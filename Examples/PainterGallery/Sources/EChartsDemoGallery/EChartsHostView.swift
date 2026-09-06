// macOS gallery host. Default creation follows echarts.use -> registerPainter -> echarts.init.
// Explicit painter injection remains available for existing capture/test callers. This host
// retains the gallery input handlers, animation clock and demo-owned timers.
#if canImport(AppKit)
import AppKit
import ZRenderKit
import NativePainter
import EChartsKit
import EChartsDemoCore
import NativeRenderer
import RasterizerRenderer
final class EChartsHostView: NSView, ZRenderHost {

    private(set) var echartsView: EChartsView!
    /// `CALayerPainter` by default; an alternative backend (the Metal `RasterizerPainter`)
    /// can be injected at init — same seam as `ZRenderView`.
    private var painter: LayerHostedPainter!
    private let proxy = NativeHandlerProxy()
    private var animationLoop: AnimationLoop!
    /// Timers a demo's `drive` hook scheduled (the native side of the example's setInterval /
    /// setTimeout). Owned here so they die with the view — the gallery builds a fresh host per demo,
    /// and a leaked timer would keep setOption-ing a disposed chart.
    private var driveTimers: [Timer] = []
    private var isDisposed = false
    /// Gallery policy, not an ECharts option: when false every later drive/setOption call is stamped
    /// with animation:false as well. Timers still run, so the switch disables interpolation without
    /// freezing race/dynamic data progression.
    var animationsEnabled = true

    public init(frame: CGRect, dpr: Double? = nil, painter injected: LayerHostedPainter? = nil,
                renderer: String = "canvas") {
        self.scale = dpr ?? 2
        super.init(frame: frame)
        self.wantsLayer = true
        if let injected {
            self.painter = injected
            self.echartsView = EChartsView(width: Double(frame.width), height: Double(frame.height),
                painter: injected, proxy: proxy, useCoarsePointer: false)
            self.layer?.addSublayer(injected.rootLayer)
        } else {
            echarts.use([CanvasRenderer.self, RasterizerRenderer.self])
            var opts = EChartsInitOpts()
            opts.renderer = renderer
            opts.devicePixelRatio = scale
            opts.useCoarsePointer = false
            do { self.echartsView = try echarts.`init`(self, nil, opts) }
            catch { preconditionFailure("Unable to create gallery painter: \(error)") }
            self.painter.setBackgroundColor("white")
        }
        self.animationLoop = AnimationLoop(animation: echartsView.zr.animation)
        self.animationLoop.start()
    }

    private let scale: Double
    var width: Double { Double(bounds.width) }
    var height: Double { Double(bounds.height) }
    var devicePixelRatio: Double { scale }
    var handlerProxy: HandlerProxyInterface? { proxy }
    func attach(_ zr: ZRender) throws {
        guard let painter = zr.painter as? LayerHostedPainter else {
            throw NativeChartHostError.requiresLayerHostedPainter
        }
        self.painter = painter
        layer?.addSublayer(painter.rootLayer)
    }
    func detach(_ zr: ZRender) {
        animationLoop?.stop()
        (zr.painter as? LayerHostedPainter)?.rootLayer.removeFromSuperlayer()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        dispose()
    }

    /// Explicitly stop a demo before the gallery releases it. A drive callback usually captures the
    /// chart, so deinit alone cannot break the host -> timer -> host retain cycle.
    func dispose() {
        guard !isDisposed else { return }
        isDisposed = true
        driveTimers.forEach { $0.invalidate() }
        driveTimers.removeAll()
        animationLoop.stop()
        echartsView.dispose()
    }

    // Top-left / y-down, matching zrender + the flipped AppKit root layer.
    override var isFlipped: Bool { true }

    func setOption(_ option: [String: Any]) {
        self.echartsView.setOption(optionRespectingAnimationPolicy(option))
    }

    private func optionRespectingAnimationPolicy(_ option: [String: Any]) -> [String: Any] {
        guard !animationsEnabled else { return option }
        return disablingAllAnimations(in: option)
    }

    private func disablingAllAnimations(in option: [String: Any]) -> [String: Any] {
        var result = option
        result["animation"] = false
        // Series options may explicitly enable animation (gauge-clock), and treemap's merged default
        // does so too. A force-off UI policy must win over both, including notMerge drive updates.
        if var series = result["series"] as? [String: Any] {
            series["animation"] = false
            result["series"] = series
        }
        else if let series = result["series"] as? [[String: Any]] {
            result["series"] = series.map { item in
                var item = item; item["animation"] = false; return item
            }
        }
        // Timeline/media wrappers resolve their own option trees rather than inheriting the outer bag.
        if let base = result["baseOption"] as? [String: Any] {
            result["baseOption"] = disablingAllAnimations(in: base)
        }
        if let snapshots = result["options"] as? [[String: Any]] {
            result["options"] = snapshots.map(disablingAllAnimations)
        }
        return result
    }

    override func layout() {
        super.layout()
        let size = bounds.size
        if size.width <= 0 || size.height <= 0 { return }
        painter.rootLayer.frame = CGRect(origin: .zero, size: size)
        // EChartsView has no resize() of its own; resize the underlying zr (painter + Handler)
        // directly, exactly like macOS ZRenderView.layout() does.
        var opt = ZRenderResizeOpt()
        opt.width = Double(size.width)
        opt.height = Double(size.height)
        echartsView.zr.resize(opt)
        echartsView.zr.refresh()
    }

