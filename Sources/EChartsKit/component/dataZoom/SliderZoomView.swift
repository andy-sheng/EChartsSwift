// Ported from echarts/src/component/dataZoom/SliderZoomView.ts — keep in sync with upstream
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

// upstream imports mapping:
//   import * as graphic from '../../util/graphic';           -> ZRenderKit `Rect` / `Group` / `Text`(ZRText) used directly;
//        the `graphic.getTransform` / `graphic.applyTransform` / `graphic.transformDirection` helpers are
//        reproduced file-privately at the bottom (mirrors ContinuousView.swift), until util/graphic lands them.
//   import DataZoomView from './DataZoomView';               -> NOT PORTED. `DataZoomView` is a thin base whose
//        `render` only caches `this.dataZoomModel / ecModel / api`. Those three fields + that caching are inlined
//        here (see `super`-equivalent at the top of `render`). `SliderZoomView` extends `ComponentView` directly.
//   import { linearMap, asc, parsePercent, round } from '../../util/number';  -> `number.*`
//   import * as layout from '../../util/layout';             -> `layout.*` (util/layout.swift; getLayoutRect/getBoxLayoutParams/createBoxLayoutReference)
//   import { createSymbol, symbolBuildProxies } from '../../util/symbol';     -> `symbol.createSymbol` / `symbol.symbolBuildProxies`
//   import { createTextStyle } from '../../label/labelStyle';                 -> module-internal `createTextStyle` (AxisBuilder.swift)
//   import { enableHoverEmphasis } from '../../util/states';                  -> `states.enableHoverEmphasis`
//   import tokens from '../../visual/tokens';                                 -> `tokens`
//   import { isOrdinalScale, isTimeScale } from '../../scale/helper';         -> `helper.isOrdinalScale` / `helper.isTimeScale`
//   import { getAxisMainType, collectReferCoordSysModelInfo, getAlignTo } from './helper'; -> dataZoomHelper.swift
//   import * as throttle from '../../util/throttle';         -> DEFERRED (TASK 2 — dispatch throttling)
//   import sliderMove from '../helper/sliderMove';           -> `sliderMove` (component/helper/sliderMove.swift) — used by TASK 2 drag

// Constants
private let DEFAULT_FRAME_BORDER_WIDTH: Double = 1
private let DEFAULT_FILLER_SIZE: Double = 30
private let DEFAULT_MOVE_HANDLE_SIZE: Double = 7
private let HORIZONTAL = "horizontal"
private let VERTICAL = "vertical"
private let LABEL_GAP: Double = 5
// private let SHOW_DATA_SHADOW_SERIES_TYPE = ['line', 'bar', 'candlestick', 'scatter'];  // DEFERRED (data shadow)

// upstream: interface Displayables { sliderGroup; handles; handleLabels; dataShadowSegs; filler;
//   brushRect; moveHandle; moveHandleIcon; moveZone; }
//   Modeled as a `final class` (reference bag) of optionals so `render` can populate incrementally and
//   TASK 2's drag/brush can reach them. `dataShadowSegs` / `brushRect` are DEFERRED (data shadow / brush).
public final class SliderZoomDisplayables {
    public var sliderGroup: Group?
    // [coord of the first handle, coord of the second handle]
    public var handles: [Path?] = [nil, nil]
    public var handleLabels: [ZRText?] = [nil, nil]
    public var filler: Rect?
    public var panel: Rect?               // upstream: the transparent `clickPanel` (over shadow, below handles).
    public var moveHandle: Rect?
    public var moveHandleIcon: Path?
    public var moveZone: Rect?
    public var brushRect: Rect?          // brush-select rubber band (upstream Displayables.brushRect).
    // public var dataShadowSegs: [Group] // DEFERRED (data shadow)
    public init() {}
}

// class SliderZoomView extends DataZoomView (extends ComponentView)
open class SliderZoomView: ComponentView {

    // PORT-STUB: upstream toggles the handle-label emphasis visibility here; the handle labels are not
    //   ported, so dragging a slider handle never shows the value under the cursor.
    func _showDataInfo(_ isEmphasis: Bool) {
        PortStub.hit("SliderZoomView._showDataInfo",
                     "dataZoom slider handle labels are not ported; dragging a handle shows no value")
        _ = isEmphasis
    }

    // static type = 'dataZoom.slider'; type = SliderZoomView.type;
    public static let type = "dataZoom.slider"
    open var type: String { return SliderZoomView.type }

    // ---- inlined from DataZoomView (the un-ported thin base) ----
    // upstream DataZoomView declares: dataZoomModel; ecModel; api; and its `render` caches all three.
    public var dataZoomModel: SliderZoomModel!
    public var ecModel: GlobalModel!
    public var api: ExtensionAPI!

    // Exposed so TASK 2's drag (and headless tests) can reach the handle/filler/panel elements.
    public internal(set) var _displayables = SliderZoomDisplayables()

