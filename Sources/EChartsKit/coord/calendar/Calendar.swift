// Ported from echarts/src/coord/calendar/Calendar.ts — keep in sync with upstream
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

// upstream imports:
//   import * as zrUtil from 'zrender/src/core/util';                       -> `util.*` (ZRenderKit).
//   import * as layout from '../../util/layout';                           -> `layout.*` (util/layout.swift).
//   import * as numberUtil from '../../util/number';                       -> `number.*` (util/number.swift).
//   import BoundingRect, {RectLike} from 'zrender/src/core/BoundingRect';  -> BoundingRect / RectLike (ZRenderKit).
//   import CalendarModel from './CalendarModel';                           -> CalendarModel (sibling — see note below).
//   import GlobalModel from '../../model/Global';                          -> GlobalModel.
//   import ExtensionAPI from '../../core/ExtensionAPI';                    -> ExtensionAPI (core/ExtensionAPI.swift).
//   import { LayoutOrient, ScaleDataValue, OptionDataValueDate, CoordinateSystemDataLayout }
//       from '../../util/types';                                          -> util/types.swift.
//   import { ParsedModelFinder, ParsedModelFinderKnown } from '../../util/model';
//       -> ParsedModelFinder / ParsedModelFinderKnown (`[String: Any]`, util/modelUtil.swift).
//   import { CoordinateSystem, CoordinateSystemMaster } from '../CoordinateSystem';
//       -> coord/CoordinateSystem.swift. See the CoordinateSystem-drop note on the class below.
//   import { expandOrShrinkRect } from '../../util/graphic';               -> `expandOrShrinkRect` (util/graphic.swift).
//   import { injectCoordSysByOption, simpleCoordSysInjectionProvider } from '../../core/CoordinateSystem';
//       -> injectCoordSysByOption / simpleCoordSysInjectionProvider (core/CoordinateSystemManager.swift).
//
// PORT-NOTE: the sibling `coord/calendar/CalendarModel.ts` is ported as `CalendarModel.swift`
//   (`public final class CalendarModel: ComponentModel, CoordinateSystemHostModel`) exposing:
//     - `getModel(_:)` / `get(_:)` (Model API, already on ComponentModel),
//     - `getCellSize() -> [Any]` (the `cellSize` option normalized to a 2-length `(number | 'auto')[]`),
//     - `getBoxLayoutParams() -> BoxLayoutOptionMixin` (already on ComponentModel),
//     - `var coordinateSystem: CoordinateSystemMaster?` (assigned in `create`).
//   Reconcile the exact API once CalendarModel.swift lands.

// (24*60*60*1000)
// upstream: const PROXIMATE_ONE_DAY = 86400000;
private let PROXIMATE_ONE_DAY: Double = 86400000

// upstream: export interface CalendarParsedDateRangeInfo { ... }
//   Plain data bag (no identity) -> struct (CONVENTIONS §2/§4).
public struct CalendarParsedDateRangeInfo {
    public var range: [String]                  // [string, string]
    public var start: CalendarParsedDateInfo
    public var end: CalendarParsedDateInfo
    public var allDay: Double
    public var weeks: Double
    public var nthWeek: Double
    public var fweek: Double
    public var lweek: Double
}

// upstream: export interface CalendarParsedDateInfo { ... }
public struct CalendarParsedDateInfo {
    /**
     * local full year, eg., '1940'
     */
    public var y: String
    /**
     * local month, from '01' ot '12',
     */
    public var m: String
    /**
     * local date, from '01' to '31' (if exists),
     */
    public var d: String
    /**
     * It is not date.getDay(). It is the location of the cell in a week, from 0 to 6,
     */
    public var day: Double
    /**
     * Timestamp
     */
    public var time: Double
    /**
     * yyyy-MM-dd
     */
    public var formatedDate: String
    /**
     * The original date object
     */
    public var date: JSDate
}

// upstream: interface CalendarCellRect { center; tl; tr; br; bl: number[] }
public struct CalendarCellRect {
    public var center: [Double]
    public var tl: [Double]
    public var tr: [Double]
    public var br: [Double]
    public var bl: [Double]
}

// upstream: class Calendar implements CoordinateSystem, CoordinateSystemMaster { ... }
//   Reference type → `public final class`. Conforms to `CoordinateSystemMaster` only (dropping the
//   `CoordinateSystem` conformance) for the same reason as Single/Polar/Radar: Calendar's
//   `dataToPoint(data, clamp?, out?)` / `pointToData(point)` / `dataToLayout(data, clamp?, out?)`
//   carry calendar-specific signatures that do NOT match the `CoordinateSystem` protocol requirements
//   (`dataToPoint(data, opt?)`, `pointToData(point, opt?)`, `dataToLayout(data, opt?)`). Those
//   converters are therefore plain concrete methods; `CoordinateSystemMaster` is what the coord-sys
//   registry / convert* pipeline need.
public final class Calendar: CoordinateSystemMaster, CoordinateSystem {
    // upstream `class Calendar implements CoordinateSystem, CoordinateSystemMaster`. The port had dropped
    //   the `CoordinateSystem` conformance, but the coord-injection provider casts a model's
    //   `coordinateSystem` to `CoordinateSystem` (`simpleCoordSysInjectionProvider`) — so WITHOUT it a
    //   `coordinateSystem:'calendar'` series never gets its coord injected (calendar heatmap/scatter drew
    //   nothing). Most CoordinateSystem requirements resolve to the protocol-extension nil defaults; only
    //   the generic `dataToPoint(_:_:)` witness (below) needs bridging to the concrete date method. `type`
    //   / `dimensions` are already present.

