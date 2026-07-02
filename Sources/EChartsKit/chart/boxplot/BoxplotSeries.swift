// Ported from echarts/src/chart/boxplot/BoxplotSeries.ts — keep in sync with upstream
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
//   import SeriesModel from '../../model/Series';                        -> SeriesModel (model/Series.swift).
//   import {WhiskerBoxCommonMixin} from '../helper/whiskerBoxCommon';    -> chart/helper/whiskerBoxCommon.ts NOT
//       ported as its own file. Per CONVENTIONS §2 (mixins → replicate via explicit forwarding), the
//       mixin's stored state (`_baseAxisDim`, `_layout`) and methods (`_hasEncodeRule`, `getInitialData`,
//       `getBaseAxis`, `getWhiskerBoxesLayout`) are FOLDED directly into this class below, matching the
//       upstream `mixin(BoxplotSeriesModel, WhiskerBoxCommonMixin, true)`. Candlestick is the only other
//       consumer and is not yet ported; when it lands, hoist the folded members into a shared
//       whiskerBoxCommon.swift. `resolveNormalBoxClipping` (also exported from whiskerBoxCommon.ts) is
//       used only by the View (deferred stage) and is not ported here.
//   import { ... option mixins ... } from '../../util/types';            -> util/types.swift (type-only; the
//       dynamic option tree is the `[String: Any]` bag, CONVENTIONS §2).
//   import type Axis2D from '../../coord/cartesian/Axis2D';              -> Axis2D (coord/cartesian/Axis2D.swift).
//   import Cartesian2D from '../../coord/cartesian/Cartesian2D';         -> Cartesian2D (coord/cartesian/Cartesian2D.swift).
//   import { mixin } from 'zrender/src/core/util';                       -> see folding note above (no runtime mixin).
//   import tokens from '../../visual/tokens';
//       -> PORT-TODO: visual/tokens.ts not ported yet. `tokens.color.neutral00` / `tokens.color.shadow`
//          are inlined verbatim as their resolved constants in `defaultOption` (same convention as
//          ScatterSeries.swift); re-wire to the real `tokens` namespace once visual/tokens.swift lands.
//            tokens.color.neutral00 = '#fff'
//            tokens.color.shadow    = 'rgba(0,0,0,0.2)'

// ============================================================================
// The following upstream `interface` declarations describe the (dynamic) option tree.
// Per CONVENTIONS §2, the option tree is the `[String: Any]` bag; these types are kept as
// documentation only (the diffable surface) — no Swift types are emitted for them.
// ============================================================================
//
// // [min,  Q1,  median (or Q2),  Q3,  max]
// type BoxplotDataValue = OptionDataValueNumeric[];
// export interface BoxplotStateOption<TCbParams = never> {
//     itemStyle?: ItemStyleOption<TCbParams>
//     label?: SeriesLabelOption
// }
// export interface BoxplotDataItemOption
//     extends BoxplotStateOption, StatesOptionMixin<BoxplotStateOption, ExtraStateOption> {
//     value: BoxplotDataValue
// }
// interface ExtraStateOption {
//     emphasis?: { focus?: DefaultEmphasisFocus; scale?: boolean }
// }
// export interface BoxplotSeriesOption
//     extends SeriesOption<...>, BoxplotStateOption<CallbackDataParams>,
//     SeriesOnCartesianOptionMixin, SeriesEncodeOptionMixin {
//     type?: 'boxplot'
//     coordinateSystem?: 'cartesian2d'
//     layout?: LayoutOrient
//     clip?: boolean;
//     boxWidth?: (string | number)[]    // [min, max] can be percent of band width.
//     data?: (BoxplotDataValue | BoxplotDataItemOption)[]
// }

// upstream: export const SERIES_TYPE_BOXPLOT = 'boxplot';
public let SERIES_TYPE_BOXPLOT = "boxplot"

// upstream: class BoxplotSeriesModel extends SeriesModel<BoxplotSeriesOption>
//   The generic `Opts` is dropped per CONVENTIONS §2 (the dynamic option tree is the `[String: Any]`
//   bag). `open class` to match the port's model style (Series/Component are `open`).
open class BoxplotSeriesModel: SeriesModel {

    // upstream: static readonly type = 'series.' + SERIES_TYPE_BOXPLOT;  /  type = BoxplotSeriesModel.type;
    public override class var type: ComponentFullType { return "series." + SERIES_TYPE_BOXPLOT }

    // upstream: static readonly dependencies = ['xAxis', 'yAxis', 'grid'];
    public override class var dependencies: [String] { return ["xAxis", "yAxis", "grid"] }

