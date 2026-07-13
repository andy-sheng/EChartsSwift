// official-geo-map-scatter — replica of https://echarts.apache.org/examples/zh/editor.html?c=geo-map-scatter
// title: map and scatter share a geo / titleCN: map and scatter share a geo
//
// ONE `geo` (the china map) shared by TWO series: a `scatter` of 27 cities pinned to it via
// `coordinateSystem: 'geo'` (each an orange #F06C00, 20px, 35deg-rotated aircraft glyph given as
// `symbol: 'path://…'`, its [lng, lat] joined to the reading by `convertData()`), plus a `map` series
// bound to that SAME geo through `geoIndex: 0`, whose 34 provinces form a choropleth. The calculable
// `visualMap` (0-1500, #e0ffff→#006edd) is scoped by `seriesIndex: [1]`, so it colours only the province
// choropleth and leaves the scatter glyphs their flat orange — that scoping is the point of the example.
//
// DEVIATIONS from the official source:
//   - randomValue() IS FROZEN TO A SINGLE DRAW. Upstream fills all 34 provinces with
//     `Math.round(Math.random() * 1000)`, so every reload recolours the choropleth. This gallery exists to
//     DIFF the native pane against the echarts.js pane, and two independent Math.random() draws would make
//     the panes disagree on every render — hiding any real porting gap in the noise. One draw is therefore
//     baked in as literals, IDENTICAL on both sides (geoMapScatterProvinceData below and the inlined JS
//     data array), and `randomValue()` is dropped. Nothing else about that series changes.
//   - THE CHINA MAP IS REGISTERED BY US. The source says `geo: { map: 'china' }` but never registers it —
//     echarts ships no built-in map and the official editor injects `china` behind the scenes, so a
//     verbatim port renders a blank geo on BOTH panes. The map goes through `mapRegistrations` instead
//     (WebPage.swift injects `echarts.registerMap('china', …)` ahead of the option script; the native pane
//     calls ECharts.registerMap), read from assets/geo/china.json — the repo's own vendored, ASF-licensed
//     map, the same asset official-scatter-map.swift uses.
//   - `convertData()` is JS-only: the web pane runs it verbatim; the native option carries its RESULT,
//     computed in Swift from the same two inputs by the same lookup-and-skip rule (all 27 cities resolve).
//   - `geo.emphasis.itemStyle.areaColor: null` is carried as NSNull() — EChartsKit's JS-`null` convention,
//     i.e. an explicit "no emphasis fill", so a hovered province keeps its visualMap colour.
//   - `roam: true` is kept verbatim; the gallery renders one static frame, so it shows the initial view.
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

