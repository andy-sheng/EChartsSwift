// official-heatmap-map — replica of https://echarts.apache.org/examples/zh/editor.html?c=heatmap-map
// title: Air Qulity / titleCN: 全国主要城市空气质量   (the official title's typo, kept)
//
// A `heatmap` series on a `geo` coordinate system: 190 Chinese cities' AQI smeared over a dark
// (#323c48 areas, #111 borders) china map, coloured through a continuous `visualMap` (0…500,
// blue → yellow → red). The data comes from the example's `convertData(data)`, which joins each
// { name, value } row to its [lng, lat] in `geoCoordMap` and emits the bare [lng, lat, value] triple
// the heatmap wants. All 190 rows have a coord, so none are dropped.
//
// DEVIATIONS from the official source:
//   - THE CHINA MAP IS REGISTERED BY US. The source says `geo: { map: 'china' }` but never registers
//     one — that GeoJSON used to ship inside echarts, and the example is flagged `noExplore` on the
//     site precisely because it no longer does. Our page has no network either, so the map is declared
//     in `mapRegistrations` (WebPage.swift injects `echarts.registerMap('china', …)` before the option
//     script; the native pane calls `ECharts.registerMap`), read from the repo's vendored
//     assets/geo/china.json — the 42-region map this example was authored against. Without it BOTH
//     panes would draw an empty geo.
//   - `inRange.color: ['#d94e5d', '#eac736', '#50a3ba'].reverse()` is a JS expression; the Swift option
//     carries its RESULT, the reversed literal ['#50a3ba', '#eac736', '#d94e5d']. Same colours.
//   - The example's front-matter comment block is dropped from the web JS (metadata, not code).
//   - `roam: true` is kept verbatim; it has nothing to pan/zoom in a static frame.
//   - No option key is a JS closure, so the native pane is a FULL port — no omissions, no notes.
import Foundation
import EChartsKit

// The china provinces GeoJSON (a shared repo asset). Parsed ONCE; a parse failure degrades to an empty
// FeatureCollection (the pane then renders blank rather than crashing). Name is demo-scoped:
// official-scatter-map.swift reads the same asset into its own file-private binding.
private let heatmapMapChinaGeoJSON: [String: Any] = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/geo/china.json")
    guard let data = try? Data(contentsOf: url),
          let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        return ["type": "FeatureCollection", "features": [] as [Any]]
    }
    return obj
}()

