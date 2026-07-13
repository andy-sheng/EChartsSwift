// official-bump-chart — replica of https://echarts.apache.org/examples/zh/editor.html?c=bump-chart
// title: Bump Chart (Ranking) / titleCN: 凹凸图
// Nine competitors' yearly rank (1..9) as smooth lines on an INVERSE value y-axis: big symbols
// (symbolSize 20), thick lines (width 4), `endLabel` naming each series at its right edge, and
// `emphasis.focus: 'series'` to dim the rest on hover.
//
// DEVIATIONS from the official source:
//   - DATA FROZEN. The example builds its rankings with a Math.random() Fisher-Yates `shuffle()`,
//     so every reload draws a different chart. Both panes here share ONE fixed draw
//     (`bumpChartRankings` / the `rankings` table in webOptionJS) — each year is still a permutation
//     of 1..9, and the series-building code is otherwise the example's, verbatim. Without this the
//     web and native panes would render different data and could not be diffed.
//   - `export {};` and the TS type annotations dropped (a bare export is a SyntaxError in the
//     reference pane's classic script).
// Everything else — title, tooltip, grid, toolbox, both axes, and every series key — is verbatim.
extension EChartsDemoRegistry {
    static let official_bump_chart = EChartsDemo(
        name: "official-bump-chart", category: "line",
        summary: "凹凸图 — Bump Chart (Ranking)",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
const names = [
  'Orange',
  'Tomato',
  'Apple',
  'Sakana',
  'Banana',
  'Iwashi',
  'Snappy Fish',
  'Lemon',
  'Pasta'
];

const years = ['2001', '2002', '2003', '2004', '2005', '2006'];

// DEVIATION: the official example shuffles `[1..names.length]` with Math.random() once per year.
// Frozen to one fixed draw (each year is still a permutation of 1..9) so both panes render the
// same chart and stay diffable.
const rankings = {
  Orange: [3, 1, 2, 5, 4, 6],
  Tomato: [1, 4, 3, 2, 6, 5],
  Apple: [5, 2, 6, 4, 1, 3],
  Sakana: [9, 8, 7, 6, 5, 4],
  Banana: [2, 5, 1, 3, 7, 8],
  Iwashi: [7, 6, 9, 8, 3, 2],
  'Snappy Fish': [4, 3, 5, 1, 2, 7],
  Lemon: [8, 9, 4, 7, 9, 1],
  Pasta: [6, 7, 8, 9, 8, 9]
};

const generateRankingData = () => {
  const map = new Map();
  for (const name of names) {
    map.set(name, rankings[name]);
  }
  return map;
};

const generateSeriesList = () => {
  const seriesList = [];
  const rankingMap = generateRankingData();

  rankingMap.forEach((data, name) => {
    const series = {
      name,
      symbolSize: 20,
      type: 'line',
      smooth: true,
      emphasis: {
        focus: 'series'
      },
      endLabel: {
        show: true,
        formatter: '{a}',
        distance: 20
      },
      lineStyle: {
        width: 4
      },
      data
    };
    seriesList.push(series);
  });
  return seriesList;
};

option = {
  title: {
    text: 'Bump Chart (Ranking)'
  },
  tooltip: {
    trigger: 'item'
  },
  grid: {
    left: 30,
    right: 110,
    bottom: 30,
    containLabel: true
  },
  toolbox: {
    feature: {
      saveAsImage: {}
    }
  },
  xAxis: {
    type: 'category',
    splitLine: {
      show: true
    },
    axisLabel: {
      margin: 30,
      fontSize: 16
    },
    boundaryGap: false,
    data: years
  },
  yAxis: {
    type: 'value',
    axisLabel: {
      margin: 30,
      fontSize: 16,
      formatter: '#{value}'
    },
    inverse: true,
    interval: 1,
    min: 1,
    max: names.length
  },
  series: generateSeriesList()
};
"""#,
        option: [
            "title": [
                "text": "Bump Chart (Ranking)"
            ] as [String: Any],
            "tooltip": [
                "trigger": "item"
            ] as [String: Any],
            "grid": [
                "left": 30.0,
                "right": 110.0,
                "bottom": 30.0,
                "containLabel": true
            ] as [String: Any],
            "toolbox": [
                "feature": [
                    "saveAsImage": [:] as [String: Any]
                ] as [String: Any]
            ] as [String: Any],
            "xAxis": [
                "type": "category",
                "splitLine": [
                    "show": true
                ] as [String: Any],
                "axisLabel": [
                    "margin": 30.0,
                    "fontSize": 16.0
                ] as [String: Any],
                "boundaryGap": false,
                "data": bumpChartYears
            ] as [String: Any],
            "yAxis": [
                "type": "value",
                "axisLabel": [
                    "margin": 30.0,
                    "fontSize": 16.0,
                    "formatter": "#{value}"
                ] as [String: Any],
                "inverse": true,
                "interval": 1.0,
                "min": 1.0,
                "max": Double(bumpChartNames.count)
            ] as [String: Any],
            "series": bumpChartSeries
        ])
}

private let bumpChartNames: [String] = [
    "Orange",
    "Tomato",
    "Apple",
    "Sakana",
    "Banana",
    "Iwashi",
    "Snappy Fish",
    "Lemon",
    "Pasta"
]

private let bumpChartYears: [String] = ["2001", "2002", "2003", "2004", "2005", "2006"]

// One frozen draw of the example's random shuffle: row i is `bumpChartNames[i]`'s rank in each of
// the six years, and every column (year) is a permutation of 1...9.
private let bumpChartRankings: [[Double]] = [
    [3, 1, 2, 5, 4, 6],   // Orange
    [1, 4, 3, 2, 6, 5],   // Tomato
    [5, 2, 6, 4, 1, 3],   // Apple
    [9, 8, 7, 6, 5, 4],   // Sakana
    [2, 5, 1, 3, 7, 8],   // Banana
    [7, 6, 9, 8, 3, 2],   // Iwashi
    [4, 3, 5, 1, 2, 7],   // Snappy Fish
    [8, 9, 4, 7, 9, 1],   // Lemon
    [6, 7, 8, 9, 8, 9]    // Pasta
]

// The example's `generateSeriesList()`: one smooth line series per name, all styled identically.
private let bumpChartSeries: [[String: Any]] = bumpChartNames.enumerated().map { index, name in
    [
        "name": name,
        "symbolSize": 20.0,
        "type": "line",
        "smooth": true,
        "emphasis": [
            "focus": "series"
        ] as [String: Any],
        "endLabel": [
            "show": true,
            "formatter": "{a}",
            "distance": 20.0
        ] as [String: Any],
        "lineStyle": [
            "width": 4.0
        ] as [String: Any],
        "data": bumpChartRankings[index]
    ] as [String: Any]
}
