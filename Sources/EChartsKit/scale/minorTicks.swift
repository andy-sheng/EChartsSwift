// Ported from echarts/src/scale/minorTicks.ts — keep in sync with upstream
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
//   import { round } from '../util/number';            -> sibling number.swift (`number.round`)
//   import { ParsedAxisBreakList } from '../util/types'; -> sibling types.swift (`ParsedAxisBreakList`)
//   import { getScaleBreakHelper } from './break';     -> sibling break.swift (`` `break`.getScaleBreakHelper() ``)
//   import { getIntervalPrecision } from './helper';   -> sibling helper.swift (`helper.getIntervalPrecision`)
//   import Scale from './Scale';                       -> sibling Scale.swift (`Scale`)

// upstream module `minorTicks.ts` (free function) -> caseless enum namespace `minorTicks`.
//   call site: upstream `import { getMinorTicks } from './minorTicks'` -> `minorTicks.getMinorTicks(...)`.
public enum minorTicks {

    public static func getMinorTicks(
        _ scale: Scale,
        _ splitNumber: Double,
        _ breaks: ParsedAxisBreakList,
        _ scaleInterval: Double
    ) -> [[Double]] {
        var opt = ScaleGetTicksOpt()
        opt.expandToNicedExtent = true
        let ticks = scale.getTicks(opt)
        // NOTE: In log-scale, do not support minor ticks when breaks exist.
        //  because currently log-scale minor ticks is calculated based on raw values
        //  rather than log-transformed value, due to an odd effect when breaks exist.
        var minorTicks: [[Double]] = []
        let extent = scale.getExtent()

        var i = 1
        while i < ticks.count {
            let nextTick = ticks[i]
            let prevTick = ticks[i - 1]

            if prevTick.break != nil || nextTick.break != nil {
                // Do not build minor ticks to the adjacent ticks to breaks ticks,
                // since the interval might be irregular.
                i += 1
                continue
            }

            var count: Double = 0
            var minorTicksGroup: [Double] = []
            let interval = nextTick.value - prevTick.value
            let minorInterval = interval / splitNumber
            let minorIntervalPrecision = helper.getIntervalPrecision(minorInterval)

            while count < splitNumber - 1 {
                let minorTick = number.round(prevTick.value + (count + 1) * minorInterval, minorIntervalPrecision)

                // For the first and last interval. The count may be less than splitNumber.
                if minorTick > extent[0] && minorTick < extent[1] {
                    minorTicksGroup.append(minorTick)
                }
                count += 1
            }

            let scaleBreakHelper = `break`.getScaleBreakHelper()
            // depends on sibling break.swift `BreakScaleHelper.pruneTicksByBreak`, which
            //  mutates `ticks` in place (upstream `void` return); ported as `inout`. `value => value`
            //  is the identity `getValue` for the `number[]` (TItem = number) specialization.
            scaleBreakHelper?.pruneTicksByBreak(
                "auto",
                &minorTicksGroup,
                breaks,
                { value in value },
                scaleInterval,
                extent
            )
            minorTicks.append(minorTicksGroup)

            i += 1
        }

        return minorTicks
    }
}
