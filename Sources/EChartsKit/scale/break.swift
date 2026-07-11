// Ported from echarts/src/scale/break.ts — keep in sync with upstream
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

// upstream imports (types resolved from Tier1 `util/types.swift`, sibling scale modules, and the
// forward-declared placeholder at the bottom of this file — see CONVENTIONS §2 / §6):
// import { AxisLabelFormatterExtraParams } from '../coord/axisCommonTypes';
// import type {
//     NullUndefined, ParsedAxisBreak, ParsedAxisBreakList, AxisBreakOption,
//     AxisBreakOptionIdentifierInAxis, ScaleTick, VisualAxisBreak,
// } from '../util/types';
// import { ValueTransformLookupOpt } from './helper';     -> sibling scale/helper.swift (ValueTransformLookupOpt.Lookup)
// import type Scale from './Scale';                       -> sibling scale/Scale.swift (Scale)
// import { ScaleMapper } from './scaleMapper';            -> sibling scale/scaleMapper.swift (class ScaleMapper)

/**
 * @file The facade of scale break.
 *  Separate the impl to reduce code size.
 *
 * @caution
 *  Must not import `scale/breakImpl.ts` directly or indirectly.
 *  Must not implement anything in this file.
 */


// upstream: `export interface BreakScaleMapper extends ScaleMapper { ... }`.
//   The sibling `scaleMapper.swift` models `ScaleMapper` as a base `class` (per-instance closure
//   method-slots), so `BreakScaleMapper` is a subclass (not a protocol) so its slots are reusable and
//   `createBreakScaleMapper` can return it polymorphically. The concrete behavior lives in
//   `scale/breakImpl.swift` (BreakScaleMapperImpl) — the bodies here are unreachable base placeholders.
// NOTE: `public` (not `open`) — the sibling base `ScaleMapper` is `public class` (not `open`), and a
//   within-module subclass (scale/breakImpl.swift) can override `public` members without `open`.
public class BreakScaleMapper: ScaleMapper {

    // upstream: readonly breaks: ParsedAxisBreakList;
    public var breaks: ParsedAxisBreakList { [] }   // PORT-NOTE: overridden by BreakScaleMapperImpl in scale/breakImpl.swift

    public func hasBreaks() -> Bool {
        return false                                // PORT-NOTE: overridden by BreakScaleMapperImpl in scale/breakImpl.swift
    }

    public func calcNiceTickMultiple(
        _ tickVal: Double,
        _ estimateNiceMultiple: (_ tickVal: Double, _ brkEnd: Double) -> Double
    ) -> Double {
        return 0                                    // PORT-NOTE: overridden by BreakScaleMapperImpl in scale/breakImpl.swift
    }

    public override init() { super.init() }
}

// upstream: export type AxisBreakParsingResult = { breaks: ParsedAxisBreakList };
public struct AxisBreakParsingResult {
    public var breaks: ParsedAxisBreakList
    public init(breaks: ParsedAxisBreakList) {
        self.breaks = breaks
    }
}

// upstream: export type ParseBreakOptionOpt = { noNegative?: boolean };
public struct ParseBreakOptionOpt {
    public var noNegative: Bool?
    public init(noNegative: Bool? = nil) {
        self.noNegative = noNegative
    }
}

// upstream: export type ParseAxisBreakOptionInwardTransformOut = {
//     lookup: ValueTransformLookupOpt['lookup'];
//     original?: AxisBreakParsingResult;
//     transformed?: AxisBreakParsingResult;
// };
public struct ParseAxisBreakOptionInwardTransformOut {
    // upstream: ValueTransformLookupOpt['lookup'] (`{from, to} | NullUndefined`).
    public var lookup: ValueTransformLookupOpt.Lookup?
    public var original: AxisBreakParsingResult?
    public var transformed: AxisBreakParsingResult?
    public init(
        lookup: ValueTransformLookupOpt.Lookup? = nil,
        original: AxisBreakParsingResult? = nil,
        transformed: AxisBreakParsingResult? = nil
    ) {
        self.lookup = lookup
        self.original = original
        self.transformed = transformed
    }
}

/**
 * Whether to remove any normal ticks that are too close to axis breaks.
 *  - 'auto': Default. Remove any normal ticks that are too close to axis breaks.
 *  - 'no': Do nothing pruning.
 *  - 'exclude_scale_bound': Prune but keep scale extent boundary.
 * For example:
 *  - For splitLine, if remove the tick on extent, split line on the boundary of cartesian
 *   will not be displayed, causing weird effect.
 *  - For labels, scale extent boundary should be pruned if in break, otherwise duplicated
 *   labels will displayed.
 */
