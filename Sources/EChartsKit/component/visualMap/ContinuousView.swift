// Ported from echarts/src/component/visualMap/ContinuousView.ts — keep in sync with upstream
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
//   import * as zrUtil from 'zrender/src/core/util';                 → `util.*` (ZRenderKit).
//   import LinearGradient from 'zrender/src/graphic/LinearGradient'; → `LinearGradient` (ZRenderKit).
//   import * as eventTool from 'zrender/src/core/event';             → native-event `stop` (no-op headless).
//   import VisualMapView from './VisualMapView';                     → `VisualMapView` (base, same dir).
//   import * as graphic from '../../util/graphic';                   → `Group`/`Rect`/`Polygon`/`ZRText`;
//        `getTransform`/`applyTransform`/`transformDirection` reproduced locally (bottom).
//   import {linearMap, mathMax, mathMin, mathPI} from '../../util/number';
//        → `number.linearMap`; `mathMax`/`mathMin` == `Swift.max`/`Swift.min`; `mathPI` == `Double.pi`.
//   import sliderMove from '../helper/sliderMove';                   → `sliderMove` (component/helper/sliderMove.swift).
//   import * as helper from './helper';                              → `getItemAlign`/`makeHighDownBatch` (local + visualMapHelper).
//   import * as modelUtil from '../../util/model';                   → `model.makeInner` / `model.compressBatches`.
//   import ContinuousModel from './ContinuousModel';                 → `ContinuousModel` (sibling).
//   import Element, { ElementEvent } from 'zrender/src/Element';     → `Element` / `ElementEvent`.
//   import { TextVerticalAlign, TextAlign } from 'zrender/src/core/types';  → `TextVerticalAlign` / `TextAlign`.
//   import { parsePercent } from 'zrender/src/contain/text';         → `text.parsePercent`.
//   import { setAsHighDownDispatcher } from '../../util/states';     → `states.setAsHighDownDispatcher`.
//   import { createSymbol } from '../../util/symbol';                → `symbol.createSymbol`.
//   import { ECData, getECData } from '../../util/innerStore';       → `innerStore.getECData`.
//   import { createTextStyle } from '../../label/labelStyle';        → `createTextStyle` (AxisBuilder.swift).
//   import { findEventDispatcher } from '../../util/event';          → walked inline (hoverLink-from-series).
//   import BoundingRect from 'zrender/src/core/BoundingRect';        → `BoundingRect` (handle-label overlap merge).

// Arbitrary value
private let HOVER_LINK_SIZE = 12.0
private let HOVER_LINK_OUT = 6.0
/// Pixels to inflate handle label bounds when testing overlap (merge slightly before touching).
private let HANDLE_LABEL_MERGE_MARGIN = 2.0

// type ContinuousVisualMapHandleIndex = 0 | 1 | 'all';  → modeled by `SliderMoveHandleIndex`.

// const elInner = modelUtil.makeInner<{ hdlIdx }, Element>();
//   Per-element storage of the drag handle index (0 | 1 | 'all'). `makeInner`'s value must be a
//   reference type, so a tiny box holds the (value-type) `SliderMoveHandleIndex`.
private final class HandleIndexBox { var hdlIdx: SliderMoveHandleIndex? }
private let elInner: (Element) -> HandleIndexBox = model.makeInner { HandleIndexBox() }

// upstream: type ShapeStorage = { handleThumbs; handleLabelPoints; handleLabels; inRange; outOfRange;
//   mainGroup; indicator; indicatorLabel; indicatorLabelPoint }.
private final class ShapeStorage {
    var mainGroup: Group!
    var inRange: Polygon!
    var outOfRange: Polygon!
    var handleThumbs: [Path] = []
    var handleLabels: [ZRText] = []
    var handleLabelPoints: [[Double]] = []
    var indicator: Path?
    var indicatorLabel: ZRText?
    var indicatorLabelPoint: [Double] = [0, 0]
    init() {}
}

// upstream: class ContinuousView extends VisualMapView
public final class ContinuousView: VisualMapView {

    // static type = 'visualMap.continuous';
    public static let continuousType = "visualMap.continuous"
    public override var type: String { return ContinuousView.continuousType }

    // private _shapes = {} as ShapeStorage;
    private var _shapes = ShapeStorage()

    // private _dataInterval: number[] = [];
    private var _dataInterval: [Double] = []
    // private _handleEnds: number[] = [];
    private var _handleEnds: [Double] = []
    // private _orient: Orient;
    private var _orient: String = "vertical"
    // private _useHandle: boolean;
    private var _useHandle: Bool = false
    // private _hoverLinkDataIndices: TargetDataIndices = [];
    private var _hoverLinkDataIndices: [BatchItem] = []
    // private _dragging / _hovering / _firstShowIndicator: boolean;
    private var _dragging: Bool = false
    private var _hovering: Bool = false
    private var _firstShowIndicator: Bool = false

    // ---- test seam: expose the two draggable handle thumbs so a headless test can compute their
    //   global pixel centres and inject a synthetic pointer drag over them (see ZZVisualMapDragTests).
    internal func _handleThumbForTest(_ i: Int) -> Path? {
        return _shapes.handleThumbs.indices.contains(i) ? _shapes.handleThumbs[i] : nil
    }
    internal var _dataIntervalForTest: [Double] { return _dataInterval }

    // upstream: doRender(visualMapModel, ecModel, api, payload: {type, from})
    public override func doRender(
        _ visualMapModel: VisualMapModel,
        _ ecModel: GlobalModel,
        _ api: ExtensionAPI,
        _ payload: Payload
    ) {
        // if (!payload || payload.type !== 'selectDataRange' || payload.from !== this.uid) { this._buildView(); }
        //   A `selectDataRange` self-dispatched by THIS view's own drag must NOT rebuild (the drag has
        //   already updated the shapes in place via `_updateView`); every other trigger rebuilds.
        let from = payload.other["from"] as? String
        if payload.type != "selectDataRange" || from != self.uid {
            self._buildView()
        }
    }

