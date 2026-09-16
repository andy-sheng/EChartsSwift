// Ported from echarts/src/util/clazz.ts — keep in sync with upstream
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

// import * as zrUtil from 'zrender/src/core/util';   -> ZRenderKit `util`
// import { Dictionary } from 'zrender/src/core/types';
// import { ComponentFullType, ComponentTypeInfo, ComponentMainType, ComponentSubType } from './types';
//   -> now owned by util/types.swift (same module); no re-declaration needed.

// upstream: type Constructor = new (...args: any) => any;
//
// upstream `Constructor` is any JS class object. The registry needs to
//            (a) store it and (b) read its `type`. We model that as a metatype of a
//            protocol the registered component/series classes conform to. Faithful
//            mechanism (registry keyed by component type), not prototype mutation.
public protocol ClassManageable: AnyObject {
    static var type: String { get }
}
public typealias Constructor = ClassManageable.Type

/// Namespace mirror of echarts/src/util/clazz.ts (import * as clazzUtil).
public enum clazz {

    static let TYPE_DELIMITER: Character = "."
    static let IS_CONTAINER = "___EC__COMPONENT__CONTAINER___"
    static let IS_EXTENDED_CLASS = "___EC__EXTENDED_CLASS___"

    /// Notice, parseClassType('') should returns {main: '', sub: ''}
    /// @public
    public static func parseClassType(_ componentType: ComponentFullType) -> ComponentTypeInfo {
        var ret = ComponentTypeInfo(main: "", sub: "")
        if !componentType.isEmpty {
            let typeArr = componentType
                .split(separator: TYPE_DELIMITER, omittingEmptySubsequences: false)
                .map(String.init)
            ret.main = (typeArr.count > 0 ? typeArr[0] : "")    // typeArr[0] || ''
            ret.sub = (typeArr.count > 1 ? typeArr[1] : "")     // typeArr[1] || ''
        }
        return ret
    }

    /// @public
    static func checkClassType(_ componentType: ComponentFullType) {
        util.assert(
            componentType.range(of: "^[a-zA-Z0-9_]+([.][a-zA-Z0-9_]+)?$", options: .regularExpression) != nil,
            "componentType \"" + componentType + "\" illegal"
        )
    }

    public static func isExtendedClass(_ clz: Any?) -> Bool {
        // upstream tags extended classes with IS_EXTENDED_CLASS via prototype
        //            mutation (`return !!(clz && clz[IS_EXTENDED_CLASS])`). Swift uses
        //            native subclassing, so there is no runtime "extended" tag to read.
        return false
    }

    // export interface ExtendableConstructor { new; $constructor; extend;
    //            superCall; superApply; superClass; [IS_EXTENDED_CLASS]; }
    //            Describes the prototype-mounted shape produced by `enableClassExtend`.
    //            No Swift equivalent — native `class Sub: Super` replaces it.

    /// Implements `ExtendableConstructor` for `rootClz`.
    ///
    /// prototype-based `extend(proto)` machinery (clones the super class,
    ///            copies a proto bag onto the prototype, mounts extend/superCall/
    ///            superApply/superClass, tags IS_EXTENDED_CLASS). In Swift this is
    ///            replaced by native subclassing (`class Series: Component`) and
    ///            `super.method(...)`. Kept as a callable no-op so call sites that
    ///            still invoke it during porting compile.
    public static func enableClassExtend(_ rootClz: Any, _ mandatoryMethods: [String]? = nil) {
        // no-op — see note above
    }

    // function isESClass(fn) — JS source-string inspection
    //            (`/^class\s/.test(Function.prototype.toString.call(fn))`).
    //            Not applicable to Swift; every Swift class is an "ES class".

    /// A work around to both support ts extend and this extend mechanism on sub-class.
    ///
    /// `SubClz.extend = SupperClz.extend` — prototype `extend` propagation.
    ///            No Swift equivalent; native subclassing inherits behavior directly.
    public static func mountExtend(_ SubClz: Any, _ SupperClz: Any) {
        // no-op — see note above
    }

