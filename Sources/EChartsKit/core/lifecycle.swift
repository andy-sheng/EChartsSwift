// Ported from echarts/src/core/lifecycle.ts — keep in sync with upstream
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

// upstream:
//   import Eventful, { EventCallback } from 'zrender/src/core/Eventful';   → see note below
//   import SeriesModel from '../model/Series';                             → model/Series.swift
//   import GlobalModel from '../model/Global';                             → model/Global.swift
//   import { EChartsType } from './echarts';                               → core/ECharts.swift (protocol)
//   import ExtensionAPI from './ExtensionAPI';                             → core/ExtensionAPI.swift
//   import { ModelFinderIdQuery, ModelFinderIndexQuery } from '../util/model';  → util/modelUtil.swift
//   import { DimensionLoose } from '../util/types';                        → util/types.swift
import Foundation

// export interface UpdateLifecycleTransitionSeriesFinder {
//     seriesIndex?: ModelFinderIndexQuery,
//     seriesId?: ModelFinderIdQuery
//     dimension: DimensionLoose;
// }
public struct UpdateLifecycleTransitionSeriesFinder {
    // `ModelFinderIndexQuery` = `number | number[] | 'all' | 'none'` and
    //   `ModelFinderIdQuery` = `OptionId | OptionId[]`. universalTransition's `querySeries` only ever
    //   compares them for equality against `series[i].seriesIndex` / `series[i].id`, so the scalar
    //   forms (`Double` / `String`) are what is modeled here; the array/'all'/'none' forms are not
    //   consumed by any ported call site.
    public var seriesIndex: Double?
    public var seriesId: String?
    public var dimension: DimensionLoose?
    public init(seriesIndex: Double? = nil, seriesId: String? = nil, dimension: DimensionLoose? = nil) {
        self.seriesIndex = seriesIndex
        self.seriesId = seriesId
        self.dimension = dimension
    }
}

// export interface UpdateLifecycleTransitionItem {
//     from?: UpdateLifecycleTransitionSeriesFinder | UpdateLifecycleTransitionSeriesFinder[];
//     to: UpdateLifecycleTransitionSeriesFinder | UpdateLifecycleTransitionSeriesFinder[];
// };
public struct UpdateLifecycleTransitionItem {
    // If `from` not given, it means that do not make series transition mandatorily.
    // There might be transition mapping dy default. Sometimes we do not need them,
    // which might bring about misleading.
    //
    // the `T | T[]` union is not expressible; both are stored as `Any?` and fed through
    //   `model.normalizeToArray` at the (single) consuming site, exactly like upstream.
    public var from: Any?   // UpdateLifecycleTransitionSeriesFinder | [UpdateLifecycleTransitionSeriesFinder]
    public var to: Any?     // UpdateLifecycleTransitionSeriesFinder | [UpdateLifecycleTransitionSeriesFinder]
    public init(from: Any? = nil, to: Any? = nil) {
        self.from = from
        self.to = to
    }
}

// export type UpdateLifecycleTransitionOpt = UpdateLifecycleTransitionItem | UpdateLifecycleTransitionItem[];
//   the union is carried as `Any?` on `UpdateLifecycleParams.seriesTransition` (below) and
//   normalized with `model.normalizeToArray`, as upstream does.
public typealias UpdateLifecycleTransitionOpt = Any

// export interface UpdateLifecycleParams { updatedSeries?, optionChanged?, seriesTransition? }
public struct UpdateLifecycleParams {
    public var updatedSeries: [SeriesModel]?

    /**
     * If this update is from setOption and option is changed.
     */
    public var optionChanged: Bool?

    // Specify series to transition in this setOption.
    public var seriesTransition: UpdateLifecycleTransitionOpt?

    public init(updatedSeries: [SeriesModel]? = nil,
                optionChanged: Bool? = nil,
                seriesTransition: UpdateLifecycleTransitionOpt? = nil) {
        self.updatedSeries = updatedSeries
        self.optionChanged = optionChanged
        self.seriesTransition = seriesTransition
    }
}