    private func _buildView() {
        _ = self.group.removeAll()

        let visualMapModel = self.visualMapModel!
        let thisGroup = self.group

        self._orient = (visualMapModel.get("orient") as? String) ?? "vertical"
        self._useHandle = visualMapJsTruthy(visualMapModel.get("calculable"))

        // this._resetInterval();
        self._resetInterval()

        self._renderBar(thisGroup)

        // const dataRangeText = visualMapModel.get('text');
        let dataRangeText = visualMapModel.get("text") as? [Any]
        self._renderEndsText(thisGroup, dataRangeText, 0)
        self._renderEndsText(thisGroup, dataRangeText, 1)

        // Do this for background size calculation.
        self._updateView(true)

        // After updating view, inner shapes is built completely, and then background can be rendered.
        self.renderBackground(thisGroup)

        // Real update view
        self._updateView(false)

        self._enableHoverLinkToSeries()
        // PORT-NOTE: `_enableHoverLinkFromSeries()` binds `api.getZr().on('mouseover'/'mouseout')`.
        //   The ExtensionAPI has no live `getZr()`, so the series→bar hover indicator (the "and vice
        //   versa" direction) is driven by the host `EChartsView` instead: it calls this view's public
        //   `_hoverLinkFromSeriesMouseOver(_:)` / `_hideIndicator()` on a series-element mouseover/mouseout.

        self.positionGroup(thisGroup)
    }

    private func _renderEndsText(_ group: Group, _ dataRangeText: [Any]?, _ endsIndex: Int) {
        // if (!dataRangeText) { return; }  — the calculable handle VALUES are shown by the handle labels
        //   (_updateHandle), so the ends-text renders only when an explicit `text` is configured.
        guard let dataRangeText = dataRangeText else { return }

        let visualMapModel = self.visualMapModel!

        // Compatible with ec2, text[0] map to high value, text[1] map low value.
        let rawText = dataRangeText.indices.contains(1 - endsIndex) ? dataRangeText[1 - endsIndex] : nil
        let text = rawText != nil ? stringifyAny(rawText) : ""

        let textGap = visualMapAsDouble(visualMapModel.get("textGap")) ?? 0
        let itemSize = visualMapModel.itemSize

        let barGroup = self._shapes.mainGroup!
        let position = self._applyTransform(
            [itemSize[0] / 2, endsIndex == 0 ? -textGap : itemSize[1] + textGap],
            barGroup
        )
        let align = self._applyTransform(endsIndex == 0 ? "bottom" : "top", barGroup)
        let orient = self._orient
        let textStyleModel = visualMapModel.textStyleModel

        let vAlignStr = (textStyleModel.get("verticalAlign") as? String)
            ?? (orient == "horizontal" ? "middle" : align)
        let alignStr = (textStyleModel.get("align") as? String)
            ?? (orient == "horizontal" ? align : "center")

        var style = createTextStyle(
            textStyleModel,
            text: text,
            align: TextAlign(rawValue: alignStr),
            verticalAlign: TextVerticalAlign(rawValue: vAlignStr)
        )
        style.x = position[0]
        style.y = position[1]
        _ = self.group.add(ZRText(["style": style]))
    }

    private func _renderBar(_ targetGroup: Group) {
        let visualMapModel = self.visualMapModel!
        let shapes = self._shapes
        let itemSize = visualMapModel.itemSize
        let orient = self._orient
        let useHandle = self._useHandle
        // const itemAlign = helper.getItemAlign(visualMapModel, this.api, itemSize);
        let itemAlign = getItemAlign(visualMapModel, self.api!, itemSize)
        let mainGroup = self._createBarGroup(itemAlign)
        shapes.mainGroup = mainGroup

        let gradientBarGroup = Group()
        _ = mainGroup.add(gradientBarGroup)

        // Bar — two polygons: outOfRange (the full track) + inRange (the selected window). Points/fill
        //   are set by `_updateView`; the drag mounts on `inRange` ('all' = move the whole window).
        shapes.outOfRange = createPolygon(nil, nil)
        _ = gradientBarGroup.add(shapes.outOfRange)
        shapes.inRange = createPolygon(nil, useHandle ? getCursor(self._orient) : nil)
        _ = gradientBarGroup.add(shapes.inRange)
        self._mountDrag(shapes.inRange, .all)

        // A border radius clip.
        var clipShape = RectShape()
        clipShape.x = 0
        clipShape.y = 0
        clipShape.width = itemSize[0]
        clipShape.height = itemSize[1]
        clipShape.r = .number(3)
        gradientBarGroup.setClipPath(Rect(["shape": clipShape as PathShape]))

        // const textRect = visualMapModel.textStyleModel.getTextRect('国');
        // const textSize = mathMax(textRect.width, textRect.height);
        let textRect = visualMapModel.textStyleModel.getTextRect("国")
        let textSize = Swift.max(textRect.width, textRect.height)

        // Handle
        if useHandle {
            shapes.handleThumbs = []
            shapes.handleLabels = []
            shapes.handleLabelPoints = []

            self._createHandle(visualMapModel, mainGroup, 0, itemSize, textSize, orient)
            self._createHandle(visualMapModel, mainGroup, 1, itemSize, textSize, orient)
        }

        self._createIndicator(visualMapModel, mainGroup, itemSize, textSize, orient)

        _ = targetGroup.add(mainGroup)
    }

