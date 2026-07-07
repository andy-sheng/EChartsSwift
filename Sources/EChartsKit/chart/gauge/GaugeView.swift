// Ported from echarts/src/chart/gauge/GaugeView.ts — keep in sync with upstream
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
//   import PointerPath from './PointerPath';                          → sibling PointerPath.swift.
//   import * as graphic from '../../util/graphic';
//     → `Sector` / `Arc` / `Line` / `Circle` / `Text`(==ZRText) / `Group` are the ZRenderKit scene-graph
//       shapes (used directly — the sanctioned DRAWING deviation; cf. PieView / AngleAxisView).
//       PORT-TODO: `graphic.initProps` / `graphic.updateProps` (animation) are NOT ported — the diff-based
//       enter/update/remove + rotation/endAngle draw-on tweens are deferred (CONVENTIONS §5: STATIC render).
//   import { setStatesStylesFromModel, toggleHoverEmphasis } from '../../util/states';
//     → PORT-TODO: util/states NOT ported (emphasis/blur/focus states deferred).
//   import {createTextStyle, setLabelValueAnimation, animateLabelValue} from '../../label/labelStyle';
//     → PORT-TODO: label/labelStyle NOT ported. Text styles are built with a minimal plain reproduction
//       (`gaugeTextStyle` below — font/fill/align only), same deviation as FunnelView/Breadcrumb.
//       `setLabelValueAnimation` / `animateLabelValue` (detail number roll-up) are deferred.
//   import ChartView from '../../view/Chart';                         → ChartView (view/Chart.swift).
//   import {parsePercent, round, linearMap, DEFAULT_PRECISION_FOR_ROUNDING_ERROR} from '../../util/number';
//     → `number.parsePercent` / `number.round` / `number.linearMap` / `number.DEFAULT_PRECISION_FOR_ROUNDING_ERROR`.
//   import GaugeSeriesModel, { GaugeDataItemOption } from './GaugeSeries';  → sibling GaugeSeries.swift.
//   import GlobalModel from '../../model/Global';                     → GlobalModel.
//   import ExtensionAPI from '../../core/ExtensionAPI';               → ExtensionAPI.
//   import { ColorString, ECElement } from '../../util/types';        → ColorString(==String); ECElement deferred.
//   import SeriesData from '../../data/SeriesData';                   → SeriesData.
//   import Sausage from '../../util/shape/sausage';
//     → PORT-TODO: `util/shape/sausage` (round-capped sector) NOT ported. The `roundCap ? Sausage : Sector`
//       selection falls back to `Sector` (square caps); the band/progress geometry is otherwise identical.
//   import {createSymbol} from '../../util/symbol';                   → `symbol.createSymbol`.
//   import ZRImage from 'zrender/src/graphic/Image';
//     → PORT-TODO: the `pointer instanceof ZRImage` styling branch (image:// pointer icon) is deferred.
//   import { extend, isFunction, isString, isNumber, each } from 'zrender/src/core/util';
//     → `util.*` (ZRenderKit). `isString`/`isFunction`/`isNumber` used via the local helpers below.
//   import {setCommonECData} from '../../util/innerStore';
//     → PORT-TODO: inner-store ECData seam (tooltip indexing) deferred.
//   import { normalizeArcAngles } from 'zrender/src/core/PathProxy';  → `normalizeArcAngles` (ZRenderKit, free func).

// type ECSymbol = ReturnType<typeof createSymbol>;  → `ECSymbol` protocol (util/symbol.swift). Not needed as
//   a distinct alias here; the created pointer/anchor are handled as `Path`.

// upstream: interface PosInfo { cx: number; cy: number; r: number }
//   A plain data bag (no identity) → `struct`.
private struct PosInfo {
    var cx: Double
    var cy: Double
    var r: Double
}

// upstream: function parsePosition(seriesModel, api): PosInfo
private func parsePosition(_ seriesModel: GaugeSeriesModel, _ api: ExtensionAPI) -> PosInfo {
    // const center = seriesModel.get('center');
    let center = (seriesModel.get("center") as? [Any]) ?? []
    let width = api.getWidth()
    let height = api.getHeight()
    let size = Swift.min(width, height)
    // const cx = parsePercent(center[0], api.getWidth());
    let cx = number.parsePercent(center.count > 0 ? center[0] : nil, api.getWidth())
    let cy = number.parsePercent(center.count > 1 ? center[1] : nil, api.getHeight())
    let r = number.parsePercent(seriesModel.get("radius"), size / 2)

    return PosInfo(cx: cx, cy: cy, r: r)
}

// upstream: function formatLabel(value: number, labelFormatter: string | ((value: number) => string)): string
private func formatLabel(_ value: Double?, _ labelFormatter: Any?) -> String {
    // let label = value == null ? '' : (value + '');
    var label = value == nil ? "" : jsNumberToString(value!)
    // if (labelFormatter) { ... }
    if jsTruthy(labelFormatter) {
        if isString(labelFormatter) {
            // label = labelFormatter.replace('{value}', label);
            label = (labelFormatter as! String).replacingOccurrences(of: "{value}", with: label)
        }
        else if isFunction(labelFormatter) {
            // label = labelFormatter(value);
            // PORT-TODO: a JS `(value: number) => string` formatter callback cannot be invoked from the
            //   option bag in this port; the raw numeric label is kept. Restore when the formatter-callback
            //   seam lands.
            _ = labelFormatter
        }
    }

    return label
}

