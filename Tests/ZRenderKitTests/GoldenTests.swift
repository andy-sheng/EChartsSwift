// GoldenTests.swift — the Swift side of the Golden Test harness.
//
// This is the *oracle consumer*. The generator (Oracle/dump-displaylist.js) runs the
// real ECharts/ZRender in SSR mode and writes, per shape, the exact path-command stream
// that ZRender's PathProxy.rebuildPath() emits (moveTo/lineTo/bezierCurveTo/arc/...),
// plus a canonical string form `rebuiltD`. The Swift port is *faithful* iff our ported
// `PathProxy` + shape `buildPath` produce the same stream, and our `PathRebuilder` +
// formatter render it to the same `rebuiltD`.
//
// Two layers live here:
//   1. testRebuiltDMatchesOracle()         — RUNS TODAY. Feeds each fixture's recorded
//      pathCommands through a Swift `PathRebuilder` and asserts our canonical formatter
//      reproduces the fixture's `rebuiltD` byte-for-byte. This pins the PathRebuilder
//      surface + the cross-language number formatting before any shape math exists.
//   2. testSwiftBuildPathMatchesOracle()    — the INTENDED end-state pattern, written
//      out but compiled-out behind `#if PORT_TODO_GOLDEN` because it references types
//      not ported yet (PathProxy, Sector, RectShape, ...). As each phase lands, port the
//      type, then flip the shape into layer 1's data-driven loop (or enable the flag).
//
// See Oracle/README.md for how fixtures map to tests and how to add new ones.

import XCTest
@testable import ZRenderKit

final class GoldenTests: XCTestCase {

    // MARK: - Fixture model

