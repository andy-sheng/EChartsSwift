// Ported from echarts/src/model/Component.ts — keep in sync with upstream
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
// import * as zrUtil from 'zrender/src/core/util';            -> ZRenderKit `util` (util.merge / util.each / util.map / util.indexOf)
// import Model from './Model';                                 -> Model (sibling model/Model.swift)
// import * as componentUtil from '../util/component';          -> EChartsKit `component` namespace (util/component.swift)
// import {
//     enableClassManagement, parseClassType, isExtendedClass,
//     ExtendableConstructor, ClassManager, mountExtend
// } from '../util/clazz';                                       -> EChartsKit `clazz` namespace + `ClassManager` (util/clazz.swift)
// import {
//     makeInner, ModelFinderIndexQuery, queryReferringComponents,
//     ModelFinderIdQuery, QueryReferringOpt
// } from '../util/model';                                       -> EChartsKit `model` namespace + finder types (util/model.swift)
// import * as layout from '../util/layout';                     -> util/layout.swift (getBoxLayoutParams/mergeLayoutParam ported; fetchLayoutMode/getLayoutParams deferred — layout-mode merge)
// import GlobalModel from './Global';                           -> GlobalModel (util/types.swift placeholder protocol; real type is a sibling this phase)
// import {
//     ComponentOption, ComponentMainType, ComponentSubType, ComponentFullType,
//     ComponentLayoutMode, BoxLayoutOptionMixin, NullUndefined
// } from '../util/types';                                       -> EChartsKit util/types.swift (same module)
// import { CoordinateSystem } from '../coord/CoordinateSystem'; -> coord/CoordinateSystem.swift (provenance only; the type is used solely by commented-out `coordinateSystem` members here)

// const inner = makeInner<{ defaultOption: ComponentOption }, ComponentModel>();
//
// `inner` cached the auto-merged ancestor `defaultOption` for the legacy
//   `ParentClass.extend(subProto)` path inside `getDefaultOption`. That path is unreachable in the
//   Swift port (`clazz.isExtendedClass` always returns false — native subclassing replaces the
//   prototype `extend` machinery), so the `inner`/WeakMap cache is dropped together with the branch.

// upstream: class ComponentModel<Opt extends ComponentOption = ComponentOption> extends Model<Opt>
//
// the generic `Opt` is dropped per CONVENTIONS §2 (the dynamic option tree is modeled as
//   the `Any` bag; keyed access casts to `[String: Any]`). `ComponentModel` is the project's real
//   reference type for components/series — `open class` (subclassed by Series/axis/grid/etc., and by
//   each registered component model). It replaces the forward-reference placeholder
//   `protocol ComponentModel` that previously lived in util/types.swift.
//   It conforms to `ClassManageable` so its metatype is a valid `Constructor` for the class registry
//   (which reads the static `type`).
open class ComponentModel: Model, ClassManageable {

    // [Caution]: Because this class or desecendants can be used as `XXX.extend(subProto)`,
    // the class members must not be initialized in constructor or declaration place.
    // Otherwise there is bad case:
    //   class A {xxx = 1;}
    //   enableClassExtend(A);
    //   class B extends A {}
    //   var C = B.extend({xxx: 5});
    //   var c = new C();
    //   console.log(c.xxx); // expect 5 but always 1.
    //   (PORT note: Swift uses native subclassing, so this hazard does not apply; the upstream
    //    `static protoInitialize` defaults below are expressed as Swift property default values.)

    /**
     * @readonly
     */
    // upstream: type: ComponentFullType (instance member, set by protoInitialize = 'component').
    // The registry (ClassManageable) reads the *static* `type` below; instances mirror it so
    // `this.type` keeps working (faithful to `prototype.type = static type`).
    open var type: ComponentFullType { return Self.type }

    // ClassManageable: the class registry reads the static `type`. ES-class subclasses declare
    // `static type = 'xxx'` (here: `override class var type { return "xxx" }`).
    open class var type: ComponentFullType { return "component" }

    /**
     * @readonly
     */
    public var id: String = ""

    /**
     * Because simplified concept is probably better, series.name (or component.name)
     * has been having too many responsibilities:
     * (1) Generating id (which requires name in option should not be modified).
     * (2) As an index to mapping series when merging option or calling API (a name
     * can refer to more than one component, which is convenient is some cases).
     * (3) Display.
     * @readOnly But injected
     */
    public var name: String = ""

