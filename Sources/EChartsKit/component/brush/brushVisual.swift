// Ported from echarts/src/component/brush/visualEncoding.ts — keep in sync with upstream.
// FILE NAME: upstream `visualEncoding.ts`; renamed here because SwiftPM requires unique source
//   basenames per module and `component/visualMap/visualEncoding.swift` already claims that name
//   (cf. the model/Component.swift -> view/ComponentView.swift precedent). No identifiers change.
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

// import * as zrUtil from 'zrender/src/core/util';
// import BoundingRect from 'zrender/src/core/BoundingRect';
// import * as visualSolution from '../../visual/visualSolution';
// import { BrushSelectableArea, makeBrushCommonSelectorForSeries } from './selector';  -> selector.swift
// import * as throttleUtil from '../../util/throttle';   -> util/throttle.swift (createOrUpdate)
// import BrushTargetManager from '../helper/BrushTargetManager';   -> BrushTargetManager.swift
// import ParallelSeriesModel from '../../chart/parallel/ParallelSeries';
// import { createSimpleOverallStageHandler2, initExtentForUnion } from '../../util/model';

// type BrushVisualState = 'inBrush' | 'outOfBrush';
public typealias BrushVisualState = String

// const STATE_LIST = ['inBrush', 'outOfBrush'] as const;
private let STATE_LIST: [String] = ["inBrush", "outOfBrush"]
// const DISPATCH_METHOD = '__ecBrushSelect';
// const DISPATCH_FLAG = '__ecInBrushSelectEvent';
//
// interface BrushGlobalDispatcher extends ZRenderType {
//     [DISPATCH_FLAG]: boolean;
//     [DISPATCH_METHOD]: typeof doDispatch;
// }
//   PORT-NOTE: upstream stamps the throttled dispatch method and the re-entrancy flag onto the LIVE
//   ZRender instance (that is the whole point: one throttle window + one guard per chart instance),
//   so those slots die WITH the zr. Swift cannot add stored properties to `ZRender`, so the slot lives
//   in a module-level dictionary keyed by `ObjectIdentifier(zr)`. Three hazards that idiom introduces
//   which upstream does not have, and how they are handled here:
//     (a) LIFETIME — the slot would otherwise outlive the chart, and the throttle can now fire
//         ASYNCHRONOUSLY (fixRate/debounce with a non-zero throttleDelay). `BrushDispatchSlot.api` is
//         therefore `weak`, so a timer landing after teardown finds `nil` and no-ops; `doDispatch`
//         additionally honours upstream's `api.isDisposed()` guard. NOTHING here retains the chart.
//     (b) KEY RECYCLING — `ObjectIdentifier` is just an address and IS reused after the zr deallocates,
//         so a new chart's ZRender can land on a dead chart's key and inherit its throttle window /
//         pending timer / stale payload. The slot therefore also stores `weak var zr` and every lookup
//         re-validates identity (`slot.zr === zr`), clearing + evicting a mismatched slot.
//     (c) PURGE — unlike the render-scoped scratch stores in `util/jitter.swift` (plain value data, reset
//         per render via `resetJitterStore`) or `chart/tree/layoutHelper.swift`, this entry OUTLIVES a
//         render pass and so must be purged explicitly: see `clearBrushDispatch(_:)` below, called from
//         `ECharts.dispose()` — the port's stand-in for upstream's `throttle.clear(obj, fnAttr)` on
//         remove/dispose (throttle.ts).
//   All access is main-thread-only (the visual stage and `ThrottledFunction.scheduleExec`'s
//   `DispatchQueue.main.asyncAfter` both run there); the store is intentionally unsynchronised.
//
// upstream calls the throttled method as `fn(api, brushSelected)` — the throttle captures the LATEST
//   args (`args = cbArgs`) and replays them from `exec()`. This port's `ThrottledFunction` is nullary
//   (see util/throttle.swift), so the args ride in this same per-zr mutable box, which the wrapped
//   closure reads at exec time — same "latest args win" semantics.
private final class BrushDispatchSlot {
    weak var zr: ZRenderType?
    weak var api: ExtensionAPI?
    var brushSelected: [BrushSelectedItem] = []
    var fn: ThrottledFunction?
    init(zr: ZRenderType) { self.zr = zr }
    func clear() {
        throttleUtil.clear(fn)
        fn = nil
        api = nil
        brushSelected = []
    }
}
private var _dispatchSlotStore: [ObjectIdentifier: BrushDispatchSlot] = [:]

