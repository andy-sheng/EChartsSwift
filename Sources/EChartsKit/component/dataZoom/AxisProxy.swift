// Ported from echarts/src/component/dataZoom/AxisProxy.ts — keep in sync with upstream
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
//   import { clone, defaults, each, map } from 'zrender/src/core/util';   -> `util.*` (ZRenderKit)
//   import { asc, getAcceptableTickPrecision, linearMap, mathAbs, mathCeil, mathFloor, mathMax, mathMin, round }
//       from '../../util/number';                                         -> `number.*` (util/number.swift)
//   import sliderMove from '../helper/sliderMove';                        -> `sliderMove` (component/helper/sliderMove.swift)
//   import GlobalModel from '../../model/Global';                         -> `GlobalModel`
//   import SeriesModel from '../../model/Series';                         -> `SeriesModel`
//   import ExtensionAPI from '../../core/ExtensionAPI';                   -> `ExtensionAPI`
//   import { Dictionary, NullUndefined } from '../../util/types';         -> `[String: T]` / Optional
//   import DataZoomModel from './DataZoomModel';                          -> `DataZoomModel` (TASK 1 sibling; integrator reconciles)
//   import { AxisBaseModel } from '../../coord/AxisBaseModel';            -> `AxisBaseModel`
//   import { getAxisMainType, isCoordSupported, DataZoomAxisDimension } from './helper';  -> dataZoomHelper.swift
//   import { ensureExtentAscSimply, SINGLE_REFERRING } from '../../util/model';           -> `model.*`
//   import { isOrdinalScale, isTimeScale } from '../../scale/helper';                     -> `helper.*` (scale/helper.swift)
//   import { AXIS_EXTENT_INFO_BUILD_FROM_DATA_ZOOM, scaleRawExtentInfoCreate, ScaleRawExtentResultForZoom }
//       from '../../coord/scaleRawExtentInfo';                            -> coord/scaleRawExtentInfo.swift

// ============================================================================
// TASK 1 (DataZoomModel) SURFACE consumed here (integrator reconciles the exact shape):
//   - dataZoomModel.getRangePropMode() -> [String]      // 2-element ['percent'|'value', 'percent'|'value']
//   - dataZoomModel.settledOption : DataZoomWindowInput // the settled range (start/end/startValue/endValue)
//   - dataZoomModel.get("filterMode" | "minSpan" | "maxSpan" | "minValueSpan" | "maxValueSpan")  // ComponentModel.get
//   - dataZoomModel.eachTargetAxis((axisDim: DataZoomAxisDimension, axisIndex: Int) -> Void)
//   - dataZoomModel.getAxisProxy(axisDim, axisIndex) -> AxisProxy?
//   (inherited from ComponentModel: `.uid`, `.ecModel`)
// ============================================================================


// upstream: interface MinMaxSpan { minSpan; maxSpan; minValueSpan; maxValueSpan }  (all `number`, may be undefined)
struct MinMaxSpan {
    var minSpan: Double?
    var maxSpan: Double?
    var minValueSpan: Double?
    var maxValueSpan: Double?
    init(
        minSpan: Double? = nil,
        maxSpan: Double? = nil,
        minValueSpan: Double? = nil,
        maxValueSpan: Double? = nil
    ) {
        self.minSpan = minSpan
        self.maxSpan = maxSpan
        self.minValueSpan = minValueSpan
        self.maxValueSpan = maxValueSpan
    }
}

// upstream: the `opt` bag passed to `calculateDataWindow`. Also the shape of `DataZoomModel.settledOption`
//   window fields. `start`/`end` are percents (0~100); `startValue`/`endValue` are raw values
//   (number | string | Date). Modeled with `Any?` so the Int-vs-Double option-read trap is handled
//   inside `calculateDataWindow` (Int literals coerced to Double) and `startValue`/`endValue` flow
//   straight into `scale.parse`.
public struct DataZoomWindowInput {
    public var start: Any?       // percent, 0 ~ 100
    public var end: Any?         // percent, 0 ~ 100
    public var startValue: Any?  // number | string | Date
    public var endValue: Any?    // number | string | Date
    public init(start: Any? = nil, end: Any? = nil, startValue: Any? = nil, endValue: Any? = nil) {
        self.start = start
        self.end = end
        self.startValue = startValue
        self.endValue = endValue
    }
}