    var _orient: String = HORIZONTAL

    var _range: [Double] = [0, 100]

    // [coord of the first handle, coord of the second handle]
    var _handleEnds: [Double] = [0, 0]

    // [length, thick]
    var _size: [Double] = [0, 0]

    // Brush-select state (upstream `_brushing` / `_brushStart` / `_brushStartTime`; consumed by the
    // brush handlers in SliderZoomViewDrag.swift — the HOST forwards zr mousemove/mouseup while brushing).
    var _brushing = false
    var _brushStart: (x: Double, y: Double)?
    var _brushStartTime: Double = 0

    // Drag state (consumed by the drag slice in SliderZoomViewDrag.swift).
    var _dragging: Bool = false
    var _isOverDataInfoTriggerArea: Bool = false

    private var _handleWidth: Double = 0

    private var _handleHeight: Double = 0

    // upstream `_location: PointLike` — split into two Doubles (no PointLike bag needed).
    private var _locationX: Double = 0
    private var _locationY: Double = 0

    // upstream init(ecModel, api) only caches `api` + binds `_onBrush`/`_onBrushEnd` (brush handlers,
    //   DEFERRED). ComponentView.init() already builds `group`/`uid`; nothing else needed at TASK 1.

    // render(dataZoomModel, ecModel, api, payload)
    open override func render(
        _ model: ComponentModel,
        _ ecModel: GlobalModel,
        _ api: ExtensionAPI,
        _ payload: Payload
    ) {
        // super.render.apply(this, arguments)  — DataZoomView.render caches the three refs.
        let dataZoomModel = model as! SliderZoomModel
        self.dataZoomModel = dataZoomModel
        self.ecModel = ecModel
        self.api = api

        // throttle.createOrUpdate(this, '_dispatchZoomAction', dataZoomModel.get('throttle'), 'fixRate');
        //   DEFERRED (TASK 2 — dispatch throttling).

        self._orient = dataZoomModel.getOrient()

        // if (dataZoomModel.get('show') === false) { this.group.removeAll(); return; }
        if (dataZoomModel.get("show") as? Bool) == false {
            _ = self.group.removeAll()
            return
        }

        // if (dataZoomModel.noTarget()) { this._clear(); this.group.removeAll(); return; }
        if dataZoomModel.noTarget() {
            // this._clear();  — brush/zr listeners teardown (DEFERRED with brush).
            _ = self.group.removeAll()
            return
        }

        // Notice: this._resetInterval() should not be executed when payload.type is 'dataZoom' and it
        // originates from this same view (throttled self-dispatch). `payload.from` lives in `.other`.
        let payloadFrom = payload.other["from"] as? String
        if payload.type != "dataZoom" || payloadFrom != self.uid {
            self._buildView()
        }

        self._updateView()
    }

    private func _buildView() {
        let thisGroup = self.group

        _ = thisGroup.removeAll()

        // upstream: this._brushing = false; this._displayables.brushRect = null;
        self._brushing = false
        self._displayables.brushRect = nil

        self._resetLocation()
        self._resetInterval()

        let barGroup = Group()
        self._displayables.sliderGroup = barGroup

        self._renderBackground()

        self._renderHandle()

        self._renderDataShadow()

        _ = thisGroup.add(barGroup)

        self._positionGroup()
    }

    private func _resetLocation() {
        let dataZoomModel = self.dataZoomModel!
        let api = self.api!
        let showMoveHandle = jsTruthy(dataZoomModel.get("brushSelect"))
        let moveHandleSize = showMoveHandle ? DEFAULT_MOVE_HANDLE_SIZE : 0

        // const refContainer = layout.createBoxLayoutReference(dataZoomModel, api).refContainer;
        let refContainer = layout.createBoxLayoutReference(dataZoomModel, api).refContainer

        // If some of x/y/width/height are not specified, auto-adapt according to target grid.
        let coordRect = self._findCoordRect()
        // const edgeGap = dataZoomModel.get('defaultLocationEdgeGap', true) || 0;
        let edgeGap = dzNum(dataZoomModel.get("defaultLocationEdgeGap", true)) ?? 0

        // Default align by coordinate system rect. Keyed placeholder values ('ph').
        var positionInfo: [String: Double] = [:]
        if self._orient == HORIZONTAL {
            // Why using 'right': right should be used in vertical, and it is better to be consistent.
            positionInfo["right"] = refContainer.width - coordRect.x - coordRect.width
            positionInfo["top"] = refContainer.height - DEFAULT_FILLER_SIZE - edgeGap - moveHandleSize
            positionInfo["width"] = coordRect.width
            positionInfo["height"] = DEFAULT_FILLER_SIZE
        }
        else { // vertical
            positionInfo["right"] = edgeGap
            positionInfo["top"] = coordRect.y
            positionInfo["width"] = DEFAULT_FILLER_SIZE
            positionInfo["height"] = coordRect.height
        }

        // const layoutParams = layout.getLayoutParams(dataZoomModel.option);
        //   PORT-substitute: `getLayoutParams` (a copy of LOCATION_PARAMS off the raw option) is modeled by
        //   `getBoxLayoutParams(model, ignoreParent=false)`, which reads left/right/top/bottom/width/height.
        var layoutParams = layout.getBoxLayoutParams(dataZoomModel, false)

        // Replace the placeholder value ('ph') for right/top/width/height.
        if isPh(layoutParams.right) { layoutParams.right = positionInfo["right"]! }
        if isPh(layoutParams.top) { layoutParams.top = positionInfo["top"]! }
        if isPh(layoutParams.width) { layoutParams.width = positionInfo["width"]! }
        if isPh(layoutParams.height) { layoutParams.height = positionInfo["height"]! }

        // const layoutRect = layout.getLayoutRect(layoutParams, refContainer);
        let layoutRect = layout.getLayoutRect(layoutParams, refContainer)

        self._locationX = layoutRect.x
        self._locationY = layoutRect.y
        self._size = [layoutRect.width, layoutRect.height]
        // this._orient === VERTICAL && this._size.reverse();
        if self._orient == VERTICAL {
            self._size.reverse()
        }
    }

