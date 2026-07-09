// Ported from echarts/src/component/axis/parallelAxisAction.ts — keep in sync with upstream
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
//   import { Payload } from '../../util/types';                                   -> Payload (util/types.swift).
//   import ParallelAxisModel, { ParallelAxisInterval } from '../../coord/parallel/AxisModel';
//       -> ParallelAxisModel / ParallelAxisInterval (coord/parallel/ParallelAxisModel.swift).
//   import GlobalModel from '../../model/Global';                                 -> GlobalModel.
//   import ParallelModel from '../../coord/parallel/ParallelModel';              -> ParallelModel.
//   import { EChartsExtensionInstallRegisters } from '../../extension';          -> EChartsExtensionInstallRegisters.

// upstream:
//   interface ParallelAxisAreaSelectPayload extends Payload {
//       parallelAxisId: string;
//       intervals: ParallelAxisInterval[]
//   }
//   The port carries `parallelAxisId` (the component `query`) and `intervals` on the dynamic
//   `Payload.other` bag; `intervals` is a `[[Double]]` (each interval is a `[low, high]` pair).

// upstream:
//   const actionInfo = { type: 'axisAreaSelect', event: 'axisAreaSelected' /* update: 'updateVisual' */ };
//   `update` is left undefined upstream → defaults to 'update' (EC_FULL_UPDATE): the slim driver re-runs a
//   full update() after the handler, which re-runs `parallelVisual` (→ Parallel.eachActiveState reads the
//   now-populated activeIntervals and writes each line's opacity) and re-renders the polylines (dimming the
//   out-of-interval lines via the inactiveOpacity, keeping in-interval lines at activeOpacity).

// upstream:
//   export interface ParallelAxisExpandPayload extends Payload { axisExpandWindow?: number[]; }
//   The `axisExpandWindow` rides on `Payload.other` for the `parallelAxisExpand` action below.

// upstream: export function installParallelActions(registers: EChartsExtensionInstallRegisters)
public func installParallelActions(_ registers: EChartsExtensionInstallRegisters) {
    _ = registers

    // registers.registerAction(actionInfo, function (payload, ecModel) {
    //     ecModel.eachComponent({ mainType: 'parallelAxis', query: payload },
    //         function (parallelAxisModel) {
    //             parallelAxisModel.axis.model.setActiveIntervals(payload.intervals);
    //         });
    // });
    var areaSelectInfo = ActionInfo(type: "axisAreaSelect")
    areaSelectInfo.event = "axisAreaSelected"
    // `update` intentionally unset → defaults to 'update' (see actionInfo note above).
    registerAction(areaSelectInfo) { payload, ecModel, _ in
        // upstream `query: payload` — the component query fields (parallelAxisId / parallelAxisIndex /
        //   parallelAxisName) live on `payload.other`; `eachComponent(QueryConditionKindA)` resolves them
        //   via `mainType + Id/Index/Name` (see Global.findComponents.getQueryCond). If no id/index/name is
        //   present the query matches ALL parallelAxis components (upstream behavior).
        let intervals = parallelAxisIntervals(payload.other["intervals"])
        ecModel.eachComponent(
            QueryConditionKindA(mainType: "parallelAxis", query: payload.other),
            { cmpt, _ in
                // upstream: parallelAxisModel.axis.model.setActiveIntervals(payload.intervals);
                //   `axis.model` resolves back to the ParallelAxisModel itself (the activeInterval state
                //   deliberately lives on the axis MODEL, not on the disposable ParallelAxis — see the doc
                //   comment on ParallelAxisModel.setActiveIntervals). Call it directly on the model.
                guard let parallelAxisModel = cmpt as? ParallelAxisModel else { return }
                parallelAxisModel.setActiveIntervals(intervals)
            }
        )
        return nil
    }

    /**
     * @payload
     */
    // registers.registerAction('parallelAxisExpand', function (payload, ecModel) {
    //     ecModel.eachComponent({ mainType: 'parallel', query: payload },
    //         function (parallelModel) { parallelModel.setAxisExpand(payload); });
    // });
    registerAction("parallelAxisExpand") { payload, ecModel, _ in
        ecModel.eachComponent(
            QueryConditionKindA(mainType: "parallel", query: payload.other),
            { cmpt, _ in
                guard let parallelModel = cmpt as? ParallelModel else { return }
                parallelModel.setAxisExpand(payload.other)
            }
        )
        return nil
    }
}

// Coerce `payload.other["intervals"]` to `[ParallelAxisInterval]` (== `[[Double]]`). Tolerates the Int/
//   Double/NSNumber boxing the dynamic payload bag uses (the Int-vs-Double option-read trap): a bare
//   `as? [[Double]]` returns nil when any endpoint arrived as an `Int` literal, silently dropping the
//   whole selection. `intervals.length === 0` means "set all active" upstream → an empty/absent array is a
//   valid input (clears the selection back to 'normal').
private func parallelAxisIntervals(_ v: Any?) -> [ParallelAxisInterval] {
    guard let rows = v as? [Any] else { return [] }
    return rows.map { row -> ParallelAxisInterval in
        guard let pair = row as? [Any] else { return [] }
        return pair.compactMap { intervalNum($0) }
    }
}

private func intervalNum(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    if let s = v as? String { return Double(s) }
    return nil
}
