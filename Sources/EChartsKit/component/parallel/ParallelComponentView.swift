// Ported from echarts/src/component/parallel/ParallelView.ts — keep in sync with upstream
//   (plus the per-axis backdrop drawer echarts/src/component/axis/ParallelAxisView.ts — see the
//    second class below).
//
// NOTE: file/class renamed ParallelView -> ParallelComponentView (file) to avoid a SwiftPM object-file
//   basename collision with the chart-side `chart/parallel/ParallelView.swift` (SwiftPM requires unique
//   source basenames per module; cf. RadarComponentView.swift's RadarView.ts rename, and
//   ComponentView.swift's Component.swift rename). The upstream identifiers are preserved semantically:
//   the interaction component view's registered `type` is still `'parallel'` and the per-axis view's
//   registered `type` is still `'parallelAxis'`.
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

// ================================================================================================
// upstream file 1 — echarts/src/component/parallel/ParallelView.ts
//
// This component view carries NO axis drawing. It only wires the whole-coordinate-system pointer
// interaction (axis-expand on click / mousemove, throttled + debounced) — now PORTED in full: the
// mousedown/mouseup/mousemove handler table is registered on `getZr()`, gated by `checkTrigger`,
// throttled via `util/throttle.createOrUpdate`, and dispatches the `parallelAxisExpand` action. The
// per-axis brush/areaSelect drawing (in `ParallelAxisView` below) remains deferred (BrushController
// seam). The visible N-axis backdrop is produced by the `ParallelAxisView` below (upstream file 2).
//
// upstream imports (mapped to this port; `→` marks the Swift symbol used):
//   import GlobalModel from '../../model/Global';                        → `GlobalModel`.
//   import ParallelModel, { ParallelCoordinateSystemOption }
//       from '../../coord/parallel/ParallelModel';
//     → PORT-NOTE: `coord/parallel/ParallelModel` (ported with the parallel COORD port).
//       API: `open class ParallelModel: ComponentModel` with
//       `var coordinateSystem: Parallel?` and the standard Model `get` surface (reads
//       `axisExpandRate` / `axisExpandDebounce` / `axisExpandable` / `axisExpandTriggerOn`).
//   import ExtensionAPI from '../../core/ExtensionAPI';                  → `ExtensionAPI`.
//   import ComponentView from '../../view/Component';                    → `ComponentView`.
//   import { ElementEventName } from 'zrender/src/core/types';           → String event name.
//   import { ElementEvent } from 'zrender/src/Element';                  → `ElementEvent` (offsetX/offsetY).
//   import { ParallelAxisExpandPayload } from '../axis/parallelAxisAction';
//     → PORT-NOTE: `component/axis/parallelAxisAction` (the axisExpand/axisAreaSelect actions) is ported;
//       the pointer/brush interaction that dispatches them from this view is still deferred. The payload
//       is modeled as a `[String: Any]` bag.
//   import { each, bind, extend } from 'zrender/src/core/util';         → `util.*` (ZRenderKit).
//   import { ThrottleController, createOrUpdate, clear } from '../../util/throttle';
//     → PORT-NOTE (deferred): requires `util/throttle` (throttle/debounce controller), NOT ported.
//       Deferred with the interaction seam; the `createOrUpdate`/`clear`/`debounceNextCall` call sites
//       below are correspondingly deferred.
// ================================================================================================

// upstream: const CLICK_THRESHOLD = 5; // > 4
private let CLICK_THRESHOLD: Double = 5 // > 4

// upstream: type ElementEventHandler = (this: ParallelView, e: ElementEvent) => void;
//   Named `ParallelElementEventHandler` to avoid clashing with any same-module `ElementEventHandler`.
//   The upstream `this: ParallelView` receiver is passed explicitly as the first param (`view`) — the
//   registered `bind(handler, this)` binds it to the view instance.
typealias ParallelElementEventHandler = (_ view: ParallelComponentView, _ e: ElementEvent) -> Void

// upstream: class ParallelView extends ComponentView
// CONVENTIONS §2/§4: reference type extending the reference `ComponentView` → `final class`.
// NOTE: class renamed ParallelView -> ParallelComponentView to avoid a same-module name collision
//   with the chart-side `chart/parallel/ParallelView.swift` (ChartView). Registered as the
//   'parallel' component view factory.
public final class ParallelComponentView: ComponentView {

    // static type = 'parallel';
    public static let type = "parallel"
    // readonly type = ParallelView.type;
    public let type = "parallel"

    // @internal _model: ParallelModel;
    // PORT-NOTE: `coord/parallel/ParallelModel` is ported; this field is kept typed `Any?` here to avoid
    //   an import cycle. upstream: `ParallelModel`.
    var _model: Any?   // upstream: ParallelModel

