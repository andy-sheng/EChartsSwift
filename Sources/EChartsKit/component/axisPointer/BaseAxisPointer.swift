// Ported from echarts/src/component/axisPointer/BaseAxisPointer.ts — keep in sync with upstream
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

// upstream imports (resolved to the ported modules):
// import * as zrUtil from 'zrender/src/core/util';                 -> util.* (clone/curry — see notes)
// import * as graphic from '../../util/graphic';                   -> ZRenderKit Group / Line / Rect / ZRText + EChartsKit `createIcon`
// import * as axisPointerModelHelper from './modelHelper';         -> modelHelper.swift (getAxisInfo)
// import * as eventTool from 'zrender/src/core/event';             -> ZRenderKit `eventTool.stop` (handle onmousemove)
// import * as throttleUtil from '../../util/throttle';             -> util/throttle.swift (createOrUpdate / clear)
// import {makeInner} from '../../util/model';                      -> see PORT-NOTE (inner store) below
// import { AxisPointer } from './AxisPointer';                     -> AxisPointer.swift (same module)
// import { AxisBaseModel } from '../../coord/AxisBaseModel';       -> coord/AxisBaseModel.swift
// import ExtensionAPI from '../../core/ExtensionAPI';              -> core/ExtensionAPI.swift
// import Displayable, Element, Model, ...                          -> ZRenderKit / model/Model.swift
// import { calcBandWidth } from '../../coord/axisBand';            -> coord/axisBand.swift

// PORT-NOTE (makeInner): upstream stashes the built `pointerEl` / `labelEl` on the GROUP instance via
//   `makeInner<{ lastProp, labelEl, pointerEl }, Element>()`. Each `BaseAxisPointer` owns EXACTLY ONE
//   group, so those slots are held as plain instance members (`_pointerEl` / `_labelEl`) here — the
//   group identity is 1:1 with `self`, so this is behaviourally identical and avoids porting the
//   weak-map `makeInner` machinery. The `lastProp` animation-optimize slot is dropped (see `updateProps`).

// upstream:
//   type AxisValue = CommonAxisPointerOption['value'];        -> `Any?` (ScaleDataValue = number|string|Date)
//   type AxisPointerModel = Model<CommonAxisPointerOption>;   -> `Model` (the untyped model bag)

/// upstream: `export interface AxisPointerElementOptions { graphicKey; pointer; label }`.
///
/// The `{pointer, label, graphicKey}` bag the concrete `makeElOption` (TASK 1 — `CartesianAxisPointer`)
/// fills, and that `BaseAxisPointer._create*El` / `_update*El` consume. Upstream's `pointer` is
/// `PathProps & { type }` and `label` is `TextProps`; modeled here as small typed structs so the
/// build seam is explicit (the loose `[String: Any]` prop bag would lose the `type` discriminator).
public struct AxisPointerElementOptions {

    /// Enables changing axis-pointer type: when it differs from the last render, the group is cleared.
    /// upstream sets it to `pointerOption.type` ('Line' / 'Rect' / ...).
    public var graphicKey: String = ""

    /// The crosshair PATH (a `Line` for `type:'line'`, a `Rect` for `type:'shadow'`). `nil` when
    /// `axisPointer.type === 'none'` (upstream leaves `elOption.pointer` undefined).
    public var pointer: PointerElementOption?

    /// The axis LABEL (a `ZRText`). Always built for a shown pointer.
    public var label: LabelElementOption?

    public init() {}
}

/// upstream: `pointer: PathProps & { type: 'Line' | 'Rect' | 'Circle' | 'Sector' }`.
public struct PointerElementOption {
    /// The ZRenderKit shape class name — 'Line' / 'Rect' (Circle / Sector are PORT-NOTE, unused by
    /// `CartesianAxisPointer`). Selects `graphic[type]` in `createPointerEl`.
    public var type: String
    /// The typed path shape (`LineShape` / `RectShape`) built by `viewHelper.makeLineShape` / `makeRectShape`.
    public var shape: PathShape?
    /// The stroke/fill style built by `viewHelper.buildElStyle`.
    public var style: PathStyleProps?
    /// upstream `subPixelOptimize: true` on the line pointer.
    public var subPixelOptimize: Bool = false

    public init(type: String, shape: PathShape? = nil, style: PathStyleProps? = nil, subPixelOptimize: Bool = false) {
        self.type = type
        self.shape = shape
        self.style = style
        self.subPixelOptimize = subPixelOptimize
    }
}

/// upstream: `label: TextProps` (with `x`, `y`, `style`, `z2`). Built by `viewHelper.buildLabelElOption`.
public struct LabelElementOption {
    public var x: Double = 0
    public var y: Double = 0
    public var style: TextStyleProps?
    /// upstream `z2: 10` — "Label should be over axisPointer."
    public var z2: Double = 10