    // upstream: static readonly dimensions = ['time', 'value'];
    public static let dimensions: [DimensionName] = ["time", "value"]
    // upstream: static getDimensionsInfo() { return [{name:'time', type:'time'}, 'value']; }
    public static func getDimensionsInfo() -> [DimensionDefinitionLoose]? {
        return [
            ["name": "time", "type": "time"] as [String: Any],
            "value"
        ]
    }

    // upstream: readonly type = 'calendar';
    public let type = "calendar"

    // upstream: readonly dimensions = Calendar.dimensions;
    //   Upstream is readonly; `CoordinateSystemMaster.dimensions` requires `{ get set }`, so `var`.
    public var dimensions: [DimensionName] = Calendar.dimensions

    // CoordinateSystem.dataToPoint witness — the protocol's generic `(CoordinateSystemDataCoord, Any?)`
    //   signature does not match the concrete date-typed `dataToPoint(_:clampArg:)`, so bridge it here.
    public func dataToPoint(_ data: CoordinateSystemDataCoord, _ opt: Any?) -> [Double] {
        return self.dataToPoint(data as OptionDataValueDate?, nil as Bool?)
    }

    // Concrete implementations for the members BOTH CoordinateSystemMaster and CoordinateSystem declare
    //   with a protocol-extension default — needed to disambiguate the two defaults now that Calendar
    //   conforms to both (Calendar has no axes; it exposes its CalendarModel as `model`).
    public var model: ComponentModel? {
        get { self._model }
        set { if let m = newValue as? CalendarModel { self._model = m } }
    }
    public func getAxes() -> [Axis]? { nil }

    // upstream: private _model: CalendarModel;
    private var _model: CalendarModel!

    // upstream: private _rect: BoundingRect;  (assigned in `_update`, before any `getRect`) -> IUO.
    //   `LayoutRect` (= BoundingRect) is what `getLayoutRect` returns.
    private var _rect: LayoutRect!

    // upstream: private _sw: number;
    private var _sw: Double = 0
    // upstream: private _sh: number;
    private var _sh: Double = 0
    // upstream: private _orient: LayoutOrient;
    private var _orient: LayoutOrient = .horizontal

    // upstream: private _firstDayOfWeek: number;
    private var _firstDayOfWeek: Double = 0

    // upstream: private _rangeInfo: CalendarParsedDateRangeInfo;
    private var _rangeInfo: CalendarParsedDateRangeInfo!

    // upstream: private _lineWidth: number;
    private var _lineWidth: Double = 0

    // upstream: constructor(calendarModel, ecModel, api) {
    //     this._model = calendarModel;
    //     this._update(ecModel, api);
    // }
    public init(_ calendarModel: CalendarModel, _ ecModel: GlobalModel, _ api: ExtensionAPI) {
        self._model = calendarModel
        self._update(ecModel, api)
    }

    // Required in createListFromData
    // upstream: getDimensionsInfo = Calendar.getDimensionsInfo;  (instance field bound to the static).
    public func getDimensionsInfo() -> [DimensionDefinitionLoose]? {
        return Calendar.getDimensionsInfo()
    }

    // upstream: getRangeInfo() { return this._rangeInfo; }
    public func getRangeInfo() -> CalendarParsedDateRangeInfo {
        return self._rangeInfo
    }

    // upstream: getModel() { return this._model; }
    public func getModel() -> CalendarModel {
        return self._model
    }

    // upstream: getRect() { return this._rect; }
    //   POTENTIAL-BUG (protocol-witness gap): upstream returns the concrete `BoundingRect`; the optional
    //   protocol requirement `CoordinateSystemMaster.getRect(): RectLike?` may resolve to its nil default
    //   when Calendar is held as the protocol (mirroring Single/Grid/Parallel/Matrix.getRect — a systemic
    //   pattern). Concrete-typed holders get the real rect. Fix must be applied uniformly across the coord
    //   family, so it is deferred here rather than patched in one file.
    public func getRect() -> LayoutRect {
        return self._rect
    }

    // upstream: getCellWidth() { return this._sw; }
    public func getCellWidth() -> Double {
        return self._sw
    }

    // upstream: getCellHeight() { return this._sh; }
    public func getCellHeight() -> Double {
        return self._sh
    }

    // upstream: getOrient() { return this._orient; }
    public func getOrient() -> LayoutOrient {
        return self._orient
    }

    /**
     * getFirstDayOfWeek
     *
     * @example
     *     0 : start at Sunday
     *     1 : start at Monday
     *
     * @return {number}
     */
    // upstream: getFirstDayOfWeek() { return this._firstDayOfWeek; }
    public func getFirstDayOfWeek() -> Double {
        return self._firstDayOfWeek
    }

