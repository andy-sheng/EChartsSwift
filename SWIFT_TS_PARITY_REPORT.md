# ZRenderKit Swift ↔ zrender TS 逐文件保真度报告

> 生成日期：2026-06-30
> 方法：对 `Sources/ZRenderKit/**` 的每个 Swift 文件与 `upstream/zrender/src/**` 对应的 TS 源文件做逐文件对照（75 对，每对一个审计 agent，结构化输出），随后人工复核 `PathProxy`。
> 关注真实的行为/API 差异，忽略纯语言习惯差异（值返回 vs 出参、enum 命名空间、Optional、PathProxy 替代 Canvas2D 等已在 CONVENTIONS 约定的转换）。

## 评级口径

| 状态 | 含义 |
|------|------|
| **parity** | 行为等价，可放心使用 |
| **minor** | 仅有装饰性/小范围省略或类型契约差异，功能基本可用 |
| **major** | 有实质性行为/API 缺口，特定功能会出错或不可用 |
| **stub-or-missing** | 大部分未实现 |

## 总览

- 共审计 **75** 个文件对。
- **parity 34** · **minor 17** · **major 23** · **stub-or-missing 1**
- 结论：**几何 / 数学 / 形状层高度保真**（contain、curve、bbox、shape/*、helper/* 几乎全 parity）；**差距集中在三块**：① 状态机（states machinery）② 文本/富文本布局引擎 ③ 渐变/图案（gradient/pattern）作为 fill/stroke 的运行时处理。这与代码里大量 `PORT-TODO / Phase-2 / Phase-3` 标注一致。

---

## 🔴 最该优先补齐（major / stub，按影响排序）

### 1. 状态机 states machinery — 跨多个核心文件，系统性缺失
状态切换（hover/emphasis/select 等）的核心 `_applyStateObj / _savePrimaryToNormal / _mergeStates / _innerSaveToNormal` 在以下文件均为 PORT-TODO 空桩：
- `Element.swift` (major) — `_applyStateObj` 空实现，`saveCurrentToNormalState` 动画烘焙缺失，`setTextConfig` 整体替换而非逐字段 merge，`updateInnerText` autoOverflowArea 分支缺失。
- `Graphic/Displayable.swift` (major) — 整套 states (140+ 行) 全 stub；另外 `setStyle` 对未知 key 静默丢弃、`shouldBePainted` 的 zero-area clip 剔除与 NaN 缩放检测缺失。
- `Graphic/Path.swift` (major) — shape 状态保存/合并/过渡动画全 stub；`setShape(key,value)` 仅标脏不写值；decal 元素合成 `_decalEl` 未实现。

> 影响：任何依赖状态切换的交互（高亮、选中、悬停动画）都不工作。建议作为独立的 “Phase-2: states” 专项推进。

### 2. 文本与富文本布局 — `Graphic/Text.swift` (major) + `Graphic/TSpan.swift` (major)
- `parseRichText` 返回空块、`parsePlainText` 仅支持无换行纯文本；overflow / lineOverflow / truncate / ellipsis 全部未实现。
- gradient/pattern 作为 fill/stroke 时 TS 回退 `#000` 的逻辑被删除（Swift 里 fill/stroke 是 String，渐变描边不可达）。
- `normalizeStyle` 缺少 align 校验与 `middle`↔`center` 归一化。
- `TSpan.getBoundingRect()` 直接返回 nil（未实现 `tSpanCreateBoundingRect`），阻断精确文本测量。

> 影响：富文本、文字截断/省略号、文字渐变全部失效。

### 3. `Core/PathRebuilder.swift` (stub-or-missing) ← `svg/SVGPathRebuilder.ts`
Swift 仅有 protocol 定义，`SVGPathRebuilder` 实现类（reset/generateStr/getStr/_add、椭圆弧渲染、精度取整、NaN 校验）全部缺失（45 行 vs 151 行）。

> 影响：SVG 路径字符串生成不可用。若当前不走 SVG 导出路径，可暂缓。

### 4. `Core/util.swift` (major) — 工具函数缺口大（510 行 vs 860 行）
缺失 `HashMap/createHashMap`、`bind/curry`、`trim`、`setAsPrimitive/isPrimitive`、`concatArray`、`hasOwn`、`assignProps`、`inherits`、`mixin`、`slice` 等 10+ 函数；`merge()` 递归缺少 isPrimitive/isBuiltInObject/isDom 防护；`each()` 不支持字典遍历。

> 影响：上游若有代码依赖这些工具会编译失败；merge 防护缺失可能污染特殊对象。建议按“被实际调用”清单逐个补。

### 5. 出参 → 返回值的调用约定不一致（潜在运行时错误）
这是 CONVENTIONS §3 的有意改造，但部分调用点没改对：
- `Core/Transformable.swift` (major) — `matrix.rotate/mul/copy/invert` 仍按 TS 的“原地变异”语义调用（如 `m = matrix.rotate(m, angle)`），与 Swift 的值返回签名混用，变换计算可能失效。这条建议立即核查，因为它会静默产生错误矩阵。
- `Core/bbox.swift` (major)、`Core/platform.swift` (major)、`Graphic/Helper/subPixelOptimize.swift` (major) — 签名从出参改为返回值/Optional，调用方需适配。

### 6. 数值/算法偏差（会改变渲染输出）
- `Graphic/Shape/Trochoid.swift` (major) — 循环终止用 `truncatingRemainder` 替代 TS 整数取模，可能迭代次数不同甚至死循环。优先核查。
- `Tool/convertPath.swift` (major) — anticlockwise 标志：TS `!data[i]` 对任意数值取反，Swift 只把 0/NaN 当 true，非标准编码下圆弧渲染不同。
- `Tool/ToolPath.swift` (major) — `processArc` 用 `floor(x+0.5)` + 浮点取余替代 `Math.round` + 整数取模，负角度行为不同；`extendFromString` 返回工厂闭包而非类构造器。
- `Core/curve.swift` (minor，但含 high) — `cubicProjectPoint` 的 `t` 初值 0 vs TS 的 undefined，粗扫无解时回退行为不同。

### 7. 事件系统 — `Handler.swift` (major) + `Core/Eventful.swift` (major)
- `ElementEvent` 是值类型（struct），监听器对 `cancelBubble` 的修改不回传 → stopPropagation 失效。
- on-属性处理器（onclick 等）、canvas 用户层事件分发未实现。
- `Eventful`：Swift 闭包无法比较身份 → 无法去重 handler、无法按 handler 精确 `off()`。

### 8. 其他 major
- `Core/types.swift` — 缺 ImageLike / 原始事件类型 / Canvas 上下文类型 / TS 工具型（多数 Swift 无法表达，影响 API 边界类型）。
- `Storage.swift` — 用标准库 sort 替代 timsort（大规模性能回退）；clipPath 缓冲管理算法不同；`dispose` 清空数组而非释放，潜在内存占用。
- `Animation/Animator.swift` — 非遵循 `AnimationTarget` 协议的目标在 `step()` 中无法被改属性；`color.parse()` 出参副作用未利用。
- `ZRender.swift` — 注入式 painter，省略 renderer 选择/校验、`setBackgroundColor()` 钩子、`useCoarsePointer:'auto'` 自适应。
- `Contain/ContainPath.swift` — `windingLine` 调用方式（namespace vs default export）存在接口风险（需确认 Swift 端实际可编译）。
- `Graphic/LinearGradient.swift` / `RadialGradient.swift` — 必需构造参数（x/y/x2/y2/r）被改成 Optional，弱化类型契约。

---

## 🟡 minor（可用，建议记账）

| 文件 | 主要差异 |
|------|----------|
| `Animation/Clip.swift` | `animation` 弱化为 `AnyObject?`（等 Animation 完整 port） |
| `Core/BoundingRect.swift` | `calculateTransform` 忽略 out 缓冲，每次新分配（失去复用优化） |
| `Core/env.swift` | `version` 失去 string\|number 联合；`detect()` 在 iOS 是死代码但逻辑有误 |
| `Core/event.swift` | `getBoundingClientRect` 存在性检查缺失（潜在崩溃）；wheel delta 可空性差异 |
| `Core/LRU.swift` | `LRUKey` 枚举区分数字/字符串键，与 JS 键碰撞语义不同 |
| `Core/matrix.swift` | 出参→值返回（有意，CONVENTIONS §3） |
| `Core/WeakMap.swift` | `has()` 对假值（0/false/""）返回 true，与 TS truthy 检查不同 |
| `Graphic/Group.swift` | 无参 `getBoundingRect()` 返回可空；缺 `invisible` 子元素跳过 |
| `Graphic/Gradient.swift` / `Pattern.swift` | `__canvasGradient` / `svgElement` / ImageLike 延后到 canvas 阶段 |
| `Graphic/Helper/poly.swift` | 仅接受 PathProxy（移除 canvas 路径） |
| `Graphic/Shape/Circle/Droplet/Isogon/Rose` | `XxxProps = typealias PathProps`，丢失 shape 字段编译期类型收窄 |
| `Tool/color.swift` | `liftColor` 对渐变几何属性（x/y/r）浅拷贝未深克隆 |
| `Tool/dividePath.swift` | `copyPathProps` 用 `useStyle` 替代 `setStyle`（merge vs replace 待定） |

---

## 🟢 parity（忠实移植，34 个）

动画：`Animation.swift`、`easing.swift` · 配置：`config.swift`
contain 全家桶：`ContainArc/ContainLine/ContainPolygon/ContainText/containUtil/cubic/quadratic/windingLine`
core：`GestureMgr`、`Point`、`vector`、`PathProxy`（人工复核：忠实，且 `_calculateLength` 修了一个上游会越界的 arc-slot bug）
graphic：`CompoundPath`、`constants`、`Image`、`IncrementalDisplayable`、helper 的 `roundRect/roundSector/smoothBezier`
shape：`Arc`、`BezierCurve`、`Ellipse`、`Heart`、`Line`、`Polygon`、`Polyline`、`Rect`、`Ring`、`Sector`、`Star`
tool：`morphPath`、`transformPath` · mixin：`Draggable`

---

## 建议的推进顺序

1. 先查会“静默出错”的：`Transformable`（矩阵调用约定）、`Trochoid`（取模死循环）、`convertPath`/`ToolPath`（arc 标志/取整）——这些不报错但渲染会错。
2. 再补“整块功能”：states machinery（Element/Displayable/Path 一起）、文本布局引擎（Text/TSpan + 上游 parseText）。
3. 按需补：`util.swift` 缺失函数（按实际调用清单）、`PathRebuilder`（若需 SVG 导出）、事件冒泡（若需嵌套交互）。
4. 性能/收尾：`Storage` 的 timsort、`BoundingRect` 缓冲复用、gradient/pattern 的 canvas 阶段集成。

> 注：本报告由 75 个并行审计 agent 生成 + PathProxy 人工复核。各 agent 给出的行号为参考值，落地修复前请以当前源码为准。完整逐文件原始 JSON 结果见工作流输出。

---

# 附录：第二轮「经验驱动 + 对抗式」重审(2026-06-30)

第一轮抽样修复时发现:10 个疑似 high-severity bug 里 9 个站不住(多为审计 agent 误解 JS 语义或把有意移植约定当 bug)。于是对 29 个有差距文件做了第二轮重审,方法升级为:① 给每个 agent 注入「已知陷阱清单」(JS falsy、`%` 浮点取余、`Math.round=floor(x+0.5)`、CONVENTIONS §3 值返回、enum 命名空间、renderer seam §9、PORT-TODO 延后功能等);② 每条候选 bug 再派一个「怀疑论者」agent 默认它是误报、必须举证才能存活(对抗式验证)。

## 结果:仅 5 个真 bug 存活,全部已修复并通过编译 + 101 测试

| 文件 | 严重度 | 真 bug | 修复 |
|------|--------|--------|------|
| `Animation/Clip.swift` | medium | `_life = opts.life ?? 1000` 未复刻 TS `\|\| 1000` 的 falsy 合并:`life:0` 时 Swift 保留 0 → `percent=t/0=NaN`,非循环动画永不结束、回调永不触发。`Animator.duration(0)` 可达此路径。 | `life == 0 ? 1000 : life` |
| `Tool/dividePath.swift` | medium | circle→sector 合成时 `SectorShape()` 默认 `clockwise=true`,而上游对象字面量无该键(undefined→roundSector 读为 false)。导致 `split(circle, n>1)` 每个子扇形弧线方向相反、填充区域错误。 | 合成时显式 `clockwise=false` |
| `Graphic/Text.swift` | low | `_renderBackground` 边框判断只判 `borderColor != nil`,空串 `""` 会通过(同文件 `needDrawBackground` 却正确判空串)。`borderColor:""` 时 Swift 描空色边框、`hasStroke()` 返回 true 使 getBoundingRect/contain 的包围盒与命中判定偏差。 | `let bc, !bc.isEmpty` 对齐 TS `&&` falsy |
| `Element.swift` | low | `stopAnimation(scope:)` 用 `scope == nil` 未复刻 TS `!scope` 的空串 falsy:`stopAnimation("")` 在 TS 停止所有动画,Swift 一个都不停。 | 加 `scope!.isEmpty` 分支 |
| `Core/Eventful.swift` | low | `triggerWithContext` 在无参时 `args[argLen-1]` = `args[-1]`,Swift 负下标 **崩溃**(TS 返回 undefined 正常执行)。需先绑定 handler 再无参调用。 | `argLen > 0 ? ... : nil` 守卫 |

> 加上第一轮修复的 `Graphic/Displayable.swift`(`shouldBePainted` 的 NaN 缩放剔除),本仓库经两轮审计共修复 **6 个真 bug**。

## 被对抗式验证驳回的典型「伪 bug」(供参考,勿再上报)

- **JS falsy/`%`/`Math.round` 误解**:`convertPath` 的 `!data[i]`、`Trochoid`/`Clip` 的 `truncatingRemainder`、`ToolPath`/`subPixelOptimize` 的 `floor(x+0.5)` 全部是**正确移植**。
- **CONVENTIONS §3 有意约定**:`Transformable`/`bbox`/`matrix`/`BoundingRect` 的「值返回替代出参」不是 bug。
- **延后功能(PORT-TODO Phase-2/3)**:states 状态机(Element/Displayable/Path)、富文本布局(Text/TSpan + parseText)、`SVGPathRebuilder` 实现、canvas/pattern 后端、Eventful 闭包身份(dedup/off-by-handler) —— 这些是**整块未实现**,属计划内延后,不算 bug。
- **类型层 / renderer seam**:`types.swift` 的 TS 工具型、gradient/pattern 的 `__canvasGradient`、Canvas2D 上下文 —— Swift 无对应运行时概念。
- **`color.liftColor` 浅拷贝渐变**(第一轮的 needs-architecture 项):重审确认当前 Gradient 子类因 `global` 可选性不匹配未遵从 `GradientObject` 协议,该分支是**死代码**,无实际影响;待 Gradient clone seam 统一处理时再修。

## 复核后各文件重新评级

第二轮把多个原评 major 的文件**下调**:`Animator`/`bbox`/`BoundingRect`/`env`/`LRU`/`platform`/`types`/`util`/`Displayable`/`Path`(范围内方法)/`Storage` 等经逐行核对实为 **parity 或仅延后功能的 minor**。原报告的 23 个 major 中,真正含「可修真 bug」的仅上表 5 个文件;其余 major 的实质是**计划内的延后功能**,而非移植缺陷。

