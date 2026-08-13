// official-geo-lines — replica of https://echarts.apache.org/examples/zh/editor.html?c=geo-lines
// title: Migration / titleCN: 模拟迁徙
//
// Three "Top 10" migration fans (北京 / 上海 / 广州, one colour each) over the china geo map on the dark
// #404a59 backdrop. Each fan is THREE series sharing one legend name, so `legend.selectedMode: 'single'`
// swaps the whole fan: a zlevel-1 `lines` series with width-0 lines carrying a 6s comet `effect` (the
// glowing trail), a zlevel-2 `lines` series drawing the visible curved arrow (curveness 0.2) whose
// `effect.symbol` is the `planePath` aeroplane glyph, and a zlevel-2 `effectScatter` on
// `coordinateSystem: 'geo'` rippling at each destination city. Coordinates come from a hand-written
// `geoCoordMap` (114 cities) joined to the {from, to, value} pairs by `convertData()`.
//
// DEVIATIONS from the official source:
//   - THE CHINA MAP IS REGISTERED BY US. The source says `geo: { map: 'china' }` but never registers it —
//     echarts ships no built-in map and the official editor injects `china` behind the scenes, so a
//     verbatim port renders a blank geo on BOTH panes. It therefore goes through `mapRegistrations`
//     (WebPage.swift injects `echarts.registerMap('china', …)` before the option script; the native pane
//     calls ECharts.registerMap), from assets/geo/china.json — the repo's own vendored, ASF-licensed map,
//     exactly as official-scatter-map.swift does. Nothing else about the option changed.
//   - THE COMET TRAIL AND THE RIPPLES ARE ANIMATIONS. `effect` (period 6s, trailLength) on the two `lines`
//     series and `rippleEffect` on the effectScatter are time-driven. Their independent native/Web clocks
//     cannot be phase-locked in a still comparison, so snapshot mode changes only effectScatter's
//     `showEffectOn` to `emphasis` in both panes and compares the stable weighted core points plus all map,
//     line, label and legend geometry. The live gallery keeps the official looping effects unchanged.
//   - series[0].lineStyle uses legacy ec2 `{ normal: { … } }` nesting in the Web source, where echarts'
//     backwardCompat preprocessor flattens it. The native option carries that normalized result directly,
//     because EChartsKit does not run the legacy preprocessor at option ingress.
//   - series[2].symbolSize is a JS closure; the native pane carries the equivalent typed Swift callback.
//   - `convertData()` is likewise JS-only: the native option carries its RESULT, computed in Swift from the
//     same inputs by the same lookup-and-skip rule.
//   - No data fetch, no timers, no `app.*` in the source; nothing else changed.
import Foundation
import EChartsKit

// The china map (34 provinces/regions + 8 boundary-line features). Parsed ONCE from the repo asset; a
// parse failure degrades to an empty FeatureCollection (the pane renders blank rather than crashing).
private let chinaGeoJSON: [String: Any] = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/geo/china.json")
    guard let data = try? Data(contentsOf: url),
          let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        return ["type": "FeatureCollection", "features": [] as [Any]]
    }
    return obj
}()

