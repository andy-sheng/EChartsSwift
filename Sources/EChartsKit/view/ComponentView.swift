// Ported from echarts/src/view/Component.ts — keep in sync with upstream
// NOTE: file renamed Component.swift -> ComponentView.swift to avoid an object-file name collision
//   with model/Component.swift (SwiftPM requires unique source basenames per module; cf. the
//   util/component.ts -> componentUtil.swift rename, PORT_STATUS §8). No identifiers change; the
//   class is still `ComponentView`.
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

// import Group from 'zrender/src/graphic/Group';               -> ZRenderKit `Group`.
// import * as componentUtil from '../util/component';           -> EChartsKit `component` namespace (util/componentUtil.swift).
// import * as clazzUtil from '../util/clazz';                   -> EChartsKit `clazz` namespace + `ClassManager` (util/clazz.swift).
// import ComponentModel from '../model/Component';              -> EChartsKit `ComponentModel` (model/Component.swift).
// import GlobalModel from '../model/Global';                    -> EChartsKit `GlobalModel` (model/Global.swift).
// import ExtensionAPI from '../core/ExtensionAPI';              -> EChartsKit `ExtensionAPI` (core/ExtensionAPI.swift).
// import {Payload, ViewRootGroup, ECActionEvent, EventQueryItem, ECElementEvent} from '../util/types';
//   -> EChartsKit util/types.swift (Payload, ViewRootGroup, ECActionEvent, EventQueryItem, ECElementEvent).
// import Element from 'zrender/src/Element';                    -> ZRenderKit `Element`.
// import SeriesModel from '../model/Series';                    -> EChartsKit `SeriesModel` (model/Series.swift).


// upstream: `interface ComponentView { ... }` declaration-merged with the class below. It declares
//   optional/injectable hooks a subclass may implement. Swift has no declaration merging, so these
//   are folded into the class as `open` methods (overridable no-ops / documented defaults). The
//   optional (`?`) members are represented by an overridable default; `filterForExposedEvent` is
//   the only non-optional interface member (subclasses that expose events override it).
//
//     updateTransform?(model, ecModel, api, payload): void | {update: true};
//     filterForExposedEvent(eventType, query, targetEl, packedEvent): boolean;
//     findHighDownDispatchers?(name): Element[];
//     focusBlurEnabled?: boolean;


// CONVENTIONS §2/§4: reference type + subclassed by AxisView/GridView/... — `open class`.
open class ComponentView: ViewRootGroup {

    // [Caution]: Because this class or descendants can be used as `XXX.extend(subProto)`,
    // the class members must not be initialized in constructor or declaration place.
    // Otherwise there is bad case:
    //   class A {xxx = 1;}
    //   enableClassExtend(A);
    //   class B extends A {}
    //   var C = B.extend({xxx: 5});
    //   var c = new C();
    //   console.log(c.xxx); // expect 5 but always 1.
    // PORT-NOTE: the caveat above is about upstream's prototype `extend` machinery, which Swift
    //   replaces with native subclassing (clazz.enableClassExtend is a no-op); it does not apply
    //   here, but the comment is preserved as part of the diffable surface.

    // upstream: `readonly group: ViewRootGroup;` — a `Group` augmented with an optional
    //   `__ecComponentInfo`. Typed here as the concrete `Group`; the augmentation is exposed via
    //   the `ViewRootGroup` conformance below (see `__ecComponentInfo`).
    public let group: Group

    public let uid: String

    // ----------------------
    // Injectable properties
    // ----------------------
    // PORT-NOTE: upstream declares these non-optional but assigns them after construction
    //   (injected by the render pipeline). Modeled as Optionals so the base class need not
    //   initialize them, matching the "not initialized in declaration place" caveat above.
    public var __model: ComponentModel?
    public var __alive: Bool?
    public var __id: String?

    // upstream augmentation `interface ViewRootGroup extends Group { __ecComponentInfo?: {...} }`.
    //   The view's `group` is a `ViewRootGroup`; the marker lives on that group instance. Since a
    //   bare `Group` from ZRenderKit does not carry this slot, it is held on the view and the view
    //   conforms to `ViewRootGroup`. PORT-NOTE: confirm augmentation strategy (see util/types.swift).
    public var __ecComponentInfo: ViewRootGroupComponentInfo?

    public init() {
        self.group = Group()
        self.uid = component.getUID("viewComponent")
    }

    open func `init`(_ ecModel: GlobalModel, _ api: ExtensionAPI) {}

    open func render(_ model: ComponentModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload) {}

    open func dispose(_ ecModel: GlobalModel, _ api: ExtensionAPI) {}

    open func updateView(_ model: ComponentModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload) {
        // Do nothing;
    }

    open func updateLayout(_ model: ComponentModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload) {
        // Do nothing;
    }

    open func updateVisual(_ model: ComponentModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload) {
        // Do nothing;
    }

    /**
     * Hook for toggle blur target series.
     * Can be used in marker for blur or leave blur the markers
     */
    open func toggleBlurSeries(_ seriesModels: [SeriesModel], _ isBlur: Bool, _ ecModel: GlobalModel) {
        // Do nothing;
    }

