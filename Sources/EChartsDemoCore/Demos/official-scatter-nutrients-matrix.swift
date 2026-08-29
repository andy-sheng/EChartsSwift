// official-scatter-nutrients-matrix — replica of
// https://echarts.apache.org/examples/zh/editor.html?c=scatter-nutrients-matrix
// title: Scatter Nutrients Matrix / titleCN: 营养分布散点矩阵
//
// A 2x2 matrix of scatter grids over the USDA nutrients table: the two x-axes (carbohydrate,
// potassium) and the two y-axes (calcium, fiber) are crossed, so the same 1000 foods are plotted
// four times. Each grid gets its own id'd x/y axis pair (colour-coded per axis), the four grids are
// linked pairwise through `axisPointer.link`, four dataZoom sliders drive the axis pairs, and a
// hidden piecewise `visualMap` colours points by food group (25 categories, hues stepped through
// `echarts.color.modifyHSL('#5A94DF', 13*i)`).
//
// DEVIATIONS from the official source:
//   1. DATA: the example does `$.get(ROOT_PATH + '/data/asset/data/nutrients.json', ...)`. The page
//      has no network, so the asset is mirrored into the repo (assets/data/nutrients.json, verbatim
//      from the official asset tree) and read via Upstream.repoRoot. The web pane gets the raw JSON
//      text spliced in; the native pane parses the same file. BOTH panes then run the upstream
//      `normalizeData(originData).slice(0, 1000)` — full 7637 rows for the group list, first 1000
//      plotted — so nothing about the data pipeline is simplified.
//   2. app.* HARNESS: `app.config` / `app.configParameters` (the official editor's live axis-field
//      pickers) and the `onChange` re-setOption path are removed. Both panes hard-code the initial
//      config — xAxisLeft: carbohydrate, yAxisTop: calcium, xAxisRight: potassium, yAxisBottom:
//      fiber — which is exactly the state the example first renders.
//   3. `myChart.getZr().configLayer(1, { motionBlur: true })` is dropped: there is no `myChart` at
//      option-eval time in the gallery page, and the motion-blur trail only appears DURING the 2s
//      `animationDurationUpdate` re-layout that `onChange` triggers — a single static frame cannot
//      show it. The series keep `zlevel: 1`.
//   4. The tooltip formatter and position callbacks use the native callback seams. The native rich-
//      text host emits the same headings and values as the official HTML formatter without DOM tags.
//   5. Canvas is 900x560, not the gallery default: four 35%x35% grids plus four dataZoom sliders
//      overlap vertically at 640x420 (top grid bottom edge 197px vs bottom grid top edge 193px).
import Foundation
import ZRenderKit
import EChartsKit

// upstream `schema` flattened to its `name -> index` reduction (`fieldIndices`). Column 0 is the food
// name, 1 the food group, 16 the id; 2..15 are the nutrient values.
private let nutrientsFieldIndices: [String: Int] = [
    "name": 0, "group": 1, "protein": 2, "calcium": 3, "sodium": 4, "fiber": 5,
    "vitaminc": 6, "potassium": 7, "carbohydrate": 8, "sugars": 9, "fat": 10,
    "water": 11, "calories": 12, "saturated": 13, "monounsat": 14, "polyunsat": 15, "id": 16
]

// upstream `axisColors` — one colour per axis slot, applied to that axis' line/label/tick.
private let nutrientsAxisColors: [String: String] = [
    "xAxisLeft": "#2A8339", "xAxisRight": "#367DA6",
    "yAxisTop": "#A68B36", "yAxisBottom": "#BD5692"
]

// upstream `app.config`'s initial value: which schema field each of the four axis slots plots.
private let nutrientsConfig: [String: String] = [
    "xAxisLeft": "carbohydrate", "yAxisTop": "calcium",
    "xAxisRight": "potassium", "yAxisBottom": "fiber"
]

private let nutrientsColorBySchema: [String: String] = [
    "carbohydrate": "#2A8339",
    "potassium": "#367DA6",
    "calcium": "#A68B36",
    "fiber": "#BD5692"
]

