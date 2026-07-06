// Ported from echarts/src/model/Series.ts — keep in sync with upstream
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
// import * as zrUtil from 'zrender/src/core/util';                 -> util (ZRenderKit)
// import env from 'zrender/src/core/env';                          -> ZRenderKit `env` is module-internal (see isAnimationEnabled PORT-TODO)
// import * as modelUtil from '../util/model';                      -> EChartsKit `model` namespace (util/model.swift)
// import { ... } from '../util/types';                             -> EChartsKit util/types.swift (same module)
// import ComponentModel, { ComponentModelConstructor } from './Component';  -> ComponentModel (sibling model/Component.swift)
// import {PaletteMixin} from './mixin/palette';                    -> PaletteMixin (sibling model/mixin/palette.swift)
// import { DataFormatMixin } from '../model/mixin/dataFormat';     -> DataFormatMixin (sibling model/mixin/dataFormat.swift)
// import Model from '../model/Model';                              -> Model (sibling model/Model.swift)
// import { getLayoutParams, mergeLayoutParam, fetchLayoutMode } from '../util/layout';
//                                                                  -> PORT-TODO: util/layout.ts not yet ported (layout-mode merge deferred)
// import {createTask} from '../core/task';                         -> PORT-TODO: core/task.ts not ported (Phase 6) — local stub `createTask` below
// import GlobalModel from './Global';                              -> GlobalModel (util/types.swift placeholder protocol; real type lands separately this phase)
// import { CoordinateSystem } from '../coord/CoordinateSystem';    -> PORT-TODO: coord/CoordinateSystem.ts not yet ported
// import { ExtendableConstructor, mountExtend, Constructor } from '../util/clazz';  -> clazz / Constructor (util/clazz.swift)
// import { PipelineContext, SeriesTaskContext, GeneralTask, OverallTask, SeriesTask, Pipeline } from '../core/Scheduler';
//                                                                  -> PORT-TODO: core/Scheduler.ts not ported (Phase 6) — local stubs below (PipelineContext lives in util/model.swift)
// import LegendVisualProvider from '../visual/LegendVisualProvider';  -> PORT-TODO: visual/LegendVisualProvider.ts not ported
// import SeriesData from '../data/SeriesData';                     -> SeriesData (data/SeriesData.swift)
// import Axis from '../coord/Axis';                                -> PORT-TODO: coord/Axis.ts not ported
// import type { BrushCommonSelectorsForSeries, BrushSelectableArea } from '../component/brush/selector';  -> PORT-TODO: brush not ported
// import makeStyleMapper from './mixin/makeStyleMapper';           -> makeStyleMapper (sibling model/mixin/makeStyleMapper.swift)
// import { SourceManager } from '../data/helper/sourceManager';    -> PORT-TODO: data/helper/sourceManager.ts not ported — local stub below
// import { Source } from '../data/Source';                         -> Source (data/Source.swift)
// import { defaultSeriesFormatTooltip } from '../component/tooltip/seriesFormatTooltip';  -> PORT-TODO: tooltip component not ported
// import {ECSymbol} from '../util/symbol';                         -> PORT-TODO: util/symbol.ts not ported
// import {Group} from '../util/graphic';                           -> ZRenderKit.Group
// import {LegendIconParams} from '../component/legend/LegendModel'; -> PORT-TODO: legend not ported
// import {dimPermutations} from '../component/marker/MarkAreaView';  -> PORT-TODO: marker not ported
// import type ChartView from '../view/Chart';                      -> ChartView (util/types.swift placeholder)


// const inner = modelUtil.makeInner<{ data, dataBeforeProcessed, sourceManager }, SeriesModel>();
//   The inline `{}` value bag becomes a `final class` (CONVENTIONS §2 / model.makeInner requires a
//   reference type). Each field starts `undefined`, modeled as Optionals.
final class SeriesModelInner {
    var data: SeriesData?
    var dataBeforeProcessed: SeriesData?
    var sourceManager: SourceManager?
    init() {}
}
private let inner: (SeriesModel) -> SeriesModelInner = model.makeInner { SeriesModelInner() }

func getSelectionKey(_ data: SeriesData, _ dataIndex: Int) -> String {
    // return data.getName(dataIndex) || data.getId(dataIndex);
    let name = data.getName(dataIndex)
    return name.isEmpty ? data.getId(dataIndex) : name
}

public let SERIES_UNIVERSAL_TRANSITION_PROP = "__universalTransitionEnabled"

/**
 * NOTICE:
 *  - prefix `__` can be used to avoid conflicts with possible outside subclasses.
 *  - All of these methods are optional - null-check is needed.
 */
// PORT-TODO: upstream declares an `interface SeriesModel { ... }` (declaration merging) listing
//   optional methods that subclasses MAY implement and that callers null-check before invoking:
//     preventIncremental(): boolean
//     __preparePipelineContext(view: ChartView, pipeline): PipelineContext
//     __requireStartValue(axis: Axis): boolean
//     getTooltipPosition(dataIndex: number): number[]
//     getAxisTooltipData(dim, value, baseAxis): { dataIndices: number[], nestestValue: any }
//     getMarkerPosition(value, dims?, startingAtTick?): number[]
//     getLegendIcon(opt: LegendIconParams): ECSymbol | Group
//     brushSelector(dataIndex, data, selectors, area): boolean
//     enableAriaDecal(): void
//   These are kept as documentation only: they depend on types not yet ported (ChartView/Axis/
//   ECSymbol/LegendIconParams/brush selectors) and are optional by contract. Concrete series
//   subclasses add them when those types land.

