# 迁移状态复审 · 2026-07-27

> 基线：`FIDELITY_AUDIT_2026-07.md`（2026-07-17，480 对文件）· 本次用 20 个 agent 复审 **219 个文件**，其余 261 个结论沿用。
> 评分口径与基线完全一致（忽略值返回/`enum` 命名空间/Optional/PathProxy/protocol+extension/ContiguousArray 等约定差异），因此下表数字可直接相减。

## 1. 总体变化

| 状态 | 2026-07-17 | 2026-07-27 | 变化 |
|---|---:|---:|---:|
| 🟢 parity | 307 | 365 | +58 |
| 🟡 minor | 142 | 98 | -44 |
| 🟠 major | 29 | 11 | -18 |
| 🔴 stub | 2 | 1 | -1 |
| ⚪️ no-upstream（本次新识别，原计入 parity） | 0 | 5 | +5 |
| **合计** | **480** | **480** | |

- 本次复审的 219 个文件平均覆盖率 **94.8%**（基线全库 94.9%）
- 已核实**关闭**的历史 gap：**337** 条；仍**开放**：**176** 条；本次**新发现**：**101** 条
- `PORT-TODO` 标记：363 → **65**

## 2. 方法：为什么只复审 219 个

按基线入库 commit `a6eb67d` 做 git 差分，把 480 对切成四组，只对结论**可能变化**的派 agent：

| 组 | 定义 | 数量 | 处理 |
|---|---|---:|---|
| A | 原非 parity **且改过** | 100 | 13 agent 逐条核实修复是否落地 |
| B | 原 parity **但改过** | 46 | 4 agent 回归检查 |
| C | 原非 parity **且未改** | 73 | 3 agent 核查 gap 是否已被别处间接补齐 |
| D | 原 parity 且未改 | 261 | 不派 agent，结论沿用（双方源码均未变） |

评分硬约束：**禁止依据注释评分**，必须逐函数对照代码本体；发现过期标记单独记为 `STALE-MARKER`。

## 3. 三个重点发现

### 3.1 🔴 `data/Source.swift`：dataset 维度顺序**运行时不确定**（新发现，最严重）

`objectRows` / `keyedColumns` 形态的 dataset 若未显式写 `dimensions`，维度顺序来自 `util.keys()` → `Array(obj.keys)`（`ZRenderKit/Core/util.swift:196`），而 Swift `Dictionary` 用**每进程随机种子**哈希。上游走的是 JS 对象插入顺序。
**后果**：默认 `encode`（dim0→x、dim1→y）可能绑到错误的列，**同一份数据每次运行结果可能不同**。`objectRows` 是 ECharts 官方示例里最常见的 dataset 写法。
已人工核实：`Source.swift:423-428`（keyedColumns，原注释只说"may diverge"，实际是不确定）、`Source.swift:472`（objectRows）。修复需要在 option 构建边界保留 key 顺序，改 `determineSourceDimensions` 内部无解。评级由 minor 上调为 **major / high**。

### 3.2 🟠 44 个文件、57 处**过期注释**

这正是本仓库记录在案的头号 bug 来源：注释写着"未移植/DEFERRED"，底下的代码其实已经移植好了。它会让后续排查绕远路，也会诱导 agent 重复实现。样例：