// Upstream `var geoCoordMap = { 上海: [121.4648, 31.2891], … }` — city → [lng, lat] (114 cities).
private let geoLinesGeoCoordMap: [String: [Double]] = [
    "上海": [121.4648, 31.2891],
    "东莞": [113.8953, 22.901],
    "东营": [118.7073, 37.5513],
    "中山": [113.4229, 22.478],
    "临汾": [111.4783, 36.1615],
    "临沂": [118.3118, 35.2936],
    "丹东": [124.541, 40.4242],
    "丽水": [119.5642, 28.1854],
    "乌鲁木齐": [87.9236, 43.5883],
    "佛山": [112.8955, 23.1097],
    "保定": [115.0488, 39.0948],
    "兰州": [103.5901, 36.3043],
    "包头": [110.3467, 41.4899],
    "北京": [116.4551, 40.2539],
    "北海": [109.314, 21.6211],
    "南京": [118.8062, 31.9208],
    "南宁": [108.479, 23.1152],
    "南昌": [116.0046, 28.6633],
    "南通": [121.1023, 32.1625],
    "厦门": [118.1689, 24.6478],
    "台州": [121.1353, 28.6688],
    "合肥": [117.29, 32.0581],
    "呼和浩特": [111.4124, 40.4901],
    "咸阳": [108.4131, 34.8706],
    "哈尔滨": [127.9688, 45.368],
    "唐山": [118.4766, 39.6826],
    "嘉兴": [120.9155, 30.6354],
    "大同": [113.7854, 39.8035],
    "大连": [122.2229, 39.4409],
    "天津": [117.4219, 39.4189],
    "太原": [112.3352, 37.9413],
    "威海": [121.9482, 37.1393],
    "宁波": [121.5967, 29.6466],
    "宝鸡": [107.1826, 34.3433],
    "宿迁": [118.5535, 33.7775],
    "常州": [119.4543, 31.5582],
    "广州": [113.5107, 23.2196],
    "廊坊": [116.521, 39.0509],
    "延安": [109.1052, 36.4252],
    "张家口": [115.1477, 40.8527],
    "徐州": [117.5208, 34.3268],
    "德州": [116.6858, 37.2107],
    "惠州": [114.6204, 23.1647],
    "成都": [103.9526, 30.7617],
    "扬州": [119.4653, 32.8162],
    "承德": [117.5757, 41.4075],
    "拉萨": [91.1865, 30.1465],
    "无锡": [120.3442, 31.5527],
    "日照": [119.2786, 35.5023],
    "昆明": [102.9199, 25.4663],
    "杭州": [119.5313, 29.8773],
    "枣庄": [117.323, 34.8926],
    "柳州": [109.3799, 24.9774],
    "株洲": [113.5327, 27.0319],
    "武汉": [114.3896, 30.6628],
    "汕头": [117.1692, 23.3405],
    "江门": [112.6318, 22.1484],
    "沈阳": [123.1238, 42.1216],
    "沧州": [116.8286, 38.2104],
    "河源": [114.917, 23.9722],
    "泉州": [118.3228, 25.1147],
    "泰安": [117.0264, 36.0516],
    "泰州": [120.0586, 32.5525],
    "济南": [117.1582, 36.8701],
    "济宁": [116.8286, 35.3375],
    "海口": [110.3893, 19.8516],
    "淄博": [118.0371, 36.6064],
    "淮安": [118.927, 33.4039],
    "深圳": [114.5435, 22.5439],
    "清远": [112.9175, 24.3292],
    "温州": [120.498, 27.8119],
    "渭南": [109.7864, 35.0299],
    "湖州": [119.8608, 30.7782],
    "湘潭": [112.5439, 27.7075],
    "滨州": [117.8174, 37.4963],
    "潍坊": [119.0918, 36.524],
    "烟台": [120.7397, 37.5128],
    "玉溪": [101.9312, 23.8898],
    "珠海": [113.7305, 22.1155],
    "盐城": [120.2234, 33.5577],
    "盘锦": [121.9482, 41.0449],
    "石家庄": [114.4995, 38.1006],
    "福州": [119.4543, 25.9222],
    "秦皇岛": [119.2126, 40.0232],
    "绍兴": [120.564, 29.7565],
    "聊城": [115.9167, 36.4032],
    "肇庆": [112.1265, 23.5822],
    "舟山": [122.2559, 30.2234],
    "苏州": [120.6519, 31.3989],
    "莱芜": [117.6526, 36.2714],
    "菏泽": [115.6201, 35.2057],
    "营口": [122.4316, 40.4297],
    "葫芦岛": [120.1575, 40.578],
    "衡水": [115.8838, 37.7161],
    "衢州": [118.6853, 28.8666],
    "西宁": [101.4038, 36.8207],
    "西安": [109.1162, 34.2004],
    "贵阳": [106.6992, 26.7682],
    "连云港": [119.1248, 34.552],
    "邢台": [114.8071, 37.2821],
    "邯郸": [114.4775, 36.535],
    "郑州": [113.4668, 34.6234],
    "鄂尔多斯": [108.9734, 39.2487],
    "重庆": [107.7539, 30.1904],
    "金华": [120.0037, 29.1028],
    "铜川": [109.0393, 35.1947],
    "银川": [106.3586, 38.1775],
    "镇江": [119.4763, 31.9702],
    "长春": [125.8154, 44.2584],
    "长沙": [113.0823, 28.2568],
    "长治": [112.8625, 36.4746],
    "阳泉": [113.4778, 38.0951],
    "青岛": [120.4651, 36.3373],
    "韶关": [113.7964, 24.7028],
]