    public init(x: Double = 0, y: Double = 0, style: TextStyleProps? = nil, z2: Double = 10) {
        self.x = x
        self.y = y
        self.style = style
        self.z2 = z2
    }
}

/// Base axis pointer class in 2D.
///
/// upstream: `class BaseAxisPointer implements AxisPointer`. Subclassed by `CartesianAxisPointer`
///   (TASK 1) which overrides `makeElOption` → `open class` (CONVENTIONS §2/§4).
///
/// HOST SEAM (documented deviation): upstream `render` calls `api.getZr().add(group)` to host the
///   crosshair on the LIVE zr, and `clear` calls `zr.remove(group)`. In THIS port the ported
///   `ExtensionAPI` has no `getZr()` (there is no live axis view hosting pointers at render time), so
///   the pointer manager does NOT reach the zr itself. Instead it EXPOSES its crosshair `group` and
///   invokes the `hostAdd` / `hostRemove` seam closures at exactly the points upstream touches the zr,
///   so `EChartsView` (the integrator) can add/remove the group on its live `zr`. See `group`,
///   `hostAdd`, `hostRemove`, `hide()`.
open class BaseAxisPointer: AxisPointer {

    // upstream: private _group: graphic.Group;
    //   HOST SEAM: exposed read-only so the integrator (EChartsView) can add it to the live zr.
    public private(set) var group: Group?

    // upstream: private _lastGraphicKey: string;
    private var _lastGraphicKey: String?

    // upstream: private _handle: Icon;  (Icon = ReturnType<typeof graphic.createIcon> = SVGPath | ZRImage)
    //   The draggable handle element. `nil` until `_renderHandle` builds it (handle.show + status show).
    //   Exposed read-only as `handleEl` so a headless test can assert it was created / read its position.
    private var _handle: Displayable?

    // upstream: private _dragging = false;
    private var _dragging = false

    // upstream: private _lastValue: AxisValue;
    private var _lastValue: Any?

    // upstream: private _lastStatus: CommonAxisPointerOption['status'];
    private var _lastStatus: Any?

    // upstream: private _payloadInfo: ReturnType<BaseAxisPointer['updateHandleTransform']>;
    //   The last `updateHandleTransform` result (new handle pos + cursorPoint + tooltipOption), persisted
    //   for the throttled `_doDispatchAxisPointer` to read.
    private var _payloadInfo: AxisPointerUpdatedHandleTransform?

    // upstream stamps a throttled wrapper over `this._doDispatchAxisPointer` via
    //   `throttleUtil.createOrUpdate(this, '_doDispatchAxisPointer', ...)`. Swift can't swap a method on
    //   a live instance, so the wrapper lives in this slot (see util/throttle.swift createOrUpdate
    //   PORT-NOTE). `nil` means "call `_doDispatchAxisPointer` directly".
    private var _doDispatchThrottled: ThrottledFunction?

    /// If have transition animation.
    // upstream: private _moveAnimation: boolean;
    //   PORT-NOTE (animation): computed by `determineAnimation` but NOT consumed for a real animated
    //   slide — `updateProps` sets position directly (see the `_moveAnimation` note there). Kept so the
    //   determination logic stays faithful and a future animated port can wire it.
    private var _moveAnimation = false

    // upstream: private _axisModel / _axisPointerModel / _api (bound in render).
    private var _axisModel: AxisBaseModel?
    private var _axisPointerModel: Model?
    private var _api: ExtensionAPI?

    // 1:1 group children (see makeInner PORT-NOTE).
    private var _pointerEl: Path?
    private var _labelEl: ZRText?

    /// In px, arbitrary value. Do not set too small, no animation is ok for most cases.
    // upstream: protected animationThreshold = 15;
    open var animationThreshold: Double = 15

    // -----------------------------------------------------------------------------------------------
    // HOST SEAM closures (see the HOST SEAM note on the class). Set by the integrator (EChartsView).
    // -----------------------------------------------------------------------------------------------
    /// Invoked when the crosshair `group` is first created — upstream analog `api.getZr().add(group)`.
    public var hostAdd: ((Group) -> Void)?
    /// Invoked from `clear` before the group is dropped — upstream analog `zr.remove(group)`.
    public var hostRemove: ((Group) -> Void)?
    /// Invoked when the draggable `_handle` is first created — upstream analog `zr.add(handle)` (the
    ///   handle is hosted DIRECTLY on the zr, NOT inside the crosshair group, so it needs its own seam).
    public var hostAddHandle: ((Element) -> Void)?
    /// Invoked before the `_handle` is dropped (`_renderHandle` hide-branch / `clear`) — `zr.remove(handle)`.
    public var hostRemoveHandle: ((Element) -> Void)?

