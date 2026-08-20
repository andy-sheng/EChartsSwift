// Live native host for the iOS gallery: a UIView that hosts an EChartsView + CALayerPainter and
// drives its zr.animation on a CADisplayLink frame clock — the UIKit twin of the macOS gallery's
// EChartsHostView (Sources/EChartsDemoGallery/EChartsHostView.swift). Mirrors NativePainter's iOS
// ZRenderView (Sources/NativePainter/ZRenderView.swift:173-306) for the touch → ZRRawEvent →
// NativeHandlerProxy pipeline, but the content is an echarts option instead of a raw zr scene.
//
// Placement: this target already depends on EChartsKit + NativePainter. It cannot live in
// NativePainter (which does not depend on EChartsKit); promoting it to a shared module is a
// follow-up when the real app needs it (same note as the macOS host).
//
// Sizing: unlike the macOS host (which is created once and live-resized), the iOS gallery creates a
// fresh host per demo at the demo's LOGICAL size and scale-to-fits it via transform (see FitBox in
// Entry.swift). `ECharts` has no public resize hook — the chart lays out at its init size — so
// fixing the host at demo.width × demo.height keeps the native layout box identical to the web
// pane's fixed-size div, which the viewport meta scales the same way. Touch coordinates stay in the
// logical space automatically (UIKit routes touches through the transform).
#if canImport(UIKit)
import UIKit
import ZRenderKit
import NativePainter
import EChartsKit
import EChartsDemoCore

final class EChartsHostView: UIView {

    let echartsView: EChartsView
    private let painter: CALayerPainter
    private let proxy: NativeHandlerProxy
    private let animationLoop: AnimationLoop
    private var driveTimers: [Timer] = []
    private var isDisposed = false
    /// Disable ECharts interpolation without stopping the demo's data/timer progression.
    var animationsEnabled = true

    init(frame: CGRect, dpr: Double? = nil) {
        let size = frame.size == .zero ? CGSize(width: 1, height: 1) : frame.size
        let painter = CALayerPainter(size: size, dpr: dpr, backgroundColor: UIColor.white.cgColor)
        let proxy = NativeHandlerProxy()
        let ecView = EChartsView(width: Double(size.width), height: Double(size.height),
                                 painter: painter, proxy: proxy, useCoarsePointer: true)

        self.painter = painter
        self.proxy = proxy
        self.echartsView = ecView
        self.animationLoop = AnimationLoop(animation: ecView.zr.animation)

        super.init(frame: frame)

        self.isMultipleTouchEnabled = true
        self.layer.addSublayer(painter.rootLayer)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        self.addGestureRecognizer(pinch)

        self.animationLoop.start()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    deinit {
        dispose()
    }

    /// Stop all per-demo work explicitly. Timer callbacks commonly capture the chart passed to the
    /// demo, so waiting for `deinit` would leave a host -> timer -> host cycle running forever.
    func dispose() {
        guard !isDisposed else { return }
        isDisposed = true
        driveTimers.forEach { $0.invalidate() }
        driveTimers.removeAll()
        animationLoop.stop()
        echartsView.dispose()
    }

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
        if var series = result["series"] as? [String: Any] {
            series["animation"] = false
            result["series"] = series
        }
        else if let series = result["series"] as? [[String: Any]] {
            result["series"] = series.map { item in
                var item = item; item["animation"] = false; return item
            }
        }
        if let base = result["baseOption"] as? [String: Any] {
            result["baseOption"] = disablingAllAnimations(in: base)
        }
        if let snapshots = result["options"] as? [[String: Any]] {
            result["options"] = snapshots.map(disablingAllAnimations)
        }
        return result
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = bounds.size
        if size.width <= 0 || size.height <= 0 { return }
        painter.rootLayer.frame = CGRect(origin: .zero, size: size)
        // EChartsView has no resize() of its own; resize the underlying zr (painter + Handler)
        // directly, exactly like the iOS ZRenderView.layoutSubviews() does.
        var opt = ZRenderResizeOpt()
        opt.width = Double(size.width)
        opt.height = Double(size.height)
        echartsView.zr.resize(opt)
        echartsView.zr.refresh()
    }

