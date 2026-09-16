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
    // `createRenderPlanner()` yields the upstream 1-arg planner `(SeriesModel) ->
    //   StageHandlerPlanReturn?` (nil-for-no-reset), while `StageHandlerPlan` is the 4-arg
    //   `(SeriesModel, GlobalModel, ExtensionAPI, Payload?) -> StageHandlerPlanReturn?`; the planner is
    //   created ONCE here (as upstream, so its `makeInner` large/progressive state persists across calls)
    //   and wrapped in an arity adapter that ignores the extra args, which upstream's planner also ignores.
    let planner = createRenderPlanner()
    handler.plan = { (seriesModel: SeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload?) -> StageHandlerPlanReturn? in
        return planner(seriesModel)
    }

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
        // Swift numeric-buffer specialization. Keep the general path for ordinal strings and
        // non-cartesian coordinate systems. Float32 quantization stays at the upstream boundary.
        let numericCartesian = dimLen == 2 && store.isNumericDimension(dimIdx0) && store.isNumericDimension(dimIdx1)
            ? seriesModel.coordinateSystem as? Cartesian2D : nil

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
                if useTypedArray, let cartesian = numericCartesian {
                    let point = cartesian.dataToPoint(VectorArray(store.getNumeric(dimIdx0, i), store.getNumeric(dimIdx1, i)))
                    if offset + 1 < points.count {
                        points[offset] = Double(Float(point[0]))
                        points[offset + 1] = Double(Float(point[1]))
                    }
                    offset += 2
                    continue
                }
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
                        // Upstream stores this stage in a Float32Array. Quantize at the assignment
                        // boundary so degenerate polar points and hit-derived axis values follow the
                        // same IEEE-754 path as Web rather than retaining Swift Double precision.
                        points[offset] = point.count > 0 ? Double(Float(point[0])) : Double.nan
                        points[offset + 1] = point.count > 1 ? Double(Float(point[1])) : Double.nan
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
    // Upstream `Polar` implements the `CoordinateSystem` interface, so `pointsLayout` projects polar
    //   point-series (line-on-polar) too. In this port `Polar` conforms only to `CoordinateSystemMaster`
    //   (its `dataToPoint([ScaleDataValue], clamp?)` shape differs from the protocol witness), so it is
    //   unified here — mirroring the `Geo` shim above. WITHOUT this, a polar line's `data.getLayout('points')`
    //   is nil and LineView draws nothing / never runs its polar clip enter animation.
    if let polar = coordSys as? Polar {
        return PointsLayoutCoordSys(
            dimensions: polar.dimensions,
            dataToPoint: { data, _ in
                return polar.dataToPoint((data as? [ScaleDataValue]) ?? [], nil)
            }
        )
    }
    return nil
}
