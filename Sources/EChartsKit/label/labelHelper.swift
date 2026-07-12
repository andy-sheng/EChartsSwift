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

    /// upstream: `getDefaultInterpolatedLabel(data, interpolatedValue)` — the "in-flight" label text
    ///   during the number roll-up animation (`animateLabelValue`'s `during` callback passes it as
    ///   `defaultInterpolatedText`). Ported straight from upstream; deps are all present
    ///   (`data.mapDimensionsAll`, `data.getDimensionIndex`, `util.isArray`).
    public static func getDefaultInterpolatedLabel(
        _ data: SeriesData,
        _ interpolatedValue: InterpolatableValue
    ) -> String {
        // const labelDims = data.mapDimensionsAll('defaultedLabel');
        let labelDims = data.mapDimensionsAll("defaultedLabel")
        // if (!isArray(interpolatedValue)) { return interpolatedValue + ''; }
        if !util.isArray(interpolatedValue) {
            return format._str(interpolatedValue)
        }
        let arr = (interpolatedValue as? [Any?]) ?? []
        // for (i of labelDims) { const dimIndex = data.getDimensionIndex(labelDims[i]);
        //   if (dimIndex >= 0) { vals.push(interpolatedValue[dimIndex]); } }
        var vals: [Any?] = []
        for i in 0..<labelDims.count {
            let dimIndex = data.getDimensionIndex(labelDims[i])
            if dimIndex >= 0 {
                let idx = Int(dimIndex)
                if idx < arr.count { vals.append(arr[idx]) }
            }
        }
        // return vals.join(' ');  (Array#join coerces null/undefined entries to '', see getDefaultLabel)
        return vals.map { format._strOrNil($0) ?? "" }.joined(separator: " ")
    }
}
