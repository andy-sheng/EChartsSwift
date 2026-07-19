# ECharts/ZRender → Swift 逐文件迁移保真度审计

> 生成日期：2026-07-17 · 方法：对 `Sources/{EChartsKit,ZRenderKit,NativePainter}/**` 中每个带 `// Ported from` 头的 Swift 文件，
> 与其 upstream `.ts` 原文件配对（480 对），每对派一个 agent 全量读取双方源码、逐行对照行为保真度，结构化输出。
> 忽略 CONVENTIONS 已约定的语言习惯差异（值返回 vs 出参、enum 命名空间、Optional、PathProxy 替代 Canvas2D、protocol+extension 替代继承、ContiguousArray 替代 typed array）。
>
> **用途**：后续迁移的待办清单。按优先级排序 —— §3 是可执行的迁移 backlog，§4 是全部实质缺口文件，§5 是完整逐文件表。

## 1. 总览

- 审计文件对：**480**（不含无 upstream 对应的原生胶水文件：NativePainter/RasterizerPainter、theme JSON、action/roamHelper 拆分、PortStub 等约 29 个）
- 平均行为覆盖率：**94.9%**
- 残留 PORT-TODO/TODO/FIXME 标记：**363**

### 评级分布

| 状态 | 含义 | 数量 |
|------|------|-----:|
| 🟢 parity | 行为等价，可放心依赖 | 307 |
| 🟡 minor | 仅装饰性/小范围省略或类型契约差异，功能基本可用 | 142 |
| 🟠 major | 有实质行为/API 缺口，特定功能会出错或不可用 | 29 |
| 🔴 stub | 大部分未实现/占位 | 2 |

### 迁移优先级分布

| 优先级 | 数量 |
|--------|-----:|
| high | 8 |
| medium | 41 |
| low | 132 |
| none | 299 |

### 按模块分布（major+stub 是重点）

| 模块 | parity | minor | major | stub | 平均覆盖 |
|------|-------:|------:|------:|-----:|--------:|
| chart | 63 | 49 | 14 | 1 | 92% |
| component | 56 | 39 | 6 | 1 | 94% |
| coord | 53 | 11 | 2 | 0 | 98% |
| label | 1 | 2 | 2 | 0 | 75% |
| util | 13 | 5 | 2 | 0 | 95% |
| visual | 4 | 2 | 2 | 0 | 94% |
| core | 4 | 2 | 1 | 0 | 95% |
| animation | 3 | 1 | 0 | 0 | 94% |
| data | 12 | 6 | 0 | 0 | 98% |
| i18n | 8 | 0 | 0 | 0 | 100% |
| layout | 2 | 2 | 0 | 0 | 98% |
| model | 10 | 5 | 0 | 0 | 97% |
| processor | 4 | 0 | 0 | 0 | 100% |
| scale | 10 | 0 | 0 | 0 | 100% |
| theme | 1 | 0 | 0 | 0 | 100% |
| view | 1 | 1 | 0 | 0 | 94% |
| Animation | 4 | 0 | 0 | 0 | 99% |
| ZRenderKit | 1 | 4 | 0 | 0 | 94% |
| Contain | 9 | 0 | 0 | 0 | 100% |
| Core | 12 | 7 | 0 | 0 | 94% |
| Graphic | 29 | 5 | 0 | 0 | 99% |
| mixin | 1 | 0 | 0 | 0 | 100% |
| Tool | 6 | 1 | 0 | 0 | 99% |

## 3. 迁移 Backlog（可执行 · 按优先级）

每条列出目标文件、状态、覆盖率与**具体缺口**（缺口指明了 upstream 里缺失/错误的函数/分支，非语言习惯）。

### 3.1 HIGH 优先级

#### 🟠 `EChartsKit/component/tooltip/TooltipView.swift`  · major · 40% · todos=0
<sub>↔ `echarts/src/component/tooltip/TooltipView.ts`</sub>

Deliberately SLIM TooltipView: only trigger:'item' + a ported trigger:'axis' show path; large swaths of upstream behavior deferred.

- formatter (string/function callback) override of default markup not ported → custom tooltip.formatter content unavailable
- position option (callback / string 'top'/'inside' / [x,y] array) + confine not ported → only default below/right-of-pointer, clamped placement
- showDelay/hideDelay + transitionDuration animation + throttled _updatePosition (createOrUpdate) not ported → shows/hides synchronously, no move tween
- findPointFromSeries not ported → showTip action without x/y falls back to view centre instead of series layout point
- _showComponentItemTooltip not ported → component (markPoint/geo/timeline) item tooltips unavailable
- _tryShow dispatcher walk (dataByCoordSys build, legend/component branches) + globalListener not ported; caller must pre-resolve series/dataIndex
- _updateContentNotChangedOnAxis / _keepShow no-change-position-only update path not ported
- TooltipHTMLContent host absent: renderMode forced 'richText', so renderMode:'html'/'auto' ignored

#### 🟠 `EChartsKit/chart/graph/GraphView.swift`  · major · 55% · todos=0
<sub>↔ `echarts/src/chart/graph/GraphView.ts`</sub>

Static-subset view: node SymbolDraw + inline edges + adjacency focus + edge labels are wired, but force layout, roam, drag, arrows and thumbnail are all deferred.

- _startForceLayoutIteration not driven; layout:'force' graphs never iterate/converge (only circular + simpleLayout render)
- edgeSymbol from/toSymbol arrow markers (ECLinePath.setLinePoints) not drawn; edges are bare Line/BezierCurve
- roam pan/zoom fully deferred: RoamController + applyViewCoordSysTransToElement + updateRoamControllerSimply not wired
- node draggable (el.on('drag'/'dragend') per-layout reposition) not wired
- circular rotateLabel via rotateNodeLabel deferred; node labels not rotated in circular layout
- _renderThumbnail / thumbnailBridge deferred; no minimap thumbnail
- _updateNodeAndLinkScale setSymbolScale (node/link roam scaling) deferred

#### 🟠 `EChartsKit/component/timeline/SliderTimelineView.swift`  · major · 55% · todos=2
<sub>↔ `echarts/src/component/timeline/SliderTimelineView.ts`</sub>

Slider timeline view: static render path (layout/axis/ticks/labels/control/pointer) faithful, but the entire interaction layer is deferred.

- _doPlayStop deferred: autoPlay never starts the advance timer, so the timeline never auto-advances
- _updateTicksStatus deferred: tick symbols/labels before currentIndex never toggle the 'progress' state (no past-tick highlight)
- onclick (_changeTimeline) not wired on ticks/labels/play/prev/next buttons: every click is a no-op
- checkpoint pointer drag (_handlePointerDrag/_handlePointerDragend/_pointerChangeTimeline/_toAxisCoord) deferred: pointer not draggable
- ensureState('emphasis'/'progress') + enableHoverEmphasis omitted on all elements: no hover emphasis
- giveSymbol collapsed to create-only; pointerMoveTo animateTo branch absent, so pointer index changes never animate
- remove()/dispose() (_clearTimer) not ported

#### 🟠 `EChartsKit/chart/lines/LinesView.swift`  · major · 60% · todos=0
<sub>↔ `echarts/src/chart/lines/LinesView.ts`</sub>

Static/effect subset ChartView: straight/curved lines via ported LineDraw + inline polyline morph + wired EffectLine trail; several upstream render paths deferred.

- `clip` option not wired — createClipPath(coordSys)+group.setClipPath omitted, so overflow clipping of lines is unavailable
- Large mode (isLargeDraw / LargeLineDraw) not ported — large-mode lines series do not render
- incrementalPrepareRender / incrementalRender / updateTransform / eachRendered not wired — progressive rendering and transform-only roam/zoom updates absent
- fromSymbol/toSymbol arrow markers, per-line label, and emphasis/blur states deferred (finishBuildLine)
- Only Cartesian2D coordinate system handled — polar/geo lines drop to resetPersistentElements() and draw nothing

#### 🟠 `EChartsKit/util/graphic.swift`  · major · 65% · todos=1
<sub>↔ `echarts/src/util/graphic.ts`</sub>

Partial port of the graphic util module: transform/geometry/shape-registry/createIcon slice is faithful, but several exported behaviors are unported here and nowhere else.

- setTooltipConfig not ported anywhere -> component-level item tooltipConfig (title/legend/geo/graphic/timeline) is unavailable
- clipRectByRect not ported (only inlined per-demo) -> custom-series rect-clip helper missing
- groupTransition not ported -> parallel-axis (and legacy group) transition animation is a no-op
- calcZ2Range not ported -> z2-range label-lifting computation absent
- extendShape/extendPath not ported -> user shape/path extension API unavailable

#### 🟠 `EChartsKit/chart/treemap/TreemapView.swift`  · major · 70% · todos=2
<sub>↔ `echarts/src/chart/treemap/TreemapView.ts`</sub>

Treemap chart view; static tile/label/upperLabel/drillDownIcon/hover-emphasis render is faithful, but the interactive drill/zoom subsystem and diff/animation are deferred.

- _initEvents node click (nodeClick zoomToNode / rootToNode / link windowOpen) is a no-op: clicking a tile never zooms or drills (treemapAction not ported)
- _zoomToNode/_rootToNode dispatchAction deferred, and breadcrumb onSelect callback is empty: no drill/roll navigation at all
- _onPan/_onZoom roam re-layout (treemapMove/treemapRender) replaced by a container-group transform: roam moves/scales tiles instead of re-laying-out the rootRect
- _doAnimation (drill/roll re-root, fade-out-to-corner, fade-in) deferred; replaced by a simpler morph + opacity entrance fade
- Hierarchical DataDiffer dualTravel replaced by static rebuild gated on node-count: no id-based element reuse across structural changes
- renderBackground/renderContent emphasis/blur/select fills use setStatesStylesFromModel instead of upstream's state itemStyle with fill=borderColor, so state colors differ

#### 🟠 `EChartsKit/chart/custom/CustomView.swift`  · major · 72% · todos=1
<sub>↔ `echarts/src/chart/custom/CustomView.ts`</sub>

CustomChartView: static render core (createEl+all shapes, shape/style/transform apply, makeRenderItem api, mergeChildren, static clipPath, basic textContent, data.diff enter/update/leave, keyframe animation, toggleHoverEmphasis) is faithfully ported; the transition/state/diff-animation layer is deferred (56 DEFERRED markers).

- Per-state STATES loop that calls updateElOnState (upstream doCreateOrUpdateEl L1084-1089) is deferred: renderItem emphasis/blur/select {style,shape} overrides never applied
- applyUpdateTransition/applyLeaveTransition deferred: transition/enterFrom/leaveTo/during-driven prop tweening does not animate (static apply + removeElementWithFadeOut substitute)
- Group-child by-name diff (diffGroupChildren via DataDiffer, $mergeChildren:'byName') deferred: children rebuilt by index each render, losing per-child identity/animation
- Legacy ec4 style compat (convertFromEC4CompatibleStyle/isEC4CompatibleStyle) and deprecated api.style/api.styleEmphasis return best-effort raw visual bag only
- style.decal pattern (createOrUpdatePatternFromDecal) deferred: decals ignored on custom elements
- api.getZr() and api.getDevicePixelRatio() stubbed (return nil / 1.0)
- per-state z (updateZForEachState) and ec4 z2EmphasisLift/z2SelectLift=1 default not written; uses generic Z2 lift
- renderItem params.context shared across datums upstream but copied per-datum here (value type), losing cross-datum state stash

#### 🟠 `EChartsKit/chart/bar/BarView.swift`  · major · 80% · todos=0
<sub>↔ `echarts/src/chart/bar/BarView.ts`</sub>

BarView render; cartesian normal-mode path (diff add/update/remove, clip, background, updateStyle+label+emphasis) is fully faithful and polar Sector rendering is added, but realtimeSort machinery and borderRadius are non-functional.

- realtimeSort entirely stubbed: _enableRealtimeSort/_dataSort/_updateSortWithinSameData/_dispatchInitSort/_isOrderChangedWithinSameData/_isOrderDifferentInView are no-ops → bar racing sort/reorder animation unavailable
- itemStyle.borderRadius dropped: setShape('r', borderRadius) is a documented ZRenderKit no-op → bar corners never round
- _incrementalRenderLarge is a no-op (createLarge incremental/progressive branch deferred) → progressive large-bar draw absent
- setLabelValueAnimation deferred → bar label numeric roll-up animation missing
- large-path mouse hit-test (largePathUpdateDataIndex throttle) deferred → tooltip/hover over large-mode bars cannot resolve dataIndex
- polar roundCap (Sausage) and sector label rotation (setSectorTextRotation/getSectorCornerRadius) deferred → polar bars always square-capped, no rotated sector labels

### 3.2 MEDIUM 优先级

#### 🟠 `EChartsKit/component/parallel/ParallelComponentView.swift`  · major · 20% · todos=0
<sub>↔ `echarts/src/component/parallel/ParallelView.ts`</sub>

Parallel component interaction view; the axis-expand pointer interaction (the entire behavioral content of ParallelView.ts) is deferred/stubbed, though the sibling ParallelAxisView backdrop drawer bundled in the same file works.

- The mousedown/mouseup/mousemove handler table is commented out and never registered via getZr().on, so axis-expand-on-click/mousemove never fires
- _dispatchExpand body is commented; the parallelAxisExpand action is never dispatched even if the method is reached
- createOrUpdate/debounceNextCall throttle wiring (axisExpandRate/axisExpandDebounce) not ported, so throttled expand dispatch is absent
- checkTrigger gating (axisExpandable / axisExpandTriggerOn) unimplemented — interaction cannot be enabled

#### 🟠 `EChartsKit/label/labelGuideHelper.swift`  · major · 35% · todos=0
<sub>↔ `echarts/src/label/labelGuideHelper.ts`</sub>

Leader-line angle math for label guide lines; only the three angle-limiter functions are ported, the generic guide-line generation/styling system is deferred.

- updateLabelLinePoints not ported: the candidate-anchor guide-line generation entry (getCandidateAnchor/nearestPointOnPath/nearestPointOnRect) is absent
- setLabelLineStyle not ported: no generic label-line creation/state styling (show/smooth/lineStyle/showAbove) — charts must draw leader lines inline
- getLabelLineStatesModels not ported: no per-state (normal/emphasis/blur/select) labelLine model resolution
- buildLabelLinePath / setLabelLineState not ported: smooth bezier leader-line path building is absent
- projectPointToArc / projectPointToRect not ported (only projectPointToLine present), so nearestPointOnPath arc/rect projection unavailable

#### 🟠 `EChartsKit/label/LabelManager.swift`  · major · 55% · todos=0
<sub>↔ `echarts/src/label/LabelManager.ts`</sub>

Global labelLayout stage (collect/updateLayoutConfig/layout); the overlap-resolution path is ported but all label-line update and label animation is deferred.

- processLabelsOverall + _updateLabelLine not ported: per-frame generic label-line style/point update (setLabelLineStyle/updateLabelLinePoints) never runs
- _animateLabels not ported: label position tween, fade-in initProps opacity animation, and value roll-up (animateLabelValue) are absent
- updateLayoutConfig draggable branch deferred: label drag + createDragHandler(updateLabelLinePoints) not wired
- updateLayoutConfig labelLinePoints override (guideLine.setShape) not applied
- textEl.disableLabelLayout gate omitted in addLabelsOfSeries, so a label opting out of layout is still collected

#### 🟠 `EChartsKit/chart/map/MapView.swift`  · major · 70% · todos=0
<sub>↔ `echarts/src/chart/map/MapView.ts`</sub>

Map chart view; upstream delegates all region drawing to MapDraw (not ported), so Swift inlines a static GeoJSON/SVG render + color-morph. Regions/fill/labels/symbols/basic emphasis work; interaction gaps.

- MapDraw + RoamController not ported → map pan/zoom roam is a no-op (__updateOnOwnRoam, geoRoam self-roam short-circuit inert)
- mapToggleSelect select action/state path deferred → region click-select does not function
- region↔symbol hover link (onHoverStateChange→setStatesFlag on legend circle) deferred → symbols don't react to region hover
- projectionStream (d3 clip/resample) omitted; only per-point dataToPoint projection used
- emphasis/select/blur state styles use getItemStyle not getFixedItemStyle → state areaColor fixup missing

#### 🟠 `EChartsKit/component/geo/GeoView.swift`  · major · 70% · todos=0
<sub>↔ `echarts/src/component/geo/GeoView.ts`</sub>

Geo component view; upstream is a thin MapDraw delegate, the port inlines a large static subset of MapDraw (geoJSON + geoSVG builds, styles, labels, SVG states/hover) but leaves all interaction hooks deferred as no-ops.

- render's roam re-draw (__updateOnOwnRoam → mapDraw.__updateOnOwnRoam) is a documented no-op; geo pan/zoom does not re-render
- _handleRegionClick → api.dispatchAction('geoToggleSelect') not wired; clicking a region toggles no selection
- updateSelectStatus (traverse + enterSelect/leaveSelect per isSelected) not ported; selected-region highlight never applied
- geoJSON region path draws only NORMAL itemStyle: no emphasis/select/blur states, no highDown dispatcher, so geoJSON region hover-emphasis is absent (only geoSVG has states)
- findHighDownDispatchers geoJSON branch (_regionsGroupByName) returns nil; hover-link/highlight-by-name unsupported for geoJSON maps

#### 🟠 `EChartsKit/chart/helper/SymbolDraw.swift`  · major · 72% · todos=0
<sub>↔ `echarts/src/chart/helper/SymbolDraw.ts`</sub>

Per-point symbol diff renderer; normal updateData/updateLayout/remove faithful, but the entire large/progressive incremental pipeline is omitted.

- incrementalPrepareUpdate/incrementalUpdate/eachRendered and _progressiveEls omitted — progressive (large-mode) symbol rendering unavailable
- normalizeUpdateOpt not ported: opt passed as a bare isIgnore function is not coerced to {isIgnore}

#### 🟠 `EChartsKit/chart/effectScatter/EffectScatterView.swift`  · major · 75% · todos=0
<sub>↔ `echarts/src/chart/effectScatter/EffectScatterView.ts`</sub>

View delegates to SymbolDraw(EffectSymbol) with ripple rings; core render works but clip, roam and several coord systems are omitted.

- createSymbolDrawOpt clipShape (createCoordSysClipAreaSimply) omitted, so the clip:true default is a no-op and symbols outside the coord area are not clipped
- updateTransform (roam re-layout via pointsLayout.reset + updateLayout) not ported, so roam pan/zoom does not reposition ripples without a full render
- _updateGroupTransform (matrix.clone of coordSys.getRoamTransform) not ported, so group roam transform is never applied
- geo/singleAxis/matrix coordinate systems hit the else-branch early return, rendering nothing for effectScatter on those systems
- remove() override (this._symbolDraw.remove(true)) not ported

#### 🟠 `EChartsKit/chart/parallel/ParallelView.swift`  · major · 75% · todos=0
<sub>↔ `echarts/src/chart/parallel/ParallelView.ts`</sub>

Parallel polyline chart view; core static render + hover emphasis faithful, but a declared STATIC SUBSET missing the progressive and clip-reveal paths.

- incrementalRender is a full no-op: progressive/large-data render path (default progressive:300) draws nothing for datasets over the threshold
- createGridClipShape enter clip-reveal animation (setClipPath growing rect) not ported; lines appear via an opacity-fade substitute
- data.diff add/update/remove pipeline replaced by a count-gated morph; mismatched-count updates rebuild-and-snap instead of animating, and saveOldStyle update-transition unused

#### 🟠 `EChartsKit/component/axis/SingleAxisView.swift`  · major · 75% · todos=0
<sub>↔ `echarts/src/component/axis/SingleAxisView.ts`</sub>

Single-axis view; splitLine builder fully ported, but the splitArea builder is a complete no-op.

- splitArea builder is a no-op: rectCoordAxisBuildSplitArea (axisSplitHelper) not ported, so single-axis splitArea bands never render
- remove() no-op: rectCoordAxisHandleRemove not ported, cached splitArea colors not cleared
- pathStyleFromDict does not map lineDash (deferred), so dashed splitLine styling is dropped
- graphic.groupTransition deferred: no anid-matched transition animation on re-render

#### 🟠 `EChartsKit/component/marker/MarkerModel.swift`  · major · 75% · todos=1
<sub>↔ `echarts/src/component/marker/MarkerModel.ts`</sub>

Abstract marker model base: _mergeOption/per-series wiring/getData faithful, but DataFormatMixin conformance blocked, degrading label/tooltip/params.

- fillLabel is a no-op: defaultEmphasis(opt,'label',['show']) is not applied, so per-item emphasis-label defaults are dropped
- formatTooltip returns nil (getRawValue unavailable) — marker tooltips produce no markup
- getDataParams omits the DataFormatMixin base computation (color/encode/dimensionNames/value formatting), only host-series patch applied
- DataFormatMixin not conformed: getFormattedLabel/getRawValue from the mixin are unavailable on marker models

