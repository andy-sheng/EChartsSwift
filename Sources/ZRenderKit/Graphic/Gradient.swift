// Ported from zrender/src/graphic/Gradient.ts — keep in sync with upstream

// TODO Should GradientObject been LinearGradientObject | RadialGradientObject
public protocol GradientObject {

    var id: Double? { get set }

    var type: String { get set }

    var colorStops: [GradientColorStop] { get set }

    var global: Bool? { get set }
}

public protocol InnerGradientObject: GradientObject {
    // upstream `__canvasGradient: CanvasGradient` is a canvas-backend cache field with no
    // native analogue — NativePainter renders gradients directly via `CGGradient`
    // (CGRenderer.makeCGGradient), so this field is intentionally omitted.
    var __width: Double { get set }
    var __height: Double { get set }
}

public struct GradientColorStop {
    public var offset: Double
    public var color: String

    public init(offset: Double, color: String) {
        self.offset = offset
        self.color = color
    }
}

// Non-final `class` (not `final`) because LinearGradient/RadialGradient `extends Gradient`
// (CONVENTIONS §2). Subclasses are declared `final class`.
public class Gradient {

    public var id: Double?

    // upstream declares `type: string` but the Gradient constructor never assigns it
    // (subclasses set 'linear'/'radial'). Swift requires a stored-prop initial value, so we
    // default to "" — overwritten by every subclass before use.
    public var type: String = ""

    public var colorStops: [GradientColorStop]

    // upstream declares `global: boolean` but the Gradient constructor never assigns it
    // (subclasses set it from `globalCoord || false`). Defaulted to `false` per the Swift
    // stored-prop init requirement; overwritten by every subclass.
    public var global: Bool = false

    public init(_ colorStops: [GradientColorStop]?) {
        self.colorStops = colorStops ?? []
    }

    public func addColorStop(_ offset: Double, _ color: String) {
        self.colorStops.append(GradientColorStop(
            offset: offset,
            color: color
        ))
    }
}
