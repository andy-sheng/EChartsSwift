// Ported from echarts/src/model/Global.ts — keep in sync with upstream
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


/**
 * Caution: If the mechanism should be changed some day, these cases
 * should be considered:
 *
 * (1) In `merge option` mode, if using the same option to call `setOption`
 * many times, the result should be the same (try our best to ensure that).
 * (2) In `merge option` mode, if a component has no id/name specified, it
 * will be merged by index, and the result sequence of the components is
 * consistent to the original sequence.
 * (3) In `replaceMerge` mode, keep the result sequence of the components is
 * consistent to the original sequence, even though there might result in "hole".
 * (4) `reset` feature (in toolbox). Find detailed info in comments about
 * `mergeOption` in module:echarts/model/OptionManager.
 */

import Foundation
import ZRenderKit
// import {
//     each, filter, isArray, isObject, isString,
//     createHashMap, assert, clone, merge, extend, mixin, HashMap, isFunction
// } from 'zrender/src/core/util';                       -> ZRenderKit `util` (createHashMap/HashMap are the
//                                                          EChartsKit shim in util/model.swift; see PORT-NOTE)
// import * as modelUtil from '../util/model';           -> EChartsKit `model` namespace (util/model.swift)
// import Model from './Model';                           -> Model (sibling model/Model.swift)
// import ComponentModel, {ComponentModelConstructor} from './Component'; -> ComponentModel (sibling model/Component.swift)
// import globalDefault from './globalDefault';           -> globalDefault (sibling model/globalDefault.swift; `globalDefault.option`)
// import {resetSourceDefaulter} from '../data/helper/sourceHelper';       -> sourceHelper.resetSourceDefaulter
// import SeriesModel from './Series';                     -> SeriesModel (sibling model/Series.swift)
// import { ... } from '../util/types';                    -> EChartsKit util/types.swift (same module)
// import OptionManager from './OptionManager';            -> `OptionManager` (ported, model/OptionManager.swift)
// import Scheduler from '../core/Scheduler';              -> `Scheduler` (ported, core/Scheduler.swift)
// import { concatInternalOptions } from './internalComponentCreator';     -> concatInternalOptions (free func, model/internalComponentCreator.swift)
// import { LocaleOption } from '../core/locale';          -> core/locale.swift (ported); `Model<LocaleOption>` modeled as `Model`
// import {PaletteMixin} from './mixin/palette';           -> PaletteMixin (protocol + extension, model/mixin/palette.swift)
// import { error, warn } from '../util/log';              -> log.error / log.warn (util/log.swift)

// OptionManager: the real `final class OptionManager` is ported in the sibling model/OptionManager.swift.

// core/Scheduler.ts — the real `final class Scheduler` is ported in core/Scheduler.swift (same
//   module). `GlobalModelSetOptionOpts.scheduler` references it directly.

public struct GlobalModelSetOptionOpts {
    // upstream: replaceMerge: ComponentMainType | ComponentMainType[]
    public var replaceMerge: Any?
    public init(replaceMerge: Any? = nil) { self.replaceMerge = replaceMerge }
}
public struct InnerSetOptionOpts {
    public var replaceMergeMainTypeMap: HashMap<Bool>   // upstream: HashMap<boolean, string>
    public init(replaceMergeMainTypeMap: HashMap<Bool>) {
        self.replaceMergeMainTypeMap = replaceMergeMainTypeMap
    }
}

// -----------------------
// Internal method names:
// -----------------------
// upstream declares these as module-level `let`s reassigned inside the `internalField` static IIFE
// (see the bottom of the class). Ported as file-private free funcs at the end of this file so call
// sites stay `reCreateSeriesIndices(self)` / `assertSeriesInitialized(self)` / `initBase(self, ...)`.

private let OPTION_INNER_KEY = "\u{0}_ec_inner"
private let OPTION_INNER_VALUE = 1.0

private let BUITIN_COMPONENTS_MAP: [String: String] = [
    "grid": "GridComponent",
    "polar": "PolarComponent",
    "geo": "GeoComponent",
    "singleAxis": "SingleAxisComponent",
    "parallel": "ParallelComponent",
    "calendar": "CalendarComponent",
    "matrix": "MatrixComponent",
    "graphic": "GraphicComponent",
    "toolbox": "ToolboxComponent",
    "tooltip": "TooltipComponent",
    "axisPointer": "AxisPointerComponent",
    "brush": "BrushComponent",
    "title": "TitleComponent",
    "timeline": "TimelineComponent",
    "markPoint": "MarkPointComponent",
    "markLine": "MarkLineComponent",
    "markArea": "MarkAreaComponent",
    "legend": "LegendComponent",
    "dataZoom": "DataZoomComponent",
    "visualMap": "VisualMapComponent",
    // aria: 'AriaComponent',
    // dataset: 'DatasetComponent',

    // Dependencies
    "xAxis": "GridComponent",
    "yAxis": "GridComponent",
    "angleAxis": "PolarComponent",
    "radiusAxis": "PolarComponent"
]

private let BUILTIN_CHARTS_MAP: [String: String] = [
    "line": "LineChart",
    "bar": "BarChart",
    "pie": "PieChart",
    "scatter": "ScatterChart",
    "radar": "RadarChart",
    "map": "MapChart",
    "tree": "TreeChart",
    "treemap": "TreemapChart",
    "graph": "GraphChart",
    "chord": "ChordChart",
    "gauge": "GaugeChart",
    "funnel": "FunnelChart",
    "parallel": "ParallelChart",
    "sankey": "SankeyChart",
    "boxplot": "BoxplotChart",
    "candlestick": "CandlestickChart",
    "effectScatter": "EffectScatterChart",
    "lines": "LinesChart",
    "heatmap": "HeatmapChart",
    "pictorialBar": "PictorialBarChart",
    "themeRiver": "ThemeRiverChart",
    "sunburst": "SunburstChart",
    "custom": "CustomChart"
]

private var componetsMissingLogPrinted: [String: Bool] = [:]

private func checkMissingComponents(_ option: ECUnitOption) {
    // each(option, function (componentOption, mainType) { ... })
    // PORT-NOTE: JS object key order is not guaranteed by Swift dictionaries; the log order may differ.
    for (mainType, _) in option {
        if !ComponentModel.hasClass(mainType) {
            let componentImportName = BUITIN_COMPONENTS_MAP[mainType]
            if let componentImportName = componentImportName, componetsMissingLogPrinted[componentImportName] == nil {
                log.error("Component \(mainType) is used but not imported.\nimport { \(componentImportName) } from 'echarts/components';\necharts.use([\(componentImportName)]);")
                componetsMissingLogPrinted[componentImportName] = true
            }
        }
    }
}

