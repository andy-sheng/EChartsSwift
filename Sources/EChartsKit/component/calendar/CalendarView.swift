// Ported from echarts/src/component/calendar/CalendarView.ts — keep in sync with upstream
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

// upstream imports (mapped to this port; `→` marks the Swift symbol used):
//   import { isString, extend, map, isFunction } from 'zrender/src/core/util';
//     → ZRenderKit `util.isString` / `util.extend` / `util.map` / `util.isFunction`.
//   import * as graphic from '../../util/graphic';
//     → `util/graphic` is NOT ported as a namespace. `graphic.Group` / `graphic.Rect` / `graphic.Polyline`
//       / `graphic.Text` are the ZRenderKit scene-graph types (`Group` / `Rect` / `Polyline` / `ZRText`),
//       used directly — the sanctioned DRAWING deviation (cf. SingleAxisView / FunnelView).
//   import {createTextStyle} from '../../label/labelStyle';
//     → PORT-TODO: `label/labelStyle` NOT ported. The file-private `calendarCreateTextStyle` below is a
//       minimal faithful reproduction (text + font + fill), mirroring AxisBuilder/FunnelView/Breadcrumb.
//   import { formatTplSimple } from '../../util/format';           → `format.formatTplSimple`.
//   import { parsePercent } from '../../util/number';              → `number.parsePercent`.
//   import type CalendarModel from '../../coord/calendar/CalendarModel';  → `CalendarModel` (sibling).
//   import {CalendarParsedDateRangeInfo, CalendarParsedDateInfo} from '../../coord/calendar/Calendar';
//     → `CalendarParsedDateRangeInfo` / `CalendarParsedDateInfo` (assumed structs from the `Calendar`
//       coord sibling — see below).
//   import type GlobalModel from '../../model/Global';            → `GlobalModel`.
//   import type ExtensionAPI from '../../core/ExtensionAPI';      → `ExtensionAPI`.
//   import { LayoutOrient, OptionDataValueDate, ZRTextAlign, ZRTextVerticalAlign } from '../../util/types';
//     → `LayoutOrient` (enum), `OptionDataValueDate` (= Any), `ZRTextAlign` (= TextAlign),
//       `ZRTextVerticalAlign` (= TextVerticalAlign).
//   import ComponentView from '../../view/Component';             → `ComponentView` (view/ComponentView.swift).
//   import { PathStyleProps } from 'zrender/src/graphic/Path';    → ZRenderKit `PathStyleProps`.
//   import { TextStyleProps, TextProps } from 'zrender/src/graphic/Text';
//     → ZRenderKit `TextStyleProps` / `TextProps` (`TextProps` = `DisplayableProps` = `ElementProps`).
//   import { LocaleOption, getLocaleModel } from '../../core/locale';
//     → PORT-TODO: `core/locale` NOT ported. `ecModel.getLocaleModel()` (→ `Model`) supplies the default
//       locale; the by-name `getLocaleModel(nameMap)` reassignment is deferred (see PORT-TODOs below).
//   import type Model from '../../model/Model';                   → `Model`.
//
//   The sibling `Calendar` (`CalendarModel.coordinateSystem`) is the calendar COORDINATE SYSTEM (the 6th),
//   a grid of day cells keyed by DATE, forward-referenced by calendarPrepareCustom.swift and landing in a
//   later phase (coord/calendar/Calendar.swift). Assumed API (mirrors upstream Calendar.ts):
//     final class Calendar: CoordinateSystemMaster {
//         func getRangeInfo() -> CalendarParsedDateRangeInfo
//         func getOrient() -> LayoutOrient
//         func getCellWidth() -> Double
//         func getCellHeight() -> Double
//         func getFirstDayOfWeek() -> Double
//         func getDateInfo(_ date: OptionDataValueDate) -> CalendarParsedDateInfo
//         func getNextNDay(_ date: OptionDataValueDate, _ n: Double) -> CalendarParsedDateInfo
//         func dataToCalendarLayout(_ data: [OptionDataValueDate], _ clamp: Bool) -> CalendarCellRect
//     }
//   with `CalendarModel.coordinateSystem: CoordinateSystemMaster?` (already ported) downcast to `Calendar`,
//   and the assumed value structs:
//     struct CalendarParsedDateInfo { y: String; m: String; d: String; day: Double; time: Double;
//                                     formatedDate: String; date: Foundation.Date }
//     struct CalendarParsedDateRangeInfo { start: CalendarParsedDateInfo; end: CalendarParsedDateInfo;
//                                          weeks: Double; fweek: Double; lweek: Double; ... }
//     struct CalendarCellRect { center: [Double]; tl: [Double]; tr: [Double]; br: [Double]; bl: [Double] }

