// Ported from echarts/src/chart/gauge/GaugeSeries.ts — keep in sync with upstream
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
//   import createSeriesDataSimply from '../helper/createSeriesDataSimply';
//       -> `createSeriesDataSimply` (sibling chart/helper/createSeriesDataSimply.swift). Gauge uses the
//          bare-`coordDimensions`-array overload: `createSeriesDataSimply(this, ['value'])`.
//   import SeriesModel from '../../model/Series';                  -> SeriesModel (model/Series.swift).
//   import { ... } from '../../util/types';                        -> util/types.swift (type-only; the dynamic
//       option tree is the `[String: Any]` bag per CONVENTIONS §2).
//   import GlobalModel from '../../model/Global';                  -> GlobalModel (model/Global.swift).
//   import SeriesData from '../../data/SeriesData';                -> SeriesData (data/SeriesData.swift).
//   import tokens from '../../visual/tokens';
//       -> PORT-TODO: visual/tokens.ts not ported yet; every `tokens.color.*` used in defaultOption is
//          inlined below as its resolved constant (resolved from upstream src/visual/tokens.ts):
//            tokens.color.neutral10      = '#e8ebf0'
//            tokens.color.neutral00      = '#fff'
//            tokens.color.neutral40      = '#9ea0a5'
//            tokens.color.axisTick       = color.neutral70 = '#54555a'
//            tokens.color.axisTickMinor  = color.neutral60 = '#6d6e73'
//            tokens.color.axisLabel      = color.neutral70 = '#54555a'
//            tokens.color.secondary      = color.neutral70 = '#54555a'
//            tokens.color.primary        = color.neutral80 = '#3c3c41'
//            tokens.color.transparent    = 'rgba(0,0,0,0)'
//            tokens.color.theme[0]       = '#5070dd'
//          Re-wire to the `tokens.color.*` symbols once visual/tokens.swift lands.

// upstream registration surface (echarts/src/chart/gauge/install.ts) — INTEGRATION wires this:
//   import { EChartsExtensionInstallRegisters } from '../../extension';
//   import GaugeView from './GaugeView';
//   import GaugeSeriesModel from './GaugeSeries';
//
//   export function install(registers: EChartsExtensionInstallRegisters) {
//       registers.registerChartView(GaugeView);
//       registers.registerSeriesModel(GaugeSeriesModel);
//   }

// ============================================================================
// The upstream `type`/`interface` declarations (GaugeColorStop, LabelFormatter, PointerOption,
// AnchorOption, ProgressOption, TitleOption, DetailOption, GaugeStatesMixin, GaugeStateOption,
// GaugeDataItemOption, GaugeSeriesOption) describe the (dynamic) option tree. Per CONVENTIONS §2 the
// option tree is the `[String: Any]` bag; these types are kept as documentation only — no Swift types
// are emitted.
// ============================================================================

// upstream: class GaugeSeriesModel extends SeriesModel<GaugeSeriesOption>
open class GaugeSeriesModel: SeriesModel {

    // upstream: static type = 'series.gauge' as const;  /  type = GaugeSeriesModel.type;
    //   The static drives the instance `type` (inherited `var type { Self.type }` from ComponentModel).
    public override class var type: ComponentFullType { return "series.gauge" }

    // upstream: visualStyleAccessPath = 'itemStyle';
    //   Identical to the inherited SeriesModel default (`open var visualStyleAccessPath = "itemStyle"`,
    //   model/Series.swift), so no override is emitted (the value would be unchanged).

    // upstream: getInitialData(option, ecModel): SeriesData { return createSeriesDataSimply(this, ['value']); }
    //   Overrides the base `getInitialData(option, ecModel) -> SeriesData?`. Uses the bare-array overload
    //   of `createSeriesDataSimply` (the `isArray(opt) && {coordDimensions: opt}` branch — no
    //   encodeDefaulter). `CoordDimensionDefinitionLoose` is `Any`, so the literal is annotated.
    open override func getInitialData(_ option: ModelOption?, _ ecModel: GlobalModel?) -> SeriesData? {
        // return createSeriesDataSimply(this, ['value']);
        return createSeriesDataSimply(self, ["value"] as [CoordDimensionDefinitionLoose])
    }

