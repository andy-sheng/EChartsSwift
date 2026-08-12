// official-bar-race-country — replica of https://echarts.apache.org/examples/zh/editor.html?c=bar-race-country
// title: Bar Race / titleCN: 动态排序柱状图 - 人均收入
// A `realtimeSort` bar chart over a `dataset`: per-capita income of 19 countries, one frame per year,
// the bars re-sorting as the years advance from 1890 to 2015. The country's flag emoji rides its y-axis
// label (a rich-text `{flag|…}` tag from the axisLabel formatter), each bar is painted its flag's colour
// (an itemStyle colour closure) and the big faded year sits in a `graphic` text element.
//
// THE RACE IS PORTED, on both panes. Upstream schedules a `setTimeout` ladder — 71 rungs, one every
// `updateFrequency` (2000ms), starting at delay ZERO — and each step re-points `option.series[0].data` at
// the next year's rows, rewrites the `graphic` year and re-`setOption`s (a MERGE). The web pane runs that
// ladder verbatim; the native pane replays it rung for rung through `drive` (see EChartsDemoChart).
//
// A NOTE FOR ANYONE DIFFING THE HEADLESS PNGs: they are one rung apart, and that is the harness, not the
// port. This example is driven by `setTimeout`, and the snapshot harness only neuters `setInterval`
// (echarts needs setTimeout internally) — so in the 0.4s the web snapshot waits, the ladder's FIRST rung,
// whose delay is 0, has already fired and the web PNG shows 1900. The native still-frame never calls
// `drive` at all (a PNG has no timeline), so it shows the initial option: 1890. Live, in the gallery,
// both panes run the same ladder and stay in step. Compare the LIVE panes, or expect the year to differ
// by exactly one step in the stills.
//
// DEVIATIONS from the official source:
//   - THE TWO FETCHES ARE INLINED. Upstream is a `$.when($.getJSON(CDN_PATH + 'emoji-flags@1.3.0/
//     data.json'), $.getJSON(ROOT_PATH + '/data/asset/data/life-expectancy-table.json')).done(...)`; the
//     page has no network, so the `.done` CALLBACK BODY is kept verbatim at the top level and both results
//     are spliced in as raw JSON text: `flags` = assets/data/emoji-flags.json (the npm package's data.json,
//     all 251 entries — NOT trimmed, so `getFlag` resolves exactly as upstream), `data` =
//     assets/data/life-expectancy-table.json (header row included, so the verbatim `data.slice(1)` and the
//     `years[0] === 'Year'` off-by-one below still hold). Both are read from the repo via `Upstream.repoRoot`
//     — the same #filePath-relative read WebPage.swift uses for the echarts dist; a parse failure degrades
//     to an empty table (blank pane rather than a crash).
//   - TypeScript-only syntax dropped, as a classic script cannot parse it: `Record<string, string>`, the
//     `interface Flag`, the `: string[]` / `: Flag[]` / `: number` / `: any` annotations, `param.value as
//     number[]`, the `myChart.setOption<echarts.EChartsOption>(...)` type arguments, and `export {};`.
//     `myChart.setOption(option)` and the whole `setTimeout` / `updateYear` timeline are KEPT.
//   - Native pane: the three JS closures ARE now carried as native Swift closures (the framework supports
//     them — see the closure definitions below): `series[0].itemStyle.color` (a `ColorCallback` painting
//     each bar its country's flag colour), `yAxis.axisLabel.formatter` (an `AxisLabelCategoryFormatter`
//     appending the country's flag emoji as a rich-text `{flag|…}` tag, hitting the `rich.flag` style),
//     and `xAxis.axisLabel.formatter` (an `AxisLabelValueFormatter` rounding the income ticks). realtimeSort
//     re-sorts the bars + y-axis labels each frame (BarView's `coordsys:aftercreate` sort hook). Everything
//     else — dataset, encode, valueAnimation label, graphic year, and the race itself — is ported.
//     KNOWN GAP: the rich `{flag|…}` emoji is over-measured by the native text layout (an emoji advance-width
//     limitation in the shared text subsystem), so a long country name is clipped a few chars on the left
//     where echarts.js fits it within `grid.left`. The flag + colour + re-sort are all correct.
//   - `graphic.elements[0].style.text` is the YEAR AS A STRING natively (upstream hands zrender the raw
//     number and lets it coerce; a Swift `TextStyleProps.text` is a String).
import Foundation
import EChartsKit

