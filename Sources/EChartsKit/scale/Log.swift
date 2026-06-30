// Ported from echarts/src/scale/Log.ts — keep in sync with upstream
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
//   import Scale, { ScaleGetTicksOpt } from './Scale';            -> sibling scale/Scale.swift (`Scale`, `ScaleGetTicksOpt`)
//   import IntervalScale from './Interval';                       -> sibling scale/Interval.swift (`IntervalScale`) [other agent this phase]
//   import { ScaleTick, NullUndefined, AxisBreakOption } from '../util/types';
//                                                                 -> util/types.swift (`ScaleTick`, `AxisBreakOption`; NullUndefined -> Optional, §6)
//   import { logScalePowTick, IntervalScaleGetLabelOpt, logScaleLogTick, ValueTransformLookupOpt } from './helper';
//                                                                 -> scale/helper.swift (`helper.logScalePowTick`, `helper.logScaleLogTick`;
//                                                                     `IntervalScaleGetLabelOpt`, `ValueTransformLookupOpt` are top-level types there)
//   import { getBreaksUnsafe, getScaleBreakHelper, ParseAxisBreakOptionInwardTransformOut } from './break';
//                                                                 -> scale/break.swift (top-level free funcs `getBreaksUnsafe`/`getScaleBreakHelper`;
//                                                                     `ParseAxisBreakOptionInwardTransformOut` struct)
//   import { getMinorTicks } from './minorTicks';                 -> scale/minorTicks.swift (`minorTicks.getMinorTicks`)
//   import { DecoratedScaleMapperMethods, decorateScaleMapper, enableScaleMapperFreeze,
//            SCALE_EXTENT_KIND_EFFECTIVE, SCALE_MAPPER_DEPTH_OUT_OF_BREAK, ScaleMapperTransformOutOpt } from './scaleMapper';
//                                                                 -> scale/scaleMapper.swift (top-level)
//   import { map } from 'zrender/src/core/util';                  -> ZRenderKit `util.map`
//   import { isValidBoundsForExtent } from '../util/model';       -> util/model.swift (`model.isValidBoundsForExtent`)
//   import { isNullableNumberFinite } from '../util/number';      -> util/number.swift (`number.isNullableNumberFinite`)
//
// PORT-TODO (cross-sibling dependency): this file relies on the established mapper design in
//   scale/scaleMapper.swift where `ScaleMapper` is a base *class* of stored method-slot closures,
//   mounted via `decorateScaleMapper`. That requires `Scale` (and thus `LogScale`) to be a
//   `ScaleMapper` subclass — see the note in scale/Scale.swift. `IntervalScale` / `IntervalScaleSetting`
//   are translated by another agent this phase; the references below match upstream Interval.ts.

// upstream: type LogScaleSetting = { logBase: number | NullUndefined; breakOption: AxisBreakOption[] | NullUndefined; }
public struct LogScaleSetting {
    public var logBase: Double?
    public var breakOption: [AxisBreakOption]?
    public init(logBase: Double? = nil, breakOption: [AxisBreakOption]? = nil) {
        self.logBase = logBase
        self.breakOption = breakOption
    }
}

// upstream: const LOOKUP_IDX_EXTENT_START = 0; ... (module-level)
// EXTENT indices are genuine array indices (-> Int, CONVENTIONS §7); BREAK_START is also passed
// as the `lookupStartIdx: number` argument of `parseAxisBreakOptionInwardTransform` (-> Double there).
private let LOOKUP_IDX_EXTENT_START = 0
private let LOOKUP_IDX_EXTENT_END = 1
private let LOOKUP_IDX_BREAK_START: Double = 2

/**
 * @final NEVER inherit me!
 */
// upstream: class LogScale extends Scale<LogScale>  (the `<This>` self-type collapses, CONVENTIONS §2).
// `@final` -> `final class`. Adopts `ClassManageable` for `Scale.registerClass` (clazz registry).
public final class LogScale: Scale, ClassManageable {

    // upstream: static type = 'log';
    public static let type = "log"
    // upstream: readonly type = 'log' as const;  — instance `type` (inherited `AxisScaleType!`) set in init.

    // upstream: readonly base: number;
    public let base: Double

