// Ported from zrender/src/graphic/helper/roundSector.ts — keep in sync with upstream
//
// The corner-radius-aware sector path builder shared by Sector. Translated MATH EXACTLY
// (corner-radius tangents, intersection clamping, inner/outer ring rounding) — these are
// validated byte-for-byte against the real-ECharts golden fixture for 'sector'.
//
// NaN-PROPAGATION NOTE (load-bearing): upstream leaves icrStart/icrEnd/ocrStart/ocrEnd and the
//   derived ocrs/ocre/icrs/icre/...Max values `undefined` when there is no corner radius. Those
//   `undefined`s flow through `Math.min`/`Math.max`, which coerce to `NaN`, and every downstream
//   `> e` comparison against NaN is `false`, so the corner branches are skipped. Swift's
//   `Swift.min`/`Swift.max` do NOT propagate NaN (they return the non-NaN operand), so we use the
//   local `mathMin`/`mathMax` below that replicate JS `Math.min`/`Math.max` NaN semantics, and we
//   seed the "undefined" corner variables with `Double.nan`.

import Foundation

// upstream module-local aliases:
private let PI = Double.pi
private let PI2 = PI * 2
private func mathSin(_ x: Double) -> Double { sin(x) }
private func mathCos(_ x: Double) -> Double { cos(x) }
private func mathACos(_ x: Double) -> Double { acos(x) }
private func mathATan2(_ y: Double, _ x: Double) -> Double { atan2(y, x) }
private func mathAbs(_ x: Double) -> Double { abs(x) }
private func mathSqrt(_ x: Double) -> Double { sqrt(x) }
// NOTE: replicate JS Math.max/Math.min NaN propagation (see header NaN-PROPAGATION NOTE).
private func mathMax(_ a: Double, _ b: Double) -> Double {
    if a.isNaN || b.isNaN { return Double.nan }
    return Swift.max(a, b)
}
private func mathMin(_ a: Double, _ b: Double) -> Double {
    if a.isNaN || b.isNaN { return Double.nan }
    return Swift.min(a, b)
}
private let e = 1e-4

// PORT-NOTE: upstream models the sector corner radius as the inline union `number | number[]`.
//   Modeled as a tagged enum (no untagged unions in Swift). Used by SectorShape + normalizeCornerRadius.
//   PORT-NOTE: `Equatable` is a port addition (upstream compares the raw union with `===`). It lets
//   `anyStrictEqual` (Element.swift) see through the boxed enum so an UNCHANGED corner radius is
//   filtered out of an `animateTo` prop bag instead of always allocating a no-op animator. The only
//   deviation vs upstream is the `.array` case (JS `===` on two equal arrays is false); the animator
//   upstream would create there only re-sets the same value, so the rendered result is unchanged.
public enum CornerRadius: Equatable {
    case number(Double)
    case array([Double])
}

extension CornerRadius {
    // upstream `if (cornerRadius)` truthiness: a number is falsy when 0/NaN; an array (incl. empty)
    //   is always truthy.
    var zrTruthy: Bool {
        switch self {
        case .number(let n): return n != 0 && !n.isNaN
        case .array: return true
        }
    }
}

public enum roundSector {   // upstream module: graphic/helper/roundSector

    // upstream: function intersect(...) : [number, number] | undefined
    static func intersect(
        _ x0: Double, _ y0: Double,
        _ x1: Double, _ y1: Double,
        _ x2: Double, _ y2: Double,
        _ x3: Double, _ y3: Double
    ) -> [Double]? {
        let dx10 = x1 - x0
        let dy10 = y1 - y0
        let dx32 = x3 - x2
        let dy32 = y3 - y2
        var t = dy32 * dx10 - dx32 * dy10
        if t * t < e {
            return nil
        }
        t = (dx32 * (y0 - y2) - dy32 * (x0 - x2)) / t
        return [x0 + t * dx10, y0 + t * dy10]
    }

    // upstream: the return shape of computeCornerTangents
    struct CornerTangents {
        var cx: Double
        var cy: Double
        var x0: Double
        var y0: Double
        var x1: Double
        var y1: Double
    }