    /// HOST-SEAM read accessor (deviation): the draggable handle element, exposed so the integrator /
    ///   a headless test can hit-test or inspect it. `nil` until `_renderHandle` builds it.
    public var handleEl: Displayable? { self._handle }

    public init() {}

    /// @implement
    // upstream: render(axisModel, axisPointerModel, api, forceRender?)
    open func render(
        _ axisModel: AxisBaseModel,
        _ axisPointerModel: Model,
        _ api: ExtensionAPI,
        _ forceRender: Bool = false
    ) {
        let value = axisPointerModel.get("value")
        let status = axisPointerModel.get("status")

        // Bind them to `this`, not in closure, otherwise they will not
        // be replaced when user calling setOption in not merge mode.
        self._axisModel = axisModel
        self._axisPointerModel = axisPointerModel
        self._api = api

        // Optimize: `render` will be called repeatedly during mouse move.
        // So it is power consuming if performing `render` each time,
        // especially on mobile device.
        if !forceRender
            && _axisValueEqual(self._lastValue, value)
            && _axisValueEqual(self._lastStatus, status) {
            return
        }
        self._lastValue = value
        self._lastStatus = status

        // upstream: `const handle = this._handle;`
        let handle = self._handle

        // upstream: `if (!status || status === 'hide')`. `!status` ⟷ `_isFalsy` (null/''/false/0).
        if _isFalsy(status) || (status as? String) == "hide" {
            // Do not clear here, for animation better.
            self.group?.hide()
            handle?.hide()
            return
        }
        self.group?.show()
        handle?.show()

        // Otherwise status is 'show'
        var elOption = AxisPointerElementOptions()
        self.makeElOption(&elOption, value, axisModel, axisPointerModel, api)

        // Enable change axis pointer type.
        let graphicKey = elOption.graphicKey
        if graphicKey != self._lastGraphicKey {
            self.clear(api)
        }
        self._lastGraphicKey = graphicKey

        self._moveAnimation = self.determineAnimation(axisModel, axisPointerModel)

        if self.group == nil {
            let group = Group()
            self.group = group
            self.createPointerEl(group, elOption, axisModel, axisPointerModel)
            self.createLabelEl(group, elOption, axisModel, axisPointerModel)
            // upstream: api.getZr().add(group). HOST SEAM — hand the group to the integrator's zr.
            self.hostAdd?(group)
        }
        else {
            // upstream: `const doUpdateProps = zrUtil.curry(updateProps, axisPointerModel, moveAnimation)`.
            //   The `updateProps` closure is `(el, props)`; the `animationModel`/`moveAnimation` capture
            //   is inert here (no animated slide — see the free `updateProps` PORT-NOTE).
            self.updatePointerEl(self.group!, elOption)
            self.updateLabelEl(self.group!, elOption, axisPointerModel)
        }

        updateMandatoryProps(self.group, axisPointerModel, true)

        // upstream: this._renderHandle(value);
        self._renderHandle(value)
    }

    /// @implement
    // upstream: remove(api) { this.clear(api); }
    open func remove(_ api: ExtensionAPI) {
        self.clear(api)
    }

    /// @implement
    // upstream: dispose(api) { this.clear(api); }
    open func dispose(_ api: ExtensionAPI) {
        self.clear(api)
    }

    /// HOST-SEAM convenience (deviation): hide the crosshair without tearing it down. Mirrors upstream's
    /// `render` "status hide" branch (`group.hide()`); the integrator calls this on pointer `leave` so
    /// the crosshair vanishes but the built elements are kept for the next hover (matches upstream's
    /// "Do not clear here, for animation better.").
    open func hide() {
        self.group?.hide()
    }

    /// @protected
    // upstream: determineAnimation(axisModel, axisPointerModel): boolean
    open func determineAnimation(_ axisModel: AxisBaseModel, _ axisPointerModel: Model) -> Bool {
        let animation = axisPointerModel.get("animation")
        // PROTOCOL-WITNESS / narrowing trap: `axisModel.axis` is typed `Any` on AxisBaseModel; narrow to
        //   the concrete `Axis` to read `type` / `getExtent` (and pass to `calcBandWidth`).
        guard let axis = axisModel.axis as? Axis else {
            return false
        }
        let isCategoryAxis = (axis.type as String?) == "category"
        let useSnap = _isTruthy(axisPointerModel.get("snap"))

        // Value axis without snap always do not snap.
        if !useSnap && !isCategoryAxis {
            return false
        }

        // upstream: `if (animation === 'auto' || animation == null)`.
        if (animation as? String) == "auto" || animation == nil || animation is NSNull {
            let animationThreshold = self.animationThreshold
            if isCategoryAxis && calcBandWidth(axis).w > animationThreshold {
                return true
            }

            // It is important to auto animation when snap used. Consider if there is
            // a dataZoom, animation will be disabled when too many points exist, while
            // it will be enabled for better visual effect when little points exist.
            if useSnap {
                let seriesDataCount = Double(getAxisInfo(axisModel)?.seriesDataCount ?? 0)
                let axisExtent = axis.getExtent()
                // Approximate band width
                return abs(axisExtent[0] - axisExtent[1]) / seriesDataCount > animationThreshold
            }

            return false
        }

        return _isTruthy(animation)  // upstream: `animation === true`.
    }

