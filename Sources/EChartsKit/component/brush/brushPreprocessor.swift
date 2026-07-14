// Ported from echarts/src/component/brush/preprocessor.ts — keep in sync with upstream.
// FILE NAME: upstream `preprocessor.ts`; renamed because SwiftPM requires unique source basenames per
//   module and `chart/candlestick/preprocessor.swift` already claims that name. No identifiers change.
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

// import { normalizeToArray, removeDuplicates } from '../../util/model';  -> model.normalizeToArray / model.removeDuplicates

// const DEFAULT_TOOLBOX_BTNS: BrushToolboxIconType[] = ['rect', 'polygon', 'keep', 'clear'];
private let DEFAULT_TOOLBOX_BTNS: [String] = ["rect", "polygon", "keep", "clear"]

// export default function brushPreprocessor(option: ECUnitOption, isNew: boolean): void
//   Turns `brush: { toolbox: ['rect', 'polygon', ...] }` into the toolbox's `feature.brush.type` list —
//   i.e. it is what puts the brush BUTTONS in the toolbar (the buttons that arm the paint cursor via
//   `takeGlobalCursor`). Mutates `option` in place (inout write-back, value-type semantics — the same
//   convention as parallelPreprocessor / visualMapPreprocessor).
public func brushPreprocessor(_ option: inout [String: Any], _ isNew: Bool = true) {
    // const brushComponents = normalizeToArray(option ? option.brush : []);
    let brushComponents: [Any] = model.normalizeToArray(option["brush"])

    // if (!brushComponents.length) { return; }
    if brushComponents.isEmpty {
        return
    }

    // let brushComponentSpecifiedBtns = [] as string[];
    var brushComponentSpecifiedBtns: [String] = []

    // zrUtil.each(brushComponents, function (brushOpt: BrushOption) {
    //     const tbs = brushOpt.hasOwnProperty('toolbox') ? brushOpt.toolbox : [];
    //     if (tbs instanceof Array) { brushComponentSpecifiedBtns = brushComponentSpecifiedBtns.concat(tbs); }
    // });
    util.each(brushComponents) { brushOptIn, _ in
        guard let brushOpt = brushOptIn as? [String: Any] else { return }
        let tbs = brushOpt.index(forKey: "toolbox") != nil ? brushOpt["toolbox"] : [Any]()
        if let arr = tbs as? [Any] {
            brushComponentSpecifiedBtns.append(contentsOf: arr.compactMap { $0 as? String })
        }
    }

    // let toolbox: ToolboxOption = option && option.toolbox;
    // if (zrUtil.isArray(toolbox)) { toolbox = toolbox[0]; }
    // if (!toolbox) { toolbox = {feature: {}}; option.toolbox = [toolbox]; }
    var toolbox: [String: Any]
    if let arr = option["toolbox"] as? [Any] {
        toolbox = (arr.first as? [String: Any]) ?? ["feature": [String: Any]()]
    }
    else if let obj = option["toolbox"] as? [String: Any] {
        toolbox = obj
    }
    else {
        toolbox = ["feature": [String: Any]()]
    }

    // const toolboxFeature = (toolbox.feature || (toolbox.feature = {}));
    var toolboxFeature = (toolbox["feature"] as? [String: Any]) ?? [String: Any]()
    // const toolboxBrush = (toolboxFeature.brush || (toolboxFeature.brush = {}));
    var toolboxBrush = (toolboxFeature["brush"] as? [String: Any]) ?? [String: Any]()
    // const brushTypes = toolboxBrush.type || (toolboxBrush.type = []);
    var brushTypes: [String] = (toolboxBrush["type"] as? [Any])?.compactMap { $0 as? String } ?? []

    // brushTypes.push.apply(brushTypes, brushComponentSpecifiedBtns);
    brushTypes.append(contentsOf: brushComponentSpecifiedBtns)

    // removeDuplicates(brushTypes, item => item + '', null);
    var seen = Set<String>()
    brushTypes = brushTypes.filter { seen.insert($0).inserted }

    // if (isNew && !brushTypes.length) { brushTypes.push.apply(brushTypes, DEFAULT_TOOLBOX_BTNS); }
    if isNew && brushTypes.isEmpty {
        brushTypes.append(contentsOf: DEFAULT_TOOLBOX_BTNS)
    }

    // Write the (value-type) sub-bags back up the chain.
    toolboxBrush["type"] = brushTypes
    toolboxFeature["brush"] = toolboxBrush
    toolbox["feature"] = toolboxFeature
    option["toolbox"] = [toolbox]
}
