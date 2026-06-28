// Ported from zrender/src/contain/line.ts — keep in sync with upstream

import Foundation

public enum line {

    /**
     * 线段包含判断
     * @param  {number}  x0
     * @param  {number}  y0
     * @param  {number}  x1
     * @param  {number}  y1
     * @param  {number}  lineWidth
     * @param  {number}  x
     * @param  {number}  y
     * @return {boolean}
     */
    public static func containStroke(
        _ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double,
        _ lineWidth: Double, _ x: Double, _ y: Double
    ) -> Bool {
        if lineWidth == 0 {
            return false
        }
        let _l = lineWidth
        var _a: Double = 0
        var _b = x0
        // Quick reject
        if
            (y > y0 + _l && y > y1 + _l)
            || (y < y0 - _l && y < y1 - _l)
            || (x > x0 + _l && x > x1 + _l)
            || (x < x0 - _l && x < x1 - _l)
        {
            return false
        }

        if x0 != x1 {
            _a = (y0 - y1) / (x0 - x1)
            _b = (x0 * y1 - x1 * y0) / (x0 - x1)
        }
        else {
            return Swift.abs(x - x0) <= _l / 2
        }
        let tmp = _a * x - y + _b
        let _s = tmp * tmp / (_a * _a + 1)
        return _s <= _l / 2 * _l / 2
    }
}
