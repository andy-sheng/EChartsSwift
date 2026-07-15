// Tests for the ported data processors:
//   - processor/dataSample.swift  (lttb / minmax / average / sum / max / min / nearest down-sampling)
//   - processor/negativeDataFilter.swift  (pie drops negative-value data)
//
// Two layers: (1) the pure per-bucket sampler functions (`dataSampleSamplers`), and (2) the wired
// processor driven end-to-end through ECharts (a cartesian line series with `sampling`).

import XCTest
import ZRenderKit
@testable import EChartsKit

final class DataSampleProcessorTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Re-register the real models (global registry may hold doubles from other suites).
        ComponentModel.registerClass(LineSeriesModel.self)
        ComponentModel.registerClass(PieSeriesModel.self)
    }

    // MARK: - (1) Pure per-bucket samplers

    // max-sampling picks the per-bucket maximum; the other reducers mirror upstream `samplers`.
    func testSamplersReduceEachBucket() {
        let frame: [ParsedValue] = [1.0, 5.0, 3.0, 2.0]
        XCTAssertEqual(dataSampleSamplers["max"]!(frame), 5.0, "max picks the bucket maximum")
        XCTAssertEqual(dataSampleSamplers["min"]!(frame), 1.0, "min picks the bucket minimum")
        XCTAssertEqual(dataSampleSamplers["sum"]!(frame), 11.0, "sum totals the bucket")
        XCTAssertEqual(dataSampleSamplers["average"]!(frame), 11.0 / 4.0, "average is the bucket mean")
        XCTAssertEqual(dataSampleSamplers["nearest"]!(frame), 1.0, "nearest returns the first element")
    }

    // NaN handling mirrors upstream: average/max/min ignore NaN; sum treats NaN as 0; an all-NaN
    // bucket yields NaN for average/max/min (which would otherwise produce an illegal axis extent).
    func testSamplersNaNHandling() {
        let mixed: [ParsedValue] = [Double.nan, 4.0, 2.0]
        XCTAssertEqual(dataSampleSamplers["average"]!(mixed), 3.0, "average skips NaN")
        XCTAssertEqual(dataSampleSamplers["max"]!(mixed), 4.0, "max skips NaN")
        XCTAssertEqual(dataSampleSamplers["min"]!(mixed), 2.0, "min skips NaN")
        XCTAssertEqual(dataSampleSamplers["sum"]!(mixed), 6.0, "sum treats NaN as 0")

        let allNaN: [ParsedValue] = [Double.nan, Double.nan]
        XCTAssertTrue(dataSampleSamplers["average"]!(allNaN).isNaN, "all-NaN average is NaN")
        XCTAssertTrue(dataSampleSamplers["max"]!(allNaN).isNaN, "all-NaN max is NaN (not -Infinity)")
        XCTAssertTrue(dataSampleSamplers["min"]!(allNaN).isNaN, "all-NaN min is NaN (not +Infinity)")
    }

    // MARK: - Helpers

    private static let bigCount = 10000

    /// A cartesian line chart with `bigCount` points on a value x-axis. `sampling` is optional.
    private func lineOption(sampling: String?, gridWidth: Double = 300) -> [String: Any] {
        var data: [[Double]] = []
        data.reserveCapacity(DataSampleProcessorTests.bigCount)
        for i in 0..<DataSampleProcessorTests.bigCount {
            // A deterministic wiggly signal with a clear global max/min in the middle.
            let x = Double(i)
            let y = sin(x * 0.01) * 50 + (i == 5000 ? 1000.0 : 0.0)
            data.append([x, y])
        }
        var series: [String: Any] = ["type": "line", "data": data, "showSymbol": false]
        if let sampling = sampling { series["sampling"] = sampling }
        return [
            "grid": ["left": 40.0, "top": 20.0, "width": gridWidth, "height": 200.0] as [String: Any],
            "xAxis": ["type": "value"] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [series]
        ]
    }

    /// Render the option and return the (post-processing) point count of the first series.
    private func renderedSeriesDataCount(_ option: [String: Any]) -> Int {
        let ec = ECharts(width: 480, height: 320)
        ec.setOption(option)
        var count = -1
        ec.getModel()?.eachSeries { s, _ in if count < 0 { count = s.getData().count() } }
        return count
    }

    /// Number of points on the rendered line ECPolyline (the actual drawn envelope). The faithful port
    ///   stores points as a FLAT `[x0,y0,x1,y1,…]` buffer, so the datum count is `points.count / 2`.
    private func polylinePointCount(_ ec: ECharts) -> Int {
        var n = 0
        _ = ec.getRoot().traverse { el in
            if let p = el as? ECPolyline, p.name == "line", let s = p.shape as? ECPolylineShape {
                n = s.points.count / 2
            }
            return false
        }
        return n
    }

    // MARK: - (2) Wired processor, end-to-end

    // sampling unset → data is untouched (all bigCount points survive, both in data and on-screen).
    func testSamplingUnsetLeavesDataUntouched() {
        let count = renderedSeriesDataCount(lineOption(sampling: nil))
        XCTAssertEqual(count, DataSampleProcessorTests.bigCount, "no sampling keeps every point")

        let ec = ECharts(width: 480, height: 320)
        ec.setOption(lineOption(sampling: nil))
        XCTAssertEqual(polylinePointCount(ec), DataSampleProcessorTests.bigCount,
                       "polyline draws every point when sampling is unset")
    }

    // sampling:"lttb" → data downsampled to roughly the base-axis pixel width (dpr=1), and the
    // extreme (envelope) points are preserved (lttb always keeps the first and last datum).
    func testLttbDownsamplesToPixelWidthPreservingEnvelope() {
        let gridWidth = 300.0
        let ec = ECharts(width: 480, height: 320)
        ec.setOption(lineOption(sampling: "lttb", gridWidth: gridWidth))

        var data: SeriesData?
        ec.getModel()?.eachSeries { s, _ in if data == nil { data = s.getData() } }
        guard let data = data else { XCTFail("no series data"); return }

        let count = data.count()
        XCTAssertLessThan(count, DataSampleProcessorTests.bigCount / 10,
                          "lttb dramatically reduces the point count")
        // Roughly the pixel width: rate = round(N / (~width*dpr)); bucket count ≈ N / frameSize.
        XCTAssertGreaterThan(count, 100, "count stays near the pixel width")
        XCTAssertLessThan(count, 700, "count stays near the pixel width")

        // Envelope preserved: first & last x retained, and the global spike (y≈1000 at x=5000) survives.
        let firstX = data.get("x", 0) as? Double ?? .nan
        let lastX = data.get("x", count - 1) as? Double ?? .nan
        XCTAssertEqual(firstX, 0.0, "lttb keeps the first datum")
        XCTAssertEqual(lastX, Double(DataSampleProcessorTests.bigCount - 1), "lttb keeps the last datum")

        var maxY = -Double.infinity
        for i in 0..<count { maxY = max(maxY, data.get("y", i) as? Double ?? -.infinity) }
        XCTAssertGreaterThan(maxY, 900, "the global spike is preserved through lttb")

        // The drawn polyline matches the downsampled data.
        XCTAssertEqual(polylinePointCount(ec), count, "polyline draws the downsampled points")
    }

    // average / max sampling reduce the count deterministically (identical across independent renders)
    // and to about the pixel width.
    func testBucketSamplingIsDeterministicAndReduces() {
        for kind in ["average", "max"] {
            let opt = lineOption(sampling: kind, gridWidth: 200)
            let a = renderedSeriesDataCount(opt)
            let b = renderedSeriesDataCount(opt)
            XCTAssertEqual(a, b, "\(kind) sampling is deterministic")
            XCTAssertLessThan(a, DataSampleProcessorTests.bigCount / 10, "\(kind) sampling reduces the count")
            XCTAssertGreaterThan(a, 100, "\(kind) count near the pixel width")
        }
    }

    // Too-few-points guard: a small line series with `sampling` set is left untouched (count <= 10).
    func testSmallSeriesNotSampled() {
        let ec = ECharts(width: 480, height: 320)
        ec.setOption([
            "grid": ["left": 40.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "value"] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "line", "sampling": "lttb",
                        "data": [[0.0, 1.0], [1.0, 2.0], [2.0, 3.0]]] as [String: Any]]
        ])
        var count = -1
        ec.getModel()?.eachSeries { s, _ in if count < 0 { count = s.getData().count() } }
        XCTAssertEqual(count, 3, "a tiny series is never downsampled")
    }

    // MARK: - negativeDataFilter (pie)

    // A pie with a negative datum drops that slice (isNumber && < 0), keeping the rest.
    func testNegativeDataFilterDropsNegativePieSlices() {
        let ec = ECharts(width: 400, height: 300)
        ec.setOption([
            "series": [["type": "pie", "radius": "60%",
                        "data": [
                            ["value": 30.0, "name": "A"] as [String: Any],
                            ["value": -5.0, "name": "B"] as [String: Any],
                            ["value": 20.0, "name": "C"] as [String: Any]
                        ]] as [String: Any]]
        ])
        var count = -1
        ec.getModel()?.eachSeries { s, _ in if count < 0 { count = s.getData().count() } }
        XCTAssertEqual(count, 2, "the negative-value pie slice is filtered out")
    }
}
