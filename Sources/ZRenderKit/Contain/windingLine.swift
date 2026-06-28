// Ported from zrender/src/contain/windingLine.ts — keep in sync with upstream

import Foundation

// upstream: `export default function windingLine(...)`
public enum windingLine {

    public static func windingLine(
        _ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ x: Double, _ y: Double
    ) -> Double {
        if (y > y0 && y > y1) || (y < y0 && y < y1) {
            return 0
        }
        // Ignore horizontal line
        if y1 == y0 {
            return 0
        }
        let t = (y - y0) / (y1 - y0)

        var dir: Double = y1 < y0 ? 1 : -1
        // Avoid winding error when intersection point is the connect point of two line of polygon
        if t == 1 || t == 0 {
            dir = y1 < y0 ? 0.5 : -0.5
        }

        let x_ = t * (x1 - x0) + x0

        // If (x, y) on the line, considered as "contain".
        return x_ == x ? Double.infinity : x_ > x ? dir : 0
    }
}
