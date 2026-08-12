// Ported from echarts/src/component/marker/MarkAreaView.ts — keep in sync with upstream
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

// TODO Optimize on polar

import Foundation
import ZRenderKit
// upstream imports (mapped to this port; `→` marks the Swift symbol used):
//   import * as colorUtil from 'zrender/src/tool/color';           -> ZRenderKit `color` namespace (Tool/color.swift).
//   import SeriesData from '../../data/SeriesData';                 -> `SeriesData`.
//   import * as numberUtil from '../../util/number';                -> `number` namespace (util/number.swift).
//   import * as graphic from '../../util/graphic';
//     -> `util/graphic` is NOT ported as a namespace. `graphic.Group` / `graphic.Polygon` are the
//        ZRenderKit scene-graph types `Group` / `Polygon` (used directly). `graphic.updateProps`
//        resolves to the real ported `animation/basicTransition.updateProps` (same as BarView.swift).
//   import { toggleHoverEmphasis, setStatesStylesFromModel } from '../../util/states';
//     -> states.toggleHoverEmphasis / states.setStatesStylesFromModel (util/states.swift).
//   import * as markerHelper from './markerHelper';                 -> sibling `markerHelper`.
//   import MarkerView from './MarkerView';                          -> sibling `MarkerView`.
//   import { retrieve, mergeAll, map, curry, filter, HashMap, extend, isString, retrieve2 }
//        from 'zrender/src/core/util';
//     -> `util.retrieve` / `util.mergeAll` / `util.map` / `util.filter` / `util.extend` /
//        `util.isString` / `util.retrieve2`; `HashMap` (util/modelUtil.swift shim); `curry` inlined.
//   import { ScaleDataValue, ZRColor } from '../../util/types';     -> util/types.swift.
//   import { CoordinateSystem, isCoordinateSystemType } from '../../coord/CoordinateSystem';
//     -> coord/CoordinateSystem.swift (`CoordinateSystem`; `isCoordinateSystemType` narrowed via `as?`).
//   import MarkAreaModel, { MarkArea2DDataItemOption } from './MarkAreaModel'; -> sibling `MarkAreaModel`.
//   import SeriesModel from '../../model/Series';                   -> `SeriesModel`.
//   import Cartesian2D from '../../coord/cartesian/Cartesian2D';    -> `Cartesian2D`.
//   import SeriesDimensionDefine from '../../data/SeriesDimensionDefine'; -> `SeriesDimensionDefine`.
//   import GlobalModel from '../../model/Global';                   -> `GlobalModel`.
//   import ExtensionAPI from '../../core/ExtensionAPI';             -> `ExtensionAPI`.
//   import MarkerModel from './MarkerModel';                        -> sibling `MarkerModel`.
//   import { makeInner } from '../../util/model';                   -> `model.makeInner`.
//   import { getVisualFromData } from '../../visual/helper';
//     -> PORT-NOTE (deferred): `visual/helper.ts` NOT ported as a module. Faithful minimal
//        `getVisualFromData` at the bottom of this file (delete once visual/helper.swift lands).
//   import { setLabelStyle, getLabelStatesModels } from '../../label/labelStyle';
//     -> `label/labelStyle.swift` (`labelStyle.setLabelStyle` / `labelStyle.getLabelStatesModels`).
//        labelStyle IS ported; the label block below is still deferred, but NOT for lack of it —
//        see the deferral note at the label block (MarkerModel is not a DataFormatMixin/DataModel).
//   import { getECData } from '../../util/innerStore';              -> `innerStore.getECData`.
//   import Axis2D from '../../coord/cartesian/Axis2D';              -> `Axis2D`.
//   import { parseDataValue } from '../../data/helper/dataValueHelper'; -> `dataValueHelper.parseDataValue`.
//   import tokens from '../../visual/tokens';
//     -> `visual/tokens.swift` (`tokens.color.neutral99`); only referenced by the deferred label block.

// interface MarkAreaDrawGroup { group: graphic.Group }
//   The per-series draw group. Conforms to `MarkerDraw` (MarkerView.swift) so it can be stored in the
//   inherited `markerGroupMap: HashMap<MarkerDraw>` and hosted by `markKeep`/`makeInner`.
final class MarkAreaDrawGroup: MarkerDraw {
    let group: Group
    init(group: Group) { self.group = group }
}

// const inner = makeInner<{ data: SeriesData<MarkAreaModel> }, MarkAreaDrawGroup>();
// PORT-NOTE: `makeInner` requires a reference (`AnyObject`) value type; the `{ data }` bag is wrapped
//   in a reference `MarkAreaInnerData`; the host is the `MarkAreaDrawGroup` object.
final class MarkAreaInnerData {
    var data: SeriesData?
    init() {}
}
private let inner: (AnyObject) -> MarkAreaInnerData = model.makeInner { MarkAreaInnerData() }