// upstream: class GaugeView extends ChartView
open class GaugeView: ChartView {

    // upstream: static type = 'gauge' as const;  /  type = GaugeView.type;
    public static let gaugeType = "gauge"
    open override var type: String {
        get { GaugeView.gaugeType }
        set { /* readonly upstream */ }
    }

    // upstream: private _data: SeriesData;
    private var _data: SeriesData?
    // upstream: private _progressEls: graphic.Path[];
    private var _progressEls: [Path?] = []

    // upstream: private _titleEls: graphic.Text[];
    private var _titleEls: [ZRText] = []
    // upstream: private _detailEls: graphic.Text[];
    private var _detailEls: [ZRText] = []

    // upstream: render(seriesModel: GaugeSeriesModel, ecModel: GlobalModel, api: ExtensionAPI)
    open override func render(
        _ seriesModelBase: SeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        // upstream typed `seriesModel: GaugeSeriesModel`; the base override is typed `SeriesModel`.
        let seriesModel = seriesModelBase as! GaugeSeriesModel

        _ = self.group.removeAll()

        // const colorList = seriesModel.get(['axisLine', 'lineStyle', 'color']);
        let colorList = gaugeColorList(seriesModel.get(["axisLine", "lineStyle", "color"]))
        let posInfo = parsePosition(seriesModel, api)

        self._renderMain(
            seriesModel, ecModel, api, colorList, posInfo
        )

        self._data = seriesModel.getData()
    }

    // upstream: dispose() {}
    open override func dispose(_ ecModel: GlobalModel, _ api: ExtensionAPI) {}

    // upstream: _renderMain(seriesModel, ecModel, api, colorList, posInfo)
    private func _renderMain(
        _ seriesModel: GaugeSeriesModel,
        _ ecModel: GlobalModel,
        _ api: ExtensionAPI,
        _ colorList: [(Double, String)],
        _ posInfo: PosInfo
    ) {
        let group = self.group
        let clockwise = jsTruthy(seriesModel.get("clockwise"))
        // let startAngle = -seriesModel.get('startAngle') / 180 * Math.PI;  (default 225 — an Int literal!)
        var startAngle = -(gaugeNum(seriesModel.get("startAngle")) ?? 0) / 180 * Double.pi
        // let endAngle = -seriesModel.get('endAngle') / 180 * Math.PI;      (default -45 — an Int literal!)
        var endAngle = -(gaugeNum(seriesModel.get("endAngle")) ?? 0) / 180 * Double.pi
        let axisLineModel = seriesModel.getModel("axisLine")

        let roundCap = jsTruthy(axisLineModel.get("roundCap"))
        // const MainPath = roundCap ? Sausage : graphic.Sector;
        // PORT-TODO: Sausage (round-capped sector) NOT ported; `Sector` is used for both branches.
        _ = roundCap

        let showAxis = jsTruthy(axisLineModel.get("show"))
        let lineStyleModel = axisLineModel.getModel("lineStyle")
        let axisLineWidth = gaugeNum(lineStyleModel.get("width")) ?? 0

        // const angles = [startAngle, endAngle]; normalizeArcAngles(angles, !clockwise);
        var angles = [startAngle, endAngle]
        normalizeArcAngles(&angles, !clockwise)
        startAngle = angles[0]
        endAngle = angles[1]
        let angleRangeSpan = endAngle - startAngle

        var prevEndAngle = startAngle

        // const sectors: (Sausage | graphic.Sector)[] = [];
        var sectors: [Path] = []
        // for (let i = 0; showAxis && i < colorList.length; i++)
        var i = 0
        while showAxis && i < colorList.count {
            // Clamp
            let percent = Swift.min(Swift.max(colorList[i].0, 0), 1)
            endAngle = startAngle + angleRangeSpan * percent
            var sectorShape = SectorShape()
            sectorShape.startAngle = prevEndAngle
            sectorShape.endAngle = endAngle
            sectorShape.cx = posInfo.cx
            sectorShape.cy = posInfo.cy
            sectorShape.clockwise = clockwise
            sectorShape.r0 = posInfo.r - axisLineWidth
            sectorShape.r = posInfo.r
            let sector = Sector([
                "shape": sectorShape as PathShape,
                "silent": true
            ])

            // sector.setStyle({ fill: colorList[i][1] });
            // sector.setStyle(lineStyleModel.getLineStyle(['color', 'width']));  (color/width excluded — arc
            //   is simulated by a sector so the stroke props are useless). The fill (set first) survives.
            var style = pathStyleFromDict(lineStyleModel.getLineStyle(["color", "width"]))
            style.fill = .string(colorList[i].1)
            sector.useStyle(style)

            sectors.append(sector)

            prevEndAngle = endAngle
            i += 1
        }

        // sectors.reverse(); each(sectors, sector => group.add(sector));
        sectors.reverse()
        util.each(sectors, { sector, _ in _ = group.add(sector) })

        // const getColor = function (percent) { ... }
        let getColor: (Double) -> String = { percent in
            // Less than 0
            if percent <= 0 {
                return colorList[0].1
            }
            var i = 0
            while i < colorList.count {
                if colorList[i].0 >= percent
                    && (i == 0 ? 0 : colorList[i - 1].0) < percent {
                    return colorList[i].1
                }
                i += 1
            }
            // More than 1
            return colorList[i - 1].1
        }

        self._renderTicks(
            seriesModel, ecModel, api, getColor, posInfo,
            startAngle, endAngle, clockwise, axisLineWidth
        )

        self._renderTitleAndDetail(
            seriesModel, ecModel, api, getColor, posInfo
        )

        self._renderAnchor(seriesModel, posInfo)

        self._renderPointer(
            seriesModel, ecModel, api, getColor, posInfo,
            startAngle, endAngle, clockwise, axisLineWidth
        )
    }

