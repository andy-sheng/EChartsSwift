// Ported from zrender/src/graphic/helper/roundRect.ts — keep in sync with upstream

// upstream: import PathProxy from '../../core/PathProxy';

// upstream marker: free-function module → caseless `enum` namespace (CONVENTIONS §2).
//   upstream import alias: `roundRectHelper`.
public enum roundRect {

    // upstream: export function buildPath(ctx, shape: { x, y, width, height, r? })
    //   The CanvasRenderingContext2D branch is handled by the native backend (CONVENTIONS §9);
    //   we emit into the `PathProxy`. `shape` is the `RectShape` (defined in Rect.swift), which
    //   carries the exact `{ x, y, width, height, r? }` fields the upstream anonymous type needs.
    public static func buildPath(_ ctx: PathProxy, _ shape: RectShape) {
        var x = shape.x
        var y = shape.y
        var width = shape.width
        var height = shape.height
        let r = shape.r
        var r1: Double
        var r2: Double
        var r3: Double
        var r4: Double

        // Convert width and height to positive for better borderRadius
        if width < 0 {
            x = x + width
            width = -width
        }
        if height < 0 {
            y = y + height
            height = -height
        }

        // upstream: typeof r === 'number' / r instanceof Array
        switch r {
        case .some(.number(let rn)):
            r1 = rn; r2 = rn; r3 = rn; r4 = rn
        case .some(.array(let ra)):
            if ra.count == 1 {
                r1 = ra[0]; r2 = ra[0]; r3 = ra[0]; r4 = ra[0]
            }
            else if ra.count == 2 {
                r1 = ra[0]; r3 = ra[0]
                r2 = ra[1]; r4 = ra[1]
            }
            else if ra.count == 3 {
                r1 = ra[0]
                r2 = ra[1]; r4 = ra[1]
                r3 = ra[2]
            }
            else {
                r1 = ra[0]
                r2 = ra[1]
                r3 = ra[2]
                r4 = ra[3]
            }
        case .none:
            r1 = 0; r2 = 0; r3 = 0; r4 = 0
        }

        var total: Double
        if r1 + r2 > width {
            total = r1 + r2
            r1 *= width / total
            r2 *= width / total
        }
        if r3 + r4 > width {
            total = r3 + r4
            r3 *= width / total
            r4 *= width / total
        }
        if r2 + r3 > height {
            total = r2 + r3
            r2 *= height / total
            r3 *= height / total
        }
        if r1 + r4 > height {
            total = r1 + r4
            r1 *= height / total
            r4 *= height / total
        }
        _ = ctx.moveTo(x + r1, y)
        _ = ctx.lineTo(x + width - r2, y)
        if r2 != 0 { _ = ctx.arc(x + width - r2, y + r2, r2, -Double.pi / 2, 0) }
        _ = ctx.lineTo(x + width, y + height - r3)
        if r3 != 0 { _ = ctx.arc(x + width - r3, y + height - r3, r3, 0, Double.pi / 2) }
        _ = ctx.lineTo(x + r4, y + height)
        if r4 != 0 { _ = ctx.arc(x + r4, y + height - r4, r4, Double.pi / 2, Double.pi) }
        _ = ctx.lineTo(x, y + r1)
        if r1 != 0 { _ = ctx.arc(x + r1, y + r1, r1, Double.pi, Double.pi * 1.5) }
        _ = ctx.closePath()
    }
}
