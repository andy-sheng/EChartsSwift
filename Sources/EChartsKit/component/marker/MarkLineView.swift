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
//   -> PORT-TODO: the real `chart/helper/LineDraw` (+ `chart/helper/Line`, with enter/leave animation
//      + emphasis/blur states) is not ported. A STATIC-SUBSET stand-in `LineDraw` is defined at the
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
//   -> PORT-TODO: util/innerStore (ECData host-model tagging for tooltip) not ported.
// import ExtensionAPI from '../../core/ExtensionAPI';                -> EChartsKit `ExtensionAPI`
// import Cartesian2D from '../../coord/cartesian/Cartesian2D';       -> EChartsKit `Cartesian2D`
// import GlobalModel from '../../model/Global';                      -> EChartsKit `GlobalModel`
// import MarkerModel from './MarkerModel';                           -> sibling MarkerModel.swift
// import { isArray, retrieve, retrieve2, clone, extend, logError, merge, map, curry, filter, HashMap,
//          isNumber } from 'zrender/src/core/util';                 -> ZRenderKit `util.*`
// import { makeInner } from '../../util/model';                      -> EChartsKit `model.makeInner`
// import { LineDataVisual } from '../../visual/commonVisualTypes';   -> util/types
// import { getVisualFromData } from '../../visual/helper';
//   -> PORT-TODO: visual/helper.getVisualFromData not ported; approximated by `getVisualFromData` below.
// import Axis2D from '../../coord/cartesian/Axis2D';                 -> EChartsKit `Axis2D`
// import SeriesDimensionDefine from '../../data/SeriesDimensionDefine'; -> EChartsKit `SeriesDimensionDefine`

// Item option for configuring line and each end of symbol.
// Line option. be merged from configuration of two ends.
// type MarkLineMergedItemOption = MarkLine2DDataItemOption[number];
//   -> the per-end option; modeled as `MarkerPositionOption` (position-only, see MarkerModel.swift).
//   PORT-TODO: item-level style/label/symbol options in the raw `[String: Any]` data item are not
//     carried onto `MarkerPositionOption`; where they are needed they are re-read via `getItemModel`
//     (which falls back to the mark-line model option).

// const inner = makeInner<{ from: SeriesData<MarkLineModel>, to: SeriesData<MarkLineModel> }, MarkLineModel>();
// PORT-TODO: `makeInner` needs an `AnyObject` value; the `{ from, to }` bag is wrapped in a reference.
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
        // Chart like bar may have there own marker positioning logic
        // if (seriesModel.getMarkerPosition) { point = seriesModel.getMarkerPosition(...); }
        // PORT-TODO (MarkLineView.ts:217): `SeriesModel.getMarkerPosition` (bar/candlestick override)
        //   is not ported; the else branch (generic coord `dataToPoint`) is always taken.
        let dims = coordSys?.dimensions ?? []
        let x = data.get(dims[0], idx)
        let y = data.get(dims[1], idx)
        point = coordSys?.dataToPoint([(x as Any), (y as Any)], nil)

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
        // PORT-TODO: `getECData` (util/innerStore) not ported — tagging the graphic els with the host
        //   data model (for tooltip) is deferred (interaction, out of static-render scope).

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
                // PORT-TODO: upstream's `|| {}` fallback when the dim info is genuinely absent is not
                //   reproduced (getDimensionInfo force-unwraps); `md` resolves in practice for markLine.
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

// ─────────────────────────────────────────────────────────────────────────────────────────────
// STATIC-SUBSET stand-in for chart/helper/LineDraw.ts (+ chart/helper/Line.ts). The real LineDraw
//   diffs `lineData`, entering a `Line` group per datum (Polyline body + two end `Symbol`s + a
//   `label`), with enter/leave animation and emphasis/blur states. This stand-in builds the static
//   from→to segment faithfully: the `Polyline` body with the full `lineStyle` (dashed/width/opacity),
//   the from/to end SYMBOLS (circle+arrow) at the resolved endpoints with the Line.ts tangent
//   rotation, and the default value LABEL at `label.position`. PORT-TODO: enter/leave animation,
//   emphasis/blur states, curved (`percent`<1 / bezier) lines, and non-`end`/`start` label layouts
//   are deferred (see the switch in chart/helper/Line.ts#beforeUpdate).
// ─────────────────────────────────────────────────────────────────────────────────────────────
final class LineDraw: MarkerDraw {
    // group = new graphic.Group();
    let group = Group()
    private var _lineData: SeriesData?

    init() {}

