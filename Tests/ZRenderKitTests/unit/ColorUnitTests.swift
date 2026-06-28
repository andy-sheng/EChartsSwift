// Ported from zrender/test/ut/spec/tool/color.test.ts — keep in sync with upstream

import XCTest
@testable import ZRenderKit

// upstream: import * as colorTool from '../../../../src/tool/color';   → Tool/color.swift (enum `color`)
//
// upstream parametrizes a single `it` per (colorStr, colorRes) pair via a forEach over a table.
// XCTest has no parametrized `it`, so the table is iterated inside one test method; each row
// carries its own diff-bearing assertion (file/line + the offending color string in the message),
// matching the per-case failure granularity of the Jest `forEach`.
//
// Phase-1 deferred this spec because `tool/color` was only partially ported; `color.parse` is now
// complete (Phase 3), so it runs unskipped.
final class ColorUnitTests: XCTestCase {

    // upstream: each `it(`'${colorStr}' should be converted to [...]`)` → `expect(colorTool.parse(colorStr)).toEqual(colorRes)`
    func test_parse_converts_color_strings() {
        // upstream table: ([ [colorStr, colorRes], ... ] as [string, number[]][])
        let cases: [(String, [Double])] = [
            ("rgba(17, 163, 69)", [17, 163, 69, 1]),
            ("rgba(17, 163, 69, 0.5)", [17, 163, 69, 0.5]),
            ("rgb(17, 163, 69)", [17, 163, 69, 1]),
            ("rgb(2, 163, 254, 1)", [2, 163, 254, 1]),
            ("rgb(2, 163, 254, 0.8)", [2, 163, 254, 0.8]),
            ("rgb(2, 163, 254, 20%)", [2, 163, 254, 0.2]),
            ("rgba(2, 163, 254, 50%)", [2, 163, 254, 0.5]),
            ("#14c4ba00", [20, 196, 186, 0]),
            ("#14c4bacc", [20, 196, 186, 0.8]),
            ("#14c4ba", [20, 196, 186, 1]),
            ("#07f0", [0, 119, 255, 0]),
            ("#07fc", [0, 119, 255, 0.8]),
            ("#07f", [0, 119, 255, 1]),
            ("red", [255, 0, 0, 1]),
            ("blue", [0, 0, 255, 1])
        ]

        for (colorStr, colorRes) in cases {
            // upstream: expect(colorTool.parse(colorStr)).toEqual(colorRes);
            let parsed = color.parse(colorStr)
            XCTAssertEqual(parsed, colorRes, "'\(colorStr)' should be converted to \(colorRes)")
        }
    }
}
