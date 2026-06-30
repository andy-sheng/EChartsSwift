// Ported from echarts/src/scale/scaleMapper.ts — keep in sync with upstream
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

// upstream: import { assert, bind, each, extend, keys, noop } from 'zrender/src/core/util'  -> ZRenderKit `util`
//   - `bind(fn, ctx)` is unnecessary: a method "slot" is a stored closure that already captures its
//     owner, so copying a slot preserves its binding.
//   - `extend(target, methods)` (mounting a static method bag onto a plain object) becomes
//     per-instance closure assignment (the upstream method bodies use `this`, captured here).
// upstream: import { initExtentForUnion, isValidBoundsForExtent } from '../util/model'  -> EChartsKit `model`
// upstream: import { NullUndefined } from '../util/types'  -> Optional (CONVENTIONS §6)
// upstream: import { error } from '../util/log'  -> EChartsKit `log.error`
// upstream: import { AxisBreakParsingResult, BreakScaleMapper, getScaleBreakHelper } from './break'  -> scale/break.swift
// upstream: import type { ValueTransformLookupOpt } from './helper'  -> scale/helper.swift
// upstream: import { DataSanitizationFilter } from '../data/helper/dataValueHelper'
//   `DataSanitizationFilter` is owned by data/helper/dataValueHelper.ts (not yet translated);
//   a minimal forward-declared shim lives in the fenced PORT-TODO block at the bottom of this file.
//
// PORT-TODO (the central deviation of this file): upstream models `ScaleMapper`/`LinearScaleMapper`/
//   `BreakScaleMapper` as TS *interfaces* whose method set is **dynamically mounted at runtime** onto
//   plain objects (and onto `Scale` subclass instances) via `bind`/`extend`/`each(SCALE_MAPPER_METHOD_NAMES)`.
//   Swift has no string-keyed dynamic method assignment, so `ScaleMapper` is a base `class` whose methods
//   are stored-closure "slots"; "mounting" assigns those slots. `BreakScaleMapper` (scale/break.swift)
//   and `Scale` (scale/Scale.swift) subclass it so the slots are inherited/reusable. The
//   `each(SCALE_MAPPER_METHOD_NAMES)` loops are kept, with a per-name `switch` standing in for the
//   `obj[methodName]` dynamic indexing.
// PORT-TODO: CONVENTIONS §2 prefers a `enum scaleMapper` namespace for the free functions, but every
//   sibling scale (Interval/Time/Ordinal/Log) calls these unqualified, so they are bare top-level funcs.


// ------ START: Scale Mapper Core ------

/**
 * Illustration:
 *  SCALE_EXTENT_KIND_EFFECTIVE:     |------------|     (always exist)
 *  SCALE_EXTENT_KIND_MAPPING:   |---|------------|--|  (present only when it is specified by `setExtent2`)
 *
 *  - [SCALE_EXTENT_KIND_EFFECTIVE]:
 *    It is a portion of a scale extent that is functional on most features, including:
 *      - All tick/label-related calculation.
 *      - `dataZoom` controlled ends.
 *      - Cartesian2D `clampData`.
 *      - line series start.
 *      - heatmap series range.
 *      - markerArea range.
 *      - etc.
 *    `SCALE_EXTENT_KIND_EFFECTIVE` always exists.
 *
 *  - [SCALE_EXTENT_KIND_MAPPING]:
 *    It is an expanded extent from ends of `SCALE_EXTENT_KIND_EFFECTIVE` to accommodate shapes at edges to
 *    avoid overflow. They can be typically used by bar/candlestick series on category axis with
 *    `boundaryGap: false`, or on other numeric axes. ec option `xxxAxis.containShape` is the switch.
 *    In this case, we need to:
 *      - Do not render ticks and labels in the portion "SCALE_EXTENT_KIND_MAPPING - SCALE_EXTENT_KIND_EFFECTIVE",
 *        since they are considered meaningless there.
 *      - Prevent "nice strategy" from triggering unexpectedly by the "contain shape expansion".
 *        Otherwise, for example, the original extent is `[0, 1000]`, then the expanded
 *        extent, say `[-5, 1000]`, can cause a considerable negative expansion by "nice",
 *        like `[-200, 10000]`, which is commonly unexpected. And it is exacerbated in LogScale.
 *      - Prevent the min/max tick label from displaying, since they are commonly meaningless
 *        and probably misleading.
 *    Therefore, `SCALE_EXTENT_KIND_MAPPING` is only used for:
 *      - mapping between data and pixel, such as,
 *        - `scaleMapper.normalize/scale`;
 *        - Cartesian2D `calcAffineTransform` (a quick path of `scaleMapper.normalize/scale`).
 *      - `grid` boundary related calculation in view rendering, such as, `barGrid` calculates
 *        `barWidth` for numeric scales based on the data extent.
 *      - Axis line position determination (such as `canOnZeroToAxis`);
 *      - `axisPointer` triggering (otherwise users may be confused if using `SCALE_EXTENT_KIND_EFFECTIVE`).
 *    `SCALE_EXTENT_KIND_MAPPING` can be absent, which can be used to determine whether it is used.
 *
 * @see SCALE_EXTENT_CONSTRUCTION for the full processing flow.
 */
