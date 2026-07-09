// Ported from echarts/src/chart/funnel/funnelLayout.ts — keep in sync with upstream
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
//   import * as layout from '../../util/layout';                     -> `layout.*` (util/layout.swift).
//   import {parsePercent, linearMap} from '../../util/number';       -> `number.parsePercent` / `number.linearMap`.
//   import FunnelSeriesModel, { ..., SERIES_TYPE_FUNNEL } from './FunnelSeries';
//       -> FunnelSeriesModel / `SERIES_TYPE_FUNNEL` (sibling FunnelSeries.swift).
//   import ExtensionAPI from '../../core/ExtensionAPI';              -> ExtensionAPI (core/ExtensionAPI.swift).
//   import SeriesData from '../../data/SeriesData';                  -> SeriesData (data/SeriesData.swift).
//   import GlobalModel from '../../model/Global';                    -> GlobalModel (model/Global.swift).
//   import { indexOf, isFunction, isString } from 'zrender/src/core/util';
//       -> `util.indexOf` / `util.isFunction` / `util.isString` (ZRenderKit).
//   import { createSimpleOverallStageHandler } from '../../util/model';
//       -> `model.createSimpleOverallStageHandler` (util/modelUtil.swift).

// upstream: function getSortedIndices(data: SeriesData, sort: FunnelSeriesOption['sort'])
private func getSortedIndices(_ data: SeriesData, _ sort: Any?) -> [Int] {
    let valueDim = data.mapDimension("value")!
    // const valueArr = data.mapArray(valueDim, function (val: number) { return val; });
    let valueArr = data.mapArray(valueDim) { args in
        return args[0]
    }
    var indices: [Int] = []
    let isAscending = (sort as? String) == "ascending"
    // for (let i = 0, len = data.count(); i < len; i++) { indices[i] = i; }
    let len = data.count()
    for i in 0..<len {
        indices.append(i)
    }

    // Add custom sortable function & none sortable opetion by "options.sort"
    if util.isFunction(sort) {
        // indices.sort(sort as any);
        // PORT-TODO: a custom comparator `sort` function cannot be carried through the `[String: Any]`
        //   option bag; only the string forms ('ascending' / 'descending' / 'none') are supported here.
    }
    else if (sort as? String) != "none" {
        // indices.sort(function (a, b) {
        //     return isAscending ? valueArr[a] - valueArr[b] : valueArr[b] - valueArr[a];
        // });
        indices.sort { a, b in
            let va = jsNumOr0(valueArr[a])
            let vb = jsNumOr0(valueArr[b])
            return isAscending ? va < vb : vb < va
        }
    }
    return indices
}

