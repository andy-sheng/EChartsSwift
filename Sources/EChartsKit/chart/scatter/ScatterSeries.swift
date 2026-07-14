// Ported from echarts/src/chart/scatter/ScatterSeries.ts — keep in sync with upstream
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
//       -> BrushCommonSelectorsForSeries (component/brush/brushVisual.swift). The scatter `brushSelector`
//          override is still deferred (see below).
//   import tokens from '../../visual/tokens';
//       -> PORT-NOTE: tokens (visual/tokens.swift) is ported. `tokens.color.primary` is inlined verbatim as its
//          resolved constant in `defaultOption` (same convention as BarSeries.swift);
//          a live `tokens` read could replace the inlined constant.
//            tokens.color.primary = color.neutral80 = '#3c3c41'

// ============================================================================
// The following upstream `interface` declarations describe the (dynamic) option tree.
// Per CONVENTIONS §2, the option tree is the `[String: Any]` bag; these types are kept as
// documentation only (the diffable surface) — no Swift types are emitted for them.
// ============================================================================
//
// interface ScatterStateOption<TCbParams = never> {
//     itemStyle?: ItemStyleOption<TCbParams>
//     label?: SeriesLabelOption
// }
// interface ScatterStatesOptionMixin {
//     emphasis?: { focus?: DefaultEmphasisFocus; scale?: boolean | number }
// }
// export interface ScatterDataItemOption extends SymbolOptionMixin, ScatterStateOption,
//     StatesOptionMixin<ScatterStateOption, ScatterStatesOptionMixin>,
//     OptionDataItemObject<OptionDataValue> {}
// export interface ScatterSeriesOption
//     extends SeriesOption<...>, ScatterStateOption<CallbackDataParams>,
//     SeriesOnCartesianOptionMixin, SeriesOnPolarOptionMixin,
//     ComponentOnCalendarOptionMixin, ComponentOnMatrixOptionMixin,
//     SeriesOnGeoOptionMixin, SeriesOnSingleOptionMixin,
//     SeriesLargeOptionMixin, SeriesStackOptionMixin,
//     SymbolOptionMixin<CallbackDataParams>, SeriesEncodeOptionMixin {
//     type?: 'scatter'
//     coordinateSystem?: string
//     cursor?: string
//     clip?: boolean
//     data?: (ScatterDataItemOption | OptionDataValue | OptionDataValue[])[] | ArrayLike<number>
// }

// upstream: class ScatterSeriesModel extends SeriesModel<ScatterSeriesOption>
//   The generic `Opts` is dropped per CONVENTIONS §2 (the dynamic option tree is the `[String: Any]`
//   bag). `open class` to match the port's model style (Series/Component are `open`).
open class ScatterSeriesModel: SeriesModel {

    // upstream: static readonly type = 'series.scatter';  /  type = ScatterSeriesModel.type;
    //   The static drives the instance `type` (inherited `var type { Self.type }` from ComponentModel).
    public override class var type: ComponentFullType { return "series.scatter" }

