// Ported from zrender/src/tool/morphPath.ts — keep in sync with upstream
//
// NAMESPACE DEVIATION (CONVENTIONS §2): a free-function module would normally become a caseless
//   `enum` named after the file (`morphPath`). But `morphPath` is itself one of the exported
//   functions, and upstream consumers import the exports as NAMED imports
//   (`import { morphPath, combineMorph, separateMorph, alignBezierCurves, centroid, isMorphing,
//   isCombineMorphing } from './morphPath'`). Exposing them as top-level `public func`s keeps call
//   sites byte-identical to upstream. The non-exported helpers stay file-private, mirroring their
//   upstream (un-exported) visibility. Same precedent as Tool/ToolPath.swift / Tool/dividePath.swift.
//
// MONKEY-PATCH SEAM (CONVENTIONS §2 / §9): upstream `saveAndModifyMethod` / `restoreMethod` REASSIGN
//   methods (`buildPath`, `updateTransform`, `addSelfToZr`, `removeSelfFromZr`, `childrenRef`) on a
//   LIVE Path/Element instance. Swift cannot reassign methods on an existing object, so the four
//   patched methods consult typed optional hooks added to Path/Element/Transformable
//   (`__morphBuildPath`, `__morphIgnoreTransform`, `__morphAddSelfToZrAfter`,
//   `__morphRemoveSelfFromZrAfter`, `__morphChildrenRef`, `__morphT`, `__isCombineMorphing`).
//   `saveAndModifyMethod` is modeled by direct hook assignment (commented with its upstream call);
//   `restoreMethod` clears the matching hook. The generic `__mOriginal_<method>` save slot is folded
//   into the typed hook being non-nil.
//
// ANIMATION HOOKUP: `morphPath` / `combineMorph` drive the morph via `toPath.animateTo({ __morphT: 1 })`
//   (Element.animateTo). The Animator/animateTo bodies are a Phase-3 type-surface stub today, so the
//   morph is geometrically faithful but does not yet *drive* at runtime; the buildPath interpolation
//   below is the real bar→pie geometry. (PORT-TODO: once animateTo is real, this morphs live.)

import Foundation

// upstream imports (resolved to the ported modules):
// import PathProxy from '../core/PathProxy';                  → Core/PathProxy.swift
// import { cubicSubdivide } from '../core/curve';             → Core/curve.swift (curve.cubicSubdivide)
// import Path from '../graphic/Path';                         → Graphic/Path.swift
// import Element, { ElementAnimateConfig } from '../Element';  → Element.swift
// import { defaults, map } from '../core/util';               → util.defaults / util.map
// import { lerp } from '../core/vector';                      → vector.lerp
// import Group, { GroupLike } from '../graphic/Group';        → Graphic/Group.swift
// import { clonePath } from './path';                         → Tool/ToolPath.swift (clonePath)
// import { MatrixArray } from '../core/matrix';               → Core/matrix.swift
// import Transformable from '../core/Transformable';          → Core/Transformable.swift
// import { ZRenderType } from '../zrender';                   → ZRender.swift (typealias ZRenderType)
// import { split } from './dividePath';                       → Tool/dividePath.swift (split)
// import { pathToBezierCurves } from './convertPath';         → Tool/convertPath.swift (pathToBezierCurves)

