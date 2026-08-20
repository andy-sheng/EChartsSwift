// official-circle-packing-with-d3 — replica of https://echarts.apache.org/examples/zh/editor.html?c=circle-packing-with-d3
// title: Circle Packing with d3 / titleCN: 基于 d3 的圆形包络图
// The ECharts option-doc statistics tree (`option.series.line.itemStyle…`, one node per documented
// option key, `$count` = how often it appears in the wild) drawn as a CIRCLE PACKING: a `custom` series
// whose `renderItem` returns one `circle` per node, laid out by **d3-hierarchy** (`d3.stratify()` →
// `.sum()` → `.sort()` → `d3.pack().size([w-2, h-2]).padding(3)`), coloured by depth through a
// continuous `visualMap`, with the leaf's own key as an inside `textContent` (CamelCase broken onto
// separate lines, truncated to the circle).
//
// DEVIATIONS from the official source:
//   - DATA INLINED. Upstream fetches the tree with `$.get(ROOT_PATH + '/data/asset/data/option-view.json')`
//     inside a `$.when(...).done(function (res) { run(res[0]); })`. The page has no network, so the asset
//     (assets/data/option-view.json, the upstream file byte-for-byte) is spliced into the web pane as
//     `const rawData = {...}` and `run(rawData)` is called at the top level. Everything below that —
//     `run` / `prepareData` / `initChart` / `renderItem` / the drilldown handlers — is VERBATIM.
//   - CDN SCRIPT VENDORED. The example's second deferred is `$.getScript(CDN_PATH +
//     'd3-hierarchy@2.0.0/dist/d3-hierarchy.min.js')` — `d3.stratify` / `d3.pack` ARE the layout. The
//     dist is mirrored into assets/lib/d3-hierarchy.js (the same version, un-minified) and spliced
//     verbatim into the head of webOptionJS; its UMD wrapper publishes the same `d3` global the CDN
//     script does, so the web pane runs the REAL d3-hierarchy.
//   - NATIVE PANE: d3-hierarchy IS PORTED (below), not dropped. `renderItem` is the chart here, and
//     EChartsKit carries a Swift `CustomSeriesRenderItem` on the series option under "renderItem"
//     (CustomView resolves `getRenderItem() ?? getCustomSeries(subType)` — omitting it would NOT leave an
//     empty series but silently draw Demos/custom-basic.swift's globally-registered "custom" bar
//     renderItem against this data, a wrong chart). So `stratify` / `sum` / `sort` / `pack` /
//     `packEnclose` / `packSiblings`'s Welzl enclose are ported from the vendored d3-hierarchy 2.0.0
//     source, statement for statement, and both panes draw the same packing.
//     `params.context` is reference-typed in EChartsKit, so the upstream "lay out once per setOption,
//     cache it on context" lifecycle is preserved rather than leaking a layout across updates.
//   - INTERACTION DROPPED ON THE NATIVE PANE ONLY. Upstream's `myChart.on('click', {seriesIndex: 0}, ...)`
//     (drill into the clicked node) and `myChart.getZr().on('click', ...)` (reset on blank click) stay
//     VERBATIM in the web pane. `EChartsDemoChart` now exposes chart-level events but not the underlying
//     zrender blank-area event needed by the paired reset handler, so the native demo still shows the
//     initial, un-drilled packing. This limitation is independent of the update-animation path above.
//   - The root row has no `$count`, i.e. `value: undefined` in JS; Swift carries `NSNull()` so the
//     dataset's object-row dimension detection still sees all four keys (id / value / depth / index).
import Foundation
import EChartsKit

// MARK: - assets (the upstream /data/asset/data/option-view.json + the vendored CDN script)

/// The raw asset text — spliced into the web pane as `const rawData = …`. A read failure degrades to a
/// single empty node (a near-blank chart) rather than crashing.
private let circlePackingRawJSON: String = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/data/option-view.json")
    return (try? String(contentsOf: url, encoding: .utf8)) ?? "{}"
}()

/// d3-hierarchy@2.0.0 (the exact dist the example `$.getScript`s, un-minified), spliced into the page.
private let circlePackingD3JS: String = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/lib/d3-hierarchy.js")
    return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
}()

// MARK: - the asset, parsed IN KEY ORDER

// `prepareData`'s `for (var key in source)` walks the JSON's own key order, and its `if (maxDepth > 5)
// return;` guard is STATEFUL — the first branch to reach depth 6 truncates every node visited after it.
// Key order therefore decides WHICH nodes exist (527 in JSON order vs 456 in sorted order), and
// JSONSerialization's unordered dictionary would silently produce a different chart from the web pane.
// So the asset is parsed by a tiny order-preserving scanner. The file's shape is trivial: nested objects
// whose only scalar is `"$count": <int>`.
private struct CirclePackingRawNode {
    var count: Double?                                       // `$count`, absent on the root
    var children: [(key: String, node: CirclePackingRawNode)] // in JSON order
}