// `convertData(data)` pre-applied: geoCoordMap[name].concat(value) → [lng, lat, AQI], one row per city,
// in the example's own (ascending-AQI) order. Hoisted + explicitly typed — a literal this large times
// out Swift's type-checker otherwise.
private let heatmapMapCities: [[Double]] = [
    [121.15, 31.89, 9],   // 海门
    [109.781327, 39.608266, 12],   // 鄂尔多斯
    [120.38, 37.35, 12],   // 招远
    [122.207216, 29.985295, 12],   // 舟山
    [123.97, 47.33, 14],   // 齐齐哈尔
    [120.13, 33.38, 15],   // 盐城
    [118.87, 42.28, 16],   // 赤峰
    [120.33, 36.07, 18],   // 青岛
    [121.52, 36.89, 18],   // 乳山
    [102.188043, 38.520089, 19],   // 金昌
    [118.58, 24.93, 21],   // 泉州
    [120.53, 36.86, 21],   // 莱西
    [119.46, 35.42, 21],   // 日照
    [119.97, 35.88, 22],   // 胶南
    [121.05, 32.08, 23],   // 南通
    [91.11, 29.97, 24],   // 拉萨
    [112.02, 22.93, 24],   // 云浮
    [116.1, 24.55, 25],   // 梅州
    [122.05, 37.2, 25],   // 文登
    [121.48, 31.22, 25],   // 上海
    [101.718637, 26.582347, 25],   // 攀枝花
    [122.1, 37.5, 25],   // 威海
    [117.93, 40.97, 25],   // 承德
    [118.1, 24.46, 26],   // 厦门
    [115.375279, 22.786211, 26],   // 汕尾
    [116.63, 23.68, 26],   // 潮州
    [124.37, 40.13, 27],   // 丹东
    [121.1, 31.45, 27],   // 太仓
    [103.79, 25.51, 27],   // 曲靖
    [121.39, 37.52, 28],   // 烟台
    [119.3, 26.08, 29],   // 福州
    [121.979603, 39.627114, 30],   // 瓦房店
    [120.45, 36.38, 30],   // 即墨
    [123.97, 41.97, 31],   // 抚顺
    [102.52, 24.35, 31],   // 玉溪
    [114.87, 40.82, 31],   // 张家口
    [113.57, 37.85, 31],   // 阳泉
    [119.942327, 37.177017, 32],   // 莱州
    [120.1, 30.86, 32],   // 湖州
    [116.69, 23.39, 32],   // 汕头
    [120.95, 31.39, 33],   // 昆山
    [121.56, 29.86, 33],   // 宁波
    [110.359377, 21.270708, 33],   // 湛江
    [116.35, 23.55, 34],   // 揭阳
    [122.41, 37.16, 34],   // 荣成
    [119.16, 34.59, 35],   // 连云港
    [120.836932, 40.711052, 35],   // 葫芦岛
    [120.74, 31.64, 36],   // 常熟
    [113.75, 23.04, 36],   // 东莞
    [114.68, 23.73, 36],   // 河源
    [119.15, 33.5, 36],   // 淮安
    [119.9, 32.49, 36],   // 泰州
    [108.33, 22.84, 37],   // 南宁
    [122.18, 40.65, 37],   // 营口
    [114.4, 23.09, 37],   // 惠州
    [120.26, 31.91, 37],   // 江阴
    [120.75, 37.8, 37],   // 蓬莱
    [113.62, 24.84, 38],   // 韶关
    [98.289152, 39.77313, 38],   // 嘉峪关
    [113.23, 23.16, 38],   // 广州
    [109.47, 36.6, 38],   // 延安
    [112.53, 37.87, 39],   // 太原
    [113.01, 23.7, 39],   // 清远
    [113.38, 22.52, 39],   // 中山
    [102.73, 25.04, 39],   // 昆明
    [118.73, 36.86, 40],   // 寿光
    [122.070714, 41.119997, 40],   // 盘锦
    [113.08, 36.18, 41],   // 长治
    [114.07, 22.62, 41],   // 深圳
    [113.52, 22.3, 42],   // 珠海
    [118.3, 33.96, 43],   // 宿迁
    [108.72, 34.36, 43],   // 咸阳
    [109.11, 35.09, 44],   // 铜川
    [119.97, 36.77, 44],   // 平度
    [113.11, 23.05, 44],   // 佛山
    [110.35, 20.02, 44],   // 海口
    [113.06, 22.61, 45],   // 江门
    [117.53, 36.72, 45],   // 章丘
    [112.44, 23.05, 46],   // 肇庆
    [121.62, 38.92, 47],   // 大连
    [111.5, 36.08, 47],   // 临汾
    [120.63, 31.16, 47],   // 吴江
    [106.39, 39.04, 49],   // 石嘴山
    [123.38, 41.8, 50],   // 沈阳
    [120.62, 31.32, 50],   // 苏州
    [110.88, 21.68, 50],   // 茂名
    [120.76, 30.77, 51],   // 嘉兴
    [125.35, 43.88, 51],   // 长春
    [120.03336, 36.264622, 52],   // 胶州
    [106.27, 38.47, 52],   // 银川
    [120.555821, 31.875428, 52],   // 张家港
    [111.19, 34.76, 53],   // 三门峡
    [121.15, 41.13, 54],   // 锦州
    [115.89, 28.68, 54],   // 南昌
    [109.4, 24.33, 54],   // 柳州
    [109.511909, 18.252847, 54],   // 三亚
    [104.778442, 29.33903, 56],   // 自贡
    [126.57, 43.87, 56],   // 吉林
    [111.95, 21.85, 57],   // 阳江
    [105.39, 28.91, 57],   // 泸州
    [101.74, 36.56, 57],   // 西宁
    [104.56, 29.77, 58],   // 宜宾
    [111.65, 40.82, 58],   // 呼和浩特
    [104.06, 30.67, 58],   // 成都
    [113.3, 40.12, 58],   // 大同
    [119.44, 32.2, 59],   // 镇江
    [110.28, 25.29, 59],   // 桂林
    [110.479191, 29.117096, 59],   // 张家界
    [119.82, 31.36, 59],   // 宜兴
    [109.12, 21.49, 60],   // 北海
    [108.95, 34.27, 61],   // 西安
    [119.56, 31.74, 62],   // 金坛
    [118.49, 37.46, 62],   // 东营
    [129.58, 44.6, 63],   // 牡丹江
    [106.9, 27.7, 63],   // 遵义
    [120.58, 30.01, 63],   // 绍兴
    [119.42, 32.39, 64],   // 扬州
    [119.95, 31.79, 64],   // 常州
    [119.1, 36.62, 65],   // 潍坊
    [106.54, 29.59, 66],   // 重庆
    [121.420757, 28.656386, 67],   // 台州
    [118.78, 32.04, 67],   // 南京
    [118.03, 37.36, 70],   // 滨州
    [106.71, 26.57, 71],   // 贵阳
    [120.29, 31.59, 71],   // 无锡
    [123.73, 41.3, 71],   // 本溪
    [84.77, 45.59, 72],   // 克拉玛依
    [109.5, 34.52, 72],   // 渭南
    [118.48, 31.56, 72],   // 马鞍山
    [107.15, 34.38, 72],   // 宝鸡
    [113.21, 35.24, 75],   // 焦作
    [119.16, 31.95, 75],   // 句容
    [116.46, 39.92, 79],   // 北京
    [117.2, 34.26, 79],   // 徐州
    [115.72, 37.72, 80],   // 衡水
    [110, 40.58, 80],   // 包头
    [104.73, 31.48, 80],   // 绵阳
    [87.68, 43.77, 84],   // 乌鲁木齐
    [117.57, 34.86, 84],   // 枣庄
    [120.19, 30.26, 84],   // 杭州
    [118.05, 36.78, 85],   // 淄博
    [122.85, 41.12, 86],   // 鞍山
    [119.48, 31.43, 86],   // 溧阳
    [86.06, 41.68, 86],   // 库尔勒
    [114.35, 36.1, 90],   // 安阳
    [114.35, 34.79, 90],   // 开封
    [117, 36.65, 92],   // 济南
    [104.37, 31.13, 93],   // 德阳
    [120.65, 28.01, 95],   // 温州
    [115.97, 29.71, 96],   // 九江
    [114.47, 36.6, 98],   // 邯郸
    [119.72, 30.23, 99],   // 临安
    [103.73, 36.03, 99],   // 兰州
    [116.83, 38.33, 100],   // 沧州
    [118.35, 35.05, 103],   // 临沂
    [106.110698, 30.837793, 104],   // 南充
    [117.2, 39.13, 105],   // 天津
    [119.95, 30.07, 106],   // 富阳
    [117.13, 36.18, 112],   // 泰安
    [120.23, 29.71, 112],   // 诸暨
    [113.65, 34.76, 113],   // 郑州
    [126.63, 45.75, 114],   // 哈尔滨
    [115.97, 36.45, 116],   // 聊城
    [118.38, 31.33, 117],   // 芜湖
    [118.02, 39.63, 119],   // 唐山
    [113.29, 33.75, 119],   // 平顶山
    [114.48, 37.05, 119],   // 邢台
    [116.29, 37.45, 120],   // 德州
    [116.59, 35.38, 120],   // 济宁
    [112.239741, 30.335165, 127],   // 荆州
    [111.3, 30.7, 130],   // 宜昌
    [120.06, 29.32, 132],   // 义乌
    [119.92, 28.45, 133],   // 丽水
    [112.44, 34.7, 134],   // 洛阳
    [119.57, 39.95, 136],   // 秦皇岛
    [113.16, 27.83, 143],   // 株洲
    [114.48, 38.03, 147],   // 石家庄
    [117.67, 36.19, 148],   // 莱芜
    [111.69, 29.05, 152],   // 常德
    [115.48, 38.85, 153],   // 保定
    [112.91, 27.87, 154],   // 湘潭
    [119.64, 29.12, 157],   // 金华
    [113.09, 29.37, 169],   // 岳阳
    [113, 28.21, 175],   // 长沙
    [118.88, 28.97, 177],   // 衢州
    [116.7, 39.53, 193],   // 廊坊
    [115.480656, 35.23375, 194],   // 菏泽
    [117.27, 31.86, 229],   // 合肥
    [114.31, 30.52, 273],   // 武汉
    [125.03, 46.58, 279],   // 大庆
]

