// Ported from echarts/src/legacy/dataSelectAction.ts — keep in sync with upstream
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

// upstream imports (mapped to this port; `->` marks the Swift symbol used):
//   import { Payload, SelectChangedEvent } from '../util/types';   -> `Payload` / `SelectChangedEvent` (util/types.swift).
//   import SeriesModel from '../model/Series';                     -> `SeriesModel`.
//   import { extend, each, isArray, isString } from 'zrender/src/core/util';
//       -> `Payload` is a value type (a `var` copy IS the `extend({}, payload)` clone); `each`/`isArray`/
//          `isString` collapse to native Swift iteration / `as?` casts.
//   import GlobalModel from '../model/Global';                     -> `GlobalModel`.
//   import { deprecateReplaceLog, deprecateLog } from '../util/log';
//       -> `log.deprecateReplaceLog` / `log.deprecateLog` — gated on `__DEV__` upstream; the port has no
//          `__DEV__` flag wired, so the dev-only deprecation logs are skipped (see sunburstAction.swift).
//   import Eventful from 'zrender/src/core/Eventful';              -> the INTERNAL bus is `MessageCenter`
//          (ECharts.swift; upstream `class MessageCenter extends Eventful`).
//   import type { EChartsType, registerAction } from '../core/echarts';
//       -> `ECharts` (the concrete driver — `EChartsType` is an empty marker protocol here) / the
//          two-arg `registerAction(type, handler)` arm (core/action.swift).
//   import { queryDataIndex } from '../util/model';                -> `model.queryDataIndex`
//       (upstream aliased the import `modelUtil`, but the ported caseless enum is `model`; modelUtil.swift:451).
//   import ExtensionAPI from '../core/ExtensionAPI';               -> `ExtensionAPI`.

// Legacy data selection action.
// Includes: pieSelect, pieUnSelect, pieToggleSelect, mapSelect, mapUnSelect, mapToggleSelect
//
// note (§3): a TS module of free functions → a caseless `enum` named after the file, so the shared
//   exports (`createLegacyDataSelectAction`, `handleLegacySelectEvents`) live under one namespace.
public enum dataSelectAction {

    // export function createLegacyDataSelectAction(seriesType, ecRegisterAction: typeof registerAction)
    //   `ecRegisterAction` is the two-arg `registerAction(type, handler)` arm (the only one used here).
    // note (registration site): upstream calls this from the map and pie installs
    //   (`createLegacyDataSelectAction('map'/'pie', registers.registerAction)` — chart/map/install.ts:37,
    //   chart/pie/install.ts:33). In this port the `*Install.swift` files are commented-only diffable
    //   surface; the ACTUAL install() bodies are inlined in `ECharts.installOnce()` (the geo/heatmap
    //   convention), so both calls live there — pie next to `ComponentModel.registerClass(PieSeriesModel)`
    //   and map next to `ComponentModel.registerClass(MapSeriesModel)`. `ecRegisterAction` is passed as a
    //   closure forwarding to the free two-arg `registerAction` (overload disambiguation).
    public static func createLegacyDataSelectAction(
        _ seriesType: String,
        _ ecRegisterAction: (String, @escaping ActionHandler) -> Void
    ) {

        // function getSeriesIndices(ecModel, payload) { ... }
        func getSeriesIndices(_ ecModel: GlobalModel, _ payload: Payload) -> [Double] {
            var seriesIndices: [Double] = []
            // ecModel.eachComponent({ mainType: 'series', subType: seriesType, query: payload }, cb)
            //   Component-query fields (seriesId/seriesIndex/…) live in `payload.other` (see sunburstAction.swift).
            ecModel.eachComponent(
                QueryConditionKindA(mainType: "series", query: payload.other, subType: seriesType)
            ) { modelBase, _ in
                guard let seriesModel = modelBase as? SeriesModel else { return }
                // seriesIndices.push(seriesModel.seriesIndex);
                seriesIndices.append(seriesModel.seriesIndex)
            }
            return seriesIndices
        }

        // each([[type+'ToggleSelect','toggleSelect'], [type+'Select','select'], [type+'UnSelect','unselect']], cb)
        let eventsMaps: [(String, String)] = [
            (seriesType + "ToggleSelect", "toggleSelect"),
            (seriesType + "Select", "select"),
            (seriesType + "UnSelect", "unselect")
        ]
        for eventsMap in eventsMaps {
            // ecRegisterAction(eventsMap[0], function (payload, ecModel, api) { ... });
            ecRegisterAction(eventsMap.0) { payload, ecModel, api in
                // payload = extend({}, payload);  — `Payload` is a value type, so a `var` copy IS the clone.
                var payload = payload

                // if (__DEV__) { deprecateReplaceLog(payload.type, eventsMap[1]); }
                //   dev-only deprecation log skipped (no `__DEV__` flag wired; see the import note above).

                // api.dispatchAction(extend(payload, { type: eventsMap[1], seriesIndex: getSeriesIndices(...) }));
                //   `seriesIndex` is a dynamic payload field → `payload.other` (mirrors sunburstAction.swift).
                //   Upstream evaluates the object literal (including `getSeriesIndices(ecModel, payload)`)
                //   BEFORE `extend` mutates `payload`, so its `getSeriesIndices` sees the ORIGINAL legacy
                //   type ('pieSelect'), not the rewritten one. Hoisted here to keep that sequencing.
                let seriesIndices = getSeriesIndices(ecModel, payload)
                payload.type = eventsMap.1
                payload.other["seriesIndex"] = seriesIndices
                api.dispatchAction(payload)

                return nil
            }
        }
    }