private struct CirclePackingJSONScanner {
    let bytes: [UInt8]
    var i = 0

    init(_ text: String) { bytes = Array(text.utf8) }

    mutating func skipWS() {
        while i < bytes.count {
            let c = bytes[i]
            if c == 0x20 || c == 0x09 || c == 0x0a || c == 0x0d { i += 1 } else { break }
        }
    }

    /// A JSON string. The asset's keys are plain ASCII identifiers; an escape aborts the parse (the
    /// caller then falls back), which is safer than half-decoding one.
    mutating func parseString() -> String? {
        guard i < bytes.count, bytes[i] == 0x22 else { return nil }   // "
        i += 1
        let start = i
        while i < bytes.count, bytes[i] != 0x22 {
            if bytes[i] == 0x5c { return nil }                        // backslash: not expected here
            i += 1
        }
        guard i < bytes.count else { return nil }
        let s = String(decoding: bytes[start..<i], as: UTF8.self)
        i += 1
        return s
    }

    mutating func parseNumber() -> Double? {
        let start = i
        while i < bytes.count {
            let c = bytes[i]
            // digits, '-', '+', '.', 'e', 'E'
            if (c >= 0x30 && c <= 0x39) || c == 0x2d || c == 0x2b || c == 0x2e || c == 0x65 || c == 0x45 {
                i += 1
            } else { break }
        }
        guard i > start else { return nil }
        return Double(String(decoding: bytes[start..<i], as: UTF8.self))
    }

    mutating func parseObject() -> CirclePackingRawNode? {
        skipWS()
        guard i < bytes.count, bytes[i] == 0x7b else { return nil }   // {
        i += 1
        var node = CirclePackingRawNode(count: nil, children: [])
        skipWS()
        if i < bytes.count, bytes[i] == 0x7d { i += 1; return node }  // }
        while true {
            skipWS()
            guard let key = parseString() else { return nil }
            skipWS()
            guard i < bytes.count, bytes[i] == 0x3a else { return nil }  // :
            i += 1
            skipWS()
            if i < bytes.count, bytes[i] == 0x7b {
                guard let child = parseObject() else { return nil }
                // `!key.match(/^\$/)` — a `$`-prefixed key is never a child (there are none of object
                // type in the asset; the guard mirrors prepareData anyway).
                if !key.hasPrefix("$") { node.children.append((key, child)) }
            } else {
                guard let num = parseNumber() else { return nil }
                if key == "$count" { node.count = num }
            }
            skipWS()
            if i < bytes.count, bytes[i] == 0x2c { i += 1; continue }    // ,
            if i < bytes.count, bytes[i] == 0x7d { i += 1; break }       // }
            return nil
        }
        return node
    }
}

private let circlePackingRawTree: CirclePackingRawNode = {
    var scanner = CirclePackingJSONScanner(circlePackingRawJSON)
    return scanner.parseObject() ?? CirclePackingRawNode(count: nil, children: [])
}()

// MARK: - `prepareData`, ported

/// Upstream `prepareData(rawData)`: a depth-first flatten into `{ id, value, depth, index }` rows, the
/// path (`option.series.line`) as the id, capped by the `maxDepth > 5` guard.
private let circlePackingPrepared: (seriesData: [[String: Any]], maxDepth: Double) = {
    var seriesData: [[String: Any]] = []
    var maxDepth = 0

    func convert(_ source: CirclePackingRawNode, _ basePath: String, _ depth: Int) {
        if maxDepth > 5 { return }
        maxDepth = max(depth, maxDepth)

        seriesData.append([
            "id": basePath,
            // `source.$count` — undefined on the root; NSNull keeps the key (and the dimension) present.
            "value": source.count.map { $0 as Any } ?? NSNull(),
            "depth": Double(depth),
            "index": Double(seriesData.count)
        ] as [String: Any])

        for (key, child) in source.children {
            convert(child, basePath + "." + key, depth + 1)
        }
    }

    convert(circlePackingRawTree, "option", 0)
    return (seriesData, Double(maxDepth))
}()

private let circlePackingSeriesData: [[String: Any]] = circlePackingPrepared.seriesData
private let circlePackingMaxDepth: Double = circlePackingPrepared.maxDepth

// MARK: - d3-hierarchy 2.0.0, ported (stratify + sum + sort + pack)