// upstream: export interface AxisProxyWindow
public struct AxisProxyWindow {
    // NOTE: May include non-effective portion.
    public var value: ScaleRawExtentResultForZoom   // [Double]
    public var percent: [Double]
    // Percent invert from "value window", which may be slightly different from "percent window" due to some
    // handling such as rounding. (See upstream comment.)
    public var percentInverted: [Double]
    public var valuePrecision: Double
    public init(value: [Double], percent: [Double], percentInverted: [Double], valuePrecision: Double) {
        self.value = value
        self.percent = percent
        self.percentInverted = percentInverted
        self.valuePrecision = valuePrecision
    }
}

/**
 * Operate single axis.
 * One axis can only operated by one axis operator.
 * Different dataZoomModels may be defined to operate the same axis.
 * (i.e. 'inside' data zoom and 'slider' data zoom components)
 * So dataZoomModels share one axisProxy in that case.
 */
// upstream: class AxisProxy — identity/shared instance stored in the per-ec-prepare cache → `final class`.
public final class AxisProxy {

    public var ecModel: GlobalModel

    // NOTICE: The lifetime of `AxisProxy` instance is different from `Axis` instance.
    // It is recreated in each run of "ec prepare".

    private var _dimName: DataZoomAxisDimension
    private var _axisIndex: Int

    private var _window: AxisProxyWindow!

    private var _extent: ScaleRawExtentResultForZoom!

    private var _minMaxSpan: MinMaxSpan!

    /**
     * The host `dataZoom` model. An axis may be controlled by multiple `dataZoom`s,
     * but only the first declared `dataZoom` is the host.
     */
    private var _dataZoomModel: DataZoomModel

    public init(
        _ dimName: DataZoomAxisDimension,
        _ axisIndex: Int,
        _ dataZoomModel: DataZoomModel,
        _ ecModel: GlobalModel
    ) {
        self._dimName = dimName
        self._axisIndex = axisIndex
        self.ecModel = ecModel
        self._dataZoomModel = dataZoomModel
    }

    /**
     * Whether the axisProxy is hosted by dataZoomModel.
     */
    public func hostedBy(_ dataZoomModel: DataZoomModel) -> Bool {
        return self._dataZoomModel === dataZoomModel
    }

    /**
     * @return `getWindow().value` can only have NaN or finite value.
     */
    public func getWindow() -> AxisProxyWindow {
        return self._window   // clone(this._window): value struct + array fields deep-copy on return
    }

    public func getTargetSeriesModels() -> [SeriesModel] {
        var seriesModels: [SeriesModel] = []

        self.ecModel.eachSeries { seriesModel, _ in
            if isCoordSupported(seriesModel) {
                let axisMainType = getAxisMainType(self._dimName)
                let axisModel = seriesModel.getReferringComponents(
                    axisMainType, EChartsKit.model.SINGLE_REFERRING
                ).models.first
                if let axisModel = axisModel, Double(self._axisIndex) == axisModel.componentIndex {
                    seriesModels.append(seriesModel)
                }
            }
        }

        return seriesModels
    }

    public func getAxisModel() -> AxisBaseModel {
        return self.ecModel.getComponent(self._dimName + "Axis", Double(self._axisIndex)) as! AxisBaseModel
    }

    func getMinMaxSpan() -> MinMaxSpan {
        return self._minMaxSpan   // clone
    }