// upstream: class GlobalModel extends Model<ECUnitOption>
//
// PORT (CONVENTIONS §2): the generic `Opt = ECUnitOption` is dropped (the dynamic option tree is the
//   `[String: Any]` bag; keyed access casts). `GlobalModel` is the real parsed/merged option tree —
//   an `open class` (reference type). It conforms to `PaletteMixin` (upstream `mixin(GlobalModel,
//   PaletteMixin)`; see the bottom of the file). It replaces the forward-reference placeholder
//   `protocol GlobalModel` that previously lived in util/types.swift.
open class GlobalModel: Model, PaletteMixin {
    // @readonly
    // upstream re-declares `option: ECUnitOption`. Swift can not re-type an inherited stored property;
    // we use the inherited `Model.option: ModelOption?` (= `Any?`) and cast to `[String: Any]`
    // (= ECUnitOption) at the keyed-access sites below.

    fileprivate var _theme: Model! = nil

    fileprivate var _locale: Model! = nil

    fileprivate var _optionManager: OptionManager! = nil

    fileprivate var _componentsMap: HashMap<[ComponentModel?]>! = nil

    /**
     * `_componentsMap` might have "hole" because of remove.
     * So save components count for a certain mainType here.
     */
    fileprivate var _componentsCount: HashMap<Double>! = nil

    /**
     * Mapping between filtered series list and raw series list.
     * key: filtered series indices, value: raw series indices.
     * Items of `_seriesIndices` never be null/empty/-1.
     * If series has been removed by `replaceMerge`, those series
     * also won't be in `_seriesIndices`, just like be filtered.
     */
    fileprivate var _seriesIndices: [Double]! = nil

    /**
     * Key: seriesIndex.
     * Keep consistent with `_seriesIndices`.
     */
    fileprivate var _seriesIndicesMap: HashMap<Double>! = nil

    /**
     * Model for store update payload
     */
    fileprivate var _payload: Payload?

    // Injectable properties:
    public var scheduler: Scheduler?

    // If in ssr mode.
    // TODO put in a better place?
    public var ssr: Bool = false

    // upstream: init(option, parentModel, ecModel, theme, locale, optionManager): void
    //
    // PORT-NOTE: the base overridable lifecycle method is `` `init` `` (see Model.swift), whose
    //   signature is `(option, parentModel, ecModel, rest...)`. GlobalModel's upstream `init` adds
    //   three fixed params (theme, locale, optionManager), which are folded into `rest` here to keep
    //   the override signature compatible with the base method.
    open override func `init`(
        _ option: ModelOption?,
        _ parentModel: Model? = nil,
        _ ecModel: GlobalModel? = nil,
        _ rest: Any...
    ) {
        let theme: Any? = rest.count > 0 ? rest[0] : nil
        let locale: Any? = rest.count > 1 ? rest[1] : nil
        let optionManager: OptionManager? = rest.count > 2 ? (rest[2] as? OptionManager) : nil

        // theme = theme || {};
        let themeObj: Any = theme ?? [String: Any]()
        self.option = nil // Mark as not initialized.
        self._theme = Model(themeObj)
        self._locale = Model(locale ?? [String: Any]())
        self._optionManager = optionManager
    }

    // upstream: setOption(option: ECBasicOption, opts, optionPreprocessorFuncs)
    // PORT-NOTE: the ported `OptionManager.setOption` takes the dynamic `ECUnitOption?` bag (not the
    //   typed `ECBasicOption` struct), so `option` is typed to match — consistent with the dynamic
    //   option-tree convention.
    open func setOption(
        _ option: ECUnitOption?,
        _ opts: GlobalModelSetOptionOpts?,
        _ optionPreprocessorFuncs: [OptionPreprocessor]
    ) {
        if __DEV__ {
            util.assert(option != nil, "option is null/undefined")
            util.assert(
                (option?[OPTION_INNER_KEY] as? Double) != OPTION_INNER_VALUE,
                "please use chart.getOption()"
            )
        }

        let innerOpt = normalizeSetOptionInput(opts)

        self._optionManager.setOption(option, optionPreprocessorFuncs, innerOpt)

        self._resetOption(nil, innerOpt)
    }

    /**
     * @param type null/undefined: reset all.
     *        'recreate': force recreate all.
     *        'timeline': only reset timeline option
     *        'media': only reset media query option
     * @return Whether option changed.
     */
    @discardableResult
    open func resetOption(
        _ type: String?,
        _ opt: GlobalModelSetOptionOpts? = nil
    ) -> Bool {
        return self._resetOption(type, normalizeSetOptionInput(opt))
    }

    @discardableResult
    fileprivate func _resetOption(
        _ type: String?,
        _ opt: InnerSetOptionOpts
    ) -> Bool {
        var optionChanged = false
        let optionManager = self._optionManager

        if type == nil || type == "recreate" {
            let baseOption = optionManager!.mountOption(type == "recreate")
            if __DEV__ {
                checkMissingComponents(baseOption)
            }

            if self.option == nil || type == "recreate" {
                initBase(self, baseOption)
            }
            else {
                self.restoreData()
                self._mergeOption(baseOption, opt)
            }
            optionChanged = true
        }

        if type == "timeline" || type == "media" {
            self.restoreData()
        }

        // By design, if `setOption(option2)` at the second time, and `option2` is a `ECUnitOption`,
        // it should better not have the same props with `MediaUnit['option']`.
        // Because either `option2` or `MediaUnit['option']` will be always merged to "current option"
        // rather than original "baseOption". If they both override a prop, the result might be
        // unexpected when media state changed after `setOption` called.
        // If we really need to modify a props in each `MediaUnit['option']`, use the full version
        // (`{baseOption, media}`) in `setOption`.
        // For `timeline`, the case is the same.

        if type == nil || type == "recreate" || type == "timeline" {
            let timelineOption = optionManager!.getTimelineOption(self)
            if let timelineOption = timelineOption {
                optionChanged = true
                self._mergeOption(timelineOption, opt)
            }
        }

        if type == nil || type == "recreate" || type == "media" {
            let mediaOptions = optionManager!.getMediaOption(self)
            if mediaOptions.count > 0 {
                util.each(mediaOptions) { mediaOption, _ in
                    optionChanged = true
                    self._mergeOption(mediaOption, opt)
                }
            }
        }

        return optionChanged
    }

    open func mergeOption(_ option: ECUnitOption) {
        self._mergeOption(option, nil)
    }

