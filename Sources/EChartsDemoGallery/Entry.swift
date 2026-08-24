// Entry.swift — EChartsDemoGallery entry point.
//
// The ECharts analog of DemoGallery/Entry.swift. Renders each demo option two ways side-by-side:
//   swift run EChartsDemoGallery                       GUI: sidebar + native | echarts.js panes
//   swift run EChartsDemoGallery --list                print demo names, exit
//   swift run EChartsDemoGallery --render <name> <png> headless native render (EChartsKit) → PNG
//   swift run EChartsDemoGallery --render-all <dir>    native-render every demo to <dir>/<name>.png
//   swift run EChartsDemoGallery --web-snapshot <name> <png>   headless echarts.js render → PNG
//   swift run EChartsDemoGallery --compare <name> <dir>        BOTH panes → <dir>/<name>.{native,web}.png
//   swift run EChartsDemoGallery --render-rasterizer <name> <png> [timeMs]  Metal snapshot

#if canImport(AppKit)

import AppKit
import WebKit
import CoreGraphics
import ZRenderKit
import EChartsKit
import NativePainter
import EChartsDemoCore
import RasterizerPainter

// NOTE: the demo definitions (`EChartsDemo`, `EChartsDemoRegistry`, `Demos/*.swift`), the `Upstream`
// dist locator and the `echartsHTMLPage(_:)` web-pane builder all live in EChartsDemoCore, shared
// with the iOS gallery (EChartsDemoGalleryiOS).

// ---------------------------------------------------------------------------
// NATIVE render: EChartsKit → ECharts → ZRenderKit Group → NativePainter → CGImage.
// ---------------------------------------------------------------------------

/// The headless render never ticks the animation loop, so looping effects (e.g. effectScatter
/// ripples) would freeze at their t=0 initial state (all rings overlapping at scaleX 0.5) — a
/// single opaque disc. Advance every animation clip to a fixed representative time so the static
/// frame shows the same staggered ripple echarts paints on the first frame (per-ring negative
/// delays realize the stagger). Generic: currently only effectScatter creates animators.
private func advanceAnimationsForStaticFrame(_ root: Group, _ timeMs: Double = 1000) {
    func advance(_ el: Element) {
        for animator in el.animators {
            if let clip = animator.getClip() {
                // WKWebView waits 400 ms after the page is ready before taking its deterministic
                // snapshot. Lines-series effect symbols keep animating even when option.animation is
                // false, so sample those at the same 400 ms phase. EffectScatter ripples also keep
                // animating independently of option.animation; their paths are named `ripple`.
                let sampleTime: Double
                if el.name == "treemapLabel" {
                    // Snapshot mode forces option.animation=false in the Web oracle. Treemap's label
                    // enter animator is still installed by its label manager but remains parked at
                    // the initial opacity-zero frame, so keep Native at that same deterministic phase.
                    sampleTime = 0
                }
                else if el.name == "effectSymbol" || el.name == "ripple" {
                    sampleTime = 400
                }
                else {
                    sampleTime = timeMs
                }
                _ = clip.step(0, 0)          // establish baseline / apply delay offsets
                _ = clip.step(sampleTime, sampleTime) // advance to the representative frame
            }
        }
        // Attached text/guide elements are inserted into ZRender's display list but are not ordinary
        // Group children, so Element.traverse does not visit them. Advance their independent animators
        // explicitly. Treemap labels are named `treemapLabel`, which lets the sampler preserve the
        // Web snapshot's initial label phase without affecting unrelated text animations.
        if let text = el.getTextContent() { advance(text) }
        if let guide = el.getTextGuideLine() { advance(guide) }
    }
    advance(root)
    _ = root.traverse { el in advance(el); return false }
}

/// Drive ECharts with the demo option. Phase 6c: the real SourceManager builds each series' data
/// from the option's own `series[].data`, so the stock Bar/Line series models render directly — no
/// data double is registered anymore.
@MainActor
func renderNativeGroup(_ demo: EChartsDemo) -> Group {
    var opt = demo.option
    opt["animation"] = false
    // `geo-lines` uses endlessly looping, negatively staggered ripples whose phase origin differs
    // between the native animation clock and WKWebView. Its Web snapshot applies the same static
    // hover-only trigger, so compare the stable weighted core symbols and all line/map geometry.
    if demo.name == "official-geo-lines", var series = opt["series"] as? [[String: Any]] {
        for i in series.indices where series[i]["type"] as? String == "effectScatter" {
            series[i]["showEffectOn"] = "emphasis"
        }
        opt["series"] = series
    }
    let ec = ECharts(width: demo.width, height: demo.height)
    ec.setOption(opt)
    let root = ec.getRoot()
    advanceAnimationsForStaticFrame(root)
    // axisPointer draggable HANDLE (+ its crosshair): normally zr-hosted by EChartsView (like the
    //   tooltip), so it lives ABOVE ec.getRoot() and this bare-root static harness would not show it.
    //   For a faithful side-by-side, draw the parked handle(s) into `root`. STRICTLY gated on
    //   `useHandle` (handle.show) so the ~287 non-handle demos are completely unaffected.
    renderAxisPointerHandlesIntoRoot(ec, root)
    return root
}

/// Draw the parked axisPointer crosshair + draggable handle for each `handle.show` axis into `root`,
/// mirroring EChartsView._renderInitialAxisPointerHandles (which the interactive view runs). Static
/// (no animation). Only `useHandle` axes are touched.
@MainActor
func renderAxisPointerHandlesIntoRoot(_ ec: ECharts, _ root: Group) {
    guard let ecModel = ec.getModel(),
          let apModel = ecModel.getComponent("axisPointer") as? AxisPointerModel,
          let result = apModel.coordSysAxesInfo as? CollectionResult else { return }
    let api = ec.api
    for (_, axisInfo) in result.axesInfo where axisInfo.useHandle {
        guard axisInfo.axis is Axis2D, let axisModel = axisInfo.axis.model else { continue }
        fixValue(axisModel)
        let pointer = CartesianAxisPointer()
        pointer.hostAdd = { g in _ = root.add(g) }
        pointer.hostAddHandle = { el in _ = root.add(el) }
        pointer.render(axisModel, axisInfo.axisPointerModel, api, false)
    }
}

@MainActor
func renderNativeImage(_ demo: EChartsDemo, dpr: Double = 2.0) -> CGImage? {
    let group = renderNativeGroup(demo)
    let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
    return renderToImage(group: group,
                         size: CGSize(width: demo.width, height: demo.height),
                         dpr: dpr, backgroundColor: white)
}

@MainActor
func writeNativePNG(_ demo: EChartsDemo, to url: URL) -> Bool {
    guard let cg = renderNativeImage(demo) else { return false }
    let rep = NSBitmapImageRep(cgImage: cg)
    guard let png = rep.representation(using: .png, properties: [:]) else { return false }
    do { try png.write(to: url); return true } catch { return false }
}

// ---------------------------------------------------------------------------
// GUI — standard macOS chrome (Notes-style), aligned 1:1 with DemoGallery's:
// NSSplitViewController with a source-list sidebar + unified toolbar. On
// macOS 26 (Tahoe) these system components render with Liquid Glass
// automatically; the content header also uses an explicit NSGlassEffectView
// where available.
// ---------------------------------------------------------------------------

/// Demos grouped by category, in first-seen order (drives the source list sections).
struct DemoSection { let title: String; let demos: [EChartsDemo] }

func demoSections(_ collection: EChartsDemo.Collection) -> [DemoSection] {
    var order: [String] = []
    var byCat: [String: [EChartsDemo]] = [:]
    func add(_ d: EChartsDemo, to cat: String) {
        if byCat[cat] == nil { order.append(cat) }
        byCat[cat, default: []].append(d)
    }
    for d in EChartsDemoRegistry.demos(in: collection) {
        add(d, to: d.category)
        // The official gallery lists some examples under SEVERAL chart-type categories (pie-rich-text
        // sits under both `pie` and `rich`). One demo file per example, but the sidebar mirrors the
        // site and shows it under each — otherwise `rich`, `lines` and `dataZoom`, whose examples are
        // all cross-listed, would have no section at all.
        for extra in EChartsDemoRegistry.officialAlsoIn[d.name] ?? [] { add(d, to: extra) }
    }
    // The official tab reads in the site's own category order; the port tab keeps registry order.
    if collection == .official {
        let rank = Dictionary(uniqueKeysWithValues: EChartsDemoRegistry.officialCategoryOrder.enumerated().map { ($1, $0) })
        order.sort { (rank[$0] ?? .max, $0) < (rank[$1] ?? .max, $1) }
    }
    return order.map { DemoSection(title: $0, demos: byCat[$0]!) }
}

/// The official tab's categories are the official gallery's own ids (lowercase, e.g. `themeRiver`,
/// `pictorialBar`); the port tab's are capitalized (`ThemeRiver`). Match case-insensitively so one
/// table serves both.
func symbol(for category: String) -> String {
    switch category.lowercased() {
    case "bar":           return "chart.bar"
    case "line":          return "chart.xyaxis.line"
    case "scatter":       return "circle.grid.3x3"
    case "effectscatter": return "dot.radiowaves.left.and.right"
    case "lines":         return "scribble"
    case "pie":           return "chart.pie"
    case "component":     return "slider.horizontal.3"
    case "funnel":        return "arrowtriangle.down"
    case "candlestick":   return "chart.bar.xaxis"
    case "boxplot":       return "square.split.2x1"
    case "sunburst":      return "sun.max"
    case "treemap":       return "square.grid.2x2"
    case "tree":          return "arrow.triangle.branch"
    case "graph":         return "point.3.connected.trianglepath.dotted"
    case "radar":         return "hexagon"
    case "polar":         return "circle.circle"
    case "gauge":         return "gauge"
    case "sankey":        return "arrow.triangle.merge"
    case "chord":         return "circle.hexagonpath"
    case "themeriver":    return "waveform.path"
    case "parallel":      return "line.3.horizontal"
    case "calendar":      return "calendar"
    case "matrix":        return "tablecells"
    case "geo":           return "map"
    case "map":           return "map.fill"
    case "visualmap":     return "slider.horizontal.below.rectangle"
    case "heatmap":       return "square.grid.3x3.fill"
    case "datazoom":      return "magnifyingglass"
    case "dataset":       return "tablecells.badge.ellipsis"
    case "custom":        return "wrench.and.screwdriver"
    // official-only categories
    case "pictorialbar":  return "chart.bar.doc.horizontal"
    case "graphic":       return "square.on.circle"
    case "rich":          return "textformat"
    default:              return "chart.bar"
    }
}

// MARK: - Sidebar (NSOutlineView, source-list style)

/// Outline view that copies the selected demo's name on ⌘C (the app has no menu bar to route copy:).
final class DemoOutlineView: NSOutlineView {
    var onCopy: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command),
           event.charactersIgnoringModifiers?.lowercased() == "c" {
            onCopy?()
            return
        }
        super.keyDown(with: event)
    }
}

final class SidebarViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuItemValidation {
    /// The demo set the sidebar is showing — switched by the tab picker above the list.
    /// `ECHARTS_GALLERY_TAB=official` opens straight on the official-examples tab.
    private(set) var collection: EChartsDemo.Collection =
        ProcessInfo.processInfo.environment["ECHARTS_GALLERY_TAB"] == "official" ? .official : .port
    private(set) lazy var sections: [DemoSection] = demoSections(collection)
    var onSelect: ((EChartsDemo) -> Void)?
    /// Fired when the tab changes, so the window subtitle can follow the visible demo count.
    var onCollectionChange: ((EChartsDemo.Collection) -> Void)?
    private let outline = DemoOutlineView()
    private let tabs = NSSegmentedControl(labels: ["移植", "官方示例"],
                                          trackingMode: .selectOne, target: nil, action: nil)
    /// True while `select(row:)` is driving the selection — the delegate stays quiet and lets it announce.
    private var announcingSelection = false