// upstream: class SeriesModel<Opt extends SeriesOption = SeriesOption> extends ComponentModel<Opt>
//
// PORT-TODO: the generic `Opt` is dropped per CONVENTIONS §2 (the dynamic option tree is the `Any`
//   bag; keyed access casts to `[String: Any]`). `SeriesModel` is the project's real reference type
//   for series — `open class` (subclassed by every concrete series). It replaces the forward-
//   reference placeholder `protocol SeriesModel` that previously lived in util/types.swift.
//
//   The two upstream `zrUtil.mixin(...)` grafts are ported as protocol conformances (CONVENTIONS §2):
//     - `mixin(SeriesModel, PaletteMixin)` -> `: PaletteMixin` (its `getColorFromPalette`/
//       `clearColorPalette` extension methods are inherited; the `get` requirement is satisfied below).
//     - `mixin(SeriesModel, DataFormatMixin)` -> `: DataFormatMixin`. The impedance that once blocked
//       this (the mixin required a *non-optional* `ecModel: GlobalModel`, but `Model.ecModel` is
//       `GlobalModel?`) is resolved by relaxing the mixin's `ecModel` requirement to `GlobalModel?`
//       (neither extension method reads it) and defaulting `animatedValue` in the extension. So
//       `getDataParams`/`getFormattedLabel`/`getRawValue` are now inherited from the mixin; the
//       `formatTooltip` override below wins over the extension's empty default (as upstream).
//   `DataHost` (the `getData` contract `DataFormatMixin` refines) is conformed directly.
open class SeriesModel: ComponentModel, PaletteMixin, DataHost, DataFormatMixin {

    // [Caution]: Because this class or desecendants can be used as `XXX.extend(subProto)`,
    // the class members must not be initialized in constructor or declaration place.
    // Otherwise there is bad case:
    //   class A {xxx = 1;}
    //   enableClassExtend(A);
    //   class B extends A {}
    //   var C = B.extend({xxx: 5});
    //   var c = new C();
    //   console.log(c.xxx); // expect 5 but always 1.
    //   (PORT note: Swift uses native subclassing, so this hazard does not apply; the upstream
    //    `static protoInitialize` defaults below are expressed as Swift property default values.)

    // @readonly
    // upstream: type: string (set by protoInitialize = 'series.__base__'). The static drives the
    //   instance `type` (inherited `var type { Self.type }`); subtype series override the static.
    open override class var type: ComponentFullType { return "series.__base__" }

    // Should be impleneted in subclass.
    // upstream: defaultOption: SeriesOption
    // PORT-TODO: `defaultOption` is supplied via the inherited `class var defaultOption: ModelOption?`
    //   (ComponentModel); concrete series override that static (cf. `getDefaultOption`).

    // @readonly
    open var seriesIndex: Double = 0

    // Injected outside / @see `injectCoordinateSystem`
    // PORT-TODO: coord/CoordinateSystem.ts not ported — typed `Any?` until it lands.
    open var coordinateSystem: Any?

    // Injected outside
    // PORT-TODO: core/Scheduler.ts not ported (Phase 6) — `SeriesTask` is a local stub below.
    open var dataTask: SeriesTask!

    // Injected outside
    // CAUTION: Can read from it; but never write to it!
    open var pipelineContext: PipelineContext!

    // ---------------------------------------
    // Props to tell visual/style.ts about how to do visual encoding.
    // ---------------------------------------
    // legend visual provider to the legend component
    // PORT-TODO: visual/LegendVisualProvider.ts not ported — typed `Any?`.
    open var legendVisualProvider: Any?

    // Access path of style for visual
    open var visualStyleAccessPath: String = "itemStyle"
    // Which property is treated as main color. Which can get from the palette.
    // upstream: 'fill' | 'stroke'
    // PORT-TODO: the string-literal union is modeled as `String`.
    open var visualDrawType: String = "fill"
    // Style mapping rules.
    // upstream: ReturnType<typeof makeStyleMapper>
    open var visualStyleMapper: ((Model, [String]?, [String]?) -> Dictionary<Any>)?
    // If ignore style on data. It's only for global visual/style.ts
    // Enabled when series it self will handle it.
    open var ignoreStyleOnData: Bool = false
    // If do symbol visual encoding
    open var hasSymbolVisual: Bool = false
    // Default symbol type.
    open var defaultSymbol: String = "circle"
    // Symbol provide to legend.
    open var legendIcon: String = ""

    // It will be set temporary when cross series transition setting is from setOption.
    // TODO if deprecate further?
    // upstream: [SERIES_UNIVERSAL_TRANSITION_PROP]: boolean
    // PORT-TODO: the dynamic computed-key property `'__universalTransitionEnabled'` maps to this
    //   stored property; `isUniversalTransitionEnabled` reads it directly.
    open var __universalTransitionEnabled: Bool?

    // ---------------------------------------
    // Props about data selection
    // ---------------------------------------
    private var _selectedDataIndicesMap: [String: Double] = [:]
    public var preventUsingHoverLayer: Bool = false   // upstream: readonly; injected

    // static protoInitialize = (function () { proto.type = 'series.__base__'; proto.seriesIndex = 0;
    //   proto.ignoreStyleOnData = false; proto.hasSymbolVisual = false; proto.defaultSymbol = 'circle';
    //   proto.visualStyleAccessPath = 'itemStyle'; proto.visualDrawType = 'fill'; })();
    //   -> Expressed as the property default values above. Swift has no prototype to mutate at load.