// Upstream BJData / SHData / GZData: `[{ name: <from> }, { name: <to>, value: <v> }]` → (from, to, value).
private let geoLinesBJData: [(String, String, Double)] = [
    ("北京", "上海", 95.0),
    ("北京", "广州", 90.0),
    ("北京", "大连", 80.0),
    ("北京", "南宁", 70.0),
    ("北京", "南昌", 60.0),
    ("北京", "拉萨", 50.0),
    ("北京", "长春", 40.0),
    ("北京", "包头", 30.0),
    ("北京", "重庆", 20.0),
    ("北京", "常州", 10.0),
]

private let geoLinesSHData: [(String, String, Double)] = [
    ("上海", "包头", 95.0),
    ("上海", "昆明", 90.0),
    ("上海", "广州", 80.0),
    ("上海", "郑州", 70.0),
    ("上海", "长春", 60.0),
    ("上海", "重庆", 50.0),
    ("上海", "长沙", 40.0),
    ("上海", "北京", 30.0),
    ("上海", "丹东", 20.0),
    ("上海", "大连", 10.0),
]

private let geoLinesGZData: [(String, String, Double)] = [
    ("广州", "福州", 95.0),
    ("广州", "太原", 90.0),
    ("广州", "长春", 80.0),
    ("广州", "重庆", 70.0),
    ("广州", "西安", 60.0),
    ("广州", "成都", 50.0),
    ("广州", "常州", 40.0),
    ("广州", "北京", 30.0),
    ("广州", "北海", 20.0),
    ("广州", "海口", 10.0),
]

// Upstream `var planePath = 'path://…'` — the aeroplane glyph flown along the zlevel-2 lines' effect.
private let geoLinesPlanePath =
    "path://M1705.06,1318.313v-89.254l-319.9-221.799l0.073-208.063c0.521-84.662-26.629-121.796-63.961-121.491c-37.332-0.305-64.482,36.829-63.961,121.491l0.073,208.063l-319.9,221.799v89.254l330.343-157.288l12.238,241.308l-134.449,92.931l0.531,42.034l175.125-42.917l175.125,42.917l0.531-42.034l-134.449-92.931l12.238-241.308L1705.06,1318.313z"

// Upstream `convertData(data)`: join each {from, to} pair to its two [lng, lat] coords and emit
// { fromName, toName, coords: [from, to] }; a pair whose city is missing from geoCoordMap is SKIPPED
// (here: none are). This is the `lines` series' data.
private func geoLinesConvertData(_ data: [(String, String, Double)]) -> [[String: Any]] {
    data.compactMap { from, to, _ in
        guard let fromCoord = geoLinesGeoCoordMap[from], let toCoord = geoLinesGeoCoordMap[to] else {
            return nil
        }
        return ["fromName": from, "toName": to, "coords": [fromCoord, toCoord]]
    }
}

// Upstream `item[1].map(dataItem => ({ name, value: geoCoordMap[name].concat([value]) }))` — the
// effectScatter's data: one dot per DESTINATION city, value = [lng, lat, weight].
private func geoLinesScatterData(_ data: [(String, String, Double)]) -> [[String: Any]] {
    data.compactMap { _, to, value in
        guard let coord = geoLinesGeoCoordMap[to] else { return nil }
        return ["name": to, "value": [coord[0], coord[1], value]]
    }
}

