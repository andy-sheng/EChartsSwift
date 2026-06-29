// main.swift — DemoGallery entry point.
//
// The native equivalent of opening zrender's `test/*.html` in a browser: it renders the
// migrated demo scenes (Demos.swift) through NativePainter. Two ways to drive it:
//
//   swift run DemoGallery                       GUI: sidebar of demos + live ZRenderView
//   swift run DemoGallery --list                print demo names, exit
//   swift run DemoGallery --render <name> <png> headless-render one demo to a PNG
//   swift run DemoGallery --render-all <dir>    headless-render every demo to <dir>/<name>.png
//
// The headless modes need no window/display, so they double as a CI smoke check that the
// add → paint → rasterize pipeline produces non-blank output.

#if canImport(AppKit)

import AppKit
import WebKit
import ZRenderKit
import NativePainter

let DEMO_SIZE = CGSize(width: 680, height: 220)

// ---------------------------------------------------------------------------
// Headless rendering: build the scene, paint it, rasterize painter.rootLayer.
// ---------------------------------------------------------------------------

@MainActor
func renderToBitmap(_ demo: Demo, size: CGSize) -> NSBitmapImageRep? {
    let view = ZRenderView(frame: CGRect(origin: .zero, size: size),
                           backgroundColor: NSColor.white.cgColor)
    demo.build(view.zr)
    view.frame = CGRect(origin: .zero, size: size)
    view.layoutSubtreeIfNeeded()      // -> ZRenderView.layout(): resize + refresh
    view.zr.refreshImmediately()      // force a synchronous paint into the CAShapeLayers

    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }

    // CALayer.render(in:) rasterizes the layer + its sublayers without needing a window.
    view.painter.rootLayer.render(in: ctx.cgContext)
    return rep
}

@MainActor
func writePNG(_ demo: Demo, to url: URL, size: CGSize) -> Bool {
    guard let rep = renderToBitmap(demo, size: size),
          let png = rep.representation(using: .png, properties: [:]) else { return false }
    do { try png.write(to: url); return true } catch { return false }
}

/// A crude "is anything painted?" check: count pixels that are not the white background.
@MainActor
func nonBackgroundPixelCount(_ rep: NSBitmapImageRep) -> Int {
    var n = 0
    for y in stride(from: 0, to: rep.pixelsHigh, by: 4) {
        for x in stride(from: 0, to: rep.pixelsWide, by: 4) {
            if let c = rep.colorAt(x: x, y: y),
               !(c.redComponent > 0.98 && c.greenComponent > 0.98 && c.blueComponent > 0.98) {
                n += 1
            }
        }
    }
    return n
}

/// Composite every demo into one tall, labeled PNG — a single "look at everything" sheet.
@MainActor
func renderContactSheet(to url: URL, cell: CGSize) -> Bool {
    let demos = DemoRegistry.everything
    let pad: CGFloat = 14, labelH: CGFloat = 22
    let totalW = cell.width + pad * 2
    let rowH = labelH + cell.height + pad
    let totalH = pad + rowH * CGFloat(demos.count)

    let image = NSImage(size: NSSize(width: totalW, height: totalH))
    image.lockFocus()              // non-flipped (y-up); draw cells upright like the per-demo PNGs
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: totalW, height: totalH).fill()

    let labelAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.boldSystemFont(ofSize: 13),
        .foregroundColor: NSColor.black
    ]
    // Stack rows top→bottom by computing each row's TOP edge in y-up coordinates.
    for (i, d) in demos.enumerated() {
        let topEdge = totalH - pad - CGFloat(i) * rowH
        ("\(d.name) — \(d.summary)" as NSString).draw(
            in: NSRect(x: pad, y: topEdge - labelH, width: cell.width, height: labelH),
            withAttributes: labelAttrs)
        let native = CGSize(width: d.width, height: d.height)
        if let bmp = renderToBitmap(d, size: native) {
            // aspect-fit the native-size render into the fixed cell box
            let box = NSRect(x: pad, y: topEdge - labelH - cell.height, width: cell.width, height: cell.height)
            let s = min(box.width / native.width, box.height / native.height)
            let w = native.width * s, h = native.height * s
            bmp.draw(in: NSRect(x: box.minX, y: box.minY + (box.height - h) / 2, width: w, height: h))
        }
    }
    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { return false }
    return (try? png.write(to: url)) != nil
}

