// Ported from echarts/src/coord/parallel/ParallelAxis.ts — keep in sync with upstream
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
//   import Axis from '../Axis';                                          -> Axis (coord/Axis.swift; base class extended below).
//   import Scale from '../../scale/Scale';                               -> Scale (scale/Scale.swift).
//   import { DimensionName } from '../../util/types';                    -> DimensionName (util/types.swift, = String).
//   import { OptionAxisType } from '../axisCommonTypes';                 -> OptionAxisType (coord/axisHelper.swift, = String).
//   import AxisModel from './AxisModel';                                 -> ParallelAxisModel (coord/parallel/ParallelAxisModel.swift).
//       the inherited `Axis.model: AxisBaseModel!` already provides the model slot — no
//       re-declaration needed; narrow via `as? ParallelAxisModel` at use.
//   import Parallel from './Parallel';                                   -> Parallel (coord/parallel/Parallel.swift; the parallel
//       coordinate-system master). note: `Parallel` is ported (coord/parallel/Parallel.swift); the
//       `coordinateSystem` slot below references it (mirrors AngleAxis referencing `Polar`,
//       SingleAxis referencing `Single`). `getModel()` is provided by that master.

// upstream: class ParallelAxis extends Axis { ... }
//   Not further subclassed → `final class` (CONVENTIONS §2).
public final class ParallelAxis: Axis {

    // upstream: readonly axisIndex: number;
    //   Number -> Double (CONVENTIONS §1), mirroring ComponentModel.componentIndex.
    public let axisIndex: Double

    // Inject
    // upstream: model: AxisModel;  (property narrowing of the inherited `Axis.model`) — see import note.
    // upstream: coordinateSystem: Parallel;  (injected by Parallel's constructor).
    //   `Parallel` (coord/parallel/Parallel.swift) is ported; typed here to that master so
    //   `getModel()` resolves. Narrow the inherited `model` via `as? ParallelAxisModel` at use.
    public var coordinateSystem: Parallel!

    // upstream: constructor(dim, scale, coordExtent, axisType, axisIndex) {
    //     super(dim, scale, coordExtent);
    //     this.type = axisType || 'value';
    //     this.axisIndex = axisIndex;
    // }
    public init(
        _ dim: DimensionName,
        _ scale: Scale,
        _ coordExtent: [Double],
        _ axisType: OptionAxisType?,
        _ axisIndex: Double
    ) {
        self.axisIndex = axisIndex
        super.init(dim, scale, coordExtent)

        // upstream: this.type = axisType || 'value';  (JS `||` — nil/empty string is falsy → 'value').
        self.type = (axisType != nil && !axisType!.isEmpty) ? axisType! : "value"
    }

    // upstream: isHorizontal(): boolean {
    //     return this.coordinateSystem.getModel().get('layout') !== 'horizontal';
    // }
    public func isHorizontal() -> Bool {
        return (self.coordinateSystem.getModel().get("layout") as? String) != "horizontal"
    }
}

// export default ParallelAxis;  -> `public final class ParallelAxis` above.
