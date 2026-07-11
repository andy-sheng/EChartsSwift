// Ported from echarts/src/scale/Ordinal.ts — keep in sync with upstream
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
 * Linear continuous scale
 * http://en.wikipedia.org/wiki/Level_of_measurement
 */

import Foundation
import ZRenderKit

// upstream imports:
//   import Scale from './Scale';                  -> sibling Scale.swift (`Scale`, same module)
//   import OrdinalMeta from '../data/OrdinalMeta'; -> sibling data/OrdinalMeta.swift (`OrdinalMeta`, other agent this phase)
//   import { OrdinalRawValue, OrdinalNumber, OrdinalSortInfo, ScaleTick } from '../util/types';
//       -> Tier1 util/types.swift (same module)
//   import { CategoryAxisBaseOption } from '../coord/axisCommonTypes';
//       -> coord/axisCommonTypes.swift (other agent; only `['data']` referenced — see PORT-NOTE below)
//   import { isArray, map, isObject, isString } from 'zrender/src/core/util';
//       -> ZRenderKit caseless enum `util` (`util.isArray`, `util.map`, `util.isObject`, `util.isString`)
//   import { mathMin, mathRound } from '../util/number';
//       -> sibling number.swift caseless enum `number` (`number.mathMin`, `number.mathRound`)
//   import {
//       DecoratedScaleMapperMethods, decorateScaleMapper, enableScaleMapperFreeze,
//       getScaleExtentForTickUnsafe, initBreakOrLinearMapper, ScaleMapper, ScaleMapperGeneric
//   } from './scaleMapper';
//       -> sibling scaleMapper.swift. NOTE the actual ported shape (matched here):
//          * `ScaleMapper` is a *class* holding the mapper-method *closure slots*
//            (not a protocol); `ScaleMapperGeneric<This>` collapses into it.
//          * the free functions are top-level (NOT a caseless enum namespace), so call sites
//            are bare: `decorateScaleMapper(...)`, `initBreakOrLinearMapper(...)`, etc.
//          * `DecoratedScaleMapperMethods` is a NON-generic struct whose closures capture
//            their host as `this` (no host parameter).
//   import { ordinalScaleCreateTicks } from './helper';
//       -> sibling helper.swift caseless enum `helper` (`helper.ordinalScaleCreateTicks`)
//
// PORT-NOTE (cross-file integration): `decorateScaleMapper`/`enableScaleMapperFreeze`/
//   `getScaleExtentForTickUnsafe` take a `ScaleMapper` host, and upstream passes `this`
//   (the OrdinalScale) to the first two. For that to type-check, `Scale` must subclass the
//   `ScaleMapper` class (i.e. `class Scale: ScaleMapper`), so that `OrdinalScale: Scale` is a
//   `ScaleMapper` and carries the mounted method slots — exactly mirroring the upstream
//   `interface Scale extends ScaleMapperGeneric` declaration merge. This is owned by Scale.swift
//   (sibling, this phase); this file is written assuming that wiring.


// upstream: type OrdinalScaleSetting = { ordinalMeta?: ...; extent?: number[] };
// Object-literal options bag → struct (CONVENTIONS §4).
public struct OrdinalScaleSetting {
    // upstream: ordinalMeta?: OrdinalMeta | CategoryAxisBaseOption['data'];
    // PORT-NOTE: union of `OrdinalMeta` and the axis `data` array
    //   (`(OrdinalRawValue | { value })[]`); modeled as `Any?` and discriminated at runtime
    //   in the constructor (matching upstream `isArray`/`isObject` checks).
    public var ordinalMeta: Any?
    public var extent: [Double]?
    public init(ordinalMeta: Any? = nil, extent: [Double]? = nil) {
        self.ordinalMeta = ordinalMeta
        self.extent = extent
    }
}

/**
 * @final NEVER inherit me!
 */
// upstream:
//   interface OrdinalScale extends ScaleMapperGeneric<OrdinalScale> { _mapper: ScaleMapper; }
//   class OrdinalScale extends Scale<OrdinalScale> { ... }
//
// The `ScaleMapperGeneric` method surface is inherited from the `ScaleMapper` class (via
// `Scale: ScaleMapper`) and *mounted onto the instance* by `decorateScaleMapper`/
// `enableScaleMapperFreeze` in the constructor, faithfully mirroring upstream.
//
// The `<This = OrdinalScale>` generic is not load-bearing and is dropped (CONVENTIONS §2).
// `@final NEVER inherit me!` → `final class` (CONVENTIONS §2). `ClassManageable` is adopted so
// `OrdinalScale.self` is a valid `Constructor` for `Scale.registerClass` (see bottom of file).
public final class OrdinalScale: Scale, ClassManageable {

