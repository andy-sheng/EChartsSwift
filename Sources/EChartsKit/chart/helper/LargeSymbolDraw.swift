// Ported from echarts/src/chart/helper/LargeSymbolDraw.ts — keep in sync with upstream.
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

// PORT SCOPE (large-mode fast path): a scatter/effectScatter series with `large: true` (past
//   `largeThreshold`) is drawn as ONE `LargeSymbolPath` whose `buildPath` iterates the packed
//   `points` array and re-emits the symbol geometry for every datum — instead of one `Symbol`
//   Group per point (SymbolDraw). This is the performance path for thousands of points.
//
// DEVIATIONS (documented):
//   - The canvas `fillRect` boost (`ctx && size[0] < BOOST_SIZE_THRESHOLD` → `afterBrush`) is a
//     CanvasRenderingContext2D-only optimization; our renderer draws through `PathProxy`, so the
//     boost branch never activates (there is no canvas `ctx` here). Every datum is emitted via the
//     `symbolProxy.buildPath` loop (the non-boost path), which is the faithful geometry. The
//     `_off`/`notClear` progressive cursor + `beforeBrush(reset)` are kept for provenance but stay
//     inert (the driver has no incremental pipeline: `incremental == 0`), so the full point
//     range is drawn in ONE pass — a deliberate deviation from the progressive `incrementalUpdate`.
//   - `incrementalPrepareUpdate` / `incrementalUpdate` / `eachRendered` are ported (single-pass
//     semantics) so the ISymbolDraw surface stays complete, but the Scheduler task graph that would
//     call them is not ported (sub-project C).

// upstream: const BOOST_SIZE_THRESHOLD = 4;
private let BOOST_SIZE_THRESHOLD: Double = 4

// upstream: class LargeSymbolPathShape { points: ArrayLike<number>; size: number[]; }
//   The packed points are `[x0, y0, x1, y1, ...]` (upstream a Float32Array; here a [Double]).
public struct LargeSymbolPathShape: PathShape {
    public var points: [Double] = []
    public var size: [Double] = [0, 0]
    public init() {}
    // points/size are not tweened (the whole shape is replaced via setShape) → no keyed animation.
}

// upstream: class LargeSymbolPath extends graphic.Path<LargeSymbolPathProps>
//   A single Path that paints EVERY point of the series (one buildPath loop over the packed array).
public final class LargeSymbolPath: Path {

    // upstream: symbolProxy: ECSymbol — the reusable symbol whose buildPath emits each point's shape.
    //   Stored as the concrete `Path` (its shape is mutated per-point and re-built into our PathProxy).
    public var symbolProxy: Path?
    // Whether the proxy symbol is an "empty" (hollow) symbol — mirrors ECSymbol.__isEmptyBrush,
    //   consumed by `setColor` (empty → stroke, else → fill).
    private var _isEmptyBrush: Bool = false
    // The proxy symbol's type ("line" strokes rather than fills — see `setColor`).
    private var _proxySymbolType: String = ""

    // upstream: softClipShape: CoordinateSystemClipArea — a soft clip (points outside are skipped).
    public var softClipShape: SymbolClipShape?

    // upstream: startIndex / endIndex — the [start, end) datum range this path covers (progressive).
    public var startIndex: Int?
    public var endIndex: Int?

    // upstream: hoverDataIdx — the datum index found by the last `contain` hit-test (for tooltip).
    public var hoverDataIdx: Int = -1

    // upstream: notClear / _off — progressive draw cursor (inert here, see the deviation note).
    //   `notClear` is inherited from Displayable (the incremental-layer keep-alive flag).
    private var _off: Int = 0

    // Our own bounding-rect cache (the base `_rect` is internal to ZRenderKit; upstream caches on
    //   `this._rect` — we mirror the "ignore stroke, derive from points+size" rect here).
    private var _largeRect: BoundingRect?

    public override init(_ opts: PathProps? = nil) {
        super.init(opts)
        // upstream leaves `type` as 'path'; name it distinctively for debug / hit-test lookup.
        self.type = "largeSymbol"
    }