    // upstream: _renderTicks(seriesModel, ecModel, api, getColor, posInfo, startAngle, endAngle, clockwise, axisLineWidth)
    private func _renderTicks(
        _ seriesModel: GaugeSeriesModel,
        _ ecModel: GlobalModel,
        _ api: ExtensionAPI,
        _ getColor: (Double) -> String,
        _ posInfo: PosInfo,
        _ startAngle: Double,
        _ endAngle: Double,
        _ clockwise: Bool,
        _ axisLineWidth: Double
    ) {
        let group = self.group
        let cx = posInfo.cx
        let cy = posInfo.cy
        let r = posInfo.r

        // const minVal = +seriesModel.get('min');  (default 0 — an Int literal!)
        let minVal = gaugeNum(seriesModel.get("min")) ?? 0
        // const maxVal = +seriesModel.get('max');  (default 100 — an Int literal!)
        let maxVal = gaugeNum(seriesModel.get("max")) ?? 0

        let splitLineModel = seriesModel.getModel("splitLine")
        let tickModel = seriesModel.getModel("axisTick")
        let labelModel = seriesModel.getModel("axisLabel")

        // const splitNumber = seriesModel.get('splitNumber');  (default 10 — an Int literal!)
        let splitNumber = gaugeNum(seriesModel.get("splitNumber")) ?? 0
        let subSplitNumber = gaugeNum(tickModel.get("splitNumber")) ?? 0

        let splitLineLen = number.parsePercent(splitLineModel.get("length"), r)
        let tickLen = number.parsePercent(tickModel.get("length"), r)

        var angle = startAngle
        let step = (endAngle - startAngle) / splitNumber
        let subStep = step / subSplitNumber

        let splitLineStyleDict = splitLineModel.getModel("lineStyle").getLineStyle()
        let tickLineStyleDict = tickModel.getModel("lineStyle").getLineStyle()

        // const splitLineDistance = splitLineModel.get('distance');
        let splitLineDistance = gaugeNum(splitLineModel.get("distance")) ?? 0

        var unitX: Double
        var unitY: Double

        // for (let i = 0; i <= splitNumber; i++)
        let splitNumberInt = Int(splitNumber)
        var i = 0
        while i <= splitNumberInt {
            unitX = cos(angle)
            unitY = sin(angle)
            // Split line
            if jsTruthy(splitLineModel.get("show")) {
                // const distance = splitLineDistance ? splitLineDistance + axisLineWidth : axisLineWidth;
                let distance = jsTruthyNum(splitLineDistance) ? splitLineDistance + axisLineWidth : axisLineWidth
                var lineShape = LineShape()
                lineShape.x1 = unitX * (r - distance) + cx
                lineShape.y1 = unitY * (r - distance) + cy
                lineShape.x2 = unitX * (r - splitLineLen - distance) + cx
                lineShape.y2 = unitY * (r - splitLineLen - distance) + cy
                let splitLine = Line([
                    "shape": lineShape as PathShape,
                    "silent": true
                ])
                var splitLineStyle = pathStyleFromDict(splitLineStyleDict)
                // if (splitLineStyle.stroke === 'auto') { splitLine.setStyle({ stroke: getColor(i/splitNumber) }); }
                if (splitLineStyleDict["stroke"] as? String) == "auto" {
                    splitLineStyle.stroke = .string(getColor(Double(i) / splitNumber))
                }
                splitLine.useStyle(splitLineStyle)

                _ = group.add(splitLine)
            }

            // Label
            if jsTruthy(labelModel.get("show")) {
                // const distance = labelModel.get('distance') + splitLineDistance;
                let distance = (gaugeNum(labelModel.get("distance")) ?? 0) + splitLineDistance

                let label = formatLabel(
                    // multiply firstly to avoid rounding error.
                    number.round(Double(i) * (maxVal - minVal) / splitNumber + minVal, number.DEFAULT_PRECISION_FOR_ROUNDING_ERROR),
                    labelModel.get("formatter")
                )
                let autoColor = getColor(Double(i) / splitNumber)
                let textStyleX = unitX * (r - splitLineLen - distance) + cx
                let textStyleY = unitY * (r - splitLineLen - distance) + cy

                let rotateType = labelModel.get("rotate")
                var rotate = 0.0
                if (rotateType as? String) == "radial" {
                    rotate = -angle + 2 * Double.pi
                    if rotate > Double.pi / 2 {
                        rotate += Double.pi
                    }
                }
                else if (rotateType as? String) == "tangential" {
                    rotate = -angle - Double.pi / 2
                }
                else if isNumber(rotateType) {
                    rotate = (gaugeNum(rotateType) ?? 0) * Double.pi / 180
                }

                // fill via inheritColor: labelModel textColor OR the auto (segment) color.
                let fill = labelModel.getTextColor() ?? autoColor

                if rotate == 0 {
                    var ts = gaugeTextStyle(labelModel, text: label, fill: fill,
                        align: unitX < -0.4 ? .left : (unitX > 0.4 ? .right : .center),
                        verticalAlign: unitY < -0.8 ? .top : (unitY > 0.8 ? .bottom : .middle))
                    ts.x = textStyleX
                    ts.y = textStyleY
                    let textEl = ZRText(["silent": true])
                    textEl.useStyle(ts)
                    _ = group.add(textEl)
                }
                else {
                    var ts = gaugeTextStyle(labelModel, text: label, fill: fill,
                        align: .center, verticalAlign: .middle)
                    ts.x = textStyleX
                    ts.y = textStyleY
                    let textEl = ZRText(["silent": true])
                    textEl.useStyle(ts)
                    textEl.originX = textStyleX
                    textEl.originY = textStyleY
                    textEl.rotation = rotate
                    _ = group.add(textEl)
                }
            }

            // Axis tick
            if jsTruthy(tickModel.get("show")) && i != splitNumberInt {
                // let distance = tickModel.get('distance'); distance = distance ? distance + axisLineWidth : axisLineWidth;
                let tickDistanceRaw = gaugeNum(tickModel.get("distance")) ?? 0
                let distance = jsTruthyNum(tickDistanceRaw) ? tickDistanceRaw + axisLineWidth : axisLineWidth

                // for (let j = 0; j <= subSplitNumber; j++)
                let subSplitNumberInt = Int(subSplitNumber)
                var j = 0
                while j <= subSplitNumberInt {
                    unitX = cos(angle)
                    unitY = sin(angle)
                    var lineShape = LineShape()
                    lineShape.x1 = unitX * (r - distance) + cx
                    lineShape.y1 = unitY * (r - distance) + cy
                    lineShape.x2 = unitX * (r - tickLen - distance) + cx
                    lineShape.y2 = unitY * (r - tickLen - distance) + cy
                    let tickLine = Line([
                        "shape": lineShape as PathShape,
                        "silent": true
                    ])

                    var tickLineStyle = pathStyleFromDict(tickLineStyleDict)
                    if (tickLineStyleDict["stroke"] as? String) == "auto" {
                        tickLineStyle.stroke = .string(getColor((Double(i) + Double(j) / subSplitNumber) / splitNumber))
                    }
                    tickLine.useStyle(tickLineStyle)

                    _ = group.add(tickLine)
                    angle += subStep
                    j += 1
                }
                angle -= subStep
            }
            else {
                angle += step
            }
            i += 1
        }
    }