    /// add {pointer, label, graphicKey} to elOption
    /// @protected — Should be implemented by sub-class (TASK 1 — `CartesianAxisPointer`).
    //
    //   OVERRIDE-SIGNATURE NOTE (for the integrator / TASK 1): the concrete override narrows `axisModel`
    //   to `CartesianAxisModel` and `value` to `ScaleDataValue`, but a Swift `override` must keep THIS
    //   exact signature — narrow INSIDE the body via `axisModel as? CartesianAxisModel` (the same
    //   protocol-witness/narrowing trap that bit Phase 35). `elOption` is `inout` because it is a value
    //   struct the subclass fills (upstream mutates the passed object in place).
    open func makeElOption(
        _ elOption: inout AxisPointerElementOptions,
        _ value: Any?,
        _ axisModel: AxisBaseModel,
        _ axisPointerModel: Model,
        _ api: ExtensionAPI
    ) {
        // Should be implemented by sub-class.
    }

    /// @protected
    // upstream: createPointerEl(group, elOption, axisModel, axisPointerModel)
    open func createPointerEl(
        _ group: Group,
        _ elOption: AxisPointerElementOptions,
        _ axisModel: AxisBaseModel,
        _ axisPointerModel: Model
    ) {
        guard let pointerOption = elOption.pointer else { return }
        // upstream: `new graphic[pointerOption.type](clone(elOption.pointer))`. Swift has no dynamic
        //   `graphic[type]` — switch the shape-class name. Reuse the ctor prop-bag merge path
        //   (DEFAULT_PATH_STYLE + getDefaultStyle + props.style), matching `new graphic.Line({...})`.
        let pointerEl = makePointerPath(pointerOption)
        self._pointerEl = pointerEl
        _ = group.add(pointerEl)
    }

    /// @protected
    // upstream: createLabelEl(group, elOption, axisModel, axisPointerModel)
    open func createLabelEl(
        _ group: Group,
        _ elOption: AxisPointerElementOptions,
        _ axisModel: AxisBaseModel,
        _ axisPointerModel: Model
    ) {
        guard let label = elOption.label else { return }
        // upstream: `new graphic.Text(clone(elOption.label))`.
        var props: [String: Any] = ["x": label.x, "y": label.y, "z2": label.z2]
        if let style = label.style { props["style"] = style }
        let labelEl = ZRText(props)
        self._labelEl = labelEl
        _ = group.add(labelEl)
        updateLabelShowHide(labelEl, axisPointerModel)
    }

    /// @protected
    // upstream: updatePointerEl(group, elOption, updateProps)
    open func updatePointerEl(_ group: Group, _ elOption: AxisPointerElementOptions) {
        guard let pointerEl = self._pointerEl, let pointer = elOption.pointer else { return }
        // upstream: `pointerEl.setStyle(elOption.pointer.style)` (MERGE). There is no
        //   `Path.setStyle(PathStyleProps)` overload in the port; `elOption.pointer.style` is the FULL
        //   style rebuilt every render by `viewHelper.buildElStyle`, so replacing == merging here.
        //   PORT-NOTE: replace == merge here because the style is fully rebuilt every render; a true
        //   partial-merge would only matter if a caller ever supplied a partial style (none do).
        if let style = pointer.style { pointerEl.useStyle(style) }
        if let shape = pointer.shape {
            updateProps(pointerEl, ["shape": shape])
        }
    }

    /// @protected
    // upstream: updateLabelEl(group, elOption, updateProps, axisPointerModel)
    open func updateLabelEl(_ group: Group, _ elOption: AxisPointerElementOptions, _ axisPointerModel: Model) {
        guard let labelEl = self._labelEl, let label = elOption.label else { return }
        if let style = label.style { labelEl.useStyle(style) }
        // upstream animates {x, y} (shape animation TODO'd out upstream too).
        updateProps(labelEl, ["x": label.x, "y": label.y])
        updateLabelShowHide(labelEl, axisPointerModel)
    }

    // -----------------------------------------------------------------------------------------------
    // Handle-support hooks (upstream `interface BaseAxisPointer`): "Should be implemented by sub-class
    //   if support `handle`." A base pointer with no handle support returns nil / false; the concrete
    //   `CartesianAxisPointer` overrides these (see CartesianAxisPointer.swift).
    // -----------------------------------------------------------------------------------------------

