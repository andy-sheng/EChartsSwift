// Ported from echarts/src/layout/barCommon.ts — keep in sync with upstream
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
//   import { assert } from 'zrender/src/core/util';                          -> `util.assert` (ZRenderKit Core/util.swift)
//   import { createMetricsNonOrdinalLinearPositiveMinGap } from '../chart/helper/axisSnippets';
//       -> chart/helper/axisSnippets.ts NOT yet ported (PREREQ). PORT-TODO stub below mirrors its impl;
//          remove it (and use the real symbol) once axisSnippets.swift lands.
//   import type Axis from '../coord/Axis';                                   -> Axis (coord/Axis.swift)
//   import { AxisStatKey, requireAxisStatistics } from '../coord/axisStatistics';
//       -> AxisStatKey / requireAxisStatistics (coord/axisStatistics.swift, top-level free symbols)
//   import { EChartsExtensionInstallRegisters } from '../extension';
//       -> EChartsExtensionInstallRegisters (stub registrar currently owned by coord/axisStatistics.swift; Phase 6b)
//   import { isNullableNumberFinite } from '../util/number';                 -> `number.isNullableNumberFinite` (util/number.swift)


// PORT-NOTE: upstream `BaseBarSeriesSubType = typeof SERIES_TYPE_BAR | typeof SERIES_TYPE_PICTORIAL_BAR`
//   (a union of string literals). The literal-union brand is dropped in Swift (aliased to String),
//   matching `ComponentSubType = String` used by `AxisStatKeyedClient.seriesType`.
public typealias BaseBarSeriesSubType = String

public let SERIES_TYPE_BAR = "bar"
public let SERIES_TYPE_PICTORIAL_BAR = "pictorialBar"


// PORT-NOTE: upstream `coordSysType: 'cartesian2d' | 'polar'` (string-literal union) modeled as String.
public func requireAxisStatisticsForBaseBar(
    _ registers: EChartsExtensionInstallRegisters,
    _ axisStatKey: AxisStatKey,
    _ seriesType: BaseBarSeriesSubType,
    _ coordSysType: String
) {
    requireAxisStatistics(
        registers,
        AxisStatKeyedClient(
            key: axisStatKey,
            seriesType: seriesType,
            coordSysType: coordSysType,
            getMetrics: createMetricsNonOrdinalLinearPositiveMinGap
        )
    )
}

// See cases in `test/bar-start.html` and `#7412`, `#8747`.
public func getStartValue(_ baseAxis: Axis) -> Double {
    // PORT-TODO: `Scale.rawExtentInfo` is `ScaleRawExtentInfo?`; upstream treats it as present here
    //   (it is created by the coord-sys pipeline before layout).
    let val = baseAxis.scale.rawExtentInfo!.makeRenderInfo().startValue
    if __DEV__ {
        util.assert(number.isNullableNumberFinite(val))
    }
    // PORT-TODO: upstream returns `number` directly; `startValue` is `number | undefined` (Pick of
    //   `ScaleRawExtentInternal`). The __DEV__ assert above guarantees it is finite when reached.
    return val!
}


// ============================================================================
// PORT-TODO: stub for `createMetricsNonOrdinalLinearPositiveMinGap` from
//   `chart/helper/axisSnippets.ts` (PREREQ, not yet ported). Mirrors the upstream one-liner so this
//   file compiles; remove and import the real symbol from `chart/helper/axisSnippets.swift` when it lands.
//
//   export function createMetricsNonOrdinalLinearPositiveMinGap(axis: Axis): AxisStatMetrics {
//       registerMetricImplLiPosMinGap();
//       return {
//           // non-category scale do not use `liPosMinGap` to calculate `bandWidth`.
//           liPosMinGap: !isOrdinalScale(axis.scale)
//       };
//   }
private func createMetricsNonOrdinalLinearPositiveMinGap(_ axis: Axis) -> AxisStatMetrics? {
    registerMetricImplLiPosMinGap()
    return AxisStatMetrics(
        // non-category scale do not use `liPosMinGap` to calculate `bandWidth`.
        liPosMinGap: !helper.isOrdinalScale(axis.scale)
    )
}
// ============================================================================
