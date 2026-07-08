// Ported (GRAPH SUBSET) from echarts/src/component/helper/roamHelper.ts — keep in sync with upstream.
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

// upstream `roamHelper.ts` maps a `View`-based coord sys. The port's graph carries a stand-in
//   `GraphViewCoordSys` (createView.swift). This file ports the GRAPH slice of roamHelper:
//     - `updateRoamControllerSimply` → `updateGraphRoamControllerSimply` (controller.enable + the
//        pan/zoom → dispatchAction glue).
//     - `registerRoamActionSimply('series','graph')` → `registerGraphRoamAction` (the `graphRoam` action
//        that applies the pan/zoom payload to the graph's view coord sys, via `applyRoamPayload`).
//     - `createIsInSelfByPointerCheckerEl` → `createIsInSelfByGraphRect` (the view-rect pointer checker).
//   The `View` sync-back-to-model / roaming-animation machinery stays DEFERRED (coord/View sync-back is a
//   PORT-TODO); the roam state instead persists in a per-series inner store (below) that survives the
//   full-`update()` rebuild `graphRoam` triggers.

// ---------------------------------------------------------------------------------------------------
// Roam state — the single source of truth for a graph's (center, zoom), carried across update() rebuilds.
//   Upstream stores center/zoom on the series option (`syncBackRoamOptionToRoamHostModel`) and re-reads
//   it via `viewCoordSysSetRoamOptionFromModel`. The port keeps it in a `makeInner` store keyed on the
//   series model (same lifetime: reset on `setOption`, persists across `update()`).
// ---------------------------------------------------------------------------------------------------
final class GraphRoamState {
    var center: [Double]? = nil
    var zoom: Double = 1
    // Whether a roam action has written this state yet. Before the first roam, the state is (re)seeded
    //   from the series `center`/`zoom` option on each build; after, the roamed value wins.
    var roamed = false
    init() {}
}
let graphRoamState: (GraphSeriesModel) -> GraphRoamState = model.makeInner { GraphRoamState() }

// Number coercion for a dynamic option/payload value (numbers box as Int OR Double).
private func graphRoamNum(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return nil
}

// Parse the `center` option ([number|percent, number|percent]) to a data-space `[x, y]`. Percentage
//   center is DEFERRED (graph center is normally absolute data coords or unset); only numeric is parsed.
private func graphParseCenterOption(_ v: Any?) -> [Double]? {
    guard let arr = v as? [Any], arr.count >= 2 else {
        if let d = v as? [Double], d.count >= 2 { return [d[0], d[1]] }
        return nil
    }
    guard let x = graphRoamNum(arr[0]), let y = graphRoamNum(arr[1]) else { return nil }
    return [x, y]
}

// Parse `scaleLimit` ({min?, max?}) to a `ScaleLimit`. Upstream `viewInner.zoomLimit`.
private func graphParseScaleLimit(_ v: Any?) -> RoamOptionMixin.ScaleLimit? {
    guard let d = v as? [String: Any] else { return nil }
    var lim = RoamOptionMixin.ScaleLimit()
    lim.min = graphRoamNum(d["min"])
    lim.max = graphRoamNum(d["max"])
    return lim
}

// Seed a freshly-built graph coord sys with the current roam state (called from createViewCoordSys).
//   On first build (before any roam) the state is seeded from the series `center`/`zoom` option.
func graphRoamApplyStateToCoordSys(_ seriesModel: GraphSeriesModel, _ coordSys: GraphViewCoordSys) {
    let state = graphRoamState(seriesModel)
    if !state.roamed {
        state.center = graphParseCenterOption(seriesModel.get("center"))
        state.zoom = graphRoamNum(seriesModel.get("zoom")) ?? 1
    }
    coordSys.roamCenter = state.center
    coordSys.roamZoom = state.zoom
}

// ---------------------------------------------------------------------------------------------------
// updateRoamControllerSimply (GRAPH) — controller.enable + the pan/zoom → dispatchAction glue.
// ---------------------------------------------------------------------------------------------------

// upstream: `createIsInSelfByPointerCheckerEl(pointerCheckerEl)` — here the pointer checker is the graph's
//   view rect (the box the graph is laid out within). A point inside the rect can start a roam.
public func createIsInSelfByGraphRect(
    _ seriesModel: GraphSeriesModel
) -> (ElementEvent, Double, Double) -> Bool {
    return { _, x, y in
        guard let vc = seriesModel.coordinateSystem as? GraphViewCoordSys,
              let rect = vc.getViewRect() else {
            return false
        }
        return rect.contain(x, y)
    }
}

