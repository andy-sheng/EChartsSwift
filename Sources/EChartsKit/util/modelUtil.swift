// Ported from echarts/src/util/model.ts — keep in sync with upstream
// NOTE: file renamed model.swift -> modelUtil.swift (upstream import alias `modelUtil`) to avoid a
//   case-insensitive object-file name collision with model/Model.swift on macOS (see PORT_STATUS §8).
//   The namespace enum is still `model`; no call sites change.
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
//   import { each, isObject, isArray, createHashMap, HashMap, map, assert, isString,
//            indexOf, isStringSafe, isNumber, hasOwn, retrieve2 } from 'zrender/src/core/util';
//       -> ZRenderKit.util  (createHashMap/HashMap/hasOwn are NOT yet ported in ZRenderKit — see
//          ZRenderKit/Core/util.swift PORT-TODO. A local public shim `HashMap`/`createHashMap`
//          is provided below; replace with `util.createHashMap` when ZRenderKit gains it.)
//   import env from 'zrender/src/core/env';
//       -> ZRenderKit `env` singleton is module-internal (not exposed); see getTooltipRenderMode.
//   import GlobalModel, { QueryConditionKindA } from '../model/Global';
//       -> GlobalModel placeholder (util/types.swift); QueryConditionKindA placeholder below.
//   import ComponentModel, { ComponentModelConstructor } from '../model/Component';
//       -> ComponentModel placeholder (util/types.swift); ComponentModelConstructor placeholder below.
//   import SeriesData from '../data/SeriesData';            -> SeriesData placeholder (util/types.swift)
//   import { ... } from './types';                          -> sibling types.swift (same module)
//   import { Dictionary } from 'zrender/src/core/types';    -> ZRenderKit.Dictionary
//   import type SeriesModel from '../model/Series';         -> SeriesModel placeholder (util/types.swift)
//   import type CartesianAxisModel / GridModel             -> not referenced at runtime here
//   import { isNumeric, getRandomIdBase, getPrecision, round } from './number';  -> sibling number.swift
//   import { error, warn } from './log';                   -> sibling log.swift
//   import type Model from '../model/Model';               -> Model placeholder (util/types.swift)
//   import type Displayable from 'zrender/src/graphic/Displayable';  -> ZRenderKit.Displayable
//   import type ChartView from '../view/Chart';            -> ChartView placeholder (util/types.swift)
//   import type { Pipeline, PipelineContext } from '../core/Scheduler';  -> placeholders below
//   import { TaskProgressParams } from '../core/task';     -> util/types.swift

// ============================================================================
// PORT-TODO: FORWARD-REFERENCE PLACEHOLDERS
// These types are imported by upstream `model.ts` from sibling echarts files that
// are NOT yet ported in this phase. They are declared here as minimal placeholders
// so this file compiles. The agent that ports the corresponding source file MUST
// remove the placeholder here and replace it with the real, fully-ported type.
// ============================================================================

// '../model/Global' — QueryConditionKindA (return type of makeQueryConditionKindA)
//   The real `QueryConditionKindA` is now defined in model/Global.swift (this phase); the placeholder
//   struct was removed to avoid a redeclaration. `makeQueryConditionKindA` below constructs it via
//   `QueryConditionKindA(mainType:query:)` and sets `.subType`, which the real definition supports.

// '../model/Component' — ComponentModelConstructor (the constructor/metatype with static
//   `determineSubType`). Modeled as a protocol whose metatype is passed where upstream passes
//   the class object.
public protocol ComponentModelConstructor: AnyObject {                       // PORT-TODO: belongs to model/Component
    static func determineSubType(_ mainType: ComponentMainType, _ option: ComponentOption) -> ComponentSubType
}

// '../core/Scheduler' — Pipeline (Pick<Pipeline, 'progressiveEnabled' | 'threshold'>) and
//   PipelineContext, used by preparePipelineContext.
public struct PipelinePick {                                                 // PORT-TODO: belongs to core/Scheduler
    public var progressiveEnabled: Bool
    public var threshold: Double
    public init(progressiveEnabled: Bool, threshold: Double) {
        self.progressiveEnabled = progressiveEnabled
        self.threshold = threshold
    }
}
public struct PipelineContext {                                              // PORT-TODO: belongs to core/Scheduler
    public var progressiveRender: Bool
    public var large: Bool
    public var modDataCount: Double?
    public init(progressiveRender: Bool, large: Bool, modDataCount: Double?) {
        self.progressiveRender = progressiveRender
        self.large = large
        self.modDataCount = modDataCount
    }
}

// `subType`-bearing existing component (upstream inline `{ subType?: ComponentSubType }`).
public protocol HasSubType: AnyObject {                                      // PORT-TODO: provided by ComponentModel
    var subType: ComponentSubType? { get }
}

// ============================================================================
// PORT-TODO: HashMap / createHashMap shim.
// `createHashMap` / `HashMap` are zrender util exports that are NOT yet ported in
// ZRenderKit (see ZRenderKit/Core/util.swift). This local public shim mirrors the
// upstream surface used here (`get`/`set`/`each`/`keys`, insertion-ordered, string
// keys via JS-style key coercion). Replace with `util.HashMap`/`util.createHashMap`
// once ZRenderKit ports them. Generic `KEY` is dropped (keys are always string-like).
// ============================================================================
public final class HashMap<V> {                                             // PORT-TODO: temporary shim for zrender HashMap
    private var data: [String: V] = [:]
    private var _keys: [String] = []   // preserves insertion order, like JS `Object.keys`

    public init() {}

    @discardableResult
    public func set(_ key: Any?, _ value: V) -> V {
        let k = hashKey(key)
        if data[k] == nil {
            _keys.append(k)
        }
        data[k] = value
        return value
    }

    public func get(_ key: Any?) -> V? {
        return data[hashKey(key)]
    }

    public func hasKey(_ key: Any?) -> Bool {
        return data[hashKey(key)] != nil
    }

    public func each(_ cb: (V, String) -> Void) {
        for k in _keys {
            if let v = data[k] {
                cb(v, k)
            }
        }
    }

    public func keys() -> [String] {
        return _keys
    }

    // zrender HashMap.removeKey (used by ElementMap.removeEl in GraphicView).
    public func removeKey(_ key: Any?) {
        let k = hashKey(key)
        data.removeValue(forKey: k)
        if let idx = _keys.firstIndex(of: k) {
            _keys.remove(at: idx)
        }
    }
}
public func createHashMap<V>() -> HashMap<V> {                              // PORT-TODO: temporary shim for zrender createHashMap
    return HashMap<V>()
}

// JS object-key coercion (number -> its toString, string -> itself). Not part of upstream.
fileprivate func hashKey(_ key: Any?) -> String {
    switch key {
    case nil: return "undefined"   // PORT-TODO: JS distinguishes 'null'/'undefined' keys
    case let s as String: return s
    case let d as Double: return jsNumberStr(d)
    case let i as Int: return String(i)
    case let b as Bool: return b ? "true" : "false"
    default: return String(describing: key!)
    }
}

// JS `'' + x` / `Number.prototype.toString` for a Double. Not part of upstream.
fileprivate func jsNumberStr(_ x: Double) -> String {
    if x.isNaN { return "NaN" }
    if x.isInfinite { return x > 0 ? "Infinity" : "-Infinity" }
    if x == x.rounded() && Swift.abs(x) < 1e21 {
        return String(Int64(x))
    }
    return String(x)
}

// JS `x + ''` for a value of unknown type. Not part of upstream.
fileprivate func jsToString(_ val: Any?) -> String {
    switch val {
    case nil: return "undefined"
    case let s as String: return s
    case let d as Double: return jsNumberStr(d)
    case let i as Int: return String(i)
    case let b as Bool: return b ? "true" : "false"
    default: return String(describing: val!)
    }
}

