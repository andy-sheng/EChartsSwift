// Ported from echarts/src/chart/graph/graphHelper.ts — keep in sync with upstream
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

// upstream imports:
//   import GraphSeriesModel from './GraphSeries';
//       -> PORT-NOTE: `GraphSeries.swift` is ported; `getNodeGlobalScale` is still typed against
//          the base `SeriesModel` (it only touches `.coordinateSystem`, an `Any?` on SeriesModel).
//   import { calcCompensationScaleToPreserveNodeSize, isViewCoordSys } from '../../coord/View';
//       -> PORT-NOTE: `coord/View.swift` is ported (`isViewCoordSys` available). Upstream's
//          `calcCompensationScaleToPreserveNodeSize` is a deferred roam export in coord/View.swift, so
//          it is inlined locally (this is its only caller); see `getNodeGlobalScale` below.
//   import { GraphNode } from '../../data/Graph';   -> data/Graph.swift (sibling port)

// Free-function module `graphHelper.ts` -> caseless enum namespace `graphHelper` (CONVENTIONS §2).
// Named exports: `getNodeGlobalScale`, `getSymbolSize`. Call sites:
//   upstream `getNodeGlobalScale(...)` -> `graphHelper.getNodeGlobalScale(...)`, etc.
public enum graphHelper {

    // export function getNodeGlobalScale(seriesModel: GraphSeriesModel)
    // PORT-NOTE: upstream parameter type is `GraphSeriesModel`; typed as the base `SeriesModel`
    //   (only `.coordinateSystem` is accessed). `GraphSeries.swift` is ported.
    public static func getNodeGlobalScale(_ seriesModel: SeriesModel) -> Double {
        let coordSys = seriesModel.coordinateSystem
        // return isViewCoordSys(coordSys)
        //     ? calcCompensationScaleToPreserveNodeSize(coordSys, seriesModel)
        //     // Geo coord sys do not use `Transformable`.
        //     // PENDING: historially `nodeScaleRatio` has not been applied on
        //     // geo based graph series.
        //     : 1;
        // PORT-NOTE: `isViewCoordSys(coordSys)` == `coordSys is View` (a View always has
        //   `type === VIEW_COORD_SYS_TYPE`). In this port Geo does NOT subclass View, so the
        //   `as? View` cast matches only the view coord sys — the geo branch falls through to `1`.
        if let view = coordSys as? View {
            return calcCompensationScaleToPreserveNodeSize(view, seriesModel)
        }
        return 1
    }

    // upstream (coord/View.ts): export function calcCompensationScaleToPreserveNodeSize(viewCoordSys, model) {
    //     const nodeScaleRatio = (model.getShallow('nodeScaleRatio', true) || 1);
    //     const viewInner = inner(viewCoordSys);
    //     // Scale node when zoom changes
    //     return ((viewInner.zoom - 1) * nodeScaleRatio + 1)
    //         / (viewInner.trans[VIEW_COORD_SYS_TRANS_OVERALL].scaleX || 1);
    // }
    // PORT-NOTE: upstream places this in `coord/View`, where it is documented as a deferred roam
    //   export (see the deferred-exports banner in coord/View.swift). It is inlined here — its only
    //   caller — because the compensation is purely a function of the view coord sys's zoom/overall
    //   scale plus the series' `nodeScaleRatio`; all inputs are reachable from the target file.
    //   `inner(viewCoordSys)` state lives directly on the `View` instance in the port (ViewInner
    //   fields are members of `View`). Dedupe if it later lands in coord/View.swift.
    private static func calcCompensationScaleToPreserveNodeSize(_ viewCoordSys: View, _ model: SeriesModel) -> Double {
        // (model.getShallow('nodeScaleRatio', true) || 1)
        let nodeScaleRatio = jsNumOrOne(model.getShallow("nodeScaleRatio", true))
        // (viewInner.trans[VIEW_COORD_SYS_TRANS_OVERALL].scaleX || 1)
        let overallScaleX = viewCoordSys.trans[VIEW_COORD_SYS_TRANS_OVERALL].scaleX
        let denom = (overallScaleX != 0 && !overallScaleX.isNaN) ? overallScaleX : 1
        return ((viewCoordSys.zoom - 1) * nodeScaleRatio + 1) / denom
    }

    // export function getSymbolSize(node: GraphNode)
    public static func getSymbolSize(_ node: GraphNode) -> Double {
        var symbolSize = node.getVisual("symbolSize")
        // if (symbolSize instanceof Array) { symbolSize = (symbolSize[0] + symbolSize[1]) / 2; }
        if let arr = symbolSize as? [Double] {
            symbolSize = (arr[0] + arr[1]) / 2
        }
        // return +symbolSize;
        return unaryPlusToNumber(symbolSize)
    }
}

// Mirrors the JS `x || 1` fallback for a numeric option: coerce to a number, and substitute `1` for
// any JS-falsy result (nil/undefined, 0, NaN, empty string). Used for `nodeScaleRatio || 1`.
private func jsNumOrOne(_ v: Any?) -> Double {
    let d = unaryPlusToNumber(v)
    return (d == 0 || d.isNaN) ? 1 : d
}

// Mirrors the JS unary-plus number coercion `+symbolSize` (numeric -> itself, numeric string ->
// its value, otherwise NaN). Not an upstream symbol.
private func unaryPlusToNumber(_ v: Any?) -> Double {
    guard let v = v else { return Double.nan }
    if v is NSNull { return Double.nan }
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let f = v as? Float { return Double(f) }
    if let b = v as? Bool { return b ? 1 : 0 }
    if let s = v as? String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return 0 }   // +'' === 0 in JS
        return Double(trimmed) ?? Double.nan
    }
    return Double.nan
}
