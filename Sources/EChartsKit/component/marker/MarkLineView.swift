// Ported from echarts/src/component/marker/MarkLineView.ts — keep in sync with upstream
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
// import SeriesData from '../../data/SeriesData';                    -> EChartsKit `SeriesData`
// import * as numberUtil from '../../util/number';                   -> EChartsKit `number`
// import * as markerHelper from './markerHelper';                    -> sibling markerHelper.swift
// import LineDraw from '../../chart/helper/LineDraw';
//   -> PORT-NOTE (deferred): the real `chart/helper/LineDraw` (+ `chart/helper/Line`, with enter/leave
//      animation + emphasis/blur states) is not ported. A STATIC-SUBSET stand-in `LineDraw` is defined at the
//      bottom of this file: it draws the from→to Polyline with the full `lineStyle` (dashed/width/
//      opacity), the from/to end symbols (circle+arrow, tangent-rotated per Line.ts), and the default
//      value label. Diff/enter-leave animation + emphasis are deferred.
// import MarkerView from './MarkerView';                             -> sibling MarkerView.swift
// import {getStackedDimension} from '../../data/helper/dataStackHelper'; -> EChartsKit `getStackedDimension`
// import { CoordinateSystem, isCoordinateSystemType } from '../../coord/CoordinateSystem';
//   -> EChartsKit `CoordinateSystem` / `isCoordinateSystemType`
// import MarkLineModel, {...} from './MarkLineModel';                -> sibling MarkLineModel.swift
// import { ScaleDataValue, ColorString } from '../../util/types';    -> util/types.swift
// import SeriesModel from '../../model/Series';                      -> EChartsKit `SeriesModel`
// import { getECData } from '../../util/innerStore';
//   -> PORT-NOTE: util/innerStore is ported (util/innerStore.swift, getECData); the ECData host-model
//      tagging for tooltip is still deferred (see below).
// import ExtensionAPI from '../../core/ExtensionAPI';                -> EChartsKit `ExtensionAPI`
// import Cartesian2D from '../../coord/cartesian/Cartesian2D';       -> EChartsKit `Cartesian2D`
// import GlobalModel from '../../model/Global';                      -> EChartsKit `GlobalModel`
// import MarkerModel from './MarkerModel';                           -> sibling MarkerModel.swift
// import { isArray, retrieve, retrieve2, clone, extend, logError, merge, map, curry, filter, HashMap,
//          isNumber } from 'zrender/src/core/util';                 -> ZRenderKit `util.*`
// import { makeInner } from '../../util/model';                      -> EChartsKit `model.makeInner`
// import { LineDataVisual } from '../../visual/commonVisualTypes';   -> util/types
// import { getVisualFromData } from '../../visual/helper';
//   -> PORT-NOTE (deferred): requires visual/helper.getVisualFromData (not ported); approximated by the local `getVisualFromData` below.
// import Axis2D from '../../coord/cartesian/Axis2D';                 -> EChartsKit `Axis2D`
// import SeriesDimensionDefine from '../../data/SeriesDimensionDefine'; -> EChartsKit `SeriesDimensionDefine`

// Item option for configuring line and each end of symbol.
// Line option. be merged from configuration of two ends.
// type MarkLineMergedItemOption = MarkLine2DDataItemOption[number];
//   -> the per-end option; modeled as `MarkerPositionOption` (position-only, see MarkerModel.swift).
//   PORT-NOTE: item-level style/label/symbol options in the raw `[String: Any]` data item are not
//     carried onto `MarkerPositionOption`; where they are needed they are re-read via `getItemModel`
//     (which falls back to the mark-line model option).

// const inner = makeInner<{ from: SeriesData<MarkLineModel>, to: SeriesData<MarkLineModel> }, MarkLineModel>();
// PORT-NOTE: `makeInner` needs an `AnyObject` value; the `{ from, to }` bag is wrapped in a reference.
final class MarkLineInner {
    var from: SeriesData?
    var to: SeriesData?
    init() {}
}
private let inner: (MarkLineModel) -> MarkLineInner = model.makeInner { MarkLineInner() }