private func alignSubpath(_ subpath1: [Double], _ subpath2: [Double]) -> ([Double], [Double]) {
    let len1 = subpath1.count
    let len2 = subpath2.count
    if len1 == len2 {
        return (subpath1, subpath2)
    }
    var tmpSegX: [Double] = []
    var tmpSegY: [Double] = []

    let shorterPath = len1 < len2 ? subpath1 : subpath2
    let shorterLen = Swift.min(len1, len2)
    // Should divide excatly
    let diff = Double(Swift.abs(len2 - len1)) / 6
    let shorterBezierCount = Double(shorterLen - 2) / 6
    // Add `diff` number of beziers
    let eachCurveSubDivCount = ceil(diff / shorterBezierCount) + 1

    var newSubpath: [Double] = [shorterPath[0], shorterPath[1]]
    var remained = diff

    var i = 2
    while i < shorterLen {
        var x0 = shorterPath[i - 2]
        var y0 = shorterPath[i - 1]
        var x1 = shorterPath[i]; i += 1
        var y1 = shorterPath[i]; i += 1
        var x2 = shorterPath[i]; i += 1
        var y2 = shorterPath[i]; i += 1
        let x3 = shorterPath[i]; i += 1
        let y3 = shorterPath[i]; i += 1

        if remained <= 0 {
            newSubpath.append(contentsOf: [x1, y1, x2, y2, x3, y3])
            continue
        }

        let actualSubDivCount = Swift.min(remained, eachCurveSubDivCount - 1) + 1
        var k = 1
        while Double(k) <= actualSubDivCount {
            let p = Double(k) / actualSubDivCount

            tmpSegX = curve.cubicSubdivide(x0, x1, x2, x3, p)
            tmpSegY = curve.cubicSubdivide(y0, y1, y2, y3, p)

            // tmpSegX[3] === tmpSegX[4]
            x0 = tmpSegX[3]
            y0 = tmpSegY[3]

            newSubpath.append(contentsOf: [tmpSegX[1], tmpSegY[1], tmpSegX[2], tmpSegY[2], x0, y0])
            x1 = tmpSegX[5]
            y1 = tmpSegY[5]
            x2 = tmpSegX[6]
            y2 = tmpSegY[6]
            // The last point (x3, y3) is still the same.
            k += 1
        }
        remained -= actualSubDivCount - 1
        // suppress "never read after final assignment" warnings for faithfully-tracked locals
        _ = x1; _ = y1; _ = x2; _ = y2
    }

    return shorterPath == subpath1 ? (newSubpath, subpath2) : (subpath1, newSubpath)
}

private func createSubpath(_ lastSubpathSubpath: [Double], _ otherSubpath: [Double]) -> [Double] {
    let len = lastSubpathSubpath.count
    let lastX = lastSubpathSubpath[len - 2]
    let lastY = lastSubpathSubpath[len - 1]

    var newSubpath: [Double] = []
    var i = 0
    while i < otherSubpath.count {
        newSubpath.append(lastX); i += 1
        newSubpath.append(lastY); i += 1
    }
    return newSubpath
}

/**
 * Make two bezier arrays aligns on structure. To have better animation.
 *
 * It will:
 * Make two bezier arrays have same number of subpaths.
 * Make each subpath has equal number of bezier curves.
 *
 * array is the convert result of pathToBezierCurves.
 */
public func alignBezierCurves(_ array1: [[Double]], _ array2: [[Double]]) -> ([[Double]], [[Double]]) {

    var lastSubpath1: [Double]? = nil
    var lastSubpath2: [Double]? = nil

    var newArray1: [[Double]] = []
    var newArray2: [[Double]] = []

    for i in 0..<Swift.max(array1.count, array2.count) {
        // upstream `array1[i]` may be undefined → modeled as Optional.
        let subpath1: [Double]? = i < array1.count ? array1[i] : nil
        let subpath2: [Double]? = i < array2.count ? array2[i] : nil

        var newSubpath1: [Double]
        var newSubpath2: [Double]

        if subpath1 == nil {
            newSubpath1 = createSubpath(lastSubpath1 ?? subpath2!, subpath2!)
            newSubpath2 = subpath2!
        }
        else if subpath2 == nil {
            newSubpath2 = createSubpath(lastSubpath2 ?? subpath1!, subpath1!)
            newSubpath1 = subpath1!
        }
        else {
            (newSubpath1, newSubpath2) = alignSubpath(subpath1!, subpath2!)
            lastSubpath1 = newSubpath1
            lastSubpath2 = newSubpath2
        }

        newArray1.append(newSubpath1)
        newArray2.append(newSubpath2)
    }

    return (newArray1, newArray2)
}

// upstream: interface MorphingPath extends Path { __morphT: number }
//   → Path.__morphT (Graphic/Path.swift, morphPath seam).
// upstream: export interface CombineMorphingPath extends Path { childrenRef(); __isCombineMorphing }
//   → Path.childrenRef() / Path.__isCombineMorphing (Graphic/Path.swift, morphPath seam).

public func centroid(_ array: [Double]) -> [Double] {
    // https://en.wikipedia.org/wiki/Centroid#Of_a_polygon
    var signedArea: Double = 0
    var cx: Double = 0
    var cy: Double = 0
    let len = array.count
    // Polygon should been closed.
    var i = 0
    var j = len - 2
    while i < len {
        let x0 = array[j]
        let y0 = array[j + 1]
        let x1 = array[i]
        let y1 = array[i + 1]
        let a = x0 * y1 - x1 * y0
        signedArea += a
        cx += (x0 + x1) * a
        cy += (y0 + y1) * a
        j = i
        i += 2
    }

    if signedArea == 0 {
        // upstream: `array[0] || 0` (JS-falsy → 0). Guard empty + NaN per CONVENTIONS §5.
        return [array.first ?? 0, array.count > 1 ? array[1] : 0]
    }

    return [cx / signedArea / 3, cy / signedArea / 3, signedArea]
}