// upstream: class CalendarView extends ComponentView { ... }
// CONVENTIONS §2/§4: reference type extending the reference `ComponentView` → `final class`.
public final class CalendarView: ComponentView {

    // upstream: static type = 'calendar';
    public static let type = "calendar"
    // upstream: type = CalendarView.type;
    public let type = "calendar"

    /**
     * top/left line points
     */
    // upstream: private _tlpoints: number[][];
    private var _tlpoints: [[Double]] = []

    /**
     * bottom/right line points
     */
    // upstream: private _blpoints: number[][];
    private var _blpoints: [[Double]] = []

    /**
     * first day of month
     */
    // upstream: private _firstDayOfMonth: CalendarParsedDateInfo[];
    private var _firstDayOfMonth: [CalendarParsedDateInfo] = []

    /**
     * first day point of month
     */
    // upstream: private _firstDayPoints: number[][];
    private var _firstDayPoints: [[Double]] = []

    // upstream: render(calendarModel: CalendarModel, ecModel: GlobalModel, api: ExtensionAPI)
    //   The base `ComponentView.render` signature is (model, ecModel, api, payload); upstream declares
    //   only (calendarModel, ecModel, api) (payload optional in JS). The override matches the full base
    //   signature and narrows `model` to `CalendarModel` (cf. TitleView.render / SingleAxisView.render).
    public override func render(
        _ calendarModel: ComponentModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        let calendarModel = calendarModel as! CalendarModel

        let group = self.group

        _ = group.removeAll()

        // upstream: const coordSys = calendarModel.coordinateSystem;
        let coordSys = calendarModel.coordinateSystem as! Calendar

        // range info
        let rangeData = coordSys.getRangeInfo()
        let orient = coordSys.getOrient()

        // locale
        let localeModel = ecModel.getLocaleModel()

        self._renderDayRect(calendarModel, rangeData, group)

        // _renderLines must be called prior to following function
        self._renderLines(calendarModel, rangeData, orient, group)

        self._renderYearText(calendarModel, rangeData, orient, group)

        self._renderMonthText(calendarModel, localeModel, orient, group)

        self._renderWeekText(calendarModel, localeModel, rangeData, orient, group)
    }

    // render day rect
    private func _renderDayRect(
        _ calendarModel: CalendarModel, _ rangeData: CalendarParsedDateRangeInfo, _ group: Group
    ) {
        let coordSys = calendarModel.coordinateSystem as! Calendar
        let itemRectStyleModel = calendarModel.getModel("itemStyle").getItemStyle()
        let sw = coordSys.getCellWidth()
        let sh = coordSys.getCellHeight()

        // upstream: for (let i = rangeData.start.time; i <= rangeData.end.time; i = coordSys.getNextNDay(i, 1).time)
        var i = rangeData.start.time
        while i <= rangeData.end.time {

            let point = coordSys.dataToCalendarLayout([i], false).tl

            // every rect
            // upstream: new graphic.Rect({ shape: {x, y, width, height}, cursor: 'default', style: itemRectStyleModel })
            var shape = RectShape()
            shape.x = point[0]
            shape.y = point[1]
            shape.width = sw
            shape.height = sh
            let rect = Rect(["shape": shape as PathShape])
            rect.cursor = "default"
            rect.useStyle(calendarPathStyleFromDict(itemRectStyleModel))

            _ = group.add(rect)

            i = coordSys.getNextNDay(i, 1).time
        }

    }

