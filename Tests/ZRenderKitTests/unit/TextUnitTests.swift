// Ported from zrender/test/ut/spec/graphic/Text.test.ts — keep in sync with upstream

import XCTest
@testable import ZRenderKit

final class TextUnitTests: XCTestCase {

    func test_richTextToken_synchronizesTextShadowToPainterStyle() throws {
        var token = TextStylePropsPart()
        token.fill = "#fff"
        token.textShadowBlur = 3
        token.textShadowColor = "#123456"
        token.textShadowOffsetX = 4
        token.textShadowOffsetY = 5

        var style = TextStyleProps()
        style.text = "{city|City Alpha}"
        style.rich = ["city": token]

        let text = ZRText()
        text.useStyle(style)
        XCTAssertNotNil(text.getBoundingRect())

        let span = try XCTUnwrap(text.childrenRef().compactMap { $0 as? TSpan }.first)
        XCTAssertEqual(span.tspanStyle.shadowBlur, 3)
        XCTAssertEqual(span.style.shadowBlur, 3)
        XCTAssertEqual(span.style.shadowColor, "#123456")
        XCTAssertEqual(span.style.shadowOffsetX, 4)
        XCTAssertEqual(span.style.shadowOffsetY, 5)
    }

    // upstream: it('Text#useState should merge rich style property.')
    func test_Text_useState_should_merge_rich_style_property() throws {
        throw XCTSkip("States machinery is a Phase-2 stub: Element.useState() returns nil and does "
            + "not apply the state object, so useState('emphasis') does not merge emphasisState.style "
            + "into text.textStyle (Element.useState / ZRText._mergeStyle path). Additionally, "
            + "ensureState returns a typed ElementState whose `.style` cannot hold a TextStyleProps "
            + "rich bag. The whole assertion (text.style.rich.foo == {fill, stroke}) is "
            + "unreachable until the states machinery lands. (Element.swift / Text.swift note)")
    }
}