// `zr[DISPATCH_FLAG]` — the re-entrancy guard. Keyed by the API instance (not the zr) so the hosted and
//   the headless (`api.getZr() == nil`) paths share ONE guard; it is set and cleared synchronously
//   around `api.dispatchAction`, so the key can never be observed stale/recycled.
private var _dispatchFlagStore: Set<ObjectIdentifier> = []

/// Purge the per-zr brush-dispatch slot (throttle wrapper + pending timer + payload box).
///   upstream: `throttleUtil.clear(zr, DISPATCH_METHOD)` semantics on chart teardown — upstream gets this
///   for free because the slots hang off the zr itself. Called from `ECharts.dispose()`.
internal func clearBrushDispatch(_ zr: ZRenderType?) {
    if let zr = zr {
        let key = ObjectIdentifier(zr)
        _dispatchSlotStore[key]?.clear()
        _dispatchSlotStore.removeValue(forKey: key)
    }
    // Also sweep entries whose zr has already deallocated (their key is now recyclable).
    for (k, slot) in _dispatchSlotStore where slot.zr == nil {
        slot.clear()
        _dispatchSlotStore.removeValue(forKey: k)
    }
}

// interface BrushSelectedItem { brushId; brushIndex; brushName; areas; selected: {seriesId; seriesIndex;
//     seriesName; dataIndex: number[]}[] }
//   Modeled as classes (they are MUTATED while building: `seriesBrushSelected.dataIndex.push(...)`),
//   serialized to the `[String: Any]` bag the `brushSelect` action payload / `brushselected` event carries.
public final class BrushSelectedSeries {
    public let seriesId: String
    public let seriesIndex: Int
    public let seriesName: String
    public var dataIndex: [Int] = []
    init(seriesId: String, seriesIndex: Int, seriesName: String) {
        self.seriesId = seriesId; self.seriesIndex = seriesIndex; self.seriesName = seriesName
    }
    public func toDict() -> [String: Any] {
        return ["seriesId": seriesId, "seriesIndex": seriesIndex, "seriesName": seriesName,
                "dataIndex": dataIndex]
    }
}
public final class BrushSelectedItem {
    public let brushId: String
    public let brushIndex: Int
    public let brushName: String
    public let areas: [BrushAreaParamInternal]
    public var selected: [BrushSelectedSeries] = []
    init(brushId: String, brushIndex: Int, brushName: String, areas: [BrushAreaParamInternal]) {
        self.brushId = brushId; self.brushIndex = brushIndex; self.brushName = brushName; self.areas = areas
    }
    public func toDict() -> [String: Any] {
        return ["brushId": brushId, "brushIndex": brushIndex, "brushName": brushName,
                "areas": areas, "selected": selected.map { $0.toDict() }]
    }
    /// The selected raw dataIndices of one series — the headless test oracle.
    public func selectedDataIndices(_ seriesIndex: Int) -> [Int] {
        return selected.first { $0.seriesIndex == seriesIndex }?.dataIndex ?? []
    }
}