    // render separate line
    private func _renderLines(
        _ calendarModel: CalendarModel,
        _ rangeData: CalendarParsedDateRangeInfo,
        _ orient: LayoutOrient,
        _ group: Group
    ) {

        // upstream: const self = this;  — the nested `addPoints` closure captures `self` directly.

        let coordSys = calendarModel.coordinateSystem as! Calendar

        // upstream: const lineStyleModel = calendarModel.getModel(['splitLine', 'lineStyle']).getLineStyle();
        //   getLineStyle() returns the dynamic style bag ([String: Any]); bridged once to `PathStyleProps`.
        let lineStyleDict = calendarModel.getModel(["splitLine", "lineStyle"]).getLineStyle()
        let lineStyleModel = calendarPathStyleFromDict(lineStyleDict)
        let show = jsTruthy(calendarModel.get(["splitLine", "show"]))

        // upstream: const lineWidth = lineStyleModel.lineWidth;
        //   Read with `numOpt` (NOT a bare `as? Double`) — the Int-vs-Double option-read trap (CONVENTIONS
        //   trap #1); default to 0 when absent (JS would carry `undefined` into `lineWidth / 2` → NaN).
        let lineWidth = numOpt(lineStyleDict["lineWidth"]) ?? 0

        self._tlpoints = []
        self._blpoints = []
        self._firstDayOfMonth = []
        self._firstDayPoints = []


        // upstream: function addPoints(date) { ... } (hoisted; called below). Modeled as a local closure.
        func addPoints(_ date: OptionDataValueDate) {

            self._firstDayOfMonth.append(coordSys.getDateInfo(date))
            self._firstDayPoints.append(coordSys.dataToCalendarLayout([date], false).tl)

            let points = self._getLinePointsOfOneWeek(calendarModel, date, orient)

            self._tlpoints.append(points[0])
            self._blpoints.append(points[points.count - 1])

            // upstream: show && self._drawSplitline(points, lineStyleModel, group);
            if show { self._drawSplitline(points, lineStyleModel, group) }
        }

        var firstDay = rangeData.start

        // upstream: for (let i = 0; firstDay.time <= rangeData.end.time; i++)
        var i = 0
        while firstDay.time <= rangeData.end.time {
            addPoints(firstDay.formatedDate)

            if i == 0 {
                firstDay = coordSys.getDateInfo(rangeData.start.y + "-" + rangeData.start.m)
            }

            // upstream: const date = firstDay.date; date.setMonth(date.getMonth() + 1);
            //   `JSDate` is a reference type, so the in-place setMonth mutation mirrors JS directly.
            //   `getDateInfo` re-parses via number.parseDate, so pass the wrapped Foundation.Date.
            let date = firstDay.date
            date.setMonth(date.getMonth() + 1)
            firstDay = coordSys.getDateInfo(date.date)

            i += 1
        }

        addPoints(coordSys.getNextNDay(rangeData.end.time, 1).formatedDate)

        // render top/left line
        // upstream: show && this._drawSplitline(self._getEdgesPoints(self._tlpoints, lineWidth, orient), lineStyleModel, group);
        if show {
            self._drawSplitline(self._getEdgesPoints(self._tlpoints, lineWidth, orient), lineStyleModel, group)
        }

        // render bottom/right line
        if show {
            self._drawSplitline(self._getEdgesPoints(self._blpoints, lineWidth, orient), lineStyleModel, group)
        }

    }

    // get points at both ends
    private func _getEdgesPoints(_ points: [[Double]], _ lineWidth: Double, _ orient: LayoutOrient) -> [[Double]] {
        // upstream: const rs = [points[0].slice(), points[points.length - 1].slice()];
        //   Swift arrays are value types, so the assignment already copies.
        var rs = [points[0], points[points.count - 1]]
        let idx = orient == .horizontal ? 0 : 1

        // both ends of the line are extend half lineWidth
        rs[0][idx] = rs[0][idx] - lineWidth / 2
        rs[1][idx] = rs[1][idx] + lineWidth / 2

        return rs
    }

    // render split line
    private func _drawSplitline(_ points: [[Double]], _ lineStyle: PathStyleProps, _ group: Group) {

        // upstream: const poyline = new graphic.Polyline({ z2: 20, shape: { points }, style: lineStyle });
        var shape = PolylineShape()
        shape.points = pointsToVector(points)
        let poyline = Polyline(["shape": shape as PathShape, "z2": 20.0])
        poyline.useStyle(lineStyle)

        _ = group.add(poyline)
    }

    // render month line of one week points
    private func _getLinePointsOfOneWeek(
        _ calendarModel: CalendarModel, _ date: OptionDataValueDate, _ orient: LayoutOrient
    ) -> [[Double]] {

        let coordSys = calendarModel.coordinateSystem as! Calendar
        let parsedDate = coordSys.getDateInfo(date)

        // upstream: const points = [];  — sparse array indexed at [2*day] / [2*day+1] (day: 0..6 → 14 slots).
        var points = [[Double]](repeating: [], count: 14)

        for i in 0..<7 {

            let tmpD = coordSys.getNextNDay(parsedDate.time, Double(i))
            let point = coordSys.dataToCalendarLayout([tmpD.time], false)

            let day = Int(tmpD.day)
            points[2 * day] = point.tl
            points[2 * day + 1] = orient == .horizontal ? point.bl : point.tr
        }

        return points

    }

