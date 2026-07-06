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
// import * as graphic from '../../util/graphic';                   -> ZRenderKit Group / Line / Rect / ZRText
// import * as axisPointerModelHelper from './modelHelper';         -> modelHelper.swift (getAxisInfo)
// import * as eventTool from 'zrender/src/core/event';             -> handle drag seam (PORT-TODO)
// import * as throttleUtil from '../../util/throttle';             -> handle throttle seam (PORT-TODO)
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
    /// The ZRenderKit shape class name — 'Line' / 'Rect' (Circle / Sector are PORT-TODO, unused by
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
///   crosshair on the LIVE zr, and `clear` calls `zr.remove(group)`. In THIS slim port the ported
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

    // upstream: private _handle: Icon;  — the draggable handle (PORT-TODO, deferred).
    // private var _handle: ... (deferred)

    // upstream: private _dragging = false;  — handle drag (PORT-TODO, deferred).
    private var _dragging = false

    // upstream: private _lastValue: AxisValue;
    private var _lastValue: Any?

    // upstream: private _lastStatus: CommonAxisPointerOption['status'];
    private var _lastStatus: Any?

    /// If have transition animation.
    // upstream: private _moveAnimation: boolean;
    //   PORT-TODO (animation): computed by `determineAnimation` but NOT consumed for a real animated
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

        let handle: AnyObject? = nil  // upstream `const handle = this._handle` — handle is PORT-TODO.

        // upstream: `if (!status || status === 'hide')`. `!status` ⟷ `_isFalsy` (null/''/false/0).
        if _isFalsy(status) || (status as? String) == "hide" {
            // Do not clear here, for animation better.
            self.group?.hide()
            // handle && handle.hide();  (PORT-TODO)
            _ = handle
            return
        }
        self.group?.show()
        // handle && handle.show();  (PORT-TODO)

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
            //   is inert here (no animated slide — see the free `updateProps` PORT-TODO).
            self.updatePointerEl(self.group!, elOption)
            self.updateLabelEl(self.group!, elOption, axisPointerModel)
        }

        updateMandatoryProps(self.group, axisPointerModel, true)

        // upstream: this._renderHandle(value);  — draggable handle (PORT-TODO, deferred).
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
        //   PORT-TODO: true partial-merge if a caller ever supplies a partial style.
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

    // upstream: _renderHandle / _moveHandleToValue / _onHandleDragMove / _doDispatchAxisPointer /
    //   _onHandleDragEnd — the draggable handle + `updateAxisPointer` drag dispatch.
    //   PORT-TODO (deferred): the whole handle/drag surface (handle icon, throttle, drift, dragend,
    //   `getHandleTransform` / `updateHandleTransform`) is out of scope for the headless crosshair.

    /// @private
    // upstream: clear(api)
    open func clear(_ api: ExtensionAPI) {
        self._lastValue = nil
        self._lastStatus = nil

        // upstream removes the group (and handle) from the zr. HOST SEAM — hand the group back to the
        //   integrator's zr for removal, then drop our references.
        if let group = self.group {
            self._lastGraphicKey = nil
            self.hostRemove?(group)
            self.group = nil
            self._pointerEl = nil
            self._labelEl = nil
        }

        // upstream: throttleUtil.clear(this, '_doDispatchAxisPointer');  (handle throttle — PORT-TODO)
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
    default:
        // PORT-TODO: 'Circle' / 'Sector' pointers (Polar/Single axis pointers) — not used by
        //   CartesianAxisPointer. Fall back to a Line so the build never crashes.
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
//   PORT-TODO (animation): the animated-slide branch (`graphic.updateProps` transition) + the
//   `inner(el).lastProp` equality memo are DROPPED — the crosshair sets its position DIRECTLY
//   (`el.stopAnimation(); el.attr(props)`), which is upstream's own no-animation branch. `moveAnimation`
//   is therefore not consulted here (it is still computed by `determineAnimation` for a future port).
//   For a `Path`, `attr('shape', PathShape)` routes to `setShape`; for `ZRText`, `attr('x'/'y', …)` sets
//   the position — matching the props each caller passes.
private func updateProps(_ el: Element, _ props: [String: Any]) {
    _ = el.stopAnimation()
    _ = el.attr(props)
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
private func updateMandatoryProps(_ group: Group?, _ axisPointerModel: Model, _ silent: Bool) {
    // Int-vs-Double option-read trap: `z` defaults to `50.0` but a user option may box it as Int.
    let z = _optDouble(axisPointerModel.get("z"))
    let zlevel = _optDouble(axisPointerModel.get("zlevel"))

    _ = group?.traverse({ el in
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
