// Ported from zrender/src/graphic/shape/Sector.ts — keep in sync with upstream
//
// A `Path` subclass: a `SectorShape` parameter bag + a `buildPath` that delegates to the
// corner-radius-aware `roundSector` helper (see Graphic/Helper/roundSector.swift). The math is
// validated byte-for-byte against the real-ECharts golden fixture for 'sector'.

import Foundation

// upstream imports (resolved to the ported modules):
// import Path, { PathProps } from '../Path';
// import * as roundSectorHelper from '../helper/roundSector';

// upstream: export class SectorShape { ... }
//   A plain parameter bag (no identity) → `struct` conforming to the `PathShape` marker (see the
//   GENERICS DECISION header note in Path.swift).
public struct SectorShape: PathShape {
    public var cx: Double = 0
    public var cy: Double = 0
    public var r0: Double = 0
    public var r: Double = 0
    public var startAngle: Double = 0
    public var endAngle: Double = Double.pi * 2
    public var clockwise: Bool = true
    /// Corner radius of sector
    ///
    /// clockwise, from inside to outside, four corners are
    /// inner start -> inner end
    /// outer start -> outer end
    ///
    /// 5               => [5, 5, 5, 5]
    /// [5]             => [5, 5, 0, 0]
    /// [5, 10]         => [5, 5, 10, 10]
    /// [5, 10, 15]     => [5, 10, 15, 15]
    /// [5, 10, 15, 20] => [5, 10, 15, 20]
    public var cornerRadius: CornerRadius = .number(0)

    public init() {}

    // Keyed access for animateTo({shape: {...}}) — exposes the animatable numeric fields
    //   (mirrors RectShape). `clockwise` (Bool) and `cornerRadius` (union) are not tweened.
    // PORT-TODO: `cornerRadius` (number | number[]) is not exposed for keyed animation.
    public func animationGet(_ key: String) -> Any? {
        switch key {
        case "cx": return cx
        case "cy": return cy
        case "r0": return r0
        case "r": return r
        case "startAngle": return startAngle
        case "endAngle": return endAngle
        default: return nil
        }
    }

    public mutating func animationSet(_ key: String, _ value: Any?) {
        guard let v = value as? Double else { return }
        switch key {
        case "cx": cx = v
        case "cy": cy = v
        case "r0": r0 = v
        case "r": r = v
        case "startAngle": startAngle = v
        case "endAngle": endAngle = v
        default: break
        }
    }
}

// PORT-TODO: upstream `interface SectorProps extends PathProps { shape?: Partial<SectorShape> }`.
//   The typed-props interface collapses onto `PathProps == DisplayableProps` (the dynamic prop bag);
//   see Path.swift's `PathProps` note. Kept as an alias for provenance.
public typealias SectorProps = PathProps

// upstream: class Sector extends Path<SectorProps>
public final class Sector: Path {

    // upstream: shape: SectorShape — narrows the inherited `PathShape` existential. The base `Path`
    //   stores `shape` as `PathShape!`; `buildPath` downcasts (see GENERICS DECISION in Path.swift).

    // upstream: constructor(opts?: SectorProps) { super(opts) }
    public override init(_ opts: ElementProps? = nil) {
        super.init(opts)
        // upstream: Sector.prototype.type = 'sector'
        self.type = "sector"
    }

    public override func getDefaultShape() -> PathShape {
        return SectorShape()
    }

    public override func buildPath(_ ctx: PathProxy, _ shape: PathShape, _ inBatch: Bool) {
        let shape = shape as! SectorShape
        roundSector.buildPath(ctx, shape)
    }

    public override func isZeroArea() -> Bool {
        let shape = self.shape as! SectorShape
        return shape.startAngle == shape.endAngle
            || shape.r == shape.r0
    }
}