    private func _positionGroup() {
        let thisGroup = self.group
        let orient = self._orient

        // Just use the first axis to determine mapping.
        let targetAxisModel = self.dataZoomModel.getFirstTargetAxisModel()
        let inverse = jsTruthy(targetAxisModel?.get("inverse"))

        let sliderGroup = self._displayables.sliderGroup!
        // (this._dataShadowInfo || {}).otherAxisInverse — data shadow DEFERRED → always falsy.
        let otherAxisInverse = false

        // Transform barGroup (flip so the slider draws with the natural orientation).
        if orient == HORIZONTAL && !inverse {
            sliderGroup.scaleY = otherAxisInverse ? 1 : -1
            sliderGroup.scaleX = 1
        }
        else if orient == HORIZONTAL && inverse {
            sliderGroup.scaleY = otherAxisInverse ? 1 : -1
            sliderGroup.scaleX = -1
        }
        else if orient == VERTICAL && !inverse {
            sliderGroup.scaleY = otherAxisInverse ? -1 : 1
            sliderGroup.scaleX = 1
            sliderGroup.rotation = Double.pi / 2
        }
        else { // VERTICAL && inverse — don't use Math.PI, considering shadow direction.
            sliderGroup.scaleY = otherAxisInverse ? -1 : 1
            sliderGroup.scaleX = -1
            sliderGroup.rotation = Double.pi / 2
        }

        // Position barGroup
        let rect = thisGroup.getBoundingRect([sliderGroup])
        let rectX = rect.x.isNaN ? 0 : rect.x
        let rectY = rect.y.isNaN ? 0 : rect.y

        thisGroup.x = self._locationX - rectX
        thisGroup.y = self._locationY - rectY
        thisGroup.markRedraw()
    }

    func _getViewExtent() -> [Double] {
        return [0, self._size[0]]
    }

    private func _renderBackground() {
        let dataZoomModel = self.dataZoomModel!
        let size = self._size
        let barGroup = self._displayables.sliderGroup!

        var bgShape = RectShape()
        bgShape.x = 0
        bgShape.y = 0
        bgShape.width = size[0]
        bgShape.height = size[1]
        let bg = Rect(["shape": bgShape as PathShape])
        bg.silent = true
        bg.pathStyle.fill = dzColor(dataZoomModel.get("backgroundColor"))
        bg.z2 = -40
        _ = barGroup.add(bg)

        // Click panel, over shadow, below handles.
        var panelShape = RectShape()
        panelShape.x = 0
        panelShape.y = 0
        panelShape.width = size[0]
        panelShape.height = size[1]
        let clickPanel = Rect(["shape": panelShape as PathShape])
        clickPanel.pathStyle.fill = .string("transparent")
        clickPanel.z2 = 0
        // upstream: onclick: bind(this._onClickPanel, this) — click recenters the window; and when
        //   brushSelect, `clickPanel.on('mousedown', this._onBrushStart)` + crosshair cursor starts a
        //   brush (the zr-level mousemove/mouseup legs are forwarded by the HOST — EChartsView, which
        //   owns the live zr; SliderZoomView.ts:346-355 binds them directly upstream).
        _ = clickPanel.on("click", { [weak self] _, args in
            guard let self = self, let e = args.first as? ZRenderKit.ElementEvent,
                  let local = self._displayables.sliderGroup?.transformCoordToLocal(e.offsetX, e.offsetY)
            else { return nil }
            self._onClickPanel(local[0], local[1])
            return nil
        })
        if jsTruthy(self.dataZoomModel.get("brushSelect")) {
            clickPanel.cursor = "crosshair"
            _ = clickPanel.on("mousedown", { [weak self] _, args in
                guard let self = self, let e = args.first as? ZRenderKit.ElementEvent else { return nil }
                self._onBrushStart(e.offsetX, e.offsetY)
                return nil
            })
        }
        self._displayables.panel = clickPanel
        _ = barGroup.add(clickPanel)
    }