    /**
     * get date info
     * }
     */
    // upstream: getDateInfo(date: OptionDataValueDate): CalendarParsedDateInfo { ... }
    public func getDateInfo(_ dateArg: OptionDataValueDate?) -> CalendarParsedDateInfo {

        // date = numberUtil.parseDate(date);
        let date = JSDate(number.parseDate(dateArg))

        // const y = date.getFullYear();
        let y = date.getFullYear()

        // const m = date.getMonth() + 1;
        let m = date.getMonth() + 1
        // const mStr = m < 10 ? '0' + m : '' + m;
        let mStr = m < 10 ? "0" + String(m) : "" + String(m)

        // const d = date.getDate();
        let d = date.getDate()
        // const dStr = d < 10 ? '0' + d : '' + d;
        let dStr = d < 10 ? "0" + String(d) : "" + String(d)

        // let day = date.getDay();
        var day = Double(date.getDay())

        // day = Math.abs((day + 7 - this.getFirstDayOfWeek()) % 7);
        day = Swift.abs((day + 7 - self.getFirstDayOfWeek()).truncatingRemainder(dividingBy: 7))

        return CalendarParsedDateInfo(
            y: String(y),                                       // y + ''
            m: mStr,
            d: dStr,
            day: day,
            time: date.getTime(),
            formatedDate: String(y) + "-" + mStr + "-" + dStr,  // y + '-' + mStr + '-' + dStr
            date: date
        )
    }

    // upstream: getNextNDay(date: OptionDataValueDate, n: number) { ... }
    public func getNextNDay(_ dateArg: OptionDataValueDate?, _ nArg: Double) -> CalendarParsedDateInfo {
        // n = n || 0;
        let n = jsTruthyNum(nArg) ? nArg : 0
        // if (n === 0) { return this.getDateInfo(date); }
        if n == 0 {
            return self.getDateInfo(dateArg)
        }

        // date = new Date(this.getDateInfo(date).time);
        let date = JSDate(time: self.getDateInfo(dateArg).time)
        // date.setDate(date.getDate() + n);
        date.setDate(date.getDate() + Int(n))

        // return this.getDateInfo(date);
        return self.getDateInfo(date.date)
    }

    // upstream: private _update(ecModel: GlobalModel, api: ExtensionAPI) { ... }
    private func _update(_ ecModel: GlobalModel, _ api: ExtensionAPI) {

        // this._firstDayOfWeek = +this._model.getModel('dayLabel').get('firstDay');
        self._firstDayOfWeek = calendarPlus(self._model.getModel("dayLabel").get("firstDay"))
        // this._orient = this._model.get('orient');
        self._orient = LayoutOrient(rawValue: (self._model.get("orient") as? String) ?? "horizontal") ?? .horizontal
        // this._lineWidth = this._model.getModel('itemStyle').getItemStyle().lineWidth || 0;
        self._lineWidth = calendarLineWidthOr0(self._model.getModel("itemStyle").getItemStyle()["lineWidth"])

        // this._rangeInfo = this._getRangeInfo(this._initRangeOption());
        self._rangeInfo = self._getRangeInfo(self._initRangeOption())
        // const weeks = this._rangeInfo.weeks || 1;
        let weeks = jsTruthyNum(self._rangeInfo.weeks) ? self._rangeInfo.weeks : 1
        // const whNames = ['width', 'height'] as const;
        //   (Indexed via `setWH` / `getWH` below, since BoxLayoutOptionMixin/LayoutRect are struct/class
        //   with named — not string-keyed — members.)
        // const cellSize = this._model.getCellSize().slice();
        var cellSize = self._model.getCellSize()   // slice() -> value-copy is implicit for [Any]
        // const layoutParams = this._model.getBoxLayoutParams();
        var layoutParams = self._model.getBoxLayoutParams()
        // const cellNumbers = this._orient === 'horizontal' ? [weeks, 7] : [7, weeks];
        let cellNumbers: [Double] = self._orient == .horizontal ? [weeks, 7] : [7, weeks]

        func setWH(_ idx: Int, _ v: Double) {
            if idx == 0 { layoutParams.width = v } else { layoutParams.height = v }
        }

        // function cellSizeSpecified(cellSize, idx): cellSize is number[] {
        //     return cellSize[idx] != null && cellSize[idx] !== 'auto';
        // }
        func cellSizeSpecified(_ cellSize: [Any], _ idx: Int) -> Bool {
            let v = cellSize[idx]
            if v is NSNull { return false }
            if let s = v as? String, s == "auto" { return false }
            return true
        }

        // zrUtil.each([0, 1], function (idx) {
        //     if (cellSizeSpecified(cellSize, idx)) {
        //         layoutParams[whNames[idx]] = cellSize[idx] * cellNumbers[idx];
        //     }
        // });
        for idx in 0..<2 {
            if cellSizeSpecified(cellSize, idx) {
                setWH(idx, (calendarAsNumber(cellSize[idx]) ?? 0) * cellNumbers[idx])
            }
        }

        // const whGlobal = { width: api.getWidth(), height: api.getHeight() };
        let whGlobal = BoundingRect(0, 0, api.getWidth(), api.getHeight())
        // const calendarRect = this._rect = layout.getLayoutRect(layoutParams, whGlobal);
        let calendarRect = layout.getLayoutRect(layoutParams, whGlobal)
        self._rect = calendarRect

        // zrUtil.each([0, 1], function (idx) {
        //     if (!cellSizeSpecified(cellSize, idx)) {
        //         cellSize[idx] = calendarRect[whNames[idx]] / cellNumbers[idx];
        //     }
        // });
        for idx in 0..<2 {
            if !cellSizeSpecified(cellSize, idx) {
                cellSize[idx] = (idx == 0 ? calendarRect.width : calendarRect.height) / cellNumbers[idx]
            }
        }

        // Has been calculated out number.
        // this._sw = cellSize[0] as number;
        self._sw = calendarAsNumber(cellSize[0]) ?? 0
        // this._sh = cellSize[1] as number;
        self._sh = calendarAsNumber(cellSize[1]) ?? 0
    }