// const markLineTransform = function (seriesModel, coordSys, mlModel, item) { ... }
private func markLineTransform(
    _ seriesModel: SeriesModel,
    _ coordSys: CoordinateSystem?,
    _ mlModel: MarkLineModel,
    _ item: Any?
) -> [MarkerPositionOption?] {
    let data = seriesModel.getData()

    var itemArray: [MarkerPositionOption?]
    if !util.isArray(item) {
        // Special type markLine like 'min', 'max', 'average', 'median'
        let itemMpo = markerPositionOption(from: item) ?? MarkerPositionOption()
        let mlType = itemMpo.type
        if
            mlType == .min || mlType == .max || mlType == .average || mlType == .median
            // In case
            // data: [{
            //   yAxis: 10
            // }]
            || (itemMpo.xAxis != nil || itemMpo.yAxis != nil)
        {

            var valueAxis: Axis?
            var value: Any?

            if itemMpo.yAxis != nil || itemMpo.xAxis != nil {
                valueAxis = coordSys?.getAxis(itemMpo.yAxis != nil ? "y" : "x")
                value = util.retrieve(itemMpo.yAxis, itemMpo.xAxis)
            }
            else {
                let axisInfo = markerHelper.getAxisInfo(itemMpo, data, coordSys!, seriesModel)
                valueAxis = axisInfo.valueAxis
                let valueDataDim = getStackedDimension(data, axisInfo.valueDataDim ?? "")
                value = markerHelper.numCalculate(data, valueDataDim, mlType!)
            }
            let valueIndex = valueAxis?.dim == "x" ? 0 : 1
            let baseIndex = 1 - valueIndex

            // Normized to 2d data with start and end point
            var mlFrom = util.clone(itemMpo)   // clone(item)
            var mlTo = MarkerPositionOption()   // { coord: [] }

            mlFrom.type = nil

            // upstream builds sparse arrays via index assignment; pre-size to 2 (cartesian/polar).
            var fromCoord: [Any?] = [nil, nil]
            var toCoord: [Any?] = [nil, nil]
            fromCoord[baseIndex] = -Double.infinity
            toCoord[baseIndex] = Double.infinity

            let precision = (mlModel.get("precision") as? Double) ?? 0
            if precision >= 0 && util.isNumber(value) {
                // value = +value.toFixed(Math.min(precision, 20));
                let v = (value as? Double) ?? Double.nan
                value = toFixedNumber(v, Int(Swift.min(precision, 20)))
            }

            fromCoord[valueIndex] = value
            toCoord[valueIndex] = value
            mlFrom.coord = fromCoord
            mlTo.coord = toCoord

            // { type: mlType, valueIndex: item.valueIndex, value: value }
            var extra = MarkerPositionOption()
            extra.type = mlType
            // Force to use the value of calculated value.
            extra.valueIndex = itemMpo.valueIndex
            extra.value = value

            itemArray = [mlFrom, mlTo, extra]
        }
        else {
            // Invalid data
            if __DEV__ {
                util.logError("Invalid markLine data.")
            }
            itemArray = []
        }
    }
    else {
        // item is the 2D pair [start, end]
        itemArray = ((item as? [Any?]) ?? []).map { markerPositionOption(from: $0) }
    }

    // JS `itemArray[i]` is `undefined` when absent (invalid data => `[]`); replicate via bounds check.
    let a0: MarkerPositionOption? = itemArray.count > 0 ? itemArray[0] : nil
    let a1: MarkerPositionOption? = itemArray.count > 1 ? itemArray[1] : nil
    let a2: MarkerPositionOption? = itemArray.count > 2 ? itemArray[2] : nil

    let n0 = markerHelper.dataTransform(seriesModel, a0)
    let n1 = markerHelper.dataTransform(seriesModel, a1)
    var n2 = a2 ?? MarkerPositionOption()   // extend({}, itemArray[2])

    // Avoid line data type is extended by from(to) data type
    // normalizedItem[2].type = normalizedItem[2].type || null;  (no-op for a value struct)

    // Merge from option and to option into line option
    mergePositionOption(&n2, n0)
    mergePositionOption(&n2, n1)

    return [n0, n1, n2]
}