// upstream `key.match(/^(\w+)(Index|Id|Name)$/)`. Returns (main, queryType-lowercased) or nil.
// Not a standalone upstream symbol; inlines the regex used in preParseFinder.
fileprivate func matchFinderKey(_ key: String) -> (main: String, queryType: String)? {
    for suffix in ["Index", "Id", "Name"] {  // longest-first: 'Index' before 'Id'
        if key.hasSuffix(suffix) {
            let main = String(key.dropLast(suffix.count))
            if !main.isEmpty && main.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) {
                return (main, suffix.lowercased())
            }
        }
    }
    return nil
}

// 'id' | 'name' selector for keyExistAndEqual (upstream uses the string literal type).
enum AttrIdName {
    case id
    case name
}

// ============================================================================
// Exported data types / protocols (top level, mirroring upstream `interface`/`type`).
// ============================================================================

// Compatible with previous definition: id could be number (but not recommended).
// number and string are treated the same when compared.
// number id will not be converted to string in option.
// number id will be converted to string in component instance id.
// upstream: `interface MappingExistingItem { id?: OptionId; name?: string; }`.
// PORT-TODO: `name` widened from `string` to `OptionName` so this protocol and `ComponentOption`
//   share `MappingComparable` uniformly (id is already OptionId). Coerced back to String at use.
public protocol MappingExistingItem: AnyObject, MappingComparable {
    var id: OptionId? { get }
    var name: OptionName? { get }
}

// Shared id/name accessor so both `MappingExistingItem` (class) and `ComponentOption` (struct)
// can be passed to `keyExistAndEqual` / `isComponentIdInternal`. Not an upstream symbol; models
// the upstream structural type `{ id?: OptionId, name?: OptionName }`.
public protocol MappingComparable {
    var id: OptionId? { get }
    var name: OptionName? { get }
}
extension ComponentOption: MappingComparable {}

/**
 * The array `MappingResult<T>[]` exactly represents the content of the result
 * components array after merge.
 * The indices are the same as the `existings`.
 * Items will not be `null`/`undefined` even if the corresponding `existings` will be removed.
 */
// PORT-TODO: upstream is generic `MappingResult<T extends MappingExistingItem>`. Flattened to
//   `MappingExistingItem` (TS array covariance has no Swift analogue, and `makeIdAndName`
//   consumes `MappingResult<MappingExistingItem>`). Callers cast `.existing` to their concrete type.
public typealias MappingResult = [MappingResultItem]
// keyInfo for new component. All of them will be assigned to a created component instance.
// Modeled as a `final class` (reference) because upstream grabs `const keyInfo = item.keyInfo`
// then mutates fields through that alias (CONVENTIONS §4).
public final class MappingResultKeyInfo {
    public var name: String = ""
    public var id: String = ""
    public var mainType: ComponentMainType = ""
    public var subType: ComponentSubType = ""
    public init() {}
}
// Modeled as a `final class` (reference) because the mapping functions mutate
// `resultItem.newOption` / `.existing` / `.brandNew` / `.keyInfo` through aliases.
public final class MappingResultItem {
    // Existing component instance.
    public var existing: MappingExistingItem?
    // The mapped new component option.
    public var newOption: ComponentOption?
    // Mark that the new component has nothing to do with any of the old components.
    // So they won't share view. Also see `__requireNewView`.
    public var brandNew: Bool?
    public var keyInfo: MappingResultKeyInfo?
    public init(
        existing: MappingExistingItem? = nil,
        newOption: ComponentOption? = nil,
        brandNew: Bool? = nil,
        keyInfo: MappingResultKeyInfo? = nil
    ) {
        self.existing = existing
        self.newOption = newOption
        self.brandNew = brandNew
        self.keyInfo = keyInfo
    }
}

public enum MappingToExistsMode: String {                                    // upstream: 'normalMerge' | 'replaceMerge' | 'replaceAll'
    case normalMerge
    case replaceMerge
    case replaceAll
}

/**
 * If string, e.g., 'geo', means {geoIndex: 0}.
 * If Object, could contain some of these properties below: {seriesIndex, seriesId, ...}.
 * (See upstream for the full doc block.)
 */
// upstream: number | number[] | 'all' | 'none' | false | NullUndefined
public typealias ModelFinderIndexQuery = Any                                 // PORT-TODO: union
// upstream: OptionId | OptionId[] | NullUndefined
public typealias ModelFinderIdQuery = Any                                    // PORT-TODO: union
// upstream: OptionId | OptionId[] | NullUndefined
public typealias ModelFinderNameQuery = Any                                  // PORT-TODO: union
// upstream: string | ModelFinderObject
public typealias ModelFinder = Any                                           // PORT-TODO: string | ModelFinderObject
// upstream: a typed object with seriesIndex/seriesId/... keys; accessed dynamically (regex on
//   keys), so the runtime representation is a dictionary.
public typealias ModelFinderObject = [String: Any]                           // PORT-TODO: typed object upstream
/**
 * { seriesModels: [...], seriesModel: ..., geoModels: [...], ... }
 */
// upstream: { [key: string]: ComponentModel | ComponentModel[] | undefined }
public typealias ParsedModelFinder = [String: Any]                           // PORT-TODO: typed value union
public typealias ParsedModelFinderKnown = ParsedModelFinder                  // PORT-TODO: known-keys variant

public struct QueryReferringUserOption {
    public var index: ModelFinderIndexQuery?
    public var id: ModelFinderIdQuery?
    public var name: ModelFinderNameQuery?
    public init() {}
}

public struct QueryReferringOpt {
    // Whether to use the first component as the default if none of index/id/name are specified.
    public var useDefault: Bool?
    // Whether to enable `'all'` on index option.
    public var enableAll: Bool?
    // Whether to enable `'none'`/`false` on index option.
    public var enableNone: Bool?
    public init(useDefault: Bool? = nil, enableAll: Bool? = nil, enableNone: Bool? = nil) {
        self.useDefault = useDefault
        self.enableAll = enableAll
        self.enableNone = enableNone
    }
}

// Always be array rather than null/undefined, which is convenient to use.
public struct QueryReferringResult {
    public var models: [ComponentModel]
    public var specified: Bool
    public init(models: [ComponentModel], specified: Bool) {
        self.models = models
        self.specified = specified
    }
}

// Options for `parseFinder` / `preParseFinder`.
public struct PreParseFinderOpt {
    // If provided, types out of this list will be ignored.
    public var includeMainTypes: [ComponentMainType]?
    public init(includeMainTypes: [ComponentMainType]? = nil) {
        self.includeMainTypes = includeMainTypes
    }
}
public struct ParseFinderOpt {
    // If no main type specified, use this main type.
    public var defaultMainType: ComponentMainType?
    // If provided, types out of this list will be ignored.
    public var includeMainTypes: [ComponentMainType]?
    public var enableAll: Bool?
    public var enableNone: Bool?
    public init(
        defaultMainType: ComponentMainType? = nil,
        includeMainTypes: [ComponentMainType]? = nil,
        enableAll: Bool? = nil,
        enableNone: Bool? = nil
    ) {
        self.defaultMainType = defaultMainType
        self.includeMainTypes = includeMainTypes
        self.enableAll = enableAll
        self.enableNone = enableNone
    }
}

public struct PreParseFinderResult {
    public var mainTypeSpecified: Bool
    public var queryOptionMap: HashMap<QueryReferringUserOption>
    public var others: [String: Any]   // Partial<Pick<ParsedModelFinderKnown, 'dataIndex' | 'dataIndexInside'>>
}

public struct BatchItem {
    public var seriesId: OptionId
    public var dataIndex: Any   // number | number[]
    public init(seriesId: OptionId, dataIndex: Any) {
        self.seriesId = seriesId
        self.dataIndex = dataIndex
    }
}

/**
 * Use an iterator to avoid exposing the internal list or duplicating it
 * for the outside traveller, and no extra heap allocation. (See upstream usage block.)
 */
public final class ListIterator<TItem> {

    private var _idx: Int = 0
    private var _end: Int = 0
    private var _list: [TItem] = []
    private var _step: Int = 0

    public var item: TItem?
    public var key: Double = Double.nan

    public init() {}

