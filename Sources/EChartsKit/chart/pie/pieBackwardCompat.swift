// Pie/gauge slice of echarts/src/preprocessor/backwardCompat.ts.
//
// Upstream runs this before model defaults are merged. That ordering matters for the deprecated
// `label.margin` alias: once PieSeries.defaultOption has supplied `edgeDistance: "25%"`, it is no
// longer possible to tell whether the caller explicitly provided edgeDistance.

import Foundation

/// Migrate the deprecated pie/gauge edge-aligned label margin to `edgeDistance`.
///
/// Mirrors upstream `compatPieLabel` and its traversal of the series-level label and data items.
/// Swift dictionaries are value types, so every mutated child is written back into the option tree.
public func pieBackwardCompat(_ option: inout ECUnitOption) {
    guard let rawSeries = option["series"] else { return }

    if var series = rawSeries as? [Any] {
        for index in series.indices {
            guard var seriesOption = series[index] as? [String: Any] else { continue }
            compatPieSeries(&seriesOption)
            series[index] = seriesOption
        }
        option["series"] = series
    }
    else if var seriesOption = rawSeries as? [String: Any] {
        // The complete upstream preprocessor first array-normalizes series. The Swift option pipeline
        // also accepts the convenient singleton form, so preserve that public input shape here.
        compatPieSeries(&seriesOption)
        option["series"] = seriesOption
    }
}

private func compatPieSeries(_ seriesOption: inout [String: Any]) {
    guard let type = seriesOption["type"] as? String, type == "pie" || type == "gauge" else { return }

    if var label = seriesOption["label"] as? [String: Any] {
        compatPieLabel(&label)
        seriesOption["label"] = label
    }

    if var data = seriesOption["data"] as? [Any] {
        for index in data.indices {
            guard var item = data[index] as? [String: Any] else { continue }
            // This intentionally matches upstream's `compatPieLabel(data[i])`: legacy per-item
            // alignTo/margin fields live on the data item itself rather than under item.label.
            compatPieLabel(&item)
            data[index] = item
        }
        seriesOption["data"] = data
    }
}

private func compatPieLabel(_ label: inout [String: Any]) {
    guard (label["alignTo"] as? String) == "edge",
          !isNullish(label["margin"]),
          isNullish(label["edgeDistance"])
    else { return }

    label["edgeDistance"] = label["margin"]
}

private func isNullish(_ value: Any?) -> Bool {
    value == nil || value is NSNull
}