// Merge two ends option into one.
// type MarkAreaMergedItemOption = Omit<MarkArea2DDataItemOption[number], 'coord'> & {
//     coord: MarkArea2DDataItemOption[number]['coord'][]
//     x0: number | string; y0: number | string; x1: number | string; y1: number | string;
// };
// PORT-NOTE: the merged item is a dynamic option bag `[String: Any]` (CONVENTIONS §2/§4). It must stay
//   a dict so `data.getItemModel(idx)` (a `Model` over the raw item) can read passthrough keys
//   (`itemStyle`/`z2`/`name`/`label`) AND the dim-value getter can read `coord`.
typealias MarkAreaMergedItemOption = [String: Any]

// const markAreaTransform = function (seriesModel, coordSys, maModel, item): MarkAreaMergedItemOption
private func markAreaTransform(
    _ seriesModel: SeriesModel,
    _ coordSys: CoordinateSystem?,
    _ maModel: MarkAreaModel,
    _ itemInput: Any?
) -> MarkAreaMergedItemOption? {
    // item may be null
    // const item0 = item[0]; const item1 = item[1];
    // `item` is the 2-end tuple `MarkArea2DDataItemOption` — a 2-element array of dim option dicts.
    // POTENTIAL-BUG: a 1D markArea item (`MarkArea1DDataItemOption`, a single object) has no `[0]`/`[1]`,
    //   so `item0`/`item1` are nil and this returns nil — the item is silently dropped (see the filter
    //   below). Upstream relies on prior normalization; 1D markArea normalization is not reproduced here,
    //   so a 1D markArea data item renders nothing. Out of current static-render scope.
    let itemArr = itemInput as? [Any?]
    let item0Any: Any? = (itemArr != nil && itemArr!.count > 0) ? itemArr![0] : nil
    let item1Any: Any? = (itemArr != nil && itemArr!.count > 1) ? itemArr![1] : nil
    // if (!item0 || !item1) { return; }
    guard let item0Dict = item0Any as? [String: Any],
          let item1Dict = item1Any as? [String: Any] else {
        return nil
    }

    // const lt = markerHelper.dataTransform(seriesModel, item0);
    // const rb = markerHelper.dataTransform(seriesModel, item1);
    guard var lt = markerHelper.dataTransform(seriesModel, markAreaPositionOption(item0Dict)),
          var rb = markerHelper.dataTransform(seriesModel, markAreaPositionOption(item1Dict)) else {
        return nil
    }

    // FIXME make sure lt is less than rb
    // const ltCoord = lt.coord; const rbCoord = rb.coord;
    var ltCoord: [Any?] = lt.coord ?? [nil, nil]
    var rbCoord: [Any?] = rb.coord ?? [nil, nil]
    // ltCoord[0] = retrieve(ltCoord[0], -Infinity); ltCoord[1] = retrieve(ltCoord[1], -Infinity);
    ltCoord[0] = ltCoord[0] ?? (-Double.infinity)
    ltCoord[1] = ltCoord[1] ?? (-Double.infinity)
    // rbCoord[0] = retrieve(rbCoord[0], Infinity); rbCoord[1] = retrieve(rbCoord[1], Infinity);
    rbCoord[0] = rbCoord[0] ?? Double.infinity
    rbCoord[1] = rbCoord[1] ?? Double.infinity
    lt.coord = ltCoord
    rb.coord = rbCoord

    // Merge option into one
    // const result: MarkAreaMergedItemOption = mergeAll([{}, lt, rb]);
    // PORT-NOTE: upstream merges the two TRANSFORMED position objects `lt`/`rb` (which are clones of
    //   `item0`/`item1` still carrying passthrough keys like itemStyle/name/z2). The ported
    //   `MarkerPositionOption` is a struct that drops those passthrough keys, so the merge is
    //   reconstructed from the ORIGINAL item dicts (preserving passthrough) and the struct-carried
    //   transformed fields (coord/x/y/value) are overlaid below. `mergeAll` uses the same non-overwrite
    //   semantics as zrender (`item0` wins on shared keys).
    var result: MarkAreaMergedItemOption = util.mergeAll([[:], item0Dict, item1Dict])

    // result.coord = [lt.coord, rb.coord];
    result["coord"] = [ltCoord, rbCoord]
    // result.x0 = lt.x; result.y0 = lt.y; result.x1 = rb.x; result.y1 = rb.y;
    result["x0"] = lt.x
    result["y0"] = lt.y
    result["x1"] = rb.x
    result["y1"] = rb.y
    // `value` (a transformed field) — mergeAll([{}, lt, rb]) with non-overwrite keeps lt's value.
    if let v = lt.value {
        result["value"] = v
    }
    else if let v = rb.value {
        result["value"] = v
    }
    _ = (coordSys, maModel)
    return result
}

// function isInfinity(val: ScaleDataValue) { return !isNaN(val as number) && !isFinite(val as number); }
private func isInfinity(_ val: Any?) -> Bool {
    // PORT-NOTE: JS `isNaN`/`isFinite` coerce strings; only a `Double` (incl. the ±Infinity defaults
    //   assigned in `markAreaTransform`) is examined here — sufficient for the numeric coord path.
    let d = (val as? Double) ?? Double.nan
    return !d.isNaN && !d.isFinite
}

