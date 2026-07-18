// Ported from echarts/src/model/Model.ts — keep in sync with upstream
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
// import env from 'zrender/src/core/env';                      -> ZRenderKit `env` (module-internal; see isAnimationEnabled PORT-NOTE)
// import {
//     enableClassExtend, ExtendableConstructor,
//     enableClassCheck, CheckableConstructor
// } from '../util/clazz';                                       -> clazz.enableClassExtend / clazz.enableClassCheck (EChartsKit util/clazz.swift)
// import {AreaStyleMixin} from './mixin/areaStyle';             -> AreaStyleMixin  (sibling model/mixin/areaStyle.swift)
// import TextStyleMixin from './mixin/textStyle';               -> TextStyleMixin  (sibling model/mixin/textStyle.swift)
// import {LineStyleMixin} from './mixin/lineStyle';             -> LineStyleMixin: ported as a direct `extension Model` (sibling model/mixin/lineStyle.swift)
// import {ItemStyleMixin} from './mixin/itemStyle';             -> ItemStyleMixin  (sibling model/mixin/itemStyle.swift)
// import GlobalModel from './Global';                           -> GlobalModel     (sibling model/Global.swift; currently a placeholder protocol in util/types.swift)
// import { AnimationOptionMixin, ModelOption } from '../util/types'; -> AnimationOptionMixin / ModelOption (EChartsKit util/types.swift)
// import { Dictionary } from 'zrender/src/core/types';          -> Dictionary<T> = [String: T] (ZRenderKit core/types)
// import { mixin, clone, merge } from 'zrender/src/core/util';  -> util.mixin / util.clone / util.merge (ZRenderKit)

// Since model.option can be not only `Dictionary` but also primary types,
// we do this conditional type to avoid getting type 'never';
// type Key<Opt> = Opt extends Dictionary<any>
//     ? keyof Opt : string;
// type Value<Opt, R> = Opt extends Dictionary<any>
//     ? (R extends keyof Opt ? Opt[R] : ModelOption)
//     : ModelOption;

// PORT-NOTE: upstream is generic `Model<Opt = ModelOption>` and uses declaration merging
//   (`interface Model extends LineStyleMixin, ItemStyleMixin, TextStyleMixin, AreaStyleMixin {}`)
//   plus runtime `mixin(Model, ...)` to graft the four style mixins onto the class. Per
//   CONVENTIONS §2 the generic is dropped (`Opt` -> the dynamic `ModelOption` = `Any` bag) and
//   the mixins are expressed as protocol conformances:
//     - ItemStyleMixin / TextStyleMixin / AreaStyleMixin are ported as protocols with
//       `where Self: Model` extensions (see the sibling mixin files); `Model` conforms to them
//       here, which is exactly what `mixin(Model, ...)` did.
//     - LineStyleMixin is ported as a direct `extension Model` (no protocol), so `getLineStyle`
//       is already available without a conformance declaration.

// eslint-disable-next-line @typescript-eslint/no-unused-vars
// interface Model<Opt = ModelOption>
//     extends LineStyleMixin, ItemStyleMixin, TextStyleMixin, AreaStyleMixin {}
open class Model: ItemStyleMixin, TextStyleMixin, AreaStyleMixin {    // TODO: TYPE use unknown instead of any?

    // [Caution]: Because this class or desecendants can be used as `XXX.extend(subProto)`,
    // the class members must not be initialized in constructor or declaration place.
    // Otherwise there is bad case:
    //   class A {xxx = 1;}
    //   enableClassExtend(A);
    //   class B extends A {}
    //   var C = B.extend({xxx: 5});
    //   var c = new C();
    //   console.log(c.xxx); // expect 5 but always 1.
    //   (PORT note: Swift uses native subclassing, so this hazard does not apply; the members
    //    are still declared without initializers and assigned in the initializer, faithfully.)

    public var parentModel: Model?

    public var ecModel: GlobalModel?

    // TODO Opt should only be object.
    // PORT-NOTE: upstream `option: Opt` (Opt = ModelOption = Dictionary<any> | any[] | string |
    //   number | boolean | function). The dynamic option tree is modeled as the `Any?` bag
    //   (CONVENTIONS): keyed access casts to `[String: Any]` in `getShallow`/`_doGet`.
    public var option: ModelOption?

    // PORT-NOTE: marked `required` so `clone()` can reconstruct the dynamic subclass via
    //   `type(of: self).init(...)` (a Swift metatype can only call a `required` initializer),
    //   faithfully mirroring upstream's `new (this.constructor as any)(...)`. Subclasses that
    //   declare their own designated init already override this as `required` (e.g. ComponentModel);
    //   those without one inherit it.
    public required init(_ option: ModelOption? = nil, _ parentModel: Model? = nil, _ ecModel: GlobalModel? = nil) {
        self.parentModel = parentModel
        self.ecModel = ecModel
        self.option = option

        // Simple optimization
        // if (this.init) {
        //     if (arguments.length <= 4) {
        //         this.init(option, parentModel, ecModel, extraOpt);
        //     }
        //     else {
        //         this.init.apply(this, arguments);
        //     }
        // }
    }

