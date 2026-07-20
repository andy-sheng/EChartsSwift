// Ported (GEO/MAP SUBSET) from echarts/src/component/helper/roamHelper.ts — keep in sync with upstream.
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

// This file ports the GEO/MAP slice of roamHelper (the graph slice lives in roamHelperGraph.swift):
//   - `updateRoamControllerSimply` → `updateGeoRoamControllerSimply` (controller.enable + the
//      pan/zoom → dispatchAction glue). Upstream's caller is `MapDraw._updateController`, which wires
//      the SAME `updateRoamControllerSimply` for both the `geo` component and `map` series (their shared
//      Geo coord sys). `isInSelf` is `coordinateSystem.containPoint([x, y])` (roamHelper's MapDraw call).
//   - `registerRoamActionSimply('series','map')` + the `geo` component's own registerAction (both resolve
//      to action type `geoRoam`, "Historical setting") → `registerGeoRoamAction` (the `geoRoam` action that
//      applies the pan/zoom payload to the host's Geo `View` coord sys via `viewCoordSysApplyRoamPayloadSyncBack`).
//
//   The `View` sync-back-TO-MODEL / roaming-animation machinery stays DEFERRED (see View.swift). The roam
//   state instead persists in a per-host-model inner store (below) that survives the full-`update()` rebuild
//   `geoRoam` triggers — same architecture as the graph slice. DEVIATION (same as graph): upstream registers
//   `update: 'updateTransform'` and re-transforms the region group via `MapDraw.__updateOnOwnRoam`; the
//   driver has no partial updateTransform, so this registers the DEFAULT `update: 'update'` — after the handler
//   writes the roam state, the full `update()` rebuilds the Geo coord sys (seeded from the stored roam state
//   via `geoRoamApplyStateToView` in geoCreator.resizeGeo) and re-renders the shifted/scaled regions.
//   PORT-NOTE (deferred): MAP_SERIES_GROUP sync-to-all (`otherModelsToSync`) — a single roam host is handled.

// ---------------------------------------------------------------------------------------------------
// Roam state — the single source of truth for a geo/map host's (center, zoom), carried across update()
//   rebuilds. Upstream stores center/zoom on the host model option; the port keeps it in a `makeInner`
//   store keyed on the host ComponentModel (GeoModel or MapSeriesModel), same lifetime.
// ---------------------------------------------------------------------------------------------------
final class GeoRoamState {
    var center: [Any]? = nil                          // View.centerOption (data-space numeric or percent)
    var zoom: Double = 1
    var zoomLimit: RoamOptionMixin.ScaleLimit? = nil
    // Whether a roam action has written this state yet. Before the first roam, the state is (re)seeded
    //   from the host `center`/`zoom`/`scaleLimit` option on each build; after, the roamed value wins.
    var roamed = false
    init() {}
}
let geoRoamState: (ComponentModel) -> GeoRoamState = model.makeInner { GeoRoamState() }

// Number coercion for a dynamic option/payload value (numbers box as Int OR Double).
private func geoRoamNum(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber, !(n === kCFBooleanTrue || n === kCFBooleanFalse) { return n.doubleValue }
    return nil
}

// Parse `scaleLimit` ({min?, max?}) to a `ScaleLimit`. Upstream `viewInner.zoomLimit`.
private func geoParseScaleLimit(_ v: Any?) -> RoamOptionMixin.ScaleLimit? {
    guard let d = v as? [String: Any] else { return nil }
    var lim = RoamOptionMixin.ScaleLimit()
    lim.min = geoRoamNum(d["min"])
    lim.max = geoRoamNum(d["max"])
    return lim
}

// The Geo coord sys a roam host (geo component | map series) is laid out on. Upstream reads
//   `componentOrSeries.coordinateSystem` (a Geo for both); the port re-fetches it live each call (it is
//   rebuilt on every `update()`), mirroring the graph slice's `seriesModel.coordinateSystem as?` re-fetch.
func geoRoamHostCoordSys(_ hostModel: ComponentModel) -> Geo? {
    if let geoModel = hostModel as? GeoModel {
        return geoModel.coordinateSystem as? Geo
    }
    if let mapSeries = hostModel as? MapSeriesModel {
        return mapSeries.coordinateSystem as? Geo
    }
    return nil
}

// Seed a freshly-built Geo's View with the current roam state (called from geoCreator.resizeGeo, replacing
//   the deferred `viewCoordSysSetRoamOptionFromModel(viewCoordSys, geoModel)`). On first build (before any
//   roam) the state is seeded from the host `center`/`zoom`/`scaleLimit` option.
func geoRoamApplyStateToView(_ hostModel: ComponentModel, _ view: View) {
    let state = geoRoamState(hostModel)
    if !state.roamed {
        state.center = hostModel.getShallow("center") as? [Any]
        state.zoom = geoRoamNum(hostModel.getShallow("zoom")) ?? 1
        state.zoomLimit = geoParseScaleLimit(hostModel.getShallow("scaleLimit"))
    }
    viewCoordSysSetRoamOption(view, state.center, state.zoom, state.zoomLimit)
}

// ---------------------------------------------------------------------------------------------------
// updateRoamControllerSimply (GEO/MAP) — controller.enable + the pan/zoom → dispatchAction glue.
// ---------------------------------------------------------------------------------------------------

