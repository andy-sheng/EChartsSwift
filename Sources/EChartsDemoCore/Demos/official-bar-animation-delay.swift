// official-bar-animation-delay — replica of https://echarts.apache.org/examples/zh/editor.html?c=bar-animation-delay
// title: Animation Delay / titleCN: 柱状图动画延迟
// Two 100-point bar series ('bar' = sin, 'bar2' = cos, both over a shared 'A0'…'A99' category axis),
// with a legend, a tooltip, a toolbox (magicType stack / dataView / saveAsImage) and `animationEasing:
// 'elasticOut'`. The example's point is the STAGGERED entry animation: each bar's `animationDelay` is a
// function of its data index, so the bars cascade in left-to-right.
//
// DEVIATIONS from the official source:
//   - webOptionJS: verbatim (the `for` loop that builds xAxisData/data1/data2 and both `animationDelay`
//     closures run as real JS). Only the leading title/category block comment is dropped.
//   - The gallery snapshots ONE STATIC FRAME — WebPage.swift forces `option.animation = false` and the
//     native pane renders to an image — so the cascade itself is not visible in either pane. Both panes
//     show the settled final state; the delays are still carried in the web pane's JS for fidelity.
//   - option (native): `animationDelay` (both series) and `animationDelayUpdate` are JS closures, so the
//     Swift option omits them (see PORT-NOTEs). Everything else — including `animationEasing` — matches.
//     The 100-point series data is precomputed in `barAnimationDelay*` below with the same formulas.
import Foundation

extension EChartsDemoRegistry {
    static let official_bar_animation_delay = EChartsDemo(
        name: "official-bar-animation-delay", category: "bar",
        summary: "柱状图动画延迟 — Animation Delay",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
var xAxisData = [];
var data1 = [];
var data2 = [];
for (var i = 0; i < 100; i++) {
  xAxisData.push('A' + i);
  data1.push((Math.sin(i / 5) * (i / 5 - 10) + i / 6) * 5);
  data2.push((Math.cos(i / 5) * (i / 5 - 10) + i / 6) * 5);
}

option = {
  title: {
    text: 'Bar Animation Delay'
  },
  legend: {
    data: ['bar', 'bar2']
  },
  toolbox: {
    // y: 'bottom',
    feature: {
      magicType: {
        type: ['stack']
      },
      dataView: {},
      saveAsImage: {
        pixelRatio: 2
      }
    }
  },
  tooltip: {},
  xAxis: {
    data: xAxisData,
    splitLine: {
      show: false
    }
  },
  yAxis: {},
  series: [
    {
      name: 'bar',
      type: 'bar',
      data: data1,
      emphasis: {
        focus: 'series'
      },
      animationDelay: function (idx) {
        return idx * 10;
      }
    },
    {
      name: 'bar2',
      type: 'bar',
      data: data2,
      emphasis: {
        focus: 'series'
      },
      animationDelay: function (idx) {
        return idx * 10 + 100;
      }
    }
  ],
  animationEasing: 'elasticOut',
  animationDelayUpdate: function (idx) {
    return idx * 5;
  }
};
"""#,
        option: [
            "title": [
                "text": "Bar Animation Delay"
            ] as [String: Any],
            "legend": [
                "data": ["bar", "bar2"]
            ] as [String: Any],
            "toolbox": [
                "_featureOrder": ["magicType", "dataView", "saveAsImage"],
                "feature": [
                    "magicType": ["type": ["stack"]] as [String: Any],
                    "dataView": [:] as [String: Any],
                    "saveAsImage": ["pixelRatio": 2.0] as [String: Any]
                ] as [String: Any]
            ] as [String: Any],
            "tooltip": [:] as [String: Any],
            "xAxis": [
                "data": barAnimationDelayXAxisData,
                "splitLine": ["show": false] as [String: Any]
            ] as [String: Any],
            "yAxis": [:] as [String: Any],
            "series": [
                [
                    "name": "bar",
                    "type": "bar",
                    "data": barAnimationDelayData1,
                    "emphasis": ["focus": "series"] as [String: Any]
                    // PORT-NOTE: series[0].animationDelay omitted — JS closure `idx => idx * 10`,
                    // staggering each bar's entry animation by 10ms per data index.
                ] as [String: Any],
                [
                    "name": "bar2",
                    "type": "bar",
                    "data": barAnimationDelayData2,
                    "emphasis": ["focus": "series"] as [String: Any]
                    // PORT-NOTE: series[1].animationDelay omitted — JS closure `idx => idx * 10 + 100`,
                    // the same 10ms/index stagger offset 100ms behind the first series.
                ] as [String: Any]
            ],
            "animationEasing": "elasticOut"
            // PORT-NOTE: animationDelayUpdate omitted — JS closure `idx => idx * 5`, staggering the
            // re-layout animation (e.g. after the toolbox `magicType: ['stack']` switch) by 5ms per index.
        ])
}

// The Swift twin of the example's generator loop:
//   xAxisData[i] = 'A' + i
//   data1[i] = (sin(i / 5) * (i / 5 - 10) + i / 6) * 5
//   data2[i] = (cos(i / 5) * (i / 5 - 10) + i / 6) * 5
private let barAnimationDelayXAxisData: [String] = (0..<100).map { "A\($0)" }

private let barAnimationDelayData1: [Double] = (0..<100).map { idx in
    let i = Double(idx)
    return (sin(i / 5) * (i / 5 - 10) + i / 6) * 5
}

private let barAnimationDelayData2: [Double] = (0..<100).map { idx in
    let i = Double(idx)
    return (cos(i / 5) * (i / 5 - 10) + i / 6) * 5
}
