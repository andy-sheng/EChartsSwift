// Ported from echarts/src/component/axisPointer/globalListener.ts — keep in sync with upstream.
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
//
// ============================================================================
// WHAT THIS FILE IS  (Phase 35, TASK 2)
// ============================================================================
// The zr-level mouse binding that drives the axisPointer/tooltip `trigger:"axis"` path. Upstream
// `register(key, api, handler)` binds ONE set of zr listeners (`click`/`mousemove`/`mousewheel`/
// `globalout`) that fan every registered `handler(currTrigger, event, dispatchAction)` out, then merges
// their `showTip`/`hideTip` intents so only the LAST one is actually dispatched (a tooltip and an
// axisPointer both want to show/hide — the "final stage" resolves the conflict).
//
// ADAPTATION vs upstream: upstream reaches the live zr via `api.getZr()`. In this port the live zr lives
// in `EChartsView` (ECharts is zr-less), and ExtensionAPI has no `getZr()` yet, so `register` takes
// the `ZRender` directly plus a `realDispatch` closure (the "actually dispatch" seam — upstream
// `api.dispatchAction`). `EChartsView` owns the zr and wires `realDispatch` to
// `ec.dispatchAction` + its tooltip view, and registers the axisTrigger as the `mousemove` handler:
//
//   globalListener.register("axisPointer", view.zr, realDispatch: { payload in
//       view.ec.dispatchAction(payload)            // showTip/hideTip → tooltip trigger:"axis"
//   }, handler: { currTrigger, event, dispatchAction in
//       var payload = Payload(type: "axisTrigger")
//       payload.other["currTrigger"] = currTrigger
//       if let e = event { payload.other["x"] = e.offsetX; payload.other["y"] = e.offsetY }
//       payload.other["dispatchAction"] = dispatchAction   // route showTip THROUGH the merge stage
//       axisTrigger(payload, ecModel, api)
//   })
//
// The `handler` MUST forward the passed `dispatchAction` into `axisTrigger` (as `payload.dispatchAction`)
// so `showTip`/`hideTip` flow through the pend/merge below rather than dispatching directly.
//
// `util/throttle.throttle` / `throttleUtil` is VERIFIED NOT APPLICABLE here.
//   THROTTLE: none in this file. Verified against upstream 6.1.0 (pinned 20ecdf4) —
//   `globalListener.ts` imports no `util/throttle` and calls every `record.handler(...)` SYNCHRONOUSLY
//   inside `useHandler`'s zr listener; the handler fan-out is NOT throttled upstream, so this port
//   matches it by calling immediately. An earlier note incorrectly claimed this fan-out was
//   throttled upstream.
//
//   The axisPointer/tooltip throttling upstream lives in the CONSUMERS of this listener, not here:
//     - `BaseAxisPointer._updateHandle` (BaseAxisPointer.ts:391) throttles `_doDispatchAxisPointer` at
//       `handleModel.get('throttle') || 0` with `'fixRate'` (AxisPointerModel.ts:139 defaults
//       `handle.throttle: 40`) — the HANDLE path ONLY; with no `axisPointer.handle` the dispatch is
//       unthrottled. WIRED in this port: BaseAxisPointer.swift:568 (`throttleUtil.createOrUpdate`),
//       :637 (call), :713 (`throttleUtil.clear`).
//     - `TooltipView._updatePosition` at 50ms `'fixRate'` (upstream TooltipView.ts:59 imports
//       `{clear, createOrUpdate}`; :212 `createOrUpdate(this, '_updatePosition', 50, 'fixRate')`, cleared
//       at :215/:1052). STILL DEFERRED in this port — see TooltipView.swift:42; TooltipView.swift:390
//       calls `_updatePosition(...)` directly with no throttle wrapper.
//   The throttle utility itself IS fully ported (`util/throttle.swift`, enum `throttleUtil`).
//
// DEFERRED:
//   - `env.node` guard (SSR) — native client is browser-like, so it is skipped.
//
// import * as zrUtil from 'zrender/src/core/util';   -> Swift stdlib / ZRenderKit
// import env from 'zrender/src/core/env';            -> (skipped; native)
// import {makeInner} from '../../util/model';        -> `model.makeInner` (util/modelUtil.swift)
// import ExtensionAPI from '../../core/ExtensionAPI';-> replaced by (ZRender + realDispatch) — see above

import Foundation
import ZRenderKit

// upstream: type Handler = (currTrigger, event: ZRElementEvent, dispatchAction) => void
public typealias AxisPointerGlobalHandler = (
    _ currTrigger: String,
    _ event: ElementEvent?,
    _ dispatchAction: @escaping (Payload) -> Void
) -> Void

// upstream: interface Record { handler }
final class GlobalListenerRecord {
    var handler: AxisPointerGlobalHandler
    init(_ handler: @escaping AxisPointerGlobalHandler) { self.handler = handler }
}

// upstream: interface InnerStore { initialized; records } (+ the realDispatch seam — see adaptation note)
final class GlobalListenerInnerStore {
    var initialized: Bool = false
    var records: [String: GlobalListenerRecord] = [:]
    var realDispatch: ((Payload) -> Void)?
    init() {}
}

// upstream: interface Pendings { showTip: ShowTipPayload[]; hideTip: HideTipPayload[] }
final class GlobalListenerPendings {
    var showTip: [Payload] = []
    var hideTip: [Payload] = []
    init() {}
}

// upstream: const inner = makeInner<InnerStore, ZRenderType>();  (keyed on the live zr)
private let globalListenerInner: (ZRender) -> GlobalListenerInnerStore =
    model.makeInner { GlobalListenerInnerStore() }

