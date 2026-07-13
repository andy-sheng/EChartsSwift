// official-scatter-nutrients — replica of https://echarts.apache.org/examples/zh/editor.html?c=scatter-nutrients
// title: Scatter Nutrients / titleCN: 营养分布散点图
// 1000 USDA food items scattered protein (x) vs calcium (y), coloured by food group through a
// piecewise visualMap over dimension 2 (25 categories, each an HSL-rotated shade of #5A94DF), with a
// second continuous visualMap dimming lightness by dimension 3 (the row index).
//
// DEVIATIONS from the official source:
//  - DATA INLINED: the official `$.get(ROOT_PATH + '/data/asset/data/nutrients.json', ...)` fetch is
//    replaced by the repo asset assets/data/nutrients.json (verbatim mirror, 7637 rows × 17 cols),
//    read via Upstream.repoRoot for the native pane and spliced into the web pane's script. The WHOLE
//    file is inlined, not just the plotted rows: `normalizeData` derives groupCategories/groupColors
//    from ALL rows, and only afterwards does `.slice(0, 1000)` pick the rows that become the series —
//    truncating the data first would change the category count, hence hStep, hence every colour.
//    The callback body is kept; `option` is assigned unconditionally at the top level.
//  - `myChart.getZr().configLayer(1, { motionBlur: true })` DROPPED from the web pane: the gallery
//    page creates `myChart` only after the option script runs, and it renders ONE static frame with
//    animation off, so there is no motion to leave a trail. The series' `zlevel: 1` is kept verbatim.
//  - `app.config` / `app.configParameters` (the official editor's live x/y-field pickers) and the
//    trailing `export {}` are dropped — editor harness, and a bare export is a SyntaxError in a
//    classic script. The initial pair (protein, calcium) is what both panes render.
//  - The source's TS type annotations are stripped in the web pane (the page runs classic JS).
// The option itself contains no closures, so the native pane carries it whole — normalizeData's work
// (null→0 coercion, group ordering, echarts.color.modifyHSL ramp) is done in Swift below.
import Foundation
import ZRenderKit

// The nutrients dataset, prepared once: the raw JSON text (spliced into the web pane verbatim) plus
// the Swift-side result of the example's `normalizeData` + `getOption`'s `data.map`. A read/parse
// failure degrades to empty data (the pane renders blank rather than crashing).
private struct NutrientsPrep {
    let categories: [String]   // groupCategories — food groups in first-seen order
    let colors: [String]       // groupColors — modifyHSL('#5A94DF', hStep * i)
    let seriesData: [[Any]]    // [protein, calcium, group, idx] for the first 1000 rows
    let json: String           // the raw asset text, for webOptionJS
}

private let nutrientsPrep: NutrientsPrep = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/data/nutrients.json")
    guard let raw = try? Data(contentsOf: url),
          let jsonText = String(data: raw, encoding: .utf8),
          let rows = (try? JSONSerialization.jsonObject(with: raw)) as? [[Any]],
          !rows.isEmpty else {
        return NutrientsPrep(categories: [], colors: [], seriesData: [], json: "[]")
    }

    // normalizeData(): groupMap keyed by row[1] — JS object key insertion order, so first-seen order.
    var categories: [String] = []
    var seenGroups = Set<String>()
    for row in rows where row.count > 1 {
        guard let group = row[1] as? String else { continue }
        if seenGroups.insert(group).inserted { categories.append(group) }
    }

    // let hStep = Math.round(300 / (groupCategories.length - 1));
    // groupColors.push(echarts.color.modifyHSL('#5A94DF', hStep * i));
    let hStep = categories.count > 1 ? (300.0 / Double(categories.count - 1)).rounded() : 0
    let colors: [String] = (0..<categories.count).map { i in
        ZRenderKit.color.modifyHSL("#5A94DF", .number(hStep * Double(i))) ?? "#5A94DF"
    }

    // normalizeData(): every column except name/group/id is `parseFloat(item) || 0` (null → 0, all "g").
    func num(_ row: [Any], _ index: Int) -> Double {
        guard index < row.count else { return 0 }
        if let n = row[index] as? NSNumber { return n.doubleValue }
        if let s = row[index] as? String { return Double(s) ?? 0 }
        return 0
    }

    // getOption(): data.slice(0, 1000).map((item, idx) => [item[2], item[3], item[1], idx])
    var seriesData: [[Any]] = []
    seriesData.reserveCapacity(1000)
    for (idx, row) in rows.prefix(1000).enumerated() {
        let group: String = (row.count > 1 ? row[1] as? String : nil) ?? ""
        seriesData.append([num(row, 2), num(row, 3), group, Double(idx)])
    }

    return NutrientsPrep(categories: categories, colors: colors, seriesData: seriesData, json: jsonText)
}()

