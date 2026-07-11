// Ported (STATIC SUBSET) from echarts/src/component/marker/MarkPointView.ts — keep in sync with upstream.
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
// import SymbolDraw from '../../chart/helper/SymbolDraw';          -> `SymbolDraw` (chart/helper/SymbolDraw.swift, ported).
// import * as numberUtil from '../../util/number';                 -> EChartsKit `number` (util/number.swift)
// import SeriesData from '../../data/SeriesData';                  -> EChartsKit `SeriesData`
// import * as markerHelper from './markerHelper';                  -> sibling markerHelper.swift
// import MarkerView from './MarkerView';                           -> sibling MarkerView.swift
// import { CoordinateSystem } from '../../coord/CoordinateSystem'; -> EChartsKit `CoordinateSystem`
// import SeriesModel from '../../model/Series';                    -> EChartsKit `SeriesModel`
// import MarkPointModel, {MarkPointDataItemOption} from './MarkPointModel'; -> sibling MarkPointModel.swift
// import GlobalModel from '../../model/Global';                    -> EChartsKit `GlobalModel`
// import MarkerModel from './MarkerModel';                         -> sibling MarkerModel.swift
// import ExtensionAPI from '../../core/ExtensionAPI';              -> EChartsKit `ExtensionAPI`
// import { HashMap, isFunction, map, filter, curry, extend, retrieve2 } from 'zrender/src/core/util';
//   -> `HashMap` (util/modelUtil shim); `isFunction`/`map`/`filter`/`extend`/`retrieve2` -> ZRenderKit `util.*`;
//      `curry` replicated inline.
// import { getECData } from '../../util/innerStore';               -> `innerStore.getECData`
// import { getVisualFromData } from '../../visual/helper';         -> PORT-NOTE: visual/helper.ts not ported;
//      a minimal faithful `getVisualFromData` is inlined at the bottom of this file.
// import { ZRColor } from '../../util/types';                      -> EChartsKit `ZRColor` / ZRenderKit `ZRColor`
// import SeriesDimensionDefine from '../../data/SeriesDimensionDefine'; -> EChartsKit `SeriesDimensionDefine`

// function updateMarkerLayout(mpData, seriesModel, api)
private func updateMarkerLayout(
    _ mpData: SeriesData,
    _ seriesModel: SeriesModel,
    _ api: ExtensionAPI
) {
    // const coordSys = seriesModel.coordinateSystem;
    let coordSys = seriesModel.coordinateSystem as? CoordinateSystem
    let apiWidth = api.getWidth()
    let apiHeight = api.getHeight()
    // const coordRect = coordSys && coordSys.getArea && coordSys.getArea();
    let coordRect = coordSys?.getArea(nil)
    mpData.each { args in
        let idx = Int(args[0] as? Double ?? 0)
        let itemModel = mpData.getItemModel(idx)
        let isRelativeToCoordinate = (itemModel.get("relativeTo") as? String) == "coordinate"
        let width = isRelativeToCoordinate
            ? (coordRect != nil ? coordRect!.width : 0)
            : apiWidth
        let height = isRelativeToCoordinate
            ? (coordRect != nil ? coordRect!.height : 0)
            : apiHeight
        let left = (isRelativeToCoordinate && coordRect != nil)
            ? coordRect!.x
            : 0
        let top = (isRelativeToCoordinate && coordRect != nil)
            ? coordRect!.y
            : 0

        var point: [Double]?
        let xPx = number.parsePercent(itemModel.get("x"), width) + left
        let yPx = number.parsePercent(itemModel.get("y"), height) + top
        if !xPx.isNaN && !yPx.isNaN {
            point = [xPx, yPx]
        }
        // Chart like bar may have there own marker positioning logic
        // else if (seriesModel.getMarkerPosition)
        //   PORT-NOTE: `getMarkerPosition` is duck-typed on the series in upstream; only
        //   `BaseBarSeriesModel` declares it in the port. Feature-detect via `as? BaseBarSeriesModel`.
        //   Other series with custom marker positioning add it when they land.
        else if let barSeries = seriesModel as? BaseBarSeriesModel {
            // Use the getMarkerPosition
            point = barSeries.getMarkerPosition(
                mpData.getValues(mpData.dimensions, idx) as [ScaleDataValue]
            )
        }
        else if let coordSys = coordSys {
            let x = mpData.get(coordSys.dimensions[0], idx)
            let y = mpData.get(coordSys.dimensions[1], idx)
            point = coordSys.dataToPoint([x as Any, y as Any], nil)
        }

        // Use x, y if has any
        // PORT-NOTE: upstream assigns `point[0] = xPx` even when `point` is undefined (throws in JS on a
        //   degenerate config with no coordSys/getMarkerPosition and only one of x/y). Optional-chained
        //   assignment here no-ops instead of trapping — a safe deviation for static render.
        if !xPx.isNaN {
            point?[0] = xPx
        }
        if !yPx.isNaN {
            point?[1] = yPx
        }

        mpData.setItemLayout(idx, point)
    }
}

