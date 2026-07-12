// Ported from echarts/src/coord/calendar/CalendarModel.ts — keep in sync with upstream
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

// import * as zrUtil from 'zrender/src/core/util';                    -> `util.*` (ZRenderKit) / inline (isArray checks below)
// import ComponentModel from '../../model/Component';                 -> ComponentModel (model/Component.swift)
// import { getLayoutParams, sizeCalculable, mergeLayoutParam }
//     from '../../util/layout';                                       -> layout.mergeLayoutParam (util/layout.swift).
//     PORT-NOTE (deferred): requires util/layout `getLayoutParams` / `sizeCalculable` (confirmed absent
//     from the partial util/layout.swift port, which covers only the cartesian surface). They are
//     faithfully reproduced here as file-scope helpers (calendarGetLayoutParams / calendarSizeCalculable)
//     and should be folded into the `layout` namespace once the full util/layout.ts port lands.
// import Calendar from './Calendar';                                  -> Calendar (coord/calendar/Calendar.swift — coord-sys master; sibling in a later phase)
// import {
//     ComponentOption, BoxLayoutOptionMixin, LayoutOrient, LineStyleOption,
//     ItemStyleOption, LabelOption, OptionDataValueDate
// } from '../../util/types';                                          -> option interfaces dropped (dynamic option bag, CONVENTIONS §2)
// import GlobalModel from '../../model/Global';                       -> GlobalModel (model/Global.swift)
// import Model from '../../model/Model';                              -> Model (model/Model.swift)
// import { CoordinateSystemHostModel } from '../CoordinateSystem';    -> CoordinateSystemHostModel (coord/CoordinateSystem.swift)
// import tokens from '../../visual/tokens';                           -> tokens.* (visual/tokens.ts not ported yet; values inlined below, see NOTE)

// upstream:
// export interface CalendarMonthLabelFormatterCallbackParams { nameMap; yyyy; yy; MM; M }
// export interface CalendarYearLabelFormatterCallbackParams { nameMap; start; end }
// export interface CalendarOption extends ComponentOption, BoxLayoutOptionMixin { ... }
//   PORT-NOTE: the label-formatter callback param interfaces and `CalendarOption` describe the dynamic
//   option shape; modeled as the dynamic option bag ([String: Any]) per CONVENTIONS §2 — no standalone
//   Swift structs emitted. The `formatter` callbacks are stored as closures in the bag at use time.

// NOTE: visual/tokens.ts is not ported yet (visual/ lands in a later phase). The individual `tokens.*`
// values consumed by `defaultOption` are inlined verbatim as their resolved constants (mirrors
// coord/axisDefault.swift). Re-wire to the real `tokens` namespace once visual/tokens.swift lands:
//   tokens.color.axisLine  = color.neutral70 = '#54555a'
//   tokens.color.neutral00 =                   '#fff'
//   tokens.color.neutral10 =                   '#e8ebf0'
//   tokens.color.secondary = color.neutral70 = '#54555a'
//   tokens.color.quaternary = color.neutral50 = '#86878c'
//   tokens.size.s  = 10
//   tokens.size.xl = 30

// upstream: class CalendarModel extends ComponentModel<CalendarOption>
//     implements CoordinateSystemHostModel { ... }
//   Component reference type -> `final class : ComponentModel, CoordinateSystemHostModel` (mirrors PolarModel).
public final class CalendarModel: ComponentModel, CoordinateSystemHostModel {

    // static type = 'calendar';
    // type = CalendarModel.type;  (the instance `type` mirrors the static via ComponentModel's `type`.)
    public override class var type: ComponentFullType { return "calendar" }

    // coordinateSystem: Calendar;
    //   PORT-NOTE: upstream types this the concrete `Calendar` (a `CoordinateSystemMaster`), injected once
    //   the coordinate system is built. `Calendar` (coord/calendar/Calendar.swift) is a sibling in a later
    //   phase; typed here as the `CoordinateSystemMaster?` required by `CoordinateSystemHostModel`
    //   (narrow via `as? Calendar` at use), mirroring PolarModel.
    public var coordinateSystem: CoordinateSystemMaster?

    // static layoutMode = 'box' as const;
    public override class var layoutMode: Any? { return "box" }

