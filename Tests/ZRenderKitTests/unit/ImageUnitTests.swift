// Ported from zrender/test/ut/spec/graphic/Image.test.ts — keep in sync with upstream

import XCTest
@testable import ZRenderKit

// upstream uses a stand-in `HTMLImageElement { width; height }` as the image source. The Swift port
// models `image?: string | ImageLike` as `ImageStyleProps.image: ImageSource?` where `.image(ImageLike)`
// wraps an opaque native handle; `Image._getSize` reads its natural size through the `ImageNaturalSize`
// seam protocol. So the test source is a small struct conforming to `ImageNaturalSize`.
private struct FakeImageElement: ImageNaturalSize {
    var width: Double
    var height: Double
}

final class ImageUnitTests: XCTestCase {

    // upstream: it('Should get width and height from style by default')
    func test_Should_get_width_and_height_from_style_by_default() throws {
        let imgSource = FakeImageElement(width: 100, height: 100)
        var style = ImageStyleProps()
        style.width = 300
        style.height = 200
        style.image = .image(imgSource)
        let img = ZRImage(["style": style])

        let rect = img.getBoundingRect()
        XCTAssertEqual(rect?.width, 300)
        XCTAssertEqual(rect?.height, 200)
    }

    // upstream: it('Should get width with proper aspect')
    func test_Should_get_width_with_proper_aspect() throws {
        let imgSource = FakeImageElement(width: 100, height: 50)
        var style = ImageStyleProps()
        style.width = 300
        style.image = .image(imgSource)
        let img = ZRImage(["style": style])

        let rect = img.getBoundingRect()
        XCTAssertEqual(rect?.width, 300)
        XCTAssertEqual(rect?.height, 150)
    }

    // upstream: it('Should get height with proper aspect')
    func test_Should_get_height_with_proper_aspect() throws {
        let imgSource = FakeImageElement(width: 100, height: 50)
        var style = ImageStyleProps()
        style.height = 200
        style.image = .image(imgSource)
        let img = ZRImage(["style": style])

        let rect = img.getBoundingRect()
        XCTAssertEqual(rect?.width, 400)
        XCTAssertEqual(rect?.height, 200)
    }
}