    override func loadView() {
        outline.headerView = nil
        outline.style = .sourceList
        outline.indentationPerLevel = 6
        outline.allowsEmptySelection = false
        outline.autoresizesOutlineColumn = false
        let col = NSTableColumn(identifier: .init("main"))
        outline.addTableColumn(col)
        outline.outlineTableColumn = col
        outline.dataSource = self
        outline.delegate = self

        // Copy a demo's name: right-click → Copy, or ⌘C on the selected row. Handy for noting a
        // problem case's exact id (e.g. for --render / --compare).
        let menu = NSMenu()
        let copyName = NSMenuItem(title: "Copy Name", action: #selector(copyClickedDemoName(_:)), keyEquivalent: "")
        let copyNameCat = NSMenuItem(title: "Copy Name & Category", action: #selector(copyClickedDemoNameCategory(_:)), keyEquivalent: "")
        for it in [copyName, copyNameCat] { it.target = self; menu.addItem(it) }
        outline.menu = menu
        outline.onCopy = { [weak self] in self?.copySelectedDemoName() }

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.documentView = outline
        scroll.translatesAutoresizingMaskIntoConstraints = false

        // Tab picker: which demo set the list shows (.port | .official).
        tabs.translatesAutoresizingMaskIntoConstraints = false
        tabs.segmentDistribution = .fillEqually
        tabs.selectedSegment = collection == .official ? 1 : 0
        tabs.target = self
        tabs.action = #selector(tabChanged)

        let container = NSView()
        container.addSubview(tabs)
        container.addSubview(scroll)
        NSLayoutConstraint.activate([
            tabs.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor, constant: 8),
            tabs.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            tabs.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),

            scroll.topAnchor.constraint(equalTo: tabs.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        self.view = container
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // `ECHARTS_GALLERY_START=<demo name>` opens straight on one demo — how a dynamic demo gets
        // eyeballed (a still PNG cannot show a 2s morph; you have to watch the live pane).
        if let want = ProcessInfo.processInfo.environment["ECHARTS_GALLERY_START"],
           selectDemo(named: want) {
            return
        }
        expandAndSelectFirst()
    }

    /// Select a demo by name (switching tabs if it lives in the other collection). False if unknown.
    @discardableResult
    private func selectDemo(named name: String) -> Bool {
        guard let demo = EChartsDemoRegistry.byName(name) else { return false }
        if demo.collection != collection {
            collection = demo.collection
            tabs.selectedSegment = demo.collection == .official ? 1 : 0
            sections = demoSections(collection)
            outline.reloadData()
        }
        outline.expandItem(nil, expandChildren: true)
        for r in 0..<outline.numberOfRows {
            guard let d = outline.item(atRow: r) as? EChartsDemo, d.name == name else { continue }
            select(row: r)
            return true
        }
        return false
    }

    @objc private func tabChanged() {
        collection = tabs.selectedSegment == 1 ? .official : .port
        sections = demoSections(collection)
        outline.reloadData()
        expandAndSelectFirst()
        onCollectionChange?(collection)
    }

    /// Show every category and land on the first demo — the list is never left with no selection
    /// (`allowsEmptySelection` is off, but a reload clears the selection without notifying).
    private func expandAndSelectFirst() {
        outline.expandItem(nil, expandChildren: true)
        for r in 0..<outline.numberOfRows where outline.item(atRow: r) is EChartsDemo {
            select(row: r)
            break
        }
    }

    /// Select a row and announce it EXACTLY once. `selectRowIndexes` posts the selection
    /// notification when the selection changes but stays silent when the row is already selected, so
    /// neither "always announce" nor "let the delegate do it" is correct on its own — announcing from
    /// both built the demo twice, giving it two live hosts each running its own `drive` timers.
    private func select(row: Int) {
        guard let d = outline.item(atRow: row) as? EChartsDemo else { return }
        announcingSelection = true
        outline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        outline.scrollRowToVisible(row)
        announcingSelection = false
        onSelect?(d)
    }

    // MARK: Copy demo name

    private func demo(atRow row: Int) -> EChartsDemo? {
        guard row >= 0, row < outline.numberOfRows else { return nil }
        return outline.item(atRow: row) as? EChartsDemo
    }

    private func copyToPasteboard(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
    }

    @objc private func copyClickedDemoName(_ sender: Any?) {
        if let d = demo(atRow: outline.clickedRow) { copyToPasteboard(d.name) }
    }

    @objc private func copyClickedDemoNameCategory(_ sender: Any?) {
        if let d = demo(atRow: outline.clickedRow) { copyToPasteboard("\(d.name) [\(d.category)]") }
    }

    private func copySelectedDemoName() {
        if let d = demo(atRow: outline.selectedRow) { copyToPasteboard(d.name) }
    }

    // Disable the context-menu items when the right-clicked row isn't a demo (e.g. a section header).
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        return demo(atRow: outline.clickedRow) != nil
    }

    // Data source
    func outlineView(_ ov: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil { return sections.count }
        if let s = item as? DemoSection { return s.demos.count }
        return 0
    }
    func outlineView(_ ov: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil { return sections[index] }
        return (item as! DemoSection).demos[index]
    }
    func outlineView(_ ov: NSOutlineView, isItemExpandable item: Any) -> Bool { item is DemoSection }

    // Delegate
    func outlineView(_ ov: NSOutlineView, isGroupItem item: Any) -> Bool { item is DemoSection }
    func outlineView(_ ov: NSOutlineView, shouldSelectItem item: Any) -> Bool { item is EChartsDemo }

    func outlineView(_ ov: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        if let s = item as? DemoSection {
            let id = NSUserInterfaceItemIdentifier("group")
            let tf = (ov.makeView(withIdentifier: id, owner: self) as? NSTextField)
                ?? { let t = NSTextField(labelWithString: ""); t.identifier = id; return t }()
            tf.stringValue = s.title
            return tf
        }
        let d = item as! EChartsDemo
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = (ov.makeView(withIdentifier: id, owner: self) as? NSTableCellView) ?? Self.makeCell(id)
        cell.textField?.stringValue = d.displayName
        cell.textField?.textColor = d.nativeSupported ? .labelColor : .secondaryLabelColor
        cell.toolTip = d.nativeSupported ? d.summary : d.summary + " (native N/A)"
        cell.imageView?.image = NSImage(systemSymbolName: symbol(for: d.category),
                                        accessibilityDescription: d.category)
        return cell
    }

    private static func makeCell(_ id: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let c = NSTableCellView()
        let iv = NSImageView()
        let tf = NSTextField(labelWithString: "")
        iv.translatesAutoresizingMaskIntoConstraints = false
        tf.translatesAutoresizingMaskIntoConstraints = false
        c.addSubview(iv); c.addSubview(tf)
        c.imageView = iv; c.textField = tf
        c.identifier = id
        NSLayoutConstraint.activate([
            iv.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 2),
            iv.centerYAnchor.constraint(equalTo: c.centerYAnchor),
            iv.widthAnchor.constraint(equalToConstant: 18),
            tf.leadingAnchor.constraint(equalTo: iv.trailingAnchor, constant: 6),
            tf.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -4),
            tf.centerYAnchor.constraint(equalTo: c.centerYAnchor),
        ])
        return c
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !announcingSelection else { return }   // select(row:) announces it itself
        if let d = outline.item(atRow: outline.selectedRow) as? EChartsDemo { onSelect?(d) }
    }
}

// MARK: - Content (render area): glass header pill + native | echarts.js cards

final class ContentViewController: NSViewController {
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let nativeHost = NSView()
    // Live native render: the chart lays out at the demo's LOGICAL size (ECharts has no resize
    // hook), so host a fresh EChartsHostView at that size inside a scroll view and fit-scale it via
    // `magnification` — the same trick DemoGallery uses for its 1000px zrender canvases.
    private let liveScroll = NSScrollView()
    private var currentHostView: EChartsHostView?
    private let webHost = NSView()
    private let webView = WKWebView()
    private let animSwitch = NSSwitch()
    // Rendering-backend toggle: CoreGraphics (CALayerPainter, default) vs the experimental
    // Metal RasterizerPainter — same seam as DemoGallery's checkbox.
    private let metalSwitch = NSSwitch()
    private let nativeCap = NSTextField(labelWithString: "Native · EChartsKit + NativePainter")
    private var currentDemo: EChartsDemo?

    override func loadView() {
        let root = NSView()

        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabelColor
        let labels = NSStackView(views: [titleLabel, subtitleLabel])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 1
        labels.edgeInsets = NSEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)

