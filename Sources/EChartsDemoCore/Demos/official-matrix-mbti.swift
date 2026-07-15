// official-matrix-mbti — replica of https://echarts.apache.org/examples/zh/editor.html?c=matrix-mbti
// title: MBTI Partner Compatibility / titleCN: MBTI 伴侣相容性
// A 16x16 compatibility matrix of the MBTI types on a `matrix` coordinate system. The x/y axes are
// two-level (four temperament groups NF/NT/SJ/SP, each with four types); the body is a `heatmap`
// series whose cells carry a per-cell `decal` (a circle pattern colored by the row/column group) and
// a hidden `continuous` visualMap on dimension 2 that maps compatibility (0..1) to opacity. A second
// `scatter` series (symbolSize 0, silent) sits on top only to print each cell's percentage label.
// Clicking anywhere toggles the detail view for a 4x4 group-median view.
//
// DEVIATIONS from the official source:
//   - window.innerWidth / window.innerHeight — the source sizes the matrix and picks font sizes from
//     the live window (`size = round(min(innerW, innerH) * 0.9)`, group/item/value font 24/13/15 vs
//     16/11/12, matrix `left = (innerW - size)/2`). Kept VERBATIM in the web pane (it is real example
//     behavior). The native option cannot read a window, so it pins the matrix to width/height 360 at
//     left 180 / top 50 (fits the 720x460 pane) and takes the desktop (>700) font branch (group 24,
//     item 13). getColor()'s lightness/group logic is deterministic, so every color the JS closures
//     compute is precomputed in Swift and baked into the data — colors are NOT a deviation.
//   - Function-valued keys omitted from the native option (each marked PORT-NOTE): tooltip.formatter
//     (colored "<B> / <A> : NN%"), and detail-scatter series label.formatter (`round(value[2]*100)+'%'`).
//     The scatter series exists only to render those percentage labels, so with the formatter gone the
//     native pane shows no per-cell percentages. Kept verbatim in the web pane.
//   - Click-to-toggle grouping is pure `myChart.on('click', ...)` interaction: kept verbatim in the web
//     pane (both the detail and group series are built there); the native pane is not driven (per the
//     harness's rule that pure-click examples need no `drive`), so it stays on the initial detail view.
//   - NATIVE PANE: nativeSupported: false — but the original blocker (no matrix branch in HeatmapView) is
//     GONE: HeatmapView._renderOnMatrix now lays out all 256 cells on the matrix coord, so the native pane
//     draws the 16x16 grid. It still diverges from the reference on FOUR counts, hence stays off:
//       (1) Cell COLOUR — each datum bakes an itemStyle.color (green/purple/blue/orange by group), but the
//           cells render GREYSCALE: the continuous visualMap (dimension 2 → inRange.opacity only) leaves a
//           default grey value ramp in the visual pipeline that overrides the baked colour. The visualMap
//           should modulate only opacity here.
//       (2) Two-level GROUP HEADERS (NF/NT/SJ/SP + the per-type IN/FJ… stacks on both axes) are not drawn.
//       (3) Per-cell DECAL circle patterns are not drawn.
//       (4) Per-cell PERCENTAGE labels come from the detail-`scatter` series' `label.formatter` — a JS
//           closure (`round(value[2]*100)+'%'`), which is necessarily OMITTED from the static native option.
//           These labels sit in every one of the 256 cells, so this one alone keeps the native pane from
//           ever matching the reference, independent of (1)–(3).
//     Because (4) is unreachable without a live formatter, the pane stays off even once (1)–(3) land.
extension EChartsDemoRegistry {
    static let official_matrix_mbti = EChartsDemo(
        name: "official-matrix-mbti", category: "matrix",
        summary: "MBTI 伴侣相容性 — MBTI Partner Compatibility",
        width: 720, height: 460,
        nativeSupported: false,
        collection: .official,
        webOptionJS: #"""
// Click on the data to toggle grouping

const mbti = [
  'ENFJ',
  'ENFP',
  'ENTJ',
  'ENTP',
  'ESFJ',
  'ESFP',
  'ESTJ',
  'ESTP',
  'INFJ',
  'INFP',
  'INTJ',
  'INTP',
  'ISFJ',
  'ISFP',
  'ISTJ',
  'ISTP'
];

const color = {
  green: '#2D9A69',
  purple: '#7D568F',
  blue: '#3A8DAB',
  yellow: '#E0A433',

  greenLighter: '#10CA77',
  purpleLighter: '#9253AF',
  blueLighter: '#26A9D9',
  yellowLighter: '#F4AC24',

  greenDarker: '#0FB369',
  purpleDarker: '#854AA0',
  blueDarker: '#2298C3',
  yellowDarker: '#F2A30D'
};
const fontSize = {
  group: window.innerHeight > 700 ? 24 : 16,
  item: window.innerHeight > 700 ? 13 : 11,
  value: window.innerHeight > 700 ? 15 : 12
};

const getColor = (mbti, lightness = 0) => {
  if (mbti.indexOf('NF') >= 0) {
    return lightness < 0
      ? color.greenLighter
      : lightness > 0
      ? color.greenDarker
      : color.green;
  }
  if (mbti.indexOf('NT') >= 0) {
    return lightness < 0
      ? color.purpleLighter
      : lightness > 0
      ? color.purpleDarker
      : color.purple;
  }
  if (mbti.indexOf('S') >= 0 && mbti.indexOf('J') >= 0) {
    return lightness < 0
      ? color.blueLighter
      : lightness > 0
      ? color.blueDarker
      : color.blue;
  }
  if (mbti.indexOf('S') >= 0 && mbti.indexOf('P') >= 0) {
    return lightness < 0
      ? color.yellowLighter
      : lightness > 0
      ? color.yellowDarker
      : color.yellow;
  }
};

const generateGroup = (groupName) => {
  const colorMap = {
    NF: color.green,
    NT: color.purple,
    SJ: color.blue,
    SP: color.yellow
  };
  const groupMembers = {
    NF: ['INFJ', 'INFP', 'ENFJ', 'ENFP'],
    NT: ['INTJ', 'INTP', 'ENTJ', 'ENTP'],
    SJ: ['ISFJ', 'ISTJ', 'ESFJ', 'ESTJ'],
    SP: ['ISFP', 'ISTP', 'ESFP', 'ESTP']
  };
  return {
    value: groupName,
    label: {
      color: colorMap[groupName],
      fontSize: fontSize.group,
      fontWeight: 'bolder',
      padding: 0
    },
    children: groupMembers[groupName].map((mbti) => ({
      value: mbti,
      label: {
        color: colorMap[groupName],
        fontSize: fontSize.item,
        fontWeight: 'bold'
      }
    }))
  };
};

const xData = [
  generateGroup('NF'),
  generateGroup('NT'),
  generateGroup('SJ'),
  generateGroup('SP')
];
const yData = [
  generateGroup('NF'),
  generateGroup('NT'),
  generateGroup('SJ'),
  generateGroup('SP')
];

const originalData = [
  ['ENFJ', 'ENFJ', 0.86],
  ['ENFJ', 'ENFP', 0.91],
  ['ENFJ', 'ENTJ', 0.42],
  ['ENFJ', 'ENTP', 0.73],
  ['ENFJ', 'ESFJ', 0.64],
  ['ENFJ', 'ESFP', 0.8],
  ['ENFJ', 'ESTJ', 0.22],
  ['ENFJ', 'ESTP', 0.41],
  ['ENFJ', 'INFJ', 0.74],
  ['ENFJ', 'INFP', 0.73],
  ['ENFJ', 'INTJ', 0.16],
  ['ENFJ', 'INTP', 0.35],
  ['ENFJ', 'ISFJ', 0.3],
  ['ENFJ', 'ISFP', 0.4],
  ['ENFJ', 'ISTJ', 0.18],
  ['ENFJ', 'ISTP', 0.09],

  ['ENFP', 'ENFJ', 0.91],
  ['ENFP', 'ENFP', 0.97],
  ['ENFP', 'ENTJ', 0.37],
  ['ENFP', 'ENTP', 0.85],
  ['ENFP', 'ESFJ', 0.42],
  ['ENFP', 'ESFP', 0.93],
  ['ENFP', 'ESTJ', 0.27],
  ['ENFP', 'ESTP', 0.76],
  ['ENFP', 'INFJ', 0.51],
  ['ENFP', 'INFP', 0.73],
  ['ENFP', 'INTJ', 0.13],
  ['ENFP', 'INTP', 0.36],
  ['ENFP', 'ISFJ', 0.11],
  ['ENFP', 'ISFP', 0.49],
  ['ENFP', 'ISTJ', 0.04],
  ['ENFP', 'ISTP', 0.14],

  ['ENTJ', 'ENFJ', 0.42],
  ['ENTJ', 'ENFP', 0.37],
  ['ENTJ', 'ENTJ', 0.91],
  ['ENTJ', 'ENTP', 0.81],
  ['ENTJ', 'ESFJ', 0.53],
  ['ENTJ', 'ESFP', 0.51],
  ['ENTJ', 'ESTJ', 0.87],
  ['ENTJ', 'ESTP', 0.74],
  ['ENTJ', 'INFJ', 0.25],
  ['ENTJ', 'INFP', 0.13],
  ['ENTJ', 'INTJ', 0.46],
  ['ENTJ', 'INTP', 0.47],
  ['ENTJ', 'ISFJ', 0.29],
  ['ENTJ', 'ISFP', 0.06],
  ['ENTJ', 'ISTJ', 0.66],
  ['ENTJ', 'ISTP', 0.41],

  ['ENTP', 'ENFJ', 0.73],
  ['ENTP', 'ENFP', 0.64],
  ['ENTP', 'ENTJ', 0.81],
  ['ENTP', 'ENTP', 0.94],
  ['ENTP', 'ESFJ', 0.32],
  ['ENTP', 'ESFP', 0.87],
  ['ENTP', 'ESTJ', 0.7],
  ['ENTP', 'ESTP', 0.92],
  ['ENTP', 'INFJ', 0.11],
  ['ENTP', 'INFP', 0.35],
  ['ENTP', 'INTJ', 0.22],
  ['ENTP', 'INTP', 0.51],
  ['ENTP', 'ISFJ', 0.05],
  ['ENTP', 'ISFP', 0.14],
  ['ENTP', 'ISTJ', 0.11],
  ['ENTP', 'ISTP', 0.35],

  ['ESFJ', 'ESFJ', 0.94],
  ['ESFJ', 'ESFP', 0.4],
  ['ESFJ', 'ESTJ', 0.77],
  ['ESFJ', 'ESTP', 0.37],
  ['ESFJ', 'INFJ', 0.74],
  ['ESFJ', 'INFP', 0.17],
  ['ESFJ', 'INTJ', 0.32],
  ['ESFJ', 'INTP', 0.05],
  ['ESFJ', 'ISFJ', 0.79],
  ['ESFJ', 'ISFP', 0.57],
  ['ESFJ', 'ISTJ', 0.71],
  ['ESFJ', 'ISTP', 0.19],

  ['ESFP', 'ESFP', 0.7],
  ['ESFP', 'ESTJ', 0.39],
  ['ESFP', 'ESTP', 0.75],
  ['ESFP', 'INFJ', 0.43],
  ['ESFP', 'INFP', 0.58],
  ['ESFP', 'INTJ', 0.22],
  ['ESFP', 'INTP', 0.39],
  ['ESFP', 'ISFJ', 0.12],
  ['ESFP', 'ISFP', 0.58],
  ['ESFP', 'ISTJ', 0.08],
  ['ESFP', 'ISTP', 0.26],

  ['ESTJ', 'ESTJ', 0.96],
  ['ESTJ', 'ESTP', 0.78],
  ['ESTJ', 'INFJ', 0.14],
  ['ESTJ', 'INFP', 0.03],
  ['ESTJ', 'INTJ', 0.33],
  ['ESTJ', 'INTP', 0.22],
  ['ESTJ', 'ISFJ', 0.48],
  ['ESTJ', 'ISFP', 0.22],
  ['ESTJ', 'ISTJ', 0.79],
  ['ESTJ', 'ISTP', 0.55],

  ['ESTP', 'ESTP', 0.95],
  ['ESTP', 'INFJ', 0.05],
  ['ESTP', 'INFP', 0.24],
  ['ESTP', 'INTJ', 0.17],
  ['ESTP', 'INTP', 0.39],
  ['ESTP', 'ISFJ', 0.12],
  ['ESTP', 'ISFP', 0.43],
  ['ESTP', 'ISTJ', 0.2],
  ['ESTP', 'ISTP', 0.62],

  ['INFJ', 'INFJ', 0.95],
  ['INFJ', 'INFP', 0.85],
  ['INFJ', 'INTJ', 0.65],
  ['INFJ', 'INTP', 0.5],
  ['INFJ', 'ISFJ', 0.85],
  ['INFJ', 'ISFP', 0.58],
  ['INFJ', 'ISTJ', 0.53],
  ['INFJ', 'ISTP', 0.23],

  ['INFP', 'INFP', 0.97],
  ['INFP', 'INTJ', 0.7],
  ['INFP', 'INTP', 0.84],
  ['INFP', 'ISFJ', 0.46],
  ['INFP', 'ISFP', 0.78],
  ['INFP', 'ISTJ', 0.21],
  ['INFP', 'ISTP', 0.49],

  ['INTJ', 'INTJ', 0.86],
  ['INTJ', 'INTP', 0.89],
  ['INTJ', 'ISFJ', 0.79],
  ['INTJ', 'ISFP', 0.45],
  ['INTJ', 'ISTJ', 0.85],
  ['INTJ', 'ISTP', 0.78],

  ['INTP', 'INTP', 0.96],
  ['INTP', 'ISFJ', 0.38],
  ['INTP', 'ISFP', 0.43],
  ['INTP', 'ISTJ', 0.51],
  ['INTP', 'ISTP', 0.81],

  ['ISFJ', 'ISFJ', 0.95],
  ['ISFJ', 'ISFP', 0.76],
  ['ISFJ', 'ISTJ', 0.93],
  ['ISFJ', 'ISTP', 0.62],

  ['ISFP', 'ISFP', 0.97],
  ['ISFP', 'ISTJ', 0.47],
  ['ISFP', 'ISTP', 0.76],

  ['ISTJ', 'ISTJ', 0.96],
  ['ISTJ', 'ISTP', 0.78],

  ['ISTP', 'ISTP', 0.96]
];

const dataMap = new Map();
const avgData = {};
for (const [a, b, v] of originalData) {
  dataMap.set(`${a}-${b}`, v);
}

const heatmapData = [];
const scatterData = [];
const decalSize = 1;
for (const a of mbti) {
  for (const b of mbti) {
    const key = `${a}-${b}`;
    const altKey = `${b}-${a}`;

    let value;
    if (dataMap.has(key)) {
      value = [a, b, dataMap.get(key)];
    } else if (dataMap.has(altKey)) {
      value = [a, b, dataMap.get(altKey)];
    } else {
      value = [a, b, 0];
    }
    heatmapData.push({
      value,
      itemStyle: {
        decal: {
          shape: 'circle',
          symbolSize: 1,
          color: getColor(a, 1),
          backgroundColor: getColor(b, 1),
          dashArrayX: [
            [decalSize, decalSize],
            [0, decalSize, decalSize, 0]
          ],
          dashArrayY: [decalSize, 0]
        },
        borderColor: getColor(b),
        borderWidth: 0
      }
    });
    scatterData.push({
      value,
      label: {
        color: value[2] < 0.2 ? getColor(b) : '#fff',
        opacity: value[2] < 0.15 ? 0.6 : 1
      }
    });
  }
}

const size = Math.round(Math.min(window.innerWidth, window.innerHeight) * 0.9);
const fontFamily = 'Ubuntu Condensed, sans-serif';

const detailSeries = [
  {
    id: 'detail-heatmap',
    type: 'heatmap',
    coordinateSystem: 'matrix',
    data: heatmapData,
    label: {
      show: false
    },
    emphasis: {
      itemStyle: {
        borderWidth: 5
      }
    }
  },
  {
    id: 'detail-scatter',
    type: 'scatter',
    coordinateSystem: 'matrix',
    symbolSize: 0,
    data: scatterData,
    color: '#fff',
    label: {
      show: true,
      formatter: (params) => Math.round(params.value[2] * 100) + '%',
      fontWeight: 'bold',
      color: 'inherit'
    },
    silent: true
  }
];

const getGroup = (mbti) => {
  if (mbti.indexOf('NF') >= 0) {
    return 'NF';
  }
  if (mbti.indexOf('NT') >= 0) {
    return 'NT';
  }
  if (mbti[1] === 'S' && mbti[3] === 'J') {
    return 'SJ';
  }
  if (mbti[1] === 'S' && mbti[3] === 'P') {
    return 'SP';
  }
  return '';
};
const groupRawData = {};
for (let i = 0; i < originalData.length; ++i) {
  const [a, b, v] = originalData[i];
  const groupA = getGroup(a);
  const groupB = getGroup(b);
  const key = groupA > groupB ? `${groupA}-${groupB}` : `${groupB}-${groupA}`;
  if (groupRawData[key]) {
    groupRawData[key].push(v);
  } else {
    groupRawData[key] = [v];
  }
}
const groupData = [];
function median(arr) {
  const sorted = arr.slice().sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  if (sorted.length % 2 === 0) {
    return (sorted[mid - 1] + sorted[mid]) / 2;
  } else {
    return sorted[mid];
  }
}
for (const key in groupRawData) {
  if (groupRawData.hasOwnProperty(key)) {
    const [a, b] = key.split('-');
    const v = median(groupRawData[key]);
    const colorA = getColor(a, 1);
    const colorB = getColor(b, 1);
    const label = {
      color: v < 0.2 ? getColor(b) : '#fff',
      fontSize: fontSize.value,
      fontWeight: 'bold',
      opacity: v < 0.15 ? 0.6 : 1,
      formatter: (params) => {
        return `${Math.round(params.value[2] * 100)}%`;
      }
    };
    const decalSize = 3;
    const itemStyle = {
      decal: {
        shape: 'circle',
        symbolSize: 1,
        color: colorA,
        backgroundColor: colorB,
        dashArrayX: [
          [decalSize, decalSize],
          [0, decalSize, decalSize, 0]
        ],
        dashArrayY: [decalSize, 0]
      },
      borderColor: getColor(b),
      borderWidth: 0
    };
    groupData.push({
      value: [a, b, v],
      label,
      itemStyle
    });
    if (a !== b) {
      groupData.push({
        value: [b, a, v],
        label,
        itemStyle
      }); // Symmetric
    }
  }
}
const groupSeries = [
  {
    id: 'summary-heatmap',
    type: 'heatmap',
    coordinateSystem: 'matrix',
    data: groupData,
    label: {
      show: true
    }
  }
];

option = {
  backgroundColor: '#F0F7F9',
  textStyle: {
    fontFamily
  },
  title: {
    text: 'MBTI Partner Compatibility',
    subtext:
      'Data from: https://www.personalitydata.org/16-types/enfj-relationships#partner-matrix',
    sublink:
      'https://www.personalitydata.org/16-types/enfj-relationships#partner-matrix',
    left: 'center',
    top: 5,
    textStyle: {
      fontSize: 20,
      color: '#57576A'
    },
    itemGap: 5
  },
  tooltip: {
    formatter: (params) => {
      return `<span style="color:${getColor(
        params.value[1]
      )};font-weight:bold">${params.value[1]}</span> /
                            <span style="color:${getColor(
                              params.value[0]
                            )};font-weight:bold">${params.value[0]}</span> :
                            ${Math.round(params.value[2] * 100)}%`;
    },
    borderColor: '#eee',
    padding: [2, 8]
  },
  matrix: {
    x: {
      data: xData,
      itemStyle: {
        borderColor: 'transparent',
        borderWidth: 0
      },
      dividerLineStyle: {
        width: 0
      },
      label: {
        fontFamily
      },
      levels: [
        {
          levelSize: 25
        },
        {
          levelSize: 30
        }
      ]
    },
    y: {
      data: yData,
      itemStyle: {
        borderColor: 'transparent',
        borderWidth: 0
      },
      dividerLineStyle: {
        width: 0
      },
      label: {
        fontFamily
      }
    },
    body: {
      itemStyle: {
        borderWidth: 0
      },
      label: {
        fontFamily
      }
    },
    width: size,
    height: size,
    left: (window.innerWidth - size) / 2,
    top: 50,
    backgroundStyle: {
      color: 'transparent',
      borderColor: 'transparent',
      borderWidth: 0
    }
  },
  visualMap: [
    {
      type: 'continuous',
      min: 0,
      max: 1,
      dimension: 2,
      calculable: true,
      orient: 'horizontal',
      top: 5,
      left: 'center',
      inRange: {
        opacity: [0, 1]
      },
      seriesIndex: [0, 2],
      show: false
    }
  ],
  series: detailSeries,
  aria: {
    enabled: true,
    decal: {
      show: true
    }
  },
  animation: 0
};

let isGroup = false;
myChart.on('click', () => {
  isGroup = !isGroup;
  option.series = isGroup ? groupSeries : detailSeries;
  myChart.setOption(option, true);
});
"""#,
        option: matrixMbtiOption)
}

// MARK: - generated data (mirrors the example's preamble; see DEVIATIONS above)

private let mbtiTypes = [
    "ENFJ", "ENFP", "ENTJ", "ENTP",
    "ESFJ", "ESFP", "ESTJ", "ESTP",
    "INFJ", "INFP", "INTJ", "INTP",
    "ISFJ", "ISFP", "ISTJ", "ISTP"
]

private let mbtiFontFamily = "Ubuntu Condensed, sans-serif"

/// Deterministic port of the source's `getColor(mbti, lightness)`: temperament group -> hex, with a
/// lighter (lightness < 0) / darker (lightness > 0) variant. All 16 types match one of the four
/// branches, so the JS `undefined` fallthrough is never hit; a black fallback stands in for it.
private func mbtiGetColor(_ m: String, _ lightness: Int = 0) -> String {
    if m.contains("NF") {
        return lightness < 0 ? "#10CA77" : lightness > 0 ? "#0FB369" : "#2D9A69"
    }
    if m.contains("NT") {
        return lightness < 0 ? "#9253AF" : lightness > 0 ? "#854AA0" : "#7D568F"
    }
    if m.contains("S") && m.contains("J") {
        return lightness < 0 ? "#26A9D9" : lightness > 0 ? "#2298C3" : "#3A8DAB"
    }
    if m.contains("S") && m.contains("P") {
        return lightness < 0 ? "#F4AC24" : lightness > 0 ? "#F2A30D" : "#E0A433"
    }
    return "#000000"
}

/// `[a, b, v]` compatibility triples (upper triangle only, as in the source's `originalData`).
private let mbtiOriginalData: [(String, String, Double)] = [
    ("ENFJ", "ENFJ", 0.86), ("ENFJ", "ENFP", 0.91), ("ENFJ", "ENTJ", 0.42), ("ENFJ", "ENTP", 0.73),
    ("ENFJ", "ESFJ", 0.64), ("ENFJ", "ESFP", 0.8), ("ENFJ", "ESTJ", 0.22), ("ENFJ", "ESTP", 0.41),
    ("ENFJ", "INFJ", 0.74), ("ENFJ", "INFP", 0.73), ("ENFJ", "INTJ", 0.16), ("ENFJ", "INTP", 0.35),
    ("ENFJ", "ISFJ", 0.3), ("ENFJ", "ISFP", 0.4), ("ENFJ", "ISTJ", 0.18), ("ENFJ", "ISTP", 0.09),

    ("ENFP", "ENFJ", 0.91), ("ENFP", "ENFP", 0.97), ("ENFP", "ENTJ", 0.37), ("ENFP", "ENTP", 0.85),
    ("ENFP", "ESFJ", 0.42), ("ENFP", "ESFP", 0.93), ("ENFP", "ESTJ", 0.27), ("ENFP", "ESTP", 0.76),
    ("ENFP", "INFJ", 0.51), ("ENFP", "INFP", 0.73), ("ENFP", "INTJ", 0.13), ("ENFP", "INTP", 0.36),
    ("ENFP", "ISFJ", 0.11), ("ENFP", "ISFP", 0.49), ("ENFP", "ISTJ", 0.04), ("ENFP", "ISTP", 0.14),

    ("ENTJ", "ENFJ", 0.42), ("ENTJ", "ENFP", 0.37), ("ENTJ", "ENTJ", 0.91), ("ENTJ", "ENTP", 0.81),
    ("ENTJ", "ESFJ", 0.53), ("ENTJ", "ESFP", 0.51), ("ENTJ", "ESTJ", 0.87), ("ENTJ", "ESTP", 0.74),
    ("ENTJ", "INFJ", 0.25), ("ENTJ", "INFP", 0.13), ("ENTJ", "INTJ", 0.46), ("ENTJ", "INTP", 0.47),
    ("ENTJ", "ISFJ", 0.29), ("ENTJ", "ISFP", 0.06), ("ENTJ", "ISTJ", 0.66), ("ENTJ", "ISTP", 0.41),

    ("ENTP", "ENFJ", 0.73), ("ENTP", "ENFP", 0.64), ("ENTP", "ENTJ", 0.81), ("ENTP", "ENTP", 0.94),
    ("ENTP", "ESFJ", 0.32), ("ENTP", "ESFP", 0.87), ("ENTP", "ESTJ", 0.7), ("ENTP", "ESTP", 0.92),
    ("ENTP", "INFJ", 0.11), ("ENTP", "INFP", 0.35), ("ENTP", "INTJ", 0.22), ("ENTP", "INTP", 0.51),
    ("ENTP", "ISFJ", 0.05), ("ENTP", "ISFP", 0.14), ("ENTP", "ISTJ", 0.11), ("ENTP", "ISTP", 0.35),

    ("ESFJ", "ESFJ", 0.94), ("ESFJ", "ESFP", 0.4), ("ESFJ", "ESTJ", 0.77), ("ESFJ", "ESTP", 0.37),
    ("ESFJ", "INFJ", 0.74), ("ESFJ", "INFP", 0.17), ("ESFJ", "INTJ", 0.32), ("ESFJ", "INTP", 0.05),
    ("ESFJ", "ISFJ", 0.79), ("ESFJ", "ISFP", 0.57), ("ESFJ", "ISTJ", 0.71), ("ESFJ", "ISTP", 0.19),

    ("ESFP", "ESFP", 0.7), ("ESFP", "ESTJ", 0.39), ("ESFP", "ESTP", 0.75), ("ESFP", "INFJ", 0.43),
    ("ESFP", "INFP", 0.58), ("ESFP", "INTJ", 0.22), ("ESFP", "INTP", 0.39), ("ESFP", "ISFJ", 0.12),
    ("ESFP", "ISFP", 0.58), ("ESFP", "ISTJ", 0.08), ("ESFP", "ISTP", 0.26),

    ("ESTJ", "ESTJ", 0.96), ("ESTJ", "ESTP", 0.78), ("ESTJ", "INFJ", 0.14), ("ESTJ", "INFP", 0.03),
    ("ESTJ", "INTJ", 0.33), ("ESTJ", "INTP", 0.22), ("ESTJ", "ISFJ", 0.48), ("ESTJ", "ISFP", 0.22),
    ("ESTJ", "ISTJ", 0.79), ("ESTJ", "ISTP", 0.55),

    ("ESTP", "ESTP", 0.95), ("ESTP", "INFJ", 0.05), ("ESTP", "INFP", 0.24), ("ESTP", "INTJ", 0.17),
    ("ESTP", "INTP", 0.39), ("ESTP", "ISFJ", 0.12), ("ESTP", "ISFP", 0.43), ("ESTP", "ISTJ", 0.2),
    ("ESTP", "ISTP", 0.62),

    ("INFJ", "INFJ", 0.95), ("INFJ", "INFP", 0.85), ("INFJ", "INTJ", 0.65), ("INFJ", "INTP", 0.5),
    ("INFJ", "ISFJ", 0.85), ("INFJ", "ISFP", 0.58), ("INFJ", "ISTJ", 0.53), ("INFJ", "ISTP", 0.23),

    ("INFP", "INFP", 0.97), ("INFP", "INTJ", 0.7), ("INFP", "INTP", 0.84), ("INFP", "ISFJ", 0.46),
    ("INFP", "ISFP", 0.78), ("INFP", "ISTJ", 0.21), ("INFP", "ISTP", 0.49),

    ("INTJ", "INTJ", 0.86), ("INTJ", "INTP", 0.89), ("INTJ", "ISFJ", 0.79), ("INTJ", "ISFP", 0.45),
    ("INTJ", "ISTJ", 0.85), ("INTJ", "ISTP", 0.78),

    ("INTP", "INTP", 0.96), ("INTP", "ISFJ", 0.38), ("INTP", "ISFP", 0.43), ("INTP", "ISTJ", 0.51),
    ("INTP", "ISTP", 0.81),

    ("ISFJ", "ISFJ", 0.95), ("ISFJ", "ISFP", 0.76), ("ISFJ", "ISTJ", 0.93), ("ISFJ", "ISTP", 0.62),

    ("ISFP", "ISFP", 0.97), ("ISFP", "ISTJ", 0.47), ("ISFP", "ISTP", 0.76),

    ("ISTJ", "ISTJ", 0.96), ("ISTJ", "ISTP", 0.78),

    ("ISTP", "ISTP", 0.96)
]

/// `"<a>-<b>" -> v` lookup built from `mbtiOriginalData`, mirroring the source's `dataMap`.
private let mbtiDataMap: [String: Double] = {
    var m = [String: Double]()
    for (a, b, v) in mbtiOriginalData { m["\(a)-\(b)"] = v }
    return m
}()

/// Symmetric value lookup: the compatibility of (a, b), falling back to (b, a), else 0.
private func mbtiValue(_ a: String, _ b: String) -> Double {
    if let v = mbtiDataMap["\(a)-\(b)"] { return v }
    if let v = mbtiDataMap["\(b)-\(a)"] { return v }
    return 0
}

/// 256 heatmap cells `{ value: [a, b, v], itemStyle: { decal, borderColor } }` — the detail series.
private let mbtiHeatmapData: [[String: Any]] = {
    let decalSize = 1.0
    var out: [[String: Any]] = []
    for a in mbtiTypes {
        for b in mbtiTypes {
            let v = mbtiValue(a, b)
            let decal: [String: Any] = [
                "shape": "circle",
                "symbolSize": 1.0,
                "color": mbtiGetColor(a, 1),
                "backgroundColor": mbtiGetColor(b, 1),
                "dashArrayX": [[decalSize, decalSize], [0.0, decalSize, decalSize, 0.0]],
                "dashArrayY": [decalSize, 0.0]
            ]
            out.append([
                "value": [a, b, v] as [Any],
                "itemStyle": [
                    "decal": decal,
                    "borderColor": mbtiGetColor(b),
                    "borderWidth": 0.0
                ] as [String: Any]
            ])
        }
    }
    return out
}()

/// 256 scatter points `{ value: [a, b, v], label: { color, opacity } }` — labels the cells.
private let mbtiScatterData: [[String: Any]] = {
    var out: [[String: Any]] = []
    for a in mbtiTypes {
        for b in mbtiTypes {
            let v = mbtiValue(a, b)
            out.append([
                "value": [a, b, v] as [Any],
                "label": [
                    "color": v < 0.2 ? mbtiGetColor(b) : "#fff",
                    "opacity": v < 0.15 ? 0.6 : 1.0
                ] as [String: Any]
            ])
        }
    }
    return out
}()

/// Two-level matrix axis data (four temperament groups, each with four types) — the source's
/// `generateGroup(...)` output; identical for the x and y axes. Font sizes take the desktop (>700)
/// branch (group 24 / item 13); see DEVIATIONS.
private func mbtiGenerateGroup(_ groupName: String) -> [String: Any] {
    let colorMap = ["NF": "#2D9A69", "NT": "#7D568F", "SJ": "#3A8DAB", "SP": "#E0A433"]
    let groupMembers = [
        "NF": ["INFJ", "INFP", "ENFJ", "ENFP"],
        "NT": ["INTJ", "INTP", "ENTJ", "ENTP"],
        "SJ": ["ISFJ", "ISTJ", "ESFJ", "ESTJ"],
        "SP": ["ISFP", "ISTP", "ESFP", "ESTP"]
    ]
    let c = colorMap[groupName]!
    let children: [[String: Any]] = groupMembers[groupName]!.map { m in
        [
            "value": m,
            "label": ["color": c, "fontSize": 13.0, "fontWeight": "bold"] as [String: Any]
        ]
    }
    return [
        "value": groupName,
        "label": ["color": c, "fontSize": 24.0, "fontWeight": "bolder", "padding": 0.0] as [String: Any],
        "children": children
    ]
}

private let mbtiAxisData: [[String: Any]] = [
    mbtiGenerateGroup("NF"),
    mbtiGenerateGroup("NT"),
    mbtiGenerateGroup("SJ"),
    mbtiGenerateGroup("SP")
]

/// The detail (16x16) series: a heatmap of decal-patterned cells + a silent scatter that labels them.
private let mbtiDetailSeries: [[String: Any]] = [
    [
        "id": "detail-heatmap",
        "type": "heatmap",
        "coordinateSystem": "matrix",
        "data": mbtiHeatmapData,
        "label": ["show": false] as [String: Any],
        "emphasis": ["itemStyle": ["borderWidth": 5.0] as [String: Any]] as [String: Any]
    ],
    [
        "id": "detail-scatter",
        "type": "scatter",
        "coordinateSystem": "matrix",
        "symbolSize": 0.0,
        "data": mbtiScatterData,
        "color": "#fff",
        // PORT-NOTE: label.formatter omitted — JS closure `round(value[2]*100)+'%'` printed each cell's
        // compatibility percentage; this scatter series exists only to draw those labels.
        "label": [
            "show": true,
            "fontWeight": "bold",
            "color": "inherit"
        ] as [String: Any],
        "silent": true
    ]
]

private let matrixMbtiOption: [String: Any] = [
    "backgroundColor": "#F0F7F9",
    "textStyle": ["fontFamily": mbtiFontFamily] as [String: Any],
    "title": [
        "text": "MBTI Partner Compatibility",
        "subtext": "Data from: https://www.personalitydata.org/16-types/enfj-relationships#partner-matrix",
        "sublink": "https://www.personalitydata.org/16-types/enfj-relationships#partner-matrix",
        "left": "center",
        "top": 5.0,
        "textStyle": ["fontSize": 20.0, "color": "#57576A"] as [String: Any],
        "itemGap": 5.0
    ] as [String: Any],
    // PORT-NOTE: tooltip.formatter omitted — JS closure rendered "<B> / <A> : NN%" with each type
    // colored by its group. The rest of the tooltip config is carried.
    "tooltip": [
        "borderColor": "#eee",
        "padding": [2.0, 8.0]
    ] as [String: Any],
    "matrix": [
        "x": [
            "data": mbtiAxisData,
            "itemStyle": ["borderColor": "transparent", "borderWidth": 0.0] as [String: Any],
            "dividerLineStyle": ["width": 0.0] as [String: Any],
            "label": ["fontFamily": mbtiFontFamily] as [String: Any],
            "levels": [
                ["levelSize": 25.0] as [String: Any],
                ["levelSize": 30.0] as [String: Any]
            ]
        ] as [String: Any],
        "y": [
            "data": mbtiAxisData,
            "itemStyle": ["borderColor": "transparent", "borderWidth": 0.0] as [String: Any],
            "dividerLineStyle": ["width": 0.0] as [String: Any],
            "label": ["fontFamily": mbtiFontFamily] as [String: Any]
        ] as [String: Any],
        "body": [
            "itemStyle": ["borderWidth": 0.0] as [String: Any],
            "label": ["fontFamily": mbtiFontFamily] as [String: Any]
        ] as [String: Any],
        // Fixed layout (the source derives these from window.innerWidth/innerHeight — see DEVIATIONS).
        "width": 360.0,
        "height": 360.0,
        "left": 180.0,
        "top": 50.0,
        "backgroundStyle": [
            "color": "transparent", "borderColor": "transparent", "borderWidth": 0.0
        ] as [String: Any]
    ] as [String: Any],
    "visualMap": [
        [
            "type": "continuous",
            "min": 0.0,
            "max": 1.0,
            "dimension": 2.0,
            "calculable": true,
            "orient": "horizontal",
            "top": 5.0,
            "left": "center",
            "inRange": ["opacity": [0.0, 1.0]] as [String: Any],
            "seriesIndex": [0.0, 2.0],
            "show": false
        ] as [String: Any]
    ],
    "series": mbtiDetailSeries,
    "aria": [
        "enabled": true,
        "decal": ["show": true] as [String: Any]
    ] as [String: Any],
    "animation": false
]
