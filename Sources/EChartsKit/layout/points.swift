// Ported from echarts/src/layout/points.ts — keep in sync with upstream
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

// import {map} from 'zrender/src/core/util';                      -> `util.map`
// import createRenderPlanner from '../chart/helper/createRenderPlanner';  -> `createRenderPlanner`
// import {isDimensionStacked} from '../data/helper/dataStackHelper';      -> `isDimensionStacked`
// import { StageHandler, ParsedValueNumeric } from '../util/types';
// import { createFloat32Array } from '../util/vendor';            -> `vendor.createFloat32Array`

// export default function pointsLayout(seriesType: string, forceStoreInTypedArray?: boolean): StageHandler
//
// WHY THIS MATTERS FOR BRUSH: this is the stage that writes each point-series datum's PIXEL position with
//   `data.setItemLayout(i, point)`. `ScatterSeries#brushSelector` / `EffectScatterSeries#brushSelector`
//   read it back through `data.getItemLayout(dataIndex)`. Without this stage a scatter's item layout is
//   nil and a brush over a scatter silently selects NOTHING.
public func pointsLayout(_ seriesType: String, _ forceStoreInTypedArray: Bool = false) -> StageHandler {
    var handler = StageHandler()

    handler.seriesType = seriesType

    // plan: createRenderPlanner(),
    //   PORT-NOTE (deferred): the `StageHandler.plan` typealias has a NON-optional return here, so the
    //   planner's "no reset needed" answer cannot be represented (identical deviation to
    //   candlestickLayout / barGrid). `reset` recomputes each pass, so output is unaffected.
    _ = createRenderPlanner()
    handler.plan = nil

    handler.reset = { (seriesModel: SeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload?) -> Any? in
        let data = seriesModel.getData()
        let coordSysIn = seriesModel.coordinateSystem
        let pipelineContext = seriesModel.pipelineContext
        let useTypedArray = forceStoreInTypedArray || (pipelineContext?.large ?? false)

        // if (!coordSys) { return; }
        guard let coordSys = pointsLayoutCoordSys(coordSysIn) else {
            return nil
        }

        // const dims = map(coordSys.dimensions, dim => data.mapDimension(dim)).slice(0, 2);
        var dims: [String?] = util.map(coordSys.dimensions) { dim, _ in
            return data.mapDimension(dim)
        }
        if dims.count > 2 { dims = Array(dims[0..<2]) }
        let dimLen = dims.count

        // const stackResultDim = data.getCalculationInfo('stackResultDimension');
        let stackResultDim = data.getCalculationInfo("stackResultDimension") as? String
        // if (isDimensionStacked(data, dims[0])) { dims[0] = stackResultDim; }
        if dimLen > 0, let d0 = dims[0], isDimensionStacked(data, d0) {
            dims[0] = stackResultDim
        }
        // if (isDimensionStacked(data, dims[1])) { dims[1] = stackResultDim; }
        if dimLen > 1, let d1 = dims[1], isDimensionStacked(data, d1) {
            dims[1] = stackResultDim
        }

        let store = data.getStore()
        let dimIdx0 = dims.count > 0 && dims[0] != nil ? data.getDimensionIndex(dims[0]!) : -1
        let dimIdx1 = dims.count > 1 && dims[1] != nil ? data.getDimensionIndex(dims[1]!) : -1

        // return dimLen && { progress(params, data) { ... } };
        if dimLen == 0 {
            return nil
        }

        var executor = StageHandlerProgressExecutor()
        executor.progress = { (params: StageHandlerProgressParams, data: SeriesData) in
            let start = Int(params.start)
            let end = Int(params.end)
            // const segCount = params.end - params.start;
            let segCount = end - start
            // const points = useTypedArray && createFloat32Array(segCount * dimLen);
            var points: [Double] = useTypedArray
                ? vendor.createFloat32Array(Double(segCount * dimLen))
                : []

            var offset = 0
            for i in start..<end {
                var point: [Double]

                if dimLen == 1 {
                    let x = store.get(dimIdx0, i)
                    // NOTE: Make sure the second parameter is null to use default strategy.
                    point = coordSys.dataToPoint(x, nil)
                }
                else {
                    var tmpIn: [ParsedValue] = [0, 0]
                    tmpIn[0] = store.get(dimIdx0, i)
                    tmpIn[1] = store.get(dimIdx1, i)
                    // Let coordinate system to handle the NaN data.
                    point = coordSys.dataToPoint(tmpIn, nil)
                }

                if useTypedArray {
                    if offset + 1 < points.count {
                        points[offset] = point.count > 0 ? point[0] : Double.nan
                        points[offset + 1] = point.count > 1 ? point[1] : Double.nan
                    }
                    offset += 2
                }
                else {
                    // data.setItemLayout(i, point.slice());
                    data.setItemLayout(i, point)
                }
            }

            if useTypedArray {
                data.setLayout("points", points)
                data.setLayout("pointsRange", ["start": params.start, "end": params.end] as [String: Any])
            }
        }
        return executor
    }

    return handler
}

// ---------------------------------------------------------------------------
// PORT-LOCAL coord-system shim (not in upstream).
//
// Upstream `Geo` implements the `CoordinateSystem` interface, so `pointsLayout` reaches
// `coordSys.dimensions` / `coordSys.dataToPoint` polymorphically. In this port `Geo` conforms only to
// `CoordinateSystemMaster` (its `dataToPoint` returns an Optional `[Double]?` and takes `noRoam`), so the
// two shapes are unified here. `seriesModel.coordinateSystem` is `Any?` in the port, so the cast happens
// here anyway.
// ---------------------------------------------------------------------------
private struct PointsLayoutCoordSys {
    let dimensions: [DimensionName]
    let dataToPoint: (_ data: Any?, _ opt: Any?) -> [Double]
}

private func pointsLayoutCoordSys(_ coordSys: Any?) -> PointsLayoutCoordSys? {
    if let geo = coordSys as? Geo {
        return PointsLayoutCoordSys(
            dimensions: geo.dimensions,
            dataToPoint: { data, _ in
                // An invalid point is `[NaN, NaN]` by the CoordinateSystem contract (never nil).
                return geo.dataToPoint(data, nil) ?? [Double.nan, Double.nan]
            }
        )
    }
    if let cs = coordSys as? CoordinateSystem {
        return PointsLayoutCoordSys(
            dimensions: cs.dimensions,
            dataToPoint: { data, opt in
                return cs.dataToPoint(data as CoordinateSystemDataCoord, opt)
            }
        )
    }
    return nil
}
