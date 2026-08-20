// Ported from echarts/src/component/helper/BrushTargetManager.ts — keep in sync with upstream
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

// import { each, indexOf, curry, assert, map, createHashMap } from 'zrender/src/core/util';  -> `util` / `createHashMap`
// import * as graphic from '../../util/graphic';        -> BoundingRect (ZRenderKit)
// import * as brushHelper from './brushHelper';         -> brushHelper.swift (makeRectPanelClipPath/...)
// import { BrushPanelConfig, BrushControllerEvents, BrushType, BrushAreaRange, BrushDimensionMinMax }
//     from './BrushController';                         -> BrushController.swift
// import ExtensionAPI from '../../core/ExtensionAPI';   -> ExtensionAPI
// import GridModel from '../../coord/cartesian/GridModel';  -> GridModel
// import GeoModel from '../../coord/geo/GeoModel';          -> GeoModel
// import Cartesian2D from '../../coord/cartesian/Cartesian2D';  -> Cartesian2D
// import Geo from '../../coord/geo/Geo';                        -> Geo
// import { BrushAreaParam, BrushAreaParamInternal } from '../brush/BrushModel';  -> [String: Any]
// import { ModelFinderObject, parseFinder as modelUtilParseFinder, ParsedModelFinderKnown,
//     initExtentForUnion } from '../../util/model';     -> model.parseFinder / model.initExtentForUnion
// import { viewCoordSysCopyBoundingRect, viewCoordSysCopyOverallMatrix } from '../../coord/View';
// import { boundingRectApplyTransform } from 'zrender/src/core/BoundingRect';

// type COORD_CONVERTS_INDEX = 0 | 1;
typealias COORD_CONVERTS_INDEX = Int

// FIXME
// how to genarialize to more coordinate systems.
let INCLUDE_FINDER_MAIN_TYPES = [
    "grid", "xAxis", "yAxis", "geo", "graph",
    "polar", "radiusAxis", "angleAxis", "bmap"
]

// type BrushableCoordinateSystem = Cartesian2D | Geo;
//
// PORT-NOTE: an untagged TS union of two unrelated classes whose ported `dataToPoint`/`pointToData`
//   signatures differ (Cartesian2D takes the erased `CoordinateSystemDataCoord` + `opt: Any?`; Geo takes
//   `Any?` + `noRoam` and returns an Optional). Modeled as a tagged enum so the upstream call sites stay
//   byte-identical (`coordSys.dataToPoint(range, clamp)`), with the per-case shim inside. NOTE the
//   upstream quirk this preserves: `coordConvert` passes `clamp` into geo's 2nd parameter, which geo names
//   `noRoam`/`reserved` — it is never `true` on the geo path (`clamp: true` is only passed by
//   `matchOutputRanges`, i.e. pointToData, whose geo arg is `reserved` and ignored).
public enum BrushableCoordinateSystem {
    case cartesian2D(Cartesian2D)
    case geo(Geo)

    func dataToPoint(_ data: [Double], _ clamp: Bool? = nil) -> [Double] {
        switch self {
        case .cartesian2D(let cartesian):
            return cartesian.dataToPoint(data as CoordinateSystemDataCoord, clamp)
        case .geo(let geo):
            return geo.dataToPoint(data, nil) ?? [Double.nan, Double.nan]
        }
    }

    func pointToData(_ point: [Double], _ clamp: Bool? = nil) -> [Double] {
        switch self {
        case .cartesian2D(let cartesian):
            return (cartesian.pointToData(point, clamp) as? [Double]) ?? [Double.nan, Double.nan]
        case .geo(let geo):
            return geo.pointToData(point) ?? [Double.nan, Double.nan]
        }
    }

    /// `indexOf(targetInfo.coordSyses, seriesModel.coordinateSystem) >= 0` — reference identity.
    var asObject: AnyObject {
        switch self {
        case .cartesian2D(let c): return c
        case .geo(let g): return g
        }
    }

    // `assert(coordSys.type === 'cartesian2d', 'lineX/lineY brush is available only in cartesian2d.')`
    var asCartesian2D: Cartesian2D? {
        if case .cartesian2D(let c) = self { return c }
        return nil
    }
}

