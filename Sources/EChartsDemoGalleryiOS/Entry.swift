// Entry.swift — EChartsDemoGalleryiOS entry point.
//
// The iOS twin of the macOS gallery (Sources/EChartsDemoGallery/Entry.swift): the SAME demo
// registry (EChartsDemoCore), rendered two ways per demo —
//   - NATIVE:  EChartsKit → ECharts → ZRenderKit → NativePainter, live in an EChartsHostView
//   - REAL:    the same option fed to echarts.js (upstream/echarts/dist) in a WKWebView
// as a UISplitViewController: primary = demo list, secondary = the two panes (side-by-side when
// wide, stacked when narrow) + the same "Native 动画" toggle.
//
// No CLI: the headless --render/--compare/--web-snapshot paths stay macOS-only (Entry.swift there).
// Built for the iOS SIMULATOR by scripts/build-echarts-gallery-ios.sh — the web pane inlines
// upstream/echarts/dist/echarts.js read off the HOST filesystem (via #filePath in EChartsDemoCore),
// which only the simulator shares; the staged .app is a local dev/test artifact, like the mac one.

#if canImport(UIKit)

import UIKit
import WebKit
import ZRenderKit
import EChartsKit
import NativePainter
import EChartsDemoCore

// ---------------------------------------------------------------------------
// FitBox — scale-to-fit container for a fixed-logical-size content view.
//
// The native chart lays out at the demo's logical size (ECharts has no resize hook), so the
// host view keeps bounds = demo.width × demo.height and is transform-scaled to fit — the exact
// visual analog of the web pane's `<meta viewport width=demo.width>` scaling. UIKit routes touches
// through the transform, so interaction coordinates stay logical for free.
// ---------------------------------------------------------------------------
final class FitBox: UIView {
    private let logicalSize: CGSize
    private let content: UIView

    init(content: UIView, logicalSize: CGSize) {
        self.content = content
        self.logicalSize = logicalSize
        super.init(frame: .zero)
        addSubview(content)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0,
              logicalSize.width > 0, logicalSize.height > 0 else { return }
        let scale = min(bounds.width / logicalSize.width, bounds.height / logicalSize.height)
        // Set bounds+center (not frame) — frame is undefined under a non-identity transform.
        content.bounds = CGRect(origin: .zero, size: logicalSize)
        content.center = CGPoint(x: bounds.midX, y: bounds.midY)
        content.transform = CGAffineTransform(scaleX: scale, y: scale)
    }
}

// ---------------------------------------------------------------------------
// Demo list (primary column) — name + category rows, mirroring the mac sidebar.
// ---------------------------------------------------------------------------
final class DemoListViewController: UITableViewController {
    /// The mac gallery's two tabs, as two table sections (the phone list has no room for a tab bar).
    private let groups: [(title: String, demos: [EChartsDemo])] = [
        ("移植 · Port", EChartsDemoRegistry.portDemos),
        ("官方示例 · Official", EChartsDemoRegistry.officialDemos),
    ]
    var onSelect: ((EChartsDemo) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "ECharts Demos"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
    }

    override func numberOfSections(in tableView: UITableView) -> Int { groups.count }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        groups[section].title
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        groups[section].demos.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let d = groups[indexPath.section].demos[indexPath.row]
        var conf = UIListContentConfiguration.subtitleCell()
        conf.text = d.displayName
        conf.secondaryText = d.nativeSupported ? d.category : d.category + " · native N/A"
        conf.secondaryTextProperties.color = .secondaryLabel
        conf.secondaryTextProperties.font = .systemFont(ofSize: 11)
        cell.contentConfiguration = conf
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        onSelect?(groups[indexPath.section].demos[indexPath.row])
    }
}

// ---------------------------------------------------------------------------
// Detail (secondary column) — native | echarts.js panes + anim toggle.
// ---------------------------------------------------------------------------
final class DemoDetailViewController: UIViewController {
    private let stack = UIStackView()
    private let nativePane = paneCard()
    private let webPane = paneCard()
    private let webView: WKWebView = {
        let wv = WKWebView()
        wv.scrollView.isScrollEnabled = false   // the viewport meta scales the page; don't pan it
        return wv
    }()
    private var nativeFit: FitBox?
    private var hostView: EChartsHostView?
    private let animSwitch = UISwitch()
    private var currentDemo: EChartsDemo?

    private static func paneCard() -> UIView {
        let v = UIView()
        v.backgroundColor = .white
        v.layer.cornerRadius = 12
        v.layer.masksToBounds = true
        v.layer.borderWidth = 0.5
        v.layer.borderColor = UIColor.separator.cgColor
        return v
    }

    private func caption(_ s: String) -> UILabel {
        let l = UILabel()
        l.text = s
        l.font = .systemFont(ofSize: 11, weight: .medium)
        l.textColor = .secondaryLabel
        return l
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground

        // "Native 动画" toggle in the nav bar, same semantics as the mac switch: OFF forces
        // option.animation = false; ON leaves the echarts default (animate).
        animSwitch.addTarget(self, action: #selector(toggleAnim), for: .valueChanged)
        let animLabel = caption("Native 动画")
        let bar = UIStackView(arrangedSubviews: [animLabel, animSwitch])
        bar.axis = .horizontal; bar.spacing = 6; bar.alignment = .center
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: bar)

        // A column per pane: caption over card, cards share the demo's aspect via the stack.
        let nativeCol = UIStackView(arrangedSubviews: [caption("Native · EChartsKit + NativePainter"), nativePane])
        let webCol = UIStackView(arrangedSubviews: [caption("Real · echarts.js 6.1.0 (WKWebView)"), webPane])
        for col in [nativeCol, webCol] { col.axis = .vertical; col.spacing = 6 }

        stack.addArrangedSubview(nativeCol)
        stack.addArrangedSubview(webCol)
        stack.spacing = 16
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        webView.translatesAutoresizingMaskIntoConstraints = false
        webPane.addSubview(webView)

        let g = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: g.topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: g.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: g.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: g.bottomAnchor, constant: -12),

