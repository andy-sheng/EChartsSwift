// Ported from echarts/src/coord/matrix/prepareCustom.ts — keep in sync with upstream
//   NOTE: named matrixPrepareCustom.swift (not prepareCustom.swift) to avoid a SwiftPM object-name
//   collision with the other coord `prepareCustom.swift` files (duplicate basenames collide in one target).
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

// import type Matrix from './Matrix';                                  -> Matrix (coord/matrix/Matrix.swift; coord-sys master)
//
// PORT-TODO: `Matrix` (coord/matrix/Matrix.swift) is NOT ported yet — it is the coordinate-system master
//   (registered via CoordinateSystemManager.register("matrix", ...)) and lands in a later phase. The
//   surface referenced below (getRect(), dataToPoint(_ , _), dataToLayout(_ , _)) mirrors upstream
//   Matrix.ts; re-narrow once the sibling lands. Until then this file references the forward `Matrix`
//   type and does not compile standalone (staged, like the other matrix coord pieces).

// upstream: export default function matrixPrepareCustom(coordSys: Matrix) { ... }
public func matrixPrepareCustom(_ coordSys: Matrix) -> [String: Any] {
    // const rect = coordSys.getRect();
    let rect = coordSys.getRect()

    // return { coordSys: {...}, api: {...} };
    return [
        "coordSys": [
            "type": "matrix",
            "x": rect.x,
            "y": rect.y,
            "width": rect.width,
            "height": rect.height
        ] as [String: Any],
        "api": [
            // coord: function (data, opt?) { return coordSys.dataToPoint(data, opt); }
            //   `data` is Parameters<Matrix['dataToPoint']>[0] (= MatrixCoordRangeOption[]) -> `[Any]`;
            //   `opt` is the optional dataToLayout options object -> `[String: Any]?`.
            //   Returns ReturnType<Matrix['dataToPoint']> (= number[]) -> `[Double]`.
            "coord": { (data: [Any], opt: [String: Any]?) -> [Double] in
                return coordSys.dataToPoint(data, matrixDataToLayoutOptFromDict(opt))
            } as ([Any], [String: Any]?) -> [Double],
            // layout: function (data, opt?) { return coordSys.dataToLayout(data, opt); }
            //   Returns ReturnType<Matrix['dataToLayout']> (= CoordinateSystemDataLayout); modeled as the
            //   dynamic result of coordSys.dataToLayout (narrow at the custom-series call site).
            "layout": { (data: [Any], opt: [String: Any]?) -> Any in
                return coordSys.dataToLayout(data, matrixDataToLayoutOptFromDict(opt))
            } as ([Any], [String: Any]?) -> Any
        ] as [String: Any]
    ]
}

// Bridge the custom-series `api.coord(data, opt)` / `api.layout(data, opt)` loose `[String: Any]?`
// options object to the typed `MatrixDataToLayoutOpt`. `clamp` may arrive as the Int `MatrixClampOption`
// constant or its string kind ('none'|'all'|'body'|'corner', mapped via MatrixClampOption.byKind).
private func matrixDataToLayoutOptFromDict(_ opt: [String: Any]?) -> MatrixDataToLayoutOpt? {
    guard let opt = opt else { return nil }
    var out = MatrixDataToLayoutOpt()
    if let clampInt = opt["clamp"] as? Int {
        out.clamp = clampInt
    } else if let clampKind = opt["clamp"] as? String {
        out.clamp = MatrixClampOption.byKind(clampKind)
    }
    if let ignore = opt["ignoreMergeCells"] as? Bool {
        out.ignoreMergeCells = ignore
    }
    return out
}
