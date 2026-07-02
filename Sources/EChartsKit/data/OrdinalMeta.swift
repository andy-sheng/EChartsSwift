// Ported from echarts/src/data/OrdinalMeta.ts — keep in sync with upstream
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

// import {createHashMap, isObject, map, HashMap, isString} from 'zrender/src/core/util';
//   -> `isObject`/`map`/`isString` are ZRenderKit.util.* ; `createHashMap`/`HashMap` are
//      the EChartsKit local shim (same module — see util/model.swift; ZRenderKit has not
//      yet ported them, see ZRenderKit/Core/util.swift PORT-TODO).
// import Model from '../model/Model';                     -> Model (same-module forward ref)
// import { OrdinalNumber, OrdinalRawValue } from '../util/types';  -> same module
import Foundation
import ZRenderKit

private var uidBase: Double = 0

public final class OrdinalMeta {

    public private(set) var categories: [OrdinalRawValue]   // readonly categories: OrdinalRawValue[]
    // PORT-TODO: upstream is `readonly` (reference fixed, elements mutable). Modeled as
    // `private(set) var` so `parseAndCollect` can mutate elements while keeping it
    // externally read-only.

    private var _needCollect: Bool

    private var _deduplication: Bool

    private var _map: HashMap<OrdinalNumber>?

    private var _onCollect: ((OrdinalRawValue, OrdinalNumber) -> Void)?

    public let uid: OrdinalNumber   // readonly uid: number

    /**
     * PENDING - Regarding forcibly converting to string:
     *  In the early days, the underlying hash map impl used JS plain object and converted the key to
     *  string; later in https://github.com/ecomfe/zrender/pull/966 it was changed to a JS Map (in supported
     *  platforms), which does not require string keys. But consider any input that `scale/Ordinal['parse']`
     *  is involved, a number input represents an `OrdinalNumber` (i.e., an index), and affect the query
     *  behavior:
     *    - If forcbily converting to string:
     *      pros: users can use numeric string (such as, '123') to query the raw data (123), tho it's probably
     *      still confusing.
     *      cons: NaN/null/undefined in data will be equals to 'NaN'/'null'/'undefined', if simply using
     *      `val + ''` to convert them, like currently `getName` does.
     *    - Otherwise:
     *      pros: see NaN/null/undefined case above.
     *      cons: users cannot query the raw data (123) any more.
     *  There are two inconsistent behaviors in the current impl:
     *    - Force conversion is applied on the case `xAxis{data: ['aaa', 'bbb', ...]}`,
     *      but no conversion applied to the case `xAxis{data: [{value: 'aaa'}, ...]}` and
     *      the case `dataset: {source: [['aaa', 123], ['bbb', 234], ...]}`.
     *    - behaves differently according to whether JS Map is supported (the polyfill is simply using JS
     *      plain object) (tho it seems rare platform that do not support it).
     *  Since there's no sufficient good solution to offset cost of the breaking change, we preserve the
     *  current behavior, until real issues is reported.
     */
    public init(
        categories: [OrdinalRawValue]? = nil,
        needCollect: Bool? = nil,
        deduplication: Bool? = nil,
        // Called only on `needCollect` is true and collect happens.
        onCollect: ((OrdinalRawValue, OrdinalNumber) -> Void)? = nil
    ) {
        self.categories = categories ?? []   // opt.categories || []
        // upstream stores the (possibly undefined) bool directly; it is consumed truthily,
        // so undefined collapses to false.
        self._needCollect = needCollect ?? false
        self._deduplication = deduplication ?? false
        uidBase += 1
        self.uid = uidBase   // this.uid = ++uidBase;
        self._onCollect = onCollect
    }

    public static func createByAxisModel(_ axisModel: Model) -> OrdinalMeta {
        // const option = axisModel.option; const data = option.data;
        // Model.option now exists (model/Model.swift) — read categories from the axis option bag
        // (e.g. `xAxis.data`) so category axes actually collect their categories.
        let option = (axisModel.option as? [String: Any]) ?? [:]
        let data = option["data"] as? [OrdinalRawValue]   // const data = option.data;
        // const categories = data && map(data, getName);
        let categories = data != nil ? util.map(data, { (obj, _) in getName(obj) }) : nil

        return OrdinalMeta(
            categories: categories,
            needCollect: categories == nil,   // needCollect: !categories,
            // deduplication is default in axis.
            deduplication: (option["dedplication"] as? Bool) != false   // option.dedplication !== false
        )
    }

