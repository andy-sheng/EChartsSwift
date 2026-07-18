// Ported from echarts/src/coord/axisModelCreator.ts — keep in sync with upstream
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

// import axisDefault from './axisDefault';                               -> axisDefault (coord/axisDefault.swift; map is `axisDefault.option`)
// import ComponentModel from '../model/Component';                       -> ComponentModel (model/Component.swift)
// import { getLayoutParams, mergeLayoutParam, fetchLayoutMode } from '../util/layout';
//     -> PORT-NOTE (deferred): requires util/layout `fetchLayoutMode` / `getLayoutParams` (still absent;
//        only `mergeLayoutParam` is ported in util/layout.swift). The layout-mode param extraction/merge in
//        `mergeDefaultAndTheme` is deferred (same deferral as ComponentModel.mergeDefaultAndTheme).
// import OrdinalMeta from '../data/OrdinalMeta';                         -> OrdinalMeta (data/OrdinalMeta.swift)
// import { DimensionName, BoxLayoutOptionMixin, OrdinalRawValue } from '../util/types';
//     -> DimensionName / BoxLayoutOptionMixin / OrdinalRawValue (util/types.swift)
// import { AxisBaseOption, AXIS_TYPES, CategoryAxisBaseOption } from './axisCommonTypes';
//     -> PORT-NOTE (deferred): requires the full coord/axisCommonTypes (still a minimal stub — only `AxisScaleType`). The axis
//        option interfaces `AxisBaseOption` / `CategoryAxisBaseOption` are modeled as the dynamic option
//        bag ([String: Any]) per the option-tree convention, and `AXIS_TYPES` is inlined below (see
//        `AXIS_TYPES` / `AXIS_TYPES_ORDER`) until the full axisCommonTypes lands.
// import GlobalModel from '../model/Global';                             -> GlobalModel (model/Global.swift)
// import { each, merge } from 'zrender/src/core/util';                   -> util.each / util.merge (ZRenderKit)
// import { EChartsExtensionInstallRegisters } from '../extension';       -> EChartsExtensionInstallRegisters
//     (currently the stub registrar in coord/axisStatistics.swift; extended below with the
//      registerComponentModel / registerSubTypeDefaulter surface — Phase 6b registrar wiring).
// import { BaseAxisBreakPayload } from '../component/axis/axisAction';
// import { AxisBreakUpdateResult, getAxisBreakHelper } from '../component/axis/axisBreakHelper';
//     -> PORT-NOTE (deferred): requires component/axis/{axisAction,axisBreakHelper} (still absent, out of scope this phase — Phase 6b).
//        Minimal stubs are provided below so the creator's method set ports faithfully.

// ============================================================================
// PORT-NOTE stubs — replace when the sibling modules land (all Phase 6b).

// upstream: import { AxisBaseOption, AXIS_TYPES, CategoryAxisBaseOption } from './axisCommonTypes';
//   `AXIS_TYPES` (= `{value: 1, category: 1, time: 1, log: 1} as const`) belongs to axisCommonTypes; it
//   is currently the module-level placeholder declared in coord/axisHelper.swift (PORT-NOTE there), so
//   it is NOT redeclared here. `AXIS_TYPES_ORDER` preserves the JS object insertion order that
//   `each(AXIS_TYPES, ...)` iterates (Swift dictionaries are unordered), keeping registration order.
private let AXIS_TYPES_ORDER: [String] = ["value", "category", "time", "log"]

// upstream: interfaces `AxisBaseOption` / `CategoryAxisBaseOption` from axisCommonTypes.
//   PORT-NOTE: modeled as the dynamic option bag ([String: Any]) per the option-tree convention until
//   the full coord/axisCommonTypes.swift lands (keyed access replaces `.type` / `.data`).
public typealias AxisBaseOption = [String: Any]

// upstream: import { BaseAxisBreakPayload } from '../component/axis/axisAction';
public typealias BaseAxisBreakPayload = Any                                // PORT-NOTE (deferred): requires component/axis/axisAction (not ported)

