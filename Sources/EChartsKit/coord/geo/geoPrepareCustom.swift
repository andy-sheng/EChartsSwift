// Ported from echarts/src/coord/geo/prepareCustom.ts — keep in sync with upstream
//   NOTE: named geoPrepareCustom.swift (not prepareCustom.swift) to avoid a SwiftPM object-name collision
//   with coord/polar/prepareCustom.swift (duplicate basenames collide in one target).
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

// import * as zrUtil from 'zrender/src/core/util';                      -> `util.*` (ZRenderKit) / inline
// import Geo from './Geo';                                              -> Geo (coord/geo/Geo.swift; coord-sys master)
// import { viewCoordSysGetZoomOption } from '../View';                  -> viewCoordSysGetZoomOption (coord/View.swift; a free function, not View.*)
//
// `Geo` (coord/geo/Geo.swift, the GEO coordinate-system master — the 7th coord system, projects
//   [lng, lat] -> pixel), `View` (coord/View.swift), and `viewCoordSysGetZoomOption(_:)` are ALL ported.
//   NOTE: the ported `Geo.dataToPoint(_:_:)` returns `[Double]?` (upstream returns `number[]`); the Optional
//   is unwrapped (`?? []` / `?[i] ?? 0`) below to keep the upstream non-optional shape at the custom-API seam.

// upstream:
// function dataToCoordSize(this: Geo, dataSize: number[], dataItem: number[]): number[] {
//     dataItem = dataItem || [0, 0];
//     return zrUtil.map([0, 1], function (dimIdx) { ... }, this);
// }
//   The bound `this: Geo` -> explicit leading `coordSys: Geo` param (zrUtil.bind capture below).
private func dataToCoordSize(_ coordSys: Geo, _ dataSize: [Double], _ dataItem: [Double]?) -> [Double] {
    // dataItem = dataItem || [0, 0];
    //   JS `||` only falls back on a falsy `dataItem` (null/undefined); a non-nil array (even empty) is
    //   truthy and is kept -> `?? [0, 0]` (do NOT treat [] as absent).
    let dataItem: [Double] = dataItem ?? [0, 0]
    // return zrUtil.map([0, 1], function (dimIdx) { ... }, this);
    return [0, 1].map { (dimIdx: Int) -> Double in
        // const val = dataItem[dimIdx];
        let val = dataItem[dimIdx]
        // const halfSize = dataSize[dimIdx] / 2;
        let halfSize = dataSize[dimIdx] / 2
        // const p1 = []; const p2 = [];
        var p1: [Double] = [0, 0]
        var p2: [Double] = [0, 0]
        // p1[dimIdx] = val - halfSize;
        p1[dimIdx] = val - halfSize
        // p2[dimIdx] = val + halfSize;
        p2[dimIdx] = val + halfSize
        // p1[1 - dimIdx] = p2[1 - dimIdx] = dataItem[1 - dimIdx];
        p1[1 - dimIdx] = dataItem[1 - dimIdx]
        p2[1 - dimIdx] = dataItem[1 - dimIdx]
        // return Math.abs(this.dataToPoint(p1)[dimIdx] - this.dataToPoint(p2)[dimIdx]);
        //   ported Geo.dataToPoint returns [Double]? -> `?[dimIdx] ?? 0` (upstream is non-optional).
        return Swift.abs((coordSys.dataToPoint(p1)?[dimIdx] ?? 0) - (coordSys.dataToPoint(p2)?[dimIdx] ?? 0))
    }
}

// upstream: export default function geoPrepareCustom(coordSys: Geo) { ... }
public func geoPrepareCustom(_ coordSys: Geo) -> [String: Any] {
    // const viewCoordSys = coordSys.view;
    //   coordSys.view is an IUO (`View!`); bind to a non-optional `View` for the calls below.
    let viewCoordSys: View = coordSys.view
    // const rect = viewCoordSys.getBoundingRect();
    let rect = viewCoordSys.getBoundingRect()
    // return { coordSys: {...}, api: {...} };
    return [
        "coordSys": [
            "type": "geo",
            "x": rect.x,
            "y": rect.y,
            "width": rect.width,
            "height": rect.height,
            "zoom": viewCoordSysGetZoomOption(viewCoordSys)
        ] as [String: Any],
        "api": [
            // coord: function (data: number[]): number[] {
            //     // do not provide "out" and noRoam param,
            //     // Compatible with this usage:
            //     // echarts.util.map(item.points, api.coord)
            //     return coordSys.dataToPoint(data);
            // }
            "coord": { (data: [Double]) -> [Double] in
                return coordSys.dataToPoint(data) ?? []
            } as ([Double]) -> [Double],
            // size: zrUtil.bind(dataToCoordSize, coordSys)
            "size": { (dataSize: [Double], dataItem: [Double]?) -> [Double] in
                return dataToCoordSize(coordSys, dataSize, dataItem)
            } as ([Double], [Double]?) -> [Double]
        ] as [String: Any]
    ]
}
