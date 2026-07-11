// Ported from echarts/src/component/brush/visualEncoding.ts (+ the rect branch of
// echarts/src/component/brush/selector.ts and the grid/rect subset of
// echarts/src/component/helper/BrushTargetManager.ts) — keep in sync with upstream.
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

// ============================================================================
// PORT SCOPE (Phase 44 — brush milestone)
//
// This is the RECTANGLE brush on a cartesian grid only. DEFERRED (marked PORT-TODO inline):
//   - lineX / lineY / polygon brush types (selector.ts `getLineSelectors` + polygon branch).
//   - geo / parallel coordinate systems (BrushTargetManager `geo` builder + `stepAParallel`).
//   - the throttle machinery + the `zr[DISPATCH_FLAG]` re-entrancy guard around `brushSelect`
//     (throttleUtil.createOrUpdate needs a live zr — not available headlessly).
//
// UPSTREAM SURFACE consumed from Task 1 (the ported BrushModel). `BrushModel` is expected to
// conform to `BrushModelLike` below (its `areas` runtime state + `setAreas`). Areas are modeled
// as the CONVENTIONS dynamic bag `[String: Any]` (BrushAreaParamInternal), with keys:
//   "brushType"   : String ("rect" here)
//   "range"       : [[Double]] pixel min/max  [[x0,x1],[y0,y1]]  (computed from coordRange)
//   "coordRange"  : [[Double]] data min/max    (the dispatch input for a coord-bound area)
//   "panelId"     : String?    (assigned by setInputRanges once a target grid is matched)
//   "gridIndex"/"xAxisIndex"/"yAxisIndex" : finder to bind the area to a grid.
//
// PORT DEVIATION: upstream stores `brushModel.brushTargetManager` on the model and reads it in
// `stepAOthers`. Here the target manager is a local built once per `brushVisual` pass and threaded
// through — it avoids adding a stored property to the Task-1 class and keeps the two invocation
// sites (layoutCovers + stepAOthers) using the same instance.
// ============================================================================

/// The Task-1 `BrushModel` is expected to conform to this so the visual encoder can read/write its
/// runtime `areas`. (Mirrors the dataZoomAction convention of assuming a Task-1 model surface.)
public protocol BrushModelLike: AnyObject {
    var areas: [[String: Any]] { get set }
    func setAreas(_ areas: [[String: Any]]?)
}

// type BrushVisualState = 'inBrush' | 'outOfBrush';
// const STATE_LIST = ['inBrush', 'outOfBrush'];
private let STATE_LIST: [String] = ["inBrush", "outOfBrush"]

// ---------------------------------------------------------------------------
// selector.ts — the RECT selector + `makeBrushCommonSelectorForSeries`.
// ---------------------------------------------------------------------------

// export interface BrushSelectableArea extends BrushAreaParamInternal {
//     boundingRect: BoundingRect; selectors: BrushCommonSelectorsForSeries;
// }
//   Modeled as a class carrying the raw area bag + the computed boundingRect + bound selectors.
final class BrushSelectableArea {
    var area: [String: Any]
    var brushType: String
    var range: Any?
    var boundingRect: BoundingRect?
    // Bound selectors (upstream `area.selectors`), assigned right after construction.
    var selectors: BrushCommonSelectorsForSeries!

    init(_ area: [String: Any]) {
        self.area = area
        self.brushType = (area["brushType"] as? String) ?? ""
        self.range = area["range"]
        self.boundingRect = boundingRectBuilders[self.brushType].map { $0(area) } ?? nil
    }
}

// export interface BrushCommonSelectorsForSeries { point(itemLayout); rect(itemLayout); }
final class BrushCommonSelectorsForSeries {
    let pointFn: ([Double]?) -> Bool
    let rectFn: (RectLike?) -> Bool
    init(point: @escaping ([Double]?) -> Bool, rect: @escaping (RectLike?) -> Bool) {
        self.pointFn = point
        self.rectFn = rect
    }
    func point(_ itemLayout: [Double]?) -> Bool { pointFn(itemLayout) }
    func rect(_ itemLayout: RectLike?) -> Bool { rectFn(itemLayout) }
}