// upstream: import { AxisBreakUpdateResult, getAxisBreakHelper } from '../component/axis/axisBreakHelper';
public struct AxisBreakUpdateResult {                                      // PORT-NOTE (deferred): requires component/axis/axisBreakHelper (not ported)
    public var breaks: [Any]
    public init(breaks: [Any]) { self.breaks = breaks }
}
public protocol AxisBreakHelper {                                          // PORT-NOTE (deferred): requires component/axis/axisBreakHelper (not ported)
    func updateModelAxisBreak(_ model: Any, _ payload: BaseAxisBreakPayload) -> AxisBreakUpdateResult
}
// getAxisBreakHelper(): AxisBreakHelper | undefined — installed by an optional module; nil in this port.
func getAxisBreakHelper() -> AxisBreakHelper? {
    return nil
}

// upstream: import { EChartsExtensionInstallRegisters } from '../extension';
//   The registration surface (`registerComponentModel` / `registerSubTypeDefaulter`) is Phase 6b. The
//   base stub (coord/axisStatistics.swift) only models `registerProcessor`; these two registrar methods
//   are added as no-op PORT-NOTE stubs so the creator's structure ports faithfully.
//   NOTE: upstream `registerComponentModel(AxisModel)` passes the generated CLASS. Swift cannot
//   synthesize a subclass of the runtime `BaseAxisModelClass` (see `axisModelCreator`), so the single
//   `AxisModel` reference type is registered via a factory closure that carries the per-type closure
//   captures (`axisName` / `axisType` / merged `defaultOption`).
public typealias AxisModelFactory = (ModelOption?, Model?, GlobalModel?) -> ComponentModel
extension EChartsExtensionInstallRegisters {
    // PORT-NOTE: upstream signature is `registerComponentModel(ComponentModelClass)`. Ported as
    //   (type, factory) to carry the dynamically-generated class's per-type identity/defaults.
    public func registerComponentModel(_ componentModelType: ComponentFullType, _ factory: @escaping AxisModelFactory) {
        // PORT-STUB: the registrar does not instantiate dynamically-generated axis model classes.
        PortStub.hit("axisModelCreator.registerComponentModel",
                     "axis model classes are not registered dynamically; ECharts.swift's hand-written "
                     + "stand-in models (EChartsXAxisModel / EChartsYAxisModel / …) serve instead")
        _ = componentModelType
        _ = factory
    }
    // PORT-NOTE: upstream defaulter type is `SubTypeDefaulter = (ComponentOption) -> ComponentSubType`;
    //   `getAxisType` reads the dynamic option bag, so `[String: Any]` is used here.
    public func registerSubTypeDefaulter(_ componentType: String, _ defaulter: @escaping ([String: Any]) -> ComponentSubType) {
        // upstream: registerSubTypeDefaulter(componentType, defaulter) {
        //     ComponentModel.registerSubTypeDefaulter(componentType, defaulter);
        // }
        // Forwards into the real `ComponentModel` sub-type defaulter registry so a component whose
        // subType must be inferred from its option (for axes: `getAxisType`, "has `data` -> category")
        // is resolved through `ComponentModel.determineSubType`.
        //
        // PORT-NOTE: upstream's `SubTypeDefaulter` is `(ComponentOption) -> ComponentSubType`; this
        //   file models the axis defaulter (`getAxisType`) over the dynamic option bag, so adapt via
        //   `rawOption` (mirroring the visualMap defaulter, which likewise reads the raw bag).
        ComponentModel.registerSubTypeDefaulter(componentType) { (option: ComponentOption) -> ComponentSubType in
            return defaulter(option.rawOption ?? [:])
        }
    }
}
// ============================================================================

// type Constructor<T> = new (...args: any[]) => T;
//   -> PORT-NOTE: expressed as `ComponentModel.Type` at the `BaseAxisModelClass` parameter below.

public protocol AxisModelExtendedInCreator: AnyObject {
    func getCategories(_ rawData: Bool?) -> [OrdinalRawValue]?             // OrdinalRawValue[] | CategoryAxisBaseOption['data']
    func getOrdinalMeta() -> OrdinalMeta
    func updateAxisBreaks(_ payload: BaseAxisBreakPayload) -> AxisBreakUpdateResult
}

/**
 * Generate sub axis model class
 * @param axisName 'x' 'y' 'radius' 'angle' 'parallel' ...
 */
