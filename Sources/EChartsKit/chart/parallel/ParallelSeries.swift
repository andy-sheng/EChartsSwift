// Ported from echarts/src/chart/parallel/ParallelSeries.ts — keep in sync with upstream
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
//   import {each, bind} from 'zrender/src/core/util';                -> `util.each` (ZRenderKit); `bind` is
//       inlined as a Swift closure that captures `self` (see getInitialData).
//   import SeriesModel from '../../model/Series';                    -> SeriesModel (model/Series.swift).
//   import createSeriesData from '../helper/createSeriesData';       -> `createSeriesData`
//       (sibling chart/helper/createSeriesData.swift).
//   import { ... option mixins ... } from '../../util/types';        -> util/types.swift (type-only; the
//       dynamic option tree is the `[String: Any]` bag per CONVENTIONS §2).
//   import GlobalModel from '../../model/Global';                    -> GlobalModel (model/Global.swift).
//   import SeriesData from '../../data/SeriesData';                  -> SeriesData (data/SeriesData.swift).
//   import { ParallelActiveState, ParallelAxisOption } from '../../coord/parallel/AxisModel';
//       -> ParallelActiveState (coord/parallel/ParallelAxisModel.swift — sibling coord-system track).
//   import Parallel from '../../coord/parallel/Parallel';            -> Parallel (coord/parallel/Parallel.swift).
//   import ParallelModel from '../../coord/parallel/ParallelModel';  -> ParallelModel (coord/parallel/ParallelModel.swift).

// ============================================================================
// The following upstream `type`/`interface` declarations describe the (dynamic) option tree.
// Per CONVENTIONS §2 the option tree is the `[String: Any]` bag; these types are kept as documentation
// only (the diffable surface) — no Swift types are emitted for them.
// ============================================================================
//
// type ParallelSeriesDataValue = OptionDataValue[];
//
// interface ParallelStatesMixin { emphasis?: DefaultStatesMixinEmphasis }
// export interface ParallelStateOption<TCbParams = never> {
//     lineStyle?: LineStyleOption<(TCbParams extends never ? never : (params: TCbParams) => ZRColor) | ZRColor>
//     label?: SeriesLabelOption
// }
// export interface ParallelSeriesDataItemOption extends ParallelStateOption,
//     StatesOptionMixin<ParallelStateOption, ParallelStatesMixin> {
//     value?: ParallelSeriesDataValue
// }
// export interface ParallelSeriesOption extends
//     SeriesOption<ParallelStateOption<CallbackDataParams>, ParallelStatesMixin>,
//     ParallelStateOption<CallbackDataParams>,
//     ComponentOnCalendarOptionMixin,
//     ComponentOnMatrixOptionMixin,
//     SeriesEncodeOptionMixin {
//     type?: 'parallel';
//     coordinateSystem?: string;
//     parallelIndex?: number;
//     parallelId?: string;
//     inactiveOpacity?: number;
//     activeOpacity?: number;
//     smooth?: boolean | number;
//     realtime?: boolean;
//     tooltip?: SeriesTooltipOption;
//     parallelAxisDefault?: ParallelAxisOption;
//     data?: (ParallelSeriesDataValue | ParallelSeriesDataItemOption)[]
// }

// upstream: class ParallelSeriesModel extends SeriesModel<ParallelSeriesOption>
//   The generic `Opts` is dropped per CONVENTIONS §2 (the dynamic option tree is the `[String: Any]`
//   bag). `open class` matches the port's model style (Series/Component are `open`).
open class ParallelSeriesModel: SeriesModel {

    // upstream: static type = 'series.parallel';  /  readonly type = ParallelSeriesModel.type;
    //   The static drives the instance `type` (inherited `var type { Self.type }` from ComponentModel).
    public override class var type: ComponentFullType { return "series.parallel" }

    // upstream: static dependencies = ['parallel'];
    public override class var dependencies: [String] {
        return ["parallel"]
    }

    // upstream (instance field): coordinateSystem: Parallel;
    //   The base `SeriesModel` declares `open var coordinateSystem: Any?`; upstream narrows it to
    //   `Parallel`. A stored `Any?` var can not be overridden by a typed one, so the typed view is
    //   exposed as a computed accessor and use sites downcast (mirrors RadarSeries `radarCoordinateSystem`).
    open var parallelCoordinateSystem: Parallel? { return self.coordinateSystem as? Parallel }

    // upstream (instance fields, set on the class body):
    //   visualStyleAccessPath = 'lineStyle';
    //   visualDrawType = 'stroke' as const;
    //   The base `SeriesModel` declares these as stored `open var`s (defaulting to 'itemStyle'/'fill'),
    //   which a subclass field can not re-default, so they are assigned in the `init` lifecycle override
    //   below — faithful to the upstream class-body field initializers (same pattern as RadarSeries).
    open override func `init`(
        _ option: ModelOption?, _ parentModel: Model? = nil, _ ecModel: GlobalModel? = nil, _ rest: Any...
    ) {
        super.`init`(option, parentModel, ecModel)

        self.visualStyleAccessPath = "lineStyle"
        self.visualDrawType = "stroke"
    }

