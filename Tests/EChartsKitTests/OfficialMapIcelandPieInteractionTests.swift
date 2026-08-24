import XCTest
import EChartsDemoCore
@testable import EChartsKit
@testable import ZRenderKit

final class OfficialMapIcelandPieInteractionTests: XCTestCase {
    private func fillString(_ path: Path) -> String? {
        guard case let .string(value)? = path.pathStyle?.fill else { return nil }
        return value
    }

    private func finishStateTransition(_ element: Element) {
        for animator in element.animators where animator.__fromStateTransition != nil {
            guard let clip = animator.getClip() else { continue }
            _ = clip.step(0, 0)
            if clip.step(300, 300) { clip.ondestroy() }
        }
    }

    private func geoRegionGroup(_ view: EChartsView, named name: String) -> Group? {
        var found: Group?
        _ = view.ec.getRoot().traverse { element in
            if let group = element as? Group,
               innerStore.getECData(group).componentHighDownName == name {
                found = group
                return true
            }
            return false
        }
        return found
    }

    func testGeoRegionHoverAppliesAndRestoresEmphasisFill() throws {
        let demo = try XCTUnwrap(EChartsDemoRegistry.byName("official-map-iceland-pie"))
        let view = EChartsView(width: demo.width, height: demo.height)
        view.setOption(demo.option)
        _ = view.zr.storage.getDisplayList(true)

        let group = try XCTUnwrap(geoRegionGroup(view, named: "Suðurnes"))
        let regionPath = try XCTUnwrap(group.childAt(0) as? CompoundPath)
        let bounds = try XCTUnwrap(regionPath.getBoundingRect())
        let point = regionPath.transformCoordToGlobal(
            bounds.x + bounds.width / 2,
            bounds.y + bounds.height / 2
        )
        let normalFill = fillString(regionPath)

        view._injectPointerForTest(type: "mousemove", zrX: point[0], zrY: point[1])
        XCTAssertTrue(regionPath.currentStates.contains("emphasis"))
        finishStateTransition(regionPath)
        XCTAssertEqual(
            fillString(regionPath),
            "rgba(255,231,130,0.8)",
            "hover must apply the geo emphasis fill to the rendered region path"
        )

        view._injectGlobalOutForTest()
        XCTAssertTrue(regionPath.currentStates.isEmpty)
        finishStateTransition(regionPath)
        XCTAssertEqual(fillString(regionPath).flatMap { color.parse($0) },
                       normalFill.flatMap { color.parse($0) },
                       "global-out must restore the region's normal fill")
        view.dispose()
    }

    func testEveryGeoPieUsesOfficialPercentTooltipFormatter() throws {
        let demo = try XCTUnwrap(EChartsDemoRegistry.byName("official-map-iceland-pie"))
        let expected = [
            "Category C: 18 (18%)",
            "Category C: 28 (28%)",
            "Category C: 26 (26%)",
            "Category C: 35 (35%)",
        ]

        for seriesIndex in 0..<expected.count {
            let view = EChartsView(width: demo.width, height: demo.height)
            view.setOption(demo.option)
            _ = view.zr.storage.getDisplayList(true)
            let series = try XCTUnwrap(view.ec.getModel()?.getSeriesByIndex(Double(seriesIndex)))
            let dataIndex = series.getData().indexOfName("Category C")
            let sector = try XCTUnwrap(series.getData().getItemGraphicEl(dataIndex) as? Sector)
            let shape = try XCTUnwrap(sector.shape as? SectorShape)
            let angle = (shape.startAngle + shape.endAngle) / 2
            let radius = (shape.r0 + shape.r) / 2
            view._injectPointerForTest(
                type: "mousemove",
                zrX: shape.cx + cos(angle) * radius,
                zrY: shape.cy + sin(angle) * radius
            )
            XCTAssertEqual(view.tooltipView?.contentEl?.textStyle?.text, expected[seriesIndex])
            view.dispose()
        }
    }
}
