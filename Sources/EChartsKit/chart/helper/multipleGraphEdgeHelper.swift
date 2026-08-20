// Ported from echarts/src/chart/helper/multipleGraphEdgeHelper.ts — keep in sync with upstream
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

// upstream imports:
//   import * as zrUtil from 'zrender/src/core/util';  -> util.* (ZRenderKit).
//
// Free-function module `multipleGraphEdgeHelper.ts` -> caseless enum namespace
// `multipleGraphEdgeHelper` (CONVENTIONS §2). The three exported free functions
// (initCurvenessList / createEdgeMapForCurveness / getCurvenessForEdge) become static members.
//
// PORT NOTE on state: upstream stashes `__curvenessList` and `__edgeMap` directly on the
//   `GraphSeriesModel` instance (dynamic JS properties). Swift cannot add stored properties to a
//   class from another file, so the per-series state lives in a side table keyed by object identity.
//   The mutable edge-array is a reference type (class `EdgeArray`) so that `.isForward` mutations
//   made through `edgeMap[key]` are visible through `edgeMap[oppositeKey]` (upstream mutates shared
//   JS arrays in place).

// A curveness edge bucket: the pushed `index` values plus the `isForward` flag upstream tacks on the
// array object. Reference type so aliasing through the map mirrors upstream's shared-array mutation.
private final class EdgeArray {
    var indices: [Double] = []
    var isForward: Bool?
}

// Per-series auto-curveness state (upstream: seriesModel.__curvenessList / __edgeMap).
private final class CurvenessState {
    var curvenessList: [Double] = []
    var edgeMap: [String: EdgeArray] = [:]
}

public enum multipleGraphEdgeHelper {

    private static let KEY_DELIMITER = "-->"

    // Side table: seriesModel identity -> its curveness state (weak-keyed like upstream).
    private static let _state: (GraphSeriesModel) -> CurvenessState =
        model.makeInner { CurvenessState() }

    private static func state(_ seriesModel: GraphSeriesModel) -> CurvenessState {
        return _state(seriesModel)
    }

    // const getAutoCurvenessParams = function (seriesModel) {
    //     return seriesModel.get('autoCurveness') || null;
    // };
    // Returns nil for JS-falsy values (undefined/null/false/0), otherwise the raw option value.
    private static func getAutoCurvenessParams(_ seriesModel: GraphSeriesModel) -> Any? {
        let v = seriesModel.get("autoCurveness")
        if v == nil || v is NSNull { return nil }
        if let b = v as? Bool { return b ? v : nil }
        if let d = asNumber(v), d == 0 { return nil }
        return v
    }

    // const createCurveness = function (seriesModel, appendLength) { ... }
    private static func createCurveness(_ seriesModel: GraphSeriesModel, _ appendLength: Double? = nil) {
        let autoCurvenessParmas = getAutoCurvenessParams(seriesModel)
        var length = 20.0

        // if (zrUtil.isNumber(autoCurvenessParmas)) { length = autoCurvenessParmas; }
        if let n = asNumber(autoCurvenessParmas), !(autoCurvenessParmas is Bool) {
            length = n
        }
        // else if (zrUtil.isArray(autoCurvenessParmas)) { seriesModel.__curvenessList = ...; return; }
        else if let arr = autoCurvenessParmas as? [Any] {
            state(seriesModel).curvenessList = arr.compactMap { asNumber($0) }
            return
        }

        // if (appendLength > length) { length = appendLength; }
        if let appendLength = appendLength, appendLength > length {
            length = appendLength
        }

        // const len = length % 2 ? length + 2 : length + 3;
        let lengthI = Int(length)
        let len = (lengthI % 2 != 0) ? lengthI + 2 : lengthI + 3

        var curvenessList: [Double] = []
        // for (let i = 0; i < len; i++) {
        //     curvenessList.push((i % 2 ? i + 1 : i) / 10 * (i % 2 ? -1 : 1));
        // }
        for i in 0..<len {
            let numer = (i % 2 != 0) ? Double(i + 1) : Double(i)
            let sign = (i % 2 != 0) ? -1.0 : 1.0
            curvenessList.append(numer / 10.0 * sign)
        }
        state(seriesModel).curvenessList = curvenessList
    }

    // const getKeyOfEdges = function (n1, n2, seriesModel) { ... }
    private static func getKeyOfEdges(_ n1: GraphNode, _ n2: GraphNode, _ seriesModel: GraphSeriesModel) -> String {
        let source = "\(n1.id).\(n1.dataIndex)"
        let target = "\(n2.id).\(n2.dataIndex)"
        return [seriesModel.uid, source, target].joined(separator: KEY_DELIMITER)
    }

    // const getOppositeKey = function (key) { ... }
    private static func getOppositeKey(_ key: String) -> String {
        let keys = key.components(separatedBy: KEY_DELIMITER)
        return [keys[0], keys[2], keys[1]].joined(separator: KEY_DELIMITER)
    }

    // const getEdgeFromMap = function (edge, seriesModel) { ... }
    private static func getEdgeFromMap(_ edge: GraphEdge, _ seriesModel: GraphSeriesModel) -> EdgeArray? {
        let key = getKeyOfEdges(edge.node1, edge.node2, seriesModel)
        return state(seriesModel).edgeMap[key]
    }

