// official-scatter-matrix — replica of https://echarts.apache.org/examples/zh/editor.html?c=scatter-matrix
// title: Scatter Matrix / titleCN: 散点矩阵和平行坐标
// A 6x6 lower-triangle scatter-plot matrix (15 grids, one scatter series per cell, every pairing of
// the 6 AQI dimensions) sharing a piecewise visualMap keyed on the city dimension, plus a `parallel`
// series of the same rows underneath. `brush` with brushLink:'all' cross-highlights across all cells.
//
// DEVIATIONS from the official source:
//   - webOptionJS: TypeScript-only syntax stripped (the `retrieveScatterData` parameter annotations
//     and the four `echarts.*ComponentOption[]` array types) plus the trailing `export {};` — a bare
//     export is a SyntaxError in the page's classic script. Everything else is verbatim, generator
//     functions included, so the reference pane builds the grids exactly as the website does.
//   - option (native): the same grids/axes/series, but computed in Swift by `scatterMatrixGrids`
//     rather than by the JS generator. It reproduces the generator 1:1, including the official's
//     own off-by-one: `visualMap.seriesIndex` / `brush.[xy]AxisIndex` are `gridOption.series.map(idx)`
//     = 0...14, which — because the `parallel` series is unshifted in front of the 15 scatter series —
//     covers the parallel series and the first 14 cells, leaving the last cell out of the visualMap.
//     Ported as-is, not "fixed".
//   - Canvas bumped to 900x560 (from the tab default): 15 grids + a parallel coord system in 720x460
//     collapses into unreadable slivers.
//   - Data inlined (it is inline in the official source too); no fetch, no timers, no closures in the
//     option itself, so nothing had to be dropped from the native pane.
import Foundation   // NSNull — the padding cells in each scatter row are echarts' "no value" datum.

