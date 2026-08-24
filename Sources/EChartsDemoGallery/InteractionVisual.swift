// Headless, deterministic interaction-sequence screenshots for visual-agent review.

#if canImport(AppKit)

import AppKit
import ImageIO
import WebKit
import EChartsKit
import EChartsDemoCore
import NativePainter
import ZRenderKit

struct InteractionVisualScenario: Decodable {
    let id: String
    let demo: String
    let checks: [String]
    let steps: [InteractionVisualStep]
}

struct InteractionVisualStep: Decodable {
    let action: String
    let name: String?
    let movePointer: Bool?
    let x: Double?
    let y: Double?
    let seriesIndex: Double?
    let dataIndex: Double?
    let dataName: String?
    let milliseconds: Double?
    let deltaX: Double?
    let deltaY: Double?
    let deltaPercent: Double?
    let componentIndex: Double?
    let handleIndex: Double?
    let pieceIndex: Double?
    let targetType: String?
    let allowMissing: Bool?
    let capture: String?
}

private func loadInteractionScenario(_ path: String) throws -> InteractionVisualScenario {
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    return try JSONDecoder().decode(InteractionVisualScenario.self, from: data)
}

private func captureFileName(_ index: Int, _ label: String, side: String) -> String {
    let safe = label.map { character -> Character in
        character.isLetter || character.isNumber || character == "-" || character == "_"
            ? character : "-"
    }
    return String(format: "%02d-%@.%@.png", index, String(safe), side)
}

/// Snapshot the live zrender display list, not only `ec.getRoot()`. Tooltip text, axisPointer
/// crosshairs/labels/handles and other host-owned overlays are intentionally attached directly to
/// `view.zr`; rendering only the ECharts root silently drops exactly the transient UI this harness is
/// meant to verify.
@MainActor
private func renderInteractionView(
    _ view: EChartsView,
    size: CGSize,
    dpr: Double,
    backgroundColor: CGColor?
) -> CGImage? {
    let painter = CALayerPainter(size: size, dpr: dpr, backgroundColor: backgroundColor)
    guard let renderer = painter.beginFrame() as? CGRenderer else { return nil }
    for displayable in view.zr.storage.getDisplayList(true) {
        drawDisplayable(displayable, into: renderer)
    }
    return renderer.ctx.makeImage()
}