    /**
     * The loop condition is `idx < end` if `step > 0`;
     * The loop condition is `idx >= end` if `step < 0`.
     *
     * @param end By default `list.length` if `step > 0`; `0` if `step < 0`.
     * @param step By default `1`.
     */
    @discardableResult
    public func reset(_ list: [TItem], _ start: Int, _ end: Int? = nil, _ step: Int? = nil) -> ListIterator<TItem> {
        self._list = list
        let step = (step == nil || step == 0) ? 1 : step!   // step = step || 1
        self._step = step
        self._idx = start
        self._end = end != nil ? end! : step > 0 ? list.count : 0

        self.item = nil
        self.key = Double.nan

        return self
    }

    @discardableResult
    public func next() -> Bool {
        if self._step > 0 ? self._idx < self._end : self._idx >= self._end {
            self.item = self._list[self._idx]
            self._idx = self._idx + self._step
            self.key = Double(self._idx)
            return true
        }
        return false
    }
}

// ============================================================================
// Free-function module `model.ts` -> caseless enum namespace `model` (CONVENTIONS §2).
// Call sites: upstream `normalizeToArray(...)` -> `model.normalizeToArray(...)`, etc.
// ============================================================================
public enum model {

    static func interpolateNumber(_ p0: Double, _ p1: Double, _ percent: Double) -> Double {
        return (p1 - p0) * percent + p0
    }

    /**
     * Make the name displayable. But we should
     * make sure it is not duplicated with user
     * specified name, so use '\0';
     */
    static let DUMMY_COMPONENT_NAME_PREFIX = "series\0"

    static let INTERNAL_COMPONENT_ID_PREFIX = "\0_ec_\0"

    /**
     * If value is not array, then translate it to array.
     * @param  {*} value
     * @return {Array} [value] or value
     */
    // upstream: normalizeToArray<T>(value?: T | T[]): T[]. The `T | T[]` union is not expressible;
    //   modeled with `Any?` input and an explicit `[T]` result (call sites annotate T).
    public static func normalizeToArray<T>(_ value: Any? = nil) -> [T] {
        // value instanceof Array
        if let arr = value as? [T] {
            return arr
        }
        // value == null
        if value == nil {
            return []
        }
        // [value]
        if let v = value as? T {
            return [v]
        }
        return []   // PORT-TODO: value is neither [T] nor T
    }

    /**
     * Sync default option between normal and emphasis like `position` and `show`
     * (See upstream for the full example.)
     */
    // PORT-TODO: `opt` is `inout` and `Optional` because upstream mutates the object in place and
    //   guards with `if (opt)`; `DisplayStateHostOption` is a value struct (CONVENTIONS §4), so the
    //   nested dictionary writes are read-modify-write-back. `opt[key]` reads from the dynamic
    //   `.other` bag; `opt.emphasis` is the typed field.
    public static func defaultEmphasis(
        _ opt: inout DisplayStateHostOption?,
        _ key: String,
        _ subOpts: [String]
    ) {
        // Caution: performance sensitive.
        if var o = opt {
            // opt[key] = opt[key] || {};
            if o.other[key] == nil {
                o.other[key] = [String: Any]()
            }
            // opt.emphasis = opt.emphasis || {};
            if o.emphasis == nil {
                o.emphasis = [:]
            }
            // opt.emphasis[key] = opt.emphasis[key] || {};
            if o.emphasis![key] == nil {
                o.emphasis![key] = [String: Any]()
            }

            var emphasisKey = (o.emphasis![key] as? [String: Any]) ?? [:]
            let optKey = (o.other[key] as? [String: Any]) ?? [:]

            // Default emphasis option from normal
            var i = 0
            let len = subOpts.count
            while i < len {
                let subOptName = subOpts[i]
                if !(emphasisKey[subOptName] != nil)   // !opt.emphasis[key].hasOwnProperty(subOptName)
                    && (optKey[subOptName] != nil)     // && opt[key].hasOwnProperty(subOptName)
                {
                    emphasisKey[subOptName] = optKey[subOptName]
                }
                i += 1
            }
            o.emphasis![key] = emphasisKey
            opt = o
        }
    }

    public static let TEXT_STYLE_OPTIONS: [String] = [
        "fontStyle", "fontWeight", "fontSize", "fontFamily",
        "rich", "tag", "color", "textBorderColor", "textBorderWidth",
        "width", "height", "lineHeight", "align", "verticalAlign", "baseline",
        "shadowColor", "shadowBlur", "shadowOffsetX", "shadowOffsetY",
        "textShadowColor", "textShadowBlur", "textShadowOffsetX", "textShadowOffsetY",
        "backgroundColor", "borderColor", "borderWidth", "borderRadius", "padding"
    ]

    // modelUtil.LABEL_OPTIONS = modelUtil.TEXT_STYLE_OPTIONS.concat([
    //     'position', 'offset', 'rotate', 'origin', 'show', 'distance', 'formatter',
    //     'fontStyle', 'fontWeight', 'fontSize', 'fontFamily',
    //     // FIXME: deprecated, check and remove it.
    //     'textStyle'
    // ]);

    /**
     * The method does not ensure performance.
     * data could be [12, 2323, {value: 223}, [1221, 23], {value: [2, 23]}]
     * This helper method retrieves value from data.
     */
    public static func getDataItemValue(_ dataItem: OptionDataItem) -> Any? {
        return (util.isObject(dataItem) && !util.isArray(dataItem) && !(dataItem is Date))
            ? (dataItem as? [String: Any])?["value"]   // (dataItem as Dictionary<OptionDataValue>).value
            : dataItem
    }

    /**
     * data could be [12, 2323, {value: 223}, [1221, 23], {value: [2, 23]}]
     * This helper method determine if dataItem has extra option besides value
     */
    public static func isDataItemOption(_ dataItem: OptionDataItem) -> Bool {
        return util.isObject(dataItem)
            && !(dataItem is [Any])
            // // markLine data can be array
            // && !(dataItem[0] && isObject(dataItem[0]) && !(dataItem[0] instanceof Array));
    }

    /**
     * Mapping to existings for merge. (See upstream for the full doc block describing the
     * "normalMerge" / "replaceMerge" / "replaceAll" modes.)
     */
    public static func mappingToExists(
        _ existings: [MappingExistingItem]?,
        _ newCmptOptionsInput: [ComponentOption]?,
        _ mode: MappingToExistsMode
    ) -> MappingResult {

        let isNormalMergeMode = mode == .normalMerge
        let isReplaceMergeMode = mode == .replaceMerge
        let isReplaceAllMode = mode == .replaceAll
        let existings = existings ?? []
        // newCmptOptions = (newCmptOptions || []).slice();
        var newCmptOptions: [ComponentOption?] = (newCmptOptionsInput ?? []).map { $0 }
        let existingIdIdxMap: HashMap<Double> = createHashMap()

        // Validate id and name on user input option.
        // (Iterate a snapshot so the captured `newCmptOptions` can be mutated without overlapping access.)
        let validateSnapshot = newCmptOptions
        util.each(validateSnapshot, { cmptOption, index in
            // !isObject<ComponentOption>(cmptOption) — `cmptOption` is a typed ComponentOption (always
            //   an object) or nil; a nil element is left as nil.
            guard let cmptOption = cmptOption else {
                newCmptOptions[index] = nil
                return
            }

            if __DEV__ {
                // There is some legacy case that name is set as `false`.
                // But should work normally rather than throw error.
                if cmptOption.id != nil && !isValidIdOrName(cmptOption.id) {
                    warnInvalidateIdOrName(cmptOption.id)
                }
                if cmptOption.name != nil && !isValidIdOrName(cmptOption.name) {
                    warnInvalidateIdOrName(cmptOption.name)
                }
            }
        })

        var result = prepareResult(existings, existingIdIdxMap, mode)

        if isNormalMergeMode || isReplaceMergeMode {
            mappingById(&result, existings, existingIdIdxMap, &newCmptOptions)
        }

        if isNormalMergeMode {
            mappingByName(&result, &newCmptOptions)
        }

        if isNormalMergeMode || isReplaceMergeMode {
            mappingByIndex(&result, &newCmptOptions, isReplaceMergeMode)
        }
        else if isReplaceAllMode {
            mappingInReplaceAllMode(&result, &newCmptOptions)
        }

        makeIdAndName(&result)

        // The array `result` MUST NOT contain elided items, otherwise the
        // forEach will omit those items and result in incorrect result.
        return result
    }

