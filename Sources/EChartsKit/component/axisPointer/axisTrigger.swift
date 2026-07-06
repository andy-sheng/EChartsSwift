// Ported from echarts/src/component/axisPointer/axisTrigger.ts — keep in sync with upstream.
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
// WHAT THIS FILE IS  (Phase 35, TASK 2 — the trigger:"axis" core)
// ============================================================================
// The default `axisTrigger(payload, ecModel, api)`: given a pointer `point` (payload.x/y), it walks the
// collected axisPointer coord-system/axis info (built by modelHelper.collect — TASK 1), resolves the
// AXIS VALUE at the pointer on each involved axis (`axis.pointToData`), snaps it to the nearest series
// data per axis (`buildPayloadsBySeries`), and assembles `dataByCoordSys` (the DataByCoordSys/DataByAxis
// tree). It then dispatches a `showTip` action carrying `dataByCoordSys` (consumed by the tooltip
// trigger:"axis" path — `TooltipView._showAxisTooltip`), or `hideTip` if nothing resolved.
//
// SCOPE / DEFERRED:
//   - `updateModelActually` writes each axisPointer model's `status`/`value`/`seriesDataIndices` (the
//     crosshair STATUS). It is ported (it is pure computation), but the DRAW of that crosshair (the
//     axisPointer VIEW render) is Phase 36 — see the PORT-TODO in `updateModelActually`.
//   - `dispatchHighDownActually` (highlight/downplay fan-out on axis hover) IS ported — the Phase-30
//     emphasis engine backs it. Its per-instance diff store is keyed on `api` (upstream keys on
//     `api.getZr()`; this port's ExtensionAPI has no `getZr()` yet — documented deviation).
//   - `series.getAxisTooltipData` (candlestick/boxplot) + `link.mapper` (linked-axis value mapping) are
//     DEFERRED (PORT-TODOs at their sites); the default `indicesOfNearest` snap + pass-through link are used.
//
// import {makeInner, ModelFinderObject} from '../../util/model';   -> `model.*` (util/modelUtil.swift)
// import * as modelHelper from './modelHelper';                    -> `modelHelper.*` (TASK 1 — see contract)
// import findPointFromSeries from './findPointFromSeries';         -> findPointFromSeries (sibling file)
// import GlobalModel / ExtensionAPI                                -> GlobalModel / ExtensionAPI
// import AxisPointerModel, { AxisPointerOption } from './AxisPointerModel'; -> AxisPointerModel (TASK 1)
// import { isNullableNumberFinite } from '../../util/number';      -> number.isNullableNumberFinite
//
// ============================================================================
// INTEGRATION CONTRACT — TASK 1 (parallel task; reconcile at the single build)
// ============================================================================
// This file consumes these TASK-1 symbols (faithful to modelHelper.ts / AxisPointerModel.ts). If TASK 1's
// names/shapes differ, reconcile HERE — the coupling is localized to the field/method accesses below:
//
//   open class AxisPointerModel : ComponentModel {
//       var coordSysAxesInfo: Any?    // holds the CollectionResult (cast at use); set by collect(...)
//   }
//
//   final class CollectionResult {                   // ReturnType<modelHelper.collect>
//       var coordSysAxesInfo: [String: [String: AxisInfo]]   // [coordSysKey][axisKey] -> AxisInfo
//       var axesInfo:         [String: AxisInfo]             // [axisKey] -> AxisInfo (flat)
//       var coordSysMap:      [String: CoordinateSystemMaster] // [coordSysKey] -> master
//       var seriesInvolved:   Bool
//   }
//
//   final class AxisInfo {                            // REFERENCE type (identity compared via `===`)
//       var axis: Axis
//       var key: String
//       var coordSys: CoordinateSystemMaster
//       var axisPointerModel: Model                  // Model<CommonAxisPointerOption>
//       var triggerTooltip: Bool
//       var triggerEmphasis: Bool
//       var involveSeries: Bool
//       var snap: Bool
//       var useHandle: Bool
//       var seriesModels: [SeriesModel]
//       var linkGroup: LinkGroup?
//       var seriesDataCount: Double?
//   }
//   final class LinkGroup { var axesInfo: [String: AxisInfo]; var mapper: Any? /* link callback */ }
//
//   public func makeKey(_ model: ComponentModel) -> String   // TASK 1 free function (modelHelper.swift)

