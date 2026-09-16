// Ported from echarts/src/chart/themeRiver/themeRiverLayout.ts — keep in sync with upstream
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

// upstream imports:
//   import * as zrUtil from 'zrender/src/core/util';                 -> ZRenderKit.util (`util.map`).
//   import * as numberUtil from '../../util/number';                 -> `number.*` (util/number.swift).
//   import GlobalModel from '../../model/Global';                    -> GlobalModel (model/Global.swift).
//   import ExtensionAPI from '../../core/ExtensionAPI';              -> ExtensionAPI (core/ExtensionAPI.swift).
//   import ThemeRiverSeriesModel, { SERIES_TYPE_THEME_RIVER, ThemeRiverSeriesOption } from './ThemeRiverSeries';
//       -> ThemeRiverSeriesModel / `SERIES_TYPE_THEME_RIVER` (sibling ThemeRiverSeries.swift); the option
//          type is collapsed to the dynamic bag.
//   import { RectLike } from 'zrender/src/core/BoundingRect';        -> `BoundingRect` (ZRenderKit) — `RectLike`
//       is a plain {x,y,width,height} bag; `single.getRect()` returns a BoundingRect.
//   import SeriesData from '../../data/SeriesData';                  -> SeriesData (data/SeriesData.swift).
//   import { createSimpleOverallStageHandler } from '../../util/model';
//       -> `model.createSimpleOverallStageHandler` (util/modelUtil.swift).

// export interface ThemeRiverLayoutInfo { rect: RectLike; boundaryGap: ThemeRiverSeriesOption['boundaryGap'] }
//   modeled as a `[String: Any]` layout bag ("rect": BoundingRect, "boundaryGap": [Double])
//   written via `data.setLayout('layoutInfo', …)`, mirroring the funnel/pie layout convention.

// export const themeRiverLayoutStageHandler = createSimpleOverallStageHandler(SERIES_TYPE_THEME_RIVER, themeRiverLayout);
// `createSimpleOverallStageHandler` expects a `StageHandlerOverallReset = (GlobalModel, ExtensionAPI,
// Payload?) -> Void`; the upstream `themeRiverLayout` is `(ecModel, api)` (2-arg). Adapt with a thin
// wrapper that drops the (unused) payload, keeping `themeRiverLayout` byte-faithful (2-arg) below
// (same pattern as funnelLayout.swift).
public let themeRiverLayoutStageHandler = model.createSimpleOverallStageHandler(
    SERIES_TYPE_THEME_RIVER,
    { ecModel, api, _ in themeRiverLayout(ecModel, api) }
)

