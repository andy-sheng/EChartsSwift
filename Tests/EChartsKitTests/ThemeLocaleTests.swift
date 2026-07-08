// Theme + i18n locale tests (Phase: theme-i18n).
//
// Covers the two new subsystems:
//   (a) theme/dark.ts — the built-in "dark" theme, resolved by name via `registerTheme('dark', ...)`
//       (installed in EChartsSlim.installOnce), merged into the option by GlobalModel.mergeTheme.
//       Asserts the dark theme sets `backgroundColor` (dark) + `textStyle.color` (light), and that a
//       chart renders through the full pipeline with the dark palette (the "dark-theme demo").
//   (b) core/locale.ts + i18n/{langEN,langZH} — the locale registry. Asserts registerLocale ZH
//       round-trips a known localized string, and that the default (EN) locale drives
//       GlobalModel.getLocaleModel() reads.

import XCTest
import ZRenderKit
@testable import EChartsKit

#if canImport(QuartzCore) && canImport(CoreGraphics)
import NativePainter
import CoreGraphics
#endif

final class ThemeLocaleTests: XCTestCase {

    // Some suites register empty-data `series.bar` doubles into the GLOBAL registry; re-register the
    // real model so this order-independent test uses the real data pipeline.
    override func setUp() { super.setUp(); ComponentModel.registerClass(BarSeriesModel.self) }

    private func barOption() -> [String: Any] {
        return [
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "category", "data": ["A", "B", "C", "D"]] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "bar", "data": [10.0, 20.0, 30.0, 40.0]] as [String: Any]]
        ]
    }

    // MARK: - (a) dark theme

    /// The dark theme merges its `backgroundColor` (a dark color from tokens.darkColor) into the
    /// global option; without a theme the option has no backgroundColor.
    func testDarkThemeSetsBackgroundColor() {
        let ec = EChartsSlim(width: 400, height: 300, theme: "dark")
        ec.setOption(barOption())

        let bg = ec.getModel()?.get("backgroundColor") as? String
        XCTAssertEqual(bg, tokens.darkColor.background,
                       "dark theme should set backgroundColor to tokens.darkColor.background")

        // Control: a chart WITHOUT a theme has no backgroundColor merged in.
        let plain = EChartsSlim(width: 400, height: 300)
        plain.setOption(barOption())
        XCTAssertNil(plain.getModel()?.get("backgroundColor") as? String,
                     "no theme => no backgroundColor in the merged option")
    }

    /// The dark theme's light text: `textStyle.color` is the (light) secondary color.
    func testDarkThemeSetsLightTextColor() {
        let ec = EChartsSlim(width: 400, height: 300, theme: "dark")
        ec.setOption(barOption())

        let textColor = ec.getModel()?.get(["textStyle", "color"]) as? String
        XCTAssertEqual(textColor, tokens.darkColor.secondary,
                       "dark theme should set textStyle.color to the light secondary color")
        // darkMode flag also propagates.
        XCTAssertEqual(ec.getModel()?.get("darkMode") as? Bool, true)
    }

    /// A dict theme (not a registered name) works too, and renders through the full pipeline.
    func testDarkThemeDemoRenders() {
        // Pass the theme dict directly (mirrors `echarts.init(dom, themeObject)`).
        let ec = EChartsSlim(width: 400, height: 300, theme: darkTheme.theme)
        ec.setOption(barOption())

        // The full setOption/update cycle produced a scene graph (the dark-theme "demo").
        var barCount = 0
        _ = ec.getRoot().traverse { el in
            if let r = el as? Rect, r.name == "item" { barCount += 1 }
            return false
        }
        XCTAssertEqual(barCount, 4, "the dark-theme bar demo should emit 4 bars")
        XCTAssertEqual(ec.getModel()?.get("backgroundColor") as? String, tokens.darkColor.background)

        #if canImport(QuartzCore) && canImport(CoreGraphics)
        // Render to an image on the dark background — proves the paint path is reachable with the
        // dark palette (the visual "renders with the dark background" check).
        let img = renderToImage(group: ec.getRoot(),
                                size: CGSize(width: 400, height: 300),
                                dpr: 2.0,
                                backgroundColor: CGColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1))
        XCTAssertNotNil(img, "the dark-theme demo should render to an image")
        #endif
    }

    // MARK: - (b) i18n locale

    /// registerLocale('ZH', ...) round-trips known localized strings through the registered Model.
    func testRegisterLocaleZHRoundTrips() {
        // ZH is registered by default (installOnce → registerDefaultLocales), but re-register to
        // exercise registerLocale explicitly and make the test order-independent.
        locale.registerLocale("ZH", langZH.option)

        let zh = locale.getLocaleModel("ZH")
        XCTAssertNotNil(zh, "ZH locale model should be registered")
        XCTAssertEqual(zh?.get(["legend", "selector", "all"]) as? String, "全选")
        XCTAssertEqual(zh?.get(["toolbox", "saveAsImage", "title"]) as? String, "保存为图片")
        XCTAssertEqual((zh?.get(["time", "month"]) as? [String])?.first, "一月")

        // Case-insensitive lookup key (registerLocale upper-cases the name).
        locale.registerLocale("zh", langZH.option)
        XCTAssertEqual(locale.getLocaleModel("ZH")?.get(["toolbox", "restore", "title"]) as? String, "还原")
    }

    /// createLocaleObject clones a known locale, and merges the default (EN) under a non-builtin lang.
    func testCreateLocaleObject() {
        let zh = locale.createLocaleObject("ZH")
        XCTAssertEqual((((zh["toolbox"] as? [String: Any])?["dataZoom"] as? [String: Any])?["title"]
                        as? [String: Any])?["zoom"] as? String, "区域缩放")

        // SYSTEM_LANG defaults to EN in this (DOM-less) port.
        XCTAssertEqual(locale.SYSTEM_LANG, "EN")
        let en = locale.createLocaleObject(locale.SYSTEM_LANG)
        XCTAssertEqual((en["legend"] as? [String: Any]).flatMap { $0["selector"] as? [String: Any] }?["all"]
                        as? String, "All")
    }

    /// The default locale (EN) drives GlobalModel.getLocaleModel() reads used by components
    /// (legend selector, toolbox titles, time-axis month names).
    func testDefaultLocaleIsEN() {
        let ec = EChartsSlim(width: 400, height: 300)
        ec.setOption(barOption())

        let localeModel = ec.getModel()?.getLocaleModel()
        XCTAssertEqual(localeModel?.get(["legend", "selector", "all"]) as? String, "All")
        XCTAssertEqual(localeModel?.get(["toolbox", "saveAsImage", "title"]) as? String, "Save as Image")
        XCTAssertEqual((localeModel?.get(["time", "monthAbbr"]) as? [String])?.first, "Jan")
    }

    /// A ZH-locale chart drives getLocaleModel() with the Chinese strings.
    func testChartWithZHLocale() {
        let ec = EChartsSlim(width: 400, height: 300, locale: "ZH")
        ec.setOption(barOption())

        let localeModel = ec.getModel()?.getLocaleModel()
        XCTAssertEqual(localeModel?.get(["legend", "selector", "all"]) as? String, "全选")
    }
}
