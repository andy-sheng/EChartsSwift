// Ported from echarts/src/data/DataDiffer.ts — keep in sync with upstream
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

// import {ArrayLike} from 'zrender/src/core/types';
//   -> `ArrayLike<unknown>` is modeled as `[Any]` (CONVENTIONS §1). The data arrays here
//      are only walked by `.length`/`[i]` and handed to the key getters.
import Foundation

// return key.
// PORT-NOTE: upstream `DiffKeyGetter<CTX>` carries a `this: DataDiffer<CTX>` binding so the
//   getter may read `this.context`. Swift closures have no `this`; callers that need the
//   context must capture the differ explicitly. Param `value: unknown` -> `Any`.
public typealias DiffKeyGetter = (_ value: Any, _ index: Int) -> String

public typealias DiffCallbackAdd = (_ newIndex: Int) -> Void
public typealias DiffCallbackUpdate = (_ newIndex: Int, _ oldIndex: Int) -> Void
public typealias DiffCallbackRemove = (_ oldIndex: Int) -> Void
public typealias DiffCallbackUpdateManyToOne = (_ newIndex: Int, _ oldIndex: [Int]) -> Void
public typealias DiffCallbackUpdateOneToMany = (_ newIndex: [Int], _ oldIndex: Int) -> Void
public typealias DiffCallbackUpdateManyToMany = (_ newIndex: [Int], _ oldIndex: [Int]) -> Void

/**
 * The value of `DataIndexMap` can only be:
 * + a number
 * + a number[] that length >= 2.
 * + null/undefined
 */
// PORT-NOTE: upstream `{[key: string]: number | number[]}`. Modeled as `[String: Any]`
//   whose values are `Int` or `[Int]`; `null` is represented by absence of the key
//   (`dict[key] = nil`), which yields the same length-0 behavior as upstream `null`.
public typealias DataIndexMap = [String: Any]

private func dataIndexMapValueLength(
    _ valNumOrArrLengthMoreThan2: Any?
) -> Int {
    if valNumOrArrLengthMoreThan2 == nil {
        return 0
    }
    if let arr = valNumOrArrLengthMoreThan2 as? [Int] {
        return arr.count != 0 ? arr.count : 1
    }
    return 1
}

private func defaultKeyGetter(_ item: Any) -> String {
    return item as! String
}

public enum DataDiffMode: String {
    case oneToOne
    case multiple
}

public final class DataDiffer<CTX> {

    private var _old: [Any]
    private var _new: [Any]
    private var _oldKeyGetter: DiffKeyGetter
    private var _newKeyGetter: DiffKeyGetter
    private var _add: DiffCallbackAdd?
    private var _update: DiffCallbackUpdate?
    private var _updateManyToOne: DiffCallbackUpdateManyToOne?
    private var _updateOneToMany: DiffCallbackUpdateOneToMany?
    private var _updateManyToMany: DiffCallbackUpdateManyToMany?
    private var _remove: DiffCallbackRemove?
    private var _diffModeMultiple: Bool

    public let context: CTX?

    /**
     * @param context Can be visited by this.context in callback.
     */
    public init(
        _ oldArr: [Any],
        _ newArr: [Any],
        _ oldKeyGetter: DiffKeyGetter? = nil,
        _ newKeyGetter: DiffKeyGetter? = nil,
        _ context: CTX? = nil,
        // By default: 'oneToOne'.
        _ diffMode: DataDiffMode? = nil
    ) {
        self._old = oldArr
        self._new = newArr

        self._oldKeyGetter = oldKeyGetter ?? { value, _ in defaultKeyGetter(value) }
        self._newKeyGetter = newKeyGetter ?? { value, _ in defaultKeyGetter(value) }

        // Visible in callback via `this.context`;
        self.context = context

        self._diffModeMultiple = diffMode == .multiple
    }

    /**
     * Callback function when add a data
     */
    @discardableResult
    public func add(_ func_: @escaping DiffCallbackAdd) -> DataDiffer {
        self._add = func_
        return self
    }

    /**
     * Callback function when update a data
     */
    @discardableResult
    public func update(_ func_: @escaping DiffCallbackUpdate) -> DataDiffer {
        self._update = func_
        return self
    }

    /**
     * Callback function when update a data and only work in `cbMode: 'byKey'`.
     */
    @discardableResult
    public func updateManyToOne(_ func_: @escaping DiffCallbackUpdateManyToOne) -> DataDiffer {
        self._updateManyToOne = func_
        return self
    }