    // PORT-NOTE: upstream has an overridable lifecycle method literally named `init` (distinct
    //   from the JS constructor above), which subclasses (ComponentModel/SeriesModel) override.
    //   Swift reserves `init` for initializers, so the method keeps the upstream name via a
    //   backtick-escaped identifier; subclasses override `` `init` ``.
    open func `init`(_ option: ModelOption?, _ parentModel: Model? = nil, _ ecModel: GlobalModel? = nil, _ rest: Any...) {}

    /**
     * Merge the input option to me.
     */
    open func mergeOption(_ option: ModelOption?, _ ecModel: GlobalModel? = nil) {
        // upstream: merge(this.option, option, true);
        // PORT-NOTE: `util.merge` requires both target & source to be `[String: Any]` dicts; the
        //   dynamic option bag is `Any?`. Both are cast; when either is not a dict the merge is a
        //   no-op — semantically equivalent to upstream, whose `merge(target, null)` is likewise a
        //   no-op (post-init `self.option` is always a dict). The null/undefined-guard nuance lives
        //   in `util.merge` itself (see PORT_STATUS §4 #7), not in this delegating call.
        guard var target = self.option as? [String: Any],
              let source = option as? [String: Any] else {
            return
        }
        util.merge(&target, source, true)
        self.option = target
    }

    // FIXME:TS consider there is parentModel,
    // return type have to be ModelOption or can be Option<R>?
    // (Is there any chance that parentModel value type is different?)
    //
    // PORT-NOTE: the upstream `get<R extends keyof Opt>(...)` overload chain (1–3 level keyed
    //   type-narrowing) collapses, with the generic, to the `path: string | readonly string[]`
    //   signature returning `ModelOption`. Modeled as two overloads (String / [String]) plus a
    //   no-arg form for the `path == null` branch, so call sites stay byte-identical.

    // upstream `path == null` branch: `if (path == null) { return this.option; }`
    public func get() -> ModelOption? {
        return self.option
    }

    // `path` can be 'a.b.c', so the return value type have to be `ModelOption`
    // TODO: TYPE strict key check?
    // get(path: string | string[], ignoreParent?: boolean): ModelOption;
    public func get(_ path: String, _ ignoreParent: Bool? = nil) -> ModelOption? {
        return get(parsePath(path), ignoreParent)
    }

    public func get(_ path: [String], _ ignoreParent: Bool? = nil) -> ModelOption? {
        return self._doGet(
            self.parsePath(path),
            // upstream: !ignoreParent && this.parentModel
            !(ignoreParent ?? false) ? self.parentModel : nil
        )
    }

    public func getShallow(_ key: String, _ ignoreParent: Bool? = nil) -> ModelOption? {
        let option = self.option

        // upstream: let val = option == null ? option : option[key];
        var val: ModelOption? = (option == nil) ? option : (option as? [String: Any])?[key]
        if val == nil && !(ignoreParent ?? false) {
            let parentModel = self.parentModel
            if let parentModel = parentModel {
                // FIXME:TS do not know how to make it works
                val = parentModel.getShallow(key)
            }
        }
        return val
    }

    // TODO At most 3 depth?
    //
    // PORT-NOTE: the upstream `getModel<R extends keyof Opt>(...)` overload chain collapses, with
    //   the generic dropped, to `getModel(path?: string | readonly string[], parentModel?: Model)`.
    //   Modeled as a String convenience + the `[String]?` core (the latter also covers the
    //   `path == null` form).
    // `path` can be 'a.b.c', so the return value type have to be `Model<ModelOption>`
    // getModel(path: string | string[], parentModel?: Model): Model;
    // TODO 'a.b.c' is deprecated
    public func getModel(_ path: String, _ parentModel: Model? = nil) -> Model {
        return getModel(self.parsePath(path), parentModel)
    }

    public func getModel(_ path: [String]? = nil, _ parentModel: Model? = nil) -> Model {
        let hasPath = path != nil
        let pathFinal: [String]? = hasPath ? self.parsePath(path!) : nil
        let obj: ModelOption? = hasPath
            ? self._doGet(pathFinal)
            : self.option

        let parentModel = parentModel ?? (
            self.parentModel != nil
                ? self.parentModel!.getModel(self.resolveParentPath(pathFinal))
                : nil
        )

        return Model(obj, parentModel, self.ecModel)
    }

    /**
     * If model has option
     */
    public func isEmpty() -> Bool {
        return self.option == nil
    }

    open func restoreData() {}

