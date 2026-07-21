// Ported from echarts/src/chart/lines/linesLayout.ts — keep in sync with upstream
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

/* global Float32Array */

import Foundation
import ZRenderKit

// upstream imports:
//   import createRenderPlanner from '../helper/createRenderPlanner';   -> `createRenderPlanner` (sibling).
//   import { StageHandler } from '../../util/types';                    -> StageHandler (util/types.swift).
//   import LinesSeriesModel, {LinesDataItemOption} from './LinesSeries'; -> sibling LinesSeries.swift.
//   import { error } from '../../util/log';                             -> `log.error` (util/log.swift).
//
// `new Float32Array(...)` (the large point buffer) -> `vendor.createFloat32Array` (util/vendor.swift),
//   which returns a `[Double]` — the same substitution candlestickLayout uses.

// const linesLayout: StageHandler = { seriesType, plan, reset }
public let linesLayout: StageHandler = {
    var handler = StageHandler()

    // seriesType: 'lines',
    handler.seriesType = "lines"

    // plan: createRenderPlanner(),
    // PORT-NOTE (deferred): upstream `plan: createRenderPlanner()`. Left unwired due to the signature
    //   mismatch of `StageHandler.plan` — `createRenderPlanner()` yields a 1-arg `(SeriesModel) ->
    //   StageHandlerPlanReturn?` (nil-for-no-reset), but `StageHandlerPlan` is the 4-arg
    //   `(SeriesModel, GlobalModel, ExtensionAPI, Payload?) -> StageHandlerPlanReturn` (non-optional return)
    //   and cannot be assigned without relaxing that typealias (same deviation as candlestickLayout.swift /
    //   layout/barGrid.swift `handler.plan = nil`).
    _ = createRenderPlanner()
    handler.plan = nil

    // reset: function (seriesModel: LinesSeriesModel) { ... }
    handler.reset = { (seriesModelBase: SeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload?) -> Any? in
        // upstream typed `seriesModel: LinesSeriesModel`.
        let seriesModel = seriesModelBase as! LinesSeriesModel

        // const coordSys = seriesModel.coordinateSystem;
        // if (!coordSys) { if (__DEV__) { error('The lines series must have a coordinate system.'); } return; }
        guard let coordSysAny = seriesModel.coordinateSystem else {
            if __DEV__ {
                log.error("The lines series must have a coordinate system.")
            }
            return nil
        }

        // upstream calls `coordSys.dataToPoint(...)` generically for whatever coordinate system the lines
        //   series is bound to (defaults to 'geo'; also grid/cartesian2d + calendar). Guard against the
        //   `CoordinateSystem` protocol and dispatch through its `dataToPoint(_:_:)` requirement: Cartesian2D,
        //   Geo and Calendar all witness it, so geo/calendar lines now lay out (was cartesian-only).
        //   `Polar` conforms only to `CoordinateSystemMaster` (its `dataToPoint(_:clamp:)` has a divergent
        //   signature and does not witness the protocol), so it fails the cast and produces no layout.
        guard let coordSys = coordSysAny as? CoordinateSystem else {
            return nil
        }

        // const isPolyline = seriesModel.get('polyline');
        let isPolyline = jsTruthy(seriesModel.get("polyline"))
        // const isLarge = seriesModel.pipelineContext.large;
        let isLarge = seriesModel.pipelineContext.large

        // return { progress(params, lineData) { ... } };
        var executor = StageHandlerProgressExecutor()
        executor.progress = { (params: StageHandlerProgressParams, lineData: SeriesData) in
            // const lineCoords: number[][] = [];
            var lineCoords: [[Double]] = []
            // if (isLarge) {
            if isLarge {
                // This branch is the SOLE PRODUCER of the flat `linesPoints` buffer, and it IS consumed:
                //   `LinesView.render`'s large branch hands the data to chart/helper/LargeLineDraw.updateData,
                //   which reads `data.getLayout("linesPoints") as? [Double]`. Both sides gate on the same
                //   `pipelineContext.large`, so producer and consumer cannot disagree. The buffer is
                //   FIXED-SIZE (as upstream's Float32Array) — that is the LAYOUT INVARIANT
                //   LargeLinesPath.buildPath / findDataIndex rely on (a Swift out-of-bounds read TRAPS where
                //   upstream's typed array merely yields NaN), so do NOT switch this to appending.
                // let points;
                var points: [Double]
                // const segCount = params.end - params.start;
                let segCount = Int(params.end) - Int(params.start)
                // if (isPolyline) {
                if isPolyline {
                    // let totalCoordsCount = 0;
                    var totalCoordsCount = 0
                    // for (let i = params.start; i < params.end; i++) { totalCoordsCount += getLineCoordsCount(i); }
                    for i in Int(params.start)..<Int(params.end) {
                        totalCoordsCount += seriesModel.getLineCoordsCount(i)
                    }
                    // points = new Float32Array(segCount + totalCoordsCount * 2);
                    points = vendor.createFloat32Array(Double(segCount + totalCoordsCount * 2))
                }
                // else {
                else {
                    // points = new Float32Array(segCount * 4);
                    points = vendor.createFloat32Array(Double(segCount * 4))
                }

                // let offset = 0;  let pt = [];
                var offset = 0
                var pt: [Double] = []
                // for (let i = params.start; i < params.end; i++) {
                for i in Int(params.start)..<Int(params.end) {
                    // const len = seriesModel.getLineCoords(i, lineCoords);
                    let len = seriesModel.getLineCoords(i, &lineCoords)
                    // if (isPolyline) { points[offset++] = len; }
                    if isPolyline {
                        points[offset] = Double(len); offset += 1
                    }
                    // for (let k = 0; k < len; k++) {
                    for k in 0..<len {
                        // pt = coordSys.dataToPoint(lineCoords[k], false, pt);
                        pt = coordSys.dataToPoint(lineCoords[k], false)
                        // points[offset++] = pt[0];  points[offset++] = pt[1];
                        points[offset] = pt[0]; offset += 1
                        points[offset] = pt[1]; offset += 1
                    }
                }

                // lineData.setLayout('linesPoints', points);
                lineData.setLayout("linesPoints", points)
            }
            // else {
            else {
                // for (let i = params.start; i < params.end; i++) {
                for i in Int(params.start)..<Int(params.end) {
                    // const itemModel = lineData.getItemModel<LinesDataItemOption>(i);
                    let itemModel = lineData.getItemModel(i)
                    // const len = seriesModel.getLineCoords(i, lineCoords);
                    let len = seriesModel.getLineCoords(i, &lineCoords)

                    // const pts = [];
                    var pts: [[Double]] = []
                    // if (isPolyline) {
                    if isPolyline {
                        // for (let j = 0; j < len; j++) { pts.push(coordSys.dataToPoint(lineCoords[j])); }
                        for j in 0..<len {
                            pts.append(coordSys.dataToPoint(lineCoords[j], nil))
                        }
                    }
                    // else {
                    else {
                        // pts[0] = coordSys.dataToPoint(lineCoords[0]);
                        pts.append(coordSys.dataToPoint(lineCoords[0], nil))
                        // pts[1] = coordSys.dataToPoint(lineCoords[1]);
                        pts.append(coordSys.dataToPoint(lineCoords[1], nil))

                        // const curveness = itemModel.get(['lineStyle', 'curveness']);
                        let curveness = linesNum(itemModel.get(["lineStyle", "curveness"]))
                        // if (+curveness) {   (JS: truthy iff non-zero and not NaN)
                        if curveness != 0 && !curveness.isNaN {
                            // pts[2] = [
                            //     (pts[0][0] + pts[1][0]) / 2 - (pts[0][1] - pts[1][1]) * curveness,
                            //     (pts[0][1] + pts[1][1]) / 2 - (pts[1][0] - pts[0][0]) * curveness
                            // ];
                            pts.append([
                                (pts[0][0] + pts[1][0]) / 2 - (pts[0][1] - pts[1][1]) * curveness,
                                (pts[0][1] + pts[1][1]) / 2 - (pts[1][0] - pts[0][0]) * curveness
                            ])
                        }
                    }
                    // lineData.setItemLayout(i, pts);
                    lineData.setItemLayout(i, pts)
                }
            }
        }
        return executor
    }

    return handler
}()

// export default linesLayout;  -> `public let linesLayout` above.

// ─── JS coercion shim (not an upstream symbol) ────────────────────────────────────────────────────

// `itemModel.get(['lineStyle', 'curveness'])` -> Double. A bare `as? Double` drops an Int (INT-vs-DOUBLE
//   trap); nil / non-numeric collapse to NaN (mirrors JS `+curveness`).
private func linesNum(_ v: Any?) -> Double {
    switch v {
    case let d as Double: return d
    case let i as Int: return Double(i)
    case let n as NSNumber: return n.doubleValue
    case let s as String: return Double(s) ?? Double.nan
    default: return Double.nan
    }
}

// Mirrors JavaScript truthiness for `seriesModel.get('polyline')` (nil / NSNull / false / 0 / NaN / "" falsy).
private func jsTruthy(_ v: Any?) -> Bool {
    guard let v = v else { return false }
    if v is NSNull { return false }
    if let b = v as? Bool { return b }
    if let n = v as? Double { return n != 0 && !n.isNaN }
    if let i = v as? Int { return i != 0 }
    if let s = v as? String { return !s.isEmpty }
    return true
}