    // upstream: _formatterLabel<T extends { nameMap: string }>(formatter, params)
    //   `params` is the dynamic template bag ([String: Any]); `nameMap` is read back off it.
    private func _formatterLabel(_ formatter: Any?, _ params: [String: Any]) -> String {

        if util.isString(formatter), let tpl = formatter as? String, !tpl.isEmpty {
            return format.formatTplSimple(tpl, params)
        }

        // upstream: if (isFunction(formatter)) { return formatter(params); }
        // PORT-TODO: a JS callback formatter can not be invoked from the option bag in this static port;
        //   falls through to `params.nameMap` (the default), matching the no-formatter case.
        if util.isFunction(formatter) {
            return (params["nameMap"] as? String) ?? ""
        }

        return (params["nameMap"] as? String) ?? ""

    }

    // upstream: _yearTextPositionControl(textEl, point, orient, position, margin): TextProps
    //   `textEl` is unused upstream (kept for signature parity). Returns the element-level `TextProps`
    //   (rotation / x / y) plus a `style` carrying `align`/`verticalAlign`.
    private func _yearTextPositionControl(
        _ textEl: ZRText,
        _ point: [Double],
        _ orient: LayoutOrient,
        _ position: String,   // 'left' | 'right' | 'top' | 'bottom'
        _ margin: Double
    ) -> ElementProps {

        var x = point[0]
        var y = point[1]
        var aligns: (ZRTextAlign, ZRTextVerticalAlign) = (.center, .bottom)

        if position == "bottom" {
            y += margin
            aligns = (.center, .top)
        }
        else if position == "left" {
            x -= margin
        }
        else if position == "right" {
            x += margin
            aligns = (.center, .top)
        }
        else { // top
            y -= margin
        }

        var rotate = 0.0
        if position == "left" || position == "right" {
            rotate = Double.pi / 2
        }

        var style = TextStyleProps()
        style.align = aligns.0
        style.verticalAlign = aligns.1

        return [
            "rotation": rotate,
            "x": x,
            "y": y,
            "style": style
        ]
    }

    // render year
    private func _renderYearText(
        _ calendarModel: CalendarModel,
        _ rangeData: CalendarParsedDateRangeInfo,
        _ orient: LayoutOrient,
        _ group: Group
    ) {
        let yearLabel = calendarModel.getModel("yearLabel")

        if !jsTruthy(yearLabel.get("show")) {
            return
        }

        let margin = numOpt(yearLabel.get("margin")) ?? 0
        var pos = yearLabel.get("position") as? String

        if pos == nil {
            pos = orient != .horizontal ? "top" : "left"
        }

        // upstream: const points = [this._tlpoints[this._tlpoints.length - 1], this._blpoints[0]];
        let points = [self._tlpoints[self._tlpoints.count - 1], self._blpoints[0]]
        let xc = (points[0][0] + points[1][0]) / 2
        let yc = (points[0][1] + points[1][1]) / 2

        let idx = orient == .horizontal ? 0 : 1

        let posPoints: [String: [Double]] = [
            "top": [xc, points[idx][1]],
            "bottom": [xc, points[1 - idx][1]],
            "left": [points[1 - idx][0], yc],
            "right": [points[idx][0], yc]
        ]

        // upstream: let name = rangeData.start.y;
        var name = rangeData.start.y

        // upstream: if (+rangeData.end.y > +rangeData.start.y) { name = name + '-' + rangeData.end.y; }
        if (Double(rangeData.end.y) ?? 0) > (Double(rangeData.start.y) ?? 0) {
            name = name + "-" + rangeData.end.y
        }

        let formatter = yearLabel.get("formatter")

        let params: [String: Any] = [
            "start": rangeData.start.y,
            "end": rangeData.end.y,
            "nameMap": name
        ]

        let content = self._formatterLabel(formatter, params)

        // upstream: new graphic.Text({ z2: 30, style: createTextStyle(yearLabel, {text: content}), silent: yearLabel.get('silent') })
        let yearText = ZRText([
            "z2": 30.0,
            "style": calendarCreateTextStyle(yearLabel, content),
            "silent": (yearLabel.get("silent") as? Bool) ?? false
        ])
        // upstream: yearText.attr(this._yearTextPositionControl(yearText, posPoints[pos], orient, pos, margin));
        self._applyTextProps(yearText, self._yearTextPositionControl(yearText, posPoints[pos!]!, orient, pos!, margin))

        _ = group.add(yearText)
    }