import Foundation
import ZRenderKit

// ============================================================================
// DataByCoordSys / DataByAxis — the axis-tooltip payload tree (upstream axisTrigger.ts:39-71).
//   `DataByCoordSys` is a CLASS (reference) because upstream stores it in both `map` and `list` and then
//   mutates `.dataByAxis` through the `map` handle after pushing to `list`.
// ============================================================================

// upstream: interface DataIndex { seriesIndex; dataIndex; dataIndexInside }  (a BatchItem)
public struct AxisTriggerDataIndex: Equatable {
    public var seriesIndex: Double
    public var dataIndexInside: Double
    public var dataIndex: Double
    public init(seriesIndex: Double, dataIndexInside: Double, dataIndex: Double) {
        self.seriesIndex = seriesIndex
        self.dataIndexInside = dataIndexInside
        self.dataIndex = dataIndex
    }
}

// upstream: interface DataByAxis { value, axisIndex, axisDim, axisType, axisId, seriesDataIndices, valueLabelOpt }
public struct DataByAxis {
    public var value: Any?              // ScaleDataValue
    public var axisIndex: Double
    public var axisDim: String
    public var axisType: String
    public var axisId: String
    public var seriesDataIndices: [AxisTriggerDataIndex]
    // upstream valueLabelOpt: { precision, formatter } — prepared here, consumed on the view stage.
    public var valueLabelPrecision: Any?
    public var valueLabelFormatter: Any?
    public init(
        value: Any?, axisIndex: Double, axisDim: String, axisType: String, axisId: String,
        seriesDataIndices: [AxisTriggerDataIndex], valueLabelPrecision: Any?, valueLabelFormatter: Any?
    ) {
        self.value = value; self.axisIndex = axisIndex; self.axisDim = axisDim
        self.axisType = axisType; self.axisId = axisId; self.seriesDataIndices = seriesDataIndices
        self.valueLabelPrecision = valueLabelPrecision; self.valueLabelFormatter = valueLabelFormatter
    }
}

// upstream: interface DataByCoordSys { coordSysId, coordSysIndex, coordSysType, coordSysMainType, dataByAxis }
public final class DataByCoordSys {
    public var coordSysId: String
    public var coordSysIndex: Double
    public var coordSysType: String
    public var coordSysMainType: String
    public var dataByAxis: [DataByAxis]
    public init(
        coordSysId: String, coordSysIndex: Double, coordSysType: String,
        coordSysMainType: String, dataByAxis: [DataByAxis]
    ) {
        self.coordSysId = coordSysId; self.coordSysIndex = coordSysIndex
        self.coordSysType = coordSysType; self.coordSysMainType = coordSysMainType
        self.dataByAxis = dataByAxis
    }
}

// upstream: interface DataByCoordSysCollection { list: DataByCoordSys[]; map: Dictionary<DataByCoordSys> }
public final class DataByCoordSysCollection {
    public var list: [DataByCoordSys] = []
    public var map: [String: DataByCoordSys] = [:]
    public init() {}
}

// upstream: ShowValueMap = Dictionary<{ value; payloadBatch }>. Boxed so nested funcs mutate by reference.
final class ShowValueMapBox {
    struct Item { var value: Any?; var payloadBatch: [AxisTriggerDataIndex]? }
    var map: [String: Item] = [:]
}