// upstream: class MarkPointView extends MarkerView
open class MarkPointView: MarkerView {

    // static type = 'markPoint';
    // type = MarkPointView.type;
    open override class var type: String { return "markPoint" }

    // markerGroupMap: HashMap<SymbolDraw>;  (inherited `markerGroupMap: HashMap<MarkerDraw>` on MarkerView)

    // updateTransform(markPointModel, ecModel, api)
    //   PORT-TODO: interaction/transform path (roam / dataZoom). It recomputes layout and calls
    //   `symbolDraw.updateLayout()` — SymbolDraw is not ported, so the per-draw relayout is deferred.
    //   The layout recompute is kept; the `.updateLayout()` call is stubbed.
    open func updateTransform(_ markPointModel: MarkPointModel, _ ecModel: GlobalModel, _ api: ExtensionAPI) {
        ecModel.eachSeries { seriesModel, _ in
            let mpModel = MarkerModel.getMarkerModelFromSeries(seriesModel, "markPoint") as? MarkPointModel
            if let mpModel = mpModel {
                updateMarkerLayout(
                    mpModel.getData(),
                    seriesModel, api
                )
                // this.markerGroupMap.get(seriesModel.id).updateLayout();
                // PORT-TODO: SymbolDraw.updateLayout not ported.
                _ = self.markerGroupMap.get(seriesModel.id)
            }
        }
    }