    // upstream: static defaultOption: GaugeSeriesOption = { ... }
    //   Gauge is COORDLESS (no coordinate system); center/radius/startAngle/endAngle drive geometry
    //   directly in GaugeView. The full option subtree is kept VERBATIM (it is the diffable option
    //   surface). NOTE (CONVENTIONS trap #1 / task): every numeric default is stored as a bare `Double`
    //   literal here; any READER of these must coerce via a `gaugeNum` helper (Int|Double|NSNumber ->
    //   Double) — the reads live in GaugeView, not this model.
    open override class var defaultOption: ModelOption? {
        return [
            // zlevel: 0,
            "z": 2.0,
            "colorBy": "data",
            // 默认全局居中
            "center": ["50%", "50%"],
            "legendHoverLink": true,
            "radius": "75%",
            "startAngle": 225.0,
            "endAngle": -45.0,
            "clockwise": true,
            // 最小值
            "min": 0.0,
            // 最大值
            "max": 100.0,
            // 分割段数，默认为10
            "splitNumber": 10.0,
            // 坐标轴线
            "axisLine": [
                // 默认显示，属性show控制显示与否
                "show": true,
                "roundCap": false,
                "lineStyle": [       // 属性lineStyle控制线条样式
                    // color: [[1, tokens.color.neutral10]]  (tokens.color.neutral10 = '#e8ebf0')
                    "color": [[1.0, "#e8ebf0"] as [Any]],
                    "width": 10.0
                ] as [String: Any]
            ] as [String: Any],
            // 坐标轴线
            "progress": [
                // 默认显示，属性show控制显示与否
                "show": false,
                "overlap": true,
                "width": 10.0,
                "roundCap": false,
                "clip": true
            ] as [String: Any],
            // 分隔线
            "splitLine": [
                // 默认显示，属性show控制显示与否
                "show": true,
                // 属性length控制线长
                "length": 10.0,
                "distance": 10.0,
                // 属性lineStyle（详见lineStyle）控制线条样式
                "lineStyle": [
                    // color: tokens.color.axisTick  (= color.neutral70 = '#54555a')
                    "color": "#54555a",
                    "width": 3.0,
                    "type": "solid"
                ] as [String: Any]
            ] as [String: Any],
            // 坐标轴小标记
            "axisTick": [
                // 属性show控制显示与否，默认不显示
                "show": true,
                // 每份split细分多少段
                "splitNumber": 5.0,
                // 属性length控制线长
                "length": 6.0,
                "distance": 10.0,
                // 属性lineStyle控制线条样式
                "lineStyle": [
                    // color: tokens.color.axisTickMinor  (= color.neutral60 = '#6d6e73')
                    "color": "#6d6e73",
                    "width": 1.0,
                    "type": "solid"
                ] as [String: Any]
            ] as [String: Any],
            "axisLabel": [
                "show": true,
                "distance": 15.0,
                // formatter: null,
                // color: tokens.color.axisLabel  (= color.neutral70 = '#54555a')
                "color": "#54555a",
                "fontSize": 12.0,
                "rotate": 0.0
            ] as [String: Any],
            "pointer": [
                // PORT-TODO: upstream value is `null`; NSNull() retains the key in the [String: Any] bag.
                "icon": NSNull(),
                "offsetCenter": [0.0, 0.0],
                "show": true,
                "showAbove": true,
                "length": "60%",
                "width": 6.0,
                "keepAspect": false
            ] as [String: Any],
            "anchor": [
                "show": false,
                "showAbove": false,
                "size": 6.0,
                "icon": "circle",
                "offsetCenter": [0.0, 0.0],
                "keepAspect": false,
                "itemStyle": [
                    // color: tokens.color.neutral00  (= '#fff')
                    "color": "#fff",
                    "borderWidth": 0.0,
                    // borderColor: tokens.color.theme[0]  (= '#5070dd')
                    "borderColor": "#5070dd"
                ] as [String: Any]
            ] as [String: Any],

            "title": [
                "show": true,
                // x, y，单位px
                "offsetCenter": [0.0, "20%"] as [Any],
                // 其余属性默认使用全局文本样式，详见TEXTSTYLE
                // color: tokens.color.secondary  (= color.neutral70 = '#54555a')
                "color": "#54555a",
                "fontSize": 16.0,
                "valueAnimation": false
            ] as [String: Any],
            "detail": [
                "show": true,
                // backgroundColor: tokens.color.transparent  (= 'rgba(0,0,0,0)')
                "backgroundColor": "rgba(0,0,0,0)",
                "borderWidth": 0.0,
                // borderColor: tokens.color.neutral40  (= '#9ea0a5')
                "borderColor": "#9ea0a5",
                "width": 100.0,
                // PORT-TODO: upstream value is `null` (self-adaption); NSNull() retains the key.
                "height": NSNull(), // self-adaption
                "padding": [5.0, 10.0],
                // x, y，单位px
                "offsetCenter": [0.0, "40%"] as [Any],
                // formatter: null,
                // 其余属性默认使用全局文本样式，详见TEXTSTYLE
                // color: tokens.color.primary  (= color.neutral80 = '#3c3c41')
                "color": "#3c3c41",
                "fontSize": 30.0,
                "fontWeight": "bold",
                "lineHeight": 30.0,
                "valueAnimation": false
            ] as [String: Any]
        ] as [String: Any]
    }

}

// export default GaugeSeriesModel;  -> `open class GaugeSeriesModel` above.