    fileprivate func _mergeOption(
        _ newOption: ECUnitOption,
        _ opt: InnerSetOptionOpts?
    ) {
        var option = (self.option as? [String: Any]) ?? [:]
        let componentsMap = self._componentsMap!
        let componentsCount = self._componentsCount!
        var newCmptTypes: [ComponentMainType] = []
        let newCmptTypeMap: HashMap<Bool> = createHashMap()
        let replaceMergeMainTypeMap = opt?.replaceMergeMainTypeMap

        sourceHelper.resetSourceDefaulter(self)

        // If no component class, merge directly.
        // For example: color, animaiton options, etc.
        // PORT-NOTE: JS object key order is not preserved by Swift dictionaries; `newCmptTypes` order
        //   may differ (topologicalTravel re-sorts by dependency, so the final order is unaffected).
        for (mainType, componentOption) in newOption {
            if isNullish(componentOption) {
                continue
            }

            if !ComponentModel.hasClass(mainType) {
                // globalSettingTask.dirty();
                // option[mainType] = option[mainType] == null ? clone(componentOption) : merge(option[mainType], componentOption, true);
                if isNullish(option[mainType]) {
                    option[mainType] = util.clone(componentOption) as Any
                }
                else if var tgt = option[mainType] as? [String: Any], let src = componentOption as? [String: Any] {
                    util.merge(&tgt, src, true)
                    option[mainType] = tgt
                }
                else {
                    // PORT-NOTE: upstream `merge(option[mainType], componentOption, true)` also merges
                    //   arrays/primitives; the ported `util.merge` handles only dicts. For the non-dict
                    //   case with overwrite == true the merge result IS the (cloned) source, so this is
                    //   semantically equivalent.
                    option[mainType] = util.clone(componentOption) as Any
                }
            }
            else if !mainType.isEmpty {
                newCmptTypes.append(mainType)
                newCmptTypeMap.set(mainType, true)
            }
        }

        if let replaceMergeMainTypeMap = replaceMergeMainTypeMap {
            // If there is a mainType `xxx` in `replaceMerge` but not declared in option,
            // we trade it as it is declared in option as `{xxx: []}`. Because:
            // (1) for normal merge, `{xxx: null/undefined}` are the same meaning as `{xxx: []}`.
            // (2) some preprocessor may convert some of `{xxx: null/undefined}` to `{xxx: []}`.
            replaceMergeMainTypeMap.each { _, mainTypeInReplaceMerge in
                if ComponentModel.hasClass(mainTypeInReplaceMerge) && !(newCmptTypeMap.get(mainTypeInReplaceMerge) ?? false) {
                    newCmptTypes.append(mainTypeInReplaceMerge)
                    newCmptTypeMap.set(mainTypeInReplaceMerge, true)
                }
            }
        }

        // upstream: function visitComponent(this: GlobalModel, mainType: ComponentMainType): void
        //   Ported as a nested func capturing `option`/`componentsMap`/`componentsCount`/`newOption`/self.
        func visitComponent(_ mainType: ComponentMainType, _ dependencies: [ComponentMainType]) {
            // const newCmptOptionList = concatInternalOptions(this, mainType, modelUtil.normalizeToArray(newOption[mainType]));
            // PORT: `newOption[mainType]` is a dynamic option bag (`[String: Any]` / array of bags),
            //   NOT a typed `[ComponentOption]`. Upstream's `ComponentOption` IS that dynamic object;
            //   the Swift struct is a lossy typed subset, so each bag is projected into a
            //   `ComponentOption` that also carries the full bag in `.rawOption` (used below when the
            //   option is handed to the created/merged component model). This replaces the previous
            //   inert `normalizeToArray<ComponentOption>` (which yielded `[]` on dynamic bags).
            let newCmptOptionList: [ComponentOption] = concatInternalOptions(
                self, mainType, normalizeToComponentOptionList(newOption[mainType])
            )

            let oldCmptList = componentsMap.get(mainType)
            // upstream passes `oldCmptList` (ComponentModel[]) where MappingExistingItem[] is expected.
            // The ported protocols require optional id/name/subType witnesses, so wrap each model.
            // "Holes" (removed components, left behind by a previous `replaceMerge`) are PRESERVED as
            //   nil elements, per model.ts:302-304: upstream's `existings: T[]` carries the holes and
            //   `prepareResult` iterates by index precisely so they are not omitted. Using `map`
            //   (not `compactMap`) keeps existings/result/idIdxMap index-aligned with `oldCmptList`.
            let oldExistings: [MappingExistingItem?]? = oldCmptList.map { list in
                list.map { (cmpt: ComponentModel?) -> MappingExistingItem? in
                    cmpt.map { ExistingComponentItem($0) }
                }
            }
            let mergeMode: MappingToExistsMode =
                // `!oldCmptList` means init. See the comment in `mappingToExists`
                  (oldCmptList == nil) ? .replaceAll
                : ((replaceMergeMainTypeMap?.get(mainType) ?? false)) ? .replaceMerge
                : .normalMerge
            let mappingResult = model.mappingToExists(oldExistings, newCmptOptionList, mergeMode)

            // Set mainType and complete subType.
            model.setComponentTypeToKeyInfo(mappingResult, mainType, GlobalComponentModelConstructor.self)

            // Empty it before the travel, in order to prevent `this._componentsMap`
            // from being used in the `init`/`mergeOption`/`optionUpdated` of some
            // components, which is probably incorrect logic.
            option[mainType] = NSNull() // option[mainType] = null
            // PORT-NOTE: upstream sets componentsMap[mainType] = null; the shim value type is
            //   non-optional so we clear to [] (transient — overwritten below in this func).
            componentsMap.set(mainType, [])
            componentsCount.set(mainType, 0)

            var optionsByMainType: [Any?] = []           // as ComponentOption[]
            var cmptsByMainType: [ComponentModel?] = []  // as ComponentModel[]
            var cmptsCountByMainType = 0.0

            var tooltipExists = false
            var tooltipWarningLogged = false

            util.each(mappingResult) { resultItem, index in
                var componentModel = (resultItem.existing as? ExistingComponentItem)?.cmpt
                let newCmptOption = resultItem.newOption

                if newCmptOption == nil {
                    if let componentModel = componentModel {
                        // Consider where is no new option and should be merged using {},
                        // see removeEdgeAndAdd in topologicalTravel and
                        // ComponentModel.getAllClassMainTypes.
                        componentModel.mergeOption([String: Any](), self)
                        componentModel.optionUpdated([String: Any](), false)
                    }
                    // If no both `resultItem.exist` and `resultItem.option`,
                    // either it is in `replaceMerge` and not matched by any id,
                    // or it has been removed in previous `replaceMerge` and left a "hole" in this component index.
                }
                else {
                    let isSeriesType = mainType == "series"
                    let ComponentModelClass = ComponentModel.getClass(
                        mainType,
                        resultItem.keyInfo?.subType,
                        !isSeriesType // Give a more detailed warn later if series don't exists
                    )

                    if ComponentModelClass == nil {
                        if __DEV__ {
                            let subType = resultItem.keyInfo?.subType ?? ""
                            let seriesImportName = BUILTIN_CHARTS_MAP[subType]
                            if componetsMissingLogPrinted[subType] == nil {
                                componetsMissingLogPrinted[subType] = true
                                if let seriesImportName = seriesImportName {
                                    log.error("Series \(subType) is used but not imported.\nimport { \(seriesImportName) } from 'echarts/charts';\necharts.use([\(seriesImportName)]);")
                                }
                                else {
                                    log.error("Unknown series \(subType)")
                                }
                            }
                        }
                        return
                    }

                    // TODO Before multiple tooltips get supported, we do this check to avoid unexpected exception.
                    if mainType == "tooltip" {
                        if tooltipExists {
                            if __DEV__ {
                                if !tooltipWarningLogged {
                                    log.warn("Currently only one tooltip component is allowed.")
                                    tooltipWarningLogged = true
                                }
                            }
                            return
                        }
                        tooltipExists = true
                    }

                    // PORT: `newCmptOption` (a `ComponentOption`) carries the full dynamic option bag
                    //   in `.rawOption`; that bag (`[String: Any]`) is what the ported model layer
                    //   consumes as `ModelOption` (`self.option`). Upstream passes the `ComponentOption`
                    //   object directly.
                    let newCmptOptionBag = newCmptOption!.rawOption

                    if componentModel != nil && sameConstructor(componentModel!, ComponentModelClass!) {
                        componentModel!.name = resultItem.keyInfo!.name
                        // componentModel.settingTask && componentModel.settingTask.dirty();
                        componentModel!.mergeOption(newCmptOptionBag, self)
                        componentModel!.optionUpdated(newCmptOptionBag, false)
                    }
                    else {
                        // PENDING Global as parent ?
                        // const extraOpt = extend({ componentIndex: index }, resultItem.keyInfo);
                        // componentModel = new ComponentModelClass(newCmptOption, this, this, extraOpt);
                        // // Assign `keyInfo`
                        // extend(componentModel, extraOpt);
                        //
                        // PORT: the registry returns a `Constructor` (= `ClassManageable.Type`); the
                        //   registered classes are `ComponentModel` subclasses, so downcast to
                        //   `ComponentModel.Type` and instantiate via the `required` designated init.
                        //   `extraOpt` (= { componentIndex } ∪ keyInfo) is assigned to the typed
                        //   stored properties directly (no dynamic `extend`). The Swift `ComponentModel`
                        //   initializer does NOT auto-call the lifecycle `` `init` `` (that JS-constructor
                        //   auto-call is commented out in Model.swift), so the explicit `` `init` ``
                        //   below is the single lifecycle-init call. keyInfo is assigned BEFORE it so
                        //   `mergeDefaultAndTheme`/series init can read `subType`/`componentIndex`.
                        guard let componentModelClass = ComponentModelClass as? ComponentModel.Type else {
                            // PORT-NOTE: a registered class that is not a ComponentModel subclass can
                            //   not be instantiated through this path; skip (upstream has no analogue —
                            //   every registered class is a ComponentModel).
                            _ = index
                            componentModel = nil
                            return
                        }
                        let created = componentModelClass.init(newCmptOptionBag, self, self)

                        // extend(componentModel, extraOpt): componentIndex + keyInfo fields.
                        created.componentIndex = Double(index)
                        if let keyInfo = resultItem.keyInfo {
                            created.mainType = keyInfo.mainType
                            created.subType = keyInfo.subType
                            created.name = keyInfo.name
                            created.id = keyInfo.id
                        }
                        if resultItem.brandNew == true {
                            created.__requireNewView = true
                        }
                        created.`init`(newCmptOptionBag, self, self)

                        // Call optionUpdated after init.
                        // newCmptOption has been used as componentModel.option
                        // and may be merged with theme and default, so pass null
                        // to avoid confusion.
                        created.optionUpdated(nil, true)

                        componentModel = created
                    }
                }

                if let componentModel = componentModel {
                    optionsByMainType.append(componentModel.option)
                    cmptsByMainType.append(componentModel)
                    cmptsCountByMainType += 1
                }
                else {
                    // Always do assign to avoid elided item in array.
                    optionsByMainType.append(nil)  // void 0
                    cmptsByMainType.append(nil)    // void 0
                }
            }

            option[mainType] = optionsByMainType
            componentsMap.set(mainType, cmptsByMainType)
            componentsCount.set(mainType, cmptsCountByMainType)

            // Backup series for filtering.
            if mainType == "series" {
                reCreateSeriesIndices(self)
            }
        }

        // upstream: (ComponentModel as ComponentModelConstructor).topologicalTravel(newCmptTypes, ..., visitComponent, this)
        // PORT-NOTE: the ported `topologicalTravel` is `throws`; upstream lets its internal assert
        //   propagate. Swallowed with `try?` to keep the non-throwing public API (semantically
        //   equivalent — a failed assert aborts the travel either way).
        try? ComponentModel.topologicalTravel(
            newCmptTypes,
            ComponentModel.getAllClassMainTypes(),
            visitComponent,
            self
        )

        self.option = option

        // If no series declared, ensure `_seriesIndices` initialized.
        if self._seriesIndices == nil {
            reCreateSeriesIndices(self)
        }
    }