// export function makeBrushCommonSelectorForSeries(area): BrushCommonSelectorsForSeries
func makeBrushCommonSelectorForSeries(_ area: BrushSelectableArea) -> BrushCommonSelectorsForSeries {
    let brushType = area.brushType
    // selectorsByBrushType dispatch (upstream `selector[brushType]`).
    switch brushType {
    case "rect":
        return BrushCommonSelectorsForSeries(
            // rect.point: itemLayout && area.boundingRect.contain(itemLayout[0], itemLayout[1])
            point: { itemLayout in
                guard let p = itemLayout, p.count >= 2, let br = area.boundingRect else { return false }
                return br.contain(p[0], p[1])
            },
            // rect.rect: itemLayout && area.boundingRect.intersect(itemLayout)
            rect: { itemLayout in
                guard let rl = itemLayout, let br = area.boundingRect else { return false }
                return br.intersect(rl)
            }
        )
    case "lineX":
        // getLineSelectors(0): area.range is the 1D pixel band [x0, x1] on the X dim.
        let range = brushRange1D(area.area["range"])
        return BrushCommonSelectorsForSeries(
            // point: range[0] <= itemLayout[0] <= range[1]
            point: { itemLayout in
                guard let p = itemLayout, p.count >= 1, let r = range else { return false }
                return r[0] <= p[0] && p[0] <= r[1]
            },
            // rect: range[0] <= x+width && x <= range[1] (x-overlap)
            rect: { itemLayout in
                guard let rl = itemLayout, let r = range else { return false }
                return r[0] <= rl.x + rl.width && rl.x <= r[1]
            }
        )
    case "lineY":
        // getLineSelectors(1): area.range is the 1D pixel band [y0, y1] on the Y dim.
        let range = brushRange1D(area.area["range"])
        return BrushCommonSelectorsForSeries(
            // point: range[0] <= itemLayout[1] <= range[1]
            point: { itemLayout in
                guard let p = itemLayout, p.count >= 2, let r = range else { return false }
                return r[0] <= p[1] && p[1] <= r[1]
            },
            // rect: range[0] <= y+height && y <= range[1] (y-overlap)
            rect: { itemLayout in
                guard let rl = itemLayout, let r = range else { return false }
                return r[0] <= rl.y + rl.height && rl.y <= r[1]
            }
        )
    case "polygon":
        // selector.ts polygon: point-in-polygon (ray casting) within the area's boundingRect.
        let points = brushPolygonPoints(area.area["range"])
        return BrushCommonSelectorsForSeries(
            // point: boundingRect.contain(x,y) && polygonContain.contain(range, x, y)
            point: { itemLayout in
                guard let p = itemLayout, p.count >= 2, let br = area.boundingRect, let pts = points else { return false }
                return br.contain(p[0], p[1]) && ZRenderKit.polygon.contain(pts, p[0], p[1])
            },
            // rect: any bar corner inside the polygon, OR a polygon vertex inside the bar, OR a bar edge
            //   crossing a polygon edge (upstream selector.ts polygon.rect).
            rect: { itemLayout in
                guard let rl = itemLayout, let pts = points, pts.count > 1 else { return false }
                let x = rl.x, y = rl.y, w = rl.width, h = rl.height
                if ZRenderKit.polygon.contain(pts, x, y) || ZRenderKit.polygon.contain(pts, x + w, y)
                    || ZRenderKit.polygon.contain(pts, x, y + h) || ZRenderKit.polygon.contain(pts, x + w, y + h) {
                    return true
                }
                // a polygon vertex inside the bar rect
                if let first = pts.first, BoundingRect.contain(rl, first[0], first[1]) { return true }
                // a bar edge crossing any polygon edge
                return linePolygonIntersect(x, y, x + w, y, pts)
                    || linePolygonIntersect(x, y, x, y + h, pts)
                    || linePolygonIntersect(x + w, y, x + w, y + h, pts)
                    || linePolygonIntersect(x, y + h, x + w, y + h, pts)
            }
        )
    default:
        return BrushCommonSelectorsForSeries(point: { _ in false }, rect: { _ in false })
    }
}