    // upstream: _renderPointer(seriesModel, ecModel, api, getColor, posInfo, startAngle, endAngle, clockwise, axisLineWidth)
    private func _renderPointer(
        _ seriesModel: GaugeSeriesModel,
        _ ecModel: GlobalModel,
        _ api: ExtensionAPI,
        _ getColor: (Double) -> String,
        _ posInfo: PosInfo,
        _ startAngle: Double,
        _ endAngle: Double,
        _ clockwise: Bool,
        _ axisLineWidth: Double
    ) {
        let group = self.group
        // const oldData = this._data; const oldProgressData = this._progressEls;  — used only by the
        //   deferred diff/animation path.
        _ = self._data
        _ = self._progressEls

        let showPointer = jsTruthy(seriesModel.get(["pointer", "show"]))
        let progressModel = seriesModel.getModel("progress")
        let showProgress = jsTruthy(progressModel.get("show"))

        let data = seriesModel.getData()
        let valueDim = data.mapDimension("value")
        let minVal = gaugeNum(seriesModel.get("min")) ?? 0
        let maxVal = gaugeNum(seriesModel.get("max")) ?? 0
        let valueExtent = [minVal, maxVal]
        let angleExtent = [startAngle, endAngle]

        var progressList = [Path?](repeating: nil, count: data.count())

        // function createPointer(idx, angle)
        func createPointer(_ idx: Int, _ angle: Double) -> Path {
            let itemModel = data.getItemModel(idx)
            let pointerModel = itemModel.getModel("pointer")
            let pointerWidth = number.parsePercent(pointerModel.get("width"), posInfo.r)
            let pointerLength = number.parsePercent(pointerModel.get("length"), posInfo.r)
            let pointerStr = seriesModel.get(["pointer", "icon"])
            let pointerOffset = (pointerModel.get("offsetCenter") as? [Any]) ?? []
            let pointerOffsetX = number.parsePercent(pointerOffset.count > 0 ? pointerOffset[0] : nil, posInfo.r)
            let pointerOffsetY = number.parsePercent(pointerOffset.count > 1 ? pointerOffset[1] : nil, posInfo.r)
            let pointerKeepAspect = pointerModel.get("keepAspect") as? Bool

            let pointer: Path
            // not exist icon type will be set 'rect'
            if jsTruthy(pointerStr) {
                // createSymbol returns ECSymbol; the concrete conformer is always a Path in this port.
                pointer = symbol.createSymbol(
                    pointerStr as! String,
                    pointerOffsetX - pointerWidth / 2,
                    pointerOffsetY - pointerLength,
                    pointerWidth,
                    pointerLength,
                    nil,
                    pointerKeepAspect
                ) as! Path
            }
            else {
                var shape = PointerShape()
                shape.angle = -Double.pi / 2
                shape.width = pointerWidth
                shape.r = pointerLength
                shape.x = pointerOffsetX
                shape.y = pointerOffsetY
                pointer = PointerPath(["shape": shape as PathShape])
            }
            pointer.rotation = -(angle + Double.pi / 2)
            pointer.x = posInfo.cx
            pointer.y = posInfo.cy
            return pointer
        }

        // function createProgress(idx, endAngle)
        func createProgress(_ idx: Int, _ endAngle: Double) -> Sector {
            let roundCap = jsTruthy(progressModel.get("roundCap"))
            // const ProgressPath = roundCap ? Sausage : graphic.Sector;
            // PORT-TODO: Sausage NOT ported; `Sector` used for both branches.
            _ = roundCap

            let isOverlap = jsTruthy(progressModel.get("overlap"))
            let progressWidth = isOverlap ? (gaugeNum(progressModel.get("width")) ?? 0) : axisLineWidth / Double(data.count())
            let r0 = isOverlap ? posInfo.r - progressWidth : posInfo.r - Double(idx + 1) * progressWidth
            let r = isOverlap ? posInfo.r : posInfo.r - Double(idx) * progressWidth
            var shape = SectorShape()
            shape.startAngle = startAngle
            shape.endAngle = endAngle
            shape.cx = posInfo.cx
            shape.cy = posInfo.cy
            shape.clockwise = clockwise
            shape.r0 = r0
            shape.r = r
            let progress = Sector(["shape": shape as PathShape])
            if isOverlap {
                progress.z2 = number.linearMap(asDouble(data.get(valueDim!, idx)), [minVal, maxVal], [100, 0], true)
            }
            return progress
        }

        // ------------------------------------------------------------------------------------------
        // STATIC render deviation: upstream diffs `oldData` → add/update the pointer + progress with
        //   `graphic.initProps`/`updateProps` rotation/endAngle tweens. The full add/update diff is
        //   deferred (CONVENTIONS §5). The pointer's entrance sweep (rotation from startAngle to the
        //   value angle) IS wired via the shared `initProps`; the progress sector is still built
        //   directly at its FINAL endAngle (the tween end-state), then styled in a second pass
        //   (mirroring the upstream `data.each`).
        // ------------------------------------------------------------------------------------------
        if showProgress || showPointer {
            for idx in 0..<data.count() {
                let val = asDouble(data.get(valueDim!, idx))
                if showPointer {
                    // upstream: createPointer(idx, startAngle) then initProps rotation to the value angle.
                    //   Create the pointer collapsed at startAngle, then sweep its rotation to the
                    //   final value angle via the shared enter transition (instant when animation off).
                    let finalAngle = val.isNaN ? angleExtent[0] : number.linearMap(val, valueExtent, angleExtent, true)
                    let pointer = createPointer(idx, startAngle)
                    initProps(pointer, ["rotation": -(finalAngle + Double.pi / 2)], seriesModel)
                    _ = group.add(pointer)
                    data.setItemGraphicEl(idx, pointer)
                }

                if showProgress {
                    let isClip = jsTruthy(progressModel.get("clip"))
                    // upstream: createProgress(idx, startAngle) then initProps shape.endAngle to the value angle.
                    //   Static: create directly at the final endAngle.
                    let progress = createProgress(idx, number.linearMap(val, valueExtent, angleExtent, isClip))
                    _ = group.add(progress)
                    // PORT-TODO: setCommonECData(seriesModel.seriesIndex, data.dataType, idx, progress)
                    //   — inner-store ECData tooltip indexing deferred.
                    progressList[idx] = progress
                }
            }

            // upstream: data.each(function (idx) { ... styling + emphasis/states ... })
            for idx in 0..<data.count() {
                let itemModel = data.getItemModel(idx)
                // const emphasisModel = itemModel.getModel('emphasis'); focus/blurScope/disabled
                //   PORT-TODO: emphasis/blur/focus states deferred (util/states not ported).
                let autoColor = getColor(number.linearMap(asDouble(data.get(valueDim!, idx)), valueExtent, [0, 1], true))
                if showPointer {
                    let pointer = data.getItemGraphicEl(idx) as? Path
                    let symbolStyle = data.getItemVisual(idx, "style")
                    let visualColor = gaugeVisualFill(symbolStyle)
                    // PORT-TODO: the `pointer instanceof ZRImage` branch (image:// icon) is deferred.
                    //   pointer.useStyle(symbolStyle); then `pointer.type !== 'pointer' && pointer.setColor(visualColor)`;
                    //   then setStyle(itemModel.getModel(['pointer','itemStyle']).getItemStyle()); then 'auto' fill.
                    //   Static: merge the visual style + pointer itemStyle into one bag, resolve 'auto', useStyle.
                    var styleDict = styleToDict(symbolStyle)
                    let pointerItemStyle = itemModel.getModel(["pointer", "itemStyle"]).getItemStyle()
                    for (k, v) in pointerItemStyle { styleDict[k] = v }
                    if let pointer = pointer, pointer.type != "pointer", let sym = pointer as? ECSymbol,
                       let vc = visualColor {
                        sym.setColor(.string(vc), nil)
                    }
                    if (styleDict["fill"] as? String) == "auto" {
                        styleDict["fill"] = autoColor
                    }
                    pointer?.useStyle(barStyleFromDict(styleDict))
                    // PORT-TODO: z2EmphasisLift = 0; setStatesStylesFromModel; toggleHoverEmphasis — deferred.
                }

                if showProgress {
                    let progress = progressList[idx]
                    var styleDict = styleToDict(data.getItemVisual(idx, "style"))
                    let progressItemStyle = itemModel.getModel(["progress", "itemStyle"]).getItemStyle()
                    for (k, v) in progressItemStyle { styleDict[k] = v }
                    if (styleDict["fill"] as? String) == "auto" {
                        styleDict["fill"] = autoColor
                    }
                    progress?.useStyle(barStyleFromDict(styleDict))
                    // PORT-TODO: z2EmphasisLift = 0; setStatesStylesFromModel; toggleHoverEmphasis — deferred.
                }
            }

            self._progressEls = progressList
        }
    }

