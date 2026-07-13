// official-bar-race-country — replica of https://echarts.apache.org/examples/zh/editor.html?c=bar-race-country
// title: Bar Race / titleCN: 动态排序柱状图 - 人均收入
// A `realtimeSort` bar chart over a `dataset`: per-capita income of 19 countries, one decade per frame,
// bars re-ordered as the years advance. Flag emoji come from the yAxis label formatter; the big faded
// year sits in a `graphic` text element.
//
// DEVIATIONS from the official source:
//   * Data inlined. Upstream `$.when($.getJSON(CDN_PATH + 'emoji-flags@1.3.0/data.json'),
//     $.getJSON(ROOT_PATH + '/data/asset/data/life-expectancy-table.json')).done(...)` — the page has no
//     network, so the callback body is kept verbatim and both fetches are replaced by literals:
//       - the life-expectancy table is read from assets/data/life-expectancy-table.json (via
//         Upstream.repoRoot) and spliced into webOptionJS as its raw JSON text;
//       - `flags` is the emoji-flags data TRIMMED to the 19 countries the table contains (all 19 are
//         present, so `getFlag()` resolves exactly as it does upstream — the other 232 entries are dead).
//   * Animation reduced to its first frame. Upstream schedules `setTimeout(updateYear(years[i+1]), ...)`
//     every 2s from `startIndex = 10` and re-`setOption`s to race the bars through 1890→2019. The gallery
//     renders ONE static frame with animation off, so only the INITIAL state is ported: `startYear =
//     years[10]` = 1890 (upstream's `years[0]` is the header row's literal 'Year' string, hence the
//     off-by-one against the numeric decades). The `updateYear` loop and `myChart.setOption` are dropped.
//   * Native pane: the three JS closures cannot cross into the Swift option (see PORT-NOTEs) — the bars
//     lose their per-country flag colours, the y-axis labels lose their flag emoji, and the x-axis labels
//     lose their round-to-integer formatter. Everything else (dataset, encode, realtimeSort, graphic year)
//     is ported.
import Foundation

// ---------------------------------------------------------------------------
// assets/data/life-expectancy-table.json — [Income, Life Expectancy, Population, Country, Year] rows,
// header first. Read ONCE from the repo (the same #filePath-relative read WebPage.swift uses for the
// echarts dist); a parse failure degrades to an empty table (blank pane rather than a crash).
// ---------------------------------------------------------------------------
private let barRaceCountryTableURL = Upstream.repoRoot
    .appendingPathComponent("assets/data/life-expectancy-table.json")

/// Raw JSON text, spliced verbatim into webOptionJS in place of the `$.getJSON` result.
private let barRaceCountryTableJSON: String =
    (try? String(contentsOf: barRaceCountryTableURL, encoding: .utf8)) ?? "[]"

/// Data rows only (upstream's `data.slice(1)` — the header row dropped).
private let barRaceCountryRows: [[Any]] = {
    guard let data = try? Data(contentsOf: barRaceCountryTableURL),
          let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[Any]] else { return [] }
    return Array(rows.dropFirst())
}()

/// The distinct decades, in first-seen order. NOTE the off-by-one against upstream: its `years` array is
/// built from the table INCLUDING the header, so `years[0] === 'Year'` and `years[10]` is the 10th decade,
/// i.e. index 9 here.
private let barRaceCountryYears: [Double] = {
    var seen: [Double] = []
    for row in barRaceCountryRows {
        guard row.count > 4, let year = (row[4] as? NSNumber)?.doubleValue else { continue }
        if seen.last != year { seen.append(year) }
    }
    return seen
}()

/// `startYear = years[startIndex]`, startIndex = 10 → 1890.
private let barRaceCountryStartYear: Double = barRaceCountryYears.count > 9 ? barRaceCountryYears[9] : 1890
private let barRaceCountryStartYearText = String(Int(barRaceCountryStartYear))