    // const getTotalLengthBetweenNodes = function (edge, seriesModel) { ... }
    private static func getTotalLengthBetweenNodes(_ edge: GraphEdge, _ seriesModel: GraphSeriesModel) -> Double {
        let len = getEdgeMapLengthWithKey(getKeyOfEdges(edge.node1, edge.node2, seriesModel), seriesModel)
        let lenV = getEdgeMapLengthWithKey(getKeyOfEdges(edge.node2, edge.node1, seriesModel), seriesModel)
        return len + lenV
    }

    // const getEdgeMapLengthWithKey = function (key, seriesModel) { ... }
    private static func getEdgeMapLengthWithKey(_ key: String, _ seriesModel: GraphSeriesModel) -> Double {
        let edgeMap = state(seriesModel).edgeMap
        return edgeMap[key] != nil ? Double(edgeMap[key]!.indices.count) : 0
    }

    // export function initCurvenessList(seriesModel) { ... }
    public static func initCurvenessList(_ seriesModel: GraphSeriesModel) {
        if getAutoCurvenessParams(seriesModel) == nil {
            return
        }
        let s = state(seriesModel)
        s.curvenessList = []
        s.edgeMap = [:]
        // calc the array of curveness List
        createCurveness(seriesModel)
    }

    // export function createEdgeMapForCurveness(n1, n2, seriesModel, index) { ... }
    public static func createEdgeMapForCurveness(_ n1: GraphNode, _ n2: GraphNode, _ seriesModel: GraphSeriesModel, _ index: Double) {
        if getAutoCurvenessParams(seriesModel) == nil {
            return
        }

        let key = getKeyOfEdges(n1, n2, seriesModel)
        let s = state(seriesModel)
        let oppositeEdges = s.edgeMap[getOppositeKey(key)]
        // set direction
        if s.edgeMap[key] != nil && oppositeEdges == nil {
            s.edgeMap[key]!.isForward = true
        }
        else if oppositeEdges != nil && s.edgeMap[key] != nil {
            oppositeEdges!.isForward = true
            s.edgeMap[key]!.isForward = false
        }

        if s.edgeMap[key] == nil {
            s.edgeMap[key] = EdgeArray()
        }
        s.edgeMap[key]!.indices.append(index)
    }

    // export function getCurvenessForEdge(edge, seriesModel, index, needReverse?) { ... }
    // PORT NOTE: upstream returns `number | null`. Both call sites in the layout helpers pass the
    //   result into `retrieve3` (directly or negated). JS `-null === 0`, and retrieve3 skips only
    //   null/undefined, so returning 0.0 for the null cases is behaviourally identical for those
    //   sites (retrieve3 falls through to its `0` default). Hence the return type is a plain Double.
    public static func getCurvenessForEdge(_ edge: GraphEdge, _ seriesModel: GraphSeriesModel, _ index: Double, _ needReverse: Bool = false) -> Double {
        let autoCurvenessParams = getAutoCurvenessParams(seriesModel)
        let isArrayParam = autoCurvenessParams is [Any]
        if autoCurvenessParams == nil {
            return 0   // upstream: null
        }

        guard let edgeArray = getEdgeFromMap(edge, seriesModel) else {
            return 0   // upstream: null
        }

        var edgeIndex = -1
        for i in 0..<edgeArray.indices.count {
            if edgeArray.indices[i] == index {
                edgeIndex = i
                break
            }
        }
        // if totalLen is Longer createCurveness
        let totalLen = getTotalLengthBetweenNodes(edge, seriesModel)
        createCurveness(seriesModel, totalLen)

        // edge.lineStyle = edge.lineStyle || {};
        // PORT-NOTE: GraphEdge has no dynamic `lineStyle` slot; upstream only ensures its existence
        //   here (no effect on the returned value), so the assignment is omitted.

        // const parityCorrection = isArrayParam ? 0 : totalLen % 2 ? 0 : 1;
        let totalLenI = Int(totalLen)
        let parityCorrection = isArrayParam ? 0 : (totalLenI % 2 != 0 ? 0 : 1)

        let curvenessList = state(seriesModel).curvenessList

        func at(_ i: Int) -> Double {
            return (i >= 0 && i < curvenessList.count) ? curvenessList[i] : 0
        }

        if edgeArray.isForward != true {
            // the opposite edge show outside
            let curKey = getKeyOfEdges(edge.node1, edge.node2, seriesModel)
            let oppositeKey = getOppositeKey(curKey)
            let len = Int(getEdgeMapLengthWithKey(oppositeKey, seriesModel))
            let resValue = at(edgeIndex + len + parityCorrection)
            // isNeedReverse
            if needReverse {
                if isArrayParam {
                    // if (autoCurvenessParams && autoCurvenessParams[0] === 0)
                    let arr = autoCurvenessParams as? [Any]
                    let firstIsZero = (arr?.first).flatMap { asNumber($0) } == 0
                    if firstIsZero {
                        return (len + parityCorrection) % 2 != 0 ? resValue : -resValue
                    }
                    else {
                        return ((len % 2 != 0 ? 0 : 1) + parityCorrection) % 2 != 0 ? resValue : -resValue
                    }
                }
                else {
                    return (len + parityCorrection) % 2 != 0 ? resValue : -resValue
                }
            }
            else {
                return at(edgeIndex + len + parityCorrection)
            }
        }
        else {
            return at(parityCorrection + edgeIndex)
        }
    }

    // MARK: - Port helpers (not upstream symbols)

    private static func asNumber(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let i = v as? Int { return Double(i) }
        return nil
    }
}
