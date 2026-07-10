// Ported from echarts/src/chart/funnel/FunnelSeries.ts — keep in sync with upstream
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
//   import * as zrUtil from 'zrender/src/core/util';               -> `zrUtil.*` / `util.*` (ZRenderKit).
//   import createSeriesDataSimply from '../helper/createSeriesDataSimply';
//       -> `createSeriesDataSimply` (sibling chart/helper/createSeriesDataSimply.swift).
//   import {defaultEmphasis} from '../../util/model';              -> `model.defaultEmphasis` (util/modelUtil.swift).
//   import {makeSeriesEncodeForNameBased} from '../../data/helper/sourceHelper';
//       -> `sourceHelper.makeSeriesEncodeForNameBased` (data/helper/sourceHelper.swift).
//   import LegendVisualProvider from '../../visual/LegendVisualProvider';
//       -> PORT-TODO: visual/LegendVisualProvider.ts NOT ported (legend deferred).
//   import SeriesModel from '../../model/Series';                  -> SeriesModel (model/Series.swift).
//   import { ... } from '../../util/types';                        -> util/types.swift (type-only; the dynamic
//       option tree is the `[String: Any]` bag per CONVENTIONS §2).
//   import GlobalModel from '../../model/Global';                  -> GlobalModel (model/Global.swift).
//   import SeriesData from '../../data/SeriesData';                -> SeriesData (data/SeriesData.swift).
//   import tokens from '../../visual/tokens';
//       -> PORT-TODO: visual/tokens.ts not ported yet; `tokens.color.neutral00` / `tokens.color.primary`
//          are inlined as their resolved constants below.

// ============================================================================
// The upstream `type`/`interface` declarations (FunnelLabelOption, FunnelStatesMixin,
// FunnelCallbackDataParams, FunnelStateOption, FunnelDataItemOption, FunnelSeriesOption) describe the
// (dynamic) option tree. Per CONVENTIONS §2 the option tree is the `[String: Any]` bag; these types are
// kept as documentation only — no Swift types are emitted.
// ============================================================================

// export const SERIES_TYPE_FUNNEL = 'funnel';
public let SERIES_TYPE_FUNNEL = "funnel"

// upstream: class FunnelSeriesModel extends SeriesModel<FunnelSeriesOption>
open class FunnelSeriesModel: SeriesModel {

    // upstream: static readonly type = 'series.' + SERIES_TYPE_FUNNEL;  /  readonly type = FunnelSeriesModel.type;
    //   The static drives the instance `type` (inherited `var type { Self.type }` from ComponentModel).
    public override class var type: ComponentFullType { return "series." + SERIES_TYPE_FUNNEL }

    // upstream: init(option: FunnelSeriesOption) { super.init.apply(this, arguments); ... }
    //   The upstream `init` is the model LIFECYCLE method (ported as `func \`init\``), NOT the Swift
    //   constructor. Delegates to `super.init` (builds the data via `getInitialData`) then wires the
    //   legend provider + label-line defaults.
    open override func `init`(
        _ option: ModelOption?, _ parentModel: Model? = nil, _ ecModel: GlobalModel? = nil, _ rest: Any...
    ) {
        // super.init.apply(this, arguments as any);
        super.`init`(option, parentModel, ecModel)

        // Enable legend selection for each DATA ITEM (funnel legend entries are item names). Use functions
        //   (not direct data refs) because the data reference may change; the provider defers access.
        self.legendVisualProvider = LegendVisualProvider(
            { [unowned self] in self.getData() },
            { [unowned self] in self.getRawData() }
        )

        // Extend labelLine emphasis
        // this._defaultLabelLine(option);
        // PORT-TODO: `_defaultLabelLine` mutates `option.labelLine.show`/`option.emphasis.labelLine.show`
        //   from `label.show`/`emphasis.label.show` (via `model.defaultEmphasis`, which IS ported). The
        //   label/labelLine subsystem is deferred (nothing reads `labelLine.show` in the static FunnelView
        //   render), so this is kept as a documented no-op with faithful call shape. Faithful body in
        //   `_defaultLabelLine` below.
    }

    // upstream: getInitialData(this, option, ecModel): SeriesData { return createSeriesDataSimply(...); }
    //   Overrides the base `getInitialData(option, ecModel) -> SeriesData?`.
    open override func getInitialData(_ option: ModelOption?, _ ecModel: GlobalModel?) -> SeriesData? {
        // return createSeriesDataSimply(this, {
        //     coordDimensions: ['value'],
        //     encodeDefaulter: zrUtil.curry(makeSeriesEncodeForNameBased, this)
        // });
        // The `{coordDimensions, encodeDefaulter}` object literal is the `PrepareSeriesDataSchemaParams`
        //   overload of `createSeriesDataSimply` (the `extend({encodeDefine: getEncode()}, opt)` branch).
        //   `zrUtil.curry(makeSeriesEncodeForNameBased, this)` binds the series as the first arg, leaving
        //   `(source, dimCount) -> encode` — exactly the `EncodeDefaulter` shape (see PieSeries.swift).
        return createSeriesDataSimply(self, PrepareSeriesDataSchemaParams(
            coordDimensions: ["value"],
            encodeDefaulter: { (source: Source, dimCount: Double) -> OptionEncode in
                let internalEncode = sourceHelper.makeSeriesEncodeForNameBased(self, source, dimCount)
                return internalEncode.mapValues { $0 as Any } as OptionEncode
            }
        ))
    }

