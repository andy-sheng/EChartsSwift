// Ported from echarts/src/scale/breakImpl.ts — keep in sync with upstream
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

// upstream imports (resolved to sibling ported modules / Tier1 types):
//   import { assert, clone, each, filter, find, isString, map, trim } from 'zrender/src/core/util'
//                                                                    -> ZRenderKit `util`
//   import { NullUndefined, ParsedAxisBreak, ParsedAxisBreakList, AxisBreakOption,
//     AxisBreakOptionIdentifierInAxis, ScaleTick, VisualAxisBreak } from '../util/types'
//                                                                    -> EChartsKit util/types.swift
//   import { error } from '../util/log'                              -> EChartsKit `log.error`
//   import type Scale from './Scale'                                 -> scale/Scale.swift
//   import { AxisBreakParsingResult, registerScaleBreakHelperImpl, ParamPruneByBreak,
//     BreakScaleMapper, ParseBreakOptionOpt } from './break'         -> scale/break.swift
//   import { mathMax, mathMin, mathRound } from '../util/number'      -> EChartsKit `number.mathMax/...`
//   import { AxisLabelFormatterExtraParams } from '../coord/axisCommonTypes'
//                                                                    -> break.swift placeholder struct
//   import { DecoratedScaleMapperMethods, decorateScaleMapper, enableScaleMapperFreeze,
//     initLinearScaleMapper, SCALE_EXTENT_KIND_EFFECTIVE, SCALE_MAPPER_DEPTH_OUT_OF_BREAK,
//     ScaleMapper, ScaleMapperTransformOutOpt } from './scaleMapper' -> scale/scaleMapper.swift
//   import { isValidBoundsForExtent } from '../util/model'           -> EChartsKit `model`
//   import { ValueTransformLookupOpt } from './helper'               -> scale/helper.swift
//
// @caution (upstream): Must not export anything except `installScaleBreakHelper`.
//   In the port, `BreakScaleMapperImpl` and the free functions below are `internal`/`fileprivate`;
//   only `installScaleBreakHelper()` is `public`.

// upstream:
//   interface BreakScaleMapperImpl extends BreakScaleMapper { _linear: ScaleMapper; }
//   class BreakScaleMapperImpl { readonly breaks; private _outOfBrk; constructor(...) {...} ... }
// The port's `BreakScaleMapper` (scale/break.swift) is a `class` (stored-closure method slots), so
//   `BreakScaleMapperImpl` subclasses it; `breaks`/`hasBreaks`/`calcNiceTickMultiple` override the
//   base placeholders. Overriding `public` (non-`open`) base members is legal here since both files
//   live in the same module (EChartsKit).
final class BreakScaleMapperImpl: BreakScaleMapper {

    // upstream: readonly breaks: ParsedAxisBreakList;  ([CAVEAT] Should set only by the constructor!)
    // Backing storage: `updateAxisBreakGapReal` writes `gapReal` into the elements in place (upstream
    //   mutates by reference; a Swift `[ParsedAxisBreak]` is a value type, so we expose the getter and
    //   mutate `_breaks` directly from the file-private `updateAxisBreakGapReal`).
    fileprivate var _breaks: ParsedAxisBreakList
    override var breaks: ParsedAxisBreakList { return _breaks }

    // Linear space, the elapsed result. (upstream: `_linear: ScaleMapper` on the interface.)
    fileprivate var _linear: ScaleMapper!

    // Only used to save the original extent to avoid rounding error.
    private var _outOfBrk: ScaleMapper!

    init(
        _ breakParsed: AxisBreakParsingResult?,
        _ initialExtent: [Double]?
    ) {
        // upstream: this.breaks = breakParsed && breakParsed.breaks || [];
        //   (moved before super.init() to satisfy Swift two-phase init; the decorated methods that
        //    read `breaks` are only invoked after construction.)
        self._breaks = breakParsed?.breaks ?? []

        super.init()

        // upstream: decorateScaleMapper(this, BreakScaleMapperImpl.decoratedMethods);
        decorateScaleMapper(self, BreakScaleMapperImpl.decoratedMethods(self))

        // upstream: this._outOfBrk = initLinearScaleMapper(null, initialExtent);
        self._outOfBrk = initLinearScaleMapper(nil, initialExtent)
        // upstream: const mapper = this._linear = initLinearScaleMapper(null, initialExtent);
        let mapper = initLinearScaleMapper(nil, initialExtent)
        self._linear = mapper
        // upstream: enableScaleMapperFreeze(this, mapper);
        enableScaleMapperFreeze(self, mapper)
    }

