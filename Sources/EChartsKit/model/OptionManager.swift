// Ported from echarts/src/model/OptionManager.ts — keep in sync with upstream
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
import ZRenderKit  // upstream: each, clone, map, isTypedArray, setAsPrimitive, isArray, isObject from 'zrender/src/core/util'

// upstream imports (translated against the conventional public API of sibling files):
//   import ExtensionAPI from '../core/ExtensionAPI';                 -> ExtensionAPI (util/types.swift placeholder protocol; core/ExtensionAPI not ported yet)
//   import {
//       OptionPreprocessor, MediaQuery, ECUnitOption, MediaUnit, ECBasicOption, SeriesOption
//   } from '../util/types';                                         -> OptionPreprocessor / MediaQuery / ECUnitOption / MediaUnit / ECBasicOption / SeriesOption (EChartsKit util/types.swift)
//   import GlobalModel, { InnerSetOptionOpts } from './Global';     -> GlobalModel (util/types.swift placeholder; real type lands this phase). InnerSetOptionOpts -> `Any?` (see setOption PORT-NOTE).
//   import { normalizeToArray } from '../util/model';               -> model.normalizeToArray (EChartsKit util/model.swift)
//   import { each, clone, map, isTypedArray, setAsPrimitive, isArray, isObject } from 'zrender/src/core/util'; -> util.* (ZRenderKit)
//   import { DatasetOption } from '../component/dataset/install';   -> dynamic bag (dataset option) — component/dataset not ported; accessed via the `[String: Any]` bag.
//   import { error } from '../util/log';                            -> log.error (EChartsKit util/log.swift)

private let QUERY_REG = try! NSRegularExpression(pattern: "^(min|max)?(.+)$")

// Key: mainType
// type FakeComponentsMap = HashMap<(MappingExistingItem & { subType: string })[]>;

// PORT-NOTE: `ParsedRawOption` is an upstream `interface` used as a plain data bag (no identity);
//   ported as a Swift `struct` (CONVENTIONS §2). `mediaDefault` is optional (upstream leaves it
//   `undefined` when there is no default media unit).
struct ParsedRawOption {
    var baseOption: ECUnitOption
    var timelineOptions: [ECUnitOption]
    var mediaDefault: MediaUnit?
    var mediaList: [MediaUnit]
}

/**
 * TERM EXPLANATIONS:
 * See `ECOption` and `ECUnitOption` in `src/util/types.ts`.
 */
// PORT-NOTE: upstream `class OptionManager` (not subclassed / `export default`) -> `final class`
//   per CONVENTIONS §2 (reference semantics).
final class OptionManager {

    private var _api: ExtensionAPI

    private var _timelineOptions: [ECUnitOption] = []

    private var _mediaList: [MediaUnit] = []

    private var _mediaDefault: MediaUnit?

    /**
     * -1, means default.
     * empty means no media.
     */
    private var _currentMediaIndices: [Int] = []

    private var _optionBackup: ParsedRawOption?

    // private _fakeCmptsMap: FakeComponentsMap;

    private var _newBaseOption: ECUnitOption?

    // timeline.notMerge is not supported in ec3. Firstly there is rearly
    // case that notMerge is needed. Secondly supporting 'notMerge' requires
    // rawOption cloned and backuped when timeline changed, which does no
    // good to performance. What's more, that both timeline and setOption
    // method supply 'notMerge' brings complex and some problems.
    // Consider this case:
    // (step1) chart.setOption({timeline: {notMerge: false}, ...}, false);
    // (step2) chart.setOption({timeline: {notMerge: true}, ...}, false);

    init(_ api: ExtensionAPI) {
        self._api = api
    }

