// Ported from echarts/src/chart/gauge/PointerPath.ts — keep in sync with upstream
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

import Foundation
import ZRenderKit

// upstream imports:
//   import Path, { PathProps } from 'zrender/src/graphic/Path';  -> ZRenderKit `Path` / `PathProps`.

// upstream: class PointerShape { angle = 0; width = 10; r = 10; x = 0; y = 0; }
//   A plain parameter bag (no identity) → `struct` conforming to the `PathShape` marker
//   (CONVENTIONS §4; see Sector.swift / NormalBoxPathShape). Field defaults verbatim (width/r = 10).
public struct PointerShape: PathShape {
    public var angle: Double = 0
    public var width: Double = 10
    public var r: Double = 10
    public var x: Double = 0
    public var y: Double = 0

    public init() {}

    // Keyed access for animateTo({shape: {...}}) — exposes every animatable numeric field
    //   (mirrors SectorShape). The needle sweeps by tweening `angle`.
    public func animationGet(_ key: String) -> Any? {
        switch key {
        case "angle": return angle
        case "width": return width
        case "r": return r
        case "x": return x
        case "y": return y
        default: return nil
        }
    }

    public mutating func animationSet(_ key: String, _ value: Any?) {
        guard let v = value as? Double else { return }
        switch key {
        case "angle": angle = v
        case "width": width = v
        case "r": r = v
        case "x": x = v
        case "y": y = v
        default: break
        }
    }
}

// upstream: interface PointerPathProps extends PathProps { shape?: Partial<PointerShape> }
// PORT-TODO: the typed-props interface collapses onto the dynamic `PathProps == DisplayableProps`
//   prop bag (see Sector.swift `SectorProps`). Kept as an alias for provenance.
public typealias PointerPathProps = PathProps

// upstream: export default class PointerPath extends Path<PointerPathProps>
public final class PointerPath: Path {

    // upstream: readonly type = 'pointer'; shape: PointerShape;

    // upstream: constructor(opts?: PointerPathProps) { super(opts); }
    public override init(_ opts: ElementProps? = nil) {
        super.init(opts)
        // upstream: readonly type = 'pointer'
        self.type = "pointer"
    }

    // upstream: getDefaultShape() { return new PointerShape(); }
    public override func getDefaultShape() -> PathShape {
        return PointerShape()
    }

    // upstream: buildPath(ctx: CanvasRenderingContext2D, shape: PointerShape)
    public override func buildPath(_ ctx: PathProxy, _ shape: PathShape, _ inBatch: Bool) {
        let shape = shape as! PointerShape

        // const mathCos = Math.cos; const mathSin = Math.sin;
        //   Bound as concrete (Double)->Double funcs to disambiguate the overloaded Foundation cos/sin.
        let mathCos: (Double) -> Double = { Foundation.cos($0) }
        let mathSin: (Double) -> Double = { Foundation.sin($0) }

        let r = shape.r
        let width = shape.width
        var angle = shape.angle
        // Tail base offset: pull the back point 1× the width normally, 2× when the needle is very
        //   short relative to its width (width >= r/3 ? 1 : 2), so a stubby needle still reads.
        let x = shape.x - mathCos(angle) * width * (width >= r / 3 ? 1 : 2)
        let y = shape.y - mathSin(angle) * width * (width >= r / 3 ? 1 : 2)

        angle = shape.angle - Double.pi / 2
        _ = ctx.moveTo(x, y)
        _ = ctx.lineTo(
            shape.x + mathCos(angle) * width,
            shape.y + mathSin(angle) * width
        )
        _ = ctx.lineTo(
            shape.x + mathCos(shape.angle) * r,
            shape.y + mathSin(shape.angle) * r
        )
        _ = ctx.lineTo(
            shape.x - mathCos(angle) * width,
            shape.y - mathSin(angle) * width
        )
        _ = ctx.lineTo(x, y)
    }
}