// PORT-TODO: `ScaleExtentKind = 0 | 1` modeled as `Int` (a genuine array index into `_extents`, CONVENTIONS §7).
public typealias ScaleExtentKind = Int
public let SCALE_EXTENT_KIND_EFFECTIVE: ScaleExtentKind = 0
public let SCALE_EXTENT_KIND_MAPPING: ScaleExtentKind = 1


// upstream: const SCALE_MAPPER_METHOD_NAMES_MAP: Record<keyof ScaleMapper, 1> = {...}
//   `Record<..., 1>` -> `[String: Int]`; the values are an unused marker constant `1`.
private let SCALE_MAPPER_METHOD_NAMES_MAP: [String: Int] = [
    "needTransform": 1,
    "normalize": 1,
    "scale": 1,
    "transformIn": 1,
    "transformOut": 1,
    "contain": 1,
    "getExtent": 1,
    "getExtentUnsafe": 1,
    "setExtent": 1,
    "setExtent2": 1,
    "getFilter": 1,
    "sanitize": 1,
    "getDefaultStartValue": 1,
    "freeze": 1,
]
// PORT-TODO: Swift dictionary key order is nondeterministic; the iteration order of
//   SCALE_MAPPER_METHOD_NAMES is not load-bearing (every consumer just visits all names).
private let SCALE_MAPPER_METHOD_NAMES = util.keys(SCALE_MAPPER_METHOD_NAMES_MAP)

/**
 * - [SCALE_MAPPER_DEPTH_OUT_OF_BREAK]:
 *   In `transformIn`, it transforms a value from the outermost space to the space before break being applied.
 *   In `transformOut`, it transforms a value from the space before break being applied to the outermost space.
 *   Typically nice axis ticks are picked in that space due to the current design of nice ticks
 *   algorithm, while size related features may use `SCALE_MAPPER_DEPTH_INNERMOST`.
 * - [SCALE_MAPPER_DEPTH_INNERMOST]:
 *   Currently only linear space is used as the innermost space.
 */
public struct ScaleMapperDepthOpt {
    // depth: NullUndefined | SCALE_MAPPER_DEPTH_OUT_OF_BREAK | SCALE_MAPPER_DEPTH_INNERMOST
    public var depth: Double?
    public init(depth: Double? = nil) { self.depth = depth }
}
public let SCALE_MAPPER_DEPTH_OUT_OF_BREAK: Double = 2
public let SCALE_MAPPER_DEPTH_INNERMOST: Double = 3

// upstream: type ScaleMapperTransformOutOpt = ScaleMapperDepthOpt & ValueTransformLookupOpt
//   (TS intersection -> flattened struct; `depth: NullUndefined` means SCALE_MAPPER_DEPTH_INNERMOST).
public struct ScaleMapperTransformOutOpt {
    public var depth: Double?
    public var lookup: ValueTransformLookupOpt.Lookup?
    public init(depth: Double? = nil, lookup: ValueTransformLookupOpt.Lookup? = nil) {
        self.depth = depth
        self.lookup = lookup
    }
}
// upstream: type ScaleMapperTransformInOpt = ScaleMapperDepthOpt
//   (depth: NullUndefined means SCALE_MAPPER_DEPTH_INNERMOST).
public typealias ScaleMapperTransformInOpt = ScaleMapperDepthOpt