    // PORT-NOTE: upstream `rawOption: ECBasicOption` (structurally an `ECUnitOption` with optional
    //   `baseOption`/`timeline`/`options`/`media` keys). Collapsed to the dynamic `ECUnitOption`
    //   = `[String: Any]` bag per CONVENTIONS: the whole file treats `rawOption` dynamically
    //   (`rawOption.baseOption`, `baseOption = rawOption`, `clone(rawOption)`), which the typed
    //   `ECBasicOption` struct cannot support. Reserved keys are accessed by string.
    // PORT-NOTE: upstream `opt: InnerSetOptionOpts` (from model/Global). It is read only by the
    //   commented-out `mergeToBackupOption`, so it is unused by the active code; typed `Any?` to
    //   avoid a fragile cross-file dependency until model/Global lands.
    func setOption(
        _ rawOption: ECUnitOption?,
        _ optionPreprocessorFuncs: [OptionPreprocessor],
        _ opt: Any?
    ) {
        var rawOption = rawOption
        _ = opt

        if let ro = rawOption {  // upstream: if (rawOption)
            // That set dat primitive is dangerous if user reuse the data when setOption again.
            let seriesList: [Any] = model.normalizeToArray(ro["series"])
            util.each(seriesList) { series, _ in
                // series && series.data && isTypedArray(series.data) && setAsPrimitive(series.data);
                if let seriesDict = series as? [String: Any],
                   let data = seriesDict["data"],
                   util.isTypedArray(data) {
                    // PORT-NOTE (deferred): requires `util.setAsPrimitive(series.data)` — JS hidden-key
                    //   tagging (util.swift:474), not ported. The typed-array-reuse guard is inert until
                    //   it lands.
                    _ = data
                }
            }
            let datasetList: [Any] = model.normalizeToArray(ro["dataset"])
            util.each(datasetList) { dataset, _ in
                // dataset && dataset.source && isTypedArray(dataset.source) && setAsPrimitive(dataset.source);
                if let datasetDict = dataset as? [String: Any],
                   let source = datasetDict["source"],
                   util.isTypedArray(source) {
                    // PORT-NOTE (deferred): requires `util.setAsPrimitive(dataset.source)` — see the series note above.
                    _ = source
                }
            }
        }

        // Caution: some series modify option data, if do not clone,
        // it should ensure that the repeat modify correctly
        // (create a new object when modify itself).
        rawOption = util.clone(rawOption)

        // FIXME
        // If some property is set in timeline options or media option but
        // not set in baseOption, a warning should be given.

        let optionBackup = self._optionBackup
        let newParsedOption = parseRawOption(
            rawOption, optionPreprocessorFuncs, optionBackup == nil
        )
        self._newBaseOption = newParsedOption.baseOption

        // For setOption at second time (using merge mode);
        if var optionBackup = optionBackup {
            // FIXME
            // the restore merge solution is essentially incorrect.
            // the mapping can not be 100% consistent with ecModel, which probably brings
            // potential bug!

            // The first merge is delayed, because in most cases, users do not call `setOption` twice.
            // let fakeCmptsMap = this._fakeCmptsMap;
            // if (!fakeCmptsMap) {
            //     fakeCmptsMap = this._fakeCmptsMap = createHashMap();
            //     mergeToBackupOption(fakeCmptsMap, null, optionBackup.baseOption, null);
            // }

            // mergeToBackupOption(
            //     fakeCmptsMap, optionBackup.baseOption, newParsedOption.baseOption, opt
            // );

            // For simplicity, timeline options and media options do not support merge,
            // that is, if you `setOption` twice and both has timeline options, the latter
            // timeline options will not be merged to the former, but just substitute them.
            //
            // PORT-NOTE: upstream mutates the `_optionBackup` object in place (JS reference).
            //   `ParsedRawOption` is a value-type struct, so mutate a local copy and write it back.
            if !newParsedOption.timelineOptions.isEmpty {
                optionBackup.timelineOptions = newParsedOption.timelineOptions
            }
            if !newParsedOption.mediaList.isEmpty {
                optionBackup.mediaList = newParsedOption.mediaList
            }
            if newParsedOption.mediaDefault != nil {
                optionBackup.mediaDefault = newParsedOption.mediaDefault
            }
            self._optionBackup = optionBackup
        }
        else {
            self._optionBackup = newParsedOption
        }
    }

    func mountOption(_ isRecreate: Bool) -> ECUnitOption {
        let optionBackup = self._optionBackup!

        self._timelineOptions = optionBackup.timelineOptions
        self._mediaList = optionBackup.mediaList
        self._mediaDefault = optionBackup.mediaDefault
        self._currentMediaIndices = []

        return util.clone(isRecreate
            // this._optionBackup.baseOption, which is created at the first `setOption`
            // called, and is merged into every new option by inner method `mergeToBackupOption`
            // each time `setOption` called, can be only used in `isRecreate`, because
            // its reliability is under suspicion. In other cases option merge is
            // performed by `model.mergeOption`.
            ? optionBackup.baseOption : self._newBaseOption!
        )
    }

