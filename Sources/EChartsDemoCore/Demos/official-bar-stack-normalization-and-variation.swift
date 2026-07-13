// official-bar-stack-normalization-and-variation — replica of
// https://echarts.apache.org/examples/zh/editor.html?c=bar-stack-normalization-and-variation
// title: Stacked Bar Normalization and Variation / titleCN: 堆叠柱状图的归一化和变化
//
// Five bar series stacked to a constant 1.0: each raw value is divided by its column total, so every
// column is a 100%-normalized stack. On top of the grid, a `graphic` component draws 5 × 6 translucent
// polygons — one per (series, adjacent-column pair) — connecting the top/bottom edge of a segment in
// column j-1 to the same segment in column j, so the VARIATION between neighbouring columns reads as a
// ribbon. The polygons are laid out in raw canvas pixels, computed from the grid box and the bar width.
//
// DEVIATIONS from the official source:
//   - `myChart.getWidth()` / `myChart.getHeight()`: the official editor computes the polygon geometry
//     from the LIVE chart instance. Our web pane runs the option script BEFORE `echarts.init` (see
//     WebPage.swift), and the Swift pane has no chart instance at option-build time, so both panes
//     substitute this demo's declared canvas size (640 × 420) — the exact size both panes render at,
//     so the geometry is identical to what the editor would compute.
//   - webOptionJS drops the TypeScript-only bits that a classic <script> cannot parse: the
//     `: number[]` / `: echarts.BarSeriesOption[]` / `(params: any)` annotations and the trailing
//     `export {};`. Everything else — the loops, the map, the label formatter — is verbatim.
//   - the native pane omits `series[].label.formatter` (a JS closure; see PORT-NOTE below). The
//     `graphic` polygons are plain data, not JS-built elements, so the native pane DOES carry them.
import Foundation

// There should not be negative values in rawData.
private let barStackNormRawData: [[Double]] = [
    [100, 302, 301, 334, 390, 330, 320],
    [320, 132, 101, 134, 90, 230, 210],
    [220, 182, 191, 234, 290, 330, 310],
    [150, 212, 201, 154, 190, 330, 410],
    [820, 832, 901, 934, 1290, 1330, 1320]
]

private let barStackNormSeriesNames = ["Direct", "Mail Ad", "Affiliate Ad", "Video Ad", "Search Engine"]

// Column totals — the normalization denominators.
private let barStackNormTotalData: [Double] = {
    var totals: [Double] = []
    for i in 0..<barStackNormRawData[0].count {
        var sum = 0.0
        for j in 0..<barStackNormRawData.count { sum += barStackNormRawData[j][i] }
        totals.append(sum)
    }
    return totals
}()

// The grid box, and the canvas the polygon geometry is computed against (see DEVIATIONS).
private let barStackNormGridLeft = 100.0
private let barStackNormGridRight = 100.0
private let barStackNormGridTop = 50.0
private let barStackNormGridBottom = 90.0
private let barStackNormChartWidth = 640.0
private let barStackNormChartHeight = 420.0

private let barStackNormSeries: [[String: Any]] = {
    var series: [[String: Any]] = []
    for sid in 0..<barStackNormSeriesNames.count {
        var data: [Double] = []
        for did in 0..<barStackNormRawData[sid].count {
            let total = barStackNormTotalData[did]
            data.append(total <= 0 ? 0 : barStackNormRawData[sid][did] / total)
        }
        series.append([
            "name": barStackNormSeriesNames[sid],
            "type": "bar",
            "stack": "total",
            "barWidth": "60%",
            // PORT-NOTE: label.formatter omitted — the JS closure
            //   (params) => Math.round(params.value * 1000) / 10 + '%'
            // renders each normalized fraction as a one-decimal percentage ("18.7%"). Swift cannot
            // carry a closure through the option dict, so the native pane's labels show the raw
            // fraction (0.187…) instead. `label.show` is kept so the labels are still laid out.
            "label": ["show": true] as [String: Any],
            "data": data
        ] as [String: Any])
    }
    return series
}()