    // private _api: ExtensionAPI;
    private var _api: ExtensionAPI?

    // @internal _mouseDownPoint: number[];
    var _mouseDownPoint: [Double]?

    // private _handlers: Partial<Record<ElementEventName, ElementEventHandler>>;
    //   PORT-NOTE: stores the BOUND `EventCallback`s registered on `getZr()` (upstream stores the
    //   `bind(handler, this)` results), keyed by event name — so `dispose` can `getZr().off(...)` them.
    private var _handlers: [String: EventCallback]?

    // upstream: the throttled `_throttledDispatchExpand` method. `util/throttle.ts` cannot swap a method
    //   on a live Swift instance, so the throttled wrapper is held in this slot (the closure-slot
    //   adaptation of upstream's `obj[fnAttr]` swap — see throttleUtil.createOrUpdate). Built/updated in
    //   `render` via `createOrUpdate`, cleared in `dispose` via `clear`.
    fileprivate var _throttledDispatch: ThrottledFunction?

    // The opt bag the throttled dispatch will fire with. Upstream's throttle captures the call `args`
    //   (`fn.apply(scope, args)`); this port's `ThrottledFunction` is nullary, so the latest opt is
    //   stashed here and read by the origin closure at exec time (fixRate → latest call wins, matching
    //   the upstream roaming semantics). `nil` = "cancel the last trigger" (behavior === 'none').
    private var _pendingExpandOpt: [String: Any]?

    // upstream: render(parallelModel: ParallelModel, ecModel, api)
    //   The base `ComponentView.render` signature is (model, ecModel, api, payload); the concrete
    //   `ParallelModel` is recovered by downcast at the call site (pattern shared with RadarComponentView).
    public override func render(
        _ parallelModel: ComponentModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        // upstream: this._model = parallelModel;
        self._model = parallelModel
        // upstream: this._api = api;
        self._api = api

        // upstream:
        //   if (!this._handlers) {
        //       this._handlers = {};
        //       each(handlers, function (handler, eventName) {
        //           api.getZr().on(eventName, this._handlers[eventName] = bind(handler, this));
        //       }, this);
        //   }
        //   Register the pointer handlers ONCE on the zrender event bus. `bind(handler, this)` → an
        //   `EventCallback` that (a) unpacks the `ElementEvent` from `args[0]` and (b) calls the handler
        //   with the view as the explicit `this`. `ctx` is passed `nil` (NOT `self`): the `Eventful`
        //   stores ctx strongly and zr is strongly reachable, so `self` there would form a retain cycle —
        //   the closures already capture `[weak self]` (cf. EChartsView's zr.on wiring).
        if self._handlers == nil {
            self._handlers = [:]
            let zr = api.getZr()
            for (eventName, handler) in handlers {
                let cb: EventCallback = { [weak self] _, args in
                    guard let self = self, let e = args.first as? ElementEvent else { return nil }
                    handler(self, e)
                    return nil
                }
                self._handlers?[eventName] = cb
                _ = zr?.on(eventName, cb, nil)
            }
        }

        // upstream: createOrUpdate(this, '_throttledDispatchExpand',
        //     parallelModel.get('axisExpandRate'), 'fixRate');
        //   The closure-slot adaptation returns the throttled wrapper to store back (see throttleUtil).
        //   `axisExpandRate` read with `numOpt` (Int-vs-Double option trap — the default `17` is boxed
        //   Int). The origin closure fires `_dispatchExpand` with the latest stashed opt.
        self._throttledDispatch = throttleUtil.createOrUpdate(
            existing: self._throttledDispatch,
            origin: { [weak self] in self?._dispatchExpand(self?._pendingExpandOpt) },
            rate: numOpt(parallelModel.get("axisExpandRate")),
            throttleType: .fixRate
        )
        _ = payload
    }

    // upstream: dispose(ecModel, api)
    public override func dispose(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        // upstream:
        //   clear(this, '_throttledDispatchExpand');
        //   each(this._handlers, function (handler, eventName) { api.getZr().off(eventName, handler); });
        //   this._handlers = null;
        // `clear` cancels any pending throttle timer and restores the origin (→ nil slot here).
        self._throttledDispatch = throttleUtil.clear(self._throttledDispatch)
        // NOTE: `Eventful.off(event, handler)` cannot filter a specific closure by identity (Swift
        //   closures are not comparable — documented divergence in Eventful.off), so this is effectively
        //   a no-op; the stale handlers remain but are inert (their `[weak self]` returns early once the
        //   view is gone). Kept structurally faithful to upstream.
        let zr = api.getZr()
        if let handlers = self._handlers {
            for (eventName, handler) in handlers {
                zr?.off(eventName, handler)
            }
        }
        self._handlers = nil
    }

