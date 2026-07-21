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

// upstream:
//   export interface BoxplotTransformOption extends DataTransformOption {
//       type: 'boxplot';
//       config: PrepareBoxplotDataOpt;
//   }
// PORT: kept as a Swift struct for the typed/programmatic path; at runtime `params.config` flows from the
//   dynamic option bag (CONVENTIONS §2) and is consumed as `PrepareBoxplotDataOpt` (or its dictionary form).
public struct BoxplotTransformOption {
    public var type: String = "boxplot"
    public var config: PrepareBoxplotDataOpt

    public init(config: PrepareBoxplotDataOpt) {
        self.config = config
    }
}

// upstream: export const boxplotTransform: ExternalDataTransform<BoxplotTransformOption>
public let boxplotTransform: ExternalDataTransform = ExternalDataTransform(
    type: "echarts:boxplot",
    transform: { params in
        let upstream = params.upstream

        // PORT-NOTE: this throw is propagated by applySingleDataTransform -> applyDataTransform up to
        //   sourceManager.swift, whose catch calls `doThrow(...)` (fatalError) — upstream a bad option
        //   only rejects that chart with a JS Error. Same convention as the sibling built-in transforms.
        if upstream.sourceFormat != SOURCE_FORMAT_ARRAY_ROWS {
            var errMsg = ""
            if __DEV__ {
                errMsg = log.makePrintable(
                    "source data is not applicable for this boxplot transform. Expect number[][]."
                )
            }
            try log.throwError(errMsg)
        }

        // upstream: `upstream.getRawData() as number[][]` — a pure type-erasing TS cast that neither
        //   filters nor validates, so the coercion below must preserve ARITY: upstream keeps every
        //   non-numeric cell (a null / '-' / a string header cell) and simply degrades it to NaN inside
        //   the arithmetic, it does not drop it. Dropping cells would shift Q1/Q2/Q3; dropping a whole
        //   all-non-numeric row (getRawData returns `upstream.data` verbatim, header rows included)
        //   would hand prepareBoxplotData an empty array, which indexes `ascList[0]` unconditionally.
        let rawAny = try upstream.getRawData()
        let rawRows: [[Any?]] =
            (rawAny as? [[Any?]])
            ?? (rawAny as? [Any])?.compactMap { $0 as? [Any?] }
            ?? []
        let raw: [[Double]] = rawRows
            .map { row in row.map { boxplotToDouble($0) ?? Double.nan } }
            // PORT-NOTE: a genuinely EMPTY row yields `undefined`/NaN bounds in JS but is an
            //   index-out-of-range fatal error in Swift, so it is skipped rather than crashing.
            .filter { !$0.isEmpty }

        // upstream passes `params.config` (typed `PrepareBoxplotDataOpt`) straight through; the erased
        //   `Any?` config here may already be a `PrepareBoxplotDataOpt` or the raw option dictionary.
        var opt = PrepareBoxplotDataOpt()
        if let cfg = params.config as? PrepareBoxplotDataOpt {
            opt = cfg
            // prepareBoxplotData reads boundIQR as `as? Double`, so an Int-boxed value must be coerced.
            if let n = boxplotToDouble(opt.boundIQR) { opt.boundIQR = n }
        }
        else if let cfg = params.config as? [String: Any] {
            // boundIQR: number | 'none' — numbers first, so a numeric STRING ("1.5", which JS coerces
            //   arithmetically) is normalized to a Double; only the literal 'none' stays a String
            //   (`boxplotToDouble("none")` is nil).
            if let n = boxplotToDouble(cfg["boundIQR"]) { opt.boundIQR = n }
            else if let s = cfg["boundIQR"] as? String { opt.boundIQR = s }
            // itemNameFormatter: string | ((params: { value: number }) => string) — passed through
            //   erased, exactly as upstream does; prepareBoxplotData does the shape casts itself.
            opt.itemNameFormatter = cfg["itemNameFormatter"]
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