// upstream: export type ParamPruneByBreak = 'auto' | 'no' | 'preserve_extent_bound' | NullUndefined;
// PORT-NOTE: the TS string-literal union (incl. its `NullUndefined` arm) is modeled as `String`
//   (optional at use sites), so call sites pass raw strings like `"auto"` (CONVENTIONS §6).
public typealias ParamPruneByBreak = String

// upstream: type BreakScaleHelper = { ...methods }; modeled as a protocol contract (CONVENTIONS §2).
//   The concrete impl is `scale/breakImpl.ts` (deferred) and is registered via
//   `registerScaleBreakHelperImpl`; until then `break.getScaleBreakHelper()` returns `nil`.
public protocol BreakScaleHelper {
    func createBreakScaleMapper(
        _ breakParsed: AxisBreakParsingResult?,
        _ initialExtent: [Double]?
    ) -> BreakScaleMapper
    // upstream: pruneTicksByBreak<TItem extends ScaleTick | number>(...): void  (mutates `ticks`).
    // PORT-NOTE: the `TItem extends ScaleTick | number` constraint is a TS union and cannot be
    //   expressed as a Swift generic constraint; left unconstrained. `ticks` is `inout` (the upstream
    //   `void` return mutates the array in place — CONVENTIONS §3).
    func pruneTicksByBreak<TItem>(
        _ pruneByBreak: ParamPruneByBreak?,
        _ ticks: inout [TItem],
        _ breaks: ParsedAxisBreakList,
        _ getValue: (_ item: TItem) -> Double,
        _ interval: Double,
        _ scaleExtent: [Double]
    )
    // upstream: addBreaksToTicks(ticks, ...): void  (pushes break ticks into `ticks`) -> `inout`.
    //   getTimeProps?: (clampedBrk) => ScaleTick['time']  (ScaleTick['time'] is `TimeScaleTickTime?`).
    func addBreaksToTicks(
        _ ticks: inout [ScaleTick],
        _ breaks: ParsedAxisBreakList,
        _ scaleExtent: [Double],
        _ getTimeProps: ((_ clampedBrk: ParsedAxisBreak) -> TimeScaleTickTime?)?
    )
    func parseAxisBreakOption(
        // raw user input breaks, retrieved from axis model.
        _ breakOptionList: [AxisBreakOption]?,
        // upstream: scale: {parse: Scale['parse']} (a structural subset of `Scale`).
        // PORT-NOTE: upstream narrows to the structural `{parse}`; Swift's IUO `Scale.parse` stored
        //   property cannot satisfy a non-optional protocol requirement, so we accept the concrete
        //   `Scale` (the only type passed in practice).
        _ scale: Scale,
        // upstream: opt?: { noNegative: boolean }
        // PORT-NOTE: upstream's inline opt requires `noNegative`; reuse `ParseBreakOptionOpt` (optional field).
        _ opt: ParseBreakOptionOpt?
    ) -> AxisBreakParsingResult
    func identifyAxisBreak(
        _ brk: AxisBreakOption,
        _ identifier: AxisBreakOptionIdentifierInAxis
    ) -> Bool
    func serializeAxisBreakIdentifier(
        _ identifier: AxisBreakOptionIdentifierInAxis
    ) -> String
    // upstream: retrieveAxisBreakPairs<TItem, TReturnIdx extends boolean>(...): TReturnIdx extends false
    //   ? TItem[][] : number[][]
    // PORT-NOTE: the conditional return type (`TItem[][] | number[][]` keyed on `returnIdx`) cannot be
    //   expressed in Swift; returns `[[Any]]` and the `TReturnIdx` type parameter is dropped.
    func retrieveAxisBreakPairs<TItem>(
        _ itemList: [TItem],
        _ getVisualAxisBreak: (_ item: TItem) -> VisualAxisBreak?,
        _ returnIdx: Bool
    ) -> [[Any]]
    func getTicksBreakOutwardTransform(
        _ scale: ScaleMapper,
        _ tick: ScaleTick,
        _ outermostBreaks: ParsedAxisBreakList,
        _ lookup: ValueTransformLookupOpt.Lookup?
    ) -> (tickVal: Double?, vBreak: VisualAxisBreak?)?
    // upstream: out: ParseAxisBreakOptionInwardTransformOut is written in place → `inout` (CONVENTIONS §3).
    func parseAxisBreakOptionInwardTransform(
        _ breakOptionList: [AxisBreakOption]?,
        _ scale: Scale,
        _ parseOpt: ParseBreakOptionOpt,
        _ lookupStartIdx: Double,
        _ out: inout ParseAxisBreakOptionInwardTransformOut
    )
    func makeAxisLabelFormatterParamBreak(
        _ extraParam: AxisLabelFormatterExtraParams?,
        _ vBreak: VisualAxisBreak?
    ) -> AxisLabelFormatterExtraParams?
}