// function themeRiverLayout(ecModel: GlobalModel, api: ExtensionAPI)
// Exposed for the driver to call directly (mirrors funnelLayout), matching upstream's module-private
// `function themeRiverLayout(ecModel, api)`.
public func themeRiverLayout(
    _ ecModel: GlobalModel,
    _ api: ExtensionAPI
) {
    // ecModel.eachSeriesByType(SERIES_TYPE_THEME_RIVER, function (seriesModel: ThemeRiverSeriesModel) { ... });
    ecModel.eachSeriesByType(SERIES_TYPE_THEME_RIVER) { seriesModelBase, _ in
        // upstream typed callback param `seriesModel: ThemeRiverSeriesModel`.
        let seriesModel = seriesModelBase as! ThemeRiverSeriesModel

        // const data = seriesModel.getData();
        let data = seriesModel.getData()

        // const single = seriesModel.coordinateSystem;
        //   coord/single/Single.swift is ported; `coordinateSystem` is the inherited `Any?`
        //   slot, downcast to `Single` here. `Single` exposes getRect() -> BoundingRect,
        //   getAxis() -> SingleAxis (with `.orient`), dataToPoint(_ value) -> [Double].
        let single = seriesModel.coordinateSystem as! Single

        // const layoutInfo = {} as ThemeRiverLayoutInfo;
        var layoutInfo: [String: Any] = [:]

        // use the axis boundingRect for view
        // const rect = single.getRect();
        let rect = single.getRect()

        // layoutInfo.rect = rect;
        layoutInfo["rect"] = rect

        // const boundaryGap = seriesModel.get('boundaryGap');
        //   `(string | number)[]`, e.g. ['10%', '10%']. Read as `[Any]` (option bag).
        var boundaryGap: [Any] = (seriesModel.get("boundaryGap") as? [Any]) ?? []

        // const axis = single.getAxis();
        let axis = single.getAxis()

        // layoutInfo.boundaryGap = boundaryGap;
        //   Upstream aliases the same array into layoutInfo, then mutates boundaryGap[0]/[1] below; the
        //   final stored values are the parsed numerics. Swift arrays are value types, so the mutated
        //   `boundaryGap` is written back into `layoutInfo` after the parse (CONVENTIONS §3).

        // if (axis.orient === 'horizontal') {
        //   `axis.orient` is a SingleAxis field (LayoutOrient); `single.getAxis()` returns
        //   that SingleAxis, so `.orient` resolves against the ported SingleAxis.
        if axis.orient == .horizontal {
            // boundaryGap[0] = numberUtil.parsePercent(boundaryGap[0], rect.height);
            boundaryGap[0] = number.parsePercent(boundaryGap[0], rect.height)
            // boundaryGap[1] = numberUtil.parsePercent(boundaryGap[1], rect.height);
            boundaryGap[1] = number.parsePercent(boundaryGap[1], rect.height)
            // const height = rect.height - boundaryGap[0] - boundaryGap[1];
            let height = rect.height - (boundaryGap[0] as! Double) - (boundaryGap[1] as! Double)
            // doThemeRiverLayout(data, seriesModel, height);
            doThemeRiverLayout(data, seriesModel, height)
        }
        else {
            // boundaryGap[0] = numberUtil.parsePercent(boundaryGap[0], rect.width);
            boundaryGap[0] = number.parsePercent(boundaryGap[0], rect.width)
            // boundaryGap[1] = numberUtil.parsePercent(boundaryGap[1], rect.width);
            boundaryGap[1] = number.parsePercent(boundaryGap[1], rect.width)
            // const width = rect.width - boundaryGap[0] - boundaryGap[1];
            let width = rect.width - (boundaryGap[0] as! Double) - (boundaryGap[1] as! Double)
            // doThemeRiverLayout(data, seriesModel, width);
            doThemeRiverLayout(data, seriesModel, width)
        }

        // (value-type write-back of the mutated boundaryGap alias — see note above)
        layoutInfo["boundaryGap"] = boundaryGap

        // data.setLayout('layoutInfo', layoutInfo);
        data.setLayout("layoutInfo", layoutInfo)
    }
}

/**
 * The layout information about themeriver
 *
 * @param data  data in the series
 * @param seriesModel  the model object of themeRiver series
 * @param height  value used to compute every series height
 */
