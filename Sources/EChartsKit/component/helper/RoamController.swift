// Ported from echarts/src/component/helper/RoamController.ts — keep in sync with upstream
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

// upstream imports mapped:
//   import Eventful from 'zrender/src/core/Eventful';         -> COMPOSED (Eventful is `final` in the
//       port, CONVENTIONS §2). RoamController holds a private `_eventful` and forwards on/off/trigger.
//   import * as eventTool from 'zrender/src/core/event';      -> `eventTool` (ZRenderKit Core/event.swift).
//   import * as interactionMutex from './interactionMutex';   -> `interactionMutex` (sibling).
//   import { ZRenderType } from 'zrender/src/zrender';        -> ZRenderKit `ZRender`.
//   import { ZRElementEvent, RoamOptionMixin, NullUndefined } from '../../util/types'; -> `ElementEvent`.
//   import { Bind3, isString, bind, defaults, extend, retrieve2 } from 'zrender/src/core/util';
//   import { makeInner } from '../../util/model';             -> `model.makeInner`.
//   import { retrieveZInfo } from '../../util/graphic';       -> `retrieveZInfo` (defined below; util/graphic
//       has not landed it yet).
//   import type Component from '../../model/Component';       -> `ComponentModel`.
//   import ExtensionAPI from '../../core/ExtensionAPI';       -> `ExtensionAPI`.
//   import { onIrrelevantElement } from './cursorHelper';     -> `onIrrelevantElement` (sibling).
//   import Displayable from 'zrender/src/graphic/Displayable';-> `Displayable`.

// upstream: `import { retrieveZInfo } from '../../util/graphic'`. Not yet landed in util/graphic.swift;
//   reproduced here (reads z/zlevel/z2 off the component model with a 0 floor — enough for the roam
//   listener precedence ordering). PORT-TODO: dedupe once util/graphic.retrieveZInfo lands.
public struct RoamZInfo {
    public var component: ComponentModel?
    public var z: Double
    public var zlevel: Double
    public var z2: Double
}
private func roamNum(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return nil
}
public func retrieveZInfo(_ model: ComponentModel) -> RoamZInfo {
    return RoamZInfo(
        component: model,
        z: roamNum(model.get("z")) ?? 0,
        zlevel: roamNum(model.get("zlevel")) ?? 0,
        z2: roamNum(model.get("z2")) ?? 0
    )
}

// ---------------------------------------------------------------------------
// RoamOption / RoamSetting — upstream `interface RoamOption` + `type RoamSetting`.
// ---------------------------------------------------------------------------

// upstream: interface RoamOption { zInfo, triggerInfo, api, zoomOnMouseWheel?, moveOnMouseMove?,
//   moveOnMouseWheel?, preventDefaultMouseMove?, cursorGrab?, cursorGrabbing? }
public struct RoamOption {
    // zInfo.component / zInfo.z2
    public var component: ComponentModel
    public var z2: Double?
    // triggerInfo.roamTrigger / isInSelf / isInClip
    public var roamTrigger: String?
    public var isInSelf: (ElementEvent, Double, Double) -> Bool
    public var isInClip: ((ElementEvent, Double, Double) -> Bool)?
    public var api: ExtensionAPI

    // behavior flags: `boolean | 'ctrl' | 'shift' | 'alt'`, erased to `Any?`.
    public var zoomOnMouseWheel: Any?
    public var moveOnMouseMove: Any?
    public var moveOnMouseWheel: Any?
    public var preventDefaultMouseMove: Bool?
    public var cursorGrab: String?
    public var cursorGrabbing: String?