        // Header in Liquid Glass where available; plain otherwise (same as DemoGallery).
        let header: NSView
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = 12
            glass.contentView = labels
            header = glass
        } else {
            labels.wantsLayer = true
            labels.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.5).cgColor
            labels.layer?.cornerRadius = 12
            header = labels
        }
        header.translatesAutoresizingMaskIntoConstraints = false

        func card(_ host: NSView) {
            host.translatesAutoresizingMaskIntoConstraints = false
            host.wantsLayer = true
            host.layer?.backgroundColor = NSColor.white.cgColor
            host.layer?.cornerRadius = 14
            host.layer?.masksToBounds = true
            host.layer?.borderWidth = 0.5
            host.layer?.borderColor = NSColor.separatorColor.cgColor
        }
        card(nativeHost); card(webHost)

        liveScroll.translatesAutoresizingMaskIntoConstraints = false
        liveScroll.drawsBackground = false
        liveScroll.hasVerticalScroller = false
        liveScroll.hasHorizontalScroller = false
        liveScroll.borderType = .noBorder
        liveScroll.allowsMagnification = true
        liveScroll.verticalScrollElasticity = .none
        liveScroll.horizontalScrollElasticity = .none
        nativeHost.addSubview(liveScroll)
        NSLayoutConstraint.activate([
            liveScroll.topAnchor.constraint(equalTo: nativeHost.topAnchor, constant: 8),
            liveScroll.leadingAnchor.constraint(equalTo: nativeHost.leadingAnchor, constant: 8),
            liveScroll.trailingAnchor.constraint(equalTo: nativeHost.trailingAnchor, constant: -8),
            liveScroll.bottomAnchor.constraint(equalTo: nativeHost.bottomAnchor, constant: -8),
        ])

        webView.translatesAutoresizingMaskIntoConstraints = false
        webHost.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: webHost.topAnchor),
            webView.leadingAnchor.constraint(equalTo: webHost.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: webHost.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: webHost.bottomAnchor),
        ])

        nativeCap.font = .systemFont(ofSize: 11, weight: .medium)
        nativeCap.textColor = .secondaryLabelColor
        nativeCap.translatesAutoresizingMaskIntoConstraints = false
        let webCap = caption("Real · echarts.js 6.1.0 (WKWebView)")

        let animLabel = caption("Native 动画")
        animSwitch.translatesAutoresizingMaskIntoConstraints = false
        animSwitch.state = .off
        animSwitch.target = self
        animSwitch.action = #selector(toggleAnim)

        let metalLabel = caption("Metal")
        metalSwitch.translatesAutoresizingMaskIntoConstraints = false
        metalSwitch.state = ProcessInfo.processInfo.environment["DEMO_GALLERY_RASTERIZER"] == "1" ? .on : .off
        metalSwitch.target = self
        metalSwitch.action = #selector(toggleAnim)   // same handler: re-show the current demo

        [header, nativeCap, webCap, nativeHost, webHost, animLabel, animSwitch,
         metalLabel, metalSwitch].forEach { root.addSubview($0) }
        // Pin to the SAFE AREA (not raw view): with `.fullSizeContentView` + a unified toolbar
        // the content extends under the toolbar; safeAreaLayoutGuide.top sits below it.
        let safe = root.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: safe.topAnchor, constant: 12),
            header.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 20),
            header.trailingAnchor.constraint(lessThanOrEqualTo: safe.trailingAnchor, constant: -20),

            nativeCap.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
            nativeCap.leadingAnchor.constraint(equalTo: nativeHost.leadingAnchor, constant: 2),
            webCap.topAnchor.constraint(equalTo: nativeCap.topAnchor),
            webCap.leadingAnchor.constraint(equalTo: webHost.leadingAnchor, constant: 2),

            animSwitch.centerYAnchor.constraint(equalTo: nativeCap.centerYAnchor),
            animSwitch.trailingAnchor.constraint(equalTo: nativeHost.trailingAnchor, constant: -2),
            animLabel.centerYAnchor.constraint(equalTo: nativeCap.centerYAnchor),
            animLabel.trailingAnchor.constraint(equalTo: animSwitch.leadingAnchor, constant: -6),

            metalSwitch.centerYAnchor.constraint(equalTo: nativeCap.centerYAnchor),
            metalSwitch.trailingAnchor.constraint(equalTo: animLabel.leadingAnchor, constant: -14),
            metalLabel.centerYAnchor.constraint(equalTo: nativeCap.centerYAnchor),
            metalLabel.trailingAnchor.constraint(equalTo: metalSwitch.leadingAnchor, constant: -6),

            nativeHost.topAnchor.constraint(equalTo: nativeCap.bottomAnchor, constant: 6),
            nativeHost.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 20),
            nativeHost.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -20),

            webHost.topAnchor.constraint(equalTo: nativeHost.topAnchor),
            webHost.leadingAnchor.constraint(equalTo: nativeHost.trailingAnchor, constant: 16),
            webHost.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -20),
            webHost.bottomAnchor.constraint(equalTo: nativeHost.bottomAnchor),
            webHost.widthAnchor.constraint(equalTo: nativeHost.widthAnchor),
        ])
        self.view = root
    }

    private func caption(_ s: String) -> NSTextField {
        let c = NSTextField(labelWithString: s)
        c.font = .systemFont(ofSize: 11, weight: .medium)
        c.textColor = .secondaryLabelColor
        c.translatesAutoresizingMaskIntoConstraints = false
        return c
    }

    func show(_ demo: EChartsDemo) {
        currentDemo = demo
        titleLabel.stringValue = demo.displayName
        subtitleLabel.stringValue = "\(demo.category) · \(demo.summary)"

        // Tear down the previous live chart (dropping the last strong ref deallocates the host,
        // whose deinit stops its animation clock + disposes its ZRender), then build a FRESH host
        // at the demo's logical size — the same per-demo lifecycle as DemoGallery's ZRenderView.
        currentHostView?.dispose()
        currentHostView?.removeFromSuperview()
        currentHostView = nil
        liveScroll.documentView = nil
        if demo.nativeSupported {
            var opt = demo.liveOption ?? demo.option
            if animSwitch.state == .off { opt["animation"] = false }   // ON → leave echarts default (animate)
            let useMetal = metalSwitch.state == .on
            nativeCap.stringValue = useMetal
                ? "Native · EChartsKit + Rasterizer (Metal)"
                : "Native · EChartsKit + NativePainter"
            let logical = NSRect(x: 0, y: 0, width: demo.width, height: demo.height)
            let painter: LayerHostedPainter? = useMetal
                ? RasterizerPainter(size: logical.size, dpr: 2.0,
                                    backgroundColor: NSColor.white.cgColor)
                : nil
            let host = EChartsHostView(frame: logical, dpr: 2.0, painter: painter)
            host.animationsEnabled = animSwitch.state == .on
            host.setOption(opt)
            // Replay the example's own timeline (its setInterval / setOption), if it has one. Without
            // this a dynamic example — map-bar-morph's map<->bar morph, dynamic-data's shifting
            // window — would sit frozen on its first frame while the web pane next to it animated.
            demo.drive?(host)
            liveScroll.documentView = host
            currentHostView = host
            fitNativeMagnification()
        }

        // HTML pane — the example as the website runs it (timers, dispatchAction and all).
        if let page = echartsHTMLPage(demo) {
            webView.loadHTMLString(page, baseURL: nil)
        }
        fitWebZoom()
    }

    /// Fit the live chart's logical canvas into the scroll view via `magnification` (aspect-fit).
    /// Uses the scroll view's OWN bounds, not the clip view's (see DemoGallery for the oscillation
    /// bug that clip-view bounds cause — they are in already-magnified document coordinates).
    private func fitNativeMagnification() {
        guard let doc = currentHostView else { return }
        let clip = liveScroll.bounds.size
        let dw = doc.frame.width, dh = doc.frame.height
        guard clip.width > 0, clip.height > 0, dw > 0, dh > 0 else { return }
        let s = min(clip.width / dw, clip.height / dh)
        // Bracket the target so setting `magnification` can't be clamped by stale min/max bounds.
        liveScroll.minMagnification = min(s, 1)
        liveScroll.maxMagnification = max(s, 1)
        if abs(liveScroll.magnification - s) > 1e-4 {
            liveScroll.magnification = s
        }
    }

    /// Match the web pane's zoom to the native fit so both panes show the chart at the same scale
    /// (macOS WKWebView ignores the page's viewport meta; `pageZoom` is the mac equivalent).
    private func fitWebZoom() {
        guard let d = currentDemo, d.width > 0, d.height > 0 else { return }
        let size = webView.bounds.size
        guard size.width > 0, size.height > 0 else { return }
        let s = min(size.width / d.width, size.height / d.height)
        webView.pageZoom = min(max(s, 0.25), 3)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        fitNativeMagnification()
        fitWebZoom()
    }

    @objc private func toggleAnim() {
        if let d = currentDemo { show(d) }
    }
}

// MARK: - Split + window + toolbar

final class GallerySplitViewController: NSSplitViewController {
    let sidebar = SidebarViewController()
    let content = ContentViewController()

    override func viewDidLoad() {
        super.viewDidLoad()
        let side = NSSplitViewItem(sidebarWithViewController: sidebar)
        side.minimumThickness = 210
        side.maximumThickness = 320
        side.canCollapse = true
        addSplitViewItem(side)

        let main = NSSplitViewItem(viewController: content)
        main.minimumThickness = 500
        addSplitViewItem(main)

        sidebar.onSelect = { [weak self] demo in self?.content.show(demo) }
        sidebar.onCollectionChange = { [weak self] c in
            let n = EChartsDemoRegistry.demos(in: c).count
            self?.view.window?.subtitle = c == .official
                ? "Official Examples · \(n) demos"
                : "ECharts Demo Gallery · \(n) demos"
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSToolbarDelegate {
    var window: NSWindow!
    private let splitVC = GallerySplitViewController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        win.title = "echarts → Swift"
        let tab = splitVC.sidebar.collection
        let shown = EChartsDemoRegistry.demos(in: tab).count
        win.subtitle = tab == .official
            ? "Official Examples · \(shown) demos"
            : "ECharts Demo Gallery · \(shown) demos"
        win.contentViewController = splitVC

        let toolbar = NSToolbar(identifier: "main")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        win.toolbar = toolbar
        win.toolbarStyle = .unified

        win.center()
        win.makeKeyAndOrderFront(nil)
        self.window = win
        NSApp.activate(ignoringOtherApps: true)
    }

    // System-provided items (toggle sidebar + the sidebar/content tracking separator) auto-wire
    // to the NSSplitViewController; the delegate just lists them.
    func toolbarDefaultItemIdentifiers(_ tb: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace]
    }
    func toolbarAllowedItemIdentifiers(_ tb: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace, .space]
    }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? { nil }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

// ---------------------------------------------------------------------------
// Headless WKWebView snapshot (mirrors DemoGallery's WebSnapper).
// ---------------------------------------------------------------------------

@MainActor
final class WebSnapper: NSObject, WKNavigationDelegate {
    let out: URL
    init(out: URL) { self.out = out }
    func webView(_ wv: WKWebView, didFinish nav: WKNavigation!) {
        // Give ECharts a tick to lay out + paint. A demo with async local assets can explicitly hold
        // the snapshot by setting `window.__echartsSnapshotReady = false`; poll that opt-in marker
        // instead of capturing a timing-dependent intermediate frame.
        waitUntilReady(wv, attempt: 0)
    }
    private func waitUntilReady(_ wv: WKWebView, attempt: Int) {
        let delay = attempt == 0 ? 0.4 : 0.1
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            wv.evaluateJavaScript("window.__echartsSnapshotReady !== false") { value, _ in
                let ready = (value as? Bool) ?? true
                // Explicitly gated heavyweight examples (for example the 624k-polyline New York
                // street map) can need well beyond three seconds for their first complete canvas.
                // Ordinary demos never set the marker false and still snapshot after the initial
                // 0.4 s delay; only opted-in async/progressive pages use this 30 s ceiling.
                if !ready && attempt < 300 {
                    self.waitUntilReady(wv, attempt: attempt + 1)
                    return
                }
                self.takeSnapshot(wv)
            }
        }
    }
    private func takeSnapshot(_ wv: WKWebView) {
        let cfg = WKSnapshotConfiguration(); cfg.rect = wv.bounds
        wv.takeSnapshot(with: cfg) { image, _ in
            defer { exit(0) }
            guard let image = image,
                  let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else {
                FileHandle.standardError.write(Data("snapshot failed\n".utf8)); return
            }
            try? png.write(to: self.out); print("wrote \(self.out.path)")
        }
    }
    func webView(_ wv: WKWebView, didFail nav: WKNavigation!, withError e: Error) {
        FileHandle.standardError.write(Data("web load failed: \(e)\n".utf8)); exit(1)
    }
}

/// Reference holder for --anim-invariant's per-offset element-identity snapshots (the asyncAfter
/// closures share and append to it across the run loop).
final class AnimInvariantSnaps {
    var samples: [(time: Int, ids: Set<ObjectIdentifier>, activeAnimators: Int)] = []
}

/// Live-timeline analog of WebSnapper: snapshots the echarts.js pane at a series of wall-clock offsets
/// (from page load) WITHOUT neutering animation/setInterval — the web oracle for --anim-native's frames.
final class WebMultiSnapper: NSObject, WKNavigationDelegate {
    let demo: EChartsDemo; let dir: URL; let offsets: [Int]
    init(demo: EChartsDemo, dir: URL, offsets: [Int]) { self.demo = demo; self.dir = dir; self.offsets = offsets }
    func webView(_ wv: WKWebView, didFinish nav: WKNavigation!) {
        for (i, t) in offsets.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(t) / 1000.0) {
                let cfg = WKSnapshotConfiguration(); cfg.rect = wv.bounds
                wv.takeSnapshot(with: cfg) { image, _ in
                    if let image = image, let tiff = image.tiffRepresentation,
                       let rep = NSBitmapImageRep(data: tiff),
                       let png = rep.representation(using: .png, properties: [:]) {
                        let out = self.dir.appendingPathComponent(String(format: "%@.t%04d.web.png", self.demo.name, t))
                        try? png.write(to: out); print("wrote \(out.lastPathComponent)")
                    } else {
                        print("t\(t) web snapshot FAILED")
                    }
                    if i == self.offsets.count - 1 { exit(0) }
                }
            }
        }
    }
    func webView(_ wv: WKWebView, didFail nav: WKNavigation!, withError e: Error) {
        FileHandle.standardError.write(Data("web load failed: \(e)\n".utf8)); exit(1)
    }
}

/// Deterministic entrance-animation oracle. The page has already stopped zrender's RAF loop before
/// setOption; each snapshot explicitly advances every entrance clip to the requested logical time.
final class WebEntranceSnapper: NSObject, WKNavigationDelegate {
    let demo: EChartsDemo
    let dir: URL
    let offsets: [Int]
    let page: String
    let actionJSON: String?
    private var index = 0

    init(demo: EChartsDemo, dir: URL, offsets: [Int], page: String, actionJSON: String? = nil) {
        self.demo = demo
        self.dir = dir
        self.offsets = offsets
        self.page = page
        self.actionJSON = actionJSON
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        waitUntilEntranceReady(webView, attempt: 0)
    }

    private func waitUntilEntranceReady(_ webView: WKWebView, attempt: Int) {
        webView.evaluateJavaScript(
            "({ ready: Boolean(window.__entranceReady && window.__stepEntranceAnimation)," +
            " stage: String(window.__entranceStage || 'missing')," +
            " error: String(window.__entranceError || '') })"
        ) { result, error in
            if let error {
                FileHandle.standardError.write(Data("entrance readiness probe failed: \(error)\n".utf8))
                exit(1)
            }
            let state = result as? [String: Any]
            if let pageError = state?["error"] as? String, !pageError.isEmpty {
                FileHandle.standardError.write(Data("entrance page failed for \(self.demo.name): \(pageError)\n".utf8))
                exit(1)
            }
            if (state?["ready"] as? Bool) == true {
                if let actionJSON = self.actionJSON {
                    self.prepareActionAnimation(webView, actionJSON: actionJSON)
                } else {
                    self.capture(webView)
                }
                return
            }
            guard attempt < 300 else {
                let stage = state?["stage"] as? String ?? "unknown"
                FileHandle.standardError.write(
                    Data("entrance readiness timed out for \(self.demo.name) at \(stage)\n".utf8)
                )
                exit(1)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                self.waitUntilEntranceReady(webView, attempt: attempt + 1)
            }
        }
    }