// ---------------------------------------------------------------------------
// GUI — standard macOS chrome (Notes-style): NSSplitViewController with a
// source-list sidebar + unified toolbar. On macOS 26 (Tahoe) these system
// components render with Liquid Glass automatically; the content header also
// uses an explicit NSGlassEffectView where available.
// ---------------------------------------------------------------------------

/// Demos grouped by category, in first-seen order (drives the source list sections).
struct DemoSection { let title: String; let demos: [Demo] }

// MARK: - ES-module → inlined-UMD html rewrite (shared by the GUI right pane + --web-snapshot)

/// Rebuild an ES-module demo html (`<script type="module"> … import … from '../index.js'`) into a
/// self-contained page: inline the UMD `dist/zrender.js` (exposes global `zrender`), reuse the page's
/// `#main` div, and run the original scene script with its `import` line(s) stripped. No file
/// subresources, so `loadHTMLString(baseURL: nil)` renders it with zero file-access setup. Returns
/// nil if the bundle is missing or the module script can't be located (→ caller falls back to the file).
func inlinedUMDPage(moduleHTML html: String, distJSURL: URL) -> String? {
    guard let dist = try? String(contentsOf: distJSURL, encoding: .utf8) else { return nil }
    guard let body = substringBetween(html, after: "<script type=\"module\">", upTo: "</script>") else { return nil }

    // Drop the ES `import …;` statements — the UMD bundle already provides the global `zrender`.
    let scene = body
        .split(separator: "\n", omittingEmptySubsequences: false)
        .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("import ") }
        .joined(separator: "\n")

    // Reuse the page's #main (preserves the canvas size); fall back to a default box.
    let mainDiv = substringBetween(html, after: "<div id=\"main\"", upTo: ">")
        .map { "<div id=\"main\"\($0)></div>" }
        ?? "<div id=\"main\" style=\"width:1000px;height:800px;\"></div>"

    // Defensive: a `</script>` inside the bundle would close the tag early (dist/zrender.js has none
    // today, but guard anyway). `<\/script` is equivalent inside any JS string/regex.
    let safeDist = dist.replacingOccurrences(of: "</script", with: "<\\/script")

    return """
    <!DOCTYPE html><html><head><meta charset="utf-8">
    <script>\(safeDist)</script>
    </head><body style="margin:0">
    \(mainDiv)
    <script>\(scene)</script>
    </body></html>
    """
}

/// Substring strictly between the first `start` and the first `end` after it (nil if not found).
func substringBetween(_ s: String, after start: String, upTo end: String) -> String? {
    guard let a = s.range(of: start) else { return nil }
    guard let b = s.range(of: end, range: a.upperBound..<s.endIndex) else { return nil }
    return String(s[a.upperBound..<b.lowerBound])
}

func demoSections() -> [DemoSection] {
    var order: [String] = []
    var byCat: [String: [Demo]] = [:]
    for d in DemoRegistry.everything {
        if byCat[d.category] == nil { order.append(d.category) }
        byCat[d.category, default: []].append(d)
    }
    return order.map { DemoSection(title: $0, demos: byCat[$0]!) }
}

func symbol(for category: String) -> String {
    switch category {
    case "Shapes":     return "square.on.circle"
    case "Paint":      return "paintpalette"
    case "Text":       return "textformat"
    case "Transform":  return "rotate.3d"
    case "Path tools": return "scribble.variable"
    case "Animation":  return "play.circle"
    case "Rendering":  return "square.grid.3x3.fill"
    default:           return "circle"
    }
}

// MARK: - Sidebar (NSOutlineView, source-list style)

