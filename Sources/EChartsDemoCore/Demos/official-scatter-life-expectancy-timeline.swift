// official-scatter-life-expectancy-timeline — replica of
// https://echarts.apache.org/examples/zh/editor.html?c=scatter-life-expectancy-timeline
// title: Life Expectancy and GDP / titleCN: 各国人均寿命与GDP关系演变
// A Gapminder-style bubble scatter over a `{ baseOption, options: [...] }` timeline (81 frames,
// 1800…2015): per-capita income on a LOG x-axis, life expectancy on y, population as the bubble area,
// country as a categorical visualMap colour. The giant year (title[0]) sits behind the plot.
//
// DEVIATIONS from the official source:
//   - data: the official example fetches `ROOT_PATH + '/data/asset/data/life-expectancy.json'` via
//     `$.get`. The page has no network, so the SAME asset is vendored at assets/data/life-expectancy.json
//     and read at demo time through Upstream.repoRoot (the #filePath-relative repo read WebPage.swift
//     uses for the echarts dist). The web pane gets the raw JSON text spliced in as `var data = {...}`;
//     the callback body below is otherwise verbatim. `myChart.showLoading()/hideLoading()/setOption()`
//     are dropped (the harness owns init + setOption).
//   - timeline.autoPlay: the official option auto-advances every 1000ms. The gallery renders ONE static
//     frame, so BOTH panes pin the playhead to its initial index (1800) — the JS literal is verbatim and
//     `autoPlay` is switched off in the DEVIATION block at the bottom of webOptionJS.
//   - animation: WebPage.swift's blanket `option.animation = false` is DROPPED by echarts when the option
//     carries a `baseOption` (only baseOption/options/timeline/media are read off the root), so the web
//     pane would otherwise snapshot a half-grown scatter. Turned off inside `baseOption` instead — the
//     harness's intent, restored, not a change to the chart.
//   - native bubble size: `symbolSize` is a JS closure (`sizeFunction(val[2])`) and cannot cross into the
//     Swift option, so the native pane draws every point at the default symbol size instead of scaling it
//     by population. Expect uniformly-sized dots on the left, population-sized bubbles on the right.
//     Same for `tooltip.formatter` (see the PORT-NOTEs).
//   - native title/series text: JS pushes the raw NUMBER `data.timeline[n]` into `title.text` and
//     `series.name`; the Swift option carries its string form ("1800"), which is what JS renders anyway.
import Foundation

// The vendored asset (19 countries × 81 years; each row is [income, lifeExpectancy, population, country,
// year]). Read ONCE from the repo; a read/parse failure degrades to an empty dataset (blank pane, no crash).
private let lifeExpectancyJSONURL = Upstream.repoRoot.appendingPathComponent("assets/data/life-expectancy.json")

// Raw JSON text, spliced into the web pane in place of the `$.get` fetch. The fallback keeps the page
// syntactically valid (a parse error in the option script would blank the whole reference pane).
private let lifeExpectancyJSONText: String = {
    (try? String(contentsOf: lifeExpectancyJSONURL, encoding: .utf8))
        ?? #"{"counties":[],"timeline":[0],"series":[[]]}"#
}()

// The same asset, parsed for the native pane. JSONSerialization hands back NSNumber/NSString; normalise to
// Double/String so the option bag holds Swift natives.
private struct LifeExpectancyDataset {
    let counties: [String]        // 19 country names — the visualMap's categories
    let timeline: [Double]        // 81 years, 1800…2015
    let series: [[[Any]]]         // per year: 19 rows of [income, life, population, country, year]
}

private let lifeExpectancyDataset: LifeExpectancyDataset = {
    guard let data = try? Data(contentsOf: lifeExpectancyJSONURL),
          let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let counties = obj["counties"] as? [String],
          let timeline = obj["timeline"] as? [NSNumber],
          let series = obj["series"] as? [Any] else {
        return LifeExpectancyDataset(counties: [], timeline: [], series: [])
    }
    // Cast stepwise (rather than one deep `as? [[[Any]]]` bridge) so a single odd row cannot silently
    // collapse the whole dataset to empty.
    let rows: [[[Any]]] = series.map { frame in
        (frame as? [Any] ?? []).map { row in
            (row as? [Any] ?? []).map { cell -> Any in
                if let n = cell as? NSNumber { return n.doubleValue }
                if let s = cell as? String { return s }
                return NSNull()
            }
        }
    }
    return LifeExpectancyDataset(counties: counties,
                                 timeline: timeline.map { $0.doubleValue },
                                 series: rows)
}()

// `data.timeline[n] + ''` — the year as the big background title / the series name.
private let lifeExpectancyYearLabels: [String] = lifeExpectancyDataset.timeline.map { String(Int($0)) }

// `var itemStyle = { opacity: 0.8 };` — shared by baseOption.series[0] and every options[n].series.
private let lifeExpectancyItemStyle: [String: Any] = ["opacity": 0.8]

