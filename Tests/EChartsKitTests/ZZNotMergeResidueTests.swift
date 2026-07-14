// ZZNotMergeResidueTests — `setOption(option, notMerge: true)` must leave NOTHING of the old option
// behind.
//
// Why this test exists: while watching official-map-bar-morph flip from its map to its bar, the
// native pane showed the bar chart WITH THE MAP'S visualMap COLOUR BAR STILL DRAWN next to it. The
// bar option has no visualMap at all. Upstream `notMerge` throws the whole model away
// (`this._model = new GlobalModel()`, echarts.ts:768), so a component the new option does not
// declare cannot survive — and its view must be swept.
//
// The assertion is deliberately blunt: the chart you get by going map -> bar(notMerge) must be
// PIXEL-IDENTICAL to the chart you get by rendering that bar option on a fresh instance. Anything
// left over — a stale component, an orphaned view group — shows up as a differing pixel. Checking
// `getComponent("visualMap") == nil` would only prove the MODEL is clean, and the residue we saw was
// on screen, not in the model.

import XCTest
import CoreGraphics
@testable import EChartsKit
import ZRenderKit
import NativePainter

final class ZZNotMergeResidueTests: XCTestCase {

    private let size = CGSize(width: 400, height: 300)

    /// The option that declares a visualMap (the "map half" of map-bar-morph, reduced to its essence:
    /// what matters is that a COMPONENT exists here and not in the successor option).
    private var optionWithVisualMap: [String: Any] {
        [
            "visualMap": [
                "left": "right", "min": 0.0, "max": 40.0, "calculable": true
            ] as [String: Any],
            "xAxis": ["type": "category", "data": ["a", "b", "c"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [
                ["id": "p", "type": "bar", "data": [10.0, 20.0, 30.0]] as [String: Any]
            ]
        ]
    }

    /// The successor option — no visualMap, axes swapped (a different chart, sharing the series id).
    private var optionWithout: [String: Any] {
        [
            "xAxis": ["type": "value"] as [String: Any],
            "yAxis": ["type": "category", "data": ["a", "b", "c"]] as [String: Any],
            "series": [
                ["id": "p", "type": "bar", "data": [10.0, 20.0, 30.0]] as [String: Any]
            ]
        ]
    }

    @MainActor
    private func render(_ build: (ECharts) -> Void) -> CGImage? {
        let ec = ECharts(width: Double(size.width), height: Double(size.height))
        build(ec)
        return renderToImage(group: ec.getRoot(), size: size, dpr: 1,
                             backgroundColor: CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    }

    /// Raw BGRA bytes, so two renders can be compared byte-for-byte.
    private func pixels(_ img: CGImage) -> [UInt8] {
        let w = img.width, h = img.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        buf.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                bytesPerRow: w * 4, space: cs,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            ctx?.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return buf
    }

    @MainActor
    func testNotMergeLeavesNoResidueOfTheOldOption() throws {
        // Control: the successor option on a fresh chart — what it is SUPPOSED to look like.
        let control = try XCTUnwrap(render { ec in
            var o = self.optionWithout; o["animation"] = false
            ec.setOption(o)
        })

        // Subject: the same option, reached by replacing an option that had a visualMap.
        let subject = try XCTUnwrap(render { ec in
            var first = self.optionWithVisualMap; first["animation"] = false
            ec.setOption(first)
            var second = self.optionWithout; second["animation"] = false
            ec.setOption(second, notMerge: true)
        })

        let a = pixels(control), b = pixels(subject)
        XCTAssertEqual(a.count, b.count)

        let differing = zip(a, b).lazy.filter { $0 != $1 }.count
        XCTAssertEqual(differing, 0,
            "notMerge left something of the old option behind: \(differing) of \(a.count) bytes differ "
            + "from a fresh render of the same option. The visualMap the first option declared (and the "
            + "second does not) is the prime suspect.")
    }

    /// The model half of the same question — cheap, and it localises a failure: if this passes but the
    /// pixel test fails, the leak is a stale VIEW, not a stale component.
    @MainActor
    func testNotMergeDropsTheComponentFromTheModel() throws {
        let ec = ECharts(width: Double(size.width), height: Double(size.height))
        ec.setOption(optionWithVisualMap)
        XCTAssertNotNil(ec.getModel()?.getComponent("visualMap", 0),
                        "precondition: the first option declares a visualMap")

        ec.setOption(optionWithout, notMerge: true)
        XCTAssertNil(ec.getModel()?.getComponent("visualMap", 0),
                     "notMerge must rebuild the model (upstream: `this._model = new GlobalModel()`), "
                     + "so a component the new option never declares cannot survive")
    }
}