    /// upstream check `!this.updateHandleTransform` (in `_renderHandle`) — whether this pointer subclass
    ///   implements the handle transform. Base = false; overridden to true by handle-supporting subclasses.
    open var hasHandleSupport: Bool { false }

    /// upstream: `getHandleTransform(value, axisModel, axisPointerModel): Transform`
    ///   Should be implemented by sub-class if support `handle`. Base returns nil.
    open func getHandleTransform(
        _ value: Any?,
        _ axisModel: AxisBaseModel,
        _ axisPointerModel: Model
    ) -> AxisPointerHandleTransform? {
        return nil
    }

    /// upstream: `updateHandleTransform(transform, delta, axisModel, axisPointerModel): Transform & {...}`
    ///   Should be implemented by sub-class if support `handle`. Base returns nil.
    open func updateHandleTransform(
        _ transform: AxisPointerHandleTransform,
        _ delta: [Double],
        _ axisModel: AxisBaseModel,
        _ axisPointerModel: Model
    ) -> AxisPointerUpdatedHandleTransform? {
        return nil
    }

    /// @private
    // upstream: _renderHandle(value: AxisValue)
    private func _renderHandle(_ value: Any?) {
        // upstream: if (this._dragging || !this.updateHandleTransform) { return; }
        if self._dragging || !self.hasHandleSupport {
            return
        }

        let axisPointerModel = self._axisPointerModel!
        // upstream: const zr = this._api.getZr();  — HOST SEAM: reached via hostAddHandle/hostRemoveHandle.
        var handle = self._handle
        let handleModel = axisPointerModel.getModel("handle")

        let status = axisPointerModel.get("status")
        // upstream: if (!handleModel.get('show') || !status || status === 'hide')
        if !_isTruthy(handleModel.get("show")) || _isFalsy(status) || (status as? String) == "hide" {
            // handle && zr.remove(handle); this._handle = null;
            if let h = handle { self.hostRemoveHandle?(h) }
            self._handle = nil
            return
        }

        var isInit = false
        if self._handle == nil {
            isInit = true
            // upstream: handle = this._handle = graphic.createIcon(handleModel.get('icon'), { ... });
            let icon = handleModel.get("icon") as? String
            let created = createIcon(icon, [
                "cursor": "move",
                "draggable": true
            ])
            // createIcon returns nil only for an empty icon string; the handle default icon is a non-empty
            //   path, so `created` is present. Guard defensively (upstream `handle` would be undefined).
            guard let h = created else { return }
            self._handle = h
            handle = h

            // upstream passes the event handlers inside the createIcon opt; here they are wired onto the
            //   element after construction (event seam — see createIcon PORT-NOTE):
            //     onmousemove(e) { eventTool.stop(e.event); }  — prevent screen slide on mobile.
            _ = h.on("mousemove", { _, args in
                if let e = args.first as? ElementEvent, let raw = e.event as? ZRRawEvent {
                    eventTool.stop(raw)
                }
                return nil
            }, self)
            //     onmousedown: bind(this._onHandleDragMove, this, 0, 0)
            _ = h.on("mousedown", { [weak self] _, _ in
                self?._onHandleDragMove(0, 0)
                return nil
            }, self)
            //     drift: bind(this._onHandleDragMove, this)  — the reassignable `drift` (driftHandler seam).
            h.driftHandler = { [weak self] dx, dy, _ in
                self?._onHandleDragMove(dx, dy)
            }
            //     ondragend: bind(this._onHandleDragEnd, this)
            _ = h.on("dragend", { [weak self] _, _ in
                self?._onHandleDragEnd()
                return nil
            }, self)

            // zr.add(handle);  — HOST SEAM.
            self.hostAddHandle?(h)
        }

        guard let handle = handle else { return }

        // updateMandatoryProps(handle, axisPointerModel, false);
        updateMandatoryProps(handle, axisPointerModel, false)

        // update style
        //   (handle as graphic.Path).setStyle(handleModel.getItemStyle(null, [ ... ]));
        let itemStyle = handleModel.getItemStyle(nil, [
            "color", "borderColor", "borderWidth", "opacity",
            "shadowColor", "shadowBlur", "shadowOffsetX", "shadowOffsetY"
        ])
        if let path = handle as? Path {
            _ = path.useStyle(handlePathStyleFromDict(itemStyle))
        }

        // update position
        // let handleSize = handleModel.get('size'); if (!isArray) handleSize = [handleSize, handleSize];
        var handleSize: [Double]
        if let arr = handleModel.get("size") as? [Double] {
            handleSize = arr
        }
        else if let arr = handleModel.get("size") as? [Any] {
            handleSize = arr.map { _optDouble($0) ?? 0 }
        }
        else {
            let s = _optDouble(handleModel.get("size")) ?? 0
            handleSize = [s, s]
        }
        // handle.scaleX = handleSize[0] / 2; handle.scaleY = handleSize[1] / 2;
        handle.scaleX = (handleSize.count > 0 ? handleSize[0] : 0) / 2
        handle.scaleY = (handleSize.count > 1 ? handleSize[1] : 0) / 2

        // throttleUtil.createOrUpdate(this, '_doDispatchAxisPointer', handleModel.get('throttle') || 0, 'fixRate');
        self._doDispatchThrottled = throttleUtil.createOrUpdate(
            existing: self._doDispatchThrottled,
            origin: { [weak self] in self?._doDispatchAxisPointer() },
            rate: _optDouble(handleModel.get("throttle")) ?? 0,
            throttleType: .fixRate
        )

        // this._moveHandleToValue(value, isInit);
        self._moveHandleToValue(value, isInit)
    }

