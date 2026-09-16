// Ported from echarts/src/chart/pie/PieSeries.ts — keep in sync with upstream
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
//       -> `createSeriesDataSimply` (sibling chart/helper/createSeriesDataSimply.swift).
//   import * as zrUtil from 'zrender/src/core/util';               -> `zrUtil.*` / `util.*` (ZRenderKit).
//   import * as modelUtil from '../../util/model';                 -> `model.*` (util/modelUtil.swift).
//   import { getPercentSeats } from '../../util/number';           -> `number.getPercentSeats` (util/number.swift).
//   import { makeSeriesEncodeForNameBased } from '../../data/helper/sourceHelper';
//       -> `sourceHelper.makeSeriesEncodeForNameBased` (data/helper/sourceHelper.swift).
//   import LegendVisualProvider from '../../visual/LegendVisualProvider';
//       -> visual/LegendVisualProvider.swift (PORTED). Wired below (init sets self.legendVisualProvider).
//   import SeriesModel from '../../model/Series';                  -> SeriesModel (model/Series.swift).
//   import { ... } from '../../util/types';                        -> util/types.swift (type-only; the dynamic
//       option tree is the `[String: Any]` bag per CONVENTIONS §2).
//   import type SeriesData from '../../data/SeriesData';           -> SeriesData (data/SeriesData.swift).
//   import { registerLayOutOnCoordSysUsage } from '../../core/CoordinateSystem';
//       -> `registerLayOutOnCoordSysUsage` (core/CoordinateSystemManager.swift).

// ============================================================================
// The upstream `interface`/`type` declarations (PieItemStyleOption, PieCallbackDataParams,
// PieStateOption, PieLabelOption, PieLabelLineOption, ExtraStateOption, PieDataItemOption,
// PieSeriesOption) describe the (dynamic) option tree. Per CONVENTIONS §2 the option tree is the
// `[String: Any]` bag; these types are kept as documentation only — no Swift types are emitted.
// ============================================================================

// export const SERIES_TYPE_PIE = 'pie';
public let SERIES_TYPE_PIE = "pie"

// const innerData = modelUtil.makeInner<{ seats?: number[] }, SeriesData>();
//   Read by `getDataParams` (percent seats), ported below.
//   `makeInner` requires a class Host/value (CONVENTIONS §2 + innerStore.swift); the anonymous inner
//   record `{ seats?: number[] }` is modeled as a small class.
public final class PieInnerData {
    public var seats: [Double]?
    public init() {}
}
private let innerData: (SeriesData) -> PieInnerData = model.makeInner { PieInnerData() }

// upstream: class PieSeriesModel extends SeriesModel<PieSeriesOption>
open class PieSeriesModel: SeriesModel {

    // upstream: static readonly type = 'series.' + SERIES_TYPE_PIE;  /  readonly type = PieSeriesModel.type;
    //   The static drives the instance `type` (inherited `var type { Self.type }` from ComponentModel).
    public override class var type: ComponentFullType { return "series." + SERIES_TYPE_PIE }

    /**
     * @overwrite
     */
    // upstream: init(option: PieSeriesOption): void { super.init.apply(this, arguments); ... }
    //   The upstream `init` is the model LIFECYCLE method (ported as `func \`init\``), NOT the Swift
    //   constructor. Delegates to `super.init` (builds the data via `getInitialData`) then wires the
    //   legend provider + label-line defaults.
    open override func `init`(
        _ option: ModelOption?, _ parentModel: Model? = nil, _ ecModel: GlobalModel? = nil, _ rest: Any...
    ) {
        // super.init.apply(this, arguments as any);
        super.`init`(option, parentModel, ecModel)

        // Enable legend selection for each data item
        // Use a function instead of direct access because data reference may changed
        // Enable legend selection for each data item. Use functions (not direct data refs) because the
        //   data reference may change; the provider defers access until getAllNames/getItemVisual is called.
        self.legendVisualProvider = LegendVisualProvider(
            { [unowned self] in self.getData() },
            { [unowned self] in self.getRawData() }
        )

        // this._defaultLabelLine(option);
        // upstream `option` in `init` IS `this.option` (same reference), which `super.init`
        //   has already merged with defaults/theme (label + labelLine subtrees present). The `[String: Any]`
        //   bag is a value type, so read-modify-write-back through `self.option` (not the raw `option`
        //   parameter, which is the pre-merge partial). `defaultEmphasis` bridges the bag via
        //   `DisplayStateHostOption`, mirroring `SeriesModel.defaultEmphasisOnBag`.
        if var opt = self.option as? [String: Any] {
            self._defaultLabelLine(&opt)
            self.option = opt
        }
    }

