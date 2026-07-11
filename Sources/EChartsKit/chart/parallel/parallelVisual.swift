// Ported from echarts/src/chart/parallel/parallelVisual.ts — keep in sync with upstream
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
//   import ParallelSeriesModel, { ParallelSeriesOption } from './ParallelSeries';  -> sibling ParallelSeries.swift.
//   import { StageHandler } from '../../util/types';                                -> StageHandler (util/types.swift).

// const opacityAccessPath = ['lineStyle', 'opacity'] as const;
private let opacityAccessPath = ["lineStyle", "opacity"]

// upstream: const parallelVisual: StageHandler = { ... }; export default parallelVisual;
public let parallelVisual: StageHandler = {
    var handler = StageHandler()

    handler.seriesType = "parallel"

    handler.reset = { (seriesModelBase: SeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload?) -> Any? in
        // upstream typed `seriesModel: ParallelSeriesModel`.
        let seriesModel = seriesModelBase as! ParallelSeriesModel

        // const coordSys = seriesModel.coordinateSystem;
        let coordSys = seriesModel.parallelCoordinateSystem

        // const opacityMap = {
        //     normal: seriesModel.get(['lineStyle', 'opacity']),
        //     active: seriesModel.get('activeOpacity'),
        //     inactive: seriesModel.get('inactiveOpacity')
        // };
        // PORT-NOTE (CONVENTIONS trap 1): opacities are stored as bare `Int`/`Double` in the option bag,
        //   so each is read through `numOpt` (a plain `as? Double` would silently drop an Int literal).
        let opacityMap: [String: Double?] = [
            "normal": numOpt(seriesModel.get(["lineStyle", "opacity"])),
            "active": numOpt(seriesModel.get("activeOpacity")),
            "inactive": numOpt(seriesModel.get("inactiveOpacity"))
        ]

        // return { progress(params, data) { ... } };
        var executor = StageHandlerProgressExecutor()
        executor.progress = { (params: StageHandlerProgressParams, data: SeriesData) in
            // PORT-NOTE: `Parallel.eachActiveState` is ported (coord/parallel/Parallel.swift) and called
            //   below. Without a live parallelAxis brush selection every row resolves to the
            //   'normal' state, giving each polyline the `lineStyle.opacity`. Body is ported faithfully.
            coordSys?.eachActiveState(data, { (activeState: ParallelActiveState, dataIndex: Int) in
                // let opacity = opacityMap[activeState];
                var opacity: Double? = opacityMap[activeState] ?? nil
                // if (activeState === 'normal' && data.hasItemOption) {
                if activeState == "normal" && data.hasItemOption {
                    // const itemOpacity = data.getItemModel<...>(dataIndex).get(opacityAccessPath, true);
                    let itemOpacity = numOpt(data.getItemModel(dataIndex).get(opacityAccessPath, true))
                    // itemOpacity != null && (opacity = itemOpacity);
                    if itemOpacity != nil {
                        opacity = itemOpacity
                    }
                }
                // const existsStyle = data.ensureUniqueItemVisual(dataIndex, 'style');
                // existsStyle.opacity = opacity;
                //   Upstream mutates the stored visual `style` object IN PLACE; the ported store returns a
                //   value dict, so read → set → write back (CONVENTIONS §3; same as candlestickVisual).
                var existsStyle = (data.ensureUniqueItemVisual(dataIndex, "style") as? [String: Any]) ?? [:]
                existsStyle["opacity"] = opacity
                data.setItemVisual(dataIndex, "style", existsStyle)
            }, Int(params.start), Int(params.end))
        }
        return executor
    }

    return handler
}()

// INT-vs-DOUBLE option reader (CONVENTIONS trap 1). Not an upstream symbol.
private func numOpt(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return nil
}
