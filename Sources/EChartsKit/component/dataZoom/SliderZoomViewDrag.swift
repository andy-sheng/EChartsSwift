// Ported from echarts/src/component/dataZoom/SliderZoomView.ts — keep in sync with upstream
// (drag-interaction slice: `_updateInterval` / `_onDragMove` / `_onDragEnd` / `_onClickPanel` /
//  `_dispatchZoomAction`, plus the drift-wiring helper). The rendering half — `render` / `_renderHandle` /
//  `_updateView` / `_updateDataInfo` / layout / `_getViewExtent` — lives in TASK 1's `SliderZoomView.swift`.
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

// ============================================================================
// TASK 1 (`SliderZoomView`) SURFACE consumed by this drag slice.
// These stored properties / methods must be declared on `SliderZoomView` (matching upstream):
//   - var dataZoomModel: SliderZoomModel
//   - var api: ExtensionAPI                          // stored during `render`
//   - var uid: String                                // ComponentView.uid (set in init) — used as `from`
//   - var _range: [Double]                           // percent range [start, end], 0..100
//   - var _handleEnds: [Double]                      // the two handle positions in the slider pixel extent
//   - var _size: [Double]                            // [width, height] in slider-local coords
//   - var _dragging: Bool
//   - var _isOverDataInfoTriggerArea: Bool
//   - var _displayables: SliderDisplayables          // must expose `sliderGroup: Group`,
//                                                     //   `handles: [Path]` (0/1), `filler: Rect`
//   - func _getViewExtent() -> [Double]              // returns [0, _size[0]]
//   - func _updateView(_ nonRealtime: Bool)          // repositions handles/filler/labels
//   - func _showDataInfo(_ isEmphasis: Bool)         // toggles handle-label visibility (used by _onDragEnd)
// If TASK 1 names these differently, the Integrator reconciles at merge.
// ============================================================================

// upstream: const REALTIME_ANIMATION_CONFIG = { easing: 'cubicOut', duration: 100, delay: 0 } as const;
private let REALTIME_ANIMATION_CONFIG: PayloadAnimationPart = {
    var p = PayloadAnimationPart()
    p.easing = .named("cubicOut")
    p.duration = 100
    p.delay = 0
    return p
}()

// upstream constant (SliderZoomView.ts): const HORIZONTAL = 'horizontal';
private let HORIZONTAL = "horizontal"

extension SliderZoomView {

    // ------------------------------------------------------------------------
    // Drag wiring — call from TASK 1's `render`/`_renderHandle`/`_renderDataShadow`
    // after the handle/filler elements are created, e.g.:
    //     _wireDrift(displayables.handles[0], .at(0))
    //     _wireDrift(displayables.handles[1], .at(1))
    //     _wireDrift(displayables.filler,     .all)
    // upstream sets these via `handle.attr({ draggable: true, drift: bind(this._onDragMove, this, handleIndex) })`.
    // Here we set `draggable = .true` + the `driftHandler` closure (the faithful seam for upstream's
    // assignable `drift` property; see Element.driftHandler). `[weak self]` breaks the
    // element → closure → view retain cycle (the view owns `_displayables`, which owns the element).
    // ------------------------------------------------------------------------
    public func _wireDrift(_ el: Element, _ handleIndex: SliderMoveHandleIndex) {
        el.draggable = .true
        // upstream wires the two resize handles (handleIndex 0/1) with `drift: _onDragMove` directly
        //   (SliderZoomView.ts:615-617), but the pan-drag element — `actualMoveZone`, handleIndex `all`,
        //   which is the `moveZone` when `brushSelect` else the `filler` — with the moveZone-specific
        //   `drift: _onActualMoveZoneDrift`, `ondragstart: _onActualMoveZoneDragStart`,
        //   `ondragend: _onActualMoveZoneDragEnd` (SliderZoomView.ts:712-718). Those add the
        //   'grabbing'/'grab' cursor swap and the `_showDataInfo(true)` reveal that the plain
        //   `_onDragMove` path lacks. `.all` is only ever wired for the actualMoveZone.
        switch handleIndex {
        case .all:
            el.driftHandler = { [weak self] dx, dy, e in
                self?._onActualMoveZoneDrift(dx, dy, e)
            }
            _ = el.on("dragstart", { [weak self, weak el] _, _ in
                self?._onActualMoveZoneDragStart(el as? Displayable); return nil
            })
            _ = el.on("dragend", { [weak self, weak el] _, _ in
                self?._onActualMoveZoneDragEnd(el as? Displayable); return nil
            })
        case .at:
            el.driftHandler = { [weak self] dx, dy, e in
                self?._onDragMove(handleIndex, dx, dy, e)
            }
        }
    }

