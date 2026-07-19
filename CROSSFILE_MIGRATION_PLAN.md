# 相互依赖迁移方案（Bun 式）— Cross-File Migration Plan

> 目标：迁移**有相互依赖**的 gap —— 那些"修 A 必须先在 B 里造符号"的部分，lane 隔离方案只能 defer 的 155 条 cross-file gap（来自 106 个消费端文件，指向约 30–40 个共享 provider 符号）。
> 方法：照搬 Bun 的 Zig→Rust 重写流水线（`bun.com/blog/bun-in-rust`），把"逐文件 build-green"换成"**先全量迁移、再把编译错误当工作队列**"，用一份**权威符号表**保证不同 agent 的公开命名一致。

## 0. 为什么 lane 隔离做不了这部分

lane 方案禁止 agent 改本文件以外的东西（防并行冲突），于是任何"需要新造/改共享符号"的修复都被 defer。三个根因：
1. **命名漂移**：agent A 造 `fooBar()`、agent B 期望 `foo_bar()` → 链接不上。
2. **重复创建**：A 和 B 都发现缺同一个 `setLabelValueAnimation` → 两份同名定义 → duplicate symbol。
3. **无法孤立编译**：互相依赖的一组文件，单个拿出来必然编译不过。

Bun 的三把钥匙正好对应：**权威命名表**（治漂移）、**单一 owner + 依赖分层**（治重复创建 & 孤立编译）、**编译错误工作队列**（治"合起来才编译得过"）。

---

## Phase 0 — 权威 Prep 文档（动手前先定、并对抗式评审）

这是整个方案的地基，也是你要的"统一迁移规则"。

### 0a. `PORTING.md` — TS→Swift 机械翻译规则
把 `CONVENTIONS.md` 固化成一页硬规则：Canvas2D→PathProxy、class→protocol+extension、自由函数→`enum <模块名>`、Optional 包裹、`number[]`→`ContiguousArray`、enum 命名空间…… 每条给一个正例。

### 0b. `SYMBOLS.tsv` — 权威符号注册表（= Bun 的 `LIFETIMES.tsv` 对应物）
**每一个被 ≥1 个 cross-file gap 需要的共享符号一行**，是所有 agent 唯一绑定的真相源：

| 列 | 含义 |
|---|---|
| `symbol_id` | 稳定标识（如 `util/throttle.throttle`）|
| `upstream_ts` | 上游出处（`echarts/src/util/throttle.ts`）|
| `swift_name` | **规范 Swift 名 = 上游标识符逐字保留**（camelCase 不改）|
| `owning_file` | **唯一 owner 文件**（只有它能定义该符号）|
| `container` | `enum 命名空间` / `type` / `protocol` / `extension X` |
| `signature` | 确定的 Swift 签名（参数/返回/Optional）|
| `layer` | 依赖层级 L0/L1/L2（见 Phase 1）|
| `status` | `todo` / `merged` |
| `consumers` | 依赖它的文件列表 |

- **自动 seed**：从 `scratchpad/crossfile_deferrals.json`（155 条，已含被点名的 provider 文件/符号）生成初稿。
- **命名规则内建在表里** → 不同 agent 查同一行，产出必然同名。这就是治"命名漂移"。
- **对抗式评审**：2 个独立 reviewer 过一遍签名/owner/层级，**在任何 porting 之前**定稿。

---

## Phase 1 — 依赖分层（灭环 + 定序）

Bun 在 porting 前先重整 crate 边界灭掉循环依赖。我们对应：

1. 从 `SYMBOLS.tsv` 的 `owning_file → consumers` + 每个文件的 upstream `import` 建 **provider→consumer 有向图**。
2. **拓扑分层**（本仓库实测的形态）：
   - **L0 叶子 provider**（无下游依赖）：`util/throttle`、`util/shape/sausage`、`util/types` 增补、几何/label 小工具、`ZRenderKit Path.extend/extendShape`。
   - **L1 中间 provider**：`component/helper/MapDraw`、`RoamController` roam 变换、`chart/bar/LargeBarPath` progressive 参数、`AxisBuilder` 增补。
   - **L2 消费端**：BarView / MapView / PictorialBarView / … 106 个消费文件。
