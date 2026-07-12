// Ported from zrender/src/core/GestureMgr.ts — keep in sync with upstream

/**
 * Only implements needed gestures for mobile.
 */

// PORT-NOTE: upstream `import * as eventUtil from './event'` — event.swift (clientToLocal) is
// ported, but the DOM coordinate mapping is the native event seam (CONVENTIONS §9); the
// UIKit bridge supplies touch points already in ZRender-local coordinates, so this file keeps a
// local passthrough `clientToLocal` (below) rather than using event.swift's.
// PORT-NOTE: upstream `import { ZRRawTouchEvent, ZRPinchEvent, Dictionary } from './types'` —
// ZRRawTouchEvent / ZRPinchEvent are browser DOM event types (PORT-NOTE in types.swift). They
// are modeled here as native seam types (`Touch`, `ZRRawTouchEvent`). `Dictionary` comes from
// types.swift.

// PORT-NOTE: browser `Touch` — native event seam. The UIKit bridge populates these; upstream
// reads `touch.clientX/clientY` and converts via `clientToLocal`.
public struct Touch {
    public var clientX: Double
    public var clientY: Double

    public init(clientX: Double, clientY: Double) {
        self.clientX = clientX
        self.clientY = clientY
    }
}

// PORT-NOTE: browser `HTMLElement` root — native event seam (CONVENTIONS §9). Upstream passes
// the container element to `clientToLocal`; the native bridge owns coordinate context.
public protocol GestureRoot: AnyObject {}

// PORT-NOTE: merges browser `ZRRawTouchEvent` (which carries `touches`) and `ZRPinchEvent`
// (the `event as ZRPinchEvent` cast in the pinch recognizer, which writes `pinchScale`/
// `pinchX`/`pinchY`). Modeled as a `final class` so the in-place mutation in `pinch` is
// visible to the caller, matching the browser event object's reference semantics.
public final class ZRRawTouchEvent {
    public var touches: [Touch]?

    // ZRPinchEvent properties (written by the `pinch` recognizer).
    public var pinchScale: Double = 0
    public var pinchX: Double = 0
    public var pinchY: Double = 0
    public var gestureEvent: String?

    public init(touches: [Touch]? = nil) {
        self.touches = touches
    }
}

struct TrackItem {
    var points: [[Double]]
    var touches: [Touch]
    var target: Displayable
    var event: ZRRawTouchEvent
}

public final class GestureMgr {

    private var _track: [TrackItem] = []

    public init() {}

    public func recognize(_ event: ZRRawTouchEvent, _ target: Displayable, _ root: GestureRoot?) -> GestureInfo? {
        self._doTrack(event, target, root)
        return self._recognize(event)
    }

    @discardableResult
    public func clear() -> GestureMgr {
        self._track.removeAll()
        return self
    }

    func _doTrack(_ event: ZRRawTouchEvent, _ target: Displayable, _ root: GestureRoot?) {
        let touches = event.touches

        guard let touches = touches else {
            return
        }

        var trackItem = TrackItem(
            points: [],
            touches: [],
            target: target,
            event: event
        )

        var i = 0
        let len = touches.count
        while i < len {
            let touch = touches[i]
            let pos = clientToLocal(root, touch)
            trackItem.points.append([pos.zrX, pos.zrY])
            trackItem.touches.append(touch)
            i += 1
        }

        self._track.append(trackItem)
    }

    func _recognize(_ event: ZRRawTouchEvent) -> GestureInfo? {
        for eventName in recognizers.keys {
            if let recognizer = recognizers[eventName] {
                let gestureInfo = recognizer(self._track, event)
                if let gestureInfo = gestureInfo {
                    return gestureInfo
                }
            }
        }
        return nil
    }
}

// PORT-NOTE: eventUtil.clientToLocal (zrender/src/core/event.ts) maps client coords to
// ZRender-local (zrX/zrY) via the root element's bounding box. event.swift is ported, but the
// native UIKit bridge supplies touch points already in local coordinates, so this seam returns
// them unchanged. See CONVENTIONS §9.
private func clientToLocal(_ root: GestureRoot?, _ touch: Touch) -> (zrX: Double, zrY: Double) {
    return (touch.clientX, touch.clientY)
}

private func dist(_ pointPair: [[Double]]) -> Double {
    let dx = pointPair[1][0] - pointPair[0][0]
    let dy = pointPair[1][1] - pointPair[0][1]

    return (dx * dx + dy * dy).squareRoot()
}

private func center(_ pointPair: [[Double]]) -> [Double] {
    return [
        (pointPair[0][0] + pointPair[1][0]) / 2,
        (pointPair[0][1] + pointPair[1][1]) / 2
    ]
}

// PORT-NOTE: upstream Recognizer returns `{ type, target, event }`; modeled as a struct.
public struct GestureInfo {
    public var type: String
    public var target: Displayable
    public var event: ZRRawTouchEvent
}

typealias Recognizer = (_ tracks: [TrackItem], _ event: ZRRawTouchEvent) -> GestureInfo?

private let recognizers: Dictionary<Recognizer> = [

    "pinch": { (tracks: [TrackItem], event: ZRRawTouchEvent) -> GestureInfo? in
        let trackLen = tracks.count

        if trackLen == 0 {
            return nil
        }

        let pinchEnd = tracks.count >= 1 ? tracks[trackLen - 1].points : nil
        // (tracks[trackLen - 2] || {}).points || pinchEnd
        let pinchPre = (trackLen - 2 >= 0 ? tracks[trackLen - 2].points : nil) ?? pinchEnd

        if let pinchPre = pinchPre,
           pinchPre.count > 1,
           let pinchEnd = pinchEnd,
           pinchEnd.count > 1 {
            var pinchScale = dist(pinchEnd) / dist(pinchPre)
            if !pinchScale.isFinite { pinchScale = 1 }

            event.pinchScale = pinchScale

            let pinchCenter = center(pinchEnd)
            event.pinchX = pinchCenter[0]
            event.pinchY = pinchCenter[1]

            return GestureInfo(
                type: "pinch",
                target: tracks[0].target,
                event: event
            )
        }
        return nil
    }

    // Only pinch currently.
]
