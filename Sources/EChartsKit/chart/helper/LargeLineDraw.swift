// Ported from echarts/src/chart/helper/LargeLineDraw.ts — keep in sync with upstream.
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

// TODO Batch by color

import Foundation
import ZRenderKit

// PORT SCOPE (large-mode fast path for `lines`): one `LargeLinesPath` paints EVERY line/segment of
//   the series in a single `buildPath` loop over the packed `linesPoints` layout (`[count?, x, y, ...]`
//   for polylines, or `[x0, y0, x1, y1, ...]` pairs for 2-point lines) — instead of one Line/Polyline
//   per item (LinesView's per-item reuse). This is the performance path for many lines.
//
// LAYOUT INVARIANT: `linesPoints` is always well-formed — non-polyline segs are a multiple of 4
//   (x0,y0,x1,y1 tuples); polyline segs are count-prefixed (count, then `count` x,y pairs). The
//   `buildPath` / `findDataIndex` loops read segs[i+1..i+3] past the `while i < count` guard on that
//   assumption (mirroring upstream, whose `segs[i++]` past the end yields NaN and no-ops; in Swift an
//   out-of-bounds read traps instead — a malformed/truncated buffer is a layout-stage bug, not input).
//
// DEVIATIONS (documented, matching sibling LargeSymbolDraw.swift):
//   - The progressive `_off`/`notClear` cursor + `beforeBrush(reset)` are ported for provenance but
//     stay INERT: the static/live driver has no incremental task graph (`incremental == 0`), so
//     `buildPath` always draws the full range in ONE pass and `_off` stays 0.
//   - `incrementalPrepareUpdate` / `incrementalUpdate` / `eachRendered` are ported (single-pass
//     semantics) so the ILineDraw surface stays complete, but the Scheduler task graph that would
//     call them is not ported (sub-project C). `incrementalUpdate` renders the given range as a
//     single path (the merge-into-lastAdded / Float32Array-concat split is kept faithfully so a
//     future task pipeline threads through unchanged).
//
// upstream: `baseDraw` / `ILineDraw` is NOT ported (same as the LineDraw precedent) → this is a
//   plain `public final class` with no protocol conformance. Wiring LargeLineDraw into LinesView is
//   a separate follow-up (LinesView currently keeps only PORT-NOTE deferrals for large mode).

// upstream: class LargeLinesPathShape { polyline = false; curveness = 0; segs: ArrayLike<number> = []; }
//   The packed `segs` are the projected `linesPoints` (upstream a Float32Array; here a [Double]).
public struct LargeLinesPathShape: PathShape {
    public var polyline: Bool = false
    public var curveness: Double = 0
    public var segs: [Double] = []
    public init() {}
    // polyline / curveness / segs are not tweened (the whole shape is replaced via setShape) →
    //   no keyed animation (default no-op animationGet/animationSet).
}

// upstream: class LargeLinesPath extends graphic.Path<LargeLinesPathProps>
//   A single Path that paints EVERY line of the series (one buildPath loop over the packed array).
public final class LargeLinesPath: Path {

    // upstream: __startIndex — the datum index this path's range begins at (progressive offset).
    public var __startIndex: Int = 0

    // upstream: private _off — progressive draw cursor (inert here, see the deviation note).
    private var _off: Int = 0

    // upstream: hoverDataIdx — the datum index found by the last `contain` hit-test (for tooltip).
    public var hoverDataIdx: Int = -1

    // upstream: notClear — the incremental-layer keep-alive flag (inherited from Displayable).
    //   Redeclared as non-optional here to mirror upstream's `notClear: boolean`; writes flow to
    //   the base Displayable.notClear via `self.notClear`.

    // Our own bounding-rect cache (the base `_rect` is private to ZRenderKit; upstream caches on
    //   `this._rect` — we mirror the "ignore stroke, derive from segs" rect here).
    private var _largeRect: BoundingRect?

    public override init(_ opts: PathProps? = nil) {
        super.init(opts)
        // upstream leaves `type` as 'path'; name it distinctively for debug / hit-test lookup.
        self.type = "largeLines"
    }

    // upstream: reset() { this.notClear = false; this._off = 0; }
    func reset() {
        self.notClear = false
        self._off = 0
    }

    // upstream: beforeBrush(param) { if (param && !param.contentRetained) { this.reset(); } }
    //   PORT-NOTE: `Displayable.beforeBrush` is `public` (not `open`) so it cannot be overridden from
    //   this module — and the progressive brush hook is inert here anyway (no incremental pipeline),
    //   exactly as sibling LargeSymbolPath omits the override. `reset()` is kept for provenance.

