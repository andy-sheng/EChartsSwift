// official-wind-barb — replica of https://echarts.apache.org/examples/zh/editor.html?c=wind-barb
// title: Wind Barb / titleCN: 风向图
// Hobart marine forecast: a wave-height area line + a wind-speed line, overlaid with `custom`-series
// wind barbs (rotated arrows at each hour, direction from R) and a `custom`-series row of weather
// icons + min/max temps, with a piecewise visualMap, time xAxis and inside+slider dataZoom.
//
// DEVIATIONS from the official source:
//   - Data fetch inlined: the upstream `$.getJSON(ROOT_PATH + '/data/asset/data/wind-barb-hobart.json',
//     function (rawData) { ... })` wrapper is dropped; its callback body runs at top level with
//     `rawData` spliced in verbatim from assets/data/wind-barb-hobart.json (both panes).
//   - Weather-icon PNGs (showers/sunny/cloudy_128.png) are inlined as base64 `data:image/png;base64,…`
//     URIs — the web pane cannot reach the filesystem. Native reads the same files from assets/img/weather/.
//   - TypeScript type annotations (`: Record<…>`, `: echarts.CustomSeries…`, `as number/string`) stripped
//     so the classic <script> parses; nothing else about the JS changed.
//   - nativeSupported = false: the chart's identity IS two `custom` series whose renderItem closures
//     draw the arrows (renderArrow) and the icon+temperature groups (renderWeather). The Swift option
//     cannot carry a renderItem, so the native pane can only show the two plain line series — not the
//     wind barbs the example is named for. The `option` below is still a faithful port (renderItems and
//     the tooltip/series formatters omitted with notes) for when the framework can carry them.
import Foundation
import EChartsKit

// Raw JSON spliced into the web pane verbatim (the fetch's `rawData`); falls back to an empty payload.
private let windBarbRawJSON: String = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/data/wind-barb-hobart.json")
    return (try? String(contentsOf: url, encoding: .utf8)) ?? #"{"data":[],"forecast":[]}"#
}()

// Parsed once for the native option's data arrays; a read/parse failure degrades to empty (blank pane).
private let windBarbParsed: [String: Any] = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/data/wind-barb-hobart.json")
    guard let data = try? Data(contentsOf: url),
          let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        return [:]
    }
    return obj
}()

// Weather-icon PNGs → base64 data: URIs (spliced into the web pane; the page has no filesystem).
private func windBarbIconURI(_ file: String) -> String {
    let url = Upstream.repoRoot.appendingPathComponent("assets/img/weather/\(file)")
    guard let data = try? Data(contentsOf: url) else { return "" }
    return "data:image/png;base64," + data.base64EncodedString()
}
private let windBarbShowersURI = windBarbIconURI("showers_128.png")
private let windBarbSunnyURI = windBarbIconURI("sunny_128.png")
private let windBarbCloudyURI = windBarbIconURI("cloudy_128.png")

// data.map(entry => [entry.time, entry.windSpeed, entry.R, entry.waveHeight]) — heterogeneous rows.
private let windBarbData: [[Any]] = {
    guard let rows = windBarbParsed["data"] as? [[String: Any]] else { return [] }
    return rows.map { row in
        [row["time"] ?? "", row["windSpeed"] ?? 0, row["R"] ?? "", row["waveHeight"] ?? 0]
    }
}()

// forecast.map(entry => [entry.localDate, 0, weatherIcons[entry.skyIcon], entry.minTemp, entry.maxTemp]).
private let windBarbWeatherData: [[Any]] = {
    let icons: [String: String] = [
        "Showers": windBarbShowersURI,
        "Sunny": windBarbSunnyURI,
        "Cloudy": windBarbCloudyURI
    ]
    guard let rows = windBarbParsed["forecast"] as? [[String: Any]] else { return [] }
    return rows.map { row in
        [row["localDate"] ?? "", 0, icons[row["skyIcon"] as? String ?? ""] ?? "",
         row["minTemp"] ?? 0, row["maxTemp"] ?? 0]
    }
}()

