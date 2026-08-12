// official-watermark — replica of https://echarts.apache.org/examples/zh/editor.html?c=watermark
// title: Watermark - ECharts Download / titleCN: 水印 - ECharts 下载统计
// A 3-title dashboard: two stacked "progress bar" grids (charts / components, each bar padded to
// builderJson.all with a grey #eee filler bar) plus two pies (dist downloads / theme downloads),
// all drawn over a repeating canvas-pattern "ECHARTS" watermark background.
//
// DEVIATIONS from the official source:
//  - webOptionJS: the source is TypeScript; the TS-only syntax (`as Record<string, number>`,
//    `: Record<string, number>`, the `!` non-null assertion on getContext) and the trailing
//    `export {};` are stripped — they are SyntaxErrors in the page's classic script. Everything
//    else, including the whole document.createElement('canvas') watermark block, is verbatim.
//  - native pane: the browser's live-canvas pattern is represented by an equivalent grid of
//    low-z `graphic` text elements. Native pattern images require a decodable raster image, while
//    the official example supplies a DOM canvas; the explicit text grid preserves the same 100pt
//    tile spacing, -45° rotation, font size, opacity and placement without a browser object.
//  - the JS `Object.keys(...).map/reduce` expressions that build the series data and the title
//    subtexts are evaluated ahead of time into the Swift literals below (same values, same key
//    order); the `.replace('.js', '')` pie names are likewise pre-applied.
private let watermarkGraphicElements: [[String: Any]] = {
    var elements: [[String: Any]] = []
    for row in 0..<5 {
        for column in 0..<8 {
            elements.append([
                "type": "text",
                "x": 50.0 + Double(column) * 100.0,
                "y": 50.0 + Double(row) * 100.0,
                "rotation": -Double.pi / 4.0,
                "z": -100.0,
                "silent": true,
                "style": [
                    "text": "ECHARTS",
                    "x": 0.0,
                    "y": 0.0,
                    "align": "center",
                    "verticalAlign": "middle",
                    "font": "20px Microsoft Yahei",
                    "fill": "rgba(0,0,0,0.08)"
                ] as [String: Any]
            ])
        }
    }
    return elements
}()