#### 🟠 `EChartsKit/chart/tree/TreeView.swift`  · major · 78% · todos=0
<sub>↔ `echarts/src/chart/tree/TreeView.ts`</sub>

Tree chart view; orthogonal trees (nodes, curve/polyline edges, focus, expand-collapse, blur hook) fully ported, but radial label rotation, collapsed-node inner color, and roam node-scale are deferred.

- Radial label block (render() lines 389-444: rad/isLeft/setTextConfig rotation) deferred - radial-tree labels are unrotated and on the wrong side
- symbolInnerColor (isExpand===false && children ? visualColor : neutral00) deferred - collapsed nodes lack the hollow inner-fill marker
- _updateNodeAndLinkScale / calcCompensationScaleToPreserveNodeSize deferred - node symbols scale with zoom instead of preserving size under roam
- drawEdge does not call setDefaultStateProxy(edge) (upstream line 555) - edge default state-transition proxy missing
- Enter/remove animation (removeElement, fadeOut, source-old-layout grow-out) deferred - nodes/edges appear and vanish without tween

#### 🟠 `EChartsKit/util/layout.swift`  · major · 78% · todos=2
<sub>↔ `echarts/src/util/layout.ts`</sub>

Component box-layout helpers; core getLayoutRect/box/positionElement/mergeLayoutParam/getCircleLayout faithful, but several exported helpers unported.

- applyPreserveAspect not ported: preserveAspect 'cover'/'contain' for geo/graphic/image components is unavailable
- fetchLayoutMode not ported: component layoutMode resolution for mergeLayoutParam callers is absent
- getLayoutParams not ported: retrieve LOCATION_PARAMS from a source option object is missing
- sizeCalculable not ported (option[width] \|\| (left&&right) size check)
- createBoxLayoutReference omits the enableLayoutOnlyByCenter+dataToPoint POINT-kind branch and the __DEV__ error branch
- vbox/hbox curried forwarders absent (no current consumer)

#### 🟠 `EChartsKit/chart/pie/PieView.swift`  · major · 80% · todos=0
<sub>↔ `echarts/src/chart/pie/PieView.ts`</sub>

PieView with faithful data.diff add/update/remove, expansion enter, labels+leader lines, emphasis; several interactive/enter features deferred.

- select-state selectedOffset dx/dy translate omitted: selecting a slice does not offset (explode) the sector/label/labelLine
- getSectorCornerRadius not wired: itemStyle.borderRadius/innerCornerRadius ignored, cornerRadius forced to 0
- animationType:'scale' r-grow enter and SSR scaleX/scaleY branch not ported; only 'expansion' enter supported
- itemStyle.cursor (itemModel.getShallow('cursor')) never applied to the sector
- select/blur state getSectorCornerRadius shape merges omitted; _updateLabel guards leader line on labelLine.show instead of labelPosition outer/outside

#### 🟠 `EChartsKit/core/ECharts.swift`  · major · 80% · todos=2
<sub>↔ `echarts/src/core/echarts.ts`</sub>

The ECharts driver: setOption/update/render/dispatchAction pipeline is extremely faithful, but a swath of public instance-API methods is unported.

- `convertToPixel`/`convertFromPixel` (data<->pixel coordinate conversion public API) not ported
- `resize(opts)` not ported — no runtime resize / media-query re-resolve (driver takes fixed width/height at init)
- `getOption()` (return current merged option tree) not ported
- `getVisual(finder, visualType)` not ported
- `clear`/`dispose`/`isDisposed` instance lifecycle not ported (no _disposed flag)
- `showLoading`/`hideLoading` loading spinner not ported
- `appendData` streaming/incremental data API not ported
- module-level `connect`/`disconnect` cross-chart event mirroring not wired (MessageCenter exists but connect() absent)
- `refineEvent` path unported: refined 'selectchanged' event never emitted (only non-refined select/unselect/toggleselect)
- legacy dataSelectAction events (pieselectchanged/mapselectchanged/selected) not re-emitted
- Scheduler progressive/large-mode incremental rendering + updateStreamModes framing not reproduced (renderTask runs synchronously)
- `makeActionFromEvent` not ported

#### 🟠 `EChartsKit/visual/symbolVisual.swift`  · major · 80% · todos=0
<sub>↔ `echarts/src/visual/symbol.ts`</sub>

seriesSymbolTask/dataSymbolTask populating symbol/symbolSize/etc visuals; literal path faithful but function-valued symbol props are not evaluated.

- Function-valued symbol props (symbolSize/symbol/symbolRotate/symbolOffset callbacks) not evaluated per data item — the seriesSymbolTask dataEach callback branch is not ported
- dataSymbolTask omits the ecModel.isSeriesFiltered(seriesModel) skip and the performRawSeries/createOnAllSeries scheduler flags (invoked inline from views instead)

#### 🟠 `EChartsKit/chart/radar/RadarView.swift`  · major · 82% · todos=0
<sub>↔ `echarts/src/chart/radar/RadarView.ts`</sub>

RadarView: line/area rings, keyed data.diff, collapse-to-center entrance, symbols, and emphasis dispatch faithfully ported; several styling/label sub-behaviors deferred.

- Per-vertex value label block (upstream setLabelStyle loop lines 251-265) not ported — radar label.show shows no vertex values
- Per-state polygon.ensureState(stateName).ignore + per-state polyline/polygon/symbol itemStyle loop (lines 209-222) not applied
- Vertex symbols ignore symbolRotate (createSymbol applies rotation upstream)
- Vertex symbols don't apply full itemStyle/setColor/strokeNoScale (only createSymbol fill param)
- ZRImage image-symbol branch (lines 236-244) deferred

#### 🟠 `EChartsKit/chart/sunburst/SunburstSeries.swift`  · major · 82% · todos=1
<sub>↔ `echarts/src/chart/sunburst/SunburstSeries.ts`</sub>

Series model: tree build, completeTreeValue, viewRoot reset, level models, aria decal — solid, but the levels[] per-node inheritance wiring and getDataParams are broken/deferred.

