// Ported from echarts/src/coord/axisBand.ts — keep in sync with upstream

import Foundation
import ZRenderKit

// import { assert, each } from 'zrender/src/core/util';           -> `util.assert` / `util.each` (ZRenderKit)
// import { NullUndefined } from '../util/types';                  -> NullUndefined -> nil (CONVENTIONS §6)
// import type Axis from './Axis';                                 -> `open class Axis` (coord/Axis.swift)
// import { isOrdinalScale } from '../scale/helper';               -> helper.isOrdinalScale (scale/helper.swift)
// import { isNullableNumberFinite, mathAbs, mathMax } from '../util/number';
//   -> number.isNullableNumberFinite / number.mathAbs / number.mathMax (util/number.swift)
// import {
//     AxisStatKey, getAxisStat, getAxisStatBySeries,
//     LINEAR_POSITIVE_MIN_GAP_SINGLE_VALID_VALUE,
// } from './axisStatistics';                                      -> top-level free funcs/types (coord/axisStatistics.swift)
// import { getScaleLinearSpanForMapping } from '../scale/scaleMapper';
//   -> getScaleLinearSpanForMapping (scale/scaleMapper.swift; top-level free func)
// import type SeriesModel from '../model/Series';                 -> SeriesModel (model/Series.swift)


// Arbitrary, leave some space to avoid overflowing when dataZoom moving.
private let FALLBACK_BAND_WIDTH_RATIO: Double = 0.8

public struct AxisBandWidthResult {
    // bandWidth in pixel.
    // Never be null/undefined.
    // May be NaN if no meaningfull value. But it's unlikely to be NaN, since edge cases
    // are handled internally whenever possible.
    public var w: Double
    // bandWidth in data space.
    // Never be null/undefined.
    // May be NaN if no meaningfull value, typically when no valid series data item.
    public var w2: Double

    public init(w: Double, w2: Double) {
        self.w = w
        self.w2 = w2
    }
}

public struct CalculateBandWidthOpt {
    // Only used on non-'category' axes. Calculate `bandWidth` based on statistics.
    // Require `requireAxisStatistics` to be called.
    public struct FromStat {
        // Either `key` or `sers` is required.
        //  - `key`: Calculate `bandWidth` based on a series collection defined by the `AxisStatKey`.
        public var key: AxisStatKey?
        //  - `sers`: Query all keys by the given series collection and union the corresponding bandWidth.
        //    PENDING: If multiple axis statistics can be queried by `series`, currently we only support
        //    to return a maximum `bandWidth`, which is suitable for cases like "axis pointer shadow".
        public var sers: [SeriesModel?]?

        public init(key: AxisStatKey? = nil, sers: [SeriesModel?]? = nil) {
            self.key = key
            self.sers = sers
        }
    }
    public var fromStat: FromStat?
    // It also act as a fallback for NaN/null/undefined result.
    public var min: Double?

    public init(fromStat: FromStat? = nil, min: Double? = nil) {
        self.fromStat = fromStat
        self.min = min
    }
}

/**
 * NOTICE:
 *  - Require the axis pixel extent and the scale extent as inputs. But they
 *    can be not precise for approximation.
 *  - Can only be called after "data processing" stage.
 *
 * PENDING:
 *  Currently `bandWidth` can not be specified by users explicitly. But if we
 *  allow that in future, these issues must be considered:
 *    - Can only allow specifying a band width in data scale rather than pixel.
 *    - LogScale needs to be considered - band width can only be specified on linear
 *      (but before break) scale, similar to `axis.interval`.
 *
 * A band is required on:
 *  - series group band width in bar/boxplot/candlestick/...;
 *  - tooltip axisPointer type "shadow";
 *  - etc.
 */
