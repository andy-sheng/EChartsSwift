// Ported from echarts/src/util/graphic.ts — keep in sync with upstream
// (Partial: only `expandOrShrinkRect` / `expandRectOnOneDimension` are landed here so far; the rest of
//  util/graphic.ts — createIcon/setTooltipConfig/getTransformedTouches etc. — is PORT-TODO.)

import Foundation
import ZRenderKit

// upstream: export function expandOrShrinkRect<TRect extends RectLike>(rect, delta, shrinkOrExpand, noNegative, minSize?)
//   Grows (or shrinks, when `shrinkOrExpand`) `rect` on each side. `delta` is a scalar (applied to all four
//   sides) or a `[top, right, bottom, left]` array; `noNegative` clamps the deltas to >= 0. `minSize`
//   ([w, h], default [0, 0]) is the floor each dimension collapses to. Mutates `rect` IN PLACE — matching the
//   JS (BoundingRect is a reference type). Returns the same rect for chaining.
@discardableResult
public func expandOrShrinkRect(
    _ rect: RectLike,
    _ delta: Any?,
    _ shrinkOrExpand: Bool,
    _ noNegative: Bool,
    _ minSize: [Double]? = nil
) -> RectLike {
    // if (delta == null) { return rect; }
    guard let delta = delta else { return rect }
    var d: [Double]
    if let n = delta as? Double {
        d = [n, n, n, n]
    }
    else if let i = delta as? Int {
        let n = Double(i); d = [n, n, n, n]
    }
    else if let arr = delta as? [Double], arr.count == 4 {
        d = arr
    }
    else if let arr = delta as? [Any], arr.count == 4 {
        d = arr.map { ($0 as? Double) ?? Double(($0 as? Int) ?? 0) }
    }
    else {
        return rect
    }
    // if (noNegative) { each delta = max(0, delta) }
    if noNegative {
        for k in 0..<4 { d[k] = Swift.max(0, d[k]) }
    }
    // if (shrinkOrExpand) { negate each delta }
    if shrinkOrExpand {
        for k in 0..<4 { d[k] = -d[k] }
    }
    // expandRectOnOneDimension(rect, delta, 'x', 'width', 3, 1, minSize?[0] || 0);
    expandRectOnOneDimension(rect, d, true, 3, 1, (minSize.flatMap { $0.count > 0 ? $0[0] : nil }) ?? 0)
    // expandRectOnOneDimension(rect, delta, 'y', 'height', 0, 2, minSize?[1] || 0);
    expandRectOnOneDimension(rect, d, false, 0, 2, (minSize.flatMap { $0.count > 1 ? $0[1] : nil }) ?? 0)
    return rect
}

// upstream: function expandRectOnOneDimension(rect, delta, xy, wh, ltIdx, rbIdx, minSize)
//   `isX` selects the x/width pair (true) vs y/height (false). `ltIdx`/`rbIdx` index the left-top /
//   right-bottom delta for that dimension.
private func expandRectOnOneDimension(
    _ rect: RectLike, _ delta: [Double], _ isX: Bool, _ ltIdx: Int, _ rbIdx: Int, _ minSizeIn: Double
) {
    let deltaSum = delta[rbIdx] + delta[ltIdx]
    let oldSize = isX ? rect.width : rect.height
    var newSize = oldSize + deltaSum
    // minSize = max(0, min(minSize, oldSize));
    let minSize = Swift.max(0, Swift.min(minSizeIn, oldSize))
    if newSize < minSize {
        newSize = minSize
        // Try to make the position of the zero rect reasonable in most visual cases.
        let shift: Double =
            delta[ltIdx] >= 0 ? -delta[ltIdx]
            : delta[rbIdx] >= 0 ? oldSize + delta[rbIdx]
            : Swift.abs(deltaSum) > 1e-8 ? (oldSize - minSize) * delta[ltIdx] / deltaSum
            : 0
        if isX { rect.x += shift } else { rect.y += shift }
    }
    else {
        if isX { rect.x -= delta[ltIdx] } else { rect.y -= delta[ltIdx] }
    }
    if isX { rect.width = newSize } else { rect.height = newSize }
}