    // upstream: getDefaultShape() { return new LargeSymbolPathShape(); }
    public override func getDefaultShape() -> PathShape {
        return LargeSymbolPathShape()
    }

    // Configure the proxy symbol (from `data.getVisual('symbol')`). Sets the type / empty flag used
    //   by `buildPath` + `setColor`. (Upstream assigns `symbolProxy` + borrows its `setColor`.)
    func setSymbolProxy(_ proxy: Path, isEmptyBrush: Bool, symbolType: String) {
        self.symbolProxy = proxy
        self._isEmptyBrush = isEmptyBrush
        self._proxySymbolType = symbolType
    }

    // upstream: reset() { this.notClear = false; this._off = 0; }
    func reset() {
        self.notClear = false
        self._off = 0
    }

    // upstream: buildPath(path, shape) — the per-point loop. `canBoost`/afterBrush (canvas fillRect)
    //   is omitted (no canvas ctx here); we always take the symbolProxy.buildPath loop.
    public override func buildPath(_ path: PathProxy, _ shapeIn: PathShape, _ inBatch: Bool) {
        guard let shape = shapeIn as? LargeSymbolPathShape else { return }
        let points = shape.points
        let size = shape.size
        guard size.count >= 2, let symbolProxy = self.symbolProxy,
              var proxyShape = symbolProxy.shape else { return }

        let softClipShape = self.softClipShape

        var i = self._off
        // Each datum contributes an (x, y) pair — iterate two-at-a-time.
        while i + 1 < points.count {
            let x = points[i]; i += 1
            let y = points[i]; i += 1

            if x.isNaN || y.isNaN {
                continue
            }
            if let clip = softClipShape, !clip.contain(x, y) {
                continue
            }

            // upstream mutates `symbolProxyShape.x/.y/.width/.height` in place; the value-type shape
            //   exposes those numeric fields via keyed animationSet (SymbolShape / Rect / Circle …).
            proxyShape.animationSet("x", x - size[0] / 2)
            proxyShape.animationSet("y", y - size[1] / 2)
            proxyShape.animationSet("width", size[0])
            proxyShape.animationSet("height", size[1])

            symbolProxy.buildPath(path, proxyShape, true)
        }
        // DEVIATION: `if (this.incremental) { this._off = i; this.notClear = true; }` — inert here
        //   (`incremental == 0` in the driver), so `_off` stays 0 and the full range re-draws.
    }

    // upstream: setColor (borrowed from symbolProxy). Runs with `this` == the LargeSymbolPath, so it
    //   paints THIS path's style (empty → stroke + inner fill; 'line' → stroke; else → fill).
    public func setColor(_ color: ZRenderKit.ZRColor, _ innerColor: ZRenderKit.ZRColor? = nil) {
        if self.type == "image" { return }
        if self._isEmptyBrush {
            self.pathStyle.stroke = color
            self.pathStyle.fill = innerColor ?? .string("#fff")
            self.pathStyle.lineWidth = 2
        }
        else if self._proxySymbolType == "line" {
            self.pathStyle.stroke = color
        }
        else {
            self.pathStyle.fill = color
        }
        self.markRedraw()
    }