    // MARK: Touch capture → normalized ZRRawEvent → proxy (verbatim from iOS ZRenderView)

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        proxy.touchstart(makeTouchEvent("touchstart", touches, event))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        proxy.touchmove(makeTouchEvent("touchmove", touches, event))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        proxy.touchend(makeTouchEvent("touchend", touches, event))
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        proxy.touchcancel(makeTouchEvent("touchend", touches, event))
    }

    /// Build a `ZRRawEvent` already normalized into ZRender-local coordinates (UIView space is
    /// top-left / y-down, matching zrender's coordinate convention, so no flip is needed). The
    /// primary touch drives `zrX`/`zrY`; every active touch is copied into `touches` so
    /// `Handler.processGesture` (GestureMgr) can recognize a pinch.
    private func makeTouchEvent(_ type: String, _ changed: Set<UITouch>, _ uiEvent: UIEvent?) -> ZRRawEvent {
        let e = ZRRawEvent()
        e.type = type

        let allTouches = uiEvent?.allTouches ?? changed
        // Prefer a non-ended touch for the anchor; fall back to a changed touch (e.g. touchend).
        let primary = allTouches.first(where: { $0.phase != .ended && $0.phase != .cancelled }) ?? changed.first
        if let primary = primary {
            let p = primary.location(in: self)
            e.zrX = Double(p.x)
            e.zrY = Double(p.y)
            e.clientX = Double(p.x)
            e.clientY = Double(p.y)
        }
        e.which = 1

        var list: [Touch] = []
        for t in allTouches where t.phase != .ended && t.phase != .cancelled {
            let p = t.location(in: self)
            list.append(Touch(clientX: Double(p.x), clientY: Double(p.y)))
        }
        // On touchend the changed touch may already be in `.ended`; ensure `touches` is non-empty so
        // GestureMgr's final track is recorded.
        if list.isEmpty, let primary = primary {
            let p = primary.location(in: self)
            list.append(Touch(clientX: Double(p.x), clientY: Double(p.y)))
        }
        e.touches = list
        e.targetTouches = list
        e.changedTouches = changed.map { t in
            let p = t.location(in: self)
            return Touch(clientX: Double(p.x), clientY: Double(p.y))
        }
        return e
    }

    @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
        let c = g.location(in: self)
        let e = ZRRawEvent()
        e.type = "pinch"
        e.zrX = Double(c.x)
        e.zrY = Double(c.y)
        e.clientX = Double(c.x)
        e.clientY = Double(c.y)
        e.pinchX = Double(c.x)
        e.pinchY = Double(c.y)
        e.pinchScale = Double(g.scale)
        proxy.pinch(e)
        // Reset so each delta is reported relative to the last (matches the per-step pinch ratio the
        // GestureMgr recognizer produces from successive touch frames).
        g.scale = 1
    }
}

extension EChartsHostView: EChartsDemoChart {
    func setOption(_ option: [String: Any], notMerge: Bool) {
        echartsView.setOption(optionRespectingAnimationPolicy(option), notMerge: notMerge)
    }

    func appendData(seriesIndex: Int, data: [Double]) {
        guard !isDisposed else { return }
        echartsView.ec.appendData(seriesIndex: seriesIndex, data: data.map { $0 as Any })
        echartsView.syncAfterAction()
    }

    func every(_ seconds: Double, _ body: @escaping @MainActor () -> Void) {
        guard !isDisposed else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, !self.isDisposed else { timer.invalidate(); return }
                body()
            }
        }
        driveTimers.append(timer)
    }

    func after(_ seconds: Double, _ body: @escaping @MainActor () -> Void) {
        guard !isDisposed else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self, !self.isDisposed else { return }
                defer { self.driveTimers.removeAll { $0 === timer } }
                body()
            }
        }
        driveTimers.append(timer)
    }

    func dispatch(_ payload: [String: Any]) {
        guard let type = payload["type"] as? String else { return }
        var action = Payload(type: type)
        action.other = payload.filter { $0.key != "type" }
        echartsView.ec.dispatchAction(action)
        echartsView.syncAfterAction()
    }

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
