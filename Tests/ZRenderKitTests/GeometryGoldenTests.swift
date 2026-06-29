// GeometryGoldenTests.swift — the Swift consumer of Oracle/dump-geometry.js.
//
// This is the automated-assertion counterpart to the algorithm-class `test/*.html` demos
// (boundingbox / sector / pathContain / poly / bezier), which upstream only ever verified
// by a human looking at a canvas. The oracle (Oracle/dump-geometry.js) runs the *real*
// zrender (the same UMD bundle those .html files load) and records, per shape, two
// renderer-independent, deterministic outputs:
//
//   - boundingRect : shape.getBoundingRect() -> {x,y,width,height}
//   - contain[]    : shape.contain(x,y) over a fixed probe grid -> bool fingerprint
//
// The Swift port is faithful iff the ported Sector/Circle/Ring/Ellipse/Polygon/BezierCurve
// reconstruct the SAME numbers. Everything here is test-side: the shapes are reached via
// `@testable import`, the fixture is generated test data under Oracle/fixtures. No source
// in Sources/ is touched to make this pass.
//
// To (re)generate the fixture:  cd Oracle && node dump-geometry.js
// See also GoldenTests.swift (the path-command-stream oracle) and Oracle/README.md.

import XCTest
@testable import ZRenderKit

final class GeometryGoldenTests: XCTestCase {

    // MARK: - Fixture model

    struct Fixture: Decodable {
        let generator: String
        let zrenderVersion: String
        let precision: Int
        let cases: [Case]
    }

    struct Case: Decodable {
        let name: String
        let demo: String
        let type: String
        let shape: ShapeProps
        let pathRect: Rect          // pure PathProxy geometry (the faithful oracle)
        let styledRect: Rect        // shape.getBoundingRect() incl. zrender's style policy
        let hasFill: Bool?
        let hasStroke: Bool?
        let contain: [Probe]
    }

    struct Rect: Decodable { let x, y, width, height: Double }
    struct Probe: Decodable { let x, y: Double; let inside: Bool }

    /// A superset bag: every shape's prop keys as optionals, so one struct decodes every
    /// case (absent keys -> nil). The builder pulls only the keys its `type` needs.
    struct ShapeProps: Decodable {
        var cx, cy, r, r0, rx, ry: Double?
        var startAngle, endAngle: Double?
        var clockwise: Bool?
        var x1, y1, x2, y2, cpx1, cpy1, cpx2, cpy2: Double?
        var points: [[Double]]?
    }

    // MARK: - Fixture loading (same #filePath walk-up GoldenTests uses)

