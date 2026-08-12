// official-bar-stack-normalization — replica of https://echarts.apache.org/examples/zh/editor.html?c=bar-stack-normalization
// title: Stacked Bar Normalization / titleCN: 堆叠柱状图的归一化
// Five bar series stacked on 'total', each datum divided by its column sum, so every day's stack
// sums to 1 and the bars read as percentage composition. Legend is display-only (selectedMode: false,
// since toggling a series off would break the normalization).
// DEVIATIONS:
//   - webOptionJS: the source is TypeScript; the type annotations (`: number[]`,
//     `echarts.BarSeriesOption[]`, `params: any`) and the trailing `export {};` are stripped so it
//     runs as a classic script. Everything else — rawData, the total/normalize loops, the series
//     .map() and the label formatter — is verbatim.
//   - native pane: the JavaScript label closure is expressed as the equivalent typed Swift callback.
//     The series array itself is built in Swift from the same rawData with the same normalization.
import Foundation
import EChartsKit

extension EChartsDemoRegistry {
    static let official_bar_stack_normalization = EChartsDemo(
        name: "official-bar-stack-normalization", category: "bar",
        summary: "堆叠柱状图的归一化 — Stacked Bar Normalization",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
// There should not be negative values in rawData
const rawData = [
    [100, 302, 301, 334, 390, 330, 320],
    [320, 132, 101, 134, 90, 230, 210],
    [220, 182, 191, 234, 290, 330, 310],
    [150, 212, 201, 154, 190, 330, 410],
    [820, 832, 901, 934, 1290, 1330, 1320]
];
const totalData = [];
for (let i = 0; i < rawData[0].length; ++i) {
    let sum = 0;
    for (let j = 0; j < rawData.length; ++j) {
        sum += rawData[j][i];
    }
    totalData.push(sum);
}

const series = [
    'Direct',
    'Mail Ad',
    'Affiliate Ad',
    'Video Ad',
    'Search Engine'
].map((name, sid) => {
    return {
        name,
        type: 'bar',
        stack: 'total',
        barWidth: '60%',
        label: {
            show: true,
            formatter: (params) => Math.round(params.value * 1000) / 10 + '%'
        },
        data: rawData[sid].map((d, did) =>
        totalData[did] <= 0 ? 0 : d / totalData[did]
        )
    };
});

option = {
    legend: {
        selectedMode: false
    },
    yAxis: {
        type: 'value'
    },
    xAxis: {
        type: 'category',
        data: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
    },
    series
};
"""#,
        option: [
            "legend": [
                "selectedMode": false
            ] as [String: Any],
            "yAxis": [
                "type": "value"
            ] as [String: Any],
            "xAxis": [
                "type": "category",
                "data": ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
            ] as [String: Any],
            "series": barStackNormalizationSeries
        ])
}

// There should not be negative values in rawData. Rows are the five series, columns the seven days.
private let barStackNormalizationRawData: [[Double]] = [
    [100, 302, 301, 334, 390, 330, 320],
    [320, 132, 101, 134, 90, 230, 210],
    [220, 182, 191, 234, 290, 330, 310],
    [150, 212, 201, 154, 190, 330, 410],
    [820, 832, 901, 934, 1290, 1330, 1320]
]

/// Column sums (`totalData` in the source) — the denominator that normalizes each stack to 1.
private let barStackNormalizationTotals: [Double] = (0..<barStackNormalizationRawData[0].count).map { i in
    barStackNormalizationRawData.reduce(0.0) { $0 + $1[i] }
}

private let barStackNormalizationNames: [String] = [
    "Direct", "Mail Ad", "Affiliate Ad", "Video Ad", "Search Engine"
]

/// Equivalent of `Math.round(params.value * 1000) / 10 + '%'` from the official example.
private let barStackNormalizationLabelFormatter: (CallbackDataParams) -> String = { params in
    let value: Double
    if let double = params.value as? Double { value = double }
    else if let int = params.value as? Int { value = Double(int) }
    else if let number = params.value as? NSNumber { value = number.doubleValue }
    else { return "" }

    let percent = (value * 1_000).rounded() / 10
    if percent.rounded() == percent {
        return "\(Int(percent))%"
    }
    return "\(percent)%"
}

/// One stacked `bar` series per name, data normalized by its column total (0 when the total is <= 0).
private let barStackNormalizationSeries: [[String: Any]] = barStackNormalizationNames.enumerated().map { sid, name in
    let normalized: [Double] = barStackNormalizationRawData[sid].enumerated().map { did, d in
        let total: Double = barStackNormalizationTotals[did]
        return total <= 0 ? 0.0 : d / total
    }
    return [
        "name": name,
        "type": "bar",
        "stack": "total",
        "barWidth": "60%",
        "label": [
            "show": true,
            "formatter": barStackNormalizationLabelFormatter
        ] as [String: Any],
        "data": normalized
    ] as [String: Any]
}