    /**
     * Convert a time data(time, value) item to (x, y) point.
     */
    // TODO Clamp of calendar is not same with cartesian coordinate systems.
    // It will return NaN if data exceeds.
    // upstream: dataToPoint(data, clamp?, out?): number[] { ... }
    //   `out?` perf out-param dropped, value-returning (CONVENTIONS §3).
    public func dataToPoint(_ dataArg: OptionDataValueDate?, _ clampArg: Bool? = nil) -> [Double] {
        // out = out || [];
        var out: [Double] = [0, 0]
        // zrUtil.isArray(data) && (data = data[0]);
        var data: OptionDataValueDate? = dataArg
        if let arr = dataArg as? [Any] {
            data = arr.isEmpty ? nil : arr[0]
        }
        // clamp == null && (clamp = true);
        let clamp = clampArg ?? true

        // const dayInfo = this.getDateInfo(data);
        let dayInfo = self.getDateInfo(data)
        // const range = this._rangeInfo;
        let range = self._rangeInfo!
        // const date = dayInfo.formatedDate;
        let date = dayInfo.formatedDate

        // if not in range return [NaN, NaN]
        // if (clamp && !(dayInfo.time >= range.start.time && dayInfo.time < range.end.time + PROXIMATE_ONE_DAY)) {
        if clamp && !(
            dayInfo.time >= range.start.time
            && dayInfo.time < range.end.time + PROXIMATE_ONE_DAY
        ) {
            // out[0] = out[1] = NaN;
            out[0] = Double.nan
            out[1] = Double.nan
            return out
        }

        // const week = dayInfo.day;
        let week = dayInfo.day
        // const nthWeek = this._getRangeInfo([range.start.time, date]).nthWeek;
        let nthWeek = self._getRangeInfo([range.start.time, date]).nthWeek

        if self._orient == .vertical {
            // out[0] = this._rect.x + week * this._sw + this._sw / 2;
            out[0] = self._rect.x + week * self._sw + self._sw / 2
            // out[1] = this._rect.y + nthWeek * this._sh + this._sh / 2;
            out[1] = self._rect.y + nthWeek * self._sh + self._sh / 2
        }
        else {
            // out[0] = this._rect.x + nthWeek * this._sw + this._sw / 2;
            out[0] = self._rect.x + nthWeek * self._sw + self._sw / 2
            // out[1] = this._rect.y + week * this._sh + this._sh / 2;
            out[1] = self._rect.y + week * self._sh + self._sh / 2
        }
        return out
    }

    /**
     * Convert a (x, y) point to time data
     */
    // upstream: pointToData(point: number[]): number { ... }
    //   PORT-NOTE: upstream `return date && date.time` yields `null` when `date` is null (falsy). The
    //   declared return type is `number`; the Swift port returns `Double.nan` in the null case as the
    //   nearest non-Optional sentinel (JS/Swift language difference, semantically equivalent).
    public func pointToData(_ point: [Double]) -> Double {
        // const date = this.pointToDate(point);
        let date = self.pointToDate(point)
        // return date && date.time;
        return date != nil ? date!.time : Double.nan
    }

    // upstream: dataToLayout(data, clamp?, out?): CoordinateSystemDataLayout { ... }
    //   `out?` perf out-param dropped, value-returning (CONVENTIONS §3).
    public func dataToLayout(_ data: OptionDataValueDate?, _ clamp: Bool? = nil) -> CoordinateSystemDataLayout {
        // out = out || {} as CoordinateSystemDataLayout;
        var out = CoordinateSystemDataLayout()
        // const rect = out.rect = out.rect || {} as RectLike;
        let rect: RectLike = BoundingRect(0, 0, 0, 0)
        out.rect = rect
        // const contentRect = out.contentRect = out.contentRect || {} as RectLike;
        let contentRect: RectLike = BoundingRect(0, 0, 0, 0)
        out.contentRect = contentRect
        // const point = this.dataToPoint(data, clamp);
        let point = self.dataToPoint(data, clamp)

        // rect.x = point[0] - (this._sw) / 2;
        rect.x = point[0] - self._sw / 2
        // rect.y = point[1] - (this._sh) / 2;
        rect.y = point[1] - self._sh / 2
        // rect.width = this._sw;
        rect.width = self._sw
        // rect.height = this._sh;
        rect.height = self._sh

        // BoundingRect.copy(contentRect, rect);
        _ = BoundingRect.copy(contentRect, rect)
        // expandOrShrinkRect(contentRect, this._lineWidth / 2, true, true);
        //   Shrinks `contentRect` inward by lineWidth/2 (now landed in util/graphic.swift).
        expandOrShrinkRect(contentRect, self._lineWidth / 2, true, true)

        return out
    }