    // Pending
    public func clone() -> Self {
        // upstream: const Ctor = this.constructor; return new (Ctor as any)(clone(this.option));
        // PORT-NOTE: `type(of: self)` is the dynamic metatype (upstream's `this.constructor`) and the
        //   `required` designated init lets us call it on that metatype, so a `clone()` of a subclass
        //   preserves its concrete type. The `-> Self` return type surfaces that to callers.
        return type(of: self).init(util.clone(self.option))
    }

    // setReadOnly(properties): void {
        // clazzUtil.setReadOnly(this, properties);
    // }

    // If path is null/undefined, return null/undefined.
    public func parsePath(_ path: String) -> [String] {
        // upstream: if (typeof path === 'string') { return path.split('.'); }
        return path
            .split(separator: ".", omittingEmptySubsequences: false)
            .map(String.init)
    }

    public func parsePath(_ path: [String]) -> [String] {
        return path
    }

    // Resolve path for parent. Perhaps useful when parent use a different property.
    // Default to be a identity resolver.
    // Can be modified to a different resolver.
    open func resolveParentPath(_ path: [String]?) -> [String]? {
        return path
    }

    // FIXME:TS check whether put this method here
    open func isAnimationEnabled() -> Bool? {
        // upstream: if (!env.node && this.option) { ... }
        // PORT-NOTE: `env` is module-internal to ZRenderKit (not importable here), and the
        //   ZRenderKit port hardcodes `env.node = true` (windowless branch) — which would
        //   disable animation on an interactive native client. We treat the native client as
        //   browser-like (`!env.node` == true) so animation can be enabled; revisit once a public
        //   `env` accessor lands. The `this.option` truthiness becomes a dict cast below.
        if let option = self.option as? [String: Any] {
            // upstream: if ((this.option as AnimationOptionMixin).animation != null)
            if let animation = option["animation"] {
                // upstream: return !!(this.option as AnimationOptionMixin).animation;
                return modelOptionTruthy(animation)
            }
            else if let parentModel = self.parentModel {
                return parentModel.isAnimationEnabled()
            }
        }
        return nil
    }

    private func _doGet(_ pathArr: [String]?, _ parentModel: Model? = nil) -> ModelOption? {
        var obj: ModelOption? = self.option
        if pathArr == nil {
            return obj
        }

        for i in 0..<pathArr!.count {
            // Ignore empty
            // upstream: if (!pathArr[i]) { continue; }  (empty string is falsy)
            if pathArr![i].isEmpty {
                continue
            }
            // obj could be number/string/... (like 0)
            // upstream: obj = (obj && typeof obj === 'object') ? obj[pathArr[i]] : null;
            //   In JS an array is an object, so a numeric string key (`obj['0']`) indexes it — both the
            //   dict and the numeric-array-index branches are honored here to match `typeof === 'object'`.
            if let dict = obj as? [String: Any] {
                obj = dict[pathArr![i]]
            }
            else if let arr = obj as? [Any], let idx = Int(pathArr![i]), idx >= 0, idx < arr.count {
                obj = arr[idx]
            }
            else {
                obj = nil
            }
            if obj == nil {
                break
            }
        }
        if obj == nil, let parentModel = parentModel {
            obj = parentModel._doGet(
                self.resolveParentPath(pathArr),
                parentModel.parentModel
            )
        }

        return obj
    }
}

// upstream: `!!value` — JS truthiness of the resolved `animation` option value.
//   nil / false / 0 / NaN / "" are falsy; every other value is truthy.
private func modelOptionTruthy(_ value: ModelOption?) -> Bool {
    guard let value = value else { return false }
    if let b = value as? Bool { return b }
    if let n = value as? Double { return n != 0 && !n.isNaN }
    if let s = value as? String { return !s.isEmpty }
    return true
}

// type ModelConstructor = typeof Model
//     & ExtendableConstructor
//     & CheckableConstructor;
//
// // Enable Model.extend.
// enableClassExtend(Model as ModelConstructor);
// enableClassCheck(Model as ModelConstructor);
//
// mixin(Model, LineStyleMixin);
// mixin(Model, ItemStyleMixin);
// mixin(Model, AreaStyleMixin);
// mixin(Model, TextStyleMixin);
//
// PORT-NOTE: the module-level `enableClassExtend`/`enableClassCheck`/`mixin` calls run at TS
//   module-load time. Swift library modules have no load-time execution, and:
//     - `clazz.enableClassExtend`/`clazz.enableClassCheck` are no-ops (native subclassing +
//       `is`/`as?` replace the prototype `extend`/`isInstance` machinery — see util/clazz.swift);
//     - `mixin(Model, ...)` is replaced by the protocol conformances on the class declaration
//       above (ItemStyle/TextStyle/AreaStyle) and the direct `extension Model` for LineStyle.
//   So these four calls are intentionally dropped.

// export default Model;
