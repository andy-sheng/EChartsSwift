// Ported from zrender/src/tool/path.ts — keep in sync with upstream
//
// FILENAME DEVIATION: upstream is `tool/path.ts`, but a `path.swift` file collides with
//   `graphic/Path.ts` → `Graphic/Path.swift` on macOS's case-insensitive filesystem (both derive the
//   same object file `Path.swift.o`, clobbering each other and breaking the link). Renamed
//   `ToolPath.swift`, mirroring the existing precedent for `contain/path.ts` → `Contain/ContainPath.swift`.
//   The header above still names the true upstream path so the file stays diffable.
//
// NAMESPACE DEVIATION (CONVENTIONS §2): a free-function module would normally become a caseless
//   `enum` named after the file (`path`). That name is ALREADY taken in this module by the contain
//   namespace `enum path` (Contain/ContainPath.swift). Upstream consumers import these as NAMED
//   imports (`import { createFromString, mergePath, clonePath } from 'zrender/.../tool/path'`), so
//   exposing the four exported functions as top-level `public func`s keeps call sites byte-identical
//   to upstream (`createFromString(...)`, `mergePath(...)`). The non-exported helpers
//   (createPathProxyFromString / processArc / vMag / vRatio / vAngle / isPathProxy / createPathOptions)
//   stay file-private, mirroring their upstream (un-exported) visibility.

import Foundation

// upstream imports (resolved to the ported modules):
// import Path, { PathProps } from '../graphic/Path';        → Graphic/Path.swift
// import PathProxy from '../core/PathProxy';                 → Core/PathProxy.swift
// import transformPath from './transformPath';               → Tool/transformPath.swift (free func)
// import { VectorArray } from '../core/vector';              → Core/vector.swift
// import { MatrixArray } from '../core/matrix';              → Core/matrix.swift
// import { extend } from '../core/util';                     → util.extend

// command chars
// const cc = [
//     'm', 'M', 'l', 'L', 'v', 'V', 'h', 'H', 'z', 'Z',
//     'c', 'C', 'q', 'Q', 't', 'T', 's', 'S', 'a', 'A'
// ];

// const mathSqrt = Math.sqrt;   -> Foundation `sqrt`
// const mathSin = Math.sin;     -> Foundation `sin`
// const mathCos = Math.cos;     -> Foundation `cos`
private let PI = Double.pi

private func vMag(_ v: VectorArray) -> Double {
    return sqrt(v[0] * v[0] + v[1] * v[1])
}
private func vRatio(_ u: VectorArray, _ v: VectorArray) -> Double {
    return (u[0] * v[0] + u[1] * v[1]) / (vMag(u) * vMag(v))
}
private func vAngle(_ u: VectorArray, _ v: VectorArray) -> Double {
    return (u[0] * v[1] < u[1] * v[0] ? -1 : 1)
            * acos(vRatio(u, v))
}