// visualMap.inRange.color — the IIFE's `colors.concat(colors)` (10 hues, doubled to cover 19 countries).
private let lifeExpectancyColors: [String] = {
    let colors = ["#51689b", "#ce5c5c", "#fbc357", "#8fbf8f", "#659d84",
                  "#fb8e6a", "#c77288", "#786090", "#91c4c5", "#6890ba"]
    return colors + colors
}()

// The `for (var n = 0; ...)` loop's output: one option snapshot per timeline tick.
private let lifeExpectancyTimelineOptions: [[String: Any]] = lifeExpectancyDataset.series.indices.map { n in
    [
        "title": ["show": true, "text": lifeExpectancyYearLabels[n]] as [String: Any],
        "series": [
            "name": lifeExpectancyYearLabels[n],
            "type": "scatter",
            "itemStyle": lifeExpectancyItemStyle,
            "data": lifeExpectancyDataset.series[n] as [Any]
            // PORT-NOTE: series.symbolSize omitted — JS closure `val => sizeFunction(val[2])`, where
            //   sizeFunction(x) = (Math.sqrt(x / 5e8) + 0.1) * 80, i.e. each bubble's radius grows with
            //   the square root of the country's population (dimension 2).
        ] as [String: Any]
    ] as [String: Any]
}

private let lifeExpectancyBaseOption: [String: Any] = [
    "timeline": [
        "axisType": "category",
        "orient": "vertical",
        // DEVIATION: official `autoPlay: true` — one static frame, so the playhead stays at index 0 (1800).
        "autoPlay": false,
        "inverse": true,
        "playInterval": 1000.0,
        "left": NSNull(),
        "right": 0.0,
        "top": 20.0,
        "bottom": 20.0,
        "width": 55.0,
        "height": NSNull(),
        "symbol": "none",
        "checkpointStyle": ["borderWidth": 2.0] as [String: Any],
        "controlStyle": [
            "showNextBtn": false,
            "showPrevBtn": false
        ] as [String: Any],
        "data": lifeExpectancyDataset.timeline as [Any]
    ] as [String: Any],
    "title": [
        [
            // data.timeline[0] — the giant year behind the plot, replaced per tick by options[n].title.
            "text": lifeExpectancyYearLabels.first ?? "",
            "textAlign": "center",
            "left": "63%",
            "top": "55%",
            "textStyle": ["fontSize": 100.0] as [String: Any]
        ] as [String: Any],
        [
            "text": "各国人均寿命与GDP关系演变",
            "left": "center",
            "top": 10.0,
            "textStyle": [
                "fontWeight": "normal",
                "fontSize": 20.0
            ] as [String: Any]
        ] as [String: Any]
    ],
    "tooltip": [
        "padding": 5.0,
        "borderWidth": 1.0
        // PORT-NOTE: tooltip.formatter omitted — JS closure over the `schema` table; it renders the hovered
        //   row as 国家/人均寿命(岁)/人均收入(美元)/总人口, one `<br>`-separated line each, reading
        //   value[3]/value[1]/value[0]/value[2].
    ] as [String: Any],
    "grid": [
        "top": 100.0,
        "containLabel": true,
        "left": 30.0,
        "right": "110"      // verbatim: the official source really does quote this one
    ] as [String: Any],
    "xAxis": [
        "type": "log",
        "name": "人均收入",
        "max": 100000.0,
        "min": 300.0,
        "nameGap": 25.0,
        "nameLocation": "middle",
        "nameTextStyle": ["fontSize": 18.0] as [String: Any],
        "splitLine": ["show": false] as [String: Any],
        "axisLabel": ["formatter": "{value} $"] as [String: Any]
    ] as [String: Any],
    "yAxis": [
        "type": "value",
        "name": "平均寿命",
        "max": 100.0,
        "nameTextStyle": ["fontSize": 18.0] as [String: Any],
        "splitLine": ["show": false] as [String: Any],
        "axisLabel": ["formatter": "{value} 岁"] as [String: Any]
    ] as [String: Any],
    "visualMap": [
        [
            "show": false,
            "dimension": 3.0,
            "categories": lifeExpectancyDataset.counties,
            "inRange": ["color": lifeExpectancyColors] as [String: Any]
        ] as [String: Any]
    ],
    "series": [
        [
            "type": "scatter",
            "itemStyle": lifeExpectancyItemStyle,
            "data": (lifeExpectancyDataset.series.first ?? []) as [Any]
            // PORT-NOTE: series.symbolSize omitted — same `val => sizeFunction(val[2])` closure as above.
        ] as [String: Any]
    ],
    "animationDurationUpdate": 1000.0,
    "animationEasingUpdate": "quinticInOut",
    // DEVIATION: see the header — the harness's `animation = false` cannot reach a baseOption.
    "animation": false
]