    // upstream: _renderAnchor(seriesModel, posInfo)
    private func _renderAnchor(
        _ seriesModel: GaugeSeriesModel,
        _ posInfo: PosInfo
    ) {
        let anchorModel = seriesModel.getModel("anchor")
        let showAnchor = jsTruthy(anchorModel.get("show"))
        if showAnchor {
            let anchorSize = gaugeNum(anchorModel.get("size")) ?? 0
            let anchorType = (anchorModel.get("icon") as? String) ?? ""
            let offsetCenter = (anchorModel.get("offsetCenter") as? [Any]) ?? []
            let anchorKeepAspect = anchorModel.get("keepAspect") as? Bool
            let anchor = symbol.createSymbol(
                anchorType,
                posInfo.cx - anchorSize / 2 + number.parsePercent(offsetCenter.count > 0 ? offsetCenter[0] : nil, posInfo.r),
                posInfo.cy - anchorSize / 2 + number.parsePercent(offsetCenter.count > 1 ? offsetCenter[1] : nil, posInfo.r),
                anchorSize,
                anchorSize,
                nil,
                anchorKeepAspect
            ) as! Path
            anchor.z2 = jsTruthy(anchorModel.get("showAbove")) ? 1 : 0
            anchor.useStyle(barStyleFromDict(anchorModel.getModel("itemStyle").getItemStyle()))
            _ = self.group.add(anchor)
        }
    }

