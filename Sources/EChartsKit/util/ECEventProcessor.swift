// Ported from echarts/src/util/ECEventProcessor.ts — keep in sync with upstream
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
// upstream:
//   import { EventProcessor, EventQuery } from 'zrender/src/core/Eventful';  → ZRenderKit.EventProcessor/EventQuery
//   import { ECActionEvent, NormalizedEventQuery, EventQueryItem, ECElementEvent } from './types';
//                                                                            → sibling types.swift
//   import ComponentModel from '../model/Component';                         → model/Component.swift
//   import ComponentView from '../view/Component';                           → view/ComponentView.swift
//   import ChartView from '../view/Chart';                                   → view/Chart.swift
//   import * as zrUtil from 'zrender/src/core/util';                         → util (ZRenderKit)
//   import { parseClassType } from './clazz';                                → clazz.parseClassType
//   import Element from 'zrender/src/Element';                               → ZRenderKit.Element

/**
 * Usage of query:
 * `chart.on('click', query, handler);`
 * The `query` can be:
 * + The component type query string, only `mainType` or `mainType.subType`,
 *   like: 'xAxis', 'series', 'xAxis.category' or 'series.line'.
 * + The component query object, like:
 *   `{seriesIndex: 2}`, `{seriesName: 'xx'}`, `{seriesId: 'some'}`,
 *   `{xAxisIndex: 2}`, `{xAxisName: 'xx'}`, `{xAxisId: 'some'}`.
 * + The data query object, like:
 *   `{dataIndex: 123}`, `{dataType: 'link'}`, `{name: 'some'}`.
 * + The other query object (cmponent customized query), like:
 *   `{element: 'some'}` (only available in custom series).
 *
 * Caveat: If a prop in the `query` object is `null/undefined`, it is the
 * same as there is no such prop in the `query` object.
 */
// note (CONVENTIONS §2): ZRenderKit's `EventProcessor` is a STRUCT of three optional closures (the
//   upstream TS interface has three optional methods). `ECEventProcessor` is a `final class` because
//   `eventInfo` is mutable state written by `ECharts._initEvents` before each `trigger` and cleared by
//   `afterTrigger`. `asEventProcessor()` adapts it into the closure struct `Eventful` stores.
public final class ECEventProcessor {

    // These info required: targetEl, packedEvent, model, view
    public struct EventInfo {
        public var targetEl: Element?
        public var packedEvent: ECEventParams        // `ECActionEvent | ECElementEvent` union → protocol
        public var model: ComponentModel?
        public var view: AnyObject?                  // `ComponentView | ChartView` union → AnyObject
        public init(targetEl: Element?, packedEvent: ECEventParams, model: ComponentModel?, view: AnyObject?) {
            self.targetEl = targetEl
            self.packedEvent = packedEvent
            self.model = model
            self.view = view
        }
    }
    public var eventInfo: EventInfo?

    public init() {}

    public func normalizeQuery(_ query: EventQuery) -> NormalizedEventQuery {
        var cptQuery: EventQueryItem = [:]
        var dataQuery: EventQueryItem = [:]
        var otherQuery: EventQueryItem = [:]

        // `query` is `mainType` or `mainType.subType` of component.
        if let queryStr = query as? String {
            let condCptType = clazz.parseClassType(queryStr)
            // `.main` and `.sub` may be ''.
            cptQuery["mainType"] = condCptType.main.isEmpty ? nil : condCptType.main
            cptQuery["subType"] = condCptType.sub.isEmpty ? nil : condCptType.sub
        }
        // `query` is an object, convert to {mainType, index, name, id}.
        else {
            // `xxxIndex`, `xxxName`, `xxxId`, `name`, `dataIndex`, `dataType` is reserved,
            // can not be used in `compomentModel.filterForExposedEvent`.
            let suffixes = ["Index", "Name", "Id"]
            let dataKeys = ["name": 1, "dataIndex": 1, "dataType": 1]
            let queryObj = (query as? [String: Any]) ?? [:]
            for (key, val) in queryObj {
                var reserved = false
                for i in 0..<suffixes.count {
                    let propSuffix = suffixes[i]
                    // `key.lastIndexOf(propSuffix)`, then `suffixPos > 0 && suffixPos === key.length - len`
                    //   → the key ENDS WITH the suffix and has a non-empty mainType prefix.
                    if key.hasSuffix(propSuffix) && key.count > propSuffix.count {
                        let mainType = String(key.dropLast(propSuffix.count))
                        // Consider `dataIndex`.
                        if mainType != "data" {
                            cptQuery["mainType"] = mainType
                            cptQuery[propSuffix.lowercased()] = val
                            reserved = true
                        }
                    }
                }
                if dataKeys[key] != nil {
                    dataQuery[key] = val
                    reserved = true
                }
                if !reserved {
                    otherQuery[key] = val
                }
            }
        }

        return NormalizedEventQuery(
            cptQuery: cptQuery,
            dataQuery: dataQuery,
            otherQuery: otherQuery
        )
    }

