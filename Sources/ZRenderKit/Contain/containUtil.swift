// Ported from zrender/src/contain/util.ts — keep in sync with upstream

import Foundation

private let PI2 = Double.pi * 2

// upstream module name is `util` (contain/util.ts); renamed to
// `containUtil` to avoid a Swift namespace collision with core/util.ts (`enum util`).
public enum containUtil {

    public static func normalizeRadian(_ angle: Double) -> Double {
        var angle = angle
        angle = angle.truncatingRemainder(dividingBy: PI2)
        if angle < 0 {
            angle += PI2
        }
        return angle
    }
}
