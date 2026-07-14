// Ported from echarts/src/animation/universalTransition.ts — keep in sync with upstream
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

// Universal transitions that can animate between any shapes(series) and any properties in any amounts.

// upstream:
//   import SeriesModel, { SERIES_UNIVERSAL_TRANSITION_PROP } from '../model/Series';   → model/Series.swift
//   import {createHashMap, each, map, filter, isArray, extend} from 'zrender/src/core/util';
//       -> `createHashMap`/`HashMap` are the util/modelUtil.swift shims; `each`/`map`/`filter` are
//          Swift's `for`/`map`/`filter` (CONVENTIONS §8).
//   import Element, { ElementAnimateConfig } from 'zrender/src/Element';   → ZRenderKit.Element
//   import { applyMorphAnimation, getPathList } from './morphTransitionHelper';  → sibling file
//   import Path from 'zrender/src/graphic/Path';                           → ZRenderKit.Path
//   import { EChartsExtensionInstallRegisters } from '../extension';       → coord/axisStatistics.swift
//   import { initProps } from '../util/graphic';                           → animation/basicTransition.swift
//   import DataDiffer from '../data/DataDiffer';                           → data/DataDiffer.swift
//   import SeriesData from '../data/SeriesData';                           → data/SeriesData.swift
//   import { ... } from '../util/types';                                   → util/types.swift
//   import { UpdateLifecycleParams, ... } from '../core/lifecycle';        → core/lifecycle.swift
//   import { makeInner, normalizeToArray } from '../util/model';           → `model.makeInner` / `model.normalizeToArray`
//   import { warn } from '../util/log';                                    → `log.warn`
//   import ExtensionAPI from '../core/ExtensionAPI';                       → core/ExtensionAPI.swift
//   import { getAnimationConfig, getOldStyle } from './basicTransition';   → sibling basicTransition.swift
//   import Model from '../model/Model';                                    → model/Model.swift
//   import Displayable from 'zrender/src/graphic/Displayable';             → ZRenderKit.Displayable
import Foundation
import ZRenderKit

private let DATA_COUNT_THRESHOLD = 1e4
private let TRANSITION_NONE = 0
private let TRANSITION_P2C = 1
private let TRANSITION_C2P = 2

// interface GlobalStore { oldSeries: SeriesModel[], oldDataGroupIds: string[], oldData: SeriesData[] };
//   PORT-NOTE: `makeInner` keys by object identity and requires a CLASS store (CONVENTIONS §4) — the
//   record is mutated in place by the 'series:transition' handler and read on the NEXT update.
//   `oldDataGroupIds` is `[String?]` because `series.get('dataGroupId')` may be absent (upstream
//   `string` is really `string | undefined`).
final class UniversalTransitionGlobalStore {
    var oldSeries: [SeriesModel]?
    var oldDataGroupIds: [String?] = []
    var oldData: [SeriesData] = []
    init() {}
}
private let getUniversalTransitionGlobalStore: (ExtensionAPI) -> UniversalTransitionGlobalStore
    = model.makeInner { UniversalTransitionGlobalStore() }

// interface DiffItem { data, groupId, childGroupId, divide, dataIndex }
private struct DiffItem {
    var data: SeriesData
    var groupId: String?
    var childGroupId: String?
    var divide: String?     // upstream: UniversalTransitionOption['divideShape']
    var dataIndex: Int
}
// interface TransitionSeries { dataGroupId, data, divide, groupIdDim? }
struct TransitionSeries {
    var dataGroupId: String?
    var data: SeriesData
    var divide: String?       // upstream: UniversalTransitionOption['divideShape']
    var groupIdDim: DimensionLoose?
}

// PORT-NOTE: JS `value + ''` string coercion, used by `getValueByDimension` / `getGroupId` where the
//   raw value may be a number, a string, or an ordinal category. (File-local shim, as elsewhere in the
//   port — Source.swift / sourceManager.swift each carry their own.)
private func jsToString(_ value: Any?) -> String {
    switch value {
    case nil: return "undefined"
    case let s as String: return s
    case let b as Bool: return b ? "true" : "false"
    case let d as Double: return jsNumberStr(d)
    case let i as Int: return jsNumberStr(Double(i))
    case let n as NSNumber: return jsNumberStr(n.doubleValue)
    default: return String(describing: value!)
    }
}
// JS `Number.prototype.toString` for a Double (integral values print without a fraction).
private func jsNumberStr(_ x: Double) -> String {   // PORT-NOTE: JS number-to-string shim
    if x.isNaN { return "NaN" }
    if x.isInfinite { return x > 0 ? "Infinity" : "-Infinity" }
    if x == x.rounded() && Swift.abs(x) < 1e15 {
        return String(Int(x))
    }
    return String(x)
}
// JS truthiness for an arbitrary value.
private func jsTruthy(_ v: Any?) -> Bool {   // PORT-NOTE: JS truthiness shim
    guard let v = v else { return false }
    if let b = v as? Bool { return b }
    if let d = v as? Double { return d != 0 && !d.isNaN }
    if let i = v as? Int { return i != 0 }
    if let s = v as? String { return !s.isEmpty }
    return true // arrays / objects are truthy
}

