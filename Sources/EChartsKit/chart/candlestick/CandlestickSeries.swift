// Ported from echarts/src/chart/candlestick/CandlestickSeries.ts — keep in sync with upstream
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
//   import SeriesModel from '../../model/Series';                    -> SeriesModel (model/Series.swift).
//   import {WhiskerBoxCommonMixin} from '../helper/whiskerBoxCommon';
//     -> chart/helper/whiskerBoxCommon.ts is NOT ported as a standalone file. Upstream applies it with
//        `mixin(CandlestickSeriesModel, WhiskerBoxCommonMixin, true)`; per CONVENTIONS §2 a `mixin(...)`
//        has no Swift equivalent, so its members (`_hasEncodeRule`, `getInitialData`, `getBaseAxis`,
//        `getWhiskerBoxesLayout`, the `_baseAxisDim`/`_layout` fields) are INLINED into this class below,
//        tagged `// from whiskerBoxCommon.ts`. When boxplot (the mixin's other client) is ported, extract
//        it into a shared chart/helper/whiskerBoxCommon.swift. `resolveNormalBoxClipping` (also in that
//        file, consumed by the View) is deferred with the View stage.
//   import { OptionDataValue, ... } from '../../util/types';         -> util/types.swift (type-only surface).
//   import SeriesData from '../../data/SeriesData';                  -> SeriesData (data/SeriesData.swift).
//   import Cartesian2D from '../../coord/cartesian/Cartesian2D';     -> Cartesian2D (coord/cartesian/Cartesian2D.swift).
//   import { BrushCommonSelectorsForSeries } from '../../component/brush/selector';
//     -> PORT-NOTE (deferred): `BrushCommonSelectorsForSeries` IS ported (brushVisual.swift), but the
//        central brush dispatch (`brushSelectorSupported`) does not yet enable candlestick, so the
//        per-series `brushSelector` below stays deferred (see below).
//   import { mixin } from 'zrender/src/core/util';                   -> see the mixin note above.
//   import type Axis2D from '../../coord/cartesian/Axis2D';          -> Axis2D (coord/cartesian/Axis2D.swift).
//   import CartesianAxisModel from '../../coord/cartesian/AxisModel';  (via whiskerBoxCommon) -> CartesianAxisModel.
//   import createSeriesDataSimply from '../helper/createSeriesDataSimply';  (via whiskerBoxCommon).
//   import {getDimensionTypeByAxis} from '../../data/helper/dimensionHelper';  (via whiskerBoxCommon).
//   import {makeSeriesEncodeForAxisCoordSys} from '../../data/helper/sourceHelper';  (via whiskerBoxCommon).

// upstream: type CandlestickDataValue = OptionDataValue[];
// upstream interfaces `CandlestickItemStyleOption` / `CandlestickStateOption` /
//   `CandlestickDataItemOption` / `ExtraStateOption` / `CandlestickSeriesOption` describe the dynamic
//   option shape; per CONVENTIONS §2 the option tree is the dynamic `[String: Any]` bag (accessed via
//   `Model.get`), so no standalone Swift structs are emitted (mirrors BaseBarSeries.swift). The key
//   fields (itemStyle.color/color0/borderColor/borderColor0/borderColorDoji, layout, clip, barWidth,
//   large, ...) are read by name in candlestickLayout/candlestickVisual.

// upstream: export const SERIES_TYPE_CANDLESTICK = 'candlestick';
public let SERIES_TYPE_CANDLESTICK = "candlestick"

// upstream: class CandlestickSeriesModel extends SeriesModel<CandlestickSeriesOption>
//   (+ mixin WhiskerBoxCommonMixin — inlined, see header note).
open class CandlestickSeriesModel: SeriesModel {

    // upstream: static readonly type = 'series.' + SERIES_TYPE_CANDLESTICK; readonly type = ...
    open override class var type: ComponentFullType { return "series." + SERIES_TYPE_CANDLESTICK }

    // upstream: static readonly dependencies = ['xAxis', 'yAxis', 'grid'];
    open override class var dependencies: [String] { return ["xAxis", "yAxis", "grid"] }

    // upstream: coordinateSystem: Cartesian2D;   (narrows the inherited `Any?`; downcast at use sites).

