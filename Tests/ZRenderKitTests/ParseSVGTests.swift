// Proves the ported `parseSVG` (zrender/src/tool/parseSVG.ts) turns an SVG string into the expected
// zrender element tree: a <rect> → `Rect` with the right shape + fill, a <path> → `SVGPath`, a <circle>
// → `Circle`, a <polygon> → `Polygon`, transforms decoded onto the element, and `name` attrs collected
// into `result.named`.

import XCTest
@testable import ZRenderKit
import NativePainter

final class ParseSVGTests: XCTestCase {

    // Parse with ignoreViewBox/ignoreRootClip (as GeoSVGResource does) so `result.root` directly holds
    // the parsed children (no viewBox-wrapper group, no clip rect).
    private func parse(_ svg: String) -> SVGParserResult {
        return parseSVG(svg, SVGParserOption(ignoreViewBox: true, ignoreRootClip: true))
    }

    func test_rect_and_path_become_Rect_and_Path_with_geometry() throws {
        let svg = """
        <svg width="100" height="100" viewBox="0 0 100 100">
          <rect x="10" y="20" width="30" height="40" fill="#ff0000"/>
          <path d="M0 0 L10 0 L10 10 Z" stroke="#00ff00"/>
        </svg>
        """
        let result = parse(svg)
        let children = result.root.childrenRef()
        XCTAssertEqual(children.count, 2, "one <rect> + one <path>")

        // <rect> → Rect with the parsed shape + fill.
        let rect = try XCTUnwrap(children[0] as? Rect)
        let rectShape = try XCTUnwrap(rect.shape as? RectShape)
        XCTAssertEqual(rectShape.x, 10, accuracy: 1e-9)
        XCTAssertEqual(rectShape.y, 20, accuracy: 1e-9)
        XCTAssertEqual(rectShape.width, 30, accuracy: 1e-9)
        XCTAssertEqual(rectShape.height, 40, accuracy: 1e-9)
        if case let .string(fill)? = rect.pathStyle.fill {
            XCTAssertEqual(fill, "#ff0000")
        } else {
            XCTFail("expected a solid-color fill on the rect")
        }
        XCTAssertTrue(rect.silent, "shape elements are parsed silent")

        // <path> → SVGPath (createFromString), stroke set, no fill attribute → fill unset.
        let path = try XCTUnwrap(children[1] as? SVGPath)
        XCTAssertEqual(path.type, "path")
        if case let .string(stroke)? = path.pathStyle.stroke {
            XCTAssertEqual(stroke, "#00ff00")
        } else {
            XCTFail("expected a solid-color stroke on the path")
        }
        // No `fill` attribute → the path keeps zrender's default `#000` (SVG's default fill is also black),
        //   matching upstream parseSVG (it does not clear the default fill).
        if case let .string(fill)? = path.pathStyle.fill {
            XCTAssertEqual(fill, "#000")
        } else {
            XCTFail("expected the default solid fill on the path")
        }
    }

    func test_circle_and_polygon_geometry() throws {
        let svg = """
        <svg width="100" height="100">
          <circle cx="50" cy="60" r="15"/>
          <polygon points="0,0 10,0 10,10"/>
        </svg>
        """
        let result = parse(svg)
        let children = result.root.childrenRef()
        XCTAssertEqual(children.count, 2)

        let circle = try XCTUnwrap(children[0] as? Circle)
        let circleShape = try XCTUnwrap(circle.shape as? CircleShape)
        XCTAssertEqual(circleShape.cx, 50, accuracy: 1e-9)
        XCTAssertEqual(circleShape.cy, 60, accuracy: 1e-9)
        XCTAssertEqual(circleShape.r, 15, accuracy: 1e-9)

        let polygon = try XCTUnwrap(children[1] as? ZRenderKit.Polygon)
        let polyShape = try XCTUnwrap(polygon.shape as? PolygonShape)
        let points: [VectorArray] = try XCTUnwrap(polyShape.points)
        XCTAssertEqual(points.count, 3)
        XCTAssertEqual(points[1].x, 10, accuracy: 1e-9)
        XCTAssertEqual(points[2].y, 10, accuracy: 1e-9)
    }

    func test_transform_attribute_is_decoded_onto_the_element() throws {
        let svg = """
        <svg width="100" height="100">
          <rect x="0" y="0" width="10" height="10" transform="translate(15, 25)"/>
        </svg>
        """
        let result = parse(svg)
        let rect = try XCTUnwrap(result.root.childrenRef().first as? Rect)
        // translate(15,25) → local transform tx/ty decoded onto x/y.
        XCTAssertEqual(rect.x, 15, accuracy: 1e-9)
        XCTAssertEqual(rect.y, 25, accuracy: 1e-9)
    }

    func test_named_items_collected() throws {
        let svg = """
        <svg width="100" height="100">
          <rect name="alpha" x="0" y="0" width="10" height="10"/>
          <circle name="beta" cx="50" cy="50" r="5"/>
          <path d="M0 0 L1 1 Z"/>
        </svg>
        """
        let result = parse(svg)
        let names = result.named.map { $0.name }
        XCTAssertEqual(names, ["alpha", "beta"], "only named tags land in `named`")
        XCTAssertEqual(result.named[0].svgNodeTagLower, "rect")
        XCTAssertEqual(result.named[1].svgNodeTagLower, "circle")
    }

    func test_group_style_inheritance() throws {
        // fill declared on a <g> is inherited by a child that does not set its own fill.
        let svg = """
        <svg width="100" height="100">
          <g fill="#123456">
            <rect x="0" y="0" width="10" height="10"/>
          </g>
        </svg>
        """
        let result = parse(svg)
        let g = try XCTUnwrap(result.root.childrenRef().first as? Group)
        let rect = try XCTUnwrap(g.childrenRef().first as? Rect)
        if case let .string(fill)? = rect.pathStyle.fill {
            XCTAssertEqual(fill, "#123456", "child inherits the group fill")
        } else {
            XCTFail("expected inherited fill on the child rect")
        }
    }

    func test_group_opacity_is_applied_to_image() throws {
        let svg = """
        <svg width="100" height="100">
          <g opacity="0.6">
            <image href="data:image/png;base64,AA==" x="5" y="6" width="20" height="30"/>
          </g>
        </svg>
        """
        let result = parse(svg)
        let group = try XCTUnwrap(result.root.childrenRef().first as? Group)
        let image = try XCTUnwrap(group.childrenRef().first as? ZRImage)
        XCTAssertEqual(try XCTUnwrap(image.imageStyle.opacity), 0.6, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(image.imageStyle.x), 5, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(image.imageStyle.y), 6, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(image.imageStyle.width), 20, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(image.imageStyle.height), 30, accuracy: 1e-9)
    }

    func test_data_uri_image_decoder_accepts_wrapped_base64() throws {
        let wrappedPNG = """
        data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJ
        AAAADUlEQVR42mP8/5+hHgAHggJ/PshqCgAAAABJRU5ErkJggg==
        """
        let image = try XCTUnwrap(loadCGImage(wrappedPNG))
        XCTAssertEqual(image.width, 1)
        XCTAssertEqual(image.height, 1)
    }
}