    open override func `init`(_ option: ModelOption?, _ parentModel: Model? = nil, _ ecModel: GlobalModel? = nil, _ rest: Any...) {

        self.seriesIndex = self.componentIndex

        self.dataTask = createTask(count: dataTaskCount, reset: dataTaskReset)
        self.dataTask.context = SeriesTaskContext()
        self.dataTask.context.model = self

        self.mergeDefaultAndTheme(option, ecModel)

        let sourceManager = SourceManager(self)
        inner(self).sourceManager = sourceManager
        sourceManager.prepareSource()

        // Upstream merges theme+defaults into `option` IN PLACE (option === this.option), so
        // getInitialData sees the fully-merged option. The Swift option bag is a value type and
        // mergeDefaultAndTheme wrote the merge back to self.option — pass THAT, not the raw param
        // (which lacks the merged defaults/theme). See PORT_STATUS §29 #0a.
        let data = self.getInitialData(self.option, ecModel)

        if __DEV__ {
            util.assert(data != nil, "getInitialData returned invalid data.")
        }

        // If we reverse the order (make data firstly, and then make
        // dataBeforeProcessed by cloneShallow), cloneShallow will
        // cause data.graph.data !== data when using
        // module:echarts/data/Graph or module:echarts/data/Tree.
        // See module:echarts/data/helper/linkSeriesData

        // Theoretically, it is unreasonable to call `seriesModel.getData()` in the model
        // init or merge stage, because the data can be restored. So we do not `restoreData`
        // and `setData` here, which forbids calling `seriesModel.getData()` in this stage.
        // Call `seriesModel.getRawData()` instead.
        // this.restoreData();
        if let data = data {
            wrapData(data, self)
            self.dataTask.context.data = data

            inner(self).dataBeforeProcessed = data

            autoSeriesName(self)

            self._initSelectedMapFromData(data)
        }
    }

    /**
     * Util for merge default and theme to option
     */
    open override func mergeDefaultAndTheme(_ option: ModelOption?, _ ecModel: GlobalModel?) {
        // const layoutMode = fetchLayoutMode(this);
        // const inputPositionParams = layoutMode ? getLayoutParams(option) : {};
        // PORT-TODO: util/layout.ts not ported — layout-mode param extraction and the final
        //   `mergeLayoutParam` below are deferred.

        // Backward compat: using subType on theme.
        // But if name duplicate between series subType
        // (for example: parallel) add component mainType,
        // add suffix 'Series'.
        var themeSubType = self.subType
        if ComponentModel.hasClass(themeSubType) {
            themeSubType += "Series"
        }
        // zrUtil.merge(option, ecModel.getTheme().get(this.subType));
        // PORT-TODO: GlobalModel placeholder has no `getTheme()`; theme merge deferred until
        //   model/Global lands. `themeSubType` is computed faithfully but otherwise unused here.
        _ = themeSubType
        _ = ecModel

        // zrUtil.merge(option, this.getDefaultOption());
        // PORT-TODO: option bags are value types; merge the default into a mutable copy and write
        //   it back to `self.option` (at call time `option === self.option`). `overwrite` is false.
        if var target = (self.option ?? option) as? [String: Any],
           let def = self.getDefaultOption() as? [String: Any] {
            util.merge(&target, def, false)
            self.option = target
        }

        // Default label emphasis `show`
        // modelUtil.defaultEmphasis(option, 'label', ['show']);
        // PORT-TODO: model.defaultEmphasis takes a typed `DisplayStateHostOption` (struct); the
        //   dynamic option bag is `[String: Any]`. Top-level label emphasis defaulting deferred.

        // this.fillDataTextStyle(option.data);
        self.fillDataTextStyle((self.option as? [String: Any])?["data"])

        // if (layoutMode) { mergeLayoutParam(option, inputPositionParams, layoutMode); }
        // PORT-TODO: util/layout.ts not ported.
    }

    open override func mergeOption(_ newSeriesOption: ModelOption?, _ ecModel: GlobalModel?) {
        // this.settingTask.dirty();

        // newSeriesOption = zrUtil.merge(this.option, newSeriesOption, true);
        var mergedData: Any? = nil
        if var target = self.option as? [String: Any], let source = newSeriesOption as? [String: Any] {
            util.merge(&target, source, true)
            self.option = target
            mergedData = target["data"]
        }
        self.fillDataTextStyle(mergedData)

        // const layoutMode = fetchLayoutMode(this);
        // if (layoutMode) { mergeLayoutParam(this.option, newSeriesOption, layoutMode); }
        // PORT-TODO: util/layout.ts not ported.

        let sourceManager = inner(self).sourceManager
        sourceManager?.dirty()
        sourceManager?.prepareSource()

        // Upstream rebinds newSeriesOption to the merged this.option; the Swift merge wrote into
        // self.option but did not rebind, so pass the merged self.option (not the raw partial
        // delta, which would rebuild data missing everything not in the update). PORT_STATUS §29 #0b.
        let data = self.getInitialData(self.option, ecModel)
        if let data = data {
            wrapData(data, self)
            self.dataTask.dirty()
            self.dataTask.context.data = data

            inner(self).dataBeforeProcessed = data

            autoSeriesName(self)

            self._initSelectedMapFromData(data)
        }
    }

    open func fillDataTextStyle(_ data: Any?) {
        // Default data label emphasis `show`
        // FIXME Tree structure data ?
        // FIXME Performance ?
        if let arr = data as? [Any], !util.isTypedArray(data) {
            // const props = ['show'];
            for i in 0..<arr.count {
                // if (data[i] && data[i].label)
                if let item = arr[i] as? [String: Any], item["label"] != nil {
                    // modelUtil.defaultEmphasis(data[i], 'label', props);
                    // PORT-TODO: model.defaultEmphasis takes a typed `DisplayStateHostOption`; the
                    //   dynamic data item is `[String: Any]`. Per-item emphasis defaulting deferred.
                }
            }
        }
    }

    /**
     * Init a data structure from data related option in series
     * Must be overridden.
     */
    // upstream return type is `SeriesData` (non-optional), but the base body is `return;`
    // (undefined) — it is meant to be overridden. Modeled `SeriesData?` so the base can faithfully
    // return nil; the DEV assert in `init` flags the unoverridden case.
    open func getInitialData(_ option: ModelOption?, _ ecModel: GlobalModel?) -> SeriesData? {
        return nil
    }

    /**
     * Append data to list
     */
    // upstream param: `{ data: ArrayLike<any> }` — the inline object type becomes a value struct
    //   (CONVENTIONS §4); see `SeriesAppendDataParams` below.
    open func appendData(_ params: SeriesAppendDataParams) {
        // FIXME ???
        // (1) If data from dataset, forbidden append.
        // (2) support append data of dataset.
        let data = self.getRawData()
        data.appendData(params.data)
    }

