// Ported from zrender/src/core/PathProxy.ts — keep in sync with upstream

/**
 * Path 代理，可以在`buildPath`中用于替代`ctx`, 会保存每个path操作的命令到pathCommands属性中
 * 可以用于 isInsidePath 判断以及获取boundingRect
 */

// TODO getTotalLength, getPointAtLength, arcTo

/* global Float32Array */

import Foundation
// import * as vec2 from './vector';                                  -> enum `vector` (this module)
// import BoundingRect from './BoundingRect';                         -> final class BoundingRect (this module)
// import { fromLine, fromCubic, fromQuadratic, fromArc } from './bbox';   -> enum `bbox` (this module)
// import { cubicLength, cubicSubdivide, quadraticLength, quadraticSubdivide } from './curve'; -> enum `curve` (this module)

// upstream: const CMD = { M:1, L:2, C:3, Q:4, A:5, Z:6, R:7 }.
// Modeled as a caseless enum of static-let constants (CONVENTIONS §2). It is nested in
// `PathProxy` below so that internal `CMD.M` and external `PathProxy.CMD.M` both resolve,
// matching upstream's module-level `const CMD` + `static CMD = CMD` re-export.

// const CMD_MEM_SIZE = {
//     M: 3,
//     L: 3,
//     C: 7,
//     Q: 5,
//     A: 9,
//     R: 5,
//     Z: 1
// };

// PORT-NOTE: interface ExtendedCanvasRenderingContext2D extends CanvasRenderingContext2D { dpr?: number }
//            The canvas 2D context is a renderer-backend type and is NOT ported (CONVENTIONS §9).

private var tmpOutX: [Double] = []
private var tmpOutY: [Double] = []

private var min: VectorArray = VectorArray()
private var max: VectorArray = VectorArray()
private var min2: VectorArray = VectorArray()
private var max2: VectorArray = VectorArray()
private func mathMin(_ a: Double, _ b: Double) -> Double { Swift.min(a, b) }
private func mathMax(_ a: Double, _ b: Double) -> Double { Swift.max(a, b) }
private func mathCos(_ x: Double) -> Double { cos(x) }
private func mathSin(_ x: Double) -> Double { sin(x) }
private func mathAbs(_ x: Double) -> Double { Swift.abs(x) }

private let PI = Double.pi
private let PI2 = PI * 2

// PORT-NOTE: `typeof Float32Array !== 'undefined'` — runtime feature detection; on the
// Swift side the typed buffer is always available, so the Float32Array branch is taken
// (CONVENTIONS §8). The dynamic `number[] | Float32Array` distinction collapses to a single
// growable `ContiguousArray<Double>` (CONVENTIONS §1).
private let hasTypedArray = true

private var tmpAngles: [Double] = [0, 0]   // upstream: const tmpAngles: number[] = []

private func modPI2(_ radian: Double) -> Double {
    // It's much more stable to mod N instedof PI
    // upstream: const n = Math.round(radian / PI * 1e8) / 1e8;
    // JS Math.round(x) === floor(x + 0.5) (rounds half toward +Inf), replicate exactly (CONVENTIONS §5)
    let n = floor(radian / PI * 1e8 + 0.5) / 1e8
    return (n.truncatingRemainder(dividingBy: 2)) * PI
}
/**
 * Normalize start and end angles.
 * startAngle will be normalized to 0 ~ PI*2
 * sweepAngle(endAngle - startAngle) will be normalized to 0 ~ PI*2 if clockwise.
 * -PI*2 ~ 0 if anticlockwise.
 */
public func normalizeArcAngles(_ angles: inout [Double], _ anticlockwise: Bool) {
    var newStartAngle = modPI2(angles[0])
    if newStartAngle < 0 {
        // Normlize to 0 - PI2
        newStartAngle += PI2
    }

    let delta = newStartAngle - angles[0]
    var newEndAngle = angles[1]
    newEndAngle += delta

    // https://github.com/chromium/chromium/blob/c20d681c9c067c4e15bb1408f17114b9e8cba294/third_party/blink/renderer/modules/canvas/canvas2d/canvas_path.cc#L184
    // Is circle
    if !anticlockwise && newEndAngle - newStartAngle >= PI2 {
        newEndAngle = newStartAngle + PI2
    }
    else if anticlockwise && newStartAngle - newEndAngle >= PI2 {
        newEndAngle = newStartAngle - PI2
    }
    // Make startAngle < endAngle when clockwise, otherwise endAngle < startAngle.
    // The sweep angle can never been larger than P2.
    else if !anticlockwise && newStartAngle > newEndAngle {
        newEndAngle = newStartAngle + (PI2 - modPI2(newStartAngle - newEndAngle))
    }
    else if anticlockwise && newStartAngle < newEndAngle {
        newEndAngle = newStartAngle - (PI2 - modPI2(newEndAngle - newStartAngle))
    }

    angles[0] = newStartAngle
    angles[1] = newEndAngle
}