    /**
     * @readOnly
     */
    public var mainType: ComponentMainType = ""

    /**
     * @readOnly
     */
    public var subType: ComponentSubType = ""

    /**
     * @readOnly
     */
    public var componentIndex: Double = 0

    /**
     * @readOnly
     */
    // upstream: protected defaultOption: ComponentOption
    //
    // upstream declares `defaultOption` as a `protected` instance (prototype) member, but
    //   its value is supplied by the subclass STATIC `defaultOption` (read via `(ctor as any)
    //   .defaultOption` in `getDefaultOption`). Per the doc block on `getDefaultOption`, ES-class
    //   subclasses MUST declare `static defaultOption`. We model it as an overridable class var;
    //   subclasses override it (cf. `component.inheritDefaultOption`).
    open class var defaultOption: ModelOption? { return nil }

    // upstream: ecModel: GlobalModel (re-declared non-null on ComponentModel).
    //   Inherited from `Model` as `ecModel: GlobalModel?`; not re-declared (it is non-null in
    //   practice once the component is mounted by GlobalModel).

    /**
     * @readOnly
     */
    // upstream: static dependencies: string[]
    open class var dependencies: [String] { return [] }

    public let uid: String

    // // No common coordinateSystem needed. Each sub class implement
    // // `CoordinateSystemHostModel` itself.
    // coordinateSystem: CoordinateSystemMaster | CoordinateSystemExecutive;

    // Determine the layout box based on that coordinate system, if specified.
    // Will be injected.
    // @see injectCoordinateSystem
    // upstream: boxCoordinateSystem?: CoordinateSystem | NullUndefined
    // coord/CoordinateSystem.swift is ported (protocol `CoordinateSystem`); this box is
    //   still kept as `Any?`.
    public var boxCoordinateSystem: Any?

    /**
     * Support merge layout params.
     * Only support 'box' now (left/right/top/bottom/width/height).
     */
    // upstream: static layoutMode: ComponentLayoutMode | ComponentLayoutMode['type']
    // union `ComponentLayoutMode | string` modeled as `Any?` (consumed by
    //   `layout.fetchLayoutMode`).
    open class var layoutMode: Any? { return nil }

    /**
     * Prevent from auto set z, zlevel, z2 by the framework.
     */
    // upstream leaves `preventAutoZ: boolean` uninitialized (the caution above); Swift
    //   requires a stored value, so it defaults to `false` (≡ JS `undefined` truthiness here).
    public var preventAutoZ: Bool = false

    // Injectable properties:
    public var __viewId: String?
    public var __requireNewView: Bool?

    // static protoInitialize = (function () {
    //     const proto = ComponentModel.prototype;
    //     proto.type = 'component';
    //     proto.id = '';
    //     proto.name = '';
    //     proto.mainType = '';
    //     proto.subType = '';
    //     proto.componentIndex = 0;
    // })();
    //   -> Expressed as the property default values above (`type`/`id`/`name`/`mainType`/`subType`/
    //      `componentIndex`). Swift has no prototype to mutate at module-load time.

    // upstream: `constructor(option, parentModel, ecModel) { super(...); this.uid = ... }`.
    //   Marked `required` so the class-registry `Constructor` (= `ComponentModel.Type`) is
    //   instantiable via the metatype in `Global._mergeOption` (`new ComponentModelClass(...)`).
    //   Every subclass inherits it (none declares its own designated initializer). CONVENTIONS §2:
    //   Swift metatypes can not call a non-`required` init, so this is the minimal enabling change.
    public required init(_ option: ModelOption?, _ parentModel: Model?, _ ecModel: GlobalModel?) {
        self.uid = component.getUID("ec_cpt_model")
        super.init(option, parentModel, ecModel)
    }

    open override func `init`(_ option: ModelOption?, _ parentModel: Model? = nil, _ ecModel: GlobalModel? = nil, _ rest: Any...) {
        self.mergeDefaultAndTheme(option, ecModel)
    }