// function getDimension(data: SeriesData, visualDimension: string) { ... }
private func getDimension(_ data: SeriesData, _ visualDimension: String) -> DimensionName? {
    let dimensions = data.dimensions
    for i in 0..<dimensions.count {
        let dimInfo = data.getDimensionInfo(dimensions[i])
        // upstream: dimInfo && dimInfo.otherDims[visualDimension] === 0
        // PORT-NOTE: `otherDims` is a typed struct here (`DataVisualDimensions`), so the dynamic
        //   string-keyed lookup is an explicit switch over the two keys this file ever passes.
        let otherDim: DimensionIndex?
        switch visualDimension {
        case "itemGroupId": otherDim = dimInfo.otherDims?.itemGroupId
        case "itemChildGroupId": otherDim = dimInfo.otherDims?.itemChildGroupId
        default: otherDim = nil
        }
        if otherDim == 0 {
            return dimensions[i]
        }
    }
    return nil
}

// get value by dimension. (only get value of itemGroupId or childGroupId, so convert it to string)
private func getValueByDimension(_ data: SeriesData, _ dataIndex: Int, _ dimension: DimensionName) -> String? {
    let dimInfo = data.getDimensionInfo(dimension)
    let dimOrdinalMeta = dimInfo.ordinalMeta
    let value = data.get(dimInfo.name, dataIndex)
    if let dimOrdinalMeta = dimOrdinalMeta {
        // upstream: (dimOrdinalMeta.categories[value as number] as string) || value + ''
        let idx = (value as? Double).map { Int($0) }
        if let idx = idx, idx >= 0, idx < dimOrdinalMeta.categories.count {
            let category = jsToString(dimOrdinalMeta.categories[idx])
            if !category.isEmpty {
                return category
            }
        }
        return jsToString(value)
    }
    return jsToString(value)
}

private func getGroupId(_ data: SeriesData, _ dataIndex: Int, _ dataGroupId: String?, _ isChild: Bool) -> String? {
    // try to get groupId from encode
    let visualDimension = isChild ? "itemChildGroupId" : "itemGroupId"
    let groupIdDim = getDimension(data, visualDimension)
    if let groupIdDim = groupIdDim {
        let groupId = getValueByDimension(data, dataIndex, groupIdDim)
        return groupId
    }
    // try to get groupId from raw data item
    let rawDataItem = data.getRawDataItem(dataIndex) as? [String: Any]
    let property = isChild ? "childGroupId" : "groupId"
    if let rawDataItem = rawDataItem, let value = rawDataItem[property], jsTruthy(value) {
        return jsToString(value)
    }
    // fallback
    if isChild {
        return nil
    }
    // try to use series.dataGroupId as groupId, otherwise use dataItem's id as groupId
    // upstream: (dataGroupId || data.getId(dataIndex))  — the empty string is falsy in JS too.
    if let dataGroupId = dataGroupId, !dataGroupId.isEmpty {
        return dataGroupId
    }
    return data.getId(dataIndex)
}

// flatten all data items from different serieses into one arrary
private func flattenDataDiffItems(_ list: [TransitionSeries]) -> [DiffItem] {
    var items: [DiffItem] = []

    for seriesInfo in list {
        let data = seriesInfo.data
        let dataGroupId = seriesInfo.dataGroupId
        if Double(data.count()) > DATA_COUNT_THRESHOLD {
            if __DEV__ {
                log.warn("Universal transition is disabled on large data > 10k.")
            }
            continue    // upstream: `return` from the `each` callback == `continue`
        }
        let indices = data.getIndices()
        for dataIndex in 0..<indices.count {
            items.append(DiffItem(
                data: data,
                // either of groupId or childGroupId will be used as diffItem's key,
                groupId: getGroupId(data, dataIndex, dataGroupId, false),
                // depending on the transition direction (see below)
                childGroupId: getGroupId(data, dataIndex, dataGroupId, true),
                divide: seriesInfo.divide,
                dataIndex: dataIndex
            ))
        }
    }

    return items
}

