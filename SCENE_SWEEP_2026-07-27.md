# 交互态结构性对比 · 全局扫描 · 2026-07-27

> 工具：`--scene-manifest` / `--scene-sweep-native` / `--scene-sweep-web` + `scripts/scene-sweep.sh` + `scripts/scene-sweep-report.py`
> 方法：从每个 demo 的**真实 LegendModel** 推导可达的图例开关，写进 manifest；两侧消费**同一份 manifest**，因此收到逐字节相同的 payload——差异必然出在响应，不可能出在激励。
> 对比对象是 z 排序后的**显示列表结构**（type / z / z2 / ignore / silent / transform / shape / style），不是像素。

## 0. 为什么补这一层

`official-chord-simple` 的"点图例数据就错"，在两种既有 oracle 下都是满分：

| 口径 | 结论 |
|---|---|
| 像素 diff（`--compare`） | **0.12%** 通过 |
| 结构 diff，**仅初始帧** | 只报了一个标签 z2 问题 |
| 结构 diff，**图例点击后** | **原生仍画着 3 条 ribbon，上游只剩 2 条；扇区角度与点击前逐位相同（布局没重算）** |

初始帧两侧确实一致——bug 只存在于**状态迁移之后**。交互稳态对比**不需要虚拟时钟**，把它和动画捆在一起推迟是排序错误。

## 1. 扫描规模

| | 值 |
|---|---:|
| demo | 419 |
| 含图例（可推导动作）的 demo | 132 |
| 推导出的动作（每 demo 上限 2） | 249 |
| 每侧 slot（基线 + 动作） | 668 |
| Web 侧成功 | **668 / 668** |
| 原生侧成功 | 664 / 668（**4 个硬崩溃**） |

## 2. 🔴 原生硬崩溃：点击图例直接崩

Swift 无法捕获 `fatalError` / 数组越界，所以 sweep 做成可断点续跑（先落 `.skip` 标记再执行），崩溃点因此可定位：

```
official-graph-circular-layout##1   {"type":"legendToggleSelect","name":"A"}
official-graph-circular-layout##2   {"type":"legendToggleSelect","name":"B"}
official-graph-webkit-dep##1        {"type":"legendToggleSelect","name":"HTMLElement"}
official-graph-webkit-dep##2        {"type":"legendToggleSelect","name":"WebGL"}
```

`Swift/ContiguousArrayBuffer.swift:705: Fatal error: Index out of range`。两个都是 **graph 图表**，都是**图例开关**。这是可用性级别的问题——用户点一下就 crash。

## 3. 交互回归总览

245 个可比对的动作 slot 中：

| 分级 | 数量 |
|---|---:|
| 动作后变差（含属性/顺序差异） | **38** |
| 其中结构性变差（元素数 / 匹配失败） | **18** |
| 其中"**原生比上游多画元素**"（基线元素数还完全一致） | **11** |
| 动作后无变差 | 227 |

按图表族分布（结构性变差的 18 个）：

| 族 | 数量 |
|---|---:|
| chord | 8 |
| custom | 4 |
| tree | 2 |
| data-transform / graph / pie / treemap | 各 1 |

## 4. 🔴 主线故障：**隐藏的系列，图形没被删掉**

基线元素数两侧完全一致、动作后原生多画元素的 slot：

```
+26  official-custom-error-scatter##2      隐藏 "error" 后原生 41 vs 上游 15
+18  official-data-transform-aggregate##1  隐藏 "boxplot" 后 57 vs 39
+18  official-custom-ohlc##1               隐藏 "Dow-Jones index" 后 41 vs 23
+12  official-chord-lineStyle-color##1     54 vs 42
+6   official-chord-style##2 / lineStyle-color##2
+5   official-chord-style##1
+2   official-chord-simple##1 / ##2 / minAngle##1 / ##2
```

已人工核实 `official-custom-error-scatter`：基线 **184/184 完美匹配**，隐藏 "error" 系列后原生仍画着 **18 条 `line`**（误差线），上游只剩 2 条。

chord 族的表现与 `official-chord-simple` 已定位的形态一致：节点被过滤掉了，但**边没有被过滤、布局没有重算**——扇区角度与点击前逐位相同。

## 4b. 根因与修复（2026-07-31）

上面第 2 节的 4 个崩溃和第 4 节 chord 族的全部条目**是同一个根因**。

**链路**：`legendDataFilter` → `getData().filterSelf(...)` → 应触发 `linkSeriesData` 的 `changeInjection` → `struct.update()` → `Graph.update()`（`data/Graph.ts:271`）——后者既重映射每个节点的 `dataIndex`，也执行
`edgeData.filterSelf(edge => edge.node1.dataIndex >= 0 && edge.node2.dataIndex >= 0)`。