    /**
     * Convert a time date item to (x, y) four point.
     */
    // upstream: dataToCalendarLayout(data, clamp?): CalendarCellRect { ... }
    public func dataToCalendarLayout(_ data: OptionDataValueDate?, _ clamp: Bool? = nil) -> CalendarCellRect {
        // const point = this.dataToPoint(data, clamp);
        let point = self.dataToPoint(data, clamp)
        return CalendarCellRect(
            center: point,
            tl: [
                point[0] - self._sw / 2,
                point[1] - self._sh / 2
            ],
            tr: [
                point[0] + self._sw / 2,
                point[1] - self._sh / 2
            ],
            br: [
                point[0] + self._sw / 2,
                point[1] + self._sh / 2
            ],
            bl: [
                point[0] - self._sw / 2,
                point[1] + self._sh / 2
            ]
        )
    }

    /**
     * Convert a (x, y) point to time date
     *
     * @param  {Array} point point
     * @return {Object}       date
     */
    // upstream: pointToDate(point: number[]): CalendarParsedDateInfo { ... }
    public func pointToDate(_ point: [Double]) -> CalendarParsedDateInfo? {
        // const nthX = Math.floor((point[0] - this._rect.x) / this._sw) + 1;
        let nthX = floor((point[0] - self._rect.x) / self._sw) + 1
        // const nthY = Math.floor((point[1] - this._rect.y) / this._sh) + 1;
        let nthY = floor((point[1] - self._rect.y) / self._sh) + 1
        // const range = this._rangeInfo.range;
        let range = self._rangeInfo.range

        if self._orient == .vertical {
            // return this._getDateByWeeksAndDay(nthY, nthX - 1, range);
            return self._getDateByWeeksAndDay(nthY, nthX - 1, range)
        }

        // return this._getDateByWeeksAndDay(nthX, nthY - 1, range);
        return self._getDateByWeeksAndDay(nthX, nthY - 1, range)
    }

    // upstream: convertToPixel(ecModel, finder, value) {
    //     const coordSys = getCoordSys(finder);
    //     return coordSys === this ? coordSys.dataToPoint(value) : null;
    // }
    public func convertToPixel(
        _ ecModel: GlobalModel,
        _ finder: ParsedModelFinder,
        _ value: CoordinateSystemDataCoord,
        _ opt: Any?
    ) -> Any? {
        let coordSys = getCoordSys(finder)
        return coordSys === self ? coordSys!.dataToPoint(value) : nil
    }

    // upstream: convertToLayout(ecModel, finder, value) {
    //     const coordSys = getCoordSys(finder);
    //     return coordSys === this ? coordSys.dataToLayout(value) : null;
    // }
    public func convertToLayout(
        _ ecModel: GlobalModel,
        _ finder: ParsedModelFinder,
        _ value: CoordinateSystemDataCoord,
        _ opt: Any?
    ) -> CoordinateSystemDataLayout? {
        let coordSys = getCoordSys(finder)
        return coordSys === self ? coordSys!.dataToLayout(value) : nil
    }

    // upstream: convertFromPixel(ecModel, finder, pixel) {
    //     const coordSys = getCoordSys(finder);
    //     return coordSys === this ? coordSys.pointToData(pixel) : null;
    // }
    public func convertFromPixel(
        _ ecModel: GlobalModel,
        _ finder: ParsedModelFinder,
        _ pixelValue: [Double],
        _ opt: Any?
    ) -> Any? {
        let coordSys = getCoordSys(finder)
        return coordSys === self ? coordSys!.pointToData(pixelValue) : nil
    }

    // upstream: containPoint(point: number[]): boolean {
    //     console.warn('Not implemented.');
    //     return false;
    // }
    public func containPoint(_ point: [Double]) -> Bool {
        // upstream: console.warn('Not implemented.') -> `log.warn` (util/log.swift).
        log.warn("Not implemented.")
        return false
    }