/**
 * There can be multiple axes in a single targetInfo. Consider the case
 * of `grid` component, a targetInfo represents a grid which contains one or more
 * cartesian and one or more axes. And consider the case of parallel system,
 * which has multiple axes in a coordinate system.
 */
// interface BrushTargetInfo { panelId; coordSysModel; coordSys; coordSyses; getPanelRect; }
// export interface BrushTargetInfoCartesian2D extends BrushTargetInfo { gridModel; xAxisDeclared; yAxisDeclared; }
// export interface BrushTargetInfoGeo extends BrushTargetInfo { geoModel; }
//   PORT-NOTE: the two subtypes are folded into ONE class with the union of their fields (the builders
//   set the relevant ones; `targetInfoMatchers` reads `gridModel`/`geoModel` back and a nil field simply
//   fails that matcher — the same behavior as upstream's `targetInfo as BrushTargetInfoGeo` cast on a
//   grid target, which yields `undefined`).
public final class BrushTargetInfo {
    public var panelId: String
    public var coordSysModel: ComponentModel
    // Use the first one as the representitive coordSys.
    // A representitive cartesian in grid (first cartesian by default).
    public var coordSys: BrushableCoordinateSystem
    // All cartesians.
    public var coordSyses: [BrushableCoordinateSystem]
    public var getPanelRect: () -> BoundingRect

    // BrushTargetInfoCartesian2D
    public var gridModel: GridModel?
    public var xAxisDeclared: Bool = false
    public var yAxisDeclared: Bool = false
    // BrushTargetInfoGeo
    public var geoModel: GeoModel?

    init(
        panelId: String,
        coordSysModel: ComponentModel,
        coordSys: BrushableCoordinateSystem,
        coordSyses: [BrushableCoordinateSystem],
        getPanelRect: @escaping () -> BoundingRect
    ) {
        self.panelId = panelId
        self.coordSysModel = coordSysModel
        self.coordSys = coordSys
        self.coordSyses = coordSyses
        self.getPanelRect = getPanelRect
    }
}

/// `findTargetInfo` returns `BrushTargetInfo | true` — an object (a coord found) or `true` (global found).
///   PORT-NOTE: the `| true` arm of the union becomes the `.global` case (CONVENTIONS §2).
public enum BrushTargetInfoOrGlobal {
    case targetInfo(BrushTargetInfo)
    case global      // upstream: `true`
}

// class BrushTargetManager
public final class BrushTargetManager {

    // private _targetInfoList: BrushTargetInfo[] = [];
    private var _targetInfoList: [BrushTargetInfo] = []

    /**
     * @param finder contains Index/Id/Name of xAxis/yAxis/geo/grid
     *        Each can be {number|Array.<number>}. like: {xAxisIndex: [3, 4]}
     * @param opt.include include coordinate system types.
     */
    // constructor(finder: ModelFinderObject, ecModel: GlobalModel, opt?: {include?: BrushTargetBuilderKey[]})
    public init(
        _ finder: ModelFinderObject,
        _ ecModel: GlobalModel,
        include: [String]? = nil
    ) {
        let foundCpts = brushParseFinder(ecModel, finder)

        // each(targetInfoBuilders, (builder, type) => {
        //     if (!opt || !opt.include || indexOf(opt.include, type) >= 0) { builder(foundCpts, this._targetInfoList); }
        // });
        for type in targetInfoBuilderKeys {
            if include == nil || include!.contains(type) {
                targetInfoBuilders[type]!(foundCpts, &self._targetInfoList)
            }
        }
    }