    /**
     * `powStub` is used to save original values, i.e., values before logarithm
     * applied, such as raw extent and raw breaks.
     * NOTE: Logarithm transform is probably not inversible by rounding error, which
     * may cause min/max tick is displayed like `5.999999999999999`. The extent in
     * powStub is used to get the original precise extent for this issue.
     *
     * [CAVEAT] `powStub` and `intervalStub` should be modified synchronously.
     */
    // upstream: readonly powStub: IntervalScale;
    // PORT-TODO: upstream `readonly`; constructed after `super.init()` (it needs `self` and the parsed
    //   breaks), so modeled as an IUO `private(set) var` (two-phase init, CONVENTIONS).
    public private(set) var powStub: IntervalScale!
    /**
     * `intervalStub` provides linear tick arrangement (logarithm applied).
     * @see {powStub}
     */
    // upstream: readonly intervalStub: IntervalScale;
    public private(set) var intervalStub: IntervalScale!

    // upstream: private _lookup: ValueTransformLookupOpt['lookup'];
    private var _lookup: ValueTransformLookupOpt.Lookup


    // upstream: constructor(setting: LogScaleSetting)
    public init(_ setting: LogScaleSetting) {
        // ---- Phase 1: initialize stored properties that need no `self` (before super.init). ----
        // upstream: this.base = setting.logBase || 10;  (JS `||`: 0 / NaN / null -> 10)
        self.base = number.or(setting.logBase, 10)

        // upstream:
        //   const lookupFrom: number[] = [];
        //   const lookupTo: number[] = [];
        //   const lookup = this._lookup = {from: lookupFrom, to: lookupTo};
        //   lookupFrom[START] = lookupFrom[END] = lookupTo[START] = lookupTo[END] = NaN;
        // (Index 0 and 1 assigned NaN; modeled as pre-sized length-2 arrays.)
        let lookup = ValueTransformLookupOpt.Lookup(from: [Double.nan, Double.nan], to: [Double.nan, Double.nan])
        self._lookup = lookup

        super.init()

        // upstream: this.parse = IntervalScale.parse;
        self.parse = IntervalScale.parse
        // upstream: readonly type = 'log' as const;
        self.type = "log"

        // upstream: decorateScaleMapper(this, LogScale.mapperMethods);
        decorateScaleMapper(self, LogScale.mapperMethods(self))

        let scaleBreakHelper = getScaleBreakHelper()
        let breakOption = setting.breakOption
        // upstream: const out: ParseAxisBreakOptionInwardTransformOut = {lookup};
        var out = ParseAxisBreakOptionInwardTransformOut(lookup: lookup)
        if let scaleBreakHelper = scaleBreakHelper {
            // upstream: scaleBreakHelper.parseAxisBreakOptionInwardTransform(
            //     breakOption, this, {noNegative: true}, LOOKUP_IDX_BREAK_START, out);
            // PORT-TODO: upstream shares the `lookup` arrays by reference between `this._lookup` and
            //   `out.lookup`, so the breaks written here also appear in `this._lookup`. Swift `Lookup`
            //   is a value type, so we read the mutated `out.lookup` back into `self._lookup` below.
            scaleBreakHelper.parseAxisBreakOptionInwardTransform(
                breakOption, self, ParseBreakOptionOpt(noNegative: true), LOOKUP_IDX_BREAK_START, &out
            )
        }
        if let outLookup = out.lookup {
            self._lookup = outLookup
        }

        // upstream: this.powStub = new IntervalScale({breakParsed: out.original});
        self.powStub = IntervalScale(IntervalScaleSetting(breakParsed: out.original))
        // upstream: this.intervalStub = new IntervalScale({breakParsed: out.transformed});
        self.intervalStub = IntervalScale(IntervalScaleSetting(breakParsed: out.transformed))

        // upstream: enableScaleMapperFreeze(this, this.intervalStub);
        enableScaleMapperFreeze(self, self.intervalStub)
    }

