// Ported from echarts/src/chart/bar/PictorialBarSeries.ts — keep in sync with upstream
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
//   import BaseBarSeriesModel, { BaseBarSeriesOption } from './BaseBarSeries';
//       -> BaseBarSeriesModel (sibling chart/bar/BaseBarSeries.swift).
//   import { ... } from '../../util/types';   -> util/types.swift (type-only; the dynamic option tree
//       is the `[String: Any]` bag, per CONVENTIONS §2 — no Swift struct is emitted for the option interfaces).
//   import type Cartesian2D from '../../coord/cartesian/Cartesian2D';  -> Cartesian2D (type-only).
//   import { inheritDefaultOption } from '../../util/component';       -> `component.inheritDefaultOption`.
//   import tokens from '../../visual/tokens';
//       -> PORT-TODO: visual/tokens.ts not ported. `tokens.color.primary` is inlined as its resolved
//          constant (color.neutral80 = '#3c3c41'), same convention as BarSeries.swift's `select`.
//   import { SERIES_TYPE_PICTORIAL_BAR } from '../../layout/barCommon';  -> `SERIES_TYPE_PICTORIAL_BAR`.

// ============================================================================
// The upstream `interface PictorialBarStateOption` / `PictorialBarSeriesSymbolOption` /
// `PictorialBarDataItemOption` / `PictorialBarSeriesOption` describe the (dynamic) option tree.
// Per CONVENTIONS §2, the option tree is the `[String: Any]` bag; these are documentation only.
// ============================================================================

// upstream: class PictorialBarSeriesModel extends BaseBarSeriesModel<PictorialBarSeriesOption>
//   The generic `Opts` is dropped per CONVENTIONS §2 (the dynamic option tree is the `[String: Any]` bag).
open class PictorialBarSeriesModel: BaseBarSeriesModel {

    // upstream: static type = 'series.' + SERIES_TYPE_PICTORIAL_BAR;  /  type = PictorialBarSeriesModel.type;
    public override class var type: ComponentFullType { return "series." + SERIES_TYPE_PICTORIAL_BAR }

    // upstream: static dependencies = ['grid'];
    public override class var dependencies: [String] { return ["grid"] }

    // upstream: coordinateSystem: Cartesian2D;  — inherited `open var coordinateSystem: Any?` slot.

    // upstream (instance fields): hasSymbolVisual = true;  defaultSymbol = 'roundRect';
    //   The base `SeriesModel` declares these as stored `open var`s (false / 'circle'), which a subclass
    //   field cannot re-default; flip them in the `init` lifecycle override (same pattern as ScatterSeries).
    //   The symbol-visual stage reads them off the constructed model.
    open override func `init`(_ option: ModelOption?, _ parentModel: Model? = nil, _ ecModel: GlobalModel? = nil, _ rest: Any...) {
        super.`init`(option, parentModel, ecModel)
        self.hasSymbolVisual = true
        self.defaultSymbol = "roundRect"
    }

    // upstream:
    //   getInitialData(option) { (option as any).stack = null; return super.getInitialData.apply(this, arguments); }
    // Pictorial bar disables stacking.
    open override func getInitialData(_ option: ModelOption?, _ ecModel: GlobalModel?) -> SeriesData? {
        // `(option as any).stack = null;` — remove any stack so createSeriesData does not stack.
        if var optDict = option as? [String: Any] {
            optDict["stack"] = NSNull()
            return super.getInitialData(optDict, ecModel)
        }
        return super.getInitialData(option, ecModel)
    }

    // upstream: static defaultOption = inheritDefaultOption(BaseBarSeriesModel.defaultOption, {...})
    open override class var defaultOption: ModelOption? {
        return component.inheritDefaultOption(
            (BaseBarSeriesModel.defaultOption as? [String: Any]) ?? [:],
            [
                "symbol": "circle",           // Customized bar shape
                // PORT-TODO: upstream values are `null`; NSNull() retains the key in the [String: Any] bag
                //   so `get(...)` reads back a distinguishable "unset" rather than a missing key.
                "symbolSize": NSNull(),
                "symbolRotate": NSNull(),

                "symbolPosition": NSNull(),   // 'start' or 'end' or 'center', null means auto.
                "symbolOffset": NSNull(),
                "symbolMargin": NSNull(),
                "symbolRepeat": false,
                "symbolRepeatDirection": "end",   // 'end' means from 'start' to 'end'.

                "symbolClip": false,
                "symbolBoundingData": NSNull(),   // Can be 60 or -40 or [-40, 60]
                "symbolPatternSize": 400,         // 400 * 400 px

                "barGap": "-100%",                // In most case, overlap is needed.

                // Pictorial bar do not clip by default because in many cases
                // xAxis and yAxis are not displayed and it's expected not to clip.
                "clip": false,

                // Disable progressive
                "progressive": 0,

                "emphasis": [
                    // By default pictorialBar do not hover scale.
                    "scale": false
                ] as [String: Any],

                "select": [
                    "itemStyle": [
                        // PORT-TODO: tokens.color.primary inlined as resolved constant (color.neutral80);
                        //   re-wire to `tokens.color.primary` once visual/tokens.swift lands.
                        "borderColor": "#3c3c41"   // tokens.color.primary
                    ] as [String: Any]
                ] as [String: Any]
            ] as [String: Any]
        )
    }
}

// export default PictorialBarSeriesModel;  -> `open class PictorialBarSeriesModel` above.

// SeriesModel.registerClass side effect (upstream runs it at install time). The EChartsKit registration
//   entry point (`ECharts.installOnce`) invokes `ComponentModel.registerClass(PictorialBarSeriesModel.self)`
//   directly; the inherited `BaseBarSeriesModel.registerSeriesModelClass()` would register the WRONG
//   (base) class, so it is intentionally NOT reused here.
