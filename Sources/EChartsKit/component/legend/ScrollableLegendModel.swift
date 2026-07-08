// Ported from echarts/src/component/legend/ScrollableLegendModel.ts — keep in sync with upstream
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

// upstream imports (mapped to this port):
//   import LegendModel, {LegendOption} from './LegendModel';       -> `LegendModel` (the base class).
//   import { mergeLayoutParam, getLayoutParams } from '../../util/layout';
//     -> `layout.mergeLayoutParam` (util/layout.swift). `getLayoutParams(source)` upstream is just
//        `copyLayoutParams({}, source)`, so it maps to `layout.copyLayoutParams([:], source)`.
//   import { ZRColor, LabelOption } from '../../util/types';        -> (type-only; the dynamic bag).
//   import Model from '../../model/Model';                          -> `Model`.
//   import GlobalModel from '../../model/Global';                   -> `GlobalModel`.
//   import { inheritDefaultOption } from '../../util/component';    -> `component.inheritDefaultOption`.
//   import tokens from '../../visual/tokens';
//     -> PORT-TODO: visual/tokens.ts not ported; the consumed constants are inlined verbatim
//        (same deviation as LegendModel.swift):
//          tokens.color.accent50 = '#6578ba'
//          tokens.color.accent10 = '#e0e4f2'
//          tokens.color.tertiary = neutral60 = '#6d6e73'

// interface ScrollableLegendOption extends LegendOption { scrollDataIndex, pageButtonItemGap,
//   pageButtonGap, pageButtonPosition, pageFormatter, pageIcons, pageIconColor, pageIconInactiveColor,
//   pageIconSize, pageTextStyle, animationDurationUpdate }
//   -> collapsed into the dynamic `[String: Any]` option bag (CONVENTIONS §2); the fields are set in
//      `defaultOption` below.

// class ScrollableLegendModel extends LegendModel<ScrollableLegendOption>
//   -> generic `Ops` dropped per CONVENTIONS §2. `open` because the view resolves it by subtype.
open class ScrollableLegendModel: LegendModel {

    // static type = 'legend.scroll';
    // type = ScrollableLegendModel.type;
    public override class var type: ComponentFullType { return "legend.scroll" }

    // setScrollDataIndex(scrollDataIndex: number) { this.option.scrollDataIndex = scrollDataIndex; }
    open func setScrollDataIndex(_ scrollDataIndex: Double) {
        guard var opt = self.option as? [String: Any] else { return }
        opt["scrollDataIndex"] = scrollDataIndex
        self.option = opt
    }

    // init(option, parentModel, ecModel)
    open override func `init`(
        _ option: ModelOption?, _ parentModel: Model? = nil, _ ecModel: GlobalModel? = nil, _ rest: Any...
    ) {
        // const inputPositionParams = getLayoutParams(option);
        let inputPositionParams = layout.copyLayoutParams([:], (option as? [String: Any]) ?? [:])

        // super.init(option, parentModel, ecModel);
        super.`init`(option, parentModel, ecModel)

        // mergeAndNormalizeLayoutParams(this, option, inputPositionParams);
        //   (upstream `target === option === this.option`; here we normalize onto `self.option`.)
        scrollableMergeAndNormalizeLayoutParams(self, inputPositionParams)
    }

    // mergeOption(option, ecModel)
    open override func mergeOption(_ option: ModelOption?, _ ecModel: GlobalModel?) {
        // super.mergeOption(option, ecModel);
        super.mergeOption(option, ecModel)
        // mergeAndNormalizeLayoutParams(this, this.option, option);
        scrollableMergeAndNormalizeLayoutParams(self, (option as? [String: Any]) ?? [:])
    }

    // static defaultOption = inheritDefaultOption(LegendModel.defaultOption, { ... });
    public override class var defaultOption: ModelOption? {
        return component.inheritDefaultOption(
            (LegendModel.defaultOption as? [String: Any]) ?? [:],
            [
                "scrollDataIndex": 0.0,
                "pageButtonItemGap": 5.0,
                // pageButtonGap: null (represented by absence; retrieve2 falls back to itemGap).
                "pageButtonGap": NSNull(),
                "pageButtonPosition": "end",   // 'start' or 'end'
                // If null/undefined, do not show page.
                "pageFormatter": "{current}/{total}",
                "pageIcons": [
                    "horizontal": ["M0,0L12,-10L12,10z", "M0,0L-12,-10L-12,10z"] as [Any],
                    "vertical": ["M0,0L20,0L10,-20z", "M0,0L20,0L10,20z"] as [Any]
                ] as [String: Any],
                "pageIconColor": "#6578ba",           // tokens.color.accent50
                "pageIconInactiveColor": "#e0e4f2",   // tokens.color.accent10
                // Can be [10, 3], which represents [width, height]
                "pageIconSize": 15.0,
                "pageTextStyle": [
                    "color": "#6d6e73"                // tokens.color.tertiary
                ] as [String: Any],

                "animationDurationUpdate": 800.0
            ]
        )
    }
}

// Do not `ignoreSize` to enable setting {left: 10, right: 10}.
//   NOTE (faithful to upstream): the `ignoreSize` array is computed but then passed through `!!ignoreSize`
//   which — since a JS array is always truthy — collapses to the boolean `true`. So `mergeLayoutParam`
//   always receives `ignoreSize: true` here. Reproduced exactly.
private func scrollableMergeAndNormalizeLayoutParams(
    _ legendModel: ScrollableLegendModel,
    _ raw: [String: Any]
) {
    let orient = legendModel.getOrient()
    var ignoreSize = [1, 1]
    ignoreSize[Int(orient.index)] = 0
    _ = ignoreSize   // computed for fidelity; `!!ignoreSize` (array truthy) === true (see note above).
    guard var target = legendModel.option as? [String: Any] else { return }
    layout.mergeLayoutParam(&target, raw, ["type": "box", "ignoreSize": true])
    legendModel.option = target
}

// export default ScrollableLegendModel; -> `open class ScrollableLegendModel` above.