    // export interface CheckableConstructor { new; isInstance(ins) }
    //            Shape mounted by `enableClassCheck`.

    // let classBase = Math.round(Math.random() * 10);
    //            A random offset used to generate per-class hidden attr keys for
    //            `enableClassCheck`. Not needed — Swift uses `is` / `as?`.

    /// Implements `CheckableConstructor` for `target`.
    /// Can not use instanceof, consider different scope by
    /// cross domain or es module import in ec extensions.
    /// Mount a method "isInstance()" to Clz.
    ///
    /// mounts a hidden boolean on the prototype + an `isInstance()` static
    ///            that checks it (a cross-realm-safe `instanceof`). Swift type identity
    ///            is process-local and reliable, so use `obj is Clz` / `obj as? Clz`
    ///            at call sites instead. Kept as a callable no-op for porting.
    public static func enableClassCheck(_ target: Any) {
        // no-op — see note above
    }

    // function superCall(context, methodName, ...args)
    //            function superApply(context, methodName, args)
    //            Walk `this.superClass.prototype[methodName]` to avoid the dead-loop
    //            described in the upstream comment. Swift uses `super.method(...)`.

    /// Implements `ClassManager` for `target`.
    ///
    /// Deviation: upstream mounts the manager methods onto a target class object. Swift
    /// metatypes can not have methods mounted at runtime, so this returns a concrete
    /// `ClassManagement` registry instance (the faithful translation of the closures
    /// defined inside `enableClassManagement`). A root component class should hold one.
    public static func enableClassManagement() -> ClassManager {
        return ClassManagement()
    }
}

// upstream: type SubclassContainer = {[subType: string]: Constructor} & {[IS_CONTAINER]?: true};
//
// Modelled as an enum so the `IS_CONTAINER` marker becomes the case discriminant
// (`.container`) instead of a magic key stored alongside the subclasses.
private enum StorageValue {
    case clz(Constructor)
    case container([ComponentSubType: Constructor])   // implies IS_CONTAINER
}

public protocol ClassManager: AnyObject {
    @discardableResult func registerClass(_ clz: Constructor) -> Constructor
    func getClass(
        _ componentMainType: ComponentMainType, _ subType: ComponentSubType?, _ throwWhenNotFound: Bool
    ) -> Constructor?
    func getClassesByMainType(_ componentType: ComponentMainType) -> [Constructor]
    func hasClass(_ componentType: ComponentFullType) -> Bool
    func getAllClassMainTypes() -> [ComponentMainType]
    func hasSubTypes(_ componentType: ComponentFullType) -> Bool
}

/// Concrete `ClassManager`. Faithful port of the closures created inside upstream
/// `enableClassManagement`, hung on an instance rather than mounted on a class object.
public final class ClassManagement: ClassManager {

    /// Component model classes
    /// key: componentType,
    /// value:
    ///     componentClass, when componentType is 'a'
    ///     or Object.<subKey, componentClass>, when componentType is 'a.b'
    private var storage: [ComponentMainType: StorageValue] = [:]

    public init() {}

    @discardableResult
    public func registerClass(_ clz: Constructor) -> Constructor {

        // `type` should not be a "instance member".
        // If using TS class, should better declared as `static type = 'series.pie'`.
        // otherwise users have to mount `type` on prototype manually.
        // For backward compat and enable instance visit type via `this.type`,
        // we still support fetch `type` from prototype.
        // upstream reads `(clz as any).type || clz.prototype.type`; here the
        //            static `type` is the single source of truth. An empty string is
        //            treated as "absent" (JS falsy), matching `if (componentFullType)`.
        let componentFullType = clz.type

        if !componentFullType.isEmpty {
            clazz.checkClassType(componentFullType)

            // If only static type declared, we assign it to prototype mandatorily.
            // `clz.prototype.type = componentFullType` — no-op in Swift; the
            //            static `type` is already authoritative and immutable.

            let componentTypeInfo = clazz.parseClassType(componentFullType)

            if componentTypeInfo.sub.isEmpty {
                #if DEBUG
                if storage[componentTypeInfo.main] != nil {
                    print(componentTypeInfo.main + " exists.")
                }
                #endif
                storage[componentTypeInfo.main] = .clz(clz)
            }
            else if componentTypeInfo.sub != clazz.IS_CONTAINER {
                var container = makeContainer(componentTypeInfo)
                container[componentTypeInfo.sub] = clz
                // Deviation §value-semantics: Swift dictionaries are value types, so
                // write the mutated container back into storage.
                storage[componentTypeInfo.main] = .container(container)
            }
        }
        return clz
    }