    // upstream: _createHandle(visualMapModel, mainGroup, handleIndex, itemSize, textSize, orient)
    private func _createHandle(
        _ visualMapModel: VisualMapModel,
        _ mainGroup: Group,
        _ handleIndex: Int,
        _ itemSize: [Double],
        _ textSize: Double,
        _ orient: String
    ) {
        // const handleSize = parsePercent(visualMapModel.get('handleSize'), itemSize[0]);
        let handleSize = text.parsePercent(numberOrString(visualMapModel.get("handleSize")), itemSize[0])
        // const handleThumb = createSymbol(handleIcon, -handleSize/2, -handleSize/2, handleSize, handleSize, null, true);
        let handleThumb = symbol.createSymbol(
            (visualMapModel.get("handleIcon") as? String) ?? "roundRect",
            -handleSize / 2, -handleSize / 2, handleSize, handleSize,
            nil, true
        ) as! Path
        let cursor = getCursor(self._orient)
        handleThumb.cursor = cursor
        // handleThumb.attr({ onmousemove(e){ eventTool.stop(e.event) } }) — native stop, no-op headless.

        self._mountDrag(handleThumb, .at(handleIndex))
        handleThumb.x = itemSize[0] / 2

        handleThumb.useStyle(barStyleFromDict(visualMapModel.getModel("handleStyle").getItemStyle()))
        handleThumb.pathStyle.strokeNoScale = true
        handleThumb.pathStyle.strokeFirst = true
        handleThumb.pathStyle.lineWidth = (handleThumb.pathStyle.lineWidth ?? 0) * 2

        handleThumb.ensureState("emphasis").style =
            visualMapModel.getModel(["emphasis", "handleStyle"]).getItemStyle()
        states.setAsHighDownDispatcher(handleThumb, true)

        _ = mainGroup.add(handleThumb)

        // Text is always horizontal layout but should not be effected by transform (orient/inverse). So
        //   the label is built separately (in the view group), located via handleLabelPoint on the thumb.
        let textStyleModel = self.visualMapModel!.textStyleModel
        var labelStyle = createTextStyle(textStyleModel, text: "")
        labelStyle.x = 0
        labelStyle.y = 0
        let handleLabel = ZRText(["style": labelStyle])
        handleLabel.cursor = cursor
        self._mountDrag(handleLabel, .at(handleIndex))
        handleLabel.ensureState("blur").style = ["opacity": 0.1]
        // handleLabel.stateTransition = { duration: 200 } — animation, DEFERRED.

        _ = self.group.add(handleLabel)

        let shapes = self._shapes
        while shapes.handleThumbs.count <= handleIndex { shapes.handleThumbs.append(handleThumb) }
        shapes.handleThumbs[handleIndex] = handleThumb
        while shapes.handleLabelPoints.count <= handleIndex { shapes.handleLabelPoints.append([handleSize, 0]) }
        shapes.handleLabelPoints[handleIndex] = [handleSize, 0]
        while shapes.handleLabels.count <= handleIndex { shapes.handleLabels.append(handleLabel) }
        shapes.handleLabels[handleIndex] = handleLabel
    }

    // upstream: _createIndicator(visualMapModel, mainGroup, itemSize, textSize, orient)
    private func _createIndicator(
        _ visualMapModel: VisualMapModel,
        _ mainGroup: Group,
        _ itemSize: [Double],
        _ textSize: Double,
        _ orient: String
    ) {
        // const scale = parsePercent(visualMapModel.get('indicatorSize'), itemSize[0]);
        let scale = text.parsePercent(numberOrString(visualMapModel.get("indicatorSize")), itemSize[0])
        let indicator = symbol.createSymbol(
            (visualMapModel.get("indicatorIcon") as? String) ?? "circle",
            -scale / 2, -scale / 2, scale, scale,
            nil, true
        ) as! Path
        indicator.cursor = "move"
        indicator.invisible = true
        indicator.silent = true
        indicator.x = itemSize[0] / 2
        // const indicatorStyle = visualMapModel.getModel('indicatorStyle').getItemStyle();
        indicator.useStyle(barStyleFromDict(visualMapModel.getModel("indicatorStyle").getItemStyle()))
        // PORT-NOTE: ZRImage-icon branch (image indicator) — the ported createSymbol image path falls
        //   back to a SymbolClz here, so the upstream ZRImage special-case is not needed.

        _ = mainGroup.add(indicator)

        let textStyleModel = self.visualMapModel!.textStyleModel
        var labelStyle = createTextStyle(textStyleModel, text: "")
        labelStyle.x = 0
        labelStyle.y = 0
        let indicatorLabel = ZRText(["style": labelStyle])
        indicatorLabel.silent = true
        indicatorLabel.invisible = true
        _ = self.group.add(indicatorLabel)

        let indicatorLabelPoint: [Double] = [
            (orient == "horizontal" ? textSize / 2 : HOVER_LINK_OUT) + itemSize[0] / 2,
            0
        ]

        let shapes = self._shapes
        shapes.indicator = indicator
        shapes.indicatorLabel = indicatorLabel
        shapes.indicatorLabelPoint = indicatorLabelPoint

        self._firstShowIndicator = true
    }

    // upstream: _mountDrag(el, handleIndex) — draggable + drift/ondragend + record the handle index.
    private func _mountDrag(_ el: Element, _ handleIndex: SliderMoveHandleIndex) {
        el.draggable = .true
        // upstream: drift: bind(this._dragHandle, this, el, false). The Draggable mixin (Handler) calls
        //   `el.drift(dx, dy, e)` on every drag move; the assigned `driftHandler` fully replaces the
        //   default translate (Element.driftHandler seam). [weak el] breaks el→closure→el.
        el.driftHandler = { [weak self, weak el] dx, dy, e in
            guard let self = self, let el = el else { return }
            self._dragHandle(el, false, dx, dy, e)
        }
        // upstream: ondragend: bind(this._dragHandle, this, el, true). The Handler dispatches a 'dragend'
        //   ELEMENT event on `el` at mouseup (Draggable._dragEnd → dispatchToElement).
        _ = el.on("dragend", { [weak self, weak el] _, args in
            guard let self = self, let el = el else { return nil }
            self._dragHandle(el, true, 0, 0, args.first as? ElementEvent)
            return nil
        })
        elInner(el).hdlIdx = handleIndex
    }

