// Ported from echarts/src/component/timeline/{TimelineView.ts, SliderTimelineView.ts}
//   — keep in sync with upstream.
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

// upstream imports (mapped to this port; interaction-only imports are DEFERRED — see notes below):
//   import BoundingRect from 'zrender/src/core/BoundingRect';        -> `BoundingRect`.
//   import * as matrix from 'zrender/src/core/matrix';               -> `matrix.*`.
//   import * as graphic from '../../util/graphic';                   -> ZRenderKit scene types + local helpers.
//   import { createTextStyle } from '../../label/labelStyle';        -> `labelStyle.createTextStyle`.
//   import * as layout from '../../util/layout';                     -> `layout.*` (util/layout.swift).
//   import TimelineAxis from './TimelineAxis';                       -> `TimelineAxis` (this component).
//   import {createSymbol, normalizeSymbolOffset, normalizeSymbolSize} from '../../util/symbol';
//       -> `symbol.createSymbol` / `symbol.normalizeSymbolOffset` / `symbol.normalizeSymbolSize`.
//   import * as numberUtil from '../../util/number';                 -> `number.*`.
//   import { merge, each, extend, defaults, retrieve2 } from 'zrender/src/core/util'; -> `util.*`.
//   import { createScaleByModel } from '../../coord/axisHelper';     -> `axisHelper.createScaleByModel`.
//   import { scaleCalcNiceDirectly } from '../../coord/axisNiceTicks'; -> `scaleCalcNiceDirectly`.
//   The hover/tooltip/drag/play imports (enableHoverEmphasis, getECData, createTooltipMarkup,
//     makeInner) drive INTERACTION and are DEFERRED (static render only, task scope; cf. TitleView).

// upstream: class TimelineView extends ComponentView { static type = 'timeline'; }
//   The thin base — SliderTimelineView extends it. (CONVENTIONS §2: `open class`.)
open class TimelineView: ComponentView {
    // static type = 'timeline'; type = TimelineView.type;
    public class var type: String { return "timeline" }
}

// The per-render layout result (upstream `interface LayoutInfo`).
private struct LayoutInfo {
    var viewRect: BoundingRect
    var mainLength: Double
    var orient: String

    var rotation: Double
    var labelRotation: Double
    // number | '+' | '-'  → a Double when numeric, else the "+"/"-" string.
    var labelPosOpt: Any?
    var labelAlign: String
    var labelBaseline: String

    var playPosition: [Double]?
    var prevBtnPosition: [Double]?
    var nextBtnPosition: [Double]?
    var axisExtent: [Double]

    var controlSize: Double
    var controlGap: Double
}

// upstream: class SliderTimelineView extends TimelineView
//   Not further subclassed → `final class` (CONVENTIONS §2).
public final class SliderTimelineView: TimelineView {

    // static type = 'timeline.slider'; type = SliderTimelineView.type;
    public override class var type: String { return "timeline.slider" }

    // Exposed for tests (upstream `private`): the built axis + current-index pointer + progress line.
    public private(set) var _axis: TimelineAxis!
    public private(set) var _mainGroup: Group!
    public private(set) var _labelGroup: Group!
    public private(set) var _currentPointer: Path?
    public private(set) var _progressLine: Line?
    public private(set) var _tickSymbols: [Path] = []
    public private(set) var _tickLabels: [ZRText] = []

    // init(ecModel, api) { this.api = api; } — `api` is passed to render directly here; nothing to cache.
    public override func `init`(_ ecModel: GlobalModel, _ api: ExtensionAPI) {}