    // setOutputRanges(areas, ecModel): BrushAreaParam[]
    @discardableResult
    public func setOutputRanges(
        _ areas: [BrushControllerBrushArea],
        _ ecModel: GlobalModel
    ) -> [[String: Any]] {
        // PORT-NOTE: upstream MUTATES the incoming area objects (`area.coordRanges.push(...)`,
        //   `area.coordRange = ...`, `area.__rangeOffset = ...`) and returns the same array. The
        //   controller hands us value-typed `BrushControllerBrushArea` structs, so the decorated areas
        //   are materialized as the `[String: Any]` param bags the `brush` action payload carries
        //   (`BrushAreaParam`), which is what BrushView.dispatchAction sends.
        var out: [[String: Any]] = util.map(areas) { area, _ in
            var bag: [String: Any] = ["brushType": area.brushType]
            if let panelId = area.panelId { bag["panelId"] = panelId }
            if let range = area.range { bag["range"] = range }
            return bag
        }

        self.matchOutputRanges(areas, ecModel) { areaIndex, area, coordRange, coordSys in
            // (area.coordRanges || (area.coordRanges = [])).push(coordRange);
            var coordRanges = (out[areaIndex]["coordRanges"] as? [Any]) ?? []
            coordRanges.append(coordRange)
            out[areaIndex]["coordRanges"] = coordRanges

            // area.coordRange is the first of area.coordRanges
            if out[areaIndex]["coordRange"] == nil {
                out[areaIndex]["coordRange"] = coordRange
                // In 'category' axis, coord to pixel is not reversible, so we can not
                // rebuild range by coordRange accrately, which may bring trouble when
                // brushing only one item. So we use __rangeOffset to rebuilding range
                // by coordRange. And this it only used in brush component so it is no
                // need to be adapted to coordRanges.
                let result = coordConvert[area.brushType]!(0, coordSys, coordRange, nil)
                out[areaIndex]["__rangeOffset"] = BrushRangeOffset(
                    offset: diffProcessor[area.brushType]!(result.values, area.range, [1, 1]),
                    xyMinMax: result.xyMinMax
                )
            }
        }
        return out
    }

    // matchOutputRanges<T>(areas: T[], ecModel, cb)
    public func matchOutputRanges(
        _ areas: [BrushControllerBrushArea],
        _ ecModel: GlobalModel,
        _ cb: (
            _ areaIndex: Int,
            _ area: BrushControllerBrushArea,
            _ coordRange: BrushAreaRange,
            _ coordSys: BrushableCoordinateSystem
        ) -> Void
    ) {
        util.each(areas) { area, areaIndex in
            // const targetInfo = this.findTargetInfo(area, ecModel);
            var finder: ModelFinderObject = [:]
            if let panelId = area.panelId { finder["panelId"] = panelId }
            let targetInfo = self.findTargetInfo(finder, ecModel)

            // if (targetInfo && targetInfo !== true) { ... }
            guard case .targetInfo(let info) = targetInfo else { return }

            util.each(info.coordSyses) { coordSys, _ in
                // const result = coordConvert[area.brushType](1, coordSys, area.range, true);
                guard let convert = coordConvert[area.brushType], let range = area.range else { return }
                let result = convert(1, coordSys, range, true)
                cb(areaIndex, area, result.values, coordSys)
            }
        }
    }

    /**
     * the `areas` is `BrushModel.areas`.
     * Called in layout stage.
     * convert `area.coordRange` to global range and set panelId to `area.range`.
     */
    // setInputRanges(areas: BrushAreaParamInternal[], ecModel): void
    //   PORT-NOTE: upstream mutates each area object in place; `BrushAreaParamInternal` is a Swift
    //   dictionary (value type), so the array is taken `inout` and each entry written back.
    public func setInputRanges(_ areas: inout [BrushAreaParamInternal], _ ecModel: GlobalModel) {
        for i in areas.indices {
            let area = areas[i]
            let targetInfo = self.findTargetInfo(area, ecModel)

            // if (__DEV__) {
            //     assert(!targetInfo || targetInfo === true || area.coordRange, 'coordRange must be
            //         specified when coord index specified.');
            //     assert(!targetInfo || targetInfo !== true || area.range, 'range must be specified in
            //         global brush.');
            // }

            // area.range = area.range || [];
            if areas[i]["range"] == nil {
                areas[i]["range"] = [[Double]]()
            }

            // convert coordRange to global range and set panelId.
            guard case .targetInfo(let info) = targetInfo else { continue }

            areas[i]["panelId"] = info.panelId
            // (1) area.range should always be calculate from coordRange but does
            // not keep its original value, for the sake of the dataZoom scenario,
            // where area.coordRange remains unchanged but area.range may be changed.
            // (2) Only support converting one coordRange to pixel range in brush
            // component. So do not consider `coordRanges`.
            // (3) About __rangeOffset, see comment above.
            let brushType = (area["brushType"] as? BrushType) ?? ""
            guard let convert = coordConvert[brushType], let coordRange = area["coordRange"] else {
                continue
            }
            let result = convert(0, info.coordSys, coordRange, nil)
            let rangeOffset = area["__rangeOffset"] as? BrushRangeOffset
            areas[i]["range"] = rangeOffset != nil
                ? diffProcessor[brushType]!(
                    result.values,
                    rangeOffset!.offset,
                    getScales(result.xyMinMax, rangeOffset!.xyMinMax)
                )
                : result.values
        }
    }