    public func getClass(
        _ mainType: ComponentMainType,
        _ subType: ComponentSubType?,
        _ throwWhenNotFound: Bool
    ) -> Constructor? {
        var clz: Constructor? = nil

        switch storage[mainType] {
        case .clz(let c):
            clz = c
        case .container(let cont):
            clz = (subType != nil) ? cont[subType!] : nil
        case nil:
            break
        }

        if throwWhenNotFound && clz == nil {
            // upstream `throw new Error(...)`; faithful failure surfaced as
            //            a fatalError (no throwing signature to keep the API ergonomic).
            fatalError(
                subType == nil
                    ? mainType + "." + "type should be specified."
                    : "Component " + mainType + "." + (subType ?? "") + " is used but not imported."
            )
        }

        return clz
    }

    public func getClassesByMainType(_ componentType: ComponentFullType) -> [Constructor] {
        let componentTypeInfo = clazz.parseClassType(componentType)

        var result: [Constructor] = []
        let obj = storage[componentTypeInfo.main]

        switch obj {
        case .container(let cont):
            // upstream skips the IS_CONTAINER key; here there is no such key to skip.
            for (_, o) in cont {
                result.append(o)
            }
        case .clz(let c):
            result.append(c)
        case nil:
            // upstream does `result.push(obj)` (pushes `undefined`) when the
            //            main type is absent; a non-optional `[Constructor]` cannot hold a
            //            sentinel, so we skip. Callers never request an absent main type.
            break
        }

        return result
    }

    public func hasClass(_ componentType: ComponentFullType) -> Bool {
        // Just consider componentType.main.
        let componentTypeInfo = clazz.parseClassType(componentType)
        return storage[componentTypeInfo.main] != nil
    }

    /// @return Like ['aa', 'bb'], but can not be ['aa.xx']
    public func getAllClassMainTypes() -> [ComponentMainType] {
        var types: [String] = []
        // upstream iterates with zrUtil.each preserving insertion order;
        //            Swift Dictionary key order is unspecified. Callers treat the result
        //            as an unordered set of main types.
        for (type, _) in storage {
            types.append(type)
        }
        return types
    }

    /// If a main type is container and has sub types
    public func hasSubTypes(_ componentType: ComponentFullType) -> Bool {
        let componentTypeInfo = clazz.parseClassType(componentType)
        if case .container = storage[componentTypeInfo.main] {
            return true
        }
        return false
    }

    private func makeContainer(_ componentTypeInfo: ComponentTypeInfo) -> [ComponentSubType: Constructor] {
        if case .container(let container)? = storage[componentTypeInfo.main] {
            return container
        }
        let container: [ComponentSubType: Constructor] = [:]
        storage[componentTypeInfo.main] = .container(container)
        return container
    }
}

// /**
//  * @param {string|Array.<string>} properties
//  */
// export function setReadOnly(obj, properties) {
    // FIXME It seems broken in IE8 simulation of IE11
    // if (!zrUtil.isArray(properties)) {
    //     properties = properties != null ? [properties] : [];
    // }
    // zrUtil.each(properties, function (prop) {
    //     let value = obj[prop];

    //     Object.defineProperty
    //         && Object.defineProperty(obj, prop, {
    //             value: value, writable: false
    //         });
    //     zrUtil.isArray(obj[prop])
    //         && Object.freeze
    //         && Object.freeze(obj[prop]);
    // });
// }
