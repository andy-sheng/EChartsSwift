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

// NOTE: the demo definitions (`EChartsDemo`, `EChartsDemoRegistry`, `Demos/*.swift`), the `Upstream`
// dist locator and the `echartsHTMLPage(_:)` web-pane builder all live in EChartsDemoCore, shared
// with the iOS gallery (EChartsDemoGalleryiOS).

// ---------------------------------------------------------------------------
// NATIVE render: EChartsKit → EChartsSlim → ZRenderKit Group → NativePainter → CGImage.
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

/// Drive EChartsSlim with the demo option. Phase 6c: the real SourceManager builds each series' data
/// from the option's own `series[].data`, so the stock Bar/Line series models render directly — no
/// data double is registered anymore.
@MainActor
func renderNativeGroup(_ demo: EChartsDemo) -> Group {
    var opt = demo.option
    opt["animation"] = false
    let ec = EChartsSlim(width: demo.width, height: demo.height)
    ec.setOption(opt)
    let root = ec.getRoot()
    advanceAnimationsForStaticFrame(root)
    return root
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

func demoSections() -> [DemoSection] {
    var order: [String] = []
    var byCat: [String: [EChartsDemo]] = [:]
    for d in EChartsDemoRegistry.everything {
        if byCat[d.category] == nil { order.append(d.category) }
        byCat[d.category, default: []].append(d)
    }
    return order.map { DemoSection(title: $0, demos: byCat[$0]!) }
}

func symbol(for category: String) -> String {
    switch category {
    case "Bar":           return "chart.bar"
    case "Line":          return "chart.xyaxis.line"
    case "Scatter":       return "circle.grid.3x3"
    case "EffectScatter": return "dot.radiowaves.left.and.right"
    case "Lines":         return "scribble"
    case "Pie":           return "chart.pie"
    case "Component":     return "slider.horizontal.3"
    case "Funnel":        return "arrowtriangle.down"
    case "Candlestick":   return "chart.bar.xaxis"
    case "Boxplot":       return "square.split.2x1"
    case "Sunburst":      return "sun.max"
    case "Treemap":       return "square.grid.2x2"
    case "Tree":          return "arrow.triangle.branch"
    case "Graph":         return "point.3.connected.trianglepath.dotted"
    case "Radar":         return "hexagon"
    case "Polar":         return "circle.circle"
    case "Gauge":         return "gauge"
    case "Sankey":        return "arrow.triangle.merge"
    case "Chord":         return "circle.hexagonpath"
    case "ThemeRiver":    return "waveform.path"
    case "Parallel":      return "line.3.horizontal"
    case "Calendar":      return "calendar"
    case "Matrix":        return "tablecells"
    case "Geo":           return "map"
    case "Map":           return "map.fill"
    case "VisualMap":     return "slider.horizontal.below.rectangle"
    case "Heatmap":       return "square.grid.3x3.fill"
    case "DataZoom":      return "magnifyingglass"
    case "Dataset":       return "tablecells.badge.ellipsis"
    case "Custom":        return "wrench.and.screwdriver"
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
    let sections = demoSections()
    var onSelect: ((EChartsDemo) -> Void)?
    private let outline = DemoOutlineView()

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

        let container = NSView()
        container.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: container.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        self.view = container
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        outline.expandItem(nil, expandChildren: true)
        for r in 0..<outline.numberOfRows where outline.item(atRow: r) is EChartsDemo {
            outline.selectRowIndexes(IndexSet(integer: r), byExtendingSelection: false)
            break
        }
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
        cell.textField?.stringValue = d.name
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
        if let d = outline.item(atRow: outline.selectedRow) as? EChartsDemo { onSelect?(d) }
    }
}

// MARK: - Content (render area): glass header pill + native | echarts.js cards

final class ContentViewController: NSViewController {
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let nativeHost = NSView()
    // Live native render: the chart lays out at the demo's LOGICAL size (EChartsSlim has no resize
    // hook), so host a fresh EChartsHostView at that size inside a scroll view and fit-scale it via
    // `magnification` — the same trick DemoGallery uses for its 1000px zrender canvases.
    private let liveScroll = NSScrollView()
    private var currentHostView: EChartsHostView?
    private let webHost = NSView()
    private let webView = WKWebView()
    private let animSwitch = NSSwitch()
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

        let nativeCap = caption("Native · EChartsKit + NativePainter")
        let webCap = caption("Real · echarts.js 6.1.0 (WKWebView)")

        let animLabel = caption("Native 动画")
        animSwitch.translatesAutoresizingMaskIntoConstraints = false
        animSwitch.state = .off
        animSwitch.target = self
        animSwitch.action = #selector(toggleAnim)

        [header, nativeCap, webCap, nativeHost, webHost, animLabel, animSwitch].forEach { root.addSubview($0) }
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
        titleLabel.stringValue = demo.name
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
            let host = EChartsHostView(
                frame: NSRect(x: 0, y: 0, width: demo.width, height: demo.height), dpr: 2.0)
            host.setOption(opt)
            liveScroll.documentView = host
            currentHostView = host
            fitNativeMagnification()
        }

        // HTML pane
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
        win.subtitle = "ECharts Demo Gallery · \(EChartsDemoRegistry.everything.count) demos"
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

@MainActor
func loadWebAndSnapshot(_ demo: EChartsDemo, out: URL) -> Never {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: demo.width, height: demo.height))
    let win = NSWindow(contentRect: wv.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    win.contentView = wv; win.orderFrontRegardless()
    let snapper = WebSnapper(out: out)
    wv.navigationDelegate = snapper
    guard let page = echartsHTMLPage(demo) else {
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
            print("\(d.name)\t[\(d.category)]\tnative:\(d.nativeSupported ? "yes" : "N/A")\t\(d.summary)")
        }
        return true

    case "--render":
        guard args.count >= 3, let demo = EChartsDemoRegistry.byName(args[1]) else {
            FileHandle.standardError.write(Data("usage: --render <name> <out.png>\n".utf8)); exit(2)
        }
        let ok = writeNativePNG(demo, to: URL(fileURLWithPath: args[2]))
        print(ok ? "wrote \(args[2])" : "FAILED to native-render \(demo.name)")
        exit(ok ? 0 : 1)

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
