// Regression tests for the parseText layout engine (graphic/helper/parseText.ts port).
// Uses a monospace font so the platform fallback measurer is exact: width = fontSize * charCount
// (see Core/platform.swift measureText — `font.contains("mono")` ⇒ fontSize * utf16.count).

import XCTest
@testable import ZRenderKit

final class ParseTextTests: XCTestCase {
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


    // 12px monospace ⇒ every ASCII char is exactly 12pt wide.
    private let MONO = "12px monospace"
    private let CW: Double = 12   // char width

    private func plainStyle(
        width: Double? = nil,
        height: Double? = nil,
        overflow: String? = nil,
        lineOverflow: String? = nil,
        ellipsis: String? = nil,
        truncateMinChar: Double? = nil,
        placeholder: String? = nil,
        lineHeight: Double? = nil
    ) -> TextStyleProps {
        var s = TextStyleProps()
        s.font = MONO
        s.width = width
        s.height = height
        s.overflow = overflow
        s.lineOverflow = lineOverflow
        s.ellipsis = ellipsis
        s.truncateMinChar = truncateMinChar
        s.placeholder = placeholder
        s.lineHeight = lineHeight
        return s
    }

    // MARK: - plain text: no overflow

    func test_plainText_splitsOnNewline_noWidth() {
        let block = parseText.parsePlainText("ab\ncde", plainStyle(), nil, nil)
        XCTAssertEqual(block.lines, ["ab", "cde"])
        XCTAssertEqual(block.contentWidth, 3 * CW, accuracy: 0.001)   // widest line "cde"
        XCTAssertFalse(block.isTruncated)
    }

    // MARK: - plain text: overflow 'break' (wrap by char, word-aware)

    func test_plainText_break_wrapsByWidth() {
        // width = 3 chars. "abcdef" (no break chars) → break the long word at the boundary.
        let block = parseText.parsePlainText("abcdef", plainStyle(width: 3 * CW, overflow: "break"), nil, nil)
        // Each wrapped line must fit within the width.
        for line in block.lines {
            XCTAssertLessThanOrEqual(Double(line.count) * CW, 3 * CW + 0.001, "line '\(line)' exceeds width")
        }
        XCTAssertEqual(block.lines.joined(), "abcdef", "wrap must preserve all characters")
        XCTAssertGreaterThan(block.lines.count, 1, "long text must wrap to multiple lines")
    }

    func test_plainText_break_wordAware_keepsWordsTogether() {
        // Spaces are break chars; "aa bb cc" with width=5 chars should break at spaces, not mid-word.
        let block = parseText.parsePlainText("aa bb cc", plainStyle(width: 5 * CW, overflow: "break"), nil, nil)
        for line in block.lines {
            XCTAssertFalse(line.hasPrefix(" ") && line.count == 1)
        }
        XCTAssertEqual(block.lines.joined(), "aa bb cc")
    }

    func test_plainText_breakAll_breaksAnywhere() {
        // breakAll ignores word boundaries — packs exactly width/CW chars per line.
        let block = parseText.parsePlainText("abcdefgh", plainStyle(width: 3 * CW, overflow: "breakAll"), nil, nil)
        XCTAssertEqual(block.lines.first, "abc")
        XCTAssertEqual(block.lines.joined(), "abcdefgh")
    }

    // MARK: - plain text: overflow 'truncate' + ellipsis

    func test_plainText_truncate_addsEllipsis() {
        // width = 5 chars; long line gets cut and '...' appended; result fits in container.
        let block = parseText.parsePlainText(
            "abcdefghij",
            plainStyle(width: 5 * CW, overflow: "truncate", ellipsis: "..."),
            nil, nil
        )
        XCTAssertEqual(block.lines.count, 1)
        XCTAssertTrue(block.lines[0].hasSuffix("..."), "truncated line must end with ellipsis, got '\(block.lines[0])'")
        XCTAssertTrue(block.isTruncated)
        // Truncated text width must not exceed the container width.
        XCTAssertLessThanOrEqual(Double(block.lines[0].count) * CW, 5 * CW + 0.001)
    }

    func test_plainText_truncate_shortTextUnchanged() {
        let block = parseText.parsePlainText(
            "ab",
            plainStyle(width: 10 * CW, overflow: "truncate", ellipsis: "..."),
            nil, nil
        )
        XCTAssertEqual(block.lines, ["ab"])
        XCTAssertFalse(block.isTruncated)
    }

    // MARK: - plain text: lineOverflow 'truncate' (drop overflowing lines)

    func test_plainText_lineOverflow_truncatesLines() {
        // 4 lines, lineHeight 10, height 25 ⇒ floor(25/10)=2 lines kept.
        let block = parseText.parsePlainText(
            "a\nb\nc\nd",
            plainStyle(height: 25, lineOverflow: "truncate", lineHeight: 10),
            nil, nil
        )
        XCTAssertEqual(block.lines, ["a", "b"])
        XCTAssertTrue(block.isTruncated)
    }

    // MARK: - rich text: tokenizing

    private func richStyle(_ rich: [String: TextStylePropsPart], width: Double? = nil, overflow: String? = nil) -> TextStyleProps {
        var s = TextStyleProps()
        s.font = MONO
        s.rich = rich
        s.width = width
        s.overflow = overflow
        return s
    }

    func test_richText_parsesStyledTokens() {
        var a = TextStylePropsPart(); a.font = MONO
        let block = parseText.parseRichText("hi {a|world}", richStyle(["a": a]), nil, nil, .left)
        // One line: token "hi " (plain) + token "world" (styled 'a').
        XCTAssertEqual(block.lines.count, 1)
        let tokens = block.lines[0].tokens
        XCTAssertEqual(tokens.count, 2)
        XCTAssertNil(tokens[0].styleName)
        XCTAssertEqual(tokens[0].text, "hi ")
        XCTAssertEqual(tokens[1].styleName, "a")
        XCTAssertEqual(tokens[1].text, "world")
    }

    func test_richText_newlineInTokenStartsNewLine() {
        let block = parseText.parseRichText("a\nb", richStyle([:]), nil, nil, .left)
        XCTAssertEqual(block.lines.count, 2)
        XCTAssertEqual(block.lines[0].tokens.first?.text, "a")
        XCTAssertEqual(block.lines[1].tokens.first?.text, "b")
    }

    func test_richText_emptyReturnsEmptyBlock() {
        let block = parseText.parseRichText("", richStyle([:]), nil, nil, .left)
        XCTAssertEqual(block.lines.count, 0)
    }

    func test_richText_contentWidthIsMaxLineWidth() {
        var a = TextStylePropsPart(); a.font = MONO
        // "ab" + "cdef" on one line ⇒ width = 6 chars.
        let block = parseText.parseRichText("ab{a|cdef}", richStyle(["a": a]), nil, nil, .left)
        XCTAssertEqual(block.contentWidth, 6 * CW, accuracy: 0.001)
    }

    // MARK: - truncateText (public helper)

    func test_truncateText_basic() {
        let out = parseText.truncateText("abcdefghij", 5 * CW, MONO, "...")
        XCTAssertTrue(out.hasSuffix("..."))
        XCTAssertLessThanOrEqual(Double(out.count) * CW, 5 * CW + 0.001)
    }

    func test_truncateText_zeroWidthEmpty() {
        XCTAssertEqual(parseText.truncateText("abc", 0, MONO, "..."), "")
    }
}