    // upstream (instance field): coordinateSystem: Cartesian2D;
    //   The base `SeriesModel.coordinateSystem` is `Any?` (the coord layer is dynamically assigned); the
    //   boxplot layout narrows it to `Cartesian2D` at the call site. No override needed.

    // TODO (upstream)
    // box width represents group size, so dimension should have 'size'.

    /**
     * @see <https://en.wikipedia.org/wiki/Box_plot>
     * The meanings of 'min' and 'max' depend on user,
     * and echarts do not need to know it.
     * @readOnly
     */
    // upstream instance field `defaultValueDimensions = [ {name,defaultTooltip}, ... ]`.
    //   Read by the folded `getInitialData` (was on WhiskerBoxCommonMixin). Each element is a
    //   `CoordDimensionDimsDefItem` (the `{ name, defaultTooltip }` inline object).
    open var defaultValueDimensions: [CoordDimensionDimsDefItem] = [
        CoordDimensionDimsDefItem(name: "min", defaultTooltip: true),
        CoordDimensionDimsDefItem(name: "Q1", defaultTooltip: true),
        CoordDimensionDimsDefItem(name: "median", defaultTooltip: true),
        CoordDimensionDimsDefItem(name: "Q3", defaultTooltip: true),
        CoordDimensionDimsDefItem(name: "max", defaultTooltip: true)
    ]

    // upstream: dimensions: string[];  (populated by createSeriesDataSimply → SeriesData.dimensions)

    // upstream instance field: visualDrawType = 'stroke' as const;
    //   The base `SeriesModel.visualDrawType` is a stored `open var` defaulting to 'fill'; a subclass
    //   field can't re-default a stored property, so it is flipped in the `init` override below
    //   (same pattern ScatterSeries.swift uses for `hasSymbolVisual`).
    open override func `init`(_ option: ModelOption?, _ parentModel: Model? = nil, _ ecModel: GlobalModel? = nil, _ rest: Any...) {
        super.`init`(option, parentModel, ecModel)
        self.visualDrawType = "stroke"
    }

    // upstream: static defaultOption: BoxplotSeriesOption = { ... }
    open override class var defaultOption: ModelOption? {
        return [
            // zlevel: 0,
            "z": 2.0,
            "coordinateSystem": "cartesian2d",
            "legendHoverLink": true,

            // layout: null,
            "clip": true,
            "boxWidth": [7.0, 50.0],

            "itemStyle": [
                // PORT-TODO: tokens.color.neutral00 inlined as resolved constant ('#fff');
                //   re-wire to `tokens.color.neutral00` once visual/tokens.swift lands.
                "color": "#fff",   // tokens.color.neutral00
                "borderWidth": 1.0
            ] as [String: Any],

            "emphasis": [
                "scale": true,

                "itemStyle": [
                    "borderWidth": 2.0,
                    "shadowBlur": 5.0,
                    "shadowOffsetX": 1.0,
                    "shadowOffsetY": 1.0,
                    // PORT-TODO: tokens.color.shadow inlined as resolved constant ('rgba(0,0,0,0.2)');
                    //   re-wire to `tokens.color.shadow` once visual/tokens.swift lands.
                    "shadowColor": "rgba(0,0,0,0.2)"   // tokens.color.shadow
                ] as [String: Any]
            ] as [String: Any],

            "animationDuration": 800.0
        ] as [String: Any]
    }

    // ========================================================================
    // Folded from `WhiskerBoxCommonMixin` (chart/helper/whiskerBoxCommon.ts) — see the import note above.
    //   upstream: mixin(BoxplotSeriesModel, WhiskerBoxCommonMixin, true)
    // ========================================================================

    // upstream: private _baseAxisDim: string;
    private var _baseAxisDim: String = ""

    /**
     * Computed layout.
     */
    // upstream: private _layout: CommonOption['layout'];  ('horizontal' | 'vertical')
    private var _layout: String?

    /**
     * @private
     */
    // upstream:
    //   _hasEncodeRule(key) {
    //       const encodeRules = this.getEncode();
    //       return encodeRules && encodeRules.get(key) != null;
    //   }
    func _hasEncodeRule(_ key: String) -> Bool {
        let encodeRules = self.getEncode()
        return encodeRules != nil && encodeRules!.get(key) != nil
    }

