import XCTest
@testable import ZRenderKit

final class StorageAttachedTextZOrderTests: XCTestCase {
    func testAttachedTextPreservesAuthoredZ2() {
        var shape = RectShape()
        shape.width = 20
        shape.height = 20
        let host = Rect()
        host.setShape(shape)
        host.z2 = 2

        let label = ZRText()
        label.z2 = 10
        var style = TextStyleProps()
        style.text = "0"
        label.useStyle(style)
        host.setTextContent(label)

        let storage = Storage()
        storage.addRoot(host)
        let displayList = storage.getDisplayList(true, true)

        let glyph = displayList.first { $0 is TSpan }
        XCTAssertNotNil(glyph)
        XCTAssertEqual(glyph?.z2, 10, "attached text must keep its label z2 instead of inheriting host z2")
        XCTAssertGreaterThan(glyph?.z2 ?? -.infinity, host.z2)
    }
}
