// official-matrix-periodic-table — replica of
// https://echarts.apache.org/examples/zh/editor.html?c=matrix-periodic-table
// title: Periodic Table / titleCN: 元素周期表
// The periodic table drawn on a `matrix` coordinate system: a 19x10 grid of unlabelled, border-less
// cells, and ONE `custom` series whose 120 data rows are [group, period, atomicNumber, symbol, colour].
// renderItem turns each row into the element's tile (the cell rect, inset by a 2px margin, filled with
// its category colour); label.formatter stacks the atomic number over the symbol inside it. The two
// `null`-numbered rows ('La~Yb', 'Ac~No') are the placeholder tiles that stand in for the lanthanide /
// actinide blocks pulled out below the table. A trailing setTimeout then annotates the table with 11
// italic `graphic` texts ("Nonmetals", "d-block", ...), each positioned by converting a matrix cell
// coordinate to pixels with `myChart.convertToPixel({ matrixIndex: 0 }, [x, y])`.
//
// SIZE: 1040x620, not the gallery default. `matrix.width` is hard-coded to 900 upstream and the matrix
// component is `layoutMode: 'box'` (defaults left/right/top/bottom: '10%'), so the table is a FIXED
// 900px-wide box centred in the canvas — which means the canvas must be WIDER than 900, not equal to it.
// The trailing `graphic` annotations deliberately hang off the table's left edge: 'Nonmetals'/'Metals'
// sit at x = cell(1,1).centre - 70, i.e. ~2px LEFT of the table box, so a 900px canvas (table spanning
// edge to edge) slices them in half. 1040 leaves a 70px margin each side. The height then follows from
// the cells: the grid is 20x11, not 19x10 — the example hides the x/y header LABELS but not the headers
// themselves (`show` defaults true), so they still occupy a row/column. A column is 900/20 = 45px, and
// at 620px of canvas a row is (0.8 * 620)/11 = 45px too — square cells, as on the website.
//
// DEVIATIONS from the official source:
//   - The native pane expresses the JS renderItem and label formatter as a typed CustomSeriesRenderItem.
//     The delayed graphic annotations are emitted as attached texts on the final custom group; their
//     positions use the fixed matrix box geometry and are equivalent to the web pane's convertToPixel.
//   - `series` is an array of one in the Swift option where the source writes the single-series object
//     form (`series: { ... }`) — echarts normalises the two to the same thing.
//   - The example's `/* title: ... */` metadata block is dropped (it is the website's front-matter, not
//     JS). Data inlined: none needed — the source's data is already a literal.
import Foundation
import EChartsKit

// upstream renderItem: one rect per periodic-table cell (inset 2px), filled with the row's colour
//   (dim 4); an "element" cell (dim 2 is a numeric atomic number) gets a 1px #aaa border at full opacity,
//   a category/legend cell (dim 2 non-numeric) is borderless at 0.5 opacity.
private func periodicNum(_ v: Any?) -> Double {
    if let d = v as? Double { return d }
    if let i = v as? Int { return Double(i) }
    if let n = v as? NSNumber { return n.doubleValue }
    if let s = v as? String { return Double(s) ?? .nan }
    return .nan
}
private func periodicString(_ v: Any?) -> String {
    guard let v else { return "" }
    if let s = v as? String { return s }
    let mirror = Mirror(reflecting: v)
    if mirror.displayStyle == .optional {
        return periodicString(mirror.children.first?.value)
    }
    return String(describing: v)
}
private let periodicTableRenderItem: CustomSeriesRenderItem = { _, api in
    let x = api.ordinalRawValue(0.0, nil) ?? api.value(0.0, nil)
    let y = api.ordinalRawValue(1.0, nil) ?? api.value(1.0, nil)
    guard let rect = api.layout([x, y], nil)?.rect else { return nil }
    let atomicNumber = periodicNum(api.value(2.0, nil))
    let isElement = !atomicNumber.isNaN
    let symbol = periodicString(api.ordinalRawValue(3.0, nil) ?? api.value(3.0, nil))
    let label = isElement ? "\(Int(atomicNumber))\n\(symbol)" : "{small|\(symbol)}"
    let margin = 2.0
    let tile: [String: Any] = [
        "type": "rect",
        "shape": [
            "x": rect.x + margin, "y": rect.y + margin,
            "width": rect.width - margin * 2, "height": rect.height - margin * 2
        ] as [String: Any],
        "style": api.style([
            "fill": api.ordinalRawValue(4.0, nil) ?? api.value(4.0, nil) as Any,
            "stroke": "#aaa",
            "lineWidth": isElement ? 1.0 : 0.0,
            "opacity": isElement ? 1.0 : 0.5
        ] as [String: Any], nil),
        "textConfig": ["position": "inside"] as [String: Any],
        "textContent": [
            "type": "text",
            "style": [
                "text": label,
                "fill": "#555",
                "fontSize": 14.0,
                "align": "center",
                "verticalAlign": "middle",
                "rich": [
                    "small": ["fontSize": 12.0, "fill": "#777"] as [String: Any]
                ] as [String: Any]
            ] as [String: Any]
        ] as [String: Any]
    ]
    if symbol == "Ac~No" {
        return [
            "type": "group",
            "children": [tile] + periodicTableGraphicElements()
        ] as [String: Any]
    }
    return tile
}