    private func _renderHandle() {
        let thisGroup = self.group
        let displayables = self._displayables
        displayables.handles = [nil, nil]
        displayables.handleLabels = [nil, nil]
        let sliderGroup = displayables.sliderGroup!
        let size = self._size
        let dataZoomModel = self.dataZoomModel!

        let borderRadius = dzNum(dataZoomModel.get("borderRadius")) ?? 0

        let brushSelect = jsTruthy(dataZoomModel.get("brushSelect"))

        // The `filler` selected-window band.
        let filler = Rect()
        filler.silent = brushSelect
        filler.pathStyle.fill = dzColor(dataZoomModel.get("fillerColor"))
        var fillerTextConfig = ElementTextConfig()
        fillerTextConfig.position = "inside"
        filler.textConfig = fillerTextConfig
        // Exposed + draggable for TASK 2 (the primary move target when brushSelect is false).
        filler.draggable = .true
        displayables.filler = filler
        _ = sliderGroup.add(filler)

        // Frame border.
        var frameShape = RectShape()
        frameShape.x = 0
        frameShape.y = 0
        frameShape.width = size[0]
        frameShape.height = size[1]
        frameShape.r = .number(borderRadius)
        let frame = Rect(["shape": frameShape as PathShape])
        frame.silent = true
        frame.subPixelOptimize = true
        // stroke: get('dataBackgroundColor') || get('borderColor') (deprecated alias first)
        let strokeColor = dataZoomModel.get("dataBackgroundColor") ?? dataZoomModel.get("borderColor")
        frame.pathStyle.stroke = dzColor(strokeColor)
        frame.pathStyle.lineWidth = DEFAULT_FRAME_BORDER_WIDTH
        frame.pathStyle.fill = .string(tokens.color.transparent)
        _ = sliderGroup.add(frame)

        // Left and right handle to resize.
        for handleIndex in 0..<2 {
            var iconStr = (dataZoomModel.get("handleIcon") as? String) ?? ""
            // Compatible with old icon parsers: a bare path string without `path://`.
            if symbol.symbolBuildProxies[iconStr] == nil
                && !iconStr.contains("path://")
                && !iconStr.contains("image://") {
                iconStr = "path://" + iconStr
            }
            // createSymbol returns the `ECSymbol` protocol; the concrete type is a `Path` (SymbolPath).
            let path = symbol.createSymbol(iconStr, -1, 0, 2, 2, nil, true) as! Path
            path.cursor = getCursor(self._orient)
            // upstream: handle.attr({ draggable: true, drift: bind(this._onDragMove, this, handleIndex),
            //   ondragend: bind(this._onDragEnd, this), ... }) — the resize-drag wiring.
            self._wireDrift(path, .at(handleIndex))
            _ = path.on("dragend", { [weak self] _, _ in self?._onDragEnd(); return nil })
            path.z2 = 5

            let bRect = path.getBoundingRect()!
            let handleSize = dataZoomModel.get("handleSize")

            self._handleHeight = number.parsePercent(handleSize, self._size[1])
            self._handleWidth = bRect.width / bRect.height * self._handleHeight

            path.useStyle(barStyleFromDict(dataZoomModel.getModel("handleStyle").getItemStyle()))
            path.pathStyle.strokeNoScale = true
            path.rectHover = true

            path.ensureState("emphasis").style =
                dataZoomModel.getModel(["emphasis", "handleStyle"]).getItemStyle()
            states.enableHoverEmphasis(path)

            // const handleColor = dataZoomModel.get('handleColor'); // deprecated — nil by default.
            if let handleColor = dataZoomModel.get("handleColor") {
                path.pathStyle.fill = dzColor(handleColor)
            }

            displayables.handles[handleIndex] = path
            _ = sliderGroup.add(path)

            // Handle label (start/end value text), invisible unless handleLabel.show.
            let textStyleModel = dataZoomModel.getModel("textStyle")
            let handleLabel = (dataZoomModel.get("handleLabel") as? [String: Any]) ?? [:]
            let handleLabelShow = jsTruthy(handleLabel["show"])

            var labelStyle = createTextStyle(
                textStyleModel,
                text: "",
                fill: textStyleModel.getTextColor(),
                align: .center,
                verticalAlign: .middle
            )
            labelStyle.x = 0
            labelStyle.y = 0
            let handleLabelText = ZRText(["style": labelStyle])
            handleLabelText.silent = true
            handleLabelText.invisible = !handleLabelShow
            handleLabelText.z2 = 10
            displayables.handleLabels[handleIndex] = handleLabelText
            _ = thisGroup.add(handleLabelText)
        }

        // Handle to move. Only visible when brushSelect is set true.
        if brushSelect {
            let moveHandleHeight = number.parsePercent(dataZoomModel.get("moveHandleSize"), size[1])
            var moveHandleShape = RectShape()
            moveHandleShape.r = .array([0, 0, 2, 2])
            moveHandleShape.y = size[1] - 0.5
            moveHandleShape.height = moveHandleHeight
            let moveHandle = Rect(["shape": moveHandleShape as PathShape])
            moveHandle.useStyle(barStyleFromDict(dataZoomModel.getModel("moveHandleStyle").getItemStyle()))
            moveHandle.silent = true
            displayables.moveHandle = moveHandle

            let iconSize = moveHandleHeight * 0.8
            let moveHandleIcon = symbol.createSymbol(
                (dataZoomModel.get("moveHandleIcon") as? String) ?? "",
                -iconSize / 2, -iconSize / 2, iconSize, iconSize,
                .string(tokens.color.neutral00),
                true
            ) as! Path
            moveHandleIcon.silent = true
            moveHandleIcon.y = size[1] + moveHandleHeight / 2 - 0.5
            displayables.moveHandleIcon = moveHandleIcon

            moveHandle.ensureState("emphasis").style =
                dataZoomModel.getModel(["emphasis", "moveHandleStyle"]).getItemStyle()

            let moveZoneExpandSize = Swift.min(size[1] / 2, Swift.max(moveHandleHeight, 10))
            var moveZoneShape = RectShape()
            moveZoneShape.y = size[1] - moveZoneExpandSize
            moveZoneShape.height = moveHandleHeight + moveZoneExpandSize
            let moveZone = Rect(["shape": moveZoneShape as PathShape])
            moveZone.invisible = true
            // actualMoveZone.on('mouseover'/'mouseout', enter/leaveEmphasis) — DEFERRED (TASK 2).
            moveZone.draggable = .true
            moveZone.cursor = "grab"
            displayables.moveZone = moveZone

            _ = sliderGroup.add(moveHandle)
            _ = sliderGroup.add(moveHandleIcon)
            _ = sliderGroup.add(moveZone)
        }

        // upstream: actualMoveZone.attr({ draggable: true, cursor, drift: bind(this._onDragMove, this,
        //   'all'), ondragend: bind(this._onDragEnd, this), ... }) — the pan-drag ('all') wiring on the
        //   moveZone when brushSelect, else on the filler. `draggable`/`cursor` set above.
        //   PORT-NOTE (deferred): ondragstart→_showDataInfo(true) + onmouseover/out label toggles stay
        //   deferred (_showDataInfo is a stub; handle-label data-info niceties path not yet ported).
        if let actualMoveZone: Element = brushSelect ? displayables.moveZone : displayables.filler {
            self._wireDrift(actualMoveZone, .all)
            _ = actualMoveZone.on("dragend", { [weak self] _, _ in self?._onDragEnd(); return nil })
        }
    }