    // upstream: _renderTitleAndDetail(seriesModel, ecModel, api, getColor, posInfo)
    private func _renderTitleAndDetail(
        _ seriesModel: GaugeSeriesModel,
        _ ecModel: GlobalModel,
        _ api: ExtensionAPI,
        _ getColor: (Double) -> String,
        _ posInfo: PosInfo
    ) {
        let data = seriesModel.getData()
        let valueDim = data.mapDimension("value")
        let minVal = gaugeNum(seriesModel.get("min")) ?? 0
        let maxVal = gaugeNum(seriesModel.get("max")) ?? 0

        let contentGroup = Group()

        var newTitleEls: [ZRText] = []
        var newDetailEls: [ZRText] = []
        // const hasAnimation = seriesModel.isAnimationEnabled();
        //   PORT-TODO: the detail number roll-up animation is deferred.
        _ = seriesModel.isAnimationEnabled()

        let showPointerAbove = jsTruthy(seriesModel.get(["pointer", "showAbove"]))

        // ------------------------------------------------------------------------------------------
        // STATIC render deviation: upstream diffs `this._data` → reuse the previous title/detail Text
        //   elements on update. Here fresh Text elements are created per datum each render.
        // ------------------------------------------------------------------------------------------
        for _ in 0..<data.count() {
            newTitleEls.append(ZRText(["silent": true]))
            newDetailEls.append(ZRText(["silent": true]))
        }

        // data.each(function (idx) { ... })
        for idx in 0..<data.count() {
            let itemModel = data.getItemModel(idx)
            let value = asDouble(data.get(valueDim!, idx))
            let itemGroup = Group()
            let autoColor = getColor(
                number.linearMap(value, [minVal, maxVal], [0, 1], true)
            )

            let itemTitleModel = itemModel.getModel("title")
            if jsTruthy(itemTitleModel.get("show")) {
                let titleOffsetCenter = (itemTitleModel.get("offsetCenter") as? [Any]) ?? []
                let titleX = posInfo.cx + number.parsePercent(titleOffsetCenter.count > 0 ? titleOffsetCenter[0] : nil, posInfo.r)
                let titleY = posInfo.cy + number.parsePercent(titleOffsetCenter.count > 1 ? titleOffsetCenter[1] : nil, posInfo.r)
                let labelEl = newTitleEls[idx]
                labelEl.z2 = showPointerAbove ? 0 : 2
                var ts = gaugeTextStyle(itemTitleModel,
                    text: data.getName(idx),
                    fill: itemTitleModel.getTextColor() ?? autoColor,
                    align: .center, verticalAlign: .middle)
                ts.x = titleX
                ts.y = titleY
                labelEl.useStyle(ts)

                _ = itemGroup.add(labelEl)
            }

            let itemDetailModel = itemModel.getModel("detail")
            if jsTruthy(itemDetailModel.get("show")) {
                let detailOffsetCenter = (itemDetailModel.get("offsetCenter") as? [Any]) ?? []
                let detailX = posInfo.cx + number.parsePercent(detailOffsetCenter.count > 0 ? detailOffsetCenter[0] : nil, posInfo.r)
                let detailY = posInfo.cy + number.parsePercent(detailOffsetCenter.count > 1 ? detailOffsetCenter[1] : nil, posInfo.r)
                let width = number.parsePercent(itemDetailModel.get("width"), posInfo.r)
                let height = number.parsePercent(itemDetailModel.get("height"), posInfo.r)
                // const detailColor = seriesModel.get(['progress','show']) ? data.getItemVisual(idx,'style').fill : autoColor;
                let detailColor: String? = jsTruthy(seriesModel.get(["progress", "show"]))
                    ? gaugeVisualFill(data.getItemVisual(idx, "style"))
                    : autoColor
                let labelEl = newDetailEls[idx]
                let formatter = itemDetailModel.get("formatter")
                labelEl.z2 = showPointerAbove ? 0 : 2
                var ts = gaugeTextStyle(itemDetailModel,
                    text: formatLabel(value, formatter),
                    fill: itemDetailModel.getTextColor() ?? detailColor,
                    align: .center, verticalAlign: .middle)
                ts.x = detailX
                ts.y = detailY
                // width: isNaN(width) ? null : width, height: isNaN(height) ? null : height
                ts.width = width.isNaN ? nil : width
                ts.height = height.isNaN ? nil : height
                labelEl.useStyle(ts)
                // PORT-TODO: setLabelValueAnimation / animateLabelValue (detail number roll-up) deferred.

                _ = itemGroup.add(labelEl)
            }

            _ = contentGroup.add(itemGroup)
        }
        _ = self.group.add(contentGroup)

        self._titleEls = newTitleEls
        self._detailEls = newDetailEls
    }

}