- `BarView.swift` — Sources/EChartsKit/chart/bar/BarView.swift:44 says "the label block in `updateStyle` is still deferred in this view" but the label block IS implemented at 1085-1109 (getLabelStatesModels + setLabelSty
- `BarView.swift` — BarView.swift:62 repeats "(label block still deferred in this view)" for labelHelper, which is likewise live (getDefaultLabel at 1089, getDefaultInterpolatedLabel at 1108). STALE-MARKER (reverse kind 
- `ChordPiece.swift` — ChordPiece.swift:143 says 'per-state itemStyle (emphasis/blur/select) not wired here yet' but setStatesStylesFromModel(el, itemModel) runs 22 lines below.
- `ChordPiece.swift` — ChordPiece.swift:29 and :36-44 (header import map) still say graphic.updateProps is DEFERRED and that the view 'inlines a minimal NORMAL-state label' — both are now fully wired. Grade from code, not f
- `CustomView.swift` — CustomView.swift:55 lists 'the clipPath handling (doCreateOrUpdateClipPath, group createClipPath)' as DEFERRED while doCreateOrUpdateClipPath is fully implemented at :1387-1416 (only the GROUP-level s
- `CustomView.swift` — CustomView.swift:222-231 says the copyElement/recreate path is 'DEFERRED here' although doesElNeedRecreate + the replaceAt recreate path are live (:1260-1267, :1353-1356); what copyElement actually om
- `CustomView.swift` — CustomView.swift:1279 and :1490 say 'states DEFERRED, no-op' in a file whose states machinery is otherwise fully wired.
- `EffectScatterView.swift` — EffectScatterView.swift:17, :22-23, :83 and :151 all say the matrix coord system is 'not ported', but Sources/EChartsKit/coord/matrix/Matrix.swift exists and is a full coordinate system (CustomView ev

完整 57 条见 `FIDELITY_STATUS_2026-07-27.tsv` 的 `notes` 列。**这是最划算的下一批工作**：纯注释订正，零行为风险。

### 3.3 🟠 B 组回归检查：无真回归，但暴露了基线的漏判

46 个"原本 parity 且被改过"的文件里，30 个仍 parity、5 个实为无上游对应，11 个被下调。逐条看，下调的原因**不是这轮改动弄坏了什么**，而是基线那次把它们判宽了（如 `MapDraw.swift` 的 region-无数据项、投影 stream 裁剪；`EChartsView.swift` `_handleClick` 缺 `dataType`/`isFromClick`）。
即：**没有发现本轮战役引入的回归**（整场战役测试数只增不减、失败数始终停在同样的 6 个基线失败，也印证这一点），但基线的 parity 判定有约 1/4 偏乐观。

## 4. 剩余 major / stub 清单

| 状态 | 覆盖 | 优先级 | 文件 | 原评级 | 主要缺口 |
|---|---:|---|---|---|---|
| major | 78% | high | `EChartsKit/chart/lines/LinesView.swift` | major | only Cartesian2D is rendered: the `guard let coord = coordinateSystem as? Cartesian2D` at :150 drops geo and p… |
| major | 88% | high | `EChartsKit/component/helper/MapDraw.swift` | parity | Map-series regions with no matching data item lose all styling, labels and hover: _buildGeoJSON sets regionMod… |
| major | 88% | high | `EChartsKit/data/Source.swift` | minor | keyedColumns datasets without explicit 'dimensions': determineSourceDimensions builds dimensionsDefine by iter… |
| major | 60% | medium | `EChartsKit/label/LabelManager.swift` | major | processLabelsOverall + _updateLabelLine are still absent entirely: the per-frame generic label-line pass (setL… |
| major | 75% | medium | `EChartsKit/chart/graph/GraphView.swift` | major | edgeSymbol from/toSymbol arrow markers are still never drawn: edges are built inline as bare ZRenderKit Line/B… |
| major | 78% | medium | `EChartsKit/component/tooltip/TooltipView.swift` | major | tooltip.triggerOn is ignored — _initGlobalListener/globalListener.register is not ported and nothing else read… |
| major | 86% | medium | `EChartsKit/chart/custom/CustomView.swift` | major | `$mergeChildren: 'byName'` (and the deprecated diffChildrenByName) still falls through to the by-index merge (… |
| major | 88% | medium | `EChartsKit/coord/axisModelCreator.swift` | major | registerComponentModel is still a PortStub no-op: the per-axis-type model classes the creator generates are ne… |
| major | 88% | medium | `EChartsKit/core/ECharts.swift` | major | showLoading/hideLoading not ported — the loading-effect registry map exists but is never read, so there is no … |
| major | 89% | medium | `EChartsKit/coord/cartesian/Grid.swift` | major | layOutGridByOuterBounds is still a stub returning noPxChange=true: the grid rect is never shrunk to fit axis l… |
| major | 90% | medium | `EChartsKit/chart/bar/BarView.swift` | major | updateRealtimeAnimation is still a stub (BarView.swift:902-920): upstream splits the layout into an axis-drive… |
| stub | 100% | none | `EChartsKit/component/visualMap/installCommon.swift` | stub | （见 notes） |

> `component/visualMap/installCommon.swift` 仍标 stub，但它**不含可执行代码**——是一份集成说明；agent 已核实它描述的 4 处注册全部由驱动层真实执行（`ECharts.swift:1061/1062/1752/1411`），覆盖率 100%、优先级 none。

## 5. 建议的下一批

1. **`Source.swift` 维度顺序**（high）—— 唯一"结果不可复现"级别的问题，应最先修。
2. **57 处过期注释订正**（零风险，收益高）。
3. **`LinesView.swift`**（high, 78%）—— 只渲染 Cartesian2D，geo/polar lines 直接被丢弃；progressive / updateTransform 均未覆写。
4. **`MapDraw.swift`**（high, 88%）—— 无数据项的 region 丢失全部样式/标签/hover。
5. 其余 medium 档（`LabelManager` 60%、`GraphView` 75%、`TooltipView` 78%、`CustomView` 86%…）按覆盖率排队。

## 6. 逐文件明细

完整 219 行（含每个文件的 fixed / remaining / newGaps / notes）见 **`FIDELITY_STATUS_2026-07-27.tsv`**。
未复审的 261 个文件（原 parity 且两侧源码均未变动）沿用 `FIDELITY_AUDIT_2026-07.md` §5 的结论。