    public init(
        component: ComponentModel,
        api: ExtensionAPI,
        isInSelf: @escaping (ElementEvent, Double, Double) -> Bool,
        isInClip: ((ElementEvent, Double, Double) -> Bool)? = nil,
        roamTrigger: String? = nil,
        z2: Double? = nil,
        zoomOnMouseWheel: Any? = nil,
        moveOnMouseMove: Any? = nil,
        moveOnMouseWheel: Any? = nil,
        preventDefaultMouseMove: Bool? = nil,
        cursorGrab: String? = nil,
        cursorGrabbing: String? = nil
    ) {
        self.component = component
        self.api = api
        self.isInSelf = isInSelf
        self.isInClip = isInClip
        self.roamTrigger = roamTrigger
        self.z2 = z2
        self.zoomOnMouseWheel = zoomOnMouseWheel
        self.moveOnMouseMove = moveOnMouseMove
        self.moveOnMouseWheel = moveOnMouseWheel
        self.preventDefaultMouseMove = preventDefaultMouseMove
        self.cursorGrab = cursorGrab
        self.cursorGrabbing = cursorGrabbing
    }
}

// upstream: `type RoamSetting = Omit<Required<RoamOption>, 'zInfo'> & { zInfoParsed }` — the resolved
//   option after `defaults(...)`. Class (reference) so `isAvailableBehavior` can read it back.
final class RoamSetting {
    var roamTrigger: String?
    var isInSelf: (ElementEvent, Double, Double) -> Bool
    var isInClip: ((ElementEvent, Double, Double) -> Bool)?
    var api: ExtensionAPI

    var zoomOnMouseWheel: Any?
    var moveOnMouseMove: Any?
    var moveOnMouseWheel: Any?
    var preventDefaultMouseMove: Bool
    var cursorGrab: String
    var cursorGrabbing: String

    // zInfoParsed
    var component: ComponentModel
    var z: Double
    var zlevel: Double
    var z2: Double

    init(_ opt: RoamOption) {
        self.roamTrigger = opt.roamTrigger
        self.isInSelf = opt.isInSelf
        self.isInClip = opt.isInClip
        self.api = opt.api
        // upstream defaults: zoomOnMouseWheel:true, moveOnMouseMove:true, moveOnMouseWheel:false,
        //   preventDefaultMouseMove:true, cursorGrab:'grab', cursorGrabbing:'grabbing'.
        self.zoomOnMouseWheel = opt.zoomOnMouseWheel ?? true
        self.moveOnMouseMove = opt.moveOnMouseMove ?? true
        self.moveOnMouseWheel = opt.moveOnMouseWheel ?? false
        self.preventDefaultMouseMove = opt.preventDefaultMouseMove ?? true
        self.cursorGrab = opt.cursorGrab ?? "grab"
        self.cursorGrabbing = opt.cursorGrabbing ?? "grabbing"
        // zInfoParsed: {component, z, zlevel, z2 = retrieve2(zInfo.z2, -Infinity)}
        let zi = retrieveZInfo(opt.component)
        self.component = opt.component
        self.z = zi.z
        self.zlevel = zi.zlevel
        self.z2 = opt.z2 ?? -Double.infinity
    }

    // `settings[behaviorToCheck]` accessor.
    func behaviorValue(_ behavior: String) -> Any? {
        switch behavior {
        case "zoomOnMouseWheel": return zoomOnMouseWheel
        case "moveOnMouseMove": return moveOnMouseMove
        case "moveOnMouseWheel": return moveOnMouseWheel
        default: return nil
        }
    }
}

// upstream: `interface RoamEventParams` — the per-event param object. One class carries all shapes
//   (pan / zoom / scrollMove); each event only populates its own fields.
public final class RoamEventParams {
    // pan
    public var dx: Double = 0
    public var dy: Double = 0
    public var oldX: Double = 0
    public var oldY: Double = 0
    public var newX: Double = 0
    public var newY: Double = 0
    // zoom
    public var scale: Double = 0
    // zoom + scrollMove
    public var originX: Double = 0
    public var originY: Double = 0
    // scrollMove
    public var scrollDelta: Double = 0
    // upstream: `isAvailableBehavior: Bind3<...>` — a behavior checker for shared listeners. Rarely used
    //   (graph does not); modeled as a closure taking the settings bag. PORT-TODO: settings typing.
    public var isAvailableBehavior: ((RoamSettingLike) -> Bool)?
    public init() {}
}