    /**
     * @override
     */
    // render(timelineModel, ecModel, api)
    public override func render(
        _ model: ComponentModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        guard let timelineModel = model as? SliderTimelineModel else { return }

        // this.group.removeAll();
        _ = self.group.removeAll()
        self._tickSymbols = []
        self._tickLabels = []
        self._currentPointer = nil
        self._progressLine = nil

        // if (timelineModel.get('show', true)) { ... }
        if timelineModel.get("show", true) as? Bool ?? true {

            let layoutInfo = self._layout(timelineModel, api)
            let mainGroup = self._createGroup(true)   // '_mainGroup'
            let labelGroup = self._createGroup(false)  // '_labelGroup'

            let axis = self._createAxis(layoutInfo, timelineModel)
            self._axis = axis

            // timelineModel.formatTooltip = ...  — DEFERRED (tooltip CONTENT; task: static render).

            // each(['AxisLine', 'AxisTick', 'Control', 'CurrentPointer'], name => this['_render'+name](...));
            self._renderAxisLine(layoutInfo, mainGroup, axis, timelineModel)
            self._renderAxisTick(layoutInfo, mainGroup, axis, timelineModel)
            self._renderControl(layoutInfo, mainGroup, axis, timelineModel)
            self._renderCurrentPointer(layoutInfo, mainGroup, axis, timelineModel)

            self._renderAxisLabel(layoutInfo, labelGroup, axis, timelineModel)
            self._position(layoutInfo, timelineModel)
        }

        // this._doPlayStop();      — DEFERRED (auto-advance play timer; needs the live host).
        // this._updateTicksStatus(); — DEFERRED (progress/emphasis toggle states; needs states).
    }