final class SidebarViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    let sections = demoSections()
    var onSelect: ((Demo) -> Void)?
    private let outline = NSOutlineView()

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
        for r in 0..<outline.numberOfRows where outline.item(atRow: r) is Demo {
            outline.selectRowIndexes(IndexSet(integer: r), byExtendingSelection: false)
            break
        }
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
    func outlineView(_ ov: NSOutlineView, shouldSelectItem item: Any) -> Bool { item is Demo }

    func outlineView(_ ov: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        if let s = item as? DemoSection {
            let id = NSUserInterfaceItemIdentifier("group")
            let tf = (ov.makeView(withIdentifier: id, owner: self) as? NSTextField)
                ?? { let t = NSTextField(labelWithString: ""); t.identifier = id; return t }()
            tf.stringValue = s.title
            return tf
        }
        let d = item as! Demo
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = (ov.makeView(withIdentifier: id, owner: self) as? NSTableCellView) ?? Self.makeCell(id)
        cell.textField?.stringValue = d.name
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
        if let d = outline.item(atRow: outline.selectedRow) as? Demo { onSelect?(d) }
    }
}

// MARK: - Content (render area): glass header pill + white canvas card

final class CanvasViewController: NSViewController {
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let canvasHost = NSView()
    // Live native render: a real ZRenderView (animation clock + Handler/drag), hosted in a scroll
    // view whose `magnification` fit-scales the demo's logical canvas — so animations actually play
    // and draggable elements actually drag, side-by-side with the live html on the right.
    private let liveScroll = NSScrollView()
    private var currentZRView: ZRenderView?
    private var controlsPanel: NSView?     // floating dat.GUI-equivalent panel (demos with controls)
    private let webView = WKWebView()

    /// upstream test/ dir, baked in at compile time via #filePath (same trick GoldenTests uses
    /// for the Oracle path). Entry.swift lives at <repo>/Sources/DemoGallery/Entry.swift.
    private static let testDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // DemoGallery
        .deletingLastPathComponent()   // Sources
        .deletingLastPathComponent()   // repo root
        .appendingPathComponent("upstream/zrender/test", isDirectory: true)
    /// Read access must include ../dist so the html's `<script src="../dist/zrender.js">` resolves.
    private static var zrenderDir: URL { testDir.deletingLastPathComponent() }
    /// The UMD bundle (a global `zrender`), inlined for the ES-module → dist rewrite.
    static var distJSURL: URL { zrenderDir.appendingPathComponent("dist/zrender.js") }

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

        // Header in Liquid Glass where available; plain otherwise.
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