    // upstream: _dragHandle(sourceEl, isEnd?, dx?, dy?)
    private func _dragHandle(
        _ sourceEl: Element,
        _ isEnd: Bool,
        _ dx: Double,
        _ dy: Double,
        _ e: ElementEvent?
    ) {
        if !self._useHandle {
            return
        }

        let handleIndex = elInner(sourceEl).hdlIdx ?? .all
        self._dragging = !isEnd

        if !isEnd {
            // Transform dx, dy to bar coordination.
            let vertex = self._applyTransform([dx, dy], self._shapes.mainGroup, true)
            self._updateInterval(handleIndex, vertex[1])

            self._hideIndicator()
            // Considering realtime, update view should be executed before dispatch action.
            self._updateView(false)
        }

        // dragEnd do not dispatch action when realtime.
        // isEnd === !realtime
        let realtime = visualMapJsTruthy(self.visualMapModel!.get("realtime"))
        if isEnd == !realtime {
            var payload = Payload(type: "selectDataRange")
            payload.other["from"] = self.uid
            payload.other["visualMapId"] = self.visualMapModel!.id
            payload.other["selected"] = Array(self._dataInterval)
            self.api!.dispatchAction(payload, nil)
        }

        if isEnd {
            if !self._hovering { self._clearHoverLinkToSeries() }
        }
        else if useHoverLinkOnHandle(self.visualMapModel!) {
            let hoverPos: Double
            switch handleIndex {
            case .all: hoverPos = (self._handleEnds[0] + self._handleEnds[1]) / 2
            case .at(let i): hoverPos = self._handleEnds[i]
            }
            self._doHoverLinkToSeries(hoverPos, false)
        }
    }

    // upstream: _resetInterval() — seed `_dataInterval` + `_handleEnds` from the model's selected range.
    private func _resetInterval() {
        let visualMapModel = self.visualMapModel!

        // const dataInterval = this._dataInterval = visualMapModel.getSelected();
        let dataInterval = (visualMapModel.getSelected() as? [Double]) ?? []
        self._dataInterval = dataInterval
        let dataExtent = visualMapModel.getExtent()
        let sizeExtent = [0.0, visualMapModel.itemSize[1]]

        self._handleEnds = [
            number.linearMap(dataInterval[0], dataExtent, sizeExtent, true),
            number.linearMap(dataInterval[1], dataExtent, sizeExtent, true)
        ]
    }

    // upstream: _updateInterval(handleIndex, delta)
    private func _updateInterval(_ handleIndex: SliderMoveHandleIndex, _ deltaIn: Double) {
        let delta = deltaIn.isNaN ? 0 : deltaIn
        let visualMapModel = self.visualMapModel!
        var handleEnds = self._handleEnds
        let sizeExtent = [0.0, visualMapModel.itemSize[1]]

        // sliderMove(delta, handleEnds, sizeExtent, handleIndex, /* cross is forbidden */ 0);
        _ = sliderMove(delta, &handleEnds, sizeExtent, handleIndex, 0)
        self._handleEnds = handleEnds

        let dataExtent = visualMapModel.getExtent()
        // Update data interval.
        self._dataInterval = [
            number.linearMap(handleEnds[0], sizeExtent, dataExtent, true),
            number.linearMap(handleEnds[1], sizeExtent, dataExtent, true)
        ]
    }

    // upstream: _updateView(forSketch?)
    private func _updateView(_ forSketch: Bool) {
        let visualMapModel = self.visualMapModel!
        let dataExtent = visualMapModel.getExtent()
        let shapes = self._shapes

        let outOfRangeHandleEnds = [0.0, visualMapModel.itemSize[1]]
        let inRangeHandleEnds = forSketch ? outOfRangeHandleEnds : self._handleEnds

        let visualInRange = self._createBarVisual(
            self._dataInterval, dataExtent, inRangeHandleEnds, "inRange"
        )
        let visualOutOfRange = self._createBarVisual(
            dataExtent, dataExtent, outOfRangeHandleEnds, "outOfRange"
        )

        // shapes.inRange.setStyle({fill}).setShape('points', points);  — per-key setShape is a no-op in
        //   this port, so assign the shape/fill directly (equivalent).
        _setPolygon(shapes.inRange, fill: visualInRange.barColor, points: visualInRange.barPoints)
        _setPolygon(shapes.outOfRange, fill: visualOutOfRange.barColor, points: visualOutOfRange.barPoints)

        self._updateHandle(inRangeHandleEnds, visualInRange)
    }

    // upstream: _createBarVisual(dataInterval, dataExtent, handleEnds, forceState) → BarVisual
    private struct BarVisual {
        var barColor: LinearGradient
        var barPoints: [VectorArray]
        var handlesColor: [String]
    }
    private func _createBarVisual(
        _ dataInterval: [Double],
        _ dataExtent: [Double],
        _ handleEnds: [Double],
        _ forceState: VisualState
    ) -> BarVisual {
        let colorStops = self._makeColorGradient(
            dataInterval, forceState: forceState, convertOpacityToAlpha: true
        )

        let symbolSizes = [
            cvDouble(self.getControllerVisual(dataInterval[0], "symbolSize", forceState: forceState, convertOpacityToAlpha: true))
                ?? self.visualMapModel!.itemSize[0],
            cvDouble(self.getControllerVisual(dataInterval[1], "symbolSize", forceState: forceState, convertOpacityToAlpha: true))
                ?? self.visualMapModel!.itemSize[0]
        ]
        let barPoints = self._createBarPoints(handleEnds, symbolSizes)

        return BarVisual(
            barColor: LinearGradient(0, 0, 0, 1, colorStops),
            barPoints: barPoints,
            handlesColor: [
                colorStops.first?.color ?? "#000",
                colorStops.last?.color ?? "#000"
            ]
        )
    }

    // upstream: _makeColorGradient(dataInterval, opts) — sample the (possibly non-linear) mapping.
    private func _makeColorGradient(
        _ dataInterval: [Double],
        forceState: VisualState?,
        convertOpacityToAlpha: Bool
    ) -> [GradientColorStop] {
        let sampleNumber = 100 // Arbitrary value.
        var colorStops: [GradientColorStop] = []
        let step = (dataInterval[1] - dataInterval[0]) / Double(sampleNumber)

        colorStops.append(GradientColorStop(
            offset: 0,
            color: colorToString(self.getControllerVisual(
                dataInterval[0], "color", forceState: forceState, convertOpacityToAlpha: convertOpacityToAlpha
            ))
        ))

        var i = 1
        while i < sampleNumber {
            let currValue = dataInterval[0] + step * Double(i)
            if currValue > dataInterval[1] {
                break
            }
            colorStops.append(GradientColorStop(
                offset: Double(i) / Double(sampleNumber),
                color: colorToString(self.getControllerVisual(
                    currValue, "color", forceState: forceState, convertOpacityToAlpha: convertOpacityToAlpha
                ))
            ))
            i += 1
        }

        colorStops.append(GradientColorStop(
            offset: 1,
            color: colorToString(self.getControllerVisual(
                dataInterval[1], "color", forceState: forceState, convertOpacityToAlpha: convertOpacityToAlpha
            ))
        ))

        return colorStops
    }

