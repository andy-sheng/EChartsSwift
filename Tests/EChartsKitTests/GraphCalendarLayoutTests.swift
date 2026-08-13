import XCTest
@testable import EChartsKit

final class GraphCalendarLayoutTests: XCTestCase {
    func testGraphKeepsCalendarCoordinateSystemAndLaysOutDateNodes() {
        let ec = ECharts(width: 640, height: 420)
        ec.setOption([
            "animation": false,
            "calendar": [[
                "orient": "vertical", "cellSize": 40.0, "range": "2017-02"
            ] as [String: Any]],
            "series": [[
                "type": "graph", "coordinateSystem": "calendar", "calendarIndex": 0.0,
                "edgeSymbol": ["none", "arrow"], "edgeSymbolSize": 10.0,
                "data": [["2017-02-01", 260.0], ["2017-02-04", 200.0]],
                "links": [["source": 0.0, "target": 1.0]]
            ] as [String: Any]]
        ])

        guard let series = ec.getModel()?.getSeriesByIndex(0) as? GraphSeriesModel else {
            return XCTFail("missing graph series")
        }
        XCTAssertTrue(series.coordinateSystem is EChartsKit.Calendar)
        let data = series.getData()
        for i in 0..<data.count() {
            guard let point = data.getItemLayout(i) as? [Double], point.count >= 2 else {
                return XCTFail("missing graph node layout at index \(i)")
            }
            let time = data.get("time", i)
            let value = data.get("value", i)
            XCTAssertTrue(point[0].isFinite && point[1].isFinite,
                          "layout=\(point), dims=\(data.dimensions), time=\(String(describing: time)), value=\(String(describing: value))")
            XCTAssertNotNil(data.getItemGraphicEl(i), "calendar graph node should render")
        }

        let displayList = ec.getStorage().getDisplayList(true)
        XCTAssertTrue(displayList.contains { $0.name == "to" },
                      "graph edgeSymbol arrow should render at the target endpoint")
    }
}
