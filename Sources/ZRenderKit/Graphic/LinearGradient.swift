// Ported from zrender/src/graphic/LinearGradient.ts — keep in sync with upstream

// upstream: import Gradient, {GradientObject, GradientColorStop} from './Gradient';

public protocol LinearGradientObject: GradientObject {
    // upstream narrows `type: 'linear'`; Swift protocols can't narrow, so `type: String`
    // (inherited from GradientObject) stays and is set to "linear" by conformers.

    var x: Double { get set }
    var y: Double { get set }
    var x2: Double { get set }
    var y2: Double { get set }
}
/**
 * x, y, x2, y2 are all percent from 0 to 1 when globalCoord is false
 */

public final class LinearGradient: Gradient {

    // type: 'linear' — stored in the inherited `type` property, assigned in init below.

    public var x: Double
    public var y: Double
    public var x2: Double
    public var y2: Double

    public init(
        _ x: Double?, _ y: Double?, _ x2: Double?, _ y2: Double?,
        _ colorStops: [GradientColorStop]? = nil, _ globalCoord: Bool? = nil
    ) {

        // Deviation: Swift requires stored properties be set before super.init, so the
        // x/y/x2/y2 assignments are hoisted above `super.init` (upstream assigns them after
        // `super(colorStops)`). Behaviour is identical.
        self.x = x == nil ? 0 : x!

        self.y = y == nil ? 0 : y!

        self.x2 = x2 == nil ? 1 : x2!

        self.y2 = y2 == nil ? 0 : y2!

        super.init(colorStops)

        // Should do nothing more in this constructor. Because gradient can be
        // declard by `color: {type: 'linear', colorStops: ...}`, where
        // this constructor will not be called.

        // Can be cloned
        self.type = "linear"

        // If use global coord
        self.global = globalCoord ?? false
    }
}
