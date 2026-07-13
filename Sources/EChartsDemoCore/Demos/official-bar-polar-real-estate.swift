// official-bar-polar-real-estate — replica of https://echarts.apache.org/examples/zh/editor.html?c=bar-polar-real-estate
// title: Bar Chart on Polar / titleCN: 极坐标系下的柱状图
// Chinese apartment rents on a polar coordinate system: 19 cities on the angleAxis, each drawn as a
// floating "Range" bar (min→max, stacked on a transparent min spacer) plus a fixed-height "Average"
// marker bar (stacked on a transparent `avg - barHeight` spacer, barGap '-100%', z 10).
// DEVIATIONS:
//   - webOptionJS: the TS type annotation in `function (params: any)` is dropped (the reference pane
//     is a classic <script>; `: any` is a SyntaxError there). Otherwise verbatim, minus `export {};`.
//   - option (native): `tooltip.formatter` is omitted — it is a JS closure (see PORT-NOTE below).
//   - option (native): the four series' `data.map(...)` calls are precomputed into file-scope arrays
//     (same numbers); inline closures inside the option literal stall Swift's type-checker.
//   - Canvas bumped to 720x520 (official shotWidth is 800): the polar plot needs room under the
//     title/subtitle and above the bottom legend.
extension EChartsDemoRegistry {
    static let official_bar_polar_real_estate = EChartsDemo(
        name: "official-bar-polar-real-estate", category: "bar",
        summary: "极坐标系下的柱状图 — Bar Chart on Polar",
        width: 720, height: 520,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
const data = [
  [5000, 10000, 6785.71],
  [4000, 10000, 6825],
  [3000, 6500, 4463.33],
  [2500, 5600, 3793.83],
  [2000, 4000, 3060],
  [2000, 4000, 3222.33],
  [2500, 4000, 3133.33],
  [1800, 4000, 3100],
  [2000, 3500, 2750],
  [2000, 3000, 2500],
  [1800, 3000, 2433.33],
  [2000, 2700, 2375],
  [1500, 2800, 2150],
  [1500, 2300, 2100],
  [1600, 3500, 2057.14],
  [1500, 2600, 2037.5],
  [1500, 2417.54, 1905.85],
  [1500, 2000, 1775],
  [1500, 1800, 1650]
];
// prettier-ignore
const cities = ['北京', '上海', '深圳', '广州', '苏州', '杭州', '南京', '福州', '青岛', '济南', '长春', '大连', '温州', '郑州', '武汉', '成都', '东莞', '沈阳', '烟台'];
const barHeight = 50;

option = {
  title: {
    text: 'How expensive is it to rent an apartment in China?',
    subtext: 'Data from https://www.numbeo.com'
  },
  legend: {
    show: true,
    top: 'bottom',
    data: ['Range', 'Average']
  },
  grid: {
    top: 100
  },
  angleAxis: {
    type: 'category',
    data: cities
  },
  tooltip: {
    show: true,
    formatter: function (params) {
      const id = params.dataIndex;
      return (
        cities[id] +
        '<br>Lowest：' +
        data[id][0] +
        '<br>Highest：' +
        data[id][1] +
        '<br>Average：' +
        data[id][2]
      );
    }
  },
  radiusAxis: {},
  polar: {},
  series: [
    {
      type: 'bar',
      itemStyle: {
        color: 'transparent'
      },
      data: data.map(function (d) {
        return d[0];
      }),
      coordinateSystem: 'polar',
      stack: 'Min Max',
      silent: true
    },
    {
      type: 'bar',
      data: data.map(function (d) {
        return d[1] - d[0];
      }),
      coordinateSystem: 'polar',
      name: 'Range',
      stack: 'Min Max'
    },
    {
      type: 'bar',
      itemStyle: {
        color: 'transparent'
      },
      data: data.map(function (d) {
        return d[2] - barHeight;
      }),
      coordinateSystem: 'polar',
      stack: 'Average',
      silent: true,
      z: 10
    },
    {
      type: 'bar',
      data: data.map(function (d) {
        return barHeight * 2;
      }),
      coordinateSystem: 'polar',
      name: 'Average',
      stack: 'Average',
      barGap: '-100%',
      z: 10
    }
  ]
};
"""#,
        option: [
            "title": [
                "text": "How expensive is it to rent an apartment in China?",
                "subtext": "Data from https://www.numbeo.com"
            ] as [String: Any],
            "legend": [
                "show": true,
                "top": "bottom",
                "data": ["Range", "Average"]
            ] as [String: Any],
            "grid": [
                "top": 100.0
            ] as [String: Any],
            "angleAxis": [
                "type": "category",
                "data": barPolarRealEstateCities
            ] as [String: Any],
            "tooltip": [
                "show": true
                // PORT-NOTE: tooltip.formatter omitted — a JS closure that looked the hovered
                // params.dataIndex up in the raw table and rendered an HTML block
                // "<city><br>Lowest：<min><br>Highest：<max><br>Average：<avg>".
            ] as [String: Any],
            "radiusAxis": [:] as [String: Any],
            "polar": [:] as [String: Any],
            "series": [
                // Transparent spacer: pushes the "Range" bar out to each city's minimum rent.
                [
                    "type": "bar",
                    "itemStyle": ["color": "transparent"] as [String: Any],
                    "data": barPolarRealEstateLowest,
                    "coordinateSystem": "polar",
                    "stack": "Min Max",
                    "silent": true
                ] as [String: Any],
                // The visible min→max range bar.
                [
                    "type": "bar",
                    "data": barPolarRealEstateRange,
                    "coordinateSystem": "polar",
                    "name": "Range",
                    "stack": "Min Max"
                ] as [String: Any],
                // Transparent spacer: pushes the "Average" marker out to (avg - barHeight).
                [
                    "type": "bar",
                    "itemStyle": ["color": "transparent"] as [String: Any],
                    "data": barPolarRealEstateAvgBase,
                    "coordinateSystem": "polar",
                    "stack": "Average",
                    "silent": true,
                    "z": 10.0
                ] as [String: Any],
                // The fixed-thickness average marker, centred on avg.
                [
                    "type": "bar",
                    "data": barPolarRealEstateAvgBand,
                    "coordinateSystem": "polar",
                    "name": "Average",
                    "stack": "Average",
                    "barGap": "-100%",
                    "z": 10.0
                ] as [String: Any]
            ]
        ])
}

// [lowest, highest, average] monthly rent (CNY) per city, in the same order as the cities below.
private let barPolarRealEstateData: [[Double]] = [
    [5000, 10000, 6785.71],
    [4000, 10000, 6825],
    [3000, 6500, 4463.33],
    [2500, 5600, 3793.83],
    [2000, 4000, 3060],
    [2000, 4000, 3222.33],
    [2500, 4000, 3133.33],
    [1800, 4000, 3100],
    [2000, 3500, 2750],
    [2000, 3000, 2500],
    [1800, 3000, 2433.33],
    [2000, 2700, 2375],
    [1500, 2800, 2150],
    [1500, 2300, 2100],
    [1600, 3500, 2057.14],
    [1500, 2600, 2037.5],
    [1500, 2417.54, 1905.85],
    [1500, 2000, 1775],
    [1500, 1800, 1650]
]

private let barPolarRealEstateCities: [String] = [
    "北京", "上海", "深圳", "广州", "苏州", "杭州", "南京", "福州", "青岛", "济南",
    "长春", "大连", "温州", "郑州", "武汉", "成都", "东莞", "沈阳", "烟台"
]

// Radial half-thickness of the "Average" marker bar.
private let barPolarRealEstateBarHeight: Double = 50

// The four series' data, mirroring the source's `data.map(...)` calls one-for-one.
private let barPolarRealEstateLowest: [Double] = barPolarRealEstateData.map { $0[0] }
private let barPolarRealEstateRange: [Double] = barPolarRealEstateData.map { $0[1] - $0[0] }
private let barPolarRealEstateAvgBase: [Double] = barPolarRealEstateData.map { $0[2] - barPolarRealEstateBarHeight }
private let barPolarRealEstateAvgBand: [Double] = barPolarRealEstateData.map { _ in barPolarRealEstateBarHeight * 2 }
