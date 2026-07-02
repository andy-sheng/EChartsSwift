// Ported from echarts/src/chart/pie/pieLayout.ts — keep in sync with upstream
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
//   import { linearMap } from '../../util/number';                   -> `number.linearMap` (util/number.swift).
//   import GlobalModel from '../../model/Global';                    -> GlobalModel (model/Global.swift).
//   import ExtensionAPI from '../../core/ExtensionAPI';              -> ExtensionAPI (core/ExtensionAPI.swift).
//   import PieSeriesModel, { SERIES_TYPE_PIE } from './PieSeries';   -> PieSeriesModel / `SERIES_TYPE_PIE`
//       (sibling chart/pie/PieSeries.swift — provided by the PieSeries track).
//   import { normalizeArcAngles } from 'zrender/src/core/PathProxy'; -> `normalizeArcAngles` (ZRenderKit
//       PathProxy.swift; a top-level free function).
//   import { createSimpleOverallStageHandler, makeInner } from '../../util/model';
//       -> `model.createSimpleOverallStageHandler` / `model.makeInner` (util/modelUtil.swift).
//   import { getCircleLayout } from '../../util/layout';             -> `layout.getCircleLayout` (util/layout.swift).

// const PI2 = Math.PI * 2;
private let PI2 = Double.pi * 2
// const RADIAN = Math.PI / 180;
private let RADIAN = Double.pi / 180

// upstream:
//   export const pieLayoutStageHandler = createSimpleOverallStageHandler(SERIES_TYPE_PIE, pieLayout);
// `createSimpleOverallStageHandler` expects a `StageHandlerOverallReset = (GlobalModel, ExtensionAPI,
// Payload?) -> Void`; the upstream `pieLayout` is `(ecModel, api)` (2-arg). Adapt with a thin wrapper
// that drops the (unused) payload, keeping `pieLayout` byte-faithful (2-arg) below.
public let pieLayoutStageHandler = model.createSimpleOverallStageHandler(
    SERIES_TYPE_PIE,
    { ecModel, api, _ in pieLayout(ecModel, api) }
)

