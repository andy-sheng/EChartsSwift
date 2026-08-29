// Ported (VIEW-GROUP SUBSET) from echarts/src/component/helper/roamHelper.ts — keep in sync with upstream.
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

// This file ports the VIEW-GROUP slice of roamHelper — the shared roam machinery for the tree and
//   sankey series (the graph slice lives in roamHelperGraph.swift, the geo/map slice in roamHelperGeo).
//
//   Upstream lays tree/sankey out on a `View` coordinate system and applies roam through
//   `updateRoamControllerSimply` + `registerRoamActionSimply`. These two views are not wired onto that
//   coordinate system in the port, so this helper applies the equivalent accumulated transform to their
//   rendered group. Treemap is deliberately excluded: its upstream view dispatches `treemapMove` and
//   `treemapRender` rootRect actions and re-lays out tiles instead of transforming the group.
//     - `updateRoamControllerSimply` → `updateViewGroupRoamControllerSimply` (controller.enable + the
//        pan/zoom → dispatchAction glue), with thin per-chart wrappers below.
//     - `registerRoamActionSimply('series',<sub>)` → `registerViewGroupRoamAction(actionType, seriesType)`
//        (the `treeRoam` / `sankeyRoam` action that accumulates the pan/zoom payload into
//        the per-series roam state).
//     - `createIsInSelfByPointerCheckerEl(this.group)` → `viewGroupRoamPointerRect` (the view-group's
//        transformed bounding-rect pointer checker).
//   The roam state persists in a per-series inner store (below) that survives the full-`update()` rebuild
//   the roam action triggers, and the view re-applies it to the group each render (same architecture as the
//   graph/geo slices).

// ---------------------------------------------------------------------------------------------------
// Roam state — the single source of truth for a view-group host's (pan, zoom), carried across update()
//   rebuilds. Keyed on the series model (same lifetime as the graph/geo slices: reset on `setOption`,
//   persists across `update()`). Identity (pan 0, zoom 1) → the view group renders UNCHANGED, so a chart
//   with roam off (or roam on but never dragged) is pixel-identical to the pre-roam static render.
// ---------------------------------------------------------------------------------------------------
final class ViewGroupRoamState {
    // The roam transform T applied on top of the base placement, in the group's PARENT space:
    //   T(v) = zoom * v + (panX, panY).  Combined with a base placement (baseX, baseY, scale 1), the
    //   view group's effective transform is scaleX = scaleY = zoom, x = zoom*baseX + panX (see
    //   viewGroupRoamApplyStateToGroup).
    var panX: Double = 0
    var panY: Double = 0
    var zoom: Double = 1
    // Whether a roam action has written this state yet (parity with the graph/geo slices' `roamed`).
    var roamed = false
    init() {}
}
let viewGroupRoamState: (ComponentModel) -> ViewGroupRoamState = model.makeInner { ViewGroupRoamState() }

// Number coercion for a dynamic option/payload value (numbers box as Int OR Double).
func viewGroupRoamNum(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber, !(n === kCFBooleanTrue || n === kCFBooleanFalse) { return n.doubleValue }
    return nil
}

// Parse `scaleLimit` ({min?, max?}) to a `ScaleLimit` — upstream `viewInner.zoomLimit`.
//   (Same shape as geoParseScaleLimit / graphParseScaleLimit, which are private to their own slices; this
//   one is the slice-level copy the view-group hosts share.)
func viewGroupParseScaleLimit(_ v: Any?) -> RoamOptionMixin.ScaleLimit? {
    guard let d = v as? [String: Any] else { return nil }
    var lim = RoamOptionMixin.ScaleLimit()
    lim.min = viewGroupRoamNum(d["min"])
    lim.max = viewGroupRoamNum(d["max"])
    return lim
}