    // upstream: dimensions: string[];   (assigned by SeriesData; not stored here.)

    // upstream:
    //   defaultValueDimensions = [
    //       {name: 'open', defaultTooltip: true}, {name: 'close', defaultTooltip: true},
    //       {name: 'lowest', defaultTooltip: true}, {name: 'highest', defaultTooltip: true}
    //   ];
    // (This is the `WhiskerBoxCommonMixin.defaultValueDimensions` slot; supplied by the concrete series.)
    open var defaultValueDimensions: [CoordDimensionDimsDefItem] = [
        CoordDimensionDimsDefItem(name: "open", defaultTooltip: true),
        CoordDimensionDimsDefItem(name: "close", defaultTooltip: true),
        CoordDimensionDimsDefItem(name: "lowest", defaultTooltip: true),
        CoordDimensionDimsDefItem(name: "highest", defaultTooltip: true)
    ]

    // upstream: static defaultOption: CandlestickSeriesOption = { ... }
    open override class var defaultOption: ModelOption? {
        return [
            // zlevel: 0,
            "z": 2.0,
            "coordinateSystem": "cartesian2d",
            "legendHoverLink": true,

            // xAxisIndex: 0,
            // yAxisIndex: 0,

            "layout": NSNull(),  // 'horizontal' or 'vertical'

            "clip": true,

            "itemStyle": [
                "color": "#eb5454",       // positive
                "color0": "#47b262",      // negative
                "borderColor": "#eb5454",
                "borderColor0": "#47b262",
                "borderColorDoji": NSNull(),  // when close === open
                // borderColor: '#d24040',
                // borderColor0: '#398f4f',
                "borderWidth": 1.0
            ] as [String: Any],

            "emphasis": [
                "itemStyle": [
                    "borderWidth": 2.0
                ] as [String: Any]
            ] as [String: Any],

            "barMaxWidth": NSNull(),
            "barMinWidth": NSNull(),
            "barWidth": NSNull(),

            "large": true,
            "largeThreshold": 600.0,

            "progressive": 3e3,
            "progressiveThreshold": 1e4,
            "progressiveChunkMode": "mod",

            "animationEasing": "linear",
            "animationDuration": 300.0
        ] as [String: Any]
    }

    /**
     * Get dimension for shadow in dataZoom
     * @return dimension name
     */
    // upstream: getShadowDim() { return 'open'; }
    open func getShadowDim() -> String {
        return "open"
    }

    // upstream: brushSelector(dataIndex, data, selectors): boolean
    // PORT-NOTE (deferred): `BrushCommonSelectorsForSeries`/`selectors.rect` ARE ported (brushVisual.swift),
    //   but candlestick is not enabled in the central `brushSelectorSupported` dispatch, so this method is
    //   never invoked yet. The signature is preserved; `itemLayout.brushRect` is exposed by candlestickLayout
    //   for the eventual wiring. Deferred → returns false (matches scatter's deferred brushSelector).
    open func brushSelector(_ dataIndex: Int, _ data: SeriesData, _ selectors: Any) -> Bool {
        // const itemLayout = data.getItemLayout(dataIndex);
        // return itemLayout && selectors.rect(itemLayout.brushRect);
        _ = (dataIndex, data, selectors)
        return false
    }

    // ========================================================================================
    // from whiskerBoxCommon.ts — WhiskerBoxCommonMixin (inlined; see header note).
    // ========================================================================================

    // upstream: private _baseAxisDim: string;
    private var _baseAxisDim: String?

    // upstream: private _layout: CommonOption['layout'];   (computed layout: 'horizontal' | 'vertical')
    private var _layout: String?

    /**
     * @private
     */
    // upstream: _hasEncodeRule(key: string) { const encodeRules = this.getEncode();
    //   return encodeRules && encodeRules.get(key) != null; }
    open func _hasEncodeRule(_ key: String) -> Bool {
        let encodeRules = self.getEncode()
        return encodeRules != nil && encodeRules!.get(key) != nil
    }