    // ────────────────────────────── _layout ──────────────────────────────
    private func _layout(_ timelineModel: SliderTimelineModel, _ api: ExtensionAPI) -> LayoutInfo {
        // const labelPosOpt = timelineModel.get(['label', 'position']);
        let labelPosOpt = timelineModel.get(["label", "position"])
        // const orient = timelineModel.get('orient');
        let orient = (timelineModel.get("orient") as? String) ?? "horizontal"
        // const viewRect = getViewRect(timelineModel, api);
        let viewRect = getViewRect(timelineModel, api)

        // Auto label offset.  parsedLabelPos: number | '+' | '-'
        var parsedLabelPos: Any?
        if labelPosOpt == nil || (labelPosOpt as? String) == "auto" {
            parsedLabelPos = orient == "horizontal"
                ? ((viewRect.y + viewRect.height / 2) < api.getHeight() / 2 ? "-" : "+")
                : ((viewRect.x + viewRect.width / 2) < api.getWidth() / 2 ? "+" : "-")
        }
        else if let s = labelPosOpt as? String {
            // ({horizontal:{top:'-',bottom:'+'}, vertical:{left:'-',right:'+'}})[orient][labelPosOpt]
            let map: [String: [String: String]] = [
                "horizontal": ["top": "-", "bottom": "+"],
                "vertical": ["left": "-", "right": "+"]
            ]
            parsedLabelPos = map[orient]?[s]
        }
        else {
            // is number
            parsedLabelPos = tlReadDouble(labelPosOpt)
        }

        // parsedLabelPos >= 0 || parsedLabelPos === '+'
        func posIsPlus() -> Bool {
            if let d = parsedLabelPos as? Double { return d >= 0 }
            return (parsedLabelPos as? String) == "+"
        }

        // labelAlignMap / labelBaselineMap / rotationMap
        let labelAlignMap: [String: String] = [
            "horizontal": "center",
            "vertical": posIsPlus() ? "left" : "right"
        ]
        let labelBaselineMap: [String: String] = [
            "horizontal": posIsPlus() ? "top" : "bottom",
            "vertical": "middle"
        ]
        let rotationMap: [String: Double] = [
            "horizontal": 0,
            "vertical": Double.pi / 2
        ]

        // const mainLength = orient === 'vertical' ? viewRect.height : viewRect.width;
        let mainLength = orient == "vertical" ? viewRect.height : viewRect.width

        // const controlModel = timelineModel.getModel('controlStyle');
        let controlModel = timelineModel.getModel("controlStyle")
        // const showControl = controlModel.get('show', true);
        let showControl = controlModel.get("show", true) as? Bool ?? true
        // const controlSize = showControl ? controlModel.get('itemSize') : 0;
        let controlSize = showControl ? (tlReadDouble(controlModel.get("itemSize")) ?? 0) : 0
        // const controlGap = showControl ? controlModel.get('itemGap') : 0;
        let controlGap = showControl ? (tlReadDouble(controlModel.get("itemGap")) ?? 0) : 0
        let sizePlusGap = controlSize + controlGap

        // let labelRotation = timelineModel.get(['label', 'rotate']) || 0;  labelRotation *= PI/180;
        let labelRotation = (tlReadDouble(timelineModel.get(["label", "rotate"])) ?? 0) * Double.pi / 180

        var playPosition: [Double]?
        var prevBtnPosition: [Double]?
        var nextBtnPosition: [Double]?
        // const controlPosition = controlModel.get('position', true);
        let controlPosition = controlModel.get("position", true) as? String
        let showPlayBtn = showControl && (controlModel.get("showPlayBtn", true) as? Bool ?? true)
        let showPrevBtn = showControl && (controlModel.get("showPrevBtn", true) as? Bool ?? true)
        let showNextBtn = showControl && (controlModel.get("showNextBtn", true) as? Bool ?? true)
        var xLeft: Double = 0
        var xRight = mainLength

        // position[0] means left, position[1] means middle.
        if controlPosition == "left" || controlPosition == "bottom" {
            if showPlayBtn { playPosition = [0, 0]; xLeft += sizePlusGap }
            if showPrevBtn { prevBtnPosition = [xLeft, 0]; xLeft += sizePlusGap }
            if showNextBtn { nextBtnPosition = [xRight - controlSize, 0]; xRight -= sizePlusGap }
        }
        else { // 'top' 'right'
            if showPlayBtn { playPosition = [xRight - controlSize, 0]; xRight -= sizePlusGap }
            if showPrevBtn { prevBtnPosition = [0, 0]; xLeft += sizePlusGap }
            if showNextBtn { nextBtnPosition = [xRight - controlSize, 0]; xRight -= sizePlusGap }
        }
        var axisExtent = [xLeft, xRight]

        // if (timelineModel.get('inverse')) { axisExtent.reverse(); }
        if tlTruthy(timelineModel.get("inverse")) {
            axisExtent.reverse()
        }

        // labelAlign / labelBaseline honor explicit label.align / label.verticalAlign / label.baseline.
        let labelAlign = (timelineModel.get(["label", "align"]) as? String) ?? (labelAlignMap[orient] ?? "center")
        let labelBaseline = (timelineModel.get(["label", "verticalAlign"]) as? String)
            ?? (timelineModel.get(["label", "baseline"]) as? String)
            ?? (labelBaselineMap[orient] ?? "top")

        return LayoutInfo(
            viewRect: viewRect,
            mainLength: mainLength,
            orient: orient,
            rotation: rotationMap[orient] ?? 0,
            labelRotation: labelRotation,
            labelPosOpt: parsedLabelPos,
            labelAlign: labelAlign,
            labelBaseline: labelBaseline,
            playPosition: playPosition,
            prevBtnPosition: prevBtnPosition,
            nextBtnPosition: nextBtnPosition,
            axisExtent: axisExtent,
            controlSize: controlSize,
            controlGap: controlGap
        )
    }