    open func mergeDefaultAndTheme(_ option: ModelOption?, _ ecModel: GlobalModel?) {
        // const layoutMode = layout.fetchLayoutMode(this);
        let layoutMode = layout.fetchLayoutMode(self)
        // const inputPositionParams = layoutMode ? layout.getLayoutParams(option as BoxLayoutOptionMixin) : {};
        // `option === self.option` at call, so capture the input position params from that
        //   bag BEFORE the theme/default merges below (mirrors Series.mergeDefaultAndTheme).
        let inputPositionParams: [String: Any]
        if layoutMode != nil, let src = (self.option ?? option) as? [String: Any] {
            inputPositionParams = layout.getLayoutParams(src)
        }
        else {
            inputPositionParams = [:]
        }

        // const themeModel = ecModel.getTheme();
        // zrUtil.merge(option, themeModel.get(this.mainType));
        // mirrors mergeOption's value-type writeback (upstream mutates `option` in place;
        //   at call time `option === self.option`). `overwrite` is false (theme must not clobber
        //   existing option values). Skipped when `ecModel` is nil (upstream `this.ecModel` is non-null).
        if var target = (self.option ?? option) as? [String: Any],
           let themeOption = ecModel?.getTheme().get(self.mainType) as? [String: Any] {
            util.merge(&target, themeOption, false)
            self.option = target
        }

        // zrUtil.merge(option, this.getDefaultOption());
        // upstream mutates the shared `option` object in place; Swift option bags are
        //   value types, so merge the default option into a mutable copy and write it back to
        //   `self.option` (at call time `option === self.option`, mirroring Model.mergeOption's
        //   writeback). `overwrite` is false (defaults must not clobber existing option values).
        if var target = (self.option ?? option) as? [String: Any],
           let def = self.getDefaultOption() as? [String: Any] {
            util.merge(&target, def, false)
            self.option = target
        }

        // if (layoutMode) {
        //     layout.mergeLayoutParam(option as BoxLayoutOptionMixin, inputPositionParams, layoutMode);
        // }
        // upstream passes the `ComponentLayoutMode` object as `opt`; only its `ignoreSize`
        //   is read by `mergeLayoutParam`, so it is forwarded via the option bag (cf. Series).
        if let mode = layoutMode, var target = self.option as? [String: Any] {
            var opt: [String: Any] = [:]
            if let ignoreSize = mode.ignoreSize {
                opt["ignoreSize"] = ignoreSize
            }
            layout.mergeLayoutParam(&target, inputPositionParams, opt)
            self.option = target
        }
    }

    open override func mergeOption(_ option: ModelOption?, _ ecModel: GlobalModel?) {
        // zrUtil.merge(this.option, option, true);
        if var target = self.option as? [String: Any], let source = option as? [String: Any] {
            util.merge(&target, source, true)
            self.option = target
        }

        // const layoutMode = layout.fetchLayoutMode(this);
        let layoutMode = layout.fetchLayoutMode(self)
        // if (layoutMode) {
        //     layout.mergeLayoutParam(this.option as BoxLayoutOptionMixin, option as BoxLayoutOptionMixin, layoutMode);
        // }
        // upstream merges the incoming `option` box params INTO this.option; the delta box
        //   params live in the raw `option`. Only `ignoreSize` from the layout mode is read (cf. Series).
        if let mode = layoutMode,
           var target = self.option as? [String: Any],
           let source = option as? [String: Any] {
            var opt: [String: Any] = [:]
            if let ignoreSize = mode.ignoreSize {
                opt["ignoreSize"] = ignoreSize
            }
            layout.mergeLayoutParam(&target, source, opt)
            self.option = target
        }
        _ = ecModel
    }

    /**
     * Called immediately after `init` or `mergeOption` of this instance called.
     */
    open func optionUpdated(_ newCptOption: ModelOption?, _ isInit: Bool) {
        // MUST NOT do anything here.
    }

