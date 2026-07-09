// Ported from echarts/src/component/dataZoom/dataZoomProcessor.ts — keep in sync with upstream
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
//   import { createHashMap, each } from 'zrender/src/core/util';    -> `util.each` / `createHashMap`
//   import SeriesModel from '../../model/Series';                   -> `SeriesModel`
//   import DataZoomModel from './DataZoomModel';                    -> `DataZoomModel` (TASK 1 sibling; integrator reconciles)
//   import { getAxisMainType, DataZoomAxisDimension, getAlignTo, getAxisProxyFromModel, setAxisProxyToModel }
//       from './helper';                                            -> dataZoomHelper.swift
//   import AxisProxy from './AxisProxy';                            -> AxisProxy.swift
//   import { StageHandler } from '../../util/types';                -> `StageHandler` (util/types.swift)
//   import { AxisBaseModel } from '../../coord/AxisBaseModel';      -> `AxisBaseModel`

// ============================================================================
// TASK 1 (DataZoomModel) SURFACE additionally consumed here:
//   - dataZoomModel.findRepresentativeAxisProxy() -> AxisProxy?
//   - dataZoomModel.setCalculatedRange(start:end:startValue:endValue:)    // fills getOption() range props
//   (plus the surface listed in AxisProxy.swift)
// ============================================================================

// upstream: const dataZoomProcessor: StageHandler = { ... }
//   Exposed as a value so the integrator can invoke `dataZoomProcessor.overallReset?(ecModel, api, nil)`
//   in `ECharts.update()`'s PROCESSOR stage (like `graphCategoryFilterStageHandler`), BEFORE
//   `coordSysMgr.update` reads the (now filtered) series-data extents. It is a FILTER-priority processor.
public let dataZoomProcessor: StageHandler = {
    var handler = StageHandler()

    handler.dirtyOnOverallProgress = true

    // `dataZoomProcessor` will only be performed in needed series. (See upstream comment.)
    handler.getTargetSeries = { ecModel, _ in

        // upstream nested: eachAxisModel(cb)
        func eachAxisModel(
            _ cb: (
                _ axisDim: DataZoomAxisDimension,
                _ axisIndex: Int,
                _ axisModel: AxisBaseModel?,
                _ dataZoomModel: DataZoomModel
            ) -> Void
        ) {
            ecModel.eachComponent("dataZoom") { modelItem, _ in
                let dataZoomModel = modelItem as! DataZoomModel
                dataZoomModel.eachTargetAxis { axisDim, axisIndex in
                    let axisModel = ecModel.getComponent(
                        getAxisMainType(axisDim), axisIndex
                    ) as? AxisBaseModel
                    // `eachTargetAxis` yields a `Double` componentIndex; AxisProxy's cb takes `Int`.
                    cb(axisDim, Int(axisIndex), axisModel, dataZoomModel)
                }
            }
        }

        // FIXME: it brings side-effect to `getTargetSeries`.
        var proxyList: [AxisProxy] = []
        eachAxisModel { axisDim, axisIndex, axisModel, dataZoomModel in
            // Different dataZooms may control the same axis. In that case,
            // an axisProxy serves both of them.
            if getAxisProxyFromModel(axisModel) == nil {
                // Use the first dataZoomModel as the main model of axisProxy.
                let axisProxy = AxisProxy(axisDim, axisIndex, dataZoomModel, ecModel)
                proxyList.append(axisProxy)
                if let axisModel = axisModel {
                    setAxisProxyToModel(axisModel, axisProxy)
                }
            }
        }

        // upstream: createHashMap<SeriesModel>() keyed by seriesModel.uid.
        //   The ported StageHandler.getTargetSeries returns `[String: SeriesModel]`.
        var seriesModelMap: [String: SeriesModel] = [:]
        util.each(proxyList) { axisProxy, _ in
            util.each(axisProxy.getTargetSeriesModels()) { seriesModel, _ in
                seriesModelMap[seriesModel.uid] = seriesModel
            }
        }

        return seriesModelMap
    }

    // Consider appendData, where filter should be performed. (See upstream comment.)
    handler.overallReset = { ecModel, api, _ in

        ecModel.eachComponent("dataZoom") { modelItem, _ in
            let dataZoomModel = modelItem as! DataZoomModel
            // We calculate window and reset axis here but not in model init stage and not after
            // action dispatch handler, because reset should be called after seriesData.restoreData.
            var axisProxyNeedAlign: [(AxisProxy, AxisProxy)] = []
            dataZoomModel.eachTargetAxis { axisDim, axisIndex in
                guard let axisProxy = dataZoomModel.getAxisProxy(axisDim, axisIndex) else {
                    return
                }
                let alignToAxisProxy = getAlignTo(dataZoomModel, axisProxy)
                if let alignToAxisProxy = alignToAxisProxy {
                    axisProxyNeedAlign.append((axisProxy, alignToAxisProxy))
                }
                else {
                    axisProxy.reset(dataZoomModel, nil)
                }
            }
            util.each(axisProxyNeedAlign) { item, _ in
                item.0.reset(dataZoomModel, item.1.getWindow().percentInverted)
            }

            // Caution: data zoom filtering is order sensitive when using percent range and no
            // min/max/scale set on axis. (See upstream comment: reset+filter x-axis before y-axis.)
            dataZoomModel.eachTargetAxis { axisDim, axisIndex in
                dataZoomModel.getAxisProxy(axisDim, axisIndex)?.filterData(dataZoomModel, api)
            }
        }

        ecModel.eachComponent("dataZoom") { modelItem, _ in
            let dataZoomModel = modelItem as! DataZoomModel
            // Fullfill all of the range props so that user is able to get them from chart.getOption().
            if let axisProxy = dataZoomModel.findRepresentativeAxisProxy() {
                let window = axisProxy.getWindow()
                let percent = window.percent
                let value = window.value
                dataZoomModel.setCalculatedRange([
                    "start": percent[0],
                    "end": percent[1],
                    "startValue": value[0],
                    "endValue": value[1]
                ])
            }
        }
    }

    return handler
}()