// upstream `fromCp[2] < 0` reads `signedArea` — which is absent (undefined) when `centroid` short-
//   circuited (`signedArea === 0`). JS `undefined < 0` is false; Swift `cp[2]` would trap, so test
//   existence first. Replicates `cp[2] < 0` exactly.
private func centroidSignNegative(_ cp: [Double]) -> Bool {
    return cp.count > 2 && cp[2] < 0
}

/**
 * Offset the points to find the nearest morphing distance.
 * Return beziers count needs to be offset.
 */
private func findBestRingOffset(
    _ fromSubBeziers: [Double],
    _ toSubBeziers: [Double],
    _ fromCp: [Double],
    _ toCp: [Double]
) -> Int {
    let bezierCount = (fromSubBeziers.count - 2) / 6
    var bestScore = Double.infinity
    var bestOffset = 0

    let len = fromSubBeziers.count
    let len2 = len - 2
    for offset in 0..<bezierCount {
        let cursorOffset = offset * 6
        var score: Double = 0

        var k = 0
        while k < len {
            let idx = k == 0 ? cursorOffset : ((cursorOffset + k - 2) % len2 + 2)

            let x0 = fromSubBeziers[idx] - fromCp[0]
            let y0 = fromSubBeziers[idx + 1] - fromCp[1]
            let x1 = toSubBeziers[k] - toCp[0]
            let y1 = toSubBeziers[k + 1] - toCp[1]

            let dx = x1 - x0
            let dy = y1 - y0
            score += dx * dx + dy * dy
            k += 2
        }
        if score < bestScore {
            bestScore = score
            bestOffset = offset
        }
    }

    return bestOffset
}

private func reverse(_ array: [Double]) -> [Double] {
    let len = array.count
    var newArr = [Double](repeating: 0, count: len)
    var i = 0
    while i < len {
        newArr[i] = array[len - i - 2]
        newArr[i + 1] = array[len - i - 1]
        i += 2
    }
    return newArr
}

// type MorphingData = { from; to; fromCp; toCp; rotation }[]
private struct MorphingDataItem {
    var from: [Double]
    var to: [Double]
    var fromCp: [Double]
    var toCp: [Double]
    var rotation: Double
}
private typealias MorphingData = [MorphingDataItem]

/**
 * If we interpolating between two bezier curve arrays.
 * It will have many broken effects during the transition.
 * So we try to apply an extra rotation which can make each bezier curve morph as small as possible.
 */