private func writeResolvedInteraction(
    scenario: InteractionVisualScenario,
    side: String,
    records: [[String: Any]],
    to url: URL
) {
    let object: [String: Any] = [
        "case": scenario.id,
        "demo": scenario.demo,
        "side": side,
        "records": records,
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else {
        return
    }
    try? data.write(to: url)
}

private func incrementFirstDataValuePerDataViewBlock(_ content: String) -> String {
    let separator = String(repeating: "-", count: 59)
    return content.components(separatedBy: separator).map { block in
        var lines = block.components(separatedBy: "\n")
        guard lines.count > 1 else { return block }
        for index in 1..<lines.count {
            var fields = lines[index].components(separatedBy: "\t")
            guard let last = fields.last, let value = Double(last) else { continue }
            fields[fields.count - 1] = String(format: "%g", value + 1)
            lines[index] = fields.joined(separator: "\t")
            break
        }
        return lines.joined(separator: "\n")
    }.joined(separator: separator)
}

@MainActor
private func interactionPNGData(_ view: EChartsView, options: [String: Any]) -> Data? {
    let ratio = (options["pixelRatio"] as? NSNumber)?.doubleValue ?? 1
    guard let image = renderInteractionView(
        view,
        size: CGSize(width: view.ec.getWidth(), height: view.ec.getHeight()),
        dpr: ratio,
        backgroundColor: CGColor(red: 1, green: 1, blue: 1, alpha: 1)
    ) else { return nil }
    return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
}

private func pngMetadata(_ data: Data, filename: String) -> [String: Any]? {
    guard Array(data.prefix(4)) == [0x89, 0x50, 0x4e, 0x47],
          let source = CGImageSourceCreateWithData(data as CFData, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    else { return nil }
    return [
        "emitted": true,
        "callbackCount": 1,
        "filename": filename,
        "mimeType": "image/png",
        "byteCount": data.count,
        "signatureHex": "89504e47",
        "pixelWidth": properties[kCGImagePropertyPixelWidth] ?? 0,
        "pixelHeight": properties[kCGImagePropertyPixelHeight] ?? 0,
    ]
}

@MainActor
private func resolvedDataAction(
    _ step: InteractionVisualStep, view: EChartsView
) -> [String: Any]? {
    let seriesIndex = step.seriesIndex ?? 0
    guard let series = view.ec.getModel()?.getSeriesByIndex(seriesIndex) else { return nil }
    let dataIndex: Int
    if let dataName = step.dataName {
        dataIndex = series.getData().indexOfName(dataName)
        guard dataIndex >= 0 else { return nil }
    }
    else {
        dataIndex = Int(step.dataIndex ?? 0)
    }
    return ["seriesIndex": seriesIndex, "dataIndex": Double(dataIndex)]
}

@MainActor
private func resolvedSeriesPoint(
    _ step: InteractionVisualStep, view: EChartsView
) -> (seriesIndex: Double, dataIndex: Int, point: [Double])? {
    let seriesIndex = step.seriesIndex ?? 0
    guard let series = view.ec.getModel()?.getSeriesByIndex(seriesIndex) else { return nil }
    let data = series.getData()
    let dataIndex: Int
    if let dataName = step.dataName {
        dataIndex = data.indexOfName(dataName)
    }
    else {
        dataIndex = Int(step.dataIndex ?? 0)
    }
    guard dataIndex >= 0 else { return nil }
    let action: [String: Any] = [
        "seriesIndex": seriesIndex,
        "dataIndex": Double(dataIndex),
    ]
    if let hit = resolveDeterministicDataHit(action, ec: view.ec, view: view) {
        return (seriesIndex, dataIndex, hit.point)
    }
    guard let points = data.getLayout("points") as? [Double],
          dataIndex * 2 + 1 < points.count else { return nil }
    let point = [points[dataIndex * 2], points[dataIndex * 2 + 1]]
    guard point[0].isFinite, point[1].isFinite,
          point[0] >= 0, point[0] <= view.ec.getWidth(),
          point[1] >= 0, point[1] <= view.ec.getHeight() else { return nil }
    return (seriesIndex, dataIndex, point)
}

@MainActor
private func dragInteractiveElement(
    kind: String, deltaX: Double, deltaY: Double, deltaPercent: Double?, view: EChartsView
) -> [Double]? {
    if kind == "dataZoom" {
        return view._injectSliderDataZoomDragForTest(
            deltaX: deltaX, deltaY: deltaY, deltaPercent: deltaPercent
        )
    }
    let height = view.ec.getHeight()
    let width = view.ec.getWidth()
    let candidates = view.zr.storage.getDisplayList(true).filter { element in
        guard element.draggable != .false else { return false }
        guard let bounds = element.getBoundingRect() else { return false }
        let center = element.transformCoordToGlobal(
            bounds.x + bounds.width / 2, bounds.y + bounds.height / 2
        )
        if kind == "axisPointer" {
            return center[0] >= width * 0.08 && center[0] <= width * 0.92
                && center[1] >= height * 0.68 && center[1] < height * 0.92
        }
        if kind == "timeline" { return true }
        return center[0] >= width * 0.08 && center[0] <= width * 0.85 && center[1] < height * 0.68
    }
    for candidate in candidates {
        guard let start = deterministicHoverPoint(candidate, accepting: { point in
            view.zr.handler.findHover(point[0], point[1]).target === candidate
        }) else { continue }
        var dx = deltaX
        var dy = deltaY
        if start[0] + dx < 2 || start[0] + dx > view.ec.getWidth() - 2 { dx = -dx }
        if start[1] + dy < 2 || start[1] + dy > view.ec.getHeight() - 2 { dy = -dy }
        view._injectPointerForTest(type: "mousemove", zrX: start[0], zrY: start[1])
        view._injectPointerForTest(type: "mousedown", zrX: start[0], zrY: start[1])
        for fraction in [0.25, 0.5, 0.75, 1.0] {
            view._injectPointerForTest(
                type: "mousemove", zrX: start[0] + dx * fraction, zrY: start[1] + dy * fraction
            )
        }
        if kind != "axisPointer" {
            view._injectPointerForTest(type: "mouseup", zrX: start[0] + dx, zrY: start[1] + dy)
        }
        return start
    }
    return nil
}

@MainActor
private func dragRoamingGeo(
    deltaX: Double, deltaY: Double, view: EChartsView
) -> [Double]? {
    guard let geoModel = view.ec.getModel()?
        .findComponents(QueryConditionKindA(mainType: "geo"))
        .compactMap({ $0 as? GeoModel })
        .first(where: {
            ($0.get("roam") as? Bool) == true || ($0.get("roam") as? String) != nil
        }), let geo = geoModel.coordinateSystem as? Geo else { return nil }
    let rect = geo.getViewRect()
    let start = [rect.x + rect.width / 2, rect.y + rect.height / 2]
    view._injectPointerForTest(type: "mousemove", zrX: start[0], zrY: start[1])
    view._injectPointerForTest(type: "mousedown", zrX: start[0], zrY: start[1])
    for fraction in [0.25, 0.5, 0.75, 1.0] {
        view._injectPointerForTest(
            type: "mousemove",
            zrX: start[0] + deltaX * fraction,
            zrY: start[1] + deltaY * fraction
        )
    }
    view._injectPointerForTest(
        type: "mouseup", zrX: start[0] + deltaX, zrY: start[1] + deltaY
    )
    return start
}

private func geoRegionEventData(at point: [Double], view: EChartsView) -> ECEventData? {
    var current = view.zr.handler.findHover(point[0], point[1]).target
    while let element = current {
        if let eventData = innerStore.getECData(element).eventData,
           (eventData["componentType"] as? String) == "geo" {
            return eventData
        }
        current = element.__hostTarget ?? (element.parent as? Element)
    }
    return nil
}

@MainActor
private func firstHitTestableGeoRegion(view: EChartsView) -> (name: String, point: [Double])? {
    let geos = view.ec.getModel()?
        .findComponents(QueryConditionKindA(mainType: "geo"))
        .compactMap { ($0 as? GeoModel)?.coordinateSystem as? Geo } ?? []
    for geo in geos {
        for region in geo.regions {
            guard let point = geo.dataToPoint(region.getCenter(), false),
                  point.count >= 2, point[0].isFinite, point[1].isFinite,
                  let eventData = geoRegionEventData(at: point, view: view),
                  (eventData["name"] as? String) == region.name else { continue }
            return (region.name, point)
        }
    }
    return nil
}

@MainActor
private func hoverGeoRegion(name: String, view: EChartsView) -> [Double]? {
    let geos = view.ec.getModel()?
        .findComponents(QueryConditionKindA(mainType: "geo"))
        .compactMap { ($0 as? GeoModel)?.coordinateSystem as? Geo } ?? []
    for geo in geos {
        guard let region = geo.getRegion(name),
              let point = geo.dataToPoint(region.getCenter(), false),
              point.count >= 2,
              (geoRegionEventData(at: point, view: view)?["name"] as? String) == name else {
            continue
        }
        view._injectPointerForTest(type: "mousemove", zrX: point[0], zrY: point[1])
        return point
    }
    return nil
}

@MainActor
private func wheelRoamingGeo(delta: Double, view: EChartsView) -> [Double]? {
    guard let geoModel = view.ec.getModel()?
        .findComponents(QueryConditionKindA(mainType: "geo"))
        .compactMap({ $0 as? GeoModel })
        .first(where: {
            let roam = $0.get("roam")
            return (roam as? Bool) == true || ((roam as? String).map { $0 != "move" } ?? false)
        }), let geo = geoModel.coordinateSystem as? Geo else { return nil }
    let rect = geo.getViewRect()
    let point = [rect.x + rect.width / 2, rect.y + rect.height / 2]
    view._injectWheelForTest(zrDelta: delta, zrX: point[0], zrY: point[1])
    return point
}

/// Minimal live-chart adapter for deterministic interaction scenarios. Timers are intentionally
/// inert: this runner advances only the explicit scenario steps, while event subscriptions and
/// synchronous setOption/dispatch calls remain live exactly as they are in the gallery host.
@MainActor
private final class InteractionVisualChart: EChartsDemoChart {
    let view: EChartsView
    private var intervalBodies: [@MainActor () -> Void] = []
    private var afterBodies: [@MainActor () -> Void] = []

    init(_ view: EChartsView) { self.view = view }

    func setOption(_ option: [String: Any], notMerge: Bool) {
        view.setOption(option, notMerge: notMerge)
    }

    func appendData(seriesIndex: Int, data: [Double]) {
        view.ec.appendData(seriesIndex: seriesIndex, data: data.map { $0 as Any })
        view.syncAfterAction()
    }

    func every(_ seconds: Double, _ body: @escaping @MainActor () -> Void) {
        intervalBodies.append(body)
    }
    func after(_ seconds: Double, _ body: @escaping @MainActor () -> Void) {
        afterBodies.append(body)
    }

    func runIntervalTick() -> Int {
        let bodies = intervalBodies
        for body in bodies { body() }
        return bodies.count
    }

    func runAfterTick() -> Int {
        let bodies = afterBodies
        afterBodies.removeAll()
        for body in bodies { body() }
        return bodies.count
    }

    var registeredIntervalCount: Int { intervalBodies.count }
    var registeredAfterCount: Int { afterBodies.count }

    func dispatch(_ payload: [String: Any]) {
        guard let type = payload["type"] as? String else { return }
        var action = Payload(type: type)
        action.other = payload.filter { $0.key != "type" }
        view.ec.dispatchAction(action)
        view.syncAfterAction()
    }

    func convertToPixel(_ finder: ModelFinder, _ value: CoordinateSystemDataCoord) -> Any? {
        view.ec.convertToPixel(finder, value)
    }

    func convertFromPixel(_ finder: ModelFinder, _ value: [Double]) -> Any? {
        view.ec.convertFromPixel(finder, value)
    }

    func on(_ event: String, _ handler: @escaping @MainActor (ECEventParams) -> Void) {
        view.on(event) { [weak self] params in
            MainActor.assumeIsolated {
                handler(params)
                self?.view.syncAfterAction()
            }
        }
    }
}

@MainActor
private func settleInteractionAnimations(_ root: Element) {
    var elements: [Element] = []
    var seenElements = Set<ObjectIdentifier>()
    func collect(_ element: Element) {
        guard seenElements.insert(ObjectIdentifier(element)).inserted else { return }
        elements.append(element)
        if let text = element.getTextContent() { collect(text) }
        if let guide = element.getTextGuideLine() { collect(guide) }
        if let group = element as? Group {
            for child in group.children() { collect(child) }
        }
    }
    collect(root)

    var seenClips = Set<ObjectIdentifier>()
    for clip in elements.flatMap(\.animators).compactMap({ $0.getClip() }) where
        seenClips.insert(ObjectIdentifier(clip)).inserted {
        clip.resetForDeterministicSampling()
        if clip.sampleForDeterministicRendering(at: 1_000_000_000) {
            clip.ondestroy()
        }
    }
}

private func interactionSlug(_ value: String) -> String {
    let result = value.lowercased().map { character -> Character in
        character.isLetter || character.isNumber ? character : "-"
    }
    return String(result).split(separator: "-").filter { !$0.isEmpty }.joined(separator: "-")
}

@MainActor
private func writeOfficialInteractionScenarios(
    category: String,
    seriesSubtypes: Set<String>,
    outputDirectory: String
) -> Bool {
    guard let section = demoSections(.official).first(where: {
        $0.title.caseInsensitiveCompare(category) == .orderedSame
    }) else {
        FileHandle.standardError.write(Data("official \(category) section was not found\n".utf8))
        return false
    }
    let directory = URL(fileURLWithPath: outputDirectory, isDirectory: true)
    do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
    catch {
        FileHandle.standardError.write(Data("could not create scenario directory: \(error)\n".utf8))
        return false
    }

    var manifest: [[String: Any]] = []
    for demo in section.demos where demo.nativeSupported {
        let view = EChartsView(width: demo.width, height: demo.height)
        view.setOption(demo.liveOption ?? demo.option)
        let chart = InteractionVisualChart(view)
        demo.drive?(chart)
        settleInteractionAnimations(view.ec.getRoot())
        guard let ecModel = view.ec.getModel() else { return false }

        var steps: [[String: Any]]
        if demo.liveOption != nil, chart.registeredAfterCount > 0 {
            // The Web demo and Native demo both expose the first asynchronous data arrival through
            // the logical one-shot clock. Advance that first callback before taking the baseline so
            // neither side is compared while one still has an empty series.
            steps = [
                ["action": "driveAfterTick"],
                ["action": "settle", "capture": "baseline"],
            ]
        }
        else {
            steps = [["action": "settle", "capture": "baseline"]]
        }
        var selectedSeries: [SeriesModel] = []
        var hitIndexBySeries: [Int: Int] = [:]
        var hoverInteractionCount = 0
        var coverageNotes: [String] = []
        let noVisibleSeriesHoverDemos: Set<String> = [
            "official-lines-ny",
            "official-matrix-stock",
        ]
        let hasUserVisibleSeriesHover = !noVisibleSeriesHoverDemos.contains(demo.name)
        if !hasUserVisibleSeriesHover {
            coverageNotes.append(
                "series have no authored tooltip or visually distinguishable hover state"
            )
        }
        let matchingSeries = hasUserVisibleSeriesHover ? ecModel.getSeries().filter {
            (seriesSubtypes.isEmpty || seriesSubtypes.contains($0.subType))
                && ($0.get("silent") as? Bool) != true
        } : []
        let samplePositions = matchingSeries.count <= 4
            ? Array(matchingSeries.indices)
            : [0, matchingSeries.count / 2, max(0, matchingSeries.count - 1)]
        for position in samplePositions where !matchingSeries.isEmpty {
            let series = matchingSeries[position]
            if !selectedSeries.contains(where: { $0 === series }) { selectedSeries.append(series) }
        }
        for series in selectedSeries {
            let data = series.getData()
            let count = data.count()
            guard count > 0 else { continue }
            let middle = count / 2
            let index: Int
            if category == "pie", demo.name == "official-pie-rich-text",
               data.indexOfName("CityE") >= 0 {
                index = data.indexOfName("CityE")
            }
            else if series.subType == "line" {
                guard let points = data.getLayout("points") as? [Double] else { continue }
                let candidates = (0..<min(count, points.count / 2)).sorted {
                    abs($0 - middle) < abs($1 - middle)
                }
                guard let pointIndex = candidates.first(where: {
                    points[$0 * 2].isFinite && points[$0 * 2 + 1].isFinite
                }) else { continue }
                index = pointIndex
            }
            else {
                var candidates = [middle]
                // The web reference keeps only the first progressive chunk attached to the live
                // display tree. Later chunks are painted incrementally and cannot be reached by a
                // real pointer hit even though the data and coordinate layout still exist. Prefer
                // an early, retained datum for large progressive series so Native and Web exercise
                // the same genuinely hit-testable symbol.
                if count > 2_000 {
                    candidates = Array(0..<min(32, count)) + candidates
                }
                for offset in 1...min(32, max(1, count - 1)) {
                    if middle - offset >= 0 { candidates.append(middle - offset) }
                    if middle + offset < count { candidates.append(middle + offset) }
                }
                if count > 65 {
                    for bucket in 0..<64 {
                        let candidate = (count - 1) * bucket / 63
                        if !candidates.contains(candidate) { candidates.append(candidate) }
                    }
                }
                if !candidates.contains(0) { candidates.append(0) }
                if !candidates.contains(count - 1) { candidates.append(count - 1) }
                guard let hitIndex = candidates.first(where: { candidate in
                    resolveDeterministicDataHit([
                        "seriesIndex": Double(series.seriesIndex),
                        "dataIndex": Double(candidate),
                    ], ec: view.ec, view: view) != nil
                }) else { continue }
                index = hitIndex
            }
            let seriesIndex = Int(series.seriesIndex)
            hitIndexBySeries[seriesIndex] = index
            steps.append([
                "action": series.subType == "line" ? "hoverSeries" : "hoverData",
                "seriesIndex": Double(seriesIndex),
                "dataIndex": Double(index)
            ])
            steps.append(["action": "wait", "milliseconds": 120.0])
            steps.append(["action": "settle", "capture": "hover-series-\(seriesIndex)"])
            hoverInteractionCount += 1
        }
        if hoverInteractionCount > 0 {
            steps += [
                ["action": "pointerMove", "x": 1.0, "y": 1.0],
                ["action": "globalOut"],
                ["action": "wait", "milliseconds": 700.0],
                ["action": "settle", "capture": "hover-restored"],
            ]
        }

        if category == "pie", demo.name == "official-dataset-link" {
            let linkedLines = ecModel.getSeries().filter {
                $0.subType == "line" && ($0.get("silent") as? Bool) != true
            }
            let linkedPositions = linkedLines.count <= 4
                ? Array(linkedLines.indices)
                : [0, linkedLines.count / 2, max(0, linkedLines.count - 1)]
            var linkedHoverCount = 0
            for position in linkedPositions where !linkedLines.isEmpty {
                let series = linkedLines[position]
                let data = series.getData()
                guard data.count() > 0 else { continue }
                let index = min(3, data.count() - 1)
                guard resolveDeterministicDataHit([
                    "seriesIndex": Double(series.seriesIndex), "dataIndex": Double(index),
                ], ec: view.ec, view: view) != nil else { continue }
                let seriesIndex = Int(series.seriesIndex)
                steps += [
                    [
                        "action": "hoverData", "seriesIndex": Double(seriesIndex),
                        "dataIndex": Double(index),
                    ],
                    ["action": "wait", "milliseconds": 120.0],
                    ["action": "settle", "capture": "linked-line-hover-series-\(seriesIndex)"],
                ]
                linkedHoverCount += 1
            }
            if linkedHoverCount > 0 {
                steps += [
                    ["action": "pointerMove", "x": 1.0, "y": 1.0],
                    ["action": "globalOut"],
                    ["action": "wait", "milliseconds": 700.0],
                    ["action": "settle", "capture": "linked-line-hover-restored"],
                ]
            }
        }

        struct LegendInteraction {
            var name: String
            var singleMode: Bool
            var initialName: String?
            var initiallySelected: Bool
        }
        var legendNames: [String] = []
        var legendInteractions: [LegendInteraction] = []
        var seenLegendNames = Set<String>()
        var hasScrollableLegend = false
        func hasLegendProvider(_ name: String) -> Bool {
            ecModel.getSeries().contains { series in
                if series.name == name { return true }
                let data = series.getData()
                return (0..<data.count()).contains { data.getName($0) == name }
            }
        }
        for component in ecModel.findComponents(QueryConditionKindA(mainType: "legend")) {
            guard let legend = component as? LegendModel,
                  (legend.get("show") as? Bool) != false,
                  (legend.get("selectedMode") as? Bool) != false else { continue }
            var componentNames: [String] = []
            var authoredItemCount = 0
            for item in legend.getData() {
                guard let name = model.convertOptionIdName(item.get("name", true), nil),
                      !name.isEmpty else { continue }
                authoredItemCount += 1
                guard hasLegendProvider(name),
                      seenLegendNames.insert(name).inserted else { continue }
                componentNames.append(name)
            }
            if authoredItemCount > 0, componentNames.isEmpty {
                coverageNotes.append(
                    "legend has authored items but none matches a live series or data provider"
                )
            }
            if legend.subType == "scroll", componentNames.count > 3 {
                hasScrollableLegend = true
                componentNames = Array(componentNames.prefix(3))
            }
            legendNames.append(contentsOf: componentNames)
            let singleMode = (legend.get("selectedMode") as? String) == "single"
            let initialName = singleMode ? componentNames.first(where: { legend.isSelected($0) }) : nil
            legendInteractions.append(contentsOf: componentNames.map {
                LegendInteraction(
                    name: $0,
                    singleMode: singleMode,
                    initialName: initialName,
                    initiallySelected: legend.isSelected($0)
                )
            })
        }
        // This official option positions its horizontal slider directly under the legend. Their live
        // hit regions overlap, so a pointer click at the visible legend swatch is received by the
        // slider and changes the data window instead of selecting a series. Record the coverage gap
        // explicitly and exercise the slider below; dispatchAction would no longer be a UI hit test.
        let skippedLegendReason: String? = category == "bar"
            && demo.name == "official-mix-zoom-on-value"
            ? "legend hit regions overlap the horizontal dataZoom slider; pointer clicks resolve to the slider"
            : nil
        if let skippedLegendReason { coverageNotes.append(skippedLegendReason) }
        let interactiveLegends = skippedLegendReason == nil ? legendInteractions : []
        for interaction in interactiveLegends {
            let name = interaction.name
            let slug = interactionSlug(name)
            steps += [
                ["action": "clickLegend", "name": name, "movePointer": true],
                ["action": "pointerMove", "x": 1.0, "y": 1.0],
                ["action": "globalOut"],
                ["action": "wait", "milliseconds": 700.0],
                [
                    "action": "settle",
                    "capture": interaction.singleMode
                        ? "legend-\(slug)-selected"
                        : "legend-\(slug)-\(interaction.initiallySelected ? "off" : "on")"
                ],
            ]
            if interaction.singleMode {
                if let initialName = interaction.initialName, initialName != name {
                    steps.append([
                        "action": "clickLegend", "name": initialName, "movePointer": true
                    ])
                }
            }
            else {
                steps.append(["action": "clickLegend", "name": name, "movePointer": true])
            }
            steps += [
                ["action": "pointerMove", "x": 1.0, "y": 1.0],
                ["action": "globalOut"],
                ["action": "wait", "milliseconds": 700.0],
                ["action": "settle", "capture": "legend-\(slug)-restored"],
            ]
        }
        if hasScrollableLegend {
            steps += [
                ["action": "clickLegendPage", "name": "pageNext"],
                ["action": "pointerMove", "x": 1.0, "y": 1.0],
                ["action": "globalOut"],
                ["action": "settle", "capture": "legend-page-next"],
                ["action": "clickVisibleLegendItem", "dataIndex": 0.0],
                ["action": "pointerMove", "x": 1.0, "y": 1.0],
                ["action": "globalOut"],
                ["action": "settle", "capture": "legend-page-item-off"],
                ["action": "clickVisibleLegendItem", "dataIndex": 0.0],
                ["action": "pointerMove", "x": 1.0, "y": 1.0],
                ["action": "globalOut"],
                ["action": "settle", "capture": "legend-page-item-restored"],
                ["action": "clickLegendPage", "name": "pagePrev"],
                ["action": "pointerMove", "x": 1.0, "y": 1.0],
                ["action": "globalOut"],
                ["action": "settle", "capture": "legend-page-restored"],
            ]
        }

        if category == "pie",
           let selectable = matchingSeries.first(where: { series in
               let selectedMode = series.get("selectedMode")
               return selectedMode != nil && (selectedMode as? Bool) != false
                   && hitIndexBySeries[Int(series.seriesIndex)] != nil
           }), let index = hitIndexBySeries[Int(selectable.seriesIndex)] {
            let seriesIndex = Int(selectable.seriesIndex)
            var initialSingleSelection: Int?
            if (selectable.get("selectedMode") as? String) == "single" {
                initialSingleSelection = (0..<selectable.getData().count()).first {
                    selectable.isSelected(Double($0))
                }
            }
            steps += [
                [
                    "action": "clickData", "seriesIndex": Double(seriesIndex),
                    "dataIndex": Double(index), "movePointer": true,
                ],
            ]
            steps += [
                ["action": "pointerMove", "x": 1.0, "y": 1.0],
                ["action": "globalOut"],
                ["action": "wait", "milliseconds": 700.0],
                ["action": "settle", "capture": "pie-selection-toggled"],
            ]
            let restoreIndex = initialSingleSelection.flatMap { initial in
                initial != index && resolveDeterministicDataHit([
                    "seriesIndex": Double(seriesIndex), "dataIndex": Double(initial),
                ], ec: view.ec, view: view) != nil ? initial : nil
            } ?? index
            steps += [
                [
                    "action": "clickData", "seriesIndex": Double(seriesIndex),
                    "dataIndex": Double(restoreIndex), "movePointer": true,
                ],
                ["action": "pointerMove", "x": 1.0, "y": 1.0],
                ["action": "globalOut"],
                ["action": "wait", "milliseconds": 700.0],
                ["action": "settle", "capture": "pie-selection-restored"],
            ]
        }

        let hasSlider = ecModel.findComponents(QueryConditionKindA(mainType: "dataZoom"))
            .contains { $0.subType == "slider" && ($0.get("show") as? Bool) != false }
        let toolboxNames = Set(view.zr.storage.getDisplayList(true).compactMap {
            innerStore.getECData($0).tooltipConfig?.name
        })
        let hasRestore = toolboxNames.contains("restore")
        if hasSlider {
            let usesSemanticZoomDelta = category == "bar"
                && demo.name == "official-mix-zoom-on-value"
            var dragStep: [String: Any] = [
                "action": "dragDataZoom", "deltaX": 48.0, "deltaY": 0.0,
            ]
            if usesSemanticZoomDelta { dragStep["deltaPercent"] = 2.0 }
            steps += [
                dragStep,
                ["action": "wait", "milliseconds": 180.0],
                ["action": "settle", "capture": "datazoom-dragged"],
                ["action": "pointerMove", "x": 1.0, "y": 1.0],
                ["action": "globalOut"],
                ["action": "wait", "milliseconds": 700.0],
                ["action": "settle", "capture": "datazoom-drag-cleared"],
            ]
        }
        let calculableVisualMaps = ecModel
            .findComponents(QueryConditionKindA(mainType: "visualMap"))
            .filter {
                $0.subType == "continuous" && ($0.get("calculable") as? Bool) == true
            }
        for (visualMapIndex, visualMapModel) in calculableVisualMaps.enumerated() {
            let horizontal = (visualMapModel.get("orient") as? String) == "horizontal"
            let dx = horizontal ? -30.0 : 0.0
            let dy = horizontal ? 0.0 : 30.0
            steps += [
                [
                    "action": "dragVisualMap", "componentIndex": Double(visualMapIndex),
                    "handleIndex": 1.0, "deltaX": dx, "deltaY": dy,
                ],
                ["action": "pointerMove", "x": 1.0, "y": 1.0],
                ["action": "globalOut"],
                ["action": "wait", "milliseconds": 700.0],
                ["action": "settle", "capture": "visualmap-\(visualMapIndex)-dragged"],
                [
                    "action": "dragVisualMap", "componentIndex": Double(visualMapIndex),
                    "handleIndex": 1.0, "deltaX": -dx, "deltaY": -dy,
                ],
                ["action": "pointerMove", "x": 1.0, "y": 1.0],
                ["action": "globalOut"],
                ["action": "wait", "milliseconds": 700.0],
                ["action": "settle", "capture": "visualmap-\(visualMapIndex)-restored"],
            ]
        }
        let selectablePiecewiseVisualMaps = ecModel
            .findComponents(QueryConditionKindA(mainType: "visualMap"))
            .compactMap { $0 as? PiecewiseModel }
            .filter {
                ($0.get("show") as? Bool) != false
                    && ($0.get("selectedMode") as? Bool) != false
            }
        for (visualMapIndex, visualMapModel) in selectablePiecewiseVisualMaps.enumerated() {
            let pieces = visualMapModel.getPieceList()
            guard !pieces.isEmpty else { continue }
            let pieceIndex = pieces.count / 2
            let piece = pieces[pieceIndex]
            let label = (piece["text"] as? String)
                ?? (piece["value"] as? String)
                ?? (piece["value"] as? NSNumber)?.stringValue
                ?? ""
            steps += [
                [
                    "action": "clickVisualMapPiece",
                    "componentIndex": Double(visualMapIndex),
                    "pieceIndex": Double(pieceIndex),
                    "dataName": label,
                ],
                ["action": "pointerMove", "x": 1.0, "y": 1.0],
                ["action": "globalOut"],
                ["action": "settle", "capture": "visualmap-piece-\(visualMapIndex)-off"],
                [
                    "action": "clickVisualMapPiece",
                    "componentIndex": Double(visualMapIndex),
                    "pieceIndex": Double(pieceIndex),
                    "dataName": label,
                ],
                ["action": "pointerMove", "x": 1.0, "y": 1.0],
                ["action": "globalOut"],
                ["action": "settle", "capture": "visualmap-piece-\(visualMapIndex)-restored"],
            ]
        }
        let brushModels = ecModel.findComponents(QueryConditionKindA(mainType: "brush"))
            .compactMap { $0 as? BrushModel }
        if let brushModel = brushModels.first,
           toolboxNames.contains("rect"), toolboxNames.contains("clear") {
            let targetType = brushModel.get("geoIndex") != nil ? "geo" : "grid"
            if !brushModel.areas.isEmpty {
                steps += [
                    ["action": "clickToolbox", "name": "clear", "movePointer": true],
                    ["action": "pointerMove", "x": 1.0, "y": 1.0],
                    ["action": "globalOut"],
                    ["action": "wait", "milliseconds": 500.0],
                    ["action": "settle", "capture": "brush-initial-cleared"],
                ]
            }
            steps += [
                ["action": "clickToolbox", "name": "rect", "movePointer": true],
                [
                    "action": "dragBrush", "name": "rect", "targetType": targetType,
                    "componentIndex": 0.0,
                ],
                ["action": "pointerMove", "x": 1.0, "y": 1.0],
                ["action": "globalOut"],
                ["action": "wait", "milliseconds": 500.0],
                ["action": "settle", "capture": "brush-rect"],
                ["action": "clickToolbox", "name": "clear", "movePointer": true],
                ["action": "pointerMove", "x": 1.0, "y": 1.0],
                ["action": "globalOut"],
                ["action": "wait", "milliseconds": 500.0],
                ["action": "settle", "capture": "brush-rect-cleared"],
            ]
            if toolboxNames.contains("polygon") {
                steps += [
                    ["action": "clickToolbox", "name": "polygon", "movePointer": true],
                    [
                        "action": "dragBrush", "name": "polygon", "targetType": targetType,
                        "componentIndex": 0.0,
                    ],
                    ["action": "pointerMove", "x": 1.0, "y": 1.0],
                    ["action": "globalOut"],
                    ["action": "wait", "milliseconds": 500.0],
                    ["action": "settle", "capture": "brush-polygon"],
                    ["action": "clickToolbox", "name": "clear", "movePointer": true],
                    ["action": "pointerMove", "x": 1.0, "y": 1.0],
                    ["action": "globalOut"],
                    ["action": "wait", "milliseconds": 500.0],
                    ["action": "settle", "capture": "brush-polygon-cleared"],
                ]
            }
        }
        let geoRegionHit = firstHitTestableGeoRegion(view: view)
        if let geoRegionHit {
            steps += [
                ["action": "hoverGeoRegion", "name": geoRegionHit.name],
                ["action": "wait", "milliseconds": 120.0],
                ["action": "settle", "capture": "geo-region-hover"],
                ["action": "pointerMove", "x": 1.0, "y": 1.0],
                ["action": "globalOut"],
                ["action": "wait", "milliseconds": 700.0],
                ["action": "settle", "capture": "geo-region-hover-restored"],
            ]
        }
        let roamingGeos = demo.name == "official-scatter-map-brush"
            ? []
            : ecModel.findComponents(QueryConditionKindA(mainType: "geo")).filter {
                ($0.get("roam") as? Bool) == true || ($0.get("roam") as? String) != nil
            }
        let canPanGeo = roamingGeos.contains {
            ($0.get("roam") as? Bool) == true || ($0.get("roam") as? String) != "scale"
        }
        let canZoomGeo = roamingGeos.contains {
            ($0.get("roam") as? Bool) == true || ($0.get("roam") as? String) != "move"
        }
        if canPanGeo {
            steps += [
                ["action": "dragGeoRoam", "deltaX": 36.0, "deltaY": 24.0],
                ["action": "pointerMove", "x": 1.0, "y": 1.0],
                ["action": "globalOut"],
                ["action": "wait", "milliseconds": 700.0],
                ["action": "settle", "capture": "geo-panned"],
                ["action": "dragGeoRoam", "deltaX": -36.0, "deltaY": -24.0],
                ["action": "pointerMove", "x": 1.0, "y": 1.0],
                ["action": "globalOut"],
                ["action": "wait", "milliseconds": 700.0],
                ["action": "settle", "capture": "geo-pan-restored"],
            ]
        }
        if canZoomGeo {
            steps += [
                ["action": "wheelGeoRoam", "deltaY": 3.0],
                ["action": "pointerMove", "x": 1.0, "y": 1.0],
                ["action": "globalOut"],
                ["action": "wait", "milliseconds": 700.0],
                ["action": "settle", "capture": "geo-zoomed"],
                ["action": "wheelGeoRoam", "deltaY": -3.0],
                ["action": "pointerMove", "x": 1.0, "y": 1.0],
                ["action": "globalOut"],
                ["action": "wait", "milliseconds": 700.0],
                ["action": "settle", "capture": "geo-zoom-restored"],
            ]
        }
        if let timeline = ecModel.findComponents(QueryConditionKindA(mainType: "timeline")).first,
           (timeline.get("show") as? Bool) != false {
            let vertical = (timeline.get("orient") as? String) == "vertical"
            steps += [
                [
                    "action": "dragTimeline",
                    "deltaX": vertical ? 0.0 : 120.0,
                    "deltaY": vertical ? 90.0 : 0.0,
                ],
                ["action": "wait", "milliseconds": 180.0],
                ["action": "settle", "capture": "timeline-dragged"],
                ["action": "pointerMove", "x": 1.0, "y": 1.0],
                ["action": "globalOut"],
            ]
        }
        if category == "line" && demo.name == "official-line-draggable" {
            steps += [[
                "action": "dragGraphic", "deltaX": 42.0, "deltaY": 24.0,
                "allowMissing": true, "capture": "graphic-point-dragged"
            ]]
        }
        if category == "line" && demo.name == "official-line-tooltip-touch" {
            steps += [[
                "action": "dragAxisPointer", "deltaX": 56.0, "deltaY": 0.0,
            ], [
                "action": "wait", "milliseconds": 180.0
            ], [
                "action": "settle", "capture": "axis-pointer-handle-dragged"
            ]]
        }
        let completesPieToolbox = category == "pie"
            && (demo.name == "official-pie-roseType"
                || demo.name == "official-pie-roseType-simple")
        if completesPieToolbox && toolboxNames.contains("dataView") {
            steps += [
                ["action": "editDataView"],
                ["action": "wait", "milliseconds": 180.0],
                ["action": "settle", "capture": "toolbox-dataview-refreshed"],
            ]
        }
        if hasRestore && (hasSlider || !interactiveLegends.isEmpty || completesPieToolbox) {
            steps += [
                ["action": "clickToolbox", "name": "restore", "movePointer": true],
                ["action": "pointerMove", "x": 1.0, "y": 1.0],
                ["action": "globalOut"],
                ["action": "wait", "milliseconds": 700.0],
                [
                    "action": "settle",
                    "capture": completesPieToolbox ? "toolbox-restored" : "final-restored",
                ],
            ]
        }
        if completesPieToolbox && toolboxNames.contains("saveAsImage") {
            steps += [["action": "saveToolboxImage"]]
        }

        if category == "bar", demo.name.contains("drilldown"),
           let series = selectedSeries.first {
            let data = series.getData()
            let index = max(0, data.count() / 2)
            if data.count() > 0 {
                steps += [
                    [
                        "action": "clickData", "seriesIndex": Double(series.seriesIndex),
                        "dataIndex": Double(index), "movePointer": true,
                    ],
                    ["action": "wait", "milliseconds": 180.0],
                    ["action": "settle", "capture": "bar-click-drilldown"],
                ]
            }
        }

        if chart.registeredIntervalCount > 0 {
            let tickCount = demo.name == "official-scatter-symbol-morph" ? 11 : 2
            for tick in 1...tickCount {
                steps += [
                    ["action": "driveTick"],
                    ["action": "settle", "capture": "drive-tick-\(tick)"],
                ]
            }
        }
        if demo.liveOption != nil, chart.registeredAfterCount > 0 {
            // The first link was advanced before the baseline. Advance the remaining links, settle
            // each appended progressive batch, but retain screenshots only at the meaningful midpoint
            // and completed stream.
            for tick in 1..<32 {
                steps.append(["action": "driveAfterTick"])
                if tick == 15 {
                    steps.append(["action": "settle", "capture": "stream-midpoint-16"])
                }
                else if tick == 31 {
                    steps.append(["action": "settle", "capture": "stream-complete-32"])
                }
                else {
                    steps.append(["action": "settle"])
                }
            }
        }

        var scenario: [String: Any] = [
            "id": "\(category)-all-\(demo.name)",
            "demo": demo.name,
            "checks": [
                "Every requested \(category)-series hover must resolve on the live chart; moving out must clear tooltip, axisPointer and emphasis without stale state.",
                "Every requested hit-testable legend item must toggle to the opposite of its authored initial state and back in the same instance; the restored frame must recover the initial series, symbols, labels and annotations.",
                "When a slider dataZoom exists, a real Handler drag must change the visible window consistently in Native and Web, and pointer cleanup must remove temporary handle state.",
                "Interactive \(category) examples must react to their scenario-specific click or drag action consistently in Native and Web.",
                "Timer-driven examples must reach the same settled state after each explicit logical interval tick in Native and Web.",
                "Native and Web must agree semantically after every interaction; ignore font antialiasing and subpixel stroke differences.",
            ],
            "steps": steps,
        ]
        if !coverageNotes.isEmpty {
            scenario["coverageNotes"] = coverageNotes
        }
        let file = "\(category)-all-\(demo.name).json"
        do {
            let data = try JSONSerialization.data(
                withJSONObject: scenario, options: [.prettyPrinted, .sortedKeys]
            )
            try data.write(to: directory.appendingPathComponent(file))
        }
        catch {
            FileHandle.standardError.write(Data("could not write \(file): \(error)\n".utf8))
            return false
        }
        manifest.append([
            "demo": demo.name, "scenario": file, "legendCount": legendNames.count,
            "legendInteractionCount": interactiveLegends.count,
            "hoverSeriesCount": hoverInteractionCount, "hasSlider": hasSlider,
            "hasRestore": hasRestore, "hasGeoRoam": !roamingGeos.isEmpty,
            "hasGeoRegionHover": geoRegionHit != nil,
            "calculableVisualMapCount": calculableVisualMaps.count,
            "coverageNotes": coverageNotes,
        ])
        view.dispose()
        print("wrote \(file)")
    }
    do {
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: directory.appendingPathComponent("manifest.json"))
    }
    catch {
        FileHandle.standardError.write(Data("could not write \(category) manifest: \(error)\n".utf8))
        return false
    }
    print("generated \(manifest.count) \(category) interaction scenarios")
    return true
}

@MainActor
func writeLineInteractionScenarios(outputDirectory: String) -> Bool {
    writeOfficialInteractionScenarios(
        category: "line", seriesSubtypes: ["line"], outputDirectory: outputDirectory
    )
}

@MainActor
func writeBarInteractionScenarios(outputDirectory: String) -> Bool {
    writeOfficialInteractionScenarios(
        category: "bar", seriesSubtypes: ["bar"], outputDirectory: outputDirectory
    )
}

@MainActor
func writePieInteractionScenarios(outputDirectory: String) -> Bool {
    writeOfficialInteractionScenarios(
        category: "pie", seriesSubtypes: ["pie"], outputDirectory: outputDirectory
    )
}

@MainActor
func writeScatterInteractionScenarios(outputDirectory: String) -> Bool {
    writeOfficialInteractionScenarios(
        category: "scatter", seriesSubtypes: ["scatter", "effectScatter"],
        outputDirectory: outputDirectory
    )
}

@MainActor
func writeMapInteractionScenarios(outputDirectory: String) -> Bool {
    // Map demos deliberately mix map/geo with pie, scatter, lines, graph, bar, and custom
    // series. An empty subtype filter exercises every non-silent interactive series instead
    // of silently dropping the overlays that make these demos useful interaction fixtures.
    writeOfficialInteractionScenarios(
        category: "map", seriesSubtypes: [], outputDirectory: outputDirectory
    )
}

@MainActor
func writeCategoryInteractionScenarios(category: String, outputDirectory: String) -> Bool {
    guard EChartsDemoRegistry.officialCategoryOrder.contains(category) else {
        FileHandle.standardError.write(Data("unknown official category: \(category)\n".utf8))
        return false
    }
    // The remaining official sections are not type-pure: a category may include overlays from
    // lines, scatter, custom, graph, pie, or another series family. Exercise every non-silent
    // rendered series so the generic sweep cannot miss a user-reachable overlay interaction.
    return writeOfficialInteractionScenarios(
        category: category, seriesSubtypes: [], outputDirectory: outputDirectory
    )
}

@MainActor
func runNativeInteractionVisual(
    scenarioPath: String,
    outputDirectory: String,
    resolvedPath: String
) -> Bool {
    let scenario: InteractionVisualScenario
    do { scenario = try loadInteractionScenario(scenarioPath) }
    catch {
        FileHandle.standardError.write(Data("invalid interaction scenario: \(error)\n".utf8))
        return false
    }
    guard let demo = EChartsDemoRegistry.byName(scenario.demo), demo.nativeSupported else {
        FileHandle.standardError.write(Data("unknown or native-unsupported demo: \(scenario.demo)\n".utf8))
        return false
    }

    let directory = URL(fileURLWithPath: outputDirectory, isDirectory: true)
    do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
    catch {
        FileHandle.standardError.write(Data("could not create output directory: \(error)\n".utf8))
        return false
    }

    let view = EChartsView(width: demo.width, height: demo.height)
    view.setOption(demo.liveOption ?? demo.option)
    let chart = InteractionVisualChart(view)
    demo.drive?(chart)
    var presentedDataView: ToolboxDataViewPresentation?
    var dataViewCallbackCount = 0
    view.ec.onPresentDataView = { presentation in
        dataViewCallbackCount += 1
        presentedDataView = presentation
    }
    var savedImageData: Data?
    var savedImageFilename: String?
    var saveCallbackCount = 0
    var saveRenderOptions: [String: Any] = [:]
    view.ec.getRenderedImage = { [weak view] options in
        guard let view else { return nil }
        saveRenderOptions = options
        return interactionPNGData(view, options: options)
    }
    view.ec.onSaveImage = { data, filename in
        saveCallbackCount += 1
        savedImageData = data
        savedImageFilename = filename
    }
    func firstSeriesValues() -> [Any] {
        view.ec.getModel()?.getSeries().map { series -> Any in
            let item = series.getData().getRawDataItem(0)
            if let dict = item as? [String: Any] { return dict["value"] ?? NSNull() }
            if let array = item as? [Any] { return array.first ?? NSNull() }
            return item
        } ?? []
    }
    let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
    var captureIndex = 0
    var records: [[String: Any]] = []

    for (stepIndex, step) in scenario.steps.enumerated() {
        var record: [String: Any] = ["step": stepIndex, "action": step.action]
        switch step.action {
        case "settle":
            settleInteractionAnimations(view.ec.getRoot())
            record["seriesDataCounts"] = view.ec.getModel()?.getSeries().map {
                $0.getData().count()
            } ?? []
            let largeLinePaths = view.zr.storage.getDisplayList(true).compactMap {
                $0 as? LargeLinesPath
            }
            record["largeLines"] = [
                "pathCount": largeLinePaths.count,
                "segmentValueCount": largeLinePaths.reduce(0) {
                    $0 + (($1.shape as? LargeLinesPathShape)?.segs.count ?? 0)
                },
            ]
        case "clickLegend":
            guard let name = step.name,
                  let point = view._injectLegendClickForTest(
                    name: name, movePointer: step.movePointer ?? true
                  ) else {
                FileHandle.standardError.write(
                    Data("step \(stepIndex): legend item was not hit-testable\n".utf8)
                )
                return false
            }
            record["name"] = name
            record["resolvedPoint"] = point
        case "clickLegendPage":
            guard let name = step.name,
                  let point = view._injectScrollableLegendPageClickForTest(name: name) else {
                FileHandle.standardError.write(
                    Data("step \(stepIndex): scroll legend page control was not hit-testable\n".utf8)
                )
                return false
            }
            record["name"] = name
            record["resolvedPoint"] = point
        case "clickVisibleLegendItem":
            let visibleIndex = Int(step.dataIndex ?? 0)
            guard let point = view._injectVisibleScrollableLegendItemClickForTest(
                visibleIndex: visibleIndex
            ) else {
                FileHandle.standardError.write(
                    Data("step \(stepIndex): visible scroll legend item was not hit-testable\n".utf8)
                )
                return false
            }
            record["visibleIndex"] = visibleIndex
            record["resolvedPoint"] = point
        case "hoverData":
            guard let action = resolvedDataAction(step, view: view) else {
                FileHandle.standardError.write(
                    Data("step \(stepIndex): data item was not found in the current series\n".utf8)
                )
                return false
            }
            guard injectDeterministicHover(action, ec: view.ec, view: view) else {
                FileHandle.standardError.write(
                    Data("step \(stepIndex): data item was not hit-testable\n".utf8)
                )
                return false
            }
            record["seriesIndex"] = step.seriesIndex ?? 0
            record["dataIndex"] = action["dataIndex"]
            if let dataName = step.dataName { record["dataName"] = dataName }
        case "hoverSeries":
            guard let resolved = resolvedSeriesPoint(step, view: view) else {
                FileHandle.standardError.write(
                    Data("step \(stepIndex): line-series point was not resolvable\n".utf8)
                )
                return false
            }
            view._injectPointerForTest(
                type: "mousemove", zrX: resolved.point[0], zrY: resolved.point[1]
            )
            record["seriesIndex"] = resolved.seriesIndex
            record["dataIndex"] = Double(resolved.dataIndex)
            record["resolvedPoint"] = resolved.point
        case "clickData":
            guard let action = resolvedDataAction(step, view: view),
                  let point = injectDeterministicDataClick(
                    action, ec: view.ec, view: view, movePointer: step.movePointer ?? true
                  ) else {
                FileHandle.standardError.write(
                    Data("step \(stepIndex): data item was not hit-testable\n".utf8)
                )
                return false
            }
            record["seriesIndex"] = step.seriesIndex ?? 0
            record["dataIndex"] = action["dataIndex"]
            if let dataName = step.dataName { record["dataName"] = dataName }
            record["resolvedPoint"] = point
        case "clickToolbox":
            guard let name = step.name,
                  let point = injectDeterministicToolboxClick(
                    featureName: name, view: view, movePointer: step.movePointer ?? true
                  ) else {
                FileHandle.standardError.write(
                    Data("step \(stepIndex): toolbox feature was not hit-testable\n".utf8)
                )
                return false
            }
            record["name"] = name
            record["resolvedPoint"] = point
            if name == "restore" {
                record["hostOutput"] = [
                    "feature": "restore",
                    "emitted": true,
                    "seriesFirstValues": firstSeriesValues(),
                ]
            }
        case "editDataView":
            presentedDataView = nil
            let callbackCountBefore = dataViewCallbackCount
            let valuesBefore = firstSeriesValues()
            guard let point = injectDeterministicToolboxClick(
                featureName: "dataView", view: view, movePointer: true
            ), let presentation = presentedDataView else {
                FileHandle.standardError.write(
                    Data("step \(stepIndex): dataView presentation callback was not emitted\n".utf8)
                )
                return false
            }
            let edited = incrementFirstDataValuePerDataViewBlock(presentation.content)
            guard edited != presentation.content else {
                FileHandle.standardError.write(
                    Data("step \(stepIndex): dataView did not expose editable numeric rows\n".utf8)
                )
                return false
            }
            do { try presentation.refresh(edited) }
            catch {
                FileHandle.standardError.write(
                    Data("step \(stepIndex): dataView refresh failed: \(error)\n".utf8)
                )
                return false
            }
            record["resolvedPoint"] = point
            record["hostOutput"] = [
                "feature": "dataView",
                "emitted": true,
                "invocationCount": dataViewCallbackCount - callbackCountBefore,
                "title": presentation.title,
                "readOnly": presentation.readOnly,
                "contentLength": presentation.content.count,
                "blockCount": presentation.content
                    .components(separatedBy: String(repeating: "-", count: 59)).count,
                "seriesNames": view.ec.getModel()?.getSeries().map(\.name) ?? [],
                "valuesBefore": valuesBefore,
                "valuesAfter": firstSeriesValues(),
                "refreshed": true,
            ]
        case "saveToolboxImage":
            savedImageData = nil
            savedImageFilename = nil
            saveRenderOptions = [:]
            let callbackCountBefore = saveCallbackCount
            guard let point = injectDeterministicToolboxClick(
                featureName: "saveAsImage", view: view, movePointer: true
            ), let data = savedImageData, let filename = savedImageFilename,
                  var metadata = pngMetadata(data, filename: filename) else {
                FileHandle.standardError.write(
                    Data("step \(stepIndex): saveAsImage did not emit a valid PNG\n".utf8)
                )
                return false
            }
            metadata["callbackCount"] = saveCallbackCount - callbackCountBefore
            metadata["feature"] = "saveAsImage"
            metadata["excludeComponents"] = saveRenderOptions["excludeComponents"] ?? []
            record["resolvedPoint"] = point
            record["hostOutput"] = metadata
        case "dragGeoRoam":
            let dx = step.deltaX ?? 36
            let dy = step.deltaY ?? 24
            guard let point = dragRoamingGeo(deltaX: dx, deltaY: dy, view: view) else {
                FileHandle.standardError.write(
                    Data("step \(stepIndex): roaming geo was not available\n".utf8)
                )
                return false
            }
            record["resolvedPoint"] = point
            record["deltaX"] = dx
            record["deltaY"] = dy
        case "wheelGeoRoam":
            let delta = step.deltaY ?? 3
            guard let point = wheelRoamingGeo(delta: delta, view: view) else {
                FileHandle.standardError.write(
                    Data("step \(stepIndex): zoomable geo was not available\n".utf8)
                )
                return false
            }
            record["resolvedPoint"] = point
            record["delta"] = delta
        case "hoverGeoRegion":
            guard let name = step.name,
                  let point = hoverGeoRegion(name: name, view: view) else {
                FileHandle.standardError.write(
                    Data("step \(stepIndex): geo region was not hit-testable\n".utf8)
                )
                return false
            }
            record["resolvedPoint"] = point
            record["name"] = name
        case "dragVisualMap":
            let componentIndex = Int(step.componentIndex ?? 0)
            let handleIndex = Int(step.handleIndex ?? 1)
            let dx = step.deltaX ?? 0
            let dy = step.deltaY ?? 30
            guard let point = view._injectVisualMapHandleDragForTest(
                componentIndex: componentIndex,
                handleIndex: handleIndex,
                deltaX: dx,
                deltaY: dy
            ) else {
                FileHandle.standardError.write(
                    Data("step \(stepIndex): visualMap handle was not available\n".utf8)
                )
                return false
            }
            record["resolvedPoint"] = point
            record["componentIndex"] = componentIndex
            record["handleIndex"] = handleIndex
            record["deltaX"] = dx
            record["deltaY"] = dy
        case "clickVisualMapPiece":
            let componentIndex = Int(step.componentIndex ?? 0)
            let pieceIndex = Int(step.pieceIndex ?? 0)
            guard let point = view._injectPiecewiseVisualMapClickForTest(
                componentIndex: componentIndex,
                pieceIndex: pieceIndex,
                movePointer: step.movePointer ?? true
            ) else {
                FileHandle.standardError.write(
                    Data("step \(stepIndex): piecewise visualMap item was not available\n".utf8)
                )
                return false
            }
            record["resolvedPoint"] = point
            record["componentIndex"] = componentIndex
            record["pieceIndex"] = pieceIndex
            if let dataName = step.dataName { record["dataName"] = dataName }
        case "dragBrush":
            let targetType = step.targetType ?? "grid"
            let componentIndex = Int(step.componentIndex ?? 0)
            let brushType = step.name ?? "rect"
            guard let points = view._injectBrushDragForTest(
                targetType: targetType,
                componentIndex: componentIndex,
                brushType: brushType
            ) else {
                FileHandle.standardError.write(
                    Data("step \(stepIndex): brush target was not available\n".utf8)
                )
                return false
            }
            record["resolvedPoints"] = points
            record["targetType"] = targetType
            record["componentIndex"] = componentIndex
            record["brushType"] = brushType
        case "dragDataZoom", "dragGraphic", "dragAxisPointer", "dragTimeline":
            let dx = step.deltaX ?? 48
            let dy = step.deltaY ?? 0
            if let point = dragInteractiveElement(
                kind: step.action == "dragDataZoom" ? "dataZoom"
                    : (step.action == "dragAxisPointer" ? "axisPointer"
                        : (step.action == "dragTimeline" ? "timeline" : "graphic")),
                deltaX: dx, deltaY: dy, deltaPercent: step.deltaPercent, view: view
            ) {
                record["resolvedPoint"] = point
            }
            else if step.allowMissing == true {
                record["missingTarget"] = true
            }
            else {
                FileHandle.standardError.write(
                    Data("step \(stepIndex): \(step.action) target was not hit-testable\n".utf8)
                )
                return false
            }
            record["deltaX"] = dx
            record["deltaY"] = dy
            if let deltaPercent = step.deltaPercent { record["deltaPercent"] = deltaPercent }
            if step.action == "dragDataZoom" {
                record["dataZoomRanges"] = view.ec.getModel()?
                    .findComponents(QueryConditionKindA(mainType: "dataZoom"))
                    .compactMap { ($0 as? DataZoomModel)?.getPercentRange() } ?? []
            }
        case "pointerMove":
            let x = step.x ?? 1
            let y = step.y ?? 1
            view._injectPointerForTest(type: "mousemove", zrX: x, zrY: y)
            record["resolvedPoint"] = [x, y]
        case "globalOut":
            view._injectGlobalOutForTest()
        case "driveTick":
            let count = chart.runIntervalTick()
            guard count > 0 else {
                FileHandle.standardError.write(
                    Data("step \(stepIndex): demo did not register an interval callback\n".utf8)
                )
                return false
            }
            record["intervalCallbacks"] = count
        case "driveAfterTick":
            let count = chart.runAfterTick()
            guard count > 0 else {
                FileHandle.standardError.write(
                    Data("step \(stepIndex): demo did not register a one-shot callback\n".utf8)
                )
                return false
            }
            record["afterCallbacks"] = count
        case "wait":
            let milliseconds = max(0, step.milliseconds ?? 0)
            RunLoop.current.run(until: Date(timeIntervalSinceNow: milliseconds / 1_000))
            record["milliseconds"] = milliseconds
        default:
            FileHandle.standardError.write(Data("step \(stepIndex): unknown action \(step.action)\n".utf8))
            return false
        }

        if let capture = step.capture {
            guard let image = renderInteractionView(
                view,
                size: CGSize(width: demo.width, height: demo.height),
                dpr: 2,
                backgroundColor: white
            ), let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                FileHandle.standardError.write(Data("step \(stepIndex): native capture failed\n".utf8))
                return false
            }
            let file = captureFileName(captureIndex, capture, side: "native")
            do { try png.write(to: directory.appendingPathComponent(file)) }
            catch {
                FileHandle.standardError.write(Data("step \(stepIndex): write failed: \(error)\n".utf8))
                return false
            }
            record["capture"] = capture
            record["file"] = file
            captureIndex += 1
            print("wrote \(file)")
        }
        records.append(record)
    }

    writeResolvedInteraction(
        scenario: scenario,
        side: "native",
        records: records,
        to: URL(fileURLWithPath: resolvedPath)
    )
    return true
}