// ---------------------------------------------------------------------------------------------------
// upstream: export function createViewCoordSysSimply(
//         componentOrSeries: RoamHostComponentOrSeries, api: ExtensionAPI,
//         x: number, y: number, width: number, height: number,   // VIEW_COORD_SYS DataRect init
//         viewRect?: RectLike | NullUndefined                    // VIEW_COORD_SYS ViewRect init
//     ): View {
//         const viewCoordSys = new View(null, useLegacyViewCoordSysCenterBase(componentOrSeries.ecModel, api));
//         viewCoordSysSetBoundingRect(viewCoordSys, x, y, width, height);
//         viewRect
//             ? viewCoordSysSetViewRect(viewCoordSys, viewRect.x, viewRect.y, viewRect.width, viewRect.height)
//             : viewCoordSysSetViewRect(viewCoordSys, x, y, width, height);
//         viewCoordSysSetRoamOptionFromModel(viewCoordSys, componentOrSeries);
//         return viewCoordSys;
//     }
//   (component/helper/roamHelper.ts:186-212)
//   PORT-NOTE: `RoamHostComponentOrSeries` (component OR series) → `ComponentModel` (SeriesModel's base).
//   `viewCoordSysSetRoamOptionFromModel` is realized as the port's value-taking `viewCoordSysSetRoamOption`
//   fed from the host model's `center` / `zoom` / `scaleLimit` shallow options — exactly what upstream's
//   *FromModel reads.
// ---------------------------------------------------------------------------------------------------
public func createViewCoordSysSimply(
    _ componentOrSeries: ComponentModel,
    _ api: ExtensionAPI,
    // VIEW_COORD_SYS DataRect init:
    _ x: Double,
    _ y: Double,
    _ width: Double,
    _ height: Double,
    // VIEW_COORD_SYS ViewRect init:
    // Use DataRect by default, which means DataRect is in pixel space.
    _ viewRect: RectLike? = nil
) -> View {
    let viewCoordSys = View(
        nil,
        useLegacyViewCoordSysCenterBase(componentOrSeries.ecModel, api)
    )

    viewCoordSysSetBoundingRect(viewCoordSys, x, y, width, height)

    if let viewRect = viewRect {
        viewCoordSysSetViewRect(viewCoordSys, viewRect.x, viewRect.y, viewRect.width, viewRect.height)
    }
    else {
        viewCoordSysSetViewRect(viewCoordSys, x, y, width, height)
    }

    // viewCoordSysSetRoamOptionFromModel(viewCoordSys, componentOrSeries);
    viewCoordSysSetRoamOption(
        viewCoordSys,
        componentOrSeries.getShallow("center") as? [Any],
        viewGroupRoamNum(componentOrSeries.getShallow("zoom")),
        viewGroupParseScaleLimit(componentOrSeries.getShallow("scaleLimit"))
    )

    return viewCoordSys
}

// Apply the current roam state to a view group given its base (roam-free) placement. Called at the END of
//   the view's render(), replacing the deferred `applyViewCoordSysTransToElement`. Composing the roam
//   transform T (in parent space) with the base placement (baseX, baseY, scale 1):
//     a local point p → base-place → (baseX + p) → T → zoom*(baseX + p) + pan
//   so the group's effective transform is scale = zoom, x = zoom*baseX + panX (idem for y).
//   Identity state (zoom 1, pan 0) → group.x = baseX, scale = 1 → the placement is left exactly as-is.
func viewGroupRoamApplyStateToGroup(
    _ hostModel: ComponentModel, _ group: Group, _ baseX: Double, _ baseY: Double
) {
    let state = viewGroupRoamState(hostModel)
    group.scaleX = state.zoom
    group.scaleY = state.zoom
    group.x = state.zoom * baseX + state.panX
    group.y = state.zoom * baseY + state.panY
    group.markRedraw()
}

// ---------------------------------------------------------------------------------------------------
// createIsInSelfByPointerCheckerEl(pointerCheckerEl) — the view group's transformed bounding-rect checker.
//   Upstream tree/treemap pass `this.group` (tree) / the container group (treemap) as the pointer checker;
//   a pointer inside the rendered area starts a roam. (With the default `roamTrigger: 'global'` for all
//   three, `_checkPointer` short-circuits to true and never consults this — but it is wired faithfully.)
// ---------------------------------------------------------------------------------------------------
public func viewGroupRoamPointerRect(_ el: Group?) -> ((ElementEvent, Double, Double) -> Bool) {
    return { _, x, y in
        guard let el = el, let rect = el.getBoundingRect() else { return false }
        // tmpRect.copy(el.getBoundingRect()); tmpRect.applyTransform(el.getComputedTransform());
        let tmp = rect.clone()
        tmp.applyTransform(el.getComputedTransform())
        return tmp.contain(x, y)
    }
}