public func calcBandWidth(
    _ axis: Axis,
    _ opt: CalculateBandWidthOpt? = nil
) -> AxisBandWidthResult {
    let opt = opt ?? CalculateBandWidthOpt()
    var out = AxisBandWidthResult(w: Double.nan, w2: Double.nan)
    let scale = axis.scale
    let fromStat = opt.fromStat
    let min = opt.min

    // [BAND_WIDTH_USED_SCALE_LINEAR_SPAN]
    //  - Band width should always respect to the currently specified extent, and `SCALE_EXTENT_KIND_MAPPING`
    //    should be used if specified.
    //    Otherwise, the result may incorrect, especially when data count is small.
    //    For example, when "containShape" is calculating, no `SCALE_EXTENT_KIND_MAPPING` is set, so here only
    //    `SCALE_EXTENT_KIND_EFFECTIVE` is returned, say, `[3, 5]`, based on which a `SCALE_EXTENT_KIND_MAPPING`
    //    is calculated, say `[2.5, 5.5]` (expanded by `0.5`). Then when rendering, that `SCALE_EXTENT_KIND_MAPPING`
    //    is returned here.
    //    See AXIS_CONTAIN_SHAPE_COMMON_STRATEGY for more details.
    //  - The span should be in the linear space (typically, the innermost space).
    //  - We use the scale extent after being zoommed and `intervalScaleEnsureValidExtent`-ish applied and
    //    "nice"/"align" applied, because:
    //    - For OrdinalScale, fine;
    //    - For numeric scale, `scaleLinearSpan` is normally not used for a consistent result when `dataZoom`
    //      is applied, but used when none or single data item case.
    var scaleLinearSpan = getScaleLinearSpanForMapping(scale)
    if !number.isNullableNumberFinite(scaleLinearSpan) { // scale may be `[Infinity, -Infinity]`.
        scaleLinearSpan = Double.nan
    }
    let axisExtent = axis.getExtent()
    // Always use a new pxSpan because it may be changed in `grid` contain label calculation.
    let pxSpan = number.mathAbs(axisExtent[1] - axisExtent[0])

    if helper.isOrdinalScale(scale) {
        calcBandWidthForCategoryAxis(&out, axis, scaleLinearSpan, pxSpan)
    }
    else if let fromStat = fromStat {
        calcBandWidthForNumericAxis(&out, axis, scaleLinearSpan, pxSpan, fromStat)
    }
    else if min == nil {
        if __DEV__ {
            util.assert(false)
        }
    }

    if let min = min {
        out.w = number.isNullableNumberFinite(out.w)
            ? number.mathMax(min, out.w) : min
    }

    return out
}

private func calcBandWidthForCategoryAxis(
    _ out: inout AxisBandWidthResult,
    _ axis: Axis,
    _ scaleLinearSpan: Double,
    _ pxSpan: Double
) {
    let onBand = axis.onBand

    var len = scaleLinearSpan + (onBand ? 1 : 0)
    // Fix #2728, avoid NaN when only one data.
    if len == 0 { len = 1 }

    out.w = pxSpan / len
    // NOTE:
    //  - When `scaleLinearSpan === 0`, no need to expand extent.
    //  - `onBand: true` (`boundaryGap: true`) does not need to support `containShape`,
    //    thereby no `invRatio`.
    // `scaleLinearSpan`/`pxSpan` used as JS truthy (`0` and `NaN` are falsy) — replicated explicitly.
    if !onBand
        && (scaleLinearSpan != 0 && !scaleLinearSpan.isNaN)
        && (pxSpan != 0 && !pxSpan.isNaN) {
        out.w2 = out.w * scaleLinearSpan / pxSpan
    }
}

private func calcBandWidthForNumericAxis(
    _ out: inout AxisBandWidthResult,
    _ axis: Axis,
    _ scaleLinearSpan: Double,
    _ pxSpan: Double,
    _ fromStat: CalculateBandWidthOpt.FromStat
) {

    if __DEV__ {
        util.assert(true) // upstream: assert(fromStat) — `fromStat` is a non-optional param in this port
    }

    var onlySingular = false
    var bandWidthInData = -Double.infinity
    util.each(
        fromStat.key != nil
            ? [getAxisStat(axis, fromStat.key!)]
            : getAxisStatBySeries(axis, fromStat.sers ?? []),
        { stat, _ in
            let liPosMinGap = stat.liPosMinGap
            // NOTE: `liPosMinGap == null` may indicate that `requireAxisStatistics`
            // is not used by any series on this axis. We should not make `bandWidth`
            // for this case.
            if liPosMinGap != nil {
                if liPosMinGap! > 0 {
                    if liPosMinGap! > bandWidthInData {
                        bandWidthInData = liPosMinGap!
                    }
                    onlySingular = false
                }
                else if liPosMinGap! == LINEAR_POSITIVE_MIN_GAP_SINGLE_VALID_VALUE {
                    onlySingular = true
                }
            }
        }
    )

    if number.isNullableNumberFinite(scaleLinearSpan) && scaleLinearSpan > 0
        && number.isNullableNumberFinite(bandWidthInData)
    {
        out.w = pxSpan / scaleLinearSpan * bandWidthInData
        out.w2 = bandWidthInData
    }
    else if onlySingular {
        // This is the special handing for single value case, where min gap can not
        // be calculated, but `w` and `w2` (for "containShape") are still needed.
        out.w = pxSpan * FALLBACK_BAND_WIDTH_RATIO
        out.w2 = out.w * scaleLinearSpan / pxSpan
        // Consider an axis has both candlestick and bar series, where candlestick has multiple data
        // but the bar series has no data. In this case, that bar series should be ignored; otherwise,
        // the axis will be significantly expanded by "containShape" but no bar shape displayed.
    }
}