    // upstream: getDefaultStyle() { return { stroke: tokens.color.neutral99, fill: null as ColorString }; }
    public override func getDefaultStyle() -> PathStyleProps? {
        var style = PathStyleProps()
        style.stroke = .string(tokens.color.neutral99)
        style.fill = nil   // upstream: fill: null as ColorString
        return style
    }

    // upstream: getDefaultShape() { return new LargeLinesPathShape(); }
    public override func getDefaultShape() -> PathShape {
        return LargeLinesPathShape()
    }

    // upstream: buildPath(ctx, shape) — the per-segment loop.
    public override func buildPath(_ ctx: PathProxy, _ shapeIn: PathShape, _ inBatch: Bool) {
        guard let shape = shapeIn as? LargeLinesPathShape else { return }
        let segs = shape.segs
        let curveness = shape.curveness
        var i = self._off

        if shape.polyline {
            while i < segs.count {
                let count = Int(segs[i]); i += 1
                if count > 0 {
                    let x = segs[i]; i += 1
                    let y = segs[i]; i += 1
                    _ = ctx.moveTo(x, y)
                    for _ in 1..<max(count, 1) where count > 1 {
                        let lx = segs[i]; i += 1
                        let ly = segs[i]; i += 1
                        _ = ctx.lineTo(lx, ly)
                    }
                }
            }
        }
        else {
            while i < segs.count {
                let x0 = segs[i]; i += 1
                let y0 = segs[i]; i += 1
                let x1 = segs[i]; i += 1
                let y1 = segs[i]; i += 1
                _ = ctx.moveTo(x0, y0)
                if curveness > 0 {
                    let x2 = (x0 + x1) / 2 - (y0 - y1) * curveness
                    let y2 = (y0 + y1) / 2 - (x1 - x0) * curveness
                    _ = ctx.quadraticCurveTo(x2, y2, x1, y1)
                }
                else {
                    _ = ctx.lineTo(x1, y1)
                }
            }
        }
        // DEVIATION: `if (this.incremental) { this._off = i; this.notClear = true; }` — inert here
        //   (`incremental == 0` in the driver), so `_off` stays 0 and the full range re-draws.
        if self.incremental != 0 {
            self._off = i
            self.notClear = true
        }
    }

    // upstream: findDataIndex(x, y) — walk the segs; return the datum index whose stroke contains (x, y).
    //   `x`/`y` are in LOCAL coords (see `contain`).
    public func findDataIndex(_ x: Double, _ y: Double) -> Int {
        let shape = (self.shape as? LargeLinesPathShape) ?? LargeLinesPathShape()
        let segs = shape.segs
        let curveness = shape.curveness
        let lineWidth = self.pathStyle.lineWidth ?? 0

        if shape.polyline {
            var dataIndex = 0
            var i = 0
            while i < segs.count {
                let count = Int(segs[i]); i += 1
                if count > 0 {
                    // FIDELITY: upstream reads x0/y0 ONCE and holds them fixed for every k
                    //   (LargeLineDraw.ts:146-154) — each test is the chord from the polyline's FIRST
                    //   vertex to the k-th vertex (p0->p1, p0->p2, ...), NOT consecutive segments.
                    let x0 = segs[i]; i += 1
                    let y0 = segs[i]; i += 1
                    for _ in 1..<max(count, 1) where count > 1 {
                        let x1 = segs[i]; i += 1
                        let y1 = segs[i]; i += 1
                        if line.containStroke(x0, y0, x1, y1, lineWidth, x, y) {
                            return dataIndex
                        }
                    }
                }
                dataIndex += 1
            }
        }
        else {
            var dataIndex = 0
            var i = 0
            while i < segs.count {
                let x0 = segs[i]; i += 1
                let y0 = segs[i]; i += 1
                let x1 = segs[i]; i += 1
                let y1 = segs[i]; i += 1
                if curveness > 0 {
                    let x2 = (x0 + x1) / 2 - (y0 - y1) * curveness
                    let y2 = (y0 + y1) / 2 - (x1 - x0) * curveness
                    if quadratic.containStroke(x0, y0, x2, y2, x1, y1, lineWidth, x, y) {
                        return dataIndex
                    }
                }
                else {
                    if line.containStroke(x0, y0, x1, y1, lineWidth, x, y) {
                        return dataIndex
                    }
                }
                dataIndex += 1
            }
        }

        return -1
    }

