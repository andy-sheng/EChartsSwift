# Native / Web 性能优化实施记录

日期：2026-09-06。实现基于 `c6b15b51a78a5a52fa315e28117a1e4eaee8c572`，对应 [技术方案](native-web-performance-plan.md)。

当前完成 P0 的 CPU 基准设施、P1 的数值存储与大数据布局切片、P3 的路径缓存及不透明大柱图绘制优化。50 万柱图滚轮 CPU 中位耗时下降约 28%，4 万散点下降约 18%。**尚未达到 Web 性能门槛；P0–P5 整体未完成。** GPU、RasterizerPainter 和线程模型未变。

## 已实现

### 数值存储和布局

- `DataStore` 的 float/time 列使用 `ContiguousArray<Double>`，int 列使用 `ContiguousArray<Int32>`；ordinal/number 保留异构值。集中实现 Int32 截断、回绕及 NaN/Infinity 转换，保留原始值参与 extent 计算的上游语义。
- `getNumeric` 直接读取数值列。过滤、范围统计、采样和 bar/scatter 的数值热路径减少 `Any` 装箱/拆箱；自定义 provider 的原公开接口保留兼容桥接。
- `linearMap`、Axis 的 band extent、Cartesian2D 数值坐标转换和大柱图局部临时变量使用二元 SIMD 值，避免逐点创建短数组。extent 与 scale 仍读取当前状态。
- scatter 仅在双数值列、Cartesian2D、typed layout 分支使用专用路径；原始 ordinal 字符串等继续走通用路径。保留既有 Float32 量化边界、原始索引与数据数量，未引入降采样或修改官方配置。

代码入口：[DataStore](../Sources/EChartsKit/data/DataStore.swift)、[barGrid](../Sources/EChartsKit/layout/barGrid.swift)、[points](../Sources/EChartsKit/layout/points.swift)、[Cartesian2D](../Sources/EChartsKit/coord/cartesian/Cartesian2D.swift)。

### Core Graphics

- 新增 Painter 持有的 [CGGeometryCache](../Sources/ApplePainterSupport/CGGeometryCache.swift)，跨帧复用不可变 CGPath，并共享给 clip 和 incremental 离屏绘制。缓存弱引用 PathProxy，不保留 scene 或 CGContext。
- 缓存检查对象身份、版本、有效长度、strokePercent、简化阈值和命令快照；即使 `setData` 未递增版本也会失效。默认最多 2,048 项、1,000,000 个命令数值，FIFO 有界淘汰；clear/dispose 清空。
- 大柱图通过渲染语义 hook 标明 compound rectangles。仅纯色、不透明、无 shadow、source-over 的矩形采用每组 32 个的 `CGContext.fill(rects)`，减少密集重叠柱的绘制成本。无效数值不会使整组有效柱丢失，尾组照常绘制。
- scatter 保留逐点透明度叠加；半透明或不符合条件的绘制沿用现有路径。未将整条大 series 合并成超大的 CGPath。

代码入口：[CGRenderer](../Sources/ApplePainterSupport/CGRenderer.swift)、[CGSceneRenderer](../Sources/ApplePainterSupport/CGSceneRenderer.swift)、[CALayerPainter](../Sources/NativePainter/CALayerPainter.swift)、[LargeBarPath](../Sources/EChartsKit/chart/bar/LargeBarPath.swift)。

这些修改保留 Painter 边界。主体逻辑的数值优化可被未来 GPU Painter 复用；CGPath 缓存只属于 Apple 后端，不成为核心数据表示。

## 实测

同一台 macOS 主机，Release 原生二进制、真实 WKWebView 内运行固定本地 ECharts。640 × 420、DPR 2，坐标 `(320, 100)`，五次 delta=1 滚轮事件，间隔 150 ms；每个变体两轮，共 10 个输入样本。各轮串行，保留优化前二进制及 SHA256。

表中单位为 ms，指标是滚轮 Handler 处理加同步 flush 的 **CPU 提交耗时 P50**，不包含显示器呈现完成。不能换算为实际 FPS 或 input-to-present latency。样本量较小，收益代表本次测量。当前探针首次输入等待 Native 为 150 ms、Web 为 300 ms，此后的输入间隔均为 150 ms；Native 前后版本使用相同等待。本轮 Web 数值用于定位差距，严格性能门禁仍需统一预热、动画逻辑时间和呈现测量。

| 用例 | 优化前 Native | 当前 Native | Web | Native 降幅 |
|---|---:|---:|---:|---:|
| 50 万柱图 | 873.05 | 629.01 | 167.00 | 28.0% |
| 4 万散点 | 55.94 | 46.13 | 24.00 | 17.5% |
| K 线及 4 条 MA | 38.94 | 37.41 | 26.00 | 3.9% |

K 线变化较小，暂不认定有显著性能收益。三例当前均慢于 Web。

大柱图阶段 P50：事件处理 `404.73 → 342.62 ms`，Painter 绘制 `468.25 → 286.33 ms`；Web 分别约 `82 / 85 ms`。分项中位数不要求相加等于总体中位数。强制无变化刷新仍约 `240.59 ms`，说明保留层和 dirty 管理仍是缺口，路径缓存没有解决全层重复绘制。

基准对每个输入核对全部 series 的数据量及两个 authored dataZoom 范围，全部通过。Native 另有 toolbox 自动生成的 dataZoom，未把该门禁描述为全部模型一致。Web repaint 的 0 ms 属于当前计时分辨率下结果，不用于计算加速倍数。