private func findBestMorphingRotation(
    _ fromArr: [[Double]],
    _ toArr: [[Double]],
    _ searchAngleIteration: Double,
    _ searchAngleRange: Double
) -> MorphingData {
    var result: MorphingData = []

    var fromNeedsReverse: Bool? = nil

    for i in 0..<fromArr.count {
        var fromSubpathBezier = fromArr[i]
        let toSubpathBezier = toArr[i]

        let fromCp = centroid(fromSubpathBezier)
        let toCp = centroid(toSubpathBezier)

        if fromNeedsReverse == nil {
            // Reverse from array if two have different directions.
            // Determine the clockwise based on the first subpath.
            // Reverse all subpaths or not. Avoid winding rule changed.
            fromNeedsReverse = centroidSignNegative(fromCp) != centroidSignNegative(toCp)
        }

        var newFromSubpathBezier = [Double](repeating: 0, count: fromSubpathBezier.count)
        var newToSubpathBezier = [Double](repeating: 0, count: fromSubpathBezier.count)
        var bestAngle: Double = 0
        var bestScore = Double.infinity
        var tmpArr = [Double](repeating: 0, count: fromSubpathBezier.count)

        let len = fromSubpathBezier.count
        if fromNeedsReverse == true {
            // Make sure clockwise
            fromSubpathBezier = reverse(fromSubpathBezier)
        }
        let offset = findBestRingOffset(fromSubpathBezier, toSubpathBezier, fromCp, toCp) * 6

        let len2 = len - 2
        var k = 0
        while k < len2 {
            // Not include the start point.
            let idx = (offset + k) % len2 + 2
            newFromSubpathBezier[k + 2] = fromSubpathBezier[idx] - fromCp[0]
            newFromSubpathBezier[k + 3] = fromSubpathBezier[idx + 1] - fromCp[1]
            k += 2
        }
        newFromSubpathBezier[0] = fromSubpathBezier[offset] - fromCp[0]
        newFromSubpathBezier[1] = fromSubpathBezier[offset + 1] - fromCp[1]

        if searchAngleIteration > 0 {
            let step = searchAngleRange / searchAngleIteration
            var angle = -searchAngleRange / 2
            while angle <= searchAngleRange / 2 {
                let sa = sin(angle)
                let ca = cos(angle)
                var score: Double = 0

                var kk = 0
                while kk < fromSubpathBezier.count {
                    let x0 = newFromSubpathBezier[kk]
                    let y0 = newFromSubpathBezier[kk + 1]
                    let x1 = toSubpathBezier[kk] - toCp[0]
                    let y1 = toSubpathBezier[kk + 1] - toCp[1]

                    // Apply rotation on the target point.
                    let newX1 = x1 * ca - y1 * sa
                    let newY1 = x1 * sa + y1 * ca

                    tmpArr[kk] = newX1
                    tmpArr[kk + 1] = newY1

                    let dx = newX1 - x0
                    let dy = newY1 - y0

                    // Use dot product to have min direction change.
                    // const d = Math.sqrt(x0 * x0 + y0 * y0);
                    // score += x0 * dx / d + y0 * dy / d;
                    score += dx * dx + dy * dy
                    kk += 2
                }

                if score < bestScore {
                    bestScore = score
                    bestAngle = angle
                    // Copy.
                    for m in 0..<tmpArr.count {
                        newToSubpathBezier[m] = tmpArr[m]
                    }
                }
                angle += step
            }
        }
        else {
            var ii = 0
            while ii < len {
                newToSubpathBezier[ii] = toSubpathBezier[ii] - toCp[0]
                newToSubpathBezier[ii + 1] = toSubpathBezier[ii + 1] - toCp[1]
                ii += 2
            }
        }

        result.append(MorphingDataItem(
            from: newFromSubpathBezier,
            to: newToSubpathBezier,
            fromCp: fromCp,
            toCp: toCp,
            rotation: -bestAngle
        ))
    }
    return result
}

public func isCombineMorphing(_ path: Element) -> Bool {
    return (path as? Path)?.__isCombineMorphing ?? false
}

public func isMorphing(_ el: Element) -> Bool {
    // upstream: (el as MorphingPath).__morphT >= 0 — undefined (non-Path) reads as false.
    if let p = el as? Path {
        return p.__morphT >= 0
    }
    return false
}

// upstream: const SAVED_METHOD_PREFIX = '__mOriginal_';
//   saveAndModifyMethod / restoreMethod monkey-patch methods on a live instance. Swift can't reassign
//   methods, so the patched methods are routed through typed hooks (see the file header). The generic
//   `saveAndModifyMethod` is realized at each call site by direct hook assignment (commented with its
//   upstream call). `restoreMethod` clears the matching hook by method name.
private func restoreMethod(_ obj: Element, _ methodName: String) {
    switch methodName {
    case "buildPath":
        (obj as? Path)?.__morphBuildPath = nil
    case "updateTransform":
        obj.__morphIgnoreTransform = false
    case "addSelfToZr":
        obj.__morphAddSelfToZrAfter = nil
    case "removeSelfFromZr":
        obj.__morphRemoveSelfFromZrAfter = nil
    case "childrenRef":
        (obj as? Path)?.__morphChildrenRef = nil
    default:
        break
    }
}

private func applyTransformOnBeziers(_ bezierCurves: inout [[Double]], _ mm: MatrixArray) {
    for i in 0..<bezierCurves.count {
        var subBeziers = bezierCurves[i]
        var k = 0
        while k < subBeziers.count {
            let x = subBeziers[k]
            let y = subBeziers[k + 1]

            subBeziers[k] = mm[0] * x + mm[2] * y + mm[4]; k += 1
            subBeziers[k] = mm[1] * x + mm[3] * y + mm[5]; k += 1
        }
        bezierCurves[i] = subBeziers
    }
}

