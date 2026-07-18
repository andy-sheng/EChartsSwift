// Ported from echarts/src/component/timeline/timelineAction.ts — keep in sync with upstream.
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
//   import GlobalModel from '../../model/Global';       -> `GlobalModel`.
//   import TimelineModel from './TimelineModel';          -> `TimelineModel`.
//   import { defaults } from 'zrender/src/core/util';     -> `util.defaults`.
//   import { EChartsExtensionInstallRegisters } from '../../extension';
//       -> `EChartsExtensionInstallRegisters` (coord/axisStatistics.swift stub); the stub does not
//          model `registerAction`, so this calls the module-level `registerAction` directly (same as
//          installDataZoomAction / installToolboxActions).
//   import ExtensionAPI from '../../core/ExtensionAPI';   -> `ExtensionAPI`.
//   The `TimelineChangePayload` / `TimelinePlayChangePayload` interfaces collapse to `Payload`
//     (fields read from `payload.other[...]`).

// export function installTimelineAction(registers: EChartsExtensionInstallRegisters)
public func installTimelineAction(_ registers: EChartsExtensionInstallRegisters) {
    _ = registers

    // registerAction({type:'timelineChange', event:'timelineChanged', update:'prepareAndUpdate'}, handler)
    var changeInfo = ActionInfo(type: "timelineChange")
    changeInfo.event = "timelineChanged"
    changeInfo.update = "prepareAndUpdate"
    registerAction(changeInfo) { payload, ecModel, api in
        // const timelineModel = ecModel.getComponent('timeline') as TimelineModel;
        let timelineModel = ecModel.getComponent("timeline") as? TimelineModel

        // if (timelineModel && payload.currentIndex != null) { ... }
        if let timelineModel = timelineModel, let currentIndex = tlReadInt(payload.other["currentIndex"]) {
            timelineModel.setCurrentIndex(currentIndex)

            // if (!timelineModel.get('loop', true) && timelineModel.isIndexMax() && timelineModel.getPlayState())
            if !(timelineModel.get("loop", true) as? Bool ?? true)
                && timelineModel.isIndexMax()
                && timelineModel.getPlayState() {
                timelineModel.setPlayState(false)

                // The timeline has played to the end, trigger event.
                var p = Payload(type: "timelinePlayChange")
                p.other["playState"] = false
                p.other["from"] = payload.other["from"]
                api.dispatchAction(p)
            }
        }

        // Set normalized currentIndex to payload.
        if let timelineModel = timelineModel {
            // ecModel.resetOption('timeline', { replaceMerge: timelineModel.get('replaceMerge', true) });
            _ = ecModel.resetOption(
                "timeline",
                GlobalModelSetOptionOpts(replaceMerge: timelineModel.get("replaceMerge", true))
            )

            // return defaults({ currentIndex: timelineModel.option.currentIndex }, payload);
            //   The normalized currentIndex wins; every other field of the payload (from, and any
            //   user-supplied keys carried in the dynamic bag) is filled in from `payload.other`.
            var ev: ECEventData = [:]
            ev["currentIndex"] = timelineModel.getCurrentIndex()
            util.defaults(&ev, payload.other)
            return ev
        }

        return nil
    }

    // registerAction({type:'timelinePlayChange', event:'timelinePlayChanged', update:'update'}, handler)
    var playInfo = ActionInfo(type: "timelinePlayChange")
    playInfo.event = "timelinePlayChanged"
    playInfo.update = "update"
    registerAction(playInfo) { payload, ecModel, _ in
        // const timelineModel = ecModel.getComponent('timeline') as TimelineModel;
        let timelineModel = ecModel.getComponent("timeline") as? TimelineModel
        // if (timelineModel && payload.playState != null) { timelineModel.setPlayState(payload.playState); }
        if let timelineModel = timelineModel, let playState = payload.other["playState"] as? Bool {
            timelineModel.setPlayState(playState)
        }
        return nil
    }
}
