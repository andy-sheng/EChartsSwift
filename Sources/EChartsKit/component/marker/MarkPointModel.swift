// Ported from echarts/src/component/marker/MarkPointModel.ts — keep in sync with upstream
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
// import MarkerModel, { MarkerOption, MarkerPositionOption } from './MarkerModel'; -> sibling MarkerModel.swift
// import GlobalModel from '../../model/Global';                                    -> EChartsKit `GlobalModel`
// import { SymbolOptionMixin, ItemStyleOption, SeriesLabelOption, CallbackDataParams,
//          StatesOptionMixin, StatesMixinBase } from '../../util/types';           -> EChartsKit util/types.swift

// interface MarkPointCallbackDataParams extends CallbackDataParams { ... }   (commented out upstream)

// interface MarkPointStateOption {
//     itemStyle?: ItemStyleOption
//     label?: SeriesLabelOption
//     z2?: number
// }
// PORT-NOTE: the `MarkPointStateOption` / `MarkPointDataItemOption` / `MarkPointOption` typed
//   interfaces (a documentation/type surface over the dynamic `[String: Any]` option bag, per
//   CONVENTIONS §4) are not modeled as Swift structs here — the runtime option is the dynamic bag on
//   `ComponentModel.option`, and the per-item data flows as `MarkerPositionOption` (see MarkerModel.swift).
//   Kept as commented source for the diffable surface:
//
//   export interface MarkPointDataItemOption extends
//       MarkPointStateOption, StatesOptionMixin<MarkPointStateOption, StatesMixinBase>,
//       SymbolOptionMixin<CallbackDataParams>, MarkerPositionOption { name: string }
//
//   export interface MarkPointOption extends MarkerOption,
//       SymbolOptionMixin<CallbackDataParams>,
//       StatesOptionMixin<MarkPointStateOption, StatesMixinBase>, MarkPointStateOption {
//       mainType?: 'markPoint'
//       precision?: number
//       data?: MarkPointDataItemOption[]
//   }

// upstream: class MarkPointModel extends MarkerModel<MarkPointOption>
//   The generic `Opts` is dropped per CONVENTIONS §2 (dynamic option bag). Not abstract -> `final class`.
public final class MarkPointModel: MarkerModel {

    // static type = 'markPoint';
    // type = MarkPointModel.type;  (instance `type` mirrors the static via the inherited computed prop)
    public override class var type: ComponentFullType { return "markPoint" }

    // createMarkerModelFromSeries(markerOpt, masterMarkerModel, ecModel) {
    //     return new MarkPointModel(markerOpt, masterMarkerModel, ecModel);
    // }
    public override func createMarkerModelFromSeries(
        _ markerOpt: Any?,
        _ masterMarkerModel: MarkerModel,
        _ ecModel: GlobalModel?
    ) -> MarkerModel {
        return MarkPointModel(markerOpt, masterMarkerModel, ecModel)
    }

    // static defaultOption: MarkPointOption = { ... }
    public override class var defaultOption: ModelOption? {
        return [
            // zlevel: 0,
            "z": 5.0,
            "symbol": "pin",
            "symbolSize": 50.0,
            // symbolRotate: 0,
            // symbolOffset: [0, 0]
            "tooltip": [
                "trigger": "item"
            ] as [String: Any],
            "label": [
                "show": true,
                "position": "inside"
            ] as [String: Any],
            "itemStyle": [
                "borderWidth": 2.0
            ] as [String: Any],
            "emphasis": [
                "label": [
                    "show": true
                ] as [String: Any]
            ] as [String: Any]
        ] as [String: Any]
    }
}

// export default MarkPointModel;  -> `public final class MarkPointModel` above.
