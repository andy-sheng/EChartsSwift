// official-cycle-plot — replica of https://echarts.apache.org/examples/zh/editor.html?c=cycle-plot
// title: Cycle Plot / titleCN: 周期图
// Sales-trend cycle plot: within each month's category band, one `custom` series draws a polyline
// linking that month's 2002-2012 values (year fanned across the band), a second `custom` series draws
// a horizontal line at the month's 11-year average. dataZoom (slider + inside) over the 12 months.
//
// DEVIATIONS from the official source:
//   - NATIVE PANE UNSUPPORTED (nativeSupported: false). BOTH series are `custom`, and their
//     `renderItem` closures ARE the chart: `renderTrendItem` fans the 11 year-values of a month across
//     0.85 of the band and returns a `polyline` through them; `renderAverageItem` returns a horizontal
//     `line` at the month's average spanning 0.85 of the band. A Swift [String: Any] cannot carry a JS
//     function, so dropping them leaves the two custom series with nothing to draw. Everything else IS
//     ported (tooltip, title, legend, dataZoom, grid, xAxis, yAxis, encode, and the series data), so the
//     option lights up the moment renderItem gains a native form.
//   - Data is inline in the source (no asset fetch). `dataByMonth` and `averageByMonth` are DERIVED from
//     `rawData` in JS at load time; the native pane recomputes them in Swift below, mirroring the JS
//     transforms 1:1 (verified byte-identical), and feeds them as each series' `data`.
import Foundation
import EChartsKit

// MARK: - raw + derived data (mirrors the example's load-time transforms)

// prettier-ignore — one row per year: [year, Jan, Feb, ..., Dec]
private let cyclePlotRawData: [[Double]] = [
    [2002, 14, 21, 25, 21, 26, 32, 27, 20, 10, 11, 5, 5],
    [2003, 18, 24, 28, 24, 33, 37, 30, 25, 13, 14, 6, 6],
    [2004, 22, 31, 36, 28, 37, 43, 35, 30, 13, 13, 7, 7],
    [2005, 25, 32, 38, 34, 39, 48, 38, 29, 14, 14, 8, 8],
    [2006, 29, 38, 47, 33, 44, 57, 41, 39, 16, 16, 9, 8],
    [2007, 29, 35, 49, 34, 43, 57, 41, 37, 20, 17, 9, 10],
    [2008, 22, 32, 37, 30, 35, 44, 38, 31, 16, 17, 8, 7],
    [2009, 25, 34, 41, 33, 39, 47, 44, 32, 17, 17, 9, 8],
    [2010, 26, 35, 46, 40, 47, 61, 47, 41, 20, 18, 9, 10],
    [2011, 29, 39, 55, 38, 55, 67, 53, 41, 19, 20, 11, 11],
    [2012, 38, 48, 60, 49, 57, 79, 62, 54, 26, 26, 13, 11]
]

private let cyclePlotMonths: [String] =
    ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

/// Transpose: `dataByMonth[monthIndex] = [monthIndex, val2002, val2003, ..., val2012]` (12 entries).
private let cyclePlotDataByMonth: [[Double]] = {
    let slots = cyclePlotRawData.count + 1   // monthIndex + one value per year
    var dataByMonth: [[Double]] = Array(repeating: Array(repeating: 0, count: slots), count: 12)
    for (yearIndex, entry) in cyclePlotRawData.enumerated() {
        for (index, value) in entry.enumerated() where index != 0 {
            let monthIndex = index - 1
            dataByMonth[monthIndex][0] = Double(monthIndex)
            dataByMonth[monthIndex][yearIndex + 1] = value
        }
    }
    return dataByMonth
}()

/// `averageByMonth[monthIndex] = [monthIndex, mean of that month's year-values]`.
private let cyclePlotAverageByMonth: [[Double]] = {
    cyclePlotDataByMonth.enumerated().map { (index, entry) in
        let sum = entry.enumerated().reduce(0.0) { $0 + ($1.offset == 0 ? 0 : $1.element) }
        return [Double(index), sum / Double(entry.count - 1)]
    }
}()

/// Upstream: `encode.y = rawData.map((entry, index) => index + 1)` → [1, 2, ..., 11].
private let cyclePlotTrendEncodeY: [Double] = (1...cyclePlotRawData.count).map(Double.init)