// Exposed for the slim driver to call directly (mirrors how the bar layout handlers are invoked
// directly), matching upstream's module-private `function pieLayout(ecModel, api)`.
public func pieLayout(
    _ ecModel: GlobalModel,
    _ api: ExtensionAPI
) {
    ecModel.eachSeriesByType(SERIES_TYPE_PIE) { seriesModelBase, _ in
        // upstream typed callback param `seriesModel: PieSeriesModel`.
        let seriesModel = seriesModelBase as! PieSeriesModel
        let data = seriesModel.getData()
        // upstream `const valueDim = data.mapDimension('value')` — the value dim is always present for pie.
        let valueDim = data.mapDimension("value")!

        let (cx, cy, r0, r, viewRect) = layout.getCircleLayout(seriesModel, api)

        var startAngle = -(asDouble(seriesModel.get("startAngle"))) * RADIAN
        let endAngleOpt = seriesModel.get("endAngle")
        let padAngle = asDouble(seriesModel.get("padAngle")) * RADIAN

        // endAngle = endAngle === 'auto' ? startAngle - PI2 : -endAngle * RADIAN;
        var endAngle = (endAngleOpt as? String) == "auto"
            ? startAngle - PI2
            : -(asDouble(endAngleOpt)) * RADIAN

        let minAngle = asDouble(seriesModel.get("minAngle")) * RADIAN

        let minAndPadAngle = minAngle + padAngle

        var validDataCount: Double = 0
        data.each(valueDim) { args in
            let value = (args[0] as? Double) ?? Double.nan
            // !isNaN(value) && validDataCount++;
            if !value.isNaN { validDataCount += 1 }
        }

        let sum = data.getSum(valueDim)
        // Sum may be 0
        // let unitRadian = Math.PI / (sum || validDataCount) * 2;
        // JS `sum || validDataCount` is truthy: 0 AND NaN both fall through to validDataCount.
        var unitRadian = Double.pi / ((sum == 0 || sum.isNaN) ? validDataCount : sum) * 2

        // upstream `clockwise: boolean` (defaulted `true` in defaultOption).
        // Fall back to the upstream default (true) when the option is absent, not false —
        // a nil here must not silently invert the winding direction.
        let clockwise = (seriesModel.get("clockwise") as? Bool) ?? true

        let roseType = seriesModel.get("roseType")
        let roseTypeIsArea = (roseType as? String) == "area"
        let roseTypeTruthy = pieLayoutJsTruthy(roseType)
        let stillShowZeroSum = (seriesModel.get("stillShowZeroSum") as? Bool) ?? false

        // [0...max]
        var extent = data.getDataExtent(valueDim)
        extent[0] = 0

        let dir: Double = clockwise ? 1 : -1
        var angles = [startAngle, endAngle]
        let halfPadAngle = dir * padAngle / 2
        normalizeArcAngles(&angles, !clockwise)

        // [startAngle, endAngle] = angles;
        startAngle = angles[0]
        endAngle = angles[1]

        let layoutData = getSeriesLayoutData(seriesModel)
        layoutData.startAngle = startAngle
        layoutData.endAngle = endAngle
        layoutData.clockwise = clockwise
        layoutData.cx = cx
        layoutData.cy = cy
        layoutData.r = r
        layoutData.r0 = r0

        let angleRange = abs(endAngle - startAngle)

        // In the case some sector angle is smaller than minAngle
        var restAngle = angleRange
        var valueSumLargerThanMinAngle: Double = 0

        var currentAngle = startAngle

        // Requird by `pieLabelLayout`.
        data.setLayout(["viewRect": viewRect, "r": r])

        data.each(valueDim) { args in
            let value = (args[0] as? Double) ?? Double.nan
            let idx = Int(args[1] as! Double)
            var angle: Double
            if value.isNaN {
                data.setItemLayout(idx, [
                    "angle": Double.nan,
                    "startAngle": Double.nan,
                    "endAngle": Double.nan,
                    "clockwise": clockwise,
                    "cx": cx,
                    "cy": cy,
                    "r0": r0,
                    "r": roseTypeTruthy
                        ? Double.nan
                        : r
                ] as [String: Any])
                return
            }

            // FIXME 兼容 2.0 但是 roseType 是 area 的时候才是这样？
            if !roseTypeIsArea {
                angle = (sum == 0 && stillShowZeroSum)
                    ? unitRadian : (value * unitRadian)
            }
            else {
                angle = angleRange / validDataCount
            }

            if angle < minAndPadAngle {
                angle = minAndPadAngle
                restAngle -= minAndPadAngle
            }
            else {
                valueSumLargerThanMinAngle += value
            }

            // upstream shadows the outer `endAngle` with a per-datum `const endAngle`; renamed to
            // `endAngleLocal` to avoid clashing with the mutable outer `endAngle`.
            let endAngleLocal = currentAngle + dir * angle

            // calculate display angle
            var actualStartAngle: Double = 0
            var actualEndAngle: Double = 0

            if padAngle > angle {
                actualStartAngle = currentAngle + dir * angle / 2
                actualEndAngle = actualStartAngle
            }
            else {
                actualStartAngle = currentAngle + halfPadAngle
                actualEndAngle = endAngleLocal - halfPadAngle
            }

            data.setItemLayout(idx, [
                "angle": angle,
                "startAngle": actualStartAngle,
                "endAngle": actualEndAngle,
                "clockwise": clockwise,
                "cx": cx,
                "cy": cy,
                "r0": r0,
                "r": roseTypeTruthy
                    ? number.linearMap(value, extent, [r0, r])
                    : r
            ] as [String: Any])

            currentAngle = endAngleLocal
        }

        // Some sector is constrained by minAngle and padAngle
        // Rest sectors needs recalculate angle
        if restAngle < PI2 && validDataCount != 0 {
            // Average the angle if rest angle is not enough after all angles is
            // Constrained by minAngle and padAngle
            if restAngle <= 1e-3 {
                let angle = angleRange / validDataCount
                data.each(valueDim) { args in
                    let value = (args[0] as? Double) ?? Double.nan
                    let idx = Int(args[1] as! Double)
                    if !value.isNaN {
                        // upstream mutates the stored layout object in place; the ported store holds a
                        // value dict, so read → mutate → write back (only angle/startAngle/endAngle change).
                        var layout = (data.getItemLayout(idx) as? [String: Any]) ?? [:]
                        layout["angle"] = angle

                        var actualStartAngle: Double = 0
                        var actualEndAngle: Double = 0

                        if angle < padAngle {
                            actualStartAngle = startAngle + dir * (Double(idx) + 1.0 / 2) * angle
                            actualEndAngle = actualStartAngle
                        }
                        else {
                            actualStartAngle = startAngle + dir * Double(idx) * angle + halfPadAngle
                            actualEndAngle = startAngle + dir * (Double(idx) + 1) * angle - halfPadAngle
                        }

                        layout["startAngle"] = actualStartAngle
                        layout["endAngle"] = actualEndAngle
                        data.setItemLayout(idx, layout)
                    }
                }
            }
            else {
                unitRadian = restAngle / valueSumLargerThanMinAngle
                currentAngle = startAngle
                data.each(valueDim) { args in
                    let value = (args[0] as? Double) ?? Double.nan
                    let idx = Int(args[1] as! Double)
                    if !value.isNaN {
                        var layout = (data.getItemLayout(idx) as? [String: Any]) ?? [:]
                        let layoutAngle = (layout["angle"] as? Double) ?? Double.nan
                        let angle = layoutAngle == minAndPadAngle
                            ? minAndPadAngle : value * unitRadian

                        var actualStartAngle: Double = 0
                        var actualEndAngle: Double = 0

                        if angle < padAngle {
                            actualStartAngle = currentAngle + dir * angle / 2
                            actualEndAngle = actualStartAngle
                        }
                        else {
                            actualStartAngle = currentAngle + halfPadAngle
                            actualEndAngle = currentAngle + dir * angle - halfPadAngle
                        }

                        layout["startAngle"] = actualStartAngle
                        layout["endAngle"] = actualEndAngle
                        data.setItemLayout(idx, layout)
                        currentAngle += dir * angle
                    }
                }
            }
        }
    }
}