// The raw asset text, spliced verbatim into the web pane (which cannot read the filesystem).
private let nutrientsRawJSON: String = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/data/nutrients.json")
    return (try? String(contentsOf: url, encoding: .utf8)) ?? "[]"
}()

/// The upstream `normalizeData(originData)` + `.slice(0, 1000)`, in Swift.
private struct NutrientsMatrix {
    let rows: [[Any]]              // first 1000 rows, numeric columns coerced to Double
    let groupCategories: [String]  // every distinct food group across ALL 7637 rows (25 of them)
    let groupColors: [String]      // modifyHSL('#5A94DF', hStep * i) per category
}

private let nutrientsMatrix: NutrientsMatrix = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/data/nutrients.json")
    guard let data = try? Data(contentsOf: url),
          let raw = (try? JSONSerialization.jsonObject(with: data)) as? [[Any]], !raw.isEmpty else {
        return NutrientsMatrix(rows: [], groupCategories: [], groupColors: [])
    }

    // groupMap is built over the WHOLE table (not the 1000-row slice), so all 25 groups get a colour.
    var groupCategories: [String] = []
    var seen = Set<String>()
    for row in raw {
        guard row.count > 1, let group = row[1] as? String, !seen.contains(group) else { continue }
        seen.insert(group)
        groupCategories.append(group)
    }

    // upstream: `row[index] = parseFloat(item) || 0` for every column except name/group/id — the
    // table is full of nulls (all values share the unit "g", so null means zero).
    let rows: [[Any]] = raw.prefix(1000).map { row in
        var out = row
        for i in out.indices where i != 0 && i != 1 && i != 16 {
            out[i] = (out[i] as? NSNumber)?.doubleValue ?? 0.0
        }
        return out
    }

    // upstream: `Math.round(300 / (groupCategories.length - 1))` -> round(12.5) -> 13. Swift's
    // `.rounded()` is toNearestOrAwayFromZero, which matches JS `Math.round` on the .5 tie.
    let hStep = (300.0 / Double(max(1, groupCategories.count - 1))).rounded()
    let groupColors: [String] = (0..<groupCategories.count).map { i in
        ZRenderKit.color.modifyHSL("#5A94DF", .number(hStep * Double(i))) ?? "#5A94DF"
    }
    return NutrientsMatrix(rows: rows, groupCategories: groupCategories, groupColors: groupColors)
}()

/// upstream `makeAxis(dimIndex, id, name, nameLocation)`. `id` is "<xSlot>-<ySlot>"; the axis takes
/// the colour of its own half of that id (dimIndex 0 -> x slot, 1 -> y slot).
private func nutrientsAxis(_ dimIndex: Int, _ id: String, _ name: String,
                           _ nameLocation: String) -> [String: Any] {
    let slots = id.split(separator: "-").map(String.init)
    let axisColor = nutrientsAxisColors[slots[dimIndex]] ?? "#333"
    return [
        "id": id,
        "name": name,
        "nameLocation": nameLocation,
        "nameGap": nameLocation == "middle" ? 30.0 : 10.0,
        "gridId": id,
        "splitLine": ["show": false] as [String: Any],
        "axisLine": ["lineStyle": ["color": axisColor] as [String: Any]] as [String: Any],
        "axisLabel": ["color": axisColor] as [String: Any],
        "axisTick": ["lineStyle": ["color": axisColor] as [String: Any]] as [String: Any]
    ]
    // NOTE: upstream also records `colorBySchema[name] = axisColor` here — that map is read ONLY by
    // the tooltip formatter (a JS closure the native option cannot carry), so it is web-pane-only.
}

/// upstream `makeSeriesData` — one point per food:
/// [0] xValue, [1] yValue, [2] group, [3] name, [4] schemaX, [5] schemaY, [6] index.
private func nutrientsSeriesData(_ xLeftOrRight: String, _ yTopOrBottom: String) -> [[Any]] {
    let schemaX = nutrientsConfig[xLeftOrRight] ?? "carbohydrate"
    let schemaY = nutrientsConfig[yTopOrBottom] ?? "calcium"
    let xi = nutrientsFieldIndices[schemaX] ?? 0
    let yi = nutrientsFieldIndices[schemaY] ?? 0
    return nutrientsMatrix.rows.enumerated().map { idx, item -> [Any] in
        [item[xi], item[yi], item[1], item[0], schemaX, schemaY, Double(idx)]
    }
}