    // ────────────────────────────── _position ──────────────────────────────
    private func _position(_ layoutInfo: LayoutInfo, _ timelineModel: SliderTimelineModel) {
        // Position is called finally, because bounding rect is needed to adapt content to fill viewRect.
        let mainGroup = self._mainGroup!
        let labelGroup = self._labelGroup!

        var viewRect = layoutInfo.viewRect
        if layoutInfo.orient == "vertical" {
            // transform to horizontal, inverse rotate by left-top point.
            var m = matrix.create()
            let rotateOriginX = viewRect.x
            let rotateOriginY = viewRect.y + viewRect.height
            m = matrix.translate(m, [-rotateOriginX, -rotateOriginY])
            m = matrix.rotate(m, -Double.pi / 2)
            m = matrix.translate(m, [rotateOriginX, rotateOriginY])
            viewRect = viewRect.clone()
            viewRect.applyTransform(m)
        }

        // [[xmin, xmax], [ymin, ymax]]
        func getBound(_ rect: RectLike) -> [[Double]] {
            return [
                [rect.x, rect.x + rect.width],
                [rect.y, rect.y + rect.height]
            ]
        }

        let viewBound = getBound(viewRect)
        let mainBound = getBound(mainGroup.getBoundingRect(nil))
        let labelBound = getBound(labelGroup.getBoundingRect(nil))

        var mainPosition = [mainGroup.x, mainGroup.y]
        var labelsPosition = [labelGroup.x, labelGroup.y]

        labelsPosition[0] = viewBound[0][0]
        mainPosition[0] = viewBound[0][0]

        // fromPos[dimIdx] += to[dimIdx][boundIdx] - from[dimIdx][boundIdx];
        func toBound(_ fromPos: inout [Double], _ from: [[Double]], _ to: [[Double]], _ dimIdx: Int, _ boundIdx: Int) {
            fromPos[dimIdx] += to[dimIdx][boundIdx] - from[dimIdx][boundIdx]
        }

        let labelPosOpt = layoutInfo.labelPosOpt
        if labelPosOpt == nil || (labelPosOpt is String) { // '+' or '-'
            let mainBoundIdx = (labelPosOpt as? String) == "+" ? 0 : 1
            toBound(&mainPosition, mainBound, viewBound, 1, mainBoundIdx)
            toBound(&labelsPosition, labelBound, viewBound, 1, 1 - mainBoundIdx)
        }
        else {
            let num = (labelPosOpt as? Double) ?? 0
            let mainBoundIdx = num >= 0 ? 0 : 1
            toBound(&mainPosition, mainBound, viewBound, 1, mainBoundIdx)
            labelsPosition[1] = mainPosition[1] + num
        }

        mainGroup.setPosition(mainPosition)
        labelGroup.setPosition(labelsPosition)
        mainGroup.rotation = layoutInfo.rotation
        labelGroup.rotation = layoutInfo.rotation

        func setOrigin(_ targetGroup: Group) {
            targetGroup.originX = viewBound[0][0] - targetGroup.x
            targetGroup.originY = viewBound[1][0] - targetGroup.y
        }
        setOrigin(mainGroup)
        setOrigin(labelGroup)
    }

    // ────────────────────────────── _createAxis ──────────────────────────────
    private func _createAxis(_ layoutInfo: LayoutInfo, _ timelineModel: SliderTimelineModel) -> TimelineAxis {
        let data = timelineModel.getData()
        // let axisType = timelineModel.get('axisType') || timelineModel.get('type');
        var axisType = (timelineModel.get("axisType") as? String) ?? (timelineModel.get("type") as? String)
        // if (axisType !== 'category' && axisType !== 'time') { axisType = 'value'; }
        if axisType != "category" && axisType != "time" {
            axisType = "value"
        }

        // const scale = createScaleByModel(timelineModel, axisType, false);
        let scale = axisHelper.createScaleByModel(timelineModel, axisType!, false)

        // Customize scale. The `tickValue` is `dataIndex`. (PORT: via `getTicksOverride`, see Scale.swift.)
        //   upstream: `return data.mapArray(['value'], value => ({value}));`
        scale.getTicksOverride = { _ in
            var ticks: [ScaleTick] = []
            _ = data.mapArray(["value"]) { args in
                ticks.append(ScaleTick(value: tlReadDouble(args.first ?? nil) ?? 0))
                return nil
            }
            return ticks
        }

        // const dataExtent = data.getDataExtent('value');
        let dataExtent = data.getDataExtent("value")
        // scale.setExtent(dataExtent[0], dataExtent[1]);
        scale.setExtent(dataExtent[0], dataExtent[1])
        // scaleCalcNiceDirectly(scale, {fixMinMax: [true, true]});
        scaleCalcNiceDirectly(scale, ScaleCalcNiceMethodOpt(fixMinMax: [true, true]))

        // const axis = new TimelineAxis('value', scale, layoutInfo.axisExtent, axisType);
        let axis = TimelineAxis("value", scale, layoutInfo.axisExtent, axisType)
        // axis.model = timelineModel;
        axis.timelineModel = timelineModel

        return axis
    }