    // upstream: static readonly dependencies = ['grid', 'polar', 'geo', 'singleAxis', 'calendar', 'matrix'];
    //   PORT-NOTE: cartesian2d / polar / geo scatter are renderable now (see ScatterView); singleAxis /
    //   calendar / matrix scatter are still deferred though their coord systems are ported. The dependency
    //   list is kept verbatim so registration/topo order matches.
    public override class var dependencies: [String] {
        return ["grid", "polar", "geo", "singleAxis", "calendar", "matrix"]
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

    // Scatter's legend swatch is its data symbol (a circle by default), not the default filled rect.
    //   Build a single symbol tinted with the series color; hollow variants ('emptyCircle') stroke +
    //   white-fill like the chart symbols.
    open override func getLegendIcon(_ opt: LegendIconParams) -> Element? {
        // Prefer the legend-computed `opt.itemStyle.fill` (upstream getLegendIcon uses it): the resolved
        //   series color when the item is SELECTED, and the grey `inactiveColor` when UNSELECTED. This is
        //   stable even for a legend-filtered (toggled-off) series, whose data visual is gone — reading
        //   getData().getVisual there returned nil, so the icon lost its fill and VANISHED instead of
        //   greying out. Fall back to the series data visual only when itemStyle has no usable fill.
        let colorZR: ZRenderKit.ZRColor? = {
            if let f = opt.itemStyle["fill"] {
                if let z = f as? EChartsKit.ZRColor, case let .color(c) = z { return .string(c) }
                if let s = f as? String, !s.isEmpty, s != "inherit", s != "auto", s != "none" { return .string(s) }
            }
            guard let s = self.getData().getVisual("style") as? [String: Any] else { return nil }
            for key in ["fill", "stroke"] {
                if let z = s[key] as? EChartsKit.ZRColor, case let .color(c) = z { return .string(c) }
                if let str = s[key] as? String, !str.isEmpty, str != "inherit", str != "auto" { return .string(str) }
            }
            return nil
        }()

        let visualType = (self.getData().getVisual("symbol") as? String) ?? (self.get("symbol", false) as? String)
        let symbolType = (visualType == nil || visualType == "none") ? "circle" : visualType!
        let size = opt.itemHeight
        guard let sym = symbol.createSymbol(
            symbolType, (opt.itemWidth - size) / 2, 0, size, size, colorZR
        ) as? Path else { return nil }
        if symbolType.contains("empty") {
            sym.pathStyle.stroke = colorZR
            sym.pathStyle.fill = .string("#fff")
            sym.pathStyle.lineWidth = 2
        } else {
            sym.pathStyle.fill = colorZR
        }
        let group = Group()
        _ = group.add(sym)
        return group
    }

    // upstream: getInitialData(option, ecModel): SeriesData {
    //     return createSeriesData(null, this, { useEncodeDefaulter: true });
    // }
    //   Identical to LineSeries — reuses the ported createSeriesData + real SourceManager (Phase 6c).
    open override func getInitialData(_ option: ModelOption?, _ ecModel: GlobalModel?) -> SeriesData? {
        return createSeriesData(nil, self, CreateSeriesDataOpt(useEncodeDefaulter: true))
    }

    // upstream:
    //   getProgressive() {
    //       const progressive = this.option.progressive;
    //       if (progressive == null) { return this.option.large ? 5e3 : this.get('progressive'); }
    //       return progressive;
    //   }
    //   getProgressiveThreshold() {
    //       const progressiveThreshold = this.option.progressiveThreshold;
    //       if (progressiveThreshold == null) { return this.option.large ? 1e4 : this.get('progressiveThreshold'); }
    //       return progressiveThreshold;
    //   }
    //   getZLevelKey() {
    //       return this.getData().count() > this.getProgressiveThreshold() ? this.id : '';
    //   }
    // getProgressive()
    open override func getProgressive() -> Any? {
        // const progressive = this.option.progressive;
        let progressive = (self.option as? [String: Any])?["progressive"]
        // if (progressive == null) { return this.option.large ? 5e3 : this.get('progressive'); }
        if progressive == nil || progressive is NSNull {
            return scatterTruthy((self.option as? [String: Any])?["large"]) ? (5e3 as Any) : self.get("progressive")
        }
        // return progressive;
        return progressive
    }

    // getProgressiveThreshold()
    open override func getProgressiveThreshold() -> Double {
        // const progressiveThreshold = this.option.progressiveThreshold;
        let progressiveThreshold = (self.option as? [String: Any])?["progressiveThreshold"]
        // if (progressiveThreshold == null) { return this.option.large ? 1e4 : this.get('progressiveThreshold'); }
        if progressiveThreshold == nil || progressiveThreshold is NSNull {
            return scatterTruthy((self.option as? [String: Any])?["large"])
                ? 1e4 : scatterNum(self.get("progressiveThreshold"))
        }
        // return progressiveThreshold;
        return scatterNum(progressiveThreshold)
    }

    // getZLevelKey()
    open override func getZLevelKey() -> String {
        // return this.getData().count() > this.getProgressiveThreshold() ? this.id : '';
        return Double(self.getData().count()) > self.getProgressiveThreshold() ? self.id : ""
    }

    // upstream:
    //   brushSelector(dataIndex, data, selectors): boolean {
    //       return selectors.point(data.getItemLayout(dataIndex));
    //   }
    //   (`brushSelector` is an OPTIONAL declaration-merged member of SeriesModel, modeled as an optional
    //    function-valued property — see the PORT-NOTE on `SeriesModel.brushSelector`.)
    open override var brushSelector: BrushSelectorFn? {
        return { dataIndex, data, selectors, _ in
            return selectors.point(brushItemLayoutAsPoint(data.getItemLayout(dataIndex)))
        }
    }

    // upstream: static defaultOption: ScatterSeriesOption = { ... }
    open override class var defaultOption: ModelOption? {
        return [
            "coordinateSystem": "cartesian2d",
            // zlevel: 0,
            "z": 2.0,
            "legendHoverLink": true,

            "symbolSize": 10.0,
            // symbolRotate: null,

            "large": false,
            // Available when large is true
            "largeThreshold": 2000,
            // cursor: null,

            "itemStyle": [
                "opacity": 0.8
            ] as [String: Any],

            "emphasis": [
                "scale": true
            ] as [String: Any],

            "clip": true,

            "select": [
                "itemStyle": [
                    // PORT-NOTE: tokens.color.primary inlined as its resolved constant (color.neutral80);
                    //   visual/tokens.swift is ported (Tokens.color.primary) if a live read is wanted.
                    "borderColor": "#3c3c41"   // tokens.color.primary
                ] as [String: Any]
            ] as [String: Any],

            "universalTransition": [
                "divideShape": "clone"
            ] as [String: Any]
            // progressive: null
        ] as [String: Any]
    }
}

// export default ScatterSeriesModel;  -> `open class ScatterSeriesModel` above.

// MARK: - Port helpers (not upstream symbols)

// Coerce a dynamic option value to Double (NaN when non-numeric), mirroring `as number`.
private func scatterNum(_ v: Any?) -> Double {
    switch v {
    case let d as Double: return d
    case let i as Int: return Double(i)
    case let n as NSNumber: return n.doubleValue
    case let s as String: return Double(s) ?? Double.nan
    default: return Double.nan
    }
}

// JS truthiness of `this.option.large` (nil/false/0/"" -> false).
private func scatterTruthy(_ v: Any?) -> Bool {
    switch v {
    case nil: return false
    case is NSNull: return false
    case let b as Bool: return b
    case let i as Int: return i != 0
    case let d as Double: return d != 0
    case let n as NSNumber: return n.doubleValue != 0
    case let s as String: return !s.isEmpty
    default: return true
    }
}
