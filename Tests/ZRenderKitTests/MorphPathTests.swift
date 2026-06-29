// Regression: morphPath() drives a real `__morphT` 0→1 animation (was inert — `__morphT` was not
// wired into Path.animationGet/animationSet, so the morph animator was never created and the demo
// could only show a static source shape). Covers all 7 morphPath.html targets, including the
// multi-subpath SVG strings, to guard the morph animation lifecycle end to end.
import XCTest
@testable import ZRenderKit
#if canImport(QuartzCore) && canImport(CoreGraphics)
import CoreGraphics
import NativePainter
#endif

final class MorphPathTests: XCTestCase {

    private static let D1 = "M910.5,263.6C899.5,229,801.5-57.8,576.9,24.9c-36.9,19.3-65.7,83-52.9,124.4c13,42,85.6,44.7,111.1,16.5z M153.7,510.1c15,9,23.9,22.1,26.6,39.1C160.1,542,151.2,529,153.7,510.1z M224.6,535.5l27.2-27.8C263.5,537.6,254.4,546.9,224.6,535.5z"
    private static let D2 = "M0,6.792 C0,7.192 0.9,8.492 1.9,9.592 C2.9,10.792 4.9,15.892 6.3,20.992 C9.2,31.592 12.4,36.492 17.5,38.192 Z M70,15.592 C70,18.592 65.7,22.192 62.3,22.192 C61,22.192 59,22.692 57.9,23.192 Z"
    private static let D3 = "M0.38,5.94 C0.38,6.34 -0.28,17.75 4.32,31.15 C5.32,32.35 6.09,37.89 7.49,42.99 Z M64.79,22.86 C64.79,25.86 65.5,27.91 60.63,31.75 C59.59,32.58 64.0,30.28 62.9,30.78 Z"

    private func styledRed(_ p: Path) -> Path {
        var st = PathStyleProps(); st.fill = .string("red"); st.stroke = .string("red"); st.opacity = 0.5
        p.useStyle(st); return p
    }
    private func pathFromString(_ d: String, _ x: Double, _ y: Double, _ width: Double) -> Path {
        let path = createFromString(d)
        let r = path.getBoundingRect()!
        let m = r.calculateTransform(BoundingRect(x, y, width, width / r.width * r.height))
        path.applyTransform(m)
        return path
    }
    private func sevenTargets() -> [Path] {
        var rs = RectShape(); rs.x = 100; rs.y = 100; rs.width = 100; rs.height = 200
        let rect = Rect(); rect.setShape(rs)
        var cs = CircleShape(); cs.cx = 200; cs.cy = 200; cs.r = 90
        let circle = Circle(); circle.setShape(cs)
        var iso = IsogonShape(); iso.x = 200; iso.y = 200; iso.r = 100; iso.n = 6
        let isogon = Isogon(); isogon.setShape(iso)
        var sec = SectorShape(); sec.cx = 250; sec.cy = 200; sec.r0 = 50; sec.r = 100; sec.startAngle = 1; sec.endAngle = 3
        let sector = Sector(); sector.setShape(sec)
        return [rect, circle, isogon, sector,
                pathFromString(Self.D1, 100, 100, 200),
                pathFromString(Self.D2, 100, 100, 200),
                pathFromString(Self.D3, 100, 100, 200)].map(styledRed)
    }

    /// `__morphT` is now an animatable scalar: morphPath() creates one animator that tweens 0→1.
    func test_morphPath_creates_animator_and_tweens_morphT() throws {
        var rs = RectShape(); rs.x = 100; rs.y = 100; rs.width = 100; rs.height = 200
        let rect = Rect(); rect.setShape(rs)
        var cs = CircleShape(); cs.cx = 200; cs.cy = 200; cs.r = 90
        let circle = Circle(); circle.setShape(cs)

        var cfg = ElementAnimateConfig(); cfg.duration = 1000; cfg.easing = .named("linear")
        _ = morphPath(rect, circle, cfg)

        XCTAssertEqual(circle.animators.count, 1, "morphPath must create one __morphT animator (was 0 — inert)")
        let clip = try XCTUnwrap(circle.animators.first?.getClip(), "no morph clip")
        _ = clip.step(0, 0)
        XCTAssertEqual(circle.__morphT, 0.0, accuracy: 1e-9, "t=0 baseline")
        _ = clip.step(500, 500)
        XCTAssertEqual(circle.__morphT, 0.5, accuracy: 1e-6, "linear midpoint")
        _ = clip.step(1000, 500)
        XCTAssertEqual(circle.__morphT, 1.0, accuracy: 1e-9, "t=1 endpoint")
    }

    /// Every adjacent pair across the 7 html targets morphs + rebuilds geometry without crashing.
    func test_all_seven_targets_morph_without_crash() throws {
        let shapes = sevenTargets()
        var cfg = ElementAnimateConfig(); cfg.duration = 1000; cfg.easing = .named("cubicInOut")
        for i in 0..<shapes.count {
            let to = shapes[(i + 1) % shapes.count]
            _ = morphPath(shapes[i], to, cfg)
            let clip = try XCTUnwrap(to.animators.first?.getClip(), "pair \(i): inert morph track")
            _ = clip.step(0, 0)
            for t in stride(from: 0.0, through: 1000.0, by: 250.0) {
                _ = clip.step(t, 250)
                _ = to.getUpdatedPathProxy()   // forces __morphBuildPath at this t
                _ = to.getBoundingRect()
            }
            XCTAssertEqual(to.__morphT, 1.0, accuracy: 1e-9, "pair \(i): morph completes")
        }
    }
}