    /**
     * @override
     */
    // upstream: getInitialData(option: Opts, ecModel: GlobalModel): SeriesData { ... }
    open override func getInitialData(_ option: ModelOption?, _ ecModel: GlobalModel?) -> SeriesData? {
        // When both types of xAxis and yAxis are 'value', layout is
        // needed to be specified by user. Otherwise, layout can be
        // judged by which axis is category.

        // upstream `ecModel` is non-null in this call path (set during model init); guard defensively.
        let ecModel = ecModel!
        // upstream `option` is the merged series option; the port passes `self.option` (a `[String: Any]`
        //   bag). Read fields through the bag.
        let optionBag = (option as? [String: Any]) ?? [:]

        var ordinalMeta: OrdinalMeta?

        // const xAxisModel = ecModel.getComponent('xAxis', this.get('xAxisIndex')) as CartesianAxisModel;
        // const yAxisModel = ecModel.getComponent('yAxis', this.get('yAxisIndex')) as CartesianAxisModel;
        // PORT-TODO: upstream casts to the generated `CartesianAxisModel` (which implements
        //   `AxisModelExtendedInCreator`). In the port, `xAxis`/`yAxis` are instantiated as
        //   axisModelCreator-generated CartesianAxisModel subclasses (the slim driver's SlimXAxisModel);
        //   cast to CartesianAxisModel here (NOT the standalone `AxisModel`, which the slim models are not),
        //   and reach `getOrdinalMeta()` through the `AxisModelExtendedInCreator` protocol below.
        let xAxisModel = ecModel.getComponent("xAxis", asOptDimIndex(self.get("xAxisIndex"))) as? CartesianAxisModel
        let yAxisModel = ecModel.getComponent("yAxis", asOptDimIndex(self.get("yAxisIndex"))) as? CartesianAxisModel
        let xAxisType = xAxisModel?.get("type") as? String
        let yAxisType = yAxisModel?.get("type") as? String
        var addOrdinal: Bool = false

        // Theoretically, if `encode` and/or `layout` are not specified, they can be derived from
        // the specified one (also according to axis types). However, only the logic for deriving
        // `encode` from `layout` is implemented; the reverse direction is not implemented yet,
        // due to its complexity and low priority.
        var layout = optionBag["layout"] as? String
        // 'category' axis has historically been enforcing `layout` regardless of its presence.
        // This behavior is preserved until it causes problems.
        if xAxisType == "category" {
            layout = "horizontal"
            ordinalMeta = (xAxisModel as? AxisModelExtendedInCreator)?.getOrdinalMeta()
            addOrdinal = !self._hasEncodeRule("x")
        }
        else if yAxisType == "category" {
            layout = "vertical"
            ordinalMeta = (yAxisModel as? AxisModelExtendedInCreator)?.getOrdinalMeta()
            addOrdinal = !self._hasEncodeRule("y")
        }
        if layout == nil {
            layout = yAxisType == "time" ? "vertical" : "horizontal"
            // It is theoretically possible for an axis with type "time" to serve as the "value axis".
            // `layout` can be explicitly specified for that case.
        }
        // Do not assign the computed `layout` to `option.layout`, otherwise the idempotent may be broken.
        self._layout = layout

        let coordDims = ["x", "y"]
        let baseAxisDimIndex = layout == "horizontal" ? 0 : 1
        let baseAxisDim = coordDims[baseAxisDimIndex]
        self._baseAxisDim = baseAxisDim
        let otherAxisDim = coordDims[1 - baseAxisDimIndex]
        let axisModels = [xAxisModel, yAxisModel]
        let baseAxisType = axisModels[baseAxisDimIndex]?.get("type") as? String
        let otherAxisType = axisModels[1 - baseAxisDimIndex]?.get("type") as? String
        let data = optionBag["data"] as? [Any]

        // Clone a new data for next setOption({}) usage.
        // Avoid modifying current data will affect further update.
        // PORT-TODO (value-semantics): upstream keeps two aliases of each data item — it mutates the
        //   SOURCE-referenced originals in place (`item.unshift(index)` / `item.value.unshift(index)`) so
        //   the Source sees the base-category index, while assigning `option.data = newOptionData` (clones
        //   WITHOUT the index) for setOption idempotency. Swift `[Any]`/`[String:Any]` are value types, and
        //   the ported `Source` holds a value copy of `option.data` prepared BEFORE this method runs — so
        //   the in-place mutation can not reach it. To reproduce the observable SOURCE state
        //   (index-prepended data — REQUIRED so the base/category dimension parses the ordinal index rather
        //   than the first value, which otherwise NaNs the trailing `max` dim and yields `hasValue == false`)
        //   we write the INDEX-PREPENDED items back to `self.option["data"]` and re-prepare the
        //   SourceManager below. This mirrors the identical, working CandlestickSeries.swift fix. CAVEAT:
        //   unlike upstream, `self.option["data"]` is left with the index prepended; a subsequent
        //   `mergeOption` that does not replace `data` would double-prepend. Acceptable for first-render
        //   correctness; revisit when the dual-alias trick can be modeled.
        if data != nil && addOrdinal {
            var indexedData: [Any] = []
            util.each(data!) { (item: Any, index: Int) in
                if util.isArray(item) {
                    // item.unshift(index)
                    var arr = (item as? [Any]) ?? []
                    arr.insert(Double(index), at: 0)
                    indexedData.append(arr)
                }
                else if var itemObj = item as? [String: Any], util.isArray(itemObj["value"]) {
                    // item.value.unshift(index)
                    var valueArr = (itemObj["value"] as? [Any]) ?? []
                    valueArr.insert(Double(index), at: 0)
                    itemObj["value"] = valueArr
                    indexedData.append(itemObj)
                }
                else {
                    indexedData.append(item)
                }
            }
            // Write the index-prepended data to the option bag the Source reads from, then re-prepare.
            if var opt = self.option as? [String: Any] {
                opt["data"] = indexedData
                self.option = opt
            }
            let sm = self.getSourceManager()
            sm.dirty()
            sm.prepareSource()
        }

        let defaultValueDimensions = self.defaultValueDimensions
        // const coordDimensions: CoordDimensionDefinition[] = [{ base }, { value dims }];
        var baseDimDef = CoordDimensionDefinition()
        baseDimDef.name = baseAxisDim
        baseDimDef.type = getDimensionTypeByAxis(baseAxisType ?? "")
        baseDimDef.ordinalMeta = ordinalMeta
        var baseOtherDims = DataVisualDimensions()
        baseOtherDims.tooltip = false
        baseOtherDims.itemName = 0
        baseDimDef.otherDims = baseOtherDims
        baseDimDef.dimsDef = ["base"]

        var otherDimDef = CoordDimensionDefinition()
        otherDimDef.name = otherAxisDim
        otherDimDef.type = getDimensionTypeByAxis(otherAxisType ?? "")
        otherDimDef.dimsDef = defaultValueDimensions.map { $0 as Any }   // defaultValueDimensions.slice()

        let coordDimensions: [CoordDimensionDefinitionLoose] = [baseDimDef, otherDimDef]

        // return createSeriesDataSimply(this, {
        //     coordDimensions,
        //     dimensionsCount: defaultValueDimensions.length + 1,
        //     encodeDefaulter: zrUtil.curry(makeSeriesEncodeForAxisCoordSys, coordDimensions, this as any)
        // });
        return createSeriesDataSimply(self, PrepareSeriesDataSchemaParams(
            coordDimensions: coordDimensions,
            dimensionsCount: Double(defaultValueDimensions.count + 1),
            // curry(makeSeriesEncodeForAxisCoordSys, coordDimensions, this): binds coordDimensions and the
            //   series, leaving `(source, dimCount) -> encode` (dimCount ignored). Same widening bridge as
            //   createSeriesData.swift: SeriesEncodeInternal ([String:[DimensionIndex]]) → OptionEncode.
            encodeDefaulter: { (src: Source, _: Double) -> OptionEncode in
                let internalEncode = sourceHelper.makeSeriesEncodeForAxisCoordSys(coordDimensions, self, src)
                return internalEncode.mapValues { $0 as Any } as OptionEncode
            }
        ))
    }

    /**
     * If horizontal, base axis is x, otherwise y.
     * @override
     */
    // upstream:
    //   getBaseAxis(): Axis2D {
    //       const dim = this._baseAxisDim;
    //       return (this.ecModel.getComponent(dim + 'Axis', this.get(dim + 'AxisIndex')) as CartesianAxisModel).axis;
    //   }
    open override func getBaseAxis() -> Any? {
        let dim = self._baseAxisDim
        let axisModel = self.ecModel!.getComponent(dim + "Axis", asOptDimIndex(self.get(dim + "AxisIndex"))) as? CartesianAxisModel
        // upstream returns the concrete `Axis2D`; `AxisBaseModel.axis` is `Any?` (the attached Axis2D).
        return axisModel?.axis
    }

    // upstream: getWhiskerBoxesLayout() { return this._layout; }
    func getWhiskerBoxesLayout() -> String? {
        return self._layout
    }
}

// export default BoxplotSeriesModel;  -> `open class BoxplotSeriesModel` above.

// JS number coercion shim for the dynamic option bag: `this.get('xAxisIndex')` is a `number | undefined`
// used as `getComponent`'s `idx: Double?`. Not an upstream symbol.
private func asOptDimIndex(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    return nil
}
