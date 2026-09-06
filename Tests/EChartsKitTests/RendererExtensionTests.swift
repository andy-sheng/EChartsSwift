import XCTest
import ZRenderKit
import EChartsKit
import NativeRenderer

final class RendererExtensionTests: XCTestCase {
    private enum CountingRenderer: EChartsExtension {
        static var installs = 0
        static func install(_ registers: EChartsExtensionInstallRegisters) {
            installs += 1
            registers.registerPainter("extension-probe") { CALayerPainter($0, $1, $2, $3) }
        }
    }

    private final class Host: ZRenderHost {
        var width: Double = 240
        var height: Double = 160
        var devicePixelRatio: Double = 1
        var handlerProxy: HandlerProxyInterface? { nil }
        var attached = 0
        var detached = 0
        func attach(_ zr: ZRender) throws { attached += 1 }
        func detach(_ zr: ZRender) { detached += 1 }
    }

    func testUseDeduplicatesAndInitOwnsARealPainter() throws {
        echarts.use([CountingRenderer.self, CountingRenderer.self])
        echarts.use(CountingRenderer.self)
        XCTAssertEqual(CountingRenderer.installs, 1)
        let host = Host()
        var opts = EChartsInitOpts(); opts.renderer = "extension-probe"
        let chart = try echarts.`init`(host, ["backgroundColor": "#ff0000"], opts)
        defer { chart.dispose() }
        XCTAssertTrue(chart === (try echarts.`init`(host, nil, opts)))
        XCTAssertEqual(host.attached, 1)
        XCTAssertTrue(chart.getZr().painter.storage === chart.getZr().storage)
        chart.setOption(["animation": false, "xAxis": ["data": ["A", "B"]],
                         "yAxis": [:], "series": [["type": "bar", "data": [2, 4]]]])
        chart.getZr().refreshImmediately()
        let painter = try XCTUnwrap(chart.getZr().painter as? CALayerPainter)
        XCTAssertNotNil(painter.rootLayer.contents)
        XCTAssertFalse(chart.getZr().storage.getDisplayList().isEmpty)
        host.width = 360; host.height = 200
        chart.resize()
        XCTAssertEqual(chart.getWidth(), 360)
        XCTAssertEqual(chart.getZr().painter.getWidth(), 360)
        chart.dispose(); chart.dispose()
        XCTAssertEqual(host.detached, 1)
        XCTAssertNil(echarts.getInstanceByDom(host))
        let replacement = try echarts.`init`(host, nil, opts)
        defer { replacement.dispose() }
        XCTAssertFalse(replacement === chart)
    }

    func testSSRSkipsHostAndLegacyHeadlessRemainsHeadless() throws {
        echarts.use(CanvasRenderer.self)
        let host = Host()
        var opts = EChartsInitOpts(); opts.renderer = "canvas"; opts.ssr = true
        let chart = try echarts.`init`(host, nil, opts)
        defer { chart.dispose() }
        XCTAssertEqual(host.attached, 0)
        chart.dispose()
        XCTAssertEqual(host.detached, 0)
        let legacy = EChartsView(width: 30, height: 20)
        defer { legacy.dispose() }
        XCTAssertTrue(legacy.zr.painter is HeadlessPainter)
    }

    func testNativeHostMountsAndDetachesTheSelectedLayer() throws {
        echarts.use(CanvasRenderer.self)
        let host = NativeChartHost(frame: CGRect(x: 0, y: 0, width: 100, height: 80))
        var opts = EChartsInitOpts(); opts.renderer = "canvas"
        let chart = try echarts.`init`(host, nil, opts)
        let painter = try XCTUnwrap(chart.getZr().painter as? CALayerPainter)
        XCTAssertNotNil(painter.rootLayer.superlayer)
        host.frame.size = CGSize(width: 200, height: 100)
        chart.resize()
        XCTAssertEqual(painter.rootLayer.frame.origin, .zero)
        XCTAssertEqual(painter.rootLayer.frame.size, CGSize(width: 200, height: 100))
        chart.dispose()
        XCTAssertNil(painter.rootLayer.superlayer)
    }
}
