// Ported from echarts/src/chart/bar/BarSeries.ts — keep in sync with upstream
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
//   import BaseBarSeriesModel, {BaseBarSeriesOption} from './BaseBarSeries';
//       -> BaseBarSeriesModel (sibling chart/bar/BaseBarSeries.swift, ported by another agent).
//   import { ItemStyleOption, OptionDataValue, SeriesStackOptionMixin, StatesOptionMixin,
//            OptionDataItemObject, SeriesSamplingOptionMixin, SeriesLabelOption,
//            SeriesEncodeOptionMixin, DefaultStatesMixinEmphasis, CallbackDataParams }
//       from '../../util/types';                                    -> util/types.swift (same module; type-only,
//                                                                       the dynamic option tree is `[String: Any]`).
//   import type Cartesian2D from '../../coord/cartesian/Cartesian2D';  -> Cartesian2D (coord/cartesian/Cartesian2D.swift; type-only).
//   import createSeriesData from '../helper/createSeriesData';      -> `createSeriesData` (sibling chart/helper/createSeriesData.swift).
//   import type Polar from '../../coord/polar/Polar';               -> Polar (coord/polar/Polar.swift); BarView rendering is cartesian-only.
//   import { inheritDefaultOption } from '../../util/component';     -> `component.inheritDefaultOption` (util/componentUtil.swift).
//   import SeriesData from '../../data/SeriesData';                 -> SeriesData (data/SeriesData.swift).
//   import { BrushCommonSelectorsForSeries } from '../../component/brush/selector';
//       -> PORT-TODO: component/brush not ported (brushSelector deferred below).
//   import tokens from '../../visual/tokens';
//       -> PORT-NOTE: visual/tokens.swift is ported (`tokens.color.primary`), but the value is still
//          inlined verbatim as its resolved constant in `defaultOption` (same convention as
//          coord/cartesian/GridModel.swift); re-wiring to the real `tokens` namespace is still pending.
//            tokens.color.primary = color.neutral80 = '#3c3c41'
//   import { preparePipelineContext } from '../../util/model';      -> `model.preparePipelineContext` (util/modelUtil.swift).
//   import type { Pipeline } from '../../core/Scheduler';           -> `Pipeline` / `PipelinePick` (core/Scheduler.swift; util/modelUtil.swift).
//   import type ChartView from '../../view/Chart';                  -> ChartView (view/Chart.swift).
//   import { SERIES_TYPE_BAR } from '../../layout/barCommon';       -> `SERIES_TYPE_BAR` (layout/barCommon.swift).

// ============================================================================
// The following upstream `type`/`interface` declarations describe the (dynamic) option tree.
// Per CONVENTIONS §2, the option tree is the `[String: Any]` bag; these types are kept as
// documentation only (the diffable surface) — no Swift types are emitted for them.
// ============================================================================
//
// type PolarBarLabelPositionExtra = 'start' | 'insideStart' | 'middle' | 'end' | 'insideEnd';
// export type PolarBarLabelPosition = SeriesLabelOption['position'] | PolarBarLabelPositionExtra;
//
// export type BarSeriesLabelOption = SeriesLabelOption<
//     CallbackDataParams,
//     {positionExtra: PolarBarLabelPositionExtra | 'outside'}
// >;
//
// export interface BarStateOption<TCbParams = never> {
//     itemStyle?: BarItemStyleOption<TCbParams>
//     label?: BarSeriesLabelOption
// }
//
// interface BarStatesMixin {
//     emphasis?: DefaultStatesMixinEmphasis
// }
//
// export interface BarItemStyleOption<TCbParams = never> extends ItemStyleOption<TCbParams> {
//     // for polar bars, this is used for sector's cornerRadius
//     borderRadius?: (number | string)[] | number | string
// }
// export interface BarDataItemOption extends BarStateOption,
//     StatesOptionMixin<BarStateOption, BarStatesMixin>,
//     OptionDataItemObject<OptionDataValue> {
//     cursor?: string
// }
//
// export interface BarSeriesOption
//     extends BaseBarSeriesOption<BarStateOption<CallbackDataParams>, BarStatesMixin>,
//     BarStateOption<CallbackDataParams>,
//     SeriesStackOptionMixin, SeriesSamplingOptionMixin, SeriesEncodeOptionMixin {
//
//     type?: 'bar'
//     coordinateSystem?: 'cartesian2d' | 'polar'
//     clip?: boolean
//     // If use caps on two sides of bars. Only available on tangential polar bar
//     roundCap?: boolean
//     showBackground?: boolean
//     backgroundStyle?: ItemStyleOption & { borderRadius?: number | number[] }
//     data?: (BarDataItemOption | OptionDataValue | OptionDataValue[])[]
//     realtimeSort?: boolean
// }

// upstream: class BarSeriesModel extends BaseBarSeriesModel<BarSeriesOption>
//   The generic `Opts` is dropped per CONVENTIONS §2 (the dynamic option tree is the `[String: Any]`
//   bag). `open class` to match the port's model style (Series/Component are `open`).
open class BarSeriesModel: BaseBarSeriesModel {