    public static let type = "ordinal"
    // upstream: readonly type = 'ordinal' as const;  (assigned in the constructor)

    private var _ordinalMeta: OrdinalMeta!

    /**
     * For example:
     * Given original ordinal data:
     * ```js
     * option = {
     *     xAxis: {
     *         // Their raw ordinal numbers are:
     *         //      0    1    2    3    4    5
     *         data: ['a', 'b', 'c', 'd', 'e', 'f']
     *     },
     *     yAxis: {}
     *     series: {
     *         type: 'bar',
     *         data: [
     *             ['d', 110], // ordinalNumber: 3
     *             ['c', 660], // ordinalNumber: 2
     *             ['f', 220], // ordinalNumber: 5
     *             ['e', 550]  // ordinalNumber: 4
     *         ],
     *         realtimeSort: true
     *     }
     * };
     * ```
     * After realtime sorted (order by yValue desc):
     * ```js
     * _ordinalNumbersByTick: [
     *     2, // tick: 0, yValue: 660
     *     5, // tick: 1, yValue: 220
     *     3, // tick: 2, yValue: 110
     *     4, // tick: 3, yValue: 550
     *     0, // tick: 4, yValue: -
     *     1, // tick: 5, yValue: -
     * ],
     * _ticksByOrdinalNumber: [
     *     4, // ordinalNumber: 0, yValue: -
     *     5, // ordinalNumber: 1, yValue: -
     *     0, // ordinalNumber: 2, yValue: 660
     *     2, // ordinalNumber: 3, yValue: 110
     *     3, // ordinalNumber: 4, yValue: 550
     *     1, // ordinalNumber: 5, yValue: 220
     * ]
     * ```
     * NOTICE:
     *  - The index of `_ordinalNumbersByTick` is "tick number", i.e., `tick.value`,
     *    rather than the index of `scale.getTicks()`. They are not the same when
     *    `_extent[0]` is delibrately set to be not zero, or `axisTick/axisLabel.interval` > 0.
     *  - Currently we only support that the index of `_ordinalNumbersByTick` is
     *    from `0` to `ordinalMeta.categories.length - 1`.
     *  - `OrdinalNumber` is always from `0` to `ordinalMeta.categories.length - 1`.
     *
     * @see `Ordinal['getRawOrdinalNumber']`
     * @see `OrdinalSortInfo`
     */
    private var _ordinalNumbersByTick: [OrdinalNumber]?

    /**
     * This is the inverted map of `_ordinalNumbersByTick`.
     * The index is `OrdinalNumber`, which is from `0` to `ordinalMeta.categories.length - 1`.
     * after `_ticksByOrdinalNumber` is initialized.
     *
     * @see `Ordinal['_ordinalNumbersByTick']`
     * @see `Ordinal['_getTickNumber']`
     * @see `OrdinalSortInfo`
     */
    private var _ticksByOrdinalNumber: [Double]?

    // upstream: _mapper: ScaleMapper;  (declared on the merged interface, set in the constructor)
    private var _mapper: ScaleMapper!


    public init(_ setting: OrdinalScaleSetting) {
        super.init()

        // upstream: readonly type = 'ordinal' as const;
        self.type = OrdinalScale.type

        // upstream: this.parse = OrdinalScale.parse;
        // PORT-NOTE: verify capture — `parse` is a `self`-owned closure; `[unowned self]`
        //   breaks the retain cycle and is safe (closure lifetime == self lifetime).
        self.parse = { [unowned self] val in OrdinalScale.parse(self, val) }

        decorateScaleMapper(self, OrdinalScale.decoratedMethods(self))

        var ordinalMeta = setting.ordinalMeta
        // Caution: Should not use instanceof, consider ec-extensions using
        // import approach to get OrdinalMeta class.
        if ordinalMeta == nil {           // if (!ordinalMeta)
            ordinalMeta = OrdinalMeta()    // new OrdinalMeta({})
        }
        if util.isArray(ordinalMeta) {
            // PORT-NOTE: `OrdinalMeta(categories:)` initializer is ported (data/OrdinalMeta.swift).
            let arr = ordinalMeta as! [Any]
            ordinalMeta = OrdinalMeta(categories: util.map(arr) { item, _ in
                // isObject(item) ? item.value : item
                // PORT-TODO: dynamic `item.value` access — `OrdinalRawValue` is `Any`; objects
                //   modeled as `[String: Any]` with a `"value"` key.
                util.isObject(item) ? ((item as? [String: Any])?["value"] ?? item) : item
            })
        }
        self._ordinalMeta = (ordinalMeta as! OrdinalMeta)

        // Create an interval LinearScaleMapper, and decorate it.
        let res = initBreakOrLinearMapper(
            nil,
            nil, // Do not support break in OrdinalScale yet.
            setting.extent ?? [0, Double(self._ordinalMeta.categories.count) - 1]
        )
        self._mapper = res.mapper

        enableScaleMapperFreeze(self, res.mapper)
    }