// upstream: the inline `opt` object of `simplyParseBreakOption`:
//   { breakOption?: AxisBreakOption[] | NullUndefined; breakParsed?: AxisBreakParsingResult | NullUndefined; }
public struct SimplyParseBreakOptionOpt {
    public var breakOption: [AxisBreakOption]?
    public var breakParsed: AxisBreakParsingResult?
    public init(
        breakOption: [AxisBreakOption]? = nil,
        breakParsed: AxisBreakParsingResult? = nil
    ) {
        self.breakOption = breakOption
        self.breakParsed = breakParsed
    }
}

// upstream `break.ts` uses named-export free functions (`import { getScaleBreakHelper } from './break'`),
// so the faithful, byte-identical form is **top-level** functions (CONVENTIONS §2). These are the
// canonical declarations.
//
// NOTE: some sibling consumers (e.g. `minorTicks.swift`) instead spell call sites through a caseless
//   enum namespace `` `break` `` (CONVENTIONS §2's `import * as` form). To support both spellings the
//   enum below forwards to these top-level functions; `break` is a Swift keyword, hence backticks.

private var _impl: BreakScaleHelper? = nil

public func registerScaleBreakHelperImpl(_ impl: BreakScaleHelper) {
    if _impl == nil {
        _impl = impl
    }
}

public func getScaleBreakHelper() -> BreakScaleHelper? {
    return _impl
}

public func simplyParseBreakOption(
    // upstream: scale: {parse: Scale['parse']} (a structural subset of `Scale`).
    // PORT-NOTE: upstream narrows to `{parse}`; we accept the concrete `Scale` (see
    //   `BreakScaleHelper.parseAxisBreakOption`).
    _ scale: Scale,
    _ opt: SimplyParseBreakOptionOpt
) -> AxisBreakParsingResult? {
    let scaleBreakHelper = getScaleBreakHelper()
    let breakOption = opt.breakOption
    var breakParsed = opt.breakParsed
    if breakParsed == nil, let scaleBreakHelper = scaleBreakHelper {
        breakParsed = scaleBreakHelper.parseAxisBreakOption(breakOption, scale, nil)
    }
    return breakParsed
}

public func getBreaksUnsafe(_ scale: Scale) -> ParsedAxisBreakList {
    let brk = scale.brk
    return brk != nil ? brk!.breaks : []
}

public func hasBreaks(_ scale: Scale) -> Bool {
    let brk = scale.brk
    return brk != nil ? brk!.hasBreaks() : false
}

// Namespace-form forwarders (see NOTE above) so `` `break`.getScaleBreakHelper() `` call sites resolve.
public enum `break` {
    public static func registerScaleBreakHelperImpl(_ impl: BreakScaleHelper) {
        EChartsKit.registerScaleBreakHelperImpl(impl)
    }
    public static func getScaleBreakHelper() -> BreakScaleHelper? {
        return EChartsKit.getScaleBreakHelper()
    }
    public static func simplyParseBreakOption(
        _ scale: Scale, _ opt: SimplyParseBreakOptionOpt
    ) -> AxisBreakParsingResult? {
        return EChartsKit.simplyParseBreakOption(scale, opt)
    }
    public static func getBreaksUnsafe(_ scale: Scale) -> ParsedAxisBreakList {
        return EChartsKit.getBreaksUnsafe(scale)
    }
    public static func hasBreaks(_ scale: Scale) -> Bool {
        return EChartsKit.hasBreaks(scale)
    }
}


// ============================================================================
// Forward-declaration placeholder (PORT-NOTE).
//
// Declared here only so `break.swift` compiles where the real owner has not yet landed (mirrors the
// precedent in `Element.swift`). When the real file lands, DELETE this placeholder:
//   - AxisLabelFormatterExtraParams → coord/axisCommonTypes.ts (later phase)
//
// NOTE: `ScaleMapper` (scale/scaleMapper.swift, a base `class`), `Scale` (scale/Scale.swift), and
//   `ValueTransformLookupOpt` (scale/helper.swift) have already landed as sibling files this phase, so
//   this facade references the real types directly (their placeholders were removed from
//   scaleMapper.swift in favor of the canonical declarations above).
// ============================================================================

// upstream: coord/axisCommonTypes.ts
//   `AxisLabelFormatterExtraParams = {/* others if any */} & AxisLabelFormatterExtraBreakPart`.
//   The break part (`AxisLabelFormatterExtraBreakPartBreak`) is already in Tier1 `util/types.swift`.
// PORT-NOTE: forward-declared placeholder; replace with the real type in coord/axisCommonTypes.swift.
public struct AxisLabelFormatterExtraParams {
    public var `break`: AxisLabelFormatterExtraBreakPartBreak?
    public init(`break`: AxisLabelFormatterExtraBreakPartBreak? = nil) {
        self.`break` = `break`
    }
}