// function isInfinity(val) { return !isNaN(val as number) && !isFinite(val as number); }
private func isInfinity(_ val: Any?) -> Bool {
    guard let d = toNum(val) else { return false }   // non-numeric => isNaN true => false
    return !d.isNaN && !d.isFinite
}

// If a markLine has one dim
// function ifMarkLineHasOnlyDim(dimIndex, fromCoord, toCoord, coordSys)
private func ifMarkLineHasOnlyDim(
    _ dimIndex: Int,
    _ fromCoord: [Any?],
    _ toCoord: [Any?],
    _ coordSys: CoordinateSystem
) -> Bool {
    let otherDimIndex = 1 - dimIndex
    let dimName = coordSys.dimensions[dimIndex]
    // isInfinity(fromCoord[otherDimIndex]) && isInfinity(toCoord[otherDimIndex])
    //   && fromCoord[dimIndex] === toCoord[dimIndex]
    //   && coordSys.getAxis(dimName).containData(fromCoord[dimIndex])
    return isInfinity(coordAt(fromCoord, otherDimIndex)) && isInfinity(coordAt(toCoord, otherDimIndex))
        && looseEquals(coordAt(fromCoord, dimIndex), coordAt(toCoord, dimIndex))
        && (coordSys.getAxis(dimName)?.containData((coordAt(fromCoord, dimIndex) as Any)) ?? false)
}

// function markLineFilter(coordSys, item)
private func markLineFilter(
    _ coordSys: CoordinateSystem?,
    _ item: [MarkerPositionOption?]
) -> Bool {
    if coordSys?.type == "cartesian2d" {
        let fromCoord = (item.count > 0 ? item[0] : nil)?.coord
        let toCoord = (item.count > 1 ? item[1] : nil)?.coord
        // In case
        // {
        //  markLine: {
        //    data: [{ yAxis: 2 }]
        //  }
        // }
        if
            let fromCoord = fromCoord, let toCoord = toCoord,
            (ifMarkLineHasOnlyDim(1, fromCoord, toCoord, coordSys!)
            || ifMarkLineHasOnlyDim(0, fromCoord, toCoord, coordSys!))
        {
            return true
        }
    }
    return markerHelper.dataFilter(coordSys, (item.count > 0 ? item[0] : nil) ?? MarkerPositionOption())
        && markerHelper.dataFilter(coordSys, (item.count > 1 ? item[1] : nil) ?? MarkerPositionOption())
}