    /**
     * @overwrite
     */
    // upstream: mergeOption(): void { super.mergeOption.apply(this, arguments); }
    //   Pure delegation — the inherited `ComponentModel.mergeOption` already does exactly this, so no
    //   override is emitted (a body that only calls `super` would change nothing).

    /**
     * @overwrite
     */
    // upstream signature: getInitialData(this: PieSeriesModel): SeriesData  (ignores both params).
    //   Overrides the base `getInitialData(option, ecModel) -> SeriesData?`.
    open override func getInitialData(_ option: ModelOption?, _ ecModel: GlobalModel?) -> SeriesData? {
        // return createSeriesDataSimply(this, {
        //     coordDimensions: ['value'],
        //     encodeDefaulter: zrUtil.curry(makeSeriesEncodeForNameBased, this)
        // });
        // The `{coordDimensions, encodeDefaulter}` object literal is the `PrepareSeriesDataSchemaParams`
        //   overload of `createSeriesDataSimply` (the `extend({encodeDefine: getEncode()}, opt)` branch).
        //   `zrUtil.curry(makeSeriesEncodeForNameBased, this)` binds the series as the first arg, leaving
        //   `(source, dimCount) -> encode` — exactly the `EncodeDefaulter` shape.
        // `SeriesEncodeInternal` ([String: [DimensionIndex]]) widens to `OptionEncode`
        //   ([String: OptionEncodeValue=Any]) via `mapValues` — same bridge as createSeriesData.swift.
        return createSeriesDataSimply(self, PrepareSeriesDataSchemaParams(
            coordDimensions: ["value"],
            encodeDefaulter: { (source: Source, dimCount: Double) -> OptionEncode in
                let internalEncode = sourceHelper.makeSeriesEncodeForNameBased(self, source, dimCount)
                return internalEncode.mapValues { $0 as Any } as OptionEncode
            }
        ))
    }

    /**
     * @overwrite
     */
    // upstream: getDataParams(dataIndex: number): PieCallbackDataParams { ... percent seats ... }
    //   Overrides `SeriesModel.getDataParams` (the overridable witness for `DataFormatMixin.getDataParams`),
    //   so `getFormattedLabel`/tooltip see the `{d}` percent. `super.getDataParams` reaches the shared base
    //   (SeriesModel forwards to the `DataFormatMixin` extension) — no self-recursion.
    open override func getDataParams(_ dataIndex: Double, _ dataType: SeriesDataType? = nil) -> CallbackDataParams {
        // const data = this.getData();
        let data = self.getData()
        // const dataInner = innerData(data);
        let dataInner = innerData(data)
        // let seats = dataInner.seats;
        var seats = dataInner.seats
        // if (!seats) { ... }
        if seats == nil {
            // const valueList: number[] = [];
            var valueList: [Double] = []
            // data.each(data.mapDimension('value'), value => valueList.push(value));
            let valueDim = data.mapDimension("value") ?? "value"
            data.each(valueDim) { args in
                valueList.append((args[0] as? Double) ?? Double.nan)
            }
            // seats = dataInner.seats = getPercentSeats(valueList, data.hostModel.get('percentPrecision'));
            //   `get` boxes the option value; percentPrecision may arrive as an Int literal, so coerce
            //   both Int and Double (Int-vs-Double option-read trap) — default matches defaultOption (2).
            let precisionRaw = data.hostModel?.get("percentPrecision")
            let precision = (precisionRaw as? Double) ?? (precisionRaw as? Int).map(Double.init) ?? 2
            let computed = number.getPercentSeats(valueList, precision)
            dataInner.seats = computed
            seats = computed
        }
        // const params = super.getDataParams(dataIndex);
        var params = super.getDataParams(dataIndex, dataType)
        // params.percent = seats[dataIndex] || 0;
        let idx = Int(dataIndex)
        let seatsArr = seats ?? []
        let seat = (idx >= 0 && idx < seatsArr.count) ? seatsArr[idx] : 0
        params.percent = (seat.isNaN || seat == 0) ? 0 : seat
        // params.$vars.push('percent');
        params.vars.append("percent")
        // return params;
        return params
    }

