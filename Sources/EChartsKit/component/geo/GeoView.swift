// Ported from echarts/src/component/geo/GeoView.ts — keep in sync with upstream
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

// upstream imports (mapped to this port; `→` marks the Swift symbol used):
//   import MapDraw from '../helper/MapDraw';
//     → `MapDraw` (component/helper/MapDraw.swift) — roam controller (incl. the `clipRect` roam limit) +
//       the persistent `_transformGroup`, GeoJSON + geoSVG builds, series-map data/visualMap encoding,
//       emphasis/select/blur states, and the event/tooltip/state triggers (`setTooltipConfig` wired) —
//       with TWO documented gaps: the `GeoProjection.stream` clip/resample path (`projectionStream` is
//       nil, `projectPolys` dormant) and the name-keyed geo `labelFetcher` (replaced by an eager
//       `getFormattedLabel`); see its PORT-TODOs.
//     → SWITCHOVER DONE: this view now owns a persistent `_mapDraw` and delegates the WHOLE region
//       backdrop to `MapDraw.draw` (upstream lifecycle: create-on-demand, `remove()` when `show` is
//       false / on dispose, `__updateOnOwnRoam`, `findHighDownDispatchers`). The previously inlined
//       STATIC subset of MapDraw (`_buildGeoJSON` / `_buildSVG` / `_applyOptionStyleForRegionSVG` /
//       `_resetEventTriggerForRegion` / `_resetStateTriggerForRegion` / `_resetLabelForRegion(SVG)` /
//       `_enableBlurEntireSVG` and their file-tail helpers) is DELETED — it was a duplicate of MapDraw
//       (PORTING §2), and MapDraw's persistent `_transformGroup` + `applyViewCoordSysTransToElement`
//       architecture (roam pan/zoom, geo clip rect, tooltip/label states) replaces it wholesale.
//   import ComponentView from '../../view/Component';             → `ComponentView` (view/ComponentView.swift).
//   import GlobalModel from '../../model/Global';                 → `GlobalModel`.
//   import ExtensionAPI from '../../core/ExtensionAPI';           → `ExtensionAPI`.
//   import GeoModel from '../../coord/geo/GeoModel';              → `GeoModel` (coord/geo/GeoModel.swift).
//   import { Payload, ZRElementEvent, ECEventData, RoamPayload } from '../../util/types';
//     → `Payload` / `ECEventData` / `RoamPayload` (util/types.swift); `ZRElementEvent` → `ElementEvent`.
//   import { getECData } from '../../util/innerStore';            → `innerStore.getECData` (util/innerStore.swift).
//   import { findEventDispatcher } from '../../util/event';       → `findEventDispatcher` (util/event.swift).
//   import Element from 'zrender/src/Element';                    → ZRenderKit `Element`.

// upstream: class GeoView extends ComponentView
// CONVENTIONS §2/§4: reference type extending the reference `ComponentView` → `final class`.
public final class GeoView: ComponentView {

    // upstream: static type = 'geo' as const;
    public static let type = "geo"
    // upstream: readonly type = GeoView.type;
    public let type = "geo"

    // upstream: private _mapDraw: MapDraw;
    private var _mapDraw: MapDraw?

    // upstream: private _api: ExtensionAPI;
    private var _api: ExtensionAPI?

    // upstream: private _model: GeoModel;
    private var _model: GeoModel?

    // upstream: focusBlurEnabled = true;
    // Consulted by the emphasis/blur system (states.ts:536). PORT-NOTE: the base `ComponentView` does not
    //   declare the seam yet (its deferred PORT-NOTE @ComponentView.swift:177), so this stays a LOCAL var;
    //   it becomes `override` in the same change that adds `open var focusBlurEnabled` to the base and
    //   restores the `blurComponent` guard (SYMBOLS.tsv row `view/ComponentView.baseSeams`).
    public var focusBlurEnabled = true

    // upstream: init(ecModel: GlobalModel, api: ExtensionAPI) { this._api = api; }
    public override func `init`(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        self._api = api
    }