    /**
     * Consider some method like `filter`, `map` need make new data,
     * We should make sure that `seriesModel.getData()` get correct
     * data in the stream procedure. So we fetch data from upstream
     * each time `task.perform` called.
     */
    open func getData(_ dataType: SeriesDataType? = nil) -> SeriesData {
        let task = getCurrentTask(self)
        if let task = task {
            let data = task.context.data!
            // upstream: return (dataType == null || !data.getLinkedData) ? data : data.getLinkedData(dataType);
            // PORT-TODO: `!data.getLinkedData` checks method existence; base SeriesData's
            //   getLinkedData is provided by Graph/Tree only (it fatalErrors otherwise). Treat as
            //   absent here -> always return `data` (the linked-data branch lands with Graph/Tree).
            _ = dataType
            return data
        }
        else {
            // When series is not alive (that may happen when click toolbox
            // restore or setOption with not merge mode), series data may
            // be still need to judge animation or something when graphic
            // elements want to know whether fade out.
            return inner(self).data!
        }
    }

    open func getAllData() -> [(data: SeriesData, type: SeriesDataType?)] {
        let mainData = self.getData()
        // upstream: (mainData && mainData.getLinkedDataAll) ? mainData.getLinkedDataAll() : [{ data: mainData }];
        // PORT-TODO: getLinkedDataAll is provided by Graph/Tree only (fatalErrors otherwise); treat
        //   as absent.
        return [(data: mainData, type: nil)]
    }

    open func setData(_ data: SeriesData) {
        let task = getCurrentTask(self)
        if let task = task {
            let context = task.context!
            // Consider case: filter, data sample.
            // FIXME:TS never used, so comment it
            // if (context.data !== data && task.modifyOutputEnd) {
            //     task.setOutputEnd(data.count());
            // }
            context.outputData = data
            // Caution: setData should update context.data,
            // Because getData may be called multiply in a
            // single stage and expect to get the data just
            // set. (For example, AxisProxy, x y both call
            // getData and setDate sequentially).
            // So the context.data should be fetched from
            // upstream each time when a stage starts to be
            // performed.
            if task !== self.dataTask {
                context.data = data
            }
        }
        inner(self).data = data
    }

    open func getEncode() -> HashMap<OptionEncodeValue>? {
        // const encode = (this as Model<SeriesEncodeOptionMixin>).get('encode', true);
        let encode = self.get("encode", true)
        if let encode = encode {
            // return zrUtil.createHashMap<OptionEncodeValue, DimensionName>(encode);
            // PORT-TODO: the `createHashMap` shim (util/model.swift) has no init-from-object; build
            //   it manually from the dynamic `encode` dict.
            let hm: HashMap<OptionEncodeValue> = createHashMap()
            if let dict = encode as? [String: Any] {
                for (k, v) in dict {
                    hm.set(k, v)
                }
            }
            return hm
        }
        return nil
    }

    open func getSourceManager() -> SourceManager {
        return inner(self).sourceManager!
    }

    open func getSource() -> Source {
        // upstream `SeriesModel.getSource` returns `Source` (non-optional). The ported
        // `SourceManager.getSource()` returns `Source?` (faithful to upstream's `Source | undefined`
        // return type); on the reachable series inline-data path a source is always created.
        return self.getSourceManager().getSource()!
    }

    /**
     * Get data before processed
     */
    open func getRawData() -> SeriesData {
        return inner(self).dataBeforeProcessed!
    }

    open func getColorBy() -> ColorBy {
        let colorBy = self.get("colorBy")
        // return colorBy || 'series';
        if let cb = colorBy as? ColorBy {
            return cb
        }
        if let s = colorBy as? String, let cb = ColorBy(rawValue: s) {
            return cb
        }
        return .series
    }

    open func isColorBySeries() -> Bool {
        return self.getColorBy() == .series
    }

    /**
     * Get base axis if has coordinate system and has axis.
     * By default use coordSys.getBaseAxis();
     * Can be overridden for some chart.
     * @return {type} description
     */
    // upstream return: Axis
    open func getBaseAxis() -> Any? {
        // const coordSys = this.coordinateSystem;
        // return coordSys && coordSys.getBaseAxis && coordSys.getBaseAxis();
        // (coord/CoordinateSystem + coord/Axis have landed.) `coordinateSystem` is `Any?`; upstream
        //   duck-types `coordSys.getBaseAxis`. NOTE: `Cartesian2D.getBaseAxis(): Axis2D` does NOT witness
        //   the `CoordinateSystem.getBaseAxis(): Axis?` protocol requirement (concrete non-optional
        //   subclass return vs optional protocol return → the protocol's nil default is used, same
        //   pattern as `getRect`), so a `as? CoordinateSystem` cast would spuriously return nil. Narrow
        //   to the concrete `Cartesian2D` — the same pattern `BarView`/`barGrid` use. (Polar is out of
        //   the current bar scope → nil.)
        // NOTE: narrow to the concrete `Cartesian2D` (polar is out of the current bar scope → nil).
        guard let coordSys = self.coordinateSystem as? Cartesian2D else { return nil }
        // The base axis MUST be bound to an explicit `Axis2D` local, NOT returned inline. `Cartesian2D`
        //   has a concrete `getBaseAxis(): Axis2D`, and its superprotocol `CoordinateSystem` declares
        //   `getBaseAxis(): Axis?` WITH A nil-returning default (CoordinateSystem.swift:316). In an
        //   untyped `Any?`-return position, Swift overload resolution prefers the protocol's `-> Axis?`
        //   member (its optional result matches the `Any?` context) over the concrete `-> Axis2D`, so a
        //   direct `return coordSys.getBaseAxis()` binds the DEFAULT and yields nil (verified: bars then
        //   get NaN x/width because the axis-statistics `isBaseAxis` check fails → §35b). The typed local
        //   pins resolution to the concrete method.
        let baseAxis: Axis2D = coordSys.getBaseAxis()
        return baseAxis
    }

