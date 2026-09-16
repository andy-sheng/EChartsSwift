// Ported from echarts/src/view/Chart.ts — keep in sync with upstream
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

// upstream imports:
//   import {each} from 'zrender/src/core/util';                 -> `util.each` (ZRenderKit).
//   import Group from 'zrender/src/graphic/Group';              -> `Group` (ZRenderKit).
//   import * as componentUtil from '../util/component';         -> `component` namespace (util/componentUtil.swift).
//   import * as clazzUtil from '../util/clazz';                 -> `clazz` namespace (util/clazz.swift).
//   import * as modelUtil from '../util/model';                 -> `model` namespace (util/modelUtil.swift; upstream alias `modelUtil`).
//   import { enterEmphasis, leaveEmphasis, getHighlightDigit, isHighDownDispatcher } from '../util/states';
//       -> `states` namespace (util/states.swift). See `elSetState`/`toggleHighlight`.
//   import {createTask, TaskResetCallbackReturn} from '../core/task';   -> sibling core/task.swift.
//   import createRenderPlanner from '../chart/helper/createRenderPlanner';  -> sibling chart/helper/createRenderPlanner.swift.
//   import SeriesModel from '../model/Series';                  -> `SeriesModel` (model/Series.swift).
//   import GlobalModel from '../model/Global';                  -> `GlobalModel` (model/Global.swift).
//   import ExtensionAPI from '../core/ExtensionAPI';            -> `ExtensionAPI` (core/ExtensionAPI.swift).
//   import Element from 'zrender/src/Element';                  -> `Element` (ZRenderKit).
//   import { Payload, ViewRootGroup, ECActionEvent, EventQueryItem, StageHandlerPlanReturn,
//            DisplayState, StageHandlerProgressParams, ECElementEvent } from '../util/types';  -> util/types.swift.
//   import { SeriesTaskContext, SeriesTask } from '../core/Scheduler';   -> sibling core/Scheduler.swift.
//   import SeriesData from '../data/SeriesData';                -> `SeriesData` (data/SeriesData.swift).
//   import { traverseElements } from '../util/graphic';         -> note: util/graphic.ts not yet ported; see `eachRendered`.
//   import { error } from '../util/log';                        -> `log.error` (util/log.swift).

// upstream:
//   const inner = modelUtil.makeInner<{ updateMethod: keyof ChartView }, Payload>();
// `makeInner` requires an `AnyObject` host, but `Payload` is a value type (struct) in this
//   port, so per-payload attached state can not be stored/read back through object identity. The
//   `inner(payload).updateMethod` mechanism is therefore inert: `markUpdateMethod` is a documented
//   no-op and `renderTaskReset` treats `updateMethod` as always nil (routing falls through to
//   'render'/'incrementalPrepareRender'). Wire once `Payload` becomes a reference type or an
//   external `[Payload-identity: UpdateMethod]` side-table lands.
private let renderPlanner = createRenderPlanner()

// upstream: interface ChartView { incrementalPrepareRender?; incrementalRender?; updateTransform?;
//   containPoint?; filterForExposedEvent? } — a declaration-merged interface whose members are
//   "implement it if needed" (their *existence* is feature-detected elsewhere, e.g.
//   `!view.incrementalPrepareRender` in Scheduler). Swift can not feature-detect method existence,
//   so these are folded into the class below as `open` methods with note default bodies.
open class ChartView {

    // [Caution]: Because this class or desecendants can be used as `XXX.extend(subProto)`,
    // the class members must not be initialized in constructor or declaration place.
    // Otherwise there is bad case:
    //   class A {xxx = 1;}
    //   enableClassExtend(A);
    //   class B extends A {}
    //   var C = B.extend({xxx: 5});
    //   var c = new C();
    //   console.log(c.xxx); // expect 5 but always 1.
    // Swift has no prototype `extend`; native subclassing is used instead, so the caution
    //   above does not apply. Members that upstream leaves unset (assigned by `protoInitialize`) are
    //   given Swift declaration defaults below.

    // @readonly
    // upstream: type set by `protoInitialize` to 'chart'.
    open var type: String = "chart"

    // upstream: readonly group: ViewRootGroup
    // `ViewRootGroup` (Group augmented with `__ecComponentInfo`) is a protocol stub in
    //   util/types.swift; the concrete `new Group()` is a ZRenderKit `Group`, so `group` is typed as
    //   `Group` here. Revisit once `ViewRootGroup` is a real Group subclass/augmentation.
    public let group: Group