// function updateSingleMarkerEndLayout(data, idx, isFrom, seriesModel, api)
private func updateSingleMarkerEndLayout(
    _ data: SeriesData,
    _ idx: Int,
    _ isFrom: Bool,
    _ seriesModel: SeriesModel,
    _ api: ExtensionAPI
) {
    let coordSys = seriesModel.coordinateSystem as? CoordinateSystem
    let itemModel = data.getItemModel(idx)

    var point: [Double]?
    let xPx = number.parsePercent(itemModel.get("x"), api.getWidth())
    let yPx = number.parsePercent(itemModel.get("y"), api.getHeight())
    if !xPx.isNaN && !yPx.isNaN {
        point = [xPx, yPx]
    }
    else {
        let dims = coordSys?.dimensions ?? []
        // Chart like bar may have there own marker positioning logic
        // if (seriesModel.getMarkerPosition) { point = seriesModel.getMarkerPosition(...); }
        //   PORT-NOTE: `getMarkerPosition` is duck-typed on the series in upstream; only
        //   `BaseBarSeriesModel` declares it in the port (mirrors MarkPointView). Feature-detect
        //   via `as? BaseBarSeriesModel`; other series with custom positioning add it when they land.
        if let barSeries = seriesModel as? BaseBarSeriesModel {
            // Use the getMarkerPosition
            point = barSeries.getMarkerPosition(
                data.getValues(data.dimensions, idx) as [ScaleDataValue]
            )
        }
        else {
            let x = data.get(dims[0], idx)
            let y = data.get(dims[1], idx)
            point = coordSys?.dataToPoint([(x as Any), (y as Any)], nil)
        }

        // Expand line to the edge of grid if value on one axis is Inifnity
        // In case
        //  markLine: {
        //    data: [{
        //      yAxis: 2
        //      // or
        //      type: 'average'
        //    }]
        //  }
        if let cs = coordSys, isCoordinateSystemType(cs, "cartesian2d"), let cart = cs as? Cartesian2D {
            // TODO: TYPE ts@4.1 may still infer it as Axis instead of Axis2D.
            let xAxis = cart.getAxis("x")
            let yAxis = cart.getAxis("y")
            if isInfinity(data.get(dims[0], idx)) {
                point?[0] = xAxis!.toGlobalCoord(xAxis!.getExtent()[isFrom ? 0 : 1])
            }
            else if isInfinity(data.get(dims[1], idx)) {
                point?[1] = yAxis!.toGlobalCoord(yAxis!.getExtent()[isFrom ? 0 : 1])
            }
        }

        // Use x, y if has any
        if !xPx.isNaN {
            point?[0] = xPx
        }
        if !yPx.isNaN {
            point?[1] = yPx
        }
    }

    data.setItemLayout(idx, point)
}

// class MarkLineView extends MarkerView
final class MarkLineView: MarkerView {

    // static type = 'markLine';
    override class var type: String { return "markLine" }
    // type = MarkLineView.type;  (inherited computed `type` mirrors the static)

    // markerGroupMap: HashMap<LineDraw>;
    //   The base `MarkerView` already stores `markerGroupMap: HashMap<MarkerDraw>`. `LineDraw`
    //   conforms to `MarkerDraw`; values are narrowed via `as? LineDraw` at the call sites below
    //   (Swift generics are invariant, so the map is not re-typed).

    // updateTransform(markLineModel, ecModel, api)
    func updateTransform(_ markLineModel: MarkLineModel, _ ecModel: GlobalModel, _ api: ExtensionAPI) {
        ecModel.eachSeries { [self] seriesModel, _ in
            let mlModel = MarkerModel.getMarkerModelFromSeries(seriesModel, "markLine") as? MarkLineModel
            if let mlModel = mlModel {
                let mlData = mlModel.getData()
                let fromData = inner(mlModel).from
                let toData = inner(mlModel).to
                // Update visual and layout of from symbol and to symbol
                fromData?.each { args in
                    let idx = Int(args[0] as! Double)
                    updateSingleMarkerEndLayout(fromData!, idx, true, seriesModel, api)
                    updateSingleMarkerEndLayout(toData!, idx, false, seriesModel, api)
                }
                // Update layout of line
                mlData.each { args in
                    let idx = Int(args[0] as! Double)
                    mlData.setItemLayout(idx, [
                        fromData!.getItemLayout(idx),
                        toData!.getItemLayout(idx)
                    ])
                }

                (self.markerGroupMap.get(seriesModel.id) as? LineDraw)?.updateLayout()
            }
        }
    }