    /// A single recorded path command, e.g. ["moveTo", 160, 75] or ["arc", 100,75,60,0,1.57,false].
    /// JSON arrays are heterogeneous (op name : String, coords : Double, flags : Bool),
    /// so each slot decodes into one of these.
    enum CommandValue: Decodable, Equatable {
        case op(String)
        case num(Double)
        case flag(Bool)

        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let s = try? c.decode(String.self) { self = .op(s); return }
            if let b = try? c.decode(Bool.self) { self = .flag(b); return }
            if let d = try? c.decode(Double.self) { self = .num(d); return }
            throw DecodingError.dataCorruptedError(
                in: c, debugDescription: "Unsupported command value")
        }
    }

    struct Element: Decodable {
        let type: String
        let z: Double
        let zlevel: Double
        let z2: Double
        // Present only for Path elements:
        let pathDataOps: [String]?
        let pathCommands: [[CommandValue]]?
        let rebuiltD: String?
    }

    struct Fixture: Decodable {
        let name: String
        let echartsVersion: String
        let precision: Int
        let elements: [Element]
        let svgPaths: [String]
    }

    // MARK: - Fixture loading

    /// Oracle/fixtures lives at <repo>/Oracle/fixtures; this file is at
    /// <repo>/Tests/ZRenderKitTests/GoldenTests.swift.
    static var fixturesDir: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // ZRenderKitTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Oracle/fixtures", isDirectory: true)
    }

    func loadFixture(_ name: String) throws -> Fixture {
        let url = Self.fixturesDir.appendingPathComponent(name + ".json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Fixture.self, from: data)
    }

    /// Every fixture name we expect on disk. Add new ones here as phases land.
    static let allFixtures = [
        "rect", "circle", "sector", "arc", "bezier-curve", "polygon", "combined",
        "ellipse", "ring", "line", "polyline"
    ]

    // MARK: - Recording PathRebuilder (canonical 'd' form)

    /// Records the commands it receives AND renders them to the same canonical string
    /// the oracle uses (`rebuiltD`). The tokens are intentionally NOT the SVG `d`
    /// grammar — arcs stay arcs — so the comparison is 1:1 with PathProxy, not with a
    /// renderer's arc→cubic approximation.
    ///
    /// The number formatter here MUST match Oracle/dump-displaylist.js `fmt()`:
    /// round to 6 decimals, then drop trailing zeros / trailing dot, normalise -0.
    final class GoldenPathRebuilder: PathRebuilder {
        private(set) var tokens: [String] = []

        var dString: String { tokens.joined(separator: " ") }

        static func fmt(_ n: Double) -> String {
            var r = (n * 1e6).rounded() / 1e6
            if r == 0 { r = 0 }                       // normalise -0 → 0
            // %.6f then trim — matches JS String(round(n)) for 6-dp values.
            var s = String(format: "%.6f", r)
            if s.contains(".") {
                while s.hasSuffix("0") { s.removeLast() }
                if s.hasSuffix(".") { s.removeLast() }
            }
            if s == "-0" { s = "0" }
            return s
        }

        private func push(_ token: String, _ nums: [Double], flags: [Bool] = []) {
            var parts = [token]
            parts.append(contentsOf: nums.map(Self.fmt))
            parts.append(contentsOf: flags.map { $0 ? "1" : "0" })
            tokens.append(parts.joined(separator: " "))
        }

        func moveTo(_ x: Double, _ y: Double) { push("M", [x, y]) }
        func lineTo(_ x: Double, _ y: Double) { push("L", [x, y]) }
        func bezierCurveTo(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ x3: Double, _ y3: Double) {
            push("C", [x1, y1, x2, y2, x3, y3])
        }
        func quadraticCurveTo(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
            push("Q", [x1, y1, x2, y2])
        }
        func arc(_ cx: Double, _ cy: Double, _ r: Double, _ startAngle: Double, _ endAngle: Double, _ anticlockwise: Bool) {
            push("ARC", [cx, cy, r, startAngle, endAngle], flags: [anticlockwise])
        }
        func ellipse(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double, _ rotation: Double, _ startAngle: Double, _ endAngle: Double, _ anticlockwise: Bool) {
            push("ELL", [cx, cy, rx, ry, rotation, startAngle, endAngle], flags: [anticlockwise])
        }
        func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) { push("RECT", [x, y, w, h]) }
        func closePath() { tokens.append("Z") }
    }

    // MARK: - Helper: replay a fixture's recorded commands through a PathRebuilder

    /// Interprets `[[CommandValue]]` and drives `rb` exactly as PathProxy.rebuildPath
    /// would. This is the stand-in until the real ported `PathProxy.rebuildPath(rb,1)`
    /// exists — at which point shape tests call that instead (see PORT-NOTE below).
    private func replay(_ commands: [[CommandValue]], into rb: PathRebuilder) throws {
        func nums(_ cmd: [CommandValue]) -> [Double] {
            cmd.compactMap { if case let .num(d) = $0 { return d } else { return nil } }
        }
        func flag(_ cmd: [CommandValue]) -> Bool {
            for v in cmd { if case let .flag(b) = v { return b } }
            return false
        }
        for cmd in commands {
            guard case let .op(op) = cmd.first else {
                throw XCTSkip("malformed command (missing op): \(cmd)")
            }
            let n = nums(cmd)
            switch op {
            case "moveTo": rb.moveTo(n[0], n[1])
            case "lineTo": rb.lineTo(n[0], n[1])
            case "bezierCurveTo": rb.bezierCurveTo(n[0], n[1], n[2], n[3], n[4], n[5])
            case "quadraticCurveTo": rb.quadraticCurveTo(n[0], n[1], n[2], n[3])
            case "arc": rb.arc(n[0], n[1], n[2], n[3], n[4], flag(cmd))
            case "ellipse": rb.ellipse(n[0], n[1], n[2], n[3], n[4], n[5], n[6], flag(cmd))
            case "rect": rb.rect(n[0], n[1], n[2], n[3])
            case "closePath": rb.closePath()
            default: throw XCTSkip("unknown op in fixture: \(op)")
            }
        }
    }

    // MARK: - Layer 1: harness self-check (RUNS TODAY)

    /// For every Path element in every fixture: drive a Swift `PathRebuilder` with the
    /// oracle's recorded commands and assert our canonical formatter reproduces the
    /// oracle's `rebuiltD` byte-for-byte. Locks in the PathRebuilder surface + the
    /// JS<->Swift number-format contract before any geometry is ported.
    func testRebuiltDMatchesOracle() throws {
        for name in Self.allFixtures {
            let fixture = try loadFixture(name)
            for (i, el) in fixture.elements.enumerated() {
                guard let commands = el.pathCommands, let expected = el.rebuiltD else {
                    continue  // non-Path element (Group/Text/Image)
                }
                let rb = GoldenPathRebuilder()
                try replay(commands, into: rb)
                XCTAssertEqual(
                    rb.dString, expected,
                    "fixture '\(name)' element[\(i)] (\(el.type)): rebuilt 'd' diverged from oracle"
                )
            }
        }
    }

    /// Sanity: the fixtures we expect are actually on disk and decodable.
    func testAllFixturesLoad() throws {
        for name in Self.allFixtures {
            let fixture = try loadFixture(name)
            XCTAssertEqual(fixture.name, name)
            XCTAssertFalse(fixture.elements.isEmpty, "fixture '\(name)' has no elements")
        }
    }

    // MARK: - Layer 2: TRUE GEOMETRY PARITY (RUNS TODAY)

    // The intended end-state, now real. For each shape we instantiate the ported `…Shape`
    // struct with the params from `Oracle/options/<name>.json`, set it on the ported `Path`
    // subclass, build the path the *Swift* way (`getUpdatedPathProxy` → `beginPath` +
    // `buildPath`), replay through the GoldenPathRebuilder, and assert the canonical `d`
    // matches the oracle's `rebuiltD` byte-for-byte — the same assertion as layer 1, but now
    // driven by the ported shape math instead of the oracle's recorded command stream.

    /// Build the Swift-side canonical `d` for `path` after setting `shape` on it.
    /// Mirrors what `CALayerPainter` does: `getUpdatedPathProxy(false)` (beginPath + buildPath)
    /// then `rebuildPath(rb, 1)`.
    private func buildRebuiltD(_ path: Path, _ shape: PathShape) -> String {
        path.setShape(shape)
        let proxy = path.getUpdatedPathProxy(false)
        let rb = GoldenPathRebuilder()
        proxy.rebuildPath(rb, 1)
        return rb.dString
    }

    /// Assert the Swift-built `d` for one fixture equals the oracle's first Path element's
    /// `rebuiltD`. Returns nothing; on mismatch the failure message carries the full diff.
    private func assertGeometryParity(
        _ name: String, _ path: Path, _ shape: PathShape,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let fixture = try loadFixture(name)
        guard let expected = fixture.elements.first(where: { $0.rebuiltD != nil })?.rebuiltD else {
            return XCTFail("fixture '\(name)' has no Path element with rebuiltD", file: file, line: line)
        }
        let actual = buildRebuiltD(path, shape)
        XCTAssertEqual(
            actual, expected,
            "fixture '\(name)': Swift buildPath 'd' diverged from oracle\n  expected: \(expected)\n  actual:   \(actual)",
            file: file, line: line
        )
    }

    func testSwiftBuildPathMatchesOracle() throws {
        // --- rect ---  (Oracle/options/rect.json: x 10 y 10 w 80 h 50 r [8,4,2,6])
        var rectShape = RectShape()
        rectShape.x = 10; rectShape.y = 10; rectShape.width = 80; rectShape.height = 50
        rectShape.r = .array([8, 4, 2, 6])
        try assertGeometryParity("rect", Rect(), rectShape)

        // --- circle ---  (cx 100 cy 75 r 40)
        var circleShape = CircleShape()
        circleShape.cx = 100; circleShape.cy = 75; circleShape.r = 40
        try assertGeometryParity("circle", Circle(), circleShape)

        // --- sector ---  (cx 100 cy 75 r 60 r0 20 startAngle 0 endAngle π/2 clockwise true)
        var sectorShape = SectorShape()
        sectorShape.cx = 100; sectorShape.cy = 75; sectorShape.r = 60; sectorShape.r0 = 20
        sectorShape.startAngle = 0; sectorShape.endAngle = 1.5707963267948966
        sectorShape.clockwise = true
        try assertGeometryParity("sector", Sector(), sectorShape)

        // --- arc ---  (cx 100 cy 75 r 40 startAngle 0 endAngle 4.712389 clockwise true)
        var arcShape = ArcShape()
        arcShape.cx = 100; arcShape.cy = 75; arcShape.r = 40
        arcShape.startAngle = 0; arcShape.endAngle = 4.71238898038469
        arcShape.clockwise = true
        try assertGeometryParity("arc", Arc(), arcShape)

        // --- bezier-curve ---  (x1 10 y1 120 cpx1 30 cpy1 90 cpx2 60 cpy2 140 x2 90 y2 120)
        var bezierShape = BezierCurveShape()
        bezierShape.x1 = 10; bezierShape.y1 = 120
        bezierShape.cpx1 = 30; bezierShape.cpy1 = 90
        bezierShape.cpx2 = 60; bezierShape.cpy2 = 140
        bezierShape.x2 = 90; bezierShape.y2 = 120
        try assertGeometryParity("bezier-curve", BezierCurve(), bezierShape)

        // --- polygon ---  (5 points)
        var polygonShape = PolygonShape()
        polygonShape.points = [
            VectorArray(20, 20), VectorArray(90, 35), VectorArray(70, 110),
            VectorArray(25, 95), VectorArray(10, 55)
        ]
        try assertGeometryParity("polygon", Polygon(), polygonShape)

        // --- ellipse ---  (cx 100 cy 75 rx 60 ry 40) — Phase 2 shape
        var ellipseShape = EllipseShape()
        ellipseShape.cx = 100; ellipseShape.cy = 75; ellipseShape.rx = 60; ellipseShape.ry = 40
        try assertGeometryParity("ellipse", Ellipse(), ellipseShape)

        // --- ring ---  (cx 100 cy 75 r 50 r0 20) — Phase 2 shape
        var ringShape = RingShape()
        ringShape.cx = 100; ringShape.cy = 75; ringShape.r = 50; ringShape.r0 = 20
        try assertGeometryParity("ring", Ring(), ringShape)

        // --- line ---  (x1 10 y1 20 x2 180 y2 130; percent 1, subPixelOptimize off) — Phase 2 shape
        var lineShape = LineShape()
        lineShape.x1 = 10; lineShape.y1 = 20; lineShape.x2 = 180; lineShape.y2 = 130
        try assertGeometryParity("line", Line(), lineShape)

        // --- polyline ---  (5 points, open, smooth 0) — Phase 2 shape
        var polylineShape = PolylineShape()
        polylineShape.points = [
            VectorArray(10, 130), VectorArray(50, 30), VectorArray(90, 100),
            VectorArray(130, 25), VectorArray(180, 120)
        ]
        try assertGeometryParity("polyline", Polyline(), polylineShape)
    }

    // MARK: - Layer 3: SMOKE TEST for zrender-only decorative shapes

    // These shapes (Heart, Droplet, Isogon, Rose, Star, Trochoid) exist in zrender but the
    // ECharts `graphic` component does not register/expose them, so there is NO ECharts oracle
    // to compare against. We do NOT fabricate one. Instead we exercise each shape's `buildPath`
    // and assert it produced a non-empty, NaN-free PathProxy command buffer — proving the ported
    // math compiles and runs without emitting garbage coordinates.
    // no ECharts oracle — covered by ported zrender unit tests / visual.

    /// Build `shape` on `path`, then assert the resulting PathProxy data buffer is non-empty and
    /// free of NaN/Inf. Also drives the GoldenPathRebuilder so `rebuildPath` is exercised too.
    private func assertSmokeBuildPath(
        _ name: String, _ path: Path, _ shape: PathShape,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        path.setShape(shape)
        let proxy = path.getUpdatedPathProxy(false)
        let n = Int(proxy.len())
        XCTAssertGreaterThan(n, 0, "\(name): buildPath produced an empty command buffer", file: file, line: line)
        for i in 0..<n {
            let v = proxy.data[i]
            XCTAssertTrue(v.isFinite, "\(name): command buffer slot[\(i)] is non-finite (\(v))", file: file, line: line)
        }
        // Exercise rebuildPath end-to-end; the token stream must also be non-empty.
        let rb = GoldenPathRebuilder()
        proxy.rebuildPath(rb, 1)
        XCTAssertFalse(rb.tokens.isEmpty, "\(name): rebuildPath produced no tokens", file: file, line: line)
        XCTAssertFalse(rb.dString.lowercased().contains("nan"), "\(name): rebuilt 'd' contains NaN", file: file, line: line)
    }

    func testDecorativeShapesSmoke() {
        // --- heart ---  (cx 100 cy 75 width 80 height 60)
        var heartShape = HeartShape()
        heartShape.cx = 100; heartShape.cy = 75; heartShape.width = 80; heartShape.height = 60
        assertSmokeBuildPath("heart", Heart(), heartShape)

        // --- droplet ---  (cx 100 cy 75 width 40 height 60)
        var dropletShape = DropletShape()
        dropletShape.cx = 100; dropletShape.cy = 75; dropletShape.width = 40; dropletShape.height = 60
        assertSmokeBuildPath("droplet", Droplet(), dropletShape)

        // --- isogon ---  (x 100 y 75 r 40 n 6) — regular hexagon
        var isogonShape = IsogonShape()
        isogonShape.x = 100; isogonShape.y = 75; isogonShape.r = 40; isogonShape.n = 6
        assertSmokeBuildPath("isogon", Isogon(), isogonShape)

        // --- rose ---  (cx 100 cy 75 r [40] k 4 n 1)
        var roseShape = RoseShape()
        roseShape.cx = 100; roseShape.cy = 75; roseShape.r = [40]; roseShape.k = 4; roseShape.n = 1
        assertSmokeBuildPath("rose", Rose(), roseShape)

        // --- star ---  (cx 100 cy 75 n 5 r 40; r0 auto)
        var starShape = StarShape()
        starShape.cx = 100; starShape.cy = 75; starShape.n = 5; starShape.r = 40
        assertSmokeBuildPath("star", Star(), starShape)

        // --- trochoid ---  (cx 100 cy 75 r 40 r0 10 d 10 location out)
        var trochoidShape = TrochoidShape()
        trochoidShape.cx = 100; trochoidShape.cy = 75; trochoidShape.r = 40; trochoidShape.r0 = 10
        trochoidShape.d = 10; trochoidShape.location = "out"
        assertSmokeBuildPath("trochoid", Trochoid(), trochoidShape)
    }
}