    // makePanelOpts(api, getDefaultBrushType?): BrushPanelConfig[]
    public func makePanelOpts(
        _ api: ExtensionAPI,
        _ getDefaultBrushType: ((_ targetInfo: BrushTargetInfo) -> BrushType)? = nil
    ) -> [BrushPanelConfig] {
        return util.map(self._targetInfoList) { targetInfo, _ in
            let rect = targetInfo.getPanelRect()
            return BrushPanelConfig(
                panelId: targetInfo.panelId,
                clipPath: makeRectPanelClipPath(rect),
                isTargetByCursor: makeRectIsTargetByCursor(rect, api, targetInfo.coordSysModel),
                defaultBrushType: getDefaultBrushType != nil ? getDefaultBrushType!(targetInfo) : nil,
                getLinearBrushOtherExtent: makeLinearBrushOtherExtent(rect)
            )
        }
    }

    // controlSeries(area, seriesModel, ecModel): boolean
    public func controlSeries(
        _ area: BrushAreaParamInternal,
        _ seriesModel: SeriesModel,
        _ ecModel: GlobalModel
    ) -> Bool {
        // Check whether area is bound in coord, and series do not belong to that coord.
        // If do not do this check, some brush (like lineX) will controll all axes.
        let targetInfo = self.findTargetInfo(area, ecModel)

        // return targetInfo === true
        //     || (targetInfo && indexOf(targetInfo.coordSyses, seriesModel.coordinateSystem) >= 0);
        switch targetInfo {
        case .global:
            return true
        case .targetInfo(let info):
            guard let seriesCoordSys = seriesModel.coordinateSystem as AnyObject? else { return false }
            return info.coordSyses.contains { $0.asObject === seriesCoordSys }
        }
    }

    /**
     * If return Object, a coord found.
     * If return true, global found.
     * Otherwise nothing found.
     */
    // findTargetInfo(area: ModelFinderObject & {panelId?: string}, ecModel): BrushTargetInfo | true
    public func findTargetInfo(
        _ area: ModelFinderObject,
        _ ecModel: GlobalModel
    ) -> BrushTargetInfoOrGlobal {
        let targetInfoList = self._targetInfoList
        let foundCpts = brushParseFinder(ecModel, area)

        for i in 0..<targetInfoList.count {
            let targetInfo = targetInfoList[i]
            let areaPanelId = area["panelId"] as? String
            if let areaPanelId = areaPanelId {
                if targetInfo.panelId == areaPanelId {
                    return .targetInfo(targetInfo)
                }
            }
            else {
                for j in 0..<targetInfoMatchers.count {
                    if targetInfoMatchers[j](foundCpts, targetInfo) {
                        return .targetInfo(targetInfo)
                    }
                }
            }
        }

        return .global
    }
}

// function formatMinMax(minMax: BrushDimensionMinMax): BrushDimensionMinMax
private func formatMinMax(_ minMax: BrushDimensionMinMax) -> BrushDimensionMinMax {
    // minMax[0] > minMax[1] && minMax.reverse();
    var minMax = minMax
    if minMax[0] > minMax[1] {
        minMax.reverse()
    }
    return minMax
}

// function parseFinder(ecModel, finder): ParsedModelFinderKnown
private func brushParseFinder(_ ecModel: GlobalModel, _ finder: ModelFinder) -> ParsedModelFinderKnown {
    return model.parseFinder(
        ecModel, finder, ParseFinderOpt(includeMainTypes: INCLUDE_FINDER_MAIN_TYPES)
    )
}