    // upstream: _monthTextPositionControl(point, isCenter, orient, position, margin): TextStyleProps
    private func _monthTextPositionControl(
        _ point: [Double],
        _ isCenter: Bool,
        _ orient: LayoutOrient,
        _ position: String,   // 'start' | 'end'
        _ margin: Double
    ) -> TextStyleProps {
        var align: ZRTextAlign = .left
        var vAlign: ZRTextVerticalAlign = .top
        var x = point[0]
        let y = point[1]
        var yy = y

        if orient == .horizontal {
            yy = yy + margin

            if isCenter {
                align = .center
            }

            if position == "start" {
                vAlign = .bottom
            }
        }
        else {
            x = x + margin

            if isCenter {
                vAlign = .middle
            }

            if position == "start" {
                align = .right
            }
        }

        var style = TextStyleProps()
        style.x = x
        style.y = yy
        style.align = align
        style.verticalAlign = vAlign
        return style
    }

    // render month and year text
    private func _renderMonthText(
        _ calendarModel: CalendarModel,
        _ localeModelIn: Model,
        _ orient: LayoutOrient,
        _ group: Group
    ) {
        let localeModel = localeModelIn
        let monthLabel = calendarModel.getModel("monthLabel")

        if !jsTruthy(monthLabel.get("show")) {
            return
        }

        let nameMapRaw = monthLabel.get("nameMap")
        var margin = numOpt(monthLabel.get("margin")) ?? 0
        let pos = (monthLabel.get("position") as? String) ?? "start"
        let align = monthLabel.get("align") as? String

        let termPoints = [self._tlpoints, self._blpoints]

        var nameMap: [Any] = []
        // upstream: if (!nameMap || isString(nameMap)) { if (nameMap) { localeModel = getLocaleModel(nameMap) || localeModel; }
        //             nameMap = localeModel.get(['time', 'monthAbbr']) || []; }
        if !jsTruthy(nameMapRaw) || util.isString(nameMapRaw) {
            if jsTruthy(nameMapRaw) {
                // case-sensitive
                // PORT-TODO: `getLocaleModel(nameMap)` (core/locale) NOT ported — the by-name locale
                //   override is deferred; keep the default `localeModel`.
                _ = localeModel
            }
            // PENDING
            // for ZH locale, original form is `一月` but current form is `1月`
            nameMap = (localeModel.get(["time", "monthAbbr"]) as? [Any]) ?? []
        }
        else {
            nameMap = (nameMapRaw as? [Any]) ?? []
        }
        _ = nameMapRaw
        // PORT-TODO: core/locale is not ported, so the default localeModel has no `time.monthAbbr`;
        //   fall back to the EN month abbreviations (echarts' en locale) so the `nameMap[m-1]` index below
        //   is in range and month labels render. Remove once core/locale lands.
        if nameMap.isEmpty { nameMap = calendarEnMonthAbbr }

        let idx = pos == "start" ? 0 : 1
        let axis = orient == .horizontal ? 0 : 1
        margin = pos == "start" ? -margin : margin
        let isCenter = (align == "center")

        let labelSilent = (monthLabel.get("silent") as? Bool) ?? false

        // upstream: for (let i = 0; i < termPoints[idx].length - 1; i++)
        var i = 0
        while i < termPoints[idx].count - 1 {

            // upstream: const tmp = termPoints[idx][i].slice();  (value-type copy)
            var tmp = termPoints[idx][i]
            let firstDay = self._firstDayOfMonth[i]

            if isCenter {
                let firstDayPoints = self._firstDayPoints[i]
                tmp[axis] = (firstDayPoints[axis] + termPoints[0][i + 1][axis]) / 2
            }

            let formatter = monthLabel.get("formatter")
            // upstream: const name = nameMap[+firstDay.m - 1];
            let name = nameMap[Int(Double(firstDay.m) ?? 1) - 1]
            let params: [String: Any] = [
                "yyyy": firstDay.y,
                // upstream: yy: (firstDay.y + '').slice(2)
                "yy": String(firstDay.y.dropFirst(2)),
                "MM": firstDay.m,
                "M": Double(firstDay.m) ?? 0,
                "nameMap": name
            ]

            let content = self._formatterLabel(formatter, params)

            // upstream: new graphic.Text({ z2: 30, style: extend(createTextStyle(monthLabel, {text: content}),
            //             this._monthTextPositionControl(tmp, isCenter, orient, pos, margin)), silent: labelSilent })
            //   `extend(base, positionControl)` overwrites `base` with the position-control fields (x/y/
            //   align/verticalAlign) — applied field-by-field here (only those four are set on the pc).
            var style = calendarCreateTextStyle(monthLabel, content)
            let pc = self._monthTextPositionControl(tmp, isCenter, orient, pos, margin)
            style.x = pc.x
            style.y = pc.y
            style.align = pc.align
            style.verticalAlign = pc.verticalAlign

            let monthText = ZRText([
                "z2": 30.0,
                "style": style,
                "silent": labelSilent
            ])

            _ = group.add(monthText)

            i += 1
        }
    }