    // renderSeries(seriesModel, mlModel, ecModel, api)
    override func renderSeries(
        _ seriesModel: SeriesModel,
        _ markerModel: MarkerModel,
        _ ecModel: GlobalModel,
        _ api: ExtensionAPI
    ) {
        // upstream param is `mlModel: MarkLineModel`; the base signature types it `MarkerModel`.
        let mlModel = markerModel as! MarkLineModel

        let coordSys = seriesModel.coordinateSystem as? CoordinateSystem
        let seriesId = seriesModel.id
        let seriesData = seriesModel.getData()

        let lineDrawMap = self.markerGroupMap!
        let lineDraw: LineDraw
        if let existing = lineDrawMap.get(seriesId) as? LineDraw {
            lineDraw = existing
        }
        else {
            lineDraw = LineDraw()
            _ = lineDrawMap.set(seriesId, lineDraw)
        }
        _ = self.group.add(lineDraw.group)

        let mlData = createList(coordSys, seriesModel, mlModel)

        let fromData = mlData.from
        let toData = mlData.to
        let lineData = mlData.line

        inner(mlModel).from = fromData
        inner(mlModel).to = toData
        // Line data for tooltip and formatter
        mlModel.setData(lineData)

        // TODO
        // Functionally, `symbolSize` & `symbolOffset` can also be 2D array now.
        // But the related logic and type definition are not finished yet.
        // Finish it if required
        var symbolType = mlModel.get("symbol")
        var symbolSize = mlModel.get("symbolSize")
        var symbolRotate = mlModel.get("symbolRotate")
        var symbolOffset = mlModel.get("symbolOffset")
        // TODO: support callback function like markPoint
        if !util.isArray(symbolType) {
            symbolType = [symbolType, symbolType]
        }
        if !util.isArray(symbolSize) {
            symbolSize = [symbolSize, symbolSize]
        }
        if !util.isArray(symbolRotate) {
            symbolRotate = [symbolRotate, symbolRotate]
        }
        if !util.isArray(symbolOffset) {
            symbolOffset = [symbolOffset, symbolOffset]
        }
        let symbolTypeArr = (symbolType as? [Any?]) ?? [nil, nil]
        let symbolSizeArr = (symbolSize as? [Any?]) ?? [nil, nil]
        let symbolRotateArr = (symbolRotate as? [Any?]) ?? [nil, nil]
        let symbolOffsetArr = (symbolOffset as? [Any?]) ?? [nil, nil]

        // function updateDataVisualAndLayout(data, idx, isFrom)
        func updateDataVisualAndLayout(_ data: SeriesData, _ idx: Int, _ isFrom: Bool) {
            let itemModel = data.getItemModel(idx)

            updateSingleMarkerEndLayout(data, idx, isFrom, seriesModel, api)

            var style = itemModel.getModel("itemStyle").getItemStyle()
            if style["fill"] == nil {
                style["fill"] = getVisualFromData(seriesData, "color")   // as ColorString
            }

            data.setItemVisual(idx, [
                "symbolKeepAspect": itemModel.get("symbolKeepAspect") as Any,
                // `0` should be considered as a valid value, so use `retrieve2` instead of `||`
                "symbolOffset": retrieve2Any(
                    itemModel.get("symbolOffset", true),
                    symbolOffsetArr[isFrom ? 0 : 1]
                ) as Any,
                "symbolRotate": retrieve2Any(
                    itemModel.get("symbolRotate", true),
                    symbolRotateArr[isFrom ? 0 : 1]
                ) as Any,
                // TODO: when 2d array is supported, it should ignore parent
                "symbolSize": retrieve2Any(
                    itemModel.get("symbolSize"),
                    symbolSizeArr[isFrom ? 0 : 1]
                ) as Any,
                "symbol": retrieve2Any(
                    itemModel.get("symbol", true),
                    symbolTypeArr[isFrom ? 0 : 1]
                ) as Any,
                "style": style
            ])
        }

        // Update visual and layout of from symbol and to symbol
        fromData.each { args in
            let idx = Int(args[0] as! Double)
            updateDataVisualAndLayout(fromData, idx, true)
            updateDataVisualAndLayout(toData, idx, false)
        }

        // Update visual and layout of line
        lineData.each { args in
            let idx = Int(args[0] as! Double)
            let itemModel = lineData.getItemModel(idx)
            var lineStyle = itemModel.getModel("lineStyle").getLineStyle()
            // lineData.setItemVisual(idx, { color: lineColor || fromData.getItemVisual(idx, 'color') });
            lineData.setItemLayout(idx, [
                fromData.getItemLayout(idx),
                toData.getItemLayout(idx)
            ])
            let z2 = itemModel.get("z2")

            if lineStyle["stroke"] == nil {
                lineStyle["stroke"] = (fromData.getItemVisual(idx, "style") as? [String: Any])?["fill"]
            }

            lineData.setItemVisual(idx, [
                "z2": retrieve2Any(z2, 0.0) as Any,
                "fromSymbolKeepAspect": fromData.getItemVisual(idx, "symbolKeepAspect") as Any,
                "fromSymbolOffset": fromData.getItemVisual(idx, "symbolOffset") as Any,
                "fromSymbolRotate": fromData.getItemVisual(idx, "symbolRotate") as Any,
                "fromSymbolSize": fromData.getItemVisual(idx, "symbolSize") as Any,
                "fromSymbol": fromData.getItemVisual(idx, "symbol") as Any,
                "toSymbolKeepAspect": toData.getItemVisual(idx, "symbolKeepAspect") as Any,
                "toSymbolOffset": toData.getItemVisual(idx, "symbolOffset") as Any,
                "toSymbolRotate": toData.getItemVisual(idx, "symbolRotate") as Any,
                "toSymbolSize": toData.getItemVisual(idx, "symbolSize") as Any,
                "toSymbol": toData.getItemVisual(idx, "symbol") as Any,
                "style": lineStyle
            ])
        }

        lineDraw.updateData(lineData)

        // Set host model for tooltip
        // FIXME
        // mlData.line.eachItemGraphicEl(function (el) { getECData(el).dataModel = mlModel; ... });
        // PORT-NOTE: `MarkerModel` now conforms to `DataFormatMixin`/`DataHost` (MarkerModel.swift); the
        //   only remaining piece for `ECData.dataModel` (typed `DataModel?`) is the `DataModel` conformance
        //   — added as a retroactive extension at the bottom of this file (MarkLineModel: DataModel). The
        //   child callback returns `Void` upstream (falsy → never stops descending); mapped to the `Group`
        //   traverse overload with a `false`-returning closure.
        lineData.eachItemGraphicEl { el, _ in
            innerStore.getECData(el).dataModel = mlModel

            if let group = el as? Group {
                group.traverse { child in
                    innerStore.getECData(child).dataModel = mlModel
                    return false
                }
            }
        }

        self.markKeep(lineDraw)

        // lineDraw.group.silent = mlModel.get('silent') || seriesModel.get('silent');
        lineDraw.group.silent = isTruthy(mlModel.get("silent")) || isTruthy((seriesModel as Model).get("silent"))
    }
}