    static func prepareResult(
        _ existings: [MappingExistingItem],
        _ existingIdIdxMap: HashMap<Double>,
        _ mode: MappingToExistsMode
    ) -> MappingResult {
        var result: MappingResult = []

        if mode == .replaceAll {
            return result
        }

        // Do not use native `map` to in case that the array `existings`
        // contains elided items, which will be omitted.
        for index in 0..<existings.count {
            let existing: MappingExistingItem? = existings[index]
            // Because of replaceMerge, `existing` may be null/undefined.
            if let existing = existing, existing.id != nil {
                existingIdIdxMap.set(existing.id, Double(index))
            }
            // For non-internal-componnets:
            //     Mode "normalMerge": all existings kept.
            //     Mode "replaceMerge": all existing removed unless mapped by id.
            // For internal-components:
            //     go with "replaceMerge" approach in both mode.
            result.append(MappingResultItem(
                existing: (mode == .replaceMerge || isComponentIdInternal(existing))
                    ? nil
                    : existing,
                newOption: nil,
                brandNew: nil,
                keyInfo: nil
            ))
        }
        return result
    }

    static func mappingById(
        _ result: inout MappingResult,
        _ existings: [MappingExistingItem],
        _ existingIdIdxMap: HashMap<Double>,
        _ newCmptOptions: inout [ComponentOption?]
    ) {
        // Mapping by id if specified.
        let snapshot = newCmptOptions
        util.each(snapshot, { cmptOption, index in
            guard let cmptOption = cmptOption, cmptOption.id != nil else {
                return
            }
            let optionId = makeComparableKey(cmptOption.id)
            let existingIdx = existingIdIdxMap.get(optionId)
            if let existingIdx = existingIdx {
                let resultItem = result[Int(existingIdx)]
                util.assert(
                    !(resultItem.newOption != nil),
                    "Duplicated option on id \"" + optionId + "\"."
                )
                resultItem.newOption = cmptOption
                // In both mode, if id matched, new option will be merged to
                // the existings rather than creating new component model.
                resultItem.existing = existings[Int(existingIdx)]
                newCmptOptions[index] = nil
            }
        })
    }

    static func mappingByName(
        _ result: inout MappingResult,
        _ newCmptOptions: inout [ComponentOption?]
    ) {
        // Mapping by name if specified.
        let snapshot = newCmptOptions
        util.each(snapshot, { cmptOption, index in
            guard let cmptOption = cmptOption, cmptOption.name != nil else {
                return
            }
            for i in 0..<result.count {
                let existing = result[i].existing
                if !(result[i].newOption != nil)  // Consider name: two map to one.
                    // Can not match when both ids existing but different.
                    && existing != nil
                    && (existing!.id == nil || cmptOption.id == nil)
                    && !isComponentIdInternal(cmptOption)
                    && !isComponentIdInternal(existing)
                    && keyExistAndEqual(.name, existing!, cmptOption)
                {
                    result[i].newOption = cmptOption
                    newCmptOptions[index] = nil
                    return
                }
            }
        })
    }

    static func mappingByIndex(
        _ result: inout MappingResult,
        _ newCmptOptions: inout [ComponentOption?],
        _ brandNew: Bool
    ) {
        let snapshot = newCmptOptions
        util.each(snapshot, { cmptOption, _ in
            guard let cmptOption = cmptOption else {
                return
            }

            // Find the first place that not mapped by id and not internal component (consider the "hole").
            var resultItem: MappingResultItem?
            var nextIdx = 0
            while true {
                // Be `!resultItem` only when `nextIdx >= result.length`.
                resultItem = nextIdx < result.count ? result[nextIdx] : nil
                guard let ri = resultItem else {
                    break
                }
                // (1)(2)(3) — see upstream comment block.
                let cond =
                    (ri.newOption != nil)
                    || isComponentIdInternal(ri.existing)
                    || (
                        // In mode "replaceMerge", here no not-mapped-non-internal-existing.
                        ri.existing != nil
                        && cmptOption.id != nil
                        && !keyExistAndEqual(.id, cmptOption, ri.existing!)
                    )
                if !cond {
                    break
                }
                nextIdx += 1
            }

            if let resultItem = resultItem {
                resultItem.newOption = cmptOption
                resultItem.brandNew = brandNew
            }
            else {
                result.append(MappingResultItem(
                    existing: nil,
                    newOption: cmptOption,
                    brandNew: brandNew,
                    keyInfo: nil
                ))
            }
            // nextIdx++; (vestigial in upstream; the var is not reused after this)
            nextIdx += 1
            _ = nextIdx
        })
    }

    static func mappingInReplaceAllMode(
        _ result: inout MappingResult,
        _ newCmptOptions: inout [ComponentOption?]
    ) {
        let snapshot = newCmptOptions
        util.each(snapshot, { cmptOption, _ in
            // The feature "reproduce" requires "hole" will also reproduced
            // in case that component index referring are broken.
            result.append(MappingResultItem(
                existing: nil,
                newOption: cmptOption,
                brandNew: true,
                keyInfo: nil
            ))
        })
    }

    /**
     * Make id and name for mapping result (result of mappingToExists)
     * into `keyInfo` field.
     */
    static func makeIdAndName(
        _ mapResult: inout MappingResult
    ) {
        // We use this id to hash component models and view instances in echarts.
        // (See upstream comment block for the id/name generation rationale.)

        // Ensure that each id is distinct.
        let idMap: HashMap<MappingResultItem> = createHashMap()

        util.each(mapResult, { item, _ in
            let existing = item.existing
            if let existing = existing {
                idMap.set(existing.id, item)
            }
        })

        util.each(mapResult, { item, _ in
            // Force ensure id not duplicated.
            if let opt = item.newOption {
                let dup = opt.id != nil ? idMap.get(opt.id) : nil
                util.assert(
                    opt.id == nil || dup == nil || dup === item,
                    "id duplicates: " + jsToString(opt.id)
                )
                if opt.id != nil {
                    idMap.set(opt.id, item)
                }
            }
            if item.keyInfo == nil {
                item.keyInfo = MappingResultKeyInfo()
            }
        })

        // Make name and id.
        util.each(mapResult, { item, index in
            let existing = item.existing
            let optOpt = item.newOption
            let keyInfo = item.keyInfo!

            // if (!isObject<ComponentOption>(opt)) return;
            guard let opt = optOpt else {
                return
            }

            // Name can be overwritten. Consider case: axis.name = '20km'. (See upstream comment.)
            if opt.name != nil {
                keyInfo.name = makeComparableKey(opt.name)
            }
            else if let existing = existing {
                keyInfo.name = convertOptionIdName(existing.name, "") ?? ""   // PORT-TODO: name widened to OptionName
            }
            else {
                // Avoid that different series has the same name,
                // because name may be used like in color pallet.
                keyInfo.name = DUMMY_COMPONENT_NAME_PREFIX + String(index)
            }

            if let existing = existing {
                keyInfo.id = makeComparableKey(existing.id)
            }
            else if opt.id != nil {
                keyInfo.id = makeComparableKey(opt.id)
            }
            else {
                // Consider this situatoin: (see upstream comment) — series with the same name
                // between optionA and optionB should be mapped.
                var idNum = 0
                repeat {
                    keyInfo.id = "\0" + keyInfo.name + "\0" + String(idNum)
                    idNum += 1
                }
                while idMap.get(keyInfo.id) != nil
            }

            idMap.set(keyInfo.id, item)
        })
    }