    /**
     * initRange
     * Normalize to an [start, end] array
     */
    // upstream: private _initRangeOption(): OptionDataValueDate[] { ... }
    private func _initRangeOption() -> [OptionDataValueDate] {
        // let range = this._model.get('range');
        var range: Any? = self._model.get("range")
        var normalizedRange: [OptionDataValueDate]? = nil

        // Convert [1990] to 1990
        // if (zrUtil.isArray(range) && range.length === 1) { range = range[0]; }
        if let arr = range as? [Any], arr.count == 1 {
            range = arr[0]
        }

        // if (!zrUtil.isArray(range)) { ... } else { normalizedRange = range; }
        if !(range is [Any]) {
            // const rangeStr = range.toString();
            let rangeStr = calendarToString(range)
            // One year.
            // if (/^\d{4}$/.test(rangeStr)) { normalizedRange = [rangeStr + '-01-01', rangeStr + '-12-31']; }
            if calendarRegexTest("^\\d{4}$", rangeStr) {
                normalizedRange = [rangeStr + "-01-01", rangeStr + "-12-31"]
            }
            // One month
            // if (/^\d{4}[\/|-]\d{1,2}$/.test(rangeStr)) { ... }
            if calendarRegexTest("^\\d{4}[\\/|-]\\d{1,2}$", rangeStr) {
                // const start = this.getDateInfo(rangeStr);
                let start = self.getDateInfo(rangeStr)
                // const firstDay = start.date;
                let firstDay = start.date
                // firstDay.setMonth(firstDay.getMonth() + 1);
                firstDay.setMonth(firstDay.getMonth() + 1)

                // const end = this.getNextNDay(firstDay, -1);
                let end = self.getNextNDay(firstDay.date, -1)
                normalizedRange = [start.formatedDate, end.formatedDate]
            }
            // One day
            // if (/^\d{4}[\/|-]\d{1,2}[\/|-]\d{1,2}$/.test(rangeStr)) { normalizedRange = [rangeStr, rangeStr]; }
            if calendarRegexTest("^\\d{4}[\\/|-]\\d{1,2}[\\/|-]\\d{1,2}$", rangeStr) {
                normalizedRange = [rangeStr, rangeStr]
            }
        }
        else {
            // normalizedRange = range;
            normalizedRange = (range as? [OptionDataValueDate]) ?? []
        }

        // if (!normalizedRange) { ...logError...; return range as OptionDataValueDate[]; }
        guard var normalizedRangeUnwrapped = normalizedRange else {
            if __DEV__ {
                util.logError("Invalid date range.")
            }
            // Not handling it.
            return (range as? [OptionDataValueDate]) ?? []
        }

        // const tmp = this._getRangeInfo(normalizedRange);
        let tmp = self._getRangeInfo(normalizedRangeUnwrapped)

        // if (tmp.start.time > tmp.end.time) { normalizedRange.reverse(); }
        if tmp.start.time > tmp.end.time {
            normalizedRangeUnwrapped.reverse()
        }

        return normalizedRangeUnwrapped
    }

    /**
     * range info
     *
     * @private
     * @param  {Array} range range ['2017-01-01', '2017-07-08']
     *  If range[0] > range[1], they will not be reversed.
     * @return {Object}       obj
     */
    // upstream: _getRangeInfo(range: OptionDataValueDate[]): CalendarParsedDateRangeInfo { ... }
    public func _getRangeInfo(_ range: [OptionDataValueDate]) -> CalendarParsedDateRangeInfo {
        // const parsedRange = [ this.getDateInfo(range[0]), this.getDateInfo(range[1]) ];
        var parsedRange: [CalendarParsedDateInfo] = [
            self.getDateInfo(range[0]),
            self.getDateInfo(range[1])
        ]

        // let reversed;
        var reversed = false
        // if (parsedRange[0].time > parsedRange[1].time) { reversed = true; parsedRange.reverse(); }
        if parsedRange[0].time > parsedRange[1].time {
            reversed = true
            parsedRange.reverse()
        }

        // let allDay = Math.floor(parsedRange[1].time / PROXIMATE_ONE_DAY)
        //     - Math.floor(parsedRange[0].time / PROXIMATE_ONE_DAY) + 1;
        var allDay = floor(parsedRange[1].time / PROXIMATE_ONE_DAY)
            - floor(parsedRange[0].time / PROXIMATE_ONE_DAY) + 1

        // Consider case1 (#11677 #10430):
        // Set the system timezone as "UK", set the range to `['2016-07-01', '2016-12-31']`

        // Consider case2:
        // Firstly set system timezone as "Time Zone: America/Toronto",
        // ```
        // let first = new Date(1478412000000 - 3600 * 1000 * 2.5);
        // let second = new Date(1478412000000);
        // let allDays = Math.floor(second / ONE_DAY) - Math.floor(first / ONE_DAY) + 1;
        // ```
        // will get wrong result because of DST. So we should fix it.
        // const date = new Date(parsedRange[0].time);
        let date = JSDate(time: parsedRange[0].time)
        // const startDateNum = date.getDate();
        let startDateNum = date.getDate()
        // const endDateNum = parsedRange[1].date.getDate();
        let endDateNum = parsedRange[1].date.getDate()
        // date.setDate(startDateNum + allDay - 1);
        date.setDate(startDateNum + Int(allDay) - 1)
        // The bias can not over a month, so just compare date.
        // let dateNum = date.getDate();
        var dateNum = date.getDate()
        // if (dateNum !== endDateNum) { ... }
        if dateNum != endDateNum {
            // const sign = date.getTime() - parsedRange[1].time > 0 ? 1 : -1;
            let sign = date.getTime() - parsedRange[1].time > 0 ? 1 : -1
            // while ((dateNum = date.getDate()) !== endDateNum
            //     && (date.getTime() - parsedRange[1].time) * sign > 0) {
            //     allDay -= sign;
            //     date.setDate(dateNum - sign);
            // }
            while true {
                dateNum = date.getDate()
                if !(dateNum != endDateNum
                    && (date.getTime() - parsedRange[1].time) * Double(sign) > 0) {
                    break
                }
                allDay -= Double(sign)
                date.setDate(dateNum - sign)
            }
        }

        // const weeks = Math.floor((allDay + parsedRange[0].day + 6) / 7);
        let weeks = floor((allDay + parsedRange[0].day + 6) / 7)
        // const nthWeek = reversed ? -weeks + 1 : weeks - 1;
        let nthWeek = reversed ? -weeks + 1 : weeks - 1

        // reversed && parsedRange.reverse();
        if reversed {
            parsedRange.reverse()
        }

        return CalendarParsedDateRangeInfo(
            range: [parsedRange[0].formatedDate, parsedRange[1].formatedDate],
            start: parsedRange[0],
            end: parsedRange[1],
            allDay: allDay,
            weeks: weeks,
            // From 0.
            nthWeek: nthWeek,
            fweek: parsedRange[0].day,
            lweek: parsedRange[1].day
        )
    }

