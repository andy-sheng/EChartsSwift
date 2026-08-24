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
//   dataZoom / saveAsImage / dataView / brush). This port wires the on-canvas icon view, the
//   option-expressible actions, and native host seams for saveAsImage bytes + editable dataView content.
public typealias ToolboxOption = [String: Any]

open class ToolboxModel: ComponentModel {

    // static type = 'toolbox' as const;
    public override class var type: ComponentFullType { return "toolbox" }

    // static layoutMode = { type: 'box', ignoreSize: true }
    public override class var layoutMode: Any? {
        return ["type": "box", "ignoreSize": true] as [String: Any]
    }

    // private _themeFeatureOption: ToolboxOption['feature'];
    private var _themeFeatureOption: [String: Any]?

    // upstream `init(option, parentModel, ecModel)`.
    //   An historical behavior: an initial ec option
    //       chart.setOption({toolbox: {feature: { featureA: {}, featureB: {} }}})
    //   indicates the declared toolbox features need to be enabled regardless of whether property
    //   "show" is explicitly specified. But the subsequent `setOption` in merge mode requires
    //   "show: false" to be explicitly specified if intending to remove features. We keep backward
    //   compatibility and perform specific processing to prevent theme settings from breaking it:
    //   the theme's `feature` is extracted out of the theme option before `super.init` merges the
    //   theme (so it is NOT merged wholesale into `option`), stashed on `_themeFeatureOption`, and
    //   later merged per-declared-feature (once) inside `optionUpdated`; the theme is then recovered.
    open override func `init`(_ option: ModelOption?, _ parentModel: Model? = nil, _ ecModel: GlobalModel? = nil, _ rest: Any...) {
        // const toolboxOptionInTheme = ecModel.getTheme().get('toolbox');
        // const themeFeatureOption = toolboxOptionInTheme ? toolboxOptionInTheme.feature : null;
        var toolboxOptionInTheme = ecModel?.getTheme().get("toolbox") as? [String: Any]
        let themeFeatureOption = toolboxOptionInTheme?["feature"] as? [String: Any]
        if let themeFeatureOption = themeFeatureOption, let ecModel = ecModel {
            // this._themeFeatureOption = extend({}, themeFeatureOption);
            //   (Swift dictionaries are value types, so assignment already copies — mirrors `extend`.)
            self._themeFeatureOption = themeFeatureOption
            // toolboxOptionInTheme.feature = {};
            //   Upstream mutates the shared theme option object in place; the port writes the emptied
            //   `feature` back into the theme Model's option so the `super.init` theme-merge below sees
            //   it (theme option bags are value types).
            toolboxOptionInTheme?["feature"] = [String: Any]()
            if var themeOption = ecModel.getTheme().option as? [String: Any] {
                themeOption["toolbox"] = toolboxOptionInTheme
                ecModel.getTheme().option = themeOption
            }
        }

        // super.init(option, parentModel, ecModel); // merge theme is performed inside it.
        super.`init`(option, parentModel, ecModel)

        if let themeFeatureOption = themeFeatureOption, let ecModel = ecModel {
            // toolboxOptionInTheme.feature = themeFeatureOption; // Recover
            toolboxOptionInTheme?["feature"] = themeFeatureOption
            if var themeOption = ecModel.getTheme().option as? [String: Any] {
                themeOption["toolbox"] = toolboxOptionInTheme
                ecModel.getTheme().option = themeOption
            }
        }
        _ = rest
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
    //   read `featureModel.get('icon')` / `get('title')`. The stashed theme `feature` (see `init`) is
    //   merged in per feature, once, before the registered default option.
    open override func optionUpdated(_ newCptOption: ModelOption?, _ isInit: Bool) {
        guard var option = self.option as? [String: Any],
              var feature = option["feature"] as? [String: Any] else {
            return
        }
        for featureName in feature.keys {
            guard var featureOpt = feature[featureName] as? [String: Any] else { continue }
            if let registration = getFeature(featureName) {
                // if (themeFeatureOption && themeFeatureOption[featureName]) {
                //     merge(featureOpt, themeFeatureOption[featureName]);
                //     themeFeatureOption[featureName] = null;  // theme is only merged once.
                // }
                if let themeFeatureOpt = self._themeFeatureOption?[featureName] as? [String: Any] {
                    _ = util.merge(&featureOpt, themeFeatureOpt, false)
                    // Follow the previous behavior, theme is only merged once.
                    self._themeFeatureOption?[featureName] = nil
                }
                if let getDefaultOption = registration.getDefaultOption,
                   let ecModel = self.ecModel {
                    let defaultOption = getDefaultOption(ecModel)
                    // merge(featureOpt, Feature.defaultOption)  — user option wins (overwrite:false).
                    _ = util.merge(&featureOpt, defaultOption, false)
                }
                feature[featureName] = featureOpt
            }
        }
        option["feature"] = feature
        self.option = option
    }
}