    func getTimelineOption(_ ecModel: GlobalModel) -> ECUnitOption? {
        var option: ECUnitOption?
        let timelineOptions = self._timelineOptions

        if !timelineOptions.isEmpty {  // upstream: if (timelineOptions.length)
            // getTimelineOption can only be called after ecModel inited,
            // so we can get currentIndex from timelineModel.
            let timelineModel = ecModel.getComponent("timeline")
            if let timelineModel = timelineModel {
                // upstream: option = clone(timelineOptions[(timelineModel as TimelineModel).getCurrentIndex()]);
                //   `TimelineModel` (component/timeline) is now ported; read the real current index.
                var currentIndex = (timelineModel as? TimelineModel)?.getCurrentIndex() ?? 0
                // upstream `timelineOptions[currentIndex]` is `undefined` when out of range, and
                //   `clone(undefined)` yields `undefined` (→ nil here). Guard the Swift index access;
                //   an out-of-range currentIndex just merges nothing (matches upstream's no-op merge).
                if currentIndex < 0 || currentIndex >= timelineOptions.count {
                    currentIndex = -1
                }
                if currentIndex >= 0 {
                    option = util.clone(
                        timelineOptions[currentIndex]
                    )
                }
            }
        }

        return option
    }

    func getMediaOption(_ ecModel: GlobalModel) -> [ECUnitOption] {
        // const ecWidth = this._api.getWidth();
        // const ecHeight = this._api.getHeight();
        // upstream: const ecWidth = this._api.getWidth(); const ecHeight = this._api.getHeight();
        //   `core/ExtensionAPI` now provides `getWidth()`/`getHeight()` (forwarded to the EC instance),
        //   so viewport-driven media resolution reads the real size.
        _ = ecModel  // upstream `getMediaOption(ecModel)` never reads `ecModel`.
        let ecWidth: Double = self._api.getWidth()
        let ecHeight: Double = self._api.getHeight()
        let mediaList = self._mediaList
        let mediaDefault = self._mediaDefault
        var indices: [Int] = []
        var result: [ECUnitOption] = []

        // No media defined.
        if mediaList.isEmpty && mediaDefault == nil {
            return result
        }

        // Multi media may be applied, the latter defined media has higher priority.
        var i = 0
        let len = mediaList.count
        while i < len {
            // mediaList entries always carry a `query` (only queried units are pushed below).
            if applyMediaQuery(mediaList[i].query!, ecWidth, ecHeight) {
                indices.append(i)
            }
            i += 1
        }

        // FIXME
        // Whether mediaDefault should force users to provide? Otherwise
        // the change by media query can not be recorvered.
        if indices.isEmpty && mediaDefault != nil {
            indices = [-1]
        }

        if !indices.isEmpty && !indicesEquals(indices, self._currentMediaIndices) {
            result = util.map(indices) { index, _ in
                return util.clone(
                    index == -1 ? mediaDefault!.option : mediaList[index].option
                )
            }
        }
        // Otherwise return nothing.

        self._currentMediaIndices = indices

        return result
    }

}

/**
 * [RAW_OPTION_PATTERNS]
 * (Note: "series: []" represents all other props in `ECUnitOption`)
 *
 * (1) No prop "baseOption" declared:
 * Root option is used as "baseOption" (except prop "options" and "media").
 * ```js
 * option = {
 *     series: [],
 *     timeline: {},
 *     options: [],
 * };
 * option = {
 *     series: [],
 *     media: {},
 * };
 * option = {
 *     series: [],
 *     timeline: {},
 *     options: [],
 *     media: {},
 * }
 * ```
 *
 * (2) Prop "baseOption" declared:
 * If "baseOption" declared, `ECUnitOption` props can only be declared
 * inside "baseOption" except prop "timeline" (compat ec2).
 * ```js
 * option = {
 *     baseOption: {
 *         timeline: {},
 *         series: [],
 *     },
 *     options: []
 * };
 * option = {
 *     baseOption: {
 *         series: [],
 *     },
 *     media: []
 * };
 * option = {
 *     baseOption: {
 *         timeline: {},
 *         series: [],
 *     },
 *     options: []
 *     media: []
 * };
 * option = {
 *     // ec3 compat ec2: allow (only) `timeline` declared
 *     // outside baseOption. Keep this setting for compat.
 *     timeline: {},
 *     baseOption: {
 *         series: [],
 *     },
 *     options: [],
 *     media: []
 * };
 * ```
 */
