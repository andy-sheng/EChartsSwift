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
// import * as throttleUtil from '../../util/throttle';   -> PORT-NOTE (deferred), see `dispatchAction`
// import BrushTargetManager from '../helper/BrushTargetManager';   -> BrushTargetManager.swift
// import ParallelSeriesModel from '../../chart/parallel/ParallelSeries';
// import { createSimpleOverallStageHandler2, initExtentForUnion } from '../../util/model';

// type BrushVisualState = 'inBrush' | 'outOfBrush';
public typealias BrushVisualState = String

// const STATE_LIST = ['inBrush', 'outOfBrush'] as const;
private let STATE_LIST: [String] = ["inBrush", "outOfBrush"]
// const DISPATCH_METHOD = '__ecBrushSelect';
// const DISPATCH_FLAG = '__ecInBrushSelectEvent';
//   -> see the `dispatchAction` PORT-NOTE (no zr-attached throttle in this port).

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
            // hasBrushExists = hasBrushExists || coordSys.hasAxisBrushed();
            // linkOthers(seriesIndex) && coordSys.eachActiveState(seriesModel.getData(),
            //     (activeState, dataIndex) => { activeState === 'active' && (selectedDataIndexForLink[dataIndex] = 1); });
            //
            // PORT-NOTE (deferred): `Parallel.hasAxisBrushed()` / `Parallel.eachActiveState()` express the
            //   PARALLEL-AXIS brush state, which is painted by ParallelAxisView's own BrushController — and
            //   that view's live axis-drag brush is itself unported (see the PORT-NOTE at
            //   `installParallelActions` in core/ECharts.swift). WHAT WE DO: a parallel series contributes
            //   nothing to `hasBrushExists` and adds no linked selection. USER-VISIBLE CONSEQUENCE: with
            //   `brushLink`, a selection made on a PARALLEL axis does not propagate to the other series.
            //   A rect/lineX/lineY/polygon brush over cartesian/geo series is unaffected.
            _ = (seriesModel, seriesIndex)
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

    // const zr = api.getZr() as BrushGlobalDispatcher;
    // if (zr[DISPATCH_FLAG]) { return; }
    // if (!zr[DISPATCH_METHOD]) { zr[DISPATCH_METHOD] = doDispatch; }
    // const fn = throttleUtil.createOrUpdate(zr, DISPATCH_METHOD, throttleDelay, throttleType);
    // fn(api, brushSelected);
    //
    // PORT-NOTE (deferred): `util/throttle.ts` is not ported, so the throttle wrapper and the
    //   zr-attached `DISPATCH_FLAG` re-entrancy guard are dropped; `doDispatch` runs synchronously.
    //   WHY IT IS SAFE: `throttleDelay` defaults to 0 (BrushModel.defaultOption) and upstream's
    //   `throttleUtil.createOrUpdate(..., 0, ...)` returns the raw function — so for the default
    //   configuration this IS upstream behavior. The re-entrancy flag guards against `brushSelect`
    //   re-entering the visual stage, which cannot happen here either: the action is registered with
    //   `update: 'none'`. USER-VISIBLE CONSEQUENCE: a brush configured with a non-zero `throttleDelay`
    //   emits `brushselected` on every drag step rather than at most once per delay window (the same
    //   selection data, just more events).
    _ = (throttleType, throttleDelay)
    doDispatch(api, brushSelected)
}

// function doDispatch(api: ExtensionAPI, brushSelected: BrushSelectedItem[]): void
private func doDispatch(_ api: ExtensionAPI, _ brushSelected: [BrushSelectedItem]) {
    // if (!api.isDisposed()) {
    //     zr[DISPATCH_FLAG] = true;
    //     api.dispatchAction({type: 'brushSelect', batch: brushSelected});
    //     zr[DISPATCH_FLAG] = false;
    // }
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
