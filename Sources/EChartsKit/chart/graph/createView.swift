// Ported from echarts/src/chart/graph/createView.ts — keep in sync with upstream
/*
* Licensed to the Apache Software Foundation (ASF) under one
* or more contributor license agreements.  See the NOTICE file
* distributed with this work for additional information
* regarding copyright ownership.  The ASF licenses this file
* to you under the Apache License, Version 2.0 (the
* "License"); you may not use this file except in compliance
* with the License.  You may obtain a copy of the License at
*
*   http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing,
* software distributed under the License is distributed on an
* "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
* KIND, either express or implied.  See the License for the
* specific language governing permissions and limitations
* under the License.
*/

import Foundation
import ZRenderKit

// FIXME Where to create the simple view coordinate system
// upstream imports:
//   import View from '../../coord/View';
//       -> PORT-TODO: coord/View.ts NOT ported. The roam view coordinate-system object is deferred
//          this phase; this file ports the *pure box/scale computation* only (see `GraphViewBox`).
//   import {createBoxLayoutReference, getLayoutRect, applyPreserveAspect} from '../../util/layout';
//       -> `layout.createBoxLayoutReference` / `layout.getLayoutRect` (util/layout.swift).
//          `applyPreserveAspect` is NOT ported (see util/layout.swift header) -> PORT-TODO below.
//   import * as bbox from 'zrender/src/core/bbox';                   -> `bbox` (ZRenderKit Core/bbox.swift).
//   import GraphSeriesModel, { GraphNodeItemOption } from './GraphSeries';
//       -> PORT-TODO: sibling GraphSeries.swift NOT ported yet; `GraphSeriesModel` referenced as sibling.
//          `GraphNodeItemOption` is a type-only generic — dropped.
//   import ExtensionAPI from '../../core/ExtensionAPI';              -> ExtensionAPI (core/ExtensionAPI.swift).
//   import GlobalModel from '../../model/Global';                    -> GlobalModel (model/Global.swift).
//   import { extend } from 'zrender/src/core/util';                  -> `util.extend`.
//   import { injectCoordSysByOption } from '../../core/CoordinateSystem';
//       -> `injectCoordSysByOption` (core/CoordinateSystemManager.swift). Wiring deferred (needs View).
//   import { createViewCoordSysSimply } from '../../component/helper/roamHelper';
//       -> PORT-TODO: component/helper/roamHelper.ts NOT ported (roam View controller). Deferred.

// PORT-TODO: `View` (coord/View.ts) NOT ported. Upstream `createViewCoordSys` returns `View[]` and
//   registers each `View` via `injectCoordSysByOption` + `createViewCoordSysSimply`. Those are the
//   roam-view controller (parent scope: deferred this phase). This port captures the *pure box/scale
//   computation* — `getViewRect` and the min/max/aspect/bbWidth/bbHeight derivation — in `GraphViewBox`.
//   The `createViewCoordSysSimply(seriesModel, api, min[0], min[1], bbWidth, bbHeight, viewRect)` call
//   consumes exactly these fields; wiring them into a real `View` + `viewList: View[]` +
//   `injectCoordSysByOption` is left as PORT-TODO when coord/View + roamHelper land.
// PORT-TODO(coord/View.ts NOT ported): minimal stand-in for the roam `View` coordinate system that a
//   graph series carries. Upstream `createViewCoordSysSimply` builds a real `View` (with a data-rect ->
//   view-rect roam transform, `dataToPoint`/`pointToData`, `setRoamTransform`, etc.) and registers it via
//   `injectCoordSysByOption`. That full port is deferred this phase (roam interaction is deferred, §5).
//   The layout stages this phase (`circularLayout`, `simpleLayout`) only ever read `type` + `getBoundingRect()`
//   off the coord sys (the `simpleLayout` `type != 'view'` coord-projection branch and the circular drag
//   `pointToData` path are not exercised by the static render), so this stand-in supplies exactly those.
//   DEVIATION: with no roam transform, node/edge layouts are produced directly in pixel space, so
//   `getBoundingRect()` returns the *pixel* view rect (not the data-space bbox a real `View` returns) —
//   this is what makes GraphView (which applies no group transform) place nodes correctly. Replace with a
//   real `View` (separate data rect + view rect + transform) when coord/View + roamHelper land.
public final class GraphViewCoordSys: CoordinateSystem {
    public let type: String = "view"
    public var dimensions: [DimensionName] = ["x", "y"]
    public var master: CoordinateSystemMaster? = nil
    public var model: ComponentModel? = nil