    /**
     * @internal
     * @param {Object} [opt] If null, cancel the last action triggering for debounce.
     */
    // upstream: _throttledDispatchExpand(opt: Omit<ParallelAxisExpandPayload, 'type'>): void
    //   In upstream this method body IS `this._dispatchExpand(opt)`, but `createOrUpdate` REPLACES the
    //   method with a throttled wrapper (whose origin is this body). The closure-slot adaptation keeps
    //   the wrapper in `_throttledDispatch`; here we stash the opt and fire the wrapper (falling back to
    //   the unthrottled body when no wrapper exists — mirroring `createOrUpdate` returning the originFn).
    func _throttledDispatchExpand(_ opt: [String: Any]?) {
        self._pendingExpandOpt = opt
        if let throttled = self._throttledDispatch {
            throttled()
        }
        else {
            self._dispatchExpand(opt)
        }
    }

    /**
     * @internal
     */
    // upstream: _dispatchExpand(opt: Omit<ParallelAxisExpandPayload, 'type'>)
    func _dispatchExpand(_ opt: [String: Any]?) {
        // upstream: opt && this._api.dispatchAction(extend({ type: 'parallelAxisExpand' }, opt));
        //   `extend({ type: 'parallelAxisExpand' }, opt)` → a Payload whose extra keys (`axisExpandWindow`,
        //   `animation`) ride on the dynamic `.other` bag (the `parallelAxisExpand` action reads
        //   `axisExpandWindow` off it via `setAxisExpand`). `nil` opt cancels the trigger (no dispatch).
        guard let opt = opt else { return }
        var action = Payload(type: "parallelAxisExpand")
        for (k, v) in opt {
            action.other[k] = v
        }
        self._api?.dispatchAction(action)
    }
}

// upstream:
//   const handlers: Partial<Record<ElementEventName, ElementEventHandler>> = { mousedown, mouseup, mousemove };
//   The pointer-interaction handler table (mousedown/mouseup/mousemove → axis-expand). Each handler
//   receives the view as the explicit `this` (first param) and the `ElementEvent`. Registered on the
//   zrender event bus in `render` (see there).
private let handlers: [String: ParallelElementEventHandler] = [
    // mousedown(e): if (checkTrigger(this, 'click')) { this._mouseDownPoint = [e.offsetX, e.offsetY]; }
    "mousedown": { view, e in
        if checkTrigger(view, "click") {
            view._mouseDownPoint = [e.offsetX, e.offsetY]
        }
    },
    // mouseup(e): a click (within CLICK_THRESHOLD of the mousedown) triggers an axis-expand dispatch.
    "mouseup": { view, e in
        let mouseDownPoint = view._mouseDownPoint
        if checkTrigger(view, "click"), let mouseDownPoint = mouseDownPoint {
            let point = [e.offsetX, e.offsetY]
            // const dist = Math.pow(dx, 2) + Math.pow(dy, 2);
            let dist = pow(mouseDownPoint[0] - point[0], 2) + pow(mouseDownPoint[1] - point[1], 2)
            // if (dist > CLICK_THRESHOLD) { return; }  — NOTE: returns WITHOUT resetting _mouseDownPoint.
            if dist > CLICK_THRESHOLD {
                return
            }
            // const result = this._model.coordinateSystem.getSlidedAxisExpandWindow([e.offsetX, e.offsetY]);
            if let coordSys = view._coordinateSystem() {
                let result = coordSys.getSlidedAxisExpandWindow([e.offsetX, e.offsetY])
                // result.behavior !== 'none' && this._dispatchExpand({ axisExpandWindow: ... });
                if result.behavior != "none" {
                    view._dispatchExpand(["axisExpandWindow": result.axisExpandWindow])
                }
            }
        }
        view._mouseDownPoint = nil
    },
    // mousemove(e): slide/jump the expand window (throttled; jump debounced). No-op while brushing
    //   (a mousedown is in progress).
    "mousemove": { view, e in
        // Should do nothing when brushing.
        if view._mouseDownPoint != nil || !checkTrigger(view, "mousemove") {
            return
        }
        guard let coordSys = view._coordinateSystem() else { return }
        let result = coordSys.getSlidedAxisExpandWindow([e.offsetX, e.offsetY])
        let behavior = result.behavior
        // behavior === 'jump' && (this._throttledDispatchExpand ...).debounceNextCall(get('axisExpandDebounce'));
        if behavior == "jump" {
            view._throttledDispatch?.debounceNextCall(view._axisExpandDebounce())
        }
        // this._throttledDispatchExpand(behavior === 'none' ? null : { axisExpandWindow, animation });
        if behavior == "none" {
            // Cancel the last trigger, in case that mouse slide out of the area quickly.
            view._throttledDispatchExpand(nil)
        }
        else {
            var opt: [String: Any] = ["axisExpandWindow": result.axisExpandWindow]
            // Jumping uses animation, and sliding suppresses animation ({ duration: 0 }); jump → null (absent).
            if behavior != "jump" {
                opt["animation"] = ["duration": 0.0]
            }
            view._throttledDispatchExpand(opt)
        }
    }
]

