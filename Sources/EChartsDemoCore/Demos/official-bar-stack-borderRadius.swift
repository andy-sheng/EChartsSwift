// official-bar-stack-borderRadius — replica of https://echarts.apache.org/examples/zh/editor.html?c=bar-stack-borderRadius
// title: Stacked Bar with borderRadius / titleCN: 带圆角的堆积柱状图
// Five bar series across two stacks ('a', 'b'); only the TOPMOST non-empty series of each stack, per
// category, gets a rounded top (`itemStyle.borderRadius: [20, 20, 0, 0]`) — so each stacked column
// reads as one rounded-cap bar. The official source computes that per-item itemStyle in a JS pre-pass
// (scan every category, remember the last series index whose value is truthy and not '-').
//
// DEVIATIONS from the official source:
//   - webOptionJS runs the pre-pass VERBATIM, minus the TypeScript-only bits that a classic script
//     rejects: the `const stackInfo: {[key: string]: ...}` type annotation, the two `as` casts, and
//     the trailing `export {}`. The loop bodies and the resulting option are untouched.
//   - The native pane cannot carry a JS pre-pass, so the SAME computation is pre-evaluated here and
//     its RESULT inlined: every data point is already a `{value, itemStyle: {borderRadius}}` object
//     (top radius 20 on the stack-top item, 0 elsewhere). Same rendered output, no runtime loop.
//     Empty points stay '-' / "-", exactly as upstream.
extension EChartsDemoRegistry {
    static let official_bar_stack_borderradius = EChartsDemo(
        name: "official-bar-stack-borderRadius", category: "bar",
        summary: "带圆角的堆积柱状图 — Stacked Bar with borderRadius",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
var series = [
{
    data: [120, 200, 150, 80, 70, 110, 130],
    type: 'bar',
    stack: 'a',
    name: 'a'
},
{
    data: [10, 46, 64, '-', 0, '-', 0],
    type: 'bar',
    stack: 'a',
    name: 'b'
},
{
    data: [30, '-', 0, 20, 10, '-', 0],
    type: 'bar',
    stack: 'a',
    name: 'c'
},
{
    data: [30, '-', 0, 20, 10, '-', 0],
    type: 'bar',
    stack: 'b',
    name: 'd'
},
{
    data: [10, 20, 150, 0, '-', 50, 10],
    type: 'bar',
    stack: 'b',
    name: 'e'
}
];

const stackInfo = {};
for (let i = 0; i < series[0].data.length; ++i) {
    for (let j = 0; j < series.length; ++j) {
        const stackName = series[j].stack;
        if (!stackName) {
        continue;
        }
        if (!stackInfo[stackName]) {
        stackInfo[stackName] = {
            stackStart: [],
            stackEnd: []
        };
        }
        const info = stackInfo[stackName];
        const data = series[j].data[i];
        if (data && data !== '-') {
        if (info.stackStart[i] == null) {
            info.stackStart[i] = j;
        }
        info.stackEnd[i] = j;
        }
    }
}
for (let i = 0; i < series.length; ++i) {
const data = series[i].data;
const info = stackInfo[series[i].stack];
for (let j = 0; j < series[i].data.length; ++j) {
    // const isStart = info.stackStart[j] === i;
    const isEnd = info.stackEnd[j] === i;
    const topBorder = isEnd ? 20 : 0;
    const bottomBorder = 0;
    data[j] = {
        value: data[j],
        itemStyle: {
            borderRadius: [topBorder, topBorder, bottomBorder, bottomBorder]
        }
    };
}
}

option = {
    xAxis: {
        type: 'category',
        data: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
    },
    yAxis: {
        type: 'value'
    },
    series: series
};
"""#,
        option: [
            "xAxis": [
                "type": "category",
                "data": ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
            ] as [String: Any],
            "yAxis": [
                "type": "value"
            ] as [String: Any],
            "series": [
                ["data": barStackRadiusA, "type": "bar", "stack": "a", "name": "a"] as [String: Any],
                ["data": barStackRadiusB, "type": "bar", "stack": "a", "name": "b"] as [String: Any],
                ["data": barStackRadiusC, "type": "bar", "stack": "a", "name": "c"] as [String: Any],
                ["data": barStackRadiusD, "type": "bar", "stack": "b", "name": "d"] as [String: Any],
                ["data": barStackRadiusE, "type": "bar", "stack": "b", "name": "e"] as [String: Any]
            ]
        ])
}

// One data point, in the shape the official pre-pass produces:
//   { value: <number|'-'>, itemStyle: { borderRadius: [top, top, 0, 0] } }
// `top` is 20 only where this series is the stack's topmost non-empty one for that category.
private func barStackRadiusItem(_ value: Any, _ top: Double) -> [String: Any] {
    ["value": value, "itemStyle": ["borderRadius": [top, top, 0.0, 0.0]] as [String: Any]]
}

// Pre-evaluated stackEnd (the JS pre-pass's result), per category Mon…Sun:
//   stack 'a' (series a,b,c → indices 0,1,2): [2, 1, 1, 2, 2, 0, 0]
//   stack 'b' (series d,e   → indices 3,4)  : [4, 4, 4, 3, 3, 4, 4]
// A point is "empty" (no radius, no bar) when its value is '-' or 0 — `data && data !== '-'` in the
// original, so a literal 0 is falsy and never counts as the stack top.

private let barStackRadiusA: [[String: Any]] = [
    barStackRadiusItem(120.0, 0), barStackRadiusItem(200.0, 0), barStackRadiusItem(150.0, 0),
    barStackRadiusItem(80.0, 0), barStackRadiusItem(70.0, 0), barStackRadiusItem(110.0, 20),
    barStackRadiusItem(130.0, 20)
]

private let barStackRadiusB: [[String: Any]] = [
    barStackRadiusItem(10.0, 0), barStackRadiusItem(46.0, 20), barStackRadiusItem(64.0, 20),
    barStackRadiusItem("-", 0), barStackRadiusItem(0.0, 0), barStackRadiusItem("-", 0),
    barStackRadiusItem(0.0, 0)
]

private let barStackRadiusC: [[String: Any]] = [
    barStackRadiusItem(30.0, 20), barStackRadiusItem("-", 0), barStackRadiusItem(0.0, 0),
    barStackRadiusItem(20.0, 20), barStackRadiusItem(10.0, 20), barStackRadiusItem("-", 0),
    barStackRadiusItem(0.0, 0)
]

private let barStackRadiusD: [[String: Any]] = [
    barStackRadiusItem(30.0, 0), barStackRadiusItem("-", 0), barStackRadiusItem(0.0, 0),
    barStackRadiusItem(20.0, 20), barStackRadiusItem(10.0, 20), barStackRadiusItem("-", 0),
    barStackRadiusItem(0.0, 0)
]

private let barStackRadiusE: [[String: Any]] = [
    barStackRadiusItem(10.0, 20), barStackRadiusItem(20.0, 20), barStackRadiusItem(150.0, 20),
    barStackRadiusItem(0.0, 0), barStackRadiusItem("-", 0), barStackRadiusItem(50.0, 20),
    barStackRadiusItem(10.0, 20)
]
