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
//   The action follows component/geo/install.ts: it updates the owning MapDraw directly, then dispatches
//   `updateTransform` so dependent series re-layout without rebuilding the geo component or restarting
//   long-running effect animators. The per-host inner state below mirrors the model sync-back needed by this
//   port's rebuilt coordinate-system path and remains the source used by a later full update.
//   TODO: MAP_SERIES_GROUP sync-to-all (`otherModelsToSync`) — a single roam host is handled.

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
    //   for geo backward compatibility).
    let hostId = hostModel.id
    let hostMainType = hostModel.mainType
    func dispatch(_ extra: [String: Any]) {
        var payload = Payload(type: "geoRoam")
        payload.other["componentType"] = hostMainType
        payload.other[hostMainType + "Id"] = hostId
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

// component/geo/install.ts `makeAction` — selection model mutation followed by the targeted
// `geo:updateSelectStatus` view method. Kept beside geoRoam because both are installed together upstream.
private func registerGeoSelectAction(
    _ method: String, _ type: String, _ event: String
) {
    var info = ActionInfo(type: type)
    info.event = event
    info.update = "geo:updateSelectStatus"
    registerAction(info) { payload, ecModel, _ in
        var selected: [String: Bool] = [:]
        var allSelected: [[String: Any]] = []
        let condition = model.makeQueryConditionKindA(payload, "geo", nil)

        ecModel.eachComponent(condition) { component, _ in
            guard let geoModel = component as? GeoModel else { return }
            let name = payload.other["name"] as? String
            switch method {
            case "toggleSelected": geoModel.toggleSelected(name)
            case "select": geoModel.select(name)
            case "unSelect": geoModel.unSelect(name)
            default: return
            }

            if let geo = geoModel.coordinateSystem as? Geo {
                for region in geo.regions {
                    selected[region.name] = geoModel.isSelected(region.name)
                }
            }
            let names = selected.compactMap { $0.value ? $0.key : nil }
            allSelected.append(["geoIndex": geoModel.componentIndex, "name": names])
        }

        return [
            "selected": selected,
            "allSelected": allSelected,
            "name": payload.other["name"] ?? NSNull()
        ]
    }
}

// upstream: component/geo/install.ts install selection actions and the geoRoam action.
public func registerGeoRoamAction() {
    registerGeoSelectAction("toggleSelected", "geoToggleSelect", "geoselectchanged")
    registerGeoSelectAction("select", "geoSelect", "geoselected")
    registerGeoSelectAction("unSelect", "geoUnSelect", "geounselected")

    var info = ActionInfo(type: "geoRoam")
    info.event = "geoRoam"
    info.update = "updateTransform"
    registerAction(info) { payload, ecModel, api in
        let dx = geoRoamNum(payload.other["dx"])
        let dy = geoRoamNum(payload.other["dy"])
        let zoom = geoRoamNum(payload.other["zoom"])
        let originX = geoRoamNum(payload.other["originX"]) ?? 0
        let originY = geoRoamNum(payload.other["originY"]) ?? 0

        func handle(_ hostModel: ComponentModel) {
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

            // ownRoamViewUpdateDirectlyInAction(payload, componentOrSeries, ecModel, api)
            let roamPayload = RoamPayload(
                type: "geoRoam",
                dx: dx ?? 0, dy: dy ?? 0, zoom: zoom ?? 1,
                originX: originX, originY: originY,
                escapeConnect: payload.escapeConnect, batch: nil,
                excludeSeriesId: payload.excludeSeriesId,
                animation: payload.animation,
                other: payload.other
            )
            if let roamView = getViewOfComponentOrSeries(api, hostModel) as? RoamHostView {
                roamView.__updateOnOwnRoam(roamPayload, hostModel, api)
            }
        }

        // component/geo/install.ts mainType selection: componentType is backward-compatible; a geo
        // finder implies geo, otherwise the historical default is series.map.
        let explicitMainType = payload.other["componentType"] as? String
        let mainType = explicitMainType
            ?? ((payload.other["geoId"] != nil
                || payload.other["geoName"] != nil
                || payload.other["geoIndex"] != nil) ? "geo" : COMPONENT_MAIN_TYPE_SERIES)
        if mainType == "geo" {
            let condition = model.makeQueryConditionKindA(payload, "geo", nil)
            ecModel.eachComponent(condition) { component, _ in
                if let geoModel = component as? GeoModel { handle(geoModel) }
            }
        }
        else if mainType == COMPONENT_MAIN_TYPE_SERIES {
            let condition = model.makeQueryConditionKindA(payload, COMPONENT_MAIN_TYPE_SERIES, "map")
            ecModel.eachComponent(condition) { component, _ in
                guard let mapSeries = component as? MapSeriesModel,
                      mapSeriesNeedsDrawMap(mapSeries) else { return }
                handle(mapSeries)
            }
        }
        return nil
    }
}