// Upstream `var geoCoordMap = { 海门: [121.15, 31.89], … }` — city → [lng, lat] (190 entries; the scatter
// series uses 27 of them, the rest are dead weight upstream too).
private let geoMapScatterGeoCoordMap: [String: [Double]] = [
    "海门": [121.15, 31.89],
    "鄂尔多斯": [109.781327, 39.608266],
    "招远": [120.38, 37.35],
    "舟山": [122.207216, 29.985295],
    "齐齐哈尔": [123.97, 47.33],
    "盐城": [120.13, 33.38],
    "赤峰": [118.87, 42.28],
    "青岛": [120.33, 36.07],
    "乳山": [121.52, 36.89],
    "金昌": [102.188043, 38.520089],
    "泉州": [118.58, 24.93],
    "莱西": [120.53, 36.86],
    "日照": [119.46, 35.42],
    "胶南": [119.97, 35.88],
    "南通": [121.05, 32.08],
    "拉萨": [91.11, 29.97],
    "云浮": [112.02, 22.93],
    "梅州": [116.1, 24.55],
    "文登": [122.05, 37.2],
    "上海": [121.48, 31.22],
    "攀枝花": [101.718637, 26.582347],
    "威海": [122.1, 37.5],
    "承德": [117.93, 40.97],
    "厦门": [118.1, 24.46],
    "汕尾": [115.375279, 22.786211],
    "潮州": [116.63, 23.68],
    "丹东": [124.37, 40.13],
    "太仓": [121.1, 31.45],
    "曲靖": [103.79, 25.51],
    "烟台": [121.39, 37.52],
    "福州": [119.3, 26.08],
    "瓦房店": [121.979603, 39.627114],
    "即墨": [120.45, 36.38],
    "抚顺": [123.97, 41.97],
    "玉溪": [102.52, 24.35],
    "张家口": [114.87, 40.82],
    "阳泉": [113.57, 37.85],
    "莱州": [119.942327, 37.177017],
    "湖州": [120.1, 30.86],
    "汕头": [116.69, 23.39],
    "昆山": [120.95, 31.39],
    "宁波": [121.56, 29.86],
    "湛江": [110.359377, 21.270708],
    "揭阳": [116.35, 23.55],
    "荣成": [122.41, 37.16],
    "连云港": [119.16, 34.59],
    "葫芦岛": [120.836932, 40.711052],
    "常熟": [120.74, 31.64],
    "东莞": [113.75, 23.04],
    "河源": [114.68, 23.73],
    "淮安": [119.15, 33.5],
    "泰州": [119.9, 32.49],
    "南宁": [108.33, 22.84],
    "营口": [122.18, 40.65],
    "惠州": [114.4, 23.09],
    "江阴": [120.26, 31.91],
    "蓬莱": [120.75, 37.8],
    "韶关": [113.62, 24.84],
    "嘉峪关": [98.289152, 39.77313],
    "广州": [113.23, 23.16],
    "延安": [109.47, 36.6],
    "太原": [112.53, 37.87],
    "清远": [113.01, 23.7],
    "中山": [113.38, 22.52],
    "昆明": [102.73, 25.04],
    "寿光": [118.73, 36.86],
    "盘锦": [122.070714, 41.119997],
    "长治": [113.08, 36.18],
    "深圳": [114.07, 22.62],
    "珠海": [113.52, 22.3],
    "宿迁": [118.3, 33.96],
    "咸阳": [108.72, 34.36],
    "铜川": [109.11, 35.09],
    "平度": [119.97, 36.77],
    "佛山": [113.11, 23.05],
    "海口": [110.35, 20.02],
    "江门": [113.06, 22.61],
    "章丘": [117.53, 36.72],
    "肇庆": [112.44, 23.05],
    "大连": [121.62, 38.92],
    "临汾": [111.5, 36.08],
    "吴江": [120.63, 31.16],
    "石嘴山": [106.39, 39.04],
    "沈阳": [123.38, 41.8],
    "苏州": [120.62, 31.32],
    "茂名": [110.88, 21.68],
    "嘉兴": [120.76, 30.77],
    "长春": [125.35, 43.88],
    "胶州": [120.03336, 36.264622],
    "银川": [106.27, 38.47],
    "张家港": [120.555821, 31.875428],
    "三门峡": [111.19, 34.76],
    "锦州": [121.15, 41.13],
    "南昌": [115.89, 28.68],
    "柳州": [109.4, 24.33],
    "三亚": [109.511909, 18.252847],
    "自贡": [104.778442, 29.33903],
    "吉林": [126.57, 43.87],
    "阳江": [111.95, 21.85],
    "泸州": [105.39, 28.91],
    "西宁": [101.74, 36.56],
    "宜宾": [104.56, 29.77],
    "呼和浩特": [111.65, 40.82],
    "成都": [104.06, 30.67],
    "大同": [113.3, 40.12],
    "镇江": [119.44, 32.2],
    "桂林": [110.28, 25.29],
    "张家界": [110.479191, 29.117096],
    "宜兴": [119.82, 31.36],
    "北海": [109.12, 21.49],
    "西安": [108.95, 34.27],
    "金坛": [119.56, 31.74],
    "东营": [118.49, 37.46],
    "牡丹江": [129.58, 44.6],
    "遵义": [106.9, 27.7],
    "绍兴": [120.58, 30.01],
    "扬州": [119.42, 32.39],
    "常州": [119.95, 31.79],
    "潍坊": [119.1, 36.62],
    "重庆": [106.54, 29.59],
    "台州": [121.420757, 28.656386],
    "南京": [118.78, 32.04],
    "滨州": [118.03, 37.36],
    "贵阳": [106.71, 26.57],
    "无锡": [120.29, 31.59],
    "本溪": [123.73, 41.3],
    "克拉玛依": [84.77, 45.59],
    "渭南": [109.5, 34.52],
    "马鞍山": [118.48, 31.56],
    "宝鸡": [107.15, 34.38],
    "焦作": [113.21, 35.24],
    "句容": [119.16, 31.95],
    "北京": [116.46, 39.92],
    "徐州": [117.2, 34.26],
    "衡水": [115.72, 37.72],
    "包头": [110.0, 40.58],
    "绵阳": [104.73, 31.48],
    "乌鲁木齐": [87.68, 43.77],
    "枣庄": [117.57, 34.86],
    "杭州": [120.19, 30.26],
    "淄博": [118.05, 36.78],
    "鞍山": [122.85, 41.12],
    "溧阳": [119.48, 31.43],
    "库尔勒": [86.06, 41.68],
    "安阳": [114.35, 36.1],
    "开封": [114.35, 34.79],
    "济南": [117.0, 36.65],
    "德阳": [104.37, 31.13],
    "温州": [120.65, 28.01],
    "九江": [115.97, 29.71],
    "邯郸": [114.47, 36.6],
    "临安": [119.72, 30.23],
    "兰州": [103.73, 36.03],
    "沧州": [116.83, 38.33],
    "临沂": [118.35, 35.05],
    "南充": [106.110698, 30.837793],
    "天津": [117.2, 39.13],
    "富阳": [119.95, 30.07],
    "泰安": [117.13, 36.18],
    "诸暨": [120.23, 29.71],
    "郑州": [113.65, 34.76],
    "哈尔滨": [126.63, 45.75],
    "聊城": [115.97, 36.45],
    "芜湖": [118.38, 31.33],
    "唐山": [118.02, 39.63],
    "平顶山": [113.29, 33.75],
    "邢台": [114.48, 37.05],
    "德州": [116.29, 37.45],
    "济宁": [116.59, 35.38],
    "荆州": [112.239741, 30.335165],
    "宜昌": [111.3, 30.7],
    "义乌": [120.06, 29.32],
    "丽水": [119.92, 28.45],
    "洛阳": [112.44, 34.7],
    "秦皇岛": [119.57, 39.95],
    "株洲": [113.16, 27.83],
    "石家庄": [114.48, 38.03],
    "莱芜": [117.67, 36.19],
    "常德": [111.69, 29.05],
    "保定": [115.48, 38.85],
    "湘潭": [112.91, 27.87],
    "金华": [119.64, 29.12],
    "岳阳": [113.09, 29.37],
    "长沙": [113.0, 28.21],
    "衢州": [118.88, 28.97],
    "廊坊": [116.7, 39.53],
    "菏泽": [115.480656, 35.23375],
    "合肥": [117.27, 31.86],
    "武汉": [114.31, 30.52],
    "大庆": [125.03, 46.58],
]