extension EChartsDemoRegistry {
    static let official_watermark = EChartsDemo(
        name: "official-watermark", category: "bar",
        summary: "水印 - ECharts 下载统计 — Watermark - ECharts Download",
        width: 720, height: 480,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
const builderJson = {
  all: 10887,
  charts: {
    map: 3237,
    lines: 2164,
    bar: 7561,
    line: 7778,
    pie: 7355,
    scatter: 2405,
    candlestick: 1842,
    radar: 2090,
    heatmap: 1762,
    treemap: 1593,
    graph: 2060,
    boxplot: 1537,
    parallel: 1908,
    gauge: 2107,
    funnel: 1692,
    sankey: 1568
  },
  components: {
    geo: 2788,
    title: 9575,
    legend: 9400,
    tooltip: 9466,
    grid: 9266,
    markPoint: 3419,
    markLine: 2984,
    timeline: 2739,
    dataZoom: 2744,
    visualMap: 2466,
    toolbox: 3034,
    polar: 1945
  },
  ie: 9743
};

const downloadJson = {
  'echarts.min.js': 17365,
  'echarts.simple.min.js': 4079,
  'echarts.common.min.js': 6929,
  'echarts.js': 14890
};

const themeJson = {
  'dark.js': 1594,
  'infographic.js': 925,
  'shine.js': 1608,
  'roma.js': 721,
  'macarons.js': 2179,
  'vintage.js': 1982
};

const waterMarkText = 'ECHARTS';

const canvas = document.createElement('canvas');
const ctx = canvas.getContext('2d');
canvas.width = canvas.height = 100;
ctx.textAlign = 'center';
ctx.textBaseline = 'middle';
ctx.globalAlpha = 0.08;
ctx.font = '20px Microsoft Yahei';
ctx.translate(50, 50);
ctx.rotate(-Math.PI / 4);
ctx.fillText(waterMarkText, 0, 0);

option = {
  backgroundColor: {
    type: 'pattern',
    image: canvas,
    repeat: 'repeat'
  },
  tooltip: {},
  title: [
    {
      text: '在线构建',
      subtext: '总计 ' + builderJson.all,
      left: '25%',
      textAlign: 'center'
    },
    {
      text: '各版本下载',
      subtext:
        '总计 ' +
        Object.keys(downloadJson).reduce(function (all, key) {
          return all + downloadJson[key];
        }, 0),
      left: '75%',
      textAlign: 'center'
    },
    {
      text: '主题下载',
      subtext:
        '总计 ' +
        Object.keys(themeJson).reduce(function (all, key) {
          return all + themeJson[key];
        }, 0),
      left: '75%',
      top: '50%',
      textAlign: 'center'
    }
  ],
  grid: [
    {
      top: 50,
      width: '50%',
      bottom: '45%',
      left: 10,
      containLabel: true
    },
    {
      top: '55%',
      width: '50%',
      bottom: 0,
      left: 10,
      containLabel: true
    }
  ],
  xAxis: [
    {
      type: 'value',
      max: builderJson.all,
      splitLine: {
        show: false
      }
    },
    {
      type: 'value',
      max: builderJson.all,
      gridIndex: 1,
      splitLine: {
        show: false
      }
    }
  ],
  yAxis: [
    {
      type: 'category',
      data: Object.keys(builderJson.charts),
      axisLabel: {
        interval: 0,
        rotate: 30
      },
      splitLine: {
        show: false
      }
    },
    {
      gridIndex: 1,
      type: 'category',
      data: Object.keys(builderJson.components),
      axisLabel: {
        interval: 0,
        rotate: 30
      },
      splitLine: {
        show: false
      }
    }
  ],
  series: [
    {
      type: 'bar',
      stack: 'chart',
      z: 3,
      label: {
        position: 'right',
        show: true
      },
      data: Object.keys(builderJson.charts).map(function (key) {
        return builderJson.charts[key];
      })
    },
    {
      type: 'bar',
      stack: 'chart',
      silent: true,
      itemStyle: {
        color: '#eee'
      },
      data: Object.keys(builderJson.charts).map(function (key) {
        return builderJson.all - builderJson.charts[key];
      })
    },
    {
      type: 'bar',
      stack: 'component',
      xAxisIndex: 1,
      yAxisIndex: 1,
      z: 3,
      label: {
        position: 'right',
        show: true
      },
      data: Object.keys(builderJson.components).map(function (key) {
        return builderJson.components[key];
      })
    },
    {
      type: 'bar',
      stack: 'component',
      silent: true,
      xAxisIndex: 1,
      yAxisIndex: 1,
      itemStyle: {
        color: '#eee'
      },
      data: Object.keys(builderJson.components).map(function (key) {
        return builderJson.all - builderJson.components[key];
      })
    },
    {
      type: 'pie',
      radius: [0, '30%'],
      center: ['75%', '25%'],
      data: Object.keys(downloadJson).map(function (key) {
        return {
          name: key.replace('.js', ''),
          value: downloadJson[key]
        };
      })
    },
    {
      type: 'pie',
      radius: [0, '30%'],
      center: ['75%', '75%'],
      data: Object.keys(themeJson).map(function (key) {
        return {
          name: key.replace('.js', ''),
          value: themeJson[key]
        };
      })
    }
  ]
};
"""#,
        option: [
            "graphic": watermarkGraphicElements,
            "tooltip": [:] as [String: Any],
            "title": [
                [
                    "text": "在线构建",
                    "subtext": "总计 10887",          // '总计 ' + builderJson.all
                    "left": "25%",
                    "textAlign": "center"
                ] as [String: Any],
                [
                    "text": "各版本下载",
                    "subtext": "总计 43263",          // sum of downloadJson values
                    "left": "75%",
                    "textAlign": "center"
                ] as [String: Any],
                [
                    "text": "主题下载",
                    "subtext": "总计 9009",           // sum of themeJson values
                    "left": "75%",
                    "top": "50%",
                    "textAlign": "center"
                ] as [String: Any]
            ],
            "grid": [
                [
                    "top": 50.0,
                    "width": "50%",
                    "bottom": "45%",
                    "left": 10.0,
                    "containLabel": true
                ] as [String: Any],
                [
                    "top": "55%",
                    "width": "50%",
                    "bottom": 0.0,
                    "left": 10.0,
                    "containLabel": true
                ] as [String: Any]
            ],
            "xAxis": [
                [
                    "type": "value",
                    "max": watermarkAll,
                    "splitLine": ["show": false] as [String: Any]
                ] as [String: Any],
                [
                    "type": "value",
                    "max": watermarkAll,
                    "gridIndex": 1.0,
                    "splitLine": ["show": false] as [String: Any]
                ] as [String: Any]
            ],
            "yAxis": [
                [
                    "type": "category",
                    "data": watermarkChartNames,
                    "axisLabel": ["interval": 0.0, "rotate": 30.0] as [String: Any],
                    "splitLine": ["show": false] as [String: Any]
                ] as [String: Any],
                [
                    "gridIndex": 1.0,
                    "type": "category",
                    "data": watermarkComponentNames,
                    "axisLabel": ["interval": 0.0, "rotate": 30.0] as [String: Any],
                    "splitLine": ["show": false] as [String: Any]
                ] as [String: Any]
            ],
            "series": [
                [
                    "type": "bar",
                    "stack": "chart",
                    "z": 3.0,
                    "label": ["position": "right", "show": true] as [String: Any],
                    "data": watermarkChartValues
                ] as [String: Any],
                [
                    "type": "bar",
                    "stack": "chart",
                    "silent": true,
                    "itemStyle": ["color": "#eee"] as [String: Any],
                    "data": watermarkChartRest
                ] as [String: Any],
                [
                    "type": "bar",
                    "stack": "component",
                    "xAxisIndex": 1.0,
                    "yAxisIndex": 1.0,
                    "z": 3.0,
                    "label": ["position": "right", "show": true] as [String: Any],
                    "data": watermarkComponentValues
                ] as [String: Any],
                [
                    "type": "bar",
                    "stack": "component",
                    "silent": true,
                    "xAxisIndex": 1.0,
                    "yAxisIndex": 1.0,
                    "itemStyle": ["color": "#eee"] as [String: Any],
                    "data": watermarkComponentRest
                ] as [String: Any],
                [
                    "type": "pie",
                    "radius": [0.0, "30%"] as [Any],
                    "center": ["75%", "25%"],
                    "data": watermarkDownloadPie
                ] as [String: Any],
                [
                    "type": "pie",
                    "radius": [0.0, "30%"] as [Any],
                    "center": ["75%", "75%"],
                    "data": watermarkThemePie
                ] as [String: Any]
            ]
        ])
}

// builderJson.all — the axis max every bar pair is padded up to.
private let watermarkAll: Double = 10887

// Object.keys(builderJson.charts) / .map(key => charts[key]) / .map(key => all - charts[key]).
private let watermarkChartNames: [String] = [
    "map", "lines", "bar", "line", "pie", "scatter", "candlestick", "radar",
    "heatmap", "treemap", "graph", "boxplot", "parallel", "gauge", "funnel", "sankey"
]
private let watermarkChartValues: [Double] = [
    3237, 2164, 7561, 7778, 7355, 2405, 1842, 2090,
    1762, 1593, 2060, 1537, 1908, 2107, 1692, 1568
]
private let watermarkChartRest: [Double] = [
    7650, 8723, 3326, 3109, 3532, 8482, 9045, 8797,
    9125, 9294, 8827, 9350, 8979, 8780, 9195, 9319
]

// Object.keys(builderJson.components) and the same two maps.
private let watermarkComponentNames: [String] = [
    "geo", "title", "legend", "tooltip", "grid", "markPoint",
    "markLine", "timeline", "dataZoom", "visualMap", "toolbox", "polar"
]
private let watermarkComponentValues: [Double] = [
    2788, 9575, 9400, 9466, 9266, 3419,
    2984, 2739, 2744, 2466, 3034, 1945
]
private let watermarkComponentRest: [Double] = [
    8099, 1312, 1487, 1421, 1621, 7468,
    7903, 8148, 8143, 8421, 7853, 8942
]

// downloadJson / themeJson as pie data; names have `.js` stripped (JS String.replace, first match).
private let watermarkDownloadPie: [[String: Any]] = [
    ["name": "echarts.min", "value": 17365.0],
    ["name": "echarts.simple.min", "value": 4079.0],
    ["name": "echarts.common.min", "value": 6929.0],
    ["name": "echarts", "value": 14890.0]
]
private let watermarkThemePie: [[String: Any]] = [
    ["name": "dark", "value": 1594.0],
    ["name": "infographic", "value": 925.0],
    ["name": "shine", "value": 1608.0],
    ["name": "roma", "value": 721.0],
    ["name": "macarons", "value": 2179.0],
    ["name": "vintage", "value": 1982.0]
]