    /**
     * [CAVEAT] Keep this method pure, so that it can be called multiple times.
     */
    public func calculateDataWindow(_ opt: DataZoomWindowInput) -> AxisProxyWindow {
        let dataExtent = self._extent!
        let axis = self.getAxisModel().axis as! Axis
        let scale = axis.scale
        let dataZoomModel = self._dataZoomModel
        let rangePropMode = dataZoomModel.getRangePropMode()
        let percentExtent: [Double] = [0, 100]
        var percentWindow: [Double] = [Double.nan, Double.nan]
        var valueWindow: [Double] = [Double.nan, Double.nan]
        var hasPropModeValue = false
        var needRound: [Bool] = [false, false]

        // NOTE: (See upstream comment block on the percentage base calculation strategy.)

        for idx in 0..<2 {
            var boundPercent: Double? = dzCoerceNumber(idx == 0 ? opt.start : opt.end)
            let rawBoundValue: Any? = (idx == 0 ? opt.startValue : opt.endValue)
            var boundValueNum: Double?

            // NOTE: dataZoom is based either on `percentProp` ('start', 'end') or
            // on `valueProp` ('startValue', 'endValue'). (See upstream comment.)

            if rangePropMode[idx] == "percent" {
                if boundPercent == nil {
                    boundPercent = percentExtent[idx]
                }
                boundValueNum = number.linearMap(boundPercent!, percentExtent, dataExtent)
                needRound[idx] = true
            }
            else {
                hasPropModeValue = true
                // NOTE: `scale.parse` can also round input for 'time' or 'ordinal' scale.
                if rawBoundValue == nil || rawBoundValue is NSNull {
                    boundValueNum = dataExtent[idx]
                }
                else {
                    // Need to parse user inputs from ec option or action param.
                    var parsed = scale.parse(rawBoundValue!)
                    if let sanitize = scale.sanitize {
                        // upstream: boundValue = scale.sanitize(boundValue, dataExtent)
                        if let s = sanitize(parsed, dataExtent) { parsed = s }
                    }
                    boundValueNum = parsed
                }
                // Calculating `percent` from `value` may be not accurate. (See upstream comment.)
                boundPercent = number.linearMap(boundValueNum!, dataExtent, percentExtent)
            }

            // fallback to extent start/end when parsed value or percent is invalid
            valueWindow[idx] = (boundValueNum == nil || boundValueNum!.isNaN)
                ? dataExtent[idx]
                : boundValueNum!
            percentWindow[idx] = (boundPercent == nil || boundPercent!.isNaN)
                ? percentExtent[idx]
                : boundPercent!
        }

        // Historical behavior - enable switching.
        valueWindow = number.asc(valueWindow)
        percentWindow = number.asc(percentWindow)

        // The windows specified from `dispatchAction` or `setOption` may be out of the extent, or
        // do not comply with `minSpan/maxSpan`, `minValueSpan/maxValueSpan`. So we clamp them here.
        // (See upstream comment on `zoomLock` and the historical option incompatibility.)
        let spans = self._minMaxSpan!
        if hasPropModeValue {
            dzRestrictSet(
                &valueWindow, &percentWindow, dataExtent, percentExtent, false, spans, &needRound
            )
        }
        else {
            dzRestrictSet(
                &percentWindow, &valueWindow, percentExtent, dataExtent, true, spans, &needRound
            )
        }

        // (See upstream comment on rounding rules by scale type.)
        let isScaleOrdinalOrTime = helper.isOrdinalScale(scale) || helper.isTimeScale(scale)
        // Typically pxExtent has been ready in coordSys create. (See `create` of `Grid.ts`)
        let pxExtent = axis.getExtent()
        // NOTICE: this pxSpan may be not accurate yet due to "outerBounds" logic, but acceptable.
        let pxSpan = number.mathAbs(pxExtent[1] - pxExtent[0])
        let precision: Double = isScaleOrdinalOrTime
            ? 0
            // (See upstream comment on why user-specified precision is deliberately disallowed.)
            : number.getAcceptableTickPrecision(valueWindow, pxSpan, 0.5)

        // each([[0, mathCeil], [1, mathFloor]])
        let ceilOrFloorPairs: [(Int, (Double) -> Double)] = [(0, number.mathCeil), (1, number.mathFloor)]
        for (idx, ceilOrFloor) in ceilOrFloorPairs {
            if !needRound[idx] || !precision.isFinite {
                continue
            }
            valueWindow[idx] = number.round(valueWindow[idx], precision)
            valueWindow[idx] = number.mathMin(dataExtent[1], number.mathMax(dataExtent[0], valueWindow[idx])) // Clamp.
            if percentWindow[idx] == percentExtent[idx] {
                // When `percent` is 0 or 100, `value` must be `dataExtent[0]` or `dataExtent[1]`
                // regardless of the calculated precision.
                valueWindow[idx] = dataExtent[idx]
                if isScaleOrdinalOrTime {
                    // In case that dataExtent[idx] is not an integer (may occur since it comes from user input)
                    valueWindow[idx] = ceilOrFloor(valueWindow[idx])
                }
            }
        }
        dzEnsureExtentAscSimply(&valueWindow)

        var percentInvertedWindow: [Double] = [
            number.linearMap(valueWindow[0], dataExtent, percentExtent, true),
            number.linearMap(valueWindow[1], dataExtent, percentExtent, true),
        ]
        dzEnsureExtentAscSimply(&percentInvertedWindow)

        return AxisProxyWindow(
            value: valueWindow,
            percent: percentWindow,
            percentInverted: percentInvertedWindow,
            valuePrecision: precision
        )
    }