// A polygon area's `range` is a point list `[[x0,y0], [x1,y1], …]` (pixel). Returned as `VectorArray`
//   (SIMD2<Double>) so it feeds `ZRenderKit.polygon.contain` directly; `p[0]`/`p[1]` still subscript it.
private func brushPolygonPoints(_ v: Any?) -> [VectorArray]? {
    guard let arr = v as? [Any] else { return nil }
    let pts = arr.compactMap { row -> VectorArray? in
        if let r = row as? [Double], r.count >= 2 { return VectorArray(r[0], r[1]) }
        if let r = row as? [Any] {
            let d = r.compactMap { coerceDouble($0) }
            if d.count >= 2 { return VectorArray(d[0], d[1]) }
        }
        return nil
    }
    return pts.count >= 2 ? pts : nil
}

// linePolygonIntersect(a1x, a1y, a2x, a2y, points): true if segment (a1→a2) crosses any polygon edge.
private func linePolygonIntersect(_ a1x: Double, _ a1y: Double, _ a2x: Double, _ a2y: Double,
                                  _ points: [VectorArray]) -> Bool {
    let n = points.count
    for i in 0..<n {
        let p1 = points[i], p2 = points[(i + 1) % n]
        if brushSegIntersect(a1x, a1y, a2x, a2y, p1[0], p1[1], p2[0], p2[1]) { return true }
    }
    return false
}

// Standard orientation-based segment intersection (proper crossings; collinear-overlap edge cases elided).
private func brushSegIntersect(_ a1x: Double, _ a1y: Double, _ a2x: Double, _ a2y: Double,
                               _ b1x: Double, _ b1y: Double, _ b2x: Double, _ b2y: Double) -> Bool {
    func cross(_ ox: Double, _ oy: Double, _ ax: Double, _ ay: Double, _ bx: Double, _ by: Double) -> Double {
        return (ax - ox) * (by - oy) - (ay - oy) * (bx - ox)
    }
    let d1 = cross(b1x, b1y, b2x, b2y, a1x, a1y)
    let d2 = cross(b1x, b1y, b2x, b2y, a2x, a2y)
    let d3 = cross(a1x, a1y, a2x, a2y, b1x, b1y)
    let d4 = cross(a1x, a1y, a2x, a2y, b2x, b2y)
    return ((d1 > 0) != (d2 > 0)) && ((d3 > 0) != (d4 > 0))
}

// A lineX/lineY area's `range` is a 1-D `[min, max]` pixel band (NOT the rect `[[x0,x1],[y0,y1]]`).
private func brushRange1D(_ v: Any?) -> [Double]? {
    if let a = v as? [Double], a.count >= 2 { return [Swift.min(a[0], a[1]), Swift.max(a[0], a[1])] }
    if let a = v as? [Any] {
        let d = a.compactMap { coerceDouble($0) }
        if d.count >= 2 { return [Swift.min(d[0], d[1]), Swift.max(d[0], d[1])] }
    }
    return nil
}

// const boundingRectBuilders: Partial<Record<BrushType, AreaBoundingRectBuilder>>
private let boundingRectBuilders: [String: ([String: Any]) -> BoundingRect?] = [
    // rect: getBoundingRectFromMinMax(area.range)
    "rect": { area in
        guard let range = brushRangeMinMax(area["range"]) else { return nil }
        return getBoundingRectFromMinMax(range)
    },
    // polygon: the bounding box (min/max union) over the range's point list.
    "polygon": { area in
        guard let pts = brushPolygonPoints(area["range"]) else { return nil }
        var minX = pts[0][0], maxX = pts[0][0], minY = pts[0][1], maxY = pts[0][1]
        for p in pts {
            minX = Swift.min(minX, p[0]); maxX = Swift.max(maxX, p[0])
            minY = Swift.min(minY, p[1]); maxY = Swift.max(maxY, p[1])
        }
        return BoundingRect(minX, minY, maxX - minX, maxY - minY)
    }
]