// The `takeGlobalCursor` arm/disarm, factored out of `brushVisual`'s first `eachComponent` loop:
//     payload && payload.type === 'takeGlobalCursor' && brushModel.setBrushOption(
//         payload.key === 'brush' ? payload.brushOption : {brushType: false}
//     );
//
// PORT-NOTE (stage order): upstream runs the VISUAL stages BEFORE `renderComponents`, so by the time
//   BrushView renders, `brushModel.brushOption` is already fresh and its controller arms on the SAME
//   frame the `takeGlobalCursor` action arrives. This driver renders the components FIRST and runs the
//   brush visual near the end of `render()` (it must follow the LAYOUT stages — the selectors read each
//   datum's `getItemLayout`). So `BrushView._updateController` calls this too. It is idempotent: same
//   payload, same `setBrushOption` result. Without it the paint cursor would only arm one frame late, and
//   the very first drag after clicking the brush button would do nothing.
func applyTakeGlobalCursor(_ brushModel: BrushModel, _ payload: Payload?) {
    guard let payload = payload, payload.type == "takeGlobalCursor" else { return }
    let key = payload.other["key"] as? String
    let brushOption = (payload.other["brushOption"] as? [String: Any]) ?? [:]
    // `{brushType: false}` -> `["brushType": NSNull()]`: `generateBrushOption` merges this over the
    //   component option (which carries a `brushType` default), so the key must be PRESENT and falsy to
    //   disable — an absent key would let the default win. `as? String` on NSNull is nil, i.e. exactly
    //   upstream's falsy `false`.
    brushModel.setBrushOption(key == "brush" ? brushOption : ["brushType": NSNull()])
}

// export function layoutCovers(ecModel: GlobalModel): void
public func layoutCovers(_ ecModel: GlobalModel) {
    // ecModel.eachComponent({mainType: 'brush'}, function (brushModel: BrushModel) {
    //     const brushTargetManager = brushModel.brushTargetManager = new BrushTargetManager(brushModel.option, ecModel);
    //     brushTargetManager.setInputRanges(brushModel.areas, ecModel);
    // });
    ecModel.eachComponent("brush") { brushModelIn, _ in
        guard let brushModel = brushModelIn as? BrushModel else { return }
        let brushTargetManager = BrushTargetManager(
            (brushModel.option as? [String: Any]) ?? [:], ecModel
        )
        brushModel.brushTargetManager = brushTargetManager
        brushTargetManager.setInputRanges(&brushModel.areas, ecModel)
    }
}

// export const brushVisualStageHandler = createSimpleOverallStageHandler2(brushVisual);
public let brushVisualStageHandler: StageHandler = model.createSimpleOverallStageHandler2(brushVisual)

/**
 * Register the visual encoding if this modules required.
 */
