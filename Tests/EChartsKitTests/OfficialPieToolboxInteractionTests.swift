import XCTest
import AppKit
import CoreGraphics
import ImageIO
import EChartsDemoCore
import NativePainter
import ZRenderKit
@testable import EChartsKit

final class OfficialPieToolboxInteractionTests: XCTestCase {
    private func makeView(_ name: String) throws -> EChartsView {
        let demo = try XCTUnwrap(EChartsDemoRegistry.byName(name))
        let view = EChartsView(width: demo.width, height: demo.height)
        view.setOption(demo.option)
        _ = view.zr.storage.getDisplayList(true)
        return view
    }

    @discardableResult
    private func clickToolbox(_ name: String, in view: EChartsView) throws -> [Double] {
        let icon = try XCTUnwrap(view.zr.storage.getDisplayList(true).first {
            innerStore.getECData($0).tooltipConfig?.name == name
        })
        let bounds = try XCTUnwrap(icon.getBoundingRect())
        let fractions = [0.5, 0.25, 0.75, 0.125, 0.375, 0.625, 0.875]
        let point = try XCTUnwrap(fractions.lazy.compactMap { fy in
            fractions.lazy.compactMap { fx -> [Double]? in
                let candidate = icon.transformCoordToGlobal(
                    bounds.x + bounds.width * fx,
                    bounds.y + bounds.height * fy
                )
                return view.zr.handler.findHover(candidate[0], candidate[1]).target === icon
                    ? candidate : nil
            }.first
        }.first, "the rendered \(name) icon must be hit-testable")
        for type in ["mousemove", "mousedown", "mouseup", "click"] {
            view._injectPointerForTest(type: type, zrX: point[0], zrY: point[1])
        }
        return point
    }

    private func pngData(_ view: EChartsView, options: [String: Any]) -> Data? {
        let ratio = (options["pixelRatio"] as? Double) ?? 1
        let size = CGSize(width: view.ec.getWidth(), height: view.ec.getHeight())
        guard let image = renderToImage(
            group: view.ec.getRoot(), size: size, dpr: ratio,
            backgroundColor: CGColor(gray: 1, alpha: 1)
        ) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, "public.png" as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    func testRoseTypeDataViewPresentsEditableContentAndRefreshesBothPieSeries() throws {
        let view = try makeView("official-pie-roseType")
        var presentation: ToolboxDataViewPresentation?
        view.ec.onPresentDataView = { presentation = $0 }

        try clickToolbox("dataView", in: view)

        let request = try XCTUnwrap(presentation)
        XCTAssertFalse(request.readOnly)
        XCTAssertEqual(request.title, "Data View")
        XCTAssertTrue(request.content.contains("Radius Mode\nrose 1\t40"))
        XCTAssertTrue(request.content.contains("Area Mode\nrose 1\t30"))
        XCTAssertEqual(request.content.components(separatedBy: String(repeating: "-", count: 59)).count, 2)

        let edited = request.content
            .replacingOccurrences(of: "rose 1\t40", with: "rose 1\t41")
            .replacingOccurrences(of: "rose 1\t30", with: "rose 1\t31")
        try request.refresh(edited)

        let first = try XCTUnwrap(view.ec.getModel()?.getSeriesByIndex(0)?.getData().getRawDataItem(0) as? [String: Any])
        let second = try XCTUnwrap(view.ec.getModel()?.getSeriesByIndex(1)?.getData().getRawDataItem(0) as? [String: Any])
        XCTAssertEqual((first["value"] as? NSNumber)?.doubleValue, 41)
        XCTAssertEqual((second["value"] as? NSNumber)?.doubleValue, 31)
    }

    func testRoseTypeSaveAsImageRealIconClickDeliversPngAndOfficialFilename() throws {
        let view = try makeView("official-pie-roseType")
        var renderOptions: [String: Any]?
        var savedData: Data?
        var savedFilename: String?
        view.ec.getRenderedImage = { [weak view] options in
            guard let view else { return nil }
            renderOptions = options
            return self.pngData(view, options: options)
        }
        view.ec.onSaveImage = { data, filename in
            savedData = data
            savedFilename = filename
        }

        try clickToolbox("saveAsImage", in: view)

        let data = try XCTUnwrap(savedData)
        XCTAssertEqual(Array(data.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
        XCTAssertGreaterThan(data.count, 0)
        XCTAssertEqual(savedFilename, "Nightingale Chart.png")
        XCTAssertEqual(renderOptions?["excludeComponents"] as? [String], ["toolbox"])
    }

    func testRoseTypeSimpleRestoreRealIconClickRestoresDisabledLegendItem() throws {
        let view = try makeView("official-pie-roseType-simple")
        let legend = try XCTUnwrap(view.ec.getModel()?.getComponent("legend") as? LegendModel)
        XCTAssertTrue(legend.isSelected("rose 1"))
        XCTAssertNotNil(view._injectLegendClickForTest(name: "rose 1", movePointer: false))
        XCTAssertFalse(legend.isSelected("rose 1"))

        try clickToolbox("restore", in: view)

        let restoredLegend = try XCTUnwrap(view.ec.getModel()?.getComponent("legend") as? LegendModel)
        XCTAssertTrue(restoredLegend.isSelected("rose 1"),
                      "restore must recover a genuinely changed legend state")
    }
}
