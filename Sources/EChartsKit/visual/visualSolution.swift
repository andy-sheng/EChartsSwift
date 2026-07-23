// Ported from echarts/src/visual/visualSolution.ts — keep in sync with upstream.
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

/**
 * @file Visual solution, for consistent option specification.
 */

import Foundation
import ZRenderKit

// import * as zrUtil from 'zrender/src/core/util';   -> `util` (ZRenderKit).
// import VisualMapping, { VisualMappingOption } from './VisualMapping';   -> visual/VisualMapping.swift.
// import { getItemVisualFromData, setItemVisualFromData } from './helper';
//   -> visual/helper.ts is not ported as a namespace; the two item-visual bridges are inlined at the
//      bottom of this file (same convention as visualEncoding.swift's getVisualFromData).

// type VisualMappingCollection<VisualState> = { [state]?: { [visualType]?: VisualMapping } & { __alphaForOpacity?: VisualMapping } };
//   Modeled as `[state: [visualType: VisualMapping]]`; the hidden `__alphaForOpacity` slot is stored under
//   the literal key "__alphaForOpacity" (upstream hides it via a prototype trick — `createMappings` puts it
//   on the prototype so object iteration with hasOwnProperty skips it). Swift dictionaries have no such
//   hidden slot, so the key IS iterable here; `VisualMapping.prepareVisualTypes` reproduces the hidden-slot
//   semantics for every walker by skipping "__alphaForOpacity" while collecting the object's keys
//   (otherwise an opacity visualMap/brush would apply an extra colorAlpha on top of opacity).
//   The mappings dict still KEEPS the entry, so the `opacity` -> `__alphaForOpacity` remap lookups resolve.
typealias VisualMappingCollection = [String: [String: VisualMapping]]

// The literal key under which the (upstream-prototype-hidden) __alphaForOpacity mapping is stashed.
// Shared source of truth for the magic key: this is the storage key used when writing the mapping
// (see `createVisualMappings`), and the SAME constant is referenced by VisualMapping.prepareVisualTypes,
// which is where the iteration-time filtering (skipping the hidden slot) is enforced centrally.
let alphaForOpacityKey = "__alphaForOpacity"

// function hasKeys(obj) { for name in obj: if hasOwnProperty(name) return true; }
//   Upstream returns true for ANY non-empty own-enumerable value: object, array, or string. Mirror that
//   for the value shapes that actually occur in replacableOptionKeys (e.g. `visualMap.color` is commonly
//   an array like ['#d94e5d','#eac736']), otherwise an array-valued key would fail to trigger the reset.
private func hasKeys(_ obj: Any?) -> Bool {
    guard let obj = obj else { return false }
    if let dict = obj as? [String: Any] {
        return !dict.isEmpty
    }
    if let arr = obj as? [Any] {
        return !arr.isEmpty
    }
    if let str = obj as? String {
        return !str.isEmpty
    }
    return false
}

enum visualSolution {

    // export function createVisualMappings(option, stateList, supplementVisualOption)
    static func createVisualMappings(
        _ option: [String: Any]?,
        _ stateList: [String],
        _ supplementVisualOption: ((inout [String: Any], String) -> Void)?
    ) -> VisualMappingCollection {
        var visualMappings: VisualMappingCollection = [:]

        // each(stateList, function (state) { ... });
        util.each(stateList) { state, _ in
            // const mappings = visualMappings[state] = createMappings();
            var mappings: [String: VisualMapping] = [:]

            // each(option[state], function (visualData, visualType) { ... });
            let stateOption = option?[state] as? [String: Any]
            if let stateOption = stateOption {
                for (visualType, visualData) in stateOption {
                    // if (!VisualMapping.isValidType(visualType)) { return; }
                    if !VisualMapping.isValidType(visualType) {
                        continue
                    }
                    // let mappingOption = { type: visualType, visual: visualData };
                    var mappingOption: [String: Any] = ["type": visualType, "visual": visualData]
                    // supplementVisualOption && supplementVisualOption(mappingOption, state);
                    supplementVisualOption?(&mappingOption, state)
                    // mappings[visualType] = new VisualMapping(mappingOption);
                    mappings[visualType] = VisualMapping(VisualMappingOption(mappingOption))

                    // Prepare a alpha for opacity, for some case that opacity is not supported, such as
                    // rendering using gradient color.
                    // if (visualType === 'opacity') { ... mappings.__hidden.__alphaForOpacity = ...; }
                    if visualType == "opacity" {
                        var alphaOption = mappingOption
                        alphaOption["type"] = "colorAlpha"
                        // upstream: mappings.__hidden.__alphaForOpacity = ...; the hidden slot is not
                        // own-enumerable. Here it's a plain key; consumers must skip it during iteration.
                        mappings[alphaForOpacityKey] = VisualMapping(VisualMappingOption(alphaOption))
                    }
                }
            }

            visualMappings[state] = mappings
        }

        return visualMappings
    }

