// Ported from zrender/test/ut/spec/graphic/Text.test.ts — keep in sync with upstream

import XCTest
@testable import ZRenderKit

final class TextUnitTests: XCTestCase {

    // upstream: it('Text#useState should merge rich style property.')
    func test_Text_useState_should_merge_rich_style_property() throws {
        throw XCTSkip("States machinery is a Phase-2 stub: Element.useState() returns nil and does "
            + "not apply the state object, so useState('emphasis') does not merge emphasisState.style "
            + "into text.textStyle (Element.useState / ZRText._mergeStyle path). Additionally, "
            + "ensureState returns a typed ElementState whose `.style` cannot hold a TextStyleProps "
            + "rich bag. The whole assertion (text.style.rich.foo == {fill, stroke}) is "
            + "unreachable until the states machinery lands. (Element.swift / Text.swift PORT-NOTE)")
    }
}