/// upstream `makeSeries` — one scatter per grid, bound to that grid's id'd axis pair.
private func nutrientsSeries(_ xLeftOrRight: String, _ yTopOrBottom: String) -> [String: Any] {
    let id = xLeftOrRight + "-" + yTopOrBottom
    return [
        "zlevel": 1.0,
        "type": "scatter",
        "name": "nutrients",
        "xAxisId": id,
        "yAxisId": id,
        "symbolSize": 8.0,
        "emphasis": ["itemStyle": ["color": "#fff"] as [String: Any]] as [String: Any],
        "data": nutrientsSeriesData(xLeftOrRight, yTopOrBottom) as [Any]
    ]
}

/// upstream `makeDataZoom(opt)` — `Object.assign({ type, filterMode, realtime }, opt)`.
private func nutrientsDataZoom(_ opt: [String: Any]) -> [String: Any] {
    var dz: [String: Any] = ["type": "slider", "filterMode": "empty", "realtime": false]
    for (key, value) in opt { dz[key] = value }
    return dz
}

private func nutrientsTooltipValueText(_ value: Any?) -> String {
    if let value = value as? Double {
        return value.rounded() == value ? String(Int(value)) : String(value)
    }
    if let value = value as? Int { return String(value) }
    if let value = value as? NSNumber {
        let number = value.doubleValue
        return number.rounded() == number ? String(Int(number)) : String(number)
    }
    return String(describing: value ?? "")
}

private struct NutrientsTooltipFood {
    var keyOrder: [String] = []
    var values: [String: Any] = [:]
}

private let nutrientsTooltipFormatter: ([TooltipCallbackDataParams]) -> String = { params in
    var foods: [String: NutrientsTooltipFood] = [:]
    var foodOrder: [String] = []
    var namesByAxis: [String: Set<String>] = ["x": [], "y": []]

    for item in params {
        guard let data = item.data as? [Any], data.count > 5,
              let foodName = data[3] as? String,
              let xSchema = data[4] as? String,
              let ySchema = data[5] as? String else { continue }
        if foods[foodName] == nil {
            foods[foodName] = NutrientsTooltipFood()
            foodOrder.append(foodName)
        }
        var food = foods[foodName]!
        if food.values[xSchema] == nil { food.keyOrder.append(xSchema) }
        food.values[xSchema] = data[0]
        if food.values[ySchema] == nil { food.keyOrder.append(ySchema) }
        food.values[ySchema] = data[1]
        foods[foodName] = food
        if let axisDim = item.axisDim, namesByAxis[axisDim] != nil {
            namesByAxis[axisDim]!.insert(foodName)
        }
    }

    let xNames = namesByAxis["x"] ?? []
    let yNames = namesByAxis["y"] ?? []
    let crossNames = xNames.intersection(yNames)
    let sections: [(Set<String>, String)] = [
        (crossNames, "CROSS"),
        (xNames.subtracting(crossNames), "V LINE"),
        (yNames.subtracting(crossNames), "H LINE")
    ]
    var output: [String] = []
    for (names, heading) in sections where !names.isEmpty {
        var lines = ["{heading|POINTS ON \(heading)}"]
        for foodName in foodOrder where names.contains(foodName) {
            guard let food = foods[foodName] else { continue }
            lines.append("")
            lines.append(foodName)
            for key in food.keyOrder {
                // Upstream colors only the schema name inside <span>; punctuation and value inherit
                // the tooltip's white text color. The leading newline combines with the array join's
                // separator to create the rich-text line holder consumed by the colored span; this is
                // the exact one-line equivalent of the preceding HTML <br/> without an empty row.
                lines.append("\n{\(key)|\(key)}: \(nutrientsTooltipValueText(food.values[key]))")
            }
        }
        output.append(lines.joined(separator: "\n"))
    }
    return output.joined(separator: "\n\n")
}

