// Ported from echarts/src/component/dataZoom/SelectZoomModel.ts — keep in sync with upstream
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

// upstream: class SelectDataZoomModel extends DataZoomModel { static type = 'dataZoom.select'; }
//   The INVISIBLE dataZoom the toolbox dataZoom feature drives: `registerInternalOptionCreator(
//   'dataZoom', …)` (feature/DataZoom.ts:330) injects one of these per referenced axis whenever
//   `toolbox.feature.dataZoom` is configured, so an index-less `dispatchAction({type:'dataZoom'})`
//   (and the toolbox zoom brush / restore path) reaches EVERY axis — including the y axis, which has
//   no user-declared dataZoom. Without it the port answered such payloads on the x axis only.
//   Upstream SelectZoomView is an empty DataZoomView subclass; the port tolerates a model with no
//   registered view (same as dataZoom.inside), so no view is needed.
open class SelectZoomModel: DataZoomModel {

    public override class var type: ComponentFullType { return "dataZoom.select" }
}

// upstream feature/DataZoom.ts:53
let DATA_ZOOM_ID_BASE = model.makeInternalComponentId("toolbox-dataZoom_")

// upstream feature/DataZoom.ts:330-366 `registerInternalOptionCreator('dataZoom', …)`.
//   Free function invoked once from `ECharts.installOnce()` (the port's registrar surface — upstream
//   runs this at toolbox/feature/DataZoom.ts module scope, imported by the toolbox install).
func installToolboxDataZoomInternalOptionCreator() {
    registerInternalOptionCreator("dataZoom") { ecModel in
        guard let toolboxModel = ecModel.getComponent("toolbox", 0),
              toolboxModel.get(["feature", "dataZoom"]) != nil else {
            return []
        }
        let dzFeatureModel = toolboxModel.getModel(["feature", "dataZoom"])
        var dzOptions: [ComponentOption] = []

        // makeAxisFinder (feature/DataZoom.ts:254): absent xAxisIndex/xAxisId means 'all'
        // (same for y); `false`/'none' closes that side's control.
        var finder: [String: Any] = [:]
        finder["xAxisIndex"] = dzFeatureModel.get("xAxisIndex", true)
        finder["yAxisIndex"] = dzFeatureModel.get("yAxisIndex", true)
        finder["xAxisId"] = dzFeatureModel.get("xAxisId", true)
        finder["yAxisId"] = dzFeatureModel.get("yAxisId", true)
        if finder["xAxisIndex"] == nil && finder["xAxisId"] == nil { finder["xAxisIndex"] = "all" }
        if finder["yAxisIndex"] == nil && finder["yAxisId"] == nil { finder["yAxisIndex"] = "all" }

        let finderResult = model.parseFinder(ecModel, finder)

        func buildInternalOptions(_ axisModel: ComponentModel, _ axisMainType: String, _ axisIndexPropName: String) {
            let axisIndex = axisModel.componentIndex
            var bag: [String: Any] = [
                "type": "select",
                "$fromToolbox": true,
                // Default to be filter
                "filterMode": dzFeatureModel.get("filterMode", true) ?? "filter",
                // Id for merge mapping.
                "id": DATA_ZOOM_ID_BASE + axisMainType + String(Int(axisIndex)),
            ]
            bag[axisIndexPropName] = axisIndex
            // ComponentOption is the typed projection over the dynamic bag (types.swift): the bag
            // itself rides in `rawOption`, which is what Global._mergeOption instantiates from.
            var newOpt = ComponentOption()
            newOpt.mainType = "dataZoom"
            newOpt.type = "select"
            newOpt.id = bag["id"]
            newOpt.rawOption = bag
            dzOptions.append(newOpt)
        }

        for m in (finderResult["xAxisModels"] as? [ComponentModel]) ?? [] {
            buildInternalOptions(m, "xAxis", "xAxisIndex")
        }
        for m in (finderResult["yAxisModels"] as? [ComponentModel]) ?? [] {
            buildInternalOptions(m, "yAxis", "yAxisIndex")
        }
        return dzOptions
    }
}