3. **一层做完并合进 main，再做下一层** → 上层需要的符号在开工时已在树里、可直接引用；**杜绝重复创建、天然可编译**。
4. 有环则单独起一个"分类+重构"小 workflow 打破（Bun 的做法），不手抠。

---

## Phase 2 — 试点 3 文件（放大前先验证）

选 1 个 L0 provider + 1 个 L1 + 1 个消费端，走完整"实现→评审→修复"闭环，验证 `PORTING.md`/`SYMBOLS.tsv` 是否够用；不够就补规则，再放大。（Bun 也是先 port 3 个文件全评审。）

---

## Phase 3 — 逐层并行 porting（worktree 分片）

对每一层：

- 该层内文件**互不依赖**（依赖都在已合并的下层）→ 可安全并行到多个 worktree。
- 每个文件走 **Bun 三段式**：
  - **实现 agent**：line-for-line 忠实翻译上游；**凡引用/创建共享符号，一律照 `SYMBOLS.tsv` 的 `swift_name`**；只有 `owning_file` 的 agent 才定义该符号，其余只引用。
  - **2 个对抗式 reviewer**：只给 diff + "假设代码是错的"，重点查 ①是否偏离 `SYMBOLS.tsv` ②语义 bug。
  - **修复 agent**：应用评审意见后提交。
- **关键松绑**：这一阶段**允许改共享文件**（因为 owner 唯一、下层已合并）→ 这正是 lane 方案做不到、而此方案能做的。
- **消费端不逐文件 build-green**（Bun 就是先全量翻、后统一修）——build 门槛放到 Phase 4 的层集成。

---

## Phase 4 — 编译错误工作队列（每层合并后）

Bun 的核心手法：`cargo check` 每 crate 一次 → 1.6 万个错误按文件分组 → 分给 64 个 Claude 修。我们对应：

1. 合并本层 → `swift build`。
2. 抓**全部**编译错误，**按文件分组**成工作队列。
3. 分片给多个 fix-agent（各占一个 worktree）修，2-reviewer 过。
4. 循环到该层 **build 绿**。签名/命名/重复不一致都在这里被吸收。

---

## Phase 5 — Oracle 收敛（不跳过任何测试）

Bun 用 140 万条断言的测试套件当等价 oracle。我们的 oracle：
1. `swift test`（已移植的 zrender/echarts XCTest specs）。
2. `swift run EChartsDemoGallery --render-all`（125 demo 全渲染）。
3. `--compare`（native vs real-echarts.js 逐 demo 像素对比）。
循环修到全绿，**测试只准修不准删/跳**（Bun 明确"0 test skipped"）。

---

## 编排与防碰撞（"相互依赖"的要害）

| 风险 | 手段 |
|---|---|
| 命名漂移 | `SYMBOLS.tsv` 权威名 = 上游逐字；agent 只查表 |
| 重复创建 | 每符号**唯一 owner**（表里定），非 owner 只引用 |
| 孤立编译不过 | **provider 先行分层** + **编译错误工作队列**（合起来编） |
| 并行改同一文件冲突 | 层内文件互不依赖才并行；跨层串行合并 |
| 循环依赖 | 建图时检出，单独 workflow 打破 |
| agent 写错语义但能编译 | 对抗式 2-reviewer（"假设是错的"，只给 diff）|

**工具**：沿用 `Workflow` + 持久 worktree；`SYMBOLS.tsv` 放 main 作共享真相，**agent 只读不写**，由编排层在每层合并后把该层符号 `status→merged`。第一波的经验教训已内建：commit 用**显式 `git add <file>`**（不用 `-A`）、worktree 里 `third_party/Rasterizer` 软链到 main 真实目录并 `info/exclude`。

---

## 落地顺序（可执行）

1. **Phase 0a/0b**：我生成 `PORTING.md` + 从 155 条 deferral seed 出 `SYMBOLS.tsv` 初稿 → 你/2-reviewer 定稿。
2. **Phase 1**：建依赖图、分 L0/L1/L2、灭环。
3. **Phase 2**：3 文件试点。
4. **Phase 3–5**：逐层 port→review→集成→修编译→跑 oracle。

> 规模参照：Bun 11 天、6502 commit、~100 万行、64 并发 Claude。我们这批是 ~155 gap / ~40 provider / 106 consumer，一个多层 workflow 即可覆盖。