// upstream:
//   export const getSeriesLayoutData = makeInner<{
//       startAngle: number; endAngle: number; clockwise: boolean;
//       cx: number; cy: number; r: number; r0: number
//   }, PieSeriesModel>();
//
// The anonymous inner-store record is modeled as a small class (`makeInner` requires a class Host/value
// per CONVENTIONS §2 + innerStore.swift; upstream stores `getSeriesLayoutData(seriesModel).startAngle = …`).
public final class PieSeriesLayoutData {
    public var startAngle: Double = 0
    public var endAngle: Double = 0
    public var clockwise: Bool = false
    public var cx: Double = 0
    public var cy: Double = 0
    public var r: Double = 0
    public var r0: Double = 0
    public init() {}
}

public let getSeriesLayoutData: (PieSeriesModel) -> PieSeriesLayoutData =
    model.makeInner { PieSeriesLayoutData() }

// JS number coercion shim for the dynamic option bag (upstream reads `seriesModel.get('startAngle')`
// etc. as `number`). Not an upstream symbol.
private func asDouble(_ v: Any?) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let s = v as? String, let d = Double(s) { return d }
    return Double.nan
}

// JS truthiness shim for the dynamic `roseType` bag (`false`/`undefined` are falsy; a non-empty string
// like `'radius'`/`'area'` is truthy). Not an upstream symbol.
private func pieLayoutJsTruthy(_ v: Any?) -> Bool {
    switch v {
    case nil: return false
    case is NSNull: return false
    case let b as Bool: return b
    case let d as Double: return d != 0 && !d.isNaN
    case let i as Int: return i != 0
    case let s as String: return !s.isEmpty
    default: return true
    }
}