    // upstream: contain(x, y) — hit-test in local coords via `findDataIndex`, caching hoverDataIdx.
    public override func contain(_ x: Double, _ y: Double) -> Bool {
        let localPos = self.transformCoordToLocal(x, y)
        let lx = localPos[0]
        let ly = localPos[1]
        if let rect = self.getBoundingRect(), rect.contain(lx, ly) {
            // Cache found data index.
            let dataIdx = self.findDataIndex(lx, ly)
            self.hoverDataIdx = dataIdx
            return dataIdx >= 0
        }
        self.hoverDataIdx = -1
        return false
    }

    // upstream: getBoundingRect() — ignore stroke; derive from the packed segs' point extents.
    public override func getBoundingRect() -> BoundingRect? {
        if let rect = self._largeRect { return rect }
        let shape = (self.shape as? LargeLinesPathShape) ?? LargeLinesPathShape()
        let points = shape.segs
        var minX = Double.infinity
        var minY = Double.infinity
        var maxX = -Double.infinity
        var maxY = -Double.infinity
        var i = 0
        while i + 1 < points.count {
            let x = points[i]; i += 1
            let y = points[i]; i += 1
            minX = Swift.min(x, minX)
            maxX = Swift.max(x, maxX)
            minY = Swift.min(y, minY)
            maxY = Swift.max(y, maxY)
        }
        // FIDELITY: upstream constructs `new graphic.BoundingRect(minX, minY, maxX, maxY)` — it passes
        //   the max coords into the (x, y, width, height) constructor verbatim (an upstream quirk).
        //   Mirror it exactly so the port diffs cleanly against the .ts.
        let rect = BoundingRect(minX, minY, maxX, maxY)
        self._largeRect = rect
        return rect
    }

    // Invalidate the cached bounding rect when the shape (segs) changes.
    public override func dirtyShape() {
        self._largeRect = nil
        super.dirtyShape()
    }
}

// upstream: class LargeLineDraw implements ILineDraw  (ILineDraw not ported — plain class here)
public final class LargeLineDraw {

    // upstream: group = new graphic.Group();
    public let group = Group()

    // upstream: private _newAdded: LargeLinesPath[];
    private var _newAdded: [LargeLinesPath] = []

    public init() {}

    // upstream: updateData(data) — one path for the whole series' packed `linesPoints` layout.
    public func updateData(_ data: SeriesData) {
        self._clear()

        let lineEl = self._create()
        var shape = (lineEl.shape as? LargeLinesPathShape) ?? LargeLinesPathShape()
        shape.segs = (data.getLayout("linesPoints") as? [Double]) ?? []
        _ = lineEl.setShape(shape)

        self._setCommon(lineEl, data)
    }

    // upstream: incrementalPrepareUpdate(data) { this.group.removeAll(); this._clear(); }
    public func incrementalPrepareUpdate(_ data: SeriesData) {
        _ = self.group.removeAll()
        self._clear()
    }

    // upstream: incrementalUpdate(taskParams, data, incrementalId) — merge into the last-added path
    //   while its segs stay under 2e4, else start a fresh path for this range.
    public func incrementalUpdate(
        _ taskParams: StageHandlerProgressParams,
        _ data: SeriesData,
        _ incrementalId: Int
    ) {
        let lastAdded = self._newAdded.first
        let linePoints = (data.getLayout("linesPoints") as? [Double]) ?? []

        let oldSegs = lastAdded.flatMap { ($0.shape as? LargeLinesPathShape)?.segs }

        // Merging the exists. Each element has 1e4 points.
        // Consider the performance balance between too much elements and too much points in one shape
        // (may affect hover optimization)
        if let lastAdded = lastAdded, let oldSegs = oldSegs, oldSegs.count < 20000 {
            // Concat two array (upstream: Float32Array set + set-at-offset → [Double] append §1).
            var newSegs = oldSegs
            newSegs.append(contentsOf: linePoints)
            var shape = (lastAdded.shape as? LargeLinesPathShape) ?? LargeLinesPathShape()
            shape.segs = newSegs
            _ = lastAdded.setShape(shape)
        }
        else {
            // Clear
            self._newAdded = []

            let lineEl = self._create()
            lineEl.incremental = Double(incrementalId)
            var shape = (lineEl.shape as? LargeLinesPathShape) ?? LargeLinesPathShape()
            shape.segs = linePoints
            _ = lineEl.setShape(shape)
            self._setCommon(lineEl, data)
            lineEl.__startIndex = Int(taskParams.start)
        }
    }