    // upstream: _weekTextPositionControl(point, orient, position, margin, cellSize): TextStyleProps
    private func _weekTextPositionControl(
        _ point: [Double],
        _ orient: LayoutOrient,
        _ position: String,   // 'start' | 'end'
        _ margin: Double,
        _ cellSize: [Double]
    ) -> TextStyleProps {
        var align: ZRTextAlign = .center
        var vAlign: ZRTextVerticalAlign = .middle
        var x = point[0]
        var y = point[1]
        let isStart = position == "start"

        if orient == .horizontal {
            x = x + margin + (isStart ? 1 : -1) * cellSize[0] / 2
            align = isStart ? .right : .left
        }
        else {
            y = y + margin + (isStart ? 1 : -1) * cellSize[1] / 2
            vAlign = isStart ? .bottom : .top
        }

        var style = TextStyleProps()
        style.x = x
        style.y = y
        style.align = align
        style.verticalAlign = vAlign
        return style
    }

    // render weeks
    private func _renderWeekText(
        _ calendarModel: CalendarModel,
        _ localeModelIn: Model,
        _ rangeData: CalendarParsedDateRangeInfo,
        _ orient: LayoutOrient,
        _ group: Group
    ) {
        let localeModel = localeModelIn
        let dayLabel = calendarModel.getModel("dayLabel")

        if !jsTruthy(dayLabel.get("show")) {
            return
        }

        let coordSys = calendarModel.coordinateSystem as! Calendar
        let pos = (dayLabel.get("position") as? String) ?? "start"
        let nameMapRaw = dayLabel.get("nameMap")
        var margin = numOpt(dayLabel.get("margin")) ?? 0
        let firstDayOfWeek = coordSys.getFirstDayOfWeek()

        var nameMap: [Any] = []
        if !jsTruthy(nameMapRaw) || util.isString(nameMapRaw) {
            if jsTruthy(nameMapRaw) {
                // case-sensitive
                // PORT-TODO: `getLocaleModel(nameMap)` (core/locale) NOT ported — deferred; keep default.
                _ = localeModel
            }
            // Use the first letter of `dayOfWeekAbbr` if `dayOfWeekShort` doesn't exist in the locale file
            let dayOfWeekShort = localeModel.get(["time", "dayOfWeekShort"]) as? [Any]
            if let dow = dayOfWeekShort {
                nameMap = dow
            }
            else {
                var abbr = (localeModel.get(["time", "dayOfWeekAbbr"]) as? [Any]) ?? []
                // PORT-TODO: locale not ported → no `time.dayOfWeekAbbr`; fall back to the EN abbreviations
                //   so the `nameMap[day]` index (day 0..6) is in range. Remove once core/locale lands.
                if abbr.isEmpty { abbr = calendarEnDayOfWeekAbbr }
                nameMap = util.map(abbr) { val, _ -> Any in
                    // upstream: val => val[0]  (first character of the abbreviation string)
                    let s = (val as? String) ?? ""
                    return String(s.prefix(1))
                }
            }
        }
        else {
            nameMap = (nameMapRaw as? [Any]) ?? []
        }

        // upstream: let start = coordSys.getNextNDay(rangeData.end.time, (7 - rangeData.lweek)).time;
        var start = coordSys.getNextNDay(rangeData.end.time, 7 - rangeData.lweek).time

        let cellSize = [coordSys.getCellWidth(), coordSys.getCellHeight()]
        margin = number.parsePercent(margin, Swift.min(cellSize[1], cellSize[0]))

        if pos == "start" {
            start = coordSys.getNextNDay(rangeData.start.time, -(7 + rangeData.fweek)).time
            margin = -margin
        }

        let labelSilent = (dayLabel.get("silent") as? Bool) ?? false

        for i in 0..<7 {

            let tmpD = coordSys.getNextNDay(start, Double(i))
            let point = coordSys.dataToCalendarLayout([tmpD.time], false).center
            // upstream: let day = i; day = Math.abs((i + firstDayOfWeek) % 7);
            let day = Int(Swift.abs((Double(i) + firstDayOfWeek).truncatingRemainder(dividingBy: 7)))

            // upstream: extend(createTextStyle(dayLabel, {text: nameMap[day]}),
            //             this._weekTextPositionControl(point, orient, pos, margin, cellSize))
            var style = calendarCreateTextStyle(dayLabel, (nameMap[day] as? String) ?? "")
            let pc = self._weekTextPositionControl(point, orient, pos, margin, cellSize)
            style.x = pc.x
            style.y = pc.y
            style.align = pc.align
            style.verticalAlign = pc.verticalAlign

            let weekText = ZRText([
                "z2": 30.0,
                "style": style,
                "silent": labelSilent
            ])

            _ = group.add(weekText)
        }
    }

