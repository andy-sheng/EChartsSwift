// Ported from echarts/src/component/marker/MarkerModel.ts — keep in sync with upstream
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
// import * as zrUtil from 'zrender/src/core/util';                 -> ZRenderKit `util` (util.each / util.extend)
// import env from 'zrender/src/core/env';                          -> ZRenderKit `env`
// import { DataFormatMixin } from '../../model/mixin/dataFormat';  -> EChartsKit `DataFormatMixin` (model/mixin/dataFormat.swift)
// import ComponentModel from '../../model/Component';              -> EChartsKit `ComponentModel` (model/Component.swift)
// import SeriesModel from '../../model/Series';                    -> EChartsKit `SeriesModel` (model/Series.swift)
// import { ... } from '../../util/types';                          -> EChartsKit util/types.swift (same module)
// import Model from '../../model/Model';                           -> EChartsKit `Model` (model/Model.swift)
// import GlobalModel from '../../model/Global';                    -> EChartsKit `GlobalModel` (model/Global.swift)
// import SeriesData from '../../data/SeriesData';                  -> EChartsKit `SeriesData` (data/SeriesData.swift)
// import { makeInner, defaultEmphasis } from '../../util/model';   -> EChartsKit `model.makeInner` / `model.defaultEmphasis` (util/modelUtil.swift)
// import { createTooltipMarkup } from '../tooltip/tooltipMarkup';  -> EChartsKit `createTooltipMarkup` (component/tooltip/tooltipMarkup.swift)

// function fillLabel(opt: DisplayStateHostOption) {
//     defaultEmphasis(opt, 'label', ['show']);
// }
// PORT-NOTE (deferred): upstream `defaultEmphasis` mutates the plain option object in place. The ported
//   `model.defaultEmphasis` takes a typed `DisplayStateHostOption` (struct); the marker data items
//   are dynamic `[String: Any]` bags. Following the same treatment as `SeriesModel.fillDataTextStyle`
//   (model/Series.swift), the `[String: Any]` <-> DisplayStateHostOption bridging is deferred — the
//   structural walk in `_mergeOption` is preserved so no branch is dropped.
private func fillLabel(_ opt: Any?) {
    // defaultEmphasis(opt, 'label', ['show']);
    // PORT-NOTE (deferred): bridge `[String: Any]` <-> DisplayStateHostOption for `model.defaultEmphasis`.
    _ = opt
}

// export type MarkerStatisticType = 'average' | 'min' | 'max' | 'median';
public enum MarkerStatisticType: String {
    case average = "average"
    case min = "min"
    case max = "max"
    case median = "median"
}

/**
 * Option to specify where to put the marker.
 */
// upstream: interface MarkerPositionOption. An option data bag accessed dynamically; per CONVENTIONS
//   §4 an interface used as a plain data bag -> struct (value data, no identity). The marker `data`
//   array items in the user option are `[String: Any]` dicts converted to this struct by the
//   per-type views (dependent stage) before being handed to `markerHelper.dataTransform`.
public struct MarkerPositionOption {
    // Priority: x/y > coord(xAxis, yAxis) > type

    // Absolute position, px or percent string
    // upstream: x?: number | string
    public var x: Any?
    // upstream: y?: number | string
    public var y: Any?
    // upstream: relativeTo?: 'container' | 'coordinate'
    public var relativeTo: String?

    /**
     * Coord on any coordinate system
     */
    // upstream: coord?: (ScaleDataValue | MarkerStatisticType)[]
    public var coord: [Any?]?

    // On cartesian coordinate system
    // upstream: xAxis?: ScaleDataValue
    public var xAxis: Any?
    // upstream: yAxis?: ScaleDataValue
    public var yAxis: Any?

    // On polar coordinate system
    // upstream: radiusAxis?: ScaleDataValue
    public var radiusAxis: Any?
    // upstream: angleAxis?: ScaleDataValue
    public var angleAxis: Any?

    // Use statistic method
    // upstream: type?: MarkerStatisticType
    public var type: MarkerStatisticType?
    /**
     * When using statistic method with type.
     * valueIndex and valueDim can be specify which dim the statistic is used on.
     */
    // upstream: valueIndex?: number
    public var valueIndex: Double?
    // upstream: valueDim?: string
    public var valueDim: String?