    // upstream: hasBreaks(): boolean { return !!this.breaks.length; }
    override func hasBreaks() -> Bool {
        return !self._breaks.isEmpty
    }

    /**
     * When iteratively generating ticks by nice interval, currently the `interval`, which is
     * calculated by break-elapsed extent span, is probably very small comparing to the original
     * extent, leading to a large number of iteration and tick generation, even over `safeLimit`.
     * Thus stepping over breaks is necessary in that loop.
     *
     * "Nice" should be ensured on ticks when step over the breaks. Thus this method returns
     * a integer multiple of the "nice tick interval".
     *
     * This method does little work; it is just for unifying and restricting the behavior.
     */
    override func calcNiceTickMultiple(
        _ tickVal: Double,
        _ estimateNiceMultiple: (_ tickVal: Double, _ brkEnd: Double) -> Double
    ) -> Double {
        for idx in 0..<self._breaks.count {
            let brk = self._breaks[idx]
            if brk.vmin < tickVal && tickVal < brk.vmax {
                let multiple = estimateNiceMultiple(tickVal, brk.vmax)
                if __DEV__ {
                    // If not, it may cause dead loop or not nice tick.
                    util.assert(multiple >= 0 && number.mathRound(multiple) == multiple)
                }
                return multiple
            }
        }
        return 0
    }

    // upstream: static decoratedMethods: DecoratedScaleMapperMethods<BreakScaleMapperImpl> = { ... };
    //   Ported as a static FACTORY taking the host `this` (closures capture `this`) — same convention
    //   as `OrdinalScale.decoratedMethods`. Member order below mirrors upstream's object literal; the
    //   `DecoratedScaleMapperMethods.init` argument order is (needTransform, normalize, scale,
    //   transformIn, transformOut, contain, getExtent, getExtentUnsafe, setExtent, setExtent2).
    static func decoratedMethods(_ this: BreakScaleMapperImpl) -> DecoratedScaleMapperMethods {
        return DecoratedScaleMapperMethods(

            needTransform: {
                return this._breaks.isEmpty
            },

            normalize: { val in
                return this._linear.normalize(this.transformIn(val, nil))
            },

            scale: { val in
                return this.transformOut(this._linear.scale(val), nil)
            },

            transformIn: { val, opt in
                if let opt = opt, opt.depth == SCALE_MAPPER_DEPTH_OUT_OF_BREAK {
                    return val
                }
                // If the value is in the break, return the normalized value in the break
                var elapsedVal = AXIS_BREAK_ELAPSED_BASE
                var lastBreakEnd = AXIS_BREAK_LAST_BREAK_END_BASE
                var stillOver = true
                for i in 0..<this._breaks.count {
                    let brk = this._breaks[i]
                    if val <= brk.vmax {
                        if val > brk.vmin {
                            elapsedVal += brk.vmin - lastBreakEnd
                                + (val - brk.vmin) / (brk.vmax - brk.vmin) * brk.gapReal!
                        }
                        else {
                            elapsedVal += val - lastBreakEnd
                        }
                        lastBreakEnd = brk.vmax
                        stillOver = false
                        break
                    }
                    elapsedVal += brk.vmin - lastBreakEnd + brk.gapReal!
                    lastBreakEnd = brk.vmax
                }
                if stillOver {
                    elapsedVal += val - lastBreakEnd
                }
                return elapsedVal
            },

            transformOut: { elapsedVal, opt in
                if let opt = opt, opt.depth == SCALE_MAPPER_DEPTH_OUT_OF_BREAK {
                    return elapsedVal
                }
                var lastElapsedEnd = AXIS_BREAK_ELAPSED_BASE
                var lastBreakEnd = AXIS_BREAK_LAST_BREAK_END_BASE
                var stillOver = true
                var unelapsedVal: Double = 0
                for i in 0..<this._breaks.count {
                    let brk = this._breaks[i]
                    let elapsedStart = lastElapsedEnd + brk.vmin - lastBreakEnd
                    let elapsedEnd = elapsedStart + brk.gapReal!
                    if elapsedVal <= elapsedEnd {
                        if elapsedVal > elapsedStart {
                            unelapsedVal = brk.vmin
                                + (elapsedVal - elapsedStart) / (elapsedEnd - elapsedStart) * (brk.vmax - brk.vmin)
                        }
                        else {
                            unelapsedVal = lastBreakEnd + elapsedVal - lastElapsedEnd
                        }
                        lastBreakEnd = brk.vmax
                        stillOver = false
                        break
                    }
                    lastElapsedEnd = elapsedEnd
                    lastBreakEnd = brk.vmax
                }
                if stillOver {
                    unelapsedVal = lastBreakEnd + elapsedVal - lastElapsedEnd
                }
                return unelapsedVal
            },

            contain: { val in
                return this._outOfBrk.contain(val)
            },

            getExtent: {
                return this._outOfBrk.getExtent()
            },

            getExtentUnsafe: { kind, depth in
                return (depth == nil || depth == SCALE_MAPPER_DEPTH_OUT_OF_BREAK)
                    ? this._outOfBrk.getExtentUnsafe(kind, nil)
                    : this._linear.getExtentUnsafe(kind, nil)
            },

            setExtent: { start, end in
                this.setExtent2(SCALE_EXTENT_KIND_EFFECTIVE, start, end)
            },

            setExtent2: { kind, start, end in
                if model.isValidBoundsForExtent(start, end) {
                    if kind == SCALE_EXTENT_KIND_EFFECTIVE {
                        updateAxisBreakGapReal(this, [start, end])
                    }
                    this._outOfBrk.setExtent2(kind, start, end)
                    this._linear.setExtent2(
                        kind,
                        this.transformIn(start, nil),
                        this.transformIn(end, nil)
                    )
                }
            }

        )
    }
}