/**
 * @tutorial [SCALE_COMPOSITION_AND_TRANSFORMATION]:
 *  `ScaleMapper` is designed for multiple steps of numeric transformations from a certain space to a linear space,
 *  or vice versa. Each step is implemented as a `ScaleMapper`, and composed like a decorator pattern. And some
 *  steps, such as "axis breaks transfromation", can be skipped when no breaks for performance consideration.
 *  Currently we support:
 *    - step#0: extent based linear scaling. (`LinearScaleMapper`)
 *    - step#1: axis breaks. (`BreakScaleMapper`; absent if no breaks)
 *    - step#2: logarithmic (`LogScale`), or ordinal-related handling, or others such as asinh ...
 *
 * @tutorial [SCALE_EXTENT_CONSTRUCTION]:
 *  The full construction processing of the scale extent in EC_FULL_UPDATE_CYCLE:
 *  - step#1. At `CoordinateSystem#create` stage, `Scale` instances are created.
 *  - step#2. `scaleRawExtentInfoCreate` collects series data extent.
 *  - step#3. Perform "nice"/"align" strategies.
 *  - step#4. `calcContainShape`; set `SCALE_EXTENT_KIND_MAPPING` if needed.
 */
// upstream: interface ScaleMapper extends ScaleMapperGeneric<ScaleMapper> {}
//   interface ScaleMapperGeneric<This> { needTransform; normalize; scale; transformIn; transformOut;
//     contain; getExtent; getExtentUnsafe; setExtent; setExtent2; getFilter?; sanitize?;
//     getDefaultStartValue?; freeze; }
// PORT-TODO: modeled as a base `public` (not `open`) class of stored-closure "method slots" — see the
//   file-level note. The `<This>` self-type collapses (closures capture their owner). Required slots are
//   IUO (assigned at construction by `initLinearScaleMapper` / `decorateScaleMapper` / break decoration);
//   invoking one before it is mounted traps, mirroring "calling an undefined method" in JS.
// PORT-TODO: declared `open` (not just `public`) because the sibling `open class Scale` subclasses it,
//   and an `open` class requires an `open` superclass.
open class ScaleMapper {

    /**
     * Enable a fast path in large data traversal - the call of `transformIn`/`transformOut`
     * can be omitted, and this is the most case.
     */
    public var needTransform: (() -> Bool)!

    /**
     * Normalize a value to linear [0, 1], return 0.5 if extent span is 0.
     */
    public var normalize: ((_ val: Double) -> Double)!

    /**
     * Scale a normalized value to extent. It's the inverse of `normalize`.
     */
    public var scale: ((_ val: Double) -> Double)!

    /**
     * Transform a value forward into a inner space.
     * [NOTICE]: Must be available since the instance is constructed; has nothing to do with extent.
     */
    public var transformIn: ((_ val: Double, _ opt: ScaleMapperTransformInOpt?) -> Double)!

    /**
     * The inverse method of `transformIn`.
     */
    public var transformOut: ((_ val: Double, _ opt: ScaleMapperTransformOutOpt?) -> Double)!

    /**
     * Whether the extent contains the given value.
     */
    public var contain: ((_ val: Double) -> Bool)!

    /**
     * Get a clone of the scale extent. An extent is always in an increase order; never null.
     */
    public var getExtent: (() -> [Double])!

    /**
     * [NOTICE]: Callers must NOT modify the return.  (depth: NullUndefined means the outermost space.)
     */
    public var getExtentUnsafe: ((_ kind: ScaleExtentKind, _ depth: Double?) -> [Double]?)!

    /**
     * [NOTICE]: The caller must ensure `start <= end` and both are finite number!
     * `setExtent` is identical to `setExtent2(SCALE_EXTENT_KIND_EFFECTIVE)`.
     */
    public var setExtent: ((_ start: Double, _ end: Double) -> Void)!
    public var setExtent2: ((_ kind: ScaleExtentKind, _ start: Double, _ end: Double) -> Void)!

