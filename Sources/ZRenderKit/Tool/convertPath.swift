// Ported from zrender/src/tool/convertPath.ts — keep in sync with upstream
//
// NAMESPACE DEVIATION (CONVENTIONS §2): a free-function module would normally become a caseless
//   `enum` named after the file (`convertPath`). Upstream consumers import the two exports as NAMED
//   imports (`import { pathToPolygons } from './convertPath'`), so exposing `pathToBezierCurves` /
//   `pathToPolygons` as top-level `public func`s keeps call sites byte-identical to upstream
//   (`pathToPolygons(...)`). The non-exported helpers (aroundEqual / adpativeBezier) stay file-private,
//   mirroring their upstream (un-exported) visibility. Same precedent as Tool/ToolPath.swift.

import Foundation

// upstream imports (resolved to the ported modules):
// import { cubicSubdivide } from '../core/curve';   → Core/curve.swift (curve.cubicSubdivide)
// import PathProxy from '../core/PathProxy';          → Core/PathProxy.swift

private typealias CMD = PathProxy.CMD

private func aroundEqual(_ a: Double, _ b: Double) -> Bool {
    return Swift.abs(a - b) < 1e-5
}

public func pathToBezierCurves(_ path: PathProxy) -> [[Double]] {

    let data = path.data
    let len = path.len()

    var bezierArrayGroups: [[Double]] = []
    // upstream: `let currentSubpath: number[];` (initially undefined — modeled as Optional).
    var currentSubpath: [Double]? = nil

    var xi: Double = 0
    var yi: Double = 0
    var x0: Double = 0
    var y0: Double = 0

    func createNewSubpath(_ x: Double, _ y: Double) {
        // More than one M command
        if let cur = currentSubpath, cur.count > 2 {
            bezierArrayGroups.append(cur)
        }
        currentSubpath = [x, y]
    }

    func addLine(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) {
        if !(aroundEqual(x0, x1) && aroundEqual(y0, y1)) {
            currentSubpath!.append(contentsOf: [x0, y0, x1, y1, x1, y1])
        }
    }

    func addArc(_ startAngle: Double, _ endAngle: Double, _ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double) {
        // https://stackoverflow.com/questions/1734745/how-to-create-circle-with-b%C3%A9zier-curves
        let delta = Swift.abs(endAngle - startAngle)
        let len = tan(delta / 4) * 4 / 3
        let dir: Double = endAngle < startAngle ? -1 : 1

        let c1 = cos(startAngle)
        let s1 = sin(startAngle)
        let c2 = cos(endAngle)
        let s2 = sin(endAngle)

        let x1 = c1 * rx + cx
        let y1 = s1 * ry + cy

        let x4 = c2 * rx + cx
        let y4 = s2 * ry + cy

        let hx = rx * len * dir
        let hy = ry * len * dir
        currentSubpath!.append(contentsOf: [
            // Move control points on tangent.
            x1 - hx * s1, y1 + hy * c1,
            x4 + hx * s2, y4 - hy * c2,
            x4, y4
        ])
    }

    var x1: Double = 0
    var y1: Double = 0
    var x2: Double
    var y2: Double

    var i = 0
    // helper for the `data[i++]` post-increment idiom (CONVENTIONS §7).
    func nextData() -> Double { let v = data[i]; i += 1; return v }
    while i < Int(len) {
        let cmd = nextData()
        let isFirst = i == 1

        if isFirst {
            // 如果第一个命令是 L, C, Q
            // 则 previous point 同绘制命令的第一个 point
            // 第一个命令为 Arc 的情况下会在后面特殊处理
            xi = data[i]
            yi = data[i + 1]

            x0 = xi
            y0 = yi

            if cmd == CMD.L || cmd == CMD.C || cmd == CMD.Q {
                // Start point
                currentSubpath = [x0, y0]
            }
        }

        switch cmd {
        case CMD.M:
            // moveTo 命令重新创建一个新的 subpath, 并且更新新的起点
            // 在 closePath 的时候使用
            xi = nextData(); x0 = xi
            yi = nextData(); y0 = yi

            createNewSubpath(x0, y0)
        case CMD.L:
            x1 = nextData()
            y1 = nextData()
            addLine(xi, yi, x1, y1)
            xi = x1
            yi = y1
        case CMD.C:
            currentSubpath!.append(contentsOf: [
                nextData(), nextData(), nextData(), nextData()
            ])
            xi = nextData(); currentSubpath!.append(xi)
            yi = nextData(); currentSubpath!.append(yi)
        case CMD.Q:
            x1 = nextData()
            y1 = nextData()
            x2 = nextData()
            y2 = nextData()
            currentSubpath!.append(contentsOf: [
                // Convert quadratic to cubic
                xi + 2 / 3 * (x1 - xi), yi + 2 / 3 * (y1 - yi),
                x2 + 2 / 3 * (x1 - x2), y2 + 2 / 3 * (y1 - y2),
                x2, y2
            ])
            xi = x2
            yi = y2
        case CMD.A:
            let cx = nextData()
            let cy = nextData()
            let rx = nextData()
            let ry = nextData()
            let startAngle = nextData()
            let endAngle = nextData() + startAngle

            // TODO Arc rotation
            i += 1
            // upstream: `const anticlockwise = !data[i++];` — JS falsy (0 / NaN) → true.
            let acFlag = nextData()
            let anticlockwise = (acFlag == 0 || acFlag.isNaN)

            x1 = cos(startAngle) * rx + cx
            y1 = sin(startAngle) * ry + cy
            if isFirst {
                // 直接使用 arc 命令
                // 第一个命令起点还未定义
                x0 = x1
                y0 = y1
                createNewSubpath(x0, y0)
            }
            else {
                // Connect a line between current point to arc start point.
                addLine(xi, yi, x1, y1)
            }

            xi = cos(endAngle) * rx + cx
            yi = sin(endAngle) * ry + cy

            let step = (anticlockwise ? -1 : 1) * Double.pi / 2

            var angle = startAngle
            while anticlockwise ? angle > endAngle : angle < endAngle {
                let nextAngle = anticlockwise ? Swift.max(angle + step, endAngle)
                    : Swift.min(angle + step, endAngle)
                addArc(angle, nextAngle, cx, cy, rx, ry)
                angle += step
            }
        case CMD.R:
            x0 = nextData(); xi = x0
            y0 = nextData(); yi = y0
            x1 = x0 + nextData()
            y1 = y0 + nextData()

            // rect is an individual path.
            createNewSubpath(x1, y0)
            addLine(x1, y0, x1, y1)
            addLine(x1, y1, x0, y1)
            addLine(x0, y1, x0, y0)
            addLine(x0, y0, x1, y0)
        case CMD.Z:
            if currentSubpath != nil { addLine(xi, yi, x0, y0) }
            xi = x0
            yi = y0
        default:
            break
        }
    }

    if let cur = currentSubpath, cur.count > 2 {
        bezierArrayGroups.append(cur)
    }

    return bezierArrayGroups
}

