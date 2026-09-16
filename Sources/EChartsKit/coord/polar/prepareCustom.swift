// Ported from echarts/src/coord/polar/prepareCustom.ts — keep in sync with upstream
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

// import * as zrUtil from 'zrender/src/core/util';                    -> util.* (ZRenderKit)
// import Polar from './Polar';                                        -> Polar (coord/polar/Polar.swift; the coord-sys master, sibling this phase)
// import RadiusAxis from './RadiusAxis';                              -> RadiusAxis (coord/polar/RadiusAxis.swift; sibling this phase)
// import { calcBandWidth } from '../axisBand';                        -> calcBandWidth (coord/axisBand.swift)
// // import AngleAxis from './AngleAxis';                             (commented out upstream too)
//
// `Polar` / `RadiusAxis` / `AngleAxis` (coord/polar/{Polar,RadiusAxis,AngleAxis}.swift) are
//   the polar coordinate-system classes ported alongside this file in the same phase. They expose:
//     Polar:      cx, cy, getRadiusAxis(), getAngleAxis(), coordToPoint([radius, angle]) -> [Double]
//     RadiusAxis: dataToRadius(_), getExtent() -> [Double], dataToCoord(_) , type  (extends Axis)
//     AngleAxis:  dataToAngle(_) , dataToCoord(_) , type                          (extends Axis)
//   Re-narrow / re-wire once those siblings land if their surface differs.

// upstream:
// function dataToCoordSize(this: Polar, dataSize: number[], dataItem: number[]) { ... }
//   Bound to the coord sys via `zrUtil.bind(dataToCoordSize, coordSys)` at the `size` api below; ported as
//   a free function taking `coordSys` explicitly (replaces the JS `this` binding).
private func dataToCoordSize(_ coordSys: Polar, _ dataSize: [Double], _ dataItemIn: [Double]?) -> [Double] {
    // dataItem is necessary in log axis.
    // dataItem = dataItem || [0, 0];
    let dataItem: [Double] = jsTruthyArray(dataItemIn) ? dataItemIn! : [0, 0]

    // return zrUtil.map(['Radius', 'Angle'], function (dim, dimIdx) { ... }, this);
    //   dim iterates 'Radius' (dimIdx 0) then 'Angle' (dimIdx 1). The dynamic `this['get'+dim+'Axis']()`
    //   dispatch is ported as an explicit switch on the dimension.
    return util.map(["Radius", "Angle"]) { (dim: String, dimIdx: Int) -> Double in
        // const getterName = 'get' + dim + 'Axis';
        // const axis = this[getterName]() as RadiusAxis;   // TODO: TYPE Check Angle Axis
        //   both RadiusAxis and AngleAxis extend the base `Axis`; `calcBandWidth` / `dataToCoord`
        //   / `type` are on that base, so `axis` is typed as `Axis` here.
        let axis: Axis = (dim == "Radius") ? coordSys.getRadiusAxis() : coordSys.getAngleAxis()
        // const val = dataItem[dimIdx];
        let val = dataItem[dimIdx]
        // const halfSize = dataSize[dimIdx] / 2;
        let halfSize = dataSize[dimIdx] / 2

        // let result = axis.type === 'category'
        //     ? calcBandWidth(axis).w
        //     : Math.abs(axis.dataToCoord(val - halfSize) - axis.dataToCoord(val + halfSize));
        var result = axis.type == "category"
            ? calcBandWidth(axis).w
            : abs(axis.dataToCoord(val - halfSize) - axis.dataToCoord(val + halfSize))

        // if (dim === 'Angle') { result = result * Math.PI / 180; }
        if dim == "Angle" {
            result = result * Double.pi / 180
        }

        // return result;
        return result
    }
}

// upstream: export default function polarPrepareCustom(coordSys: Polar) { ... }
public func polarPrepareCustom(_ coordSys: Polar) -> [String: Any] {
    // const radiusAxis = coordSys.getRadiusAxis();
    let radiusAxis = coordSys.getRadiusAxis()
    // const angleAxis = coordSys.getAngleAxis();
    let angleAxis = coordSys.getAngleAxis()
    // const radius = radiusAxis.getExtent();
    // radius[0] > radius[1] && radius.reverse();
    //   `getExtent()` returns a fresh array; `reverse()` mutates it in place (JS). Ported with a mutable copy.
    var radius = radiusAxis.getExtent()
    if radius[0] > radius[1] {
        radius.reverse()
    }

    // return { coordSys: {...}, api: {...} };
    return [
        "coordSys": [
            "type": "polar",
            "cx": coordSys.cx,
            "cy": coordSys.cy,
            "r": radius[1],
            "r0": radius[0]
        ] as [String: Any],
        "api": [
            // coord: function (data: number[]) { ... }
            "coord": { (data: [Double]) -> [Double] in
                // const radius = radiusAxis.dataToRadius(data[0]);   (shadows the outer extent `radius`)
                let radiusVal = radiusAxis.dataToRadius(data[0])
                // const angle = angleAxis.dataToAngle(data[1]);
                let angle = angleAxis.dataToAngle(data[1])
                // const coord = coordSys.coordToPoint([radius, angle]);
                var coord = coordSys.coordToPoint([radiusVal, angle])
                // coord.push(radius, angle * Math.PI / 180);
                coord.append(radiusVal)
                coord.append(angle * Double.pi / 180)
                // return coord;
                return coord
            } as ([Double]) -> [Double],
            // size: zrUtil.bind(dataToCoordSize, coordSys)
            "size": { (dataSize: [Double], dataItem: [Double]?) -> [Double] in
                return dataToCoordSize(coordSys, dataSize, dataItem)
            } as ([Double], [Double]?) -> [Double]
        ] as [String: Any]
    ]
}

// JS truthiness for the `dataItem || [0, 0]` guard: a nil/empty `dataItem` is falsy.
// mirrors the jsTruthy helpers used across the port (CONVENTIONS §6); an empty array is
//   truthy in JS (only nil/undefined here triggers the fallback), so only nil is treated as falsy.
private func jsTruthyArray(_ value: [Double]?) -> Bool {
    return value != nil
}