    /**
     * [How to declare defaultOption]:
     *
     * (A) If using class declaration in typescript (since echarts 5):
     * ```ts
     * import {ComponentOption} from '../model/option';
     * export interface XxxOption extends ComponentOption {
     *     aaa: number
     * }
     * export class XxxModel extends Component {
     *     static type = 'xxx';
     *     static defaultOption: XxxOption = {
     *         aaa: 123
     *     }
     * }
     * Component.registerClass(XxxModel);
     * ```
     * ```ts
     * import {inheritDefaultOption} from '../util/component';
     * import {XxxModel, XxxOption} from './XxxModel';
     * export interface XxxSubOption extends XxxOption {
     *     bbb: number
     * }
     * class XxxSubModel extends XxxModel {
     *     static defaultOption: XxxSubOption = inheritDefaultOption(XxxModel.defaultOption, {
     *         bbb: 456
     *     })
     *     fn() {
     *         let opt = this.getDefaultOption();
     *         // opt is {aaa: 123, bbb: 456}
     *     }
     * }
     * ```
     *
     * (B) If using class extend (previous approach in echarts 3 & 4):
     * ```js
     * let XxxComponent = Component.extend({
     *     defaultOption: {
     *         xx: 123
     *     }
     * })
     * ```
     * ```js
     * let XxxSubComponent = XxxComponent.extend({
     *     defaultOption: {
     *         yy: 456
     *     },
     *     fn: function () {
     *         let opt = this.getDefaultOption();
     *         // opt is {xx: 123, yy: 456}
     *     }
     * })
     * ```
     */
    open func getDefaultOption() -> ModelOption? {
        // `Swift.type(of:)` qualified because the instance `type` property shadows the global.
        let ctor = Swift.type(of: self)

        if !clazz.isExtendedClass(ctor) {
            // When using ES class declaration, defaultOption must be declared as static.
            // And manually inherit the defaultOption from its parent class if needed, such as,
            //  ```ts
            //  static defaultOption = inheritDefaultOption(ParentModel.defaultOption, {...});
            //  ```
            return ctor.defaultOption   // (ctor as any).defaultOption
        }

        // FIXME: remove this approach?
        // Legacy: auto merge defaultOption from ancestor classes if using ParentClass.extend(subProto)
        //
        // the legacy `extend`-based ancestor-merge branch (`inner(this)` cache +
        //   `ExtendableConstructor.superClass` walk + `zrUtil.merge`) is unreachable in the Swift
        //   port — `clazz.isExtendedClass(ctor)` always returns false (native subclassing replaces
        //   the prototype `extend` machinery; see util/clazz.swift). Branch dropped.
        return ctor.defaultOption
    }

    /**
     * Notice: always force to input param `useDefault` in case that forget to consider it.
     * The same behavior as `modelUtil.parseFinder`.
     *
     * @param useDefault In many cases like series refer axis and axis refer grid,
     *        If axis index / axis id not specified, use the first target as default.
     *        In other cases like dataZoom refer axis, if not specified, measn no refer.
     */
    // upstream return: { models: ComponentModel[]; specified: boolean }  ->  QueryReferringResult
    open func getReferringComponents(_ mainType: ComponentMainType, _ opt: QueryReferringOpt) -> QueryReferringResult {
        let indexKey = mainType + "Index"   // (mainType + 'Index') as keyof Opt
        let idKey = mainType + "Id"         // (mainType + 'Id') as keyof Opt

        var userOption = QueryReferringUserOption()
        userOption.index = self.get(indexKey, true)   // this.get(indexKey, true) as ModelFinderIndexQuery
        userOption.id = self.get(idKey, true)          // this.get(idKey, true) as ModelFinderIdQuery

        return model.queryReferringComponents(
            // POTENTIAL-BUG: `ecModel` is `GlobalModel?` on Model; force-unwrap mirrors upstream's
            //   non-null `this.ecModel` (the component is always mounted by then). SIGTRAPs if called
            //   on an unmounted component.
            self.ecModel!,
            mainType,
            userOption,
            opt
        )
    }

    open func getBoxLayoutParams() -> BoxLayoutOptionMixin {
        // Consider itself having box layout configs.
        // For backward compatibility, by default do not `ignoreParent`.
        // return layout.getBoxLayoutParams(this as Model<BoxLayoutOptionMixin>, false);
        return layout.getBoxLayoutParams(self, false)
    }

    /**
     * If developers don't configure zlevel. We will assign zlevel to series based on the key, if provided.
     * For example, lines with trail effect is expected to be in an individual zlevel.
     *
     * @tutorial [GET_ZLEVEL_KEY_FOR_PROGRESSIVE]
     * Regarding "progressive rendering", zrender can automatically assign a dedicated "incremental layer"
     * for `el.incremental` per zlevel. But there is a trade-off:
     *  - If we do not provide different zlevelKey for different series here, all incremental elements from
     *    different series will be assigned to one incremental layer, which causes them to cover each other
     *    in an order depending on progressive steps.
     *      i.e., seriesA_el1 -covered_by-> seriesB_el1 -covered_by-> seriesC_el1 -> seriesA_el2 -> seriesB_el2 ...
     *    This order may causes an unexpected visual result: series with small data are likely to be completely
     *    covered by series with large data. (like in test/scatter-weibo.html)
     *  - If we assign a different zlevelKey to each series, the "covering issue" above can be resolved,
     *    but having one HTML Canvas per series may be excessively memory-consuming.
     *  Therefore, we only automatically assign zlevelKey on `ScatterSeries` and `LinesSeries` for backward
     *  compatibility, and not to other series. Users can explicitly assign zlevel if they encouter above
     *  "covering issue".
     */
    open func getZLevelKey() -> String {
        return ""
    }