    /**
     * @override
     */
    // init(option: CalendarOption, parentModel: Model, ecModel: GlobalModel) {
    //     const inputPositionParams = getLayoutParams(option);
    //     super.init.apply(this, arguments as any);
    //     mergeAndNormalizeLayoutParams(option, inputPositionParams);
    // }
    //   `getLayoutParams(option)` reads the RAW user option (before super.init merges defaults), so the
    //   position params are captured from the `option` param up front. After `super.init` merges defaults,
    //   upstream's in-place mutation of `option` (=== self.option) is mirrored by reading/writing self.option.
    public override func `init`(_ option: ModelOption?, _ parentModel: Model? = nil, _ ecModel: GlobalModel? = nil, _ rest: Any...) {
        let inputPositionParams = calendarGetLayoutParams((option as? [String: Any]) ?? [:])

        super.`init`(option, parentModel, ecModel)

        if var target = self.option as? [String: Any] {
            mergeAndNormalizeLayoutParams(&target, inputPositionParams)
            self.option = target
        }
    }

    /**
     * @override
     */
    // mergeOption(option: CalendarOption) {
    //     super.mergeOption.apply(this, arguments as any);
    //     mergeAndNormalizeLayoutParams(this.option, option);
    // }
    public override func mergeOption(_ option: ModelOption?, _ ecModel: GlobalModel?) {
        super.mergeOption(option, ecModel)

        if var target = self.option as? [String: Any] {
            mergeAndNormalizeLayoutParams(&target, (option as? [String: Any]) ?? [:])
            self.option = target
        }
    }

    // getCellSize() {
    //     // Has been normalized
    //     return this.option.cellSize as (number | 'auto')[];
    // }
    //   `cellSize` has been normalized to a `[number | 'auto']` array by mergeAndNormalizeLayoutParams;
    //   entries are Double or the String "auto" boxed in `Any`.
    public func getCellSize() -> [Any] {
        return (self.option as? [String: Any])?["cellSize"] as? [Any] ?? []
    }

    // static defaultOption: CalendarOption = { ... }
    //   Numbers -> Double (CONVENTIONS §1) so a bare `as? Double` read does not silently drop them
    //   (INT-vs-DOUBLE option-read trap).
    public override class var defaultOption: ModelOption? {
        return [
            // zlevel: 0,
            // TODO(upstream): theoretically, the z of the calendar should be lower than series, but we
            // don't want the series to be displayed on top of the borders like month split line. To align
            // with previous versions, z is set to 2 for now until a better solution is found.
            "z": 2.0,
            "left": 80.0,
            "top": 60.0,

            "cellSize": 20.0,

            // horizontal vertical
            "orient": "horizontal",

            // month separate line style
            "splitLine": [
                "show": true,
                "lineStyle": [
                    "color": "#54555a",       // tokens.color.axisLine
                    "width": 1.0,
                    "type": "solid"
                ] as [String: Any]
            ] as [String: Any],

            // rect style  temporarily unused emphasis
            "itemStyle": [
                "color": "#fff",              // tokens.color.neutral00
                "borderWidth": 1.0,
                "borderColor": "#e8ebf0"      // tokens.color.neutral10
            ] as [String: Any],

            // week text style
            "dayLabel": [
                "show": true,

                "firstDay": 0.0,

                // start end
                "position": "start",
                "margin": 10.0,               // tokens.size.s
                "color": "#54555a"            // tokens.color.secondary
            ] as [String: Any],

            // month text style
            "monthLabel": [
                "show": true,

                // start end
                "position": "start",
                "margin": 10.0,               // tokens.size.s

                // center or left
                "align": "center",

                "formatter": NSNull(),
                "color": "#54555a"            // tokens.color.secondary
            ] as [String: Any],

            // year text style
            "yearLabel": [
                "show": true,

                // top bottom left right
                "position": NSNull(),
                "margin": 30.0,               // tokens.size.xl
                "formatter": NSNull(),
                "color": "#86878c",           // tokens.color.quaternary
                "fontFamily": "sans-serif",
                "fontWeight": "bolder",
                "fontSize": 20.0
            ] as [String: Any]
        ] as [String: Any]
    }
}

