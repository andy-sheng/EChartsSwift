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
//       -> PORT-NOTE: coord/View.swift is ported. This file still uses a stand-in view coord sys and
//          ports the *pure box/scale computation* only (see `GraphViewBox`).
//   import {createBoxLayoutReference, getLayoutRect, applyPreserveAspect} from '../../util/layout';
//       -> `layout.createBoxLayoutReference` / `layout.getLayoutRect` / `layout.applyPreserveAspect`
//          (all ported in util/layout.swift; wired in `getViewRect` below).
//   import * as bbox from 'zrender/src/core/bbox';                   -> `bbox` (ZRenderKit Core/bbox.swift).
//   import GraphSeriesModel, { GraphNodeItemOption } from './GraphSeries';
//       -> PORT-NOTE: GraphSeries.swift is ported; `GraphSeriesModel` referenced as sibling.
//          `GraphNodeItemOption` is a type-only generic — dropped.
//   import ExtensionAPI from '../../core/ExtensionAPI';              -> ExtensionAPI (core/ExtensionAPI.swift).
//   import GlobalModel from '../../model/Global';                    -> GlobalModel (model/Global.swift).
//   import { extend } from 'zrender/src/core/util';                  -> `util.extend`.
//   import { injectCoordSysByOption } from '../../core/CoordinateSystem';
//       -> `injectCoordSysByOption` (core/CoordinateSystemManager.swift). Wiring deferred (needs View).
//   import { createViewCoordSysSimply } from '../../component/helper/roamHelper';
//       -> PORT-NOTE: roamHelper is ported (component/helper/roamHelper*.swift); createViewCoordSysSimply is not used here (stand-in instead).