private func fadeInElement(_ newEl: Element, _ newSeries: SeriesModel, _ newIndex: Int) {
    traverseElement(newEl) { el in
        if let el = el as? Path {
            // TODO use fade in animation for target element.
            initProps(el, ["style": ["opacity": 0.0] as [String: Any]], newSeries,
                      AnimateOrSetPropsOption(dataIndex: newIndex, isFrom: true))
        }
    }
}
private func removeEl(_ el: Element) {
    if let parent = el.parent as? Group {
        // Bake parent transform to element.
        // So it can still have proper transform to transition after it's removed.
        let computedTransform = el.getComputedTransform()
        el.setLocalTransform(computedTransform)
        _ = parent.remove(el)
    }
}
private func stopAnimation(_ el: Element) {
    _ = el.stopAnimation()
    if el.isGroup {
        traverseChildren(el) { child in
            _ = child.stopAnimation()
        }
    }
}
private func animateElementStyles(_ el: Element, _ dataIndex: Int, _ seriesModel: SeriesModel) {
    let animationConfig = getAnimationConfig(.update, seriesModel, dataIndex, nil)
    guard let animationConfig = animationConfig else { return }
    traverseElement(el) { child in
        if let child = child as? Displayable {
            let oldStyle = getOldStyle(child)
            if let oldStyle = oldStyle {
                var cfg = ElementAnimateConfig()
                cfg.duration = animationConfig.duration
                cfg.delay = animationConfig.delay
                cfg.easing = animationConfig.easing
                child.animateFrom(["style": pathStyleToAnimTarget(oldStyle)], cfg)
            }
        }
    }
}

// PORT-NOTE: `Element.traverse` (void cb) is a no-op on the base class; `Displayable` overrides it
//   (visits self) and `Group` declares an OVERLOAD taking a Bool-returning cb (visits children only,
//   like upstream `Group.traverse`). Static dispatch on an `Element`-typed value would silently skip a
//   Group's subtree, so upstream's `el.traverse(cb)` is routed through these two helpers.
//   `traverseElement` == upstream `el.traverse(cb)`; `traverseChildren` == the same call made on an
//   element already known to be a Group (`el.isGroup && el.traverse(...)`).
private func traverseElement(_ el: Element, _ cb: @escaping (Element) -> Void) {
    if let group = el as? Group {
        _ = group.traverse({ child in cb(child); return false })
    }
    else {
        el.traverse(cb)
    }
}
private func traverseChildren(_ el: Element, _ cb: @escaping (Element) -> Void) {
    if let group = el as? Group {
        _ = group.traverse({ child in cb(child); return false })
    }
}

// PORT-NOTE: upstream animates a whole style OBJECT (`to.animateFrom({ style: from.style })`) — in JS
//   the style bag IS a plain keyed object, so `animateTo` walks its own keys. `PathStyleProps` is a
//   Swift struct, and `Element.animateTo`'s nested-object target must be a `[String: Any]`, so the
//   struct is projected onto its ANIMATABLE keys (`PathStyleProps.animationGet`, the same list the
//   Animator can tween). Non-animatable keys (lineDash/lineCap/blend/…) are dropped: under
//   `animateFrom` they are no-ops anyway (animateToShallow skips a key whose current value is nil,
//   and a non-tweenable key has no animation track), so nothing observable is lost.
private let PATH_STYLE_ANIM_KEYS = [
    "opacity", "fillOpacity", "strokeOpacity", "lineWidth", "lineDashOffset",
    "strokePercent", "miterLimit", "shadowBlur", "shadowOffsetX", "shadowOffsetY",
    "shadowColor", "fill", "stroke"
]
func pathStyleToAnimTarget(_ style: PathStyleProps?) -> [String: Any] {
    guard let style = style else { return [:] }
    var out: [String: Any] = [:]
    for key in PATH_STYLE_ANIM_KEYS {
        if let v = style.animationGet(key) {
            out[key] = v
        }
    }
    return out
}

private func isAllIdSame(_ oldDiffItems: [DiffItem], _ newDiffItems: [DiffItem]) -> Bool {
    let len = oldDiffItems.count
    if len != newDiffItems.count {
        return false
    }
    for i in 0..<len {
        let oldItem = oldDiffItems[i]
        let newItem = newDiffItems[i]
        if oldItem.data.getId(oldItem.dataIndex) != newItem.data.getId(newItem.dataIndex) {
            return false
        }
    }
    return true
}