    static func keyExistAndEqual(
        _ attr: AttrIdName,
        _ obj1: MappingComparable,
        _ obj2: MappingComparable
    ) -> Bool {
        let key1 = convertOptionIdName(attrValue(obj1, attr), nil)
        let key2 = convertOptionIdName(attrValue(obj2, attr), nil)
        // See `MappingExistingItem`. `id` and `name` trade string equals to number.
        return key1 != nil && key2 != nil && key1 == key2
    }

    static func attrValue(_ obj: MappingComparable, _ attr: AttrIdName) -> Any? {
        switch attr {
        case .id: return obj.id
        case .name: return obj.name
        }
    }

    /**
     * @return return null if not exist.
     */
    static func makeComparableKey(_ val: Any?) -> String {
        if __DEV__ {
            if val == nil {
                // upstream: throw new Error();
                util.assert(false)   // PORT-TODO: upstream throws Error()
            }
        }
        return convertOptionIdName(val, "") ?? ""
    }

    public static func convertOptionIdName(_ idOrName: Any?, _ defaultValue: String?) -> String? {
        if idOrName == nil {
            return defaultValue
        }
        if util.isString(idOrName) {
            return (idOrName as! String)
        }
        if util.isNumber(idOrName) || util.isStringSafe(idOrName) {
            return jsToString(idOrName)   // idOrName + ''
        }
        return defaultValue
    }

    static func warnInvalidateIdOrName(_ idOrName: Any?) {
        if __DEV__ {
            log.warn("`" + jsToString(idOrName) + "` is invalid id or name. Must be a string or number.")
        }
    }

    static func isValidIdOrName(_ idOrName: Any?) -> Bool {
        return util.isStringSafe(idOrName) || number.isNumeric(idOrName)
    }

    public static func isNameSpecified(_ componentModel: ComponentModel) -> Bool {
        // PORT-TODO: ComponentModel placeholder (util/types.swift) has no `name`; cannot read
        //   componentModel.name yet. Faithful body preserved below.
        // const name = componentModel.name;
        // // Is specified when `indexOf` get -1 or > 0.
        // return !!(name && name.indexOf(DUMMY_COMPONENT_NAME_PREFIX));
        _ = componentModel
        return false
    }

    /**
     * @public
     */
    public static func isComponentIdInternal(_ cmptOption: MappingComparable?) -> Bool {
        guard let cmptOption = cmptOption, cmptOption.id != nil else {
            return false
        }
        // makeComparableKey(cmptOption.id).indexOf(INTERNAL_COMPONENT_ID_PREFIX) === 0
        return makeComparableKey(cmptOption.id).hasPrefix(INTERNAL_COMPONENT_ID_PREFIX)
    }

    public static func makeInternalComponentId(_ idSuffix: String) -> String {
        return INTERNAL_COMPONENT_ID_PREFIX + idSuffix
    }

    public static func setComponentTypeToKeyInfo(
        _ mappingResult: MappingResult,
        _ mainType: ComponentMainType,
        _ componentModelCtor: ComponentModelConstructor.Type
    ) {
        // Set mainType and complete subType.
        util.each(mappingResult, { item, _ in
            // if (isObject(newOption)) — newOption is a typed ComponentOption or nil.
            if let newOption = item.newOption {
                item.keyInfo!.mainType = mainType
                item.keyInfo!.subType = determineSubType(mainType, newOption, item.existing, componentModelCtor)
            }
        })
    }

    static func determineSubType(
        _ mainType: ComponentMainType,
        _ newCmptOption: ComponentOption,
        _ existComponent: MappingExistingItem?,
        _ componentModelCtor: ComponentModelConstructor.Type
    ) -> ComponentSubType {
        let subType: ComponentSubType
        if let type = newCmptOption.type, !type.isEmpty {   // newCmptOption.type ? ...
            subType = type
        }
        else if let existComponent = existComponent {
            // PORT-TODO: existComponent.subType requires the component to conform to HasSubType.
            subType = (existComponent as? HasSubType)?.subType ?? ""
        }
        else {
            // Use determineSubType only when there is no existComponent.
            subType = componentModelCtor.determineSubType(mainType, newCmptOption)
        }

        // tooltip, markline, markpoint may always has no subType
        return subType
    }

    /**
     * A helper for removing duplicate items between batchA and batchB,
     * and in themselves, and categorize by series.
     *
     * @param batchA Like: [{seriesId: 2, dataIndex: [32, 4, 5]}, ...]
     * @param batchB Like: [{seriesId: 2, dataIndex: [32, 4, 5]}, ...]
     * @return result: [resultBatchA, resultBatchB]
     */
    public static func compressBatches(
        _ batchA: [BatchItem]?,
        _ batchB: [BatchItem]?
    ) -> ([BatchItem], [BatchItem]) {

        // type InnerMap = { [seriesId]: { [dataIndex]: 1 } }. Modeled as nested dictionaries.
        // The value uses `Double??` so a key can be present-but-null (upstream sets the cell to
        // `null` to mark a cross-batch duplicate but keeps the key).
        var mapA: [String: [String: Double?]] = [:]
        var mapB: [String: [String: Double?]] = [:]

        // PORT: upstream `otherMap` is a JS object (reference) that `makeMap` mutates in place
        //   (`otherDataIndices[dataIndex] = null`) so the cross-batch dedup is reflected back in
        //   `mapA`. Swift dictionaries are value types, so `otherMap` MUST be `inout` (see the
        //   §3/§4 value-vs-reference hazard) — otherwise the nulling is lost and resultA still
        //   contains cross-batch duplicates. The first (batchA) call has no other map upstream
        //   (`otherMap?`); we pass an empty dict (behaviorally == absent: every lookup misses).
        var noOtherMap: [String: [String: Double?]] = [:]
        makeMap(batchA ?? [], &mapA, &noOtherMap)
        makeMap(batchB ?? [], &mapB, &mapA)

        return (mapToArrayOuter(mapA), mapToArrayOuter(mapB))
    }

    static func makeMap(
        _ sourceBatch: [BatchItem],
        _ map: inout [String: [String: Double?]],
        _ otherMap: inout [String: [String: Double?]]
    ) {
        var i = 0
        let len = sourceBatch.count
        while i < len {
            let seriesId = convertOptionIdName(sourceBatch[i].seriesId, nil)
            if seriesId == nil {
                return
            }
            let dataIndices: [Double] = normalizeToArray(sourceBatch[i].dataIndex)
            var otherDataIndices = otherMap[seriesId!]

            var j = 0
            let lenj = dataIndices.count
            while j < lenj {
                let dataIndex = dataIndices[j]
                let dataIndexKey = jsNumberStr(dataIndex)

                if let od = otherDataIndices, let cell = od[dataIndexKey], cell != nil {
                    // otherDataIndices[dataIndex] = null;
                    otherDataIndices!.updateValue(nil, forKey: dataIndexKey)
                    otherMap[seriesId!] = otherDataIndices
                }
                else {
                    // (map[seriesId] || (map[seriesId] = {}))[dataIndex] = 1;
                    if map[seriesId!] == nil {
                        map[seriesId!] = [:]
                    }
                    map[seriesId!]![dataIndexKey] = .some(1)
                }
                j += 1
            }
            i += 1
        }
    }

    // upstream `mapToArray(map, isData?)` is one recursive function returning `any[]`. Swift's type
    // system makes a single signature awkward, so it is split: outer (seriesId -> dataIndices) and
    // inner (dataIndex cell -> +i). PORT-TODO: documented split of upstream's recursive mapToArray.
    static func mapToArrayOuter(_ map: [String: [String: Double?]]) -> [BatchItem] {
        var result: [BatchItem] = []
        for i in map.keys {
            if map[i] != nil {   // map.hasOwnProperty(i) && map[i] != null
                let dataIndices = mapToArrayInner(map[i]!)
                if !dataIndices.isEmpty {   // dataIndices.length && ...
                    result.append(BatchItem(seriesId: i, dataIndex: dataIndices))
                }
            }
        }
        return result
    }