/// d3's `Node`: the hierarchy node the layout mutates (`x` / `y` / `r`). A class — d3 threads references
/// through the front-chain and the enclose basis.
private final class D3Node {
    let id: String
    let dataIndex: Int          // `data.index` — the datum's row index (what `focus` collects)
    let dataValue: Double?      // `data.value`
    weak var parent: D3Node?
    var children: [D3Node]?
    var depth: Int = 0
    var value: Double = 0
    var x: Double = 0
    var y: Double = 0
    var r: Double = 0

    init(id: String, dataIndex: Int, dataValue: Double?) {
        self.id = id
        self.dataIndex = dataIndex
        self.dataValue = dataValue
    }
}

// node_eachBefore / node_eachAfter — pre-order and post-order, iterative like d3's.
private func d3EachBefore(_ root: D3Node, _ callback: (D3Node) -> Void) {
    var nodes: [D3Node] = [root]
    while let node = nodes.popLast() {
        callback(node)
        if let children = node.children {
            for child in children.reversed() { nodes.append(child) }
        }
    }
}

private func d3EachAfter(_ root: D3Node, _ callback: (D3Node) -> Void) {
    var nodes: [D3Node] = [root]
    var next: [D3Node] = []
    while let node = nodes.popLast() {
        next.append(node)
        if let children = node.children { nodes.append(contentsOf: children) }
    }
    while let node = next.popLast() { callback(node) }
}

/// node_descendants — `Array.from(this)`, i.e. d3's breadth-first iterator.
private func d3Descendants(_ root: D3Node) -> [D3Node] {
    var out: [D3Node] = []
    var queue: [D3Node] = [root]
    var head = 0
    while head < queue.count {
        let node = queue[head]; head += 1
        out.append(node)
        if let children = node.children { queue.append(contentsOf: children) }
    }
    return out
}

/// `d3.stratify().parentId(d => d.id.substring(0, d.id.lastIndexOf('.')))(seriesData)` — the parent of
/// `option.series.line` is `option.series`; the root's `lastIndexOf('.')` is -1, so its parentId is the
/// empty string, which d3 treats as "no parent".
private func circlePackingStratify(_ rows: [[String: Any]]) -> D3Node? {
    var nodes: [D3Node] = []
    var byId: [String: D3Node] = [:]
    nodes.reserveCapacity(rows.count)

    for (i, row) in rows.enumerated() {
        let id = (row["id"] as? String) ?? ""
        let value = row["value"] as? Double
        let node = D3Node(id: id, dataIndex: i, dataValue: value)
        nodes.append(node)
        byId[id] = node
    }

    var root: D3Node?
    for node in nodes {
        guard let dot = node.id.lastIndex(of: ".") else {
            // no '.' → parentId is "" → this is the root.
            if root == nil { root = node }
            continue
        }
        let parentId = String(node.id[node.id.startIndex..<dot])
        if let parent = byId[parentId] {
            if parent.children == nil { parent.children = [node] } else { parent.children!.append(node) }
            node.parent = parent
        } else if root == nil {
            root = node   // upstream throws "missing: <id>"; a truncated tree cannot produce one.
        }
    }

    guard let r = root else { return nil }
    // root.eachBefore(node => node.depth = node.parent.depth + 1)
    d3EachBefore(r) { node in
        node.depth = node.parent.map { $0.depth + 1 } ?? 0
    }
    return r
}

/// node_sum(d => d.value || 0) then node_sort((a, b) => b.value - a.value).
///
/// `Array.prototype.sort` is stable in V8; Swift's `sort` is not, so ties fall back to the original
/// child order — the same permutation JS produces.
private func circlePackingSumAndSort(_ root: D3Node) {
    d3EachAfter(root) { node in
        var sum = node.dataValue ?? 0
        if !sum.isFinite { sum = 0 }
        for child in node.children ?? [] { sum += child.value }
        node.value = sum
    }
    d3EachBefore(root) { node in
        guard let children = node.children else { return }
        node.children = children.enumerated()
            .sorted { a, b in
                if a.element.value != b.element.value { return a.element.value > b.element.value }
                return a.offset < b.offset
            }
            .map { $0.element }
    }
}

// MARK: d3-hierarchy: packEnclose (Welzl) + pack

/// The plain `{x, y, r}` circle d3's enclose basis works with (it only ever READS a node's geometry).
private struct D3Circle {
    var x: Double
    var y: Double
    var r: Double
    init(x: Double, y: Double, r: Double) { self.x = x; self.y = y; self.r = r }
    init(_ n: D3Node) { x = n.x; y = n.y; r = n.r }
}

private func d3EnclosesNot(_ a: D3Circle, _ b: D3Circle) -> Bool {
    let dr = a.r - b.r, dx = b.x - a.x, dy = b.y - a.y
    return dr < 0 || dr * dr < dx * dx + dy * dy
}

