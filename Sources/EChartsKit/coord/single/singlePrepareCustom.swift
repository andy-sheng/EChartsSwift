// Ported from echarts/src/coord/single/prepareCustom.ts — keep in sync with upstream
//   NOTE: named singlePrepareCustom.swift (not prepareCustom.swift) to avoid a SwiftPM object-name
//   collision with coord/polar/prepareCustom.swift (duplicate basenames collide in one target).
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

// import { calcBandWidth } from '../axisBand';                          -> calcBandWidth (coord/axisBand.swift)
// import Single from './Single';                                        -> Single (coord/single/Single.swift; coord-sys master, sibling this phase)
// import { bind } from 'zrender/src/core/util';                         -> util.bind — replaced by an explicit coordSys param (see below)
//
// `Single` (coord/single/Single.swift) is ported alongside this file in the same phase. It
//   exposes: getAxis() (-> SingleAxis, an Axis with `type` / `dataToCoord`), getRect() (-> RectLike),
//   dataToPoint(_ , _). Re-narrow if the sibling surface differs.

// upstream:
// function dataToCoordSize(this: Single, dataSize: number | number[], dataItem: number | number[]) { ... }
//   Bound to the coord sys via `bind(dataToCoordSize, coordSys)` at the `size` api below; ported as a
//   free function taking `coordSys` explicitly (replaces the JS `this` binding). `dataSize` / `dataItem`
//   are `number | number[]` (no Swift union) → modeled as `Any` and split by the `instanceof Array` checks.
private func dataToCoordSize(_ coordSys: Single, _ dataSize: Any, _ dataItem: Any) -> Double {
    // dataItem is necessary in log axis.
    // const axis = this.getAxis();
    let axis: Axis = coordSys.getAxis()
    // const val = dataItem instanceof Array ? dataItem[0] : dataItem;
    let val: Double = (numOpt((dataItem as? [Any])?.first) ?? numOpt(dataItem)) ?? 0
    // const halfSize = (dataSize instanceof Array ? dataSize[0] : dataSize) / 2;
    let halfSize: Double = ((numOpt((dataSize as? [Any])?.first) ?? numOpt(dataSize)) ?? 0) / 2
    // return axis.type === 'category'
    //     ? calcBandWidth(axis).w
    //     : Math.abs(axis.dataToCoord(val - halfSize) - axis.dataToCoord(val + halfSize));
    return axis.type == "category"
        ? calcBandWidth(axis).w
        : abs(axis.dataToCoord(val - halfSize) - axis.dataToCoord(val + halfSize))
}

// upstream: export default function singlePrepareCustom(coordSys: Single) { ... }
public func singlePrepareCustom(_ coordSys: Single) -> [String: Any] {
    // const rect = coordSys.getRect();
    //   `coordSys` is the concrete `Single`, whose `getRect() -> LayoutRect` is non-optional
    //   (upstream returns a non-null BoundingRect; the rect is set by resize()). Call it WITHOUT `!`: a
    //   trailing `!` would force overload resolution onto the nil-returning `CoordinateSystem.getRect()
    //   -> RectLike?` protocol default (the concrete method does not witness the optional requirement),
    //   crashing at runtime — the protocol-witness/force-unwrap trap.
    let rect = coordSys.getRect()

    // return { coordSys: {...}, api: {...} };
    return [
        "coordSys": [
            "type": "singleAxis",
            "x": rect.x,
            "y": rect.y,
            "width": rect.width,
            "height": rect.height
        ] as [String: Any],
        "api": [
            // coord: function (val: number) { return coordSys.dataToPoint(val); }
            //   // do not provide "out" param
            "coord": { (val: Double) -> [Double] in
                return coordSys.dataToPoint(val)
            } as (Double) -> [Double],
            // size: bind(dataToCoordSize, coordSys)
            "size": { (dataSize: Any, dataItem: Any) -> Double in
                return dataToCoordSize(coordSys, dataSize, dataItem)
            } as (Any, Any) -> Double
        ] as [String: Any]
    ]
}

// Coerce a dynamic value to Double, tolerating Int boxing (`number | number[]` custom-series inputs are
// boxed as Int or Double in `Any`). A bare `as? Double` returns nil on an Int, silently dropping the
// value — the recurring Int-vs-Double read trap (CONVENTIONS trap 1).
private func numOpt(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber, !(n === kCFBooleanTrue || n === kCFBooleanFalse) { return n.doubleValue }
    return nil
}