func createBreakScaleMapper(
    _ breakParsed: AxisBreakParsingResult?,
    _ initialExtent: [Double]?
) -> BreakScaleMapper {
    return BreakScaleMapperImpl(breakParsed, initialExtent)
}

// Both can start with any finite value, and are not necessarily equal. But they need to
// be the same in `axisBreakElapse` and `axisBreakUnelapse` respectively.
private let AXIS_BREAK_ELAPSED_BASE: Double = 0
private let AXIS_BREAK_LAST_BREAK_END_BASE: Double = 0

/**
 * `gapReal` in brkMapper.breaks will be calculated.
 */
// upstream mutates `brkMapper.breaks[i].gapReal` by reference; the port mutates the concrete
//   `BreakScaleMapperImpl._breaks` storage directly (see the `_breaks` note above).
private func updateAxisBreakGapReal(
    _ brkMapper: BreakScaleMapper,
    _ scaleExtent: [Double]
) {
    // See upstream for the derivation of `prctBrksGapRealSum`.
    var gapPrctSum: Double = 0
    var fullyInExtBrksSumTpAbsSpan: Double = 0
    var fullyInExtBrksSumTpAbsVal: Double = 0
    var fullyInExtBrksSumTpPrctSpan: Double = 0
    var fullyInExtBrksSumTpPrctVal: Double = 0

    // upstream: const init = () => ({has: false, span: NaN, inExtFrac: NaN, val: NaN});
    struct SemiInfo {
        var has = false
        var span = Double.nan
        var inExtFrac = Double.nan
        var val = Double.nan
    }
    // semiInExtBrk[S|E][tpAbs|tpPrct]
    var semiS_tpAbs = SemiInfo(); var semiS_tpPrct = SemiInfo()
    var semiE_tpAbs = SemiInfo(); var semiE_tpPrct = SemiInfo()

    let breaks = brkMapper.breaks
    util.each(breaks) { brk, _ in
        let gapParsed = brk.gapParsed

        if gapParsed.type == "tpPrct" {
            gapPrctSum += gapParsed.val
        }

        if let clampedBrk = clampBreakByExtent(brk, scaleExtent) {
            let vminClamped = clampedBrk.vmin != brk.vmin
            let vmaxClamped = clampedBrk.vmax != brk.vmax
            let clampedSpan = clampedBrk.vmax - clampedBrk.vmin

            if vminClamped && vmaxClamped {
                // Do nothing, which simply makes the result `gapReal` cover the entire scaleExtent.
            }
            else if vminClamped || vmaxClamped {
                let inExtFrac = clampedSpan / (brk.vmax - brk.vmin)
                if vminClamped { // 'S'
                    if gapParsed.type == "tpAbs" {
                        semiS_tpAbs.has = true; semiS_tpAbs.span = clampedSpan
                        semiS_tpAbs.inExtFrac = inExtFrac; semiS_tpAbs.val = gapParsed.val
                    }
                    else {
                        semiS_tpPrct.has = true; semiS_tpPrct.span = clampedSpan
                        semiS_tpPrct.inExtFrac = inExtFrac; semiS_tpPrct.val = gapParsed.val
                    }
                }
                else { // 'E'
                    if gapParsed.type == "tpAbs" {
                        semiE_tpAbs.has = true; semiE_tpAbs.span = clampedSpan
                        semiE_tpAbs.inExtFrac = inExtFrac; semiE_tpAbs.val = gapParsed.val
                    }
                    else {
                        semiE_tpPrct.has = true; semiE_tpPrct.span = clampedSpan
                        semiE_tpPrct.inExtFrac = inExtFrac; semiE_tpPrct.val = gapParsed.val
                    }
                }
            }
            else {
                if gapParsed.type == "tpAbs" {
                    fullyInExtBrksSumTpAbsSpan += clampedSpan
                    fullyInExtBrksSumTpAbsVal += gapParsed.val
                }
                else {
                    fullyInExtBrksSumTpPrctSpan += clampedSpan
                    fullyInExtBrksSumTpPrctVal += gapParsed.val
                }
            }
        }
    }

    let prctBrksGapRealSum = gapPrctSum
        * (0
            + (scaleExtent[1] - scaleExtent[0])
            + (fullyInExtBrksSumTpAbsVal - fullyInExtBrksSumTpAbsSpan)
            + (semiS_tpAbs.has ? (semiS_tpAbs.val - semiS_tpAbs.span) * semiS_tpAbs.inExtFrac : 0)
            + (semiE_tpAbs.has ? (semiE_tpAbs.val - semiE_tpAbs.span) * semiE_tpAbs.inExtFrac : 0)
            - fullyInExtBrksSumTpPrctSpan
            - (semiS_tpPrct.has ? semiS_tpPrct.span * semiS_tpPrct.inExtFrac : 0)
            - (semiE_tpPrct.has ? semiE_tpPrct.span * semiE_tpPrct.inExtFrac : 0)
        ) / (1
            - fullyInExtBrksSumTpPrctVal
            - (semiS_tpPrct.has ? semiS_tpPrct.val * semiS_tpPrct.inExtFrac : 0)
            - (semiE_tpPrct.has ? semiE_tpPrct.val * semiE_tpPrct.inExtFrac : 0)
        )

    // Write `gapReal` back into the storage (upstream mutates each `brk` in place).
    guard let impl = brkMapper as? BreakScaleMapperImpl else {
        return
    }
    for idx in 0..<impl._breaks.count {
        let gapParsed = impl._breaks[idx].gapParsed
        if gapParsed.type == "tpPrct" {
            impl._breaks[idx].gapReal = gapPrctSum != 0
                // prctBrksGapRealSum is supposed to be non-negative but add a safe guard
                ? number.mathMax(prctBrksGapRealSum, 0) * gapParsed.val / gapPrctSum : 0
        }
        if gapParsed.type == "tpAbs" {
            impl._breaks[idx].gapReal = gapParsed.val
        }
        if impl._breaks[idx].gapReal == nil {
            impl._breaks[idx].gapReal = 0
        }
    }
}

