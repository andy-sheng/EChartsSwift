// Ported from echarts/src/model/referHelper.ts — keep in sync with upstream

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
 * Helper for model references.
 * There are many manners to refer axis/coordSys.
 */

// TODO
// merge relevant logic to this file?
// check: "modelHelper" of tooltip and "BrushTargetManager".

import ZRenderKit  // upstream: createHashMap, retrieve, each, HashMap from 'zrender/src/core/util'

// upstream imports (translated against the conventional public API of sibling files):
//   import {createHashMap, retrieve, each, HashMap} from 'zrender/src/core/util';
//       -> ZRenderKit.util.{retrieve, each}; HashMap/createHashMap are the EChartsKit shims
//          in util/model.swift (until ZRenderKit ports them — see that PORT-TODO).
//   import SeriesModel from './Series';                          -> SeriesModel (util/types.swift stub; real type lands this phase)
//   import type PolarModel from '../coord/polar/PolarModel';     -> PolarModel  (PORT-TODO placeholder below)
//   import type { SeriesOption, SeriesOnCartesianOptionMixin } from '../util/types';  -> generics dropped
//   import type { AxisBaseModel } from '../coord/AxisBaseModel'; -> AxisBaseModel (PORT-TODO placeholder below)
//   import { SINGLE_REFERRING } from '../util/model';            -> model.SINGLE_REFERRING (util/model.swift)
//   import { ParallelSeriesOption } from '../chart/parallel/ParallelSeries';  -> generics dropped
//   import ParallelModel from '../coord/parallel/ParallelModel'; -> ParallelModel (PORT-TODO placeholder below)
//   import ParallelAxisModel from '../coord/parallel/AxisModel'; -> ParallelAxisModel (PORT-TODO placeholder below)
//   import MatrixModel from '../coord/matrix/MatrixModel';       -> MatrixModel (PORT-TODO placeholder below)
//   import type Model from './Model';                            -> Model (util/types.swift stub)
//   import { AxisBaseOptionCommon } from '../coord/axisCommonTypes';            -> coord/axisCommonTypes.swift
//   import { AxisModelExtendedInCreator } from '../coord/axisModelCreator';     -> not yet ported (FetcherAxisModel)

// ============================================================================
// PORT-TODO: FORWARD-REFERENCE PLACEHOLDERS for coordinate-system models.
// These types live under `echarts/src/coord/**`, which is NOT ported in this
// (model-layer) phase. They are declared here as minimal placeholders exposing
// only the surface `referHelper` touches, so this file compiles. The agent that
// ports the corresponding coord source MUST remove the placeholder here and use
// the real, fully-ported type. They are deliberately *not* refined from
// `ComponentModel` (which becomes a concrete reference type this phase — a Swift
// protocol cannot inherit from a class), so the `as?` downcasts below stay valid.
// ============================================================================

// '../coord/AxisBaseModel' — AxisBaseModel is now the real, fully-ported reference type in
//   coord/AxisBaseModel.swift (an `open class` extending ComponentModel). The former PORT-TODO
//   placeholder protocol declared here has been removed per its own note; the `func get(...)` it
//   exposed is provided by ComponentModel's Model.get. (FetcherAxisModel, which upstream Picks
//   `getOrdinalMeta` from AxisModelExtendedInCreator, is still collapsed to AxisBaseModel below.)
// '../coord/polar/PolarModel' — PolarModel is now the real, fully-ported reference type in
//   coord/polar/PolarModel.swift (a `final class : ComponentModel, CoordinateSystemHostModel`).
//   The former PORT-TODO placeholder protocol declared here has been removed per its own note;
//   `findAxisModel` on the real class returns the concrete `PolarAxisModel?` (a subclass of
//   AxisBaseModel), so the `axisMap.set`/`isCategory` uses below stay valid.
// '../coord/parallel/ParallelModel' — ParallelModel is now the real, fully-ported reference type in
//   coord/parallel/ParallelModel.swift (a `final class : ComponentModel, CoordinateSystemHostModel`).
//   The former PORT-TODO placeholder protocol declared here has been removed per its own note.
// '../coord/parallel/AxisModel' — ParallelAxisModel is now the real, fully-ported reference type in
//   coord/parallel/ParallelAxisModel.swift (an `AxisBaseModel` subclass). The former PORT-TODO
//   placeholder subclass declared here has been removed per its own note.
// '../coord/matrix/MatrixModel' — MatrixModel is now the real, fully-ported reference type in
//   coord/matrix/MatrixModel.swift (a `final class : ComponentModel, CoordinateSystemHostModel`).
//   The former PORT-TODO placeholder protocol declared here has been removed per its own note.