- beforeLink wrapMethod('getItemModel') injection never fires (SeriesData.wrapMethod can't rebind Model-returning methods) so per-node model.parentModel=levelModel is dropped -> levels[] itemStyle/label not inherited
- getDataParams override deferred (wrapTreePathInfo stub) so params.treePathInfo is absent from tooltip/label formatters

#### 🟠 `EChartsKit/coord/axisModelCreator.swift`  · major · 82% · todos=1
<sub>↔ `echarts/src/coord/axisModelCreator.ts`</sub>

Axis-model class generator; the AxisModel class body is fully ported but the module's registration purpose is stubbed.

- registerComponentModel is a PORT-STUB no-op — creator-generated per-type axis model classes are never registered (ECharts.swift hand-written stand-in models serve instead)
- registerSubTypeDefaulter is a PORT-STUB no-op — component sub-type inference from option not consulted for non-axis components
- mergeDefaultAndTheme drops fetchLayoutMode/getLayoutParams/mergeLayoutParam branch — axis box-layout params (single/parallel axis positioning) not merged

#### 🟠 `EChartsKit/chart/gauge/GaugeView.swift`  · major · 85% · todos=0
<sub>↔ `echarts/src/chart/gauge/GaugeView.ts`</sub>

Gauge view: axisLine/ticks/labels/pointer-sweep/progress/anchor/title/detail + emphasis all present; several opt-in features deferred, verdict major.

- roundCap:true uses Sector not Sausage, so axisLine and progress arcs render square caps instead of round
- detail valueAnimation count-up not driven: setLabelValueAnimation/animateLabelValue call sites omitted, detail updates to final value without tween
- formatLabel function-callback formatter is a no-op (only the string '{value}' replacement branch works)
- pointer icon of image:// form: the `pointer instanceof ZRImage` useStyle branch is deferred
- title/detail/label built with minimal gaugeTextStyle (font/fill/align only) not createTextStyle, dropping textBorder/shadow/rich styling

#### 🟠 `EChartsKit/coord/cartesian/Grid.swift`  · major · 85% · todos=4
<sub>↔ `echarts/src/coord/cartesian/Grid.ts`</sub>

Grid coordinate-system master (axis creation, onZero, alignTicks, resize, convert, tooltip axes); core faithful but the outerBounds/label-overflow shrink path is stubbed.

- layOutGridByOuterBounds is fully stubbed (returns noPxChange=true, no shrink) so grid.outerBounds and containLabel-without-legacy-impl never shrink the grid rect for label/name overflow
- resolveAxisNameOverlapForGrid deferred: cross-perpendicular-axis name-overlap nudging (moveIfOverlapByLinearLabels) not applied; uses default resolver
- createOrUpdateAxesView skips calcNameMarginLevel/nameMarginLevelMap so axis-name margins are not scaled by relative grid size

#### 🟠 `EChartsKit/visual/visualSolution.swift`  · major · 88% · todos=0
<sub>↔ `echarts/src/visual/visualSolution.ts`</sub>

createVisualMappings/replaceVisualOption/applyVisual/incrementalApplyVisual ported, but the hidden __alphaForOpacity slot leaks into the applied visual types.

- __alphaForOpacity stored under a literal dict key is NOT filtered by prepareVisualTypes (contrary to the code comment), so an opacity visualMap/brush applies an extra colorAlpha, wrongly modifying item color alpha
- createMappings prototype-hidden-field trick is only partially emulated: the hidden slot is iterable, unlike upstream where hasOwnProperty iteration skips it

#### 🟡 `EChartsKit/chart/lines/linesInstall.swift`  · minor · 75% · todos=0
<sub>↔ `echarts/src/chart/lines/install.ts`</sub>

Install file is documentation-only (fully commented); actual registration relocated to ECharts.swift driver (view/series/layout registered), matching port convention.

- registerVisual(linesVisual) not fulfilled — linesVisual is not ported/registered anywhere; per-line palette-stroke + endpoint symbol/arrow visual stage is absent (series falls back to shared style stage)

#### 🟡 `EChartsKit/chart/scatter/ScatterView.swift`  · minor · 80% · todos=0
<sub>↔ `echarts/src/chart/scatter/ScatterView.ts`</sub>

Scatter chart view; static render using real SymbolDraw/LargeSymbolDraw over 5 coord systems, but omits clip and the incremental/transform pipeline.

- createSymbolDrawOpt clipShape (createCoordSysClipAreaSimply) omitted, so the default clip:true does not clip out-of-bounds points
- updateTransform not overridden: coord-system transform animation (geo/polar roam) won't re-layout points via updateLayout
- incrementalPrepareRender/incrementalRender not ported: large/progressive data renders single-pass with no progressive pipeline
- remove() not overridden: _symbolDraw.remove(true) leave cleanup skipped when the series is removed
- stacked scatter dim substitution (isDimensionStacked/stackResultDimension from pointsLayout) not wired, so stacked scatter plots un-stacked positions
- matrix coordinateSystem branch is an early-return no-op (upstream renders via generic pointsLayout)

#### 🟡 `EChartsKit/component/graphic/GraphicView.swift`  · minor · 82% · todos=0
<sub>↔ `echarts/src/component/graphic/GraphicView.ts`</sub>

Graphic component view (create/update/relocate/remove elements); rendering is faithful but several interaction/animation/back-compat branches are deferred to static no-ops.

- updateCommonAttrs drops upstream's on* event-handler assignment loop, so click/mouse handlers on graphic elements are never wired (no-op)
- graphicUtil.setTooltipConfig deferred: tooltip option on graphic elements is not configured
- isEC4CompatibleStyle/convertFromEC4CompatibleStyle deferred: EC4 legacy style/textConfig/textContent options are not converted
- updateCommonAttrs omits the `draggable` assignment: graphic elements cannot be dragged
- applyUpdateTransition/applyLeaveTransition/updateLeaveTo/updateProps replaced by direct el.attr: enter/update/leave transitions and x/y position tween do not animate (final state correct)

#### 🟡 `EChartsKit/coord/View.swift`  · minor · 82% · todos=0
<sub>↔ `echarts/src/coord/View.ts`</sub>

VIEW coord-sys transform machinery (raw/roam/overall trans, dataToPoint/pointToData/containPoint) — static + value-based-roam path at full parity; roam-animation sync-back flow deferred.

- calcCompensationScaleToPreserveNodeSize not ported — graph/tree/sankey nodeScaleRatio (keep node size constant on zoom) unavailable
- Roaming-animation syncBackEl path deferred: applyViewCoordSysTransToElement / calcOverallTransFromSyncBackEl / updateProps animation not ported
- invertBackToCenterOption percent-center round-trip omitted — sync-back always returns numeric center, so percent centerOption is lost on roam
- Action-handler roam entry points deferred: ownRoamModelCoordSysUpdateInAction, getOwnRoamViewCoordSys, ownRoamViewUpdateDirectlyInAction, syncBackRoamOptionToRoamHostModel model write-back
- CoordinateSystem/CoordinateSystemMaster protocol conformance dropped (documented; concrete View type used by Geo)

#### 🟡 `EChartsKit/animation/basicTransition.swift`  · minor · 85% · todos=0
<sub>↔ `echarts/src/animation/basicTransition.ts`</sub>

initProps/updateProps/removeElementWithFadeOut/getAnimationConfig transition helper; core path faithful, a few config-source branches deferred.

- getAnimationConfig does not consume ecModel.getUpdatePayload().animation, so dataZoom/resize global duration/easing/delay override is ignored
- function-valued animationDuration/animationDelay(dataIndex) dropped: transNum returns nil so per-index staggered enter delay/duration falls back to 0
- getAnimationDelayParams hook (pictorial-bar per-element delay) not wired into animateOrSetProps
- user removeOpt override on the leave path not modeled (leave still hardcodes 200ms/cubicOut)

#### 🟡 `EChartsKit/chart/chord/ChordPiece.swift`  · minor · 85% · todos=0
<sub>↔ `echarts/src/chart/chord/ChordPiece.ts`</sub>

Node Sector arc + label; shape/style/emphasis/normal-label faithful, but full setLabelStyle labelFetcher path is inlined to a minimal normal-state label.

- setLabelStyle labelStateModels not wired: per-state (emphasis/blur/select) label styles, defaultOpacity, and 'startArc' defaultOutsidePosition not applied
- graphic.updateProps({shape}) tween on non-firstCreate deferred (shape applied directly); port substitutes its own first-create endAngle sweep

#### 🟡 `EChartsKit/chart/graph/GraphSeries.swift`  · minor · 85% · todos=1
<sub>↔ `echarts/src/chart/graph/GraphSeries.ts`</sub>

Graph series model; option tree, categories data, tooltip, curveness all faithful, but the beforeLink getItemModel rebind path is dead (wrapMethod stub).

- beforeLink nodeData.wrapMethod('getItemModel') is a no-op stub, so per-category parentModel reparenting (category itemStyle/label styling) never applies
- edgeData wrapMethod resolveParentPath 'label'->'edgeLabel' redirect is a no-op stub (GraphView reimplements it only for labels, not model reads)
- mergeDefaultAndTheme skips defaultEmphasis(option,'edgeLabel',['show']) so edgeLabel emphasis show default not applied

#### 🟡 `EChartsKit/component/axis/AxisBuilder.swift`  · minor · 85% · todos=3
<sub>↔ `echarts/src/component/axis/AxisBuilder.ts`</sub>

Straight-line axis builder (line/arrows/ticks/labels/name); core render + break-label de-overlap ported, cross-axis name-overlap resolution and event/tooltip wiring deferred.

- Cross-axis name-overlap resolution is a no-op: resetOverlapRecordToShared/moveIfOverlap/moveIfOverlapByLinearLabels and shared.resolveAxisNameOverlap all deferred, so axis name is placed at nameGap without nudging away from labels
- buildAxisLabel per-category textStyle override (rawCategoryItem.textStyle -> new Model) not wired; labelModel used for all labels
- Function-form axisLabel.color callback dropped (ColorString==String); isFunction(textColor) branch not representable
- axisLine breakLine rendering deferred (getAxisBreakHelper nil); plain Line always drawn even when breakLine+hasBreaks
- setTooltipConfig and triggerEvent eventData / addBreakEventHandler on axis name and labels deferred
- nameMarginLevel margin-level defaults (DEFAULT_*_NAME_MARGIN_LEVELS) unused; name geometry margins not applied

#### 🟡 `EChartsKit/component/axis/CartesianAxisView.swift`  · minor · 85% · todos=0
<sub>↔ `echarts/src/component/axis/CartesianAxisView.ts`</sub>

Cartesian axis view (grid splitLine/minorSplitLine/splitArea/breakArea); split lines fully ported, splitArea bands and transition animation deferred.

- splitArea builder is a no-op: rectCoordAxisBuildSplitArea not ported, so alternating splitArea background bands are never drawn
- graphic.groupTransition between old/new axis group deferred; axis re-layout snaps without animation (final geometry correct)
- remove() no-op: rectCoordAxisHandleRemove (clears cached splitArea colors) not ported
- lineStylePropsFromDict does not bridge lineDash to LineDash enum; dashed split lines render solid

#### 🟡 `EChartsKit/component/dataZoom/SliderZoomView.swift`  · minor · 85% · todos=0
<sub>↔ `echarts/src/component/dataZoom/SliderZoomView.ts`</sub>

Slider dataZoom render half (layout/background/handles/labels/data-shadow/updateView); core render+labels present, some interaction/overlay omissions.

- _showDataInfo is a PortStub no-op: dragging a handle never reveals the emphasis handle-label and moveHandle never gets highlighted
- _renderDataShadow draws one area+line but omits the selectedDataBackground overlay and the 3-segment clip-path split of _updateView
- onmouseover/onmouseout (_onOverDataInfoTriggerArea) not wired on handles/moveZone, so _isOverDataInfoTriggerArea stays false and hover data-info never fires
- data-shadow simplifies upstream: no candlestick getShadowDim, no time-axis thisCoord mapping, no empty-value gap insertion

#### 🟡 `EChartsKit/component/marker/MarkAreaView.swift`  · minor · 85% · todos=3
<sub>↔ `echarts/src/component/marker/MarkAreaView.ts`</sub>

markArea polygon view: geometry/layout/overlap-clip/diff-render all faithfully ported; label, animation and bar-corner snapping deferred.

- Label block (setLabelStyle + getECData().dataModel) is a no-op; markArea labels never render — deferred pending MarkerModel DataFormatMixin/DataModel conformance
- getSingleMarkerEndPoint drops the seriesModel.getMarkerPosition branch, so bar/candlestick markArea corners are not snapped to category ticks
- 1D markArea items (single-object data) return nil in markAreaTransform and are silently dropped (upstream normalizes them earlier)
- updateProps is a no-animation shim; markArea does not animate on data change
- updateTransform (transform-only re-layout on zoom/pan) is defined but not wired into the render pipeline

#### 🟡 `EChartsKit/component/toolbox/ToolboxView.swift`  · minor · 85% · todos=0
<sub>↔ `echarts/src/component/toolbox/ToolboxView.ts`</sub>

Toolbox on-canvas view: icon paths, layout, background, emphasis/title-on-hover, click dispatch present; several interaction bits deferred.

- Title-overflow reposition block (isVertical\|\|group.eachChild emphasisState.textConfig) deferred; titles can render off-screen
- graphic.setTooltipConfig on icons deferred (no icon tooltips)
- payload.newTitle/featureName merge (FIX#11236 MagicType title update) not ported
- DataDiffer add/update/remove reduced to rebuild-each-render; removed features' dispose not called on re-render
- image:// icon branch of createIcon deferred (only path/svg icons)

#### 🟡 `EChartsKit/chart/sankey/SankeyView.swift`  · minor · 88% · todos=0
<sub>↔ `echarts/src/chart/sankey/SankeyView.ts`</sub>

Ribbon+node rendering, curvature bezier math, source/target/gradient edge fill, node/edge labels, drag, emphasis with adjacency/trajectory focus, and view-reuse morph all ported; a few decorative/state omissions remain.

- edge setStatesStylesFromModel omits the applyCurveStyle callback, so an emphasis-state lineStyle.color sentinel ('source'/'target'/'gradient') is not resolved to a real paint
- node/edge decal (setStyle('decal', getVisual('style').decal) and applyCurveStyle decal branches) is not bridged
- first-render grow-in clip animation (createGridClipShape width tween) replaced by a per-node opacity fade
- label labelFetcher.getFormattedLabel is called with dataType=nil instead of 'node'/'edge', and edge label skips the retrieve3 formatter-inheritance guard

#### 🟡 `EChartsKit/model/Series.swift`  · minor · 88% · todos=7
<sub>↔ `echarts/src/model/Series.ts`</sub>

SeriesModel base class; core lifecycle/selection/palette/tooltip/nearest-index all ported, several peripheral behaviors deferred.

- mergeDefaultAndTheme: fetchLayoutMode/getLayoutParams + final mergeLayoutParam (layout-mode box-position merge) deferred — box-layout series miss layout-param merging
- mergeDefaultAndTheme: modelUtil.defaultEmphasis(option,'label',['show']) top-level label emphasis default not applied
- fillDataTextStyle: per-item defaultEmphasis(data[i],'label',['show']) is a no-op loop — per-datum label emphasis default missing
- getData(dataType): getLinkedData(dataType) branch not ported — base always returns main data (graph/tree edge routing relies on subclass overrides)
- getAllData: getLinkedDataAll not ported — always returns [{data: mainData}]
- getCurrentTask always returns nil (Scheduler routing deferred to C2) — getData/setData never read a live task context.data, always fall back to inner.data

#### 🟡 `EChartsKit/chart/heatmap/HeatmapView.swift`  · minor · 90% · todos=0
<sub>↔ `echarts/src/chart/heatmap/HeatmapView.ts`</sub>

Heatmap view; cartesian path is full parity PLUS added morph/transition, and geo/calendar/matrix are all wired (more complete than the file's deferred notes suggest), with a few small omissions on the secondary coord paths.

- _renderOnCalendar and _renderOnMatrix omit setLabelStyle, so calendar/matrix heatmap cells render no per-cell value labels (upstream applies them in _renderOnGridLike)
- matrix and calendar cell Rects omit upstream's z2:1
- incremental path omits rect.incremental = getIncrementalId(...) and emphasis.hoverLayer = HOVER_LAYER_FOR_INCREMENTAL
- calendar path builds cells from dataToPoint±cellSize/2 rather than upstream dataToLayout().contentRect\|\|rect, ignoring cell-gap contentRect

#### 🟡 `EChartsKit/component/legend/LegendView.swift`  · minor · 90% · todos=2
<sub>↔ `echarts/src/component/legend/LegendView.ts`</sub>

LegendView: render/layoutInner/getLegendStyle/icon build/selector buttons/click+hover wiring all present; a few deferred interaction features.

- Per-item tooltip deferred: setTooltipConfig call in _createItem omitted, so legend item tooltip never shows
- triggerEvent packEventData deferred: legend items emit no eventData when triggerEvent:true
- Function-form formatter unsupported; only string formatter ('{name}' replace) is applied
- click omits upstream dispatchSelectAction's downplay-before/highlight-after sequence (only legendToggleSelect fired)
- Custom-series getLegendIcon receives iconRotate:0 instead of the symbolRotate option, dropping custom icon rotation

#### 🟡 `EChartsKit/component/legend/ScrollableLegendView.swift`  · minor · 90% · todos=1
<sub>↔ `echarts/src/component/legend/ScrollableLegendView.ts`</sub>

Scrollable (paged) legend view; rendering/layout/page-info logic is a faithful full port, only click-to-flip interaction is deferred.

- createPageButton omits the onclick binding, so page-arrow clicks never call _pageGo — user page-flip is a no-op
- pageFormatter function-callback path unsupported; only the {current}/{total} string template is handled
- scrollLegendZRColor bridges only string page-icon fill colors; gradient/pattern color objects dropped

#### 🟡 `EChartsKit/data/helper/linkSeriesData.swift`  · minor · 90% · todos=0
<sub>↔ `echarts/src/data/helper/linkSeriesData.ts`</sub>

Links list<->struct (graph/tree) via method-wrap injections; structurally faithful but some wrapped-method injections are registered-but-dormant.

- Transferable downSample/map and changable filterSelf/selectRange injections are stored but never fired, so struct.update() won't run on filter/selectRange (graph/tree dataZoom+sampling)

#### 🟡 `ZRenderKit/Element.swift`  · minor · 90% · todos=7
<sub>↔ `zrender/src/Element.ts`</sub>

Scene-graph keystone (Element/Transformable+Eventful, attr, states, animate, textContent, clipPath); faithful but reimplements the state-apply path and drops hover-layer + a few branches.

- updateInnerText omits the autoOverflowArea / overflowRect inverse-transform clamp → inside-text overflow area not computed
- Hover-layer machinery dropped: shouldUseHoverLayer always returns NO and useState/useStates never set __inHover, so no separate hover-layer promotion
- saveCurrentToNormalState omits the loop baking a running animateTo's final value into _normalState when a state change interrupts mid-flight
- _applyStateObj replaced by compute-full-target + animateTo (_computeRestoreTarget/_stateApply); claimed equivalent but is a divergent state-application implementation
- Legacy position/scale/origin array accessors (createLegacyProperty/enhanceArray) not ported (deprecated shims)

#### 🟡 `EChartsKit/util/states.swift`  · minor · 93% · todos=2
<sub>↔ `echarts/src/util/states.ts`</sub>

Emphasis/blur/select state engine; very faithful (all functions present), with a two-phase-collapse deviation and a couple of narrow behavioral divergences.

- blurComponent drops the `view.focusBlurEnabled` gate: blurs children of ANY component view rather than only opt-in views (Geo), over-blurring
- createBlurDefaultState omits getFromStateStyle's animator saveTo mining: opacity of an in-flight non-blur style animation is ignored when blurring
- setAsHighDownDispatcher does not copy highDownSilentOnTouch (ECElement not consumed): touch-silent highlight suppression is a no-op

## 4. 全部实质缺口文件（status = major / stub）

无论优先级，凡评为 major/stub 的文件都在此，按严重度 + 覆盖率升序。

| 文件 | 状态 | 覆盖 | 优先级 | 摘要 |
|------|------|-----:|--------|------|
| `EChartsKit/chart/boxplot/boxplotInstall.swift` | 🔴 stub | 30% | low | install() registration entry point; entirely commented-out, defers registerSeriesModel/View/Layout/Transform to the driver. |
| `EChartsKit/component/visualMap/installCommon.swift` | 🔴 stub | 100% | none | Install/registration boilerplate — file is documentation-only; the actual registration (models, views, subtype defaulter, action, encoding stage) is wired in ECharts.swift per the sanctioned install-in-driver convention, so no behavioral gap. |
| `EChartsKit/component/parallel/ParallelComponentView.swift` | 🟠 major | 20% | medium | Parallel component interaction view; the axis-expand pointer interaction (the entire behavioral content of ParallelView.ts) is deferred/stubbed, though the sibling ParallelAxisView backdrop drawer bundled in the same file works. |
| `EChartsKit/label/labelGuideHelper.swift` | 🟠 major | 35% | medium | Leader-line angle math for label guide lines; only the three angle-limiter functions are ported, the generic guide-line generation/styling system is deferred. |
| `EChartsKit/component/tooltip/TooltipView.swift` | 🟠 major | 40% | high | Deliberately SLIM TooltipView: only trigger:'item' + a ported trigger:'axis' show path; large swaths of upstream behavior deferred. |
| `EChartsKit/chart/graph/GraphView.swift` | 🟠 major | 55% | high | Static-subset view: node SymbolDraw + inline edges + adjacency focus + edge labels are wired, but force layout, roam, drag, arrows and thumbnail are all deferred. |
| `EChartsKit/component/timeline/SliderTimelineView.swift` | 🟠 major | 55% | high | Slider timeline view: static render path (layout/axis/ticks/labels/control/pointer) faithful, but the entire interaction layer is deferred. |
| `EChartsKit/label/LabelManager.swift` | 🟠 major | 55% | medium | Global labelLayout stage (collect/updateLayoutConfig/layout); the overlap-resolution path is ported but all label-line update and label animation is deferred. |
| `EChartsKit/chart/lines/LinesView.swift` | 🟠 major | 60% | high | Static/effect subset ChartView: straight/curved lines via ported LineDraw + inline polyline morph + wired EffectLine trail; several upstream render paths deferred. |
| `EChartsKit/util/graphic.swift` | 🟠 major | 65% | high | Partial port of the graphic util module: transform/geometry/shape-registry/createIcon slice is faithful, but several exported behaviors are unported here and nowhere else. |
| `EChartsKit/chart/map/MapView.swift` | 🟠 major | 70% | medium | Map chart view; upstream delegates all region drawing to MapDraw (not ported), so Swift inlines a static GeoJSON/SVG render + color-morph. Regions/fill/labels/symbols/basic emphasis work; interaction gaps. |
| `EChartsKit/chart/treemap/TreemapView.swift` | 🟠 major | 70% | high | Treemap chart view; static tile/label/upperLabel/drillDownIcon/hover-emphasis render is faithful, but the interactive drill/zoom subsystem and diff/animation are deferred. |
| `EChartsKit/component/geo/GeoView.swift` | 🟠 major | 70% | medium | Geo component view; upstream is a thin MapDraw delegate, the port inlines a large static subset of MapDraw (geoJSON + geoSVG builds, styles, labels, SVG states/hover) but leaves all interaction hooks deferred as no-ops. |
| `EChartsKit/chart/custom/CustomView.swift` | 🟠 major | 72% | high | CustomChartView: static render core (createEl+all shapes, shape/style/transform apply, makeRenderItem api, mergeChildren, static clipPath, basic textContent, data.diff enter/update/leave, keyframe animation, toggleHoverEmphasis) is faithfully ported; the transition/state/diff-animation layer is deferred (56 DEFERRED markers). |
| `EChartsKit/chart/helper/SymbolDraw.swift` | 🟠 major | 72% | medium | Per-point symbol diff renderer; normal updateData/updateLayout/remove faithful, but the entire large/progressive incremental pipeline is omitted. |
| `EChartsKit/chart/effectScatter/EffectScatterView.swift` | 🟠 major | 75% | medium | View delegates to SymbolDraw(EffectSymbol) with ripple rings; core render works but clip, roam and several coord systems are omitted. |
| `EChartsKit/chart/parallel/ParallelView.swift` | 🟠 major | 75% | medium | Parallel polyline chart view; core static render + hover emphasis faithful, but a declared STATIC SUBSET missing the progressive and clip-reveal paths. |
| `EChartsKit/component/axis/SingleAxisView.swift` | 🟠 major | 75% | medium | Single-axis view; splitLine builder fully ported, but the splitArea builder is a complete no-op. |
| `EChartsKit/component/marker/MarkerModel.swift` | 🟠 major | 75% | medium | Abstract marker model base: _mergeOption/per-series wiring/getData faithful, but DataFormatMixin conformance blocked, degrading label/tooltip/params. |
| `EChartsKit/chart/tree/TreeView.swift` | 🟠 major | 78% | medium | Tree chart view; orthogonal trees (nodes, curve/polyline edges, focus, expand-collapse, blur hook) fully ported, but radial label rotation, collapsed-node inner color, and roam node-scale are deferred. |
| `EChartsKit/util/layout.swift` | 🟠 major | 78% | medium | Component box-layout helpers; core getLayoutRect/box/positionElement/mergeLayoutParam/getCircleLayout faithful, but several exported helpers unported. |
| `EChartsKit/chart/bar/BarView.swift` | 🟠 major | 80% | high | BarView render; cartesian normal-mode path (diff add/update/remove, clip, background, updateStyle+label+emphasis) is fully faithful and polar Sector rendering is added, but realtimeSort machinery and borderRadius are non-functional. |
| `EChartsKit/chart/pie/PieView.swift` | 🟠 major | 80% | medium | PieView with faithful data.diff add/update/remove, expansion enter, labels+leader lines, emphasis; several interactive/enter features deferred. |
| `EChartsKit/core/ECharts.swift` | 🟠 major | 80% | medium | The ECharts driver: setOption/update/render/dispatchAction pipeline is extremely faithful, but a swath of public instance-API methods is unported. |
| `EChartsKit/visual/symbolVisual.swift` | 🟠 major | 80% | medium | seriesSymbolTask/dataSymbolTask populating symbol/symbolSize/etc visuals; literal path faithful but function-valued symbol props are not evaluated. |
| `EChartsKit/chart/radar/RadarView.swift` | 🟠 major | 82% | medium | RadarView: line/area rings, keyed data.diff, collapse-to-center entrance, symbols, and emphasis dispatch faithfully ported; several styling/label sub-behaviors deferred. |
| `EChartsKit/chart/sunburst/SunburstSeries.swift` | 🟠 major | 82% | medium | Series model: tree build, completeTreeValue, viewRoot reset, level models, aria decal — solid, but the levels[] per-node inheritance wiring and getDataParams are broken/deferred. |
| `EChartsKit/coord/axisModelCreator.swift` | 🟠 major | 82% | medium | Axis-model class generator; the AxisModel class body is fully ported but the module's registration purpose is stubbed. |
| `EChartsKit/chart/gauge/GaugeView.swift` | 🟠 major | 85% | medium | Gauge view: axisLine/ticks/labels/pointer-sweep/progress/anchor/title/detail + emphasis all present; several opt-in features deferred, verdict major. |
| `EChartsKit/coord/cartesian/Grid.swift` | 🟠 major | 85% | medium | Grid coordinate-system master (axis creation, onZero, alignTicks, resize, convert, tooltip axes); core faithful but the outerBounds/label-overflow shrink path is stubbed. |
| `EChartsKit/visual/visualSolution.swift` | 🟠 major | 88% | medium | createVisualMappings/replaceVisualOption/applyVisual/incrementalApplyVisual ported, but the hidden __alphaForOpacity slot leaks into the applied visual types. |

**缺口明细：**

- **`EChartsKit/chart/boxplot/boxplotInstall.swift`**
  - install() body is commented out; the four register* calls and registerBoxplotAxisHandlers are never invoked from this file (relies on unverified driver wiring)
  - Stale port-notes claim BoxplotView and boxplotTransform are 'NOT ported' though both sibling Swift files now exist and are implemented
- **`EChartsKit/component/parallel/ParallelComponentView.swift`**
  - The mousedown/mouseup/mousemove handler table is commented out and never registered via getZr().on, so axis-expand-on-click/mousemove never fires
  - _dispatchExpand body is commented; the parallelAxisExpand action is never dispatched even if the method is reached
  - createOrUpdate/debounceNextCall throttle wiring (axisExpandRate/axisExpandDebounce) not ported, so throttled expand dispatch is absent
  - checkTrigger gating (axisExpandable / axisExpandTriggerOn) unimplemented — interaction cannot be enabled
- **`EChartsKit/label/labelGuideHelper.swift`**
  - updateLabelLinePoints not ported: the candidate-anchor guide-line generation entry (getCandidateAnchor/nearestPointOnPath/nearestPointOnRect) is absent
  - setLabelLineStyle not ported: no generic label-line creation/state styling (show/smooth/lineStyle/showAbove) — charts must draw leader lines inline
  - getLabelLineStatesModels not ported: no per-state (normal/emphasis/blur/select) labelLine model resolution
  - buildLabelLinePath / setLabelLineState not ported: smooth bezier leader-line path building is absent
  - projectPointToArc / projectPointToRect not ported (only projectPointToLine present), so nearestPointOnPath arc/rect projection unavailable
- **`EChartsKit/component/tooltip/TooltipView.swift`**
  - formatter (string/function callback) override of default markup not ported → custom tooltip.formatter content unavailable
  - position option (callback / string 'top'/'inside' / [x,y] array) + confine not ported → only default below/right-of-pointer, clamped placement
  - showDelay/hideDelay + transitionDuration animation + throttled _updatePosition (createOrUpdate) not ported → shows/hides synchronously, no move tween
  - findPointFromSeries not ported → showTip action without x/y falls back to view centre instead of series layout point
  - _showComponentItemTooltip not ported → component (markPoint/geo/timeline) item tooltips unavailable
  - _tryShow dispatcher walk (dataByCoordSys build, legend/component branches) + globalListener not ported; caller must pre-resolve series/dataIndex
  - _updateContentNotChangedOnAxis / _keepShow no-change-position-only update path not ported
  - TooltipHTMLContent host absent: renderMode forced 'richText', so renderMode:'html'/'auto' ignored
- **`EChartsKit/chart/graph/GraphView.swift`**
  - _startForceLayoutIteration not driven; layout:'force' graphs never iterate/converge (only circular + simpleLayout render)
  - edgeSymbol from/toSymbol arrow markers (ECLinePath.setLinePoints) not drawn; edges are bare Line/BezierCurve
  - roam pan/zoom fully deferred: RoamController + applyViewCoordSysTransToElement + updateRoamControllerSimply not wired
  - node draggable (el.on('drag'/'dragend') per-layout reposition) not wired
  - circular rotateLabel via rotateNodeLabel deferred; node labels not rotated in circular layout
  - _renderThumbnail / thumbnailBridge deferred; no minimap thumbnail
  - _updateNodeAndLinkScale setSymbolScale (node/link roam scaling) deferred
- **`EChartsKit/component/timeline/SliderTimelineView.swift`**
  - _doPlayStop deferred: autoPlay never starts the advance timer, so the timeline never auto-advances
  - _updateTicksStatus deferred: tick symbols/labels before currentIndex never toggle the 'progress' state (no past-tick highlight)
  - onclick (_changeTimeline) not wired on ticks/labels/play/prev/next buttons: every click is a no-op
  - checkpoint pointer drag (_handlePointerDrag/_handlePointerDragend/_pointerChangeTimeline/_toAxisCoord) deferred: pointer not draggable
  - ensureState('emphasis'/'progress') + enableHoverEmphasis omitted on all elements: no hover emphasis
  - giveSymbol collapsed to create-only; pointerMoveTo animateTo branch absent, so pointer index changes never animate
  - remove()/dispose() (_clearTimer) not ported
- **`EChartsKit/label/LabelManager.swift`**
  - processLabelsOverall + _updateLabelLine not ported: per-frame generic label-line style/point update (setLabelLineStyle/updateLabelLinePoints) never runs
  - _animateLabels not ported: label position tween, fade-in initProps opacity animation, and value roll-up (animateLabelValue) are absent
  - updateLayoutConfig draggable branch deferred: label drag + createDragHandler(updateLabelLinePoints) not wired
  - updateLayoutConfig labelLinePoints override (guideLine.setShape) not applied
  - textEl.disableLabelLayout gate omitted in addLabelsOfSeries, so a label opting out of layout is still collected
- **`EChartsKit/chart/lines/LinesView.swift`**
  - `clip` option not wired — createClipPath(coordSys)+group.setClipPath omitted, so overflow clipping of lines is unavailable
  - Large mode (isLargeDraw / LargeLineDraw) not ported — large-mode lines series do not render
  - incrementalPrepareRender / incrementalRender / updateTransform / eachRendered not wired — progressive rendering and transform-only roam/zoom updates absent
  - fromSymbol/toSymbol arrow markers, per-line label, and emphasis/blur states deferred (finishBuildLine)
  - Only Cartesian2D coordinate system handled — polar/geo lines drop to resetPersistentElements() and draw nothing
- **`EChartsKit/util/graphic.swift`**
  - setTooltipConfig not ported anywhere -> component-level item tooltipConfig (title/legend/geo/graphic/timeline) is unavailable
  - clipRectByRect not ported (only inlined per-demo) -> custom-series rect-clip helper missing
  - groupTransition not ported -> parallel-axis (and legacy group) transition animation is a no-op
  - calcZ2Range not ported -> z2-range label-lifting computation absent
  - extendShape/extendPath not ported -> user shape/path extension API unavailable
- **`EChartsKit/chart/map/MapView.swift`**
  - MapDraw + RoamController not ported → map pan/zoom roam is a no-op (__updateOnOwnRoam, geoRoam self-roam short-circuit inert)
  - mapToggleSelect select action/state path deferred → region click-select does not function
  - region↔symbol hover link (onHoverStateChange→setStatesFlag on legend circle) deferred → symbols don't react to region hover
  - projectionStream (d3 clip/resample) omitted; only per-point dataToPoint projection used
  - emphasis/select/blur state styles use getItemStyle not getFixedItemStyle → state areaColor fixup missing
- **`EChartsKit/chart/treemap/TreemapView.swift`**
  - _initEvents node click (nodeClick zoomToNode / rootToNode / link windowOpen) is a no-op: clicking a tile never zooms or drills (treemapAction not ported)
  - _zoomToNode/_rootToNode dispatchAction deferred, and breadcrumb onSelect callback is empty: no drill/roll navigation at all
  - _onPan/_onZoom roam re-layout (treemapMove/treemapRender) replaced by a container-group transform: roam moves/scales tiles instead of re-laying-out the rootRect
  - _doAnimation (drill/roll re-root, fade-out-to-corner, fade-in) deferred; replaced by a simpler morph + opacity entrance fade
  - Hierarchical DataDiffer dualTravel replaced by static rebuild gated on node-count: no id-based element reuse across structural changes
  - renderBackground/renderContent emphasis/blur/select fills use setStatesStylesFromModel instead of upstream's state itemStyle with fill=borderColor, so state colors differ
- **`EChartsKit/component/geo/GeoView.swift`**
  - render's roam re-draw (__updateOnOwnRoam → mapDraw.__updateOnOwnRoam) is a documented no-op; geo pan/zoom does not re-render
  - _handleRegionClick → api.dispatchAction('geoToggleSelect') not wired; clicking a region toggles no selection
  - updateSelectStatus (traverse + enterSelect/leaveSelect per isSelected) not ported; selected-region highlight never applied
  - geoJSON region path draws only NORMAL itemStyle: no emphasis/select/blur states, no highDown dispatcher, so geoJSON region hover-emphasis is absent (only geoSVG has states)
  - findHighDownDispatchers geoJSON branch (_regionsGroupByName) returns nil; hover-link/highlight-by-name unsupported for geoJSON maps
- **`EChartsKit/chart/custom/CustomView.swift`**
  - Per-state STATES loop that calls updateElOnState (upstream doCreateOrUpdateEl L1084-1089) is deferred: renderItem emphasis/blur/select {style,shape} overrides never applied
  - applyUpdateTransition/applyLeaveTransition deferred: transition/enterFrom/leaveTo/during-driven prop tweening does not animate (static apply + removeElementWithFadeOut substitute)
  - Group-child by-name diff (diffGroupChildren via DataDiffer, $mergeChildren:'byName') deferred: children rebuilt by index each render, losing per-child identity/animation
  - Legacy ec4 style compat (convertFromEC4CompatibleStyle/isEC4CompatibleStyle) and deprecated api.style/api.styleEmphasis return best-effort raw visual bag only
  - style.decal pattern (createOrUpdatePatternFromDecal) deferred: decals ignored on custom elements
  - api.getZr() and api.getDevicePixelRatio() stubbed (return nil / 1.0)
  - per-state z (updateZForEachState) and ec4 z2EmphasisLift/z2SelectLift=1 default not written; uses generic Z2 lift
  - renderItem params.context shared across datums upstream but copied per-datum here (value type), losing cross-datum state stash
- **`EChartsKit/chart/helper/SymbolDraw.swift`**
  - incrementalPrepareUpdate/incrementalUpdate/eachRendered and _progressiveEls omitted — progressive (large-mode) symbol rendering unavailable
  - normalizeUpdateOpt not ported: opt passed as a bare isIgnore function is not coerced to {isIgnore}
- **`EChartsKit/chart/effectScatter/EffectScatterView.swift`**
  - createSymbolDrawOpt clipShape (createCoordSysClipAreaSimply) omitted, so the clip:true default is a no-op and symbols outside the coord area are not clipped
  - updateTransform (roam re-layout via pointsLayout.reset + updateLayout) not ported, so roam pan/zoom does not reposition ripples without a full render
  - _updateGroupTransform (matrix.clone of coordSys.getRoamTransform) not ported, so group roam transform is never applied
  - geo/singleAxis/matrix coordinate systems hit the else-branch early return, rendering nothing for effectScatter on those systems
  - remove() override (this._symbolDraw.remove(true)) not ported
- **`EChartsKit/chart/parallel/ParallelView.swift`**
  - incrementalRender is a full no-op: progressive/large-data render path (default progressive:300) draws nothing for datasets over the threshold
  - createGridClipShape enter clip-reveal animation (setClipPath growing rect) not ported; lines appear via an opacity-fade substitute
  - data.diff add/update/remove pipeline replaced by a count-gated morph; mismatched-count updates rebuild-and-snap instead of animating, and saveOldStyle update-transition unused
- **`EChartsKit/component/axis/SingleAxisView.swift`**
  - splitArea builder is a no-op: rectCoordAxisBuildSplitArea (axisSplitHelper) not ported, so single-axis splitArea bands never render
  - remove() no-op: rectCoordAxisHandleRemove not ported, cached splitArea colors not cleared
  - pathStyleFromDict does not map lineDash (deferred), so dashed splitLine styling is dropped
  - graphic.groupTransition deferred: no anid-matched transition animation on re-render
- **`EChartsKit/component/marker/MarkerModel.swift`**
  - fillLabel is a no-op: defaultEmphasis(opt,'label',['show']) is not applied, so per-item emphasis-label defaults are dropped
  - formatTooltip returns nil (getRawValue unavailable) — marker tooltips produce no markup
  - getDataParams omits the DataFormatMixin base computation (color/encode/dimensionNames/value formatting), only host-series patch applied
  - DataFormatMixin not conformed: getFormattedLabel/getRawValue from the mixin are unavailable on marker models
- **`EChartsKit/chart/tree/TreeView.swift`**
  - Radial label block (render() lines 389-444: rad/isLeft/setTextConfig rotation) deferred - radial-tree labels are unrotated and on the wrong side
  - symbolInnerColor (isExpand===false && children ? visualColor : neutral00) deferred - collapsed nodes lack the hollow inner-fill marker
  - _updateNodeAndLinkScale / calcCompensationScaleToPreserveNodeSize deferred - node symbols scale with zoom instead of preserving size under roam
  - drawEdge does not call setDefaultStateProxy(edge) (upstream line 555) - edge default state-transition proxy missing
  - Enter/remove animation (removeElement, fadeOut, source-old-layout grow-out) deferred - nodes/edges appear and vanish without tween
- **`EChartsKit/util/layout.swift`**
  - applyPreserveAspect not ported: preserveAspect 'cover'/'contain' for geo/graphic/image components is unavailable
  - fetchLayoutMode not ported: component layoutMode resolution for mergeLayoutParam callers is absent
  - getLayoutParams not ported: retrieve LOCATION_PARAMS from a source option object is missing
  - sizeCalculable not ported (option[width] \|\| (left&&right) size check)
  - createBoxLayoutReference omits the enableLayoutOnlyByCenter+dataToPoint POINT-kind branch and the __DEV__ error branch
  - vbox/hbox curried forwarders absent (no current consumer)
- **`EChartsKit/chart/bar/BarView.swift`**
  - realtimeSort entirely stubbed: _enableRealtimeSort/_dataSort/_updateSortWithinSameData/_dispatchInitSort/_isOrderChangedWithinSameData/_isOrderDifferentInView are no-ops → bar racing sort/reorder animation unavailable
  - itemStyle.borderRadius dropped: setShape('r', borderRadius) is a documented ZRenderKit no-op → bar corners never round
  - _incrementalRenderLarge is a no-op (createLarge incremental/progressive branch deferred) → progressive large-bar draw absent
  - setLabelValueAnimation deferred → bar label numeric roll-up animation missing
  - large-path mouse hit-test (largePathUpdateDataIndex throttle) deferred → tooltip/hover over large-mode bars cannot resolve dataIndex
  - polar roundCap (Sausage) and sector label rotation (setSectorTextRotation/getSectorCornerRadius) deferred → polar bars always square-capped, no rotated sector labels
- **`EChartsKit/chart/pie/PieView.swift`**
  - select-state selectedOffset dx/dy translate omitted: selecting a slice does not offset (explode) the sector/label/labelLine
  - getSectorCornerRadius not wired: itemStyle.borderRadius/innerCornerRadius ignored, cornerRadius forced to 0
  - animationType:'scale' r-grow enter and SSR scaleX/scaleY branch not ported; only 'expansion' enter supported
  - itemStyle.cursor (itemModel.getShallow('cursor')) never applied to the sector
  - select/blur state getSectorCornerRadius shape merges omitted; _updateLabel guards leader line on labelLine.show instead of labelPosition outer/outside
- **`EChartsKit/core/ECharts.swift`**
  - `convertToPixel`/`convertFromPixel` (data<->pixel coordinate conversion public API) not ported
  - `resize(opts)` not ported — no runtime resize / media-query re-resolve (driver takes fixed width/height at init)
  - `getOption()` (return current merged option tree) not ported
  - `getVisual(finder, visualType)` not ported
  - `clear`/`dispose`/`isDisposed` instance lifecycle not ported (no _disposed flag)
  - `showLoading`/`hideLoading` loading spinner not ported
  - `appendData` streaming/incremental data API not ported
  - module-level `connect`/`disconnect` cross-chart event mirroring not wired (MessageCenter exists but connect() absent)
  - `refineEvent` path unported: refined 'selectchanged' event never emitted (only non-refined select/unselect/toggleselect)
  - legacy dataSelectAction events (pieselectchanged/mapselectchanged/selected) not re-emitted
  - Scheduler progressive/large-mode incremental rendering + updateStreamModes framing not reproduced (renderTask runs synchronously)
  - `makeActionFromEvent` not ported
- **`EChartsKit/visual/symbolVisual.swift`**
  - Function-valued symbol props (symbolSize/symbol/symbolRotate/symbolOffset callbacks) not evaluated per data item — the seriesSymbolTask dataEach callback branch is not ported
  - dataSymbolTask omits the ecModel.isSeriesFiltered(seriesModel) skip and the performRawSeries/createOnAllSeries scheduler flags (invoked inline from views instead)
- **`EChartsKit/chart/radar/RadarView.swift`**
  - Per-vertex value label block (upstream setLabelStyle loop lines 251-265) not ported — radar label.show shows no vertex values
  - Per-state polygon.ensureState(stateName).ignore + per-state polyline/polygon/symbol itemStyle loop (lines 209-222) not applied
  - Vertex symbols ignore symbolRotate (createSymbol applies rotation upstream)
  - Vertex symbols don't apply full itemStyle/setColor/strokeNoScale (only createSymbol fill param)
  - ZRImage image-symbol branch (lines 236-244) deferred
- **`EChartsKit/chart/sunburst/SunburstSeries.swift`**
  - beforeLink wrapMethod('getItemModel') injection never fires (SeriesData.wrapMethod can't rebind Model-returning methods) so per-node model.parentModel=levelModel is dropped -> levels[] itemStyle/label not inherited
  - getDataParams override deferred (wrapTreePathInfo stub) so params.treePathInfo is absent from tooltip/label formatters
- **`EChartsKit/coord/axisModelCreator.swift`**
  - registerComponentModel is a PORT-STUB no-op — creator-generated per-type axis model classes are never registered (ECharts.swift hand-written stand-in models serve instead)
  - registerSubTypeDefaulter is a PORT-STUB no-op — component sub-type inference from option not consulted for non-axis components
  - mergeDefaultAndTheme drops fetchLayoutMode/getLayoutParams/mergeLayoutParam branch — axis box-layout params (single/parallel axis positioning) not merged
- **`EChartsKit/chart/gauge/GaugeView.swift`**
  - roundCap:true uses Sector not Sausage, so axisLine and progress arcs render square caps instead of round
  - detail valueAnimation count-up not driven: setLabelValueAnimation/animateLabelValue call sites omitted, detail updates to final value without tween
  - formatLabel function-callback formatter is a no-op (only the string '{value}' replacement branch works)
  - pointer icon of image:// form: the `pointer instanceof ZRImage` useStyle branch is deferred
  - title/detail/label built with minimal gaugeTextStyle (font/fill/align only) not createTextStyle, dropping textBorder/shadow/rich styling
- **`EChartsKit/coord/cartesian/Grid.swift`**
  - layOutGridByOuterBounds is fully stubbed (returns noPxChange=true, no shrink) so grid.outerBounds and containLabel-without-legacy-impl never shrink the grid rect for label/name overflow
  - resolveAxisNameOverlapForGrid deferred: cross-perpendicular-axis name-overlap nudging (moveIfOverlapByLinearLabels) not applied; uses default resolver
  - createOrUpdateAxesView skips calcNameMarginLevel/nameMarginLevelMap so axis-name margins are not scaled by relative grid size
- **`EChartsKit/visual/visualSolution.swift`**
  - __alphaForOpacity stored under a literal dict key is NOT filtered by prepareVisualTypes (contrary to the code comment), so an opacity visualMap/brush applies an extra colorAlpha, wrongly modifying item color alpha
  - createMappings prototype-hidden-field trick is only partially emulated: the hidden slot is iterable, unlike upstream where hasOwnProperty iteration skips it

## 5. 完整逐文件表（按模块）

### Animation  (4)

| 文件 | 状态 | 覆盖 | 优先级 | todos | 缺口 |
|------|------|-----:|--------|------:|------|
| `Animation.swift` | 🟢 parity | 98% | none | 2 | — |
| `Animator.swift` | 🟢 parity | 97% | none | 8 | — |
| `Clip.swift` | 🟢 parity | 100% | none | 1 | — |
| `easing.swift` | 🟢 parity | 100% | none | 0 | — |

### Contain  (9)

| 文件 | 状态 | 覆盖 | 优先级 | todos | 缺口 |
|------|------|-----:|--------|------:|------|
| `ContainArc.swift` | 🟢 parity | 100% | none | 1 | — |
| `ContainLine.swift` | 🟢 parity | 100% | none | 0 | — |
| `ContainPath.swift` | 🟢 parity | 100% | none | 5 | — |
| `ContainPolygon.swift` | 🟢 parity | 100% | none | 0 | — |
| `ContainText.swift` | 🟢 parity | 100% | none | 4 | — |
| `containUtil.swift` | 🟢 parity | 100% | none | 0 | — |
| `cubic.swift` | 🟢 parity | 100% | none | 0 | — |
| `quadratic.swift` | 🟢 parity | 100% | none | 0 | — |
| `windingLine.swift` | 🟢 parity | 100% | none | 0 | — |

### Core  (19)

| 文件 | 状态 | 覆盖 | 优先级 | todos | 缺口 |
|------|------|-----:|--------|------:|------|
| `Eventful.swift` | 🟡 minor | 90% | low | 1 | off(eventType, handler) cannot filter one handler by identity (closures not comparable) -> silently fails to unregister that handler；on() dedup loop (_h[i].h === handler) not ported -> re-binding the same closure registers it twice and fires it twice |
| `LRU.swift` | 🟡 minor | 98% | low | 0 | LRUKey models string\|number as a tagged enum: .number(1) and .string("1") are distinct, unlike JS which coerces numeric keys to strings and collides them |
| `WeakMap.swift` | 🟡 minor | 95% | low | 0 | has()/delete() return presence-based booleans, not upstream's `!!value` truthiness — a stored falsy value (0/''/false) reads has()==true where upstream returns false |
| `env.swift` | 🟡 minor | 90% | low | 0 | configureNativeEnv overrides touchEventsSupported/transformSupported/transform3dSupported to true, diverging from upstream node branch defaults (deliberate native deviation)；detect() UA browser-detection path is never invoked on iOS (dead code, translated only for diffability) |
| `event.swift` | 🟡 minor | 92% | low | 2 | transformCoordWithViewport is a nil stub (CSS-transform viewport mapping from dom.ts not ported; native UIKit bridge supplies zrX/zrY instead)；calculateZrXY yields (0,0) whenever reached because env.domSupported is false on native (path is bypassed since bridge pre-populates zrX) |
| `platform.swift` | 🟡 minor | 75% | low | 2 | createCanvas always returns nil and loadImage is a no-op returning nil (upstream creates a real HTMLCanvasElement / new Image()), so image loading via platformApi is unavailable；setPlatformAPI replaces the global platformApi wholesale instead of upstream's per-key partial merge, so single-method overrides drop the other methods |
| `util.swift` | 🟡 minor | 60% | low | 3 | each/map/reduce/filter/find only accept arrays; upstream also iterates Dictionary objects and ArrayLike；createHashMap/HashMap Map-shim not ported (callers must use Swift Dictionary)；isFunction uses a String(describing:type) '->' heuristic; isObject uses Mirror .class — approximations, not exact typeof semantics；bind/curry/inherits/mixin/slice/trim/isPrimitive/hasOwn/concatArray not ported (idio… |
| `BoundingRect.swift` | 🟢 parity | 100% | none | 0 | — |
| `GestureMgr.swift` | 🟢 parity | 98% | none | 0 | — |
| `OrientedBoundingRect.swift` | 🟢 parity | 100% | none | 1 | — |
| `PathProxy.swift` | 🟢 parity | 98% | none | 9 | — |
| `PathRebuilder.swift` | 🟢 parity | 100% | none | 0 | — |
| `Point.swift` | 🟢 parity | 100% | none | 0 | — |
| `Transformable.swift` | 🟢 parity | 99% | none | 2 | — |
| `bbox.swift` | 🟢 parity | 100% | none | 0 | — |
| `curve.swift` | 🟢 parity | 100% | none | 0 | — |
| `matrix.swift` | 🟢 parity | 100% | none | 0 | — |
| `types.swift` | 🟢 parity | 98% | none | 1 | — |
| `vector.swift` | 🟢 parity | 100% | none | 0 | — |

### Graphic  (34)

| 文件 | 状态 | 覆盖 | 优先级 | todos | 缺口 |
|------|------|-----:|--------|------:|------|
| `Displayable.swift` | 🟡 minor | 92% | low | 1 | _applyStateObj drops the whole style transition/merge body (createStyle+_mergeStyle+_transitionState, inHoverOnlyStyleChange, PRIMARY_STATES_KEYS z/z2/invisible apply); only calls super.；_innerSaveToNormal does not clone this.style into _normalState.style nor _savePrimaryToNormal the z/z2/invisible keys.；_mergeStates does not merge each state's style into mergedState.style. |
| `Path.swift` | 🟡 minor | 95% | low | 4 | _applyStateObj/_innerSaveToNormal/_mergeStates omit upstream shape-state merge/clone bodies; state-driven shape transitions routed through the live useState->animateTo path instead |
| `Pattern.swift` | 🟡 minor | 90% | low | 0 | image typed as String only; the ImageLike (native image-object) arm of the pattern source is a deferred seam, so image-object patterns are not representable |
| `TSpan.swift` | 🟡 minor | 97% | low | 0 | DEFAULT_TSPAN_STYLE omits DEFAULT_PATH_STYLE.lineJoin default, so stroked-text corner joins default differently |
| `Text.swift` | 🟡 minor | 95% | low | 0 | getFill/getStroke gradient/pattern branch (returns '#000' upstream) unreachable: fill/stroke are String, so gradient/pattern text fill/stroke unrepresentable；parseRichText backgroundColor.image token-width-from-image-size branch deferred (needs image-loading seam); token width falls back to measured text width；setSeparateFont drops the string arm of token fontSize (e.g. '12px'); svg-only field,… |
| `CompoundPath.swift` | 🟢 parity | 100% | none | 0 | — |
| `Gradient.swift` | 🟢 parity | 100% | none | 1 | — |
| `Group.swift` | 🟢 parity | 100% | none | 5 | — |
| `poly.swift` | 🟢 parity | 100% | none | 0 | — |
| `roundRect.swift` | 🟢 parity | 100% | none | 0 | — |
| `roundSector.swift` | 🟢 parity | 100% | none | 2 | — |
| `smoothBezier.swift` | 🟢 parity | 100% | none | 0 | — |
| `subPixelOptimize.swift` | 🟢 parity | 100% | none | 0 | — |
| `Image.swift` | 🟢 parity | 98% | none | 0 | — |
| `IncrementalDisplayable.swift` | 🟢 parity | 100% | none | 1 | — |
| `LinearGradient.swift` | 🟢 parity | 100% | none | 0 | — |
| `RadialGradient.swift` | 🟢 parity | 100% | none | 0 | — |
| `Arc.swift` | 🟢 parity | 100% | none | 0 | — |
| `BezierCurve.swift` | 🟢 parity | 100% | none | 0 | — |
| `Circle.swift` | 🟢 parity | 100% | none | 0 | — |
| `Droplet.swift` | 🟢 parity | 100% | none | 0 | — |
| `Ellipse.swift` | 🟢 parity | 100% | none | 0 | — |
| `Heart.swift` | 🟢 parity | 100% | none | 0 | — |
| `Isogon.swift` | 🟢 parity | 100% | none | 0 | — |
| `Line.swift` | 🟢 parity | 100% | none | 0 | — |
| `Polygon.swift` | 🟢 parity | 100% | none | 0 | — |
| `Polyline.swift` | 🟢 parity | 100% | none | 0 | — |
| `Rect.swift` | 🟢 parity | 100% | none | 0 | — |
| `Ring.swift` | 🟢 parity | 100% | none | 0 | — |
| `Rose.swift` | 🟢 parity | 100% | none | 0 | — |
| `Sector.swift` | 🟢 parity | 100% | none | 0 | — |
| `Star.swift` | 🟢 parity | 100% | none | 0 | — |
| `Trochoid.swift` | 🟢 parity | 100% | none | 0 | — |
| `constants.swift` | 🟢 parity | 100% | none | 0 | — |

### Tool  (7)

| 文件 | 状态 | 覆盖 | 优先级 | todos | 缺口 |
|------|------|-----:|--------|------:|------|
| `ToolPath.swift` | 🟡 minor | 95% | low | 5 | clonePath does not reassign path.buildPath = sourcePath.buildPath; a cloned SVGPath/custom-buildPath element renders base no-op geometry (only setShape carried)；buildPath/mergePath skip the getContext()/rebuildPath(ctx,1) Canvas2D percent-draw rebuild (sanctioned §9 renderer seam; native rebuilds from appended proxy)；clonePath setStyle uses replace (useStyle) not upstream's merge into default s… |
| `color.swift` | 🟢 parity | 99% | none | 2 | — |
| `convertPath.swift` | 🟢 parity | 100% | none | 2 | — |
| `dividePath.swift` | 🟢 parity | 99% | none | 9 | — |
| `morphPath.swift` | 🟢 parity | 99% | none | 1 | — |
| `parseSVG.swift` | 🟢 parity | 100% | none | 6 | — |
| `transformPath.swift` | 🟢 parity | 100% | none | 2 | — |

### ZRenderKit  (5)

| 文件 | 状态 | 覆盖 | 优先级 | todos | 缺口 |
|------|------|-----:|--------|------:|------|
| `Element.swift` | 🟡 minor | 90% | medium | 7 | updateInnerText omits the autoOverflowArea / overflowRect inverse-transform clamp → inside-text overflow area not computed；Hover-layer machinery dropped: shouldUseHoverLayer always returns NO and useState/useStates never set __inHover, so no separate hover-layer promotion；saveCurrentToNormalState omits the loop baking a running animateTo's final value into _normalState when a state change inter… |
| `Handler.swift` | 🟡 minor | 93% | low | 3 | dispatchToElement omits the el[onEventName] handler-prop path (onclick/onmousedown…) — only the .on() listener path fires (documented native seam)；dispatchToElement omits the CanvasPainter.eachOtherLayer user-layer event fan-out (canvas-only)；processGesture substitutes a sentinel Displayable for an empty-space pinch target instead of upstream's undefined, and dispatches the wrapped event |
| `ZRender.swift` | 🟡 minor | 92% | low | 0 | _refresh's refreshHover path never paints a hover layer (painter.refresh only runs for the normal-layer branch) — hover-layer rendering deferred；opts.useDirtyRect is stored but the dirty-rect render optimization is not implemented (always full repaint; performance, not correctness)；useCoarsePointer === 'auto' env.touchEventsSupported defaulting not modeled — only an explicit opts.pointerSize is… |
| `config.swift` | 🟡 minor | 97% | low | 0 | getDevicePixelRatio always returns 1 — the window.devicePixelRatio / screen.deviceXDPI branch is dropped (documented iOS native seam) |
| `Storage.swift` | 🟢 parity | 99% | none | 1 | — |

### animation  (4)

| 文件 | 状态 | 覆盖 | 优先级 | todos | 缺口 |
|------|------|-----:|--------|------:|------|
| `basicTransition.swift` | 🟡 minor | 85% | medium | 0 | getAnimationConfig does not consume ecModel.getUpdatePayload().animation, so dataZoom/resize global duration/easing/delay override is ignored；function-valued animationDuration/animationDelay(dataIndex) dropped: transNum returns nil so per-index staggered enter delay/duration falls back to 0；getAnimationDelayParams hook (pictorial-bar per-element delay) not wired into animateOrSetProps；user remo… |
| `customGraphicKeyframeAnimation.swift` | 🟢 parity | 98% | none | 0 | __DEV__ 'End frame with percent:1 missing' warn() not ported (dev-only diagnostic, no runtime effect) |
| `morphTransitionHelper.swift` | 🟢 parity | 98% | none | 0 | — |
| `universalTransition.swift` | 🟢 parity | 97% | none | 11 | animateFrom style targets are projected onto a fixed animatable-key list (pathStyleToAnimTarget), dropping non-tweenable keys like lineDash/lineCap/blend — documented no-op, no observable morph difference |

### chart  (127)

| 文件 | 状态 | 覆盖 | 优先级 | todos | 缺口 |
|------|------|-----:|--------|------:|------|
| `boxplotInstall.swift` | 🔴 stub | 30% | low | 0 | install() body is commented out; the four register* calls and registerBoxplotAxisHandlers are never invoked from this file (relies on unverified driver wiring)；Stale port-notes claim BoxplotView and boxplotTransform are 'NOT ported' though both sibling Swift files now exist and are implemented |
| `BarView.swift` | 🟠 major | 80% | high | 0 | realtimeSort entirely stubbed: _enableRealtimeSort/_dataSort/_updateSortWithinSameData/_dispatchInitSort/_isOrderChangedWithinSameData/_isOrderDifferentInView are no-ops → bar racing sort/reorder animation unavailable；itemStyle.borderRadius dropped: setShape('r', borderRadius) is a documented ZRenderKit no-op → bar corners never round；_incrementalRenderLarge is a no-op (createLarge incremental/… |
| `CustomView.swift` | 🟠 major | 72% | high | 1 | Per-state STATES loop that calls updateElOnState (upstream doCreateOrUpdateEl L1084-1089) is deferred: renderItem emphasis/blur/select {style,shape} overrides never applied；applyUpdateTransition/applyLeaveTransition deferred: transition/enterFrom/leaveTo/during-driven prop tweening does not animate (static apply + removeElementWithFadeOut substitute)；Group-child by-name diff (diffGroupChildren … |
| `EffectScatterView.swift` | 🟠 major | 75% | medium | 0 | createSymbolDrawOpt clipShape (createCoordSysClipAreaSimply) omitted, so the clip:true default is a no-op and symbols outside the coord area are not clipped；updateTransform (roam re-layout via pointsLayout.reset + updateLayout) not ported, so roam pan/zoom does not reposition ripples without a full render；_updateGroupTransform (matrix.clone of coordSys.getRoamTransform) not ported, so group roa… |
| `GaugeView.swift` | 🟠 major | 85% | medium | 0 | roundCap:true uses Sector not Sausage, so axisLine and progress arcs render square caps instead of round；detail valueAnimation count-up not driven: setLabelValueAnimation/animateLabelValue call sites omitted, detail updates to final value without tween；formatLabel function-callback formatter is a no-op (only the string '{value}' replacement branch works)；pointer icon of image:// form: the `poin… |
| `GraphView.swift` | 🟠 major | 55% | high | 0 | _startForceLayoutIteration not driven; layout:'force' graphs never iterate/converge (only circular + simpleLayout render)；edgeSymbol from/toSymbol arrow markers (ECLinePath.setLinePoints) not drawn; edges are bare Line/BezierCurve；roam pan/zoom fully deferred: RoamController + applyViewCoordSysTransToElement + updateRoamControllerSimply not wired；node draggable (el.on('drag'/'dragend') per-layo… |
| `SymbolDraw.swift` | 🟠 major | 72% | medium | 0 | incrementalPrepareUpdate/incrementalUpdate/eachRendered and _progressiveEls omitted — progressive (large-mode) symbol rendering unavailable；normalizeUpdateOpt not ported: opt passed as a bare isIgnore function is not coerced to {isIgnore} |
| `LinesView.swift` | 🟠 major | 60% | high | 0 | `clip` option not wired — createClipPath(coordSys)+group.setClipPath omitted, so overflow clipping of lines is unavailable；Large mode (isLargeDraw / LargeLineDraw) not ported — large-mode lines series do not render；incrementalPrepareRender / incrementalRender / updateTransform / eachRendered not wired — progressive rendering and transform-only roam/zoom updates absent；fromSymbol/toSymbol arrow … |
| `MapView.swift` | 🟠 major | 70% | medium | 0 | MapDraw + RoamController not ported → map pan/zoom roam is a no-op (__updateOnOwnRoam, geoRoam self-roam short-circuit inert)；mapToggleSelect select action/state path deferred → region click-select does not function；region↔symbol hover link (onHoverStateChange→setStatesFlag on legend circle) deferred → symbols don't react to region hover；projectionStream (d3 clip/resample) omitted; only per-poi… |
| `ParallelView.swift` | 🟠 major | 75% | medium | 0 | incrementalRender is a full no-op: progressive/large-data render path (default progressive:300) draws nothing for datasets over the threshold；createGridClipShape enter clip-reveal animation (setClipPath growing rect) not ported; lines appear via an opacity-fade substitute；data.diff add/update/remove pipeline replaced by a count-gated morph; mismatched-count updates rebuild-and-snap instead of a… |
| `PieView.swift` | 🟠 major | 80% | medium | 0 | select-state selectedOffset dx/dy translate omitted: selecting a slice does not offset (explode) the sector/label/labelLine；getSectorCornerRadius not wired: itemStyle.borderRadius/innerCornerRadius ignored, cornerRadius forced to 0；animationType:'scale' r-grow enter and SSR scaleX/scaleY branch not ported; only 'expansion' enter supported；itemStyle.cursor (itemModel.getShallow('cursor')) never … |
| `RadarView.swift` | 🟠 major | 82% | medium | 0 | Per-vertex value label block (upstream setLabelStyle loop lines 251-265) not ported — radar label.show shows no vertex values；Per-state polygon.ensureState(stateName).ignore + per-state polyline/polygon/symbol itemStyle loop (lines 209-222) not applied；Vertex symbols ignore symbolRotate (createSymbol applies rotation upstream)；Vertex symbols don't apply full itemStyle/setColor/strokeNoScale (on… |
| `SunburstSeries.swift` | 🟠 major | 82% | medium | 1 | beforeLink wrapMethod('getItemModel') injection never fires (SeriesData.wrapMethod can't rebind Model-returning methods) so per-node model.parentModel=levelModel is dropped -> levels[] itemStyle/label not inherited；getDataParams override deferred (wrapTreePathInfo stub) so params.treePathInfo is absent from tooltip/label formatters |
| `TreeView.swift` | 🟠 major | 78% | medium | 0 | Radial label block (render() lines 389-444: rad/isLeft/setTextConfig rotation) deferred - radial-tree labels are unrotated and on the wrong side；symbolInnerColor (isExpand===false && children ? visualColor : neutral00) deferred - collapsed nodes lack the hollow inner-fill marker；_updateNodeAndLinkScale / calcCompensationScaleToPreserveNodeSize deferred - node symbols scale with zoom instead of … |
| `TreemapView.swift` | 🟠 major | 70% | high | 2 | _initEvents node click (nodeClick zoomToNode / rootToNode / link windowOpen) is a no-op: clicking a tile never zooms or drills (treemapAction not ported)；_zoomToNode/_rootToNode dispatchAction deferred, and breadcrumb onSelect callback is empty: no drill/roll navigation at all；_onPan/_onZoom roam re-layout (treemapMove/treemapRender) replaced by a container-group transform: roam moves/scales ti… |
| `PictorialBarView.swift` | 🟡 minor | 88% | low | 0 | prepareLineWidth omits `valueLineWidth /= pathForLineWidth.getLineScale()`, so borderWidth on rotated/scaled symbols is mis-sized (inert when borderWidth=0 default)；createPath drops upstream's ZRImage/`image://` symbol branch (createSymbol emits no images) so image-symbol pictorial bars don't render；does not monkeypatch getAnimationDelayParams / __pictorialAnimationIndex, so per-repeat-symbol s… |
| `pictorialBarInstall.swift` | 🟡 minor | 85% | low | 0 | No code in this file; correctness of the 4 registrations (view, series, cross-series layout, progressive layout) + registerBarGridAxisHandlers depends on ECharts.installOnce wiring not verifiable here |
| `boxplotTransform.swift` | 🟡 minor | 88% | low | 0 | Does not port the SOURCE_FORMAT_ARRAY_ROWS guard/throwError; non-array-rows input is silently coerced to empty rows instead of erroring |
| `CandlestickSeries.swift` | 🟡 minor | 95% | low | 0 | addOrdinal index-prepend writes back to option.data (value types) instead of upstream's dual-alias trick; a later mergeOption not replacing data would double-prepend the category index |
| `CandlestickView.swift` | 🟡 minor | 90% | low | 0 | _incrementalRenderLarge / createLarge(progressiveEls, incremental) overload is a no-op stub → large+progressive streaming datasets don't render incrementally；Element.incremental / getIncrementalId not ported: _incrementalRenderNormal omits el.incremental assignment；eachRendered uses group.traverse instead of graphic.traverseElements; progressive-els traversal path deferred |
| `candlestickLayout.swift` | 🟡 minor | 95% | low | 0 | handler.plan set to nil instead of createRenderPlanner() → progressive chunk planning not represented (reset recomputes each pass, so normal render unaffected)；axisSnippets helpers (makeAxisStatKey/createBandWidthBasedAxisContainShapeHandler/createMetricsNonOrdinalLinearPositiveMinGap) are local stubs, not the shared upstream module |
| `candlestickVisual.swift` | 🟡 minor | 97% | low | 0 | handler.plan set to nil instead of createRenderPlanner() → progressive planning not represented (reset recomputes each pass) |
| `ChordEdge.swift` | 🟡 minor | 90% | low | 1 | saveOldStyle + graphic.updateProps({shape}) enter/update tween deferred; ribbons snap to final shape instead of morphing on data update；applyEdgeFill source/target branches drop edgeStyle.decal = node.getVisual('style').decal (Pattern not bridged) |
| `ChordPiece.swift` | 🟡 minor | 85% | medium | 0 | setLabelStyle labelStateModels not wired: per-state (emphasis/blur/select) label styles, defaultOpacity, and 'startArc' defaultOutsidePosition not applied；graphic.updateProps({shape}) tween on non-firstCreate deferred (shape applied directly); port substitutes its own first-create endAngle sweep |
| `ChordSeries.swift` | 🟡 minor | 92% | low | 1 | beforeLink resolveParentPath (redirect 'label'->'edgeLabel' via wrapMethod/getModel swap) is a no-op stub; edge label option paths resolve against 'label' not 'edgeLabel' |
| `ChordView.swift` | 🟡 minor | 85% | low | 0 | getECData(el).dataIndex tagging not wired on pieces or edges, so hover/tooltip/highlight cannot resolve the chord datum；first-render grow-in scale animation deferred (group.scaleX/Y=0.01 + parsePercent origin + graphic.initProps to 1); renders at final scale immediately；removeElementWithFadeOut on removed nodes/edges deferred; static rebuild drops elements instantly with no fade-out |
| `chordInstall.swift` | 🟡 minor | 100% | low | 0 | install() body is commented documentation only; correctness depends on the Orchestrate driver actually registering ChordView/ChordSeriesModel/chordCircularLayoutStageHandler/dataFilter('chord') |
| `effectScatterInstall.swift` | 🟡 minor | 85% | low | 0 | registerLayout(layoutPoints('effectScatter')) is not wired; per-datum placement is inlined in the view instead of a registered layout stage |
| `FunnelSeries.swift` | 🟡 minor | 92% | low | 0 | _defaultLabelLine is a deferred no-op: labelLine.show / emphasis.labelLine.show are not gated on label.show, and defaultEmphasis(labelLine) defaults are not applied |
| `FunnelView.swift` | 🟡 minor | 90% | low | 0 | setLabelLineStyle/getLabelLineStatesModels deferred: labelLine emphasis/blur/select per-state styling not applied (leader polyline drawn inline with a single stroke)；textGuideLineConfig.anchor is never set, so the label-guide anchor/turn-angle repositioning machinery is absent |
| `funnelLayout.swift` | 🟡 minor | 97% | low | 0 | isFunction(sort) branch is a documented no-op: a user-supplied JS comparator function for `sort` is dropped (only 'ascending'/'descending'/'none' strings work) |
| `GraphSeries.swift` | 🟡 minor | 85% | medium | 1 | beforeLink nodeData.wrapMethod('getItemModel') is a no-op stub, so per-category parentModel reparenting (category itemStyle/label styling) never applies；edgeData wrapMethod resolveParentPath 'label'->'edgeLabel' redirect is a no-op stub (GraphView reimplements it only for labels, not model reads)；mergeDefaultAndTheme skips defaultEmphasis(option,'edgeLabel',['show']) so edgeLabel emphasis show … |
| `createView.swift` | 🟡 minor | 85% | low | 2 | getViewRect does not port applyPreserveAspect(seriesModel, viewRect, aspect) — view rect aspect-ratio preservation is skipped (aspect ignored)；Does not register through injectCoordSysByOption/createViewCoordSysSimply pipeline; a GraphViewCoordSys stand-in is assigned directly (View returns pixel not data-space rect) |
| `forceHelper.swift` | 🟡 minor | 95% | low | 0 | Math.random() init-position and degenerate-overlap tiebreak replaced by deterministic golden-ratio scatter (port bans Math.random) — settled layout is reproducible but differs from echarts.js pixel positions |
| `forceLayout.swift` | 🟡 minor | 95% | low | 0 | Replaces upstream's single forceInstance.step() with a synchronous settle loop (up to 1500 iters) because the live per-frame animation host is not ported — static frame shows settled not first-step layout |
| `graphHelper.swift` | 🟡 minor | 75% | low | 0 | getNodeGlobalScale never calls calcCompensationScaleToPreserveNodeSize for a view coord sys — always returns 1, so nodeScaleRatio/size-compensation under roam zoom is not applied |
| `HeatmapBlurLayer.swift` | 🟡 minor | 85% | low | 0 | _getGradient stores gradient alpha as clampU8(c[3]*255) not upstream's 0/1 Uint8ClampedArray rounding, so update()'s `gradient[+3]*alpha*256` overflows and clamps every heat pixel to full opacity (breaks the soft fade / minOpacity)；canvas shadowBlur Gaussian brush replaced by analytic smootherstep falloff in _getBrush; blob edge shape only approximates the Gaussian (sanctioned deviation) |
| `HeatmapView.swift` | 🟡 minor | 90% | medium | 0 | _renderOnCalendar and _renderOnMatrix omit setLabelStyle, so calendar/matrix heatmap cells render no per-cell value labels (upstream applies them in _renderOnGridLike)；matrix and calendar cell Rects omit upstream's z2:1；incremental path omits rect.incremental = getIncrementalId(...) and emphasis.hoverLayer = HOVER_LAYER_FOR_INCREMENTAL；calendar path builds cells from dataToPoint±cellSize/2 rath… |
| `ECLine.swift` | 🟡 minor | 92% | low | 0 | setLabelStyle inheritColor defaults to '#000' instead of upstream tokens.color.neutral99, so unstyled labels inherit black not off-white；curved-edge label uses chord tangent + quadratic midpoint approximation instead of line.tangentAt/pointAt(halfPercent), so curved label rotation/align can differ；beforeUpdate per-frame reposition replaced by build/update-time _positionEndsAndLabel; mid-animati… |
| `EffectSymbolElement.swift` | 🟡 minor | 88% | low | 0 | updateRipplePath uses effectCfg.color only; upstream's `rippleEffectColor \|\| color` is not honored, so rippleEffect.color option is ignored；rippleGroup.rotation from symbolRotate (`(symbolRotate\|\|0)*PI/180`) is never applied, so rings don't rotate with the symbol；fadeOut(cb) method omitted |
| `LargeSymbolDraw.swift` | 🟡 minor | 90% | low | 0 | incrementalUpdate renders the whole range in one path (no Float32Array subrange split / lastAdded merge); progressive/incremental draw driven by Scheduler task graph is not wired；canvas afterBrush fillRect boost replaced by largeSymbolBoostRects painter hook — equivalent output but different mechanism |
| `LineDraw.swift` | 🟡 minor | 90% | low | 0 | incrementalPrepareUpdate / incrementalUpdate / eachRendered and _progressiveEls are not ported, so progressive/streaming line rendering is unavailable (deferred like SymbolDraw) |
| `SymbolElement.swift` | 🟡 minor | 90% | low | 0 | ZRImage image-symbol branch in _updateCommon deferred (image symbols not styled/created)；fadeOut animates opacity only; scaleX/scaleY→0 and the fadeLabel text-fade branch deferred；__isEmptyBrush empty-brush style-clone branch not ported (empty symbols may mutate shared visual style) |
| `treeHelper.swift` | 🟡 minor | 78% | low | 0 | wrapTreePathInfo not ported — treePathInfo (name/dataIndex/value chain) for tree/sunburst/treemap getDataParams tooltips unavailable |
| `LineSeries.swift` | 🟡 minor | 85% | low | 0 | defaultOption omits `emphasis: { scale: true }` so line symbols do not scale on hover by default；defaultOption omits `label: { position: 'top' }`, changing default line-label placement；defaultOption omits `universalTransition: { divideShape: 'clone' }` default for morph transitions；getLegendIcon drops upstream's symbolRotate / iconRotate:'inherit' rotation + setOrigin handling |
| `LineView.swift` | 🟡 minor | 96% | low | 7 | `disableLabelAnimation = true` deferred in _initSymbolLabelAnimation/_initOrUpdateEndLabel — symbol/end labels may animate where upstream suppresses it；animationDelay/animationDuration callback (per-index function) form not modeled; only numeric delay is read；triggerLineEvent __DEV__ warnDeprecated warning omitted (behaviorally inert) |
| `EffectLine.swift` | 🟡 minor | 85% | low | 0 | Continuity-trail scaleY stretch for symbolType 'line'/'rect'/'roundRect' deferred (line 262); those effect symbols render without the trailing stretch (default 'circle' unaffected)；Upstream `symbol.setStyle(effectModel.getItemStyle(['color']))` not ported — effect.itemStyle (opacity/border) not applied to the trail symbol |
| `linesInstall.swift` | 🟡 minor | 75% | medium | 0 | registerVisual(linesVisual) not fulfilled — linesVisual is not ported/registered anywhere; per-line palette-stroke + endpoint symbol/arrow visual stage is absent (series falls back to shared style stage) |
| `linesLayout.swift` | 🟡 minor | 88% | low | 0 | `plan: createRenderPlanner()` set to nil (signature mismatch) — no per-render incremental/progressive planning split for lines；reset guards `coordSys as? Cartesian2D` only — polar/geo/calendar lines produce no layout (protocol-witness dataToPoint deviation) |
| `MapSeries.swift` | 🟡 minor | 95% | low | 2 | __ownRoamView() (RoamHostModel ownership of the geo View) is a documented no-op — roam ownership deferred；shared-geo center/zoom/scaleLimit live-view roam state not wired (only initial options read) |
| `mapInstall.swift` | 🟡 minor | 75% | low | 0 | createLegacyDataSelectAction('map', registerAction) is deferred → map region legacy select actions unavailable |
| `PieSeries.swift` | 🟡 minor | 95% | low | 0 | _defaultLabelLine deferred (no-op): labelLine.show is not gated off when label.show:false, so leader lines still draw |
| `SankeyView.swift` | 🟡 minor | 88% | medium | 0 | edge setStatesStylesFromModel omits the applyCurveStyle callback, so an emphasis-state lineStyle.color sentinel ('source'/'target'/'gradient') is not resolved to a real paint；node/edge decal (setStyle('decal', getVisual('style').decal) and applyCurveStyle decal branches) is not bridged；first-render grow-in clip animation (createGridClipShape width tween) replaced by a per-node opacity fade；labe… |
| `sankeyInstall.swift` | 🟡 minor | 60% | none | 0 | — |
| `sankeyVisual.swift` | 🟡 minor | 92% | low | 0 | sankeyMapValueToColor stand-in replaces VisualMapping; when dataExtent min==max (single/all-equal nodes) it clamps t=0 -> palette color[0], whereas VisualMapping's linearMap returns 0.5 -> mid-palette color, so equal-value node fills differ |
| `ScatterView.swift` | 🟡 minor | 80% | medium | 0 | createSymbolDrawOpt clipShape (createCoordSysClipAreaSimply) omitted, so the default clip:true does not clip out-of-bounds points；updateTransform not overridden: coord-system transform animation (geo/polar roam) won't re-layout points via updateLayout；incrementalPrepareRender/incrementalRender not ported: large/progressive data renders single-pass with no progressive pipeline；remove() not overr… |
| `SunburstPiece.swift` | 🟡 minor | 88% | low | 1 | Per-state label placement (x/y/rotation/align of DISPLAY_STATES emphasis/blur/select) deferred; only NORMAL-state geometry is applied；Per-state corner-radius shape augmentation deferred: setStatesStylesFromModel sets ensureState().style but not ensureState().shape；Entrance animation sweeps endAngle instead of upstream's r0->r radius expansion (documented intentional deviation) |
| `SunburstView.swift` | 🟡 minor | 88% | low | 0 | nodeClick:'link' branch (windowOpen open URL) is deferred — clicking a node configured with link does nothing；DataDiffer getId-keyed add/update/remove replaced by positional count-gated reuse (canMorph); identity changes at equal count morph the wrong pieces；renderRollUp always removes+recreates virtualPiece instead of updateData-morphing the existing roll-up sector on update |
| `sunburstAction.swift` | 🟡 minor | 95% | low | 0 | payload.direction = rollUp/drillDown write is a no-op (value-type Payload), only feeds the deferred entrance-animation routing |
| `sunburstInstall.swift` | 🟡 minor | 90% | low | 0 | No live registration code in-file; relies on the Orchestrate/Integrate driver to register the view/model/layout/visual and installSunburstAction |
| `ThemeRiverView.swift` | 🟡 minor | 85% | low | 0 | DataDiffer add/remove not ported: layer add/remove or per-layer sample-count change does group.removeAll() rebuild instead of keyed incremental diff, losing per-layer remove/enter transitions；createGridClipShape entrance (graphic.Rect clip expanding 0→rect.width+100) deferred; replaced by an opacity fade — different animation mechanism；saveOldStyle(polygon) not called on the update/morph path, … |
| `TreeSeries.swift` | 🟡 minor | 90% | low | 0 | beforeLink's nodeData.wrapMethod('getItemModel') is a no-op stub, so leaf nodes never reparent to leavesModel — `leaves` itemStyle/label/lineStyle options do not apply；getDataParams override not ported: tooltip params.treeAncestors (wrapTreePathInfo) and params.collapsed are absent |
| `Breadcrumb.swift` | 🟡 minor | 90% | low | 0 | onclick=curry(onSelect,itemNode) not wired: clicking a breadcrumb item never drills/zooms (onSelect is a no-op at the TreemapView call site anyway)；packEventData omits treePathInfo (wrapTreePathInfo deferred) so breadcrumb event data lacks the tree ancestor path；(el as ECElement).disableLabelAnimation = true is a documented no-op |
| `TreemapSeries.swift` | 🟡 minor | 92% | low | 0 | getDataParams override (treeAncestors/treePathInfo via wrapTreePathInfo) deferred: user formatter callbacks receive no tree-ancestor path；designatedVisualModel captured a copy of designatedVisualItemStyle, so treemapVisual's write-through to designatedVisualModel.get(['itemStyle',...]) is not observed (level-model path compensates) |
| `BarSeries.swift` | 🟢 parity | 98% | low | 0 | __preparePipelineContext override is not yet reached: Scheduler calls model.preparePipelineContext directly on base SeriesModel (documented dormant) |
| `BaseBarSeries.swift` | 🟢 parity | 97% | low | 0 | getMarkerPosition narrows coordinateSystem to Cartesian2D only; polar clampData branch out of scope (documented, polar markers) |
| `PictorialBarSeries.swift` | 🟢 parity | 97% | none | 0 | — |
| `BoxplotSeries.swift` | 🟢 parity | 96% | low | 1 | setOption idempotency divergence: index-prepended data is written back into self.option["data"], so a later mergeOption not replacing data could double-prepend the base index (documented POTENTIAL-BUG) |
| `BoxplotView.swift` | 🟢 parity | 97% | none | 0 | — |
| `boxplotLayout.swift` | 🟢 parity | 98% | none | 0 | — |
| `prepareBoxplotData.swift` | 🟢 parity | 100% | none | 0 | — |
| `preprocessor.swift` | 🟢 parity | 100% | none | 0 | — |
| `chordLayout.swift` | 🟢 parity | 100% | none | 0 | — |
| `CustomSeries.swift` | 🟢 parity | 98% | none | 0 | — |
| `customInstall.swift` | 🟢 parity | 100% | none | 0 | — |
| `customSeriesRegister.swift` | 🟢 parity | 100% | none | 0 | — |
| `EffectScatterSeries.swift` | 🟢 parity | 100% | none | 0 | — |
| `GaugeSeries.swift` | 🟢 parity | 100% | none | 0 | — |
| `PointerPath.swift` | 🟢 parity | 100% | none | 0 | — |
| `adjustEdge.swift` | 🟢 parity | 98% | none | 0 | — |
| `categoryFilter.swift` | 🟢 parity | 100% | none | 0 | — |
| `categoryVisual.swift` | 🟢 parity | 99% | none | 0 | — |
| `circularLayout.swift` | 🟢 parity | 100% | none | 0 | — |
| `circularLayoutHelper.swift` | 🟢 parity | 99% | none | 2 | — |
| `edgeVisual.swift` | 🟢 parity | 98% | none | 0 | — |
| `simpleLayout.swift` | 🟢 parity | 97% | none | 0 | — |
| `simpleLayoutHelper.swift` | 🟢 parity | 98% | none | 0 | — |
| `HeatmapSeries.swift` | 🟢 parity | 100% | none | 0 | — |
| `heatmapInstall.swift` | 🟢 parity | 100% | none | 0 | — |
| `createClipPathFromCoordSys.swift` | 🟢 parity | 100% | none | 0 | — |
| `createGraphFromNodeEdge.swift` | 🟢 parity | 100% | none | 2 | — |
| `createRenderPlanner.swift` | 🟢 parity | 100% | none | 1 | — |
| `createSeriesData.swift` | 🟢 parity | 100% | none | 0 | — |
| `createSeriesDataSimply.swift` | 🟢 parity | 100% | none | 0 | — |
| `enableAriaDecalForTree.swift` | 🟢 parity | 100% | none | 0 | — |
| `multipleGraphEdgeHelper.swift` | 🟢 parity | 100% | none | 0 | — |
| `sectorHelper.swift` | 🟢 parity | 100% | none | 0 | — |
| `lineAnimationDiff.swift` | 🟢 parity | 100% | none | 2 | — |
| `lineHelper.swift` | 🟢 parity | 100% | none | 0 | — |
| `poly.swift` | 🟢 parity | 100% | none | 0 | — |
| `LinesSeries.swift` | 🟢 parity | 97% | none | 0 | — |
| `mapDataStatistic.swift` | 🟢 parity | 100% | none | 1 | — |
| `mapSymbolLayout.swift` | 🟢 parity | 100% | none | 0 | — |
| `ParallelSeries.swift` | 🟢 parity | 100% | none | 0 | — |
| `parallelInstall.swift` | 🟢 parity | 100% | none | 0 | — |
| `parallelVisual.swift` | 🟢 parity | 100% | none | 0 | — |
| `labelLayout.swift` | 🟢 parity | 97% | none | 0 | — |
| `pieLayout.swift` | 🟢 parity | 98% | none | 1 | — |
| `RadarSeries.swift` | 🟢 parity | 100% | none | 0 | — |
| `backwardCompat.swift` | 🟢 parity | 100% | none | 0 | — |
| `radarLayout.swift` | 🟢 parity | 100% | none | 1 | — |
| `SankeySeries.swift` | 🟢 parity | 97% | low | 0 | __DEV__ throw for `levels[i].depth` missing/negative is dropped (invalid level is silently skipped instead) |
| `sankeyAction.swift` | 🟢 parity | 95% | low | 0 | query resolution only matches payload.seriesId, not seriesIndex/seriesName the upstream eachComponent query supports |
| `sankeyLayout.swift` | 🟢 parity | 99% | none | 0 | cyclic-data path calls fatalError instead of upstream's throwable Error (unrecoverable either way, so behaviorally equivalent) |
| `ScatterSeries.swift` | 🟢 parity | 100% | none | 0 | — |
| `sunburstLayout.swift` | 🟢 parity | 99% | none | 0 | — |
| `sunburstVisual.swift` | 🟢 parity | 98% | none | 0 | — |
| `ThemeRiverSeries.swift` | 🟢 parity | 98% | none | 1 | — |
| `themeRiverInstall.swift` | 🟢 parity | 100% | none | 0 | — |
| `themeRiverLayout.swift` | 🟢 parity | 100% | none | 0 | — |
| `layoutHelper.swift` | 🟢 parity | 100% | none | 0 | — |
| `traversalHelper.swift` | 🟢 parity | 100% | none | 0 | — |
| `treeAction.swift` | 🟢 parity | 98% | none | 0 | — |
| `treeLayout.swift` | 🟢 parity | 100% | none | 0 | — |
| `treeVisual.swift` | 🟢 parity | 100% | none | 1 | — |
| `treemapLayout.swift` | 🟢 parity | 100% | none | 2 | — |
| `treemapVisual.swift` | 🟢 parity | 98% | low | 0 | Adds a non-upstream fallbackPalette path (render-time ecModel palette as color range) to compensate for the value-type-copied empty level-0 range; behavior matches upstream output but is extra logic not in the source |

### component  (102)

| 文件 | 状态 | 覆盖 | 优先级 | todos | 缺口 |
|------|------|-----:|--------|------:|------|
| `installCommon.swift` | 🔴 stub | 100% | none | 0 | — |
| `SingleAxisView.swift` | 🟠 major | 75% | medium | 0 | splitArea builder is a no-op: rectCoordAxisBuildSplitArea (axisSplitHelper) not ported, so single-axis splitArea bands never render；remove() no-op: rectCoordAxisHandleRemove not ported, cached splitArea colors not cleared；pathStyleFromDict does not map lineDash (deferred), so dashed splitLine styling is dropped；graphic.groupTransition deferred: no anid-matched transition animation on re-render |
| `GeoView.swift` | 🟠 major | 70% | medium | 0 | render's roam re-draw (__updateOnOwnRoam → mapDraw.__updateOnOwnRoam) is a documented no-op; geo pan/zoom does not re-render；_handleRegionClick → api.dispatchAction('geoToggleSelect') not wired; clicking a region toggles no selection；updateSelectStatus (traverse + enterSelect/leaveSelect per isSelected) not ported; selected-region highlight never applied；geoJSON region path draws only NORMAL it… |
| `MarkerModel.swift` | 🟠 major | 75% | medium | 1 | fillLabel is a no-op: defaultEmphasis(opt,'label',['show']) is not applied, so per-item emphasis-label defaults are dropped；formatTooltip returns nil (getRawValue unavailable) — marker tooltips produce no markup；getDataParams omits the DataFormatMixin base computation (color/encode/dimensionNames/value formatting), only host-series patch applied；DataFormatMixin not conformed: getFormattedLabel/… |
| `ParallelComponentView.swift` | 🟠 major | 20% | medium | 0 | The mousedown/mouseup/mousemove handler table is commented out and never registered via getZr().on, so axis-expand-on-click/mousemove never fires；_dispatchExpand body is commented; the parallelAxisExpand action is never dispatched even if the method is reached；createOrUpdate/debounceNextCall throttle wiring (axisExpandRate/axisExpandDebounce) not ported, so throttled expand dispatch is absent；c… |
| `SliderTimelineView.swift` | 🟠 major | 55% | high | 2 | _doPlayStop deferred: autoPlay never starts the advance timer, so the timeline never auto-advances；_updateTicksStatus deferred: tick symbols/labels before currentIndex never toggle the 'progress' state (no past-tick highlight)；onclick (_changeTimeline) not wired on ticks/labels/play/prev/next buttons: every click is a no-op；checkpoint pointer drag (_handlePointerDrag/_handlePointerDragend/_poin… |
| `TooltipView.swift` | 🟠 major | 40% | high | 0 | formatter (string/function callback) override of default markup not ported → custom tooltip.formatter content unavailable；position option (callback / string 'top'/'inside' / [x,y] array) + confine not ported → only default below/right-of-pointer, clamped placement；showDelay/hideDelay + transitionDuration animation + throttled _updatePosition (createOrUpdate) not ported → shows/hides synchronous… |
| `AngleAxisView.swift` | 🟡 minor | 90% | low | 0 | axisLabel per-category textStyle override (rawCategoryData[tickValue].textStyle -> new Model) deferred; commonLabelModel used for every label；graphic.setTooltipConfig on axis labels deferred (no tooltip wiring)；pathStyleFromDict maps only String fill/stroke; gradient/pattern object color and lineDash not bridged |
| `AxisBuilder.swift` | 🟡 minor | 85% | medium | 3 | Cross-axis name-overlap resolution is a no-op: resetOverlapRecordToShared/moveIfOverlap/moveIfOverlapByLinearLabels and shared.resolveAxisNameOverlap all deferred, so axis name is placed at nameGap without nudging away from labels；buildAxisLabel per-category textStyle override (rawCategoryItem.textStyle -> new Model) not wired; labelModel used for all labels；Function-form axisLabel.color callba… |
| `CartesianAxisView.swift` | 🟡 minor | 85% | medium | 0 | splitArea builder is a no-op: rectCoordAxisBuildSplitArea not ported, so alternating splitArea background bands are never drawn；graphic.groupTransition between old/new axis group deferred; axis re-layout snaps without animation (final geometry correct)；remove() no-op: rectCoordAxisHandleRemove (clears cached splitArea colors) not ported；lineStylePropsFromDict does not bridge lineDash to LineDas… |
| `RadiusAxisView.swift` | 🟡 minor | 90% | low | 0 | graphic.groupTransition(oldAxisGroup,newAxisGroup) deferred: no anid-matched transition animation on re-render；layoutAxis z2:1 dropped (AxisBuilderCfg has no z2) so axis line/ticks not guaranteed drawn over splitLine/splitArea；pathStyleFromDict maps only String fill/stroke; gradient/pattern split colors silently dropped |
| `AxisPointerView.swift` | 🟡 minor | 90% | low | 0 | render() does not compute triggerOn from tooltip/axisPointer models nor register the updateAxisPointer globalListener; relocated to EChartsView host seam |
| `BaseAxisPointer.swift` | 🟡 minor | 92% | low | 1 | updateProps drops the moveAnimation graphic.updateProps transition branch (and lastProp memo) — crosshair/handle jump to position instead of animating; _moveAnimation computed but inert；zr add/remove of group and handle replaced by hostAdd/hostRemove/hostAddHandle seam closures (ExtensionAPI has no getZr) — sanctioned host deviation, but pointer is unhosted if integrator omits them |
| `axisTrigger.swift` | 🟡 minor | 88% | low | 6 | series.getAxisTooltipData branch not ported (candlestick/boxplot/themeRiver axis snap) — always uses default indicesOfNearest；linkGroup.mapper is never invoked (makeMapperParam deferred); linked-axis value passes through unmapped instead of scale.parse(mapper(...))；dispatchHighDownActually last-highlight store keyed on ExtensionAPI instead of api.getZr() (no getZr yet) — benign single-instance … |
| `findPointFromSeries.swift` | 🟡 minor | 95% | low | 0 | seriesModel.getTooltipPosition branch is a no-op (deferred): a cartesian series overriding getTooltipPosition gets dataToPoint fallback instead |
| `globalListener.swift` | 🟡 minor | 95% | low | 1 | handler fan-out is not throttled (util/throttle deferred) — upstream throttles; here handlers fire on every raw mousemove |
| `modelHelper.swift` | 🟡 minor | 93% | low | 0 | collectSeriesInfo only handles Cartesian2D and Single coordSys; polar (and other) series never populate axisInfo.seriesModels, so their trigger:'axis' tooltip series data is missing；LinkGroup.mapper stored opaquely; cross-axis link value mapping is deferred (invoked in axisTrigger, not here) |
| `brushVisual.swift` | 🟡 minor | 92% | low | 1 | throttle wrapper deferred: a non-zero throttleDelay emits brushselected on every drag step instead of at-most-once-per-window (default delay 0 matches upstream)；stepAParallel is a no-op (Parallel.hasAxisBrushed/eachActiveState unported): brushLink selection made on a parallel axis does not propagate to other series |
| `CalendarView.swift` | 🟡 minor | 90% | low | 0 | _formatterLabel isFunction(formatter) branch is a no-op: a function year/month/day label formatter falls through to nameMap instead of being invoked；calendarCreateTextStyle populates only text/font/fill; upstream createTextStyle adds rich-text/textBorder/shadow label style fields；calendarPathStyleFromDict maps only String fill/stroke; gradient/pattern itemStyle and lineStyle paints are not pars… |
| `SliderZoomView.swift` | 🟡 minor | 85% | medium | 0 | _showDataInfo is a PortStub no-op: dragging a handle never reveals the emphasis handle-label and moveHandle never gets highlighted；_renderDataShadow draws one area+line but omits the selectedDataBackground overlay and the 3-segment clip-path split of _updateView；onmouseover/onmouseout (_onOverDataInfoTriggerArea) not wired on handles/moveZone, so _isOverDataInfoTriggerArea stays false and hover… |
| `SliderZoomViewDrag.swift` | 🟡 minor | 90% | low | 0 | _onActualMoveZoneDrift/DragStart/DragEnd not ported: pan-drag on moveZone lacks the 'grabbing' cursor swap and _showDataInfo(true) reveal (wired via generic _wireDrift(.all) instead)；_onDragEnd calls _showDataInfo(false) which is a stubbed no-op, so end-of-drag label hide is inert |
| `dataZoomHistory.swift` | 🟡 minor | 98% | low | 0 | push() origin-range lookup matches any dataZoom by id instead of upstream's subType:'select' query (documented; toolbox-select subtype not ported) |
| `GraphicView.swift` | 🟡 minor | 82% | medium | 0 | updateCommonAttrs drops upstream's on* event-handler assignment loop, so click/mouse handlers on graphic elements are never wired (no-op)；graphicUtil.setTooltipConfig deferred: tooltip option on graphic elements is not configured；isEC4CompatibleStyle/convertFromEC4CompatibleStyle deferred: EC4 legacy style/textConfig/textContent options are not converted；updateCommonAttrs omits the `draggable` … |
| `RoamController.swift` | 🟡 minor | 95% | low | 0 | isAvailableBehavior string-config path ('ctrl'/'shift'/'alt') always returns false — modifier-key-gated roam is unavailable since ZRRawEvent lacks shiftKey/ctrlKey/altKey；removeUniformListener is a no-op (Eventful can't remove a specific closure); the empty uniform stays bound and fans out to nothing — faithful in effect, not a behavior change |
| `cursorHelper.swift` | 🟡 minor | 92% | low | 0 | reads coordinateSystem only via `as? SeriesModel`; upstream uses CoordinateSystemHostModel, so an axis/grid model covering the target skips the coordSys/z-order check and always allows roam |
| `LegendModel.swift` | 🟡 minor | 97% | low | 0 | Numeric legend.data names coerce to "" (get("name") as? String) since select/isSelected assume String; numeric names mis-key the selected map |
| `LegendView.swift` | 🟡 minor | 90% | medium | 2 | Per-item tooltip deferred: setTooltipConfig call in _createItem omitted, so legend item tooltip never shows；triggerEvent packEventData deferred: legend items emit no eventData when triggerEvent:true；Function-form formatter unsupported; only string formatter ('{name}' replace) is applied；click omits upstream dispatchSelectAction's downplay-before/highlight-after sequence (only legendToggleSelect… |
| `ScrollableLegendView.swift` | 🟡 minor | 90% | medium | 1 | createPageButton omits the onclick binding, so page-arrow clicks never call _pageGo — user page-flip is a no-op；pageFormatter function-callback path unsupported; only the {current}/{total} string template is handled；scrollLegendZRColor bridges only string page-icon fill colors; gradient/pattern color objects dropped |
| `MarkAreaView.swift` | 🟡 minor | 85% | medium | 3 | Label block (setLabelStyle + getECData().dataModel) is a no-op; markArea labels never render — deferred pending MarkerModel DataFormatMixin/DataModel conformance；getSingleMarkerEndPoint drops the seriesModel.getMarkerPosition branch, so bar/candlestick markArea corners are not snapped to category ticks；1D markArea items (single-object data) return nil in markAreaTransform and are silently dropp… |
| `MarkLineView.swift` | 🟡 minor | 90% | low | 5 | The `getECData(el).dataModel = mlModel` tooltip host-model tagging loop is deferred (MarkerModel not DataFormatMixin), so markLine tooltip/formatter won't resolve the model |
| `MarkPointView.swift` | 🟡 minor | 88% | low | 4 | Callback-in-data-item branch (function symbol/symbolSize/symbolRotate/symbolOffset invoked with getRawValue/getDataParams) is a no-op stub — function-valued item symbols ignored；The `getECData(child).dataModel = mpModel` tooltip host-model tagging (eachItemGraphicEl traverse) is deferred, so markPoint tooltip won't resolve the model |
| `MarkerView.swift` | 🟡 minor | 92% | low | 0 | updateZ's traverseUpdateZ(markerDraw.group, z, zlevel) is a no-op; marker group z/zlevel from model is not propagated — deferred pending a shared traverseUpdateZ util |
| `MatrixView.swift` | 🟡 minor | 85% | low | 1 | isFunction(formatter) label path is a no-op — custom function formatters fall through to default text instead of being invoked；setTooltipConfig call dropped — cell/text-overflow tooltips not wired (deferred interaction)；triggerEvent/getECData(cellRect).eventData block omitted — matrix cell click events with eventData never emitted；setLabelStyle replaced by standalone centered ZRText — no textCo… |
| `RadarComponentView.swift` | 🟡 minor | 97% | low | 0 | pathStyleFromDict drops a raw gradient/pattern OBJECT set as splitLine/splitArea `color` (only String/pre-built ZRColor bridged) — deferred option-dict→ZRColor bridge |
| `TimelineAxis.swift` | 🟡 minor | 92% | low | 0 | getViewLabels override builds one label per tick, ignoring label.interval that upstream base createAxisLabels would honor |
| `TimelineComponentModel.swift` | 🟡 minor | 92% | low | 0 | SliderTimelineModel omits the DataFormatMixin mixin (formatTooltip/getDataParams), so timeline tooltip content is unavailable |
| `timelineAction.swift` | 🟡 minor | 90% | low | 0 | timelineChanged event object carries only currentIndex+from, not defaults(...,payload); other payload fields are dropped |
| `installTitle.swift` | 🟡 minor | 90% | low | 0 | link/sublink 'click' handlers deferred (PORT-NOTE): clicking title/subtext does not call windowOpen to open the target URL；getECData(...).eventData wiring deferred: triggerEvent does not attach {componentType:'title', componentIndex} so title mouse events carry no eventData；local createTextStyle only sets text/font/fill/x/y/verticalAlign/width; upstream label/labelStyle rich-text, textShadow, l… |
| `ToolboxModel.swift` | 🟡 minor | 85% | low | 0 | init() theme-feature backward-compat (_themeFeatureOption extract/recover) not ported；optionUpdated omits the per-feature theme merge (merge(featureOpt, themeFeatureOption[name])) |
| `ToolboxView.swift` | 🟡 minor | 85% | medium | 0 | Title-overflow reposition block (isVertical\|\|group.eachChild emphasisState.textConfig) deferred; titles can render off-screen；graphic.setTooltipConfig on icons deferred (no icon tooltips)；payload.newTitle/featureName merge (FIX#11236 MagicType title update) not ported；DataDiffer add/update/remove reduced to rebuild-each-render; removed features' dispose not called on re-render；image:// icon b… |
| `toolboxAction.swift` | 🟡 minor | 90% | low | 0 | RestoreOption.onclick's history.clear(ecModel) (dataZoom-history reset before restore) not ported in this file；computeMagicTypeOption (MagicType.onclick) reduced to line<->bar; 'stack'/'tiled' partial and markPoint/markLine carry-over deferred |
| `toolboxFeatureManager.swift` | 🟡 minor | 95% | low | 0 | ToolboxFeature.onclick drops upstream's `event: ZRElementEvent` arg (documented deferral)；UserDefinedToolboxFeature (`my*`) interface not modeled |
| `tooltipMarkup.swift` | 🟡 minor | 97% | low | 2 | retrieveVisualColorForTooltipMarker via convertToColorStringLoose returns 'transparent' for a visual-style color stored as a typed ZRenderKit ZRColor instead of String/EChartsKit ZRColor (marker dot may lose color) |
| `ContinuousView.swift` | 🟡 minor | 90% | low | 0 | _updateHandle two-handle label-overlap merge (BoundingRect.intersect MTV nudge + switch both labels to 'all'-drag) deferred；_showIndicator additive animateTo (cubicInOut duration:100) indicator/label move deferred; final state set directly；ZRImage image-indicator branch of _createIndicator not ported (falls back to symbol path) |
| `visualEncoding.swift` | 🟡 minor | 95% | low | 1 | Handler #1 omits the `pipelineContext.large` short-circuit, so large/progressive-mode series would still run per-point encoding instead of skipping |
| `visualMapHelper.swift` | 🟡 minor | 100% | none | 1 | — |
| `ariaPreprocessor.swift` | 🟢 parity | 100% | none | 0 | — |
| `ariaVisual.swift` | 🟢 parity | 98% | none | 1 | — |
| `AxisView.swift` | 🟢 parity | 100% | none | 1 | — |
| `parallelAxisAction.swift` | 🟢 parity | 100% | none | 0 | — |
| `AxisPointer.swift` | 🟢 parity | 100% | none | 0 | — |
| `AxisPointerModel.swift` | 🟢 parity | 100% | none | 0 | — |
| `CartesianAxisPointer.swift` | 🟢 parity | 100% | none | 0 | — |
| `viewHelper.swift` | 🟢 parity | 98% | none | 0 | — |
| `BrushModel.swift` | 🟢 parity | 100% | none | 0 | — |
| `BrushView.swift` | 🟢 parity | 100% | none | 0 | — |
| `brushAction.swift` | 🟢 parity | 100% | none | 0 | — |
| `brushPreprocessor.swift` | 🟢 parity | 100% | none | 0 | — |
| `selector.swift` | 🟢 parity | 100% | none | 0 | — |
| `AxisProxy.swift` | 🟢 parity | 100% | none | 1 | — |
| `DataZoomModel.swift` | 🟢 parity | 100% | none | 0 | — |
| `InsideZoomModel.swift` | 🟢 parity | 100% | none | 0 | — |
| `SliderZoomModel.swift` | 🟢 parity | 100% | none | 0 | — |
| `dataZoomAction.swift` | 🟢 parity | 100% | none | 0 | — |
| `dataZoomHelper.swift` | 🟢 parity | 100% | none | 1 | — |
| `dataZoomProcessor.swift` | 🟢 parity | 100% | none | 1 | — |
| `datasetInstall.swift` | 🟢 parity | 100% | none | 0 | — |
| `GraphicModel.swift` | 🟢 parity | 97% | none | 2 | — |
| `installGraphic.swift` | 🟢 parity | 98% | none | 0 | — |
| `installSimple.swift` | 🟢 parity | 100% | none | 0 | — |
| `BrushController.swift` | 🟢 parity | 97% | none | 0 | updateCovers grid path builds no targetInfo when cartesians is empty (documented skip); upstream keeps a coordSys:undefined targetInfo — edge-only |
| `BrushTargetManager.swift` | 🟢 parity | 96% | none | 1 | grid targetInfoBuilder skips a grid whose matched cartesians list is empty; upstream still pushes a targetInfo with coordSys undefined — edge-only, nothing brushable there |
| `brushHelper.swift` | 🟢 parity | 100% | none | 0 | — |
| `interactionMutex.swift` | 🟢 parity | 100% | none | 0 | — |
| `sliderMove.swift` | 🟢 parity | 100% | none | 0 | — |
| `ScrollableLegendModel.swift` | 🟢 parity | 100% | none | 0 | — |
| `legendAction.swift` | 🟢 parity | 98% | none | 0 | — |
| `legendFilter.swift` | 🟢 parity | 100% | none | 0 | — |
| `MarkAreaModel.swift` | 🟢 parity | 100% | none | 0 | — |
| `MarkLineModel.swift` | 🟢 parity | 100% | none | 0 | — |
| `MarkPointModel.swift` | 🟢 parity | 100% | none | 0 | — |
| `checkMarkerInSeries.swift` | 🟢 parity | 100% | none | 0 | — |
| `installMarkArea.swift` | 🟢 parity | 100% | none | 0 | — |
| `installMarkLine.swift` | 🟢 parity | 100% | none | 0 | — |
| `installMarkPoint.swift` | 🟢 parity | 100% | none | 0 | — |
| `markerHelper.swift` | 🟢 parity | 98% | low | 2 | toFixedNumber approximates JS Number.toFixed rounding via %.*f; a tie at the rounding digit can diverge by one ULP in marker coord precision (rare) |
| `timelinePreprocessor.swift` | 🟢 parity | 98% | none | 0 | — |
| `ToolboxBrushFeature.swift` | 🟢 parity | 98% | none | 0 | — |
| `TooltipModel.swift` | 🟢 parity | 100% | none | 1 | — |
| `TooltipRichContent.swift` | 🟢 parity | 98% | low | 0 | hideLater setTimeout modeled as DispatchQueue.asyncAfter and not advanced in the headless static-frame oracle (documented; live-only path) |
| `seriesFormatTooltip.swift` | 🟢 parity | 100% | none | 0 | — |
| `filterTransform.swift` | 🟢 parity | 100% | none | 0 | — |
| `sortTransform.swift` | 🟢 parity | 100% | none | 1 | — |
| `transformInstall.swift` | 🟢 parity | 100% | none | 0 | — |
| `ContinuousModel.swift` | 🟢 parity | 98% | none | 1 | — |
| `PiecewiseModel.swift` | 🟢 parity | 98% | none | 3 | — |
| `PiecewiseView.swift` | 🟢 parity | 97% | none | 1 | — |
| `VisualMapModel.swift` | 🟢 parity | 98% | low | 16 | formatValueText function-formatter path only fires for closures coercible to (Double)->String / (Double,Double)->String; other signatures silently fall through to default text |
| `VisualMapView.swift` | 🟢 parity | 100% | none | 0 | — |
| `typeDefaulter.swift` | 🟢 parity | 100% | none | 0 | — |
| `visualMapAction.swift` | 🟢 parity | 100% | none | 2 | — |
| `visualMapPreprocessor.swift` | 🟢 parity | 100% | none | 0 | — |

### coord  (66)

| 文件 | 状态 | 覆盖 | 优先级 | todos | 缺口 |
|------|------|-----:|--------|------:|------|
| `axisModelCreator.swift` | 🟠 major | 82% | medium | 1 | registerComponentModel is a PORT-STUB no-op — creator-generated per-type axis model classes are never registered (ECharts.swift hand-written stand-in models serve instead)；registerSubTypeDefaulter is a PORT-STUB no-op — component sub-type inference from option not consulted for non-axis components；mergeDefaultAndTheme drops fetchLayoutMode/getLayoutParams/mergeLayoutParam branch — axis box-layo… |
| `Grid.swift` | 🟠 major | 85% | medium | 4 | layOutGridByOuterBounds is fully stubbed (returns noPxChange=true, no shrink) so grid.outerBounds and containLabel-without-legacy-impl never shrink the grid rect for label/name overflow；resolveAxisNameOverlapForGrid deferred: cross-perpendicular-axis name-overlap nudging (moveIfOverlapByLinearLabels) not applied; uses default resolver；createOrUpdateAxesView skips calcNameMarginLevel/nameMarginL… |
| `View.swift` | 🟡 minor | 82% | medium | 0 | calcCompensationScaleToPreserveNodeSize not ported — graph/tree/sankey nodeScaleRatio (keep node size constant on zoom) unavailable；Roaming-animation syncBackEl path deferred: applyViewCoordSysTransToElement / calcOverallTransFromSyncBackEl / updateProps animation not ported；invertBackToCenterOption percent-center round-trip omitted — sync-back always returns numeric center, so percent centerOp… |
| `axisStatistics.swift` | 🟡 minor | 95% | low | 0 | cycleCache is a local stub keyed per-ecModel with no automatic per-EC_FULL_UPDATE/EC_PREPARE reset (only manual resetCachePerECFullUpdate); upstream resets each cycle in echarts.ts；EChartsExtensionInstallRegisters base registerProcessor is a PORT-STUB that discards the AXIS_STATISTICS overallReset processor unless the real capturing subclass in ECharts.swift is used |
| `cartesian2dPrepareCustom.swift` | 🟡 minor | 90% | low | 0 | dataToCoordSize category branch calls axis.getBandWidth() instead of pinned upstream's calcBandWidth(axis).w (breaks/statistics-aware), so api.size() differs on category axes with breaks |
| `GeoJSONResource.swift` | 🟡 minor | 90% | low | 0 | fixNanhai not ported: China map's Nanhai islands inset regions are not synthesized；fixTextCoord/fixDiaoyuIsland not ported: per-region label-coord and Diaoyu island corrections skipped |
| `GeoModel.swift` | 🟡 minor | 93% | low | 0 | init omits modelUtil.defaultEmphasis(option,'label',['show']) so emphasis label show default is not seeded；RoamHostModel conformance not declared; __ownRoamView returns erased Any? (roam interaction deferred) |
| `GeoSVGResource.swift` | 🟡 minor | 96% | low | 0 | _buildGraphic silently yields an empty Group on parse failure instead of throwing upstream's 'Invalid svg format' error (assert(rootFromParse != null) omitted)；applyNameMap remains unported (matches upstream's own PENDING-commented state) |
| `geoCreator.swift` | 🟡 minor | 92% | low | 2 | resizeGeo drops layout.applyPreserveAspect on the left/top/width/height path, so preserveAspect adjustment is not applied；scaleLimit is computed across the map-series group but never applied (roam deferred) |
| `ParallelAxisModel.swift` | 🟡 minor | 98% | low | 0 | updateAxisBreaks(payload) always returns empty AxisBreakUpdateResult(breaks:[]) — axis-break feature is a no-op on parallel axes |
| `PolarAxisModel.swift` | 🟡 minor | 95% | low | 0 | updateAxisBreaks returns an empty AxisBreakUpdateResult stub, so axis-break feature is inert on polar axes |
| `RadarModel.swift` | 🟡 minor | 97% | low | 2 | indicator model.uid keeps ComponentModel 'ec_cpt_model' prefix instead of getUID('ec_radar'); still unique, benign unless 'ec_radar' prefix is load-bearing；axisName.formatter function branch requires the erased closure to cast to RadarAxisNameFormatter; a differently-typed closure leaves name unchanged |
| `scaleRawExtentInfo.swift` | 🟡 minor | 97% | low | 2 | invokeAxisMinMaxCallback only casts one closure shape (([String:Double])->ScaleDataValue); an axis min/max function option of any other Swift signature is silently dropped to nil |
| `Axis.swift` | 🟢 parity | 100% | none | 0 | — |
| `AxisBaseModel.swift` | 🟢 parity | 100% | none | 0 | — |
| `CoordinateSystem.swift` | 🟢 parity | 100% | none | 4 | — |
| `axisAlignTicks.swift` | 🟢 parity | 100% | none | 2 | — |
| `axisBand.swift` | 🟢 parity | 100% | none | 0 | — |
| `axisCommonTypes.swift` | 🟢 parity | 100% | none | 0 | — |
| `axisDefault.swift` | 🟢 parity | 100% | none | 1 | — |
| `axisHelper.swift` | 🟢 parity | 99% | low | 0 | makeLabelFormatter string branch uses replacingOccurrences (replaces all {value}) vs JS replace (first only) — divergent only if multiple {value} placeholders |
| `axisModelCommonMixin.swift` | 🟢 parity | 100% | none | 0 | — |
| `axisNiceTicks.swift` | 🟢 parity | 100% | none | 1 | — |
| `axisStatisticsMetricsImpl.swift` | 🟢 parity | 100% | none | 0 | — |
| `axisTickLabelBuilder.swift` | 🟢 parity | 99% | none | 0 | axisCacheKeyEquals cannot identity-compare a function `interval` option, so a callback-interval axis recomputes each call (identical result, perf-only cost) rather than hitting the cache |
| `Calendar.swift` | 🟢 parity | 100% | none | 1 | — |
| `CalendarModel.swift` | 🟢 parity | 100% | none | 1 | — |
| `calendarPrepareCustom.swift` | 🟢 parity | 100% | none | 0 | — |
| `Axis2D.swift` | 🟢 parity | 100% | none | 0 | — |
| `AxisModel.swift` | 🟢 parity | 100% | none | 0 | — |
| `Cartesian.swift` | 🟢 parity | 100% | none | 1 | — |
| `Cartesian2D.swift` | 🟢 parity | 100% | none | 1 | — |
| `GridModel.swift` | 🟢 parity | 98% | none | 1 | — |
| `cartesianAxisHelper.swift` | 🟢 parity | 98% | none | 0 | updateCartesianAxisViewCommonPartBuilder omits the __DEV__-only per-prop invariant assert (Mirror reflection unavailable); dev-only, no runtime effect |
| `defaultAxisExtentFromData.swift` | 🟢 parity | 100% | none | 2 | — |
| `Geo.swift` | 🟢 parity | 98% | none | 1 | — |
| `Region.swift` | 🟢 parity | 99% | none | 0 | cloneShallow disables transformTo via a _transformToDisabled flag rather than nulling the method (sanctioned language difference; behavior identical) |
| `geoPrepareCustom.swift` | 🟢 parity | 100% | none | 0 | — |
| `geoSourceManager.swift` | 🟢 parity | 98% | none | 0 | load() on unregistered map returns an empty GeoResourceLoadResult instead of undefined (deliberate, documented; caller path preserved) |
| `geoTypes.swift` | 🟢 parity | 97% | none | 0 | GeoProjection full contract (unproject + optional stream(_:)) not emitted here; the minimal project-only shape lives in Region.swift (type-contract split, not a behavioral loss) |
| `parseGeoJson.swift` | 🟢 parity | 99% | none | 0 | — |
| `Matrix.swift` | 🟢 parity | 98% | none | 0 | — |
| `MatrixBodyCorner.swift` | 🟢 parity | 98% | none | 0 | — |
| `MatrixDim.swift` | 🟢 parity | 98% | none | 0 | — |
| `MatrixModel.swift` | 🟢 parity | 97% | none | 0 | — |
| `matrixCoordHelper.swift` | 🟢 parity | 98% | none | 0 | — |
| `matrixPrepareCustom.swift` | 🟢 parity | 100% | none | 0 | — |
| `Parallel.swift` | 🟢 parity | 100% | none | 3 | — |
| `ParallelAxis.swift` | 🟢 parity | 100% | none | 0 | — |
| `ParallelModel.swift` | 🟢 parity | 100% | none | 2 | — |
| `parallelCreator.swift` | 🟢 parity | 100% | none | 0 | — |
| `parallelPreprocessor.swift` | 🟢 parity | 100% | none | 0 | — |
| `AngleAxis.swift` | 🟢 parity | 100% | none | 0 | — |
| `Polar.swift` | 🟢 parity | 100% | none | 1 | — |
| `PolarModel.swift` | 🟢 parity | 100% | none | 0 | — |
| `RadiusAxis.swift` | 🟢 parity | 100% | none | 0 | — |
| `polarCreator.swift` | 🟢 parity | 100% | none | 0 | — |
| `prepareCustom.swift` | 🟢 parity | 100% | none | 1 | — |
| `IndicatorAxis.swift` | 🟢 parity | 100% | none | 0 | — |
| `Radar.swift` | 🟢 parity | 98% | none | 2 | convertToPixel/convertFromPixel not implemented, but upstream versions are console.warn('Not implemented') stubs returning null — no real behavior lost |
| `Single.swift` | 🟢 parity | 100% | none | 0 | — |
| `SingleAxis.swift` | 🟢 parity | 100% | none | 1 | — |
| `SingleAxisModel.swift` | 🟢 parity | 100% | none | 0 | — |
| `singleAxisHelper.swift` | 🟢 parity | 100% | none | 0 | — |
| `singleCreator.swift` | 🟢 parity | 100% | none | 0 | — |
| `singlePrepareCustom.swift` | 🟢 parity | 100% | none | 0 | — |

### core  (7)

| 文件 | 状态 | 覆盖 | 优先级 | todos | 缺口 |
|------|------|-----:|--------|------:|------|
| `ECharts.swift` | 🟠 major | 80% | medium | 2 | `convertToPixel`/`convertFromPixel` (data<->pixel coordinate conversion public API) not ported；`resize(opts)` not ported — no runtime resize / media-query re-resolve (driver takes fixed width/height at init)；`getOption()` (return current merged option tree) not ported；`getVisual(finder, visualType)` not ported；`clear`/`dispose`/`isDisposed` instance lifecycle not ported (no _disposed flag)；`sho… |
| `ExtensionAPI.swift` | 🟡 minor | 95% | low | 0 | `availableMethods` dynamic ecInstance forwarding (getDom/isSSR/isDisposed/on/off/getDataURL/getOption/getId/updateLabelLayout) not declared as abstract members — deferred to Phase 6b; unused by ported callers |
| `Scheduler.swift` | 🟡 minor | 90% | low | 6 | prepareView is a no-op: upstream pipes view.renderTask into the pipeline; deferred to C2 so progressive view render is not scheduler-driven；detectSeriseType always returns nil (mock-method reflection unportable); block-range narrowing for legacy pure-function handlers absent (perf only)；updateStreamModes ignores seriesModel.__preparePipelineContext override, always calling free preparePipelineC… |
| `CoordinateSystemManager.swift` | 🟢 parity | 99% | none | 2 | DEV-only assertion `each(list, m => assert(!m.update))` for non-series-box masters omitted (update is a defaulted protocol method, presence undetectable) — no runtime effect |
| `lifecycle.swift` | 🟢 parity | 100% | none | 0 | — |
| `locale.swift` | 🟢 parity | 100% | none | 0 | — |
| `task.swift` | 🟢 parity | 99% | none | 2 | — |

### data  (18)

| 文件 | 状态 | 覆盖 | 优先级 | todos | 缺口 |
|------|------|-----:|--------|------:|------|
| `DataStore.swift` | 🟡 minor | 98% | low | 3 | 'int'-typed columns are not truncated to Int32 (all chunks are Double-backed [ParsedValue]), so integer-only storage semantics differ from CtorInt32Array |
| `SeriesData.swift` | 🟡 minor | 98% | low | 4 | wrapMethod only fires injections for 'cloneShallow' and 'getItemModel'; wrapping any other method name stores the injection but never invokes it (upstream rebinds arbitrary methods) |
| `Source.swift` | 🟡 minor | 97% | low | 1 | keyedColumns branch of determineSourceDimensions iterates Swift's unordered Dictionary, so auto-detected dimension order may diverge from upstream JS insertion order |
| `createDimensions.swift` | 🟡 minor | 97% | low | 4 | encodeDefMap built from a Swift `[String:Any]` dict loses JS insertion order, so encode-key iteration order (affecting availDimIdx assignment) can differ from upstream in edge cases |
| `linkSeriesData.swift` | 🟡 minor | 90% | medium | 0 | Transferable downSample/map and changable filterSelf/selectRange injections are stored but never fired, so struct.update() won't run on filter/selectRange (graph/tree dataZoom+sampling) |
| `sourceManager.swift` | 🟡 minor | 95% | low | 1 | disableTransformOptionMerge is a no-op (setAsPrimitive unported), so a transform option is deep-merged instead of replaced on a second setOption；needsCreateSource collapses JS null-vs-undefined on seriesLayoutBy in the dataset-upstream path (Optionals), may diverge from upstream |
| `DataDiffer.swift` | 🟢 parity | 100% | none | 0 | — |
| `Graph.swift` | 🟢 parity | 100% | none | 1 | — |
| `OrdinalMeta.swift` | 🟢 parity | 100% | none | 0 | — |
| `SeriesDimensionDefine.swift` | 🟢 parity | 100% | none | 1 | — |
| `Tree.swift` | 🟢 parity | 100% | none | 3 | — |
| `SeriesDataSchema.swift` | 🟢 parity | 100% | none | 0 | — |
| `dataProvider.swift` | 🟢 parity | 100% | none | 6 | — |
| `dataStackHelper.swift` | 🟢 parity | 100% | none | 1 | — |
| `dataValueHelper.swift` | 🟢 parity | 100% | none | 0 | — |
| `dimensionHelper.swift` | 🟢 parity | 100% | none | 2 | — |
| `sourceHelper.swift` | 🟢 parity | 98% | none | 2 | — |
| `transform.swift` | 🟢 parity | 98% | none | 1 | — |

### i18n  (8)

| 文件 | 状态 | 覆盖 | 优先级 | todos | 缺口 |
|------|------|-----:|--------|------:|------|
| `langDE.swift` | 🟢 parity | 100% | none | 0 | — |
| `langEN.swift` | 🟢 parity | 100% | none | 0 | — |
| `langES.swift` | 🟢 parity | 100% | none | 0 | — |
| `langFR.swift` | 🟢 parity | 100% | none | 0 | — |
| `langJA.swift` | 🟢 parity | 100% | none | 0 | — |
| `langPTbr.swift` | 🟢 parity | 100% | none | 0 | — |
| `langRU.swift` | 🟢 parity | 100% | none | 0 | — |
| `langZH.swift` | 🟢 parity | 100% | none | 0 | — |

### label  (5)

| 文件 | 状态 | 覆盖 | 优先级 | todos | 缺口 |
|------|------|-----:|--------|------:|------|
| `LabelManager.swift` | 🟠 major | 55% | medium | 0 | processLabelsOverall + _updateLabelLine not ported: per-frame generic label-line style/point update (setLabelLineStyle/updateLabelLinePoints) never runs；_animateLabels not ported: label position tween, fade-in initProps opacity animation, and value roll-up (animateLabelValue) are absent；updateLayoutConfig draggable branch deferred: label drag + createDragHandler(updateLabelLinePoints) not wired… |
| `labelGuideHelper.swift` | 🟠 major | 35% | medium | 0 | updateLabelLinePoints not ported: the candidate-anchor guide-line generation entry (getCandidateAnchor/nearestPointOnPath/nearestPointOnRect) is absent；setLabelLineStyle not ported: no generic label-line creation/state styling (show/smooth/lineStyle/showAbove) — charts must draw leader lines inline；getLabelLineStatesModels not ported: no per-state (normal/emphasis/blur/select) labelLine model r… |
| `labelLayoutHelper.swift` | 🟡 minor | 90% | low | 2 | Margin machinery is a documented no-op: marginForce/minMarginForce/marginDefault/__marginType and expandOrShrinkRect expansion are skipped in computeLabelGeometry, so minMargin/textMargin do not enlarge label rects；computeLabelGeometry2 (raw-rect+transform geometry, used for axis-break boundary labels) not ported |
| `labelStyle.swift` | 🟡 minor | 97% | low | 3 | LabelExtendedTextStyle.__marginType tag is not stored on the style: the margin VALUE is computed but which of minMargin/textMargin produced it is lost, so downstream margin-conflict resolution (labelLayoutHelper margin expansion) cannot distinguish them |
| `labelHelper.swift` | 🟢 parity | 100% | none | 0 | — |

### layout  (4)

| 文件 | 状态 | 覆盖 | 优先级 | todos | 缺口 |
|------|------|-----:|--------|------:|------|
| `barGrid.swift` | 🟡 minor | 97% | low | 2 | createProgressiveLayout sets handler.plan=nil (createRenderPlanner not wired), so progressive-render chunk planning differs from upstream; reset recomputes each pass；computeBarLayoutForCustomSeries does not resolve string-percent bar sizes (barGridOptionSize collapses strings to 0) for custom series |
| `points.swift` | 🟡 minor | 97% | low | 0 | handler.plan=nil (createRenderPlanner not wired), so progressive-render chunk planning differs from upstream; reset recomputes each pass |
| `barCommon.swift` | 🟢 parity | 100% | none | 0 | — |
| `barPolar.swift` | 🟢 parity | 100% | none | 1 | — |

### mixin  (1)

| 文件 | 状态 | 覆盖 | 优先级 | todos | 缺口 |
|------|------|-----:|--------|------:|------|
| `Draggable.swift` | 🟢 parity | 100% | none | 1 | — |

### model  (15)

| 文件 | 状态 | 覆盖 | 优先级 | todos | 缺口 |
|------|------|-----:|--------|------:|------|
| `Component.swift` | 🟡 minor | 92% | low | 1 | mergeDefaultAndTheme omits layout.fetchLayoutMode/getLayoutParams + final mergeLayoutParam (box-layout param merge for layoutMode components)；mergeOption omits the layout.fetchLayoutMode/mergeLayoutParam branch, so left/right/width/height merge semantics are plain-merged not layout-aware；getDefaultOption legacy ParentClass.extend ancestor-merge branch dropped (unreachable: isExtendedClass alway… |
| `Global.swift` | 🟡 minor | 95% | low | 4 | _mergeOption wraps oldCmptList via compactMap, dropping 'hole' (removed) components, so replaceMerge index/hole preservation (design case 3) is not modeled |
| `Model.swift` | 🟡 minor | 96% | low | 8 | clone() returns a base Model instead of reconstructing the concrete subclass (constructor-via-metatype avoided), so a subclass clone loses its type；isAnimationEnabled hardcodes !env.node true (ZRenderKit env.node=1) intentionally for native, diverging from upstream node-guard |
| `OptionManager.swift` | 🟡 minor | 90% | low | 4 | doPreprocess seam is inert: ECUnitOption is a value type so registered preprocessors can't mutate baseOption/timelineOptions/mediaList in place (timeline & media options never get preprocessing applied)；setAsPrimitive typed-array-reuse guard for series.data/dataset.source is a no-op (util.setAsPrimitive not ported)；__DEV__ 'Illegal media option { query,option }' shape-error check inside the med… |
| `Series.swift` | 🟡 minor | 88% | medium | 7 | mergeDefaultAndTheme: fetchLayoutMode/getLayoutParams + final mergeLayoutParam (layout-mode box-position merge) deferred — box-layout series miss layout-param merging；mergeDefaultAndTheme: modelUtil.defaultEmphasis(option,'label',['show']) top-level label emphasis default not applied；fillDataTextStyle: per-item defaultEmphasis(data[i],'label',['show']) is a no-op loop — per-datum label emphasis… |
| `globalDefault.swift` | 🟢 parity | 100% | none | 0 | — |
| `internalComponentCreator.swift` | 🟢 parity | 100% | none | 0 | — |
| `areaStyle.swift` | 🟢 parity | 100% | none | 0 | — |
| `dataFormat.swift` | 🟢 parity | 98% | none | 0 | dimensionNames coerces absent dim names to "" (loses element optionality vs upstream [DimensionName?]); semantically inert per port note |
| `itemStyle.swift` | 🟢 parity | 100% | none | 0 | — |
| `lineStyle.swift` | 🟢 parity | 100% | none | 0 | — |
| `makeStyleMapper.swift` | 🟢 parity | 100% | none | 3 | — |
| `palette.swift` | 🟢 parity | 100% | none | 1 | — |
| `textStyle.swift` | 🟢 parity | 100% | none | 3 | — |
| `referHelper.swift` | 🟢 parity | 100% | none | 2 | — |

### processor  (4)

| 文件 | 状态 | 覆盖 | 优先级 | todos | 缺口 |
|------|------|-----:|--------|------:|------|
| `dataSample.swift` | 🟢 parity | 100% | none | 2 | — |
| `dataStack.swift` | 🟢 parity | 100% | none | 0 | — |
| `legendDataFilter.swift` | 🟢 parity | 100% | none | 0 | — |
| `negativeDataFilter.swift` | 🟢 parity | 100% | none | 0 | — |

### scale  (10)

| 文件 | 状态 | 覆盖 | 优先级 | todos | 缺口 |
|------|------|-----:|--------|------:|------|
| `Interval.swift` | 🟢 parity | 100% | none | 1 | — |
| `LogScale.swift` | 🟢 parity | 100% | none | 0 | — |
| `Ordinal.swift` | 🟢 parity | 100% | none | 0 | — |
| `Scale.swift` | 🟢 parity | 100% | none | 0 | — |
| `TimeScale.swift` | 🟢 parity | 100% | none | 3 | — |
| `break.swift` | 🟢 parity | 100% | none | 0 | — |
| `breakImpl.swift` | 🟢 parity | 100% | none | 0 | — |
| `helper.swift` | 🟢 parity | 100% | none | 0 | — |
| `minorTicks.swift` | 🟢 parity | 100% | none | 0 | — |
| `scaleMapper.swift` | 🟢 parity | 100% | none | 0 | — |

### theme  (1)

| 文件 | 状态 | 覆盖 | 优先级 | todos | 缺口 |
|------|------|-----:|--------|------:|------|
| `darkTheme.swift` | 🟢 parity | 100% | none | 0 | — |

### util  (20)

| 文件 | 状态 | 覆盖 | 优先级 | todos | 缺口 |
|------|------|-----:|--------|------:|------|
| `graphic.swift` | 🟠 major | 65% | high | 1 | setTooltipConfig not ported anywhere -> component-level item tooltipConfig (title/legend/geo/graphic/timeline) is unavailable；clipRectByRect not ported (only inlined per-demo) -> custom-series rect-clip helper missing；groupTransition not ported -> parallel-axis (and legacy group) transition animation is a no-op；calcZ2Range not ported -> z2-range label-lifting computation absent；extendShape/exte… |
| `layout.swift` | 🟠 major | 78% | medium | 2 | applyPreserveAspect not ported: preserveAspect 'cover'/'contain' for geo/graphic/image components is unavailable；fetchLayoutMode not ported: component layoutMode resolution for mergeLayoutParam callers is absent；getLayoutParams not ported: retrieve LOCATION_PARAMS from a source option object is missing；sizeCalculable not ported (option[width] \|\| (left&&right) size check)；createBoxLayoutRefere… |
| `format.swift` | 🟡 minor | 97% | low | 0 | windowOpen is a native no-op (browser-only window.open has no host wiring yet)；formatTplSimple iterates a Swift Dictionary (unspecified order) vs upstream JS insertion order, diverging if one value contains another key's placeholder |
| `log.swift` | 🟡 minor | 97% | low | 0 | makePrintable: JSON.stringify replacer that re-formats nested Infinity/NaN/Date/function values is dropped; bare scalars fall through to '?' (dev-only log text) |
| `modelUtil.swift` | 🟡 minor | 96% | low | 1 | preParseFinder iterates ModelFinderObject via Swift Dictionary (unordered); upstream relies on object key order, so ambiguous multi-key finders may map differently |
| `states.swift` | 🟡 minor | 93% | medium | 2 | blurComponent drops the `view.focusBlurEnabled` gate: blurs children of ANY component view rather than only opt-in views (Geo), over-blurring；createBlurDefaultState omits getFromStateStyle's animator saveTo mining: opacity of an in-flight non-blur style animation is ignored when blurring；setAsHighDownDispatcher does not copy highDownSilentOnTouch (ECElement not consumed): touch-silent highlight… |
| `time.swift` | 🟡 minor | 95% | low | 0 | leveledFormat skips makeAxisLabelFormatterParamBreak enrichment, so a user function formatter on a break time-axis gets extra with no break info |
| `ECEventProcessor.swift` | 🟢 parity | 100% | none | 0 | — |
| `clazz.swift` | 🟢 parity | 100% | none | 1 | — |
| `componentUtil.swift` | 🟢 parity | 100% | none | 0 | — |
| `conditionalExpression.swift` | 🟢 parity | 100% | none | 0 | — |
| `decal.swift` | 🟢 parity | 95% | low | 0 | SVG-painter tile arm (renderOneToVNode/svgElement) not ported — sanctioned renderer seam, canvas-only；decalMap identity/dirty invalidation dropped in favor of value-keyed cache (equivalent for value-dict decals) |
| `event.swift` | 🟢 parity | 100% | none | 0 | — |
| `innerStore.swift` | 🟢 parity | 100% | none | 1 | — |
| `jitter.swift` | 🟢 parity | 97% | none | 0 | — |
| `number.swift` | 🟢 parity | 99% | none | 1 | — |
| `symbol.swift` | 🟢 parity | 98% | none | 4 | — |
| `throttle.swift` | 🟢 parity | 100% | none | 0 | — |
| `types.swift` | 🟢 parity | 98% | none | 9 | — |
| `vendor.swift` | 🟢 parity | 100% | none | 0 | — |

### view  (2)

| 文件 | 状态 | 覆盖 | 优先级 | todos | 缺口 |
|------|------|-----:|--------|------:|------|
| `Chart.swift` | 🟡 minor | 92% | low | 0 | makeInner(payload).updateMethod is inert (value-type Payload) so markUpdateMethod is a no-op and renderTaskReset drops the dynamic view[updateMethod] routing, always falling through to 'render' instead of updateView/updateVisual；eachRendered uses Group.traverse which visits children only, so unlike upstream traverseElements it never invokes cb on the root group element |
| `ComponentView.swift` | 🟢 parity | 97% | none | 0 | — |

### visual  (8)

| 文件 | 状态 | 覆盖 | 优先级 | todos | 缺口 |
|------|------|-----:|--------|------:|------|
| `symbolVisual.swift` | 🟠 major | 80% | medium | 0 | Function-valued symbol props (symbolSize/symbol/symbolRotate/symbolOffset callbacks) not evaluated per data item — the seriesSymbolTask dataEach callback branch is not ported；dataSymbolTask omits the ecModel.isSeriesFiltered(seriesModel) skip and the performRawSeries/createOnAllSeries scheduler flags (invoked inline from views instead) |
| `visualSolution.swift` | 🟠 major | 88% | medium | 0 | __alphaForOpacity stored under a literal dict key is NOT filtered by prepareVisualTypes (contrary to the code comment), so an opacity visualMap/brush applies an extra colorAlpha, wrongly modifying item color alpha；createMappings prototype-hidden-field trick is only partially emulated: the hidden slot is iterable, unlike upstream where hasOwnProperty iteration skips it |
| `VisualMapping.swift` | 🟡 minor | 95% | low | 2 | prepareVisualTypes replaces upstream's inconsistent sort comparator with a color-first stable partition; relative order of multiple color* types can differ；normalizeVisualRange flattens an object-form visual via nondeterministic Swift dict iteration, so paired visual assignment order can differ from JS insertion order |
| `style.swift` | 🟡 minor | 95% | low | 3 | decalOption.dirty=true and sharedModel.option.decal.dirty=true mutations not propagated (value-type bag) — deferred pending decal-pattern rendering |
| `LegendVisualProvider.swift` | 🟢 parity | 100% | none | 0 | — |
| `decalVisual.swift` | 🟢 parity | 100% | none | 0 | — |
| `tokens.swift` | 🟢 parity | 100% | none | 0 | — |
| `visualDefault.swift` | 🟢 parity | 98% | none | 0 | — |