    // upstream: getInitialData(this: ParallelSeriesModel, option, ecModel: GlobalModel): SeriesData { ... }
    open override func getInitialData(_ option: ModelOption?, _ ecModel: GlobalModel?) -> SeriesData? {
        // return createSeriesData(null, this, {
        //     useEncodeDefaulter: bind(makeDefaultEncode, null, this)
        // });
        //   `bind(makeDefaultEncode, null, this)` fixes the series as the (only) real argument, yielding a
        //   `(source, dimCount) => OptionEncode` that ignores both trailing args — exactly the
        //   `EncodeDefaulter` shape. `useEncodeDefaulter` is the `Bool | EncodeDefaulter` union slot on
        //   `CreateSeriesDataOpt` (typed `Any?`); createSeriesData downcasts it to `EncodeDefaulter`.
        return createSeriesData(nil, self, CreateSeriesDataOpt(
            useEncodeDefaulter: { [weak self] (_ source: Source, _ dimCount: Double) -> OptionEncode in
                guard let self = self else { return [:] }
                // PORT-TODO: `makeDefaultEncode` returns `undefined` when no parallel component exists;
                //   the ported `EncodeDefaulter` return is non-optional, so the empty encode `[:]` stands
                //   in for that `undefined` (both leave the encode undefined downstream).
                return makeDefaultEncode(self) ?? [:]
            }
        ))
    }

    /**
     * User can get data raw indices on 'axisAreaSelected' event received.
     *
     * @return Raw indices
     */
    // upstream: getRawIndicesByActiveState(activeState: ParallelActiveState): number[]
    // PORT-TODO: depends on `Parallel.eachActiveState` — part of the parallelAxis brush / active-interval
    //   selection path, which is DEFERRED (see task scope). Body is ported faithfully; `eachActiveState`
    //   is provided by the coord/parallel track.
    open func getRawIndicesByActiveState(_ activeState: ParallelActiveState) -> [Double] {
        // const coordSys = this.coordinateSystem;
        let coordSys = self.parallelCoordinateSystem
        // const data = this.getData();
        let data = self.getData()
        // const indices = [] as number[];
        var indices: [Double] = []

        // coordSys.eachActiveState(data, function (theActiveState, dataIndex) { ... });
        coordSys?.eachActiveState(data, { (theActiveState: ParallelActiveState, dataIndex: Int) in
            if activeState == theActiveState {
                // indices.push(data.getRawIndex(dataIndex));
                indices.append(Double(data.getRawIndex(dataIndex)))
            }
        })

        return indices
    }

    // upstream: static defaultOption: ParallelSeriesOption = { ... }
    open override class var defaultOption: ModelOption? {
        return [
            // zlevel: 0,
            "z": 2.0,

            "coordinateSystem": "parallel",
            // DEVIATION (Int-vs-Double option-read trap): store as a Double literal, NOT `0`. This value is
            //   read via `getReferringComponents("parallel", …)` → `queryComponents` → `normalizeToArray<Double>`,
            //   and `Int(0) as? Double` is `nil` in Swift — a bare `0` would make the parallel-component query
            //   return no models, leaving `seriesModel.coordinateSystem` nil (no polylines rendered).
            "parallelIndex": 0.0,

            "label": [
                "show": false
            ] as [String: Any],

            "inactiveOpacity": 0.05,
            "activeOpacity": 1,

            "lineStyle": [
                "width": 1,
                "opacity": 0.45,
                "type": "solid"
            ] as [String: Any],
            "emphasis": [
                "label": [
                    "show": false
                ] as [String: Any]
            ] as [String: Any],

            "progressive": 300,
            "smooth": false, // true | false | number

            "animationEasing": "linear"
        ] as [String: Any]
    }

}

// upstream: function makeDefaultEncode(seriesModel: ParallelSeriesModel): OptionEncode { ... }
//   Returns `OptionEncode?` — upstream `return;` (undefined) when no parallel component is found.
func makeDefaultEncode(_ seriesModel: ParallelSeriesModel) -> OptionEncode? {
    // The mapping of parallelAxis dimension to data dimension can
    // be specified in parallelAxis.option.dim. For example, if
    // parallelAxis.option.dim is 'dim3', it mapping to the third
    // dimension of data. But `data.encode` has higher priority.
    // Moreover, parallelModel.dimension should not be regarded as data
    // dimensions. Consider dimensions = ['dim4', 'dim2', 'dim6'];

    // const parallelModel = seriesModel.ecModel.getComponent(
    //     'parallel', seriesModel.get('parallelIndex')
    // ) as ParallelModel;
    // PORT-TODO (CONVENTIONS trap 1): `parallelIndex` is stored as a bare `Int` in defaultOption, so it is
    //   read through `numOpt` (never a bare `as? Double`, which would silently drop the Int).
    let parallelModel = seriesModel.ecModel?.getComponent(
        "parallel", numOpt(seriesModel.get("parallelIndex"))
    ) as? ParallelModel
    // if (!parallelModel) { return; }
    guard let parallelModel = parallelModel else {
        return nil
    }

    // const encodeDefine: Dictionary<OptionEncodeValue> = {};
    var encodeDefine: [String: OptionEncodeValue] = [:]
    // each(parallelModel.dimensions, function (axisDim) { ... });
    util.each(parallelModel.dimensions) { (axisDim: DimensionName, _: Int) in
        let dataDimIndex = convertDimNameToNumber(axisDim)
        encodeDefine[axisDim] = dataDimIndex
    }

    return encodeDefine
}

// upstream: function convertDimNameToNumber(dimName: DimensionName): number
//   return +dimName.replace('dim', '');
func convertDimNameToNumber(_ dimName: DimensionName) -> Double {
    // PORT-TODO (CONVENTIONS §5): JS `+"..."` string→number coercion; falls back to 0 on parse failure
    //   (upstream would yield NaN — parallel dim names are always well-formed `dim<N>`, so 0 is unreached).
    return Double(dimName.replacingOccurrences(of: "dim", with: "")) ?? 0
}

// export default ParallelSeriesModel;  -> `open class ParallelSeriesModel` above.

// INT-vs-DOUBLE option reader (CONVENTIONS trap 1): `[String: Any]` option bags store numbers as bare
// `Int`/`Double`/`NSNumber`; a plain `as? Double` silently drops an Int. Not an upstream symbol.
private func numOpt(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return nil
}