// upstream:
//   function checkTrigger(view: ParallelView, triggerOn): boolean {
//       const model = view._model;
//       return model.get('axisExpandable') && model.get('axisExpandTriggerOn') === triggerOn;
//   }
//   Gates the pointer handlers: interaction fires only when `axisExpandable` is truthy AND the configured
//   `axisExpandTriggerOn` ('click' | 'mousemove') matches the handler's trigger.
private func checkTrigger(_ view: ParallelComponentView, _ triggerOn: String) -> Bool {
    guard let model = view._model as? ParallelModel else { return false }
    return jsTruthy(model.get("axisExpandable"))
        && (model.get("axisExpandTriggerOn") as? String) == triggerOn
}

// export default ParallelView;  -> `public final class ParallelView` above.

// PARALLEL-VIEW interaction helpers (narrow the `Any?` _model to the concrete coord/model surface).
extension ParallelComponentView {
    // `this._model.coordinateSystem` — the `Parallel` coord system (getSlidedAxisExpandWindow).
    func _coordinateSystem() -> Parallel? {
        return (self._model as? ParallelModel)?.coordinateSystem as? Parallel
    }
    // `model.get('axisExpandDebounce')` — read with numOpt (Int-vs-Double option trap; default `50`).
    func _axisExpandDebounce() -> Double {
        return numOpt((self._model as? ParallelModel)?.get("axisExpandDebounce")) ?? 0
    }
}


// ================================================================================================
// Ported from echarts/src/component/axis/ParallelAxisView.ts — keep in sync with upstream
//
// This is the per-axis backdrop drawer: one `ParallelAxisView` per `parallelAxis` component. It draws a
// single parallel axis (axis line + ticks + labels) via the ported `AxisBuilder`, placed with the
// per-axis `position` / `rotation` supplied by the Parallel coord layout (`coordSys.getAxisLayout(dim)`).
// The N-axis backdrop is the composition of the N registered `parallelAxis` component views.
//
// The brush/areaSelect drawing (BrushController mount/panels/covers, the `axisAreaSelect` action, and
// the active-interval covers) is DEFERRED per the task scope — those paths are PORT-NOTE below.
//
// upstream imports (mapped to this port; `→` marks the Swift symbol used):
//   import * as zrUtil from 'zrender/src/core/util';                    → `util.*` (ZRenderKit).
//   import AxisBuilder from './AxisBuilder';                            → `AxisBuilder` (component/axis).
//   import BrushController, { ... } from '../helper/BrushController';
//     → PORT-NOTE (deferred): requires `component/helper/BrushController` (brush interaction seam), NOT ported.
//   import * as brushHelper from '../helper/brushHelper';
//     → PORT-NOTE (deferred): requires `component/helper/brushHelper` (brush panels/clip), NOT ported.
//   import * as graphic from '../../util/graphic';
//     → `graphic.Group` is the ZRenderKit `Group`; `graphic.BoundingRect` is ZRenderKit
//       `BoundingRect` (used only in the deferred brush rect); `graphic.groupTransition` is the
//       ported top-level free func in `util/graphic.swift` (called bare, see `render`).
//   import ComponentView from '../../view/Component';                   → `ComponentView`.
//   import ExtensionAPI from '../../core/ExtensionAPI';                 → `ExtensionAPI`.
//   import GlobalModel from '../../model/Global';                       → `GlobalModel`.
//   import ParallelAxisModel, { ParallelAreaSelectStyleProps }
//       from '../../coord/parallel/AxisModel';
//     → PORT-NOTE: `coord/parallel/AxisModel` (ported as `ParallelAxisModel.swift`, NOT the
//       generic `AxisModel.swift`). API:
//       `open class ParallelAxisModel: <AxisBaseModel>` (so it satisfies `AxisBuilder`'s
//       `AxisBaseModel` param) with `var axis: ParallelAxis` (typed `Any` on AxisBaseModel),
//       `func getAreaSelectStyle() -> [String: Any]` (the makeStyleMapper bag: fill/lineWidth/stroke/
//       width/opacity), `var activeIntervals: [[Double]]`, and `coordinateSystem: Parallel`.
//   import { Payload } from '../../util/types';                         → `Payload`.
//   import ParallelModel from '../../coord/parallel/ParallelModel';     → see file-1 PORT-NOTE.
//   import { ParallelAxisLayoutInfo } from '../../coord/parallel/Parallel';
//     → PORT-NOTE: `coord/parallel/Parallel.ParallelAxisLayoutInfo` (ported) is the per-axis layout struct
//       (position: [Double], rotation, transform, axisNameAvailableWidth, axisLabelShow,
//       nameTruncateMaxWidth, tickDirection: -1|1, labelDirection: -1|1).
//
// Assumed sibling coord/parallel API (from the coord port):
//   Parallel (CoordinateSystemMaster):
//     func getAxisLayout(_ dim: String) -> ParallelAxisLayoutInfo
//     func getSlidedAxisExpandWindow(_ point: [Double]) -> ...   // DEFERRED (interaction)
//   ParallelAxis (open class ParallelAxis: Axis):
//     var dim: String
//     func getExtent() -> [Double]
//     func dataToCoord(_ v: Double, _ clamp: Bool) -> Double     // DEFERRED (brush covers)
//     func coordToData(_ v: Double, _ clamp: Bool) -> Double     // DEFERRED (brush onBrush)
// ================================================================================================