/// upstream: `area.__rangeOffset = {offset, xyMinMax}`
public final class BrushRangeOffset {
    public var offset: BrushAreaRange
    public var xyMinMax: [BrushDimensionMinMax]
    init(offset: BrushAreaRange, xyMinMax: [BrushDimensionMinMax]) {
        self.offset = offset
        self.xyMinMax = xyMinMax
    }
}

// type TargetInfoBuilder = (foundCpts, targetInfoList) => void;
// const targetInfoBuilders: Record<BrushTargetBuilderKey, TargetInfoBuilder>
//   type BrushTargetBuilderKey = 'grid' | 'geo';  (the iteration order matters -> keep an explicit key list)
private let targetInfoBuilderKeys = ["grid", "geo"]
private let targetInfoBuilders: [String: (ParsedModelFinderKnown, inout [BrushTargetInfo]) -> Void] = [

    "grid": { foundCpts, targetInfoList in
        let xAxisModels = (foundCpts["xAxisModels"] as? [ComponentModel]) ?? []
        let yAxisModels = (foundCpts["yAxisModels"] as? [ComponentModel]) ?? []
        let gridModels = (foundCpts["gridModels"] as? [ComponentModel]) ?? []
        // Remove duplicated.
        var gridModelMap: [String: GridModel] = [:]
        var gridModelOrder: [String] = []
        var xAxesHas: [String: Bool] = [:]
        var yAxesHas: [String: Bool] = [:]

        // if (!xAxisModels && !yAxisModels && !gridModels) { return; }
        if foundCpts["xAxisModels"] == nil && foundCpts["yAxisModels"] == nil && foundCpts["gridModels"] == nil {
            return
        }

        func setGrid(_ gridModel: GridModel) {
            if gridModelMap[gridModel.id] == nil {
                gridModelMap[gridModel.id] = gridModel
                gridModelOrder.append(gridModel.id)
            }
        }

        // each(xAxisModels, axisModel => { const gridModel = axisModel.axis.grid.model; ... });
        util.each(xAxisModels) { axisModel, _ in
            guard let axis = (axisModel as? AxisBaseModel)?.axis as? Axis2D,
                  let gridModel = axis.grid?.model as? GridModel else { return }
            setGrid(gridModel)
            xAxesHas[gridModel.id] = true
        }
        util.each(yAxisModels) { axisModel, _ in
            guard let axis = (axisModel as? AxisBaseModel)?.axis as? Axis2D,
                  let gridModel = axis.grid?.model as? GridModel else { return }
            setGrid(gridModel)
            yAxesHas[gridModel.id] = true
        }
        util.each(gridModels) { gridModel, _ in
            guard let gridModel = gridModel as? GridModel else { return }
            setGrid(gridModel)
            xAxesHas[gridModel.id] = true
            yAxesHas[gridModel.id] = true
        }

        // gridModelMap.each(gridModel => { ... });
        for id in gridModelOrder {
            let gridModel = gridModelMap[id]!
            guard let grid = gridModel.coordinateSystem as? Grid else { continue }
            var cartesians: [Cartesian2D] = []

            util.each(grid.getCartesians()) { cartesian, _ in
                // if (indexOf(xAxisModels, cartesian.getAxis('x').model) >= 0
                //     || indexOf(yAxisModels, cartesian.getAxis('y').model) >= 0) { cartesians.push(cartesian); }
                let xModel = cartesian.getAxis("x")?.model
                let yModel = cartesian.getAxis("y")?.model
                let inX = xAxisModels.contains { ($0 as AnyObject) === (xModel as AnyObject?) }
                let inY = yAxisModels.contains { ($0 as AnyObject) === (yModel as AnyObject?) }
                if inX || inY {
                    cartesians.append(cartesian)
                }
            }
            // PORT-NOTE: upstream pushes the targetInfo even when `cartesians` is empty (its
            //   `coordSys: cartesians[0]` is then `undefined`). A Swift enum cannot hold that, and a
            //   panel with no cartesian can neither convert nor control any series — skip it. Observable
            //   only for a finder that names a grid whose axes were not matched (nothing to brush there).
            guard let first = cartesians.first else { continue }

            let coordSyses = cartesians.map { BrushableCoordinateSystem.cartesian2D($0) }
            let info = BrushTargetInfo(
                panelId: "grid--" + gridModel.id,
                coordSysModel: gridModel,
                // Use the first one as the representitive coordSys.
                coordSys: .cartesian2D(first),
                coordSyses: coordSyses,
                getPanelRect: { panelRectBuilderGrid(first) }
            )
            info.gridModel = gridModel
            info.xAxisDeclared = xAxesHas[gridModel.id] ?? false
            info.yAxisDeclared = yAxesHas[gridModel.id] ?? false
            targetInfoList.append(info)
        }
    },

    "geo": { foundCpts, targetInfoList in
        let geoModels = (foundCpts["geoModels"] as? [ComponentModel]) ?? []
        util.each(geoModels) { geoModelIn, _ in
            guard let geoModel = geoModelIn as? GeoModel,
                  let coordSys = geoModel.coordinateSystem as? Geo else { return }
            let info = BrushTargetInfo(
                panelId: "geo--" + geoModel.id,
                coordSysModel: geoModel,
                coordSys: .geo(coordSys),
                coordSyses: [.geo(coordSys)],
                getPanelRect: { panelRectBuilderGeo(coordSys) }
            )
            info.geoModel = geoModel
            targetInfoList.append(info)
        }
    }
]