private func processArc(
    _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ fa: Double, _ fs: Double,
    _ rx0: Double, _ ry0: Double, _ psiDeg: Double, _ cmd: Double, _ path: PathProxy
) {
    // upstream mutates the `rx`/`ry` parameters in place; Swift params are immutable, so shadow them.
    var rx = rx0
    var ry = ry0
    // https://www.w3.org/TR/SVG11/implnote.html#ArcImplementationNotes
    let psi = psiDeg * (PI / 180.0)
    let xp = cos(psi) * (x1 - x2) / 2.0
                + sin(psi) * (y1 - y2) / 2.0
    let yp = -1 * sin(psi) * (x1 - x2) / 2.0
                + cos(psi) * (y1 - y2) / 2.0

    let lambda = (xp * xp) / (rx * rx) + (yp * yp) / (ry * ry)

    if lambda > 1 {
        rx *= sqrt(lambda)
        ry *= sqrt(lambda)
    }

    // upstream: `... || 0` — JS treats NaN and 0 as falsy, so map both to 0.
    let fval = (fa == fs ? -1.0 : 1.0)
        * sqrt((((rx * rx) * (ry * ry))
                - ((rx * rx) * (yp * yp))
                - ((ry * ry) * (xp * xp))) / ((rx * rx) * (yp * yp)
                + (ry * ry) * (xp * xp))
            )
    let f = (fval.isNaN || fval == 0) ? 0 : fval

    let cxp = f * rx * yp / ry
    let cyp = f * -ry * xp / rx

    let cx = (x1 + x2) / 2.0
                + cos(psi) * cxp
                - sin(psi) * cyp
    let cy = (y1 + y2) / 2.0
            + sin(psi) * cxp
            + cos(psi) * cyp

    let theta = vAngle(VectorArray(1, 0), VectorArray((xp - cxp) / rx, (yp - cyp) / ry))
    let u = VectorArray((xp - cxp) / rx, (yp - cyp) / ry)
    let v = VectorArray((-1 * xp - cxp) / rx, (-1 * yp - cyp) / ry)
    var dTheta = vAngle(u, v)

    if vRatio(u, v) <= -1 {
        dTheta = PI
    }
    if vRatio(u, v) >= 1 {
        dTheta = 0
    }

    if dTheta < 0 {
        // Math.round rounds half up (== floor(x + 0.5)); see CONVENTIONS §5.
        let n = floor(dTheta / PI * 1e6 + 0.5) / 1e6
        // Convert to positive
        dTheta = PI * 2 + n.truncatingRemainder(dividingBy: 2) * PI
    }

    path.addData(cmd, cx, cy, rx, ry, theta, dTheta, psi, fs)
}


// const commandReg = /([mlvhzcqtsa])([^mlvhzcqtsa]*)/ig;
private let commandRegPattern = "([mlvhzcqtsa])([^mlvhzcqtsa]*)"
// Consider case:
// (1) delimiter can be comma or space, where continuous commas
// or spaces should be seen as one comma.
// (2) value can be like:
// '2e-4', 'l.5.9' (ignore 0), 'M-10-10', 'l-2.43e-1,34.9983',
// 'l-.5E1,54', '121-23-44-11' (no delimiter)
// const numberReg = /-?([0-9]*\.)?[0-9]+([eE]-?[0-9]+)?/g;
private let numberRegPattern = "-?([0-9]*\\.)?[0-9]+([eE]-?[0-9]+)?"
// const valueSplitReg = /[\s,]+/;

// String.prototype.match(regex /g) → array of whole matches (group 0), or `nil` when there is none.
private func matchAll(_ pattern: String, _ options: NSRegularExpression.Options, _ s: String) -> [String]? {
    guard let re = try? NSRegularExpression(pattern: pattern, options: options) else {
        return nil
    }
    let ns = s as NSString
    let results = re.matches(in: s, options: [], range: NSRange(location: 0, length: ns.length))
    if results.isEmpty {
        return nil
    }
    return results.map { ns.substring(with: $0.range) }
}