// MARK: - CALayerPainter smoke test (macOS / iOS only)

#if canImport(QuartzCore) && canImport(CoreGraphics)
import CoreGraphics
import NativePainter

final class CALayerPainterSmokeTests: XCTestCase {

    /// Build a Group containing a Rect + Circle + Sector by hand and render it through
    /// `renderToImage`. Geometry parity is covered by `testSwiftBuildPathMatchesOracle`; this
    /// just proves the painter path (flatten → buildPath → CGRenderer → bitmap) executes and
    /// produces a non-nil image of the expected pixel size.
    func testRenderToImageProducesImage() throws {
        let group = Group()

        var rectShape = RectShape()
        rectShape.x = 10; rectShape.y = 10; rectShape.width = 80; rectShape.height = 50
        let rect = Rect()
        rect.setShape(rectShape)
        _ = group.add(rect)

        var circleShape = CircleShape()
        circleShape.cx = 100; circleShape.cy = 75; circleShape.r = 40
        let circle = Circle()
        circle.setShape(circleShape)
        _ = group.add(circle)

        var sectorShape = SectorShape()
        sectorShape.cx = 100; sectorShape.cy = 75; sectorShape.r = 60; sectorShape.r0 = 20
        sectorShape.startAngle = 0; sectorShape.endAngle = 1.5707963267948966
        let sector = Sector()
        sector.setShape(sectorShape)
        _ = group.add(sector)

        let size = CGSize(width: 200, height: 150)
        let image = renderToImage(group: group, size: size, dpr: 1)

        let img = try XCTUnwrap(image, "renderToImage returned nil")
        XCTAssertEqual(img.width, 200, "rendered image width")
        XCTAssertEqual(img.height, 150, "rendered image height")
    }