// ---------------------------------------------------------------------------
// The two upstream fetches, as repo assets.
// ---------------------------------------------------------------------------

/// `ROOT_PATH + '/data/asset/data/life-expectancy-table.json'` — [Income, Life Expectancy, Population,
/// Country, Year] rows, header row first.
private let barRaceCountryTableURL = Upstream.repoRoot
    .appendingPathComponent("assets/data/life-expectancy-table.json")
/// `CDN_PATH + 'emoji-flags@1.3.0/data.json'` — [{ code, emoji, unicode, name, title, dialCode }, …].
private let barRaceCountryFlagsURL = Upstream.repoRoot
    .appendingPathComponent("assets/data/emoji-flags.json")

/// Raw JSON text, spliced into webOptionJS in place of the `$.getJSON` results (`res1[0]` / `res0[0]`).
private let barRaceCountryTableJSON: String =
    (try? String(contentsOf: barRaceCountryTableURL, encoding: .utf8)) ?? "[]"
private let barRaceCountryFlagsJSON: String =
    (try? String(contentsOf: barRaceCountryFlagsURL, encoding: .utf8)) ?? "[]"

/// The table's DATA rows (upstream's `data.slice(1)` — the header dropped), numbers normalised to Double.
private let barRaceCountryRows: [[Any]] = {
    guard let data = try? Data(contentsOf: barRaceCountryTableURL),
          let raw = (try? JSONSerialization.jsonObject(with: data)) as? [[Any]] else { return [] }
    return raw.dropFirst().map { row in
        row.map { cell -> Any in (cell as? NSNumber).map { $0.doubleValue as Any } ?? cell }
    }
}()

/// The distinct years, in first-seen order: 1800, 1810, … 1890, 1900, … 2015 (81 of them).
/// NOTE the off-by-one against upstream: its `years` is built from the table INCLUDING the header, so
/// `years[0] === 'Year'` and its `startIndex = 10` lands on the 10th year — index 9 here.
private let barRaceCountryYears: [Double] = {
    var seen: [Double] = []
    for row in barRaceCountryRows {
        guard row.count > 4, let year = row[4] as? Double else { continue }
        if seen.last != year { seen.append(year) }
    }
    return seen
}()

private let barRaceCountryUpdateFrequency: Double = 2000   // ms, upstream `updateFrequency`
private let barRaceCountryDimension: Double = 0            // upstream `dimension`
private let barRaceCountryStartIndex = 9                   // upstream `startIndex = 10`, less the header
private let barRaceCountryStartYear: Double =
    barRaceCountryYears.indices.contains(barRaceCountryStartIndex)
        ? barRaceCountryYears[barRaceCountryStartIndex] : 1890

/// The 19 country rows of one year — upstream's `data.slice(1).filter(d => d[4] === year)`.
private func barRaceCountryRows(year: Double) -> [[Any]] {
    barRaceCountryRows.filter { $0.count > 4 && ($0[4] as? Double) == year }
}
/// `dataset.source` — the start year's rows, set once and never touched again (upstream's updates go to
/// `series[0].data`, which takes precedence over the dataset).
private let barRaceCountryStartRows: [[Any]] = barRaceCountryRows(year: barRaceCountryStartYear)
private let barRaceCountrySortedStartRows: [[Any]] = barRaceCountryStartRows.sorted {
    (($0.first as? Double) ?? 0) > (($1.first as? Double) ?? 0)
}
private let barRaceCountrySortedStartCategories: [String] = barRaceCountrySortedStartRows.compactMap {
    $0.count > 3 ? $0[3] as? String : nil
}

// ---------------------------------------------------------------------------
// The three JS closures the earlier port dropped, now native (the framework supports them):
//   - `series[0].itemStyle.color`  — a `(CallbackDataParams) -> ZRColor` callback (visual/style.swift
//     resolves `itemStyle.color` as a `ColorCallback` when `util.isFunction`).
//   - `yAxis.axisLabel.formatter`  — an `AxisLabelCategoryFormatter` (coord/axisHelper.swift invokes a
//     function formatter on a category axis).
//   - `xAxis.axisLabel.formatter`  — an `AxisLabelValueFormatter` (rounds the income ticks to integers).
// ---------------------------------------------------------------------------

