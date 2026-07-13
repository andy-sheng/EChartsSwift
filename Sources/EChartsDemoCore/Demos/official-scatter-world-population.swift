// official-scatter-world-population — replica of https://echarts.apache.org/examples/zh/editor.html?c=scatter-world-population
// title: World Population (2011) / titleCN: World Population (2011)
// A bubble scatter on a `geo` world map: one symbol per country, placed at that country's (longitude,
// latitude) from the example's own `latlong` table, sized by its 2011 population (Gapminder) through a
// hidden continuous visualMap mapping value → symbolSize [6, 60], and coloured per-datum by continent.
//
// DEVIATIONS from the official source:
//  - MAP REGISTRATION: the example itself registers nothing — the official editor auto-injects the map
//    named by `geo.map: 'world'`. We must be explicit, so the world GeoJSON is a repo asset:
//    assets/geo/world.json (217 features, mirrored from echarts-examples' public/data/asset/geo/world.json),
//    read at demo time via Upstream.repoRoot and handed to BOTH panes via `mapRegistrations` — WebPage.swift
//    injects `echarts.registerMap('world', ...)` ahead of the option script, and the native pane registers
//    the same GeoJSON. A parse failure degrades to an empty FeatureCollection (blank map, no crash).
//  - NATIVE `series[0].data`: the JS builds it with `mapData.map(...)`, joining the 169 `mapData` rows
//    against the `latlong` table. Swift cannot carry that closure, so the join is PRE-COMPUTED below —
//    `worldPopulationRows` holds the same 169 rows in the same order, already carrying each country's
//    lon/lat, and `worldPopulationPoints` assembles the identical data items. The web pane still runs
//    the real `.map()` over the verbatim `latlong` + `mapData`.
//  - `visualMap.max`: the JS scans mapData for `max`; the Swift option inlines the result (1347565324 — China).
//  - `tooltip.formatter` omitted from the native option (a JS closure) — see PORT-NOTE.
// Everything else (backgroundColor, title, geo styling incl. roam + emphasis, per-datum emphasis label
// and itemStyle) is carried verbatim by both panes.
import Foundation
import EChartsKit

// The world map GeoJSON, parsed ONCE from the repo asset.
private let worldGeoJSON: [String: Any] = {
    let url = Upstream.repoRoot.appendingPathComponent("assets/geo/world.json")
    guard let data = try? Data(contentsOf: url),
          let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
        return ["type": "FeatureCollection", "features": [] as [Any]]
    }
    return obj
}()