// function createList(coordSys, seriesModel, mlModel)
private func createList(
    _ coordSys: CoordinateSystem?,
    _ seriesModel: SeriesModel,
    _ mlModel: MarkLineModel
) -> (from: SeriesData, to: SeriesData, line: SeriesData) {

    var coordDimsInfos: [SeriesDimensionDefine]
    if let coordSys = coordSys {
        coordDimsInfos = util.map(coordSys.dimensions) { coordDim, _ in
            let data = seriesModel.getData()
            // const info = data.getDimensionInfo(data.mapDimension(coordDim)) || {};
            let md = data.mapDimension(coordDim)
            let base: SeriesDimensionDefine
            if let md = md {
                // POTENTIAL-BUG: upstream's `|| {}` fallback when the dim info is genuinely absent is not
                //   reproduced (SeriesData.getDimensionInfo force-unwraps internally); a truly absent dim
                //   info would trap instead of yielding an empty define. `md` resolves in practice for markLine.
                base = SeriesDimensionDefine(data.getDimensionInfo(md))
            }
            else {
                base = SeriesDimensionDefine()
            }
            // In map series data don't have lng and lat dimension. Fallback to same with coordSys
            // extend(extend({}, info), { name: coordDim, ordinalMeta: null });
            base.name = coordDim
            // DON'T use ordinalMeta to parse and collect ordinal.
            base.ordinalMeta = nil
            return base
        }
    }
    else {
        let d = SeriesDimensionDefine()
        d.name = "value"
        d.type = .float
        coordDimsInfos = [d]
    }

    let fromData = SeriesData(coordDimsInfos as [Any], mlModel)
    let toData = SeriesData(coordDimsInfos as [Any], mlModel)
    // No dimensions
    let lineData = SeriesData([] as [Any], mlModel)

    // let optData = map(mlModel.get('data'), curry(markLineTransform, seriesModel, coordSys, mlModel));
    var optData = util.map((mlModel.get("data") as? [Any?]) ?? []) { item, _ in
        markLineTransform(seriesModel, coordSys, mlModel, item)
    }
    if coordSys != nil {
        optData = util.filter(optData) { item, _ in
            markLineFilter(coordSys, item)
        }
    }

    let markerGetter = markerHelper.createMarkerDimValueGetter(coordSys != nil, coordDimsInfos)
    // Bridge the marker getter (item: MarkerPositionOption) to the store's `DimValueGetter`
    //   (dataItem: Any?, property, dataIndex, dimIndex). See markerHelper.swift.
    let dimValueGetter: DimValueGetter = { _, dataItem, property, dataIndex, dimIndex in
        let item = (dataItem as? MarkerPositionOption) ?? MarkerPositionOption()
        return markerGetter(item, property ?? "", Double(dataIndex), dimIndex)
    }

    fromData.initData(
        util.map(optData) { item, _ in (item.count > 0 ? item[0] : nil) as Any },
        nil,
        dimValueGetter
    )
    toData.initData(
        util.map(optData) { item, _ in (item.count > 1 ? item[1] : nil) as Any },
        nil,
        dimValueGetter
    )
    lineData.initData(
        util.map(optData) { item, _ in (item.count > 2 ? item[2] : nil) as Any }
    )
    lineData.hasItemOption = true

    // Stash the resolved line VALUE (the merged item[2].value) as an item visual so the LineDraw
    //   stand-in can render the default label text (upstream Line.ts uses `seriesModel.getRawValue(idx)`
    //   → the merged line-data item's value; `getRawValue`/`getFormattedLabel` are blocked here because
    //   MarkerModel's DataFormatMixin conformance is deferred — see MarkerModel.swift).
    for i in 0..<optData.count {
        let n2 = optData[i].count > 2 ? optData[i][2] : nil
        if let v = n2?.value {
            lineData.setItemVisual(i, ["__labelValue": v])
        }
    }

    return (from: fromData, to: toData, line: lineData)
}