    /// Settle the initial setOption animation, dispatch one interaction, then replace the entrance
    /// stepper with the clips created by that interaction. This gives legend/update animations the
    /// same deterministic visual oracle as first-render animations.
    private func prepareActionAnimation(_ webView: WKWebView, actionJSON: String) {
        let script = """
        (function () {
          window.__stepEntranceAnimation(1000000000);
          var action = \(actionJSON);
          if (action.type === '__setOption') { myChart.setOption(action.option || {}); }
          else if (action.type === '__hoverData') {
            myChart.getZr().storage.getDisplayList(true);
            var series = myChart.getModel().getSeriesByIndex(action.seriesIndex || 0);
            var data = series && series.getData();
            var el = data && data.getItemGraphicEl(action.dataIndex || 0);
            if (!el) { throw new Error('__hoverData could not resolve a data element'); }
            if (!el.contain && el.traverse) {
              var childTarget = null;
              el.traverse(function (child) {
                if (!childTarget && child && child.contain
                    && child.states && child.states.emphasis) { childTarget = child; }
              });
              if (childTarget) { el = childTarget; }
            }
            var point;
            var shape = el.shape || {};
            if (shape.cx != null && shape.cy != null && shape.r != null
                && shape.startAngle != null && shape.endAngle != null) {
              var angle = (shape.startAngle + shape.endAngle) / 2;
              var radius = ((shape.r0 || 0) + shape.r) / 2;
              point = el.transformCoordToGlobal(shape.cx + Math.cos(angle) * radius,
                                                 shape.cy + Math.sin(angle) * radius);
              if (!el.contain(point[0], point[1])) { point = null; }
            }
            if (!point) {
              var bounds = el.getBoundingRect();
              for (var gy = 1; gy < 20 && !point; gy++) {
                for (var gx = 1; gx < 20; gx++) {
                  var candidate = el.transformCoordToGlobal(
                    bounds.x + bounds.width * gx / 20,
                    bounds.y + bounds.height * gy / 20
                  );
                  if (el.contain(candidate[0], candidate[1])) { point = candidate; break; }
                }
              }
            }
            if (!point) { throw new Error('__hoverData could not find a contained hit point'); }
            myChart.getZr().handler.dispatchToElement(
              { target: el, topTarget: el }, 'mouseover', { zrX: point[0], zrY: point[1] }
            );
            // ECharts applies high/down flags in its next frame (`applyChangedStates`). The
            // deterministic oracle has intentionally stopped zrender's RAF loop, so explicitly run
            // that frame seam before collecting the interaction clips. Without this, the real Web
            // chart has the correct hover animation in a browser but this frozen harness reports 0
            // clips and captures the unchanged pre-hover frame.
            if (myChart._onframe) { myChart._onframe(); }
          }
          else if (action.type === '__legendClick') {
            var item = action.name;
            myChart.dispatchAction({ type: 'downplay', name: item });
            myChart.dispatchAction({ type: 'legendToggleSelect', name: item });
            myChart.dispatchAction({ type: 'highlight', name: item });
          }
          else { myChart.dispatchAction(action); }
          myChart.getZr().animation.stop();
          var clips = [];
          var seenElements = new Set();
          var seenClips = new Set();
          function collect(el) {
            if (!el || seenElements.has(el)) { return; }
            seenElements.add(el);
            var animators = el.animators || [];
            for (var ai = 0; ai < animators.length; ai++) {
              var clip = animators[ai].getClip && animators[ai].getClip();
              if (clip && !seenClips.has(clip)) { seenClips.add(clip); clips.push(clip); }
            }
            if (el.getClipPath) { collect(el.getClipPath()); }
            if (el.getTextContent) { collect(el.getTextContent()); }
            if (el.getTextGuideLine) { collect(el.getTextGuideLine()); }
            if (el.children) {
              var children = el.children();
              for (var ci = 0; ci < children.length; ci++) { collect(children[ci]); }
            }
          }
          var roots = myChart.getZr().storage.getRoots();
          for (var ri = 0; ri < roots.length; ri++) { collect(roots[ri]); }
          for (var i = 0; i < clips.length; i++) {
            clips[i]._inited = false;
            clips[i]._startTime = 0;
            clips[i]._pausedTime = 0;
            clips[i]._paused = false;
            clips[i].__entranceFinished = false;
          }
          window.__stepEntranceAnimation = function (timeMs) {
            for (var ci = 0; ci < clips.length; ci++) {
              var clip = clips[ci];
              if (clip.__entranceFinished) { continue; }
              var elapsed = timeMs - clip._delay;
              var percent = clip.loop && elapsed >= 0
                ? (elapsed % clip._life) / clip._life
                : Math.max(0, Math.min(elapsed / clip._life, 1));
              clip.onframe(clip.easingFunc ? clip.easingFunc(percent) : percent);
              if (!clip.loop && elapsed >= clip._life) {
                clip.ondestroy();
                clip.__entranceFinished = true;
              }
            }
            seenElements.forEach(function (el) { if (el.markRedraw) { el.markRedraw(); } });
            myChart.getZr().animation.stop();
            myChart.getZr().refreshImmediately(true);
            return { clips: clips.length, time: timeMs };
          };
          return { clips: clips.length };
        })()
        """
        webView.evaluateJavaScript(script) { result, error in
            if let error {
                FileHandle.standardError.write(Data("action animation setup failed: \(error)\n".utf8))
                exit(1)
            }
            print("action animation ready: \(result ?? [:])")
            self.capture(webView)
        }
    }

