// Apple container for echarts.init / zrender.init. Painter-independent input and frame clock.
import Foundation
import ZRenderKit
import ApplePainterSupport

public enum NativeChartHostError: Error {
    case requiresLayerHostedPainter
    case alreadyAttached
}

#if canImport(UIKit)
import UIKit
public typealias NativeChartHostView = UIView
#elseif canImport(AppKit)
import AppKit
public typealias NativeChartHostView = NSView
#endif

#if canImport(UIKit) || canImport(AppKit)
public final class NativeChartHost: NativeChartHostView, ZRenderHost {
    private weak var zr: ZRender?
    private let proxy = NativeHandlerProxy()
    private var animationLoop: AnimationLoop?
    public var handlerProxy: HandlerProxyInterface? { proxy }
    public var width: Double { Double(bounds.width) }
    public var height: Double { Double(bounds.height) }
    public var devicePixelRatio: Double {
        #if canImport(UIKit)
        return Double(window?.screen.scale ?? UIScreen.main.scale)
        #else
        return Double(window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
        #endif
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        #if canImport(UIKit)
        isMultipleTouchEnabled = true
        addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:))))
        #else
        wantsLayer = true
        addGestureRecognizer(NSMagnificationGestureRecognizer(target: self, action: #selector(magnify(_:))))
        #endif
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    public func attach(_ zr: ZRender) throws {
        guard self.zr == nil || self.zr?.isDisposed == true else { throw NativeChartHostError.alreadyAttached }
        guard let painter = zr.painter as? LayerHostedPainter else {
            throw NativeChartHostError.requiresLayerHostedPainter
        }
        self.zr = zr
        painter.rootLayer.anchorPoint = .zero
        painter.rootLayer.frame = CGRect(x: 0, y: 0, width: painter.getWidth(), height: painter.getHeight())
        #if canImport(UIKit)
        layer.addSublayer(painter.rootLayer)
        #else
        layer?.addSublayer(painter.rootLayer)
        #endif
        animationLoop = AnimationLoop { [weak zr] in
            guard let zr, !zr.isDisposed else { return }
            zr.animation.update()
        }
        animationLoop?.start()
    }

    public func detach(_ zr: ZRender) {
        guard self.zr === zr else { return }
        animationLoop?.stop()
        animationLoop = nil
        (zr.painter as? LayerHostedPainter)?.rootLayer.removeFromSuperlayer()
        self.zr = nil
    }

    deinit { animationLoop?.stop() }

    private func event(_ type: String, _ point: CGPoint, which: Int = 0) -> ZRRawEvent {
        let event = ZRRawEvent()
        event.type = type
        event.zrX = Double(point.x)
        event.zrY = Double(point.y)
        event.clientX = Double(point.x)
        event.clientY = Double(point.y)
        event.which = Double(which)
        event.button = which == 1 ? 0 : (which == 3 ? 2 : -1)
        return event
    }

    #if canImport(UIKit)
    public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        proxy.touchstart(self.event("touchstart", touch.location(in: self), which: 1))
    }
    public override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        proxy.touchmove(self.event("touchmove", touch.location(in: self), which: 1))
    }
    public override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        proxy.touchend(self.event("touchend", touch.location(in: self), which: 1))
    }
    public override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        proxy.touchcancel(self.event("touchcancel", touch.location(in: self)))
    }
    @objc private func pinch(_ gesture: UIPinchGestureRecognizer) {
        let event = self.event("pinch", gesture.location(in: self))
        event.pinchScale = Double(gesture.scale)
        event.pinchX = event.zrX
        event.pinchY = event.zrY
        proxy.pinch(event)
        gesture.scale = 1
    }
    #else
    public override var isFlipped: Bool { true }
    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero,
            options: [.activeInActiveApp, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect], owner: self))
    }
    private func mouse(_ type: String, _ e: NSEvent, which: Int = 0) -> ZRRawEvent {
        let raw = event(type, convert(e.locationInWindow, from: nil), which: which)
        raw.shiftKey = e.modifierFlags.contains(.shift)
        raw.ctrlKey = e.modifierFlags.contains(.control)
        raw.altKey = e.modifierFlags.contains(.option)
        return raw
    }
    public override func mouseMoved(with e: NSEvent) { proxy.mousemove(mouse("mousemove", e)) }
    public override func mouseDragged(with e: NSEvent) { proxy.mousemove(mouse("mousemove", e, which: 1)) }
    public override func mouseDown(with e: NSEvent) { proxy.mousedown(mouse("mousedown", e, which: 1)) }
    public override func mouseUp(with e: NSEvent) {
        proxy.mouseup(mouse("mouseup", e, which: 1))
        proxy.click(mouse("click", e, which: 1))
        if e.clickCount == 2 { proxy.dblclick(mouse("dblclick", e, which: 1)) }
    }
    public override func mouseExited(with e: NSEvent) { proxy.mouseout(mouse("mouseout", e)) }
    public override func rightMouseUp(with e: NSEvent) { proxy.contextmenu(mouse("contextmenu", e, which: 3)) }
    public override func scrollWheel(with e: NSEvent) {
        let raw = mouse("mousewheel", e)
        raw.zrDelta = Double(e.scrollingDeltaY) / 120
        proxy.wheel(raw)
    }
    @objc private func magnify(_ gesture: NSMagnificationGestureRecognizer) {
        let raw = event("pinch", gesture.location(in: self))
        raw.pinchScale = 1 + Double(gesture.magnification)
        raw.pinchX = raw.zrX
        raw.pinchY = raw.zrY
        proxy.pinch(raw)
        gesture.magnification = 0
    }
    #endif
}
#endif