    // upstream: @override remove() { this._clear(); }
    public func remove() {
        self._clear()
    }

    // upstream: eachRendered(cb) { this._newAdded[0] && cb(this._newAdded[0]); }
    @discardableResult
    public func eachRendered(_ cb: (Element) -> Bool?) -> Bool? {
        if let first = self._newAdded.first {
            return cb(first)
        }
        return nil
    }

    // upstream: private _create()
    @discardableResult
    private func _create() -> LargeLinesPath {
        let lineEl = LargeLinesPath()
        lineEl.cursor = "default"
        lineEl.ignoreCoarsePointer = true
        self._newAdded.append(lineEl)
        _ = self.group.add(lineEl)
        return lineEl
    }

    // upstream: private _setCommon(lineEl, data, isIncremental?)
    private func _setCommon(_ lineEl: LargeLinesPath, _ data: SeriesData, _ isIncremental: Bool = false) {
        let hostModel = data.hostModel

        // upstream: lineEl.setShape({ polyline: hostModel.get('polyline'),
        //                             curveness: hostModel.get(['lineStyle', 'curveness']) });
        var shape = (lineEl.shape as? LargeLinesPathShape) ?? LargeLinesPathShape()
        shape.polyline = largeLinesTruthy(hostModel?.get("polyline"))
        shape.curveness = largeLinesToNumber(hostModel?.get(["lineStyle", "curveness"]))
        _ = lineEl.setShape(shape)

        // upstream: lineEl.useStyle(hostModel.getModel('lineStyle').getLineStyle());
        let lineStyle = hostModel?.getModel("lineStyle").getLineStyle() ?? [:]
        lineEl.useStyle(barStyleFromDict(lineStyle))
        // upstream: lineEl.style.strokeNoScale = true;
        lineEl.pathStyle.strokeNoScale = true

        // upstream: const style = data.getVisual('style');
        //           if (style && style.stroke) { lineEl.setStyle('stroke', style.stroke); }
        let style = data.getVisual("style") as? [String: Any]
        if let stroke = zrPaintFromStyleValue(style?["stroke"]) {
            lineEl.pathStyle.stroke = stroke
        }
        // upstream: lineEl.setStyle('fill', null);
        //   TRAP: setStyle('fill', nil) is dropped by extendPathStyle → clear the field directly.
        lineEl.pathStyle.fill = nil

        // upstream: const ecData = getECData(lineEl);
        //   Enable tooltip. PENDING May have performance issue when path is extremely large.
        let ecData = innerStore.getECData(lineEl)
        ecData.seriesIndex = (hostModel as? SeriesModel)?.seriesIndex
        _ = lineEl.on("mousemove", { [weak lineEl] _, _ in
            guard let lineEl = lineEl else { return nil }
            let hostECData = innerStore.getECData(lineEl)
            hostECData.dataIndex = nil
            let dataIndex = lineEl.hoverDataIdx
            if dataIndex > 0 {
                // Provide dataIndex for tooltip.
                hostECData.dataIndex = Double(dataIndex + lineEl.__startIndex)
            }
            return nil
        })
    }

    // upstream: private _clear() { this._newAdded = []; this.group.removeAll(); }
    private func _clear() {
        self._newAdded = []
        _ = self.group.removeAll()
    }
}

// ---- STATIC-port helpers (not upstream functions) --------------------------------------------------
//   Mirror LinesView's `linesTruthy` / `linesToNumber` (INT-vs-DOUBLE-safe reads of dynamic options).

// JS truthiness for the `polyline` option (`hostModel.get('polyline')` fed to a boolean field).
private func largeLinesTruthy(_ v: Any?) -> Bool {
    guard let v = v else { return false }
    if let b = v as? Bool { return b }
    if let i = v as? Int { return i != 0 }
    if let d = v as? Double { return d != 0 }
    if let n = v as? NSNumber { return n.doubleValue != 0 }
    if let s = v as? String { return !s.isEmpty }
    return true
}

// INT-vs-DOUBLE-safe numeric coercion for `curveness` (may arrive as a bare Int/Double/NSNumber);
//   a missing / non-numeric value yields 0 (upstream's undefined curveness → falsy `curveness > 0`).
private func largeLinesToNumber(_ v: Any?) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return 0
}