// type TargetInfoMatcher = (foundCpts, targetInfo) => boolean;
// const targetInfoMatchers: TargetInfoMatcher[]
private let targetInfoMatchers: [(ParsedModelFinderKnown, BrushTargetInfo) -> Bool] = [

    // grid
    { foundCpts, targetInfo in
        let xAxisModel = foundCpts["xAxisModel"] as? ComponentModel
        let yAxisModel = foundCpts["yAxisModel"] as? ComponentModel
        var gridModel = foundCpts["gridModel"] as? GridModel

        // !gridModel && xAxisModel && (gridModel = xAxisModel.axis.grid.model);
        if gridModel == nil, let xAxisModel = xAxisModel as? AxisBaseModel {
            gridModel = (xAxisModel.axis as? Axis2D)?.grid?.model as? GridModel
        }
        // !gridModel && yAxisModel && (gridModel = yAxisModel.axis.grid.model);
        if gridModel == nil, let yAxisModel = yAxisModel as? AxisBaseModel {
            gridModel = (yAxisModel.axis as? Axis2D)?.grid?.model as? GridModel
        }

        // return gridModel && gridModel === targetInfo.gridModel;
        return gridModel != nil && gridModel === targetInfo.gridModel
    },

    // geo
    { foundCpts, targetInfo in
        let geoModel = foundCpts["geoModel"] as? GeoModel
        // return geoModel && geoModel === targetInfo.geoModel;
        return geoModel != nil && geoModel === targetInfo.geoModel
    }
]

// type PanelRectBuilder = (this: BrushTargetInfo) => graphic.BoundingRect;
// const panelRectBuilders: Record<BrushTargetBuilderKey, PanelRectBuilder>

// grid: function () { return this.coordSys.master.getRect().clone(); }
//   (grid is not Transformable.)
private func panelRectBuilderGrid(_ coordSys: Cartesian2D) -> BoundingRect {
    guard let grid = coordSys.master as? Grid else { return BoundingRect(0, 0, 0, 0) }
    return grid.getRect().clone()
}

// geo: function () {
//     const viewCoordSys = this.coordSys.view;
//     const rect = viewCoordSysCopyBoundingRect(null, viewCoordSys);
//     boundingRectApplyTransform(rect, rect, viewCoordSysCopyOverallMatrix(null, viewCoordSys));
//     return rect;
// }
private func panelRectBuilderGeo(_ coordSys: Geo) -> BoundingRect {
    let viewCoordSys = coordSys.view!
    let rect = viewCoordSysCopyBoundingRect(nil, viewCoordSys)
    boundingRectApplyTransform(rect, rect, viewCoordSysCopyOverallMatrix(nil, viewCoordSys))
    return rect
}