// PORT-NOTE: `View` (coord/View.swift) is ported. Upstream `createViewCoordSys` returns `View[]` and
//   registers each `View` via `injectCoordSysByOption` + `createViewCoordSysSimply`. Those are the
//   roam-view controller (parent scope: deferred this phase). This port captures the *pure box/scale
//   computation* — `getViewRect` and the min/max/aspect/bbWidth/bbHeight derivation — in `GraphViewBox`.
//   The `createViewCoordSysSimply(seriesModel, api, min[0], min[1], bbWidth, bbHeight, viewRect)` call
//   consumes exactly these fields; wiring them into a real `View` + `viewList: View[]` +
//   `injectCoordSysByOption` is not used here (the stand-in is set directly); coord/View + roamHelper are ported.
// PORT-NOTE(coord/View.swift is ported; this file keeps a stand-in): minimal stand-in for the roam `View` coordinate system that a
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

    // ------------------------------------------------------------------------------------------------
    // ROAM (VIEW_COORD_SYS_TRANS_ROAM). Upstream a real `View` composes a raw (dataRect→viewRect) map
    //   with a roam (center/zoom) transform → VIEW_COORD_SYS_TRANS_OVERALL. This stand-in reproduces the
    //   same OVERALL affine as a pure scale+translate (the box→rect map has no rotation), so a graph can
    //   pan/zoom. `roamCenter` is a point in DATA space that maps to the center of the view rect;
    //   `roamZoom` is the scale (== 1, identity roam, in the static render). See `applyRoamPayload`.
    // ------------------------------------------------------------------------------------------------
    public var roamCenter: [Double]? = nil          // VIEW_COORD_SYS center (data space).
    public var roamZoom: Double = 1                  // VIEW_COORD_SYS zoom.

    // The raw box→rect linear map as scale + translate (px = rawScale*data + rawT).
    private var rawScaleX: Double { rect.width / boxW }
    private var rawScaleY: Double { rect.height / boxH }
    private var rawTx: Double { rect.x - boxX * rawScaleX }
    private var rawTy: Double { rect.y - boxY * rawScaleY }
    private var viewCenterX: Double { rect.x + rect.width / 2 }
    private var viewCenterY: Double { rect.y + rect.height / 2 }

    // OVERALL affine = roam(center, zoom) ∘ raw. Returns (scaleX, scaleY, translateX, translateY).
    //   Mirrors View's `viewCoordSysUpdateRoamTrans` + `calcOverallTrans`.
    private func overallTransform() -> (sx: Double, sy: Double, tx: Double, ty: Double) {
        let zoom = roamZoom
        // roamViewCenter = raw(center) or the view-rect center (upstream `viewCoordSysUpdateRoamTrans`).
        let rvcx: Double
        let rvcy: Double
        if let c = roamCenter, c.count >= 2, c[0].isFinite, c[1].isFinite {
            rvcx = rawScaleX * c[0] + rawTx
            rvcy = rawScaleY * c[1] + rawTy
        } else {
            rvcx = viewCenterX
            rvcy = viewCenterY
        }
        let roamTx = viewCenterX - zoom * rvcx
        let roamTy = viewCenterY - zoom * rvcy
        let sx = zoom * rawScaleX
        let sy = zoom * rawScaleY
        // overallT = roamT + zoom * rawT.
        let tx = roamTx + zoom * rawTx
        let ty = roamTy + zoom * rawTy
        return (sx, sy, tx, ty)
    }

    // upstream coord/View.ts: `getBoundingRect()` returns "a rect in DATA space" (the node bounding box
    //   `dataToPoint` maps onto the pixel view rect), NOT the pixel view rect. The circular/force layout
    //   stages compute cx/cy/r from `coordSys.getBoundingRect()` and lay nodes out in that space; GraphView
    //   then maps them to pixels with `dataToPoint` (fitPoint). Returning the PIXEL rect here made
    //   circularLayout place nodes in pixel space, which `dataToPoint` then transformed a SECOND time —
    //   collapsing the `layout:'circular'` graph into a small offset blob. Return the data box, per upstream.
    //   (When the nodes carry no x/y — e.g. a bare force layout — the box equals the view rect, so this is a
    //   no-op there.) `getViewRect` keeps returning the pixel rect (upstream's VIEW_COORD_SYS_TRANS_RAW view rect).
    public func getBoundingRect() -> BoundingRect? { return BoundingRect(boxX, boxY, boxW, boxH) }
    public func getViewRect() -> BoundingRect? { return rect.clone() }

    // The View transform (raw + roam): map the node bounding box (data space) onto the pixel view rect,
    //   then apply the roam (pan/zoom). Upstream: `View.dataToPoint` reading VIEW_COORD_SYS_TRANS_OVERALL.
    public func dataToPoint(_ data: CoordinateSystemDataCoord, _ opt: Any?) -> [Double] {
        var px = Double.nan, py = Double.nan
        if let p = data as? [Double], p.count >= 2 { px = p[0]; py = p[1] }
        else if let p = data as? [Any], p.count >= 2 {
            px = (p[0] as? Double) ?? Double((p[0] as? Int) ?? 0)
            py = (p[1] as? Double) ?? Double((p[1] as? Int) ?? 0)
        } else { return [Double.nan, Double.nan] }
        let o = overallTransform()
        return [o.sx * px + o.tx, o.sy * py + o.ty]
    }

    // Apply a roam payload (pan dx/dy and/or zoom scale about origin) to the OVERALL transform, then sync
    //   back to (center, zoom) — the single source of truth (upstream `applyRoamPayloadToOverallTrans` +
    //   `syncBackToRoamOptionFromRoamTrans`). Returns the NEW (center in data space, zoom). Pure (does not
    //   mutate self); the caller stores the result so the next `createViewCoordSys` rebuild reflects it.
    public func applyRoamPayload(
        _ dx: Double?, _ dy: Double?,
        _ zoomScale: Double?, _ originX: Double, _ originY: Double,
        _ zoomLimit: RoamOptionMixin.ScaleLimit?
    ) -> (center: [Double], zoom: Double) {
        var (sx, sy, tx, ty) = overallTransform()

        // pan — dx/dy are applied in pixel space (upstream: `targetOverallTrans.x += payload.dx`).
        if let dx = dx, let dy = dy {
            tx += dx
            ty += dy
        }
        // zoom about the mouse origin (upstream: keep the mouse center when scaling).
        if let scale = zoomScale {
            let oldZoom = roamZoom
            let newZoom = clampByZoomLimit(oldZoom * scale, zoomLimit)
            let dz = oldZoom != 0 ? newZoom / oldZoom : 1
            tx -= (originX - tx) * (dz - 1)
            ty -= (originY - ty) * (dz - 1)
            sx *= dz
            sy *= dz
        }

        // sync back: recover zoom + center (data space) from the mutated OVERALL affine.
        let newZoom = rawScaleX != 0 ? sx / rawScaleX : roamZoom
        let roamTx = tx - newZoom * rawTx
        let roamTy = ty - newZoom * rawTy
        let cvx = newZoom != 0 ? (viewCenterX - roamTx) / newZoom : viewCenterX
        let cvy = newZoom != 0 ? (viewCenterY - roamTy) / newZoom : viewCenterY
        let cdx = rawScaleX != 0 ? (cvx - rawTx) / rawScaleX : 0
        let cdy = rawScaleY != 0 ? (cvy - rawTy) / rawScaleY : 0
        return ([cdx, cdy], newZoom)
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
    //   `aspect` is not a field of `BoxLayoutOptionMixin`; rebuilt as a `[String: Any]` bag (+ aspect)
    //   so `layout.getLayoutRect`'s dynamic overload reads it, preserving upstream behavior
    //   (mirrors coord/geo/geoCreator.swift).
    let box = seriesModel.getBoxLayoutParams()
    var option: [String: Any] = [:]
    if let v = box.left { option["left"] = v }
    if let v = box.top { option["top"] = v }
    if let v = box.right { option["right"] = v }
    if let v = box.bottom { option["bottom"] = v }
    if let v = box.width { option["width"] = v }
    if let v = box.height { option["height"] = v }
    option["aspect"] = aspect
    let viewRect = layout.getLayoutRect(option, layoutRef.refContainer)
    // return applyPreserveAspect(seriesModel, viewRect, aspect);
    return layout.applyPreserveAspect(seriesModel, viewRect, aspect)
}

