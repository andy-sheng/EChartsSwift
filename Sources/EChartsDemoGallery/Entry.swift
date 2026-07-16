// Entry.swift — EChartsDemoGallery entry point.
//
// The ECharts analog of DemoGallery/Entry.swift. Renders each demo option two ways side-by-side:
//   swift run EChartsDemoGallery                       GUI: sidebar + native | echarts.js panes
//   swift run EChartsDemoGallery --list                print demo names, exit
//   swift run EChartsDemoGallery --render <name> <png> headless native render (EChartsKit) → PNG
//   swift run EChartsDemoGallery --render-all <dir>    native-render every demo to <dir>/<name>.png
//   swift run EChartsDemoGallery --web-snapshot <name> <png>   headless echarts.js render → PNG
//   swift run EChartsDemoGallery --compare <name> <dir>        BOTH panes → <dir>/<name>.{native,web}.png

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
                _ = clip.step(0, 0)          // establish baseline / apply delay offsets
                _ = clip.step(timeMs, timeMs) // advance to the representative frame
            }
        }
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
        currentHostView?.removeFromSuperview()
        currentHostView = nil
        liveScroll.documentView = nil
        if demo.nativeSupported {
            var opt = demo.option
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
        // Give ECharts a tick to lay out + paint before snapshotting.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
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
    }
    func webView(_ wv: WKWebView, didFail nav: WKNavigation!, withError e: Error) {
        FileHandle.standardError.write(Data("web load failed: \(e)\n".utf8)); exit(1)
    }
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

    case "--web-snapshot":
        guard args.count >= 3, let demo = EChartsDemoRegistry.byName(args[1]) else {
            FileHandle.standardError.write(Data("usage: --web-snapshot <name> <out.png>\n".utf8)); exit(2)
        }
        loadWebAndSnapshot(demo, out: URL(fileURLWithPath: args[2]))

    case "--render-rasterizer":
        // --render-rasterizer <name> <out.png> : headless render of the demo's static frame
        // through the RasterizerPainter translation + the engine's RasterizerCG CPU reference
        // (the Metal toggle renders the same scene list on the GPU).
        guard args.count >= 3, let demo = EChartsDemoRegistry.byName(args[1]),
              demo.nativeSupported else {
            FileHandle.standardError.write(Data("usage: --render-rasterizer <name> <out.png>\n".utf8)); exit(2)
        }
        let group = renderNativeGroup(demo)
        let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        let painter = RasterizerPainter(size: CGSize(width: demo.width, height: demo.height),
                                        dpr: 1, backgroundColor: white)
        painter.refresh(flattenDisplayList(group))
        guard let img = painter.renderToImage(),
              let png = NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:]),
              (try? png.write(to: URL(fileURLWithPath: args[2]))) != nil else {
            print("FAILED"); exit(1)
        }
        print("wrote \(args[2])")
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
        host.setOption(demo.option)          // animation ON (do NOT force it off)
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
