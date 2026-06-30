// TextBoundingRectTests.swift — regression for the ZRText.getBoundingRect() crash.
//
// `getBoundingRect()` walked its child TSpans calling `child.getLocalTransform(tmpMat)` with a
// scratch `tmpMat: MatrixArray = []` (empty). Upstream relies on JS auto-extending the array on
// `m[4] = …`; Swift arrays can't grow by subscript, so it trapped with "Index out of range". The
// `text` demo's "Show boundingRect" button (which calls getBoundingRect on every label) crashed.
// Fixed by normalizing an empty/short scratch to the 6-slot identity in getLocalTransform.

import XCTest
@testable import ZRenderKit

final class TextBoundingRectTests: XCTestCase {

    private func boundingRect(_ configure: (inout TextStyleProps) -> Void) -> BoundingRect? {
        var st = TextStyleProps(); configure(&st)
        let t = ZRText(); t.useStyle(st)
        return t.getBoundingRect()
    }

    func test_plain_multiline_does_not_crash() throws {
        let r = try XCTUnwrap(boundingRect {
            $0.text = "阴影阴影\nshadow"; $0.fill = "#456"; $0.font = "18px Arial"; $0.padding = .number(10)
        })
        XCTAssertGreaterThan(r.width, 0)
        XCTAssertGreaterThan(r.height, 0)
    }

    func test_transformed_text_does_not_crash() throws {
        var st = TextStyleProps()
        st.text = "rotated"; st.font = "18px Arial"
        let t = ZRText(); t.useStyle(st)
        t.rotation = -1; t.scaleX = 0.5; t.scaleY = 0.5; t.originX = 0; t.originY = 50
        XCTAssertNotNil(t.getBoundingRect(), "a transformed text's bounding rect must compute without trapping")
    }

    func test_empty_text_with_background() throws {
        // Empty text + background + 4-element padding (text demo spec 11).
        XCTAssertNotNil(boundingRect {
            $0.text = ""; $0.padding = .array([10, 20, 30, 40]); $0.backgroundColor = .string("rgba(124,0,123,0.4)")
        })
    }
}