        // ---- Two side-by-side comparison panes ----
        // Left: the native Swift render (NativePainter). Right: the ORIGINAL zrender
        // test/*.html in a WKWebView, for a direct visual diff.
        func card(_ host: NSView) {
            host.translatesAutoresizingMaskIntoConstraints = false
            host.wantsLayer = true
            host.layer?.backgroundColor = NSColor.white.cgColor
            host.layer?.cornerRadius = 14
            host.layer?.masksToBounds = true
            host.layer?.borderWidth = 0.5
            host.layer?.borderColor = NSColor.separatorColor.cgColor
        }
        card(canvasHost)
        // The native render uses the demo's own (often 1000–1200px) coordinate space, so host a live
        // ZRenderView at that logical size inside a scroll view and fit-scale it via `magnification`
        // (the native analog of the webview's pageZoom).
        liveScroll.translatesAutoresizingMaskIntoConstraints = false
        liveScroll.drawsBackground = false
        liveScroll.hasVerticalScroller = false
        liveScroll.hasHorizontalScroller = false
        liveScroll.borderType = .noBorder
        liveScroll.allowsMagnification = true
        liveScroll.verticalScrollElasticity = .none
        liveScroll.horizontalScrollElasticity = .none
        canvasHost.addSubview(liveScroll)
        NSLayoutConstraint.activate([
            liveScroll.topAnchor.constraint(equalTo: canvasHost.topAnchor, constant: 8),
            liveScroll.leadingAnchor.constraint(equalTo: canvasHost.leadingAnchor, constant: 8),
            liveScroll.trailingAnchor.constraint(equalTo: canvasHost.trailingAnchor, constant: -8),
            liveScroll.bottomAnchor.constraint(equalTo: canvasHost.bottomAnchor, constant: -8),
        ])
        let webHost = NSView(); card(webHost)
        webView.translatesAutoresizingMaskIntoConstraints = false
        // Upstream demos use big (1000–1200px) canvases; zoom out so most of the original
        // scene fits the half-width pane instead of showing only a corner.
        webView.pageZoom = 0.55
        webHost.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: webHost.topAnchor),
            webView.leadingAnchor.constraint(equalTo: webHost.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: webHost.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: webHost.bottomAnchor),
        ])

        let nativeCap = NSTextField(labelWithString: "Native · Swift + NativePainter")
        let webCap = NSTextField(labelWithString: "Original · zrender test/*.html")
        for c in [nativeCap, webCap] {
            c.font = .systemFont(ofSize: 11, weight: .medium)
            c.textColor = .secondaryLabelColor
            c.translatesAutoresizingMaskIntoConstraints = false
        }

        root.addSubview(header)
        root.addSubview(nativeCap); root.addSubview(webCap)
        root.addSubview(canvasHost); root.addSubview(webHost)
        // Pin to the SAFE AREA (not raw view): with `.fullSizeContentView` + a unified toolbar
        // the content extends under the toolbar; safeAreaLayoutGuide.top sits below it.
        let safe = root.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: safe.topAnchor, constant: 12),
            header.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 20),
            header.trailingAnchor.constraint(lessThanOrEqualTo: safe.trailingAnchor, constant: -20),

            nativeCap.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
            nativeCap.leadingAnchor.constraint(equalTo: canvasHost.leadingAnchor, constant: 2),
            webCap.topAnchor.constraint(equalTo: nativeCap.topAnchor),
            webCap.leadingAnchor.constraint(equalTo: webHost.leadingAnchor, constant: 2),

            canvasHost.topAnchor.constraint(equalTo: nativeCap.bottomAnchor, constant: 6),
            canvasHost.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 20),
            canvasHost.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -20),

            webHost.topAnchor.constraint(equalTo: canvasHost.topAnchor),
            webHost.leadingAnchor.constraint(equalTo: canvasHost.trailingAnchor, constant: 16),
            webHost.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -20),
            webHost.bottomAnchor.constraint(equalTo: canvasHost.bottomAnchor),
            webHost.widthAnchor.constraint(equalTo: canvasHost.widthAnchor),
        ])
        self.view = root
    }

    func show(_ demo: Demo) {
        // Tear down the previous live scene (dropping the last strong ref deallocates the old
        // ZRenderView, whose deinit stops its animation clock + disposes its ZRender).
        currentZRView?.removeFromSuperview()
        controlsPanel?.removeFromSuperview(); controlsPanel = nil
        let logical = CGRect(x: 0, y: 0, width: demo.width, height: demo.height)
        let zrView = ZRenderView(frame: logical, backgroundColor: NSColor.white.cgColor)
        // Demos with a control panel build the scene AND return their controls (so the controls can
        // capture the live element refs); others just build. Either way the scene is built once.
        let controls: [DemoControl]
        if let make = demo.controls {
            controls = make(zrView.zr)
        } else {
            demo.build(zrView.zr)
            controls = []
        }
        zrView.frame = logical
        liveScroll.documentView = zrView
        currentZRView = zrView
        fitNativeMagnification()
        buildControlsPanel(controls)

        titleLabel.stringValue = demo.name
        subtitleLabel.stringValue = "\(demo.category) · \(demo.summary)"

        // Right pane: load the original upstream html. The dist-bundle demos (`../dist/zrender.js`)
        // load directly. The ES-module ones (`import … from '../index.js'`, e.g. sector.html) can't
        // run in WKWebView (the uncompiled TS entry + tslib don't resolve), so rebuild them as a
        // self-contained page with the UMD dist bundle INLINED — the original scene then renders for
        // side-by-side comparison. Demos without any html still get the graceful notice.
        let htmlURL = Self.testDir.appendingPathComponent(demo.name + ".html")
        if FileManager.default.fileExists(atPath: htmlURL.path),
           let html = try? String(contentsOf: htmlURL, encoding: .utf8) {
            if html.contains("type=\"module\""),
               let umd = inlinedUMDPage(moduleHTML: html, distJSURL: Self.distJSURL) {
                webView.loadHTMLString(umd, baseURL: nil)
            } else {
                // dist-bundle demo (or rewrite unavailable) — load the file as-is.
                webView.loadFileURL(htmlURL, allowingReadAccessTo: Self.zrenderDir)
            }
        } else {
            webView.loadHTMLString(
                "<html><body style=\"margin:0;font:13px -apple-system;color:#999;"
                + "display:flex;align-items:center;justify-content:center;height:100vh\">"
                + "no upstream <code style=\"margin:0 .4em\">test/\(demo.name).html</code></body></html>",
                baseURL: nil)
        }
    }

    /// Fit the live scene's logical canvas into the scroll view via `magnification` (aspect-fit).
    private func fitNativeMagnification() {
        guard let doc = currentZRView else { return }
        // Use the scroll view's OWN view-space size, NOT `contentView.bounds` — the clip view's bounds
        // are in (already-magnified) DOCUMENT coordinates, so feeding them back here makes the fit
        // ratio depend on the current magnification and oscillate on every resize/layout pass (the
        // "size goes wrong when resizing" bug). `liveScroll.bounds` is unaffected by magnification.
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

    override func viewDidLayout() {
        super.viewDidLayout()
        fitNativeMagnification()
    }

    /// Floating control panel (the native analog of the demo's `dat.GUI`), pinned top-right over the
    /// canvas card. Rebuilt per demo; empty `controls` → no panel.
    private func buildControlsPanel(_ controls: [DemoControl]) {
        controlsPanel?.removeFromSuperview(); controlsPanel = nil
        guard !controls.isEmpty else { return }

        let stack = NSStackView(views: controls.map { ControlRowView($0) })
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let panel = NSView()
        panel.wantsLayer = true
        panel.layer?.backgroundColor = NSColor(white: 0.12, alpha: 0.92).cgColor
        panel.layer?.cornerRadius = 6
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(stack)
        canvasHost.addSubview(panel)   // added after liveScroll → floats on top

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: panel.topAnchor),
            stack.bottomAnchor.constraint(equalTo: panel.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            panel.topAnchor.constraint(equalTo: canvasHost.topAnchor, constant: 10),
            panel.trailingAnchor.constraint(equalTo: canvasHost.trailingAnchor, constant: -10),
        ])
        controlsPanel = panel
    }
}