// function getBoundingRectFromMinMax(minMax): BoundingRect
private func getBoundingRectFromMinMax(_ minMax: [[Double]]) -> BoundingRect {
    return BoundingRect(
        minMax[0][0],
        minMax[1][0],
        minMax[0][1] - minMax[0][0],
        minMax[1][1] - minMax[1][0]
    )
}

// ---------------------------------------------------------------------------
// The visual stage handler.
// export const brushVisualStageHandler = createSimpleOverallStageHandler2(brushVisual);
// ---------------------------------------------------------------------------
public let brushVisualStageHandler: StageHandler = model.createSimpleOverallStageHandler2(brushVisual)

// export function layoutCovers(ecModel): void
//   Upstream builds a BrushTargetManager and calls setInputRanges (coordRange -> pixel range).
public func layoutCovers(_ ecModel: GlobalModel) {
    ecModel.eachComponent("brush") { brushModel, _ in
        guard let brush = brushModel as? BrushModelLike else { return }
        let mgr = BrushTargetManagerLite(brushModel, ecModel)
        mgr.setInputRanges(&brush.areas, ecModel)
    }
}

// function brushVisual(ecModel, api, payload)
public func brushVisual(_ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload?) {

    // The `brushSelected` event batch (one entry per brush component).
    let brushSelected = BrushSelectedBatch()

    // PORT-TODO: `takeGlobalCursor` -> brushModel.setBrushOption(...) drives the paint cursor; deferred
    //   (belongs to the BrushController paint flow). The layout below still runs so `range` is fresh.

    layoutCovers(ecModel)

    ecModel.eachComponent("brush") { brushModel, brushIndexD in
        let brushIndex = Int(brushIndexD)
        guard let brush = brushModel as? BrushModelLike else { return }
        let brushOption = (brushModel.option as? [String: Any]) ?? [:]

        // const thisBrushSelected = { brushId, brushIndex, brushName, areas: clone(areas), selected: [] };
        let thisBrushSelected = BrushSelectedItem(
            brushId: brushModel.id,
            brushIndex: brushIndex,
            brushName: brushModel.name,
            areas: util.clone(brush.areas)
        )
        brushSelected.items.append(thisBrushSelected)

        // brushLink (number[] | 'all' | 'none'); selectedDataIndexForLink; rangeInfoBySeries.
        let brushLink = brushOption["brushLink"]
        var linkedSeriesMap: [Int: Bool] = [:]
        var selectedDataIndexForLink: [Int: Bool] = [:]
        var rangeInfoBySeries: [Int: [BrushSelectableArea]] = [:]
        var hasBrushExists = false

        let mgr = BrushTargetManagerLite(brushModel, ecModel)

        // Add boundingRect + selectors to each area (map over brushModel.areas).
        let areas: [BrushSelectableArea] = util.map(brush.areas) { areaBag, _ in
            let selectableArea = BrushSelectableArea(areaBag)
            selectableArea.selectors = makeBrushCommonSelectorForSeries(selectableArea)
            return selectableArea
        }

        // const visualMappings = createVisualMappings(option, STATE_LIST, mo => mo.mappingMethod = 'fixed');
        let visualMappings = visualSolution.createVisualMappings(
            brushOption, STATE_LIST
        ) { mappingOption, _ in
            mappingOption["mappingMethod"] = "fixed"
        }

        // isArray(brushLink) && each(brushLink, i => linkedSeriesMap[i] = 1);
        if let linkArr = brushLink as? [Any] {
            util.each(linkArr) { si, _ in
                if let i = coerceInt(si) { linkedSeriesMap[i] = true }
            }
        }

        func linkOthers(_ seriesIndex: Int) -> Bool {
            // brushLink === 'all' || !!linkedSeriesMap[seriesIndex]
            return (brushLink as? String) == "all" || (linkedSeriesMap[seriesIndex] ?? false)
        }

        // function brushed(rangeInfoList) { return !!rangeInfoList.length; }
        func brushed(_ rangeInfoList: [BrushSelectableArea]) -> Bool { !rangeInfoList.isEmpty }

        // ---- Step A ----
        ecModel.eachSeries { seriesModel, seriesIndexD in
            let seriesIndex = Int(seriesIndexD)
            var rangeInfoList: [BrushSelectableArea] = []

            // subType === 'parallel' ? stepAParallel(...) : stepAOthers(...)
            if seriesModel.subType == "parallel" {
                // PORT-TODO: stepAParallel (ParallelSeries.coordinateSystem.hasAxisBrushed / eachActiveState)
                //   is deferred (parallel coord out of scope). No brush contribution.
            }
            else {
                // stepAOthers
                if brushSelectorSupported(seriesModel) && !brushModelNotControll(brushOption, seriesIndex) {
                    util.each(areas) { area, _ in
                        if mgr.controlSeries(area, seriesModel, ecModel) {
                            rangeInfoList.append(area)
                        }
                        hasBrushExists = hasBrushExists || brushed(rangeInfoList)
                    }
                    if linkOthers(seriesIndex) && brushed(rangeInfoList) {
                        let data = seriesModel.getData()
                        data.each { args in
                            let dataIndex = Int((args.first as? Double) ?? 0)
                            if checkInRange(seriesModel, rangeInfoList, data, dataIndex) {
                                selectedDataIndexForLink[dataIndex] = true
                            }
                        }
                    }
                }
            }
            rangeInfoBySeries[seriesIndex] = rangeInfoList
        }

        // ---- Step B ----
        ecModel.eachSeries { seriesModel, seriesIndexD in
            let seriesIndex = Int(seriesIndexD)
            let seriesBrushSelected = BrushSelectedSeries(
                seriesId: seriesModel.id,
                seriesIndex: seriesIndex,
                seriesName: seriesModel.name
            )
            thisBrushSelected.selected.append(seriesBrushSelected)

            let rangeInfoList = rangeInfoBySeries[seriesIndex] ?? []
            let data = seriesModel.getData()

            // getValueState: valueOrIndex(here == dataIndex) -> 'inBrush' | 'outOfBrush'
            let getValueState: (Any?) -> String = { valueOrIndex in
                let dataIndex = Int((valueOrIndex as? Double) ?? 0)
                if linkOthers(seriesIndex) {
                    if selectedDataIndexForLink[dataIndex] ?? false {
                        seriesBrushSelected.dataIndex.append(data.getRawIndex(dataIndex))
                        return "inBrush"
                    }
                    return "outOfBrush"
                }
                else {
                    if checkInRange(seriesModel, rangeInfoList, data, dataIndex) {
                        seriesBrushSelected.dataIndex.append(data.getRawIndex(dataIndex))
                        return "inBrush"
                    }
                    return "outOfBrush"
                }
            }

            // (linkOthers ? hasBrushExists : brushed(rangeInfoList)) && applyVisual(...)
            let shouldApply = linkOthers(seriesIndex) ? hasBrushExists : brushed(rangeInfoList)
            if shouldApply {
                visualSolution.applyVisual(STATE_LIST, visualMappings, data, getValueState, nil)
            }
        }
    }

    dispatchBrushSelected(api, brushSelected, payload)
}