    /// Inherited-clip propagation (clipping.html's core). A leaf that sets NO clip of its own,
    /// nested in g1 (rect clip) ⊃ g2 (circle clip), must paint only inside rect ∩ circle.
    ///
    /// Storage builds the leaf's `__clipPaths` chain (parent g1 rect ∩ parent g2 circle); the painter
    /// must apply the WHOLE chain (CALayerPainter.applyClipChain), not just the leaf's own
    /// `getClipPath()` (which is nil here). Before that fix the leaf rendered fully unclipped.
    ///
    /// Geometry (200x200, all probes at y=100 — the vertical centre — so the CGImage y-flip is moot):
    ///   g1.clip = rect  x0 y0 w100 h200      → keeps x < 100
    ///   g2.clip = circle cx100 cy100 r80     → keeps dist((100,100)) < 80
    ///   cell    = rect  x0 y0 w200 h200 red  → covers the whole canvas, NO clip of its own
    func testGroupClipChainPropagatesToChildren() throws {
        let g1 = Group()
        let g2 = Group()
        _ = g1.add(g2)

        var rs = RectShape(); rs.x = 0; rs.y = 0; rs.width = 100; rs.height = 200
        let clipRect = Rect(); clipRect.setShape(rs)
        g1.setClipPath(clipRect)

        var cs = CircleShape(); cs.cx = 100; cs.cy = 100; cs.r = 80
        let clipCircle = Circle(); clipCircle.setShape(cs)
        g2.setClipPath(clipCircle)

        var cellShape = RectShape(); cellShape.x = 0; cellShape.y = 0; cellShape.width = 200; cellShape.height = 200
        let cell = Rect(); cell.setShape(cellShape)
        var fill = PathStyleProps(); fill.fill = .string("red"); cell.useStyle(fill)
        _ = g2.add(cell)

        // Populate each element's __clipPaths chain exactly as the live ZRender path does.
        let storage = Storage()
        storage.addRoot(g1)
        _ = storage.getDisplayList(true)
        XCTAssertEqual(cell.__clipPaths?.count, 2,
                       "leaf should inherit BOTH parent group clips (rect ∩ circle)")

        let img = try XCTUnwrap(renderToImage(group: g1, size: CGSize(width: 200, height: 200), dpr: 1))

        // (50,100): inside rect (x<100) AND inside circle (dist 50<80) → painted red.
        let inside = try pixelRGBA(img, 50, 100)
        XCTAssertGreaterThan(inside.a, 0.5, "inside rect∩circle should be painted")
        XCTAssertGreaterThan(inside.r, 0.5, "inside should be red")
        XCTAssertLessThan(inside.g, 0.5, "inside should be red (low green)")

        // (10,100): inside rect but OUTSIDE circle (dist 90>80) → clipped away by the inherited circle.
        let outCircle = try pixelRGBA(img, 10, 100)
        XCTAssertLessThan(outCircle.a, 0.5, "outside the inherited circle clip should be unpainted")

        // (150,100): inside circle (dist 50<80) but OUTSIDE rect (x>100) → clipped by the inherited rect.
        let outRect = try pixelRGBA(img, 150, 100)
        XCTAssertLessThan(outRect.a, 0.5, "outside the inherited rect clip should be unpainted")
    }

