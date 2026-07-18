// Ported from echarts/src/util/shape/sausage.ts — keep in sync with upstream
/*
* Licensed to the Apache Software Foundation (ASF) under one
* or more contributor license agreements.  See the NOTICE file
* distributed with this work for additional information
* regarding copyright ownership.  The ASF licenses this file
* to you under the Apache License, Version 2.0 (the
* "License"); you may not use this file except in compliance
* with the License.  You may obtain a copy of the License at
*
*   http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing,
* software distributed under the License is distributed on an
* "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
* KIND, either express or implied.  See the License for the
* specific language governing permissions and limitations
* under the License.
*/

// PORT-NOTE (location deviation): upstream lives in `util/shape/sausage.ts` (imported by GaugeView as
//   `import Sausage from '../../util/shape/sausage'`). It is ported here — alongside its only consumer,
//   GaugeView — rather than under a util/shape package. If another chart ever needs the round-capped
//   sector, promote this to a shared ZRenderKit/EChartsKit shape module.

import Foundation
import ZRenderKit

// upstream imports:
//   import {Path} from '../graphic';                       -> ZRenderKit `Path`.
//   import { PathProps } from 'zrender/src/graphic/Path';  -> ZRenderKit `PathProps`.

/**
 * Sausage: similar to sector, but have half circle on both sides
 */

// upstream: class SausageShape { cx = 0; cy = 0; r0 = 0; r = 0; startAngle = 0; endAngle = Math.PI*2; clockwise = true; }
//   A plain parameter bag (no identity) → `struct` conforming to the `PathShape` marker (mirrors
//   SectorShape). The progress arc tweens `endAngle`, so the animatable numeric fields are exposed for
//   keyed animateTo({shape: {...}}) — identical set to SectorShape.
public struct SausageShape: PathShape {
    public var cx: Double = 0
    public var cy: Double = 0
    public var r0: Double = 0
    public var r: Double = 0
    public var startAngle: Double = 0
    public var endAngle: Double = Double.pi * 2
    public var clockwise: Bool = true

    public init() {}

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

// PORT-NOTE: upstream `interface SausagePathProps extends PathProps { shape?: SausageShape }`.
//   The typed-props interface collapses onto `PathProps == DisplayableProps` (dynamic prop bag);
//   see Sector.swift's `SectorProps` note. Kept as an alias for provenance.
public typealias SausagePathProps = PathProps

// upstream: class SausagePath extends Path<SausagePathProps>  (export default)
public final class SausagePath: Path {

    // upstream: type = 'sausage';
    // upstream: constructor(opts?: SausagePathProps) { super(opts); }
    public override init(_ opts: ElementProps? = nil) {
        super.init(opts)
        self.type = "sausage"
    }

    // upstream: getDefaultShape() { return new SausageShape(); }
    public override func getDefaultShape() -> PathShape {
        return SausageShape()
    }

    // upstream: buildPath(ctx: CanvasRenderingContext2D, shape: SausageShape)
    public override func buildPath(_ ctx: PathProxy, _ shape: PathShape, _ inBatch: Bool) {
        let shape = shape as! SausageShape

        let cx = shape.cx
        let cy = shape.cy
        let r0 = Swift.max(shape.r0, 0)
        let r = Swift.max(shape.r, 0)
        let dr = (r - r0) * 0.5
        let rCenter = r0 + dr
        var startAngle = shape.startAngle
        let endAngle = shape.endAngle
        let clockwise = shape.clockwise

        let PI2 = Double.pi * 2
        let lessThanCircle = clockwise
            ? endAngle - startAngle < PI2
            : startAngle - endAngle < PI2

        if !lessThanCircle {
            // Normalize angles
            startAngle = endAngle - (clockwise ? PI2 : -PI2)
        }

        let unitStartX = cos(startAngle)
        let unitStartY = sin(startAngle)
        let unitEndX = cos(endAngle)
        let unitEndY = sin(endAngle)

        if lessThanCircle {
            _ = ctx.moveTo(unitStartX * r0 + cx, unitStartY * r0 + cy)
            _ = ctx.arc(
                unitStartX * rCenter + cx, unitStartY * rCenter + cy, dr,
                -Double.pi + startAngle, startAngle, !clockwise
            )
        }
        else {
            _ = ctx.moveTo(unitStartX * r + cx, unitStartY * r + cy)
        }

        _ = ctx.arc(cx, cy, r, startAngle, endAngle, !clockwise)

        _ = ctx.arc(
            unitEndX * rCenter + cx, unitEndY * rCenter + cy, dr,
            endAngle - Double.pi * 2, endAngle - Double.pi, !clockwise
        )

        if r0 != 0 {
            _ = ctx.arc(cx, cy, r0, endAngle, startAngle, clockwise)
        }

        // ctx.closePath();
    }
}