    /**
     * Get option for output (cloned option and inner info removed)
     */
    open func getOption() -> ECUnitOption {
        var option = util.clone((self.option as? [String: Any]) ?? [:])

        // each(option, function (optInMainType, mainType) { ... })
        for mainType in Array(option.keys) {
            let optInMainType = option[mainType]
            if ComponentModel.hasClass(mainType) {
                var opts: [Any?] = (model.normalizeToArray(optInMainType) as [Any]).map { $0 as Any? }
                // Inner cmpts need to be removed.
                // Inner cmpts might not be at last since ec5.0, but still
                // compatible for users: if inner cmpt at last, splice the returned array.
                var realLen = opts.count
                var metNonInner = false
                var i = realLen - 1
                while i >= 0 {
                    // Remove options with inner id.
                    if let item = opts[i], !model.isComponentIdInternal(optionBagToComparable(item)) {
                        metNonInner = true
                    }
                    else {
                        opts[i] = nil
                        if !metNonInner { realLen -= 1 }
                    }
                    i -= 1
                }
                opts = Array(opts.prefix(realLen)) // opts.length = realLen
                option[mainType] = opts
            }
        }

        option[OPTION_INNER_KEY] = nil // delete option[OPTION_INNER_KEY]

        return option
    }

    open func setTheme(_ theme: Any) {
        self._theme = Model(theme)
        self._resetOption("recreate", InnerSetOptionOpts(replaceMergeMainTypeMap: createHashMap()))
    }

    open func getTheme() -> Model {
        return self._theme
    }

    // upstream: getLocaleModel(): Model<LocaleOption>
    open func getLocaleModel() -> Model {
        return self._locale
    }

    open func setUpdatePayload(_ payload: Payload?) {
        self._payload = payload
    }

    open func getUpdatePayload() -> Payload? {
        return self._payload
    }

    /**
     * @param idx If not specified, return the first one.
     */
    open func getComponent(_ mainType: ComponentMainType, _ idx: Double? = nil) -> ComponentModel? {
        let list = self._componentsMap.get(mainType)
        if let list = list {
            let i = Int(idx ?? 0) // list[idx || 0]
            if i >= 0 && i < list.count, let cmpt = list[i] {
                return cmpt
            }
            else if idx == nil {
                for j in 0..<list.count {
                    if let c = list[j] {
                        return c
                    }
                }
            }
        }
        return nil
    }