    private static func parse(_ this: OrdinalScale, _ val: OrdinalRawValue) -> OrdinalNumber {
        var val: Any? = val
        // Caution: Math.round(null) will return `0` rather than `NaN`
        // PORT-NOTE: `ScaleDataValue`/`OrdinalRawValue` is `Any` (Tier1), so JS `null`/`undefined`
        //   can only surface as a wrapped `Optional.none` or `NSNull`; both are treated as null.
        if val == nil || val is NSNull {
            val = Double.nan
        }
        else if util.isString(val) {
            // this._ordinalMeta.getOrdinal(val) — returns null/undefined when not found.
            // NOTE: unwrap the `OrdinalNumber?` explicitly — assigning it straight into the `Any?`
            //   `val` would wrap the inner Optional and defeat the `== nil` check below.
            let ordinal = this._ordinalMeta.getOrdinal(val!)   // val! is Any == OrdinalRawValue
            if ordinal == nil {
                val = Double.nan
            }
            else {
                val = ordinal!
            }
        }
        else {
            // The val from user input might be float.
            //   INT-vs-DOUBLE trap (CONVENTIONS §1): a numeric option can arrive Int-boxed (e.g. a
            //   matrix `coord: [0, 0]`), so a bare `as! Double` would crash. Coerce Int/Double/NSNumber
            //   to Double (JS `val as number` never throws); a non-number falls through to NaN.
            if let d = val as? Double {
                val = number.mathRound(d)
            }
            else if let i = val as? Int {
                val = number.mathRound(Double(i))
            }
            else if let n = val as? NSNumber {
                val = number.mathRound(n.doubleValue)
            }
            else {
                val = Double.nan
            }
        }
        return val as! OrdinalNumber
    }

    // upstream: static decoratedMethods: DecoratedScaleMapperMethods<OrdinalScale> = { ... };
    //
    // Ported as a static FACTORY taking the host `this` (the closures capture `this` and thus
    // cannot be a context-free `static let`). The `this` parameter mirrors upstream's `this:`
    // typing exactly; the label/order of the entries below match upstream's object literal, but
    // the call below them is reordered to satisfy `DecoratedScaleMapperMethods.init` argument
    // order (needTransform, normalize, scale, transformIn, transformOut, contain, getExtent,
    // getExtentUnsafe, setExtent, setExtent2 — the trailing getFilter/sanitize/getDefaultStartValue
    // default to nil, mirroring that OrdinalScale does not define them).
    static func decoratedMethods(_ this: OrdinalScale) -> DecoratedScaleMapperMethods {
        return DecoratedScaleMapperMethods(

            needTransform: {
                return this._mapper.needTransform()
            },

            normalize: { val in
                return this._mapper.normalize(this._getTickNumber(val))
            },

            scale: { val in
                return this.getRawOrdinalNumber(number.mathRound(this._mapper.scale(val)))
            },

            transformIn: { val, opt in
                return this._mapper.transformIn(this._getTickNumber(val), opt)
            },

            transformOut: { val, opt in
                return this.getRawOrdinalNumber(this._mapper.transformOut(val, opt))
            },

            contain: { val in
                return this._mapper.contain(this._getTickNumber(val))
                    && val >= 0 && val < Double(this._ordinalMeta.categories.count)
            },

            getExtent: {
                return this._mapper.getExtent()
            },

            getExtentUnsafe: { kind, depth in
                return this._mapper.getExtentUnsafe(kind, depth)
            },

            setExtent: { start, end in
                return this._mapper.setExtent(start, end)
            },

            /**
             * NOTICE: OrdinalScale extent should always originates from
             * `[0, ordinalMeta.categories.length - 1]`, regardless of min/max of `series.data`.
             * But settings like `xxxAxis.min/max` can still modify the extent.
             * It is handled by constructor of `ScaleRawExtentInfo`.
             */
            setExtent2: { kind, start, end in
                return this._mapper.setExtent2(kind, start, end)
            }

        )
    }