private func createPathProxyFromString(_ data: String?) -> PathProxy {
    let path = PathProxy()

    // if (!data)
    guard let data = data, !data.isEmpty else {
        return path
    }

    // init context point
    var cpx: Double = 0
    var cpy: Double = 0
    var subpathX = cpx
    var subpathY = cpy
    var prevCmd: Double? = nil

    typealias CMD = PathProxy.CMD

    let cmdList = matchAll(commandRegPattern, [.caseInsensitive], data)
    guard let cmdList = cmdList else {
        // Invalid svg path.
        return path
    }

    for l in 0..<cmdList.count {
        let cmdText = cmdList[l]
        var cmdStr = String(cmdText.first!)

        var cmd: Double = 0

        // Following code will convert string to number. So convert type to number here
        // upstream: const p = cmdText.match(numberReg) ... ; for (...) p[i] = parseFloat(p[i]);
        // `parseFloat` fallback — numberReg yields clean tokens; `Double(_:)` parses
        //   '.5' / '-2.43e-1' etc. Unparsable tokens fall back to 0 (should not occur).
        let p: [Double] = (matchAll(numberRegPattern, [], cmdText) ?? []).map { Double($0) ?? 0 }
        let pLen = p.count

        var off = 0
        // helper for the `p[off++]` post-increment idiom (CONVENTIONS §7).
        func nextP() -> Double { let v = p[off]; off += 1; return v }
        while off < pLen {
            var ctlPtx: Double = 0
            var ctlPty: Double = 0

            var rx: Double = 0
            var ry: Double = 0
            var psi: Double = 0
            var fa: Double = 0
            var fs: Double = 0

            var x1 = cpx
            var y1 = cpy

            var len: Double
            var pathData: ContiguousArray<Double>
            // convert l, H, h, V, and v to L
            switch cmdStr {
            case "l":
                cpx += nextP()
                cpy += nextP()
                cmd = CMD.L
                path.addData(cmd, cpx, cpy)
            case "L":
                cpx = nextP()
                cpy = nextP()
                cmd = CMD.L
                path.addData(cmd, cpx, cpy)
            case "m":
                cpx += nextP()
                cpy += nextP()
                cmd = CMD.M
                path.addData(cmd, cpx, cpy)
                subpathX = cpx
                subpathY = cpy
                cmdStr = "l"
            case "M":
                cpx = nextP()
                cpy = nextP()
                cmd = CMD.M
                path.addData(cmd, cpx, cpy)
                subpathX = cpx
                subpathY = cpy
                cmdStr = "L"
            case "h":
                cpx += nextP()
                cmd = CMD.L
                path.addData(cmd, cpx, cpy)
            case "H":
                cpx = nextP()
                cmd = CMD.L
                path.addData(cmd, cpx, cpy)
            case "v":
                cpy += nextP()
                cmd = CMD.L
                path.addData(cmd, cpx, cpy)
            case "V":
                cpy = nextP()
                cmd = CMD.L
                path.addData(cmd, cpx, cpy)
            case "C":
                cmd = CMD.C
                path.addData(
                    cmd, nextP(), nextP(), nextP(), nextP(), nextP(), nextP()
                )
                cpx = p[off - 2]
                cpy = p[off - 1]
            case "c":
                cmd = CMD.C
                path.addData(
                    cmd,
                    nextP() + cpx, nextP() + cpy,
                    nextP() + cpx, nextP() + cpy,
                    nextP() + cpx, nextP() + cpy
                )
                cpx += p[off - 2]
                cpy += p[off - 1]
            case "S":
                ctlPtx = cpx
                ctlPty = cpy
                len = path.len()
                pathData = path.data
                if prevCmd == CMD.C {
                    ctlPtx += cpx - pathData[Int(len) - 4]
                    ctlPty += cpy - pathData[Int(len) - 3]
                }
                cmd = CMD.C
                x1 = nextP()
                y1 = nextP()
                cpx = nextP()
                cpy = nextP()
                path.addData(cmd, ctlPtx, ctlPty, x1, y1, cpx, cpy)
            case "s":
                ctlPtx = cpx
                ctlPty = cpy
                len = path.len()
                pathData = path.data
                if prevCmd == CMD.C {
                    ctlPtx += cpx - pathData[Int(len) - 4]
                    ctlPty += cpy - pathData[Int(len) - 3]
                }
                cmd = CMD.C
                x1 = cpx + nextP()
                y1 = cpy + nextP()
                cpx += nextP()
                cpy += nextP()
                path.addData(cmd, ctlPtx, ctlPty, x1, y1, cpx, cpy)
            case "Q":
                x1 = nextP()
                y1 = nextP()
                cpx = nextP()
                cpy = nextP()
                cmd = CMD.Q
                path.addData(cmd, x1, y1, cpx, cpy)
            case "q":
                x1 = nextP() + cpx
                y1 = nextP() + cpy
                cpx += nextP()
                cpy += nextP()
                cmd = CMD.Q
                path.addData(cmd, x1, y1, cpx, cpy)
            case "T":
                ctlPtx = cpx
                ctlPty = cpy
                len = path.len()
                pathData = path.data
                if prevCmd == CMD.Q {
                    ctlPtx += cpx - pathData[Int(len) - 4]
                    ctlPty += cpy - pathData[Int(len) - 3]
                }
                cpx = nextP()
                cpy = nextP()
                cmd = CMD.Q
                path.addData(cmd, ctlPtx, ctlPty, cpx, cpy)
            case "t":
                ctlPtx = cpx
                ctlPty = cpy
                len = path.len()
                pathData = path.data
                if prevCmd == CMD.Q {
                    ctlPtx += cpx - pathData[Int(len) - 4]
                    ctlPty += cpy - pathData[Int(len) - 3]
                }
                cpx += nextP()
                cpy += nextP()
                cmd = CMD.Q
                path.addData(cmd, ctlPtx, ctlPty, cpx, cpy)
            case "A":
                rx = nextP()
                ry = nextP()
                psi = nextP()
                fa = nextP()
                fs = nextP()

                x1 = cpx; y1 = cpy
                cpx = nextP()
                cpy = nextP()
                cmd = CMD.A
                processArc(
                    x1, y1, cpx, cpy, fa, fs, rx, ry, psi, cmd, path
                )
            case "a":
                rx = nextP()
                ry = nextP()
                psi = nextP()
                fa = nextP()
                fs = nextP()

                x1 = cpx; y1 = cpy
                cpx += nextP()
                cpy += nextP()
                cmd = CMD.A
                processArc(
                    x1, y1, cpx, cpy, fa, fs, rx, ry, psi, cmd, path
                )
            default:
                break
            }
            // suppress "never read" warnings for faithfully-declared locals
            _ = x1; _ = y1; _ = ctlPtx; _ = ctlPty
        }

        if cmdStr == "z" || cmdStr == "Z" {
            cmd = CMD.Z
            path.addData(cmd)
            // z may be in the middle of the path.
            cpx = subpathX
            cpy = subpathY
        }

        prevCmd = cmd
    }

    path.toStatic()

    return path
}