    /**
     * Retrieve the index of nearest value in the view coordinate.
     * Data position is compared with each axis's dataToCoord.
     *
     * @param axisDim axis dimension
     * @param dim data dimension
     * @param value
     * @param [maxDistance=Infinity] The maximum distance in view coordinate space
     * @return If and only if multiple indices has
     *         the same value, they are put to the result.
     */
    open func indicesOfNearest(_ axisDim: DimensionName, _ dim: DimensionLoose, _ value: Double, _ maxDistance: Double? = nil) -> [Double] {
        // const data = this.getData();
        let data = self.getData()
        // const coordSys = this.coordinateSystem;
        // const axis = coordSys && coordSys.getAxis(axisDim);
        //   PROTOCOL-WITNESS: `coordinateSystem.getAxis(axisDim)` through the erased `CoordinateSystem`
        //   existential dispatches the nil-returning protocol default (Cartesian2D's non-optional-param
        //   `getAxis(_:)` does not witness `getAxis(_ dim: DimensionName?) -> Axis?`). Narrow to the
        //   concrete `Cartesian2D` (as findPointFromSeries / modelHelper do). Polar/single are out of scope.
        guard let coordSys = self.coordinateSystem as? Cartesian2D,
              let axis = coordSys.getAxis(axisDim) else {
            return []
        }
        // const targetCoord = axis.dataToCoord(value);
        let targetCoord = axis.dataToCoord(value)
        // if (maxDistance == null) { maxDistance = Infinity; }
        let maxDist = maxDistance ?? Double.greatestFiniteMagnitude

        var nearestIndices: [Double] = []
        var minDist = Double.greatestFiniteMagnitude
        var minDiff: Double = -1
        var nearestIndicesLen = 0

        // const dimIdx = data.getDimensionIndex(dim);
        let dimIdx = data.getDimensionIndex(dim)
        if dimIdx < 0 { return [] }   // dimension not found (getDimensionIndex returns -1)
        // const store = data.getStore();
        let store = data.getStore()
        let len = store.count()
        for idx in 0..<len {
            // const dimValue = store.get(dimIdx, idx);
            let dimValue = store.get(dimIdx, idx)
            // const dataCoord = axis.dataToCoord(dimValue);
            let dataCoord = axis.dataToCoord(dimValue)
            let diff = targetCoord - dataCoord
            let dist = abs(diff)
            if dist <= maxDist {
                if dist < minDist || (dist == minDist && diff >= 0 && minDiff < 0) {
                    minDist = dist
                    minDiff = diff
                    nearestIndicesLen = 0
                }
                if diff == minDiff {
                    // nearestIndices[nearestIndicesLen++] = idx;
                    if nearestIndicesLen < nearestIndices.count {
                        nearestIndices[nearestIndicesLen] = Double(idx)
                    } else {
                        nearestIndices.append(Double(idx))
                    }
                    nearestIndicesLen += 1
                }
            }
        }
        // nearestIndices.length = nearestIndicesLen;
        if nearestIndicesLen < nearestIndices.count {
            nearestIndices.removeLast(nearestIndices.count - nearestIndicesLen)
        }
        return nearestIndices
    }

    /**
     * Default tooltip formatter
     *
     * @param dataIndex
     * @param multipleSeries
     * @param dataType
     * @param renderMode valid values: 'html'(by default) and 'richText'.
     * @return formatted tooltip with `html` and `markers`
     */
    open func formatTooltip(
        _ dataIndex: Double,
        _ multipleSeries: Bool? = nil,
        _ dataType: SeriesDataType? = nil
    ) -> TooltipFormatResult? {
        // upstream: return defaultSeriesFormatTooltip({ series: this, dataIndex, multipleSeries });
        //   `multipleSeries` may be undefined upstream (falsy) -> `?? false`.
        _ = dataType
        return defaultSeriesFormatTooltip(
            series: self,
            dataIndex: dataIndex,
            multipleSeries: multipleSeries ?? false
        )
    }

    open override func isAnimationEnabled() -> Bool? {
        let ecModel = self.ecModel
        // Disable animation if using echarts in node but not give ssr flag.
        // In ssr mode, renderToString will generate svg with css animation.
        // if (env.node && !(ecModel && ecModel.ssr)) { return false; }
        // PORT-TODO: zrender `env` is module-internal to ZRenderKit (not exposed) and GlobalModel
        //   placeholder has no `ssr`. The native client is treated as browser-like (`env.node`
        //   false), so this early-return is skipped; revisit once `env`/Global land.
        _ = ecModel

        var animationEnabled = self.getShallow("animation")
        if jsTruthy(animationEnabled) {
            // Absent threshold => no cap (JS `count > undefined` is false, animation stays on).
            // Using 0 would wrongly disable animation for any non-empty data. PORT_STATUS §29 #1.
            if Double(self.getData().count()) > ((self.getShallow("animationThreshold") as? Double) ?? Double.infinity) {
                animationEnabled = false
            }
        }
        // return !!animationEnabled;
        return jsTruthy(animationEnabled)
    }

    open override func restoreData() {
        // See `dataTaskReset`.
        self.dataTask.dirty()
    }

