// Ported from echarts/src/coord/parallel/parallelCreator.ts — keep in sync with upstream
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
 * Parallel coordinate system creator.
 */

import Foundation
import ZRenderKit

// upstream imports:
//   import Parallel from './Parallel';                                    -> Parallel (coord/parallel/Parallel.swift;
//       the parallel coord-sys master). note: ported sibling. This file references it (constructor +
//       `.name`/`.resize`/`.model`/`.dimensions`/`.getAxis`); the return type below is the upstream
//       `CoordinateSystemMaster[]` (not `[Parallel]`), so only the body depends on Parallel.
//   import GlobalModel from '../../model/Global';                         -> GlobalModel (model/Global.swift).
//   import ExtensionAPI from '../../core/ExtensionAPI';                   -> ExtensionAPI (core/ExtensionAPI.swift).
//   import ParallelModel, { COMPONENT_TYPE_PARALLEL, COORD_SYS_TYPE_PARALLEL } from './ParallelModel';
//       -> ParallelModel + constants (sibling, ParallelModel.swift).
//   import { CoordinateSystemMaster } from '../CoordinateSystem';         -> CoordinateSystemMaster (coord/CoordinateSystem.swift).
//   import ParallelSeriesModel from '../../chart/parallel/ParallelSeries';
//       -> ParallelSeriesModel (chart/parallel/ParallelSeries.swift; forthcoming). Erased to the SeriesModel
//          base — the `.get('coordinateSystem')` read lives there.
//   import { SINGLE_REFERRING } from '../../util/model';                  -> `model.SINGLE_REFERRING` (util/modelUtil.swift).
//   import { each } from 'zrender/src/core/util';                         -> `util.each` (ZRenderKit).
//   import { associateSeriesWithAxis } from '../axisStatistics';         -> associateSeriesWithAxis (coord/axisStatistics.swift).

// function createParallelCoordSys(ecModel: GlobalModel, api: ExtensionAPI): CoordinateSystemMaster[]
private func createParallelCoordSys(_ ecModel: GlobalModel, _ api: ExtensionAPI) -> [CoordinateSystemMaster] {
    // const coordSysList: CoordinateSystemMaster[] = [];
    var coordSysList: [CoordinateSystemMaster] = []

    // ecModel.eachComponent(COMPONENT_TYPE_PARALLEL, function (parallelModel: ParallelModel, idx: number) { ... });
    ecModel.eachComponent(COMPONENT_TYPE_PARALLEL) { (parallelModelComp: ComponentModel, idx: Double) in
        guard let parallelModel = parallelModelComp as? ParallelModel else { return }

        // const coordSys = new Parallel(parallelModel, ecModel, api);
        let coordSys = Parallel(parallelModel, ecModel, api)

        // coordSys.name = 'parallel_' + idx;
        coordSys.name = "parallel_" + String(Int(idx))
        // coordSys.resize(parallelModel, api);
        coordSys.resize(parallelModel, api)

        // parallelModel.coordinateSystem = coordSys;
        parallelModel.coordinateSystem = coordSys
        // coordSys.model = parallelModel;
        coordSys.model = parallelModel

        // coordSysList.push(coordSys);
        coordSysList.append(coordSys)
    }

    // Inject the coordinateSystems into seriesModel
    // ecModel.eachSeries(function (seriesModel) { ... });
    ecModel.eachSeries { (seriesModel: SeriesModel, _: Double) in
        // if ((seriesModel as ParallelSeriesModel).get('coordinateSystem') === COORD_SYS_TYPE_PARALLEL) { ... }
        if (seriesModel.get("coordinateSystem") as? String) == COORD_SYS_TYPE_PARALLEL {
            // const parallelModel = seriesModel.getReferringComponents(
            //     COMPONENT_TYPE_PARALLEL, SINGLE_REFERRING
            // ).models[0] as ParallelModel;
            let parallelModel = seriesModel.getReferringComponents(
                COMPONENT_TYPE_PARALLEL, model.SINGLE_REFERRING
            ).models.first as? ParallelModel

            // const parallel = seriesModel.coordinateSystem = parallelModel.coordinateSystem;
            //   ParallelModel.coordinateSystem is typed `CoordinateSystemMaster?` (mirroring PolarModel), so
            //   narrow to the concrete `Parallel` for `.dimensions`/`.getAxis(dim)` below.
            // DEVIATION (nested-optional-in-Any boxing): assign the UNWRAPPED non-optional `Parallel` to
            //   `SeriesModel.coordinateSystem` (typed `Any?`). Assigning an `Optional<Parallel>` boxes as
            //   `.some(Optional<Parallel>)`, which downstream `as? Parallel` (in ParallelView.render) fails
            //   to see through. Store the existential unwrapped so the downcast succeeds (per the integration
            //   note; same reasoning as CoordinateSystemManager.injectCoordSysByOption).
            if let parallel = parallelModel?.coordinateSystem as? Parallel {
                seriesModel.coordinateSystem = parallel

                // if (parallel) {
                //     each(parallel.dimensions, function (dim) {
                //         associateSeriesWithAxis(parallel.getAxis(dim), seriesModel, COORD_SYS_TYPE_PARALLEL);
                //     });
                // }
                util.each(parallel.dimensions) { dim, _ in
                    associateSeriesWithAxis(parallel.getAxis(dim), seriesModel, COORD_SYS_TYPE_PARALLEL)
                }
            } else {
                seriesModel.coordinateSystem = nil
            }
        }
    }

    // return coordSysList;
    return coordSysList
}

// const parallelCoordSysCreator = { create: createParallelCoordSys };
//   (object literal → caseless enum namespace, mirroring polarCreator / singleCreator).
public enum parallelCoordSysCreator {

    // create: createParallelCoordSys
    public static func create(_ ecModel: GlobalModel, _ api: ExtensionAPI) -> [CoordinateSystemMaster] {
        return createParallelCoordSys(ecModel, api)
    }
}

// export default parallelCoordSysCreator;  -> `public enum parallelCoordSysCreator` above.