    // Apply an element-level `TextProps` bag (from `_yearTextPositionControl`) to a ZRText.
    //   PORT-TODO: NOT part of CalendarView.ts. Upstream calls `yearText.attr(props)`, but ZRText.attr
    //   routes the `"style"` key through `Displayable.attrKV`, which merges via `CommonStyleProps` and
    //   drops the text-only `align`/`verticalAlign` fields. This helper applies rotation/x/y at the
    //   element level and merges `align`/`verticalAlign` into the ZRText's `textStyle` directly, matching
    //   upstream's `.attr({rotation, x, y, style: {align, verticalAlign}})` end state.
    private func _applyTextProps(_ el: ZRText, _ props: ElementProps) {
        if let r = props["rotation"] as? Double { el.rotation = r }
        if let x = props["x"] as? Double { el.x = x }
        if let y = props["y"] as? Double { el.y = y }
        if let st = props["style"] as? TextStyleProps {
            var cur = el.textStyle ?? TextStyleProps()
            if st.align != nil { cur.align = st.align }
            if st.verticalAlign != nil { cur.verticalAlign = st.verticalAlign }
            el.useStyle(cur)
        }
    }
}

// export default CalendarView;  → `public final class CalendarView` above.


// ============================================================================
// PORT-TODO helpers — NOT part of CalendarView.ts upstream. They reproduce the
// dynamic-option-read coercions, the minimal `createTextStyle`, the style-bag →
// PathStyleProps bridge, the number[][] → [VectorArray] conversion, and the
// JS `Date.setMonth` replacement referenced above. Delete each when its real
// sibling lands (label/labelStyle, util/graphic) and call it directly.
// (Mirrors the file-private helpers in SingleAxisView / FunnelView / TitleView.)
// ============================================================================

/// Coerce a dynamic option value to Double, tolerating the Int boxing that `[String: Any]` defaultOption
/// literals use (e.g. a bare `"margin": 30`). A bare `as? Double` returns nil on an Int, silently dropping
/// the value — the recurring Int-vs-Double option-read trap (CONVENTIONS trap #1).
private func numOpt(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber, !(n === kCFBooleanTrue || n === kCFBooleanFalse) { return n.doubleValue }
    return nil
}

/// JS truthiness for the dynamic option bag (`if (x)` on `get(...)` results); mirrors the same file-private
/// helper in SingleAxisView/TitleView (CONVENTIONS §6).
private func jsTruthy(_ v: Any?) -> Bool {
    guard let v = v, !(v is NSNull) else { return false }
    if let b = v as? Bool { return b }
    if let d = v as? Double { return d != 0 && !d.isNaN }
    if let i = v as? Int { return i != 0 }
    if let s = v as? String { return !s.isEmpty }
    if let a = v as? [Any] { return !a.isEmpty }
    return true
}