// function dispatchAction(api, throttleType, throttleDelay, brushSelected, payload)
//   PORT-TODO: the throttle (throttleUtil.createOrUpdate) + `zr[DISPATCH_FLAG]` re-entrancy guard need a
//   live zr; here we dispatch synchronously when a `payload` is present (matches upstream's "only on a
//   real action, never on setOption" gate). `brushSelect` has update:'none', so it does not re-run visual.
private func dispatchBrushSelected(_ api: ExtensionAPI, _ brushSelected: BrushSelectedBatch, _ payload: Payload?) {
    if payload == nil { return }
    var p = Payload(type: "brushSelect")
    p.other["batch"] = brushSelected.toEventBatch()
    api.dispatchAction(p)
}

// function checkInRange(seriesModel, rangeInfoList, data, dataIndex)
private func checkInRange(
    _ seriesModel: SeriesModel,
    _ rangeInfoList: [BrushSelectableArea],
    _ data: SeriesData,
    _ dataIndex: Int
) -> Bool {
    for area in rangeInfoList {
        // seriesModel.brushSelector(dataIndex, data, area.selectors, area)
        if seriesBrushSelector(seriesModel, dataIndex, data, area.selectors) {
            return true
        }
    }
    return false
}

// function brushModelNotControll(brushModel, seriesIndex)
//   seriesIndex != null && !== 'all' && (isArray ? indexOf < 0 : seriesIndex !== seriesIndices)
private func brushModelNotControll(_ brushOption: [String: Any], _ seriesIndex: Int) -> Bool {
    let seriesIndices = brushOption["seriesIndex"]
    if seriesIndices == nil || seriesIndices is NSNull { return false }
    if let s = seriesIndices as? String, s == "all" { return false }
    if let arr = seriesIndices as? [Any] {
        return util.indexOf(arr.compactMap { coerceInt($0) }, seriesIndex) < 0
    }
    if let single = coerceInt(seriesIndices) {
        return seriesIndex != single
    }
    return false
}

