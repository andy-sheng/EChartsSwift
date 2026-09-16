// Ported from echarts/src/component/brush/selector.ts — keep in sync with upstream
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

// import * as polygonContain from 'zrender/src/contain/polygon';   -> ZRenderKit `polygon` (Contain/ContainPolygon.swift)
// import BoundingRect, { RectLike } from 'zrender/src/core/BoundingRect';  -> ZRenderKit BoundingRect / RectLike
// import {linePolygonIntersect} from '../../util/graphic';         -> `linePolygonIntersect` (util/graphic.swift)
// import { BrushType, BrushDimensionMinMax } from '../helper/BrushController';
//   -> BrushType / BrushDimensionMinMax (component/helper/BrushController.swift)
// import { BrushAreaParamInternal } from './BrushModel';           -> BrushAreaParamInternal ([String: Any])

// export interface BrushSelectableArea extends BrushAreaParamInternal {
//     boundingRect: BoundingRect;
//     selectors: BrushCommonSelectorsForSeries
// }
//
// upstream `BrushSelectableArea` is the area PARAM BAG itself (a plain object), decorated
//   in-place with `boundingRect` + `selectors` (`zrUtil.defaults({boundingRect}, area)`). The bag is
//   `[String: Any]` here (CONVENTIONS §2) and Swift dictionaries are value types, so the decorated area
//   is a reference-typed wrapper AROUND the bag: `area` keeps the raw param bag (the diffable surface
//   that `brushType` / `range` / `panelId` / the model-finder keys are read from) and the two decorations
//   are stored properties. Every upstream `area.brushType` / `area.range` / `area.boundingRect` read maps
//   1:1 onto this class.
public final class BrushSelectableArea {

    /// The raw `BrushAreaParamInternal` bag (upstream: the area object this interface extends).
    public var area: BrushAreaParamInternal

    // area.brushType (BrushType)
    public var brushType: BrushType
    // area.range (BrushAreaRange = BrushDimensionMinMax | BrushDimensionMinMax[])
    public var range: BrushAreaRange?
    // area.panelId
    public var panelId: String?

    // boundingRect: BoundingRect;
    public var boundingRect: BoundingRect?
    // selectors: BrushCommonSelectorsForSeries;   (assigned right after construction, as upstream does)
    public var selectors: BrushCommonSelectorsForSeries!

    public init(_ area: BrushAreaParamInternal, boundingRect: BoundingRect?) {
        self.area = area
        self.brushType = (area["brushType"] as? BrushType) ?? ""
        self.range = area["range"]
        self.panelId = area["panelId"] as? String
        self.boundingRect = boundingRect
    }
}

/**
 * Key of the first level is brushType: `line`, `rect`, `polygon`.
 * See moudule:echarts/component/helper/BrushController
 * function param:
 *      {Object} itemLayout fetch from data.getItemLayout(dataIndex)
 *      {Object} selectors {point: selector, rect: selector, ...}
 *      {Object} area {range: [[], [], ..], boudingRect}
 * function return:
 *      {boolean} Whether in the given brush.
 */
// interface BrushSelectorOnBrushType { point(itemLayout, selectors, area); rect(itemLayout, selectors, area); }
struct BrushSelectorOnBrushType {
    // For chart element type "point"
    //   itemLayout fetched from data.getItemLayout(dataIndex) — `number[]`, may be undefined -> `[Double]?`.
    let point: (_ itemLayout: [Double]?, _ selectors: BrushCommonSelectorsForSeries, _ area: BrushSelectableArea) -> Bool
    // For chart element type "rect"
    //   itemLayout fetched from data.getItemLayout(dataIndex) — `RectLike`, may be undefined -> `RectLike?`.
    let rect: (_ itemLayout: RectLike?, _ selectors: BrushCommonSelectorsForSeries, _ area: BrushSelectableArea) -> Bool
}

/**
 * This methods are corresponding to `BrushSelectorOnBrushType`,
 * but `area: BrushSelectableArea` is binded to each method.
 */
// export interface BrushCommonSelectorsForSeries { point(itemLayout): boolean; rect(itemLayout): boolean; }
//
// upstream builds an object literal whose two closures capture `selectors` (themselves) and
//   `area`. Reproducing that literally in Swift creates a strong self-reference cycle between the
//   closures and the object. The dispatch is therefore done in the methods, binding `brushType` + `area`
//   as stored properties (`area` unowned — the area OWNS the selectors, exactly as upstream). Behavior
//   is identical: `selectors.point(l)` == `selector[brushType].point(l, selectors, area)`.
public final class BrushCommonSelectorsForSeries {

    private let brushType: BrushType
    private unowned let area: BrushSelectableArea

    init(brushType: BrushType, area: BrushSelectableArea) {
        self.brushType = brushType
        self.area = area
    }