证据：[汇总 JSON](../build/performance-implementation-20260906/benchmark-batched/summary.json)、[运行日志](../build/performance-implementation-20260906/benchmark-batched.log)。原始 JSONL、stderr、二进制路径与 SHA256 在同目录中，`build/` 不纳入版本控制。

固定上游：ECharts `20ecdf4cae568f31d350a1c547516d08cdcab9b0`；ZRender `349111033fba0fa08cee745b72dd2ea66dc6fcaa`。

## 验证

完整 Swift 测试：**1022 项执行，58 项跳过，0 失败**。新增回归覆盖 typed store 的混合/空值、Int32、复制隔离、过滤原始索引、append；坐标轴变化与通用路径等价；CGPath 版本及非版本失效、弱所有权、缓存边界、clip/transform 像素；矩形透明叠加、子像素边缘、无效数据和尾组。跳过项不计为通过。

日志：[full-tests-final.log](../build/performance-implementation-20260906/full-tests-final.log)。Gallery Debug 构建通过；性能探针 Release 构建通过。

交互场景由 category manifest 补充为三个持久 JSON，并执行现有 K 线 rapid-wheel 场景。每例均在同一实例完成输入；最终两轮为 `visual-run5`、`visual-run6`，共 76 对 Native/Web 截图。最终 resolved 均无 missingTarget，数据量及已记录的拖拽范围一致。滑块操作实际命中起始手柄，改变左端点，不是整体平移窗口。

| 场景 | 覆盖 | 最终独立视觉结论 |
|---|---|---|
| bar-large | 五次滚轮、起始手柄拖动/逆拖、逆滚轮恢复 | 两轮 pass；每侧恢复与基线一致 |
| scatter-large | 两类 hover 与清理、两个 legend 开关、滚轮、手柄和恢复 | 两轮 pass |
| candlestick performance | 三类 hover、四条 MA legend、滚轮、手柄和恢复 | fail：`01-hover-series-0` tooltip 位置不一致，Web 顶部截切；其余捕获通过 |
| candlestick rapid-wheel | 五次连续输入，即时/60 ms/180 ms 捕获 | fail：最终 tooltip 数值不同；过渡窗口/几何也不同，精确相位仍 uncertain |

K 线 performance 的基线 MA、图例、滚轮、手柄和恢复均通过；每侧恢复帧与基线一致。rapid-wheel 最终各系列均为 153 项，窗口和系列几何一致，但相同日期 `2015/6/19` 的 tooltip 显示不同 OHLC/MA 值。两轮 K 线对应图像字节相同。持续输入的墙钟捕获不足以证明两侧动画相位一致，不能把这一重复性当作相位门禁通过。上述两场景保留为失败项。

为排查回归，另从 HEAD 导出隔离源码，仅替换为相同的已修正捕获脚本，构建优化前 Gallery 并执行上述两个 K 线场景。优化前后全部 42 张对应 PNG 字节一致，包含失败捕获，说明这些已观察到的差异在优化前同样存在，本次没有改变这些捕获的结果。对照证据：[visual-control](../build/performance-implementation-20260906/visual-control/)、[逐帧比较](../build/performance-implementation-20260906/visual-control-comparison.json)、[隔离构建日志](../build/performance-implementation-20260906/control-build.log)。这不替代完整类别回归，也不把既有差异计为通过。

测试脚本修复：动画完成/采样遍历补充元素附加 clipPath。之前 Web K 线入口裁剪动画未被推进，导致“settle”基线遗漏 MA；修改位于 [InteractionVisual.swift](../Examples/PainterGallery/Sources/EChartsDemoGallery/InteractionVisual.swift)，没有更改官方 demo。清理场景等待实际 tooltip hideDelay 后再捕获，避免把计时差异当成残留。

证据：[语义检查](../build/performance-implementation-20260906/visual-semantic-gates.json)、[最终第一轮](../build/performance-implementation-20260906/visual-run5/)、[最终第二轮](../build/performance-implementation-20260906/visual-run6/)。每个子目录包含 review-request、resolved 和全部原图。

## 复现

```sh
swift test
swift build -c release --product ChartPerformanceProbe
python3 scripts/benchmark-native-web.py --binary .build/release/ChartPerformanceProbe --output build/perf-new-run
```

对比旧版时增加 `--baseline-binary /path/to/previous/ChartPerformanceProbe`，必须使用同配置的 Release 构建。输出目录必须不存在，避免覆盖证据。iOS 与 macOS 使用各自独立 scratch path。

交互捕获沿用仓库脚本；构建 PainterGallery 后以该二进制为 `DEMO_CAPTURE_BINARY`，分别执行 `scripts/capture-interaction-visuals.sh Tests/VisualInteractionScenarios/<scenario>.json build/<new-run>`，重复两轮并独立视觉复核。

## 剩余工作

本轮没有完成 renderTask / Scheduler / `_onframe` 的任务图对齐、通用 layer dirty 或 dirty rectangle、文本缓存、显示时钟替换、不可变帧和后台 CG 消费。当前仍使用原线程模型，优化不会自动消除主线程阻塞。

下一阶段应继续拆解大柱图约 343 ms 的事件热点，完成渐进任务连接；并落实层复用、正确失效与变化区域绘制。dirty rectangle 必须重绘所有相交元素且保持顺序、透明和裁剪，不能只画 dirty 元素。

未执行完整官方类别 sweep、macOS/iOS 全矩阵、真机呈现延迟、GPU 或长期稳定性验收。性能门禁及未通过的视觉项持续保留；当前实现不作为“已对标 Web”的结论。