/// One row of the native control panel — label + NSSlider / NSButton checkbox, wired to a DemoControl.
private final class ControlRowView: NSView {
    private let control: DemoControl
    private let valueLabel = NSTextField(labelWithString: "")

    init(_ control: DemoControl) {
        self.control = control
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let name = NSTextField(labelWithString: control.label)
        name.font = .systemFont(ofSize: 11)
        name.textColor = .white
        name.translatesAutoresizingMaskIntoConstraints = false
        addSubview(name)

        switch control.kind {
        case .slider(let lo, let hi):
            let slider = NSSlider(value: control.value, minValue: lo, maxValue: hi,
                                  target: self, action: #selector(sliderChanged(_:)))
            slider.controlSize = .small
            slider.translatesAutoresizingMaskIntoConstraints = false
            valueLabel.stringValue = Self.fmt(control.value)
            valueLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
            valueLabel.textColor = NSColor(white: 0.7, alpha: 1)
            valueLabel.alignment = .right
            valueLabel.translatesAutoresizingMaskIntoConstraints = false
            addSubview(slider); addSubview(valueLabel)
            NSLayoutConstraint.activate([
                name.leadingAnchor.constraint(equalTo: leadingAnchor),
                name.centerYAnchor.constraint(equalTo: centerYAnchor),
                name.widthAnchor.constraint(equalToConstant: 92),
                slider.leadingAnchor.constraint(equalTo: name.trailingAnchor, constant: 6),
                slider.centerYAnchor.constraint(equalTo: centerYAnchor),
                valueLabel.leadingAnchor.constraint(equalTo: slider.trailingAnchor, constant: 6),
                valueLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
                valueLabel.widthAnchor.constraint(equalToConstant: 30),
                valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        case .toggle:
            let check = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleChanged(_:)))
            check.state = control.value != 0 ? .on : .off
            check.translatesAutoresizingMaskIntoConstraints = false
            addSubview(check)
            NSLayoutConstraint.activate([
                name.leadingAnchor.constraint(equalTo: leadingAnchor),
                name.centerYAnchor.constraint(equalTo: centerYAnchor),
                check.leadingAnchor.constraint(greaterThanOrEqualTo: name.trailingAnchor, constant: 6),
                check.trailingAnchor.constraint(equalTo: trailingAnchor),
                check.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        }
        // Fixed row width so the internal trailing constraints + the panel size are stable.
        widthAnchor.constraint(equalToConstant: 210).isActive = true
        heightAnchor.constraint(equalToConstant: 20).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private static func fmt(_ v: Double) -> String { String(format: "%.2f", v) }

    @objc private func sliderChanged(_ s: NSSlider) {
        valueLabel.stringValue = Self.fmt(s.doubleValue)
        control.onChange(s.doubleValue)
    }

    @objc private func toggleChanged(_ b: NSButton) {
        control.onChange(b.state == .on ? 1 : 0)
    }
}

// MARK: - Headless WebView snapshot (verification of the right pane, --web-snapshot)

final class WebSnapper: NSObject, WKNavigationDelegate {
    let out: URL
    init(out: URL) { self.out = out }
    func webView(_ wv: WKWebView, didFinish navigation: WKNavigation!) {
        // give zrender a beat to init + paint its canvas, then snapshot.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            wv.takeSnapshot(with: WKSnapshotConfiguration()) { image, err in
                if let image = image, let tiff = image.tiffRepresentation,
                   let rep = NSBitmapImageRep(data: tiff),
                   let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: self.out)
                    print("wrote \(self.out.path)")
                } else {
                    print("snapshot failed: \(String(describing: err))")
                }
                exit(0)
            }
        }
    }
    func webView(_ wv: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("load failed: \(error.localizedDescription)"); exit(1)
    }
}