    // upstream: _createBarPoints(handleEnds, symbolSizes)
    private func _createBarPoints(_ handleEnds: [Double], _ symbolSizes: [Double]) -> [VectorArray] {
        let itemSize = self.visualMapModel!.itemSize
        return [
            VectorArray(itemSize[0] - symbolSizes[0], handleEnds[0]),
            VectorArray(itemSize[0], handleEnds[0]),
            VectorArray(itemSize[0], handleEnds[1]),
            VectorArray(itemSize[0] - symbolSizes[1], handleEnds[1])
        ]
    }

    // upstream: _createBarGroup(itemAlign) — the orient/inverse/itemAlign transform of the bar.
    private func _createBarGroup(_ itemAlign: String) -> Group {
        let isVertical = self._orient == "vertical"
        let isItemAlignButtom = itemAlign == "bottom"
        let isItemAlignLeft = itemAlign == "left"
        let inverse = visualMapJsTruthy(self.visualMapModel!.get("inverse"))

        let props: [String: Any]
        if !isVertical && !inverse {
            props = ["scaleX": isItemAlignButtom ? 1.0 : -1.0, "rotation": Double.pi / 2]
        }
        else if !isVertical && inverse {
            props = ["scaleX": isItemAlignButtom ? -1.0 : 1.0, "rotation": -Double.pi / 2]
        }
        else if isVertical && !inverse {
            props = ["scaleX": isItemAlignLeft ? 1.0 : -1.0, "scaleY": -1.0]
        }
        else { // isVertical && inverse
            props = ["scaleX": isItemAlignLeft ? 1.0 : -1.0]
        }
        return Group(props)
    }

    // upstream: _updateHandle(handleEnds, visualInRange)
    private func _updateHandle(_ handleEnds: [Double], _ visualInRange: BarVisual) {
        if !self._useHandle {
            return
        }

        let shapes = self._shapes
        let visualMapModel = self.visualMapModel!
        let handleThumbs = shapes.handleThumbs
        let handleLabels = shapes.handleLabels
        let itemSize = visualMapModel.itemSize
        let dataExtent = visualMapModel.getExtent()
        let barGroup = shapes.mainGroup!
        let alignDir = self._applyTransform("left", barGroup)
        let isVertical = self._orient == "vertical"
        var textPosPair: [Point?] = [nil, nil]
        var textRectPair: [BoundingRect?] = [nil, nil]

        for handleIndex in 0..<2 {
            guard handleThumbs.indices.contains(handleIndex),
                  handleLabels.indices.contains(handleIndex) else { continue }
            let handleThumb = handleThumbs[handleIndex]
            handleThumb.pathStyle.fill = .string(visualInRange.handlesColor[handleIndex])
            handleThumb.dirtyStyle()
            handleThumb.y = handleEnds[handleIndex]

            let val = number.linearMap(handleEnds[handleIndex], [0, itemSize[1]], dataExtent, true)
            let symbolSize = cvDouble(self.getControllerVisual(val, "symbolSize")) ?? itemSize[0]

            handleThumb.scaleX = symbolSize / itemSize[0]
            handleThumb.scaleY = symbolSize / itemSize[0]
            handleThumb.x = itemSize[0] - symbolSize / 2

            // Update handle label position.
            var textPoint = applyTransformPoint(
                shapes.handleLabelPoints[handleIndex],
                getTransform(handleThumb, self.group),
                false
            )

            if !isVertical {
                // Offset to avoid label collision at minimum symbol size.
                let minimumOffset = (alignDir == "left" || alignDir == "top")
                    ? (itemSize[0] - symbolSize) / 2
                    : (itemSize[0] - symbolSize) / -2
                textPoint[1] += minimumOffset
            }

            var s = handleLabels[handleIndex].textStyle!
            s.x = textPoint[0]
            s.y = textPoint[1]
            s.text = visualMapModel.formatValueText(self._dataInterval[handleIndex])
            s.verticalAlign = .middle
            s.align = isVertical ? TextAlign(rawValue: alignDir) : .center
            handleLabels[handleIndex].useStyle(s)
            elInner(handleLabels[handleIndex]).hdlIdx = .at(handleIndex) // May be updated if previously overlapped.

            textPosPair[handleIndex] = Point(textPoint[0], textPoint[1])
            if let rect = handleLabels[handleIndex].getBoundingRect()?.clone() {
                expandOrShrinkRect(rect, HANDLE_LABEL_MERGE_MARGIN, false, true)
                textRectPair[handleIndex] = rect
            }
        }

        // If the two handle labels overlap, nudge them apart along the bar direction and switch both
        //   labels to 'all'-drag (the bar is hard to hit when the handles are very close).
        let mtv = Point()
        let directionVec = self._applyTransform([0, 1], barGroup)
        if let rect0 = textRectPair[0], let rect1 = textRectPair[1],
           let pos0 = textPosPair[0], let pos1 = textPosPair[1] {
            let labelsOverlap = BoundingRect.intersect(
                rect0,
                rect1,
                mtv,
                BoundingRectIntersectOpt(
                    direction: atan2(directionVec[1], directionVec[0]),
                    bidirectional: false
                )
            )
            if labelsOverlap {
                pos0.scaleAndAdd(mtv, -0.5)
                pos1.scaleAndAdd(mtv, 0.5)
                var s0 = handleLabels[0].textStyle!
                s0.x = pos0.x
                s0.y = pos0.y
                handleLabels[0].useStyle(s0)
                var s1 = handleLabels[1].textStyle!
                s1.x = pos1.x
                s1.y = pos1.y
                handleLabels[1].useStyle(s1)
                // When two handles are too close, the bar is difficult to hit, so dragging in
                // 'all' mode becomes hard to trigger. Therefore, switch labels dragging to 'all' mode.
                elInner(handleLabels[0]).hdlIdx = .all
                elInner(handleLabels[1]).hdlIdx = .all
            }
        }
    }