extension EChartsDemoRegistry {
    static let official_scatter_life_expectancy_timeline = EChartsDemo(
        name: "official-scatter-life-expectancy-timeline", category: "scatter",
        summary: "各国人均寿命与GDP关系演变 — Life Expectancy and GDP",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
// DEVIATION (gallery, not upstream): `$.get(ROOT_PATH + '/data/asset/data/life-expectancy.json', ...)`
// cannot run — the page has no network. The vendored asset (assets/data/life-expectancy.json) is spliced
// in here and the fetch's callback BODY follows verbatim.
var data = \#(lifeExpectancyJSONText);

var itemStyle = {
  opacity: 0.8
};

var sizeFunction = function (x) {
  var y = Math.sqrt(x / 5e8) + 0.1;
  return y * 80;
};
// Schema:
var schema = [
  { name: 'Income', index: 0, text: '人均收入', unit: '美元' },
  { name: 'LifeExpectancy', index: 1, text: '人均寿命', unit: '岁' },
  { name: 'Population', index: 2, text: '总人口', unit: '' },
  { name: 'Country', index: 3, text: '国家', unit: '' }
];

option = {
  baseOption: {
    timeline: {
      axisType: 'category',
      orient: 'vertical',
      autoPlay: true,
      inverse: true,
      playInterval: 1000,
      left: null,
      right: 0,
      top: 20,
      bottom: 20,
      width: 55,
      height: null,
      symbol: 'none',
      checkpointStyle: {
        borderWidth: 2
      },
      controlStyle: {
        showNextBtn: false,
        showPrevBtn: false
      },
      data: []
    },
    title: [
      {
        text: data.timeline[0],
        textAlign: 'center',
        left: '63%',
        top: '55%',
        textStyle: {
          fontSize: 100
        }
      },
      {
        text: '各国人均寿命与GDP关系演变',
        left: 'center',
        top: 10,
        textStyle: {
          fontWeight: 'normal',
          fontSize: 20
        }
      }
    ],
    tooltip: {
      padding: 5,
      borderWidth: 1,
      formatter: function (obj) {
        var value = obj.value;
        // prettier-ignore
        return schema[3].text + '：' + value[3] + '<br>'
          + schema[1].text + '：' + value[1] + schema[1].unit + '<br>'
          + schema[0].text + '：' + value[0] + schema[0].unit + '<br>'
          + schema[2].text + '：' + value[2] + '<br>';
      }
    },
    grid: {
      top: 100,
      containLabel: true,
      left: 30,
      right: '110'
    },
    xAxis: {
      type: 'log',
      name: '人均收入',
      max: 100000,
      min: 300,
      nameGap: 25,
      nameLocation: 'middle',
      nameTextStyle: {
        fontSize: 18
      },
      splitLine: {
        show: false
      },
      axisLabel: {
        formatter: '{value} $'
      }
    },
    yAxis: {
      type: 'value',
      name: '平均寿命',
      max: 100,
      nameTextStyle: {
        fontSize: 18
      },
      splitLine: {
        show: false
      },
      axisLabel: {
        formatter: '{value} 岁'
      }
    },
    visualMap: [
      {
        show: false,
        dimension: 3,
        categories: data.counties,
        inRange: {
          color: (function () {
            // prettier-ignore
            var colors = ['#51689b', '#ce5c5c', '#fbc357', '#8fbf8f', '#659d84', '#fb8e6a', '#c77288', '#786090', '#91c4c5', '#6890ba'];
            return colors.concat(colors);
          })()
        }
      }
    ],
    series: [
      {
        type: 'scatter',
        itemStyle: itemStyle,
        data: data.series[0],
        symbolSize: function (val) {
          return sizeFunction(val[2]);
        }
      }
    ],
    animationDurationUpdate: 1000,
    animationEasingUpdate: 'quinticInOut'
  },
  options: []
};

for (var n = 0; n < data.timeline.length; n++) {
  option.baseOption.timeline.data.push(data.timeline[n]);
  option.options.push({
    title: {
      show: true,
      text: data.timeline[n] + ''
    },
    series: {
      name: data.timeline[n],
      type: 'scatter',
      itemStyle: itemStyle,
      data: data.series[n],
      symbolSize: function (val) {
        return sizeFunction(val[2]);
      }
    }
  });
}

// DEVIATION (gallery, not upstream): the option literal above is verbatim. These two lines keep the
// reference pane on a single deterministic frame — the timeline's first index (1800), unanimated — which
// is what the native pane renders. `option.animation = false` (injected by WebPage.swift) is ignored when
// a `baseOption` is present, hence setting it here.
option.baseOption.timeline.autoPlay = false;
option.baseOption.animation = false;
"""#,
        option: [
            "baseOption": lifeExpectancyBaseOption,
            "options": lifeExpectancyTimelineOptions
        ])
}