// export default GaugeView;  -> `open class GaugeView` above.


// ============================================================================
// PORT-TODO helpers — NOT part of GaugeView.ts upstream. These reproduce the dynamic-option coercion,
// the JS truthiness/number-stringification, the color-stop parsing, and a minimal `createTextStyle`.
// Delete each when its real sibling (label/labelStyle, util/graphic style bridge) lands.
// ============================================================================

/// Int|Double|NSNumber → Double coercion for the `[String: Any]` option bag. The gauge default-option
/// store keeps numbers as bare `Int` literals (startAngle: 225, endAngle: -45, splitNumber: 10, min: 0,
/// max: 100, widths/offsets, fontSize …), so a bare `as? Double` SILENTLY DROPS them (CONVENTIONS:
/// INT-vs-DOUBLE trap — this exact bug once rotated a whole radar 90°). Use this for EVERY numeric read.
private func gaugeNum(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber, !(n === kCFBooleanTrue || n === kCFBooleanFalse) { return n.doubleValue }
    return nil
}

/// ParsedValue (`Any?`) → Double for value-dimension reads (`data.get(valueDim, idx)`). NaN when absent
/// (matches upstream `+val` → NaN for null/non-numeric, guarded by `isNaN(+val)` at the pointer angle).
private func asDouble(_ v: Any?) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber, !(n === kCFBooleanTrue || n === kCFBooleanFalse) { return n.doubleValue }
    if let s = v as? String { return Double(s) ?? Double.nan }
    return Double.nan
}

/// JS truthiness for the dynamic option bag (`if (x)` / `model.get('show')`) — CONVENTIONS §6 (do NOT
/// use Swift `??`). Mirrors the file-private helper across the polar/pie/funnel ports.
private func jsTruthy(_ v: Any?) -> Bool {
    guard let v = v else { return false }
    // NSNull() is the [String: Any] bag's stand-in for JS `null` (e.g. defaultOption pointer.icon,
    //   detail.height) — falsy, exactly like `if (null)` upstream. Without this, `pointer.icon`'s
    //   NSNull default would enter the `pointerStr as! String` branch and crash.
    if v is NSNull { return false }
    if let b = v as? Bool { return b }
    if let d = v as? Double { return d != 0 && !d.isNaN }
    if let i = v as? Int { return i != 0 }
    if let s = v as? String { return !s.isEmpty }
    return true
}

/// JS truthiness for an already-coerced number (`splitLineDistance ? ...`): non-zero and non-NaN.
private func jsTruthyNum(_ v: Double) -> Bool {
    return v != 0 && !v.isNaN
}

// upstream `isString` / `isFunction` / `isNumber` (zrender/src/core/util) as used by formatLabel/_renderTicks.
private func isString(_ v: Any?) -> Bool { return v is String }
private func isFunction(_ v: Any?) -> Bool { return util.isFunction(v) }
private func isNumber(_ v: Any?) -> Bool {
    if v is Double || v is Int { return true }
    if let n = v as? NSNumber, !(n === kCFBooleanTrue || n === kCFBooleanFalse) { _ = n; return true }
    return false
}

