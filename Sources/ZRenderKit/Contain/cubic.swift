// Ported from zrender/src/contain/cubic.ts — keep in sync with upstream

// import * as curve from '../core/curve';

public enum cubic {

    /**
     * 三次贝塞尔曲线描边包含判断
     */
    public static func containStroke(
        _ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double,
        _ x2: Double, _ y2: Double, _ x3: Double, _ y3: Double,
        _ lineWidth: Double, _ x: Double, _ y: Double
    ) -> Bool {
        if lineWidth == 0 {
            return false
        }
        let _l = lineWidth
        // Quick reject
        if
            (y > y0 + _l && y > y1 + _l && y > y2 + _l && y > y3 + _l)
            || (y < y0 - _l && y < y1 - _l && y < y2 - _l && y < y3 - _l)
            || (x > x0 + _l && x > x1 + _l && x > x2 + _l && x > x3 + _l)
            || (x < x0 - _l && x < x1 - _l && x < x2 - _l && x < x3 - _l)
        {
            return false
        }
        // Upstream passes `null` for out and uses the returned distance; Swift
        // curve.cubicProjectPoint returns (out, distance) per CONVENTIONS §3.
        let d = curve.cubicProjectPoint(
            x0, y0, x1, y1, x2, y2, x3, y3,
            x, y
        ).distance
        return d <= _l / 2
    }
}