extension EChartsDemoRegistry {
    static let official_scatter_matrix = EChartsDemo(
        name: "official-scatter-matrix", category: "parallel",
        summary: "散点矩阵和平行坐标 — Scatter Matrix",
        width: 900, height: 560,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
// Schema:
// date,AQIindex,PM2.5,PM10,CO,NO2,SO2
const schema = [
  { name: 'AQIindex', index: 1, text: 'AQI' },
  { name: 'PM25', index: 2, text: 'PM 2.5' },
  { name: 'PM10', index: 3, text: 'PM 10' },
  { name: 'CO', index: 4, text: 'CO' },
  { name: 'NO2', index: 5, text: 'NO₂' },
  { name: 'SO2', index: 6, text: 'SO₂' },
  { name: '等级', index: 7, text: '等级' }
];

const rawData = [
  [55, 9, 56, 0.46, 18, 6, '良', '北京'],
  [25, 11, 21, 0.65, 34, 9, '优', '北京'],
  [56, 7, 63, 0.3, 14, 5, '良', '北京'],
  [33, 7, 29, 0.33, 16, 6, '优', '北京'],
  [42, 24, 44, 0.76, 40, 16, '优', '北京'],
  [82, 58, 90, 1.77, 68, 33, '良', '北京'],
  [74, 49, 77, 1.46, 48, 27, '良', '北京'],
  [78, 55, 80, 1.29, 59, 29, '良', '北京'],
  [267, 216, 280, 4.8, 108, 64, '重度', '北京'],
  [185, 127, 216, 2.52, 61, 27, '中度', '北京'],
  [39, 19, 38, 0.57, 31, 15, '优', '北京'],
  [41, 11, 40, 0.43, 21, 7, '优', '北京'],
  [64, 38, 74, 1.04, 46, 22, '良', '北京'],
  [108, 79, 120, 1.7, 75, 41, '轻度', '北京'],
  [108, 63, 116, 1.48, 44, 26, '轻度', '北京'],
  [33, 6, 29, 0.34, 13, 5, '优', '北京'],
  [94, 66, 110, 1.54, 62, 31, '良', '北京'],
  [186, 142, 192, 3.88, 93, 79, '中度', '北京'],
  [57, 31, 54, 0.96, 32, 14, '良', '北京'],
  [22, 8, 17, 0.48, 23, 10, '优', '北京'],
  [39, 15, 36, 0.61, 29, 13, '优', '北京'],
  [94, 69, 114, 2.08, 73, 39, '良', '北京'],
  [99, 73, 110, 2.43, 76, 48, '良', '北京'],
  [31, 12, 30, 0.5, 32, 16, '优', '北京'],
  [42, 27, 43, 1, 53, 22, '优', '北京'],
  [154, 117, 157, 3.05, 92, 58, '中度', '北京'],
  [234, 185, 230, 4.09, 123, 69, '重度', '北京'],
  [160, 120, 186, 2.77, 91, 50, '中度', '北京'],
  [134, 96, 165, 2.76, 83, 41, '轻度', '北京'],
  [52, 24, 60, 1.03, 50, 21, '良', '北京'],
  [46, 5, 49, 0.28, 10, 6, '优', '北京'],

  [26, 37, 27, 1.163, 27, 13, '优', '广州'],
  [85, 62, 71, 1.195, 60, 8, '良', '广州'],
  [78, 38, 74, 1.363, 37, 7, '良', '广州'],
  [21, 21, 36, 0.634, 40, 9, '优', '广州'],
  [41, 42, 46, 0.915, 81, 13, '优', '广州'],
  [56, 52, 69, 1.067, 92, 16, '良', '广州'],
  [64, 30, 28, 0.924, 51, 2, '良', '广州'],
  [55, 48, 74, 1.236, 75, 26, '良', '广州'],
  [76, 85, 113, 1.237, 114, 27, '良', '广州'],
  [91, 81, 104, 1.041, 56, 40, '良', '广州'],
  [84, 39, 60, 0.964, 25, 11, '良', '广州'],
  [64, 51, 101, 0.862, 58, 23, '良', '广州'],
  [70, 69, 120, 1.198, 65, 36, '良', '广州'],
  [77, 105, 178, 2.549, 64, 16, '良', '广州'],
  [109, 68, 87, 0.996, 74, 29, '轻度', '广州'],
  [73, 68, 97, 0.905, 51, 34, '良', '广州'],
  [54, 27, 47, 0.592, 53, 12, '良', '广州'],
  [51, 61, 97, 0.811, 65, 19, '良', '广州'],
  [91, 71, 121, 1.374, 43, 18, '良', '广州'],
  [73, 102, 182, 2.787, 44, 19, '良', '广州'],
  [73, 50, 76, 0.717, 31, 20, '良', '广州'],
  [84, 94, 140, 2.238, 68, 18, '良', '广州'],
  [93, 77, 104, 1.165, 53, 7, '良', '广州'],
  [99, 130, 227, 3.97, 55, 15, '良', '广州'],
  [146, 84, 139, 1.094, 40, 17, '轻度', '广州'],
  [113, 108, 137, 1.481, 48, 15, '轻度', '广州'],
  [81, 48, 62, 1.619, 26, 3, '良', '广州'],
  [56, 48, 68, 1.336, 37, 9, '良', '广州'],
  [82, 92, 174, 3.29, 0, 13, '良', '广州'],
  [106, 116, 188, 3.628, 101, 16, '轻度', '广州'],
  [118, 50, 0, 1.383, 76, 11, '轻度', '广州'],

  [91, 45, 125, 0.82, 34, 23, '良', '上海'],
  [65, 27, 78, 0.86, 45, 29, '良', '上海'],
  [83, 60, 84, 1.09, 73, 27, '良', '上海'],
  [109, 81, 121, 1.28, 68, 51, '轻度', '上海'],
  [106, 77, 114, 1.07, 55, 51, '轻度', '上海'],
  [109, 81, 121, 1.28, 68, 51, '轻度', '上海'],
  [106, 77, 114, 1.07, 55, 51, '轻度', '上海'],
  [89, 65, 78, 0.86, 51, 26, '良', '上海'],
  [53, 33, 47, 0.64, 50, 17, '良', '上海'],
  [80, 55, 80, 1.01, 75, 24, '良', '上海'],
  [117, 81, 124, 1.03, 45, 24, '轻度', '上海'],
  [99, 71, 142, 1.1, 62, 42, '良', '上海'],
  [95, 69, 130, 1.28, 74, 50, '良', '上海'],
  [116, 87, 131, 1.47, 84, 40, '轻度', '上海'],
  [108, 80, 121, 1.3, 85, 37, '轻度', '上海'],
  [134, 83, 167, 1.16, 57, 43, '轻度', '上海'],
  [79, 43, 107, 1.05, 59, 37, '良', '上海'],
  [71, 46, 89, 0.86, 64, 25, '良', '上海'],
  [97, 71, 113, 1.17, 88, 31, '良', '上海'],
  [84, 57, 91, 0.85, 55, 31, '良', '上海'],
  [87, 63, 101, 0.9, 56, 41, '良', '上海'],
  [104, 77, 119, 1.09, 73, 48, '轻度', '上海'],
  [87, 62, 100, 1, 72, 28, '良', '上海'],
  [168, 128, 172, 1.49, 97, 56, '中度', '上海'],
  [65, 45, 51, 0.74, 39, 17, '良', '上海'],
  [39, 24, 38, 0.61, 47, 17, '优', '上海'],
  [39, 24, 39, 0.59, 50, 19, '优', '上海'],
  [93, 68, 96, 1.05, 79, 29, '良', '上海'],
  [188, 143, 197, 1.66, 99, 51, '中度', '上海'],
  [174, 131, 174, 1.55, 108, 50, '中度', '上海'],
  [187, 143, 201, 1.39, 89, 53, '中度', '上海']
];

const CATEGORY_DIM_COUNT = 6;
const GAP = 2;
const BASE_LEFT = 5;
const BASE_TOP = 10;
// const GRID_WIDTH = 220;
// const GRID_HEIGHT = 220;
const GRID_WIDTH = (100 - BASE_LEFT - GAP) / CATEGORY_DIM_COUNT - GAP;
const GRID_HEIGHT = (100 - BASE_TOP - GAP) / CATEGORY_DIM_COUNT - GAP;
const CATEGORY_DIM = 7;
const SYMBOL_SIZE = 4;

function retrieveScatterData(data, dimX, dimY) {
  let result = [];
  for (let i = 0; i < data.length; i++) {
    let item = [data[i][dimX], data[i][dimY]];
    item[CATEGORY_DIM] = data[i][CATEGORY_DIM];
    result.push(item);
  }
  return result;
}

function generateGrids() {
  let index = 0;

  const grid = [];
  const xAxis = [];
  const yAxis = [];
  const series = [];

  for (let i = 0; i < CATEGORY_DIM_COUNT; i++) {
    for (let j = 0; j < CATEGORY_DIM_COUNT; j++) {
      if (CATEGORY_DIM_COUNT - i + j >= CATEGORY_DIM_COUNT) {
        continue;
      }

      grid.push({
        left: BASE_LEFT + i * (GRID_WIDTH + GAP) + '%',
        top: BASE_TOP + j * (GRID_HEIGHT + GAP) + '%',
        width: GRID_WIDTH + '%',
        height: GRID_HEIGHT + '%'
      });

      xAxis.push({
        splitNumber: 3,
        position: 'top',
        axisLine: {
          show: j === 0,
          onZero: false
        },
        axisTick: {
          show: j === 0,
          inside: true
        },
        axisLabel: {
          show: j === 0
        },
        type: 'value',
        gridIndex: index,
        scale: true
      });

      yAxis.push({
        splitNumber: 3,
        position: 'right',
        axisLine: {
          show: i === CATEGORY_DIM_COUNT - 1,
          onZero: false
        },
        axisTick: {
          show: i === CATEGORY_DIM_COUNT - 1,
          inside: true
        },
        axisLabel: {
          show: i === CATEGORY_DIM_COUNT - 1
        },
        type: 'value',
        gridIndex: index,
        scale: true
      });

      series.push({
        type: 'scatter',
        symbolSize: SYMBOL_SIZE,
        xAxisIndex: index,
        yAxisIndex: index,
        data: retrieveScatterData(rawData, i, j)
      });

      index++;
    }
  }

  return {
    grid,
    xAxis,
    yAxis,
    series
  };
}

const gridOption = generateGrids();

option = {
  animation: false,
  brush: {
    brushLink: 'all',
    xAxisIndex: gridOption.xAxis.map(function (_, idx) {
      return idx;
    }),
    yAxisIndex: gridOption.yAxis.map(function (_, idx) {
      return idx;
    }),
    inBrush: {
      opacity: 1
    }
  },
  visualMap: {
    type: 'piecewise',
    categories: ['北京', '上海', '广州'],
    dimension: CATEGORY_DIM,
    orient: 'horizontal',
    top: 0,
    left: 'center',
    inRange: {
      color: ['#51689b', '#ce5c5c', '#fbc357']
    },
    outOfRange: {
      color: '#ddd'
    },
    seriesIndex: gridOption.series.map(function (_, idx) {
      return idx;
    })
  },
  tooltip: {
    trigger: 'item'
  },
  parallelAxis: [
    { dim: 0, name: schema[0].text },
    { dim: 1, name: schema[1].text },
    { dim: 2, name: schema[2].text },
    { dim: 3, name: schema[3].text },
    { dim: 4, name: schema[4].text },
    { dim: 5, name: schema[5].text },
    {
      dim: 6,
      name: schema[6].text,
      type: 'category',
      data: ['优', '良', '轻度', '中度', '重度', '严重']
    }
  ],
  parallel: {
    bottom: '5%',
    left: '2%',
    height: '30%',
    width: '55%',
    parallelAxisDefault: {
      type: 'value',
      name: 'AQI指数',
      nameLocation: 'end',
      nameGap: 20,
      splitNumber: 3,
      nameTextStyle: {
        fontSize: 14
      },
      axisLine: {
        lineStyle: {
          color: '#555'
        }
      },
      axisTick: {
        lineStyle: {
          color: '#555'
        }
      },
      splitLine: {
        show: false
      },
      axisLabel: {
        color: '#555'
      }
    }
  },
  xAxis: gridOption.xAxis,
  yAxis: gridOption.yAxis,
  grid: gridOption.grid,
  series: [
    {
      name: 'parallel',
      type: 'parallel',
      smooth: true,
      lineStyle: {
        width: 1,
        opacity: 0.3
      },
      data: rawData
    },
    ...gridOption.series
  ]
};
"""#,
        option: [
            "animation": false,
            "brush": [
                "brushLink": "all",
                "xAxisIndex": scatterMatrixGrids.axisIndices,
                "yAxisIndex": scatterMatrixGrids.axisIndices,
                "inBrush": ["opacity": 1.0] as [String: Any]
            ] as [String: Any],
            "visualMap": [
                "type": "piecewise",
                "categories": ["北京", "上海", "广州"],
                "dimension": scatterMatrixCategoryDim,
                "orient": "horizontal",
                "top": 0.0,
                "left": "center",
                "inRange": ["color": ["#51689b", "#ce5c5c", "#fbc357"]] as [String: Any],
                "outOfRange": ["color": "#ddd"] as [String: Any],
                // Verbatim from the official source: indices into gridOption.series (0...14), NOT into
                // the final series array — see the DEVIATIONS note above.
                "seriesIndex": scatterMatrixGrids.axisIndices
            ] as [String: Any],
            "tooltip": ["trigger": "item"] as [String: Any],
            "parallelAxis": [
                ["dim": 0.0, "name": "AQI"] as [String: Any],
                ["dim": 1.0, "name": "PM 2.5"] as [String: Any],
                ["dim": 2.0, "name": "PM 10"] as [String: Any],
                ["dim": 3.0, "name": "CO"] as [String: Any],
                ["dim": 4.0, "name": "NO₂"] as [String: Any],
                ["dim": 5.0, "name": "SO₂"] as [String: Any],
                [
                    "dim": 6.0,
                    "name": "等级",
                    "type": "category",
                    "data": ["优", "良", "轻度", "中度", "重度", "严重"],
                    // The reference fits all six category labels on this parallel axis. Pin the
                    // native category interval so its generic auto-overlap heuristic does not
                    // discard every other semantic level.
                    "axisLabel": ["interval": 0.0] as [String: Any]
                ] as [String: Any]
            ],
            "parallel": [
                "bottom": "5%",
                "left": "2%",
                "height": "30%",
                "width": "55%",
                "parallelAxisDefault": [
                    "type": "value",
                    "name": "AQI指数",
                    "nameLocation": "end",
                    "nameGap": 20.0,
                    "splitNumber": 3.0,
                    "nameTextStyle": ["fontSize": 14.0] as [String: Any],
                    "axisLine": ["lineStyle": ["color": "#555"] as [String: Any]] as [String: Any],
                    "axisTick": ["lineStyle": ["color": "#555"] as [String: Any]] as [String: Any],
                    "splitLine": ["show": false] as [String: Any],
                    "axisLabel": ["color": "#555"] as [String: Any]
                ] as [String: Any]
            ] as [String: Any],
            "xAxis": scatterMatrixGrids.xAxis,
            "yAxis": scatterMatrixGrids.yAxis,
            "grid": scatterMatrixGrids.grid,
            "series": [
                [
                    "name": "parallel",
                    "type": "parallel",
                    "smooth": true,
                    "lineStyle": ["width": 1.0, "opacity": 0.3] as [String: Any],
                    "data": scatterMatrixRawData
                ] as [String: Any]
            ] + scatterMatrixGrids.series
        ])
}

// MARK: - data + the Swift twin of the example's generateGrids()

// AQI rows: [AQIindex, PM2.5, PM10, CO, NO2, SO2, 等级, 城市] — dim 6 is the category axis of the
// parallel coord system, dim 7 (CATEGORY_DIM) is what the visualMap pieces on.
private let scatterMatrixRawData: [[Any]] = [
    [55.0, 9.0, 56.0, 0.46, 18.0, 6.0, "良", "北京"],
    [25.0, 11.0, 21.0, 0.65, 34.0, 9.0, "优", "北京"],
    [56.0, 7.0, 63.0, 0.3, 14.0, 5.0, "良", "北京"],
    [33.0, 7.0, 29.0, 0.33, 16.0, 6.0, "优", "北京"],
    [42.0, 24.0, 44.0, 0.76, 40.0, 16.0, "优", "北京"],
    [82.0, 58.0, 90.0, 1.77, 68.0, 33.0, "良", "北京"],
    [74.0, 49.0, 77.0, 1.46, 48.0, 27.0, "良", "北京"],
    [78.0, 55.0, 80.0, 1.29, 59.0, 29.0, "良", "北京"],
    [267.0, 216.0, 280.0, 4.8, 108.0, 64.0, "重度", "北京"],
    [185.0, 127.0, 216.0, 2.52, 61.0, 27.0, "中度", "北京"],
    [39.0, 19.0, 38.0, 0.57, 31.0, 15.0, "优", "北京"],
    [41.0, 11.0, 40.0, 0.43, 21.0, 7.0, "优", "北京"],
    [64.0, 38.0, 74.0, 1.04, 46.0, 22.0, "良", "北京"],
    [108.0, 79.0, 120.0, 1.7, 75.0, 41.0, "轻度", "北京"],
    [108.0, 63.0, 116.0, 1.48, 44.0, 26.0, "轻度", "北京"],
    [33.0, 6.0, 29.0, 0.34, 13.0, 5.0, "优", "北京"],
    [94.0, 66.0, 110.0, 1.54, 62.0, 31.0, "良", "北京"],
    [186.0, 142.0, 192.0, 3.88, 93.0, 79.0, "中度", "北京"],
    [57.0, 31.0, 54.0, 0.96, 32.0, 14.0, "良", "北京"],
    [22.0, 8.0, 17.0, 0.48, 23.0, 10.0, "优", "北京"],
    [39.0, 15.0, 36.0, 0.61, 29.0, 13.0, "优", "北京"],
    [94.0, 69.0, 114.0, 2.08, 73.0, 39.0, "良", "北京"],
    [99.0, 73.0, 110.0, 2.43, 76.0, 48.0, "良", "北京"],
    [31.0, 12.0, 30.0, 0.5, 32.0, 16.0, "优", "北京"],
    [42.0, 27.0, 43.0, 1.0, 53.0, 22.0, "优", "北京"],
    [154.0, 117.0, 157.0, 3.05, 92.0, 58.0, "中度", "北京"],
    [234.0, 185.0, 230.0, 4.09, 123.0, 69.0, "重度", "北京"],
    [160.0, 120.0, 186.0, 2.77, 91.0, 50.0, "中度", "北京"],
    [134.0, 96.0, 165.0, 2.76, 83.0, 41.0, "轻度", "北京"],
    [52.0, 24.0, 60.0, 1.03, 50.0, 21.0, "良", "北京"],
    [46.0, 5.0, 49.0, 0.28, 10.0, 6.0, "优", "北京"],
    [26.0, 37.0, 27.0, 1.163, 27.0, 13.0, "优", "广州"],
    [85.0, 62.0, 71.0, 1.195, 60.0, 8.0, "良", "广州"],
    [78.0, 38.0, 74.0, 1.363, 37.0, 7.0, "良", "广州"],
    [21.0, 21.0, 36.0, 0.634, 40.0, 9.0, "优", "广州"],
    [41.0, 42.0, 46.0, 0.915, 81.0, 13.0, "优", "广州"],
    [56.0, 52.0, 69.0, 1.067, 92.0, 16.0, "良", "广州"],
    [64.0, 30.0, 28.0, 0.924, 51.0, 2.0, "良", "广州"],
    [55.0, 48.0, 74.0, 1.236, 75.0, 26.0, "良", "广州"],
    [76.0, 85.0, 113.0, 1.237, 114.0, 27.0, "良", "广州"],
    [91.0, 81.0, 104.0, 1.041, 56.0, 40.0, "良", "广州"],
    [84.0, 39.0, 60.0, 0.964, 25.0, 11.0, "良", "广州"],
    [64.0, 51.0, 101.0, 0.862, 58.0, 23.0, "良", "广州"],
    [70.0, 69.0, 120.0, 1.198, 65.0, 36.0, "良", "广州"],
    [77.0, 105.0, 178.0, 2.549, 64.0, 16.0, "良", "广州"],
    [109.0, 68.0, 87.0, 0.996, 74.0, 29.0, "轻度", "广州"],
    [73.0, 68.0, 97.0, 0.905, 51.0, 34.0, "良", "广州"],
    [54.0, 27.0, 47.0, 0.592, 53.0, 12.0, "良", "广州"],
    [51.0, 61.0, 97.0, 0.811, 65.0, 19.0, "良", "广州"],
    [91.0, 71.0, 121.0, 1.374, 43.0, 18.0, "良", "广州"],
    [73.0, 102.0, 182.0, 2.787, 44.0, 19.0, "良", "广州"],
    [73.0, 50.0, 76.0, 0.717, 31.0, 20.0, "良", "广州"],
    [84.0, 94.0, 140.0, 2.238, 68.0, 18.0, "良", "广州"],
    [93.0, 77.0, 104.0, 1.165, 53.0, 7.0, "良", "广州"],
    [99.0, 130.0, 227.0, 3.97, 55.0, 15.0, "良", "广州"],
    [146.0, 84.0, 139.0, 1.094, 40.0, 17.0, "轻度", "广州"],
    [113.0, 108.0, 137.0, 1.481, 48.0, 15.0, "轻度", "广州"],
    [81.0, 48.0, 62.0, 1.619, 26.0, 3.0, "良", "广州"],
    [56.0, 48.0, 68.0, 1.336, 37.0, 9.0, "良", "广州"],
    [82.0, 92.0, 174.0, 3.29, 0.0, 13.0, "良", "广州"],
    [106.0, 116.0, 188.0, 3.628, 101.0, 16.0, "轻度", "广州"],
    [118.0, 50.0, 0.0, 1.383, 76.0, 11.0, "轻度", "广州"],
    [91.0, 45.0, 125.0, 0.82, 34.0, 23.0, "良", "上海"],
    [65.0, 27.0, 78.0, 0.86, 45.0, 29.0, "良", "上海"],
    [83.0, 60.0, 84.0, 1.09, 73.0, 27.0, "良", "上海"],
    [109.0, 81.0, 121.0, 1.28, 68.0, 51.0, "轻度", "上海"],
    [106.0, 77.0, 114.0, 1.07, 55.0, 51.0, "轻度", "上海"],
    [109.0, 81.0, 121.0, 1.28, 68.0, 51.0, "轻度", "上海"],
    [106.0, 77.0, 114.0, 1.07, 55.0, 51.0, "轻度", "上海"],
    [89.0, 65.0, 78.0, 0.86, 51.0, 26.0, "良", "上海"],
    [53.0, 33.0, 47.0, 0.64, 50.0, 17.0, "良", "上海"],
    [80.0, 55.0, 80.0, 1.01, 75.0, 24.0, "良", "上海"],
    [117.0, 81.0, 124.0, 1.03, 45.0, 24.0, "轻度", "上海"],
    [99.0, 71.0, 142.0, 1.1, 62.0, 42.0, "良", "上海"],
    [95.0, 69.0, 130.0, 1.28, 74.0, 50.0, "良", "上海"],
    [116.0, 87.0, 131.0, 1.47, 84.0, 40.0, "轻度", "上海"],
    [108.0, 80.0, 121.0, 1.3, 85.0, 37.0, "轻度", "上海"],
    [134.0, 83.0, 167.0, 1.16, 57.0, 43.0, "轻度", "上海"],
    [79.0, 43.0, 107.0, 1.05, 59.0, 37.0, "良", "上海"],
    [71.0, 46.0, 89.0, 0.86, 64.0, 25.0, "良", "上海"],
    [97.0, 71.0, 113.0, 1.17, 88.0, 31.0, "良", "上海"],
    [84.0, 57.0, 91.0, 0.85, 55.0, 31.0, "良", "上海"],
    [87.0, 63.0, 101.0, 0.9, 56.0, 41.0, "良", "上海"],
    [104.0, 77.0, 119.0, 1.09, 73.0, 48.0, "轻度", "上海"],
    [87.0, 62.0, 100.0, 1.0, 72.0, 28.0, "良", "上海"],
    [168.0, 128.0, 172.0, 1.49, 97.0, 56.0, "中度", "上海"],
    [65.0, 45.0, 51.0, 0.74, 39.0, 17.0, "良", "上海"],
    [39.0, 24.0, 38.0, 0.61, 47.0, 17.0, "优", "上海"],
    [39.0, 24.0, 39.0, 0.59, 50.0, 19.0, "优", "上海"],
    [93.0, 68.0, 96.0, 1.05, 79.0, 29.0, "良", "上海"],
    [188.0, 143.0, 197.0, 1.66, 99.0, 51.0, "中度", "上海"],
    [174.0, 131.0, 174.0, 1.55, 108.0, 50.0, "中度", "上海"],
    [187.0, 143.0, 201.0, 1.39, 89.0, 53.0, "中度", "上海"]
]

private let scatterMatrixDimCount = 6          // CATEGORY_DIM_COUNT
private let scatterMatrixGap = 2.0             // GAP
private let scatterMatrixBaseLeft = 5.0        // BASE_LEFT
private let scatterMatrixBaseTop = 10.0        // BASE_TOP
private let scatterMatrixGridWidth = (100.0 - scatterMatrixBaseLeft - scatterMatrixGap) / 6.0 - scatterMatrixGap
private let scatterMatrixGridHeight = (100.0 - scatterMatrixBaseTop - scatterMatrixGap) / 6.0 - scatterMatrixGap
private let scatterMatrixCategoryDim = 7.0     // CATEGORY_DIM
private let scatterMatrixSymbolSize = 4.0      // SYMBOL_SIZE

/// JS `n + '%'` — Double.description keeps "5.0", which parses the same but reads wrong in a dump.
private func scatterMatrixPercent(_ v: Double) -> String {
    v == v.rounded() ? "\(Int(v))%" : "\(v)%"
}

/// Twin of the example's `retrieveScatterData`: [x, y] with the city spliced in at CATEGORY_DIM.
/// JS leaves indices 2...6 as holes (undefined); NSNull is the option-dict equivalent.
private func scatterMatrixSeriesData(dimX: Int, dimY: Int) -> [[Any]] {
    let cat = Int(scatterMatrixCategoryDim)
    return scatterMatrixRawData.map { row -> [Any] in
        var item: [Any] = [row[dimX], row[dimY]]
        while item.count < cat { item.append(NSNull()) }
        item.append(row[cat])
        return item
    }
}

private struct ScatterMatrixGrids {
    let grid: [[String: Any]]
    let xAxis: [[String: Any]]
    let yAxis: [[String: Any]]
    let series: [[String: Any]]
    /// gridOption.{xAxis,yAxis,series}.map((_, idx) => idx) — all three have the same length.
    var axisIndices: [Double] { (0..<grid.count).map(Double.init) }
}

/// Twin of the example's `generateGrids()`: the lower-left triangle of the 6x6 matrix (the
/// `CATEGORY_DIM_COUNT - i + j >= CATEGORY_DIM_COUNT` guard keeps only j < i) => 15 cells.
private let scatterMatrixGrids: ScatterMatrixGrids = {
    var grid: [[String: Any]] = []
    var xAxis: [[String: Any]] = []
    var yAxis: [[String: Any]] = []
    var series: [[String: Any]] = []
    var index = 0

    for i in 0..<scatterMatrixDimCount {
        for j in 0..<scatterMatrixDimCount {
            if scatterMatrixDimCount - i + j >= scatterMatrixDimCount { continue }

            grid.append([
                "left": scatterMatrixPercent(scatterMatrixBaseLeft + Double(i) * (scatterMatrixGridWidth + scatterMatrixGap)),
                "top": scatterMatrixPercent(scatterMatrixBaseTop + Double(j) * (scatterMatrixGridHeight + scatterMatrixGap)),
                "width": scatterMatrixPercent(scatterMatrixGridWidth),
                "height": scatterMatrixPercent(scatterMatrixGridHeight)
            ] as [String: Any])

            xAxis.append([
                "splitNumber": 3.0,
                "position": "top",
                "axisLine": ["show": j == 0, "onZero": false] as [String: Any],
                "axisTick": ["show": j == 0, "inside": true] as [String: Any],
                "axisLabel": ["show": j == 0] as [String: Any],
                "type": "value",
                "gridIndex": Double(index),
                "scale": true
            ] as [String: Any])

            yAxis.append([
                "splitNumber": 3.0,
                "position": "right",
                "axisLine": ["show": i == scatterMatrixDimCount - 1, "onZero": false] as [String: Any],
                "axisTick": ["show": i == scatterMatrixDimCount - 1, "inside": true] as [String: Any],
                "axisLabel": ["show": i == scatterMatrixDimCount - 1] as [String: Any],
                "type": "value",
                "gridIndex": Double(index),
                "scale": true
            ] as [String: Any])

            series.append([
                "type": "scatter",
                "symbolSize": scatterMatrixSymbolSize,
                "xAxisIndex": Double(index),
                "yAxisIndex": Double(index),
                "data": scatterMatrixSeriesData(dimX: i, dimY: j)
            ] as [String: Any])

            index += 1
        }
    }

    return ScatterMatrixGrids(grid: grid, xAxis: xAxis, yAxis: yAxis, series: series)
}()