public final class PathProxy {

    // upstream: const CMD = { M, L, C, Q, A, Z, R }; static CMD = CMD
    public enum CMD {
        public static let M: Double = 1
        public static let L: Double = 2
        public static let C: Double = 3
        public static let Q: Double = 4
        public static let A: Double = 5
        public static let Z: Double = 6
        // Rect
        public static let R: Double = 7
    }

    public var dpr: Double = 1

    // PORT-NOTE: upstream `data: number[] | Float32Array`. Modeled as a single growable
    // `ContiguousArray<Double>` (CONVENTIONS §1). Always present (defaults to empty) rather
    // than possibly-undefined; constructor only assigns it when `_saveData`.
    public var data: ContiguousArray<Double> = []

    /**
     * Version is for tracking if the path has been changed.
     */
    private var _version: Double = 0   // upstream default via initDefaultProps

    /**
     * If save path data.
     */
    private var _saveData: Bool = true  // upstream default via initDefaultProps

    /**
     * If the line segment is too small to draw. It will be added to the pending pt.
     * It will be added if the subpath needs to be finished before stroke, fill, or starting a new subpath.
     */
    private var _pendingPtX: Double = 0
    private var _pendingPtY: Double = 0
    // Distance of pending pt to previous point.
    // 0 if there is no pending point.
    // Only update the pending pt when distance is larger.
    private var _pendingPtDist: Double = 0  // upstream default via initDefaultProps

    // PORT-NOTE: private _ctx: ExtendedCanvasRenderingContext2D — renderer-backend context,
    //            not ported (CONVENTIONS §9). All `this._ctx && this._ctx.xxx()` calls below
    //            are dropped; path commands are recorded into `data` only.

    private var _xi: Double = 0
    private var _yi: Double = 0

    private var _x0: Double = 0
    private var _y0: Double = 0

    private var _len: Double = 0

    // Calculating path len and seg len.
    private var _pathSegLen: [Double]?
    private var _pathLen: Double = 0
    // Unit x, Unit y. Provide for avoiding drawing that too short line segment
    private var _ux: Double = 0  // upstream default via initDefaultProps
    private var _uy: Double = 0  // upstream default via initDefaultProps

    public init(_ notSaveData: Bool? = nil) {
        if notSaveData == true {
            self._saveData = false
        }

        if self._saveData {
            self.data = []
        }
    }

    public func increaseVersion() {
        self._version += 1
    }

    /**
     * Version can be used outside for compare if the path is changed.
     * For example to determine if need to update svg d str in svg renderer.
     */
    public func getVersion() -> Double {
        return self._version
    }

    /**
     * @readOnly
     */
    public func setScale(_ sx: Double, _ sy: Double, _ segmentIgnoreThreshold: Double? = nil) {
        // Compat. Previously there is no segmentIgnoreThreshold.
        let segmentIgnoreThreshold = segmentIgnoreThreshold ?? 0  // upstream: segmentIgnoreThreshold || 0
        if segmentIgnoreThreshold > 0 {
            let dpr = self.dpr != 0 ? self.dpr : 1   // upstream: this.dpr || 1
            let ux = mathAbs(segmentIgnoreThreshold / dpr / sx)
            self._ux = ux.isNaN ? 0 : ux             // upstream: ... || 0
            let uy = mathAbs(segmentIgnoreThreshold / dpr / sy)
            self._uy = uy.isNaN ? 0 : uy             // upstream: ... || 0
        }
    }

    public func setDPR(_ dpr: Double) {
        self.dpr = dpr
    }

    // PORT-NOTE: setContext(ctx) / getContext() operate on a CanvasRenderingContext2D
    //            (renderer seam, not ported — CONVENTIONS §9).

    public func beginPath() -> PathProxy {
        // this._ctx && this._ctx.beginPath();   // PORT-NOTE renderer seam §9
        self.reset()
        return self
    }

    /**
     * Reset path data.
     */
    public func reset() {
        // Reset
        if self._saveData {
            self._len = 0
        }

        if self._pathSegLen != nil {
            self._pathSegLen = nil
            self._pathLen = 0
        }

        // Update version
        self._version += 1
    }