/// `countryColors` — each country's flag colour, keyed by country name (dim 3). Ported verbatim from the
/// demo's own `webOptionJS` map below; the `itemStyle.color` closure reads it.
private let barRaceCountryColors: [String: String] = [
    "Australia": "#00008b",
    "Canada": "#f00",
    "China": "#ffde00",
    "Cuba": "#002a8f",
    "Finland": "#003580",
    "France": "#ed2939",
    "Germany": "#000",
    "Iceland": "#003897",
    "India": "#f93",
    "Japan": "#bc002d",
    "North Korea": "#024fa2",
    "South Korea": "#000",
    "New Zealand": "#00247d",
    "Norway": "#ef2b2d",
    "Poland": "#dc143c",
    "Russia": "#d52b1e",
    "Turkey": "#e30a17",
    "United Kingdom": "#00247d",
    "United States": "#b22234"
]

/// `getFlag`'s lookup table — country name → flag emoji, parsed from the inlined
/// `emoji-flags@1.3.0/data.json` (all 251 entries). Upstream: `flags.find(item => item.name === name).emoji`.
private let barRaceCountryFlagByName: [String: String] = {
    guard let data = try? Data(contentsOf: barRaceCountryFlagsURL),
          let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return [:] }
    var out: [String: String] = [:]
    for item in arr {
        if let name = item["name"] as? String, let emoji = item["emoji"] as? String {
            out[name] = emoji
        }
    }
    return out
}()

/// upstream `getFlag(countryName)` — `if (!countryName) return ''; return (flags.find(...) || {}).emoji;`
private func barRaceCountryGetFlag(_ countryName: String) -> String {
    if countryName.isEmpty { return "" }
    return barRaceCountryFlagByName[countryName] ?? ""
}

/// dim 3 (Country) off a `CallbackDataParams.value` — the raw dataset row `[Income, LifeExp, Pop,
/// Country, Year]`. Unwraps any boxed `Any?` cell so it stringifies as `China`, not `Optional("China")`.
private func barRaceCountryNameOf(_ value: Any) -> String {
    guard let row = value as? [Any], row.count > 3 else { return "" }
    let cell = row[3]
    let m = Mirror(reflecting: cell)
    if m.displayStyle == .optional {
        return m.children.first.map { "\($0.value)" } ?? ""
    }
    return "\(cell)"
}

/// `series[0].itemStyle.color` — upstream `function (param) { return countryColors[param.value[3]] ||
/// '#5470c6'; }`. Paints each bar its country's flag colour (dim 3 = Country).
private let barRaceCountryColorCallback: (CallbackDataParams) -> EChartsKit.ZRColor = { param in
    let country = barRaceCountryNameOf(param.value)
    return .color(barRaceCountryColors[country] ?? "#5470c6")
}

/// `yAxis.axisLabel.formatter` — upstream `function (value) { return value + '{flag|' + getFlag(value)
/// + '}'; }`. Appends the country's flag emoji as a rich-text `{flag|…}` tag (styled by `rich.flag`).
private let barRaceCountryFlagFormatter: AxisLabelCategoryFormatter = { rawValue, _, _ in
    let name = "\(rawValue)"
    return name + "{flag|" + barRaceCountryGetFlag(name) + "}"
}

/// `xAxis.axisLabel.formatter` — upstream `function (n) { return Math.round(n) + ''; }`. The income ticks
/// as rounded integers.
private let barRaceCountryXAxisFormatter: AxisLabelValueFormatter = { n, _, _ in
    return String(Int(n.rounded()))
}