    private func capture(_ webView: WKWebView) {
        guard index < offsets.count else { exit(0) }
        let time = offsets[index]
        let diagnosticStep = """
        (function () {
          var step = window.__stepEntranceAnimation(\(time));
          var sources = Array.prototype.slice.call(myChart.getDom().querySelectorAll('canvas'));
          sources.sort(function (a, b) {
            return (parseFloat(a.style.zIndex) || 0) - (parseFloat(b.style.zIndex) || 0);
          });
          var source = sources[0];
          var output = document.createElement('canvas');
          output.width = source.width;
          output.height = source.height;
          var context = output.getContext('2d');
          context.fillStyle = '#fff';
          context.fillRect(0, 0, output.width, output.height);
          for (var canvasIndex = 0; canvasIndex < sources.length; canvasIndex++) {
            var layer = sources[canvasIndex];
            if (layer.style.display === 'none' || layer.style.visibility === 'hidden') { continue; }
            context.save();
            context.globalAlpha = layer.style.opacity === '' ? 1 : Number(layer.style.opacity);
            context.drawImage(layer, 0, 0);
            context.restore();
          }
          return {
            step: step,
            png: output.toDataURL('image/png')
          };
        })()
        """
        webView.evaluateJavaScript(diagnosticStep) { result, error in
            if let error {
                FileHandle.standardError.write(Data("entrance step t\(time) failed: \(error)\n".utf8))
                exit(1)
            }
            guard let result = result as? [String: Any],
                  let dataURL = result["png"] as? String,
                  let comma = dataURL.firstIndex(of: ","),
                  let png = Data(base64Encoded: String(dataURL[dataURL.index(after: comma)...])) else {
                FileHandle.standardError.write(Data("entrance canvas t\(time) failed\n".utf8))
                exit(1)
            }
            print("entrance web t\(time): \(result["step"] ?? [:])")
                let out = self.dir.appendingPathComponent(
                    String(format: "%@.t%04d.web.png", self.demo.name, time)
                )
                do {
                    try png.write(to: out)
                    print("wrote \(out.lastPathComponent)")
                    self.index += 1
                    if self.index == self.offsets.count { exit(0) }
                    // Recreate the chart for every logical timestamp. Completion callbacks and
                    // stateful tracks from an earlier sample must not influence a later keyframe.
                    webView.loadHTMLString(self.page, baseURL: nil)
                }
                catch {
                    FileHandle.standardError.write(Data("write failed: \(error)\n".utf8))
                    exit(1)
                }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        FileHandle.standardError.write(Data("web load failed: \(error)\n".utf8))
        exit(1)
    }
}

/// Walk normal children plus attached clip/text/guide elements and return each unique animator clip.
/// A bare ECharts instance has no display-link host, so these clips remain at their pristine t=0 state
/// until this deterministic validation path advances them.
private func entranceAnimationClips(_ root: Element) -> [Clip] {
    var clips: [Clip] = []
    var seenElements = Set<ObjectIdentifier>()
    var seenClips = Set<ObjectIdentifier>()

    func visit(_ element: Element?) {
        guard let element else { return }
        let elementID = ObjectIdentifier(element)
        guard seenElements.insert(elementID).inserted else { return }
        for animator in element.animators {
            guard let clip = animator.getClip() else { continue }
            if seenClips.insert(ObjectIdentifier(clip)).inserted { clips.append(clip) }
        }
        visit(element.getClipPath())
        visit(element.getTextContent())
        visit(element.getTextGuideLine())
        if let group = element as? Group {
            for child in group.children() { visit(child) }
        }
    }

    visit(root)
    return clips
}

/// Resolve a stable hit point for deterministic hover-animation snapshots. Polar sectors need a
/// point halfway through the annulus (the bounding-box center can sit in the empty inner hole);
/// ordinary symbols/bars use their local bounding-box center. Both are transformed through the
/// element's complete parent transform before entering the real Handler hit-test path.
func deterministicHoverPoint(
    _ element: Element,
    accepting: (([Double]) -> Bool)? = nil
) -> [Double]? {
    func accepted(_ point: [Double]) -> Bool {
        (accepting?(point) ?? true)
    }
    if let path = element as? Path, let sector = path.shape as? SectorShape {
        let angle = (sector.startAngle + sector.endAngle) / 2
        let radius = (sector.r0 + sector.r) / 2
        let candidate = element.transformCoordToGlobal(
            sector.cx + cos(angle) * radius,
            sector.cy + sin(angle) * radius
        )
        if path.contain(candidate[0], candidate[1]), accepted(candidate) { return candidate }
    }
    guard let bounds = element.getBoundingRect() else { return nil }
    for y in 1..<20 {
        for x in 1..<20 {
            let candidate = element.transformCoordToGlobal(
                bounds.x + bounds.width * Double(x) / 20,
                bounds.y + bounds.height * Double(y) / 20
            )
            if let displayable = element as? Displayable,
               displayable.contain(candidate[0], candidate[1]), accepted(candidate) {
                return candidate
            }
        }
    }
    return nil
}

private func interactiveDisplayables(in root: Element) -> [Displayable] {
    var result: [Displayable] = []
    func visit(_ element: Element) {
        if let displayable = element as? Displayable,
           displayable.states["emphasis"] != nil {
            result.append(displayable)
        }
        if let group = element as? Group {
            for child in group.children() { visit(child) }
        }
    }
    visit(root)
    return result
}

/// Drive a data-element hover through the real native Handler, matching the Web oracle's
/// `dispatchToElement(..., 'mouseover', ...)`. Returns false when the requested item cannot be
/// resolved to a point whose topmost hit target is that item.
func resolveDeterministicDataHit(
    _ action: [String: Any], ec: ECharts, view: EChartsView
) -> (element: Displayable, point: [Double])? {
    let seriesIndex = (action["seriesIndex"] as? NSNumber)?.doubleValue ?? 0
    let dataIndex = (action["dataIndex"] as? NSNumber)?.doubleValue ?? 0
    let displayList = view.zr.storage.getDisplayList(true)
    var candidates: [Displayable] = []
    if let dataRoot = ec.getModel()?.getSeriesByIndex(seriesIndex)?.getData()
        .getItemGraphicEl(Int(dataIndex)) {
        candidates.append(contentsOf: interactiveDisplayables(in: dataRoot))
    }
    candidates.append(contentsOf: displayList.filter { displayable in
        let ecData = innerStore.getECData(displayable)
        return ecData.seriesIndex == seriesIndex && ecData.dataIndex == dataIndex
            && displayable.states["emphasis"] != nil
    })
    var seenCandidates = Set<ObjectIdentifier>()
    candidates = candidates.filter { seenCandidates.insert(ObjectIdentifier($0)).inserted }
    var resolved: (Displayable, [Double])?
    for candidate in candidates {
        if let point = deterministicHoverPoint(candidate, accepting: { point in
            point[0] >= 0 && point[0] <= ec.getWidth()
                && point[1] >= 0 && point[1] <= ec.getHeight()
                && view.zr.handler.findHover(point[0], point[1]).target === candidate
        }) {
            resolved = (candidate, point)
            break
        }
    }
    if resolved == nil {
        let requestedIndex = Int(dataIndex)
        for path in displayList.compactMap({ $0 as? LargeSymbolPath }) {
            guard innerStore.getECData(path).seriesIndex == seriesIndex,
                  let shape = path.shape as? LargeSymbolPathShape else { continue }
            let startIndex = path.startIndex ?? 0
            let localIndex = requestedIndex - startIndex
            guard localIndex >= 0, localIndex * 2 + 1 < shape.points.count else { continue }
            let localX = shape.points[localIndex * 2]
            let localY = shape.points[localIndex * 2 + 1]
            guard localX.isFinite, localY.isFinite else { continue }
            let point = path.transformCoordToGlobal(localX, localY)
            guard point[0] >= 0, point[0] <= ec.getWidth(),
                  point[1] >= 0, point[1] <= ec.getHeight() else { continue }
            let hovered = view.zr.handler.findHover(point[0], point[1])
            guard hovered.target === path,
                  path.hoverDataIdx + startIndex == requestedIndex else { continue }
            resolved = (path, point)
            break
        }
    }
    return resolved
}

func injectDeterministicHover(
    _ action: [String: Any], ec: ECharts, view: EChartsView
) -> Bool {
    let seriesIndex = (action["seriesIndex"] as? NSNumber)?.doubleValue ?? 0
    if ProcessInfo.processInfo.environment["ECHARTS_HOVER_TRACE"] == "1" {
        if let series = ec.getModel()?.getSeriesByIndex(seriesIndex) {
            print("HOVER_TRACE model animation=\(String(describing: series.getShallow("animation"))) " +
                  "enabled=\(String(describing: series.isAnimationEnabled())) " +
                  "stateDuration=\(String(describing: series.getModel("stateAnimation").get("duration")))")
        }
    }
    guard let (element, point) = resolveDeterministicDataHit(action, ec: ec, view: view) else {
        return false
    }
    if ProcessInfo.processInfo.environment["ECHARTS_HOVER_TRACE"] == "1" {
        let hovered = view.zr.handler.findHover(point[0], point[1])
        print("HOVER_TRACE before point=\(point) targetIsData=\(hovered.target === element) " +
              "transition=\(element.stateTransition?.duration ?? -1) states=\(element.currentStates)")
    }
    view._injectPointerForTest(type: "mousemove", zrX: point[0], zrY: point[1])
    if ProcessInfo.processInfo.environment["ECHARTS_HOVER_TRACE"] == "1" {
        print("HOVER_TRACE after states=\(element.currentStates) animators=\(element.animators.count)")
    }
    return true
}

/// Click a data element through the same live Handler path as the gallery host. The target is
/// re-resolved from the current series data before every call, so an earlier drill-down/re-render
/// cannot leave the visual scenario clicking a stale coordinate.
func injectDeterministicDataClick(
    _ action: [String: Any], ec: ECharts, view: EChartsView, movePointer: Bool
) -> [Double]? {
    guard let (_, point) = resolveDeterministicDataHit(action, ec: ec, view: view) else {
        return nil
    }
    if movePointer {
        view._injectPointerForTest(type: "mousemove", zrX: point[0], zrY: point[1])
    }
    view._injectPointerForTest(type: "mousedown", zrX: point[0], zrY: point[1])
    view._injectPointerForTest(type: "mouseup", zrX: point[0], zrY: point[1])
    view._injectPointerForTest(type: "click", zrX: point[0], zrY: point[1])
    return point
}

/// Click a toolbox feature through its rendered icon. `setTooltipConfig` stamps the stable feature
/// name (for example `restore`) on the live Path, avoiding locale-dependent title matching.
func injectDeterministicToolboxClick(
    featureName: String, view: EChartsView, movePointer: Bool
) -> [Double]? {
    let candidates = view.zr.storage.getDisplayList(true).filter { displayable in
        innerStore.getECData(displayable).tooltipConfig?.name == featureName
    }
    for candidate in candidates {
        guard let point = deterministicHoverPoint(candidate, accepting: { point in
            view.zr.handler.findHover(point[0], point[1]).target === candidate
        }) else { continue }
        if movePointer {
            view._injectPointerForTest(type: "mousemove", zrX: point[0], zrY: point[1])
        }
        view._injectPointerForTest(type: "mousedown", zrX: point[0], zrY: point[1])
        view._injectPointerForTest(type: "mouseup", zrX: point[0], zrY: point[1])
        view._injectPointerForTest(type: "click", zrX: point[0], zrY: point[1])
        return point
    }
    return nil
}

/// Opt-in structural trace for debugging a visual entrance mismatch. Kept behind an environment
/// variable so the normal all-demo oracle remains quiet while a failing frame can expose whether an
/// element owns an enter clip and what transform the deterministic sampler actually applied.
private func traceEntranceAnimationElements(_ root: Element, at time: Int) {
    guard ProcessInfo.processInfo.environment["ECHARTS_ENTRANCE_TRACE"] == "1" else { return }
    var seen = Set<ObjectIdentifier>()
    func visit(_ element: Element?, _ depth: Int) {
        guard let element else { return }
        guard seen.insert(ObjectIdentifier(element)).inserted else { return }
        if !element.animators.isEmpty || element.scaleX != 1 || element.scaleY != 1 {
            let scopes = element.animators.map { $0.scope ?? "-" }.joined(separator: ",")
            print(
                "ENTRANCE_TRACE\tt=\(time)\tdepth=\(depth)\ttype=\(String(describing: type(of: element)))" +
                "\tname=\(element.name.isEmpty ? "-" : element.name)\tx=\(element.x)\ty=\(element.y)" +
                "\tsx=\(element.scaleX)\tsy=\(element.scaleY)\tanim=\(scopes)"
            )
        }
        visit(element.getClipPath(), depth + 1)
        visit(element.getTextContent(), depth + 1)
        visit(element.getTextGuideLine(), depth + 1)
        if let group = element as? Group {
            for child in group.children() { visit(child, depth + 1) }
        }
    }
    visit(root, 0)
}

@MainActor
func loadWebAndSnapshot(_ demo: EChartsDemo, out: URL) -> Never {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: demo.width, height: demo.height))
    let win = NSWindow(contentRect: wv.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    win.contentView = wv; win.orderFrontRegardless()
    let snapper = WebSnapper(out: out)
    wv.navigationDelegate = snapper
    // Headless PNG: one deterministic frame (animation off, the example's setInterval neutered) —
    // otherwise a repeating example would race the snapshot and the same demo would diff against
    // itself between runs.
    guard let page = echartsHTMLPage(demo, snapshot: true) else {
        FileHandle.standardError.write(Data("could not build html (missing echarts dist?)\n".utf8)); exit(1)
    }
    wv.loadHTMLString(page, baseURL: nil)
    app.run()
    fatalError("unreachable — WebSnapper exits")
}

// ---------------------------------------------------------------------------
// CLI dispatch
// ---------------------------------------------------------------------------