    /**
     * get date by nthWeeks and week day in range
     *
     * @private
     * @param  {number} nthWeek the week
     * @param  {number} day   the week day
     * @param  {Array} range [d1, d2]
     * @return {Object}
     */
    // upstream: private _getDateByWeeksAndDay(nthWeek, day, range): CalendarParsedDateInfo { ... }
    private func _getDateByWeeksAndDay(_ nthWeek: Double, _ day: Double, _ range: [OptionDataValueDate]) -> CalendarParsedDateInfo? {
        // const rangeInfo = this._getRangeInfo(range);
        let rangeInfo = self._getRangeInfo(range)

        // if (nthWeek > rangeInfo.weeks
        //     || (nthWeek === 0 && day < rangeInfo.fweek)
        //     || (nthWeek === rangeInfo.weeks && day > rangeInfo.lweek)) {
        //     return null;
        // }
        if nthWeek > rangeInfo.weeks
            || (nthWeek == 0 && day < rangeInfo.fweek)
            || (nthWeek == rangeInfo.weeks && day > rangeInfo.lweek) {
            return nil
        }

        // const nthDay = (nthWeek - 1) * 7 - rangeInfo.fweek + day;
        let nthDay = (nthWeek - 1) * 7 - rangeInfo.fweek + day
        // const date = new Date(rangeInfo.start.time);
        let date = JSDate(time: rangeInfo.start.time)
        // date.setDate(+rangeInfo.start.d + nthDay);
        date.setDate(Int(calendarPlus(rangeInfo.start.d) + nthDay))

        // return this.getDateInfo(date);
        return self.getDateInfo(date.date)
    }

    // upstream: static create(ecModel: GlobalModel, api: ExtensionAPI) { ... }
    public static func create(_ ecModel: GlobalModel, _ api: ExtensionAPI) -> [Calendar] {
        // const calendarList: Calendar[] = [];
        var calendarList: [Calendar] = []

        // ecModel.eachComponent('calendar', function (calendarModel: CalendarModel) { ... });
        ecModel.eachComponent("calendar") { (calendarModelComp: ComponentModel, _: Double) in
            guard let calendarModel = calendarModelComp as? CalendarModel else { return }
            // const calendar = new Calendar(calendarModel, ecModel, api);
            let calendar = Calendar(calendarModel, ecModel, api)
            // calendarList.push(calendar);
            calendarList.append(calendar)
            // calendarModel.coordinateSystem = calendar;
            calendarModel.coordinateSystem = calendar
        }

        // Inject coordinate system
        // ecModel.eachComponent((mainType, componentModel) => {
        //     injectCoordSysByOption({ targetModel: componentModel, coordSysType: 'calendar',
        //         coordSysProvider: simpleCoordSysInjectionProvider });
        // });
        ecModel.eachComponent { (_: String, componentModel: ComponentModel, _: Double) in
            _ = injectCoordSysByOption(InjectCoordSysByOptionOpt(
                targetModel: componentModel,
                coordSysType: "calendar",
                coordSysProvider: simpleCoordSysInjectionProvider
            ))
        }
        // return calendarList;
        return calendarList
    }
}

// upstream: function getCoordSys(finder: ParsedModelFinderKnown): Calendar {
//     const calendarModel = finder.calendarModel as CalendarModel;
//     const seriesModel = finder.seriesModel;
//     const coordSys = calendarModel ? calendarModel.coordinateSystem
//         : seriesModel ? seriesModel.coordinateSystem : null;
//     return coordSys as Calendar;
// }
//   `finder` is `[String: Any]` → field access via subscript.
private func getCoordSys(_ finder: ParsedModelFinderKnown) -> Calendar? {
    let calendarModel = finder["calendarModel"] as? CalendarModel
    let seriesModel = finder["seriesModel"] as? SeriesModel

    // `calendarModel.coordinateSystem` is `CoordinateSystemMaster?` (CoordinateSystemHostModel) and
    // `seriesModel.coordinateSystem` is `Any?` (Series.swift); box both as `Any?` and narrow at the end.
    let coordSys: Any?
    if let calendarModel = calendarModel {
        coordSys = calendarModel.coordinateSystem
    }
    else if let seriesModel = seriesModel {
        coordSys = seriesModel.coordinateSystem
    }
    else {
        coordSys = nil
    }

    return coordSys as? Calendar
}