func transitionBetween(
    _ oldList: [TransitionSeries],
    _ newList: [TransitionSeries],
    _ api: ExtensionAPI
) {

    let oldDiffItems = flattenDataDiffItems(oldList)
    let newDiffItems = flattenDataDiffItems(newList)

    func updateMorphingPathProps(
        _ from: Path?, _ to: Path?,
        _ rawFrom: Path?, _ rawTo: Path?,
        _ animationCfg: ElementAnimateConfig
    ) {
        _ = rawTo
        guard let to = to else { return }   // upstream reads `to` unconditionally (never undefined here)
        if rawFrom != nil || from != nil {
            // to.animateFrom({
            //     style: (rawFrom && rawFrom !== from)
            //         // dividingMethod like clone may override the style(opacity)
            //         // So extend it to raw style.
            //         ? extend(extend({}, rawFrom.style), from.style)
            //         : from.style
            // }, animationCfg);
            var styleTarget: [String: Any]
            if let rawFrom = rawFrom, rawFrom !== from {
                styleTarget = pathStyleToAnimTarget(rawFrom.pathStyle)
                for (k, v) in pathStyleToAnimTarget(from?.pathStyle) {
                    styleTarget[k] = v
                }
            }
            else {
                styleTarget = pathStyleToAnimTarget(from?.pathStyle)
            }
            to.animateFrom(["style": styleTarget], animationCfg)
        }
    }

    var hasMorphAnimation = false

    /**
     * With groupId and childGroupId, we can build parent-child relationships between dataItems.
     * However, we should mind the parent-child "direction" between old and new options.
     *
     * (See the full upstream comment in universalTransition.ts — dataA/dataB example.)
     *
     * The rule is:
     *
     * if (all childGroupIds in oldDiffItems and all groupIds in newDiffItems have common value) {
     *   direction = 'parent -> child';
     * } else if (all groupIds in oldDiffItems and all childGroupIds in newDiffItems have common value) {
     *   direction = 'child -> parent';
     * } else {
     *   direction = 'none';
     * }
     */
    var direction = TRANSITION_NONE

    // find all groupIds and childGroupIds from oldDiffItems
    let oldGroupIds: HashMap<Bool> = createHashMap()
    let oldChildGroupIds: HashMap<Bool> = createHashMap()
    for item in oldDiffItems {
        if let groupId = item.groupId, !groupId.isEmpty { oldGroupIds.set(groupId, true) }
        if let childGroupId = item.childGroupId, !childGroupId.isEmpty { oldChildGroupIds.set(childGroupId, true) }
    }
    // traverse newDiffItems and decide the direction according to the rule
    for i in 0..<newDiffItems.count {
        let newGroupId = newDiffItems[i].groupId
        if oldChildGroupIds.get(newGroupId) != nil {
            direction = TRANSITION_P2C
            break
        }
        let newChildGroupId = newDiffItems[i].childGroupId
        if let newChildGroupId = newChildGroupId, !newChildGroupId.isEmpty,
           oldGroupIds.get(newChildGroupId) != nil {
            direction = TRANSITION_C2P
            break
        }
    }

    // PORT-NOTE: the key getter receives the raw `[Any]` element (the DiffItem) + its index, and JS
    //   coerces an `undefined` groupId into the string "undefined" when it builds the map key
    //   ("_ec_" + undefined). `jsToString(nil)` reproduces that exactly.
    func createKeyGetter(_ isOld: Bool, _ onlyGetId: Bool) -> DiffKeyGetter {
        return { (value: Any, _: Int) -> String in
            let diffItem = value as! DiffItem
            let data = diffItem.data
            let dataIndex = diffItem.dataIndex
            // TODO if specified dim
            if onlyGetId {
                return data.getId(dataIndex)
            }
            if isOld {
                return jsToString(direction == TRANSITION_P2C ? diffItem.childGroupId : diffItem.groupId)
            }
            else {
                return jsToString(direction == TRANSITION_C2P ? diffItem.childGroupId : diffItem.groupId)
            }
        }
    }

    // Use id if it's very likely to be an one to one animation
    // It's more robust than groupId
    // TODO Check if key dimension is specified.
    let useId = isAllIdSame(oldDiffItems, newDiffItems)
    // upstream: `const isElementStillInChart: Dictionary<boolean> = {}` keyed by `el.id` (a number).
    var isElementStillInChart: [Double: Bool] = [:]

    if !useId {
        // We may have different diff strategy with basicTransition if we use other dimension as key.
        // If so, we can't simply check if oldEl is same with newEl. We need a map to check if oldEl is
        // still being used in the new chart.
        // We can't use the elements that already being morphed. Let it keep it's original basic transition.
        for i in 0..<newDiffItems.count {
            let newItem = newDiffItems[i]
            let el = newItem.data.getItemGraphicEl(newItem.dataIndex)
            if let el = el {
                isElementStillInChart[el.id] = true
            }
        }
    }

    func updateOneToOne(_ newIndex: Int, _ oldIndex: Int) {

        let oldItem = oldDiffItems[oldIndex]
        let newItem = newDiffItems[newIndex]

        guard let newSeries = newItem.data.hostModel as? SeriesModel else { return }

        // TODO Mark this elements is morphed and don't morph them anymore
        let oldEl = oldItem.data.getItemGraphicEl(oldItem.dataIndex)
        let newEl = newItem.data.getItemGraphicEl(newItem.dataIndex)

        // Can't handle same elements.
        if oldEl === newEl {
            if let newEl = newEl {
                animateElementStyles(newEl, newItem.dataIndex, newSeries)
            }
            return
        }

        if
            // We can't use the elements that already being morphed
            let oldEl = oldEl, isElementStillInChart[oldEl.id] == true
        {
            _ = oldEl
            return
        }

        if let newEl = newEl {
            // TODO: If keep animating the group in case
            // some of the elements don't want to be morphed.
            // TODO Label?
            stopAnimation(newEl)

            if let oldEl = oldEl {
                stopAnimation(oldEl)

                // If old element is doing leaving animation. stop it and remove it immediately.
                removeEl(oldEl)

                hasMorphAnimation = true
                applyMorphAnimation(
                    .single(getPathList(oldEl)),
                    .single(getPathList(newEl)),
                    newItem.divide,
                    newSeries,
                    newIndex,
                    updateMorphingPathProps
                )
            }
            else {
                fadeInElement(newEl, newSeries, newIndex)
            }
        }
        // else keep oldEl leaving animation.
    }

    let differ = DataDiffer<Any>(
        oldDiffItems as [Any],
        newDiffItems as [Any],
        createKeyGetter(true, useId),
        createKeyGetter(false, useId),
        nil,
        .multiple
    )
    differ
    .update(updateOneToOne)
    .updateManyToOne({ (newIndex: Int, oldIndices: [Int]) in
        let newItem = newDiffItems[newIndex]
        let newData = newItem.data
        guard let newSeries = newData.hostModel as? SeriesModel else { return }
        let newEl = newData.getItemGraphicEl(newItem.dataIndex)
        let oldElsList: [Element] = oldIndices
            .map { idx in oldDiffItems[idx].data.getItemGraphicEl(oldDiffItems[idx].dataIndex) }
            .filter { oldEl in
                guard let oldEl = oldEl else { return false }
                return oldEl !== newEl && isElementStillInChart[oldEl.id] != true
            }
            .map { $0! }

        if let newEl = newEl {
            stopAnimation(newEl)
            if !oldElsList.isEmpty {
                // If old element is doing leaving animation. stop it and remove it immediately.
                for oldEl in oldElsList {
                    stopAnimation(oldEl)
                    removeEl(oldEl)
                }

                hasMorphAnimation = true
                applyMorphAnimation(
                    .multiple(getPathList(oldElsList)),
                    .single(getPathList(newEl)),
                    newItem.divide,
                    newSeries,
                    newIndex,
                    updateMorphingPathProps
                )

            }
            else {
                fadeInElement(newEl, newSeries, newItem.dataIndex)
            }
        }
        // else keep oldEl leaving animation.
    })
    .updateOneToMany({ (newIndices: [Int], oldIndex: Int) in
        let oldItem = oldDiffItems[oldIndex]
        let oldEl = oldItem.data.getItemGraphicEl(oldItem.dataIndex)

        // We can't use the elements that already being morphed
        if let oldEl = oldEl, isElementStillInChart[oldEl.id] == true {
            return
        }

        let newElsList: [Element] = newIndices
            .map { idx in newDiffItems[idx].data.getItemGraphicEl(newDiffItems[idx].dataIndex) }
            .filter { el in el != nil && el !== oldEl }
            .map { $0! }
        guard let newSeris = newDiffItems[newIndices[0]].data.hostModel as? SeriesModel else { return }

        if !newElsList.isEmpty {
            for newEl in newElsList { stopAnimation(newEl) }
            if let oldEl = oldEl {
                stopAnimation(oldEl)
                // If old element is doing leaving animation. stop it and remove it immediately.
                removeEl(oldEl)

                hasMorphAnimation = true
                applyMorphAnimation(
                    .single(getPathList(oldEl)),
                    .multiple(getPathList(newElsList)),
                    oldItem.divide, // Use divide on old.
                    newSeris,
                    newIndices[0],
                    updateMorphingPathProps
                )
            }
            else {
                for newEl in newElsList { fadeInElement(newEl, newSeris, newIndices[0]) }
            }
        }

        // else keep oldEl leaving animation.
    })
    .updateManyToMany({ (newIndices: [Int], oldIndices: [Int]) in
        // If two data are same and both have groupId.
        // Normally they should be diff by id.
        DataDiffer<Any>(
            oldIndices as [Any],
            newIndices as [Any],
            { (rawIdx: Any, _: Int) -> String in
                let i = rawIdx as! Int
                return oldDiffItems[i].data.getId(oldDiffItems[i].dataIndex)
            },
            { (rawIdx: Any, _: Int) -> String in
                let i = rawIdx as! Int
                return newDiffItems[i].data.getId(newDiffItems[i].dataIndex)
            }
        ).update({ (newIndex: Int, oldIndex: Int) in
            // Use the original index
            updateOneToOne(newIndices[newIndex], oldIndices[oldIndex])
        }).execute()
    })
    .execute()

    if hasMorphAnimation {
        for transSeries in newList {
            let data = transSeries.data
            guard let seriesModel = data.hostModel as? SeriesModel else { continue }
            let view = api.getViewOfSeriesModel(seriesModel)
            let animationCfg = getAnimationConfig(.update, seriesModel, 0, nil)  // use 0 index.
            if let view = view, seriesModel.isAnimationEnabled() == true,
               let animationCfg = animationCfg, animationCfg.duration > 0 {
                _ = view.group.traverse({ el in
                    if let el = el as? Path, el.animators.isEmpty {
                        // We can't accept there still exists element that has no animation
                        // if universalTransition is enabled
                        var cfg = ElementAnimateConfig()
                        cfg.duration = animationCfg.duration
                        cfg.delay = animationCfg.delay
                        cfg.easing = animationCfg.easing
                        el.animateFrom(["style": ["opacity": 0.0] as [String: Any]], cfg)
                    }
                    return false
                })
            }
        }
    }
}

