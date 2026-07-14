// Live native host for the gallery: an NSView that hosts an EChartsView + CALayerPainter and
// drives its zr.animation on a frame clock — the animated analog of the static native image pane.
// Mirrors NativePainter/ZRenderView.swift's AnimationLoop -> zr.animation.update() -> zr._flush ->
// painter.refresh chain, but the content is an echarts option instead of a raw zr scene.
//
// Placement: this target already depends on EChartsKit + NativePainter. It cannot live in
// NativePainter (which does not depend on EChartsKit); promoting it to a shared module is a
// follow-up when the real app needs it.
//
// DEVIATIONS from the task brief's illustrative snippet (verified against the real sources per
// CONVENTIONS — do not invent APIs):
//   - `EChartsView` has NO `.resize(_:_:_:)` method (that signature only exists on `HeadlessPainter`
//     in EChartsKit/core/EChartsView.swift). The real resize path — exactly like macOS `ZRenderView`
//     (NativePainter/ZRenderView.swift:378-388) — is `echartsView.zr.resize(ZRenderResizeOpt)` followed
//     by `echartsView.zr.refresh()`; that resizes the painter + Handler. Note `ECharts`'s own
//     width/height (the chart layout box) has no public resize hook, so the echarts layout itself does
//     not re-flow on a live resize yet — out of scope for this task.
//   - `ZRRawEvent` has NO `init(zrX:zrY:)` convenience initializer; it is a plain `ZRRawEvent()` with
//     mutable stored properties (`Sources/ZRenderKit/Core/event.swift:82`). Mouse events are built the
//     same way `ZRenderView.makeMouseEvent` does: construct `ZRRawEvent()`, set `.type`, `.zrX`, `.zrY`,
//     `.clientX`, `.clientY`, `.which`, `.button`.
//   - `NativeHandlerProxy.mousedown/mousemove/mouseup` are real (`Sources/NativePainter/ZRenderView.swift:93-95`)
//     and take a `ZRRawEvent`, matching the brief. Also wired `click`/`dblclick` on mouseUp and
//     `scrollWheel` -> `proxy.wheel`, mirroring `ZRenderView`'s macOS block, so hover/tooltip/emphasis
//     (already wired in EChartsView's `_initEvents`) work live in the gallery, not just ripple animation.
#if canImport(AppKit)
import AppKit
import ZRenderKit
import NativePainter
import EChartsKit
import EChartsDemoCore

final class EChartsHostView: NSView {

    let echartsView: EChartsView
    /// `CALayerPainter` by default; an alternative backend (the Metal `RasterizerPainter`)
    /// can be injected at init — same seam as `ZRenderView`.
    private let painter: LayerHostedPainter
    private let proxy: NativeHandlerProxy
    private let animationLoop: AnimationLoop
    /// Timers a demo's `drive` hook scheduled (the native side of the example's setInterval /
    /// setTimeout). Owned here so they die with the view — the gallery builds a fresh host per demo,
    /// and a leaked timer would keep setOption-ing a disposed chart.
    private var driveTimers: [Timer] = []

    init(frame: CGRect, dpr: Double? = nil, painter injected: LayerHostedPainter? = nil) {
        let size = frame.size == .zero ? CGSize(width: 1, height: 1) : frame.size
        let painter = injected ?? CALayerPainter(size: size, dpr: dpr, backgroundColor: NSColor.white.cgColor)
        let proxy = NativeHandlerProxy()
        let ecView = EChartsView(width: Double(size.width), height: Double(size.height),
                                 painter: painter, proxy: proxy)

        self.painter = painter
        self.proxy = proxy
        self.echartsView = ecView
        self.animationLoop = AnimationLoop(animation: ecView.zr.animation)

        super.init(frame: frame)

        self.wantsLayer = true
        self.layer?.addSublayer(painter.rootLayer)
        self.animationLoop.start()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        self.driveTimers.forEach { $0.invalidate() }
        self.animationLoop.stop()
        self.echartsView.zr.dispose()
    }

    // Top-left / y-down, matching zrender + the flipped AppKit root layer.
    override var isFlipped: Bool { true }

    func setOption(_ option: [String: Any]) {
        self.echartsView.setOption(option)
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
            options: [.activeInActiveApp, .mouseMoved, .inVisibleRect], owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        // Pointer moves are forwarded directly; ZRenderView's per-frame coalescing is not ported here.
        proxy.mousemove(makeMouseEvent("mousemove", event, which: 0))
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
        echartsView.setOption(option, notMerge: notMerge)
    }

    /// The example's `setInterval(fn, ms)`.
    func every(_ seconds: Double, _ body: @escaping @MainActor () -> Void) {
        let t = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { _ in
            MainActor.assumeIsolated { body() }
        }
        driveTimers.append(t)
    }

    /// The example's `setTimeout(fn, ms)`.
    func after(_ seconds: Double, _ body: @escaping @MainActor () -> Void) {
        let t = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in
            MainActor.assumeIsolated { body() }
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