private let nutrientsTooltipPosition: TooltipPositionCallback = { point, _, _, _, size in
    var result: [String: Any] = [:]
    result[point.0 < size.viewSize.0 / 2 ? "right" : "left"] = 60.0
    result[point.1 < size.viewSize.1 / 2 ? "bottom" : "top"] = 20.0
    return result
}

// The option's components, hoisted out of the one big literal (Swift's type-checker chokes on deeply
// nested heterogeneous dictionaries). Assembled in `nutrientsOption` below.

private let nutrientsTooltip: [String: Any] = [
    "trigger": "none",
    "padding": [10.0, 20.0, 10.0, 20.0],
    "backgroundColor": "rgba(0,0,0,0.7)",
    "transitionDuration": 0.0,
    "extraCssText": "width: 300px; white-space: normal",
    "textStyle": [
        "color": "#fff",
        "fontSize": 12.0,
        "rich": [
            "heading": ["color": "#aaa", "fontSize": 16.0] as [String: Any],
            "carbohydrate": ["color": nutrientsColorBySchema["carbohydrate"] ?? "#2A8339"] as [String: Any],
            "potassium": ["color": nutrientsColorBySchema["potassium"] ?? "#367DA6"] as [String: Any],
            "calcium": ["color": nutrientsColorBySchema["calcium"] ?? "#A68B36"] as [String: Any],
            "fiber": ["color": nutrientsColorBySchema["fiber"] ?? "#BD5692"] as [String: Any]
        ] as [String: Any]
    ] as [String: Any],
    "position": nutrientsTooltipPosition,
    "formatter": nutrientsTooltipFormatter
]

// The four grids are linked pairwise: the two left grids share an x-axis pointer, the two right grids
// share theirs, the two top grids share a y-axis pointer, the two bottom grids share theirs.
private let nutrientsAxisPointer: [String: Any] = [
    "show": true,
    "snap": true,
    "lineStyle": ["type": "dashed"] as [String: Any],
    "label": ["show": true, "margin": 6.0, "backgroundColor": "#556", "color": "#fff"] as [String: Any],
    "link": [
        ["xAxisId": ["xAxisLeft-yAxisTop", "xAxisLeft-yAxisBottom"]] as [String: Any],
        ["xAxisId": ["xAxisRight-yAxisTop", "xAxisRight-yAxisBottom"]] as [String: Any],
        ["yAxisId": ["xAxisLeft-yAxisTop", "xAxisRight-yAxisTop"]] as [String: Any],
        ["yAxisId": ["xAxisLeft-yAxisBottom", "xAxisRight-yAxisBottom"]] as [String: Any]
    ] as [Any]
]

// gridWidth/gridHeight '35%', gridLeft 80, gridRight 50, gridTop 50, gridBottom 80.
private let nutrientsGrids: [[String: Any]] = [
    ["id": "xAxisLeft-yAxisTop", "left": 80.0, "top": 50.0, "width": "35%", "height": "35%"],
    ["id": "xAxisLeft-yAxisBottom", "left": 80.0, "bottom": 80.0, "width": "35%", "height": "35%"],
    ["id": "xAxisRight-yAxisTop", "right": 50.0, "top": 50.0, "width": "35%", "height": "35%"],
    ["id": "xAxisRight-yAxisBottom", "right": 50.0, "bottom": 80.0, "width": "35%", "height": "35%"]
]

// Two horizontal sliders (one per x-axis column) + two vertical ones (one per y-axis row).
private let nutrientsDataZooms: [[String: Any]] = [
    nutrientsDataZoom(["width": "35%", "height": 20.0, "left": 80.0, "bottom": 10.0,
                       "xAxisIndex": [0.0, 1.0]]),
    nutrientsDataZoom(["width": "35%", "height": 20.0, "right": 50.0, "bottom": 10.0,
                       "xAxisIndex": [2.0, 3.0]]),
    nutrientsDataZoom(["orient": "vertical", "width": 20.0, "height": "35%", "left": 10.0,
                       "top": 50.0, "yAxisIndex": [0.0, 2.0]]),
    nutrientsDataZoom(["orient": "vertical", "width": 20.0, "height": "35%", "left": 10.0,
                       "bottom": 80.0, "yAxisIndex": [1.0, 3.0]])
]