    // upstream: _prepareDataShadowInfo() — pick the first target series (of a shadow-able type) whose
    //   value dimension will be previewed inside the slider track. Minimal port: no `showDataShadow`
    //   per-series override handling beyond the false short-circuit; returns (series, otherDim).
    private func _prepareDataShadowInfo() -> (series: SeriesModel, otherDim: String)? {
        let dataZoomModel = self.dataZoomModel!
        // showDataShadow === false disables the preview entirely.
        if (dataZoomModel.get("showDataShadow") as? Bool) == false { return nil }
        let showDataShadowForced = (dataZoomModel.get("showDataShadow") as? Bool) == true
        let shadowTypes: Set<String> = ["line", "bar", "candlestick", "scatter"]

        var result: (series: SeriesModel, otherDim: String)? = nil
        dataZoomModel.eachTargetAxis { axisDim, axisIndex in
            if result != nil { return }
            guard let proxy = dataZoomModel.getAxisProxy(axisDim, axisIndex) else { return }
            for seriesModel in proxy.getTargetSeriesModels() {
                if result != nil { break }
                if !showDataShadowForced && !shadowTypes.contains(seriesModel.subType) { continue }
                // getOtherDim: 'x'↔'y' (the value dimension previewed against the zoomed axis).
                let otherDimName = axisDim == "x" ? "y" : (axisDim == "y" ? "x" : "")
                guard !otherDimName.isEmpty,
                      let mapped = seriesModel.getData().mapDimension(otherDimName) else { continue }
                result = (seriesModel, mapped)
            }
        }
        return result
    }