    // upstream: findDataIndex(x, y) — treat each point as a `max(size, 4)` rect; top-down traverse.
    //   `x`/`y` are in LOCAL coords (see `contain`).
    public func findDataIndex(_ x: Double, _ y: Double) -> Int {
        guard let shape = self.shape as? LargeSymbolPathShape else { return -1 }
        let points = shape.points
        let size = shape.size
        guard size.count >= 2 else { return -1 }

        let w = Swift.max(size[0], 4)
        let h = Swift.max(size[1], 4)

        // Treat each element as a rect; traverse top-down (later points drawn on top win).
        var idx = points.count / 2 - 1
        while idx >= 0 {
            let i = idx * 2
            let x0 = points[i] - w / 2
            let y0 = points[i + 1] - h / 2
            if x >= x0 && y >= y0 && x <= x0 + w && y <= y0 + h {
                return idx
            }
            idx -= 1
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

    // upstream: getBoundingRect() — ignore stroke; derive [minX-w/2, minY-h/2, ...] from points+size.
    public override func getBoundingRect() -> BoundingRect? {
        if let rect = self._largeRect { return rect }
        guard let shape = self.shape as? LargeSymbolPathShape, shape.size.count >= 2 else {
            return nil
        }
        let points = shape.points
        let w = shape.size[0]
        let h = shape.size[1]
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
        let rect = BoundingRect(minX - w / 2, minY - h / 2, maxX - minX + w, maxY - minY + h)
        self._largeRect = rect
        return rect
    }

    // Invalidate the cached bounding rect when the shape (points/size) changes.
    public override func dirtyShape() {
        self._largeRect = nil
        super.dirtyShape()
    }
}

// upstream: class LargeSymbolDraw implements ISymbolDraw
public final class LargeSymbolDraw {

    public let group = Group()

    // upstream: private _newAdded: LargeSymbolPath[]; private _data: SeriesData;
    private var _newAdded: [LargeSymbolPath] = []
    private var _data: SeriesData?

    public init() {}

    // upstream: updateData(data, opt?) — one path for the whole series' packed `points` layout.
    public func updateData(_ data: SeriesData, _ opt: SymbolDrawUpdateOpt? = nil) {
        self._clear()
        self._data = data

        let symbolEl = self._create()
        var shape = LargeSymbolPathShape()
        shape.points = (data.getLayout("points") as? [Double]) ?? []
        symbolEl.setShape(shape)
        self._setCommon(symbolEl, data, opt)
    }

    // upstream: updateLayout(opt) — re-point every child path from the latest `points` layout.
    //   The port has no Float32Array views over sub-ranges; every child shares the full array
    //   (single-path, non-progressive), so re-set the whole `points` on each child.
    public func updateLayout(_ opt: SymbolDrawUpdateOpt? = nil) {
        guard let data = self._data else { return }
        let points = (data.getLayout("points") as? [Double]) ?? []
        _ = self.group.eachChild { child, _ in
            guard let child = child as? LargeSymbolPath else { return }
            var shape = (child.shape as? LargeSymbolPathShape) ?? LargeSymbolPathShape()
            shape.points = points
            child.setShape(shape)
            child.reset()
            _ = child.stopAnimation()
        }
    }

    // upstream: incrementalPrepareUpdate(data) { this._clear(); }
    public func incrementalPrepareUpdate(_ data: SeriesData) {
        self._clear()
    }

    // upstream: incrementalUpdate(...) — the driver has no task graph, so this renders the given
    //   range as a single path in one pass (the merge-into-lastAdded / Float32Array split is dropped).
    public func incrementalUpdate(_ data: SeriesData, _ start: Int, _ end: Int, _ opt: SymbolDrawUpdateOpt? = nil) {
        let symbolEl = self._create()
        symbolEl.startIndex = start
        symbolEl.endIndex = end
        var shape = LargeSymbolPathShape()
        shape.points = (data.getLayout("points") as? [Double]) ?? []
        symbolEl.setShape(shape)
        self._setCommon(symbolEl, data, opt)
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
    private func _create() -> LargeSymbolPath {
        let symbolEl = LargeSymbolPath()
        symbolEl.cursor = "default"
        symbolEl.ignoreCoarsePointer = true
        _ = self.group.add(symbolEl)
        self._newAdded.append(symbolEl)
        return symbolEl
    }

    // upstream: private _setCommon(symbolEl, data, opt)
    private func _setCommon(_ symbolEl: LargeSymbolPath, _ data: SeriesData, _ opt: SymbolDrawUpdateOpt?) {
        let hostModel = data.hostModel

        // upstream: const size = data.getVisual('symbolSize');
        //           symbolEl.setShape('size', size instanceof Array ? size : [size, size]);
        let sizeVisual = data.getVisual("symbolSize")
        let size = largeNormalizeSize(sizeVisual)
        var shape = (symbolEl.shape as? LargeSymbolPathShape) ?? LargeSymbolPathShape()
        shape.size = size
        symbolEl.setShape(shape)

        // upstream: symbolEl.softClipShape = opt.clipShape || null;
        symbolEl.softClipShape = opt?.clipShape

        // upstream: symbolEl.symbolProxy = createSymbol(data.getVisual('symbol'), 0, 0, 0, 0);
        //           symbolEl.setColor = symbolEl.symbolProxy.setColor;
        let symbolType = (data.getVisual("symbol") as? String) ?? "circle"
        let proxyEC = symbol.createSymbol(symbolType, 0, 0, 0, 0)
        if let proxyPath = proxyEC as? Path {
            symbolEl.setSymbolProxy(
                proxyPath,
                isEmptyBrush: proxyEC.__isEmptyBrush,
                symbolType: symbolType.hasPrefix("empty")
                    ? String(symbolType.dropFirst(5)).prefix(1).lowercased() + String(symbolType.dropFirst(6))
                    : symbolType
            )
        }

        // upstream: const extrudeShadow = symbolEl.shape.size[0] < BOOST_SIZE_THRESHOLD;
        //   symbolEl.useStyle(itemStyle.getItemStyle(extrudeShadow ? ['color','shadowBlur','shadowColor'] : ['color']));
        //   (the excluded keys are EXCLUDES — the fill color comes from the visual palette below.)
        let extrudeShadow = size[0] < BOOST_SIZE_THRESHOLD
        let itemStyleModel = hostModel?.getModel("itemStyle")
        let excludes = extrudeShadow ? ["color", "shadowBlur", "shadowColor"] : ["color"]
        let itemStyleDict = itemStyleModel?.getItemStyle(excludes, nil) ?? [:]
        symbolEl.useStyle(barStyleFromDict(itemStyleDict))
        // The fill default ('#000') is layered by createStyle; the palette color (below) overrides it.

        // upstream: const globalStyle = data.getVisual('style');
        //           const visualColor = globalStyle && globalStyle.fill;
        //           if (visualColor) { symbolEl.setColor(visualColor); }
        let globalStyle = data.getVisual("style") as? [String: Any]
        if let vc = symbolColorString(globalStyle?["fill"]) {
            symbolEl.setColor(.string(vc), nil)
        }

        // upstream: enable tooltip — seriesIndex on the path; mousemove maps hoverDataIdx → dataIndex.
        let ecData = innerStore.getECData(symbolEl)
        ecData.seriesIndex = (hostModel as? SeriesModel)?.seriesIndex
        _ = symbolEl.on("mousemove", { [weak symbolEl] _, _ in
            guard let symbolEl = symbolEl else { return nil }
            let hostECData = innerStore.getECData(symbolEl)
            hostECData.dataIndex = nil
            let dataIndex = symbolEl.hoverDataIdx
            if dataIndex >= 0 {
                // Provide dataIndex for tooltip.
                hostECData.dataIndex = Double(dataIndex + (symbolEl.startIndex ?? 0))
            }
            return nil
        })
    }

    // upstream: remove() { this._clear(); }
    public func remove() {
        self._clear()
    }

    // upstream: private _clear() { this._newAdded = []; this.group.removeAll(); }
    private func _clear() {
        self._newAdded = []
        _ = self.group.removeAll()
    }
}

// upstream: `size instanceof Array ? size : [size, size]`, with normalizeSymbolSize semantics.
func largeNormalizeSize(_ sizeVisual: Any?) -> [Double] {
    if let arr = sizeVisual as? [Any] {
        let (w, h) = symbol.normalizeSymbolSize(arr)
        return [w, h]
    }
    let (w, h) = symbol.normalizeSymbolSize(sizeVisual ?? 10.0)
    return [w, h]
}