    // upstream return: ZRColor
    // NOTE: the `scope` parameter type MUST match the `PaletteMixin` extension method's `scope:
    //   AnyObject?` EXACTLY. If it differs (e.g. `Any?`), the two form an overload SET rather than a
    //   shadow, and a call with an `AnyObject?` argument (e.g. `dataColorPaletteTask`'s per-item
    //   `colorScope`) resolves to the EXTENSION — bypassing this override's ecModel fallback and
    //   returning nil for any series whose own `color` option is unset (→ pie slices lose their fill).
    //   With identical signatures, this class method wins for a statically-`SeriesModel` receiver.
    open func getColorFromPalette(_ name: String, _ scope: AnyObject? = nil, _ requestColorNum: Double? = nil) -> ZRColor? {
        let ecModel = self.ecModel
        // PENDING
        // let color = PaletteMixin.prototype.getColorFromPalette.call(this, name, scope, requestColorNum);
        // PORT-TODO: upstream calls the mixin's prototype method to avoid recursing into this
        //   override; in Swift the protocol-extension method is reached by casting `self` to
        //   `PaletteMixin` (static dispatch onto the extension default).
        var color = (self as PaletteMixin).getColorFromPalette(name, scope, requestColorNum)
        if color == nil {
            // color = ecModel.getColorFromPalette(name, scope, requestColorNum);
            // PORT-TODO: GlobalModel placeholder has no `getColorFromPalette`; upstream mixes
            //   PaletteMixin onto GlobalModel, so route through that conformance when present.
            color = ecModel?.getColorFromPalette(name, scope, requestColorNum)   // GlobalModel conforms to PaletteMixin
        }
        return color
    }

    /**
     * Use `data.mapDimensionsAll(coordDim)` instead.
     * @deprecated
     */
    open func coordDimToDataDim(_ coordDim: DimensionName) -> [DimensionName] {
        return self.getRawData().mapDimensionsAll(coordDim)
    }

    /**
     * Get progressive rendering count each step
     */
    // upstream return: number | false
    open func getProgressive() -> Any? {
        return self.get("progressive")
    }

    /**
     * Get progressive rendering count each step
     */
    open func getProgressiveThreshold() -> Double {
        return (self.get("progressiveThreshold") as? Double) ?? 0
    }

    // PENGING If selectedMode is null ?
    open func select(_ innerDataIndices: [Double], _ dataType: SeriesDataType? = nil) {
        self._innerSelect(self.getData(dataType), innerDataIndices)
    }

    open func unselect(_ innerDataIndices: [Double], _ dataType: SeriesDataType? = nil) {
        var opt = (self.option as? [String: Any]) ?? [:]
        let selectedMap = opt["selectedMap"]
        if !jsTruthy(selectedMap) {
            return
        }
        let selectedMode = opt["selectedMode"]

        let data = self.getData(dataType)
        if (selectedMode as? String) == "series" || (selectedMap as? String) == "all" {
            opt["selectedMap"] = [String: Any]()
            self.option = opt
            self._selectedDataIndicesMap = [:]
            return
        }

        var selMap = (selectedMap as? [String: Any]) ?? [:]
        for i in 0..<innerDataIndices.count {
            let dataIndex = innerDataIndices[i]
            let nameOrId = getSelectionKey(data, Int(dataIndex))
            selMap[nameOrId] = false
            self._selectedDataIndicesMap[nameOrId] = -1
        }
        opt["selectedMap"] = selMap
        self.option = opt
    }

    open func toggleSelect(_ innerDataIndices: [Double], _ dataType: SeriesDataType? = nil) {
        var tmpArr: [Double] = [0]
        for i in 0..<innerDataIndices.count {
            tmpArr[0] = innerDataIndices[i]
            if self.isSelected(innerDataIndices[i], dataType) {
                self.unselect(tmpArr, dataType)
            }
            else {
                self.select(tmpArr, dataType)
            }
        }
    }

    open func getSelectedDataIndices() -> [Double] {
        if ((self.option as? [String: Any])?["selectedMap"] as? String) == "all" {
            // return [].slice.call(this.getData().getIndices());
            return self.getData().getIndices().map { Double($0) }
        }
        let selectedDataIndicesMap = self._selectedDataIndicesMap
        let nameOrIds = util.keys(selectedDataIndicesMap)
        var dataIndices: [Double] = []
        for i in 0..<nameOrIds.count {
            let dataIndex = selectedDataIndicesMap[nameOrIds[i]]!
            if dataIndex >= 0 {
                dataIndices.append(dataIndex)
            }
        }
        return dataIndices
    }

    open func isSelected(_ dataIndex: Double, _ dataType: SeriesDataType? = nil) -> Bool {
        let selectedMap = (self.option as? [String: Any])?["selectedMap"]
        if !jsTruthy(selectedMap) {
            return false
        }

        let data = self.getData(dataType)

        let inMap = (selectedMap as? String) == "all"
            || jsTruthy((selectedMap as? [String: Any])?[getSelectionKey(data, Int(dataIndex))])
        return inMap
            && !jsTruthy(data.getItemModel(Int(dataIndex)).get(["select", "disabled"]))
    }

    open func isUniversalTransitionEnabled() -> Bool {
        if self.__universalTransitionEnabled == true {
            return true
        }

        let universalTransitionOpt = (self.option as? [String: Any])?["universalTransition"]
        // Quick reject
        if !jsTruthy(universalTransitionOpt) {
            return false
        }

        if (universalTransitionOpt as? Bool) == true {
            return true
        }

        // Can be simply 'universalTransition: true'
        // return universalTransitionOpt && universalTransitionOpt.enabled;
        return jsTruthy((universalTransitionOpt as? [String: Any])?["enabled"])
    }

    private func _innerSelect(_ data: SeriesData, _ innerDataIndices: [Double]) {
        var option = (self.option as? [String: Any]) ?? [:]
        let selectedMode = option["selectedMode"]
        let len = innerDataIndices.count
        if !jsTruthy(selectedMode) || len == 0 {
            return
        }

        if (selectedMode as? String) == "series" {
            option["selectedMap"] = "all"
            self.option = option
        }
        else if (selectedMode as? String) == "multiple" {
            if !util.isObject(option["selectedMap"]) {
                option["selectedMap"] = [String: Any]()
            }
            var selectedMap = (option["selectedMap"] as? [String: Any]) ?? [:]
            for i in 0..<len {
                let dataIndex = innerDataIndices[i]
                // TODO different types of data share same object.
                let nameOrId = getSelectionKey(data, Int(dataIndex))
                selectedMap[nameOrId] = true
                self._selectedDataIndicesMap[nameOrId] = Double(data.getRawIndex(Int(dataIndex)))
            }
            option["selectedMap"] = selectedMap
            self.option = option
        }
        else if (selectedMode as? String) == "single" || (selectedMode as? Bool) == true {
            let lastDataIndex = innerDataIndices[len - 1]
            let nameOrId = getSelectionKey(data, Int(lastDataIndex))
            option["selectedMap"] = [nameOrId: true]
            self.option = option
            self._selectedDataIndicesMap = [nameOrId: Double(data.getRawIndex(Int(lastDataIndex)))]
        }
    }