// ---------------------------------------------------------------------------
// Per-series brushSelector dispatch.
//
// Upstream defines `brushSelector` on each series prototype:
//   scatter/effectScatter: return selectors.point(data.getItemLayout(dataIndex))
//   bar:                   return selectors.rect(data.getItemLayout(dataIndex))
// Those overrides are not yet ported onto the Swift series subclasses (see the PORT-NOTEs in
// ScatterSeries.swift / BarSeries.swift), so the dispatch is centralized here, keyed by subType.
// PORT-NOTE: move each branch onto its series subclass once `brushSelector` lands there.
// ---------------------------------------------------------------------------
private func brushSelectorSupported(_ seriesModel: SeriesModel) -> Bool {
    switch seriesModel.subType {
    case "scatter", "effectScatter", "bar": return true
    default: return false   // upstream: `!seriesModel.brushSelector` short-circuits stepAOthers.
    }
}

private func seriesBrushSelector(
    _ seriesModel: SeriesModel,
    _ dataIndex: Int,
    _ data: SeriesData,
    _ selectors: BrushCommonSelectorsForSeries
) -> Bool {
    let layout = data.getItemLayout(dataIndex)
    switch seriesModel.subType {
    case "scatter", "effectScatter":
        // selectors.point(itemLayout: number[])
        if let arr = layout as? [Double] { return selectors.point(arr) }
        if let arr = layout as? [Any] { return selectors.point(arr.compactMap { coerceDouble($0) }) }
        return false
    case "bar":
        // selectors.rect(itemLayout: RectLike)  — bar layout is {x,y,width,height}.
        if let rl = layout as? RectLike { return selectors.rect(rl) }
        if let d = layout as? [String: Any] {
            let x = coerceDouble(d["x"]) ?? 0, y = coerceDouble(d["y"]) ?? 0
            let w = coerceDouble(d["width"]) ?? 0, h = coerceDouble(d["height"]) ?? 0
            return selectors.rect(BoundingRect(x, y, w, h))
        }
        return false
    default:
        return false
    }
}

// ---------------------------------------------------------------------------
// BrushTargetManager (grid / rect subset).
// ---------------------------------------------------------------------------
final class BrushTargetManagerLite {

    struct GridTarget {
        let panelId: String
        let gridIndex: Int
        let coordSyses: [Cartesian2D]
    }

    private var targets: [GridTarget] = []
    // Finder parsed from the brush option (which grids/axes this brush is bound to).
    private let gridIndexFinder: FinderSel
    private let xAxisIndexFinder: FinderSel
    private let yAxisIndexFinder: FinderSel

    enum FinderSel {
        case all              // undefined/absent -> match everything in scope
        case indices([Int])
    }

