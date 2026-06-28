// Ported from zrender/src/graphic/RadialGradient.ts — keep in sync with upstream

// upstream: import Gradient, {GradientColorStop, GradientObject} from './Gradient';

public protocol RadialGradientObject: GradientObject {
    // upstream narrows `type: 'radial'`; Swift protocols can't narrow, so `type: String`
    // (inherited from GradientObject) stays and is set to "radial" by conformers.

    var x: Double { get set }
    var y: Double { get set }
    var r: Double { get set }
}
/**
 * x, y, r are all percent from 0 to 1 when globalCoord is false
 */
public final class RadialGradient: Gradient {

    // type: 'radial' — stored in the inherited `type` property, assigned in init below.

    public var x: Double
    public var y: Double
    public var r: Double

    public init(
        _ x: Double?, _ y: Double?, _ r: Double?,
        _ colorStops: [GradientColorStop]? = nil, _ globalCoord: Bool? = nil
    ) {
        // Deviation: Swift requires stored properties be set before super.init, so the
        // x/y/r assignments are hoisted above `super.init` (upstream assigns them after
        // `super(colorStops)`). Behaviour is identical.
        self.x = x == nil ? 0.5 : x!

        self.y = y == nil ? 0.5 : y!

        self.r = r == nil ? 0.5 : r!

        super.init(colorStops)
        // Should do nothing more in this constructor. Because gradient can be
        // declard by `color: {type: 'radial', colorStops: ...}`, where
        // this constructor will not be called.

        // Can be cloned
        self.type = "radial"

        // If use global coord
        self.global = globalCoord ?? false
    }
}
