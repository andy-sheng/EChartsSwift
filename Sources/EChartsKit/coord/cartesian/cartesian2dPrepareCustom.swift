// Ported from echarts/src/coord/cartesian/prepareCustom.ts — keep in sync with upstream
//   NOTE: named cartesian2dPrepareCustom.swift (not prepareCustom.swift) to avoid a SwiftPM object-name
//   collision with coord/polar/prepareCustom.swift (duplicate basenames collide in one target — see the
//   port memo "SwiftPM port mechanical traps").
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

// import Cartesian2D, { cartesian2DDimensions } from './Cartesian2D';  -> Cartesian2D / cartesian2DDimensions
// import { CoordinateSystem } from ...                                 -> (unused: the closures capture `coordSys`)
//
// The two closures' Swift signatures MUST match the casts CustomChartView.makeRenderItem performs on the
//   `prepareResult.api` bag:
//       coord: prepareApi["coord"] as? ([Double]) -> [Double]
//       size:  prepareApi["size"]  as? ([Double], [Double]?) -> [Double]
//   so `api.coord(...)` / `api.size(...)` resolve to non-nil closures (custom-on-cartesian).

// upstream:
// function dataToCoordSize(this: Cartesian2D, dataSize: number[], dataItem: number[]): number[] {
//     dataItem = dataItem || [0, 0];
//     return map(['x', 'y'], function (dim, dimIdx) {
//         const axis = this.getAxis(dim);
//         const val = dataItem[dimIdx];
//         const halfSize = dataSize[dimIdx] / 2;
//         return axis.type === 'category'
//             ? calcBandWidth(axis).w
//             : Math.abs(axis.dataToCoord(val - halfSize) - axis.dataToCoord(val + halfSize));
//     });
// }
// pinned upstream (echarts 6.1.0) uses `calcBandWidth(axis).w` here (breaks/statistics-aware),
//   not the deprecated `axis.getBandWidth()`. Mirrors the polar/single prepareCustom siblings.
private func dataToCoordSize(_ coordSys: Cartesian2D, _ dataSize: [Double], _ dataItem: [Double]?) -> [Double] {
    let item = dataItem ?? [0, 0]
    return cartesian2DDimensions.enumerated().map { (dimIdx, dim) -> Double in
        // const axis = this.getAxis(dim);
        guard let axis = coordSys.getAxis(dim) else { return 0 }
        // const val = dataItem[dimIdx];
        let val = dimIdx < item.count ? item[dimIdx] : 0
        // const halfSize = dataSize[dimIdx] / 2;
        let halfSize = (dimIdx < dataSize.count ? dataSize[dimIdx] : 0) / 2
        // axis.type === 'category' ? calcBandWidth(axis).w : abs(dataToCoord(val - h) - dataToCoord(val + h))
        return axis.type == "category"
            ? calcBandWidth(axis).w
            : abs(axis.dataToCoord(val - halfSize) - axis.dataToCoord(val + halfSize))
    }
}

// upstream: export default function cartesian2DPrepareCustom(coordSys: Cartesian2D) { ... }
public func cartesian2dPrepareCustom(_ coordSys: Cartesian2D) -> [String: Any] {
    // const rect = coordSys.master.getRect();
    //   `master` is stored as the protocol type `CoordinateSystemMaster?`; the concrete master is a Grid
    //   whose `getRect()` returns a non-optional LayoutRect (BoundingRect).
    guard let grid = coordSys.master as? Grid else {
        // No master resized yet — return an empty bag (api.coord/api.size will be nil-cast downstream).
        return [:]
    }
    let rect = grid.getRect()

    // return { coordSys: {...}, api: {...} };
    return [
        "coordSys": [
            "type": "cartesian2d",
            "x": rect.x,
            "y": rect.y,
            "width": rect.width,
            "height": rect.height
        ] as [String: Any],
        "api": [
            // coord(data, clamp) { return coordSys.dataToPoint(data, clamp); }  // do not provide "out" param
            "coord": { (data: [Double]) -> [Double] in
                return coordSys.dataToPoint(data)
            } as ([Double]) -> [Double],
            // size: bind(dataToCoordSize, coordSys)
            "size": { (dataSize: [Double], dataItem: [Double]?) -> [Double] in
                return dataToCoordSize(coordSys, dataSize, dataItem)
            } as ([Double], [Double]?) -> [Double]
        ] as [String: Any]
    ]
}