    init(_ brushModel: ComponentModel, _ ecModel: GlobalModel) {
        let opt = (brushModel.option as? [String: Any]) ?? [:]
        gridIndexFinder = BrushTargetManagerLite.parseFinderSel(opt["gridIndex"])
        xAxisIndexFinder = BrushTargetManagerLite.parseFinderSel(opt["xAxisIndex"])
        yAxisIndexFinder = BrushTargetManagerLite.parseFinderSel(opt["yAxisIndex"])

        // Build one GridTarget per grid coordinate system.
        // PORT-TODO: geo targetInfoBuilder deferred.
        ecModel.eachComponent("grid") { gridModel, gridIdxD in
            let gridIdx = Int(gridIdxD)
            guard let gm = gridModel as? GridModel,
                  let grid = gm.coordinateSystem as? Grid else { return }
            let cartesians = grid.getCartesians()
            if cartesians.isEmpty { return }
            self.targets.append(GridTarget(
                panelId: "grid--" + gridModel.id,
                gridIndex: gridIdx,
                coordSyses: cartesians
            ))
        }
    }

    private static func parseFinderSel(_ v: Any?) -> FinderSel {
        if v == nil || v is NSNull { return .all }
        if let s = v as? String, s == "all" { return .all }
        if let arr = v as? [Any] { return .indices(arr.compactMap { coerceInt($0) }) }
        if let i = coerceInt(v) { return .indices([i]) }
        return .all
    }

    // findTargetInfo: match by area.panelId first, then by finder, else global (nil).
    func findTargetInfo(_ area: BrushSelectableArea, _ ecModel: GlobalModel) -> GridTarget? {
        // Match by panelId.
        if let panelId = area.area["panelId"] as? String {
            return targets.first { $0.panelId == panelId }
        }
        // Match by finder (area-level overrides, else brush-option-level).
        let areaGridSel = BrushTargetManagerLite.parseFinderSel(area.area["gridIndex"])
        let gridSel = isAll(areaGridSel) ? gridIndexFinder : areaGridSel
        if case .indices(let gi) = gridSel {
            if let t = targets.first(where: { gi.contains($0.gridIndex) }) { return t }
        }
        // xAxis/yAxis finder: in single-grid scope, any coord finder binds to the first grid.
        let hasCoordFinder = area.area["gridIndex"] != nil
            || area.area["xAxisIndex"] != nil || area.area["yAxisIndex"] != nil
            || !isAll(xAxisIndexFinder) || !isAll(yAxisIndexFinder) || !isAll(gridIndexFinder)
        if hasCoordFinder {
            return targets.first
        }
        // No coord binding -> global area (upstream returns `true`; nil here means "global").
        return nil
    }

    // controlSeries(area, seriesModel): true if the series' cartesian is inside the matched target.
    func controlSeries(_ area: BrushSelectableArea, _ seriesModel: SeriesModel, _ ecModel: GlobalModel) -> Bool {
        let target = findTargetInfo(area, ecModel)
        if target == nil {
            return true   // global area controls all series (upstream `targetInfo === true`).
        }
        guard let series2d = seriesModel.coordinateSystem as? Cartesian2D else { return false }
        return target!.coordSyses.contains { $0 === series2d }
    }

    // setInputRanges: convert each area's coordRange -> pixel range (rect) and stamp panelId.
    func setInputRanges(_ areas: inout [[String: Any]], _ ecModel: GlobalModel) {
        for i in areas.indices {
            let selectable = BrushSelectableArea(areas[i])
            let target = findTargetInfo(selectable, ecModel)

            // area.range = area.range || [];
            if areas[i]["range"] == nil { areas[i]["range"] = [[Double]]() }

            guard let target = target, let coordSys = target.coordSyses.first else {
                // Global area: keep its (pixel) range as given.
                continue
            }
            areas[i]["panelId"] = target.panelId

            // rect coordConvert(to=0 / dataToPoint): range = f(coordRange).
            guard let coordRange = brushRangeMinMax(areas[i]["coordRange"]) else { continue }
            let range = rectCoordConvertDataToPoint(coordSys, coordRange)
            areas[i]["range"] = range
            // PORT-TODO: __rangeOffset (category-axis non-reversible rebuild + dataZoom scale) deferred.
        }
    }