/// The full option for one frame — the Swift twin of upstream's `option` object, whose `series[0].data`
/// and `graphic.elements[0].style.text` each `updateYear(year)` rewrites before re-`setOption`ing it.
/// `seriesData: nil` is the INITIAL option, which carries no series data at all (the `dataset` supplies it).
private func barRaceCountryOption(seriesData: [[Any]]?, year: Double) -> [String: Any] {
    var series: [String: Any] = [
        "realtimeSort": true,
        "seriesLayoutBy": "column",
        "type": "bar",
        // upstream: itemStyle.color = function (param) { return countryColors[param.value[3]] || '#5470c6'; }
        //   Now native — the visual/style stage resolves an `itemStyle.color` that `util.isFunction` as a
        //   `ColorCallback` and runs it per datum (dim 3 = Country; e.g. China '#ffde00', US '#b22234').
        "itemStyle": [
            "color": (barRaceCountryColorCallback as (CallbackDataParams) -> EChartsKit.ZRColor)
        ] as [String: Any],
        "encode": [
            "x": barRaceCountryDimension,
            "y": 3.0
        ] as [String: Any],
        "label": [
            "show": true,
            "precision": 1.0,
            "position": "right",
            "valueAnimation": true,
            "fontFamily": "monospace"
        ] as [String: Any]
    ]
    if let seriesData { series["data"] = seriesData }

    return [
        "grid": [
            "top": 10.0,
            "bottom": 30.0,
            "left": 150.0,
            "right": 80.0
        ] as [String: Any],
        "xAxis": [
            "max": "dataMax",
            // upstream: axisLabel.formatter = function (n) { return Math.round(n) + ''; }
            "axisLabel": [
                "formatter": (barRaceCountryXAxisFormatter as AxisLabelValueFormatter)
            ] as [String: Any]
        ] as [String: Any],
        "dataset": [
            "source": barRaceCountryStartRows
        ] as [String: Any],
        "yAxis": [
            "type": "category",
            "data": barRaceCountrySortedStartCategories,
            "inverse": true,
            "max": 10.0,
            "axisLabel": [
                "show": true,
                "fontSize": 14.0,
                // upstream: axisLabel.formatter = function (value) { return value + '{flag|' + getFlag(value) + '}'; }
                //   Now native — coord/axisHelper.swift invokes a function formatter on a category axis,
                //   so each label appends the country's flag emoji as a rich-text `{flag|…}` tag hitting
                //   the `rich.flag` style below.
                "formatter": (barRaceCountryFlagFormatter as AxisLabelCategoryFormatter),
                "rich": [
                    "flag": [
                        "fontSize": 25.0,
                        "padding": 5.0
                    ] as [String: Any]
                ] as [String: Any]
            ] as [String: Any],
            "animationDuration": 300.0,
            "animationDurationUpdate": 300.0
        ] as [String: Any],
        "series": [series],
        // Disable init animation.
        "animationDuration": 0.0,
        "animationDurationUpdate": barRaceCountryUpdateFrequency,
        "animationEasing": "linear",
        "animationEasingUpdate": "linear",
        "graphic": [
            "elements": [
                [
                    "type": "text",
                    "right": 160.0,
                    "bottom": 60.0,
                    "style": [
                        "text": String(Int(year)),   // upstream passes the raw number; Swift text is a String
                        "font": "bolder 80px monospace",
                        "fill": "rgba(100, 100, 100, 0.25)"
                    ] as [String: Any],
                    "z": 100.0
                ] as [String: Any]
            ]
        ] as [String: Any]
    ]
}

