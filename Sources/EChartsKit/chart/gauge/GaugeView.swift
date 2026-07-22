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
//       PORT-NOTE: `graphic.initProps` / `graphic.updateProps` are ported (animation/basicTransition.swift) and
//       ARE now wired: `_renderPointer` diffs `_data` and enter-animates (initProps) the pointer rotation /
//       progress endAngle on first appearance, then TWEENS (updateProps) them from their current value to the
//       new value on refresh — the pointer/progress reset-on-update fix. The static parts (axisLine/ticks/
//       splitLines/labels) are retained + reused across renders (see `_staticGroup`) rather than rebuilt.
//   import { setStatesStylesFromModel, toggleHoverEmphasis } from '../../util/states';
//     → PORT-NOTE: util/states.swift is ported; emphasis/blur/focus states just aren't wired here yet.
//   import {createTextStyle, setLabelValueAnimation, animateLabelValue} from '../../label/labelStyle';
//     → createTextStyle / setLabelValueAnimation / animateLabelValue are PORTED
//       (label/labelStyle.swift:416 / :819 / :858) and now WIRED: the local `gaugeTextStyle` adapter below
//       delegates to `labelStyle.createTextStyle` (restoring textBorder/shadow/rich styling), and the detail
//       number roll-up (setLabelValueAnimation + animateLabelValue) is driven in `_renderTitleAndDetail`
//       (gated on the detail's `valueAnimation` option and the series animation being enabled). The
//       title/detail Text elements are also reused across renders (diffed against `_data`).
//   import ChartView from '../../view/Chart';                         → ChartView (view/Chart.swift).
//   import {parsePercent, round, linearMap, DEFAULT_PRECISION_FOR_ROUNDING_ERROR} from '../../util/number';
//     → `number.parsePercent` / `number.round` / `number.linearMap` / `number.DEFAULT_PRECISION_FOR_ROUNDING_ERROR`.
//   import GaugeSeriesModel, { GaugeDataItemOption } from './GaugeSeries';  → sibling GaugeSeries.swift.
//   import GlobalModel from '../../model/Global';                     → GlobalModel.
//   import ExtensionAPI from '../../core/ExtensionAPI';               → ExtensionAPI.
//   import { ColorString, ECElement } from '../../util/types';        → ColorString(==String); ECElement deferred.
//   import SeriesData from '../../data/SeriesData';                   → SeriesData.
//   import Sausage from '../../util/shape/sausage';
//     → `SausagePath` / `SausageShape` (sibling Sausage.swift — location deviation from
//       util/shape/sausage.ts: co-located with its gauge consumer rather than under util/shape; also
//       consumed by chart/bar/BarView.swift's polar roundCap branch). The `roundCap ? Sausage : Sector`
//       selection is wired at both sites here (axisLine bands, progress arcs).
//   import {createSymbol} from '../../util/symbol';                   → `symbol.createSymbol`.
//   import ZRImage from 'zrender/src/graphic/Image';
//     → PORT-NOTE (deferred): ZRImage IS ported (ZRenderKit Graphic/Image.swift); only the
//       `pointer instanceof ZRImage` styling branch (image:// pointer icon) is deferred.
//   import { extend, isFunction, isString, isNumber, each } from 'zrender/src/core/util';
//     → `util.*` (ZRenderKit). `isString`/`isFunction`/`isNumber` used via the local helpers below.
//   import {setCommonECData} from '../../util/innerStore';
//     → `innerStore.setCommonECData` (ported).
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
            //   upstream `(value: number) => string`. A function formatter is stored in the option bag as
            //   a Swift closure (cf. the VisualMapModel `(Double, Double) -> String` / GeoModel
            //   `([String: Any]) -> String` formatter-callback seams); invoke it with the numeric value.
            if let fn = labelFormatter as? (Double) -> String {
                label = fn(value ?? Double.nan)
            }
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

    // PORT-NOTE (reuse machinery — NOT in upstream 1:1): upstream rebuilds the static parts
    //   (axisLine sectors + ticks/splitLines/labels) from scratch on every render after a
    //   `this.group.removeAll()`. That is fine for echarts.js (those parts carry no animation), but
    //   here it (a) destroyed the pointer/progress element identities on every `setOption` refresh so
    //   they replayed the enter animation from `startAngle` instead of TWEENING (the reset-on-update
    //   bug), and (b) churned every element identity so nothing could be diffed/tweened. This port
    //   therefore REUSES elements across renders: the static geometry lives in a retained sub-group
    //   rebuilt only when its configuration signature changes; the pointer/progress/title/detail are
    //   retained and `updateProps`-tweened (see _renderPointer / _renderTitleAndDetail below).
    private var _staticGroup: Group?
    private var _staticSig: String?
    private var _anchorEl: Path?
    private var _contentGroup: Group?

    // upstream: render(seriesModel: GaugeSeriesModel, ecModel: GlobalModel, api: ExtensionAPI)
    open override func render(
        _ seriesModelBase: SeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        // upstream typed `seriesModel: GaugeSeriesModel`; the base override is typed `SeriesModel`.
        let seriesModel = seriesModelBase as! GaugeSeriesModel

        // PORT DEVIATION (reuse): upstream calls `this.group.removeAll()` here and rebuilds every element.
        //   We do NOT wipe the group — the sub-renders below reuse the retained pointer/progress/title/
        //   detail (so they tween instead of replaying the enter animation) and the retained static
        //   sub-group. See the `_staticGroup` field note above.

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
        //   roundCap → the round-capped `SausagePath` (ported alongside GaugeView); else `Sector`.

        let showAxis = jsTruthy(axisLineModel.get("show"))
        let lineStyleModel = axisLineModel.getModel("lineStyle")
        let axisLineWidth = gaugeNum(lineStyleModel.get("width")) ?? 0

        // const angles = [startAngle, endAngle]; normalizeArcAngles(angles, !clockwise);
        var angles = [startAngle, endAngle]
        normalizeArcAngles(&angles, !clockwise)
        startAngle = angles[0]
        endAngle = angles[1]
        let angleRangeSpan = endAngle - startAngle

        // PORT-NOTE (faithful, non-obvious upstream behaviour): the axisLine loop below REASSIGNS the
        //   OUTER `endAngle` on every iteration (`endAngle = startAngle + angleRangeSpan * percent;`,
        //   GaugeView.ts:134), so after the loop `endAngle` holds the LAST color stop's angle — and that
        //   mutated value is what upstream hands to `_renderTicks` (TS:184) and `_renderPointer` (TS:195).
        //   With the default `axisLine.lineStyle.color` (last stop == 1) it equals the full-range end, but
        //   for e.g. `[[0.3,'#f00'],[0.7,'#0f0']]` the ticks/splitLines/labels and the pointer extent span
        //   only up to 0.7 of the arc. The loop is skipped entirely when `!showAxis` or the color list is
        //   empty, in which case upstream leaves `endAngle` at the full-range value.
        //   The mutation is hoisted here because the loop lives inside the static-reuse cache block below
        //   (NOT in upstream) while `_renderPointer` runs on every render; the result depends only on
        //   `showAxis` / `colorList`, never on the cache state, so hoisting is value-identical.
        if showAxis, let lastStop = colorList.last {
            endAngle = startAngle + angleRangeSpan * Swift.min(Swift.max(lastStop.0, 0), 1)
        }

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

        // ---- Static parts (axisLine sectors + ticks/splitLines/labels): built once into a retained
        //   sub-group and REUSED across renders. Rebuilt only when the static configuration changes
        //   (first render, resize, or a non-data `setOption`). The value-only refreshes that drive the
        //   gauge demos leave this untouched, so these element identities persist. ----
        let sig = self.staticSignature(seriesModel, api)
        let staticChanged = (self._staticGroup == nil) || (sig != self._staticSig)
        if staticChanged {
            let staticGroup: Group
            if let existing = self._staticGroup {
                // Reuse the same sub-group object (keep it as the group's first child) — only its
                //   children are rebuilt.
                _ = existing.removeAll()
                staticGroup = existing
            } else {
                staticGroup = Group()
                self._staticGroup = staticGroup
                // First render: the static sub-group is the FIRST child of the view group, so its
                //   descendants keep their (z, z2, insertion) paint order ahead of the dynamic
                //   title/detail/anchor/pointer/progress added by the sub-renders below.
                _ = group.add(staticGroup)
            }

            var prevEndAngle = startAngle

            // const sectors: (Sausage | graphic.Sector)[] = [];
            var sectors: [Path] = []
            // for (let i = 0; showAxis && i < colorList.length; i++)
            var i = 0
            while showAxis && i < colorList.count {
                // Clamp
                let percent = Swift.min(Swift.max(colorList[i].0, 0), 1)
                // upstream: `endAngle = startAngle + angleRangeSpan * percent;` — the outer `endAngle` is
                //   mutated here; its post-loop value is pre-computed above (see the PORT-NOTE), so this
                //   loop keeps a local alias with the identical per-iteration value.
                let sectorEnd = startAngle + angleRangeSpan * percent
                // new MainPath({ shape: {...}, silent: true }) — MainPath is Sausage (roundCap) or Sector.
                let sector: Path
                if roundCap {
                    var sausageShape = SausageShape()
                    sausageShape.startAngle = prevEndAngle
                    sausageShape.endAngle = sectorEnd
                    sausageShape.cx = posInfo.cx
                    sausageShape.cy = posInfo.cy
                    sausageShape.clockwise = clockwise
                    sausageShape.r0 = posInfo.r - axisLineWidth
                    sausageShape.r = posInfo.r
                    sector = SausagePath([
                        "shape": sausageShape as PathShape,
                        "silent": true
                    ])
                }
                else {
                    var sectorShape = SectorShape()
                    sectorShape.startAngle = prevEndAngle
                    sectorShape.endAngle = sectorEnd
                    sectorShape.cx = posInfo.cx
                    sectorShape.cy = posInfo.cy
                    sectorShape.clockwise = clockwise
                    sectorShape.r0 = posInfo.r - axisLineWidth
                    sectorShape.r = posInfo.r
                    sector = Sector([
                        "shape": sectorShape as PathShape,
                        "silent": true
                    ])
                }

                // sector.setStyle({ fill: colorList[i][1] });
                // sector.setStyle(lineStyleModel.getLineStyle(['color', 'width']));  (color/width excluded — arc
                //   is simulated by a sector so the stroke props are useless). The fill (set first) survives.
                var style = pathStyleFromDict(lineStyleModel.getLineStyle(["color", "width"]))
                style.fill = .string(colorList[i].1)
                sector.useStyle(style)

                sectors.append(sector)

                prevEndAngle = sectorEnd
                i += 1
            }

            // sectors.reverse(); each(sectors, sector => group.add(sector));
            sectors.reverse()
            util.each(sectors, { sector, _ in _ = staticGroup.add(sector) })

            self._renderTicks(
                staticGroup, seriesModel, ecModel, api, getColor, posInfo,
                startAngle, endAngle, clockwise, axisLineWidth
            )

            self._staticSig = sig
        }

        self._renderTitleAndDetail(
            seriesModel, ecModel, api, getColor, posInfo
        )

        self._renderAnchor(seriesModel, posInfo, staticChanged)

        self._renderPointer(
            seriesModel, ecModel, api, getColor, posInfo,
            startAngle, endAngle, clockwise, axisLineWidth
        )
    }

    // PORT-NOTE (reuse machinery — NOT in upstream): a cheap change-detector for the STATIC parts. The
    //   gauge demos refresh with a MERGE `setOption` that supplies only `series[].data`; the static
    //   geometry (axisLine/ticks/splitLines/labels) reads everything EXCEPT the data values, so a
    //   signature over the series option minus `data` (plus the canvas size, which feeds posInfo) is
    //   stable across those refreshes and changes exactly when the static geometry would.
    private func staticSignature(_ seriesModel: GaugeSeriesModel, _ api: ExtensionAPI) -> String {
        var out = "\(api.getWidth())x\(api.getHeight())|"
        if var opt = seriesModel.option as? [String: Any] {
            // The static geometry depends on neither the data VALUES nor the ANIMATION settings, so
            //   strip both: the gauge demos refresh by merging `series[].data` (always) and sometimes an
            //   `animation` toggle (the clock suppresses the wrap-around tween). Keeping either in the
            //   signature would force a needless static rebuild on those refreshes.
            for k in Self.staticSigIgnoredKeys { opt[k] = nil }
            out += Self.stableDescribe(opt)
        }
        return out
    }

    private static let staticSigIgnoredKeys: [String] = [
        "data",
        "animation", "animationThreshold",
        "animationDuration", "animationEasing", "animationDelay",
        "animationDurationUpdate", "animationEasingUpdate", "animationDelayUpdate",
        "animationType", "animationTypeUpdate"
    ]

    /// Deterministic string for a JSON-like option value (dictionaries emitted with sorted keys) so the
    ///   same configuration always yields the same signature. Closures / opaque values fall back to a
    ///   type marker (they never appear in the gauge demos' options).
    private static func stableDescribe(_ v: Any?) -> String {
        switch v {
        case nil, is NSNull:
            return "null"
        case let d as [String: Any]:
            let body = d.keys.sorted().map { "\($0):\(stableDescribe(d[$0]!))" }.joined(separator: ",")
            return "{\(body)}"
        case let a as [Any]:
            return "[\(a.map { stableDescribe($0) }.joined(separator: ","))]"
        case let b as Bool:
            return b ? "true" : "false"
        case let n as NSNumber:
            return n.stringValue
        case let s as String:
            return "\"\(s)\""
        case let i as Int:
            return String(i)
        case let dd as Double:
            return String(dd)
        default:
            return "<\(String(describing: Swift.type(of: v!)))>"
        }
    }

    // upstream: _renderTicks(seriesModel, ecModel, api, getColor, posInfo, startAngle, endAngle, clockwise, axisLineWidth)
    //   PORT-NOTE (reuse): takes the target `group` explicitly — the ticks/splitLines/labels are built
    //   into the retained static sub-group, not directly into `self.group` (see _renderMain).
    private func _renderTicks(
        _ group: Group,
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

                if rotate == 0 {
                    var ts = gaugeTextStyle(labelModel, text: label, inheritColor: autoColor,
                        align: unitX < -0.4 ? .left : (unitX > 0.4 ? .right : .center),
                        verticalAlign: unitY < -0.8 ? .top : (unitY > 0.8 ? .bottom : .middle))
                    ts.x = textStyleX
                    ts.y = textStyleY
                    let textEl = ZRText(["silent": true])
                    textEl.useStyle(ts)
                    _ = group.add(textEl)
                }
                else {
                    var ts = gaugeTextStyle(labelModel, text: label, inheritColor: autoColor,
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
        // const oldData = this._data; const oldProgressData = this._progressEls;
        let oldData = self._data
        let oldProgressData = self._progressEls

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
        func createProgress(_ idx: Int, _ endAngle: Double) -> Path {
            let roundCap = jsTruthy(progressModel.get("roundCap"))
            // const ProgressPath = roundCap ? Sausage : graphic.Sector;
            //   roundCap → the round-capped `SausagePath`; else `Sector`.

            let isOverlap = jsTruthy(progressModel.get("overlap"))
            let progressWidth = isOverlap ? (gaugeNum(progressModel.get("width")) ?? 0) : axisLineWidth / Double(data.count())
            let r0 = isOverlap ? posInfo.r - progressWidth : posInfo.r - Double(idx + 1) * progressWidth
            let r = isOverlap ? posInfo.r : posInfo.r - Double(idx) * progressWidth
            let progress: Path
            if roundCap {
                var shape = SausageShape()
                shape.startAngle = startAngle
                shape.endAngle = endAngle
                shape.cx = posInfo.cx
                shape.cy = posInfo.cy
                shape.clockwise = clockwise
                shape.r0 = r0
                shape.r = r
                progress = SausagePath(["shape": shape as PathShape])
            }
            else {
                var shape = SectorShape()
                shape.startAngle = startAngle
                shape.endAngle = endAngle
                shape.cx = posInfo.cx
                shape.cy = posInfo.cy
                shape.clockwise = clockwise
                shape.r0 = r0
                shape.r = r
                progress = Sector(["shape": shape as PathShape])
            }
            if isOverlap {
                progress.z2 = number.linearMap(asDouble(data.get(valueDim!, idx)), [minVal, maxVal], [100, 0], true)
            }
            return progress
        }

        // upstream: data.diff(oldData).add(...).update(...).execute();
        //   ADD (first appearance): create the pointer collapsed at startAngle + `initProps` its rotation
        //     to the value angle (the enter sweep); create the progress arc at endAngle == startAngle +
        //     `initProps` its shape.endAngle to the value angle.
        //   UPDATE (refresh): REUSE the retained pointer/progress element (PORT DEVIATION — upstream
        //     recreates a fresh element pre-seeded at the previous rotation/endAngle, but here the group
        //     is not wiped, so reusing the SAME object both avoids a duplicate AND preserves its
        //     identity). `updateProps` then TWEENS from its CURRENT (mid-animation) rotation/endAngle to
        //     the new value angle — this is the fix for the reset-on-update bug.
        if showProgress || showPointer {
            data.diff(oldData)
                .add { idx in
                    let val = asDouble(data.get(valueDim!, idx))
                    if showPointer {
                        let finalAngle = val.isNaN ? angleExtent[0] : number.linearMap(val, valueExtent, angleExtent, true)
                        let pointer = createPointer(idx, startAngle)
                        initProps(pointer, ["rotation": -(finalAngle + Double.pi / 2)], seriesModel)
                        _ = group.add(pointer)
                        data.setItemGraphicEl(idx, pointer)
                    }
                    if showProgress {
                        let isClip = jsTruthy(progressModel.get("clip"))
                        let valueEndAngle = number.linearMap(val, valueExtent, angleExtent, isClip)
                        let progress = createProgress(idx, startAngle)
                        initProps(progress, ["shape": ["endAngle": valueEndAngle]], seriesModel)
                        _ = group.add(progress)
                        innerStore.setCommonECData(seriesModel.seriesIndex, data.dataType ?? .main, Double(idx), progress)
                        progressList[idx] = progress
                    }
                }
                .update { newIdx, oldIdx in
                    let val = asDouble(data.get(valueDim!, newIdx))
                    if showPointer {
                        // Reuse the retained pointer (already a child of `group`); if for any reason it is
                        //   missing, fall back to a fresh one collapsed at startAngle.
                        let pointer = (oldData?.getItemGraphicEl(oldIdx) as? Path) ?? {
                            let p = createPointer(newIdx, startAngle)
                            _ = group.add(p)
                            return p
                        }()
                        let finalAngle = val.isNaN ? angleExtent[0] : number.linearMap(val, valueExtent, angleExtent, true)
                        updateProps(pointer, ["rotation": -(finalAngle + Double.pi / 2)], seriesModel)
                        data.setItemGraphicEl(newIdx, pointer)
                    }
                    if showProgress {
                        let previousProgress = (oldIdx < oldProgressData.count) ? oldProgressData[oldIdx] : nil
                        let progress = previousProgress ?? {
                            let p = createProgress(newIdx, startAngle)
                            _ = group.add(p)
                            return p
                        }()
                        let isClip = jsTruthy(progressModel.get("clip"))
                        let valueEndAngle = number.linearMap(val, valueExtent, angleExtent, isClip)
                        updateProps(progress, ["shape": ["endAngle": valueEndAngle]], seriesModel)
                        innerStore.setCommonECData(seriesModel.seriesIndex, data.dataType ?? .main, Double(newIdx), progress)
                        progressList[newIdx] = progress
                    }
                }
                .remove { oldIdx in
                    // Data shrank: drop the now-orphaned pointer/progress (upstream relies on removeAll;
                    //   here we must remove them explicitly since the group is not wiped).
                    if showPointer, let p = oldData?.getItemGraphicEl(oldIdx) { _ = group.remove(p) }
                    if showProgress, oldIdx < oldProgressData.count, let p = oldProgressData[oldIdx] { _ = group.remove(p) }
                }
                .execute()

            // upstream: data.each(function (idx) { ... styling + emphasis/states ... })
            for idx in 0..<data.count() {
                let itemModel = data.getItemModel(idx)
                // upstream (GaugeView.ts:529-532): the per-item emphasis params feeding the
                //   pointer/progress hover wiring below.
                let emphasisModel = itemModel.getModel(["emphasis"])
                let focus: InnerFocus? = emphasisModel.get("focus")
                let blurScope = (emphasisModel.get("blurScope") as? String).flatMap { BlurScope(rawValue: $0) }
                let emphasisDisabled = (emphasisModel.get("disabled") as? Bool) ?? false
                let autoColor = getColor(number.linearMap(asDouble(data.get(valueDim!, idx)), valueExtent, [0, 1], true))
                if showPointer {
                    let pointer = data.getItemGraphicEl(idx) as? Path
                    let symbolStyle = data.getItemVisual(idx, "style")
                    let visualColor = gaugeVisualFill(symbolStyle)
                    // PORT-NOTE (deferred): the `pointer instanceof ZRImage` branch (image:// icon) is deferred.
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
                    // upstream (GaugeView.ts:558-560): the pointer's hover wiring. `z2EmphasisLift = 0`
                    //   suppresses the default z2 bump (the visible effect is the emphasis itemStyle /
                    //   default fill lift).
                    if let pointer = pointer {
                        states.getHighDownInner(pointer).z2EmphasisLift = 0
                        states.setStatesStylesFromModel(pointer, itemModel)
                        states.toggleHoverEmphasis(pointer, focus, blurScope, emphasisDisabled)
                    }
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
                    // upstream (GaugeView.ts:570-572): the progress arc's hover wiring.
                    if let progress = progress {
                        states.getHighDownInner(progress).z2EmphasisLift = 0
                        states.setStatesStylesFromModel(progress, itemModel)
                        states.toggleHoverEmphasis(progress, focus, blurScope, emphasisDisabled)
                    }
                }
            }

            self._progressEls = progressList
        }
    }

    // upstream: _renderAnchor(seriesModel, posInfo)
    //   PORT-NOTE (reuse): the anchor is static (its geometry depends only on the configuration, not on
    //   the data value), so it is retained and rebuilt only when the static signature changed this
    //   render. `staticChanged` is threaded in from _renderMain.
    private func _renderAnchor(
        _ seriesModel: GaugeSeriesModel,
        _ posInfo: PosInfo,
        _ staticChanged: Bool
    ) {
        // Nothing to do on a value-only refresh — the retained anchor is reused untouched.
        if !staticChanged {
            return
        }
        // Drop any previous anchor before (re)building.
        if let old = self._anchorEl {
            _ = self.group.remove(old)
            self._anchorEl = nil
        }
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
            self._anchorEl = anchor
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

        // PORT-NOTE (reuse): upstream builds a fresh contentGroup each render (added to the just-wiped
        //   view group). Here the view group is NOT wiped, so the contentGroup is retained (identity
        //   persists) and only its per-datum item-groups are rebuilt.
        let contentGroup: Group
        if let cg = self._contentGroup {
            _ = cg.removeAll()
            contentGroup = cg
        } else {
            contentGroup = Group()
            self._contentGroup = contentGroup
            _ = self.group.add(contentGroup)
        }

        let oldData = self._data
        let oldTitleEls = self._titleEls
        let oldDetailEls = self._detailEls
        var newTitleEls = [ZRText?](repeating: nil, count: data.count())
        var newDetailEls = [ZRText?](repeating: nil, count: data.count())
        // const hasAnimation = seriesModel.isAnimationEnabled();
        //   Gates animateLabelValue (the detail number roll-up) in the per-datum loop below.
        let hasAnimation = seriesModel.isAnimationEnabled()

        let showPointerAbove = jsTruthy(seriesModel.get(["pointer", "showAbove"]))

        // upstream: data.diff(this._data).add(reuse-new).update(reuse-old).execute() — decides only the
        //   ELEMENT IDENTITY per datum (create fresh vs. reuse the previous title/detail Text); the
        //   styling below runs for every datum regardless.
        data.diff(oldData)
            .add { idx in
                newTitleEls[idx] = ZRText(["silent": true])
                newDetailEls[idx] = ZRText(["silent": true])
            }
            .update { newIdx, oldIdx in
                newTitleEls[newIdx] = (oldIdx < oldTitleEls.count) ? oldTitleEls[oldIdx] : ZRText(["silent": true])
                newDetailEls[newIdx] = (oldIdx < oldDetailEls.count) ? oldDetailEls[oldIdx] : ZRText(["silent": true])
            }
            .execute()
        // Any index not touched by the diff (defensive) gets a fresh element.
        for idx in 0..<data.count() {
            if newTitleEls[idx] == nil { newTitleEls[idx] = ZRText(["silent": true]) }
            if newDetailEls[idx] == nil { newDetailEls[idx] = ZRText(["silent": true]) }
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
                let labelEl = newTitleEls[idx]!
                labelEl.z2 = showPointerAbove ? 0 : 2
                var ts = gaugeTextStyle(itemTitleModel,
                    text: data.getName(idx),
                    inheritColor: autoColor,
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
                let labelEl = newDetailEls[idx]!
                let formatter = itemDetailModel.get("formatter")
                labelEl.z2 = showPointerAbove ? 0 : 2
                var ts = gaugeTextStyle(itemDetailModel,
                    text: formatLabel(value, formatter),
                    inheritColor: detailColor,
                    align: .center, verticalAlign: .middle)
                ts.x = detailX
                ts.y = detailY
                // width: isNaN(width) ? null : width, height: isNaN(height) ? null : height
                ts.width = width.isNaN ? nil : width
                ts.height = height.isNaN ? nil : height
                labelEl.useStyle(ts)

                // setLabelValueAnimation / animateLabelValue (detail number roll-up) — ported
                //   (label/labelStyle.swift:819 / :858) and now wired. `setLabelValueAnimation` snapshots
                //   the new value + a default-text getter on the label; `animateLabelValue` then TWEENS the
                //   displayed number from the previous value to the target (gated on the detail's
                //   `valueAnimation` option, default false, and on the series animation being enabled).
                labelStyle.setLabelValueAnimation(
                    labelEl,
                    [.normal: itemDetailModel],
                    value,
                    { v in formatLabel(asDouble(v), formatter) }
                )
                if hasAnimation == true {
                    // upstream passes a bespoke labelFetcher whose getFormattedLabel returns
                    //   `formatLabel(interpolatedValue ?? value, formatter)`; that is exactly the
                    //   default-text getter snapshotted above, so passing `nil` here routes `during`
                    //   through that same getter (getLabelText falls back to opt.defaultText).
                    labelStyle.animateLabelValue(labelEl, Double(idx), data, seriesModel, nil)
                }

                _ = itemGroup.add(labelEl)
            }

            _ = contentGroup.add(itemGroup)
        }
        // contentGroup is retained (added to the view group once, on first render).

        self._titleEls = newTitleEls.map { $0! }
        self._detailEls = newDetailEls.map { $0! }
    }

}

// export default GaugeView;  -> `open class GaugeView` above.


// ============================================================================
// PORT-NOTE: local helpers — NOT part of GaugeView.ts upstream. These reproduce the dynamic-option coercion,
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
/// keep their shortest decimal form. PORT-NOTE: not a full ECMAScript Number→String (no exponent form).
private func jsNumberToString(_ v: Double) -> String {
    if v.isNaN { return "NaN" }
    if v == v.rounded() && Swift.abs(v) < 1e15 {
        return String(Int(v))
    }
    return String(v)
}

/// Parse the `axisLine.lineStyle.color` color-stop list (`[[percent, color], ...]`) into `[(Double, String)]`.
///   `percent` may be a bare Int literal (`1`) → coerced via gaugeNum; `color` is a solid string (or a
///   ZRColor.color). PORT-NOTE (deferred): gradient/pattern color values are not modeled (solid strings only).
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

/// Thin adapter over the ported `label/labelStyle.createTextStyle(textStyleModel, specifiedTextStyle,
///   {inheritColor})` (labelStyle.swift:416). Upstream builds every gauge title/detail/axisLabel text via
///   `createTextStyle`, so this now delegates to it — restoring textBorder/shadow/rich styling that the
///   former minimal (font/fill/align-only) stand-in dropped. The caller sets x/y (and width/height for the
///   detail) on the returned struct, matching how those fields flow through upstream's specifiedTextStyle.
///   `inheritColor` is upstream's `{ inheritColor }` opt (the segment auto-color / detail visual fill);
///   `createTextStyle` resolves the final fill from the model's `color` (falling back to inheritColor).
private func gaugeTextStyle(
    _ textStyleModel: Model,
    text: String?,
    inheritColor: String?,
    align: TextAlign?,
    verticalAlign: TextVerticalAlign?
) -> TextStyleProps {
    var specified = TextStyleProps()
    specified.text = text
    specified.align = align
    specified.verticalAlign = verticalAlign
    return labelStyle.createTextStyle(
        textStyleModel, specified, TextCommonParams(inheritColor: inheritColor)
    )
}

/// PORT-NOTE: `util/graphic` style-bag bridge for LINE styles (splitline/tick). `Model.getLineStyle()`
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
    // PORT-NOTE (deferred): `fill`/`stroke` may be a gradient/pattern object; only the String form (incl. 'none'/'auto')
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