// Upstream `var data = [{ name: '海门', value: 9 }, … ]` — the scatter's 27 readings, in source order.
private let geoMapScatterCities: [(String, Double)] = [
    ("海门", 9.0),
    ("鄂尔多斯", 12.0),
    ("招远", 12.0),
    ("舟山", 12.0),
    ("齐齐哈尔", 14.0),
    ("盐城", 15.0),
    ("赤峰", 16.0),
    ("青岛", 18.0),
    ("乳山", 18.0),
    ("金昌", 19.0),
    ("泉州", 21.0),
    ("南通", 23.0),
    ("拉萨", 24.0),
    ("云浮", 24.0),
    ("上海", 25.0),
    ("攀枝花", 25.0),
    ("承德", 25.0),
    ("汕尾", 26.0),
    ("丹东", 27.0),
    ("瓦房店", 30.0),
    ("延安", 38.0),
    ("咸阳", 43.0),
    ("南昌", 54.0),
    ("柳州", 54.0),
    ("三亚", 54.0),
    ("泸州", 57.0),
    ("克拉玛依", 72.0),
]

// Upstream `convertData(data)`: join each reading to its [lng, lat] and emit { name, value: [lng, lat,
// reading] }; a city missing from geoCoordMap is SKIPPED (here: none are).
private let geoMapScatterData: [[String: Any]] = geoMapScatterCities.compactMap { city, value in
    guard let coord = geoMapScatterGeoCoordMap[city] else { return nil }
    return ["name": city, "value": [coord[0], coord[1], value]]
}