// Upstream's `[['北京', BJData], ['上海', SHData], ['广州', GZData]].forEach(...)` series builder: three
// series per fan (comet `lines`, arrow `lines`, `effectScatter`), all sharing the fan's legend name.
private let geoLinesSeries: [[String: Any]] = {
    let color = ["#a6c84c", "#ffa022", "#46bee9"]
    let fans: [(String, [(String, String, Double)])] = [
        ("北京", geoLinesBJData), ("上海", geoLinesSHData), ("广州", geoLinesGZData)
    ]
    var series: [[String: Any]] = []
    for (i, fan) in fans.enumerated() {
        let (city, data) = fan
        series.append([
            "name": city + " Top10",
            "type": "lines",
            "zlevel": 1.0,
            "effect": [
                "show": true,
                "period": 6.0,
                "trailLength": 0.7,
                "color": "#fff",
                "symbolSize": 3.0
            ] as [String: Any],
            // Native equivalent of Web backwardCompat flattening legacy `lineStyle.normal`.
            "lineStyle": [
                "color": color[i],
                "width": 0.0,
                "curveness": 0.2
            ] as [String: Any],
            "data": geoLinesConvertData(data) as [Any]
        ] as [String: Any])
        series.append([
            "name": city + " Top10",
            "type": "lines",
            "zlevel": 2.0,
            "symbol": ["none", "arrow"],
            "symbolSize": 10.0,
            "effect": [
                "show": true,
                "period": 6.0,
                "trailLength": 0.0,
                "symbol": geoLinesPlanePath,
                "symbolSize": 15.0
            ] as [String: Any],
            "lineStyle": [
                "color": color[i],
                "width": 1.0,
                "opacity": 0.6,
                "curveness": 0.2
            ] as [String: Any],
            "data": geoLinesConvertData(data) as [Any]
        ] as [String: Any])
        series.append([
            "name": city + " Top10",
            "type": "effectScatter",
            "coordinateSystem": "geo",
            "zlevel": 2.0,
            "rippleEffect": [
                "brushType": "stroke"
            ] as [String: Any],
            "label": [
                "show": true,
                "position": "right",
                "formatter": "{b}"
            ] as [String: Any],
            "symbolSize": { (rawValue: Any, _: CallbackDataParams) -> Any in
                guard let value = rawValue as? [Any], value.count > 2,
                      let weight = value[2] as? NSNumber else { return 0.0 }
                return weight.doubleValue / 8.0
            } as SymbolSizeCallback<CallbackDataParams>,
            "itemStyle": [
                "color": color[i]
            ] as [String: Any],
            "data": geoLinesScatterData(data) as [Any]
        ] as [String: Any])
    }
    return series
}()

