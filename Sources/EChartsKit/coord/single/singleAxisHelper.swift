// Ported from echarts/src/coord/single/singleAxisHelper.ts — keep in sync with upstream
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
//   import * as zrUtil from 'zrender/src/core/util';                          -> `util.*` (ZRenderKit).
//   import SingleAxisModel from './AxisModel';                                -> SingleAxisModel
//       (coord/single/SingleAxisModel.swift; exposes `coordinateSystem: CoordinateSystemMaster?` and the
//       inherited `axis: Any` — both narrowed to their concrete Single/SingleAxis types below).
//   import { AxisBuilderCfg } from '../../component/axis/AxisBuilder';        -> AxisBuilderCfg (component/axis/AxisBuilder.swift).

// upstream:
//   interface LayoutResult {
//       position: AxisBuilderCfg['position'],
//       rotation: AxisBuilderCfg['rotation']
//       labelRotate: AxisBuilderCfg['labelRotate']
//       labelDirection: AxisBuilderCfg['labelDirection']
//       tickDirection: AxisBuilderCfg['tickDirection']
//       nameDirection: AxisBuilderCfg['nameDirection']
//       z2: number
//   }
//   Every field of `LayoutResult` is an `AxisBuilderCfg` field, and upstream passes the result directly to
//   `new AxisBuilder(axisModel, api, layout)` (relying on structural typing). The Swift `AxisBuilder` init
//   takes a concrete `AxisBuilderCfg`, and `SingleAxisView` forwards this result to it verbatim, so
//   `layout` returns an `AxisBuilderCfg` directly (CONVENTIONS §4). The extra `z2: 1` upstream field is
//   not part of `AxisBuilderCfg` and is unused by `SingleAxisView`, so it is dropped (mirrors the cartesian
//   port dropping `CartesianAxisLayout.z2` when building `AxisBuilderCfg`).

// upstream: the `opt?` bag `{ labelInside?: boolean }` of `layout` → struct (CONVENTIONS §4).
public struct SingleAxisLayoutOpt {
    public var labelInside: Bool?
    public init(labelInside: Bool? = nil) {
        self.labelInside = labelInside
    }
}

// upstream free-function module → caseless enum namespace named after the file (CONVENTIONS §2).
//   (Named `singleAxisHelper`, not `layout`, to avoid colliding with the existing `enum layout`
//   namespace in util/layout.swift.)
public enum singleAxisHelper {