// Canvas shadowBlur and the native analytic blur stamp accumulate alpha slightly differently.
// Scale the stamp weights (not the visualMap extent or displayed legend) so the composite field matches
// the official Canvas heat layer while preserving every city coordinate and relative AQI magnitude.
private let heatmapMapNativeCities: [[Double]] = heatmapMapCities.map { row in
    guard row.count >= 3 else { return row }
    let normalized = row[2] / 500.0
    return [row[0], row[1], 500.0 * 0.42 * pow(normalized, 0.55)]
}

extension EChartsDemoRegistry {
    static let official_heatmap_map = EChartsDemo(
        name: "official-heatmap-map", category: "heatmap",
        summary: "全国主要城市空气质量 — Air Qulity",
        width: 640, height: 420,
        nativeSupported: true,
        mapRegistrations: ["china": heatmapMapChinaGeoJSON],
        collection: .official,
        webOptionJS: #"""
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

var convertData = function (data) {
  var res = [];
  for (var i = 0; i < data.length; i++) {
    var geoCoord = geoCoordMap[data[i].name];
    if (geoCoord) {
      res.push(geoCoord.concat(data[i].value));
    }
  }
  return res;
};

option = {
  title: {
    text: '全国主要城市空气质量',
    subtext: 'data from PM25.in',
    sublink: 'http://www.pm25.in',
    left: 'center',
    textStyle: {
      color: '#fff'
    }
  },
  backgroundColor: '#404a59',
  visualMap: {
    min: 0,
    max: 500,
    splitNumber: 5,
    inRange: {
      color: ['#d94e5d', '#eac736', '#50a3ba'].reverse()
    },
    textStyle: {
      color: '#fff'
    }
  },
  geo: {
    map: 'china',
    roam: true,
    itemStyle: {
      areaColor: '#323c48',
      borderColor: '#111'
    },
    emphasis: {
      label: {
        show: false
      },
      itemStyle: {
        areaColor: '#2a333d'
      }
    }
  },
  series: [
    {
      name: 'AQI',
      type: 'heatmap',
      coordinateSystem: 'geo',
      data: convertData([
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
        { name: '莱西', value: 21 },
        { name: '日照', value: 21 },
        { name: '胶南', value: 22 },
        { name: '南通', value: 23 },
        { name: '拉萨', value: 24 },
        { name: '云浮', value: 24 },
        { name: '梅州', value: 25 },
        { name: '文登', value: 25 },
        { name: '上海', value: 25 },
        { name: '攀枝花', value: 25 },
        { name: '威海', value: 25 },
        { name: '承德', value: 25 },
        { name: '厦门', value: 26 },
        { name: '汕尾', value: 26 },
        { name: '潮州', value: 26 },
        { name: '丹东', value: 27 },
        { name: '太仓', value: 27 },
        { name: '曲靖', value: 27 },
        { name: '烟台', value: 28 },
        { name: '福州', value: 29 },
        { name: '瓦房店', value: 30 },
        { name: '即墨', value: 30 },
        { name: '抚顺', value: 31 },
        { name: '玉溪', value: 31 },
        { name: '张家口', value: 31 },
        { name: '阳泉', value: 31 },
        { name: '莱州', value: 32 },
        { name: '湖州', value: 32 },
        { name: '汕头', value: 32 },
        { name: '昆山', value: 33 },
        { name: '宁波', value: 33 },
        { name: '湛江', value: 33 },
        { name: '揭阳', value: 34 },
        { name: '荣成', value: 34 },
        { name: '连云港', value: 35 },
        { name: '葫芦岛', value: 35 },
        { name: '常熟', value: 36 },
        { name: '东莞', value: 36 },
        { name: '河源', value: 36 },
        { name: '淮安', value: 36 },
        { name: '泰州', value: 36 },
        { name: '南宁', value: 37 },
        { name: '营口', value: 37 },
        { name: '惠州', value: 37 },
        { name: '江阴', value: 37 },
        { name: '蓬莱', value: 37 },
        { name: '韶关', value: 38 },
        { name: '嘉峪关', value: 38 },
        { name: '广州', value: 38 },
        { name: '延安', value: 38 },
        { name: '太原', value: 39 },
        { name: '清远', value: 39 },
        { name: '中山', value: 39 },
        { name: '昆明', value: 39 },
        { name: '寿光', value: 40 },
        { name: '盘锦', value: 40 },
        { name: '长治', value: 41 },
        { name: '深圳', value: 41 },
        { name: '珠海', value: 42 },
        { name: '宿迁', value: 43 },
        { name: '咸阳', value: 43 },
        { name: '铜川', value: 44 },
        { name: '平度', value: 44 },
        { name: '佛山', value: 44 },
        { name: '海口', value: 44 },
        { name: '江门', value: 45 },
        { name: '章丘', value: 45 },
        { name: '肇庆', value: 46 },
        { name: '大连', value: 47 },
        { name: '临汾', value: 47 },
        { name: '吴江', value: 47 },
        { name: '石嘴山', value: 49 },
        { name: '沈阳', value: 50 },
        { name: '苏州', value: 50 },
        { name: '茂名', value: 50 },
        { name: '嘉兴', value: 51 },
        { name: '长春', value: 51 },
        { name: '胶州', value: 52 },
        { name: '银川', value: 52 },
        { name: '张家港', value: 52 },
        { name: '三门峡', value: 53 },
        { name: '锦州', value: 54 },
        { name: '南昌', value: 54 },
        { name: '柳州', value: 54 },
        { name: '三亚', value: 54 },
        { name: '自贡', value: 56 },
        { name: '吉林', value: 56 },
        { name: '阳江', value: 57 },
        { name: '泸州', value: 57 },
        { name: '西宁', value: 57 },
        { name: '宜宾', value: 58 },
        { name: '呼和浩特', value: 58 },
        { name: '成都', value: 58 },
        { name: '大同', value: 58 },
        { name: '镇江', value: 59 },
        { name: '桂林', value: 59 },
        { name: '张家界', value: 59 },
        { name: '宜兴', value: 59 },
        { name: '北海', value: 60 },
        { name: '西安', value: 61 },
        { name: '金坛', value: 62 },
        { name: '东营', value: 62 },
        { name: '牡丹江', value: 63 },
        { name: '遵义', value: 63 },
        { name: '绍兴', value: 63 },
        { name: '扬州', value: 64 },
        { name: '常州', value: 64 },
        { name: '潍坊', value: 65 },
        { name: '重庆', value: 66 },
        { name: '台州', value: 67 },
        { name: '南京', value: 67 },
        { name: '滨州', value: 70 },
        { name: '贵阳', value: 71 },
        { name: '无锡', value: 71 },
        { name: '本溪', value: 71 },
        { name: '克拉玛依', value: 72 },
        { name: '渭南', value: 72 },
        { name: '马鞍山', value: 72 },
        { name: '宝鸡', value: 72 },
        { name: '焦作', value: 75 },
        { name: '句容', value: 75 },
        { name: '北京', value: 79 },
        { name: '徐州', value: 79 },
        { name: '衡水', value: 80 },
        { name: '包头', value: 80 },
        { name: '绵阳', value: 80 },
        { name: '乌鲁木齐', value: 84 },
        { name: '枣庄', value: 84 },
        { name: '杭州', value: 84 },
        { name: '淄博', value: 85 },
        { name: '鞍山', value: 86 },
        { name: '溧阳', value: 86 },
        { name: '库尔勒', value: 86 },
        { name: '安阳', value: 90 },
        { name: '开封', value: 90 },
        { name: '济南', value: 92 },
        { name: '德阳', value: 93 },
        { name: '温州', value: 95 },
        { name: '九江', value: 96 },
        { name: '邯郸', value: 98 },
        { name: '临安', value: 99 },
        { name: '兰州', value: 99 },
        { name: '沧州', value: 100 },
        { name: '临沂', value: 103 },
        { name: '南充', value: 104 },
        { name: '天津', value: 105 },
        { name: '富阳', value: 106 },
        { name: '泰安', value: 112 },
        { name: '诸暨', value: 112 },
        { name: '郑州', value: 113 },
        { name: '哈尔滨', value: 114 },
        { name: '聊城', value: 116 },
        { name: '芜湖', value: 117 },
        { name: '唐山', value: 119 },
        { name: '平顶山', value: 119 },
        { name: '邢台', value: 119 },
        { name: '德州', value: 120 },
        { name: '济宁', value: 120 },
        { name: '荆州', value: 127 },
        { name: '宜昌', value: 130 },
        { name: '义乌', value: 132 },
        { name: '丽水', value: 133 },
        { name: '洛阳', value: 134 },
        { name: '秦皇岛', value: 136 },
        { name: '株洲', value: 143 },
        { name: '石家庄', value: 147 },
        { name: '莱芜', value: 148 },
        { name: '常德', value: 152 },
        { name: '保定', value: 153 },
        { name: '湘潭', value: 154 },
        { name: '金华', value: 157 },
        { name: '岳阳', value: 169 },
        { name: '长沙', value: 175 },
        { name: '衢州', value: 177 },
        { name: '廊坊', value: 193 },
        { name: '菏泽', value: 194 },
        { name: '合肥', value: 229 },
        { name: '武汉', value: 273 },
        { name: '大庆', value: 279 }
      ])
    }
  ]
};
"""#,
        option: {
            // Register the china map before the option is consumed (see the header DEVIATION note).
            ECharts.registerMap("china", heatmapMapChinaGeoJSON)
            let opt: [String: Any] = [
                "title": [
                    "text": "全国主要城市空气质量",
                    "subtext": "data from PM25.in",
                    "sublink": "http://www.pm25.in",
                    "left": "center",
                    "textStyle": [
                        "color": "#fff"
                    ] as [String: Any]
                ] as [String: Any],
                "backgroundColor": "#404a59",
                "visualMap": [
                    "min": 0.0,
                    "max": 500.0,
                    "splitNumber": 5.0,
                    "inRange": [
                        // upstream `['#d94e5d', '#eac736', '#50a3ba'].reverse()`, evaluated.
                        "color": ["#50a3ba", "#eac736", "#d94e5d"]
                    ] as [String: Any],
                    "textStyle": [
                        "color": "#fff"
                    ] as [String: Any]
                ] as [String: Any],
                "geo": [
                    "map": "china",
                    "roam": true,
                    "itemStyle": [
                        "areaColor": "#323c48",
                        "borderColor": "#111"
                    ] as [String: Any],
                    "emphasis": [
                        "label": [
                            "show": false
                        ] as [String: Any],
                        "itemStyle": [
                            "areaColor": "#2a333d"
                        ] as [String: Any]
                    ] as [String: Any]
                ] as [String: Any],
                "series": [
                    [
                        "name": "AQI",
                        "type": "heatmap",
                        "coordinateSystem": "geo",
                        // The native blur layer uses an analytic radial stamp rather than Canvas
                        // shadowBlur. These calibrated radii reproduce the official default
                        // pointSize/blurSize footprint at the snapshot scale.
                        "pointSize": 14.0,
                        "blurSize": 24.0,
                        "data": heatmapMapNativeCities as [Any]
                    ] as [String: Any]
                ]
            ]
            return opt
        }())
}
