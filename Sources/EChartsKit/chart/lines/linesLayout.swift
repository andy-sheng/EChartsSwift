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
    // PORT-NOTE: `createRenderPlanner()` yields the upstream 1-arg planner `(SeriesModel) ->
    //   StageHandlerPlanReturn?` (nil-for-no-reset), while `StageHandlerPlan` is the 4-arg
    //   `(SeriesModel, GlobalModel, ExtensionAPI, Payload?) -> StageHandlerPlanReturn?`; the planner is
    //   created ONCE here (as upstream, so its `makeInner` large/progressive state persists across calls)
    //   and wrapped in an arity adapter that ignores the extra args, which upstream's planner also ignores.
    let planner = createRenderPlanner()
    handler.plan = { (seriesModel: SeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload?) -> StageHandlerPlanReturn? in
        return planner(seriesModel)
    }

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
        //   `pipelineContext` is an IUO `PipelineContext!` here: optional-chained so this stage matches
        //   LinesView's equally defensive read (a driver path that skipped updateStreamModes takes the
        //   non-large path on BOTH sides instead of trapping in the layout stage).
        let isLarge = seriesModel.pipelineContext?.large ?? false

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
                //   PORT-NOTE (load-bearing bound guards below): the buffer is sized from `segCount` on the
                //   assumption of 2 coords per non-polyline item, but `getLineCoords` does NOT clamp `len`,
                //   so a data item with 3+ coords writes past the end. Upstream's Float32Array SILENTLY
                //   DROPS an out-of-range write; a Swift `[Double]` subscript TRAPS. The
                //   `offset < points.count` / `offset + 1 < points.count` checks reproduce the JS
                //   semantics (clip the overflow, keep the buffer length an exact multiple of 4).
                //   The `pt.count` checks likewise reproduce `undefined` → NaN for a coordinate system
                //   that returns a short point.
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
                        // PORT-NOTE: upstream writes into a `Float32Array`, where an out-of-range store is
                        //   SILENTLY DROPPED; `[Double]` traps instead. The non-polyline buffer is sized for
                        //   exactly 2 points per segment (`segCount * 4`), but `getLineCoords` returns the
                        //   ACTUAL coord count, which is >= 3 for a data item declaring 3+ `coords` with
                        //   `polyline: false` — so every store is bounds-guarded to reproduce JS's drop.
                        if offset < points.count { points[offset] = Double(len) }
                        offset += 1
                    }
                    // for (let k = 0; k < len; k++) {
                    for k in 0..<len {
                        // pt = coordSys.dataToPoint(lineCoords[k], false, pt);
                        pt = coordSys.dataToPoint(lineCoords[k], false)
                        // points[offset++] = pt[0];  points[offset++] = pt[1];
                        //   (JS reads `pt[0]`/`pt[1]` of a short array as `undefined` -> NaN in the
                        //   Float32Array; mirrored with a NaN fallback rather than an index trap.)
                        if offset < points.count { points[offset] = pt.count > 0 ? pt[0] : Double.nan }
                        offset += 1
                        if offset < points.count { points[offset] = pt.count > 1 ? pt[1] : Double.nan }
                        offset += 1
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
                        // PORT-NOTE: upstream indexes `lineCoords[0]` / `lineCoords[1]` unconditionally; for
                        //   a malformed 1-coord datum JS yields `undefined` -> NaN points, while Swift would
                        //   trap (the scratch is only grown to `len` entries by `getLineCoords`, and starts
                        //   empty on the first datum). Bail out to the (possibly empty) layout instead.
                        guard len >= 2 && lineCoords.count >= 2 else {
                            lineData.setItemLayout(i, pts)
                            continue
                        }
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