// upstream: pruneTicksByBreak<TItem extends ScaleTick | number>(...): void  (mutates `ticks`).
private func pruneTicksByBreakImpl<TItem>(
    _ pruneByBreak: ParamPruneByBreak?,
    _ ticks: inout [TItem],
    _ breaks: ParsedAxisBreakList,
    _ getValue: (_ item: TItem) -> Double,
    _ interval: Double,
    _ scaleExtent: [Double]
) {
    if pruneByBreak == "no" {
        return
    }
    util.each(breaks) { brk, _ in
        // break.vmin/vmax that out of extent must not impact the visible of normal ticks and labels.
        guard let clampedBrk = clampBreakByExtent(brk, scaleExtent) else {
            return
        }
        // Remove some normal ticks to avoid zigzag shapes overlapping with split lines and to avoid
        // break labels overlapping with normal tick labels. It's OK to O(n^2) since `ticks` is small.
        var j = ticks.count - 1
        while j >= 0 {
            let tick = ticks[j]
            let val = getValue(tick)
            // 1. Ensure there is no ticks inside `break.vmin` and `break.vmax`.
            // 2. Use an empirically gap value here.
            let gap = interval * 3 / 4
            if val > clampedBrk.vmin - gap
                && val < clampedBrk.vmax + gap
                && (
                    pruneByBreak != "preserve_extent_bound"
                    || (val != scaleExtent[0] && val != scaleExtent[1])
                )
            {
                ticks.remove(at: j)
            }
            j -= 1
        }
    }
}