// upstream: `outputPayload` — the event obj for echarts.connect (ModelFinderObject + axesInfo). Boxed so
//   `processOnAxis` can fill the sample seriesIndex/dataIndex (upstream `extend(outputFinder, payloadBatch[0])`).
public final class AxisTriggerOutput {
    public var seriesIndex: Double?
    public var dataIndex: Double?
    public var dataIndexInside: Double?
    public var axesInfo: [[String: Any]] = []
    public init() {}
}

// ============================================================================
// axisTrigger — upstream default export (axisTrigger.ts:113).
// ============================================================================
/**
 * Basic logic: check all axis, if they do not demand show/highlight,
 * then hide/downplay them.
 * @return content of event obj for echarts.connect.
 */
@discardableResult
public func axisTrigger(
    _ payload: Payload,
    _ ecModel: GlobalModel,
    _ api: ExtensionAPI
) -> AxisTriggerOutput {
    let currTrigger = payload.other["currTrigger"] as? String
    // upstream: let point = [payload.x, payload.y];  (may be undefined/NaN → illegalPoint)
    var point: [Double] = []
    if let x = atAsDouble(payload.other["x"]), let y = atAsDouble(payload.other["y"]) {
        point = [x, y]
    }
    let finder = payload
    // upstream: const dispatchAction = payload.dispatchAction || bind(api.dispatchAction, api);
    let dispatchAction: (Payload) -> Void =
        (payload.other["dispatchAction"] as? (Payload) -> Void) ?? { p in api.dispatchAction(p) }

    // upstream: const coordSysAxesInfo = (ecModel.getComponent('axisPointer')).coordSysAxesInfo;
    //   (TASK 1 types `AxisPointerModel.coordSysAxesInfo` as `Any?` — the volatile `CollectionResult`.)
    guard let apModel = ecModel.getComponent("axisPointer") as? AxisPointerModel,
          let coordSysAxesInfo = apModel.coordSysAxesInfo as? CollectionResult else {
        // Pending: See #6121. But we are not able to reproduce it yet.
        return AxisTriggerOutput()
    }

    // upstream: if (illegalPoint(point)) { point = findPointFromSeries({seriesIndex, dataIndex}, ecModel).point; }
    if illegalPoint(point) {
        point = findPointFromSeries(
            FindPointFinder(
                seriesIndex: atAsDouble(finder.other["seriesIndex"]),
                // Do not use dataIndexInside from other ec instance. FIXME: auto detect it?
                dataIndex: finder.other["dataIndex"]
            ),
            ecModel
        ).point
    }
    let isIllegalPoint = illegalPoint(point)

    // upstream: const inputAxesInfo = finder.axesInfo;
    let inputAxesInfo = finder.other["axesInfo"] as? [[String: Any]]

    let axesInfo = coordSysAxesInfo.axesInfo
    let shouldHide = currTrigger == "leave" || illegalPoint(point)
    let outputPayload = AxisTriggerOutput()

    let showValueMap = ShowValueMapBox()
    let dataByCoordSys = DataByCoordSysCollection()

    // ---- Process for triggered axes. (upstream axisTrigger.ts:164) --------------------------------
    for (coordSysKey, coordSys) in coordSysAxesInfo.coordSysMap {
        // If a point given, it must be contained by the coordinate system.
        let coordSysContainsPoint = isIllegalPoint || coordSys.containPoint(point)

        for (_, axisInfo) in (coordSysAxesInfo.coordSysAxesInfo[coordSysKey] ?? [:]) {
            let axis = axisInfo.axis
            let inputAxisInfo = findInputAxisInfo(inputAxesInfo, axisInfo)
            // If no inputAxesInfo, no axis is restricted.
            if !shouldHide && coordSysContainsPoint && (inputAxesInfo == nil || inputAxisInfo != nil) {
                var val: Any? = inputAxisInfo?["value"] ?? nil
                if val == nil && !isIllegalPoint {
                    val = axis.pointToData(point)
                }
                if val != nil {
                    processOnAxis(axisInfo, val, showValueMap, dataByCoordSys, false, outputPayload)
                }
            }
        }
    }

    // ---- Process for linked axes. (upstream axisTrigger.ts:183) ------------------------------------
    var linkTriggers: [String: Any?] = [:]
    for (tarKey, tarAxisInfo) in axesInfo {
        guard let linkGroup = tarAxisInfo.linkGroup else { continue }
        // If axis has been triggered in the previous stage, it should not be triggered by link.
        if showValueMap.map[tarKey] != nil { continue }
        for (srcKey, srcAxisInfo) in linkGroup.axesInfo {
            // If srcValItem exist, source axis is triggered, so link to target axis.
            if srcAxisInfo !== tarAxisInfo, let srcValItem = showValueMap.map[srcKey] {
                // upstream: let val = srcValItem.value;
                //           linkGroup.mapper && (val = tarAxisInfo.axis.scale.parse(linkGroup.mapper(...)));
                // PORT-TODO (DEFERRED): the `link.mapper` JS callback is not invoked; without a mapper the
                //   source value passes through unchanged (the common case). `makeMapperParam` deferred with it.
                let val: Any? = srcValItem.value
                linkTriggers[tarAxisInfo.key] = val
            }
        }
    }
    for (tarKey, val) in linkTriggers {
        if let ai = axesInfo[tarKey] {
            processOnAxis(ai, val, showValueMap, dataByCoordSys, true, outputPayload)
        }
    }

    updateModelActually(showValueMap, axesInfo, outputPayload)
    dispatchTooltipActually(dataByCoordSys, point, payload, dispatchAction)
    dispatchHighDownActually(axesInfo, dispatchAction, api)

    return outputPayload
}