private func prepareMorphPath(
    _ fromPath: Path,
    _ toPath: Path
) {
    let fromPathProxy = fromPath.getUpdatedPathProxy()
    let toPathProxy = toPath.getUpdatedPathProxy()

    var (fromBezierCurves, toBezierCurves) =
        alignBezierCurves(pathToBezierCurves(fromPathProxy), pathToBezierCurves(toPathProxy))

    let fromPathTransform = fromPath.getComputedTransform()
    let toPathTransform = toPath.getComputedTransform()
    // function updateIdentityTransform(this: Transformable) { this.transform = null; }
    //   → modeled by the `__morphIgnoreTransform` flag (Core/Transformable.swift).
    if let fromPathTransform = fromPathTransform { applyTransformOnBeziers(&fromBezierCurves, fromPathTransform) }
    if let toPathTransform = toPathTransform { applyTransformOnBeziers(&toBezierCurves, toPathTransform) }
    // Just ignore transform
    // saveAndModifyMethod(toPath, 'updateTransform', { replace: updateIdentityTransform })
    toPath.__morphIgnoreTransform = true
    toPath.transform = nil

    let morphingData = findBestMorphingRotation(fromBezierCurves, toBezierCurves, 10, Double.pi)

    // saveAndModifyMethod(toPath, 'buildPath', { replace(path: PathProxy) { ... } })
    toPath.__morphBuildPath = { [weak toPath] path in
        guard let toPath = toPath else { return }
        let t = toPath.__morphT
        let onet = 1 - t

        for i in 0..<morphingData.count {
            let item = morphingData[i]
            let from = item.from
            let to = item.to
            let angle = item.rotation * t
            let fromCp = item.fromCp
            let toCp = item.toCp
            let sa = sin(angle)
            let ca = cos(angle)

            // lerp(newCp, fromCp, toCp, t) — only [0]/[1] are used (centroid may carry a 3rd elem).
            let newCp = vector.lerp(VectorArray(fromCp[0], fromCp[1]), VectorArray(toCp[0], toCp[1]), t)

            // upstream reuses one captured `tmpArr`; allocated per-item here (sizes vary per subpath).
            var tmpArr = [Double](repeating: 0, count: from.count)

            var m = 0
            while m < from.count {
                let x0v = from[m]
                let y0v = from[m + 1]
                let x1v = to[m]
                let y1v = to[m + 1]

                let x = x0v * onet + x1v * t
                let y = y0v * onet + y1v * t

                tmpArr[m] = (x * ca - y * sa) + newCp[0]
                tmpArr[m + 1] = (x * sa + y * ca) + newCp[1]
                m += 2
            }

            var x0 = tmpArr[0]
            var y0 = tmpArr[1]

            _ = path.moveTo(x0, y0)

            var n = 2
            while n < from.count {
                let x1 = tmpArr[n]; n += 1
                let y1 = tmpArr[n]; n += 1
                let x2 = tmpArr[n]; n += 1
                let y2 = tmpArr[n]; n += 1
                let x3 = tmpArr[n]; n += 1
                let y3 = tmpArr[n]; n += 1

                // Is a line.
                if x0 == x1 && y0 == y1 && x2 == x3 && y2 == y3 {
                    _ = path.lineTo(x3, y3)
                }
                else {
                    _ = path.bezierCurveTo(x1, y1, x2, y2, x3, y3)
                }
                x0 = x3
                y0 = y3
            }
        }
    }
}

/**
 * Morphing from old path to new path.
 */
public func morphPath(
    _ fromPath: Path?,
    _ toPath: Path?,
    _ animationOpts: ElementAnimateConfig
) -> Path? {
    if fromPath == nil || toPath == nil {
        return toPath
    }
    let fromPath = fromPath!
    let toPath = toPath!

    let oldDone = animationOpts.done
    // const oldAborted = animationOpts.aborted;
    let oldDuring = animationOpts.during

    prepareMorphPath(fromPath, toPath)

    toPath.__morphT = 0

    func restoreToPath() {
        restoreMethod(toPath, "buildPath")
        restoreMethod(toPath, "updateTransform")
        // Mark as not in morphing
        toPath.__morphT = -1
        // Cleanup.
        toPath.createPathProxy()
        toPath.dirtyShape()
    }

    // defaults({ during, done }, animationOpts) — during/done override, rest from animationOpts.
    var cfg = animationOpts
    cfg.during = { p in
        toPath.dirtyShape()
        oldDuring?(p)
    }
    cfg.done = {
        restoreToPath()
        oldDone?()
    }
    // NOTE: Don't do restore if aborted.
    // Because all status was just set when animation started.
    // aborted() { oldAborted && oldAborted(); }
    toPath.animateTo(["__morphT": 1.0], cfg)

    return toPath
}

// https://github.com/mapbox/earcut/blob/master/src/earcut.js#L437
// https://jsfiddle.net/pissang/2jk7x145/
// (zOrder commented out upstream — omitted.)