private func addBreaksToTicksImpl(
    // The input ticks should be in accending order.
    _ ticks: inout [ScaleTick],
    _ breaks: ParsedAxisBreakList,
    _ scaleExtent: [Double],
    // Keep the break ends at the same level to avoid an awkward appearance.
    _ getTimeProps: ((_ clampedBrk: ParsedAxisBreak) -> TimeScaleTickTime?)?
) {
    util.each(breaks) { brk, _ in
        guard let clampedBrk = clampBreakByExtent(brk, scaleExtent) else {
            return
        }
        var tMin = ScaleTick(value: clampedBrk.vmin)
        tMin.break = VisualAxisBreak(type: "vmin", parsedBreak: clampedBrk)
        tMin.time = getTimeProps != nil ? getTimeProps!(clampedBrk) : nil
        ticks.append(tMin)
        // When gap is 0, start tick overlap with end tick, but we still count both of them.
        var tMax = ScaleTick(value: clampedBrk.vmax)
        tMax.break = VisualAxisBreak(type: "vmax", parsedBreak: clampedBrk)
        tMax.time = getTimeProps != nil ? getTimeProps!(clampedBrk) : nil
        ticks.append(tMax)
    }
    if !breaks.isEmpty {
        ticks.sort { $0.value < $1.value }
    }
}

/**
 * If break and extent does not intersect, return null/undefined.
 * If the intersection is only a point at scaleExtent[0] or scaleExtent[1], return null/undefined.
 */
private func clampBreakByExtent(
    _ brk: ParsedAxisBreak,
    _ scaleExtent: [Double]
) -> ParsedAxisBreak? {
    let vmin = number.mathMax(brk.vmin, scaleExtent[0])
    let vmax = number.mathMin(brk.vmax, scaleExtent[1])
    return (
            vmin < vmax
            || (vmin == vmax && vmin > scaleExtent[0] && vmin < scaleExtent[1])
        )
        ? ParsedAxisBreak(
            breakOption: brk.breakOption,
            vmin: vmin,
            vmax: vmax,
            gapParsed: brk.gapParsed,
            gapReal: brk.gapReal
        )
        : nil
}

private func parseAxisBreakOptionImpl(
    // raw user input breaks, retrieved from axis model.
    _ breakOptionList: [AxisBreakOption]?,
    _ scale: Scale,
    _ opt: ParseBreakOptionOpt?
) -> AxisBreakParsingResult {
    // upstream: parsedBreaks holds `ParsedAxisBreak | null` (nulled on overlap), filtered at the end.
    var parsedBreaks: [ParsedAxisBreak?] = []

    guard let breakOptionList = breakOptionList else {
        return AxisBreakParsingResult(breaks: [])
    }

    func validatePercent(_ normalizedPercent: Double, _ msg: String) -> Bool {
        if normalizedPercent >= 0 && normalizedPercent < 1 - 1e-5 { // Avoid division error.
            return true
        }
        if __DEV__ {
            log.error("\(msg) must be >= 0 and < 1, rather than \(normalizedPercent) .")
        }
        return false
    }

    util.each(breakOptionList) { brkOption, _ in
        // upstream: if (!brkOption || brkOption.start == null || brkOption.end == null) { error; return; }
        if isNullish(brkOption.start) || isNullish(brkOption.end) {
            if __DEV__ {
                log.error("The input axis breaks start/end should not be empty.")
            }
            return
        }
        if brkOption.isExpanded == true {
            return
        }

        var parsedBrk = ParsedAxisBreak(
            breakOption: brkOption,  // upstream: clone(brkOption) — value-type copy in Swift.
            vmin: scale.parse(brkOption.start),
            vmax: scale.parse(brkOption.end),
            gapParsed: ParsedAxisBreakGapParsed(type: "tpAbs", val: 0),
            gapReal: nil
        )

        if !isNullish(brkOption.gap) {
            var isPrct = false
            if util.isString(brkOption.gap) {
                let trimmedGap = number._trim(brkOption.gap as! String)
                if trimmedGap.hasSuffix("%") {
                    var normalizedPercent = number.parseFloatLeading(trimmedGap) / 100
                    if !validatePercent(normalizedPercent, "Percent gap") {
                        normalizedPercent = 0
                    }
                    parsedBrk.gapParsed.type = "tpPrct"
                    parsedBrk.gapParsed.val = normalizedPercent
                    isPrct = true
                }
            }
            if !isPrct {
                var absolute = scale.parse(brkOption.gap!)
                if !absolute.isFinite || absolute < 0 {
                    if __DEV__ {
                        log.error("Axis breaks gap must positive finite rather than (\(String(describing: brkOption.gap))).")
                    }
                    absolute = 0
                }
                parsedBrk.gapParsed.type = "tpAbs"
                parsedBrk.gapParsed.val = absolute
            }
        }
        if parsedBrk.vmin == parsedBrk.vmax {
            parsedBrk.gapParsed.type = "tpAbs"
            parsedBrk.gapParsed.val = 0
        }

        if let opt = opt, opt.noNegative == true {
            if parsedBrk.vmin < 0 {
                if __DEV__ { log.error("Axis break.vmin must not be negative.") }
                parsedBrk.vmin = 0
            }
            if parsedBrk.vmax < 0 {
                if __DEV__ { log.error("Axis break.vmax must not be negative.") }
                parsedBrk.vmax = 0
            }
        }

        // Ascending numerical order is the prerequisite of the calculation in Scale#normalize.
        // User are allowed to input desending vmin/vmax for simplifying the usage.
        if parsedBrk.vmin > parsedBrk.vmax {
            let tmp = parsedBrk.vmax
            parsedBrk.vmax = parsedBrk.vmin
            parsedBrk.vmin = tmp
        }

        parsedBreaks.append(parsedBrk)
    }

    // Ascending numerical order is the prerequisite of the calculation in Scale#normalize.
    parsedBreaks.sort { ($0?.vmin ?? 0) < ($1?.vmin ?? 0) }
    // Make sure that the intervals in breaks are not overlap.
    var lastEnd = -Double.infinity
    for idx in 0..<parsedBreaks.count {
        guard let brk = parsedBreaks[idx] else { continue }
        if lastEnd > brk.vmin {
            if __DEV__ {
                log.error("Axis breaks must not overlap.")
            }
            parsedBreaks[idx] = nil
        }
        lastEnd = brk.vmax
    }

    return AxisBreakParsingResult(
        breaks: util.filter(parsedBreaks) { brk, _ in brk != nil }.map { $0! }
    )
}

