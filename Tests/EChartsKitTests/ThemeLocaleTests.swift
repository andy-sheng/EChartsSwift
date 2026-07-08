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

    // MARK: - (c) broadened locale spread (FR / DE / ES / JA / RU / PT-br)

    /// Each newly-ported built-in locale is registered (installOnce → registerDefaultLocales) and
    /// exposes its toolbox / aria / time strings through the registered Model. Also checks the
    /// case-insensitive lookup key (registerLocale upper-cases the name).
    func testBroadenedLocalesRegistered() {
        // Ensure the defaults are installed (constructing any EChartsSlim runs installOnce).
        _ = EChartsSlim(width: 10, height: 10)

        // (locale code, saveAsImage title, aria withoutTitle, first monthAbbr, legend-all)
        let cases: [(String, String, String, String, String)] = [
            ("FR", "Sauvegarder l'image", "C'est une carte", "Jan", "Tout"),
            ("DE", "Als Bild speichern", "Dies ist ein Diagramm", "Jan", "Alle"),
            ("ES", "Guardar como imagen", "Este es un gráfico", "ene", "Todas"),
            ("JA", "図として保存", "これはチャートで、", "1月", "すべてを選択"),
            ("RU", "Сохранить картинку", "Это график", "Янв", "Всё"),
            ("PT-br", "Salvar como imagem", "Este é um gráfico", "Jan", "Todas")
        ]
        for (code, saveTitle, ariaNoTitle, monthAbbr, legendAll) in cases {
            // getLocaleModel is keyed by the raw name; registerLocale stored the upper-cased key.
            let model = locale.getLocaleModel(code.uppercased())
            XCTAssertNotNil(model, "\(code) locale model should be registered")
            XCTAssertEqual(model?.get(["toolbox", "saveAsImage", "title"]) as? String, saveTitle,
                           "\(code) toolbox.saveAsImage.title")
            XCTAssertEqual(model?.get(["aria", "general", "withoutTitle"]) as? String, ariaNoTitle,
                           "\(code) aria.general.withoutTitle")
            XCTAssertEqual((model?.get(["time", "monthAbbr"]) as? [String])?.first, monthAbbr,
                           "\(code) time.monthAbbr[0]")
            XCTAssertEqual(model?.get(["legend", "selector", "all"]) as? String, legendAll,
                           "\(code) legend.selector.all")
        }
    }

    /// A chart initialised with a new locale name drives getLocaleModel() with that language, and
    /// createLocaleObject merges the EN default under the non-builtin locale (so untranslated keys
    /// still resolve).
    func testChartWithFRLocaleAndDefaultMerge() {
        let ec = EChartsSlim(width: 400, height: 300, locale: "FR")
        ec.setOption(barOption())
        let localeModel = ec.getModel()?.getLocaleModel()
        XCTAssertEqual(localeModel?.get(["toolbox", "dataZoom", "title", "zoom"]) as? String, "Zoom")
        XCTAssertEqual(localeModel?.get(["series", "typeNames", "pie"]) as? String, "Camembert")

        // createLocaleObject("JA") clones JA and merges EN underneath (non-builtin => merge default).
        let ja = locale.createLocaleObject("JA")
        XCTAssertEqual((((ja["toolbox"] as? [String: Any])?["restore"] as? [String: Any]))?["title"]
                        as? String, "復元")
    }

    // MARK: - (d) broadened theme spread (vintage / macarons)

    /// The vintage theme sets its documented backgroundColor + palette and resolves by name.
    func testVintageTheme() {
        _ = EChartsSlim(width: 10, height: 10) // ensure installOnce ran
        let ec = EChartsSlim(width: 400, height: 300, theme: "vintage")
        ec.setOption(barOption())

        XCTAssertEqual(ec.getModel()?.get("backgroundColor") as? String, "#fef8ef",
                       "vintage theme backgroundColor")
        let palette = ec.getModel()?.get("color") as? [String]
        XCTAssertEqual(palette?.first, "#d87c7c", "vintage palette first color")
        XCTAssertEqual(palette?.count, 10, "vintage palette has 10 colors")
        XCTAssertEqual((ec.getModel()?.get(["graph", "color"]) as? [String])?.first, "#d87c7c")
    }

    /// The macarons theme sets its palette + tooltip/title colors and resolves by name.
    func testMacaronsTheme() {
        _ = EChartsSlim(width: 10, height: 10) // ensure installOnce ran
        let ec = EChartsSlim(width: 400, height: 300, theme: "macarons")
        ec.setOption(barOption())

        // The palette (`color`) is a non-component theme key => merged into the global option.
        let palette = ec.getModel()?.get("color") as? [String]
        XCTAssertEqual(palette?.first, "#2ec7c9", "macarons palette first color")
        XCTAssertEqual(palette?.count, 20, "macarons palette has 20 colors")
        // A non-component series-type theme key also merges (line / candlestick).
        XCTAssertEqual(ec.getModel()?.get(["candlestick", "itemStyle", "color"]) as? String, "#d87a80")
        XCTAssertEqual(ec.getModel()?.get(["line", "symbol"]) as? String, "emptyCircle")

        // `title` / `tooltip` are ComponentModel mainTypes, so mergeTheme intentionally leaves them
        // for the component model to merge (not the global option) — assert the ported theme dict
        // itself carries the documented colors faithfully.
        let title = (macaronsTheme.theme["title"] as? [String: Any])?["textStyle"] as? [String: Any]
        XCTAssertEqual(title?["color"] as? String, "#008acd")
        XCTAssertEqual((macaronsTheme.theme["tooltip"] as? [String: Any])?["backgroundColor"] as? String,
                       "rgba(50,50,50,0.5)")
    }

    /// A chart initialised with the vintage theme renders through the full pipeline with the theme
    /// palette + background.
    func testVintageThemeDemoRenders() {
        let ec = EChartsSlim(width: 400, height: 300, theme: "vintage")
        ec.setOption(barOption())

        var barCount = 0
        _ = ec.getRoot().traverse { el in
            if let r = el as? Rect, r.name == "item" { barCount += 1 }
            return false
        }
        XCTAssertEqual(barCount, 4, "the vintage-theme bar demo should emit 4 bars")
        XCTAssertEqual(ec.getModel()?.get("backgroundColor") as? String, "#fef8ef")
    }
}