    /**
     * Value to be displayed as label. Totally optional
     */
    // upstream: value?: string | number
    public var value: Any?

    public init() {}
}

// upstream: interface MarkerOption extends ComponentOption, AnimationOptionMixin { ... }
//   The runtime option is the dynamic `[String: Any]` bag (ComponentModel.option); this struct is a
//   faithful declaration of the extra marker fields (documentation/type surface, per CONVENTIONS §4).
public struct MarkerOption {
    // upstream: silent?: boolean
    public var silent: Bool?
    // upstream: data?: unknown[]
    public var data: [Any?]?
    // upstream: tooltip?: CommonTooltipOption<unknown> & { trigger?: 'item' | 'axis' | boolean | 'none' }
    // PORT-NOTE: tooltip option shape modeled as the dynamic bag.
    public var tooltip: Any?
    public init() {}
}

// { [componentType]: MarkerModel }
// const inner = makeInner<Dictionary<MarkerModel>, SeriesModel>();
// PORT-NOTE: `makeInner` requires a reference (`AnyObject`) value type; the upstream value is a plain
//   `Dictionary<MarkerModel>` object. Wrapped in a reference `MarkerModelInner` holding the map so the
//   per-host storage semantics are preserved (`inner(seriesModel).map[componentType]`).
final class MarkerModelInner {
    var map: [ComponentMainType: MarkerModel] = [:]
    init() {}
}
private let inner: (SeriesModel) -> MarkerModelInner = model.makeInner { MarkerModelInner() }

// upstream: abstract class MarkerModel<Opts extends MarkerOption = MarkerOption> extends ComponentModel<Opts>
//   The generic `Opts` is dropped per CONVENTIONS §2 (dynamic option bag). Abstract base for
//   markPoint/markLine/markArea -> `open class`.
//
// PORT-NOTE (deferred): requires reconciling `DataFormatMixin` conformance. Upstream
//   `zrUtil.mixin(MarkerModel, DataFormatMixin.prototype)` grafts the `DataFormatMixin` method set. As
//   with `SeriesModel` (see model/Series.swift), the conformance is blocked by an impedance mismatch:
//   `DataFormatMixin` requires a non-optional `ecModel: GlobalModel` (and `animatedValue`), but
//   `Model.ecModel` is `GlobalModel?`. Until that is reconciled, `getFormattedLabel`/`getRawValue` from
//   the mixin are unavailable here; `getDataParams`/`formatTooltip` are provided directly below.
//   `DataHost` (the `getData` contract) is conformed.
open class MarkerModel: ComponentModel, DataHost {

    // static type = 'marker';
    open override class var type: ComponentFullType { return "marker" }
    // type = MarkerModel.type;  (instance `type` mirrors the static via the inherited computed prop)

    /**
     * If marker model is created by self from series
     */
    // createdBySelf = false;
    public var createdBySelf = false

    // preventAutoZ = true;  (upstream overrides ComponentModel's default `preventAutoZ`)
    // PORT-NOTE: `preventAutoZ` is an inherited stored property (ComponentModel); default it to true
    //   in `init`/`_manager` is not possible at declaration due to override, so set in `init` below.

    // static readonly dependencies = ['series', 'grid', 'polar', 'geo'];
    open override class var dependencies: [String] { return ["series", "grid", "polar", "geo"] }

    // __hostSeries: SeriesModel;
    public var __hostSeries: SeriesModel?

    // private _data: SeriesData;
    private var _data: SeriesData!

    // upstream: `markerModel.seriesIndex` is injected via `zrUtil.extend(markerModel, {...})` in
    //   `_mergeOption`. ComponentModel has no `seriesIndex`; declared here (mirrors SeriesModel).
    public var seriesIndex: Double = 0

    public required init(_ option: ModelOption?, _ parentModel: Model?, _ ecModel: GlobalModel?) {
        super.init(option, parentModel, ecModel)
        // preventAutoZ = true;
        self.preventAutoZ = true
    }

