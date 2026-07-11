// Ported from zrender/src/tool/transformPath.ts — keep in sync with upstream
import Foundation

// upstream: import PathProxy from '../core/PathProxy';
// upstream: import {applyTransform as v2ApplyTransform, VectorArray} from '../core/vector';
// upstream: import { MatrixArray } from '../core/matrix';

// const CMD = PathProxy.CMD;  (referenced as PathProxy.CMD below)

// Module-level scratch buffers (per upstream). `p` in the R case is the file-level
// `let p: VectorArray;` declaration; `points` is the shared 3-slot scratch.
private var points: [VectorArray] = [VectorArray(), VectorArray(), VectorArray()]
// const mathSqrt = Math.sqrt;   -> Foundation `sqrt`
// const mathAtan2 = Math.atan2; -> Foundation `atan2`

// PORT-NOTE: `m` typed `MatrixArray?` (optional) to preserve the upstream `if (!m) return`
// guard, even though upstream's static type is non-null.
public func transformPath(_ path: PathProxy, _ m: MatrixArray?) {
    guard let m = m else {
        return
    }

    // upstream caches `let data = path.data`; since `ContiguousArray` is a value type we
    // index `path.data[...]` directly so the writes mutate the PathProxy's buffer in place.
    let len = Int(path.len())
    var cmd: Double
    var nPoint: Int
    var i: Int
    var j: Int
    var k: Int
    // file-level `let p: VectorArray;` (used by the R case); init to zero (Swift-safe).
    var p: VectorArray = VectorArray()

    let M = PathProxy.CMD.M
    let C = PathProxy.CMD.C
    let L = PathProxy.CMD.L
    let R = PathProxy.CMD.R
    let A = PathProxy.CMD.A
    let Q = PathProxy.CMD.Q

    i = 0
    j = 0
    while i < len {
        cmd = path.data[i]; i += 1
        j = i
        nPoint = 0

        switch cmd {
        case M:
            nPoint = 1
        case L:
            nPoint = 1
        case C:
            nPoint = 3
        case Q:
            nPoint = 2
        case A:
            let x = m[4]
            let y = m[5]
            let sx = sqrt(m[0] * m[0] + m[1] * m[1])
            let sy = sqrt(m[2] * m[2] + m[3] * m[3])
            let angle = atan2(-m[1] / sy, m[0] / sx)
            // cx
            path.data[i] *= sx
            path.data[i] += x; i += 1
            // cy
            path.data[i] *= sy
            path.data[i] += y; i += 1
            // Scale rx and ry
            // FIXME Assume psi is 0 here
            path.data[i] *= sx; i += 1
            path.data[i] *= sy; i += 1

            // Start angle
            path.data[i] += angle; i += 1
            // end angle
            path.data[i] += angle; i += 1
            // FIXME psi
            i += 2
            j = i
        case R:
            // x0, y0
            p[0] = path.data[i]; i += 1
            p[1] = path.data[i]; i += 1
            p = vector.applyTransform(p, m)
            path.data[j] = p[0]; j += 1
            path.data[j] = p[1]; j += 1
            // x1, y1
            p[0] += path.data[i]; i += 1
            p[1] += path.data[i]; i += 1
            p = vector.applyTransform(p, m)
            path.data[j] = p[0]; j += 1
            path.data[j] = p[1]; j += 1
        default:
            break
        }

        k = 0
        while k < nPoint {
            var p = points[k]
            p[0] = path.data[i]; i += 1
            p[1] = path.data[i]; i += 1

            p = vector.applyTransform(p, m)
            // Write back
            path.data[j] = p[0]; j += 1
            path.data[j] = p[1]; j += 1
            points[k] = p
            k += 1
        }
    }

    path.increaseVersion()
}