extension EChartsDemoRegistry {
    static let official_cycle_plot = EChartsDemo(
        name: "official-cycle-plot", category: "custom",
        summary: "周期图 — Cycle Plot",
        width: 720, height: 460,
        nativeSupported: false,
        collection: .official,
        webOptionJS: #"""
// prettier-ignore
var rawData = [
    [2002, 14, 21, 25, 21, 26, 32, 27, 20, 10, 11, 5, 5],
    [2003, 18, 24, 28, 24, 33, 37, 30, 25, 13, 14, 6, 6],
    [2004, 22, 31, 36, 28, 37, 43, 35, 30, 13, 13, 7, 7],
    [2005, 25, 32, 38, 34, 39, 48, 38, 29, 14, 14, 8, 8],
    [2006, 29, 38, 47, 33, 44, 57, 41, 39, 16, 16, 9, 8],
    [2007, 29, 35, 49, 34, 43, 57, 41, 37, 20, 17, 9, 10],
    [2008, 22, 32, 37, 30, 35, 44, 38, 31, 16, 17, 8, 7],
    [2009, 25, 34, 41, 33, 39, 47, 44, 32, 17, 17, 9, 8],
    [2010, 26, 35, 46, 40, 47, 61, 47, 41, 20, 18, 9, 10],
    [2011, 29, 39, 55, 38, 55, 67, 53, 41, 19, 20, 11, 11],
    [2012, 38, 48, 60, 49, 57, 79, 62, 54, 26, 26, 13, 11]
];

var dataByMonth = [];
// prettier-ignore
var months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
rawData.forEach(function (entry, yearIndex) {
  entry.forEach(function (value, index) {
    if (index) {
      var monthIndex = index - 1;
      var monthItem = (dataByMonth[monthIndex] = dataByMonth[monthIndex] || []);
      monthItem[0] = monthIndex;
      monthItem[yearIndex + 1] = value;
    }
  });
});
var averageByMonth = [];
dataByMonth.forEach(function (entry, index) {
  var sum = 0;
  entry.forEach(function (value, index) {
    index && (sum += value);
  });
  averageByMonth.push([index, sum / (entry.length - 1)]);
});

function renderTrendItem(params, api) {
  var categoryIndex = api.value(0);
  var unitBandWidth = (api.size([0, 0])[0] * 0.85) / (rawData.length - 1);

  var points = rawData.map(function (entry, index) {
    var value = api.value(index + 1);
    var point = api.coord([categoryIndex, value]);
    point[0] += unitBandWidth * (index - rawData.length / 2);
    return point;
  });

  return {
    type: 'polyline',
    transition: ['shape'],
    shape: {
      points: points
    },
    style: api.style({
      fill: null,
      stroke: api.visual('color'),
      lineWidth: 2
    })
  };
}

function renderAverageItem(param, api) {
  var bandWidth = api.size([0, 0])[0] * 0.85;
  var point = api.coord([api.value(0), api.value(1)]);

  return {
    type: 'line',
    transition: ['shape'],
    shape: {
      x1: point[0] - bandWidth / 2,
      x2: point[0] + bandWidth / 2,
      y1: point[1],
      y2: point[1]
    },
    style: api.style({
      fill: null,
      stroke: api.visual('color'),
      lineWidth: 2
    })
  };
}

option = {
  tooltip: {},
  title: {
    text: 'Sales Trends by Year within Each Month',
    subtext: 'Sample of Cycle Plot',
    left: 'center'
  },
  legend: {
    top: 70,
    data: ['Trend by year (2002 - 2012)', 'Average']
  },
  dataZoom: [
    {
      type: 'slider',
      labelFormatter: ''
    },
    {
      type: 'inside'
    }
  ],
  grid: {
    bottom: 70,
    top: 120
  },
  xAxis: {
    data: months
  },
  yAxis: {
    boundaryGap: [0, '20%']
  },
  series: [
    {
      type: 'custom',
      name: 'Average',
      renderItem: renderAverageItem,
      encode: {
        x: 0,
        y: 1
      },
      data: averageByMonth
    },
    {
      type: 'custom',
      name: 'Trend by year (2002 - 2012)',
      renderItem: renderTrendItem,
      encode: {
        x: 0,
        y: rawData.map(function (entry, index) {
          return index + 1;
        })
      },
      data: dataByMonth
    }
  ]
};
"""#,
        option: [
            "tooltip": [:] as [String: Any],
            "title": [
                "text": "Sales Trends by Year within Each Month",
                "subtext": "Sample of Cycle Plot",
                "left": "center"
            ] as [String: Any],
            "legend": [
                "top": 70.0,
                "data": ["Trend by year (2002 - 2012)", "Average"]
            ] as [String: Any],
            "dataZoom": [
                [
                    "type": "slider",
                    "labelFormatter": ""
                ] as [String: Any],
                [
                    "type": "inside"
                ] as [String: Any]
            ],
            "grid": [
                "bottom": 70.0,
                "top": 120.0
            ] as [String: Any],
            "xAxis": [
                "data": cyclePlotMonths
            ] as [String: Any],
            "yAxis": [
                "boundaryGap": [0.0, "20%"] as [Any]
            ] as [String: Any],
            "series": [
                [
                    "type": "custom",
                    "name": "Average",
                    // PORT-NOTE: renderItem omitted — `renderAverageItem` returned a horizontal `line`
                    // at the month's average y (api.coord([value(0), value(1)])), spanning bandWidth =
                    // api.size([0,0])[0] * 0.85 centred on the category, stroked api.visual('color') at
                    // lineWidth 2. Without it this custom series draws nothing (nativeSupported: false).
                    "encode": [
                        "x": 0.0,
                        "y": 1.0
                    ] as [String: Any],
                    "data": cyclePlotAverageByMonth
                ] as [String: Any],
                [
                    "type": "custom",
                    "name": "Trend by year (2002 - 2012)",
                    // PORT-NOTE: renderItem omitted — `renderTrendItem` fanned the month's 11 year-values
                    // across the band (each point's x nudged by unitBandWidth*(index - 11/2), where
                    // unitBandWidth = api.size([0,0])[0]*0.85 / 10) and returned a `polyline` through them,
                    // stroked api.visual('color') at lineWidth 2. Omitting it leaves nothing to draw.
                    "encode": [
                        "x": 0.0,
                        "y": cyclePlotTrendEncodeY
                    ] as [String: Any],
                    "data": cyclePlotDataByMonth
                ] as [String: Any]
            ]
        ])
}