    // upstream: _showIndicator(cursorValue, textValue, rangeSymbol?, halfHoverLinkSize?)
    private func _showIndicator(
        _ cursorValue: Double,
        _ textValue: Double,
        _ rangeSymbol: String? = nil,
        _ halfHoverLinkSize: Double? = nil
    ) {
        let visualMapModel = self.visualMapModel!
        let dataExtent = visualMapModel.getExtent()
        let itemSize = visualMapModel.itemSize
        let sizeExtent = [0.0, itemSize[1]]

        let shapes = self._shapes
        guard let indicator = shapes.indicator else { return }

        indicator.invisible = false

        let color = colorToString(self.getControllerVisual(cursorValue, "color", convertOpacityToAlpha: true))
        let symbolSize = cvDouble(self.getControllerVisual(cursorValue, "symbolSize")) ?? itemSize[0]
        let y = number.linearMap(cursorValue, dataExtent, sizeExtent, true)
        let x = itemSize[0] - symbolSize / 2

        let oldIndicatorPos = (x: indicator.x, y: indicator.y)
        // Update handle label position.
        indicator.y = y
        indicator.x = x
        let textPoint = applyTransformPoint(
            shapes.indicatorLabelPoint,
            getTransform(indicator, self.group),
            false
        )

        if let indicatorLabel = shapes.indicatorLabel {
            indicatorLabel.invisible = false
            let alignDir = self._applyTransform("left", shapes.mainGroup)
            let isHorizontal = self._orient == "horizontal"
            var s = indicatorLabel.textStyle!
            s.text = (rangeSymbol ?? "") + visualMapModel.formatValueText(textValue)
            s.verticalAlign = isHorizontal ? TextVerticalAlign(rawValue: alignDir) : .middle
            s.align = isHorizontal ? .center : TextAlign(rawValue: alignDir)
            indicatorLabel.useStyle(s)
        }

        // const indicatorNewProps = { x, y, style: { fill: color } };
        // const labelNewProps = { style: { x: textPoint[0], y: textPoint[1] } };
        if (self.ecModel!.isAnimationEnabled() ?? false) && !self._firstShowIndicator {
            var animationCfg = ElementAnimateConfig()
            animationCfg.duration = 100
            animationCfg.easing = .named("cubicInOut")
            animationCfg.additive = true
            indicator.x = oldIndicatorPos.x
            indicator.y = oldIndicatorPos.y
            indicator.animateTo(
                ["x": x, "y": y, "style": ["fill": color] as [String: Any]],
                animationCfg
            )
            shapes.indicatorLabel?.animateTo(
                ["style": ["x": textPoint[0], "y": textPoint[1]] as [String: Any]],
                animationCfg
            )
        }
        else {
            indicator.x = x
            indicator.y = y
            indicator.pathStyle.fill = .string(color)
            indicator.dirtyStyle()
            if let indicatorLabel = shapes.indicatorLabel {
                var s = indicatorLabel.textStyle!
                s.x = textPoint[0]
                s.y = textPoint[1]
                indicatorLabel.useStyle(s)
            }
        }

        self._firstShowIndicator = false

        let handleLabels = self._shapes.handleLabels
        for i in 0..<handleLabels.count {
            // Fade out handle labels via the api blur seam.
            self.api!.enterBlur(handleLabels[i])
        }
    }

    // upstream: _enableHoverLinkToSeries() — bar hover → highlight the matching series data.
    private func _enableHoverLinkToSeries() {
        _ = self._shapes.mainGroup.on("mousemove", { [weak self] _, args in
            guard let self = self, let e = args.first as? ElementEvent else { return nil }
            self._hovering = true

            if !self._dragging {
                let itemSize = self.visualMapModel!.itemSize
                var pos = self._applyTransform([e.offsetX, e.offsetY], self._shapes.mainGroup, true, true)
                // For hover link show when hover handle (might be below/upper than sizeExtent).
                pos[1] = Swift.min(Swift.max(0, pos[1]), itemSize[1])
                self._doHoverLinkToSeries(pos[1], 0 <= pos[0] && pos[0] <= itemSize[0])
            }
            return nil
        })

        _ = self._shapes.mainGroup.on("mouseout", { [weak self] _, _ in
            guard let self = self else { return nil }
            self._hovering = false
            if !self._dragging { self._clearHoverLinkToSeries() }
            return nil
        })
    }

    // upstream: _doHoverLinkToSeries(cursorPos, hoverOnBar?)
    private func _doHoverLinkToSeries(_ cursorPosIn: Double, _ hoverOnBar: Bool) {
        let visualMapModel = self.visualMapModel! as! ContinuousModel
        let itemSize = visualMapModel.itemSize

        if !visualMapJsTruthy(visualMapModel.get("hoverLink")) {
            return
        }

        let sizeExtent = [0.0, itemSize[1]]
        let dataExtent = visualMapModel.getExtent()

        // For hover link show when hover handle (might be below or upper than sizeExtent).
        let cursorPos = Swift.min(Swift.max(sizeExtent[0], cursorPosIn), sizeExtent[1])

        let halfHoverLinkSize = getHalfHoverLinkSize(visualMapModel, dataExtent, sizeExtent)
        var hoverRange = [cursorPos - halfHoverLinkSize, cursorPos + halfHoverLinkSize]
        let cursorValue = number.linearMap(cursorPos, sizeExtent, dataExtent, true)
        var valueRange = [
            number.linearMap(hoverRange[0], sizeExtent, dataExtent, true),
            number.linearMap(hoverRange[1], sizeExtent, dataExtent, true)
        ]
        // Consider data range out of visualMap range.
        if hoverRange[0] < sizeExtent[0] { valueRange[0] = -Double.infinity }
        if hoverRange[1] > sizeExtent[1] { valueRange[1] = Double.infinity }
        _ = hoverRange   // (kept for structural fidelity)

        // Do not show indicator when mouse is over handle (labels overlap, especially dragging).
        if hoverOnBar {
            if valueRange[0] == -Double.infinity {
                self._showIndicator(cursorValue, valueRange[1], "< ", halfHoverLinkSize)
            }
            else if valueRange[1] == Double.infinity {
                self._showIndicator(cursorValue, valueRange[0], "> ", halfHoverLinkSize)
            }
            else {
                self._showIndicator(cursorValue, cursorValue, "≈ ", halfHoverLinkSize)
            }
        }

        let oldBatch = self._hoverLinkDataIndices
        var newBatch: [BatchItem] = []
        if hoverOnBar || useHoverLinkOnHandle(visualMapModel) {
            newBatch = targetDataIndicesToBatchItems(visualMapModel.findTargetDataIndices(valueRange))
            self._hoverLinkDataIndices = newBatch
        }

        let resultBatches = model.compressBatches(oldBatch, newBatch)

        self._dispatchHighDown("downplay", makeHighDownBatch(resultBatches.0, visualMapModel))
        self._dispatchHighDown("highlight", makeHighDownBatch(resultBatches.1, visualMapModel))
    }