// The `map` series' 34 provinces. Upstream calls `randomValue()` (Math.round(Math.random() * 1000)) for
// each; this is ONE frozen draw of that, so the two panes agree (see DEVIATIONS).
private let geoMapScatterProvinceData: [[String: Any]] = [
    ["name": "北京", "value": 289.0],
    ["name": "天津", "value": 897.0],
    ["name": "上海", "value": 633.0],
    ["name": "重庆", "value": 67.0],
    ["name": "河北", "value": 680.0],
    ["name": "河南", "value": 250.0],
    ["name": "云南", "value": 462.0],
    ["name": "辽宁", "value": 505.0],
    ["name": "黑龙江", "value": 680.0],
    ["name": "湖南", "value": 664.0],
    ["name": "安徽", "value": 187.0],
    ["name": "山东", "value": 706.0],
    ["name": "新疆", "value": 530.0],
    ["name": "江苏", "value": 541.0],
    ["name": "浙江", "value": 920.0],
    ["name": "江西", "value": 350.0],
    ["name": "湖北", "value": 562.0],
    ["name": "广西", "value": 656.0],
    ["name": "甘肃", "value": 470.0],
    ["name": "山西", "value": 88.0],
    ["name": "内蒙古", "value": 346.0],
    ["name": "陕西", "value": 922.0],
    ["name": "吉林", "value": 754.0],
    ["name": "福建", "value": 919.0],
    ["name": "贵州", "value": 753.0],
    ["name": "广东", "value": 173.0],
    ["name": "青海", "value": 680.0],
    ["name": "西藏", "value": 930.0],
    ["name": "四川", "value": 488.0],
    ["name": "宁夏", "value": 501.0],
    ["name": "海南", "value": 330.0],
    ["name": "台湾", "value": 816.0],
    ["name": "香港", "value": 889.0],
    ["name": "澳门", "value": 602.0],
]

// The scatter's symbol: an aircraft outline as an SVG path (upstream `symbol: 'path://…'`).
private let geoMapScatterSymbol = "path://M1705.06,1318.313v-89.254l-319.9-221.799l0.073-208.063c0.521-84.662-26.629-121.796-63.961-121.491c-37.332-0.305-64.482,36.829-63.961,121.491l0.073,208.063l-319.9,221.799v89.254l330.343-157.288l12.238,241.308l-134.449,92.931l0.531,42.034l175.125-42.917l175.125,42.917l0.531-42.034l-134.449-92.931l12.238-241.308L1705.06,1318.313z"