    public let uid: String

    public let renderTask: SeriesTask

    /**
     * Ignore label line update in global stage. Will handle it in chart itself.
     * Used in pie / funnel
     */
    open var ignoreLabelLineUpdate: Bool = false

    // ----------------------
    // Injectable properties
    // ----------------------
    // `__model`/`__id` are non-optional upstream but injected after construction; modeled
    //   as Optional to avoid an initializer requirement.
    open var __alive: Bool = false
    open var __model: SeriesModel?
    open var __id: String?

    // static protoInitialize = (function () { const proto = ChartView.prototype; proto.type = 'chart'; })();
    //   -> expressed as the `type` declaration default above.

    public init() {
        self.group = Group()
        self.uid = component.getUID("viewChart")

        self.renderTask = createTask(TaskDefineParam<SeriesTaskContext>(
            reset: { _, context in renderTaskReset(context) },
            plan: { _, context in renderTaskPlan(context) }
        ))
        // this.renderTask.context = {view: this} as SeriesTaskContext;
        let context = SeriesTaskContext()
        context.view = self
        self.renderTask.context = context
    }

    open func init_(_ ecModel: GlobalModel, _ api: ExtensionAPI) {}
    // NOTE: upstream method name is `init`; renamed `init_` to avoid clashing with Swift's `init`
    //   (the constructor). note: keep call sites in sync (they call `view.init(ecModel, api)`).

    open func render(_ seriesModel: SeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload) {
        if __DEV__ {
            fatalError("render method must been implemented")
        }
    }

    /**
     * Highlight series or specified data item.
     */
    open func highlight(_ seriesModel: SeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload) {
        // upstream: const data = seriesModel.getData(payload && payload.dataType);
        let data = seriesModel.getData(payloadDataType(payload))
        // upstream: if (!data) { if (__DEV__) { error(`Unknown dataType ${payload.dataType}`); } return; }
        // `SeriesModel.getData` returns a non-Optional `SeriesData` in this port (unknown
        //   dataType can not be signalled), so the `!data` guard is vacuous and omitted.
        toggleHighlight(data, payload, .emphasis)
    }

    /**
     * Downplay series or specified data item.
     */
    open func downplay(_ seriesModel: SeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload) {
        let data = seriesModel.getData(payloadDataType(payload))
        // see `highlight` — vacuous `!data` guard omitted.
        toggleHighlight(data, payload, .normal)
    }

    /**
     * `remove` only occurs when series is filtered out, typically by legend.
     * And theirafter the view can only be rendered again via
     * `ChartView['render']` or `ChartView['incrementalPrepareRender']`.
     */
    open func remove(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        self.group.removeAll()
    }

    /**
     * Dispose self.
     */
    open func dispose(_ ecModel: GlobalModel, _ api: ExtensionAPI) {}


    open func updateView(_ seriesModel: SeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload) {
        self.render(seriesModel, ecModel, api, payload)
    }

    // FIXME never used?
    // updateLayout(seriesModel: SeriesModel, ecModel: GlobalModel, api: ExtensionAPI, payload: Payload): void {
    //     this.render(seriesModel, ecModel, api, payload);
    // }

    // FIXME never used?
    open func updateVisual(_ seriesModel: SeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload) {
        self.render(seriesModel, ecModel, api, payload)
    }

    // -------------------------------------------------------------------------------------------
    // upstream `interface ChartView` optional members ("Implement it if needed."), folded in here.
    // -------------------------------------------------------------------------------------------

    /**
     * Rendering preparation in progressive mode.
     * Implement it if needed.
     */
    open func incrementalPrepareRender(
        _ seriesModel: SeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        // optional upstream method; base is a no-op (subclasses override for progressive mode).
    }

    /**
     * Render in progressive mode.
     * Implement it if needed.
     * @param params See taskParams in `stream/task.js`
     */
    open func incrementalRender(
        _ params: StageHandlerProgressParams, _ seriesModel: SeriesModel, _ ecModel: GlobalModel,
        _ api: ExtensionAPI, _ payload: Payload
    ) {
        // optional upstream method; base is a no-op.
    }