/// JS `value + ''` for a number. Integers render without a decimal point (`20` → "20"); non-integers
/// keep their shortest decimal form. PORT-TODO: not a full ECMAScript Number→String (no exponent form).
private func jsNumberToString(_ v: Double) -> String {
    if v.isNaN { return "NaN" }
    if v == v.rounded() && Swift.abs(v) < 1e15 {
        return String(Int(v))
    }
    return String(v)
}

/// Parse the `axisLine.lineStyle.color` color-stop list (`[[percent, color], ...]`) into `[(Double, String)]`.
///   `percent` may be a bare Int literal (`1`) → coerced via gaugeNum; `color` is a solid string (or a
///   ZRColor.color). PORT-TODO: gradient/pattern color values are not modeled (solid strings only).
private func gaugeColorList(_ v: Any?) -> [(Double, String)] {
    guard let arr = v as? [Any] else { return [] }
    var out: [(Double, String)] = []
    for item in arr {
        guard let pair = item as? [Any], pair.count >= 2 else { continue }
        let p = gaugeNum(pair[0]) ?? 0
        let c: String
        if let s = pair[1] as? String { c = s }
        else if let zr = pair[1] as? EChartsKit.ZRColor, case let .color(str) = zr { c = str }
        else { c = "" }
        out.append((p, c))
    }
    return out
}

/// Extract the solid-color fill string from an item-visual 'style' bag (stored as an EChartsKit `ZRColor`
///   or a raw String). Mirrors FunnelView.funnelVisualFill.
private func gaugeVisualFill(_ style: Any?) -> String? {
    guard let d = style as? [String: Any] else { return nil }
    if let str = d["fill"] as? String { return str }
    if let zr = d["fill"] as? EChartsKit.ZRColor, case let .color(str) = zr { return str }
    return nil
}

/// Coerce an item-visual 'style' value (`Any?`) to a mutable `[String: Any]` bag so the pointer/progress
///   itemStyle overrides can be merged onto it before bridging via `barStyleFromDict`.
private func styleToDict(_ style: Any?) -> [String: Any] {
    return (style as? [String: Any]) ?? [:]
}

/// PORT-TODO: minimal reproduction of `label/labelStyle.createTextStyle(textStyleModel, opts, {inheritColor})`.
///   Only text/font/fill/align/verticalAlign are modeled (the geometry the gauge needs); x/y/width/height
///   and rotation are set by the caller on the returned struct / element. Same deviation as
///   FunnelView / Breadcrumb / AxisBuilder.createTextStyle. Delete when label/labelStyle.swift lands.
private func gaugeTextStyle(
    _ textStyleModel: Model,
    text: String?,
    fill: String?,
    align: TextAlign?,
    verticalAlign: TextVerticalAlign?
) -> TextStyleProps {
    var s = TextStyleProps()
    s.text = text
    s.font = textStyleModel.getFont()
    s.fill = fill
    s.align = align
    s.verticalAlign = verticalAlign
    return s
}

/// PORT-TODO: `util/graphic` style-bag bridge for LINE styles (splitline/tick). `Model.getLineStyle()`
///   returns the dynamic `[String: Any]` paint bag; ZRenderKit `Path.style` is a typed `PathStyleProps`.
///   Maps the common stroke/line keys (stroke resolved elsewhere for the 'auto' sentinel). Mirrors
///   AngleAxisView.pathStyleFromDict. `lineDash` is not bridged yet.
private func gaugeStyleNum(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber, !(n === kCFBooleanTrue || n === kCFBooleanFalse) { return n.doubleValue }
    return nil
}

private func pathStyleFromDict(_ dict: [String: Any]) -> PathStyleProps {
    var s = PathStyleProps()
    // PORT-TODO: `fill`/`stroke` may be a gradient/pattern object; only the String form (incl. 'none'/'auto')
    //   is mapped here. The 'auto' stroke sentinel is overridden by getColor at the call site.
    if let fill = dict["fill"] as? String { s.fill = .string(fill) }
    if let stroke = dict["stroke"] as? String { s.stroke = .string(stroke) }
    if let lineWidth = gaugeStyleNum(dict["lineWidth"]) { s.lineWidth = lineWidth }
    if let lineCap = dict["lineCap"] as? String { s.lineCap = lineCap }
    if let lineJoin = dict["lineJoin"] as? String { s.lineJoin = lineJoin }
    if let opacity = gaugeStyleNum(dict["opacity"]) { s.opacity = opacity }
    if let shadowBlur = gaugeStyleNum(dict["shadowBlur"]) { s.shadowBlur = shadowBlur }
    if let shadowOffsetX = gaugeStyleNum(dict["shadowOffsetX"]) { s.shadowOffsetX = shadowOffsetX }
    if let shadowOffsetY = gaugeStyleNum(dict["shadowOffsetY"]) { s.shadowOffsetY = shadowOffsetY }
    if let shadowColor = dict["shadowColor"] as? String { s.shadowColor = shadowColor }
    if let lineDashOffset = gaugeStyleNum(dict["lineDashOffset"]) { s.lineDashOffset = lineDashOffset }
    if let miterLimit = gaugeStyleNum(dict["miterLimit"]) { s.miterLimit = miterLimit }
    return s
}