// upstream: directionMap[name] = Math.PI/8 * index over the 16 compass names; arrowSize/weatherIconSize.
private let windBarbDirectionMap: [String: Double] = {
    let names = ["W", "WSW", "SW", "SSW", "S", "SSE", "SE", "ESE", "E", "ENE", "NE", "NNE", "N", "NNW", "NW", "WNW"]
    var m: [String: Double] = [:]
    for (index, name) in names.enumerated() { m[name] = Double.pi / 8 * Double(index) }
    return m
}()
private let windBarbArrowSize = 18.0
private let windBarbWeatherIconSize = 45.0

private func windBarbNum(_ v: Any?) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    return .nan
}
private func windBarbStr(_ v: Any?) -> String { if let s = v as? String { return s }; return "\(v ?? "")" }
// JS number stringification (whole → no trailing .0), for the "min - max°" label.
private func windBarbTemp(_ v: Any?) -> String {
    let n = windBarbNum(v)
    if n.isNaN { return "" }
    return n == n.rounded() ? String(Int(n)) : String(n)
}

// Match the zh-CN time-axis labels used by the official web example: ordinary
// day ticks are numeric, while the first tick of a month is rendered as “7月”.
private let windBarbXAxisLabelFormatter: AxisLabelTimeFormatter = { value, _, _ in
    let date = Date(timeIntervalSince1970: value / 1000.0)
    let components = Calendar.current.dateComponents([.day, .month], from: date)
    guard let day = components.day, let month = components.month else { return "" }
    return day == 1 ? "\(month)月" : "\(day)"
}

// upstream renderArrow: a rotated wind-barb arrow `path` at each [time, windSpeed] point, rotation from
//   directionMap[R] (dims: time=0, windSpeed=1, R=2).
private let windBarbArrowRenderItem: CustomSeriesRenderItem = { _, api in
    let point = api.coord([windBarbNum(api.value(0.0, nil)), windBarbNum(api.value(1.0, nil))], nil)
    guard point.count >= 2 else { return nil }
    let rotation = windBarbDirectionMap[windBarbStr(api.value(2.0, nil))] ?? 0
    return [
        "type": "path",
        "shape": [
            "pathData": "M31 16l-15-15v9h-26v12h26v9z",
            "x": -windBarbArrowSize / 2, "y": -windBarbArrowSize / 2,
            "width": windBarbArrowSize, "height": windBarbArrowSize
        ] as [String: Any],
        "rotation": rotation,
        "position": point,
        "style": api.style(["stroke": "#555", "lineWidth": 1.0], nil)
    ] as [String: Any]
}

// upstream renderWeather: a group of {weather-icon image + "min - max°" text} per forecast day, centred on
//   the day's noon (dims: time=0, weatherIcon=2, minTemp=3, maxTemp=4).
private let windBarbWeatherRenderItem: CustomSeriesRenderItem = { _, api in
    let point = api.coord([windBarbNum(api.value(0.0, nil)) + (3600 * 24 * 1000) / 2, 0.0], nil)
    guard point.count >= 2 else { return nil }
    return [
        "type": "group",
        "children": [
            [
                "type": "image",
                "style": [
                    "image": api.value(2.0, nil) as Any,
                    "x": -windBarbWeatherIconSize / 2, "y": -windBarbWeatherIconSize / 2,
                    "width": windBarbWeatherIconSize, "height": windBarbWeatherIconSize
                ] as [String: Any],
                "position": [point[0], 110.0]
            ] as [String: Any],
            [
                "type": "text",
                "style": [
                    "text": "\(windBarbTemp(api.value(3.0, nil))) - \(windBarbTemp(api.value(4.0, nil)))°",
                    "textFont": api.font(["fontSize": 14.0]),
                    "align": "center", "verticalAlign": "bottom"
                ] as [String: Any],
                "position": [point[0], 80.0]
            ] as [String: Any]
        ]
    ] as [String: Any]
}