    // upstream: getTicks(opt?: ScaleGetTicksOpt): ScaleTick[]
    public override func getTicks(_ opt: ScaleGetTicksOpt? = nil) -> [ScaleTick] {
        let base = self.base
        let powStub = self.powStub!
        let scaleBreakHelper = getScaleBreakHelper()
        let intervalStub = self.intervalStub!
        let intervalExtent = intervalStub.getExtent()
        let powExtent = powStub.getExtent()
        let powOpt = ValueTransformLookupOpt(
            lookup: ValueTransformLookupOpt.Lookup(from: intervalExtent, to: powExtent)
        )

        // upstream: map(intervalStub.getTicks(opt || {}), function (tick) { ... }, this)
        //   The `this` context arg is dropped — the Swift closure captures `self`.
        return util.map(intervalStub.getTicks(opt ?? ScaleGetTicksOpt())) { [unowned self] tick, _ in
            let val = tick.value
            var powVal = helper.logScalePowTick(val, base, powOpt)

            var vBreak: VisualAxisBreak?
            if let scaleBreakHelper = scaleBreakHelper {
                let brkPowResult = scaleBreakHelper.getTicksBreakOutwardTransform(
                    self,
                    tick,
                    getBreaksUnsafe(powStub),
                    self._lookup
                )
                if let brkPowResult = brkPowResult {
                    vBreak = brkPowResult.vBreak
                    // PORT-TODO: upstream `powVal = brkPowResult.tickVal` may assign `number|undefined`
                    //   while `ScaleTick.value` is non-optional `Double`; undefined coerced to NaN.
                    powVal = brkPowResult.tickVal ?? Double.nan
                }
            }

            var result = ScaleTick(value: powVal)
            result.break = vBreak
            return result
        }
    }

    // upstream: getMinorTicks(splitNumber: number): number[][]
    public override func getMinorTicks(_ splitNumber: Double) -> [[Double]] {
        return minorTicks.getMinorTicks(
            self,
            splitNumber,
            getBreaksUnsafe(self.powStub),
            // NOTE: minor ticks are in the log scale value to visually hint users "logarithm".
            self.intervalStub.getConfig().interval
        )
    }

    // upstream: getLabel(data: ScaleTick, opt?: IntervalScaleGetLabelOpt)
    public func getLabel(
        _ data: ScaleTick,
        _ opt: IntervalScaleGetLabelOpt? = nil
    ) -> String {
        return self.intervalStub.getLabel(data, opt)
    }

    // PORT-TODO: the abstract base declares `getLabel(_ tick: ScaleTick) -> String`. Upstream satisfies
    //   it with the wider `getLabel(data, opt?)`; Swift cannot widen an override signature, so this
    //   one-arg override forwards to the upstream two-arg method.
    public override func getLabel(_ tick: ScaleTick) -> String {
        return self.getLabel(tick, nil)
    }