// The upstream `mapData` rows, each already joined to its `latlong` entry:
// (country name, longitude, latitude, 2011 population, continent colour).
private let worldPopulationRows: [(name: String, lon: Double, lat: Double, value: Double, color: String)] = [
    ("Afghanistan", 65, 33, 32358260, "#eea638"),
    ("Albania", 20, 41, 3215988, "#d8854f"),
    ("Algeria", 3, 28, 35980193, "#de4c4f"),
    ("Angola", 18.5, -12.5, 19618432, "#de4c4f"),
    ("Argentina", -64, -34, 40764561, "#86a965"),
    ("Armenia", 45, 40, 3100236, "#d8854f"),
    ("Australia", 133, -27, 22605732, "#8aabb0"),
    ("Austria", 13.3333, 47.3333, 8413429, "#d8854f"),
    ("Azerbaijan", 47.5, 40.5, 9306023, "#d8854f"),
    ("Bahrain", 50.55, 26, 1323535, "#eea638"),
    ("Bangladesh", 90, 24, 150493658, "#eea638"),
    ("Belarus", 28, 53, 9559441, "#d8854f"),
    ("Belgium", 4, 50.8333, 10754056, "#d8854f"),
    ("Benin", 2.25, 9.5, 9099922, "#de4c4f"),
    ("Bhutan", 90.5, 27.5, 738267, "#eea638"),
    ("Bolivia", -65, -17, 10088108, "#86a965"),
    ("Bosnia and Herzegovina", 18, 44, 3752228, "#d8854f"),
    ("Botswana", 24, -22, 2030738, "#de4c4f"),
    ("Brazil", -55, -10, 196655014, "#86a965"),
    ("Brunei", 114.6667, 4.5, 405938, "#eea638"),
    ("Bulgaria", 25, 43, 7446135, "#d8854f"),
    ("Burkina Faso", -2, 13, 16967845, "#de4c4f"),
    ("Burundi", 30, -3.5, 8575172, "#de4c4f"),
    ("Cambodia", 105, 13, 14305183, "#eea638"),
    ("Cameroon", 12, 6, 20030362, "#de4c4f"),
    ("Canada", -100, 54, 34349561, "#a7a737"),
    ("Cape Verde", -24, 16, 500585, "#de4c4f"),
    ("Central African Rep.", 21, 7, 4486837, "#de4c4f"),
    ("Chad", 19, 15, 11525496, "#de4c4f"),
    ("Chile", -71, -30, 17269525, "#86a965"),
    ("China", 105, 35, 1347565324, "#eea638"),
    ("Colombia", -72, 4, 46927125, "#86a965"),
    ("Comoros", 44.25, -12.1667, 753943, "#de4c4f"),
    ("Congo, Dem. Rep.", 25, 0, 67757577, "#de4c4f"),
    ("Congo, Rep.", 15, -1, 4139748, "#de4c4f"),
    ("Costa Rica", -84, 10, 4726575, "#a7a737"),
    ("Cote d'Ivoire", -5, 8, 20152894, "#de4c4f"),
    ("Croatia", 15.5, 45.1667, 4395560, "#d8854f"),
    ("Cuba", -80, 21.5, 11253665, "#a7a737"),
    ("Cyprus", 33, 35, 1116564, "#d8854f"),
    ("Czech Rep.", 15.5, 49.75, 10534293, "#d8854f"),
    ("Denmark", 10, 56, 5572594, "#d8854f"),
    ("Djibouti", 43, 11.5, 905564, "#de4c4f"),
    ("Dominican Rep.", -70.6667, 19, 10056181, "#a7a737"),
    ("Ecuador", -77.5, -2, 14666055, "#86a965"),
    ("Egypt", 30, 27, 82536770, "#de4c4f"),
    ("El Salvador", -88.9167, 13.8333, 6227491, "#a7a737"),
    ("Equatorial Guinea", 10, 2, 720213, "#de4c4f"),
    ("Eritrea", 39, 15, 5415280, "#de4c4f"),
    ("Estonia", 26, 59, 1340537, "#d8854f"),
    ("Ethiopia", 38, 8, 84734262, "#de4c4f"),
    ("Fiji", 175, -18, 868406, "#8aabb0"),
    ("Finland", 26, 62, 5384770, "#d8854f"),
    ("France", 2, 46, 63125894, "#d8854f"),
    ("Gabon", 11.75, -1, 1534262, "#de4c4f"),
    ("Gambia", -16.5667, 13.4667, 1776103, "#de4c4f"),
    ("Georgia", 43.5, 42, 4329026, "#d8854f"),
    ("Germany", 9, 51, 82162512, "#d8854f"),
    ("Ghana", -2, 8, 24965816, "#de4c4f"),
    ("Greece", 22, 39, 11390031, "#d8854f"),
    ("Guatemala", -90.25, 15.5, 14757316, "#a7a737"),
    ("Guinea", -10, 11, 10221808, "#de4c4f"),
    ("Guinea-Bissau", -15, 12, 1547061, "#de4c4f"),
    ("Guyana", -59, 5, 756040, "#86a965"),
    ("Haiti", -72.4167, 19, 10123787, "#a7a737"),
    ("Honduras", -86.5, 15, 7754687, "#a7a737"),
    ("Hong Kong, China", 114.1667, 22.25, 7122187, "#eea638"),
    ("Hungary", 20, 47, 9966116, "#d8854f"),
    ("Iceland", -18, 65, 324366, "#d8854f"),
    ("India", 77, 20, 1241491960, "#eea638"),
    ("Indonesia", 120, -5, 242325638, "#eea638"),
    ("Iran", 53, 32, 74798599, "#eea638"),
    ("Iraq", 44, 33, 32664942, "#eea638"),
    ("Ireland", -8, 53, 4525802, "#d8854f"),
    ("Israel", 34.75, 31.5, 7562194, "#eea638"),
    ("Italy", 12.8333, 42.8333, 60788694, "#d8854f"),
    ("Jamaica", -77.5, 18.25, 2751273, "#a7a737"),
    ("Japan", 138, 36, 126497241, "#eea638"),
    ("Jordan", 36, 31, 6330169, "#eea638"),
    ("Kazakhstan", 68, 48, 16206750, "#eea638"),
    ("Kenya", 38, 1, 41609728, "#de4c4f"),
    ("Korea, Dem. Rep.", 127, 40, 24451285, "#eea638"),
    ("Korea, Rep.", 127.5, 37, 48391343, "#eea638"),
    ("Kuwait", 47.6581, 29.3375, 2818042, "#eea638"),
    ("Kyrgyzstan", 75, 41, 5392580, "#eea638"),
    ("Laos", 105, 18, 6288037, "#eea638"),
    ("Latvia", 25, 57, 2243142, "#d8854f"),
    ("Lebanon", 35.8333, 33.8333, 4259405, "#eea638"),
    ("Lesotho", 28.5, -29.5, 2193843, "#de4c4f"),
    ("Liberia", -9.5, 6.5, 4128572, "#de4c4f"),
    ("Libya", 17, 25, 6422772, "#de4c4f"),
    ("Lithuania", 24, 55, 3307481, "#d8854f"),
    ("Luxembourg", 6, 49.75, 515941, "#d8854f"),
    ("Macedonia, FYR", 22, 41.8333, 2063893, "#d8854f"),
    ("Madagascar", 47, -20, 21315135, "#de4c4f"),
    ("Malawi", 34, -13.5, 15380888, "#de4c4f"),
    ("Malaysia", 112.5, 2.5, 28859154, "#eea638"),
    ("Mali", -4, 17, 15839538, "#de4c4f"),
    ("Mauritania", -12, 20, 3541540, "#de4c4f"),
    ("Mauritius", 57.55, -20.2833, 1306593, "#de4c4f"),
    ("Mexico", -102, 23, 114793341, "#a7a737"),
    ("Moldova", 29, 47, 3544864, "#d8854f"),
    ("Mongolia", 105, 46, 2800114, "#eea638"),
    ("Montenegro", 19.4, 42.5, 632261, "#d8854f"),
    ("Morocco", -5, 32, 32272974, "#de4c4f"),
    ("Mozambique", 35, -18.25, 23929708, "#de4c4f"),
    ("Myanmar", 98, 22, 48336763, "#eea638"),
    ("Namibia", 17, -22, 2324004, "#de4c4f"),
    ("Nepal", 84, 28, 30485798, "#eea638"),
    ("Netherlands", 5.75, 52.5, 16664746, "#d8854f"),
    ("New Zealand", 174, -41, 4414509, "#8aabb0"),
    ("Nicaragua", -85, 13, 5869859, "#a7a737"),
    ("Niger", 8, 16, 16068994, "#de4c4f"),
    ("Nigeria", 8, 10, 162470737, "#de4c4f"),
    ("Norway", 10, 62, 4924848, "#d8854f"),
    ("Oman", 57, 21, 2846145, "#eea638"),
    ("Pakistan", 70, 30, 176745364, "#eea638"),
    ("Panama", -80, 9, 3571185, "#a7a737"),
    ("Papua New Guinea", 147, -6, 7013829, "#8aabb0"),
    ("Paraguay", -58, -23, 6568290, "#86a965"),
    ("Peru", -76, -10, 29399817, "#86a965"),
    ("Philippines", 122, 13, 94852030, "#eea638"),
    ("Poland", 20, 52, 38298949, "#d8854f"),
    ("Portugal", -8, 39.5, 10689663, "#d8854f"),
    ("Puerto Rico", -66.5, 18.25, 3745526, "#a7a737"),
    ("Qatar", 51.25, 25.5, 1870041, "#eea638"),
    ("Romania", 25, 46, 21436495, "#d8854f"),
    ("Russia", 100, 60, 142835555, "#d8854f"),
    ("Rwanda", 30, -2, 10942950, "#de4c4f"),
    ("Saudi Arabia", 45, 25, 28082541, "#eea638"),
    ("Senegal", -14, 14, 12767556, "#de4c4f"),
    ("Serbia", 21, 44, 9853969, "#d8854f"),
    ("Sierra Leone", -11.5, 8.5, 5997486, "#de4c4f"),
    ("Singapore", 103.8, 1.3667, 5187933, "#eea638"),
    ("Slovak Republic", 19.5, 48.6667, 5471502, "#d8854f"),
    ("Slovenia", 15, 46, 2035012, "#d8854f"),
    ("Solomon Islands", 159, -8, 552267, "#8aabb0"),
    ("Somalia", 49, 10, 9556873, "#de4c4f"),
    ("South Africa", 24, -29, 50459978, "#de4c4f"),
    ("Spain", -4, 40, 46454895, "#d8854f"),
    ("Sri Lanka", 81, 7, 21045394, "#eea638"),
    ("Sudan", 30, 15, 34735288, "#de4c4f"),
    ("Suriname", -56, 4, 529419, "#86a965"),
    ("Swaziland", 31.5, -26.5, 1203330, "#de4c4f"),
    ("Sweden", 15, 62, 9440747, "#d8854f"),
    ("Switzerland", 8, 47, 7701690, "#d8854f"),
    ("Syria", 38, 35, 20766037, "#eea638"),
    ("Taiwan", 121, 23.5, 23072000, "#eea638"),
    ("Tajikistan", 71, 39, 6976958, "#eea638"),
    ("Tanzania", 35, -6, 46218486, "#de4c4f"),
    ("Thailand", 100, 15, 69518555, "#eea638"),
    ("Togo", 1.1667, 8, 6154813, "#de4c4f"),
    ("Trinidad and Tobago", -61, 11, 1346350, "#a7a737"),
    ("Tunisia", 9, 34, 10594057, "#de4c4f"),
    ("Turkey", 35, 39, 73639596, "#d8854f"),
    ("Turkmenistan", 60, 40, 5105301, "#eea638"),
    ("Uganda", 32, 1, 34509205, "#de4c4f"),
    ("Ukraine", 32, 49, 45190180, "#d8854f"),
    ("United Arab Emirates", 54, 24, 7890924, "#eea638"),
    ("United Kingdom", -2, 54, 62417431, "#d8854f"),
    ("United States", -97, 38, 313085380, "#a7a737"),
    ("Uruguay", -56, -33, 3380008, "#86a965"),
    ("Uzbekistan", 64, 41, 27760267, "#eea638"),
    ("Venezuela", -66, 8, 29436891, "#86a965"),
    ("West Bank and Gaza", 35.25, 32, 4152369, "#eea638"),
    ("Vietnam", 106, 16, 88791996, "#eea638"),
    ("Yemen, Rep.", 48, 15, 24799880, "#eea638"),
    ("Zambia", 30, -15, 13474959, "#de4c4f"),
    ("Zimbabwe", 30, -20, 12754378, "#de4c4f")
]