    // function handleSeriesLegacySelectEvents(type, eventPostfix, ecIns, ecModel, payload) { ... }
    private static func handleSeriesLegacySelectEvents(
        _ type: String,                       // 'map' | 'pie'
        _ eventPostfix: String,               // 'selectchanged' | 'selected' | 'unselected'
        _ ecIns: ECharts,
        _ ecModel: GlobalModel,
        _ payload: SelectChangedEvent
    ) {
        // const legacyEventName = type + eventPostfix;
        let legacyEventName = type + eventPostfix
        // if (!ecIns.isSilent(legacyEventName)) {
        if !ecIns.isSilent(legacyEventName) {
            // if (__DEV__) { deprecateLog(`event ${legacyEventName} is deprecated.`); }
            //   dev-only deprecation log skipped (see the import note above).

            // ecModel.eachComponent({ mainType: 'series', subType: 'pie' }, cb)
            //   note (upstream quirk, faithful — do NOT "fix"): `subType` is hardcoded 'pie' even when
            //   `type` == 'map' (dataSelectAction.ts:77), while `legacyEventName` above is built from
            //   `type`. Net effect upstream AND here: the 'mapselectchanged' / 'mapselected' /
            //   'mapunselected' legacy events can never match a map series, because this loop only ever
            //   visits pie components. Changing 'pie' to `type` would emit events echarts does not emit.
            ecModel.eachComponent(
                QueryConditionKindA(mainType: "series", subType: "pie")
            ) { modelBase, _ in
                guard let seriesModel = modelBase as? SeriesModel else { return }
                // const seriesIndex = seriesModel.seriesIndex;
                let seriesIndex = seriesModel.seriesIndex
                // const selectedMap = seriesModel.option.selectedMap;
                let selectedMap = (seriesModel.option as? [String: Any])?["selectedMap"]
                // const selected = payload.selected;
                let selected = payload.selected
                // for (let i = 0; i < selected.length; i++) {
                for i in 0..<selected.count {
                    // if (selected[i].seriesIndex === seriesIndex) {
                    if selected[i].seriesIndex == seriesIndex {
                        // const data = seriesModel.getData();
                        let data = seriesModel.getData()
                        // const dataIndex = queryDataIndex(data, payload.fromActionPayload);
                        //   note (divergence, intentional): the `?? Payload(type: "")` fallback and the
                        //   `arr.isEmpty` guard below are safety hardening not present upstream (which
                        //   passes a possibly-undefined payload and unconditionally reads `dataIndex[0]`).
                        //   Both are non-crashing; kept for defensiveness.
                        let dataIndex = model.queryDataIndex(data, payload.fromActionPayload ?? Payload(type: ""))
                        // name: isArray(dataIndex) ? data.getName(dataIndex[0]) : data.getName(dataIndex)
                        //   `queryDataIndex` yields an `Int` (or `[Int]`); `ecEventNumber` coerces the boxing.
                        //   note (divergence, intentional): `Int(Double)` TRAPS on NaN/infinity, and
                        //   `queryDataIndex`'s first branch (modelUtil.swift:1114) returns the RAW
                        //   user-supplied `payload.other["dataIndexInside"]` un-coerced — so a hostile/blank
                        //   payload could otherwise reach `Int(Double.nan)` and SIGTRAP. Non-finite values
                        //   collapse to -1, the correct JS-`undefined` analogue (`getName(-1)` is bounds-safe:
                        //   DataStore.getRawIndex -> -1, DataStore.get guarded).
                        func finiteIndex(_ boxed: Any?) -> Int {
                            guard let n = ecEventNumber(boxed), n.isFinite else { return -1 }
                            return Int(n)
                        }
                        let name: String
                        if let arr = dataIndex as? [Any] {
                            name = arr.isEmpty ? data.getName(-1) : data.getName(finiteIndex(arr[0]))
                        }
                        else {
                            name = data.getName(finiteIndex(dataIndex))
                        }
                        // selected: isString(selectedMap) ? selectedMap : extend({}, selectedMap)
                        //   selectedMap is 'all' (string) or a { name: boolean } map (value-copied by read).
                        //   The non-string branch mirrors `extend({}, selectedMap)`: when selectedMap is
                        //   undefined upstream yields an empty object `{}`, so fall back to `[:]` (assigning
                        //   nil to an ECEventData key would DROP it, not store an empty map).
                        let selectedValue: Any?
                        if let s = selectedMap as? String {
                            selectedValue = s
                        }
                        else {
                            selectedValue = (selectedMap as? [String: Any]) ?? [String: Any]()
                        }
                        // ecIns.trigger(legacyEventName, { type, seriesId, name, selected });
                        //   The flat upstream object → an `ECActionEvent` carrying the extra fields in its
                        //   dynamic `eventData` bag (seriesId/name/selected are read back off it).
                        var event = ECActionEvent(type: legacyEventName)
                        event.eventData["seriesId"] = seriesModel.id
                        event.eventData["name"] = name
                        event.eventData["selected"] = selectedValue
                        _ = ecIns.trigger(legacyEventName, event)
                    }
                }
            }
        }
    }