    // ────────────────────────────── _createGroup ──────────────────────────────
    private func _createGroup(_ isMain: Bool) -> Group {
        let newGroup = Group()
        if isMain { self._mainGroup = newGroup }
        else { self._labelGroup = newGroup }
        _ = self.group.add(newGroup)
        return newGroup
    }

    // ────────────────────────────── _renderAxisLine ──────────────────────────────
    private func _renderAxisLine(
        _ layoutInfo: LayoutInfo, _ group: Group, _ axis: TimelineAxis, _ timelineModel: SliderTimelineModel
    ) {
        let axisExtent = axis.getExtent()

        // if (!timelineModel.get(['lineStyle', 'show'])) { return; }
        if !tlTruthy(timelineModel.get(["lineStyle", "show"])) {
            return
        }

        // style: extend({lineCap:'round'}, timelineModel.getModel('lineStyle').getLineStyle())
        var lineStyleDict = timelineModel.getModel("lineStyle").getLineStyle()
        lineStyleDict["lineCap"] = "round"

        var lineShape = LineShape()
        lineShape.x1 = axisExtent[0]; lineShape.y1 = 0
        lineShape.x2 = axisExtent[1]; lineShape.y2 = 0
        let line = Line([
            "shape": lineShape as PathShape,
            "style": barStyleFromDict(lineStyleDict),
            "silent": true
        ])
        line.z2 = 1
        _ = group.add(line)

        // progressLine — from axisExtent[0] to current pointer x (or axisExtent[0] if no pointer yet).
        let lineWidth = tlReadDouble(lineStyleDict["lineWidth"])
        var progressLineStyle = timelineModel.getModel(["progress", "lineStyle"]).getLineStyle()
        progressLineStyle["lineCap"] = "round"
        if progressLineStyle["lineWidth"] == nil, let lw = lineWidth { progressLineStyle["lineWidth"] = lw }

        var progShape = LineShape()
        progShape.x1 = axisExtent[0]
        progShape.x2 = self._currentPointer?.x ?? axisExtent[0]
        progShape.y1 = 0; progShape.y2 = 0
        let progressLine = Line([
            "shape": progShape as PathShape,
            "style": barStyleFromDict(progressLineStyle),
            "silent": true
        ])
        progressLine.z2 = 1
        self._progressLine = progressLine
        _ = group.add(progressLine)
    }

    // ────────────────────────────── _renderAxisTick ──────────────────────────────
    private func _renderAxisTick(
        _ layoutInfo: LayoutInfo, _ group: Group, _ axis: TimelineAxis, _ timelineModel: SliderTimelineModel
    ) {
        let data = timelineModel.getData()
        // Show all ticks, despite ignoring strategy.
        let ticks = axis.scale.getTicks()

        self._tickSymbols = []

        // The value is dataIndex, see the customized scale.
        let count = data.count()
        for tick in ticks {
            let tickCoord = axis.dataToCoord(tick.value)
            // upstream: `data.getItemModel(tick.value)`. For the standard `axisType:'category'` timeline
            //   the tick value IS the dataIndex (see TimelineModel._initData). For a value/time axisType
            //   the value is the raw datum, so upstream relies on JS out-of-bounds → `undefined` → an
            //   empty Model; the Swift provider would crash on an OOB index. Clamp to the valid range
            //   (exact for the category case; a graceful non-crashing fallback otherwise).
            let itemModel = data.getItemModel(timelineClampIndex(Int(tick.value), count))
            let itemStyleModel = itemModel.getModel("itemStyle")

            // giveSymbol(itemModel, itemStyleModel, group, {x: tickCoord, y: 0})
            let el = timelineGiveSymbol(itemModel, itemStyleModel, group, x: tickCoord, y: 0)
            // el.ensureState('emphasis')/'progress' + enableHoverEmphasis + tooltip ecData — DEFERRED.
            self._tickSymbols.append(el)
        }
    }