    public func getOrdinal(_ category: OrdinalRawValue) -> OrdinalNumber? {
        // upstream return type is OrdinalNumber, but `HashMap.get` may return undefined,
        // so this is modeled as Optional.
        return self._getOrCreateMap().get(category)
    }

    /**
     * @return The ordinal. If not found, return NaN.
     */
    public func parseAndCollect(_ category: OrdinalRawValue) -> OrdinalNumber {
        // category: OrdinalRawValue | OrdinalNumber
        var index: OrdinalNumber?
        let needCollect = self._needCollect

        // The value of category dim can be the index of the given category set.
        // This feature is only supported when !needCollect, because we should
        // consider a common case: a value is 2017, which is a number but is
        // expected to be tread as a category. This case usually happen in dataset,
        // where it happent to be no need of the index feature.
        if !util.isString(category) && !needCollect {
            // category here is an OrdinalNumber (the index into the category set)
            return (category as? OrdinalNumber) ?? OrdinalNumber.nan
            // PORT-TODO: numeric coercion — assumes numbers flow as Double (CONVENTIONS §1).
        }

        // Optimize for the scenario:
        // category is ['2012-01-01', '2012-01-02', ...], where the input
        // data has been ensured not duplicate and is large data.
        // Notice, if a dataset dimension provide categroies, usually echarts
        // should remove duplication except user tell echarts dont do that
        // (set axis.deduplication = false), because echarts do not know whether
        // the values in the category dimension has duplication (consider the
        // parallel-aqi example)
        if needCollect && !self._deduplication {
            index = OrdinalNumber(self.categories.count)
            self.categories.append(category)   // this.categories[index] = category;
            self._onCollect?(category, index!)
            return index!
        }

        let map = self._getOrCreateMap()
        index = map.get(category)

        if index == nil {   // index == null
            if needCollect {
                index = OrdinalNumber(self.categories.count)
                self.categories.append(category)   // this.categories[index] = category;
                map.set(category, index!)
                self._onCollect?(category, index!)
            }
            else {
                index = OrdinalNumber.nan
            }
        }

        return index!
    }

    // Consider big data, do not create map until needed.
    private func _getOrCreateMap() -> HashMap<OrdinalNumber> {
        if let map = self._map {
            return map
        }
        // upstream: this._map = createHashMap<OrdinalNumber>(this.categories)
        // PORT-TODO: the EChartsKit `createHashMap` shim has no init-from-array overload
        // (upstream seeds value->index from the array via `set(value, key)`); seed manually
        // until ZRenderKit ports `createHashMap`.
        let map: HashMap<OrdinalNumber> = createHashMap()
        for i in 0..<self.categories.count {
            map.set(self.categories[i], OrdinalNumber(i))
        }
        self._map = map
        return map
    }
}

// upstream: function getName(obj: any): string
// PORT-TODO: returns OrdinalRawValue (not String) so the object branch can pass `obj.value`
// through unchanged, as upstream does at runtime despite its `: string` annotation.
private func getName(_ obj: Any?) -> OrdinalRawValue {
    if util.isObject(obj), let dict = obj as? [String: Any],
       let value = dict["value"], !(value is NSNull) {   // isObject(obj) && obj.value != null
        return value
    }
    else {
        return jsToString(obj)   // obj + ''
    }
}

// JS `x + ''` string coercion for a value of unknown type. Not a standalone upstream symbol.
private func jsToString(_ val: Any?) -> String {
    switch val {
    case nil: return "undefined"
    case let s as String: return s
    case let d as Double:
        if d.isNaN { return "NaN" }
        if d.isInfinite { return d > 0 ? "Infinity" : "-Infinity" }
        if d == d.rounded() && Swift.abs(d) < 1e21 { return String(Int64(d)) }
        return String(d)
    case let i as Int: return String(i)
    case let b as Bool: return b ? "true" : "false"
    case is NSNull: return "null"
    default: return String(describing: val!)
    }
}