// upstream: function mergeAndNormalizeLayoutParams(target: CalendarOption, raw: BoxLayoutOptionMixin) { ... }
//   Module-private function -> file-scope function operating on the dynamic option bags. `target` is
//   mutated in place upstream (cellSize normalization + mergeLayoutParam); mirrored via `inout`.
private func mergeAndNormalizeLayoutParams(_ target: inout [String: Any], _ raw: [String: Any]) {
    // Normalize cellSize
    // const cellSize = target.cellSize;
    // let cellSizeArr: (number | 'auto')[];
    let cellSize = target["cellSize"]
    var cellSizeArr: [Any]

    // if (!zrUtil.isArray(cellSize)) {
    //     cellSizeArr = target.cellSize = [cellSize, cellSize];
    // } else { cellSizeArr = cellSize; }
    if let arr = cellSize as? [Any] {
        cellSizeArr = arr
    }
    else {
        let cs: Any = cellSize ?? NSNull()
        cellSizeArr = [cs, cs]
        target["cellSize"] = cellSizeArr
    }

    // if (cellSizeArr.length === 1) { cellSizeArr[1] = cellSizeArr[0]; }
    if cellSizeArr.count == 1 {
        cellSizeArr.append(cellSizeArr[0])
    }

    // const ignoreSize = zrUtil.map([0, 1], function (hvIdx) {
    //     if (sizeCalculable(raw, hvIdx)) { cellSizeArr[hvIdx] = 'auto'; }
    //     return cellSizeArr[hvIdx] != null && cellSizeArr[hvIdx] !== 'auto';
    // });
    var ignoreSize: [Bool] = []
    for hvIdx in [0, 1] {
        // If user has set `width` or both `left` and `right`, cellSizeArr will be automatically set to
        // 'auto', otherwise the default setting of cellSizeArr will make `width` setting not work.
        if calendarSizeCalculable(raw, hvIdx) {
            cellSizeArr[hvIdx] = "auto"
        }
        let v = cellSizeArr[hvIdx]
        let notNull = !(v is NSNull)
        ignoreSize.append(notNull && !((v as? String) == "auto"))
    }
    // Persist the mutated cellSize array (upstream mutates the array reference in place).
    target["cellSize"] = cellSizeArr

    // mergeLayoutParam(target, raw, { type: 'box', ignoreSize: ignoreSize });
    layout.mergeLayoutParam(&target, raw, ["type": "box", "ignoreSize": ignoreSize] as [String: Any])
}

// PORT-NOTE: faithful reproduction of util/layout.ts `getLayoutParams` + `copyLayoutParams({}, source)`
// and `sizeCalculable` (+ their `LOCATION_PARAMS` / `HV_NAMES` tables), which are not yet in the partial
// `layout` port. Fold these into the `layout` namespace when the full util/layout.ts port lands.

// upstream: export const LOCATION_PARAMS = ['left','right','top','bottom','width','height'] as const;
private let CALENDAR_LOCATION_PARAMS = ["left", "right", "top", "bottom", "width", "height"]

// upstream: export const HV_NAMES = [['width','left','right'], ['height','top','bottom']] as const;
private let CALENDAR_HV_NAMES = [
    ["width", "left", "right"],
    ["height", "top", "bottom"]
]

// upstream:
// export function getLayoutParams(source) { return copyLayoutParams({}, source); }
// export function copyLayoutParams(target, source) {
//     source && target && each(LOCATION_PARAMS, name => { hasOwn(source, name) && (target[name] = source[name]); });
//     return target;
// }
private func calendarGetLayoutParams(_ source: [String: Any]) -> [String: Any] {
    var target: [String: Any] = [:]
    for name in CALENDAR_LOCATION_PARAMS {
        if let v = source[name] {
            target[name] = v
        }
    }
    return target
}

// upstream:
// export function sizeCalculable(option, hvIdx) {
//     return option[HV_NAMES[hvIdx][0]] != null
//         || (option[HV_NAMES[hvIdx][1]] != null && option[HV_NAMES[hvIdx][2]] != null);
// }
//   JS `!= null` treats both `null` and `undefined` as absent → in the bag, a key that is missing OR
//   holds NSNull is "absent".
private func calendarSizeCalculable(_ option: [String: Any], _ hvIdx: Int) -> Bool {
    func present(_ key: String) -> Bool {
        guard let v = option[key] else { return false }
        return !(v is NSNull)
    }
    return present(CALENDAR_HV_NAMES[hvIdx][0])
        || (present(CALENDAR_HV_NAMES[hvIdx][1]) && present(CALENDAR_HV_NAMES[hvIdx][2]))
}

// export default CalendarModel;  -> `public final class CalendarModel` above.
