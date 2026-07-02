// Ported from echarts/src/component/marker/MarkLineModel.ts — keep in sync with upstream
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

import ZRenderKit
// import MarkerModel, { MarkerOption, MarkerStatisticType, MarkerPositionOption } from './MarkerModel';
//   -> sibling MarkerModel.swift (`MarkerModel` class, `MarkerOption`/`MarkerStatisticType`/
//      `MarkerPositionOption` types).
// import GlobalModel from '../../model/Global';                       -> EChartsKit `GlobalModel`
// import { LineStyleOption, SeriesLineLabelOption, SymbolOptionMixin, ItemStyleOption,
//          StatesOptionMixin, StatesMixinBase } from '../../util/types'; -> util/types.swift
//
// The TS `interface`s below (MarkLineStateOption, MarkLine1DDataItemOption,
// MarkLine2DDataItemOption, MarkLineOption) are pure option-shape declarations consumed
// dynamically via the `[String: Any]` option bag (ComponentModel.option). Per CONVENTIONS §4 a
// plain data-bag interface maps to documentation here; the runtime shape is the dynamic bag, so
// they are captured as comments rather than empty structs to avoid dead types.
//
// interface MarkLineStateOption { lineStyle?; itemStyle? /* for symbol */; label?; z2? }
// interface MarkLineDataItemOptionBase extends MarkLineStateOption, StatesOptionMixin { name? }
// export interface MarkLine1DDataItemOption extends MarkLineDataItemOptionBase {
//     xAxis?; yAxis?; type?; valueIndex?; valueDim?;
//     symbol?; symbolSize?; symbolRotate?; symbolOffset?;   // both ends
// }
// interface MarkLine2DDataItemDimOption extends MarkLineDataItemOptionBase, SymbolOptionMixin,
//     MarkerPositionOption {}
// export type MarkLine2DDataItemOption = [ /* start */ MarkLine2DDataItemDimOption,
//                                          /* end */   MarkLine2DDataItemDimOption ];
// export interface MarkLineOption extends MarkerOption, MarkLineStateOption, StatesOptionMixin {
//     mainType?: 'markLine'
//     symbol?; symbolSize?; symbolRotate?; symbolOffset?;
//     precision?;   // used on statistic method
//     data?: (MarkLine1DDataItemOption | MarkLine2DDataItemOption)[]
// }

// class MarkLineModel extends MarkerModel<MarkLineOption>
//   The generic `Opts` is dropped per CONVENTIONS §2 (dynamic option bag).
final class MarkLineModel: MarkerModel {

    // static type = 'markLine';
    static let mlType = "markLine"
    // type = MarkLineModel.type;  (instance `type` mirrors the static via the inherited computed prop)
    override class var type: ComponentFullType { return MarkLineModel.mlType }

    // createMarkerModelFromSeries(markerOpt, masterMarkerModel, ecModel) {
    //     return new MarkLineModel(markerOpt, masterMarkerModel, ecModel);
    // }
    // upstream `masterMarkerModel: MarkLineModel`; the base signature types it `MarkerModel`.
    override func createMarkerModelFromSeries(
        _ markerOpt: Any?,
        _ masterMarkerModel: MarkerModel,
        _ ecModel: GlobalModel?
    ) -> MarkerModel {
        return MarkLineModel(markerOpt, masterMarkerModel, ecModel)
    }

    // static defaultOption: MarkLineOption = { ... }
    //   -> overridable class var holding the object literal (CONVENTIONS §2; cf. LegendModel).
    override class var defaultOption: ModelOption? {
        return [
            // zlevel: 0,
            "z": 5.0,

            "symbol": ["circle", "arrow"],
            "symbolSize": [8.0, 16.0],

            // symbolRotate: 0,
            "symbolOffset": 0.0,

            "precision": 2.0,
            "tooltip": [
                "trigger": "item"
            ],
            "label": [
                "show": true,
                "position": "end",
                "distance": 5.0
            ],
            "lineStyle": [
                "type": "dashed"
            ],
            "emphasis": [
                "label": [
                    "show": true
                ],
                "lineStyle": [
                    "width": 3.0
                ]
            ],
            "animationEasing": "linear"
        ]
    }
}

// export default MarkLineModel;  -> `final class MarkLineModel` above.