    // point(itemLayout: number[]) { return selector[brushType].point(itemLayout, selectors, area); }
    public func point(_ itemLayout: [Double]?) -> Bool {
        guard let sel = selector[brushType] else { return false }
        return sel.point(itemLayout, self, area)
    }

    // rect(itemLayout: RectLike) { return selector[brushType].rect(itemLayout, selectors, area); }
    public func rect(_ itemLayout: RectLike?) -> Bool {
        guard let sel = selector[brushType] else { return false }
        return sel.rect(itemLayout, self, area)
    }
}

/// The type of the OPTIONAL `SeriesModel#brushSelector` member (upstream model/Series.ts declares it in
/// the declaration-merged `interface SeriesModel`; see the note there):
///   brushSelector(dataIndex, data, selectors, area): boolean
public typealias BrushSelectorFn = (
    _ dataIndex: Int,
    _ data: SeriesData,
    _ selectors: BrushCommonSelectorsForSeries,
    _ area: BrushSelectableArea
) -> Bool

// export function makeBrushCommonSelectorForSeries(area: BrushSelectableArea): BrushCommonSelectorsForSeries
public func makeBrushCommonSelectorForSeries(
    _ area: BrushSelectableArea
) -> BrushCommonSelectorsForSeries {
    let brushType = area.brushType
    // Do not use function binding or curry for performance.
    let selectors = BrushCommonSelectorsForSeries(brushType: brushType, area: area)
    return selectors
}

// const selector: Record<BrushType, BrushSelectorOnBrushType> = { ... }
let selector: [BrushType: BrushSelectorOnBrushType] = [

    // lineX: getLineSelectors(0),
    "lineX": getLineSelectors(0),

    // lineY: getLineSelectors(1),
    "lineY": getLineSelectors(1),

    "rect": BrushSelectorOnBrushType(
        // point: itemLayout && area.boundingRect.contain(itemLayout[0], itemLayout[1])
        point: { itemLayout, _, area in
            guard let itemLayout = itemLayout, itemLayout.count >= 2,
                  let boundingRect = area.boundingRect else { return false }
            return boundingRect.contain(itemLayout[0], itemLayout[1])
        },
        // rect: itemLayout && area.boundingRect.intersect(itemLayout)
        rect: { itemLayout, _, area in
            guard let itemLayout = itemLayout, let boundingRect = area.boundingRect else { return false }
            return boundingRect.intersect(itemLayout)
        }
    ),

    "polygon": BrushSelectorOnBrushType(
        // point: itemLayout && area.boundingRect.contain(...) && polygonContain.contain(area.range, x, y)
        point: { itemLayout, _, area in
            guard let itemLayout = itemLayout, itemLayout.count >= 2,
                  let boundingRect = area.boundingRect,
                  let points = brushDimensionMinMaxList(area.range) else { return false }
            return boundingRect.contain(itemLayout[0], itemLayout[1])
                && polygon.contain(
                    toVectorArrayList(points), itemLayout[0], itemLayout[1]
                )
        },
        rect: { itemLayout, _, area in
            // const points = area.range as BrushDimensionMinMax[];
            guard let points = brushDimensionMinMaxList(area.range) else { return false }

            // if (!itemLayout || points.length <= 1) { return false; }
            guard let itemLayout = itemLayout, points.count > 1 else {
                return false
            }

            let x = itemLayout.x
            let y = itemLayout.y
            let width = itemLayout.width
            let height = itemLayout.height
            let p = points[0]

            let pts = toVectorArrayList(points)

            if polygon.contain(pts, x, y)
                || polygon.contain(pts, x + width, y)
                || polygon.contain(pts, x, y + height)
                || polygon.contain(pts, x + width, y + height)
                || BoundingRect.create(itemLayout).contain(p[0], p[1])
                || linePolygonIntersect(x, y, x + width, y, points)
                || linePolygonIntersect(x, y, x, y + height, points)
                || linePolygonIntersect(x + width, y, x + width, y + height, points)
                || linePolygonIntersect(x, y + height, x + width, y + height, points)
            {
                return true
            }
            // upstream: falls off the end -> `undefined` (falsy).
            return false
        }
    )
]