private func identifyAxisBreakImpl(
    _ brk: AxisBreakOption,
    _ identifier: AxisBreakOptionIdentifierInAxis
) -> Bool {
    return serializeAxisBreakIdentifierImpl(identifier)
        == serializeAxisBreakIdentifierImpl(AxisBreakOptionIdentifierInAxis(start: brk.start, end: brk.end))
}

private func serializeAxisBreakIdentifierImpl(_ identifier: AxisBreakOptionIdentifierInAxis) -> String {
    // We use user input start/end to identify break. Theoretically `Scale#parse` should be used here,
    // but simply converting to string happens to be correct and reduces dependencies.
    return "\(scaleDataValueToString(identifier.start))_\u{0}_\(scaleDataValueToString(identifier.end))"
}

/**
 * - A break pair represents `[vmin, vmax]`,
 * - Only both vmin and vmax item exist, they are counted as a pair.
 */
// upstream: retrieveAxisBreakPairs<TItem, TReturnIdx>(...): TReturnIdx extends false ? TItem[][] : number[][]
//   The conditional return type collapses to `[[Any]]` (each inner array is either `[TItem, TItem]`
//   or `[Int, Int]`).
private func retrieveAxisBreakPairsImpl<TItem>(
    _ itemList: [TItem],
    _ getVisualAxisBreak: (_ item: TItem) -> VisualAxisBreak?,
    _ returnIdx: Bool
) -> [[Any]] {
    var idxPairList: [[Int]] = []
    util.each(itemList) { el, idx in
        let vBreak = getVisualAxisBreak(el)
        if let vBreak = vBreak, vBreak.type == "vmin" {
            idxPairList.append([idx])
        }
    }
    util.each(itemList) { el, idx in
        let vBreak = getVisualAxisBreak(el)
        if let vBreak = vBreak, vBreak.type == "vmax" {
            // parsedBreak may be changed, can only use breakOption to match them.
            let found = firstIndexWhere(idxPairList) { pr in
                let other = getVisualAxisBreak(itemList[pr[0]])!
                return identifyAxisBreakImpl(
                    other.parsedBreak.breakOption,
                    AxisBreakOptionIdentifierInAxis(
                        start: vBreak.parsedBreak.breakOption.start,
                        end: vBreak.parsedBreak.breakOption.end
                    )
                )
            }
            if let found = found {
                idxPairList[found].append(idx)
            }
        }
    }
    var result: [[Any]] = []
    util.each(idxPairList) { idxPair, _ in
        if idxPair.count == 2 {
            if returnIdx {
                result.append([idxPair[0], idxPair[1]])
            }
            else {
                result.append([itemList[idxPair[0]], itemList[idxPair[1]]])
            }
        }
    }
    return result
}