    /**
     * Notice: reset should not be called before series.restoreData() is called,
     * so it is recommended to be called in "process stage" but not "model init stage".
     */
    public func reset(_ dataZoomModel: DataZoomModel, _ alignToPercentInverted: [Double]?) {
        if !self.hostedBy(dataZoomModel) {
            return
        }

        // It is important to get "consistent" extent when more then one axes is controlled by a
        // `dataZoom`. (See upstream comment.) Basically dataZoom obtains extent by series.data.
        let axis = self.getAxisModel().axis as! Axis
        scaleRawExtentInfoCreate(axis, AXIS_EXTENT_INFO_BUILD_FROM_DATA_ZOOM)

        let rawExtentInfo = axis.scale.rawExtentInfo!
        self._extent = rawExtentInfo.makeNoZoom()

        // `calculateDataWindow` uses min/maxSpan.
        self._updateMinMaxSpan()

        // upstream: let opt = dataZoomModel.settledOption; if (alignToPercentInverted) { opt = defaults({start,end}, opt); }
        //   `DataZoomWindowInput` has only the 4 window fields, so overriding start/end on a copy
        //   exactly reproduces `defaults({start, end}, settledOption)` (start/end forced, startValue/endValue kept).
        // `settledOption` is the `[String: Any]` option bag (ModelOption); build a typed
        //   `DataZoomWindowInput` from its window fields. Overriding start/end on the copy exactly
        //   reproduces upstream `defaults({start, end}, settledOption)`.
        let settled = (dataZoomModel.settledOption as? [String: Any]) ?? [:]
        var opt = DataZoomWindowInput(
            start: settled["start"],
            end: settled["end"],
            startValue: settled["startValue"],
            endValue: settled["endValue"]
        )
        if let align = alignToPercentInverted {
            opt.start = align[0]
            opt.end = align[1]
        }
        let window = self.calculateDataWindow(opt)
        self._window = window
        let percent = window.percent
        let value = window.value

        if percent[0] != 0 {
            rawExtentInfo.setZoomMM(0, value[0])
        }
        if percent[1] != 100 {
            rawExtentInfo.setZoomMM(1, value[1])
        }
    }

    public func filterData(_ dataZoomModel: DataZoomModel, _ api: ExtensionAPI) {
        if !self.hostedBy(dataZoomModel) {
            return
        }

        let axisDim = self._dimName
        let seriesModels = self.getTargetSeriesModels()
        // `filterMode` defaults to 'filter' (option default). A `nil` read here falls through all the
        // named branches to the `else` (selectRange), which IS the 'filter' behavior — so no fallback needed.
        let filterMode = dataZoomModel.get("filterMode") as? String
        let valueWindow = self._window.value

        if filterMode == "none" {
            return
        }

        // FIXME / TODO (See upstream comments on toolbox-injected dataZoom + stacked-NaN + huge-data.)

        func isInWindow(_ value: Double) -> Bool {
            return value >= valueWindow[0] && value <= valueWindow[1]
        }

        util.each(seriesModels) { seriesModel, _ in
            var seriesData = seriesModel.getData()
            let dataDims = seriesData.mapDimensionsAll(axisDim)

            if dataDims.isEmpty {
                return
            }

            if filterMode == "weakFilter" {
                let store = seriesData.getStore()
                let dataDimIndices = util.map(dataDims) { dim, _ in seriesData.getDimensionIndex(dim) }
                seriesData.filterSelf { args in
                    // no-dims filterSelf callback: args[0] is the dataIndex (as Double).
                    let dataIndex = Int(dzToDouble(args[0]))
                    var leftOut = false
                    var rightOut = false
                    var hasValue = false
                    for i in 0..<dataDims.count {
                        let value = dzToDouble(store.get(dataDimIndices[i], dataIndex))
                        let thisHasValue = !value.isNaN
                        let thisLeftOut = value < valueWindow[0]
                        let thisRightOut = value > valueWindow[1]
                        if thisHasValue && !thisLeftOut && !thisRightOut {
                            return true
                        }
                        if thisHasValue { hasValue = true }
                        if thisLeftOut { leftOut = true }
                        if thisRightOut { rightOut = true }
                    }
                    // If both left out and right out, do not filter.
                    return hasValue && leftOut && rightOut
                }
            }
            else {
                util.each(dataDims) { dim, _ in
                    if filterMode == "empty" {
                        seriesData = seriesData.map(dim) { args in
                            let value = dzToDouble(args[0])
                            return !isInWindow(value) ? Double.nan : value
                        }
                        seriesModel.setData(seriesData)
                    }
                    else {
                        var range: [String: [Double]] = [:]
                        range[dim] = valueWindow
                        seriesData.selectRange(range)
                    }
                }
            }

            util.each(dataDims) { dim, _ in
                seriesData.setApproximateExtent(valueWindow, dim)
            }
        }
    }