// If a markArea has one dim
// function ifMarkAreaHasOnlyDim(dimIndex, fromCoord, toCoord, coordSys)
private func ifMarkAreaHasOnlyDim(
    _ dimIndex: Int,
    _ fromCoord: [Any?],
    _ toCoord: [Any?],
    _ coordSys: CoordinateSystem
) -> Bool {
    let otherDimIndex = 1 - dimIndex
    return isInfinity(fromCoord[otherDimIndex]) && isInfinity(toCoord[otherDimIndex])
}

// function markAreaFilter(coordSys, item)
private func markAreaFilter(_ coordSys: CoordinateSystem, _ item: MarkAreaMergedItemOption) -> Bool {
    let coord = (item["coord"] as? [[Any?]]) ?? [[nil, nil], [nil, nil]]
    let fromCoord = coord[0]
    let toCoord = coord[1]
    // const item0 = { coord: fromCoord, x: item.x0, y: item.y0 };
    var item0 = MarkerPositionOption()
    item0.coord = fromCoord
    item0.x = item["x0"]
    item0.y = item["y0"]
    // const item1 = { coord: toCoord, x: item.x1, y: item.y1 };
    var item1 = MarkerPositionOption()
    item1.coord = toCoord
    item1.x = item["x1"]
    item1.y = item["y1"]
    // if (isCoordinateSystemType<Cartesian2D>(coordSys, 'cartesian2d'))
    if coordSys is Cartesian2D {
        // In case { markArea: { data: [{ yAxis: 2 }] } }
        // if (fromCoord && toCoord && (ifMarkAreaHasOnlyDim(1,...) || ifMarkAreaHasOnlyDim(0,...))) return true;
        // `fromCoord`/`toCoord` are always present here (defaulted above) — mirror the truthy guard as
        //   a non-empty check.
        if !fromCoord.isEmpty && !toCoord.isEmpty
            && (ifMarkAreaHasOnlyDim(1, fromCoord, toCoord, coordSys)
                || ifMarkAreaHasOnlyDim(0, fromCoord, toCoord, coordSys)) {
            return true
        }
        // Directly returning true may also do the work, because markArea will not be shown
        // automatically when it's not included in coordinate system. But filtering ahead can avoid
        // keeping rendering markArea when there are too many of them.
        return markerHelper.zoneFilter(coordSys, item0, item1)
    }
    return markerHelper.dataFilter(coordSys, item0)
        || markerHelper.dataFilter(coordSys, item1)
}