// function brushVisual(ecModel: GlobalModel, api: ExtensionAPI, payload: Payload)
public func brushVisual(_ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload?) {

    // const brushSelected: BrushSelectedItem[] = [];
    var brushSelected: [BrushSelectedItem] = []
    var throttleType: String?
    var throttleDelay: Double?

    // ecModel.eachComponent({mainType: 'brush'}, function (brushModel) {
    //     payload && payload.type === 'takeGlobalCursor' && brushModel.setBrushOption(
    //         payload.key === 'brush' ? payload.brushOption : {brushType: false}
    //     );
    // });
    ecModel.eachComponent("brush") { brushModelIn, _ in
        guard let brushModel = brushModelIn as? BrushModel else { return }
        applyTakeGlobalCursor(brushModel, payload)
    }

    layoutCovers(ecModel)

    ecModel.eachComponent("brush") { brushModelIn, brushIndexD in
        guard let brushModel = brushModelIn as? BrushModel else { return }
        let brushIndex = Int(brushIndexD)

        // const thisBrushSelected: BrushSelectedItem = {brushId, brushIndex, brushName,
        //     areas: zrUtil.clone(brushModel.areas), selected: []};
        let thisBrushSelected = BrushSelectedItem(
            brushId: brushModel.id,
            brushIndex: brushIndex,
            brushName: brushModel.name,
            areas: util.clone(brushModel.areas)
        )
        // Every brush component exists in event params, convenient
        // for user to find by index.
        brushSelected.append(thisBrushSelected)

        let brushOption = (brushModel.option as? [String: Any]) ?? [:]
        let brushLink = brushOption["brushLink"]
        var linkedSeriesMap: [Int: Bool] = [:]
        var selectedDataIndexForLink: [Int: Bool] = [:]
        var rangeInfoBySeries: [Int: [BrushSelectableArea]] = [:]
        var hasBrushExists = false

        // if (!brushIndex) { // Only the first throttle setting works.
        //     throttleType = brushOption.throttleType; throttleDelay = brushOption.throttleDelay;
        // }
        if brushIndex == 0 {
            throttleType = brushOption["throttleType"] as? String
            throttleDelay = brushCoerceDouble(brushOption["throttleDelay"])
        }

        // Add boundingRect and selectors to range.
        // const areas: BrushSelectableArea[] = zrUtil.map(brushModel.areas, function (area) {
        //     const builder = boundingRectBuilders[area.brushType];
        //     const selectableArea = zrUtil.defaults({boundingRect: builder ? builder(area) : void 0}, area);
        //     selectableArea.selectors = makeBrushCommonSelectorForSeries(selectableArea);
        //     return selectableArea;
        // });
        let areas: [BrushSelectableArea] = util.map(brushModel.areas) { area, _ in
            let builder = boundingRectBuilders[(area["brushType"] as? BrushType) ?? ""]
            let selectableArea = BrushSelectableArea(area, boundingRect: builder != nil ? builder!(area) : nil)
            selectableArea.selectors = makeBrushCommonSelectorForSeries(selectableArea)
            return selectableArea
        }

        // const visualMappings = visualSolution.createVisualMappings(brushModel.option, STATE_LIST,
        //     function (mappingOption) { mappingOption.mappingMethod = 'fixed'; });
        let visualMappings = visualSolution.createVisualMappings(
            brushOption, STATE_LIST
        ) { mappingOption, _ in
            mappingOption["mappingMethod"] = "fixed"
        }

        // zrUtil.isArray(brushLink) && zrUtil.each(brushLink, seriesIndex => { linkedSeriesMap[seriesIndex] = 1; });
        if let linkArr = brushLink as? [Any] {
            util.each(linkArr) { si, _ in
                if let i = brushCoerceInt(si) { linkedSeriesMap[i] = true }
            }
        }

        // function linkOthers(seriesIndex) { return brushLink === 'all' || !!linkedSeriesMap[seriesIndex]; }
        func linkOthers(_ seriesIndex: Int) -> Bool {
            return (brushLink as? String) == "all" || (linkedSeriesMap[seriesIndex] ?? false)
        }

        // If no supported brush or no brush on the series,
        // all visuals should be in original state.
        // function brushed(rangeInfoList) { return !!rangeInfoList.length; }
        func brushed(_ rangeInfoList: [BrushSelectableArea]) -> Bool {
            return !rangeInfoList.isEmpty
        }

        /**
         * Logic for each series: (If the logic has to be modified one day, do it carefully!)
         *
         * ( brushed ┬ && ┬hasBrushExist ┬ && linkOthers  ) => StepA: ┬record, ┬ StepB: ┬visualByRecord.
         *   !brushed┘    ├hasBrushExist ┤                            └nothing,┘        ├visualByRecord.
         *                └!hasBrushExist┘                                              └nothing.
         * ( !brushed  && ┬hasBrushExist ┬ && linkOthers  ) => StepA:  nothing,  StepB: ┬visualByRecord.
         *                └!hasBrushExist┘                                              └nothing.
         * ( brushed ┬ &&                     !linkOthers ) => StepA:  nothing,  StepB: ┬visualByCheck.
         *   !brushed┘                                                                  └nothing.
         * ( !brushed  &&                     !linkOthers ) => StepA:  nothing,  StepB:  nothing.
         */

        // function stepAParallel(seriesModel: ParallelSeriesModel, seriesIndex: number): void
        func stepAParallel(_ seriesModel: SeriesModel, _ seriesIndex: Int) {
            // const coordSys = seriesModel.coordinateSystem;
            //   `seriesModel.coordinateSystem` is `Any?` in this port; for a parallel series it is a
            //   `Parallel` (coord/parallel/Parallel.swift). If the cast fails (no coord system), a
            //   parallel series contributes nothing — matching upstream, which never sees a null here.
            guard let coordSys = seriesModel.coordinateSystem as? Parallel else { return }

            // hasBrushExists = hasBrushExists || coordSys.hasAxisBrushed();
            hasBrushExists = hasBrushExists || coordSys.hasAxisBrushed()

            // linkOthers(seriesIndex) && coordSys.eachActiveState(seriesModel.getData(),
            //     (activeState, dataIndex) => { activeState === 'active' && (selectedDataIndexForLink[dataIndex] = 1); });
            if linkOthers(seriesIndex) {
                coordSys.eachActiveState(seriesModel.getData()) { activeState, dataIndex in
                    if activeState == "active" {
                        selectedDataIndexForLink[dataIndex] = true
                    }
                }
            }
        }

        // function stepAOthers(seriesModel, seriesIndex, rangeInfoList): void
        func stepAOthers(
            _ seriesModel: SeriesModel, _ seriesIndex: Int, _ rangeInfoList: inout [BrushSelectableArea]
        ) {
            // if (!seriesModel.brushSelector || brushModelNotControll(brushModel, seriesIndex)) { return; }
            guard let brushSelector = seriesModel.brushSelector,
                  !brushModelNotControll(brushModel, seriesIndex) else {
                return
            }

            // zrUtil.each(areas, function (area) {
            //     if (brushModel.brushTargetManager.controlSeries(area, seriesModel, ecModel)) { rangeInfoList.push(area); }
            //     hasBrushExists = hasBrushExists || brushed(rangeInfoList);
            // });
            for area in areas {
                if brushModel.brushTargetManager?.controlSeries(area.area, seriesModel, ecModel) == true {
                    rangeInfoList.append(area)
                }
                hasBrushExists = hasBrushExists || brushed(rangeInfoList)
            }

            // if (linkOthers(seriesIndex) && brushed(rangeInfoList)) {
            //     const data = seriesModel.getData();
            //     data.each(function (dataIndex) {
            //         if (checkInRange(seriesModel, rangeInfoList, data, dataIndex)) {
            //             selectedDataIndexForLink[dataIndex] = 1;
            //         }
            //     });
            // }
            if linkOthers(seriesIndex) && brushed(rangeInfoList) {
                let data = seriesModel.getData()
                let list = rangeInfoList
                for dataIndex in 0..<data.count() {
                    if checkInRange(brushSelector, list, data, dataIndex) {
                        selectedDataIndexForLink[dataIndex] = true
                    }
                }
            }
        }

        // Step A
        // ecModel.eachSeries(function (seriesModel, seriesIndex) {
        //     const rangeInfoList = rangeInfoBySeries[seriesIndex] = [];
        //     seriesModel.subType === 'parallel' ? stepAParallel(...) : stepAOthers(...);
        // });
        ecModel.eachSeries { seriesModel, seriesIndexD in
            let seriesIndex = Int(seriesIndexD)
            var rangeInfoList: [BrushSelectableArea] = []

            if seriesModel.subType == "parallel" {
                stepAParallel(seriesModel, seriesIndex)
            }
            else {
                stepAOthers(seriesModel, seriesIndex, &rangeInfoList)
            }
            rangeInfoBySeries[seriesIndex] = rangeInfoList
        }

        // Step B
        ecModel.eachSeries { seriesModel, seriesIndexD in
            let seriesIndex = Int(seriesIndexD)
            let seriesBrushSelected = BrushSelectedSeries(
                seriesId: seriesModel.id,
                seriesIndex: seriesIndex,
                seriesName: seriesModel.name
            )
            // Every series exists in event params, convenient
            // for user to find series by seriesIndex.
            thisBrushSelected.selected.append(seriesBrushSelected)

            let rangeInfoList = rangeInfoBySeries[seriesIndex] ?? []

            let data = seriesModel.getData()
            let brushSelector = seriesModel.brushSelector

            // const getValueState = linkOthers(seriesIndex)
            //     ? dataIndex => selectedDataIndexForLink[dataIndex]
            //         ? (seriesBrushSelected.dataIndex.push(data.getRawIndex(dataIndex)), 'inBrush') : 'outOfBrush'
            //     : dataIndex => checkInRange(seriesModel, rangeInfoList, data, dataIndex)
            //         ? (seriesBrushSelected.dataIndex.push(data.getRawIndex(dataIndex)), 'inBrush') : 'outOfBrush';
            let getValueState: (Any?) -> String
            if linkOthers(seriesIndex) {
                getValueState = { valueOrIndex in
                    let dataIndex = brushCoerceInt(valueOrIndex) ?? 0
                    if selectedDataIndexForLink[dataIndex] ?? false {
                        seriesBrushSelected.dataIndex.append(data.getRawIndex(dataIndex))
                        return "inBrush"
                    }
                    return "outOfBrush"
                }
            }
            else {
                getValueState = { valueOrIndex in
                    let dataIndex = brushCoerceInt(valueOrIndex) ?? 0
                    if let brushSelector = brushSelector,
                       checkInRange(brushSelector, rangeInfoList, data, dataIndex) {
                        seriesBrushSelected.dataIndex.append(data.getRawIndex(dataIndex))
                        return "inBrush"
                    }
                    return "outOfBrush"
                }
            }

            // If no supported brush or no brush, all visuals are in original state.
            // (linkOthers(seriesIndex) ? hasBrushExists : brushed(rangeInfoList))
            //     && visualSolution.applyVisual(STATE_LIST, visualMappings, data, getValueState);
            if linkOthers(seriesIndex) ? hasBrushExists : brushed(rangeInfoList) {
                visualSolution.applyVisual(STATE_LIST, visualMappings, data, getValueState, nil)
            }
        }
    }

    dispatchAction(api, throttleType, throttleDelay, brushSelected, payload)
}

