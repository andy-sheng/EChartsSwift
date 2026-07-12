// Ported from echarts/src/chart/effectScatter/EffectScatterSeries.ts — keep in sync with upstream
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
//   import createSeriesData from '../helper/createSeriesData';   -> `createSeriesData` (sibling chart/helper/createSeriesData.swift).
//   import SeriesModel from '../../model/Series';                 -> SeriesModel (model/Series.swift).
//   import { ... option mixins ... } from '../../util/types';     -> util/types.swift (type-only; the dynamic
//                                                                    option tree is `[String: Any]`, CONVENTIONS §2).
//   import GlobalModel from '../../model/Global';                 -> GlobalModel (model/Global.swift).
//   import SeriesData from '../../data/SeriesData';               -> SeriesData (data/SeriesData.swift).
//   import { BrushCommonSelectorsForSeries } from '../../component/brush/selector';
//       -> PORT-NOTE: BrushCommonSelectorsForSeries IS ported (component/brush/brushVisual.swift); only the
//          `brushSelector` override on this model is intentionally not restored yet (brush out of scope for
//          this milestone — see the deferred override below).
//   import { SymbolDrawItemModelOption } from '../helper/baseDraw';
//       -> type-only (describes the `rippleEffect` option sub-tree); the dynamic option tree is `[String: Any]`.

// ============================================================================
// The following upstream `interface` declarations describe the (dynamic) option tree.
// Per CONVENTIONS §2, the option tree is the `[String: Any]` bag; these types are kept as
// documentation only (the diffable surface) — no Swift types are emitted for them.
// ============================================================================
//
// interface EffectScatterStatesOptionMixin {
//     emphasis?: { focus?: DefaultEmphasisFocus; scale?: boolean | number }
// }
// export interface EffectScatterStateOption<TCbParams = never> {
//     itemStyle?: ItemStyleOption<TCbParams>
//     label?: SeriesLabelOption
// }
// export interface EffectScatterDataItemOption extends SymbolOptionMixin, EffectScatterStateOption,
//     StatesOptionMixin<EffectScatterStateOption, EffectScatterStatesOptionMixin> {
//     name?: string
//     value?: ScatterDataValue
//     rippleEffect?: SymbolDrawItemModelOption['rippleEffect']
// }
// export interface EffectScatterSeriesOption
//     extends SeriesOption<...>, EffectScatterStateOption<CallbackDataParams>,
//     SeriesOnCartesianOptionMixin, SeriesOnPolarOptionMixin,
//     ComponentOnCalendarOptionMixin, ComponentOnMatrixOptionMixin,
//     SeriesOnGeoOptionMixin, SeriesOnSingleOptionMixin, SymbolOptionMixin<CallbackDataParams>,
//     SeriesEncodeOptionMixin {
//     type?: 'effectScatter'
//     coordinateSystem?: string
//     effectType?: 'ripple'
//     showEffectOn?: 'render' | 'emphasis'
//     clip?: boolean
//     rippleEffect?: SymbolDrawItemModelOption['rippleEffect']
//     data?: (EffectScatterDataItemOption | ScatterDataValue)[]
// }

// upstream: class EffectScatterSeriesModel extends SeriesModel<EffectScatterSeriesOption>
//   The generic `Opts` is dropped per CONVENTIONS §2 (the dynamic option tree is the `[String: Any]`
//   bag). `open class` to match the port's model style (Series/Component are `open`).
open class EffectScatterSeriesModel: SeriesModel {

    // upstream: static readonly type = 'series.effectScatter';  /  type = EffectScatterSeriesModel.type;
    //   The static drives the instance `type` (inherited `var type { Self.type }` from ComponentModel).
    public override class var type: ComponentFullType { return "series.effectScatter" }

    // upstream: static readonly dependencies = ['grid', 'polar'];
    //   PORT-NOTE: only grid/cartesian2d is renderable now (polar coord system is wired via the ported
    //   Polar, but the effectScatter static render below only guards cartesian2d + polar); the dependency
    //   list is kept verbatim so registration/topo order matches.
    public override class var dependencies: [String] {
        return ["grid", "polar"]
    }

    // upstream (instance field): hasSymbolVisual = true;
    //   LOAD-BEARING: the symbol visual stage (visual/symbol.ts) reads `seriesModel.hasSymbolVisual` to
    //   decide whether to populate the 'symbol'/'symbolSize' item visuals. The base `SeriesModel` declares
    //   `open var hasSymbolVisual = false` (a stored property, can't be re-defaulted by a subclass field),
    //   so it is flipped to `true` in the `init` override below — faithful to the upstream instance field.
    open override func `init`(_ option: ModelOption?, _ parentModel: Model? = nil, _ ecModel: GlobalModel? = nil, _ rest: Any...) {
        super.`init`(option, parentModel, ecModel)
        self.hasSymbolVisual = true
    }

    // upstream: getInitialData(option, ecModel): SeriesData {
    //     return createSeriesData(null, this, { useEncodeDefaulter: true });
    // }
    //   Identical to Scatter/Line — reuses the ported createSeriesData + real SourceManager (Phase 6c).
    open override func getInitialData(_ option: ModelOption?, _ ecModel: GlobalModel?) -> SeriesData? {
        return createSeriesData(nil, self, CreateSeriesDataOpt(useEncodeDefaulter: true))
    }

    // upstream:
    //   brushSelector(dataIndex, data, selectors): boolean {
    //       return selectors.point(data.getItemLayout(dataIndex));
    //   }
    // PORT-NOTE: BrushCommonSelectorsForSeries is ported (component/brush/brushVisual.swift); this
    //   brushSelector override is simply not restored here yet (brush out of scope for this milestone).

    // upstream: static defaultOption: EffectScatterSeriesOption = { ... }
    open override class var defaultOption: ModelOption? {
        return [
            "coordinateSystem": "cartesian2d",
            // zlevel: 0,
            "z": 2.0,
            "legendHoverLink": true,

            "effectType": "ripple",

            "progressive": 0.0,

            // When to show the effect, option: 'render'|'emphasis'
            "showEffectOn": "render",
            "clip": true,

            // Ripple effect config
            // PORT-NOTE: rippleEffect is the ANIMATED expanding-ring config consumed by helper/EffectSymbol
            //   (period/scale/brushType/number) — EffectSymbolElement.swift has landed and EffectScatterView
            //   routes through SymbolDraw(EffectSymbol), which renders these rings.
            "rippleEffect": [
                "period": 4.0,
                // Scale of ripple
                "scale": 2.5,
                // Brush type can be fill or stroke
                "brushType": "fill",
                // Ripple number
                "number": 3.0
            ] as [String: Any],

            "universalTransition": [
                "divideShape": "clone"
            ] as [String: Any],
            // Cartesian coordinate system
            // xAxisIndex: 0,
            // yAxisIndex: 0,

            // Polar coordinate system
            // polarIndex: 0,

            // Geo coordinate system
            // geoIndex: 0,

            // symbol: null,        // 图形类型
            "symbolSize": 10.0      // 图形大小，半宽（半径）参数，当图形为方向或菱形则总宽度为symbolSize * 2
            // symbolRotate: null,  // 图形旋转控制

            // itemStyle: {
            //     opacity: 1
            // }
        ] as [String: Any]
    }
}

// export default EffectScatterSeriesModel;  -> `open class EffectScatterSeriesModel` above.