@MainActor
func runCLI() -> Bool {
    // Real Core Text metrics for `platform.measureText` before ANY chart is built. The headless
    // commands (scene-graph oracle, --render*) never construct a CALayerPainter, which is what would
    // otherwise install the native platform backing — without this they would size every label from
    // zrender's no-canvas ASCII width table while the painter draws with CTLine.
    installNativeTextMeasure()

    let args = Array(CommandLine.arguments.dropFirst())
    guard let cmd = args.first else { return false }   // no args → GUI

    switch cmd {
    case "--list":
        for d in EChartsDemoRegistry.everything {
            let tab = d.collection == .official ? "official" : "port"
            print("\(d.name)\t[\(tab)/\(d.category)]\tnative:\(d.nativeSupported ? "yes" : "N/A")\t\(d.summary)")
        }
        return true

    case "--render":
        guard args.count >= 3, let demo = EChartsDemoRegistry.byName(args[1]) else {
            FileHandle.standardError.write(Data("usage: --render <name> <out.png>\n".utf8)); exit(2)
        }
        let ok = writeNativePNG(demo, to: URL(fileURLWithPath: args[2]))
        print(ok ? "wrote \(args[2])" : "FAILED to native-render \(demo.name)")
        exit(ok ? 0 : 1)

    case "--port-stubs":
        // --port-stubs <name> : which knowingly-unimplemented behaviour does THIS demo silently
        // depend on? Renders the demo and prints one `STUB\t<id>\t<consequence>` line per hit.
        //
        // This is the forcing function the port lacked. A stub that CRASHES is harmless — it gets
        // fixed on day one. A stub that silently degrades (an axis quietly becoming a value axis)
        // survives for a year, because everything downstream still looks plausible. Now it is a list.
        //
        // One demo per process, driven by scripts/port-stubs.sh: some demos still hit a `fatalError`,
        // and an in-process sweep would be killed by the first one — losing the whole report to the
        // very kind of gap it exists to find.
        guard args.count >= 2, let demo = EChartsDemoRegistry.byName(args[1]), demo.nativeSupported else {
            FileHandle.standardError.write(Data("usage: --port-stubs <name>   (see scripts/port-stubs.sh)\n".utf8))
            exit(2)
        }
        PortStub.reset()
        _ = renderNativeGroup(demo)
        for (gap, count) in PortStub.hits.sorted(by: { $0.key.id < $1.key.id }) {
            print("STUB\t\(gap.id)\t\(count)\t\(gap.consequence)")
        }
        exit(0)

    case "--render-all":
        guard args.count >= 2 else {
            FileHandle.standardError.write(Data("usage: --render-all <dir>\n".utf8)); exit(2)
        }
        let dir = URL(fileURLWithPath: args[1], isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var failed = 0
        for d in EChartsDemoRegistry.everything where d.nativeSupported {
            let url = dir.appendingPathComponent(d.name + ".png")
            if writeNativePNG(d, to: url) { print("  \(d.name).png") }
            else { print("  \(d.name)  FAILED"); failed += 1 }
        }
        print("native-rendered demos to \(dir.path) (\(failed) failed)")
        exit(failed == 0 ? 0 : 1)

    case "--list-driven":
        // Dynamic examples whose behaviour includes a native drive timeline. Keep discovery in the
        // registry so validation never silently misses a newly-added timer-driven case.
        for demo in EChartsDemoRegistry.everything where demo.nativeSupported && demo.drive != nil {
            print(demo.name)
        }
        exit(0)

    case "--web-snapshot":
        guard args.count >= 3, let demo = EChartsDemoRegistry.byName(args[1]) else {
            FileHandle.standardError.write(Data("usage: --web-snapshot <name> <out.png>\n".utf8)); exit(2)
        }
        loadWebAndSnapshot(demo, out: URL(fileURLWithPath: args[2]))

    case "--interaction-native":
        // --interaction-native <scenario.json> <frames-dir> <resolved.json>
        // Replays a sequence through the real headless Handler and captures named visual states.
        guard args.count >= 4 else {
            FileHandle.standardError.write(
                Data("usage: --interaction-native <scenario.json> <frames-dir> <resolved.json>\n".utf8)
            )
            exit(2)
        }
        exit(runNativeInteractionVisual(
            scenarioPath: args[1], outputDirectory: args[2], resolvedPath: args[3]
        ) ? 0 : 1)

    case "--interaction-generate-line":
        guard args.count >= 2 else {
            FileHandle.standardError.write(
                Data("usage: --interaction-generate-line <scenario-dir>\n".utf8)
            )
            exit(2)
        }
        exit(writeLineInteractionScenarios(outputDirectory: args[1]) ? 0 : 1)

    case "--interaction-generate-bar":
        guard args.count >= 2 else {
            FileHandle.standardError.write(
                Data("usage: --interaction-generate-bar <scenario-dir>\n".utf8)
            )
            exit(2)
        }
        exit(writeBarInteractionScenarios(outputDirectory: args[1]) ? 0 : 1)

    case "--interaction-generate-pie":
        guard args.count >= 2 else {
            FileHandle.standardError.write(
                Data("usage: --interaction-generate-pie <scenario-dir>\n".utf8)
            )
            exit(2)
        }
        exit(writePieInteractionScenarios(outputDirectory: args[1]) ? 0 : 1)

    case "--interaction-generate-scatter":
        guard args.count >= 2 else {
            FileHandle.standardError.write(
                Data("usage: --interaction-generate-scatter <scenario-dir>\n".utf8)
            )
            exit(2)
        }
        exit(writeScatterInteractionScenarios(outputDirectory: args[1]) ? 0 : 1)

    case "--interaction-generate-map":
        guard args.count >= 2 else {
            FileHandle.standardError.write(
                Data("usage: --interaction-generate-map <scenario-dir>\n".utf8)
            )
            exit(2)
        }
        exit(writeMapInteractionScenarios(outputDirectory: args[1]) ? 0 : 1)

    case "--interaction-generate-category":
        guard args.count >= 3 else {
            FileHandle.standardError.write(
                Data("usage: --interaction-generate-category <category> <scenario-dir>\n".utf8)
            )
            exit(2)
        }
        exit(writeCategoryInteractionScenarios(
            category: args[1], outputDirectory: args[2]
        ) ? 0 : 1)

    case "--interaction-web":
        // Web oracle for --interaction-native. It resolves the current LegendView after every
        // rebuild and sends the same pointer sequence through zrender's Handler.
        guard args.count >= 4 else {
            FileHandle.standardError.write(
                Data("usage: --interaction-web <scenario.json> <frames-dir> <resolved.json>\n".utf8)
            )
            exit(2)
        }
        guard startWebInteractionVisual(
            scenarioPath: args[1], outputDirectory: args[2], resolvedPath: args[3]
        ) else { exit(1) }
        return true

    case "--interaction-contact":
        guard args.count >= 3 else {
            FileHandle.standardError.write(
                Data("usage: --interaction-contact <scenario.json> <case-root>\n".utf8)
            )
            exit(2)
        }
        exit(writeInteractionVisualContact(
            scenarioPath: args[1], caseRootPath: args[2]
        ) ? 0 : 1)

    case "--scene-native":
        // --scene-native <demo> <out.json> : structural (scene-graph) dump of the native port's
        //   z-sorted display list. Pair with --scene-web + scripts/scene-diff.py. See SceneDump.swift.
        guard args.count >= 3, let demo = EChartsDemoRegistry.byName(args[1]), demo.nativeSupported else {
            FileHandle.standardError.write(Data("usage: --scene-native <name> <out.json>\n".utf8)); exit(2)
        }
        // Optional 3rd arg: a dispatchAction payload as JSON, applied after the initial render.
        let nAction: [String: Any]? = args.count >= 4
            ? (try? JSONSerialization.jsonObject(with: Data(args[3].utf8))) as? [String: Any] : nil
        guard let json = sceneDumpNative(demo, action: nAction) else {
            FileHandle.standardError.write(Data("scene dump failed\n".utf8)); exit(1)
        }
        try? json.write(to: URL(fileURLWithPath: args[2]), atomically: true, encoding: .utf8)
        print("wrote \(args[2]) (\(json.count) bytes)")
        exit(0)

    case "--scene-web":
        // --scene-web <demo> <out.json> : the echarts.js oracle for --scene-native, dumped from the
        //   SAME page --compare uses (real echarts 6.1.0 in WKWebView), animation forced off.
        guard args.count >= 3, let demo = EChartsDemoRegistry.byName(args[1]) else {
            FileHandle.standardError.write(Data("usage: --scene-web <name> <out.json>\n".utf8)); exit(2)
        }
        let sapp = NSApplication.shared
        sapp.setActivationPolicy(.accessory)
        let swv = WKWebView(frame: CGRect(x: 0, y: 0, width: demo.width, height: demo.height))
        let swin = NSWindow(contentRect: swv.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        swin.contentView = swv; swin.orderFrontRegardless()
        // --scene-web <demo> <out.json> [actionJSON | probe.js]
        //   3rd arg starting with '{' is a dispatchAction payload (mirrors --scene-native);
        //   otherwise it is a path to a script that REPLACES the scene dump, for probing the
        //   reference implementation directly.
        var probeJS = sceneDumpJS
        var wAction: String? = nil
        if args.count >= 4 {
            if args[3].hasPrefix("{") { wAction = args[3] }
            else { probeJS = (try? String(contentsOfFile: args[3], encoding: .utf8)) ?? sceneDumpJS }
        }
        let dumper = WebSceneDumper(out: URL(fileURLWithPath: args[2]), js: probeJS, actionJSON: wAction)
        swv.navigationDelegate = dumper
        guard let spage = echartsHTMLPage(demo, snapshot: true) else {
            FileHandle.standardError.write(Data("could not build html\n".utf8)); exit(1)
        }
        swv.loadHTMLString(spage, baseURL: nil)
        sapp.run()
        return true

    case "--scene-manifest":
        // --scene-manifest <out.json> [maxActionsPerDemo] : derive the user-reachable actions for every
        //   demo (v1: legend toggles, read off the real ported LegendModel) and write them to a manifest
        //   that BOTH sweeps consume — so the two implementations always get byte-identical payloads and
        //   any divergence is necessarily in the response, not the stimulus.
        guard args.count >= 2 else {
            FileHandle.standardError.write(Data("usage: --scene-manifest <out.json> [maxPerDemo]\n".utf8)); exit(2)
        }
        let maxPer = args.count >= 3 ? (Int(args[2]) ?? 2) : 2
        var manifest: [String: [[String: Any]]] = [:]
        var withActions = 0
        for d in EChartsDemoRegistry.everything where d.nativeSupported {
            let acts = deriveLegendActions(d, max: maxPer)
            manifest[d.name] = acts
            if !acts.isEmpty { withActions += 1 }
        }
        let mdata = try! JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys, .prettyPrinted])
        try? mdata.write(to: URL(fileURLWithPath: args[1]))
        let total = manifest.values.reduce(0) { $0 + $1.count }
        print("manifest: \(manifest.count) demos, \(withActions) with legend actions, \(total) actions total")
        exit(0)

    case "--scene-sweep-native":
        // --scene-sweep-native <manifest.json> <outdir> : base + per-action structural dumps, in-process.
        guard args.count >= 3,
              let mdata = FileManager.default.contents(atPath: args[1]),
              let man = (try? JSONSerialization.jsonObject(with: mdata)) as? [String: [[String: Any]]] else {
            FileHandle.standardError.write(Data("usage: --scene-sweep-native <manifest.json> <outdir>\n".utf8)); exit(2)
        }
        let ndir = URL(fileURLWithPath: args[2], isDirectory: true)
        try? FileManager.default.createDirectory(at: ndir, withIntermediateDirectories: true)
        // RESUMABLE, because a slot can hard-crash the process (fatalError / index-out-of-range are not
        // catchable in Swift). Each finished slot writes either its dump or a `.skip` marker, so an outer
        // driver (scripts/scene-sweep.sh) can re-invoke past a crash and the crashing slot is identifiable
        // as the one slot with neither file. A crash IS a finding — do not paper over it.
        var nOK = 0, nSkip = 0
        for d in EChartsDemoRegistry.everything where d.nativeSupported {
            let acts = man[d.name] ?? []
            for slot in 0...acts.count {
                let out = ndir.appendingPathComponent(sweepFileName(d.name, slot: slot, side: "native"))
                let skip = ndir.appendingPathComponent(sweepFileName(d.name, slot: slot, side: "native") + ".skip")
                if FileManager.default.fileExists(atPath: out.path)
                    || FileManager.default.fileExists(atPath: skip.path) { nSkip += 1; continue }
                // Claim the slot BEFORE running it: if this slot crashes the process, the marker is
                // already on disk and the next invocation moves past it instead of looping forever.
                try? "in-progress".write(to: skip, atomically: true, encoding: .utf8)
                FileHandle.standardError.write(Data("RUN \(d.name)##\(slot)\n".utf8))
                if let json = sceneDumpNative(d, action: slot == 0 ? nil : acts[slot - 1]) {
                    try? json.write(to: out, atomically: true, encoding: .utf8)
                    try? FileManager.default.removeItem(at: skip)
                    nOK += 1
                }
            }
        }
        print("sweep-native pass done: \(nOK) new, \(nSkip) already present -> \(ndir.path)")
        exit(0)

    case "--anim-probe":
        // --anim-probe <manifest.json> <out.tsv> : per demo, does an update that demonstrably changes
        //   the scene actually produce animators? Resumable/crash-tolerant like --scene-sweep-native.
        guard args.count >= 3 else {
            FileHandle.standardError.write(Data("usage: --anim-probe <manifest.json> <out.tsv>\n".utf8)); exit(2)
        }
        let apMan = FileManager.default.contents(atPath: args[1])
            .flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: [[String: Any]]] } ?? [:]
        let apOut = URL(fileURLWithPath: args[2])
        let apClaim = URL(fileURLWithPath: args[2] + ".inprogress")
        var done = Set<String>()
        if let existing = try? String(contentsOf: apOut, encoding: .utf8) {
            for line in existing.split(separator: "\n").dropFirst() {
                if let name = line.split(separator: "\t").first { done.insert(String(name)) }
            }
        } else {
            try? "demo\tsceneChanged\tinitialTotal\tinitialAnimated\tupdateTotal\tupdateAnimated\n"
                .write(to: apOut, atomically: true, encoding: .utf8)
        }
        let apHandle = try! FileHandle(forWritingTo: apOut)
        apHandle.seekToEndOfFile()
        // A hard crash cannot be caught in-process. On resume, turn the prior claim into one durable
        // CRASHED row, then continue with the following demo instead of looping forever.
        if let claimed = try? String(contentsOf: apClaim, encoding: .utf8), !claimed.isEmpty,
           !done.contains(claimed) {
            apHandle.write(Data("\(claimed)\tCRASHED\t0\t0\t0\t0\n".utf8))
            done.insert(claimed)
        }
        try? FileManager.default.removeItem(at: apClaim)
        for d in EChartsDemoRegistry.everything where d.nativeSupported {
            if done.contains(d.name) { continue }
            FileHandle.standardError.write(Data("RUN \(d.name)\n".utf8))
            try? d.name.write(to: apClaim, atomically: true, encoding: .utf8)
            let r = animProbe(d, action: apMan[d.name]?.first)
            apHandle.write(Data("\(d.name)\t\(r.sceneChanged)\t\(r.initialTotal)\t\(r.initialAnimated)\t\(r.total)\t\(r.animated)\n".utf8))
            try? apHandle.synchronize()
            try? FileManager.default.removeItem(at: apClaim)
        }
        try? apHandle.close()
        print("anim-probe pass done -> \(apOut.path)")
        exit(0)

    case "--anim-probe-web":
        // --anim-probe-web <manifest.json> <out.tsv> [onlyList.txt] : the echarts.js side of --anim-probe.
        //   Without it a native zero is not a verdict — upstream removes a fully-hidden series' view
        //   group synchronously too (echarts.ts:1756), so zero can be the faithful answer.
        guard args.count >= 3 else {
            FileHandle.standardError.write(Data("usage: --anim-probe-web <manifest.json> <out.tsv> [only.txt]\n".utf8)); exit(2)
        }
        let awMan = FileManager.default.contents(atPath: args[1])
            .flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: [[String: Any]]] } ?? [:]
        var only: Set<String>? = nil
        if args.count >= 4, let txt = try? String(contentsOfFile: args[3], encoding: .utf8) {
            only = Set(txt.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty })
        }
        var awJobs: [SweepJob] = []
        for d in EChartsDemoRegistry.everything where d.nativeSupported {
            if let only = only, !only.contains(d.name) { continue }
            let act = awMan[d.name]?.first
            let aJSON = act.flatMap { try? JSONSerialization.data(withJSONObject: $0) }
                .flatMap { String(data: $0, encoding: .utf8) }
            awJobs.append(SweepJob(demo: d, actionJSON: aJSON, out: URL(fileURLWithPath: "/dev/null"), label: d.name))
        }
        print("anim-probe-web: \(awJobs.count) page loads")
        let awApp = NSApplication.shared
        awApp.setActivationPolicy(.accessory)
        let awWV = WKWebView(frame: CGRect(x: 0, y: 0, width: 640, height: 420))
        let awWin = NSWindow(contentRect: awWV.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        awWin.contentView = awWV; awWin.orderFrontRegardless()
        let awProber = WebAnimProber(jobs: awJobs, wv: awWV, out: URL(fileURLWithPath: args[2]))
        awWV.navigationDelegate = awProber
        awProber.start()
        awApp.run()
        return true

    case "--anim-probe-one":
        // --anim-probe-one <demo> [actionJSON] : the verbose single-demo form of --anim-probe, for
        //   diagnosing WHY a demo reports zero animators (which element classes exist, which tween).
        guard args.count >= 2, let demo = EChartsDemoRegistry.byName(args[1]), demo.nativeSupported else {
            FileHandle.standardError.write(Data("usage: --anim-probe-one <name> [actionJSON]\n".utf8)); exit(2)
        }
        let a1Action: [String: Any]? = args.count >= 3
            ? (try? JSONSerialization.jsonObject(with: Data(args[2].utf8))) as? [String: Any] : nil
        animProbeVerbose(demo, action: a1Action)
        exit(0)

    case "--scene-sweep-web":
        // --scene-sweep-web <manifest.json> <outdir> : the echarts.js side of the same sweep, one page
        //   load per (demo, action), sequentially in one process.
        guard args.count >= 3,
              let wdata = FileManager.default.contents(atPath: args[1]),
              let wman = (try? JSONSerialization.jsonObject(with: wdata)) as? [String: [[String: Any]]] else {
            FileHandle.standardError.write(Data("usage: --scene-sweep-web <manifest.json> <outdir>\n".utf8)); exit(2)
        }
        let wdir = URL(fileURLWithPath: args[2], isDirectory: true)
        try? FileManager.default.createDirectory(at: wdir, withIntermediateDirectories: true)
        var jobs: [SweepJob] = []
        for d in EChartsDemoRegistry.everything where d.nativeSupported {
            let acts = wman[d.name] ?? []
            for slot in 0...acts.count {
                let aJSON: String? = slot == 0 ? nil : (try? JSONSerialization.data(withJSONObject: acts[slot - 1]))
                    .flatMap { String(data: $0, encoding: .utf8) }
                jobs.append(SweepJob(demo: d, actionJSON: aJSON,
                                     out: wdir.appendingPathComponent(sweepFileName(d.name, slot: slot, side: "web")),
                                     label: "\(d.name)##\(slot)"))
            }
        }
        print("sweep-web: \(jobs.count) page loads")
        let wapp2 = NSApplication.shared
        wapp2.setActivationPolicy(.accessory)
        let sweepWV = WKWebView(frame: CGRect(x: 0, y: 0, width: 640, height: 420))
        let sweepWin = NSWindow(contentRect: sweepWV.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        sweepWin.contentView = sweepWV; sweepWin.orderFrontRegardless()
        let sweeper = WebSweeper(jobs: jobs, wv: sweepWV)
        sweepWV.navigationDelegate = sweeper
        sweeper.start()
        wapp2.run()
        return true

    case "--render-rasterizer":
        // --render-rasterizer <name> <out.png> [timeMs] [actionJSON] : deterministically sample the
        // demo's entrance animation (or an action animation after settling entrance), then
        // synchronously render the resulting display list through the
        // REAL RasterizerLayer Metal pipeline. The drawable is blitted into the layer's feedback
        // texture on that first frame and read back to the PNG. With no timeMs, sample a completed
        // entrance frame; an explicit timeMs preserves an exact intermediate animation phase.
        guard args.count >= 3, let demo = EChartsDemoRegistry.byName(args[1]),
              demo.nativeSupported else {
            FileHandle.standardError.write(
                Data("usage: --render-rasterizer <name> <out.png> [timeMs] [actionJSON]\n".utf8)
            )
            exit(2)
        }
        var requestedTime: Double?
        if args.count >= 4 {
            guard let parsed = Double(args[3]), parsed.isFinite, parsed >= 0 else {
                FileHandle.standardError.write(Data("timeMs must be a finite non-negative number\n".utf8))
                exit(2)
            }
            requestedTime = parsed
        }
        let sampleTime = requestedTime ?? 1_000_000_000
        let action = args.count >= 5
            ? (try? JSONSerialization.jsonObject(with: Data(args[4].utf8))) as? [String: Any]
            : nil

        // Do not use renderNativeGroup: that static oracle forces option.animation=false. A bare
        // ECharts instance has no display-link host, so its freshly-created entrance clips remain
        // pristine until this command advances every clip to the requested logical timestamp. Hover
        // actions need an EChartsView because they deliberately enter through the real Handler.
        let view = action == nil ? nil : EChartsView(width: demo.width, height: demo.height)
        let ec = view?.ec ?? ECharts(width: demo.width, height: demo.height)
        if let view { view.setOption(demo.option) }
        else { ec.setOption(demo.option) }
        let group = ec.getRoot()
        var clips = entranceAnimationClips(group)
        if let action {
            for clip in clips {
                clip.resetForDeterministicSampling()
                if clip.sampleForDeterministicRendering(at: 1_000_000_000) { clip.ondestroy() }
            }
            if action["type"] as? String == "__hoverData", let view {
                guard injectDeterministicHover(action, ec: ec, view: view) else {
                    FileHandle.standardError.write(Data("__hoverData could not resolve a hittable data element\n".utf8))
                    exit(1)
                }
            }
            else if let type = action["type"] as? String {
                var payload = Payload(type: type)
                for (key, value) in action where key != "type" { payload.other[key] = value }
                ec.dispatchAction(payload)
            }
            clips = entranceAnimationClips(group)
        }
        for clip in clips {
            clip.resetForDeterministicSampling()
            if clip.sampleForDeterministicRendering(at: sampleTime) { clip.ondestroy() }
        }
        renderAxisPointerHandlesIntoRoot(ec, group)

        let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        let painter = RasterizerPainter(size: CGSize(width: demo.width, height: demo.height),
                                        dpr: 2, backgroundColor: white)
        painter.refresh(flattenDisplayList(group))
        guard let img = painter.renderFirstMetalFrame(),
              let png = NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:]),
              (try? png.write(to: URL(fileURLWithPath: args[2]))) != nil else {
            print("FAILED to render via RasterizerLayer Metal"); exit(1)
        }
        let phase = requestedTime.map { String($0) } ?? "stable"
        print("wrote \(args[2]) (Metal, timeMs=\(phase), clips=\(clips.count))")
        exit(0)

    case "--compare":
        // --compare <name> <dir> : native PNG now, then web PNG (the web path exits the process).
        guard args.count >= 3, let demo = EChartsDemoRegistry.byName(args[1]) else {
            FileHandle.standardError.write(Data("usage: --compare <name> <dir>\n".utf8)); exit(2)
        }
        let dir = URL(fileURLWithPath: args[2], isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if demo.nativeSupported {
            let n = dir.appendingPathComponent(demo.name + ".native.png")
            print(writeNativePNG(demo, to: n) ? "wrote \(n.path)" : "native FAILED")
        } else {
            print("native N/A for \(demo.name)")
        }
        loadWebAndSnapshot(demo, out: dir.appendingPathComponent(demo.name + ".web.png"))

    case "--entrance-native":
        // --entrance-native <demo> <outdir> [offsetsMsCSV] [actionJSON]
        // Deterministic visual frames for the INITIAL setOption animation. Unlike --anim-native this
        // does not use a wall clock: every clip is advanced to the same exact logical timestamps used
        // by --entrance-web, eliminating process/WKWebView startup skew from the comparison.
        guard args.count >= 3, let demo = EChartsDemoRegistry.byName(args[1]), demo.nativeSupported else {
            FileHandle.standardError.write(Data("usage: --entrance-native <name> <outdir> [offsetsMsCSV] [actionJSON]\n".utf8))
            exit(2)
        }
        let dir = URL(fileURLWithPath: args[2], isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let parsed = args.count >= 4 ? args[3].split(separator: ",").compactMap { Int($0) } : []
        let offsets = Array(Set(parsed.isEmpty ? [0, 250, 500, 800, 1200, 1600] : parsed)).sorted()
        let action = args.count >= 5
            ? (try? JSONSerialization.jsonObject(with: Data(args[4].utf8))) as? [String: Any]
            : nil
        let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        for time in offsets {
            // Fresh chart per timestamp for the same reason as the Web oracle: keyframes are
            // independent samples, not mutations chained through prior completion callbacks.
            let view = action == nil ? nil : EChartsView(width: demo.width, height: demo.height)
            let ec = view?.ec ?? ECharts(width: demo.width, height: demo.height)
            if let view { view.setOption(demo.option) }
            else { ec.setOption(demo.option) }
            let root = ec.getRoot()
            if let action = action {
                for clip in entranceAnimationClips(root) {
                    clip.resetForDeterministicSampling()
                    if clip.sampleForDeterministicRendering(at: 1_000_000_000) { clip.ondestroy() }
                }
                if action["type"] as? String == "__setOption",
                   let option = action["option"] as? [String: Any] {
                    ec.setOption(option, notMerge: false)
                }
                else if action["type"] as? String == "__hoverData", let view {
                    if !injectDeterministicHover(action, ec: ec, view: view) {
                        FileHandle.standardError.write(Data("__hoverData could not resolve a hittable data element\n".utf8))
                        exit(1)
                    }
                }
                else if action["type"] as? String == "__legendClick",
                        let name = action["name"] as? String {
                    for type in ["downplay", "legendToggleSelect", "highlight"] {
                        var payload = Payload(type: type)
                        payload.other["name"] = name
                        ec.dispatchAction(payload)
                    }
                }
                else if let type = action["type"] as? String {
                    var payload = Payload(type: type)
                    for (key, value) in action where key != "type" { payload.other[key] = value }
                    ec.dispatchAction(payload)
                }
            }
            let clips = entranceAnimationClips(root)
            for clip in clips {
                clip.resetForDeterministicSampling()
                if clip.sampleForDeterministicRendering(at: Double(time)) {
                    clip.ondestroy()
                }
            }
            traceEntranceAnimationElements(root, at: time)
            guard let image = renderToImage(group: root,
                                            size: CGSize(width: demo.width, height: demo.height),
                                            dpr: 2, backgroundColor: white),
                  let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                FileHandle.standardError.write(Data("entrance native t\(time) render failed\n".utf8))
                exit(1)
            }
            let out = dir.appendingPathComponent(String(format: "%@.t%04d.native.png", demo.name, time))
            do { try png.write(to: out); print("wrote \(out.lastPathComponent)") }
            catch { FileHandle.standardError.write(Data("write failed: \(error)\n".utf8)); exit(1) }
        }
        exit(0)

    case "--entrance-web":
        // --entrance-web <demo> <outdir> [offsetsMsCSV] [actionJSON] — real echarts.js, with its RAF loop frozen
        // before setOption and its entrance clips explicitly advanced to the requested logical times.
        guard args.count >= 3, let demo = EChartsDemoRegistry.byName(args[1]) else {
            FileHandle.standardError.write(Data("usage: --entrance-web <name> <outdir> [offsetsMsCSV] [actionJSON]\n".utf8))
            exit(2)
        }
        let dir = URL(fileURLWithPath: args[2], isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let parsed = args.count >= 4 ? args[3].split(separator: ",").compactMap { Int($0) } : []
        let offsets = Array(Set(parsed.isEmpty ? [0, 250, 500, 800, 1200, 1600] : parsed)).sorted()
        let actionJSON = args.count >= 5 ? args[4] : nil
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: demo.width, height: demo.height))
        let window = NSWindow(contentRect: webView.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = webView
        window.orderFrontRegardless()
        guard let page = echartsHTMLPage(demo, snapshot: false, freezeEntranceAnimation: true) else {
            FileHandle.standardError.write(Data("could not build entrance html\n".utf8))
            exit(1)
        }
        let snapper = WebEntranceSnapper(
            demo: demo, dir: dir, offsets: offsets, page: page, actionJSON: actionJSON
        )
        webView.navigationDelegate = snapper
        webView.loadHTMLString(page, baseURL: nil)
        app.run()
        return true

    case "--anim-native":
        // --anim-native <demo> <outdir> [offsetsMsCSV]
        //   The time-aware analog of --render: drive the demo WITH animation on (+ its `drive`
        //   timeline) and snapshot the live scene at wall-clock offsets, so an enter animation or an
        //   update transition — invisible to the single static frame — is captured as a frame series.
        //   Reuses EChartsHostView (EChartsView + CALayerPainter + AnimationLoop + drive timers).
        guard args.count >= 3, let demo = EChartsDemoRegistry.byName(args[1]), demo.nativeSupported else {
            FileHandle.standardError.write(Data("usage: --anim-native <name> <outdir> [offsetsMsCSV]\n".utf8)); exit(2)
        }
        let dir = URL(fileURLWithPath: args[2], isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let offsets: [Int] = (args.count >= 4 ? args[3].split(separator: ",").compactMap { Int($0) } : [])
            .isEmpty ? [0, 80, 200, 400, 700, 1100, 1600, 2100, 2400, 2800, 3200, 3600]
                     : args[3].split(separator: ",").compactMap { Int($0) }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let host = EChartsHostView(frame: CGRect(x: 0, y: 0, width: demo.width, height: demo.height))
        host.setOption(demo.liveOption ?? demo.option) // animation ON (do NOT force it off)
        demo.drive?(host)                    // replay the example's setInterval/setOption timeline
        let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        let sorted = offsets.sorted()
        for (i, t) in sorted.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(t) / 1000.0) {
                let img = renderToImage(group: host.echartsView.ec.getRoot(),
                                        size: CGSize(width: demo.width, height: demo.height),
                                        dpr: 2, backgroundColor: white)
                if let img = img,
                   let png = NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:]) {
                    let out = dir.appendingPathComponent(String(format: "%@.t%04d.native.png", demo.name, t))
                    try? png.write(to: out)
                    print("wrote \(out.lastPathComponent)")
                } else {
                    print("t\(t) native render FAILED")
                }
                if i == sorted.count - 1 { exit(0) }
            }
        }
        app.run()
        return true   // unreachable: exit(0) fires from the last snapshot closure

    case "--anim-web":
        // --anim-web <demo> <outdir> [offsetsMsCSV] : the echarts.js oracle for --anim-native — the
        //   live-timeline page (animation ON, setInterval running) sampled at the same wall-clock offsets.
        guard args.count >= 3, let demo = EChartsDemoRegistry.byName(args[1]) else {
            FileHandle.standardError.write(Data("usage: --anim-web <name> <outdir> [offsetsMsCSV]\n".utf8)); exit(2)
        }
        let dir = URL(fileURLWithPath: args[2], isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let woffsets: [Int] = (args.count >= 4 ? args[3].split(separator: ",").compactMap { Int($0) } : [])
            .isEmpty ? [0, 80, 200, 400, 700, 1100, 1600, 2100, 2400, 2800, 3200, 3600]
                     : args[3].split(separator: ",").compactMap { Int($0) }
        let wapp = NSApplication.shared
        wapp.setActivationPolicy(.accessory)
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: demo.width, height: demo.height))
        let win = NSWindow(contentRect: wv.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        win.contentView = wv; win.orderFrontRegardless()
        let msnap = WebMultiSnapper(demo: demo, dir: dir, offsets: woffsets.sorted())
        wv.navigationDelegate = msnap
        guard let page = echartsHTMLPage(demo, snapshot: false) else {   // LIVE timeline, animation on
            FileHandle.standardError.write(Data("could not build html\n".utf8)); exit(1)
        }
        wv.loadHTMLString(page, baseURL: nil)
        wapp.run()
        return true

    case "--anim-invariant":
        // --anim-invariant <demo> [offsetsMsCSV] : the reliable animation-bug detector (approach B).
        //   Global pixel-diff (--anim-native vs --anim-web) is dominated by startup-timing skew and
        //   random-data value differences, NOT animation correctness — a real gauge "reset on refresh"
        //   scores ~1 while a correctly-synced morph scores ~27. Instead, sample the SET of scene element
        //   object-identities at each offset and report the overlap between consecutive samples. A view
        //   that TWEENS an update reuses its elements (identity persists → high overlap); a view that
        //   `group.removeAll()`s + rebuilds on every update (the reset bug — new elements replay the enter
        //   animation from the initial state) shows a near-ZERO overlap across the update. Element size and
        //   frame timing are irrelevant — this is a structural signal.
        guard args.count >= 2, let demo = EChartsDemoRegistry.byName(args[1]), demo.nativeSupported else {
            FileHandle.standardError.write(Data("usage: --anim-invariant <name> [offsetsMsCSV]\n".utf8)); exit(2)
        }
        let ioffsets: [Int] = (args.count >= 3 ? args[2].split(separator: ",").compactMap { Int($0) } : [])
            .isEmpty ? [800, 1300, 1900, 2400, 3000, 3500] : args[2].split(separator: ",").compactMap { Int($0) }
        let iapp = NSApplication.shared
        iapp.setActivationPolicy(.accessory)
        let ihost = EChartsHostView(frame: CGRect(x: 0, y: 0, width: demo.width, height: demo.height))
        ihost.setOption(demo.option)
        demo.drive?(ihost)
        let snaps = AnimInvariantSnaps()
        let isorted = ioffsets.sorted()
        for (i, t) in isorted.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(t) / 1000.0) {
                var ids = Set<ObjectIdentifier>()
                var activeAnimators = 0
                var animatorTypes: [String: Int] = [:]
                var animatedExtraSamples: [String] = []
                _ = ihost.echartsView.ec.getRoot().traverse { el in
                    ids.insert(ObjectIdentifier(el))
                    activeAnimators += el.animators.count
                    if !el.animators.isEmpty { animatorTypes[el.type, default: 0] += el.animators.count }
                    if !el.animators.isEmpty, let raw = el.extra?["endRadian"] {
                        let value = (raw as? Double) ?? (raw as? NSNumber)?.doubleValue
                        if let value { animatedExtraSamples.append(String(format: "%@.endRadian=%.3f", el.type, value)) }
                    }
                    return false
                }
                snaps.samples.append((t, ids, activeAnimators))
                let typeSummary = animatorTypes.keys.sorted().map { "\($0):\(animatorTypes[$0]!)" }.joined(separator: ",")
                print("  t\(t) activeAnimators=\(activeAnimators) [\(typeSummary)]")
                if !animatedExtraSamples.isEmpty { print("    " + animatedExtraSamples.joined(separator: " ")) }
                if i == isorted.count - 1 {
                    var minOverlap = 1.0
                    for k in 1..<snaps.samples.count {
                        let a = snaps.samples[k - 1].ids, b = snaps.samples[k].ids
                        let inter = a.intersection(b).count
                        let ratio = a.isEmpty ? 1.0 : Double(inter) / Double(a.count)
                        minOverlap = min(minOverlap, ratio)
                        print(String(format: "  t%d->t%d  overlap=%.2f  (%d/%d kept, %d total@t%d)",
                                     snaps.samples[k-1].time, snaps.samples[k].time, ratio, inter, a.count,
                                     b.count, snaps.samples[k].time))
                    }
                    print(String(format: "MIN_OVERLAP\t%.2f\t%@", minOverlap, demo.name))
                    exit(0)
                }
            }
        }
        iapp.run()
        return true

    case "--anim-disabled-invariant":
        // --anim-disabled-invariant <driven-demo> [offsetsMsCSV]
        // The gallery switch means "disable ECharts interpolation", not "pause the example". Verify
        // that drive timers still change the settled scene while every sample has zero animators.
        guard args.count >= 2, let demo = EChartsDemoRegistry.byName(args[1]),
              demo.nativeSupported, demo.drive != nil else {
            FileHandle.standardError.write(Data("usage: --anim-disabled-invariant <driven-demo> [offsetsMsCSV]\n".utf8)); exit(2)
        }
        let offsets: [Int] = (args.count >= 3 ? args[2].split(separator: ",").compactMap { Int($0) } : [])
            .isEmpty ? [100, 1100, 2100, 3100] : args[2].split(separator: ",").compactMap { Int($0) }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let host = EChartsHostView(frame: CGRect(x: 0, y: 0, width: demo.width, height: demo.height))
        host.animationsEnabled = false
        host.setOption(demo.option)
        demo.drive?(host)
        let sorted = offsets.sorted()
        var priorSignature: String?
        var changed = false
        var failed = false
        for (i, time) in sorted.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(time) / 1000) {
                var active = 0
                _ = host.echartsView.ec.getRoot().traverse { el in
                    active += el.animators.count
                    return false
                }
                let signature = sceneSignature(host.echartsView)
                if let priorSignature, priorSignature != signature { changed = true }
                priorSignature = signature
                if active != 0 { failed = true }
                print("t\(time)\tactiveAnimators=\(active)")
                if i == sorted.count - 1 {
                    print("ANIMATION_DISABLED\t\(failed ? "FAIL" : "PASS")\tsceneChanged=\(changed)\t\(demo.name)")
                    exit(failed ? 1 : 0)
                }
            }
        }
        app.run()
        return true

    case "--update-invariant":
        // --update-invariant <demo> : the broad-coverage variant of --anim-invariant. --anim-invariant
        //   needs a `drive` timeline (only 21 demos have one); this instead applies the demo's OWN option
        //   a second time (merge-mode setOption — upstream's refresh idiom) and measures element-identity
        //   overlap across that update. A view that reuses+tweens keeps its elements (overlap→1); a view
        //   ported as a static rebuild (the GaugeView reset bug) churns them (overlap→0). Runs on all
        //   demos, so the whole reset-bug CLASS is enumerable, not just the drive-demo instances.
        guard args.count >= 2, let demo = EChartsDemoRegistry.byName(args[1]), demo.nativeSupported else {
            FileHandle.standardError.write(Data("usage: --update-invariant <name>\n".utf8)); exit(2)
        }
        let uapp = NSApplication.shared
        uapp.setActivationPolicy(.accessory)
        let uhost = EChartsHostView(frame: CGRect(x: 0, y: 0, width: demo.width, height: demo.height))
        uhost.setOption(demo.option)
        let usnaps = AnimInvariantSnaps()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            var ids = Set<ObjectIdentifier>()
            _ = uhost.echartsView.ec.getRoot().traverse { el in ids.insert(ObjectIdentifier(el)); return false }
            usnaps.samples.append((700, ids, 0))
            uhost.setOption(demo.option, notMerge: false)   // the second, MERGE-mode apply
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            var ids = Set<ObjectIdentifier>()
            _ = uhost.echartsView.ec.getRoot().traverse { el in ids.insert(ObjectIdentifier(el)); return false }
            usnaps.samples.append((1500, ids, 0))
            let a = usnaps.samples[0].1, b = usnaps.samples[1].1
            let ratio = a.isEmpty ? 1.0 : Double(a.intersection(b).count) / Double(a.count)
            print(String(format: "UPDATE_OVERLAP\t%.2f\t%d\t%d\t%@", ratio, a.count, b.count, demo.name))
            exit(0)
        }
        uapp.run()
        return true

    default:
        return false
    }
}

@main
struct EChartsDemoGalleryMain {
    @MainActor
    static func main() {
        if runCLI() == false {
            let app = NSApplication.shared
            let delegate = AppDelegate()
            app.delegate = delegate
            app.setActivationPolicy(.regular)
            app.run()
        }
    }
}

#else

import Foundation
@main
struct EChartsDemoGalleryMain {
    static func main() {
        FileHandle.standardError.write(Data("EChartsDemoGallery requires macOS (AppKit).\n".utf8))
        exit(1)
    }
}

#endif