    /**
     * @return Never be null/undefined.
     */
    open func queryComponents(_ condition: QueryConditionKindB) -> [ComponentModel] {
        let mainType = condition.mainType
        if mainType.isEmpty { // if (!mainType)
            return []
        }

        let index = condition.index
        let id = condition.id
        let name = condition.name
        let cmpts = self._componentsMap.get(mainType)

        guard let cmpts = cmpts, cmpts.count > 0 else {
            return []
        }

        var result: [ComponentModel]

        if index != nil {
            var res: [ComponentModel] = []
            // Int-vs-Double option-read trap: an option index written as a Swift Int literal
            // (e.g. `datasetIndex: 1`, `xAxisIndex: 0`) does NOT satisfy `as? Double`, so a naive
            // `normalizeToArray<Double>(index)` would drop it and silently resolve to no component.
            // Coerce each element (Int/Double/NSNumber) to Double, honoring both scalar and array forms.
            let idxArr: [Double] = queryComponentsIndexToDoubles(index)
            util.each(idxArr) { idx, _ in
                let i = Int(idx)
                if i >= 0 && i < cmpts.count, let c = cmpts[i] {
                    res.append(c)
                }
            }
            result = res
        }
        else if id != nil {
            result = queryByIdOrName(.id, id, cmpts)
        }
        else if name != nil {
            result = queryByIdOrName(.name, name, cmpts)
        }
        else {
            // Return all non-empty components in that mainType
            result = util.filter(cmpts, { cmpt, _ in cmpt != nil }).map { $0! }
        }

        return filterBySubType(result, condition)
    }

    // Coerce a query `index` (JS `number | number[]`) to `[Double]`, tolerating Int/NSNumber boxing.
    // Mirrors `model.normalizeToArray` but with numeric coercion so Int-literal option indices survive.
    private func queryComponentsIndexToDoubles(_ value: Any?) -> [Double] {
        func toDouble(_ v: Any?) -> Double? {
            switch v {
            case let d as Double: return d
            case let i as Int: return Double(i)
            case let n as NSNumber: return n.doubleValue
            default: return nil
            }
        }
        if value == nil { return [] }
        if let arr = value as? [Any] {
            return arr.compactMap { toDouble($0) }
        }
        if let d = toDouble(value) {
            return [d]
        }
        return []
    }

    /**
     * The interface is different from queryComponents,
     * which is convenient for inner usage.
     *
     * @usage
     * let result = findComponents(
     *     {mainType: 'dataZoom', query: {dataZoomId: 'abc'}}
     * );
     * let result = findComponents(
     *     {mainType: 'series', subType: 'pie', query: {seriesName: 'uio'}}
     * );
     * let result = findComponents(
     *     {mainType: 'series',
     *     filter: function (model, index) {...}}
     * );
     * // result like [component0, component1, ...]
     */
    open func findComponents(_ condition: QueryConditionKindA) -> [ComponentModel] {
        let query = condition.query
        let mainType = condition.mainType

        let queryCond = getQueryCond(query)
        let result: [ComponentModel] = queryCond != nil
            ? self.queryComponents(queryCond!)
            // Retrieve all non-empty components.
            : util.filter(self._componentsMap.get(mainType), { cmpt, _ in cmpt != nil }).map { $0! }

        return doFilter(filterBySubType(result, condition))

        func getQueryCond(_ q: [String: Any]?) -> QueryConditionKindB? {
            let indexAttr = (mainType ?? "") + "Index"
            let idAttr = (mainType ?? "") + "Id"
            let nameAttr = (mainType ?? "") + "Name"
            if let q = q, (q[indexAttr] != nil || q[idAttr] != nil || q[nameAttr] != nil) {
                return QueryConditionKindB(
                    mainType: mainType ?? "",
                    // subType will be filtered finally.
                    index: q[indexAttr],
                    id: q[idAttr],
                    name: q[nameAttr]
                )
            }
            return nil
        }

        func doFilter(_ res: [ComponentModel]) -> [ComponentModel] {
            if let filter = condition.filter {
                return util.filter(res, { cmpt, _ in filter(cmpt) })
            }
            return res
        }
    }

    /**
     * Travel components (before filtered).
     * (See upstream for the full @usage doc block on the three overloads.)
     */
    // upstream overload (1): eachComponent(cb: EachComponentAllCallback, context?)
    open func eachComponent(_ cb: EachComponentAllCallback, _ context: Any? = nil) {
        let componentsMap = self._componentsMap!
        // PORT-NOTE: `context` (upstream `cb.call(ctxForAll, ...)`) is dropped — Swift closures capture.
        componentsMap.each { cmpts, componentType in
            var i = 0
            while i < cmpts.count {
                let cmpt = cmpts[i]
                if let cmpt = cmpt {
                    cb(componentType, cmpt, cmpt.componentIndex)
                }
                i += 1
            }
        }
    }

    // upstream overload (2): eachComponent(mainType: string, cb: EachComponentInMainTypeCallback, context?)
    open func eachComponent(_ mainType: String, _ cb: EachComponentInMainTypeCallback, _ context: Any? = nil) {
        let cmpts = self._componentsMap.get(mainType)
        var i = 0
        while let cmpts = cmpts, i < cmpts.count {
            let cmpt = cmpts[i]
            if let cmpt = cmpt {
                cb(cmpt, cmpt.componentIndex)
            }
            i += 1
        }
    }

    // upstream overload (3): eachComponent(mainType: QueryConditionKindA, cb: EachComponentInMainTypeCallback, context?)
    open func eachComponent(_ mainType: QueryConditionKindA, _ cb: EachComponentInMainTypeCallback, _ context: Any? = nil) {
        let cmpts = self.findComponents(mainType)
        var i = 0
        while i < cmpts.count {
            let cmpt = cmpts[i]
            cb(cmpt, cmpt.componentIndex)
            i += 1
        }
    }

    /**
     * Get series list before filtered by name.
     */
    open func getSeriesByName(_ name: OptionName) -> [SeriesModel] {
        let nameStr = model.convertOptionIdName(name, nil)
        let arr = self._componentsMap.get("series") ?? []
        return util.filter(arr, { oneSeries, _ in
            oneSeries != nil && nameStr != nil && (oneSeries as? SeriesModel)?.name == nameStr
        }).map { $0 as! SeriesModel }
    }

    /**
     * Get series list before filtered by index.
     */
    // upstream returns `SeriesModel` (may be undefined at runtime) -> `SeriesModel?`.
    open func getSeriesByIndex(_ seriesIndex: Double) -> SeriesModel? {
        let arr = self._componentsMap.get("series") ?? []
        let i = Int(seriesIndex)
        guard i >= 0 && i < arr.count else { return nil }
        return arr[i] as? SeriesModel
    }

