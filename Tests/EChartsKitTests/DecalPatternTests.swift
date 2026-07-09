// Verifies the ported decal-pattern feature:
//   * util/decal.swift — createOrUpdatePatternFromDecal + the dash/symbol normalization + tile geometry
//     (upstream echarts/src/util/decal.ts).
//   * component/aria/ariaVisual.swift `setDecal` — the aria.decal.show auto-decal palette assignment.
//   * visual/decalVisual.swift + Path._decalEl synthesis + BarView decal bridge — the paint path
//     (a bar with itemStyle.decal renders a decal element whose fill is the generated tiling Pattern).

import XCTest
import ZRenderKit
@testable import EChartsKit

#if canImport(QuartzCore) && canImport(CoreGraphics)
import NativePainter
import CoreGraphics
#endif

// Minimal ExtensionAPI double: createOrUpdatePatternFromDecal only reads getDevicePixelRatio() (=1 base).
private final class DecalTestEChartsInstance: EChartsType {}
private final class DecalTestAPI: ExtensionAPI {
    init() { super.init(ecInstance: DecalTestEChartsInstance()) }
    override func getWidth() -> Double { 400 }
    override func getHeight() -> Double { 300 }
}

final class DecalPatternTests: XCTestCase {

    override func setUp() { super.setUp(); ComponentModel.registerClass(BarSeriesModel.self) }

    // ---- normalization (module-level ports of util/decal.ts) ----------------------------------

    func testNormalizeDashArrayX() {
        // A single number → [[ceil, ceil]].
        XCTAssertEqual(normalizeDashArrayX(5), [[5, 5]])
        // [1, 0] (all-number) → wrapped into [[1, 0]].
        XCTAssertEqual(normalizeDashArrayX([1, 0]), [[1, 0]])
        // Mixed [[8,8],[0,8,8,0]] (the dots decal) passes through per-line.
        XCTAssertEqual(normalizeDashArrayX([[8, 8], [0, 8, 8, 0]]), [[8, 8], [0, 8, 8, 0]])
        // Odd-length inner line is mirrored: [4,2,1] → [4,2,1,4,2,1].
        XCTAssertEqual(normalizeDashArrayX([[4, 2, 1]]), [[4, 2, 1, 4, 2, 1]])
        // nil / empty → [[0, 0]].
        XCTAssertEqual(normalizeDashArrayX(nil), [[0, 0]])
        XCTAssertEqual(normalizeDashArrayX([Any]()), [[0, 0]])
    }

    func testNormalizeDashArrayY() {
        XCTAssertEqual(normalizeDashArrayY(5), [5, 5])
        XCTAssertEqual(normalizeDashArrayY([2, 5]), [2, 5])
        XCTAssertEqual(normalizeDashArrayY([6, 0]), [6, 0])
        // odd length is mirrored
        XCTAssertEqual(normalizeDashArrayY([4, 2, 1]), [4, 2, 1, 4, 2, 1])
        XCTAssertEqual(normalizeDashArrayY(nil), [0, 0])
    }

    func testNormalizeSymbolArray() {
        XCTAssertEqual(normalizeSymbolArray("circle"), [["circle"]])
        XCTAssertEqual(normalizeSymbolArray(nil), [["rect"]])
        XCTAssertEqual(normalizeSymbolArray(""), [["rect"]])
        XCTAssertEqual(normalizeSymbolArray(["rect", "circle"]), [["rect", "circle"]])
        XCTAssertEqual(normalizeSymbolArray([["rect", "circle"], "triangle"]), [["rect", "circle"], ["triangle"]])
    }

    func testGetPatternSize() {
        // Lines decal: dashArrayX [1,0], dashArrayY [2,5], symbol 'rect'.
        let dashXLines = normalizeDashArrayX([1, 0])
        let dashYLines = normalizeDashArrayY([2, 5])
        let symLines = normalizeSymbolArray("rect")
        let sizeLines = getPatternSize(
            lineBlockLengthsX: getLineBlockLengthX(dashXLines),
            lineBlockLengthY: getLineBlockLengthY(dashYLines),
            symbolArray: symLines, maxTileWidth: 512, maxTileHeight: 512
        )
        XCTAssertEqual(sizeLines.width, 1, accuracy: 1e-9)
        XCTAssertEqual(sizeLines.height, 7, accuracy: 1e-9)   // 2 + 5

        // Dots decal: circle, dashArrayX [[8,8],[0,8,8,0]], dashArrayY [6,0].
        let dashXDots = normalizeDashArrayX([[8, 8], [0, 8, 8, 0]])
        let dashYDots = normalizeDashArrayY([6, 0])
        let symDots = normalizeSymbolArray("circle")
        let sizeDots = getPatternSize(
            lineBlockLengthsX: getLineBlockLengthX(dashXDots),   // [16, 16]
            lineBlockLengthY: getLineBlockLengthY(dashYDots),    // 6
            symbolArray: symDots, maxTileWidth: 512, maxTileHeight: 512
        )
        XCTAssertEqual(sizeDots.width, 16, accuracy: 1e-9)       // lcm(1,16,16)
        XCTAssertEqual(sizeDots.height, 12, accuracy: 1e-9)      // 6 * 2 lines * 1 symbol-row
    }