    // upstream: _onActualMoveZoneDrift(dx, dy, event) — the pan-drag `drift` callback on the moveZone.
    //   Sets the global 'grabbing' cursor for the drag, then delegates to the shared `_onDragMove('all')`.
    public func _onActualMoveZoneDrift(_ dx: Double, _ dy: Double, _ event: ElementEvent?) {
        self.api.getZr()?.setCursorStyle("grabbing")
        self._onDragMove(.all, dx, dy, event)
    }

    // upstream: _onActualMoveZoneDragStart(event) — swap the dragged element's cursor to 'grabbing' and
    //   reveal the handle labels (emphasis) for the duration of the pan.
    //   `event.target as Displayable` upstream; here `_wireDrift` passes the wired element directly.
    public func _onActualMoveZoneDragStart(_ target: Displayable?) {
        target?.cursor = "grabbing"
        self._showDataInfo(true)
    }

    // upstream: _onActualMoveZoneDragEnd(event) — restore the 'grab' cursor and finish the drag.
    public func _onActualMoveZoneDragEnd(_ target: Displayable?) {
        target?.cursor = "grab"
        self._onDragEnd()
    }

    // upstream: _updateInterval(handleIndex: 0 | 1 | 'all', delta: number): boolean
    //   Given a drag delta (in slider-axis pixels), moves `_handleEnds` via `sliderMove` (clamped to
    //   the view extent + min/maxSpan), then recomputes `_range` (percents) from the handle ends.
    //   Returns whether the range actually changed.
    @discardableResult
    public func _updateInterval(_ handleIndex: SliderMoveHandleIndex, _ delta: Double) -> Bool {
        // IUO-bound-to-let infers Optional — annotate the type to force the unwrap (mechanical port trap).
        let dataZoomModel: SliderZoomModel = self.dataZoomModel
        // `sliderMove` mutates `handleEnds` in place; upstream mutates `this._handleEnds` directly (JS
        //   array ref). Swift arrays are value types, so copy → mutate → write back.
        var handleEnds = self._handleEnds
        let viewExtend = self._getViewExtent()
        let minMaxSpan = dataZoomModel.findRepresentativeAxisProxy()?.getMinMaxSpan()
        let percentExtent: [Double] = [0, 100]

        // upstream: dataZoomModel.get('zoomLock') ? 'all' : handleIndex
        let effectiveHandleIndex: SliderMoveHandleIndex =
            dzDragTruthy(dataZoomModel.get("zoomLock")) ? .all : handleIndex

        // minSpan/maxSpan are percents in the option; map to the pixel view extent (clamp = true).
        // upstream: minMaxSpan.minSpan != null ? linearMap(minMaxSpan.minSpan, percentExtent, viewExtend, true) : null
        var minSpanPx: Double? = nil
        var maxSpanPx: Double? = nil
        if let mms = minMaxSpan {
            if let ms = mms.minSpan { minSpanPx = number.linearMap(ms, percentExtent, viewExtend, true) }
            if let xs = mms.maxSpan { maxSpanPx = number.linearMap(xs, percentExtent, viewExtend, true) }
        }

        sliderMove(
            delta,
            &handleEnds,
            viewExtend,
            effectiveHandleIndex,
            minSpanPx,
            maxSpanPx
        )
        self._handleEnds = handleEnds

        let lastRange = self._range
        // upstream: asc([linearMap(handleEnds[0], viewExtend, percentExtent, true), linearMap(handleEnds[1], ...)])
        let range = number.asc([
            number.linearMap(handleEnds[0], viewExtend, percentExtent, true),
            number.linearMap(handleEnds[1], viewExtend, percentExtent, true)
        ])
        self._range = range

        // upstream: return !lastRange || lastRange[0] !== range[0] || lastRange[1] !== range[1];
        //   (`_range` is non-optional here after init, so the `!lastRange` arm is unreachable —
        //    handled by an empty-guard for the very first drag before `_resetInterval`.)
        if lastRange.count < 2 { return true }
        return lastRange[0] != range[0] || lastRange[1] != range[1]
    }

    // upstream: _onDragMove(handleIndex, dx, dy, event) — the `drift` callback.
    //   Converts the global pixel drift (dx, dy) into the slider group's local axis, updates the
    //   interval, re-positions the view, and (in realtime mode) dispatches the zoom action.
    public func _onDragMove(_ handleIndex: SliderMoveHandleIndex, _ dx: Double, _ dy: Double, _ event: ElementEvent?) {
        self._dragging = true

        // For mobile device, prevent screen slider on the button.  upstream: eventTool.stop(event.event)
        event?.stop?()

        // Transform dx, dy to bar coordination.
        // upstream: const barTransform = this._displayables.sliderGroup.getLocalTransform();
        //           const vertex = graphic.applyTransform([dx, dy], barTransform, true);   // invert = true
        let barTransform = self._displayables.sliderGroup?.getLocalTransform()
        let vertex = dzApplyTransform([dx, dy], barTransform, true)

        let changed = self._updateInterval(handleIndex, vertex[0])

        let realtime = dzDragTruthy(self.dataZoomModel.get("realtime"))

        self._updateView(!realtime)

        // Avoid dispatch dataZoom repeatly but range not changed,
        // which cause bad visual effect when progressive enabled.
        if changed && realtime {
            // Throttled realtime dispatch (upstream wraps `_dispatchZoomAction` in throttle.createOrUpdate;
            //   see the slot in SliderZoomView.render). Coalesces a fast drag's per-mousemove re-renders to
            //   one per `throttle` ms so the main thread isn't saturated. Falls back to a direct dispatch if
            //   the wrapper wasn't installed (throttle rate nil).
            if let throttled = self._dispatchZoomActionThrottled {
                throttled()
            } else {
                self._dispatchZoomAction(true)
            }
        }
    }

