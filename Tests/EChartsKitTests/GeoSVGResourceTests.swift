// Proves the ported `GeoSVGResource` (echarts/src/coord/geo/GeoSVGResource.ts) builds a geo resource from
// an SVG string: `load()` exposes the SVG viewport bounding rect and the named-tag REGIONS (name → region),
// and a region's center is computed from its element bounding rect (GeoSVGRegion.calcCenter).

import XCTest
@testable import EChartsKit
@testable import ZRenderKit

final class GeoSVGResourceTests: XCTestCase {

    private let svg = """
    <svg width="200" height="120">
      <rect name="alpha" x="10" y="10" width="20" height="20" fill="#4e79a7"/>
      <circle name="beta" cx="120" cy="55" r="40" fill="#e15759"/>
      <path name="gamma" d="M150 100 L190 100 L170 20 Z" fill="#59a14f"/>
      <rect x="0" y="0" width="5" height="5"/>
    </svg>
    """

    func test_load_exposes_named_regions_and_bounding_rect() throws {
        let resource = GeoSVGResource("svgTest", svg)
        XCTAssertEqual(resource.type, "geoSVG")

        let loaded = resource.load(nil, nil)

        // boundingRect == the SVG viewport (0, 0, width, height).
        XCTAssertEqual(loaded.boundingRect.x, 0, accuracy: 1e-9)
        XCTAssertEqual(loaded.boundingRect.y, 0, accuracy: 1e-9)
        XCTAssertEqual(loaded.boundingRect.width, 200, accuracy: 1e-9)
        XCTAssertEqual(loaded.boundingRect.height, 120, accuracy: 1e-9)

        // Only the three NAMED tags are regions (the unnamed <rect> is not).
        let names = loaded.regions.map { $0.name }.sorted()
        XCTAssertEqual(names, ["alpha", "beta", "gamma"])

        // regionsMap resolves a name → region.
        XCTAssertNotNil(loaded.regionsMap.get("alpha"))
        XCTAssertNotNil(loaded.regionsMap.get("gamma"))
        XCTAssertNil(loaded.regionsMap.get("does-not-exist"))

        // Every region is a geoSVG region.
        for region in loaded.regions {
            XCTAssertEqual(region.type, "geoSVG")
        }
    }

    func test_region_center_from_element_bounding_rect() throws {
        let resource = GeoSVGResource("svgTest2", svg)
        let loaded = resource.load(nil, nil)
        let alpha = try XCTUnwrap(loaded.regionsMap.get("alpha"))
        // <rect x=10 y=10 w=20 h=20> → center (20, 20) in SVG-local coords.
        let center = alpha.getCenter()
        XCTAssertEqual(center[0], 20, accuracy: 1e-6)
        XCTAssertEqual(center[1], 20, accuracy: 1e-6)
    }

    func test_load_is_idempotent() throws {
        // A second load returns the same (cached) regions/boundingRect without rebuilding.
        let resource = GeoSVGResource("svgTest3", svg)
        let first = resource.load(nil, nil)
        let second = resource.load(nil, nil)
        XCTAssertEqual(first.regions.count, second.regions.count)
        XCTAssertEqual(first.boundingRect.width, second.boundingRect.width, accuracy: 1e-9)
    }
}
