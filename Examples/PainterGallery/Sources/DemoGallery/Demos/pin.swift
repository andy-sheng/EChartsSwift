import ZRenderKit
import Foundation
// Faithful port of zrender test/pin.html  (canvas 1000x500)
//
// Upstream defines a custom shape via `zrender.Path.extend({ type:'pin', shape, buildPath })` and adds
// ONE instance: shape { x:100, y:100, width:20, height:40 }, scale [2,2], default (black) fill.
// `Path` is now `open`, so this is a REAL `Path` subclass whose `buildPath` emits the SAME PathProxy
// commands as the html (head `arc` + two cubic `bezierCurveTo` flanks to the cusp + `closePath`) —
// a 1:1 translation of the html's `<script>`, not a sampled approximation.

// var Pin = zrender.Path.extend({ type:'pin', shape: { x, y, width, height }, buildPath })
struct PinShape: PathShape {
    var x: Double = 0       // x, y on the cusp
    var y: Double = 0
    var width: Double = 0
    var height: Double = 0
    init() {}

    func animationGet(_ key: String) -> Any? {
        switch key {
        case "x": return x
        case "y": return y
        case "width": return width
        case "height": return height
        default: return nil
        }
    }
    mutating func animationSet(_ key: String, _ value: Any?) {
        guard let v = value as? Double else { return }
        switch key {
        case "x": x = v
        case "y": y = v
        case "width": width = v
        case "height": height = v
        default: break
        }
    }
}

final class Pin: Path {
    // NOTE: `Path.init` is `public` (not `open`), so it can't be overridden across the module
    // boundary; `type = "pin"` is set at the call site instead. The custom geometry comes through the
    // two `open` override points — `getDefaultShape` (the PinShape default) and `buildPath`.
    override func getDefaultShape() -> PathShape { PinShape() }

    override func buildPath(_ path: PathProxy, _ shape: PathShape, _ inBatch: Bool) {
        let shape = shape as! PinShape
        let x = shape.x
        let y = shape.y
        let w = shape.width / 5 * 3
        // Height must be larger than width
        let h = Swift.max(w, shape.height)
        let r = w / 2

        // Dist on y with tangent point and circle center
        let dy = r * r / (h - r)
        let cy = y - h + r + dy
        let angle = asin(dy / r)
        // Dist on x with tangent point and circle center
        let dx = cos(angle) * r

        let tanX = sin(angle)
        let tanY = cos(angle)

        _ = path.arc(
            x, cy, r,
            Double.pi - angle,
            Double.pi * 2 + angle
        )

        let cpLen = r * 0.6
        let cpLen2 = r * 0.7
        _ = path.bezierCurveTo(
            x + dx - tanX * cpLen, cy + dy + tanY * cpLen,
            x, y - cpLen2,
            x, y
        )
        _ = path.bezierCurveTo(
            x, y - cpLen2,
            x - dx + tanX * cpLen, cy + dy + tanY * cpLen,
            x - dx, cy + dy
        )
        _ = path.closePath()
    }
}

extension DemoRegistry {
    static let demo_pin: Demo = Demo(
        name: "pin", category: "Shapes",
        summary: "A single map-pin (real Path subclass: arc + 2× bezierCurveTo), shape 20×40, scale 2×",
        width: 1000, height: 500
    ) { zr in
        // new Pin({ shape: { x:100, y:100, width:20, height:40 }, scale: [2, 2] })
        var s = PinShape(); s.x = 100; s.y = 100; s.width = 20; s.height = 40
        let pin = Pin(); pin.type = "pin"; pin.setShape(s)
        pin.scaleX = 2; pin.scaleY = 2          // scale: [2, 2]
        zr.add(pin)                              // no style set → default (black) fill, as in the html
    }
}