    // Compute perpendicular offset line of length rc.
    static func computeCornerTangents(
        _ x0: Double, _ y0: Double,
        _ x1: Double, _ y1: Double,
        _ radius: Double, _ cr: Double,
        _ clockwise: Bool
    ) -> CornerTangents {
        let x01 = x0 - x1
        let y01 = y0 - y1
        let lo = (clockwise ? cr : -cr) / mathSqrt(x01 * x01 + y01 * y01)
        let ox = lo * y01
        let oy = -lo * x01
        let x11 = x0 + ox
        let y11 = y0 + oy
        let x10 = x1 + ox
        let y10 = y1 + oy
        let x00 = (x11 + x10) / 2
        let y00 = (y11 + y10) / 2
        let dx = x10 - x11
        let dy = y10 - y11
        let d2 = dx * dx + dy * dy
        let r = radius - cr
        let s = x11 * y10 - x10 * y11
        let d = (dy < 0 ? -1.0 : 1.0) * mathSqrt(mathMax(0, r * r * d2 - s * s))
        var cx0 = (s * dy - dx * d) / d2
        var cy0 = (-s * dx - dy * d) / d2
        let cx1 = (s * dy + dx * d) / d2
        let cy1 = (-s * dx + dy * d) / d2
        let dx0 = cx0 - x00
        let dy0 = cy0 - y00
        let dx1 = cx1 - x00
        let dy1 = cy1 - y00

        // Pick the closer of the two intersection points
        // TODO: Is there a faster way to determine which intersection to use?
        if dx0 * dx0 + dy0 * dy0 > dx1 * dx1 + dy1 * dy1 {
            cx0 = cx1
            cy0 = cy1
        }

        return CornerTangents(
            cx: cx0,
            cy: cy0,
            x0: -ox,
            y0: -oy,
            x1: cx0 * (radius / r - 1),
            y1: cy0 * (radius / r - 1)
        )
    }

    // For compatibility, don't use normalizeCssArray
    // 5 represents [5, 5, 5, 5]
    // [5] represents [5, 5, 0, 0]
    // [5, 10] represents [5, 5, 10, 10]
    // [5, 10, 15] represents [5, 10, 15, 15]
    // [5, 10, 15, 20] represents [5, 10, 15, 20]
    static func normalizeCornerRadius(_ cr: CornerRadius) -> [Double] {
        var arr: [Double]
        switch cr {
        case .array(let crArr):
            let len = crArr.count
            if len == 0 {
                return crArr
            }
            if len == 1 {
                arr = [crArr[0], crArr[0], 0, 0]
            }
            else if len == 2 {
                arr = [crArr[0], crArr[0], crArr[1], crArr[1]]
            }
            else if len == 3 {
                arr = crArr + [crArr[2]]
            }
            else {
                arr = crArr
            }
        case .number(let cr):
            arr = [cr, cr, cr, cr]
        }
        return arr
    }

