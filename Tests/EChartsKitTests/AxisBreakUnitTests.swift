// Behavioral oracle for the value-axis BREAK core:
//   - scale/breakImpl.swift (BreakScaleMapper composition): removing a [start,end] interval from a
//     value axis and compressing it to `gap`, so values above the break shift down.
//   - component/axis/axisBreakMarker.swift: the zigzag break-marker glyph at the break position.
//   - end-to-end wiring: an `yAxis.breaks` option flows through createScaleByModel →
//     retrieveAxisBreaksOption → the scale's brk → AxisView draws the marker.
//
// The mapping numbers are derived from upstream `breakImpl.ts` transformIn/transformOut:
//   extent [0, 200], break {start:50, end:150, gap:10} (absolute).
//   transformIn (a.k.a. "elapse") compresses the [50,150] span (100) to 10:
//     transformIn(0)=0, transformIn(50)=50, transformIn(100)=55, transformIn(150)=60, transformIn(200)=110.
//   So the break-elapsed linear extent is [0, 110] and normalize(v) = transformIn(v)/110.

import XCTest
import ZRenderKit
@testable import EChartsKit

final class AxisBreakUnitTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Register the concrete break helper (idempotent). Also done by EChartsSlim.installOnce, but
        // the direct-scale tests below do not go through the slim driver.
        installScaleBreakHelper()
    }

    // MARK: - Scale core: normalize / scale with a value break

    private func makeBrokenIntervalScale() -> IntervalScale {
        let brk = AxisBreakOption(start: 50, end: 150, gap: 10, isExpanded: nil)
        let scale = IntervalScale(IntervalScaleSetting(breakOption: [brk]))
        scale.setExtent(0, 200)
        return scale
    }

    func testBreakScaleMapperIsInstalled() {
        let scale = makeBrokenIntervalScale()
        XCTAssertNotNil(scale.brk, "a scale created with a `breaks` option must have a BreakScaleMapper")
        XCTAssertTrue(hasBreaks(scale), "hasBreaks(scale) must be true when a break exists")
        XCTAssertEqual(getBreaksUnsafe(scale).count, 1)
        // gapReal for an absolute gap is exactly the parsed gap value.
        XCTAssertEqual(getBreaksUnsafe(scale)[0].gapReal ?? .nan, 10, accuracy: 1e-9)
        XCTAssertEqual(getBreaksUnsafe(scale)[0].vmin, 50, accuracy: 1e-9)
        XCTAssertEqual(getBreaksUnsafe(scale)[0].vmax, 150, accuracy: 1e-9)
    }

    func testNormalizeSkipsTheBrokenInterval() {
        let scale = makeBrokenIntervalScale()
        // Below the break.
        XCTAssertEqual(scale.normalize(0), 0.0, accuracy: 1e-9)
        XCTAssertEqual(scale.normalize(50), 50.0 / 110.0, accuracy: 1e-9)
        // Inside the break: the whole [50,150] span collapses onto the tiny gap; the midpoint (100)
        // lands at the middle of the compressed gap, NOT the middle of the raw span.
        XCTAssertEqual(scale.normalize(100), 55.0 / 110.0, accuracy: 1e-9)
        XCTAssertEqual(scale.normalize(150), 60.0 / 110.0, accuracy: 1e-9)
        // Above the break: shifted down (200 maps to the axis end, not off the top).
        XCTAssertEqual(scale.normalize(200), 1.0, accuracy: 1e-9)

        // The break compresses the axis: the [50,150] value span (half the raw range) occupies only
        // 10/110 of the axis, so a value just above the break sits far below where it would with no break.
        let noBreak = IntervalScale()
        noBreak.setExtent(0, 200)
        XCTAssertEqual(noBreak.normalize(150), 0.75, accuracy: 1e-9, "sanity: without a break, 150 → 0.75")
        XCTAssertLessThan(scale.normalize(150), 0.6, "with the break, 150 is pulled far down")
    }

    func testScaleIsInverseOfNormalize() {
        let scale = makeBrokenIntervalScale()
        // `scale(normalize(v)) == v` for values outside the break (inside-break points are many-to-one).
        for v in [0.0, 25.0, 50.0, 160.0, 200.0] {
            XCTAssertEqual(scale.scale(scale.normalize(v)), v, accuracy: 1e-6, "round-trip for \(v)")
        }
        // The middle of the compressed gap maps back into the [50,150] interval.
        let mid = scale.scale(55.0 / 110.0)
        XCTAssertGreaterThanOrEqual(mid, 50)
        XCTAssertLessThanOrEqual(mid, 150)
    }

    func testNonBrokenScaleStaysByteIdentical() {
        // A scale with NO breaks must behave exactly like a plain linear scale even after the helper
        // is installed (brk stays nil).
        let scale = IntervalScale()
        scale.setExtent(0, 200)
        XCTAssertNil(scale.brk)
        XCTAssertFalse(hasBreaks(scale))
        XCTAssertEqual(scale.normalize(50), 0.25, accuracy: 1e-12)
        XCTAssertEqual(scale.normalize(100), 0.5, accuracy: 1e-12)
        XCTAssertEqual(scale.scale(0.5), 100, accuracy: 1e-12)
    }

    // MARK: - Break marker glyph

    func testBreakMarkerBuiltAtBreakMidpoint() {
        let scale = makeBrokenIntervalScale()
        // A 400px axis; onBand=false (value axis).
        let axis = Axis("x", scale, [0, 400])
        let group = Group()
        var style = PathStyleProps()
        style.stroke = .string("#333")
        style.lineWidth = 1

        let markers = buildAxisBreakMarker(axis, group, nil, style)

        XCTAssertEqual(markers.count, 1, "one break → one marker glyph")
        guard let marker = markers.first else { return }
        // It was added to the group.
        XCTAssertTrue(group.children().contains { $0 === marker })
        // Zigzag has 4 points, centered at the break's pixel midpoint.
        let pts = (marker.shape as? PolylineShape)?.points
        XCTAssertEqual(pts?.count, 4)
        if let pts = pts, pts.count == 4 {
            let cMin = axis.dataToCoord(50)   // ~181.8
            let cMax = axis.dataToCoord(150)  // ~218.2
            let expectedMid = (cMin + cMax) / 2
            let markerMid = (pts[0][0] + pts[3][0]) / 2
            XCTAssertEqual(markerMid, expectedMid, accuracy: 1e-6, "marker centered on the break midpoint")
        }
        // Stroke-only: the default black fill must have been cleared.
        XCTAssertNil(marker.pathStyle.fill, "break marker must be stroke-only (no fill)")
    }

    func testNoMarkerWhenNoBreaks() {
        let scale = IntervalScale()
        scale.setExtent(0, 200)
        let axis = Axis("x", scale, [0, 400])
        let group = Group()
        let markers = buildAxisBreakMarker(axis, group, nil, PathStyleProps())
        XCTAssertEqual(markers.count, 0)
        XCTAssertEqual(group.childCount(), 0, "non-broken axis adds nothing")
    }

    // MARK: - End-to-end (the minimal demo): an `yAxis.breaks` option renders a marker

    func testYAxisBreaksOptionRendersMarkerEndToEnd() {
        ComponentModel.registerClass(ScatterSeriesModel.self)

        let option: [String: Any] = [
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "value"] as [String: Any],
            "yAxis": [
                "type": "value",
                "min": 0.0,
                "max": 200.0,
                // The break: hide the empty [50,150] band so the outlier at 180 sits close to the cluster.
                "breaks": [["start": 50.0, "end": 150.0, "gap": 10.0] as [String: Any]]
            ] as [String: Any],
            "series": [[
                "type": "scatter",
                "data": [[1.0, 10.0], [2.0, 30.0], [3.0, 180.0]]  // 180 is an outlier above the break
            ] as [String: Any]]
        ]

        let ec = EChartsSlim(width: 400, height: 300)
        ec.setOption(option)

        var markerFound = false
        _ = ec.getRoot().traverse { el in
            if let anid = el.anid, anid.hasPrefix("break_marker") {
                markerFound = true
            }
            return false
        }
        XCTAssertTrue(markerFound, "a value axis with `breaks` must render a break-marker glyph end-to-end")
    }
}
