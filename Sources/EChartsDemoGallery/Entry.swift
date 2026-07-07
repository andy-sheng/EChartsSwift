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

// ---------------------------------------------------------------------------
// upstream echarts UMD dist (the REAL echarts 6.1.0), baked in via #filePath — the same trick
// DemoGallery uses for the zrender test dir. Entry.swift lives at <repo>/Sources/EChartsDemoGallery/.
// ---------------------------------------------------------------------------
enum Upstream {
    static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // EChartsDemoGallery
        .deletingLastPathComponent()   // Sources
        .deletingLastPathComponent()   // repo root
    static let echartsDistJS = repoRoot.appendingPathComponent("upstream/echarts/dist/echarts.js")
}

// ---------------------------------------------------------------------------
// NATIVE render: EChartsKit → EChartsSlim → ZRenderKit Group → NativePainter → CGImage.
// ---------------------------------------------------------------------------

/// Drive EChartsSlim with the demo option. Phase 6c: the real SourceManager builds each series' data
/// from the option's own `series[].data`, so the stock Bar/Line series models render directly — no
/// data double is registered anymore.
@MainActor
func renderNativeGroup(_ demo: EChartsDemo) -> Group {
    let ec = EChartsSlim(width: demo.width, height: demo.height)
    ec.setOption(demo.option)
    return ec.getRoot()
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
// HTML render: the SAME option fed to the REAL echarts in a self-contained page (dist inlined).
// ---------------------------------------------------------------------------

/// A self-contained page: inline the echarts UMD bundle (global `echarts`), a `#main` div at the
/// demo's logical size, then `echarts.init(...).setOption(option)` with animation forced off so the
/// snapshot is the final, deterministic frame — matching the static native render.
func echartsHTMLPage(_ demo: EChartsDemo) -> String? {
    guard let dist = try? String(contentsOf: Upstream.echartsDistJS, encoding: .utf8) else { return nil }
    guard let optionData = try? JSONSerialization.data(withJSONObject: demo.option, options: []),
          let optionJSON = String(data: optionData, encoding: .utf8) else { return nil }
    // Guard against a stray `</script>` inside the bundle closing the tag early.
    let safeDist = dist.replacingOccurrences(of: "</script", with: "<\\/script")
    return """
    <!DOCTYPE html><html><head><meta charset="utf-8">
    <script>\(safeDist)</script>
    </head><body style="margin:0;background:#fff">
    <div id="main" style="width:\(Int(demo.width))px;height:\(Int(demo.height))px"></div>
    <script>
      var opt = \(optionJSON);
      opt.animation = false;
      var chart = echarts.init(document.getElementById('main'), null, { renderer: 'canvas' });
      chart.setOption(opt);
    </script>
    </body></html>
    """
}

// ---------------------------------------------------------------------------
// GUI: sidebar (demo list) + Native | echarts.js side-by-side panes.
// ---------------------------------------------------------------------------

@MainActor
final class GalleryWindowController: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    let window: NSWindow
    private let table = NSTableView()
    private var nativeHostView: EChartsHostView?
    private let webView = WKWebView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let demos = EChartsDemoRegistry.everything

    override init() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        super.init()
        window.title = "ECharts Demo Gallery — Native (EChartsKit) vs echarts.js"
        window.center()
        buildUI()
        if !demos.isEmpty { table.selectRowIndexes([0], byExtendingSelection: false); show(demos[0]) }
    }

    private func buildUI() {
        // Sidebar
        let col = NSTableColumn(identifier: .init("name")); col.width = 220
        table.addTableColumn(col)
        table.headerView = nil
        table.dataSource = self; table.delegate = self
        table.rowHeight = 40
        let sidebar = NSScrollView(); sidebar.documentView = table
        sidebar.hasVerticalScroller = true; sidebar.translatesAutoresizingMaskIntoConstraints = false

        // Panes
        func card(_ v: NSView) {
            v.wantsLayer = true; v.layer?.backgroundColor = NSColor.white.cgColor
            v.layer?.cornerRadius = 12; v.layer?.masksToBounds = true
            v.layer?.borderWidth = 0.5; v.layer?.borderColor = NSColor.separatorColor.cgColor
            v.translatesAutoresizingMaskIntoConstraints = false
        }
        let nativeHost = NSView(); card(nativeHost)
        let hostView = EChartsHostView(frame: NSRect(x: 0, y: 0, width: 300, height: 300), dpr: 2.0)
        hostView.translatesAutoresizingMaskIntoConstraints = false
        nativeHost.addSubview(hostView)
        self.nativeHostView = hostView
        let webHost = NSView(); card(webHost)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webHost.addSubview(webView)
        pin(hostView, to: nativeHost, inset: 8); pin(webView, to: webHost, inset: 0)

        let nativeCap = caption("Native · EChartsKit + NativePainter")
        let webCap = caption("Real · echarts.js 6.1.0 (WKWebView)")
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let root = window.contentView!
        [sidebar, titleLabel, nativeCap, webCap, nativeHost, webHost].forEach { root.addSubview($0) }
        NSLayoutConstraint.activate([
            sidebar.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
            sidebar.widthAnchor.constraint(equalToConstant: 230),

            titleLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            titleLabel.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: 16),

            nativeCap.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            nativeCap.leadingAnchor.constraint(equalTo: nativeHost.leadingAnchor, constant: 2),
            webCap.topAnchor.constraint(equalTo: nativeCap.topAnchor),
            webCap.leadingAnchor.constraint(equalTo: webHost.leadingAnchor, constant: 2),

            nativeHost.topAnchor.constraint(equalTo: nativeCap.bottomAnchor, constant: 6),
            nativeHost.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: 16),
            nativeHost.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),

            webHost.topAnchor.constraint(equalTo: nativeHost.topAnchor),
            webHost.leadingAnchor.constraint(equalTo: nativeHost.trailingAnchor, constant: 16),
            webHost.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            webHost.bottomAnchor.constraint(equalTo: nativeHost.bottomAnchor),
            webHost.widthAnchor.constraint(equalTo: nativeHost.widthAnchor),
        ])
    }

    private func caption(_ s: String) -> NSTextField {
        let c = NSTextField(labelWithString: s)
        c.font = .systemFont(ofSize: 11, weight: .medium); c.textColor = .secondaryLabelColor
        c.translatesAutoresizingMaskIntoConstraints = false
        return c
    }
    private func pin(_ v: NSView, to host: NSView, inset: CGFloat) {
        NSLayoutConstraint.activate([
            v.topAnchor.constraint(equalTo: host.topAnchor, constant: inset),
            v.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: inset),
            v.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -inset),
            v.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -inset),
        ])
    }

    private func show(_ demo: EChartsDemo) {
        titleLabel.stringValue = "\(demo.name)  —  \(demo.summary)"
        // Native pane
        if demo.nativeSupported {
            nativeHostView?.setOption(demo.option)
        }
        // HTML pane
        if let page = echartsHTMLPage(demo) {
            webView.loadHTMLString(page, baseURL: nil)
        }
    }

    // Table data source / delegate
    func numberOfRows(in tableView: NSTableView) -> Int { demos.count }
    func tableView(_ t: NSTableView, viewFor col: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = (t.makeView(withIdentifier: id, owner: nil) as? NSTableCellView) ?? {
            let c = NSTableCellView(); c.identifier = id
            let tf = NSTextField(labelWithString: ""); tf.translatesAutoresizingMaskIntoConstraints = false
            c.addSubview(tf); c.textField = tf
            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 8),
                tf.centerYAnchor.constraint(equalTo: c.centerYAnchor),
                tf.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -6),
            ])
            return c
        }()
        let d = demos[row]
        cell.textField?.attributedStringValue = sidebarLabel(d)
        return cell
    }
    private func sidebarLabel(_ d: EChartsDemo) -> NSAttributedString {
        let s = NSMutableAttributedString(
            string: d.name + "\n",
            attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium)])
        let sub = d.nativeSupported ? d.category : d.category + " · native N/A"
        s.append(NSAttributedString(string: sub, attributes: [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.secondaryLabelColor]))
        return s
    }
    func tableViewSelectionDidChange(_ n: Notification) {
        let r = table.selectedRow
        if r >= 0, r < demos.count { show(demos[r]) }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var controller: GalleryWindowController?
    func applicationDidFinishLaunching(_ n: Notification) {
        let c = GalleryWindowController(); controller = c
        c.window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
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