    static func mapToArrayInner(_ map: [String: Double?]) -> [Double] {
        var result: [Double] = []
        for i in map.keys {
            if let cell = map[i], cell != nil {   // map.hasOwnProperty(i) && map[i] != null
                result.append(numericFromKey(i))   // result.push(+i)
            }
        }
        return result
    }

    // JS `+i` where `i` is a numeric object key.
    static func numericFromKey(_ key: String) -> Double {
        return Double(key) ?? Double.nan
    }

    /**
     * @param payload Contains dataIndex (means rawIndex) / dataIndexInside / name
     *                each of which can be Array or primary type.
     * @return dataIndex If not found, return undefined/null.
     */
    // upstream return: number | number[]
    public static func queryDataIndex(_ data: SeriesData, _ payload: Payload) -> Any? {
        // PORT-TODO: payload dynamic keys (dataIndexInside/dataIndex/name) read from `.other`;
        //   SeriesData placeholder (util/types.swift) has no `indexOfRawIndex`/`indexOfName`,
        //   so the lookup is stubbed. Faithful body preserved in comments.
        _ = data
        if let dataIndexInside = payload.other["dataIndexInside"], !(dataIndexInside is NSNull) {
            return dataIndexInside
        }
        else if let dataIndex = payload.other["dataIndex"], !(dataIndex is NSNull) {
            // return isArray(dataIndex)
            //     ? map(dataIndex, v => data.indexOfRawIndex(v))
            //     : data.indexOfRawIndex(dataIndex);
            _ = dataIndex
            return nil   // PORT-TODO: data.indexOfRawIndex
        }
        else if let name = payload.other["name"], !(name is NSNull) {
            // return isArray(name)
            //     ? map(name, v => data.indexOfName(v))
            //     : data.indexOfName(name);
            _ = name
            return nil   // PORT-TODO: data.indexOfName
        }
        return nil
    }

    /**
     * Enable property storage to any host object. (See upstream usage block.)
     * [CAVEAT]: DO NOT use it in performance-sensitive scenarios.
     */
    // PORT-TODO: upstream stores a hidden key (`'__ec_inner_' + innerUniqueIndex++`) directly on the
    //   host object and lazily creates an empty `{}` bag. Swift cannot add a dynamic property to an
    //   arbitrary object, and cannot construct `T` without a factory, so:
    //     - storage uses a per-`makeInner` `WeakMap<Host, T>` (object-identity keyed),
    //     - the empty `{}` default becomes a caller-supplied `create` factory (matches innerStore.swift).
    //   `innerUniqueIndex` is still incremented for fidelity but no longer namespaces a hidden key.
    public static func makeInner<T: AnyObject, Host: AnyObject>(_ create: @escaping () -> T) -> (Host) -> T {
        // const key = '__ec_inner_' + innerUniqueIndex++;
        innerUniqueIndex += 1
        let store = WeakMap<Host, T>()
        return { hostObj in
            // return (hostObj as any)[key] || ((hostObj as any)[key] = {});
            if let existing = store.get(hostObj) {
                return existing
            }
            let created = create()
            store.set(hostObj, created)
            return created
        }
    }
    static var innerUniqueIndex: Double = number.getRandomIdBase()

    /**
     * The same behavior as `component.getReferringComponents`.
     */
    public static func parseFinder(
        _ ecModel: GlobalModel,
        _ finderInput: ModelFinder,
        _ opt: ParseFinderOpt? = nil
    ) -> ParsedModelFinder {
        let pre = preParseFinder(
            finderInput,
            opt != nil ? PreParseFinderOpt(includeMainTypes: opt!.includeMainTypes) : nil
        )
        let mainTypeSpecified = pre.mainTypeSpecified
        let queryOptionMap = pre.queryOptionMap
        var result: ParsedModelFinderKnown = pre.others   // const result = others as ParsedModelFinderKnown;

        let defaultMainType = opt != nil ? opt!.defaultMainType : nil
        if !mainTypeSpecified, let defaultMainType = defaultMainType {
            queryOptionMap.set(defaultMainType, QueryReferringUserOption())
        }

        queryOptionMap.each({ queryOption, mainType in
            let queryResult = queryReferringComponents(
                ecModel,
                mainType,
                queryOption,
                QueryReferringOpt(
                    useDefault: defaultMainType == mainType,
                    enableAll: (opt != nil && opt!.enableAll != nil) ? opt!.enableAll : true,
                    enableNone: (opt != nil && opt!.enableNone != nil) ? opt!.enableNone : true
                )
            )
            result[mainType + "Models"] = queryResult.models
            result[mainType + "Model"] = queryResult.models.first   // models[0]
        })

        return result
    }

    public static func preParseFinder(
        _ finderInput: ModelFinder,
        _ opt: PreParseFinderOpt? = nil
    ) -> PreParseFinderResult {
        var finder: ModelFinderObject
        if util.isString(finderInput) {
            var obj: [String: Any] = [:]
            obj[(finderInput as! String) + "Index"] = 0.0
            finder = obj
        }
        else {
            finder = (finderInput as? ModelFinderObject) ?? [:]
        }

        let queryOptionMap: HashMap<QueryReferringUserOption> = createHashMap()
        var others: [String: Any] = [:]
        var mainTypeSpecified = false

        // each(finder, function (value, key) { ... })
        // PORT-TODO: object iteration order is not guaranteed by Swift Dictionary; upstream relies
        //   on JS enumeration order, but here each key is processed independently so order is benign.
        for (key, value) in finder {
            // Exclude 'dataIndex' and other illegal keys.
            if key == "dataIndex" || key == "dataIndexInside" {
                others[key] = value
                continue
            }

            // const parsedKey = key.match(/^(\w+)(Index|Id|Name)$/) || [];
            guard let parsedKey = matchFinderKey(key) else {
                continue
            }
            let mainType = parsedKey.main
            let queryType = parsedKey.queryType

            if opt != nil, let includeMainTypes = opt!.includeMainTypes,
               util.indexOf(includeMainTypes, mainType) < 0 {
                continue
            }

            mainTypeSpecified = mainTypeSpecified || !mainType.isEmpty

            // const queryOption = queryOptionMap.get(mainType) || queryOptionMap.set(mainType, {});
            var queryOption = queryOptionMap.get(mainType) ?? queryOptionMap.set(mainType, QueryReferringUserOption())
            // queryOption[queryType] = value;
            switch queryType {
            case "index": queryOption.index = value
            case "id": queryOption.id = value
            case "name": queryOption.name = value
            default: break
            }
            // PORT-TODO: QueryReferringUserOption is a value struct; write the mutated copy back.
            queryOptionMap.set(mainType, queryOption)
        }

        return PreParseFinderResult(
            mainTypeSpecified: mainTypeSpecified,
            queryOptionMap: queryOptionMap,
            others: others
        )
    }

    public static let SINGLE_REFERRING = QueryReferringOpt(useDefault: true, enableAll: false, enableNone: false)
    public static let MULTIPLE_REFERRING = QueryReferringOpt(useDefault: false, enableAll: true, enableNone: true)

    public static func queryReferringComponents(
        _ ecModel: GlobalModel,
        _ mainType: ComponentMainType,
        _ userOption: QueryReferringUserOption,
        _ optInput: QueryReferringOpt? = nil
    ) -> QueryReferringResult {
        let opt = optInput ?? SINGLE_REFERRING
        var indexOption = userOption.index
        var idOption = userOption.id
        var nameOption = userOption.name

        var result = QueryReferringResult(
            models: [],
            specified: indexOption != nil || idOption != nil || nameOption != nil
        )

        if !result.specified {
            // Use the first as default if `useDefault`.
            // result.models = (opt.useDefault && (firstCmpt = ecModel.getComponent(mainType))) ? [firstCmpt] : [];
            if opt.useDefault == true, let firstCmpt = ecModel.getComponent(mainType) {
                result.models = [firstCmpt]
            }
            else {
                result.models = []
            }
            return result
        }

        if (indexOption as? String) == "none" || (indexOption as? Bool) == false {
            if opt.enableNone == true {
                result.models = []
                return result
            }
            else {
                // Do not throw; consider backward compatibility (see upstream comment).
                if __DEV__ {
                    log.error("`\"none\"` or `false` is not a valid value on index option.")
                }
                indexOption = -1.0   // Can not query by index but may still query by id/name if specified.
            }
        }

        // `queryComponents` will return all components if
        // both all of index/id/name are null/undefined.
        if (indexOption as? String) == "all" {
            if opt.enableAll == true {
                indexOption = nil
                idOption = nil
                nameOption = nil
            }
            else {
                if __DEV__ {
                    log.error("`\"all\"` is not a valid value on index option.")
                }
                indexOption = -1.0
            }
        }
        // result.models = ecModel.queryComponents({ mainType, index: indexOption, id: idOption, name: nameOption });
        result.models = ecModel.queryComponents(
            QueryConditionKindB(mainType: mainType, index: indexOption, id: idOption, name: nameOption)
        )
        return result
    }