    // upstream: _renderDataShadow(info) — draw a faint area+line preview of the target series' values
    //   across the slider track. The "selected" (clipped, darker) overlay is DEFERRED.
    private func _renderDataShadow() {
        guard let info = self._prepareDataShadowInfo() else { return }
        let dataZoomModel = self.dataZoomModel!
        let sliderGroup = self._displayables.sliderGroup!
        let size = self._size
        let data = info.series.getRawData()
        let otherDim = info.otherDim
        let n = data.count()
        if n < 2 { return }

        // Pad the value extent by 30% (upstream) so the preview never touches the track edges.
        var otherDataExtent = data.getDataExtent(otherDim)
        let otherOffset = (otherDataExtent[1] - otherDataExtent[0]) * 0.3
        otherDataExtent = [otherDataExtent[0] - otherOffset, otherDataExtent[1] + otherOffset]
        let otherShadowExtent = [0.0, size[1]]

        let step = size[0] / Double(n - 1)
        var thisCoord = 0.0
        var areaPoints: [VectorArray] = [VectorArray(size[0], 0), VectorArray(0, 0)]
        var linePoints: [VectorArray] = []
        for i in 0..<n {
            let raw = data.get(otherDim, i)
            let value = shadowNumber(raw)
            let otherCoord = value.isNaN
                ? 0
                : number.linearMap(value, otherDataExtent, otherShadowExtent, true)
            areaPoints.append(VectorArray(thisCoord, otherCoord))
            linePoints.append(VectorArray(thisCoord, otherCoord))
            thisCoord += step
        }

        let dataBackgroundModel = dataZoomModel.getModel("dataBackground")
        // Area polygon (dataBackground.areaStyle — read color/opacity directly so the fill is never the
        //   spurious black DEFAULT_PATH_STYLE default).
        let areaStyleModel = dataBackgroundModel.getModel("areaStyle")
        var areaShape = PolygonShape()
        areaShape.points = areaPoints
        let area = Polygon(["shape": areaShape as PathShape])
        area.silent = true
        area.pathStyle.fill = dzColor(areaStyleModel.get("color"))
        area.pathStyle.opacity = dzNum(areaStyleModel.get("opacity"))
        area.pathStyle.stroke = nil
        area.z2 = -20
        _ = sliderGroup.add(area)
        // Line polyline (dataBackground.lineStyle).
        let lineStyleModel = dataBackgroundModel.getModel("lineStyle")
        var lineShape = PolylineShape()
        lineShape.points = linePoints
        let line = Polyline(["shape": lineShape as PathShape])
        line.silent = true
        line.pathStyle.stroke = dzColor(lineStyleModel.get("color"))
        line.pathStyle.lineWidth = dzNum(lineStyleModel.get("width")) ?? 0.5
        line.pathStyle.fill = nil
        line.z2 = -19
        _ = sliderGroup.add(line)
    }

    private func _resetInterval() {
        // const range = this._range = this.dataZoomModel.getPercentRange();
        let range = self.dataZoomModel.getPercentRange() ?? [0, 100]
        self._range = range
        let viewExtent = self._getViewExtent()

        self._handleEnds = [
            number.linearMap(range[0], [0, 100], viewExtent, true),
            number.linearMap(range[1], [0, 100], viewExtent, true)
        ]
    }

    // `nonRealtime` (upstream _updateView(nonRealtime?)) only affects the animated-tween path, which is
    //   DEFERRED — the driver repositions synchronously, so it is ignored here.
    func _updateView(_ nonRealtime: Bool = false) {
        _ = nonRealtime
        let displayables = self._displayables
        let handleEnds = self._handleEnds
        let handleInterval = number.asc(Array(handleEnds))
        let size = self._size

        for handleIndex in 0..<2 {
            // Handles
            guard let handle = displayables.handles[handleIndex] else { continue }
            let handleHeight = self._handleHeight
            handle.scaleX = handleHeight / 2
            handle.scaleY = handleHeight / 2
            // Trick: a tiny offset so the default handle's end point aligns to the drag window.
            handle.x = handleEnds[handleIndex] + (handleIndex != 0 ? -1.0 : 1.0)
            handle.y = size[1] / 2 - handleHeight / 2
        }

        // Filler
        _ = displayables.filler?.setShape("x", handleInterval[0])
        _ = displayables.filler?.setShape("y", 0.0)
        _ = displayables.filler?.setShape("width", handleInterval[1] - handleInterval[0])
        _ = displayables.filler?.setShape("height", size[1])

        // Move handle
        if let moveHandle = displayables.moveHandle {
            _ = moveHandle.setShape("x", handleInterval[0])
            _ = moveHandle.setShape("width", handleInterval[1] - handleInterval[0])
            _ = displayables.moveZone?.setShape("x", handleInterval[0])
            _ = displayables.moveZone?.setShape("width", handleInterval[1] - handleInterval[0])
            // Force update path on the invisible object.
            _ = displayables.moveZone?.getBoundingRect()
            displayables.moveHandleIcon?.x = handleInterval[0] + (handleInterval[1] - handleInterval[0]) / 2
        }

        // update clip path of shadow — DEFERRED (data shadow).

        self._updateDataInfo()
    }

