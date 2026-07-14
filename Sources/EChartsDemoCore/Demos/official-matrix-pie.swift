// official-matrix-pie — replica of https://echarts.apache.org/examples/zh/editor.html?c=matrix-pie
// title: Pie Charts in Matrix / titleCN: 矩阵布局下的饼图
// A 9-column x 6-row `matrix` coordinate system (x header is two-level: 'Primary School' → Grade 1…5,
// 'High School' → Grade 6…9; y header is Class 1…6) carrying 54 tiny `pie` series — one per body cell,
// placed by `coordinateSystem: 'matrix'` + `center: ['Grade i', 'Class j']`, radius 18, two slices
// (Male / Female), labels off. Plus a legend and a tooltip.
//
// DEVIATIONS from the official source:
//   - DATA: upstream is NONDETERMINISTIC — every slice is `Math.round(Math.random() * 10) + 10`
//     (i.e. 10…20), so the two panes (and two renders of the same pane) would never agree and the
//     reference↔port diff would be meaningless. The 54×2 slice values are instead generated ONCE in
//     Swift by a seeded LCG (same shape and range) IN UPSTREAM'S ITERATION ORDER (i = grade outer,
//     j = class inner → index i * yCnt + j), and the SAME array feeds BOTH panes: spliced into
//     webOptionJS as a JSON literal, and used verbatim as the native series data. Everything else —
//     including the `for i / for j` loop that builds the 54 series in the reference pane — is verbatim.
//   - The TS `/* title: ... */` header block is dropped. No closures, no timers, no assets in this
//     example; there is nothing else to change.
//
// CANVAS SIZE (a gallery knob, not part of the option): 60px taller than the tab default. The option
// itself pins `matrix.top: 80` / `matrix.bottom: 80`, so the 6 class-rows plus the two-level grade
// header must share whatever is left; at 460px tall each row is barely the 36px pie diameter and the
// pies touch their cell edges. 520px gives them a margin.
import Foundation

private let matrixPieXCnt = 9
private let matrixPieYCnt = 6

// The random slice values upstream would have produced, made deterministic: a fixed-seed LCG stands in
// for Math.random(). One [Male, Female] pair per body cell, each 10…20, in upstream's push order.
private let matrixPieValues: [[Double]] = {
    var seed: UInt64 = 9_006
    func nextUnit() -> Double {          // deterministic stand-in for Math.random() → [0, 1)
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return Double((seed >> 33) % 1_000_000) / 1_000_000.0
    }
    var values: [[Double]] = []
    for _ in 0..<matrixPieXCnt {         // i (grade) outer …
        for _ in 0..<matrixPieYCnt {     // … j (class) inner — upstream's exact order
            values.append([(nextUnit() * 10).rounded() + 10, (nextUnit() * 10).rounded() + 10])
        }
    }
    return values
}()

// The same array as a JSON literal, spliced into the reference pane's JS (see \#( ... ) below).
private let matrixPieValuesJSON: String = {
    guard let data = try? JSONSerialization.data(withJSONObject: matrixPieValues, options: []),
          let json = String(data: data, encoding: .utf8) else { return "[]" }
    return json
}()

// The 54 pie series — the Swift form of upstream's nested `for i / for j` push loop.
private let matrixPieSeries: [[String: Any]] = {
    var series: [[String: Any]] = []
    for i in 0..<matrixPieXCnt {
        for j in 0..<matrixPieYCnt {
            let values = matrixPieValues[i * matrixPieYCnt + j]
            series.append([
                "type": "pie",
                "coordinateSystem": "matrix",
                "center": ["Grade \(i + 1)", "Class \(j + 1)"],   // x locator, y locator
                "radius": 18.0,
                "data": [
                    ["value": values[0], "name": "Male"] as [String: Any],
                    ["value": values[1], "name": "Female"] as [String: Any]
                ],
                "label": ["show": false] as [String: Any],
                "emphasis": ["label": ["show": false] as [String: Any]] as [String: Any]
            ] as [String: Any])
        }
    }
    return series
}()

// matrix.x: two-level header (a school band per group of grades). matrix.y: flat Class 1…6.
private let matrixPieXData: [[String: Any]] = [
    [
        "value": "Primary School",
        "children": (1...5).map { "Grade \($0)" }
    ] as [String: Any],
    [
        "value": "High School",
        "children": (6...9).map { "Grade \($0)" }
    ] as [String: Any]
]
private let matrixPieYData: [String] = (1...matrixPieYCnt).map { "Class \($0)" }

extension EChartsDemoRegistry {
    static let official_matrix_pie = EChartsDemo(
        name: "official-matrix-pie", category: "matrix",
        summary: "矩阵布局下的饼图 — Pie Charts in Matrix",
        width: 720, height: 520,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
const xCnt = 9;
const yCnt = 6;
// Upstream fills each slice with Math.round(Math.random() * 10) + 10; the identical deterministic
// 54x2 array the native pane uses is inlined here instead, so the two panes are diffable.
const pieValues = \#(matrixPieValuesJSON);
const series = [];
for (let i = 0; i < xCnt; ++i) {
  for (let j = 0; j < yCnt; ++j) {
    series.push({
      type: 'pie',
      coordinateSystem: 'matrix',
      center: [`Grade ${i + 1}`, `Class ${j + 1}`],
      radius: 18,
      data: [
        {
          value: pieValues[i * yCnt + j][0],
          name: 'Male'
        },
        {
          value: pieValues[i * yCnt + j][1],
          name: 'Female'
        }
      ],
      label: {
        show: false
      },
      emphasis: {
        label: {
          show: false
        }
      }
    });
  }
}

option = {
  legend: {
    show: true,
    bottom: 40
  },
  matrix: {
    x: {
      data: [
        {
          value: 'Primary School',
          children: Array.from({ length: 5 }, (_, i) => {
            return `Grade ${i + 1}`;
          })
        },
        {
          value: 'High School',
          children: Array.from({ length: 4 }, (_, i) => {
            return `Grade ${i + 6}`;
          })
        }
      ]
    },
    y: {
      data: Array.from({ length: 6 }, (_, i) => {
        return `Class ${i + 1}`;
      })
    },
    top: 80,
    bottom: 80
  },
  series,
  tooltip: {
    show: true
  }
};
"""#,
        option: [
            "legend": [
                "show": true,
                "bottom": 40.0
            ] as [String: Any],
            "matrix": [
                "x": ["data": matrixPieXData] as [String: Any],
                "y": ["data": matrixPieYData] as [String: Any],
                "top": 80.0,
                "bottom": 80.0
            ] as [String: Any],
            "series": matrixPieSeries,
            "tooltip": [
                "show": true
            ] as [String: Any]
        ])
}