// JS bitwise `&` coerces both operands via ToInt32 (truncate toward zero, mod 2^32, signed).
private func toInt32(_ v: Double) -> Int32 {
    if !v.isFinite { return 0 }
    let m = v.rounded(.towardZero)
    let mod = m.truncatingRemainder(dividingBy: 4294967296.0) // 2^32
    var n = mod < 0 ? mod + 4294967296.0 : mod
    if n >= 2147483648.0 { n -= 4294967296.0 } // 2^31
    return Int32(n)
}

// https://github.com/w8r/hilbert/blob/master/hilbert.js#L30
// https://jsfiddle.net/pissang/xdnbzg6v/
private func hilbert(_ x0: Double, _ y0: Double, _ minX: Double, _ minY: Double, _ maxX: Double, _ maxY: Double) -> Double {
    let bits = 16
    // Math.round rounds half up (== floor(x + 0.5)); see CONVENTIONS §5.
    var x = (maxX == minX) ? 0.0 : floor(32767 * (x0 - minX) / (maxX - minX) + 0.5)
    var y = (maxY == minY) ? 0.0 : floor(32767 * (y0 - minY) / (maxY - minY) + 0.5)

    var d: Double = 0
    var s = Double(1 << bits) / 2
    while s > 0 {
        var rx: Double = 0
        var ry: Double = 0

        if (toInt32(x) & toInt32(s)) > 0 {
            rx = 1
        }
        if (toInt32(y) & toInt32(s)) > 0 {
            ry = 1
        }

        d += s * s * Double((3 * Int(rx)) ^ Int(ry))

        if ry == 0 {
            if rx == 1 {
                x = s - 1 - x
                y = s - 1 - y
            }
            let tmp = x
            x = y
            y = tmp
        }
        s /= 2
    }
    return d
}

// Sort paths on hilbert. Not using z-order because it may still have large cross.
// So the left most source can animate to the left most target, not right most target.
// Hope in this way. We can make sure each element is animated to the proper target. Not the farthest.
private func sortPaths(_ pathList: [Path]) -> [Path] {
    var xMin = Double.infinity
    var yMin = Double.infinity
    var xMax = -Double.infinity
    var yMax = -Double.infinity
    let cps = util.map(pathList) { path, _ -> [Double] in
        let rect = path.getBoundingRect()!
        let m = path.getComputedTransform()
        let x = rect.x + rect.width / 2 + (m != nil ? m![4] : 0)
        let y = rect.y + rect.height / 2 + (m != nil ? m![5] : 0)
        xMin = Swift.min(x, xMin)
        yMin = Swift.min(y, yMin)
        xMax = Swift.max(x, xMax)
        yMax = Swift.max(y, yMax)
        return [x, y]
    }

    let items = util.map(cps) { cp, idx -> (cp: [Double], z: Double, path: Path) in
        return (
            cp: cp,
            z: hilbert(cp[0], cp[1], xMin, yMin, xMax, yMax),
            path: pathList[idx]
        )
    }

    return items.sorted { a, b in a.z < b.z }.map { $0.path }
}

// export interface DividePathParams { path: Path, count: number }
public struct DividePathParams {
    public var path: Path
    public var count: Double
    public init(path: Path, count: Double) {
        self.path = path
        self.count = count
    }
}
// export interface DividePath { (params: DividePathParams): Path[] }
public typealias DividePath = (DividePathParams) -> [Path]

// export interface IndividualDelay { (index, count, fromPath, toPath): number }
public typealias IndividualDelay = (_ index: Double, _ count: Double, _ fromPath: Path, _ toPath: Path) -> Double

private func defaultDividePath(_ param: DividePathParams) -> [Path] {
    return split(param.path, param.count)
}

// export interface CombineConfig extends ElementAnimateConfig { dividePath?; individualDelay? }
//   ElementAnimateConfig is a struct (no inheritance); the base config is composed as `base`.
//   Upstream `animationOpts.done` / `.during` / `.delay` map to `animationOpts.base.*`.
public struct CombineConfig {
    /// Base animation config. (upstream: the inherited ElementAnimateConfig fields.)
    public var base: ElementAnimateConfig
    /// Transform of returned will be ignored.
    public var dividePath: DividePath?
    /// delay of each individual. Because individual are sorted on z-order. The index is also sorted
    /// top-left / right-down.
    public var individualDelay: IndividualDelay?
    // If sort splitted paths so the movement between them can be more natural
    // sort?: boolean
    public init(base: ElementAnimateConfig = ElementAnimateConfig(),
                dividePath: DividePath? = nil,
                individualDelay: IndividualDelay? = nil) {
        self.base = base
        self.dividePath = dividePath
        self.individualDelay = individualDelay
    }
}