// upstream: function labelLayout(data: SeriesData)
private func labelLayout(_ data: SeriesData) {
    let seriesModel = data.hostModel as! FunnelSeriesModel
    let isHorizontal = isOrientHorizontal(seriesModel)
    data.each { args in
        let idx = Int(args[0] as! Double)
        let itemModel = data.getItemModel(idx)
        let labelModel = itemModel.getModel("label")
        var labelPosition = labelModel.get("position")

        let labelLineModel = itemModel.getModel("labelLine")

        // const layout = data.getItemLayout(idx);
        var layout = (data.getItemLayout(idx) as? [String: Any]) ?? [:]
        // const points = layout.points;
        let points = (layout["points"] as? [[Double]]) ?? []

        let labelPositionStr = labelPosition as? String
        let isLabelInside = labelPositionStr == "inner"
            || labelPositionStr == "inside" || labelPositionStr == "center"
            || labelPositionStr == "insideLeft" || labelPositionStr == "insideRight"

        var textAlign: String?
        var textX: Double?
        var textY: Double?
        var linePoints: [[Double]]?

        if isLabelInside {
            if labelPositionStr == "insideLeft" {
                textX = (points[0][0] + points[3][0]) / 2 + 5
                textY = (points[0][1] + points[3][1]) / 2
                textAlign = "left"
            }
            else if labelPositionStr == "insideRight" {
                textX = (points[1][0] + points[2][0]) / 2 - 5
                textY = (points[1][1] + points[2][1]) / 2
                textAlign = "right"
            }
            else {
                textX = (points[0][0] + points[1][0] + points[2][0] + points[3][0]) / 4
                textY = (points[0][1] + points[1][1] + points[2][1] + points[3][1]) / 4
                textAlign = "center"
            }
            linePoints = [
                [textX!, textY!], [textX!, textY!]
            ]
        }
        else {
            var x1: Double = Double.nan
            var y1: Double = Double.nan
            var x2: Double = Double.nan
            var y2: Double = Double.nan
            let labelLineLen = asDouble(labelLineModel.get("length"))
            if util.isString(labelPosition) {
                if !isHorizontal && util.indexOf(["top", "bottom"], labelPositionStr!) > -1 {
                    labelPosition = "left"
                    // PORT-TODO: __DEV__ console.warn
                    //   ('Position error: Funnel chart on vertical orient dose not support top and bottom.')
                }
                if isHorizontal && util.indexOf(["left", "right"], labelPositionStr!) > -1 {
                    labelPosition = "bottom"
                    // PORT-TODO: __DEV__ console.warn
                    //   ('Position error: Funnel chart on horizontal orient dose not support left and right.')
                }
            }
            // NOTE: `labelPosition` may have been reassigned above; re-read the string form.
            let pos = labelPosition as? String
            if pos == "left" {
                // Left side
                x1 = (points[3][0] + points[0][0]) / 2
                y1 = (points[3][1] + points[0][1]) / 2
                x2 = x1 - labelLineLen
                textX = x2 - 5
                textAlign = "right"
            }
            else if pos == "right" {
                // Right side
                x1 = (points[1][0] + points[2][0]) / 2
                y1 = (points[1][1] + points[2][1]) / 2
                x2 = x1 + labelLineLen
                textX = x2 + 5
                textAlign = "left"
            }
            else if pos == "top" {
                // Top side
                x1 = (points[3][0] + points[0][0]) / 2
                y1 = (points[3][1] + points[0][1]) / 2
                y2 = y1 - labelLineLen
                textY = y2 - 5
                textAlign = "center"
            }
            else if pos == "bottom" {
                // Bottom side
                x1 = (points[1][0] + points[2][0]) / 2
                y1 = (points[1][1] + points[2][1]) / 2
                y2 = y1 + labelLineLen
                textY = y2 + 5
                textAlign = "center"
            }
            else if pos == "rightTop" {
                // RightTop side
                x1 = isHorizontal ? points[3][0] : points[1][0]
                y1 = isHorizontal ? points[3][1] : points[1][1]
                if isHorizontal {
                    y2 = y1 - labelLineLen
                    textY = y2 - 5
                    textAlign = "center"
                }
                else {
                    x2 = x1 + labelLineLen
                    textX = x2 + 5
                    textAlign = "top"
                }
            }
            else if pos == "rightBottom" {
                // RightBottom side
                x1 = points[2][0]
                y1 = points[2][1]
                if isHorizontal {
                    y2 = y1 + labelLineLen
                    textY = y2 + 5
                    textAlign = "center"
                }
                else {
                    x2 = x1 + labelLineLen
                    textX = x2 + 5
                    textAlign = "bottom"
                }
            }
            else if pos == "leftTop" {
                // LeftTop side
                x1 = points[0][0]
                y1 = isHorizontal ? points[0][1] : points[1][1]
                if isHorizontal {
                    y2 = y1 - labelLineLen
                    textY = y2 - 5
                    textAlign = "center"
                }
                else {
                    x2 = x1 - labelLineLen
                    textX = x2 - 5
                    textAlign = "right"
                }
            }
            else if pos == "leftBottom" {
                // LeftBottom side
                x1 = isHorizontal ? points[1][0] : points[3][0]
                y1 = isHorizontal ? points[1][1] : points[2][1]
                if isHorizontal {
                    y2 = y1 + labelLineLen
                    textY = y2 + 5
                    textAlign = "center"
                }
                else {
                    x2 = x1 - labelLineLen
                    textX = x2 - 5
                    textAlign = "right"
                }
            }
            else {
                // Right side or Bottom side
                x1 = (points[1][0] + points[2][0]) / 2
                y1 = (points[1][1] + points[2][1]) / 2
                if isHorizontal {
                    y2 = y1 + labelLineLen
                    textY = y2 + 5
                    textAlign = "center"
                }
                else {
                    x2 = x1 + labelLineLen
                    textX = x2 + 5
                    textAlign = "left"
                }
            }
            if isHorizontal {
                x2 = x1
                textX = x2
            }
            else {
                y2 = y1
                textY = y2
            }
            linePoints = [[x1, y1], [x2, y2]]
        }

        // layout.label = { linePoints, x, y, verticalAlign, textAlign, inside };
        var label: [String: Any] = [
            "verticalAlign": "middle",
            "inside": isLabelInside
        ]
        if let linePoints = linePoints { label["linePoints"] = linePoints }
        if let textX = textX { label["x"] = textX }
        if let textY = textY { label["y"] = textY }
        if let textAlign = textAlign { label["textAlign"] = textAlign }
        layout["label"] = label
        data.setItemLayout(idx, layout)
    }
}

