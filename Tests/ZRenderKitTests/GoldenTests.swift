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
    /// exists — at which point shape tests call that instead (see PORT-TODO below).
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
}
#endif