    // Pixel view rect (the box the graph is laid out within). See DEVIATION note above.
    private let rect: BoundingRect
    // The node bounding box (data space) that `dataToPoint` maps onto `rect`. `getViewRect` already
    //   sized `rect` to the box's aspect ratio, so a plain box→rect stretch preserves the aspect
    //   (this is the roam-less View transform: scale + translate, zoom = 1, no pan).
    private let boxX: Double
    private let boxY: Double
    private let boxW: Double
    private let boxH: Double

    public convenience init(_ viewRect: BoundingRect) {
        // Identity box (box == viewRect) → dataToPoint is a pass-through. Kept for call sites that do not
        //   yet have the node bounding box.
        self.init(viewRect, viewRect.x, viewRect.y, viewRect.width, viewRect.height)
    }

    public init(_ viewRect: BoundingRect, _ boxX: Double, _ boxY: Double, _ boxW: Double, _ boxH: Double) {
        self.rect = BoundingRect(viewRect.x, viewRect.y, viewRect.width, viewRect.height)
        self.boxX = boxX
        self.boxY = boxY
        self.boxW = boxW > 0 ? boxW : 1
        self.boxH = boxH > 0 ? boxH : 1
    }

    public func getBoundingRect() -> BoundingRect? { return rect.clone() }
    public func getViewRect() -> BoundingRect? { return rect.clone() }

    // The roam-less View transform: map the node bounding box (data space) onto the pixel view rect.
    //   Upstream builds this via `View.setBoundingRect` + `setViewRect` (createViewCoordSysSimply).
    public func dataToPoint(_ data: CoordinateSystemDataCoord, _ opt: Any?) -> [Double] {
        var px = Double.nan, py = Double.nan
        if let p = data as? [Double], p.count >= 2 { px = p[0]; py = p[1] }
        else if let p = data as? [Any], p.count >= 2 {
            px = (p[0] as? Double) ?? Double((p[0] as? Int) ?? 0)
            py = (p[1] as? Double) ?? Double((p[1] as? Int) ?? 0)
        } else { return [Double.nan, Double.nan] }
        return [
            (px - boxX) / boxW * rect.width + rect.x,
            (py - boxY) / boxH * rect.height + rect.y
        ]
    }

    public func pointToData(_ point: [Double], _ opt: Any?) -> Any? { return point }

    public func containPoint(_ point: [Double]) -> Bool {
        return rect.contain(point[0], point[1])
    }
}

public struct GraphViewBox {
    public var x: Double        // min[0]
    public var y: Double        // min[1]
    public var width: Double    // bbWidth (max[0] - min[0])
    public var height: Double   // bbHeight (max[1] - min[1])
    public var viewRect: LayoutRect

    public init(x: Double, y: Double, width: Double, height: Double, viewRect: LayoutRect) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.viewRect = viewRect
    }
}

// function getViewRect(seriesModel, api, aspect)
private func getViewRect(_ seriesModel: GraphSeriesModel, _ api: ExtensionAPI, _ aspect: Double) -> LayoutRect {
    let layoutRef = layout.createBoxLayoutReference(seriesModel, api)
    // const option = extend(seriesModel.getBoxLayoutParams(), { aspect: aspect });
    //   `getBoxLayoutParams()` yields a `BoxLayoutOptionMixin` struct with no `aspect` slot, and the
    //   `getLayoutRect(BoxLayoutOptionMixin, …)` overload ignores `aspect` regardless, so it is passed
    //   through directly. `aspect` is consumed only by `applyPreserveAspect` (PORT-TODO below).
    let option = seriesModel.getBoxLayoutParams()
    let viewRect = layout.getLayoutRect(option, layoutRef.refContainer)
    // return applyPreserveAspect(seriesModel, viewRect, aspect);
    // PORT-TODO: `applyPreserveAspect` (util/layout.ts) NOT ported — returns the un-adjusted viewRect
    //   until it lands. `aspect` referenced to preserve the faithful call shape.
    _ = aspect
    return viewRect
}