    // export function replaceVisualOption(thisOption, newOption, keys)
    //   Visual attributes merge is not supported (#2853): if newOption has ANY of `keys` (with content),
    //   ALL of `keys` are reset; otherwise all keys remain.
    static func replaceVisualOption(
        _ thisOption: inout [String: Any],
        _ newOption: [String: Any],
        _ keys: [String]
    ) {
        // let has; each(keys, (key) => { if (newOption.hasOwnProperty(key) && hasKeys(newOption[key])) has = true; });
        var has = false
        util.each(keys) { key, _ in
            if newOption.index(forKey: key) != nil && hasKeys(newOption[key]) {
                has = true
            }
        }
        // has && each(keys, (key) => { ... });
        if has {
            util.each(keys) { key, _ in
                if newOption.index(forKey: key) != nil && hasKeys(newOption[key]) {
                    // thisOption[key] = zrUtil.clone(newOption[key]);
                    thisOption[key] = util.clone(newOption[key]!) as Any
                }
                else {
                    // delete thisOption[key];
                    thisOption.removeValue(forKey: key)
                }
            }
        }
    }

    // export function applyVisual(stateList, visualMappings, data, getValueState, scope?, dimension?)
    //   Non-incremental sibling of `incrementalApplyVisual`: walks the whole `data` once and, for each
    //   datum, resolves its visual state via `getValueState`, then applies every visualType's mapping
    //   for that state (color/opacity/colorAlpha/symbol/...). Used by the brush visual encoder.
    //   `getValueState` receives `valueOrIndex`: when `dimension == nil` it is the dataIndex; when a
    //   dimension is given it is that dimension's parsed value. (The `scope` bind arg is dropped —
    //   Swift closures capture their own context.)
    static func applyVisual(
        _ stateList: [String],
        _ visualMappings: VisualMappingCollection,
        _ data: SeriesData,
        _ getValueState: @escaping (Any?) -> String,
        _ dimension: DimensionLoose? = nil
    ) {
        // const visualTypesMap = {}; each(stateList, (state) => visualTypesMap[state] = prepareVisualTypes(...));
        var visualTypesMap: [String: [String]] = [:]
        util.each(stateList) { state, _ in
            // (prepareVisualTypes already omits the prototype-hidden __alphaForOpacity slot.)
            visualTypesMap[state] = VisualMapping.prepareVisualTypes(visualMappings[state])
        }

        // Closure-captured `dataIndex` mirrors upstream's outer `let dataIndex` shared by getVisual/setVisual.
        var dataIndex: Int = 0
        func getVisual(_ key: String) -> Any? { getItemVisualFromData(data, dataIndex, key) }
        func setVisual(_ key: String, _ value: Any?) { setItemVisualFromData(data, dataIndex, key, value) }

        // function eachItem(valueOrIndex, index?) { dataIndex = dimension == null ? valueOrIndex : index; ... }
        //   The store's EachCb passes `[Double(i)]` (no-dim) or `[value..., Double(i)]` (with dims); the
        //   trailing element is always the index. `valueOrIndex` = args[0].
        let eachItem: EachCb = { args in
            let valueOrIndex: Any? = args.first
            if dimension == nil {
                dataIndex = Int((args.first as? Double) ?? 0)
            }
            else {
                dataIndex = Int((args.last as? Double) ?? 0)
            }

            // if (rawDataItem && rawDataItem.visualMap === false) { return; }
            let rawDataItem = data.getRawDataItem(dataIndex)
            if let rawDict = rawDataItem as? [String: Any],
               let vm = rawDict["visualMap"] as? Bool, vm == false {
                return
            }

            // const valueState = getValueState.call(scope, valueOrIndex);
            let valueState = getValueState(valueOrIndex)
            let mappings = visualMappings[valueState]
            let visualTypes = visualTypesMap[valueState] ?? []

            for type in visualTypes {
                // mappings[type] && mappings[type].applyVisual(valueOrIndex, getVisual, setVisual);
                if let mapping = mappings?[type] {
                    mapping.applyVisual(valueOrIndex as Any, getVisual, setVisual)
                }
            }
        }

        // if (dimension == null) { data.each(eachItem); } else { data.each([dimension], eachItem); }
        if let dimension = dimension {
            data.each([dimension], eachItem)
        }
        else {
            data.each(eachItem)
        }
    }

