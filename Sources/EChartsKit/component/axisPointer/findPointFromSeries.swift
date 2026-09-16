// Ported from echarts/src/component/axisPointer/findPointFromSeries.ts — keep in sync with upstream.
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
// WHAT THIS FILE IS  (Phase 35, TASK 2)
// ============================================================================
// `findPointFromSeries(finder, ecModel)` → the pixel `point: [x, y]` (+ optional graphic `el`) for a
// series datum, resolved through the series' coordinate system `dataToPoint`. It is the data-driven
// position source for a `showTip`/`updateAxisPointer` that carries a `{seriesIndex, dataIndex}` finder
// but no explicit `x`/`y` (upstream `axisTrigger` calls this when `payload.x/y` are illegal — see
// axisTrigger.swift).
//
// import * as zrUtil from 'zrender/src/core/util';           -> ZRenderKit / Swift stdlib map
// import * as modelUtil from '../../util/model';             -> `model` caseless enum (util/modelUtil.swift)
// import GlobalModel from '../../model/Global';              -> GlobalModel (model/Global.swift)
// import Element from 'zrender/src/Element';                 -> ZRenderKit.Element
// import { Payload } from '../../util/types';                -> Payload (util/types.swift)

import Foundation
import ZRenderKit

// upstream: the `finder` param object `{seriesIndex?, dataIndex?, dataIndexInside?, name?, isStacked?}`.
//   `dataIndex`/`dataIndexInside` are `number | number[]`; `name` is `string | string[]` — erased to `Any?`
//   (they flow straight into `modelUtil.queryDataIndex`'s payload-bag lookup).
public struct FindPointFinder {
    public var seriesIndex: Double?
    public var dataIndex: Any?          // number | number[]
    public var dataIndexInside: Any?    // number | number[]
    public var name: Any?               // string | string[]
    public var isStacked: Bool?
    public init(
        seriesIndex: Double? = nil,
        dataIndex: Any? = nil,
        dataIndexInside: Any? = nil,
        name: Any? = nil,
        isStacked: Bool? = nil
    ) {
        self.seriesIndex = seriesIndex
        self.dataIndex = dataIndex
        self.dataIndexInside = dataIndexInside
        self.name = name
        self.isStacked = isStacked
    }
}

/**
 * @param finder contains {seriesIndex, dataIndex, dataIndexInside}
 * @param ecModel
 * @return  {point: [x, y], el: ...} point Will not be null.
 */