// upstream: processOnAxis (axisTrigger.ts:213)
fileprivate func processOnAxis(
    _ axisInfo: AxisInfo,
    _ newValueIn: Any?,
    _ showValueMap: ShowValueMapBox,
    _ dataByCoordSys: DataByCoordSysCollection,
    _ noSnap: Bool,
    _ outputFinder: AxisTriggerOutput
) {
    let axis = axisInfo.axis

    // upstream: if (axis.scale.isBlank() || !axis.containData(newValue)) return;
    if axis.scale.isBlank() || !(newValueIn.map { axis.containData($0) } ?? false) {
        return
    }

    if !axisInfo.involveSeries {
        showPointer(showValueMap, axisInfo, newValueIn, nil)
        return
    }

    // Heavy calculation. So put it after axis.containData checking.
    // (buildPayloadsBySeries needs a numeric axis value — `pointToData`/link values are numeric.)
    guard let numValue = atAsDouble(newValueIn) else {
        showPointer(showValueMap, axisInfo, newValueIn, nil)   // defensive: non-numeric → pointer only
        return
    }
    let payloadInfo = buildPayloadsBySeries(numValue, axisInfo)
    let payloadBatch = payloadInfo.payloadBatch
    let snapToValue = payloadInfo.snapToValue

    // Fill content of event obj for echarts.connect (upstream: extend(outputFinder, payloadBatch[0])).
    if let first = payloadBatch.first, outputFinder.seriesIndex == nil {
        outputFinder.seriesIndex = first.seriesIndex
        outputFinder.dataIndex = first.dataIndex
        outputFinder.dataIndexInside = first.dataIndexInside
    }

    var newValue: Any? = newValueIn
    // If no linkSource input, this process is for collecting link target, where snap should not be accepted.
    if !noSnap && axisInfo.snap {
        if axis.containData(snapToValue) {   // snapToValue is a finite Double (non-null)
            newValue = snapToValue
        }
    }

    showPointer(showValueMap, axisInfo, newValue, payloadBatch)
    // Tooltip should always be snapToValue, otherwise there will be an incorrect
    // "axis value ~ series value" mapping displayed in tooltip.
    showTooltip(dataByCoordSys, axisInfo, payloadBatch, snapToValue)
}