    // upstream: private _defaultLabelLine(option): void { ... }
    //   Mutates the `[String: Any]` option bag in place (read-modify-write-back through the `inout`
    //   dictionary; the caller writes the result back to `self.option`).
    private func _defaultLabelLine(_ option: inout [String: Any]) {
        // Extend labelLine emphasis
        // modelUtil.defaultEmphasis(option, 'labelLine', ['show']);
        //   Bridge the bag through DisplayStateHostOption (cf. SeriesModel.defaultEmphasisOnBag), since
        //   `model.defaultEmphasis` consumes the typed struct.
        var host: DisplayStateHostOption? = DisplayStateHostOption()
        host!.other = option
        host!.emphasis = option["emphasis"] as? [String: Any]
        model.defaultEmphasis(&host, "labelLine", ["show"])
        option = host!.other
        if let emphasis = host!.emphasis {
            option["emphasis"] = emphasis
        }

        // const labelLineNormalOpt = option.labelLine;
        var labelLineNormalOpt = (option["labelLine"] as? [String: Any]) ?? [:]
        // const labelLineEmphasisOpt = option.emphasis.labelLine;
        var emphasis = (option["emphasis"] as? [String: Any]) ?? [:]
        var labelLineEmphasisOpt = (emphasis["labelLine"] as? [String: Any]) ?? [:]
        let labelOpt = (option["label"] as? [String: Any]) ?? [:]
        let emphasisLabelOpt = (emphasis["label"] as? [String: Any]) ?? [:]

        // Not show label line if `label.normal.show = false`
        // labelLineNormalOpt.show = labelLineNormalOpt.show && option.label.show;
        labelLineNormalOpt["show"] =
            PieSeriesModel.isTruthy(labelLineNormalOpt["show"]) && PieSeriesModel.isTruthy(labelOpt["show"])
        // labelLineEmphasisOpt.show = labelLineEmphasisOpt.show && option.emphasis.label.show;
        labelLineEmphasisOpt["show"] =
            PieSeriesModel.isTruthy(labelLineEmphasisOpt["show"]) && PieSeriesModel.isTruthy(emphasisLabelOpt["show"])

        // Write the mutated sub-bags back (value-type read-modify-write-back).
        option["labelLine"] = labelLineNormalOpt
        emphasis["labelLine"] = labelLineEmphasisOpt
        option["emphasis"] = emphasis
    }

    // Faithful JS `&&`/truthiness for an option-bag value (absent/NSNull/false/0/"" are falsy).
    private static func isTruthy(_ value: Any?) -> Bool {
        guard let value = value, !(value is NSNull) else { return false }
        if let b = value as? Bool { return b }
        if let i = value as? Int { return i != 0 }
        if let d = value as? Double { return d != 0 }
        if let s = value as? String { return !s.isEmpty }
        return true
    }