    /** Filter for sanitization. (Optional method — nil when not mounted.) */
    public var getFilter: (() -> DataSanitizationFilter)?

    /** Sanitize a value if possible. (Optional method — nil when not mounted.) */
    public var sanitize: ((_ value: Double?, _ dataExtent: [Double]) -> Double?)?

    /** If not provided, use `0`. (Optional method — nil when not mounted.) */
    public var getDefaultStartValue: (() -> Double)?

    /**
     * Restrict the modification behavior of a scale for robustness.
     */
    public var freeze: (() -> Void)!

    // ------------------------------------------------------------------------
    // PORT-TODO: upstream `interface LinearScaleMapper extends ScaleMapper` declares the two fields below;
    //   folded onto this base class because `initLinearScaleMapper` decorates the same instance in place.
    /**
     * [CAVEAT]:
     *  - Should update only by `setExtent` or `setExtent2`!
     *  - The caller of `setExtent()` should ensure `extent[0] <= extent[1]`,
     *    but it is initialized as `[Infinity, -Infinity]`.
     * Structure: `_extents[ScaleExtentKind][]`
     */
    // PORT-TODO: upstream `readonly _extents: number[][]` is SPARSE (index 0 always set, index 1 set only
    //   by setExtent2). Modeled as a fixed length-2 `[[Double]?]` so `_extents[kind]` reads/writes are
    //   Swift-safe (an absent slot reads as nil, matching JS `undefined`).
    internal var _extents: [[Double]?] = [nil, nil]
    internal var _frozen: Bool = false

    public init() {}
}

public func initBreakOrLinearMapper(
    // If input `null/undefined`, a mapper will be created.
    _ mapper: ScaleMapper?,
    _ breakParsed: AxisBreakParsingResult?,
    _ initialExtent: [Double]?
) -> (brk: BreakScaleMapper?, mapper: ScaleMapper) {
    var brk: BreakScaleMapper?
    let mapper = mapper ?? ScaleMapper()

    let scaleBreakHelper = getScaleBreakHelper()
    if let scaleBreakHelper = scaleBreakHelper {

        let brkMapper = scaleBreakHelper.createBreakScaleMapper(breakParsed, initialExtent)

        if brkMapper.hasBreaks() {
            // Some `ScaleMapper` methods (such as `normalize`) needs to be fast for large data
            // when no breaks, so mount break methods only when breaks really exist.
            util.each(SCALE_MAPPER_METHOD_NAMES) { methodName, _ in
                // upstream: if (brkMapper[methodName]) mapper[methodName] = bind(brkMapper[methodName], brkMapper);
                //   `bind(.., brkMapper)` is unnecessary — brkMapper's slot closures already capture brkMapper.
                mountBreakMapperMethod(methodName, brkMapper, mapper)
            }
            brk = brkMapper
        }
    }

    if brk == nil {
        _ = initLinearScaleMapper(mapper, initialExtent)
    }

    return (brk, mapper)
}