// dims can be ['x0', 'y0'], ['x1', 'y1'], ['x0', 'y1'], ['x1', 'y0']
// function getSingleMarkerEndPoint(data, idx, dims, seriesModel, api): number[]
private func getSingleMarkerEndPoint(
    _ data: SeriesData,
    _ idx: Int,
    _ dims: [String],
    _ seriesModel: SeriesModel,
    _ api: ExtensionAPI
) -> [Double] {
    let coordSys = seriesModel.coordinateSystem
    let itemModel = data.getItemModel(idx)

    var point: [Double]
    // const xPx = numberUtil.parsePercent(itemModel.get(dims[0]), api.getWidth());
    let xPx = number.parsePercent(itemModel.get(dims[0]), api.getWidth())
    // const yPx = numberUtil.parsePercent(itemModel.get(dims[1]), api.getHeight());
    let yPx = number.parsePercent(itemModel.get(dims[1]), api.getHeight())
    if !xPx.isNaN && !yPx.isNaN {
        point = [xPx, yPx]
    }
    else {
        // Chart like bar may have there own marker positioning logic
        // if (seriesModel.getMarkerPosition) { ... }
        //   PORT-NOTE: `getMarkerPosition` is duck-typed on the series in upstream; only
        //   `BaseBarSeriesModel` declares it in the port (mirrors MarkLineView/MarkPointView).
        //   Feature-detect via `as? BaseBarSeriesModel`; the bar/candlestick override snaps
        //   markArea corners to category ticks.
        if let barSeries = seriesModel as? BaseBarSeriesModel {
            // Consider the case that user input the right-bottom point first
            // Pick the larger x and y as 'x1' and 'y1'
            // const pointValue0 = data.getValues(['x0', 'y0'], idx);
            let pointValue0 = data.getValues(["x0", "y0"], idx)
            // const pointValue1 = data.getValues(['x1', 'y1'], idx);
            let pointValue1 = data.getValues(["x1", "y1"], idx)
            // const clampPointValue0 = coordSys.clampData(pointValue0);
            let clampPointValue0 = (coordSys as? Cartesian2D)?.clampData(pointValue0) ?? [Double.nan, Double.nan]
            // const clampPointValue1 = coordSys.clampData(pointValue1);
            let clampPointValue1 = (coordSys as? Cartesian2D)?.clampData(pointValue1) ?? [Double.nan, Double.nan]
            // const pointValue = [];
            var pointValue: [ScaleDataValue] = [Double.nan, Double.nan]
            if dims[0] == "x0" {
                pointValue[0] = (clampPointValue0[0] > clampPointValue1[0]) ? pointValue1[0] : pointValue0[0]
            }
            else {
                pointValue[0] = (clampPointValue0[0] > clampPointValue1[0]) ? pointValue0[0] : pointValue1[0]
            }
            if dims[1] == "y0" {
                pointValue[1] = (clampPointValue0[1] > clampPointValue1[1]) ? pointValue1[1] : pointValue0[1]
            }
            else {
                pointValue[1] = (clampPointValue0[1] > clampPointValue1[1]) ? pointValue0[1] : pointValue1[1]
            }
            // Use the getMarkerPosition
            // point = seriesModel.getMarkerPosition(pointValue, dims, true);
            point = barSeries.getMarkerPosition(pointValue, dims, true)
        }
        else {
            let x = data.get(dims[0], idx)
            let y = data.get(dims[1], idx)
            var pt: [ScaleDataValue] = [(x ?? Double.nan), (y ?? Double.nan)]
            // coordSys.clampData && coordSys.clampData(pt, pt);
            if let cartesian = coordSys as? Cartesian2D, let clamped = cartesian.clampData(pt) {
                pt = clamped.map { $0 as ScaleDataValue }
            }
            // point = coordSys.dataToPoint(pt, true);
            // PORT-NOTE (deferred): `dataToPoint` dispatched on the concrete Cartesian2D (protocol default
            //   is []); polar/geo out of static-render scope.
            point = (coordSys as? Cartesian2D)?.dataToPoint(pt, true) ?? [Double.nan, Double.nan]
        }
        // if (isCoordinateSystemType<Cartesian2D>(coordSys, 'cartesian2d'))
        if let cartesian = coordSys as? Cartesian2D {
            // TODO: TYPE ts@4.1 may still infer it as Axis instead of Axis2D. Not sure if it's a bug
            let xAxis = cartesian.getAxis("x")!
            let yAxis = cartesian.getAxis("y")!
            let x = data.get(dims[0], idx)
            let y = data.get(dims[1], idx)
            if isInfinity(x) {
                point[0] = xAxis.toGlobalCoord(xAxis.getExtent()[dims[0] == "x0" ? 0 : 1])
            }
            else if isInfinity(y) {
                point[1] = yAxis.toGlobalCoord(yAxis.getExtent()[dims[1] == "y0" ? 0 : 1])
            }
        }

        // Use x, y if has any
        if !xPx.isNaN {
            point[0] = xPx
        }
        if !yPx.isNaN {
            point[1] = yPx
        }
    }

    return point
}

// export const dimPermutations = [['x0', 'y0'], ['x1', 'y0'], ['x1', 'y1'], ['x0', 'y1']] as const;
public let dimPermutations: [[String]] = [["x0", "y0"], ["x1", "y0"], ["x1", "y1"], ["x0", "y1"]]

// upstream: class MarkAreaView extends MarkerView
public final class MarkAreaView: MarkerView {

    // static type = 'markArea';
    // type = MarkAreaView.type;
    public override class var type: String { return "markArea" }

    // markerGroupMap: HashMap<MarkAreaDrawGroup>;
    //   Inherited from MarkerView as `HashMap<MarkerDraw>`; `MarkAreaDrawGroup` entries are narrowed
    //   via `as?` at use sites (Swift cannot re-type an inherited generic property).