            webView.topAnchor.constraint(equalTo: webPane.topAnchor),
            webView.leadingAnchor.constraint(equalTo: webPane.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: webPane.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: webPane.bottomAnchor),
        ])

        if let d = currentDemo { render(d) }
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        // Side-by-side when wide (iPad / landscape), stacked when narrow (iPhone portrait).
        let horizontal = view.bounds.width > view.bounds.height
        let axis: NSLayoutConstraint.Axis = horizontal ? .horizontal : .vertical
        if stack.axis != axis { stack.axis = axis }
        updatePaneAspect()
    }

    private var aspectConstraints: [NSLayoutConstraint] = []
    private func updatePaneAspect() {
        guard let d = currentDemo else { return }
        NSLayoutConstraint.deactivate(aspectConstraints)
        let ratio = CGFloat(d.height / d.width)
        aspectConstraints = [nativePane, webPane].map {
            let c = $0.heightAnchor.constraint(equalTo: $0.widthAnchor, multiplier: ratio)
            c.priority = .defaultHigh   // yields if the stacked panes would overflow the safe area
            return c
        }
        NSLayoutConstraint.activate(aspectConstraints)
    }

    func show(_ demo: EChartsDemo) {
        currentDemo = demo
        guard isViewLoaded else { return }
        render(demo)
    }

    private func render(_ demo: EChartsDemo) {
        title = demo.displayName
        navigationItem.prompt = demo.summary
        updatePaneAspect()

        // Native pane: a FRESH host per demo at the demo's logical size (ECharts lays out at
        // init size), scale-to-fit via FitBox. Recreating also clears the previous demo's scene.
        hostView?.dispose()
        nativeFit?.removeFromSuperview()
        hostView = nil
        if demo.nativeSupported {
            var opt = demo.liveOption ?? demo.option
            if !animSwitch.isOn { opt["animation"] = false }   // ON → leave echarts default (animate)
            let host = EChartsHostView(
                frame: CGRect(x: 0, y: 0, width: demo.width, height: demo.height),
                dpr: Double(UIScreen.main.scale))
            host.animationsEnabled = animSwitch.isOn
            host.setOption(opt)
            demo.drive?(host)
            let fit = FitBox(content: host, logicalSize: CGSize(width: demo.width, height: demo.height))
            fit.translatesAutoresizingMaskIntoConstraints = false
            nativePane.addSubview(fit)
            NSLayoutConstraint.activate([
                fit.topAnchor.constraint(equalTo: nativePane.topAnchor),
                fit.leadingAnchor.constraint(equalTo: nativePane.leadingAnchor),
                fit.trailingAnchor.constraint(equalTo: nativePane.trailingAnchor),
                fit.bottomAnchor.constraint(equalTo: nativePane.bottomAnchor),
            ])
            nativeFit = fit
            hostView = host
        }

        // Web pane: the shared page builder; its viewport meta scales the fixed-size div to fit.
        if let page = echartsHTMLPage(demo) {
            webView.loadHTMLString(page, baseURL: nil)
        } else {
            webView.loadHTMLString(
                "<body style='font:13px -apple-system;color:#888'>upstream/echarts/dist/echarts.js "
                + "not readable — run scripts/sync-upstream.sh (web pane needs the simulator's host "
                + "filesystem access)</body>", baseURL: nil)
        }
    }

    @objc private func toggleAnim() {
        if let d = currentDemo { render(d) }
    }
}

// ---------------------------------------------------------------------------
// Split container + app lifecycle.
// ---------------------------------------------------------------------------
final class GallerySplitViewController: UISplitViewController, UISplitViewControllerDelegate {
    private let list = DemoListViewController(style: .plain)
    private let detail = DemoDetailViewController()

    init() {
        super.init(style: .doubleColumn)
        delegate = self
        preferredDisplayMode = .oneBesideSecondary
        setViewController(UINavigationController(rootViewController: list), for: .primary)
        setViewController(UINavigationController(rootViewController: detail), for: .secondary)
        list.onSelect = { [weak self] demo in
            guard let self else { return }
            self.detail.show(demo)
            self.show(.secondary)
        }
        if let first = EChartsDemoRegistry.everything.first { detail.show(first) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    // Collapse (iPhone) onto the demo LIST, not the detail, so launch shows the picker.
    func splitViewController(_ svc: UISplitViewController,
                             topColumnForCollapsingToProposedTopColumn proposedTopColumn: UISplitViewController.Column)
        -> UISplitViewController.Column { .primary }
}

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = GallerySplitViewController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}

#else

import Foundation
@main
struct EChartsDemoGalleryiOSMain {
    static func main() {
        FileHandle.standardError.write(Data(
            "EChartsDemoGalleryiOS requires iOS (UIKit) — build it with scripts/build-echarts-gallery-ios.sh.\n".utf8))
        exit(1)
    }
}

#endif