extension EChartsDemoRegistry {
    static let official_geo_lines = EChartsDemo(
        name: "official-geo-lines", category: "map",
        summary: "模拟迁徙 — Migration",
        width: 720, height: 460,
        nativeSupported: true,
        mapRegistrations: ["china": chinaGeoJSON],
        collection: .official,
        webOptionJS: #"""
var geoCoordMap = {
  上海: [121.4648, 31.2891],
  东莞: [113.8953, 22.901],
  东营: [118.7073, 37.5513],
  中山: [113.4229, 22.478],
  临汾: [111.4783, 36.1615],
  临沂: [118.3118, 35.2936],
  丹东: [124.541, 40.4242],
  丽水: [119.5642, 28.1854],
  乌鲁木齐: [87.9236, 43.5883],
  佛山: [112.8955, 23.1097],
  保定: [115.0488, 39.0948],
  兰州: [103.5901, 36.3043],
  包头: [110.3467, 41.4899],
  北京: [116.4551, 40.2539],
  北海: [109.314, 21.6211],
  南京: [118.8062, 31.9208],
  南宁: [108.479, 23.1152],
  南昌: [116.0046, 28.6633],
  南通: [121.1023, 32.1625],
  厦门: [118.1689, 24.6478],
  台州: [121.1353, 28.6688],
  合肥: [117.29, 32.0581],
  呼和浩特: [111.4124, 40.4901],
  咸阳: [108.4131, 34.8706],
  哈尔滨: [127.9688, 45.368],
  唐山: [118.4766, 39.6826],
  嘉兴: [120.9155, 30.6354],
  大同: [113.7854, 39.8035],
  大连: [122.2229, 39.4409],
  天津: [117.4219, 39.4189],
  太原: [112.3352, 37.9413],
  威海: [121.9482, 37.1393],
  宁波: [121.5967, 29.6466],
  宝鸡: [107.1826, 34.3433],
  宿迁: [118.5535, 33.7775],
  常州: [119.4543, 31.5582],
  广州: [113.5107, 23.2196],
  廊坊: [116.521, 39.0509],
  延安: [109.1052, 36.4252],
  张家口: [115.1477, 40.8527],
  徐州: [117.5208, 34.3268],
  德州: [116.6858, 37.2107],
  惠州: [114.6204, 23.1647],
  成都: [103.9526, 30.7617],
  扬州: [119.4653, 32.8162],
  承德: [117.5757, 41.4075],
  拉萨: [91.1865, 30.1465],
  无锡: [120.3442, 31.5527],
  日照: [119.2786, 35.5023],
  昆明: [102.9199, 25.4663],
  杭州: [119.5313, 29.8773],
  枣庄: [117.323, 34.8926],
  柳州: [109.3799, 24.9774],
  株洲: [113.5327, 27.0319],
  武汉: [114.3896, 30.6628],
  汕头: [117.1692, 23.3405],
  江门: [112.6318, 22.1484],
  沈阳: [123.1238, 42.1216],
  沧州: [116.8286, 38.2104],
  河源: [114.917, 23.9722],
  泉州: [118.3228, 25.1147],
  泰安: [117.0264, 36.0516],
  泰州: [120.0586, 32.5525],
  济南: [117.1582, 36.8701],
  济宁: [116.8286, 35.3375],
  海口: [110.3893, 19.8516],
  淄博: [118.0371, 36.6064],
  淮安: [118.927, 33.4039],
  深圳: [114.5435, 22.5439],
  清远: [112.9175, 24.3292],
  温州: [120.498, 27.8119],
  渭南: [109.7864, 35.0299],
  湖州: [119.8608, 30.7782],
  湘潭: [112.5439, 27.7075],
  滨州: [117.8174, 37.4963],
  潍坊: [119.0918, 36.524],
  烟台: [120.7397, 37.5128],
  玉溪: [101.9312, 23.8898],
  珠海: [113.7305, 22.1155],
  盐城: [120.2234, 33.5577],
  盘锦: [121.9482, 41.0449],
  石家庄: [114.4995, 38.1006],
  福州: [119.4543, 25.9222],
  秦皇岛: [119.2126, 40.0232],
  绍兴: [120.564, 29.7565],
  聊城: [115.9167, 36.4032],
  肇庆: [112.1265, 23.5822],
  舟山: [122.2559, 30.2234],
  苏州: [120.6519, 31.3989],
  莱芜: [117.6526, 36.2714],
  菏泽: [115.6201, 35.2057],
  营口: [122.4316, 40.4297],
  葫芦岛: [120.1575, 40.578],
  衡水: [115.8838, 37.7161],
  衢州: [118.6853, 28.8666],
  西宁: [101.4038, 36.8207],
  西安: [109.1162, 34.2004],
  贵阳: [106.6992, 26.7682],
  连云港: [119.1248, 34.552],
  邢台: [114.8071, 37.2821],
  邯郸: [114.4775, 36.535],
  郑州: [113.4668, 34.6234],
  鄂尔多斯: [108.9734, 39.2487],
  重庆: [107.7539, 30.1904],
  金华: [120.0037, 29.1028],
  铜川: [109.0393, 35.1947],
  银川: [106.3586, 38.1775],
  镇江: [119.4763, 31.9702],
  长春: [125.8154, 44.2584],
  长沙: [113.0823, 28.2568],
  长治: [112.8625, 36.4746],
  阳泉: [113.4778, 38.0951],
  青岛: [120.4651, 36.3373],
  韶关: [113.7964, 24.7028]
};

var BJData = [
  [{ name: '北京' }, { name: '上海', value: 95 }],
  [{ name: '北京' }, { name: '广州', value: 90 }],
  [{ name: '北京' }, { name: '大连', value: 80 }],
  [{ name: '北京' }, { name: '南宁', value: 70 }],
  [{ name: '北京' }, { name: '南昌', value: 60 }],
  [{ name: '北京' }, { name: '拉萨', value: 50 }],
  [{ name: '北京' }, { name: '长春', value: 40 }],
  [{ name: '北京' }, { name: '包头', value: 30 }],
  [{ name: '北京' }, { name: '重庆', value: 20 }],
  [{ name: '北京' }, { name: '常州', value: 10 }]
];

var SHData = [
  [{ name: '上海' }, { name: '包头', value: 95 }],
  [{ name: '上海' }, { name: '昆明', value: 90 }],
  [{ name: '上海' }, { name: '广州', value: 80 }],
  [{ name: '上海' }, { name: '郑州', value: 70 }],
  [{ name: '上海' }, { name: '长春', value: 60 }],
  [{ name: '上海' }, { name: '重庆', value: 50 }],
  [{ name: '上海' }, { name: '长沙', value: 40 }],
  [{ name: '上海' }, { name: '北京', value: 30 }],
  [{ name: '上海' }, { name: '丹东', value: 20 }],
  [{ name: '上海' }, { name: '大连', value: 10 }]
];

var GZData = [
  [{ name: '广州' }, { name: '福州', value: 95 }],
  [{ name: '广州' }, { name: '太原', value: 90 }],
  [{ name: '广州' }, { name: '长春', value: 80 }],
  [{ name: '广州' }, { name: '重庆', value: 70 }],
  [{ name: '广州' }, { name: '西安', value: 60 }],
  [{ name: '广州' }, { name: '成都', value: 50 }],
  [{ name: '广州' }, { name: '常州', value: 40 }],
  [{ name: '广州' }, { name: '北京', value: 30 }],
  [{ name: '广州' }, { name: '北海', value: 20 }],
  [{ name: '广州' }, { name: '海口', value: 10 }]
];

var planePath =
  'path://M1705.06,1318.313v-89.254l-319.9-221.799l0.073-208.063c0.521-84.662-26.629-121.796-63.961-121.491c-37.332-0.305-64.482,36.829-63.961,121.491l0.073,208.063l-319.9,221.799v89.254l330.343-157.288l12.238,241.308l-134.449,92.931l0.531,42.034l175.125-42.917l175.125,42.917l0.531-42.034l-134.449-92.931l12.238-241.308L1705.06,1318.313z';

var convertData = function (data) {
  var res = [];
  for (var i = 0; i < data.length; i++) {
    var dataItem = data[i];
    var fromCoord = geoCoordMap[dataItem[0].name];
    var toCoord = geoCoordMap[dataItem[1].name];
    if (fromCoord && toCoord) {
      res.push({
        fromName: dataItem[0].name,
        toName: dataItem[1].name,
        coords: [fromCoord, toCoord]
      });
    }
  }
  return res;
};

var color = ['#a6c84c', '#ffa022', '#46bee9'];
var series = [];
[
  ['北京', BJData],
  ['上海', SHData],
  ['广州', GZData]
].forEach(function (item, i) {
  series.push(
    {
      name: item[0] + ' Top10',
      type: 'lines',
      zlevel: 1,
      effect: {
        show: true,
        period: 6,
        trailLength: 0.7,
        color: '#fff',
        symbolSize: 3
      },
      lineStyle: {
        normal: {
          color: color[i],
          width: 0,
          curveness: 0.2
        }
      },
      data: convertData(item[1])
    },
    {
      name: item[0] + ' Top10',
      type: 'lines',
      zlevel: 2,
      symbol: ['none', 'arrow'],
      symbolSize: 10,
      effect: {
        show: true,
        period: 6,
        trailLength: 0,
        symbol: planePath,
        symbolSize: 15
      },
      lineStyle: {
        color: color[i],
        width: 1,
        opacity: 0.6,
        curveness: 0.2
      },
      data: convertData(item[1])
    },
    {
      name: item[0] + ' Top10',
      type: 'effectScatter',
      coordinateSystem: 'geo',
      zlevel: 2,
      rippleEffect: {
        brushType: 'stroke'
      },
      label: {
        show: true,
        position: 'right',
        formatter: '{b}'
      },
      symbolSize: function (val) {
        return val[2] / 8;
      },
      itemStyle: {
        color: color[i]
      },
      data: item[1].map(function (dataItem) {
        return {
          name: dataItem[1].name,
          value: geoCoordMap[dataItem[1].name].concat([dataItem[1].value])
        };
      })
    }
  );
});

option = {
  backgroundColor: '#404a59',
  title: {
    text: '模拟迁徙',
    subtext: '数据纯属虚构',
    left: 'center',
    textStyle: {
      color: '#fff'
    }
  },
  tooltip: {
    trigger: 'item'
  },
  legend: {
    orient: 'vertical',
    top: 'bottom',
    left: 'right',
    data: ['北京 Top10', '上海 Top10', '广州 Top10'],
    textStyle: {
      color: '#fff'
    },
    selectedMode: 'single'
  },
  geo: {
    map: 'china',
    label: {
      show: false
    },
    roam: true,
    itemStyle: {
      areaColor: '#323c48',
      borderColor: '#404a59'
    },

    emphasis: {
      label: {
        show: true
      },
      itemStyle: {
        areaColor: '#2a333d'
      }
    }
  },
  series: series
};

// A still screenshot cannot synchronize the two independent looping animation clocks. Keep the live
// demo unchanged; for the deterministic comparison frame, render weighted core points without ripples.
if (__snapshot) {
  option.series.forEach(function (s) {
    if (s.type === 'effectScatter') {
      s.showEffectOn = 'emphasis';
    }
  });
}
"""#,
        option: {
            // The map the `geo` component names — upstream leaves this to the example editor (see header).
            ECharts.registerMap("china", chinaGeoJSON)
            return [
                "backgroundColor": "#404a59",
                "title": [
                    "text": "模拟迁徙",
                    "subtext": "数据纯属虚构",
                    "left": "center",
                    "textStyle": [
                        "color": "#fff"
                    ] as [String: Any]
                ] as [String: Any],
                "tooltip": [
                    "trigger": "item"
                ] as [String: Any],
                "legend": [
                    "orient": "vertical",
                    "top": "bottom",
                    "left": "right",
                    "data": ["北京 Top10", "上海 Top10", "广州 Top10"],
                    "textStyle": [
                        "color": "#fff"
                    ] as [String: Any],
                    "selectedMode": "single"
                ] as [String: Any],
                "geo": [
                    "map": "china",
                    "label": [
                        "show": false
                    ] as [String: Any],
                    "roam": true,
                    "itemStyle": [
                        "areaColor": "#323c48",
                        "borderColor": "#404a59"
                    ] as [String: Any],
                    "emphasis": [
                        "label": [
                            "show": true
                        ] as [String: Any],
                        "itemStyle": [
                            "areaColor": "#2a333d"
                        ] as [String: Any]
                    ] as [String: Any]
                ] as [String: Any],
                "series": geoLinesSeries as [Any]
            ]
        }())
}