    /**
     * @override
     */
    // upstream: getInitialData(option: Opts, ecModel: GlobalModel): SeriesData
    open override func getInitialData(_ option: ModelOption?, _ ecModel: GlobalModel?) -> SeriesData? {
        // When both types of xAxis and yAxis are 'value', layout is
        // needed to be specified by user. Otherwise, layout can be
        // judged by which axis is category.

        // let ordinalMeta;
        var ordinalMeta: OrdinalMeta?

        let ecModel = ecModel!
        // const xAxisModel = ecModel.getComponent('xAxis', this.get('xAxisIndex')) as CartesianAxisModel;
        let xAxisModel = ecModel.getComponent("xAxis", candlestickIndexNum(self.get("xAxisIndex"))) as! CartesianAxisModel
        let yAxisModel = ecModel.getComponent("yAxis", candlestickIndexNum(self.get("yAxisIndex"))) as! CartesianAxisModel
        let xAxisType = xAxisModel.get("type") as? String
        let yAxisType = yAxisModel.get("type") as? String
        // let addOrdinal;
        var addOrdinal = false

        // Theoretically, if `encode` and/or `layout` are not specified, they can be derived from
        // the specified one (also according to axis types). However, only the logic for deriving
        // `encode` from `layout` is implemented; the reverse direction is not implemented yet,
        // due to its complexity and low priority.
        // let layout = option.layout;
        var layout = (option as? [String: Any])?["layout"] as? String
        // 'category' axis has historically been enforcing `layout` regardless of its presence.
        // This behavior is preserved until it causes problems.
        if xAxisType == "category" {
            layout = "horizontal"
            // PORT-NOTE: upstream's generated `CartesianAxisModel` implements `AxisModelExtendedInCreator`
            //   (getOrdinalMeta); the port supplies that surface via the axisModelCreator-generated subclass
            //   (the driver's EChartsXAxisModel), reachable through the protocol. Cast through it here.
            ordinalMeta = (xAxisModel as? AxisModelExtendedInCreator)?.getOrdinalMeta()
            addOrdinal = !self._hasEncodeRule("x")
        }
        else if yAxisType == "category" {
            layout = "vertical"
            ordinalMeta = (yAxisModel as? AxisModelExtendedInCreator)?.getOrdinalMeta()
            addOrdinal = !self._hasEncodeRule("y")
        }
        // if (!layout) { layout = yAxisType === 'time' ? 'vertical' : 'horizontal'; }
        if layout == nil || layout!.isEmpty {
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
        let baseAxisType = axisModels[baseAxisDimIndex].get("type") as? String
        let otherAxisType = axisModels[1 - baseAxisDimIndex].get("type") as? String
        // const data = option.data as WhiskerBoxCommonData;
        let data = (option as? [String: Any])?["data"] as? [Any]

        // Clone a new data for next setOption({}) usage.
        // Avoid modifying current data will affect further update.
        if let data = data, addOrdinal {
            // POTENTIAL-BUG (value-semantics): upstream keeps two aliases of each data item — it mutates the
            //   SOURCE-referenced originals in place (`item.unshift(index)` / `item.value.unshift(index)`)
            //   so the Source sees the base-category index, while assigning `option.data = newOptionData`
            //   (clones WITHOUT the index) for setOption idempotency. Swift `[Any]`/`[String:Any]` are
            //   value types, and the ported `Source` holds a value copy of `option.data` prepared BEFORE
            //   this method runs — so the in-place mutation can not reach it. To reproduce the observable
            //   SOURCE state (index-prepended data) we write the INDEX-PREPENDED items back to
            //   `self.option["data"]` and re-prepare the SourceManager below. CAVEAT: unlike upstream,
            //   `self.option["data"]` is left with the index prepended; a subsequent `mergeOption` that
            //   does not replace `data` would double-prepend. Acceptable for first-render correctness;
            //   revisit when the dual-alias trick can be modeled.
            var indexedData: [Any] = []
            util.each(data) { item, index in
                if util.isArray(item) {
                    // newItem = item.slice(); item.unshift(index);
                    var arr = (item as? [Any]) ?? []
                    arr.insert(Double(index), at: 0)
                    indexedData.append(arr)
                }
                else if var itemObj = item as? [String: Any], util.isArray(itemObj["value"]) {
                    // newItem = extend({}, item); newItem.value = newItem.value.slice(); item.value.unshift(index);
                    var valueArr = (itemObj["value"] as? [Any]) ?? []
                    valueArr.insert(Double(index), at: 0)
                    itemObj["value"] = valueArr
                    indexedData.append(itemObj)
                }
                else {
                    // newItem = item;
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

        // const defaultValueDimensions = this.defaultValueDimensions;
        let defaultValueDimensions = self.defaultValueDimensions
        // const coordDimensions: CoordDimensionDefinition[] = [{...}, {...}];
        var baseDimDef = CoordDimensionDefinition()
        baseDimDef.name = baseAxisDim
        baseDimDef.type = getDimensionTypeByAxis(baseAxisType ?? "")
        baseDimDef.ordinalMeta = ordinalMeta
        // otherDims: { tooltip: false, itemName: 0 }
        var baseOtherDims = DataVisualDimensions()
        baseOtherDims.tooltip = false
        baseOtherDims.itemName = 0
        baseDimDef.otherDims = baseOtherDims
        baseDimDef.dimsDef = ["base"]

        var otherDimDef = CoordDimensionDefinition()
        otherDimDef.name = otherAxisDim
        otherDimDef.type = getDimensionTypeByAxis(otherAxisType ?? "")
        // dimsDef: defaultValueDimensions.slice()
        otherDimDef.dimsDef = defaultValueDimensions.map { $0 as Any }

        let coordDimensions: [CoordDimensionDefinitionLoose] = [baseDimDef, otherDimDef]

        // return createSeriesDataSimply(this, {
        //     coordDimensions, dimensionsCount: defaultValueDimensions.length + 1,
        //     encodeDefaulter: zrUtil.curry(makeSeriesEncodeForAxisCoordSys, coordDimensions, this) });
        var opt = PrepareSeriesDataSchemaParams(
            coordDimensions: coordDimensions,
            dimensionsCount: Double(defaultValueDimensions.count + 1)
        )
        // curry(makeSeriesEncodeForAxisCoordSys, coordDimensions, this): the curried defaulter is
        //   `(source, dimCount) -> OptionEncode`; the trailing `dimCount` is ignored. `SeriesEncodeInternal`
        //   ([String:[DimensionIndex]]) is widened to `OptionEncode`. (Same wrapping as createSeriesData.swift.)
        opt.encodeDefaulter = { (src: Source, _: Double) -> OptionEncode in
            let internalEncode = sourceHelper.makeSeriesEncodeForAxisCoordSys(coordDimensions, self, src)
            return internalEncode.mapValues { $0 as Any } as OptionEncode
        }
        return createSeriesDataSimply(self, opt)
    }

    /**
     * If horizontal, base axis is x, otherwise y.
     * @override
     */
    // upstream: getBaseAxis(): Axis2D {
    //   const dim = this._baseAxisDim;
    //   return (this.ecModel.getComponent(dim + 'Axis', this.get(dim + 'AxisIndex')) as CartesianAxisModel).axis;
    // }
    open override func getBaseAxis() -> Any? {
        let dim = self._baseAxisDim!
        let axisModel = self.ecModel!.getComponent(
            dim + "Axis", candlestickIndexNum(self.get(dim + "AxisIndex"))
        ) as! CartesianAxisModel
        return axisModel.axis as! Axis2D
    }

    // upstream: getWhiskerBoxesLayout() { return this._layout; }
    open func getWhiskerBoxesLayout() -> String? {
        return self._layout
    }
}

// export default CandlestickSeriesModel;  -> `open class CandlestickSeriesModel` above.

// Coerce an `*AxisIndex` option-bag value (`number | undefined`) to `Double?` for `getComponent`.
//   The dynamic bag may hold the number as `Int` or `Double`; both are accepted (nil -> first axis).
//   Not an upstream symbol.
private func candlestickIndexNum(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return nil
}

// SeriesModel.registerClass(CandlestickSeriesModel) is a side-effecting import-time registration upstream;
//   Swift has no import-time hook, so it is exposed as an idempotent static bootstrap the Integrate stage
//   invokes once (mirrors BaseBarSeriesModel.registerSeriesModelClass()).
extension CandlestickSeriesModel {
    @discardableResult
    public static func registerSeriesModelClass() -> Constructor {
        return SeriesModel.registerClass(CandlestickSeriesModel.self)
    }
}
