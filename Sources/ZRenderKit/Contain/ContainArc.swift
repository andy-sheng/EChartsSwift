// Ported from zrender/src/contain/arc.ts — keep in sync with upstream

import Foundation

// import {normalizeRadian} from './util';  → containUtil.normalizeRadian (see util.swift)

public enum arc {

    private static let PI2 = Double.pi * 2

    /**
     * 圆弧描边包含判断
     */
    public static func containStroke(
        _ cx: Double, _ cy: Double, _ r: Double, _ startAngle: Double, _ endAngle: Double,
        _ anticlockwise: Bool,
        _ lineWidth: Double, _ x: Double, _ y: Double
    ) -> Bool {

        var startAngle = startAngle
        var endAngle = endAngle
        var x = x
        var y = y

        if lineWidth == 0 {
            return false
        }
        let _l = lineWidth

        x -= cx
        y -= cy
        let d = sqrt(x * x + y * y)

        if (d - _l > r) || (d + _l < r) {
            return false
        }
        // TODO
        if (Swift.abs(startAngle - endAngle)).truncatingRemainder(dividingBy: PI2) < 1e-4 {
            // Is a circle
            return true
        }
        if anticlockwise {
            let tmp = startAngle
            startAngle = containUtil.normalizeRadian(endAngle)
            endAngle = containUtil.normalizeRadian(tmp)
        }
        else {
            startAngle = containUtil.normalizeRadian(startAngle)
            endAngle = containUtil.normalizeRadian(endAngle)
        }
        if startAngle > endAngle {
            endAngle += PI2
        }

        var angle = atan2(y, x)
        if angle < 0 {
            angle += PI2
        }
        return (angle >= startAngle && angle <= endAngle)
            || (angle + PI2 >= startAngle && angle + PI2 <= endAngle)
    }
}