    // upstream: _onDragEnd() — clears the drag flag and, in non-realtime mode, dispatches once at drag end.
    // Wire from TASK 1's handle/filler `ondragend` (or the drag-end seam) if separate drag-end events exist.
    public func _onDragEnd() {
        self._dragging = false

        if !self._isOverDataInfoTriggerArea {
            // Drag end may occur on draggable bars, where data info should be still shown.
            self._showDataInfo(false)
        }

        // While in realtime mode and stream mode, dispatch action when
        // drag end will cause the whole view rerender, which is unnecessary.
        let realtime = dzDragTruthy(self.dataZoomModel.get("realtime"))
        if !realtime {
            self._dispatchZoomAction(false)
        }
    }

    // upstream: _onClickPanel(e) — a click on the slider panel recenters the window on the click point.
    //   `sliderGroup.transformCoordToLocal` maps the global click into slider-local coords.
    // `transformCoordToLocal` (invert-transform of the global point) is a ported Group helper
    //   (ZRenderKit Transformable). The caller (the panel click seam) supplies the already-localized
    //   point, so `_onClickPanel` recenters the window on the click point (the drag handles remain the
    //   primary interaction; the click-panel is a convenience).
    public func _onClickPanel(_ localX: Double, _ localY: Double) {
        let size = self._size

        // upstream computes localPoint via sliderGroup.transformCoordToLocal(e.offsetX, e.offsetY);
        //   here the caller (TASK 1's click seam) supplies the already-localized point.
        if localX < 0 || localX > size[0] || localY < 0 || localY > size[1] {
            return
        }

        let handleEnds = self._handleEnds
        let center = (handleEnds[0] + handleEnds[1]) / 2

        let changed = self._updateInterval(.all, localX - center)
        self._updateView(false)
        if changed {
            self._dispatchZoomAction(false)
        }
    }

    // upstream: _dispatchZoomAction(realtime) — dispatch the Phase-32 `dataZoom` action with the new
    //   start/end percents. This re-filters + re-renders (the action handler calls `setRawRange`).
    //   NOTE (throttle): upstream comments "This action will be throttled." The throttle wrapper
    //   (`throttle`/`createOrUpdate` on `_dispatchZoomAction`) is a TODO: requires
    //   `throttleUtil.createOrUpdate` (not ported) — here we dispatch directly. Faithful semantics
    //   otherwise; only the frame-coalescing is deferred.
    public func _dispatchZoomAction(_ realtime: Bool) {
        let range = self._range

        var payload = Payload(type: "dataZoom")
        // upstream fields on the dispatched action object:
        //   { type, from: this.uid, dataZoomId: this.dataZoomModel.id, animation, start, end }
        payload.other["from"] = self.uid
        payload.other["dataZoomId"] = self.dataZoomModel.id
        payload.other["start"] = range[0]
        payload.other["end"] = range[1]
        // upstream: animation: realtime ? REALTIME_ANIMATION_CONFIG : null
        payload.animation = realtime ? REALTIME_ANIMATION_CONFIG : nil

        self.api.dispatchAction(payload, nil)
    }

    // ------------------------------------------------------------------------
    // Brush select (upstream SliderZoomView.ts:987-1086). `_onBrushStart` fires from the clickPanel's
    //   element mousedown; the mousemove/mouseup legs are zr-level listeners upstream — here the HOST
    //   (EChartsView, which owns the live zr) forwards them to `_onBrush`/`_onBrushEnd` while
    //   `_brushing` is set.
    // ------------------------------------------------------------------------

    // upstream: _onBrushStart(e) — record the down point and arm the brush.
    public func _onBrushStart(_ x: Double, _ y: Double) {
        self._brushStart = (x: x, y: y)
        self._brushing = true
        self._brushStartTime = Date().timeIntervalSince1970 * 1000
        // this._updateBrushRect(x, y);  (upstream keeps this commented too)
    }