    // upstream: static defaultOption: Omit<PieSeriesOption, 'type'> = { ... }
    //   LOAD-BEARING: `coordinateSystemUsage: 'box'` is what `registerLayOutOnCoordSysUsage` /
    //   `createBoxLayoutReference` / `getCircleLayout` key on to resolve the pie's view rect (analogous
    //   to line's `coordinateSystem` being load-bearing). The full label/labelLine/labelLayout subtree
    //   is kept VERBATIM even though rendering is deferred (it is the diffable option surface).
    open override class var defaultOption: ModelOption? {
        return [
            // zlevel: 0,
            "z": 2.0,
            "legendHoverLink": true,
            "colorBy": "data",
            // 默认全局居中
            "center": ["50%", "50%"],
            "radius": [0, "50%"] as [Any],
            // 默认顺时针
            "clockwise": true,
            "startAngle": 90.0,
            "endAngle": "auto",
            "padAngle": 0.0,
            // 最小角度改为0
            "minAngle": 0.0,

            // If the angle of a sector less than `minShowLabelAngle`,
            // the label will not be displayed.
            "minShowLabelAngle": 0.0,

            // 选中时扇区偏移量
            "selectedOffset": 10.0,

            // 选择模式，默认关闭，可选single，multiple
            // selectedMode: false,
            // 南丁格尔玫瑰图模式，'radius'（半径） | 'area'（面积）
            // roseType: null,

            "percentPrecision": 2.0,

            // If still show when all data zero.
            "stillShowZeroSum": true,

            // cursor: null,
            "coordinateSystemUsage": "box",

            "left": 0.0,
            "top": 0.0,
            "right": 0.0,
            "bottom": 0.0,
            // POTENTIAL-BUG: upstream value is `null`; NSNull() retains the key in the [String: Any] bag.
            //   Faithful to JS (which keeps `width: null`), but readers using `option["width"] != nil`
            //   see NSNull (non-nil) instead of an absent key — treat NSNull as null when reading.
            "width": NSNull(),
            "height": NSNull(),

            "label": [
                // color: 'inherit',
                // If rotate around circle
                "rotate": 0.0,
                "show": true,
                "overflow": "truncate",
                // 'outer', 'inside', 'center'
                "position": "outer",
                // 'none', 'labelLine', 'edge'. Works only when position is 'outer'
                "alignTo": "none",
                // Closest distance between label and chart edge.
                // Works only position is 'outer' and alignTo is 'edge'.
                "edgeDistance": "25%",
                // Works only position is 'outer' and alignTo is not 'edge'.
                // The default `bleedMargin` is auto determined according to view rect size.
                // bleedMargin: 10,
                // Distance between text and label line.
                "distanceToLabelLine": 5.0
                // formatter: 标签文本格式器，同 tooltip.formatter，不支持异步回调
                // 默认使用全局文本样式，详见 textStyle
                // distance: 当position为inner时有效，为label位置到圆心的距离与圆半径(环状图为内外半径和)的比例系数
            ] as [String: Any],
            // Enabled when label.normal.position is 'outer'
            "labelLine": [
                "show": true,
                // 引导线两段中的第一段长度
                "length": 15.0,
                // 引导线两段中的第二段长度
                "length2": 30.0,
                "smooth": false,
                "minTurnAngle": 90.0,
                "maxSurfaceAngle": 90.0,
                "lineStyle": [
                    // color: 各异,
                    "width": 1.0,
                    "type": "solid"
                ] as [String: Any]
            ] as [String: Any],
            "itemStyle": [
                "borderWidth": 1.0,
                "borderJoin": "round"
            ] as [String: Any],

            "showEmptyCircle": true,
            "emptyCircleStyle": [
                "color": "lightgray",
                "opacity": 1.0
            ] as [String: Any],

            "labelLayout": [
                // Hide the overlapped label.
                "hideOverlap": true
            ] as [String: Any],

            "emphasis": [
                "scale": true,
                "scaleSize": 5.0
            ] as [String: Any],

            // If use strategy to avoid label overlapping
            "avoidLabelOverlap": true,

            // Animation type. Valid values: expansion, scale
            "animationType": "expansion",

            "animationDuration": 1000.0,

            // Animation type when update. Valid values: transition, expansion
            "animationTypeUpdate": "transition",

            "animationEasingUpdate": "cubicInOut",
            "animationDurationUpdate": 500.0,
            "animationEasing": "cubicInOut"
        ] as [String: Any]
    }

}

// upstream (module-level side effect):
//   registerLayOutOnCoordSysUsage({
//       fullType: PieSeriesModel.type,
//       getCoord2(model: PieSeriesModel) { return model.getShallow('center'); }
//   });
//
// Swift library files can not run top-level statements, so the call is wrapped in a lazily-initialized
// global whose initializer runs the registration EXACTLY ONCE on first access (matching a load-time
// side effect; `registerLayOutOnCoordSysUsage` asserts uniqueness, so it must not run twice). INTEGRATION
// must reference this symbol once during pie install (e.g. `_ = pieLayOutOnCoordSysUsageRegistered`),
// mirroring how the module's other registrations are wired in ECharts.
public let pieLayOutOnCoordSysUsageRegistered: Void = {
    registerLayOutOnCoordSysUsage(RegisterLayOutOnCoordSysUsageOpt(
        fullType: PieSeriesModel.type,
        // upstream typed param `model: PieSeriesModel`; the registrar callback is `(ComponentModel) -> …`.
        getCoord2: { model in
            // Not able to validate `center` type here.
            // But percentage center, such as '12%', is not allowed in this case.
            return (model.getShallow("center") as Any)
        }
    ))
}()

// export default PieSeriesModel;  -> `open class PieSeriesModel` above.