    private func _updateDataInfo() {
        let dataZoomModel = self.dataZoomModel!
        let displayables = self._displayables
        let handleLabels = displayables.handleLabels
        let orient = self._orient
        var labelTexts = ["", ""]

        if jsTruthy(dataZoomModel.get("showDetail")) {
            let axisProxy = dataZoomModel.findRepresentativeAxisProxy()
            if let axisProxy = axisProxy, let axis = axisProxy.getAxisModel().axis as? Axis {
                let scale = axis.scale
                // Realtime path only: `window = axisProxy.getWindow()`.
                //   The non-realtime branch (`calculateDataWindow` + `getAlignTo`) fires only during a
                //   drag with `realtime: false` — DEFERRED to TASK 2.
                let window = axisProxy.getWindow()
                labelTexts = [
                    formatLabel(dataZoomModel, 0, window, scale),
                    formatLabel(dataZoomModel, 1, window, scale)
                ]
            }
        }

        let orderedHandleEnds = number.asc(Array(self._handleEnds))

        for handleIndex in 0..<2 {
            guard let handleParent = displayables.handles[handleIndex]?.parent,
                  let labelText = handleLabels[handleIndex] else { continue }
            // Text should not transform by barGroup — ignore the handles' transform.
            let barTransform = szGetTransform(handleParent, self.group)
            let direction = szTransformDirection(handleIndex == 0 ? "right" : "left", barTransform, false)
            let offset = self._handleWidth / 2 + LABEL_GAP
            let textPoint = szApplyTransformPoint(
                [
                    orderedHandleEnds[handleIndex] + (handleIndex == 0 ? -offset : offset),
                    self._size[1] / 2
                ],
                barTransform,
                false
            )

            var style = createTextStyle(
                dataZoomModel.getModel("textStyle"),
                text: labelTexts[handleIndex],
                fill: dataZoomModel.getModel("textStyle").getTextColor(),
                align: TextAlign(rawValue: orient == HORIZONTAL ? direction : "center"),
                verticalAlign: TextVerticalAlign(rawValue: orient == HORIZONTAL ? "middle" : direction)
            )
            style.x = textPoint[0]
            style.y = textPoint[1]
            labelText.useStyle(style)
        }
    }

    // upstream: private _findCoordRect(): RectLike
    private func _findCoordRect() -> RectLike {
        var rect: RectLike?

        let coordSysInfoList = collectReferCoordSysModelInfo(self.dataZoomModel).infoList
        if rect == nil && !coordSysInfoList.isEmpty {
            // const coordSys = coordSysInfoList[0].model.coordinateSystem;
            //   coord host models (grid/single/polar) carry `coordinateSystem` via CoordinateSystemHostModel.
            if let hostModel = coordSysInfoList[0].model as? CoordinateSystemHostModel {
                // rect = coordSys.getRect && coordSys.getRect();
                rect = hostModel.coordinateSystem?.getRect()
            }
        }

        if rect == nil {
            let width = self.api.getWidth()
            let height = self.api.getHeight()
            rect = BoundingRect(width * 0.2, height * 0.2, width * 0.6, height * 0.6)
        }

        return rect!
    }
}

// upstream: function formatLabel(dataZoomModel, extentIdx, window, scale): string
private func formatLabel(
    _ dataZoomModel: SliderZoomModel,
    _ extentIdx: Int,
    _ window: AxisProxyWindow,
    _ scale: Scale
) -> String {
    let labelFormatter = dataZoomModel.get("labelFormatter")

    // let labelPrecision = dataZoomModel.get('labelPrecision');
    // if (labelPrecision == null || labelPrecision === 'auto') { labelPrecision = window.valuePrecision; }
    var labelPrecision: Double
    let rawPrecision = dataZoomModel.get("labelPrecision")
    if rawPrecision == nil || rawPrecision is NSNull || (rawPrecision as? String) == "auto" {
        labelPrecision = window.valuePrecision
    }
    else {
        labelPrecision = dzNum(rawPrecision) ?? window.valuePrecision
    }

    // const value = window.value[extentIdx];
    let value = window.value.indices.contains(extentIdx) ? window.value[extentIdx] : Double.nan

    let valueStr: String
    if value.isNaN {
        valueStr = ""
    }
    else if helper.isOrdinalScale(scale) || helper.isTimeScale(scale) {
        valueStr = scale.getLabel(ScaleTick(value: value.rounded()))
    }
    else if labelPrecision.isFinite {
        valueStr = number.roundStr(value, labelPrecision)
    }
    else {
        valueStr = jsNumToString(value)
    }

    // isFunction(labelFormatter) ? labelFormatter(value, valueStr)
    //   : isString(labelFormatter) ? labelFormatter.replace('{value}', valueStr) : valueStr
    if let fn = labelFormatter as? ((Double, String) -> String) {
        return fn(value, valueStr)
    }
    if let template = labelFormatter as? String {
        return template.replacingOccurrences(of: "{value}", with: valueStr)
    }
    return valueStr
}