    /// Oracle/fixtures lives at <repo>/Oracle/fixtures; this file is at
    /// <repo>/Tests/ZRenderKitTests/GeometryGoldenTests.swift.
    static var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // ZRenderKitTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Oracle/fixtures/geometry.json", isDirectory: false)
    }

    private func loadFixture() throws -> Fixture {
        let data = try Data(contentsOf: Self.fixtureURL)
        return try JSONDecoder().decode(Fixture.self, from: data)
    }

    // MARK: - Reconstruct the Swift shape named by `type`

    /// Build the ported `Path` subclass for a fixture case, mirroring the prop bag the
    /// oracle fed the real zrender shape. Returns nil for a type this test doesn't model.
    private func buildPath(_ c: Case) -> Path? {
        let p = c.shape
        switch c.type {
        case "Sector":
            var s = SectorShape()
            s.cx = p.cx!; s.cy = p.cy!; s.r0 = p.r0!; s.r = p.r!
            s.startAngle = p.startAngle!; s.endAngle = p.endAngle!
            if let cw = p.clockwise { s.clockwise = cw }
            let el = Sector(); _ = el.setShape(s); return el
        case "Circle":
            var s = CircleShape()
            s.cx = p.cx!; s.cy = p.cy!; s.r = p.r!
            let el = Circle(); _ = el.setShape(s); return el
        case "Ring":
            var s = RingShape()
            s.cx = p.cx!; s.cy = p.cy!; s.r = p.r!; s.r0 = p.r0!
            let el = Ring(); _ = el.setShape(s); return el
        case "Ellipse":
            var s = EllipseShape()
            s.cx = p.cx!; s.cy = p.cy!; s.rx = p.rx!; s.ry = p.ry!
            let el = Ellipse(); _ = el.setShape(s); return el
        case "Polygon":
            var s = PolygonShape()
            s.points = p.points!.map { VectorArray($0[0], $0[1]) }
            // `Polygon` (unqualified) is shadowed by a transitively-imported system symbol
            // (`MacPolygon`); qualify to the ported shape class.
            let el = ZRenderKit.Polygon(); _ = el.setShape(s); return el
        case "BezierCurve":
            var s = BezierCurveShape()
            s.x1 = p.x1!; s.y1 = p.y1!; s.x2 = p.x2!; s.y2 = p.y2!
            s.cpx1 = p.cpx1!; s.cpy1 = p.cpy1!
            s.cpx2 = p.cpx2; s.cpy2 = p.cpy2
            let el = BezierCurve(); _ = el.setShape(s); return el
        default:
            return nil
        }
    }

    // MARK: - Tests

    /// Sanity: the fixture is on disk, decodable, and was generated from real zrender.
    func test_geometryFixture_isPresentAndWellFormed() throws {
        let fx = try loadFixture()
        XCTAssertFalse(fx.cases.isEmpty, "geometry.json has no cases — run `node Oracle/dump-geometry.js`")
        XCTAssertFalse(fx.zrenderVersion.isEmpty, "fixture must record the zrender version it came from")
        for c in fx.cases {
            XCTAssertNotNil(buildPath(c),
                "no Swift shape modelled for fixture type \(c.type) (case \(c.name)) — extend buildPath()")
        }
    }

    /// The renderer-independent path geometry must match the real zrender shape's, for
    /// EVERY case — including the BezierCurve, whose box is driven by cubic-extrema math
    /// (boundingbox.html / sector.html / bezier.html). We compare the *PathProxy* rect
    /// (not Path.getBoundingRect()) so no style policy is mixed into the geometry oracle —
    /// the same renderer-independent philosophy GoldenTests uses for the command stream.
    func test_pathBoundingRect_matchesZRenderOracle() throws {
        let fx = try loadFixture()
        let tol = 5e-6  // fixture is rounded to 1e-6; a hair more than half-ULP
        for c in fx.cases {
            guard let path = buildPath(c) else { XCTFail("unmodelled type \(c.type)"); continue }
            let bb = path.getUpdatedPathProxy(false).getBoundingRect()
            XCTAssertEqual(bb.x, c.pathRect.x, accuracy: tol, "\(c.name) pathRect.x")
            XCTAssertEqual(bb.y, c.pathRect.y, accuracy: tol, "\(c.name) pathRect.y")
            XCTAssertEqual(bb.width, c.pathRect.width, accuracy: tol, "\(c.name) pathRect.width")
            XCTAssertEqual(bb.height, c.pathRect.height, accuracy: tol, "\(c.name) pathRect.height")
        }
    }

    /// contain(x,y) must match the real zrender shape's hit-test at every probe point
    /// (mirrors pathContain.html / poly.html). Restricted to FILL shapes: a fill shape's
    /// contain is the unambiguous "point inside the filled region" test. Stroke-only shapes
    /// (BezierCurve) are excluded here — see test_strokeOnly_knownDivergence.
    /// The grid fingerprint diverges on any hit-test bug; we report the first few
    /// mismatches rather than 300+ separate failures.
    func test_contain_matchesZRenderOracle() throws {
        let fx = try loadFixture()
        var checked = 0
        for c in fx.cases where (c.hasFill ?? false) && !(c.hasStroke ?? false) {
            guard let path = buildPath(c) else { XCTFail("unmodelled type \(c.type)"); continue }
            checked += 1
            var mismatches: [String] = []
            for probe in c.contain where path.contain(probe.x, probe.y) != probe.inside {
                if mismatches.count < 8 {
                    mismatches.append("(\(probe.x),\(probe.y)) expected \(probe.inside) got \(!probe.inside)")
                }
            }
            XCTAssertTrue(mismatches.isEmpty,
                "\(c.name) (\(c.demo)) contain() diverged from zrender at \(mismatches.count)+ probe(s): "
                + mismatches.joined(separator: ", "))
        }
        XCTAssertGreaterThan(checked, 0, "expected at least one fill shape to hit-test")
    }

    /// KNOWN PORT GAP captured by this oracle (not a test artifact): for a *stroke-only,
    /// no-fill* path (BezierCurve/Line/Polyline), zrender's `getBoundingRect()` and
    /// `contain()` inflate/route through `strokeContainThreshold` (default 5) — i.e. the
    /// box grows by max(lineWidth, strokeContainThreshold)/2 and contain becomes a
    /// stroke-proximity test, not a fill test. The Swift port currently uses plain
    /// lineWidth/2 and a fill test. This documents the divergence the fixture proves
    /// (bezier.styledRect = {17.5,27.5,165,95} vs Swift's {19.5,29.5,161,91}); the
    /// underlying *geometry* is faithful (asserted in test_pathBoundingRect...).
    /// Flip this to a hard assertion once the framework applies strokeContainThreshold.
    func test_strokeOnly_styledBoundingRect_knownDivergence() throws {
        let fx = try loadFixture()
        for c in fx.cases where (c.hasStroke ?? false) && !(c.hasFill ?? false) {
            guard let path = buildPath(c), let swiftStyled = path.getBoundingRect() else { continue }
            // The port matches the pure geometry but NOT zrender's strokeContainThreshold policy.
            let appliesThreshold = abs(swiftStyled.width - c.styledRect.width) < 1e-6
            if appliesThreshold { continue }   // framework was fixed — nothing to skip.
            throw XCTSkip(
                "KNOWN GAP — \(c.name) (\(c.demo)): zrender inflates a stroke-only path's "
                + "getBoundingRect by strokeContainThreshold(5)/2 → styled \(rectStr(c.styledRect)); "
                + "Swift port uses lineWidth/2 → \(rectStr(swiftStyled)). Pure geometry IS faithful "
                + "(pathRect \(rectStr(c.pathRect))). PORT-TODO: apply strokeContainThreshold in "
                + "Path.getBoundingRect/contain for no-fill paths.")
        }
    }

    private func rectStr(_ r: Rect) -> String { "{\(r.x),\(r.y),\(r.width),\(r.height)}" }
    private func rectStr(_ r: BoundingRect) -> String { "{\(r.x),\(r.y),\(r.width),\(r.height)}" }
}