// upstream `import * as globalListener` namespace → caseless enum (avoids polluting the global scope
//   with `register`/`unregister`, mirroring the `modelHelper` / `model` enum convention).
public enum globalListener {

    // upstream: export function register(key, api, handler)
    public static func register(
        _ key: String,
        _ zr: ZRender,
        realDispatch: @escaping (Payload) -> Void,
        handler: @escaping AxisPointerGlobalHandler
    ) {
        // upstream: if (env.node) return;  — native (browser-like), skip.
        let inner = globalListenerInner(zr)
        inner.realDispatch = realDispatch

        initGlobalListeners(zr)

        // upstream: const record = inner(zr).records[key] || (inner(zr).records[key] = {}); record.handler = handler;
        if let record = inner.records[key] {
            record.handler = handler
        }
        else {
            inner.records[key] = GlobalListenerRecord(handler)
        }
    }

    // upstream: export function unregister(key, api)
    public static func unregister(_ key: String, _ zr: ZRender) {
        // upstream: if (env.node) return;
        let inner = globalListenerInner(zr)
        // upstream sets records[key] = null (kept in the map). Here we remove it (the fan-out skips missing).
        inner.records[key] = nil
    }

    // upstream: function initGlobalListeners(zr, api)
    private static func initGlobalListeners(_ zr: ZRender) {
        let inner = globalListenerInner(zr)
        if inner.initialized {
            return
        }
        inner.initialized = true

        // upstream: useHandler('click',      curry(doEnter, 'click'));
        useHandler(zr, "click", currTrigger: "click", isLeave: false)
        // upstream: useHandler('mousemove',  curry(doEnter, 'mousemove'));
        useHandler(zr, "mousemove", currTrigger: "mousemove", isLeave: false)
        // For example, dataZoom may update series layout while mousewheel; axisPointer and tooltip need to
        // follow that update, otherwise highlighted items (by axisPointer) may have no chance to downplay.
        useHandler(zr, "mousewheel", currTrigger: "mousewheel", isLeave: false)
        // useHandler('mouseout', onLeave);
        // upstream: useHandler('globalout', onLeave);
        useHandler(zr, "globalout", currTrigger: nil, isLeave: true)
    }

    // upstream: function useHandler(eventType, cb) { zr.on(eventType, e => { ... }); }
    //   `cb` is `doEnter(currTrigger)` (isLeave=false) or `onLeave` (isLeave=true).
    private static func useHandler(
        _ zr: ZRender,
        _ eventType: String,
        currTrigger: String?,
        isLeave: Bool
    ) {
        zr.on(eventType, { _, args in
            // upstream: const dis = makeDispatchAction(api);
            let dis = makeDispatchAction(zr)
            let e = args.first as? ElementEvent

            // upstream: each(inner(zr).records, record => record && cb(record, e, dis.dispatchAction));
            for (_, record) in globalListenerInner(zr).records {
                if isLeave {
                    // upstream onLeave: record.handler('leave', null, dispatchAction)
                    record.handler("leave", nil, dis.dispatchAction)
                }
                else {
                    // upstream doEnter(currTrigger): record.handler(currTrigger, e, dispatchAction)
                    record.handler(currTrigger!, e, dis.dispatchAction)
                }
            }

            // upstream: dispatchTooltipFinally(dis.pendings, api);
            dispatchTooltipFinally(dis.pendings, zr)
            return nil
        }, nil)   // ctx nil — no retain cycle (the inner stores are keyed on zr, not captured strongly).
    }

    // upstream: function makeDispatchAction(api) — the pend/merge wrapper.
    private static func makeDispatchAction(
        _ zr: ZRender
    ) -> (dispatchAction: (Payload) -> Void, pendings: GlobalListenerPendings) {
        let pendings = GlobalListenerPendings()
        // FIXME (upstream): 'showTip'/'hideTip' can be triggered by BOTH axisPointer and tooltip and may
        //   conflict; the "final stage" (dispatchTooltipFinally) merges those dispatched actions.
        let dispatchAction: (Payload) -> Void = { payload in
            if payload.type == "showTip" {
                pendings.showTip.append(payload)
            }
            else if payload.type == "hideTip" {
                pendings.hideTip.append(payload)
            }
            else {
                // upstream: payload.dispatchAction = dispatchAction; api.dispatchAction(payload);
                globalListenerInner(zr).realDispatch?(payload)
            }
        }
        return (dispatchAction, pendings)
    }

    // upstream: function dispatchTooltipFinally(pendings, api)
    private static func dispatchTooltipFinally(_ pendings: GlobalListenerPendings, _ zr: ZRender) {
        let showLen = pendings.showTip.count
        let hideLen = pendings.hideTip.count

        var actuallyPayload: Payload?
        if showLen > 0 {
            actuallyPayload = pendings.showTip[showLen - 1]
        }
        else if hideLen > 0 {
            actuallyPayload = pendings.hideTip[hideLen - 1]
        }
        if var p = actuallyPayload {
            // upstream: actuallyPayload.dispatchAction = null; api.dispatchAction(actuallyPayload);
            //   Removing the key is equivalent to upstream's `= null` (every read is a truthiness/`if let`
            //   test). No producer copies `other["dispatchAction"]` into the showTip/hideTip payload today
            //   (axisTrigger.swift:527-539 builds them fresh), so this is a no-op guard — but it keeps the
            //   final-stage dispatch from re-entering the pend/merge if a future handler ever forwards the
            //   incoming payload (which DOES carry it — set at EChartsView.swift:639, read at
            //   axisTrigger.swift:191).
            p.other["dispatchAction"] = nil
            globalListenerInner(zr).realDispatch?(p)
        }
    }
}
