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
// PORT: upstream `defaultEmphasis` mutates the plain option object in place. The ported
//   `model.defaultEmphasis` takes a typed `DisplayStateHostOption` (value struct); the marker data
//   items are dynamic `[String: Any]` bags. The dict is bridged into a `DisplayStateHostOption`
//   (`.other` holds the flat option keys, `.emphasis` the typed emphasis sub-bag), mutated, then bridged
//   back and returned. `_mergeOption` writes the returned value back into `markerOpt`/`markerOpt.data`
//   so the mutation propagates to `createMarkerModelFromSeries`, matching upstream's in-place edit.
//   A non-dict opt (e.g. a bare numeric data value) is returned unchanged — mirrors JS, where
//   `defaultEmphasis` on a primitive is a no-op.
private func fillLabel(_ opt: Any?) -> Any? {
    // defaultEmphasis(opt, 'label', ['show']);
    guard let dict = opt as? [String: Any] else { return opt }
    var host: DisplayStateHostOption? = DisplayStateHostOption()
    host!.other = dict
    host!.emphasis = dict["emphasis"] as? Dictionary<Any>
    model.defaultEmphasis(&host, "label", ["show"])
    guard let result = host else { return dict }
    var out = result.other
    out["emphasis"] = result.emphasis
    return out
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
    // Full source option bag. The typed fields drive coordinate calculations, while marker views
    // need the original per-end symbol/label/style options when constructing item models.
    public var rawOption: [String: Any]?
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
// PORT: upstream `zrUtil.mixin(MarkerModel, DataFormatMixin.prototype)` grafts the `DataFormatMixin`
//   method set. Mirroring `SeriesModel` (see model/Series.swift), this is conformed via the ported
//   `DataFormatMixin` protocol + extension. The former `ecModel: GlobalModel` (non-optional) impedance
//   was already resolved by relaxing the protocol requirement to `GlobalModel?`, so `getFormattedLabel`/
//   `getRawValue` from the mixin are now available here; `getDataParams`/`formatTooltip` are overridden
//   below exactly as upstream. `DataHost` (the `getData` contract `DataFormatMixin` refines) is conformed.
open class MarkerModel: ComponentModel, DataHost, DataFormatMixin {

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
                // PORT: `var` (upstream mutates `markerOpt`/its data items in place via `fillLabel`; Swift
                //   dicts are value types, so the defaulted emphasis-label is written back below before
                //   `createMarkerModelFromSeries` consumes it).
                var markerOpt = (seriesModel as Model).get(self.mainType, true) as? [String: Any]

                var markerModel = inner(seriesModel).map[componentType]
                // if (!markerOpt || !markerOpt.data)
                if markerOpt == nil || markerOpt?["data"] == nil {
                    inner(seriesModel).map[componentType] = nil
                    return
                }
                if markerModel == nil {
                    if isInit ?? false {
                        // Default label emphasis `position` and `show`
                        markerOpt = fillLabel(markerOpt) as? [String: Any]
                    }
                    // zrUtil.each(markerOpt.data, function (item) { ... });
                    var data = (markerOpt?["data"] as? [Any?]) ?? []
                    util.each(data) { item, idx in
                        // FIXME Overwrite fillLabel method ?
                        if var pair = item as? [Any?], util.isArray(item) {
                            if pair.count > 0 { pair[0] = fillLabel(pair[0]) }
                            if pair.count > 1 { pair[1] = fillLabel(pair[1]) }
                            data[idx] = pair
                        }
                        else {
                            data[idx] = fillLabel(item)
                        }
                    }
                    markerOpt?["data"] = data

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
        let data = self.getData()
        // const value = this.getRawValue(dataIndex);  (`getRawValue` from DataFormatMixin)
        let value = self.getRawValue(dataIndex)
        // const itemName = data.getName(dataIndex);
        let itemName = data.getName(Int(dataIndex))

        return createTooltipMarkup("section", TooltipMarkupSection(
            header: self.name,
            blocks: [createTooltipMarkup("nameValue", TooltipMarkupNameValueBlock(
                name: itemName,
                value: value,
                // noName: !itemName,  (JS-falsy: empty string / null)
                noName: itemName.isEmpty,
                // noValue: value == null,
                noValue: value == nil
            ))]
        ))
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
        // `getDataParams` is a `DataFormatMixin` protocol-EXTENSION member (not a requirement); reaching it
        //   through a `DataFormatMixin`-typed self dispatches statically to the shared base — mirrors the
        //   `SeriesModel.getDataParams` pattern (model/Series.swift) and matches upstream's explicit
        //   `DataFormatMixin.prototype.getDataParams.call(this, ...)`.
        var params = (self as DataFormatMixin).getDataParams(dataIndex, dataType)
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
//   -> `open class MarkerModel: ..., DataFormatMixin` above conforms to the ported `DataFormatMixin`
//      protocol + extension (mirrors SeriesModel), grafting `getRawValue`/`getFormattedLabel` and the
//      base `getDataParams`/`formatTooltip` that the overrides above build on.

// PORT-NOTE: the marker views tag their graphic els with `getECData(el).dataModel = markerModel`
//   (ECData.dataModel: DataModel?, innerStore.swift). `DataModel` (util/types.swift) refines
//   `DataHost` + `DataFormatMixin` (both conformed on the class above) and additionally requires the
//   3-arg `getDataParams(_:_:_:)`. The `el:` parameter is a port artifact that exists only on
//   upstream's CustomSeries `getDataParams` override; MarkerModel itself provides only the 2-arg form,
//   so add the 3-arg witness delegating to it. Declared on the BASE class so it covers all three
//   subclasses (MarkPointModel / MarkLineModel / MarkAreaModel). Same-module conformance ⇒ no
//   `@retroactive`. Default `= nil` keeps both the 2-arg and 3-arg forms callable.
extension MarkerModel: DataModel {
    public func getDataParams(
        _ dataIndex: Double,
        _ dataType: SeriesDataType? = nil,
        _ el: Element? = nil
    ) -> CallbackDataParams {
        // PORT-NOTE: this call MUST bind to the class-body 2-arg `open func getDataParams(_:_:)`
        //   (line ~327). It is non-recursive only because Swift prefers an exact-arity overload over
        //   applying a default argument to this 3-arg witness. If that 2-arg entry point is ever
        //   removed/renamed/given a default that changes its arity, this silently rebinds to itself
        //   and becomes infinite recursion (stack overflow on the first marker tooltip/click) rather
        //   than a compile error.
        return self.getDataParams(dataIndex, dataType)
    }
}

// export default MarkerModel;  -> `open class MarkerModel` above.

// JS truthiness for the dynamic `getShallow('animation')` result (CONVENTIONS §6).
private func isTruthy(_ value: Any?) -> Bool {
    guard let value = value else { return false }
    if let b = value as? Bool { return b }
    if let d = value as? Double { return d != 0 && !d.isNaN }
    if let s = value as? String { return !s.isEmpty }
    return true
}