    // ────────────────────────────── _renderAxisLabel ──────────────────────────────
    private func _renderAxisLabel(
        _ layoutInfo: LayoutInfo, _ group: Group, _ axis: TimelineAxis, _ timelineModel: SliderTimelineModel
    ) {
        let labelModel = axis.getLabelModel()

        // if (!labelModel.get('show')) { return; }
        if !tlTruthy(labelModel.get("show")) {
            return
        }

        let data = timelineModel.getData()
        let labels = axis.getViewLabels()

        self._tickLabels = []

        for labelItem in labels {
            // if (labelItem.tick.offInterval) { return; }
            if labelItem.tick.offInterval ?? false { continue }
            // The tickValue is dataIndex, see the customized scale. (Clamp: same as _renderAxisTick.)
            let dataIndex = timelineClampIndex(Int(labelItem.tick.value), data.count())

            let itemModel = data.getItemModel(dataIndex)
            let normalLabelModel = itemModel.getModel("label")

            let tickCoord = axis.dataToCoord(labelItem.tick.value)

            // style: createTextStyle(normalLabelModel, {text, align, verticalAlign})
            var specified = TextStyleProps()
            specified.text = labelItem.formattedLabel
            specified.align = TextAlign(rawValue: layoutInfo.labelAlign)
            specified.verticalAlign = TextVerticalAlign(rawValue: layoutInfo.labelBaseline)
            let textStyle = labelStyle.createTextStyle(normalLabelModel, specified, nil, nil, nil)

            let textEl = ZRText([
                "style": textStyle,
                "silent": false
            ])
            textEl.x = tickCoord
            textEl.y = 0
            // rotation: layoutInfo.labelRotation - layoutInfo.rotation
            textEl.rotation = layoutInfo.labelRotation - layoutInfo.rotation

            // textEl.ensureState('emphasis')/'progress' + enableHoverEmphasis + onclick — DEFERRED.

            _ = group.add(textEl)
            self._tickLabels.append(textEl)
        }
    }

    // ────────────────────────────── _renderControl ──────────────────────────────
    private func _renderControl(
        _ layoutInfo: LayoutInfo, _ group: Group, _ axis: TimelineAxis, _ timelineModel: SliderTimelineModel
    ) {
        let controlSize = layoutInfo.controlSize
        let rotation = layoutInfo.rotation

        // const itemStyle = timelineModel.getModel('controlStyle').getItemStyle();
        let itemStyle = timelineModel.getModel("controlStyle").getItemStyle()
        // const playState = timelineModel.getPlayState();
        let playState = timelineModel.getPlayState()

        // makeBtn(position, iconName, onclick, willRotate?)
        func makeBtn(_ position: [Double]?, _ iconName: String, _ willRotate: Bool = false) {
            // if (!position) { return; }
            guard let position = position else { return }
            // const iconSize = parsePercent(retrieve2(controlStyle[iconName+'BtnSize'], controlSize), controlSize);
            let btnSizeOpt = timelineModel.get(["controlStyle", iconName + "BtnSize"])
            let iconSize = number.parsePercent(
                util.retrieve2(tlReadDouble(btnSizeOpt), controlSize) ?? controlSize,
                controlSize
            )
            // const rect = [0, -iconSize/2, iconSize, iconSize];
            let rect = [0, -iconSize / 2, iconSize, iconSize]
            // makeControlIcon(timelineModel, iconName+'Icon', rect, { x, y, originX, originY, rotation, style })
            let btn = makeControlIcon(
                timelineModel, iconName + "Icon", rect,
                x: position[0], y: position[1],
                originX: controlSize / 2, originY: 0,
                rotation: willRotate ? -rotation : 0,
                style: itemStyle
            )
            // btn.ensureState('emphasis') + enableHoverEmphasis — DEFERRED.
            _ = group.add(btn)
        }

        makeBtn(layoutInfo.nextBtnPosition, "next")
        makeBtn(layoutInfo.prevBtnPosition, "prev")
        makeBtn(layoutInfo.playPosition, (playState ? "stop" : "play"), true)
    }

