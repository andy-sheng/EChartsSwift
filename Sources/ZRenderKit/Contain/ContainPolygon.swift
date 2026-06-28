// Ported from zrender/src/contain/polygon.ts — keep in sync with upstream

import Foundation

// import windingLine from './windingLine';
// import { VectorArray } from '../core/vector';

public enum polygon {

    private static let EPSILON = 1e-8

    private static func isAroundEqual(_ a: Double, _ b: Double) -> Bool {
        return Swift.abs(a - b) < EPSILON
    }

    public static func contain(_ points: [VectorArray], _ x: Double, _ y: Double) -> Bool {
        var w: Double = 0
        // upstream: `let p = points[0]; if (!p) { return false; }`
        guard var p = points.first else {
            return false
        }

        var i = 1
        while i < points.count {
            let p2 = points[i]
            w += windingLine.windingLine(p[0], p[1], p2[0], p2[1], x, y)
            p = p2
            i += 1
        }

        // Close polygon
        let p0 = points[0]
        if !isAroundEqual(p[0], p0[0]) || !isAroundEqual(p[1], p0[1]) {
            w += windingLine.windingLine(p[0], p[1], p0[0], p0[1], x, y)
        }

        return w != 0
    }
}