    private func isAll(_ f: FinderSel) -> Bool {
        if case .all = f { return true }
        return false
    }
}

// rect coordConvert (to = 0, dataToPoint): the pixel min/max box for a data-space [[x0,x1],[y0,y1]].
//   xminymin = dataToPoint([cr[0][0], cr[1][0]]); xmaxymax = dataToPoint([cr[0][1], cr[1][1]]);
//   values = [ formatMinMax([xminymin[0], xmaxymax[0]]), formatMinMax([xminymin[1], xmaxymax[1]]) ]
private func rectCoordConvertDataToPoint(_ coordSys: Cartesian2D, _ coordRange: [[Double]]) -> [[Double]] {
    let xminymin = coordSys.dataToPoint([coordRange[0][0], coordRange[1][0]])
    let xmaxymax = coordSys.dataToPoint([coordRange[0][1], coordRange[1][1]])
    return [
        formatMinMax([xminymin[0], xmaxymax[0]]),
        formatMinMax([xminymin[1], xmaxymax[1]])
    ]
}

// function formatMinMax(minMax) { minMax[0] > minMax[1] && minMax.reverse(); return minMax; }
private func formatMinMax(_ minMax: [Double]) -> [Double] {
    return minMax[0] > minMax[1] ? [minMax[1], minMax[0]] : minMax
}

// ---------------------------------------------------------------------------
// brushSelected event payload model (BrushSelectedItem[]).
// ---------------------------------------------------------------------------
final class BrushSelectedSeries {
    let seriesId: String
    let seriesIndex: Int
    let seriesName: String
    var dataIndex: [Int] = []
    init(seriesId: String, seriesIndex: Int, seriesName: String) {
        self.seriesId = seriesId; self.seriesIndex = seriesIndex; self.seriesName = seriesName
    }
    func toDict() -> [String: Any] {
        return ["seriesId": seriesId, "seriesIndex": seriesIndex, "seriesName": seriesName,
                "dataIndex": dataIndex]
    }
}
final class BrushSelectedItem {
    let brushId: String
    let brushIndex: Int
    let brushName: String
    let areas: [[String: Any]]
    var selected: [BrushSelectedSeries] = []
    init(brushId: String, brushIndex: Int, brushName: String, areas: [[String: Any]]) {
        self.brushId = brushId; self.brushIndex = brushIndex; self.brushName = brushName; self.areas = areas
    }
    func toDict() -> [String: Any] {
        return ["brushId": brushId, "brushIndex": brushIndex, "brushName": brushName,
                "areas": areas, "selected": selected.map { $0.toDict() }]
    }
    /// The selected raw dataIndices per series — the headless test oracle.
    func selectedDataIndices(_ seriesIndex: Int) -> [Int] {
        return selected.first { $0.seriesIndex == seriesIndex }?.dataIndex ?? []
    }
}
final class BrushSelectedBatch {
    var items: [BrushSelectedItem] = []
    func toEventBatch() -> [[String: Any]] { items.map { $0.toDict() } }
}

// ---------------------------------------------------------------------------
// Small numeric coercers (Int-vs-Double option/payload-read trap).
// ---------------------------------------------------------------------------
private func brushRangeMinMax(_ v: Any?) -> [[Double]]? {
    guard let arr = v as? [Any], arr.count >= 2 else { return nil }
    func toPair(_ x: Any?) -> [Double]? {
        guard let a = x as? [Any], a.count >= 2,
              let lo = coerceDouble(a[0]), let hi = coerceDouble(a[1]) else { return nil }
        return [lo, hi]
    }
    guard let d0 = toPair(arr[0]), let d1 = toPair(arr[1]) else { return nil }
    return [d0, d1]
}

private func coerceInt(_ v: Any?) -> Int? {
    if let i = v as? Int { return i }
    if let d = v as? Double { return Int(d) }
    if let f = v as? CGFloat { return Int(f) }
    return nil
}

private func coerceDouble(_ v: Any?) -> Double? {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let f = v as? CGFloat { return Double(f) }
    return nil
}
