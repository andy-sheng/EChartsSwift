// official-pie-legend — replica of https://echarts.apache.org/examples/zh/editor.html?c=pie-legend
// title: Pie with Scrollable Legend / titleCN: 可滚动的图例
// A 50-slice pie with a vertical `type: 'scroll'` legend down the right edge (the legend cannot fit
// 50 entries, so it paginates); emphasis adds a drop shadow to the hovered sector.
// DEVIATIONS:
//   - Data frozen. The official source builds its data with `genData(50)`, which is Math.random()
//     over a surname list: every reload is a different chart, and the two panes could never agree.
//     One sample of genData(50) (50 unique names, values 0..100000) is inlined verbatim into BOTH
//     panes, so `genData`/`makeWord` are gone. Nothing else about the option changed.
//   - `export {};` dropped (a bare export is a SyntaxError in the page's classic script).
extension EChartsDemoRegistry {
    static let official_pie_legend = EChartsDemo(
        name: "official-pie-legend", category: "pie",
        summary: "可滚动的图例 — Pie with Scrollable Legend",
        width: 640, height: 420,
        nativeSupported: true,
        collection: .official,
        webOptionJS: #"""
// genData(50) frozen to one sample — see the file header.
const legendData = [
    '皮吕朱', '施苗·韩强', '朱廉明·李张', '窦卫喻·朱彭鲍', '韩褚安', '康杜余陈·宋贾',
    '戴蒋袁', '薛薛谈云柏·水汪尤', '齐陈秦卞安·董麻', '谢舒', '费王茅·施平', '窦时韦',
    '毛伏', '殷魏茅·危', '俞屈宋', '何时曹罗·贾殷', '皮郑', '危周奚',
    '禹任萧·明', '茅熊', '袁余·方', '华禹郎', '郝席', '萧彭谈',
    '任任郑·顾邵', '酆袁章穆魏·赵', '费孙', '萧卜', '韩萧', '戚任祁席·余鲍',
    '祝魏毛俞·唐', '彭阮', '计姚郝', '杜金', '沈鲁', '皮唐',
    '常任·柳', '金卜', '戚尹', '苏成麻邵·韩贾', '狄陶顾', '计项柳',
    '齐贺杨·李', '穆魏·贾禹董', '孟曹姜', '余郎', '明张廉茅·姚阮倪', '臧吴施',
    '汤魏沈', '梁廉·蓝余苗'
];
const seriesData = [
    { name: '皮吕朱', value: 88138 },
    { name: '施苗·韩强', value: 72627 },
    { name: '朱廉明·李张', value: 37381 },
    { name: '窦卫喻·朱彭鲍', value: 19258 },
    { name: '韩褚安', value: 28262 },
    { name: '康杜余陈·宋贾', value: 9896 },
    { name: '戴蒋袁', value: 14935 },
    { name: '薛薛谈云柏·水汪尤', value: 19374 },
    { name: '齐陈秦卞安·董麻', value: 49097 },
    { name: '谢舒', value: 12390 },
    { name: '费王茅·施平', value: 19128 },
    { name: '窦时韦', value: 83318 },
    { name: '毛伏', value: 79205 },
    { name: '殷魏茅·危', value: 6124 },
    { name: '俞屈宋', value: 87057 },
    { name: '何时曹罗·贾殷', value: 96678 },
    { name: '皮郑', value: 63471 },
    { name: '危周奚', value: 46118 },
    { name: '禹任萧·明', value: 82784 },
    { name: '茅熊', value: 8280 },
    { name: '袁余·方', value: 82580 },
    { name: '华禹郎', value: 1474 },
    { name: '郝席', value: 15652 },
    { name: '萧彭谈', value: 49764 },
    { name: '任任郑·顾邵', value: 9858 },
    { name: '酆袁章穆魏·赵', value: 57030 },
    { name: '费孙', value: 10287 },
    { name: '萧卜', value: 56776 },
    { name: '韩萧', value: 61996 },
    { name: '戚任祁席·余鲍', value: 41710 },
    { name: '祝魏毛俞·唐', value: 70548 },
    { name: '彭阮', value: 40368 },
    { name: '计姚郝', value: 40006 },
    { name: '杜金', value: 44561 },
    { name: '沈鲁', value: 5775 },
    { name: '皮唐', value: 22099 },
    { name: '常任·柳', value: 61147 },
    { name: '金卜', value: 9125 },
    { name: '戚尹', value: 28285 },
    { name: '苏成麻邵·韩贾', value: 10606 },
    { name: '狄陶顾', value: 41791 },
    { name: '计项柳', value: 25198 },
    { name: '齐贺杨·李', value: 70685 },
    { name: '穆魏·贾禹董', value: 20176 },
    { name: '孟曹姜', value: 93817 },
    { name: '余郎', value: 89423 },
    { name: '明张廉茅·姚阮倪', value: 17490 },
    { name: '臧吴施', value: 71789 },
    { name: '汤魏沈', value: 46232 },
    { name: '梁廉·蓝余苗', value: 46592 }
];
const data = { legendData: legendData, seriesData: seriesData };

option = {
  title: {
    text: '同名数量统计',
    subtext: '纯属虚构',
    left: 'center'
  },
  tooltip: {
    trigger: 'item',
    formatter: '{a} <br/>{b} : {c} ({d}%)'
  },
  legend: {
    type: 'scroll',
    orient: 'vertical',
    right: 10,
    top: 20,
    bottom: 20,
    data: data.legendData
  },
  series: [
    {
      name: '姓名',
      type: 'pie',
      radius: '55%',
      center: ['40%', '50%'],
      data: data.seriesData,
      emphasis: {
        itemStyle: {
          shadowBlur: 10,
          shadowOffsetX: 0,
          shadowColor: 'rgba(0, 0, 0, 0.5)'
        }
      }
    }
  ]
};
"""#,
        option: [
            "title": [
                "text": "同名数量统计",
                "subtext": "纯属虚构",
                "left": "center"
            ] as [String: Any],
            "tooltip": [
                "trigger": "item",
                // A string template, not a closure — ECharts expands {a}/{b}/{c}/{d} itself, so it ports.
                "formatter": "{a} <br/>{b} : {c} ({d}%)"
            ] as [String: Any],
            "legend": [
                "type": "scroll",
                "orient": "vertical",
                "right": 10.0,
                "top": 20.0,
                "bottom": 20.0,
                "data": pieLegendLegendData
            ] as [String: Any],
            "series": [
                [
                    "name": "姓名",
                    "type": "pie",
                    "radius": "55%",
                    "center": ["40%", "50%"],
                    "data": pieLegendSeriesData,
                    "emphasis": [
                        "itemStyle": [
                            "shadowBlur": 10.0,
                            "shadowOffsetX": 0.0,
                            "shadowColor": "rgba(0, 0, 0, 0.5)"
                        ] as [String: Any]
                    ] as [String: Any]
                ] as [String: Any]
            ]
        ])
}

// One frozen sample of the official `genData(50)`: 50 random surname-ish names, each with a
// 0..100000 value. Same list, same order, as the literals spliced into webOptionJS above.
private let pieLegendLegendData: [String] = [
    "皮吕朱", "施苗·韩强", "朱廉明·李张", "窦卫喻·朱彭鲍", "韩褚安", "康杜余陈·宋贾",
    "戴蒋袁", "薛薛谈云柏·水汪尤", "齐陈秦卞安·董麻", "谢舒", "费王茅·施平", "窦时韦",
    "毛伏", "殷魏茅·危", "俞屈宋", "何时曹罗·贾殷", "皮郑", "危周奚",
    "禹任萧·明", "茅熊", "袁余·方", "华禹郎", "郝席", "萧彭谈",
    "任任郑·顾邵", "酆袁章穆魏·赵", "费孙", "萧卜", "韩萧", "戚任祁席·余鲍",
    "祝魏毛俞·唐", "彭阮", "计姚郝", "杜金", "沈鲁", "皮唐",
    "常任·柳", "金卜", "戚尹", "苏成麻邵·韩贾", "狄陶顾", "计项柳",
    "齐贺杨·李", "穆魏·贾禹董", "孟曹姜", "余郎", "明张廉茅·姚阮倪", "臧吴施",
    "汤魏沈", "梁廉·蓝余苗"
]

private let pieLegendSeriesData: [[String: Any]] = [
    ["name": "皮吕朱", "value": 88138.0] as [String: Any],
    ["name": "施苗·韩强", "value": 72627.0] as [String: Any],
    ["name": "朱廉明·李张", "value": 37381.0] as [String: Any],
    ["name": "窦卫喻·朱彭鲍", "value": 19258.0] as [String: Any],
    ["name": "韩褚安", "value": 28262.0] as [String: Any],
    ["name": "康杜余陈·宋贾", "value": 9896.0] as [String: Any],
    ["name": "戴蒋袁", "value": 14935.0] as [String: Any],
    ["name": "薛薛谈云柏·水汪尤", "value": 19374.0] as [String: Any],
    ["name": "齐陈秦卞安·董麻", "value": 49097.0] as [String: Any],
    ["name": "谢舒", "value": 12390.0] as [String: Any],
    ["name": "费王茅·施平", "value": 19128.0] as [String: Any],
    ["name": "窦时韦", "value": 83318.0] as [String: Any],
    ["name": "毛伏", "value": 79205.0] as [String: Any],
    ["name": "殷魏茅·危", "value": 6124.0] as [String: Any],
    ["name": "俞屈宋", "value": 87057.0] as [String: Any],
    ["name": "何时曹罗·贾殷", "value": 96678.0] as [String: Any],
    ["name": "皮郑", "value": 63471.0] as [String: Any],
    ["name": "危周奚", "value": 46118.0] as [String: Any],
    ["name": "禹任萧·明", "value": 82784.0] as [String: Any],
    ["name": "茅熊", "value": 8280.0] as [String: Any],
    ["name": "袁余·方", "value": 82580.0] as [String: Any],
    ["name": "华禹郎", "value": 1474.0] as [String: Any],
    ["name": "郝席", "value": 15652.0] as [String: Any],
    ["name": "萧彭谈", "value": 49764.0] as [String: Any],
    ["name": "任任郑·顾邵", "value": 9858.0] as [String: Any],
    ["name": "酆袁章穆魏·赵", "value": 57030.0] as [String: Any],
    ["name": "费孙", "value": 10287.0] as [String: Any],
    ["name": "萧卜", "value": 56776.0] as [String: Any],
    ["name": "韩萧", "value": 61996.0] as [String: Any],
    ["name": "戚任祁席·余鲍", "value": 41710.0] as [String: Any],
    ["name": "祝魏毛俞·唐", "value": 70548.0] as [String: Any],
    ["name": "彭阮", "value": 40368.0] as [String: Any],
    ["name": "计姚郝", "value": 40006.0] as [String: Any],
    ["name": "杜金", "value": 44561.0] as [String: Any],
    ["name": "沈鲁", "value": 5775.0] as [String: Any],
    ["name": "皮唐", "value": 22099.0] as [String: Any],
    ["name": "常任·柳", "value": 61147.0] as [String: Any],
    ["name": "金卜", "value": 9125.0] as [String: Any],
    ["name": "戚尹", "value": 28285.0] as [String: Any],
    ["name": "苏成麻邵·韩贾", "value": 10606.0] as [String: Any],
    ["name": "狄陶顾", "value": 41791.0] as [String: Any],
    ["name": "计项柳", "value": 25198.0] as [String: Any],
    ["name": "齐贺杨·李", "value": 70685.0] as [String: Any],
    ["name": "穆魏·贾禹董", "value": 20176.0] as [String: Any],
    ["name": "孟曹姜", "value": 93817.0] as [String: Any],
    ["name": "余郎", "value": 89423.0] as [String: Any],
    ["name": "明张廉茅·姚阮倪", "value": 17490.0] as [String: Any],
    ["name": "臧吴施", "value": 71789.0] as [String: Any],
    ["name": "汤魏沈", "value": 46232.0] as [String: Any],
    ["name": "梁廉·蓝余苗", "value": 46592.0] as [String: Any]
]