    private func _initSelectedMapFromData(_ data: SeriesData) {
        // Ignore select info in data if selectedMap exists.
        // NOTE It's only for legacy usage. edge data is not supported.
        if jsTruthy((self.option as? [String: Any])?["selectedMap"]) {
            return
        }

        var dataIndices: [Double] = []
        if data.hasItemOption {
            data.each { args in
                // upstream callback receives `idx`; the no-dim store.each yields `[Double(idx)]`.
                let idx = (args[0] as? Double) ?? 0
                let rawItem = data.getRawDataItem(Int(idx))
                // if (rawItem && (rawItem as OptionDataItemObject).selected)
                // PORT-TODO: rawItem is a dynamic `OptionDataItem`; `.selected` read via dict.
                if let dict = rawItem as? [String: Any], jsTruthy(dict["selected"]) {
                    dataIndices.append(idx)
                }
            }
        }

        if dataIndices.count > 0 {
            self._innerSelect(data, dataIndices)
        }
    }

    // /**
    //  * @see {module:echarts/stream/Scheduler}
    //  */
    // abstract pipeTask: null

    // upstream: static registerClass(clz: Constructor): Constructor { return ComponentModel.registerClass(clz); }
    //   `ComponentModel.registerClass` is `static` (not overridable); this shadows it on SeriesModel.
    //
    // PORT-TODO: Swift `static func` is `final` and cannot be overridden/shadowed by a subclass with
    //   the same signature. But Swift *inherits* statics, so `SeriesModel.registerClass(clz)` already
    //   resolves to `ComponentModel.registerClass` (identical behavior to the upstream forwarder).
    //   The redeclaration is therefore dropped; the inherited static provides the same call surface.

    // MARK: - PaletteMixin conformance (`Pick<Model, 'get'>` requirement)

    // upstream: PaletteMixin requires `get` (path: string | readonly string[]). Dispatches to the
    //   typed `Model.get` overloads. Satisfies `mixin(SeriesModel, PaletteMixin)`.
    public func get(_ path: Any?, _ ignoreParent: Bool) -> Any? {
        if let s = path as? String {
            return self.get(s, ignoreParent)
        }
        if let a = path as? [String] {
            return self.get(a, ignoreParent)
        }
        if path == nil {
            return self.get()
        }
        return nil
    }
}

// upstream:
//   interface SeriesModel<Opt extends SeriesOption = SeriesOption>
//       extends DataFormatMixin, PaletteMixin<Opt>, DataHost {
//       getShadowDim?(): string   // Get dimension to render shadow in dataZoom component
//   }
//   zrUtil.mixin(SeriesModel, DataFormatMixin);
//   zrUtil.mixin(SeriesModel, PaletteMixin);
//
// PORT (CONVENTIONS §2): `PaletteMixin` + `DataHost` are conformed on the class declaration above;
//   `DataFormatMixin` conformance is blocked by the `Model.ecModel: GlobalModel?` (optional) vs
//   `DataFormatMixin.ecModel: GlobalModel` (non-optional) impedance (see the class header PORT-TODO).
//   The optional `getShadowDim()` is implemented by subclasses (dataZoom shadow) when needed.

// export type SeriesModelConstructor = typeof SeriesModel & ExtendableConstructor;
// mountExtend(SeriesModel, ComponentModel as SeriesModelConstructor);
//   -> no-op: native subclassing (`class SeriesModel: ComponentModel`) replaces the prototype
//      `extend` machinery (clazz.mountExtend is a no-op; see util/clazz.swift).


/**
 * MUST be called after `prepareSource` called
 * Here we need to make auto series, especially for auto legend. But we
 * do not modify series.name in option to avoid side effects.
 */
func autoSeriesName(_ seriesModel: SeriesModel) {
    // User specified name has higher priority, otherwise it may cause
    // series can not be queried unexpectedly.
    let name = seriesModel.name
    if !model.isNameSpecified(seriesModel) {
        // seriesModel.name = getSeriesAutoName(seriesModel) || name;
        let autoName = getSeriesAutoName(seriesModel)
        seriesModel.name = autoName.isEmpty ? name : autoName
    }
}

func getSeriesAutoName(_ seriesModel: SeriesModel) -> String {
    let data = seriesModel.getRawData()
    let dataDims = data.mapDimensionsAll("seriesName")
    var nameArr: [String] = []
    util.each(dataDims) { dataDim, _ in
        let dimInfo = data.getDimensionInfo(dataDim)
        // dimInfo.displayName && nameArr.push(dimInfo.displayName);
        if let displayName = dimInfo.displayName, !displayName.isEmpty {
            nameArr.append(displayName)
        }
    }
    return nameArr.joined(separator: " ")
}

func dataTaskCount(_ context: SeriesTaskContext) -> Double {
    return Double(context.model!.getRawData().count())
}

@discardableResult
func dataTaskReset(_ context: SeriesTaskContext) -> Any? {
    let seriesModel = context.model!
    seriesModel.setData(seriesModel.getRawData().cloneShallow())
    return dataTaskProgress
}

func dataTaskProgress(_ param: TaskProgressParams, _ context: SeriesTaskContext) {
    // Avoid repeat cloneShallow when data just created in reset.
    if let outputData = context.outputData, Int(param.end) > outputData.count() {
        _ = context.model!.getRawData().cloneShallow(context.outputData)
    }
}

