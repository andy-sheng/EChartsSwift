// NativePainter — host frame-clock driver. NOT a translation.
//
// zrender's `Animation` expects the *host* to supply the per-frame tick that the browser
// provides via `requestAnimationFrame` (see Animation.swift `_startLoop` / the
// `requestAnimationFrame` PORT-NOTE). This file is that platform glue: a small driver that
// pumps `Animation.update()` on a real frame clock and lets the resulting `stage.update`
// flow drive a `CALayerPainter` refresh (`Animation.update -> stage.update -> ZRender._flush
// -> _refresh -> painter.refresh`).
//
// Clock source:
//   - iOS / tvOS:  CADisplayLink (vsync-aligned).
//   - macOS:       a main-run-loop Timer fallback (~60 Hz). (A CVDisplayLink could be used
//                  for vsync alignment, but it fires on a background thread and would need a
//                  hop back to the main thread; the Timer keeps this minimal and main-bound.)
//
// Keep it minimal: it only owns the frame clock and calls a per-frame closure.

import Foundation

#if canImport(QuartzCore)
import QuartzCore   // CACurrentMediaTime / CADisplayLink
#endif

import ZRenderKit

#if (os(iOS) || os(tvOS) || os(macOS)) && canImport(QuartzCore)

public final class AnimationLoop {

    /// Called once per frame on the main thread.
    private let onFrame: () -> Void

    private var running = false

    #if os(iOS) || os(tvOS)
    private var displayLink: CADisplayLink?
    private var proxy: _DisplayLinkProxy?
    #elseif os(macOS)
    private var timer: Timer?
    #endif

    /// Drive an arbitrary per-frame callback.
    public init(_ onFrame: @escaping () -> Void) {
        self.onFrame = onFrame
    }

    /// Convenience: drive a zrender `Animation` directly. Equivalent to the browser's
    /// `requestAnimationFrame(step)` recursion calling `self.update()` each frame, which
    /// triggers the `'frame'` event + `stage.update` (the painter refresh on the native path).
    public convenience init(animation: Animation) {
        self.init { animation.update() }
    }

    /// The host monotonic clock, in milliseconds (matches `getTime()`'s unit in Animation.swift).
    public static func getTime() -> Double {
        return CACurrentMediaTime() * 1000
    }

    /// Begin driving frames. Idempotent.
    public func start() {
        if running { return }
        running = true

        #if os(iOS) || os(tvOS)
        let proxy = _DisplayLinkProxy { [weak self] in self?.tick() }
        let link = CADisplayLink(target: proxy, selector: #selector(_DisplayLinkProxy.onFrame(_:)))
        link.add(to: .main, forMode: .common)
        self.proxy = proxy
        self.displayLink = link
        #elseif os(macOS)
        // Timer fallback (~60 Hz) on the main run loop.
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        #endif
    }

    /// Stop driving frames and release the clock. Idempotent.
    public func stop() {
        if !running { return }
        running = false

        #if os(iOS) || os(tvOS)
        displayLink?.invalidate()
        displayLink = nil
        proxy = nil
        #elseif os(macOS)
        timer?.invalidate()
        timer = nil
        #endif
    }

    private func tick() {
        if !running { return }
        onFrame()
    }

    deinit {
        stop()
    }
}

#if os(iOS) || os(tvOS)
/// CADisplayLink retains its target and needs an `@objc` selector; this thin proxy keeps
/// `AnimationLoop` free of `NSObject` and breaks the retain cycle (the proxy weakly calls back).
private final class _DisplayLinkProxy: NSObject {
    private let callback: () -> Void
    init(_ callback: @escaping () -> Void) {
        self.callback = callback
    }
    @objc func onFrame(_ link: CADisplayLink) {
        callback()
    }
}
#endif

#endif
