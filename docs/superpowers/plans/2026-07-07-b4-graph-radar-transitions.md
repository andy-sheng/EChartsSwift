# B4 — Graph node + Radar vertex scale-in Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. Checkbox steps.

**Goal:** Apply the proven scatter symbol scale-in entrance (set `scaleX/scaleY=0`, origin at the point, `initProps` toward scale 1) to graph nodes and radar vertices, so they grow in when animation is enabled.

**Architecture:** Identical to B2 scatter (chart/helper/Symbol.ts first-create). Both views build node/vertex symbols inline via `symbol.createSymbol` (full pixel size, normal scale 1). Set the symbol's transform origin to its point, `scaleX/scaleY=0`, then `initProps(path, ["scaleX":1.0, "scaleY":1.0], seriesModel, dataIndex)`. Animation off → instant full scale (no-op branch). Scalar transform props — no struct→dict issue.

**Tech Stack:** EChartsKit (GraphView, RadarView, animation/basicTransition), ZRenderKit (Path transform).

## Global Constraints

- Faithful to `upstream/echarts/src/chart/helper/Symbol.ts` first-create scale-in.
- Build 0 warnings (ignore pre-existing `calendarPrepareCustom.swift`). `swift test` green (333 baseline).
- Commit + push to `main`. No backticks in commit messages. End with `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
- Symbol scale is a scalar transform prop (pass `["scaleX":1.0,"scaleY":1.0]` directly). Set the transform origin to the symbol's point so it grows from the datum, not the canvas origin.
- Test pattern (from ScatterTransitionTests): assert an animator with a scaleX track exists; step the track to t=0/t=1 and assert 0 then 1 (real delta). `setToFinal` jumps the live prop to final, so assert the TRACK, not the synchronous live value.

---

### Task 1: Graph node scale-in

**Files:**
- Modify: `Sources/EChartsKit/chart/graph/GraphView.swift` (node symbol creation loop)
- Test: `Tests/EChartsKitTests/GraphTransitionTests.swift`

**Interfaces:** Consumes shared `initProps`; `Path.scaleX/scaleY/originX/originY`.

- [ ] **Step 1: Find the node symbol creation site + its point coords**

Run: `grep -n "createSymbol\|node.name\|\"node\"\|setItemGraphicEl\|dataToPoint\|\.getLayout\|nodePoint\|cx\|cy\|point" Sources/EChartsKit/chart/graph/GraphView.swift | head -25`
Identify: the per-node `Path` (its `name` — likely "node"), the node's center point (x,y) in the view's pixel space, the `seriesModel`, and the node's dataIndex. Read the loop that builds each node symbol.

- [ ] **Step 2: Write the failing test**

Create `Tests/EChartsKitTests/GraphTransitionTests.swift`:

```swift
// Graph nodes scale in (scaleX/scaleY 0→1) when animation is on. Faithful to Symbol.ts first-create.
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class GraphTransitionTests: XCTestCase {
    private func firstNode(_ el: Element) -> Path? {
        if let p = el as? Path, p.name == "node" { return p }
        if let g = el as? Group { for c in g.children() { if let h = firstNode(c) { return h } } }
        return nil
    }
    private func option(_ animation: Bool) -> [String: Any] {
        [
            "animation": animation,
            "series": [[
                "type": "graph", "layout": "none",
                "data": [["name": "n1", "x": 100.0, "y": 100.0], ["name": "n2", "x": 200.0, "y": 200.0]],
                "links": [["source": "n1", "target": "n2"]]
            ]]
        ]
    }
    func test_node_scales_in_when_animation_on() {
        let ec = EChartsSlim(width: 400, height: 400); ec.setOption(option(true))
        guard let node = firstNode(ec.getRoot()) else { return XCTFail("no graph node (name==\"node\")") }
        let anim = node.animators.first { $0.getTrack("scaleX") != nil }
        XCTAssertNotNil(anim, "node should have a scaleX animator when animation on")
        if let track = anim?.getTrack("scaleX") {
            track.step(node, 0.0); XCTAssertEqual(node.scaleX, 0.0, accuracy: 1e-9, "track starts at 0")
            track.step(node, 1.0); XCTAssertEqual(node.scaleX, 1.0, accuracy: 1e-9, "track ends at 1")
        }
    }
    func test_node_full_scale_when_animation_off() {
        let ec = EChartsSlim(width: 400, height: 400); ec.setOption(option(false))
        guard let node = firstNode(ec.getRoot()) else { return XCTFail("no graph node") }
        XCTAssertEqual(node.animators.count, 0, "no animator when animation off")
        XCTAssertEqual(node.scaleX, 1.0, accuracy: 1e-9, "node at full scale when off")
    }
}
```
If the node symbol's `name` is not `"node"`, fix `firstNode` to the real name (from Step 1). If the demo option shape differs (graph needs `x`/`y` with `layout:"none"`), adjust so a node symbol is actually produced — verify by running the test and seeing it find a node (the "on" assertion should fail on 0 animators, not on "no node").

- [ ] **Step 3: Run to verify failure** — `swift test --filter GraphTransitionTests` → the "on" test FAILS (0 animators).

- [ ] **Step 4: Add the scale-in** — at the node symbol creation site, after the node `Path` is configured and `data.setItemGraphicEl(...)`, before adding it to its group, insert (adapt var names from Step 1):
```swift
                nodePath.originX = nodeX
                nodePath.originY = nodeY
                nodePath.scaleX = 0
                nodePath.scaleY = 0
                initProps(nodePath, ["scaleX": 1.0, "scaleY": 1.0], seriesModel, dataIndex)