/// PORT-TODO: minimal faithful reproduction of `label/labelStyle.createTextStyle(textStyleModel, {text})`.
///   Only the fields used by the calendar backdrop labels (text / font / fill) are populated; the full
///   rich-text / state / ecModel-driven behavior is in labelStyle.ts. Mirrors AxisBuilder/FunnelView/
///   Breadcrumb. Delete when label/labelStyle.swift lands and call `createTextStyle(textStyleModel, {text})`.
private func calendarCreateTextStyle(_ textStyleModel: Model, _ text: String?) -> TextStyleProps {
    var style = TextStyleProps()
    style.text = text
    style.font = textStyleModel.getFont()
    style.fill = textStyleModel.getTextColor()
    return style
}

/// PORT-TODO: `util/graphic` (and its `useStyle` dict bridge) is not ported. Map the dynamic style bag
///   ([String: Any] — the `getItemStyle()` / `getLineStyle()` result) onto the typed `PathStyleProps`.
///   Same deviation as SingleAxisView.pathStyleFromDict; numbers are read via `numOpt` (Int|Double|
///   NSNumber) to avoid the Int-drop trap. Delete when the graphic bridge lands.
private func calendarPathStyleFromDict(_ dict: [String: Any]) -> PathStyleProps {
    var s = PathStyleProps()
    // PORT-TODO: `fill`/`stroke` may be a gradient/pattern object (ZRColor non-string); only the String
    //   form (incl. the sentinel 'none') is mapped here.
    if let v = colorString(dict["fill"]) { s.fill = .string(v) }
    if let v = colorString(dict["stroke"]) { s.stroke = .string(v) }
    if let v = numOpt(dict["lineWidth"]) { s.lineWidth = v }
    if let v = dict["lineCap"] as? String { s.lineCap = v }
    if let v = dict["lineJoin"] as? String { s.lineJoin = v }
    if let v = numOpt(dict["miterLimit"]) { s.miterLimit = v }
    if let v = numOpt(dict["opacity"]) { s.opacity = v }
    if let v = numOpt(dict["fillOpacity"]) { s.fillOpacity = v }
    if let v = numOpt(dict["strokeOpacity"]) { s.strokeOpacity = v }
    if let v = numOpt(dict["shadowBlur"]) { s.shadowBlur = v }
    if let v = dict["shadowColor"] as? String { s.shadowColor = v }
    if let v = numOpt(dict["shadowOffsetX"]) { s.shadowOffsetX = v }
    if let v = numOpt(dict["shadowOffsetY"]) { s.shadowOffsetY = v }
    if let v = numOpt(dict["lineDashOffset"]) { s.lineDashOffset = v }
    // PORT-TODO: `lineDash` (number[] | false) mapping deferred (LineDash enum bridge).
    return s
}

/// Bridge a visual/style paint value (raw `String` or EChartsKit `ZRColor`) to a solid color string.
///   (gradient/pattern are out of the calendar-backdrop scope.) Mirrors BarView.barStyleFromDict.
private func colorString(_ v: Any?) -> String? {
    if let str = v as? String { return str }
    if let zr = v as? EChartsKit.ZRColor, case let .color(str) = zr { return str }
    return nil
}

/// Convert a JS `number[][]` (each inner `[x, y]`) to `[VectorArray]` for a `PolylineShape.points`.
private func pointsToVector(_ points: [[Double]]) -> [VectorArray] {
    return points.map { VectorArray($0.count > 0 ? $0[0] : 0, $0.count > 1 ? $0[1] : 0) }
}

/// PORT-TODO: replacement for the JS `date.setMonth(date.getMonth() + n)` in-place mutation.
///   Foundation.Date is a value type, so this returns a new Date `n` months later. Uses a Gregorian
///   calendar in the current timezone to match JS local `Date` semantics (cf. util/time.swift's non-UTC
///   getters, which use `TimeZone.current`). Reconcile with the `Calendar` coord's date parsing (which
///   also uses number.parseDate) at integration.
private func calendarSetMonthPlus(_ date: Foundation.Date, _ n: Int) -> Foundation.Date {
    var cal = Foundation.Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone.current
    return cal.date(byAdding: .month, value: n, to: date) ?? date
}

// PORT-TODO bridge: echarts' EN locale (core/locale/EN.ts `time.monthAbbr` / `time.dayOfWeekAbbr`).
// Used as a fallback when the (not-yet-ported) locale model supplies no month/day names, so the
// calendar month/week label index lookups stay in range. Remove once core/locale lands.
private let calendarEnMonthAbbr: [Any] = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
]
private let calendarEnDayOfWeekAbbr: [Any] = [
    "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"
]