// upstream: export default function findPointFromSeries(finder, ecModel): { point: number[], el?: Element }
@discardableResult
public func findPointFromSeries(
    _ finder: FindPointFinder,
    _ ecModel: GlobalModel
) -> (point: [Double], el: Element?) {
    var point: [Double] = []
    let seriesIndex = finder.seriesIndex

    // upstream: if (seriesIndex == null || !(seriesModel = ecModel.getSeriesByIndex(seriesIndex))) return {point: []};
    guard let seriesIndex = seriesIndex,
          let seriesModel = ecModel.getSeriesByIndex(seriesIndex) else {
        return (point: [], el: nil)
    }

    let data = seriesModel.getData()

    // upstream: const dataIndex = modelUtil.queryDataIndex(data, finder as Payload);
    //   `queryDataIndex` reads `dataIndexInside` / `dataIndex` / `name` off the payload bag, so pack the
    //   finder fields into a throwaway `Payload.other`.
    var qp = Payload(type: "")
    if let v = finder.dataIndexInside { qp.other["dataIndexInside"] = v }
    if let v = finder.dataIndex { qp.other["dataIndex"] = v }
    if let v = finder.name { qp.other["name"] = v }
    let dataIndexAny = model.queryDataIndex(data, qp)

    // upstream: if (dataIndex == null || dataIndex < 0 || zrUtil.isArray(dataIndex)) return {point: []};
    if dataIndexAny is [Any] {
        return (point: [], el: nil)
    }
    guard let dataIndexD = fpsAsDouble(dataIndexAny), dataIndexD >= 0 else {
        return (point: [], el: nil)
    }
    let dataIndex = Int(dataIndexD)

    let el = data.getItemGraphicEl(dataIndex)
    let coordSys = seriesModel.coordinateSystem

    // upstream: if (seriesModel.getTooltipPosition) { point = seriesModel.getTooltipPosition(dataIndex) || []; }
    //   TODO: requires a base `SeriesModel.getTooltipPosition` witness. Upstream's is a
    //   declaration-merged optional method; concrete overrides now exist on MapSeries/RadarSeries but with
    //   divergent signatures and no common protocol to dispatch through, and neither uses a cartesian
    //   axisPointer, so this cartesian branch never reaches them. Wire a protocol witness once a
    //   cartesian-coord series (e.g. graph/tree) overrides `getTooltipPosition`.

    // upstream: else if (coordSys && coordSys.dataToPoint) { ... }
    //   The concrete `Cartesian2D` supplies `dataToPoint` / `getBaseAxis` / `getOtherAxis` / `dimensions`.
    //   Narrow to the concrete class (the `getBaseAxis`/`getOtherAxis` protocol witnesses are the
    //   nil-returning defaults — see model/Series.getBaseAxis note — so an `as? CoordinateSystem` cast
    //   would mis-resolve; the concrete cast pins the real methods). Polar is out of current scope.
    if let cartesian = coordSys as? Cartesian2D {
        if finder.isStacked == true {
            let baseAxis = cartesian.getBaseAxis()
            let valueAxis = cartesian.getOtherAxis(baseAxis)
            let valueAxisDim = valueAxis.dim
            let baseAxisDim = baseAxis.dim
            // upstream: const baseDataOffset = valueAxisDim === 'x' || valueAxisDim === 'radius' ? 1 : 0;
            let baseDataOffset = (valueAxisDim == "x" || valueAxisDim == "radius") ? 1 : 0
            let baseDim = data.mapDimension(baseAxisDim)
            // upstream: const stackedData = []; stackedData[baseDataOffset] = data.get(baseDim, dataIndex);
            //   stackedData[1 - baseDataOffset] = data.get(getCalculationInfo('stackResultDimension'), dataIndex);
            var stackedData: [ScaleDataValue] = [Double.nan, Double.nan]
            if let baseDim = baseDim, let v = data.get(baseDim, dataIndex) {
                stackedData[baseDataOffset] = v
            }
            if let stackResultDim = data.getCalculationInfo("stackResultDimension") as? String,
               let v = data.get(stackResultDim, dataIndex) {
                stackedData[1 - baseDataOffset] = v
            }
            // upstream: point = coordSys.dataToPoint(stackedData) || [];
            point = cartesian.dataToPoint(stackedData)
        }
        else {
            // upstream: point = coordSys.dataToPoint(
            //     data.getValues(zrUtil.map(coordSys.dimensions, dim => data.mapDimension(dim)), dataIndex)
            // ) || [];
            // upstream's `zrUtil.map` is length-preserving — a `mapDimension` returning
            //   `undefined` keeps its slot (undefined -> NaN through `getValues`). `compactMap` instead
            //   DROPS a nil slot, which would shorten/misalign the dims array. This is safe here (and only
            //   here) because Cartesian2D's `dimensions` are always ['x','y'], both of which resolve via
            //   `mapDimension`, so no slot is ever nil. `SeriesData.getValues` also takes a non-optional
            //   `[DimensionName]`, so a faithful length-preserving map would require widening that signature;
            //   keep compactMap until a coord system with droppable dims reaches this branch.
            let dims: [DimensionName] = cartesian.dimensions.compactMap { data.mapDimension($0) }
            let values = data.getValues(dims, dataIndex)
            point = cartesian.dataToPoint(values)
        }
    }
    // upstream: else if (el) { const rect = el.getBoundingRect().clone(); rect.applyTransform(el.transform);
    //   point = [rect.x + rect.width / 2, rect.y + rect.height / 2]; }
    else if let el = el, let rect = el.getBoundingRect()?.clone() {
        rect.applyTransform(el.transform)
        point = [rect.x + rect.width / 2, rect.y + rect.height / 2]
    }

    return (point: point, el: el)
}

// fpsAsDouble — coerce a JS-number-ish value (Int or Double) from `queryDataIndex` to Double.
//   (Int-vs-Double option/payload read trap: small indices box as `Int`.)
private func fpsAsDouble(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    return nil
}