// upstream: type DecoratedScaleMapperMethods<THost extends ScaleMapper> = Omit<ScaleMapperGeneric<THost>, 'freeze'>;
// PORT-TODO: the `<THost>` self-type collapses — the sibling scales build this via a per-host factory
//   (e.g. `OrdinalScale.decoratedMethods(this)`) whose closures capture `this`, so the slots here take
//   only the value args (no explicit host). Member/init order mirrors upstream `ScaleMapperGeneric`
//   (minus `freeze`); the trailing optional three default to nil.
public struct DecoratedScaleMapperMethods {
    public var needTransform: () -> Bool
    public var normalize: (_ val: Double) -> Double
    public var scale: (_ val: Double) -> Double
    public var transformIn: (_ val: Double, _ opt: ScaleMapperTransformInOpt?) -> Double
    public var transformOut: (_ val: Double, _ opt: ScaleMapperTransformOutOpt?) -> Double
    public var contain: (_ val: Double) -> Bool
    public var getExtent: () -> [Double]
    public var getExtentUnsafe: (_ kind: ScaleExtentKind, _ depth: Double?) -> [Double]?
    public var setExtent: (_ start: Double, _ end: Double) -> Void
    public var setExtent2: (_ kind: ScaleExtentKind, _ start: Double, _ end: Double) -> Void
    public var getFilter: (() -> DataSanitizationFilter)?
    public var sanitize: ((_ value: Double?, _ dataExtent: [Double]) -> Double?)?
    public var getDefaultStartValue: (() -> Double)?
    public init(
        needTransform: @escaping () -> Bool,
        normalize: @escaping (Double) -> Double,
        scale: @escaping (Double) -> Double,
        transformIn: @escaping (Double, ScaleMapperTransformInOpt?) -> Double,
        transformOut: @escaping (Double, ScaleMapperTransformOutOpt?) -> Double,
        contain: @escaping (Double) -> Bool,
        getExtent: @escaping () -> [Double],
        getExtentUnsafe: @escaping (ScaleExtentKind, Double?) -> [Double]?,
        setExtent: @escaping (Double, Double) -> Void,
        setExtent2: @escaping (ScaleExtentKind, Double, Double) -> Void,
        getFilter: (() -> DataSanitizationFilter)? = nil,
        sanitize: ((Double?, [Double]) -> Double?)? = nil,
        getDefaultStartValue: (() -> Double)? = nil
    ) {
        self.needTransform = needTransform
        self.normalize = normalize
        self.scale = scale
        self.transformIn = transformIn
        self.transformOut = transformOut
        self.contain = contain
        self.getExtent = getExtent
        self.getExtentUnsafe = getExtentUnsafe
        self.setExtent = setExtent
        self.setExtent2 = setExtent2
        self.getFilter = getFilter
        self.sanitize = sanitize
        self.getDefaultStartValue = getDefaultStartValue
    }
}

public func decorateScaleMapper(
    _ host: ScaleMapper,
    _ decoratedMapperMethods: DecoratedScaleMapperMethods
) {
    util.each(SCALE_MAPPER_METHOD_NAMES) { methodName, _ in
        // upstream: host[methodName] = decoratedMapperMethods[methodName];
        assignDecoratedMapperMethod(methodName, decoratedMapperMethods, host)
    }
}

public func enableScaleMapperFreeze(_ host: ScaleMapper, _ subMapper: ScaleMapper) {
    host.freeze = util.noop
    if __DEV__ {
        host.freeze = {
            subMapper.freeze() // PORT-TODO: verify capture — subMapper captured strongly (mirrors upstream).
        }
    }
}

public func getScaleExtentForTickUnsafe(_ mapper: ScaleMapper) -> [Double] {
    // EFFECTIVE always exists, so the optional return is force-unwrapped.
    return mapper.getExtentUnsafe(SCALE_EXTENT_KIND_EFFECTIVE, SCALE_MAPPER_DEPTH_OUT_OF_BREAK)!
}

public func getScaleExtentForMappingUnsafe(
    _ mapper: ScaleMapper,
    // NullUndefined means the outermost space.
    _ depth: Double?
) -> [Double] {
    return mapper.getExtentUnsafe(SCALE_EXTENT_KIND_MAPPING, depth)
        ?? mapper.getExtentUnsafe(SCALE_EXTENT_KIND_EFFECTIVE, depth)!
}

public func getScaleLinearSpanForMapping(_ mapper: ScaleMapper) -> Double {
    let extent = getScaleExtentForMappingUnsafe(mapper, SCALE_MAPPER_DEPTH_INNERMOST)
    return extent[1] - extent[0]
}

public func getScaleLinearSpanEffective(_ mapper: ScaleMapper) -> Double {
    let extent = mapper.getExtentUnsafe(SCALE_EXTENT_KIND_EFFECTIVE, SCALE_MAPPER_DEPTH_INNERMOST)!
    return extent[1] - extent[0]
}