private func parseRawOption(
    // `rawOption` May be modified
    _ rawOptionIn: ECUnitOption?,
    _ optionPreprocessorFuncs: [OptionPreprocessor],
    _ isNew: Bool
) -> ParsedRawOption {
    var rawOption: ECUnitOption = rawOptionIn ?? [:]
    var mediaList: [MediaUnit] = []
    var mediaDefault: MediaUnit?
    var baseOption: ECUnitOption

    let declaredBaseOption = rawOption["baseOption"] as? ECUnitOption
    // Compatible with ec2, [RAW_OPTION_PATTERNS] above.
    let timelineOnRoot = rawOption["timeline"]
    let timelineOptionsOnRoot = rawOption["options"] as? [ECUnitOption]
    let mediaOnRoot = rawOption["media"]
    let hasMedia = rawOption["media"] != nil
    let hasTimeline = (
        timelineOptionsOnRoot != nil
            || timelineOnRoot != nil
            || (declaredBaseOption != nil && declaredBaseOption!["timeline"] != nil)
    )

    if let declaredBaseOption = declaredBaseOption {
        baseOption = declaredBaseOption
        // For merge option.
        if baseOption["timeline"] == nil {  // upstream: if (!baseOption.timeline)
            // upstream: baseOption.timeline = timelineOnRoot;  (setting a `nil` value removes the
            //   key in Swift, which — since we are in the `timeline == nil` branch — is equivalent
            //   to upstream setting `undefined`.)
            baseOption["timeline"] = timelineOnRoot
        }
    }
    // For convenience, enable to use the root option as the `baseOption`:
    // `{ ...normalOptionProps, media: [{ ... }, { ... }] }`
    else {
        if hasTimeline || hasMedia {
            rawOption["options"] = nil
            rawOption["media"] = nil
        }
        baseOption = rawOption
    }

    if hasMedia {
        if util.isArray(mediaOnRoot) {
            // Media entries come from the dynamic ECUnitOption bag as [[String: Any]], NOT typed
            // MediaUnit structs — `as? [MediaUnit]` was always nil, silently dropping all media
            // (PORT_STATUS §29 #0c). Build the typed MediaUnit/MediaQuery from the bag by key,
            // exactly as the timeline `options` path reads its entries.
            util.each(mediaOnRoot as? [Any]) { rawMediaAny, _ in
                guard let rawMedia = rawMediaAny as? [String: Any] else { return }
                // upstream: if (singleMedia && singleMedia.option) { ... }
                guard let opt = rawMedia["option"] as? ECUnitOption else { return }
                var singleMedia = MediaUnit(query: nil, option: opt)
                if let q = rawMedia["query"] as? [String: Any] {
                    singleMedia.query = buildMediaQuery(q)
                }
                if singleMedia.query != nil {
                    mediaList.append(singleMedia)
                }
                else if mediaDefault == nil {
                    // Use the first media default.
                    mediaDefault = singleMedia
                }
            }
        }
        else {
            if __DEV__ {
                // Real case of wrong config.
                log.error("Illegal media option. Must be an array. Like { media: [ {...}, {...} ] }")
            }
        }
    }

    doPreprocess(baseOption)
    util.each(timelineOptionsOnRoot) { option, _ in doPreprocess(option) }
    util.each(mediaList) { media, _ in doPreprocess(media.option) }

    // POTENTIAL-BUG: upstream preprocessors mutate the shared `option` object in place (JS reference).
    //   The conventional `OptionPreprocessor = (ECUnitOption, Bool) -> Void` typealias takes the
    //   option by value (`ECUnitOption` = `[String: Any]`), so mutations cannot propagate back to
    //   the stored `baseOption`/`timelineOptions`/`mediaList`. Preprocessing via THIS seam is
    //   therefore effectively a no-op until the typealias returns/mutates via `inout`. Currently
    //   inert: the built-in preprocessors run separately via `&opt` in ECharts.setOption, and no
    //   external preprocessor is registered here (echarts.registerPreprocessor is not ported).
    func doPreprocess(_ option: ECUnitOption) {
        util.each(optionPreprocessorFuncs) { preProcess, _ in
            preProcess(option, isNew)
        }
    }

    return ParsedRawOption(
        baseOption: baseOption,
        timelineOptions: timelineOptionsOnRoot ?? [],
        mediaDefault: mediaDefault,
        mediaList: mediaList
    )
}