// function doThemeRiverLayout(data, seriesModel, height)
private func doThemeRiverLayout(
    _ data: SeriesData,
    _ seriesModel: ThemeRiverSeriesModel,
    _ height: Double
) {
    // if (!data.count()) { return; }
    if data.count() == 0 {
        return
    }
    // const coordSys = seriesModel.coordinateSystem;
    let coordSys = seriesModel.coordinateSystem as! Single
    // the data in each layer are organized into a series.
    // const layerSeries = seriesModel.getLayerSeries();
    let layerSeries = seriesModel.getLayerSeries()

    // the points in each layer.
    // const timeDim = data.mapDimension('single');
    let timeDim = data.mapDimension("single")!
    // const valueDim = data.mapDimension('value');
    let valueDim = data.mapDimension("value")!
    // const layerPoints = zrUtil.map(layerSeries, function (singleLayer) {
    //     return zrUtil.map(singleLayer.indices, function (idx) {
    //         const pt = coordSys.dataToPoint(data.get(timeDim, idx));
    //         pt[1] = data.get(valueDim, idx) as number;
    //         return pt;
    //     });
    // });
    let layerPoints: [[[Double]]] = layerSeries.map { singleLayer in
        let indices = (singleLayer["indices"] as? [Int]) ?? []
        return indices.map { idx -> [Double] in
            var pt = coordSys.dataToPoint(data.get(timeDim, idx) as Any)
            pt[1] = trNum(data.get(valueDim, idx))
            return pt
        }
    }

    // const base = computeBaseline(layerPoints);
    let base = computeBaseline(layerPoints)
    // const baseLine = base.y0;
    let baseLine = base.y0
    // const ky = height / base.max;
    let ky = height / base.max

    // set layout information for each item.
    // const n = layerSeries.length;
    let n = layerSeries.count
    // indices per layer (dict-shaped layerSeries — see getLayerSeries).
    let layerIndices: [[Int]] = layerSeries.map { ($0["indices"] as? [Int]) ?? [] }
    // const m = layerSeries[0].indices.length;
    let m = layerIndices[0].count
    // let baseY0;
    var baseY0: Double
    // for (let j = 0; j < m; ++j) {
    for j in 0..<m {
        // baseY0 = baseLine[j] * ky;
        baseY0 = baseLine[j] * ky
        // data.setItemLayout(layerSeries[0].indices[j], { layerIndex: 0, x, y0, y });
        data.setItemLayout(layerIndices[0][j], [
            "layerIndex": 0.0,
            "x": layerPoints[0][j][0],
            "y0": baseY0,
            "y": layerPoints[0][j][1] * ky
        ] as [String: Any])
        // for (let i = 1; i < n; ++i) {
        for i in 1..<n {
            // baseY0 += layerPoints[i - 1][j][1] * ky;
            baseY0 += layerPoints[i - 1][j][1] * ky
            // data.setItemLayout(layerSeries[i].indices[j], { layerIndex: i, x, y0, y });
            data.setItemLayout(layerIndices[i][j], [
                "layerIndex": Double(i),
                "x": layerPoints[i][j][0],
                "y0": baseY0,
                "y": layerPoints[i][j][1] * ky
            ] as [String: Any])
        }
    }
}

/**
 * Compute the baseLine of the rawdata
 * Inspired by Lee Byron's paper Stacked Graphs - Geometry & Aesthetics
 *
 * @param  data  the points in each layer
 */
// function computeBaseline(data: number[][][])
private func computeBaseline(_ data: [[[Double]]]) -> (y0: [Double], max: Double) {
    // const layerNum = data.length;
    let layerNum = data.count
    // const pointNum = data[0].length;
    let pointNum = data[0].count
    // const sums = [];
    var sums: [Double] = []
    // const y0 = [];
    var y0: [Double] = []
    // let max = 0;
    var max: Double = 0

    // for (let i = 0; i < pointNum; ++i) {
    for i in 0..<pointNum {
        // let temp = 0;
        var temp: Double = 0
        // for (let j = 0; j < layerNum; ++j) { temp += data[j][i][1]; }
        for j in 0..<layerNum {
            temp += data[j][i][1]
        }
        // if (temp > max) { max = temp; }
        if temp > max {
            max = temp
        }
        // sums.push(temp);
        sums.append(temp)
    }

    // for (let k = 0; k < pointNum; ++k) { y0[k] = (max - sums[k]) / 2; }
    for k in 0..<pointNum {
        y0.append((max - sums[k]) / 2)
    }
    // max = 0;
    max = 0

    // for (let l = 0; l < pointNum; ++l) {
    for l in 0..<pointNum {
        // const sum = sums[l] + y0[l];
        let sum = sums[l] + y0[l]
        // if (sum > max) { max = sum; }
        if sum > max {
            max = sum
        }
    }

    // return { y0, max };
    return (y0: y0, max: max)
}

// ─── JS coercion shims (not upstream symbols) ─────────────────────────────────────────────────────

// `data.get(valueDim, idx) as number`: coerce a ParsedValue (`Any?`) to Double. The value store may hold
//   Int / Double / NSNumber; a bare `as? Double` drops an Int (INT-vs-DOUBLE trap).
private func trNum(_ v: Any?) -> Double {
    switch v {
    case let d as Double: return d
    case let i as Int: return Double(i)
    case let n as NSNumber: return n.doubleValue
    case let s as String: return Double(s) ?? Double.nan
    default: return Double.nan
    }
}