    // updateTransform(markAreaModel, ecModel, api)
    // PORT-NOTE: this is the optional `ComponentView.updateTransform` hook (transform-only re-layout on
    //   zoom/pan), now WIRED — the driver (`ECharts.updateTransform`, core/ECharts.swift) invokes the
    //   base 4-param hook `updateTransform(_:_:_:_:) -> Bool?`, so this must override it exactly (a
    //   narrower 3-param method does not override and would never be called). Upstream types the first
    //   parameter as the concrete `MarkAreaModel` via declaration merging; Swift requires the base
    //   `ComponentModel` parameter type.
    //   Return tri-state (see `ComponentView.updateTransform` and `ECharts.updateTransform`):
    //     `nil`   == the BASE (no hook at all) → the driver falls back to a full render;
    //     `false` == upstream's `void` from an IMPLEMENTED hook — handled in place, view is NOT pushed
    //                onto `componentDirtyList` (echarts.ts:1964-1970), so no re-render;
    //     `true`  == upstream `{update: true}`.
    //   This hook re-lays out in place, so it returns `false`; returning `nil` would make the driver
    //   re-render everything and discard the work done here.
    //   `markAreaModel` is unused upstream as well (the sweep is driven by `ecModel.eachSeries`).
    public override func updateTransform(
        _ markAreaModel: ComponentModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) -> Bool? {
        ecModel.eachSeries({ seriesModel, _ in
            let maModel = MarkerModel.getMarkerModelFromSeries(seriesModel, "markArea") as? MarkAreaModel
            if let maModel = maModel {
                let areaData = maModel.getData()
                areaData.each { args in
                    let idx = Int((args[0] as? Double) ?? 0)
                    let points = util.map(dimPermutations) { dim, _ in
                        return getSingleMarkerEndPoint(areaData, idx, dim, seriesModel, api)
                    }
                    // Layout
                    // areaData.setItemLayout(idx, points);
                    // PORT-NOTE (deliberate deviation): upstream writes the RAW `points` array here,
                    //   which silently drops the `{points, allClipped}` shape that renderSeries
                    //   (MarkAreaView.ts:300) writes and the label/render paths read. JS tolerates the
                    //   type switch; Swift readers cast to `MarkAreaItemLayout`, so keep the struct
                    //   contract and preserve the existing `allClipped` flag (which gates label
                    //   suppression, #12591) instead of replacing the layout value's type.
                    // PORT-TODO: `allClipped` and graphic-el existence are NOT recomputed on a
                    //   transform-only pass — a datum that was allClipped (no Polygon created) stays
                    //   invisible after a roam/pan brings it back into the coord sys, and returning
                    //   `false` below suppresses the full-render fallback. Upstream
                    //   (MarkAreaView.ts:251-253) has the same blind spot (and would in fact throw on
                    //   `el.setShape` with `el === undefined`), so this is faithful-but-latent.
                    let prev = areaData.getItemLayout(idx) as? MarkAreaItemLayout
                    areaData.setItemLayout(
                        idx, MarkAreaItemLayout(points: points, allClipped: prev?.allClipped ?? false))
                    let el = areaData.getItemGraphicEl(idx) as? Polygon
                    // el.setShape('points', points);
                    //   `Path.setShape(key:_:)` routes through `PolygonShape.animationSet`, which
                    //   handles the "points" key for `[[Double]]` — a literal mirror of upstream.
                    _ = el?.setShape("points", points)
                }
            }
        }, self)
        // Upstream returns void from an implemented hook == "handled in place, do not dirty".
        return false
    }