// A read-only view of the three behavior flags for `RoamEventParams.isAvailableBehavior`.
public struct RoamSettingLike {
    public var zoomOnMouseWheel: Any?
    public var moveOnMouseMove: Any?
    public var moveOnMouseWheel: Any?
    public init(zoomOnMouseWheel: Any? = nil, moveOnMouseMove: Any? = nil, moveOnMouseWheel: Any? = nil) {
        self.zoomOnMouseWheel = zoomOnMouseWheel
        self.moveOnMouseMove = moveOnMouseMove
        self.moveOnMouseWheel = moveOnMouseWheel
    }
}

/**
 * An manager of zoom and pan(drag) behavior. It is not responsible for updating the view.
 * See upstream class doc for the view-update contract (roamHelper / coord/View).
 */
// upstream: class RoamController extends Eventful<RoamEventDefinition>
public final class RoamController {

    // upstream: private _zr. WEAK — EChartsView owns both the zr and this controller; the per-zr roam
    //   listener store references this controller (via the bound handlers), so a strong `_zr` here would
    //   form a zr<->controller retain cycle that ARC cannot collect. See addRoamZrListener.
    private weak var _zr: ZRender?

    private var _opt: RoamSetting?

    private var _dragging = false
    private var _pinching = false
    private var _x: Double = 0
    private var _y: Double = 0

    private var _controlType: String?   // resolved roam control type (normalized to a String key).
    private var _enabled = false

    // upstream `extends Eventful`: composed here (CONVENTIONS §2). `on`/`off`/`trigger` forward to it.
    private let _eventful = Eventful()

    // The five bound gesture handlers (upstream `bind(this._mousedownHandler, this)` etc.). Held as stable
    //   `RoamZrListener` tokens so `removeRoamZrListener` can identify them (Swift closures have no `===`).
    private var _mousedownListener: RoamZrListener!
    private var _mousemoveListener: RoamZrListener!
    private var _mouseupListener: RoamZrListener!
    private var _mousewheelListener: RoamZrListener!
    private var _pinchListener: RoamZrListener!

    public init(_ zr: ZRender) {
        self._zr = zr
        // Avoid two roamControllers binding the same handler — each listener is a distinct token.
        self._mousedownListener = RoamZrListener { [weak self] e in self?._mousedownHandler(e) }
        self._mousemoveListener = RoamZrListener { [weak self] e in self?._mousemoveHandler(e) }
        self._mouseupListener = RoamZrListener { [weak self] e in self?._mouseupHandler(e) }
        self._mousewheelListener = RoamZrListener { [weak self] e in self?._mousewheelHandler(e) }
        self._pinchListener = RoamZrListener { [weak self] e in self?._pinchHandler(e) }
    }

    // ---- Eventful forwarding (upstream `extends Eventful`) ----

    @discardableResult
    public func on(_ event: String, _ cb: @escaping (RoamEventParams) -> Void) -> RoamController {
        _eventful.on(event, { _, args in
            if let p = args.first as? RoamEventParams { cb(p) }
            return nil
        })
        return self
    }

    @discardableResult
    public func off(_ event: String? = nil) -> RoamController {
        _eventful.off(event)
        return self
    }

    // upstream: `(controller as any).trigger(eventName, contollerEvent)`.
    func triggerEvent(_ event: String, _ params: RoamEventParams) {
        _eventful.trigger(event, params)
    }