    // upstream: export function buildPath(ctx, shape)
    // PORT-NOTE: upstream's `shape` is an inline structural type `{ cx, cy, startAngle, endAngle,
    //   clockwise?, r?, r0?, cornerRadius? }`. Only Sector calls this helper, so we accept the
    //   concrete `SectorShape` (its fields satisfy the structural type). `shape.r0 || 0` collapses
    //   to `shape.r0` since `r0` is a non-optional Double (default 0).
    public static func buildPath(_ ctx: PathProxy, _ shape: SectorShape) {
        var radius = mathMax(shape.r, 0)
        var innerRadius = mathMax(shape.r0, 0)
        let hasRadius = radius > 0
        let hasInnerRadius = innerRadius > 0

        if !hasRadius && !hasInnerRadius {
            return
        }

        if !hasRadius {
            // use innerRadius as radius if no radius
            radius = innerRadius
            innerRadius = 0
        }

        if innerRadius > radius {
            // swap, ensure that radius is always larger than innerRadius
            let tmp = radius
            radius = innerRadius
            innerRadius = tmp
        }

        let startAngle = shape.startAngle
        let endAngle = shape.endAngle
        if startAngle.isNaN || endAngle.isNaN {
            return
        }

        let cx = shape.cx
        let cy = shape.cy
        let clockwise = shape.clockwise

        var arc = mathAbs(endAngle - startAngle)
        // upstream: const mod = arc > PI2 && arc % PI2; mod > e && (arc = mod);
        //   `false` (when arc <= PI2) coerces to 0 in the `mod > e` test, so we model it as 0.
        let mod = arc > PI2 ? arc.truncatingRemainder(dividingBy: PI2) : 0
        if mod > e { arc = mod }

        // is a point
        if !(radius > e) {
            _ = ctx.moveTo(cx, cy)
        }
        // is a circle or annulus
        else if arc > PI2 - e {
            _ = ctx.moveTo(
                cx + radius * mathCos(startAngle),
                cy + radius * mathSin(startAngle)
            )
            _ = ctx.arc(cx, cy, radius, startAngle, endAngle, !clockwise)

            if innerRadius > e {
                _ = ctx.moveTo(
                    cx + innerRadius * mathCos(endAngle),
                    cy + innerRadius * mathSin(endAngle)
                )
                _ = ctx.arc(cx, cy, innerRadius, endAngle, startAngle, clockwise)
            }
        }
        // is a circular or annular sector
        else {
            // upstream leaves these `undefined`; we seed with NaN so JS Math.min/max NaN
            //   propagation (see header NaN-PROPAGATION NOTE) reproduces the corner-skip behavior.
            var icrStart = Double.nan
            var icrEnd = Double.nan
            var ocrStart = Double.nan
            var ocrEnd = Double.nan

            var ocrs = Double.nan
            var ocre = Double.nan
            var icrs = Double.nan
            var icre = Double.nan

            var ocrMax = Double.nan
            var icrMax = Double.nan
            var limitedOcrMax = Double.nan
            var limitedIcrMax = Double.nan

            var xre = Double.nan
            var yre = Double.nan
            var xirs = Double.nan
            var yirs = Double.nan

            let xrs = radius * mathCos(startAngle)
            let yrs = radius * mathSin(startAngle)
            let xire = innerRadius * mathCos(endAngle)
            let yire = innerRadius * mathSin(endAngle)

            let hasArc = arc > e
            if hasArc {
                let cornerRadius = shape.cornerRadius
                if cornerRadius.zrTruthy {
                    let nrm = normalizeCornerRadius(cornerRadius)
                    // upstream destructures [icrStart, icrEnd, ocrStart, ocrEnd]; missing elements
                    //   (e.g. empty-array case) stay `undefined` → NaN.
                    icrStart = nrm.count > 0 ? nrm[0] : Double.nan
                    icrEnd = nrm.count > 1 ? nrm[1] : Double.nan
                    ocrStart = nrm.count > 2 ? nrm[2] : Double.nan
                    ocrEnd = nrm.count > 3 ? nrm[3] : Double.nan
                }

                let halfRd = mathAbs(radius - innerRadius) / 2
                ocrs = mathMin(halfRd, ocrStart)
                ocre = mathMin(halfRd, ocrEnd)
                icrs = mathMin(halfRd, icrStart)
                icre = mathMin(halfRd, icrEnd)

                limitedOcrMax = mathMax(ocrs, ocre)
                ocrMax = limitedOcrMax
                limitedIcrMax = mathMax(icrs, icre)
                icrMax = limitedIcrMax

                // draw corner radius
                if ocrMax > e || icrMax > e {
                    xre = radius * mathCos(endAngle)
                    yre = radius * mathSin(endAngle)
                    xirs = innerRadius * mathCos(startAngle)
                    yirs = innerRadius * mathSin(startAngle)

                    // restrict the max value of corner radius
                    if arc < PI {
                        let it = intersect(xrs, yrs, xirs, yirs, xre, yre, xire, yire)
                        if let it = it {
                            let x0 = xrs - it[0]
                            let y0 = yrs - it[1]
                            let x1 = xre - it[0]
                            let y1 = yre - it[1]
                            let a = 1 / mathSin(
                                mathACos((x0 * x1 + y0 * y1) / (mathSqrt(x0 * x0 + y0 * y0) * mathSqrt(x1 * x1 + y1 * y1))) / 2
                            )
                            let b = mathSqrt(it[0] * it[0] + it[1] * it[1])
                            limitedOcrMax = mathMin(ocrMax, (radius - b) / (a + 1))
                            limitedIcrMax = mathMin(icrMax, (innerRadius - b) / (a - 1))
                        }
                    }
                }
            }

            // the sector is collapsed to a line
            if !hasArc {
                _ = ctx.moveTo(cx + xrs, cy + yrs)
            }
            // the outer ring has corners
            else if limitedOcrMax > e {
                let crStart = mathMin(ocrStart, limitedOcrMax)
                let crEnd = mathMin(ocrEnd, limitedOcrMax)
                let ct0 = computeCornerTangents(xirs, yirs, xrs, yrs, radius, crStart, clockwise)
                let ct1 = computeCornerTangents(xre, yre, xire, yire, radius, crEnd, clockwise)

                _ = ctx.moveTo(cx + ct0.cx + ct0.x0, cy + ct0.cy + ct0.y0)

                // Have the corners merged?
                if limitedOcrMax < ocrMax && crStart == crEnd {
                    _ = ctx.arc(cx + ct0.cx, cy + ct0.cy, limitedOcrMax, mathATan2(ct0.y0, ct0.x0), mathATan2(ct1.y0, ct1.x0), !clockwise)
                }
                else {
                    // draw the two corners and the ring
                    if crStart > 0 {
                        _ = ctx.arc(cx + ct0.cx, cy + ct0.cy, crStart, mathATan2(ct0.y0, ct0.x0), mathATan2(ct0.y1, ct0.x1), !clockwise)
                    }
                    _ = ctx.arc(cx, cy, radius, mathATan2(ct0.cy + ct0.y1, ct0.cx + ct0.x1), mathATan2(ct1.cy + ct1.y1, ct1.cx + ct1.x1), !clockwise)
                    if crEnd > 0 {
                        _ = ctx.arc(cx + ct1.cx, cy + ct1.cy, crEnd, mathATan2(ct1.y1, ct1.x1), mathATan2(ct1.y0, ct1.x0), !clockwise)
                    }
                }
            }
            // the outer ring is a circular arc
            else {
                _ = ctx.moveTo(cx + xrs, cy + yrs)
                _ = ctx.arc(cx, cy, radius, startAngle, endAngle, !clockwise)
            }

            // no inner ring, is a circular sector
            if !(innerRadius > e) || !hasArc {
                _ = ctx.lineTo(cx + xire, cy + yire)
            }
            // the inner ring has corners
            else if limitedIcrMax > e {
                let crStart = mathMin(icrStart, limitedIcrMax)
                let crEnd = mathMin(icrEnd, limitedIcrMax)
                let ct0 = computeCornerTangents(xire, yire, xre, yre, innerRadius, -crEnd, clockwise)
                let ct1 = computeCornerTangents(xrs, yrs, xirs, yirs, innerRadius, -crStart, clockwise)
                _ = ctx.lineTo(cx + ct0.cx + ct0.x0, cy + ct0.cy + ct0.y0)

                // Have the corners merged?
                if limitedIcrMax < icrMax && crStart == crEnd {
                    _ = ctx.arc(cx + ct0.cx, cy + ct0.cy, limitedIcrMax, mathATan2(ct0.y0, ct0.x0), mathATan2(ct1.y0, ct1.x0), !clockwise)
                }
                // draw the two corners and the ring
                else {
                    if crEnd > 0 {
                        _ = ctx.arc(cx + ct0.cx, cy + ct0.cy, crEnd, mathATan2(ct0.y0, ct0.x0), mathATan2(ct0.y1, ct0.x1), !clockwise)
                    }
                    _ = ctx.arc(cx, cy, innerRadius, mathATan2(ct0.cy + ct0.y1, ct0.cx + ct0.x1), mathATan2(ct1.cy + ct1.y1, ct1.cx + ct1.x1), clockwise)
                    if crStart > 0 {
                        _ = ctx.arc(cx + ct1.cx, cy + ct1.cy, crStart, mathATan2(ct1.y1, ct1.x1), mathATan2(ct1.y0, ct1.x0), !clockwise)
                    }
                }
            }
            // the inner ring is just a circular arc
            else {
                // FIXME: if no lineTo, svg renderer will perform an abnormal drawing behavior.
                _ = ctx.lineTo(cx + xire, cy + yire)

                _ = ctx.arc(cx, cy, innerRadius, endAngle, startAngle, clockwise)
            }
        }

        _ = ctx.closePath()
    }
}