// upstream: class ParallelAxisView extends ComponentView
// CONVENTIONS §2/§4: reference type extending the reference `ComponentView` → `final class`.
public final class ParallelAxisView: ComponentView {

    // static type = 'parallelAxis';
    public static let type = "parallelAxis"
    // readonly type = ParallelAxisView.type;
    public let type = "parallelAxis"

    // private _brushController: BrushController;
    // PORT-NOTE (deferred): requires `BrushController` (brush interaction seam), NOT ported; typed `Any?`.
    private var _brushController: Any?

    // private _axisGroup: graphic.Group;
    private var _axisGroup: Group!

    // axisModel: ParallelAxisModel;
    // PORT-NOTE: `ParallelAxisModel` is ported; this field is kept typed `Any?` here (resolved via the
    //   file-private shims below). upstream: ParallelAxisModel.
    var axisModel: Any?   // upstream: ParallelAxisModel

    // api: ExtensionAPI;
    var api: ExtensionAPI?

    // upstream:
    //   init(ecModel, api) {
    //       super.init.apply(this, arguments);
    //       (this._brushController = new BrushController(api.getZr()))
    //           .on('brush', zrUtil.bind(this._onBrush, this));
    //   }
    // PORT-NOTE (deferred): the BrushController construction/mount is DEFERRED (brush interaction seam,
    //   requires BrushController). The base `ComponentView.init(ecModel, api)` is a no-op; nothing else
    //   to do statically.
    public override func `init`(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        super.`init`(ecModel, api)
        // PORT-NOTE (deferred): this._brushController = new BrushController(api.getZr()).on('brush', ...);
    }