/**
 * payload: {
 *      brushComponents: [
 *          {
 *              brushId, brushIndex, brushName,
 *              series: [{seriesId, seriesIndex, seriesName, rawIndices: [21, 34, ...]}, ...]
 *          },
 *          ...
 *      ]
 * }
 */
// function dispatchAction(api, throttleType, throttleDelay, brushSelected, payload): void
private func dispatchAction(
    _ api: ExtensionAPI,
    _ throttleType: String?,
    _ throttleDelay: Double?,
    _ brushSelected: [BrushSelectedItem],
    _ payload: Payload?
) {
    // This event will not be triggered when `setOption`, otherwise dead lock may
    // triggered when do `setOption` in event listener, which we do not find
    // satisfactory way to solve yet. Some considered resolutions:
    // (a) Diff with previous selected data ant only trigger event when changed.
    // But store previous data and diff precisely (i.e., not only by dataIndex, but
    // also detect value changes in selected data) might bring complexity or fragility.
    // (b) Use special param like `silent` to suppress event triggering.
    // But such kind of volatile param may be weird in `setOption`.
    if payload == nil {
        return
    }

    // FIXME: [INCONSISTENCY_OF_BRUSH_SELECTED_EVENT_IN_UPDATE_TRANSFORM]  (upstream comment retained
    //   verbatim in the .ts; it describes an upstream inconsistency, not a port gap.)

    // if (zr[DISPATCH_FLAG]) { return; }
    //   PORT SEAM: keyed by the api (see `_dispatchFlagStore`) so the guard is identical on the hosted
    //   and the headless path — upstream applies it unconditionally.
    if _dispatchFlagStore.contains(ObjectIdentifier(api)) {
        return
    }

    // const zr = api.getZr() as BrushGlobalDispatcher;
    //   PORT SEAM: `api.getZr()` is Optional here (headless has no host zr — see ExtensionAPI.getZr).
    //   With no zr there is no instance to key the throttle slot on, so dispatch straight through,
    //   which is exactly what upstream's `createOrUpdate` does for the default `throttleDelay: 0`.
    //   (The re-entrancy guard above/inside `doDispatch` still applies — it is keyed by the api.)
    guard let zr = api.getZr() else {
        doDispatch(api, brushSelected)
        return
    }
    let zrKey = ObjectIdentifier(zr)

    // if (!zr[DISPATCH_METHOD]) { zr[DISPATCH_METHOD] = doDispatch; }
    //   -> the "origin method" below IS `doDispatch`; `createOrUpdate` seeds it on first use.
    //   Identity re-validation (see the `_dispatchSlotStore` PORT-NOTE): a slot found under a RECYCLED
    //   ObjectIdentifier belongs to a dead chart — clear its pending timer and start fresh.
    let slot: BrushDispatchSlot
    if let existing = _dispatchSlotStore[zrKey], existing.zr === zr {
        slot = existing
    }
    else {
        _dispatchSlotStore[zrKey]?.clear()
        slot = BrushDispatchSlot(zr: zr)
        _dispatchSlotStore[zrKey] = slot
    }
    slot.api = api
    slot.brushSelected = brushSelected
    let origin: () -> Void = { [weak slot] in
        guard let slot = slot, let api = slot.api else { return }
        doDispatch(api, slot.brushSelected)
    }

    // const fn = throttleUtil.createOrUpdate(zr, DISPATCH_METHOD, throttleDelay, throttleType);
    //   upstream: `if (rate == null || !throttleType) { return (obj[fnAttr] = originFn); }` — a FALSY
    //   `throttleType` (undefined OR the empty string) means "unthrottled". `throttleType` is Optional
    //   here; JS falsiness is replicated by folding "" into nil, and "unthrottled" is expressed by
    //   passing `rate: nil` (same `nil` return → call the origin directly).
    let effectiveThrottleType: String? = (throttleType?.isEmpty == false) ? throttleType : nil
    let parsedThrottleType: ThrottleType? = effectiveThrottleType == nil
        ? nil
        : (effectiveThrottleType == "debounce" ? .debounce : .fixRate)
    let fn = throttleUtil.createOrUpdate(
        existing: slot.fn,
        origin: origin,
        rate: parsedThrottleType == nil ? nil : throttleDelay,
        throttleType: parsedThrottleType ?? .fixRate
    )
    slot.fn = fn

    // fn(api, brushSelected);
    if let fn = fn {
        fn()
    }
    else {
        origin()
    }
}

