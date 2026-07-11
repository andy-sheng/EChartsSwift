// Ported from echarts/src/coord/single/singleCreator.ts — keep in sync with upstream
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

/**
 * Single coordinate system creator.
 */

import Foundation
import ZRenderKit

// upstream imports:
//   import Single, { singleDimensions } from './Single';                  -> Single + singleDimensions (sibling, Single.swift).
//   import GlobalModel from '../../model/Global';                         -> GlobalModel (model/Global.swift).
//   import ExtensionAPI from '../../core/ExtensionAPI';                   -> ExtensionAPI (core/ExtensionAPI.swift).
//   import SingleAxisModel, {
//       COMPONENT_TYPE_SINGLE_AXIS, COORD_SYS_TYPE_SINGLE, COORD_SYS_TYPE_SINGLE_AXIS_COMPATIBLE
//   } from './AxisModel';                                                 -> SingleAxisModel + constants (SingleAxisModel.swift).
//   import SeriesModel from '../../model/Series';                         -> SeriesModel (model/Series.swift).
//   import { SeriesOption } from '../../util/types';                      -> collapsed (dynamic option bag).
//   import { SINGLE_REFERRING } from '../../util/model';                  -> `model.SINGLE_REFERRING` (util/modelUtil.swift).
//   import { associateSeriesWithAxis } from '../axisStatistics';         -> associateSeriesWithAxis (coord/axisStatistics.swift).
//
// PORT-NOTE: `Single` (coord/single/Single.swift; the coord-sys master) + `singleDimensions` are ported
//   alongside this file in the same phase. `Single` exposes: name, resize(axisModel, api), getAxis()
//   (-> SingleAxis, an Axis), dataToPoint(_), getRect(). Re-narrow if the sibling surface differs.

// upstream: const singleCreator = { create, dimensions: singleDimensions };
//   (object literal → caseless enum namespace, mirroring polarCreator).
public enum singleCreator {

    // dimensions: singleDimensions
    public static let dimensions: [DimensionName] = singleDimensions

    /**
     * Create single coordinate system and inject it into seriesModel.
     */
    // create: function create(ecModel: GlobalModel, api: ExtensionAPI) { ... }
    public static func create(_ ecModel: GlobalModel, _ api: ExtensionAPI) -> [Single] {
        // const singles: Single[] = [];
        var singles: [Single] = []

        // ecModel.eachComponent(COMPONENT_TYPE_SINGLE_AXIS, function (axisModel: SingleAxisModel, idx: number) { ... });
        ecModel.eachComponent(COMPONENT_TYPE_SINGLE_AXIS) { (axisModelComp: ComponentModel, idx: Double) in
            guard let axisModel = axisModelComp as? SingleAxisModel else { return }

            // const single = new Single(axisModel, ecModel, api);
            let single = Single(axisModel, ecModel, api)
            // single.name = 'single_' + idx;
            single.name = "single_" + String(Int(idx))
            // single.resize(axisModel, api);
            single.resize(axisModel, api)
            // axisModel.coordinateSystem = single;
            axisModel.coordinateSystem = single
            // singles.push(single);
            singles.append(single)
        }

        // ecModel.eachSeries(function (seriesModel: SeriesModel<...>) { ... });
        ecModel.eachSeries { (seriesModel: SeriesModel, _: Double) in
            // if (seriesModel.get('coordinateSystem') === COORD_SYS_TYPE_SINGLE_AXIS_COMPATIBLE) { ... }
            if (seriesModel.get("coordinateSystem") as? String) == COORD_SYS_TYPE_SINGLE_AXIS_COMPATIBLE {
                // const singleAxisModel = seriesModel.getReferringComponents(
                //     COMPONENT_TYPE_SINGLE_AXIS, SINGLE_REFERRING
                // ).models[0] as SingleAxisModel;
                let singleAxisModel = seriesModel.getReferringComponents(
                    COMPONENT_TYPE_SINGLE_AXIS, model.SINGLE_REFERRING
                ).models.first as? SingleAxisModel

                // const single = seriesModel.coordinateSystem = singleAxisModel && singleAxisModel.coordinateSystem;
                //   `singleAxisModel && singleAxisModel.coordinateSystem` -> nil if no axis model, else its
                //   coordinateSystem. SingleAxisModel.coordinateSystem is typed `CoordinateSystemMaster?`
                //   (mirroring PolarModel), so narrow to the concrete `Single` for `getAxis()` below.
                let single = singleAxisModel?.coordinateSystem as? Single
                seriesModel.coordinateSystem = single
                // if (single) { associateSeriesWithAxis(single.getAxis(), seriesModel, COORD_SYS_TYPE_SINGLE); }
                if let single = single {
                    associateSeriesWithAxis(single.getAxis(), seriesModel, COORD_SYS_TYPE_SINGLE)
                }
            }
        }

        // return singles;
        return singles
    }
}

// export default singleCreator;  -> `public enum singleCreator` above.