    // upstream: private _moveHandleToValue(value, isInit?)
    private func _moveHandleToValue(_ value: Any?, _ isInit: Bool = false) {
        guard let handle = self._handle,
              let trans = self.getHandleTransform(value, self._axisModel!, self._axisPointerModel!) else {
            return
        }
        // upstream: updateProps(this._axisPointerModel, !isInit && this._moveAnimation, this._handle,
        //   getHandleTransProps(this.getHandleTransform(value, ...)));
        //   The port's `updateProps(el, props)` sets directly (no animated slide — see its PORT-NOTE);
        //   `!isInit && this._moveAnimation` is therefore inert here.
        _ = isInit
        updateProps(handle, getHandleTransProps(trans))
    }

    // upstream: private _onHandleDragMove(dx, dy)
    private func _onHandleDragMove(_ dx: Double, _ dy: Double) {
        guard let handle = self._handle else {
            return
        }

        self._dragging = true

        // Persistent for throttle.
        // const trans = this.updateHandleTransform(getHandleTransProps(handle), [dx, dy], axisModel, axisPointerModel);
        guard let trans = self.updateHandleTransform(
            handleTransFromEl(handle),
            [dx, dy],
            self._axisModel!,
            self._axisPointerModel!
        ) else {
            return
        }
        self._payloadInfo = trans

        // handle.stopAnimation(); (handle as graphic.Path).attr(getHandleTransProps(trans)); inner(handle).lastProp = null;
        _ = handle.stopAnimation()
        _ = handle.attr(getHandleTransProps(trans))

        // this._doDispatchAxisPointer();  — throttled (see _doDispatchThrottled).
        if let throttled = self._doDispatchThrottled {
            throttled()
        }
        else {
            self._doDispatchAxisPointer()
        }
    }

    /// Throttled method.
    // upstream: _doDispatchAxisPointer()
    private func _doDispatchAxisPointer() {
        guard self._handle != nil else {
            return
        }

        guard let payloadInfo = self._payloadInfo, let axisModel = self._axisModel else {
            return
        }
        let axis = axisModel.axis as! Axis
        // this._api.dispatchAction({ type: 'updateAxisPointer', x, y, tooltipOption, axesInfo: [{ axisDim, axisIndex }] });
        var payload = Payload(type: "updateAxisPointer")
        payload.other["x"] = payloadInfo.cursorPoint.count > 0 ? payloadInfo.cursorPoint[0] : 0
        payload.other["y"] = payloadInfo.cursorPoint.count > 1 ? payloadInfo.cursorPoint[1] : 0
        if let tooltipOption = payloadInfo.tooltipOption {
            payload.other["tooltipOption"] = tooltipOption
        }
        payload.other["axesInfo"] = [[
            "axisDim": axis.dim,
            "axisIndex": axisModel.componentIndex
        ] as [String: Any]]
        self._api?.dispatchAction(payload)
    }

    // upstream: private _onHandleDragEnd()
    private func _onHandleDragEnd() {
        self._dragging = false
        guard self._handle != nil else {
            return
        }

        let value = self._axisPointerModel!.get("value")
        // Consider snap or category axis, handle may be not consistent with axisPointer. So move handle
        // to align the exact value position when drag ended.
        self._moveHandleToValue(value)

        // For the effect: tooltip will be shown when finger holding on handle button, and will be hidden
        // after finger left handle button.
        self._api?.dispatchAction(Payload(type: "hideTip"))
    }

    /// @private
    // upstream: clear(api)
    open func clear(_ api: ExtensionAPI) {
        self._lastValue = nil
        self._lastStatus = nil

        // upstream removes the group (and handle) from the zr. HOST SEAM — hand the group / handle back
        //   to the integrator's zr for removal, then drop our references.
        if let group = self.group {
            self._lastGraphicKey = nil
            self.hostRemove?(group)
            if let handle = self._handle { self.hostRemoveHandle?(handle) }
            self.group = nil
            self._handle = nil
            self._pointerEl = nil
            self._labelEl = nil
            self._payloadInfo = nil
        }

        // throttleUtil.clear(this, '_doDispatchAxisPointer');
        self._doDispatchThrottled = throttleUtil.clear(self._doDispatchThrottled)
    }