    /**
     * Get series list before filtered by type.
     * FIXME: rename to getRawSeriesByType?
     */
    open func getSeriesByType(_ subType: ComponentSubType) -> [SeriesModel] {
        let arr = self._componentsMap.get("series") ?? []
        return util.filter(arr, { oneSeries, _ in
            oneSeries != nil && (oneSeries as? SeriesModel)?.subType == subType
        }).map { $0 as! SeriesModel }
    }

    /**
     * Get all series before filtered.
     */
    open func getSeries() -> [SeriesModel] {
        let arr = self._componentsMap.get("series") ?? []
        return util.filter(arr, { oneSeries, _ in oneSeries != nil }).map { $0 as! SeriesModel }
    }

    /**
     * Count series before filtered.
     */
    open func getSeriesCount() -> Double {
        return self._componentsCount.get("series") ?? 0
    }

    // upstream inlines `this._componentsMap.get('series')[rawSeriesIndex] as SeriesModel` in each
    //   series iterator. Extracted here to a helper. POTENTIAL-BUG: force-cast/force-unwrap mirror the
    //   upstream unchecked `as SeriesModel` (indices in `_seriesIndices` are always valid series);
    //   SIGTRAPs if an index is stale/out-of-range or the component is not a SeriesModel.
    private func rawSeries(_ rawIndex: Double) -> SeriesModel {
        return self._componentsMap.get("series")![Int(rawIndex)]! as! SeriesModel
    }

    /**
     * After filtering, series may be different
     * from raw series.
     */
    open func eachSeries(_ cb: (SeriesModel, Double) -> Void, _ context: Any? = nil) {
        assertSeriesInitialized(self)
        util.each(self._seriesIndices) { rawSeriesIndex, _ in
            let series = rawSeries(rawSeriesIndex)
            cb(series, rawSeriesIndex)
        }
    }

    /**
     * Iterate raw series before filtered.
     */
    open func eachRawSeries(_ cb: (SeriesModel, Double) -> Void, _ context: Any? = nil) {
        util.each(self._componentsMap.get("series")) { series, _ in
            if let series = series as? SeriesModel {
                cb(series, series.componentIndex)
            }
        }
    }

    /**
     * After filtering, series may be different.
     * from raw series.
     */
    open func eachSeriesByType(_ subType: ComponentSubType, _ cb: (SeriesModel, Double) -> Void, _ context: Any? = nil) {
        assertSeriesInitialized(self)
        util.each(self._seriesIndices) { rawSeriesIndex, _ in
            let series = rawSeries(rawSeriesIndex)
            if series.subType == subType {
                cb(series, rawSeriesIndex)
            }
        }
    }

    /**
     * Iterate raw series before filtered of given type.
     */
    open func eachRawSeriesByType(_ subType: ComponentSubType, _ cb: (SeriesModel, Double) -> Void, _ context: Any? = nil) {
        util.each(self.getSeriesByType(subType)) { series, _ in
            cb(series, series.componentIndex)
        }
    }

    /**
     * It means "filtered out".
     */
    open func isSeriesFiltered(_ seriesModel: SeriesModel) -> Bool {
        assertSeriesInitialized(self)
        return self._seriesIndicesMap.get(seriesModel.componentIndex) == nil
    }

    open func getCurrentSeriesIndices() -> [Double] {
        return (self._seriesIndices ?? []) // .slice()
    }

    open func filterSeries(_ cb: (SeriesModel, Double) -> Bool, _ context: Any? = nil) {
        assertSeriesInitialized(self)

        var newSeriesIndices: [Double] = []
        util.each(self._seriesIndices) { seriesRawIdx, _ in
            let series = rawSeries(seriesRawIdx)
            if cb(series, seriesRawIdx) {
                newSeriesIndices.append(seriesRawIdx)
            }
        }

        self._seriesIndices = newSeriesIndices
        // createHashMap<number, number>(newSeriesIndices)
        let map: HashMap<Double> = createHashMap()
        for idx in newSeriesIndices { map.set(idx, idx) }
        self._seriesIndicesMap = map
    }

    // upstream: restoreData(payload?: Payload): void
    //
    // PORT-NOTE: upstream is a single method with an optional `payload`, and it overrides
    //   `Model.restoreData()`. Swift can not both override the no-param base and add an optional
    //   param (that would be an ambiguous overload against the inherited no-arg method), so it is
    //   split into an `override` no-arg entry and a payload entry, both forwarding to `_restoreData`.
    open override func restoreData() {
        _restoreData(nil)
    }
    open func restoreData(_ payload: Payload) {
        _restoreData(payload)
    }

    private func _restoreData(_ payload: Payload?) {
        reCreateSeriesIndices(self)

        let componentsMap = self._componentsMap!
        var componentTypes: [String] = []
        componentsMap.each { components, componentType in
            if ComponentModel.hasClass(componentType) {
                componentTypes.append(componentType)
            }
        }

        try? ComponentModel.topologicalTravel(
            componentTypes,
            ComponentModel.getAllClassMainTypes(),
            { componentType, _ in
                util.each(componentsMap.get(componentType)) { component, _ in
                    if let component = component,
                       (componentType != "series"
                        || !isNotTargetSeries(component as! SeriesModel, payload)) {
                        component.restoreData()
                    }
                }
            },
            nil
        )
    }

    // upstream: private static internalField = (function () { reCreateSeriesIndices = ...; assertSeriesInitialized = ...; initBase = ...; })();
    //   The IIFE assigns the three module-level internal methods. Swift has no module-load execution,
    //   so the three functions are ported directly as file-private free funcs at the bottom of this
    //   file (accessing the `fileprivate` GlobalModel members).