    public func moveTo(_ x: Double, _ y: Double) -> PathProxy {
        // Add pending point for previous path.
        self._drawPendingPt()

        self.addData(CMD.M, x, y)
        // this._ctx && this._ctx.moveTo(x, y);   // PORT-NOTE renderer seam §9

        // x0, y0, xi, yi 是记录在 _dashedXXXXTo 方法中使用
        // xi, yi 记录当前点, x0, y0 在 closePath 的时候回到起始点。
        // 有可能在 beginPath 之后直接调用 lineTo，这时候 x0, y0 需要
        // 在 lineTo 方法中记录，这里先不考虑这种情况，dashed line 也只在 IE10- 中不支持
        self._x0 = x
        self._y0 = y

        self._xi = x
        self._yi = y

        return self
    }

    public func lineTo(_ x: Double, _ y: Double) -> PathProxy {
        let dx = mathAbs(x - self._xi)
        let dy = mathAbs(y - self._yi)
        let exceedUnit = dx > self._ux || dy > self._uy

        self.addData(CMD.L, x, y)

        // if (this._ctx && exceedUnit) { this._ctx.lineTo(x, y); }   // PORT-NOTE renderer seam §9
        if exceedUnit {
            self._xi = x
            self._yi = y
            self._pendingPtDist = 0
        }
        else {
            let d2 = dx * dx + dy * dy
            // Only use the farthest pending point.
            if d2 > self._pendingPtDist {
                self._pendingPtX = x
                self._pendingPtY = y
                self._pendingPtDist = d2
            }
        }

        return self
    }

    public func bezierCurveTo(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ x3: Double, _ y3: Double) -> PathProxy {
        self._drawPendingPt()

        self.addData(CMD.C, x1, y1, x2, y2, x3, y3)
        // if (this._ctx) { this._ctx.bezierCurveTo(x1, y1, x2, y2, x3, y3); }   // PORT-NOTE renderer seam §9
        self._xi = x3
        self._yi = y3
        return self
    }