    // ---- createOrUpdatePatternFromDecal --------------------------------------------------------

    func testCreatePatternNoneAndNil() {
        let api = DecalTestAPI()
        XCTAssertNil(createOrUpdatePatternFromDecal("none", api))
        XCTAssertNil(createOrUpdatePatternFromDecal(nil, api))
    }

    #if canImport(CoreGraphics) && canImport(ImageIO)
    func testCreatePatternForDotsDecal() {
        let api = DecalTestAPI()
        let decal: [String: Any] = [
            "symbol": "circle",
            "color": "#e60000",
            "dashArrayX": [[8, 8], [0, 8, 8, 0]],
            "dashArrayY": [6, 0],
            "symbolSize": 0.8
        ]
        guard let pattern = createOrUpdatePatternFromDecal(decal, api) else {
            return XCTFail("dots decal should produce a Pattern")
        }
        XCTAssertTrue(pattern.image.hasPrefix("data:image/png;base64,"), "tile should be a PNG data URI")
        XCTAssertEqual(pattern.repeat, .repeat)
        XCTAssertEqual(pattern.scaleX, 1, accuracy: 1e-9)   // 1 / dpr(1)
        // The tile image decodes to the computed pattern size (16 × 12 at dpr 1).
        guard let img = decodeDataURI(pattern.image) else { return XCTFail("tile PNG should decode") }
        XCTAssertEqual(img.width, 16)
        XCTAssertEqual(img.height, 12)
    }

    func testCreatePatternForLinesDecalCarriesRotation() {
        let api = DecalTestAPI()
        let decal: [String: Any] = [
            "color": "rgba(0, 0, 0, 0.2)",
            "dashArrayX": [1, 0],
            "dashArrayY": [2, 5],
            "symbolSize": 1,
            "rotation": Double.pi / 6
        ]
        guard let pattern = createOrUpdatePatternFromDecal(decal, api) else {
            return XCTFail("lines decal should produce a Pattern")
        }
        XCTAssertEqual(pattern.rotation, Double.pi / 6, accuracy: 1e-9)
        guard let img = decodeDataURI(pattern.image) else { return XCTFail("tile PNG should decode") }
        XCTAssertEqual(img.width, 1)
        XCTAssertEqual(img.height, 7)
    }

    private func decodeDataURI(_ src: String) -> CGImage? {
        guard let comma = src.firstIndex(of: ","),
              let data = Data(base64Encoded: String(src[src.index(after: comma)...])),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let img = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return img
    }
    #endif

    // ---- aria.decal.show — auto palette assignment ---------------------------------------------