// function getLineSelectors(xyIndex: 0 | 1): BrushSelectorOnBrushType
func getLineSelectors(_ xyIndex: Int) -> BrushSelectorOnBrushType {
    // const xy = ['x', 'y'] as const;
    // const wh = ['width', 'height'] as const;
    //   the `itemLayout[xy[xyIndex]]` / `itemLayout[wh[xyIndex]]` string indexing of a
    //   `RectLike` is a keyPath pick in Swift; done with the two accessors below.
    func xyOf(_ rect: RectLike) -> Double { return xyIndex == 0 ? rect.x : rect.y }
    func whOf(_ rect: RectLike) -> Double { return xyIndex == 0 ? rect.width : rect.height }

    return BrushSelectorOnBrushType(
        point: { itemLayout, _, area in
            // if (itemLayout) { const range = area.range as BrushDimensionMinMax; ... }
            guard let itemLayout = itemLayout, itemLayout.count > xyIndex,
                  let range = brushDimensionMinMax(area.range) else {
                return false   // upstream: `undefined` (falsy) when no itemLayout.
            }
            let p = itemLayout[xyIndex]
            return inLineRange(p, range)
        },
        rect: { itemLayout, _, area in
            guard let itemLayout = itemLayout,
                  let range = brushDimensionMinMax(area.range) else {
                return false   // upstream: `undefined` (falsy) when no itemLayout.
            }
            var layoutRange: BrushDimensionMinMax = [
                xyOf(itemLayout),
                xyOf(itemLayout) + whOf(itemLayout)
            ]
            // layoutRange[1] < layoutRange[0] && layoutRange.reverse();
            if layoutRange[1] < layoutRange[0] {
                layoutRange.reverse()
            }
            return inLineRange(layoutRange[0], range)
                || inLineRange(layoutRange[1], range)
                || inLineRange(range[0], layoutRange)
                || inLineRange(range[1], layoutRange)
        }
    )
}

// function inLineRange(p: number, range: BrushDimensionMinMax): boolean
func inLineRange(_ p: Double, _ range: BrushDimensionMinMax) -> Bool {
    return range[0] <= p && p <= range[1]
}

// export default selector;  -> the module-level `selector` map above.

// ---------------------------------------------------------------------------
// PORT-LOCAL coercers (not in upstream).
//
// `BrushAreaRange` is the untagged TS union `BrushDimensionMinMax | BrushDimensionMinMax[]`, carried
// through the `[String: Any]` area bag. TS reads it with a cast (`area.range as BrushDimensionMinMax[]`);
// Swift needs a runtime coercion. These also absorb the Int-vs-Double trap of an option/payload bag
// literal (`range: [[0, 1], [2, 3]]` parses as `[[Int]]` in Swift unless annotated).
// ---------------------------------------------------------------------------

/// `area.range as BrushDimensionMinMax` — the 1-D `[min, max]` band of a lineX/lineY area.
func brushDimensionMinMax(_ range: BrushAreaRange?) -> BrushDimensionMinMax? {
    guard let arr = range as? [Any] else { return nil }
    let d = arr.compactMap { brushCoerceDouble($0) }
    return d.count >= 2 ? d : nil
}

/// `area.range as BrushDimensionMinMax[]` — the per-dimension min/max list of a rect area
/// (`[[xMin, xMax], [yMin, yMax]]`) or the point list of a polygon area (`[[x, y], ...]`).
func brushDimensionMinMaxList(_ range: BrushAreaRange?) -> [BrushDimensionMinMax]? {
    guard let arr = range as? [Any] else { return nil }
    var out: [BrushDimensionMinMax] = []
    for row in arr {
        guard let r = row as? [Any] else { return nil }
        let d = r.compactMap { brushCoerceDouble($0) }
        if d.count < 2 { return nil }
        out.append(d)
    }
    return out.isEmpty ? nil : out
}

/// `polygonContain.contain(points, x, y)` takes `VectorArray[]` (SIMD2) in ZRenderKit.
func toVectorArrayList(_ points: [BrushDimensionMinMax]) -> [VectorArray] {
    return points.map { VectorArray($0[0], $0[1]) }
}

func brushCoerceDouble(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let f = v as? Float { return Double(f) }
    if let c = v as? CGFloat { return Double(c) }
    return nil
}

func brushCoerceInt(_ v: Any?) -> Int? {
    if let i = v as? Int { return i }
    if let d = v as? Double { return Int(d) }
    if let c = v as? CGFloat { return Int(c) }
    return nil
}

/// Coerce a `data.getItemLayout(dataIndex)` value to the `RectLike` the rect selectors expect. Bar's
/// layout is stored as the `["x": .., "y": .., "width": .., "height": ..]` bag (layout/barGrid.swift),
/// upstream stores a `RectLike` object — accept both.
func brushItemLayoutAsRect(_ layout: Any?) -> RectLike? {
    if let r = layout as? RectLike { return r }
    if let d = layout as? [String: Any] {
        guard let x = brushCoerceDouble(d["x"]), let y = brushCoerceDouble(d["y"]),
              let w = brushCoerceDouble(d["width"]), let h = brushCoerceDouble(d["height"]) else { return nil }
        return BoundingRect(x, y, w, h)
    }
    return nil
}

/// Coerce a `data.getItemLayout(dataIndex)` value to the `number[]` point the point selectors expect.
func brushItemLayoutAsPoint(_ layout: Any?) -> [Double]? {
    if let p = layout as? [Double] { return p }
    if let arr = layout as? [Any] {
        let d = arr.compactMap { brushCoerceDouble($0) }
        return d.count >= 2 ? d : nil
    }
    return nil
}