    private func _updateMinMaxSpan() {
        var minMaxSpan = MinMaxSpan()
        let dataZoomModel = self._dataZoomModel
        let dataExtent = self._extent!
        let scale = (self.getAxisModel().axis as! Axis).scale

        for minMax in ["min", "max"] {
            var percentSpan: Double? = dzCoerceNumber(dataZoomModel.get(minMax + "Span"))
            let rawValueSpan = dataZoomModel.get(minMax + "ValueSpan")
            var valueSpan: Double? = (rawValueSpan != nil && !(rawValueSpan is NSNull))
                ? scale.parse(rawValueSpan!)
                : nil

            // minValueSpan and maxValueSpan has higher priority than minSpan and maxSpan
            if valueSpan != nil {
                percentSpan = number.linearMap(
                    dataExtent[0] + valueSpan!, dataExtent, [0, 100], true
                )
            }
            else if percentSpan != nil {
                valueSpan = number.linearMap(
                    percentSpan!, [0, 100], dataExtent, true
                ) - dataExtent[0]
            }

            if minMax == "min" {
                minMaxSpan.minSpan = percentSpan
                minMaxSpan.minValueSpan = valueSpan
            }
            else {
                minMaxSpan.maxSpan = percentSpan
                minMaxSpan.maxValueSpan = valueSpan
            }
        }

        self._minMaxSpan = minMaxSpan
    }
}

// upstream nested `restrictSet` — extracted to a file-private function so the `fromWindow`/`toWindow`
//   arrays can be mutated via `inout` (Swift closures cannot capture `inout`).
private func dzRestrictSet(
    _ fromWindow: inout [Double],
    _ toWindow: inout [Double],
    _ fromExtent: [Double],
    _ toExtent: [Double],
    _ toValue: Bool,
    _ spans: MinMaxSpan,
    _ needRound: inout [Bool]
) {
    // const suffix = toValue ? 'Span' : 'ValueSpan';  ->  toValue: min/maxSpan ; !toValue: min/maxValueSpan
    let minSpan = toValue ? spans.minSpan : spans.minValueSpan
    let maxSpan = toValue ? spans.maxSpan : spans.maxValueSpan
    sliderMove(0, &fromWindow, fromExtent, .all, minSpan, maxSpan)
    for i in 0..<2 {
        toWindow[i] = number.linearMap(fromWindow[i], fromExtent, toExtent, true)
        if toValue {
            // toWindow[i] = toWindow[i];  (upstream no-op)
            needRound[i] = true
        }
    }
    dzEnsureExtentAscSimply(&toWindow)
}

// Bridge to `model.ensureExtentAscSimply(inout [Double?])` for a `[Double]`.
private func dzEnsureExtentAscSimply(_ extent: inout [Double]) {
    var tmp: [Double?] = extent.map { $0 }
    EChartsKit.model.ensureExtentAscSimply(&tmp)
    for i in 0..<extent.count {
        if let v = tmp[i] { extent[i] = v }
    }
}

// Int-vs-Double option-read trap: coerce an option value (which `defaultOptions` may box as `Int`) to
//   `Double?`, preserving `nil` for null/undefined/non-numeric. (See MEMORY int-vs-double-option-read-trap.)
private func dzCoerceNumber(_ v: Any?) -> Double? {
    if v == nil || v is NSNull { return nil }
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let f = v as? CGFloat { return Double(f) }
    return nil
}

// Coerce a `ParsedValue` (Any) to `Double`; `NaN` for non-numeric (matches JS numeric coercion on the
//   axis dimension). Used by `filterData`.
private func dzToDouble(_ v: Any?) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let f = v as? CGFloat { return Double(f) }
    return Double.nan
}