    // upstream: _onBrush(e) — grow the rubber band while armed.
    public func _onBrush(_ x: Double, _ y: Double) {
        if self._brushing {
            // upstream also `eventTool.stop(e.event)` (mobile scroll suppression) — no-op here.
            self._updateBrushRect(x, y)
        }
    }

    // upstream: _onBrushEnd(e) — commit the brushed span as the new window.
    public func _onBrushEnd() {
        if !self._brushing {
            return
        }

        let brushRect = self._displayables.brushRect
        self._brushing = false

        guard let brushRect = brushRect else {
            return
        }

        brushRect.ignore = true

        guard let brushShape = brushRect.shape as? RectShape else { return }

        let brushEndTime = Date().timeIntervalSince1970 * 1000
        if brushEndTime - self._brushStartTime < 200 && Swift.abs(brushShape.width) < 5 {
            // Will treat it as a click
            return
        }

        let viewExtend = self._getViewExtent()
        let percentExtent: [Double] = [0, 100]

        var handleEnds = [brushShape.x, brushShape.x + brushShape.width]
        let minMaxSpan = self.dataZoomModel.findRepresentativeAxisProxy()?.getMinMaxSpan()
        // Restrict range.
        var minSpanPx: Double? = nil
        var maxSpanPx: Double? = nil
        if let mms = minMaxSpan {
            if let ms = mms.minSpan { minSpanPx = number.linearMap(ms, percentExtent, viewExtend, true) }
            if let xs = mms.maxSpan { maxSpanPx = number.linearMap(xs, percentExtent, viewExtend, true) }
        }
        sliderMove(0, &handleEnds, viewExtend, .at(0), minSpanPx, maxSpanPx)
        self._handleEnds = handleEnds

        self._range = number.asc([
            number.linearMap(handleEnds[0], viewExtend, percentExtent, true),
            number.linearMap(handleEnds[1], viewExtend, percentExtent, true)
        ])

        self._updateView(false)

        self._dispatchZoomAction(false)
    }

    // upstream: _updateBrushRect(mouseX, mouseY) — lazily build the rubber-band Rect (brushStyle) and
    //   stretch it from the down point to the cursor in slider-local coords.
    func _updateBrushRect(_ mouseX: Double, _ mouseY: Double) {
        let displayables = self._displayables
        let dataZoomModel: SliderZoomModel = self.dataZoomModel
        var brushRect = displayables.brushRect
        if brushRect == nil {
            let rect = Rect()
            rect.silent = true
            rect.useStyle(barStyleFromDict(dataZoomModel.getModel("brushStyle").getItemStyle()))
            displayables.brushRect = rect
            brushRect = rect
            _ = displayables.sliderGroup?.add(rect)
        }

        brushRect!.ignore = false

        guard let brushStart = self._brushStart, let sliderGroup = displayables.sliderGroup else { return }

        let endPoint = sliderGroup.transformCoordToLocal(mouseX, mouseY)
        let startPoint = sliderGroup.transformCoordToLocal(brushStart.x, brushStart.y)

        let size = self._size
        let endX = Swift.max(Swift.min(size[0], endPoint[0]), 0)

        var shape = RectShape()
        shape.x = startPoint[0]
        shape.y = 0
        shape.width = endX - startPoint[0]
        shape.height = size[1]
        _ = brushRect!.setShape(shape)
    }
}

// ---- local helpers (file-private) ----------------------------------------------------------------

// upstream: graphic.applyTransform(target, transform, invert) — util/graphic.ts.
//   With `invert = true`, invert the matrix first, then `vector.applyTransform`.
private func dzApplyTransform(_ target: [Double], _ transform: MatrixArray?, _ invert: Bool) -> [Double] {
    // nil transform (slider group not yet laid out / identity) → no-op map.
    guard var m: MatrixArray = transform else { return target }
    if invert {
        // upstream: matrix.invert([], transform). A singular matrix returns undefined in zrender; here
        //   `matrix.invert` returns nil → fall back to identity (no transform), matching a no-op drift map.
        m = matrix.invert(m) ?? [1, 0, 0, 1, 0, 0]
    }
    // `VectorArray` is `SIMD2<Double>`; adapt the [Double] pair in/out.
    let out = vector.applyTransform(VectorArray(target[0], target[1]), m)
    return [out[0], out[1]]
}

// JS truthiness for a model-read option value (ModelOption == Any). Mirrors `dataZoomModel.get('realtime')`
//   / `get('zoomLock')` used in boolean position: nil/false/0/""/NaN → false; otherwise true.
private func dzDragTruthy(_ v: Any?) -> Bool {
    guard let v = v, !(v is NSNull) else { return false }
    if let b = v as? Bool { return b }
    if let i = v as? Int { return i != 0 }
    if let d = v as? Double { return d != 0 && !d.isNaN }
    if let s = v as? String { return !s.isEmpty }
    return true
}