private func d3EnclosesWeak(_ a: D3Circle, _ b: D3Circle) -> Bool {
    let dr = a.r - b.r + max(a.r, b.r, 1) * 1e-9, dx = b.x - a.x, dy = b.y - a.y
    return dr > 0 && dr * dr > dx * dx + dy * dy
}

private func d3EnclosesWeakAll(_ a: D3Circle, _ B: [D3Circle]) -> Bool {
    for b in B where !d3EnclosesWeak(a, b) { return false }
    return true
}

private func d3EncloseBasis1(_ a: D3Circle) -> D3Circle { D3Circle(x: a.x, y: a.y, r: a.r) }

private func d3EncloseBasis2(_ a: D3Circle, _ b: D3Circle) -> D3Circle {
    let x1 = a.x, y1 = a.y, r1 = a.r
    let x2 = b.x, y2 = b.y, r2 = b.r
    let x21 = x2 - x1, y21 = y2 - y1, r21 = r2 - r1
    let l = (x21 * x21 + y21 * y21).squareRoot()
    return D3Circle(
        x: (x1 + x2 + x21 / l * r21) / 2,
        y: (y1 + y2 + y21 / l * r21) / 2,
        r: (l + r1 + r2) / 2
    )
}

private func d3EncloseBasis3(_ a: D3Circle, _ b: D3Circle, _ c: D3Circle) -> D3Circle {
    let x1 = a.x, y1 = a.y, r1 = a.r
    let x2 = b.x, y2 = b.y, r2 = b.r
    let x3 = c.x, y3 = c.y, r3 = c.r
    let a2 = x1 - x2
    let a3 = x1 - x3
    let b2 = y1 - y2
    let b3 = y1 - y3
    let c2 = r2 - r1
    let c3 = r3 - r1
    let d1 = x1 * x1 + y1 * y1 - r1 * r1
    let d2 = d1 - x2 * x2 - y2 * y2 + r2 * r2
    let d3 = d1 - x3 * x3 - y3 * y3 + r3 * r3
    let ab = a3 * b2 - a2 * b3
    let xa = (b2 * d3 - b3 * d2) / (ab * 2) - x1
    let xb = (b3 * c2 - b2 * c3) / ab
    let ya = (a3 * d2 - a2 * d3) / (ab * 2) - y1
    let yb = (a2 * c3 - a3 * c2) / ab
    let A = xb * xb + yb * yb - 1
    let B = 2 * (r1 + xa * xb + ya * yb)
    let C = xa * xa + ya * ya - r1 * r1
    let r = -(A != 0 ? (B + (B * B - 4 * A * C).squareRoot()) / (2 * A) : C / B)
    return D3Circle(x: x1 + xa + xb * r, y: y1 + ya + yb * r, r: r)
}

private func d3EncloseBasis(_ B: [D3Circle]) -> D3Circle? {
    switch B.count {
    case 1: return d3EncloseBasis1(B[0])
    case 2: return d3EncloseBasis2(B[0], B[1])
    case 3: return d3EncloseBasis3(B[0], B[1], B[2])
    default: return nil
    }
}

private func d3ExtendBasis(_ B: [D3Circle], _ p: D3Circle) -> [D3Circle] {
    if d3EnclosesWeakAll(p, B) { return [p] }

    for i in 0..<B.count {
        if d3EnclosesNot(p, B[i]) && d3EnclosesWeakAll(d3EncloseBasis2(B[i], p), B) {
            return [B[i], p]
        }
    }

    if B.count >= 2 {
        for i in 0..<(B.count - 1) {
            for j in (i + 1)..<B.count {
                if d3EnclosesNot(d3EncloseBasis2(B[i], B[j]), p)
                    && d3EnclosesNot(d3EncloseBasis2(B[i], p), B[j])
                    && d3EnclosesNot(d3EncloseBasis2(B[j], p), B[i])
                    && d3EnclosesWeakAll(d3EncloseBasis3(B[i], B[j], p), B) {
                    return [B[i], B[j], p]
                }
            }
        }
    }

    // upstream `throw new Error` ("something is very wrong"). Degrade instead of trapping.
    return [p]
}