// export default function createViewCoordSys(ecModel, api)
//   Returns the computed box/scale for each graph series. PORT-NOTE: upstream returns `View[]` and
//   registers each view via `injectCoordSysByOption`; that wiring is deferred (needs coord/View +
//   roamHelper). Here we compute `GraphViewBox[]` — the pure inputs `createViewCoordSysSimply` needs.
@discardableResult
public func createViewCoordSys(_ ecModel: GlobalModel, _ api: ExtensionAPI) -> [GraphViewBox] {
    var viewList: [GraphViewBox] = []
    ecModel.eachSeriesByType("graph") { seriesModelBase, _ in
        let seriesModel = seriesModelBase as! GraphSeriesModel

        // PORT-NOTE: injectCoordSysByOption({ targetModel: seriesModel, coordSysType: 'view',
        //   coordSysProvider: createViewCoordSys (inner), isDefaultDataCoordSys: true }). Both
        //   injectCoordSysByOption and the `View` provider are ported; this file inlines the pure
        //   computation and sets the stand-in coord sys directly instead of registering through the
        //   manager pipeline.

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

        // PORT-NOTE: const viewCoordSys = createViewCoordSysSimply(
        //     seriesModel, api, min[0], min[1], bbWidth, bbHeight, viewRect);
        //   createViewCoordSysSimply (roamHelper) is ported but not used here; the captured box below
        //   carries exactly these arguments.
        let viewCoordSys = GraphViewBox(
            x: min[0], y: min[1], width: bbWidth, height: bbHeight, viewRect: viewRect
        )

        // PORT-NOTE(injectCoordSysByOption + real View are ported; stand-in used here): assign the stand-in view coord sys onto
        //   the series so the layout stages (circular/simple) can read `type`/`getBoundingRect()`. Upstream
        //   assigns the coord sys through the CoordinateSystemManager pipeline; here we set it directly.
        let graphCoordSys = GraphViewCoordSys(viewRect, min[0], min[1], bbWidth, bbHeight)
        // ROAM: seed the coord sys with the current roam (center/zoom). The roam state is the single source
        //   of truth carried across `update()` rebuilds (upstream `viewCoordSysSetRoamOptionFromModel`
        //   reads center/zoom from the model each rebuild; here they live in a per-series inner store that
        //   the `graphRoam` action writes, seeded from the series option on first build). See roamHelperGraph.
        graphRoamApplyStateToCoordSys(seriesModel, graphCoordSys)
        seriesModel.coordinateSystem = graphCoordSys

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