    /**
     * @overrite
     */
    open override func `init`(_ option: ModelOption?, _ parentModel: Model? = nil, _ ecModel: GlobalModel? = nil, _ rest: Any...) {

        if __DEV__ {
            if self.type == "marker" {
                fatalError("Marker component is abstract component. Use markLine, markPoint, markArea instead.")
            }
        }
        self.mergeDefaultAndTheme(option, ecModel)
        self._mergeOption(option, ecModel, false, true)
    }

    // upstream: isAnimationEnabled(): boolean. Overrides `Model.isAnimationEnabled(): Bool?` (the
    //   Swift port typed it Optional); returns a non-nil Bool.
    open override func isAnimationEnabled() -> Bool? {
        // if (env.node) { return false; }
        // PORT-NOTE: ZRenderKit's `env` is module-internal (not visible from EChartsKit) and the
        //   native client is treated as browser-like (`env.node == false`), matching the treatment in
        //   model/Series.swift `isAnimationEnabled`. The node early-return is therefore dropped.

        let hostSeries = self.__hostSeries
        // return this.getShallow('animation') && hostSeries && hostSeries.isAnimationEnabled();
        return isTruthy(self.getShallow("animation"))
            && hostSeries != nil
            && (hostSeries!.isAnimationEnabled() ?? false)
    }

    /**
     * @overrite
     */
    open override func mergeOption(_ newOpt: ModelOption?, _ ecModel: GlobalModel?) {
        self._mergeOption(newOpt, ecModel, false, false)
    }

    open func _mergeOption(_ newOpt: ModelOption?, _ ecModel: GlobalModel?, _ createdBySelf: Bool? = nil, _ isInit: Bool? = nil) {
        let componentType = self.mainType
        if !(createdBySelf ?? false) {
            ecModel?.eachSeries({ seriesModel, _ in

                // mainType can be markPoint, markLine, markArea
                // const markerOpt = seriesModel.get(this.mainType as any, true) as Opts;
                // `seriesModel` (SeriesModel) adds a `get(Any?, Bool)` overload (PaletteMixin) that is
                // ambiguous with `Model.get(String, Bool?)`; upcast to `Model` to select the typed one.
                let markerOpt = (seriesModel as Model).get(self.mainType, true) as? [String: Any]

                var markerModel = inner(seriesModel).map[componentType]
                // if (!markerOpt || !markerOpt.data)
                if markerOpt == nil || markerOpt?["data"] == nil {
                    inner(seriesModel).map[componentType] = nil
                    return
                }
                if markerModel == nil {
                    if isInit ?? false {
                        // Default label emphasis `position` and `show`
                        fillLabel(markerOpt)
                    }
                    // zrUtil.each(markerOpt.data, function (item) { ... });
                    util.each((markerOpt?["data"] as? [Any?]) ?? []) { item, _ in
                        // FIXME Overwrite fillLabel method ?
                        if let pair = item as? [Any?], util.isArray(item) {
                            fillLabel(pair.count > 0 ? pair[0] : nil)
                            fillLabel(pair.count > 1 ? pair[1] : nil)
                        }
                        else {
                            fillLabel(item)
                        }
                    }

                    markerModel = self.createMarkerModelFromSeries(
                        markerOpt, self, ecModel
                    )
                    // markerModel = new ImplementedMarkerModel(markerOpt, this, ecModel);

                    // zrUtil.extend(markerModel, { mainType, seriesIndex, name, createdBySelf: true });
                    markerModel!.mainType = self.mainType
                    // Use the same series index and name
                    markerModel!.seriesIndex = seriesModel.seriesIndex
                    markerModel!.name = seriesModel.name
                    markerModel!.createdBySelf = true

                    markerModel!.__hostSeries = seriesModel
                }
                else {
                    markerModel!._mergeOption(markerOpt, ecModel, true)
                }
                inner(seriesModel).map[componentType] = markerModel
            }, self)
        }
    }

    open func formatTooltip(
        _ dataIndex: Double,
        _ multipleSeries: Bool? = nil,
        _ dataType: String? = nil
    ) -> TooltipFormatResult? {
        // const data = this.getData();
        // const value = this.getRawValue(dataIndex);
        // const itemName = data.getName(dataIndex);
        // return createTooltipMarkup('section', { header: this.name, blocks: [...] });
        //
        // PORT-NOTE (deferred): requires `getRawValue` (DataFormatMixin, conformance blocked — see class
        //   header). `createTooltipMarkup` (component/tooltip/tooltipMarkup) is ported, but the raw value
        //   feeding it is unavailable until the mixin conformance lands. Tooltip markup deferred
        //   (interaction/formatting, out of static-render scope). Returns nil until then.
        _ = (dataIndex, multipleSeries, dataType)
        return nil
    }