// TODO refactor
func wrapData(_ data: SeriesData, _ seriesModel: SeriesModel) {
    // zrUtil.each(zrUtil.concatArray(data.CHANGABLE_METHODS, data.DOWNSAMPLE_METHODS), function (methodName) {
    //     data.wrapMethod(methodName, zrUtil.curry(onDataChange, seriesModel));
    // });
    // PORT-TODO: `util.concatArray`/`util.curry` are not ported in ZRenderKit; inlined here
    //   (`+` for concat, an explicit closure for the curried `onDataChange`).
    let methods = data.CHANGABLE_METHODS + data.DOWNSAMPLE_METHODS
    util.each(methods) { methodName, _ in
        data.wrapMethod(methodName) { args in
            // curried onDataChange(seriesModel, newList): the wrapped method's first arg is newList.
            let newList = args.first as? SeriesData
            return onDataChange(data, seriesModel, newList)
        }
    }
}

@discardableResult
func onDataChange(_ this: SeriesData, _ seriesModel: SeriesModel, _ newList: SeriesData?) -> SeriesData? {
    let task = getCurrentTask(seriesModel)
    if let task = task {
        // Consider case: filter, selectRange
        task.setOutputEnd(Double((newList ?? this).count()))
    }
    return newList
}

func getCurrentTask(_ seriesModel: SeriesModel) -> SeriesTask? {
    // const scheduler = (seriesModel.ecModel || {}).scheduler;
    // const pipeline = scheduler && scheduler.getPipeline(seriesModel.uid);
    // ... return the pipeline currentTask (or its agentStub for an OverallTask).
    // PORT-TODO: core/Scheduler.ts not ported (Phase 6) and GlobalModel placeholder has no
    //   `scheduler`; no pipeline task is reachable -> returns nil (so getData/setData fall back to
    //   `inner(this).data`). Faithful body restored when the Scheduler lands.
    _ = seriesModel
    return nil
}

// export default SeriesModel;  -> `open class SeriesModel` above.


// ============================================================================
// PORT-TODO: local stubs for the not-yet-ported Scheduler/task pipeline (Phase 6) and the
// data/helper/sourceManager. They carry faithful surface (identifiers/signatures) so this file's
// `init`/`mergeOption`/`getData`/`setData` stay structurally identical to upstream; the bodies are
// no-ops until those modules land. The agents porting `core/Scheduler.ts`, `core/task.ts`, and
// `data/helper/sourceManager.ts` MUST remove these and replace them with the real types.
// ============================================================================

// '../core/Scheduler' — SeriesTaskContext and SeriesTask are now the REAL types ported in
//   core/Scheduler.swift (`SeriesTaskContext: TaskContext`, `SeriesTask = Task<SeriesTaskContext>`).
//   The former local stubs were removed by the Scheduler-porting agent, per their PORT-TODO note.

// '../core/task' — createTask({ count, reset }). Bridges the `dataTask` config closures (which use
//   the upstream `(context)`-only shape) to the real `createTask<Ctx>(TaskDefineParam)` (core/task.swift).
//   The single-unlabeled-arg call resolves to the global generic `createTask`; this labeled overload
//   preserves the `init`/`mergeOption` call sites unchanged.
func createTask(
    count: @escaping (SeriesTaskContext) -> Double,
    reset: @escaping (SeriesTaskContext) -> Any?
) -> SeriesTask {
    return createTask(TaskDefineParam<SeriesTaskContext>(
        reset: { (_: SeriesTask, ctx: SeriesTaskContext) -> TaskResetCallbackReturn<SeriesTaskContext>? in
            let progress = reset(ctx)
            if let prog = progress as? (TaskProgressParams, SeriesTaskContext) -> Void {
                return .progress(.single({ (_, params, c) in prog(params, c) }))
            }
            return nil
        },
        count: { (_: SeriesTask, ctx: SeriesTaskContext) -> Double in count(ctx) }
    ))
}

// '../data/helper/sourceManager' — SourceManager is now the REAL type ported in
//   data/helper/sourceManager.swift (faithful port of echarts/src/data/helper/sourceManager.ts).
//   The former local stub was removed by the sourceManager-integration agent.

// upstream inline param type of `appendData`: `{ data: ArrayLike<any> }` — the anonymous object type
//   becomes a value struct (CONVENTIONS §4; no identity, plain data bag).
public struct SeriesAppendDataParams {
    public var data: ArrayLike<Any>
    public init(data: ArrayLike<Any>) {
        self.data = data
    }
}

// JS truthiness shim for the dynamic option bag (nil/false/0/NaN/"" are falsy). Not an upstream
// symbol — replaces inline `if (x)` / `x || y` truthiness on `Any?` option values.
private func jsTruthy(_ v: Any?) -> Bool {
    guard let v = v else { return false }
    if v is NSNull { return false }
    if let b = v as? Bool { return b }
    if let n = v as? Double { return n != 0 && !n.isNaN }
    if let i = v as? Int { return i != 0 }
    if let s = v as? String { return !s.isEmpty }
    return true
}

// ---------------------------------------------------------------------------
// dataStackHelper.DataStackSeriesModel conformance.
// `enableDataStack` (data/helper/dataStackHelper.swift) casts the series to `DataStackSeriesModel`
// to read `get('stack')` + `id`. Without this conformance the `as?` cast silently fails → `mayStack`
// is always false → the stack calculation dimensions are never created → stacked bar/line series
// render overlaid at the shared baseline (the classic protocol-witness trap). `id` is inherited from
// ComponentModel; the single-arg `get(_:)` witness dispatches to the two-arg option reader.
// ---------------------------------------------------------------------------
extension SeriesModel: DataStackSeriesModel {
    public func get(_ key: String) -> Any? {
        return self.get(key as Any?, false)
    }
}