    // upstream: render(axisModel: ParallelAxisModel, ecModel, api, payload)
    //   The concrete `ParallelAxisModel` is recovered by downcast (pattern shared with CartesianAxisView).
    public override func render(
        _ axisModel: ComponentModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        // upstream: if (fromAxisAreaSelect(axisModel, ecModel, payload)) { return; }
        if fromAxisAreaSelect(axisModel, ecModel, payload) {
            return
        }

        // upstream: this.axisModel = axisModel; this.api = api;
        self.axisModel = axisModel
        self.api = api

        // upstream: this.group.removeAll();
        self.group.removeAll()

        // upstream: const oldAxisGroup = this._axisGroup; this._axisGroup = new graphic.Group();
        let oldAxisGroup = self._axisGroup
        self._axisGroup = Group()
        // upstream: this.group.add(this._axisGroup);
        _ = self.group.add(self._axisGroup)

        // upstream: if (!axisModel.get('show')) { return; }
        if !jsTruthy(axisModel.get("show")) {
            return
        }

        // upstream: const coordSysModel = getCoordSysModel(axisModel, ecModel);
        //   PORT-NOTE: `getCoordSysModel` returns the `ParallelModel` (ported); typed `Any` here and
        //   narrowed via the file-private shims below.
        let coordSysModel = getCoordSysModel(axisModel, ecModel)
        // upstream: const coordSys = coordSysModel.coordinateSystem;
        //   PORT-NOTE: `coordSysModel.coordinateSystem` is the concrete `Parallel` coord system (ported,
        //   API `getAxisLayout(dim)`). Referenced conventionally via the shims below.
        let coordSys = coordSysModelCoordinateSystem(coordSysModel)

        // upstream: const areaSelectStyle = axisModel.getAreaSelectStyle();
        //   PORT-NOTE: `ParallelAxisModel.getAreaSelectStyle()` returns the makeStyleMapper bag
        //   (`ParallelAreaSelectStyleProps` == fill/lineWidth/stroke/width/opacity) as `[String: Any]`.
        let areaSelectStyle = parallelAxisModelGetAreaSelectStyle(axisModel)
        // upstream: const areaWidth = areaSelectStyle.width;
        //   Read with `numOpt` (NOT a bare `as? Double`) — the Int-vs-Double option-read trap
        //   (CONVENTIONS trap #1): the makeStyleMapper default `width: 20` is a bare Int literal.
        let areaWidth = numOpt(areaSelectStyle["width"])

        // upstream: const dim = axisModel.axis.dim;
        //   PORT-NOTE: `ParallelAxisModel.axis` is a `ParallelAxis` (typed `Any` on AxisBaseModel); `dim`
        //   is the `DimensionName` (String). Read via the conventional accessor.
        let dim = parallelAxisModelAxisDim(axisModel)

        // upstream: const axisLayout = coordSys.getAxisLayout(dim);
        //   PORT-NOTE: returns `ParallelAxisLayoutInfo` from the ported `Parallel` coord.
        let axisLayout = parallelGetAxisLayout(coordSys, dim)

        // upstream: const builderOpt = zrUtil.extend({strokeContainThreshold: areaWidth}, axisLayout);
        //   `extend(target, source)` copies `axisLayout`'s fields onto `{strokeContainThreshold}`. Mapped
        //   onto the typed `AxisBuilderCfg`: `ParallelAxisLayoutInfo` supplies position/rotation/
        //   tickDirection/labelDirection/axisLabelShow/axisNameAvailableWidth/nameTruncateMaxWidth; the
        //   `transform` field is NOT part of `AxisBuilderCfg` upstream and is dropped (same as
        //   CartesianAxisView dropping `CartesianAxisLayout.z2`).
        var builderOpt = AxisBuilderCfg(
            position: axisLayout.position,
            rotation: axisLayout.rotation,
            tickDirection: axisLayout.tickDirection,
            labelDirection: axisLayout.labelDirection,
            axisLabelShow: axisLayout.axisLabelShow,
            axisNameAvailableWidth: axisLayout.axisNameAvailableWidth,
            strokeContainThreshold: areaWidth,
            nameTruncateMaxWidth: axisLayout.nameTruncateMaxWidth
        )

        // upstream: const axisBuilder = new AxisBuilder(axisModel, api, builderOpt);
        //   PORT-NOTE: `ParallelAxisModel` (ported) satisfies `AxisBuilder`'s `AxisBaseModel` parameter (it
        //   mixes in `AxisModelCommonMixin` upstream). Passed via the conventional AxisBaseModel view.
        let axisBuilder = AxisBuilder(parallelAxisModelAsAxisBaseModel(axisModel), api, builderOpt)

        // upstream: axisBuilder.build();
        _ = axisBuilder.build()

        // upstream: this._axisGroup.add(axisBuilder.group);
        _ = self._axisGroup.add(axisBuilder.group)

        // upstream: this._refreshBrushController(builderOpt, areaSelectStyle, axisModel,
        //     coordSysModel, areaWidth, api);
        // PORT-NOTE (deferred): the brush controller refresh (select-area rect, panels, covers) is DEFERRED
        //   (brush interaction seam, requires BrushController). The static axis backdrop above is complete
        //   without it.
        self._refreshBrushController(&builderOpt, areaSelectStyle, axisModel, coordSysModel, areaWidth, api)

        // upstream: graphic.groupTransition(oldAxisGroup, this._axisGroup, axisModel);
        //   PORT-NOTE: `groupTransition` is ported in `util/graphic.swift` as a bare top-level free func
        //   (the `graphic.` qualifier is dropped). It matches old/new elements by `anid` and animates
        //   each freshly-built element from its old pose to its new one.
        groupTransition(oldAxisGroup, self._axisGroup, axisModel)
    }