    /**
     * Callback function when update a data and only work in `cbMode: 'byKey'`.
     */
    @discardableResult
    public func updateOneToMany(_ func_: @escaping DiffCallbackUpdateOneToMany) -> DataDiffer {
        self._updateOneToMany = func_
        return self
    }
    /**
     * Callback function when update a data and only work in `cbMode: 'byKey'`.
     */
    @discardableResult
    public func updateManyToMany(_ func_: @escaping DiffCallbackUpdateManyToMany) -> DataDiffer {
        self._updateManyToMany = func_
        return self
    }

    /**
     * Callback function when remove a data
     */
    @discardableResult
    public func remove(_ func_: @escaping DiffCallbackRemove) -> DataDiffer {
        self._remove = func_
        return self
    }

    public func execute() {
        // upstream: this[this._diffModeMultiple ? '_executeMultiple' : '_executeOneToOne']();
        if self._diffModeMultiple {
            self._executeMultiple()
        }
        else {
            self._executeOneToOne()
        }
    }

    private func _executeOneToOne() {
        let oldArr = self._old
        let newArr = self._new
        var newDataIndexMap: DataIndexMap? = [:]
        var oldDataKeyArr: [String] = [String](repeating: "", count: oldArr.count)
        var newDataKeyArr: [String] = [String](repeating: "", count: newArr.count)
        var nullMap: DataIndexMap? = nil

        self._initIndexMap(oldArr, &nullMap, &oldDataKeyArr, self._oldKeyGetter)
        self._initIndexMap(newArr, &newDataIndexMap, &newDataKeyArr, self._newKeyGetter)

        for i in 0..<oldArr.count {
            let oldKey = oldDataKeyArr[i]
            let newIdxMapVal = newDataIndexMap![oldKey]
            let newIdxMapValLen = dataIndexMapValueLength(newIdxMapVal)

            // idx can never be empty array here. see 'set null' logic below.
            if newIdxMapValLen > 1 {
                // Consider there is duplicate key (for example, use dataItem.name as key).
                // We should make sure every item in newArr and oldArr can be visited.
                // PORT-NOTE: upstream `shift()` mutates the array stored in the map in place
                //   (reference). Swift arrays are value types, so we explicitly write the
                //   shifted array back to the map to keep the same semantics.
                var newIdxArr = newIdxMapVal as! [Int]
                let newIdx = newIdxArr.removeFirst()
                if newIdxArr.count == 1 {
                    newDataIndexMap![oldKey] = newIdxArr[0]
                }
                else {
                    newDataIndexMap![oldKey] = newIdxArr
                }
                self._update?(newIdx, i)
            }
            else if newIdxMapValLen == 1 {
                newDataIndexMap![oldKey] = nil
                self._update?(newIdxMapVal as! Int, i)
            }
            else {
                self._remove?(i)
            }
        }

        self._performRestAdd(newDataKeyArr, &newDataIndexMap)
    }