    open func setZLevel(_ zlevel: Double) {
        // this.option.zlevel = zlevel;
        if var opt = self.option as? [String: Any] {
            opt["zlevel"] = zlevel
            self.option = opt
        }
    }

    // // Interfaces for component / series with select ability.
    // select(dataIndex?: number[], dataType?: string): void {}

    // unSelect(dataIndex?: number[], dataType?: string): void {}

    // getSelectedDataIndices(): number[] {
    //     return [];
    // }

    // upstream:
    //   static registerClass: ClassManager['registerClass'];
    //   static hasClass: ClassManager['hasClass'];
    //   static registerSubTypeDefaulter: componentUtil.SubTypeDefaulterManager['registerSubTypeDefaulter'];
    //
    // Deviation: upstream mounts these (and the rest of the `ClassManager` / `SubTypeDefaulterManager`
    // / `TopologicalTravelable` surface) onto the class object via the module-level
    // `enableClassManagement(...)` / `enableSubTypeDefaulter(...)` / `enableTopologicalTravel(...)`
    // calls (see the block below). Swift metatypes can not have methods mounted at runtime, so the
    // managers are held on a single static `ComponentModelManager` instance and the statics forward
    // to it.
    private static let _manager: ComponentModelManager = {
        let m = ComponentModelManager()
        // componentUtil.enableSubTypeDefaulter(ComponentModel as ComponentModelConstructor);
        component.enableSubTypeDefaulter(m)
        // componentUtil.enableTopologicalTravel(ComponentModel as ComponentModelConstructor, getDependencies);
        component.enableTopologicalTravel(m, getDependencies)
        return m
    }()

    @discardableResult
    public static func registerClass(_ clz: Constructor) -> Constructor {
        return _manager.registerClass(clz)
    }

    public static func hasClass(_ componentType: ComponentFullType) -> Bool {
        return _manager.hasClass(componentType)
    }

    public static func registerSubTypeDefaulter(_ componentType: String, _ defaulter: @escaping component.SubTypeDefaulter) {
        _manager.registerSubTypeDefaulter?(componentType, defaulter)
    }

    // Remaining `ClassManager` / `SubTypeDefaulterManager` / `TopologicalTravelable` surface mounted
    // by the `enable*` calls upstream (part of `ComponentModelConstructor`); exposed as static
    // forwarders for this file (`getClassesByMainType` is used by `getDependencies`) and siblings.
    public static func getClass(
        _ componentMainType: ComponentMainType,
        _ subType: ComponentSubType? = nil,
        _ throwWhenNotFound: Bool = false
    ) -> Constructor? {
        return _manager.getClass(componentMainType, subType, throwWhenNotFound)
    }

    public static func getClassesByMainType(_ componentType: ComponentMainType) -> [Constructor] {
        return _manager.getClassesByMainType(componentType)
    }

    public static func getAllClassMainTypes() -> [ComponentMainType] {
        return _manager.getAllClassMainTypes()
    }

    public static func hasSubTypes(_ componentType: ComponentFullType) -> Bool {
        return _manager.hasSubTypes(componentType)
    }

    public static func determineSubType(_ componentType: String, _ option: ComponentOption) -> String? {
        return _manager.determineSubType?(componentType, option)
    }

    public static func topologicalTravel(
        _ targetNameList: [ComponentMainType],
        _ fullNameList: [ComponentMainType],
        _ callback: (ComponentMainType, [ComponentMainType]) -> Void,
        _ context: Any? = nil
    ) throws {
        try _manager.topologicalTravel?(targetNameList, fullNameList, callback, context)
    }
}