    /// A Rect filled with an image Pattern carrying a transform (rotation + scaleX + x offset) must
    /// still paint inside the rect and nowhere outside it. Guards the `CGRenderer.tilePattern` rewrite
    /// that applies the full pattern matrix (translate·rotate·scale) and bounds tiles via M⁻¹ — a
    /// broken extent/inverse would render the rect blank or spill the tiling outside the clip.
    /// (Rotation *direction* is verified visually against the upstream html; see DEMO_PARITY_GAPS.md.)
    func testRotatedPatternFillsRectAndClips() throws {
        // 20x20 tile: ECharts-blue with a white dot + amber corner (same as the pattern demos).
        let tile = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABQAAAAUCAYAAACNiR0NAAAAd0lEQVR4nGP8dSLiPwMURK3IY6AUMFFsAq0NZAwpOAb3MjUAEzUNI8nA1f2WlHt5NR5DQguPk+bC1QRchEueiYHKgIkuBq4mMgKwqWMiJcCJUcfEQGXARDcDQwl4G5c8I7F5GRQBxIQtEzGG4XMRA7kGEgsGv4EAElwhSajUA98AAAAASUVORK5CYII="
        let pat = Pattern(tile, .repeat)
        pat.x = 100; pat.scaleX = 0.5; pat.rotation = 0.5235987755982988  // π/6

        var rs = RectShape(); rs.x = 0; rs.y = 0; rs.width = 200; rs.height = 200
        let r = Rect(); r.setShape(rs)
        var st = PathStyleProps(); st.fill = .pattern(pat); r.useStyle(st)

        let group = Group(); _ = group.add(r)
        let img = try XCTUnwrap(renderToImage(group: group, size: CGSize(width: 400, height: 300), dpr: 1))

        // (100,100): inside the rect → some tile pixel is painted (the tile is fully opaque).
        let inside = try pixelRGBA(img, 100, 100)
        XCTAssertGreaterThan(inside.a, 0.5, "pattern should fill inside the rect")

        // (350,250): well outside the 200x200 rect → nothing painted (no tiling spill).
        let outside = try pixelRGBA(img, 350, 250)
        XCTAssertLessThan(outside.a, 0.5, "pattern fill must stay clipped to the rect")
    }