// export default MarkLineView;  -> `final class MarkLineView` above.

// PORT-NOTE: `getECData(el).dataModel = mlModel` (renderSeries, host-model tooltip tagging) needs
//   `mlModel` to be a `DataModel`. `MarkerModel` already conforms to `DataHost` + `DataFormatMixin`
//   (MarkerModel.swift); `DataModel` additionally requires the 3-arg `getDataParams(_:_:_:)`.
//   `MarkerModel` provides only the 2-arg form (the `el` argument exists only on the CustomSeries
//   override in upstream), so add the 3-arg witness delegating to it. Same-module conformance ⇒ no
//   `@retroactive` needed.
extension MarkLineModel: DataModel {
    func getDataParams(
        _ dataIndex: Double,
        _ dataType: SeriesDataType?,
        _ el: Element?
    ) -> CallbackDataParams {
        return self.getDataParams(dataIndex, dataType)
    }
}

// ── local helpers (not in upstream; bridge dynamic option bags <-> MarkerPositionOption) ──────────

// Build a MarkerPositionOption from a raw `[String: Any]` data item (position-only fields).
private func markerPositionOption(from raw: Any?) -> MarkerPositionOption? {
    guard let raw = raw else { return nil }
    if let existing = raw as? MarkerPositionOption { return existing }
    var m = MarkerPositionOption()
    guard let d = raw as? [String: Any] else { return m }
    m.x = d["x"]
    m.y = d["y"]
    m.relativeTo = d["relativeTo"] as? String
    m.coord = d["coord"] as? [Any?]
    m.xAxis = d["xAxis"]
    m.yAxis = d["yAxis"]
    m.radiusAxis = d["radiusAxis"]
    m.angleAxis = d["angleAxis"]
    if let t = d["type"] as? String { m.type = MarkerStatisticType(rawValue: t) }
    m.valueIndex = d["valueIndex"] as? Double
    m.valueDim = d["valueDim"] as? String
    m.value = d["value"]
    return m
}