    // upstream:
    //   _refreshBrushController(builderOpt, areaSelectStyle, axisModel, coordSysModel, areaWidth, api) {
    //       const extent = axisModel.axis.getExtent();
    //       const extentLen = extent[1] - extent[0];
    //       const extra = Math.min(30, Math.abs(extentLen) * 0.1);
    //       const rect = graphic.BoundingRect.create({
    //           x: extent[0], y: -areaWidth / 2, width: extentLen, height: areaWidth });
    //       rect.x -= extra; rect.width += 2 * extra;
    //       this._brushController
    //           .mount({ enableGlobalPan: true, rotation: builderOpt.rotation,
    //                    x: builderOpt.position[0], y: builderOpt.position[1] })
    //           .setPanels([{ panelId: 'pl',
    //               clipPath: brushHelper.makeRectPanelClipPath(rect),
    //               isTargetByCursor: brushHelper.makeRectIsTargetByCursor(rect, api, coordSysModel),
    //               getLinearBrushOtherExtent: brushHelper.makeLinearBrushOtherExtent(rect, 0) }])
    //           .enableBrush({ brushType: 'lineX', brushStyle: areaSelectStyle, removeOnClick: true })
    //           .updateCovers(getCoverInfoList(axisModel));
    //   }
    // PORT-NOTE (deferred): brush/areaSelect drawing — requires BrushController + brushHelper, NOT ported.
    //   The whole body reaches the brush interaction seam. Signature preserved so it re-syncs 1:1.
    func _refreshBrushController(
        _ builderOpt: inout AxisBuilderCfg,
        _ areaSelectStyle: [String: Any],
        _ axisModel: ComponentModel,
        _ coordSysModel: Any,
        _ areaWidth: Double?,
        _ api: ExtensionAPI
    ) {
        // PORT-NOTE (deferred): brush controller mount/panels/covers — requires BrushController (see method comment above).
        _ = (builderOpt, areaSelectStyle, axisModel, coordSysModel, areaWidth, api)
    }

    // upstream:
    //   _onBrush(eventParam) {
    //       const coverInfoList = eventParam.areas;
    //       const axisModel = this.axisModel;
    //       const axis = axisModel.axis;
    //       const intervals = zrUtil.map(coverInfoList, coverInfo => [
    //           axis.coordToData(coverInfo.range[0], true), axis.coordToData(coverInfo.range[1], true)]);
    //       if (!axisModel.option.realtime === eventParam.isEnd || eventParam.removeOnClick) {
    //           this.api.dispatchAction({ type: 'axisAreaSelect',
    //               parallelAxisId: axisModel.id, intervals: intervals });
    //       }
    //   }
    // PORT-NOTE (deferred): brush selection path (emits the `axisAreaSelect` action) — requires
    //   BrushController. Not wired.
    func _onBrush(_ eventParam: Any) {
        // PORT-NOTE (deferred): brush→axisAreaSelect action dispatch — requires BrushController.
        _ = eventParam
    }

    // upstream: dispose() { this._brushController.dispose(); }
    public override func dispose(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        // PORT-NOTE (deferred): this._brushController.dispose() — requires BrushController (brush seam), NOT ported.
        _ = (ecModel, api)
    }
}

// upstream:
//   function fromAxisAreaSelect(axisModel, ecModel, payload): boolean {
//       return payload
//           && payload.type === 'axisAreaSelect'
//           && ecModel.findComponents({mainType: 'parallelAxis', query: payload})[0] === axisModel;
//   }
//   Guards `render` against re-running for the axis that originated an `axisAreaSelect` action (the
//   brush realtime path). For the static render path (no such action) this returns `false` and render
//   proceeds. PORT-NOTE: the `axisAreaSelect` action itself is ported (parallelAxisAction); only the
//   brush controller that originates it from this view is deferred. The guard is kept faithful so the
//   static path early-outs correctly.
private func fromAxisAreaSelect(
    _ axisModel: ComponentModel, _ ecModel: GlobalModel, _ payload: Payload
) -> Bool {
    // `payload &&` — `Payload` is a non-optional struct here; upstream guards a possibly-null payload.
    //   The meaningful gate is the type check.
    if payload.type != "axisAreaSelect" {
        return false
    }
    // upstream: ecModel.findComponents({mainType: 'parallelAxis', query: payload})[0] === axisModel
    //   Upstream passes the whole `payload` as `query`; its component-query fields live in `payload.other`
    //   (cf. TreemapView.getModelStatesFor / findComponents usage).
    let found = ecModel.findComponents(
        QueryConditionKindA(mainType: "parallelAxis", query: payload.other)
    )
    guard let first = found.first else { return false }
    return (first as AnyObject) === (axisModel as AnyObject)
}

// upstream:
//   function getCoverInfoList(axisModel): BrushCoverConfig[] {
//       const axis = axisModel.axis;
//       return zrUtil.map(axisModel.activeIntervals, interval => ({
//           brushType: 'lineX', panelId: 'pl',
//           range: [axis.dataToCoord(interval[0], true), axis.dataToCoord(interval[1], true)] }));
//   }
// PORT-NOTE (deferred): active-interval → brush cover mapping (feeds the deferred BrushController.
//   updateCovers) — requires BrushController. Reads `ParallelAxisModel.activeIntervals` and
//   `ParallelAxis.dataToCoord`.