// export type ComponentModelConstructor = typeof ComponentModel
//     & ClassManager
//     & componentUtil.SubTypeDefaulterManager
//     & ExtendableConstructor
//     & componentUtil.TopologicalTravelable<object>;
//
// no Swift equivalent for the `typeof ComponentModel & ...` metatype intersection. The
//   combined manager surface is provided by `ComponentModel._manager` (a `ComponentModelManager`,
//   below) plus the static forwarders above. (A placeholder `protocol ComponentModelConstructor`
//   for `determineSubType` lives in util/model.swift; ComponentModel does not conform to it because
//   the placeholder returns a non-optional subType.)

// mountExtend(ComponentModel, Model);                          -> no-op: native subclassing (`class ComponentModel: Model`).
// enableClassManagement(ComponentModel as ComponentModelConstructor);
// componentUtil.enableSubTypeDefaulter(ComponentModel as ComponentModelConstructor);
// componentUtil.enableTopologicalTravel(ComponentModel as ComponentModelConstructor, getDependencies);
//   -> realized by `ComponentModel._manager` (initialized at first static access). Swift has no
//      module-load execution, so the wiring runs lazily the first time any static surface is touched.

/// The single object that carries the three runtime-mounted manager surfaces upstream attaches to
/// the `ComponentModel` class object: `ClassManager` (registry), `SubTypeDefaulterManager`, and
/// `TopologicalTravelable`. It must be one object because `enableSubTypeDefaulter` requires a target
/// that is *both* a `SubTypeDefaulterManager` and a `ClassManager` (it reads `target.hasSubTypes`).
/// The `ClassManager` half delegates to a `clazz.enableClassManagement()` registry.
final class ComponentModelManager: ClassManager, component.SubTypeDefaulterManager, component.TopologicalTravelable {

    private let _registry: ClassManager = clazz.enableClassManagement()

    // component.SubTypeDefaulterManager (assigned by component.enableSubTypeDefaulter)
    var registerSubTypeDefaulter: ((String, @escaping component.SubTypeDefaulter) -> Void)?
    var determineSubType: ((String, ComponentOption) -> String?)?

    // component.TopologicalTravelable (assigned by component.enableTopologicalTravel)
    var topologicalTravel: ((
        _ targetNameList: [ComponentMainType],
        _ fullNameList: [ComponentMainType],
        _ callback: (ComponentMainType, [ComponentMainType]) -> Void,
        _ context: Any?
    ) throws -> Void)?

    init() {}

    // ClassManager — forward to the registry produced by `clazz.enableClassManagement()`.
    @discardableResult
    func registerClass(_ clz: Constructor) -> Constructor {
        return _registry.registerClass(clz)
    }
    func getClass(_ componentMainType: ComponentMainType, _ subType: ComponentSubType?, _ throwWhenNotFound: Bool) -> Constructor? {
        return _registry.getClass(componentMainType, subType, throwWhenNotFound)
    }
    func getClassesByMainType(_ componentType: ComponentMainType) -> [Constructor] {
        return _registry.getClassesByMainType(componentType)
    }
    func hasClass(_ componentType: ComponentFullType) -> Bool {
        return _registry.hasClass(componentType)
    }
    func getAllClassMainTypes() -> [ComponentMainType] {
        return _registry.getAllClassMainTypes()
    }
    func hasSubTypes(_ componentType: ComponentFullType) -> Bool {
        return _registry.hasSubTypes(componentType)
    }
}

func getDependencies(_ componentType: String) -> [String] {
    var deps: [String] = []
    util.each(ComponentModel.getClassesByMainType(componentType)) { clz, _ in
        // deps = deps.concat((clz as any).dependencies || (clz as any).prototype.dependencies || []);
        // upstream reads `dependencies` off either the class object or its prototype; the
        //   Swift static `dependencies` (a class var on ComponentModel subclasses) is the single
        //   source of truth — read it by downcasting the `Constructor` metatype.
        if let cm = clz as? ComponentModel.Type {
            deps = deps + cm.dependencies
        }
    }

    // Ensure main type.
    deps = util.map(deps) { type, _ in
        return clazz.parseClassType(type).main
    }

    // Hack dataset for convenience.
    if componentType != "dataset" && util.indexOf(deps, "dataset") <= 0 {
        deps.insert("dataset", at: 0)   // deps.unshift('dataset');
    }

    return deps
}

// export default ComponentModel;  -> `open class ComponentModel` above.