    // upstream: static type = 'series.' + SERIES_TYPE_BAR;  /  type = BarSeriesModel.type;
    //   The static drives the instance `type` (inherited `var type { Self.type }` from ComponentModel).
    public override class var type: ComponentFullType { return "series." + SERIES_TYPE_BAR }

    // upstream: static dependencies = ['grid', 'polar'];
    public override class var dependencies: [String] { return ["grid", "polar"] }

    // upstream: coordinateSystem: Cartesian2D | Polar;
    //   The inherited `open var coordinateSystem: Any?` (SeriesModel) already provides this slot;
    //   Swift can not re-type an inherited stored property, so the narrowed union stays a comment.

    // upstream signature: getInitialData(): SeriesData
    //   Overrides the base `getInitialData(option, ecModel) -> SeriesData?` (upstream ignores both
    //   params here). createSeriesData returns a non-optional SeriesData; wrapped as SeriesData?.
    open override func getInitialData(_ option: ModelOption?, _ ecModel: GlobalModel?) -> SeriesData? {
        // return createSeriesData(null, this, {
        //     useEncodeDefaulter: true,
        //     createInvertedIndices: !!this.get('realtimeSort', true) || null
        // });
        // `!!this.get('realtimeSort', true) || null` -> `true` when realtimeSort is truthy, else `nil`
        //   (JS `false || null === null`). realtimeSort defaults to a Bool in defaultOption.
        // PORT-TODO: `!!` truthiness modeled via a Bool cast; non-Bool realtimeSort values ignored.
        let createInvertedIndices: Bool? = ((self.get("realtimeSort", true) as? Bool) ?? false) ? true : nil
        return createSeriesData(nil, self, CreateSeriesDataOpt(
            useEncodeDefaulter: true,
            createInvertedIndices: createInvertedIndices
        ))
    }

    /**
     * @override
     */
    open override func getProgressive() -> Any? {
        // Do not support progressive in normal mode.
        // return this.get('large') ? this.get('progressive') : false;
        return ((self.get("large") as? Bool) ?? false)
            ? self.get("progressive")
            : false
    }

    /**
     * @implement
     */
    // upstream: __preparePipelineContext(view: ChartView, pipeline: Pick<Pipeline, 'progressiveEnabled' | 'threshold'>)
    //   `Pick<Pipeline, ...>` -> `PipelinePick` (core/Scheduler.swift / util/modelUtil.swift).
    // NOTE: this is a declaration-merged optional method on the upstream `SeriesModel` interface; the
    //   base Swift `SeriesModel` does not declare it, so it is introduced fresh here. The Scheduler
    //   currently always calls `model.preparePipelineContext` directly (see core/Scheduler.swift
    //   PORT-TODO), so this override is not yet reached by the pipeline; kept faithful for when it is.
    open func __preparePipelineContext(_ view: ChartView, _ pipeline: PipelinePick) -> PipelineContext {
        var context = model.preparePipelineContext(self, view, pipeline)
        // Do not support progressive in normal mode.
        if context.progressiveRender {
            context.large = true
        }
        return context
    }

    // upstream:
    //   brushSelector(dataIndex: number, data: SeriesData, selectors: BrushCommonSelectorsForSeries): boolean {
    //       return selectors.rect(data.getItemLayout(dataIndex));
    //   }
    // PORT-TODO: component/brush/selector.ts (BrushCommonSelectorsForSeries) not ported — brush is out
    //   of scope for the bar-chart milestone. Restore this override when the brush component lands.

    // upstream: static defaultOption: BarSeriesOption = inheritDefaultOption(BaseBarSeriesModel.defaultOption, {...})
    open override class var defaultOption: ModelOption? {
        return component.inheritDefaultOption(
            (BaseBarSeriesModel.defaultOption as? [String: Any]) ?? [:],
            [
                // If clipped
                // Only available on cartesian2d
                "clip": true,

                "roundCap": false,

                "showBackground": false,
                "backgroundStyle": [
                    "color": "rgba(180, 180, 180, 0.2)",
                    // PORT-NOTE: upstream value is `null`; NSNull() retains the key in the [String: Any] bag.
                    "borderColor": NSNull(),
                    "borderWidth": 0,
                    "borderType": "solid",
                    "borderRadius": 0,
                    "shadowBlur": 0,
                    // PORT-NOTE: upstream value is `null`; NSNull() retains the key.
                    "shadowColor": NSNull(),
                    "shadowOffsetX": 0,
                    "shadowOffsetY": 0,
                    "opacity": 1
                ] as [String: Any],

                "select": [
                    "itemStyle": [
                        // PORT-NOTE: tokens.color.primary inlined as resolved constant (color.neutral80);
                        //   visual/tokens.swift is ported — re-wire to `tokens.color.primary` still pending.
                        "borderColor": "#3c3c41",   // tokens.color.primary
                        "borderWidth": 2
                    ] as [String: Any]
                ] as [String: Any],

                "realtimeSort": false
            ] as [String: Any]
        )
    }

}

// export default BarSeriesModel;  -> `open class BarSeriesModel` above.