// function doDispatch(api: ExtensionAPI, brushSelected: BrushSelectedItem[]): void
private func doDispatch(_ api: ExtensionAPI, _ brushSelected: [BrushSelectedItem]) {
    // if (!api.isDisposed()) {
    //     zr[DISPATCH_FLAG] = true;
    //     api.dispatchAction({type: 'brushSelect', batch: brushSelected});
    //     zr[DISPATCH_FLAG] = false;
    // }
    //   This guard is load-bearing here: `dispatchAction` can now schedule the dispatch ASYNCHRONOUSLY
    //   (fixRate/debounce with a non-zero `throttleDelay`), so a pending timer can land after the chart
    //   has been disposed.
    if api.isDisposed() {
        return
    }
    //
    // PORT-NOTE: `Payload.batch` is typed `[PayloadItem]?` in this port (util/types.swift) and cannot
    //   carry the brushSelected items; the batch rides in the dynamic `other` bag instead. That IS the
    //   channel the ported event system reads — `ECharts.doDispatchAction` copies `payload.other` into the
    //   emitted `ECActionEvent.eventData` — so a `chart.on("brushselected")` handler sees
    //   `params.eventData["batch"]` exactly where upstream puts `params.batch`.
    var p = Payload(type: "brushSelect")
    p.other["batch"] = brushSelected.map { $0.toDict() }
    // ADDITIVE: the typed items, so an in-process consumer (a test, a native host) need not re-parse bags.
    p.other["batchItems"] = brushSelected

    // zr[DISPATCH_FLAG] = true; ... zr[DISPATCH_FLAG] = false;  (re-entrancy guard read by dispatchAction;
    //   keyed by the api so headless — where there is no zr — is guarded identically. See the store note.)
    let apiKey = ObjectIdentifier(api)
    _dispatchFlagStore.insert(apiKey)
    defer { _dispatchFlagStore.remove(apiKey) }
    api.dispatchAction(p)
}