    // ────────────────────────────── _renderCurrentPointer ──────────────────────────────
    private func _renderCurrentPointer(
        _ layoutInfo: LayoutInfo, _ group: Group, _ axis: TimelineAxis, _ timelineModel: SliderTimelineModel
    ) {
        let data = timelineModel.getData()
        let currentIndex = timelineModel.getCurrentIndex()
        // const pointerModel = data.getItemModel(currentIndex).getModel('checkpointStyle');
        let clampedIndex = Swift.max(0, Swift.min(currentIndex, data.count() - 1))
        let pointerModel = data.getItemModel(clampedIndex).getModel("checkpointStyle")

        // this._currentPointer = giveSymbol(pointerModel, pointerModel, this._mainGroup, {}, ...);
        //   (create branch: fresh each static render). Then move it to the current-index coord — the
        //   `onCreate` callback's `pointerMoveTo(..., noAnimation=true)` in upstream.
        let pointer = timelineGiveSymbol(pointerModel, pointerModel, self._mainGroup, x: 0, y: 0)
        // pointerMoveTo (noAnimation): pointer.x = axis.dataToCoord(data.get('value', currentIndex)); y = 0.
        let toCoord = axis.dataToCoord(tlReadDouble(data.get("value", clampedIndex)) ?? 0)
        pointer.x = toCoord
        pointer.y = 0
        pointer.updateTransform()
        self._currentPointer = pointer

        // Sync the progress line end to the pointer (upstream `pointerMoveTo` sets progressLine.shape.x2).
        if let progressLine = self._progressLine {
            var shape = (progressLine.shape as? LineShape) ?? LineShape()
            shape.x2 = toCoord
            progressLine.shape = shape
        }
    }
}

// ────────────────────────────── module helpers (file-local) ──────────────────────────────

/// Clamp a per-item dataIndex into `[0, count-1]` (see the `_renderAxisTick` note). Returns 0 when
/// empty (harmless — the loops that call it don't run when there are no ticks).
private func timelineClampIndex(_ idx: Int, _ count: Int) -> Int {
    if count <= 0 { return 0 }
    return Swift.max(0, Swift.min(idx, count - 1))
}

// function getViewRect(model, api)
private func getViewRect(_ model: SliderTimelineModel, _ api: ExtensionAPI) -> BoundingRect {
    let layoutRef = layout.createBoxLayoutReference(model, api)
    return layout.getLayoutRect(
        model.getBoxLayoutParams(),
        layoutRef.refContainer,
        model.get("padding")
    )
}

// function makeControlIcon(timelineModel, objPath, rect, opts)
//   PORT: `graphic.createIcon` is not ported as a namespace fn; reproduce its `path://` branch via
//   `makePath` (same as ScrollableLegendView.scrollLegendCreateIcon), then apply position/style.
private func makeControlIcon(
    _ timelineModel: TimelineModel, _ objPath: String, _ rect: [Double],
    x: Double, y: Double, originX: Double, originY: Double, rotation: Double, style: [String: Any]
) -> Path {
    // graphic.createIcon(timelineModel.get(['controlStyle', objPath]), opts, new BoundingRect(rect...))
    let iconStr = (timelineModel.get(["controlStyle", objPath]) as? String) ?? ""
    let br = BoundingRect(rect[0], rect[1], rect[2], rect[3])
    let icon: Path = timelineCreateIcon(iconStr, br)

    // opts: x, y, originX, originY, rotation, rectHover:true
    icon.x = x
    icon.y = y
    icon.originX = originX
    icon.originY = originY
    icon.rotation = rotation

    // TODO createIcon won't use style in opt.  if (style) { icon.setStyle(style); }
    //   Merge the control itemStyle onto the icon's style (keep the makePath default strokeNoScale).
    var merged: [String: Any] = style
    if merged["fill"] == nil, let f = style["color"] { merged["fill"] = f }
    icon.useStyle(barStyleFromDict(merged))
    icon.pathStyle.strokeNoScale = true
    icon.dirtyStyle()

    return icon
}