// function createEmptyReturn() { return { fromIndividuals, toIndividuals, count }; }
public struct MorphResult {
    public var fromIndividuals: [Path]
    public var toIndividuals: [Path]
    public var count: Double
    public init(fromIndividuals: [Path], toIndividuals: [Path], count: Double) {
        self.fromIndividuals = fromIndividuals
        self.toIndividuals = toIndividuals
        self.count = count
    }
}
private func createEmptyReturn() -> MorphResult {
    return MorphResult(fromIndividuals: [], toIndividuals: [], count: 0)
}

/**
 * Make combine morphing from many paths to one.
 * Will return a group to replace the original path.
 */
public func combineMorph(
    _ fromList: [Path],
    _ toPath: Path,
    _ animationOpts: CombineConfig
) -> MorphResult {
    var fromPathList: [Path] = []

    func addFromPath(_ fromList: [Element]) {
        for i in 0..<fromList.count {
            let from = fromList[i]
            if isCombineMorphing(from) {
                addFromPath((from as! Path).childrenRef())
            }
            else if from is Path {
                fromPathList.append(from as! Path)
            }
        }
    }
    addFromPath(fromList.map { $0 as Element })

    let separateCount = fromPathList.count

    // fromPathList.length is 0.
    if separateCount == 0 {
        return createEmptyReturn()
    }

    let dividePath = animationOpts.dividePath ?? defaultDividePath

    var toSubPathList = dividePath(DividePathParams(path: toPath, count: Double(separateCount)))
    if toSubPathList.count != separateCount {
        // PORT-NOTE: console.error('Invalid morphing: unmatched splitted path')
        return createEmptyReturn()
    }

    fromPathList = sortPaths(fromPathList)
    toSubPathList = sortPaths(toSubPathList)

    let oldDone = animationOpts.base.done
    // const oldAborted = animationOpts.aborted;
    let oldDuring = animationOpts.base.during
    let individualDelay = animationOpts.individualDelay

    let identityTransform = Transformable()

    for i in 0..<separateCount {
        let from = fromPathList[i]
        let to = toSubPathList[i]

        to.parent = toPath

        // Ignore transform in each subpath.
        to.copyTransform(identityTransform)

        // Will do morphPath for each individual if individualDelay is set.
        if individualDelay == nil {
            prepareMorphPath(from, to)
        }
    }

    toPath.__isCombineMorphing = true
    // (toPath as CombineMorphingPath).childrenRef = function () { return toSubPathList; };
    toPath.__morphChildrenRef = { toSubPathList }

    func addToSubPathListToZr(_ zr: ZRenderType) {
        for i in 0..<toSubPathList.count {
            toSubPathList[i].addSelfToZr(zr)
        }
    }
    // saveAndModifyMethod(toPath, 'addSelfToZr', { after(zr) { addToSubPathListToZr(zr) } })
    toPath.__morphAddSelfToZrAfter = { zr in
        addToSubPathListToZr(zr)
    }
    // saveAndModifyMethod(toPath, 'removeSelfFromZr', { after(zr) { ... } })
    toPath.__morphRemoveSelfFromZrAfter = { zr in
        for i in 0..<toSubPathList.count {
            toSubPathList[i].removeSelfFromZr(zr)
        }
    }

    func restoreToPath() {
        toPath.__isCombineMorphing = false
        // Mark as not in morphing
        toPath.__morphT = -1
        toPath.__morphChildrenRef = nil

        restoreMethod(toPath, "addSelfToZr")
        restoreMethod(toPath, "removeSelfFromZr")
    }

    let toLen = toSubPathList.count

    if let individualDelay = individualDelay {
        var animating = toLen
        let eachDone: () -> Void = {
            animating -= 1
            if animating == 0 {
                restoreToPath()
                oldDone?()
            }
        }
        // Animate each element individually.
        for i in 0..<toLen {
            // TODO only call during once?
            var indivdualAnimationOpts = animationOpts.base
            indivdualAnimationOpts.delay = (animationOpts.base.delay ?? 0)
                + individualDelay(Double(i), Double(toLen), fromPathList[i], toSubPathList[i])
            indivdualAnimationOpts.done = eachDone
            _ = morphPath(fromPathList[i], toSubPathList[i], indivdualAnimationOpts)
        }
    }
    else {
        toPath.__morphT = 0
        var cfg = animationOpts.base
        cfg.during = { p in
            for i in 0..<toLen {
                let child = toSubPathList[i]
                child.__morphT = toPath.__morphT
                child.dirtyShape()
            }
            oldDuring?(p)
        }
        cfg.done = {
            restoreToPath()
            for i in 0..<fromList.count {
                restoreMethod(fromList[i], "updateTransform")
            }
            oldDone?()
        }
        toPath.animateTo(["__morphT": 1.0], cfg)
    }

    if let zr = toPath.__zr {
        addToSubPathListToZr(zr)
    }

    return MorphResult(
        fromIndividuals: fromPathList,
        toIndividuals: toSubPathList,
        count: Double(toLen)
    )
}