    /**
     * Notice: only enable needed types. Idempotent.
     */
    // upstream: enable(controlType, rawOpt)
    public func enable(_ controlTypeIn: Any?, _ rawOpt: RoamOption) {
        guard let zr = self._zr else { return }

        let setting = RoamSetting(rawOpt)
        self._opt = setting

        // upstream: if (controlType == null) { controlType = true; }
        var controlType: Any? = controlTypeIn
        if controlType == nil { controlType = true }
        let controlKey = RoamController.normalizeControlType(controlType)

        // A quick optimization for repeatedly calling `enable` during roaming.
        if !self._enabled || self._controlType != controlKey {
            // Disable previous first.
            self.disable()

            self._enabled = true
            self._controlType = controlKey

            let isMove = (controlKey == "true" || controlKey == "move" || controlKey == "pan")
            let isScale = (controlKey == "true" || controlKey == "scale" || controlKey == "zoom")

            if isMove {
                addRoamZrListener(zr, "mousedown", self._mousedownListener, setting)
                addRoamZrListener(zr, "mousemove", self._mousemoveListener, setting)
                addRoamZrListener(zr, "mouseup", self._mouseupListener, setting)
            }
            if isScale {
                addRoamZrListener(zr, "mousewheel", self._mousewheelListener, setting)
                addRoamZrListener(zr, "pinch", self._pinchListener, setting)
            }
        }
    }

    // upstream: disable()
    public func disable() {
        if self._enabled {
            self._enabled = false
            self._controlType = nil
            guard let zr = self._zr else { return }
            removeRoamZrListener(zr, "mousedown", self._mousedownListener)
            removeRoamZrListener(zr, "mousemove", self._mousemoveListener)
            removeRoamZrListener(zr, "mouseup", self._mouseupListener)
            removeRoamZrListener(zr, "mousewheel", self._mousewheelListener)
            removeRoamZrListener(zr, "pinch", self._pinchListener)
        }
    }

    public func isDragging() -> Bool { return self._dragging }
    public func isPinching() -> Bool { return self._pinching }

    // upstream: dispose() { this.disable(); }
    public func dispose() {
        self.disable()
    }

    // upstream: _checkPointer(e, x, y): boolean
    func _checkPointer(_ e: ElementEvent, _ x: Double, _ y: Double) -> Bool {
        guard let opt = self._opt else { return false }

        if onIrrelevantElement(e, opt.api, opt.component) {
            return false
        }

        let roamTrigger = opt.roamTrigger
        var inArea = false
        if roamTrigger == "global" {
            inArea = true
        }
        if !inArea {
            inArea = opt.isInSelf(e, x, y)
        }
        if inArea, let isInClip = opt.isInClip, !isInClip(e, x, y) {
            inArea = false
        }
        return inArea
    }

    // upstream: _decideCursorStyle(e, x, y, forReverse): string | NullUndefined
    private func _decideCursorStyle(_ e: ElementEvent, _ x: Double, _ y: Double, _ forReverse: Bool) -> String? {
        let target = e.target
        if target == nil && self._checkPointer(e, x, y) {
            return self._opt?.cursorGrab
        }
        if forReverse {
            // upstream: `return target && (target as Displayable).cursor || 'default';`
            if let d = target as? Displayable {
                return d.cursor
            }
            return "default"
        }
        return nil
    }

    // upstream: _mousedownHandler(e)
    private func _mousedownHandler(_ e: ElementEvent) {
        if isMiddleOrRightButton(e) || eventConsumed(e) {
            return
        }

        // check if target or a host is draggable.
        var el: Element? = e.target
        while let cur = el {
            if cur.draggable != .false {
                return
            }
            el = cur.__hostTarget ?? (cur.parent as? Element)
        }

        let x = e.offsetX
        let y = e.offsetY

        // Determine dragging start only on mousedown.
        if self._checkPointer(e, x, y) {
            self._x = x
            self._y = y
            self._dragging = true
        }
    }