// upstream: function getCursor(orient) { return orient === 'vertical' ? 'ns-resize' : 'ew-resize'; }
private func getCursor(_ orient: String) -> String {
    return orient == VERTICAL ? "ns-resize" : "ew-resize"
}

// ---- port-local helpers (not in upstream) ----

// JS truthiness of an option-bag value.
private func jsTruthy(_ value: Any?) -> Bool {
    guard let value = value, !(value is NSNull) else { return false }
    if let b = value as? Bool { return b }
    if let n = value as? Double { return n != 0 && !n.isNaN }
    if let i = value as? Int { return i != 0 }
    if let s = value as? String { return !s.isEmpty }
    return true
}

// Int-vs-Double coercion for numeric option reads (defaultOptions box numbers as Int) — see MEMORY trap.
private func dzNum(_ value: Any?) -> Double? {
    if let d = value as? Double { return d }
    if let i = value as? Int { return Double(i) }
    if let f = value as? Float { return Double(f) }
    return nil
}

// Coerce a data-store cell to a Double (NaN for null / non-numeric) for the data-shadow preview.
private func shadowNumber(_ v: Any?) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    if let s = v as? String, let d = Double(s) { return d }
    return Double.nan
}

// `layout.getLayoutParams` placeholder value is the string 'ph' (see SliderZoomModel.defaultOption).
private func isPh(_ value: Any?) -> Bool {
    return (value as? String) == "ph"
}

// Bridge an option color value (String, or EChartsKit.ZRColor) to the ZRenderKit `ZRColor.string`.
//   (Solid colors only; gradient/pattern fill on the slider is out of scope.)
private func dzColor(_ value: Any?) -> ZRenderKit.ZRColor? {
    if let s = value as? String { return .string(s) }
    if let zr = value as? EChartsKit.ZRColor, case let .color(str) = zr { return .string(str) }
    return nil
}

// JS numeric stringify (`value + ''`): drop the trailing `.0` for integral values.
private func jsNumToString(_ d: Double) -> String {
    guard d.isFinite else { return "\(d)" }
    return d == d.rounded() ? String(Int(d)) : String(d)
}

// ============================================================================
// PORT helpers reproducing `util/graphic` transform utilities (mirrors ContinuousView.swift). Delete
// each when its real sibling lands and call the sibling directly.
// ============================================================================

/// upstream `util/graphic.getTransform(target, ancestor)` — matrix from `target` up to (excluding) `ancestor`.
private func szGetTransform(_ target: Transformable?, _ ancestor: Transformable?) -> MatrixArray {
    var mat = matrix.identity()
    var t = target
    while let cur = t, cur !== ancestor {
        mat = matrix.mul(cur.getLocalTransform(), mat)
        t = cur.parent
    }
    return mat
}

/// upstream `util/graphic.applyTransform(target, transform, invert?)` — apply matrix (or its inverse) to a point.
private func szApplyTransformPoint(_ target: [Double], _ transform: MatrixArray, _ invert: Bool) -> [Double] {
    var m = transform
    if invert {
        m = matrix.invert(m) ?? m
    }
    let r = vector.applyTransform(VectorArray(target[0], target[1]), m)
    return [r[0], r[1]]
}

/// upstream `util/graphic.transformDirection(direction, transform, invert?)`.
private func szTransformDirection(_ direction: String, _ transform: MatrixArray, _ invert: Bool) -> String {
    // Pick a base, ensure that transform result will not be (0, 0).
    let hBase = (transform[4] == 0 || transform[5] == 0 || transform[0] == 0)
        ? 1.0 : Swift.abs(2 * transform[4] / transform[0])
    let vBase = (transform[4] == 0 || transform[5] == 0 || transform[2] == 0)
        ? 1.0 : Swift.abs(2 * transform[4] / transform[2])

    var vertex: [Double] = [
        direction == "left" ? -hBase : direction == "right" ? hBase : 0,
        direction == "top" ? -vBase : direction == "bottom" ? vBase : 0
    ]
    vertex = szApplyTransformPoint(vertex, transform, invert)

    return Swift.abs(vertex[0]) > Swift.abs(vertex[1])
        ? (vertex[0] > 0 ? "right" : "left")
        : (vertex[1] > 0 ? "bottom" : "top")
}

// export default SliderZoomView;  -> `open class SliderZoomView` above.
