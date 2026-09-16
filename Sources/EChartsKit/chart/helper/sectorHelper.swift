// Ported from echarts/src/chart/helper/sectorHelper.ts — keep in sync with upstream
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
//   import type Model from '../../model/Model';                       -> `Model` (model/Model.swift).
//   import type Sector from 'zrender/src/graphic/shape/Sector';        -> `Sector` / `SectorShape` (ZRenderKit).
//   import { isArray, map } from 'zrender/src/core/util';              -> `util.isArray` / `util.map` (ZRenderKit).
//   import { parsePercent } from 'zrender/src/contain/text';           -> `number.parsePercent` (util/number.swift;
//       upstream imports the `contain/text` re-export of the same `parsePercent`).

// upstream:
//   export function getSectorCornerRadius(
//       model: Model<{ borderRadius?: string | number | (string | number)[] }>,
//       shape: Pick<Sector['shape'], 'r0' | 'r'>,
//       zeroIfNull?: boolean
//   )
//
// upstream returns `{ cornerRadius: number | number[] } | { cornerRadius: 0 } | null`; the
//   callers `zrUtil.extend(sectorShape, cornerRadius)` merge it onto a `SectorShape`. The Swift
//   `SectorShape.cornerRadius` is the `CornerRadius` union enum, so this returns `CornerRadius?`
//   (nil == upstream `null`) and callers assign it onto `sectorShape.cornerRadius` when non-nil.
public func getSectorCornerRadius(
    _ model: Model,
    _ shape: SectorShape,
    _ zeroIfNull: Bool? = nil
) -> CornerRadius? {
    // let cornerRadius = model.get('borderRadius');
    var cornerRadius = model.get("borderRadius")
    if cornerRadius == nil {
        // return zeroIfNull ? { cornerRadius: 0 } : null;
        return (zeroIfNull ?? false) ? .number(0) : nil
    }
    // if (!isArray(cornerRadius)) { cornerRadius = [cornerRadius, cornerRadius, cornerRadius, cornerRadius]; }
    if !util.isArray(cornerRadius) {
        cornerRadius = [cornerRadius as Any, cornerRadius as Any, cornerRadius as Any, cornerRadius as Any]
    }
    // const dr = Math.abs(shape.r || 0 - shape.r0 || 0);
    //   NOTE (upstream operator-precedence quirk faithfully preserved): `-` binds tighter than `||`, so
    //   this parses as `shape.r || (0 - shape.r0) || 0` — i.e. the first JS-truthy of r, (-r0), 0.
    let dr = Swift.abs(zrNumberTruthy(shape.r) ? shape.r
        : (zrNumberTruthy(0 - shape.r0) ? (0 - shape.r0) : 0))
    // return { cornerRadius: map(cornerRadius, cr => parsePercent(cr, dr)) };
    let arr = cornerRadius as? [Any] ?? []
    return .array(util.map(arr) { cr, _ in number.parsePercent(cr, dr) })
}

// JS number truthiness: nonzero and non-NaN. Helper for the `||` chain above.
private func zrNumberTruthy(_ x: Double) -> Bool {
    return x != 0 && !x.isNaN
}