// ---------------------------------------------------------------------------------------------------
// updateRoamControllerSimply (VIEW-GROUP) — controller.enable + the pan/zoom → dispatchAction glue.
//   `onDispatched` is a port seam: after `api.dispatchAction` re-renders (full update() this phase), the
//   caller (EChartsView) flushes the live zr display list + repaints (same seam as the graph/geo slices).
// ---------------------------------------------------------------------------------------------------
public func updateViewGroupRoamControllerSimply(
    _ hostModel: ComponentModel,
    _ actionType: String,
    _ isInSelf: @escaping (ElementEvent, Double, Double) -> Bool,
    _ api: ExtensionAPI,
    _ controller: RoamController,
    _ onDispatched: (() -> Void)? = nil
) {
    // upstream: `controller.enable(retrieve2(componentOrSeries.get('roam'), roamTypeDefault), {...})`.
    let roam = hostModel.get("roam")
    let opt = RoamOption(
        component: hostModel,
        api: api,
        isInSelf: isInSelf,
        isInClip: nil,
        roamTrigger: hostModel.get("roamTrigger") as? String
    )
    controller.enable(roam, opt)

    // upstream `dispatchAction(extra)`: `{type:'<sub>Roam', seriesId, ...extra}` with animation disabled.
    let seriesId = hostModel.id
    func dispatch(_ extra: [String: Any]) {
        var payload = Payload(type: actionType)
        payload.other["seriesId"] = seriesId
        for (k, v) in extra { payload.other[k] = v }
        // payloadDisableAnimation — the roam update should be immediate (no tween).
        payload.other["animation"] = ["duration": 0] as [String: Any]
        api.dispatchAction(payload)
        onDispatched?()
    }

    // upstream: `.off('pan').off('zoom').on('pan', ...).on('zoom', ...)`. The listeners do NOTHING except
    //   dispatchAction; the transform update lives in the action handler (see registerViewGroupRoamAction).
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
// registerRoamActionSimply (VIEW-GROUP) — the `<sub>Roam` action.
//   The handler accumulates the pan/zoom payload into the per-series roam state. See the DEVIATION note in
//   the graph/geo slices: upstream registers `update: 'none'`/`'updateTransform'` and re-transforms the
//   view via `__updateOnOwnRoam`; the driver has no partial updateTransform, so this registers the
//   DEFAULT `update: 'update'` — after the handler writes the state, `doDispatchAction` runs the full
//   `update()`, which re-renders the view and re-applies the roam state to the group (via
//   viewGroupRoamApplyStateToGroup). Over-render, but faithful in result.
// ---------------------------------------------------------------------------------------------------
public func registerViewGroupRoamAction(_ actionType: String, _ seriesType: String) {
    var info = ActionInfo(type: actionType)
    info.event = actionType
    // update: default 'update' — see the DEVIATION note above.
    registerAction(info) { payload, ecModel, _ in
        let targetSeriesId = payload.other["seriesId"] as? String
        let dx = viewGroupRoamNum(payload.other["dx"]) ?? 0
        let dy = viewGroupRoamNum(payload.other["dy"]) ?? 0
        let zoom = viewGroupRoamNum(payload.other["zoom"])
        let originX = viewGroupRoamNum(payload.other["originX"]) ?? 0
        let originY = viewGroupRoamNum(payload.other["originY"]) ?? 0

        ecModel.eachSeriesByType(seriesType) { s, _ in
            let seriesModel = s
            if let sid = targetSeriesId, !sid.isEmpty, seriesModel.id != sid { return }

            let state = viewGroupRoamState(seriesModel)
            if let f = zoom {
                // Zoom by factor f around the global (parent-space) origin (originX, originY):
                //   compose Z ∘ T where Z(w) = f*w + origin*(1 - f), giving
                //     zoom  *= f
                //     pan   = f*pan + origin*(1 - f)
                //   which keeps the point (originX, originY) fixed while scaling the group by f (the
                //   standard zrender roam-around-origin accumulation).
                state.zoom *= f
                state.panX = f * state.panX + originX * (1 - f)
                state.panY = f * state.panY + originY * (1 - f)
            }
            else {
                // Pan: T'(v) = T(v) + (dx, dy) → the group shifts by exactly (dx, dy) in parent space.
                state.panX += dx
                state.panY += dy
            }
            state.roamed = true
        }
        return nil
    }
}

// ---------------------------------------------------------------------------------------------------
// Per-chart thin wrappers (upstream: each view's own `updateRoamControllerSimply(...)` call + install's
//   `registerRoamActionSimply(registers,'series',<sub>)`).
// ---------------------------------------------------------------------------------------------------

// TREE — upstream TreeView.render: `updateRoamControllerSimply(seriesModel, api, this._controller,
//   createIsInSelfByPointerCheckerEl(this.group), null)`.
public func updateTreeRoamControllerSimply(
    _ seriesModel: TreeSeriesModel,
    _ api: ExtensionAPI,
    _ controller: RoamController,
    _ onDispatched: (() -> Void)? = nil
) {
    let isInSelf = viewGroupRoamPointerRect((api.getViewOfSeriesModel(seriesModel) as? TreeView)?.roamPointerCheckerGroup())
    updateViewGroupRoamControllerSimply(seriesModel, "treeRoam", isInSelf, api, controller, onDispatched)
}
public func registerTreeRoamAction() { registerViewGroupRoamAction("treeRoam", "tree") }

// SANKEY — upstream SankeyView.render: `updateRoamControllerSimply(seriesModel, api, this._controller, ...)`.
public func updateSankeyRoamControllerSimply(
    _ seriesModel: SankeySeriesModel,
    _ api: ExtensionAPI,
    _ controller: RoamController,
    _ onDispatched: (() -> Void)? = nil
) {
    let isInSelf = viewGroupRoamPointerRect((api.getViewOfSeriesModel(seriesModel) as? SankeyView)?.roamPointerCheckerGroup())
    updateViewGroupRoamControllerSimply(seriesModel, "sankeyRoam", isInSelf, api, controller, onDispatched)
}
public func registerSankeyRoamAction() { registerViewGroupRoamAction("sankeyRoam", "sankey") }