    // renderSeries(seriesModel, maModel, ecModel, api)
    public override func renderSeries(
        _ seriesModel: SeriesModel,
        _ maModel: MarkerModel,
        _ ecModel: GlobalModel,
        _ api: ExtensionAPI
    ) {
        // `maModel` is a MarkAreaModel (the base MarkerView.render narrows the per-series model).
        let maModel = maModel as! MarkAreaModel
        let coordSys = seriesModel.coordinateSystem as? CoordinateSystem
        let seriesId = seriesModel.id
        let seriesData = seriesModel.getData()

        let areaGroupMap = self.markerGroupMap!
        // const polygonGroup = areaGroupMap.get(seriesId) || areaGroupMap.set(seriesId, {group: new graphic.Group()});
        let polygonGroup: MarkAreaDrawGroup
        if let existing = areaGroupMap.get(seriesId) as? MarkAreaDrawGroup {
            polygonGroup = existing
        }
        else {
            polygonGroup = MarkAreaDrawGroup(group: Group())
            _ = areaGroupMap.set(seriesId, polygonGroup)
        }

        _ = self.group.add(polygonGroup.group)
        self.markKeep(polygonGroup)

        let areaData = createList(coordSys, seriesModel, maModel)

        // Line data for tooltip and formatter
        maModel.setData(areaData)

        // Update visual and layout of line
        areaData.each { args in
            let idx = Int((args[0] as? Double) ?? 0)
            // Layout
            let points = util.map(dimPermutations) { dim, _ in
                return getSingleMarkerEndPoint(areaData, idx, dim, seriesModel, api)
            }
            // const overlapped = ... — cartesian extent overlap test.
            var overlapped = true
            // PORT-NOTE (deferred): the overlap test reads `coordSys.getAxis('x'|'y').scale`, dispatched on
            //   the concrete Cartesian2D (the protocol getAxis returns nil); polar is out of static-render
            //   scope. When not cartesian, treat the area as overlapped so it still renders.
            if let cartesian = coordSys as? Cartesian2D {
                let xAxisScale = cartesian.getAxis("x")!.scale
                let yAxisScale = cartesian.getAxis("y")!.scale
                let xAxisExtent = xAxisScale.getExtent()
                let yAxisExtent = yAxisScale.getExtent()
                // NOTE: `get(...) ?? Double.nan` unwraps the Optional (an `Any?` boxed as `Any` would
                //   carry the Optional and break `scale.parse`'s numeric coercion).
                var xPointExtent = [
                    xAxisScale.parse(areaData.get("x0", idx) ?? Double.nan),
                    xAxisScale.parse(areaData.get("x1", idx) ?? Double.nan)
                ]
                var yPointExtent = [
                    yAxisScale.parse(areaData.get("y0", idx) ?? Double.nan),
                    yAxisScale.parse(areaData.get("y1", idx) ?? Double.nan)
                ]
                // numberUtil.asc(xPointExtent); numberUtil.asc(yPointExtent);
                xPointExtent = number.asc(xPointExtent)
                yPointExtent = number.asc(yPointExtent)
                overlapped = !(xAxisExtent[0] > xPointExtent[1] || xAxisExtent[1] < xPointExtent[0]
                    || yAxisExtent[0] > yPointExtent[1] || yAxisExtent[1] < yPointExtent[0])
            }
            // If none of the area is inside coordSys, allClipped is set to be true
            // in layout so that label will not be displayed. See #12591
            let allClipped = !overlapped
            areaData.setItemLayout(idx, MarkAreaItemLayout(points: points, allClipped: allClipped))

            let itemModel = areaData.getItemModel(idx)
            var style = itemModel.getModel("itemStyle").getItemStyle()
            let z2 = itemModel.get("z2")
            // const color = getVisualFromData(seriesData, 'color') as ZRColor;
            let color = getVisualFromData(seriesData, "color")
            // if (!style.fill) { style.fill = color; if (isString(style.fill)) style.fill = colorUtil.modifyAlpha(style.fill, 0.4); }
            if style["fill"] == nil {
                style["fill"] = color
                if util.isString(style["fill"]) {
                    // colorUtil.modifyAlpha(style.fill, 0.4)
                    style["fill"] = ZRenderKit.color.modifyAlpha(style["fill"] as! String, 0.4)
                }
            }
            // if (!style.stroke) { style.stroke = color; }
            if style["stroke"] == nil {
                style["stroke"] = color
            }
            // Visual
            areaData.setItemVisual(idx, "style", style)
            // areaData.setItemVisual(idx, 'z2', retrieve2(z2, 0));
            areaData.setItemVisual(idx, "z2", (util.retrieve2(z2 as? Double, 0.0) ?? 0) as Any)
        }

        areaData.diff(inner(polygonGroup).data)
            .add({ idx in
                // PORT-NOTE: `as?` + guard (not a force cast) so a foreign layout value degrades to
                //   "skip this item" instead of trapping (upstream's untyped `layout` cannot trap).
                guard let layout = areaData.getItemLayout(idx) as? MarkAreaItemLayout else { return }
                let z2 = areaData.getItemVisual(idx, "z2")
                if !layout.allClipped {
                    // const polygon = new graphic.Polygon({ z2: retrieve2(z2, 0), shape: { points: layout.points } });
                    let polygon = Polygon([
                        "z2": (util.retrieve2(z2 as? Double, 0.0) ?? 0),
                        "shape": makeMarkAreaPolygonShape(layout.points) as PathShape
                    ])
                    areaData.setItemGraphicEl(idx, polygon)
                    _ = polygonGroup.group.add(polygon)
                }
            })
            .update({ newIdx, oldIdx in
                var polygon = inner(polygonGroup).data?.getItemGraphicEl(oldIdx) as? Polygon
                guard let layout = areaData.getItemLayout(newIdx) as? MarkAreaItemLayout else { return }
                let z2 = areaData.getItemVisual(newIdx, "z2")
                if !layout.allClipped {
                    if let polygon = polygon {
                        // graphic.updateProps(polygon, { z2: retrieve2(z2, 0), shape: { points: layout.points } }, maModel, newIdx);
                        // PORT-NOTE: the real ported `updateProps` (animation/basicTransition) animates
                        //   the polygon to its new points/z2 when the model has animation enabled, else
                        //   sets them instantly. `shape` is a partial `[String: Any]` (not the typed
                        //   PolygonShape) so `animateToShallow` recurses per-field and the `points`
                        //   array tweens — same seam as BarView's `rectShapeAnimShape`.
                        updateProps(polygon, [
                            "z2": (util.retrieve2(z2 as? Double, 0.0) ?? 0),
                            "shape": ["points": layout.points] as [String: Any]
                        ], maModel, newIdx)
                    }
                    else {
                        polygon = Polygon([
                            "shape": makeMarkAreaPolygonShape(layout.points) as PathShape
                        ])
                    }
                    areaData.setItemGraphicEl(newIdx, polygon)
                    _ = polygonGroup.group.add(polygon)
                }
                else if let polygon = polygon {
                    _ = polygonGroup.group.remove(polygon)
                }
            })
            .remove({ idx in
                let polygon = inner(polygonGroup).data?.getItemGraphicEl(idx)
                // polygonGroup.group.remove(polygon);  (no-op if undefined)
                if let polygon = polygon {
                    _ = polygonGroup.group.remove(polygon)
                }
            })
            .execute()

        areaData.eachItemGraphicEl({ el, idx in
            let polygon = el as! Polygon
            let itemModel = areaData.getItemModel(idx)
            let style = areaData.getItemVisual(idx, "style")
            // polygon.useStyle(areaData.getItemVisual(idx, 'style'));
            // PORT-NOTE (deferred): the item visual 'style' is a `[String: Any]` bag; bridge it to the typed
            //   `PathStyleProps` via the shared `barStyleFromDict` seam (BarView.swift). This is what
            //   fills/strokes the area. Gradient/pattern fills are not bridged yet.
            polygon.useStyle(barStyleFromDict(style))

            // upstream (MarkAreaView.ts:388-390): the area polygon's hover wiring — emphasis/blur/
            //   select state styles + the highDown-dispatcher mark (focus/blurScope are not options
            //   on markArea; upstream passes null/null).
            states.setStatesStylesFromModel(polygon, itemModel)
            let emphasisDisabled = (itemModel.get(["emphasis", "disabled"]) as? Bool) ?? false
            states.toggleHoverEmphasis(polygon, nil, nil, emphasisDisabled)

            // setLabelStyle(polygon, getLabelStatesModels(itemModel), { labelFetcher: maModel,
            //     labelDataIndex: idx, defaultText: areaData.getName(idx) || '',
            //     inheritColor: isString(style.fill) ? colorUtil.modifyAlpha(style.fill, 1) : tokens.color.neutral99 });
            let styleDict = style as? [String: Any]
            let inheritColor: String
            if let fill = styleDict?["fill"] as? String {
                inheritColor = ZRenderKit.color.modifyAlpha(fill, 1) ?? fill
            }
            else {
                inheritColor = tokens.color.neutral99
            }
            var labelOpt = SetLabelStyleOpt()
            labelOpt.labelFetcher = maModel
            labelOpt.labelDataIndex = Double(idx)
            labelOpt.defaultText = areaData.getName(idx)
            labelOpt.inheritColor = inheritColor
            labelStyle.setLabelStyle(
                polygon,
                labelStyle.getLabelStatesModels(itemModel),
                labelOpt
            )

            // getECData(polygon).dataModel = maModel;
            // PORT-NOTE: `MarkAreaModel` conforms to `DataModel` (inherited from `MarkerModel`, see
            //   MarkerModel.swift), so `ECData.dataModel` (typed `DataModel?`) accepts `maModel`
            //   directly. Upstream tags the polygon only (no traverse).
            innerStore.getECData(polygon).dataModel = maModel
        })

        inner(polygonGroup).data = areaData

        // polygonGroup.group.silent = maModel.get('silent') || seriesModel.get('silent');
        polygonGroup.group.silent = jsTruthy((maModel as Model).get("silent"))
            || jsTruthy((seriesModel as Model).get("silent"))
    }
}