/**
 * @class
 * For example:
 * {
 *     coordSysName: 'cartesian2d',
 *     coordSysDims: ['x', 'y', ...],
 *     axisMap: HashMap({
 *         x: xAxisModel,
 *         y: yAxisModel
 *     }),
 *     categoryAxisMap: HashMap({
 *         x: xAxisModel,
 *         y: undefined
 *     }),
 *     // The index of the first category axis in `coordSysDims`.
 *     // `null/undefined` means no category axis exists.
 *     firstCategoryDimIndex: 1,
 *     // To replace user specified encode.
 * }
 */

public final class SeriesModelCoordSysInfo {

    public var coordSysName: String

    public var coordSysDims: [String] = []

    public var axisMap: HashMap<AxisBaseModel> = createHashMap()

    public var categoryAxisMap: HashMap<AxisBaseModel> = createHashMap()

    public var firstCategoryDimIndex: Double?   // upstream `number`, may be null/undefined

    public init(_ coordSysName: String) {
        self.coordSysName = coordSysName
    }
}

// upstream: type SupportedCoordSys = 'cartesian2d' | 'polar' | 'singleAxis' | 'geo' | 'parallel' | 'matrix';
public typealias SupportedCoordSys = String                                // PORT-TODO: string union narrowed to String
// upstream: type FetcherAxisModel = Model<Pick<AxisBaseOptionCommon,'type'>> & Pick<AxisModelExtendedInCreator,'getOrdinalMeta'>;
public typealias FetcherAxisModel = AxisBaseModel                          // PORT-TODO: structural Pick type collapsed to AxisBaseModel
// upstream: type Fetcher = (seriesModel, result, axisMap, categoryAxisMap) => void;
public typealias Fetcher = (
    _ seriesModel: SeriesModel,
    _ result: SeriesModelCoordSysInfo,
    _ axisMap: HashMap<FetcherAxisModel>,
    _ categoryAxisMap: HashMap<FetcherAxisModel>
) -> Void

// PORT-TODO: returns `undefined` when no fetcher matches the coordSysName, hence Optional.
public func getCoordSysInfoBySeries(_ seriesModel: SeriesModel) -> SeriesModelCoordSysInfo? {
    let coordSysName = seriesModel.get("coordinateSystem") as? SupportedCoordSys ?? ""  // PORT-TODO: as SupportedCoordSys
    let result = SeriesModelCoordSysInfo(coordSysName)
    let fetch = fetchers[coordSysName]
    if let fetch = fetch {
        fetch(seriesModel, result, result.axisMap, result.categoryAxisMap)
        return result
    }
    return nil
}