/// Reproduce `graphic.createIcon`'s `path://` branch: `makePath(str, {rectHover:true,
///   style:{strokeNoScale:true}}, rect, 'center')`.
private func timelineCreateIcon(_ iconStr: String, _ rect: BoundingRect) -> Path {
    let pathData = iconStr.hasPrefix("path://") ? String(iconStr.dropFirst("path://".count)) : iconStr
    let path = ZRenderKit.makePath(pathData, nil, rect, "center")
    path.pathStyle.strokeNoScale = true
    path.dirtyStyle()
    return path
}

// function giveSymbol(hostModel, itemStyleModel, group, opt, symbol?, callback?)
//   STATIC-RENDER reduction: always the create branch (no reuse across renders), no event/drag/anim
//   wiring. Faithfully reproduces: createSymbol → strokeNoScale → item style (color as fill) →
//   scale by symbolSize/2 → symbolOffset → symbolRotate → updateTransform.
@discardableResult
private func timelineGiveSymbol(
    _ hostModel: Model, _ itemStyleModel: Model, _ group: Group, x: Double, y: Double
) -> Path {
    // const color = itemStyleModel.get('color');
    let color = itemStyleModel.get("color") as? String

    // const symbolType = hostModel.get('symbol');
    let symbolType = (hostModel.get("symbol") as? String) ?? "circle"
    // symbol = createSymbol(symbolType, -1, -1, 2, 2, color); symbol.setStyle('strokeNoScale', true);
    let symbolEc = symbol.createSymbol(symbolType, -1, -1, 2, 2, color.map { ZRenderKit.ZRColor.string($0) })
    let sym: Path = (symbolEc as? Path) ?? Path()
    _ = group.add(sym)

    // const itemStyle = itemStyleModel.getItemStyle(['color']); symbol.setStyle(itemStyle);
    var styleDict = itemStyleModel.getItemStyle(["color"])
    // createSymbol's color arg set the fill; re-add it so `useStyle` (a REPLACE) keeps it.
    if styleDict["fill"] == nil, let c = color { styleDict["fill"] = c }
    sym.useStyle(barStyleFromDict(styleDict))
    sym.pathStyle.strokeNoScale = true
    sym.dirtyStyle()

    // z2: 100 (from merge({rectHover:true, z2:100}, opt))
    sym.z2 = 100

    // const symbolSize = normalizeSymbolSize(hostModel.get('symbolSize'));
    let symbolSize = symbol.normalizeSymbolSize((hostModel.get("symbolSize") as Any?) ?? 12.0)
    // opt.scaleX = symbolSize[0]/2; opt.scaleY = symbolSize[1]/2;
    sym.scaleX = symbolSize.0 / 2
    sym.scaleY = symbolSize.1 / 2

    // symbolOffset
    var ox = x
    var oy = y
    if let off = symbol.normalizeSymbolOffset(hostModel.get("symbolOffset"), [symbolSize.0, symbolSize.1]) {
        ox += off.0
        oy += off.1
    }
    sym.x = ox
    sym.y = oy

    // opt.rotation = (symbolRotate || 0) * PI / 180 || 0;
    let symbolRotate = tlReadDouble(hostModel.get("symbolRotate")) ?? 0
    sym.rotation = symbolRotate * Double.pi / 180

    // symbol.updateTransform();  (strokeNoScale bounding-rect fix — see upstream FIXME)
    sym.updateTransform()

    return sym
}

// export default SliderTimelineView;  -> `public final class SliderTimelineView` above.