// function createList(coordSys, seriesModel, maModel): SeriesData
private func createList(
    _ coordSys: CoordinateSystem?,
    _ seriesModel: SeriesModel,
    _ maModel: MarkAreaModel
) -> SeriesData {

    let areaData: SeriesData
    var dataDims: [SeriesDimensionDefine]
    let dims = ["x0", "y0", "x1", "y1"]
    if let coordSys = coordSys {
        // const coordDimsInfos = map(coordSys.dimensions, function (coordDim) { ... });
        let coordDimsInfos: [SeriesDimensionDefine] = util.map(coordSys.dimensions) { coordDim, _ in
            let data = seriesModel.getData()
            // const info = data.getDimensionInfo(data.mapDimension(coordDim)) || {} as SeriesDimensionDefine;
            let info = data.getDimensionInfo(data.mapDimension(coordDim) ?? "")
            // In map series data don't have lng and lat dimension. Fallback to same with coordSys
            // return extend(extend({}, info), { name: coordDim, ordinalMeta: null });
            let out = SeriesDimensionDefine(info)
            out.name = coordDim
            // DON'T use ordinalMeta to parse and collect ordinal.
            out.ordinalMeta = nil
            return out
        }
        // dataDims = map(dims, (dim, idx) => ({ name: dim, type: coordDimsInfos[idx % 2].type }));
        dataDims = util.map(dims) { dim, idx in
            let d = SeriesDimensionDefine()
            d.name = dim
            d.type = coordDimsInfos[idx % 2].type
            return d
        }
        areaData = SeriesData(dataDims, maModel)
    }
    else {
        // dataDims = [{ name: 'value', type: 'float' }];
        let d = SeriesDimensionDefine()
        d.name = "value"
        d.type = .float
        dataDims = [d]
        areaData = SeriesData(dataDims, maModel)
    }

    // let optData = map(maModel.get('data'), curry(markAreaTransform, seriesModel, coordSys, maModel));
    var optData: [MarkAreaMergedItemOption?] = util.map((maModel as Model).get("data") as? [Any?]) { item, _ in
        return markAreaTransform(seriesModel, coordSys, maModel, item)
    }
    if coordSys != nil {
        // optData = filter(optData, curry(markAreaFilter, coordSys));
        optData = util.filter(optData) { item, _ in
            // PORT-NOTE: upstream passes every mapped entry (including the `undefined` produced by 1D
            //   items) straight to `markAreaFilter`, which would then read `undefined.coord`. Nil
            //   entries are dropped here (see the 1D POTENTIAL-BUG in `markAreaTransform`).
            guard let item = item else { return false }
            return markAreaFilter(coordSys!, item)
        }
    }

    // const dimValueGetter: markerHelper.MarkerDimValueGetter<MarkAreaMergedItemOption> = coordSys ? ... : ...;
    //   The SeriesData/DataStore `DimValueGetter` prepends a `store` param (dropped by upstream's
    //   marker getter, which only reads item/dimIndex).
    let dimValueGetter: DimValueGetter = (coordSys != nil)
        ? { _, item, _, _, dimIndex in
            // const rawVal = item.coord[Math.floor(dimIndex / 2)][dimIndex % 2];
            let itemDict = item as? MarkAreaMergedItemOption
            let coord = (itemDict?["coord"] as? [[Any?]]) ?? [[nil, nil], [nil, nil]]
            let di = Int(dimIndex)
            let rawVal = coord[Int(floor(Double(di) / 2))][di % 2]
            return dataValueHelper.parseDataValue(rawVal, ParseDataValueOpt(type: dataDims[di].type)) as ParsedValue
        }
        : { _, item, _, _, dimIndex in
            let itemDict = item as? MarkAreaMergedItemOption
            return dataValueHelper.parseDataValue(itemDict?["value"], ParseDataValueOpt(type: dataDims[Int(dimIndex)].type)) as ParsedValue
        }
    // areaData.initData(optData, null, dimValueGetter);
    areaData.initData(optData.map { $0 as Any? }, nil, dimValueGetter)
    areaData.hasItemOption = true
    return areaData
}