    /**
     * Traverse the new rendered elements.
     *
     * It will traverse the new added element in progressive rendering.
     * And traverse all in normal rendering.
     */
    // PORT-NOTE: upstream `cb: (el: Element) => boolean | void`; ZRenderKit `Group.traverse` takes
    //   `(Element) -> Bool` (a truthy return short-circuits the branch). The `void` arm is dropped —
    //   callers that do not short-circuit return `false`.
    open func eachRendered(_ cb: (_ el: Element) -> Bool) {
        let group = self.group
        // `if (group)` — always non-nil here (`group` is a non-optional stored property).
        _ = group.traverse(cb)
    }

    // ------------------------------------------------------------------
    // Optional/overridable interface hooks (declaration-merged upstream).
    // ------------------------------------------------------------------

    // upstream (optional): updateTransform?(model, ecModel, api, payload): void | {update: true};
    //   The `void | {update: true}` return is modeled as a TRI-STATE `Bool?`, mirroring how upstream
    //   distinguishes "no hook at all" from "hook returned void" (echarts.ts:1964-1970):
    //     `nil`   == the view has NO hook (this base implementation) → `ECharts.updateTransform()`
    //                pushes it onto the dirty list and falls back to a full render;
    //     `false` == an IMPLEMENTED hook returning upstream's `void` — handled in place, NOT dirtied;
    //     `true`  == upstream `{update: true}`.
    //   So an overriding view that re-lays out in place must return `false`, NOT `nil`.
    open func updateTransform(
        _ model: ComponentModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) -> Bool? {
        return nil
    }

    /**
     * Pass only when return `true`.
     * Implement it if needed.
     */
    // PORT-NOTE: `packedEvent: ECActionEvent | ECElementEvent` union modeled as `Any`.
    //   Upstream this is an OPTIONAL member (`filterForExposedEvent?`), and `ECEventProcessor.filter`
    //   short-circuits with `!view.filterForExposedEvent || view.filterForExposedEvent(...)` — i.e. a
    //   view that does not implement it lets every queried event THROUGH. A Swift `open func` is always
    //   present, so the base returns `true` to model that absence (ChartView already does). Returning
    //   `false` here — as this base did while the event bus was deferred — silently swallowed every
    //   query-filtered component event (`chart.on('click', 'xAxis', …)`).
    open func filterForExposedEvent(
        _ eventType: String, _ query: EventQueryItem, _ targetEl: Element, _ packedEvent: Any
    ) -> Bool {
        return true
    }

    // upstream (optional): findHighDownDispatchers?(name): Element[];
    //   Optional hook enabling component-level hover link (upstream only Geo implements it). `nil`
    //   models the upstream "method absent" check in `findComponentHighDownDispatchers`
    //   (states.ts:615 `if (!view || !view.findHighDownDispatchers)`); subclasses that support the
    //   feature override to return the dispatcher elements.
    open func findHighDownDispatchers(_ name: String?) -> [Element]? {
        return nil
    }

    // upstream (optional): focusBlurEnabled?: boolean;
    //   Modeled as an overridable base member defaulting to `false` (upstream optional-absent is falsy;
    //   the guard is `if (!view || !view.focusBlurEnabled)`, states.ts:536). Only GeoView opts in
    //   (overrides to `true`). Consulted by `states.blurComponent`.
    open var focusBlurEnabled: Bool = false

    // upstream: static registerClass: clazzUtil.ClassManager['registerClass'];
    //
    // Deviation: upstream mounts this static onto the class object via
    // `enableClassManagement(ComponentView)`. Swift metatypes can not have methods mounted at
    // runtime, so the registry is held as a static `ClassManager` instance (the faithful
    // translation produced by `clazz.enableClassManagement()`) and the static forwards to it.
    private static let _classManager: ClassManager = clazz.enableClassManagement()

    @discardableResult
    public static func registerClass(_ clz: Constructor) -> Constructor {
        return _classManager.registerClass(clz)
    }

    // PORT-NOTE: `getClass` is part of the mounted `ClassManager` surface used by the view registry
    //   (echarts.ts looks views up by type). Exposed here for completeness (upstream reaches it via
    //   the same `enableClassManagement` mount).
    public static func getClass(
        _ componentMainType: ComponentMainType,
        _ subType: ComponentSubType? = nil,
        _ throwWhenNotFound: Bool = false
    ) -> Constructor? {
        return _classManager.getClass(componentMainType, subType, throwWhenNotFound)
    }
}


// upstream:
//   export type ComponentViewConstructor = typeof ComponentView
//       & clazzUtil.ExtendableConstructor
//       & clazzUtil.ClassManager;
//   clazzUtil.enableClassExtend(ComponentView as ComponentViewConstructor);
//   clazzUtil.enableClassManagement(ComponentView as ComponentViewConstructor);
//
// PORT-NOTE: no Swift equivalent for the `typeof ComponentView & ExtendableConstructor & ClassManager`
//   intersection. `enableClassExtend` is a no-op (native subclassing); the class-management surface
//   is provided by `ComponentView._classManager` + the static `registerClass`/`getClass` forwarders
//   above (initialized at first access).

// export default ComponentView;  -> `class ComponentView` above.