    /**
     * `{{mainType}Id, {mainType}Index, {mainType}Name}` takes precedence if provided in `payload`;
     * otherwise, query by `mainType`. `subType` performs further filtering if provided.
     */
    public static func makeQueryConditionKindA(
        _ payload: Payload,
        // `mainType` is mandatory to restrict the range of query, since `payload` in an user input.
        _ mainType: ComponentMainType,
        // subType may be '' by `parseClassType`
        _ subType: ComponentSubType?
    ) -> QueryConditionKindA {
        if __DEV__ {
            util.assert(!mainType.isEmpty)   // assert(mainType)
        }
        var query: [String: Any] = [:]
        // PORT-TODO: `payload[mainType + 'Id']` dynamic access -> `payload.other[...]`.
        query[mainType + "Id"] = payload.other[mainType + "Id"]
        query[mainType + "Index"] = payload.other[mainType + "Index"]
        query[mainType + "Name"] = payload.other[mainType + "Name"]

        var condition = QueryConditionKindA(mainType: mainType, query: query)
        if let subType = subType, !subType.isEmpty {   // subType && (condition.subType = subType)
            condition.subType = subType   // subType is determined by `hasOwnProperty`.
        }

        return condition
    }

    public static func setAttribute(_ dom: HTMLElement, _ key: String, _ value: Any) {
        // PORT-TODO: DOM seam (CONVENTIONS §9) — no HTMLElement on iOS.
        //   dom.setAttribute ? dom.setAttribute(key, value) : (dom[key] = value);
        _ = dom
        _ = key
        _ = value
    }

    public static func getAttribute(_ dom: HTMLElement, _ key: String) -> Any? {
        // PORT-TODO: DOM seam (CONVENTIONS §9).
        //   return dom.getAttribute ? dom.getAttribute(key) : dom[key];
        _ = dom
        _ = key
        return nil
    }

    public static func getTooltipRenderMode(_ renderModeOption: Any?) -> TooltipRenderMode {
        if (renderModeOption as? String) == "auto" {
            // Using html when `document` exists, use richText otherwise.
            // PORT-TODO: zrender `env` is module-internal (not exposed to EChartsKit); on iOS
            //   `env.domSupported` is always false -> richText.
            return .richText
        }
        else {
            // return renderModeOption || 'html';
            if let m = renderModeOption as? TooltipRenderMode {
                return m
            }
            if let s = renderModeOption as? String, let m = TooltipRenderMode(rawValue: s) {
                return m
            }
            return .html
        }
    }

    /**
     * Group a list by key.
     */
    public static func groupData<T, R>(
        _ array: [T]?,
        _ getKey: (T) -> R   // return key
    ) -> (keys: [R], buckets: HashMap<[T]>) {
        let buckets: HashMap<[T]> = createHashMap()
        var keys: [R] = []

        util.each(array, { item, _ in
            let key = getKey(item)
            // (buckets.get(key) || (keys.push(key), buckets.set(key, []))).push(item);
            var bucket = buckets.get(key)
            if bucket == nil {
                keys.append(key)
                bucket = buckets.set(key, [T]())
            }
            bucket!.append(item)
            // PORT-TODO: JS arrays are reference types; Swift `[T]` is a value type, so write the
            //   mutated bucket back into the map.
            buckets.set(key, bucket!)
        })

        return (keys: keys, buckets: buckets)
    }

    /**
     * Interpolate raw values of a series with percent. (See upstream for the full doc block.)
     */
    // upstream param `precision: number | 'auto'`; sourceValue/targetValue: InterpolatableValue.
    public static func interpolateRawValues(
        _ data: SeriesData,
        _ precision: Any?,
        _ sourceValue: Any?,
        _ targetValue: Any?,
        _ percent: Double
    ) -> Any? {
        let isAutoPrecision = precision == nil || (precision as? String) == "auto"

        if targetValue == nil {
            return targetValue
        }

        if util.isNumber(targetValue) {
            let value = interpolateNumber(
                (sourceValue as? Double) ?? 0,   // sourceValue as number || 0
                targetValue as! Double,
                percent
            )
            return number.round(
                value,
                isAutoPrecision ? number.mathMax(
                    number.getPrecision((sourceValue as? Double) ?? 0),
                    number.getPrecision(targetValue as! Double)
                )
                : (precision as! Double)
            )
        }
        else if util.isString(targetValue) {
            return percent < 1 ? sourceValue : targetValue
        }
        else {
            var interpolated: [Any?] = []
            let leftArr = sourceValue as? [Any?]
            let rightArr = targetValue as! [Any?]
            let length = Int(number.mathMax(Double(leftArr != nil ? leftArr!.count : 0), Double(rightArr.count)))
            var i = 0
            while i < length {
                // const info = data.getDimensionInfo(i);
                // PORT-TODO: SeriesData placeholder (util/types.swift) has no `getDimensionInfo`;
                //   assume non-ordinal (`info` is nil) for now.
                _ = data
                // PORT-TODO: upstream skips interpolation for ordinal dims —
                //   `const infoIsOrdinal = info && info.type === 'ordinal';`
                //   `if (infoIsOrdinal) { interpolated[i] = (percent<1 && leftArr ? leftArr : rightArr)[i]; }`
                //   `else { <numeric interpolation below> }`
                //   The dimension `info` is not threaded into this helper yet (always non-ordinal
                //   here), so only the numeric path is active. Restore the ordinal-skip branch when
                //   dim info is wired (model/ phase).
                // const leftVal = leftArr && leftArr[i] ? leftArr[i] as number : 0;
                let leftVal: Double = (leftArr != nil && i < leftArr!.count ? (leftArr![i] as? Double) : nil) ?? 0
                let rightVal: Double = (i < rightArr.count ? (rightArr[i] as? Double) : nil) ?? 0
                let value = interpolateNumber(leftVal, rightVal, percent)
                interpolated.append(number.round(
                    value,
                    isAutoPrecision ? number.mathMax(
                        number.getPrecision(leftVal),
                        number.getPrecision(rightVal)
                    )
                    : (precision as! Double)
                ))
                i += 1
            }
            return interpolated
        }
    }

    public static func clearTmpModel(_ model: Model) {
        // Clear to avoid memory leak.
        // PORT-TODO: Model placeholder (util/types.swift) has no `option`/`parentModel`/`ecModel`.
        //   model.option = model.parentModel = model.ecModel = null;
        _ = model
    }

    public static func initExtentForUnion() -> [Double] {
        return [Double.infinity, -Double.infinity]
    }

    /**
     * NOTICE:
     *  - The input `val` must be a number - type checking is not performed.
     *  - `extent` should be initialized as `initExtentForUnion()`.
     */
    // PORT-TODO: `extent` is `inout` (upstream mutates `number[]` in place; Swift `[Double]` is a value).
    public static func unionExtentFromNumber(_ extent: inout [Double], _ val: Double?) {
        if isValidNumberForExtent(val) {
            if val! < extent[0] { extent[0] = val! }
            if val! > extent[1] { extent[1] = val! }
        }
    }