private let webInteractionHarnessJS = #"""
(function () {
  var interceptedDownload = null;
  var interceptedDownloadCount = 0;
  var originalAnchorDispatchEvent = HTMLAnchorElement.prototype.dispatchEvent;
  HTMLAnchorElement.prototype.dispatchEvent = function (event) {
    if (event && event.type === 'click' && this.download
        && typeof this.href === 'string' && this.href.indexOf('data:image/') === 0) {
      interceptedDownloadCount++;
      interceptedDownload = { filename: this.download, href: this.href };
      return true;
    }
    return originalAnchorDispatchEvent.call(this, event);
  };
  function firstSeriesValues() {
    return myChart.getModel().getSeries().map(function (series) {
      var item = series.getRawData().getRawDataItem(0);
      if (item && typeof item === 'object' && !Array.isArray(item)) { return item.value; }
      return Array.isArray(item) ? item[0] : item;
    });
  }
  function incrementFirstDataValuePerBlock(content) {
    var separator = new Array(60).join('-');
    return content.split(separator).map(function (block) {
      var lines = block.split('\n');
      for (var i = 1; i < lines.length; i++) {
        var fields = lines[i].split('\t');
        var value = Number(fields[fields.length - 1]);
        if (!Number.isNaN(value) && fields[fields.length - 1].trim() !== '') {
          fields[fields.length - 1] = String(value + 1);
          lines[i] = fields.join('\t');
          break;
        }
      }
      return lines.join('\n');
    }).join(separator);
  }
  function children(el) {
    if (!el || !el.children) { return []; }
    var result = el.children();
    return Array.isArray(result) ? result : [];
  }
  function containsText(el, name) {
    if (!el) { return false; }
    if (el.type === 'text' && el.style && el.style.text === name) { return true; }
    var text = el.getTextContent && el.getTextContent();
    if (text && text.style && text.style.text === name) { return true; }
    var list = children(el);
    for (var i = 0; i < list.length; i++) {
      if (containsText(list[i], name)) { return true; }
    }
    return false;
  }
  function belongsTo(target, owner) {
    var current = target;
    while (current) {
      if (current === owner) { return true; }
      current = current.__hostTarget || current.parent;
    }
    return false;
  }
  function legendHit(name) {
    var zr = myChart.getZr();
    zr.refreshImmediately(true);
    zr.storage.getDisplayList(true);
    var views = myChart._componentsViews || [];
    for (var vi = 0; vi < views.length; vi++) {
      var content = views[vi].getContentGroup && views[vi].getContentGroup();
      var items = children(content);
      for (var ii = 0; ii < items.length; ii++) {
        if (!containsText(items[ii], name)) { continue; }
        var targets = children(items[ii]);
        var target = targets[targets.length - 1];
        if (!target || !target.getBoundingRect) { continue; }
        var rect = target.getBoundingRect();
        var point = target.transformCoordToGlobal(
          rect.x + rect.width / 2,
          rect.y + rect.height / 2
        );
        var hovered = zr.handler.findHover(point[0], point[1]);
        if (hovered && belongsTo(hovered.target, items[ii])) {
          return { point: point, hovered: hovered };
        }
      }
    }
    throw new Error('legend item was not hit-testable: ' + name);
  }
  function scrollLegendPageHit(name) {
    var zr = myChart.getZr();
    zr.refreshImmediately(true);
    zr.storage.getDisplayList(true);
    var views = myChart._componentsViews || [];
    var target = null;
    function visit(item) {
      if (!item || target) { return; }
      if (item.type === 'path' && item.name === name) { target = item; return; }
      var nested = children(item);
      for (var i = 0; i < nested.length; i++) { visit(nested[i]); }
    }
    for (var vi = 0; vi < views.length; vi++) {
      if (views[vi].type !== 'legend.scroll') { continue; }
      visit(views[vi].group);
      if (target) { break; }
    }
    if (!target || !target.getBoundingRect) {
      throw new Error('scroll legend page control was not available: ' + name);
    }
    var rect = target.getBoundingRect();
    var point = target.transformCoordToGlobal(
      rect.x + rect.width / 2, rect.y + rect.height / 2
    );
    var hovered = zr.handler.findHover(point[0], point[1]);
    if (!hovered || hovered.target !== target) {
      throw new Error('scroll legend page control was not hit-testable: ' + name);
    }
    return { point: point, hovered: hovered };
  }
  function visibleScrollLegendItemHit(visibleIndex) {
    var zr = myChart.getZr();
    zr.refreshImmediately(true);
    zr.storage.getDisplayList(true);
    var views = myChart._componentsViews || [];
    var visible = [];
    for (var vi = 0; vi < views.length; vi++) {
      if (views[vi].type !== 'legend.scroll') { continue; }
      var content = views[vi].getContentGroup && views[vi].getContentGroup();
      var items = children(content);
      for (var ii = 0; ii < items.length; ii++) {
        var targets = children(items[ii]);
        var target = targets[targets.length - 1];
        if (!target || !target.getBoundingRect) { continue; }
        var rect = target.getBoundingRect();
        var point = target.transformCoordToGlobal(
          rect.x + rect.width / 2, rect.y + rect.height / 2
        );
        var hovered = zr.handler.findHover(point[0], point[1]);
        if (hovered && belongsTo(hovered.target, items[ii])) {
          visible.push({ point: point, hovered: hovered });
        }
      }
    }
    if (!visible[visibleIndex]) {
      throw new Error('visible scroll legend item was not hit-testable: ' + visibleIndex);
    }
    return visible[visibleIndex];
  }
  function toolboxHit(name) {
    var zr = myChart.getZr();
    zr.refreshImmediately(true);
    zr.storage.getDisplayList(true);
    var views = myChart._componentsViews || [];
    var target = null;
    function visit(item) {
      if (!item || target) { return; }
      if (item.getBoundingRect && item.type !== 'rect') {
        var text = item.getTextContent && item.getTextContent();
        var title = text && text.style && text.style.text;
        if (typeof title === 'string' && title.toLowerCase() === name.toLowerCase()) {
          target = item;
          return;
        }
      }
      var nested = children(item);
      for (var ni = 0; ni < nested.length; ni++) { visit(nested[ni]); }
    }
    for (var vi = 0; vi < views.length; vi++) {
      if (views[vi].type !== 'toolbox') { continue; }
      visit(views[vi].group);
      if (target) { break; }
    }
    if (!target) {
      var toolboxModel = myChart.getModel().getComponent('toolbox', 0);
      var featureOpts = (toolboxModel && toolboxModel.get('feature')) || {};
      var iconNames = [];
      Object.keys(featureOpts).forEach(function (featureName) {
        var featureModel = toolboxModel.getModel(['feature', featureName]);
        if (featureModel.get('show') === false) { return; }
        var icons = featureModel.get('icon');
        if (typeof icons === 'string') { iconNames.push(featureName); return; }
        var names = Object.keys(icons || {});
        if (featureName === 'dataZoom') {
          names = ['zoom', 'back'].filter(function (n) { return icons && icons[n]; });
        }
        else if (featureName === 'magicType') {
          var types = featureModel.get('type') || [];
          names = types.filter(function (n) { return icons && icons[n]; });
        }
        else if (featureName === 'brush') {
          var brushTypes = featureModel.get('type') || [];
          names = brushTypes.filter(function (n) { return icons && icons[n]; });
        }
        Array.prototype.push.apply(iconNames, names);
      });
      var ordinal = iconNames.indexOf(name);
      if (ordinal >= 0) {
        var paths = [];
        function collectPaths(item) {
          if (!item) { return; }
          if (item.type === 'path' && item.getBoundingRect) { paths.push(item); }
          var nested = children(item);
          for (var pi = 0; pi < nested.length; pi++) { collectPaths(nested[pi]); }
        }
        for (var tvi = 0; tvi < views.length; tvi++) {
          if (views[tvi].type === 'toolbox') { collectPaths(views[tvi].group); break; }
        }
        target = paths[ordinal] || null;
      }
    }
    if (!target) { throw new Error('toolbox feature not found: ' + name); }
    var bounds = target.getBoundingRect();
    var point = target.transformCoordToGlobal(
      bounds.x + bounds.width / 2,
      bounds.y + bounds.height / 2
    );
    var hovered = zr.handler.findHover(point[0], point[1]);
    if (!hovered || !hovered.target) { throw new Error('toolbox feature was not hit-testable'); }
    return { point: point, hovered: hovered };
  }
  function raw(point) {
    return {
      zrX: point[0], zrY: point[1], offsetX: point[0], offsetY: point[1], which: 1,
      stop: function () {}, preventDefault: function () {}, stopPropagation: function () {}
    };
  }
  function dataHit(seriesIndex, dataIndex, dataName) {
    var zr = myChart.getZr();
    zr.refreshImmediately(true);
    zr.storage.getDisplayList(true);
    var series = myChart.getModel().getSeriesByIndex(seriesIndex);
    var data = series && series.getData();
    if (dataName) { dataIndex = data ? data.indexOfName(dataName) : -1; }
    if (dataIndex < 0) { throw new Error('data item not found by name: ' + dataName); }
    var el = data && data.getItemGraphicEl(dataIndex);
    if (!el) {
      var chartView = null;
      var chartViews = myChart._chartsViews || [];
      for (var cv = 0; cv < chartViews.length; cv++) {
        if (chartViews[cv].__model === series) { chartView = chartViews[cv]; break; }
      }
      var largePaths = [];
      function collectLarge(item) {
        if (!item) { return; }
        if (item.shape && (item.shape.points || item.shape.segs)
            && typeof item.hoverDataIdx === 'number') {
          largePaths.push(item);
        }
      }
      var chartGroup = chartView && chartView.group;
      collectLarge(chartGroup);
      if (chartGroup && chartGroup.traverse) { chartGroup.traverse(collectLarge); }
      for (var lp = 0; lp < largePaths.length; lp++) {
        var large = largePaths[lp];
        var isLargeLines = !!large.shape.segs;
        var largeStart = isLargeLines ? (large.__startIndex || 0) : (large.startIndex || 0);
        var localIndex = dataIndex - largeStart;
        if (localIndex < 0) { continue; }
        var largeLocalPoints = [];
        var points = large.shape.points;
        if (points) {
          if (localIndex * 2 + 1 >= points.length) { continue; }
          largeLocalPoints.push([points[localIndex * 2], points[localIndex * 2 + 1]]);
        }
        else {
          var segs = large.shape.segs;
          var fractions = [0.25, 0.5, 0.75];
          function addLinePoints(x0, y0, x1, y1) {
            for (var fi = 0; fi < fractions.length; fi++) {
              var t = fractions[fi];
              largeLocalPoints.push([x0 + (x1 - x0) * t, y0 + (y1 - y0) * t]);
            }
          }
          if (large.shape.polyline) {
            var item = 0;
            var cursor = 0;
            while (cursor < segs.length) {
              var pointCount = segs[cursor++];
              if (item === localIndex) {
                if (pointCount >= 2) {
                  var px0 = segs[cursor];
                  var py0 = segs[cursor + 1];
                  for (var pi = 1; pi < pointCount; pi++) {
                    var po = cursor + pi * 2;
                    addLinePoints(px0, py0, segs[po], segs[po + 1]);
                  }
                }
                break;
              }
              cursor += pointCount * 2;
              item++;
            }
          }
          else {
            var so = localIndex * 4;
            if (so + 3 < segs.length) {
              var sx0 = segs[so], sy0 = segs[so + 1];
              var sx1 = segs[so + 2], sy1 = segs[so + 3];
              var curveness = large.shape.curveness || 0;
              if (curveness > 0) {
                var cx = (sx0 + sx1) / 2 - (sy0 - sy1) * curveness;
                var cy = (sy0 + sy1) / 2 - (sx1 - sx0) * curveness;
                for (var qi = 0; qi < fractions.length; qi++) {
                  var qt = fractions[qi], qu = 1 - qt;
                  largeLocalPoints.push([
                    qu * qu * sx0 + 2 * qu * qt * cx + qt * qt * sx1,
                    qu * qu * sy0 + 2 * qu * qt * cy + qt * qt * sy1
                  ]);
                }
              }
              else { addLinePoints(sx0, sy0, sx1, sy1); }
            }
          }
        }
        for (var lpi = 0; lpi < largeLocalPoints.length; lpi++) {
          var localPoint = largeLocalPoints[lpi];
          var largePoint = large.transformCoordToGlobal(localPoint[0], localPoint[1]);
          var largeHovered = zr.handler.findHover(largePoint[0], largePoint[1]);
          if (largeHovered && largeHovered.target === large
              && large.hoverDataIdx + largeStart === dataIndex) {
            return { point: largePoint, hovered: largeHovered };
          }
        }
      }
      var itemPoint = data && data.getItemLayout && data.getItemLayout(dataIndex);
      if ((!itemPoint || itemPoint.length < 2) && data && data.getLayout) {
        var layoutPoints = data.getLayout('points');
        var layoutOffset = dataIndex * 2;
        if (layoutPoints && layoutOffset + 1 < layoutPoints.length) {
          itemPoint = [layoutPoints[layoutOffset], layoutPoints[layoutOffset + 1]];
        }
      }
      if (itemPoint && itemPoint.length >= 2
          && isFinite(itemPoint[0]) && isFinite(itemPoint[1])) {
        var progressivePoint = [itemPoint[0], itemPoint[1]];
        var progressiveHovered = zr.handler.findHover(progressivePoint[0], progressivePoint[1]);
        if (progressiveHovered && progressiveHovered.target
            && chartGroup && belongsTo(progressiveHovered.target, chartGroup)) {
          return { point: progressivePoint, hovered: progressiveHovered };
        }
      }
      throw new Error('data item not found: ' + seriesIndex + '/' + dataIndex);
    }
    if (!el.contain && el.traverse) {
      var childTarget = null;
      el.traverse(function (child) {
        if (!childTarget && child && child.contain
            && child.states && child.states.emphasis) { childTarget = child; }
      });
      if (childTarget) { el = childTarget; }
    }
    var point;
    var hovered;
    function accepts(candidate) {
      var candidateHovered = zr.handler.findHover(candidate[0], candidate[1]);
      if (candidateHovered && belongsTo(candidateHovered.target, el)) {
        hovered = candidateHovered;
        return true;
      }
      return false;
    }
    var shape = el.shape || {};
    if (shape.cx != null && shape.cy != null && shape.r != null
        && shape.startAngle != null && shape.endAngle != null) {
      var angle = (shape.startAngle + shape.endAngle) / 2;
      var radius = ((shape.r0 || 0) + shape.r) / 2;
      point = el.transformCoordToGlobal(shape.cx + Math.cos(angle) * radius,
                                        shape.cy + Math.sin(angle) * radius);
      if (!el.contain(point[0], point[1]) || !accepts(point)) { point = null; }
    }
    if (!point) {
      var bounds = el.getBoundingRect();
      for (var gy = 1; gy < 20 && !point; gy++) {
        for (var gx = 1; gx < 20; gx++) {
          var candidate = el.transformCoordToGlobal(
            bounds.x + bounds.width * gx / 20,
            bounds.y + bounds.height * gy / 20
          );
          if (el.contain(candidate[0], candidate[1]) && accepts(candidate)) {
            point = candidate;
            break;
          }
        }
      }
    }
    if (!point) { throw new Error('data item has no contained hit point'); }
    if (!hovered || !belongsTo(hovered.target, el)) {
      throw new Error('data item was not hit-testable');
    }
    return { point: point, hovered: hovered };
  }
  function seriesPoint(seriesIndex, dataIndex, dataName) {
    try { return dataHit(seriesIndex, dataIndex, dataName); }
    catch (_) {}
    var series = myChart.getModel().getSeriesByIndex(seriesIndex);
    var data = series && series.getData();
    if (dataName) { dataIndex = data ? data.indexOfName(dataName) : -1; }
    if (dataIndex < 0) { throw new Error('series point not found by name: ' + dataName); }
    var points = data && data.getLayout && data.getLayout('points');
    var offset = dataIndex * 2;
    if (!points || offset + 1 >= points.length
        || !isFinite(points[offset]) || !isFinite(points[offset + 1])) {
      throw new Error('line-series point was not resolvable: ' + seriesIndex + '/' + dataIndex);
    }
    return { point: [points[offset], points[offset + 1]], hovered: { target: null } };
  }
  function draggableHit(kind, preferWindow) {
    var zr = myChart.getZr();
    zr.refreshImmediately(true);
    var list = zr.storage.getDisplayList(true);
    var height = myChart.getHeight();
    var width = myChart.getWidth();
    var sliderViews = (myChart._componentsViews || []).filter(function (view) {
      return view.type === 'dataZoom.slider';
    });
    var sliderGroups = sliderViews.map(function (view) { return view.group; });
    if (kind === 'dataZoom') {
      var sliderView = sliderViews[0];
      var displayables = sliderView && sliderView._displayables;
      var target = null;
      if (displayables) {
        target = preferWindow
          ? (sliderView.dataZoomModel.get('brushSelect')
            ? displayables.moveZone : displayables.filler)
          : (displayables.handles && displayables.handles[0]);
      }
      // Pin both renderers to the same semantic target. Display-list order can put handle 1
      // before handle 0, producing different zoom windows even though both drags succeed.
      list = target ? [target] : [];
    }
    var hits = [];
    for (var i = 0; i < list.length; i++) {
      var el = list[i];
      if (!el || !el.draggable || !el.getBoundingRect || !el.contain) { continue; }
      var bounds = el.getBoundingRect();
      var found = null;
      for (var gy = 1; gy < 20; gy++) {
        for (var gx = 1; gx < 20; gx++) {
          var point = el.transformCoordToGlobal(
            bounds.x + bounds.width * gx / 20,
            bounds.y + bounds.height * gy / 20
          );
          var inRegion = kind === 'timeline'
            ? true
            : (kind === 'dataZoom'
            ? point[0] >= width * 0.08 && point[0] <= width * 0.92
              && sliderGroups.some(function (group) { return belongsTo(el, group); })
            : (kind === 'axisPointer'
              ? point[0] >= width * 0.08 && point[0] <= width * 0.92
                && point[1] >= height * 0.68 && point[1] < height * 0.92
              : point[0] >= width * 0.08 && point[0] <= width * 0.85 && point[1] < height * 0.68));
          if (!inRegion || !el.contain(point[0], point[1])) { continue; }
          var hovered = zr.handler.findHover(point[0], point[1]);
          if (hovered && hovered.target === el) { found = point; break; }
        }
        if (found) { break; }
      }
      if (found) {
        var left = el.transformCoordToGlobal(bounds.x, bounds.y);
        var right = el.transformCoordToGlobal(bounds.x + bounds.width, bounds.y);
        hits.push({ point: found, target: el, globalWidth: Math.abs(right[0] - left[0]) });
      }
    }
    if (kind === 'dataZoom' && hits.length) {
      hits.sort(function (a, b) {
        return preferWindow ? b.globalWidth - a.globalWidth : a.globalWidth - b.globalWidth;
      });
    }
    if (hits.length) { return hits[0]; }
    throw new Error(kind + ' draggable target was not hit-testable');
  }
  function roamingGeoHit() {
    var models = myChart.getModel().queryComponents({mainType: 'geo'});
    for (var i = 0; i < models.length; i++) {
      var roam = models[i].get('roam');
      var geo = models[i].coordinateSystem;
      if (!roam || !geo || !geo.getViewRect) { continue; }
      var rect = geo.getViewRect();
      return [rect.x + rect.width / 2, rect.y + rect.height / 2];
    }
    throw new Error('roaming geo was not available');
  }
  function geoRegionHit(name) {
    var models = myChart.getModel().queryComponents({mainType: 'geo'});
    for (var i = 0; i < models.length; i++) {
      var geo = models[i].coordinateSystem;
      var region = geo && geo.getRegion && geo.getRegion(name);
      var center = region && region.getCenter && region.getCenter();
      var point = center && geo.dataToPoint && geo.dataToPoint(center);
      if (!point || !isFinite(point[0]) || !isFinite(point[1])) { continue; }
      var hovered = myChart.getZr().handler.findHover(point[0], point[1]);
      if (hovered && hovered.target) { return { point: point, hovered: hovered }; }
    }
    throw new Error('geo region was not hit-testable: ' + name);
  }
  function brushTargetRect(targetType, componentIndex) {
    var model = myChart.getModel().getComponent(targetType, componentIndex);
    var coord = model && model.coordinateSystem;
    var rect = targetType === 'geo'
      ? (coord && coord.getViewRect && coord.getViewRect())
      : (coord && coord.getRect && coord.getRect());
    if (!rect || !(rect.width > 0) || !(rect.height > 0)) {
      throw new Error('brush target was not available: ' + targetType + '/' + componentIndex);
    }
    return rect;
  }
  function visualMapHandleHit(componentIndex, handleIndex) {
    var views = (myChart._componentsViews || []).filter(function (view) {
      return view.type === 'visualMap.continuous';
    });
    var view = views[componentIndex];
    var thumbs = view && view._shapes && view._shapes.handleThumbs;
    var target = thumbs && thumbs[handleIndex];
    if (!target || !target.transformCoordToGlobal) {
      throw new Error('visualMap handle was not available');
    }
    return { point: target.transformCoordToGlobal(0, 0), target: target };
  }
  function piecewiseVisualMapHit(componentIndex, pieceIndex, label) {
    var zr = myChart.getZr();
    zr.refreshImmediately(true);
    zr.storage.getDisplayList(true);
    var views = (myChart._componentsViews || []).filter(function (view) {
      return view.type === 'visualMap.piecewise';
    });
    var view = views[componentIndex];
    var items = children(view && view.group);
    var owner = null;
    if (label) {
      for (var i = 0; i < items.length; i++) {
        if (containsText(items[i], label)) { owner = items[i]; break; }
      }
    }
    if (!owner) {
      var itemGroups = items.filter(function (item) {
        return children(item).some(function (child) {
          return child && child.type === 'path' && child.getBoundingRect;
        });
      });
      owner = itemGroups[pieceIndex];
    }
    var targets = children(owner);
    for (var ti = 0; ti < targets.length; ti++) {
      var target = targets[ti];
      if (!target || target.type !== 'path' || !target.getBoundingRect) { continue; }
      var rect = target.getBoundingRect();
      var point = target.transformCoordToGlobal(
        rect.x + rect.width / 2, rect.y + rect.height / 2
      );
      var hovered = zr.handler.findHover(point[0], point[1]);
      if (hovered && belongsTo(hovered.target, owner)) {
        return { point: point, hovered: hovered };
      }
    }
    throw new Error('piecewise visualMap item was not available: ' + componentIndex + '/' + pieceIndex);
  }
  var pointerOutside = false;
  function hideTooltipHost() {
    myChart.dispatchAction({ type: 'hideTip' });
    var views = myChart._componentsViews || [];
    var found = 0;
    for (var vi = 0; vi < views.length; vi++) {
      if (views[vi]._tooltipContent) {
        found++;
        views[vi]._tooltipContent.hide();
        if (views[vi]._tooltipContent.el) {
          views[vi]._tooltipContent.el.style.display = 'none';
          views[vi]._tooltipContent.el.style.visibility = 'hidden';
          views[vi]._tooltipContent.el.style.opacity = '0';
        }
      }
    }
    return { tooltipViews: found };
  }
  function settleTooltipHost() {
    var views = myChart._componentsViews || [];
    var found = 0;
    for (var vi = 0; vi < views.length; vi++) {
      var content = views[vi]._tooltipContent;
      var el = content && content.el;
      if (!el || !el.style) { continue; }
      found++;
      // WKWebView can leave an HTML tooltip's CSS position transition suspended while the
      // offscreen oracle is being snapshotted. The inline left/top values already describe the
      // requested hover target, so remove only the host transition and force layout to capture
      // that final semantic state, matching the Native renderer's settled capture contract.
      el.style.transition = 'none';
      el.style.transitionProperty = 'none';
      el.style.transitionDuration = '0s';
      void el.offsetWidth;
    }
    return found;
  }
  function drainProgressive() {
    var frames = 0;
    var scheduler = myChart._scheduler;
    var zr = myChart.getZr();
    while (scheduler && scheduler.unfinished && frames < 10000) {
      if (myChart._onframe) { myChart._onframe(); }
      // A real animation frame flushes ZRender immediately after ECharts' `_onframe` callback.
      // `_onframe` only flushes itself on the FINAL progressive batch; calling it directly without
      // this intermediate flush drops every earlier incremental canvas batch from the visual oracle.
      // That made dense progressive lines (official-lines-ny) look much dimmer on Web than they do
      // after the same scheduler has actually finished in a browser.
      if (scheduler.unfinished) { zr.flush(); }
      frames++;
    }
    if (scheduler && scheduler.unfinished) {
      throw new Error('progressive rendering did not settle after ' + frames + ' frames');
    }
    return frames;
  }
  function finishAnimations() {
    var zr = myChart.getZr();
    zr.animation.stop();
    var progressiveFrames = drainProgressive();
    var seenElements = new Set();
    var seenClips = new Set();
    var clips = [];
    function collect(el) {
      if (!el || seenElements.has(el)) { return; }
      seenElements.add(el);
      var animators = el.animators || [];
      for (var ai = 0; ai < animators.length; ai++) {
        var clip = animators[ai].getClip && animators[ai].getClip();
        if (clip && !seenClips.has(clip)) { seenClips.add(clip); clips.push(clip); }
      }
      if (el.getTextContent) { collect(el.getTextContent()); }
      if (el.getTextGuideLine) { collect(el.getTextGuideLine()); }
      var list = children(el);
      for (var ci = 0; ci < list.length; ci++) { collect(list[ci]); }
    }
    var roots = zr.storage.getRoots();
    for (var ri = 0; ri < roots.length; ri++) { collect(roots[ri]); }
    for (var i = 0; i < clips.length; i++) {
      var clip = clips[i];
      clip._inited = false;
      clip._startTime = 0;
      clip._pausedTime = 0;
      clip._paused = false;
      var elapsed = 1000000000 - (clip._delay || 0);
      var life = clip._life || 1;
      var percent = clip.loop && elapsed >= 0
        ? (elapsed % life) / life
        : Math.max(0, Math.min(elapsed / life, 1));
      clip.onframe(clip.easingFunc ? clip.easingFunc(percent) : percent);
      if (!clip.loop && elapsed >= life) { clip.ondestroy(); }
    }
    progressiveFrames += drainProgressive();
    if (pointerOutside) { hideTooltipHost(); }
    var tooltipViews = settleTooltipHost();
    zr.animation.stop();
    zr.refreshImmediately(true);
    var settledList = zr.storage.getDisplayList(true);
    var largeLinePathCount = 0;
    var largeLineSegmentValueCount = 0;
    for (var si = 0; si < settledList.length; si++) {
      var settledShape = settledList[si] && settledList[si].shape;
      if (settledShape && settledShape.segs) {
        largeLinePathCount++;
        largeLineSegmentValueCount += settledShape.segs.length;
      }
    }
    return {
      clips: clips.length,
      progressiveFrames: progressiveFrames,
      tooltipViews: tooltipViews,
      seriesDataCounts: myChart.getModel().getSeries().map(function (series) {
        return series.getData().count();
      }),
      largeLines: {
        pathCount: largeLinePathCount,
        segmentValueCount: largeLineSegmentValueCount
      }
    };
  }
  window.__interactionVisual = {
    settle: finishAnimations,
    clickLegend: function (name, movePointer) {
      pointerOutside = false;
      var hit = legendHit(name);
      var handler = myChart.getZr().handler;
      var event = raw(hit.point);
      if (movePointer) { handler.mousemove(event); }
      handler.mousedown(event);
      handler.mouseup(event);
      handler.click(event);
      if (myChart._onframe) { myChart._onframe(); }
      myChart.getZr().animation.stop();
      return { x: hit.point[0], y: hit.point[1], targetType: hit.hovered.target.type || '' };
    },
    clickLegendPage: function (name, movePointer) {
      pointerOutside = false;
      var hit = scrollLegendPageHit(name);
      var handler = myChart.getZr().handler;
      var event = raw(hit.point);
      if (movePointer) { handler.mousemove(event); }
      handler.mousedown(event);
      handler.mouseup(event);
      handler.click(event);
      if (myChart._onframe) { myChart._onframe(); }
      myChart.getZr().animation.stop();
      return { x: hit.point[0], y: hit.point[1], targetType: hit.hovered.target.type || '' };
    },
    clickVisibleLegendItem: function (visibleIndex, movePointer) {
      pointerOutside = false;
      var hit = visibleScrollLegendItemHit(visibleIndex);
      var handler = myChart.getZr().handler;
      var event = raw(hit.point);
      if (movePointer) { handler.mousemove(event); }
      handler.mousedown(event);
      handler.mouseup(event);
      handler.click(event);
      if (myChart._onframe) { myChart._onframe(); }
      myChart.getZr().animation.stop();
      return { x: hit.point[0], y: hit.point[1], targetType: hit.hovered.target.type || '' };
    },
    hoverData: function (seriesIndex, dataIndex, dataName) {
      pointerOutside = false;
      var hit = dataHit(seriesIndex, dataIndex, dataName);
      myChart.getZr().handler.mousemove(raw(hit.point));
      if (myChart._onframe) { myChart._onframe(); }
      myChart.getZr().animation.stop();
      return { x: hit.point[0], y: hit.point[1], targetType: hit.hovered.target.type || '' };
    },
    hoverSeries: function (seriesIndex, dataIndex, dataName) {
      pointerOutside = false;
      var hit = seriesPoint(seriesIndex, dataIndex, dataName);
      myChart.getZr().handler.mousemove(raw(hit.point));
      if (myChart._onframe) { myChart._onframe(); }
      myChart.getZr().animation.stop();
      return {
        x: hit.point[0], y: hit.point[1],
        targetType: hit.hovered.target ? (hit.hovered.target.type || '') : ''
      };
    },
    clickData: function (seriesIndex, dataIndex, dataName, movePointer) {
      pointerOutside = false;
      var hit = dataHit(seriesIndex, dataIndex, dataName);
      var handler = myChart.getZr().handler;
      var event = raw(hit.point);
      if (movePointer) { handler.mousemove(event); }
      handler.mousedown(event);
      handler.mouseup(event);
      handler.click(event);
      if (myChart._onframe) { myChart._onframe(); }
      myChart.getZr().animation.stop();
      return { x: hit.point[0], y: hit.point[1], targetType: hit.hovered.target.type || '' };
    },
    clickToolbox: function (name, movePointer) {
      pointerOutside = false;
      var hit = toolboxHit(name);
      var handler = myChart.getZr().handler;
      var event = raw(hit.point);
      if (movePointer) { handler.mousemove(event); }
      handler.mousedown(event);
      handler.mouseup(event);
      handler.click(event);
      if (myChart._onframe) { myChart._onframe(); }
      myChart.getZr().animation.stop();
      var result = { x: hit.point[0], y: hit.point[1], targetType: hit.hovered.target.type || '' };
      if (name === 'restore') {
        result.hostOutput = {
          feature: 'restore', emitted: true, seriesFirstValues: firstSeriesValues()
        };
      }
      return result;
    },
    editDataView: function () {
      var callbackCountBefore = document.querySelectorAll('#main textarea').length;
      var valuesBefore = firstSeriesValues();
      var hit = window.__interactionVisual.clickToolbox('dataView', true);
      var textarea = document.querySelector('#main textarea');
      if (!textarea || textarea.readOnly) { throw new Error('dataView editable textarea was not presented'); }
      var original = textarea.value;
      var edited = incrementFirstDataValuePerBlock(original);
      if (edited === original) { throw new Error('dataView did not expose editable numeric rows'); }
      textarea.value = edited;
      textarea.dispatchEvent(new Event('input', { bubbles: true }));
      var buttonContainer = textarea.parentElement && textarea.parentElement.nextElementSibling;
      var refresh = buttonContainer && buttonContainer.children[0];
      if (!refresh) { throw new Error('dataView refresh button was not presented'); }
      refresh.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
      if (document.querySelector('#main textarea')) { throw new Error('dataView refresh did not close the editor'); }
      return {
        x: hit.x, y: hit.y,
        hostOutput: {
          feature: 'dataView', emitted: true,
          invocationCount: callbackCountBefore === 0 ? 1 : 0,
          title: 'Data View', readOnly: false,
          contentLength: original.length,
          blockCount: original.split(new Array(60).join('-')).length,
          seriesNames: myChart.getModel().getSeries().map(function (series) { return series.name; }),
          valuesBefore: valuesBefore, valuesAfter: firstSeriesValues(), refreshed: true
        }
      };
    },
    saveToolboxImage: function () {
      interceptedDownload = null;
      var countBefore = interceptedDownloadCount;
      var hit = window.__interactionVisual.clickToolbox('saveAsImage', true);
      if (!interceptedDownload) { throw new Error('saveAsImage did not dispatch a download anchor click'); }
      var comma = interceptedDownload.href.indexOf(',');
      var payload = comma >= 0 ? interceptedDownload.href.slice(comma + 1) : '';
      var bytes = atob(payload);
      var signature = '';
      for (var i = 0; i < Math.min(4, bytes.length); i++) {
        signature += ('0' + bytes.charCodeAt(i).toString(16)).slice(-2);
      }
      if (signature !== '89504e47') { throw new Error('saveAsImage emitted a non-PNG payload'); }
      var featureModel = myChart.getModel().getComponent('toolbox')
        .getModel(['feature', 'saveAsImage']);
      var ratio = Number(featureModel.get('pixelRatio')) || 1;
      return {
        x: hit.x, y: hit.y,
        hostOutput: {
          feature: 'saveAsImage', emitted: true,
          callbackCount: interceptedDownloadCount - countBefore,
          filename: interceptedDownload.filename,
          mimeType: 'image/png', byteCount: bytes.length,
          signatureHex: signature,
          pixelWidth: myChart.getWidth() * ratio,
          pixelHeight: myChart.getHeight() * ratio,
          excludeComponents: ['toolbox']
        }
      };
    },
    drag: function (kind, deltaX, deltaY, deltaPercent) {
      pointerOutside = false;
      var hit = draggableHit(kind, typeof deltaPercent === 'number');
      var handler = myChart.getZr().handler;
      var start = hit.point;
      var dx = deltaX;
      var dy = deltaY;
      if (kind === 'dataZoom' && typeof deltaPercent === 'number') {
        var zoomModels = myChart.getModel().queryComponents({mainType: 'dataZoom'});
        var range = zoomModels.length ? zoomModels[0].getPercentRange() : null;
        var bounds = hit.target.getBoundingRect();
        var left = hit.target.transformCoordToGlobal(bounds.x, bounds.y);
        var right = hit.target.transformCoordToGlobal(bounds.x + bounds.width, bounds.y);
        var rangeSpan = range ? Math.abs(range[1] - range[0]) : 0;
        if (rangeSpan > 0) { dx = Math.abs(right[0] - left[0]) * Math.abs(deltaPercent) / rangeSpan; }
      }
      if (kind === 'dataZoom' && dx !== 0 && start[0] > myChart.getWidth() * 0.72) {
        dx = -Math.abs(dx);
      }
      if (start[0] + dx < 2 || start[0] + dx > myChart.getWidth() - 2) { dx = -dx; }
      if (start[1] + dy < 2 || start[1] + dy > myChart.getHeight() - 2) { dy = -dy; }
      handler.mousemove(raw(start));
      handler.mousedown(raw(start));
      // A realtime dataZoom rebuild can replace the handle after the first move. Send the full
      // displacement once so Native and Web consume the same complete drag.
      var fractions = kind === 'dataZoom' ? [1] : [0.25, 0.5, 0.75, 1];
      fractions.forEach(function (fraction) {
        handler.mousemove(raw([start[0] + dx * fraction, start[1] + dy * fraction]));
      });
      if (kind !== 'axisPointer') {
        handler.mouseup(raw([start[0] + dx, start[1] + dy]));
      }
      if (myChart._onframe) { myChart._onframe(); }
      myChart.getZr().animation.stop();
      var ranges = [];
      if (kind === 'dataZoom') {
        ranges = myChart.getModel().queryComponents({mainType: 'dataZoom'}).map(function (model) {
          return model.getPercentRange();
        });
      }
      return { x: start[0], y: start[1], deltaX: dx, deltaY: dy, dataZoomRanges: ranges };
    },
    pointerMove: function (x, y) {
      pointerOutside = false;
      myChart.getZr().handler.mousemove(raw([x, y]));
      if (myChart._onframe) { myChart._onframe(); }
      myChart.getZr().animation.stop();
      return { x: x, y: y };
    },
    driveTick: function () {
      pointerOutside = false;
      var callbacks = (window.__capturedIntervals || []).slice();
      for (var i = 0; i < callbacks.length; i++) { callbacks[i](); }
      if (myChart._onframe) { myChart._onframe(); }
      myChart.getZr().animation.stop();
      return { intervalCallbacks: callbacks.length };
    },
    driveAfterTick: function () {
      pointerOutside = false;
      var queue = window.__capturedDemoAfters || [];
      var callback = queue.shift();
      if (!callback) { throw new Error('demo did not register a one-shot callback'); }
      callback();
      if (myChart._onframe) { myChart._onframe(); }
      myChart.getZr().animation.stop();
      return { afterCallbacks: 1, pendingAfterCallbacks: queue.length };
    },
    dragGeoRoam: function (deltaX, deltaY) {
      pointerOutside = false;
      var start = roamingGeoHit();
      var handler = myChart.getZr().handler;
      handler.mousemove(raw(start));
      handler.mousedown(raw(start));
      [0.25, 0.5, 0.75, 1].forEach(function (fraction) {
        handler.mousemove(raw([
          start[0] + deltaX * fraction,
          start[1] + deltaY * fraction
        ]));
      });
      handler.mouseup(raw([start[0] + deltaX, start[1] + deltaY]));
      if (myChart._onframe) { myChart._onframe(); }
      myChart.getZr().animation.stop();
      return { x: start[0], y: start[1], deltaX: deltaX, deltaY: deltaY };
    },
    wheelGeoRoam: function (delta) {
      pointerOutside = false;
      var point = roamingGeoHit();
      var event = raw(point);
      event.zrDelta = delta;
      event.wheelDelta = delta;
      myChart.getZr().handler.mousewheel(event);
      if (myChart._onframe) { myChart._onframe(); }
      myChart.getZr().animation.stop();
      return { x: point[0], y: point[1], delta: delta };
    },
    hoverGeoRegion: function (name) {
      pointerOutside = false;
      var hit = geoRegionHit(name);
      myChart.getZr().handler.mousemove(raw(hit.point));
      if (myChart._onframe) { myChart._onframe(); }
      myChart.getZr().animation.stop();
      return { x: hit.point[0], y: hit.point[1], name: name };
    },
    dragVisualMap: function (componentIndex, handleIndex, deltaX, deltaY) {
      pointerOutside = false;
      var hit = visualMapHandleHit(componentIndex, handleIndex);
      var start = hit.point;
      var handler = myChart.getZr().handler;
      handler.mousemove(raw(start));
      handler.mousedown(raw(start));
      [0.25, 0.5, 0.75, 1].forEach(function (fraction) {
        handler.mousemove(raw([
          start[0] + deltaX * fraction,
          start[1] + deltaY * fraction
        ]));
      });
      handler.mouseup(raw([start[0] + deltaX, start[1] + deltaY]));
      if (myChart._onframe) { myChart._onframe(); }
      myChart.getZr().animation.stop();
      return { x: start[0], y: start[1], deltaX: deltaX, deltaY: deltaY };
    },
    clickVisualMapPiece: function (componentIndex, pieceIndex, label, movePointer) {
      pointerOutside = false;
      var hit = piecewiseVisualMapHit(componentIndex, pieceIndex, label);
      var handler = myChart.getZr().handler;
      var event = raw(hit.point);
      if (movePointer) { handler.mousemove(event); }
      handler.mousedown(event);
      handler.mouseup(event);
      handler.click(event);
      if (myChart._onframe) { myChart._onframe(); }
      myChart.getZr().animation.stop();
      return { x: hit.point[0], y: hit.point[1], targetType: hit.hovered.target.type || '' };
    },
    dragBrush: function (targetType, componentIndex, brushType) {
      pointerOutside = false;
      var rect = brushTargetRect(targetType, componentIndex);
      var start = [rect.x + rect.width * 0.18, rect.y + rect.height * 0.2];
      var end = [rect.x + rect.width * 0.55, rect.y + rect.height * 0.72];
      var points = brushType === 'polygon'
        ? [[end[0], start[1]], end, [start[0], end[1]], start]
        : [0.25, 0.5, 0.75, 1].map(function (fraction) {
            return [
              start[0] + (end[0] - start[0]) * fraction,
              start[1] + (end[1] - start[1]) * fraction
            ];
          });
      var handler = myChart.getZr().handler;
      handler.mousemove(raw(start));
      handler.mousedown(raw(start));
      for (var i = 0; i < points.length; i++) { handler.mousemove(raw(points[i])); }
      handler.mouseup(raw(end));
      if (myChart._onframe) { myChart._onframe(); }
      myChart.getZr().animation.stop();
      return { start: start, end: end, targetType: targetType, brushType: brushType };
    },
    globalOut: function () {
      pointerOutside = true;
      var chartDom = myChart.getDom();
      var viewport = chartDom.querySelector('canvas') || chartDom;
      viewport.dispatchEvent(new MouseEvent('mouseout', {
        bubbles: true, cancelable: true, relatedTarget: document.body,
        clientX: -1, clientY: -1
      }));
      myChart.getZr().handler.mouseout({ zrEventControl: 'only_globalout' });
      if (myChart._onframe) { myChart._onframe(); }
      // Calling Handler directly bypasses the browser proxy's DOM mouseout leg. In a real canvas
      // exit that leg retires rich/HTML tooltip content; normalize the Web oracle to that host-level
      // result after still exercising zrender's real globalout path above.
      var cleanup = hideTooltipHost();
      myChart.getZr().animation.stop();
      return cleanup;
    }
  };
  myChart.getZr().animation.stop();
  return true;
})()
"""#

final class WebInteractionVisualRunner: NSObject, WKNavigationDelegate {
    private let scenario: InteractionVisualScenario
    private let directory: URL
    private let resolvedURL: URL
    private let webView: WKWebView
    private var stepIndex = 0
    private var captureIndex = 0
    private var records: [[String: Any]] = []

    init(
        scenario: InteractionVisualScenario,
        directory: URL,
        resolvedURL: URL,
        webView: WKWebView
    ) {
        self.scenario = scenario
        self.directory = directory
        self.resolvedURL = resolvedURL
        self.webView = webView
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            webView.evaluateJavaScript(webInteractionHarnessJS) { _, error in
                if let error { self.fail("could not install web interaction harness: \(error)") }
                else { self.runNextStep() }
            }
        }
    }

    private func runNextStep() {
        guard stepIndex < scenario.steps.count else {
            writeResolvedInteraction(
                scenario: scenario, side: "web", records: records, to: resolvedURL
            )
            exit(0)
        }
        let currentIndex = stepIndex
        let step = scenario.steps[currentIndex]
        stepIndex += 1
        if step.action == "wait" {
            let milliseconds = max(0, step.milliseconds ?? 0)
            DispatchQueue.main.asyncAfter(deadline: .now() + milliseconds / 1_000) {
                self.records.append([
                    "step": currentIndex, "action": step.action, "milliseconds": milliseconds
                ])
                self.runNextStep()
            }
            return
        }
        let payload: [String: Any] = [
            "name": step.name ?? "",
            "movePointer": step.movePointer ?? true,
            "x": step.x ?? 1,
            "y": step.y ?? 1,
            "seriesIndex": step.seriesIndex ?? 0,
            "dataIndex": step.dataIndex ?? 0,
            "dataName": step.dataName ?? "",
            "milliseconds": step.milliseconds ?? 0,
            "deltaX": step.deltaX ?? 48,
            "deltaY": step.deltaY ?? 0,
            "deltaPercent": step.deltaPercent ?? NSNull(),
            "componentIndex": step.componentIndex ?? 0,
            "handleIndex": step.handleIndex ?? 1,
            "pieceIndex": step.pieceIndex ?? 0,
            "targetType": step.targetType ?? "grid",
        ]
        let data = try! JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        let json = String(data: data, encoding: .utf8)!
        let script: String
        switch step.action {
        case "settle": script = "window.__interactionVisual.settle()"
        case "clickLegend":
            script = "(function(a){return window.__interactionVisual.clickLegend(a.name,a.movePointer);})(\(json))"
        case "clickLegendPage":
            script = "(function(a){return window.__interactionVisual.clickLegendPage(a.name,a.movePointer);})(\(json))"
        case "clickVisibleLegendItem":
            script = "(function(a){return window.__interactionVisual.clickVisibleLegendItem(a.dataIndex,a.movePointer);})(\(json))"
        case "hoverData":
            script = "(function(a){return window.__interactionVisual.hoverData(a.seriesIndex,a.dataIndex,a.dataName);})(\(json))"
        case "hoverSeries":
            script = "(function(a){return window.__interactionVisual.hoverSeries(a.seriesIndex,a.dataIndex,a.dataName);})(\(json))"
        case "clickData":
            script = "(function(a){return window.__interactionVisual.clickData(a.seriesIndex,a.dataIndex,a.dataName,a.movePointer);})(\(json))"
        case "clickToolbox":
            script = "(function(a){return window.__interactionVisual.clickToolbox(a.name,a.movePointer);})(\(json))"
        case "editDataView":
            script = "window.__interactionVisual.editDataView()"
        case "saveToolboxImage":
            script = "window.__interactionVisual.saveToolboxImage()"
        case "dragDataZoom":
            script = "(function(a){return window.__interactionVisual.drag('dataZoom',a.deltaX,a.deltaY,a.deltaPercent);})(\(json))"
        case "dragGraphic":
            script = "(function(a){return window.__interactionVisual.drag('graphic',a.deltaX,a.deltaY,a.deltaPercent);})(\(json))"
        case "dragAxisPointer":
            script = "(function(a){return window.__interactionVisual.drag('axisPointer',a.deltaX,a.deltaY,a.deltaPercent);})(\(json))"
        case "dragTimeline":
            script = "(function(a){return window.__interactionVisual.drag('timeline',a.deltaX,a.deltaY,a.deltaPercent);})(\(json))"
        case "pointerMove":
            script = "(function(a){return window.__interactionVisual.pointerMove(a.x,a.y);})(\(json))"
        case "driveTick": script = "window.__interactionVisual.driveTick()"
        case "driveAfterTick": script = "window.__interactionVisual.driveAfterTick()"
        case "dragGeoRoam":
            script = "(function(a){return window.__interactionVisual.dragGeoRoam(a.deltaX,a.deltaY);})(\(json))"
        case "wheelGeoRoam":
            script = "(function(a){return window.__interactionVisual.wheelGeoRoam(a.deltaY);})(\(json))"
        case "hoverGeoRegion":
            script = "(function(a){return window.__interactionVisual.hoverGeoRegion(a.name);})(\(json))"
        case "dragVisualMap":
            script = "(function(a){return window.__interactionVisual.dragVisualMap(a.componentIndex,a.handleIndex,a.deltaX,a.deltaY);})(\(json))"
        case "clickVisualMapPiece":
            script = "(function(a){return window.__interactionVisual.clickVisualMapPiece(a.componentIndex,a.pieceIndex,a.dataName,a.movePointer);})(\(json))"
        case "dragBrush":
            script = "(function(a){return window.__interactionVisual.dragBrush(a.targetType,a.componentIndex,a.name);})(\(json))"
        case "globalOut": script = "window.__interactionVisual.globalOut()"
        default:
            fail("step \(currentIndex): unknown action \(step.action)")
            return
        }

        webView.evaluateJavaScript(script) { result, error in
            if let error {
                self.fail("step \(currentIndex) failed: \(error)")
                return
            }
            var record: [String: Any] = ["step": currentIndex, "action": step.action]
            if let result { record["result"] = result }
            if let capture = step.capture {
                let file = captureFileName(self.captureIndex, capture, side: "web")
                let config = WKSnapshotConfiguration()
                config.rect = self.webView.bounds
                self.webView.takeSnapshot(with: config) { image, snapshotError in
                    guard let image,
                          let tiff = image.tiffRepresentation,
                          let rep = NSBitmapImageRep(data: tiff),
                          let png = rep.representation(using: .png, properties: [:]) else {
                        self.fail("step \(currentIndex) snapshot failed: \(String(describing: snapshotError))")
                        return
                    }
                    do { try png.write(to: self.directory.appendingPathComponent(file)) }
                    catch { self.fail("step \(currentIndex) write failed: \(error)"); return }
                    record["capture"] = capture
                    record["file"] = file
                    self.records.append(record)
                    self.captureIndex += 1
                    print("wrote \(file)")
                    self.runNextStep()
                }
            } else {
                self.records.append(record)
                self.runNextStep()
            }
        }
    }

    private func fail(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fail("web load failed: \(error)")
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        fail("web provisional load failed: \(error)")
    }
}

@MainActor
func startWebInteractionVisual(
    scenarioPath: String,
    outputDirectory: String,
    resolvedPath: String
) -> Bool {
    let scenario: InteractionVisualScenario
    do { scenario = try loadInteractionScenario(scenarioPath) }
    catch {
        FileHandle.standardError.write(Data("invalid interaction scenario: \(error)\n".utf8))
        return false
    }
    guard let demo = EChartsDemoRegistry.byName(scenario.demo) else {
        FileHandle.standardError.write(Data("unknown demo: \(scenario.demo)\n".utf8))
        return false
    }
    let directory = URL(fileURLWithPath: outputDirectory, isDirectory: true)
    do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
    catch {
        FileHandle.standardError.write(Data("could not create output directory: \(error)\n".utf8))
        return false
    }
    // Interaction screenshots compare settled semantic states. Disable ordinary series entrance/
    // update animation on the Web oracle just like --compare; emphasis state transitions are still
    // driven explicitly by the scenario's `settle` steps.
    guard let page = echartsHTMLPage(demo, snapshot: true, captureIntervals: true) else {
        FileHandle.standardError.write(Data("could not build web page\n".utf8))
        return false
    }

    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: demo.width, height: demo.height))
    let window = NSWindow(
        contentRect: webView.frame, styleMask: [.borderless], backing: .buffered, defer: false
    )
    window.contentView = webView
    window.orderFrontRegardless()
    let runner = WebInteractionVisualRunner(
        scenario: scenario,
        directory: directory,
        resolvedURL: URL(fileURLWithPath: resolvedPath),
        webView: webView
    )
    webView.navigationDelegate = runner
    webView.loadHTMLString(page, baseURL: nil)
    app.run()
    return true
}

@MainActor
func writeInteractionVisualContact(scenarioPath: String, caseRootPath: String) -> Bool {
    let scenario: InteractionVisualScenario
    do { scenario = try loadInteractionScenario(scenarioPath) }
    catch {
        FileHandle.standardError.write(Data("invalid interaction scenario: \(error)\n".utf8))
        return false
    }
    let captures = scenario.steps.compactMap(\.capture)
    guard !captures.isEmpty else {
        FileHandle.standardError.write(Data("interaction scenario has no named captures\n".utf8))
        return false
    }

    let caseRoot = URL(fileURLWithPath: caseRootPath, isDirectory: true)
    let thumbWidth = 640.0
    let labelWidth = 190.0
    let headerHeight = 32.0
    let gap = 4.0
    var rows: [(String, NSImage, NSImage, Double)] = []
    for (index, capture) in captures.enumerated() {
        let nativeURL = caseRoot.appendingPathComponent("frames/native")
            .appendingPathComponent(captureFileName(index, capture, side: "native"))
        let webURL = caseRoot.appendingPathComponent("frames/web")
            .appendingPathComponent(captureFileName(index, capture, side: "web"))
        guard let native = NSImage(contentsOf: nativeURL), let web = NSImage(contentsOf: webURL),
              native.size.width > 0, web.size.width > 0 else {
            FileHandle.standardError.write(Data("missing capture pair for \(capture)\n".utf8))
            return false
        }
        let nativeHeight = native.size.height * thumbWidth / native.size.width
        let webHeight = web.size.height * thumbWidth / web.size.width
        rows.append((capture, native, web, max(nativeHeight, webHeight)))
    }

    let width = labelWidth + thumbWidth * 2 + gap
    let height = headerHeight + rows.reduce(0) { $0 + $1.3 } + gap * Double(max(0, rows.count - 1))
    let canvas = NSImage(size: NSSize(width: width, height: height))
    canvas.lockFocus()
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    let titleAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
        .foregroundColor: NSColor.black,
    ]
    let labelAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
        .foregroundColor: NSColor.black,
    ]
    (scenario.id as NSString).draw(at: NSPoint(x: 8, y: height - 22), withAttributes: titleAttributes)
    ("Native" as NSString).draw(
        at: NSPoint(x: labelWidth + 8, y: height - 22), withAttributes: titleAttributes
    )
    ("Web reference" as NSString).draw(
        at: NSPoint(x: labelWidth + thumbWidth + gap + 8, y: height - 22),
        withAttributes: titleAttributes
    )

    var top = height - headerHeight
    for (index, row) in rows.enumerated() {
        let y = top - row.3
        (String(format: "%02d\n%@", index, row.0) as NSString).draw(
            in: NSRect(x: 8, y: y + row.3 - 48, width: labelWidth - 16, height: 44),
            withAttributes: labelAttributes
        )
        let nativeHeight = row.1.size.height * thumbWidth / row.1.size.width
        row.1.draw(
            in: NSRect(x: labelWidth, y: y + row.3 - nativeHeight, width: thumbWidth, height: nativeHeight),
            from: .zero, operation: .sourceOver, fraction: 1
        )
        let webHeight = row.2.size.height * thumbWidth / row.2.size.width
        row.2.draw(
            in: NSRect(
                x: labelWidth + thumbWidth + gap, y: y + row.3 - webHeight,
                width: thumbWidth, height: webHeight
            ),
            from: .zero, operation: .sourceOver, fraction: 1
        )
        top = y - gap
    }
    canvas.unlockFocus()

    let contactURL = caseRoot.appendingPathComponent("contact.png")
    guard let tiff = canvas.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("could not encode interaction contact sheet\n".utf8))
        return false
    }
    do { try png.write(to: contactURL); print(contactURL.path); return true }
    catch {
        FileHandle.standardError.write(Data("could not write interaction contact sheet: \(error)\n".utf8))
        return false
    }
}

#endif