    public func quadraticCurveTo(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> PathProxy {
        self._drawPendingPt()

        self.addData(CMD.Q, x1, y1, x2, y2)
        // if (this._ctx) { this._ctx.quadraticCurveTo(x1, y1, x2, y2); }   // PORT-NOTE renderer seam §9
        self._xi = x2
        self._yi = y2
        return self
    }

    public func arc(_ cx: Double, _ cy: Double, _ r: Double, _ startAngle: Double, _ endAngle: Double, _ anticlockwise: Bool? = nil) -> PathProxy {
        self._drawPendingPt()

        tmpAngles[0] = startAngle
        tmpAngles[1] = endAngle
        normalizeArcAngles(&tmpAngles, anticlockwise ?? false)

        let startAngle = tmpAngles[0]
        let endAngle = tmpAngles[1]

        let delta = endAngle - startAngle

        self.addData(
            CMD.A, cx, cy, r, r, startAngle, delta, 0, (anticlockwise ?? false) ? 0 : 1
        )

        // this._ctx && this._ctx.arc(cx, cy, r, startAngle, endAngle, anticlockwise);   // PORT-NOTE renderer seam §9

        self._xi = mathCos(endAngle) * r + cx
        self._yi = mathSin(endAngle) * r + cy
        return self
    }

    // TODO
    public func arcTo(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ radius: Double) -> PathProxy {
        self._drawPendingPt()

        // if (this._ctx) { this._ctx.arcTo(x1, y1, x2, y2, radius); }   // PORT-NOTE renderer seam §9
        return self
    }

    // TODO
    public func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> PathProxy {
        self._drawPendingPt()

        // this._ctx && this._ctx.rect(x, y, w, h);   // PORT-NOTE renderer seam §9
        self.addData(CMD.R, x, y, w, h)
        return self
    }

    public func closePath() -> PathProxy {
        // Add pending point for previous path.
        self._drawPendingPt()

        self.addData(CMD.Z)

        // const ctx = this._ctx;   // PORT-NOTE renderer seam §9
        let x0 = self._x0
        let y0 = self._y0
        // if (ctx) { ctx.closePath(); }   // PORT-NOTE renderer seam §9

        self._xi = x0
        self._yi = y0
        return self
    }

    // PORT-NOTE: fill(ctx)/stroke(ctx) — `ctx` is a CanvasRenderingContext2D (renderer seam,
    //            not ported — CONVENTIONS §9). The `ctx && ctx.fill()/stroke()` call is dropped.
    public func fill() {
        // ctx && ctx.fill();   // PORT-NOTE renderer seam §9
        self.toStatic()
    }

    public func stroke() {
        // ctx && ctx.stroke();   // PORT-NOTE renderer seam §9
        self.toStatic()
    }

    public func len() -> Double {
        return self._len
    }

    public func setData(_ data: [Double]) {
        if !self._saveData {
            return
        }

        let len = data.count

        if !(self.data.count == len) && hasTypedArray {
            self.data = ContiguousArray<Double>(repeating: 0, count: len)
        }

        for i in 0..<len {
            self.data[i] = data[i]
        }

        self._len = Double(len)
    }

    // upstream: appendPath(path: PathProxy | PathProxy[]). The single-path form is provided
    // as a convenience overload below, mirroring `if (!(path instanceof Array)) path = [path]`.
    public func appendPath(_ path: PathProxy) {
        self.appendPath([path])
    }

    public func appendPath(_ path: [PathProxy]) {
        if !self._saveData {
            return
        }
        let len = path.count
        var appendSize = 0
        var offset = Int(self._len)
        for i in 0..<len {
            appendSize += Int(path[i].len())
        }
        let oldData = self.data
        // upstream: if (hasTypedArray && (oldData instanceof Float32Array || !oldData))
        // PORT-NOTE: single ContiguousArray<Double> — always reallocate to exact size.
        if hasTypedArray {
            self.data = ContiguousArray<Double>(repeating: 0, count: offset + appendSize)
            if offset > 0 {   // upstream: offset > 0 && oldData
                for k in 0..<offset {
                    self.data[k] = oldData[k]
                }
            }
        }
        for i in 0..<len {
            let appendPathData = path[i].data
            for k in 0..<appendPathData.count {
                self.data[offset] = appendPathData[k]
                offset += 1
            }
        }
        self._len = Double(offset)
    }

    /**
     * 填充 Path 数据。
     * 尽量复用而不申明新的数组。大部分图形重绘的指令数据长度都是不变的。
     */
    public func addData(
        _ cmd: Double,
        _ args: Double...
    ) {
        if !self._saveData {
            return
        }

        // upstream uses the `arguments` object; reconstruct it as cmd + variadic (CONVENTIONS §7)
        var arguments = [cmd]
        arguments.append(contentsOf: args)
        let argumentsLength = arguments.count

        // upstream: let data = this.data;
        if self._len + Double(argumentsLength) > Double(self.data.count) {
            // 因为之前的数组已经转换成静态的 Float32Array
            // 所以不够用时需要扩展一个新的动态数组
            self._expandData()
            // data = this.data;
        }
        for i in 0..<argumentsLength {
            // upstream: data[this._len++] = arguments[i];
            // ContiguousArray cannot index-assign past `count`; grow by append, matching the
            // implicit auto-grow of a dynamic JS array.
            let idx = Int(self._len)
            if idx < self.data.count {
                self.data[idx] = arguments[i]
            }
            else {
                self.data.append(arguments[i])
            }
            self._len += 1
        }
    }

    private func _drawPendingPt() {
        if self._pendingPtDist > 0 {
            // this._ctx && this._ctx.lineTo(this._pendingPtX, this._pendingPtY);   // PORT-NOTE renderer seam §9
            self._pendingPtDist = 0
        }
    }

    private func _expandData() {
        // Only if data is Float32Array
        // PORT-NOTE: upstream converts a static Float32Array back into a growable number[].
        // In Swift `data` is already a single growable ContiguousArray<Double>, so the
        // static→dynamic conversion is a no-op; growth happens via `append` in `addData`.
    }

    /**
     * Convert dynamic array to static Float32Array
     *
     * It will still use a normal array if command buffer length is less than 10
     * Because Float32Array itself may take more memory than a normal array.
     *
     * 10 length will make sure at least one M command and one A(arc) command.
     */
    public func toStatic() {
        if !self._saveData {
            return
        }

        self._drawPendingPt()

        // upstream: if (data instanceof Array) { data.length = this._len; if (hasTypedArray && this._len > 11) this.data = new Float32Array(data); }
        // PORT-NOTE: truncate to `_len`. The Float32Array static conversion (which would
        // truncate Double precision to Float) is dropped — single ContiguousArray<Double>
        // keeps full precision (CONVENTIONS §1).
        if self.data.count > Int(self._len) {
            self.data.removeLast(self.data.count - Int(self._len))
        }
    }


    public func getBoundingRect() -> BoundingRect {
        min[0] = Double.greatestFiniteMagnitude; min[1] = Double.greatestFiniteMagnitude
        min2[0] = Double.greatestFiniteMagnitude; min2[1] = Double.greatestFiniteMagnitude
        max[0] = -Double.greatestFiniteMagnitude; max[1] = -Double.greatestFiniteMagnitude
        max2[0] = -Double.greatestFiniteMagnitude; max2[1] = -Double.greatestFiniteMagnitude

        let data = self.data
        var xi: Double = 0
        var yi: Double = 0
        var x0: Double = 0
        var y0: Double = 0

        var i = 0
        while i < Int(self._len) {
            let cmd = data[i]; i += 1

            let isFirst = i == 1
            if isFirst {
                // 如果第一个命令是 L, C, Q
                // 则 previous point 同绘制命令的第一个 point
                // 第一个命令为 Arc 的情况下会在后面特殊处理
                xi = data[i]
                yi = data[i + 1]

                x0 = xi
                y0 = yi
            }

            switch cmd {
                case CMD.M:
                    // moveTo 命令重新创建一个新的 subpath, 并且更新新的起点
                    // 在 closePath 的时候使用
                    x0 = data[i]; xi = x0; i += 1
                    y0 = data[i]; yi = y0; i += 1
                    min2[0] = x0
                    min2[1] = y0
                    max2[0] = x0
                    max2[1] = y0
                case CMD.L:
                    (min2, max2) = bbox.fromLine(xi, yi, data[i], data[i + 1])
                    xi = data[i]; i += 1
                    yi = data[i]; i += 1
                case CMD.C:
                    let c1 = data[i]; i += 1
                    let c2 = data[i]; i += 1
                    let c3 = data[i]; i += 1
                    let c4 = data[i]; i += 1
                    (min2, max2) = bbox.fromCubic(
                        xi, yi, c1, c2, c3, c4, data[i], data[i + 1]
                    )
                    xi = data[i]; i += 1
                    yi = data[i]; i += 1
                case CMD.Q:
                    let q1 = data[i]; i += 1
                    let q2 = data[i]; i += 1
                    (min2, max2) = bbox.fromQuadratic(
                        xi, yi, q1, q2, data[i], data[i + 1]
                    )
                    xi = data[i]; i += 1
                    yi = data[i]; i += 1
                case CMD.A:
                    let cx = data[i]; i += 1
                    let cy = data[i]; i += 1
                    let rx = data[i]; i += 1
                    let ry = data[i]; i += 1
                    let startAngle = data[i]; i += 1
                    let endAngle = data[i] + startAngle; i += 1
                    // TODO Arc 旋转
                    i += 1
                    let anticlockwise = data[i] == 0; i += 1   // upstream: !data[i++]

                    if isFirst {
                        // 直接使用 arc 命令
                        // 第一个命令起点还未定义
                        x0 = mathCos(startAngle) * rx + cx
                        y0 = mathSin(startAngle) * ry + cy
                    }

                    (min2, max2) = bbox.fromArc(
                        cx, cy, rx, ry, startAngle, endAngle,
                        anticlockwise
                    )

                    xi = mathCos(endAngle) * rx + cx
                    yi = mathSin(endAngle) * ry + cy
                case CMD.R:
                    xi = data[i]; x0 = xi; i += 1
                    yi = data[i]; y0 = yi; i += 1
                    let width = data[i]; i += 1
                    let height = data[i]; i += 1
                    // Use fromLine
                    (min2, max2) = bbox.fromLine(x0, y0, x0 + width, y0 + height)
                case CMD.Z:
                    xi = x0
                    yi = y0
                default:
                    break
            }

            // Union
            min = vector.min(min, min2)
            max = vector.max(max, max2)
        }

        // No data
        if i == 0 {
            min[0] = 0; min[1] = 0; max[0] = 0; max[1] = 0
        }

        return BoundingRect(
            min[0], min[1], max[0] - min[0], max[1] - min[1]
        )
    }

    @discardableResult
    private func _calculateLength() -> Double {
        let data = self.data
        let len = self._len
        let ux = self._ux
        let uy = self._uy
        var xi: Double = 0
        var yi: Double = 0
        var x0: Double = 0
        var y0: Double = 0

        if self._pathSegLen == nil {
            self._pathSegLen = []
        }
        var pathSegLen = self._pathSegLen!
        var pathTotalLen: Double = 0
        var segCount = 0

        var i = 0
        while i < Int(len) {
            let cmd = data[i]; i += 1
            let isFirst = i == 1

            if isFirst {
                // 如果第一个命令是 L, C, Q
                // 则 previous point 同绘制命令的第一个 point
                // 第一个命令为 Arc 的情况下会在后面特殊处理
                xi = data[i]
                yi = data[i + 1]

                x0 = xi
                y0 = yi
            }

            var l: Double = -1

            switch cmd {
                case CMD.M:
                    // moveTo 命令重新创建一个新的 subpath, 并且更新新的起点
                    // 在 closePath 的时候使用
                    x0 = data[i]; xi = x0; i += 1
                    y0 = data[i]; yi = y0; i += 1
                case CMD.L:
                    let x2 = data[i]; i += 1
                    let y2 = data[i]; i += 1
                    let dx = x2 - xi
                    let dy = y2 - yi
                    if mathAbs(dx) > ux || mathAbs(dy) > uy || Double(i) == len - 1 {
                        l = sqrt(dx * dx + dy * dy)
                        xi = x2
                        yi = y2
                    }
                case CMD.C:
                    let x1 = data[i]; i += 1
                    let y1 = data[i]; i += 1
                    let x2 = data[i]; i += 1
                    let y2 = data[i]; i += 1
                    let x3 = data[i]; i += 1
                    let y3 = data[i]; i += 1
                    // TODO adaptive iteration
                    l = curve.cubicLength(xi, yi, x1, y1, x2, y2, x3, y3, 10)
                    xi = x3
                    yi = y3
                case CMD.Q:
                    let x1 = data[i]; i += 1
                    let y1 = data[i]; i += 1
                    let x2 = data[i]; i += 1
                    let y2 = data[i]; i += 1
                    l = curve.quadraticLength(xi, yi, x1, y1, x2, y2, 10)
                    xi = x2
                    yi = y2
                case CMD.A:
                    // TODO Arc 判断的开销比较大
                    let cx = data[i]; i += 1
                    let cy = data[i]; i += 1
                    let rx = data[i]; i += 1
                    let ry = data[i]; i += 1
                    let startAngle = data[i]; i += 1
                    let delta = data[i]; i += 1
                    let endAngle = delta + startAngle
                    // TODO Arc 旋转
                    // psi slot.
                    i += 1
                    // PORT FIX (diverges from upstream): an arc occupies 8 data slots
                    // (cx,cy,rx,ry,startAngle,delta,psi,anticlockwise — see `arc()`/`addData`), and
                    // getBoundingRect/rebuildPath both consume all 8. Upstream `_calculateLength`
                    // advances `i` by only 7 (it never reads the anticlockwise slot); in JS the
                    // resulting 1-slot misalignment reads `undefined` (NaN) and limps to the end, but
                    // in Swift the strict-bounds `data[i]` overruns and crashes (e.g. a Circle/Sector
                    // with `strokePercent < 1`, which is the only caller of `_calculateLength`).
                    // Consume the anticlockwise slot too so the traversal stays aligned.
                    i += 1
                    if isFirst {
                        // 直接使用 arc 命令
                        // 第一个命令起点还未定义
                        x0 = mathCos(startAngle) * rx + cx
                        y0 = mathSin(startAngle) * ry + cy
                    }

                    // TODO Ellipse
                    l = mathMax(rx, ry) * mathMin(PI2, abs(delta))

                    xi = mathCos(endAngle) * rx + cx
                    yi = mathSin(endAngle) * ry + cy
                case CMD.R:
                    x0 = data[i]; xi = x0; i += 1
                    y0 = data[i]; yi = y0; i += 1
                    let width = data[i]; i += 1
                    let height = data[i]; i += 1
                    l = width * 2 + height * 2
                case CMD.Z:
                    let dx = x0 - xi
                    let dy = y0 - yi
                    l = sqrt(dx * dx + dy * dy)

                    xi = x0
                    yi = y0
                default:
                    break
            }

            if l >= 0 {
                // upstream: pathSegLen[segCount++] = l;
                if segCount < pathSegLen.count {
                    pathSegLen[segCount] = l
                }
                else {
                    pathSegLen.append(l)
                }
                segCount += 1
                pathTotalLen += l
            }
        }

        // TODO Optimize memory cost.
        self._pathSegLen = pathSegLen
        self._pathLen = pathTotalLen

        return pathTotalLen
    }
    /**
     * Rebuild path from current data
     * Rebuild path will not consider javascript implemented line dash.
     * @param {CanvasRenderingContext2D} ctx
     */
    public func rebuildPath(_ ctx: PathRebuilder, _ percent: Double) {
        let d = self.data
        let ux = self._ux
        let uy = self._uy
        let len = self._len
        var x0: Double = 0
        var y0: Double = 0
        var xi: Double = 0
        var yi: Double = 0
        var x: Double = 0
        var y: Double = 0

        let drawPart = percent < 1
        var pathSegLen: [Double] = []
        var pathTotalLen: Double = 0
        var accumLength: Double = 0
        var segCount = 0
        var displayedLength: Double = 0

        var pendingPtDist: Double = 0
        var pendingPtX: Double = 0
        var pendingPtY: Double = 0


        if drawPart {
            if self._pathSegLen == nil {
                self._calculateLength()
            }
            pathSegLen = self._pathSegLen ?? []
            pathTotalLen = self._pathLen
            displayedLength = percent * pathTotalLen

            if displayedLength == 0 {   // upstream: if (!displayedLength)
                return
            }
        }

        var i = 0
        lo: while i < Int(len) {
            let cmd = d[i]; i += 1
            let isFirst = i == 1

            if isFirst {
                // 如果第一个命令是 L, C, Q
                // 则 previous point 同绘制命令的第一个 point
                // 第一个命令为 Arc 的情况下会在后面特殊处理
                xi = d[i]
                yi = d[i + 1]

                x0 = xi
                y0 = yi
            }
            // Only lineTo support ignoring small segments.
            // Otherwise if the pending point should always been flushed.
            if cmd != CMD.L && pendingPtDist > 0 {
                ctx.lineTo(pendingPtX, pendingPtY)
                pendingPtDist = 0
            }
            switch cmd {
                case CMD.M:
                    x0 = d[i]; xi = x0; i += 1
                    y0 = d[i]; yi = y0; i += 1
                    ctx.moveTo(xi, yi)
                case CMD.L:
                    x = d[i]; i += 1
                    y = d[i]; i += 1
                    let dx = mathAbs(x - xi)
                    let dy = mathAbs(y - yi)
                    // Not draw too small seg between
                    if dx > ux || dy > uy {
                        if drawPart {
                            let l = pathSegLen[segCount]; segCount += 1
                            if accumLength + l > displayedLength {
                                let t = (displayedLength - accumLength) / l
                                ctx.lineTo(xi * (1 - t) + x * t, yi * (1 - t) + y * t)
                                break lo
                            }
                            accumLength += l
                        }

                        ctx.lineTo(x, y)
                        xi = x
                        yi = y
                        pendingPtDist = 0
                    }
                    else {
                        let d2 = dx * dx + dy * dy
                        // Only use the farthest pending point.
                        if d2 > pendingPtDist {
                            pendingPtX = x
                            pendingPtY = y
                            pendingPtDist = d2
                        }
                    }
                case CMD.C:
                    let x1 = d[i]; i += 1
                    let y1 = d[i]; i += 1
                    let x2 = d[i]; i += 1
                    let y2 = d[i]; i += 1
                    let x3 = d[i]; i += 1
                    let y3 = d[i]; i += 1
                    if drawPart {
                        let l = pathSegLen[segCount]; segCount += 1
                        if accumLength + l > displayedLength {
                            let t = (displayedLength - accumLength) / l
                            tmpOutX = curve.cubicSubdivide(xi, x1, x2, x3, t)
                            tmpOutY = curve.cubicSubdivide(yi, y1, y2, y3, t)
                            ctx.bezierCurveTo(tmpOutX[1], tmpOutY[1], tmpOutX[2], tmpOutY[2], tmpOutX[3], tmpOutY[3])
                            break lo
                        }
                        accumLength += l
                    }

                    ctx.bezierCurveTo(x1, y1, x2, y2, x3, y3)
                    xi = x3
                    yi = y3
                case CMD.Q:
                    let x1 = d[i]; i += 1
                    let y1 = d[i]; i += 1
                    let x2 = d[i]; i += 1
                    let y2 = d[i]; i += 1

                    if drawPart {
                        let l = pathSegLen[segCount]; segCount += 1
                        if accumLength + l > displayedLength {
                            let t = (displayedLength - accumLength) / l
                            tmpOutX = curve.quadraticSubdivide(xi, x1, x2, t)
                            tmpOutY = curve.quadraticSubdivide(yi, y1, y2, t)
                            ctx.quadraticCurveTo(tmpOutX[1], tmpOutY[1], tmpOutX[2], tmpOutY[2])
                            break lo
                        }
                        accumLength += l
                    }

                    ctx.quadraticCurveTo(x1, y1, x2, y2)
                    xi = x2
                    yi = y2
                case CMD.A:
                    let cx = d[i]; i += 1
                    let cy = d[i]; i += 1
                    let rx = d[i]; i += 1
                    let ry = d[i]; i += 1
                    let startAngle = d[i]; i += 1
                    let delta = d[i]; i += 1
                    let psi = d[i]; i += 1
                    let anticlockwise = d[i] == 0; i += 1   // upstream: !d[i++]
                    let r = (rx > ry) ? rx : ry
                    // const scaleX = (rx > ry) ? 1 : rx / ry;
                    // const scaleY = (rx > ry) ? ry / rx : 1;
                    let isEllipse = mathAbs(rx - ry) > 1e-3
                    var endAngle = startAngle + delta
                    var breakBuild = false

                    if drawPart {
                        let l = pathSegLen[segCount]; segCount += 1
                        if accumLength + l > displayedLength {
                            endAngle = startAngle + delta * (displayedLength - accumLength) / l
                            breakBuild = true
                        }
                        accumLength += l
                    }
                    // PORT-NOTE: upstream guards `isEllipse && ctx.ellipse` (feature-detects
                    // the optional `ellipse` method). PathRebuilder always provides `ellipse`,
                    // so the existence check is dropped (CONVENTIONS §8/§9).
                    if isEllipse {
                        ctx.ellipse(cx, cy, rx, ry, psi, startAngle, endAngle, anticlockwise)
                    }
                    else {
                        ctx.arc(cx, cy, r, startAngle, endAngle, anticlockwise)
                    }

                    if breakBuild {
                        break lo
                    }

                    if isFirst {
                        // 直接使用 arc 命令
                        // 第一个命令起点还未定义
                        x0 = mathCos(startAngle) * rx + cx
                        y0 = mathSin(startAngle) * ry + cy
                    }
                    xi = mathCos(endAngle) * rx + cx
                    yi = mathSin(endAngle) * ry + cy
                case CMD.R:
                    xi = d[i]; x0 = xi
                    yi = d[i + 1]; y0 = yi

                    x = d[i]; i += 1
                    y = d[i]; i += 1
                    let width = d[i]; i += 1
                    let height = d[i]; i += 1

                    if drawPart {
                        let l = pathSegLen[segCount]; segCount += 1
                        if accumLength + l > displayedLength {
                            var d = displayedLength - accumLength   // upstream shadows `d` (the data array)
                            ctx.moveTo(x, y)
                            ctx.lineTo(x + mathMin(d, width), y)
                            d -= width
                            if d > 0 {
                                ctx.lineTo(x + width, y + mathMin(d, height))
                            }
                            d -= height
                            if d > 0 {
                                ctx.lineTo(x + mathMax(width - d, 0), y + height)
                            }
                            d -= width
                            if d > 0 {
                                ctx.lineTo(x, y + mathMax(height - d, 0))
                            }
                            break lo
                        }
                        accumLength += l
                    }
                    ctx.rect(x, y, width, height)
                case CMD.Z:
                    if drawPart {
                        let l = pathSegLen[segCount]; segCount += 1
                        if accumLength + l > displayedLength {
                            let t = (displayedLength - accumLength) / l
                            ctx.lineTo(xi * (1 - t) + x0 * t, yi * (1 - t) + y0 * t)
                            break lo
                        }
                        accumLength += l
                    }

                    ctx.closePath()
                    xi = x0
                    yi = y0
                default:
                    break
            }
        }
    }

    public func clone() -> PathProxy {
        let newProxy = PathProxy()
        let data = self.data
        // upstream: data.slice ? data.slice() : Array.prototype.slice.call(data)
        newProxy.data = data   // ContiguousArray is a value type — assignment copies
        newProxy._len = self._len
        return newProxy
    }

    public func canSave() -> Bool {
        return self._saveData   // upstream: !!this._saveData
    }

    // upstream: private static initDefaultProps = (function () { proto._saveData = true;
    // proto._ux = 0; proto._uy = 0; proto._pendingPtDist = 0; proto._version = 0; })()
    // Replicated as the property default values above (CONVENTIONS §2).
}


// upstream: export interface PathRebuilder { ... }
// Ported in `Sources/ZRenderKit/Core/PathRebuilder.swift` (the renderer seam — CONVENTIONS §9).