// upstream: buildPayloadsBySeries (axisTrigger.ts:259)
fileprivate func buildPayloadsBySeries(_ value: Double, _ axisInfo: AxisInfo)
    -> (payloadBatch: [AxisTriggerDataIndex], snapToValue: Double)
{
    let axis = axisInfo.axis
    let dim = axis.dim
    var snapToValue = value
    var payloadBatch: [AxisTriggerDataIndex] = []
    var minDist = Double.greatestFiniteMagnitude
    var minDiff: Double = -1

    for series in axisInfo.seriesModels {
        let data = series.getData()
        let dataDim = data.mapDimensionsAll(dim)
        let dataIndices: [Double]
        let seriesNestestValue: Any?

        // upstream: if (series.getAxisTooltipData) { ... } else { indicesOfNearest ... }
        //   PORT-TODO (DEFERRED): `SeriesModel.getAxisTooltipData` (candlestick/boxplot) not ported;
        //   only the default `indicesOfNearest` snap path is taken.
        dataIndices = series.indicesOfNearest(
            dim,
            dataDim.first ?? "",
            value,
            // Add a threshold to avoid finding the wrong dataIndex when data length is not same.
            axis.type == "category" ? 0.5 : nil
        )
        if dataIndices.isEmpty { continue }
        seriesNestestValue = data.get(dataDim.first ?? "", Int(dataIndices[0]))

        // upstream: if (!isNullableNumberFinite(seriesNestestValue)) return; (continue to next series)
        let nearestNum = atAsDouble(seriesNestestValue)
        if !number.isNullableNumberFinite(nearestNum) { continue }
        let nearest = nearestNum!

        let diff = value - nearest
        let dist = abs(diff)
        // Consider category case.
        if dist <= minDist {
            if dist < minDist || (diff >= 0 && minDiff < 0) {
                minDist = dist
                minDiff = diff
                snapToValue = nearest
                payloadBatch.removeAll()
            }
            for dataIndex in dataIndices {
                payloadBatch.append(AxisTriggerDataIndex(
                    seriesIndex: series.seriesIndex,
                    dataIndexInside: dataIndex,
                    dataIndex: Double(data.getRawIndex(Int(dataIndex)))
                ))
            }
        }
    }

    return (payloadBatch, snapToValue)
}

// upstream: showPointer (axisTrigger.ts:323)
fileprivate func showPointer(
    _ showValueMap: ShowValueMapBox,
    _ axisInfo: AxisInfo,
    _ value: Any?,
    _ payloadBatch: [AxisTriggerDataIndex]?
) {
    showValueMap.map[axisInfo.key] = ShowValueMapBox.Item(value: value, payloadBatch: payloadBatch)
}

// upstream: showTooltip (axisTrigger.ts:335)
fileprivate func showTooltip(
    _ dataByCoordSys: DataByCoordSysCollection,
    _ axisInfo: AxisInfo,
    _ payloadBatch: [AxisTriggerDataIndex],
    _ value: Any?
) {
    let axis = axisInfo.axis
    let axisModel = axis.model
    let axisPointerModel = axisInfo.axisPointerModel

    // If no data, do not create anything in dataByCoordSys, whose length is used to judge dispatch.
    if !axisInfo.triggerTooltip || payloadBatch.isEmpty {
        return
    }

    guard let coordSysModel = axisInfo.coordSys.model else { return }
    let coordSysKey = makeKey(coordSysModel)   // TASK 1 free function (modelHelper.swift)
    let coordSysItem: DataByCoordSys
    if let existing = dataByCoordSys.map[coordSysKey] {
        coordSysItem = existing
    }
    else {
        coordSysItem = DataByCoordSys(
            coordSysId: coordSysModel.id,
            coordSysIndex: coordSysModel.componentIndex,
            coordSysType: coordSysModel.type,
            coordSysMainType: coordSysModel.mainType,
            dataByAxis: []
        )
        dataByCoordSys.map[coordSysKey] = coordSysItem
        dataByCoordSys.list.append(coordSysItem)
    }

    coordSysItem.dataByAxis.append(DataByAxis(
        value: value,
        axisIndex: axisModel!.componentIndex,
        axisDim: axis.dim,
        axisType: axisModel!.type,
        axisId: axisModel!.id,
        seriesDataIndices: payloadBatch,     // upstream payloadBatch.slice() — arrays are value types here
        // Caution: viewHelper.getValueLabel is on the "view stage"; prepare params here (volatile model).
        valueLabelPrecision: axisPointerModel.get(["label", "precision"]),
        valueLabelFormatter: axisPointerModel.get(["label", "formatter"])
    ))
}