// The upstream `mapData.map(function (itemOpt) { ... })` — value is the [lon, lat, population] triple the
// geo coord system consumes (first two = position, third = the visualMap's symbolSize dimension).
private let worldPopulationPoints: [[String: Any]] = worldPopulationRows.map { row in
    [
        "name": row.name,
        "value": [row.lon, row.lat, row.value],
        "emphasis": [
            "label": ["position": "right", "show": true] as [String: Any]
        ] as [String: Any],
        "itemStyle": ["color": row.color] as [String: Any]
    ]
}

extension EChartsDemoRegistry {
    static let official_scatter_world_population = EChartsDemo(
        name: "official-scatter-world-population", category: "scatter",
        summary: "World Population (2011) — World Population (2011)",
        width: 800, height: 500,
        nativeSupported: true,
        mapRegistrations: ["world": worldGeoJSON],
        collection: .official,
        webOptionJS: #"""
var latlong = {};
latlong.AD = { latitude: 42.5, longitude: 1.5 };
latlong.AE = { latitude: 24, longitude: 54 };
latlong.AF = { latitude: 33, longitude: 65 };
latlong.AG = { latitude: 17.05, longitude: -61.8 };
latlong.AI = { latitude: 18.25, longitude: -63.1667 };
latlong.AL = { latitude: 41, longitude: 20 };
latlong.AM = { latitude: 40, longitude: 45 };
latlong.AN = { latitude: 12.25, longitude: -68.75 };
latlong.AO = { latitude: -12.5, longitude: 18.5 };
latlong.AP = { latitude: 35, longitude: 105 };
latlong.AQ = { latitude: -90, longitude: 0 };
latlong.AR = { latitude: -34, longitude: -64 };
latlong.AS = { latitude: -14.3333, longitude: -170 };
latlong.AT = { latitude: 47.3333, longitude: 13.3333 };
latlong.AU = { latitude: -27, longitude: 133 };
latlong.AW = { latitude: 12.5, longitude: -69.9667 };
latlong.AZ = { latitude: 40.5, longitude: 47.5 };
latlong.BA = { latitude: 44, longitude: 18 };
latlong.BB = { latitude: 13.1667, longitude: -59.5333 };
latlong.BD = { latitude: 24, longitude: 90 };
latlong.BE = { latitude: 50.8333, longitude: 4 };
latlong.BF = { latitude: 13, longitude: -2 };
latlong.BG = { latitude: 43, longitude: 25 };
latlong.BH = { latitude: 26, longitude: 50.55 };
latlong.BI = { latitude: -3.5, longitude: 30 };
latlong.BJ = { latitude: 9.5, longitude: 2.25 };
latlong.BM = { latitude: 32.3333, longitude: -64.75 };
latlong.BN = { latitude: 4.5, longitude: 114.6667 };
latlong.BO = { latitude: -17, longitude: -65 };
latlong.BR = { latitude: -10, longitude: -55 };
latlong.BS = { latitude: 24.25, longitude: -76 };
latlong.BT = { latitude: 27.5, longitude: 90.5 };
latlong.BV = { latitude: -54.4333, longitude: 3.4 };
latlong.BW = { latitude: -22, longitude: 24 };
latlong.BY = { latitude: 53, longitude: 28 };
latlong.BZ = { latitude: 17.25, longitude: -88.75 };
latlong.CA = { latitude: 54, longitude: -100 };
latlong.CC = { latitude: -12.5, longitude: 96.8333 };
latlong.CD = { latitude: 0, longitude: 25 };
latlong.CF = { latitude: 7, longitude: 21 };
latlong.CG = { latitude: -1, longitude: 15 };
latlong.CH = { latitude: 47, longitude: 8 };
latlong.CI = { latitude: 8, longitude: -5 };
latlong.CK = { latitude: -21.2333, longitude: -159.7667 };
latlong.CL = { latitude: -30, longitude: -71 };
latlong.CM = { latitude: 6, longitude: 12 };
latlong.CN = { latitude: 35, longitude: 105 };
latlong.CO = { latitude: 4, longitude: -72 };
latlong.CR = { latitude: 10, longitude: -84 };
latlong.CU = { latitude: 21.5, longitude: -80 };
latlong.CV = { latitude: 16, longitude: -24 };
latlong.CX = { latitude: -10.5, longitude: 105.6667 };
latlong.CY = { latitude: 35, longitude: 33 };
latlong.CZ = { latitude: 49.75, longitude: 15.5 };
latlong.DE = { latitude: 51, longitude: 9 };
latlong.DJ = { latitude: 11.5, longitude: 43 };
latlong.DK = { latitude: 56, longitude: 10 };
latlong.DM = { latitude: 15.4167, longitude: -61.3333 };
latlong.DO = { latitude: 19, longitude: -70.6667 };
latlong.DZ = { latitude: 28, longitude: 3 };
latlong.EC = { latitude: -2, longitude: -77.5 };
latlong.EE = { latitude: 59, longitude: 26 };
latlong.EG = { latitude: 27, longitude: 30 };
latlong.EH = { latitude: 24.5, longitude: -13 };
latlong.ER = { latitude: 15, longitude: 39 };
latlong.ES = { latitude: 40, longitude: -4 };
latlong.ET = { latitude: 8, longitude: 38 };
latlong.EU = { latitude: 47, longitude: 8 };
latlong.FI = { latitude: 62, longitude: 26 };
latlong.FJ = { latitude: -18, longitude: 175 };
latlong.FK = { latitude: -51.75, longitude: -59 };
latlong.FM = { latitude: 6.9167, longitude: 158.25 };
latlong.FO = { latitude: 62, longitude: -7 };
latlong.FR = { latitude: 46, longitude: 2 };
latlong.GA = { latitude: -1, longitude: 11.75 };
latlong.GB = { latitude: 54, longitude: -2 };
latlong.GD = { latitude: 12.1167, longitude: -61.6667 };
latlong.GE = { latitude: 42, longitude: 43.5 };
latlong.GF = { latitude: 4, longitude: -53 };
latlong.GH = { latitude: 8, longitude: -2 };
latlong.GI = { latitude: 36.1833, longitude: -5.3667 };
latlong.GL = { latitude: 72, longitude: -40 };
latlong.GM = { latitude: 13.4667, longitude: -16.5667 };
latlong.GN = { latitude: 11, longitude: -10 };
latlong.GP = { latitude: 16.25, longitude: -61.5833 };
latlong.GQ = { latitude: 2, longitude: 10 };
latlong.GR = { latitude: 39, longitude: 22 };
latlong.GS = { latitude: -54.5, longitude: -37 };
latlong.GT = { latitude: 15.5, longitude: -90.25 };
latlong.GU = { latitude: 13.4667, longitude: 144.7833 };
latlong.GW = { latitude: 12, longitude: -15 };
latlong.GY = { latitude: 5, longitude: -59 };
latlong.HK = { latitude: 22.25, longitude: 114.1667 };
latlong.HM = { latitude: -53.1, longitude: 72.5167 };
latlong.HN = { latitude: 15, longitude: -86.5 };
latlong.HR = { latitude: 45.1667, longitude: 15.5 };
latlong.HT = { latitude: 19, longitude: -72.4167 };
latlong.HU = { latitude: 47, longitude: 20 };
latlong.ID = { latitude: -5, longitude: 120 };
latlong.IE = { latitude: 53, longitude: -8 };
latlong.IL = { latitude: 31.5, longitude: 34.75 };
latlong.IN = { latitude: 20, longitude: 77 };
latlong.IO = { latitude: -6, longitude: 71.5 };
latlong.IQ = { latitude: 33, longitude: 44 };
latlong.IR = { latitude: 32, longitude: 53 };
latlong.IS = { latitude: 65, longitude: -18 };
latlong.IT = { latitude: 42.8333, longitude: 12.8333 };
latlong.JM = { latitude: 18.25, longitude: -77.5 };
latlong.JO = { latitude: 31, longitude: 36 };
latlong.JP = { latitude: 36, longitude: 138 };
latlong.KE = { latitude: 1, longitude: 38 };
latlong.KG = { latitude: 41, longitude: 75 };
latlong.KH = { latitude: 13, longitude: 105 };
latlong.KI = { latitude: 1.4167, longitude: 173 };
latlong.KM = { latitude: -12.1667, longitude: 44.25 };
latlong.KN = { latitude: 17.3333, longitude: -62.75 };
latlong.KP = { latitude: 40, longitude: 127 };
latlong.KR = { latitude: 37, longitude: 127.5 };
latlong.KW = { latitude: 29.3375, longitude: 47.6581 };
latlong.KY = { latitude: 19.5, longitude: -80.5 };
latlong.KZ = { latitude: 48, longitude: 68 };
latlong.LA = { latitude: 18, longitude: 105 };
latlong.LB = { latitude: 33.8333, longitude: 35.8333 };
latlong.LC = { latitude: 13.8833, longitude: -61.1333 };
latlong.LI = { latitude: 47.1667, longitude: 9.5333 };
latlong.LK = { latitude: 7, longitude: 81 };
latlong.LR = { latitude: 6.5, longitude: -9.5 };
latlong.LS = { latitude: -29.5, longitude: 28.5 };
latlong.LT = { latitude: 55, longitude: 24 };
latlong.LU = { latitude: 49.75, longitude: 6 };
latlong.LV = { latitude: 57, longitude: 25 };
latlong.LY = { latitude: 25, longitude: 17 };
latlong.MA = { latitude: 32, longitude: -5 };
latlong.MC = { latitude: 43.7333, longitude: 7.4 };
latlong.MD = { latitude: 47, longitude: 29 };
latlong.ME = { latitude: 42.5, longitude: 19.4 };
latlong.MG = { latitude: -20, longitude: 47 };
latlong.MH = { latitude: 9, longitude: 168 };
latlong.MK = { latitude: 41.8333, longitude: 22 };
latlong.ML = { latitude: 17, longitude: -4 };
latlong.MM = { latitude: 22, longitude: 98 };
latlong.MN = { latitude: 46, longitude: 105 };
latlong.MO = { latitude: 22.1667, longitude: 113.55 };
latlong.MP = { latitude: 15.2, longitude: 145.75 };
latlong.MQ = { latitude: 14.6667, longitude: -61 };
latlong.MR = { latitude: 20, longitude: -12 };
latlong.MS = { latitude: 16.75, longitude: -62.2 };
latlong.MT = { latitude: 35.8333, longitude: 14.5833 };
latlong.MU = { latitude: -20.2833, longitude: 57.55 };
latlong.MV = { latitude: 3.25, longitude: 73 };
latlong.MW = { latitude: -13.5, longitude: 34 };
latlong.MX = { latitude: 23, longitude: -102 };
latlong.MY = { latitude: 2.5, longitude: 112.5 };
latlong.MZ = { latitude: -18.25, longitude: 35 };
latlong.NA = { latitude: -22, longitude: 17 };
latlong.NC = { latitude: -21.5, longitude: 165.5 };
latlong.NE = { latitude: 16, longitude: 8 };
latlong.NF = { latitude: -29.0333, longitude: 167.95 };
latlong.NG = { latitude: 10, longitude: 8 };
latlong.NI = { latitude: 13, longitude: -85 };
latlong.NL = { latitude: 52.5, longitude: 5.75 };
latlong.NO = { latitude: 62, longitude: 10 };
latlong.NP = { latitude: 28, longitude: 84 };
latlong.NR = { latitude: -0.5333, longitude: 166.9167 };
latlong.NU = { latitude: -19.0333, longitude: -169.8667 };
latlong.NZ = { latitude: -41, longitude: 174 };
latlong.OM = { latitude: 21, longitude: 57 };
latlong.PA = { latitude: 9, longitude: -80 };
latlong.PE = { latitude: -10, longitude: -76 };
latlong.PF = { latitude: -15, longitude: -140 };
latlong.PG = { latitude: -6, longitude: 147 };
latlong.PH = { latitude: 13, longitude: 122 };
latlong.PK = { latitude: 30, longitude: 70 };
latlong.PL = { latitude: 52, longitude: 20 };
latlong.PM = { latitude: 46.8333, longitude: -56.3333 };
latlong.PR = { latitude: 18.25, longitude: -66.5 };
latlong.PS = { latitude: 32, longitude: 35.25 };
latlong.PT = { latitude: 39.5, longitude: -8 };
latlong.PW = { latitude: 7.5, longitude: 134.5 };
latlong.PY = { latitude: -23, longitude: -58 };
latlong.QA = { latitude: 25.5, longitude: 51.25 };
latlong.RE = { latitude: -21.1, longitude: 55.6 };
latlong.RO = { latitude: 46, longitude: 25 };
latlong.RS = { latitude: 44, longitude: 21 };
latlong.RU = { latitude: 60, longitude: 100 };
latlong.RW = { latitude: -2, longitude: 30 };
latlong.SA = { latitude: 25, longitude: 45 };
latlong.SB = { latitude: -8, longitude: 159 };
latlong.SC = { latitude: -4.5833, longitude: 55.6667 };
latlong.SD = { latitude: 15, longitude: 30 };
latlong.SE = { latitude: 62, longitude: 15 };
latlong.SG = { latitude: 1.3667, longitude: 103.8 };
latlong.SH = { latitude: -15.9333, longitude: -5.7 };
latlong.SI = { latitude: 46, longitude: 15 };
latlong.SJ = { latitude: 78, longitude: 20 };
latlong.SK = { latitude: 48.6667, longitude: 19.5 };
latlong.SL = { latitude: 8.5, longitude: -11.5 };
latlong.SM = { latitude: 43.7667, longitude: 12.4167 };
latlong.SN = { latitude: 14, longitude: -14 };
latlong.SO = { latitude: 10, longitude: 49 };
latlong.SR = { latitude: 4, longitude: -56 };
latlong.ST = { latitude: 1, longitude: 7 };
latlong.SV = { latitude: 13.8333, longitude: -88.9167 };
latlong.SY = { latitude: 35, longitude: 38 };
latlong.SZ = { latitude: -26.5, longitude: 31.5 };
latlong.TC = { latitude: 21.75, longitude: -71.5833 };
latlong.TD = { latitude: 15, longitude: 19 };
latlong.TF = { latitude: -43, longitude: 67 };
latlong.TG = { latitude: 8, longitude: 1.1667 };
latlong.TH = { latitude: 15, longitude: 100 };
latlong.TJ = { latitude: 39, longitude: 71 };
latlong.TK = { latitude: -9, longitude: -172 };
latlong.TM = { latitude: 40, longitude: 60 };
latlong.TN = { latitude: 34, longitude: 9 };
latlong.TO = { latitude: -20, longitude: -175 };
latlong.TR = { latitude: 39, longitude: 35 };
latlong.TT = { latitude: 11, longitude: -61 };
latlong.TV = { latitude: -8, longitude: 178 };
latlong.TW = { latitude: 23.5, longitude: 121 };
latlong.TZ = { latitude: -6, longitude: 35 };
latlong.UA = { latitude: 49, longitude: 32 };
latlong.UG = { latitude: 1, longitude: 32 };
latlong.UM = { latitude: 19.2833, longitude: 166.6 };
latlong.US = { latitude: 38, longitude: -97 };
latlong.UY = { latitude: -33, longitude: -56 };
latlong.UZ = { latitude: 41, longitude: 64 };
latlong.VA = { latitude: 41.9, longitude: 12.45 };
latlong.VC = { latitude: 13.25, longitude: -61.2 };
latlong.VE = { latitude: 8, longitude: -66 };
latlong.VG = { latitude: 18.5, longitude: -64.5 };
latlong.VI = { latitude: 18.3333, longitude: -64.8333 };
latlong.VN = { latitude: 16, longitude: 106 };
latlong.VU = { latitude: -16, longitude: 167 };
latlong.WF = { latitude: -13.3, longitude: -176.2 };
latlong.WS = { latitude: -13.5833, longitude: -172.3333 };
latlong.YE = { latitude: 15, longitude: 48 };
latlong.YT = { latitude: -12.8333, longitude: 45.1667 };
latlong.ZA = { latitude: -29, longitude: 24 };
latlong.ZM = { latitude: -15, longitude: 30 };
latlong.ZW = { latitude: -20, longitude: 30 };

var mapData = [
  { code: 'AF', name: 'Afghanistan', value: 32358260, color: '#eea638' },
  { code: 'AL', name: 'Albania', value: 3215988, color: '#d8854f' },
  { code: 'DZ', name: 'Algeria', value: 35980193, color: '#de4c4f' },
  { code: 'AO', name: 'Angola', value: 19618432, color: '#de4c4f' },
  { code: 'AR', name: 'Argentina', value: 40764561, color: '#86a965' },
  { code: 'AM', name: 'Armenia', value: 3100236, color: '#d8854f' },
  { code: 'AU', name: 'Australia', value: 22605732, color: '#8aabb0' },
  { code: 'AT', name: 'Austria', value: 8413429, color: '#d8854f' },
  { code: 'AZ', name: 'Azerbaijan', value: 9306023, color: '#d8854f' },
  { code: 'BH', name: 'Bahrain', value: 1323535, color: '#eea638' },
  { code: 'BD', name: 'Bangladesh', value: 150493658, color: '#eea638' },
  { code: 'BY', name: 'Belarus', value: 9559441, color: '#d8854f' },
  { code: 'BE', name: 'Belgium', value: 10754056, color: '#d8854f' },
  { code: 'BJ', name: 'Benin', value: 9099922, color: '#de4c4f' },
  { code: 'BT', name: 'Bhutan', value: 738267, color: '#eea638' },
  { code: 'BO', name: 'Bolivia', value: 10088108, color: '#86a965' },
  {
    code: 'BA',
    name: 'Bosnia and Herzegovina',
    value: 3752228,
    color: '#d8854f'
  },
  { code: 'BW', name: 'Botswana', value: 2030738, color: '#de4c4f' },
  { code: 'BR', name: 'Brazil', value: 196655014, color: '#86a965' },
  { code: 'BN', name: 'Brunei', value: 405938, color: '#eea638' },
  { code: 'BG', name: 'Bulgaria', value: 7446135, color: '#d8854f' },
  { code: 'BF', name: 'Burkina Faso', value: 16967845, color: '#de4c4f' },
  { code: 'BI', name: 'Burundi', value: 8575172, color: '#de4c4f' },
  { code: 'KH', name: 'Cambodia', value: 14305183, color: '#eea638' },
  { code: 'CM', name: 'Cameroon', value: 20030362, color: '#de4c4f' },
  { code: 'CA', name: 'Canada', value: 34349561, color: '#a7a737' },
  { code: 'CV', name: 'Cape Verde', value: 500585, color: '#de4c4f' },
  {
    code: 'CF',
    name: 'Central African Rep.',
    value: 4486837,
    color: '#de4c4f'
  },
  { code: 'TD', name: 'Chad', value: 11525496, color: '#de4c4f' },
  { code: 'CL', name: 'Chile', value: 17269525, color: '#86a965' },
  { code: 'CN', name: 'China', value: 1347565324, color: '#eea638' },
  { code: 'CO', name: 'Colombia', value: 46927125, color: '#86a965' },
  { code: 'KM', name: 'Comoros', value: 753943, color: '#de4c4f' },
  { code: 'CD', name: 'Congo, Dem. Rep.', value: 67757577, color: '#de4c4f' },
  { code: 'CG', name: 'Congo, Rep.', value: 4139748, color: '#de4c4f' },
  { code: 'CR', name: 'Costa Rica', value: 4726575, color: '#a7a737' },
  { code: 'CI', name: "Cote d'Ivoire", value: 20152894, color: '#de4c4f' },
  { code: 'HR', name: 'Croatia', value: 4395560, color: '#d8854f' },
  { code: 'CU', name: 'Cuba', value: 11253665, color: '#a7a737' },
  { code: 'CY', name: 'Cyprus', value: 1116564, color: '#d8854f' },
  { code: 'CZ', name: 'Czech Rep.', value: 10534293, color: '#d8854f' },
  { code: 'DK', name: 'Denmark', value: 5572594, color: '#d8854f' },
  { code: 'DJ', name: 'Djibouti', value: 905564, color: '#de4c4f' },
  { code: 'DO', name: 'Dominican Rep.', value: 10056181, color: '#a7a737' },
  { code: 'EC', name: 'Ecuador', value: 14666055, color: '#86a965' },
  { code: 'EG', name: 'Egypt', value: 82536770, color: '#de4c4f' },
  { code: 'SV', name: 'El Salvador', value: 6227491, color: '#a7a737' },
  { code: 'GQ', name: 'Equatorial Guinea', value: 720213, color: '#de4c4f' },
  { code: 'ER', name: 'Eritrea', value: 5415280, color: '#de4c4f' },
  { code: 'EE', name: 'Estonia', value: 1340537, color: '#d8854f' },
  { code: 'ET', name: 'Ethiopia', value: 84734262, color: '#de4c4f' },
  { code: 'FJ', name: 'Fiji', value: 868406, color: '#8aabb0' },
  { code: 'FI', name: 'Finland', value: 5384770, color: '#d8854f' },
  { code: 'FR', name: 'France', value: 63125894, color: '#d8854f' },
  { code: 'GA', name: 'Gabon', value: 1534262, color: '#de4c4f' },
  { code: 'GM', name: 'Gambia', value: 1776103, color: '#de4c4f' },
  { code: 'GE', name: 'Georgia', value: 4329026, color: '#d8854f' },
  { code: 'DE', name: 'Germany', value: 82162512, color: '#d8854f' },
  { code: 'GH', name: 'Ghana', value: 24965816, color: '#de4c4f' },
  { code: 'GR', name: 'Greece', value: 11390031, color: '#d8854f' },
  { code: 'GT', name: 'Guatemala', value: 14757316, color: '#a7a737' },
  { code: 'GN', name: 'Guinea', value: 10221808, color: '#de4c4f' },
  { code: 'GW', name: 'Guinea-Bissau', value: 1547061, color: '#de4c4f' },
  { code: 'GY', name: 'Guyana', value: 756040, color: '#86a965' },
  { code: 'HT', name: 'Haiti', value: 10123787, color: '#a7a737' },
  { code: 'HN', name: 'Honduras', value: 7754687, color: '#a7a737' },
  { code: 'HK', name: 'Hong Kong, China', value: 7122187, color: '#eea638' },
  { code: 'HU', name: 'Hungary', value: 9966116, color: '#d8854f' },
  { code: 'IS', name: 'Iceland', value: 324366, color: '#d8854f' },
  { code: 'IN', name: 'India', value: 1241491960, color: '#eea638' },
  { code: 'ID', name: 'Indonesia', value: 242325638, color: '#eea638' },
  { code: 'IR', name: 'Iran', value: 74798599, color: '#eea638' },
  { code: 'IQ', name: 'Iraq', value: 32664942, color: '#eea638' },
  { code: 'IE', name: 'Ireland', value: 4525802, color: '#d8854f' },
  { code: 'IL', name: 'Israel', value: 7562194, color: '#eea638' },
  { code: 'IT', name: 'Italy', value: 60788694, color: '#d8854f' },
  { code: 'JM', name: 'Jamaica', value: 2751273, color: '#a7a737' },
  { code: 'JP', name: 'Japan', value: 126497241, color: '#eea638' },
  { code: 'JO', name: 'Jordan', value: 6330169, color: '#eea638' },
  { code: 'KZ', name: 'Kazakhstan', value: 16206750, color: '#eea638' },
  { code: 'KE', name: 'Kenya', value: 41609728, color: '#de4c4f' },
  { code: 'KP', name: 'Korea, Dem. Rep.', value: 24451285, color: '#eea638' },
  { code: 'KR', name: 'Korea, Rep.', value: 48391343, color: '#eea638' },
  { code: 'KW', name: 'Kuwait', value: 2818042, color: '#eea638' },
  { code: 'KG', name: 'Kyrgyzstan', value: 5392580, color: '#eea638' },
  { code: 'LA', name: 'Laos', value: 6288037, color: '#eea638' },
  { code: 'LV', name: 'Latvia', value: 2243142, color: '#d8854f' },
  { code: 'LB', name: 'Lebanon', value: 4259405, color: '#eea638' },
  { code: 'LS', name: 'Lesotho', value: 2193843, color: '#de4c4f' },
  { code: 'LR', name: 'Liberia', value: 4128572, color: '#de4c4f' },
  { code: 'LY', name: 'Libya', value: 6422772, color: '#de4c4f' },
  { code: 'LT', name: 'Lithuania', value: 3307481, color: '#d8854f' },
  { code: 'LU', name: 'Luxembourg', value: 515941, color: '#d8854f' },
  { code: 'MK', name: 'Macedonia, FYR', value: 2063893, color: '#d8854f' },
  { code: 'MG', name: 'Madagascar', value: 21315135, color: '#de4c4f' },
  { code: 'MW', name: 'Malawi', value: 15380888, color: '#de4c4f' },
  { code: 'MY', name: 'Malaysia', value: 28859154, color: '#eea638' },
  { code: 'ML', name: 'Mali', value: 15839538, color: '#de4c4f' },
  { code: 'MR', name: 'Mauritania', value: 3541540, color: '#de4c4f' },
  { code: 'MU', name: 'Mauritius', value: 1306593, color: '#de4c4f' },
  { code: 'MX', name: 'Mexico', value: 114793341, color: '#a7a737' },
  { code: 'MD', name: 'Moldova', value: 3544864, color: '#d8854f' },
  { code: 'MN', name: 'Mongolia', value: 2800114, color: '#eea638' },
  { code: 'ME', name: 'Montenegro', value: 632261, color: '#d8854f' },
  { code: 'MA', name: 'Morocco', value: 32272974, color: '#de4c4f' },
  { code: 'MZ', name: 'Mozambique', value: 23929708, color: '#de4c4f' },
  { code: 'MM', name: 'Myanmar', value: 48336763, color: '#eea638' },
  { code: 'NA', name: 'Namibia', value: 2324004, color: '#de4c4f' },
  { code: 'NP', name: 'Nepal', value: 30485798, color: '#eea638' },
  { code: 'NL', name: 'Netherlands', value: 16664746, color: '#d8854f' },
  { code: 'NZ', name: 'New Zealand', value: 4414509, color: '#8aabb0' },
  { code: 'NI', name: 'Nicaragua', value: 5869859, color: '#a7a737' },
  { code: 'NE', name: 'Niger', value: 16068994, color: '#de4c4f' },
  { code: 'NG', name: 'Nigeria', value: 162470737, color: '#de4c4f' },
  { code: 'NO', name: 'Norway', value: 4924848, color: '#d8854f' },
  { code: 'OM', name: 'Oman', value: 2846145, color: '#eea638' },
  { code: 'PK', name: 'Pakistan', value: 176745364, color: '#eea638' },
  { code: 'PA', name: 'Panama', value: 3571185, color: '#a7a737' },
  { code: 'PG', name: 'Papua New Guinea', value: 7013829, color: '#8aabb0' },
  { code: 'PY', name: 'Paraguay', value: 6568290, color: '#86a965' },
  { code: 'PE', name: 'Peru', value: 29399817, color: '#86a965' },
  { code: 'PH', name: 'Philippines', value: 94852030, color: '#eea638' },
  { code: 'PL', name: 'Poland', value: 38298949, color: '#d8854f' },
  { code: 'PT', name: 'Portugal', value: 10689663, color: '#d8854f' },
  { code: 'PR', name: 'Puerto Rico', value: 3745526, color: '#a7a737' },
  { code: 'QA', name: 'Qatar', value: 1870041, color: '#eea638' },
  { code: 'RO', name: 'Romania', value: 21436495, color: '#d8854f' },
  { code: 'RU', name: 'Russia', value: 142835555, color: '#d8854f' },
  { code: 'RW', name: 'Rwanda', value: 10942950, color: '#de4c4f' },
  { code: 'SA', name: 'Saudi Arabia', value: 28082541, color: '#eea638' },
  { code: 'SN', name: 'Senegal', value: 12767556, color: '#de4c4f' },
  { code: 'RS', name: 'Serbia', value: 9853969, color: '#d8854f' },
  { code: 'SL', name: 'Sierra Leone', value: 5997486, color: '#de4c4f' },
  { code: 'SG', name: 'Singapore', value: 5187933, color: '#eea638' },
  { code: 'SK', name: 'Slovak Republic', value: 5471502, color: '#d8854f' },
  { code: 'SI', name: 'Slovenia', value: 2035012, color: '#d8854f' },
  { code: 'SB', name: 'Solomon Islands', value: 552267, color: '#8aabb0' },
  { code: 'SO', name: 'Somalia', value: 9556873, color: '#de4c4f' },
  { code: 'ZA', name: 'South Africa', value: 50459978, color: '#de4c4f' },
  { code: 'ES', name: 'Spain', value: 46454895, color: '#d8854f' },
  { code: 'LK', name: 'Sri Lanka', value: 21045394, color: '#eea638' },
  { code: 'SD', name: 'Sudan', value: 34735288, color: '#de4c4f' },
  { code: 'SR', name: 'Suriname', value: 529419, color: '#86a965' },
  { code: 'SZ', name: 'Swaziland', value: 1203330, color: '#de4c4f' },
  { code: 'SE', name: 'Sweden', value: 9440747, color: '#d8854f' },
  { code: 'CH', name: 'Switzerland', value: 7701690, color: '#d8854f' },
  { code: 'SY', name: 'Syria', value: 20766037, color: '#eea638' },
  { code: 'TW', name: 'Taiwan', value: 23072000, color: '#eea638' },
  { code: 'TJ', name: 'Tajikistan', value: 6976958, color: '#eea638' },
  { code: 'TZ', name: 'Tanzania', value: 46218486, color: '#de4c4f' },
  { code: 'TH', name: 'Thailand', value: 69518555, color: '#eea638' },
  { code: 'TG', name: 'Togo', value: 6154813, color: '#de4c4f' },
  { code: 'TT', name: 'Trinidad and Tobago', value: 1346350, color: '#a7a737' },
  { code: 'TN', name: 'Tunisia', value: 10594057, color: '#de4c4f' },
  { code: 'TR', name: 'Turkey', value: 73639596, color: '#d8854f' },
  { code: 'TM', name: 'Turkmenistan', value: 5105301, color: '#eea638' },
  { code: 'UG', name: 'Uganda', value: 34509205, color: '#de4c4f' },
  { code: 'UA', name: 'Ukraine', value: 45190180, color: '#d8854f' },
  {
    code: 'AE',
    name: 'United Arab Emirates',
    value: 7890924,
    color: '#eea638'
  },
  { code: 'GB', name: 'United Kingdom', value: 62417431, color: '#d8854f' },
  { code: 'US', name: 'United States', value: 313085380, color: '#a7a737' },
  { code: 'UY', name: 'Uruguay', value: 3380008, color: '#86a965' },
  { code: 'UZ', name: 'Uzbekistan', value: 27760267, color: '#eea638' },
  { code: 'VE', name: 'Venezuela', value: 29436891, color: '#86a965' },
  { code: 'PS', name: 'West Bank and Gaza', value: 4152369, color: '#eea638' },
  { code: 'VN', name: 'Vietnam', value: 88791996, color: '#eea638' },
  { code: 'YE', name: 'Yemen, Rep.', value: 24799880, color: '#eea638' },
  { code: 'ZM', name: 'Zambia', value: 13474959, color: '#de4c4f' },
  { code: 'ZW', name: 'Zimbabwe', value: 12754378, color: '#de4c4f' }
];

var max = -Infinity;
var min = Infinity;
mapData.forEach(function (itemOpt) {
  if (itemOpt.value > max) {
    max = itemOpt.value;
  }
  if (itemOpt.value < min) {
    min = itemOpt.value;
  }
});

option = {
  backgroundColor: '#404a59',
  title: {
    text: 'World Population (2011)',
    subtext: 'From Gapminder',
    left: 'center',
    top: 'top',
    textStyle: {
      color: '#fff'
    }
  },
  tooltip: {
    trigger: 'item',
    formatter: function (params) {
      var value = (params.value + '').split('.');
      value =
        value[0].replace(/(\d{1,3})(?=(?:\d{3})+(?!\d))/g, '$1,') +
        '.' +
        value[1];
      return params.seriesName + '<br/>' + params.name + ' : ' + value;
    }
  },
  visualMap: {
    show: false,
    min: 0,
    max: max,
    inRange: {
      symbolSize: [6, 60]
    }
  },
  geo: {
    name: 'World Population (2010)',
    type: 'map',
    map: 'world',
    roam: true,
    emphasis: {
      label: {
        show: false
      },
      itemStyle: {
        areaColor: '#2a333d'
      }
    },
    itemStyle: {
      areaColor: '#323c48',
      borderColor: '#111'
    }
  },
  series: [
    {
      type: 'scatter',
      coordinateSystem: 'geo',
      data: mapData.map(function (itemOpt) {
        return {
          name: itemOpt.name,
          value: [
            latlong[itemOpt.code].longitude,
            latlong[itemOpt.code].latitude,
            itemOpt.value
          ],
          emphasis: {
            label: {
              position: 'right',
              show: true
            }
          },
          itemStyle: {
            color: itemOpt.color
          }
        };
      })
    }
  ]
};
"""#,
        option: {
            // Upstream registers nothing (the editor injects the `world` map); the native pane must.
            ECharts.registerMap("world", worldGeoJSON)
            let opt: [String: Any] = [
                "backgroundColor": "#404a59",
                "title": [
                    "text": "World Population (2011)",
                    "subtext": "From Gapminder",
                    "left": "center",
                    "top": "top",
                    "textStyle": ["color": "#fff"] as [String: Any]
                ] as [String: Any],
                // PORT-NOTE: tooltip.formatter omitted — the JS closure splits `params.value` on '.',
                // thousands-separates the integer part with a regex, and renders
                // "<seriesName><br/><countryName> : <formatted value>". Not expressible in the Swift option.
                "tooltip": [
                    "trigger": "item"
                ] as [String: Any],
                "visualMap": [
                    "show": false,
                    "min": 0.0,
                    "max": 1347565324.0,   // JS: max of mapData[].value (China)
                    "inRange": [
                        "symbolSize": [6.0, 60.0]
                    ] as [String: Any]
                ] as [String: Any],
                "geo": [
                    "name": "World Population (2010)",
                    "type": "map",
                    "map": "world",
                    "roam": true,
                    "emphasis": [
                        "label": ["show": false] as [String: Any],
                        "itemStyle": ["areaColor": "#2a333d"] as [String: Any]
                    ] as [String: Any],
                    "itemStyle": [
                        "areaColor": "#323c48",
                        "borderColor": "#111"
                    ] as [String: Any]
                ] as [String: Any],
                "series": [
                    [
                        "type": "scatter",
                        "coordinateSystem": "geo",
                        "data": worldPopulationPoints as [Any]
                    ] as [String: Any]
                ]
            ]
            return opt
        }())
}