    /**
     * PENDING: currently this method is not used.
     * `makeCategoryTicks` is effectively used.
     */
    public override func getTicks(_ opt: ScaleGetTicksOpt? = nil) -> [ScaleTick] {
        // PORT-DEVIATION: honor the per-instance `getTicksOverride` (timeline axis) — see Scale.swift.
        if let override = self.getTicksOverride { return override(opt) }
        var ticks: [ScaleTick] = []
        helper.ordinalScaleCreateTicks(self, 0) { tick, _ in
            ticks.append(tick)
        }
        return ticks
    }

    public override func getMinorTicks(_ splitNumber: Double) -> [[Double]] {
        // Not support.
        // PORT-NOTE: upstream `return;` (undefined); base `getMinorTicks` is non-optional `[[Double]]`.
        return []
    }

    /**
     * @see `Ordinal['_ordinalNumbersByTick']`
     */
    public func setSortInfo(_ info: OrdinalSortInfo?) {
        if info == nil {
            self._ordinalNumbersByTick = nil
            self._ticksByOrdinalNumber = nil
            return
        }

        let infoOrdinalNumbers = info!.ordinalNumbers
        // PORT-TODO: upstream grows these as sparse JS arrays with `undefined` holes (read via
        //   `!= null`). Here they are pre-sized to `allCategoryLen` and seeded with `NaN` as the
        //   "unset" sentinel (`!= null` → `!isNaN`), then assigned to the properties at the end
        //   (no observer reads them mid-loop, so this is behaviorally equivalent). Indices are
        //   assumed in `0..<allCategoryLen` per the `OrdinalNumber` contract; an out-of-range
        //   ordinal would crash here where JS would silently extend the array.
        let allCategoryLen = self._ordinalMeta.categories.count
        var ordinalsByTick = [OrdinalNumber](repeating: Double.nan, count: allCategoryLen)
        var ticksByOrdinal = [Double](repeating: Double.nan, count: allCategoryLen)

        // Unnecessary support negative tick in `realtimeSort`.
        var tickNum = 0
        let len = Int(number.mathMin(Double(allCategoryLen), Double(infoOrdinalNumbers.count)))
        while tickNum < len {
            let ordinalNumber = infoOrdinalNumbers[tickNum]
            ordinalsByTick[tickNum] = ordinalNumber
            ticksByOrdinal[Int(ordinalNumber)] = Double(tickNum)
            tickNum += 1
        }
        // Handle that `series.data` only covers part of the `axis.category.data`.
        var unusedOrdinal = 0
        while tickNum < allCategoryLen {
            while !ticksByOrdinal[unusedOrdinal].isNaN {   // ticksByOrdinal[unusedOrdinal] != null
                unusedOrdinal += 1
            }
            ordinalsByTick[tickNum] = Double(unusedOrdinal)
            ticksByOrdinal[unusedOrdinal] = Double(tickNum)
            tickNum += 1
        }

        self._ordinalNumbersByTick = ordinalsByTick
        self._ticksByOrdinalNumber = ticksByOrdinal
    }

    private func _getTickNumber(_ ordinal: OrdinalNumber) -> Double {
        let ticksByOrdinalNumber = self._ticksByOrdinalNumber
        // also support ordinal out of range of `ordinalMeta.categories.length`,
        // where ordinal numbers are used as tick value directly.
        return (ticksByOrdinalNumber != nil && ordinal >= 0 && ordinal < Double(ticksByOrdinalNumber!.count))
            ? ticksByOrdinalNumber![Int(ordinal)]
            : ordinal
    }

    /**
     * @usage
     * ```js
     * const ordinalNumber = ordinalScale.getRawOrdinalNumber(tick.value);
     * // case0
     * const rawOrdinalValue = axisModel.getCategories()[ordinalNumber];
     * // case1
     * const rawOrdinalValue = this._ordinalMeta.categories[ordinalNumber];
     * // case2
     * const coord = axis.dataToCoord(ordinalNumber);
     * ```
     *
     * value may be out of range, e.g., when axis max is larger than `ordinalMeta.categories.length`,
     * where ordinal numbers are used as tick value directly.
     */
    // upstream: getRawOrdinalNumber(tickValue: ScaleTick['value']): OrdinalNumber
    public func getRawOrdinalNumber(_ tickValue: Double) -> OrdinalNumber {
        let ordinalNumbersByTick = self._ordinalNumbersByTick
        return (ordinalNumbersByTick != nil && tickValue >= 0 && tickValue < Double(ordinalNumbersByTick!.count))
            ? ordinalNumbersByTick![Int(tickValue)]
            : tickValue
    }