    /// `IncrementalDisplayable` must actually render its added displayables — it now exposes them via
    /// `childrenRef`, so the shared `activeChildrenRef()` descends into it. Before this it never entered
    /// the display list and the incremental demos drew nothing (the "没有增加" report).
    func testIncrementalDisplayableRendersAddedDisplayables() throws {
        let inc = IncrementalDisplayable()
        var cs = CircleShape(); cs.cx = 100; cs.cy = 100; cs.r = 40
        let c = Circle(); c.setShape(cs)
        var st = PathStyleProps(); st.fill = .string("#00ff00"); c.useStyle(st)
        inc.addDisplayable(c, true)   // html: inc.addDisplayable(circleShape, true)

        let group = Group(); _ = group.add(inc)
        let img = try XCTUnwrap(renderToImage(group: group, size: CGSize(width: 200, height: 200), dpr: 1))
        let inside = try pixelRGBA(img, 100, 100)
        XCTAssertGreaterThan(inside.a, 0.5, "an incremental displayable's child must paint")
        XCTAssertGreaterThan(inside.g, 0.5, "the child is green")
    }

    /// The incremental RETAINED layer accumulates pixels across flushes: a dot drawn on one `refresh`
    /// must survive the NEXT refresh even though it is no longer "pending" (its temp list was cleared) —
    /// i.e. old dots are not redrawn but stay on screen. And `clearDisplaybles()` wipes the bitmap.
    /// This is what makes the incremental demo O(batch)/frame instead of O(total).
    /// The painter draws through `Path.getCachedPathProxy` (upstream brushPath caching: the PathProxy
    /// command buffer is rebuilt only on first draw or when SHAPE_CHANGED_BIT is set). Guards that a
    /// shape change between flushes DOES invalidate the cache — otherwise a moving/resizing shape would
    /// render stale geometry forever.
    func testCachedPathProxyInvalidatesOnShapeChange() throws {
        func contentsImage(_ p: CALayerPainter) throws -> CGImage {
            let cf = try XCTUnwrap(p.rootLayer.contents) as CFTypeRef
            return cf as! CGImage
        }
        let painter = CALayerPainter(size: CGSize(width: 60, height: 60), dpr: 1)
        var cs = CircleShape(); cs.cx = 30; cs.cy = 30; cs.r = 5
        let c = Circle(); c.setShape(cs)
        var st = PathStyleProps(); st.fill = .string("#00ff00"); c.useStyle(st)

        // Flush 1: r=5. A point 12px above center is OUTSIDE the circle → not green.
        painter.refresh([c])
        XCTAssertLessThan(try pixelRGBA(contentsImage(painter), 30, 18).g, 0.5, "outside r=5 → unpainted")

        // Grow to r=20 (setShape sets SHAPE_CHANGED_BIT). Flush 2 must reflect the new geometry.
        cs.r = 20; c.setShape(cs)
        painter.refresh([c])
        XCTAssertGreaterThan(try pixelRGBA(contentsImage(painter), 30, 18).g, 0.5,
                             "shape change must invalidate the cached path proxy")
    }

