// Ported from echarts/src/chart/helper/labelHelper.ts — keep in sync with upstream
//
// upstream imports (resolved to the ported modules):
//   import {retrieveRawValue} from '../../data/helper/dataProvider';   -> EChartsKit.retrieveRawValue
//   import SeriesData from '../../data/SeriesData';                    -> EChartsKit.SeriesData
//   import { InterpolatableValue } from '../../util/types';            -> EChartsKit.InterpolatableValue
//   import { isArray } from 'zrender/src/core/util';                   -> ZRenderKit.util.isArray

import Foundation
import ZRenderKit

// upstream: free-function module -> caseless enum namespace named after the file (CONVENTIONS §2),
//   matching the sibling `labelStyle` enum. Call sites read `labelHelper.getDefaultLabel(...)`.
public enum labelHelper {

    /// @return label string. Not null/undefined (upstream's own doc comment — though the TS
    ///   implementation can in fact fall off the end returning `undefined` when `len == 0`; ported
    ///   faithfully as `String?` here rather than force a non-optional contract the source doesn't
    ///   actually uphold).
    public static func getDefaultLabel(_ data: SeriesData, _ dataIndex: Double) -> String? {
        let labelDims = data.mapDimensionsAll("defaultedLabel")
        let len = labelDims.count

        // Simple optimization (in lots of cases, label dims length is 1).
        if len == 1 {
            let rawVal = retrieveRawValue(data, dataIndex, labelDims[0])
            // upstream `rawVal != null ? rawVal + '' : null` — `+ ''` is JS's generic
            //   number/string/bool -> string coercion; `format._str/_strOrNil` already reproduces
            //   that exact coercion (see its own PORT header) so it's reused rather than re-derived.
            return rawVal != nil ? format._strOrNil(rawVal) : nil
        }
        else if len > 0 {
            var vals: [String] = []
            for i in 0..<labelDims.count {
                let v = retrieveRawValue(data, dataIndex, labelDims[i])
                // upstream `vals.push(retrieveRawValue(...))` then `vals.join(' ')` — Array#join
                //   coerces `null`/`undefined` entries to `''` (NOT the string `'undefined'`, unlike
                //   `String(x)`), so nil maps to `""` here, not `format._str`'s `"undefined"`.
                vals.append(format._strOrNil(v) ?? "")
            }
            return vals.joined(separator: " ")
        }
        // upstream: falls off the end of the function (implicit `undefined`) when `len == 0`.
        return nil
    }

    // PORT-TODO (DEFERRED — no caller yet, NOT because the animation is unported):
    //   `getDefaultInterpolatedLabel(data, interpolatedValue)` computes the "in-flight" label text
    //   during the number roll-up animation (`animateLabelValue`'s `during` callback passes it as
    //   `defaultInterpolatedText`). `setLabelValueAnimation`/`animateLabelValue` ARE now ported
    //   (-> label/labelStyle.swift `setLabelValueAnimation` / `animateLabelValue`), but no view yet
    //   WIRES `setLabelValueAnimation` (e.g. BarView still marks it DEFERRED), so this helper has no
    //   caller and is left unported until a view supplies the `getDefaultText` closure that would call
    //   it. Deps are present (`data.mapDimensionsAll`, `data.getDimensionIndex`, `util.isArray`).
    //   Upstream body for reference:
    //     const labelDims = data.mapDimensionsAll('defaultedLabel');
    //     if (!isArray(interpolatedValue)) { return interpolatedValue + ''; }
    //     const vals = [];
    //     for (dim of labelDims) { const i = data.getDimensionIndex(dim); if (i >= 0) vals.push(interpolatedValue[i]); }
    //     return vals.join(' ');
}