// PORT-TODO: name-keyed slot copy/assignment helpers. Upstream copies via `obj[methodName]` dynamic
//   indexing; Swift has no string-keyed access to typed stored properties, so the
//   `each(SCALE_MAPPER_METHOD_NAMES)` loop body switches on the name. The `if (brkMapper[methodName])`
//   presence guard becomes a per-slot `!= nil` check.
private func mountBreakMapperMethod(_ methodName: String, _ brkMapper: BreakScaleMapper, _ mapper: ScaleMapper) {
    switch methodName {
    case "needTransform": if brkMapper.needTransform != nil { mapper.needTransform = brkMapper.needTransform }
    case "normalize": if brkMapper.normalize != nil { mapper.normalize = brkMapper.normalize }
    case "scale": if brkMapper.scale != nil { mapper.scale = brkMapper.scale }
    case "transformIn": if brkMapper.transformIn != nil { mapper.transformIn = brkMapper.transformIn }
    case "transformOut": if brkMapper.transformOut != nil { mapper.transformOut = brkMapper.transformOut }
    case "contain": if brkMapper.contain != nil { mapper.contain = brkMapper.contain }
    case "getExtent": if brkMapper.getExtent != nil { mapper.getExtent = brkMapper.getExtent }
    case "getExtentUnsafe": if brkMapper.getExtentUnsafe != nil { mapper.getExtentUnsafe = brkMapper.getExtentUnsafe }
    case "setExtent": if brkMapper.setExtent != nil { mapper.setExtent = brkMapper.setExtent }
    case "setExtent2": if brkMapper.setExtent2 != nil { mapper.setExtent2 = brkMapper.setExtent2 }
    case "getFilter": if brkMapper.getFilter != nil { mapper.getFilter = brkMapper.getFilter }
    case "sanitize": if brkMapper.sanitize != nil { mapper.sanitize = brkMapper.sanitize }
    case "getDefaultStartValue": if brkMapper.getDefaultStartValue != nil { mapper.getDefaultStartValue = brkMapper.getDefaultStartValue }
    case "freeze": if brkMapper.freeze != nil { mapper.freeze = brkMapper.freeze }
    default: break
    }
}

private func assignDecoratedMapperMethod(
    _ methodName: String, _ d: DecoratedScaleMapperMethods, _ host: ScaleMapper
) {
    switch methodName {
    case "needTransform": host.needTransform = d.needTransform
    case "normalize": host.normalize = d.normalize
    case "scale": host.scale = d.scale
    case "transformIn": host.transformIn = d.transformIn
    case "transformOut": host.transformOut = d.transformOut
    case "contain": host.contain = d.contain
    case "getExtent": host.getExtent = d.getExtent
    case "getExtentUnsafe": host.getExtentUnsafe = d.getExtentUnsafe
    case "setExtent": host.setExtent = d.setExtent
    case "setExtent2": host.setExtent2 = d.setExtent2
    case "getFilter": host.getFilter = d.getFilter
    case "sanitize": host.sanitize = d.sanitize
    case "getDefaultStartValue": host.getDefaultStartValue = d.getDefaultStartValue
    // upstream: `decoratedMapperMethods['freeze']` is `undefined` (Omit<..., 'freeze'>) so host.freeze is cleared.
    case "freeze": host.freeze = nil
    default: break
    }
}

// ------ END: Scale Mapper Core ------


// ------ START: Linear Scale Mapper ------

/**
 * Generally, no need to export `LinearScaleMapper` and not recommended
 * to visit `_extent` directly outside - use `getExtentUnsafe()` instead.
 */
// PORT-TODO: upstream `interface LinearScaleMapper extends ScaleMapper { _extents; _frozen }` — the
//   `_extents`/`_frozen` storage lives on the base `ScaleMapper` class (see there).

public func initLinearScaleMapper(
    // If input `null/undefined`, a mapper will be created.
    _ mapper: ScaleMapper?,
    _ initialExtent: [Double]?
) -> ScaleMapper {
    let linearMapper = mapper ?? ScaleMapper()

    // upstream: const extendList: number[][] = []; linearMapper._extents = extendList;
    //   modeled as the pre-sized length-2 `[[Double]?]` on the instance (see `_extents` PORT-TODO).
    linearMapper._extents = [nil, nil]

    // `.slice()` -> value-type array copy on assignment.
    linearMapper._extents[SCALE_EXTENT_KIND_EFFECTIVE] =
        initialExtent != nil ? initialExtent! : model.initExtentForUnion()

    applyLinearScaleMapperMethods(linearMapper) // upstream: extend(linearMapper, linearScaleMapperMethods)

    return linearMapper
}