```

- [ ] **Step 5: Green + full suite** — `swift test --filter GraphTransitionTests` PASS, then full `swift test` 0 failures.

- [ ] **Step 6: Build + commit**
```bash
swift build 2>&1 | grep -iE "error|warning" | grep -v calendarPrepareCustom
git add Sources/EChartsKit/chart/graph/GraphView.swift Tests/EChartsKitTests/GraphTransitionTests.swift
git commit -m "$(cat <<'EOF'
graph: node symbol scale-in entrance via shared basicTransition

Reuse the scatter/Symbol.ts first-create pattern: scaleX/scaleY 0 with origin at the
node point, initProps toward scale 1 so graph nodes grow in when animation is enabled.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
git push origin main
```

---

### Task 2: Radar vertex scale-in

**Files:**
- Modify: `Sources/EChartsKit/chart/radar/RadarView.swift` (vertex symbol creation ~line 204-212)
- Test: `Tests/EChartsKitTests/RadarTransitionTests.swift`

**Interfaces:** Consumes shared `initProps`; `Path.scaleX/scaleY/originX/originY`.

- [ ] **Step 1: Read the vertex creation site**

Run: `grep -n "createSymbol\|\"vertex\"\|path.name\|path.z2\|itemGroup.add\|point\[\|cx\|cy" Sources/EChartsKit/chart/radar/RadarView.swift | head`
The vertex `Path` is named `"vertex"` (RadarView.swift:208), z2=100, created via createSymbol at the vertex point. Identify the vertex point coords (the `x - w/2, y - h/2` centering implies the center is at some `(px, py)`), `seriesModel`, and the vertex dataIndex/dimIdx.

- [ ] **Step 2: Write the failing test**

Create `Tests/EChartsKitTests/RadarTransitionTests.swift`:

```swift
// Radar vertices scale in (scaleX/scaleY 0→1) when animation is on. Faithful to Symbol.ts first-create.
import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class RadarTransitionTests: XCTestCase {
    private func firstVertex(_ el: Element) -> Path? {
        if let p = el as? Path, p.name == "vertex" { return p }
        if let g = el as? Group { for c in g.children() { if let h = firstVertex(c) { return h } } }
        return nil
    }
    private func option(_ animation: Bool) -> [String: Any] {
        [
            "animation": animation,
            "radar": ["indicator": [["name": "A", "max": 100.0], ["name": "B", "max": 100.0], ["name": "C", "max": 100.0]]],
            "series": [["type": "radar", "data": [["value": [60.0, 70.0, 80.0]]]]]
        ]
    }
    func test_vertex_scales_in_when_animation_on() {
        let ec = EChartsSlim(width: 400, height: 400); ec.setOption(option(true))
        guard let v = firstVertex(ec.getRoot()) else { return XCTFail("no radar vertex (name==\"vertex\")") }
        let anim = v.animators.first { $0.getTrack("scaleX") != nil }
        XCTAssertNotNil(anim, "vertex should have a scaleX animator when animation on")
        if let track = anim?.getTrack("scaleX") {
            track.step(v, 0.0); XCTAssertEqual(v.scaleX, 0.0, accuracy: 1e-9, "track starts at 0")
            track.step(v, 1.0); XCTAssertEqual(v.scaleX, 1.0, accuracy: 1e-9, "track ends at 1")
        }
    }
    func test_vertex_full_scale_when_animation_off() {
        let ec = EChartsSlim(width: 400, height: 400); ec.setOption(option(false))
        guard let v = firstVertex(ec.getRoot()) else { return XCTFail("no radar vertex") }
        XCTAssertEqual(v.animators.count, 0, "no animator when animation off")
        XCTAssertEqual(v.scaleX, 1.0, accuracy: 1e-9, "vertex at full scale when off")
    }
}
```

- [ ] **Step 3: Run to verify failure** — `swift test --filter RadarTransitionTests` → "on" test FAILS (0 animators).

- [ ] **Step 4: Add the scale-in** — at the vertex creation site (after `path.name = "vertex"` / z2, before adding to itemGroup), insert (adapt the vertex center coords `vx`/`vy`):
```swift
                        path.originX = vx
                        path.originY = vy
                        path.scaleX = 0
                        path.scaleY = 0
                        initProps(path, ["scaleX": 1.0, "scaleY": 1.0], seriesModel, idx)
```
The vertex center is the point createSymbol was centered on (createSymbol was called with `x - w/2, y - h/2`, so `vx = x`, `vy = y` — the pre-centering point). Use those.

- [ ] **Step 5: Green + full suite** — `swift test --filter RadarTransitionTests` PASS, full `swift test` 0 failures.

- [ ] **Step 6: Build + commit**
```bash
swift build 2>&1 | grep -iE "error|warning" | grep -v calendarPrepareCustom
git add Sources/EChartsKit/chart/radar/RadarView.swift Tests/EChartsKitTests/RadarTransitionTests.swift
git commit -m "$(cat <<'EOF'
radar: vertex symbol scale-in entrance via shared basicTransition

Reuse the scatter/Symbol.ts first-create pattern for radar vertices: scaleX/scaleY 0 with
origin at the vertex point, initProps toward scale 1. Radar polygon-from-center expansion
is deferred.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
git push origin main
```

---

## Self-Review

- **Coverage:** graph nodes → Task 1; radar vertices → Task 2. Both reuse the scatter scale-in; radar polygon-from-center + graph edge animation deferred (noted).
- **Placeholders:** none — Steps 1 are real find-the-site steps with concrete greps; var names adapted by the implementer.
- **Type consistency:** shared `initProps` (B1), scalar transform props (no dict), track-step test asserting real 0→1 delta (matches Scatter/Pie).
- **Risks:** the node/vertex `name` and point-coord var names must be confirmed (Step 1). Graph with `layout:"none"` + explicit x/y ensures a node symbol is produced headlessly.
