// Ported from echarts/src/visual/decal.ts — keep in sync with upstream.
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
//   import ExtensionAPI from '../core/ExtensionAPI';
//   import GlobalModel from '../model/Global';
//   import {createOrUpdatePatternFromDecal} from '../util/decal';   -> createOrUpdatePatternFromDecal
//   import { createSimpleOverallStageHandler2 } from '../util/model'; -> model.createSimpleOverallStageHandler2
//
// upstream: export const decalVisualStageHandler = createSimpleOverallStageHandler2(decalVisual);
//   Registered at PRIORITY.VISUAL.DECAL (7000) — AFTER the style tasks (GLOBAL/CHART_DATA_CUSTOM) and
//   the aria decal assignment (ARIA, 6000). The slim driver invokes its `overallReset` in the visual
//   stage (see ECharts.performVisualStage / the aria + decal calls in the update pipeline).
public let decalVisualStageHandler: StageHandler =
    model.createSimpleOverallStageHandler2 { ecModel, api, _ in
        decalVisual(ecModel, api)
    }

// upstream: function decalVisual(ecModel: GlobalModel, api: ExtensionAPI): void
func decalVisual(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
    // upstream: ecModel.eachRawSeries(seriesModel => { ... });
    ecModel.eachRawSeries { seriesModel, _ in
        // upstream: if (ecModel.isSeriesFiltered(seriesModel)) { return; }
        if ecModel.isSeriesFiltered(seriesModel) {
            return
        }

        let data = seriesModel.getData()

        // upstream:
        //   if (data.hasItemVisual()) {
        //       data.each(idx => {
        //           const decal = data.getItemVisual(idx, 'decal');
        //           if (decal) {
        //               const itemStyle = data.ensureUniqueItemVisual(idx, 'style');
        //               itemStyle.decal = createOrUpdatePatternFromDecal(decal, api);
        //           }
        //       });
        //   }
        if data.hasItemVisual() {
            data.each { args in
                let idx = Int(args[0] as! Double)
                let decal = data.getItemVisual(idx, "decal")
                if decal != nil {
                    // ensureUniqueItemVisual returns the per-item 'style' bag (a `[String: Any]`); the
                    //   upstream in-place `itemStyle.decal = ...` mutation is written back via setItemVisual
                    //   (Swift dicts are value types, CONVENTIONS §3).
                    var itemStyle = (data.ensureUniqueItemVisual(idx, "style") as? [String: Any]) ?? [:]
                    itemStyle["decal"] = createOrUpdatePatternFromDecal(decal, api)
                    data.setItemVisual(idx, "style", itemStyle)
                }
            }
        }

        // upstream:
        //   const decal = data.getVisual('decal');
        //   if (decal) {
        //       const style = data.getVisual('style');
        //       style.decal = createOrUpdatePatternFromDecal(decal, api);
        //   }
        let decal = data.getVisual("decal")
        if decal != nil {
            var style = (data.getVisual("style") as? [String: Any]) ?? [:]
            style["decal"] = createOrUpdatePatternFromDecal(decal, api)
            data.setVisual("style", style)
        }
    }
}