// interface LifecycleEvents {
//     'afterinit': [EChartsType],
//     'coordsys:aftercreate': [GlobalModel, ExtensionAPI],
//     'series:beforeupdate': [GlobalModel, ExtensionAPI, UpdateLifecycleParams],
//     'series:layoutlabels': [GlobalModel, ExtensionAPI, UpdateLifecycleParams],
//     'series:transition': [GlobalModel, ExtensionAPI, UpdateLifecycleParams],
//     'series:afterupdate': [GlobalModel, ExtensionAPI, UpdateLifecycleParams]
//     'afterupdate': [GlobalModel, ExtensionAPI]
// }
//
// upstream is `new Eventful<{[key in keyof LifecycleEvents]: EventCallback<LifecycleEvents[key]>}>()`
//   — one Eventful instance whose per-event ARGUMENT TUPLE is statically typed by the mapped type.
//   ZRenderKit's `Eventful` exists, but its `EventCallback` is variadic/untyped (`(Any?...) -> Bool?`),
//   so routing these through it would force every listener to hand-cast `args[0] as! GlobalModel`.
//   Instead this is a hand-rolled emitter with ONE handler list per argument SHAPE (there are exactly
//   three: `[EChartsType]`, `[GlobalModel, ExtensionAPI]`, `[GlobalModel, ExtensionAPI,
//   UpdateLifecycleParams]`), keyed by the same upstream event-name strings. `on`/`trigger` overload on
//   the closure/arg types, so call sites stay byte-identical to upstream
//   (`lifecycle.on('series:transition', cb)` / `lifecycle.trigger('series:transition', ecModel, api, params)`).
//   Event names are NOT validated against the set below (a typo silently never fires) — the price of
//   dropping the mapped type.
public typealias LifecycleAfterInitCallback = (EChartsType) -> Void
public typealias LifecycleModelApiCallback = (GlobalModel, ExtensionAPI) -> Void
public typealias LifecycleUpdateCallback = (GlobalModel, ExtensionAPI, UpdateLifecycleParams) -> Void

public final class Lifecycle {

    // The three handler tables (one per argument shape), keyed by event name.
    private var _afterInitHandlers: [String: [LifecycleAfterInitCallback]] = [:]
    private var _modelApiHandlers: [String: [LifecycleModelApiCallback]] = [:]
    private var _updateHandlers: [String: [LifecycleUpdateCallback]] = [:]

    fileprivate init() {}

    // ---- on ----

    public func on(_ event: String, _ cb: @escaping LifecycleAfterInitCallback) {
        _afterInitHandlers[event, default: []].append(cb)
    }

    public func on(_ event: String, _ cb: @escaping LifecycleModelApiCallback) {
        _modelApiHandlers[event, default: []].append(cb)
    }

    public func on(_ event: String, _ cb: @escaping LifecycleUpdateCallback) {
        _updateHandlers[event, default: []].append(cb)
    }

    // ---- trigger ----

    public func trigger(_ event: String, _ chart: EChartsType) {
        for cb in _afterInitHandlers[event] ?? [] {
            cb(chart)
        }
    }

    public func trigger(_ event: String, _ ecModel: GlobalModel, _ api: ExtensionAPI) {
        for cb in _modelApiHandlers[event] ?? [] {
            cb(ecModel, api)
        }
    }

    public func trigger(_ event: String, _ ecModel: GlobalModel, _ api: ExtensionAPI,
                        _ params: UpdateLifecycleParams) {
        for cb in _updateHandlers[event] ?? [] {
            cb(ecModel, api, params)
        }
    }

    /// Test-only: drop every registered handler (the emitter is a module-global singleton, like
    /// upstream's `const lifecycle = new Eventful(...)`, so a test that wants a clean slate needs this).
    func off() {
        _afterInitHandlers.removeAll()
        _modelApiHandlers.removeAll()
        _updateHandlers.removeAll()
    }
}

// const lifecycle = new Eventful<...>();
// export default lifecycle;
public let lifecycle = Lifecycle()

// ============================================================================
// upstream echarts.ts:3091 —
//   export function registerUpdateLifecycle<T extends keyof LifecycleEvents>(
//       name: T, cb: (...args: LifecycleEvents[T]) => void
//   ): void { (lifecycle as any).on(name, cb); }
// re-exported by extension.ts onto the `EChartsExtensionInstallRegisters` bag that every
// `install(registers)` receives. The registrar base class lives in coord/axisStatistics.swift (see its
// note); the method is added here, next to the emitter it forwards to, mirroring
// core/action.swift's `extension EChartsExtensionInstallRegisters` precedent for `registerAction`.
// ============================================================================
extension EChartsExtensionInstallRegisters {
    public func registerUpdateLifecycle(_ name: String, _ cb: @escaping LifecycleUpdateCallback) {
        lifecycle.on(name, cb)
    }
    public func registerUpdateLifecycle(_ name: String, _ cb: @escaping LifecycleModelApiCallback) {
        lifecycle.on(name, cb)
    }
    public func registerUpdateLifecycle(_ name: String, _ cb: @escaping LifecycleAfterInitCallback) {
        lifecycle.on(name, cb)
    }
}