    // MARK: - PaletteMixin conformance (`Pick<Model, 'get'>` requirement)
    // upstream: `mixin(GlobalModel, PaletteMixin)`. Dispatches to the typed `Model.get` overloads,
    //   mirroring SeriesModel's conformance.
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


/**
 * Either `mainType` or `query` should be provided.
 * A valid `query` (containing either xxxId, xxxName or xxxIndex) takes precedence
 * if `query` and `mainType` are both provided.
 * `query` is like `{xxxIndex, xxxId, xxxName}`,
 *      where xxx is mainType.
 *      If query attribute is null/undefined or has no index/id/name,
 *      do not filtering by query conditions, which is convenient for
 *      no-payload situations or when target of action is global.
 * `subType` and `filter` provide further filtering to the above result.
 * `subType` is determined by `hasOwnProperty`.
 *
 * @see {makeQueryConditionKindA}
 */
public struct QueryConditionKindA {
    // upstream: query?: { [k: string]: number | number[] | string | string[] }
    public var query: [String: Any]?
    public var mainType: ComponentMainType?
    public var subType: ComponentSubType?
    public var filter: ((ComponentModel) -> Bool)?
    public init(
        mainType: ComponentMainType? = nil,
        query: [String: Any]? = nil,
        subType: ComponentSubType? = nil,
        filter: ((ComponentModel) -> Bool)? = nil
    ) {
        self.mainType = mainType
        self.query = query
        self.subType = subType
        self.filter = filter
    }
}

/**
 * If none of index and id and name used, return all components with mainType.
 * @param condition.mainType
 * @param condition.subType If ignore, only query by mainType
 * @param condition.index Either input index or id or name.
 * @param condition.id Either input index or id or name.
 * @param condition.name Either input index or id or name.
 */
public struct QueryConditionKindB {
    public var mainType: ComponentMainType
    public var subType: ComponentSubType?
    public var index: Any?  // number | number[]
    public var id: Any?     // OptionId | OptionId[]
    public var name: Any?   // OptionName | OptionName[]
    public init(
        mainType: ComponentMainType,
        subType: ComponentSubType? = nil,
        index: Any? = nil,
        id: Any? = nil,
        name: Any? = nil
    ) {
        self.mainType = mainType
        self.subType = subType
        self.index = index
        self.id = id
        self.name = name
    }
}
public typealias EachComponentAllCallback = (_ mainType: String, _ model: ComponentModel, _ componentIndex: Double) -> Void
public typealias EachComponentInMainTypeCallback = (_ model: ComponentModel, _ componentIndex: Double) -> Void


// upstream returns `undefined` (falsy) when `!payload`; Swift models that as `false`.
private func isNotTargetSeries(_ seriesModel: SeriesModel, _ payload: Payload?) -> Bool {
    if let payload = payload {
        let index = payload.other["seriesIndex"]
        let id = payload.other["seriesId"]
        let name = payload.other["seriesName"]
        // upstream strict `!==`; ids/names compared via `convertOptionIdName` (string coercion).
        let indexMismatch = index != nil && seriesModel.componentIndex != ((index as? Double) ?? Double.nan)
        let idMismatch = id != nil && seriesModel.id != model.convertOptionIdName(id, nil)
        let nameMismatch = name != nil && seriesModel.name != model.convertOptionIdName(name, nil)
        return indexMismatch || idMismatch || nameMismatch
    }
    return false
}

private func mergeTheme(_ option: inout ECUnitOption, _ theme: ThemeOption) {
    // PENDING
    // NOT use `colorLayer` in theme if option has `color`
    let notMergeColorLayer = !isNullish(option["color"]) && isNullish(option["colorLayer"])

    for (name, themeItem) in theme {
        if (name == "colorLayer" && notMergeColorLayer)
            || (name == "color" && !isNullish(option["color"])) {
            continue
        }

        // If it is component model mainType, the model handles that merge later.
        // otherwise, merge them here.
        if !ComponentModel.hasClass(name) {
            if util.isObject(themeItem) { // typeof themeItem === 'object'
                // option[name] = !option[name] ? clone(themeItem) : merge(option[name], themeItem, false);
                if isNullish(option[name]) {
                    option[name] = util.clone(themeItem) as Any
                }
                else if var tgt = option[name] as? [String: Any], let src = themeItem as? [String: Any] {
                    util.merge(&tgt, src, false)
                    option[name] = tgt
                }
                else {
                    // PORT-NOTE: array / non-dict object merge (util.merge handles only dicts) —
                    //   keep existing value. With overwrite == false and an existing value present,
                    //   upstream merge leaves it unchanged too, so this is semantically equivalent.
                }
            }
            else {
                if isNullish(option[name]) {
                    option[name] = themeItem
                }
            }
        }
    }
}

// upstream: queryByIdOrName<T extends { id?, name? }>(attr, idOrName, cmpts)
// PORT-NOTE: the generic `T` is specialized to `ComponentModel` (the only caller passes the components
//   map). `attr` is the caseless local enum below rather than the `'id' | 'name'` string-literal type.
private enum IdOrNameAttr { case id, name }
private func queryByIdOrName(_ attr: IdOrNameAttr, _ idOrName: Any?, _ cmpts: [ComponentModel?]) -> [ComponentModel] {
    func attrOf(_ c: ComponentModel) -> String { attr == .id ? c.id : c.name }
    // Here is a break from echarts4: string and number are
    // treated as equal.
    if util.isArray(idOrName) {
        let keyMap: HashMap<Bool> = createHashMap()
        util.each(idOrName as? [Any]) { idOrNameItem, _ in
            if !isNullish(idOrNameItem) {
                let idName = model.convertOptionIdName(idOrNameItem, nil)
                if idName != nil { keyMap.set(idOrNameItem, true) }
            }
        }
        return util.filter(cmpts, { cmpt, _ in
            cmpt != nil && (keyMap.get(attrOf(cmpt!)) ?? false)
        }).map { $0! }
    }
    else {
        let idName = model.convertOptionIdName(idOrName, nil)
        return util.filter(cmpts, { cmpt, _ in
            cmpt != nil && idName != nil && attrOf(cmpt!) == idName
        }).map { $0! }
    }
}

// upstream: filterBySubType(components, condition: QueryConditionKindA | QueryConditionKindB)
//   The union is modeled by the `ComponentQueryCondition` protocol (both condition kinds conform).
private protocol ComponentQueryCondition {
    var subType: ComponentSubType? { get }
    // `hasOwnProperty('subType')` — PORT-NOTE: value structs collapse absent ≡ explicit-nil, so
    //   presence is modeled as `subType != nil` (semantically equivalent here — a condition never
    //   sets subType to an explicit null).
    var hasSubType: Bool { get }
}
extension QueryConditionKindA: ComponentQueryCondition {
    var hasSubType: Bool { self.subType != nil }
}
extension QueryConditionKindB: ComponentQueryCondition {
    var hasSubType: Bool { self.subType != nil }
}
private func filterBySubType(_ components: [ComponentModel], _ condition: ComponentQueryCondition) -> [ComponentModel] {
    // Using hasOwnProperty for restrict. Consider
    // subType is undefined in user payload.
    return condition.hasSubType
        ? util.filter(components, { cmpt, _ in cmpt.subType == condition.subType })
        : components
}

private func normalizeSetOptionInput(_ opts: GlobalModelSetOptionOpts?) -> InnerSetOptionOpts {
    let replaceMergeMainTypeMap: HashMap<Bool> = createHashMap()
    if let opts = opts {
        let arr: [ComponentMainType] = model.normalizeToArray(opts.replaceMerge)
        util.each(arr) { mainType, _ in
            if __DEV__ {
                util.assert(
                    ComponentModel.hasClass(mainType),
                    "\"" + mainType + "\" is not valid component main type in \"replaceMerge\""
                )
            }
            replaceMergeMainTypeMap.set(mainType, true)
        }
    }
    return InnerSetOptionOpts(replaceMergeMainTypeMap: replaceMergeMainTypeMap)
}

// upstream: interface GlobalModel extends PaletteMixin<ECUnitOption> {}
//           mixin(GlobalModel, PaletteMixin);
//   Ported as the `PaletteMixin` conformance on the class declaration above + the `get` witness.

// export default GlobalModel;  -> `open class GlobalModel` above.


// ============================================================================
// PORT-only helpers (not upstream symbols).
// ============================================================================

// `x == null` (JS null/undefined). NSNull is used to retain explicit-null values in the [String: Any]
// option bag (see globalDefault.swift), so it counts as nullish here.
private func isNullish(_ v: Any?) -> Bool {
    return v == nil || v is NSNull
}

// Reads id/name off a dynamic option bag so it can be passed to `model.isComponentIdInternal`
// (which consumes a `MappingComparable`). Not an upstream symbol.
private func optionBagToComparable(_ any: Any?) -> ComponentOption {
    var co = ComponentOption()
    if let d = any as? [String: Any] {
        co.id = d["id"]
        co.name = d["name"]
    }
    return co
}

// upstream: `modelUtil.normalizeToArray(newOption[mainType])` yields the raw `ComponentOption[]`.
//   Because upstream `ComponentOption` IS the dynamic option object, the same objects flow into
//   `mappingToExists` and then into `new ComponentModelClass(newCmptOption, ...)`. The Swift
//   `ComponentOption` is a lossy typed struct, so each dynamic bag is projected into a
//   `ComponentOption` carrying the full bag in `.rawOption`. Not an upstream symbol (the projection
//   bridges the dynamic tree and the typed mapping struct).
private func normalizeToComponentOptionList(_ value: Any?) -> [ComponentOption] {
    // value instanceof Array
    if let arr = value as? [Any] {
        return arr.compactMap { optionBagToComponentOption($0) }
    }
    // value == null
    if value == nil || value is NSNull {
        return []
    }
    // [value]
    if let one = optionBagToComponentOption(value) {
        return [one]
    }
    return []
}

// Projects one dynamic option bag (`[String: Any]`) into a `ComponentOption`, copying the typed
// fields read by the mapping engine (`id`/`name`/`type`/`mainType`/`z`/`zlevel`) and retaining the
// full bag in `.rawOption`. Returns nil when the value is not an option object. Not an upstream
// symbol (see `normalizeToComponentOptionList`).
private func optionBagToComponentOption(_ any: Any?) -> ComponentOption? {
    guard let d = any as? [String: Any] else {
        return nil
    }
    var co = ComponentOption()
    co.mainType = d["mainType"] as? String
    co.type = d["type"] as? String
    co.id = d["id"]
    co.name = d["name"]
    co.z = d["z"] as? Double
    co.zlevel = d["zlevel"] as? Double
    co.rawOption = d
    return co
}

// `componentModel.constructor === ComponentModelClass` — metatype identity between the existing model
// and the registered class. Not an upstream symbol (JS `===` on constructors).
private func sameConstructor(_ model: ComponentModel, _ ctor: Constructor) -> Bool {
    // metatypes are always AnyObject.Type — compare identity directly (inlined to avoid a named
    // `any AnyObject.Type` constant).
    return ObjectIdentifier(Swift.type(of: model) as AnyObject.Type) == ObjectIdentifier(ctor as AnyObject.Type)
}

// upstream passes `ComponentModel[]` where `MappingExistingItem[]` is expected (structural typing).
// The ported `MappingExistingItem` / `HasSubType` protocols require `id/name: OptionId?` and
// `subType: ComponentSubType?`, which ComponentModel's non-optional `String` stored properties can not
// satisfy as covariant witnesses — so wrap each model.
private final class ExistingComponentItem: MappingExistingItem, HasSubType {
    let cmpt: ComponentModel
    init(_ cmpt: ComponentModel) { self.cmpt = cmpt }
    var id: OptionId? { cmpt.id }
    var name: OptionName? { cmpt.name }
    var subType: ComponentSubType? { cmpt.subType }
}

// upstream passes `ComponentModel as ComponentModelConstructor` to `setComponentTypeToKeyInfo`.
// The ported `ComponentModelConstructor` protocol requires a *non-optional* `determineSubType`, which
// `ComponentModel.determineSubType` (-> String?) does not satisfy, so ComponentModel can not conform
// directly. This tiny adapter forwards to it (empty string when the registry returns nil).
private final class GlobalComponentModelConstructor: ComponentModelConstructor {
    static func determineSubType(_ mainType: ComponentMainType, _ option: ComponentOption) -> ComponentSubType {
        return ComponentModel.determineSubType(mainType, option) ?? ""
    }
}

// ---- upstream `internalField` IIFE-assigned module methods ----

private func reCreateSeriesIndices(_ ecModel: GlobalModel) {
    // const seriesIndices: number[] = ecModel._seriesIndices = [];
    var seriesIndices: [Double] = []
    util.each(ecModel._componentsMap.get("series")) { series, _ in
        // series may have been removed by `replaceMerge`.
        if let series = series {
            seriesIndices.append(series.componentIndex)
        }
    }
    ecModel._seriesIndices = seriesIndices
    // ecModel._seriesIndicesMap = createHashMap<number, number>(seriesIndices);
    let map: HashMap<Double> = createHashMap()
    for idx in seriesIndices { map.set(idx, idx) }
    ecModel._seriesIndicesMap = map
}

private func assertSeriesInitialized(_ ecModel: GlobalModel) {
    // Components that use _seriesIndices should depends on series component,
    // which make sure that their initialization is after series.
    if __DEV__ {
        if ecModel._seriesIndices == nil {
            // upstream: throw new Error('Option should contains series.');
            // PORT-NOTE: ported as an error log rather than a thrown error, to keep the callers'
            //   non-throwing signatures (eachSeries/filterSeries/isSeriesFiltered).
            log.error("Option should contains series.")
        }
    }
}

private func initBase(_ ecModel: GlobalModel, _ baseOptionInput: ECUnitOption) {
    var baseOption = baseOptionInput
    // Using OPTION_INNER_KEY to mark that this option cannot be used outside,
    // i.e. `chart.setOption(chart.getModel().option);` is forbidden.
    var option: [String: Any] = [:] // {} as ECUnitOption
    option[OPTION_INNER_KEY] = OPTION_INNER_VALUE
    ecModel.option = option

    // Init with series: [], in case of calling findSeries method
    // before series initialized.
    let componentsMap: HashMap<[ComponentModel?]> = createHashMap()
    componentsMap.set("series", []) // createHashMap({series: []})
    ecModel._componentsMap = componentsMap
    ecModel._componentsCount = createHashMap()

    // If user spefied `option.aria`, aria will be enable. This detection should be
    // performed before theme and globalDefault merge.
    let airaOption = baseOption["aria"]
    if var airaObj = airaOption as? [String: Any] { // isObject(airaOption)
        if airaObj["enabled"] == nil { // airaOption.enabled == null
            airaObj["enabled"] = true
            baseOption["aria"] = airaObj
        }
    }

    mergeTheme(&baseOption, (ecModel._theme.option as? ThemeOption) ?? [:])

    // TODO Needs clone when merging to the unexisted property
    util.merge(&baseOption, globalDefault.option, false)

    ecModel._mergeOption(baseOption, nil)
}