    // upstream: _hoverLinkFromSeriesMouseOver(e) — hovering a data point highlights the corresponding
    //   position on the visualMap bar (the "and vice versa" direction). Driven by the host EChartsView.
    public func _hoverLinkFromSeriesMouseOver(_ e: ElementEvent) {
        // findEventDispatcher(e.target, target => getECData(target).dataIndex != null, true) — walk up
        //   to the nearest ECData-bearing ancestor.
        var ecDataFound: ECData? = nil
        var cur: Element? = e.target
        while let el = cur {
            let d = innerStore.getECData(el)
            if d.dataIndex != nil {
                ecDataFound = d
                break
            }
            cur = el.__hostTarget ?? (el.parent as? Element)
        }
        guard let ecData = ecDataFound,
              let dataIndex = ecData.dataIndex,
              let seriesIndex = ecData.seriesIndex else { return }

        guard let dataModel = self.ecModel!.getSeriesByIndex(seriesIndex) else { return }

        let visualMapModel = self.visualMapModel!
        if !visualMapModel.isTargetSeries(dataModel) { return }

        let data = dataModel.getData(ecData.dataType)
        guard let dimIdx = visualMapModel.getDataDimensionIndex(data) else { return }
        let value = data.getStore().get(dimIdx, Int(dataIndex))
        let valueD = cvDouble(value)

        if let v = valueD, !v.isNaN {
            self._showIndicator(v, v)
        }
    }

    // upstream: _hideIndicator()
    public func _hideIndicator() {
        let shapes = self._shapes
        shapes.indicator?.invisible = true
        shapes.indicatorLabel?.invisible = true

        let handleLabels = self._shapes.handleLabels
        for i in 0..<handleLabels.count {
            self.api!.leaveBlur(handleLabels[i])
        }
    }

    // upstream: _clearHoverLinkToSeries()
    private func _clearHoverLinkToSeries() {
        self._hideIndicator()

        let indices = self._hoverLinkDataIndices
        self._dispatchHighDown("downplay", makeHighDownBatch(indices, self.visualMapModel!))

        self._hoverLinkDataIndices = []
    }

    // upstream: _dispatchHighDown(type, batch)
    private func _dispatchHighDown(_ type: String, _ batch: [PayloadItem]) {
        if batch.isEmpty { return }
        var payload = Payload(type: type)
        payload.batch = batch
        self.api!.dispatchAction(payload, nil)
    }

    // upstream overloaded: _applyTransform(vertex: number[] | Direction, element, inverse?, global?)
    private func _applyTransform(_ vertex: [Double], _ element: Element, _ inverse: Bool = false, _ global: Bool = false) -> [Double] {
        let transform = getTransform(element, global ? nil : self.group)
        return applyTransformPoint(vertex, transform, inverse)
    }

    private func _applyTransform(_ vertex: String, _ element: Element, _ inverse: Bool = false, _ global: Bool = false) -> String {
        let transform = getTransform(element, global ? nil : self.group)
        return transformDirection(vertex, transform, inverse)
    }
}

// export default ContinuousView;  → `final class ContinuousView` above.

// ============================================================================
// Module-internal helpers (upstream free functions at the bottom of ContinuousView.ts).
// ============================================================================

// upstream: function createPolygon(points?, cursor?)
private func createPolygon(_ points: [VectorArray]?, _ cursor: String?) -> Polygon {
    var shape = PolygonShape()
    shape.points = points
    let poly = Polygon(["shape": shape as PathShape])
    if let cursor = cursor { poly.cursor = cursor }
    // onmousemove(e){ eventTool.stop(e.event) } — native stop, no-op headless.
    return poly
}

// upstream: function getHalfHoverLinkSize(visualMapModel, dataExtent, sizeExtent)
private func getHalfHoverLinkSize(_ visualMapModel: ContinuousModel, _ dataExtent: [Double], _ sizeExtent: [Double]) -> Double {
    var halfHoverLinkSize = HOVER_LINK_SIZE / 2
    if let hoverLinkDataSize = visualMapAsDouble(visualMapModel.get("hoverLinkDataSize")) {
        halfHoverLinkSize = number.linearMap(hoverLinkDataSize, dataExtent, sizeExtent, true) / 2
    }
    return halfHoverLinkSize
}

// upstream: function useHoverLinkOnHandle(visualMapModel)
private func useHoverLinkOnHandle(_ visualMapModel: VisualMapModel) -> Bool {
    let hoverLinkOnHandle = visualMapModel.get("hoverLinkOnHandle")
    // return !!(hoverLinkOnHandle == null ? get('realtime') : hoverLinkOnHandle);
    if hoverLinkOnHandle == nil || hoverLinkOnHandle is NSNull {
        return visualMapJsTruthy(visualMapModel.get("realtime"))
    }
    return visualMapJsTruthy(hoverLinkOnHandle)
}

// upstream: function getCursor(orient)
private func getCursor(_ orient: String) -> String {
    return orient == "vertical" ? "ns-resize" : "ew-resize"
}

