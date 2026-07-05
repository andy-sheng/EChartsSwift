// Phase 32 regression tests — dataZoom DATA core (window calc + axis reset + series-data filter).
// Guards that a `dataZoom` component actually FILTERS the rendered series data to its window, that the
// processor self-gates to a no-op when no dataZoom is present, AND that an Int-literal `start`/`end`
// option coerces identically to a Double-literal one (the Int-vs-Double option-read trap).
import XCTest
import ZRenderKit
@testable import EChartsKit

final class ZZDataZoomTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // The dataZoom classes are registered by EChartsSlim.installOnce(); the series class is not.
        ComponentModel.registerClass(BarSeriesModel.self)
    }

    /// 10 categories c0..c9, series data [0..9], grid + category xAxis + value yAxis.
    /// `intLiterals` selects Int vs Double `start`/`end` to exercise numeric coercion.
    private func makeOption(withDataZoom: Bool, intLiterals: Bool) -> [String: Any] {
        let cats: [Any] = (0..<10).map { "c\($0)" }
        let data: [Any] = (0..<10).map { Double($0) }
        var opt: [String: Any] = [
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "category", "data": cats] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "bar", "data": data] as [String: Any]]
        ]
        if withDataZoom {
            let dz: [String: Any] = intLiterals
                ? ["xAxisIndex": 0, "start": 0, "end": 40]        // Int literals
                : ["xAxisIndex": 0, "start": 0.0, "end": 40.0]    // Double literals
            opt["dataZoom"] = [dz]
        }
        return opt
    }

    private func windowedCount(withDataZoom: Bool, intLiterals: Bool) -> Int {
        let ec = EChartsSlim(width: 400, height: 300)
        ec.setOption(makeOption(withDataZoom: withDataZoom, intLiterals: intLiterals))
        return ec.getModel()?.getSeriesByIndex(0)?.getData().count() ?? -1
    }

    // Test A: a 0~40% window on 10 categories must render only the leading subset, and an Int-literal
    // window must produce the SAME result as a Double-literal one.
    func testZoomFiltersData() {
        let doubleCount = windowedCount(withDataZoom: true, intLiterals: false)
        let intCount = windowedCount(withDataZoom: true, intLiterals: true)
        print("DATAZOOM windowed count double=\(doubleCount) int=\(intCount)")
        XCTAssertGreaterThan(doubleCount, 0, "zoom must keep at least one datum")
        XCTAssertLessThan(doubleCount, 10, "zoom must filter out some categories (not the full 10)")
        XCTAssertEqual(intCount, doubleCount,
            "Int-literal start/end must coerce to the same window as Double-literal (Int-vs-Double trap)")
    }

    // Test B: the SAME chart with NO dataZoom renders all 10 — proves the processor self-gates and there
    // is no regression when the component is absent.
    func testNoDataZoomGate() {
        let count = windowedCount(withDataZoom: false, intLiterals: false)
        print("DATAZOOM no-zoom count = \(count)")
        XCTAssertEqual(count, 10, "without dataZoom all 10 render (processor self-gates to a no-op)")
    }
}