// type SVGPathOption = Omit<PathProps, 'shape' | 'buildPath'>
public typealias SVGPathOption = PathProps

// interface InnerSVGPathOption extends PathProps { applyTransform?: (m: MatrixArray) => void }
//   Modeled as a small value bag holding the captured closures (Swift can't reassign methods, so
//   `buildPath`/`applyTransform` are carried as closures and dispatched by `SVGPath`).
private struct InnerSVGPathOption {
    var opts: SVGPathOption?
    var buildPath: ((PathProxy) -> Void)?
    var applyTransform: ((SVGPath, MatrixArray) -> Void)?
}

// class SVGPath extends Path { applyTransform(m: MatrixArray) {} }
//   Upstream `createPathOptions` REASSIGNS `buildPath`/`applyTransform` on the option bag, which
//   the Path/Element machinery copies onto the instance (TS methods are assignable fields). Swift
//   methods are not assignable, so `SVGPath` stores the closures and its overrides dispatch to them.
public final class SVGPath: Path {
    // upstream: the assigned `buildPath` / `applyTransform` (captured `pathProxy`).
    fileprivate var __buildPathClosure: ((PathProxy) -> Void)?
    fileprivate var __applyTransformClosure: ((SVGPath, MatrixArray) -> Void)?

    // Stored slot so an `ECSymbol` conformance (declared in EChartsKit — see util/symbol.swift) can be
    //   satisfied by this property when a `path://` symbol is built as an `SVGPath` (createSymbol). The
    //   protocol itself lives in EChartsKit, which cannot add a stored property via extension, so the
    //   storage lives here (mirrors SymbolPath.__isEmptyBrush).
    public var __isEmptyBrush: Bool = false

    public override func buildPath(_ ctx: PathProxy, _ shape: PathShape, _ inBatch: Bool) {
        // upstream SVGPath.buildPath signature is (path: PathProxy | CanvasRenderingContext2D);
        //   here the renderer seam (CONVENTIONS §9) routes a PathProxy.
        __buildPathClosure?(ctx)
    }