// function checkInRange(seriesModel, rangeInfoList, data, dataIndex)
//   PORT-NOTE: `seriesModel` is replaced by its already-resolved `brushSelector` (upstream reads
//   `seriesModel.brushSelector` — an optional declaration-merged method — on every call).
private func checkInRange(
    _ brushSelector: BrushSelectorFn,
    _ rangeInfoList: [BrushSelectableArea],
    _ data: SeriesData,
    _ dataIndex: Int
) -> Bool {
    for i in 0..<rangeInfoList.count {
        let area = rangeInfoList[i]
        // if (seriesModel.brushSelector(dataIndex, data, area.selectors, area)) { return true; }
        if brushSelector(dataIndex, data, area.selectors, area) {
            return true
        }
    }
    return false
}

// function brushModelNotControll(brushModel: BrushModel, seriesIndex: number): boolean
private func brushModelNotControll(_ brushModel: BrushModel, _ seriesIndex: Int) -> Bool {
    // const seriesIndices = brushModel.option.seriesIndex;
    // return seriesIndices != null && seriesIndices !== 'all'
    //     && (isArray(seriesIndices) ? indexOf(seriesIndices, seriesIndex) < 0 : seriesIndex !== seriesIndices);
    let seriesIndices = ((brushModel.option as? [String: Any]) ?? [:])["seriesIndex"]
    if seriesIndices == nil || seriesIndices is NSNull { return false }
    if let s = seriesIndices as? String, s == "all" { return false }
    if let arr = seriesIndices as? [Any] {
        return util.indexOf(arr.compactMap { brushCoerceInt($0) }, seriesIndex) < 0
    }
    if let single = brushCoerceInt(seriesIndices) {
        return seriesIndex != single
    }
    return false
}