    /**
     * Update transform directly.
     * Implement it if needed.
     */
    // upstream return type: `void | {update: true}` — modeled as a TRI-STATE `Bool?`, the SAME contract
    //   as `ComponentView.updateTransform` (see ComponentView.swift), mirroring how upstream
    //   distinguishes "no hook at all" from "hook returned void" (echarts.ts:1964-1990):
    //     `nil`   == the view has NO hook (this base implementation) → `ECharts.updateTransform()`
    //                marks it dirty and falls back to a full render;
    //     `false` == an IMPLEMENTED hook returning upstream's `void` — handled in place, NOT dirtied;
    //     `true`  == upstream `{update: true}`.
    //   So an overriding view that re-lays out in place must return `false`, NOT `nil`.
    open func updateTransform(
        _ seriesModel: SeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) -> Bool? {
        // optional upstream method; base returns nil (no hook).
        return nil
    }

    /**
     * The view contains the given point.
     * Implement it if needed.
     */
    open func containPoint(_ point: [Double], _ seriesModel: SeriesModel) -> Bool {
        // optional upstream method; base returns false.
        return false
    }

    /**
     * Pass only when return `true`.
     * Implement it if needed.
     */
    open func filterForExposedEvent(
        _ eventType: String, _ query: EventQueryItem, _ targetEl: Element, _ packedEvent: Any
    ) -> Bool {
        // upstream `packedEvent: ECActionEvent | ECElementEvent` — the union is erased to `Any` here.
        // optional upstream method; base returns true (default: not filtered out).
        return true
    }

    /**
     * Traverse the new rendered elements.
     *
     * It will traverse the new added element in progressive rendering.
     * And traverse all in normal rendering.
     */
    open func eachRendered(_ cb: (_ el: Element) -> Bool) {
        // upstream: traverseElements(this.group, cb);
        //   which reduces (single, non-array root) to `traverseElement(this.group, cb)`:
        //     let stopped;
        //     if (el.isGroup) { stopped = cb(el); }
        //     if (!stopped) { el.traverse(cb); }
        // util/graphic.traverseElement is `private`, so the polyfill is inlined here to
        //   preserve upstream behavior — `cb` is invoked on the root group element itself first (which
        //   `Group.traverse` alone skips, since it visits children only). The `boolean | void`
        //   callback return maps to the `Bool` "stopped" flag consumed by `Group.traverse`.
        var stopped = false
        if self.group.isGroup {
            stopped = cb(self.group)
        }
        if !stopped {
            self.group.traverse(cb)
        }
    }

    static func markUpdateMethod(_ payload: Payload, _ methodName: String) {
        // upstream: inner(payload).updateMethod = methodName;  (methodName: keyof ChartView)
        // no-op — see the `inner` note at the top of this file (value-type Payload
        //   can not carry `makeInner` state). Kept for call-site compatibility.
        _ = (payload, methodName)
    }

    // upstream: static registerClass: clazzUtil.ClassManager['registerClass'];
    // Deviation (same as ComponentModel): Swift metatypes can not have methods mounted at runtime, so
    // the manager produced by `clazz.enableClassManagement()` is held on a static and `registerClass`
    // forwards to it (see the `enableClassManagement` note below).
    private static let _manager: ClassManager = clazz.enableClassManagement()

    @discardableResult
    public static func registerClass(_ clz: Constructor) -> Constructor {
        return _manager.registerClass(clz)
    }

    /// Convenience: read the dynamic `payload.dataType` field.
    /// upstream: `payload && payload.dataType` — `payload` is non-Optional here, so this reduces to
    /// reading the dynamic `dataType` key from the payload bag (`Payload` has no static `dataType`).
    private func payloadDataType(_ payload: Payload) -> SeriesDataType? {
        return payload.other["dataType"] as? SeriesDataType
    }
}


/**
 * Set state of single element
 */
private func elSetState(_ el: Element?, _ state: DisplayState, _ highlightDigit: Double?) {
    // upstream:
    //   if (el && isHighDownDispatcher(el)) {
    //       (state === 'emphasis' ? enterEmphasis : leaveEmphasis)(el, highlightDigit);
    //   }
    if let el = el, states.isHighDownDispatcher(el) {
        if state == .emphasis {
            states.enterEmphasis(el, highlightDigit)
        } else {
            states.leaveEmphasis(el, highlightDigit)
        }
    }
}