private func d3Enclose(_ circles: [D3Circle]) -> D3Circle? {
    var cs = circles
    var m = cs.count
    while m > 0 {
        // d3-hierarchy 2.0.0: `array[i] = array[m], array[m] = t` with
        // `i = random() * m-- | 0`. Its `random` is Math.random, so use Swift's system RNG rather
        // than freezing the order across setOption calls; the latter suppresses the official shape
        // update transition by making every floating-point result bit-identical.
        let i = Int.random(in: 0..<m)
        m -= 1
        cs.swapAt(m, min(i, cs.count - 1))
    }

    var i = 0
    let n = cs.count
    var B: [D3Circle] = []
    var e: D3Circle?

    while i < n {
        let p = cs[i]
        if let ee = e, d3EnclosesWeak(ee, p) {
            i += 1
        } else {
            B = d3ExtendBasis(B, p)
            e = d3EncloseBasis(B)
            i = 0
        }
    }
    return e
}

private func d3Place(_ b: D3Node, _ a: D3Node, _ c: D3Node) {
    let dx = b.x - a.x
    let dy = b.y - a.y
    let d2 = dx * dx + dy * dy
    if d2 != 0 {
        var a2 = a.r + c.r; a2 *= a2
        var b2 = b.r + c.r; b2 *= b2
        if a2 > b2 {
            let x = (d2 + b2 - a2) / (2 * d2)
            let y = max(0, b2 / d2 - x * x).squareRoot()
            c.x = b.x - x * dx - y * dy
            c.y = b.y - x * dy + y * dx
        } else {
            let x = (d2 + a2 - b2) / (2 * d2)
            let y = max(0, a2 / d2 - x * x).squareRoot()
            c.x = a.x + x * dx - y * dy
            c.y = a.y + x * dy + y * dx
        }
    } else {
        c.x = a.x + c.r
        c.y = a.y
    }
}

private func d3Intersects(_ a: D3Node, _ b: D3Node) -> Bool {
    let dr = a.r + b.r - 1e-6, dx = b.x - a.x, dy = b.y - a.y
    return dr > 0 && dr * dr > dx * dx + dy * dy
}

/// The front-chain node (`Node$1` upstream): a circle in an intrusive circular doubly-linked list.
private final class D3ChainNode {
    let circle: D3Node
    var next: D3ChainNode!
    var previous: D3ChainNode!
    init(_ circle: D3Node) { self.circle = circle }
}

private func d3Score(_ node: D3ChainNode) -> Double {
    let a = node.circle
    let b = node.next.circle
    let ab = a.r + b.r
    let dx = (a.x * b.r + b.x * a.r) / ab
    let dy = (a.y * b.r + b.y * a.r) / ab
    return dx * dx + dy * dy
}

/// `packEnclose(circles)` — places every circle (mutating x/y) and returns the enclosing radius.
@discardableResult
private func d3PackEnclose(_ circles: [D3Node]) -> Double {
    let n = circles.count
    if n == 0 { return 0 }

    // Place the first circle.
    let a = circles[0]
    a.x = 0; a.y = 0
    if n <= 1 { return a.r }

    // Place the second circle.
    let b0 = circles[1]
    a.x = -b0.r; b0.x = a.r; b0.y = 0
    if n <= 2 { return a.r + b0.r }

    // Place the third circle.
    d3Place(b0, a, circles[2])

    // Initialize the front-chain using the first three circles a, b and c.
    var aNode = D3ChainNode(a)
    var bNode = D3ChainNode(b0)
    let cNode = D3ChainNode(circles[2])
    aNode.next = bNode; cNode.previous = bNode
    bNode.next = aNode; aNode.previous = cNode
    cNode.next = bNode.previous; bNode.previous = cNode
    // (the three lines above transcribe `a.next = c.previous = b; b.next = a.previous = c;
    //  c.next = b.previous = a;` — restate them explicitly to keep the ring unambiguous:)
    aNode.next = bNode; bNode.previous = aNode
    bNode.next = cNode; cNode.previous = bNode
    cNode.next = aNode; aNode.previous = cNode

    // Attempt to place each remaining circle…
    var i = 3
    pack: while i < n {
        d3Place(aNode.circle, bNode.circle, circles[i])
        let c = D3ChainNode(circles[i])

        // Find the closest intersecting circle on the front-chain, if any.
        var j = bNode.next!
        var k = aNode.previous!
        var sj = bNode.circle.r
        var sk = aNode.circle.r
        repeat {
            if sj <= sk {
                if d3Intersects(j.circle, c.circle) {
                    bNode = j; aNode.next = bNode; bNode.previous = aNode
                    continue pack        // upstream `--i; continue pack;` + the loop's `++i`
                }
                sj += j.circle.r
                j = j.next
            } else {
                if d3Intersects(k.circle, c.circle) {
                    aNode = k; aNode.next = bNode; bNode.previous = aNode
                    continue pack
                }
                sk += k.circle.r
                k = k.previous
            }
        } while j !== k.next

        // Success! Insert the new circle c between a and b.
        c.previous = aNode
        c.next = bNode
        aNode.next = c
        bNode.previous = c
        bNode = c

        // Compute the new closest circle pair to the centroid.
        var aa = d3Score(aNode)
        var cursor = c
        while true {
            cursor = cursor.next
            if cursor === bNode { break }
            let ca = d3Score(cursor)
            if ca < aa { aNode = cursor; aa = ca }
        }
        bNode = aNode.next

        i += 1
    }

    // Compute the enclosing circle of the front chain.
    var chain: [D3Circle] = [D3Circle(bNode.circle)]
    var cursor = bNode.next!
    while cursor !== bNode {
        chain.append(D3Circle(cursor.circle))
        cursor = cursor.next
    }
    guard let e = d3Enclose(chain) else { return 0 }

    // Translate the circles to put the enclosing circle around the origin.
    for circle in circles {
        circle.x -= e.x
        circle.y -= e.y
    }
    return e.r
}