/// `dataset.source` — the 19 country rows of the start year (the only frame we render).
private let barRaceCountryStartRows: [[Any]] = barRaceCountryRows.filter { row in
    row.count > 4 && (row[4] as? NSNumber)?.doubleValue == barRaceCountryStartYear
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

// emoji-flags@1.3.0/data.json, trimmed to the countries this table contains.
const flags = [
  { name: 'Australia', emoji: '🇦🇺' },
  { name: 'Canada', emoji: '🇨🇦' },
  { name: 'China', emoji: '🇨🇳' },
  { name: 'Cuba', emoji: '🇨🇺' },
  { name: 'Germany', emoji: '🇩🇪' },
  { name: 'Finland', emoji: '🇫🇮' },
  { name: 'France', emoji: '🇫🇷' },
  { name: 'United Kingdom', emoji: '🇬🇧' },
  { name: 'India', emoji: '🇮🇳' },
  { name: 'Iceland', emoji: '🇮🇸' },
  { name: 'Japan', emoji: '🇯🇵' },
  { name: 'North Korea', emoji: '🇰🇵' },
  { name: 'South Korea', emoji: '🇰🇷' },
  { name: 'Norway', emoji: '🇳🇴' },
  { name: 'New Zealand', emoji: '🇳🇿' },
  { name: 'Poland', emoji: '🇵🇱' },
  { name: 'Russia', emoji: '🇷🇺' },
  { name: 'Turkey', emoji: '🇹🇷' },
  { name: 'United States', emoji: '🇺🇸' }
];

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
    source: data.slice(1).filter(function (d) {
      return d[4] === startYear;
    })
  },
  yAxis: {
    type: 'category',
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
"""#,
        option: [
            "grid": [
                "top": 10.0,
                "bottom": 30.0,
                "left": 150.0,
                "right": 80.0
            ] as [String: Any],
            "xAxis": [
                "max": "dataMax"
                // PORT-NOTE: xAxis.axisLabel.formatter omitted — JS closure `function (n) { return
                // Math.round(n) + ''; }`, i.e. the income tick labels rendered as rounded integers.
            ] as [String: Any],
            "dataset": [
                "source": barRaceCountryStartRows
            ] as [String: Any],
            "yAxis": [
                "type": "category",
                "inverse": true,
                "max": 10.0,
                "axisLabel": [
                    "show": true,
                    "fontSize": 14.0,
                    // PORT-NOTE: yAxis.axisLabel.formatter omitted — JS closure `function (value) { return
                    // value + '{flag|' + getFlag(value) + '}'; }`, which appended the country's flag emoji
                    // as a rich-text `{flag|…}` tag. Without it the `rich.flag` style below is never hit,
                    // but it is kept so the option stays faithful.
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
            "series": [
                [
                    "realtimeSort": true,
                    "seriesLayoutBy": "column",
                    "type": "bar",
                    // PORT-NOTE: series[0].itemStyle.color omitted — JS closure `function (param) { return
                    // countryColors[param.value[3]] || '#5470c6'; }`, which coloured each bar by its
                    // country's flag colour (dim 3 = Country). Native bars fall back to the palette.
                    "encode": [
                        "x": 0.0,   // `dimension`
                        "y": 3.0
                    ] as [String: Any],
                    "label": [
                        "show": true,
                        "precision": 1.0,
                        "position": "right",
                        "valueAnimation": true,
                        "fontFamily": "monospace"
                    ] as [String: Any]
                ] as [String: Any]
            ],
            // Disable init animation.
            "animationDuration": 0.0,
            "animationDurationUpdate": 2000.0,   // `updateFrequency`
            "animationEasing": "linear",
            "animationEasingUpdate": "linear",
            "graphic": [
                "elements": [
                    [
                        "type": "text",
                        "right": 160.0,
                        "bottom": 60.0,
                        "style": [
                            "text": barRaceCountryStartYearText,
                            "font": "bolder 80px monospace",
                            "fill": "rgba(100, 100, 100, 0.25)"
                        ] as [String: Any],
                        "z": 100.0
                    ] as [String: Any]
                ]
            ] as [String: Any]
        ])
}
