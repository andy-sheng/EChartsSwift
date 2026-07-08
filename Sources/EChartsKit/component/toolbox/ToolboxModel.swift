// Ported (MODEL + a subset of features) from echarts/src/component/toolbox/ToolboxModel.ts — keep in
// sync with upstream.
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

// class ToolboxModel extends ComponentModel<ToolboxOption>
//   The toolbox component. Its `feature` sub-option enables per-feature buttons (restore / magicType /
//   dataZoom / saveAsImage / dataView / brush). This port wires the DATA/ACTION core of the option-
//   expressible features (`restore`, `magicType`) via `toolboxAction.swift`; the on-canvas icon VIEW +
//   the host-dependent features (saveAsImage → canvas export, dataView → HTML overlay) are DEFERRED.
public typealias ToolboxOption = [String: Any]

open class ToolboxModel: ComponentModel {

    // static type = 'toolbox' as const;
    public override class var type: ComponentFullType { return "toolbox" }

    // static layoutMode = { type: 'box', ignoreSize: true }
    public override class var layoutMode: Any? {
        return ["type": "box", "ignoreSize": true] as [String: Any]
    }

    // static defaultOption: ToolboxOption = { ... }
    public override class var defaultOption: ModelOption? {
        return [
            "show": true,
            // z / zlevel
            "z": 6.0,
            // 'horizontal' | 'vertical'
            "orient": "horizontal",
            "left": "right",
            "top": "top",
            // "right" / "bottom" resolved by layout
            "backgroundColor": "transparent",
            "borderColor": tokens.color.border,
            "borderRadius": 0.0,
            "borderWidth": 0.0,
            "padding": tokens.size.m,       // 15
            "itemSize": 15.0,
            "itemGap": tokens.size.s,       // 10
            "showTitle": true,
            // iconStyle: { borderColor: accent50, color: 'none' } → the stroke-only icon paint.
            "iconStyle": [
                "borderColor": tokens.color.accent50,
                "color": "none"
            ] as [String: Any],
            "emphasis": [
                "iconStyle": [
                    "borderColor": tokens.color.accent70
                ] as [String: Any]
            ] as [String: Any],
            // feature: { saveAsImage, restore, dataView, dataZoom, magicType, brush } — user-supplied.
            "feature": [String: Any](),
            "tooltip": [
                "show": false,
                "position": "bottom"
            ] as [String: Any]
        ]
    }

    // upstream `optionUpdated()` — merge each enabled feature's registered `getDefaultOption(ecModel)`
    //   (its icon/title/show/... default bag) into the user's `feature[name]` option, so the VIEW can
    //   read `featureModel.get('icon')` / `get('title')`. (The theme-feature merge is DEFERRED — no
    //   toolbox theme option in the slim port.)
    open override func optionUpdated(_ newCptOption: ModelOption?, _ isInit: Bool) {
        guard var option = self.option as? [String: Any],
              var feature = option["feature"] as? [String: Any] else {
            return
        }
        for featureName in feature.keys {
            guard var featureOpt = feature[featureName] as? [String: Any] else { continue }
            if let registration = getFeature(featureName),
               let getDefaultOption = registration.getDefaultOption,
               let ecModel = self.ecModel {
                let defaultOption = getDefaultOption(ecModel)
                // merge(featureOpt, Feature.defaultOption)  — user option wins (overwrite:false).
                _ = util.merge(&featureOpt, defaultOption, false)
                feature[featureName] = featureOpt
            }
        }
        option["feature"] = feature
        self.option = option
    }
}