// The variation ribbons: for each adjacent column pair (j-1, j) and each series i, a quad joining
// segment i's slab in column j-1 to its slab in column j. Canvas-pixel coordinates.
private let barStackNormGraphicElements: [[String: Any]] = {
    let gridWidth = barStackNormChartWidth - barStackNormGridLeft - barStackNormGridRight
    let gridHeight = barStackNormChartHeight - barStackNormGridTop - barStackNormGridBottom
    let categoryWidth = gridWidth / Double(barStackNormRawData[0].count)
    let barWidth = categoryWidth * 0.6
    let barPadding = (categoryWidth - barWidth) / 2
    let colors = ["#5070dd", "#b6d634", "#505372", "#ff994d", "#0ca8df"]

    var elements: [[String: Any]] = []
    for j in 1..<barStackNormRawData[0].count {
        let leftX = barStackNormGridLeft + categoryWidth * Double(j) - barPadding
        let rightX = leftX + barPadding * 2
        var leftY = barStackNormGridTop + gridHeight
        var rightY = leftY
        for i in 0..<barStackNormRawData.count {
            let leftBarHeight = (barStackNormRawData[i][j - 1] / barStackNormTotalData[j - 1]) * gridHeight
            let rightBarHeight = (barStackNormRawData[i][j] / barStackNormTotalData[j]) * gridHeight
            let points: [[Double]] = [
                [leftX, leftY],
                [leftX, leftY - leftBarHeight],
                [rightX, rightY - rightBarHeight],
                [rightX, rightY],
                [leftX, leftY]
            ]
            leftY -= leftBarHeight
            rightY -= rightBarHeight
            elements.append([
                "type": "polygon",
                "shape": ["points": points] as [String: Any],
                "style": ["fill": colors[i], "opacity": 0.25] as [String: Any]
            ] as [String: Any])
        }
    }
    return elements
}()

extension EChartsDemoRegistry {
    static let official_bar_stack_normalization_and_variation = EChartsDemo(
        name: "official-bar-stack-normalization-and-variation", category: "bar",
        summary: "堆叠柱状图的归一化和变化 — Stacked Bar Normalization and Variation",
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

const grid = {
    left: 100,
    right: 100,
    top: 50,
    bottom: 90
};
// Upstream reads these off the live chart (myChart.getWidth() / getHeight()); this page builds the
// option BEFORE echarts.init, so the demo's declared canvas size is substituted verbatim.
const gridWidth = 640 - grid.left - grid.right;
const gridHeight = 420 - grid.top - grid.bottom;
const categoryWidth = gridWidth / rawData[0].length;
const barWidth = categoryWidth * 0.6;
const barPadding = (categoryWidth - barWidth) / 2;

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

const color = [
    '#5070dd',
    '#b6d634',
    '#505372',
    '#ff994d',
    '#0ca8df'
];
const elements = [];
for (let j = 1, jlen = rawData[0].length; j < jlen; ++j) {
    const leftX = grid.left + categoryWidth * j - barPadding;
    const rightX = leftX + barPadding * 2;
    let leftY = grid.top + gridHeight;
    let rightY = leftY;
    for (let i = 0, len = series.length; i < len; ++i) {
        const points = [];
        const leftBarHeight = (rawData[i][j - 1] / totalData[j - 1]) * gridHeight;
        points.push([leftX, leftY]);
        points.push([leftX, leftY - leftBarHeight]);
        const rightBarHeight = (rawData[i][j] / totalData[j]) * gridHeight;
        points.push([rightX, rightY - rightBarHeight]);
        points.push([rightX, rightY]);
        points.push([leftX, leftY]);

        leftY -= leftBarHeight;
        rightY -= rightBarHeight;

        elements.push({
            type: 'polygon',
            shape: {
                points
            },
            style: {
                fill: color[i],
                opacity: 0.25
            }
        });
    }
}

option = {
    legend: {
        selectedMode: false
    },
    grid,
    yAxis: {
        type: 'value'
    },
    xAxis: {
        type: 'category',
        data: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
    },
    series,
    graphic: {
      elements
    }
};
"""#,
        option: [
            "legend": [
                "selectedMode": false
            ] as [String: Any],
            "grid": [
                "left": barStackNormGridLeft,
                "right": barStackNormGridRight,
                "top": barStackNormGridTop,
                "bottom": barStackNormGridBottom
            ] as [String: Any],
            "yAxis": [
                "type": "value"
            ] as [String: Any],
            "xAxis": [
                "type": "category",
                "data": ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
            ] as [String: Any],
            "series": barStackNormSeries,
            "graphic": [
                "elements": barStackNormGraphicElements
            ] as [String: Any]
        ])
}