**断点**：插桩显示 `legendDataFilter` 拿到的 `SeriesData` 上 `inj=[]`——注入是空的。`Graph.update()` 全程只在建图时触发过一次。

上游 `transferProperties`（`SeriesData.ts:1456-1465`）会把 `source.__wrappedMethods` 里每个名字对应的**包装函数本身**复制到克隆体，所以克隆的 `filterSelf` 仍然带着整条 wrap 链。移植把注入存在旁路表里，而 `transferProperties` 没有复制它——偏偏 `legendDataFilter` 过滤的 `seriesModel.getData()` 在数据任务跑完后**正是一个克隆**。

代码里原有的 KNOWN DIVERGENCE 注释断言这条路径"不可达"，该断言是错的。

**修复**（`data/SeriesData.swift`）：在 `transferProperties` 中复制 CHANGABLE_METHODS（`filterSelf`/`selectRange`）的注入。仅限这两个是因为 `changeInjection` **与接收者无关**（只调 `opt.struct.update()`），复制后行为与上游一致；而 TRANSFERABLE 那组的 `transferInjection` 会分支于 `isMainData(this)`，移植的闭包捕获的是注册时那个 list，照搬会指向错误的对象——故意留着，并在注释里写明了前置条件。

回归测试：`Tests/EChartsKitTests/ZZGraphStructLegendFilterTests.swift`。

**效果**（复用未变的 Web dump，仅重跑原生侧）：

| 指标 | 修复前 | 修复后 |
|---|---:|---:|
| 原生硬崩溃 | 4 | **0** |
| 结构性交互回归 | 18 | **9** |
| "原生比上游多画元素" | 11 | **3** |
| 新增回归 | — | **0** |
| 单元测试 | 810 / 6 基线失败 | 812 / 6 基线失败 |

已消除：chord 全部 8 个 slot、`official-graph-label-overlap##1`，以及两个 graph demo 的崩溃。
`official-chord-simple##1` 现在 **20/20 完全匹配、零 unmatched**（仅剩已知的标签 z2 绘制顺序问题，基线同样存在）。

**残留的 3 个"多画元素"**（`official-custom-error-scatter##2`、`official-custom-ohlc##1`、`official-data-transform-aggregate##1`）是**另一个根因**：custom 系列 / boxplot 的 renderItem 产物在过滤后没有被回收，与 Graph 结构无关。

## 5. 局限（必须写清楚，否则数字会被误读）

1. **v1 只覆盖图例开关**。dataZoom、timeline、brush、hover、select 尚未纳入。图例是本次报告的故障类，不是全部交互面。
2. **基线（slot 0）的 "16/419 结构一致" 不是质量指标**。里面混着已知的 oracle 伪影——最典型的是 progressive 渲染：`official-custom-wind` 原生 65600 个元素 vs 上游 2440，上游把大批数据合并成少量批量路径，原生逐点建元素。这类需要一次噪声分诊，和第一版 frame-0 diff 当初一样。**本报告的结论只建立在"动作前后的 delta"上**，delta 天然抵消了两侧共有的基线噪声。
3. **每个 demo 最多取 2 个图例项**（`--scene-manifest <out> [maxPerDemo]` 可调）。所以本报告是**下界**，不是完备枚举。
4. 元素匹配按 `(type, text)` 分桶后在桶内贪心；超过 60 个的同质桶按序配对（65k 元素的图表上全对全匹配不可行）。同质元素的错配不影响元素数与桶级结论。

## 6. 复现

```bash
swift build
swift run EChartsDemoGallery --scene-manifest /tmp/manifest.json 2
./scripts/scene-sweep.sh /tmp/manifest.json /tmp/sweep          # 原生，跨崩溃续跑
swift run EChartsDemoGallery --scene-sweep-web /tmp/manifest.json /tmp/sweep
python3 scripts/scene-sweep-report.py /tmp/sweep /tmp/manifest.json --top 25
```

单个用例：

```bash
A='{"type":"legendToggleSelect","name":"A"}'
swift run EChartsDemoGallery --scene-native official-chord-simple /tmp/n.json "$A"
swift run EChartsDemoGallery --scene-web    official-chord-simple /tmp/w.json "$A"
python3 scripts/scene-diff.py /tmp/n.json /tmp/w.json
```

`--scene-web <demo> <out> <probe.js>`（第三参不以 `{` 开头时）把 dump 换成任意脚本，用于直接探测参考实现——上游 TS 源码回答不了的问题（"这个 z2=4 是哪来的"）用它一次就能问清楚。