    // updateData(lineData)
    func updateData(_ lineData: SeriesData) {
        self.group.removeAll()
        for idx in 0..<lineData.count() {
            // itemLayout = [fromPoint, toPoint]
            guard
                let layout = lineData.getItemLayout(idx) as? [Any?], layout.count >= 2,
                let p0 = layout[0] as? [Double], p0.count >= 2,
                let p1 = layout[1] as? [Double], p1.count >= 2,
                // lineNeedsDraw: no NaN endpoint
                p0[0].isFinite, p0[1].isFinite, p1[0].isFinite, p1[1].isFinite
            else {
                continue
            }
            // A `Line` in upstream is a Group holding the polyline + end symbols + label; mirror that
            //   grouping so z-order and future emphasis wiring line up.
            let lineGroup = Group()
            lineGroup.name = "line"

            let style = lineData.getItemVisual(idx, "style") as? [String: Any]

            var shape = PolylineShape()
            shape.points = [VectorArray(p0[0], p0[1]), VectorArray(p1[0], p1[1])]
            let line = Polyline()
            line.setShape(shape)
            line.name = "line"

            // Full lineStyle: stroke + lineWidth + opacity + lineDash (the markLine default
            //   `lineStyle.type:'dashed'` → getLineStyle → style["lineDash"]="dashed").
            var st = PathStyleProps()
            st.fill = .string("none")
            let strokeColor = colorString(style?["stroke"])
            if let stroke = strokeColor {
                st.stroke = .string(stroke)
            }
            st.lineWidth = (style?["lineWidth"] as? Double) ?? 2
            if let op = style?["opacity"] as? Double { st.opacity = op }
            st.lineDash = lineDashFrom(style?["lineDash"])
            line.useStyle(st)
            _ = lineGroup.add(line)

            // upstream (Line.ts:243-264): emphasis/blur/select lineStyle states on the polyline.
            //   An empty emphasis style still creates the state, so the render pass's
            //   `savePathStates` seam picks the line up and the default stroke lift applies.
            let hoverItemModel = lineData.getItemModel(idx)
            let emphasisModel = hoverItemModel.getModel(["emphasis"])
            line.ensureState("emphasis").style = emphasisModel.getModel("lineStyle").getLineStyle()
            line.ensureState("blur").style = hoverItemModel.getModel(["blur", "lineStyle"]).getLineStyle()
            line.ensureState("select").style = hoverItemModel.getModel(["select", "lineStyle"]).getLineStyle()
            let focus: InnerFocus? = emphasisModel.get("focus")
            let blurScope = (emphasisModel.get("blurScope") as? String).flatMap { BlurScope(rawValue: $0) }
            let emphasisDisabled = (emphasisModel.get("disabled") as? Bool) ?? false

            // from/to end symbols with the Line.ts tangent rotation. For a straight 2-point line the
            //   tangent is constant = normalize(toPos − fromPos).
            var d = [p1[0] - p0[0], p1[1] - p0[1]]
            let dlen = (d[0] * d[0] + d[1] * d[1]).squareRoot()
            if dlen > 0 { d = [d[0] / dlen, d[1] / dlen] }
            let baseAtan = atan2(d[1], d[0])
            var endSymbols: [Path] = []
            if let sym = makeEndSymbol(lineData, idx, "from", strokeColor, style?["opacity"] as? Double) {
                sym.x = p0[0]; sym.y = p0[1]
                // percent 0: `1 * PI/2 − atan2(tangent)`
                sym.rotation = Double.pi / 2 - baseAtan
                _ = lineGroup.add(sym)
                endSymbols.append(sym)
            }
            if let sym = makeEndSymbol(lineData, idx, "to", strokeColor, style?["opacity"] as? Double) {
                sym.x = p1[0]; sym.y = p1[1]
                // percent 1: `-1 * PI/2 − atan2(tangent)`
                sym.rotation = -Double.pi / 2 - baseAtan
                _ = lineGroup.add(sym)
                endSymbols.append(sym)
            }

            // upstream (Line.ts:274-292): share the line's per-state stroke/opacity with the end
            //   symbols (an empty-brush symbol takes it on `stroke`, a solid one on `fill`).
            for sym in endSymbols {
                for stateName in ["emphasis", "blur", "select"] {
                    guard let lineStateStyle = line.getState(stateName)?.style else { continue }
                    let state = sym.ensureState(stateName)
                    var stateStyle = state.style ?? [:]
                    if let stroke = lineStateStyle["stroke"] {
                        let isEmpty = (sym as? ECSymbol)?.__isEmptyBrush ?? false
                        stateStyle[isEmpty ? "stroke" : "fill"] = stroke
                    }
                    if let opacity = lineStateStyle["opacity"] {
                        stateStyle["opacity"] = opacity
                    }
                    state.style = stateStyle
                }
            }

            // default value LABEL (label.show/position/distance resolve from the markLine model via the
            //   item model's parent chain). Only the 'start'/'end' positions of Line.ts are ported.
            let itemModel = lineData.getItemModel(idx)
            let labelModel = itemModel.getModel("label")
            if isTruthy(labelModel.get("show")), let text = labelText(lineData, idx) {
                let position = (labelModel.get("position") as? String) ?? "end"
                let distance = (labelModel.get("distance") as? Double) ?? 5
                let label = ZRText(["silent": true])
                var ts = TextStyleProps()
                ts.text = text
                ts.font = labelModel.getFont()
                ts.fill = labelModel.getTextColor() ?? strokeColor
                positionLineLabel(&ts, position, distance, d, p0, p1)
                label.useStyle(ts)
                label.z2 = 10
                _ = lineGroup.add(label)
            }

            // upstream (Line.ts:336): the whole line group is the highDown dispatcher — hovering the
            //   polyline OR an end symbol emphasizes them together.
            states.toggleHoverEmphasis(lineGroup, focus, blurScope, emphasisDisabled)

            _ = self.group.add(lineGroup)
            lineData.setItemGraphicEl(idx, lineGroup)
        }
        self._lineData = lineData
    }