private func adpativeBezier(
    _ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ x3: Double, _ y3: Double,
    _ out: inout [Double], _ scale: Double
) {
    // This bezier is used to simulates a line when converting path to beziers.
    if aroundEqual(x0, x1) && aroundEqual(y0, y1) && aroundEqual(x2, x3) && aroundEqual(y2, y3) {
        out.append(contentsOf: [x3, y3])
        return
    }

    let PIXEL_DISTANCE = 2 / scale
    let PIXEL_DISTANCE_SQR = PIXEL_DISTANCE * PIXEL_DISTANCE

    // Determine if curve is straight enough
    var dx = x3 - x0
    var dy = y3 - y0
    let d = sqrt(dx * dx + dy * dy)
    dx /= d
    dy /= d

    let dx1 = x1 - x0
    let dy1 = y1 - y0
    let dx2 = x2 - x3
    let dy2 = y2 - y3

    let cp1LenSqr = dx1 * dx1 + dy1 * dy1
    let cp2LenSqr = dx2 * dx2 + dy2 * dy2

    if cp1LenSqr < PIXEL_DISTANCE_SQR && cp2LenSqr < PIXEL_DISTANCE_SQR {
        // Add small segment
        out.append(contentsOf: [x3, y3])
        return
    }

    // Project length of cp1
    let projLen1 = dx * dx1 + dy * dy1
    // Project length of cp2
    let projLen2 = -dx * dx2 - dy * dy2

    // Distance from cp1 to start-end line.
    let d1Sqr = cp1LenSqr - projLen1 * projLen1
    // Distance from cp2 to start-end line.
    let d2Sqr = cp2LenSqr - projLen2 * projLen2

    // IF the cp1 and cp2 is near to the start-line enough
    // We treat it straight enough
    if d1Sqr < PIXEL_DISTANCE_SQR && projLen1 >= 0
        && d2Sqr < PIXEL_DISTANCE_SQR && projLen2 >= 0 {
        out.append(contentsOf: [x3, y3])
        return
    }

    // Subdivide
    let tmpSegX = curve.cubicSubdivide(x0, x1, x2, x3, 0.5)
    let tmpSegY = curve.cubicSubdivide(y0, y1, y2, y3, 0.5)

    adpativeBezier(
        tmpSegX[0], tmpSegY[0], tmpSegX[1], tmpSegY[1], tmpSegX[2], tmpSegY[2], tmpSegX[3], tmpSegY[3],
        &out, scale
    )
    adpativeBezier(
        tmpSegX[4], tmpSegY[4], tmpSegX[5], tmpSegY[5], tmpSegX[6], tmpSegY[6], tmpSegX[7], tmpSegY[7],
        &out, scale
    )
}

public func pathToPolygons(_ path: PathProxy, _ scale: Double? = nil) -> [[Double]] {
    // TODO Optimize simple case like path is polygon and rect?
    let bezierArrayGroups = pathToBezierCurves(path)

    var polygons: [[Double]] = []

    let scale = (scale == nil || scale == 0) ? 1.0 : scale!

    for i in 0..<bezierArrayGroups.count {
        let beziers = bezierArrayGroups[i]
        var polygon: [Double] = []
        var x0 = beziers[0]
        var y0 = beziers[1]

        polygon.append(contentsOf: [x0, y0])

        var k = 2
        while k < beziers.count {

            let x1 = beziers[k]; k += 1
            let y1 = beziers[k]; k += 1
            let x2 = beziers[k]; k += 1
            let y2 = beziers[k]; k += 1
            let x3 = beziers[k]; k += 1
            let y3 = beziers[k]; k += 1

            adpativeBezier(x0, y0, x1, y1, x2, y2, x3, y3, &polygon, scale)

            x0 = x3
            y0 = y3
        }

        polygons.append(polygon)
    }
    return polygons
}