    func testIncrementalRetainedLayerAccumulatesAndClears() throws {
        func greenDot(_ cx: Double, _ cy: Double) -> Circle {
            var cs = CircleShape(); cs.cx = cx; cs.cy = cy; cs.r = 8
            let c = Circle(); c.setShape(cs)
            var st = PathStyleProps(); st.fill = .string("#00ff00"); c.useStyle(st)
            return c
        }
        func contentsImage(_ p: CALayerPainter) throws -> CGImage {
            let cf = try XCTUnwrap(p.rootLayer.contents) as CFTypeRef
            XCTAssertEqual(CFGetTypeID(cf), CGImage.typeID)
            return cf as! CGImage
        }

        let painter = CALayerPainter(size: CGSize(width: 100, height: 100), dpr: 1)
        let inc = IncrementalDisplayable()

        // Flush 1: a dot at (25,25). It is drawn into the retained bitmap; its temp list is then cleared.
        inc.addDisplayable(greenDot(25, 25), true)
        painter.refresh([inc])

        // Flush 2: a NEW dot at (75,75). Dot #1 is no longer pending — yet it must still be on screen
        // (retained), proving old dots are not redrawn but persist.
        inc.addDisplayable(greenDot(75, 75), true)
        painter.refresh([inc])
        let acc = try contentsImage(painter)
        XCTAssertGreaterThan(try pixelRGBA(acc, 25, 25).g, 0.5, "dot from flush 1 must be retained")
        XCTAssertGreaterThan(try pixelRGBA(acc, 75, 75).g, 0.5, "dot from flush 2 must be drawn")

        // clearDisplaybles() wipes the retained bitmap on the next flush.
        inc.clearDisplaybles()
        painter.refresh([inc])
        let cleared = try contentsImage(painter)
        XCTAssertLessThan(try pixelRGBA(cleared, 25, 25).g, 0.5, "clearDisplaybles must wipe the retained pixels")
        XCTAssertLessThan(try pixelRGBA(cleared, 75, 75).g, 0.5, "clearDisplaybles must wipe the retained pixels")
    }