// Hidden piecewise visualMap: colours each point by its food group (data dimension 2).
private let nutrientsVisualMap: [String: Any] = [
    "show": false,
    "type": "piecewise",
    "categories": nutrientsMatrix.groupCategories,
    "dimension": 2.0,
    "inRange": ["color": nutrientsMatrix.groupColors] as [String: Any],
    "outOfRange": ["color": ["#ccc"]] as [String: Any],
    "top": 20.0,
    "textStyle": ["color": "#fff"] as [String: Any],
    "realtime": false
]

private let nutrientsOption: [String: Any] = [
    "tooltip": nutrientsTooltip,
    "axisPointer": nutrientsAxisPointer,
    "xAxis": [
        nutrientsAxis(0, "xAxisLeft-yAxisTop", "carbohydrate", "middle"),
        nutrientsAxis(0, "xAxisLeft-yAxisBottom", "carbohydrate", "middle"),
        nutrientsAxis(0, "xAxisRight-yAxisTop", "potassium", "middle"),
        nutrientsAxis(0, "xAxisRight-yAxisBottom", "potassium", "middle")
    ] as [Any],
    "yAxis": [
        nutrientsAxis(1, "xAxisLeft-yAxisTop", "calcium", "end"),
        nutrientsAxis(1, "xAxisLeft-yAxisBottom", "fiber", "end"),
        nutrientsAxis(1, "xAxisRight-yAxisTop", "calcium", "end"),
        nutrientsAxis(1, "xAxisRight-yAxisBottom", "fiber", "end")
    ] as [Any],
    "grid": nutrientsGrids as [Any],
    "dataZoom": nutrientsDataZooms as [Any],
    "visualMap": [nutrientsVisualMap] as [Any],
    "series": [
        nutrientsSeries("xAxisLeft", "yAxisTop"),
        nutrientsSeries("xAxisLeft", "yAxisBottom"),
        nutrientsSeries("xAxisRight", "yAxisTop"),
        nutrientsSeries("xAxisRight", "yAxisBottom")
    ] as [Any],
    "animationThreshold": 5000.0,
    "progressiveThreshold": 5000.0,
    "animationEasingUpdate": "cubicInOut",
    "animationDurationUpdate": 2000.0
]