extension EChartsDemoRegistry {
    static let official_geo_map_scatter = EChartsDemo(
        name: "official-geo-map-scatter", category: "map",
        summary: "map and scatter share a geo — map and scatter share a geo",
        width: 720, height: 460,
        nativeSupported: true,
        mapRegistrations: ["china": chinaGeoJSON],
        collection: .official,
        webOptionJS: #"""
var data = [
  { name: '海门', value: 9 },
  { name: '鄂尔多斯', value: 12 },
  { name: '招远', value: 12 },
  { name: '舟山', value: 12 },
  { name: '齐齐哈尔', value: 14 },
  { name: '盐城', value: 15 },
  { name: '赤峰', value: 16 },
  { name: '青岛', value: 18 },
  { name: '乳山', value: 18 },
  { name: '金昌', value: 19 },
  { name: '泉州', value: 21 },
  { name: '南通', value: 23 },
  { name: '拉萨', value: 24 },
  { name: '云浮', value: 24 },
  { name: '上海', value: 25 },
  { name: '攀枝花', value: 25 },
  { name: '承德', value: 25 },
  { name: '汕尾', value: 26 },
  { name: '丹东', value: 27 },
  { name: '瓦房店', value: 30 },
  { name: '延安', value: 38 },
  { name: '咸阳', value: 43 },
  { name: '南昌', value: 54 },
  { name: '柳州', value: 54 },
  { name: '三亚', value: 54 },
  { name: '泸州', value: 57 },
  { name: '克拉玛依', value: 72 }
];

var geoCoordMap = {
  海门: [121.15, 31.89],
  鄂尔多斯: [109.781327, 39.608266],
  招远: [120.38, 37.35],
  舟山: [122.207216, 29.985295],
  齐齐哈尔: [123.97, 47.33],
  盐城: [120.13, 33.38],
  赤峰: [118.87, 42.28],
  青岛: [120.33, 36.07],
  乳山: [121.52, 36.89],
  金昌: [102.188043, 38.520089],
  泉州: [118.58, 24.93],
  莱西: [120.53, 36.86],
  日照: [119.46, 35.42],
  胶南: [119.97, 35.88],
  南通: [121.05, 32.08],
  拉萨: [91.11, 29.97],
  云浮: [112.02, 22.93],
  梅州: [116.1, 24.55],
  文登: [122.05, 37.2],
  上海: [121.48, 31.22],
  攀枝花: [101.718637, 26.582347],
  威海: [122.1, 37.5],
  承德: [117.93, 40.97],
  厦门: [118.1, 24.46],
  汕尾: [115.375279, 22.786211],
  潮州: [116.63, 23.68],
  丹东: [124.37, 40.13],
  太仓: [121.1, 31.45],
  曲靖: [103.79, 25.51],
  烟台: [121.39, 37.52],
  福州: [119.3, 26.08],
  瓦房店: [121.979603, 39.627114],
  即墨: [120.45, 36.38],
  抚顺: [123.97, 41.97],
  玉溪: [102.52, 24.35],
  张家口: [114.87, 40.82],
  阳泉: [113.57, 37.85],
  莱州: [119.942327, 37.177017],
  湖州: [120.1, 30.86],
  汕头: [116.69, 23.39],
  昆山: [120.95, 31.39],
  宁波: [121.56, 29.86],
  湛江: [110.359377, 21.270708],
  揭阳: [116.35, 23.55],
  荣成: [122.41, 37.16],
  连云港: [119.16, 34.59],
  葫芦岛: [120.836932, 40.711052],
  常熟: [120.74, 31.64],
  东莞: [113.75, 23.04],
  河源: [114.68, 23.73],
  淮安: [119.15, 33.5],
  泰州: [119.9, 32.49],
  南宁: [108.33, 22.84],
  营口: [122.18, 40.65],
  惠州: [114.4, 23.09],
  江阴: [120.26, 31.91],
  蓬莱: [120.75, 37.8],
  韶关: [113.62, 24.84],
  嘉峪关: [98.289152, 39.77313],
  广州: [113.23, 23.16],
  延安: [109.47, 36.6],
  太原: [112.53, 37.87],
  清远: [113.01, 23.7],
  中山: [113.38, 22.52],
  昆明: [102.73, 25.04],
  寿光: [118.73, 36.86],
  盘锦: [122.070714, 41.119997],
  长治: [113.08, 36.18],
  深圳: [114.07, 22.62],
  珠海: [113.52, 22.3],
  宿迁: [118.3, 33.96],
  咸阳: [108.72, 34.36],
  铜川: [109.11, 35.09],
  平度: [119.97, 36.77],
  佛山: [113.11, 23.05],
  海口: [110.35, 20.02],
  江门: [113.06, 22.61],
  章丘: [117.53, 36.72],
  肇庆: [112.44, 23.05],
  大连: [121.62, 38.92],
  临汾: [111.5, 36.08],
  吴江: [120.63, 31.16],
  石嘴山: [106.39, 39.04],
  沈阳: [123.38, 41.8],
  苏州: [120.62, 31.32],
  茂名: [110.88, 21.68],
  嘉兴: [120.76, 30.77],
  长春: [125.35, 43.88],
  胶州: [120.03336, 36.264622],
  银川: [106.27, 38.47],
  张家港: [120.555821, 31.875428],
  三门峡: [111.19, 34.76],
  锦州: [121.15, 41.13],
  南昌: [115.89, 28.68],
  柳州: [109.4, 24.33],
  三亚: [109.511909, 18.252847],
  自贡: [104.778442, 29.33903],
  吉林: [126.57, 43.87],
  阳江: [111.95, 21.85],
  泸州: [105.39, 28.91],
  西宁: [101.74, 36.56],
  宜宾: [104.56, 29.77],
  呼和浩特: [111.65, 40.82],
  成都: [104.06, 30.67],
  大同: [113.3, 40.12],
  镇江: [119.44, 32.2],
  桂林: [110.28, 25.29],
  张家界: [110.479191, 29.117096],
  宜兴: [119.82, 31.36],
  北海: [109.12, 21.49],
  西安: [108.95, 34.27],
  金坛: [119.56, 31.74],
  东营: [118.49, 37.46],
  牡丹江: [129.58, 44.6],
  遵义: [106.9, 27.7],
  绍兴: [120.58, 30.01],
  扬州: [119.42, 32.39],
  常州: [119.95, 31.79],
  潍坊: [119.1, 36.62],
  重庆: [106.54, 29.59],
  台州: [121.420757, 28.656386],
  南京: [118.78, 32.04],
  滨州: [118.03, 37.36],
  贵阳: [106.71, 26.57],
  无锡: [120.29, 31.59],
  本溪: [123.73, 41.3],
  克拉玛依: [84.77, 45.59],
  渭南: [109.5, 34.52],
  马鞍山: [118.48, 31.56],
  宝鸡: [107.15, 34.38],
  焦作: [113.21, 35.24],
  句容: [119.16, 31.95],
  北京: [116.46, 39.92],
  徐州: [117.2, 34.26],
  衡水: [115.72, 37.72],
  包头: [110, 40.58],
  绵阳: [104.73, 31.48],
  乌鲁木齐: [87.68, 43.77],
  枣庄: [117.57, 34.86],
  杭州: [120.19, 30.26],
  淄博: [118.05, 36.78],
  鞍山: [122.85, 41.12],
  溧阳: [119.48, 31.43],
  库尔勒: [86.06, 41.68],
  安阳: [114.35, 36.1],
  开封: [114.35, 34.79],
  济南: [117, 36.65],
  德阳: [104.37, 31.13],
  温州: [120.65, 28.01],
  九江: [115.97, 29.71],
  邯郸: [114.47, 36.6],
  临安: [119.72, 30.23],
  兰州: [103.73, 36.03],
  沧州: [116.83, 38.33],
  临沂: [118.35, 35.05],
  南充: [106.110698, 30.837793],
  天津: [117.2, 39.13],
  富阳: [119.95, 30.07],
  泰安: [117.13, 36.18],
  诸暨: [120.23, 29.71],
  郑州: [113.65, 34.76],
  哈尔滨: [126.63, 45.75],
  聊城: [115.97, 36.45],
  芜湖: [118.38, 31.33],
  唐山: [118.02, 39.63],
  平顶山: [113.29, 33.75],
  邢台: [114.48, 37.05],
  德州: [116.29, 37.45],
  济宁: [116.59, 35.38],
  荆州: [112.239741, 30.335165],
  宜昌: [111.3, 30.7],
  义乌: [120.06, 29.32],
  丽水: [119.92, 28.45],
  洛阳: [112.44, 34.7],
  秦皇岛: [119.57, 39.95],
  株洲: [113.16, 27.83],
  石家庄: [114.48, 38.03],
  莱芜: [117.67, 36.19],
  常德: [111.69, 29.05],
  保定: [115.48, 38.85],
  湘潭: [112.91, 27.87],
  金华: [119.64, 29.12],
  岳阳: [113.09, 29.37],
  长沙: [113, 28.21],
  衢州: [118.88, 28.97],
  廊坊: [116.7, 39.53],
  菏泽: [115.480656, 35.23375],
  合肥: [117.27, 31.86],
  武汉: [114.31, 30.52],
  大庆: [125.03, 46.58]
};

function convertData(data) {
  var res = [];
  for (var i = 0; i < data.length; i++) {
    var geoCoord = geoCoordMap[data[i].name];
    if (geoCoord) {
      res.push({
        name: data[i].name,
        value: geoCoord.concat(data[i].value)
      });
    }
  }
  return res;
}

option = {
  tooltip: {},
  visualMap: {
    min: 0,
    max: 1500,
    left: 'left',
    top: 'bottom',
    text: ['High', 'Low'],
    seriesIndex: [1],
    inRange: {
      color: ['#e0ffff', '#006edd']
    },
    calculable: true
  },
  geo: {
    map: 'china',
    roam: true,
    label: {
      show: true,
      color: 'rgba(0,0,0,0.4)'
    },
    itemStyle: {
      borderColor: 'rgba(0, 0, 0, 0.2)'
    },
    emphasis: {
      itemStyle: {
        areaColor: null,
        shadowOffsetX: 0,
        shadowOffsetY: 0,
        shadowBlur: 20,
        borderWidth: 0,
        shadowColor: 'rgba(0, 0, 0, 0.5)'
      }
    }
  },
  series: [
    {
      type: 'scatter',
      coordinateSystem: 'geo',
      data: convertData(data),
      symbolSize: 20,
      symbol:
        'path://M1705.06,1318.313v-89.254l-319.9-221.799l0.073-208.063c0.521-84.662-26.629-121.796-63.961-121.491c-37.332-0.305-64.482,36.829-63.961,121.491l0.073,208.063l-319.9,221.799v89.254l330.343-157.288l12.238,241.308l-134.449,92.931l0.531,42.034l175.125-42.917l175.125,42.917l0.531-42.034l-134.449-92.931l12.238-241.308L1705.06,1318.313z',
      symbolRotate: 35,
      label: {
        formatter: '{b}',
        position: 'right',
        show: false
      },
      itemStyle: {
        color: '#F06C00'
      },
      emphasis: {
        label: {
          show: true
        }
      }
    },
    {
      name: 'categoryA',
      type: 'map',
      geoIndex: 0,
      data: [
        { name: '北京', value: 289 },
        { name: '天津', value: 897 },
        { name: '上海', value: 633 },
        { name: '重庆', value: 67 },
        { name: '河北', value: 680 },
        { name: '河南', value: 250 },
        { name: '云南', value: 462 },
        { name: '辽宁', value: 505 },
        { name: '黑龙江', value: 680 },
        { name: '湖南', value: 664 },
        { name: '安徽', value: 187 },
        { name: '山东', value: 706 },
        { name: '新疆', value: 530 },
        { name: '江苏', value: 541 },
        { name: '浙江', value: 920 },
        { name: '江西', value: 350 },
        { name: '湖北', value: 562 },
        { name: '广西', value: 656 },
        { name: '甘肃', value: 470 },
        { name: '山西', value: 88 },
        { name: '内蒙古', value: 346 },
        { name: '陕西', value: 922 },
        { name: '吉林', value: 754 },
        { name: '福建', value: 919 },
        { name: '贵州', value: 753 },
        { name: '广东', value: 173 },
        { name: '青海', value: 680 },
        { name: '西藏', value: 930 },
        { name: '四川', value: 488 },
        { name: '宁夏', value: 501 },
        { name: '海南', value: 330 },
        { name: '台湾', value: 816 },
        { name: '香港', value: 889 },
        { name: '澳门', value: 602 }
      ]
    }
  ]
};
"""#,
        option: {
            // The map the `geo` component names — upstream leaves this to the example editor (see header).
            ECharts.registerMap("china", chinaGeoJSON)
            return [
                "tooltip": [:] as [String: Any],
                "visualMap": [
                    "min": 0.0,
                    "max": 1500.0,
                    "left": "left",
                    "top": "bottom",
                    "text": ["High", "Low"],
                    // Scope the colour ramp to series 1 (the `map` choropleth); series 0's scatter glyphs
                    // keep their flat #F06C00.
                    "seriesIndex": [1.0],
                    "inRange": [
                        "color": ["#e0ffff", "#006edd"]
                    ] as [String: Any],
                    "calculable": true
                ] as [String: Any],
                "geo": [
                    "map": "china",
                    "roam": true,
                    "label": [
                        "show": true,
                        "color": "rgba(0,0,0,0.4)"
                    ] as [String: Any],
                    "itemStyle": [
                        "borderColor": "rgba(0, 0, 0, 0.2)"
                    ] as [String: Any],
                    "emphasis": [
                        "itemStyle": [
                            // NSNull is the JS `null`: explicitly NO emphasis fill, so a hovered province
                            // keeps the areaColor the visualMap gave it and only gains the shadow.
                            "areaColor": NSNull(),
                            "shadowOffsetX": 0.0,
                            "shadowOffsetY": 0.0,
                            "shadowBlur": 20.0,
                            "borderWidth": 0.0,
                            "shadowColor": "rgba(0, 0, 0, 0.5)"
                        ] as [String: Any]
                    ] as [String: Any]
                ] as [String: Any],
                "series": [
                    [
                        "type": "scatter",
                        "coordinateSystem": "geo",
                        "data": geoMapScatterData as [Any],
                        "symbolSize": 20.0,
                        "symbol": geoMapScatterSymbol,
                        "symbolRotate": 35.0,
                        "label": [
                            // '{b}' is a template STRING (the datum's name), not a closure — it ports as-is.
                            "formatter": "{b}",
                            "position": "right",
                            "show": false
                        ] as [String: Any],
                        "itemStyle": [
                            "color": "#F06C00"
                        ] as [String: Any],
                        "emphasis": [
                            "label": [
                                "show": true
                            ] as [String: Any]
                        ] as [String: Any]
                    ] as [String: Any],
                    [
                        "name": "categoryA",
                        "type": "map",
                        // Bind to the geo declared above instead of owning a map — the point of the example.
                        "geoIndex": 0.0,
                        "data": geoMapScatterProvinceData as [Any]
                    ] as [String: Any]
                ]
            ]
        }())
}