    /// blend 'lighter' is additive: a green dot over a red fill brightens toward yellow (red+green),
    /// where the default source-over would replace red with green. Guards `CGRenderer.setBlendMode` —
    /// the additive composite the incremental demos' '#121' dots rely on to glow.
    func testLighterBlendIsAdditive() throws {
        func redChannelOfDot(_ blend: String?) throws -> Double {
            let group = Group()
            var rs = RectShape(); rs.x = 0; rs.y = 0; rs.width = 60; rs.height = 60
            let bg = Rect(); bg.setShape(rs)
            var bgs = PathStyleProps(); bgs.fill = .string("red"); bg.useStyle(bgs)
            _ = group.add(bg)
            var cs = CircleShape(); cs.cx = 30; cs.cy = 30; cs.r = 20
            let c = Circle(); c.setShape(cs)
            var s = PathStyleProps(); s.fill = .string("#00ff00"); s.blend = blend; c.useStyle(s)
            _ = group.add(c)
            let img = try XCTUnwrap(renderToImage(group: group, size: CGSize(width: 60, height: 60), dpr: 1))
            return try pixelRGBA(img, 30, 30).r
        }
        // 'lighter' adds green onto the red bg → red channel stays high (→ yellow). source-over replaces
        // it → red channel drops to ~0 (→ green).
        XCTAssertGreaterThan(try redChannelOfDot("lighter"), 0.5, "additive blend keeps the red channel")
        XCTAssertLessThan(try redChannelOfDot(nil), 0.5, "source-over replaces red with green")
    }

    /// Read one pixel's straight (un-premultiplied via opaque-red assumption) RGBA in 0...1 from a
    /// CGImage by blitting it into a known RGBA8 buffer.
    private func pixelRGBA(_ image: CGImage, _ x: Int, _ y: Int)
        throws -> (r: Double, g: Double, b: Double, a: Double) {
        let w = image.width, h = image.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = try XCTUnwrap(CGContext(
            data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let i = (y * w + x) * 4
        return (Double(buf[i]) / 255, Double(buf[i + 1]) / 255,
                Double(buf[i + 2]) / 255, Double(buf[i + 3]) / 255)
    }
}
#endif