private func getTicksBreakOutwardTransformImpl(
    _ scale: ScaleMapper,
    _ tick: ScaleTick,
    _ outermostBreaks: ParsedAxisBreakList,
    _ lookup: ValueTransformLookupOpt.Lookup?
) -> (tickVal: Double?, vBreak: VisualAxisBreak?)? {

    guard let tickBreak = tick.break else {
        return nil
    }

    let brk = tickBreak.parsedBreak
    let originalBrkItem = util.find(outermostBreaks) { obrk, _ in
        identifyAxisBreakImpl(
            obrk.breakOption,
            AxisBreakOptionIdentifierInAxis(
                start: tickBreak.parsedBreak.breakOption.start,
                end: tickBreak.parsedBreak.breakOption.end
            )
        )
    }
    // NOTE: `tick.break` may have been clamped by scale extent.
    let opt = ScaleMapperTransformOutOpt(depth: SCALE_MAPPER_DEPTH_OUT_OF_BREAK, lookup: lookup)
    let vmin = scale.transformOut(brk.vmin, opt)
    let vmax = scale.transformOut(brk.vmax, opt)
    let parsedBreak = ParsedAxisBreak(
        breakOption: brk.breakOption, // It is not changed by extent clamping.
        vmin: vmin,
        vmax: vmax,
        gapParsed: originalBrkItem!.gapParsed,  // upstream: clone(originalBrkItem.gapParsed)
        gapReal: brk.gapReal
    )
    let tickVal = tickBreak.type == "vmin" ? parsedBreak.vmin : parsedBreak.vmax
    return (tickVal: tickVal, vBreak: VisualAxisBreak(type: tickBreak.type, parsedBreak: parsedBreak))
}

private func parseAxisBreakOptionInwardTransformImpl(
    _ breakOptionList: [AxisBreakOption]?,
    _ scale: Scale,
    _ parseOpt: ParseBreakOptionOpt,
    _ lookupStartIdx: Double,
    _ out: inout ParseAxisBreakOptionInwardTransformOut
) {
    out.original = parseAxisBreakOptionImpl(breakOptionList, scale, parseOpt)
    var transformed = parseAxisBreakOptionImpl(breakOptionList, scale, parseOpt)
    // upstream shares `out.lookup` arrays by reference; the port reads/writes the value-typed copy
    //   and stores it back below (see LogScale's mirroring comment).
    var lookup = out.lookup ?? ValueTransformLookupOpt.Lookup(from: [], to: [])
    let startIdx = Int(lookupStartIdx)

    func ensureLookupSize(_ n: Int) {
        while lookup.from.count < n { lookup.from.append(0) }
        while lookup.to.count < n { lookup.to.append(0) }
    }

    transformed.breaks = util.map(transformed.breaks) { brk, idx in
        let transOpt = ScaleMapperTransformInOpt(depth: SCALE_MAPPER_DEPTH_OUT_OF_BREAK)
        let vmin = scale.transformIn(brk.vmin, transOpt)
        let vmax = scale.transformIn(brk.vmax, transOpt)
        let gapParsed = ParsedAxisBreakGapParsed(
            type: brk.gapParsed.type,
            val: brk.gapParsed.type == "tpAbs"
                ? scale.transformIn(brk.vmin + brk.gapParsed.val, transOpt) - vmin
                : brk.gapParsed.val
        )

        ensureLookupSize(startIdx + idx + 2)
        lookup.from[startIdx + idx] = vmin
        lookup.to[startIdx + idx] = brk.vmin
        lookup.from[startIdx + idx + 1] = vmax
        lookup.to[startIdx + idx + 1] = brk.vmax

        return ParsedAxisBreak(
            breakOption: brk.breakOption,
            vmin: vmin,
            vmax: vmax,
            gapParsed: gapParsed,
            gapReal: brk.gapReal
        )
    }
    out.transformed = transformed
    out.lookup = lookup
}

// upstream: const BREAK_MIN_MAX_TO_PARAM = {vmin: 'start', vmax: 'end'} as const;
private func makeAxisLabelFormatterParamBreakImpl(
    _ extraParam: AxisLabelFormatterExtraParams?,
    _ vBreak: VisualAxisBreak?
) -> AxisLabelFormatterExtraParams? {
    var extraParam = extraParam
    if let vBreak = vBreak {
        var ep = extraParam ?? AxisLabelFormatterExtraParams()
        ep.break = AxisLabelFormatterExtraBreakPartBreak(
            type: vBreak.type == "vmin" ? "start" : "end",
            start: vBreak.parsedBreak.vmin,
            end: vBreak.parsedBreak.vmax
        )
        extraParam = ep
    }
    return extraParam
}