// upstream:
//   function getCoordSysModel(axisModel, ecModel): ParallelModel {
//       return ecModel.getComponent('parallel', axisModel.get('parallelIndex')) as ParallelModel;
//   }
//   PORT-NOTE: upstream returns a typed `ParallelModel` (ported); returned as `Any` here and narrowed
//   via the file-private shims below.
private func getCoordSysModel(_ axisModel: ComponentModel, _ ecModel: GlobalModel) -> Any {
    // upstream: axisModel.get('parallelIndex') — read with `numOpt` (Int-vs-Double option trap #1).
    let parallelIndex = numOpt(axisModel.get("parallelIndex"))
    return ecModel.getComponent("parallel", parallelIndex) as Any
}

// export default ParallelAxisView;  -> `public final class ParallelAxisView` above.


// ================================================================================================
// FILE-PRIVATE SIBLING SHIMS
// Thin stand-ins for coord/parallel sibling APIs that land with the PARALLEL COORD port (not yet in
// Sources). They keep the render body above byte-faithful to upstream while the concrete
// `Parallel` / `ParallelAxis` / `ParallelAxisModel` / `ParallelModel` types are unavailable. Delete
// each when its real sibling lands and call the sibling directly. (Mirrors the file-private helper
// pattern in SingleAxisView / RadiusAxisView.)
// ================================================================================================

// `coordSysModel.coordinateSystem` — the `Parallel` coord system. Now that the coord port has landed,
//   the real accessor is `(coordSysModel as! ParallelModel).coordinateSystem`.
private func coordSysModelCoordinateSystem(_ coordSysModel: Any) -> Any {
    return (coordSysModel as! ParallelModel).coordinateSystem as Any
}

// `coordSys.getAxisLayout(dim)` — the Parallel coord layout for one dim.
private func parallelGetAxisLayout(_ coordSys: Any, _ dim: String) -> ParallelAxisLayoutInfo {
    return (coordSys as! Parallel).getAxisLayout(dim)
}

// `ParallelAxisModel.getAreaSelectStyle()` — the makeStyleMapper bag.
private func parallelAxisModelGetAreaSelectStyle(_ axisModel: ComponentModel) -> [String: Any] {
    if let pam = axisModel as? ParallelAxisModel {
        return pam.getAreaSelectStyle()
    }
    // Fallback (defensive): the install.ts default areaSelectStyle bag.
    return ["width": 20, "lineWidth": 1, "opacity": 0.3]
}

// `ParallelAxisModel.axis.dim` — the axis `DimensionName`.
private func parallelAxisModelAxisDim(_ axisModel: ComponentModel) -> String {
    if let pam = axisModel as? ParallelAxisModel, let pAxis = pam.axis as? ParallelAxis {
        return pAxis.dim
    }
    return ""
}

// PORT-NOTE: view `ParallelAxisModel` (ported) as the `AxisBaseModel` that `AxisBuilder.init` requires
//   (ParallelAxisModel mixes in `AxisModelCommonMixin` upstream, so it IS an AxisBaseModel). Resolved via
//   a force-cast here; upstream passes `axisModel` directly.
private func parallelAxisModelAsAxisBaseModel(_ axisModel: ComponentModel) -> AxisBaseModel {
    // ParallelAxisModel IS an AxisBaseModel (it mixes AxisModelCommonMixin upstream).
    return axisModel as! AxisBaseModel
}

/// Coerce a dynamic option value to Double, tolerating the Int boxing that `[String: Any]`
/// defaultOption literals use (e.g. a bare `"width": 20`). A bare `as? Double` returns nil on an Int,
/// silently dropping the value — the recurring Int-vs-Double option-read trap (CONVENTIONS trap #1).
private func numOpt(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber, !(n === kCFBooleanTrue || n === kCFBooleanFalse) { return n.doubleValue }
    return nil
}

/// JS truthiness for the dynamic option bag (`if (x)` on `get(...)` results); mirrors the same
/// file-private helper in CartesianAxisView/SingleAxisView (CONVENTIONS §6).
private func jsTruthy(_ v: Any?) -> Bool {
    guard let v = v else { return false }
    if let b = v as? Bool { return b }
    if let d = v as? Double { return d != 0 && !d.isNaN }
    if let i = v as? Int { return i != 0 }
    if let s = v as? String { return !s.isEmpty }
    return true
}