extension EChartsDemoRegistry {
    static let official_scatter_nutrients = EChartsDemo(
        name: "official-scatter-nutrients", category: "scatter",
        summary: "营养分布散点图 — Scatter Nutrients",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
const indices = {
  name: 0,
  group: 1,
  id: 16
};
const schema = [
  { name: 'name', index: 0 },
  { name: 'group', index: 1 },
  { name: 'protein', index: 2 },
  { name: 'calcium', index: 3 },
  { name: 'sodium', index: 4 },
  { name: 'fiber', index: 5 },
  { name: 'vitaminc', index: 6 },
  { name: 'potassium', index: 7 },
  { name: 'carbohydrate', index: 8 },
  { name: 'sugars', index: 9 },
  { name: 'fat', index: 10 },
  { name: 'water', index: 11 },
  { name: 'calories', index: 12 },
  { name: 'saturated', index: 13 },
  { name: 'monounsat', index: 14 },
  { name: 'polyunsat', index: 15 },
  { name: 'id', index: 16 }
];

const fieldIndices = schema.reduce(function (obj, item) {
  obj[item.name] = item.index;
  return obj;
}, {});

const groupCategories = [];
const groupColors = [];
let data;

// DEVIATION: `myChart.getZr().configLayer(1, { motionBlur: true })` dropped — the page creates
// myChart only after this script and renders one static frame, so there is no trail to blur.

// DEVIATION: `$.get(ROOT_PATH + '/data/asset/data/nutrients.json', function (originData) {...})` —
// fetch dropped, the asset inlined; the callback body is kept and assigns `option` at top level.
const originData = \#(nutrientsPrep.json);
data = normalizeData(originData).slice(0, 1000);
option = getOption(data);

function normalizeData(originData) {
  let groupMap = {};
  originData.forEach(function (row) {
    let groupName = row[indices.group];
    if (!groupMap.hasOwnProperty(groupName)) {
      groupMap[groupName] = 1;
    }
  });

  originData.forEach(function (row) {
    row.forEach(function (item, index) {
      if (
        index !== indices.name &&
        index !== indices.group &&
        index !== indices.id
      ) {
        // Convert null to zero, as all of them under unit "g".
        row[index] = parseFloat(item) || 0;
      }
    });
  });

  for (let groupName in groupMap) {
    if (groupMap.hasOwnProperty(groupName)) {
      groupCategories.push(groupName);
    }
  }
  let hStep = Math.round(300 / (groupCategories.length - 1));
  for (let i = 0; i < groupCategories.length; i++) {
    groupColors.push(echarts.color.modifyHSL('#5A94DF', hStep * i));
  }

  return originData;
}

function getOption(data) {
  return {
    xAxis: {
      name: 'protein',
      splitLine: { show: false }
    },
    yAxis: {
      name: 'calcium',
      splitLine: { show: false }
    },
    visualMap: [
      {
        show: false,
        type: 'piecewise',
        categories: groupCategories,
        dimension: 2,
        inRange: {
          color: groupColors
        },
        outOfRange: {
          color: ['#ccc']
        },
        top: 20,
        textStyle: {
          color: '#fff'
        },
        realtime: false
      },
      {
        show: false,
        dimension: 3,
        max: 100,
        inRange: {
          colorLightness: [0.15, 0.6]
        }
      }
    ],
    series: [
      {
        zlevel: 1,
        name: 'nutrients',
        type: 'scatter',
        data: data.map(function (item, idx) {
          return [item[2], item[3], item[1], idx];
        }),
        animationThreshold: 5000,
        progressiveThreshold: 5000
      }
    ],
    animationEasingUpdate: 'cubicInOut',
    animationDurationUpdate: 2000
  };
}
"""#,
        option: [
            "xAxis": [
                "name": "protein",
                "splitLine": ["show": false] as [String: Any]
            ] as [String: Any],
            "yAxis": [
                "name": "calcium",
                "splitLine": ["show": false] as [String: Any]
            ] as [String: Any],
            "visualMap": [
                [
                    "show": false,
                    "type": "piecewise",
                    "categories": nutrientsPrep.categories,
                    "dimension": 2.0,
                    "inRange": ["color": nutrientsPrep.colors] as [String: Any],
                    "outOfRange": ["color": ["#ccc"]] as [String: Any],
                    "top": 20.0,
                    "textStyle": ["color": "#fff"] as [String: Any],
                    "realtime": false
                ] as [String: Any],
                [
                    "show": false,
                    "dimension": 3.0,
                    "max": 100.0,
                    "inRange": ["colorLightness": [0.15, 0.6]] as [String: Any]
                ] as [String: Any]
            ],
            "series": [
                [
                    "zlevel": 1.0,
                    "name": "nutrients",
                    "type": "scatter",
                    "data": nutrientsPrep.seriesData,
                    "animationThreshold": 5000.0,
                    "progressiveThreshold": 5000.0
                ] as [String: Any]
            ],
            "animationEasingUpdate": "cubicInOut",
            "animationDurationUpdate": 2000.0
        ])
}