// TODO: refactor them to static member of each coord sys, rather than hard code here.
private let fetchers: [SupportedCoordSys: Fetcher] = [

    "cartesian2d": { seriesModel, result, axisMap, categoryAxisMap in
        let xAxisModel = seriesModel.getReferringComponents("xAxis", model.SINGLE_REFERRING).models.first as? AxisBaseModel
        let yAxisModel = seriesModel.getReferringComponents("yAxis", model.SINGLE_REFERRING).models.first as? AxisBaseModel

        if __DEV__ {
            if xAxisModel == nil {
                // PORT-TODO: upstream `throw new Error(...)`; surfaced as fatalError (no throwing signature).
                fatalError("xAxis \"\(util.retrieve(seriesModel.get("xAxisIndex"), seriesModel.get("xAxisId"), 0 as Any) ?? 0)\" not found")
            }
            if yAxisModel == nil {
                // PORT-TODO: upstream `throw new Error(...)`; surfaced as fatalError (no throwing signature).
                // (Upstream uses `xAxisIndex` here too — preserved faithfully.)
                fatalError("yAxis \"\(util.retrieve(seriesModel.get("xAxisIndex"), seriesModel.get("yAxisId"), 0 as Any) ?? 0)\" not found")
            }
        }

        result.coordSysDims = ["x", "y"]
        // PORT-TODO: upstream HashMap<AxisBaseModel> may hold undefined; Swift maps are
        //   non-optional so we force-unwrap post the __DEV__ guard.
        axisMap.set("x", xAxisModel!)
        axisMap.set("y", yAxisModel!)

        if isCategory(xAxisModel!) {
            categoryAxisMap.set("x", xAxisModel!)
            result.firstCategoryDimIndex = 0
        }
        if isCategory(yAxisModel!) {
            categoryAxisMap.set("y", yAxisModel!)
            if result.firstCategoryDimIndex == nil { result.firstCategoryDimIndex = 1 }
        }
    },

    "singleAxis": { seriesModel, result, axisMap, categoryAxisMap in
        let singleAxisModel = seriesModel.getReferringComponents(
            "singleAxis", model.SINGLE_REFERRING
        ).models.first as? AxisBaseModel

        if __DEV__ {
            if singleAxisModel == nil {
                // PORT-TODO: upstream `throw new Error(...)`; surfaced as fatalError (no throwing signature).
                fatalError("singleAxis should be specified.")
            }
        }

        result.coordSysDims = ["single"]
        axisMap.set("single", singleAxisModel!)

        if isCategory(singleAxisModel!) {
            categoryAxisMap.set("single", singleAxisModel!)
            result.firstCategoryDimIndex = 0
        }
    },

    "polar": { seriesModel, result, axisMap, categoryAxisMap in
        let polarModel = seriesModel.getReferringComponents("polar", model.SINGLE_REFERRING).models.first as? PolarModel
        let radiusAxisModel = polarModel?.findAxisModel("radiusAxis")
        let angleAxisModel = polarModel?.findAxisModel("angleAxis")

        if __DEV__ {
            if angleAxisModel == nil {
                // PORT-TODO: upstream `throw new Error(...)`; surfaced as fatalError (no throwing signature).
                fatalError("angleAxis option not found")
            }
            if radiusAxisModel == nil {
                // PORT-TODO: upstream `throw new Error(...)`; surfaced as fatalError (no throwing signature).
                fatalError("radiusAxis option not found")
            }
        }

        result.coordSysDims = ["radius", "angle"]
        axisMap.set("radius", radiusAxisModel!)
        axisMap.set("angle", angleAxisModel!)

        if isCategory(radiusAxisModel!) {
            categoryAxisMap.set("radius", radiusAxisModel!)
            result.firstCategoryDimIndex = 0
        }
        if isCategory(angleAxisModel!) {
            categoryAxisMap.set("angle", angleAxisModel!)
            if result.firstCategoryDimIndex == nil { result.firstCategoryDimIndex = 1 }
        }
    },

    "geo": { seriesModel, result, axisMap, categoryAxisMap in
        result.coordSysDims = ["lng", "lat"]
    },

    "parallel": { seriesModel, result, axisMap, categoryAxisMap in
        // upstream `ComponentModel.ecModel` is non-null; `Model.ecModel` is `GlobalModel?` in the port
        // (see the reconciliation PORT-TODO in util/types.swift, resolved now that model/Global landed).
        let ecModel = seriesModel.ecModel!
        let parallelModel = ecModel.getComponent(
            "parallel", seriesModel.get("parallelIndex") as? Double
        ) as? ParallelModel
        let coordSysDims = parallelModel?.dimensions ?? []   // PORT-TODO: upstream `.slice()` (value copy); parallelModel assumed non-null
        result.coordSysDims = coordSysDims

        util.each(parallelModel?.parallelAxisIndex) { axisIndex, index in
            let axisModel = ecModel.getComponent("parallelAxis", axisIndex) as? ParallelAxisModel
            let axisDim = coordSysDims[index]
            axisMap.set(axisDim, axisModel!)

            if isCategory(axisModel!) {
                categoryAxisMap.set(axisDim, axisModel!)
                if result.firstCategoryDimIndex == nil {
                    result.firstCategoryDimIndex = Double(index)
                }
            }
        }
    },

    "matrix": { seriesModel, result, axisMap, categoryAxisMap in
        let matrixModel = seriesModel.getReferringComponents(
            "matrix", model.SINGLE_REFERRING
        ).models.first as? MatrixModel

        if __DEV__ {
            if matrixModel == nil {
                // PORT-TODO: upstream `throw new Error(...)`; surfaced as fatalError (no throwing signature).
                fatalError("matrix coordinate system should be specified.")
            }
        }

        result.coordSysDims = ["x", "y"]
        // upstream:
        //   const xModel = matrixModel.getDimensionModel('x');
        //   const yModel = matrixModel.getDimensionModel('y');
        //   axisMap.set('x', xModel); axisMap.set('y', yModel);
        //   categoryAxisMap.set('x', xModel); categoryAxisMap.set('y', yModel);
        // PORT-TODO (DEFERRED): `getDimensionModel` returns `MatrixDimensionModel` (a `Model` with
        //   `.get('type')`/`getOrdinalMeta()`), but this port collapsed the structural upstream
        //   `FetcherAxisModel` to the concrete `AxisBaseModel` (see the typealias above), and
        //   MatrixDimensionModel is NOT an AxisBaseModel — so it cannot be inserted into the
        //   `HashMap<AxisBaseModel>` axisMap here. No series is registered on the `matrix` coordinate
        //   system in the port (matrix is a custom-series/nonSeriesBox coord — Phase 6b), so this
        //   fetcher is never invoked; the axisMap population is left as a PORT-TODO to be wired once
        //   FetcherAxisModel is widened to the structural (type + getOrdinalMeta) protocol.
        _ = matrixModel?.getDimensionModel("x")
        _ = matrixModel?.getDimensionModel("y")
        _ = axisMap
        _ = categoryAxisMap
    },
]

private func isCategory(_ axisModel: AxisBaseModel) -> Bool {
    return (axisModel.get("type") as? String) == "category"
}