    // Pointer -> proxy so hover/tooltip/emphasis (already wired in EChartsView) work live.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
            options: [.activeInActiveApp, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        // Pointer moves are forwarded directly; ZRenderView's per-frame coalescing is not ported here.
        proxy.mousemove(makeMouseEvent("mousemove", event, which: 0))
    }

    override func mouseExited(with event: NSEvent) {
        proxy.mouseout(makeMouseEvent("mouseout", event, which: 0))
    }

    override func mouseDown(with event: NSEvent) {
        proxy.mousedown(makeMouseEvent("mousedown", event, which: 1))
    }

    override func mouseDragged(with event: NSEvent) {
        proxy.mousemove(makeMouseEvent("mousemove", event, which: 1))
    }

    override func mouseUp(with event: NSEvent) {
        let e = makeMouseEvent("mouseup", event, which: 1)
        proxy.mouseup(e)
        if event.clickCount >= 2 {
            proxy.dblclick(makeMouseEvent("dblclick", event, which: 1))
        } else {
            proxy.click(makeMouseEvent("click", event, which: 1))
        }
    }

    override func scrollWheel(with event: NSEvent) {
        let e = makeMouseEvent("mousewheel", event, which: 0)
        e.zrDelta = Double(event.scrollingDeltaY)
        proxy.wheel(e)
    }

    private func makeMouseEvent(_ type: String, _ event: NSEvent, which: Double) -> ZRRawEvent {
        let p = convert(event.locationInWindow, from: nil)
        let e = ZRRawEvent()
        e.type = type
        e.zrX = Double(p.x)
        e.zrY = Double(p.y)
        e.clientX = Double(p.x)
        e.clientY = Double(p.y)
        e.which = which
        e.button = which > 0 ? which - 1 : nil
        return e
    }
}

// MARK: - EChartsDemoChart: the native pane's `myChart`
//
// An official example's behaviour is often a timeline, not an option (map-bar-morph flips a map
// series and a bar series every 2s). The demo carries a `drive` closure that replays that timeline;
// this is the handle it drives. Timers are retained by the view and invalidated in `deinit`, so a
// demo the user has navigated away from stops setOption-ing a disposed chart.
extension EChartsHostView: EChartsDemoChart {

    func setOption(_ option: [String: Any], notMerge: Bool) {
        echartsView.setOption(optionRespectingAnimationPolicy(option), notMerge: notMerge)
    }

    func appendData(seriesIndex: Int, data: [Double]) {
        guard !isDisposed else { return }
        echartsView.ec.appendData(seriesIndex: seriesIndex, data: data.map { $0 as Any })
        echartsView.syncAfterAction()
    }

    /// The example's `setInterval(fn, ms)`.
    func every(_ seconds: Double, _ body: @escaping @MainActor () -> Void) {
        guard !isDisposed else { return }
        let t = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, !self.isDisposed else { timer.invalidate(); return }
                body()
            }
        }
        driveTimers.append(t)
    }

    /// The example's `setTimeout(fn, ms)`.
    func after(_ seconds: Double, _ body: @escaping @MainActor () -> Void) {
        guard !isDisposed else { return }
        let t = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, !self.isDisposed else { return }
                defer { self.driveTimers.removeAll { $0 === timer } }
                body()
            }
        }
        driveTimers.append(t)
    }

    /// The example's `myChart.dispatchAction({ type: 'brush', ... })`. The JS payload is a bag; the
    /// port's `Payload` is a struct with a `type` plus an `other` dictionary for everything else, so
    /// map it that way.
    func dispatch(_ payload: [String: Any]) {
        guard let type = payload["type"] as? String else { return }
        var p = Payload(type: type)
        p.other = payload.filter { $0.key != "type" }
        echartsView.ec.dispatchAction(p)
        echartsView.syncAfterAction()   // the action mutated the model; pull it back into the zr scene
    }

    func convertToPixel(_ finder: ModelFinder, _ value: CoordinateSystemDataCoord) -> Any? {
        echartsView.ec.convertToPixel(finder, value)
    }

    func convertFromPixel(_ finder: ModelFinder, _ value: [Double]) -> Any? {
        echartsView.ec.convertFromPixel(finder, value)
    }

    /// The example's `myChart.on('click', params => ...)`. Forwards to the ported chart event bus
    /// (`ECharts.on` — `Eventful` + `MessageCenter`, echarts.ts `_initEvents`).
    ///
    /// The zr pointer events that feed this bus are already delivered on the main thread (they come
    /// from this NSView's mouse handlers → `NativeHandlerProxy` → `zr.handler`), so hopping is not
    /// needed; `MainActor.assumeIsolated` states that invariant rather than deferring the call (a demo
    /// handler that re-enters `setOption` must run BEFORE the click returns, as it does in JS).
    ///
    /// After the handler runs, the scene is re-pulled: a handler that `dispatchAction`s (or otherwise
    /// mutates the model) goes through `ECharts` directly, and — as with `dispatch` above — the zr copy
    /// of the display list has to be refreshed. `setOption` on this host already syncs itself; a second
    /// sync is idempotent.
    func on(_ event: String, _ handler: @escaping @MainActor (ECEventParams) -> Void) {
        echartsView.on(event) { [weak self] params in
            MainActor.assumeIsolated {
                handler(params)
                self?.echartsView.syncAfterAction()
            }
        }
    }
}
#endif