    /**
     * For example, consider the case:
     * oldData: [o0, o1, o2, o3, o4, o5, o6, o7],
     * newData: [n0, n1, n2, n3, n4, n5, n6, n7, n8],
     * Where:
     *     o0, o1, n0 has key 'a' (many to one)
     *     o5, n4, n5, n6 has key 'b' (one to many)
     *     o2, n1 has key 'c' (one to one)
     *     n2, n3 has key 'd' (add)
     *     o3, o4 has key 'e' (remove)
     *     o6, o7, n7, n8 has key 'f' (many to many, treated as add and remove)
     * Then:
     *     (The order of the following directives are not ensured.)
     *     this._updateManyToOne(n0, [o0, o1]);
     *     this._updateOneToMany([n4, n5, n6], o5);
     *     this._update(n1, o2);
     *     this._remove(o3);
     *     this._remove(o4);
     *     this._remove(o6);
     *     this._remove(o7);
     *     this._add(n2);
     *     this._add(n3);
     *     this._add(n7);
     *     this._add(n8);
     */
    private func _executeMultiple() {
        let oldArr = self._old
        let newArr = self._new
        var oldDataIndexMap: DataIndexMap? = [:]
        var newDataIndexMap: DataIndexMap? = [:]
        var oldDataKeyArr: [String] = []
        var newDataKeyArr: [String] = []

        self._initIndexMap(oldArr, &oldDataIndexMap, &oldDataKeyArr, self._oldKeyGetter)
        self._initIndexMap(newArr, &newDataIndexMap, &newDataKeyArr, self._newKeyGetter)

        for i in 0..<oldDataKeyArr.count {
            let oldKey = oldDataKeyArr[i]
            let oldIdxMapVal = oldDataIndexMap![oldKey]
            let newIdxMapVal = newDataIndexMap![oldKey]
            let oldIdxMapValLen = dataIndexMapValueLength(oldIdxMapVal)
            let newIdxMapValLen = dataIndexMapValueLength(newIdxMapVal)

            if oldIdxMapValLen > 1 && newIdxMapValLen == 1 {
                self._updateManyToOne?(newIdxMapVal as! Int, oldIdxMapVal as! [Int])
                newDataIndexMap![oldKey] = nil
            }
            else if oldIdxMapValLen == 1 && newIdxMapValLen > 1 {
                self._updateOneToMany?(newIdxMapVal as! [Int], oldIdxMapVal as! Int)
                newDataIndexMap![oldKey] = nil
            }
            else if oldIdxMapValLen == 1 && newIdxMapValLen == 1 {
                self._update?(newIdxMapVal as! Int, oldIdxMapVal as! Int)
                newDataIndexMap![oldKey] = nil
            }
            else if oldIdxMapValLen > 1 && newIdxMapValLen > 1 {
                self._updateManyToMany?(newIdxMapVal as! [Int], oldIdxMapVal as! [Int])
                newDataIndexMap![oldKey] = nil
            }
            else if oldIdxMapValLen > 1 {
                for i in 0..<oldIdxMapValLen {
                    self._remove?((oldIdxMapVal as! [Int])[i])
                }
            }
            else {
                self._remove?(oldIdxMapVal as! Int)
            }
        }

        self._performRestAdd(newDataKeyArr, &newDataIndexMap)
    }

    private func _performRestAdd(_ newDataKeyArr: [String], _ newDataIndexMap: inout DataIndexMap?) {
        for i in 0..<newDataKeyArr.count {
            let newKey = newDataKeyArr[i]
            let newIdxMapVal = newDataIndexMap![newKey]
            let idxMapValLen = dataIndexMapValueLength(newIdxMapVal)
            if idxMapValLen > 1 {
                for j in 0..<idxMapValLen {
                    self._add?((newIdxMapVal as! [Int])[j])
                }
            }
            else if idxMapValLen == 1 {
                self._add?(newIdxMapVal as! Int)
            }
            // Support both `newDataKeyArr` are duplication removed or not removed.
            newDataIndexMap![newKey] = nil
        }
    }

    private func _initIndexMap(
        _ arr: [Any],
        // Can be null.
        _ map: inout DataIndexMap?,
        // In 'byKey', the output `keyArr` is duplication removed.
        // In 'byIndex', the output `keyArr` is not duplication removed and
        //     its indices are accurately corresponding to `arr`.
        _ keyArr: inout [String],
        // PORT-NOTE: upstream passes the key-getter property name ('_oldKeyGetter' |
        //   '_newKeyGetter') and dynamically dispatches via `this[keyGetterName]`. Swift has
        //   no string-keyed member access, so we pass the resolved getter closure directly.
        _ keyGetter: DiffKeyGetter
    ) {
        let cbModeMultiple = self._diffModeMultiple

        for i in 0..<arr.count {
            // Add prefix to avoid conflict with Object.prototype.
            let key = "_ec_" + keyGetter(arr[i], i)
            if !cbModeMultiple {
                keyArr[i] = key
            }
            if map == nil {
                continue
            }

            let idxMapVal = map![key]
            let idxMapValLen = dataIndexMapValueLength(idxMapVal)

            if idxMapValLen == 0 {
                // Simple optimize: in most cases, one index has one key,
                // do not need array.
                map![key] = i
                if cbModeMultiple {
                    keyArr.append(key)
                }
            }
            else if idxMapValLen == 1 {
                map![key] = [idxMapVal as! Int, i]
            }
            else {
                // PORT-NOTE: upstream `push` mutates the array stored in the map in place
                //   (reference). Swift arrays are value types, so we write back explicitly.
                var arrVal = idxMapVal as! [Int]
                arrVal.append(i)
                map![key] = arrVal
            }
        }
    }

}
