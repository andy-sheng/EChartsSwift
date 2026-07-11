// Ported from echarts/src/scale/Scale.ts — keep in sync with upstream
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

// import * as clazzUtil from '../util/clazz';                        -> EChartsKit `clazz` (same module)
// import { ScaleDataValue, ScaleTick, NullUndefined, ParsedValueNumeric } from '../util/types';
//                                                                    -> EChartsKit util/types.swift (same module)
// import { ScaleRawExtentInfo } from '../coord/scaleRawExtentInfo';  -> EChartsKit coord/scaleRawExtentInfo.swift (sibling; other agent this phase)
// import { BreakScaleMapper, ParamPruneByBreak } from './break';     -> EChartsKit scale/break.swift (sibling; other agent this phase)
// import { AxisScaleType } from '../coord/axisCommonTypes';          -> EChartsKit coord/axisCommonTypes.swift (sibling; other agent this phase)
// import { ScaleMapperGeneric } from './scaleMapper';                -> EChartsKit scale/scaleMapper.swift (sibling; other agent this phase)

/// upstream: export type ScaleGetTicksOpt = { ... }
/// Object-literal options bag → struct (CONVENTIONS §4).
public struct ScaleGetTicksOpt {
    // Whether expand the ticks to nice extent.
    public var expandToNicedExtent: Bool?
    public var pruneByBreak: ParamPruneByBreak?
    // - not specified or undefined(default): insert the breaks as items into the tick array.
    // - 'only-break': return break ticks only without any normal ticks.
    // - 'none': return only normal ticks without any break ticks. Useful when creating split
    //      line / split area, where break area is rendered using zigzag line.
    // NOTE: The returned break ticks do not outside axis extent. And if a break only intersects
    //  with axis extent at start or end, it does not count as a tick.
    // PORT-NOTE: upstream union `'only_break' | 'none' | NullUndefined` modeled as `String?`.
    public var breakTicks: String?
    public init() {}
}

/**
 * @see ScaleMapper for the hierarchy structure.
 */
// upstream: interface Scale<This = unknown> extends ScaleMapperGeneric<This> {}
//           abstract class Scale<This = unknown> { ... }
//
// upstream uses TS *declaration merging* — `interface Scale extends ScaleMapperGeneric<This>`
//   declares that every `Scale` carries the `ScaleMapper` method set (needTransform/
//   normalize/scale/transformIn/transformOut/contain/getExtent/getExtentUnsafe/
//   setExtent/setExtent2/getFilter/sanitize/getDefaultStartValue/freeze), whose bodies
//   are *mounted at runtime* via `decorateScaleMapper`/`initBreakOrLinearMapper` inside the
//   concrete subclasses (Interval/Ordinal/Time/Log) — the abstract base declares no bodies.
// PORT-NOTE: `Scale extends ScaleMapperGeneric<This>` (the merged interface) → `Scale` subclasses the
//   sibling base class `ScaleMapper` (scale/scaleMapper.swift), inheriting its stored-closure method
//   "slots" (needTransform/normalize/.../freeze) and `_extents`/`_frozen`; the concrete subclasses
//   (Interval/Ordinal/Time/Log) mount the bodies at runtime via `initBreakOrLinearMapper` /
//   `decorateScaleMapper`.
// PORT-NOTE: the `<This = unknown>` generic exists only to keep the merged interface's
//   `this`-typing identical; it is not load-bearing and is dropped (CONVENTIONS §2).
//
// `abstract class` → an open (non-final) class whose abstract members `fatalError`
// (CONVENTIONS §2: TS class → Swift class; abstract base cannot be `final`).
open class Scale: ScaleMapper {

    // upstream: type: AxisScaleType;
    // Set by each concrete subclass (no base default) → implicitly-unwrapped.
    public var type: AxisScaleType!

    /**
     * CAUTION: Do not visit it directly - use helper methods in `scale/break.ts` instead.
     */
    // upstream: readonly brk: BreakScaleMapper | NullUndefined;
    // upstream: readonly — assigned during subclass construction (see initBreakOrLinearMapper).
    public internal(set) var brk: BreakScaleMapper?

    private var _isBlank: Bool = false

    // Inject
    // upstream: readonly rawExtentInfo: ScaleRawExtentInfo | NullUndefined;
    public internal(set) var rawExtentInfo: ScaleRawExtentInfo?

