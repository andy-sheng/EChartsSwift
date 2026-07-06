# PORT_STATUS.md — ECharts/ZRender → Swift port

**Phase 46 (CHORD hover-emphasis + `focus:'adjacency'`; 17th interaction-layer phase; completes the node/edge hover story — chord was the LAST node/edge chart without hover): applied the node+edge emphasis block to `ChordPiece` (Sector, per-node) and `ChordEdge` (Path, per-ribbon) — both were already `setItemGraphicEl`-registered + `ecData.dataType`-tagged, so this adds `toggleHoverEmphasis` (with `focus:'adjacency'` → `getAdjacentDataIndices()` bridged to the `{node,edge}` dict via `chordFocusDict`) + `setStatesStylesFromModel` (itemStyle for pieces, lineStyle for ribbons) + the `ecData.dataIndex` tag. `ChordSeriesModel` got the `getData(.edge)→getEdgeData()` override (the [[getdata-datatype-ignored-trap]], same as graph/sankey). TRAP hit + fixed: inside a `Sector`/`Path` subclass the bare `states` resolves to `self.states` (the element's ZR state dict), NOT the `states` enum — qualified as `EChartsKit.states`. **Clean build (0 warnings); `swift test` — 301 / 0 failures / 58 skipped** (baseline 300; +1 `ZZTopologyFocusTests.testChordAdjacencyFocusBlursUnrelated`: highlight chord node a → unrelated node c blurs, a + adjacent b stay bright). Demos: 47/47 render. Done directly in the main loop. Hover-highlight + topology-focus now works for ALL node/edge charts (graph, tree, sankey, chord). DEFERRED (documented): tree `__edge` blur propagation; the live mouseover focus fan-out (Phase 33). See §77.**

**Phase 45 (TOPOLOGY FOCUS + EDGE EMPHASIS for graph / tree / sankey; 16th interaction-layer phase; completes the node/edge hover story): `emphasis.focus:'adjacency'`/`'trajectory'` (graph, sankey) + `'ancestor'`/`'descendant'`/`'relative'` (tree) now resolve to the actual TOPOLOGY index set — highlighting a node keeps its neighbourhood BRIGHT and blurs the rest — and graph/sankey EDGES are now emphasis dispatchers. The data-layer methods (`GraphNode/Edge.getAdjacentDataIndices/getTrajectoryDataIndices`, `TreeNode.getAncestorsIndices/getDescendantIndices`) already existed; this phase is the VIEW-layer wiring. Files edited: `chart/graph/GraphView.swift` (edge emphasis block + a post `eachNode`/`eachEdge` loop overwriting each dispatcher's `ecData.focus` with the adjacency set — node → `getAdjacentDataIndices()`, edge → inline `{edge:[self], node:[n1,n2]}` — bridged to the `{node,edge}` dict via `graphFocusDict`), `chart/graph/GraphSeries.swift` (**override `getData(.edge)` → `getEdgeData()`** — the base ignored dataType, so the object-focus branch was resolving edge indices against NODE data), `chart/sankey/SankeyView.swift` (edge emphasis + inline adjacency/trajectory resolution for BOTH node+edge via `sankeyResolveNodeFocus`/`sankeyResolveEdgeFocus`; `ecData.dataType`/`dataIndex` tags on the curve/rect so `blurSeries`'s dataType lookup resolves), `chart/sankey/SankeySeries.swift` (same `getData(.edge)` override), `chart/tree/TreeView.swift` (node focus → `treeResolveFocus` → `[Int]` array-focus; edge `setStatesStylesFromModel(lineStyle)`). **Clean build (0 warnings); `swift test` — 300 / 0 failures / 58 skipped** (baseline 297; +3 `ZZTopologyFocusTests`: graph 'adjacency' highlight n0 → n2/n3 + edge n1-n2 blur while n1 + edge n0-n1 stay bright; tree 'descendant' highlight A → sibling subtree B blurs; sankey 'adjacency' highlight a → unrelated node c blurs). Demos: 47/47 still render (0 failed). Done DIRECTLY in the main loop (no workflow — mechanical wiring off a thorough scout of the existing data-layer methods). KEY FIX found via test: `SeriesModel.getData(dataType)` ignored the dataType (base returns node data), so graph/sankey `getData(.edge)` returned node data → edges never un-blurred; the two overrides fix it. Also documented: the highlight dispatch resolves the target via `dataIndexInside` (the `dataIndex`→`indexOfRawIndex` map is a pre-existing stub). DEFERRED (documented): the tree `__edge` blur-propagation hook (edges dim with their node — needs `TreeSymbol.__edge` + `onHoverStateChange`); the live mouseover focus fan-out (Phase 33 defers it — focus works via `dispatchAction(highlight)`, the axisPointer/tooltip path); chord `focus:'adjacency'` (a peer deferred site). Hover-highlight + topology-focus now work across the node/edge charts. See §76.**

**Phase 44 (RECT BRUSH — drag-select a rectangle over a cartesian chart to DIM the unselected; 15th interaction-layer phase): `component/brush` RECT core now runs end-to-end. Files added: `component/brush/BrushModel.swift` (the `brush` component model + `setAreas`/`generateBrushOption`/default `outOfBrush:{color:disabled}`), `component/brush/brushVisual.swift` (the port of `visualEncoding.ts` + `selector.ts`: `BrushTargetManagerLite` grid/rect target match + `setInputRanges` coordRange→pixel, the RECT `BrushCommonSelectorsForSeries` (point-in-rect / rect-intersect), Step A `controlSeries` + Step B `applyVisual` in/out-of-brush → recolor the unselected via `visualSolution.applyVisual`), `component/brush/brushAction.swift` (`installBrushAction` → registerAction `brush`(updateVisual)/`brushSelect`/`brushEnd`). Files edited: `visual/visualSolution.swift` (added the non-incremental `applyVisual(stateList,mappings,data,getValueState,dim?)` — additive), `core/EChartsSlim.swift` (registered `BrushModel` + `installBrushAction`; hooked `brushVisual(ecModel,api,nil)` at PRIORITY.VISUAL.BRUSH — placed at the END of `render()` right before `renderSeries`, NOT in the `update()` visual stage, because the rect selector reads each datum's `getItemLayout` which the slim driver only populates in `render()`'s layout stages), `core/EChartsView.swift` (`_bindBrush` + `_brushDrag` state machine: mousedown→mouseup drags a rect → dispatch `{type:'brush', areas:[{brushType:'rect', range}]}`; a <2px drag clears the selection — a `removeOnClick` stand-in; hover suppressed while brushing, alongside `_insideZoomDrag`). **Clean build (0 warnings); `swift test` — 297 / 0 failures / 58 skipped** (baseline 294; +3 `ZZBrushTests`: a rect brush over the first 2 of 5 bars keeps them at palette fill + dims bars 2-4 to the outOfBrush color; the same via a LIVE injected mousedown→mouseup drag; an empty-areas brush leaves all normal). INTEGRATED MANUALLY: the workflow finished translation but both verify agents reported CRITICAL-ISSUES (integrator died) — a dead duplicate `selector.swift` (colliding top-level decls; deleted, its logic already lived in `brushVisual.swift`), `BrushModel` lacked the `BrushModelLike` conformance the runtime `as?` casts need (added `extension BrushModel: BrushModelLike {}`), and the EChartsView drag + test were absent (both added). ALSO fixed a real render-ORDER bug found while wiring: brushVisual first placed in the update() visual stage saw nil item layouts → selected nothing; moved to end-of-render() (matches upstream priority 5000 running after the layout stages). DEFERRED (documented): brushType polygon/lineX/lineY, the full `BrushController` (transformable covers, live rubber-band, removeOnClick covers), coordRange persistence across dataZoom, the toolbox brush button, `brushLink`/parallel `stepAParallel`, throttle. See §75.**

**Phase 43 (HOVER-EMPHASIS for graph / tree / sankey; 14th interaction-layer phase): applied the emphasis-enable block to the NODE elements of the node/edge charts — `GraphView` (node symbols), `TreeView` (node symbols, in `updateNode`), `SankeyView` (node rects) — each mirroring its upstream call site (graph/tree via SymbolDraw→Symbol.ts:357; sankey SankeyView.ts:315/323). Elements were already `setItemGraphicEl`-registered. **Clean build (0 warnings); `swift test` — 294 / 0 failures / 58 skipped** (baseline 291; +3 `ZZHoverBreadth3Tests`, each hovering a node → emphasis through the real Handler chain). Hover-highlight now works for **11 chart types** (bar, scatter, line, pie, candlestick, boxplot, funnel, radar, graph, tree, sankey). DEFERRED (documented): topology focus (graph `focus:'adjacency'`, tree `relative/ancestor/descendant`, sankey `adjacency/trajectory`); edge/link emphasis (graph edges, tree curves, sankey ribbons); select/blur label niceties. See §74.**

**Phase 42 (DEMO-TRACK batch 1 — 10 echarts test-case demos; goal clause 2 "在demo中实现echart test中所有用例"): added 10 option-expressible demos derived from canonical echarts `test/` scenarios to `EChartsDemoGallery` (bar-stack/bar-negative/bar-horizontal, line-area/line-smooth/line-stack, pie-doughnut/pie-rose, scatter-multi, bar-datazoom-slider), each exercising a ported feature. Verified via `swift run EChartsDemoGallery --render-all` → **39 / 39 demos render headlessly, 0 failed** (29 existing + 10 new). EChartsKit + its 291 tests unaffected (the gallery is a separate executable target). This begins the demo-corpus track; the gallery already covered the core chart types (39 demos across bar/line/scatter/pie/radar/funnel/gauge/candlestick/boxplot/sunburst/treemap/themeRiver/tree/graph/sankey/chord/heatmap/map/geo/calendar/matrix/parallel/custom/visualMap). See §73.**

**Phase 41 (SliderZoomView — the on-screen dataZoom SLIDER widget + drag; 13th interaction-layer phase; completes the dataZoom feature): the `dataZoom:{type:"slider"}` bar renders (background + the selected-window filler band + two draggable handles) and dragging a handle resizes the window. Files added: `component/dataZoom/SliderZoomView.swift` (the render — `_renderBackground` + `_renderHandle` (handles + `filler` band + moveHandle) + the slider RECT layout from the option`s left/right/top/bottom/width/height over the api container (a minimal getLayoutRect substitute, since `util/layout` is unported); the handles/filler are `draggable`), `component/dataZoom/SliderZoomViewDrag.swift` (`_updateInterval` via the ported `sliderMove` + min/maxSpan clamp, `_onDragMove`/`_onDragEnd`/`_onClickPanel`/`_dispatchZoomAction` → the Phase-32 `dataZoom` action). Files edited: `core/EChartsSlim.swift` (registered `"dataZoom.slider" → SliderZoomView` in `_componentViewFactories`; `_componentsViews` made internal for test reach), `ZRenderKit/Element.swift` (added the `driftHandler` closure seam — upstream assigns `el.drift = fn` to replace the default drag-translate; Swift makes drift a method, so an optional `driftHandler` is the faithful reassignable seam — additive, default preserved). **Clean build `buildGreen = true` (0 warnings); `swift test` — 291 executed / 0 failures / 58 skipped** (baseline 289/0/58; +2 = new `ZZSliderZoomTests`: the slider renders its filler + 2 handles with the window `_range ≈ [20,60]`, and `_onDragMove(.at(1), +40px)` on the right handle widens the window end). INTEGRATED MANUALLY: the workflow hit the account session limit (integrate + both verify agents failed) after the 2 translators finished — I fixed the compile errors (access-level `private→internal` across the render/drag file split; the IUO-bound-to-`let` trap [[swiftpm-port-mechanical-traps]] on `dataZoomModel`; optional `sliderGroup`/transform; `_updateView` optional param; `_showDataInfo` stub), registered the view, and wrote the test. No adversarial review (agents quota-limited) — deliverable proven green by the render+drag tests; 289 pre-existing tests unchanged. DEFERRED (documented): the data-shadow mini-series preview, brushSelect, `_onClickPanel` recenter (behind a transformCoordToLocal guard), realtime/throttle, the label formatter, the animated tween, vertical-orient niceties, `util/layout`. Next: brush; toolbox; timeline; graph/tree/sankey hover; the data-shadow preview. See §72.**

**Phase 40 (HOVER-EMPHASIS for candlestick / boxplot / funnel / radar; 12th interaction-layer phase): extended hover-highlight + item-tooltip to 4 more chart types (previously bar/scatter/line/pie only). Applied the established emphasis-enable block (`toggleHoverEmphasis` + `setStatesStylesFromModel` per data element via `data.getItemModel(idx)`) to `CandlestickView` (`setBoxCommon` per `NormalBoxPath`, incl. the faithful per-state sign-color `getColor`/`getBorderColor` override loop over `el.states`), `BoxplotView` (`updateNormalBoxData` per `BoxPath`), `FunnelView` (per `Polygon` piece), `RadarView` (`setStatesStylesFromModel` on the polyline `lineStyle` + polygon `areaStyle`, `toggleHoverEmphasis` on the per-series `itemGroup` dispatcher so hovering any vertex/line/area resolves up). **Clean build `buildGreen = true` (0 warnings); `swift test` — 289 executed / 0 failures / 58 skipped** (baseline 285/0/58; +4 = new `ZZHoverBreadth2Tests`: each of candlestick/boxplot/funnel/radar enters emphasis on an injected hover through the real Handler chain, clears on move-off). Verified via a focused agent (mechanical replication of the tested pattern); 285 pre-existing tests pass unchanged. DEFERRED (documented): candlestick large/progressive batched path (no per-item element); radar per-state symbol itemStyle clone + polygon.ignore toggle; select-state offsets, blur fan-out, label emphasis, enter/update animations (across all four). Hover-highlight + item-tooltip now work for **8 chart types** (bar, scatter, line, pie, candlestick, boxplot, funnel, radar). Next: graph/tree/sankey (node/edge) hover; the SliderZoomView slider widget; brush; toolbox; timeline. See §71.**

**Phase 39 (INSIDE-ZOOM PAN — drag the chart body to move the dataZoom window; 11th interaction-layer phase; completes inside-zoom roam): dragging a cartesian chart body (mousedown→mousemove→mouseup) now PANs the dataZoom window, pairing with the Phase-38 wheel-zoom. Files edited: `core/EChartsView.swift` — `_bindInsidePan` + `_insideZoomDrag` state machine (mirrors `RoamController._mousedown/move/up`), `_computeInsidePanRange` ports the pan math from `InsideZoomView.getRangeHandlers.pan` + `roams.getDirectionInfo.grid` (`percentDelta = signal*(range[1]-range[0])*pixel/pixelLength`, then `sliderMove(percentDelta, range, [0,100], .all)` — whole-window span-preserving move), dispatching the Phase-32 `dataZoom` action; the shared axis/grid resolver was factored into `_resolveInsideZoomGeom` (reused by wheel + pan). CRITICAL detail: hover (emphasis/tooltip/crosshair/axisTrigger) is suppressed ONLY while a drag is active (the `_insideZoomDrag != nil` gate on the mouseover/mouseout + globalListener handlers) — so with no drag, hover behaves exactly as before. **Clean build `buildGreen = true` (0 warnings); `swift test` — 285 executed / 0 failures / 58 skipped** (baseline 282/0/58; +3 = new `ZZInsidePanTests`: drag-left `[20,60]→[40,80]`, drag-right `[20,60]→[10,50]` (span 40 preserved), drag-starting-off-grid → no-op). All Phase 33-38 hover/tooltip/crosshair/wheel tests still pass (verified). Only `EChartsView.swift` changed (no shared-infra). Faithful to `InsideZoomView` pan + `sliderMove('all')`; `zoomLock` correctly NOT checked for pan (upstream maps it to controlType 'move'). DEFERRED (documented): cursor styling, interactionMutex globalPan, modifier-key gating (`moveOnMouseMove:'ctrl'`), `moveOnMouseWheel` scroll-move, pinch/momentum, the full RoamController record machine, throttle/animated tween, polar/single roam, the SliderZoomView widget. Next: the SliderZoomView slider widget; brush; toolbox; timeline; hover-emphasis across the remaining series views. See §70.**

**Phase 38 (INSIDE-ZOOM WHEEL-TO-ZOOM — dataZoom is now INTERACTIVE via the mouse wheel; 10th interaction-layer phase): scrolling the wheel over a cartesian chart with an inside dataZoom zooms the data window in/out live — reusing the Phase-32 dataZoom data-filter core. Files edited: `core/EChartsView.swift` — `_bindInsideZoom()` binds `zr.on("mousewheel")` (`[weak self]`, ctx nil); `_handleInsideZoomWheel`/`_computeInsideZoomRange` port the zoom math from `InsideZoomView._onZoom` + `RoamController` (scale factor `|wheelDelta|>3?1.4:>1?1.2:1.1`, `scale=delta>0?factor:1/factor`; new percent range `range[i]=(range[i]-anchorPercent)*zoomScale+anchorPercent` clamped via `sliderMove` honoring minSpan/maxSpan), find the inside dataZoom(s) whose target coordSys `containPoint([zrX,zrY])`, dispatch the Phase-32 `dataZoom` action ({batch:[{dataZoomId,start,end}]}) → setRawRange → `update()` re-filters → `zr.refresh()`; `_injectWheelForTest` + a mousewheel case in `_injectPointerForTest`. **Clean build `buildGreen = true` (0 warnings); `swift test` — 282 executed / 0 failures / 58 skipped** (baseline 279/0/58; +3 = new `ZZInsideZoomTests`: a zoom-in wheel over the grid shrinks the rendered window 10→6, zoom-out grows it 6→10, an outside-grid wheel is a no-op — all through the real Handler→mousewheel chain). Verified via a focused integrator agent; only `EChartsView.swift` changed (no shared-infra) — 279 pre-existing tests pass unchanged. Faithful zoom math vs `InsideZoomView._onZoom`; ONE documented deviation: the target axis is resolved via the dataZoom`s representative AxisProxy (the same path `dataZoomProcessor` uses) instead of `collectReferCoordSysModelInfo().axisModels[0]` (the slim axis models return empty `getReferringComponents("grid")`) — equivalent for a single-axis cartesian inside dataZoom. DEFERRED (documented): pan/drag (`moveOnMouseMove`/`moveOnMouseWheel`), pinch/touch, the full `RoamController` state machine, throttle + the animated dataZoom tween, polar/singleAxis roam, the SliderZoomView on-screen slider widget, multi-axis-per-grid grouping. Next: the SliderZoomView slider widget; brush; toolbox; timeline; hover-emphasis across the remaining series views. See §69.**

**Phase 37 (HOVER-EMPHASIS BREADTH — hover-highlight + item-tooltip now work for SCATTER, LINE, PIE (not just bar); 9th interaction-layer phase): applied the BarView/Phase-33 emphasis-enable block — `toggleHoverEmphasis(el, focus, blurScope, isDisabled)` + `setStatesStylesFromModel(el, itemModel)` (reading the per-item `emphasis` model via `data.getItemModel(idx)`) — to each data element in `chart/scatter/ScatterView.swift` (symbols), `chart/line/LineView.swift` (data-point symbols), `chart/pie/PieView.swift` (sectors; un-stubbed its states PORT-TODO). ALSO fixed a real gap: ScatterView + LineView were NOT calling `data.setItemGraphicEl(idx, el)`, so their data elements were never registered for hit-test / tooltip / highlight resolution — added it (upstream`s SymbolDraw sets it). **Clean build `buildGreen = true` (0 warnings); `swift test` — 279 executed / 0 failures / 58 skipped** (baseline 276/0/58; +3 = new `ZZHoverBreadthTests`: scatter point / pie sector / line data-point symbol each enter the emphasis state on an injected hover through the real Handler chain, and clear on move-off). Verified via a focused integrator agent (no adversarial workflow review — a mechanical replication of the established, tested BarView pattern; the 276 pre-existing tests pass unchanged, so the `setItemGraphicEl` additions did not regress the scatter/line render). DEFERRED (documented): the line POLYLINE path`s own line-emphasis (`lineStyle` emphasis); pie select-state `selectedOffset` + blur focus fan-out; symbol `symbolRotate`/`symbolOffset`/emphasis scale-up (unported SymbolDraw states). Next: hover-emphasis across the remaining series views (tree/graph/sankey/etc.); dataZoom slider/inside DRAG; brush/toolbox/timeline. See §68.**

**Phase 36 (VISUAL axisPointer CROSSHAIR — the line that follows the pointer along the axis; 8th interaction-layer phase; completes the axisPointer feature): hovering a cartesian chart (with `tooltip:{trigger:"axis"}`) now draws a vertical crosshair `Line` at the hovered category`s x-pixel, alongside the Phase-35 axis tooltip; moving off-grid hides it. Files added: `component/axisPointer/{viewHelper,CartesianAxisPointer,BaseAxisPointer,AxisPointer,AxisPointerView}.swift` — the crosshair shape/render stack: `viewHelper.makeLineShape`/`makeRectShape`/`buildElStyle`/`getValueLabel`; `CartesianAxisPointer.makeElOption` computes the line pixel via `toGlobalCoord(dataToCoord(value,true))` across the grid rect (narrowing to concrete `Cartesian2D`/`Axis2D` — the protocol-witness trap avoided); `BaseAxisPointer.render` builds the `Line`+label into a `Group` (pointer `silent=true` so it does not block hit-testing) via a `hostAdd`/`hostRemove` seam, `hide()` on leave. Files edited: `core/EChartsView.swift` — `_axisPointers` (per-axis `CartesianAxisPointer`, keyed by `makeKey`, persisted across hovers) + `_updateAxisPointers(ecModel)` called right after `axisTrigger(...)`: for each cartesian axis it wires `hostAdd = { self?.zr.add($0) }` / `hostRemove` (`[weak self]`, ctx-free — retain-cycle rule) and renders the pointer with the value/status `axisTrigger.updateModelActually` just wrote to the model; off-grid → `hide()`. **Clean build `buildGreen = true` (0 warnings); `swift test` — 276 executed / 0 failures / 58 skipped** (baseline 275/0/58; +1 = new `ZZAxisCrosshairTests`: an injected mousemove at category "B" produces a vertical crosshair `Line` in `view.zr` with `x1≈x2≈`B`s pixel spanning the grid y-range, through the real pointer→globalListener→axisTrigger→axisPointer-status chain; off-grid → hidden). Faithfulness reviews: shape-builders (`viewHelper`+`CartesianAxisPointer`) **FAITHFUL** (pixel math + label + line/shadow style verified); render-wiring **CRITICAL-ISSUES** (only because the workflow integrator DIED before wiring — the 5 pointer files were translated + compiling but dead). RESOLVED post-workflow (rescue integrator): wired the crosshair into `EChartsView` (drive directly on hover, PARALLEL to the tooltip — the slim path has no live per-axis AxisView hosting a zr, same reason Phase 34/35 own the tooltip in EChartsView) + added the test. Only `EChartsView.swift` changed (no shared-infra) — no regression. WIRING APPROACH: driven from EChartsView (not the full `AxisView._doUpdateAxisPointerClass`+`registerAxisPointerClass` refactor). DEFERRED (documented): `axisPointer:{show:true}` WITHOUT a tooltip trigger:"axis" (the hover path is currently gated on the axis-trigger tooltip); polar/single crosshairs; move animation; drag handle; `lineDash` (the default `type:"dashed"` crosshair renders SOLID). Next: dataZoom slider/inside DRAG (on-screen zoom UI); hover+tooltip breadth across the remaining series views; brush/toolbox/timeline. See §67.**

**Phase 35 (axisTrigger + tooltip trigger:`axis` — the multi-series AXIS tooltip on hover; 7th interaction-layer phase; the VISUAL crosshair is Phase 36): hovering a cartesian chart with `tooltip:{trigger:"axis"}` now shows ONE combined tooltip listing EVERY series` value at the hovered x. Files added: `component/axisPointer/{AxisPointerModel,modelHelper,axisTrigger,findPointFromSeries,globalListener}.swift` — the axis-trigger data core: `axisTrigger` resolves the pointer point → per-coordSys/per-axis axis VALUE (via `Cartesian2D.pointToData`) → the nearest series data indices at that value → `dataByCoordSys` → dispatches a `showTip` carrying it; `modelHelper` collects the per-axis axisPointer models; `findPointFromSeries` maps a series datum → pixel; `globalListener` is the mousemove→axisTrigger driver. Files edited: `component/tooltip/TooltipView.swift` (added the trigger:"axis" path `_showAxisTooltip` — builds ONE combined markup from all series in dataByCoordSys, each via `formatTooltip(dataIndex, multipleSeries:true, dataType)`, shown in the same box), `core/EChartsView.swift` (`_bindAxisPointerListeners` wires `globalListener`→`axisTrigger`; routes the merged `showTip{dataByCoordSys}`→`_showAxisTooltip`, `hideTip`→`hide`; gated on `tooltip.trigger=="axis"` so the Phase-34 item tooltip is untouched), `core/EChartsSlim.swift` (registered `AxisPointerModel` + the axisPointer preprocessor + runs `modelHelper.collect()` in the STATISTIC stage of `update()` + exposes `api`). **Clean build `buildGreen = true` (0 warnings); `swift test` — 275 executed / 0 failures / 58 skipped** (baseline 274/0/58; +1 = new `ZZAxisTooltipTests`: an injected mousemove at category "B"`s x makes the combined axis tooltip appear as a visible zr root carrying the header "B" AND series B`s value "20", through the real Handler → globalListener → axisTrigger → showTip → _showAxisTooltip chain; off-grid → hidden). Faithfulness review (axistrigger) **CRITICAL-ISSUES** + the wiring review **CRITICAL-ISSUES** (both because the workflow integrator DIED before wiring — the data core was translated + compiling but dead). RESOLVED post-workflow (via a rescue integrator): the CRITICAL was the recurring PROTOCOL-WITNESS trap ([[swift-protocol-witness-trap]]) biting in THREE places at once, ALL of which had to be fixed for the tooltip to resolve any series value: (1) `modelHelper.collectSeriesInfo` cast to the `CoordinateSystem` existential → `getAxis` hit the nil default → series never attached to an axis (fixed: narrow to concrete `Cartesian2D`); (2) `Grid``s stored `let model: GridModel` did not witness `CoordinateSystemMaster.model: ComponentModel?` → `coordSys.model` nil → empty axes info (fixed: `_gridModel` private + a real `var model` witness + concrete `gridModel` accessor); (3) `SeriesModel.indicesOfNearest` was a `return []` stub → empty payloadBatch → `hideTip` not showTip (fixed: implemented via concrete `Cartesian2D.getAxis` + `axis.dataToCoord` + store scan). All three regression-safe — the 274 pre-existing tests pass unchanged. DEFERRED (documented, Phase 36+): the VISUAL crosshair (the axisPointer line/label view element); polar/single-axis pointers; link-group `mapper`; throttle; `getAxisTooltipData` (candlestick/boxplot); `label.formatter` + full valueLabel; `_showOrMove`/showDelay/no-change position-only update. Next: Phase 36 = the visual axisPointer crosshair; then dataZoom slider/inside drag; hover+tooltip across the remaining series views. See §66.**

**Phase 34 (TOOLTIP-ON-HOVER — the Phase-31 tooltip content now APPEARS on hover; 6th interaction-layer phase): hovering a data element shows its formatted tooltip (name + value) at the pointer, in a ZRenderKit-drawn box floating above the chart — driven by the Phase-33 `EChartsView` hover events. Files added: `component/tooltip/TooltipRichContent.swift` (the `ZRText` tooltip box: `setContent` builds the rich-text style from the Phase-31 markup + padding/backgroundColor/borderColor/shadow/textStyle, hosted in the LIVE `zr` via `_zr.add(el)` — NOT `ec.getRoot()`, so it floats above the chart and a re-render does not wipe it; `show`/`hide`/`getSize`/`moveTo`), `component/tooltip/TooltipView.swift` (a SLIM trigger:`item` view: `tryShow` → resolve hovered series+dataIndex → tooltip-model guard (`show!=false && trigger=="item"`) → `formatTooltip(dataIndex)` (Phase 31) → `TooltipRichContent.setContent`+`show`, positioned near the pointer with a minimal clamped `_updatePosition`; `hide`; + the `showTip`/`hideTip` action registration). Files edited: `core/EChartsView.swift` (OWNS a lazily-built `TooltipView` over the live zr; the mouseover handler now fires BOTH emphasis (Phase 33) AND `tryShow`; mouseout → `hide`; disposed in `deinit`), `core/EChartsSlim.swift` (`installTooltipActions`). **Clean build `buildGreen = true` (0 warnings); `swift test` — 274 executed / 0 failures / 58 skipped** (baseline 273/0/58; +1 = new `ZZTooltipHoverTests`: an injected synthetic pointer over bar 0 makes the tooltip `ZRText` appear as a visible root of `view.zr` carrying the category name "A" AND the value "10", through the real Handler hover chain; move off → hidden). Faithfulness reviews flagged 2 CRITICALs that were STALE (the reviewers saw a mid-integration state before the integrator finished the `EChartsView` wiring + the `ZZTooltipHoverTests` — both verified present + passing). ONE real CRITICAL found + FIXED post-workflow: `TooltipRichContent.richTextStylesToParts` (which reverse-engineers each `{styleName|text}` style bag into a `TextStylePropsPart` via a whitelist, vs upstream's wholesale `rich: richTextStyles` assignment) DROPPED the `width` key — so the series-color swatch marker (an empty-text token sized purely by `width`+`height`+`backgroundColor`) collapsed to width 0 (the color dot vanished). Fixed by adding the `width` (NumberOrString) branch. Also fixed a flawed TEST assertion: a rich `ZRText` is a CONTAINER (`Storage.updateDisplayList` recurses into its text tokens rather than emitting the ZRText as a leaf), so the tooltip is asserted as a visible STORAGE ROOT of the zr, not as a flattened-display-list member. MINORs (documented): `alwaysShowContent` JS-truthiness edge; non-string (gradient) backgroundColor dropped; the marker-whitelist remains fragile vs upstream's pass-through. DEFERRED (documented): trigger:`axis` + axisPointer integration; the HTML content host; `transitionDuration` animation; `confine`; the position-callback; per-item/coordSys tooltip-model cascade (series-only merge this phase); tooltip on the OTHER series views (BarView-driven hover only). Next: trigger:`axis` + the axisPointer hover crosshair; dataZoom slider/inside drag; hover+tooltip across the remaining series views. See §65.**

**Phase 33 (LIVE interaction — the `EChartsView` host binding: hover-to-highlight goes LIVE through the real native input stack; 5th interaction-layer phase): the first genuinely INTERACTIVE behavior lands — hovering a data element highlights it, driven end-to-end through the ALREADY-PORTED ZRenderKit `Handler` (findHover hit-test + mouseover/mouseout dispatch) + `NativeHandlerProxy` + `ZRenderView` native host. This connects everything built in Phases 29-31 (dispatchAction, the emphasis engine, state styles) to the native input stack. Files added: `core/EChartsView.swift` — the echarts↔live-ZRender host binding: owns an `EChartsSlim` + a live `ZRender` (built via the ported `zrender.init`, `HeadlessPainter` for tests / a real `PainterBase` for a native host), syncs `ec.getRoot()` into the zr storage, and `_initEvents` binds `zr.on("mouseover"/"mouseout")` → `enterEmphasisWhenMouseOver`/`leaveEmphasisWhenMouseOut` on the hovered highDown dispatcher + `zr.on("click")` → `toggleSelect` dispatchAction; plus `_injectPointerForTest` (headless synthetic-pointer hook). Files edited: `util/states.swift` (ported `enterEmphasisWhenMouseOver`/`leaveEmphasisWhenMouseOut` (states.ts:360-372, the `!shouldSilent && __highByOuter==0` gate so an API highlight is not clobbered by hover) + `setStatesStylesFromModel` (reads the model's emphasis/blur/select itemStyle into each element's ZR states)), `chart/bar/BarView.swift` (un-stubbed the emphasis block — each bar `Rect` now gets `setStatesStylesFromModel` + `enableHoverEmphasis`, marking it a highDown dispatcher with its emphasis state style, without disturbing the normal render). **Clean build `buildGreen = true` (0 warnings); `swift test` — 273 executed / 0 failures / 58 skipped** (baseline 271/0/58; +2 = new `ZZLiveHoverTests`: an injected synthetic pointer over bar 0 drives it into emphasis THROUGH the real Handler hit-test → mouseover → listener chain (NOT a shortcut), and a mousemove off all bars clears it via the mouseout leg; + a retain-cycle regression test). Faithfulness reviews: `states`+`BarView` **MINOR-ISSUES** (the full pointer→Handler→emphasis chain traced correct + faithful; normal render untouched); `EChartsView`+binding **CRITICAL-ISSUES**. CRITICAL found + FIXED post-workflow: a **retain cycle** — the `zr.on(evt, closure, self)` listeners passed `self` as the ctx, which `Eventful`/`EventHandler.ctx` stores STRONGLY (and zr→handler→eventful is strongly owned by the view) → `EChartsView` never deallocated (leaking the whole chart graph). Fixed by binding ctx `nil` (the closures already `[weak self]`; `Handler.on` defaults ctx to the handler) on ALL THREE listeners + a `deinit { zr.dispose() }` (removes the zr from the module-global zrender `instances` registry). Locked by `testEChartsViewHasNoRetainCycle`. MINORs FIXED: `findDispatcher` returned the INNERMOST dispatcher for mouseover/mouseout, but upstream returns the OUTERMOST (echarts.ts:2329/2336 — no returnFirstMatch) while click uses first-match (echarts.ts:2343) — added a `returnFirstMatch` param and used it correctly at each site; the click handler dispatched `highlight` (duplicating hover) where upstream toggles SELECTION — changed to `toggleSelect`. DEFERRED (documented): the FOCUS fan-out (`handleGlobalMouseOverForHighDown` → `blurSeries`/`blurComponent` to dim non-focused siblings on hover — the `blurSeries` engine is ported but the global focus handler is not); the `mousemove`→`axisTrigger`→tooltip/axisPointer show; applying `enableHoverEmphasis` in the OTHER series views (only BarView this phase — mechanical follow-up); the public ECharts event bus; `__highDownSilentOnTouch`. Next: apply hover-emphasis across the remaining series views; wire `mousemove`→axisTrigger→tooltip/axisPointer show; dataZoom slider/inside drag. See §64.**

**Phase 32 (dataZoom DATA CORE — the 4th interaction-layer phase; HOST-INDEPENDENT, fully headless): `option.dataZoom = [{start, end}]` now FILTERS/ZOOMS the series data to the window on render — a real, visible, testable effect with NO pointer/host needed. The slider/inside VIEWS + roam/DRAG are DEFERRED (need the live-view host). Files added: `component/dataZoom/DataZoomModel.swift` (base model — target-axis resolution via the model finder, start/end normalization + rangePropMode percent-vs-value, `setRawRange`/`getPercentRange`/`getValueRange`/`findRepresentativeAxisProxy`, per-axis `AxisProxy` construction), `InsideZoomModel.swift` + `SliderZoomModel.swift` (the concrete inside/slider models + defaultOption; VIEW logic deferred), `AxisProxy.swift` (`calculateDataWindow` percent↔value + minSpan/maxSpan clamping, `reset` → sets the scale zoom min/max via the ported `scaleRawExtentInfo.setZoomMM` seam, `filterData` → filters each target series via `SeriesData.filterSelf`/`selectRange` honoring all four `filterMode`s empty/filter/weakFilter/none), `dataZoomProcessor.swift` (the FILTER-stage processor), `dataZoomHelper.swift` (target-axis resolution helpers), `dataZoomAction.swift` (the `dataZoom` action), and `component/helper/sliderMove.swift` (the range-move clamp helper). Files edited: `core/EChartsSlim.swift` — registered `InsideZoomModel`+`SliderZoomModel` (base left unregistered, mirroring visualMap) + the `dataZoom`→`"slider"` subtype defaulter + the dataZoom action, and HOOKED the processor into `update()`'s data-processor stage BEFORE `coordSysMgr.update` (calls `getTargetSeries` — whose side-effect creates each `AxisProxy` — THEN `overallReset`; self-gates to a no-op when no dataZoom component exists). **Clean build `buildGreen = true` (0 warnings); `swift test` — 271 executed / 0 failures / 58 skipped** (baseline 269/0/58; +2 = new `ZZDataZoomTests`: `dataZoom{start:0,end:40}` on 10 categories → value range [0,4] → 10 filtered to 5 (Int AND Double `start`/`end` parity — the Int-vs-Double coercion works); and the no-dataZoom no-op gate → full 10 (no regression)). Faithfulness reviews: `AxisProxy`+`dataZoomProcessor`+`dataZoomHelper` **FAITHFUL** (calculateDataWindow/reset/filterData all faithful across the four filterModes; Int-vs-Double handled; processor self-gates); `models`+registration **CRITICAL-ISSUES** — the CRITICAL was "the data core is never WIRED" (models not registered, no subtype defaulter, processor not invoked) — **RESOLVED post-workflow** by the registration + subtype defaulter + the processor hook above (the previous integrator died before wiring). Also FIXED a real runtime bug caught during integration: `sliderMove.swift` `restrictSlider(_:_ extend:[Double])` re-dispatched to itself (infinite recursion / stack overflow) — disambiguated the overload with `as [Double?]`. DEFERRED (documented): the slider/inside VIEWS + roam/DRAG (need the live-view host); throttle; dataShadow; the `CoordinateSystemHostModel`→`ComponentModel` narrowing (pre-existing helper PORT-TODO). Next: the live-view host (pointer/gesture → dispatchAction) → then the slider/inside views + drag, and the tooltip/axisPointer hover trigger. See §63.**

**Phase 31 (TOOLTIP CONTENT model + `visual/tokens` — the 3rd interaction-layer phase; HOST-INDEPENDENT, fully headless): the tooltip content pipeline lands — given a series + dataIndex, `formatTooltip` now produces real formatted content (a markup tree → html OR richText string). The on-screen `TooltipView` + the hover TRIGGER are DEFERRED (they need the live-view host, a later phase). Files added: `visual/tokens.swift` (the 233-line design-token palette — neutral00..99 grays, the 9-color `theme` array, accent/semantic/shadow/background tokens + the darkColor derivation; many series had been inlining these as PORT-TODO), `component/tooltip/tooltipMarkup.swift` (`createTooltipMarkup` section/nameValue, `buildTooltipMarkup` for BOTH renderMode `html` (`<div>`/`<span>` style strings) and `richText` (`{styleName|text}` tokens), `retrieveVisualColorForTooltipMarker`, `TooltipMarkupStyleCreator`, the gap/indent/sortBlocks-by-order logic via the ported `SortOrderComparator`), `component/tooltip/seriesFormatTooltip.swift` (`defaultSeriesFormatTooltip` — series name + per-dim nameValue blocks), `component/tooltip/TooltipModel.swift` (`TooltipModel` + the full `defaultOption`, reading token colors; `axisPointer` sub-option as a minimal `[String:Any]` stub since axisPointer is unported). Files edited: `model/Series.swift` (un-stubbed `formatTooltip` → `defaultSeriesFormatTooltip`), `model/mixin/dataFormat.swift` + `data/helper/dataProvider.swift` (un-stubbed `retrieveRawValue` — its faithful body was enabled now that `getRawDataItem`/`getStore`/`getDataItemValue` have landed; tooltip reads raw values through it), `core/EChartsSlim.swift` (registered `TooltipModel` with a documented `component/tooltip/install.ts` deferral note — TooltipView/showTip/hideTip/installAxisPointer deferred). **Clean build `buildGreen = true` (0 warnings); `swift test` — 269 executed / 0 failures / 58 skipped** (baseline 264/0/58; +5 = new `ZZTooltipContentTests`: formatTooltip returns a real fragment, and BOTH html + richText content carry the category name AND the value). Faithfulness reviews: `tooltipMarkup`+`seriesFormatTooltip` **MINOR-ISSUES** (byte-identical HTML/richText templates, correct token colors, sortBlocks order, value formatting — verified); `tokens`+`TooltipModel` **MINOR-ISSUES** (ALL token values spot-checked EXACT; defaultOption complete; formatTooltip returns real content). NO CRITICAL. MINORs (documented deferrals, non-blocking): a gradient/pattern visual fill on a tooltip MARKER falls through to `"transparent"` (needs a typed color in the visual style bag — solid colors, the common case, are correct); series with their OWN `formatTooltip` override (map/tree/sankey/…) stay stubbed (base default works for bar/line/etc.). DEFERRED (documented): the on-screen `TooltipView` render + the hover/click TRIGGER (need the live-view host); the `axisPointer` sub-option stub. Next: the live-view host (pointer/gesture events → dispatchAction) → then `TooltipView` + `axisPointer` hover trigger, and `dataZoom`. See §62.**

**Phase 30 (EMPHASIS/BLUR/SELECT state engine + the `updateDirectly` light-update + highlight/downplay/select ACTIONS — the 2nd interaction-layer phase; makes `dispatchAction` actually change element visual state): `util/states.ts` (918 lines) lands, and `dispatchAction({type:"highlight"/"downplay"/"select"/"unselect"/"toggleSelect"})` now drives real element state changes via the light-update path (NO full re-render). Files added: `util/states.swift` (the state engine — `enterEmphasis`/`leaveEmphasis` (ref-counted by highlightDigit via `__highByOuter` bitmask), `enterBlur`/`leaveBlur`, `enterSelect`/`leaveSelect`, `singleEnter*`/`singleLeave*` applied through ZRenderKit `useStates`/`clearStates`, `allLeaveBlur`, `blurSeries` (focus/blurScope self/series/coordinateSystem/global), `blurSeriesFromHighlightPayload`, `toggleSelectionFromPayload`+`updateSeriesElementSelection`, `isHighDownDispatcher`/`setAsHighDownDispatcher`/`getHighlightDigit`, the payload predicates `isHighDownPayload`/`isSelectChangePayload`); `core/actionRegister.swift` (registers highlight/downplay/select/unselect/toggleSelect via the Phase-29 `registerAction`). Files edited: `core/EChartsSlim.swift` (`updateDirectly` (echarts.ts:1772-1866) + `callViewMethod` + the doDispatchAction isHighDown/isSelectChange/cptType branches now call it instead of no-op; + the `__alive` fix below), `view/Chart.swift` (un-stubbed `elSetState`/`toggleHighlight` to call the real states functions), `core/ExtensionAPI.swift` + `SlimExtensionAPI` (emphasis methods + `getViewOfComponentModel` → optional). **Clean build `buildGreen = true` (0 warnings); `swift test` — 264 executed / 0 failures / 58 skipped** (baseline 260/0/58; +4 = new `ZZEmphasisTests`: the states engine enter/leave + digit ref-count, the ExtensionAPI emphasis seam + allLeaveBlur live, and the FULL `dispatchAction(highlight)`→emphasis-on-target / `downplay`→normal round-trip). Faithfulness reviews: `states.swift` engine **MINOR-ISSUES**; the `updateDirectly`/actions wiring **CRITICAL-ISSUES**. TWO CRITICALs found + FIXED post-workflow: (1) **the real blocker, caught by the new round-trip test (not the reviews):** `ChartView.__alive` defaulted `false` and was NEVER set — so `callViewMethod`'s `view.__alive` guard rejected EVERY light-update dispatch (highlight/downplay/updateView reached no view). Fixed by marking each view `__alive = true` when rendered (`renderSeries`/`renderComponents`), matching upstream. (2) **review CRITICAL:** `allLeaveBlur`/`blurSeries` force-unwrapped `getViewOfComponentModel` → crash on any viewless component (e.g. a `polar` component has no `"polar"` view factory) during a highlight/blur dispatch. Fixed structurally: `getViewOfComponentModel` now returns `ComponentView?` (matching upstream's possibly-undefined view) and the call sites guard `if let view` — the type now prevents re-introducing the `!`. MINORs fixed: `Int(Double.nan)` trap in `blurSeriesFromHighlightPayload` (finite-guard → 0, matching JS `||0`); `[Int]` index-array missed by `as? [Double]` in `toggleSelectionFromPayload`. DEFERRED (documented): `enableHoverEmphasis` mouse-over/out BINDING (needs the live pointer host); per-view `toggleHoverEmphasis` that marks series elements as highDown dispatchers (so a bare `highlight` on e.g. a bar is gated off until each view opts its elements in — the primitive works, proven by the test manually marking a dispatcher); `blurComponent`'s `focusBlurEnabled` gate (component-highDown is unwired); state animation transitions. Next: `axisPointer` → `tooltip` → `dataZoom`; then the live-view host. See §61.**

**Phase 29 (ACTION/EVENT SUBSTRATE — the first INTERACTION-layer phase; CONVENTIONS §5 static-first LIFTED by the user now that all rendering is done): the `dispatchAction` round-trip lands, giving the port its first interaction primitive. This is "Phase A step 1" of the interaction plan (see `INTERACTION_LAYER_PLAN.md`): programmatic `ec.dispatchAction(payload)` → look up the registered action → run its handler → re-render through the EXISTING `update()`/`render()` pipeline. HEADLESS — no UIView/live-view host, no pointer/gesture events yet (deferred). Files added: `core/action.swift` (the module-global `actions` registry + `ActionInfo`/`ActionInfoParsed`/`ActionHandler`, the `registerAction` 3-overload family faithfully ported from `echarts.ts:2876-2914,3114-3190` — isFunction(arg1) collapse, createEventType lowercasing, nonRefinedEventType, the `ACTION_REG` validate, the dedup early-return — plus `lookupAction` and the `registers.registerAction(...)` forwarders). Files edited: `core/EChartsSlim.swift` (`public func dispatchAction(_:_:)` + `doDispatchAction` + the `_pendingActions` re-entrancy queue + `_inEcCycle` guard + `flushPendingActions`, faithful to `echarts.ts:1574-1624,2148-2233,2274-2300`; `SlimExtensionAPI.dispatchAction` override; a `DispatchActionOpt`), `core/ExtensionAPI.swift` (abstract `dispatchAction`). **Clean build `buildGreen = true` (0 warnings); `swift test` — 260 executed / 0 failures / 58 skipped** (baseline 258/0/58; +2 = new `ZZActionDispatchTests` proving the round-trip headlessly: a registered action runs with the correct ecModel/api AND triggers a fresh re-render (rebuilt display-list instances), and an unregistered type is a silent no-op). Faithfulness reviews: BOTH **FAITHFUL** (registry + registerAction overloads; the dispatch guard-order/pending-queue/batch/update-dispatch). CRITICAL found + FIXED post-workflow (via the new round-trip test, NOT the reviews): `EChartsSlim.update()` was NOT idempotent — the per-full-update axis-statistics cache (`getCachePerECFullUpdate`) was a never-reset placeholder, so a SECOND `update()` on the same `GlobalModel` (i.e. any `dispatchAction` re-render) re-associated the same `<axis,series>` pairs and tripped the DEV duplicate-pair assert in `associateSeriesWithAxis` (crash). Fixed by porting `resetCachePerECFullUpdate(ecModel)` (swap in a fresh cache host, dropping the stale makeInner records) and calling it at the start of `update()` — matching upstream `updateMethods.update` (echarts.ts:1892). This makes `update()` correctly re-runnable, the foundation the whole interaction layer stands on; safe for the existing single-update tests (resetting an already-fresh cache is a no-op). DEFERRED (documented, next phases): partial-update (updateView/updateLayout/updateVisual collapse to full `update()`); the emphasis/select light-update branch (`updateDirectly` + `util/states.ts` ≈1000 lines) → Phase 30; the live-view host (real pointer/gesture events) → later. See §60 and `INTERACTION_LAYER_PLAN.md`.**

**Phase 28 (BUILT-IN dataset transforms `filter` + `sort` + the `conditionalExpression` evaluator — completes the Phase-27 dataset/transform story; PURE DATA, not §5-deferred): the two built-in external transforms register out-of-the-box in `EChartsSlim`, so `dataset: { transform: { type: 'filter', config: … } }` and `{ type: 'sort', config: … }` work WITHOUT the user calling `registerExternalTransform`. Files added: `util/conditionalExpression.swift` (the relational + logical expression parser/evaluator — the `lt`/`lte`/`gt`/`gte`/`eq`/`ne`/`reg` comparison ops via `RELATIONAL_EXPRESSION_OP_ALIAS_MAP` + `dataValueHelper.createFilterComparator`, the `and`/`or`/`not`/`true` combinators with fail-fast + short-circuit `evaluate()`, and the `RegExpEvaluator` reproducing upstream's always-stringify quirk); `component/transform/filterTransform.swift` (`echarts:filter` — builds the condition, loops the upstream rows, pushes each row where `condition.evaluate()` is true, fail-fast so a missing condition yields empty not the whole dataset); `component/transform/sortTransform.swift` (`echarts:sort` — asc/desc, multi-key array config, the time/number `parser`, and `incomparable` min/max placement, all via the REUSED `dataValueHelper.SortOrderComparator`/`getRawValueParser`, with an index-decorated stable sort since Swift `sort(by:)` is not stable); `component/transform/transformInstall.swift` (`transformInstall` registering both via `registerExternalTransform`, called in `installOnce`). **Clean build `buildGreen = true` (0 warnings); `swift test` — 258 executed / 0 failures / 58 skipped** (baseline was 256/0/58; +2 = new `ZZBuiltinTransformTests` driving filter + sort through a real `setOption` with NO manual registration). Faithfulness reviews: `sortTransform`+`transformInstall` **MINOR-ISSUES** (faithful; install verified wired; the invalid-config `try! throwError` traps match the port's dev-error pattern). `conditionalExpression`+`filterTransform` **CRITICAL-ISSUES** — **FIXED post-workflow**: the CRITICAL is again the Int-vs-Double trap — an integer filter threshold written as an option literal (`gt: 15`) boxes as Swift `Int`, which the Double-only `util.isNumber` gate in `createFilterComparator` rejects → order ops (lt/lte/gt/gte) silently disabled / a fatal throw. The translator had already routed the operand through a `jsNumberize(...)` coercion at the option-read boundary but left the helper undefined (build error); I defined `jsNumberize` (Int/NSNumber→Double, Bool/String untouched) in `conditionalExpression.swift`, which makes `gt: 15` compare correctly. Locked by `ZZBuiltinTransformTests` using an `Int` literal `gt: 15` (keeps 2 rows). DOCUMENTED latent minor (NOT introduced by this phase): `eq`/`ne` against Int-boxed **data** values goes through `dataValueHelper`'s `jsTypeof`/`jsStrictEquals`, which lack an `Int` case — a pre-existing shared-infra edge, unexercised, left for a future dataValueHelper pass rather than an unreviewed change here. This completes the dataset+transform data path (source → transform → series) end-to-end. See §59.**

**Phase 27 (DATASET component + TRANSFORM pipeline — the data-layer of the remaining component surface; NOT §5-interaction-deferred): the `dataset` component registers end-to-end in `EChartsSlim`, and the external data-transform pipeline lands. This wires `option.dataset` / `datasetIndex` / `datasetId` / `seriesLayoutBy` / `sourceHeader` / `transform` / `fromDatasetIndex` / `fromTransformResult` so a series with NO own `data` reads its rows from a dataset's `source`, and a `{ transform: … }` dataset produces a derived source consumed downstream. Registered: `DatasetModelImpl` (concrete `ComponentModel`, type `dataset`, conforming to the data-layer `DatasetModel` protocol) + `DatasetView` (static shell) via `datasetInstall`, called first in `installOnce` so datasets exist before series query them. The previously-stubbed dataset branches in `data/helper/sourceManager.swift` are now fully un-stubbed and wired: `_getUpstreamSourceManagers` (series→dataset via `querySeriesUpstreamDatasetModel`; dataset→dataset via `queryDatasetUpstreamDatasetModels`), the `_createSource` dataset host branch (root dataset reads `source`; non-root applies transform), `_applyTransform` (piped vs single, the `fromTransformResult` single-upstream guard), the `_getSourceMetaRawOption` dataset branch, and `disableTransformOptionMerge`. `data/helper/sourceHelper.swift`'s `querySeriesUpstreamDatasetModel` / `queryDatasetUpstreamDatasetModels` are ported (from stubs). Files added: `component/dataset/datasetInstall.swift` (`DatasetModelImpl` + `DatasetView` + `datasetInstall`), `data/helper/transform.swift` (the full external-transform pipeline: `DataTransformOption`/`PipedDataTransformOption`/`ExternalDataTransform`, `externalTransformMap` + `registerExternalTransform`, `applyDataTransform`/`applySingleDataTransform`, and the `ExternalSource` wrapper with getRawData/getRawDataItem/count/getDimensionInfo/retrieveValue/cloneRawData). Files edited: `sourceManager.swift`, `sourceHelper.swift`, `core/EChartsSlim.swift` (register dataset), and `model/Global.swift` (see CRITICAL fix). **Clean build `buildGreen = true` (0 warnings); `swift test` — 256 executed / 0 failures / 58 skipped** (baseline was 254/0/58; +2 = new `ZZDatasetProbeTests`: dataset→series source read, and a filter-transform chain). Faithfulness reviews: `datasetInstall.swift`+`transform.swift` **FAITHFUL** (0 CRITICAL; every `applyDataTransform` branch + `ExternalSource` verified, Int-vs-Double & `|| 0` traps defended); `sourceManager.swift` dataset branches **MINOR-ISSUES** (stale \"unreachable\" comments — **FIXED post-workflow**; series source path unchanged/faithful); `sourceHelper.swift`+`EChartsSlim` registration **CRITICAL-ISSUES** (1) — **FIXED post-workflow**: an explicit Int-literal `datasetIndex`/`fromDatasetIndex` (e.g. `datasetIndex: 1`) boxed as Swift `Int` failed `normalizeToArray<Double>`'s `as? Double`, so `queryComponents` resolved to NO dataset → the series rendered empty (the documented Int-vs-Double option-read trap). Fixed at the shared choke point `GlobalModel.queryComponents` (`Global.swift`) with an Int/Double/NSNumber index coercion — this ALSO repairs every other explicit-index component ref (`xAxisIndex`/`polarIndex`/`gridIndex`/…) that flowed through the same path; locked by the `ZZDatasetProbeTests` transform test now using an `Int` literal `datasetIndex`. Deferred per CONVENTIONS §5: `DatasetView` is a static shell (no interaction); non-built-in external transforms' object-row cast is a project-wide `Any?`-bridging concern. This lands the dataset/transform DATA path end-to-end. See §58.**

**Phase 26 (CUSTOM series / `renderItem` — the 22nd and LAST chart type; this ports ALL 22 upstream chart types; transition/animation/morph/states DEFERRED): the `custom` series registers end-to-end in `EChartsSlim` — `CustomSeriesModel` (type `series.custom`) + the `custom` view (`CustomView`). Custom is the user-programmable series: the option supplies a **`renderItem` Swift-closure** that, per data item, returns a graphic-element spec; `CustomView` dispatches that closure and builds the returned elements (`group`/`rect`/`circle`/`sector`/`polygon`/`polyline`/`line`/`bezierCurve`/`arc`/`image`/`text` …) into real `ZRenderKit` shapes, positioned through the ported coordinate systems — the **static element builders** run across the ported coord systems (cartesian, polar, geo, calendar, …) via the coord-provided `api` (coordSys/value/size helpers). This lands the port's **22nd chart type**, which makes **ALL 22 upstream chart types ported** end-to-end. Files added: `chart/custom/{CustomSeries,CustomView,customInstall,customSeriesRegister}.swift`; demo `custom-basic` + `CustomRenderTests`. **Clean build `buildGreen = true`; `swift test` — 254 executed / 0 failures / 58 skipped** (baseline was 253/0/58; +1 = new `CustomRenderTests`). No regressions. Deferred PORT-TODOs per CONVENTIONS §5: the `transition`/animation/**morph** paths, the enter/update/leave **diff** (elements are rebuilt from scratch, not diffed), `states`/emphasis, and the legacy-compat (`renderItem` legacy element) shims — all DEFERRED. Faithfulness reviews: `chart/custom/CustomView.swift` **CRITICAL-ISSUES** (2 findings) — **both FIXED post-workflow**: (1) `api.coord`/`api.size` hard-cast the prepareCustom closures to the exact cartesian signature, so on single/calendar/matrix (whose prepareCustom closures have different Swift signatures) the cast yielded nil and `api.coord` returned `[]` (every element at the origin) — `coord()` now falls back to the generic `CoordinateSystem.dataToPoint` when the closure is nil, so custom projects on ALL coord systems; (2) `api.visual` used wrong maps — corrected to upstream's `STYLE_VISUAL_TYPE = {color:'fill', borderColor:'stroke'}` + `NON_STYLE_VISUAL_PROPS = {symbol, symbolSize, symbolKeepAspect, legendIcon, visualMeta, liftZ, decal}`. `chart/custom/CustomSeries.swift` **MINOR-ISSUES** (1 — `currentZLevel` defaults 0 vs upstream `undefined`; low, documented). This makes **ALL 22 upstream chart types** ported end-to-end. See §57.**

**Phase 25 (MATRIX COORDINATE SYSTEM — the 8th and LAST coordinate system: a table/grid coord; interaction DEFERRED): the `matrix` coordinate system registers end-to-end in `EChartsSlim` — after `cartesian2d` (grid), `radar`, `polar`, `single`, `parallel`, `calendar`, and `geo`, this is the port's **8th coordinate system** and completes **ALL of upstream's coordinate systems** (cartesian/radar/polar/single/parallel/calendar/geo/matrix). Unlike the others it is a **table/grid**: two dimensions (x/y) whose values are header cells arranged in a (possibly nested) header tree, and a body region of value cells at the row×column intersections. Registered: the `matrix` coord-system creator (`CoordinateSystemManager.register("matrix", …)` → `matrixCoordHelper`, forwarding to `Matrix.create` / `Matrix.dimensions`) + `MatrixModel` (via `ComponentModel.registerClass`) + the `"matrix"` component view factory (`MatrixView`, drawing the header-cell + body-cell + corner `Rect`s and their divider `Line`s + cell labels). The table pipeline: `Matrix` builds the two `MatrixDim` header dimensions (x and y), each `MatrixDim` resolving its (possibly nested) header-cell tree — leaf/non-leaf cell spans, depth, and per-cell pixel rects — and `MatrixBodyCorner` supplies the body value-cell and top-left corner-cell geometry; `dataToPoint`/`dataToLayout` map a `[xValue,yValue]` cell coordinate to its pixel rect via the two dims. Files added: `coord/matrix/{Matrix,MatrixDim,MatrixBodyCorner,MatrixModel,matrixCoordHelper,matrixPrepareCustom}.swift`, `component/matrix/MatrixView.swift`; demo `matrix-basic` + `MatrixRenderTests`. Clean build `buildGreen = true`; `swift test` **Executed 253 tests, with 58 tests skipped and 0 failures (0 unexpected)** — baseline 251 + 2 new `MatrixRenderTests`; no regression. Deferred PORT-TODOs per CONVENTIONS §5: all matrix INTERACTION — cell select/highlight, roam pan/zoom, and the tooltip/emphasis paths — DEFERRED (static table render only). Faithfulness reviews: `coord/matrix/Matrix.swift` **FAITHFUL** (0 findings), `coord/matrix/MatrixDim.swift` **MINOR-ISSUES** (2 findings), `coord/matrix/matrixCoordHelper.swift` **FAITHFUL** (0 findings), `component/matrix/MatrixView.swift` **MINOR-ISSUES** (2 findings). No CRITICAL findings; `buildGreen = true`. This makes **8 coordinate systems** ported end-to-end — **ALL of upstream's coordinate systems** (cartesian/radar/polar/single/parallel/calendar/geo/matrix). See §56.**

**Phase 24 (MAP CHART on the geo coord — the 21st chart type; integrated MANUALLY after the workflow hit a session limit): the `map` chart registers end-to-end in `EChartsSlim`, reusing the Phase-23 `geo` coordinate system + `registerMap`. `MapSeriesModel` (type `series.map`, coordinateSystem `geo`) builds `{name,value}` region data via `createSeriesDataSimply`; `MapView` draws each geo **Region** as a filled `Polygon`/`Path` at the projected rings (`Geo.dataToPoint`) — the region fill is the per-region series-data item visual (region name → `data.indexOfName` → item style, the visualMap `style.fill` override when visual-encoded, else the region `itemStyle`/`areaColor`), plus the region name label and (via `mapSymbolLayout`) the region symbol markers; `mapDataStatistic` computes the shared-map data min/max. Files added: `chart/map/{MapSeries,MapView,mapSymbolLayout,mapDataStatistic,mapInstall}.swift`; demo `map-basic` (registerMap a toy 3-region GeoJSON + a `type:"map"` series with per-region data) + `MapRenderTests`. Clean build `buildGreen = true` (0 product warnings); `swift test` **251 executed / 0 failures / 58 skipped** (baseline 249 + 2 new `MapRenderTests`). The 2 translate agents finished; the integrate agent completed the wiring + build-fix (register `MapSeriesModel` + `"map"` view + wire the real `MapSeries` type into `geoCreator`'s map-series-geo path) but died on the session limit before returning, so registration + demo + test were already in place. Faithfulness reviews (run after the limit reset): `chart/map/MapView.swift` **FAITHFUL** (0), `chart/map/MapSeries.swift` **MINOR-ISSUES** (1 — the `properties.echartsStyle` merge onto an EXISTING data item is deferred, already a source PORT-TODO; rare, and regions absent from `data` are handled). DEFERRED per CONVENTIONS §5: roam pan/zoom, the effect/large draw paths, `MapDraw`/state (emphasis/select) infra. This makes **21 chart types**. See §55.**

**Phase 23 (GEO COORDINATE SYSTEM + GeoJSON — the 7th coordinate system wired end-to-end in `EChartsSlim`; SVG-map + roam pan/zoom DEFERRED): the `geo` coordinate system registers end-to-end — after `cartesian2d` (grid), `radar`, `polar`, `single`, `parallel`, and `calendar`, this is the port's **7th coordinate system** (a GeoJSON-backed map projection). Registered in `EChartsSlim`: the `geo` coord-system creator (`CoordinateSystemManager.register("geo", …)` → `geoCreator`, which reads registered map JSON and builds `Geo` instances) + the `registerMap` API (the map-registry entry point that parses + stores GeoJSON by name) + `GeoModel` (via `ComponentModel.registerClass`) + the `"geo"` component view factory (`GeoView`, drawing each region's boundary `Polygon`/`Path`s + region name labels). The GeoJSON pipeline: `parseGeoJSON` decodes a GeoJSON FeatureCollection into `Region`s (each region = a named set of polygon/hole rings + a precomputed bounding rect + label center); `Geo` holds the region list and a projection (`dataToPoint`/`pointToData` map lon/lat ↔ pixel via the geo-rect → view-rect linear transform, y-flipped). **This UNLOCKS the map chart (next phase)** — the map series will render its shapes on this geo coord system. Files added: `coord/geo/{Geo,Region,geoCreator,GeoModel,geoJSONLoader,parseGeoJSON}.swift` (map-registry + GeoJSON parse + Region + Geo projection), `component/geo/GeoView.swift`; demo `geo-basic` + `GeoRenderTests`. Clean build `buildGreen = true`; `swift test` **Executed 249 tests, with 58 tests skipped and 0 failures (0 unexpected)** — baseline 247 + 2 new `GeoRenderTests`; no regressions. Deferred PORT-TODOs per CONVENTIONS §5: the `GeoSVGResource` (SVG-map source), roam pan/zoom (the `RoamController` interaction), the pluggable `projection` object (only the default linear lon/lat projection lands), and geo `specialAreas` — all DEFERRED. Faithfulness reviews: `coord/geo/Region.swift` **MINOR-ISSUES** (2 findings), `coord/geo/Geo.swift` **FAITHFUL** (0), `coord/geo/geoCreator.swift` **MINOR-ISSUES** (3 findings), `component/geo/GeoView.swift` **FAITHFUL** (0). No CRITICAL findings; `buildGreen = true`. **3 of the 5 MINOR findings FIXED post-workflow** — the two crash-on-malformed-input cases (parseGeoJson odd-length encoded string → bounded the pair loop; geoCreator short `boundingCoords` inner array → NaN-guarded so the existing isFinite check skips it, both matching upstream's graceful no-throw) and the `layoutSize` falsy guard (geoCreator `centerOption && sizeOption` now uses JS-truthy `geoOptTruthy`, so a boxed `0`/`""` layoutSize no longer collapses the geo to size 0). The 2 remaining MINOR are latent edge cases left documented (Region.transformTo double-transform on a cloned/aliased region; geoCreator merging two same-named source regions) — neither is reachable on the common GeoJSON path. This makes **7 coordinate systems** ported end-to-end. See §54.**
**Phase 22 (HEATMAP chart — the 20th chart type wired end-to-end in `EChartsSlim`, on cartesian, colored by the Phase-21 `visualMap` encoding; geo/large-blur `HeatmapLayer` + calendar paths DEFERRED): the `heatmap` chart registers end-to-end and is **the payoff of Phase 21** — the visualMap value→visual encoding unlocks it. Registered: `HeatmapSeriesModel` (via `ComponentModel.registerClass`) + the `"heatmap"` view factory (`HeatmapView`). On a cartesian grid `HeatmapView` draws one colored `Rect` **cell** per datum, sized to the axis band and **colored from `getItemVisual("color")`** — the per-datum color stamped by the Phase-21 `visualEncoding` stage (the visualMap encoder). Files added: `chart/heatmap/HeatmapSeries.swift` (`HeatmapSeriesModel`), `chart/heatmap/HeatmapView.swift` (the cartesian colored-Rect cell render), `chart/heatmap/heatmapInstall.swift`; demo `heatmap-basic` + `HeatmapRenderTests`. Clean build `buildGreen = true`; `swift test` **Executed 247 tests, with 58 tests skipped and 0 failures (0 unexpected)** — baseline 246 + 1 new `HeatmapRenderTests` test; no regressions. Deferred PORT-TODOs per CONVENTIONS §5: the geo-coordinate blurred `HeatmapLayer` (the gradient/large-blur pixel path), the large/progressive draw path, and the calendar-coordinate branch (heatmap-on-calendar) — all DEFERRED; this phase lands the cartesian colored-cell heatmap only. Faithfulness reviews — ALL **FAITHFUL** (0 findings each): `chart/heatmap/HeatmapView.swift` (FAITHFUL/0), `chart/heatmap/HeatmapSeries.swift` (FAITHFUL/0). No CRITICAL findings; nothing to fix. This makes **20 chart types** ported end-to-end. See §53.**
**Phase 21 (visualMap ENCODING CORE — the value→visual encoder + models + the `visualEncoding` VISUAL stage; the interactive control WIDGET DEFERRED): the value→visual encoding half of `visualMap` registers end-to-end in `EChartsSlim` — enough to map data values to visual channels (color/opacity/symbolSize/…), but NOT the on-screen draggable control (that interactive widget is DEFERRED). Registered: `ContinuousVisualMapModel` + `PiecewiseVisualMapModel` (via `ComponentModel.registerClass`), the `visualMap` sub-type typeDefaulter (`continuous`/`piecewise`), the `visualMapPreprocessor`, the `visualEncoding` **VISUAL stage** (the `seriesVisualMap`/`visualMapVisual` value→visual pipeline that stamps each datum's visual from the model's `VisualMapping`), and a **minimal `VisualMapView`** (registration placeholder — the interactive control render is DEFERRED). The core encoder is `visual/VisualMapping.swift` — the faithful value→visual mapper (piecewise/category/linear mapping methods). **This UNLOCKS the heatmap chart (next phase), whose color comes from a visualMap.** Files added: `visual/VisualMapping.swift` (the encoder) + `visual/{visualDefault,visualSolution}.swift`; the whole `component/visualMap/` vertical — `VisualMapModel.swift` (base) + `ContinuousModel.swift` + `PiecewiseModel.swift` + `typeDefaulter.swift` + `visualMapPreprocessor.swift` + `visualEncoding.swift` + `visualMapHelper.swift` + `installCommon.swift` + the minimal `VisualMapView.swift`/`ContinuousView.swift`/`PiecewiseView.swift` + `visualMapAction.swift`; demo `visualmap-basic` + `VisualMapEncodingTests`. Clean build `buildGreen = true`; `swift test` **246 executed / 0 failures / 58 skipped** (baseline 244 preserved + 2 new `VisualMapEncodingTests`); zero regressions. Deferred PORT-TODOs per CONVENTIONS §5: the interactive control WIDGET — the drag/hover handle, the range indicator, and the hover-highlight/select actions (`visualMapAction` select/highlight, the continuous drag-range interaction, the piecewise item toggle) — all DEFERRED (the models + value→visual encoding + minimal view only). Faithfulness reviews — ALL **FAITHFUL**: `visual/VisualMapping.swift` FAITHFUL (2 findings), `component/visualMap/ContinuousModel.swift` FAITHFUL (0), `component/visualMap/PiecewiseModel.swift` FAITHFUL (0), `component/visualMap/visualEncoding.swift` FAITHFUL (1). No CRITICAL findings; `buildGreen = true`. The 3 MINOR findings are **NOT yet fixed** — to be handled by the main loop post-workflow. See §52.**
**Phase 20 (CALENDAR coordinate system — the 6th coord system + its component view; integrated MANUALLY after the workflow hit a session limit): the `calendar` coordinate system registers end-to-end in `EChartsSlim` — a grid of day cells keyed by DATE (after cartesian/radar/polar/single/parallel). Registered: `CalendarCoordinateSystemCreator` (forwards to `Calendar.create` / `Calendar.dimensions` `["time","value"]`) via `CoordinateSystemManager.register("calendar", …)` + `ComponentModel.registerClass(CalendarModel)` + the `"calendar"` component view factory (`CalendarView`, drawing the month/day-cell grid outline Polylines + day-rect + day/week/month/year labels from the `Calendar` cell geometry). Files added: `coord/calendar/{Calendar,CalendarModel,calendarPrepareCustom}.swift`, `component/calendar/CalendarView.swift`, and a NEW `util/graphic.swift` (partial — `expandOrShrinkRect`/`expandRectOnOneDimension`, the rect expand/shrink helper the calendar outline needs; Grid references it too); demo `calendar-basic` + `CalendarRenderTests`. Clean build `buildGreen = true` (0 product warnings); `swift test` **244 executed / 0 failures / 58 skipped** (baseline 243; +1 `CalendarRenderTests`). Manual-integration fixes: (1) `Calendar` (the coord class) SHADOWS `Foundation.Calendar` module-wide — qualified the Foundation uses in `util/{format,time,number}.swift` + `time.calendar(_:) -> Foundation.Calendar` + the creator's `EChartsKit.Calendar`; (2) the two date-modeling agents disagreed (coord `JSDate` reference wrapper vs view `Foundation.Date`) → `CalendarView` now mutates the `JSDate` in place (`setMonth`) like upstream; (3) landed `expandOrShrinkRect`; (4) RUNTIME CRASH (index-out-of-range in `_renderMonthText`/`_renderWeekText`): the not-yet-ported locale model supplies no `time.monthAbbr`/`dayOfWeekAbbr`, so the label `nameMap[i]` index blew up — added EN-locale fallbacks (documented locale-not-ported bridge). Faithfulness review (run after the limit reset): `Calendar.swift` date math **FAITHFUL** (0 findings) — getDateInfo day-of-week, _getRangeInfo weeks/nthWeek, getDateByWeeksAndDay/getNextNDay advancement, dataToPoint/dataToRect cell mapping + orient swap all match upstream, and the `JSDate` setDate/setMonth rollover was empirically confirmed against JS `Date` semantics. DEFERRED: scatter/heatmap-on-calendar (ScatterView calendar branch). This makes **6 coordinate systems**. See §51.**
**Phase 19 (CHORD circular flow chart — COORDLESS: the 19th chart type wired end-to-end in `EChartsSlim`, reusing the ported `Graph` + `createGraphFromNodeEdge`): the chord (circular flow) chart registers coordless (box/view usage — no coordinate system, like pie/funnel/gauge, sankey, and the tree-family). Registered: `ChordSeriesModel` (reusing the Phase 11 `createGraphFromNodeEdge` to build its node/edge `Graph`) + the `"chord"` view factory (`ChordView`) + the `chordCircularLayout` overall stage. `ChordView` draws the node **arc `Sector`s** (`ChordPiece`) laid around the circle + the bezier-ribbon edge **`Path`s** (`ChordEdge` — the curved flow ribbons between node arcs). Files added: `chart/chord/ChordSeries.swift` (`ChordSeriesModel`), `chart/chord/ChordView.swift` (node arc Sectors + bezier-ribbon edge Paths), `chart/chord/ChordPiece.swift` (the node arc Sector piece), `chart/chord/ChordEdge.swift` (the bezier-ribbon edge path), `chart/chord/chordLayout.swift` (`chordCircularLayout`), `chart/chord/chordInstall.swift`; demo `chord-basic` + a chord render test. Clean build `buildGreen = true`; `swift test` **Executed 243 tests, with 58 tests skipped and 0 failures (0 unexpected)** (baseline was 242/0/58; +1 is the new `ChordRenderTests`). Deferred PORT-TODOs per CONVENTIONS §5: interaction/decoration (emphasis/states, enter/update animation, label-layout niceties, drag/roam) deferred as in prior chart phases. Faithfulness reviews: `chart/chord/chordLayout.swift` **MINOR-ISSUES** (1 finding); `chart/chord/ChordEdge.swift` (FAITHFUL/0), `chart/chord/ChordView.swift` (FAITHFUL/0), `chart/chord/ChordSeries.swift` (FAITHFUL/0). No CRITICAL findings; build is green. **The 1 MINOR finding is FIXED post-workflow**: `chordLayout` read `nodeValues[i] ?? 0` (nil-only) where upstream is JS `nodeValues[i] || 0` (also sheds NaN) — a value-less link makes an accumulator NaN and `?? 0` propagated it into `nodeValueSum` → `unitAngle` NaN → the whole chord failed to render; replaced the 6 `nodeValues` reads with an `orZero` (nil/NaN→0) helper. This makes **19 chart types** ported end-to-end. See §50.**
**Phase 18 (effectScatter + lines charts — the 17th & 18th chart types wired end-to-end in `EChartsSlim`, reusing existing coord systems; effect/ripple/large animations DEFERRED): both `effectScatter` and `lines` register end-to-end. `effectScatter` reuses the existing coord systems and renders as **static symbols** (the animated ripple effect DEFERRED). `lines` draws **straight / bezier-curve / polyline segments between coords** (one `Path` per line datum: straight two-point, curved single-bezier, or a multi-point polyline). Registered: `EffectScatterSeriesModel` + the `"effectScatter"` view factory (`EffectScatterView`); `LinesSeriesModel` + the `"lines"` view factory (`LinesView`) + the `linesLayout` stage. Files added: `chart/effectScatter/{EffectScatterSeries,EffectScatterView,effectScatterInstall}.swift`, `chart/lines/{LinesSeries,LinesView,linesLayout,linesInstall}.swift`; demos `effectscatter-basic` + `lines-basic` + 2 new render tests. Clean build `buildGreen = true`; `swift test` — **242 executed / 0 failures / 58 skipped (baseline 240; +2 new render tests)**, zero regressions. Deferred PORT-TODOs per CONVENTIONS §5: effectScatter ripple (animated effect symbols); lines effect / moving-dot animation + large/progressive draw path + geo/polar coord paths; interaction/decoration (emphasis/states, enter/update animation) as in prior chart phases. Faithfulness reviews — ALL **FAITHFUL** (0 findings each): `chart/effectScatter/EffectScatterView.swift` (FAITHFUL/0), `chart/lines/LinesView.swift` (FAITHFUL/0), `chart/lines/linesLayout.swift` (FAITHFUL/0), `chart/lines/LinesSeries.swift` (FAITHFUL/0). No CRITICAL findings; nothing to fix. This makes **18 chart types** ported end-to-end. See §49.**
**Phase 17 (PARALLEL COORDINATE SYSTEM — the 5th coord system — + the PARALLEL chart; brush/axis-drag interaction DEFERRED): the `parallel` coordinate system registers end-to-end in `EChartsSlim` — after `cartesian2d` (grid), `radar`, `polar`, and `single`, this is the port's **5th coordinate system** (a set of N parallel axes; each data item is a polyline threading all axes). Registered: the `parallel` coord-system creator (`CoordinateSystemManager.register("parallel", ...)` → `parallelCreator`) + the `ParallelModel` + `ParallelAxisModel` components + the `ParallelComponentView` component view (draws the parallel axes), alongside the whole `chart/parallel/` vertical — `ParallelSeriesModel` + the `"parallel"` view factory (`ParallelView`) + the `parallelVisual` stage + the `parallelPreprocessor`. `ParallelView` draws one **polyline `Path` per data item** threading all the parallel axes; `ParallelComponentView` draws the N axes laid out by the coord system. Files added: `coord/parallel/{Parallel,ParallelAxis,ParallelAxisModel,parallelCreator,ParallelModel,parallelPreprocessor}.swift`, `component/parallel/ParallelComponentView.swift`, `chart/parallel/{ParallelSeries,ParallelView,parallelVisual,parallelInstall}.swift`; demo `parallel-basic` + a new Parallel render test. Clean build `buildGreen = true`; `swift test` — **Executed 240 tests, with 58 tests skipped and 0 failures (0 unexpected)** — up from a 239-test baseline (+1 new `ParallelRenderTests`), zero regressions. Deferred PORT-TODOs per CONVENTIONS §5: brush / areaSelect / axis-drag / roam interaction deferred (static parallel render only), as in prior chart phases. Faithfulness reviews — ALL **FAITHFUL** (0 findings each): `coord/parallel/Parallel.swift` (FAITHFUL/0), `chart/parallel/ParallelView.swift` (FAITHFUL/0), `component/parallel/ParallelComponentView.swift` (FAITHFUL/0), `coord/parallel/ParallelModel.swift` (FAITHFUL/0). No CRITICAL findings; nothing to fix. This makes **16 chart types** and **5 coordinate systems** ported end-to-end. See §48.**
**Phase 16 (SINGLE COORDINATE SYSTEM — the 4th coord system — + the THEMERIVER streamgraph chart): the `single` coordinate system registers end-to-end in `EChartsSlim` — after `cartesian2d` (grid), `radar`, and `polar`, this is the port's **4th coordinate system** (a single one-dimensional axis, used by ThemeRiver). Registered: the `single` coord-system creator (`CoordinateSystemManager.register("single", ...)` → `singleCreator`) + the `SingleAxisModel` component + the `SingleAxisView` axis component view, alongside the whole `chart/themeRiver/` vertical — `ThemeRiverSeriesModel` + the `"themeRiver"` view factory (`ThemeRiverView`) + the `themeRiverLayout` overall stage. ThemeRiver is a streamgraph — `ThemeRiverView` draws the stacked, smoothed river bands (one smooth `Polygon`/`Path` band per series layer) laid out along the single axis by `themeRiverLayout`. Files added: `coord/single/{Single,SingleAxis,SingleAxisModel,singleCreator,singleAxisHelper,singlePrepareCustom}.swift`, `component/axis/SingleAxisView.swift`, `chart/themeRiver/{ThemeRiverSeries,ThemeRiverView,themeRiverLayout,themeRiverInstall}.swift`; demo `themeriver-basic` + a new ThemeRiver render test. Clean build `buildGreen = true`; `swift test` — **Executed 239 tests, with 58 tests skipped and 0 failures (0 unexpected)** (baseline 238 + 1 new `ThemeRiverRenderTests`; no regressions). Deferred PORT-TODOs per CONVENTIONS §5: interaction/decoration (emphasis/states, enter/update animation, label-layout niceties) deferred as in prior chart phases. Faithfulness reviews — ALL **FAITHFUL** (0 findings each): `coord/single/Single.swift` (FAITHFUL/0), `chart/themeRiver/themeRiverLayout.swift` (FAITHFUL/0), `chart/themeRiver/ThemeRiverView.swift` (FAITHFUL/0), `component/axis/SingleAxisView.swift` (FAITHFUL/0). No CRITICAL findings; nothing to fix. This makes **15 chart types** and **4 coordinate systems** ported end-to-end. See §47.**
**Phase 15 (SANKEY FLOW CHART — COORDLESS: the 14th chart type wired end-to-end in `EChartsSlim`, reusing the ported `Graph` + `createGraphFromNodeEdge`): the sankey (flow) chart registers coordless (box/view usage — no coordinate system, like pie/funnel/gauge and the tree-family). Registered: `SankeySeriesModel` (reusing the Phase 11 `createGraphFromNodeEdge` to build its node/edge `Graph`) + the `"sankey"` view factory (`SankeyView`) + the `sankeyLayout`/`sankeyVisual` overall stages. `SankeyView` draws the node **`Rect`s** + the bezier-ribbon edge **`Path`s** (the curved flow ribbons between nodes). Files added: `chart/sankey/SankeySeries.swift` (`SankeySeriesModel`), `chart/sankey/SankeyView.swift` (node Rects + bezier-ribbon edge Paths), `chart/sankey/sankeyLayout.swift`, `chart/sankey/sankeyVisual.swift`, `chart/sankey/sankeyInstall.swift`; demo `sankey-basic` + a sankey render test. Clean build `buildGreen = true`; `swift test` **Executed 238 tests, with 58 tests skipped and 0 failures (0 unexpected)** (baseline was 237/0/58; +1 is the new `SankeyRenderTests`). Deferred PORT-TODOs per CONVENTIONS §5: interaction/decoration (emphasis/states, enter/update animation, label-layout niceties, drag/roam) deferred as in prior chart phases. Faithfulness reviews — ALL **FAITHFUL** (0 findings each): `chart/sankey/sankeyLayout.swift` (FAITHFUL/0), `chart/sankey/SankeyView.swift` (FAITHFUL/0), `chart/sankey/SankeySeries.swift` (FAITHFUL/0). No CRITICAL findings; nothing to fix. This makes **14 chart types** ported end-to-end. See §46.**
**Phase 14 (GAUGE CHART — COORDLESS: the 13th chart type wired end-to-end in `EChartsSlim`): the gauge chart registers coordless (box/view usage, like pie/funnel/the tree-family — no coordinate system). Registered: `GaugeSeriesModel` + the `"gauge"` view factory (`GaugeView`). `GaugeView` draws the entire gauge directly (no separate axis component) — the axis arc (colored segments), split-lines, ticks, tick labels, the pointer/needle, the anchor, the progress arc, and the title + detail text blocks are all built inside the view. A custom needle shape `PointerPath` (in `PointerPath.swift`) supplies the pointer geometry. Files added: `chart/gauge/GaugeSeries.swift` (`GaugeSeriesModel`), `chart/gauge/GaugeView.swift` (the whole render), `chart/gauge/PointerPath.swift` (the custom pointer/needle path); demo `gauge-basic` + a gauge render test. Clean build `buildGreen = true`; `swift test` **Executed 237 tests, with 58 tests skipped and 0 failures (0 unexpected) in 0.285s** (baseline 236 + 1 new gauge render test). Deferred PORT-TODOs per CONVENTIONS §5: interaction/decoration (emphasis/states, enter/update animation, label-layout niceties) deferred as in prior chart phases. Faithfulness reviews — ALL **FAITHFUL** (0 findings each): `chart/gauge/GaugeView.swift` (reviewed twice, FAITHFUL/0 both), `chart/gauge/PointerPath.swift` (FAITHFUL/0), `chart/gauge/GaugeSeries.swift` (FAITHFUL/0). No CRITICAL findings; nothing to fix. This makes **13 chart types** ported end-to-end. See §45.**
**Phase 13 (POLAR COORDINATE SYSTEM + angle/radius axis component views — the SECOND non-cartesian coord system): the `polar` coordinate system registers end-to-end in `EChartsSlim` — after Phase 12's `radar`, this is the port's SECOND non-cartesian coord system. Registered: the polar coord-system creator (`CoordinateSystemManager.register("polar", ...)` → `polarCreator` injecting the coord sys + associating the angle/radius axes for scale extents) + `PolarModel`/`angleAxis`/`radiusAxis` component models + the two axis component views (`AngleAxisView` + `RadiusAxisView`). `ScatterView` was made polar-aware — `ScatterView.render` now branches by coord type: the existing Cartesian2D path is unchanged, and a NEW Polar branch maps data dims by coord dim name (radius=dim0, angle=dim1 per `polarDimensions`) and places each datum via `Polar.dataToPoint([radiusVal, angleVal])` — the faithful inline of upstream `layout/points.ts`'s generic `map(coordSys.dimensions, data.mapDimension)` + `dataToPoint`. Point computation was factored into a per-index closure so the symbol-build/color/add loop is shared. The e2e render test asserts all 10 polar data points produce finite-positioned symbol `Path`s (name `"item"`), confirming `dataToPoint` works; series must set `coordinateSystem:"polar"` (scatter defaults to cartesian2d). `swift test` **236 executed / 0 failures (0 unexpected) / 58 skipped** (baseline 235 + 1 new polar render test; clean rebuild, 0 warnings, `buildGreen = true`). Demo `polar-basic` + the polar render test added. Deferred PORT-TODOs per CONVENTIONS §5. Faithfulness reviews: `coord/polar/Polar.swift` **FAITHFUL** (0), `coord/polar/polarCreator.swift` **FAITHFUL** (0), `component/axis/AngleAxisView.swift` **MINOR-ISSUES** (2), `component/axis/RadiusAxisView.swift` **MINOR-ISSUES** (1). No CRITICAL findings. **All 3 MINOR findings FIXED post-workflow** (+ a 4th same-class bug the review missed in RadiusAxisView): (a) two `lineCount % lineColors.count` / `% areaColors.count` splitLine/splitArea CRASHES on an explicit empty `color: []` (Swift `%` by zero traps where JS yields NaN → draws nothing) — guarded with `if …isEmpty { return }` in BOTH AngleAxisView and RadiusAxisView; (b) the shared `pathStyleFromDict` style bridge dropped Int-boxed numerics (`lineWidth`/`opacity`/`shadow*`/… `as? Double` → nil) — replaced with a `styleNum` Int→Double coercion across all three copies (Angle/Radius/RadarComponentView). See §44.**
**Phase 12 (RADAR CHART + RADAR COORDINATE SYSTEM — the FIRST non-cartesian coordinate system wired end-to-end): the radar chart registers end-to-end in `EChartsSlim`. This is a milestone — until now every wired coord system was cartesian (`grid`/`cartesian2d`); Phase 12 lands the first polar-style/non-cartesian coord system. The `Radar` coordinate system + its `IndicatorAxis` + `RadarModel` are registered via `CoordinateSystemManager.register("radar", RadarCoordinateSystemCreator())` (a thin creator mirroring `GridCoordinateSystemCreator`, forwarding to `Radar.create`/`Radar.dimensions`), alongside the whole `chart/radar/` vertical — `RadarSeriesModel` + `"radar"` view factory (`RadarView`) + the `radarLayout` stage + the `backwardCompat` preprocessor — and the `component/radar/` component (`RadarModel` + `RadarComponentView` drawing the indicator axes/split-lines/split-areas/name labels). Radar series read each data item's per-indicator points back from the `Radar` coord system (`dataToPoint` over the N indicator axes). `swift test` **235 executed / 0 failures (0 unexpected) / 58 skipped** (baseline 233; +2 = the radar end-to-end render test + a new `RadarCoordTests` coord oracle). Clean build `buildGreen = true`, 0 warnings. Demo `radar-basic` + both tests added. Deferred PORT-TODOs per CONVENTIONS §5: `SymbolDraw` draw-helper infra, emphasis/states + labels + enter/update animation, and roam. Faithfulness reviews: `coord/radar/Radar.swift` CRITICAL-ISSUES (3) + `coord/radar/RadarModel.swift` MINOR-ISSUES (2) — **all 5 findings FIXED post-workflow**: every one was the same recurring Int-vs-Double option-read trap (`get(...) as? Double` returns nil on the Int literals `[String: Any]` defaultOptions use, e.g. `startAngle: 90`), silently dropping the value. The CRITICAL one rotated the whole radar 90° (`startAngle` → 0 rad); fixed with a `radarNumOpt` Int→Double coercion at every option-number read (startAngle/splitNumber/radarIndex/indicator min-max), and locked by `RadarCoordTests` asserting `axis[0].angle == π/2`. `chart/radar/RadarView.swift` + `component/radar/RadarComponentView.swift` **FAITHFUL** (0). See §43.**
**Phase 11 (GRAPH / NETWORK CHART — `data/Graph.ts` port + graph vertical with CIRCULAR + SIMPLE layouts; force layout DEFERRED): the graph (network) chart registers end-to-end in `EChartsSlim`. The faithful `data/Graph.ts` port (`Graph`/`GraphNode`/`GraphEdge`: addNode/addEdge/getEdge(Direction)/eachNode/eachEdge/breadthFirstTraverse/updateNodeAndEdgeState/degree bookkeeping through the real `SeriesData` node+edge data pipeline) lands, alongside the whole `chart/graph/` vertical — `GraphSeriesModel` + `"graph"` view factory (`GraphView`) + two self-gating layout stage handlers (`graphCircularLayoutStageHandler` for `layout:'circular'`, `graphSimpleLayoutStageHandler` for `layout:'none'`) + the `categoryFilter` processor + `categoryVisual`/`edgeVisual` stages — plus `chart/helper/createGraphFromNodeEdge.ts` and `multipleGraphEdgeHelper.ts`. Graph is coordless (box/view usage): `GraphView` reads each node's `[x,y]` and each edge's point list back from whichever layout stage self-selected on the `layout` option. The graph link wiring lands too: `SeriesData.graph` retyped `AnyObject?`→`Graph?` (matches upstream `graph?: Graph`), and `linkSeriesData.linkSingle` grew the `graph`/`edgeData` arms (`structAttr=='graph'` sets `data.graph`; `attr=='data'`→`graph.data`, `attr=='edgeData'`→`graph.edgeData`). `swift test` **233 executed / 0 failures (0 unexpected) / 58 skipped** (baseline 232 executed / 0 failures / 58 skipped; +1 is the new graph render test). Clean-from-scratch `rm -rf .build && swift build` = 0 warnings, Build complete (`buildGreen = true`). Demo `graph-basic` + render test `testGraphRendersNodesAndEdges` (in `HierarchicalChartsRenderTests`) added. Deferred PORT-TODOs per CONVENTIONS §5: force layout (`forceLayout`/`forceHelper`), the SymbolDraw/LineDraw draw-helper infra, and roam/drag/emphasis/labels/effect (effect-line). Faithfulness reviews: `data/Graph.swift` **MINOR-ISSUES** (2 findings), `chart/graph/circularLayoutHelper.swift` **FAITHFUL** (0), `chart/helper/createGraphFromNodeEdge.swift` **FAITHFUL** (0), `chart/graph/GraphView.swift` **FAITHFUL** (0). No CRITICAL findings; build is green. See §42.**
**Phase 10 (TREE-FAMILY CHARTS — sunburst wired end-to-end + treemap + tree verticals): all three hierarchical chart types now register end-to-end in `EChartsSlim`. Sunburst (staged in Phase 9) is now fully wired — `SunburstSeriesModel` + `sunburst` view factory + `sunburstLayoutStageHandler`/`sunburstVisualStageHandler` overall stages run in `render`. NEW verticals `chart/treemap/` (`TreemapSeriesModel`+`TreemapView`+`treemapLayout`+`treemapVisual`+`Breadcrumb`) and `chart/tree/` (`TreeSeriesModel`+`TreeView`+`treeLayout`+`treeVisualStageHandler`+`layoutHelper`/`traversalHelper`) also register end-to-end; all three are coordless/box-usage (hierarchical, like pie) — each View reads its per-node geometry (sunburst sector angle/radius, treemap rect, tree x/y) back from its layout stage. `swift build` GREEN, `swift test` **232 executed / 0 failures / 58 skipped** (baseline 229 + 3 new hierarchical render tests). Demos added: `sunburst-basic`, `treemap-basic`, `tree-basic`. Deferred PORT-TODOs per CONVENTIONS §5: actions (sunburst rollup/highlight, treemap drill/roam/RoamController, tree roam), enter/update/remove animation (static from-scratch rebuild), and emphasis/states (util/states not ported). Four faithfulness reviews: `treemapLayout` FAITHFUL (0), `treeLayout` FAITHFUL (0), `TreeSeries` FAITHFUL (0), `TreemapView` MINOR-ISSUES (1). No CRITICAL findings; build is green. See §41.**
**Phase 9 (TREE DATA STRUCTURE + SUNBURST render layer — STAGED, not yet slim-wired): the faithful `data/Tree.ts` port (`Tree`/`TreeNode`: buildHierarchy/updateDepthAndHeight/preorder+postorder `eachNode` with subtree-suppress/getNodeById/contains/getAncestors/isAncestorOf/getValue through the real `SeriesData` data pipeline) plus its `data/helper/linkSeriesData.ts` port land, alongside the whole `chart/sunburst/` render layer (`SunburstSeriesModel`+`SunburstView`+`SunburstPiece`+`sunburstLayout`+`sunburstVisual`+`sunburstInstall`) and `chart/helper/sectorHelper`. `swift build` GREEN (0 warnings), `swift test` 229 executed / 0 failures / 58 skipped (+6 new `TreeUnitTests`, no regression). Closeout fixed the render-layer so it compiles clean: retyped the pre-Tree `SeriesData.tree` placeholder `AnyObject?`→`Tree?` (matches upstream `tree?: Tree`), fixed the IUO-bound-to-`let` Optional-inference gotcha at every `.root`/`hostTree.data` binding, and matched the typed `eachNode` callback form. Two faithfulness reviews (Tree.swift, sunburstLayout.swift) both `MINOR-ISSUES`, geometry/algorithms byte-faithful; BOTH findings fixed: `TreeNode.getValue` now uses JS-falsy `dimension || 'value'` semantics (not nil-only `??`), and the custom-comparator `sort` branch is now stable (original-index tie-break) to match ES2019 `Array.prototype.sort`. DEFERRED (next step): slim registration + end-to-end render (sunburst is coordless like pie — needs `SunburstSeriesModel` + view factory + layout/visual stage registration in `EChartsSlim` and a gallery demo); `sunburstAction` (rollup/highlight), emphasis/states, and enter/update animation are PORT-TODO. The two `install.swift` files (boxplot + sunburst) were renamed `boxplotInstall.swift`/`sunburstInstall.swift` — SwiftPM flattens object-file basenames, so two `install.swift` in one target collide (`multiple producers`); this is the scalable convention for future per-chart install files. See §40.**
**Phase 8 (NEW CHART TYPES — funnel + candlestick + boxplot): all three chart types now register end-to-end in `EChartsSlim` (`FunnelSeriesModel`+`funnelLayout`/`funnelLayoutStageHandler`+`FunnelView`; `CandlestickSeriesModel`+`candlestickLayout`+`candlestickVisual`+`CandlestickView`+`'k'→'candlestick'` preprocessor; `BoxplotSeriesModel`+`boxplotLayout`+`boxplotVisual`+`BoxplotView`), each wired into the layout + visual stages with its axis-handler registration; nothing blocked. New custom shapes `NormalBoxPath`/`BoxPath` (candlestick/boxplot box+whisker geometry) landed. Independent post-workflow verification rendered all three vs echarts.js (funnel trapezoids, candlestick bull/bear K-line, boxplot box+median+whiskers — all faithful), added `funnel-basic`/`candlestick-basic`/`boxplot-basic` gallery demos + `NewChartsRenderTests`, and fixed a real ZRenderKit crash: `Element.getOutsideStroke` force-unwrapped `self.__zr!` (nil in the headless render path — funnel outside-labels hit it) → now guarded like its sibling `getOutsideFill`. `swift build` GREEN (0 warnings), `swift test` 223 executed / 0 failures / 58 skipped. Deferred PORT-TODOs: large/progressive draw path (LargeBoxPath/createLarge no-op), emphasis/states + enter/update animation + labels, the `boxplotTransform` dataset transform, and the diff-based enter/update/remove (replaced by static from-scratch rebuild, same as Line/Pie/Funnel views). Three faithfulness reviews: funnel `FAITHFUL_WITH_MINOR_DIVERGENCES` (percent-string itemStyle width/height dropped; unstable sort tie-break; custom-comparator sort no-op), candlestick `FAITHFUL` (resolveNormalBoxClipping stubbed NOT_CLIPPED + large-mode no-op are the notable deferrals), boxplot `FAITHFUL` (0 findings). See §39.**
**Phase 7 (STATIC COMPONENT LAYER): `title`, `graphic`, and `legend` (model) now register in `EChartsSlim` (`TitleModel`+`TitleView`, `GraphicComponentModel`+`GraphicComponentView`+`graphicOptionPreprocessor`, `LegendModel`+`registerSubTypeDefaulter('legend','plain')`+`LegendView`); the three marker components (`markPoint`/`markLine`/`markArea`) are PORTED-but-BLOCKED (files compile; registration + view factories + preprocessors left unwired) on a stubbed coord/axis-resolution + SymbolDraw/LineDraw + util/states+graphic dep stack. All interaction (legend select/scroll, marker drag, actions, emphasis/animation) is deferred PORT-TODO per CONVENTIONS §5. `swift build` GREEN (0 warnings), `swift test` 220 executed / 0 failures / 58 skipped. Three faithfulness reviews all `minor-issues` (notable: legend per-series glyph stubbed → default icon; markerHelper statistic/valueAxis branch dead until coord protocol witnesses land). See §38.**
**Phase 6d (SYMBOLS + SCATTER + PIE verticals): faithful `util/symbol` (the symbol-path factory + `createSymbol`), `LineView` now honors `showSymbol`, plus two minimal new chart verticals — `chart/scatter/{ScatterSeries,ScatterView}` (points via `coord.dataToPoint` + `createSymbol`) and a coordless `chart/pie/{PieSeries,PieView,pieLayout}` (per-item angle/radius geometry through a `pieLayout(ecModel, api)` render hook + `createSeriesDataSimply`/`util/layout` box). Registered in `EChartsSlim` (`ScatterSeriesModel`/`PieSeriesModel` + `scatter`/`pie` view factories + pie's `registerLayOutOnCoordSysUsage`). Post-workflow verification fixed the visual-task ORDER (`dataColorPaletteTask` must run LAST) and a `getColorFromPalette` overload trap so pie's per-slice `colorBy:'data'` palette works; added `Scatter`/`PieChartRenderTests`. `swift build` GREEN (0 warnings), `swift test` 220 executed / 0 failures / 58 skipped. Label/emphasis/`SymbolDraw` are documented PORT-TODOs. See §37.**
**Phase 6c (REAL DATA SOURCE PIPELINE — the faithful `data/helper/sourceManager.ts` port replaces the Series stub `SourceManager`): COMPLETE — `swift build` GREEN (0 warnings), `swift test` 216 executed / 0 failures / 58 skipped (no regression).** The reachable series-inline-data path (no dataset) is fully live and verified: no upstream → `data = seriesModel.get("data")`, `SOURCE_FORMAT_ORIGINAL`, `createSource` → `DataStore` via `DefaultDataProvider`; `getSharedDataStore` now ships on the real class. Dataset/transform arms are documented PORT-TODOs (unreachable this phase). Faithfulness review: faithful, 0 findings. See §36.
**Phase 6b (RENDERING VERTICAL — a REAL bar chart end-to-end: slim `EChartsSlim` driver + `view/` bases + `visual/style` + `layout/barGrid` + `chart/bar/{BaseBarSeries,BarSeries,BarView}` + `component/{grid/GridView,axis/CartesianAxisView+AxisBuilder}`): COMPLETE — `swift build` GREEN (0 warnings), `swift test` 215 executed / 0 failures / 58 skipped (was 212; +3 real 6b tests, no regression). A cartesian bar `option` renders four bar `Rect`s through `ZRenderKit` (`BarChartRenderTests`), also exercising `NativePainter.renderToImage`.** See §35. Closeout fixed one real defect the killed workflow left: `SeriesModel.getBaseAxis()` returned `nil` via an `Any?`-return conversion, so bar x/width were NaN (§35b).
**Phase 6b.1 (AXIS RENDERING): the cartesian axes now draw too — axisLine, split(grid)Lines, ticks, and tick LABELS (x: A/B/C/D, y: 0–40).** The native `EChartsDemoGallery` render now matches echarts.js essentially 1:1. Four defects fixed: (1) `Grid.createAxisBiulders` + `createOrUpdateAxesView` were no-op stubs → un-stubbed to `new AxisBuilder → build()` per shown axis (they call the already-ported `cartesianAxisHelper.create/updateCartesianAxisViewCommonPartBuilder`); (2) the slim stand-in axis models never merged the per-type `axisDefault` (deferred `mergeDefaultAndTheme`) → `show` was nil → `shouldAxisShow` false → axes hidden; now `EChartsSlim` merges `axisDefault.option[type]` under the option; (3) a STALE `getScaleExtentForTickUnsafe(OrdinalScale)` fatalError placeholder in `scale/helper.swift` shadowed the real `scaleMapper` impl (overload-resolution trap) → removed; (4) `NativePainter.flattenDisplayList` skipped the per-element `update()` that `Storage` runs, so `ZRText` never built its `TSpan` children and all text dropped → now mirrors `Storage` (`beforeUpdate/update/afterUpdate`). Added `Sources/EChartsDemoGallery` (native vs echarts.js side-by-side) + `scripts/build-echarts-gallery.sh`.
**Phase 6b.2 (LINE vertical): a cartesian `series.line` now renders natively too** — minimal `chart/line/{LineSeries,LineView}` (a `Polyline` through `coord.dataToPoint` per datum, palette stroke; symbols/areaStyle/step/stack are documented PORT-TODOs), registered in `EChartsSlim`. `line-basic` in the gallery now renders on BOTH panes and matches echarts.js (modulo point symbols). Key gotcha: `LineSeriesModel` MUST override `static defaultOption` with `coordinateSystem:'cartesian2d'` — `decideCoordSysUsageKind` reads `getShallow("coordinateSystem")`, so without it the coord system is never injected and `LineView` renders nothing. `LineChartRenderTests` locks it in (216 tests / 0 failures).
**Phase 6a (COORDINATE SYSTEM + PIPELINE + COMPONENT-INSTANTIATION: `coord/cartesian` Grid/Cartesian2D/Axis2D/AxisModel + axis-helper cluster + the REAL `scaleRawExtentInfo`; `core/` Scheduler/task/CoordinateSystemManager/ExtensionAPI; `GlobalModel` component/series instantiation wired so `getComponent`/`eachSeries` return REAL `GridModel`/`CartesianAxisModel`/bar `SeriesModel`): COMPLETE — `swift build` GREEN, `swift test` 212 executed / 155 passed / 0 failures / 57 skipped (was 208; +4 new coord tests = 2 pass + 2 skip; no regression).** See §§31–34. **The dynamic-option→component pipeline left inert in §29 is now live; `dataToPoint` is exercised by a pixel oracle. The rendering vertical (views + slim orchestrator) is Phase 6b (§34).**
**Phase 4 (INTERACTION-COMPLETE → zrender DONE: Handler hit-test/dispatch/bubble + core/event normalization + GestureMgr pinch + Draggable + Element Eventful wiring + the hand-written UIKit/AppKit HandlerProxy bridge & ZRenderView host): COMPLETE — clean from-scratch `swift build` green (all 88 units, 0 errors), `swift test` 65 executed / 0 failures / 14 skipped (the new InteractionSmokeTests).** See §§18–22. **zrender is now COMPLETE — rendering + animation + interaction all ported; canvas/svg/dom are intentionally replaced by NativePainter. The port now advances to the ECharts layer (§22).**
**Phase 3 (LOGIC-COMPLETE: real Animator/Animation/Clip/easing + CADisplayLink host loop + path tools path/transformPath/dividePath/morphPath/convertPath + tool/color completion + Element/ZRender animation wiring): COMPLETE — `swift build` green, 61 tests / 0 failures / 16 skipped.** See §§13–17. **zrender is now logic-complete (rendering + animation + path tools); the only remaining zrender work is Phase 4 = interaction (Handler/event/GestureMgr → UIKit).**
**Phase 2 (Text/TSpan/Image + contain/* hit-testing + 10 remaining shapes + gradient/pattern/text/image paint + Storage display list + ZRender host facade): COMPLETE — `swift build --build-tests` green, 50 tests / 0 failures / 13 skipped.** See §§7–11.
**Phase 1 (scene graph + shape layer + first real NativePainter): COMPLETE — build green, all goldens pass.**
**Phase 0 (Core scaffold + math/geometry foundation): COMPLETE (its lone blocker is now resolved).**

This document records what landed per phase, the per-file status, the deduped fix-up
backlog (sorted blockers/severity-first), the next-phase plan, and the standing upstream-sync
rule. It is the single source of truth for "where the port is" — read it before starting Phase 3.
The Phase 2 plan (§5) is preserved verbatim as the historical brief; its execution results are in §§7–11.
Phase 0 history is preserved verbatim near the bottom (§§P0-1…P0-3); do not delete it.

Project root: `/Volumes/EXT-Storage/Developer/iOS-Chart`
Rulebook: `CONVENTIONS.md` (faithful, line-by-line, diffable-against-upstream port).

---

## 1. What landed in Phase 1 — checklist

**Goal (met):** translate the scene-graph + shape layer so a *hand-built* `Group`/`Path` tree
renders on iOS/macOS through a real `CALayerPainter`, validated against the golden fixtures with
**true geometry parity** (Swift `Shape.buildPath` output, not just replayed PathProxy `d`-strings).

### Scene graph & display types (`Sources/ZRenderKit/`)
- [x] `Element.swift` ← `zrender/src/Element.ts` — keystone scene-graph base (`final class`).
      Transform/clip/parent surface ported; **states, emphasis/blur/select, animation, ZRText
      inner-text, and the Eventful mixin are faithfully scaffolded but stubbed** (`// PORT-TODO`,
      Phase 2/3). Forward-declares placeholders for `ZRenderType`, `ZRText`, `Polyline`.
- [x] `Graphic/Displayable.swift` ← `graphic/Displayable.ts` — `Displayable extends Element`;
      the paintable surface (style bag, z/z2/zlevel, invisible, getBoundingRect/contain hooks).
      `STYLE_MAGIC_KEY` dynamic stamp replaced by a typed flag (`// PORT-TODO`).
- [x] `Graphic/Group.swift` ← `graphic/Group.ts` — child list, add/remove/eachChild/traverse,
      `getBoundingRect` over children.
- [x] `Graphic/Path.swift` ← `graphic/Path.ts` — where shapes meet `PathProxy`: owns a `PathProxy`,
      `getUpdatedPathProxy`/`buildPath`/`getBoundingRect` (routes through `bbox`), style/shape
      setters. `contain`/`containStroke` hit-test routes to `contain/path` = **Phase 2 stub**.

### 6 shapes (`Sources/ZRenderKit/Graphic/Shape/`)
- [x] `Rect.swift` ← `graphic/shape/Rect.ts` (RectRadius union `number | number[]`, roundRect helper)
- [x] `Circle.swift` ← `graphic/shape/Circle.ts`
- [x] `Sector.swift` ← `graphic/shape/Sector.ts` (cornerRadius via roundSector helper)
- [x] `Arc.swift` ← `graphic/shape/Arc.ts`
- [x] `BezierCurve.swift` ← `graphic/shape/BezierCurve.ts` (quadratic/cubic branch on cp2)
- [x] `Polygon.swift` ← `graphic/shape/Polygon.ts` (poly/smoothBezier helpers)

### Shape `buildPath` helpers (`Sources/ZRenderKit/Graphic/Helper/`)
- [x] `poly.swift`, `roundRect.swift`, `roundSector.swift`, `smoothBezier.swift`, `subPixelOptimize.swift`
      ← `graphic/helper/*.ts` (all emit into `PathProxy`).

### Foundations pulled in on demand
- [x] `Core/Eventful.swift` ← `core/Eventful.ts` — on/off/trigger event bus (closure-identity dedup
      and `zrEventfulCallAtLast` flag are `// PORT-TODO`; not yet wired into Element).
- [x] `Animation/Animator.swift` ← `animation/Animator.ts` — **type surface only**; every body is a
      `// PORT-TODO` (real tween/Clip/Track = Phase 3). Element/Path reference the type, do not drive it.
- [x] `Animation/easing.swift` ← `animation/easing.ts` — table stubbed (Phase 3).
- [x] `Tool/color.swift` ← `tool/color.ts` — parse/rgba/stringify/fastLerp ported; `lerp`/`modifyHSL`/
      `liftColor` need `isFunction`/`GradientObject`/`isString` = `// PORT-TODO`.
- [x] `Graphic/Gradient.swift`, `LinearGradient.swift`, `RadialGradient.swift`, `Pattern.swift`
      ← `graphic/{Gradient,LinearGradient,RadialGradient,Pattern}.ts` — **data types only**; the
      canvas/image backend fields (`__canvasGradient`, `ImageLike`, `SVGVNode`) are `// PORT-TODO`.
- [x] `Graphic/constants.swift` ← `graphic/constants.ts`; `config.swift` ← `config.ts`
      (browser-only `devicePixelRatio` is `// PORT-TODO`).
- [x] `Core/util.swift` — extended on demand for the above (per Phase-0 §P0-3.15).

### First real NativePainter (`Sources/NativePainter/`, hand-written, not a translation)
- [x] `CALayerPainter.swift` — `Painter` over a root `CALayer`; `renderToImage(group:size:dpr:)`
      walks the `Group`, paints each `Path` displayable. **Text/Image/TSpan = `// PORT-TODO` (Phase 2).**
- [x] `CGRenderer.swift` — `Renderer`: fillPath/strokePath/transform/opacity/shadow/setClip via
      `CGContext`. **Gradient & pattern paint resolve to `nil` = `// PORT-TODO`; `drawText` = Phase 2;
      even-odd fill rule never selected; line-cap/join keyword presets unresolved.**
- [x] `CGPathRebuilder.swift` — `PathRebuilder` consumer that converts `PathProxy.rebuildPath`
      commands into a `CGMutablePath` (M/L/C/Q/A/Z/R).
- [x] `Renderer.swift` — seam protocols (carried from Phase 0, now exercised).

### Golden tests — true geometry parity (`Tests/ZRenderKitTests/`)
- [x] `GoldenTests.swift` — the old compiled-out `#if PORT_TODO_GOLDEN` stub is now a **real
      data-driven test**: `testSwiftBuildPathMatchesOracle` instantiates each ported `…Shape`,
      sets it on the ported `Path` subclass, builds via `path.getUpdatedPathProxy(false)`, replays
      through `GoldenPathRebuilder`, and asserts the canonical `d` == fixture `rebuiltD` byte-for-byte
      (6 fixtures, each its own diff-carrying assertion).
- [x] `CALayerPainterSmokeTests` (guarded `#if canImport(QuartzCore) && canImport(CoreGraphics)`) —
      builds `Group{Rect,Circle,Sector}` and asserts `renderToImage` returns a non-nil 200×150 CGImage.
- [x] `Package.swift` — `NativePainter` added to the `ZRenderKitTests` test target deps. No other
      Package change needed (default `Sources/<target>/**` globbing picked up all new subdirectories).

---

## 2. Phase 1 — per-file status & review verdict

| File | Source `.ts` | Status | Verdict | Blocking note |
|---|---|---|---|---|
| `Element.swift` | `Element.ts` | partial (render surface) | minor-issues (1) | states/animation/Eventful/ZRText stubbed `// PORT-TODO` |
| `Graphic/Displayable.swift` | `graphic/Displayable.ts` | partial | **major-issues (1)** | `STYLE_MAGIC_KEY` dynamic-stamp divergence + deferred state/style surface |
| `Graphic/Group.swift` | `graphic/Group.ts` | complete | minor-issues (1) | `children()` returns a value-type COPY, not a live ref; cb-`this` binding |
| `Graphic/Path.swift` | `graphic/Path.ts` | partial | minor-issues (1) | `contain`/`containStroke` + decal + per-key setShape stubbed |
| `Graphic/Shape/Rect.swift` | `graphic/shape/Rect.ts` | complete | minor-issues (1) | RectRadius union modeling |
| `Graphic/Shape/Circle.swift` | `graphic/shape/Circle.ts` | complete | faithful | — |
| `Graphic/Shape/Sector.swift` | `graphic/shape/Sector.ts` | complete | faithful | — |
| `Graphic/Shape/Arc.swift` | `graphic/shape/Arc.ts` | complete | faithful | — |
| `Graphic/Shape/BezierCurve.swift` | `graphic/shape/BezierCurve.ts` | complete | faithful | — |
| `Graphic/Shape/Polygon.swift` | `graphic/shape/Polygon.ts` | complete | faithful | — |
| `Graphic/Helper/{poly,roundRect,roundSector,smoothBezier,subPixelOptimize}.swift` | `graphic/helper/*.ts` | complete | (folded into shape review) | minor `// PORT-TODO`s (structural-type→protocol, `Math.round` half-up) |
| `Core/Eventful.swift` | `core/Eventful.ts` | complete | (foundation sweep) | closure-identity dedup + `zrEventfulCallAtLast` stubbed; not wired to Element |
| `Animation/Animator.swift` | `animation/Animator.ts` | **type-surface stub** | (foundation sweep) | every body `// PORT-TODO` (Phase 3) |
| `Animation/easing.swift` | `animation/easing.ts` | stub | (foundation sweep) | easing table deferred (Phase 3) |
| `Tool/color.swift` | `tool/color.ts` | partial | (foundation sweep) | `lerp`/`modifyHSL`/`liftColor` deferred (need util guards + Gradient) |
| `Graphic/{Gradient,LinearGradient,RadialGradient,Pattern}.swift` | `graphic/*.ts` | data-types only | (foundation sweep) | backend image/canvas/svg fields `// PORT-TODO` |
| `Graphic/constants.swift`, `config.swift` | `graphic/constants.ts`, `config.ts` | complete | (foundation sweep) | `devicePixelRatio` browser-only `// PORT-TODO` |
| `NativePainter/CALayerPainter.swift` | (hand-written, §9) | complete (Path only) | n/a (not a translation) | Text/Image/TSpan unpainted |
| `NativePainter/CGRenderer.swift` | (hand-written, §9) | complete (fill/stroke) | n/a | gradient/pattern/text paint = `// PORT-TODO` |
| `NativePainter/CGPathRebuilder.swift` | (hand-written, §9) | complete | n/a | — |

Roll-up (ported `.ts` mirrors with a review verdict): **5 faithful, 5 minor-issues, 1 major-issues.**
The Animation/Tool/Gradient/Pattern foundations were landed via the on-demand foundation sweep and
are intentionally type-surface/partial (each gap is `// PORT-TODO`-marked).

---

## 3. Build & test status — Phase 1

- **Build: GREEN.** A clean build (`rm -rf .build && swift build`) compiled all four targets
  (`ZRenderKit`, `NativePainter`, `EChartsKit`, `ZRenderKitTests`) on the first attempt, with **no
  fixes required**. SwiftPM default `Sources/<target>/**` globbing picked up the new `Graphic`,
  `Graphic/Shape`, `Graphic/Helper`, `Animation`, and `Tool` subdirectories automatically.
- **`swift test`: GREEN.** `Executed 5 tests, 0 failures` (≈1.12 s build, 0.010 s run). The suite-level
  "5 tests" includes `testSwiftBuildPathMatchesOracle` (6 per-fixture parity assertions in one method),
  the painter smoke test, and the still-green Phase-0 `testRebuiltDMatchesOracle` + `testAllFixturesLoad`.
- **True geometry parity: 6/6 PASS, 0 FAIL** —

  | Fixture | Swift `Shape.buildPath` `d` == oracle `rebuiltD` |
  |---|---|
  | `rect` | PASS |
  | `circle` | PASS |
  | `sector` | PASS |
  | `arc` | PASS |
  | `bezier-curve` | PASS |
  | `polygon` | PASS |

  No code under `Sources/ZRenderKit` was modified to achieve parity — the ported shapes produced exact
  byte-for-byte output. `CALayerPainterSmokeTests.testRenderToImageProducesImage` also passes.
- **Phase-0 blocker RESOLVED:** `bbox.fromCubic`/`cubicExtrema` (old §P0-3 blocker #1) compiles cleanly;
  `Path.getBoundingRect` routes through it and `swift test` compiles end-to-end.

### Second oracle: ported zrender unit tests (behavioral)

Per the standing rule, the matching upstream Jest specs (`upstream/zrender/test/ut/spec/`) for
already-translated modules were ported to XCTest under `Tests/ZRenderKitTests/unit/`
(`Matrix`, `LRU`, `Util`, `Platform`, `Path`, `Group`). These complement the golden geometry
fixtures with unit-level behavior (matrix pivot-rotate, Path/Displayable default style values,
LRU eviction, Group iteration order, platform measureText).

- **`swift test`: 44 tests, 0 failures, 12 skipped.** No `Sources/` changes were needed — every
  non-skipped assertion matched upstream.
- **Skips** preserve intent for not-yet-ported surfaces: Path `setStyle`/`setShape` partial-merge
  and the states machinery (Phase-2 stubs), and JS-only semantics (`clone` of Date/TypedArray/class,
  callback-`this` binding) that don't map to Swift value types.
- **One real faithfulness gap found** (see §4): `util.merge` drops upstream's null/undefined guard.
- Specs deferred until their modules land: `tool/color` (color partial → Phase 3), `contain/Sector`
  + `graphic/{Image,Text}` (Phase 2), `animation/ElementAnimation` (Phase 3).

---

## 4. Phase 1 — new open issues & PORT-TODO backlog (deduped, severity-sorted)

### Major — sign-off needed before it spreads
1. **`Displayable` `STYLE_MAGIC_KEY` divergence (major-issues review).** Upstream stamps style objects
   with a random dynamic key (`'__zr_style_' + round(random*10)`) to detect "is this a style bag".
   The port replaces it with a static typed flag. Audit every place that consumes the magic key
   (style merging, `useStyle`, state style application in Phase 2) before relying on it.

### Correctness / fidelity — review-flagged, fix opportunistically
2. **`Group.children()` returns a value-type COPY, not a live reference** (`Group.swift:55`). Upstream
   `_children` is a live array; mutating the returned array upstream mutates the group. Callers that
   expect to mutate children through the returned handle get a silent no-op. Audit Phase-2 callers.
3. **Group `eachChild`/`traverse` callback `this`-binding** is dropped (Swift closures capture). The
   `context` argument is passed but not bound as `this`; and `cb` `boolean | void` is modeled as `-> Bool`.
4. **`color.swift` partials:** `lerp` / `mapToColor` / `modifyHSL` / `liftColor` are unported (need
   `util.isFunction`/`isString`, `GradientObject`, and TS function-overload modeling). Number→String
   fidelity (`toFixed`/exponential) is a narrow subset. Any gradient color stop or HSL tween needs these.
5. **`subPixelOptimize` `Math.round` half-up** vs Swift `.rounded()` (banker's). Replicate `floor(x+0.5)`
   if pixel-snapping parity matters.
6. **`Element` `setTextConfig`/`updateInnerText` no-op** — ZRText inner-text layout is deferred; any
   label-bearing element renders without its text in Phase 1.
7. **`util.merge` drops upstream's null/undefined guard** (found by the ported `util` unit test).
   Upstream begins `if (!isObject(source) || !isObject(target)) return overwrite ? clone(source) : target;`
   so `merge(null,x)→null`, `merge(x,undefined)→x`, etc. The Swift signature
   `merge(_ target: inout [String:Any], _ source: [String:Any], _ overwrite: Bool)` (`util.swift:104`) is
   non-optional on both sides and omits the guard — the null/undefined cases are inexpressible. Inherent to
   the chosen signature; low risk under current geometry-layer usage, but a genuine divergence. Revisit when
   the option-merge layer (echarts `model/`) needs faithful deep-merge of absent/`null` config.

### Stubbed surfaces — whole features deferred (each is `// PORT-TODO`)
7. **Text / TSpan / Image** not ported at all. `graphic/Text.ts`, `graphic/TSpan.ts`, `graphic/Image.ts`,
   `Element.updateInnerText`, and `CGRenderer.drawText` are stubs. → Phase 2.
8. **Hit-testing (`contain/*`)** not ported. `Path.contain`/`containStroke` and `Displayable.contain`
   route to `contain/path`/`contain/text` which do not exist yet. → Phase 2.
9. **States / emphasis / blur / select / hover-layer** machinery stubbed across `Element` and `Path`
   (`saveCurrentToNormalState`, `useState`, `setState`, `ensureState`, `_mergeStates`). → Phase 2.
10. **Animation** is a type-surface stub only: `Animator` bodies, `easing` table, `animation/Animation.ts`,
    `animation/Clip.ts`, `animation/Track`, and every `Element`/`Path` `animateTo`/`animate`/`stopAnimation`
    path is `// PORT-TODO`. → Phase 3.
11. **Gradient / pattern rendering** in the painter resolves to `nil` paint (only solid `fill`/`stroke`
    paint). `CGRenderer` gradient/pattern/even-odd/line-keyword resolution + the `Gradient`/`Pattern`
    backend image fields are deferred. → Phase 2.
12. **Remaining shapes:** `Polyline.ts`, `Line.ts`, `Ring.ts`, `Ellipse.ts`, `Heart`, `Droplet`, `Rose`,
    `Trochoid`, `Isogon`, `Star`, etc. not yet ported. `Polyline` is a forward-declared placeholder used
    by `Element`. → Phase 2.
13. **`Eventful` not wired into `Element`** (the mixin forwarding is a `// PORT-TODO`); closure-identity
    dedup + `zrEventfulCallAtLast` ordering unmodeled. Needed once the `Handler`/event plumbing lands.
14. **`Path` per-key `setShape(key, value)`** and the dynamic dict-merge of a partial shape into a typed
    `PathShape` struct require reflection / subclass support — only whole-shape `setShape` works today.
15. **`config.devicePixelRatio`** is browser-only; wire to screen scale when the painter gains a real host.

> Carry-over from Phase 0 (§P0-3): the `Swift.min/max` NaN-non-propagation policy (item 2), `|| 0`-vs-`?? 0`
> NaN handling (item 3), `env`/`WeakMap`/`LRU`/`platform.measureText` notes — all still open, all still
> low-risk under "finite-coords-only" usage; revisit when wiring real input/measurement.

---

## 5. Phase 2 plan (HISTORICAL — executed; results in §§7–11) — Text/Image + hit-testing + remaining shapes + gradient/pattern paint + host facade

**Goal:** a label-bearing, hit-testable, gradient-capable render path; a `Storage` display list; and a
minimal `ZRender` host facade that ties `Storage` + `Painter` + `Element` tree together — so a chart's
graphic primitives (not yet the chart layer) round-trip from a hand-built tree to pixels with text.

### 5a. Text / TSpan / Image (`zrender/src/graphic/`)
| Upstream file | Swift target | Already-ported deps |
|---|---|---|
| `graphic/Text.ts` (ZRText) | `Graphic/Text.swift` | `Displayable`, `Element` (inner-text hooks already stubbed), `platform.measureText`, `BoundingRect` |
| `graphic/TSpan.ts` | `Graphic/TSpan.swift` | `Displayable`, `platform` |
| `graphic/Image.ts` | `Graphic/Image.swift` | `Displayable`, `platform` (ImageLike seam — needs a native image type) |
| `core/text.ts` (`parsePercent`, font parse, line layout) | `Core/text.swift` | `platform`, `BoundingRect`, `util`, `LRU` |
| then: `CGRenderer.drawText` + `CALayerPainter` Text/Image painting | NativePainter | Core Text run from the resolved `TextStyle`; image draw from a native CGImage |

### 5b. Hit-testing (`zrender/src/contain/`)
| Upstream file | Swift target | Already-ported deps |
|---|---|---|
| `contain/path.ts` | `Contain/path.swift` | `PathProxy`, `curve`, `windingLine` |
| `contain/line.ts`, `contain/quadratic.ts`, `contain/cubic.ts`, `contain/arc.ts`, `contain/util.ts` | `Contain/*.swift` | `curve`, `vector` |
| `contain/text.ts` | `Contain/text.swift` | `Core/text.swift` (5a), `BoundingRect` |
| then: wire `Path.contain`/`containStroke` + `Displayable.contain` (stubs today) to the above. |

### 5c. Remaining shapes (`zrender/src/graphic/shape/`)
`Polyline.ts` (unblocks the `Element` placeholder), `Line.ts`, `Ring.ts`, `Ellipse.ts`, then the rest.
**All depend on `PathProxy` + `Path` (Phase 1) + the helpers in `Graphic/Helper/`.**

### 5d. Gradient / pattern paint in `CALayerPainter`/`CGRenderer`
Resolve `LinearGradientObject`/`RadialGradientObject` → `CGGradient` (with `colorStops`), and
`PatternObject` → a tiled `CGImage` paint. Select even-odd vs nonzero fill rule; resolve line-cap/join
keyword presets. **Deps already ported:** `Graphic/{Gradient,LinearGradient,RadialGradient,Pattern}.swift`
(data types), `Tool/color.swift` (after 5a-adjacent `color` completions for stops).

### 5e. `Storage` + display list (`zrender/src/Storage.ts`)
| Upstream file | Swift target | Already-ported deps |
|---|---|---|
| `Storage.ts` | `Storage.swift` | `Element`, `Group`, `Displayable`, `util` (the z/z2/zlevel sort) |

Builds the flattened, sorted display list the painter consumes (replacing the current ad-hoc Group walk
in `CALayerPainter`).

### 5f. `ZRender` host facade (`zrender/src/zrender.ts`)
| Upstream file | Swift target | Already-ported deps |
|---|---|---|
| `zrender.ts` (`ZRender` / `init` / `add`/`remove`/`refresh`) | `ZRender.swift` | `Storage` (5e), `NativePainter.Painter`, `Element`, `Animation` (stub surface) |

Replaces the `ZRenderType` forward-declaration placeholder in `Element.swift` with the real type
(`__zr`, `addAnimator`/`removeAnimator` hooks — animation bodies stay Phase-3 stubs). `Eventful` →
`Handler` event plumbing can be wired here.

**Sequencing note:** 5a (Text/`core/text`) unblocks 5b's `contain/text` and the `Element` inner-text
stub; 5e (`Storage`) precedes 5f (`ZRender`). Animation stays a Phase-3 deferral throughout.

---

## 7. What landed in Phase 2 — checklist

**Goal (met):** a label-bearing, hit-testable, gradient/pattern-capable render path; a flattened/sorted
`Storage` display list; and a minimal `ZRender` host facade tying `Storage` + `Painter` + `Element`
tree together. A hand-built `Group` tree of paths/text/images now round-trips to pixels, with the
four ECharts-expressible new shapes (ellipse/ring/line/polyline) validated byte-for-byte against the
ECharts oracle and the six decorative zrender-only shapes smoke-tested NaN-free.

### Text / TSpan / Image (`Sources/ZRenderKit/Graphic/`)
- [x] `Graphic/Text.swift` ← `graphic/Text.ts` (ZRText) — rich-text layout host, background/border
      rendering, per-token placement, `_updatePlainTexts`/`_placeToken`/`_renderBackground`. **Empty-string
      color truthiness + `parseFontSize` numeric-coercion + `'fill'/'stroke' in style` existence-vs-`!=nil`
      diverge on degenerate/explicit-null inputs (see §9); states-driven rich-style merge waits on Phase-3
      `useState`.**
- [x] `Graphic/TSpan.swift` ← `graphic/TSpan.ts` — single positioned text run (the paint unit).
- [x] `Graphic/Image.swift` ← `graphic/Image.ts` — `ZRImage`; `_getSize` width/height/aspect math faithful
      (verified by ported `ImageUnitTests`). Native image decode = file path / `data:` URI only.
- [x] `Graphic/CompoundPath.swift` ← `graphic/CompoundPath.ts`, `Graphic/IncrementalDisplayable.swift`
      ← `graphic/IncrementalDisplayable.ts` — pulled in as composite displayables.

### Hit-testing (`Sources/ZRenderKit/Contain/`)
- [x] `Contain/ContainPath.swift` ← `contain/path.ts` (winding-number path containment + stroke)
- [x] `Contain/ContainLine.swift`, `Contain/ContainPolygon.swift`, `Contain/ContainArc.swift`,
      `Contain/cubic.swift`, `Contain/quadratic.swift`, `Contain/windingLine.swift`,
      `Contain/containUtil.swift` ← matching `contain/*.ts`
- [x] `Contain/ContainText.swift` ← `contain/text.ts`
- [x] `Path.contain`/`containStroke` (the Phase-1 stub) now route through `ContainPath`; verified by the
      ported `ContainSectorUnitTests`.

> **Filesystem note:** the lowercase upstream basenames `contain/{arc,line,path,polygon,text}.ts` were
> renamed to `Contain/Contain{Arc,Line,Path,Polygon,Text}.swift` to avoid SwiftPM object-file name
> collisions with `Graphic/Shape/{Arc,Line,Polygon}.swift` and `Graphic/{Path,Text}.swift` on the
> case-insensitive macOS volume (see §8). Upstream mapping is preserved in each header; re-sync stays
> mechanical. **Future risk:** any new `Contain/<x>.swift` whose basename case-collides with a Graphic
> file (e.g. `circle`, `rect`) will hit the same collision — apply the same `Contain`-prefix rename.

### 10 remaining shapes (`Sources/ZRenderKit/Graphic/Shape/`)
- [x] `Ellipse.swift`, `Ring.swift`, `Line.swift`, `Polyline.swift` (the `Element` placeholder is now
      a real type), `Heart.swift`, `Droplet.swift`, `Isogon.swift`, `Rose.swift`, `Star.swift`,
      `Trochoid.swift` ← matching `graphic/shape/*.ts`.

### Gradient / pattern / text / image paint (`Sources/NativePainter/`, hand-written)
- [x] `CGRenderer` gradient fill+stroke (`makeCGGradient` from `colorStops`, linear via
      `drawLinearGradient`, radial via `drawRadialGradient`, clip-to-path), pattern fill+stroke (tiled
      `CGImage`), fill-rule selection, `drawText` (Core Text `CTLine`, align/baseline), `drawImage`
      (decoded `CGImage`), `loadCGImage` (file path / base64 `data:` URI via ImageIO).
- [x] `CALayerPainter` now paints `Path`, `TSpan`, and `ZRImage` (Phase-1 painted `Path` only).

### Storage display list + ZRender host facade (`Sources/ZRenderKit/`)
- [x] `Storage.swift` ← `Storage.ts` — flattened, z/z2/zlevel-sorted display list (add/delete/clear,
      `updateDisplayList`); replaces the ad-hoc Group walk.
- [x] `ZRender.swift` ← `zrender.ts` — `ZRender` host: lifecycle (add/remove/clear/dispose),
      refresh/`_refresh`/flush/`_flush`, `isDarkMode`, `init`/`disposeAll`/`getInstance` registry,
      version, on/off/trigger routing. Replaces the `ZRenderType` forward-declaration in `Element.swift`.
      **Handler/HandlerProxy/findHover/coarse-pointer/configLayer/setCursorStyle + the `refreshHover`
      path are PORT-TODO stubs with faithful signatures (Phase 4); painter is injected, not built from a
      `painterCtors` map (no DOM ctor natively).**

---

## 8. Build & test status — Phase 2

- **`swift build` (library): GREEN.** **`swift build --build-tests`: GREEN.** Note: the library alone was
  green even while the *test* link failed — the failure was a SwiftPM object-file name collision on the
  case-insensitive macOS filesystem (object files named by basename, deduped case-SENSITIVELY): five
  `Contain/*.swift` lowercase files collided with `Graphic*` capitalized files
  (`arc↔Arc`, `line↔Line`, `path↔Path`, `polygon↔Polygon`, `text↔Text`), so one `.o` silently overwrote
  the other and its symbols vanished from the static archive (archiving doesn't verify symbol
  completeness, which is why the lib "built"). **Fix:** renamed the five `Contain/*` files to
  `Contain<Name>.swift` (namespaces only — smallest blast radius); no type names, math, or logic changed.
- **`swift test`: GREEN — 50 tests, 0 failures, 13 skipped** (verified this run).
  - **Golden geometry parity (byte-for-byte vs ECharts oracle):** 10/10 PASS — the 6 Phase-1 fixtures
    (rect, circle, sector, arc, bezier-curve, polygon) **plus** 4 new Phase-2 shapes: `ellipse`, `ring`,
    `line`, `polyline`. No `Sources/` change was needed for parity (exact output on first run).
  - **Decorative-shape smoke (no ECharts oracle):** heart, droplet, isogon, rose, star, trochoid — each
    builds a non-empty, NaN/Inf-free command buffer + rebuild token stream (`testDecorativeShapesSmoke`).
  - **Ported zrender unit tests** (behavioral oracle, `Tests/.../unit/`): `ContainSectorUnitTests` PASS
    (Sector containment via `Path.contain`), `ImageUnitTests` PASS×3 (size/aspect math),
    `TextUnitTests` SKIP×1 (rich-style merge needs Phase-3 `useState`).
  - **Skips (13):** the 12 pre-existing Phase-0/1 intentional faithfulness-gap skips (`util.clone`/`merge`,
    Path partial-merge, JS-only `this`-binding/typed-array semantics) **plus** the 1 new `TextUnitTests`
    states skip — all genuine deferrals, none a porting error.

---

## 9. Phase 2 — per-file status & review verdict

| File | Source `.ts` | Status | Verdict | Note |
|---|---|---|---|---|
| `Graphic/Text.swift` | `graphic/Text.ts` | complete (rich layout) | minor-issues (3) | empty-string color truthiness; `parseFontSize` `+x`-coercion; `'fill'/'stroke' in style` vs `!=nil` (explicit-null) |
| `Graphic/TSpan.swift` | `graphic/TSpan.ts` | complete | (foundation sweep) | — |
| `Graphic/Image.swift` | `graphic/Image.ts` | complete | faithful | native decode = file/data-URI only (remote URL = PORT-TODO) |
| `Graphic/CompoundPath.swift` | `graphic/CompoundPath.ts` | complete | (foundation sweep) | — |
| `Graphic/IncrementalDisplayable.swift` | `graphic/IncrementalDisplayable.ts` | complete | (foundation sweep) | — |
| `Contain/ContainPath.swift` | `contain/path.ts` | complete | minor-issues (1) | missing `\|\| 0`(orZero) wrap on windingCubic/windingQuadratic — currently inert, but a textual divergence |
| `Contain/ContainText.swift` | `contain/text.ts` | complete | faithful | — |
| `Contain/{ContainArc,ContainLine,ContainPolygon,cubic,quadratic,windingLine,containUtil}.swift` | `contain/*.ts` | complete | (foundation sweep) | renamed basenames (§8); content faithful |
| `Graphic/Shape/Ellipse.swift` | `graphic/shape/Ellipse.ts` | complete | faithful | — |
| `Graphic/Shape/Ring.swift` | `graphic/shape/Ring.ts` | complete | faithful | — |
| `Graphic/Shape/Line.swift` | `graphic/shape/Line.ts` | complete | minor-issues (1) | resolved `fill` diverges: `extendPathStyle` doesn't honor upstream explicit-`null` fill override (`#000` vs null) |
| `Graphic/Shape/Polyline.swift` | `graphic/shape/Polyline.ts` | complete | faithful | — |
| `Graphic/Shape/Star.swift` | `graphic/shape/Star.ts` | complete | minor-issues (2) | `!n` NaN-guard divergence; non-integer `n` truncation (`Int(n)*2-1`) — edge-case only |
| `Graphic/Shape/{Heart,Droplet,Isogon,Rose,Trochoid}.swift` | `graphic/shape/*.ts` | complete | faithful | — |
| `Storage.swift` | `Storage.ts` | complete | faithful | — |
| `ZRender.swift` | `zrender.ts` | complete (render surface) | faithful | Handler/hover/findHover = PORT-TODO (Phase 4); painter injected; documented `_refresh` hover-only no-op |
| `NativePainter/CGRenderer.swift` (+gradient/pattern/text/image) | (hand-written, §9) | complete | n/a | remote-URL image load + pattern rotation/scale matrix + line-cap/join keyword presets = PORT-TODO |
| `NativePainter/CALayerPainter.swift` (Path+TSpan+ZRImage) | (hand-written, §9) | complete | n/a | remote-URL async `onload` = PORT-TODO |

Roll-up (ported `.ts` mirrors with a review verdict): **faithful majority; 4 minor-issues
(`Text`×3, `ContainPath`×1, `Line`×1, `Star`×2), 0 major.** No new blockers; no `Sources/` bug fixes
were required to pass goldens/units.

---

## 10. Phase 2 — new open issues & PORT-TODO backlog (deduped, severity-sorted)

### Correctness / fidelity — review-flagged, fix opportunistically
1. **`Text` empty-string color truthiness** (`Text.swift` `_renderBackground` ~1133/1179, bg ~755/921/1128).
   TS uses JS truthiness (`textBorderWidth && textBorderColor`, `!!backgroundColor`); the port uses
   `!= nil`, so an empty-string color `""` reads as *present* — Swift strokes/fills with `.string("")`
   and treats bg as drawn where TS skips it. Internally inconsistent with the port's own `needDrawBackground`
   (which correctly uses `!color.isEmpty`). Degenerate inputs only; normal non-empty colors unaffected.
2. **`Text.parseFontSize` numeric coercion** (`Text.swift` ~1255). TS `!isNaN(+fontSize)` accepts `""`→0
   and whitespace-padded `"  12  "`→12; Swift `Double(s)` returns nil for both, falling to the default
   `DEFAULT_FONT_SIZE + "px"`. Edge-case (empty/whitespace fontSize strings).
3. **`'fill'/'stroke' in style` modeled as `!= nil`** (`Text.swift` ~795/803/1038/1051). TS `in` is key
   existence, so an explicit `fill: null` keeps existence true → `getFill(null)=null` (no default fill);
   the Swift value-type model maps absent ≡ explicit-null → `useDefaultFill`, applying `defaultStyle.fill`.
   Inherent value-vs-reference limitation; affects the auto-stroke `useDefaultFill` branch.
4. **`Line` (and any shape that nulls an inherited default) resolves `fill` to `#000`, not null**
   (`Line.swift:54` + `Path.swift:728` `extendPathStyle`). TS copies the own `fill:null` key over the
   prototype so resolved `fill===null`; the shared `extendPathStyle` guards `if source.fill != nil`, so
   the null override is dropped and `fill` stays `.string("#000")`. Root cause is the shared helper not
   honoring upstream explicit-null-override semantics; affects any `hasFill`/`shouldBePainted`/`getPaintRect`
   reading `style.fill`. Visual impact on a degenerate open path is negligible but the style state diverges.
5. **`ContainPath` missing `orZero()` on windingCubic/windingQuadratic** (`ContainPath.swift` ~311/330).
   TS wraps both with `|| 0`; the L-case and the windingLine calls correctly use `orZero`, so this is an
   inconsistency. **Currently inert** (those functions reject NaN roots and cannot return NaN), but a
   textual divergence — wrap both to keep mechanical re-sync exact.
6. **`Star` NaN-guard + non-integer `n`** (`Star.swift` ~55/82). TS `!n` returns early on `n===NaN`;
   Swift `n==0 || n<2` does not (NaN comparisons are false). TS keeps fractional `n` in the loop bound
   (`n*2-1`); Swift truncates (`Int(n)*2-1`), emitting a different vertex count. Edge-case only (`n` is
   normally an integer ≥3).

### Stubbed surfaces — whole features deferred (each is `// PORT-TODO`)
7. **Animation** remains a type-surface stub: `Animator` bodies, `easing` table,
   `animation/{Animation,Clip}.ts`, `Track`, and every `animateTo`/`animate`/`stopAnimation` path. → **Phase 3.**
8. **States / emphasis / blur / select** machinery still stubbed in `Element` (`useState` is a documented
   no-op returning nil — `Element.swift:556`). Consequence: `Text` rich-style state merge is unreachable
   (the one `TextUnitTests` skip). → **Phase 3** (states/`_mergeStyle`).
9. **Native image loading** is file path / base64 `data:` URI only (ImageIO). Remote-URL fetch + async
   `onload` (the deferred renderer seam, CONVENTIONS §9) is PORT-TODO in both `CGRenderer` and `CALayerPainter`.
10. **Event / Handler plumbing** — `ZRender.on/off/trigger` route to `Eventful`, but `Handler`,
    `HandlerProxy`, `findHover` (returns nil), coarse-pointer, `configLayer`, `setCursorStyle`, and the
    `refreshHover`/hover-layer path are PORT-TODO stubs. `Eventful` is still not fully wired into `Element`.
    → **Phase 4** (UIKit interaction layer).
11. **`CGRenderer` paint gaps:** pattern rotation/scale matrix (only `repeat` + x/y offset tiled today),
    line-cap/join keyword presets, gradient/pattern *text* fill, non-base64 (URL-encoded) data URIs.
12. **`ZRender._refresh` hover-only no-op** — the port only calls `painter.refresh` when `refresh==true`,
    so `refreshHover()`/`refreshHoverImmediately()` are no-ops (`// PORT-TODO`, Phase 4 hover-layer seam).

> Carry-over still open from §4 (Phase 1) and §P0-3 (Phase 0): `Displayable.STYLE_MAGIC_KEY` static-flag
> divergence (major — audit before state-style application lands), `Group.children()` value-copy,
> `color.swift` `lerp`/`modifyHSL`/`liftColor` partials (needed for gradient-stop tweening in Phase 3),
> `util.merge` null-guard gap, and the `Swift.min/max`/`|| 0`-vs-`?? 0` NaN-policy items — all low-risk
> under finite-coords usage.

---

## 11. Phase 3 plan (HISTORICAL — executed; results in §§13–17) — animation full + path-morphing tools + color completion (→ "logic-complete")

**Goal:** replace the animation type-surface stub with a real, driven animation system and the path
geometry tools, completing the renderer's *logic*. After Phase 3 zrender is **logic-complete**; Phase 4
(Handler/event/GestureMgr → UIKit) is the final interaction layer.

### 11a. Animation (`zrender/src/animation/`)
| Upstream file | Swift target | Already-ported deps |
|---|---|---|
| `animation/Animator.ts` (real bodies — Track/Clip/keyframe interpolation) | `Animation/Animator.swift` (replace stub) | `easing` (stub→fill), `color.lerp` (Phase-1 partial→complete), `util`, `Element`/`Path` animate hooks (already referenced) |
| `animation/Animation.ts` (the loop/scheduler) | `Animation/Animation.swift` | `Animator`, `ZRender.addAnimator`/`removeAnimator` hooks (present), `Eventful` |
| `animation/Clip.ts` (per-clip timeline) | `Animation/Clip.swift` | `easing` |
| `animation/easing.ts` (fill the stubbed table) | `Animation/easing.swift` (complete) | — |
| **rAF → CADisplayLink** host loop (hand-written, §9) | `NativePainter` | `Animation.update`/`ZRender.flush` |

### 11b. Path-morphing tools (`zrender/src/tool/`)
| Upstream file | Swift target | Already-ported deps |
|---|---|---|
| `tool/path.ts` | `Tool/path.swift` | `PathProxy`, `Path`, all shapes (Phase 1–2), `BoundingRect`, `matrix` |
| `tool/transformPath.ts` | `Tool/transformPath.swift` | `PathProxy`, `matrix`, `vector` |
| `tool/dividePath.ts` | `Tool/dividePath.swift` | `tool/path`, `PathProxy` |
| `tool/morphPath.ts` | `Tool/morphPath.swift` | `tool/dividePath`, `Animator` (11a), `curve` |

### 11c. `tool/color` completion (`zrender/src/tool/color.ts`)
Finish the Phase-1 partial: `lerp` / `mapToColor` / `modifyHSL` / `modifyAlpha` / `liftColor` (need
`util.isFunction`/`isString` guards + `GradientObject` — most already present). **Required by 11a**
(keyframe color interpolation) and gradient-stop tweening. Already-ported deps: `Tool/color.swift`
(parse/rgba/stringify/fastLerp), `Graphic/Gradient*`.

**Sequencing note:** 11c (`color.lerp`) and the `easing` table unblock 11a (`Animator` interpolation);
11a `Animator` unblocks 11b `morphPath`. The CADisplayLink host loop lands last, once `Animation.update`
is real. Handler/event/GestureMgr stay a **Phase-4** deferral throughout.

---

## 13. What landed in Phase 3 — checklist

**Goal (met):** replace the animation type-surface stub with a real, driven animation system and the
path-geometry tools, completing the renderer's *logic*. A hand-built tree's `animateTo`/`animate` now
produces real keyframe-interpolated tweens driven on a real frame clock (CADisplayLink/Timer), color
keyframes interpolate channel-wise, and the path-morphing toolchain (path↔polygon/bezier conversion,
affine path transform, shape division, and morph scheduling) is in place. **After Phase 3 zrender is
logic-complete** — rendering (Phase 1–2) + animation + path tools. Only the interaction layer (Phase 4)
remains.

### Animation — real bodies (`Sources/ZRenderKit/Animation/`)
- [x] `Animation/Animator.swift` ← `animation/Animator.ts` — **stub replaced with real Track/keyframe
      interpolation**: `Track`/`when`/`whenWithKeys`, keyframe-type detection (NUMBER / 1D-ARRAY /
      2D-ARRAY / COLOR / UNKNOWN), `fillArray` length-alignment, additive tracks, `interpolate1DArray`/
      `interpolate2DArray`/color lerp, `step`/`setTime`, `start`/`stop`/`delay`/`during`/`done`/`aborted`,
      `saveTo`/`__changedKeys`. Drives via `Clip`.
- [x] `Animation/Animation.swift` ← `animation/Animation.ts` — the loop/scheduler: linked-list
      add/remove of `Clip`/`Animator`, `update()` (step + `ondestroy`/`removeClip` on finish),
      `start`/`stop`/`pause`/`resume`/`clear`/`isFinished`, `_pausedTime`/`_pauseStart` bookkeeping,
      `getTime()`. `_startLoop`/`requestAnimationFrame` seam is delegated to the native host loop (§9 / PORT-TODO).
- [x] `Animation/Clip.swift` ← `animation/Clip.ts` — per-clip timeline: `step(globalTime, deltaTime)`,
      loop/delay/gap, easing application, `onframe`/`ondestroy`/`onrestart`. `setEasing` cubic-bezier
      string miss → linear (cubicEasing.ts not yet ported — PORT-TODO).
- [x] `Animation/easing.swift` ← `animation/easing.ts` — **stubbed table filled** (linear / quad / cubic /
      quart / quint / sine / expo / circ / elastic / back / bounce, in/out/inOut). `faithful`.

### Path-morphing & path tools (`Sources/ZRenderKit/Tool/`)
- [x] `Tool/ToolPath.swift` ← `tool/path.ts` — SVG-path parse (`createPathProxyFromString`), `processArc`
      (endpoint→center arc conversion), command walker (l/L/m/M/h/H/v/V/C/c/S/s/Q/q/T/t/A/a/z with
      reflection), `mergePath`/`clonePath`. (Named `ToolPath.swift` to avoid case-collision with
      `Graphic/Path.swift`, mirroring the §8 `Contain*` rename.)
- [x] `Tool/transformPath.swift` ← `tool/transformPath.ts` — in-place affine transform of `PathProxy`
      command data. `faithful` (R-case is Swift-safe rather than the upstream TypeError; see §15).
- [x] `Tool/dividePath.swift` ← `tool/dividePath.ts` — split a path/polygon into N sub-paths
      (clone-and-clip + farthest-pair bisection), `copyPathProps`.
- [x] `Tool/morphPath.swift` ← `tool/morphPath.ts` — the morph engine: `alignBezierCurves`/`alignSubpath`
      subdivision, centroid/signed-area, `findBestRingOffset`/`findBestMorphingRotation`, `buildPath`
      lerp+rotation, `morphPath`/`combineMorph`/`separateMorph` scheduler wiring, `__morphT`/`__morphBuildPath`
      seams on `final class Path`.
- [x] `Tool/convertPath.swift` ← `tool/convertPath.ts` — `pathToPolygons` / `pathToBezierCurves`
      (subpath sampling for morph alignment). (Named-export namespace deviation documented in-header.)

### `tool/color` completion (`Sources/ZRenderKit/Tool/color.swift`)
- [x] `lerp` / `fastMapToColor` / `mapToColor` / `modifyHSL` / `modifyAlpha` / `liftColor` finished
      (the Phase-1 partial). Color-keyframe interpolation (11a) and gradient-stop tweening now resolve.
      The Phase-1-deferred `tool/color` unit spec is now **fully un-skipped** (15/15 rows pass).

### Element / ZRender animation wiring (`Sources/ZRenderKit/`)
- [x] `Element.swift` — the real animation surface: `animate`/`addAnimator`/`animateTo`/`animateFrom`/
      `stopAnimation`/`_transitionState`, the module-level `animateTo`/`animateToShallow`/`copyValue`
      family, and `animationGet`/`animationSet` (primary Element/Transformable props via `_setKnownKV`).
      `zr.animation.addAnimator`/`removeAnimator` now drive real `Animator`s (was a no-op stub).
- [x] `ZRender.swift` — `animation` is a live `Animation` instance; `addAnimator`/`removeAnimator` route
      to it; `flush`→`animation.update`→`_flush`→`_refresh`→`painter.refresh` is the real frame path.

### CADisplayLink host loop (`Sources/NativePainter/AnimationLoop.swift`, hand-written, not a translation)
- [x] `AnimationLoop.swift` — the rAF→native frame-clock glue: CADisplayLink (iOS/tvOS, vsync-aligned),
      main-run-loop `Timer` ~60 Hz fallback (macOS). `init(animation:)` pumps `Animation.update()` per
      frame; `_DisplayLinkProxy` keeps `AnimationLoop` off `NSObject` and breaks the CADisplayLink retain
      cycle. `start`/`stop` idempotent; `getTime()` = `CACurrentMediaTime()*1000`.

---

## 14. Build & test status — Phase 3

- **Build: GREEN.** Clean build (`rm -rf .build && swift build`) compiles all targets first try; **no
  `Sources/` fixes were required** to integrate the real Animator over the Phase-1/2 stub seam. One
  benign unreachable-code warning around the `cfgAborted?()` branch (`Animator.swift` ~line 1120); non-blocking.
- **`swift test`: GREEN — 61 tests, 0 failures, 16 skipped** (verified this run). Baseline was Phase-2's
  50/13; Phase 3 adds 11 tests (7 pass, 4 skip) across three new files plus the un-skipped color spec.
  - **Animation interpolation smoke** (`Tests/.../AnimationSmokeTests.swift`, the in-flight-frame analog of
    GoldenTests geometry parity) — 4/4 PASS: linear number tween (midpoint/endpoint exact), cubicOut tween
    (monotonic, eased ≠ linear, uses the real `easing.cubicOut` as oracle), color tween (channel-wise rgba
    midpoint `[30,50,70,1]`), and direct `color.lerp(0.5,…)`. Synthetic timestamps drive `clip.step(time, delta)`
    deterministically (exactly what `Animation.update` does internally), avoiding wall-clock flake.
  - **Ported `tool/color` unit spec** (`ColorUnitTests.swift`) — **fully un-skipped** (Phase 1 had deferred
    it because `tool/color` was partial): all 15 upstream `colorStr → rgba` rows PASS exactly (incl. 0.2/0.5/0.8
    alpha cases).
  - **Ported `animation/ElementAnimation` spec** (`ElementAnimationUnitTests.swift`) — 6 methods, 3 pass / 3 skip:
    PASS undefined-value-not-animated, equal-value-not-animated, done-after-finish, and the primary-prop
    set-to-final (`x==10 && y==10`). SKIP the `shape.points`/`style.fill` sub-bag assertions and abort —
    they need the value-type `shape`/`style` keyed-access seam (see §16 #1).
  - **Skips (16):** the 13 pre-existing Phase-0/1/2 faithfulness-gap skips + 3 new
    `ElementAnimationUnitTests` value-bag-seam skips. All genuine deferrals, none a porting error.
- **No real porting bugs found** in the Phase-3 reviews; 0 failures, no `XCTExpectFailure` needed,
  all `Sources/` untouched by the test/integration sweep.

---

## 15. Phase 3 — per-file status & review verdict

| File | Source `.ts` | Status | Verdict | Note |
|---|---|---|---|---|
| `Animation/Animator.swift` | `animation/Animator.ts` | complete (real bodies) | minor-issues (3) | array-step tail truncation (wholesale `animationSet` vs in-place index write); `Double(str)` vs JS unary-`+` keyframe-type detection (`""`/`Infinity`/hex); `[weak self]` lifetime break (CONVENTIONS §8) — caller must retain the Animator |
| `Animation/Animation.swift` | `animation/Animation.ts` | complete | minor-issues (1) | `getTime()` returns fractional ms (Double) vs JS integer ms — benign per number→Double; scheduler logic verified faithful; `_startLoop`/rAF seam is a documented PORT-TODO |
| `Animation/Clip.swift` | `animation/Clip.ts` | complete | faithful | `setEasing` cubic-bezier-string miss → linear (cubicEasing.ts not yet ported — marked PORT-TODO); table-backed + function easings work |
| `Animation/easing.swift` | `animation/easing.ts` | complete | faithful | — |
| `Tool/ToolPath.swift` | `tool/path.ts` | complete | minor-issues (2) | numeric/parse core + regex + `processArc` byte-faithful; `clonePath` uses `useStyle` (REPLACE) vs TS `setStyle` (MERGE) — PORT-TODO; `clonePath` drops `buildPath` copy — PORT-TODO |
| `Tool/transformPath.swift` | `tool/transformPath.ts` | complete | faithful | R-case is Swift-safe (computes) where TS throws a TypeError on uninitialized `p` — deliberate, header-documented deviation |
| `Tool/dividePath.swift` | `tool/dividePath.ts` | complete | minor-issues (1) | `copyPathProps` `useStyle` vs `setStyle` (as ToolPath); empty-polygon branch fails gracefully vs TS throw; `Array.sort` not guaranteed stable (rare equal-key ties only) — all PORT-TODO/advisory |
| `Tool/morphPath.swift` | `tool/morphPath.ts` | complete | faithful | morph math + scheduler wiring match; `__morphBuildPath` captures `[weak toPath]` (justified seam, geometry never differs) |
| `Tool/convertPath.swift` | `tool/convertPath.ts` | complete | faithful | named-export namespace deviation documented |
| `Tool/color.swift` (completion) | `tool/color.ts` | complete | faithful | `lerp`/`mapToColor`/`modifyHSL`/`modifyAlpha`/`liftColor` finished; spec fully un-skipped |
| `Element.swift` (animation wiring) | `Element.ts` | complete (animation surface) | minor-issues (carry) | `animationGet`/`animationSet` cover primary props; value-type `shape`/`style` keyed access is the open seam (§16 #1) |
| `ZRender.swift` (animation wiring) | `zrender.ts` | complete | faithful | live `Animation` instance; real `flush`→`update`→`_refresh` path |
| `NativePainter/AnimationLoop.swift` | (hand-written, §9) | complete | n/a (not a translation) | CADisplayLink (iOS/tvOS) + Timer (macOS); rAF seam |

Roll-up (ported `.ts` mirrors with a review verdict): **6 faithful, 5 minor-issues, 0 major.** No new
blockers; no `Sources/` bug fixes were required to pass smoke/units.

---

## 16. Phase 3 — new open issues & PORT-TODO backlog (deduped, severity-sorted)

### Correctness / fidelity — review-flagged, fix opportunistically
1. **Value-type `shape`/`style` bags are not yet keyed-animatable** (the one structural seam, drives the
   3 `ElementAnimationUnitTests` skips). `Path`/`Displayable` expose `style`/`shape` as VALUE-type structs
   (`PathStyleProps`/`PathShape`) with no keyed `animationGet`/`animationSet` override, so
   `animateToShallow`'s `animObjSet` is a no-op for those sub-bags (`Element.swift` ~1410). Primary
   Element/Transformable props (`x`/`y`/`rotation`/…) animate correctly; `animateTo({shape:{…}})` /
   `animateTo({style:{fill:…}})` carry empty tracks and complete synchronously. Wiring keyed access into
   the value bags unblocks shape/style/decal tweening and morph-via-animateTo. (Carries §10 #8.)
2. **`Animator` array-step tail truncation** (`Animator.swift` ~633). Upstream mutates the live property
   array in place, writing only indices `0..<keyframeLen` and **leaving a longer existing target's tail
   untouched**; the port computes a fresh exactly-sized array and `animationSet`s it wholesale, dropping
   the surplus tail. Identical-dimension cases (the common path) are unaffected; only a target array
   *longer* than the destination keyframe diverges mid/after tween.
3. **`Animator` keyframe-type detection uses `Double(str)` not JS unary-`+`** (`Animator.swift` ~407).
   TS `!isNaN(+v)` coerces `""`→0, `"  3  "`→3, `"Infinity"`, hex `"0x10"`→16 to NUMBER; Swift `Double(str)`
   returns nil for all of those, so they fall to `color.parse` and become discrete/UNKNOWN. Most impactful
   for empty string. Low practical impact (real numeric keyframe strings are like `"2"`).
4. **`Animator` `start()` closures capture `[weak self]`** (`Animator.swift` ~1001/1033). Upstream's clip
   strongly retains the animator for the clip's run; the port's weak capture means an Animator that nothing
   else retains can dealloc mid-animation, silently no-op'ing `onframe`/`ondestroy` and skipping `done`.
   Documented CONVENTIONS §8 retain-cycle break — **callers must independently retain the Animator** (the
   `ZRender.animation` linked list does this in normal use).
5. **`clonePath`/`copyPathProps` `useStyle` (REPLACE) vs TS `setStyle` (MERGE)** (`ToolPath.swift` ~544,
   `dividePath.swift` ~336). For a partially-specified source style, the clone can end up with different
   defaults than upstream. PORT-TODO-flagged. Also `clonePath` drops `buildPath = sourcePath.buildPath`, so
   cloning an element whose geometry comes from an overridden `buildPath` (not `shape`) loses its drawing logic.
6. **`Clip.setEasing` cubic-bezier string → linear** (`Clip.swift` ~184). TS compiles a `cubic-bezier(...)`
   string via `createCubicEasingFunc`; the port returns nil → `step()` degrades to linear. Narrow:
   only cubic-bezier *string* easings; all table-backed named easings and function easings work.
   → **port `animation/cubicEasing.ts`** (small, deferred from Phase 3).
7. **`transformPath` R-case Swift-safe divergence** (`transformPath.swift` ~31). A path containing a `CMD.R`
   makes TS throw (`p` is `undefined`); the port zero-inits `p` and computes a transformed result. Deliberate
   safety deviation, header-documented — arguably more correct, but not an exact reproduction.
8. **`Animation.getTime()` fractional ms** (`Animation.swift:23`) vs JS integer `new Date().getTime()`.
   Benign per number→Double; only higher timing precision, no behavioral break.

### Now NO LONGER stubbed (closed by Phase 3)
- **Animation** is fully real: `Animator` bodies, the `easing` table, `Animation` scheduler, `Clip`
  timeline, and every `Element`/`ZRender` `animate`/`animateTo`/`stopAnimation`/`addAnimator` path now
  drive actual tweens on a real frame clock. (Closes §10 #7 / §4 #10.)
- **`tool/color` completion** — `lerp`/`mapToColor`/`modifyHSL`/`modifyAlpha`/`liftColor` done; gradient-stop
  and color-keyframe interpolation resolve. (Closes §4 #4 / §10 carry-over.)
- **Path-morphing toolchain** (`tool/path`, `transformPath`, `dividePath`, `morphPath`, `convertPath`) landed.

### REMAINS deferred → Phase 4 (interaction) and small follow-ups
- **States / emphasis / blur / select** machinery still stubbed in `Element` (`useState` a documented
  no-op). The `shape`/`style` keyed-animation seam (#1) and rich-text state merge depend on it.
  Carries §10 #8 — partly Phase 4, partly an `Element` state follow-up.
- **Event / Handler / GestureMgr plumbing** — `Handler`, `HandlerProxy`, `findHover` (returns nil),
  coarse-pointer, `configLayer`, `setCursorStyle`, the `refreshHover`/hover-layer path, and full `Eventful`-
  into-`Element` wiring. → **Phase 4** (§17).
- **Native image loading** — still file path / base64 `data:` URI only (ImageIO); remote-URL fetch + async
  `onload` PORT-TODO in `CGRenderer`/`CALayerPainter`. (Carries §10 #9.)
- **`animation/cubicEasing.ts`** (#6) — small, port when a cubic-bezier-string easing is first needed.

> Carry-over still open from §§4/10/P0-3: `Displayable.STYLE_MAGIC_KEY` static-flag divergence (major —
> audit before state-style application), `Group.children()` value-copy, `util.merge` null-guard gap, and
> the `Swift.min/max`/`|| 0`-vs-`?? 0` NaN-policy items — all low-risk under finite-coords usage.

---

## 17. zrender is LOGIC-COMPLETE — Phase 4 plan (interaction → UIKit/AppKit)

**zrender is now LOGIC-COMPLETE: rendering (Phase 1–2) + animation (Phase 3) + path tools (Phase 3).** A
hand-built `Group`/`Path`/`Text`/`Image` tree renders to pixels, hit-tests, animates on a real frame clock,
and morphs. The **only remaining zrender work is Phase 4 = interaction**: the browser DOM event /
pointer / gesture layer, which on native is mostly **hand-written UIKit/AppKit bridging**, not a direct
line-by-line translation. **After Phase 4, the port moves up to the ECharts layer** (coord / scale / data /
chart series).

### 17a. Upstream files
| Upstream file | Swift target | Nature |
|---|---|---|
| `Handler.ts` | `Handler.swift` | **Translate** — the dispatcher: `findHover` (route a pointer to the top hit `Displayable` via `contain/*`, already ported), event normalization, `dispatchToElement`, cursor, the `mousedown→mousemove→mouseup`/`click`/`mouseover`/`mouseout`/`globalout` state machine. Wires the `Eventful`-into-`Element` forwarding still stubbed since Phase 1. |
| `core/event.ts` | `Core/event.swift` | **Translate** — `normalizeEvent`/`clientToLocal`/`getNativeEvent`, `Dispatcher` typing, stop-propagation/prevent-default helpers (adapted to native event objects). |
| `core/GestureMgr.ts` | `Core/GestureMgr.swift` | **Translate the recognizer logic** (pinch/tap bookkeeping), but feed it from native gestures (17b) instead of raw multi-touch DOM `TouchEvent`s. |
| `dom/HandlerProxy.ts` | `NativePainter/UIKitHandlerProxy.swift` (hand-written) | **Bridge, not translate** — the DOM `HandlerProxy` attaches `addEventListener` for mouse/touch/pointer/wheel and feeds normalized events to `Handler`. The native analog attaches `UIGestureRecognizer`s / `NSResponder` events on the host view and feeds the same normalized event shape into `Handler`. |

### 17b. How it bridges to native UIKit/AppKit
- **Host view + responder:** the `CALayerPainter`'s backing `UIView`/`NSView` becomes the event source. A
  hand-written `UIKitHandlerProxy` (the `dom/HandlerProxy` analog) attaches:
  `UITapGestureRecognizer`, `UIPanGestureRecognizer`, `UIPinchGestureRecognizer`,
  `UILongPressGestureRecognizer` (iOS/tvOS) and `mouseDown/Up/Moved`/`scrollWheel`/`magnify(with:)`
  (macOS `NSResponder`).
- **Normalize → `Handler`:** each recognizer/responder callback maps the touch/pointer location into
  ZRender-local coordinates (`clientToLocal` from `core/event`, accounting for `dpr`/contentScale) and
  synthesizes the normalized event the translated `Handler.dispatch(...)` expects
  (`mousedown`/`mousemove`/`mouseup`/`click`/`mousewheel`/`pinch`), so `Handler`'s hit-routing + the ported
  `Eventful` dispatch stay unchanged.
- **`GestureMgr` reuse:** native `UIPinchGestureRecognizer`/`magnify` can either drive ZRender's `pinch`
  event directly (preferred — let UIKit recognize) or feed raw touches into the translated `GestureMgr`;
  the bridge picks the former and keeps `GestureMgr` for parity/headless paths.
- **Cursor / hover:** `Handler.setCursorStyle` maps to `NSCursor` (macOS) / is a no-op on touch; the
  `refreshHover`/hover-layer path (PORT-TODO since §10 #12) lands here.
- **No DOM:** no `addEventListener`, `pointer-events`, or `<canvas>` — the bridge owns all of that natively.

**Sequencing:** translate `core/event` + `Handler` + `GestureMgr` (logic), then hand-write
`UIKitHandlerProxy` to feed them; finally wire `ZRender.handler`/`findHover`/`refreshHover` (the §10 #10/#12
stubs) to the real `Handler`. After Phase 4 the renderer is interaction-complete and the port advances to
the ECharts layer.

---

## 18. What landed in Phase 4 — checklist

**Goal (met):** the interaction layer — route a native pointer/touch/gesture into the z-sorted Storage
display list, hit-test it to the top `Displayable` (`findHover`), and run the full
`mousedown→mousemove→mouseup`/`click`/`mouseover`/`mouseout`/`globalout`/`pinch` dispatch + bubble state
machine, wiring the long-stubbed `Eventful`-into-`Element` forwarding. zrender's browser DOM event source
(`dom/HandlerProxy.ts`) is **replaced by a hand-written UIKit/AppKit bridge** (CONVENTIONS §9), so the
same `ZRender`/`Handler`/`Element` event surface is driven natively on both iOS and macOS. **After Phase 4
zrender is COMPLETE.**

### Handler — hit-test / dispatch / bubble (`Sources/ZRenderKit/Handler.swift`)
- [x] `Handler.swift` ← `Handler.ts` — the dispatcher (composes `Eventful` via `_eventful`, mirroring
      `class Handler extends Eventful`). `findHover` (display-list walk + `isHover`/`setHoverTarget`
      clip/silent/ignore tri-state + the coarse-pointer enlarged-pointer ring scan), `mousemove`
      (mouseout/mousemove/mouseover transitions + cursor), `mouseout`/`globalout`, `dispatchToElement`
      (per-element `trigger` + host/parent bubble + global `trigger`), `commonHandler` (the unrolled
      `click`/`mousedown`/`mouseup`/`mousewheel`/`dblclick`/`contextmenu` set with the down/up/4px
      click gate), `processGesture` (feeds `GestureMgr`), `setHandlerProxy`/`setCursorStyle`/`dispose`.
      `EmptyProxy`, `HoveredResult`, `HandlerProxyInterface`, `DraggableHandler` conformance.
- [x] `Element` `Eventful` wiring is now LIVE — `cur.trigger(eventName, eventPacket)` drives the per-element
      listener surface that was stubbed since Phase 1; `ZRender.on/off/trigger` route to the real `Handler`.

### core/event normalization (`Sources/ZRenderKit/Core/event.swift`)
- [x] `Core/event.swift` ← `core/event.ts` (caseless `enum eventTool` namespace) — `normalizeEvent`
      (in-place `zrX`/`zrY`/`which`/`zrDelta` mutation on the reference-type `ZRRawEvent`, the wheel-delta
      sign ladder, which-bitmask, `getNativeEvent`/`clientToLocal` seam), `stop`/`notLeftMouse`/etc.
      The browser DOM coordinate bits (`getBoundingClientRect`, `dom.ts` viewport transform) are PORT-TODO
      native seams — the bridge supplies points already in ZRender-local coordinates.

### GestureMgr + Draggable (`Sources/ZRenderKit/`)
- [x] `Core/GestureMgr.swift` ← `core/GestureMgr.ts` — the pinch recognizer (`recognize`/`_recognize`/
      `clear`, two-finger distance ratio → `pinchScale`/`pinchX`/`pinchY`). `Touch`/`ZRRawTouchEvent`
      native seam types; `clientToLocal` is a passthrough (bridge pre-normalizes).
- [x] `mixin/Draggable.swift` ← `mixin/Draggable.ts` — drag/dragstart/dragend derived from the
      mousedown/mousemove/mouseup stream; `final class` composed by `Handler` (`DraggableHandler` protocol
      = the 3 Handler members it calls), `unowned handler` back-ref to break the retain cycle.

### Native UIKit/AppKit bridge + host (`Sources/NativePainter/ZRenderView.swift`, hand-written, not a translation)
- [x] `NativeHandlerProxy: HandlerProxyInterface` — the `dom/HandlerProxy.ts` analog. Carries the same
      sequencing as `localDOMHandlers` (touchstart → mousemove+mousedown, touchmove → processGesture+mousemove,
      touchend → mouseup + click-within-`TOUCH_CLICK_DELAY`, touchcancel → mouseup-no-click, direct `pinch`
      dispatch), emitting `ZRRawEvent`s through the composed `Eventful` that `Handler` subscribes to.
      `setCursor` is a no-op (PORT-TODO: `NSCursor` on macOS).
- [x] `ZRenderView` — the host view, split `#if canImport(UIKit)` (`UIView`: touchesBegan/Moved/Ended/
      Cancelled + `UIPinchGestureRecognizer`) vs `#elseif canImport(AppKit)` (`NSView`, `isFlipped=true`:
      mouseDown/Dragged/Up + rightMouseDown/contextmenu + scrollWheel + `NSMagnificationGestureRecognizer`),
      all inside an outer `canImport(UIKit) || canImport(AppKit)` guard so it builds for both destinations.
      Hosts the `CALayerPainter.rootLayer`, owns the `ZRender` facade (`ZRenderKit.init(painter:proxy:)`) +
      an `AnimationLoop`, resizes on layout, and normalizes each native event into a ZRender-local
      `ZRRawEvent` (incl. multi-touch `touches[]` for `GestureMgr`) forwarded through `NativeHandlerProxy`.

---

## 19. Build & test status — Phase 4

- **Build: GREEN.** A clean from-scratch rebuild (deleted `ZRenderKit.build` + `NativePainter.build`,
  `swift build`) compiles **all 88 units with 0 errors**. The Phase-4 interaction seam was already wired
  and faithful — **no logic-weakening edits were needed; no `Sources/` changes were made.** One benign
  warning remains (`Handler.swift:386` `var eventPacket` never mutated) — an intentional value-type-struct
  faithfulness artifact already flagged by the adjacent PORT-TODO (see §20 #1); left untouched to preserve
  the upstream loop shape.
- **`swift test`: GREEN — 65 executed / 0 failures / 14 skipped** (Phase-3 baseline 61/16-skipped grew by
  the new `InteractionSmokeTests`; the count shifts to 65/14 because the new file's skip-vs-pass split
  replaces some prior skip accounting — all passing).
- **Interaction smoke** (`Tests/ZRenderKitTests/InteractionSmokeTests.swift`, 7 tests — drives the REAL
  `Handler` (`findHover` + `dispatchToElement`) over a z-sorted `Storage` display list directly, NOT the
  UIKit bridge; `CALayerPainter` is used only as the `PainterBase` Handler needs for boundary checks):
  - Entry points used (read from `Handler.swift`): `zr.handler.findHover(x,y) -> HoveredResult`
    (`.target`/`.topTarget`) and `zr.handler.dispatchToElement(targetInfo, .click, event)`. Scene = a
    `Group` of `Rect`s via `zr.add`; `zr.storage.updateDisplayList()` re-sorts after z2 changes.
  - **Invariants asserted & PASS:** `findHover` inside A→A, inside B→B, neither→nil target; overlap returns
    the TOP (higher z2) element and flipping z2 + `updateDisplayList` flips the result (z-driven, not
    insertion luck); a `silent` rect is never `.target` (hit falls through to the non-silent rect below) but
    IS reported as `.topTarget` (matches `isHover→SILENT`); an `ignore` rect yields neither; `click`
    dispatches child → parent `Group` → ZR host in that exact order; click outside dispatches to nothing.
  - **1 documented-gap skip:** `test_stopPropagation_child_stops_parent` confirms the divergent behavior
    (parent fired) and `XCTSkip`s with a FAITHFULNESS-GAP message (repo skip convention) — see §20 #1. It is
    written to self-heal into a real passing assertion the moment `ElementEvent` becomes a reference type.

---

## 20. Phase 4 — per-file status & review verdict

| File | Source `.ts` | Status | Verdict | Note |
|---|---|---|---|---|
| `Handler.swift` | `Handler.ts` | complete | minor-issues (3) | bubble-cancel inert (value-type packet + omitted on-props, §20 #1); `dispatch(nil)` swallows vs TS invoking handler (#2); cursor `?? "default"` widening (#3) |
| `Core/event.swift` | `core/event.ts` | complete | faithful | `ZRRawEvent` is a reference type so `normalizeEvent` in-place `zrX/zrY/which/zrDelta` mutation is visible to callers (faithful self-aliasing); branch order / which-bitmask / wheel-delta ladder match. Two theoretical-only NaN/empty-string notes, both unreachable. |
| `Core/GestureMgr.swift` | `core/GestureMgr.ts` | complete | faithful | latent only: `_recognize` iterates `recognizers.keys` (Swift Dictionary order nondeterministic vs TS for-in); identical today (one `pinch` recognizer) — use an ordered list if upstream ever adds recognizers |
| `mixin/Draggable.swift` | `mixin/Draggable.ts` | complete | faithful | `final class` composed by Handler; `unowned handler` retain-cycle break (CONVENTIONS §8) |
| `NativePainter/ZRenderView.swift` (NativeHandlerProxy + ZRenderView) | (hand-written replaces `dom/HandlerProxy.ts`) | complete | n/a (not a translation) | `setCursor` no-op (PORT-TODO `NSCursor`); browser pointer-capture / global-document drag-outside replaced by native touch semantics |

Roll-up (ported `.ts` mirrors with a review verdict): **3 faithful, 1 minor-issues, 0 major.** No new
blockers; **no `Sources/` bug fixes were required** to pass the build or the smoke suite.

---

## 21. Phase 4 — new open issues & PORT-TODO backlog (deduped, severity-sorted)

### Correctness / fidelity — review-flagged
1. **Bubble cancellation is INERT — `stopPropagation`/`cancelBubble` cannot stop ZR bubbling**
   (`Handler.swift` `dispatchToElement` ~386–411; the central interaction concern). Upstream
   (`Handler.ts:311–324`) lets the bubble chain stop when `eventPacket.cancelBubble` becomes true — set
   either by an on-prop handler's truthy return (`el[eventKey].call(...)`) OR by a `.on` listener directly
   mutating the shared packet object (`eventPacket` is a plain JS object passed BY REFERENCE to
   `el.trigger`). In Swift, **`ElementEvent` is a value-type `struct`** (`Element.swift:127`), so the packet
   is COPIED into each `cur.trigger(eventName.rawValue, eventPacket)` call (`Handler.swift:392`); any
   listener mutation of `cancelBubble` is lost, and the on-prop path is omitted entirely (no
   `onclick`/`onmousedown` props on `Element` — native event seam). Net: `eventPacket.cancelBubble` can
   **never** become true, so the `if eventPacket.cancelBubble { break }` (line 398) and the
   `if !eventPacket.cancelBubble` global-trigger guard (line 403) are dead — every event always bubbles all
   the way to parent/host chain root and then to the global Handler trigger. `eventTool.stop`
   (`core/event.swift`) only sets `cancelBubble` on the underlying `ZRRawEvent` reference, which the loop
   never re-reads. Acknowledged via two PORT-TODO comments (`Handler.swift:381–385`) and covered by the
   `test_stopPropagation_child_stops_parent` skip. **FIX SUGGESTION:** make `ElementEvent` a `final class`
   (reference) so listener mutations propagate, OR have `dispatchToElement` re-read the underlying event's
   `cancelBubble` after each `trigger`. Either change self-heals the smoke test into a passing assertion.
2. **`dispatch()` swallows `nil` eventArgs** (`Handler.swift:333–339`). TS (`Handler.ts:263–266`):
   `const handler = this[eventName]; handler && handler.call(this, eventArgs)` — the handler is invoked even
   when `eventArgs` is undefined. Swift wraps the call in `if let eventArgs = eventArgs { ... }`, so
   `dispatch(name, nil)` invokes nothing. Minor/undocumented; in practice all call sites pass a real
   `ZRRawEvent` (and a JS handler reading `event.zrX` on undefined would crash anyway), so low impact, but a
   divergence from the literal TS control flow.
3. **Cursor fallback widening** (`Handler.swift:290`, `mousemove`). TS (`Handler.ts:223`) passes
   `hoveredTarget.cursor` straight through (could be undefined); Swift substitutes `?? "default"` when the
   `as? Displayable` cast or `.cursor` is nil — an element with an explicitly-unset cursor yields `"default"`
   in Swift vs undefined in TS. Negligible (`Displayable` defaults cursor non-nil; every real hover target
   is a `Displayable`); noted for completeness.

### Native-bridge approximations (browser-only bits the UIKit/AppKit bridge replaces — PORT-TODO)
4. **`setCursor` is a no-op** (`ZRenderView.swift` `NativeHandlerProxy.setCursor`). iOS has no pointer
   cursor; macOS could `NSCursor`-map `cursorStyle`. `Handler.setCursorStyle` therefore has no visible
   effect today.
5. **Drag-outside / pointer-capture** — the browser's global-`document` pointer-capture machinery
   ([DRAG_OUTSIDE] in `Handler.ts`) is replaced by native touch semantics (touch events keep firing once a
   sequence starts) and AppKit drag tracking; `isOutsideBoundary` is still honored, but there is no explicit
   capture object.
6. **GestureMgr fed by recognizers, not raw multi-touch parity** — the bridge prefers letting
   `UIPinchGestureRecognizer`/`NSMagnificationGestureRecognizer` recognize and dispatch `pinch` directly;
   `GestureMgr` is retained for the headless/`processGesture` path (touchstart/move/end still feed it
   `touches[]`). On an empty-space pinch, `processGesture` falls back to a sentinel `Displayable()` target
   (PORT-TODO: identity diverges from upstream `undefined`).
7. **`core/event` DOM coordinate bits** (`getBoundingClientRect`, `dom.ts` viewport transform, `window.event`)
   are PORT-TODO native seams — the bridge supplies `zrX`/`zrY` already in ZRender-local coordinates.
8. **`Handler.painterRoot` (DOM root) is nil natively**; `(painter as CanvasPainter).eachOtherLayer`
   user-layer dispatch (canvas-only) is not modeled (`Handler.swift:408`).

> Carry-over still open from §§4/10/16/P0-3: `Displayable.STYLE_MAGIC_KEY` static-flag divergence (major —
> audit before state-style application lands in the ECharts layer), the value-type `shape`/`style`
> keyed-animation seam (§16 #1), `useState`/states machinery still stubbed in `Element`,
> `Group.children()` value-copy, `util.merge` null-guard gap, `animation/cubicEasing.ts`, native remote-URL
> image loading, and the `Swift.min/max` / `|| 0`-vs-`?? 0` NaN-policy items — all low-risk under
> finite-coords usage, several of which the ECharts option-merge/data layer will force a decision on (§22).

---

## 22. zrender is COMPLETE — the ECharts-layer plan (next major milestone)

**zrender is now COMPLETE: rendering (Phase 1–2) + animation + path tools (Phase 3) + interaction
(Phase 4) are all ported.** The browser-only `canvas/` / `svg/` / `dom/` backends are **intentionally
replaced by `NativePainter`** (CG/CA renderer + CADisplayLink/Timer frame clock + UIKit/AppKit
HandlerProxy bridge), per CONVENTIONS §9 — they are NOT translations and were never meant to be.

### Verification posture (the regression net carried forward)
- **Total ported:** `Sources/ZRenderKit/` = **77 Swift files / ~23.5 K lines** (the line-by-line zrender
  mirror) + `Sources/NativePainter/` = **6 hand-written files / ~2.1 K lines** (the native backend) +
  **16 test files**.
- **Golden geometry parity** (byte-for-byte vs the real-ECharts oracle): 10/10 shape fixtures, via
  `testRebuiltDMatchesOracle` (PathProxy replay) **and** `testSwiftBuildPathMatchesOracle` (true
  `Shape.buildPath` output).
- **Ported zrender unit tests** (behavioral oracle, the upstream Jest specs → XCTest):
  matrix/LRU/util/platform/path/group/contain-sector/image/color/element-animation.
- **Smoke tests:** decorative-shape NaN-free buffers, `CALayerPainter` renderToImage, animation
  interpolation (in-flight-frame parity vs the real `easing`), and now the Phase-4 interaction smoke
  (`findHover` + `dispatchToElement` over a z-sorted Storage list).
- `swift build` green for both iOS and macOS destinations; `swift test` 65/0-fail/14-skip.

### Pre-ECharts: a fidelity-hardening pass (do FIRST)
The carry-over JS-truthiness / null / NaN backlog (`STYLE_MAGIC_KEY`, `util.merge` null-guard, `|| 0` vs
`?? 0`, `Swift.min/max` NaN non-propagation, `'key' in obj` vs `!= nil`, empty-string color truthiness, the
value-type `shape`/`style` keyed-access seam, `useState`/states) has been low-risk under "finite-coords
only" geometry usage — **but the ECharts option-merge and data layers deliberately feed these edge values**
(absent/`null`/`NaN` config, deep option merge, sparse data). Do a focused hardening pass on these BEFORE
the ECharts port so the divergences don't silently corrupt option resolution and data scaling.

### Faithful ECharts port order (`echarts/src/`, reusing the complete `ZRenderKit`)
1. **`model/`** — `Global`/`GlobalModel`, `Component`/`ComponentModel`, `Series`/`SeriesModel`,
   option merge/normalize (forces the deep-merge / null-guard fidelity items above).
2. **`data/`** — `DataStore`, `SeriesData` (the columnar store), `DataDiffer` (enter/update/exit diff for
   data-driven transitions — pairs with the Phase-3 animation system).
3. **`scale/`** — `Scale` base, `Interval`/`Ordinal`/`Time`/`Log`, nice-ticks.
4. **`coord/cartesian/`** — `Cartesian2D`, `Axis2D`, `Grid` data↔pixel mapping.
5. **`Scheduler` + the `Task`/`stream` pipeline** — the per-stage (`createData`/`processData`/`visual`/
   `layout`/`render`) task graph that drives a render.
6. **`visual/` + `layout/`** — visual encoding (color/symbol/size mapping) and series layout.
7. **First `ChartView`** — `BarView` or `LineView` — plus `grid`/`axis` components, reusing the ported
   `Group`/`Path`/`Rect`/`Polyline`/`Text` + the animation + interaction layers end-to-end.

**Sequencing:** `model/` → `data/` → `scale/` → `coord/cartesian` → `Scheduler/Task` → `visual/`+`layout/`
→ first `ChartView` + `grid/axis`. Each stage keeps the standing upstream-sync rule (§12) and adds its
matching ported unit specs + (where an ECharts oracle exists) golden fixtures.

---

## 23. What landed in Phase 5b — the ECharts data engine (`echarts/src/data/`)

**Phase 5b (DATA-ENGINE: the columnar store + series data facade + diff + source/dimension pipeline):
COMPLETE — `swift build` GREEN, `swift test` 143 executed / 0 failures / 16 skipped, and the FIRST
ported ECharts unit tests (number + scale-interval) landed as a behavioral oracle.** Builds on the
Phase-5a `util/` + `scale/` layers (no integration breakage; no source edits to the existing layers).
The MODEL layer (Phase 5c) is still absent — `SeriesModel`/option access points are minimal protocols
/ `// PORT-TODO` stubs so data compiles standalone.

### The columnar store + series-data facade (`Sources/EChartsKit/data/`)
- [x] `data/DataStore.swift` ← `data/DataStore.ts` — the low-level columnar store: chunked `_chunks`
      typed columns, `appendData`/`appendValues`, `getRawIndex`/`get`/`getValues`, `getDataExtent`,
      `indexOfRawIndex`/`indicesOfNearest`, ordinal collection (`collectOrdinalMeta`), `map`/`modify`/
      `filter`/`selectRange`/`downSample`/`lttbDownSample`, `getMedian`, `clone`/`_copyCommonProps`.
- [x] `data/SeriesData.swift` ← `data/SeriesData.ts` — the high-level facade over `DataStore`: dimension
      bookkeeping (`_dimInfos`/`_dimSummary`), `initData`/`appendData`/`appendValues`, `getId`/`getRawIndex`,
      `getName`/`getItemModel`(stubbed for 5c), `each`/`map`/`filterSelf`/`selectRange`/`mapArray`,
      visual/layout state bags, `diff` key-getters, `cloneShallow`/`downSample`.
- [x] `data/DataDiffer.swift` ← `data/DataDiffer.ts` — the enter/update/exit diff (`add`/`update`/`remove`/
      `updateManyToOne`/`updateOneToMany`/`updateManyToMany`, `_executeOneToOne`/`_executeMultiple`,
      key-array dedup). Pairs with the Phase-3 animation system for data-driven transitions.
- [x] `data/Source.swift` ← `data/Source.ts` — `Source` (seriesLayoutBy / sourceFormat / dimensionsDefine /
      startIndex / encodeDefine), `createSource`/`createSourceFromSeriesDataOption`, `detectSourceFormat`.
- [x] `data/SeriesDimensionDefine.swift` ← `data/SeriesDimensionDefine.ts` — the per-dimension descriptor.
- [x] `data/OrdinalMeta.swift` (already landed Phase-5a stub; relied on here) — ordinal category mapping.

### Data helpers (`Sources/EChartsKit/data/helper/`)
- [x] `helper/dataValueHelper.swift` ← `helper/dataValueHelper.ts` — value parse/compare (`parseDataValue`,
      `createOrdinalSortInfo`, `SortOrderComparator`).
- [x] `helper/SeriesDataSchema.swift` ← `helper/SeriesDataSchema.ts` — dimension schema + `createDimensions` glue.
- [x] `helper/dimensionHelper.swift` ← `helper/dimensionHelper.ts` — `summarizeDimensions`, dimension-type maps.
- [x] `helper/sourceHelper.swift` ← `helper/sourceHelper.ts` — `prepareSource`/`querySeriesUpstreamDatasetMetaRawData`-class glue.
- [x] `helper/createDimensions.swift` ← `helper/createDimensions.ts` — dimension inference from source + encode.
- [x] `helper/dataProvider.swift` ← `helper/dataProvider.ts` — `DefaultDataProvider`, `getRawSourceItemGetter`/`getDataItemValue` accessors.
- [x] `helper/dataStackHelper.swift` ← `helper/dataStackHelper.ts` — `enableDataStack`/`getStackedDimension` (via the `DataStackSeriesData` PORT-TODO bridge).

### Phase 5b — per-file status & review verdict
| File | Source `.ts` | Status | Verdict | Note |
|---|---|---|---|---|
| `data/DataStore.swift` | `data/DataStore.ts` | complete | **minor-issues (3)** | `getMedian` can TRAP out-of-bounds on dims with NaN/empty points (upstream returns NaN) — §24 #1; `clone()`/`_copyCommonProps` value-copies `_dimensions` (struct) vs upstream reference-share — §24 #2; `downSample` drops `\|\| 0` (verified inert) |
| `data/SeriesData.swift` | `data/SeriesData.ts` | complete | **major-issues (1)** | `diff()` key-getters feed the loop index `i` to `getId` instead of the rawIndex `value` — wrong diff keys on FILTERED data (dataZoom) — §24 #0 (the one real bug to fix) |
| `data/DataDiffer.swift` | `data/DataDiffer.ts` | complete | faithful | — |
| `data/Source.swift` | `data/Source.ts` | complete | minor-issues (1) | `:486` dead `rawItem == nil` branch (loose dim is non-optional `Any`); coercion path always runs — faithful shape preserved |
| `data/SeriesDimensionDefine.swift` | `data/SeriesDimensionDefine.ts` | complete | (foundation sweep) | — |
| `data/helper/dataValueHelper.swift` | `helper/dataValueHelper.ts` | complete | (foundation sweep) | — |
| `data/helper/SeriesDataSchema.swift` | `helper/SeriesDataSchema.ts` | complete | (foundation sweep) | — |
| `data/helper/dimensionHelper.swift` | `helper/dimensionHelper.ts` | complete | (foundation sweep) | — |
| `data/helper/sourceHelper.swift` | `helper/sourceHelper.ts` | complete | (foundation sweep) | — |
| `data/helper/createDimensions.swift` | `helper/createDimensions.ts` | complete | (foundation sweep) | — |
| `data/helper/dataProvider.swift` | `helper/dataProvider.ts` | complete | (foundation sweep) | — |
| `data/helper/dataStackHelper.swift` | `helper/dataStackHelper.ts` | complete | (foundation sweep) | `:309`/`:315` redundant `as? DataStackSeriesData` (always succeeds) — PORT-TODO bridge for `getCalculationInfo`, left to mirror upstream call shape until 5c |

Also reviewed (carried scale/util mirrors, all **faithful**): `scale/Interval.swift`, `scale/Scale.swift`
— no semantic divergences; two benign notes (`getLabel` `precision as! Double` traps on a non-Double
caller; `Scale._isBlank` initialized `false` vs TS `undefined`, both falsy).

Roll-up (ported `.ts` mirrors with a review verdict): **majority faithful; 1 major-issues
(`SeriesData.diff`), 3 minor (`DataStore`), plus `Source` minor.** One genuine bug surfaced (§24 #0).

---

## 24. Build & test status — Phase 5b (incl. the FIRST ported ECharts unit tests)

- **`swift build`: GREEN.** The data engine compiled cleanly against the already-ported `util/` and
  `scale/` layers on the first iteration — **no integration edits to existing sources were required**,
  no DataStore/SeriesData/diff math was weakened, and no call sites needed model stubs beyond what the
  parallel translation already added.
- **`swift test`: GREEN — 143 executed / 0 failures / 16 skipped** (up from Phase-5a's 115/14). The 14
  pre-existing skips are all ZRenderKit faithfulness-gaps (`util.clone` TypedArray/user-class,
  `util.merge` null/undefined target — unrelated to data); the 2 NEW skips are the scale extreme-ticks
  tests that need `createChart` + model/coord (Phase 5c).
- **FIRST ported ECharts unit tests** (a new `EChartsKitTests` target in `Package.swift`, deps
  EChartsKit + ZRenderKit — the first behavioral oracle for the Phase-5a scale math):
  - `Tests/EChartsKitTests/NumberUnitTests.swift` ← `test/ut/spec/util/number.test.ts` (24 methods):
    `linearMap` (accuracy/clamp/noClamp/zeroInterval), `parseDate`, `reformIntervals`, `getPrecision`/
    `getPrecisionSafe` (incl. the 500-iter fuzz), `addSafe` (full ~250-case decimal.js table),
    `getPercentWithPrecision`, `quantityExponent`, `quantity`, `nice`, `isNumeric`/`numericToNumber`,
    `getAcceptableTickPrecision`/`getPixelPrecision`.
  - `Tests/EChartsKitTests/ScaleIntervalUnitTests.swift` ← `test/ut/spec/scale/interval.test.ts`: the
    portable `helper.intervalScaleNiceTicks(...)` half of `doSingleTestDeal` (4 explicit cases +
    `randomCover` 500+200 iters, asserting finite interval/precision and niceTickExtent ⊂ extent).
  - **EChartsKitTests: 28 methods, 26 pass / 0 fail / 2 skip.** Skips: `test_extreme_ticks_min_max` and
    `test_extreme_ticks_small_value` (both need `createChart` + CartesianAxisModel + a full axis →
    Phase 5c). The `scaleCalcNice2`/new-IntervalScale half of the ticks cases was omitted in-place
    (documented in-test; depends on coord/axisNiceTicks, Phase 5c).
- **Specs NOT ported (no module/scope):** `util/format` has NO upstream spec; there is NO
  `data/DataStore.test.ts` upstream; `data/{dataValueHelper,createDimensions,SeriesData,dataTransform}.test.ts`
  exist but hinge on JS dynamic-typing of `unknown` values + Source/`SeriesModel`/`createSource` surfaces
  + deep object `toEqual` — deferred behind the scale-math priority until Phase 5c lands the model layer.
- **No `Sources/` was edited to paper over any behavioral divergence.** The only Source touches were a
  case-collision filename rename (build-system, not behavior) and header-provenance notes.

---

## 25. Phase 5b — new open issues & PORT-TODO backlog (deduped, severity-sorted)

### Major — the one real bug to fix (review-flagged)
0. **`SeriesData.diff()` key-getters pass the WRONG argument to `getId`** (`SeriesData.swift:1035–1040`).
   The closures `{ _, idx in SeriesData.getId(otherList!, idx) }` discard the value and pass the loop
   POSITION `idx`. `DataDiffer.swift:326` invokes `keyGetter(arr[i], i)` (value first), and upstream
   `SeriesData.ts:1149–1154` binds `idx` to that FIRST arg = the rawIndex from `getStore().getIndices()`.
   So the port keys items by display position, not rawIndex. **When `getIndices()` is identity (fresh/
   unfiltered data) `arr[i] === i` so there is no observable difference; but after `filterSelf`/
   `selectRange` (dataZoom) the indices are a non-identity subset (e.g. `[2,5,9]`) and the diff produces
   wrong ids → wrong add/update/remove classification → broken update animations / state continuity on
   filtered data.** Correct port: `{ value, _ in SeriesData.getId(otherList!, value as! Int) }` (and the
   same for `thisList`). FIX before any dataZoom/transition work in 5c+.

### Correctness / fidelity — review-flagged, fix opportunistically
1. **`DataStore.getMedian` can TRAP out-of-bounds** (`DataStore.swift:559–579`). It faithfully copies
   upstream's index math using `len = count()` to index `dimDataArray`, but `dimDataArray` only holds the
   NON-NaN values. With any NaN/empty points (common in line charts) `dimDataArray.count < len`, so
   `dimDataArray[(len-1)/2]`/`[len/2]` go out of bounds → Swift fatal crash, where upstream TS
   (`DataStore.ts:525–531`) returns `undefined`→NaN. Behavioral divergence: crash vs NaN.
2. **`DataStore` value-vs-reference divergence across `clone()`** (`_copyCommonProps`, `DataStore.swift:1332`).
   Upstream `_copyCommonProps` shares `_dimensions` BY REFERENCE (`target._dimensions = this._dimensions`,
   `DataStore.ts:1258`) — and likewise non-picked `_chunks` columns. The port models
   `DataStoreDimensionDefine` as a `struct` and value-copies, so in-place dim mutations after a clone
   (`collectOrdinalMeta` setting `ordinalMeta`/`type`/`ordinalOffset`; `ensureCalculationDimension` adding
   dims) are visible to sibling clones in TS but NOT in Swift (each clone is independent), and non-picked
   columns are COW value-copies not shared objects. Practical trigger is narrow under the actual call order
   (collect/ensure run at init/stack time before filter/map/downSample clones), but it is a genuine
   reference-semantics divergence — audit before Phase-5c stack/transition wiring relies on shared dims.
3. **`Source.swift:486` dead null branch** — upstream guards `rawItem == null`; the Swift loose dimension
   value is non-optional `Any`, so the null branch (and its dependent ternary else) is unreachable. The
   `plusEmptyString` coercion path always runs, matching the non-null case. Faithful shape preserved.
4. **`DataStore.downSample` drops `Math.min(..., len-1) || 0`** (`DataStore.swift:1134`) — verified a true
   no-op (`sampleIndex` returns `Int`, cannot be NaN; sum is ≥ 0), the `|| 0` only ever mattered for a JS
   NaN that cannot occur in Swift. Noted for mechanical-resync exactness, not a behavioral divergence.

### MODEL refs stubbed for Phase 5c (PORT-TODOs the data layer left open)
5. **`SeriesData.getItemModel`/`getModel`/option access** are minimal-protocol / `// PORT-TODO` stubs —
   the real `SeriesModel`/`Model` does not exist yet. `getName`/visual defaults that read model option are
   the seams Phase 5c must wire.
6. **`dataStackHelper` `getCalculationInfo` bridge** (`dataStackHelper.swift:309/315`) — `data` is cast
   `as? DataStackSeriesData` (redundant today since `SeriesData` already conforms; emits a warning). Left
   to mirror upstream's `data.getCalculationInfo('stackedDimension'/'stackResultDimension')` call shape
   until 5c provides the real `getCalculationInfo`.
7. **`scale/Interval.getLabel` `precision as! Double`** traps if a caller stores `opt.precision` as a
   non-Double numeric. Consistent with number→Double; faithful callers (model `'auto' | number`) unaffected.

> Carry-over still open from §§4/10/16/21/P0-3: `Displayable.STYLE_MAGIC_KEY` static-flag divergence
> (major — the ECharts option/visual layer will force this), the value-type `shape`/`style` keyed-animation
> seam, `useState`/states still stubbed in `Element`, `util.merge` null-guard gap (the §22 fidelity-hardening
> pass — the model option-merge in 5c is exactly where the deep-merge/null-guard items become load-bearing),
> `Group.children()` value-copy, and the `Swift.min/max` / `|| 0`-vs-`?? 0` NaN-policy items.

---

## 26. Phase 5c plan (HISTORICAL — executed; results in §§27–30) — the `model/` spine (HIGHEST-RISK layer: the dynamic option-merge system)

**Goal:** the ECharts model spine — `Model` + mixins, `ComponentModel`, `SeriesModel`, `GlobalModel`,
`OptionManager`, and `model/globalDefault` — i.e. the **dynamic option-merge / normalize / default-cascade
system**. This is the highest-risk layer: it is where ECharts' deeply-dynamic JS option object (absent /
`null` / `NaN` / mixed-type config, arbitrary nesting, `mergeOption`, default cascades, query paths) meets
Swift's value/type system, and it is what `data/` (§§23–25) was deliberately stubbed against. It directly
forces the §22 fidelity-hardening decisions (`util.merge` null-guard, `'key' in obj` vs `!= nil`, `|| 0`
vs `?? 0`, JS truthiness) — **do that hardening pass on `util/` FIRST, then port `model/`.**

### 26a. Upstream files (port order) — `echarts/src/model/`
| Upstream file | Swift target | Already-ported deps | Nature |
|---|---|---|---|
| `model/Model.ts` | `model/Model.swift` | `util/{clazz,model,component}` (Phase-5a), `util.merge`/`clone`/query | the base: `get`/`getShallow`/`getModel`/`option`, `mergeOption`, mixin host |
| `model/mixin/{lineStyle,areaStyle,textStyle,itemStyle}.ts` + `model/mixin/makeStyleMapper.ts` | `model/mixin/*.swift` | `Model`, `util` | the style-getter mixins (`getItemStyle`/`getLineStyle`/…) — Swift composition vs TS `mixin()` |
| `model/Component.ts` (`ComponentModel`) | `model/Component.swift` | `Model`, `util/{component,clazz}`, `ComponentType`/subType registry | component base + the `extend`/`registerClass`/`getClass` registry + `defaultOption` cascade |
| `model/Series.ts` (`SeriesModel`) | `model/Series.swift` | `ComponentModel`, `data/SeriesData`+helpers (§23 — wires the §25 #5 stubs), `Source`/`createSource` | series base: `getInitialData`/`getData`/`getRawData`, `formatTooltip`, `mergeDefaultAndTheme` |
| `model/Global.ts` (`GlobalModel`) | `model/Global.swift` | `ComponentModel`, `OptionManager`, `util/model` (`mappingToExists`/`makeIdAndName`) | the option root: `mergeOption`, component instance create/merge/remove, `getComponent`/`queryComponents`/`eachSeries` |
| `model/OptionManager.ts` | `model/OptionManager.swift` | `GlobalModel`, `util/model`, media-query/timeline | raw-option lifecycle: `setOption`/`mergeOption`, media-query resolution, timeline option, `getTimelineOption` |
| `model/globalDefault.ts` | `model/globalDefault.swift` | — | the top-level default option object |
| (support) `model/referHelper.ts`, `model/internalComponentCreator.ts` | as needed | `Global`, `util/model` | coord-sys refer + internal component creation |

### 26b. Risk surface + sequencing
- **Option merge is the crux:** `Model.mergeOption`/`GlobalModel.mergeOption` lean on faithful deep-merge
  with null/undefined semantics (`util.merge` — §25 carry-over) and `'key' in option` existence checks.
  The value-type `Any`/dictionary modeling of the option tree must preserve absent-vs-`null`-vs-falsy
  distinctions or default cascades silently diverge. **This is the §22 hardening pass's payoff point.**
- **Registry/`extend` dynamics:** `ComponentModel.extend`/`registerClass`/`getClass` and subType lookup are
  JS-prototype/`this`-dynamic; port to a Swift type-registry + protocol surface (mirror names, mark the
  deviation `// PORT-TODO`).
- **Mixins:** TS `mixin(Model, LineStyleMixin)` → Swift protocol-extension composition; keep getter names
  (`getItemStyle`/`getLineStyle`/`getAreaStyle`/`getTextStyle`) identical.
- **Sequencing:** `util/` fidelity-hardening (merge/null/`in`/NaN) → `Model` + mixins → `ComponentModel`
  (+registry) → `SeriesModel` (wires the §25 #5 `getItemModel`/`getModel` data stubs to real models) →
  `GlobalModel` → `OptionManager` + `globalDefault`. Each stage ports its matching upstream spec
  (`test/ut/spec/model/*`) as the behavioral oracle and keeps the §12 upstream-sync rule.
- **After 5c**, the data layer's model stubs (§25 #5/#6) resolve, unblocking `scale`↔`axisModel`,
  `coord/cartesian` (the original §22 step 4), and the first `ChartView`.

---

## 27. What landed in Phase 5c — the ECharts model spine (`echarts/src/model/`)

**Phase 5c (MODEL SPINE: the dynamic option-merge / normalize / default-cascade system —
`Model` + 7 mixins, `ComponentModel`, `SeriesModel`, `GlobalModel`, `OptionManager`, `globalDefault`
+ support): COMPLETE — clean `rm -rf .build && swift build` GREEN across ZRenderKit/NativePainter/
EChartsKit/DemoGallery, `swift build --build-tests` GREEN, `swift test` GREEN (208 executed / 55
skipped / 0 failures across the whole package; 26 NEW active model-layer tests all pass).** The
parallel-translated spine integrated with the Phase-5a/5b `util/`+`scale/`+`data/` layers with **no
source edits** to the existing layers. This is the crux dynamic-option layer: `Model` is a reference
type, dynamic bags are `[String: Any]`, deep-merge routes through `util.merge` (null/undefined guard),
and `Model.get(path)` does dynamic keyed/dotted-path access with parent-model cascade.

### The base + mixins (`Sources/EChartsKit/model/` + `model/mixin/`)
- [x] `model/Model.swift` ← `model/Model.ts` — the base: `get`/`getShallow`/`getModel`/`option`,
      `_doGet` keyed+dotted path access, parent-model cascade + `ignoreParent`, `mergeOption` deep-merge,
      `isEmpty`, `clone`, `isAnimationEnabled`, mixin host. Reference type (`final/open class`).
- [x] `model/mixin/makeStyleMapper.swift` ← `model/mixin/makeStyleMapper.ts` — the style-key → getter
      mapper factory shared by the style mixins.
- [x] `model/mixin/{itemStyle,lineStyle,areaStyle,textStyle}.swift` ← matching `model/mixin/*.ts` — the
      style-getter mixins (`getItemStyle`/`getLineStyle`/`getAreaStyle`/`getTextStyle`). **TS `mixin()`
      is realized as Swift protocol + protocol-extension composition; getter names kept identical.**
- [x] `model/mixin/palette.swift` ← `model/mixin/palette.ts` — `getColorFromPalette`/color-cache
      (`PaletteMixin` protocol).
- [x] `model/mixin/dataFormat.swift` ← `model/mixin/dataFormat.ts` — `getDataParams`/`formatTooltip`
      glue (`DataFormatMixin`).

### Component / Series / Global / OptionManager (`Sources/EChartsKit/model/`)
- [x] `model/Component.swift` ← `model/Component.ts` (`ComponentModel`) — component base + the
      `mergeDefaultAndTheme`/`mergeOption`/`getDefaultOption` default cascade, `mainType`/`subType`,
      `getBoxLayoutParams`, the class-registry surface (`registerClass`/`getClass`/`getAllClassMainTypes`/
      `topologicalTravel`).
- [x] `model/Series.swift` ← `model/Series.ts` (`SeriesModel`) — series base: `getInitialData`/`getData`/
      `getRawData`, `mergeDefaultAndTheme`, `mergeOption`, `isAnimationEnabled`. **Wires the §25 #5 data
      stubs to real types: `getInitialData(_:_:) -> SeriesData?`** (see §29 below).
- [x] `model/Global.swift` ← `model/Global.ts` (`GlobalModel`) — the option root: `mergeOption`/
      `_mergeOption`, `getTheme()` (returns a real `Model`), `mergeTheme`, `getComponent`/`queryComponents`/
      `eachSeries`/`getSeries*`/`reCreateSeriesIndices`, `isNotTargetSeries`. **Component/series
      instantiation from the option tree is stubbed to nil (documented — see §29/§30).**
- [x] `model/OptionManager.swift` ← `model/OptionManager.ts` — raw-option lifecycle: `setOption`/
      `mergeOption`, timeline `getTimelineOption`/`options`, media `getMediaOption`/`parseRawOption`.
- [x] `model/globalDefault.swift` ← `model/globalDefault.ts` — the top-level default option object.
- [x] `model/referHelper.swift` ← `model/referHelper.ts`, `model/internalComponentCreator.swift`
      ← `model/internalComponentCreator.ts` — coord-sys refer + internal-component creation support.

### Phase 5c — per-file status & review verdict
| File | Source `.ts` | Status | Verdict | Note |
|---|---|---|---|---|
| `model/Model.swift` | `model/Model.ts` | complete | minor-issues (3) | `isAnimationEnabled` truthy-non-dict option skips parent-recursion (dict-cast gate); `getModel` returns a Model over a VALUE-COPY subtree (no mutate-through — inherent to `[String:Any]` bag); `clone()` returns base `Model` not the concrete subclass (PORT-TODO) |
| `model/mixin/makeStyleMapper.swift` | `model/mixin/makeStyleMapper.ts` | complete | (foundation sweep) | — |
| `model/mixin/{itemStyle,lineStyle,areaStyle,textStyle}.swift` | `model/mixin/*.ts` | complete | (foundation sweep) | TS `mixin()` → Swift protocol-extension composition |
| `model/mixin/palette.swift` | `model/mixin/palette.ts` | complete | (foundation sweep) | — |
| `model/mixin/dataFormat.swift` | `model/mixin/dataFormat.ts` | complete | (foundation sweep) | — |
| `model/Component.swift` | `model/Component.ts` | complete | minor-issues (2) | THEME-MERGE stub un-wired against a now-STALE reason (`getTheme()` exists — §615) → per-mainType theme options never merged (masked: new-component init is a documented no-op); layout-mode merge deferred (no `util/layout`) |
| `model/Series.swift` | `model/Series.ts` | complete | **major-issues (3)** | see §29 #0a/#0b/#0c (the two value-vs-reference bugs + the `animationThreshold ?? 0` NaN/`>undefined` divergence) |
| `model/Global.swift` | `model/Global.ts` | complete | minor-issues (3) | `isNotTargetSeries` coerces id/name before compare (upstream uses raw `!==`); `_mergeOption` value-copy write-back vs in-place; `visitComponent`/instantiation stubbed → dynamic-option→component pipeline presently inert (PORT-TODO, blocked by scaffolding) |
| `model/OptionManager.swift` | `model/OptionManager.ts` | complete | **major-issues (2)** | see §29 #0d (MEDIA UNITS silently dropped — dynamic bag cast to a foreign `MediaUnit` struct); minor `hasTimeline` malformed-input edge |
| `model/globalDefault.swift` | `model/globalDefault.ts` | complete | faithful | — |
| `model/referHelper.swift`, `model/internalComponentCreator.swift` | `model/{referHelper,internalComponentCreator}.ts` | complete | (foundation sweep) | — |

Roll-up (ported `.ts` mirrors with a review verdict): **majority faithful/foundation-sweep; 3
minor-issues (`Model`, `Component`, `Global`), 2 major-issues (`Series`, `OptionManager`).** The
dynamic option engine (`Model.get`/`mergeOption`) itself pins clean; the major-issues are the
value-vs-reference seam (`Series` passing un-merged option to `getInitialData`) and one real
correctness break (`OptionManager` media drop) — see §29.

---

## 28. Build & test status — Phase 5c (incl. the ported model unit tests)

- **`swift build`: GREEN.** Clean from-scratch build compiled ZRenderKit, NativePainter, EChartsKit,
  and DemoGallery first try; **no source edits to the existing 5a/5b layers were required** — the
  parallel-translated model spine integrated cleanly. `swift build --build-tests`: GREEN. One benign
  non-blocking warning at `Series.swift:582` (conditional downcast `GlobalModel?` → palette-mixin
  equivalent to an implicit optional conversion) left untouched to avoid behavior change.
- **`swift test`: GREEN — 208 executed / 55 skipped / 0 failures** (whole package; up from Phase-5b's
  143/16). Deterministic across repeated runs (ran `componentDependency` 3× + full suite). Model-layer
  tests added this phase: **65 across 6 new files = 26 active (ALL PASS) + 39 skipped.**
- **NEW test files** (all under `Tests/EChartsKitTests/`):
  - `ModelUnitTests.swift` — **15 pass.** The crux (no upstream `Model.test.ts` exists; pins the ported
    dynamic-option engine directly): `get()`/`get(path)`/`get([path])` keyed+dotted access, empty-segment
    skip, parent-model cascade + `ignoreParent`, `getShallow`, `getModel` sub-Model wrapping +
    `resolveParentPath` chain, `mergeOption` deep-merge, `isEmpty`, `clone` independence,
    `isAnimationEnabled` truthiness/inheritance.
  - `UtilModelUnitTests.swift` ← `test/ut/spec/util/model.test.ts` — **4 pass + 1 skip.** `compressBatches`
    (namespace `model`), `removeDuplicates` (resolve1/priority/edges).
  - `ComponentDependencyUnitTests.swift` ← `test/ut/spec/model/componentDependency.test.ts` — **7 pass.**
    `registerClass`/`getAllClassMainTypes`/`topologicalTravel` over fixed file-scope `ComponentModel`
    subclasses (upstream runtime class-gen has no Swift equivalent): base/empty/isolate/diamond/loop
    (Circular throw)/missingSomeNode/subType.
  - `GlobalModelUnitTests.swift` (22 skip), `TimelineMediaOptionsUnitTests.swift` (10 skip),
    `ComponentMissingUnitTests.swift` (6 skip) — every upstream `it` preserved as an `XCTSkip` with reason.
- **Skips (39) with reasons:** `Global.test.ts` (22) + `timelineMediaOptions.test.ts` (10) +
  `componentMissing.test.ts` (6) are all driven through `createChart()`/`init()`+`use()`/resize +
  `getData()`/`getInitialData()` — need the ChartView map + Scheduler + series-data pipeline + real
  component models (Phase 6). `removeDuplicates_no_resolve_has_value` (1): upstream keeps BOTH `undefined`
  and `null` (distinct `+''` keys); Swift collapses both to nil (CONVENTIONS §6) — cannot port faithfully.
- **ONE REAL BUG FOUND AND FIXED** (the only `Sources/` behavior change this phase) — a §3/§4
  value-vs-reference hazard: **`modelUtil.compressBatches` / `makeMap` mutated a value-type copy**
  (`Sources/EChartsKit/util/modelUtil.swift` ~line 992/998). Upstream `makeMap(batchB, mapB, mapA)`
  mutates `otherMap` (a JS reference object) in place via `otherDataIndices[dataIndex] = null` so
  cross-batch duplicates are removed from resultA; the Swift `otherMap` was a plain value parameter, so
  the nulling hit a throwaway copy and cross-batch duplicates were NEVER removed from batchA (failed 5/7
  `compressBatches_base` sub-cases). **Fix:** made `makeMap`'s `otherMap` parameter `inout` (matching
  upstream reference semantics) and pass `&mapA` / an empty `&noOtherMap`. All `compressBatches` cases pass.
- **DOCUMENTED FAITHFULNESS GAP (pre-existing PORT-TODO, not newly introduced):** Swift `Dictionary`
  key-iteration order is unspecified (`clazz.getAllClassMainTypes`, `modelUtil.compressBatches` maps),
  whereas upstream relies on JS object iteration order (integer-like keys ascending; string keys
  insertion-order). Consequence: `compressBatches` item/dataIndex ordering and `topologicalTravel`
  emission order are nondeterministic in the port. The ported tests assert order-normalized content
  (values faithful; only dict-order nondeterminism normalized). Content correctness is fully asserted;
  closing the ordering divergence needs an order-preserving dictionary.

---

## 29. Phase 5c — new open issues & PORT-TODO backlog (deduped, severity-sorted)

### Major — value-vs-reference / real-correctness (review-flagged, fix before Phase 6 wiring relies on them)
0a. **`Series.init` passes the UN-merged option to `getInitialData`** (`Series.swift:210`). TS
   `Series.ts:283-287` merges theme+defaults into `option` IN PLACE (option === `this.option`), so
   `getInitialData(option, ecModel)` receives the fully-merged option. In Swift the option bag is a value
   type: `mergeDefaultAndTheme` merges defaults into `self.option` and writes back there
   (`Series.swift:265-269`), but `Series.swift:210` then calls `getInitialData(option, …)` with the
   original, default-less PARAM. **Consequence:** concrete series whose `getInitialData` reads its
   `option` arg see none of the merged defaults/theme. **Fix:** pass `self.option`.
0b. **`Series.mergeOption` passes only the incremental delta to `getInitialData`** (`Series.swift:303`).
   TS `Series.ts:302` `newSeriesOption = merge(this.option, newSeriesOption, true)` rebinds the local to
   the merged `this.option`; Swift merges into `self.option` (`:288-292`) but does NOT rebind, so `:303`
   passes the raw partial delta. **Consequence:** data rebuilt from an option missing everything not in
   the incremental update. **Fix:** pass the merged `self.option` (`target`).
0c. **`OptionManager` MEDIA UNITS silently dropped** (`OptionManager.swift:390`, unflagged correctness
   break). `parseRawOption` does `util.each(mediaOnRoot as? [MediaUnit])`, but `mediaOnRoot =
   rawOption["media"]` comes from the dynamic `ECUnitOption=[String:Any]` bag and holds `[[String:Any]]`
   dicts, not the typed `MediaUnit` structs (`util/types.swift:1046`); `[[String:Any]] as? [MediaUnit]`
   returns nil, so the loop body never runs → `mediaList`/`mediaDefault` stay empty → `getMediaOption`
   short-circuits and returns `[]`. The sibling timeline `options` path survives only because
   `[ECUnitOption]` is itself `[[String:Any]]`. **Fix:** read media entries dynamically as `[[String:Any]]`
   and access `["option"]`/`["query"]` by key (as the timeline path already does).

### Correctness / fidelity — review-flagged, fix opportunistically
1. **`Series.isAnimationEnabled` threshold default** (`Series.swift:556`): `getShallow("animationThreshold")
   as? Double ?? 0`. When absent, JS `count > undefined` = false (animation stays on); Swift `count > 0` =
   true for non-empty data, wrongly disabling animation. Treat missing threshold as no-cap (Infinity).
2. **`Component` THEME-MERGE un-wired against a now-STALE reason** (`Component.swift:196-211`). Upstream
   `mergeDefaultAndTheme` merges `ecModel.getTheme().get(mainType)` (overwrite=false) BEFORE the default
   (`Component.ts:169-171`); the port skips it (`_ = ecModel`). The PORT-TODO reason ("GlobalModel has no
   getTheme()") is no longer true — `Global.swift:615` defines `getTheme() -> Model`. **Wire to
   `ecModel.getTheme().get(mainType)` merged (overwrite=false) before the default.** Severity reduced
   (not eliminated): new-component init is itself a documented no-op (Global instantiation stubbed), so
   `mergeDefaultAndTheme` is not reached yet; the separate top-level `mergeTheme` (Global.swift:1069) does
   NOT substitute — upstream keeps both mechanisms.
3. **`Model.isAnimationEnabled` non-dict-option parent-recursion** (`Model.swift:244`). Upstream recurses
   into `parentModel` for a truthy non-dict option with no `animation`; the Swift dict-cast gate
   short-circuits to nil. Edge case (option is normally a dict for animatable models).
4. **`Model.getModel` returns a Model over a VALUE-COPY subtree** (`Model.swift:177-191`). Upstream
   `_doGet` returns a reference to the nested option object (mutate-through); Swift extracts a value copy,
   so a child-Model mutation does NOT propagate to the parent tree. Inherent to the `[String:Any]` bag
   modeling; document in header for any mutate-through-getModel pattern.
5. **`Model.clone()` drops the concrete subclass** (`Model.swift:210`, documented PORT-TODO). Upstream
   `new (this.constructor)(clone(option))` preserves the subtype; Swift always returns base `Model`.
6. **`Global.isNotTargetSeries` coerces before comparing** (`Global.swift:1062-1063`). Upstream uses raw
   `!==` (no coercion) on id/name; Swift runs `convertOptionIdName` first, so a numeric `seriesId`/
   `seriesName` in a `restoreData` payload matches a string component id/name in Swift but not upstream.
7. **`Global._mergeOption` value-copy write-back vs in-place** (`Global.swift:342` + `:564`). Upstream
   mutates the shared `this.option` reference throughout the merge; the port operates on a local copy and
   publishes only at the end, and `optionsByMainType.append(componentModel.option)` copies by value.
   Any reentrant read of `ecModel.option` during component init/merge would see the pre-merge snapshot.
   Masked today because component instantiation is stubbed; will surface once registry/init lands.
8. **`OptionManager.hasTimeline` malformed-input edge** (`:362-366`) — `as? [ECUnitOption]` is nil for a
   non-array `options`, whereas upstream uses truthiness; only affects malformed input.

### Dynamic-option-model decisions (design, standing)
- **`Model` is a reference type; dynamic bags are `[String: Any]`; deep-merge routes through `util.merge`
  (null/undefined guard); `Model.get(path)` does keyed/dotted-path access** — the mandated modeling
  (§26b). Two consequences are inherent, not bugs: `getModel` value-copy (#4) and the value-type
  write-back seam (#7) — both flow from `[String:Any]` being a value type rather than a JS reference.
- **Mixins:** TS `mixin()` is realized as Swift protocol + protocol-extension composition
  (`ItemStyleMixin`/`LineStyleMixin`/`AreaStyleMixin`/`TextStyleMixin`/`PaletteMixin`/`DataFormatMixin`),
  getter names kept identical (`getItemStyle`/`getLineStyle`/`getAreaStyle`/`getTextStyle`).

### Stubbed surfaces — whole features deferred to Phase 6 (each is `// PORT-TODO`, faithful signatures)
- **Component/series instantiation from the option tree is INERT.** `Global.visitComponent`
  (`:404-406`) + component-create (`:500-529`, `componentModel = nil`) are stubbed, and
  `normalizeToArray<ComponentOption>` over the dynamic `[String:Any]` bag returns `[]`, so
  `_componentsMap['series']` stays empty and `eachSeries`/`getSeries*`/`reCreateSeriesIndices` operate on
  nothing. The crux dynamic-option → component pipeline is present but presently inert — it lands with
  the registry/`ChartView` map in Phase 6.
- **Genuine Phase-6 deferrals** (faithful-signature PORT-TODO stubs, none weakening merge/get/data
  logic): `coord/CoordinateSystem`, `coord/Axis`, `core/Scheduler`+`task`, `data/helper/sourceManager`,
  `visual/LegendVisualProvider`, tooltip/legend/marker/brush components, `util/layout`, `util/symbol`.

### Does `Series.getInitialData` build a real `SeriesData`?
**Partially — the type wiring is real, the base body is intentionally an override seam.** The §25 #5
data stubs are now consumed via the real types: `Series.getInitialData(_:_:) -> SeriesData?` returns a
real `SeriesData?` (base returns `nil`, faithful to upstream's `return;` meant to be overridden by
concrete series), `Series.init` calls it and asserts non-nil (`Series.swift:213`), and `getData`/
`getRawData` traffic in the real `SeriesData`/`GlobalModel` types (no more minimal-protocol stubs).
**No concrete series (e.g. `BarSeries`) exists yet**, so no real column-building `getInitialData`
override runs end-to-end — that is the first thing Phase 6 lands (the §29 #0a/#0b un-merged-option fixes
must precede it so the override sees merged defaults).

---

## 30. The ECharts model spine is in place — Phase 6 plan (the first real chart: bar vertical → pixels through ZRenderKit)

**Goal:** the first END-TO-END vertical — a hand-built `option` (`{xAxis, yAxis, series:[{type:'bar',
data}]}`) flows through `GlobalModel` → coord/cartesian → `Scheduler`/`Task` (processor/visual/layout) →
`BarView` and renders a REAL bar chart through the complete `ZRenderKit` (`Group`/`Rect`/`Text` +
animation + interaction). This closes the dynamic-option → component pipeline left inert in §29 and
turns the 39 `createChart`-driven skips (§28) green.

### Pre-Phase-6 (do FIRST): resolve the §29 majors + the standing hardening carry-over
- Fix `Series` #0a/#0b (pass the MERGED `self.option` to `getInitialData`) and `OptionManager` #0c
  (read media dynamically) — they are load-bearing the moment a concrete series builds data / a media
  query resolves. Wire `Component` theme-merge #2 (now-unblocked by `getTheme()`).
- Close the `Global` instantiation stub (§29 stubbed surfaces): make `visitComponent` iterate the dynamic
  `[String:Any]` option bag (not `normalizeToArray<ComponentOption>`) and instantiate via the
  `ComponentModel` registry so `_componentsMap`/`eachSeries` are populated.
- The §22 fidelity-hardening carry-over (`util.merge` null-guard, `'key' in obj` vs `!= nil`, `|| 0` vs
  `?? 0`, JS truthiness) is now maximally load-bearing — the option→component→coord path feeds exactly
  these edge values.

### 30a. `coord/cartesian/` — Axis + Scale wiring + `dataToPoint` (`echarts/src/coord/`)
| Upstream file | Swift target | Already-ported deps |
|---|---|---|
| `coord/Axis.ts` | `coord/Axis.swift` | `scale/{Scale,Interval,Ordinal}` (5a), `util/number` |
| `coord/cartesian/Cartesian.ts`, `coord/cartesian/Cartesian2D.ts` | `coord/cartesian/*.swift` | `Axis`, `data/SeriesData` (5b) |
| `coord/cartesian/Axis2D.ts`, `coord/cartesian/AxisModel.ts`, `coord/cartesian/GridModel.ts` | `coord/cartesian/*.swift` | `ComponentModel` (5c — wires the §25 #5 `scale`↔`axisModel` seam) |
| `coord/cartesian/Grid.ts` (`dataToPoint`/`pointToData`, axis layout) | `coord/cartesian/Grid.swift` | `Cartesian2D`, `Axis2D`, `util/layout` (to port) |
| `coord/axisHelper.ts`, `coord/axisTickLabelBuilder.ts` | `coord/*.swift` | `scale` nice-ticks, `util/number` |

### 30b. `Scheduler` + the `Task`/`stream` pipeline (`echarts/src/core/` + `stream/`)
| Upstream file | Swift target | Already-ported deps |
|---|---|---|
| `core/task.ts` | `core/task.swift` | `util` |
| `core/Scheduler.ts` | `core/Scheduler.swift` | `task`, `GlobalModel` (5c), `data/SeriesData` (5b) |
| the per-stage graph: `createData`/`processData`/`visual`/`layout`/`render` | driven via Scheduler | pairs the 5b data engine with the 5c model |

### 30c. `visual/` + `layout/barGrid` (`echarts/src/visual/` + `layout/`)
| Upstream file | Swift target | Already-ported deps |
|---|---|---|
| `visual/style.ts`, `visual/seriesColor.ts`, `visual/VisualMapping.ts` | `visual/*.swift` | `model/mixin/palette` (5c), `data/SeriesData` |
| `layout/barGrid.ts` | `layout/barGrid.swift` | `coord/cartesian/Grid` (30a), `data/SeriesData`, `data/helper/dataStackHelper` (5b) |

### 30d. FIRST `ChartView` = `BarView` + `component/grid` + `component/axis` (`echarts/src/chart/` + `component/`)
| Upstream file | Swift target | Already-ported deps |
|---|---|---|
| `chart/bar/BarSeries.ts` (concrete `getInitialData` → real column build) | `chart/bar/BarSeries.swift` | `SeriesModel` (5c), `data/{SeriesData,helper/createDimensions}` (5b), `Source` |
| `chart/bar/BarView.ts` (`ChartView` → `Group{Rect}` per datum, enter/update/exit + animation) | `chart/bar/BarView.swift` | `ZRenderKit` `Group`/`Rect`/`Path` + animation (Phase 1–3), `DataDiffer` (5b) |
| `view/Chart.ts` (`ChartView` base), `view/Component.ts` | `view/*.swift` | `ZRenderKit` `Group`, `GlobalModel` |
| `component/grid/GridView.ts` | `component/grid/*.swift` | `coord/cartesian/Grid` (30a), `Group`/`Rect` |
| `component/axis/{CartesianAxisView,AxisBuilder}.ts` | `component/axis/*.swift` | `coord/Axis` (30a), `Group`/`Line`/`Text` (Phase 1–2) |
| `core/echarts.ts` (the `ECharts`/`init`/`setOption`/`_update` render driver — minimal slice) | `core/echarts.swift` | `GlobalModel`+`OptionManager` (5c), `Scheduler` (30b), `ZRender` host (Phase 4) |

**Sequencing:** §29 majors + instantiation stub → `coord/cartesian` (Axis+Scale+`dataToPoint`) →
`Scheduler`/`Task` → `visual/`+`layout/barGrid` → `BarSeries`+`BarView`+`grid`+`axis` + the minimal
`echarts.ts` driver. Each stage keeps the §12 upstream-sync rule and ports its matching upstream spec
as the behavioral oracle (turning the §28 `createChart`-driven skips green as `createChart`/`init`/
`getData` become real).

### After Phase 6: the simulator demo shows a REAL echarts-driven chart
Once §30d lands, the `DemoGallery` app can call the minimal `echarts.ts` driver with a real `option`
and render an actual ECharts-computed bar chart (data → scale → coord → layout → `Rect`s) on the
iOS/macOS simulator through `NativePainter` — the first time the full ECharts→ZRenderKit vertical is
visible on screen, not just hand-built `Group` trees.

---

## 31. What landed in Phase 6a — coord/cartesian + core pipeline + Global instantiation wiring

**Phase 6a (the §30 plan, executed up to but excluding the rendering views/orchestrator): COMPLETE.**
This lands the coordinate-system layer (`coord/cartesian` geometry + axis models + the full axis-helper
cluster + the REAL `scaleRawExtentInfo` replacing the §22 minimal stub), the core scheduling pipeline
(`Scheduler`/`task` + `CoordinateSystemManager` + `ExtensionAPI`), and closes the §29 **component/series
instantiation stub** in `GlobalModel` — so a hand-built bar-chart option now materializes real
`GridModel`/`CartesianAxisModel`/bar `SeriesModel` objects and `Cartesian2D.dataToPoint` maps data →
pixels. The rendering half (BarView/GridView/CartesianAxisView + the slim `echarts.ts` driver) is Phase
6b (§34). Six scout tiers landed as one integrated unit against the existing 5a/5b/5c layers.

### Coord — leaf helpers + coordinate-system interface (`Sources/EChartsKit/coord/`)
- [x] `coord/axisDefault.swift` ← `coord/axisDefault.ts` — per-axis-type default option.
- [x] `coord/axisStatistics.swift` + `coord/axisStatisticsMetricsImpl.swift` ←
      `coord/axisTickLabelBuilder`-adjacent metrics — tick/label statistics over the real `Axis`.
- [x] `coord/CoordinateSystem.swift` ← `coord/CoordinateSystem.ts` — `CoordinateSystem`/
      `CoordinateSystemMaster` protocols (`AnyObject`), `dataToPoint`/`pointToData`/`getViewRect`
      surface + `isGeoLikeCoordSys`.
- [x] `coord/axisModelCommonMixin.swift` ← `coord/axisModelCommonMixin.ts` — the axis-model mixin
      (`getCoordSysModel`, `axis`/`option` requirements).

### Coord — axis base + helper cluster + REAL scaleRawExtentInfo (landed as one unit)
- [x] `coord/Axis.swift` ← `coord/Axis.ts` — the `open class Axis`: `dataToCoord`/`coordToData`
      (`linearMap`), band layout (`getBandWidth`/`makeExtentWithBands`), `getTicksCoords`/
      `getMinorTicksCoords`/`fixOnBandTicksCoords`, `getExtent` copy semantics.
- [x] `coord/AxisBaseModel.swift` ← `coord/AxisBaseModel.ts` — axis-model base (`getCategories`,
      `axis`, scale/extent option surface).
- [x] `coord/axisHelper.swift` ← `coord/axisHelper.ts` — `createScaleByModel`/`niceScaleExtent`/
      `getAxisRawValue`/`makeLabelFormatter`/`getFormattedLabel`.
- [x] `coord/axisNiceTicks.swift` ← `coord/axisNiceTicks.ts` (extracted) — `scaleCalcNice`/
      `scaleCalcNice2`/`calcNiceForIntervalOrLogScale` + `adoptScaleExtentKindMapping`.
- [x] `coord/axisAlignTicks.swift` ← `coord/axisAlignTicks.ts` — multi-axis tick alignment.
- [x] `coord/axisBand.swift` ← axis-band layout helpers.
- [x] `coord/axisTickLabelBuilder.swift` ← `coord/axisTickLabelBuilder.ts` — `createAxisTicks`/
      `createAxisLabels`/`calculateCategoryInterval` (`AxisTicksCreated`/`AxisCategoryTicksCreated`).
- [x] `coord/scaleRawExtentInfo.swift` ← `coord/scaleRawExtentInfo.ts` — **THE REAL ONE** (replaces the
      §22 minimal PORT-TODO stub): `ScaleRawExtentInfo` (min/max/`fixMin`/`fixMax` resolution,
      `calculate`/`freeze`/`ensureScaleRawExtentInfo`, `parseAxisModelMinMax`).
- [x] `coord/axisModelCreator.swift` ← `coord/axisModelCreator.ts` — `axisModelCreator` factory +
      the base `AxisModel` (with `getCategories` override). `axisAction`/`axisBreakHelper` stubbed
      (`getAxisBreakHelper()->null`, PORT-TODO 6b).

### Coord — cartesian (`Sources/EChartsKit/coord/cartesian/`)
- [x] `Cartesian.swift` ← `coord/cartesian/Cartesian.ts` — generic N-axis container (`addAxis`/
      `getAxis`/`getAxes`).
- [x] `Cartesian2D.swift` ← `coord/cartesian/Cartesian2D.ts` — `dataToPoint`/`pointToData`/
      `dataToPoints`/`getOtherAxis`/`getArea`, `toGlobalCoord` wiring.
- [x] `Axis2D.swift` ← `coord/cartesian/Axis2D.ts` — cartesian axis (`getGlobalExtent`/`isHorizontal`/
      `toGlobalCoord`/`toLocalCoord`/`setCategorySortInfo`).
- [x] `AxisModel.swift` ← `coord/cartesian/AxisModel.ts` — `CartesianAxisModel` (now **subclasses
      `AxisBaseModel`** so it satisfies `Axis.model`); `getCoordSysModel` via `SINGLE_REFERRING`.
- [x] `GridModel.swift` ← `coord/cartesian/GridModel.ts` — grid component model + defaultOption.
- [x] `cartesianAxisHelper.swift` ← `coord/cartesian/cartesianAxisHelper.ts` — `layout`/
      `findAxisModels`/`rotateTextRect`.
- [x] `defaultAxisExtentFromData.swift` ← `coord/cartesian/defaultAxisExtentFromData.ts`.
- [~] `Grid.swift` ← `coord/cartesian/Grid.ts` — **PARTIAL**: `create`/`update`/`resize`/`_updateScale`/
      `getCartesian`/`convertToPixel`/`convertFromPixel`/`getTooltipAxes` ported and exercised;
      `createOrUpdateAxesView` is a documented no-op stub (needs `AxisBuilder`, 6b).

### Core — scheduling pipeline + API (`Sources/EChartsKit/core/`)
- [x] `core/task.swift` ← `core/task.ts` — `Task`/`createTask`, `TaskPlanCallback`/reset/progress,
      pipe-chaining.
- [x] `core/Scheduler.swift` ← `core/Scheduler.ts` — the stage graph (`getPipeline`/`updateStreamModes`/
      `performDataProcessorTasks`/`performVisualTasks`/`prepareStageTasks`).
- [x] `core/CoordinateSystemManager.swift` ← `core/CoordinateSystem.ts` — `CoordinateSystemManager`
      (register/get, `create`/`update` ordering, `getCoordinateSystems`).
- [x] `core/ExtensionAPI.swift` ← `core/ExtensionAPI.ts` — the `ExtensionAPI` forwarding surface
      (`getWidth`/`getHeight` faithful-signature PORT-TODO members for the layout-reference path).

### Support ports pulled in on demand (`Sources/EChartsKit/util/`)
- [x] `util/vendor.swift` ← `util/vendor.ts` — `TypedArrayCtor`/`CompatibleTypedArray`/
      `createFloat32Array` (consumed by axis statistics).
- [~] `util/layout.swift` ← `util/layout.ts` — **PARTIAL**: full `getLayoutRect` (2 overloads) +
      `createBoxLayoutReference` (viewport branch); the `boxCoordinateSystem` branch is a 6b PORT-TODO.

### Global instantiation wiring (`Sources/EChartsKit/model/Global.swift`)
- [~] **`GlobalModel` now instantiates REAL component/series models** — the §29 "inert" stub is CLOSED.
      `visitComponent`/component-create iterate the dynamic `[String:Any]` option bag and instantiate via
      the `ComponentModel` registry; `getComponent`/`queryComponents` return real objects. Marked
      **partial** because three downstream stubs (see §33) still block the full data pipeline.

### Phase 6a — per-file status & review verdict
| File | Source `.ts` | Status | Verdict | Note |
|---|---|---|---|---|
| `coord/CoordinateSystem.swift` | `coord/CoordinateSystem.ts` | complete | minor-issues (3) | `isGeoLikeCoordSys` unguarded `dimensions[0]` subscript TRAPS on empty dims (TS short-circuits false); `getViewRect() != nil` tests RETURN not method-EXISTENCE; `GeoLikeCoordSys.getViewRect` mandatoriness not enforced (default supplies it) |
| `coord/Axis.swift` | `coord/Axis.ts` | complete | minor-issues (2) | `splitNumber`/threshold read via `as? Double` drops Int-boxed options → nan/default; `pointToData` base returns `.nan` vs TS `undefined`. Core math (dataToCoord/band margin/fixOnBandTicks) faithful |
| `coord/axisHelper.swift` | `coord/axisHelper.ts` | complete | minor-issues (3) | `util.isFunction`==false ⇒ functional `axisLabel.formatter` DEAD CODE (falls to default label); string-formatter `{value}` replaces ALL not first; `idx ?? 0`/`?? nan` fallback changes callback arg |
| `coord/axisNiceTicks.swift` | `coord/axisNiceTicks.ts` | complete | minor-issues (3) | empty `fixMinMax` OOB-index crash via public `scaleCalcNiceDirectly` (TS tolerant); Int-boxed `interval`/`splitNumber` silently dropped; `model.axis as? Axis` can no-op extent-kind adoption if `axis` isn't a real `Axis` |
| `coord/scaleRawExtentInfo.swift` | `coord/scaleRawExtentInfo.ts` | complete | (real port; foundation) | replaces the §22 stub; `fixMM` always `[false,false]` on the internal path so the axisNiceTicks OOB is external-caller-only |
| `coord/axisTickLabelBuilder.swift` | `coord/axisTickLabelBuilder.ts` | complete | (foundation) | `AxisTicksCreated`/`AxisCategoryTicksCreated` made public |
| `coord/axisAlignTicks.swift`, `axisBand.swift`, `axisModelCommonMixin.swift`, `AxisBaseModel.swift`, `axisDefault.swift`, `axisStatistics.swift`, `axisStatisticsMetricsImpl.swift`, `axisModelCreator.swift` | matching `.ts` | complete | (foundation) | `getCategories` moved to `AxisBaseModel` base (dynamic dispatch); `getFilter?()` optional-closure guard |
| `core/CoordinateSystemManager.swift` | `core/CoordinateSystem.ts` | complete | minor-issues (2) | dropped DEV `assert(!master.update)`; `update()` called unconditionally (safe: no-op default). create/update ordering faithful |
| `coord/cartesian/Cartesian.swift` | `coord/cartesian/Cartesian.ts` | complete | faithful | `getAxis` returns Optional (more honest than TS non-optional); force-unwraps safe under `addAxis` invariant |
| `coord/cartesian/AxisModel.swift` | `coord/cartesian/AxisModel.ts` | complete | minor-issues (2) | `getCoordSysModel().models[0]` unguarded subscript TRAPS when no grid (TS yields `undefined` → descriptive throw); `getCoordSysModel` static-dispatch via extension-default (not protocol requirement) — correct today via concrete types |
| `coord/cartesian/Axis2D.swift` | `coord/cartesian/Axis2D.ts` | complete | minor-issues (3) | `setCategorySortInfo` returns `true` vs TS implicit `undefined`; option write-back guarded (skips if not `[String:Any]`); `?? "value"`/`?? "bottom"` vs `||` on empty string |
| `coord/cartesian/Cartesian2D.swift`, `Axis2D` deps, `GridModel.swift`, `cartesianAxisHelper.swift`, `defaultAxisExtentFromData.swift` | matching `.ts` | complete | (foundation) | `dataToPoint`/`toGlobalCoord` pipeline exercised by the pixel oracle (§32) |
| `coord/cartesian/Grid.swift` | `coord/cartesian/Grid.ts` | **partial** | minor-issues | `createOrUpdateAxesView` no-op stub (AxisBuilder, 6b); `getBoxLayoutParams`/layout feed empty so grid rect fills container (§33) |
| `core/task.swift`, `core/Scheduler.swift`, `core/ExtensionAPI.swift` | matching `.ts` | complete | (foundation) | `ExtensionAPI.getWidth`/`getHeight` real forwarding = 6b PORT-TODO |
| `util/vendor.swift` | `util/vendor.ts` | complete | (support) | NEW |
| `util/layout.swift` | `util/layout.ts` | **partial** | (support) | `getLayoutRect` full; `createBoxLayoutReference` viewport-only, boxCoordinateSystem = 6b |
| `model/Global.swift` | `model/Global.ts` | **partial** | (instantiation wired) | component/series instantiation now live; blocked downstream by §33 stubs |

Roll-up: **coord/core geometry + scale/extent math faithful; the review-flagged issues are (a) a
cluster of Swift-traps-where-TS-tolerates on unguarded array subscripts (`isGeoLikeCoordSys` dims,
`getCoordSysModel().models[0]`), (b) the project-wide `as? Double` Int-boxing drop hitting axis
`splitNumber`/`interval`, and (c) `util.isFunction`==false making functional label-formatters dead
code.** None weaken the ported scale/axis-extent MATH; all are logged below.

---

## 32. Build & test status — Phase 6a (incl. the coord dataToPoint oracle + instantiation test)

- **`swift build`: GREEN.** The coord/cartesian + pipeline + Global instantiation were translated in
  parallel against the OLD §22 PORT-TODO stubs; integration reconciled the collisions with **minimal,
  faithful edits (no scale/axis-extent math weakened)** — see the integration log below.
- **`swift test`: GREEN — 212 executed / 155 passed / 0 failures / 57 skipped** (whole package; up from
  Phase-5c's 208/55). The new `CartesianCoordTests.swift` adds 4 (2 pass + 2 skip); **no pre-existing
  test regressed.**
- **NEW test file** `Tests/EChartsKitTests/CartesianCoordTests.swift` (4 tests):
  - **`testComponentInstantiationReturnsRealModels` — PASS.** Builds a `GlobalModel` from a minimal
    bar-chart option and asserts `getComponent("grid")` is a real `GridModel`, `getComponent("xAxis"/
    "yAxis")` are real `CartesianAxisModel`, and `eachSeries`/`getSeriesByType("bar")` return a real bar
    `SeriesModel` — **proving the §29 instantiation stub is closed and no longer inert.**
  - **`testDataToPointOracleAndInverse` — PASS.** Runs `Grid.create` with a fixed 400×300 `ExtensionAPI`,
    gets `Cartesian2D` (x0,y0), and asserts `dataToPoint` maps known (categoryIndex, value) → expected
    pixels, cross-checked against an independent `number.linearMap` re-derivation (grid fills the full
    400×300 container; X(rank)=rank/3·400, Y(v)=300−3v; ordinal N=4 onBand=false, value scale [0,100]),
    plus bounds checks and `pointToData` inverting `dataToPoint`.
  - `test_api_converter_cartesian`, `test_api_containPixel_cartesian` (ported upstream specs) — **SKIP**
    (need `createChart`/orchestrator + ChartView map + Scheduler = Phase 6b; the underlying
    `Grid.convertToPixel`/`convertFromPixel` + `Cartesian2D.dataToPoint` ARE ported and exercised by the
    oracle).
- **INTEGRATION LOG — minimal faithful edits to make the parallel work build (no math weakened):**
  removed obsolete §22 placeholder `Axis`/`AxisModelForAxisStat` protocols in `axisStatistics.swift`
  (source of the "`Axis` is ambiguous" clash) and rewired to the real `Axis`; NEW `util/vendor.swift` +
  `util/layout.swift`; `getFilter?()` optional-closure guard; reconciled `Axis.getTicksCoords` to the real
  `axisTickLabelBuilder` API; made `AxisTicksCreated`/`AxisCategoryTicksCreated` public; moved the base
  `getCategories` onto `AxisBaseModel` (dynamic dispatch); `CartesianAxisModel` now subclasses
  `AxisBaseModel`; `scaleCalcNice2` axis param `Any?`→`Axis?`; `Grid.createOrUpdateAxesView` `kind` param
  → `Double`; various `.model` → `.model!` IUO-bind fixups.
- **The oracle/data pipeline is reachable only through THREE documented TEST-SIDE workarounds**, each
  mapping to a real §33 Sources bug (NOT papered over, confined to private test doubles): (B1) probe series
  feeds an empty DataStore to dodge the `isFunction` assert; (B2) probe axis models override
  `getCoordSysModel` to resolve the grid via `ecModel.getComponent` (bypass the `queryReferringComponents`
  crash); (B3) ordinal scale extent set by hand to stand in for the blocked data-collection stage.

---

## 33. Phase 6a — new open issues & PORT-TODO backlog (deduped, blockers first)

### CRITICAL — real bugs the test doubles work around (fix FIRST in Phase 6b pre-work)
1. **`queryReferringComponents` still stubbed to always return `models: []`** (`util/modelUtil.swift:
   1256-1298`, both branches). Its PORT-TODO reason (GlobalModel has no `getComponent`/`queryComponents`)
   is now STALE — both exist (`Global.swift:665`/`:686`). Consequence: `CartesianAxisModel.getCoordSysModel()`
   (`AxisModel.swift:93`) does `.models[0]` → **index-out-of-range CRASH**, which crashes the entire
   `Grid.create`/cartesian pipeline via `isAxisUsedInTheGrid` (`Grid.swift:719`). **Primary blocker**; the
   test must override `getCoordSysModel` (workaround B2). **Fix:** implement `queryReferringComponents` over
   the now-real `getComponent`/`queryComponents`; also change `.models[0]` → `.models.first` (mirror TS
   `undefined` → the ported descriptive throw at `Grid.swift:679-684`).
2. **`util.isFunction` still hardcoded `false`** (ZRenderKit `Core/util.swift:304`, stub). Because
   `__DEV__` is hardcoded `true` (`util/log.swift:33`), `DataStore.initData` (`data/DataStore.swift:
   227-231`) asserts `isFunction(provider.getItem) && isFunction(provider.count)` and **ALWAYS
   fatalErrors "Invalid data provider."** ⇒ a `DefaultDataProvider` can never init a `DataStore` in a
   `__DEV__`/test build, making the whole `getInitialData`→`Source`→`DataStore` series-data pipeline
   unreachable (workaround B1). Also breaks the `axisHelper` functional-formatter branch (§31 verdict).
   **Fix:** port a real `isFunction` (`typeof x === 'function'` → Swift closure/`is` check).
3. **`OrdinalMeta.createByAxisModel` ignores its `axisModel` argument** (`data/OrdinalMeta.swift:90`,
   `_ = axisModel; let option: [String:Any] = [:]`). Its PORT-TODO reason (Model has no `.option`) is
   STALE. Consequence: a category axis NEVER collects categories from `xAxis.data`; `categories` stays
   nil, `needCollect` always true, `OrdinalScale.count()` is wrong ⇒ category `dataToPoint` is NaN out of
   the box (workaround B3). **Fix:** read `axisModel.get("data")`/`.option`.
4. **`ComponentModel.getBoxLayoutParams` returns an empty `BoxLayoutOptionMixin()`**
   (`model/Component.swift:349`). Its PORT-TODO reason (util/layout not ported) is STALE — `util/layout.
   swift` now exists and Grid consumes it. Consequence: `grid.left/right/top/bottom/width/height` are never
   read into layout, so `getLayoutRect` sees an empty position bag and the **grid rect ALWAYS fills the
   whole container** regardless of the option (and the `GridModel.defaultOption` left-15% etc. is never
   applied). **Fix:** read the box-layout keys off the model option.

### Correctness / fidelity — review-flagged, fix opportunistically (see §31 verdict table for the full set)
5. **Swift-traps-where-TS-tolerates on unguarded array subscripts:** `isGeoLikeCoordSys`
   `dimensions[0]` (`CoordinateSystem.swift:386`) on empty dims (parallel-style dimensionless coord
   systems are a documented reachable case); `getCoordSysModel().models[0]` (dup of #1). Bounds-guard
   both to mirror JS `undefined`.
6. **Project-wide `as? Double` drops Int-boxed options.** Axis `splitNumber`/`interval`/`minInterval`/
   `maxInterval` (`axisNiceTicks.swift:309-312`, `Axis.swift:280`) read via `model.get(...) as? Double`;
   an Int literal in the `[String:Any]` bag yields nil ⇒ user override silently ignored / default used.
   Only bites if option ingestion does not normalize numerics to Double — flag for the ingestion path.
7. **`util.isFunction`==false makes functional `axisLabel.formatter` dead code** (dup of #2 downstream)
   and the string-formatter `{value}` replaces ALL occurrences not just the first (`axisHelper.swift:241`).
8. **`isGeoLikeCoordSys` `getViewRect() != nil` tests RETURN value, not method existence** (TS `!!coordSys.
   getViewRect`) — a geo coord system with a transiently-nil view rect is misclassified. Documented PORT-TODO.
9. **`Axis2D.setCategorySortInfo` returns `true`** where TS implicitly returns `undefined` (falsy); only
   caller discards it. **`Axis2D` constructor defaulting** `?? "value"`/`?? "bottom"` diverges from TS `||`
   on empty string (unrealistic input).

### Deferred → Phase 6b (faithful-signature PORT-TODO stubs; none exercised by the 212 tests)
- **`core/echarts.ts` orchestrator** — the full ~125KB `ECharts`/`init`/`setOption`/`_update` driver; a
  SLIM driver comes in 6b (§34).
- **Rendering views** — `chart/*` (BarView etc.), `component/grid` `GridView`, `component/axis`
  `CartesianAxisView` + `AxisBuilder`/`AxisBuilderSharedContext`. `Grid`/`Axis2D`/`cartesianAxisHelper`
  reference `AxisBuilder` as PORT-TODO stubs; `Grid.createOrUpdateAxesView` is a documented no-op.
- **`component/axis/axisAction.ts` + `axisBreakHelper.ts`** — referenced by `axisModelCreator`; stubbed
  (`getAxisBreakHelper()->null`).
- **`util/layout` `createBoxLayoutReference` boxCoordinateSystem branch; `ExtensionAPI.getWidth/getHeight`
  real forwarding.**
- **`core/lifecycle.ts`, `core/locale.ts`, `core/impl.ts`, `core/ExtendedElement.ts`** — 6b orchestration.
- **Other coordinate systems:** polar, geo, single, radar, calendar, parallel, matrix, `coord/View.ts`;
  and `coord/cartesian/legacyContainLabel.ts` + `prepareCustom.ts` (out of scope); dataZoom/axisPointer/brush.

### Does `GlobalModel` now instantiate real component/series models?
**YES — the §29 stub is CLOSED (proven by `testComponentInstantiationReturnsRealModels`, §32).** From a
minimal bar-chart option, `GlobalModel` builds real `GridModel`, `CartesianAxisModel` (x/y), and a bar
`SeriesModel`; `getComponent`/`queryComponents`/`eachSeries`/`getSeriesByType` all operate on real
objects. **Caveat:** the pipeline BEYOND instantiation (grid resolution + series-data build) is blocked by
the four §33 CRITICAL stubs (`queryReferringComponents`, `isFunction`, `OrdinalMeta.createByAxisModel`,
`getBoxLayoutParams`) — the test uses private doubles to reach `dataToPoint`; closing those four is the
pre-work for Phase 6b.

---

## 34. Coord + pipeline are in place — Phase 6b plan (the rendering vertical: a REAL bar chart on screen)

**Goal:** finish the §30 vertical — after the §33 CRITICAL pre-work, a hand-built `option`
(`{xAxis, yAxis, series:[{type:'bar', data}]}`) flows through `GlobalModel` → coord/cartesian →
`Scheduler` → `visual`/`layout` → `BarView` and renders a REAL bar chart through the complete
`ZRenderKit` (`Group`/`Rect`/`Text` + animation + interaction) on the iOS/macOS simulator via
`NativePainter`. This turns the §28/§32 `createChart`-driven skips green.

### Pre-6b (do FIRST): close the four §33 CRITICAL stubs
`queryReferringComponents` (real impl over `getComponent`/`queryComponents` + `.models.first`),
`util.isFunction` (real closure check), `OrdinalMeta.createByAxisModel` (read `axisModel` data), and
`ComponentModel.getBoxLayoutParams` (read box-layout keys). Each removes a private test double and a real
divergence. Carry the §30 majors/hardening only if still open.

### 34a. Slim `ECharts` orchestrator (`echarts/src/core/echarts.ts` — documented subset)
| Upstream file | Swift target | Already-ported deps |
|---|---|---|
| `core/echarts.ts` (the `init`/`setOption`/`update` cycle — a SLIM hand-driven slice, not the full ~125KB driver; each ported/omitted method flagged) | `core/echarts.swift` | `GlobalModel`+`OptionManager` (5c), `Scheduler`+`CoordinateSystemManager` (6a), `ExtensionAPI` (6a), `ZRender` host (Phase 4) |

### 34b. `visual/` (style/color) + `layout/barGrid`
| Upstream file | Swift target | Already-ported deps |
|---|---|---|
| `visual/style.ts`, `visual/seriesColor.ts`, `visual/VisualMapping.ts` | `visual/*.swift` | `model/mixin/palette` (5c), `data/SeriesData` (5b) |
| `layout/barGrid.ts` | `layout/barGrid.swift` | `coord/cartesian/Grid` (6a), `data/SeriesData`, `data/helper/dataStackHelper` (5b) |

### 34c. FIRST `ChartView` = `BarSeries` + `BarView` + `component/grid`(GridView) + `component/axis`(CartesianAxisView)
| Upstream file | Swift target | Already-ported deps |
|---|---|---|
| `chart/bar/BarSeries.ts` (concrete `getInitialData` → real column build) | `chart/bar/BarSeries.swift` | `SeriesModel` (5c), `data/{SeriesData,helper/createDimensions}` (5b), `Source` |
| `chart/bar/BarView.ts` (`ChartView` → `Group{Rect}` per datum, enter/update/exit + animation) | `chart/bar/BarView.swift` | `ZRenderKit` `Group`/`Rect`/`Path` + animation (Phase 1–3), `DataDiffer` (5b) |
| `view/Chart.ts` (`ChartView` base), `view/Component.ts` | `view/*.swift` | `ZRenderKit` `Group`, `GlobalModel` |
| `component/grid/GridView.ts` | `component/grid/*.swift` | `coord/cartesian/Grid` (6a), `Group`/`Rect` |
| `component/axis/{AxisBuilder,CartesianAxisView}.ts` (unstub the 6a `createOrUpdateAxesView` / `AxisBuilder` seams) | `component/axis/*.swift` | `coord/Axis`/`Axis2D` (6a), `Group`/`Line`/`Text` (Phase 1–2) |

**Sequencing:** §33 CRITICAL pre-work → slim `echarts.ts` driver → `visual/`+`layout/barGrid` →
`BarSeries`+`BarView`+`GridView`+`CartesianAxisView` (unstubbing the 6a `AxisBuilder` seams). Each stage
keeps the §12 upstream-sync rule and ports its matching upstream spec as the behavioral oracle (turning
the `createChart`-driven skips green as `createChart`/`init`/`getData` become real).

---

## 35. What landed in Phase 6b — the rendering vertical (a REAL bar chart end-to-end): COMPLETE

**Phase 6b (the §34 plan): COMPLETE — `swift build` GREEN (0 warnings, clean `rm -rf .build`),
`swift test` 215 executed / 0 failures / 58 skipped (was 212; +3 real 6b tests, no regression).**
An `option` `{grid, xAxis:category, yAxis:value, series:[{type:'bar', data}]}` now flows
`GlobalModel` → coord/cartesian → visual → layout → `BarView` and emits four bar `Rect`s in the
`ZRenderKit` scene graph, within the grid rect, heights monotonic with the data, palette fills —
asserted by `Tests/EChartsKitTests/BarChartRenderTests.testBarChartRendersFourBars` (which also
exercises `NativePainter.renderToImage`).

### 35a. New files
- **`core/EChartsSlim.swift`** — DELIBERATELY MINIMAL subset of `core/echarts.ts` (NOT the ~3400-line
  driver). Owns a `Storage` + root `Group`; `setOption` builds `GlobalModel` via `OptionManager`, then
  `update()` runs the faithful stage ORDER of `updateMethods.update` with minimal bodies (restoreData →
  performSeriesTasks(dataTaskReset) → coordSysMgr.create → axis-statistics processor → coordSysMgr.update
  → visual → layout → render). The `Scheduler` task graph, media/actions/lifecycle/states are documented
  PORT-TODO skips. Registration is explicit (`installOnce`) with `SlimXAxisModel`/`SlimYAxisModel`
  stand-ins for the runtime-generated `axisModelCreator` classes, and `()->View` factories (Swift can't
  `new` a bare metatype).
- **View bases:** `view/Chart.swift` (`ChartView`), `view/ComponentView.swift` (`ComponentView`),
  `chart/helper/createRenderPlanner.swift` (the incremental/large render planner).
- **Visual:** `visual/style.swift` (`seriesStyleTask` + `dataColorPaletteTask`: palette + series/data style).
- **Layout:** `layout/barGrid.swift` (cross-series `calcBarWidthAndOffset` + progressive layout),
  `layout/barCommon.swift` (per-item bar layout math).
- **Bar series + view:** `chart/bar/{BaseBarSeries,BarSeries}.swift`, `chart/bar/BarView.swift`
  (`ChartView` → `Group{Rect}` per datum, `data.diff` enter/update/leave + animation), helpers
  `chart/helper/{createSeriesData,createClipPathFromCoordSys}.swift`.
- **Axis + grid views:** `component/axis/{AxisView,CartesianAxisView}.swift` +
  `component/axis/AxisBuilder.swift` (axis line/tick/label/name builder — **partial**),
  `component/grid/installSimple.swift` (grid + axis registration; unstubs the 6a
  `createOrUpdateAxesView`/`AxisBuilder` seams).

### Per-file status & review verdict (Phase 6b)
| File | Source `.ts` | Status | Verdict | Note |
|---|---|---|---|---|
| `core/EChartsSlim.swift` | `core/echarts.ts` (subset) | **partial** | (slim driver by design) | faithful stage ORDER; Scheduler/media/actions/lifecycle/states are documented skips |
| `view/Chart.swift` | `view/Chart.ts` | complete | minor-issues (2) | `eachRendered` uses `Group.traverse` (children only) — upstream `traverseElements` also visits the root group; `context.payload!`/`ecModel!`/`api!` force-unwraps in render tasks trap on a nil payload (TS tolerates undefined) |
| `view/ComponentView.swift` | `view/Component.ts` | complete | faithful | base only |
| `chart/helper/createRenderPlanner.swift` | `chart/helper/createRenderPlanner.ts` | complete | faithful | |
| `visual/style.swift` | `visual/style.ts` | complete | minor-issues (3) | palette-rotation skips filtered points (no global `colorFromPalette` fallback) so `colorBy:'data'` would shift after filtering; `== nil` vs JS-falsy on empty-string/0 color; optional key removed vs `undefined`. All out of bar-only scope (bars are `isColorBySeries()`) |
| `layout/barCommon.swift` | `layout/barGrid.ts` (item half) | complete | faithful | |
| `layout/barGrid.swift` | `layout/barGrid.ts` | complete | major → **FIXED** | the NaN-vs-JS-truthiness bar-width poisoning (`barWidth`/`barMaxWidth`/`barMinWidth`) is fixed via `barGridTruthy` (0/NaN → false); default no-`barWidth` chart now yields finite widths |
| `chart/helper/createSeriesData.swift` | `chart/helper/createSeriesData.ts` | complete | faithful | |
| `chart/helper/createClipPathFromCoordSys.swift` | `chart/helper/createClipPathFromCoordSys.ts` | complete | faithful | cartesian branch; polar `createPolarClipPath` deferred |
| `chart/bar/BaseBarSeries.swift` | `chart/bar/BaseBarSeries.ts` | complete | faithful | `getInitialData`/`defaultOption`/`getMarkerPosition` match upstream incl. JS-truthiness quirks |
| `chart/bar/BarSeries.swift` | `chart/bar/BarSeries.ts` | complete | faithful | |
| `chart/bar/BarView.swift` | `chart/bar/BarView.ts` | complete | major (1 OPEN) | **update-diff branch does NOT clip `layout` in place** — it clips a throwaway `clipLayout` then feeds the UNCLIPPED `layout` to `updateStyle`/`setShape`/`updateProps`, so a partially-overflowing bar renders unclamped on any steady-state (oldData) render. The add branch is correct; only fully-clipped bars are still handled. The render test exercises only the add path, so first-render bars are correct (§35c) |
| `component/axis/AxisView.swift` | `component/axis/AxisView.ts` | complete | faithful | base |
| `component/axis/AxisBuilder.swift` | `component/axis/AxisBuilder.ts` | **partial** | major (OPEN) | `axisTick`/`minorTick` `length` and `nameGap` read via `... as? Double` but their defaults are **Int** literals → cast fails → ticks collapse to zero length (invisible) and axis name gets 0 gap. Same Int-boxing class as §33 #6. Not caught by the render test (asserts bars only). Label/name overlap-nudge is a no-op stub |
| `component/axis/CartesianAxisView.swift` | `component/axis/CartesianAxisView.ts` | complete | faithful | drives `AxisBuilder`; splitLine/splitArea deferred |
| `component/grid/installSimple.swift` | `component/grid/install.ts` (subset) | complete | faithful | grid + axis registration |

Roll-up: **13 complete, 3 partial; 2 major FIXED-or-OPEN (barGrid width FIXED; BarView update-path clip
OPEN), 1 major OPEN in AxisBuilder (Int-boxed tick/name lengths); the rest faithful/minor.**

### 35b. Key bug found & fixed during closeout — `SeriesModel.getBaseAxis()` `Any?` conversion
The workflow was killed (session abort) before its Verify/Synthesize stages, leaving one real defect the
end-to-end test caught: **bars had `x`/`width` = NaN** (y/height were correct). Root cause chain:
`layout/barGrid` reads `data.getLayout("size"/"offset")` (→ NaN default) which the **cross-series bar
layout** (`createCrossSeriesLayoutHandler`) only writes for axes collected under the bar `AxisStatKey`.
Collection happens in `associateSeriesWithAxis` (`axisStatistics.swift`), gated by
`isBaseAxis = seriesModel.getBaseAxis() === axis`. **`SeriesModel.getBaseAxis()` (returns `Any?`) returned
`nil`**: `Cartesian2D` has a concrete `getBaseAxis(): Axis2D`, but its superprotocol `CoordinateSystem`
declares `getBaseAxis(): Axis?` WITH a nil-returning default (`CoordinateSystem.swift:316`). In an untyped
`Any?`-return position, Swift overload resolution prefers the protocol's `-> Axis?` member (its optional
result matches the `Any?` context) over the concrete `-> Axis2D`, so a direct `return coordSys.getBaseAxis()`
bound the DEFAULT → nil. **Fix** (`model/Series.swift:490+`): narrow to concrete `Cartesian2D`, then bind
the result to an explicit `let baseAxis: Axis2D` local (pins resolution to the concrete method) before
returning. With that, `isBaseAxis` is true for the category axis → statistics collect the series →
`size`/`offset` are set → bar geometry is finite. (NOT a compiler miscompile — an overload-resolution trap;
empirically confirmed by clean-build A/B on the direct vs. typed-local return.)

**Process note:** this bug was obscured for most of the investigation by STALE build artifacts — leftover
`PORTDIAG_*` diagnostic globals (added mid-debug, then removed from the source) left probe test files that
failed to compile, so `swift test` silently ran cached binaries. A `rm -rf .build` + removing the probe
tests was required to see the true (passing) state. Lesson for future closeouts: on contradictory probe
output, clean-build before trusting anything.

### 35c. Build + test status — DOES A BAR CHART RENDER?
- **`swift build`: GREEN** (clean `rm -rf .build`, 0 warnings, all targets).
- **`swift test`: 215 executed / 157 passed / 0 failures / 58 skipped** (was 212 in 6a; +3 new 6b tests, no
  regression). The 58 skips are the 57 pre-existing intentional gaps + 1 new `getVisual` skip.
- **End-to-end render test — `Tests/EChartsKitTests/BarChartRenderTests.testBarChartRendersFourBars`: PASS**
  (re-run and confirmed green this closeout, 0.003 s). **YES — a real ECharts bar `option` renders 4 bars
  through `ZRenderKit.`** Its 6 assertions all hold: (1) exactly 4 bar `Rect` elements (name `item`) in the
  root `Group`; (2) every bar rect lies within the injected `Cartesian2D.getArea()` (`{50,20,300,200}`);
  (3) bar x increases left→right (61.6/136.6/211.6/286.6); (4) `|height|` monotonic with data
  (50/100/150/200); (5) fills are REAL palette colors (`#5070dd`, not the `#000` default); (6)
  `CALayerPainter.renderToImage` returns a non-nil 400×300 `CGImage`. Plus 1 `XCTSkip`
  (`test_api_getVisual_barColorFromPalette`, needs `createChart`) and `EChartsSlimSmokeTests` (drives the
  slim update cycle; prints rects=0 because it uses an empty-DataStore double).
- **Real bugs found & fixed to get here (in Sources, not papered over in the test):** the `layout/barGrid`
  **NaN-vs-JS-truthiness** bar-width poisoning (`barGridTruthy`, §35a table) and the
  **`SeriesModel.getBaseAxis()` `Any?` overload-resolution trap** (§35b) — the latter is why x/width were
  NaN before this closeout.
- **Data source caveat (NOT a bug):** the real `BarSeriesModel.getInitialData → SourceManager.getSource()`
  is still a `fatalError` stub (`data/helper/sourceManager.ts` not ported), so all three render/coord tests
  supply data via a populated `DataStore` double — a documented substitute for a known-unported layer.

### 35d. New open issues & PORT-TODOs (deduped, severity-first)
**OPEN correctness bugs (carry into 6c pre-work):**
1. **`BarView` update-diff branch clips a throwaway copy, not the real `layout`** (see §35a table). Fix: make
   `layout` a `var` in the `.update` closure and `clipCartesian2D(coordSysClipArea, &layout)` in place, as the
   `.add` closure does. Latent today (render test hits only the add path); bites on the first re-render.
2. **`AxisBuilder` Int-boxed `axisTick.length`/`minorTick.length`/`nameGap` read via `... as? Double` → 0**
   → invisible ticks + zero name gap. Same `as? Double` Int-boxing class as §33 #6 (project-wide). Fix at
   ingestion (normalize option numerics to Double) or read with an Int-tolerant coercion helper.
3. **`Chart.eachRendered` visits children only** (`Group.traverse`), where upstream `traverseElements` first
   visits the root group; and `context.payload!`/`ecModel!`/`api!` force-unwraps in the render tasks trap on
   a nil payload the `Scheduler` may set (TS tolerates undefined). Both `view/Chart.swift`.
4. **`visual/style` palette rotation** skips filtered points (no global `colorFromPalette` fallback) so
   `colorBy:'data'` would shift after legend/dataZoom filtering. Out of bar-only scope (bars are
   `isColorBySeries()`), but mark before line/scatter land.

**Deferred features (faithful-signature PORT-TODO stubs; none block the bar vertical):**
- **Prereq util still unported** (blocks fuller BarView/AxisBuilder fidelity): `util/graphic`
  (`updateProps`/`initProps`/`subPixelOptimizeLine`/`removeElementWithFadeOut` — currently local shims),
  `util/states` (`toggleHoverEmphasis`/`setStatesStylesFromModel`), `label/labelStyle`
  (`createTextStyle`/`setLabelStyle`) — **the emphasis/states and label blocks in `BarView.updateStyle` are
  documented PORT-TODO no-ops.**
- **Label collision / layout:** `labelLayoutHelper` hideOverlap/OBB, `LabelManager`, axis-name move-overlap
  resolution, `sectorLabel` — all deferred.
- **BarView non-core paths:** large/progressive (`LargePath`, `throttle`), `realtimeSort`/`changeAxisOrder`,
  `showBackground`, polar `Sector`/`Sausage` branch, `pictorialBar`.
- **Axis extras:** `splitLine`/`splitArea` (`axisSplitHelper`), functional `axisLabel.formatter`
  (`AxisBuilder` `rawLabel` read-back), axis-break rendering; other axis views (Angle/Radius/Single/Parallel).
- **Slim driver skips:** the `Scheduler` task graph proper, media/actions/lifecycle/states, and the full
  `core/echarts.ts` orchestrator (`init`/`setOption`/`_update`).
- **Other chart types + components:** line/scatter/pie/etc.; tooltip/legend/dataZoom/brush/markLine/axisPointer;
  decal/aria; other coordinate systems (polar/geo/single/radar/calendar/parallel/matrix).

### 35e. The SIMULATOR DEMO is now updatable to a REAL echarts-option-driven bar chart
The hand-built-shapes demo can now be replaced by a chart driven end-to-end from an ECharts `option`. Exact
entry point (all public, exercised by `BarChartRenderTests`):
1. **Driver:** `EChartsSlim(width:height:)` → `.setOption(_ option: [String: Any])`
   (`Sources/EChartsKit/core/EChartsSlim.swift`).
2. **Scene-graph accessor:** `EChartsSlim.getRoot() -> ZRenderKit.Group` (the rendered display tree; also
   `.getStorage() -> Storage`, `.getModel() -> GlobalModel?`).
3. **Paint:** `NativePainter.renderToImage(group:size:dpr:backgroundColor:) -> CGImage?`
   (`Sources/NativePainter/CALayerPainter.swift:654`) for a still image; or attach `getRoot()` to the live
   host `ZRenderView` (`Sources/NativePainter/ZRenderView.swift`) for an on-screen/animated view.

So `Sources/DemoGallery` can add a demo that builds `{grid, xAxis, yAxis, series:[{type:'bar', data}]}`,
feeds it to `EChartsSlim.setOption`, and renders `getRoot()` — the first time the full ECharts→ZRenderKit
vertical (data → scale → coord → layout → `Rect`s) is on screen, not hand-built `Group` trees. (Until
`SourceManager.getSource` lands, a demo must supply data via a `DataStore` double, as the tests do.)

### 35f. Roadmap beyond Phase 6b
1. **6c pre-work:** fix the §35d OPEN bugs (BarView clip-in-place, AxisBuilder Int-boxed lengths) and port
   `SourceManager.getSource` so `BarSeriesModel.getInitialData` is real (removes the `DataStore` double).
2. **Emphasis/states + labels:** port `util/graphic`, `util/states`, `label/labelStyle` → real hover/select
   + bar value labels.
3. **More chart types:** line + scatter `ChartView`s (reuse the coord/visual/layout pipeline).
4. **More components:** tooltip, legend, dataZoom, axisPointer, splitLine/splitArea.
5. **More coordinate systems:** polar, then geo/single/radar as demand dictates.

---

## 36. Phase 6c — real data source pipeline (SourceManager)

**Goal (met):** replace the Series-local stub `SourceManager` with a faithful port of
`echarts/src/data/helper/sourceManager.ts`, making `BarSeriesModel.getInitialData`'s source/data-store
provisioning real (the §35d "6c pre-work" item: port `SourceManager.getSource` so the `DataStore`
double is removed). **`swift build` GREEN (0 warnings), `swift test` 216 executed / 0 failures /
58 skipped — no regression vs §35 (was 216/0/58).**

### What landed
- [x] `Sources/EChartsKit/data/helper/sourceManager.swift` ← `echarts/src/data/helper/sourceManager.ts` —
      all methods preserved in upstream name / order / control-flow: `dirty`, `_setLocalSource`,
      `_getVersionSign`, `prepareSource`, `_createSource`, `_applyTransform`, `_isDirty`, `getSource`,
      `getSharedDataStore`, `_innerGetDataStore`, `_getUpstreamSourceManagers`, `_getSourceMetaRawOption`,
      plus free funcs `isSeries` / `doThrow` / `disableTransformOptionMerge`. Reuses the already-ported
      `createSource` / `Source` / `DataStore` / `DefaultDataProvider` / `SeriesDataSchema` / `query*` —
      nothing re-ported.

### The faithful no-dataset path (series inline data → createSource) — fully live & verified
For a cartesian series with inline `data:` and no dataset, the reachable path is exercised end-to-end:
`_getUpstreamSourceManagers() == []` → `hasUpstream = false` → the `isSeries` else-branch →
`data = seriesModel.get("data", true)`, `sourceFormat = SOURCE_FORMAT_ORIGINAL`,
`needsCreateSource = true` → `createSource(...)`. `_innerGetDataStore` then builds a `DataStore` via
`DefaultDataProvider`, and `getSharedDataStore` now ships on the real class (the createSeriesData stub
extension was removed at integrate).

### Design choices
- **Host typing:** added `public protocol SourceManagerHost: AnyObject { var uid }` (mirrors upstream's
  `DatasetModel | SeriesModel` union) with `extension SeriesModel: SourceManagerHost {}` declared *in the
  sourceManager file* — no `Series.swift` edit needed. INTEGRATION NOTE: do **not** also add
  `: SourceManagerHost` to the `SeriesModel` class decl (that would duplicate-conform). `DatasetModel`
  conformance is deferred (dataset host unreachable this phase).
- **`isSeries` uses `host is SeriesModel`** — equivalent to upstream `mainType === 'series'` for the two
  host kinds, and robust against mainType-timing (avoids the `Global.swift` mainType-vs-lifecycle-init
  ordering fragility).
- **`DataStoreMap`:** added `public typealias DataStoreMap = [String: DataStore]`; `_storeList` uses
  auto-vivify + value-type write-back for the cache mutation (CONVENTIONS).
- **`getSource()` returns `Source?`** (upstream can return `undefined`) — an intended public-surface change
  vs the stub. On the reachable inline-data path a source is always created, so callers force-unwrap.

### Source.swift friction resolved (kept, +14/-5)
- `SourceMetaRawOption.seriesLayoutBy` made Optional (`SeriesLayoutBy?`) so the `retrieve2(...) || null`
  value is carried faithfully; ripple: `determineSourceDimensions` / `arrayRowsTravelFirst`
  `seriesLayoutBy` params → Optional (compared only vs `SERIES_LAYOUT_BY_ROW`), and `createSource`
  `sourceData` widened to Optional (upstream data may be `undefined`; no other callers).
- `needsCreateSource` reproduces the JS null-vs-undefined distinction: `upMetaRawOption` modeled as
  `SourceMetaRawOption?` (`nil` ≡ JS empty `{}`), so with no upstream a source IS created for inline data.
  A residual null/undefined subtlety in the (unreachable) upstream-present case is flagged
  `// PORT-TODO(ts:240)`.

### Dataset / transform PORT-TODO deferrals (unreachable this phase; exact upstream refs in-file)
- `_createSource` dataset-host branch (ts:249-268) — `fatalError`.
- `_applyTransform` whole body (ts:277-330) — needs `applyDataTransform` + `DatasetModel.get`.
- `_getUpstreamSourceManagers` dataset arm + series `getSourceManager()` call (ts:437, 439-444).
- `_getSourceMetaRawOption` dataset arm (ts:458-463).
- `disableTransformOptionMerge` (ts:471-474) — needs `setAsPrimitive`.

### Integration (stub → real)
- `Sources/EChartsKit/model/Series.swift`: removed the local stub `public final class SourceManager`
  (weak `_sourceHost`, no-op `prepareSource`/`dirty`, `fatalError` `getSource`), replaced with a comment
  pointing at the real `data/helper/sourceManager.swift`. `getSourceManager()` / init / `mergeOption`
  wiring unchanged. `getSource()` now force-unwraps the real `SourceManager.getSource()` (`Source?` →
  `Source`) with a comment noting upstream returns non-optional and a source is always created on the
  reachable inline-data path.
- `Sources/EChartsKit/chart/helper/createSeriesData.swift`: removed the private
  `extension SourceManager { getSharedDataStore }` PORT-TODO stub; line 184
  `source = sourceManager.getSource()` force-unwrapped to `getSource()!` (extra integration point found
  beyond the scout list, alongside the `Series.swift` `getSource()` force-unwrap).

### Build / test status
- **`swift build`: GREEN, 0 warnings.** **`swift test`: 216 executed / 0 failures / 58 skipped** — no
  regression vs §35. The stub-vs-real duplicate-`SourceManager` state that briefly made the tree red
  during pre-integration verification is resolved by the integrate step.

### Review findings & disposition
- **Faithfulness review: `faithful`, 0 findings.** No open bugs from this phase. The dataset/transform
  arms remain the only deferrals (all `// PORT-TODO`-marked with exact upstream line refs, above).

---

## 37. Phase 6d — symbols (util/symbol) + scatter + pie

**Goal (met):** land the symbol-path factory (`echarts/src/util/symbol.ts`) so line/scatter markers can
draw, teach `LineView` to honor `showSymbol`, and stand up two minimal new chart verticals — a cartesian
`series.scatter` and a coordless `series.pie` — end-to-end through `EChartsSlim`. **`swift build` GREEN
(0 warnings), `swift test` 218 executed / 0 failures / 58 skipped** — matches the required baseline
(+2 vs §36's 216, no regression).

### What landed — tier 1 (fully ported + reviewed)
- [x] `Sources/EChartsKit/util/symbol.swift` ← `echarts/src/util/symbol.ts` — the symbol-path shape
      subclasses + `symbolBuildProxies` registry + `createSymbol`. **Review: `faithful`, 0 findings.**
- [x] `Sources/EChartsKit/chart/helper/createSeriesDataSimply.swift` ← `chart/helper/createSeriesDataSimply.ts`
      — the coordless `SeriesData` builder pie uses (no Grid coord).
- [x] `Sources/EChartsKit/chart/pie/pieLayout.swift` ← `chart/pie/pieLayout.ts` — per-item angle/radius
      geometry via `data.setItemLayout` (see the render hook below).
- [x] `Sources/EChartsKit/util/layout.swift` ← `echarts/src/util/layout.ts` — the box/`getLayoutRect`
      helper pie's center/radius resolution needs.

### What landed — tier 2 (minimal verticals)
- [x] `Sources/EChartsKit/chart/scatter/{ScatterSeries,ScatterView}.swift` — points via
      `coord.dataToPoint` + `createSymbol`.
- [x] `Sources/EChartsKit/chart/line/{LineView,LineSeries}.swift` — `LineView` now honors `showSymbol`
      (draws per-datum symbols atop the polyline).
- [x] `Sources/EChartsKit/chart/pie/{PieSeries,PieView}.swift` — coordless pie sectors from the
      `pieLayout` item geometry.

### Integration into `EChartsSlim` (no coord for pie)
- `installOnce()`: registered `ScatterSeriesModel` and `PieSeriesModel` via `ComponentModel.registerClass`
  (next to `LineSeriesModel`), with faithful `chart/scatter/install.ts` + `chart/pie/install.ts` comment
  blocks.
- `installOnce()`: referenced `_ = pieLayOutOnCoordSysUsageRegistered` exactly once to trigger the Swift
  lazy-global that runs `registerLayOutOnCoordSysUsage` for pie's `box` coordinateSystemUsage.
- `_chartViewFactories`: added `"scatter": { ScatterView() }` and `"pie": { PieView() }`.
- `render()`: added a `pieLayout(ecModel, api)` call **before** `renderSeries` so the coordless pie series
  gets per-item angle/radius geometry via `data.setItemLayout` — the minimal faithful hook so pie renders
  without a Grid coord.

### Deferred PORT-TODOs (this phase)
- **Label + emphasis** on scatter/pie/line symbols — documented `// PORT-TODO`.
- **`SymbolDraw`** (the reusable symbol-collection helper) — not ported; each view draws symbols directly.
- Scatter **stacking** (see review finding below).

### Build / test status
- **`swift build`: GREEN, 0 warnings.** **`swift test`: 220 executed / 0 failures (0 unexpected) /
  58 skipped** — the 218 baseline plus the two new `Scatter`/`PieChartRenderTests`.

### Review findings & disposition
- `util/symbol.swift` — **`faithful`, 0 findings.**
- `chart/pie/pieLayout.swift` — **`minor-issues`, 2 findings (both currently masked, accepted):**
  - *(minor, pieLayout.ts:64)* `clockwise` falls back to `false` when `get("clockwise")` isn't a `Bool`
    (`?? false`), but the upstream default is `true`; a nil would flip winding (`dir = -1`), inverting
    sector geometry. **Masked** because `PieSeries.defaultOption` sets `clockwise: true`.
  - *(minor, pieLayout.ts:62)* `unitRadian` uses `sum != 0 ? sum : validDataCount` vs upstream JS-truthy
    `sum || validDataCount`: a `NaN` sum keeps `NaN` (Swift) where upstream falls through. **Practically
    unreachable** since `getSum` returns finite.
- `chart/scatter/ScatterView.swift` — **`minor-issues`, 1 finding (now a marked PORT-TODO):**
  - *(minor, upstream `src/layout/points.ts:50-56`)* stacking not applied to point coords — the render reads
    raw store values (`baseDimIdx`/`valueDimIdx`) with no `isDimensionStacked`/`stackResultDimension`
    substitution, so a **stacked** scatter would mis-place points. **Low impact** (stacked scatter is rare);
    a `PORT-TODO` referencing `points.ts:50-56` now sits at the dim derivation in `ScatterView.swift`.

### Post-workflow fixes (independent verification pass)
After the workflow, I clean-built + ran the suite, rendered all four verticals, and fixed three real defects
the reviews flagged or the renders exposed:
1. **`pieLayout.swift` `clockwise` fallback** — changed `?? false` → `?? true` to match the upstream default;
   a nil option no longer inverts sector winding. (Was review finding 1, promoted from "masked" to fixed.)
2. **`pieLayout.swift` `unitRadian` NaN-truthiness** — `sum != 0 ? sum : validDataCount` →
   `(sum == 0 || sum.isNaN) ? validDataCount : sum`, byte-faithful to JS `sum || validDataCount`.
3. **Pie slices rendered a single color / then all-black** — TWO coupled bugs:
   - **Visual-task order** (`EChartsSlim.performVisualStage`) ran `dataColorPaletteTask` FIRST; upstream
     (`core/echarts.ts:3360-3362`) runs it LAST, after `seriesStyleTask` sets the `colorFromPalette` item
     visual it reads. Reordered to `seriesStyle → dataStyle → dataColorPalette`.
   - **`SeriesModel.getColorFromPalette` overload trap** — its `scope: Any?` param differed from the
     `PaletteMixin` extension's `scope: AnyObject?`, so `dataColorPaletteTask`'s `AnyObject?` `colorScope`
     argument resolved to the EXTENSION (no ecModel fallback → nil for a series with no own `color`), and
     `itemStyle["fill"] = nil` DELETED the fill (Swift dict semantics) → black slices. Unified the override
     signature to `AnyObject?` so the class method wins for a `SeriesModel` receiver and the ecModel
     fallback runs. This is the general `colorBy: 'data'` per-item palette path; pie now renders 5 distinct
     palette colors matching echarts.js.
- **Render parity confirmed** (native vs `echarts.js`, `--render-all`): bar (4 palette bars), line (polyline
  + hollow symbol points via `showSymbol`), scatter (8 filled circles at correct value×value coords), pie
  (5 palette-colored proportional slices). New gallery demos: `scatter-basic`, `pie-basic`.

---

## 38. Phase 7 — static component layer (title + legend + graphic + marker)

**Goal (met, scoped):** stand up the static (non-interactive) component layer — `title`, `legend`,
`graphic`, and the three `mark*` series markers — as diffable mirrors of upstream, registering the ones
whose full dependency stack is present and landing the rest as compile-clean, PORT-TODO-annotated
files awaiting their deps. **`swift build` GREEN (0 warnings), `swift test` 220 executed / 0 failures /
58 skipped** (no regression vs §37's 218; +2). Per CONVENTIONS §5 (STATIC RENDER ONLY), every
interaction/event/action/animation path is deferred as an in-file PORT-TODO — see the per-component
notes below.

### Registered in `EChartsSlim` (live end-to-end)
- [x] **`title`** — `TitleModel` + `TitleView` view factory. Interaction deferred: the `link`/`sublink`
      `textEl.on('click', …)` handlers + `format.windowOpen` navigation (install.ts:193-202) and the
      `getECData(textEl/subTextEl).eventData` assignment gated on `triggerEvent` (install.ts:204-209).
      `link`/`sublink`/`triggerEvent` ARE still read to compute `textEl.silent`/`subTextEl.silent`
      faithfully. `disableBox` background-box parsing in the minimal `createTextStyle` is out of
      static-render scope. Behavioral note (documented inline, not a shortcut): for numeric
      `top`/`bottom`, upstream leaves `textVerticalAlign` as the raw number (renders as 'top'); the port
      coerces non-string → nil → `?? 'top'`, matching the rendered result.
- [x] **`graphic`** — `GraphicComponentModel` + `GraphicComponentView` view factory +
      `graphicOptionPreprocessor(_ option: inout [String: Any])` wired into `setOption`. Full model
      normalization path ported (`mergeOption`/`optionUpdated`/`_flatten`/`useElOptionsToUpdate` +
      `setKeyInfoToNewElOption`/`isSetLoc`/`mergeNewElOptionToExist`/`copyTransitionInfo`/
      `setLayoutInfoToExist`) and the view build/layout path (`_updateElements`/`_relocate`/`_clear`/
      `newEl`/`createEl`/`removeEl`/`updateCommonAttrs`/`getCleanedElOption`/`setEventData`). Design
      deviations (documented in-file): the `GraphicComponentElementOption` union collapsed to ONE
      reference bag class conforming to `MappingExistingItem`; `model.mappingToExists` (specialized to
      `ComponentOption`) is bridged by smuggling the element reference through
      `ComponentOption.rawOption[GRAPHIC_EL_KEY]`; raw `setOption` element dicts wrapped via
      `normalizeElementOptions` (recursing into children). Deferred PORT-TODO: animation/transition
      (`applyUpdateTransition` → static substitute `applyUpdateTransitionStatic` = `el.attr(cleanedOption)`,
      the no-transition-config final geometry/style; `applyLeaveTransition` → immediate detach;
      `updateLeaveTo`/`isTransitionAll`/`updateProps`/`applyKeyframeAnimation`/
      `stopPreviousKeyframeAnimationAndRestore` are no-ops); interaction (`on*` handlers + `el.draggable`
      in `updateCommonAttrs` dropped; `setEventData` IS ported — it only builds the ECData.eventData bag);
      `util/styleCompat` EC4 back-compat branch not ported (EC5 options don't hit it);
      `graphicUtil.setTooltipConfig` deferred; `graphicUtil.getShapeClass` (extendShape name→class
      registry) NOT ported — only group/image/text elements are constructed, shape elements
      (circle/rect/line/polygon/…) and non-group/image/text clipPaths return nil until the shape registry
      lands; `setTextConfig` bag→typed `ElementTextConfig` bridged for common keys (rich/union fields not
      fully bridged).
- [x] **`legend` (model only)** — `LegendModel` + `registerSubTypeDefaulter('legend', 'plain')` +
      `LegendView` view factory. STATIC MODEL scope: `legendAction.ts`/`legendFilter.ts` (the whole
      action/event/dispatch layer + `legendFilterStageHandler` processor), `installLegendScroll` /
      `ScrollableLegend*` are NOT ported. The selected-map bookkeeping
      (`select`/`unSelect`/`toggleSelected`/`allSelect`/`inverseSelect`/`isSelected`) IS ported faithfully
      — pure `option.selected` manipulation with no action-layer reference; `optionUpdated`'s single-select
      init (static render) depends on `select`/`isSelected`. Only the DISPATCH that invokes these on user
      interaction is deferred (PORT-TODO on those methods). Deferred with safe fallbacks: (a) `visual/tokens.ts`
      — `tokens.color.*`/`tokens.size.m` inlined as resolved constants in `defaultOption`; (b)
      `layout.fetchLayoutMode` — `layoutMode` modeled as a class-var override returning
      `{type:'box', ignoreSize:true}`; (c) `LegendVisualProvider` — provider branch in `_updateData` uses a
      minimal `LegendVisualProviderLike` protocol that nothing conforms to yet (isPotential=true fallback).
      Because Swift option bags are value types (not JS shared refs), init/_updateSelector and the
      select/unSelect/toggle/allSelect/inverseSelect methods operate on `self.option` and write the merged
      result back (documented PORT-TODO).

### Ported but BLOCKED — compile-clean, registration/view/preprocessor left UNWIRED
All three markers share one root blocker: **coord/axis resolution is stubbed.** `getAxisInfo`/`dataTransform`
call `coordSys.getAxis`/`getOtherAxis` through the `CoordinateSystem` PROTOCOL, but `Cartesian2D`'s
more-specific signatures (`getAxis(_:DimensionName)`, `getOtherAxis(_:Axis2D)->Axis2D`) do NOT witness the
protocol's optional-param requirements, so the nil-returning protocol default is dispatched — axis
resolution is effectively deferred until the coord-system protocol witnesses are reconciled. Also common:
`SeriesModel.indicesOfNearest` is stubbed `[]`; `util/states` `enterBlur`/`leaveBlur` and `util/graphic`
`traverseUpdateZ`/`retrieveZInfo` are no-op stubs (blur toggling + z/zlevel propagation onto the marker
draw group stubbed); `renderSeries` + `MarkerModel.createMarkerModelFromSeries` are abstract (`fatalError`)
so per-type subclasses override. `MarkerModel`/`MarkerView`/`markerHelper` base files were added (see below).
Registration was intentionally NOT added to `EChartsSlim` for these (Integrate owns wiring).

- [~] **`markPoint`** — file compiles; `registerClass` + view factory + `markPointPreprocessor` left
      unwired. `SymbolDraw.updateData` (enter/update/leave diff + item labels + emphasis/blur + animation)
      replaced by a direct per-point symbol build (same deliberate deviation as `ScatterView`) using a
      minimal `MarkerSymbolDraw`/`MarkerDraw` stand-in that only holds the `group` slot. Deferred:
      callback-in-data-item (`symbol`/`symbolSize`/`symbolRotate`/`symbolOffset` as user functions) — the
      `isFunction` guards ported, the `getRawValue`/`getDataParams` fetch + 4 invocations deferred
      (getRawValue unavailable: `DataFormatMixin` conformance blocked on `MarkerModel`); `updateTransform`'s
      per-draw `symbolDraw.updateLayout()` layout recompute kept, the relayout call stubbed; tooltip
      host-model wiring (`getECData(child).dataModel = mpModel`) deferred; symbolRotate/symbolOffset/
      symbolKeepAspect + emphasis scale not applied; `install()` registration boilerplate left to the slim
      driver (a reusable `markPointPreprocessor(&opt)` free function is provided). In `updateMarkerLayout`,
      upstream's `point[0]=xPx` on an undefined point (JS throw in degenerate configs) is a safe
      optional-chained no-op.
- [~] **`markLine`** — file compiles; `registerClass` + view factory + `checkMarkerInSeries` preprocessor
      left unwired. Same coord axis-resolution gap (statistic/Infinity single-axis marklines cannot
      resolve axes/containData). Ported Model (defaultOption + createMarkerModelFromSeries) fully, and the
      View geometry (`markLineTransform`, `isInfinity`, `ifMarkLineHasOnlyDim`, `markLineFilter`,
      `updateSingleMarkerEndLayout` — parsePercent x/y, coordSys.dataToPoint, cartesian Infinity-edge
      expansion; `createList` from/to/line SeriesData + dimValueGetter bridge; `renderSeries`;
      `updateTransform`). Deferred: `chart/helper/LineDraw`+`Line` (needs util/states, label/labelStyle,
      emphasis) replaced with a MINIMAL in-file `LineDraw` stand-in that draws the from→to segment as a
      `Polyline` stroked from the item's `style.stroke` — NO diff/enter-leave animation, NO end symbols,
      NO labels, dashed `lineStyle.type` not applied; `seriesModel.getMarkerPosition` (bar/candlestick
      override) not ported — generic dataToPoint else-branch always taken; `getECData` host-model tagging
      commented out; `getVisualFromData` approximated by a local helper reading series `style.fill`;
      `MarkerPositionOption` is position-only (item-level lineStyle/itemStyle/label/symbol re-read via
      getItemModel, `merge()` deep-recursion approximated by shallow `mergePositionOption`); registration/
      install intentionally NOT written.
- [~] **`markArea`** — file compiles; `registerClass` + view factory + `markAreaPreprocessor` left unwired.
      Same coord axis-resolution + `getVisualFromData`/`barStyleFromDict` approximations; depends on the
      same per-series `MarkerModel` instantiation not driven by the slim update cycle. Deferred: label
      (`setLabelStyle`/`getLabelStatesModels` + tokens.color.neutral99); emphasis/states
      (`setStatesStylesFromModel`/`toggleHoverEmphasis`); tooltip/data-model wiring
      (`getECData(polygon).dataModel` — MarkerModel not yet `DataModel`); animation
      (`graphic.updateProps` → local no-anim shim: setShape + z2 immediately); `updateTransform` geometry
      ported but its render-pipeline invocation deferred; `seriesModel.getMarkerPosition`
      (bar/candlestick corner-snap) deferred — generic dataToPoint else-branch, matching `MarkLineView`;
      polar/geo coord systems out (cartesian2d only — getAxis/clampData/dataToPoint dispatched on concrete
      Cartesian2D since protocol witnesses return nil); 1D-object markArea items
      (`MarkArea1DDataItemOption`) yield nil from `markAreaTransform` and are filtered out; z/zlevel
      propagation inherited from `MarkerView.updateZ` (already PORT-TODO); registration + preprocessor
      (`markAreaPreprocessor` provided as a reusable free function) left to Integrate.

### Files added under `Sources/EChartsKit/component/`
- `component/title/` — `TitleModel.swift`, `TitleView.swift` (installTitle path).
- `component/graphic/` — `GraphicComponentModel.swift`, `GraphicComponentView.swift` (+
  `graphicOptionPreprocessor`), `layout.swift` helpers (positionElement/mergeLayoutParam/copyLayoutHV).
- `component/legend/` — `LegendModel.swift`, `LegendView.swift`.
- `component/marker/` — `MarkerModel.swift`, `MarkerView.swift`, `markerHelper.swift` (shared base +
  helper), plus the per-type `MarkPoint*`/`MarkLine*`/`MarkArea*` model+view files.

Marker base notes (all PORT-TODO in-file): `MarkerModel.fillLabel`/`defaultEmphasis` — the
`DisplayStateHostOption`↔`[String:Any]` bridging deferred (mirrors `SeriesModel.fillDataTextStyle`); the
structural `_mergeOption` walk (item-is-Array branch, per-item fillLabel) is preserved, the actual
`defaultEmphasis` call is a no-op stub. `zrUtil.mixin(MarkerModel, DataFormatMixin.prototype)` NOT
expressed as a conformance — blocked by the same impedance as `SeriesModel` (`DataFormatMixin` requires
non-optional `ecModel: GlobalModel` but `Model.ecModel` is `GlobalModel?`), so `getFormattedLabel`/
`getRawValue` are unavailable and `getDataParams` computes only the host-series patch (base fields
color/encode/userOutput/dimensionNames NOT computed). `formatTooltip` fully stubbed (returns nil).
`isAnimationEnabled`'s `if (env.node) return false` early-return dropped (native treated as browser-like,
env.node==false — matches `model/Series.swift`). DEV abstract-marker guard uses `fatalError` in place of
upstream throw. `markerHelper.markerTypeCalculatorWithExtent`: `indicesOfNearest` stubbed `[]` so `[0]`
falls back to index 0; sparse `ParsedValue[]` pre-sized to 2; `toFixed` replicated via `%.*f`
(rounding-mode approximation).

### Deferred interactive PORT-TODOs (summary)
- **legend:** select/unSelect/toggle DISPATCH (legendAction.ts), legendFilter processor, scrollable
  legend (installLegendScroll/ScrollableLegend*), `LegendView` item click/mouseover/mouseout +
  dispatchSelect/Highlight/Downplay, packEventData/triggerEvent, enableHoverEmphasis (no-op), selector
  onclick, function-valued formatter, pie/funnel `legendVisualProvider` branch (provider never assigned
  → pie/funnel legend items not drawn), series-specific `getLegendIcon` glyph (always false → every
  series uses `getDefaultLegendIcon`), decal `createOrUpdatePatternFromDecal` (falls back to
  series-visual decal).
- **marker:** drag/click, `dispatchSelectAction`/highlight/downplay, blur (enterBlur/leaveBlur no-op),
  emphasis/label/animation, z2/zlevel `traverseUpdateZ` propagation, tooltip data-model wiring, and the
  per-type registration + preprocessors themselves (Integrate owns EChartsSlim wiring for the blocked
  three).
- **graphic:** `on*` handlers + `el.draggable`, keyframe/transition animation, `setTooltipConfig`.
- **title:** `link`/`sublink` click + windowOpen navigation, `triggerEvent` eventData assignment.

### Build & test status — Phase 7
- **`swift build`: GREEN (0 warnings).**
- **`swift test`: 220 executed / 0 failures (0 unexpected) / 58 skipped** in 0.280 (0.289) s — matches
  §37's 220 baseline (title/graphic/legend registration + the compile-clean blocked markers add no
  regression).

### Faithfulness reviews — three verdicts, all `minor-issues`
1. **`component/legend/LegendView.swift` — minor-issues.**
   - *(minor)* Series-specific legend glyph never rendered: the upstream
     `isFunction(seriesModel.getLegendIcon)` branch (line+symbol composite for line/scatter-like series)
     is stubbed, so every series falls through to `getDefaultLegendIcon` → flat default icon
     (roundRect/plain symbol). A line-series legend item shows a filled roundRect instead of a
     line-with-marker. Documented PORT-TODO tied to unported SeriesModel subclasses; a rendering (not
     interaction) divergence. (upstream LegendView.ts:422-453 vs LegendView.swift:432-458)
   - *(low)* `show` visibility test narrower than upstream: upstream `if (!legendModel.get('show', true))`
     uses JS falsiness (undefined/null/0/''/false all hide), the port
     `if (legendModel.get("show", true) as? Bool) == false` only returns for explicit Bool false; a
     non-Bool falsy (show:0/null) would leave the legend rendered. Benign (merged default is Bool true).
     (LegendView.ts:114 vs LegendView.swift:167)
   - *(low)* `createTextStyle` reused from AxisBuilder is a minimal reproduction of upstream
     `label/labelStyle.createTextStyle` — resolves font/fill/align/verticalAlign but drops the
     `{inheritColor}` 3rd-arg fallback and rich-text/background/shadow; faithful for plain legend text
     (fill pre-resolved), diverges for rich/inheritColor-driven color. (LegendView.ts:470-479 vs
     LegendView.swift:480-489 / AxisBuilder.swift:1267-1288)
2. **`component/marker/markerHelper.swift` — minor-issues.**
   - *(medium)* The statistic-with-extent coord branch (type:min|max|average|median → base/value axes) is
     effectively dead at runtime: `getAxisInfo` resolves valueAxis via `coordSys.getOtherAxis(...)` through
     the protocol (default returns nil, CoordinateSystem.swift:317) because
     `Cartesian2D.getOtherAxis(_:Axis2D)->Axis2D` doesn't witness the requirement; valueAxis comes back
     nil, so `dataTransform`'s guard (baseAxis!=nil && valueAxis!=nil, markerHelper.swift:187) is false and
     control falls to the xAxis/yAxis else-branch → coord=[nil,nil], no computed item.value. PORT-TODO at
     markerHelper.swift:242-247. (markerHelper.ts:129-144,176-199)
   - *(medium)* `markerTypeCalculatorWithExtent` resolves the base/target coord from data index 0 rather
     than nearest, because `SeriesModel.indicesOfNearest` is stubbed `[]` (Series.swift:546) → `.first ?? 0`.
     Upstream picks the index nearest the computed statistic; the port places it at datum 0. Latent
     (unreachable while valueAxis is nil) but wrong once axis resolution lands. PORT-TODO at
     markerHelper.swift:102-106. (markerHelper.ts:73-81)
   - *(low)* `scaleDataValues` comment claims 'dropping nils' but `coord.map { ($0 as Any) as ScaleDataValue }`
     keeps nil entries — actually MORE faithful than the comment (upstream passes item.coord straight
     through); stale-comment doc issue, not behavioral.
   - *(low)* `toFixedNumber` approximates JS `Number.prototype.toFixed` (round-half-away-from-zero) with
     `String(format:"%.*f")` (round-half-to-even) — last-digit rounding can differ at exact .5 boundaries.
     PORT-TODO at markerHelper.swift:124-126.
   - *(low)* `numCalculate` 'average' reads via `args[0] as? Double ?? .nan` and skips non-Double, whereas
     upstream uses `isNaN(val)` — matches while DataStore chunks hold Double (confirmed), but a future
     non-Double numeric ParsedValue (ordinal Int) would be silently excluded from the mean. Informational —
     currently faithful.
3. **`component/graphic/GraphicView.swift` — minor-issues (all low).**
   - *(low)* `updateCommonAttrs` (GraphicView.swift:519-528) replaces upstream's
     `else if ((el)[prop] == null)` guard with an unconditional default write when the option omits
     cursor/zlevel/z/z2, so a `merge` re-render can clobber an existing value; limited this phase (the only
     external writer, keyframe animation, is deferred) and for fresh (isInit) elements it writes the same
     defaults. (upstream GraphicView.ts:451-462)
   - *(low)* `layout.swift:474-475` (positionElement raw-group branch) uses
     `(positionInfo["width"] as? Double) ?? 0` / height, dropping upstream's `+positionInfo.width || 0`
     numeric coercion; a string-valued group width ('100') yields 0. Group width is pixel-only, so only
     malformed input bites. (util/layout.ts:592-594)
   - *(low)* `layout.swift:591-596` (mergeLayoutParam fallback) + `copyLayoutHV` (601-609) key on value-nil
     instead of upstream `zrUtil.hasOwn` key-presence, so an explicit `null` (user clearing width/right) is
     treated as absent rather than present-with-null; diverges only for that explicit-null edge.
     (util/layout.ts:733-745,751-755)
   - *(low)* `GraphicView.swift:153-163` top/bottom text-align clear sets style keys to nil (removes them)
     rather than upstream's explicit `null` assignment; on a merge onto an existing text element with
     align/verticalAlign set, the stale value is not actively cleared. No effect for freshly created text
     (static-render common case). (GraphicView.ts:133-141)

---

## 77. Phase 46 — Chord hover-emphasis + focus:'adjacency' (17th interaction-layer phase; completes node/edge hover)

**Goal (met):** chord — the last node/edge chart without hover — now enters emphasis on hover and dims the
non-adjacent subgraph under `focus:'adjacency'`. **Clean build (0 warnings); `swift test` — 301 / 0 / 58**
(baseline 300; +1 chord test). Demos: 47/47 render.

Applied the node+edge emphasis block to `ChordPiece` (Sector) + `ChordEdge` (Path) — both already
`setItemGraphicEl`-registered + `dataType`-tagged, so this adds `toggleHoverEmphasis` (adjacency →
`getAdjacentDataIndices()` → `{node,edge}` dict) + `setStatesStylesFromModel` + `ecData.dataIndex`.
`ChordSeriesModel` got the `getData(.edge)→getEdgeData()` override (same [[getdata-datatype-ignored-trap]]).

**Trap:** inside a `Sector`/`Path` subclass the bare `states` binds to `self.states` (the element's ZR
state dict), not the `states` enum — qualified as `EChartsKit.states`.

Hover-highlight + topology-focus now works for ALL node/edge charts (graph, tree, sankey, chord).

---

## 76. Phase 45 — Topology focus + edge emphasis for graph / tree / sankey (16th interaction-layer phase)

**Goal (met):** `emphasis.focus` topology now works — highlighting a node keeps its neighbourhood bright
and blurs the rest — and graph/sankey edges are emphasis dispatchers. **Clean build (0 warnings);
`swift test` — 300 / 0 / 58** (baseline 297; +3 `ZZTopologyFocusTests`). Demos: 47/47 render.

**Wiring** (the data-layer index methods already existed — this is view-layer only):
- **Graph** (`GraphView.swift`): edge emphasis block + a post `eachNode`/`eachEdge` loop that overwrites
  `ecData.focus` with the adjacency set (node → `getAdjacentDataIndices()`; edge → inline `{edge:[self],
  node:[n1,n2]}`), bridged to the `{node,edge}` dict `blurSeries` consumes.
- **Sankey** (`SankeyView.swift`): inline adjacency/trajectory resolution for node + edge; edge emphasis;
  `ecData.dataType`/`dataIndex` tags on the curve/rect (required for `blurSeries`'s `getData(dataType)`).
- **Tree** (`TreeView.swift`): `relative`/`ancestor`/`descendant` → `[Int]` array-focus on the node symbol;
  edge `setStatesStylesFromModel(lineStyle)`.

**Key fix (found via the failing test):** `SeriesModel.getData(dataType)` ignored `dataType` (base always
returns node data), so the object-focus branch resolved edge indices against NODE data → edges never
un-blurred. Added `getData(.edge) → getEdgeData()` overrides on `GraphSeriesModel` + `SankeySeriesModel`
(upstream `data.getLinkedData(dataType)`). Also: `dispatchAction(highlight)` must target via
`dataIndexInside` (the `dataIndex`→`indexOfRawIndex` map is a pre-existing stub; a raw `dataIndex` returns
nil → `toggleHighlight` falls to its highlight-ALL branch and emphasises every node, masking the blur).

**Done directly in the main loop** off a thorough scout (no workflow — mechanical wiring).

**Deferred (documented):** the tree `__edge` blur-propagation hook (edges dim with their node — needs
`TreeSymbol.__edge` + `onHoverStateChange`); the live mouseover focus fan-out (Phase 33 defers it — focus
works via the `dispatchAction(highlight)`/tooltip path); chord `focus:'adjacency'` (a peer deferred site).

---

## 75. Phase 44 — Rect brush: drag-select + dim unselected (15th interaction-layer phase)

**Goal (met):** dragging a rectangle over a cartesian chart (with a `brush` component) SELECTS the in-rect
data and DIMS the rest (recolors the unselected to the brush `outOfBrush` color). **Clean build (0 warnings);
`swift test` — 297 / 0 / 58** (baseline 294; +3 `ZZBrushTests`).

**Files added:** `component/brush/BrushModel.swift` (model + `setAreas` + default `outOfBrush:{color:disabled}`;
`extension BrushModel: BrushModelLike {}`), `component/brush/brushVisual.swift` (port of `visualEncoding.ts`
+ `selector.ts`: `BrushTargetManagerLite` grid/rect target match + `setInputRanges` coordRange→pixel, the RECT
selector (point-in-rect / rect-intersect), Step A `controlSeries` + Step B `applyVisual`), `component/brush/
brushAction.swift` (`installBrushAction` → `brush`(updateVisual)/`brushSelect`/`brushEnd`).

**Files edited:** `visual/visualSolution.swift` (added non-incremental `applyVisual(...)` — additive),
`core/EChartsSlim.swift` (register `BrushModel` + `installBrushAction`; call `brushVisual(ecModel,api,nil)` at
the END of `render()`, right before `renderSeries` — NOT the update() visual stage), `core/EChartsView.swift`
(`_bindBrush` + `_brushDrag` mousedown→mouseup rect drag → dispatch `brush`; <2px drag clears; hover suppressed
during a brush drag).

**Key detail (render order):** the rect selector reads each datum's `getItemLayout` (pixel geometry). The slim
driver only populates that in `render()`'s per-series layout stages (bar's progressive layout etc.), which run
AFTER `update()`'s generic visual stage. So brushVisual MUST run at end-of-render() (upstream PRIORITY.VISUAL.BRUSH
= 5000, after the layout stages) — a first placement in the update() visual stage saw nil layouts and selected
nothing. Uses BAR to exercise the selector end-to-end (scatter sets no item layout in this port).

**Integrated MANUALLY** (workflow verify agents reported CRITICAL-ISSUES; integrator died): deleted a dead
duplicate `selector.swift` (colliding top-level decls — logic already in brushVisual.swift), added the missing
`BrushModelLike` conformance (runtime `as?` casts were silently nil → no-op), added the EChartsView drag + the
tests, and fixed the render-order bug above.

**Deferred (documented):** brushType polygon/lineX/lineY, the full `BrushController` (transformable covers,
live rubber-band, removeOnClick covers), coordRange persistence across dataZoom, the toolbox brush button,
`brushLink` / parallel `stepAParallel`, throttle.

---

## 74. Phase 43 — Hover-emphasis for graph / tree / sankey (14th interaction-layer phase)

**Goal (met):** hover-highlight now works for the node/edge charts (node elements). **Clean build (0
warnings); `swift test` — 294 / 0 / 58** (baseline 291; +3 `ZZHoverBreadth3Tests`). Applied the emphasis
block to GraphView/TreeView/SankeyView node elements (mirroring each upstream call site). Hover now works
for **11 chart types**. Deferred: topology focus (adjacency/ancestor/trajectory blur); edge/link emphasis.

## 73. Phase 42 — Demo-track batch 1: 10 echarts test-case demos (goal clause 2)

**Goal (progress):** began "在demo中实现echart test中所有用例". Added 10 option-expressible demos from
canonical echarts `test/` scenarios to `EChartsDemoGallery` (bar-stack/negative/horizontal,
line-area/smooth/stack, pie-doughnut/rose, scatter-multi, bar-datazoom-slider). `swift run
EChartsDemoGallery --render-all` → **39/39 render headlessly, 0 failed**. The gallery already covered the
core chart types (39 demos). More batches to follow toward the (largely interactive/JS-closure) 606-case
corpus.

## 72. Phase 41 — SliderZoomView: the on-screen dataZoom slider widget + drag (13th interaction-layer phase)

**Goal (met):** the `dataZoom:{type:"slider"}` bar renders (background + selected-window filler band +
two draggable handles) and dragging a handle resizes the window. **Clean build (0 warnings); `swift
test` — 291 / 0 failures / 58 skipped** (baseline 289; +2 `ZZSliderZoomTests`: renders with `_range ≈
[20,60]`; `_onDragMove(.at(1),+40)` widens the window). `component/dataZoom/SliderZoomView.swift`
(render + layout) + `SliderZoomViewDrag.swift` (drag → `sliderMove` → dataZoom action); registered in
`_componentViewFactories`; `Element.swift` got a faithful `driftHandler` reassignable-drift seam
(additive). INTEGRATED MANUALLY (the workflow hit the account session limit after translation) — fixed
the compile errors (private→internal, IUO-bound-to-let, optionals), registered, tested. No adversarial
review (agents quota-limited); proven green by the render+drag tests. Deferred: data-shadow preview,
brushSelect, click-panel recenter, throttle/tween, label formatter, `util/layout`. Next: brush;
toolbox; timeline; graph/tree/sankey hover.

## 71. Phase 40 — Hover-emphasis for candlestick / boxplot / funnel / radar (12th interaction-layer phase)

**Goal (met):** hover-highlight + item-tooltip now work for candlestick, boxplot, funnel, radar (was
bar/scatter/line/pie only). Applied the established emphasis block per data element to each view's item
elements (candlestick per-state sign-color loop preserved; radar's per-series itemGroup as the
dispatcher). **Clean build (0 warnings); `swift test` — 289 / 0 failures / 58 skipped** (baseline 285;
+4 `ZZHoverBreadth2Tests`, each proving hover→emphasis through the real Handler chain). 285 pre-existing
tests unchanged. Hover now works for **8 chart types**. Deferred: candlestick large path; radar per-state
symbol styling; select/blur/label/animation niceties. Next: graph/tree/sankey hover; SliderZoomView;
brush; toolbox; timeline.

## 70. Phase 39 — Inside-zoom pan (drag to move the window; 11th interaction-layer phase; completes inside-zoom roam)

**Goal (met):** dragging the cartesian chart body pans the dataZoom window (pairs with Phase-38 wheel-zoom).
**Clean build (0 warnings); `swift test` — 285 / 0 failures / 58 skipped** (baseline 282; +3
`ZZInsidePanTests`: drag-left `[20,60]→[40,80]`, drag-right `→[10,50]` span-preserving, off-grid no-op).
`core/EChartsView.swift` — `_bindInsidePan` + `_insideZoomDrag` state machine (mirrors RoamController
mousedown/move/up), `_computeInsidePanRange` (pan math via `sliderMove('all')`), shared
`_resolveInsideZoomGeom` (wheel+pan). Hover suppressed only while dragging (`_insideZoomDrag != nil`
gate). All prior hover/tooltip/crosshair/wheel tests pass. Only this file changed. Deferred: cursor
styling, modifier-key gating, pinch/momentum, full RoamController, throttle/tween, polar/single roam,
SliderZoomView. Next: SliderZoomView; brush; toolbox; timeline.

## 69. Phase 38 — Inside-zoom wheel-to-zoom (interactive dataZoom; 10th interaction-layer phase)

**Goal (met):** scrolling the wheel over a cartesian chart with an inside dataZoom zooms the data
window live (reusing the Phase-32 filter core). **Clean build (0 warnings); `swift test` — 282 / 0
failures / 58 skipped** (baseline 279; +3 `ZZInsideZoomTests`: zoom-in 10→6, zoom-out 6→10, outside-grid
no-op — through the real Handler→mousewheel chain). `core/EChartsView.swift` — `_bindInsideZoom` binds
`zr.on("mousewheel")`; ports the `InsideZoomView._onZoom`/`RoamController` zoom math (scale factor +
anchor-percent window recompute via `sliderMove`); finds the inside dataZoom whose coordSys contains the
cursor; dispatches the Phase-32 `dataZoom` action → re-filter → `zr.refresh()`. Only this file changed
(no shared-infra). Deviation: target axis via the dataZoom AxisProxy (slim axis models lack the grid
referring link) — equivalent for single-axis cartesian. Deferred: pan/drag, pinch, full RoamController,
throttle/tween, polar/single roam, the SliderZoomView widget. Next: SliderZoomView; brush; toolbox;
timeline.

## 68. Phase 37 — Hover-emphasis breadth: scatter / line / pie (9th interaction-layer phase)

**Goal (met):** hover-highlight + item-tooltip now work for scatter, line, and pie (previously bar-only).
Applied the established BarView emphasis-enable block (`toggleHoverEmphasis` + `setStatesStylesFromModel`
per data element via `data.getItemModel(idx)`) to ScatterView (symbols), LineView (data-point symbols),
PieView (sectors). **Also fixed a real gap:** ScatterView + LineView never called `setItemGraphicEl`, so
their data elements were unregistered for hit-test/tooltip/highlight — added it. **Clean build (0
warnings); `swift test` — 279 / 0 failures / 58 skipped** (baseline 276; +3 `ZZHoverBreadthTests`, each
proving hover→emphasis through the real Handler chain). Mechanical replication of the tested BarView
pattern (no adversarial review); 276 pre-existing tests unchanged. Deferred: line-path line-emphasis; pie
`selectedOffset` + focus fan-out; symbol SymbolDraw states. Next: remaining series views; dataZoom drag;
brush/toolbox/timeline.

## 67. Phase 36 — Visual axisPointer crosshair (line follows the pointer; 8th interaction-layer phase; completes the axisPointer feature)

**Goal (met):** hovering a cartesian chart (`tooltip:{trigger:"axis"}`) draws a vertical crosshair `Line`
at the hovered x, alongside the Phase-35 axis tooltip; off-grid hides it. **Clean build `buildGreen =
true` (0 warnings); `swift test` — 276 executed / 0 failures / 58 skipped** — baseline 275/0/58; +1 =
new `ZZAxisCrosshairTests`.

### Files added / edited
- **`component/axisPointer/{viewHelper,CartesianAxisPointer,BaseAxisPointer,AxisPointer,AxisPointerView}.swift`**
  (NEW) — the crosshair shape/render stack. `CartesianAxisPointer.makeElOption` = line pixel via
  `toGlobalCoord(dataToCoord(value,true))` (concrete `Cartesian2D`/`Axis2D` — witness trap avoided);
  `BaseAxisPointer.render` builds the `Line`+label `Group` (pointer `silent=true`) via a `hostAdd`/
  `hostRemove` seam. Reviewed **FAITHFUL**.
- **`core/EChartsView.swift`** (EDIT) — `_axisPointers` (per-axis, persisted) + `_updateAxisPointers`
  after `axisTrigger`: wires `hostAdd = { self?.zr.add($0) }` (`[weak self]`) and renders with the
  value/status axisTrigger wrote; off-grid → `hide()`. Only this file changed (no shared-infra).

### Integrator died → rescued
The workflow integrator died before wiring (render-wiring review CRITICAL because the 5 files were dead
code). A rescue integrator wired the crosshair into EChartsView (driven directly on hover, PARALLEL to
the tooltip — the slim path has no live per-axis AxisView hosting a zr) + added the test.

### Deferred (documented)
- `axisPointer:{show:true}` WITHOUT a tooltip trigger:"axis" (hover path gated on the axis-trigger
  tooltip); polar/single crosshairs; move animation; drag handle; `lineDash` (default `dashed` renders
  SOLID).
- Next: dataZoom slider/inside DRAG; hover+tooltip across the remaining series views; brush/toolbox/timeline.

## 66. Phase 35 — axisTrigger + tooltip trigger:`axis` (multi-series axis tooltip on hover; 7th interaction-layer phase; crosshair deferred to Phase 36)

**Goal (met):** hovering a cartesian chart with `tooltip:{trigger:"axis"}` shows ONE combined tooltip
listing every series' value at the hovered x. **Clean build `buildGreen = true` (0 warnings); `swift
test` — 275 executed / 0 failures / 58 skipped** — baseline 274/0/58; +1 = new `ZZAxisTooltipTests`.

### Files added / edited
- **`component/axisPointer/{AxisPointerModel,modelHelper,axisTrigger,findPointFromSeries,globalListener}.swift`**
  (NEW) — the axis-trigger data core: point → axis value (`Cartesian2D.pointToData`) → series data
  indices → `dataByCoordSys` → `showTip`.
- **`component/tooltip/TooltipView.swift`** (EDIT) — the trigger:"axis" path `_showAxisTooltip` (combined
  markup from all series via `formatTooltip(...,multipleSeries:true,...)`).
- **`core/EChartsView.swift`** (EDIT) — `_bindAxisPointerListeners` (globalListener→axisTrigger; routes
  `showTip{dataByCoordSys}`→`_showAxisTooltip`, `hideTip`→`hide`; gated on trigger=="axis").
- **`core/EChartsSlim.swift`** (EDIT) — registered `AxisPointerModel` + preprocessor + `modelHelper.collect()`
  in `update()` + exposes `api`.

### CRITICAL found + FIXED post-workflow — the protocol-witness trap ×3
The workflow integrator died before wiring (both reviews CRITICAL because the data core was dead code).
A rescue integrator finished it and hit the recurring witness trap ([[swift-protocol-witness-trap]]) in
THREE places, all blocking series resolution: (1) `modelHelper.collectSeriesInfo` cast to the
`CoordinateSystem` existential → `getAxis` nil default → series never attached to an axis (fixed: narrow
to concrete `Cartesian2D`); (2) `Grid.model` (`let model: GridModel`) didn't witness
`CoordinateSystemMaster.model: ComponentModel?` → `coordSys.model` nil → empty axes info (fixed: real
`var model` witness + concrete `gridModel` accessor); (3) `SeriesModel.indicesOfNearest` was a `return []`
stub → empty payloadBatch → `hideTip` not showTip (fixed: implemented). All three regression-safe (274
pre-existing tests unchanged).

### Deferred (documented, Phase 36+)
- The VISUAL crosshair (axisPointer line/label view element); polar/single-axis pointers; link `mapper`;
  throttle; `getAxisTooltipData` (candlestick/boxplot); `label.formatter` + full valueLabel;
  `_showOrMove`/showDelay.
- Next: Phase 36 = the visual axisPointer crosshair; then dataZoom slider/inside drag; hover+tooltip
  across the remaining series views.

## 65. Phase 34 — Tooltip-on-hover: `TooltipRichContent` + slim `TooltipView` (trigger:item) wired into `EChartsView` (6th interaction-layer phase)

**Goal (met):** the Phase-31 tooltip content now APPEARS on hover — a ZRenderKit-drawn box at the
pointer, floating above the chart, driven by `EChartsView`'s hover events. **Clean build `buildGreen =
true` (0 warnings); `swift test` — 274 executed / 0 failures / 58 skipped** — baseline 273/0/58; +1 =
new `ZZTooltipHoverTests`.

### Files added / edited
- **`component/tooltip/TooltipRichContent.swift`** (NEW) — the `ZRText` tooltip box. `setContent` builds
  the rich-text style from the Phase-31 markup + padding/backgroundColor/borderColor/shadow/textStyle;
  hosted in the LIVE `zr` via `_zr.add(el)` (NOT `ec.getRoot()`). `show`/`hide`/`getSize`/`moveTo`.
- **`component/tooltip/TooltipView.swift`** (NEW) — slim trigger:`item` view: `tryShow` → resolve series+
  dataIndex → model guard → `formatTooltip` → `setContent`+`show` positioned near the pointer; `hide`;
  `showTip`/`hideTip` actions.
- **`core/EChartsView.swift`** (EDIT) — owns a lazily-built `TooltipView`; mouseover fires BOTH emphasis
  AND `tryShow`; mouseout → `hide`; disposed in `deinit`.
- **`core/EChartsSlim.swift`** (EDIT) — `installTooltipActions`.

### CRITICAL found + FIXED post-workflow
`TooltipRichContent.richTextStylesToParts` reverse-engineers each `{styleName|text}` style bag into a
`TextStylePropsPart` via a whitelist (vs upstream's wholesale `rich: richTextStyles`) and DROPPED the
`width` key — so the series-color swatch marker (an empty-text token sized purely by
`width`+`height`+`backgroundColor`) collapsed to width 0 (the color dot vanished). Fixed by adding the
`width` (NumberOrString) branch. (The two CRITICALs the reviewers reported — "not wired" / "no test" —
were STALE: the integrator finished the `EChartsView` wiring + `ZZTooltipHoverTests` after those reviews
ran; both verified present + passing.)

### Test-methodology fix
A rich `ZRText` is a CONTAINER — `Storage.updateDisplayList` recurses into its text tokens rather than
emitting the ZRText as a display-list leaf. So the tooltip is asserted as a visible STORAGE ROOT of the
zr (`getRoots()`), not as a flattened-display-list member.

### Deferred (documented)
- trigger:`axis` + axisPointer integration; the HTML content host; `transitionDuration`; `confine`; the
  position-callback; per-item/coordSys tooltip-model cascade (series-only merge this phase); tooltip on
  the OTHER series views (BarView-driven hover only this phase).
- MINORs: `alwaysShowContent` JS-truthiness edge; non-string (gradient) backgroundColor dropped; the
  marker-whitelist remains fragile vs upstream's pass-through.
- Next: trigger:`axis` + the axisPointer hover crosshair; dataZoom slider/inside drag; hover+tooltip
  across the remaining series views.

## 64. Phase 33 — LIVE interaction: the `EChartsView` host binding (hover-to-highlight through the real Handler; 5th interaction-layer phase)

**Goal (met):** the first genuinely interactive behavior — hovering a data element highlights it —
driven end-to-end through the already-ported ZRenderKit `Handler` (findHover + mouseover/mouseout) +
`NativeHandlerProxy` + `ZRenderView`. Connects Phases 29-31 (dispatch, emphasis engine, state styles)
to the native input stack. **Clean build `buildGreen = true` (0 warnings); `swift test` — 273 executed
/ 0 failures / 58 skipped** — baseline 271/0/58; +2 = new `ZZLiveHoverTests`.

### Files added / edited
- **`core/EChartsView.swift`** (NEW) — the echarts↔live-ZRender host binding. Owns an `EChartsSlim` + a
  live `ZRender` (`HeadlessPainter` for tests, a real `PainterBase` for a native host), syncs
  `ec.getRoot()` into the zr storage, and `_initEvents` binds mouseover/mouseout → emphasis + click →
  `toggleSelect`. `_injectPointerForTest` drives synthetic pointers headlessly. `deinit`/`dispose` release
  the zr.
- **`util/states.swift`** (EDIT) — `enterEmphasisWhenMouseOver`/`leaveEmphasisWhenMouseOut` (the
  `!shouldSilent && __highByOuter==0` gate) + `setStatesStylesFromModel` (model emphasis/blur/select
  itemStyle → element ZR states).
- **`chart/bar/BarView.swift`** (EDIT) — each bar `Rect` gets `setStatesStylesFromModel` +
  `enableHoverEmphasis` (a highDown dispatcher with its emphasis state style; normal render untouched).

### CRITICAL found + FIXED post-workflow — retain cycle
The `zr.on(evt, closure, self)` listeners passed `self` as the ctx, which `Eventful`/`EventHandler.ctx`
stores STRONGLY, and zr→handler→eventful is strongly owned by the view → `EChartsView` never
deallocated (leaking the whole chart graph). Fixed: bind ctx `nil` on all three listeners (closures are
already `[weak self]`; `Handler.on` defaults ctx to the handler) + `deinit { zr.dispose() }` (removes
the zr from the module-global zrender `instances` registry). Locked by `testEChartsViewHasNoRetainCycle`.

### MINORs fixed
- `findDispatcher` returned the innermost dispatcher for mouseover/mouseout; upstream returns the
  OUTERMOST (no returnFirstMatch) and first-match only for click — added a `returnFirstMatch` param.
- click dispatched `highlight` (duplicating hover); upstream toggles SELECTION — changed to `toggleSelect`.

### Deferred (documented)
- The FOCUS fan-out (`handleGlobalMouseOverForHighDown` → `blurSeries`/`blurComponent` to dim
  non-focused siblings on hover; the `blurSeries` engine is ported, the global focus handler is not).
- `mousemove`→`axisTrigger`→tooltip/axisPointer show; the public ECharts event bus;
  `__highDownSilentOnTouch`.
- Applying `enableHoverEmphasis` in the OTHER series views (only BarView this phase — mechanical follow-up).
- Next: hover-emphasis across the remaining series views; `mousemove`→axisTrigger→tooltip/axisPointer;
  dataZoom slider/inside drag.

## 63. Phase 32 — dataZoom DATA core (models + `AxisProxy` + `dataZoomProcessor` + action) (4th interaction-layer phase; host-independent)

**Goal (met):** `option.dataZoom = [{start, end}]` filters/zooms the series data to the window on
render — no pointer/host needed. The slider/inside VIEWS + roam/DRAG are DEFERRED (need the live-view
host). **Clean build `buildGreen = true` (0 warnings); `swift test` — 271 executed / 0 failures / 58
skipped** — baseline 269/0/58; +2 = new `ZZDataZoomTests`.

### Files added / edited
- **`component/dataZoom/DataZoomModel.swift`** (NEW, base) — target-axis resolution (model finder),
  start/end normalization + rangePropMode (percent vs value), `setRawRange`/`getPercentRange`/
  `getValueRange`/`findRepresentativeAxisProxy`, per-axis `AxisProxy` construction in `optionUpdated`.
- **`component/dataZoom/InsideZoomModel.swift` + `SliderZoomModel.swift`** (NEW) — concrete inside/slider
  models + defaultOption (VIEW logic deferred).
- **`component/dataZoom/AxisProxy.swift`** (NEW) — `calculateDataWindow` (percent↔value, minSpan/maxSpan
  clamp), `reset` (sets the scale zoom min/max via `scaleRawExtentInfo.setZoomMM`), `filterData` (filters
  each target series via `SeriesData.filterSelf`/`selectRange`, all four `filterMode`s).
- **`component/dataZoom/dataZoomProcessor.swift`** (NEW) — the FILTER-stage processor.
- **`component/dataZoom/dataZoomHelper.swift`** (NEW) — target-axis resolution helpers.
- **`component/dataZoom/dataZoomAction.swift`** (NEW) — the `dataZoom` action.
- **`component/helper/sliderMove.swift`** (NEW) — the range-move clamp helper.
- **`core/EChartsSlim.swift`** (EDIT) — registered InsideZoom/SliderZoom + the `dataZoom`→`"slider"`
  subtype defaulter + the action; HOOKED the processor into `update()`'s processor stage BEFORE
  `coordSysMgr.update` (calls `getTargetSeries` — which creates each `AxisProxy` — THEN `overallReset`;
  self-gates to a no-op with no dataZoom component).

### Reviews / issues
- `AxisProxy`/`dataZoomProcessor`/`dataZoomHelper` reviewed **FAITHFUL**. The `models`+registration review
  raised a **CRITICAL — the data core was never WIRED** (models unregistered, no subtype defaulter,
  processor not invoked) because the workflow integrator died before wiring. **RESOLVED post-workflow**
  by the registration + subtype defaulter + processor hook (verified: zoom filters 10→5, Int/Double
  parity; no-dataZoom charts unaffected).
- Also FIXED a real runtime bug found during integration: `sliderMove.swift`'s
  `restrictSlider(_:_ extend:[Double])` re-dispatched to itself (infinite recursion / stack overflow) —
  disambiguated with `as [Double?]`.

### Deferred (documented)
- Slider/inside VIEWS + roam/DRAG → need the live-view host. Throttle, dataShadow. The
  `CoordinateSystemHostModel`→`ComponentModel` narrowing (pre-existing helper PORT-TODO).
- Next: the **live-view host** (pointer/gesture → dispatchAction) → then the slider/inside views + drag,
  and the tooltip/axisPointer hover trigger.

## 62. Phase 31 — Tooltip CONTENT model (`tooltipMarkup` + `seriesFormatTooltip` + `TooltipModel`) + `visual/tokens` (3rd interaction-layer phase; host-independent)

**Goal (met):** port the host-independent tooltip content pipeline so `formatTooltip(dataIndex)` yields
real formatted content (markup tree → html/richText). The on-screen `TooltipView` + hover trigger are
DEFERRED (need the live-view host). **Clean build `buildGreen = true` (0 warnings); `swift test` — 269
executed / 0 failures / 58 skipped** — baseline 264/0/58; +5 = new `ZZTooltipContentTests`.

### Files added / edited
- **`visual/tokens.swift`** (NEW, ports `visual/tokens.ts` 233 lines) — the design-token palette
  (neutral00..99, the 9-color `theme` array, accent/semantic/shadow/background tokens, darkColor
  derivation). Reused by tooltip + (eventually) the series that inline these today.
- **`component/tooltip/tooltipMarkup.swift`** (NEW) — `createTooltipMarkup` (section/nameValue),
  `buildTooltipMarkup` for renderMode `html` AND `richText`, `retrieveVisualColorForTooltipMarker`,
  `TooltipMarkupStyleCreator`, gap/indent + sortBlocks-by-order (via `SortOrderComparator`).
- **`component/tooltip/seriesFormatTooltip.swift`** (NEW) — `defaultSeriesFormatTooltip` (series name +
  per-dim nameValue blocks).
- **`component/tooltip/TooltipModel.swift`** (NEW) — `TooltipModel` + full `defaultOption`; `axisPointer`
  sub-option as a `[String:Any]` stub (axisPointer unported).
- **`model/Series.swift`** (EDIT) — `formatTooltip` un-stubbed → `defaultSeriesFormatTooltip`.
- **`model/mixin/dataFormat.swift` + `data/helper/dataProvider.swift`** (EDIT) — `retrieveRawValue`
  un-stubbed (faithful body enabled now its deps landed; tooltip reads raw values through it).
- **`core/EChartsSlim.swift`** (EDIT) — registered `TooltipModel` with a documented
  `component/tooltip/install.ts` deferral note (TooltipView/showTip/hideTip/installAxisPointer deferred).

### Reviews / issues
- Both faithfulness reviews **MINOR-ISSUES**, NO CRITICAL. Token values spot-checked EXACT; HTML/richText
  templates byte-identical; both renderMode branches proven by the test (content carries name + value).
- MINOR (documented, non-blocking): a gradient/pattern MARKER color falls through to `"transparent"`
  (needs a typed color in the visual style bag; solid colors correct). Series-specific `formatTooltip`
  overrides (map/tree/sankey/…) remain stubbed; the base default covers bar/line/etc.

### Deferred (documented)
- On-screen `TooltipView` render + the hover/click TRIGGER → need the live-view host.
- `axisPointer` sub-option stub → lands with axisPointer.
- Next: the **live-view host** (pointer/gesture → dispatchAction) → then `TooltipView` + `axisPointer`
  hover trigger; and `dataZoom`.

## 61. Phase 30 — Emphasis/blur/select state engine (`util/states.ts`) + `updateDirectly` + highlight/downplay/select actions (2nd interaction-layer phase)

**Goal (met):** make `dispatchAction` actually change element visual state — port the emphasis/blur/select
engine and wire the light-update path so `highlight`/`downplay`/`select`/`unselect`/`toggleSelect`
mutate element states WITHOUT a full re-render. **Clean build `buildGreen = true` (0 warnings);
`swift test` — 264 executed / 0 failures / 58 skipped** — baseline 260/0/58; +4 = new `ZZEmphasisTests`.

### Files added / edited
- **`util/states.swift`** (NEW, ports `util/states.ts` 918 lines) — `enterEmphasis`/`leaveEmphasis`
  (ref-counted by highlightDigit via the `__highByOuter` bitmask), `enterBlur`/`leaveBlur`,
  `enterSelect`/`leaveSelect`, the `singleEnter*`/`singleLeave*` primitives applied through ZRenderKit
  `useStates`/`clearStates`, `allLeaveBlur`, `blurSeries` (focus + blurScope self/series/coordinateSystem/
  global), `blurSeriesFromHighlightPayload`, `toggleSelectionFromPayload` + `updateSeriesElementSelection`,
  `isHighDownDispatcher`/`setAsHighDownDispatcher`/`getHighlightDigit`, `isHighDownPayload`/
  `isSelectChangePayload`.
- **`core/actionRegister.swift`** (NEW) — registers highlight/downplay/select/unselect/toggleSelect
  (via the Phase-29 `registerAction`), invoked from `installOnce`.
- **`core/EChartsSlim.swift`** (EDIT) — `updateDirectly` (echarts.ts:1772-1866) + `callViewMethod`; the
  `doDispatchAction` isHighDown/isSelectChange/cptType branches now call `updateDirectly` (light update,
  no full pipeline). Plus the `__alive` fix (below).
- **`view/Chart.swift`** (EDIT) — un-stubbed `elSetState`/`toggleHighlight` to call the real states fns.
- **`core/ExtensionAPI.swift`** + `SlimExtensionAPI` (EDIT) — emphasis methods;
  `getViewOfComponentModel` → `ComponentView?`.

### TWO CRITICALs found + FIXED post-workflow
1. **The real blocker (caught by the new round-trip test, NOT the reviews):** `ChartView.__alive`
   defaulted `false` and was never set, so `callViewMethod`'s `view.__alive` guard rejected EVERY
   light-update dispatch — highlight/downplay reached no view (silent no-op). Fixed by marking each view
   `__alive = true` when rendered in `renderSeries`/`renderComponents`, matching upstream. This is what
   makes the whole light-update path (and hence all of Phase 30) actually work.
2. **Review CRITICAL:** `allLeaveBlur`/`blurSeries`/`blurComponent` force-unwrapped
   `getViewOfComponentModel` → crash on any viewless component (e.g. `polar` — no `"polar"` view
   factory) during a highlight/blur dispatch. Fixed structurally: `getViewOfComponentModel` now returns
   `ComponentView?` (upstream's view can be undefined) and the call sites guard `if let view` (upstream
   `if (view && view.toggleBlurSeries)`). The optional return type prevents re-introducing the `!`.

### MINORs fixed
- `Int(Double.nan)` trap in `blurSeriesFromHighlightPayload` — finite-guard → 0 (matches JS `|| 0`).
- `[Int]` index-array missed by `as? [Double]` in `toggleSelectionFromPayload` — added an `[Int]` branch.

### Deferred (documented)
- `enableHoverEmphasis` / `enterEmphasisWhenMouseOver` / `leaveEmphasisWhenMouseOut` mouse-event
  BINDING → needs the live pointer host (later phase).
- Per-view `toggleHoverEmphasis` marking series elements as highDown dispatchers: until each view opts
  its elements in, a bare `highlight` on e.g. a bar is gated off by `isHighDownDispatcher`. The engine +
  dispatch path are proven end-to-end by the test (which marks a dispatcher explicitly). The `select`
  path (no dispatcher gate) mutates state directly today.
- `blurComponent`'s `focusBlurEnabled` gate (component-highDown is unwired); state animation transitions.
- Next: `axisPointer` → `tooltip` → `dataZoom`; then the live-view host (real pointer/gesture events).

## 60. Phase 29 — Action/event substrate: the `dispatchAction` round-trip (FIRST interaction-layer phase; §5 static-first lifted)

**Goal (met):** give the port its first interaction primitive — a programmatic `dispatchAction`
round-trip — as the foundation ("Phase A step 1", see `INTERACTION_LAYER_PLAN.md`) for the interaction
components (tooltip/axisPointer/dataZoom/…). HEADLESS: no live-view host or pointer events yet.
**Clean build `buildGreen = true` (0 warnings); `swift test` — 260 executed / 0 failures / 58 skipped**
— baseline 258/0/58; +2 = the new `ZZActionDispatchTests`.

### What the round-trip does
`ec.dispatchAction(Payload(type: …))` → guard (registered? model exists? re-entrant?) → `doDispatchAction`
→ run the registered `actionInfo.action(payload, ecModel, api)` handler → for the plain update path,
re-run the EXISTING `update()`/`render()` pipeline. A re-entrant dispatch (during `update()`) is queued
in `_pendingActions` and drained by `flushPendingActions`.

### Files added / edited
- **`core/action.swift`** (NEW) — the module-global `actions` registry, `ActionInfo` /
  `ActionInfoParsed` / `ActionHandler`, `registerAction` (3 overloads collapsed faithfully:
  isFunction(arg1) collapse, createEventType lowercasing, nonRefinedEventType, `ACTION_REG` validate,
  dedup early-return), `lookupAction`, and `EChartsExtensionInstallRegisters.registerAction(...)`
  forwarders (component installs call `registers.registerAction(...)`). Upstream:
  `echarts.ts:2876-2914, 3114-3190`.
- **`core/EChartsSlim.swift`** (EDIT) — `public func dispatchAction(_:_:)` + `doDispatchAction` +
  `_pendingActions` queue + `_inEcCycle` guard + `flushPendingActions`; `DispatchActionOpt`;
  `SlimExtensionAPI.dispatchAction` override. Upstream: `echarts.ts:1574-1624, 2148-2233, 2274-2300`.
- **`core/ExtensionAPI.swift`** (EDIT) — abstract `dispatchAction`.
- **`coord/axisStatistics.swift`** (EDIT) — `resetCachePerECFullUpdate` / `resetCachePerECPrepare`
  (the idempotency fix below).

### CRITICAL found + FIXED post-workflow — `update()` was not idempotent
Exposed by the new round-trip test (not the reviews): the per-full-update axis-statistics cache
(`getCachePerECFullUpdate`) was a never-reset placeholder, so a SECOND `update()` on the same
`GlobalModel` — i.e. every `dispatchAction`-driven re-render — re-associated the same `<axis,series>`
pairs and tripped the DEV duplicate-pair assert in `associateSeriesWithAxis` (SIGTRAP crash). Fixed by
porting `resetCachePerECFullUpdate(ecModel)` (swap in a fresh cache host, orphaning the stale makeInner
records) and calling it at the very start of `update()` — matching upstream `updateMethods.update`
(echarts.ts:1892). This makes `update()` correctly re-runnable — the foundation the entire interaction
layer depends on. Safe for the 258 existing single-update tests (resetting an already-fresh cache on
the first update is a no-op).

### Deferred (documented; next phases)
- Partial-update: `updateView`/`updateLayout`/`updateVisual`/`updateTransform`/`prepareAndUpdate` all
  collapse to the full `update()` this phase (PORT-TODO).
- The emphasis/select **light-update** branch (`updateDirectly`) is a safe documented no-op — it needs
  `util/states.ts` (≈1000 lines: enter/leaveEmphasis/blur/select) → **Phase 30**. A `highlight`/`select`
  payload is accepted but currently produces no visible state change.
- The **live-view host** (a UIView/NSView owning a ZRenderKit `ZRender`+`Handler`, feeding real
  pointer/gesture events) → later phase. Until then interaction is driven programmatically.
- Next: **Phase 30** = `util/states.ts` + `updateDirectly` (make highlight/downplay/select actually
  render), then `axisPointer` → `tooltip` → `dataZoom`.

## 59. Phase 28 — Built-in dataset transforms (`filter` + `sort`) + `conditionalExpression` evaluator (PURE DATA; completes the Phase-27 dataset/transform story)

**Goal (met):** register the two built-in external transforms (`echarts:filter`, `echarts:sort`)
out-of-the-box so `dataset: { transform: { type: 'filter'|'sort', config: … } }` works WITHOUT the
user calling `registerExternalTransform`, and port their dependency `util/conditionalExpression`. This
completes the source → transform → series data path opened in Phase 27. **Clean build
`buildGreen = true` (0 warnings); `swift test` — 258 executed / 0 failures / 58 skipped** — baseline
256/0/58; +2 = the new `ZZBuiltinTransformTests`.

### Files added
- **`util/conditionalExpression.swift`** — the relational + logical expression parser/evaluator.
  Comparison ops (`lt`/`lte`/`gt`/`gte`/`eq`/`ne`/`reg`) via `RELATIONAL_EXPRESSION_OP_ALIAS_MAP` +
  `dataValueHelper.createFilterComparator`; the `and`/`or`/`not`/`true` combinators with fail-fast
  (empty-array throws) + short-circuit `evaluate()`; `RegExpEvaluator` reproducing upstream's
  always-stringify quirk. `parseConditionalExpression(config, getters)` with the caller-supplied
  `valueGetterAttrMap`/`prepareGetValue`/`getValue` plumbing.
- **`component/transform/filterTransform.swift`** — `echarts:filter`. Builds the condition
  (valueGetterAttrMap `{dimension:true}`, prepareGetValue → `upstream.getDimensionInfo` → `{dimIdx}`,
  getValue → `upstream.retrieveValueFromItem(rawItem, dimIdx)`), loops the upstream rows, pushes each
  row whose `condition.evaluate()` is true. Fail-fast: a missing condition yields an empty result, not
  the whole dataset.
- **`component/transform/sortTransform.swift`** — `echarts:sort`. asc/desc, multi-key (array config),
  the `time`/`number` `parser`, and `incomparable` min/max placement — all via the **reused**
  `dataValueHelper.SortOrderComparator` / `getRawValueParser` (not a reimplementation). Because Swift
  `sort(by:)` is not stable, items are index-decorated and the comparator tiebreaks on original index
  to reproduce upstream's stable `Array.prototype.sort`.
- **`component/transform/transformInstall.swift`** — `transformInstall(_:)` registering both built-ins
  via `registerExternalTransform`, invoked in `EChartsSlim.installOnce` (line ~649).

### CRITICAL found + FIXED post-workflow — Int-vs-Double (again)
- An integer filter threshold written as an option literal (`config: { dimension: 1, gt: 15 }`) boxes
  as Swift `Int`; the Double-only `util.isNumber` gate inside `dataValueHelper.createFilterComparator`
  rejected it, so the order ops (`lt`/`lte`/`gt`/`gte`) were silently disabled and the misconfigured
  path hit a fatal `throwError`. The translator had already routed the operand through a
  `jsNumberize(...)` coercion at the option-read boundary in `conditionalExpression.swift` but **left
  the helper undefined** (the build error). Fix: defined `jsNumberize` (Int/NSNumber → Double; Bool and
  String pass through untouched so `eq`/`reg` string semantics are unchanged). Locked by
  `ZZBuiltinTransformTests` asserting `gt: 15` keeps the 2 rows ≥ 15.

### Documented latent minor (NOT introduced here)
- `eq`/`ne` against **Int-boxed data values** flows through `dataValueHelper`'s `jsTypeof` /
  `jsStrictEquals`, which have no `Int` case → an `{ eq: 5 }` against an Int `5` data value would
  compare unequal. This is a pre-existing shared-infra edge (the filter test's data values are Double,
  so it is unexercised); left for a future `dataValueHelper` pass rather than an unreviewed change in
  this phase. Sort MINORs: invalid-config `try! throwError` traps (uncatchable vs upstream's catchable
  throw) and a differing dev-only error message on a non-string `order`/`incomparable` — all
  misconfig-only, consistent with the port's established dev-error pattern.

## 58. Phase 27 — Dataset component + transform pipeline (the data-layer of the remaining component surface; NOT §5-interaction-deferred)

**Goal (met):** land the `dataset` component and the external data-transform pipeline end-to-end, so
`option.dataset` / `datasetIndex` / `datasetId` / `seriesLayoutBy` / `sourceHeader` / `transform` /
`fromDatasetIndex` / `fromTransformResult` all work: a series with **no own `data`** reads its rows
from a dataset's `source`, and a `{ transform: … }` dataset produces a derived source consumed
downstream. **Clean build `buildGreen = true` (0 warnings); `swift test` — 256 executed / 0 failures /
58 skipped** — baseline was 254/0/58; +2 = the new `ZZDatasetProbeTests`. This is a **data-layer**
component (unlike tooltip/dataZoom/toolbox/brush/timeline it is not gated behind CONVENTIONS §5
interaction), so it is fully in-scope and actually functional.

### What registered end-to-end in `EChartsSlim`
- **`DatasetModelImpl`** — the concrete dataset `ComponentModel` (type `dataset`), conforming to the
  data-layer `DatasetModel` protocol (the forward-reference used by `sourceManager`/`sourceHelper`).
  `init` builds its own `SourceManager(self)` then `disableTransformOptionMerge(self)`;
  `optionUpdated` dirties the SourceManager — mirroring upstream lifecycle order exactly.
- **`DatasetView`** — a static shell (type `dataset`, no behavior), registered via `datasetInstall`,
  which is called **first** in `installOnce` so datasets exist before series query them.

### The transform pipeline (`data/helper/transform.swift`, NEW)
- Types `DataTransformOption` / `PipedDataTransformOption` / `ExternalDataTransform` /
  `ExternalDataTransformResultItem` / `ExternalDimensionDefinition`; the `externalTransformMap`
  registry + `registerExternalTransform`.
- `applyDataTransform` / `applySingleDataTransform` — validates the type, splits piped vs single,
  resolves upstream `Source`s, builds the `ExternalSource` wrapper
  (getRawData/getRawDataItem/count/getDimensionInfo/retrieveValue/cloneRawData), invokes the external
  transform, and wraps each result back into a `Source`. The header-concat + metaRawOption-inheritance
  branch and the number-like-string dimension resolution are ported line-for-line.

### Un-stubbed dataset branches (previously `fatalError`/PORT-TODO)
- `sourceManager.swift`: `_getUpstreamSourceManagers` (series→dataset + dataset→dataset upstream),
  `_createSource` dataset host branch (root reads `source`; non-root applies transform),
  `_applyTransform` (piped vs single + the `fromTransformResult` single-upstream guard),
  `_getSourceMetaRawOption` dataset branch, and `disableTransformOptionMerge`. **The series source
  path is unchanged and faithful (no regression).**
- `sourceHelper.swift`: `querySeriesUpstreamDatasetModel` / `queryDatasetUpstreamDatasetModels`.

### CRITICAL found + FIXED post-workflow — Int-boxed index option-read trap
- An explicit Int-literal `datasetIndex`/`fromDatasetIndex` (e.g. `series: [{ datasetIndex: 1 }]`)
  boxes as Swift `Int`; `GlobalModel.queryComponents` resolved it via `normalizeToArray<Double>`,
  whose `value as? Double` returns nil on an `Int` → **empty index array → no dataset resolved → the
  series rendered empty**. This is the documented Int-vs-Double option-read trap (same class as the
  Phase-12 radar 90° bug). **Fixed at the shared choke point `GlobalModel.queryComponents`
  (`model/Global.swift`)** with an Int/Double/NSNumber coercion of the query index — which also
  repairs **every other explicit-index component ref** (`xAxisIndex`/`polarIndex`/`gridIndex`/…) that
  flows through the same path. Locked by `ZZDatasetProbeTests` now asserting an `Int`-literal
  `datasetIndex: 1` transform chain resolves (would fail pre-fix). MINOR: stale "unreachable" comments
  in `sourceManager.swift` corrected post-workflow.

### Deferred per CONVENTIONS §5 / documented
- `DatasetView` is a static shell (no interaction). Non-built-in external transforms' object-row cast
  is a project-wide `Any?`-bridging concern (not new here). `setAsPrimitive` (used by
  `disableTransformOptionMerge`) is a no-op bridge as before.

## 57. Phase 26 — Custom series / `renderItem` (the 22nd and LAST chart type; ports ALL 22 upstream chart types; transition/animation/morph/states DEFERRED)

**Goal (met):** land the `custom` series end-to-end in `EChartsSlim` — the port's **22nd chart type**,
and the **last** one: this completes **ALL 22 of upstream's chart types**. `custom` is the
user-programmable series: rather than a fixed geometry, the option supplies a **`renderItem`
closure** that, per data item, returns a graphic-element spec, and the view materializes those
specs into real `ZRenderKit` shapes positioned through the ported coordinate systems. **Clean build
`buildGreen = true`; `swift test` — 254 executed / 0 failures / 58 skipped** — baseline was
253/0/58; +1 = the new `CustomRenderTests`; no regressions. This makes **ALL 22 upstream chart
types** ported end-to-end.

### What registered end-to-end in `EChartsSlim`
- **`CustomSeriesModel`** (type `series.custom`) — the custom series model, registered via
  `ComponentModel.registerClass`.
- **The `custom` view (`CustomView`)** — the renderItem dispatcher + element materializer.

### The renderItem dispatch + static element builders
- **The `renderItem` Swift-closure dispatch** — per data item, `CustomView` invokes the option's
  `renderItem` closure with a coord-provided `api` (the coordSys / value / size / coord helpers) and
  receives a graphic-element spec.
- **The static element builders** — one builder per returned element type (`group`, `rect`,
  `circle`, `sector`, `polygon`, `polyline`, `line`, `bezierCurve`, `arc`, `image`, `text`, …),
  each building the returned spec into a real `ZRenderKit` shape. These run **across the ported
  coordinate systems** (cartesian, polar, geo, calendar, …) — the element is positioned via the
  `api` the coord system supplies.

### Why this completes ALL 22 chart types
- With `custom` landed, every one of upstream's **22 chart types** is ported end-to-end:
  line, bar, pie, scatter, effectScatter, radar, tree, treemap, sunburst, boxplot, candlestick,
  heatmap, map, parallel, lines, graph, sankey, funnel, gauge, themeRiver, chord, and now **custom**.

### Files added
- `chart/custom/CustomSeries.swift` — `CustomSeriesModel`.
- `chart/custom/CustomView.swift` — the renderItem dispatch + the static element builders across the coord systems.
- `chart/custom/customInstall.swift` — the install/registration entry point.
- `chart/custom/customSeriesRegister.swift` — the series-type registration helper.
- Demo: `Sources/EChartsDemoGallery/Demos/custom-basic.swift`.
- Tests: `Tests/EChartsKitTests/CustomRenderTests.swift` (the +1 over the 253 baseline).

### Deferred PORT-TODOs (per CONVENTIONS §5)
- **`transition` / animation / morph** — the transition + enter/update animation + path-morph paths — DEFERRED.
- **The enter/update/leave diff** — elements are rebuilt from scratch each render, not diffed — DEFERRED.
- **`states` / emphasis** — the emphasis/blur/select state paths — DEFERRED.
- **Legacy-compat** — the legacy `renderItem` element shims — DEFERRED.

### Faithfulness reviews
- `chart/custom/CustomView.swift` — **CRITICAL-ISSUES** (2 findings).
- `chart/custom/CustomSeries.swift` — **MINOR-ISSUES** (1 finding).

Stated plainly: the `CustomView.swift` review is **CRITICAL** (2 findings). `buildGreen` is
nonetheless **true** and `swift test` is green (254/0/58). The **main loop fixes these findings
post-workflow**. This lands the 22nd and final chart type — completing **ALL 22 of upstream's chart
types** ported end-to-end.

---

## 56. Phase 25 — Matrix coordinate system (the 8th and LAST coord system: a table/grid coord; header-tree + body/corner cell pipeline; interaction DEFERRED)

**Goal (met):** land the `matrix` coordinate system end-to-end in `EChartsSlim` — the port's **8th
coordinate system** (after `cartesian2d`/grid, `radar`, `polar`, `single`, `parallel`, `calendar`,
and `geo`), and the **last** one: this completes **ALL of upstream's coordinate systems**
(cartesian/radar/polar/single/parallel/calendar/geo/matrix). Unlike the others, `matrix` is a
**table/grid** — two dimensions (x/y) whose values are header cells arranged in a (possibly nested)
header tree, plus a body region of value cells at the row×column intersections, and a top-left
corner. A `Matrix` builds the two header dimensions and projects a `[xValue,yValue]` cell coordinate
to its pixel rect; the `MatrixView` component view draws the table. **Clean build `buildGreen =
true`; `swift test` — Executed 253 tests, with 58 tests skipped and 0 failures (0 unexpected)** —
baseline 251 + 2 new `MatrixRenderTests`; no regression. This makes **8 coordinate systems** ported
end-to-end — **ALL of upstream's coordinate systems**.

### What registered end-to-end in `EChartsSlim`
- **The `matrix` coord-system creator** — `CoordinateSystemManager.register("matrix", …)` →
  `matrixCoordHelper`, which forwards to `Matrix.create` / `Matrix.dimensions` and lays the table
  out into the view box.
- **`MatrixModel`** — the matrix component model, registered via `ComponentModel.registerClass`.
- **The `"matrix"` component view factory (`MatrixView`)** — draws the header-cell + body-cell +
  corner `Rect`s and their divider `Line`s + the per-cell labels from the `Matrix` geometry.

### The table / header-tree / cell pipeline
- **`Matrix`** holds the two `MatrixDim` header dimensions (x and y) and the body/corner geometry;
  `dataToPoint`/`dataToLayout` map a `[xValue,yValue]` cell coordinate to its pixel rect by resolving
  each dimension's header cell.
- **`MatrixDim`** resolves one dimension's (possibly nested) header-cell tree: leaf/non-leaf cell
  spans, per-cell depth, and each header cell's pixel rect along that axis.
- **`MatrixBodyCorner`** supplies the body value-cell geometry (the row×column intersection rects)
  and the top-left corner cell.

### Files added
- `coord/matrix/Matrix.swift` — the `Matrix` coord system (two header dims + body/corner + `dataToPoint`/`dataToLayout`).
- `coord/matrix/MatrixDim.swift` — one header dimension's cell tree (spans, depth, per-cell rects).
- `coord/matrix/MatrixBodyCorner.swift` — the body value-cell + top-left corner geometry.
- `coord/matrix/MatrixModel.swift` — `MatrixModel`.
- `coord/matrix/matrixCoordHelper.swift` — the `matrix` coord-system creator (build + layout).
- `coord/matrix/matrixPrepareCustom.swift` — the custom-series prepare hook for the matrix coord.
- `component/matrix/MatrixView.swift` — the header/body/corner cell + divider + label render.
- Demo: `Sources/EChartsDemoGallery/Demos/matrix-basic.swift`.
- Tests: `Tests/EChartsKitTests/MatrixRenderTests.swift` (the +2 over the 251 baseline).

### Deferred PORT-TODOs (per CONVENTIONS §5)
- **All matrix interaction** — cell select/highlight, roam pan/zoom, and the tooltip/emphasis paths
  — DEFERRED (static table render only this phase).

### Faithfulness reviews
- `coord/matrix/Matrix.swift` — **FAITHFUL** (0 findings).
- `coord/matrix/MatrixDim.swift` — **MINOR-ISSUES** (2 findings).
- `coord/matrix/matrixCoordHelper.swift` — **FAITHFUL** (0 findings).
- `component/matrix/MatrixView.swift` — **MINOR-ISSUES** (2 findings).

No CRITICAL findings; `buildGreen = true`. This lands the 8th and final coordinate system —
completing **ALL of upstream's coordinate systems** (cartesian/radar/polar/single/parallel/calendar/geo/matrix).

---

## 54. Phase 23 — Geo coordinate system + GeoJSON (the 7th coord system; GeoJSON parse/Region/Geo-projection pipeline; SVG-map + roam DEFERRED)

**Goal (met):** land the `geo` coordinate system end-to-end in `EChartsSlim`, backed by GeoJSON — the
port's **7th coordinate system** (after `cartesian2d`/grid, `radar`, `polar`, `single`, `parallel`,
and `calendar`). A registered map's GeoJSON is parsed into `Region`s, held by a `Geo` instance that
projects lon/lat ↔ pixel, and drawn by the `GeoView` component view. **This UNLOCKS the map chart
(next phase)** — the map series renders on this geo coord system. **Clean build `buildGreen = true`;
`swift test` — Executed 249 tests, with 58 tests skipped and 0 failures (0 unexpected)** — baseline
247 + 2 new `GeoRenderTests`; no regressions. This makes **7 coordinate systems** ported end-to-end.

### What registered end-to-end in `EChartsSlim`
- **The `geo` coord-system creator** — `CoordinateSystemManager.register("geo", …)` → `geoCreator`,
  which reads the registered map JSON and builds `Geo` instances (forwarding to `Geo.create` /
  `Geo.dimensions`), laid out into the view box.
- **The `registerMap` API** — the map-registry entry point that parses a GeoJSON payload and stores
  the resulting `Region`s by map name, so a `geo`/`GeoModel` referencing that name resolves its shapes.
- **`GeoModel`** — the geo component model, registered via `ComponentModel.registerClass`.
- **The `"geo"` component view factory (`GeoView`)** — draws each region's boundary
  `Polygon`/`Path`s + region name labels from the `Geo`/`Region` geometry.

### The GeoJSON parse / Region / Geo-projection pipeline
- **`parseGeoJSON`** decodes a GeoJSON FeatureCollection into `Region`s: each region is a named set
  of polygon exterior + hole rings, with a precomputed bounding rect and a label/center point.
- **`Region`** holds those rings + the region rect + the label center; it is the unit the `GeoView`
  iterates to build boundary paths.
- **`Geo`** holds the region list and the projection: `dataToPoint`/`pointToData` map lon/lat ↔ pixel
  through the geo-rect → view-rect linear transform (y-flipped, as upstream). Only the **default
  linear lon/lat projection** lands this phase.

### Files added
- `coord/geo/Region.swift` — the `Region` (rings + rect + label center).
- `coord/geo/Geo.swift` — the `Geo` coord system (region list + lon/lat↔pixel projection).
- `coord/geo/geoCreator.swift` — the `geo` coord-system creator (map-registry read + `Geo` build + layout).
- `coord/geo/GeoModel.swift` — `GeoModel`.
- `coord/geo/geoJSONLoader.swift` + `coord/geo/parseGeoJSON.swift` — the `registerMap` map-registry +
  the GeoJSON FeatureCollection → `Region` parser.
- `component/geo/GeoView.swift` — the region-boundary + name-label render.
- Demo: `Sources/EChartsDemoGallery/Demos/geo-basic.swift`.
- Tests: `Tests/EChartsKitTests/GeoRenderTests.swift` (the +2 over the 247 baseline).

### Deferred PORT-TODOs (per CONVENTIONS §5)
- **`GeoSVGResource`** — the SVG-map source (map from an SVG instead of GeoJSON) — DEFERRED.
- **Roam pan/zoom** — the `RoamController` drag/wheel interaction — DEFERRED.
- **The pluggable `projection` object** — only the default linear lon/lat projection lands; a
  custom/registered projection is DEFERRED.
- **Geo `specialAreas`** — the inset/special-area repositioning — DEFERRED.

### Faithfulness reviews
- `coord/geo/Region.swift` — **MINOR-ISSUES** (2 findings).
- `coord/geo/Geo.swift` — **FAITHFUL** (0 findings).
- `coord/geo/geoCreator.swift` — **MINOR-ISSUES** (3 findings).
- `component/geo/GeoView.swift` — **FAITHFUL** (0 findings).

No CRITICAL findings; `buildGreen = true`. The **5 MINOR findings are NOT yet fixed** — to be handled
by the main loop post-workflow. This lands the 7th coordinate system and unlocks the map chart (next
phase).

---

## 53. Phase 22 — Heatmap chart (the 20th chart type; on cartesian, colored by the Phase-21 visualMap encoding; geo/large-blur + calendar paths DEFERRED)

**Goal (met):** land the `heatmap` chart end-to-end in `EChartsSlim`, on the **cartesian** coordinate
system, with each cell **colored by the Phase-21 `visualMap` encoding**. This is **the payoff of
Phase 21** — Phase 21 landed the value→visual encoder precisely so that heatmap's per-cell color has
a source; the `visualEncoding` stage stamps each datum's color and the heatmap view reads it back.
**Clean build `buildGreen = true`; `swift test` — Executed 247 tests, with 58 tests skipped and 0
failures (0 unexpected)** — baseline 246 + 1 new `HeatmapRenderTests` test; no regressions. This
makes **20 chart types** ported end-to-end.

### What registered end-to-end in `EChartsSlim`
- **`HeatmapSeriesModel`** — the heatmap series component model, registered via
  `ComponentModel.registerClass`.
- **The `"heatmap"` view factory (`HeatmapView`)** — the render layer.

### The render: cartesian colored-Rect cells
On a cartesian grid, `HeatmapView` draws one `Rect` **cell** per datum, sized to the x/y axis band,
and **colored from `getItemVisual("color")`** — the per-datum color stamped by the Phase-21
`visualEncoding` VISUAL stage (the `VisualMapping` value→visual encoder). No color computation lives
in the view; the visualMap encoding produces the color and the heatmap simply consumes it. This is
the direct payoff of the Phase-21 groundwork.

### Files added
- `chart/heatmap/HeatmapSeries.swift` — `HeatmapSeriesModel`.
- `chart/heatmap/HeatmapView.swift` — the cartesian colored-Rect cell render (color from `getItemVisual`).
- `chart/heatmap/heatmapInstall.swift` — the registration wiring.
- Demo: `Sources/EChartsDemoGallery/Demos/heatmap-basic.swift`.
- Tests: `Tests/EChartsKitTests/HeatmapRenderTests.swift` (the +1 over the 246 baseline).

### Deferred PORT-TODOs (per CONVENTIONS §5)
- **The geo-coordinate blurred `HeatmapLayer`** — the gradient / large-blur pixel path (the
  smooth-heatmap-on-geo render) is DEFERRED.
- **The large / progressive draw path** — DEFERRED.
- **The calendar-coordinate branch** (heatmap-on-calendar) — DEFERRED.

This phase lands the **cartesian colored-cell heatmap only**.

### Faithfulness reviews
- `chart/heatmap/HeatmapView.swift` — **FAITHFUL** (0 findings).
- `chart/heatmap/HeatmapSeries.swift` — **FAITHFUL** (0 findings).

No CRITICAL findings; `buildGreen = true`; nothing to fix. This lands the 20th chart type and
realizes the payoff of the Phase-21 visualMap encoding core.

---

## 52. Phase 21 — visualMap encoding core (the value→visual encoder + models + `visualEncoding` stage; the interactive control WIDGET DEFERRED)

> Insertion note: the Phase 20 banner references a `## 51. Phase 20` detail section that was
> never written (Phase 20 was integrated manually and lives as a top-of-file banner only). This
> Phase 21 section is therefore placed at the top of the detail stack, immediately before
> `## 50. Phase 19` — i.e. exactly where `## 51. Phase 20` would sit.

**Goal (met):** land the **value→visual encoding half** of `visualMap` end-to-end in `EChartsSlim` —
the machinery that maps a data value to a visual channel (color / opacity / symbolSize / …) — while
**DEFERRING the interactive control widget** (the on-screen draggable range/handle). This is the
groundwork that **UNLOCKS the heatmap chart (next phase)**, whose per-cell color is produced by a
visualMap. **Clean build `buildGreen = true`; `swift test` — 246 executed / 0 failures / 58 skipped**
(baseline 244 preserved + 2 new `VisualMapEncodingTests`); zero regressions.

### What registered end-to-end in `EChartsSlim`
- **`ContinuousVisualMapModel` + `PiecewiseVisualMapModel`** — the two visualMap component models,
  registered via `ComponentModel.registerClass` (on the shared `VisualMapModel` base).
- **The `visualMap` sub-type typeDefaulter** — resolves the bare `visualMap` type to
  `continuous` / `piecewise` (`typeDefaulter.swift`).
- **The `visualMapPreprocessor`** — the option preprocessor (normalizes the visualMap option).
- **The `visualEncoding` VISUAL stage** — the value→visual pipeline (`seriesVisualMap` /
  `visualMapVisual`) that stamps each datum's visual from the model's `VisualMapping`.
- **A minimal `VisualMapView`** — a registration placeholder only; the interactive control render
  is DEFERRED.

### The encoder: `visual/VisualMapping.swift`
`VisualMapping` is the faithful value→visual mapper — the piecewise / category / linear mapping
methods that turn a normalized data value into a visual-channel value (color, opacity, symbolSize,
…). It is what the `visualEncoding` stage drives per datum, and what the heatmap will read next phase.

### Files added
- `visual/VisualMapping.swift` — the value→visual encoder (the core).
- `visual/visualDefault.swift`, `visual/visualSolution.swift` — the visual defaulting / solution helpers.
- `component/visualMap/VisualMapModel.swift` — the shared base model.
- `component/visualMap/ContinuousModel.swift` — `ContinuousVisualMapModel`.
- `component/visualMap/PiecewiseModel.swift` — `PiecewiseVisualMapModel`.
- `component/visualMap/typeDefaulter.swift` — the `continuous`/`piecewise` sub-type defaulter.
- `component/visualMap/visualMapPreprocessor.swift` — the option preprocessor.
- `component/visualMap/visualEncoding.swift` — the `visualEncoding` VISUAL stage.
- `component/visualMap/visualMapHelper.swift`, `component/visualMap/installCommon.swift` — shared wiring.
- `component/visualMap/{VisualMapView,ContinuousView,PiecewiseView}.swift` — the minimal view
  (registration placeholder; interactive control render DEFERRED).
- `component/visualMap/visualMapAction.swift` — the action stubs (interactions DEFERRED).
- Demo: `Sources/EChartsDemoGallery/Demos/visualmap-basic.swift`.
- Tests: `Tests/EChartsKitTests/VisualMapEncodingTests.swift` (the +2 over the 244 baseline).

### Deferred PORT-TODOs (per CONVENTIONS §5)
- **The interactive control WIDGET is DEFERRED** — the draggable range handle + the range indicator
  + the hover-highlight/select interactions (`visualMapAction` select/highlight, the continuous
  drag-range interaction, the piecewise item toggle). This phase lands the models + the value→visual
  encoding + a minimal (placeholder) view only.

### Faithfulness reviews
- `visual/VisualMapping.swift` — **FAITHFUL** (2 findings).
- `component/visualMap/ContinuousModel.swift` — **FAITHFUL** (0 findings).
- `component/visualMap/PiecewiseModel.swift` — **FAITHFUL** (0 findings).
- `component/visualMap/visualEncoding.swift` — **FAITHFUL** (1 finding).

No CRITICAL findings; `buildGreen = true`. The 3 MINOR findings (2 in `VisualMapping.swift`, 1 in
`visualEncoding.swift`) are **NOT yet fixed** — they are to be handled by the main loop
post-workflow. This lands the visualMap **encoding core** that unlocks the heatmap chart next phase.

---

## 50. Phase 19 — Chord circular flow chart (COORDLESS: the 19th chart type; reuses the ported Graph + createGraphFromNodeEdge)

**Goal (met):** land the `chord` (circular flow) chart end-to-end in `EChartsSlim`, **coordless**
(box/view usage — no coordinate system, like pie/funnel/gauge, sankey, and the tree-family),
**reusing the ported `Graph` + Phase 11 `createGraphFromNodeEdge`** to build its node/edge graph.
Chord lays nodes as arcs around a circle and connects them with bezier-ribbon flow paths.
**Clean build `buildGreen = true`; `swift test` — Executed 243 tests, with 58 tests skipped and
0 failures (0 unexpected)** — up from a 242-test baseline (+1 = the new `ChordRenderTests`);
zero regressions. This makes **19 chart types** ported end-to-end.

### What registered end-to-end in `EChartsSlim`
- **`ChordSeriesModel`** — the `chord` series component model, **reusing the Phase 11
  `createGraphFromNodeEdge`** to build its node/edge `Graph`.
- **The `"chord"` view factory** → `ChordView` (coordless — no coordinate system).
- **The `chordCircularLayout` stage** — the overall chord circular layout (places node arcs around
  the circle and resolves the edge ribbon geometry).

### chord = node arc Sectors + bezier-ribbon edge Paths
`ChordView` draws the node **arc `Sector`s** (`ChordPiece`) laid around the circle, plus the
bezier-ribbon edge **`Path`s** (`ChordEdge`) — the curved flow ribbons connecting the node arcs.

### Files added
- `chart/chord/ChordSeries.swift` — `ChordSeriesModel` (reuses `createGraphFromNodeEdge`).
- `chart/chord/ChordView.swift` — the chord view factory / render (node Sectors + edge Paths).
- `chart/chord/ChordPiece.swift` — the node arc `Sector` piece.
- `chart/chord/ChordEdge.swift` — the bezier-ribbon edge `Path`.
- `chart/chord/chordLayout.swift` — the `chordCircularLayout` overall stage.
- `chart/chord/chordInstall.swift` — the registration wiring.
- Demo: `Sources/EChartsDemoGallery/Demos/chord-basic.swift`.
- Test: a new `ChordRenderTests` end-to-end render test (the +1 over the 242 baseline).

### Deferred PORT-TODOs (per CONVENTIONS §5)
- Interaction / decoration (emphasis/states, enter/update animation, label-layout niceties,
  drag/roam) deferred, as in prior chart phases.

### Faithfulness reviews
- `chart/chord/chordLayout.swift` — **MINOR-ISSUES** (1 finding). FIXED (`nodeValues[i] ?? 0` → `orZero` for JS `|| 0` NaN-shedding; NaN in a value-less link no longer collapses the whole chord).
- `chart/chord/ChordEdge.swift` — **FAITHFUL** (0 findings).
- `chart/chord/ChordView.swift` — **FAITHFUL** (0 findings).
- `chart/chord/ChordSeries.swift` — **FAITHFUL** (0 findings).

No CRITICAL findings; `buildGreen = true`. The 1 MINOR finding in `chordLayout.swift` is **NOT yet
fixed** — it is to be handled by the main loop post-workflow. This lands the **19th chart type**
ported end-to-end.

---

## 49. Phase 18 — effectScatter + lines charts (the 17th & 18th chart types; effect/ripple/large animations DEFERRED)

**Goal (met):** land the `effectScatter` and `lines` charts end-to-end in `EChartsSlim`, both
**reusing the existing coordinate systems** (no new coord system this phase). `effectScatter` renders as
**static symbols** (like scatter, minus the animated ripple); `lines` draws **straight / bezier-curve /
polyline segments between coords**. **Clean build `buildGreen = true`; `swift test` —
242 executed / 0 failures / 58 skipped** — up from a 240-test baseline (+2 = the two new render tests);
zero regressions. This makes **18 chart types** ported end-to-end.

### What registered end-to-end in `EChartsSlim`
- **`EffectScatterSeriesModel`** — the `effectScatter` series component model.
- **The `"effectScatter"` view factory** → `EffectScatterView` (reuses the existing coord systems; draws
  static symbols — the animated ripple effect is DEFERRED).
- **`LinesSeriesModel`** — the `lines` series component model.
- **The `"lines"` view factory** → `LinesView`.
- **The `linesLayout` stage** — the lines layout (resolves per-line coords).

### effectScatter = static symbols; lines = segments between coords
`EffectScatterView` places one static symbol per datum via the reused coord system's `dataToPoint` (the
ripple/effect animation is not ported). `LinesView` draws **one `Path` per line datum** — a straight
two-point segment, a single bezier curve (when a control point is present), or a multi-point polyline —
connecting the resolved coordinates.

### Files added
- `chart/effectScatter/EffectScatterSeries.swift` — `EffectScatterSeriesModel`.
- `chart/effectScatter/EffectScatterView.swift` — the static-symbol render.
- `chart/effectScatter/effectScatterInstall.swift` — the registration wiring.
- `chart/lines/LinesSeries.swift` — `LinesSeriesModel`.
- `chart/lines/LinesView.swift` — the straight/bezier/polyline per-line render.
- `chart/lines/linesLayout.swift` — the lines layout stage.
- `chart/lines/linesInstall.swift` — the registration wiring.
- Demos: `Sources/EChartsDemoGallery/Demos/effectscatter-basic.swift` + `lines-basic.swift`.
- Tests: two new end-to-end render tests (the +2 over the 240 baseline).

### Deferred PORT-TODOs (per CONVENTIONS §5)
- **effectScatter ripple** — the animated effect/ripple symbols (static symbols only this phase).
- **lines effect / moving-dot animation** — the animated moving-dot along each line.
- **lines large / progressive draw path** — the large-mode / progressive rendering.
- **lines geo / polar coord paths** — the geo and polar coordinate-system code paths.
- Interaction / decoration (emphasis/states, enter/update animation) deferred, as in prior chart phases.

### Faithfulness reviews
All four review verdicts were **FAITHFUL** with **0 findings**; no CRITICAL issues, nothing to fix:
- `chart/effectScatter/EffectScatterView.swift` — **FAITHFUL** (0 findings).
- `chart/lines/LinesView.swift` — **FAITHFUL** (0 findings).
- `chart/lines/linesLayout.swift` — **FAITHFUL** (0 findings).
- `chart/lines/LinesSeries.swift` — **FAITHFUL** (0 findings).

`buildGreen = true`. This lands the **17th and 18th chart types** ported end-to-end.

---

## 48. Phase 17 — Parallel coordinate system (the 5th coord system) + Parallel chart (brush/axis-drag DEFERRED)

**Goal (met):** land the `parallel` coordinate system + the `parallel` chart end-to-end in
`EChartsSlim`. `parallel` is the port's **5th coordinate system** — after `cartesian2d` (grid),
`radar`, `polar`, and `single`. It is a set of **N parallel axes** (upstream `coord/parallel/`); each
data item becomes a polyline that threads every axis. **Clean build `buildGreen = true`; `swift test` —
Executed 240 tests, with 58 tests skipped and 0 failures (0 unexpected)** — up from a 239-test baseline
(+1 = the new `ParallelRenderTests`); zero regressions.

### What registered end-to-end in `EChartsSlim`
- **The `parallel` coord-system creator** — `CoordinateSystemManager.register("parallel", ...)` → the
  `parallelCreator`, injecting the parallel coord system (N parallel axes). This is the **5th coordinate
  system** wired end-to-end (after `cartesian2d`, `radar`, `polar`, `single`).
- **`ParallelModel`** — the parallel coord-system component model.
- **`ParallelAxisModel`** — the parallel-axis component model (one per axis).
- **`ParallelComponentView`** — the parallel component view (draws the N parallel axes).
- **`ParallelSeriesModel`** — the `parallel` series component model.
- **The `"parallel"` view factory** → `ParallelView`.
- **The `parallelVisual` stage** — the parallel visual (style) stage.
- **The `parallelPreprocessor`** — the parallel option preprocessor.

### Parallel draws one polyline per data item across N axes
`ParallelComponentView` draws the N parallel axes laid out by the coord system; `ParallelView` renders
one **polyline `Path` per data item** threading all the axes — each datum's value on each axis fixes the
polyline's crossing point on that axis, the classic parallel-coordinates plot.

### Files added
- `coord/parallel/Parallel.swift` — the parallel coordinate system.
- `coord/parallel/ParallelAxis.swift` — the parallel axis.
- `coord/parallel/ParallelAxisModel.swift` — the parallel-axis component model.
- `coord/parallel/parallelCreator.swift` — the coord-system creator/registration.
- `coord/parallel/ParallelModel.swift` — the parallel coord-system component model.
- `coord/parallel/parallelPreprocessor.swift` — the parallel option preprocessor.
- `component/parallel/ParallelComponentView.swift` — the parallel component view (N axes).
- `chart/parallel/ParallelSeries.swift` — `ParallelSeriesModel`.
- `chart/parallel/ParallelView.swift` — the per-item polyline render.
- `chart/parallel/parallelVisual.swift` — the parallel visual (style) stage.
- `chart/parallel/parallelInstall.swift` — the registration wiring.
- Demo: `Sources/EChartsDemoGallery/Demos/parallel-basic.swift`.
- Test: a new Parallel end-to-end render test — `ParallelRenderTests` (the +1 over the 239 baseline).

### Deferred PORT-TODOs (per CONVENTIONS §5 — static parallel render only)
- Brush / areaSelect / axis-drag / roam interaction deferred, as in prior chart phases.
- Interaction / decoration (emphasis/states, enter/update animation) deferred.

### Faithfulness reviews
All four review verdicts were **FAITHFUL** with **0 findings**; no CRITICAL issues, nothing to fix:
- `coord/parallel/Parallel.swift` — **FAITHFUL** (0 findings).
- `chart/parallel/ParallelView.swift` — **FAITHFUL** (0 findings).
- `component/parallel/ParallelComponentView.swift` — **FAITHFUL** (0 findings).
- `coord/parallel/ParallelModel.swift` — **FAITHFUL** (0 findings).

`buildGreen = true`. This lands the **5th coordinate system** and the **16th chart type** ported
end-to-end.

---

## 47. Phase 16 — Single coordinate system (the 4th coord system) + ThemeRiver streamgraph chart

**Goal (met):** land the `single` coordinate system + the `themeRiver` (streamgraph) chart end-to-end
in `EChartsSlim`. `single` is the port's **4th coordinate system** — after `cartesian2d` (grid),
`radar`, and `polar`. It is a **single one-dimensional axis** (upstream `coord/single/`), the coord
system ThemeRiver lays its stacked river bands along. **Clean build `buildGreen = true`; `swift test` —
Executed 239 tests, with 58 tests skipped and 0 failures (0 unexpected)** (baseline was 238/0/58; +1 =
the new `ThemeRiverRenderTests`; no regressions).

### What registered end-to-end in `EChartsSlim`
- **The `single` coord-system creator** — `CoordinateSystemManager.register("single", ...)` → the
  `singleCreator`, injecting the single coord system (a single one-dimensional axis). This is the
  **4th coordinate system** wired end-to-end (after `cartesian2d`, `radar`, `polar`).
- **`SingleAxisModel`** — the single-axis component model.
- **`SingleAxisView`** — the single-axis component view (draws the axis line / ticks / labels).
- **`ThemeRiverSeriesModel`** — the `themeRiver` series component model.
- **The `"themeRiver"` view factory** → `ThemeRiverView`.
- **The `themeRiverLayout` overall (layout) stage** — positions the stacked river bands along the
  single axis.

### ThemeRiver draws smooth stacked river bands (streamgraph)
`ThemeRiverView` renders a **streamgraph**: `themeRiverLayout` stacks each series layer and computes its
band boundary along the single axis; the view draws one smooth band per layer (the classic river/stream
shape), each band's thickness proportional to its value.

### Files added
- `coord/single/Single.swift` — the single coordinate system.
- `coord/single/SingleAxis.swift` — the single axis.
- `coord/single/SingleAxisModel.swift` — the single-axis component model.
- `coord/single/singleCreator.swift` — the coord-system creator/registration.
- `coord/single/singleAxisHelper.swift` — the single-axis helper.
- `coord/single/singlePrepareCustom.swift` — custom-series prepare hook.
- `component/axis/SingleAxisView.swift` — the single-axis component view.
- `chart/themeRiver/ThemeRiverSeries.swift` — `ThemeRiverSeriesModel`.
- `chart/themeRiver/ThemeRiverView.swift` — the streamgraph river-band render.
- `chart/themeRiver/themeRiverLayout.swift` — the stacked-band layout stage.
- `chart/themeRiver/themeRiverInstall.swift` — the registration wiring.
- Demo: `Sources/EChartsDemoGallery/Demos/themeriver-basic.swift`.
- Test: a new ThemeRiver end-to-end render test — `ThemeRiverRenderTests` (the +1 over the 238 baseline).

### Deferred PORT-TODOs (per CONVENTIONS §5 — static themeRiver render only)
- Interaction / decoration (emphasis/states, enter/update animation, label-layout niceties) deferred,
  as in prior chart phases.

### Faithfulness reviews
All four review verdicts were **FAITHFUL** with **0 findings**; no CRITICAL issues, nothing to fix:
- `coord/single/Single.swift` — **FAITHFUL** (0 findings).
- `chart/themeRiver/themeRiverLayout.swift` — **FAITHFUL** (0 findings).
- `chart/themeRiver/ThemeRiverView.swift` — **FAITHFUL** (0 findings).
- `component/axis/SingleAxisView.swift` — **FAITHFUL** (0 findings).

`buildGreen = true`. This lands the **4th coordinate system** and the **15th chart type** ported
end-to-end.

---

## 46. Phase 15 — Sankey flow chart (coordless — the 14th chart type, reusing Graph + createGraphFromNodeEdge)

**Goal (met):** land the `sankey` (flow) chart end-to-end in `EChartsSlim`. Sankey is **coordless**
(box/view usage — no coordinate system, like `pie`/`funnel`/`gauge` and the tree-family charts): the
view lays out its own node/edge geometry from the series data rather than reading points back from a
coord system. It **reuses the Phase 11 `Graph` port + `createGraphFromNodeEdge`** to build its
node/edge graph from the node+edge data. **Clean build `buildGreen = true`; `swift test` — Executed 238
tests, with 58 tests skipped and 0 failures (0 unexpected)** (baseline was 237/0/58; +1 = the new
`SankeyRenderTests`).

### What registered end-to-end in `EChartsSlim`
- **`SankeySeriesModel`** — the `sankey` series component model. It **reuses `createGraphFromNodeEdge`**
  (the Phase 11 helper) to build its node/edge `Graph` from the series' node + edge data — no new graph
  data structure was needed.
- **The `"sankey"` view factory** → `SankeyView`. Sankey registers **coordless** (no coordinate-system
  usage registration) — the view computes its own node/edge layout.
- **The `sankeyLayout` + `sankeyVisual` overall stages** — the layout stage positions the nodes/edges;
  the visual stage assigns node/edge colors.

### SankeyView draws node Rects + bezier-ribbon edge Paths
`SankeyView` builds the sankey directly: each node becomes a **`Rect`**, and each edge becomes a
**bezier-ribbon `Path`** (the curved flow ribbon connecting the source node's right edge to the target
node's left edge, its band width proportional to the edge value).

### Files added
- `chart/sankey/SankeySeries.swift` — `SankeySeriesModel` (reusing `createGraphFromNodeEdge`).
- `chart/sankey/SankeyView.swift` — the sankey render (node `Rect`s + bezier-ribbon edge `Path`s).
- `chart/sankey/sankeyLayout.swift` — the node/edge layout stage.
- `chart/sankey/sankeyVisual.swift` — the node/edge visual (color) stage.
- `chart/sankey/sankeyInstall.swift` — the registration wiring.
- Demo: `Sources/EChartsDemoGallery/Demos/sankey-basic.swift` (registered in `Registry.swift`).
- Test: a new sankey end-to-end render test — `SankeyRenderTests` (the +1 over the 237 baseline).

### Deferred PORT-TODOs (per CONVENTIONS §5 — static sankey render only)
- Interaction / decoration (emphasis/states, enter/update animation, label-layout niceties, node
  drag/roam) deferred, as in prior chart phases.

### Faithfulness reviews
All three review verdicts were **FAITHFUL** with **0 findings**; no CRITICAL issues, nothing to fix:
- `chart/sankey/sankeyLayout.swift` — **FAITHFUL** (0 findings).
- `chart/sankey/SankeyView.swift` — **FAITHFUL** (0 findings).
- `chart/sankey/SankeySeries.swift` — **FAITHFUL** (0 findings).

`buildGreen = true`. This is the **14th chart type** ported end-to-end.

## 45. Phase 14 — Gauge chart (coordless — the 13th chart type)

**Goal (met):** land the `gauge` chart end-to-end in `EChartsSlim`. Gauge is **coordless** (box/view
usage — no coordinate system, like `pie`/`funnel` and the tree-family charts): the view lays out its own
radial geometry from the series option rather than reading points back from a coord system. **Clean build
`buildGreen = true`; `swift test` — Executed 237 tests, with 58 tests skipped and 0 failures (0 unexpected)
in 0.285s** (baseline was 236; +1 = the new gauge end-to-end render test).

### What registered end-to-end in `EChartsSlim`
- **`GaugeSeriesModel`** — the `gauge` series component model.
- **The `"gauge"` view factory** → `GaugeView`. Gauge registers coordless (no coordinate-system usage
  registration) — the view computes its own center/radius/angle frame.

### GaugeView draws the whole gauge directly (no separate axis component)
Unlike the cartesian/polar charts, there is no separate axis component view — `GaugeView` builds every
part of the gauge itself: the **axis arc** (the colored segment band), the **split-lines**, the **ticks**,
the **tick labels**, the **pointer/needle**, the **anchor** (center cap), the **progress arc**, and the
**title + detail** text blocks. A custom needle shape, **`PointerPath`**, supplies the pointer geometry
(the tapered-needle path).

### Files added
- `chart/gauge/GaugeSeries.swift` — `GaugeSeriesModel`.
- `chart/gauge/GaugeView.swift` — the full gauge render (axis arc / split-lines / ticks / labels /
  pointer / anchor / progress / title / detail).
- `chart/gauge/PointerPath.swift` — the custom pointer/needle shape.
- Demo: `Sources/EChartsDemoGallery/Demos/gauge-basic.swift` (registered in `Registry.swift`).
- Test: a new gauge end-to-end render test (the +1 over the 236 baseline).

### Deferred PORT-TODOs (per CONVENTIONS §5 — static gauge render only)
- Interaction / decoration (emphasis/states, enter/update animation, label-layout niceties) deferred, as
  in prior chart phases.

### Faithfulness reviews
All four review verdicts were **FAITHFUL** with **0 findings**; no CRITICAL issues, nothing to fix:
- `chart/gauge/GaugeView.swift` — **FAITHFUL** (0 findings).
- `chart/gauge/GaugeView.swift` — **FAITHFUL** (0 findings) [reviewed twice].
- `chart/gauge/PointerPath.swift` — **FAITHFUL** (0 findings).
- `chart/gauge/GaugeSeries.swift` — **FAITHFUL** (0 findings).

`buildGreen = true`. This is the **13th chart type** ported end-to-end.

## 44. Phase 13 — Polar coordinate system + angle/radius axis component views (the SECOND non-cartesian coord system)

**Goal (met):** land the `polar` coordinate system and its angle/radius axis component views, and
make `ScatterView` render on polar. This is the port's SECOND non-cartesian coordinate system — after
Phase 12's `radar`, and unlike every earlier cartesian (`grid`/`cartesian2d`) coord system. **Clean
rebuild `buildGreen = true`, 0 warnings; `swift test` 236 executed / 0 failures (0 unexpected) / 58
skipped** (baseline was 235; +1 = the new polar end-to-end render test).

### What registered end-to-end in `EChartsSlim`
- **Polar coordinate system (the milestone):** `CoordinateSystemManager.register("polar", ...)` wired
  to `polarCreator`, which injects the polar coord system into the coord-system list AND associates its
  angle/radius axes so their scale extents are computed from series data. This is the second coord
  system registered that is NOT `grid`/`cartesian2d`.
- **Polar component models:** `PolarModel` (the `polar` component) plus the `angleAxis` and `radiusAxis`
  axis component models (`PolarAxisModel`), holding the two axes that a polar coord system spans.
- **Two axis component views:** `AngleAxisView` + `RadiusAxisView` — the angle-axis / radius-axis
  component views (axis lines, split-lines/areas, ticks, labels for the polar frame).

### ScatterView made polar-aware (implemented and verified end-to-end)
`ScatterView.render` now branches by coord type: the existing **Cartesian2D path is unchanged**, and a
NEW **Polar branch** maps data dims by coord dim name (radius = dim0, angle = dim1 per
`polarDimensions`) and places each datum via `Polar.dataToPoint([radiusVal, angleVal])` — the faithful
inline of upstream `layout/points.ts`'s generic `map(coordSys.dimensions, data.mapDimension)` +
`dataToPoint`. Point computation was factored into a per-index closure so the symbol-build / color /
add loop is shared between the two branches. Series must set `coordinateSystem:"polar"` (scatter
defaults to `cartesian2d`); `polarCreator` injects the coord sys + associates axes for scale extents.
The e2e test asserts all 10 polar data points produce finite-positioned symbol `Path`s (name `"item"`),
confirming `dataToPoint` works end-to-end.

### Files added
- `coord/polar/`: `Polar.swift` (the `Polar` coord system), `AngleAxis.swift`, `RadiusAxis.swift`,
  `PolarModel.swift` (the `polar` component model), `PolarAxisModel.swift` (`angleAxis`/`radiusAxis`
  models), `polarCreator.swift` (the coord-system creator), `prepareCustom.swift`.
- `component/axis/`: `AngleAxisView.swift`, `RadiusAxisView.swift` (the two polar axis component views).
- Demo: `Sources/EChartsDemoGallery/Demos/polar-basic.swift` (registered in `Registry.swift`).
- Test: a new polar end-to-end render test (the +1 over the 235 baseline).
- Touched: `chart/scatter/ScatterView.swift` (the Polar branch), `core/EChartsSlim.swift`
  (coord-system + model + axis-view registration).

### Deferred PORT-TODOs (per CONVENTIONS §5 — static polar render only)
- Interaction / decoration (roam, emphasis/states, labels, enter/update animation) deferred, as in
  prior chart phases.

### Faithfulness reviews
- `coord/polar/Polar.swift` — **FAITHFUL** (0 findings).
- `coord/polar/polarCreator.swift` — **FAITHFUL** (0 findings).
- `component/axis/AngleAxisView.swift` — **MINOR-ISSUES** (2 findings). FIXED.
- `component/axis/RadiusAxisView.swift` — **MINOR-ISSUES** (1 finding). FIXED (+ a 4th, same-class, the review missed here).
`buildGreen = true`; no CRITICAL findings. **All findings FIXED post-workflow:**
- **splitLine/splitArea modulo-by-zero crash** (AngleAxisView + RadiusAxisView): `lineCount % lineColors.count`
  / `% areaColors.count` traps in Swift when an explicit `color: []` makes the array empty (upstream JS
  `n % 0` = NaN → the NaN bucket is skipped by the length-based batch loop, i.e. draws nothing). Guarded
  with `if …isEmpty { return }` in both views (the review only flagged AngleAxisView; the same bug was in
  RadiusAxisView's splitLine + splitArea and was fixed too).
- **Int-vs-Double style drop** in the shared `pathStyleFromDict` bridge (Angle/Radius/RadarComponentView):
  `lineWidth`/`opacity`/`shadow*`/`lineDashOffset`/`miterLimit` read via `as? Double` dropped Int-boxed
  option values → replaced with a `styleNum` (Int|Double|NSNumber→Double) coercion across all three copies.

## 43. Phase 12 — Radar chart + radar coordinate system (the FIRST non-cartesian coord system wired)

**Goal (met):** land the `radar` coordinate system and a radar chart vertical that registers
end-to-end in `EChartsSlim`. This is the port's FIRST non-cartesian coordinate system — every
prior wired coord system was cartesian (`grid`/`cartesian2d`). **Clean build `buildGreen = true`, 0
warnings; `swift test` 235 executed / 0 failures (0 unexpected) / 58 skipped** (baseline was 233;
+2 = the radar end-to-end render test + a `RadarCoordTests` coord oracle).

**Post-workflow fix — the recurring Int-vs-Double option-read trap (5 review findings, all fixed):**
the four review findings on `Radar.swift` (1 CRITICAL, 1 MEDIUM, 1 LOW) and two on `RadarModel.swift`
were all the same defect — `radarModel.get("<num>") as? Double` returns `nil` when the option is an
`Int` literal (which `[String: Any]` defaultOptions use, e.g. `"startAngle": 90`), silently dropping
the value. The CRITICAL case set `startAngle` to `0` instead of `π/2`, rotating EVERY radar 90°. Fixed
with a `radarNumOpt` (`Int`/`Double`/`NSNumber` → `Double`) coercion at every option-number read
(`startAngle`, `splitNumber`, `radarIndex`, indicator `min`/`max`), and locked by `RadarCoordTests`
(`axis[0].angle == π/2` under the default `startAngle`). `RadarView`/`RadarComponentView` were FAITHFUL.

### What registered end-to-end in `EChartsSlim`
- **Radar coordinate system (the milestone):** `CoordinateSystemManager.register("radar", RadarCoordinateSystemCreator())`
  — a thin creator mirroring `GridCoordinateSystemCreator` that forwards to `Radar.create`/`Radar.dimensions`. `Radar` owns N `IndicatorAxis` instances (one per indicator),
  a center/radius, and `dataToPoint`/`coordDimToDataDim`/`pointToData` over the polar-style indicator
  fan. This is the first coord system registered that is NOT `grid`/`cartesian2d`.
- **RadarModel (component):** `ComponentModel.registerClass(RadarModel)` — the `radar` component model
  holds the indicator list + center/radius/shape (`polygon`/`circle`) + splitNumber; `RadarComponentView`
  draws the indicator axes, split-lines, split-areas, and name labels.
- **RadarSeriesModel + view:** `ComponentModel.registerClass(RadarSeriesModel)` + a `"radar"` view
  factory (`RadarView`), mirroring the minimal `chart/radar/install.ts`.
- **Layout:** the `radarLayout` stage runs in `render`; each series datum's per-indicator points are
  read back from the `Radar` coord system (`dataToPoint` over the N indicator axes).

### Files added
- `coord/radar/`: `Radar.swift` (the `Radar` coord system), `IndicatorAxis.swift` (per-indicator axis),
  `RadarModel.swift` (the `radar` component model), plus radar `install`.
- `chart/radar/`: `RadarSeries.swift` (`RadarSeriesModel`), `RadarView.swift`, `radarLayout.swift`.
- `component/radar/`: `RadarComponentView.swift` (indicator axes / split-lines / split-areas / labels).
- Demo: `Sources/EChartsDemoGallery/Demos/radar-basic.swift` (registered in `Registry.swift`).
- Test: a new radar end-to-end render test (the +1 over the 233 baseline).
- Touched: `core/EChartsSlim.swift` (coord-system + model + view + layout-stage registration).

### Deferred PORT-TODOs (per CONVENTIONS §5 — static radar render only)
- **Draw-helper infra:** `SymbolDraw` (the incremental symbol draw helper) not ported — `RadarView`
  builds node symbols from scratch instead.
- **Interaction / decoration:** roam, emphasis/states (`util/states`), labels, and enter/update
  animation are all deferred.

### Faithfulness reviews
- `coord/radar/Radar.swift` — **CRITICAL-ISSUES** (3 findings). Build is green, but this file carries
  UNRESOLVED critical findings and should be revisited before radar is trusted for production geometry.
- `coord/radar/RadarModel.swift` — **MINOR-ISSUES** (2 findings).
- `chart/radar/RadarView.swift` — **FAITHFUL** (0 findings).
- `component/radar/RadarComponentView.swift` — **FAITHFUL** (0 findings).
`buildGreen = true`, but NOTE: `Radar.swift` has CRITICAL findings still open.

## 42. Phase 11 — Graph / network chart (`data/Graph.ts` port + graph vertical, circular + simple layouts; force layout DEFERRED)

**Goal (met):** land the `data/Graph.ts` data structure and a graph (network) chart vertical that
registers end-to-end in `EChartsSlim` with the two static layouts — CIRCULAR and SIMPLE (`none`).
Force layout is DEFERRED. **Clean-from-scratch `rm -rf .build && swift build` = 0 warnings, Build
complete; `swift test` 233 executed / 0 failures (0 unexpected) / 58 skipped** (baseline was
232 executed / 0 failures / 58 skipped; +1 is the new graph render test). `buildGreen = true`.
Graph is coordless (box/view usage): `GraphView` reads each node's `[x,y]` and each edge's point
list back from whichever layout stage self-selected on the `layout` option.

### What registered end-to-end in `EChartsSlim`
- **GraphSeriesModel:** `ComponentModel.registerClass(GraphSeriesModel)` + a `"graph"` view factory
  (`GraphView`), mirroring the minimal `chart/graph/install.ts`.
- **Layout (two self-gating OVERALL stage handlers):** `graphCircularLayoutStageHandler.overallReset`
  (runs for `layout:'circular'`) and `graphSimpleLayoutStageHandler.overallReset` (runs for
  `layout:'none'`/coord-sys). Each self-gates to a no-op unless its `layout` value matches, so both
  are invoked in `render` and at most one does work.
- **Processor:** `graphCategoryFilterStageHandler.overallReset` (`categoryFilter`) — filters graph
  nodes by legend selection, self-gating to a no-op when no legend component is present. Runs BEFORE
  the layout stage (layout reads the filtered data).
- **Visual (two stage handlers):** `graphCategoryVisualStageHandler` colors nodes, then
  `graphEdgeVisualStageHandler` colors edges FROM the node fill. Both run via the visual stages in
  `render` after the layout handlers.

### The graph link wiring
- **`data/SeriesData.swift`:** the pre-Graph `SeriesData.graph` placeholder retyped `AnyObject?`→`Graph?`
  (matches upstream `graph?: Graph`), now that the sibling `data/Graph.swift` port exists.
- **`data/helper/linkSeriesData.swift` — `linkSingle` graph + edgeData arms:** the shared-struct linker
  grew the `graph` cases alongside the existing `tree` cases — `opt.structAttr == "graph"` casts the
  shared `LinkableStruct` and sets `data.graph`; the back-reference arm sets `graph.data` for the main
  `data` attr and `graph.edgeData` for the `edgeData` attr. Graph (like Tree) is SHARED, not cloned,
  across a `SeriesData` and its shallow clones.

### Files added
- `data/Graph.swift` (`Graph`/`GraphNode`/`GraphEdge` — addNode/addEdge/getEdge(Direction)/eachNode/
  eachEdge/breadthFirstTraverse/updateNodeAndEdgeState/degree bookkeeping, through the real `SeriesData`
  node+edge data pipeline).
- `chart/graph/`: `GraphSeries.swift` (`GraphSeriesModel`), `GraphView.swift`, `circularLayout.swift` +
  `circularLayoutHelper.swift`, `simpleLayout.swift` + `simpleLayoutHelper.swift`, `categoryFilter.swift`,
  `categoryVisual.swift`, `edgeVisual.swift`, `adjustEdge.swift`, `graphHelper.swift`, `createView.swift`.
- `chart/helper/`: `createGraphFromNodeEdge.swift`, `multipleGraphEdgeHelper.swift`.
- Demo: `Sources/EChartsDemoGallery/Demos/graph-basic.swift` (registered in `Registry.swift`).
- Test: `testGraphRendersNodesAndEdges` added to
  `Tests/EChartsKitTests/HierarchicalChartsRenderTests.swift`.
- Touched: `core/EChartsSlim.swift` (registration + stage wiring), `data/SeriesData.swift`
  (`graph` retype), `data/helper/linkSeriesData.swift` (graph/edgeData arms).

### Deferred PORT-TODOs (per CONVENTIONS §5 — static circular/simple render only)
- **Force layout:** `forceLayout` + `forceHelper` (velocity/gravity/repulsion iteration) not ported;
  `layout:'force'` is unsupported this phase.
- **Draw-helper infra:** `SymbolDraw` / `LineDraw` (the incremental symbol + line draw helpers) not
  ported — `GraphView` builds node symbols + edge lines from scratch instead.
- **Interaction / decoration:** roam (RoamController pan/zoom), node drag, emphasis/states
  (`util/states`), labels, and edge effect (effect-line / `effectSymbol`) are all deferred.

### Faithfulness reviews
- `data/Graph.swift` — **MINOR-ISSUES** (2 findings).
- `chart/graph/circularLayoutHelper.swift` — **FAITHFUL** (0 findings).
- `chart/helper/createGraphFromNodeEdge.swift` — **FAITHFUL** (0 findings).
- `chart/graph/GraphView.swift` — **FAITHFUL** (0 findings).
No CRITICAL findings; `buildGreen = true`.

## 41. Phase 10 — Tree-family charts (sunburst wired end-to-end + treemap + tree verticals)

**Goal (met):** finish wiring the tree-family charts so all three hierarchical types render
end-to-end. The Phase 9 sunburst render layer (STAGED, not slim-wired) is now registered and
driven from `render`, and two new verticals — `chart/treemap/` and `chart/tree/` — land and
register alongside it. **`swift build` GREEN, `swift test` 232 executed / 0 failures / 58 skipped**
(baseline 229 + 3 new hierarchical render tests; no regression). `buildGreen = true`. All three
charts are coordless (hierarchical / box-like usage, like pie): each View reads its per-node
geometry back from a dedicated layout stage.

### What registered end-to-end in `EChartsSlim`
- **Sunburst (now wired — was staged in §40):** `ComponentModel.registerClass(SunburstSeriesModel)`
  + a `"sunburst"` view factory (`SunburstView`) + the `sunburstLayoutStageHandler.overallReset` and
  `sunburstVisualStageHandler.overallReset` OVERALL stages run in `render`. Sunburst has no cartesian
  coord; `SunburstView` reads per-node sector angle/radius from the layout stage.
- **Treemap (new):** `TreemapSeriesModel` + a `"treemap"` view factory (`TreemapView`) + `treemapLayout`
  (a SERIES_STAGE_TASK whose `reset` computes each node's rect + area/isInView/invisible) + `treemapVisual`
  (a SERIES_STAGE_TASK whose `reset` colors each node FROM that layout — like candlestick, the visual READS
  the layout). Both run via `runSeriesStageHandler` in `render`.
- **Tree (new):** `TreeSeriesModel` + a `"tree"` view factory (`TreeView`) + `treeLayout` (a bare 2-arg
  OVERALL layout fn computing each node's x/y via the non-layered tidy-tree walk, like pie/sunburst layout)
  + `treeVisualStageHandler.overallReset` (per-node symbol colors). `TreeView` reads the per-node x/y back.

### Files added
- `chart/treemap/`: `TreemapSeries.swift` (`TreemapSeriesModel` + level models), `TreemapView.swift`,
  `treemapLayout.swift`, `treemapVisual.swift`, `Breadcrumb.swift`.
- `chart/tree/`: `TreeSeries.swift` (`TreeSeriesModel`), `TreeView.swift`, `treeLayout.swift`,
  `treeVisual.swift` (`treeVisualStageHandler`), `layoutHelper.swift`, `traversalHelper.swift`.
- Demos: `Sources/EChartsDemoGallery/Demos/sunburst-basic.swift`, `treemap-basic.swift`, `tree-basic.swift`
  (registered in `Registry.swift`).
- Tests: `Tests/EChartsKitTests/HierarchicalChartsRenderTests.swift` (3: `testSunburstRendersSectors`,
  `testTreemapRendersRects`, `testTreeRendersNodesAndEdges`).
- Touched: `core/EChartsSlim.swift` (registration + stage wiring), `data/SeriesData.swift`.

### Deferred PORT-TODOs (per CONVENTIONS §5 — static render only)
- **Actions:** sunburst rollup/highlight (`sunburstAction`), treemap drill/zoom/roam
  (`treemapAction` + RoamController pan/zoom, node click / drill re-root / windowOpen link), tree roam.
- **Animation:** enter/update/remove transitions (replaced by static from-scratch rebuild, same as the
  Line/Pie/Funnel/Sunburst views); treemap fade-out-to-corner / drill re-root transitions.
- **Emphasis/states:** `util/states` (high-down dispatch, `Z2_EMPHASIS_LIFT`) not ported; DataDiffer diff,
  `makeStyleMapper` treemap-custom option→style mapping, `chart/helper/treeHelper` also deferred.

### Faithfulness reviews
- `chart/treemap/treemapLayout.swift` — **FAITHFUL** (0 findings).
- `chart/tree/treeLayout.swift` — **FAITHFUL** (0 findings).
- `chart/tree/TreeSeries.swift` — **FAITHFUL** (0 findings).
- `chart/treemap/TreemapView.swift` — **MINOR-ISSUES** (1 finding).
No CRITICAL findings; `buildGreen = true`.

## 40. Phase 9 — Tree data structure + Sunburst render layer (STAGED)

**Goal (partially met — staged, not yet slim-wired):** land the `data/Tree.ts` data structure and
the `chart/sunburst/` render layer so a future integration step can register sunburst end-to-end.
**`swift build` GREEN (0 warnings), `swift test` 229 executed / 0 failures / 58 skipped** (+6 new
`TreeUnitTests`, no regression). The Tree data structure is COMPLETE and unit-tested; the sunburst
render layer is PORTED + faithfulness-reviewed but NOT registered in `EChartsSlim` (no end-to-end
render yet).

### Files landed
- `data/Tree.swift` (`Tree` + `TreeNode`) — buildHierarchy/`createTree`, `updateDepthAndHeight`
  (`height = maxChildHeight + 1`, so a leaf has height 1), `eachNode` (preorder/postorder + truthy-
  return subtree-suppress; string/function/options arg normalization), `getNodeById`, `contains`,
  `getAncestors`/`getAncestorsIndices`/`getDescendantIndices`, `isAncestorOf`/`isDescendantOf`,
  `getValue` (reads the `value` dim through the real `SeriesData` store), `update`,
  `getNodeByDataIndex`, `getLevelModel`, `setLayout`/`getLayout`/`clearLayouts`.
- `data/helper/linkSeriesData.swift` — `linkSeriesData`/`transferInjection` (wires `data.tree`).
- `chart/sunburst/` — `SunburstSeries.swift` (`SunburstSeriesModel` + level models + `getViewRoot`),
  `SunburstView.swift`, `SunburstPiece.swift`, `sunburstLayout.swift` (angle/radius geometry),
  `sunburstVisual.swift` (per-node palette fill), `sunburstInstall.swift` (commented install surface).
- `chart/helper/sectorHelper.swift`; `ZRenderKit/Graphic/Shape/Sector.swift` (+3 lines).

### Closeout fixes (made it compile clean + faithful)
- **`SeriesData.tree` retyped** `AnyObject?` → `Tree?` (was a pre-Tree placeholder; matches upstream
  `tree?: Tree`). `linkSeriesData` assigns a `Tree` into it; the 4 sunburst read sites now type-check.
- **IUO-bound-to-`let` Optional-inference gotcha** at every `.root` / `hostTree.data` binding
  (`let x = tree.root` infers `TreeNode?` from the IUO) → added explicit `: TreeNode` / `: SeriesData`
  annotations. Also switched `data.tree as? Tree` guards to plain `guard let` now that `tree` is typed.
- **Typed `eachNode` callback** — the closure must be `(TreeNode) -> Any?` (the `TreeTraverseCallback`)
  to pass as the `Any?` options/cb arg; annotated + `return nil` to continue traversal.
- **Two faithfulness-review findings fixed** (both files reviewed `MINOR-ISSUES`, geometry/algorithms
  byte-faithful otherwise): (1) `TreeNode.getValue` used nil-only `?? "value"`; upstream is JS-falsy
  `dimension || 'value'` (also `0`/`""`) → now uses a `jsTruthy` guard. (2) the custom-comparator
  `sort` branch used Swift's non-stable `sort(by:)`; ES2019 `Array.prototype.sort` is stable → added an
  original-index tie-break so equal-ranked nodes keep input order.
- **`install.swift` basename collision** — SwiftPM flattens per-file object names, so `boxplot/install.swift`
  + `sunburst/install.swift` both emit `install.swift.o` (`multiple producers` build error). Renamed both
  to `boxplotInstall.swift` / `sunburstInstall.swift`; this is the convention for future per-chart installs.

### Deferred (the next step to make sunburst actually render)
- **Slim registration + gallery demo** — sunburst is coordless (like pie): register `SunburstSeriesModel`
  + a `sunburst` view factory + the `sunburstLayoutStageHandler`/`sunburstVisualStageHandler` stages in
  `EChartsSlim`, add a `sunburst-basic` demo, and verify vs echarts.js.
- **`sunburstAction`** (rollup/highlight actions), emphasis/states, and enter/update animation — PORT-TODO
  per CONVENTIONS §5 (static render only).

### Tests
- `TreeUnitTests.swift` (6, hand-authored oracle — upstream ships NO Jest spec for Tree/sunburst, only
  HTML visual tests + data fixtures): hierarchy + depth/height, preorder/postorder traversal, preorder
  subtree-suppress, ancestor/containment queries, and `getValue` read-back through the data pipeline.

## 39. Phase 8 — new chart types (funnel + candlestick + boxplot)

**Goal (met, in full):** land three new chart verticals — `funnel`, `candlestick`, and `boxplot` —
Model → layout → visual → View, and register all three end-to-end in `EChartsSlim`. **Nothing is
blocked this phase:** every type renders through the real layout + visual stages. **`swift build`
GREEN (0 warnings), `swift test` 220 executed / 0 failures / 58 skipped** (no regression). Per
CONVENTIONS §5 (STATIC RENDER ONLY), emphasis/states, enter/update animation, labels, and the
large/progressive draw path are deferred as in-file PORT-TODOs; the diff-based enter/update/remove is
replaced by a from-scratch group rebuild each render (the same deliberate deviation Line/Pie/Funnel
views use).

### Registered in `EChartsSlim` (live end-to-end)
- [x] **`funnel`** — `FunnelSeriesModel` + `funnelLayout`/`funnelLayoutStageHandler` (layout stage) +
      `FunnelView` view factory. Coordless (`coordinateSystemUsage:'box'`).
- [x] **`candlestick`** — `CandlestickSeriesModel` + `candlestickLayout` (layout stage) +
      `candlestickVisual` (visual stage) + `CandlestickView` view factory + the `'k' → 'candlestick'`
      series-type preprocessor + `registerCandlestickAxisHandlers`.
- [x] **`boxplot`** — `BoxplotSeriesModel` + `boxplotLayout` (layout stage) + `boxplotVisual` (visual
      stage) + `BoxplotView` view factory + `registerBoxplotAxisHandlers`.

### Files added under `Sources/EChartsKit/chart/`
- `chart/funnel/` — `FunnelSeries.swift` (`FunnelSeriesModel`), `funnelLayout.swift`
  (`funnelLayout` + `funnelLayoutStageHandler`), `FunnelView.swift`.
- `chart/candlestick/` — `CandlestickSeries.swift` (`CandlestickSeriesModel`), `candlestickLayout.swift`
  (+ `registerCandlestickAxisHandlers`, public `CandlestickItemLayout`/`CandlestickBrushRect`),
  `candlestickVisual.swift`, `CandlestickView.swift` (with the `NormalBoxPath` custom shape;
  `LargeBoxPath` stubbed).
- `chart/boxplot/` — `BoxplotSeries.swift` (`BoxplotSeriesModel`), `boxplotLayout.swift`
  (+ `registerBoxplotAxisHandlers`, public `BoxplotItemLayout`), `boxplotVisual.swift`,
  `BoxplotView.swift` (with the `BoxPath` custom shape).

### Custom shapes
- **`NormalBoxPath`** (candlestick) — the box-body ends + whisker geometry built via
  `dataToPoint` + `subPixelOptimize`; `buildPath` matches upstream index-for-index. Exposes the layout
  output the View consumes (`CandlestickItemLayout`: sign / initBaseline / ends / brushRect).
- **`BoxPath`** (boxplot) — the 5-number box+whisker path from `BoxplotItemLayout` (ends[][] +
  initBaseline), stored via `data.setItemLayout`.

### What was ported faithfully (per type)
- **funnel:** `FunnelSeriesModel` defaults (incl. `coordinateSystemUsage:'box'`, `SERIES_TYPE_FUNNEL`,
  `getInitialData` via `createSeriesDataSimply`); `funnelLayout` — `getSortedIndices` (sort/gap/
  `funnelAlign`), the trapezoid `getLinePoints` geometry, min/max/minSize/maxSize/`linearMap` sizing,
  the per-item 4-corner `points` stored on the data layout, ascending reversal, itemStyle width/height
  overrides, and the full `labelLayout` label-position geometry (stored as `layout.label`);
  `funnelLayoutStageHandler`; and a static `FunnelView.render` drawing one `ZRenderKit` `Polygon` per
  datum (points → `PolygonShape`, visual style via `barStyleFromDict`, `lineJoin:'round'`, final opacity).
- **candlestick:** `CandlestickSeriesModel` (defaults, dependencies, `getShadowDim`, and the
  `getInitialData`/`getBaseAxis`/`getWhiskerBoxesLayout`/`_hasEncodeRule` inlined from
  `WhiskerBoxCommonMixin`); `candlestickLayout` (candleWidth calc + normalProgress box/whisker geometry
  via `dataToPoint`+`subPixelOptimize`, `getSign`); `candlestickVisual` (`getColor`/`getBorderColor` +
  bull/bear fill/stroke assignment); the `'k' → 'candlestick'` preprocessor. `CandlestickView` box-body
  ends + whisker geometry, the bull/bear `sign(close-open)` color assignment, and `NormalBoxPath.buildPath`
  are all exact index-for-index ports (review-confirmed FAITHFUL).
- **boxplot:** `BoxplotSeriesModel` with `WhiskerBoxCommonMixin` FOLDED directly in (stored state
  `_baseAxisDim`/`_layout` + `_hasEncodeRule`/`getInitialData`/`getBaseAxis`/`getWhiskerBoxesLayout`,
  per CONVENTIONS §2 explicit forwarding); `boxplotLayout` (exposes `BoxplotItemLayout`); `boxplotVisual`.
  Review verdict FAITHFUL, 0 findings.

### Deferred PORT-TODOs (marked in-code)
- **Large / progressive draw path** — `LargeBoxPath`/`LargeBoxPathShape`/`createLarge`/`setLargeStyle`
  stubbed to no-op (full upstream body preserved in a PORT-TODO block). Layout `largeProgress`
  (`largePoints` buffer) is ported for structural fidelity but is unreachable on the normal path and has
  no consumer; `dataToPoint` out-param collapsed to a value-return. **Consequence:** with `large:true` +
  `largeThreshold:600`, a candlestick series over the threshold enters large mode and currently renders
  NOTHING (documented review finding).
- **Diff-based enter/update/remove** — `data.diff(oldData).add/.update/.remove/.execute` replaced by
  `group.removeAll()` + a straight loop over all data (static rebuild; same strategy as Line/Pie/Funnel).
- **Enter/update animation** — `initProps`/`updateProps`/`saveOldStyle` are no-animation shims (final
  geometry set immediately; `transInit` init-baseline shape is computed but immediately overwritten since
  there is no tween).
- **Emphasis / hover / select states + labels** — `getItemModel`/`emphasisModel`/
  `setStatesStylesFromModel`/`toggleHoverEmphasis`, per-state `getColor`/`getBorderColor` loops, and all
  label niceties (`setLabelStyle`/`getLabelStatesModels`/labelLine) deferred (util/states not ported).
- **Clipping** — `resolveNormalBoxClipping`/`needClip`/`createClipPath`/`SHAPE_CLIP_KIND_*` stubbed to
  `NOT_CLIPPED`, so boxes fully outside the coord area are still drawn and partially-clipped boxes get no
  per-item clipPath (real divergence when data straddles the grid edge, e.g. dataZoom).
- **`boxplotTransform.ts` dataset transform** — deferred per task scope; `install()` left uncalled /
  kept as commented source. `registerBoxplotAxisHandlers`/`registerCandlestickAxisHandlers` ARE ported
  and callable (Integrate owns the rest of the install wiring).
- **`StageHandler.plan` (`createRenderPlanner`)** — left unwired on both StageHandlers (the non-optional
  `plan` return-type mismatch, same deviation as `layout/barGrid.swift`); `reset` recomputes each pass.
- **`brushSelector`** — signature preserved but returns false (component/brush not ported).
- **Funnel-specific deferrals** — the whole `FunnelPiece` class (ZRenderKit `Polygon` is `final`, so it
  is collapsed to a plain inline `Polygon` + a `funnelUpdateLabel` free function): label/labelLine
  states, animation (opacity fade 0→opacity, `removeElementWithFadeOut`), and the SymbolDraw-style diff.
  Also: `LegendVisualProvider` assignment, `_defaultLabelLine` mutation, `getDataParams` percent/`$vars`
  (DataFormatMixin not grafted), `tokens.color.*` inlined as `'#fff'`/`'#3c3c41'`, and the custom-function
  `sort` branch (option-bag cannot carry a closure — string forms supported). The `labelLayout` GEOMETRY
  IS ported (not deferred) though nothing consumes `layout.label` until the label subsystem lands.

### Known value-semantics deviation (documented PORT-TODO)
`whiskerBoxCommon`'s `addOrdinal` path mutates source-referenced data in place upstream (dual-alias with
a clean `option.data` for idempotency). Because the Swift `Source` holds a value copy, the port writes
index-prepended data back to `self.option["data"]` and re-prepares the `SourceManager`
(`dirty()`+`prepareSource()`) to reproduce the SOURCE state. Caveat: a later `mergeOption` that does not
replace `data` could double-prepend. First-render correctness holds. (Boxplot's inline `getInitialData`
`addOrdinal` writeback is INERT — the option bag is a value type and the Source is already prepared;
the ordinal index arrives through the source/encode pipeline instead.)

### Locally stubbed helpers (pending `chart/helper/axisSnippets.swift`, mirroring barGrid/barCommon)
`makeAxisStatKey(seriesType)`, `createMetricsNonOrdinalLinearPositiveMinGap(axis)`,
`createBandWidthBasedAxisContainShapeHandler(axisStatKey)` — from `axisSnippets.ts` (not ported). Inlined
constants pending `visual/tokens.swift`: `tokens.color.neutral00 → '#fff'`, `tokens.color.shadow →
'rgba(0,0,0,0.2)'` (same convention as `ScatterSeries.swift`).

### Build & test status — Phase 8
- **`swift build`: GREEN (0 warnings).**
- **`swift test`: 220 executed / 0 failures (0 unexpected) / 58 skipped** in 0.264 (0.274) s — matches
  the §38 baseline (all three new chart types register with no regression).

### Faithfulness reviews — three verdicts
1. **`chart/funnel/funnelLayout.swift` — FAITHFUL_WITH_MINOR_DIVERGENCES.**
   - *(medium)* Per-item `itemStyle.width`/`height` given as a percent STRING (e.g. `"50%"`) is silently
     dropped: `asDoubleOpt()` returns nil for any String, so the code takes the itemSize branch instead
     of `parsePercent(width, viewWidth)`. Upstream `width == null` is false for a non-null string, so it
     honors the explicit percentage. Only plain-number overrides (and the default unset case) survive the
     port; percent-string overrides produce the wrong trapezoid width/height. (funnelLayout.ts:352-359 /
     373-380 vs funnelLayout.swift:393-401 / 414-421)
   - *(low)* `getSortedIndices` uses Swift `Array.sort(by:)` (not guaranteed stable) whereas upstream
     relies on ES2019+ stable `Array.prototype.sort`, so the tie-break ordering of equal-valued slices can
     differ. (funnelLayout.ts:46-50 vs funnelLayout.swift:62-66)
   - *(low)* Custom-function `sort` (isFunction branch) is a documented no-op PORT-TODO: a comparator
     passed via options is ignored, leaving indices in natural 0..n order. (funnelLayout.ts:42-44 vs
     funnelLayout.swift:53-57)
2. **`chart/candlestick/CandlestickView.swift` — FAITHFUL.** The three focus areas are exact ports:
   box-body ends + whisker geometry from `dataToPoint`, the bull/bear `sign(close-open)` color/border
   assignment, and `NormalBoxPath.buildPath` all match upstream index-for-index. All divergences are
   explicitly-documented PORT-TODO deferrals (not silent bugs):
   - *(medium)* `resolveNormalBoxClipping` stubbed to always return `SHAPE_CLIP_KIND_NOT_CLIPPED` — boxes
     fully outside the coord-sys area are drawn and partially-clipped boxes get no per-item clipPath (real
     divergence when data straddles the grid edge). (CandlestickView.swift:491-494)
   - *(medium)* Large-mode draw path is a no-op (`createLarge`/`setLargeStyle`/`LargeBoxPath` stubbed): a
     candlestick series exceeding `largeThreshold:600` with `large:true` renders NOTHING; `largeProgress`
     still fills `largePoints` but has no consumer. (CandlestickView.swift:464-479)
   - *(low)* `setBoxCommon` defers the states/emphasis block (per-state getColor/getBorderColor loop +
     `toggleHoverEmphasis`); *(low)* enter/update animation dropped (final geometry immediate); *(low)*
     `StageHandler.plan` left unwired in both layout and visual (optional-return mismatch).
3. **`chart/boxplot/boxplotLayout.swift`, `chart/boxplot/BoxplotView.swift` — FAITHFUL** (0 findings).

---

## 12. Standing rule for syncing upstream

Every ported file is a **diffable mirror** of its `.ts` original (CONVENTIONS §0). To keep re-sync
mechanical as upstream ECharts/ZRender evolves:

1. **Header comment, line 1, every file:**
   `// Ported from <upstream path>.ts — keep in sync with upstream` (real path, e.g.
   `zrender/src/graphic/Path.ts`). Keep the upstream `@author` / Chinese comments verbatim.
   (NativePainter files are exempt — they are hand-written backends, not translations; see CONVENTIONS §9.)
2. **Mirror structure:** preserve upstream file names, identifier names, and top-to-bottom
   declaration/method/case order. Do not refactor, rename, or reorder. Faithfulness over elegance.
3. **Never silently drop code.** Every skipped/stubbed/deferred/uncertain spot gets a
   `// PORT-TODO: <why>`. Document deviations (value-returning §3, NaN handling, weak refs) inline
   *and* in this file's backlog (§4 for Phase 1, §P0-3 for Phase 0).
4. **Golden fixtures are the regression net.** Regenerate from real ECharts after any upstream bump:
   `cd Oracle && node dump-displaylist.js` (or `node dump-displaylist.js <name>` for one).
   ECharts resolves via `require('echarts')` → `$ECHARTS_DIST` → fallback clone. Both `swift test
   --filter GoldenTests` checks must stay green: `testRebuiltDMatchesOracle` (PathProxy replay parity)
   **and** `testSwiftBuildPathMatchesOracle` (true `Shape.buildPath` geometry parity, byte-for-byte vs
   the oracle). Re-syncing a file means: update the Swift mirror, regenerate fixtures, confirm both
   parities before merge.

---
---

# Phase 0 history (preserved)

**Phase 0 (Core scaffold + math/geometry foundation): COMPLETE.** The one compile blocker recorded
below (§P0-3 #1) was **resolved in Phase 1** (`bbox.fromCubic`/`cubicExtrema`); `swift test` now compiles
end-to-end. The rest of §P0-3 remains an open low-risk backlog (cross-referenced from §4 above).

## P0-1. What landed in Phase 0 — checklist

### Package layout & seam
- [x] `Package.swift` — three targets: `ZRenderKit` (ported core), `NativePainter`
      (hand-written CG/CA backend, not a translation of CanvasPainter), `EChartsKit` (umbrella).
- [x] `Sources/ZRenderKit/Core/PathRebuilder.swift` — consumer protocol for
      `PathProxy.rebuildPath` (the path-command seam).
- [x] `Sources/NativePainter/Renderer.swift` — the `Renderer` (~8 paint ops:
      fillPath/strokePath/drawImage/drawText/setClip/transform/opacity/shadow) and `Painter`
      (beginFrame/endFrame/dpr) seam protocols. **Phase 0: contract only — bodies were PORT-TODO stubs.**
      (Phase 1 implemented these via `CALayerPainter`/`CGRenderer`/`CGPathRebuilder`.)
- [x] `Sources/EChartsKit/EChartsKit.swift` — umbrella module placeholder.
- [x] `CONVENTIONS.md` — binding translation rules (§1 number→Double, §2 module/class mapping,
      §3 out-param value-returning mandate, §9 renderer seam, etc.).
- [x] **Mutation strategy decided & enforced (§3):** value-returning, no out-params.
      `VectorArray = SIMD2<Double>`, `MatrixArray = [Double]` (6 elems, `[a,b,c,d,e,f]`),
      multi-output → tuple, single scratch-array output → returned array. `inout` dropped
      entirely (self-aliasing calls like `vec2.min(min,min,min2)` violate Swift exclusivity).

### 14 translated Core files (`Sources/ZRenderKit/Core/`)
- [x] `types.swift` — typealiases, string/number-union enums, event-name enums, ZLevel consts.
- [x] `env.swift` — `env`/`Browser` singletons; native feature flags via `configureNativeEnv`.
- [x] `util.swift` — **partial**: geometry-layer helpers only (guid, each/map/reduce/filter/find,
      retrieve*, defaults/keys, normalizeCssArray, assert). Clone/merge/type-guards deferred
      (extended on demand in Phase 1).
- [x] `LRU.swift` — `LRU`/`LinkedList`/`Entry`, `LRUKey` tagged enum.
- [x] `WeakMap.swift` — `WeakMap<K: AnyObject, V>` over `NSMapTable` (weak→strong).
- [x] `matrix.swift` — `MatrixArray = [Double]`, value-returning `matrix` namespace.
- [x] `vector.swift` — `VectorArray = SIMD2<Double>`, value-returning `vector` namespace (vec2).
- [x] `Point.swift` — `Point` / `PointLike` (class-bound) with in-place static mutators.
- [x] `curve.swift` — cubic/quadratic at/derivative/root/extrema/subdivide/project/length.
- [x] `bbox.swift` — fromPoints/Line/Cubic/Quadratic/Arc → `(min, max)` tuples. **(blocker resolved in Phase 1.)**
- [x] `BoundingRect.swift` — `BoundingRect`/`RectLike`, intersect/contain/union/transform, MTV context.
- [x] `Transformable.swift` — scene-graph transform base class (subclassable, `parent` weak).
- [x] `platform.swift` — `PlatformAPI`/`DefaultPlatformAPI`, ASCII-width-table measureText fallback.
- [x] `PathProxy.swift` — full path recorder/replayer: addData/moveTo/lineTo/bezier/arc/rect,
      getBoundingRect, rebuildPath, toStatic, clone (~37 KB, the keystone of Phase 0).

### Golden-test harness (`Oracle/` + `Tests/`)
- [x] `Oracle/dump-displaylist.js` — drives real ECharts (`animation:false`), dumps the resolved
      display list incl. each Path's rebuilt `d` string. Deterministic (verified identical on re-run).
- [x] 7 option specs + 7 generated fixtures: `rect`, `circle`, `sector`, `arc`, `bezier-curve`,
      `polygon`, `combined` (`Oracle/options/*.json`, `Oracle/fixtures/*.json`).
- [x] `Tests/ZRenderKitTests/GoldenTests.swift` — `testRebuiltDMatchesOracle` (replays each
      fixture's PathProxy data and byte-compares the rebuilt `d`) + `testAllFixturesLoad`.
      (Phase 1 added `testSwiftBuildPathMatchesOracle` for true geometry parity.)
- [x] `Tests/ZRenderKitTests/PathRebuilderTests.swift` — seam unit tests.
- [x] Harness validated standalone (swiftc-compiled copy): **PASS=12 FAIL=0**, every Path's
      rebuilt `d` matches the oracle byte-for-byte.
- [x] **`swift test` end-to-end compile** — was blocked in Phase 0 by `bbox.swift`/`curve.swift`;
      **resolved in Phase 1** (now green).

## P0-2. Per-file status & review verdict (Phase 0)

| # | File | Status | Verdict | Notes |
|---|------|--------|---------|-------|
| 1 | `types.swift` | complete | faithful | ZLevel2/IncrementalIdCompat widened to bare Double |
| 2 | `env.swift` | complete | minor-issues | native config diverges from upstream node-branch (`node`/`svgSupported`); `detect()` drops `in window` guards |
| 3 | `util.swift` | **partial** | faithful | only geometry-layer helpers ported; clone/merge/type-guards = PORT-TODO |
| 4 | `LRU.swift` | complete | minor-issues | numeric-vs-string key coercion; doubly-linked retain cycle |
| 5 | `WeakMap.swift` | complete | minor-issues | `has`/`delete` presence-test vs JS truthiness (falsy V) |
| 6 | `matrix.swift` | complete | faithful | dead `create()` in clone; redundant temps in mul (cosmetic) |
| 7 | `vector.swift` | complete | minor-issues | `min`/`max` NaN non-propagation; static-let alias resolution risk |
| 8 | `Point.swift` | complete | minor-issues | constructor `?? 0` vs JS `|| 0` (NaN); transform→Optional |
| 9 | `curve.swift` | complete | faithful | no issues raised |
| 10 | `bbox.swift` | complete | major-issues → **RESOLVED (Phase 1)** | misused `curve.cubicExtrema` tuple; fixed, compiles |
| 11 | `BoundingRect.swift` | complete | minor-issues | mathMin/Max NaN semantics; clamp-branch force-unwrap (faithful) |
| 12 | `Transformable.swift` | complete | minor-issues | `getLocalTransform` drops `|| 0` (NaN); `parent` weak ownership |
| 13 | `platform.swift` | complete | minor-issues | measureText iterates graphemes not UTF-16 code units |
| 14 | `PathProxy.swift` | complete | faithful | hard pathSegLen subscript traps vs JS NaN (unreachable in practice) |

Roll-up: **1 partial, 13 complete; 1 major (now resolved), 8 minor, 5 faithful.**

## P0-3. Open issues & PORT-TODOs (Phase 0) — deduped, blockers first

### BLOCKER — RESOLVED in Phase 1
1. **`bbox.fromCubic` misused `curve.cubicExtrema` (did not compile). RESOLVED.**
   `curve.swift:157` signature is `cubicExtrema(...) -> (extrema: [Double], n: Double)` — a
   **tuple**. The old `bbox.swift` did `let cubicExtrema = curve.cubicExtrema` → `xDim.count` /
   `xDim[i]`, which a tuple has no member for. Fixed in Phase 1 by destructuring `(xDim, n)` and
   iterating `0..<Int(n)` (which also fixed the latent semantic bug: the intended count is `n` ∈ {0,1,2},
   not the constant buffer length 2). `swift test` now compiles end-to-end.

### Correctness — pre-existing review/sign-off (still open, low-risk under finite-coords usage)
2. **Pervasive `Swift.min`/`Swift.max` NaN non-propagation** (`vector.min/max`,
   `BoundingRect.mathMin/Max` + 4-arg overloads, and any bbox reduction). JS `Math.min/max`
   propagate NaN; `Swift.min/max` return the non-NaN operand. These are exactly the bbox/bounds
   accumulators, so a NaN coordinate that would taint a bbox upstream silently survives as a
   finite extent here. Decide a policy (NaN-propagating helper, or documented "finite-coords-only"
   guarantee) and apply uniformly.
3. **`|| 0` (JS-falsy) vs `?? 0` (nil-only) inconsistency on NaN.** `Point` constructor,
   `Transformable.getLocalTransform` (`originX/Y`, `rotation`), and others substitute 0 only for
   `nil`, not for NaN — diverging from upstream where `NaN || 0 === 0`. `_resolveGlobalScaleRatio`
   *did* replicate `|| 0`. Pick one convention; NaN rotation/origin poisons whole matrices.
4. **`env.configureNativeEnv` contradicts upstream's windowless (node) branch.** Upstream sets
   `node=true; svgSupported=true` for no-global-window; native config leaves `node=false`,
   `svgSupported=false`. Any downstream `if env.node` / `if env.svgSupported` gate will branch
   oppositely. Needs explicit sign-off that no consumer depends on these.
5. **`env.detect()` is not a faithful translation despite the "fully translated" note.** It drops
   the `'ontouchstart' in window` / `'onpointerdown' in window` guards. Dead code on iOS today,
   but will compute wrong flags if ever wired. Either fix or mark clearly `// PORT-TODO: dead, not faithful`.
6. **`WeakMap.has`/`delete` use presence test, not JS truthiness.** For falsy-valued `V`
   (`0`, `""`, `false`) Swift `has` returns true where JS returns false, and `delete` then mutates/returns
   differently. Safe for object-valued WeakMaps (the common case); audit before any value-type `V` use.
7. **`LRU.LRUKey` does not coerce numeric keys to strings.** `.number(1)` and `.string("1")` are
   distinct, but JS `map[1] === map["1"]`. Audit call sites that mix numeric/string forms of one key.
8. **`platform.measureText` iterates grapheme clusters, not UTF-16 code units.** Diverges from
   `text.length` for emoji / non-BMP. Switch to `text.utf16` to match (the translator already uses
   `.utf16` in `getTextWidthMap`). Becomes load-bearing once real text measurement lands (Phase 2 5a).

### Style / divergence notes (track, fix opportunistically)
9. `vector.swift` static-let aliases (`length = len`, `dist = distance`, …) reference sibling
   statics by bare name in a stored-property initializer — fragile; **build-verify** (qualify as
   `Self.len` if it fails). *(Phase-1 clean build confirms these resolve.)*
10. **In-place-mutation aliasing is gone everywhere** (value-returning §3). Every ported caller of
    `vector.*`/`matrix.*`/`bbox.*` must *assign the result* (`p = vector.add(p, d)`); a caller that
    discards the return expecting in-place mutation is a **silent no-op**. Recheck at each call site.
11. Memory: `LRU.Entry` doubly-linked list uses bidirectional strong refs (leaks after `clear()`);
    `Transformable.parent` is `weak` (verify ownership / no mid-walk dealloc). Revisit if leaks/crashes surface.
12. `util.reduce` requires `memo` (TS optional); `util.indexOf` is `T: Equatable`+`==` (TS `===`);
    `retrieve2/3` collapse the union return — all safe in current scope, documented.
13. Force-unwraps that faithfully mirror upstream null-deref (BoundingRect `outIntersectRect!` under
    clamp; PathProxy hard `pathSegLen[segCount]`) — JS would also crash; left verbatim, not bugs.
14. Renderer/DOM seam stubs (CONVENTIONS §9): `platform.createCanvas`/`loadImage` return nil;
    `PathProxy._ctx`/setContext/getContext dropped. The `NativePainter.Renderer`/`Painter` *bodies* were
    Phase-0 stubs — **implemented in Phase 1** (`CALayerPainter`/`CGRenderer`); image/text/gradient paint
    remains Phase 2.
15. `util.swift` is **partial**: clone/merge/extend/type-guards/HashMap/bind/curry were PORT-TODO;
    extended on demand in Phase 1 and continuing into Phase 2.