private func getSeriesTransitionKey(_ series: SeriesModel) -> Any {
    // const seriesKey = (series.getModel('universalTransition') as Model<UniversalTransitionOption>)
    //     .get('seriesKey');
    let seriesKey = series.getModel("universalTransition").get("seriesKey")
    if !jsTruthy(seriesKey) {
        // Use series id by default.
        return series.id
    }
    return seriesKey!
}

private func convertArraySeriesKeyToString(_ seriesKey: Any) -> String {
    if let arr = seriesKey as? [Any] {
        // Order independent.
        return arr.map { jsToString($0) }.sorted().joined(separator: ",")
    }
    return jsToString(seriesKey)
}

// interface SeriesTransitionBatch { oldSeries: TransitionSeries[]; newSeries: TransitionSeries[] }
//   PORT-NOTE: a CLASS — upstream mutates the batch fetched out of the hashmap in place
//   (`batch.newSeries.push(...)` in the one-to-multiple branch), which a struct value copy would lose.
final class SeriesTransitionBatch {
    var oldSeries: [TransitionSeries]
    var newSeries: [TransitionSeries]
    init(oldSeries: [TransitionSeries], newSeries: [TransitionSeries]) {
        self.oldSeries = oldSeries
        self.newSeries = newSeries
    }
}