// type ConvertCoord = (to, coordSys, rangeOrCoordRange, clamp?) => {values: BrushAreaRange, xyMinMax: BrushDimensionMinMax[]};
typealias BrushConvertResult = (values: BrushAreaRange, xyMinMax: [BrushDimensionMinMax])
typealias ConvertCoord = (
    _ to: COORD_CONVERTS_INDEX,
    _ coordSys: BrushableCoordinateSystem,
    _ rangeOrCoordRange: BrushAreaRange,
    _ clamp: Bool?
) -> BrushConvertResult

// const coordConvert: Record<BrushType, ConvertCoord>
let coordConvert: [BrushType: ConvertCoord] = [

    // lineX: curry(axisConvert, 0),
    "lineX": { to, coordSys, rangeOrCoordRange, _ in
        return axisConvert(0, to, coordSys, rangeOrCoordRange)
    },

    // lineY: curry(axisConvert, 1),
    "lineY": { to, coordSys, rangeOrCoordRange, _ in
        return axisConvert(1, to, coordSys, rangeOrCoordRange)
    },

    "rect": { to, coordSys, rangeOrCoordRange, clamp in
        guard let r = brushDimensionMinMaxList(rangeOrCoordRange), r.count >= 2 else {
            return (values: [[Double]](), xyMinMax: [])
        }
        let xminymin = to != 0
            ? coordSys.pointToData([r[0][0], r[1][0]], clamp)
            : coordSys.dataToPoint([r[0][0], r[1][0]], clamp)
        let xmaxymax = to != 0
            ? coordSys.pointToData([r[0][1], r[1][1]], clamp)
            : coordSys.dataToPoint([r[0][1], r[1][1]], clamp)
        let values: [BrushDimensionMinMax] = [
            formatMinMax([xminymin[0], xmaxymax[0]]),
            formatMinMax([xminymin[1], xmaxymax[1]])
        ]
        return (values: values, xyMinMax: values)
    },

    "polygon": { to, coordSys, rangeOrCoordRange, clamp in
        guard let r = brushDimensionMinMaxList(rangeOrCoordRange) else {
            return (values: [[Double]](), xyMinMax: [])
        }
        var xyMinMax: [BrushDimensionMinMax] = [model.initExtentForUnion(), model.initExtentForUnion()]
        let values: [BrushDimensionMinMax] = util.map(r) { item, _ in
            let p = to != 0 ? coordSys.pointToData(item, clamp) : coordSys.dataToPoint(item, clamp)
            xyMinMax[0][0] = Swift.min(xyMinMax[0][0], p[0])
            xyMinMax[1][0] = Swift.min(xyMinMax[1][0], p[1])
            xyMinMax[0][1] = Swift.max(xyMinMax[0][1], p[0])
            xyMinMax[1][1] = Swift.max(xyMinMax[1][1], p[1])
            return p
        }
        return (values: values, xyMinMax: xyMinMax)
    }
]

// function axisConvert(axisNameIndex: 0 | 1, to, coordSys: Cartesian2D, rangeOrCoordRange: BrushDimensionMinMax)
private func axisConvert(
    _ axisNameIndex: Int,
    _ to: COORD_CONVERTS_INDEX,
    _ coordSys: BrushableCoordinateSystem,
    _ rangeOrCoordRange: BrushAreaRange
) -> BrushConvertResult {
    // if (__DEV__) { assert(coordSys.type === 'cartesian2d', 'lineX/lineY brush is available only in cartesian2d.'); }
    //   PORT-NOTE: the DEV assert becomes a hard guard — a lineX/lineY area on a non-cartesian coord
    //   system yields an empty conversion (and so selects nothing) instead of crashing.
    guard let cartesian = coordSys.asCartesian2D,
          let rangeIn = brushDimensionMinMax(rangeOrCoordRange),
          let axis = cartesian.getAxis(["x", "y"][axisNameIndex]) else {
        return (values: [Double](), xyMinMax: [[Double.nan, Double.nan], [Double.nan, Double.nan]])
    }

    let values = formatMinMax(util.map([0, 1]) { i, _ in
        return to != 0
            ? axis.coordToData(axis.toLocalCoord(rangeIn[i]), true)
            : axis.toGlobalCoord(axis.dataToCoord(rangeIn[i]))
    })
    var xyMinMax: [BrushDimensionMinMax] = [[], []]
    xyMinMax[axisNameIndex] = values
    xyMinMax[1 - axisNameIndex] = [Double.nan, Double.nan]

    return (values: values, xyMinMax: xyMinMax)
}