/**
 * @see <http://www.w3.org/TR/css3-mediaqueries/#media1>
 * Support: width, height, aspectRatio
 * Can use max or min as prefix.
 */
// Build a typed MediaQuery from the dynamic `query` bag (media entries live in the [String: Any]
// option tree — see parseRawOption §29 #0c). Only the six min/max width/height/aspectRatio keys
// are meaningful to applyMediaQuery.
private func buildMediaQuery(_ d: [String: Any]) -> MediaQuery {
    var q = MediaQuery()
    q.minWidth = d["minWidth"] as? Double
    q.maxWidth = d["maxWidth"] as? Double
    q.minHeight = d["minHeight"] as? Double
    q.maxHeight = d["maxHeight"] as? Double
    q.minAspectRatio = d["minAspectRatio"] as? Double
    q.maxAspectRatio = d["maxAspectRatio"] as? Double
    return q
}

private func applyMediaQuery(_ query: MediaQuery, _ ecWidth: Double, _ ecHeight: Double) -> Bool {
    let realMap: [String: Double] = [
        "width": ecWidth,
        "height": ecHeight,
        "aspectratio": ecWidth / ecHeight // lower case for convenience.
    ]

    var applicable = true

    // upstream: each(query, function (value: number, attr) { ... })
    //   The typed `MediaQuery` struct exposes the same six keys as fields; enumerate them as
    //   (value, attr) pairs so the QUERY_REG-driven matching below stays byte-faithful. A `nil`
    //   field means the key was not provided (upstream `each` only visits own keys), so it is skipped.
    let entries: [(value: Double?, attr: String)] = [
        (query.minWidth, "minWidth"),
        (query.maxWidth, "maxWidth"),
        (query.minHeight, "minHeight"),
        (query.maxHeight, "maxHeight"),
        (query.minAspectRatio, "minAspectRatio"),
        (query.maxAspectRatio, "maxAspectRatio")
    ]
    util.each(entries) { entry, _ in
        guard let value = entry.value else {
            return
        }
        let attr = entry.attr
        let matched = matchQueryReg(attr)

        if matched == nil || matched!.0 == nil || matched!.1 == nil {
            return
        }

        let operator_ = matched!.0!
        let realAttr = matched!.1!.lowercased()

        if !compare(realMap[realAttr], value, operator_) {
            applicable = false
        }
    }

    return applicable
}

// upstream: `const matched = attr.match(QUERY_REG);` — returns (group1, group2) or nil.
private func matchQueryReg(_ attr: String) -> (String?, String?)? {
    let range = NSRange(attr.startIndex..., in: attr)
    guard let m = QUERY_REG.firstMatch(in: attr, options: [], range: range) else {
        return nil
    }
    func group(_ i: Int) -> String? {
        let r = m.range(at: i)
        guard r.location != NSNotFound, let rr = Range(r, in: attr) else {
            return nil
        }
        return String(attr[rr])
    }
    return (group(1), group(2))
}

// PORT-NOTE: upstream `real: number` — `realMap[realAttr]` may be `undefined` for an unknown attr;
//   modeled as `Double?` (a missing/`nil` `real` compares false, matching JS `undefined >= x`, etc.).
private func compare(_ real: Double?, _ expect: Double, _ operator_: String) -> Bool {
    guard let real = real else {
        return false
    }
    if operator_ == "min" {
        return real >= expect
    }
    else if operator_ == "max" {
        return real <= expect
    }
    else { // Equals
        return real == expect
    }
}

private func indicesEquals(_ indices1: [Int], _ indices2: [Int]) -> Bool {
    // indices is always order by asc and has only finite number.
    return indices1.map { String($0) }.joined(separator: ",")
        == indices2.map { String($0) }.joined(separator: ",")
}