private func getDivideShapeFromData(_ data: SeriesData) -> String? {
    if let hostModel = data.hostModel as? SeriesModel {
        return hostModel.getModel("universalTransition").get("divideShape") as? String
    }
    return nil
}

private func findTransitionSeriesBatches(
    _ globalStore: UniversalTransitionGlobalStore,
    _ params: UpdateLifecycleParams
) -> HashMap<SeriesTransitionBatch> {
    let updateBatches: HashMap<SeriesTransitionBatch> = createHashMap()

    // const oldDataMap = createHashMap<{ dataGroupId: string, data: SeriesData }>();
    struct OldDataEntry {
        var dataGroupId: String?
        var data: SeriesData
    }
    let oldDataMap: HashMap<OldDataEntry> = createHashMap()
    // Map that only store key in array seriesKey.
    // Which is used to query the old data when transition from one to multiple series.
    // const oldDataMapForSplit = createHashMap<{ key, dataGroupId, data }>();
    struct OldDataForSplitEntry {
        var key: String
        var dataGroupId: String?
        var data: SeriesData
    }
    let oldDataMapForSplit: HashMap<OldDataForSplitEntry> = createHashMap()

    for (idx, series) in (globalStore.oldSeries ?? []).enumerated() {
        let oldDataGroupId = idx < globalStore.oldDataGroupIds.count ? globalStore.oldDataGroupIds[idx] : nil
        let oldData = globalStore.oldData[idx]
        let transitionKey = getSeriesTransitionKey(series)
        let transitionKeyStr = convertArraySeriesKeyToString(transitionKey)
        oldDataMap.set(transitionKeyStr, OldDataEntry(
            dataGroupId: oldDataGroupId,
            data: oldData
        ))

        if let keyArr = transitionKey as? [Any] {
            // Same key can't in different array seriesKey.
            for key in keyArr {
                oldDataMapForSplit.set(jsToString(key), OldDataForSplitEntry(
                    key: transitionKeyStr,
                    dataGroupId: oldDataGroupId,
                    data: oldData
                ))
            }
        }
    }

    func checkTransitionSeriesKeyDuplicated(_ transitionKeyStr: String) {
        if updateBatches.get(transitionKeyStr) != nil {
            log.warn("Duplicated seriesKey in universalTransition \(transitionKeyStr)")
        }
    }
    for series in params.updatedSeries ?? [] {
        if series.isUniversalTransitionEnabled() && series.isAnimationEnabled() == true {
            let newDataGroupId = series.get("dataGroupId") as? String
            let newData = series.getData()
            let transitionKey = getSeriesTransitionKey(series)
            let transitionKeyStr = convertArraySeriesKeyToString(transitionKey)
            // Only transition between series with same id.
            let oldData = oldDataMap.get(transitionKeyStr)
            // string transition key is the best match.
            if let oldData = oldData {
                if __DEV__ {
                    checkTransitionSeriesKeyDuplicated(transitionKeyStr)
                }
                // TODO check if data is same?
                updateBatches.set(transitionKeyStr, SeriesTransitionBatch(
                    oldSeries: [TransitionSeries(
                        dataGroupId: oldData.dataGroupId,
                        data: oldData.data,
                        divide: getDivideShapeFromData(oldData.data)
                    )],
                    newSeries: [TransitionSeries(
                        dataGroupId: newDataGroupId,
                        data: newData,
                        divide: getDivideShapeFromData(newData)
                    )]
                ))
            }
            else {
                // Transition from multiple series.
                // e.g. 'female', 'male' -> ['female', 'male']
                if let keyArr = transitionKey as? [Any] {
                    if __DEV__ {
                        checkTransitionSeriesKeyDuplicated(transitionKeyStr)
                    }
                    var oldSeries: [TransitionSeries] = []
                    for key in keyArr {
                        // upstream: `const oldData = oldDataMap.get(key); if (oldData.data)` — a MISSING
                        //   key throws upstream (reading `.data` of undefined); guarded here.
                        if let oldData = oldDataMap.get(jsToString(key)) {
                            oldSeries.append(TransitionSeries(
                                dataGroupId: oldData.dataGroupId,
                                data: oldData.data,
                                divide: getDivideShapeFromData(oldData.data)
                            ))
                        }
                    }
                    if !oldSeries.isEmpty {
                        updateBatches.set(transitionKeyStr, SeriesTransitionBatch(
                            oldSeries: oldSeries,
                            newSeries: [TransitionSeries(
                                dataGroupId: newDataGroupId,
                                data: newData,
                                divide: getDivideShapeFromData(newData)
                            )]
                        ))
                    }
                }
                else {
                    // Try transition to multiple series.
                    // e.g. ['female', 'male'] -> 'female', 'male'
                    let oldData = oldDataMapForSplit.get(convertArraySeriesKeyToString(transitionKey))
                    if let oldData = oldData {
                        var batch = updateBatches.get(oldData.key)
                        if batch == nil {
                            batch = SeriesTransitionBatch(
                                oldSeries: [TransitionSeries(
                                    dataGroupId: oldData.dataGroupId,
                                    data: oldData.data,
                                    divide: getDivideShapeFromData(oldData.data)
                                )],
                                newSeries: []
                            )
                            updateBatches.set(oldData.key, batch!)
                        }
                        batch!.newSeries.append(TransitionSeries(
                            dataGroupId: newDataGroupId,
                            data: newData,
                            divide: getDivideShapeFromData(newData)
                        ))
                    }
                }
            }
        }
    }

    return updateBatches
}

