// END-TO-END RENDER TEST for the CUSTOM series (renderItem) vertical (sibling of Bar/Scatter render tests).
// Drives ECharts with a custom series on a cartesian2d grid whose `renderItem` closure returns one
// `rect` element per datum (a hand-rolled bar), then inspects the ZRenderKit scene: one `Rect` per datum,
// each with a finite, in-view shape. Phase 26.
import XCTest
import ZRenderKit
@testable import EChartsKit

final class CustomRenderTests: XCTestCase {
    override func setUp() { super.setUp(); ComponentModel.registerClass(CustomSeriesModel.self) }

    func testRenderItemContextIsSharedWithinOneRenderAndResetOnUpdate() {
        let ec = ECharts(width: 240, height: 160)
        var seenContexts: [CustomSeriesRenderItemContext] = []
        var seenCounters: [Int] = []
        let renderItem: CustomSeriesRenderItem = { params, _ in
            let next = (params.context["counter"] as? Int ?? 0) + 1
            params.context["counter"] = next
            seenContexts.append(params.context)
            seenCounters.append(next)
            return [
                "type": "circle",
                "shape": ["cx": 20.0 + params.dataIndexInside * 20.0,
                          "cy": 40.0, "r": 5.0] as [String: Any]
            ] as [String: Any]
        }
        let option: [String: Any] = [
            "animation": false,
            "series": [[
                "type": "custom", "coordinateSystem": "none",
                "renderItem": renderItem, "data": [1.0, 2.0, 3.0]
            ] as [String: Any]]
        ]

        ec.setOption(option)
        XCTAssertEqual(seenCounters, [1, 2, 3])
        XCTAssertTrue(seenContexts.dropFirst().allSatisfy { $0 === seenContexts[0] })

        let firstRenderContext = seenContexts.first
        seenContexts.removeAll()
        seenCounters.removeAll()
        ec.setOption(option)
        XCTAssertEqual(seenCounters, [1, 2, 3], "a new setOption starts a fresh context")
        XCTAssertTrue(seenContexts.dropFirst().allSatisfy { $0 === seenContexts[0] })
        if let firstRenderContext {
            XCTAssertFalse(firstRenderContext === seenContexts[0])
        }
    }

