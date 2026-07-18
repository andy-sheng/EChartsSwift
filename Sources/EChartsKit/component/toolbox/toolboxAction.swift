// Ported from echarts/src/component/toolbox/feature/Restore.ts + MagicType.ts (the ACTION cores) +
// core/echarts.ts's `restore` action registration — keep in sync with upstream.
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

// upstream:
//   - core/echarts.ts `registerAction({ type: 'restore', event: 'restore', update: 'prepareAndUpdate' },
//       function (payload, ecModel) { ecModel.resetOption('recreate'); })`
//   - MagicType.ts `registerAction({ type: 'changeMagicType', event: 'magicTypeChanged', update:
//       'prepareAndUpdate' }, function (payload, ecModel) { ecModel.mergeOption(payload.newOption); })`
//
// The `registerAction` is module-level (Phase-29), so — like installBrushAction — this only
// registers the actions; `update:'prepareAndUpdate'` collapses to the full `update()` the driver runs
// after the handler (which is exactly what these two features need: resetOption / mergeOption mutate the
// live ecModel in place, then the pipeline re-renders).
public func installToolboxActions(_ registers: EChartsExtensionInstallRegisters) {
    _ = registers

    // registerAction({type:'restore', event:'restore', update:'prepareAndUpdate'}, handler)
    var restoreInfo = ActionInfo(type: "restore")
    restoreInfo.event = "restore"
    restoreInfo.update = "prepareAndUpdate"
    registerAction(restoreInfo) { _, ecModel, _ in
        // ecModel.resetOption('recreate') — re-mount the OptionManager's base-option backup, discarding
        //   every interactive change (dataZoom window, magicType swap, …). Ported GlobalModel path.
        _ = ecModel.resetOption("recreate")
        return nil
    }

    // component/helper/interactionMutex.ts self-registers `takeGlobalCursor` at module load
    //   (`registerAction({type:'takeGlobalCursor', event:'globalCursorTaken', update:'update'}, noop)`).
    //   The upstream handler is a NO-OP (the cursor arming is consumed by the toolbox DataZoom feature's
    //   `render`, which enables its BrushController). The port additionally records the `dataZoomSelect`
    //   arm state on the driver so the live host (`EChartsView`) can switch its rect-drag to a dataZoom
    //   box-select. (DEVIATION vs upstream, where the toolbox feature holds `_isZoomActive`; the
    //   host has no live feature-owned BrushController at drag time — see ECharts.dataZoomSelectActive.)
    var cursorInfo = ActionInfo(type: "takeGlobalCursor")
    cursorInfo.event = "globalCursorTaken"
    cursorInfo.update = "update"
    registerAction(cursorInfo) { payload, _, api in
        if (payload.other["key"] as? String) == "dataZoomSelect" {
            let active = (payload.other["dataZoomSelectActive"] as? Bool) ?? false
            (api as? EChartsExtensionAPI)?.setDataZoomSelectActive(active)
        }
        return nil
    }

    // registerAction({type:'changeMagicType', event:'magicTypeChanged', update:'prepareAndUpdate'}, handler)
    var magicInfo = ActionInfo(type: "changeMagicType")
    magicInfo.event = "magicTypeChanged"
    magicInfo.update = "prepareAndUpdate"
    registerAction(magicInfo) { payload, ecModel, _ in
        // ecModel.mergeOption(payload.newOption)
        if let newOption = payload.other["newOption"] as? [String: Any] {
            ecModel.mergeOption(newOption)
        }
        return nil
    }
}

// upstream: MagicType.onclick — builds the `newOption` that swaps each convertible series to `targetType`
//   ('line' ↔ 'bar'). Factored out so the toolbox VIEW's icon onclick (deferred) AND a headless caller can
//   compute the merge option. Returns `{ series: [...perSeriesOverride], xAxis?: [...], yAxis?: [...] }`.
//   PORT SCOPE: line ↔ bar + 'stack'/'tiled' modifiers. Mirrors upstream `seriesOptGenreator`: only the
//   OPPOSITE type converts (bar → line / line → bar), carrying over the series' data/stack/markPoint/markLine
//   options. The axis `boundaryGap` is flipped to match (bar → true). Still deferred vs upstream: the
//   `model.get(['option', type])` per-type option merge (needs the feature model, not passed here) and the
//   real per-axis-index boundaryGap via getReferringComponents (only xAxis[0] is flipped).
// A shared stack key the 'stack' magicType assigns so every convertible series stacks together (upstream
//   `INNER_STACK_KEYWORD`). 'tiled' clears it.
public let TOOLBOX_MAGIC_STACK_KEYWORD = "__ec_magicType_stack__"

public func computeMagicTypeOption(_ ecModel: GlobalModel, _ targetType: String) -> [String: Any] {
    // 'stack' / 'tiled' are MODIFIERS (they toggle each line/bar series' `stack`), not a type swap.
    if targetType == "stack" || targetType == "tiled" {
        var seriesOverrides: [[String: Any]] = []
        ecModel.eachSeries { seriesModel, _ in
            let sub = seriesModel.subType
            if sub == "line" || sub == "bar" {
                seriesOverrides.append([
                    "id": seriesModel.id,
                    // stack → the shared keyword; tiled → NSNull() clears it.
                    "stack": targetType == "stack" ? TOOLBOX_MAGIC_STACK_KEYWORD : NSNull()
                ])
            }
        }
        return ["series": seriesOverrides]
    }

    var seriesOverrides: [[String: Any]] = []
    var touchedCartesian = false

    ecModel.eachSeries { seriesModel, _ in
        let sub = seriesModel.subType
        // seriesOptGenreator[type]: only the OPPOSITE type converts (bar → line / line → bar); a series
        //   already of the target type returns undefined upstream, so NO override is pushed for it.
        let convertible = (targetType == "line" && sub == "bar")
            || (targetType == "bar" && sub == "line")
        if convertible {
            var override: [String: Any] = ["id": seriesModel.id, "type": targetType]
            // Preserve the series name so the merge matches by id AND keeps the legend entry.
            if !seriesModel.name.isEmpty { override["name"] = seriesModel.name }
            // Carry over the data-related option (upstream seriesOptGenreator merge:
            //   { id, type, data, stack, markPoint, markLine }).
            if let data = seriesModel.get("data") { override["data"] = data }
            if let stack = seriesModel.get("stack") { override["stack"] = stack }
            if let markPoint = seriesModel.get("markPoint") { override["markPoint"] = markPoint }
            if let markLine = seriesModel.get("markLine") { override["markLine"] = markLine }
            seriesOverrides.append(override)
        }
        // Modify boundaryGap: upstream runs for EVERY cartesian line/bar series, regardless of whether
        //   an override was pushed. (Port reduction: only xAxis[0] is flipped — see header.)
        if sub == "bar" || sub == "line" { touchedCartesian = true }
    }

    var newOption: [String: Any] = ["series": seriesOverrides]
    // newOption[axisType][axisIndex].boundaryGap = (type === 'bar'). A cartesian category x-axis wants
    //   boundaryGap:true for bars (bars sit inside a band) and false is fine for lines. Apply to xAxis[0].
    if touchedCartesian {
        newOption["xAxis"] = [["boundaryGap": targetType == "bar"] as [String: Any]]
    }
    return newOption
}