    // renderSeries(seriesModel, mpModel, ecModel, api)
    //   Overrides `MarkerView.renderSeries(seriesModel, markerModel, ecModel, api)`; narrows `markerModel`
    //   to `MarkPointModel` (upstream declares the param as `MarkPointModel`).
    open override func renderSeries(
        _ seriesModel: SeriesModel,
        _ markerModel: MarkerModel,
        _ ecModel: GlobalModel,
        _ api: ExtensionAPI
    ) {
        let mpModel = markerModel as! MarkPointModel
        let coordSys = seriesModel.coordinateSystem as? CoordinateSystem
        let seriesId = seriesModel.id
        let seriesData = seriesModel.getData()

        let symbolDrawMap = self.markerGroupMap!
        // const symbolDraw = symbolDrawMap.get(seriesId) || symbolDrawMap.set(seriesId, new SymbolDraw());
        //   The shared `chart/helper/SymbolDraw` IS ported and drives per-point `Symbol` elements
        //   (enter/update/leave diff + itemStyle + LABEL via getDefaultLabel/setLabelStyle). `SymbolDraw`
        //   conforms to `MarkerDraw` (see extension at bottom) so it lives in `markerGroupMap`.
        let symbolDraw = symbolDrawMap.get(seriesId) as? SymbolDraw
            ?? (symbolDrawMap.set(seriesId, SymbolDraw()) as! SymbolDraw)

        let mpData = createData(coordSys, seriesModel, mpModel)

        // FIXME
        mpModel.setData(mpData)

        updateMarkerLayout(mpModel.getData(), seriesModel, api)

        mpData.each { args in
            let idx = Int(args[0] as? Double ?? 0)
            let itemModel = mpData.getItemModel(idx)
            let symbol = itemModel.getShallow("symbol")
            let symbolSize = itemModel.getShallow("symbolSize")
            let symbolRotate = itemModel.getShallow("symbolRotate")
            let symbolOffset = itemModel.getShallow("symbolOffset")
            let symbolKeepAspect = itemModel.getShallow("symbolKeepAspect")

            // TODO: refactor needed: single data item should not support callback function
            if util.isFunction(symbol) || util.isFunction(symbolSize)
                || util.isFunction(symbolRotate) || util.isFunction(symbolOffset) {
                // PORT-TODO (MarkPointView.ts:144-160): callback-in-data-item — invoking an arbitrary user
                //   function against `mpModel.getRawValue(idx)` + `mpModel.getDataParams(idx)` is out of
                //   static-render scope (dynamic/interaction). `getRawValue` is additionally unavailable
                //   (DataFormatMixin conformance blocked, see MarkerModel.swift). The four function
                //   invocations are deferred:
                //     const rawIdx = mpModel.getRawValue(idx);
                //     const dataParams = mpModel.getDataParams(idx);
                //     if (isFunction(symbol)) symbol = symbol(rawIdx, dataParams);
                //     if (isFunction(symbolSize)) symbolSize = symbolSize(rawIdx, dataParams);
                //     if (isFunction(symbolRotate)) symbolRotate = symbolRotate(rawIdx, dataParams);
                //     if (isFunction(symbolOffset)) symbolOffset = symbolOffset(rawIdx, dataParams);
            }

            var style = itemModel.getModel("itemStyle").getItemStyle()
            let z2 = itemModel.get("z2")
            let color = getVisualFromData(seriesData, "color")   // as ZRColor
            // if (!style.fill) style.fill = color;
            if !jsTruthy(style["fill"]) {
                style["fill"] = color
            }

            // mpData.setItemVisual(idx, { z2, symbol, symbolSize, symbolRotate, symbolOffset,
            //                             symbolKeepAspect, style });
            //   PORT-NOTE: JS stores every key (incl. `undefined`); Swift `[String: Any]` cannot hold nil,
            //   so absent (nil) shallow values are omitted here and the direct build below falls back to the
            //   model default (`mpModel.get(...)`) — the role real ECharts' `visual/symbol.ts` stage plays.
            var visual: [String: Any] = ["style": style]
            if let z2v = util.retrieve2(z2, 0.0 as Any?) { visual["z2"] = z2v }
            if let symbol = symbol { visual["symbol"] = symbol }
            if let symbolSize = symbolSize { visual["symbolSize"] = symbolSize }
            if let symbolRotate = symbolRotate { visual["symbolRotate"] = symbolRotate }
            if let symbolOffset = symbolOffset { visual["symbolOffset"] = symbolOffset }
            if let symbolKeepAspect = symbolKeepAspect { visual["symbolKeepAspect"] = symbolKeepAspect }
            mpData.setItemVisual(idx, visual)
        }

        // TODO Text are wrong
        // symbolDraw.updateData(mpData);
        //   Faithful: the real `SymbolDraw` builds the symbols (falling back to the markPoint model
        //   default 'pin'/size-50 via the same visual slots set above) AND the value label inside each
        //   pin (label:{show:true,position:'inside'} → getDefaultLabel(mpData, idx)).
        symbolDraw.updateData(mpData)
        _ = self.group.add(symbolDraw.group)

        // Set host model for tooltip
        // FIXME
        // mpData.eachItemGraphicEl(el => el.traverse(child => getECData(child).dataModel = mpModel));
        //   PORT-TODO: tooltip host-model wiring deferred (rule 5 — interaction/tooltip). Additionally the
        //   direct build above does not register graphic els into `mpData._graphicEls` (that is
        //   SymbolDraw's job), so this loop would iterate nothing; and `getECData(child).dataModel`
        //   requires `MarkPointModel: DataModel` (blocked — DataFormatMixin conformance, see MarkerModel).

        self.markKeep(symbolDraw)

        // symbolDraw.group.silent = mpModel.get('silent') || seriesModel.get('silent');
        symbolDraw.group.silent = jsTruthy(mpModel.get("silent")) || jsTruthy(seriesModel.get("silent"))
    }
}