    // upstream: _mousemoveHandler(e)
    private func _mousemoveHandler(_ e: ElementEvent) {
        guard let zr = self._zr, let opt = self._opt else { return }
        if e.gestureEvent == "pinch"
            || interactionMutex.isTaken(zr, "globalPan")
            || eventConsumed(e) {
            return
        }

        let x = e.offsetX
        let y = e.offsetY

        if !self._dragging || !isAvailableBehavior("moveOnMouseMove", e, opt) {
            let cursorStyle = self._decideCursorStyle(e, x, y, false)
            if let cursorStyle = cursorStyle {
                zr.setCursorStyle(cursorStyle)
            }
            return
        }

        zr.setCursorStyle(opt.cursorGrabbing)

        let oldX = self._x
        let oldY = self._y

        let dx = x - oldX
        let dy = y - oldY

        self._x = x
        self._y = y

        if opt.preventDefaultMouseMove {
            e.stop?()
        }
        setEventConsumed(e)

        let params = RoamEventParams()
        params.dx = dx; params.dy = dy
        params.oldX = oldX; params.oldY = oldY
        params.newX = x; params.newY = y
        trigger(self, "pan", "moveOnMouseMove", e, params)
    }

    // upstream: _mouseupHandler(e)
    private func _mouseupHandler(_ e: ElementEvent) {
        if eventConsumed(e) { return }
        guard let zr = self._zr else { return }
        if !isMiddleOrRightButton(e) {
            self._dragging = false
            let cursorStyle = self._decideCursorStyle(e, e.offsetX, e.offsetY, true)
            if let cursorStyle = cursorStyle {
                zr.setCursorStyle(cursorStyle)
            }
        }
    }

    // upstream: _mousewheelHandler(e)
    private func _mousewheelHandler(_ e: ElementEvent) {
        if eventConsumed(e) { return }
        guard let opt = self._opt else { return }

        let shouldZoom = isAvailableBehavior("zoomOnMouseWheel", e, opt)
        let shouldMove = isAvailableBehavior("moveOnMouseWheel", e, opt)
        let wheelDelta = e.wheelDelta ?? 0
        let absWheelDeltaDelta = abs(wheelDelta)
        let originX = e.offsetX
        let originY = e.offsetY

        // wheelDelta maybe -0 in chrome mac.
        if wheelDelta == 0 || (!shouldZoom && !shouldMove) {
            return
        }

        if shouldZoom {
            // wheelDelta of mouse wheel is bigger than touch pad.
            let factor: Double = absWheelDeltaDelta > 3 ? 1.4 : (absWheelDeltaDelta > 1 ? 1.2 : 1.1)
            let scale = wheelDelta > 0 ? factor : 1 / factor
            let params = RoamEventParams()
            params.scale = scale; params.originX = originX; params.originY = originY
            self._checkTriggerMoveZoom("zoom", "zoomOnMouseWheel", e, params)
        }

        if shouldMove {
            let absDelta = abs(wheelDelta)
            let scrollDelta = (wheelDelta > 0 ? 1.0 : -1.0) * (absDelta > 3 ? 0.4 : (absDelta > 1 ? 0.15 : 0.05))
            let params = RoamEventParams()
            params.scrollDelta = scrollDelta; params.originX = originX; params.originY = originY
            self._checkTriggerMoveZoom("scrollMove", "moveOnMouseWheel", e, params)
        }
    }

    // upstream: _pinchHandler(e)
    private func _pinchHandler(_ e: ElementEvent) {
        guard let zr = self._zr else { return }
        if interactionMutex.isTaken(zr, "globalPan") || eventConsumed(e) {
            return
        }
        let scale = (e.pinchScale ?? 1) > 1 ? 1.1 : 1 / 1.1
        let params = RoamEventParams()
        params.scale = scale; params.originX = e.pinchX ?? 0; params.originY = e.pinchY ?? 0
        self._checkTriggerMoveZoom("zoom", nil, e, params)
    }

    // upstream: _checkTriggerMoveZoom(controller, eventName, behaviorToCheck, e, contollerEvent)
    private func _checkTriggerMoveZoom(
        _ eventName: String, _ behaviorToCheck: String?, _ e: ElementEvent, _ contollerEvent: RoamEventParams
    ) {
        if self._checkPointer(e, contollerEvent.originX, contollerEvent.originY) {
            e.stop?()
            setEventConsumed(e)
            trigger(self, eventName, behaviorToCheck, e, contollerEvent)
        }
    }