    func testCustomRendersOneRectPerDatum() {
        let W = 400.0, H = 300.0
        let ec = ECharts(width: W, height: H)

        // renderItem returns a rect bar per datum, sized from api.coord/api.size (cartesian2d).
        //   Carried directly on the series option under "renderItem" typed EXACTLY CustomSeriesRenderItem
        //   (CustomSeriesModel.getRenderItem casts it back). util.clone passes closures through untouched.
        let renderItem: CustomSeriesRenderItem = { _, api in
            let x = (api.value(0.0, nil) as? Double) ?? 0
            let y = (api.value(1.0, nil) as? Double) ?? 0
            let top = api.coord([x, y], nil)
            let base = api.coord([x, 0.0], nil)
            guard top.count >= 2, base.count >= 2 else { return nil }
            let unitWidth = (api.size([1.0, 0.0], nil) as? [Double])?.first ?? 10.0
            let width = unitWidth * 0.6
            return [
                "type": "rect",
                "shape": [
                    "x": top[0] - width / 2,
                    "y": top[1],
                    "width": width,
                    "height": base[1] - top[1]
                ] as [String: Any],
                "style": ["fill": "#5470c6"] as [String: Any]
            ] as [String: Any]
        }

        ec.setOption([
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "value"] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "custom",
                        "renderItem": renderItem,
                        "data": [[0.0, 5.0], [1.0, 8.0], [2.0, 4.0], [3.0, 9.0], [4.0, 6.0]]] as [String: Any]]
        ])

        // Real data pipeline built 5 rows.
        var count = -1
        ec.getModel()?.eachSeries { s, _ in count = s.getData().count() }
        XCTAssertEqual(count, 5, "custom should build 5 rows from series.data")

        // The renderItem closure was resolved off the option bag (getRenderItem cast held).
        var resolved = false
        ec.getModel()?.eachSeries { s, _ in
            if let cs = s as? CustomSeriesModel, cs.getRenderItem() != nil { resolved = true }
        }
        XCTAssertTrue(resolved, "getRenderItem() should resolve the option-carried closure")

        // Collect the Rect elements the CustomChartView built into the scene graph.
        var rects: [Rect] = []
        _ = ec.getRoot().traverse { el in
            if let r = el as? Rect { rects.append(r) }
            return false
        }
        XCTAssertEqual(rects.count, 5, "custom should emit one Rect per datum")
        XCTAssertGreaterThan(rects.count, 0, "custom must emit at least one Rect")

        // Each Rect carries a finite, in-view shape (positioned via api.coord/api.size).
        for r in rects {
            guard let shape = r.shape as? RectShape else {
                XCTFail("custom Rect must carry a RectShape"); continue
            }
            XCTAssertTrue(shape.x.isFinite && shape.y.isFinite
                && shape.width.isFinite && shape.height.isFinite,
                "rect shape must be finite: \(shape)")
            XCTAssertTrue(shape.x >= 0 && shape.x <= W, "rect x in-view: \(shape.x)")
            XCTAssertTrue(shape.y >= 0 && shape.y <= H, "rect y in-view: \(shape.y)")
            XCTAssertGreaterThan(shape.width, 0, "rect width positive: \(shape.width)")
        }

        // Rects carry the fill the renderItem style bag set.
        var fills: [String] = []
        for r in rects {
            if case let .string(s)? = r.pathStyle?.fill, !s.isEmpty { fills.append(s) }
        }
        XCTAssertEqual(fills.count, 5, "each custom Rect carries the renderItem fill")
        XCTAssertEqual(Set(fills), ["#5470c6"], "custom rects use the renderItem-specified fill")
    }

    func testCustomRenderItemMaterializesEllipseShape() {
        let ec = ECharts(width: 240, height: 160)
        let renderItem: CustomSeriesRenderItem = { _, _ in
            [
                "type": "ellipse",
                "shape": ["cx": 90.0, "cy": 70.0, "rx": 42.0, "ry": 18.0] as [String: Any],
                "style": [
                    "fill": NSNull(), "stroke": "#bbb",
                    "lineWidth": 4.0, "lineDash": [4.0, 4.0],
                ] as [String: Any],
            ] as [String: Any]
        }
        ec.setOption([
            "animation": false,
            "series": [[
                "type": "custom", "coordinateSystem": "none",
                "renderItem": renderItem, "data": [1.0],
            ] as [String: Any]],
        ])

        var rendered: Ellipse?
        _ = ec.getRoot().traverse { element in
            if let ellipse = element as? Ellipse { rendered = ellipse }
            return false
        }
        guard let shape = rendered?.shape as? EllipseShape else {
            return XCTFail("custom ellipse must materialize as a typed Ellipse")
        }
        XCTAssertEqual(shape.cx, 90)
        XCTAssertEqual(shape.cy, 70)
        XCTAssertEqual(shape.rx, 42)
        XCTAssertEqual(shape.ry, 18)
        XCTAssertEqual(rendered?.pathStyle?.lineWidth, 4)
        XCTAssertNil(rendered?.pathStyle?.fill, "authored fill:null must remain unfilled")
    }

    func testDeprecatedAPIStyleBridgesSeriesLabelToAttachedText() {
        let ec = ECharts(width: 400, height: 300)
        let renderItem: CustomSeriesRenderItem = { _, api in
            let value = (api.value(1.0, nil) as? Double) ?? 0
            let top = api.coord([0.0, value], nil)
            let base = api.coord([0.0, 0.0], nil)
            guard top.count >= 2, base.count >= 2 else { return nil }
            return [
                "type": "rect",
                "shape": [
                    "x": top[0] - 20.0, "y": top[1],
                    "width": 40.0, "height": base[1] - top[1]
                ] as [String: Any],
                "style": api.style(nil, nil)
            ] as [String: Any]
        }

        ec.setOption([
            "animation": false,
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "value"] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [[
                "type": "custom",
                "renderItem": renderItem,
                "label": ["show": true, "position": "top"] as [String: Any],
                "encode": ["x": 0.0, "y": 1.0] as [String: Any],
                "data": [[0.0, 5.0]]
            ] as [String: Any]]
        ])

        var host: Rect?
        _ = ec.getRoot().traverse { el in
            if let rect = el as? Rect, rect.getTextContent() != nil { host = rect }
            return false
        }
        guard let host, let label = host.getTextContent() else {
            return XCTFail("api.style() must materialize the series label as attached text")
        }
        XCTAssertEqual(label.textStyle?.text, "5")
        XCTAssertEqual(host.textConfig?.position as? String, "top")
    }

    // A minimal renderItem: one rect bar per datum, optionally carrying an extra style bag.
    private func makeRectRenderItem(extraStyle: [String: Any] = [:]) -> CustomSeriesRenderItem {
        return { _, api in
            let x = (api.value(0.0, nil) as? Double) ?? 0
            let y = (api.value(1.0, nil) as? Double) ?? 0
            let top = api.coord([x, y], nil)
            let base = api.coord([x, 0.0], nil)
            guard top.count >= 2, base.count >= 2 else { return nil }
            var style: [String: Any] = ["fill": "#5470c6"]
            for (k, v) in extraStyle { style[k] = v }
            return [
                "type": "rect",
                "shape": [
                    "x": top[0] - 5, "y": top[1],
                    "width": 10.0, "height": base[1] - top[1]
                ] as [String: Any],
                "style": style
            ] as [String: Any]
        }
    }

    private func rectCount(_ ec: ECharts) -> Int {
        var n = 0
        _ = ec.getRoot().traverse { el in
            if el is Rect { n += 1 }
            return false
        }
        return n
    }

    private func customOption(_ renderItem: @escaping CustomSeriesRenderItem,
                              _ data: [[Double]],
                              animation: Bool) -> [String: Any] {
        return [
            "animation": animation,
            "grid": ["left": 50.0, "top": 20.0, "width": 300.0, "height": 200.0] as [String: Any],
            "xAxis": ["type": "value"] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "custom",
                        "renderItem": renderItem,
                        "data": data] as [String: Any]]
        ]
    }

    // The LEAVE path (`applyLeaveTransition`, replacing the old removeElementWithFadeOut): when the data
    //   shrinks, the surplus per-datum els must actually leave the group.
    func testCustomLeaveTransitionRemovesElementsWhenDataShrinks() {
        for animation in [false, true] {
            let ec = ECharts(width: 400, height: 300)
            let renderItem = makeRectRenderItem()
            ec.setOption(customOption(renderItem, [[0, 5], [1, 8], [2, 4]], animation: animation))
            XCTAssertEqual(rectCount(ec), 3, "3 data → 3 rects (animation: \(animation))")

            ec.setOption(customOption(renderItem, [[0, 5], [1, 8]], animation: animation))
            XCTAssertEqual(rectCount(ec), 2,
                "shrinking to 2 data must remove the leaving el from the group (animation: \(animation))")
        }
    }

    func testCustomExtraDuringTransitionInterpolatesReusedElement() throws {
        let view = EChartsView(width: 400, height: 300)
        let ec = view.ec
        let renderItem: CustomSeriesRenderItem = { _, api in
            let target = (api.value(0.0, nil) as? Double) ?? 0
            let during: (TransitionDuringAPI) -> Void = { transitionAPI in
                let raw = transitionAPI.getExtra("progress")
                let progress = (raw as? Double) ?? (raw as? NSNumber)?.doubleValue ?? 0
                _ = transitionAPI.setShape("x", progress)
            }
            let textDuring: (TransitionDuringAPI) -> Void = { transitionAPI in
                let raw = transitionAPI.getExtra("progress")
                let progress = (raw as? Double) ?? (raw as? NSNumber)?.doubleValue ?? 0
                _ = transitionAPI.setStyle("text", String(format: "%.1f", progress))
            }
            let child = [
                "type": "rect",
                "shape": ["x": target, "y": 20.0, "width": 20.0, "height": 20.0] as [String: Any],
                "extra": [
                    "progress": target,
                    "transition": ["progress"]
                ] as [String: Any],
                "style": ["fill": "#5470c6"] as [String: Any],
                "during": during
            ] as [String: Any]
            let label = [
                "type": "text",
                "style": ["text": String(format: "%.1f", target), "fill": "#333"] as [String: Any],
                "extra": [
                    "progress": target,
                    "transition": ["progress"]
                ] as [String: Any],
                "during": textDuring
            ] as [String: Any]
            return ["type": "group", "children": [child, label]] as [String: Any]
        }

        func option(_ value: Double) -> [String: Any] {
            [
                "animation": true,
                "animationDuration": 0.0,
                "animationDurationUpdate": 1000.0,
                "animationEasingUpdate": "linear",
                "xAxis": ["type": "value"] as [String: Any],
                "yAxis": ["type": "value"] as [String: Any],
                "series": [[
                    "type": "custom",
                    "renderItem": renderItem,
                    "data": [value]
                ] as [String: Any]]
            ]
        }

        view.setOption(option(10))
        var group = try XCTUnwrap(ec.getModel()?.getSeriesByIndex(0)?.getData().getItemGraphicEl(0) as? Group)
        var rect = try XCTUnwrap(group.childAt(0) as? Rect)
        var label = try XCTUnwrap(group.childAt(1) as? ZRText)
        let originalGroupID = ObjectIdentifier(group)
        let originalID = ObjectIdentifier(rect)
        let originalLabelID = ObjectIdentifier(label)
        XCTAssertNotNil(rect.__zr)

        view.setOption(option(30))
        group = try XCTUnwrap(ec.getModel()?.getSeriesByIndex(0)?.getData().getItemGraphicEl(0) as? Group)
        rect = try XCTUnwrap(group.childAt(0) as? Rect)
        label = try XCTUnwrap(group.childAt(1) as? ZRText)
        XCTAssertEqual(ObjectIdentifier(group), originalGroupID)
        XCTAssertEqual(ObjectIdentifier(rect), originalID, "custom update must reuse the element")
        XCTAssertEqual(ObjectIdentifier(label), originalLabelID, "custom update must reuse the label")
        XCTAssertFalse(rect.animators.isEmpty, "extra.transition must create an update animator")

        view.zr.animation.update(true)
        XCTAssertEqual(try XCTUnwrap(rect.shape as? RectShape).x, 10, accuracy: 1.0)
        Thread.sleep(forTimeInterval: 0.05)
        view.zr.animation.update(true)
        let liveIntermediate = try XCTUnwrap(rect.shape as? RectShape).x
        XCTAssertGreaterThan(liveIntermediate, 10)
        XCTAssertLessThan(liveIntermediate, 30,
                          "the registered frame clock must drive `during`, not leave the final snap")
        let liveLabel = try XCTUnwrap(Double(label.textStyle?.text ?? ""))
        XCTAssertGreaterThan(liveLabel, 10)
        XCTAssertLessThan(liveLabel, 30,
                          "custom `during.setStyle(text:)` must update ZRText.textStyle")
    }

    func testCustomClipPathDuringBuildsPointerFromEntranceTween() throws {
        let view = EChartsView(width: 240, height: 240)
        let ec = view.ec
        let endAngle = Double.pi / 2
        func pointer(_ angle: Double) -> [[Double]] {
            [[120 + cos(angle) * 90, 120 - sin(angle) * 90],
             [120 + cos(angle + 0.08) * 90, 120 - sin(angle + 0.08) * 90],
             [120 + cos(angle) * 20, 120 - sin(angle) * 20]]
        }
        let renderItem: CustomSeriesRenderItem = { _, api in
            let target = (api.value(0.0, nil) as? Double) ?? 0
            let during: (TransitionDuringAPI) -> Void = { transitionAPI in
                let raw = transitionAPI.getExtra("angle")
                let angle = (raw as? Double) ?? (raw as? NSNumber)?.doubleValue ?? 0
                _ = transitionAPI.setShape("points", pointer(angle))
            }
            return [
                "type": "rect",
                "shape": ["x": 10.0, "y": 10.0, "width": 220.0, "height": 220.0] as [String: Any],
                "style": ["fill": "#fff"] as [String: Any],
                "clipPath": [
                    "type": "polygon",
                    "shape": ["points": pointer(target)] as [String: Any],
                    "extra": [
                        "angle": target,
                        "transition": ["angle"],
                        "enterFrom": ["angle": 0.0] as [String: Any]
                    ] as [String: Any],
                    "during": during
                ] as [String: Any]
            ] as [String: Any]
        }
        view.setOption([
            "animation": true,
            "animationDuration": 1000.0,
            "animationEasing": "linear",
            "xAxis": ["type": "value"] as [String: Any],
            "yAxis": ["type": "value"] as [String: Any],
            "series": [["type": "custom", "renderItem": renderItem, "data": [endAngle]] as [String: Any]]
        ])

        let host = try XCTUnwrap(ec.getModel()?.getSeriesByIndex(0)?.getData().getItemGraphicEl(0) as? Rect)
        let clipPath = try XCTUnwrap(host.getClipPath() as? ZRenderKit.Polygon)
        let animator = try XCTUnwrap(clipPath.animators.first { $0.targetName == "extra" })
        let clip = try XCTUnwrap(animator.getClip())
        clip.resetForDeterministicSampling()
        _ = clip.sampleForDeterministicRendering(at: 0)
        var shape = try XCTUnwrap(clipPath.shape as? PolygonShape)
        XCTAssertEqual(try XCTUnwrap(shape.points?.first).x, 210, accuracy: 1e-6,
                       "pointer entrance must start at angle zero")

        _ = clip.sampleForDeterministicRendering(at: 500)
        shape = try XCTUnwrap(clipPath.shape as? PolygonShape)
        let halfway = endAngle / 2
        XCTAssertEqual(try XCTUnwrap(shape.points?.first).x, 120 + cos(halfway) * 90, accuracy: 1e-6)
        XCTAssertEqual(try XCTUnwrap(shape.points?.first).y, 120 - sin(halfway) * 90, accuracy: 1e-6,
                       "custom clip-path during callback must rebuild pointer geometry every frame")
    }

    // A custom element's attached rich text must preserve the style bag and paint above its opaque
    // host. This is the path used by matrix/confusion-style custom cells: without the z2 lift the
    // label exists in the scene graph but is hidden behind a later opaque rectangle.
    func testCustomAttachedRichTextPreservesStyleAndPaintsAboveHost() {
        let ec = ECharts(width: 400, height: 300)
        let renderItem: CustomSeriesRenderItem = { _, api in
            let center = api.coord([0.0, 5.0], nil)
            guard center.count >= 2 else { return nil }
            return [
                "type": "rect",
                "shape": [
                    "x": center[0] - 60.0, "y": center[1] - 35.0,
                    "width": 120.0, "height": 70.0
                ] as [String: Any],
                "style": ["fill": "#d9534f"] as [String: Any],
                "textConfig": ["position": "inside"] as [String: Any],
                "textContent": [
                    "type": "text",
                    "style": [
                        "text": "{name|True Positive}\n{value|10}",
                        "fill": "#222222",
                        "align": "center",
                        "verticalAlign": "middle",
                        "rich": [
                            "name": [
                                "fill": "#ffffff",
                                "backgroundColor": "#666666",
                                "borderColor": "#111111",
                                "borderWidth": 2.0,
                                "borderRadius": 4.0,
                                "padding": [2.0, 5.0],
                                "fontSize": 18.0,
                                "fontWeight": "bold"
                            ] as [String: Any],
                            "value": ["fill": "#111111", "fontSize": 14.0] as [String: Any]
                        ] as [String: Any]
                    ] as [String: Any]
                ] as [String: Any]
            ] as [String: Any]
        }

        ec.setOption(customOption(renderItem, [[0, 5]], animation: false))

        var host: Rect?
        _ = ec.getRoot().traverse { el in
            if let rect = el as? Rect, rect.getTextContent() != nil { host = rect }
            return false
        }
        guard let host, let label = host.getTextContent() else {
            XCTFail("custom rect should own an attached textContent")
            return
        }

        XCTAssertEqual(label.textStyle?.text, "{name|True Positive}\n{value|10}")
        XCTAssertEqual(label.textStyle?.fill, "#222222")
        XCTAssertEqual(label.textStyle?.rich?["name"]?.fill, "#ffffff")
        XCTAssertEqual(label.textStyle?.rich?["name"]?.borderColor, "#111111")
        XCTAssertEqual(label.textStyle?.rich?["name"]?.borderWidth, 2.0)
        if case let .string(color)? = label.textStyle?.rich?["name"]?.backgroundColor {
            XCTAssertEqual(color, "#666666")
        }
        else {
            XCTFail("rich token backgroundColor should be bridged")
        }
        if case let .array(padding)? = label.textStyle?.rich?["name"]?.padding {
            XCTAssertEqual(padding, [2.0, 5.0])
        }
        else {
            XCTFail("rich token padding should be bridged")
        }
        XCTAssertGreaterThan(label.z2, host.z2,
            "attached custom labels must paint above their opaque host")
    }

    #if canImport(CoreGraphics) && canImport(ImageIO)
    // `style.decal` on a custom path resolves through createOrUpdatePatternFromDecal into a real Pattern.
    func testCustomStyleDecalResolvesToPattern() {
        let ec = ECharts(width: 400, height: 300)
        let renderItem = makeRectRenderItem(extraStyle: [
            "decal": ["symbol": "rect", "color": "#000", "dashArrayX": [5, 5], "dashArrayY": [5, 5]]
                as [String: Any]
        ])
        ec.setOption(customOption(renderItem, [[0, 5], [1, 8]], animation: false))

        var rects: [Rect] = []
        _ = ec.getRoot().traverse { el in
            if let r = el as? Rect { rects.append(r) }
            return false
        }
        XCTAssertEqual(rects.count, 2)
        for r in rects {
            XCTAssertTrue(r.pathStyle?.decal is ZRenderKit.Pattern,
                "style.decal must resolve to a tiling Pattern, got \(String(describing: r.pathStyle?.decal))")
        }
    }
    #endif
}
