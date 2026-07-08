// Tests for the labelLayout CALLBACK form — label/LabelManager.ts
//   (`updateLayoutConfig` resolving `layoutOptionOrCb` when it is a function, via
//   `prepareLayoutCallbackParams`) ported to label/LabelManager.swift.
//
// The port carries the callback as a Swift closure (`LabelLayoutOptionCallback`) stored on the series
//   `labelLayout` option; here we seed the manager's `_labelList` directly (see the `internal`
//   PORT-NOTE on `_labelList`) so the callback → params → applied-option path is exercised without a
//   full SeriesModel/data pipeline.
import XCTest
import ZRenderKit
@testable import EChartsKit

final class LabelLayoutCallbackTests: XCTestCase {

    // Build a host element carrying `label` as its text content (so `label.__hostTarget` is set), and a
    //   LabelLayoutData wrapping them with the given callback.
    private func makeItem(
        _ callback: @escaping LabelLayoutOptionCallback,
        dataIndex: Double = 3,
        seriesIndex: Double = 7,
        text: String = "hello"
    ) -> (LabelManager, LabelLayoutData, Group, ZRText) {
        let host = Group()
        let label = ZRText()
        var style = TextStyleProps()
        style.text = text
        style.align = .center
        style.verticalAlign = .middle
        label.useStyle(style)
        host.setTextContent(label)

        let item = LabelLayoutData(
            label: label,
            layoutOption: nil,
            layoutCallback: callback,
            dataIndex: dataIndex,
            dataType: nil,
            seriesIndex: seriesIndex
        )
        let manager = LabelManager()
        manager._labelList = [item]
        return (manager, item, host, label)
    }

    // A callback returning { dx, dy } shifts the label via the host's textConfig.offset (upstream: dx/dy
    //   are carried as `textConfig.offset`, not as label x/y).
    func testCallbackDxDyMovesLabelViaOffset() {
        var received: LabelLayoutOptionCallbackParams?
        let (manager, _, host, _) = makeItem({ params in
            received = params
            var opt = LabelLayoutOption()
            opt.dx = 12
            opt.dy = -8
            return opt
        })

        manager.updateLayoutConfig(400, 300)

        // The callback was invoked with faithfully-built params.
        XCTAssertNotNil(received)
        XCTAssertEqual(received?.dataIndex, 3)
        XCTAssertEqual(received?.seriesIndex, 7)
        XCTAssertEqual(received?.text, "hello")
        XCTAssertEqual(received?.align, .center)
        XCTAssertEqual(received?.verticalAlign, .middle)

        // dx/dy applied to the host textConfig offset.
        guard let offset = host.textConfig?.offset else {
            return XCTFail("host textConfig.offset should be set from dx/dy")
        }
        XCTAssertEqual(offset[0], 12, accuracy: 1e-9)
        XCTAssertEqual(offset[1], -8, accuracy: 1e-9)
    }

    // A callback returning absolute { x, y } sets the label element's x/y (percent-resolved against the
    //   viewport).
    func testCallbackXYSetsLabelPosition() {
        let (manager, _, _, label) = makeItem({ _ in
            var opt = LabelLayoutOption()
            opt.x = 50.0
            opt.y = 120.0
            return opt
        })

        manager.updateLayoutConfig(400, 300)

        XCTAssertEqual(label.x, 50, accuracy: 1e-9)
        XCTAssertEqual(label.y, 120, accuracy: 1e-9)
    }

    // A callback returning a percent-string x resolves against the viewport width.
    func testCallbackPercentXResolvesAgainstWidth() {
        let (manager, _, _, label) = makeItem({ _ in
            var opt = LabelLayoutOption()
            opt.x = "25%"
            return opt
        })

        manager.updateLayoutConfig(400, 300)
        XCTAssertEqual(label.x, 100, accuracy: 1e-9, "25% of width 400")
    }

    // A callback returning { rotate } rotates the label (degrees → radians) and, via the host
    //   textConfig, records the same rotation.
    func testCallbackRotateSetsRotation() {
        let (manager, _, host, label) = makeItem({ _ in
            var opt = LabelLayoutOption()
            opt.rotate = 90
            return opt
        })

        manager.updateLayoutConfig(400, 300)
        XCTAssertEqual(label.rotation, Double.pi / 2, accuracy: 1e-9)
        XCTAssertEqual(host.textConfig?.rotation ?? .nan, Double.pi / 2, accuracy: 1e-9)
    }

    // The resolved option is cached back on the item so the later overlap `layout()` stage sees it.
    func testResolvedOptionCachedOnItem() {
        let (manager, item, _, _) = makeItem({ _ in
            var opt = LabelLayoutOption()
            opt.hideOverlap = true
            opt.dx = 5
            return opt
        })

        manager.updateLayoutConfig(400, 300)
        XCTAssertEqual(item.layoutOption?.hideOverlap, true, "callback result cached on the item")
        XCTAssertEqual(item.layoutOption?.dx, 5)
    }
}