    // getData(): SeriesData<this> { return this._data as SeriesData<this>; }
    // DataHost.getData conformance (upstream `getData()` takes no arg; `dataType` ignored to satisfy
    //   the `DataHost` contract).
    open func getData(_ dataType: SeriesDataType? = nil) -> SeriesData {
        return self._data
    }

    open func setData(_ data: SeriesData) {
        self._data = data
    }

    open func getDataParams(
        _ dataIndex: Double,
        _ dataType: SeriesDataType? = nil
    ) -> CallbackDataParams {
        // const params = DataFormatMixin.prototype.getDataParams.call(this, dataIndex, dataType);
        // POTENTIAL-BUG: the `DataFormatMixin.getDataParams` base is unavailable (conformance blocked,
        //   see class header). The base params (color/encode/dimensionNames/…) are therefore NOT computed
        //   here — a divergence from upstream; only the host-series patch below (upstream's actual override
        //   contribution) is applied on a params scaffold built from directly-available fields. Restore the
        //   full base computation once `MarkerModel: DataFormatMixin` is unblocked.
        let data = self.getData()
        var params = CallbackDataParams(
            componentType: self.mainType,
            componentSubType: self.subType,
            componentIndex: self.componentIndex,
            seriesType: nil,
            seriesIndex: self.seriesIndex,
            seriesId: nil,
            seriesName: nil,
            name: data.getName(Int(dataIndex)),
            dataIndex: Double(data.getRawIndex(Int(dataIndex))),
            data: data.getRawDataItem(Int(dataIndex)),
            dataType: dataType,
            value: (data.getRawDataItem(Int(dataIndex)) as Any),
            color: nil,
            borderColor: nil,
            dimensionNames: nil,
            encode: nil,
            marker: nil,
            status: nil,
            dimensionIndex: nil,
            percent: nil,
            vars: ["seriesName", "name", "value"]
        )
        let hostSeries = self.__hostSeries
        if let hostSeries = hostSeries {
            params.seriesId = hostSeries.id
            params.seriesName = hostSeries.name
            params.seriesType = hostSeries.subType
        }
        return params
    }

    /**
     * Create slave marker model from series.
     */
    // abstract createMarkerModelFromSeries(markerOpt, masterMarkerModel, ecModel): MarkerModel
    // PORT-NOTE: abstract method — the per-type subclass (MarkerPointModel/MarkerLineModel/
    //   MarkerAreaModel, dependent stage) must override. `markerOpt` is the dynamic option bag.
    open func createMarkerModelFromSeries(
        _ markerOpt: Any?,
        _ masterMarkerModel: MarkerModel,
        _ ecModel: GlobalModel?
    ) -> MarkerModel {
        fatalError("createMarkerModelFromSeries must be implemented by a MarkerModel subclass")
    }

    public static func getMarkerModelFromSeries(
        _ seriesModel: SeriesModel,
        // Support three types of markers. Strict check.
        _ componentType: MarkerTypes   // 'markLine' | 'markPoint' | 'markArea'
    ) -> MarkerModel? {
        return inner(seriesModel).map[componentType]
    }
}

// interface MarkerModel<Opts> extends DataFormatMixin {}
// zrUtil.mixin(MarkerModel, DataFormatMixin.prototype);
//   -> PORT-NOTE: see class header (conformance blocked by `ecModel` optionality, mirrors SeriesModel).

// export default MarkerModel;  -> `open class MarkerModel` above.

// JS truthiness for the dynamic `getShallow('animation')` result (CONVENTIONS §6).
private func isTruthy(_ value: Any?) -> Bool {
    guard let value = value else { return false }
    if let b = value as? Bool { return b }
    if let d = value as? Double { return d != 0 && !d.isNaN }
    if let s = value as? String { return !s.isEmpty }
    return true
}
