// Ported from echarts/src/component/tooltip/TooltipModel.ts — keep in sync with upstream
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
// import { ComponentOption, LabelOption, LineStyleOption, CommonTooltipOption, TooltipRenderMode,
//          CallbackDataParams, TooltipOrderMode } from '../../util/types';
//   -> The option tree is modeled as the `[String: Any]` bag (CONVENTIONS §2); the TS
//      `TooltipOption` interface is exported as a typealias below, not a struct. The referenced
//      option/param types (CallbackDataParams, TooltipRenderMode, TooltipOrderMode,
//      CommonTooltipOption) already live in util/types.swift.
// import tokens from '../../visual/tokens';             -> `tokens` (visual/tokens.swift)
// import {AxisPointerOption} from '../axisPointer/AxisPointerModel';
//   -> PORT-NOTE: axisPointer/AxisPointerModel is ported (component/axisPointer/AxisPointerModel.swift).
//      `AxisPointerOption` is still kept below as an untyped option bag; the `axisPointer` sub-option
//      in `defaultOption` is emitted as a plain `[String: Any]` literal.

// PORT-NOTE: axisPointer/AxisPointerModel is ported; `AxisPointerOption` kept as an untyped bag here.
public typealias AxisPointerOption = [String: Any]

// export type TopLevelFormatterParams = CallbackDataParams | CallbackDataParams[];
//   -> an untagged TS union becomes a TAGGED ENUM (PORTING.md §9). This is the `params` a
//      `tooltip.formatter` receives, and what `TooltipView._showTooltipContent` threads
//      (TooltipView.ts:817): `trigger:'item'` hands the formatter ONE params object, `trigger:'axis'`
//      the LIST of every listed series' params at the hovered axis value.
//      `TooltipCallbackDataParams` (component/tooltip/TooltipView.swift) is upstream's
//      `CallbackDataParams & { axisDim?, … }` intersection.
public enum TopLevelFormatterParams {
    case single(TooltipCallbackDataParams)
    case multiple([TooltipCallbackDataParams])
    // PORT-NOTE (divergence, LANGUAGE constraint — no upstream TYPE analogue, but upstream BEHAVIOUR):
    //   the COMPONENT-item tooltip path (`TooltipView._showComponentItemTooltip`, TooltipView.ts:740)
    //   hands `_showTooltipContent` the element's `ecData.tooltipConfig.option.formatterParams` — a
    //   `ComponentItemTooltipLabelFormatterParams` (`{componentType, name, $vars, ...extra}`,
    //   util/types.swift), NOT a `CallbackDataParams` — through an `as any` cast
    //   (`clone(subTooltipModel.get('formatterParams') as any || {})`, TooltipView.ts:794). TS erases
    //   that; Swift cannot. Forcing it into `.single` would need a `CallbackDataParams`, whose fixed
    //   field set would DROP every `formatterParamsExtra` key the component views stamp (toolbox
    //   `title`, matrix `xyLocator`, axis `value`/`tickIndex`) — and those keys are exactly the
    //   `$vars` a component `tooltip.formatter` addresses (`{b}`, `{c}`, …). So the union carries the
    //   third arm upstream's `as any` implies, and every `switch` over it handles a component's
    //   params the way upstream's JS does at that point.
    case component(ComponentItemTooltipLabelFormatterParams)
}

// export interface TooltipOption extends CommonTooltipOption<TopLevelFormatterParams>, ComponentOption
//   -> the dynamic option bag. `tooltipMarkup` reads it through `Model` / `TooltipModel`; the fields
//      documented in the TS interface (showContent / trigger / renderMode / order / axisPointer /
//      defaultBorderColor / …) live in this bag.
public typealias TooltipOption = [String: Any]

// class TooltipModel extends ComponentModel<TooltipOption>
open class TooltipModel: ComponentModel {

    // static type = 'tooltip' as const;
    // type = TooltipModel.type;   (instance `type` mirrors the static in ComponentModel)
    public override class var type: ComponentFullType { return "tooltip" }

    // static dependencies = ['axisPointer'];
    public override class var dependencies: [String] { return ["axisPointer"] }

    // static defaultOption: TooltipOption = { ... }
    public override class var defaultOption: ModelOption? {
        return [
            // zlevel: 0,

            "z": 60.0,

            "show": true,

            // tooltip main content
            "showContent": true,

            // 'trigger' only works on coordinate system.
            // 'item' | 'axis' | 'none'
            "trigger": "item",

            // 'click' | 'mousemove' | 'none'
            "triggerOn": "mousemove|click|mousewheel",

            "alwaysShowContent": false,

            "renderMode": "auto",   // 'auto' | 'html' | 'richText'

            // whether restraint content inside viewRect.
            // If renderMode: 'richText', default true.
            // If renderMode: 'html', defaults to `false` (for backward compat).
            "confine": NSNull(),   // null

            "showDelay": 0.0,

            "hideDelay": 100.0,

            // Animation transition time, unit is second
            "transitionDuration": 0.4,

            "displayTransition": true,

            "enterable": false,

            "backgroundColor": tokens.color.neutral00,

            // box shadow
            "shadowBlur": 10.0,
            "shadowColor": "rgba(0, 0, 0, .2)",
            "shadowOffsetX": 1.0,
            "shadowOffsetY": 2.0,

            // tooltip border radius, unit is px, default is 4
            "borderRadius": 4.0,

            // tooltip border width, unit is px, default is 0 (no border)
            "borderWidth": 1.0,

            "defaultBorderColor": tokens.color.border,

            // Tooltip inside padding, default is 5 for all direction
            // Array is allowed to set up, right, bottom, left, same with css
            // The default value: See `tooltip/tooltipMarkup.ts#getPaddingFromTooltipModel`.
            "padding": NSNull(),   // null

            // Extra css text
            "extraCssText": "",

            // axis indicator, trigger by axis
            // PORT-NOTE: AxisPointerModel is ported; this sub-option is still emitted as a plain option bag.
            "axisPointer": [
                // default is line
                // legal values: 'line' | 'shadow' | 'cross'
                "type": "line",

                // Valid when type is line, appoint tooltip line locate on which line. Optional
                // legal values: 'x' | 'y' | 'angle' | 'radius' | 'auto'
                // default is 'auto', chose the axis which type is category.
                // for multiply y axis, cartesian coord chose x axis, polar chose angle axis
                "axis": "auto",

                "animation": "auto",
                "animationDurationUpdate": 200.0,
                "animationEasingUpdate": "exponentialOut",

                "crossStyle": [
                    "color": tokens.color.borderShade,
                    "width": 1.0,
                    "type": "dashed",

                    // TODO formatter
                    "textStyle": [:] as [String: Any]
                ] as [String: Any]

                // lineStyle and shadowStyle should not be specified here,
                // otherwise it will always override those styles on option.axisPointer.
            ] as [String: Any],
            "textStyle": [
                "color": tokens.color.tertiary,
                "fontSize": 14.0
            ] as [String: Any]
        ] as [String: Any]
    }
}