    // export function incrementalApplyVisual(stateList, visualMappings, getValueState, dim?)
    //   Returns a StageHandlerProgressExecutor whose `progress` walks the data range and, for each datum,
    //   runs each visualType's mapping.applyVisual to write the mapped color/opacity/symbol/... visual.
    static func incrementalApplyVisual(
        _ stateList: [String],
        _ visualMappings: VisualMappingCollection,
        _ getValueState: @escaping (Any?) -> String,
        _ dim: DimensionLoose?
    ) -> StageHandlerProgressExecutor {
        // const visualTypesMap = {}; each(stateList, (state) => visualTypesMap[state] = prepareVisualTypes(visualMappings[state]));
        var visualTypesMap: [String: [String]] = [:]
        util.each(stateList) { state, _ in
            // (prepareVisualTypes already omits the prototype-hidden __alphaForOpacity slot.)
            let visualTypes = VisualMapping.prepareVisualTypes(visualMappings[state])
            visualTypesMap[state] = visualTypes
        }

        var executor = StageHandlerProgressExecutor()
        executor.progress = { params, data in
            // let dimIndex; if (dim != null) dimIndex = data.getDimensionIndex(dim);
            var dimIndex: DimensionIndex = -1
            if let dim = dim {
                dimIndex = data.getDimensionIndex(dim)
            }

            // const store = data.getStore();
            let store = data.getStore()

            // while ((dataIndex = params.next()) != null) { ... }
            guard let next = params.next else { return }
            while let dataIndexD = next() {
                let dataIndex = Int(dataIndexD)

                func getVisual(_ key: String) -> Any? {
                    return getItemVisualFromData(data, dataIndex, key)
                }
                func setVisual(_ key: String, _ value: Any?) {
                    setItemVisualFromData(data, dataIndex, key, value)
                }

                // const rawDataItem = data.getRawDataItem(dataIndex);
                // if (rawDataItem && rawDataItem.visualMap === false) { continue; }
                let rawDataItem = data.getRawDataItem(dataIndex)
                if let rawDict = rawDataItem as? [String: Any],
                   let vm = rawDict["visualMap"] as? Bool, vm == false {
                    continue
                }

                // const value = dim != null ? store.get(dimIndex, dataIndex) : dataIndex;
                let value: Any?
                if dim != nil {
                    value = store.get(dimIndex, dataIndex)
                }
                else {
                    value = Double(dataIndex)
                }

                // const valueState = getValueState(value);
                let valueState = getValueState(value)
                // const mappings = visualMappings[valueState]; const visualTypes = visualTypesMap[valueState];
                let mappings = visualMappings[valueState]
                let visualTypes = visualTypesMap[valueState] ?? []

                for type in visualTypes {
                    // mappings[type] && mappings[type].applyVisual(value, getVisual, setVisual);
                    if let mapping = mappings?[type] {
                        mapping.applyVisual(value as Any, getVisual, setVisual)
                    }
                }
            }
        }
        return executor
    }
}

// MARK: - Minimal faithful port of `visual/helper.ts#{getItemVisualFromData, setItemVisualFromData}`.
//   (visual/helper.ts is not ported as a namespace; these two item-visual bridges are used by the
//    incremental encoder above. Same convention as visualEncoding.swift's getVisualFromData.)

// export function getItemVisualFromData(data, dataIndex, key)
func getItemVisualFromData(_ data: SeriesData, _ dataIndex: Int, _ key: String) -> Any? {
    switch key {
    case "color":
        // const style = data.getItemVisual(dataIndex, 'style'); return style[data.getVisual('drawType')];
        let style = data.getItemVisual(dataIndex, "style") as? [String: Any]
        let drawType = (data.getVisual("drawType") as? String) ?? "fill"
        return style?[drawType]
    case "opacity":
        return (data.getItemVisual(dataIndex, "style") as? [String: Any])?["opacity"]
    case "symbol", "symbolSize", "liftZ":
        return data.getItemVisual(dataIndex, key)
    default:
        return nil
    }
}

// export function setItemVisualFromData(data, dataIndex, key, value)
func setItemVisualFromData(_ data: SeriesData, _ dataIndex: Int, _ key: String, _ value: Any?) {
    switch key {
    case "color":
        // Make sure not sharing style object.
        _ = data.ensureUniqueItemVisual(dataIndex, "style")
        var style = (data.getItemVisual(dataIndex, "style") as? [String: Any]) ?? [:]
        let drawType = (data.getVisual("drawType") as? String) ?? "fill"
        style[drawType] = value
        data.setItemVisual(dataIndex, "style", style)
        // Mark the color has been changed, not from palette anymore
        data.setItemVisual(dataIndex, "colorFromPalette", false)
    case "opacity":
        _ = data.ensureUniqueItemVisual(dataIndex, "style")
        var style = (data.getItemVisual(dataIndex, "style") as? [String: Any]) ?? [:]
        style["opacity"] = value
        data.setItemVisual(dataIndex, "style", style)
    case "symbol", "symbolSize", "liftZ":
        data.setItemVisual(dataIndex, key, value)
    default:
        break
    }
}