// export default MarkAreaView;  -> `public final class MarkAreaView` above.

// ================================================================================================
// PORT-NOTE helpers — NOT part of MarkAreaView.ts upstream. These reproduce out-of-phase sibling APIs
// referenced above so the static markArea render compiles. Delete each when its real sibling lands.
// ================================================================================================

// upstream: `interface MarkAreaMergedItemOption['layout']` is the `{points, allClipped}` object literal
//   stored via `setItemLayout`. Modeled as a typed struct (value data, no identity; CONVENTIONS §4).
struct MarkAreaItemLayout {
    var points: [[Double]]
    var allClipped: Bool
}

// Build a `PolygonShape` from `number[][]` points (the `{ shape: { points } }` opt at the Polygon
//   construction / update sites).
private func makeMarkAreaPolygonShape(_ points: [[Double]]) -> PolygonShape {
    var s = PolygonShape()
    s.points = points.map { VectorArray($0.count > 0 ? $0[0] : 0, $0.count > 1 ? $0[1] : 0) }
    return s
}

// PORT-NOTE (deferred): faithful minimal reproduction of `visual/helper.getVisualFromData`. Only the `'color'`
//   case used here is populated (returns `style[data.getVisual('drawType')]`); the opacity/symbol/…
//   cases live in visual/helper.ts. Delete when visual/helper.swift lands and call it directly.
private func getVisualFromData(_ data: SeriesData, _ key: String) -> Any? {
    switch key {
    case "color":
        // const style = data.getVisual('style'); return style[data.getVisual('drawType')];
        //   (drawType defaults to 'fill' — mirrors the sibling MarkPointView/MarkLineView shims.)
        let style = data.getVisual("style") as? [String: Any]
        let drawType = (data.getVisual("drawType") as? String) ?? "fill"
        return style?[drawType]
    case "opacity":
        return (data.getVisual("style") as? [String: Any])?["opacity"]
    case "symbol", "symbolSize", "liftZ":
        return data.getVisual(key)
    default:
        // if (__DEV__) { console.warn(`Unknown visual type ${key}`); }
        return nil
    }
}

// upstream marker dim option items are `[String: Any]` dicts; convert to the `MarkerPositionOption`
//   struct expected by `markerHelper.dataTransform` (per the MarkerModel.swift note that the per-type
//   views perform this conversion before handing items to markerHelper).
private func markAreaPositionOption(_ dict: [String: Any]) -> MarkerPositionOption {
    var o = MarkerPositionOption()
    o.x = dict["x"]
    o.y = dict["y"]
    o.relativeTo = dict["relativeTo"] as? String
    if let c = dict["coord"] as? [Any?] {
        o.coord = c
    }
    else if let c = dict["coord"] as? [Any] {
        o.coord = c.map { $0 as Any? }
    }
    o.xAxis = dict["xAxis"]
    o.yAxis = dict["yAxis"]
    o.radiusAxis = dict["radiusAxis"]
    o.angleAxis = dict["angleAxis"]
    o.type = (dict["type"] as? String).flatMap { MarkerStatisticType(rawValue: $0) }
    o.valueIndex = dict["valueIndex"] as? Double
    o.valueDim = dict["valueDim"] as? String
    o.value = dict["value"]
    return o
}

/// JS truthiness for the dynamic option bag (`x || y` on `get(...)` results). (CONVENTIONS §6.)
private func jsTruthy(_ v: Any?) -> Bool {
    guard let v = v else { return false }
    if let b = v as? Bool { return b }
    if let d = v as? Double { return d != 0 && !d.isNaN }
    if let i = v as? Int { return i != 0 }
    if let s = v as? String { return !s.isEmpty }
    return true
}
