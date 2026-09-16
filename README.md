# EChartsSwift

**面向 iOS 和 macOS 的实验性 Apache ECharts 原生 Swift 实现。**

EChartsSwift 将 ECharts 的配置、数据处理、坐标系、布局和交互逻辑移植到 Swift，通过原生绘制后端输出图表。应用中的原生图表不依赖 WebView 或 JavaScript；仓库里的 Web 对照窗口用于与官方 ECharts 比较。

项目原名为 **iOS-Chart**，目前处于 **Experimental / Unofficial** 阶段，并非 Apache 官方发行版。目标是尽量保留官方 API 与 option 的使用方式，**目前不承诺完整 API、全部配置项、动画或性能与 Web 版本等价**。

当前参考版本为 ECharts / ZRender **6.1.0**，具体提交见 [upstream.lock](upstream/upstream.lock)。官方在线文档可能继续更新；本文中的 Swift 写法以当前仓库实现为准。

## 目录

- [安装与模块](#安装与模块)
- [初始化一个图表](#初始化一个图表)
- [官方 API 与 Swift 对应关系](#官方-api-与-swift-对应关系)
- [Option 对应规则](#option-对应规则)
- [各类图表的初始化与配置](#各类图表的初始化与配置)
- [数据更新与事件](#数据更新与事件)
- [尺寸与生命周期](#尺寸与生命周期)
- [当前兼容边界](#当前兼容边界)
- [示例与开发](#示例与开发)

## 安装与模块

[Package.swift](Package.swift) 声明的最低平台为 **iOS 15 / macOS 12**，Swift tools version 为 **5.9**。

在 Xcode 的 **Add Package Dependencies** 中添加当前仓库地址：

```text
https://github.com/andy-sheng/EChartsSwift.git
```

选择 `EChartsKit` 和 `NativeRenderer` 两个 product。直接使用 ZRender 类型时，再添加 `ZRenderKit`。

也可以在已有 Swift package 中加入以下依赖片段：

```swift
// Package.dependencies
.package(url: "https://github.com/andy-sheng/EChartsSwift.git", branch: "main")

// 你的应用 target.dependencies
.product(name: "EChartsKit", package: "echartsswift"),
.product(name: "NativeRenderer", package: "echartsswift"),
.product(name: "ZRenderKit", package: "echartsswift")
```

SwiftPM 根据仓库 URL 推导 package identity（`echartsswift`）；product 和 Swift import 名仍使用 `EChartsKit`、`NativeRenderer` 等模块名。采用 `main` 时，建议应用保存 `Package.resolved`，固定实际使用的提交。

| 模块 | 用途 |
|---|---|
| `EChartsKit` | `echarts` 入口、option、模型、图表、组件、事件与行为 |
| `NativeRenderer` | 注册原生 `CanvasRenderer`，并导出 `NativePainter` |
| `NativePainter` | `NativeChartHost`、Core Graphics / Core Animation 绘制与原生输入 |
| `ZRenderKit` | 场景、图形、动画、Handler，以及 `ZRenderResizeOpt` 等底层类型 |
| `ApplePainterSupport` | Apple 平台后端共用的路径、文字、图像和绘制支持 |

这里的 `CanvasRenderer` 是与官方命名对应的**原生 Core Graphics 后端**，不是 HTML Canvas。可选的 [RasterizerPainter](Examples/PainterGallery/README.md) 单独集成，不是核心 package 的必需依赖。

## 初始化一个图表

所有图表共用同一个初始化流程：**注册 renderer → 创建原生容器 → 初始化实例 → 设置 option**。图表种类由 `series.type` 决定。

官方参考：[快速上手](https://echarts.apache.org/handbook/zh/get-started/)、[echarts.init](https://echarts.apache.org/zh/api.html#echarts.init)、[模块引入](https://echarts.apache.org/handbook/zh/basics/import/)。

### Web 写法

以下假设已经引入完整的官方 `echarts` 包，并准备好具有尺寸的 DOM 容器：

```javascript
const chart = echarts.init(document.getElementById('chart'));
chart.setOption({
  xAxis: { type: 'category', data: ['一月', '二月', '三月'] },
  yAxis: { type: 'value' },
  series: [{ id: 'sales', type: 'bar', data: [18, 26, 21] }]
});
```

### Swift 写法：iOS 与 macOS 共用

```swift
import Foundation
import EChartsKit
import NativeRenderer

let barOption: [String: Any] = [
    "xAxis": [
        "type": "category",
        "data": ["一月", "二月", "三月"]
    ] as [String: Any],
    "yAxis": ["type": "value"],
    "series": [[
        "id": "sales",
        "type": "bar",
        "data": [18.0, 26.0, 21.0]
    ] as [String: Any]]
]

@MainActor
func makeNativeChart(
    option: [String: Any],
    theme: Any? = nil
) throws -> (host: NativeChartHost, chart: EChartsView) {
    echarts.use([CanvasRenderer.self])

    let host = NativeChartHost(
        frame: CGRect(x: 0, y: 0, width: 640, height: 360)
    )
    var opts = EChartsInitOpts()
    opts.renderer = "canvas"

    let chart = try echarts.`init`(host, theme, opts)
    chart.setOption(option)
    return (host, chart)
}
```

`NativeChartHost` 在 iOS 上是 `UIView`，在 macOS 上是 `NSView`。`EChartsView` 是持有图表状态、ZRender 和交互绑定的对象，**它本身不是 UIKit / AppKit 视图**。应用需要持有返回的 `chart`，并将 `host` 加入视图层级。

`init` 是 Swift 关键字，因此调用时写成 ``echarts.`init`(...)``。注册扩展、创建实例和修改图表都应在主线程执行。

### UIKit 接入

将上面的 `barOption` 和 `makeNativeChart` 放入应用，再添加以下控制器：

```swift
import UIKit

@MainActor
final class ChartViewController: UIViewController {
    private var chart: EChartsView?

    override func loadView() {
        do {
            let created = try makeNativeChart(option: barOption)
            view = created.host
            chart = created.chart
        } catch {
            view = UIView()
            assertionFailure("Chart initialization failed: \(error)")
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        chart?.resize()
    }

    // 页面永久移除或需要重建图表时，由页面所有者调用。
    func disposeChart() {
        chart?.dispose()
        chart = nil
    }
}
```

### AppKit 接入

```swift
import AppKit

@MainActor
final class ChartViewController: NSViewController {
    private var chart: EChartsView?

    override func loadView() {
        do {
            let created = try makeNativeChart(option: barOption)
            view = created.host
            chart = created.chart
        } catch {
            view = NSView()
            assertionFailure("Chart initialization failed: \(error)")
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        chart?.resize()
    }

    func disposeChart() {
        chart?.dispose()
        chart = nil
    }
}
```

两个控制器示例分别用于各自平台。SwiftUI 应用可以将 host 包装在 `UIViewRepresentable` / `NSViewRepresentable` 中，由 Coordinator 持有 chart，在拆除时调用 `dispose()`。

## 官方 API 与 Swift 对应关系

下表中的 `chart` 均指 ``try echarts.`init`(...)`` 返回的 **`EChartsView`**；`chart.ec` 是底层 `ECharts` 引擎。

### 全局入口

| 官方 Web API | 当前 Swift 写法 | 对应规则 |
|---|---|---|
| [echarts.use](https://echarts.apache.org/zh/api.html#echarts.use) | `echarts.use([CanvasRenderer.self])` | 传 Swift 扩展类型；当前常用图表和组件在引擎内部安装，不需要写不存在的 `BarChart.self` / `GridComponent.self` |
| [echarts.init](https://echarts.apache.org/zh/api.html#echarts.init) | ``try echarts.`init`(host, theme, opts)`` | DOM 换成 `NativeChartHost`；`opts` 为 `EChartsInitOpts`；初始化可能抛错 |
| [echarts.getInstanceByDom](https://echarts.apache.org/zh/api.html#echarts.getInstanceByDom) | `echarts.getInstanceByDom(host)` | 同一个 host 已有未销毁实例时，再次 init 返回原实例 |
| [echarts.registerTheme](https://echarts.apache.org/zh/api.html#echarts.registerTheme) | `echarts.registerTheme(name, theme)` | theme 使用 `[String: Any]`；初始化时传已注册名称或主题字典 |
| [echarts.registerMap](https://echarts.apache.org/zh/api.html#echarts.registerMap) | `ECharts.registerMap(name, geoJSON)` | 当前入口位于大写 `ECharts`，在设置地图 option 之前注册 |
| [echarts.getMap](https://echarts.apache.org/zh/api.html#echarts.getMap) | `ECharts.getMap(name)` | 返回 `GeoMapForUser?` |
| [echarts.dispose](https://echarts.apache.org/zh/api.html#echarts.dispose) | `echarts.dispose(chart)` 或 `chart.dispose()` | 当前模块入口接收 chart，不是 Web 的 DOM 重载 |

### 实例方法

| 官方 Web API | 当前 Swift 写法 | 差异或注意事项 |
|---|---|---|
| [setOption](https://echarts.apache.org/zh/api.html#echartsInstance.setOption) | `chart.setOption(option)` | 默认合并已有配置 |
| `setOption(option, true)` | `chart.setOption(option, notMerge: true)` | 重新建立配置；切换互不相关的图表时可使用 |
| `setOption(option, { lazyUpdate, silent, replaceMerge })` | **当前没有对应的公开重载** | 不要把这些参数放入 option 根部来模拟；它们属于调用参数 |
| [getOption](https://echarts.apache.org/zh/api.html#echartsInstance.getOption) | `chart.getOption()` | 返回 `ECUnitOption?`，即当前合并后的配置；组件可能已被规范化为数组 |
| [getWidth / getHeight](https://echarts.apache.org/zh/api.html#echartsInstance.getWidth) | `chart.getWidth()` / `chart.getHeight()` | `Double`，原生视图逻辑尺寸 |
| [resize](https://echarts.apache.org/zh/api.html#echartsInstance.resize) | `chart.resize()` 或 `chart.resize(opts)` | `opts` 为 `ZRenderResizeOpt`；未指定尺寸时读取 host.bounds |
| [on](https://echarts.apache.org/zh/api.html#echartsInstance.on) | `chart.on("click") { params in … }` | 回调参数为 `ECEventParams`；也有 query 重载 |
| [off](https://echarts.apache.org/zh/api.html#echartsInstance.off) | `chart.off("click")` / `chart.off()` | 当前不能像 Web 一样按某一个 closure 移除监听 |
| [dispatchAction](https://echarts.apache.org/zh/api.html#echartsInstance.dispatchAction) | `chart.dispatchAction(payload)` | 使用 `Payload`，动态字段放在 `payload.other` |
| [convertToPixel / convertFromPixel](https://echarts.apache.org/zh/api.html#echartsInstance.convertToPixel) | `chart.ec.convertToPixel(finder, value)` / `chart.ec.convertFromPixel(finder, point)` | 当前位于底层引擎；返回 `Any?`，取决于坐标系 |
| [containPixel](https://echarts.apache.org/zh/api.html#echartsInstance.containPixel) | `chart.ec.containPixel(finder, point)` | 当前位于底层引擎 |
| [getVisual](https://echarts.apache.org/zh/api.html#echartsInstance.getVisual) | `chart.ec.getVisual(finder, "color")` | 当前位于底层引擎，返回 `Any?` |
| [getZr](https://echarts.apache.org/zh/api.html#echartsInstance.getZr) | `chart.getZr()` | 访问原生 ZRender 实例 |
| [clear](https://echarts.apache.org/zh/api.html#echartsInstance.clear) | `chart.setOption(["series": [Any]()], notMerge: true)` | `EChartsView` 尚无 `clear()`；此写法通过 host 绑定清空并同步画面 |
| [appendData](https://echarts.apache.org/zh/api.html#echartsInstance.appendData) | `chart.ec.appendData(seriesIndex: 0, data: rows)`，随后 `chart.syncAfterAction()` | 当前使用同步更新回退，不代表 Web 的渐进任务调度已完整移植 |
| [dispose / isDisposed](https://echarts.apache.org/zh/api.html#echartsInstance.dispose) | `chart.dispose()` / `chart.isDisposed()` | 销毁后不再使用；需要时重新初始化 |

常规更新使用 `chart.setOption`、`chart.dispatchAction`、`chart.resize`，让视图与引擎一起同步。不要用 `chart.ec.setOption` 代替这些绑定入口。

### 初始化参数

| Web `init` 参数 | Swift 对应 |
|---|---|
| `dom` | `NativeChartHost`，其内部连接原生输入、图层和帧时钟 |
| `theme: string \| object` | 第二个参数传 `String` 或 `[String: Any]`，不指定时传 `nil` |
| `opts.renderer` | `EChartsInitOpts.renderer`；原生 `CanvasRenderer` 注册为 `"canvas"` |
| `opts.width / height` | `Double?`；省略时取 host 尺寸，不接受 CSS 字符串或 `"auto"` |
| `opts.devicePixelRatio` | `Double?`；省略时取 host 所在屏幕的比例 |
| `opts.locale` | `Any?`；可传 `"ZH"`、`"EN"` 或当前实现接受的语言字典 |
| `opts.useDirtyRect / ssr` | 字段存在，但不能据此推断 Web 脏矩形绘制或 SVG 服务端导出已经可用 |

实现入口：[EChartsModule.swift](Sources/EChartsKit/core/EChartsModule.swift)、[EChartsView.swift](Sources/EChartsKit/core/EChartsView.swift)。

## Option 对应规则

### 保留字段名称和层级

Swift 仍使用官方的 `title`、`legend`、`tooltip`、`xAxis`、`series`、`itemStyle`、`encode` 等名称，大小写和嵌套关系保持一致。可以从 [官方配置项手册](https://echarts.apache.org/zh/option.html) 查字段，再按下表转换数据表示。

| JavaScript / JSON | Swift |
|---|---|
| `{ key: value }` | `["key": value] as [String: Any]` |
| 空对象 `{}` | `[:] as [String: Any]` |
| 数组 `[]` | 有明确元素类型的 `[]`，如 `[Any]()` 或 `[[String: Any]]()` |
| 对象数组 `[{…}, {…}]` | `[[String: Any]]`；多个 series / axis / dataZoom 保留数组结构 |
| `number` | 数据、坐标、尺寸优先使用 `Double`，如 `18.0`；不要依赖所有内部路径都能把 `Int` 自动转换 |
| `true / false` | `Bool` |
| `"60%"`、`"center"`、`"category"` | 原样保留为 `String`；含义仍由对应 option 字段决定 |
| 对象中省略的属性 / `undefined` | 不放入字典；`option["key"] = nil` 是删除键 |
| 显式 `null` | `NSNull()`；是否允许空值取决于具体字段，不能与“省略属性”一概等同 |
| `function (…) { … }` | 明确类型的 Swift closure；不能通过 JSON 携带函数 |

`ECUnitOption` 是动态字典，并非覆盖所有官方配置的强类型 Builder。字典能够装入某个键，不代表该配置已经实现。建议给复杂子对象显式标注 `[String: Any]`、给混合表格标注 `[[Any]]`，避免 Swift 推导出不合适的类型或出现过慢的类型检查。

### 数据项与样式

裸数值和带样式的对象数据都遵循官方的 `series.data` 结构，例如：

```swift
let styledData: [Any] = [
    18.0,
    ["value": 26.0, "itemStyle": ["color": "#ee6666"]] as [String: Any],
    21.0
]
```

颜色在 option 中优先使用官方形式的颜色字符串，不直接塞入 `UIColor` / `NSColor`。缺失点按相应 series 文档处理；例如折线缺失值及 `connectNulls` 见 [series-line.data](https://echarts.apache.org/zh/option.html#series-line.data) 与 [connectNulls](https://echarts.apache.org/zh/option.html#series-line.connectNulls)。

### Dataset 与 encode

数据表使用 `[[Any]]`，维度名和 `encode` 保留原名：

```swift
let source: [[Any]] = [
    ["month", "sales", "cost"],
    ["一月", 18.0, 11.0],
    ["二月", 26.0, 16.0],
    ["三月", 21.0, 13.0]
]
let datasetOption: [String: Any] = [
    "dataset": ["source": source],
    "legend": [:] as [String: Any],
    "xAxis": ["type": "category"],
    "yAxis": ["type": "value"],
    "series": [
        ["name": "销量", "type": "bar", "encode": ["x": "month", "y": "sales"]] as [String: Any],
        ["name": "成本", "type": "line", "encode": ["x": "month", "y": "cost"]] as [String: Any]
    ]
]
```

官方参考：[数据集](https://echarts.apache.org/handbook/zh/concepts/dataset/)、[dataset.source](https://echarts.apache.org/zh/option.html#dataset.source)、[series.encode](https://echarts.apache.org/zh/option.html#series-bar.encode)。本地参考：[dataset 示例](Sources/EChartsDemoCore/Demos/official-dataset-simple0.swift)。

### Formatter 与 Swift closure

字符串模板仍可使用，如 `label.formatter: "{b}: {c}"`。函数形式需要使用实现所接受的 Swift 参数和返回类型，不能把 JavaScript 函数字符串作为 formatter。

```swift
let labelFormatter: (CallbackDataParams) -> String = { params in
    "\(params.name): \(params.value)"
}
let formattedPieOption: [String: Any] = [
    "series": [[
        "type": "pie",
        "label": ["show": true, "formatter": labelFormatter] as [String: Any],
        "data": [
            ["name": "A", "value": 32.0] as [String: Any],
            ["name": "B", "value": 68.0] as [String: Any]
        ]
    ] as [String: Any]]
]
```

`tooltip.formatter` 需要区分单个数据项与一组轴数据。当前 `TooltipCallbackDataParams` 是 `CallbackDataParams` 的类型别名，因此上面的单参数 closure 也可用于 item tooltip；axis tooltip 则需要接收数组。完整的三参数形式保留 ticket 与异步 callback，例如：

```swift
let axisTooltipFormatter: TooltipFormatterCallback<[TooltipCallbackDataParams]> = { items, _, _ in
    items.map { "\($0.seriesName ?? ""): \($0.value)" }.joined(separator: "\n")
}
let axisTooltip: [String: Any] = [
    "trigger": "axis",
    "formatter": axisTooltipFormatter
]
```

将 `axisTooltip` 放到 option 的 `"tooltip"` 键下即可。具体签名见 [types.swift](Sources/EChartsKit/util/types.swift) 和 [TooltipView.swift](Sources/EChartsKit/component/tooltip/TooltipView.swift)。

原生 tooltip 使用 `richText` 内容，不能返回 `HTMLElement`，也不能直接依赖 HTML、CSS 或 DOM。官方参考：[tooltip.formatter](https://echarts.apache.org/zh/option.html#tooltip.formatter)、[富文本标签](https://echarts.apache.org/handbook/zh/how-to/label/rich-text/)。

### 从 JSON 读取配置

纯数据配置可以来自 Bundle 或网络。解析后仍调用相同的 `setOption`：

```swift
@MainActor
func applyJSON(_ data: Data, to chart: EChartsView) throws {
    let object = try JSONSerialization.jsonObject(with: data)
    guard let option = object as? [String: Any] else {
        throw CocoaError(.propertyListReadCorrupt)
    }
    chart.setOption(option)
}
```

JSON 中的 `null` 会解析为 `NSNull`。闭包、原生对象和 JavaScript 表达式不属于 JSON；需要在解析后由 Swift 代码补入。Swift 字典是值类型，修改取出的子字典后，需要写回父字典，再调用 `setOption`，不会自动改变已经显示的图表。

## 各类图表的初始化与配置

**没有分别的 `initLineChart` / `initPieChart`。** 为每个图表创建独立的 host 和 chart，然后传入对应 option：

```swift
@MainActor
func makeSalesChart() throws -> (host: NativeChartHost, chart: EChartsView) {
    try makeNativeChart(option: barOption)
}
```

下表列出当前引擎中已接入的 series 类型、配置入口和本地示例。它是使用索引，**不是所有属性和交互已完整通过 Web 一致性验证的清单**。

| 图表 | `series.type` 与主要配置 | 官方文档 | 本地配置示例 |
|---|---|---|---|
| 折线 / 面积 | `line`；xAxis、yAxis；面积增加 areaStyle | [line](https://echarts.apache.org/zh/option.html#series-line) | [line-basic](Sources/EChartsDemoCore/Demos/line-basic.swift) |
| 柱状 / 条形 | `bar`；xAxis、yAxis；横向时交换分类轴 | [bar](https://echarts.apache.org/zh/option.html#series-bar) | [bar-basic](Sources/EChartsDemoCore/Demos/bar-basic.swift) |
| 象形柱图 | `pictorialBar`；坐标轴、symbol | [pictorialBar](https://echarts.apache.org/zh/option.html#series-pictorialBar) | [pictorialBar-dotted](Sources/EChartsDemoCore/Demos/official-pictorialBar-dotted.swift) |
| 散点 | `scatter`；坐标轴、二维 data | [scatter](https://echarts.apache.org/zh/option.html#series-scatter) | [scatter-basic](Sources/EChartsDemoCore/Demos/scatter-basic.swift) |
| 涟漪散点 | `effectScatter`；坐标系、rippleEffect | [effectScatter](https://echarts.apache.org/zh/option.html#series-effectScatter) | [effectscatter-basic](Sources/EChartsDemoCore/Demos/effectscatter-basic.swift) |
| 饼图 / 环图 | `pie`；name/value 数据、radius | [pie](https://echarts.apache.org/zh/option.html#series-pie) | [pie-basic](Sources/EChartsDemoCore/Demos/pie-basic.swift) |
| 漏斗图 | `funnel`；name/value 数据 | [funnel](https://echarts.apache.org/zh/option.html#series-funnel) | [funnel-basic](Sources/EChartsDemoCore/Demos/funnel-basic.swift) |
| 仪表盘 | `gauge`；value、min/max | [gauge](https://echarts.apache.org/zh/option.html#series-gauge) | [gauge-basic](Sources/EChartsDemoCore/Demos/gauge-basic.swift) |
| K 线 | `candlestick`；分类轴、四元组 data | [candlestick](https://echarts.apache.org/zh/option.html#series-candlestick) | [candlestick-basic](Sources/EChartsDemoCore/Demos/candlestick-basic.swift) |
| 箱线图 | `boxplot`；分类轴、五数概括 data | [boxplot](https://echarts.apache.org/zh/option.html#series-boxplot) | [boxplot-basic](Sources/EChartsDemoCore/Demos/boxplot-basic.swift) |
| 雷达图 | `radar`；radar.indicator、value 数组 | [radar](https://echarts.apache.org/zh/option.html#series-radar) | [radar-basic](Sources/EChartsDemoCore/Demos/radar-basic.swift) |
| 热力图 | `heatmap`；坐标系、visualMap | [heatmap](https://echarts.apache.org/zh/option.html#series-heatmap) | [heatmap-basic](Sources/EChartsDemoCore/Demos/heatmap-basic.swift) |
| 树图 | `tree`；树根与 children | [tree](https://echarts.apache.org/zh/option.html#series-tree) | [tree-basic](Sources/EChartsDemoCore/Demos/tree-basic.swift) |
| 矩形树图 | `treemap`；层级 name/value/children | [treemap](https://echarts.apache.org/zh/option.html#series-treemap) | [treemap-basic](Sources/EChartsDemoCore/Demos/treemap-basic.swift) |
| 旭日图 | `sunburst`；层级数据、radius | [sunburst](https://echarts.apache.org/zh/option.html#series-sunburst) | [sunburst-basic](Sources/EChartsDemoCore/Demos/sunburst-basic.swift) |
| 关系图 | `graph`；data、links/edges、layout | [graph](https://echarts.apache.org/zh/option.html#series-graph) | [graph-basic](Sources/EChartsDemoCore/Demos/graph-basic.swift) |
| 桑基图 | `sankey`；data 与带 value 的 links | [sankey](https://echarts.apache.org/zh/option.html#series-sankey) | [sankey-basic](Sources/EChartsDemoCore/Demos/sankey-basic.swift) |
| 和弦图 | `chord`；data、links | [chord](https://echarts.apache.org/zh/option.html#series-chord) | [chord-basic](Sources/EChartsDemoCore/Demos/chord-basic.swift) |
| 线 / 航线 | `lines`；coordinateSystem、coords | [lines](https://echarts.apache.org/zh/option.html#series-lines) | [lines-basic](Sources/EChartsDemoCore/Demos/lines-basic.swift) |
| 地图 | `map`；先 registerMap，再指定 map 名称 | [map](https://echarts.apache.org/zh/option.html#series-map) | [map-basic](Sources/EChartsDemoCore/Demos/map-basic.swift) |
| 平行坐标 | `parallel`；parallelAxis、维度数据 | [parallel](https://echarts.apache.org/zh/option.html#series-parallel) | [parallel-basic](Sources/EChartsDemoCore/Demos/parallel-basic.swift) |
| 主题河流 | `themeRiver`；singleAxis、时间/数值/名称 | [themeRiver](https://echarts.apache.org/zh/option.html#series-themeRiver) | [themeriver-basic](Sources/EChartsDemoCore/Demos/themeriver-basic.swift) |
| 自定义系列 | `custom`；Swift renderItem closure | [custom](https://echarts.apache.org/zh/option.html#series-custom) | [custom-basic](Sources/EChartsDemoCore/Demos/custom-basic.swift) |

极坐标、日历和地理坐标系不是独立的 series 类型，需要与合适的 series 配合。参见本地 [polar](Sources/EChartsDemoCore/Demos/polar-basic.swift)、[calendar](Sources/EChartsDemoCore/Demos/calendar-basic.swift)、[geo](Sources/EChartsDemoCore/Demos/geo-basic.swift) 示例，以及官方 [polar](https://echarts.apache.org/zh/option.html#polar)、[calendar](https://echarts.apache.org/zh/option.html#calendar)、[geo](https://echarts.apache.org/zh/option.html#geo) 配置。

### 折线与面积图

```swift
let lineOption: [String: Any] = [
    "xAxis": ["type": "category", "data": ["一月", "二月", "三月"]] as [String: Any],
    "yAxis": ["type": "value"],
    "series": [[
        "id": "trend", "type": "line", "smooth": true,
        "data": [18.0, 26.0, 21.0],
        "areaStyle": [:] as [String: Any]
    ] as [String: Any]]
]
```

去掉 `areaStyle` 即为普通折线图。多条线的 `series` 使用数组；堆叠系列通过相同的 `stack` 名称关联。官方参考：[基础折线](https://echarts.apache.org/handbook/zh/how-to/chart-types/line/basic-line/)、[areaStyle](https://echarts.apache.org/zh/option.html#series-line.areaStyle)。

### 散点图

```swift
let scatterOption: [String: Any] = [
    "xAxis": ["type": "value"],
    "yAxis": ["type": "value"],
    "series": [[
        "type": "scatter", "symbolSize": 12.0,
        "data": [[1.0, 8.0], [2.0, 5.0], [3.0, 11.0]]
    ] as [String: Any]]
]
```

每个点同时携带 x、y 数值。官方参考：[基础散点图](https://echarts.apache.org/handbook/zh/how-to/chart-types/scatter/basic-scatter/)。

### 饼图与环图

```swift
let pieOption: [String: Any] = [
    "tooltip": ["trigger": "item"],
    "legend": [:] as [String: Any],
    "series": [[
        "type": "pie", "radius": ["40%", "70%"],
        "data": [
            ["name": "直接访问", "value": 45.0] as [String: Any],
            ["name": "搜索", "value": 35.0] as [String: Any],
            ["name": "其他", "value": 20.0] as [String: Any]
        ]
    ] as [String: Any]]
]
```

将 `radius` 改成 `"70%"` 即为实心饼图，不需要 xAxis/yAxis。官方参考：[基础饼图](https://echarts.apache.org/handbook/zh/how-to/chart-types/pie/basic-pie/)、[radius](https://echarts.apache.org/zh/option.html#series-pie.radius)。

### K 线与缩放

```swift
let candleOption: [String: Any] = [
    "tooltip": ["trigger": "axis"],
    "xAxis": ["type": "category", "data": ["09-01", "09-02", "09-03"]] as [String: Any],
    "yAxis": ["type": "value", "scale": true] as [String: Any],
    "dataZoom": [
        ["type": "inside", "start": 0.0, "end": 100.0] as [String: Any],
        ["type": "slider", "start": 0.0, "end": 100.0] as [String: Any]
    ],
    "series": [[
        "type": "candlestick",
        "data": [[20.0, 24.0, 18.0, 26.0],
                 [24.0, 22.0, 21.0, 28.0],
                 [22.0, 27.0, 20.0, 29.0]]
    ] as [String: Any]]
]
```

每条 K 线的顺序是 **`[open, close, lowest, highest]`**，不是常见数据源中的 `[open, high, low, close]`。官方参考：[candlestick.data](https://echarts.apache.org/zh/option.html#series-candlestick.data)、[dataZoom-inside](https://echarts.apache.org/zh/option.html#dataZoom-inside)、[dataZoom-slider](https://echarts.apache.org/zh/option.html#dataZoom-slider)。

### 雷达图

```swift
let radarOption: [String: Any] = [
    "radar": ["indicator": [
        ["name": "速度", "max": 100.0] as [String: Any],
        ["name": "容量", "max": 100.0] as [String: Any],
        ["name": "稳定性", "max": 100.0] as [String: Any]
    ]],
    "series": [["type": "radar", "data": [
        ["name": "方案 A", "value": [75.0, 60.0, 90.0]] as [String: Any]
    ]] as [String: Any]]
]
```

`value` 顺序与 `radar.indicator` 对应。官方参考：[radar.indicator](https://echarts.apache.org/zh/option.html#radar.indicator)、[series-radar](https://echarts.apache.org/zh/option.html#series-radar)。

### 树图、矩形树图与旭日图

```swift
let rootNode: [String: Any] = [
    "name": "总量", "value": 30.0,
    "children": [
        ["name": "A", "value": 12.0] as [String: Any],
        ["name": "B", "value": 18.0] as [String: Any]
    ]
]
let treeOption: [String: Any] = [
    "series": [["type": "tree", "data": [rootNode], "orient": "LR"] as [String: Any]]
]
let treemapOption: [String: Any] = [
    "series": [["type": "treemap", "data": [rootNode]] as [String: Any]]
]
let sunburstOption: [String: Any] = [
    "series": [["type": "sunburst", "data": [rootNode]] as [String: Any]]
]
```

三者共享层级数据表示，但各自的布局与交互配置不同，不能把某一种图的全部 option 原样套给另一种。官方参考：[tree.data](https://echarts.apache.org/zh/option.html#series-tree.data)、[treemap.data](https://echarts.apache.org/zh/option.html#series-treemap.data)、[sunburst.data](https://echarts.apache.org/zh/option.html#series-sunburst.data)。

### 地图：先注册资源

准备一个有效的 `regions.geojson`，加入应用 Bundle。地图名称是注册表中的键，数据项的 `name` 应与 GeoJSON 区域名称对应。

```swift
@MainActor
func applyMap(geoJSONData: Data, to chart: EChartsView) throws {
    let geoJSON = try JSONSerialization.jsonObject(with: geoJSONData)
    ECharts.registerMap("regions", geoJSON)
    chart.setOption([
        "series": [[
            "type": "map", "map": "regions", "roam": true,
            "data": [["name": "Region A", "value": 42.0] as [String: Any]]
        ] as [String: Any]]
    ], notMerge: true)
}
```

地图资源不会因为写入 `map: "regions"` 而自动下载。官方参考：[registerMap](https://echarts.apache.org/zh/api.html#echarts.registerMap)、[series-map.map](https://echarts.apache.org/zh/option.html#series-map.map)。

### 自定义系列：renderItem

```swift
let renderItem: CustomSeriesRenderItem = { _, api in
    guard let x = api.value(0.0, nil) as? Double,
          let y = api.value(1.0, nil) as? Double else { return nil }
    let point = api.coord([x, y], nil)
    guard point.count >= 2 else { return nil }
    return [
        "type": "circle",
        "shape": ["cx": point[0], "cy": point[1], "r": 6.0],
        "style": ["fill": "#5470c6"]
    ] as [String: Any]
}
let customOption: [String: Any] = [
    "xAxis": ["type": "value"],
    "yAxis": ["type": "value"],
    "series": [[
        "type": "custom", "renderItem": renderItem,
        "data": [[1.0, 8.0], [2.0, 5.0], [3.0, 11.0]]
    ] as [String: Any]]
]
```

`CustomSeriesRenderItem` 返回原生实现可识别的图形描述或 `nil`。这里的数据使用 `Double`；如果自己的数据来源混有其他数字类型，需要在 closure 内明确转换。官方参考：[custom.renderItem](https://echarts.apache.org/zh/option.html#series-custom.renderItem)、[renderItem.api](https://echarts.apache.org/zh/option.html#series-custom.renderItem.api)。

## 数据更新与事件

### 更新现有系列

为需要更新的系列指定稳定的 `id`，后续传入局部配置：

```swift
@MainActor
func updateSales(_ chart: EChartsView) {
    chart.setOption([
        "series": [["id": "sales", "data": [22.0, 30.0, 25.0]] as [String: Any]]
    ])
}
```

如果要把现有图表完整切换为饼图，使用 `chart.setOption(pieOption, notMerge: true)`。默认合并并不等于删除所有没写进新 option 的旧系列；当前也没有公开的 `replaceMerge` 重载。

异步获取数据后回到主线程更新，不要在每次数据变化时重新 init。官方参考：[setOption](https://echarts.apache.org/zh/api.html#echartsInstance.setOption)、[动态的异步数据](https://echarts.apache.org/handbook/zh/how-to/data/dynamic-data/)。

### 监听点击与派发行为

```swift
@MainActor
func configureInteractions(_ chart: EChartsView) {
    chart.on("click") { params in
        print(params.seriesName ?? "", params.name ?? "", params.value as Any)
    }

    var highlight = Payload(type: "highlight")
    highlight.other = ["seriesIndex": 0.0, "dataIndex": 1.0]
    chart.dispatchAction(highlight)

    // 不再需要点击监听时：chart.off("click")
}
```

事件名与 action 名沿用官方约定，例如 `click`、`legendselectchanged`、`datazoom` 和 `highlight`。`Payload` 的 `type` 是固定属性，`seriesIndex`、`dataIndex`、`start`、`end` 等按具体 action 放入 `other`。并不是所有官方 action 都已经实现。

官方参考：[事件与行为](https://echarts.apache.org/handbook/zh/concepts/event/)、[dispatchAction](https://echarts.apache.org/zh/api.html#echartsInstance.dispatchAction)、[highlight](https://echarts.apache.org/zh/api.html#action.highlight)。

## 尺寸与生命周期

host 的大小变化后调用 `chart.resize()`，让坐标系、布局和 painter 一起调整。指定尺寸时使用原生参数结构：

```swift
import ZRenderKit

@MainActor
func resizeChart(_ chart: EChartsView, width: Double, height: Double) {
    var size = ZRenderResizeOpt()
    size.width = width
    size.height = height
    chart.resize(size)
}
```

宽高采用 UIKit / AppKit 的逻辑坐标单位；devicePixelRatio 用于后端位图分辨率，不需要应用自行把所有坐标乘以屏幕 scale。Auto Layout / SwiftUI 改变容器尺寸后，仍需通过生命周期回调通知 chart。

在页面永久释放或替换图表实例时调用 `chart.dispose()`。这会解绑 host 的图层和帧时钟，并释放相关图表资源。不要将临时页面隐藏误当作永久销毁；销毁后再次展示需要重新创建实例。

官方参考：[图表容器及大小](https://echarts.apache.org/handbook/zh/concepts/chart-size/)、[resize](https://echarts.apache.org/zh/api.html#echartsInstance.resize)、[dispose](https://echarts.apache.org/zh/api.html#echartsInstance.dispose)。

## 当前兼容边界

- **API 外形接近官方，覆盖范围尚不完整。** `lazyUpdate`、`replaceMerge`、按单个 handler 执行 `off`、跨图表 `connect` 等不能直接照搬 Web 调用。
- **渲染环境不同。** 没有浏览器 DOM、CSS 或 HTML tooltip；`renderer: "canvas"` 表示原生后端，不能据此使用 DOM Canvas 方法或假定存在 SVG 导出。
- **配置支持需要逐项验证。** 常用图表已有实现和示例，但复杂 formatter、组合坐标系、渐进绘制、动画与交互仍可能存在差异。`useDirtyRect` 等字段存在不等于相关优化完整可用。
- **option 是动态字典。** 拼写错误、未实现的字段或不匹配的 closure 类型，不一定能在编译时被发现。遇到问题可对照具体示例、测试和源码中的 `TODO`。
- **性能和像素一致性持续改进。** 仓库保留 Native/Web 对照与交互测试；不能把某个场景通过推广为所有图表都已达到 Web 版本表现。

## 示例与开发

本地 Swift 配置位于 [Sources/EChartsDemoCore/Demos](Sources/EChartsDemoCore/Demos)。官方示例移植通常同时提供 `option` 与 `webOptionJS`，便于对照 Swift 字典和 JavaScript 配置；`webOptionJS` 是对照工具使用的源码，不是原生运行时 API。

```bash
# 获取锁定的官方参考源码与 Web 对照资源
scripts/sync-upstream.sh

# 构建核心模块、运行回归
swift build
swift test

# iOS Simulator 图表示例
scripts/build-echarts-gallery-ios.sh

# macOS 对照 Gallery 还组合了可选 RasterizerPainter
scripts/sync-rasterizer.sh
scripts/build-echarts-gallery.sh
```

应用只使用 NativeRenderer 时，不需要为运行图表下载 Web 对照资源或 RasterizerPainter。更多说明见 [Gallery README](Examples/PainterGallery/README.md)、[开发指南](CLAUDE.md)、[移植规则与类型约定](PORTING.md)、[Oracle](Oracle/README.md)。

官方文档入口：[API](https://echarts.apache.org/zh/api.html)、[配置项](https://echarts.apache.org/zh/option.html)、[使用手册](https://echarts.apache.org/handbook/zh/get-started/)、[官方示例](https://echarts.apache.org/examples/zh/index.html)。若文档页面无法加载，可查阅 Apache 维护的 [API 文档源文件](https://github.com/apache/echarts-doc/tree/master/zh/api) 与 [配置项文档源文件](https://github.com/apache/echarts-doc/tree/master/zh/option)。