    public static func unionExtentStartFromNumber(_ extent: inout [Double], _ val: Double?) {
        if isValidNumberForExtent(val) && val! < extent[0] {
            extent[0] = val!
        }
    }

    public static func unionExtentEndFromNumber(_ extent: inout [Double], _ val: Double?) {
        if isValidNumberForExtent(val) && val! > extent[1] {
            extent[1] = val!
        }
    }

    /**
     * NOTICE: `extent` should be initialized as `initExtentForUnion()`.
     */
    public static func unionExtentFromExtent(_ tarExtent: inout [Double], _ srcExtent: [Double]) {
        // Accept both or neither.
        if isValidBoundsForExtent(srcExtent[0], srcExtent[1]) {
            if srcExtent[0] < tarExtent[0] { tarExtent[0] = srcExtent[0] }
            if srcExtent[1] > tarExtent[1] { tarExtent[1] = srcExtent[1] }
        }
    }

    /**
     * PENDING: `Infinity` from user data is not necessarily meaningless (see upstream comment).
     */
    public static func isValidNumberForExtent(_ val: Double?) -> Bool {
        // Considered that number could be `NaN` and `Infinity` and should not write into the extent.
        return val != nil && val!.isFinite
    }

    public static func isValidBoundsForExtent(_ start: Double?, _ end: Double?) -> Bool {
        return isValidNumberForExtent(start) && isValidNumberForExtent(end) && start! <= end!
    }

    /**
     * `extent` should be initialized by `initExtentForUnion()`, and unioned by `unionExtent()`.
     * `extent` may contain `Infinity` / `NaN`, but assume no `null`/`undefined`.
     */
    public static func extentHasValue(_ extent: [Double]) -> Bool {
        // Also considered extent may have `NaN` and `Infinity`.
        let span = extent[1] - extent[0]
        return span.isFinite && span >= 0
    }

    /**
     * NOTE: considered items are null/undefined/NaN - do nothing for this case.
     */
    // PORT-TODO: `extent` is `inout`; items typed `(number | NullUndefined)[]` -> `[Double?]`.
    public static func ensureExtentAscSimply(_ extent: inout [Double?]) {
        if isValidBoundsForExtent(extent[0], extent[1]) && extent[0]! > extent[1]! {
            extent[0] = extent[1]
        }
    }

    /**
     * A util for ensuring the callback is called only once. (See upstream usage block.)
     */
    // PORT-TODO: upstream stamps a hidden key (`'__ec_once_' + onceUniqueIndex++`) on the host via
    //   `hasOwn`. Swift cannot add a dynamic property, so a per-`makeCallOnlyOnce` `WeakMap<Host, Bool>`
    //   (object-identity keyed) records whether the callback already ran for a given host.
    public static func makeCallOnlyOnce<Host: AnyObject>() -> (Host, () -> Void) -> Void {
        // const hiddenKey = '__ec_once_' + onceUniqueIndex++;
        onceUniqueIndex += 1
        let called = WeakMap<Host, Bool>()
        return { hostObj, cb in
            if __DEV__ {
                // assert(hostObj) — Host: AnyObject guarantees a non-nil object.
            }
            if !called.has(hostObj) {   // !hasOwn(hostObj, hiddenKey)
                called.set(hostObj, true)
                cb()
            }
        }
    }
    static var onceUniqueIndex: Double = number.getRandomIdBase()

    /**
     * @usage
     *  - The earlier item takes precedence for duplicate items.
     *  - The input `arr` will be modified if `resolve` is null/undefined.
     *  - Callers can use `resolve` to manually modify the `currItem`.
     *  - Callers need to handle null/undefined (if existing) in `getKey`.
     */
    // PORT-TODO: `arr` is `inout` (upstream mutates in place, incl. `arr.length = writeIdx`).
    public static func removeDuplicates<TItem>(
        _ arr: inout [TItem?],
        _ getKey: (TItem?) -> String,
        // `existingCount`: the count before this item is added.
        _ resolve: ((TItem, Double) -> Void)?
    ) {
        let dupMap: HashMap<Double> = createHashMap()
        var writeIdx = 0
        let snapshot = arr
        util.each(snapshot, { item, _ in
            let key = getKey(item)
            if __DEV__ {
                util.assert(util.isString(key))
            }
            let count = dupMap.get(key) ?? 0
            if let resolve = resolve, let item = item {
                resolve(item, count)
            }
            if count == 0 && resolve == nil {
                arr[writeIdx] = item
                writeIdx += 1
            }
            dupMap.set(key, count + 1)
        })
        if resolve == nil {
            // arr.length = writeIdx;
            if writeIdx < arr.count {
                arr.removeLast(arr.count - writeIdx)
            }
        }
    }

    // upstream: removeDuplicatesGetKeyFromValueProp<TValue>(item: {value: TValue}): string
    public static func removeDuplicatesGetKeyFromValueProp(_ item: Any?) -> String {
        // PORT-TODO: typed `{value: TValue}` object -> dictionary access.
        let value = (item as? [String: Any])?["value"]
        if __DEV__ {
            util.assert(value != nil)
        }
        return jsToString(value)   // item.value + ''
    }

    // upstream: removeDuplicatesGetKeyFromItemItself<TValue>(item: TValue): string
    public static func removeDuplicatesGetKeyFromItemItself(_ item: Any?) -> String {
        if __DEV__ {
            util.assert(item != nil)
        }
        return jsToString(item)   // item + ''
    }

    public static func getIncrementalId(
        _ seriesModel: SeriesModel,
        _ useIncremental: Bool? = nil
    ) -> Double {
        // 0 means disable incremental.
        // 1 is preserved for backward compatibility.
        let inc = util.retrieve2(useIncremental, true) ?? true
        // PORT-TODO: SeriesModel placeholder (util/types.swift) has no `seriesIndex`.
        //   return retrieve2(useIncremental, true) ? seriesModel.seriesIndex + 2 : 0;
        _ = seriesModel
        let seriesIndex = 0.0   // PORT-TODO: seriesModel.seriesIndex
        return inc ? seriesIndex + 2 : 0
    }

    public static func preparePipelineContext(
        _ seriesModel: SeriesModel,
        _ view: ChartView,
        _ pipeline: PipelinePick
    ) -> PipelineContext {
        // PORT-TODO: SeriesModel/ChartView placeholders (util/types.swift) have no
        //   `getData`/`get`/`incrementalPrepareRender`. Faithful body preserved in comments.
        // const dataLen = seriesModel.getData().count();
        // return {
        //     progressiveRender: pipeline.progressiveEnabled && view.incrementalPrepareRender && dataLen >= pipeline.threshold,
        //     large: seriesModel.get('large') && dataLen >= seriesModel.get('largeThreshold'),
        //     modDataCount: seriesModel.get('progressiveChunkMode') === 'mod' ? seriesModel.getData().count() : null,
        // };
        _ = seriesModel
        _ = view
        _ = pipeline
        return PipelineContext(progressiveRender: false, large: false, modDataCount: nil)
    }

    /**
     * When some task "blocks" the upstream part of the pipeline, the upstream output range is from
     * the start to the final end. (See upstream comment block.) This method provides an assertion.
     */
    public static func validateUpstreamOutputRange(
        // null/undefined is not allowed, otherwise bug-prone.
        _ upstreamOutputRange: TaskProgressParams,
        _ thisTaskPlannedRange: TaskProgressParams
    ) {
        util.assert(
            upstreamOutputRange.start == thisTaskPlannedRange.start
            && upstreamOutputRange.end == thisTaskPlannedRange.end
        )
    }

    public static func createSimpleOverallStageHandler(
        _ seriesType: ComponentSubType,
        _ overallReset: @escaping StageHandlerOverallReset
    ) -> StageHandler {
        var handler = StageHandler()
        handler.seriesType = seriesType
        handler.overallReset = overallReset
        return handler
    }

    public static func createSimpleOverallStageHandler2(
        _ overallReset: @escaping StageHandlerOverallReset
    ) -> StageHandler {
        var handler = StageHandler()
        handler.overallReset = overallReset
        return handler
    }
}