    /// @protected — Implemented by sub-class if necessary.
    open func doClear() {
    }

    // upstream: buildLabel(xy, wh, xDimIndex) — a small helper used by some sub-classes (Polar/Single).
    open func buildLabel(_ xy: [Double], _ wh: [Double], _ xDimIndex: Int) -> [String: Double] {
        let i = xDimIndex  // upstream `xDimIndex = xDimIndex || 0` — caller passes 0/1.
        return [
            "x": xy[i],
            "y": xy[1 - i],
            "width": wh[i],
            "height": wh[1 - i]
        ]
    }
}

// upstream: `new graphic[pointerOption.type](clone(elOption.pointer))` — construct the pointer PATH
//   from the option. Reuses the ctor prop-bag path so the style merge matches upstream exactly.
private func makePointerPath(_ pointer: PointerElementOption) -> Path {
    var props: [String: Any] = [:]
    if let shape = pointer.shape { props["shape"] = shape }
    if let style = pointer.style { props["style"] = style }

    let el: Path
    switch pointer.type {
    case "Rect":
        el = Rect(props)
    case "Line":
        el = Line(props)
    case "Circle":
        el = Circle(props)
    case "Sector":
        el = Sector(props)
    default:
        // upstream constructs `new graphic[pointerOption.type](...)`. Any unknown pointer type
        //   falls back to a Line so the build never crashes.
        el = Line(props)
    }
    el.subPixelOptimize = pointer.subPixelOptimize
    return el
}

// upstream:
//   function updateProps(animationModel, moveAnimation, el, props) {
//       if (!propsEqual(inner(el).lastProp, props)) { inner(el).lastProp = props;
//           moveAnimation ? graphic.updateProps(el, props, animationModel)
//                         : (el.stopAnimation(), el.attr(props)); } }
//
//   PORT-NOTE (animation): the animated-slide branch (`graphic.updateProps` transition) + the
//   `inner(el).lastProp` equality memo are DROPPED — the crosshair sets its position DIRECTLY
//   (`el.stopAnimation(); el.attr(props)`), which is upstream's own no-animation branch. `moveAnimation`
//   is therefore not consulted here (it is still computed by `determineAnimation` for a future port).
//   For a `Path`, `attr('shape', PathShape)` routes to `setShape`; for `ZRText`, `attr('x'/'y', …)` sets
//   the position — matching the props each caller passes.
private func updateProps(_ el: Element, _ props: [String: Any]) {
    _ = el.stopAnimation()
    _ = el.attr(props)
}

// upstream: function getHandleTransProps(trans: Transform): Transform {
//     return { x: trans.x || 0, y: trans.y || 0, rotation: trans.rotation || 0 };
// }
//   Returns a `[String: Any]` props bag for `el.attr` / `updateProps` (the two struct kinds — the base
//   Transform and the updated Transform — both carry x/y/rotation). `trans.x || 0` guarded undefined in
//   JS; the Swift structs are non-optional Double, so no guard is needed.
private func getHandleTransProps(_ trans: AxisPointerHandleTransform) -> [String: Any] {
    return ["x": trans.x, "y": trans.y, "rotation": trans.rotation]
}
private func getHandleTransProps(_ trans: AxisPointerUpdatedHandleTransform) -> [String: Any] {
    return ["x": trans.x, "y": trans.y, "rotation": trans.rotation]
}

// upstream reads the handle ELEMENT as a `Transform` via `getHandleTransProps(handle)` (Element has
//   x/y/rotation) to seed `updateHandleTransform`. This helper packages the element's current
//   position/rotation into the typed `AxisPointerHandleTransform` that `updateHandleTransform` expects.
private func handleTransFromEl(_ el: Element) -> AxisPointerHandleTransform {
    return AxisPointerHandleTransform(x: el.x, y: el.y, rotation: el.rotation)
}

// Bridge the handle `getItemStyle(null, ['color', 'borderColor', ...])` dynamic bag ([String: Any],
//   keyed by STYLE names via ITEM_STYLE_KEY_MAP) onto the typed `PathStyleProps` the handle Path
//   consumes. Mirrors the sibling `pathStyleFrom*Dict` bridges (AxisBuilder / calendar).
private func handlePathStyleFromDict(_ dict: [String: Any]) -> PathStyleProps {
    var s = PathStyleProps()
    if let v = _handleColorString(dict["fill"]) { s.fill = .string(v) }
    if let v = _handleColorString(dict["stroke"]) { s.stroke = .string(v) }
    if let v = _optDouble(dict["lineWidth"]) { s.lineWidth = v }
    if let v = _optDouble(dict["opacity"]) { s.opacity = v }
    if let v = _optDouble(dict["shadowBlur"]) { s.shadowBlur = v }
    if let v = dict["shadowColor"] as? String { s.shadowColor = v }
    if let v = _optDouble(dict["shadowOffsetX"]) { s.shadowOffsetX = v }
    if let v = _optDouble(dict["shadowOffsetY"]) { s.shadowOffsetY = v }
    return s
}