/// `radiusLeaf(defaultRadius)` — `node.r = Math.max(0, +Math.sqrt(node.value) || 0)` on leaves.
private func d3RadiusLeaf(_ node: D3Node) {
    guard node.children == nil else { return }
    let r = node.value.squareRoot()
    node.r = max(0, r.isFinite ? r : 0)
}

/// `packChildren(padding, k)`.
private func d3PackChildren(_ node: D3Node, padding: Double, k: Double) {
    guard let children = node.children else { return }
    var r = padding * k
    if !r.isFinite { r = 0 }                      // `|| 0`
    if r != 0 { for child in children { child.r += r } }
    let e = d3PackEnclose(children)
    if r != 0 { for child in children { child.r -= r } }
    node.r = e + r
}

/// `translateChild(k)`.
private func d3TranslateChild(_ node: D3Node, k: Double) {
    node.r *= k
    if let parent = node.parent {
        node.x = parent.x + k * node.x
        node.y = parent.y + k * node.y
    }
}

/// `d3.pack().size([dx, dy]).padding(padding)(root)` — the no-custom-radius branch.
private func d3Pack(_ root: D3Node, dx: Double, dy: Double, padding: Double) {
    root.x = dx / 2
    root.y = dy / 2
    d3EachBefore(root) { d3RadiusLeaf($0) }
    d3EachAfter(root) { d3PackChildren($0, padding: 0, k: 1) }
    // NOTE the argument is evaluated NOW, off the root radius the previous pass produced (JS:
    // `packChildren(padding, root.r / Math.min(dx, dy))`).
    let k2 = root.r / min(dx, dy)
    d3EachAfter(root) { d3PackChildren($0, padding: padding, k: k2) }
    let k3 = min(dx, dy) / (2 * root.r)
    d3EachBefore(root) { d3TranslateChild($0, k: k3) }
}

// MARK: - per-render layout (upstream's `params.context`)

/// `overallLayout(params, api)`: pack once in a render round, then share the node index with every
/// datum through `params.context`. A subsequent `setOption` receives a fresh context and recomputes,
/// exactly like the JavaScript custom-series API.
private func circlePackingNodes(width: Double, height: Double) -> [String: D3Node] {
    var nodes: [String: D3Node] = [:]
    guard let root = circlePackingStratify(circlePackingSeriesData) else { return nodes }
    circlePackingSumAndSort(root)
    d3Pack(root, dx: width - 2, dy: height - 2, padding: 3)
    for node in d3Descendants(root) { nodes[node.id] = node }
    return nodes
}

/// `nodePath.slice(nodePath.lastIndexOf('.') + 1).split(/(?=[A-Z][^A-Z])/g).join('\n')` — break the leaf's
/// key before every capital that starts a word (`itemStyle` → `item\nStyle`). A zero-width match at
/// index 0 does not split in JS, hence the `> 0` guard.
private func circlePackingLeafName(_ nodePath: String) -> String {
    let key: String
    if let dot = nodePath.lastIndex(of: ".") {
        key = String(nodePath[nodePath.index(after: dot)...])
    } else {
        key = nodePath
    }

    let chars = Array(key)
    var parts: [String] = []
    var current = ""
    for (i, ch) in chars.enumerated() {
        let nextIsLower = i + 1 < chars.count && !chars[i + 1].isUppercase
        if i > 0 && ch.isUppercase && nextIsLower {
            parts.append(current)
            current = String(ch)
        } else {
            current.append(ch)
        }
    }
    parts.append(current)
    return parts.joined(separator: "\n")
}

/// ParsedValue (Any: Double | Int | NSNumber) → Double.
private func circlePackingNum(_ v: Any?) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return 0
}

// MARK: - the upstream renderItem, ported

