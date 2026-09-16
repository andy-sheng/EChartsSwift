// Ported from echarts/src/util/component.ts — keep in sync with upstream
// NOTE: file renamed component.swift -> componentUtil.swift (upstream import alias `componentUtil`) to
//   avoid a case-insensitive object-file name collision with model/Component.swift on macOS (see
//   PORT_STATUS §8). The namespace enum is still `component`; no call sites change.
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

// import * as zrUtil from 'zrender/src/core/util';
//   -> ZRenderKit `util` namespace (util.each / util.indexOf / util.merge).
// import {parseClassType, ClassManager} from './clazz';
//   -> EChartsKit util/clazz.swift: `clazz.parseClassType(...)` and the `ClassManager` protocol.
// import { ComponentOption, ComponentMainType, ComponentSubType, ComponentFullType } from './types';
//   -> EChartsKit util/types.swift (sibling).
// import { Dictionary } from 'zrender/src/core/types';
//   -> ZRenderKit `Dictionary<T> = [String: T]`.
// import { makePrintable } from './log';
//   -> EChartsKit util/log.swift: `log.makePrintable(...)`.

/// Free-function module `component.ts` -> caseless enum namespace `component` (CONVENTIONS §2).
/// Call sites: upstream `getUID(...)` -> `component.getUID(...)`, etc.
public enum component {

    // A random offset
    private static var base: Double = (Double.random(in: 0..<1) * 10).rounded()

    /**
     * @public
     * @param {string} type
     * @return {string}
     */
    public static func getUID(_ type: String) -> String {
        // Considering the case of crossing js context,
        // use Math.random to make id as unique as possible.
        // `base` is a `Double` per CONVENTIONS §1; `String(Int(base))` reproduces the
        //   JS integer string coercion (`base++` is always whole), avoiding a trailing ".0".
        let result = [(type /* || '' */), String(Int(base))].joined(separator: "_")
        base += 1
        return result
    }

    public typealias SubTypeDefaulter = (ComponentOption) -> ComponentSubType
    // upstream:
    // export interface SubTypeDefaulter {
    //     // return subType.
    //     (option: ComponentOption): ComponentSubType;
    // }

    // upstream `SubTypeDefaulterManager` declares the two members as always-present
    //   function properties; they are assigned at runtime by `enableSubTypeDefaulter`, so here they
    //   are settable Optional closure properties on a class-bound protocol (CONVENTIONS §2 mixin).
    //   `determineSubType` is annotated `=> string` upstream but its body can return `undefined`
    //   (when `option.type` is absent and no defaulter applies), so it returns `String?` (§6).
    public protocol SubTypeDefaulterManager: AnyObject {
        var registerSubTypeDefaulter: ((String, @escaping SubTypeDefaulter) -> Void)? { get set }
        var determineSubType: ((String, ComponentOption) -> String?)? { get set }
    }

    /**
     * Implements `SubTypeDefaulterManager` for `target`.
     */
    public static func enableSubTypeDefaulter(_ target: SubTypeDefaulterManager & ClassManager) {
        var subTypeDefaulters: Dictionary<SubTypeDefaulter> = [:]

        // upstream params: (componentType: ComponentFullType, defaulter: SubTypeDefaulter).
        // param types are left to inference so `defaulter` inherits the property's
        //   `@escaping`-ness (an explicit annotation would make it non-escaping and reject storing).
        target.registerSubTypeDefaulter = { componentType, defaulter in
            let componentTypeInfo = clazz.parseClassType(componentType)
            subTypeDefaulters[componentTypeInfo.main] = defaulter
        }

        target.determineSubType = { (componentType: ComponentFullType, option: ComponentOption) -> String? in
            var type = option.type
            if type == nil {
                let componentTypeMain = clazz.parseClassType(componentType).main
                // `target.hasSubTypes` assumes `ClassManager` exposes a
                //   `hasSubTypes(_:) -> Bool` method. If clazz models `ClassManager` with a settable
                //   closure property (mirroring `enableClassManagement`'s assignment style), this
                //   becomes `target.hasSubTypes!(componentType)`.
                if target.hasSubTypes(componentType) && subTypeDefaulters[componentTypeMain] != nil {
                    type = subTypeDefaulters[componentTypeMain]!(option)
                }
            }
            return type
        }
    }

    // upstream `TopologicalTravelable<T>` parameterizes only the callback's `this`/
    //   `context` binding (`callback.call(context, ...)`). Swift closures capture their own context,
    //   so the generic `T` is dropped and `context` is typed `Any?` (unused in the binding).
    //   `throws` mirrors upstream's `throw new Error(...)` on circular dependency. The closure
    //   property is settable (assigned by `enableTopologicalTravel`, CONVENTIONS §2 mixin).
    public protocol TopologicalTravelable: AnyObject {
        var topologicalTravel: ((
            _ targetNameList: [ComponentMainType],
            _ fullNameList: [ComponentMainType],
            _ callback: (ComponentMainType, [ComponentMainType]) -> Void,
            _ context: Any?
        ) throws -> Void)? { get set }
    }

    // ComponentMainType can be 'bb' or 'aa.xx'.
    // upstream `DepGraphItem` is a mutable plain object shared through the `DepGraph`
    //   dictionary (`createDependencyGraphItem` returns the stored reference and callers mutate
    //   it in place); modeled as a `final class` for shared mutable identity (CONVENTIONS §4).
    final class DepGraphItem {
        var predecessor: [ComponentMainType]
        var successor: [ComponentMainType]
        var originalDeps: [ComponentMainType]
        var entryCount: Double
        init() {
            predecessor = []
            successor = []
            // upstream leaves `originalDeps`/`entryCount` undefined until assigned
            //   (createDependencyGraphItem creates `{predecessor: [], successor: []}`).
            originalDeps = []
            entryCount = 0
        }
    }
    typealias DepGraph = [String: DepGraphItem]