// zrender `merge(target, source)` (overwrite falsy): copy source's fields into target only where
//   target's field is nil. PORT-NOTE: deep object-recursion of merge is approximated by a shallow
//   field fill (MarkerPositionOption fields are scalars/arrays).
private func mergePositionOption(_ target: inout MarkerPositionOption, _ source: MarkerPositionOption?) {
    guard let source = source else { return }
    if target.x == nil { target.x = source.x }
    if target.y == nil { target.y = source.y }
    if target.relativeTo == nil { target.relativeTo = source.relativeTo }
    if target.coord == nil { target.coord = source.coord }
    if target.xAxis == nil { target.xAxis = source.xAxis }
    if target.yAxis == nil { target.yAxis = source.yAxis }
    if target.radiusAxis == nil { target.radiusAxis = source.radiusAxis }
    if target.angleAxis == nil { target.angleAxis = source.angleAxis }
    if target.type == nil { target.type = source.type }
    if target.valueIndex == nil { target.valueIndex = source.valueIndex }
    if target.valueDim == nil { target.valueDim = source.valueDim }
    if target.value == nil { target.value = source.value }
}

// util.retrieve2 replicated for `Any?` (`value0 != null ? value0 : value1`).
private func retrieve2Any(_ value0: Any?, _ value1: Any?) -> Any? {
    return value0 != nil ? value0 : value1
}

// PORT-NOTE (deferred): requires visual/helper.getVisualFromData (not ported); approximate the series
//   'color' visual by reading `style.fill`, else the direct visual slot.
private func getVisualFromData(_ data: SeriesData, _ key: String) -> Any? {
    if key == "color", let style = data.getVisual("style") as? [String: Any], let fill = style["fill"] {
        return fill
    }
    return data.getVisual(key)
}

// JS `+(x.toFixed(precision))` — format to `precision` decimals then reparse to a number.
private func toFixedNumber(_ x: Double, _ precision: Int) -> Double {
    if x.isNaN || x.isInfinite { return x }
    let str = String(format: "%.\(Swift.max(0, precision))f", x)
    return Double(str) ?? x
}

// Coerce a dynamic value to Double for numeric comparisons (nil if non-numeric).
private func toNum(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return nil
}

// Safe indexed access into a `[Any?]` coord array (JS reads out-of-range as `undefined`).
private func coordAt(_ coord: [Any?], _ i: Int) -> Any? {
    return (i >= 0 && i < coord.count) ? coord[i] : nil
}

// JS `===` on the coord scalars: compare numerically when both are numbers, else identity-ish.
private func looseEquals(_ a: Any?, _ b: Any?) -> Bool {
    if let da = toNum(a), let db = toNum(b) { return da == db }
    if a == nil && b == nil { return true }
    if let sa = a as? String, let sb = b as? String { return sa == sb }
    return false
}

// JS truthiness for dynamic `get('silent')` results (CONVENTIONS §6).
private func isTruthy(_ value: Any?) -> Bool {
    guard let value = value else { return false }
    if let b = value as? Bool { return b }
    if let d = value as? Double { return d != 0 && !d.isNaN }
    if let s = value as? String { return !s.isEmpty }
    return true
}