extension EChartsDemoRegistry {
    static let official_bar_race_country = EChartsDemo(
        name: "official-bar-race-country", category: "bar",
        summary: "动态排序柱状图 - 人均收入 — Bar Race",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
const updateFrequency = 2000;
const dimension = 0;

const countryColors = {
  Australia: '#00008b',
  Canada: '#f00',
  China: '#ffde00',
  Cuba: '#002a8f',
  Finland: '#003580',
  France: '#ed2939',
  Germany: '#000',
  Iceland: '#003897',
  India: '#f93',
  Japan: '#bc002d',
  'North Korea': '#024fa2',
  'South Korea': '#000',
  'New Zealand': '#00247d',
  Norway: '#ef2b2d',
  Poland: '#dc143c',
  Russia: '#d52b1e',
  Turkey: '#e30a17',
  'United Kingdom': '#00247d',
  'United States': '#b22234'
};

// DEVIATION: the two `$.getJSON` results, inlined (the page has no network). `flags` is
// emoji-flags@1.3.0/data.json verbatim (all 251 entries); `data` is /data/asset/data/
// life-expectancy-table.json verbatim (header row included, as `data.slice(1)` below expects).
// Everything from here down is the official source.
const flags = \#(barRaceCountryFlagsJSON);
const data = \#(barRaceCountryTableJSON);

const years = [];
for (let i = 0; i < data.length; ++i) {
  if (years.length === 0 || years[years.length - 1] !== data[i][4]) {
    years.push(data[i][4]);
  }
}

function getFlag(countryName) {
  if (!countryName) {
    return '';
  }
  return (
    flags.find(function (item) {
      return item.name === countryName;
    }) || {}
  ).emoji;
}
let startIndex = 10;
let startYear = years[startIndex];
const startSource = data.slice(1).filter(function (d) {
  return d[4] === startYear;
}).sort(function (a, b) { return b[0] - a[0]; });

option = {
  grid: {
    top: 10,
    bottom: 30,
    left: 150,
    right: 80
  },
  xAxis: {
    max: 'dataMax',
    axisLabel: {
      formatter: function (n) {
        return Math.round(n) + '';
      }
    }
  },
  dataset: {
    source: startSource
  },
  yAxis: {
    type: 'category',
    data: startSource.map(function (d) { return d[3]; }),
    inverse: true,
    max: 10,
    axisLabel: {
      show: true,
      fontSize: 14,
      formatter: function (value) {
        return value + '{flag|' + getFlag(value) + '}';
      },
      rich: {
        flag: {
          fontSize: 25,
          padding: 5
        }
      }
    },
    animationDuration: 300,
    animationDurationUpdate: 300
  },
  series: [
    {
      realtimeSort: true,
      seriesLayoutBy: 'column',
      type: 'bar',
      itemStyle: {
        color: function (param) {
          return countryColors[param.value[3]] || '#5470c6';
        }
      },
      encode: {
        x: dimension,
        y: 3
      },
      label: {
        show: true,
        precision: 1,
        position: 'right',
        valueAnimation: true,
        fontFamily: 'monospace'
      }
    }
  ],
  // Disable init animation.
  animationDuration: 0,
  animationDurationUpdate: updateFrequency,
  animationEasing: 'linear',
  animationEasingUpdate: 'linear',
  graphic: {
    elements: [
      {
        type: 'text',
        right: 160,
        bottom: 60,
        style: {
          text: startYear,
          font: 'bolder 80px monospace',
          fill: 'rgba(100, 100, 100, 0.25)'
        },
        z: 100
      }
    ]
  }
};

// console.log(option);
myChart.setOption(option);

if (!__snapshot) {
  for (let i = startIndex; i < years.length - 1; ++i) {
    (function (i) {
      setTimeout(function () {
        updateYear(years[i + 1]);
      }, (i - startIndex) * updateFrequency);
    })(i);
  }
}

function updateYear(year) {
  let source = data.slice(1).filter(function (d) {
    return d[4] === year;
  });
  option.series[0].data = source;
  option.graphic.elements[0].style.text = year;
  myChart.setOption(option);
}
"""#,
        // The native pane's half of the race — upstream's `setTimeout` ladder, step for step:
        //   for (let i = startIndex; i < years.length - 1; ++i)
        //     setTimeout(() => updateYear(years[i + 1]), (i - startIndex) * updateFrequency);
        // 71 steps, 1900 → 2015. NOTE the first rung's delay is ZERO — the race leaves the start year on
        // the very next tick, so this must be the ladder and NOT an `every(2)` interval (that would park
        // the native pane one full step behind the web pane for the whole run). `notMerge: false` is
        // upstream's plain `myChart.setOption(option)`: it re-sends the whole mutated option and merges.
        drive: { chart in
            let years = barRaceCountryYears
            guard years.count > barRaceCountryStartIndex + 1 else { return }
            for i in barRaceCountryStartIndex..<(years.count - 1) {
                let year = years[i + 1]
                let delay = Double(i - barRaceCountryStartIndex) * barRaceCountryUpdateFrequency / 1000
                chart.after(delay) {   // `updateYear(years[i + 1])`
                    chart.setOption(
                        barRaceCountryOption(seriesData: barRaceCountryRows(year: year), year: year),
                        notMerge: false)
                }
            }
        },
        option: barRaceCountryOption(seriesData: barRaceCountrySortedStartRows, year: barRaceCountryStartYear))
}