extension EChartsDemoRegistry {
    static let official_wind_barb = EChartsDemo(
        name: "official-wind-barb", category: "custom",
        summary: "风向图 — Wind Barb",
        width: 720, height: 460,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
const rawData = \#(windBarbRawJSON);

const weatherIcons = {
  Showers: '\#(windBarbShowersURI)',
  Sunny: '\#(windBarbSunnyURI)',
  Cloudy: '\#(windBarbCloudyURI)'
};

const directionMap = {};

// prettier-ignore
['W', 'WSW', 'SW', 'SSW', 'S', 'SSE', 'SE', 'ESE', 'E', 'ENE', 'NE', 'NNE', 'N', 'NNW', 'NW', 'WNW'].forEach(
  function (name, index) {
      directionMap[name] = Math.PI / 8 * index;
  }
);

const data = rawData.data.map(function (entry) {
  return [entry.time, entry.windSpeed, entry.R, entry.waveHeight];
});
const weatherData = rawData.forecast.map(function (entry) {
  return [
    entry.localDate,
    0,
    weatherIcons[entry.skyIcon],
    entry.minTemp,
    entry.maxTemp
  ];
});

const dims = {
  time: 0,
  windSpeed: 1,
  R: 2,
  waveHeight: 3,
  weatherIcon: 2,
  minTemp: 3,
  maxTemp: 4
};
const arrowSize = 18;
const weatherIconSize = 45;

const renderArrow = function (param, api) {
  const point = api.coord([
    api.value(dims.time),
    api.value(dims.windSpeed)
  ]);

  return {
    type: 'path',
    shape: {
      pathData: 'M31 16l-15-15v9h-26v12h26v9z',
      x: -arrowSize / 2,
      y: -arrowSize / 2,
      width: arrowSize,
      height: arrowSize
    },
    rotation: directionMap[api.value(dims.R)],
    position: point,
    style: api.style({
      stroke: '#555',
      lineWidth: 1
    })
  };
};

const renderWeather = function (param, api) {
  const point = api.coord([
    api.value(dims.time) + (3600 * 24 * 1000) / 2,
    0
  ]);

  return {
    type: 'group',
    children: [
      {
        type: 'image',
        style: {
          image: api.value(dims.weatherIcon),
          x: -weatherIconSize / 2,
          y: -weatherIconSize / 2,
          width: weatherIconSize,
          height: weatherIconSize
        },
        position: [point[0], 110]
      },
      {
        type: 'text',
        style: {
          text:
            api.value(dims.minTemp) + ' - ' + api.value(dims.maxTemp) + '°',
          textFont: api.font({ fontSize: 14 }),
          textAlign: 'center',
          textVerticalAlign: 'bottom'
        },
        position: [point[0], 80]
      }
    ]
  };
};

option = {
  title: {
    text: '天气 风向 风速 海浪 预报',
    subtext: '示例数据源于 www.seabreeze.com.au',
    left: 'center'
  },
  tooltip: {
    trigger: 'axis',
    formatter: function (params) {
      return [
        echarts.format.formatTime(
          'yyyy-MM-dd',
          params[0].value[dims.time]
        ) +
          ' ' +
          echarts.format.formatTime('hh:mm', params[0].value[dims.time]),
        '风速：' + params[0].value[dims.windSpeed],
        '风向：' + params[0].value[dims.R],
        '浪高：' + params[0].value[dims.waveHeight]
      ].join('<br>');
    }
  },
  grid: {
    top: 160,
    bottom: 125
  },
  xAxis: {
    type: 'time',
    maxInterval: 3600 * 1000 * 24,
    splitLine: {
      lineStyle: {
        color: '#ddd'
      }
    }
  },
  yAxis: [
    {
      name: '风速（节）',
      nameLocation: 'middle',
      nameGap: 35,
      axisLine: {
        lineStyle: {
          color: '#666'
        }
      },
      splitLine: {
        lineStyle: {
          color: '#ddd'
        }
      }
    },
    {
      name: '浪高（米）',
      nameLocation: 'middle',
      nameGap: 35,
      max: 6,
      axisLine: {
        lineStyle: {
          color: '#015DD5'
        }
      },
      splitLine: { show: false }
    },
    {
      axisLine: { show: false },
      axisTick: { show: false },
      axisLabel: { show: false },
      splitLine: { show: false }
    }
  ],
  visualMap: {
    type: 'piecewise',
    // show: false,
    orient: 'horizontal',
    left: 'center',
    bottom: 10,
    pieces: [
      {
        gte: 17,
        color: '#18BF12',
        label: '大风（>=17节）'
      },
      {
        gte: 11,
        lt: 17,
        color: '#f4e9a3',
        label: '中风（11  ~ 17 节）'
      },
      {
        lt: 11,
        color: '#D33C3E',
        label: '微风（小于 11 节）'
      }
    ],
    seriesIndex: 1,
    dimension: 1
  },
  dataZoom: [
    {
      type: 'inside',
      xAxisIndex: 0,
      minSpan: 5
    },
    {
      type: 'slider',
      xAxisIndex: 0,
      minSpan: 5,
      bottom: 50
    }
  ],
  series: [
    {
      type: 'line',
      yAxisIndex: 1,
      showSymbol: false,
      emphasis: {
        scale: false
      },
      symbolSize: 10,
      areaStyle: {
        color: {
          type: 'linear',
          x: 0,
          y: 0,
          x2: 0,
          y2: 1,
          global: false,
          colorStops: [
            {
              offset: 0,
              color: 'rgba(88,160,253,1)'
            },
            {
              offset: 0.5,
              color: 'rgba(88,160,253,0.7)'
            },
            {
              offset: 1,
              color: 'rgba(88,160,253,0)'
            }
          ]
        }
      },
      lineStyle: {
        color: 'rgba(88,160,253,1)'
      },
      itemStyle: {
        color: 'rgba(88,160,253,1)'
      },
      encode: {
        x: dims.time,
        y: dims.waveHeight
      },
      data: data,
      z: 2
    },
    {
      type: 'custom',
      renderItem: renderArrow,
      encode: {
        x: dims.time,
        y: dims.windSpeed
      },
      data: data,
      z: 10
    },
    {
      type: 'line',
      symbol: 'none',
      encode: {
        x: dims.time,
        y: dims.windSpeed
      },
      lineStyle: {
        color: '#aaa',
        type: 'dotted'
      },
      data: data,
      z: 1
    },
    {
      type: 'custom',
      renderItem: renderWeather,
      data: weatherData,
      tooltip: {
        trigger: 'item',
        formatter: function (param) {
          return (
            param.value[dims.time] +
            ': ' +
            param.value[dims.minTemp] +
            ' - ' +
            param.value[dims.maxTemp] +
            '°'
          );
        }
      },
      yAxisIndex: 2,
      z: 11
    }
  ]
};

myChart.setOption(option);
"""#,
        option: [
            "title": [
                "text": "天气 风向 风速 海浪 预报",
                "subtext": "示例数据源于 www.seabreeze.com.au",
                "left": "center"
            ] as [String: Any],
            // tooltip.formatter omitted — JS closure joined formatTime(date)+formatTime(time),
            //            wind speed, wind direction (R) and wave height per hovered row.
            "tooltip": [
                "trigger": "axis"
            ] as [String: Any],
            "grid": [
                "top": 160.0,
                "bottom": 125.0
            ] as [String: Any],
            "xAxis": [
                "type": "time",
                "maxInterval": 3600.0 * 1000.0 * 24.0,
                "axisLabel": [
                    "formatter": windBarbXAxisLabelFormatter as AxisLabelTimeFormatter
                ] as [String: Any],
                "splitLine": ["lineStyle": ["color": "#ddd"] as [String: Any]] as [String: Any]
            ] as [String: Any],
            "yAxis": [
                [
                    "name": "风速（节）",
                    "nameLocation": "middle",
                    "nameGap": 35.0,
                    "axisLine": ["lineStyle": ["color": "#666"] as [String: Any]] as [String: Any],
                    "splitLine": ["lineStyle": ["color": "#ddd"] as [String: Any]] as [String: Any]
                ] as [String: Any],
                [
                    "name": "浪高（米）",
                    "nameLocation": "middle",
                    "nameGap": 35.0,
                    "max": 6.0,
                    "axisLine": ["lineStyle": ["color": "#015DD5"] as [String: Any]] as [String: Any],
                    "splitLine": ["show": false] as [String: Any]
                ] as [String: Any],
                [
                    "axisLine": ["show": false] as [String: Any],
                    "axisTick": ["show": false] as [String: Any],
                    "axisLabel": ["show": false] as [String: Any],
                    "splitLine": ["show": false] as [String: Any]
                ] as [String: Any]
            ],
            "visualMap": [
                "type": "piecewise",
                "orient": "horizontal",
                "left": "center",
                "bottom": 10.0,
                "pieces": [
                    ["gte": 17.0, "color": "#18BF12", "label": "大风（>=17节）"] as [String: Any],
                    ["gte": 11.0, "lt": 17.0, "color": "#f4e9a3", "label": "中风（11  ~ 17 节）"] as [String: Any],
                    ["lt": 11.0, "color": "#D33C3E", "label": "微风（小于 11 节）"] as [String: Any]
                ],
                "seriesIndex": 1.0,
                "dimension": 1.0
            ] as [String: Any],
            "dataZoom": [
                ["type": "inside", "xAxisIndex": 0.0, "minSpan": 5.0] as [String: Any],
                ["type": "slider", "xAxisIndex": 0.0, "minSpan": 5.0, "bottom": 50.0] as [String: Any]
            ],
            "series": [
                [
                    "type": "line",
                    "yAxisIndex": 1.0,
                    "showSymbol": false,
                    "emphasis": ["scale": false] as [String: Any],
                    "symbolSize": 10.0,
                    "areaStyle": [
                        "color": [
                            "type": "linear",
                            "x": 0.0, "y": 0.0, "x2": 0.0, "y2": 1.0,
                            "global": false,
                            "colorStops": [
                                ["offset": 0.0, "color": "rgba(88,160,253,1)"] as [String: Any],
                                ["offset": 0.5, "color": "rgba(88,160,253,0.7)"] as [String: Any],
                                ["offset": 1.0, "color": "rgba(88,160,253,0)"] as [String: Any]
                            ]
                        ] as [String: Any]
                    ] as [String: Any],
                    "lineStyle": ["color": "rgba(88,160,253,1)"] as [String: Any],
                    "itemStyle": ["color": "rgba(88,160,253,1)"] as [String: Any],
                    "encode": ["x": 0.0, "y": 3.0] as [String: Any],
                    "data": windBarbData as [Any],
                    "z": 2.0
                ] as [String: Any],
                [
                    "type": "custom",
                    // renderItem ported (windBarbArrowRenderItem): a rotated wind-barb arrow path per point,
                    //   rotation = directionMap[R].
                    "renderItem": windBarbArrowRenderItem,
                    "encode": ["x": 0.0, "y": 1.0] as [String: Any],
                    "data": windBarbData as [Any],
                    "z": 10.0
                ] as [String: Any],
                [
                    "type": "line",
                    "symbol": "none",
                    "encode": ["x": 0.0, "y": 1.0] as [String: Any],
                    "lineStyle": ["color": "#aaa", "type": "dotted"] as [String: Any],
                    "data": windBarbData as [Any],
                    "z": 1.0
                ] as [String: Any],
                [
                    "type": "custom",
                    // renderItem ported (windBarbWeatherRenderItem): a group of {weather-icon image +
                    //   "min - max°" text} per forecast day. (tooltip.formatter still omitted — JS closure.)
                    "renderItem": windBarbWeatherRenderItem,
                    "data": windBarbWeatherData as [Any],
                    "tooltip": ["trigger": "item"] as [String: Any],
                    "yAxisIndex": 2.0,
                    "z": 11.0
                ] as [String: Any]
            ]
        ])
}