// upstream: updateModelActually (axisTrigger.ts:384)
//   Sets each axisPointer model's status/value/seriesDataIndices — the crosshair STATUS.
//   PORT-TODO (Phase 36): the DRAW of that crosshair is the axisPointer VIEW render; this only computes
//   the status. When the axisPointer view lands, its `render` reads these `option` fields.
fileprivate func updateModelActually(
    _ showValueMap: ShowValueMapBox,
    _ axesInfo: [String: AxisInfo],
    _ outputPayload: AxisTriggerOutput
) {
    var outputAxesInfo: [[String: Any]] = []
    // Basic logic: If no 'show' required, 'hide' this axisPointer.
    for (key, axisInfo) in axesInfo {
        var option = (axisInfo.axisPointerModel.option as? [String: Any]) ?? [:]
        let valItem = showValueMap.map[key]

        if let valItem = valItem {
            if !axisInfo.useHandle { option["status"] = "show" }
            if let v = valItem.value { option["value"] = v }
            // For label formatter param and highlight.
            option["seriesDataIndices"] = (valItem.payloadBatch ?? [])
        }
        else {
            // When always show (e.g., handle used), remain original value and status. If hide, value
            // still need to be set (consider click legend to toggle axis blank).
            if !axisInfo.useHandle { option["status"] = "hide" }
        }
        axisInfo.axisPointerModel.option = option

        // If status is 'hide', should be no info in payload.
        if (option["status"] as? String) == "show" {
            var entry: [String: Any] = [
                "axisDim": axisInfo.axis.dim,
                "axisIndex": axisInfo.axis.model!.componentIndex
            ]
            if let v = option["value"] { entry["value"] = v }
            outputAxesInfo.append(entry)
        }
    }
    outputPayload.axesInfo = outputAxesInfo
}

// upstream: dispatchTooltipActually (axisTrigger.ts:418)
fileprivate func dispatchTooltipActually(
    _ dataByCoordSys: DataByCoordSysCollection,
    _ point: [Double],
    _ payload: Payload,
    _ dispatchAction: (Payload) -> Void
) {
    // Basic logic: If no showTip required, hideTip will be dispatched.
    if illegalPoint(point) || dataByCoordSys.list.isEmpty {
        dispatchAction(Payload(type: "hideTip"))
        return
    }

    // In most cases only one axis (or even one series) is used. Put the first seriesIndex/dataIndex of the
    // first axis on the payload so consumers can fetch payload.seriesIndex/dataIndex directly.
    let sampleItem = dataByCoordSys.list.first?.dataByAxis.first?.seriesDataIndices.first

    var p = Payload(type: "showTip")
    p.escapeConnect = true
    p.other["x"] = point[0]
    p.other["y"] = point[1]
    if let v = payload.other["tooltipOption"] { p.other["tooltipOption"] = v }
    if let v = payload.other["position"] { p.other["position"] = v }
    if let s = sampleItem {
        p.other["dataIndexInside"] = s.dataIndexInside
        p.other["dataIndex"] = s.dataIndex
        p.other["seriesIndex"] = s.seriesIndex
    }
    // The trigger:"axis" payload — consumed by TooltipView._showAxisTooltip (Phase 35 / parallel).
    p.other["dataByCoordSys"] = dataByCoordSys.list
    dispatchAction(p)
}