// upstream: the object literal registered by `installScaleBreakHelper` -> a concrete conformer.
struct BreakScaleHelperImpl: BreakScaleHelper {
    func createBreakScaleMapper(
        _ breakParsed: AxisBreakParsingResult?, _ initialExtent: [Double]?
    ) -> BreakScaleMapper {
        return EChartsKit.createBreakScaleMapper(breakParsed, initialExtent)
    }
    func pruneTicksByBreak<TItem>(
        _ pruneByBreak: ParamPruneByBreak?, _ ticks: inout [TItem], _ breaks: ParsedAxisBreakList,
        _ getValue: (_ item: TItem) -> Double, _ interval: Double, _ scaleExtent: [Double]
    ) {
        pruneTicksByBreakImpl(pruneByBreak, &ticks, breaks, getValue, interval, scaleExtent)
    }
    func addBreaksToTicks(
        _ ticks: inout [ScaleTick], _ breaks: ParsedAxisBreakList, _ scaleExtent: [Double],
        _ getTimeProps: ((_ clampedBrk: ParsedAxisBreak) -> TimeScaleTickTime?)?
    ) {
        addBreaksToTicksImpl(&ticks, breaks, scaleExtent, getTimeProps)
    }
    func parseAxisBreakOption(
        _ breakOptionList: [AxisBreakOption]?, _ scale: Scale, _ opt: ParseBreakOptionOpt?
    ) -> AxisBreakParsingResult {
        return parseAxisBreakOptionImpl(breakOptionList, scale, opt)
    }
    func identifyAxisBreak(_ brk: AxisBreakOption, _ identifier: AxisBreakOptionIdentifierInAxis) -> Bool {
        return identifyAxisBreakImpl(brk, identifier)
    }
    func serializeAxisBreakIdentifier(_ identifier: AxisBreakOptionIdentifierInAxis) -> String {
        return serializeAxisBreakIdentifierImpl(identifier)
    }
    func retrieveAxisBreakPairs<TItem>(
        _ itemList: [TItem], _ getVisualAxisBreak: (_ item: TItem) -> VisualAxisBreak?, _ returnIdx: Bool
    ) -> [[Any]] {
        return retrieveAxisBreakPairsImpl(itemList, getVisualAxisBreak, returnIdx)
    }
    func getTicksBreakOutwardTransform(
        _ scale: ScaleMapper, _ tick: ScaleTick, _ outermostBreaks: ParsedAxisBreakList,
        _ lookup: ValueTransformLookupOpt.Lookup?
    ) -> (tickVal: Double?, vBreak: VisualAxisBreak?)? {
        return getTicksBreakOutwardTransformImpl(scale, tick, outermostBreaks, lookup)
    }
    func parseAxisBreakOptionInwardTransform(
        _ breakOptionList: [AxisBreakOption]?, _ scale: Scale, _ parseOpt: ParseBreakOptionOpt,
        _ lookupStartIdx: Double, _ out: inout ParseAxisBreakOptionInwardTransformOut
    ) {
        parseAxisBreakOptionInwardTransformImpl(breakOptionList, scale, parseOpt, lookupStartIdx, &out)
    }
    func makeAxisLabelFormatterParamBreak(
        _ extraParam: AxisLabelFormatterExtraParams?, _ vBreak: VisualAxisBreak?
    ) -> AxisLabelFormatterExtraParams? {
        return makeAxisLabelFormatterParamBreakImpl(extraParam, vBreak)
    }
}

/**
 * @caution The only public export of this module (mirrors upstream `installScaleBreakHelper`).
 *  Registers the concrete break helper so `getScaleBreakHelper()` returns non-nil and `breaks`
 *  axis options take effect. Idempotent (`registerScaleBreakHelperImpl` only sets once).
 */
public func installScaleBreakHelper() {
    registerScaleBreakHelperImpl(BreakScaleHelperImpl())
}

// ---- small port-local helpers ----

// upstream `brkOption.start == null` etc. — `ScaleDataValue` is `Any`; treat Swift `nil`/`NSNull` as null.
private func isNullish(_ v: Any?) -> Bool {
    return v == nil || v is NSNull
}

// upstream `identifier.start + '_\0_' + identifier.end` — JS string coercion of a ScaleDataValue.
private func scaleDataValueToString(_ v: ScaleDataValue) -> String {
    if let d = v as? Double {
        return number.jsString(d)
    }
    if let i = v as? Int {
        return number.jsString(Double(i))
    }
    if let s = v as? String {
        return s
    }
    return "\(v)"
}

// upstream `find(list, pred)` returning the item; here we need the INDEX into `idxPairList` to append.
private func firstIndexWhere<T>(_ arr: [T], _ pred: (T) -> Bool) -> Int? {
    for (i, el) in arr.enumerated() {
        if pred(el) { return i }
    }
    return nil
}