// upstream:
//   export const funnelLayoutStageHandler = createSimpleOverallStageHandler(SERIES_TYPE_FUNNEL, funnelLayout);
// `createSimpleOverallStageHandler` expects a `StageHandlerOverallReset = (GlobalModel, ExtensionAPI,
// Payload?) -> Void`; the upstream `funnelLayout` is `(ecModel, api)` (2-arg). Adapt with a thin wrapper
// that drops the (unused) payload, keeping `funnelLayout` byte-faithful (2-arg) below (see pieLayout.swift).
public let funnelLayoutStageHandler = model.createSimpleOverallStageHandler(
    SERIES_TYPE_FUNNEL,
    { ecModel, api, _ in funnelLayout(ecModel, api) }
)

// Exposed for the driver to call directly (mirrors pieLayout), matching upstream's module-private
// `function funnelLayout(ecModel, api)`.
public func funnelLayout(
    _ ecModel: GlobalModel,
    _ api: ExtensionAPI
) {
    ecModel.eachSeriesByType(SERIES_TYPE_FUNNEL) { seriesModelBase, _ in
        // upstream typed callback param `seriesModel: FunnelSeriesModel`.
        let seriesModel = seriesModelBase as! FunnelSeriesModel
        let data = seriesModel.getData()
        let valueDim = data.mapDimension("value")!
        let sort = seriesModel.get("sort")

        let layoutRef = layout.createBoxLayoutReference(seriesModel, api)
        let viewRect = layout.getLayoutRect(seriesModel.getBoxLayoutParams(), layoutRef.refContainer)

        let isHorizontal = isOrientHorizontal(seriesModel)
        let viewWidth = viewRect.width
        let viewHeight = viewRect.height
        var indices = getSortedIndices(data, sort)
        var x = viewRect.x
        var y = viewRect.y

        let sizeExtent: [Double] = isHorizontal ? [
            number.parsePercent(seriesModel.get("minSize"), viewHeight),
            number.parsePercent(seriesModel.get("maxSize"), viewHeight)
        ] : [
            number.parsePercent(seriesModel.get("minSize"), viewWidth),
            number.parsePercent(seriesModel.get("maxSize"), viewWidth)
        ]
        let dataExtent = data.getDataExtent(valueDim)
        var min = asDoubleOpt(seriesModel.get("min"))
        var max = asDoubleOpt(seriesModel.get("max"))
        if min == nil {
            min = Swift.min(dataExtent[0], 0)
        }
        if max == nil {
            max = dataExtent[1]
        }
        let minV = min!
        let maxV = max!

        // `funnelAlign` is always a string (defaultOption 'center'); coerced to a non-optional so the
        //   `switch funnelAlign` below matches String literal cases directly.
        let funnelAlign = (seriesModel.get("funnelAlign") as? String) ?? ""
        var gap = asDouble(seriesModel.get("gap"))
        let viewSize = isHorizontal ? viewWidth : viewHeight
        var itemSize = (viewSize - gap * Double(data.count() - 1)) / Double(data.count())

        // const getLinePoints = function (idx: number, offset: number) { ... };
        // `idx` may be nil for the trailing end point (upstream `indices[i + 1]` is `undefined` for the
        //   last item; `data.get(valueDim, undefined) || 0` yields 0). Modeled with `idx: Int?`.
        let getLinePoints: (Int?, Double) -> [[Double]] = { idx, offset in
            // End point index is data.count() and we assign it 0
            if isHorizontal {
                let val = jsNumOr0(idx != nil ? data.get(valueDim, idx!) : nil)
                let itemHeight = number.linearMap(val, [minV, maxV], sizeExtent, true)
                var y0: Double = Double.nan
                switch funnelAlign {
                case "top":
                    y0 = y
                case "center":
                    y0 = y + (viewHeight - itemHeight) / 2
                case "bottom":
                    y0 = y + (viewHeight - itemHeight)
                default:
                    break
                }

                return [
                    [offset, y0],
                    [offset, y0 + itemHeight]
                ]
            }
            let val = jsNumOr0(idx != nil ? data.get(valueDim, idx!) : nil)
            let itemWidth = number.linearMap(val, [minV, maxV], sizeExtent, true)
            var x0: Double = Double.nan
            switch funnelAlign {
            case "left":
                x0 = x
            case "center":
                x0 = x + (viewWidth - itemWidth) / 2
            case "right":
                x0 = x + viewWidth - itemWidth
            default:
                break
            }
            return [
                [x0, offset],
                [x0 + itemWidth, offset]
            ]
        }

        if (sort as? String) == "ascending" {
            // From bottom to top
            itemSize = -itemSize
            gap = -gap
            if isHorizontal {
                x += viewWidth
            }
            else {
                y += viewHeight
            }
            // indices = indices.reverse();  (in-place; reassignment is implicit in Swift)
            indices.reverse()
        }

        for i in 0..<indices.count {
            let idx = indices[i]
            let nextIdx: Int? = (i + 1 < indices.count) ? indices[i + 1] : nil
            let itemModel = data.getItemModel(idx)

            if isHorizontal {
                var width = asDoubleOpt(itemModel.get(["itemStyle", "width"]))
                if width == nil {
                    width = itemSize
                }
                else {
                    width = number.parsePercent(itemModel.get(["itemStyle", "width"]), viewWidth)
                    if (sort as? String) == "ascending" {
                        width = -width!
                    }
                }

                let start = getLinePoints(idx, x)
                let end = getLinePoints(nextIdx, x + width!)

                x += width! + gap

                data.setItemLayout(idx, [
                    "points": start + Array(end.reversed())
                ] as [String: Any])
            }
            else {
                var height = asDoubleOpt(itemModel.get(["itemStyle", "height"]))
                if height == nil {
                    height = itemSize
                }
                else {
                    height = number.parsePercent(itemModel.get(["itemStyle", "height"]), viewHeight)
                    if (sort as? String) == "ascending" {
                        height = -height!
                    }
                }

                let start = getLinePoints(idx, y)
                let end = getLinePoints(nextIdx, y + height!)

                y += height! + gap

                data.setItemLayout(idx, [
                    "points": start + Array(end.reversed())
                ] as [String: Any])
            }
        }

        labelLayout(data)
    }
}

// upstream: function isOrientHorizontal(seriesModel: FunnelSeriesModel): boolean
private func isOrientHorizontal(_ seriesModel: FunnelSeriesModel) -> Bool {
    return (seriesModel.get("orient") as? String) == "horizontal"
}

// ─── JS coercion shims (not upstream symbols) ─────────────────────────────────────────────────────
// The dynamic option bag / ParsedValue store returns `Any?`; upstream reads these slots as `number`.

// JS number coercion (returns NaN when not a number).
private func asDouble(_ v: Any?) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let s = v as? String, let d = Double(s) { return d }
    return Double.nan
}

// Optional number: nil when the slot is absent/null/non-numeric (models `x == null`).
private func asDoubleOpt(_ v: Any?) -> Double? {
    if v == nil || v is NSNull { return nil }
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    return nil
}

// Models `data.get(valueDim, idx) as number || 0`: JS falsy (0 / NaN / null / undefined) → 0.
private func jsNumOr0(_ v: Any?) -> Double {
    let d = asDouble(v)
    return (d != 0 && !d.isNaN) ? d : 0
}