// function createData(coordSys, seriesModel, mpModel): SeriesData
private func createData(
    _ coordSys: CoordinateSystem?,
    _ seriesModel: SeriesModel,
    _ mpModel: MarkPointModel
) -> SeriesData {
    var coordDimsInfos: [SeriesDimensionDefine]
    if let coordSys = coordSys {
        // coordDimsInfos = map(coordSys.dimensions, function (coordDim) { ... });
        coordDimsInfos = util.map(coordSys.dimensions) { coordDim, _ in
            let data = seriesModel.getData()
            // const info = data.getDimensionInfo(data.mapDimension(coordDim)) || {} as SeriesDimensionDefine;
            let mapped = data.mapDimension(coordDim)
            // PORT-NOTE: upstream `|| {}` fallback when the dim is absent; `getDimensionInfo` force-unwraps
            //   in this port, so guard on `mapDimension` and use a fresh empty define when nil.
            let info: SeriesDimensionDefine = mapped != nil
                ? data.getDimensionInfo(mapped!)
                : SeriesDimensionDefine()
            // In map series data don't have lng and lat dimension. Fallback to same with coordSys
            // return extend(extend({}, info), { name: coordDim, ordinalMeta: null });
            let out = SeriesDimensionDefine(info)   // extend({}, info): shallow copy
            out.name = coordDim
            // DON'T use ordinalMeta to parse and collect ordinal.
            out.ordinalMeta = nil
            return out
        }
    }
    else {
        // coordDimsInfos = [{ name: 'value', type: 'float' }];
        let info = SeriesDimensionDefine()
        info.name = "value"
        info.type = .float
        coordDimsInfos = [info]
    }

    let mpData = SeriesData(coordDimsInfos, mpModel)

    // let dataOpt = map(mpModel.get('data'), curry(markerHelper.dataTransform, seriesModel));
    // if (coordSys) dataOpt = filter(dataOpt, curry(markerHelper.dataFilter, coordSys));
    //
    // PORT-NOTE (bridge, per MarkerModel.swift note): the user `data` items are dynamic `[String: Any]`
    //   option bags, while `markerHelper.dataTransform`/`dataFilter`/`createMarkerDimValueGetter` are typed
    //   to `MarkerPositionOption`. Convert each bag -> struct for the transform/filter/getter pipeline, and
    //   merge the resolved `coord`/`value` back onto the bag so `getItemModel`/`getShallow` (symbol/style/
    //   label) keep the full item. The bag array (not the struct array) is handed to `initData` so those
    //   readers work; the custom `dimValueGetter` reconstructs the struct from the bag.
    let rawData: [Any?] = (mpModel.get("data") as? [Any?]) ?? []
    var dataBags: [[String: Any]] = []
    var keptStructs: [MarkerPositionOption?] = []
    for raw in rawData {
        var bag = (raw as? [String: Any]) ?? [:]
        let transformed = markerHelper.dataTransform(seriesModel, toMarkerPositionOption(raw))
        if let t = transformed {
            if let coord = t.coord { bag["coord"] = coord }
            if let value = t.value { bag["value"] = value }
        }
        // if (coordSys) filter by dataFilter(coordSys, item)
        if coordSys != nil {
            if !markerHelper.dataFilter(coordSys, transformed ?? MarkerPositionOption()) {
                continue
            }
        }
        dataBags.append(bag)
        keptStructs.append(transformed)
    }
    _ = keptStructs   // struct array retained for parity; readers reconstruct from the bag via the getter.

    // const dimValueGetter = markerHelper.createMarkerDimValueGetter(!!coordSys, coordDimsInfos);
    let markerGetter = markerHelper.createMarkerDimValueGetter(coordSys != nil, coordDimsInfos)
    // Adapter: the store `DimValueGetter` is `(store, dataItem, property, dataIndex, dimIndex)`; the marker
    //   getter is `(item, dimName, dataIndex, dimIndex)`. `dataItem` is the item bag (provider.getItem).
    let dimValueGetter: DimValueGetter = { _, dataItem, property, dataIndex, dimIndex in
        let item = toMarkerPositionOption(dataItem)
        return markerGetter(item, property ?? "", Double(dataIndex), dimIndex)
    }
    // mpData.initData(dataOpt, null, dimValueGetter);
    mpData.initData(dataBags, nil, dimValueGetter)

    return mpData
}