/// The official `renderItem`, statement for statement: one `circle` per node, at the packed
/// centre/radius, filled by the depth visualMap, with the leaf key as an inside `textContent`.
/// Typed EXACTLY `CustomSeriesRenderItem` so CustomView's `get("renderItem") as? CustomSeriesRenderItem`
/// cast holds.
private let circlePackingRenderItem: CustomSeriesRenderItem = { params, api in
    // `if (!context.layout) { context.layout = true; overallLayout(params, api); }`
    if params.context["nodes"] == nil {
        params.context["nodes"] = circlePackingNodes(width: api.getWidth(), height: api.getHeight())
    }
    guard let nodes = params.context["nodes"] as? [String: D3Node] else { return nil }

    // `api.value('id')` — the 'id' dimension is ordinal WITHOUT an ordinalMeta (no category axis), so the
    // store passes the raw string through, exactly as upstream does.
    guard let nodePath = api.value("id", nil) as? String else { return nil }
    guard let node = nodes[nodePath] else {
        // Render nothing.
        return nil
    }

    let isLeaf = (node.children?.isEmpty ?? true)

    // `new Uint32Array(node.descendants().map(node => node.data.index))`
    let focus: [Double] = d3Descendants(node).map { Double($0.dataIndex) }

    let nodeName = isLeaf ? circlePackingLeafName(nodePath) : ""

    let z2 = circlePackingNum(api.value("depth", nil)) * 2

    var style: [String: Any] = [:]
    if let color = api.visual("color", nil) { style["fill"] = color }

    // Hoisted out of the return literal: Swift's type-checker times out on large nested heterogeneous
    // literals.
    let textContent: [String: Any] = [
        "type": "text",
        "style": [
            // transition: isLeaf ? 'fontSize' : null,   (commented out upstream too)
            "text": nodeName,
            "fontFamily": "Arial",
            "width": node.r * 1.3,
            "overflow": "truncate",
            "fontSize": node.r / 3
        ] as [String: Any],
        "emphasis": [
            "style": [
                // `overflow: null` — unset the truncation while hovered. NSNull is the port's `null`:
                // the `as? String` read of it fails, which is exactly "no overflow".
                "overflow": NSNull(),
                "fontSize": max(node.r / 3, 12)
            ] as [String: Any]
        ] as [String: Any]
    ]

    let emphasis: [String: Any] = [
        "style": [
            "fontFamily": "Arial",
            "fontSize": 12.0,
            "shadowBlur": 20.0,
            "shadowOffsetX": 3.0,
            "shadowOffsetY": 5.0,
            "shadowColor": "rgba(0,0,0,0.3)"
        ] as [String: Any]
    ]

    return [
        "type": "circle",
        "focus": focus,
        "shape": [
            "cx": node.x,
            "cy": node.y,
            "r": node.r
        ] as [String: Any],
        "transition": ["shape"],
        "z2": z2,
        "textContent": textContent,
        "textConfig": [
            "position": "inside"
        ] as [String: Any],
        "style": style,
        "emphasis": emphasis
    ] as [String: Any]
}

