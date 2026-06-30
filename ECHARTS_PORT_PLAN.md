# EChartsKit 移植计划 — 极简静态折线/柱状图最小集

> 生成于 2026-06-30。目标:在 ZRenderKit 之上忠实移植 echarts/src/** 的最小子集,
> 足以渲染**静态**折线图 + 柱状图(无动画、无 tooltip/legend/交互)。
> 遵循 `CONVENTIONS.md`(逐文件、保持 upstream 结构以便同步)。

## 边界(已与用户确认)

- **范围**:极简静态。打通 `option → model → coord → data → view → ZRenderKit 出图` 完整管线。
- **砍掉**:动画 diff / universalTransition、tooltip、legend、dataZoom、toolbox、brush、
  axisPointer、label 自动避让、decal、aria、custom series、pie、一切非 cartesian 坐标系
  (polar/parallel/geo/single/matrix/radar/calendar)。
- **起步**:先手工搭 L0 脚手架(定架构 + 类型契约),再用 workflow 逐层并行起草 L1→L5。

## 依赖闭包分析结论

- 全量 echarts src:**596** 文件。
- line+bar install 的纯运行时 import 闭包:**275**(被 `export/option.ts` 的 type-only
  聚合链虚胖:boxplot/geo/graph/polar/parallel/toolbox 等多为 `import type`,Swift 类型擦除
  后不需要)。
- **真实编译必需(剔除假依赖后):约 80–110 文件**。
- 骨架文件很大:`core/echarts.ts` 3434、`SeriesData` 1507、`DataStore` 1346、`Grid` 1075、
  `LineView` 1470、`BarView` 1292。**实打实约 12k–18k 行 Swift**(已砍动画/交互分支)。

## 分层(路径与 upstream 一一对应)

`Sources/EChartsKit/<同 upstream 相对路径>.swift` ↔ `echarts/src/<...>.ts`

### L0 脚手架(手工,~8 文件)— 进行中
定义所有上层依赖的类型契约与注册机制。架构决策,不并行。
- `extension.swift` — `EChartsExtensionInstallRegisters`、`use()`、registers 闭包集
- `core/echarts.swift` — **精简骨架**:`init/setOption/_prepareView/update` 主循环 +
  register* 自由函数 + PRIORITY;砍掉 SVG/进度/交互/动画分支(逐处 PORT-TODO)
- `core/ExtensionAPI.swift`、`core/CoordinateSystem.swift`(协议)、`core/Scheduler.swift`(精简)
- `util/clazz.swift`(registerClass/SubType 机制)、`util/component.swift`
- `view/Chart.swift`、`view/Component.swift`(基类 + registerClass)

### L1 工具 + 数据底座(workflow,~22 文件)— 耦合低,大并行
- `util/{number,model,format,types,layout,log,graphic,states,symbol,clazz,component,innerStore}`
- `data/{Source,DataStore,SeriesData,OrdinalMeta,DataDiffer,SeriesDimensionDefine}`
- `data/helper/{sourceHelper,dataProvider,dimensionHelper,SeriesDataSchema,dataValueHelper,...}`

### L2 模型层(workflow 起草 + 重收口,~15 文件)— 耦合高
- `model/{Model,Component,Series,Global,globalDefault}`
- `model/mixin/{palette,textStyle,itemStyle,lineStyle,areaStyle,makeStyleMapper,boxLayout}`
- `model/{OptionManager,referHelper}`(referHelper 裁剪掉非 cartesian 坐标系校验)

### L3 坐标 + 刻度(workflow,~18 文件)
- `scale/{Scale,Interval,Ordinal,Time,Log,helper,scaleMapper,minorTicks}`
- `coord/{Axis,axisHelper,axisModelCreator,axisDefault,AxisBaseModel,axisTickLabelBuilder,
  CoordinateSystem,scaleRawExtentInfo,axisModelCommonMixin,axisAlignTicks}`
- `coord/cartesian/{Cartesian,Cartesian2D,Axis2D,AxisModel,Grid,GridModel,cartesianAxisHelper}`

### L4 视觉 + 布局(workflow,~10 文件)
- `visual/{style,symbol,helper,VisualMapping?}`
- `layout/{points,barGrid,barCommon}`
- `processor/{dataSample,dataStack}`(按需)

### L5 图表视图(workflow 起草 + 重收口,~25 文件)
- `view/` 已在 L0。`chart/helper/{Symbol,SymbolDraw,Line,LineDraw,LinePath,Polyline,createSeriesData,labelHelper,createClipPathFromCoordSys}`
- `chart/line/{LineSeries,LineView,poly,helper,lineAnimationDiff(精简)}`
- `chart/bar/{BaseBarSeries,BarSeries,BarView}`
- `component/axis/{AxisBuilder,AxisView,CartesianAxisView}`
- `component/grid/{install,installSimple}`、`component/helper/*`(按需)
- `label/labelStyle`(基础)

### L6 渲染桥接(手工,~6 文件)
- `renderer/installCanvasRenderer.swift` → 桥接 ZRenderKit/NativePainter(registerPainter seam)
- `init()` 顶层 API(对接 `ZRender` + `NativePainter`)
- 首个 demo(DemoGallery 里加一个静态折线 + 柱状)

## 里程碑

- **M1**:静态折线出图(L0–L3 核心 + line 链 + L6 桥接)。
- **M2**:柱状图(+ bar 链 + barGrid 布局)。
- **M3**:坐标轴刻度/标签完善(axisTickLabelBuilder、nice ticks、category/value 轴)。

## workflow 编排策略

- L0 手工定架构 → 之后**逐层** workflow:同层并行起草,每 agent 注入
  「该层已定类型上下文 + 对应 TS 源 + CONVENTIONS + 一个已移植 ZRenderKit 文件作风格样例」。
- **每层产出后必有一个串行编译收口回合**(我来,非并行):跨文件类型契约对齐、补 PORT-TODO、
  过编译。
- L1/L3/L4 文件多耦合低,workflow 收益最大;L2/L5 耦合高,起草后人工收口占比更高。

## 测试策略

- 每层 port 后,对照 upstream 的关键算法写单元测试(scale ticks、data 维度、坐标变换)。
- M1/M2 末尾:headless 渲染静态折线/柱状到 PNG,纳入 DemoGallery。
