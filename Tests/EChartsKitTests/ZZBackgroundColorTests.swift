// ZZBackgroundColorTests — the top-level `option.backgroundColor` must actually be that colour.
//
// It was not. ECharts.swift painted the background rect with `"style": ["fill": bg]` — a
// `[String: Any]`. But `Path`'s prop init casts style as `value as? PathStyleProps`, and a dictionary
// is not a `PathStyleProps`, so the cast yielded nil, the rect got an EMPTY style, and an empty path
// style falls back to zrender's default fill of `#000`. Every chart with a top-level backgroundColor
// was drawn on BLACK regardless of the option: `#fff` came out black, the maps' `#404a59` came out
// black. In the official-examples parity sweep it was the single biggest source of divergence — a
// dozen demos sat at 25-93% pixel difference purely because of it.
//
// The test reads the painted background rect back and asserts its fill is the requested colour, not
// the default black.

import XCTest
@testable import EChartsKit
import ZRenderKit

final class ZZBackgroundColorTests: XCTestCase {

    /// Walk the rendered scene for the silent full-canvas background rect ECharts inserts at
    /// z2 = -greatestFiniteMagnitude, and return its fill.
    @MainActor
    private func backgroundFill(_ option: [String: Any]) -> ZRenderKit.ZRColor? {
        let ec = ECharts(width: 200, height: 150)
        ec.setOption(option)
        var found: ZRenderKit.ZRColor?
        _ = ec.getRoot().traverse { el in
            guard found == nil, let rect = el as? Rect, el.silent else { return false }
            // The background rect is the one that fills the whole canvas.
            if let s = rect.shape as? RectShape, s.width >= 200, s.height >= 150 {
                found = rect.pathStyle?.fill
            }
            return false
        }
        return found
    }

    private func hex(_ c: ZRenderKit.ZRColor?) -> String? {
        if case let .string(s)? = c { return s.lowercased() }
        return nil
    }

    private var barOption: [String: Any] {
        [
            "xAxis": ["type": "category", "data": ["a", "b"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "bar", "data": [1.0, 2.0]] as [String: Any]]
        ]
    }

    @MainActor
    func testWhiteBackgroundIsWhiteNotBlack() {
        var opt = barOption
        opt["backgroundColor"] = "#fff"
        XCTAssertEqual(hex(backgroundFill(opt)), "#fff",
                       "a `#fff` backgroundColor must paint white — the bug painted it black")
    }

    @MainActor
    func testDarkMapBackgroundIsItsColourNotBlack() {
        var opt = barOption
        opt["backgroundColor"] = "#404a59"   // the geo/map demos' dark blue
        XCTAssertEqual(hex(backgroundFill(opt)), "#404a59")
    }

    @MainActor
    func testNoBackgroundColorPaintsNoRect() {
        // Absent → no rect at all (the host clear shows through). Must not fabricate a black one.
        XCTAssertNil(backgroundFill(barOption),
                     "with no backgroundColor there must be no background rect, not a default-black one")
    }
}