    /**
     * Get item on tick
     */
    public override func getLabel(_ tick: ScaleTick) -> String {
        if !self.isBlank() {
            let ordinalNumber = self.getRawOrdinalNumber(tick.value)
            // this._ordinalMeta.categories[ordinalNumber]
            let categories = self._ordinalMeta.categories
            let category: OrdinalRawValue? =
                (!ordinalNumber.isNaN && ordinalNumber >= 0 && ordinalNumber < Double(categories.count))
                ? categories[Int(ordinalNumber)] : nil
            // Note that if no data, ordinalMeta.categories is an empty array.
            // Return empty if it's not exist.
            // BUGFIX: a collected category (from a dataset source) can be a BOXED Swift Optional
            //   (`Any` wrapping `String?`), so plain interpolation printed `Optional("Matcha")`.
            //   Unwrap any nested optional before stringifying.
            return category == nil ? "" : "\(ordinalUnwrapAny(category!))"
        }
        // PORT-NOTE: upstream returns `undefined` when blank; base `getLabel` is non-optional `String`.
        return ""
    }

    /**
     * NOTICE: This is different from `.getOrdinalMeta().length` when extent
     * is specified by `xxxAxis.min/max` or by `dataZoom`.
     */
    public func count() -> Double {
        let extent = getScaleExtentForTickUnsafe(self._mapper)
        return extent[1] - extent[0] + 1
    }

    public func getOrdinalMeta() -> OrdinalMeta {
        return self._ordinalMeta
    }

    // BUGFIX (dataset category axis): the scale extent is baked into the frozen `_mapper` at INIT time as
    //   `[0, ordinalMeta.categories.count - 1]`. For a `needCollect` axis (a dataset-sourced category axis
    //   with no explicit `data`), the ordinalMeta is EMPTY at init — its categories are collected LATER,
    //   during series-data build — so the mapper extent froze at `[0, -1]`, making `dataToCoord` return NaN
    //   (bars/points get `x: nan` and never draw). Rebuild the mapper from the (now-collected) category
    //   count. Called from `Grid.update` ONLY when the current extent is INVALID (`[1] < [0]`) so a valid
    //   extent — including a dataZoom sub-window or a user-set extent — is never disturbed.
    public func recomputeExtentFromOrdinalMetaIfBlank() {
        let cur = getScaleExtentForTickUnsafe(self._mapper)
        guard cur[1] < cur[0] else { return }   // extent is valid → leave it alone (dataZoom/custom safe)
        let n = self._ordinalMeta.categories.count
        let res = initBreakOrLinearMapper(nil, nil, [0, Double(n) - 1])
        self._mapper = res.mapper
        enableScaleMapperFreeze(self, res.mapper)
    }

}

// upstream: Scale.registerClass(OrdinalScale);
//
// PORT-NOTE: this is top-level side-effecting registration that runs at TS module-load time.
//   Swift has no module-load hook for library types, so it is exposed as an idempotent static
//   that the ECharts bootstrap (`install`) must invoke. `OrdinalScale` conforms to
//   `ClassManageable` (static `type`), so `OrdinalScale.self` is a valid `Constructor`.
extension OrdinalScale {
    @discardableResult
    public static func registerScaleClass() -> Constructor {
        return Scale.registerClass(OrdinalScale.self)
    }
}

// upstream: export default OrdinalScale;  -> `public final class OrdinalScale` above.

// Unwrap a value that may be a BOXED Swift Optional (`Any` wrapping `T?`), recursively, so that
//   string interpolation of a collected ordinal category prints `Matcha` rather than `Optional("Matcha")`.
//   A non-optional value is returned unchanged.
func ordinalUnwrapAny(_ v: Any) -> Any {
    let m = Mirror(reflecting: v)
    if m.displayStyle == .optional {
        if let first = m.children.first { return ordinalUnwrapAny(first.value) }
        return v   // .none — keep as-is (renders "nil")
    }
    return v
}
