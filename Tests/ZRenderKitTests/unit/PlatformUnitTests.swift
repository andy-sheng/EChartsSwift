// Ported from zrender/test/ut/spec/core/platform.test.ts — keep in sync with upstream

import XCTest
@testable import ZRenderKit

// upstream test returns a `{ width: 1 } as HTMLCanvasElement`. `CanvasLike` is `Any` in the
// Swift port, so we use a concrete struct carrying `width` and downcast at the assertion site.
private struct FakeCanvas {
    var width: Double
}

// upstream calls `setPlatformAPI({ createCanvas, measureText })` — a partial override. The Swift
// `setPlatformAPI` replaces the whole `PlatformAPI` (see platform.swift PORT-NOTE), so we supply a
// full implementation that overrides createCanvas/measureText and stubs loadImage/getTime.
private final class OverridePlatformAPI: PlatformAPI {
    func createCanvas() -> CanvasLike? {
        return FakeCanvas(width: 1)
    }
    func measureText(_ text: String, _ font: String?) -> TextMetrics {
        return TextMetrics(width: 16.5)
    }
    func loadImage(
        _ src: String,
        _ onload: @escaping () -> Void,
        _ onerror: @escaping () -> Void
    ) -> ImageLike? {
        return nil
    }
    func getTime() -> Double {
        return 0
    }
}

final class PlatformUnitTests: XCTestCase {
    // Pin the NO-CANVAS fallback measurer for the duration of this class. These tests assert widths
    // derived from zrender's ASCII width table (upstream's behaviour when no canvas exists), but they
    // read the GLOBAL `platformApi` — and NativePainter now installs a Core Text measurer onto that
    // same global. Both test targets share one xctest process, so without this pin the assertions
    // would depend on whether a sibling target happened to install it first. Pinning keeps each test
    // measuring the implementation it was written for.
    private var _savedApi: PlatformAPI?
    override func setUp() {
        super.setUp()
        _savedApi = platformApi
        setPlatformAPI(DefaultPlatformAPI())
    }
    override func tearDown() {
        if let api = _savedApi { setPlatformAPI(api) }
        super.tearDown()
    }


    // upstream: it('Default font should be correct')
    func test_Default_font_should_be_correct() throws {
        XCTAssertEqual(DEFAULT_FONT_SIZE, 12)
        XCTAssertEqual(DEFAULT_FONT_FAMILY, "sans-serif")
        XCTAssertEqual(DEFAULT_FONT, "12px sans-serif")
    }

    // upstream: it('setPlatformAPI can override methods')
    func test_setPlatformAPI_can_override_methods() throws {
        let oldApi = platformApi
        setPlatformAPI(OverridePlatformAPI())

        XCTAssertEqual((platformApi.createCanvas() as? FakeCanvas)?.width, 1)
        XCTAssertEqual(platformApi.measureText("a", "12px sans-serif").width, 16.5)

        // Restore
        setPlatformAPI(oldApi)
    }

    // upstream: it('measureText should return correct width')
    func test_measureText_should_return_correct_width() throws {
        XCTAssertEqual(platformApi.measureText("A", "normal normal 18px sans-serif").width, 12.06)
    }
}