    // upstream: export function layout(axisModel: SingleAxisModel, opt?: { labelInside?: boolean }): LayoutResult
    public static func layout(
        _ axisModel: SingleAxisModel,
        _ opt: SingleAxisLayoutOpt? = nil
    ) -> AxisBuilderCfg {
        // opt = opt || {};
        let opt = opt ?? SingleAxisLayoutOpt()
        // const single = axisModel.coordinateSystem;
        //   `SingleAxisModel.coordinateSystem` is typed `CoordinateSystemMaster?` (Swift cannot narrow it
        //   to `Single`), so downcast to the concrete `Single` — needed to reach `Single.getRect()` (the
        //   protocol's optional `getRect()` would resolve to its nil default otherwise, cf. Grid).
        let single = axisModel.coordinateSystem as! Single
        // const axis = axisModel.axis;
        //   `AxisBaseModel.axis` is typed `Any` (Swift cannot narrow an inherited stored property to
        //   `SingleAxis`); narrow it here. `single.getAxis()` returns the same instance.
        let axis = axisModel.axis as! SingleAxis

        // const axisPosition = axis.position;
        let axisPosition = axis.position
        // const orient = axis.orient;
        let orient = axis.orient

        // const rect = single.getRect();
        let rect = single.getRect()
        // const rectBound = [rect.x, rect.x + rect.width, rect.y, rect.y + rect.height];
        let rectBound = [rect.x, rect.x + rect.width, rect.y, rect.y + rect.height]

        // const positionMap = {
        //     horizontal: {top: rectBound[2], bottom: rectBound[3]},
        //     vertical: {left: rectBound[0], right: rectBound[1]}
        // } as const;

        // layout.position = [
        //     orient === 'vertical'
        //         ? positionMap.vertical[axisPosition as 'left' | 'right']
        //         : rectBound[0],
        //     orient === 'horizontal'
        //         ? positionMap.horizontal[axisPosition as 'top' | 'bottom']
        //         : rectBound[3]
        // ];
        let position: [Double] = [
            orient == .vertical
                ? (axisPosition == "left" ? rectBound[0] : rectBound[1])
                : rectBound[0],
            orient == .horizontal
                ? (axisPosition == "top" ? rectBound[2] : rectBound[3])
                : rectBound[3]
        ]

        // const r = {horizontal: 0, vertical: 1};
        // layout.rotation = Math.PI / 2 * r[orient];
        let rotation = Double.pi / 2 * (orient == .horizontal ? 0 : 1)

        // const directionMap = {top: -1, bottom: 1, right: 1, left: -1} as const;
        // layout.labelDirection = layout.tickDirection = layout.nameDirection = directionMap[axisPosition];
        let direction = directionMap(axisPosition)
        var labelDirection = direction
        var tickDirection = direction
        let nameDirection = direction

        // if (axisModel.get(['axisTick', 'inside'])) {
        //     layout.tickDirection = -layout.tickDirection;
        // }
        if truthy(axisModel.get(["axisTick", "inside"])) {
            tickDirection = -tickDirection
        }

        // if (zrUtil.retrieve(opt.labelInside, axisModel.get(['axisLabel', 'inside']))) {
        //     layout.labelDirection = -layout.labelDirection;
        // }
        //   `retrieve(a, b)` = a != null ? a : b. `opt.labelInside` is `Bool?`; the option read is `Any?`.
        let labelInsideResolved: Any? = opt.labelInside != nil
            ? opt.labelInside
            : axisModel.get(["axisLabel", "inside"])
        if truthy(labelInsideResolved) {
            labelDirection = -labelDirection
        }

        // const labelRotate = axisModel.get(['axisLabel', 'rotate']);
        let labelRotateOpt = numOpt(axisModel.get(["axisLabel", "rotate"]))
        // layout.labelRotate = axisPosition === 'top' ? -labelRotate : labelRotate;
        let labelRotate = axisPosition == "top" ? labelRotateOpt.map { -$0 } : labelRotateOpt

        // layout.z2 = 1;  -> dropped (not an AxisBuilderCfg field; unused by SingleAxisView).

        // return layout;  (structurally an AxisBuilderCfg).
        return AxisBuilderCfg(
            position: position,
            rotation: rotation,
            nameDirection: nameDirection,
            tickDirection: tickDirection,
            labelDirection: labelDirection,
            labelRotate: labelRotate
        )
    }
}

// upstream: const directionMap = {top: -1, bottom: 1, right: 1, left: -1} as const;  (keyed lookup).
private func directionMap(_ position: SingleAxisPosition) -> Double {
    switch position {
    case "top": return -1
    case "bottom": return 1
    case "right": return 1
    case "left": return -1
    default: return 1  // upstream `directionMap[axisPosition]` is undefined for other keys; unreachable for valid positions.
    }
}

// JS truthiness of a dynamic option value (for `if (axisModel.get([...]))`).
private func truthy(_ v: Any?) -> Bool {
    guard let v = v else { return false }
    switch v {
    case let b as Bool: return b
    case let d as Double: return d != 0 && !d.isNaN
    case let i as Int: return i != 0
    case let n as NSNumber:
        if n === kCFBooleanTrue { return true }
        if n === kCFBooleanFalse { return false }
        return n.doubleValue != 0 && !n.doubleValue.isNaN
    case let s as String: return !s.isEmpty
    default: return true
    }
}

// Coerce a dynamic option value to Double, tolerating the Int / NSNumber boxing that `[String: Any]`
// defaultOption literals use (e.g. `"rotate": 0`). A bare `as? Double` returns nil on an Int, silently
// dropping it — the recurring Int-vs-Double option-read trap.
private func numOpt(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber, !(n === kCFBooleanTrue || n === kCFBooleanFalse) { return n.doubleValue }
    return nil
}
