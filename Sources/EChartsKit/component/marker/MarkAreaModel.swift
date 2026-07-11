// Ported from echarts/src/component/marker/MarkAreaModel.ts — keep in sync with upstream
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
//   -> sibling MarkerModel.swift (`MarkerModel`, `MarkerOption`, `MarkerStatisticType`, `MarkerPositionOption`).
// import { SeriesLabelOption, ItemStyleOption, StatesOptionMixin, StatesMixinBase } from '../../util/types';
//   -> option interfaces collapsed to the dynamic `[String: Any]` bag (CONVENTIONS §2); preserved as
//      commented source below (declaration/type surface only).
// import GlobalModel from '../../model/Global';           -> EChartsKit `GlobalModel` (model/Global.swift).

// interface MarkAreaStateOption {
//     itemStyle?: ItemStyleOption
//     label?: SeriesLabelOption
//     z2?: number
// }
//
// interface MarkAreaDataItemOptionBase extends MarkAreaStateOption,
//     StatesOptionMixin<MarkAreaStateOption, StatesMixinBase> {
//     name?: string
// }
//
// // 1D markArea for horizontal or vertical. Similar to markLine
// export interface MarkArea1DDataItemOption extends MarkAreaDataItemOptionBase {
//     xAxis?: number
//     yAxis?: number
//     type?: MarkerStatisticType
//     valueIndex?: number
//     valueDim?: string
// }
//
// // 2D markArea on any direction. Similar to markLine
// interface MarkArea2DDataItemDimOption extends MarkAreaDataItemOptionBase, MarkerPositionOption {
// }
//
// export type MarkArea2DDataItemOption = [
//     // Start point
//     MarkArea2DDataItemDimOption,
//     // End point
//     MarkArea2DDataItemDimOption
// ];
//
// export interface MarkAreaOption extends MarkerOption, MarkAreaStateOption,
//     StatesOptionMixin<MarkAreaStateOption, StatesMixinBase> {
//     mainType?: 'markArea'
//     precision?: number
//     data?: (MarkArea1DDataItemOption | MarkArea2DDataItemOption)[]
// }
//
// PORT-NOTE: the above option interfaces are the typed documentation surface for the dynamic
//   `[String: Any]` option bag (CONVENTIONS §2/§4). `MarkArea2DDataItemOption` (the two-end tuple) is
//   consumed dynamically in MarkAreaView.swift (`markAreaTransform` reads `item[0]`/`item[1]`).

// upstream: class MarkAreaModel extends MarkerModel<MarkAreaOption>
//   The generic `Opts` is dropped per CONVENTIONS §2 (dynamic option bag). Concrete leaf →
//   `final class` (CONVENTIONS §2).
public final class MarkAreaModel: MarkerModel {

    // static type = 'markArea';
    // type = MarkAreaModel.type;  (instance `type` mirrors the static via the inherited computed prop)
    public override class var type: ComponentFullType { return "markArea" }

    // createMarkerModelFromSeries(markerOpt, masterMarkerModel, ecModel) {
    //     return new MarkAreaModel(markerOpt, masterMarkerModel, ecModel);
    // }
    public override func createMarkerModelFromSeries(
        _ markerOpt: Any?,
        _ masterMarkerModel: MarkerModel,
        _ ecModel: GlobalModel?
    ) -> MarkerModel {
        // upstream `new MarkAreaModel(markerOpt, masterMarkerModel, ecModel)`.
        //   `markerOpt` (dynamic option bag) -> `ModelOption?` (== `Any?`); `masterMarkerModel`
        //   (a MarkerModel, i.e. a Model) is the parentModel.
        return MarkAreaModel(markerOpt, masterMarkerModel, ecModel)
    }

    // static defaultOption: MarkAreaOption = { ... }
    public override class var defaultOption: ModelOption? {
        return [
            // zlevel: 0,
            // PENDING
            "z": 1.0,
            "tooltip": [
                "trigger": "item"
            ] as [String: Any],
            // markArea should fixed on the coordinate system
            "animation": false,
            "label": [
                "show": true,
                "position": "top"
            ] as [String: Any],
            "itemStyle": [
                // color and borderColor default to use color from series
                // color: 'auto'
                // borderColor: 'auto'
                "borderWidth": 0.0
            ] as [String: Any],

            "emphasis": [
                "label": [
                    "show": true,
                    "position": "top"
                ] as [String: Any]
            ] as [String: Any]
        ] as [String: Any]
    }
}

// export default MarkAreaModel;  -> `public final class MarkAreaModel` above.