// export default Calendar;  -> `public final class Calendar` above.

// MARK: - Port support

// A small mutable wrapper mirroring the subset of the JS `Date` API used by Calendar
// (getFullYear / getMonth / getDate / getDay / getTime / setDate / setMonth). All getters read in the
// LOCAL time zone, matching JS `Date`'s local getters and the `numberUtil.parseDate` gregorian+current-tz
// construction. `date` is stored so upstream `parsedRange[1].date` / `start.date` aliasing (and the
// in-place `setMonth`/`setDate` mutation of a stored date object) is reproduced faithfully.
public final class JSDate {
    public var date: Date

    // upstream: numberUtil.parseDate(...) result / a Date object.
    public init(_ d: Date) { self.date = d }
    // upstream: new Date(timeMs) — a timestamp in ms.
    public init(time: Double) { self.date = Date(timeIntervalSince1970: time / 1000) }

    private static let cal: Foundation.Calendar = {
        var c = Foundation.Calendar(identifier: .gregorian)
        c.timeZone = TimeZone.current
        return c
    }()

    // getFullYear()
    public func getFullYear() -> Int { JSDate.cal.component(.year, from: date) }
    // getMonth() — JS months are 0-based; Foundation .month is 1-based.
    public func getMonth() -> Int { JSDate.cal.component(.month, from: date) - 1 }
    // getDate() — day of month.
    public func getDate() -> Int { JSDate.cal.component(.day, from: date) }
    // getDay() — JS: 0=Sunday..6=Saturday; Foundation .weekday: 1=Sunday..7=Saturday.
    public func getDay() -> Int { JSDate.cal.component(.weekday, from: date) - 1 }
    // getTime() — ms since epoch (UTC).
    public func getTime() -> Double { date.timeIntervalSince1970 * 1000 }

    // setDate(v) — set the day-of-month, keeping year/month/time-of-day. Overflowing values roll over
    //   into adjacent months (e.g. setDate(32) => next month), matching JS; Foundation `date(from:)`
    //   normalizes out-of-range components identically.
    public func setDate(_ v: Int) {
        var c = JSDate.cal.dateComponents(
            [.year, .month, .day, .hour, .minute, .second, .nanosecond], from: date
        )
        c.day = v
        if let d = JSDate.cal.date(from: c) { date = d }
    }

    // setMonth(v) — JS month is 0-based; Foundation .month is 1-based (so store v + 1).
    public func setMonth(_ v: Int) {
        var c = JSDate.cal.dateComponents(
            [.year, .month, .day, .hour, .minute, .second, .nanosecond], from: date
        )
        c.month = v + 1
        if let d = JSDate.cal.date(from: c) { date = d }
    }
}

// JS unary `+x`: coerce a dynamic value to Double (number stays, numeric string parses, else NaN).
// Kept explicit (not a bare `as? Double`) to tolerate the Int / NSNumber boxing used by `[String: Any]`
// option bags — the recurring Int-vs-Double numeric-read trap.
private func calendarPlus(_ v: Any?) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber, !(n === kCFBooleanTrue || n === kCFBooleanFalse) { return n.doubleValue }
    if let s = v as? String { return Double(s) ?? Double.nan }
    return Double.nan
}

// Coerce a dynamic option value to Double when present (nil if absent / non-numeric). Tolerates the Int
// boxing that default-option literals use, per the Int-vs-Double option-read trap.
private func calendarAsNumber(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber, !(n === kCFBooleanTrue || n === kCFBooleanFalse) { return n.doubleValue }
    return nil
}

// upstream: `this._model.getModel('itemStyle').getItemStyle().lineWidth || 0`. JS `x || 0` returns 0 for
// any falsy `x` (undefined / 0 / NaN); replicate with the truthiness check.
private func calendarLineWidthOr0(_ v: Any?) -> Double {
    guard let n = calendarAsNumber(v) else { return 0 }
    return jsTruthyNum(n) ? n : 0
}

// JS numeric truthiness: 0 and NaN are falsy, everything else truthy (used for `weeks || 1`, `n || 0`).
private func jsTruthyNum(_ x: Double) -> Bool {
    return x != 0 && !x.isNaN
}

// JS `String(x)` / `x.toString()` for the `range` option (number | string).
private func calendarToString(_ v: Any?) -> String {
    if let s = v as? String { return s }
    if let d = v as? Double { return number.jsNumberString(d) }
    if let i = v as? Int { return String(i) }
    if let n = v as? NSNumber { return number.jsNumberString(n.doubleValue) }
    return v.map { "\($0)" } ?? ""
}

// JS `/regex/.test(str)` — an anchored search using the JS-style pattern (already `^...$`).
private func calendarRegexTest(_ pattern: String, _ s: String) -> Bool {
    guard let re = try? NSRegularExpression(pattern: pattern) else { return false }
    let ns = s as NSString
    return re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) != nil
}