    /**
     * Parse input `val` (typicall from ec option or API) to its corresponding
     * numeric representation.
     *
     * NOTICE:
     *  - The implementation must have no side-effect.
     *  - Must be available in constructor.
     *  - Must ensure the return is a number.
     *    `null`/`undefined` is not allowed.
     *    `NaN` represents invalid data.
     *  - Regarding `extent`:
     *    - In `OrdinalScale`, the extent and `ordinalMeta` has been finally determined
     *      before the constructor being called, and parse can reply on them
     *    - In other scales, the extent is not finally determined, and `parse` must not
     *      rely on them, otherwise, the result would be wrong if it is used earlier
     *      (like in `dataZoom`).
     */
    // upstream: parse: (val: ScaleDataValue) => ParsedValueNumeric;
    // Set by each concrete subclass; "Must be available in constructor" → IUO closure.
    public var parse: ((ScaleDataValue) -> ParsedValueNumeric)!

    // PORT-DEVIATION: upstream `SliderTimelineView._createAxis` monkeypatches the created scale's
    //   method: `scale.getTicks = function () { return data.mapArray(['value'], v => ({value: v})); }`.
    //   Swift's concrete scales (`IntervalScale`/`TimeScale`/`OrdinalScale`) are `final` and their
    //   methods cannot be reassigned per instance, so the base carries an optional override closure
    //   that each concrete `getTicks` consults FIRST. `nil` by default → completely inert for every
    //   existing scale/axis; only the timeline axis sets it. (See component/timeline/SliderTimelineView.ts
    //   `_createAxis` — keep in sync.)
    public var getTicksOverride: ((ScaleGetTicksOpt?) -> [ScaleTick])?

    public override init() { super.init() }

    /**
     * When axis extent depends on data and no data exists,
     * axis ticks should not be drawn, which is named 'blank'.
     *
     * @final NEVER override!
     */
    public final func isBlank() -> Bool {
        return self._isBlank
    }

    /**
     * When axis extent depends on data and no data exists,
     * axis ticks should not be drawn, which is named 'blank'.
     *
     * @final NEVER override!
     */
    public final func setBlank(_ isBlank: Bool) {
        self._isBlank = isBlank
    }

    /**
     * @return label of the tick.
     */
    // upstream: abstract getLabel(tick: ScaleTick): string;
    open func getLabel(_ tick: ScaleTick) -> String {
        fatalError("abstract method Scale.getLabel must be overridden") // PORT-NOTE: abstract
    }

    /**
     * Create ticks. The result can be modified by the caller.
     */
    // upstream: abstract getTicks(opt?: ScaleGetTicksOpt): ScaleTick[];
    open func getTicks(_ opt: ScaleGetTicksOpt? = nil) -> [ScaleTick] {
        fatalError("abstract method Scale.getTicks must be overridden") // PORT-NOTE: abstract
    }

    /**
     * Create minor ticks. The result can be modified by the caller.
     */
    // upstream: abstract getMinorTicks(splitNumber: number): number[][];
    open func getMinorTicks(_ splitNumber: Double) -> [[Double]] {
        fatalError("abstract method Scale.getMinorTicks must be overridden") // PORT-NOTE: abstract
    }

    // upstream: static registerClass: clazzUtil.ClassManager['registerClass'];
    // upstream: static getClass: clazzUtil.ClassManager['getClass'];
    //
    // Deviation: upstream mounts these statics onto the class object via
    // `enableClassManagement(Scale)`. Swift metatypes can not have methods mounted at
    // runtime, so the registry is held as a static `ClassManager` instance (the faithful
    // translation produced by `clazz.enableClassManagement()`) and the statics forward to it.
    private static let _classManager: ClassManager = clazz.enableClassManagement()

    @discardableResult
    public static func registerClass(_ clz: Constructor) -> Constructor {
        return _classManager.registerClass(clz)
    }

    public static func getClass(
        _ componentMainType: ComponentMainType,
        _ subType: ComponentSubType? = nil,
        _ throwWhenNotFound: Bool = false
    ) -> Constructor? {
        return _classManager.getClass(componentMainType, subType, throwWhenNotFound)
    }
}

// upstream: type ScaleConstructor = typeof Scale & clazzUtil.ClassManager;
//           clazzUtil.enableClassManagement(Scale as ScaleConstructor);
// PORT-NOTE: no Swift equivalent for the `typeof Scale & ClassManager` intersection;
//   the class-management surface is provided by `Scale._classManager` + the static
//   `registerClass`/`getClass` forwarders above (initialized at first access).

// upstream: export default Scale;  -> `public open class Scale` above.