    // updateLayout()
    func updateLayout() {
        // PORT-TODO: incremental layout update (re-reads item layouts onto existing els). The static
        //   stand-in simply re-renders from the retained `_lineData`.
        if let lineData = self._lineData {
            self.updateData(lineData)
        }
    }
}

// Build a from/to end symbol per chart/helper/Line.ts#createSymbol (centered at origin so the group
//   rotation pivots on the endpoint). Returns nil for symbol type 'none'/absent.
private func makeEndSymbol(
    _ lineData: SeriesData, _ idx: Int, _ name: String, _ color: String?, _ opacity: Double?
) -> Path? {
    let symbolType = lineData.getItemVisual(idx, name + "Symbol") as? String
    guard let symbolType = symbolType, symbolType != "none" else { return nil }
    let sizeVisual = lineData.getItemVisual(idx, name + "SymbolSize") ?? 8.0
    let sizeArr = symbol.normalizeSymbolSize(sizeVisual)
    let offset = symbol.normalizeSymbolOffset(lineData.getItemVisual(idx, name + "SymbolOffset") ?? 0, [sizeArr.0, sizeArr.1]) ?? (0, 0)
    let colorZR: ZRenderKit.ZRColor? = color.map { .string($0) }
    let sym = symbol.createSymbol(
        symbolType,
        -sizeArr.0 / 2 + offset.0,
        -sizeArr.1 / 2 + offset.1,
        sizeArr.0, sizeArr.1,
        colorZR
    )
    guard let path = sym as? Path else { return nil }
    if let op = opacity { path.pathStyle.opacity = op }
    path.name = name
    return path
}

// chart/helper/Line.ts#beforeUpdate label layout — only the 'end'/'start' cases (straight line).
private func positionLineLabel(
    _ ts: inout TextStyleProps, _ position: String, _ distance: Double,
    _ d: [Double], _ fromPos: [Double], _ toPos: [Double]
) {
    let distanceX = distance
    let distanceY = distance
    if position == "start" {
        ts.x = -d[0] * distanceX + fromPos[0]
        ts.y = -d[1] * distanceY + fromPos[1]
        ts.align = d[0] > 0.8 ? .right : (d[0] < -0.8 ? .left : .center)
        ts.verticalAlign = d[1] > 0.8 ? .bottom : (d[1] < -0.8 ? .top : .middle)
    }
    else {
        // 'end' (default)
        ts.x = d[0] * distanceX + toPos[0]
        ts.y = d[1] * distanceY + toPos[1]
        ts.align = d[0] > 0.8 ? .left : (d[0] < -0.8 ? .right : .center)
        ts.verticalAlign = d[1] > 0.8 ? .top : (d[1] < -0.8 ? .bottom : .middle)
    }
}

// Default label text: the stashed line value rounded (upstream `round(rawVal, 10) + ''`), else the name.
private func labelText(_ lineData: SeriesData, _ idx: Int) -> String? {
    if let v = toNum(lineData.getItemVisual(idx, "__labelValue")) {
        if v.isFinite { return number.jsString(number.round(v, 10)) }
        return number.jsString(v)
    }
    let name = lineData.getName(idx)
    return name.isEmpty ? nil : name
}

// Map the getLineStyle `lineDash` value ("solid"/"dashed"/"dotted" keyword or number[]) to the
//   ZRenderKit `LineDash` enum (same bridge LineView.applyLineStyle uses).
private func lineDashFrom(_ v: Any?) -> LineDash? {
    if let s = v as? String {
        if s == "dashed" { return .dashed }
        if s == "dotted" { return .dotted }
        if s == "solid" { return .solid }
    }
    if let arr = v as? [Double] { return .values(arr) }
    if let arri = v as? [Int] { return .values(arri.map { Double($0) }) }
    return nil
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
//   target's field is nil. PORT-TODO: deep object-recursion of merge is approximated by a shallow
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

// PORT-TODO: visual/helper.getVisualFromData not ported; approximate the series 'color' visual by
//   reading `style.fill`, else the direct visual slot.
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

// Extract a solid color string from a dynamic visual value (String or EChartsKit.ZRColor.color).
private func colorString(_ v: Any?) -> String? {
    if let str = v as? String { return str }
    if let zr = v as? EChartsKit.ZRColor, case let .color(str) = zr { return str }
    return nil
}