// The four category colours (upstream's `const colors`), reused by every data row below.
private let periodicRed = "#f88"
private let periodicGreen = "#8f8"
private let periodicBlue = "#8bf"
private let periodicYellow = "#ff8"

// matrix.x.data / matrix.y.data — upstream's Array.from({ length: N }, (_, i) => i + 1 + ''):
// the 19 groups and the 10 rows (7 periods + a spacer + the lanthanide / actinide rows).
private let periodicTableXData: [String] = (1...19).map { String($0) }
private let periodicTableYData: [String] = (1...10).map { String($0) }

// [matrix x, matrix y, text, dx, dy] — mirrors the web pane's delayed graphic rows.
private let periodicTableAnnotationData: [[Any]] = [
    ["2", "9", "Lanthanides", 20.0, 0.0],
    ["2", "10", "Actinides", 20.0, 0.0],
    ["1", "1", "Nonmetals", -70.0, 0.0],
    ["1", "2", "Metals", -70.0, 0.0],
    ["19", "1", "Noble gases", 0.0, -40.0],
    ["9", "3", "Transition metals\n(somtimes excl. group 12)", -25.0, 0.0],
    ["1", "8", "s-block\n(incl. He)", 20.0, -3.0],
    ["3", "8", "f-block", 0.0, -10.0],
    ["9", "8", "d-block", -25.0, -10.0],
    ["17", "8", "p-block (excl. He)", -25.0, -10.0],
    ["16", "1", "Some elements near\nthe dashed staircase are\nsometimes called metalloids", 0.0, 0.0]
]

private func periodicTableGraphicElements() -> [[String: Any]] {
    // Matrix box: width 900 centered in 1040; default top/bottom are 10% of 620. The hidden headers
    // still occupy one column/row, so convertToPixel(category) uses 20 columns and 11 rows.
    let left = 70.0
    let top = 62.0
    let cellWidth = 900.0 / 20.0
    let cellHeight = (620.0 - top * 2.0) / 11.0
    return periodicTableAnnotationData.compactMap { row in
        guard row.count == 5,
              let x = Double(row[0] as? String ?? ""),
              let y = Double(row[1] as? String ?? ""),
              let text = row[2] as? String,
              let dx = row[3] as? Double,
              let dy = row[4] as? Double else { return nil }
        return [
            "type": "rect",
            "shape": [
                "x": left + cellWidth * (x + 0.5) + dx,
                "y": top + cellHeight * (y + 0.5) + dy,
                "width": 0.0,
                "height": 0.0
            ] as [String: Any],
            "style": ["fill": "rgba(0,0,0,0)", "opacity": 0.0] as [String: Any],
            "z2": 100.0,
            "silent": true,
            "textConfig": ["position": "inside"] as [String: Any],
            "textContent": [
                "type": "text",
                "style": [
                    "text": text,
                    "fill": "#333",
                    "font": "italic bold 14px sans-serif",
                    "textAlign": "center",
                    "textVerticalAlign": "middle"
                ] as [String: Any]
            ] as [String: Any]
        ] as [String: Any]
    }
}