// type AreaBoundingRectBuilder = (area: BrushAreaParamInternal) => BoundingRect;
// const boundingRectBuilders: Partial<Record<BrushType, AreaBoundingRectBuilder>>
private let boundingRectBuilders: [BrushType: (BrushAreaParamInternal) -> BoundingRect?] = [

    // rect: function (area) { return getBoundingRectFromMinMax(area.range as BrushDimensionMinMax[]); }
    "rect": { area in
        guard let range = brushDimensionMinMaxList(area["range"]), range.count >= 2 else { return nil }
        return getBoundingRectFromMinMax(range)
    },

    "polygon": { area in
        // let minMax;  const range = area.range as BrushDimensionMinMax[];
        var minMax: [BrushDimensionMinMax]?
        guard let range = brushDimensionMinMaxList(area["range"]) else { return nil }

        for i in 0..<range.count {
            // minMax = minMax || [initExtentForUnion(), initExtentForUnion()];
            if minMax == nil {
                minMax = [model.initExtentForUnion(), model.initExtentForUnion()]
            }
            let rg = range[i]
            if rg[0] < minMax![0][0] { minMax![0][0] = rg[0] }
            if rg[0] > minMax![0][1] { minMax![0][1] = rg[0] }
            if rg[1] < minMax![1][0] { minMax![1][0] = rg[1] }
            if rg[1] > minMax![1][1] { minMax![1][1] = rg[1] }
        }

        // return minMax && getBoundingRectFromMinMax(minMax);
        return minMax != nil ? getBoundingRectFromMinMax(minMax!) : nil
    }
]

// function getBoundingRectFromMinMax(minMax: BrushDimensionMinMax[]): BoundingRect
private func getBoundingRectFromMinMax(_ minMax: [BrushDimensionMinMax]) -> BoundingRect {
    return BoundingRect(
        minMax[0][0],
        minMax[1][0],
        minMax[0][1] - minMax[0][0],
        minMax[1][1] - minMax[1][0]
    )
}