    public func filter(_ eventType: String, _ query: NormalizedEventQuery) -> Bool {
        // They should be assigned before each trigger call.
        let eventInfo = self.eventInfo

        guard let eventInfo = eventInfo else {
            return true
        }

        let targetEl = eventInfo.targetEl
        let packedEvent = eventInfo.packedEvent
        let model = eventInfo.model
        let view = eventInfo.view

        // For event like 'globalout'.
        guard let model = model, let view = view else {
            return true
        }

        let cptQuery = query.cptQuery
        let dataQuery = query.dataQuery

        // upstream's local `check(query, host, prop, propOnHost)` does a DYNAMIC property read
        //   (`host[propOnHost || prop]`) on the model / packed event. Swift has no dynamic member lookup,
        //   so the two hosts are read through explicit accessors (`modelProp` / `packedProp`) that resolve
        //   exactly the props upstream queries. `jsLooseEquals` reproduces `host[prop] === query[prop]`
        //   for the boxed `Any` values a query dict carries (an index may arrive as Int or Double).
        func check(_ query: EventQueryItem, _ host: (String) -> Any?, _ prop: String, _ propOnHost: String? = nil) -> Bool {
            // return query[prop] == null || host[propOnHost || prop] === query[prop];
            guard let q = query[prop], !(q is NSNull) else { return true }
            return jsLooseEquals(host(propOnHost ?? prop), q)
        }

        let modelProp: (String) -> Any? = { prop in
            switch prop {
            case "mainType": return model.mainType
            case "subType": return model.subType
            case "componentIndex": return model.componentIndex
            case "name": return model.name
            case "id": return model.id
            default: return nil
            }
        }
        let packedProp: (String) -> Any? = { prop in
            switch prop {
            case "name": return packedEvent.name
            case "dataIndex": return packedEvent.dataIndex
            case "dataType": return packedEvent.dataType
            default: return packedEvent[prop]
            }
        }

        return check(cptQuery, modelProp, "mainType")
            && check(cptQuery, modelProp, "subType")
            && check(cptQuery, modelProp, "index", "componentIndex")
            && check(cptQuery, modelProp, "name")
            && check(cptQuery, modelProp, "id")
            && check(dataQuery, packedProp, "name")
            && check(dataQuery, packedProp, "dataIndex")
            && check(dataQuery, packedProp, "dataType")
            // upstream: `!view.filterForExposedEvent || view.filterForExposedEvent(...)` — the method is
            //   OPTIONAL upstream; here every view has it (ComponentView/ChartView base returns true).
            && filterForExposedEvent(view, eventType, query.otherQuery, targetEl, packedEvent)
    }

    private func filterForExposedEvent(
        _ view: AnyObject, _ eventType: String, _ otherQuery: EventQueryItem,
        _ targetEl: Element?, _ packedEvent: ECEventParams
    ) -> Bool {
        // `targetEl` is non-null whenever a model+view were resolved (only 'globalout' has none, and that
        //   path already returned above); guard rather than force-unwrap.
        guard let targetEl = targetEl else { return true }
        if let chartView = view as? ChartView {
            return chartView.filterForExposedEvent(eventType, otherQuery, targetEl, packedEvent)
        }
        if let componentView = view as? ComponentView {
            return componentView.filterForExposedEvent(eventType, otherQuery, targetEl, packedEvent)
        }
        return true
    }

    public func afterTrigger() {
        // Make sure the eventInfo won't be used in next trigger.
        self.eventInfo = nil
    }

    /// Adapt to the closure-struct `EventProcessor` that `Eventful` stores (ZRenderKit models the
    /// upstream all-optional-methods interface as a struct of optional closures).
    public func asEventProcessor() -> EventProcessor {
        return EventProcessor(
            normalizeQuery: { [unowned self] query in self.normalizeQuery(query) },
            filter: { [unowned self] eventType, query in
                // Eventful stores the normalized query as `EventQuery` (Any); it is whatever
                // `normalizeQuery` returned.
                guard let nq = query as? NormalizedEventQuery else { return true }
                return self.filter(eventType, nq)
            },
            afterTrigger: { [unowned self] _ in self.afterTrigger() }
        )
    }
}

/// `host[prop] === query[prop]` for values boxed as `Any` (JS compares primitives by value).
/// A numeric query value may arrive as `Int` (`["seriesIndex": 0]`) while the host stores `Double`.
func jsLooseEquals(_ a: Any?, _ b: Any?) -> Bool {
    if a == nil && b == nil { return true }
    guard let a = a, let b = b else { return false }
    if let na = ecEventNumber(a), let nb = ecEventNumber(b) { return na == nb }
    if let sa = a as? String, let sb = b as? String { return sa == sb }
    if let ba = a as? Bool, let bb = b as? Bool { return ba == bb }
    if let sa = a as? SeriesDataType, let sb = b as? SeriesDataType { return sa == sb }
    // Reference identity, as JS `===` does for objects.
    let oa = a as AnyObject, ob = b as AnyObject
    return oa === ob
}
