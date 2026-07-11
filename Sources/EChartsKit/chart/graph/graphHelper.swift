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
//       -> PORT-NOTE: `coord/View.swift` is ported (`isViewCoordSys` available);
//          `calcCompensationScaleToPreserveNodeSize` is not yet ported (see `getNodeGlobalScale`).
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
        // PORT-TODO: `coord/View.swift` (`isViewCoordSys` / `calcCompensationScaleToPreserveNodeSize`)
        //   is not ported yet. Only the non-view (geo) fallback branch (`1`) is available; wire the
        //   View branch when the `View` coordinate system is ported.
        _ = coordSys
        return 1
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