/**
 * Consider case:
 * `chart.setOption(opt1);`
 * Then user do some interaction like dataZoom, dataView changing.
 * `chart.setOption(opt2);`
 * Then user press 'reset button' in toolbox.
 *
 * After doing that all of the interaction effects should be reset, the
 * chart should be the same as the result of invoke
 * `chart.setOption(opt1); chart.setOption(opt2);`.
 *
 * Although it is not able ensure that
 * `chart.setOption(opt1); chart.setOption(opt2);` is equivalents to
 * `chart.setOption(merge(opt1, opt2));` exactly,
 * this might be the only simple way to implement that feature.
 *
 * MEMO: We've considered some other approaches:
 * 1. Each model handles its self restoration but not uniform treatment.
 *     (Too complex in logic and error-prone)
 * 2. Use a shadow ecModel. (Performance expensive)
 *
 * FIXME: A possible solution:
 * Add a extra level of model for each component model. The inheritance chain would be:
 * ecModel <- componentModel <- componentActionModel <- dataItemModel
 * And all of the actions can only modify the `componentActionModel` rather than
 * `componentModel`. `setOption` will only modify the `ecModel` and `componentModel`.
 * When "resotre" action triggered, model from `componentActionModel` will be discarded
 * instead of recreating the "ecModel" from the "_optionBackup".
 */
// function mergeToBackupOption(
//     fakeCmptsMap: FakeComponentsMap,
//     // `tarOption` Can be null/undefined, means init
//     tarOption: ECUnitOption,
//     newOption: ECUnitOption,
//     // Can be null/undefined
//     opt: InnerSetOptionOpts
// ): void {
//     newOption = newOption || {} as ECUnitOption;
//     const notInit = !!tarOption;
//
//     each(newOption, function (newOptsInMainType, mainType) {
//         if (newOptsInMainType == null) {
//             return;
//         }
//
//         if (!ComponentModel.hasClass(mainType)) {
//             if (tarOption) {
//                 tarOption[mainType] = merge(tarOption[mainType], newOptsInMainType, true);
//             }
//         }
//         else {
//             const oldTarOptsInMainType = notInit ? normalizeToArray(tarOption[mainType]) : null;
//             const oldFakeCmptsInMainType = fakeCmptsMap.get(mainType) || [];
//             const resultTarOptsInMainType = notInit ? (tarOption[mainType] = [] as ComponentOption[]) : null;
//             const resultFakeCmptsInMainType = fakeCmptsMap.set(mainType, []);
//
//             const mappingResult = mappingToExists(
//                 oldFakeCmptsInMainType,
//                 normalizeToArray(newOptsInMainType),
//                 (opt && opt.replaceMergeMainTypeMap.get(mainType)) ? 'replaceMerge' : 'normalMerge'
//             );
//             setComponentTypeToKeyInfo(mappingResult, mainType, ComponentModel as ComponentModelConstructor);
//
//             each(mappingResult, function (resultItem, index) {
//                 // The same logic as `Global.ts#_mergeOption`.
//                 let fakeCmpt = resultItem.existing;
//                 const newOption = resultItem.newOption;
//                 const keyInfo = resultItem.keyInfo;
//                 let fakeCmptOpt;
//
//                 if (!newOption) {
//                     fakeCmptOpt = oldTarOptsInMainType[index];
//                 }
//                 else {
//                     if (fakeCmpt && fakeCmpt.subType === keyInfo.subType) {
//                         fakeCmpt.name = keyInfo.name;
//                         if (notInit) {
//                             fakeCmptOpt = merge(oldTarOptsInMainType[index], newOption, true);
//                         }
//                     }
//                     else {
//                         fakeCmpt = extend({}, keyInfo);
//                         if (notInit) {
//                             fakeCmptOpt = clone(newOption);
//                         }
//                     }
//                 }
//
//                 if (fakeCmpt) {
//                     notInit && resultTarOptsInMainType.push(fakeCmptOpt);
//                     resultFakeCmptsInMainType.push(fakeCmpt);
//                 }
//                 else {
//                     notInit && resultTarOptsInMainType.push(void 0);
//                     resultFakeCmptsInMainType.push(void 0);
//                 }
//             });
//         }
//     });
// }

// export default OptionManager;