// upstream MapDraw call: `updateRoamControllerSimply(mapOrGeoModel, api, controller,
//   (e, x, y) => mapOrGeoModel.coordinateSystem.containPoint([x, y]), clipRect, ..., false, true)`.
//   `onDispatched` is a port seam: after `api.dispatchAction` re-renders (full update() this phase), the
//   caller (EChartsView) flushes the live zr display list + repaints (same seam as the graph slice).
//   `clipRect` is upstream's roam limit (roamHelper.ts:85-87 `isInClip: (e, x, y) => !clipRect ||
//   clipRect.contain(x, y)`), passed by MapDraw when the geo `shouldClip()`. It is a LABELLED param placed
//   before the unlabelled `onDispatched` seam so existing 4-arg call sites keep binding the closure.
public func updateGeoRoamControllerSimply(
    _ hostModel: ComponentModel,
    _ api: ExtensionAPI,
    _ controller: RoamController,
    clipRect: BoundingRect? = nil,
    _ onDispatched: (() -> Void)? = nil
) {
    // upstream: `const coordSys = getOwnRoamViewCoordSys(componentOrSeries); if (!coordSys) { disable(); }`
    guard geoRoamHostCoordSys(hostModel) != nil else {
        controller.disable()
        return
    }

    // upstream: `controller.enable(retrieve2(componentOrSeries.get('roam'), roamTypeDefault), {...})`.
    let roam = hostModel.get("roam")
    let opt = RoamOption(
        component: hostModel,
        api: api,
        // upstream MapDraw isInSelf: `mapOrGeoModel.coordinateSystem.containPoint([x, y])`.
        isInSelf: { _, x, y in
            guard let geo = geoRoamHostCoordSys(hostModel) else { return false }
            return geo.containPoint([x, y])
        },
        // upstream roamHelper: `isInClip: (e, x, y) => !clipRect || clipRect.contain(x, y)`.
        isInClip: clipRect.map { rect in { (_: ElementEvent, x: Double, y: Double) in rect.contain(x, y) } },
        roamTrigger: hostModel.get("roamTrigger") as? String
    )
    controller.enable(roam, opt)

    // upstream `dispatchAction(extra)`: `{type: 'geoRoam', [`${mainType}Id`], ...extra}` (+ componentType
    //   when geoBackwardCompat). The port carries the host id + mainType so the action can target the exact
    //   host across a full-`update()` rebuild.
    let hostId = hostModel.id
    let hostMainType = hostModel.mainType
    func dispatch(_ extra: [String: Any]) {
        var payload = Payload(type: "geoRoam")
        payload.other["geoRoamHostId"] = hostId
        payload.other["geoRoamHostMainType"] = hostMainType
        for (k, v) in extra { payload.other[k] = v }
        // payloadDisableAnimation — the roam update should be immediate (no tween).
        payload.other["animation"] = ["duration": 0] as [String: Any]
        api.dispatchAction(payload)
        onDispatched?()
    }

    // upstream: `.off('pan').off('zoom').on('pan', ...).on('zoom', ...)`. The listeners do NOTHING except
    //   dispatchAction; the transform update lives in the action handler (see registerGeoRoamAction).
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
// registerRoamActionSimply (GEO/MAP) — the `geoRoam` action.
// ---------------------------------------------------------------------------------------------------

// upstream: the `geoRoam` action (geo/install.ts + registerRoamActionSimply(registers,'series','map')).
//   The handler applies the pan/zoom payload to the host's Geo `View` coord sys and stores the resulting
//   (center, zoom) roam state. See the DEVIATION (update:'update') note in the file header.
public func registerGeoRoamAction() {
    var info = ActionInfo(type: "geoRoam")
    info.event = "geoRoam"
    // update: default 'update' — see DEVIATION note in the file header.
    registerAction(info) { payload, ecModel, _ in
        let hostId = payload.other["geoRoamHostId"] as? String
        let dx = geoRoamNum(payload.other["dx"])
        let dy = geoRoamNum(payload.other["dy"])
        let zoom = geoRoamNum(payload.other["zoom"])
        let originX = geoRoamNum(payload.other["originX"]) ?? 0
        let originY = geoRoamNum(payload.other["originY"]) ?? 0

        func handle(_ hostModel: ComponentModel) {
            if let hid = hostId, !hid.isEmpty, hostModel.id != hid { return }
            guard let geo = geoRoamHostCoordSys(hostModel) else { return }

            // Apply the payload to the View's OVERALL trans, invert back to (center, zoom).
            let result = viewCoordSysApplyRoamPayloadSyncBack(geo.view, dx, dy, zoom, originX, originY)

            // Store the new roam state (the source of truth the next update() rebuild reads).
            let state = geoRoamState(hostModel)
            state.center = result.center.map { $0 as Any }
            state.zoom = result.zoom
            state.roamed = true
            // Also reflect immediately onto the CURRENT view (so any read before the rebuild is fresh).
            viewCoordSysSetRoamOption(geo.view, state.center, state.zoom, state.zoomLimit)
        }

        // upstream `makeQueryConditionKindA` resolves the host by mainType/subType + id. The port iterates
        //   the two roam-host kinds directly (geo components + map series), filtering by the host id.
        ecModel.eachComponent("geo") { comp, _ in
            if let geoModel = comp as? GeoModel { handle(geoModel) }
        }
        ecModel.eachSeriesByType("map") { s, _ in
            if let mapSeries = s as? MapSeriesModel { handle(mapSeries) }
        }
        return nil
    }
}