extension EChartsDemoRegistry {
    static let official_circle_packing_with_d3 = EChartsDemo(
        name: "official-circle-packing-with-d3", category: "custom",
        summary: "基于 d3 的圆形包络图 — Circle Packing with d3",
        width: 720, height: 460,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
// $.getScript(CDN_PATH + 'd3-hierarchy@2.0.0/dist/d3-hierarchy.min.js') — the page has no network, so the
// dist (assets/lib/d3-hierarchy.js, same version) is spliced in verbatim. Its UMD wrapper publishes the
// same `d3` global (d3.stratify / d3.pack) the CDN script does.
\#(circlePackingD3JS)

// $.when($.get(ROOT_PATH + '/data/asset/data/option-view.json'), <the d3 script above>).done(function (res) {
//   run(res[0]);
// });
// The asset is inlined below and `run` is called at the top level; everything after this is verbatim.
const rawData = \#(circlePackingRawJSON);

run(rawData);

function run(rawData) {
  const dataWrap = prepareData(rawData);
  initChart(dataWrap.seriesData, dataWrap.maxDepth);
}

function prepareData(rawData) {
  const seriesData = [];
  let maxDepth = 0;

  function convert(source, basePath, depth) {
    if (source == null) {
      return;
    }
    if (maxDepth > 5) {
      return;
    }
    maxDepth = Math.max(depth, maxDepth);

    seriesData.push({
      id: basePath,
      value: source.$count,
      depth: depth,
      index: seriesData.length
    });

    for (var key in source) {
      if (source.hasOwnProperty(key) && !key.match(/^\$/)) {
        var path = basePath + '.' + key;
        convert(source[key], path, depth + 1);
      }
    }
  }

  convert(rawData, 'option', 0);

  return {
    seriesData: seriesData,
    maxDepth: maxDepth
  };
}

function initChart(seriesData, maxDepth) {
  var displayRoot = stratify();

  function stratify() {
    return d3
      .stratify()
      .parentId(function (d) {
        return d.id.substring(0, d.id.lastIndexOf('.'));
      })(seriesData)
      .sum(function (d) {
        return d.value || 0;
      })
      .sort(function (a, b) {
        return b.value - a.value;
      });
  }

  function overallLayout(params, api) {
    var context = params.context;
    d3
      .pack()
      .size([api.getWidth() - 2, api.getHeight() - 2])
      .padding(3)(displayRoot);

    context.nodes = {};
    displayRoot.descendants().forEach(function (node, index) {
      context.nodes[node.id] = node;
    });
  }

  function renderItem(params, api) {
    var context = params.context;

    // Only do that layout once in each time `setOption` called.
    if (!context.layout) {
      context.layout = true;
      overallLayout(params, api);
    }

    var nodePath = api.value('id');
    var node = context.nodes[nodePath];

    if (!node) {
      // Reder nothing.
      return;
    }

    var isLeaf = !node.children || !node.children.length;

    var focus = new Uint32Array(
      node.descendants().map(function (node) {
        return node.data.index;
      })
    );

    var nodeName = isLeaf
      ? nodePath
          .slice(nodePath.lastIndexOf('.') + 1)
          .split(/(?=[A-Z][^A-Z])/g)
          .join('\n')
      : '';

    var z2 = api.value('depth') * 2;

    return {
      type: 'circle',
      focus: focus,
      shape: {
        cx: node.x,
        cy: node.y,
        r: node.r
      },
      transition: ['shape'],
      z2: z2,
      textContent: {
        type: 'text',
        style: {
          // transition: isLeaf ? 'fontSize' : null,
          text: nodeName,
          fontFamily: 'Arial',
          width: node.r * 1.3,
          overflow: 'truncate',
          fontSize: node.r / 3
        },
        emphasis: {
          style: {
            overflow: null,
            fontSize: Math.max(node.r / 3, 12)
          }
        }
      },
      textConfig: {
        position: 'inside'
      },
      style: {
        fill: api.visual('color')
      },
      emphasis: {
        style: {
          fontFamily: 'Arial',
          fontSize: 12,
          shadowBlur: 20,
          shadowOffsetX: 3,
          shadowOffsetY: 5,
          shadowColor: 'rgba(0,0,0,0.3)'
        }
      }
    };
  }

  option = {
    dataset: {
      source: seriesData
    },
    tooltip: {},
    visualMap: [
      {
        show: false,
        min: 0,
        max: maxDepth,
        dimension: 'depth',
        inRange: {
          color: ['#006edd', '#e0ffff']
        }
      }
    ],
    hoverLayerThreshold: Infinity,
    series: {
      type: 'custom',
      renderItem: renderItem,
      progressive: 0,
      coordinateSystem: 'none',
      encode: {
        tooltip: 'value',
        itemName: 'id'
      }
    }
  };

  myChart.setOption(option);

  myChart.on('click', { seriesIndex: 0 }, function (params) {
    drillDown(params.data.id);
  });

  function drillDown(targetNodeId) {
    displayRoot = stratify();
    if (targetNodeId != null) {
      displayRoot = displayRoot.descendants().find(function (node) {
        return node.data.id === targetNodeId;
      });
    }
    // A trick to prevent d3-hierarchy from visiting parents in this algorithm.
    displayRoot.parent = null;

    myChart.setOption({
      dataset: {
        source: seriesData
      }
    });
  }

  // Reset: click on the blank area.
  myChart.getZr().on('click', function (event) {
    if (!event.target) {
      drillDown();
    }
  });
}
"""#,
        option: [
            "dataset": [
                "source": circlePackingSeriesData as [Any]
            ] as [String: Any],
            "tooltip": [:] as [String: Any],
            "visualMap": [
                [
                    "show": false,
                    "min": 0.0,
                    "max": circlePackingMaxDepth,
                    "dimension": "depth",
                    "inRange": [
                        "color": ["#006edd", "#e0ffff"]
                    ] as [String: Any]
                ] as [String: Any]
            ],
            "hoverLayerThreshold": Double.infinity,
            // The example gives `series` as a single OBJECT (echarts normalizes it to a list) — kept as-is.
            "series": [
                "type": "custom",
                "renderItem": circlePackingRenderItem,
                "progressive": 0.0,
                "coordinateSystem": "none",
                "encode": [
                    "tooltip": "value",
                    "itemName": "id"
                ] as [String: Any]
            ] as [String: Any]
        ])
}