    // upstream: applyTransform(m: MatrixArray) {}  (base no-op, replaced by createPathOptions)
    public func applyTransform(_ m: MatrixArray) {
        __applyTransformClosure?(self, m)
    }
}

// function isPathProxy(path: PathProxy | CanvasRenderingContext2D): path is PathProxy
private func isPathProxy(_ path: PathProxy) -> Bool {
    // upstream: (path as PathProxy).setData != null — distinguishes a PathProxy from a
    //   CanvasRenderingContext2D. In the Swift seam the argument is always a PathProxy.
    return true
}

// TODO Optimize double memory cost problem
private func createPathOptions(_ str: String?, _ opts: SVGPathOption?) -> InnerSVGPathOption {
    let pathProxy = createPathProxyFromString(str)
    var innerOpts = InnerSVGPathOption()
    // const innerOpts: InnerSVGPathOption = extend({}, opts);
    innerOpts.opts = opts
    innerOpts.buildPath = { (path: PathProxy) in
        let beProxy = isPathProxy(path)
        if beProxy && path.canSave() {
            // path.setData(pathProxy.data);
            path.appendPath(pathProxy)
            // Svg and vml renderer don't have context
            // const ctx = path.getContext(); if (ctx) { path.rebuildPath(ctx, 1); }
            //   getContext()/rebuildPath(ctx) are the CanvasRenderingContext2D renderer seam
            //   (CONVENTIONS §9, not ported). The native backend rebuilds from the appended proxy.
        }
        else {
            // const ctx = beProxy ? path.getContext() : path;
            // if (ctx) { pathProxy.rebuildPath(ctx, 1); }
            // renderer seam (CONVENTIONS §9) — getContext()/rebuildPath not ported.
            _ = pathProxy
        }
    }

    innerOpts.applyTransform = { (this: SVGPath, m: MatrixArray) in
        transformPath(pathProxy, m)
        this.dirtyShape()
    }

    return innerOpts
}

/**
 * Create a Path object from path string data
 * http://www.w3.org/TR/SVG/paths.html#PathData
 * @param  opts Other options
 */
public func createFromString(_ str: String?, _ opts: SVGPathOption? = nil) -> SVGPath {
    // PENDING
    // return new SVGPath(createPathOptions(str, opts));
    let innerOpts = createPathOptions(str, opts)
    let svgPath = SVGPath(innerOpts.opts)
    svgPath.__buildPathClosure = innerOpts.buildPath
    svgPath.__applyTransformClosure = innerOpts.applyTransform
    return svgPath
}

// upstream: resizePath(path, rect) — bake a transform into the SVG path's baked commands so its
//   bounding rect fits `rect`.
public func resizePath(_ path: SVGPath, _ rect: RectLike) {
    guard let pathRect = path.getBoundingRect() else { return }
    let m = pathRect.calculateTransform(rect)
    path.applyTransform(m)
}

// upstream: `centerGraphic` — shrink `rect` to the aspect ratio of `boundingRect`, centered inside it
//   (the `layout === 'center'` / keep-aspect case of makePath).
private func centerRectToAspect(_ rect: RectLike, _ boundingRect: BoundingRect) -> BoundingRect {
    let aspect = boundingRect.width / boundingRect.height
    var width = rect.height * aspect
    var height: Double
    if width <= rect.width {
        height = rect.height
    } else {
        width = rect.width
        height = width / aspect
    }
    let cx = rect.x + rect.width / 2
    let cy = rect.y + rect.height / 2
    return BoundingRect(cx - width / 2, cy - height / 2, width, height)
}