private func querySeries(_ series: [SeriesModel], _ finder: UpdateLifecycleTransitionSeriesFinder) -> Int? {
    for i in 0..<series.count {
        let found = (finder.seriesIndex != nil && finder.seriesIndex == series[i].seriesIndex)
            || (finder.seriesId != nil && finder.seriesId == series[i].id)
        if found {
            return i
        }
    }
    return nil
}

private func transitionSeriesFromOpt(
    _ transitionOpt: UpdateLifecycleTransitionItem,
    _ globalStore: UniversalTransitionGlobalStore,
    _ params: UpdateLifecycleParams,
    _ api: ExtensionAPI
) {
    var from: [TransitionSeries] = []
    var to: [TransitionSeries] = []
    let fromFinders: [UpdateLifecycleTransitionSeriesFinder] = model.normalizeToArray(transitionOpt.from)
    for finder in fromFinders {
        let idx = querySeries(globalStore.oldSeries ?? [], finder)
        if let idx = idx, idx >= 0 {
            from.append(TransitionSeries(
                dataGroupId: globalStore.oldDataGroupIds[idx],
                data: globalStore.oldData[idx],
                // TODO can specify divideShape in transition.
                divide: getDivideShapeFromData(globalStore.oldData[idx]),
                groupIdDim: finder.dimension
            ))
        }
    }
    let toFinders: [UpdateLifecycleTransitionSeriesFinder] = model.normalizeToArray(transitionOpt.to)
    for finder in toFinders {
        let idx = querySeries(params.updatedSeries ?? [], finder)
        if let idx = idx, idx >= 0 {
            let data = params.updatedSeries![idx].getData()
            to.append(TransitionSeries(
                // upstream indexes `globalStore.oldDataGroupIds` with the NEW series index here (a
                //   known upstream oddity, kept); guarded against out-of-range, which JS tolerates.
                dataGroupId: idx < globalStore.oldDataGroupIds.count ? globalStore.oldDataGroupIds[idx] : nil,
                data: data,
                divide: getDivideShapeFromData(data),
                groupIdDim: finder.dimension
            ))
        }
    }
    if from.count > 0 && to.count > 0 {
        transitionBetween(from, to, api)
    }
}

