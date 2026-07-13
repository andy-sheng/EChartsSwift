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

final class EChartsHostView: NSView {

    let echartsView: EChartsView
    /// `CALayerPainter` by default; an alternative backend (the Metal `RasterizerPainter`)
    /// can be injected at init — same seam as `ZRenderView`.
    private let painter: LayerHostedPainter
    private let proxy: NativeHandlerProxy
    private let animationLoop: AnimationLoop

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
#endif