extension EChartsDemoRegistry {
    static let official_scatter_nutrients_matrix = EChartsDemo(
        name: "official-scatter-nutrients-matrix", category: "scatter",
        summary: "营养分布散点矩阵 — Scatter Nutrients Matrix",
        width: 900, height: 560,
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

const axisColors = {
  xAxisLeft: '#2A8339',
  xAxisRight: '#367DA6',
  yAxisTop: '#A68B36',
  yAxisBottom: '#BD5692'
};
const colorBySchema = {};

const fieldIndices = schema.reduce(function (obj, item) {
  obj[item.name] = item.index;
  return obj;
}, {});

const groupCategories = [];
const groupColors = [];
let data;

// PORT-NOTE: upstream `myChart.getZr().configLayer(1, { motionBlur: true })` dropped — the gallery
// page evaluates this script BEFORE echarts.init, and the trail effect only shows during the 2s
// update animation the (removed) app.config onChange triggers.

// PORT-NOTE: upstream `app.config` (the official editor's live axis-field pickers) replaced by its
// initial value; `app.configParameters` / `onChange` removed (the gallery renders one static frame).
const config = {
  xAxisLeft: 'carbohydrate',
  yAxisTop: 'calcium',
  xAxisRight: 'potassium',
  yAxisBottom: 'fiber'
};

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

function makeAxis(dimIndex, id, name, nameLocation) {
  const axisColor = axisColors[id.split('-')[dimIndex]];
  colorBySchema[name] = axisColor;
  return {
    id: id,
    name: name,
    nameLocation: nameLocation,
    nameGap: nameLocation === 'middle' ? 30 : 10,
    gridId: id,
    splitLine: { show: false },
    axisLine: {
      lineStyle: {
        color: axisColor
      }
    },
    axisLabel: {
      color: axisColor
    },
    axisTick: {
      lineStyle: {
        color: axisColor
      }
    }
  };
}

function makeSeriesData(xLeftOrRight, yTopOrBottom) {
  return data.map(function (item, idx) {
    const schemaX = config[xLeftOrRight];
    const schemaY = config[yTopOrBottom];
    return [
      item[fieldIndices[schemaX]], // 0: xValue
      item[fieldIndices[schemaY]], // 1: yValue
      item[1], // 2: group
      item[0], // 3: name
      schemaX, // 4: schemaX
      schemaY, // 5: schemaY
      idx // 6
    ];
  });
}

function makeSeries(xLeftOrRight, yTopOrBottom) {
  let id = xLeftOrRight + '-' + yTopOrBottom;
  return {
    zlevel: 1,
    type: 'scatter',
    name: 'nutrients',
    xAxisId: id,
    yAxisId: id,
    symbolSize: 8,
    emphasis: {
      itemStyle: {
        color: '#fff'
      }
    },
    data: makeSeriesData(xLeftOrRight, yTopOrBottom)
  };
}

function makeDataZoom(opt) {
  return Object.assign(
    {
      type: 'slider',
      filterMode: 'empty',
      realtime: false
    },
    opt
  );
}

function tooltipFormatter(params) {
  // Remove duplicate by data name.
  let mapByDataName = {};
  let mapOnDim = {
    x: {},
    y: {},
    xy: {}
  };
  params.forEach(function (item) {
    let data = item.data;
    let dataName = data[3];
    let mapItem = mapByDataName[dataName] || (mapByDataName[dataName] = {});
    mapItem[data[4]] = data[0];
    mapItem[data[5]] = data[1];
    mapOnDim[item.axisDim][dataName] = mapItem;
  });
  Object.keys(mapByDataName).forEach(function (dataName) {
    if (mapOnDim.x[dataName] && mapOnDim.y[dataName]) {
      mapOnDim.xy[dataName] = mapByDataName[dataName];
      delete mapOnDim.x[dataName];
      delete mapOnDim.y[dataName];
    }
  });
  let resultHTML = [];
  [
    ['xy', 'CROSS'],
    ['x', 'V LINE'],
    ['y', 'H LINE']
  ].forEach(function (dimDefine) {
    let html = [];
    Object.keys(mapOnDim[dimDefine[0]]).forEach(function (dataName) {
      let mapItem = mapOnDim[dimDefine[0]][dataName];
      let valuesHTML = [];
      Object.keys(mapItem).forEach(function (dataName) {
        valuesHTML.push(
          '<span style="color:' +
            colorBySchema[dataName] +
            '">' +
            dataName +
            '</span>: ' +
            mapItem[dataName]
        );
      });
      html.push(
        '<div style="margin: 10px 0">' +
          dataName +
          '<br/>' +
          valuesHTML.join('<br/>') +
          '</div>'
      );
    });
    html.length &&
      resultHTML.push(
        '<div style="margin: 10px 0">' +
          '<div style="font-size: 16px; color: #aaa">POINTS ON ' +
          dimDefine[1] +
          '</div>' +
          html.join('') +
          '</div>'
      );
  });
  return resultHTML.join('');
}

function getOption(data) {
  let gridWidth = '35%';
  let gridHeight = '35%';
  let gridLeft = 80;
  let gridRight = 50;
  let gridTop = 50;
  let gridBottom = 80;

  return {
    tooltip: {
      trigger: 'none',
      padding: [10, 20, 10, 20],
      backgroundColor: 'rgba(0,0,0,0.7)',
      transitionDuration: 0,
      extraCssText: 'width: 300px; white-space: normal',
      textStyle: {
        color: '#fff',
        fontSize: 12
      },
      position: function (pos, params, el, elRect, size) {
        let obj = {};
        obj[['left', 'right'][+(pos[0] < size.viewSize[0] / 2)]] = 60;
        obj[['top', 'bottom'][+(pos[1] < size.viewSize[1] / 2)]] = 20;
        return obj;
      },
      formatter: tooltipFormatter
    },
    axisPointer: {
      show: true,
      snap: true,
      lineStyle: {
        type: 'dashed'
      },
      label: {
        show: true,
        margin: 6,
        backgroundColor: '#556',
        color: '#fff'
      },
      link: [
        {
          xAxisId: ['xAxisLeft-yAxisTop', 'xAxisLeft-yAxisBottom']
        },
        {
          xAxisId: ['xAxisRight-yAxisTop', 'xAxisRight-yAxisBottom']
        },
        {
          yAxisId: ['xAxisLeft-yAxisTop', 'xAxisRight-yAxisTop']
        },
        {
          yAxisId: ['xAxisLeft-yAxisBottom', 'xAxisRight-yAxisBottom']
        }
      ]
    },
    xAxis: [
      makeAxis(0, 'xAxisLeft-yAxisTop', 'carbohydrate', 'middle'),
      makeAxis(0, 'xAxisLeft-yAxisBottom', 'carbohydrate', 'middle'),
      makeAxis(0, 'xAxisRight-yAxisTop', 'potassium', 'middle'),
      makeAxis(0, 'xAxisRight-yAxisBottom', 'potassium', 'middle')
    ],
    yAxis: [
      makeAxis(1, 'xAxisLeft-yAxisTop', 'calcium', 'end'),
      makeAxis(1, 'xAxisLeft-yAxisBottom', 'fiber', 'end'),
      makeAxis(1, 'xAxisRight-yAxisTop', 'calcium', 'end'),
      makeAxis(1, 'xAxisRight-yAxisBottom', 'fiber', 'end')
    ],
    grid: [
      {
        id: 'xAxisLeft-yAxisTop',
        left: gridLeft,
        top: gridTop,
        width: gridWidth,
        height: gridHeight
      },
      {
        id: 'xAxisLeft-yAxisBottom',
        left: gridLeft,
        bottom: gridBottom,
        width: gridWidth,
        height: gridHeight
      },
      {
        id: 'xAxisRight-yAxisTop',
        right: gridRight,
        top: gridTop,
        width: gridWidth,
        height: gridHeight
      },
      {
        id: 'xAxisRight-yAxisBottom',
        right: gridRight,
        bottom: gridBottom,
        width: gridWidth,
        height: gridHeight
      }
    ],
    dataZoom: [
      makeDataZoom({
        width: gridWidth,
        height: 20,
        left: gridLeft,
        bottom: 10,
        xAxisIndex: [0, 1]
      }),
      makeDataZoom({
        width: gridWidth,
        height: 20,
        right: gridRight,
        bottom: 10,
        xAxisIndex: [2, 3]
      }),
      makeDataZoom({
        orient: 'vertical',
        width: 20,
        height: gridHeight,
        left: 10,
        top: gridTop,
        yAxisIndex: [0, 2]
      }),
      makeDataZoom({
        orient: 'vertical',
        width: 20,
        height: gridHeight,
        left: 10,
        bottom: gridBottom,
        yAxisIndex: [1, 3]
      })
    ],
    visualMap: [
      {
        show: false,
        type: 'piecewise',
        categories: groupCategories,
        dimension: 2,
        inRange: {
          color: groupColors //['#d94e5d','#eac736','#50a3ba']
        },
        outOfRange: {
          color: ['#ccc'] //['#d94e5d','#eac736','#50a3ba']
        },
        top: 20,
        textStyle: {
          color: '#fff'
        },
        realtime: false
      }
    ],
    series: [
      makeSeries('xAxisLeft', 'yAxisTop'),
      makeSeries('xAxisLeft', 'yAxisBottom'),
      makeSeries('xAxisRight', 'yAxisTop'),
      makeSeries('xAxisRight', 'yAxisBottom')
    ],
    animationThreshold: 5000,
    progressiveThreshold: 5000,
    animationEasingUpdate: 'cubicInOut',
    animationDurationUpdate: 2000
  };
}

// PORT-NOTE: `$.get(ROOT_PATH + '/data/asset/data/nutrients.json', ...)` -> the asset (mirrored at
// assets/data/nutrients.json) is spliced in verbatim; the callback body is kept as-is.
const originData = \#(nutrientsRawJSON);

data = normalizeData(originData).slice(0, 1000);
option = getOption(data);
"""#,
        option: nutrientsOption)
}