// upstream: const linearScaleMapperMethods: ScaleMapperGeneric<LinearScaleMapper> = { ... }
//   The static method bag cannot be modeled as-is because each body uses `this`. We assign the
//   slots as per-instance closures that capture `mapper` (as `this`).
// PORT-TODO: `[unowned mapper]` breaks the retain cycle (the mapper owns the closures, the closures
//   capture the mapper); safe because the closures never outlive the mapper.
private func applyLinearScaleMapperMethods(_ mapper: ScaleMapper) {

    mapper.needTransform = {
        return false
    }

    mapper.normalize = { [unowned mapper] val in
        let extent = mapper._extents[SCALE_EXTENT_KIND_MAPPING] ?? mapper._extents[SCALE_EXTENT_KIND_EFFECTIVE]!
        if extent[1] == extent[0] {
            return 0.5
        }
        return (val - extent[0]) / (extent[1] - extent[0])
    }

    mapper.scale = { [unowned mapper] val in
        let extent = mapper._extents[SCALE_EXTENT_KIND_MAPPING] ?? mapper._extents[SCALE_EXTENT_KIND_EFFECTIVE]!
        return val * (extent[1] - extent[0]) + extent[0]
    }

    mapper.transformIn = { val, _ in
        return val
    }

    mapper.transformOut = { val, _ in
        return val
    }

    mapper.contain = { [unowned mapper] val in
        // This method is typically used in axis trigger and markers.
        // Users may be confused if the extent is restricted to `SCALE_EXTENT_KIND_EFFECTIVE`.
        let extent = getScaleExtentForMappingUnsafe(mapper, nil)
        return val >= extent[0] && val <= extent[1]
    }

    mapper.getExtent = { [unowned mapper] in
        return mapper._extents[SCALE_EXTENT_KIND_EFFECTIVE]! // .slice() -> value copy
    }

    mapper.getExtentUnsafe = { [unowned mapper] kind, _ in
        return mapper._extents[kind]
    }

    mapper.setExtent = { [unowned mapper] start, end in
        if __DEV__ {
            util.assert(!mapper._frozen)
        }
        writeExtent(mapper, SCALE_EXTENT_KIND_EFFECTIVE, start, end)
    }

    mapper.setExtent2 = { [unowned mapper] kind, start, end in
        if __DEV__ {
            util.assert(!mapper._frozen)
        }
        // upstream: const extentList = this._extents; if (!extentList[kind]) extentList[kind] = extentList[EFFECTIVE].slice();
        if mapper._extents[kind] == nil {
            mapper._extents[kind] = mapper._extents[SCALE_EXTENT_KIND_EFFECTIVE]!
        }
        writeExtent(mapper, kind, start, end)
    }

    mapper.freeze = { [unowned mapper] in
        if __DEV__ {
            mapper._frozen = true
        }
    }
}

// PORT-TODO: upstream `writeExtent(extentList: number[][], kind, start, end)` mutates the passed
//   `number[][]` by reference; a Swift `[[Double]?]` is a value type, so we pass the owning
//   `ScaleMapper` (reference type) and mutate `mapper._extents` instead.
private func writeExtent(
    _ mapper: ScaleMapper, _ kind: ScaleExtentKind, _ start: Double, _ end: Double
) {
    // NOTE: `NaN` should be excluded. e.g., `scaleRawExtentInfo.resultMinMax` may be `[NaN, NaN]`.
    if model.isValidBoundsForExtent(start, end) {
        mapper._extents[kind]![0] = start
        mapper._extents[kind]![1] = end
    }
    else {
        if __DEV__ {
            // PENDING: should use `assert` after fixing all invalid calls.
            // PORT-TODO: upstream `start != null && end != null` — start/end are non-optional Double here.
            if !start.isNaN && !end.isNaN && start <= end {
                log.error("Invalid setExtent call - start: \(start), end: \(end)")
            }
        }
    }
}

// ------ END: Linear Scale Mapper ------

// NOTE: the former `DataSanitizationFilter` forward-declaration placeholder was removed;
//   the real type is now defined in data/helper/dataValueHelper.swift.