// upstream: dispatchHighDownActually (axisTrigger.ts:450). Keyed on `api` (upstream on `api.getZr()` —
//   deviation: ExtensionAPI has no getZr() yet).
final class AxisPointerHighlightStore {
    var lastHighlights: [String: AxisTriggerDataIndex] = [:]
    init() {}
}
private let axisPointerHighlightInner: (ExtensionAPI) -> AxisPointerHighlightStore =
    model.makeInner { AxisPointerHighlightStore() }

fileprivate func dispatchHighDownActually(
    _ axesInfo: [String: AxisInfo],
    _ dispatchAction: (Payload) -> Void,
    _ api: ExtensionAPI
) {
    // FIXME highlight status modification should be a stage of main process? (setOption/legend conflicts)
    let store = axisPointerHighlightInner(api)
    let lastHighlights = store.lastHighlights
    var newHighlights: [String: AxisTriggerDataIndex] = [:]

    // Update highlight/downplay status per axisPointer model. Build a hash map, removing duplicates.
    for (_, axisInfo) in axesInfo {
        let option = (axisInfo.axisPointerModel.option as? [String: Any]) ?? [:]
        if (option["status"] as? String) == "show" && axisInfo.triggerEmphasis {
            if let sdis = option["seriesDataIndices"] as? [AxisTriggerDataIndex] {
                for batchItem in sdis {
                    newHighlights["\(Int(batchItem.seriesIndex))|\(Int(batchItem.dataIndex))"] = batchItem
                }
            }
        }
    }
    store.lastHighlights = newHighlights

    // Diff.
    var toHighlight: [PayloadItem] = []
    var toDownplay: [PayloadItem] = []
    for (key, batchItem) in lastHighlights {
        if newHighlights[key] == nil { toDownplay.append(makeHighDownItem(batchItem)) }
    }
    for (key, batchItem) in newHighlights {
        if lastHighlights[key] == nil { toHighlight.append(makeHighDownItem(batchItem)) }
    }

    if !toDownplay.isEmpty {
        var p = Payload(type: "downplay")
        p.escapeConnect = true
        p.other["notBlur"] = true   // Not blur others when highlight in axisPointer.
        p.batch = toDownplay
        api.dispatchAction(p)
    }
    if !toHighlight.isEmpty {
        var p = Payload(type: "highlight")
        p.escapeConnect = true
        p.other["notBlur"] = true
        p.batch = toHighlight
        api.dispatchAction(p)
    }
}

// upstream makeHighDownItem (nested in dispatchHighDownActually): drop dataIndexInside; keep seriesIndex/dataIndex.
private func makeHighDownItem(_ batchItem: AxisTriggerDataIndex) -> PayloadItem {
    var item = PayloadItem()
    item.other["seriesIndex"] = batchItem.seriesIndex
    item.other["dataIndex"] = batchItem.dataIndex
    return item
}

// upstream: findInputAxisInfo (axisTrigger.ts:507)
fileprivate func findInputAxisInfo(
    _ inputAxesInfo: [[String: Any]]?,
    _ axisInfo: AxisInfo
) -> [String: Any]? {
    for inputAxisInfo in (inputAxesInfo ?? []) {
        if axisInfo.axis.dim == (inputAxisInfo["axisDim"] as? String)
            && axisInfo.axis.model!.componentIndex == atAsDouble(inputAxisInfo["axisIndex"]) {
            return inputAxisInfo
        }
    }
    return nil
}

// upstream: illegalPoint (axisTrigger.ts:537) — null/NaN x or y (here an empty/short array is illegal too).
fileprivate func illegalPoint(_ point: [Double]?) -> Bool {
    guard let point = point, point.count >= 2 else { return true }
    return point[0].isNaN || point[1].isNaN
}

// atAsDouble — coerce a JS-number-ish option/payload value (Int or Double) to Double.
//   (Int-vs-Double option-read trap: small numbers box as `Int`.)
private func atAsDouble(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    return nil
}