    // ---- helpers ----

    // upstream: `eventTool.isMiddleOrRightButtonOnMouseUpDown(e)` — e.which 2/3.
    private func isMiddleOrRightButton(_ e: ElementEvent) -> Bool {
        return e.which == 2 || e.which == 3
    }

    // Normalize the roam `controlType` (bool | string) to a stable String key for `_controlType`.
    private static func normalizeControlType(_ v: Any?) -> String {
        if let b = v as? Bool { return b ? "true" : "false" }
        if let s = v as? String { return s }
        return "true"
    }
}

// export default RoamController;  -> `public final class RoamController` above.

// ===========================================================================
// Module-locals (upstream: file-scoped `function`s + `makeInner` store).
// ===========================================================================

// A stable identity token wrapping a gesture handler closure (Swift closures are not `===`-comparable,
//   so the z-priority listener list needs an object to identify + remove).
final class RoamZrListener {
    let fn: (ElementEvent) -> Void
    init(_ fn: @escaping (ElementEvent) -> Void) { self.fn = fn }
}

// upstream: `type RoamControllerListenerItem = {listener} & Pick<RoamSetting, 'zInfoParsed'>`.
private struct RoamListenerItem {
    let listener: RoamZrListener
    let z: Double
    let zlevel: Double
    let z2: Double
}

// upstream: `const innerZrStore = makeInner<{roam, uniform}, ZRenderType>()`.
fileprivate final class RoamZrStore {
    // Listeners per event type, sorted by z2/z/zlevel descending.
    var roam: [String: [RoamListenerItem]] = [:]
    // Which event types already have the ONE uniform zr listener bound. (Upstream stores the listener
    //   itself so it can be `zr.off`-ed; the port's Eventful cannot remove a specific closure — see
    //   PORT-TODO in removeUniformListener — so the uniform is bound at most once ever per (zr, type).)
    var uniformBound: Set<String> = []
}
private let roamZrInner: (ZRender) -> RoamZrStore = model.makeInner { RoamZrStore() }

// upstream: addRoamZrListener(zr, eventType, listener, zInfoParsed) — insert into the z-sorted list.
private func addRoamZrListener(
    _ zr: ZRender, _ eventType: String, _ listener: RoamZrListener, _ zInfo: RoamSetting
) {
    let store = roamZrInner(zr)
    var listenerList = store.roam[eventType] ?? []
    var idx = 0
    while idx < listenerList.count {
        let curr = listenerList[idx]
        let cmp = ((curr.zlevel - zInfo.zlevel) != 0) ? (curr.zlevel - zInfo.zlevel)
            : (((curr.z - zInfo.z) != 0) ? (curr.z - zInfo.z)
            : (curr.z2 - zInfo.z2))
        // If all equal, the latter-added one has higher precedence (insert before).
        if cmp <= 0 { break }
        idx += 1
    }
    listenerList.insert(
        RoamListenerItem(listener: listener, z: zInfo.z, zlevel: zInfo.zlevel, z2: zInfo.z2),
        at: idx
    )
    store.roam[eventType] = listenerList
    ensureUniformListener(zr, eventType)
}

// upstream: removeRoamZrListener(zr, eventType, listener)
private func removeRoamZrListener(_ zr: ZRender, _ eventType: String, _ listener: RoamZrListener) {
    let store = roamZrInner(zr)
    guard var listenerList = store.roam[eventType] else { return }
    for idx in 0..<listenerList.count {
        if listenerList[idx].listener === listener {
            listenerList.remove(at: idx)
            store.roam[eventType] = listenerList
            if listenerList.isEmpty {
                removeUniformListener(zr, eventType)
            }
            return
        }
    }
}

// upstream: ensureUniformListener(zr, eventType) — bind ONE zr listener that fans out to the z-sorted list.
private func ensureUniformListener(_ zr: ZRender, _ eventType: String) {
    let store = roamZrInner(zr)
    if !store.uniformBound.contains(eventType) {
        store.uniformBound.insert(eventType)
        _ = zr.on(eventType, { _, args in
            guard let e = args.first as? ElementEvent else { return nil }
            if let listenerList = store.roam[eventType] {
                for item in listenerList {
                    item.listener.fn(e)
                }
            }
            return nil
        }, nil)
    }
}