// export default function createViewCoordSys(ecModel, api)
//   Returns the computed box/scale for each graph series. PORT-TODO: upstream returns `View[]` and
//   registers each view via `injectCoordSysByOption`; that wiring is deferred (needs coord/View +
//   roamHelper). Here we compute `GraphViewBox[]` — the pure inputs `createViewCoordSysSimply` needs.
@discardableResult
public func createViewCoordSys(_ ecModel: GlobalModel, _ api: ExtensionAPI) -> [GraphViewBox] {
    var viewList: [GraphViewBox] = []
    ecModel.eachSeriesByType("graph") { seriesModelBase, _ in
        let seriesModel = seriesModelBase as! GraphSeriesModel

        // PORT-TODO: injectCoordSysByOption({ targetModel: seriesModel, coordSysType: 'view',
        //   coordSysProvider: createViewCoordSys (inner), isDefaultDataCoordSys: true }). The provider
        //   must return a `CoordinateSystem` (the `View`), which is not ported yet. The inner
        //   `createViewCoordSys` closure below is inlined as the pure computation for now; the
        //   coord-sys registration is deferred.

        let data = seriesModel.getData()
        // const positions = data.mapArray(idx => [+itemModel.get('x'), +itemModel.get('y')]);
        let positionsAny = data.mapArray { args in
            let idx = Int(args[0] as! Double)
            let itemModel = data.getItemModel(idx)
            return [toNumber(itemModel.get("x")), toNumber(itemModel.get("y"))]
        }
        let positions: [[Double]] = positionsAny.map { $0 as! [Double] }

        // let min: number[] = []; let max: number[] = []; bbox.fromPoints(positions, min, max);
        //   `bbox.fromPoints` is value-returning in the port (out-params dropped, CONVENTIONS §3);
        //   `VectorArray` (SIMD2) mirrors the mutable `min`/`max` slots (indices [0]/[1] used below).
        var (min, max) = bbox.fromPoints(positions, VectorArray(), VectorArray())

        // If width or height is 0
        if max[0] - min[0] == 0 {
            max[0] += 1
            min[0] -= 1
        }
        if max[1] - min[1] == 0 {
            max[1] += 1
            min[1] -= 1
        }
        let aspect = (max[0] - min[0]) / (max[1] - min[1])
        // FIXME If get view rect after data processed?
        let viewRect = getViewRect(seriesModel, api, aspect)
        // Position may be NaN (e.g., in force layout), use view rect instead
        if aspect.isNaN {
            min = VectorArray(viewRect.x, viewRect.y)
            max = VectorArray(viewRect.x + viewRect.width, viewRect.y + viewRect.height)
        }

        let bbWidth = max[0] - min[0]
        let bbHeight = max[1] - min[1]

        // PORT-TODO: const viewCoordSys = createViewCoordSysSimply(
        //     seriesModel, api, min[0], min[1], bbWidth, bbHeight, viewRect);
        //   roamHelper NOT ported. The captured box below carries exactly these arguments.
        let viewCoordSys = GraphViewBox(
            x: min[0], y: min[1], width: bbWidth, height: bbHeight, viewRect: viewRect
        )

        // PORT-TODO(injectCoordSysByOption + real View deferred): assign the stand-in view coord sys onto
        //   the series so the layout stages (circular/simple) can read `type`/`getBoundingRect()`. Upstream
        //   assigns the coord sys through the CoordinateSystemManager pipeline; here we set it directly.
        seriesModel.coordinateSystem = GraphViewCoordSys(viewRect, min[0], min[1], bbWidth, bbHeight)

        viewList.append(viewCoordSys)
    }

    return viewList
}

// upstream `+itemModel.get('x')` unary-plus numeric coercion.
private func toNumber(_ value: Any?) -> Double {
    switch value {
    case let d as Double: return d
    case let i as Int: return Double(i)
    case let s as String: return Double(s) ?? Double.nan
    default: return Double.nan
    }
}