    // upstream: _defaultLabelLine(option: FunnelSeriesOption) { ... }
    // PORT-TODO: deferred with the label/labelLine subsystem (see `init` above). Faithful upstream body:
    //     // Extend labelLine emphasis
    //     defaultEmphasis(option, 'labelLine', ['show']);
    //     const labelLineNormalOpt = option.labelLine;
    //     const labelLineEmphasisOpt = option.emphasis.labelLine;
    //     // Not show label line if `label.normal.show = false`
    //     labelLineNormalOpt.show = labelLineNormalOpt.show && option.label.show;
    //     labelLineEmphasisOpt.show = labelLineEmphasisOpt.show && option.emphasis.label.show;
    //   (`model.defaultEmphasis` IS ported.)

    // Overwrite
    // upstream: getDataParams(dataIndex: number): FunnelCallbackDataParams { ... percent ... }
    // PORT-TODO: `getDataParams` is provided by the `DataFormatMixin` graft, which is NOT yet a
    //   conformance on SeriesModel (see model/Series.swift), so there is no `super.getDataParams` to
    //   extend here. `percent`/`$vars` only feed labels/tooltip, both deferred. Faithful upstream body:
    //     const data = this.getData();
    //     const params = super.getDataParams(dataIndex) as FunnelCallbackDataParams;
    //     const valueDim = data.mapDimension('value');
    //     const sum = data.getSum(valueDim);
    //     // Percent is 0 if sum is 0
    //     params.percent = !sum ? 0 : +(data.get(valueDim, dataIndex) as number / sum * 100).toFixed(2);
    //     params.$vars.push('percent');
    //     return params;

    // upstream: static defaultOption: FunnelSeriesOption = { ... }
    //   LOAD-BEARING: `coordinateSystemUsage: 'box'` is what `createBoxLayoutReference` / `getLayoutRect`
    //   key on to resolve the funnel's view rect (funnel has NO coordinate system). The full
    //   label/labelLine/itemStyle/emphasis/select subtree is kept VERBATIM even though most rendering is
    //   deferred (it is the diffable option surface).
    open override class var defaultOption: ModelOption? {
        return [
            "coordinateSystemUsage": "box",
            // zlevel: 0,                  // 一级层叠
            "z": 2.0,                       // 二级层叠
            "legendHoverLink": true,
            "colorBy": "data",
            "left": 80.0,
            "top": 60.0,
            "right": 80.0,
            "bottom": 65.0,
            // width: {totalWidth} - left - right,
            // height: {totalHeight} - top - bottom,

            // 默认取数据最小最大值
            // min: 0,
            // max: 100,
            "minSize": "0%",
            "maxSize": "100%",
            "sort": "descending", // 'ascending', 'descending'
            "orient": "vertical",
            "gap": 0.0,
            "funnelAlign": "center",
            "label": [
                "show": true,
                "position": "outer"
                // formatter: 标签文本格式器，同Tooltip.formatter，不支持异步回调
            ] as [String: Any],
            "labelLine": [
                "show": true,
                "length": 20.0,
                "lineStyle": [
                    // color: 各异,
                    "width": 1.0
                ] as [String: Any]
            ] as [String: Any],
            "itemStyle": [
                // color: 各异,
                // PORT-TODO: tokens.color.neutral00 inlined as resolved constant ('#fff'); re-wire to
                //   `tokens.color.neutral00` once visual/tokens.swift lands.
                "borderColor": "#fff",   // tokens.color.neutral00
                "borderWidth": 1.0
            ] as [String: Any],
            "emphasis": [
                "label": [
                    "show": true
                ] as [String: Any]
            ] as [String: Any],
            "select": [
                "itemStyle": [
                    // PORT-TODO: tokens.color.primary inlined as resolved constant (color.neutral80);
                    //   re-wire to `tokens.color.primary` once visual/tokens.swift lands.
                    "borderColor": "#3c3c41"   // tokens.color.primary
                ] as [String: Any]
            ] as [String: Any]
        ] as [String: Any]
    }

}

// export default FunnelSeriesModel;  -> `open class FunnelSeriesModel` above.