// upstream: makePath(pathData, opts, rect, layout) — parse an SVG path string and (optionally) resize
//   its baked commands to fit `rect`. `layout === 'center'` keeps the path's aspect ratio (centered);
//   otherwise the path is stretched to fill `rect` ('cover').
public func makePath(
    _ pathData: String?, _ opts: SVGPathOption?, _ rect: RectLike?, _ layout: String? = nil
) -> SVGPath {
    let path = createFromString(pathData, opts)
    if let rect = rect {
        var target: RectLike = rect
        if layout == "center", let br = path.getBoundingRect() {
            target = centerRectToAspect(rect, br)
        }
        resizePath(path, target)
    }
    return path
}

// upstream: makeImage(imageStr, rect, layout) — build a ZRImage sized to `rect`. 'cover' (the default)
//   stretches the image to fill `rect`; 'center' keeps the image's own aspect ratio, centered inside
//   `rect`, once the natural image size is known (resolved via onload — a deferred renderer seam). The
//   image:// symbol branch of util/symbol.createSymbol calls this.
public func makeImage(_ imageStr: String, _ rect: RectLike, _ layout: String? = nil) -> ZRImage {
    var style = ImageStyleProps()
    style.image = .url(imageStr)
    style.x = rect.x
    style.y = rect.y
    style.width = rect.width
    style.height = rect.height
    let zrImg = ZRImage(["style": style])
    // upstream: onload recenters for `layout === 'center'` using the loaded image's natural size.
    let capturedRect = BoundingRect(rect.x, rect.y, rect.width, rect.height)
    zrImg.onload = { [weak zrImg] img in
        guard let zrImg = zrImg, layout == "center" else { return }
        guard let sized = img as? ImageNaturalSize, sized.width != 0, sized.height != 0 else { return }
        let boundingRect = BoundingRect(0, 0, sized.width, sized.height)
        let centered = centerRectToAspect(capturedRect, boundingRect)
        var s = zrImg.imageStyle ?? ImageStyleProps()
        s.x = centered.x
        s.y = centered.y
        s.width = centered.width
        s.height = centered.height
        zrImg.useStyle(s)
    }
    return zrImg
}

/**
 * Create a Path class from path string data
 * @param  str
 * @param  opts Other options
 */
// upstream returns `typeof SVGPath` (a NEW Path subclass synthesized at runtime). Swift has no
//   runtime class synthesis (CONVENTIONS §2 / §8); return a factory closure that builds configured
//   `SVGPath` instances — the call-site replacement for `const Sub = extendFromString(...); new Sub(opts)`.
// factory-closure stand-in for the synthesized `class Sub extends SVGPath`.
public func extendFromString(_ str: String?, _ defaultOpts: SVGPathOption? = nil) -> (SVGPathOption?) -> SVGPath {
    let innerOpts = createPathOptions(str, defaultOpts)
    return { (opts: SVGPathOption?) -> SVGPath in
        let sub = SVGPath(opts)
        sub.__applyTransformClosure = innerOpts.applyTransform
        sub.__buildPathClosure = innerOpts.buildPath
        return sub
    }
}

/**
 * Merge multiple paths
 */
// TODO Apply transform
// TODO stroke dash
// TODO Optimize double memory cost problem
//
// upstream reassigns `pathBundle.buildPath = function (path) {...}`. Swift can't reassign the method,
//   so the bundle is a small `MergedPath: Path` subclass holding the merged `pathList` and overriding
//   `buildPath` to append it (matching the captured-closure semantics).
final class MergedPath: Path {
    var pathList: [PathProxy] = []
    override func buildPath(_ ctx: PathProxy, _ shape: PathShape, _ inBatch: Bool) {
        // if (isPathProxy(path)) { path.appendPath(pathList); ... }
        // isPathProxy is always true in the Swift seam (ctx is a PathProxy).
        ctx.appendPath(pathList)
        // Svg and vml renderer don't have context
        // const ctx = path.getContext(); if (ctx) { path.rebuildPath(ctx, 1); }
        //   Path bundle not support percent draw. (renderer seam — CONVENTIONS §9, not ported).
    }
}