    // upstream: render(geoModel: GeoModel, ecModel: GlobalModel, api: ExtensionAPI, payload: Payload)
    //   The base override is typed `(ComponentModel, ...)`; narrow `model` to `GeoModel` (cf. MapView).
    public override func render(
        _ geoModelBase: ComponentModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {
        let geoModel = geoModelBase as! GeoModel
        self._model = geoModel

        // upstream: if (!geoModel.get('show')) { this._mapDraw && this._mapDraw.remove(); this._mapDraw = null; return; }
        if !jsTruthy(geoModel.get("show")) {
            self._mapDraw?.remove()
            self._mapDraw = nil
            return
        }

        // upstream: if (!this._mapDraw) { this._mapDraw = new MapDraw(api); }
        //           const mapDraw = this._mapDraw;
        let mapDraw: MapDraw
        if let existing = self._mapDraw {
            mapDraw = existing
        }
        else {
            mapDraw = MapDraw(api)
            self._mapDraw = mapDraw

            // upstream: mapDraw.group.on('click', this._handleRegionClick, this);  — bound in `render`.
            //   PORT-NOTE (deviation, deliberate): `mapDraw.group` PERSISTS across renders, so re-binding
            //   every render would accumulate one handler per render (upstream's `on` appends too). Bind
            //   exactly ONCE per MapDraw instance instead: the group's lifetime is the MapDraw's, and
            //   `_mapDraw` is nil'd on `show: false` / `dispose`, so a fresh instance always gets a fresh
            //   binding. (An unscoped `off("click")` would instead drop EVERY click listener on a group
            //   GeoView does not exclusively own.) Captured weakly (§12) — the group is owned by self.
            _ = mapDraw.group.on("click", { [weak self] _, args in
                self?._handleRegionClick(args.first as? ElementEvent)
                return nil
            })
        }

        // upstream: mapDraw.draw(geoModel, ecModel, api, this, payload);
        //   PORT-NOTE: upstream `payload` is nullable and `MapDraw.draw` keys its "no animation" flag off
        //   it; the driver passes `Payload(type: "")` as the "no payload" sentinel, so map it back to
        //   `nil` (same bridging as MapView.render).
        mapDraw.draw(geoModel, ecModel, api, self, payload.type.isEmpty ? nil : payload)

        // upstream: mapDraw.group.silent = geoModel.get('silent');
        if let silent = geoModel.get("silent"), !(silent is NSNull) {
            mapDraw.group.silent = jsTruthy(silent)
        }

        // upstream: this.group.add(mapDraw.group);
        //   (`Group.add` is a no-op when the child is already parented here, so re-adding each render is
        //   harmless — as upstream.)
        _ = self.group.add(mapDraw.group)

        // upstream: this.updateSelectStatus(geoModel, ecModel, api);
        self.updateSelectStatus(geoModel, ecModel, api)
    }

    /**
     * @implements RoamHostView['__updateOnOwnRoam']
     */
    // upstream: __updateOnOwnRoam(payload: RoamPayload, model: GeoModel, api: ExtensionAPI): void
    //   The performance shortcut the `geoRoam` action calls to re-transform MapDraw's `_transformGroup`
    //   directly, with no data / visual processing. (roamHelperGeo currently registers the full-`update`
    //   deviation, so this is reachable only once `update: 'updateTransform'` routing lands — see the
    //   note there and in MapView.)
    public func __updateOnOwnRoam(
        _ payload: RoamPayload, _ componentOrSeries: ComponentModel, _ api: ExtensionAPI
    ) {
        // upstream: this._mapDraw && this._mapDraw.__updateOnOwnRoam(model);
        //   No narrowing to `GeoModel`: `MapDraw.__updateOnOwnRoam` takes `MapOrGeoModel` (the
        //   `GeoModel | MapSeries` union, `= ComponentModel` here), and a map series hosted on this geo
        //   component (getHostGeoModel — a case `MapDraw.draw` handles) must roam too.
        if let mapDraw = self._mapDraw {
            mapDraw.__updateOnOwnRoam(componentOrSeries)
        }
    }

    // upstream: private _handleRegionClick(e: ZRElementEvent) — walk from the hit target to the nearest
    //   region element carrying `eventData`, then dispatch `geoToggleSelect` for that region name.
    private func _handleRegionClick(_ e: ElementEvent?) {
        guard let e = e else { return }

        // upstream: findEventDispatcher(e.target, current => (eventData = getECData(current).eventData) != null, true);
        var eventData: ECEventData?
        _ = findEventDispatcher(e.target, { current in
            eventData = innerStore.getECData(current).eventData
            return eventData != nil
        }, true)

        // upstream: if (eventData) { this._api.dispatchAction({ type: 'geoToggleSelect', geoId, name }); }
        //   `geoId` / `name` are payload extras — carried in `Payload.other` (upstream `[other: string]: any`).
        if let eventData = eventData {
            var payload = Payload(type: "geoToggleSelect")
            if let geoId = self._model?.id { payload.other["geoId"] = geoId }
            payload.other["name"] = eventData["name"]
            self._api?.dispatchAction(payload)
        }
    }

    // upstream: updateSelectStatus(model, ecModel, api) — traverse the MapDraw region group; for the first
    //   element carrying `eventData`, enter/leaveSelect per `isSelected(name)` (children need no further
    //   traversal).
    func updateSelectStatus(_ geoModel: GeoModel, _ ecModel: GlobalModel, _ api: ExtensionAPI) {
        // upstream force-derefs `this._mapDraw.group` (it is called right after `draw`); guard instead (§12).
        guard let mapDraw = self._mapDraw else { return }
        _ = mapDraw.group.traverse { node in
            // upstream: const eventData = getECData(node).eventData;
            let eventData = innerStore.getECData(node).eventData
            if let eventData = eventData {
                let name = eventData["name"] as? String
                if self._model?.isSelected(name) == true {
                    api.enterSelect(node)
                }
                else {
                    api.leaveSelect(node)
                }
                // upstream: return true; — No need to traverse children.
                return true
            }
            return false
        }
    }

    // upstream: findHighDownDispatchers(name: string): Element[] {
    //     return this._mapDraw && this._mapDraw.findHighDownDispatchers(name, this._model); }
    //   nil-vs-[] contract: `findComponentHighDownDispatchers` treats non-nil (even empty) as "the feature
    //   is supported here"; a missing MapDraw (map not built) returns nil = unsupported, so the fallback
    //   emphasis of the hovered element is not swallowed.
    public override func findHighDownDispatchers(_ name: String?) -> [Element]? {
        guard let mapDraw = self._mapDraw, let model = self._model else { return nil }
        return mapDraw.findHighDownDispatchers(name, model)
    }

    // upstream: dispose() { this._mapDraw && this._mapDraw.remove(); }
    public override func dispose(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        self._mapDraw?.remove()
        self._mapDraw = nil
    }
}

// export default GeoView;  → `public final class GeoView` above.

// upstream: `class GeoView extends ComponentView` also `@implements RoamHostView['__updateOnOwnRoam']`
//   (a structural implement, not a declared `implements`). Declared here as a real conformance so the
//   roam dispatcher can find it; the signature matches `RoamHostView` EXACTLY (util/types.swift) —
//   narrowing the model param would silently fail to witness it (MEMORY: protocol-witness trap).
extension GeoView: RoamHostView {}

// ============================================================================
// PORT-NOTE helper — NOT part of GeoView.ts upstream: the JS-truthiness bridge
// for the dynamic option bag (`if (geoModel.get('show'))`). The MapDraw subset
// that used to live here (getFixedItemStyle / the style-bag → PathStyleProps
// bridge) is DELETED — it now lives in its real upstream home, MapDraw.swift.
// ============================================================================

/// JS truthiness for the dynamic option bag (`if (x)` on `get(...)`); mirrors MapView.mapJsTruthy (CONVENTIONS §6).
private func jsTruthy(_ v: Any?) -> Bool {
    guard let v = v, !(v is NSNull) else { return false }
    if let b = v as? Bool { return b }
    if let d = v as? Double { return d != 0 && !d.isNaN }
    if let i = v as? Int { return i != 0 }
    if let s = v as? String { return !s.isEmpty }
    if let a = v as? [Any] { return !a.isEmpty }
    return true
}