// A style paint value from the itemStyle bag is a raw `String` (option `color: '#7581BD'`); accept the
//   EChartsKit `ZRColor` solid form defensively (gradient/pattern objects are out of the handle scope).
private func _handleColorString(_ v: Any?) -> String? {
    if let str = v as? String { return str }
    if let zr = v as? EChartsKit.ZRColor, case let .color(str) = zr { return str }
    return nil
}

// upstream: function updateLabelShowHide(labelEl, axisPointerModel) {
//     labelEl[axisPointerModel.get(['label', 'show']) ? 'show' : 'hide']();
// }
private func updateLabelShowHide(_ labelEl: Element, _ axisPointerModel: Model) {
    if _isTruthy(axisPointerModel.get(["label", "show"])) {
        labelEl.show()
    }
    else {
        labelEl.hide()
    }
}

// upstream: function updateMandatoryProps(group, axisPointerModel, silent?) {
//     const z = axisPointerModel.get('z'); const zlevel = axisPointerModel.get('zlevel');
//     group && group.traverse(function (el) { if (el.type !== 'group') {
//         z != null && (el.z = z); zlevel != null && (el.zlevel = zlevel); el.silent = silent; } });
// }
//   PORT-NOTE: upstream types `group: Element` and relies on dynamic dispatch — `Group.traverse`
//   visits children, while the base `Element.traverse` is EMPTY (a no-op). This is called with BOTH the
//   crosshair `Group` AND the draggable `handle` (a non-group Displayable). Swift's `Element.traverse`
//   and `Group.traverse` are not an override pair (different return types), so we branch explicitly:
//   a Group traverses its children; any other Element is the empty-traverse no-op — EXACTLY upstream's
//   behaviour (the handle therefore keeps its `createIcon` `silent:false`, staying draggable).
private func updateMandatoryProps(_ group: Element?, _ axisPointerModel: Model, _ silent: Bool) {
    // Int-vs-Double option-read trap: `z` defaults to `50.0` but a user option may box it as Int.
    let z = _optDouble(axisPointerModel.get("z"))
    let zlevel = _optDouble(axisPointerModel.get("zlevel"))

    guard let group = group as? Group else {
        // Non-group Element → base `Element.traverse` is an empty no-op upstream.
        return
    }
    _ = group.traverse({ el in
        if el.type != "group", let disp = el as? Displayable {
            if let z = z { disp.z = z }
            if let zlevel = zlevel { disp.zlevel = zlevel }
            disp.silent = silent
        }
        return false  // Group.traverse: `return true` stops descent; we always continue.
    })
}

// ---- small value helpers (JS truthiness / Int-vs-Double / loose `===` for AxisValue) ----

// upstream `z != null` / `zlevel != null` guard + Int-vs-Double coercion (MEMORY: option numbers may
//   box as Int). Returns nil for null/NSNull/non-number so the caller keeps the element's current z.
private func _optDouble(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    return nil
}

// JS truthiness for an option read (nil / NSNull / false / 0 / "" are falsy).
private func _isTruthy(_ v: Any?) -> Bool {
    return !_isFalsy(v)
}

private func _isFalsy(_ v: Any?) -> Bool {
    guard let v = v else { return true }
    if v is NSNull { return true }
    if let b = v as? Bool { return !b }
    if let d = v as? Double { return d == 0 }
    if let i = v as? Int { return i == 0 }
    if let s = v as? String { return s.isEmpty }
    return false
}

// upstream `this._lastValue === value` / `this._lastStatus === status` (strict identity on a
//   number|string|Date|null). Modeled as a loose scalar equality over the AxisValue kinds.
private func _axisValueEqual(_ a: Any?, _ b: Any?) -> Bool {
    let aNull = (a == nil) || (a is NSNull)
    let bNull = (b == nil) || (b is NSNull)
    if aNull || bNull { return aNull && bNull }
    if let ad = a as? Double, let bd = b as? Double { return ad == bd }
    if let ai = a as? Int, let bi = b as? Int { return ai == bi }
    if let ad = _optDouble(a), let bd = _optDouble(b) { return ad == bd }
    if let asx = a as? String, let bsx = b as? String { return asx == bsx }
    return false
}

// export default BaseAxisPointer;  -> `open class BaseAxisPointer` above.