// upstream: removeUniformListener(zr, eventType) — `zr.off(eventType, uniform)`.
//   PORT-TODO: the port's Eventful cannot remove a SPECIFIC closure (no closure identity), and calling
//   `zr.off(eventType)` with no handler would nuke unrelated listeners (EChartsView's own bindings). So
//   the uniform listener stays bound; it reads the live (now empty) `store.roam[eventType]` list and
//   fans out to nothing. `uniformBound` stays set so a re-enable does NOT double-bind. Faithful in effect.
private func removeUniformListener(_ zr: ZRender, _ eventType: String) {
    // Intentional no-op beyond leaving the empty list in place (see PORT-TODO above).
}

// upstream: function eventConsumed(e) { return (e as ...).__ecRoamConsumed; }
//   `__ecRoamConsumed` is a per-event flag; stored on a WeakMap keyed by the ElementEvent instance.
private final class RoamConsumedFlag { var value = false }
private let roamConsumedInner: (ElementEvent) -> RoamConsumedFlag = model.makeInner { RoamConsumedFlag() }
private func eventConsumed(_ e: ElementEvent) -> Bool {
    return roamConsumedInner(e).value
}
private func setEventConsumed(_ e: ElementEvent) {
    roamConsumedInner(e).value = true
}

// upstream: function trigger(controller, eventName, behaviorToCheck, e, contollerEvent)
private func trigger(
    _ controller: RoamController,
    _ eventName: String,
    _ behaviorToCheck: String?,
    _ e: ElementEvent,
    _ contollerEvent: RoamEventParams
) {
    // Provide a behavior checker for shared listeners (upstream `bind(isAvailableBehavior, null, ...)`).
    contollerEvent.isAvailableBehavior = { settings in
        return isAvailableBehaviorSettings(behaviorToCheck, e, settings)
    }
    controller.triggerEvent(eventName, contollerEvent)
}

// upstream: function isAvailableBehavior(behaviorToCheck, e, settings)
//   `!behaviorToCheck || (setting && (!isString(setting) || e.event[setting+'Key']))`.
private func isAvailableBehavior(_ behaviorToCheck: String?, _ e: ElementEvent, _ settings: RoamSetting) -> Bool {
    guard let behaviorToCheck = behaviorToCheck else { return true }
    let setting = settings.behaviorValue(behaviorToCheck)
    return isBehaviorSettingAvailable(setting, e)
}

private func isAvailableBehaviorSettings(_ behaviorToCheck: String?, _ e: ElementEvent, _ settings: RoamSettingLike) -> Bool {
    guard let behaviorToCheck = behaviorToCheck else { return true }
    let setting: Any?
    switch behaviorToCheck {
    case "zoomOnMouseWheel": setting = settings.zoomOnMouseWheel
    case "moveOnMouseMove": setting = settings.moveOnMouseMove
    case "moveOnMouseWheel": setting = settings.moveOnMouseWheel
    default: setting = nil
    }
    return isBehaviorSettingAvailable(setting, e)
}

private func isBehaviorSettingAvailable(_ setting: Any?, _ e: ElementEvent) -> Bool {
    // `setting && (!isString(setting) || e.event[setting+'Key'])`.
    if let b = setting as? Bool {
        return b
    }
    if setting is String {
        // PORT-TODO: modifier-key gating ('ctrl'|'shift'|'alt') — the port's ZRRawEvent carries no
        //   shiftKey/ctrlKey/altKey, so a string-configured behavior cannot be verified and is treated
        //   as unavailable. Graph roam uses boolean flags, so this is not exercised there.
        return false
    }
    // Non-bool, non-string truthy (e.g. a number) — treat truthy.
    return setting != nil
}
