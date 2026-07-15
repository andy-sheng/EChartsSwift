// Ported from echarts/src/component/grid/installLegacyGridContainLabel.ts — keep in sync with upstream.
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

// upstream imports:
//   import { EChartsExtensionInstallRegisters } from '../../extension';
//   import { registerLayOutGridByContainLabelImpl } from '../../coord/cartesian/Grid';
//     -> `registerLegacyGridContainLabelImpl` (coord/cartesian/Grid.swift).
//   import Axis2D from '../../coord/cartesian/Axis2D';   -> coord/cartesian/Axis2D.swift (`Axis2D`).
//   import { estimateLabelUnionRect } from '../../coord/axisHelper';  -> `axisHelper.estimateLabelUnionRect`.
//   import { LayoutRect } from '../../util/layout';      -> `LayoutRect` (= BoundingRect, util/layout.swift).
//   import { each } from 'zrender/src/core/util';        -> ZRenderKit `util.each`.
//
// This is the pre-outerBounds `grid.containLabel` layout: for each non-`inside` axis it reserves the axis
// label band (label union rect + margin) by shrinking the grid rect on that side. Upstream gates it behind
// `use(LegacyGridContainLabel)`; this port registers it by default (see ECharts.swift) so native output
// matches the reference echarts.js pane, which honors `containLabel`.

import Foundation
import ZRenderKit

// JS truthiness for the dynamic `axisLabel.inside` option (nil/false/0/"" are falsy).
private func legacyContainLabelTruthy(_ v: Any?) -> Bool {
    guard let v = v else { return false }
    if v is NSNull { return false }
    if let b = v as? Bool { return b }
    if let d = v as? Double { return d != 0 && !d.isNaN }
    if let i = v as? Int { return i != 0 }
    if let s = v as? String { return !s.isEmpty }
    return true
}

// upstream: function layOutGridByContainLabel(axesList: Axis2D[], gridRect: LayoutRect): void
func layOutGridByContainLabel(_ axesList: [Axis2D], _ gridRect: LayoutRect) {
    util.each(axesList) { axis, _ in
        if !legacyContainLabelTruthy(axis.model.get(["axisLabel", "inside"])) {
            if let labelUnionRect = axisHelper.estimateLabelUnionRect(axis) {
                // upstream: const dim = axis.isHorizontal() ? 'height' : 'width';
                let dimSizeBase = axis.isHorizontal() ? labelUnionRect.height : labelUnionRect.width
                let margin = (axis.model.get(["axisLabel", "margin"]) as? Double) ?? 0
                let dimSize = dimSizeBase + margin
                switch axis.position {
                case "top":
                    gridRect.y += dimSize
                    gridRect.height -= dimSize
                case "bottom":
                    gridRect.height -= dimSize
                case "left":
                    gridRect.x += dimSize
                    gridRect.width -= dimSize
                case "right":
                    gridRect.width -= dimSize
                default:
                    break
                }
            }
        }
    }
}

// upstream: export function install(registers: EChartsExtensionInstallRegisters) {
//   registers.registerLayOutGridByContainLabelImpl(layOutGridByContainLabel);
// }
public func installLegacyGridContainLabel(_ registers: EChartsExtensionInstallRegisters) {
    _ = registers
    // registers.registerLayOutGridByContainLabelImpl(layOutGridByContainLabel);
    registerLegacyGridContainLabelImpl(layOutGridByContainLabel)
}