// upstream: `updateRoamControllerSimply(componentOrSeries, api, controller, isInSelf, clipRect, ...)`.
//   The GRAPH form: enable the controller for the graph's roam option and wire pan/zoom → `graphRoam`.
//   `onDispatched` is a port seam: after `api.dispatchAction` re-renders (full update() this phase), the
//   caller (EChartsView) flushes the live zr display list + repaints. Upstream's view re-render is driven
//   by the action's own `updateTransform`/`__updateOnOwnRoam`; the slim driver has no live per-view zr, so
//   the host refreshes here (same seam as Phase 38/39 inside-dataZoom).
public func updateGraphRoamControllerSimply(
    _ seriesModel: GraphSeriesModel,
    _ api: ExtensionAPI,
    _ controller: RoamController,
    _ onDispatched: (() -> Void)? = nil
) {
    // upstream: `const coordSys = getOwnRoamViewCoordSys(componentOrSeries); if (!coordSys) { disable(); }`
    guard seriesModel.coordinateSystem is GraphViewCoordSys else {
        controller.disable()
        return
    }

    // upstream: `controller.enable(retrieve2(componentOrSeries.get('roam'), roamTypeDefault), {...})`.
    let roam = seriesModel.get("roam")
    let opt = RoamOption(
        component: seriesModel,
        api: api,
        isInSelf: createIsInSelfByGraphRect(seriesModel),
        isInClip: nil,
        roamTrigger: seriesModel.get("roamTrigger") as? String
    )
    controller.enable(roam, opt)

    // upstream `dispatchAction(extra)`: `{type: 'graphRoam', seriesId, ...extra}` with animation disabled.
    let seriesId = seriesModel.id
    func dispatch(_ extra: [String: Any]) {
        var payload = Payload(type: "graphRoam")
        payload.other["seriesId"] = seriesId
        for (k, v) in extra { payload.other[k] = v }
        // payloadDisableAnimation — the roam update should be immediate (no tween).
        payload.other["animation"] = ["duration": 0] as [String: Any]
        api.dispatchAction(payload)
        onDispatched?()
    }

    // upstream: `.off('pan').off('zoom').on('pan', ...).on('zoom', ...)`. The listeners do NOTHING except
    //   dispatchAction; the transform update lives in the action handler (see registerGraphRoamAction).
    controller
        .off("pan")
        .off("zoom")
        .on("pan", { event in
            dispatch([
                "dx": event.dx,
                "dy": event.dy
            ])
        })
        .on("zoom", { event in
            dispatch([
                "zoom": event.scale,
                "originX": event.originX,
                "originY": event.originY
            ])
        })
}

// ---------------------------------------------------------------------------------------------------
// registerRoamActionSimply (GRAPH) — the `graphRoam` action.
// ---------------------------------------------------------------------------------------------------

// upstream: `registerRoamActionSimply(registers, 'series', 'graph')` → action type `graphRoam`
//   (subType 'graph' + ROAM_ACTION_TYPE_SUFFIX). The handler applies the pan/zoom payload to the graph's
//   view coord sys and stores the resulting (center, zoom) roam state.
//
//   DEVIATION: upstream registers `update: 'none'` and re-renders via the view's `__updateOnOwnRoam`
//   (partial `updateTransform`). The slim driver has no partial updateTransform, so this registers the
//   DEFAULT `update: 'update'` — after the handler writes the roam state, `doDispatchAction` runs the full
//   `update()`, which rebuilds the graph coord sys (seeding it from the stored roam state via
//   `graphRoamApplyStateToCoordSys`) and re-renders the shifted/scaled nodes + edges. Over-render, but
//   faithful in result (same deviation documented for Phase 38/39 inside-dataZoom).
public func registerGraphRoamAction() {
    var info = ActionInfo(type: "graphRoam")
    info.event = "graphRoam"
    // update: default 'update' — see DEVIATION note above.
    registerAction(info) { payload, ecModel, _ in
        let targetSeriesId = payload.other["seriesId"] as? String
        let dx = graphRoamNum(payload.other["dx"])
        let dy = graphRoamNum(payload.other["dy"])
        let zoom = graphRoamNum(payload.other["zoom"])
        let originX = graphRoamNum(payload.other["originX"]) ?? 0
        let originY = graphRoamNum(payload.other["originY"]) ?? 0

        ecModel.eachSeriesByType("graph") { s, _ in
            guard let seriesModel = s as? GraphSeriesModel else { return }
            if let sid = targetSeriesId, !sid.isEmpty, seriesModel.id != sid { return }
            guard let coordSys = seriesModel.coordinateSystem as? GraphViewCoordSys else { return }

            let zoomLimit = graphParseScaleLimit(seriesModel.get("scaleLimit"))
            let result = coordSys.applyRoamPayload(dx, dy, zoom, originX, originY, zoomLimit)

            // Store the new roam state (the source of truth the next update() rebuild reads).
            let state = graphRoamState(seriesModel)
            state.center = result.center
            state.zoom = result.zoom
            state.roamed = true
            // Also reflect immediately onto the CURRENT coord sys (so any read before the rebuild is fresh).
            coordSys.roamCenter = result.center
            coordSys.roamZoom = result.zoom
        }
        return nil
    }
}