// upstream: export default function axisModelCreator<AxisOptionT, AxisModelCtor>(...)
public func axisModelCreator(
    _ registers: EChartsExtensionInstallRegisters,
    _ axisName: DimensionName,
    _ BaseAxisModelClass: ComponentModel.Type,
    _ extraDefaultOption: AxisBaseOption? = nil
) {
    // PORT-NOTE: upstream is generic over <AxisOptionT extends AxisBaseOption,
    //   AxisModelCtor extends Constructor<ComponentModel<AxisOptionT>>>, and the generated `AxisModel`
    //   extends the RUNTIME `BaseAxisModelClass`. Swift cannot subclass a runtime metatype, so the
    //   file-scope `AxisModel` (below) statically extends `AxisBaseModel` (the conventional axis-model
    //   base). `BaseAxisModelClass` is retained for API fidelity but is not used as the superclass —
    //   re-narrow once the registrar / dynamic-class wiring lands (Phase 6b).
    _ = BaseAxisModelClass

    util.each(AXIS_TYPES_ORDER) { axisType, _ in

        // const defaultOption = merge(
        //     merge({}, axisDefault[axisType], true),
        //     extraDefaultOption, true
        // );
        var defaultOption: [String: Any] = [:]
        if let ad = axisDefault.option[axisType] as? [String: Any] {
            util.merge(&defaultOption, ad, true)
        }
        if let extra = extraDefaultOption {
            util.merge(&defaultOption, extra, true)
        }

        // class AxisModel extends BaseAxisModelClass implements AxisModelExtendedInCreator {
        //     static type = axisName + 'Axis.' + axisType;
        //     type = axisName + 'Axis.' + axisType;
        //     static defaultOption = defaultOption;
        //     ...
        // }
        //   -> Modeled by the file-scope `AxisModel` type, configured per axis type via the factory
        //      below (mirroring upstream's closure capture of `axisName` / `axisType` / `defaultOption`).

        // registers.registerComponentModel(AxisModel);
        let type = axisName + "Axis." + axisType
        registers.registerComponentModel(type) { option, parentModel, ecModel in
            let axisModel = AxisModel(option, parentModel, ecModel)
            axisModel.configure(axisName: axisName, axisType: axisType, defaultOption: defaultOption)
            return axisModel
        }
    }

    // registers.registerSubTypeDefaulter(axisName + 'Axis', getAxisType);
    registers.registerSubTypeDefaulter(axisName + "Axis", getAxisType)
}

// class AxisModel extends BaseAxisModelClass implements AxisModelExtendedInCreator
//
// PORT-NOTE: upstream `axisModelCreator` generates a DISTINCT subclass per axis type INSIDE the
//   `each(AXIS_TYPES)` loop, closing over `axisName`, `axisType`, and the merged `defaultOption`
//   (exposed as `static type` / `type` / `static defaultOption`). Swift cannot synthesize classes at
//   runtime, so a single reference type models all of them; the per-type values are injected via
//   `configure(...)` from the factory registered in `axisModelCreator`.
public final class AxisModel: AxisBaseModel, AxisModelExtendedInCreator {

    // PORT-NOTE: closure captures of the upstream generated class (`axisName` / `axisType` /
    //   `defaultOption`), injected per-type by the registered factory.
    private var __axisName: DimensionName = ""
    private var __axisType: String = ""
    private var __defaultOptionValue: ModelOption?

    func configure(axisName: DimensionName, axisType: String, defaultOption: ModelOption?) {
        self.__axisName = axisName
        self.__axisType = axisType
        self.__defaultOptionValue = defaultOption
    }

    // static type = axisName + 'Axis.' + axisType;
    // type = axisName + 'Axis.' + axisType;
    //   -> instance `type` recomputed from the injected captures. PORT-NOTE: the upstream STATIC `type`
    //      cannot be per-type on a single Swift class; only the instance `type` is per-axis here.
    public override var type: ComponentFullType {
        return __axisName + "Axis." + __axisType
    }

    // static defaultOption = defaultOption;
    //   -> `getDefaultOption()` returns the injected per-type default (upstream reads the static
    //      `defaultOption` via `ComponentModel.getDefaultOption` → `(ctor as any).defaultOption`).
    public override func getDefaultOption() -> ModelOption? {
        return __defaultOptionValue
    }

    // private __ordinalMeta: OrdinalMeta;
    private var __ordinalMeta: OrdinalMeta!