// type DiffProcess = (values, refer, scales) => BrushDimensionMinMax | BrushDimensionMinMax[];
typealias DiffProcess = (
    _ values: BrushAreaRange,
    _ refer: BrushAreaRange?,
    _ scales: [Double]
) -> BrushAreaRange

// const diffProcessor: Record<BrushType, DiffProcess>
let diffProcessor: [BrushType: DiffProcess] = [

    // lineX: curry(axisDiffProcessor, 0),
    "lineX": { values, refer, scales in axisDiffProcessor(0, values, refer, scales) },

    // lineY: curry(axisDiffProcessor, 1),
    "lineY": { values, refer, scales in axisDiffProcessor(1, values, refer, scales) },

    "rect": { values, refer, scales in
        guard let v = brushDimensionMinMaxList(values), let r = brushDimensionMinMaxList(refer),
              v.count >= 2, r.count >= 2 else { return values }
        return [
            [v[0][0] - scales[0] * r[0][0], v[0][1] - scales[0] * r[0][1]],
            [v[1][0] - scales[1] * r[1][0], v[1][1] - scales[1] * r[1][1]]
        ] as [BrushDimensionMinMax]
    },

    "polygon": { values, refer, scales in
        guard let v = brushDimensionMinMaxList(values), let r = brushDimensionMinMaxList(refer) else {
            return values
        }
        return util.map(v) { item, idx -> BrushDimensionMinMax in
            guard idx < r.count else { return item }
            return [item[0] - scales[0] * r[idx][0], item[1] - scales[1] * r[idx][1]]
        }
    }
]

// function axisDiffProcessor(axisNameIndex, values, refer, scales): BrushDimensionMinMax
private func axisDiffProcessor(
    _ axisNameIndex: Int,
    _ values: BrushAreaRange,
    _ refer: BrushAreaRange?,
    _ scales: [Double]
) -> BrushAreaRange {
    guard let v = brushDimensionMinMax(values), let r = brushDimensionMinMax(refer) else { return values }
    return [
        v[0] - scales[axisNameIndex] * r[0],
        v[1] - scales[axisNameIndex] * r[1]
    ] as BrushDimensionMinMax
}

// We have to process scale caused by dataZoom manually,
// although it might be not accurate.
// Return [0~1, 0~1]
// function getScales(xyMinMaxCurr, xyMinMaxOrigin): number[]
private func getScales(_ xyMinMaxCurr: [BrushDimensionMinMax], _ xyMinMaxOrigin: [BrushDimensionMinMax]) -> [Double] {
    let sizeCurr = getSize(xyMinMaxCurr)
    let sizeOrigin = getSize(xyMinMaxOrigin)
    var scales = [sizeCurr[0] / sizeOrigin[0], sizeCurr[1] / sizeOrigin[1]]
    if scales[0].isNaN { scales[0] = 1 }
    if scales[1].isNaN { scales[1] = 1 }
    return scales
}

// function getSize(xyMinMax): number[]
private func getSize(_ xyMinMax: [BrushDimensionMinMax]) -> [Double] {
    // return xyMinMax ? [xyMinMax[0][1] - xyMinMax[0][0], xyMinMax[1][1] - xyMinMax[1][0]] : [NaN, NaN];
    guard xyMinMax.count >= 2, xyMinMax[0].count >= 2, xyMinMax[1].count >= 2 else {
        return [Double.nan, Double.nan]
    }
    return [xyMinMax[0][1] - xyMinMax[0][0], xyMinMax[1][1] - xyMinMax[1][0]]
}

// export default BrushTargetManager;  -> `public final class BrushTargetManager` above.