public func installUniversalTransition(_ registers: EChartsExtensionInstallRegisters) {

    registers.registerUpdateLifecycle("series:beforeupdate", { (_ ecMOdel: GlobalModel, _ api: ExtensionAPI, _ params: UpdateLifecycleParams) in
        _ = ecMOdel
        _ = api
        let transOpts: [UpdateLifecycleTransitionItem] = model.normalizeToArray(params.seriesTransition)
        for transOpt in transOpts {
            let finders: [UpdateLifecycleTransitionSeriesFinder] = model.normalizeToArray(transOpt.to)
            for finder in finders {
                let series = params.updatedSeries ?? []
                for i in 0..<series.count {
                    if (finder.seriesIndex != nil && finder.seriesIndex == series[i].seriesIndex)
                        || (finder.seriesId != nil && finder.seriesId == series[i].id) {
                        // series[i][SERIES_UNIVERSAL_TRANSITION_PROP] = true;
                        series[i].__universalTransitionEnabled = true
                    }
                }
            }
        }
    } as LifecycleUpdateCallback)

    registers.registerUpdateLifecycle("series:transition", { (_ ecModel: GlobalModel, _ api: ExtensionAPI, _ params: UpdateLifecycleParams) in
        // TODO api provide an namespace that can save stuff per instance
        let globalStore = getUniversalTransitionGlobalStore(api)

        // TODO multiple to multiple series.
        if globalStore.oldSeries != nil && params.updatedSeries != nil && params.optionChanged == true {
            // TODO transitionOpt was used in an old implementation and can be removed now
            // Use give transition config if its' give;
            let transitionOpt = params.seriesTransition
            if transitionOpt != nil {
                let opts: [UpdateLifecycleTransitionItem] = model.normalizeToArray(transitionOpt)
                for opt in opts {
                    transitionSeriesFromOpt(opt, globalStore, params, api)
                }
            }
            else {  // Else guess from series based on transition series key.
                let updateBatches = findTransitionSeriesBatches(globalStore, params)
                for key in updateBatches.keys() {
                    let batch = updateBatches.get(key)!
                    transitionBetween(batch.oldSeries, batch.newSeries, api)
                }
            }

            // Reset
            for series in params.updatedSeries ?? [] {
                // Reset;
                if series.__universalTransitionEnabled == true {
                    series.__universalTransitionEnabled = false
                }
            }
        }

        // Save all series of current update. Not only the updated one.
        let allSeries = ecModel.getSeries()
        var savedSeries: [SeriesModel] = []
        var savedDataGroupIds: [String?] = []
        var savedData: [SeriesData] = []
        for i in 0..<allSeries.count {
            let data = allSeries[i].getData()
            // Only save the data that can have transition.
            // Avoid large data costing too much extra memory
            if Double(data.count()) < DATA_COUNT_THRESHOLD {
                savedSeries.append(allSeries[i])
                savedDataGroupIds.append(allSeries[i].get("dataGroupId") as? String)
                savedData.append(data)
            }
        }
        globalStore.oldSeries = savedSeries
        globalStore.oldDataGroupIds = savedDataGroupIds
        globalStore.oldData = savedData
    } as LifecycleUpdateCallback)
}