private func toggleHighlight(_ data: SeriesData, _ payload: Payload, _ state: DisplayState) {
    let dataIndex = model.queryDataIndex(data, payload)

    // upstream:
    //   const highlightDigit = (payload && payload.highlightKey != null)
    //       ? getHighlightDigit(payload.highlightKey) : null;
    //   `highlightKey` is a dynamic payload key (carried in `.other`), a numeric key.
    let highlightKeyRaw = payload.other["highlightKey"]
    let highlightDigit: Double?
    if let hk = (highlightKeyRaw as? Int) ?? (highlightKeyRaw as? Double).map({ Int($0) }) {
        highlightDigit = states.getHighlightDigit(hk)
    } else {
        highlightDigit = nil
    }

    if let dataIndex = dataIndex, !(dataIndex is NSNull) {
        util.each(model.normalizeToArray(dataIndex) as [Any]) { dataIdx, _ in
            // `dataIdx` is `number` upstream; coerce to `Int` for `getItemGraphicEl`
            //   (out-of-range/negative indices return nil, matching JS `undefined`).
            let idx = (dataIdx as? Double).map { Int($0) } ?? (dataIdx as? Int) ?? -1
            elSetState(data.getItemGraphicEl(idx), state, highlightDigit)
        }
    }
    else {
        // In progressive mode, `data._graphicEls` has typically no items,
        // thereby skipping this hover style changing.
        // PENDING: more robust approaches?
        data.eachItemGraphicEl({ el, _ in
            elSetState(el, state, highlightDigit)
        })
    }
}

// upstream: export type ChartViewConstructor = typeof ChartView & clazzUtil.ExtendableConstructor & clazzUtil.ClassManager;
// prototype-mounted constructor shape has no Swift equivalent (native subclassing +
//   `ChartView.registerClass` static replace it).

// upstream:
//   clazzUtil.enableClassExtend(ChartView as ChartViewConstructor, ['dispose']);
//   clazzUtil.enableClassManagement(ChartView as ChartViewConstructor);
// `enableClassExtend` is a callable no-op (native subclassing replaces prototype extend);
//   `enableClassManagement` is realized by the static `_manager` on `ChartView` above.


func renderTaskPlan(_ context: SeriesTaskContext) -> StageHandlerPlanReturn? {
    return renderPlanner(context.model!)
}

func renderTaskReset(_ context: SeriesTaskContext) -> TaskResetCallbackReturn<SeriesTaskContext>? {
    let seriesModel = context.model!
    let ecModel = context.ecModel
    let api = context.api
    let payload = context.payload
    // FIXME: remove updateView updateVisual
    let progressiveRender = seriesModel.pipelineContext.progressiveRender
    let view = context.view!

    // upstream:
    //   const updateMethod = payload && inner(payload).updateMethod;
    //   const methodName: keyof ChartView = progressiveRender
    //       ? 'incrementalPrepareRender'
    //       : (updateMethod && view[updateMethod]) ? updateMethod
    //       // `appendData` is also supported when data amount is less than progressive threshold.
    //       : 'render';
    // `updateMethod` is always nil here (value-type Payload can not carry `makeInner`
    //   state — see top-of-file note), so the dynamic `view[updateMethod]` branch is dropped and
    //   `methodName` is either 'incrementalPrepareRender' (progressive) or 'render'.
    let updateMethod: String? = nil
    let methodName: String = progressiveRender
        ? "incrementalPrepareRender"
        : (updateMethod != nil) ? updateMethod!
        : "render"

    if methodName != "render" {
        // upstream: (view[methodName] as any)(seriesModel, ecModel, api, payload);
        // Reduced: `methodName` can only be "incrementalPrepareRender" here (see note above).
        view.incrementalPrepareRender(seriesModel, ecModel!, api!, payload!)
    }

    return progressMethodMap(methodName)
}

// upstream: const progressMethodMap: {[method: string]: TaskResetCallbackReturn<SeriesTaskContext>} = { ... }
//   Modeled as a function (Swift can not build a generic-enum-valued dictionary at file scope as
//   ergonomically); returns the same two entries keyed by method name.
private func progressMethodMap(_ method: String) -> TaskResetCallbackReturn<SeriesTaskContext>? {
    switch method {
    case "incrementalPrepareRender":
        return .progress(.single({ _, params, context in
            context.view!.incrementalRender(
                params, context.model!, context.ecModel!, context.api!, context.payload!
            )
        }))
    case "render":
        // Put view.render in `progress` to support appendData. But in this case
        // view.render should not be called in reset, otherwise it will be called
        // twise. Use `forceFirstProgress` to make sure that view.render is called
        // in any cases.
        return .object(forceFirstProgress: true, progress: .single({ _, params, context in
            context.view!.render(
                context.model!, context.ecModel!, context.api!, context.payload!
            )
        }))
    default:
        return nil
    }
}

// export default ChartView;  -> `open class ChartView` above.