    public override func mergeDefaultAndTheme(_ option: ModelOption?, _ ecModel: GlobalModel?) {
        // const layoutMode = fetchLayoutMode(this);
        let layoutMode = layout.fetchLayoutMode(self)
        // const inputPositionParams = layoutMode
        //     ? getLayoutParams(option as BoxLayoutOptionMixin) : {};
        // PORT-NOTE: `option === self.option` at call (mirroring Model.mergeOption), so the input
        //   position params are captured from that bag before the theme/default merges below.
        let inputPositionParams: [String: Any]
        if layoutMode != nil, let src = (self.option ?? option) as? [String: Any] {
            inputPositionParams = layout.getLayoutParams(src)
        }
        else {
            inputPositionParams = [:]
        }

        // const themeModel = ecModel.getTheme();
        // merge(option, themeModel.get(axisType + 'Axis'));
        // merge(option, this.getDefaultOption());
        // option.type = getAxisType(option);
        // PORT-NOTE: upstream mutates the shared `option` object in place; Swift bags are value types,
        //   so merge into a mutable copy and write it back to `self.option` (`option === self.option`
        //   at call, mirroring Model.mergeOption's writeback). merge overwrite defaults to false.
        if var target = (self.option ?? option) as? [String: Any] {
            if let themeModel = ecModel?.getTheme(),
               let themeAxis = themeModel.get(__axisType + "Axis") as? [String: Any] {
                util.merge(&target, themeAxis)
            }
            if let def = self.getDefaultOption() as? [String: Any] {
                util.merge(&target, def)
            }

            target["type"] = getAxisType(target)

            // if (layoutMode) {
            //     mergeLayoutParam(option as BoxLayoutOptionMixin, inputPositionParams, layoutMode);
            // }
            // PORT-NOTE: upstream passes the `ComponentLayoutMode` object as `opt`; only its
            //   `ignoreSize` is read by `mergeLayoutParam`, so it is forwarded via the option bag.
            if let mode = layoutMode {
                var opt: [String: Any] = [:]
                if let ignoreSize = mode.ignoreSize {
                    opt["ignoreSize"] = ignoreSize
                }
                layout.mergeLayoutParam(&target, inputPositionParams, opt)
            }

            self.option = target
        }
    }

    // upstream: optionUpdated(): void
    //   -> overrides ComponentModel.optionUpdated(newCptOption, isInit); upstream takes no args.
    public override func optionUpdated(_ newCptOption: ModelOption?, _ isInit: Bool) {
        // const thisOption = this.option;
        let thisOption = self.option as? [String: Any]
        // if (thisOption.type === 'category') {
        if (thisOption?["type"] as? String) == "category" {
            // this.__ordinalMeta = OrdinalMeta.createByAxisModel(this);
            self.__ordinalMeta = OrdinalMeta.createByAxisModel(self)
        }
    }

    /**
     * Should not be called before all of 'getInitailData' finished.
     * Because categories are collected during initializing data.
     */
    // upstream: getCategories(rawData?: boolean): OrdinalRawValue[] | CategoryAxisBaseOption['data']
    public override func getCategories(_ rawData: Bool? = nil) -> [OrdinalRawValue]? {
        let option = self.option as? [String: Any]
        // FIXME
        // warning if called before all of 'getInitailData' finished.
        if (option?["type"] as? String) == "category" {
            if rawData == true {
                // NOTICE: return the raw data even if not existing; never use a fallback like `[]`;
                // Its existence matters in some legacy cases.
                // return (option as CategoryAxisBaseOption).data;
                return option?["data"] as? [OrdinalRawValue]
            }
            return self.__ordinalMeta.categories
        }
        return nil
    }

    public func getOrdinalMeta() -> OrdinalMeta {
        return self.__ordinalMeta
    }

    public func updateAxisBreaks(_ payload: BaseAxisBreakPayload) -> AxisBreakUpdateResult {
        // const axisBreakHelper = getAxisBreakHelper();
        let axisBreakHelper = getAxisBreakHelper()
        // return axisBreakHelper
        //     ? axisBreakHelper.updateModelAxisBreak(this, payload)
        //     : {breaks: []};
        return axisBreakHelper != nil
            ? axisBreakHelper!.updateModelAxisBreak(self, payload)
            : AxisBreakUpdateResult(breaks: [])
    }

}

// upstream: function getAxisType(option: AxisBaseOption)
func getAxisType(_ option: AxisBaseOption) -> ComponentSubType {
    // Default axis with data is category axis
    // return option.type || ((option as CategoryAxisBaseOption).data ? 'category' : 'value');
    if let type = option["type"] as? String, !type.isEmpty {
        return type
    }
    return option["data"] != nil ? "category" : "value"
}