    // upstream: static mapperMethods: DecoratedScaleMapperMethods<LogScale> = { ... }
    // PORT-TODO: upstream is a *static* method bag whose bodies use `this`. The ported
    //   `DecoratedScaleMapperMethods` (scaleMapper.swift) is a NON-generic struct of closures that
    //   must capture the host, so it takes the host as `this` (mirroring `OrdinalScale.decoratedMethods`)
    //   and is mounted via `decorateScaleMapper` in the constructor exactly as upstream. The
    //   init-parameter order of `DecoratedScaleMapperMethods` places getExtent/getExtentUnsafe before
    //   setExtent/setExtent2 (differs from upstream method declaration order); each closure is
    //   annotated with its upstream position.
    // PORT-TODO: verify capture — the closures are stored on `this` (via decorateScaleMapper) and
    //   capture `this`, a real retain cycle; `[unowned this]` breaks it (the closures never outlive
    //   the host).
    static func mapperMethods(_ this: LogScale) -> DecoratedScaleMapperMethods {
        return DecoratedScaleMapperMethods(

            // upstream #1: needTransform()
            needTransform: {
                return true
            },

            // upstream #2: normalize(val)
            normalize: { [unowned this] val in
                return this.intervalStub.normalize(helper.logScaleLogTick(val, this.base))
            },

            // upstream #3: scale(val)
            scale: { [unowned this] val in
                // PENDING: Input `intervalStub.getExtent()` and `powStub.getExtent()` may
                // break monotonicity. Do not do it until real problems found.
                return helper.logScalePowTick(this.intervalStub.scale(val), this.base, nil)
            },

            // upstream #4: transformIn(val, opt)
            transformIn: { [unowned this] val, opt in
                let val = helper.logScaleLogTick(val, this.base)
                return (opt?.depth == SCALE_MAPPER_DEPTH_OUT_OF_BREAK)
                    ? val
                    : this.intervalStub.transformIn(val, opt)
            },

            // upstream #5: transformOut(val, opt)
            transformOut: { [unowned this] val, opt in
                let depth = opt?.depth
                LogScale.tmpTransformOutOpt1.depth = depth
                LogScale.tmpTransformOutOpt2.lookup = this._lookup
                return helper.logScalePowTick(
                    (depth == SCALE_MAPPER_DEPTH_OUT_OF_BREAK)
                        ? val
                        : this.intervalStub.transformOut(val, LogScale.tmpTransformOutOpt1),
                    this.base,
                    LogScale.tmpTransformOutOpt2
                )
            },

            // upstream #6: contain(val)
            contain: { [unowned this] val in
                return this.powStub.contain(val)
            },

            // upstream #12: getExtent()
            getExtent: { [unowned this] in
                return this.powStub.getExtent()
            },

            // upstream #13: getExtentUnsafe(kind, depth)
            getExtentUnsafe: { [unowned this] kind, depth in
                return depth == nil
                    ? this.powStub.getExtentUnsafe(kind, nil)
                    : this.intervalStub.getExtentUnsafe(kind, depth)
            },

            /**
             * upstream #7: setExtent(start, end)
             * NOTICE: The caller should ensure `start` and `end` are both non-negative.
             */
            setExtent: { [unowned this] start, end in
                this.setExtent2(SCALE_EXTENT_KIND_EFFECTIVE, start, end)
            },

            // upstream #8: setExtent2(kind, start, end)
            setExtent2: { [unowned this] kind, start, end in
                if !model.isValidBoundsForExtent(start, end)
                    || start <= 0 || end <= 0 {
                    return
                }
                // upstream aliases `lookupTo`/`lookupFrom` to either `this._lookup.{to,from}` (EFFECTIVE)
                // or a throwaway `tmpNotUsedArr`. A Swift `[Double]` is a value type and cannot be
                // aliased to observe writes, so we write directly into the (value-typed) `this._lookup`
                // on the EFFECTIVE branch only; the throwaway-branch writes are dropped (as upstream's
                // are unused).
                let effective = (kind == SCALE_EXTENT_KIND_EFFECTIVE)
                if effective {
                    this._lookup.to[LOOKUP_IDX_EXTENT_START] = start
                    this._lookup.to[LOOKUP_IDX_EXTENT_END] = end
                }
                this.powStub.setExtent2(kind, start, end)
                let base = this.base
                let fromStart = helper.logScaleLogTick(start, base)
                let fromEnd = helper.logScaleLogTick(end, base)
                if effective {
                    this._lookup.from[LOOKUP_IDX_EXTENT_START] = fromStart
                    this._lookup.from[LOOKUP_IDX_EXTENT_END] = fromEnd
                }
                this.intervalStub.setExtent2(kind, fromStart, fromEnd)
            },

            // upstream #9: getFilter()
            getFilter: {
                return DataSanitizationFilter(g: 0)
            },

            // upstream #10: sanitize(value, dataExtent)
            sanitize: { value, dataExtent in
                var value = value
                // Conservative - if dataExtent is invalid, do not sanitize.
                if model.isValidBoundsForExtent(dataExtent[0], dataExtent[1])
                    && number.isNullableNumberFinite(value)
                    && value! <= 0 {
                    // `DataStore` has ensured that `dataExtent` is valid for LogScale.
                    value = dataExtent[0]
                }
                return value
            },

            // upstream #11: getDefaultStartValue()
            getDefaultStartValue: {
                return 1
            }
        )
    }

    // upstream module-level scratch singletons (declared after the class):
    //   const tmpTransformOutOpt1: ScaleMapperTransformOutOpt = {};
    //   const tmpTransformOutOpt2: ValueTransformLookupOpt = {};
    //   const tmpNotUsedArr: number[] = [];
    // (`tmpNotUsedArr` is unused in the Swift `setExtent2` rewrite above — see the note there.)
    private static var tmpTransformOutOpt1 = ScaleMapperTransformOutOpt()
    private static var tmpTransformOutOpt2 = ValueTransformLookupOpt()

}

// upstream: Scale.registerClass(LogScale);
// PORT-TODO: upstream runs this side-effecting registration at module import time. Swift libraries
//  have no import-time hook, and a lazy `let` global only initializes on first access (so it would
//  never run). Exposed instead as an idempotent static bootstrap that the EChartsKit registration
//  entry point must invoke once (mirroring `IntervalScale.registerScaleClass()`).
extension LogScale {
    @discardableResult
    public static func registerScaleClass() -> Bool {
        Scale.registerClass(LogScale.self)
        return true
    }
}

// upstream: export default LogScale;  -> `public final class LogScale` above.