// MARK: - Split + window + toolbar

final class GallerySplitViewController: NSSplitViewController {
    let sidebar = SidebarViewController()
    let canvas = CanvasViewController()

    override func viewDidLoad() {
        super.viewDidLoad()
        let side = NSSplitViewItem(sidebarWithViewController: sidebar)
        side.minimumThickness = 210
        side.maximumThickness = 320
        side.canCollapse = true
        addSplitViewItem(side)

        let main = NSSplitViewItem(viewController: canvas)
        main.minimumThickness = 380
        addSplitViewItem(main)

        sidebar.onSelect = { [weak self] demo in self?.canvas.show(demo) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSToolbarDelegate {
    var window: NSWindow!
    private let splitVC = GallerySplitViewController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        win.title = "zrender → Swift"
        win.subtitle = "Demo Gallery · \(DemoRegistry.everything.count) demos"
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
// Arg dispatch
// ---------------------------------------------------------------------------

@MainActor
func runCLI() -> Bool {
    let args = Array(CommandLine.arguments.dropFirst())
    guard let cmd = args.first else { return false }   // no args → GUI

    switch cmd {
    case "--list":
        for d in DemoRegistry.everything { print("\(d.name)\t[\(d.category)]\t\(d.summary)") }
        return true

    case "--render":
        guard args.count >= 3, let demo = DemoRegistry.byName(args[1]) else {
            FileHandle.standardError.write(Data("usage: --render <name> <out.png>\n".utf8)); exit(2)
        }
        let url = URL(fileURLWithPath: args[2])
        let ok = writePNG(demo, to: url, size: CGSize(width: demo.width, height: demo.height))
        print(ok ? "wrote \(url.path)" : "FAILED to render \(demo.name)")
        exit(ok ? 0 : 1)

    case "--gui-snapshot":
        // --gui-snapshot <demo> <out.png> : build the demo's control panel (exercises the `controls`
        // closure + ControlRowView layout) and snapshot JUST the panel. Verifies the panel renders
        // without the glass header / WKWebView (whose offscreen layer.render traps).
        guard args.count >= 3, let demo = DemoRegistry.byName(args[1]) else {
            FileHandle.standardError.write(Data("usage: --gui-snapshot <demo> <out.png>\n".utf8)); exit(2)
        }
        NSApplication.shared.setActivationPolicy(.accessory)
        let probe = ZRenderView(frame: CGRect(x: 0, y: 0, width: demo.width, height: demo.height),
                                backgroundColor: NSColor.white.cgColor)
        let controls = demo.controls?(probe.zr) ?? []
        guard !controls.isEmpty else { print("\(demo.name) has no controls"); exit(0) }

        let stack = NSStackView(views: controls.map { ControlRowView($0) })
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        let panel = NSView(); panel.wantsLayer = true
        panel.layer?.backgroundColor = NSColor(white: 0.12, alpha: 1).cgColor
        panel.layer?.cornerRadius = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: panel.topAnchor),
            stack.bottomAnchor.constraint(equalTo: panel.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
        ])
        panel.layoutSubtreeIfNeeded()
        panel.frame = CGRect(origin: .zero, size: panel.fittingSize)
        // Host in a window so the AppKit controls draw, then cacheDisplay (captures drawRect output,
        // which layer.render does not for non-layer-backed NSSlider/NSButton/NSTextField).
        let win = NSWindow(contentRect: panel.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        win.contentView = panel
        win.orderFrontRegardless()
        panel.layoutSubtreeIfNeeded()
        if let rep = panel.bitmapImageRepForCachingDisplay(in: panel.bounds) {
            panel.cacheDisplay(in: panel.bounds, to: rep)
            if let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: args[2])); print("wrote \(args[2])")
            }
        }
        exit(0)

    case "--render-all":
        guard args.count >= 2 else {
            FileHandle.standardError.write(Data("usage: --render-all <dir>\n".utf8)); exit(2)
        }
        let dir = URL(fileURLWithPath: args[1], isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var failed = 0
        for d in DemoRegistry.everything {
            let url = dir.appendingPathComponent(d.name + ".png")
            if let rep = renderToBitmap(d, size: CGSize(width: d.width, height: d.height)),
               let png = rep.representation(using: .png, properties: [:]),
               (try? png.write(to: url)) != nil {
                print("  \(d.name).png  (\(nonBackgroundPixelCount(rep)) painted samples)")
            } else { print("  \(d.name)  FAILED"); failed += 1 }
        }
        print("rendered \(DemoRegistry.everything.count - failed)/\(DemoRegistry.everything.count) demos to \(dir.path)")
        exit(failed == 0 ? 0 : 1)

    case "--web-snapshot":
        // --web-snapshot <demo> <out.png> : render the ORIGINAL upstream html in an offscreen
        // WKWebView and snapshot it (verifies the gallery's right pane works headlessly).
        guard args.count >= 3 else {
            FileHandle.standardError.write(Data("usage: --web-snapshot <demo> <out.png>\n".utf8)); exit(2)
        }
        let testDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("upstream/zrender/test", isDirectory: true)
        let htmlURL = testDir.appendingPathComponent(args[1] + ".html")
        guard FileManager.default.fileExists(atPath: htmlURL.path) else {
            print("no upstream html for \(args[1])"); exit(1)
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 900, height: 480))
        let win = NSWindow(contentRect: wv.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        win.contentView = wv
        win.orderFrontRegardless()
        let snapper = WebSnapper(out: URL(fileURLWithPath: args[2]))
        wv.navigationDelegate = snapper
        // Mirror the GUI right pane: ES-module demos load via the inlined-UMD rewrite, others as-is.
        let zrenderDir = testDir.deletingLastPathComponent()
        if let html = try? String(contentsOf: htmlURL, encoding: .utf8),
           html.contains("type=\"module\""),
           let umd = inlinedUMDPage(moduleHTML: html, distJSURL: zrenderDir.appendingPathComponent("dist/zrender.js")) {
            wv.loadHTMLString(umd, baseURL: nil)
        } else {
            wv.loadFileURL(htmlURL, allowingReadAccessTo: zrenderDir)
        }
        app.run()
        return true   // unreachable — WebSnapper calls exit()

    case "--contact-sheet":
        guard args.count >= 2 else {
            FileHandle.standardError.write(Data("usage: --contact-sheet <out.png>\n".utf8)); exit(2)
        }
        let url = URL(fileURLWithPath: args[1])
        let ok = renderContactSheet(to: url, cell: CGSize(width: 660, height: 200))
        print(ok ? "wrote \(url.path)" : "FAILED")
        exit(ok ? 0 : 1)

    default:
        return false
    }
}

@main
struct DemoGalleryMain {
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
struct DemoGalleryMain {
    static func main() {
        FileHandle.standardError.write(Data("DemoGallery requires macOS (AppKit).\n".utf8))
        exit(1)
    }
}

#endif