    private func ariaDecalOption() -> [String: Any] {
        return [
            "aria": ["decal": ["show": true] as [String: Any]] as [String: Any],
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A", "B", "C", "D"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [
                ["type": "bar", "name": "Alpha", "data": [10.0, 20.0, 30.0, 40.0]] as [String: Any],
                ["type": "bar", "name": "Beta", "data": [5.0, 15.0, 25.0, 35.0]] as [String: Any]
            ]
        ]
    }

    func testAriaDecalAssignsDistinctDecalsAcrossSeries() {
        let ec = ECharts(width: 400, height: 300)
        ec.setOption(ariaDecalOption())
        guard let model = ec.getModel() else { return XCTFail("model") }

        guard let d0 = model.getSeriesByIndex(0)?.getData().getVisual("decal") as? [String: Any],
              let d1 = model.getSeriesByIndex(1)?.getData().getVisual("decal") as? [String: Any] else {
            return XCTFail("both series should get an aria palette decal visual")
        }

        // The default decal palette (globalDefault.aria.decal.decals): entry 0 is a lines decal
        // (dashArrayY [2,5], no symbol), entry 1 is a circle-dots decal. Successive series draw
        // successive palette entries → the two decals must differ.
        let sym0 = d0["symbol"] as? String
        let sym1 = d1["symbol"] as? String
        XCTAssertNotEqual(
            (d0["dashArrayY"].map { "\($0)" } ?? "") + (sym0 ?? ""),
            (d1["dashArrayY"].map { "\($0)" } ?? "") + (sym1 ?? ""),
            "series 0 and series 1 should receive DISTINCT palette decals"
        )
        XCTAssertEqual(sym1, "circle", "second palette decal is the circle-dots entry")

        // decalVisual then converted each series' decal visual into a paintable Pattern on 'style'.
        if let style0 = model.getSeriesByIndex(0)?.getData().getVisual("style") as? [String: Any] {
            XCTAssertTrue(style0["decal"] is ZRenderKit.Pattern, "decalVisual should store a Pattern on the style visual")
        }
        else {
            XCTFail("series 0 should have a style visual")
        }
    }

    func testAriaDecalDisabledLeavesNoDecalVisual() {
        // Without aria.decal.show there is no auto decal.
        var opt = ariaDecalOption()
        opt["aria"] = ["decal": ["show": false] as [String: Any]] as [String: Any]
        let ec = ECharts(width: 400, height: 300)
        ec.setOption(opt)
        let decal = ec.getModel()?.getSeriesByIndex(0)?.getData().getVisual("decal")
        XCTAssertNil(decal, "aria.decal.show:false should not assign a decal")
    }

    // ---- paint path: a bar with itemStyle.decal → a rendered decal element ---------------------

    private func collectBars(_ root: Group) -> [Rect] {
        var bars: [Rect] = []
        _ = root.traverse { el in
            if let rect = el as? Rect, rect.name == "item" { bars.append(rect) }
            return false
        }
        return bars
    }

    func testBarItemStyleDecalSynthesizesDecalElement() {
        let ec = ECharts(width: 400, height: 300)
        ec.setOption([
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A", "B", "C", "D"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [[
                "type": "bar",
                "data": [10.0, 20.0, 30.0, 40.0],
                "itemStyle": [
                    "decal": [
                        "symbol": "rect",
                        "color": "#ffffff",
                        "dashArrayX": [1, 0],
                        "dashArrayY": [4, 3]
                    ] as [String: Any]
                ] as [String: Any]
            ] as [String: Any]]
        ])

        let bars = collectBars(ec.getRoot())
        XCTAssertEqual(bars.count, 4, "four bars")
        guard let bar = bars.first else { return }

        // BarView bridged the generated decal Pattern onto pathStyle.decal.
        guard let decalPattern = bar.pathStyle.decal else {
            return XCTFail("bar.pathStyle.decal should carry the generated tiling Pattern")
        }
        XCTAssertFalse(decalPattern.image.isEmpty, "the decal Pattern must carry a tile image")

        // Path.update() synthesizes the hidden decal element (mirrors host geometry, filled with the
        // pattern). Storage/renderScene add it to the display list right after the bar.
        bar.update()
        guard let decalEl = bar.getDecalElement() else {
            return XCTFail("Path.update() should synthesize a decal element when style.decal is set")
        }
        XCTAssertTrue(decalEl.silent, "decal element is silent")
        if case .some(.pattern) = decalEl.pathStyle.fill {
            // ok — the decal element is filled with the pattern.
        }
        else {
            XCTFail("decal element fill should be the decal Pattern")
        }
    }

    #if canImport(QuartzCore) && canImport(CoreGraphics)
    // PNG-verify the texture appears over the fill: the decal render differs from the no-decal render.
    func testBarDecalChangesRenderedPixels() {
        func render(withDecal: Bool) -> CGImage? {
            var series: [String: Any] = ["type": "bar", "data": [40.0, 40.0, 40.0, 40.0]]
            if withDecal {
                series["itemStyle"] = ["decal": [
                    "symbol": "rect", "color": "#ffffff",
                    "dashArrayX": [2, 2], "dashArrayY": [2, 2], "symbolSize": 1
                ] as [String: Any]] as [String: Any]
            }
            let ec = ECharts(width: 400, height: 300)
            ec.setOption([
                "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
                "xAxis": ["type": "category", "data": ["A", "B", "C", "D"]] as [String: Any],
                "yAxis": ["type": "value", "max": 40.0] as [String: Any],
                "series": [series]
            ])
            return renderToImage(group: ec.getRoot(), size: CGSize(width: 400, height: 300), dpr: 1.0)
        }

        guard let plain = render(withDecal: false), let decaled = render(withDecal: true) else {
            return XCTFail("both renders should produce an image")
        }
        let diff = differingPixelCount(plain, decaled)
        XCTAssertGreaterThan(diff, 0, "the decal texture should change some pixels vs the plain fill")
    }

    /// Count pixels that differ between two same-size images (drawn into RGBA8 buffers).
    private func differingPixelCount(_ a: CGImage, _ b: CGImage) -> Int {
        guard a.width == b.width, a.height == b.height else { return -1 }
        let w = a.width, h = a.height
        func bytes(_ img: CGImage) -> [UInt8]? {
            var buf = [UInt8](repeating: 0, count: w * h * 4)
            let cs = CGColorSpaceCreateDeviceRGB()
            guard let ctx = CGContext(
                data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
            return buf
        }
        guard let ba = bytes(a), let bb = bytes(b) else { return -1 }
        var count = 0
        var i = 0
        while i < ba.count {
            if ba[i] != bb[i] || ba[i + 1] != bb[i + 1] || ba[i + 2] != bb[i + 2] || ba[i + 3] != bb[i + 3] {
                count += 1
            }
            i += 4
        }
        return count
    }
    #endif
}
