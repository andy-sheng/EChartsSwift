// official-boxplot-multi — replica of https://echarts.apache.org/examples/zh/editor.html?c=boxplot-multi
// title: Multiple Categories / titleCN: 多系列盒须图
//
// Three boxplot series side by side on one category axis: three raw datasets (18 categories × 100 random
// samples each) are each reduced by the BUILT-IN `boxplot` dataset transform (`fromDatasetIndex` 0/1/2 ->
// `dataset[3..5]`), and the three `boxplot` series read those transform results by `datasetIndex`. A legend,
// a fixed y range (-400..600), and a dataZoom pair (inside + slider, showing the first 20% of the 18
// categories) complete it.
//
// DEVIATIONS from the official source:
//   - The upstream sample generation uses `Math.random()`. For deterministic Native/Web snapshot parity,
//     both panes use the same seeded 32-bit LCG while retaining the exact 18 × 100 uniform [0, 200) shape.
//     Nothing in the chart option or boxplot transform differs from upstream.
//
// nativeSupported: TRUE — same wiring as `official-boxplot-light-velocity` / `-light-velocity2`: the
// `boxplot` SERIES (BoxplotSeriesModel + BoxplotView + boxplotLayout + registerBoxplotAxisHandlers, all
// wired in `ECharts.installOnce()`), the `dataset` TRANSFORM PIPELINE (`sourceManager.swift` reads
// `fromDatasetIndex` / `fromTransformResult`; `data/helper/transform.swift` is the `applyDataTransform`
// engine), and the `boxplot` transform TYPE itself — `chart/boxplot/boxplotTransform.swift`, the thin
// `ExternalDataTransform` wrapper around the ported `prepareBoxplotData.swift`, registered by
// `registerExternalTransform(boxplotTransform)` in `component/transform/transformInstall.swift:69`.
// The `option` below is a 1:1 transcription of the official option.
import Foundation

extension EChartsDemoRegistry {
    static let official_boxplot_multi = EChartsDemo(
        name: "official-boxplot-multi", category: "boxplot",
        summary: "多系列盒须图 — Multiple Categories",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
// Generate deterministic data with the same shape/distribution as the official Math.random() sample.
function makeData(seed) {
  let state = seed >>> 0;
  function random() {
    state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
    return state / 4294967296;
  }
  let data = [];
  for (let i = 0; i < 18; i++) {
    let cate = [];
    for (let j = 0; j < 100; j++) {
      cate.push(random() * 200);
    }
    data.push(cate);
  }
  return data;
}
const data0 = makeData(0x9e3779b9);
const data1 = makeData(0xd1b54a32);
const data2 = makeData(0xbf58476d);

option = {
  title: {
    text: 'Multiple Categories',
    left: 'center'
  },
  dataset: [
    {
      source: data0
    },
    {
      source: data1
    },
    {
      source: data2
    },
    {
      fromDatasetIndex: 0,
      transform: { type: 'boxplot' }
    },
    {
      fromDatasetIndex: 1,
      transform: { type: 'boxplot' }
    },
    {
      fromDatasetIndex: 2,
      transform: { type: 'boxplot' }
    }
  ],
  legend: {
    top: '10%'
  },
  tooltip: {
    trigger: 'item',
    axisPointer: {
      type: 'shadow'
    }
  },
  grid: {
    left: '10%',
    top: '20%',
    right: '10%',
    bottom: '15%'
  },
  xAxis: {
    type: 'category',
    boundaryGap: true,
    nameGap: 30,
    splitArea: {
      show: true
    },
    splitLine: {
      show: false
    }
  },
  yAxis: {
    type: 'value',
    name: 'Value',
    min: -400,
    max: 600,
    splitArea: {
      show: false
    }
  },
  dataZoom: [
    {
      type: 'inside',
      start: 0,
      end: 20
    },
    {
      show: true,
      type: 'slider',
      top: '90%',
      xAxisIndex: [0],
      start: 0,
      end: 20
    }
  ],
  series: [
    {
      name: 'category0',
      type: 'boxplot',
      datasetIndex: 3
    },
    {
      name: 'category1',
      type: 'boxplot',
      datasetIndex: 4
    },
    {
      name: 'category2',
      type: 'boxplot',
      datasetIndex: 5
    }
  ]
};
"""#,
        option: [
            "title": [
                "text": "Multiple Categories",
                "left": "center"
            ] as [String: Any],
            "dataset": [
                ["source": boxplotMultiData0] as [String: Any],
                ["source": boxplotMultiData1] as [String: Any],
                ["source": boxplotMultiData2] as [String: Any],
                [
                    "fromDatasetIndex": 0.0,
                    "transform": ["type": "boxplot"] as [String: Any]
                ] as [String: Any],
                [
                    "fromDatasetIndex": 1.0,
                    "transform": ["type": "boxplot"] as [String: Any]
                ] as [String: Any],
                [
                    "fromDatasetIndex": 2.0,
                    "transform": ["type": "boxplot"] as [String: Any]
                ] as [String: Any]
            ],
            "legend": [
                "top": "10%"
            ] as [String: Any],
            "tooltip": [
                "trigger": "item",
                "axisPointer": ["type": "shadow"] as [String: Any]
            ] as [String: Any],
            "grid": [
                "left": "10%",
                "top": "20%",
                "right": "10%",
                "bottom": "15%"
            ] as [String: Any],
            "xAxis": [
                "type": "category",
                "boundaryGap": true,
                "nameGap": 30.0,
                "splitArea": ["show": true] as [String: Any],
                "splitLine": ["show": false] as [String: Any]
            ] as [String: Any],
            "yAxis": [
                "type": "value",
                "name": "Value",
                "min": -400.0,
                "max": 600.0,
                "splitArea": ["show": false] as [String: Any]
            ] as [String: Any],
            "dataZoom": [
                [
                    "type": "inside",
                    "start": 0.0,
                    "end": 20.0
                ] as [String: Any],
                [
                    "show": true,
                    "type": "slider",
                    "top": "90%",
                    "xAxisIndex": [0.0],
                    "start": 0.0,
                    "end": 20.0
                ] as [String: Any]
            ],
            "series": [
                [
                    "name": "category0",
                    "type": "boxplot",
                    "datasetIndex": 3.0
                ] as [String: Any],
                [
                    "name": "category1",
                    "type": "boxplot",
                    "datasetIndex": 4.0
                ] as [String: Any],
                [
                    "name": "category2",
                    "type": "boxplot",
                    "datasetIndex": 5.0
                ] as [String: Any]
            ]
        ])
}

/// Deterministic mirror used by both panes: 18 categories × 100 samples, uniform on [0, 200).
private func boxplotMultiMakeData(seed: UInt32) -> [[Double]] {
    var state = seed
    func random() -> Double {
        state = state &* 1_664_525 &+ 1_013_904_223
        return Double(state) / 4_294_967_296.0
    }
    var data: [[Double]] = []
    data.reserveCapacity(18)
    for _ in 0..<18 {
        var cate: [Double] = []
        cate.reserveCapacity(100)
        for _ in 0..<100 {
            // upstream: cate.push(Math.random() * 200);
            cate.append(random() * 200)
        }
        data.append(cate)
    }
    return data
}

// upstream: const data0 = makeData(); const data1 = makeData(); const data2 = makeData();
private let boxplotMultiData0: [[Double]] = boxplotMultiMakeData(seed: 0x9E37_79B9)
private let boxplotMultiData1: [[Double]] = boxplotMultiMakeData(seed: 0xD1B5_4A32)
private let boxplotMultiData2: [[Double]] = boxplotMultiMakeData(seed: 0xBF58_476D)