    // export function handleLegacySelectEvents(messageCenter, ecIns, api) { ... }
    //   Internal (not `public`): `MessageCenter` is the module-internal bus, and the only caller is
    //   `ECharts._initEvents` (same module).
    static func handleLegacySelectEvents(
        _ messageCenter: MessageCenter,
        _ ecIns: ECharts,
        _ api: ExtensionAPI
    ) {
        // messageCenter.on('selectchanged', function (params: SelectChangedEvent) { ... });
        //
        // note (real gap — read this before "fixing" the cast): 'selectchanged' IS published on the
        //   bus TODAY and this handler DOES run on every select/unselect/toggleSelect. It is not dormant.
        //   actionRegister.swift:48 registers those three actions with `event = SELECT_CHANGED_EVENT_TYPE`
        //   and `refineEvent == nil`, so action.swift's `nonRefinedEventType` resolves to 'selectchanged'
        //   (not the action type), and ECharts.doDispatchAction (ECharts.swift:2606) triggers it carrying
        //   an `ECActionEvent` — NOT a `SelectChangedEvent`. A bare `as? SelectChangedEvent` therefore
        //   silently DROPPED every event. Both shapes are accepted below.
        //
        // REMAINING GAP (owned by the refineEvent row, not this one): that `ECActionEvent` is replicated
        //   from the raw select PAYLOAD, so it carries no `selected` array — that field is computed by
        //   `refineEvent` (`makeSelectChangedEvent`), still DEFERRED (ECharts.swift:2595 /
        //   actionRegister.swift:52) even though its dependency `states.getAllSelectedIndices`
        //   (states.swift:799) is already ported. Until it lands `selected` reconstructs EMPTY, so
        //   `handleSeriesLegacySelectEvents`'s inner loop matches nothing and no legacy event is emitted.
        //   The legacy events begin firing the moment `makeSelectChangedEvent` is wired — nothing further
        //   is needed HERE.
        messageCenter.on("selectchanged") { [weak ecIns, weak api] _, args in
            guard let ecIns = ecIns, let api = api else { return nil }
            let raw = args.first.flatMap({ $0 })
            let params: SelectChangedEvent
            if let refined = raw as? SelectChangedEvent {
                // Fast path: a future `refineEvent` publishing the struct directly.
                params = refined
            }
            else if let actionEvent = raw as? ECActionEvent {
                // Today's path: rebuild the upstream field set out of the dynamic `eventData` bag.
                var rebuilt = SelectChangedEvent()
                rebuilt.type = actionEvent.type
                rebuilt.isFromClick = (actionEvent.eventData["isFromClick"] as? Bool) ?? false
                rebuilt.fromAction = (actionEvent.eventData["fromAction"] as? String) ?? ""
                rebuilt.fromActionPayload = actionEvent.eventData["fromActionPayload"] as? Payload
                rebuilt.selected = (actionEvent.eventData["selected"] as? [SelectedItem]) ?? []
                params = rebuilt
            }
            else {
                return nil
            }
            // const ecModel = api.getModel();
            let ecModel = api.getModel()
            if params.isFromClick {
                // handleSeriesLegacySelectEvents('map'/'pie', 'selectchanged', ecIns, ecModel, params);
                handleSeriesLegacySelectEvents("map", "selectchanged", ecIns, ecModel, params)
                handleSeriesLegacySelectEvents("pie", "selectchanged", ecIns, ecModel, params)
            }
            else if params.fromAction == "select" {
                handleSeriesLegacySelectEvents("map", "selected", ecIns, ecModel, params)
                handleSeriesLegacySelectEvents("pie", "selected", ecIns, ecModel, params)
            }
            else if params.fromAction == "unselect" {
                handleSeriesLegacySelectEvents("map", "unselected", ecIns, ecModel, params)
                handleSeriesLegacySelectEvents("pie", "unselected", ecIns, ecModel, params)
            }
            return nil
        }
    }
}