// export interface SeparateConfig extends ElementAnimateConfig { dividePath?; individualDelay? }
public struct SeparateConfig {
    /// Base animation config. (upstream: the inherited ElementAnimateConfig fields.)
    public var base: ElementAnimateConfig
    public var dividePath: DividePath?
    public var individualDelay: IndividualDelay?
    // If sort splitted paths so the movement between them can be more natural
    // sort?: boolean
    // // If the from path of separate animation is doing combine animation.
    // // And the paths number is not same with toPathList. We need to do enter/leave animation
    // // on the missing/spare paths.
    // enter?: (el: Path) => void
    // leave?: (el: Path) => void
    public init(base: ElementAnimateConfig = ElementAnimateConfig(),
                dividePath: DividePath? = nil,
                individualDelay: IndividualDelay? = nil) {
        self.base = base
        self.dividePath = dividePath
        self.individualDelay = individualDelay
    }
}

/**
 * Make separate morphing from one path to many paths.
 * Make the MorphingKind of `toPath` become `'ONE_ONE'`.
 */
public func separateMorph(
    _ fromPath: Path,
    _ toPathList: [Path],
    _ animationOpts: SeparateConfig
) -> MorphResult {
    var toPathList = toPathList
    let toLen = toPathList.count
    var fromPathList: [Path] = []

    let dividePath = animationOpts.dividePath ?? defaultDividePath

    func addFromPath(_ fromList: [Element]) {
        for i in 0..<fromList.count {
            let from = fromList[i]
            if isCombineMorphing(from) {
                addFromPath((from as! Path).childrenRef())
            }
            else if from is Path {
                fromPathList.append(from as! Path)
            }
        }
    }
    // This case most happen when a combining path is called to reverse the animation
    // to its original separated state.
    if isCombineMorphing(fromPath) {
        addFromPath(fromPath.childrenRef())

        let fromLen = fromPathList.count
        if fromLen < toLen {
            var k = 0
            for _ in fromLen..<toLen {
                // Create a clone
                fromPathList.append(clonePath(fromPathList[k % fromLen]))
                k += 1
            }
        }
        // Else simply remove if fromLen > toLen
        if fromPathList.count > toLen {
            fromPathList.removeLast(fromPathList.count - toLen)
        }
    }
    else {
        fromPathList = dividePath(DividePathParams(path: fromPath, count: Double(toLen)))
        let fromPathTransform = fromPath.getComputedTransform()
        for i in 0..<fromPathList.count {
            // Force use transform of source path.
            fromPathList[i].setLocalTransform(fromPathTransform)
        }
        if fromPathList.count != toLen {
            // PORT-NOTE: console.error('Invalid morphing: unmatched splitted path')
            return createEmptyReturn()
        }
    }

    fromPathList = sortPaths(fromPathList)
    toPathList = sortPaths(toPathList)

    let individualDelay = animationOpts.individualDelay
    for i in 0..<toLen {
        var indivdualAnimationOpts = animationOpts.base
        if let individualDelay = individualDelay {
            indivdualAnimationOpts.delay = (animationOpts.base.delay ?? 0)
                + individualDelay(Double(i), Double(toLen), fromPathList[i], toPathList[i])
        }
        _ = morphPath(fromPathList[i], toPathList[i], indivdualAnimationOpts)
    }

    return MorphResult(
        fromIndividuals: fromPathList,
        toIndividuals: toPathList,
        count: Double(toPathList.count)
    )
}

// export { split as defaultDividePath };
//   The public divide entry is `split` (Tool/dividePath.swift), already module-public; upstream
//   re-exports it under the name `defaultDividePath`. The file-private `defaultDividePath(param)`
//   above is the internal wrapper (distinct from this re-export, matching upstream's dual binding).
