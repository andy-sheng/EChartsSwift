// Ported from echarts/src/chart/boxplot/boxplotTransform.ts — keep in sync with upstream.
//
// The built-in `echarts:boxplot` dataset transform: reduces a raw `number[][]` (one row of samples per
// box) into (1) the five-number box rows [ItemName, Low, Q1, Q2, Q3, High] and (2) the outlier points.
// Registered under the `echarts:` namespace, so a page references it as `transform: { type: 'boxplot' }`
// (registerExternalTransform strips the official `echarts:` namespace — see transform.swift). Uses the
// already-ported `prepareBoxplotData`.
import Foundation

private func boxplotToDouble(_ v: Any?) -> Double? {
    switch v {
    case let d as Double: return d
    case let i as Int: return Double(i)
    case let n as NSNumber: return n.doubleValue
    case let s as String: return Double(s)
    default: return nil
    }
}

// upstream: export const boxplotTransform: ExternalDataTransform<BoxplotTransformOption>
let boxplotTransform = ExternalDataTransform(
    type: "echarts:boxplot",
    transform: { params in
        // upstream throws if sourceFormat !== SOURCE_FORMAT_ARRAY_ROWS; the built-in getRawData below
        //   yields array-rows for a raw dataset, so read + coerce it to number[][].
        let rawAny = try? params.upstream.getRawData()
        let rawRows = (rawAny as? [[Any]]) ?? (rawAny as? [Any])?.compactMap { $0 as? [Any] } ?? []
        let raw: [[Double]] = rawRows.map { row in row.compactMap { boxplotToDouble($0) } }

        var opt = PrepareBoxplotDataOpt()
        if let cfg = params.config as? [String: Any] {
            // boundIQR: number | 'none'
            if let s = cfg["boundIQR"] as? String { opt.boundIQR = s }
            else if let n = boxplotToDouble(cfg["boundIQR"]) { opt.boundIQR = n }
            // itemNameFormatter: string form is portable (the JS-closure form is dropped upstream-side).
            if let s = cfg["itemNameFormatter"] as? String { opt.itemNameFormatter = s }
        }

        let result = prepareBoxplotData(raw, opt)
        // upstream returns TWO result items: the boxes (with named dims) + the outliers.
        return [
            ExternalDataTransformResultItem(
                data: result.boxData,
                dimensions: ["ItemName", "Low", "Q1", "Q2", "Q3", "High"]),
            ExternalDataTransformResultItem(data: result.outliers)
        ]
    }
)