// upstream helper.makeHighDownBatch(batch, visualMapModel) — move dataIndex → dataIndexInside + stamp a
//   `highlightKey`. Here we take the compressed `[BatchItem]` and emit `[PayloadItem]`.
private func makeHighDownBatch(_ batch: [BatchItem], _ visualMapModel: VisualMapModel) -> [PayloadItem] {
    var out: [PayloadItem] = []
    for item in batch {
        var p = PayloadItem()
        p.other["seriesId"] = item.seriesId
        // batchItem.dataIndexInside = batchItem.dataIndex; batchItem.dataIndex = null;
        p.other["dataIndexInside"] = item.dataIndex
        p.other["highlightKey"] = "visualMap" + String(Int(visualMapModel.componentIndex))
        out.append(p)
    }
    return out
}

// Convert `findTargetDataIndices` output ([{seriesId, dataIndex:[Double]}]) → [BatchItem].
private func targetDataIndicesToBatchItems(_ list: [[String: Any]]) -> [BatchItem] {
    return list.compactMap { dict in
        guard let seriesId = dict["seriesId"] else { return nil }
        let dataIndex = dict["dataIndex"] ?? ([] as [Double])
        return BatchItem(seriesId: seriesId, dataIndex: dataIndex)
    }
}

// Assign a polygon's points + fill directly (per-key setShape/setStyle is a no-op in this port).
private func _setPolygon(_ poly: Polygon?, fill: LinearGradient, points: [VectorArray]) {
    guard let poly = poly else { return }
    var shape = PolygonShape()
    shape.points = points
    _ = poly.setShape(shape as PathShape)
    poly.pathStyle.fill = .linearGradient(fill)
    poly.dirtyStyle()
}

// getControllerVisual('color'/'symbolSize', …) → coerce to the concrete Swift type the callers need.
private func cvDouble(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return nil
}

// `parsePercent(get('handleSize'), base)` takes a `NumberOrString`; bridge the dynamic option value.
private func numberOrString(_ v: Any?) -> NumberOrString {
    if let s = v as? String { return .string(s) }
    if let d = cvDouble(v) { return .number(d) }
    return .number(0)
}

// ============================================================================
// PORT-NOTE helpers — NOT part of visualMap/ContinuousView.ts upstream. These reproduce out-of-phase
// sibling APIs (`util/graphic` transform helpers, `visualMap/helper.getItemAlign`) so the view compiles.
// ============================================================================

// `getTransform` — the local stand-in is GONE: `util/graphic.getTransform(target, ancestor?)` is now the
//   real ported helper (util/graphic.swift), with an identical body, so the call sites below resolve to it.
//   (Keeping both is a hard "invalid redeclaration": same module, same signature.)

/// upstream `util/graphic.applyTransform(target, transform, invert?)`.
private func applyTransformPoint(_ target: [Double], _ transform: MatrixArray, _ invert: Bool) -> [Double] {
    var m = transform
    if invert {
        m = matrix.invert(m) ?? m
    }
    let r = vector.applyTransform(VectorArray(target[0], target[1]), m)
    return [r[0], r[1]]
}

/// upstream `util/graphic.transformDirection(direction, transform, invert?)`.
private func transformDirection(_ direction: String, _ transform: MatrixArray, _ invert: Bool) -> String {
    let hBase = (transform[4] == 0 || transform[5] == 0 || transform[0] == 0)
        ? 1.0 : Swift.abs(2 * transform[4] / transform[0])
    let vBase = (transform[4] == 0 || transform[5] == 0 || transform[2] == 0)
        ? 1.0 : Swift.abs(2 * transform[4] / transform[2])

    var vertex: [Double] = [
        direction == "left" ? -hBase : direction == "right" ? hBase : 0,
        direction == "top" ? -vBase : direction == "bottom" ? vBase : 0
    ]
    vertex = applyTransformPoint(vertex, transform, invert)

    return Swift.abs(vertex[0]) > Swift.abs(vertex[1])
        ? (vertex[0] > 0 ? "right" : "left")
        : (vertex[1] > 0 ? "bottom" : "top")
}

/// The `getControllerVisual('color', ...)` result is a color option value (a `String` in the static path).
internal func colorToString(_ v: Any?) -> String {
    if let s = v as? String { return s }
    // PORT-NOTE (deferred): gradient/pattern color objects are not stringified here (only the String
    //   form of a visual-result color is handled).
    return ""
}

/// `String(value)` for the `text + ''` idiom in `_renderEndsText`.
internal func stringifyAny(_ v: Any?) -> String {
    guard let v = v else { return "" }
    if let s = v as? String { return s }
    if let d = visualMapAsDouble(v) {
        return d == d.rounded() && d.isFinite ? String(Int(d)) : String(d)
    }
    return "\(v)"
}

/// PORT-NOTE: faithful reproduction of `visualMap/helper.getItemAlign` (NOT ported).
internal func getItemAlign(_ visualMapModel: VisualMapModel, _ api: ExtensionAPI, _ itemSize: [Double]) -> String {
    let paramsSet = [["left", "right", "width"], ["top", "bottom", "height"]]

    let itemAlign = visualMapModel.get("align") as? String
    if let itemAlign = itemAlign, itemAlign != "auto" {
        return itemAlign
    }

    let ecWidth = api.getWidth()
    let ecHeight = api.getHeight()
    let realIndex = (visualMapModel.get("orient") as? String) == "horizontal" ? 1 : 0

    let reals = paramsSet[realIndex]
    let fakeValue: [Any?] = [0.0, nil, 10.0]

    var layoutInput: [String: Any] = [:]
    for i in 0..<3 {
        if let fv = fakeValue[i] {
            layoutInput[paramsSet[1 - realIndex][i]] = fv
        }
        if i == 2 {
            layoutInput[reals[i]] = itemSize[0]
        }
        else if let v = visualMapModel.get(reals[i]) {
            layoutInput[reals[i]] = v
        }
    }

    let ecSize = BoundingRect(0, 0, ecWidth, ecHeight)
    let rect = layout.getLayoutRect(layoutInput as Any?, ecSize, visualMapModel.get("padding"))

    let rectStart = realIndex == 0 ? rect.x : rect.y
    let rectLen = realIndex == 0 ? rect.width : rect.height
    let ecLen = realIndex == 0 ? ecWidth : ecHeight

    return reals[(0 + rectStart + rectLen * 0.5) < ecLen * 0.5 ? 0 : 1]
}