extension EChartsDemoRegistry {
    static let official_matrix_periodic_table = EChartsDemo(
        name: "official-matrix-periodic-table", category: "matrix",
        summary: "元素周期表 — Periodic Table",
        width: 1040, height: 620,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
const colors = {
  red: '#f88',
  green: '#8f8',
  blue: '#8bf',
  yellow: '#ff8'
};

option = {
  matrix: {
    x: {
      data: Array.from({ length: 19 }, (_, i) => i + 1 + ''),
      label: {
        show: false
      },
      itemStyle: {
        borderWidth: 0
      },
      dividerLineStyle: {
        width: 0
      }
    },
    y: {
      data: Array.from({ length: 10 }, (_, i) => i + 1 + ''),
      label: {
        show: false
      },
      itemStyle: {
        borderWidth: 0
      },
      dividerLineStyle: {
        width: 0
      }
    },
    left: 'center',
    width: 900,
    backgroundStyle: {
      borderWidth: 0
    },
    body: {
      itemStyle: {
        borderWidth: 0
      }
    }
  },
  series: {
    type: 'custom',
    coordinateSystem: 'matrix',
    data: [
      ['1', '1', '1', 'H', colors.red],
      ['19', '1', '2', 'He', colors.red],
      ['1', '2', '3', 'Li', colors.red],
      ['2', '2', '4', 'Be', colors.red],
      ['14', '2', '5', 'B', colors.yellow],
      ['15', '2', '6', 'C', colors.yellow],
      ['16', '2', '7', 'N', colors.yellow],
      ['17', '2', '8', 'O', colors.yellow],
      ['18', '2', '9', 'F', colors.yellow],
      ['19', '2', '10', 'Ne', colors.yellow],
      ['1', '3', '11', 'Na', colors.red],
      ['2', '3', '12', 'Mg', colors.red],
      ['14', '3', '13', 'Al', colors.yellow],
      ['15', '3', '14', 'Si', colors.yellow],
      ['16', '3', '15', 'P', colors.yellow],
      ['17', '3', '16', 'S', colors.yellow],
      ['18', '3', '17', 'Cl', colors.yellow],
      ['19', '3', '18', 'Ar', colors.yellow],
      ['1', '4', '19', 'K', colors.red],
      ['2', '4', '20', 'Ca', colors.red],
      ['4', '4', '21', 'Sc', colors.blue],
      ['5', '4', '22', 'Ti', colors.blue],
      ['6', '4', '23', 'V', colors.blue],
      ['7', '4', '24', 'Cr', colors.blue],
      ['8', '4', '25', 'Mn', colors.blue],
      ['9', '4', '26', 'Fe', colors.blue],
      ['10', '4', '27', 'Co', colors.blue],
      ['11', '4', '28', 'Ni', colors.blue],
      ['12', '4', '29', 'Cu', colors.blue],
      ['13', '4', '30', 'Zn', colors.blue],
      ['14', '4', '31', 'Ga', colors.yellow],
      ['15', '4', '32', 'Ge', colors.yellow],
      ['16', '4', '33', 'As', colors.yellow],
      ['17', '4', '34', 'Se', colors.yellow],
      ['18', '4', '35', 'Br', colors.yellow],
      ['19', '4', '36', 'Kr', colors.yellow],
      ['1', '5', '37', 'Rb', colors.red],
      ['2', '5', '38', 'Sr', colors.red],
      ['4', '5', '39', 'Y', colors.blue],
      ['5', '5', '40', 'Zr', colors.blue],
      ['6', '5', '41', 'Nb', colors.blue],
      ['7', '5', '42', 'Mo', colors.blue],
      ['8', '5', '43', 'Tc', colors.blue],
      ['9', '5', '44', 'Ru', colors.blue],
      ['10', '5', '45', 'Rh', colors.blue],
      ['11', '5', '46', 'Pd', colors.blue],
      ['12', '5', '47', 'Ag', colors.blue],
      ['13', '5', '48', 'Cd', colors.blue],
      ['14', '5', '49', 'In', colors.yellow],
      ['15', '5', '50', 'Sn', colors.yellow],
      ['16', '5', '51', 'Sb', colors.yellow],
      ['17', '5', '52', 'Te', colors.yellow],
      ['18', '5', '53', 'I', colors.yellow],
      ['19', '5', '54', 'Xe', colors.yellow],
      ['1', '6', '55', 'Cs', colors.red],
      ['2', '6', '56', 'Ba', colors.red],
      ['4', '9', '57', 'La', colors.green],
      ['5', '9', '58', 'Ce', colors.green],
      ['6', '9', '59', 'Pr', colors.green],
      ['7', '9', '60', 'Nd', colors.green],
      ['8', '9', '61', 'Pm', colors.green],
      ['9', '9', '62', 'Sm', colors.green],
      ['10', '9', '63', 'Eu', colors.green],
      ['11', '9', '64', 'Gd', colors.green],
      ['12', '9', '65', 'Tb', colors.green],
      ['13', '9', '66', 'Dy', colors.green],
      ['14', '9', '67', 'Ho', colors.green],
      ['15', '9', '68', 'Er', colors.green],
      ['16', '9', '69', 'Tm', colors.green],
      ['17', '9', '70', 'Yb', colors.green],
      ['4', '6', '71', 'Lu', colors.blue],
      ['5', '6', '72', 'Hf', colors.blue],
      ['6', '6', '73', 'Ta', colors.blue],
      ['7', '6', '74', 'W', colors.blue],
      ['8', '6', '75', 'Re', colors.blue],
      ['9', '6', '76', 'Os', colors.blue],
      ['10', '6', '77', 'Ir', colors.blue],
      ['11', '6', '78', 'Pt', colors.blue],
      ['12', '6', '79', 'Au', colors.blue],
      ['13', '6', '80', 'Hg', colors.blue],
      ['14', '6', '81', 'Tl', colors.yellow],
      ['15', '6', '82', 'Pb', colors.yellow],
      ['16', '6', '83', 'Bi', colors.yellow],
      ['17', '6', '84', 'Po', colors.yellow],
      ['18', '6', '85', 'At', colors.yellow],
      ['19', '6', '86', 'Rn', colors.yellow],
      ['1', '7', '87', 'Fr', colors.red],
      ['2', '7', '88', 'Ra', colors.red],
      ['4', '10', '89', 'Ac', colors.green],
      ['5', '10', '90', 'Th', colors.green],
      ['6', '10', '91', 'Pa', colors.green],
      ['7', '10', '92', 'U', colors.green],
      ['8', '10', '93', 'Np', colors.green],
      ['9', '10', '94', 'Pu', colors.green],
      ['10', '10', '95', 'Am', colors.green],
      ['11', '10', '96', 'Cm', colors.green],
      ['12', '10', '97', 'Bk', colors.green],
      ['13', '10', '98', 'Cf', colors.green],
      ['14', '10', '99', 'Es', colors.green],
      ['15', '10', '100', 'Fm', colors.green],
      ['16', '10', '101', 'Md', colors.green],
      ['17', '10', '102', 'No', colors.green],
      ['4', '7', '103', 'Lr', colors.blue],
      ['5', '7', '104', 'Rf', colors.blue],
      ['6', '7', '105', 'Db', colors.blue],
      ['7', '7', '106', 'Sg', colors.blue],
      ['8', '7', '107', 'Bh', colors.blue],
      ['9', '7', '108', 'Hs', colors.blue],
      ['10', '7', '109', 'Mt', colors.blue],
      ['11', '7', '110', 'Ds', colors.blue],
      ['12', '7', '111', 'Rg', colors.blue],
      ['13', '7', '112', 'Cn', colors.blue],
      ['14', '7', '113', 'Nh', colors.yellow],
      ['15', '7', '114', 'Fl', colors.yellow],
      ['16', '7', '115', 'Mc', colors.yellow],
      ['17', '7', '116', 'Lv', colors.yellow],
      ['18', '7', '117', 'Ts', colors.yellow],
      ['19', '7', '118', 'Og', colors.yellow],

      ['3', '6', null, 'La~Yb', colors.green],
      ['3', '7', null, 'Ac~No', colors.green]
    ],
    label: {
      show: true,
      formatter: (params) => {
        if (params.value[2] == null) {
          return '{small|' + params.value[3] + '}';
        }
        return params.value[2] + '\n' + params.value[3];
      },
      rich: {
        small: {
          fontSize: 12,
          color: '#777'
        }
      },
      textStyle: {
        fontSize: 14,
        color: '#555',
        align: 'center'
      }
    },
    renderItem: function (params, api) {
      const x = api.value(0);
      const y = api.value(1);
      const rect = api.layout([x, y]).rect;
      const isElement = !isNaN(api.value(2));
      const margin = 2;
      return {
        type: 'rect',
        shape: {
          x: rect.x + margin,
          y: rect.y + margin,
          width: rect.width - margin * 2,
          height: rect.height - margin * 2
        },
        style: api.style({
          fill: api.value(4),
          stroke: '#aaa',
          lineWidth: isElement ? 1 : 0,
          opacity: isElement ? 1 : 0.5
        })
      };
    }
  }
};

setTimeout(function () {
  const elements = [
    ['2', '9', 'Lanthanides', 20],
    ['2', '10', 'Actinides', 20],
    ['1', '1', 'Nonmetals', -70],
    ['1', '2', 'Metals', -70],
    ['19', '1', 'Noble gases', 0, -40],
    ['9', '3', 'Transition metals\n(somtimes excl. group 12)', -25],
    ['1', '8', 's-block\n(incl. He)', 20, -3],
    ['3', '8', 'f-block', 0, -10],
    ['9', '8', 'd-block', -25, -10],
    ['17', '8', 'p-block (excl. He)', -25, -10],
    [
      '16',
      '1',
      'Some elements near\nthe dashed staircase are\nsometimes called metalloids'
    ]
  ].map((row) => {
    const center = myChart.convertToPixel(
      {
        matrixIndex: 0
      },
      row.slice(0, 2)
    );
    return {
      type: 'text',
      style: {
        text: row[2],
        fill: '#333',
        font: 'italic bold 14px sans-serif',
        textAlign: 'center',
        textVerticalAlign: 'middle'
      },
      x: center[0] + (row[3] || 0),
      y: center[1] + (row[4] || 0)
    };
  });

  myChart.setOption({
    graphic: {
      elements
    }
  });
});
"""#,
        option: [
            "matrix": [
                "x": [
                    "data": periodicTableXData,
                    "label": ["show": false] as [String: Any],
                    "itemStyle": ["borderWidth": 0.0] as [String: Any],
                    "dividerLineStyle": ["width": 0.0] as [String: Any]
                ] as [String: Any],
                "y": [
                    "data": periodicTableYData,
                    "label": ["show": false] as [String: Any],
                    "itemStyle": ["borderWidth": 0.0] as [String: Any],
                    "dividerLineStyle": ["width": 0.0] as [String: Any]
                ] as [String: Any],
                "left": "center",
                "width": 900.0,
                "backgroundStyle": ["borderWidth": 0.0] as [String: Any],
                "body": [
                    "itemStyle": ["borderWidth": 0.0] as [String: Any]
                ] as [String: Any]
            ] as [String: Any],
            "series": [
                [
                    "type": "custom",
                    "coordinateSystem": "matrix",
                    "renderItem": periodicTableRenderItem,
                    "data": periodicTableData as [Any],
                    "label": [
                        "show": true,
                        "rich": [
                            "small": ["fontSize": 12.0, "color": "#777"] as [String: Any]
                        ] as [String: Any],
                        "textStyle": [
                            "fontSize": 14.0,
                            "color": "#555",
                            "align": "center"
                        ] as [String: Any]
                    ] as [String: Any]
                ] as [String: Any]
            ]
        ])
}

// The series data: [group (matrix x), period (matrix y), atomic number, symbol, category colour].
// The last two rows carry NSNull for the atomic number — the 'La~Yb' / 'Ac~No' placeholder tiles that
// sit in the main table where the lanthanides / actinides were pulled out (renderItem draws those
// border-less and half-transparent; the label formatter shrinks their text).
private let periodicTableData: [[Any]] = [
    ["1", "1", "1", "H", periodicRed],
    ["19", "1", "2", "He", periodicRed],
    ["1", "2", "3", "Li", periodicRed],
    ["2", "2", "4", "Be", periodicRed],
    ["14", "2", "5", "B", periodicYellow],
    ["15", "2", "6", "C", periodicYellow],
    ["16", "2", "7", "N", periodicYellow],
    ["17", "2", "8", "O", periodicYellow],
    ["18", "2", "9", "F", periodicYellow],
    ["19", "2", "10", "Ne", periodicYellow],
    ["1", "3", "11", "Na", periodicRed],
    ["2", "3", "12", "Mg", periodicRed],
    ["14", "3", "13", "Al", periodicYellow],
    ["15", "3", "14", "Si", periodicYellow],
    ["16", "3", "15", "P", periodicYellow],
    ["17", "3", "16", "S", periodicYellow],
    ["18", "3", "17", "Cl", periodicYellow],
    ["19", "3", "18", "Ar", periodicYellow],
    ["1", "4", "19", "K", periodicRed],
    ["2", "4", "20", "Ca", periodicRed],
    ["4", "4", "21", "Sc", periodicBlue],
    ["5", "4", "22", "Ti", periodicBlue],
    ["6", "4", "23", "V", periodicBlue],
    ["7", "4", "24", "Cr", periodicBlue],
    ["8", "4", "25", "Mn", periodicBlue],
    ["9", "4", "26", "Fe", periodicBlue],
    ["10", "4", "27", "Co", periodicBlue],
    ["11", "4", "28", "Ni", periodicBlue],
    ["12", "4", "29", "Cu", periodicBlue],
    ["13", "4", "30", "Zn", periodicBlue],
    ["14", "4", "31", "Ga", periodicYellow],
    ["15", "4", "32", "Ge", periodicYellow],
    ["16", "4", "33", "As", periodicYellow],
    ["17", "4", "34", "Se", periodicYellow],
    ["18", "4", "35", "Br", periodicYellow],
    ["19", "4", "36", "Kr", periodicYellow],
    ["1", "5", "37", "Rb", periodicRed],
    ["2", "5", "38", "Sr", periodicRed],
    ["4", "5", "39", "Y", periodicBlue],
    ["5", "5", "40", "Zr", periodicBlue],
    ["6", "5", "41", "Nb", periodicBlue],
    ["7", "5", "42", "Mo", periodicBlue],
    ["8", "5", "43", "Tc", periodicBlue],
    ["9", "5", "44", "Ru", periodicBlue],
    ["10", "5", "45", "Rh", periodicBlue],
    ["11", "5", "46", "Pd", periodicBlue],
    ["12", "5", "47", "Ag", periodicBlue],
    ["13", "5", "48", "Cd", periodicBlue],
    ["14", "5", "49", "In", periodicYellow],
    ["15", "5", "50", "Sn", periodicYellow],
    ["16", "5", "51", "Sb", periodicYellow],
    ["17", "5", "52", "Te", periodicYellow],
    ["18", "5", "53", "I", periodicYellow],
    ["19", "5", "54", "Xe", periodicYellow],
    ["1", "6", "55", "Cs", periodicRed],
    ["2", "6", "56", "Ba", periodicRed],
    ["4", "9", "57", "La", periodicGreen],
    ["5", "9", "58", "Ce", periodicGreen],
    ["6", "9", "59", "Pr", periodicGreen],
    ["7", "9", "60", "Nd", periodicGreen],
    ["8", "9", "61", "Pm", periodicGreen],
    ["9", "9", "62", "Sm", periodicGreen],
    ["10", "9", "63", "Eu", periodicGreen],
    ["11", "9", "64", "Gd", periodicGreen],
    ["12", "9", "65", "Tb", periodicGreen],
    ["13", "9", "66", "Dy", periodicGreen],
    ["14", "9", "67", "Ho", periodicGreen],
    ["15", "9", "68", "Er", periodicGreen],
    ["16", "9", "69", "Tm", periodicGreen],
    ["17", "9", "70", "Yb", periodicGreen],
    ["4", "6", "71", "Lu", periodicBlue],
    ["5", "6", "72", "Hf", periodicBlue],
    ["6", "6", "73", "Ta", periodicBlue],
    ["7", "6", "74", "W", periodicBlue],
    ["8", "6", "75", "Re", periodicBlue],
    ["9", "6", "76", "Os", periodicBlue],
    ["10", "6", "77", "Ir", periodicBlue],
    ["11", "6", "78", "Pt", periodicBlue],
    ["12", "6", "79", "Au", periodicBlue],
    ["13", "6", "80", "Hg", periodicBlue],
    ["14", "6", "81", "Tl", periodicYellow],
    ["15", "6", "82", "Pb", periodicYellow],
    ["16", "6", "83", "Bi", periodicYellow],
    ["17", "6", "84", "Po", periodicYellow],
    ["18", "6", "85", "At", periodicYellow],
    ["19", "6", "86", "Rn", periodicYellow],
    ["1", "7", "87", "Fr", periodicRed],
    ["2", "7", "88", "Ra", periodicRed],
    ["4", "10", "89", "Ac", periodicGreen],
    ["5", "10", "90", "Th", periodicGreen],
    ["6", "10", "91", "Pa", periodicGreen],
    ["7", "10", "92", "U", periodicGreen],
    ["8", "10", "93", "Np", periodicGreen],
    ["9", "10", "94", "Pu", periodicGreen],
    ["10", "10", "95", "Am", periodicGreen],
    ["11", "10", "96", "Cm", periodicGreen],
    ["12", "10", "97", "Bk", periodicGreen],
    ["13", "10", "98", "Cf", periodicGreen],
    ["14", "10", "99", "Es", periodicGreen],
    ["15", "10", "100", "Fm", periodicGreen],
    ["16", "10", "101", "Md", periodicGreen],
    ["17", "10", "102", "No", periodicGreen],
    ["4", "7", "103", "Lr", periodicBlue],
    ["5", "7", "104", "Rf", periodicBlue],
    ["6", "7", "105", "Db", periodicBlue],
    ["7", "7", "106", "Sg", periodicBlue],
    ["8", "7", "107", "Bh", periodicBlue],
    ["9", "7", "108", "Hs", periodicBlue],
    ["10", "7", "109", "Mt", periodicBlue],
    ["11", "7", "110", "Ds", periodicBlue],
    ["12", "7", "111", "Rg", periodicBlue],
    ["13", "7", "112", "Cn", periodicBlue],
    ["14", "7", "113", "Nh", periodicYellow],
    ["15", "7", "114", "Fl", periodicYellow],
    ["16", "7", "115", "Mc", periodicYellow],
    ["17", "7", "116", "Lv", periodicYellow],
    ["18", "7", "117", "Ts", periodicYellow],
    ["19", "7", "118", "Og", periodicYellow],

    ["3", "6", NSNull(), "La~Yb", periodicGreen],
    ["3", "7", NSNull(), "Ac~No", periodicGreen]
]
