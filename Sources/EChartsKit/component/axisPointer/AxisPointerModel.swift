// Ported from echarts/src/component/axisPointer/AxisPointerModel.ts — keep in sync with upstream
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

// import ComponentModel from '../../model/Component';   -> ComponentModel (model/Component.swift)
// import {
//     ComponentOption, ScaleDataValue, CommonAxisPointerOption
// } from '../../util/types';                            -> util/types.swift (same module). The option
//   tree is the dynamic `[String: Any]` bag (CONVENTIONS §2); the TS `AxisPointerOption` interface
//   already exists as a stub typealias in tooltip/TooltipModel.swift (`= [String: Any]`) — NOT
//   redeclared here to avoid a duplicate symbol.
// import tokens from '../../visual/tokens';             -> `tokens` (visual/tokens.swift)

// interface MapperParamAxisInfo / AxisPointerLink / AxisPointerOption:
//   -> The `link` mapper/param shapes and the per-axis option surface are consumed dynamically through
//      the `[String: Any]` bag (see modelHelper `getLinkGroupIndex` / `checkPropInLink`), so the TS
//      interfaces are documentary. `AxisPointerOption` is the module-level typealias declared in
//      tooltip/TooltipModel.swift.

// class AxisPointerModel extends ComponentModel<AxisPointerOption>
open class AxisPointerModel: ComponentModel {

    // static type = 'axisPointer' as const;
    // type = AxisPointerModel.type;   (instance `type` mirrors the static via ComponentModel)
    public override class var type: ComponentFullType { return "axisPointer" }

    // Will be injected and read in modelHelper and axisTrigger.
    // No need to care about it.
    //   upstream: `coordSysAxesInfo: unknown;` — the `CollectionResult` produced by
    //   `modelHelper.collect(...)` is stashed here by the axisPointer processor (install) and read
    //   back by `modelHelper.getAxisInfo`. Modeled as `Any?` (holds a `CollectionResult`).
    public var coordSysAxesInfo: Any?

    // static defaultOption: AxisPointerOption = { ... }
    public override class var defaultOption: ModelOption? {
        return [
            // 'auto' means that show when triggered by tooltip or handle.
            "show": "auto",

            // zlevel: 0,
            "z": 50.0,

            "type": "line",   // 'line' 'shadow' 'cross' 'none'.
            // axispointer triggered by tootip determine snap automatically,
            // see `modelHelper`.
            "snap": false,
            "triggerTooltip": true,
            "triggerEmphasis": true,

            "value": NSNull(),   // null
            "status": NSNull(),  // null — Init value depends on whether handle is used.

            "link": [] as [Any],

            // Do not set 'auto' here, otherwise global animation: false
            // will not effect at this axispointer.
            "animation": NSNull(),   // null
            "animationDurationUpdate": 200.0,

            "lineStyle": [
                "color": tokens.color.border,
                "width": 1.0,
                "type": "dashed"
            ] as [String: Any],

            "shadowStyle": [
                "color": tokens.color.shadowTint
            ] as [String: Any],

            "label": [
                "show": true,
                "formatter": NSNull(),   // null — string | Function
                "precision": "auto",     // Or a number like 0, 1, 2 ...
                "margin": 3.0,
                "color": tokens.color.neutral00,
                "padding": [5.0, 7.0, 5.0, 7.0],
                "backgroundColor": tokens.color.accent60,   // default: axis line color
                "borderColor": NSNull(),   // null
                "borderWidth": 0.0,
                "borderRadius": 3.0
            ] as [String: Any],

            "handle": [
                "show": false,
                // eslint-disable-next-line
                "icon": "M10.7,11.9v-1.3H9.3v1.3c-4.9,0.3-8.8,4.4-8.8,9.4c0,5,3.9,9.1,8.8,9.4h1.3c4.9-0.3,8.8-4.4,8.8-9.4C19.5,16.3,15.6,12.2,10.7,11.9z M13.3,24.4H6.7v-1.2h6.6z M13.3,22H6.7v-1.2h6.6z M13.3,19.6H6.7v-1.2h6.6z",
                "size": 45.0,
                // handle margin is from symbol center to axis, which is stable when circular move.
                "margin": 50.0,
                // color: '#1b8bbd'
                // color: '#2f4554'
                "color": tokens.color.accent40,

                // For mobile performance
                "throttle": 40.0
            ] as [String: Any]
        ] as [String: Any]
    }
}

// export default AxisPointerModel;  -> `open class AxisPointerModel` above.