// export default MarkPointView;  -> `open class MarkPointView` above.


// ============================================================================
// PORT-NOTE helpers — NOT part of MarkPointView.ts upstream. These bridge out-of-phase sibling APIs so
// the static markPoint render compiles. Delete each when its real sibling lands and call it directly.
// ============================================================================

// `chart/helper/SymbolDraw` conforms to `MarkerDraw` (it exposes `group: Group`) so a real SymbolDraw
//   can be stored in MarkerView's `markerGroupMap` (keep/removal + markKeep only need the group slot).
extension SymbolDraw: MarkerDraw {}

// Minimal faithful port of `visual/helper.ts#getVisualFromData` (only the `'color'` branch is exercised
//   by markPoint; the other branches are preserved for fidelity).
private func getVisualFromData(_ data: SeriesData, _ key: String) -> Any? {
    switch key {
    case "color":
        let style = data.getVisual("style") as? [String: Any]
        let drawType = (data.getVisual("drawType") as? String) ?? "fill"
        return style?[drawType]
    case "opacity":
        return (data.getVisual("style") as? [String: Any])?["opacity"]
    case "symbol", "symbolSize", "liftZ":
        return data.getVisual(key)
    default:
        // if (__DEV__) console.warn(`Unknown visual type ${key}`);
        return nil
    }
}

// Bridge a dynamic `[String: Any]` marker-data bag (or an already-built struct) into a
//   `MarkerPositionOption` for the markerHelper pipeline / dimValueGetter.
private func toMarkerPositionOption(_ any: Any?) -> MarkerPositionOption {
    if let s = any as? MarkerPositionOption {
        return s
    }
    var opt = MarkerPositionOption()
    guard let dict = any as? [String: Any] else {
        return opt
    }
    opt.x = dict["x"]
    opt.y = dict["y"]
    opt.relativeTo = dict["relativeTo"] as? String
    opt.coord = dict["coord"] as? [Any?]
    opt.xAxis = dict["xAxis"]
    opt.yAxis = dict["yAxis"]
    opt.radiusAxis = dict["radiusAxis"]
    opt.angleAxis = dict["angleAxis"]
    if let typeStr = dict["type"] as? String {
        opt.type = MarkerStatisticType(rawValue: typeStr)
    }
    opt.valueIndex = dict["valueIndex"] as? Double
    opt.valueDim = dict["valueDim"] as? String
    opt.value = dict["value"]
    return opt
}

// JS truthiness for the dynamic option-bag results (`if (x)` / `!x`) — CONVENTIONS §6.
private func jsTruthy(_ v: Any?) -> Bool {
    guard let v = v else { return false }
    if let b = v as? Bool { return b }
    if let d = v as? Double { return d != 0 && !d.isNaN }
    if let i = v as? Int { return i != 0 }
    if let s = v as? String { return !s.isEmpty }
    return true
}
