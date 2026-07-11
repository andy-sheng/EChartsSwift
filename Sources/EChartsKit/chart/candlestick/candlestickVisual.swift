// Ported from echarts/src/chart/candlestick/candlestickVisual.ts — keep in sync with upstream
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
//   import createRenderPlanner from '../helper/createRenderPlanner';   -> `createRenderPlanner` (sibling).
//   import { StageHandler } from '../../util/types';                    -> StageHandler (util/types.swift).
//   import CandlestickSeriesModel, { SERIES_TYPE_CANDLESTICK, CandlestickDataItemOption } from './CandlestickSeries';
//   import Model from '../../model/Model';                              -> Model (model/Model.swift).
//   import { extend } from 'zrender/src/core/util';                     -> `util.extend`.

// const positiveBorderColorQuery = ['itemStyle', 'borderColor'] as const;
private let positiveBorderColorQuery = ["itemStyle", "borderColor"]
// const negativeBorderColorQuery = ['itemStyle', 'borderColor0'] as const;
private let negativeBorderColorQuery = ["itemStyle", "borderColor0"]
// const dojiBorderColorQuery = ['itemStyle', 'borderColorDoji'] as const;
private let dojiBorderColorQuery = ["itemStyle", "borderColorDoji"]
// const positiveColorQuery = ['itemStyle', 'color'] as const;
private let positiveColorQuery = ["itemStyle", "color"]
// const negativeColorQuery = ['itemStyle', 'color0'] as const;
private let negativeColorQuery = ["itemStyle", "color0"]

// upstream: export function getColor(sign, model: Model<Pick<CandlestickDataItemOption, 'itemStyle'>>)
//   `sign`/`model` typed loosely (the port's option tree is the dynamic bag). Returns `ZRColor`
//   (== `ModelOption?`, i.e. `Any?`) — a color string / gradient / null.
public func getColor(_ sign: Double, _ model: Model) -> Any? {
    return model.get(
        sign > 0 ? positiveColorQuery : negativeColorQuery
    )
}

// upstream: export function getBorderColor(sign, model: Model<Pick<CandlestickDataItemOption, 'itemStyle'>>)
public func getBorderColor(_ sign: Double, _ model: Model) -> Any? {
    return model.get(
        sign == 0 ? dojiBorderColorQuery
            : sign > 0
                ? positiveBorderColorQuery
                : negativeBorderColorQuery
    )
}

// upstream: const candlestickVisual: StageHandler = { ... }; export default candlestickVisual;
public let candlestickVisual: StageHandler = {
    var handler = StageHandler()

    handler.seriesType = SERIES_TYPE_CANDLESTICK

    // PORT-TODO: upstream `plan: createRenderPlanner()`. `createRenderPlanner()` yields a
    //   `(SeriesModel) -> StageHandlerPlanReturn?` while `StageHandler.plan` (`StageHandlerPlan`) has a
    //   NON-optional return, so "no reset" cannot be represented without spurious re-plans. Left unwired
    //   (same deviation as layout/barGrid.swift's `handler.plan = nil`). The `reset` stage still
    //   recomputes visuals each pass, so basic rendering is unaffected.
    _ = createRenderPlanner()
    handler.plan = nil

    // For legend.
    handler.performRawSeries = true

    handler.reset = { (seriesModelBase: SeriesModel, ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload?) -> Any? in
        // upstream typed `seriesModel: CandlestickSeriesModel`.
        let seriesModel = seriesModelBase as! CandlestickSeriesModel

        // Only visible series has each data be visual encoded
        if ecModel.isSeriesFiltered(seriesModel) {
            return nil
        }

        let isLargeRender = seriesModel.pipelineContext.large
        // return !isLargeRender && { progress(params, data) { ... } };
        if isLargeRender {
            return nil
        }

        var executor = StageHandlerProgressExecutor()
        executor.progress = { (params: StageHandlerProgressParams, data: SeriesData) in
            // let dataIndex; while ((dataIndex = params.next()) != null) { ... }
            while let dataIndexD = params.next?() {
                let dataIndex = Int(dataIndexD)
                let itemModel = data.getItemModel(dataIndex)
                // const sign = data.getItemLayout(dataIndex).sign;
                let sign = (data.getItemLayout(dataIndex) as? CandlestickItemLayout)?.sign ?? 0

                // const style = itemModel.getItemStyle();
                var style = itemModel.getItemStyle()
                // style.fill = getColor(sign, itemModel);
                style["fill"] = getColor(sign, itemModel)
                // style.stroke = getBorderColor(sign, itemModel) || style.fill;
                let borderColor = getBorderColor(sign, itemModel)
                style["stroke"] = candlestickVisualJsTruthy(borderColor) ? borderColor : style["fill"]

                // const existsStyle = data.ensureUniqueItemVisual(dataIndex, 'style');
                // extend(existsStyle, style);
                // PORT-NOTE: upstream `existsStyle` is the very object stored in the item visual and
                //   `extend` mutates it IN PLACE. Swift dictionaries are value types, so extend a local
                //   copy and write it back via setItemVisual (CONVENTIONS §3; same as visual/style.swift).
                var existsStyle = (data.ensureUniqueItemVisual(dataIndex, "style") as? [String: Any]) ?? [:]
                existsStyle = util.extend(&existsStyle, style)
                data.setItemVisual(dataIndex, "style", existsStyle)
            }
        }
        return executor
    }

    return handler
}()

// JS truthiness for the `getBorderColor(...) || style.fill` OR (a color string is truthy; nil/''/false
// are falsy). Not an upstream symbol.
private func candlestickVisualJsTruthy(_ v: Any?) -> Bool {
    switch v {
    case nil: return false
    case is NSNull: return false
    case let b as Bool: return b
    case let s as String: return !s.isEmpty
    case let d as Double: return d != 0 && !d.isNaN
    default: return true
    }
}