public func mergePath(_ pathEls: [Path], _ opts: PathProps?) -> Path {
    var pathList: [PathProxy] = []
    let len = pathEls.count
    for i in 0..<len {
        let pathEl = pathEls[i]
        pathList.append(pathEl.getUpdatedPathProxy(true))
    }

    let pathBundle = MergedPath(opts)
    // Need path proxy.
    pathBundle.createPathProxy()
    pathBundle.pathList = pathList

    return pathBundle
}

// opts bag for clonePath (TS inline object type).
public struct ClonePathOption {
    /// If bake global transform to path.
    public var bakeTransform: Bool?
    /// Convert global transform to local.
    public var toLocal: Bool?
    public init(bakeTransform: Bool? = nil, toLocal: Bool? = nil) {
        self.bakeTransform = bakeTransform
        self.toLocal = toLocal
    }
}

/**
 * Clone a path.
 */
public func clonePath(_ sourcePath: Path, _ opts: ClonePathOption? = nil) -> Path {
    let opts = opts ?? ClonePathOption()
    let path = Path()
    if sourcePath.shape != nil {
        path.setShape(sourcePath.shape)
    }
    // path.setStyle(sourcePath.style);
    // upstream `setStyle` MERGES `sourcePath.style` (PathStyleProps) into the fresh
    //   default style. Our rich style lives in `pathStyle`; `useStyle` assigns it (the source style
    //   is already a created/magic style, so it round-trips by value). Merge is WRONG here: a fresh
    //   Path()'s pathStyle.fill defaults to "#000", and extendPathStyle skips nil source fields, so a
    //   stroke-only source (fill == nil for Line/Polyline/BezierCurve/Arc/Rose/Trochoid) cannot clear
    //   that default → spurious black fill (the "closed-shape black fill" trap). Upstream's
    //   extend/Object.assign copies the source's own key fill=null; PathStyleProps cannot represent
    //   "key present == null" vs "absent", so only a wholesale value-replace reproduces the resolved
    //   upstream style (including the null fill). The setStyle(PathStyleProps) merge overload exists
    //   for genuinely-partial callers; clonePath must use replace.
    path.useStyle(sourcePath.pathStyle)

    if opts.bakeTransform == true {
        // `path.path` is created lazily (nil until buildPath/getBoundingRect). Upstream
        //   relies on it existing; morph callers build the proxy first. Faithful call kept.
        transformPath(path.path, sourcePath.getComputedTransform())
    }
    else {
        // TODO Copy getLocalTransform, updateTransform since they can be changed.
        if opts.toLocal == true {
            path.setLocalTransform(sourcePath.getComputedTransform())
        }
        else {
            path.copyTransform(sourcePath)
        }
    }

    // These methods may be overridden
    // upstream: `path.buildPath = sourcePath.buildPath`. Swift methods are not assignable, so carry the
    //   source's `buildPath` via the `__morphBuildPath` build-hook (the same seam decal/morphPath use;
    //   honored by getUpdatedPathProxy / getCachedPathProxy / getBoundingRect in place of `buildPath`).
    //   Delegating to `sourcePath.buildPath` while passing the clone's OWN `shape` mirrors JS invoking
    //   the reassigned method with `this === path`: a shaped source (Rect/Circle/…) reads the passed
    //   shape, while an SVGPath / MergedPath ignores it and emits from its captured proxy. Without this
    //   the clone kept only `setShape` and rendered the base no-op geometry (empty). `path` is captured
    //   weakly to avoid a retain cycle (it owns the closure); `path.shape` is never nil (base
    //   `getDefaultShape()` seeds an `EmptyPathShape`, and a non-nil source shape replaced it above).
    path.__morphBuildPath = { [weak path] ctx in
        guard let path = path else { return }
        sourcePath.buildPath(ctx, path.shape, false)
    }
    //   The upstream `(path as SVGPath).applyTransform = (path as SVGPath).applyTransform` line is a
    //   no-op self-assignment; there is nothing to port.

    path.z = sourcePath.z
    path.z2 = sourcePath.z2
    path.zlevel = sourcePath.zlevel

    return path
}