    /**
     * Implements `TopologicalTravelable<any>` for `entity`.
     *
     * Topological travel on Activity Network (Activity On Vertices).
     * Dependencies is defined in Model.prototype.dependencies, like ['xAxis', 'yAxis'].
     * If 'xAxis' or 'yAxis' is absent in componentTypeList, just ignore it in topology.
     * If there is circular dependencey, Error will be thrown.
     */
    public static func enableTopologicalTravel(
        _ entity: TopologicalTravelable,
        _ dependencyGetter: @escaping (ComponentMainType) -> [ComponentMainType]
    ) {

        /**
         * @param targetNameList Target Component type list.
         *                       Can be ['aa', 'bb', 'aa.xx']
         * @param fullNameList By which we can build dependency graph.
         * @param callback Params: componentType, dependencies.
         * @param context Scope of callback.
         */
        entity.topologicalTravel = { (targetNameList, fullNameList, callback, context) throws in
            if targetNameList.isEmpty {
                return
            }

            let result = makeDepndencyGraph(fullNameList)
            let graph = result.graph
            var noEntryList = result.noEntryList

            var targetNameSet: [String: Bool] = [:]
            util.each(targetNameList) { name, _ in
                targetNameSet[name] = true
            }

            while !noEntryList.isEmpty {
                let currComponentType = noEntryList.popLast()!
                let currVertex = graph[currComponentType]!
                let isInTargetNameSet = targetNameSet[currComponentType] == true
                if isInTargetNameSet {
                    callback(currComponentType, currVertex.originalDeps /* .slice() */)
                    targetNameSet[currComponentType] = nil
                }
                util.each(currVertex.successor) { succ, _ in
                    isInTargetNameSet ? removeEdgeAndAdd(succ) : removeEdge(succ)
                }
            }

            // ZRenderKit `util.each` provides only the array overload; iterate the
            //   `targetNameSet` dictionary directly (upstream iterates the remaining keys).
            for _ in targetNameSet {
                var errMsg = ""
                if __DEV__ {
                    errMsg = log.makePrintable("Circular dependency may exists: ", targetNameSet, targetNameList, fullNameList)
                }
                throw EChartsError(message: errMsg)
            }

            func removeEdge(_ succComponentType: ComponentMainType) {
                graph[succComponentType]!.entryCount -= 1
                if graph[succComponentType]!.entryCount == 0 {
                    noEntryList.append(succComponentType)
                }
            }

            // Consider this case: legend depends on series, and we call
            // chart.setOption({series: [...]}), where only series is in option.
            // If we do not have 'removeEdgeAndAdd', legendModel.mergeOption will
            // not be called, but only sereis.mergeOption is called. Thus legend
            // have no chance to update its local record about series (like which
            // name of series is available in legend).
            func removeEdgeAndAdd(_ succComponentType: ComponentMainType) {
                targetNameSet[succComponentType] = true
                removeEdge(succComponentType)
            }
        }

        func makeDepndencyGraph(_ fullNameList: [ComponentMainType]) -> (graph: DepGraph, noEntryList: [ComponentMainType]) {
            var graph: DepGraph = [:]
            var noEntryList: [ComponentMainType] = []

            util.each(fullNameList) { (name: ComponentMainType, _) in

                let thisItem = createDependencyGraphItem(&graph, name)
                let originalDeps = dependencyGetter(name)
                thisItem.originalDeps = originalDeps

                let availableDeps = getAvailableDependencies(originalDeps, fullNameList)
                thisItem.entryCount = Double(availableDeps.count)
                if thisItem.entryCount == 0 {
                    noEntryList.append(name)
                }

                util.each(availableDeps) { dependentName, _ in
                    if util.indexOf(thisItem.predecessor, dependentName) < 0 {
                        thisItem.predecessor.append(dependentName)
                    }
                    let thatItem = createDependencyGraphItem(&graph, dependentName)
                    if util.indexOf(thatItem.successor, dependentName) < 0 {
                        thatItem.successor.append(name)
                    }
                }
            }

            return (graph: graph, noEntryList: noEntryList)
        }

        func createDependencyGraphItem(_ graph: inout DepGraph, _ name: ComponentMainType) -> DepGraphItem {
            if graph[name] == nil {
                graph[name] = DepGraphItem()
            }
            return graph[name]!
        }

        func getAvailableDependencies(
            _ originalDeps: [ComponentMainType], _ fullNameList: [ComponentMainType]
        ) -> [ComponentMainType] {
            var availableDeps: [ComponentMainType] = []
            util.each(originalDeps) { dep, _ in
                if util.indexOf(fullNameList, dep) >= 0 { availableDeps.append(dep) }
            }
            return availableDeps
        }

    }

    // upstream `inheritDefaultOption<T, K>(superOption: T, subOption: K): K` is generic
    //   over arbitrary default-option objects; modeled as the dynamic option bag `[String: Any]`
    //   (the project's established dynamic-value approach; cf. ZRenderKit `util.merge`).
    public static func inheritDefaultOption(_ superOption: [String: Any], _ subOption: [String: Any]) -> [String: Any] {
        // See also `model/Component.ts#getDefaultOption`
        // return zrUtil.merge(zrUtil.merge({}, superOption, true), subOption, true);
        var result: [String: Any] = [:]
        util.merge(&result, superOption, true)
        util.merge(&result, subOption, true)
        return result
    }
}
