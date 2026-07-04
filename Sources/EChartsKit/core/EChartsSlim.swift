// Ported (SLIM SUBSET) from echarts/src/core/echarts.ts — keep in sync with upstream.
//
// ============================================================================
// WHAT THIS FILE IS
// ============================================================================
// `echarts/src/core/echarts.ts` is a 3400-line module. This file is a DELIBERATELY MINIMAL,
// heavily-documented subset that renders ONE vertical slice — a cartesian **bar** chart (grid +
// x/y axis + bar series) — end-to-end through the already-ported model → coord → view pipeline,
// emitting a ZRenderKit `Group` of bar `Rect`s + axis line/tick/label elements.
//
// It faithfully mirrors the STAGE ORDER of upstream `updateMethods.update` (see §UPDATE below),
// but every stage that a bar chart does not strictly need is a documented `PORT-TODO` skip. The
// heavy `ECharts` machinery that is intentionally NOT reproduced here:
//   - The `Scheduler` task/pipeline graph. Upstream runs each stage as a `Task` (`performXxxTasks`
//     / `renderTask.perform`). Here the stages are invoked DIRECTLY (documented deviation) — the
//     scheduler's progressive/stream/incremental machinery is out of the bar scope.
//   - `prepare()` + `restorePipelines`/`prepareStageTasks`/`plan` (Scheduler pipeline building).
//   - `updateTransform`/`updateView`/`updateLayout`/`updateVisual` fast-path update methods.
//   - Actions / events / lifecycle triggers / connect / loading / SSR / theme / media query.
//   - `allocateZlevels`, `clearStates`/`updateStates`/`updateZ`/`updateBlend`, hover/emphasis.
//   - The DOM/zrender `init` facade + painter. EChartsKit depends only on ZRenderKit (NOT
//     NativePainter), so this driver owns a `Storage` + a root `Group` and exposes them; a host
//     with a painter (NativePainter's `CALayerPainter`) draws `getRoot()`.
//
// ============================================================================
// REGISTRATION (replaces the per-chart `install(registers)` boilerplate)
// ============================================================================
// Upstream, each feature ships an `install(registers)` (e.g. `component/grid/installSimple.ts`,
// `chart/bar/install.ts`) that calls `registerComponentModel` / `registerComponentView` /
// `registerChartView` / `registerSeriesModel` / `registerCoordinateSystem` / `registerLayout` /
// `registerVisual` / `registerProcessor`. Those registrars are Phase-6b wiring and are NOT bridged
// to `GlobalModel`'s instantiation path yet. So `installOnce()` below performs the equivalent
// registration explicitly:
//   - MODELS  → `ComponentModel.registerClass(...)` (the ONLY instantiation path `GlobalModel`
//               currently uses; see `Global.swift:537`).
//   - COORD   → `CoordinateSystemManager.register("cartesian2d", GridCoordinateSystemCreator())`.
//   - VIEWS   → explicit factory maps (`_componentViewFactories` / `_chartViewFactories`). Upstream
//               stores the view CLASS and does `new Clazz()`; Swift can not `new` a bare
//               `ClassManageable` metatype (the protocol has no `init` requirement), so the driver
//               holds `() -> View` factories instead (documented deviation).
//   - STAGES  → the visual (`visual/style.swift`) + layout (`layout/barGrid.swift`) + processor
//               (axis-statistics) handlers are captured/referenced directly (see the stage methods).
//
// NOTE on axis models: upstream `axisModelCreator` GENERATES a distinct `AxisModel` subclass per
// axis type at runtime and registers it. Swift can not synthesize classes at runtime AND the
// generated-factory registrar is not bridged to `GlobalModel` instantiation, so this file registers
// two concrete stand-in subclasses (`SlimXAxisModel` / `SlimYAxisModel`) that add the
// `AxisModelExtendedInCreator` surface (`getOrdinalMeta` etc.) a category axis needs. This mirrors
// exactly the working `CartesianCoordTests` doubles; it is the documented stand-in for
// `axisModelCreator(registers, 'x'/'y', CartesianAxisModel, ...)` until the registrar↔instantiation
// bridge lands (Phase 6b).

import Foundation
import ZRenderKit

// ============================================================================
// Coordinate-system creator for cartesian2d (wraps `Grid.create` / `Grid.dimensions`).
// Upstream registers the `Grid` CLASS itself as the creator; the ported registry wants a
// `CoordinateSystemCreator` value, so this thin struct forwards to the static `Grid.create`.
// ============================================================================
struct GridCoordinateSystemCreator: CoordinateSystemCreator {
    func create(_ ecModel: GlobalModel, _ api: ExtensionAPI) -> [CoordinateSystemMaster] {
        // Grid.create returns [Grid]; Grid conforms to CoordinateSystemMaster.
        return Grid.create(ecModel, api).map { $0 as CoordinateSystemMaster }
    }
    var dimensions: [DimensionName]? { Grid.dimensions }        // static dimensions = cartesian2DDimensions
    func getDimensionsInfo() -> [DimensionDefinitionLoose]? { nil } // Grid has no dimensionsInfo hook.
}

// ============================================================================
// Coordinate-system creator for radar (wraps `Radar.create` / `Radar.dimensions`). Radar is the FIRST
// non-cartesian coordinate system wired here; the shape mirrors GridCoordinateSystemCreator exactly.
// Upstream registers the `Radar` CLASS itself (`registerCoordinateSystem('radar', Radar)`); the ported
// registry wants a `CoordinateSystemCreator` value, so this thin struct forwards to the static
// `Radar.create`. Radar's static `dimensions` is `[]` (radar dimensions are data-derived per-indicator).
// ============================================================================
struct RadarCoordinateSystemCreator: CoordinateSystemCreator {
    func create(_ ecModel: GlobalModel, _ api: ExtensionAPI) -> [CoordinateSystemMaster] {
        // Radar.create returns [Radar]; Radar conforms to CoordinateSystemMaster.
        return Radar.create(ecModel, api).map { $0 as CoordinateSystemMaster }
    }
    var dimensions: [DimensionName]? { Radar.dimensions }        // static dimensions = [] (data-derived).
    func getDimensionsInfo() -> [DimensionDefinitionLoose]? { nil } // Radar has no dimensionsInfo hook.
}

// ============================================================================
// Coordinate-system creator for polar (wraps `polarCreator.create` / `polarCreator.dimensions`). The
// polar coord system is the SECOND non-cartesian coordinate system wired here (after radar); the shape
// mirrors GridCoordinateSystemCreator / RadarCoordinateSystemCreator exactly. Upstream registers the
// `Polar` CLASS itself (`registerCoordinateSystem('polar', Polar)`); the ported registry wants a
// `CoordinateSystemCreator` value, so this thin struct forwards to the caseless-namespace `polarCreator`.
// polarCreator.dimensions is the static `polarDimensions` (["radius", "angle"]).
// ============================================================================
struct PolarCoordinateSystemCreator: CoordinateSystemCreator {
    func create(_ ecModel: GlobalModel, _ api: ExtensionAPI) -> [CoordinateSystemMaster] {
        // polarCreator.create returns [Polar]; Polar conforms to CoordinateSystemMaster.
        return polarCreator.create(ecModel, api).map { $0 as CoordinateSystemMaster }
    }
    var dimensions: [DimensionName]? { polarCreator.dimensions }  // static dimensions = polarDimensions.
    func getDimensionsInfo() -> [DimensionDefinitionLoose]? { nil } // Polar has no dimensionsInfo hook.
}

// ============================================================================
// single coord system is the FOURTH coordinate system wired here (after cartesian2d / radar / polar);
// the shape mirrors PolarCoordinateSystemCreator exactly. Upstream registers the caseless-namespace
// `singleCreator` (`registerCoordinateSystem('single', singleCreator)`); the ported registry wants a
// `CoordinateSystemCreator` value, so this thin struct forwards to it.
// singleCreator.dimensions is the static `singleDimensions` (["single"]).
// ============================================================================
struct SingleCoordinateSystemCreator: CoordinateSystemCreator {
    func create(_ ecModel: GlobalModel, _ api: ExtensionAPI) -> [CoordinateSystemMaster] {
        // singleCreator.create returns [Single]; Single conforms to CoordinateSystemMaster.
        return singleCreator.create(ecModel, api).map { $0 as CoordinateSystemMaster }
    }
    var dimensions: [DimensionName]? { singleCreator.dimensions }  // static dimensions = singleDimensions.
    func getDimensionsInfo() -> [DimensionDefinitionLoose]? { nil } // Single has no dimensionsInfo hook.
}

// ============================================================================
// parallel coord system is the FIFTH coordinate system wired here (after cartesian2d / radar / polar /
// single); the shape mirrors SingleCoordinateSystemCreator exactly. Upstream registers the caseless
// `parallelCoordSysCreator` (`registerCoordinateSystem('parallel', parallelCoordSysCreator)`); the ported
// registry wants a `CoordinateSystemCreator` value, so this thin struct forwards to it.
// parallelCoordSysCreator has NO static `dimensions` (parallel has no fixed dims), so `dimensions` is nil.
// ============================================================================
struct ParallelCoordinateSystemCreator: CoordinateSystemCreator {
    func create(_ ecModel: GlobalModel, _ api: ExtensionAPI) -> [CoordinateSystemMaster] {
        // parallelCoordSysCreator.create already returns [CoordinateSystemMaster].
        return parallelCoordSysCreator.create(ecModel, api)
    }
    var dimensions: [DimensionName]? { nil }                       // parallel has no static dimensions.
    func getDimensionsInfo() -> [DimensionDefinitionLoose]? { nil } // Parallel has no dimensionsInfo hook.
}

// ============================================================================
// Stand-in axis models (see the axisModelCreator NOTE in the file header).
// These are the documented equivalent of the classes `axisModelCreator` would generate for
// `xAxis.<type>` / `yAxis.<type>`. They read `axis.data` for category ordinal metadata.
// ============================================================================

/// Merge the per-type `axisDefault` (show:true + axisLine/axisTick/axisLabel/splitLine sub-defaults)
/// UNDER the model's own option, so `axisModel.get("show")` / the AxisBuilder's sub-option reads resolve.
/// This stands in for the deferred `AxisModel.mergeDefaultAndTheme` default-merge (the real
/// axisModelCreator path injects `getDefaultOption()`; the slim stand-in models never run through it).
/// Overwrite=false → user option wins; nested dicts deep-merge (util.merge).
private func slimMergeAxisDefaults(_ model: CartesianAxisModel, _ defaultType: String) {
    guard var opt = model.option as? [String: Any] else { return }
    let axisType = (opt["type"] as? String) ?? defaultType
    guard let def = axisDefault.option[axisType] as? [String: Any] else { return }
    _ = util.merge(&opt, def, false)
    model.option = opt
}

/// `xAxis` model. `static type = 'xAxis'` so `ComponentModel.registerClass` keys it correctly.
final class SlimXAxisModel: CartesianAxisModel, AxisModelExtendedInCreator {
    override class var type: ComponentFullType { return "xAxis" }
    private var __ordinalMeta: OrdinalMeta?
    override func optionUpdated(_ n: ModelOption?, _ isInit: Bool) {
        super.optionUpdated(n, isInit)
        slimMergeAxisDefaults(self, "category")
        if (self.option as? [String: Any])?["type"] as? String == "category" {
            __ordinalMeta = OrdinalMeta.createByAxisModel(self)
        }
    }
    override func getCategories(_ rawData: Bool?) -> [OrdinalRawValue]? {
        return (self.option as? [String: Any])?["data"] as? [OrdinalRawValue]
    }
    // AxisModelExtendedInCreator: category axes always have their meta built in optionUpdated;
    //   value/time/log axes never call getOrdinalMeta (createScaleByModel only reads it for 'category').
    func getOrdinalMeta() -> OrdinalMeta { return __ordinalMeta ?? OrdinalMeta.createByAxisModel(self) }
    func updateAxisBreaks(_ payload: BaseAxisBreakPayload) -> AxisBreakUpdateResult {
        return AxisBreakUpdateResult(breaks: [])   // axis-break support is out of the bar scope.
    }
}

/// `yAxis` model (value axis in a vertical bar chart; symmetric to `SlimXAxisModel`).
final class SlimYAxisModel: CartesianAxisModel, AxisModelExtendedInCreator {
    override class var type: ComponentFullType { return "yAxis" }
    private var __ordinalMeta: OrdinalMeta?
    override func optionUpdated(_ n: ModelOption?, _ isInit: Bool) {
        super.optionUpdated(n, isInit)
        slimMergeAxisDefaults(self, "value")
        if (self.option as? [String: Any])?["type"] as? String == "category" {
            __ordinalMeta = OrdinalMeta.createByAxisModel(self)
        }
    }
    override func getCategories(_ rawData: Bool?) -> [OrdinalRawValue]? {
        return (self.option as? [String: Any])?["data"] as? [OrdinalRawValue]
    }
    func getOrdinalMeta() -> OrdinalMeta { return __ordinalMeta ?? OrdinalMeta.createByAxisModel(self) }
    func updateAxisBreaks(_ payload: BaseAxisBreakPayload) -> AxisBreakUpdateResult {
        return AxisBreakUpdateResult(breaks: [])
    }
}

// ============================================================================
// Capturing registrar for the axis-statistics PROCESSOR.
// The bar cross-series layout (`layout/barGrid.swift`) reads <axis, series> statistics that are
// computed by a processor registered via `registerBarGridAxisHandlers(registers)`. The base
// `EChartsExtensionInstallRegisters.registerProcessor` is a no-op stub, so this subclass captures
// the registered `overallReset` closures; the driver runs them in the data-processor stage.
// (Calling `registerBarGridAxisHandlers` ALSO populates the module-global `clientsForLookup` in
// axisStatistics.swift — that side effect is what makes the statistics collect the bar client.)
// ============================================================================
final class SlimInstallRegisters: EChartsExtensionInstallRegisters {
    var capturedProcessors: [(GlobalModel) -> Void] = []
    override func registerProcessor(_ priority: Double, _ processor: AxisStatProcessorRegistration) {
        capturedProcessors.append(processor.overallReset)
    }
}

// ============================================================================
// The slim ECharts driver.
// ============================================================================
public final class EChartsSlim: EChartsType {

    // ---- owned state (mirrors the private fields on upstream `ECharts`) ----
    private var _model: GlobalModel?                             // upstream: this._model
    private let _coordSysMgr = CoordinateSystemManager()         // upstream: this._coordSysMgr
    private var _api: ExtensionAPI!                              // upstream: this._api
    private var _width: Double
    private var _height: Double

    /// The flattened, z-sorted display list (upstream: `zr.storage`). A host painter consumes this.
    public let storage = Storage()
    /// The ec root `Group` — all view groups are added here (upstream: elements added to `zr`).
    public let root = Group()

    // View registries. Upstream: `_componentsViews`/`_componentsMap`/`_chartsViews`/`_chartsMap`.
    private var _componentsViews: [ComponentView] = []
    private var _chartsViews: [ChartView] = []
    // viewId → view (upstream keyed by `'_ec_' + model.id + '_' + model.type`).
    private var _componentsMap: [String: ComponentView] = [:]
    private var _chartsMap: [String: ChartView] = [:]
    // model-identity → view (for `api.getViewOfComponentModel`/`getViewOfSeriesModel`).
    private var _componentViewByModel: [ObjectIdentifier: ComponentView] = [:]
    private var _chartViewByModel: [ObjectIdentifier: ChartView] = [:]

    public init(width: Double, height: Double) {
        self._width = width
        self._height = height
        EChartsSlim.installOnce()
        // `_api` needs `self`; all stored properties are initialized above, so it is safe now.
        self._api = SlimExtensionAPI(ec: self)
    }

    // ------------------------------------------------------------------------
    // Registration (idempotent). Replaces the deferred `install(registers)` boilerplate.
    // ------------------------------------------------------------------------
    private static var _installed = false
    private static let _registers = SlimInstallRegisters()
    // The bar cross-series layout handler (created once; run each layout stage).
    private static let _barLayoutHandler: StageHandler = createCrossSeriesLayoutHandler(SERIES_TYPE_BAR)
    // The bar PER-ITEM layout handler (upstream `registerLayout(PROGRESSIVE_LAYOUT, ...)`). Despite the
    //   name, this is the layout that computes each bar's x/y/width/height and calls `data.setItemLayout`
    //   (barGrid.swift `createProgressiveLayout`'s progress executor) — it runs for EVERY bar series, not
    //   only large/progressive ones. `BarView.getLayoutCartesian2D` reads that item layout back, so
    //   without running this handler no bar has a shape and `BarView` emits zero Rects.
    private static let _barProgressiveLayoutHandler: StageHandler = createProgressiveLayout(SERIES_TYPE_BAR)

    static func installOnce() {
        if _installed { return }
        _installed = true

        // -- component/grid/installSimple.ts + coord/cartesian --
        ComponentModel.registerClass(GridModel.self)                       // registerComponentModel(GridModel)
        ComponentModel.registerClass(SlimXAxisModel.self)                  // axisModelCreator(..,'x',..)  (stand-in)
        ComponentModel.registerClass(SlimYAxisModel.self)                  // axisModelCreator(..,'y',..)  (stand-in)
        CoordinateSystemManager.register("cartesian2d", GridCoordinateSystemCreator()) // registerCoordinateSystem('cartesian2d', Grid)

        // -- chart/bar/install.ts --
        ComponentModel.registerClass(BarSeriesModel.self)                  // registerSeriesModel(BarSeries)
        // registerLayout(VISUAL.LAYOUT, createCrossSeriesLayoutHandler(bar)) → `_barLayoutHandler`.
        // registerLayout(PROGRESSIVE_LAYOUT, createProgressiveLayout(bar)) → PORT-TODO: the non-large
        //   bar path recomputes per-item geometry inside `BarView.render`, so the progressive layout
        //   task is not needed for a basic render (see barGrid.swift `createProgressiveLayout` note).
        // registerProcessor(PROCESSOR.STATISTIC, dataSample) → PORT-TODO: down-sampling not needed.
        registerBarGridAxisHandlers(_registers)   // populates axisStatistics `clientsForLookup` +
                                                  //   captures the axis-statistics processor (see registrar).

        // -- chart/line/install.ts (minimal) -- registerSeriesModel(LineSeries) + registerChartView(LineView).
        //   Line needs NO cross-series/progressive layout registrar (LineView computes points directly
        //   from `coord.dataToPoint`); the visual stage colors it like any series.
        ComponentModel.registerClass(LineSeriesModel.self)

        // -- chart/scatter/install.ts (minimal) -- registerSeriesModel(ScatterSeries) + registerChartView(ScatterView).
        //   Scatter (like line) computes point positions directly from `coord.dataToPoint`; no cross-series
        //   or progressive layout registrar is needed for the static render.
        ComponentModel.registerClass(ScatterSeriesModel.self)

        // -- chart/effectScatter/install.ts (minimal) -- registerChartView(EffectScatterView) +
        //   registerSeriesModel(EffectScatterSeries) + registerLayout(layoutPoints('effectScatter')) +
        //   registerVisual(...). Like scatter, EffectScatterView computes point positions directly from
        //   `coord.dataToPoint` (inlines pointsLayout), so no cross-series layout registrar is needed for the
        //   static render. The animated RIPPLE (helper/EffectSymbol) is DEFERRED (CONVENTIONS §5) — the view
        //   draws only the static base symbols. effectScatterInstall.swift is commented-only (diffable
        //   surface); actual wiring lives here per the boxplotInstall/parallelInstall convention.
        ComponentModel.registerClass(EffectScatterSeriesModel.self)

        // -- chart/pie/install.ts (minimal) -- registerSeriesModel(PieSeries) + registerChartView(PieView) +
        //   registerLayout(pieLayout). Pie has NO cartesian coord (coordinateSystemUsage:"box"); PieView reads
        //   its geometry from `data.getItemLayout` populated by the pie layout stage (run in `render`).
        ComponentModel.registerClass(PieSeriesModel.self)
        // Trigger the lazy Swift-global that runs `registerLayOutOnCoordSysUsage` for pie's box coord-sys-usage
        //   (registerLayOutOnCoordSysUsage asserts uniqueness — reference EXACTLY once, here in installOnce).
        _ = pieLayOutOnCoordSysUsageRegistered

        // -- chart/funnel/install.ts (minimal) -- registerSeriesModel(FunnelSeries) + registerChartView(FunnelView) +
        //   registerLayout(funnelLayoutStageHandler). Funnel has NO cartesian coord (coordinateSystemUsage:"box",
        //   like pie); FunnelView reads its per-piece polygon `points` from `data.getItemLayout` populated by the
        //   funnel layout stage (run in `render`). Funnel needs no `registerLayOutOnCoordSysUsage` (it reads no
        //   `center`/`getCoord2`; the layout resolves its view rect purely from `createBoxLayoutReference`).
        ComponentModel.registerClass(FunnelSeriesModel.self)

        // -- chart/candlestick/install.ts (minimal) -- registerSeriesModel(CandlestickSeries) +
        //   registerChartView(CandlestickView) + registerLayout(candlestickLayout) + registerVisual(candlestickVisual)
        //   + registerCandlestickAxisHandlers(registers). Candlestick is a cartesian2d series (like bar): the axis
        //   handlers populate the axisStatistics `clientsForLookup` (bandWidth for candle width). The already-captured
        //   axis-statistics processor (registered once by the bar handlers) picks up the candlestick client too.
        ComponentModel.registerClass(CandlestickSeriesModel.self)
        registerCandlestickAxisHandlers(_registers)

        // -- chart/boxplot/install.ts (minimal) -- registerSeriesModel(BoxplotSeries) + registerChartView(BoxplotView)
        //   + registerLayout(boxplotLayoutStageHandler) + registerBoxplotAxisHandlers(registers). Boxplot is a
        //   cartesian2d series (like bar); its colors come from the generic visual stage (visualDrawType:'stroke'),
        //   so it needs NO dedicated visual handler — only the layout stage + axis statistics.
        ComponentModel.registerClass(BoxplotSeriesModel.self)
        registerBoxplotAxisHandlers(_registers)

        // -- chart/sunburst/install.ts (minimal) -- registerSeriesModel(SunburstSeries) +
        //   registerChartView(SunburstView) + registerLayout(sunburstLayoutStageHandler) +
        //   registerVisual(sunburstVisualStageHandler). Sunburst has NO cartesian coord (hierarchical,
        //   box-like usage like pie); SunburstView reads its per-node sector geometry from the tree
        //   layout populated by the sunburst layout stage (run in `render`). Its dedicated visual stage
        //   colors each node (installSunburstAction rollup/highlight is DEFERRED — see sunburstInstall.swift).
        ComponentModel.registerClass(SunburstSeriesModel.self)

        // -- chart/treemap/install.ts (minimal) -- registerSeriesModel(TreemapSeries) +
        //   registerChartView(TreemapView) + registerLayout(treemapLayout) + registerVisual(treemapVisual).
        //   Treemap is hierarchical/box-usage (no cartesian coord); TreemapView reads each node's rect from
        //   the treemap layout stage, and treemapVisual colors each node FROM that layout (isInView/invisible),
        //   so — like candlestick — the layout MUST run before the visual (both run in `render`).
        ComponentModel.registerClass(TreemapSeriesModel.self)

        // -- chart/tree/install.ts (minimal) -- registerSeriesModel(TreeSeries) +
        //   registerChartView(TreeView) + registerLayout(treeLayout) + registerVisual(treeVisualStageHandler).
        //   Tree is hierarchical/box-usage (no cartesian coord); TreeView reads each node's x/y from the tree
        //   layout stage. Its dedicated visual stage sets per-node symbol colors (independent of layout).
        ComponentModel.registerClass(TreeSeriesModel.self)

        // -- chart/graph/install.ts (minimal) -- registerSeriesModel(GraphSeries) +
        //   registerChartView(GraphView) + registerLayout(circular/simpleLayout stage handlers) +
        //   registerProcessor(categoryFilter) + registerVisual(categoryVisual/edgeVisual). Graph is a
        //   coordless network chart (box/view usage); GraphView reads each node's [x,y] and each edge's
        //   [[p1],[p2](,[cp])] from the layout stage (circular or simple, self-gated on the `layout`
        //   option). The category visual colors nodes; the edge visual MUST run AFTER it (edge
        //   source/target stroke reads node fill). categoryFilter (legend-gated processor) runs in the
        //   data-processor stage. All run in `render`/`update` below.
        ComponentModel.registerClass(GraphSeriesModel.self)

        // -- chart/sankey/install.ts (minimal) -- registerSeriesModel(SankeySeries) +
        //   registerChartView(SankeyView) + registerLayout(sankeyLayoutStageHandler) +
        //   registerVisual(sankeyVisualStageHandler). Sankey is a COORDLESS flow chart (box usage, no
        //   cartesian coord; reuses the ported Graph + createGraphFromNodeEdge exactly like GraphSeries).
        //   SankeyView reads each node's rect {x,y,dx,dy} + each edge's ribbon {sy,ty,dy} from the box
        //   layout stage (sankeyLayout), and each node's fill from the visual stage (sankeyVisual). The
        //   visual reads `node.getLayout().value` written by the layout, so the layout MUST run first;
        //   both run in `render`/`update` below. The `dragNode` action + roam are DEFERRED (roamHelper
        //   not ported); see chart/sankey/sankeyInstall.swift.
        ComponentModel.registerClass(SankeySeriesModel.self)

        // -- chart/lines/install.ts (minimal) -- registerChartView(LinesView) +
        //   registerSeriesModel(LinesSeries) + registerLayout(linesLayout) + registerVisual(linesVisual).
        //   Lines is a coord-space series (default coord 'geo'; ONLY cartesian2d is rendered by the ported
        //   static view — polar/geo/calendar are PORT-TODO in linesLayout/LinesView). `linesLayout` is a
        //   SERIES_STAGE_TASK (seriesType 'lines') whose reset→progress writes each line's per-item layout
        //   (`data.setItemLayout(i, pts)`), same wiring as candlestickLayout. LinesView also inlines the
        //   per-item dataToPoint + curveness control-point math (like ScatterView/LineView), so the layout
        //   stage is run here for fidelity but the view does not depend on it. The effect (moving-dot/trail)
        //   + large draw path are ANIMATED/DEFERRED; linesVisual (palette stroke) lands with a later phase —
        //   the shared visual/style stage supplies the lineStyle→stroke color meanwhile. linesInstall.swift
        //   is commented-only (diffable surface); actual wiring lives here.
        ComponentModel.registerClass(LinesSeriesModel.self)

        // -- chart/gauge/install.ts (minimal) -- registerSeriesModel(GaugeSeries) + registerChartView(GaugeView).
        //   Gauge is COORDLESS (no coordinate system, no layout/visual stage): center/radius/startAngle/endAngle
        //   drive geometry directly, and GaugeView computes the axis arc bands, ticks, split lines, pointer,
        //   anchor and title/detail text in `render`. Mirrors how pie/funnel register their series model here
        //   (view keyed by subType in `_chartViewFactories` below); no coord-sys and no separate layout stage.
        ComponentModel.registerClass(GaugeSeriesModel.self)

        // -- chart/themeRiver/install.ts (minimal) -- registerChartView(ThemeRiverView) +
        //   registerSeriesModel(ThemeRiverSeriesModel) + registerLayout(themeRiverLayout) +
        //   registerProcessor(dataFilter('themeRiver')). ThemeRiver is a streamgraph on the SINGLE
        //   coordinate system (dependencies ["singleAxis"]); its layout stage reads the Single coord rect +
        //   axis orient and writes each datum's {layerIndex,x,y0,y} band point, which ThemeRiverView reads
        //   back to draw one Polygon per layer. themeRiverLayout runs in render()/update() AFTER the coord
        //   create/update (it casts seriesModel.coordinateSystem to Single). The dataFilter processor is a
        //   no-op in this slim path (no legend-select provider); see themeRiverInstall.swift.
        ComponentModel.registerClass(ThemeRiverSeriesModel.self)                   // registerSeriesModel(ThemeRiverSeries)

        // -- component/radar/install.ts + chart/radar/install.ts (radar coordinate system) --
        //   registerCoordinateSystem('radar', Radar) + registerComponentModel(RadarModel) +
        //   registerComponentView(RadarComponentView) + registerSeriesModel(RadarSeriesModel) +
        //   registerChartView(RadarView) + registerLayout(radarLayoutStageHandler) +
        //   registerPreprocessor(radarBackwardCompat) + registerVisual(legendIcon 'roundRect').
        //   Radar is the FIRST non-cartesian coordinate system wired: the coord-sys register mirrors the
        //   cartesian2d register above (a CoordinateSystemCreator forwarding to Radar.create). The
        //   RadarModel is the coord-sys HOST component (like GridModel); its per-indicator AxisBaseModels
        //   feed the IndicatorAxes the coord builds. `_coordSysMgr.create`/`.update` (update() stages 3/5)
        //   build + update each Radar; the radarLayout stage (run in render()) stores each datum's closed
        //   point ring, which RadarView reads back. The backwardCompat preprocessor runs in setOption.
        //   registerVisual(legendIcon 'roundRect') → PORT-TODO: deferred (legend-select provider not wired).
        CoordinateSystemManager.register("radar", RadarCoordinateSystemCreator()) // registerCoordinateSystem('radar', Radar)
        ComponentModel.registerClass(RadarModel.self)                             // registerComponentModel(RadarModel)
        ComponentModel.registerClass(RadarSeriesModel.self)                       // registerSeriesModel(RadarSeries)

        // -- component/polar/install.ts (polar coordinate system) --
        //   registerCoordinateSystem('polar', Polar) + registerComponentModel(PolarModel) +
        //   axisModelCreator(registers, 'angle'/'radius', AngleAxisModel/RadiusAxisModel, extra) +
        //   registerComponentView(AngleAxisView) + registerComponentView(RadiusAxisView) +
        //   registerComponentView(PolarView) [+ PolarAxisPointer, deferred].
        //   Polar is the SECOND non-cartesian coordinate system wired: the coord-sys register mirrors the
        //   cartesian2d/radar registers above (a CoordinateSystemCreator forwarding to polarCreator.create).
        //   The PolarModel is the coord-sys HOST component (like GridModel/RadarModel); its angleAxis +
        //   radiusAxis component models feed the AngleAxis/RadiusAxis the coord builds. Unlike the cartesian
        //   x/y stand-ins (SlimXAxisModel), the polar axis models are the REAL AngleAxisModel/RadiusAxisModel
        //   (concrete PolarAxisModel subclasses), registered directly here — so `PolarModel.findAxisModel`'s
        //   `as? PolarAxisModel` + `getCoordSysModel()` resolve end-to-end (the axisModelCreator dynamic-
        //   subclass gap that blocks the cartesian path does not apply). The polar axis models carry the
        //   angle/radius extra defaults (startAngle 90 / splitNumber) via `polarAxisExtraOption` (merged in
        //   mergeDefaultAndTheme). `_coordSysMgr.create`/`.update` (update() stages 3/5) build + update each
        //   Polar; the AngleAxisView/RadiusAxisView draw the angle rings + radius axis backdrop.
        CoordinateSystemManager.register("polar", PolarCoordinateSystemCreator()) // registerCoordinateSystem('polar', Polar)
        ComponentModel.registerClass(PolarModel.self)                             // registerComponentModel(PolarModel)
        ComponentModel.registerClass(AngleAxisModel.self)                         // axisModelCreator(..,'angle',..)
        ComponentModel.registerClass(RadiusAxisModel.self)                        // axisModelCreator(..,'radius',..)

        // -- coord/single/install.ts (single coordinate system) --
        //   registerComponentModel(SingleAxisModel) + axisModelCreator(registers, 'single', SingleAxisModel,
        //   SingleAxisModel.defaultOption) + registerCoordinateSystem('single', singleCreator) +
        //   registerComponentView(SingleAxisView) [in component/axis/install.ts].
        //   Single is the FOURTH coordinate system wired: the coord-sys register mirrors the polar register
        //   above (a CoordinateSystemCreator forwarding to singleCreator.create). SingleAxisModel is the
        //   coord-sys HOST component AND the axis model at once (getCoordSysModel() returns self); like the
        //   polar axis models it is registered directly (this port has no runtime axisModelCreator — the
        //   per-type value/category/time/log subclasses it would generate are collapsed into the one model,
        //   same deviation as the polar axis models). `_coordSysMgr.create`/`.update` build + update each
        //   Single; SingleAxisView draws the axis backdrop + splitLine grid.
        CoordinateSystemManager.register("single", SingleCoordinateSystemCreator()) // registerCoordinateSystem('single', singleCreator)
        ComponentModel.registerClass(SingleAxisModel.self)                          // registerComponentModel(SingleAxisModel)

        // -- coord/parallel/install.ts + component/parallel/install.ts + chart/parallel/install.ts --
        //   registerCoordinateSystem('parallel', parallelCoordSysCreator) + registerComponentModel(ParallelModel)
        //   + registerComponentModel(ParallelAxisModel) + axisModelCreator(registers, 'parallel', ParallelAxisModel,
        //   defaultAxisOption) + registerPreprocessor(parallelPreprocessor) + registerComponentView(ParallelView)
        //   + registerComponentView(ParallelAxisView) + registerSeriesModel(ParallelSeriesModel) +
        //   registerChartView(ParallelView[chart]) + registerVisual(PRIORITY.VISUAL.BRUSH, parallelVisual).
        //   Parallel is the FIFTH coordinate system wired: the coord-sys register mirrors the single register
        //   above. ParallelModel is the coord-sys HOST component (dependencies ["parallelAxis"], so parallelAxis
        //   models load first); ParallelAxisModel is registered DIRECTLY under mainType 'parallelAxis' (same
        //   direct-registration shortcut as SingleAxisModel/the polar axis models — no runtime axisModelCreator),
        //   so `getComponent('parallelAxis', …) as! ParallelAxisModel` in the coord + `axis.dim` /
        //   getAreaSelectStyle() in ParallelAxisView resolve end-to-end. `_coordSysMgr.create`/`.update`
        //   (update() stages 3/5) build + update each Parallel; ParallelAxisView draws each axis backdrop (N
        //   registered 'parallelAxis' component views), ParallelView[component] is interaction-only, and the
        //   chart-side ParallelView draws one Polyline per data item. The parallelPreprocessor (creates
        //   parallelAxis components from parallel.parallelAxisDefault) runs in setOption. The brush/axis-drag/
        //   active-interval selection ACTIONS are DEFERRED (// PORT-TODO in ParallelComponentView/ParallelAxisModel).
        CoordinateSystemManager.register("parallel", ParallelCoordinateSystemCreator()) // registerCoordinateSystem('parallel', parallelCoordSysCreator)
        ComponentModel.registerClass(ParallelModel.self)                            // registerComponentModel(ParallelModel)
        ComponentModel.registerClass(ParallelAxisModel.self)                        // registerComponentModel(ParallelAxisModel) + axisModelCreator(..,'parallel',..)
        ComponentModel.registerClass(ParallelSeriesModel.self)                      // registerSeriesModel(ParallelSeries)

        // -- component/title/install.ts -- registerComponentModel(TitleModel) + registerComponentView(TitleView).
        ComponentModel.registerClass(TitleModel.self)

        // -- component/graphic/install.ts -- registerComponentModel(GraphicComponentModel) +
        //   registerComponentView(GraphicComponentView) + registerPreprocessor(graphicOptionPreprocessor).
        //   The preprocessor is invoked in `setOption` (see below).
        ComponentModel.registerClass(GraphicComponentModel.self)

        // -- component/legend/installLegendPlain.ts -- registerComponentModel(LegendModel) +
        //   registerComponentView(LegendView) + registerSubTypeDefaulter('legend', () => 'plain').
        //   LegendModel.type == 'legend.plain', so a subtype defaulter is required for the bare
        //   `legend: {...}` option (mainType 'legend', no subtype) to resolve to 'legend.plain'.
        ComponentModel.registerClass(LegendModel.self)
        ComponentModel.registerSubTypeDefaulter("legend", { _ in "plain" })

        // -- component/marker/installMark{Point,Line,Area}.ts --
        //   PORT-TODO (BLOCKED, left UNREGISTERED): the marker components render per-series inner models
        //   whose render path depends on deep deps that are still stubbed in this phase:
        //     - CoordinateSystem.getAxis/getOtherAxis dispatch the nil-returning protocol defaults
        //       (Cartesian2D's specialized signatures do not witness them) → statistic (min/max/average/
        //       median) and single-axis (Infinity) markers cannot resolve axes/containData.
        //     - SeriesModel.indicesOfNearest is stubbed to [] (statistic coord resolution).
        //     - SymbolDraw/LineDraw are replaced by MarkerSymbolDraw/local stand-ins; util/states
        //       enterBlur/leaveBlur and util/graphic traverseUpdateZ/retrieveZInfo are no-op stubs.
        //   The files COMPILE and are kept in place; wiring (registerClass + view factory + the
        //   markPoint/markLine/markArea preprocessors) is deferred until those deps land.
        //     ComponentModel.registerClass(MarkPointModel.self) / MarkLineModel / MarkAreaModel

        // View factories (upstream: registerComponentView / registerChartView; see header deviation).
        // (component views keyed by mainType; chart views keyed by subType.)
        // These are file-scope closures, assigned lazily on first `install`.
    }

    // Upstream stores the view CLASS; we store factories (see header). Keyed as upstream `getClass`
    // resolves: component views by mainType (grid/xAxis/yAxis), chart views by series subType (bar).
    private let _componentViewFactories: [String: () -> ComponentView] = [
        "grid": { GridView() },
        "xAxis": { CartesianXAxisView() },
        "yAxis": { CartesianYAxisView() },
        // Phase 7 static components (keyed by mainType; legend's subtype 'plain' is resolved by the
        //   registerSubTypeDefaulter above, but the VIEW is still looked up by mainType 'legend').
        "title": { TitleView() },
        "graphic": { GraphicComponentView() },
        "legend": { LegendView() },
        // Radar coord-sys component view (draws the axis lines/ticks/names + split rings/areas backdrop);
        //   registered under mainType 'radar' (upstream install.ts `registerComponentView(RadarView)`).
        "radar": { RadarComponentView() },
        // Polar coord-sys component views: the angleAxis view draws the angle rings (axisLine circle/arc +
        //   split lines + split areas + tick labels around the ring); the radiusAxis view draws the radial
        //   axis line + ticks + split lines. Registered under mainType 'angleAxis'/'radiusAxis' (upstream
        //   install.ts `registerComponentView(AngleAxisView)` / `registerComponentView(RadiusAxisView)`).
        "angleAxis": { AngleAxisView() },
        "radiusAxis": { RadiusAxisView() },
        // Single coord-sys component view (draws the single axis line + ticks + labels + splitLine grid
        //   across the coord rect). Registered under mainType 'singleAxis' (upstream component/axis/install.ts
        //   `registerComponentView(SingleAxisView)`).
        "singleAxis": { SingleAxisView() },
        // Parallel coord-sys component views. `parallelAxis` -> ParallelAxisView draws each axis backdrop
        //   (one registered view per parallelAxis component, via AxisBuilder → the N-axis backdrop is the
        //   composition of them). `parallel` -> ParallelComponentView (upstream component ParallelView) is
        //   interaction-only (axis-expand) and draws nothing. Registered under mainType 'parallelAxis' /
        //   'parallel' (upstream component/parallel/install.ts registerComponentView(ParallelAxisView) /
        //   registerComponentView(ParallelView)).
        "parallelAxis": { ParallelAxisView() },
        "parallel": { ParallelComponentView() }
    ]
    private let _chartViewFactories: [String: () -> ChartView] = [
        "bar": { BarView() },
        "line": { LineView() },
        "scatter": { ScatterView() },
        // EffectScatter chart view (static base symbols; ripple DEFERRED). Registered under series subType
        //   'effectScatter' (upstream chart/effectScatter/install.ts `registerChartView(EffectScatterView)`).
        "effectScatter": { EffectScatterView() },
        "pie": { PieView() },
        "funnel": { FunnelView() },
        "candlestick": { CandlestickView() },
        "boxplot": { BoxplotView() },
        "sunburst": { SunburstView() },
        "treemap": { TreemapView() },
        "tree": { TreeView() },
        "graph": { GraphView() },
        // Sankey chart view (coordless flow): node Rects + edge ribbon SankeyPaths + node/edge labels;
        //   geometry from the sankey box layout stage. Registered under series subType 'sankey'
        //   (upstream chart/sankey/install.ts `registerChartView(SankeyView)`).
        "sankey": { SankeyView() },
        // Lines chart view (one Line/BezierCurve per two-point line, or one Polyline per polyline line);
        //   geometry inlined via coord.dataToPoint + the curveness control-point formula (the layout STAGE
        //   is registered/run but the view projects coords itself, like ScatterView/LineView). Registered
        //   under series subType 'lines' (upstream chart/lines/install.ts `registerChartView(LinesView)`).
        "lines": { LinesView() },
        // Gauge chart view (coordless): axis arc color bands, split lines + ticks, tick labels, pointer
        //   needle, anchor, and title/detail text — all computed in render. Registered under series subType
        //   'gauge' (upstream chart/gauge/install.ts `registerChartView(GaugeView)`).
        "gauge": { GaugeView() },
        // Radar chart view (per-item polyline outline + polygon area + vertex symbols); registered under
        //   series subType 'radar' (upstream install.ts `registerChartView(RadarView)`).
        "radar": { RadarView() },
        // ThemeRiver streamgraph view (one Polygon band per layer, on the single coord); geometry from the
        //   themeRiverLayout stage. Registered under series subType 'themeRiver'
        //   (upstream chart/themeRiver/install.ts `registerChartView(ThemeRiverView)`).
        "themeRiver": { ThemeRiverView() },
        // Parallel chart view (one Polyline per data item across the N axes); geometry from
        //   coord.dataToPoint per dimension. Registered under series subType 'parallel'
        //   (upstream chart/parallel/install.ts `registerChartView(ParallelView)`).
        "parallel": { ParallelView() }
    ]

    // ------------------------------------------------------------------------
    // setOption — build the GlobalModel, then run the update cycle.
    // Mirrors `ECharts.setOption` → `prepare` + `updateMethods.prepareAndUpdate` in the minimal case:
    //   build a fresh `GlobalModel` via `OptionManager` (the ported option → model pipeline), then
    //   `update()`. Re-`setOption` merge/notMerge semantics are out of scope (each call rebuilds).
    // ------------------------------------------------------------------------
    public func setOption(_ option: [String: Any]) {
        var opt = option
        // Preprocessor from `installSimple.ts`: inject an (empty) grid if x+y axes are present but no
        //   grid was declared, so the axis models can resolve their coord-sys (`getCoordSysModel`).
        if opt["xAxis"] != nil && opt["yAxis"] != nil && opt["grid"] == nil {
            opt["grid"] = [String: Any]()
        }
        // Preprocessor from component/graphic/install.ts: normalize the `graphic` option into its
        //   canonical `[{ elements: [...] }]` shape so GraphicComponentModel can consume it.
        graphicOptionPreprocessor(&opt)
        // Preprocessor from chart/radar/backwardCompat.ts (registerPreprocessor(radarBackwardCompat)):
        //   migrate ec2's `polar` radar option (a `polar` with an `indicator`) into `radar`, and map a
        //   series' `polarIndex` → `radarIndex`. Mutates option.polar/option.radar/option.series in place
        //   (inout write-back, value-type semantics, per the candlestick preprocessor precedent).
        radarBackwardCompat(&opt)
        // Preprocessor from coord/parallel/install.ts (registerPreprocessor(parallelPreprocessor)):
        //   create the `parallelAxis` components from `parallel.parallelAxisDefault` when absent, and merge
        //   the per-axis option from the parallel component. Mutates option.parallel/option.parallelAxis in
        //   place (inout write-back; ECUnitOption == [String: Any], so `&opt` binds directly — the bespoke
        //   `inout ECUnitOption` signature is the same value type, no adapter needed).
        parallelPreprocessor(&opt)

        let ecModel = GlobalModel()
        let om = OptionManager(_api)
        // init(option, parentModel, ecModel, theme, locale, optionManager)
        ecModel.`init`(nil, nil, nil, [String: Any](), [String: Any](), om)
        ecModel.setOption(opt, nil, [])
        self._model = ecModel

        update()
    }

    // ------------------------------------------------------------------------
    // §UPDATE — faithful stage ORDER of `updateMethods.update` (echarts.ts:1880), minimal bodies.
    // ------------------------------------------------------------------------
    private func update() {
        guard let ecModel = _model else { return }          // upstream: if (!ecModel) return;
        let api = _api!

        // (1) restoreData — re-derive component/series state (upstream: scheduler.restoreData).
        ecModel.restoreData()

        // (2) performSeriesTasks — perform each series' DATA task. Its reset (`dataTaskReset`) is
        //     `setData(getRawData().cloneShallow())`, which populates the `getData()` result (the inner
        //     data slot). Upstream drives this through the Scheduler pipeline (`renderTask.perform`);
        //     with the Scheduler unported (`getCurrentTask` returns nil), the task reset is invoked
        //     directly here — otherwise `getData()` force-unwraps a nil inner data (Series.swift:387).
        ecModel.eachSeries { seriesModel, _ in
            _ = dataTaskReset(seriesModel.dataTask.context)
        }

        // (3) coordSysMgr.create — build the Grid coordinate system(s), lay them out on the container
        //     rect, and inject `coordinateSystem` into each series (Grid.create → injectCoordSysByOption).
        _coordSysMgr.create(ecModel, api)
        // lifecycle.trigger('coordsys:aftercreate', ...) — PORT-TODO: lifecycle not ported (no listeners
        //     needed for a bar chart).

        // (4) performDataProcessorTasks — the processor subset a bar needs = axis STATISTICS (feeds the
        //     cross-series bar layout). Data-stack / filter (dataZoom) / sample processors are PORT-TODO
        //     skips (single unstacked series, no dataZoom). Run the captured processor overallResets.
        for processor in EChartsSlim._registers.capturedProcessors {
            processor(ecModel)
        }

        // PROCESSOR — graph categoryFilter (upstream `registerProcessor(PROCESSOR.FILTER, categoryFilter)`).
        //   Filters graph nodes by legend selection; self-gates to a no-op when no legend component is
        //   present. Must run BEFORE the graph layout stage (layout reads the filtered data), so it lives
        //   in the data-processor stage like upstream. OVERALL handler — invoke its overallReset directly.
        graphCategoryFilterStageHandler.overallReset?(ecModel, api, nil)

        // updateStreamModes(...) — PORT-TODO skip (progressive/stream rendering out of scope).

        // (5) coordSysMgr.update — update axis pixel + data extents from the (now processed) series data,
        //     and build the axis tick/label geometry (Grid.update → resize → createAxisBiulders).
        _coordSysMgr.update(ecModel, api)

        // (6) VISUAL — resolve series/data styles (fill/stroke from palette + itemStyle).
        //     Upstream: clearColorPalette + scheduler.performVisualTasks. Here: run the ported visual
        //     stage handlers directly (visual/style.swift), in upstream registration order.
        performVisualStage(ecModel, api)

        // background / darkMode (zr.setBackgroundColor / setDarkMode) — PORT-TODO: the driver exposes a
        //     bare Group; background is a host concern.

        // (7) LAYOUT + RENDER — `render(this, ecModel, api, ...)`.
        render(ecModel, api)
    }

    // ------------------------------------------------------------------------
    // VISUAL stage — run the ported `visual/style.swift` handlers.
    // ------------------------------------------------------------------------
    private func performVisualStage(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        // Order mirrors upstream registration (core/echarts.ts:3360-3362): seriesStyleTask (GLOBAL),
        //   then dataStyleTask, then dataColorPaletteTask (both CHART_DATA_CUSTOM). The palette task
        //   MUST run LAST: it reads the `colorFromPalette` item visual that seriesStyleTask sets, and
        //   assigns per-item palette colors for `colorBy:'data'` series (e.g. pie slices). Running it
        //   first (as before) left `colorFromPalette` unset → every pie slice collapsed to one color.
        runSeriesStageHandler(seriesStyleTask, ecModel, api)
        runSeriesStageHandler(dataStyleTask, ecModel, api)
        runOverallStageHandler(dataColorPaletteTask, ecModel, api)
    }

    /// Run an OVERALL_STAGE_TASK handler (has `overallReset`).
    private func runOverallStageHandler(_ handler: StageHandler, _ ecModel: GlobalModel, _ api: ExtensionAPI) {
        handler.overallReset?(ecModel, api, nil)
    }

    /// Run a SERIES_STAGE_TASK handler (`reset` per series, then drive its returned executor over the
    /// data range). Upstream the Scheduler drives `progress`/`dataEach` over data chunks; here it is a
    /// single synchronous pass over `[0, data.count())` (no progressive chunking — documented).
    private func runSeriesStageHandler(_ handler: StageHandler, _ ecModel: GlobalModel, _ api: ExtensionAPI) {
        guard let reset = handler.reset else { return }
        ecModel.eachSeries { seriesModel, _ in
            // seriesType gate (handler.seriesType) — only run for matching series.
            if let st = handler.seriesType, seriesModel.subType != st {
                return
            }
            guard let executor = reset(seriesModel, ecModel, api, nil) as? StageHandlerProgressExecutor else {
                return
            }
            let data = seriesModel.getData()
            let count = data.count()
            if let dataEach = executor.dataEach {
                for i in 0..<count {
                    dataEach(data, Double(i))
                }
            }
            else if let progress = executor.progress {
                // Build a single full-range params (upstream `TaskProgressParams` has start/end/count/next).
                // Upstream the Scheduler supplies `params.next` (a data-index iterator); handlers such as
                // the bar per-item layout (`createProgressiveLayout`'s progress) loop `while (dataIndex =
                // params.next())`. Without a `next` iterator that loop never runs and the handler is a
                // silent no-op — so provide a full-range [0, count) iterator here.
                var cursor = 0
                let next: TaskDataIteratorNext = {
                    if cursor < count {
                        let v = Double(cursor)
                        cursor += 1
                        return v
                    }
                    return nil
                }
                let params = StageHandlerProgressParams(start: 0, end: Double(count), count: Double(count), next: next)
                progress(params, data)
            }
        }
    }

    // ------------------------------------------------------------------------
    // render — `render` (echarts.ts:2430): allocateZlevels (skip) → renderComponents → renderSeries.
    // LAYOUT runs just before series render (upstream layout tasks are part of the visual-task pipe;
    // here the bar cross-series layout is invoked explicitly right before `renderSeries`).
    // ------------------------------------------------------------------------
    private func render(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        // allocateZlevels(ecModel) — PORT-TODO skip (single grid + one series; default z ordering).

        prepareView(isComponent: true, ecModel: ecModel, api: api)
        prepareView(isComponent: false, ecModel: ecModel, api: api)

        renderComponents(ecModel, api)

        // LAYOUT — bar cross-series layout (sets bandWidth/offset/size on each series' data layout).
        //   Depends on the axis statistics computed in stage (4).
        EChartsSlim._barLayoutHandler.overallReset?(ecModel, api, nil)
        // LAYOUT (per item) — the bar PROGRESSIVE_LAYOUT handler computes each bar's x/y/width/height
        //   from bandWidth/offset/size + the cartesian `dataToPoint`, and stores it via
        //   `data.setItemLayout`. This is a SERIES_STAGE_TASK (has `reset`), so drive it through the same
        //   `runSeriesStageHandler` used for the visual stages (the `next`-iterator fix above makes its
        //   `progress` executor actually iterate the data). `BarView.getLayoutCartesian2D` consumes it.
        runSeriesStageHandler(EChartsSlim._barProgressiveLayoutHandler, ecModel, api)

        // LAYOUT — pie angle/radius layout (upstream `registerLayout(pieLayout)`). Pie has no cartesian
        //   coord, so `_coordSysMgr` never injects geometry; this OVERALL stage computes each datum's
        //   start/end angle + r0/r via `getCircleLayout` and stores it with `data.setItemLayout`, which
        //   `PieView.render` reads back. Bare 2-arg handler (like the bar layout handlers above).
        pieLayout(ecModel, api)

        // LAYOUT — funnel piece polygons (upstream `registerLayout(funnelLayoutStageHandler)`). Like pie,
        //   funnel is box-usage with no cartesian coord; this OVERALL stage computes each piece's 4-corner
        //   `points` (via createBoxLayoutReference + linearMap) and stores it with `data.setItemLayout`,
        //   which `FunnelView.render` reads back.
        funnelLayout(ecModel, api)

        // LAYOUT + VISUAL — candlestick. Upstream registers `candlestickLayout` (a SERIES_STAGE_TASK that
        //   computes each candle's 8-point `ends` + `sign` from the cartesian `dataToPoint`) and
        //   `candlestickVisual` (colors body/whiskers bull/bear FROM `itemLayout.sign`). candlestickVisual
        //   READS the sign written by candlestickLayout, so — unlike the generic visual stage, which runs
        //   before layout — the layout MUST run first. Upstream orders them by pipeline priority (layout
        //   before visual); the slim driver reproduces that by running BOTH here (layout, then visual),
        //   after the generic performVisualStage (candlestickVisual only extends fill/stroke onto the
        //   existing item-visual style, so running it last is correct). Both are SERIES_STAGE_TASKs.
        runSeriesStageHandler(candlestickLayout, ecModel, api)
        runSeriesStageHandler(candlestickVisual, ecModel, api)

        // LAYOUT — boxplot box/whisker geometry (upstream `registerLayout(boxplotLayoutStageHandler)`).
        //   An OVERALL stage (cross-series offset/width from the axis bandWidth statistics); computes each
        //   datum's `ends` + `initBaseline` via `dataToPoint` and stores it with `data.setItemLayout`,
        //   which `BoxplotView.render` reads back. Colors come from the generic visual stage
        //   (visualDrawType:'stroke'), so no dedicated boxplot visual handler is needed. Bare 1-arg handler.
        boxplotLayout(ecModel)

        // LAYOUT + VISUAL — sunburst. Upstream registers `sunburstLayoutStageHandler` (an OVERALL stage
        //   that computes each tree node's sector angle/radius from `center`/`radius`) and
        //   `sunburstVisualStageHandler` (an OVERALL stage that colors each node). Sunburst is coordless
        //   (hierarchical, box-like usage like pie); SunburstView reads the per-node layout back. Both are
        //   OVERALL stage handlers — invoke their `overallReset` directly (like the pie layout stage).
        sunburstLayoutStageHandler.overallReset?(ecModel, api, nil)
        sunburstVisualStageHandler.overallReset?(ecModel, api, nil)

        // LAYOUT + VISUAL — treemap. Upstream registers `treemapLayout` (a SERIES_STAGE_TASK whose `reset`
        //   computes each node's rect + area/isInView/invisible) and `treemapVisual` (a SERIES_STAGE_TASK
        //   whose `reset` colors each node FROM that layout). Like candlestick, treemapVisual READS the
        //   layout, so the layout MUST run first; both are SERIES_STAGE_TASKs (reset does the full work and
        //   returns nil), so drive them through `runSeriesStageHandler` (layout, then visual).
        runSeriesStageHandler(treemapLayout, ecModel, api)
        runSeriesStageHandler(treemapVisual, ecModel, api)

        // LAYOUT + VISUAL — tree. Upstream registers `treeLayout` (a 2-arg OVERALL layout fn that computes
        //   each node's x/y via the non-layered tidy-tree walk) and `treeVisualStageHandler` (an OVERALL
        //   stage that sets per-node symbol colors). Tree is coordless (hierarchical, box-usage); TreeView
        //   reads the per-node layout back. `treeLayout` is a bare 2-arg fn (like pie/sunburst layout); the
        //   visual is an OVERALL stage handler.
        treeLayout(ecModel, api)
        treeVisualStageHandler.overallReset?(ecModel, api, nil)

        // LAYOUT + VISUAL — graph. Upstream registers two layout stage handlers
        //   (graphCircularLayoutStageHandler for `layout:'circular'`, graphSimpleLayoutStageHandler for
        //   `layout:'none'`/coord-sys), and two visual stage handlers (graphCategoryVisualStageHandler
        //   colors nodes, graphEdgeVisualStageHandler colors edges FROM the node fill). Each layout
        //   handler self-gates on the series `layout` option, so both run every render (only the matching
        //   one does work). GraphView reads each node's [x,y] + each edge's point list from the layout.
        //   The edge visual MUST run AFTER the category visual (edge source/target stroke reads node
        //   fill). All four are OVERALL stage handlers (like sunburst/tree visual).
        // COORD SYS — upstream registers the graph's roam `View` coordinate system via a coord-sys creator
        //   (`registerCoordinateSystem('view', View)` + `createViewCoordSys`) that runs before layout. That
        //   full `View` is deferred (roam §5); `createViewCoordSys` here assigns a stand-in view coord sys
        //   (GraphViewCoordSys) onto each graph series so the layout stages can read its bounding rect.
        //   MUST run before the layout handlers below (circularLayout force-derefs the coord sys).
        createViewCoordSys(ecModel, api)
        graphCircularLayoutStageHandler.overallReset?(ecModel, api, nil)
        graphSimpleLayoutStageHandler.overallReset?(ecModel, api, nil)
        graphCategoryVisualStageHandler.overallReset?(ecModel, api, nil)
        graphEdgeVisualStageHandler.overallReset?(ecModel, api, nil)

        // LAYOUT + VISUAL — sankey. Upstream registers `sankeyLayoutStageHandler` (an OVERALL box-layout
        //   stage that computes each node's {x,y,dx,dy} column/height + each edge's {sy,ty,dy} ribbon
        //   offsets, and sets `seriesModel.layoutInfo`) and `sankeyVisualStageHandler` (an OVERALL stage
        //   that colors each node FROM `node.getLayout().value`, and each edge from its lineStyle). Sankey
        //   is coordless (box usage, no cartesian coord); SankeyView reads the per-node/per-edge layout
        //   back. The visual READS the value written by the layout, so — like candlestick/treemap — the
        //   layout MUST run first. `sankeyLayout` is a bare 2-arg fn (like graph/funnel layout); the
        //   visual is an OVERALL stage handler.
        sankeyLayout(ecModel, api)
        sankeyVisualStageHandler.overallReset?(ecModel, api, nil)

        // LAYOUT — lines per-item point projection (upstream `registerLayout(linesLayout)`). A
        //   SERIES_STAGE_TASK (seriesType 'lines') whose `reset`→`progress` maps each line's data-space
        //   coords through the cartesian `dataToPoint` (plus the quadratic curveness control point) and
        //   stores it with `data.setItemLayout(i, pts)`. Same wiring as candlestickLayout. `LinesView.render`
        //   inlines the same math (like ScatterView/LineView), so the view does not strictly depend on this
        //   stage, but it is run here for fidelity to the upstream pipeline. Only cartesian2d is handled
        //   (polar/geo/calendar are PORT-TODO in linesLayout).
        runSeriesStageHandler(linesLayout, ecModel, api)

        // LAYOUT — radar point rings (upstream `registerLayout(radarLayoutStageHandler)`). Radar HAS a
        //   (non-cartesian) coordinate system, already built + updated by `_coordSysMgr.create`/`.update`
        //   (update() stages 3/5). This OVERALL stage maps each datum's per-indicator values through
        //   `coordSys.dataToPoint` into a CLOSED point ring (axes+1 points, last == copy of first) and
        //   stores it with `data.setItemLayout`, which `RadarView.render` reads back. Bare 1-arg handler
        //   (like boxplotLayout); the radarLayoutStageHandler wrapper exists for the upstream registrar,
        //   but the slim driver invokes `radarLayout(ecModel)` directly (mirrors pieLayout).
        radarLayout(ecModel)

        // LAYOUT — themeRiver stream bands (upstream `registerLayout(themeRiverLayoutStageHandler)`).
        //   ThemeRiver HAS a (non-cartesian) single coordinate system, already built + updated by
        //   `_coordSysMgr.create`/`.update` (update() stages 3/5). This OVERALL stage reads the Single coord
        //   rect + axis orient and writes each datum's {layerIndex,x,y0,y} band point (+ a "layoutInfo" rect/
        //   boundaryGap) via `data.setItemLayout`/`data.setLayout`, which `ThemeRiverView.render` reads back
        //   to draw one Polygon per layer. Run AFTER the coord update (it casts seriesModel.coordinateSystem
        //   to Single). `themeRiverLayoutStageHandler` wraps this for the upstream registrar, but the slim
        //   driver invokes `themeRiverLayout(ecModel, api)` directly (mirrors sankeyLayout / radarLayout).
        themeRiverLayout(ecModel, api)

        // VISUAL — parallel per-line opacity (upstream `registerVisual(PRIORITY.VISUAL.BRUSH, parallelVisual)`).
        //   Parallel HAS a coordinate system, already built + updated by `_coordSysMgr.create`/`.update`
        //   (update() stages 3/5). This SERIES_STAGE_TASK sets each line's item-visual `style.opacity` from
        //   the (deferred) active-state → in the static-render phase every row is 'normal', giving each
        //   polyline the `lineStyle.opacity`. ParallelView.render reads that item-visual style back. Run
        //   AFTER the generic performVisualStage (it only extends `opacity` onto the existing style bag).
        runSeriesStageHandler(parallelVisual, ecModel, api)

        renderSeries(ecModel, api)
    }

    // prepareView — get-or-create a view per component/series, add its group to the root + storage.
    // Faithful reduction of `prepareView` (echarts.ts:1687): no reuse across notMerge/replaceMerge
    // (each setOption rebuilds), no dispose of dead views (fresh model each call).
    private func prepareView(isComponent: Bool, ecModel: GlobalModel, api: ExtensionAPI) {
        func doPrepare(_ model: ComponentModel) {
            let viewId = "_ec_\(model.componentIndex)_\(model.type)"
            if isComponent {
                let view = _componentsMap[viewId] ?? {
                    // getClass(classType.main, classType.sub) → factory keyed by mainType.
                    guard let factory = _componentViewFactories[model.mainType] else {
                        // PORT-TODO: no component view registered for this mainType (out of bar scope).
                        return nil as ComponentView?
                    }
                    let v = factory()
                    v.`init`(ecModel, api)
                    _componentsMap[viewId] = v
                    _componentsViews.append(v)
                    _ = root.add(v.group)
                    storage.addRoot(v.group)
                    return v
                }()
                guard let componentView = view else { return }
                componentView.__model = model
                _componentViewByModel[ObjectIdentifier(model)] = componentView
            }
            else {
                guard let seriesModel = model as? SeriesModel else { return }
                let view = _chartsMap[viewId] ?? {
                    // ChartView.getClass(classType.sub) → factory keyed by series subType.
                    guard let factory = _chartViewFactories[seriesModel.subType] else {
                        // PORT-TODO: no chart view registered for this subType (only 'bar' in scope).
                        return nil as ChartView?
                    }
                    let v = factory()
                    v.init_(ecModel, api)
                    _chartsMap[viewId] = v
                    _chartsViews.append(v)
                    _ = root.add(v.group)
                    storage.addRoot(v.group)
                    return v
                }()
                guard let chartView = view else { return }
                chartView.__model = seriesModel
                _chartViewByModel[ObjectIdentifier(seriesModel)] = chartView
                // upstream: `scheduler.prepareView(view, model, ...)` builds the series pipeline and sets
                //   `seriesModel.pipelineContext` (progressive/large flags read by `BarView._updateDrawMode`
                //   at BarView.swift:221). With the Scheduler unported, set a minimal non-progressive,
                //   non-large context directly.
                seriesModel.pipelineContext = PipelineContext(progressiveRender: false, large: false, modDataCount: nil)
            }
        }

        if isComponent {
            ecModel.eachComponent({ (mainType, model, _) in
                if mainType != "series" { doPrepare(model) }
            })
        }
        else {
            ecModel.eachSeries { seriesModel, _ in doPrepare(seriesModel) }
        }
    }

    // renderComponents (echarts.ts:2452) — minimal: clearStates/updateZ/updateStates dropped (states
    // system deferred). Just `componentView.render(model, ecModel, api, payload)`.
    private func renderComponents(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        let payload = Payload(type: "")
        for componentView in _componentsViews {
            guard let model = componentView.__model else { continue }
            componentView.render(model, ecModel, api, payload)
        }
    }

    // renderSeries (echarts.ts:2472) — minimal: bypass the Scheduler `renderTask.perform` and call
    // `chartView.render(...)` directly (documented deviation; no progressive/incremental rendering).
    private func renderSeries(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        let payload = Payload(type: "")
        ecModel.eachSeries { seriesModel, _ in
            guard let chartView = self._chartViewByModel[ObjectIdentifier(seriesModel)] else { return }
            chartView.render(seriesModel, ecModel, api, payload)
        }
    }

    // ------------------------------------------------------------------------
    // Public accessors for the host / tests.
    // ------------------------------------------------------------------------
    public func getRoot() -> Group { return root }
    public func getStorage() -> Storage { return storage }
    public func getModel() -> GlobalModel? { return _model }
    public func getWidth() -> Double { return _width }
    public func getHeight() -> Double { return _height }

    // For `api.getViewOf*` forwarding.
    fileprivate func viewOfComponentModel(_ model: ComponentModel) -> ComponentView? {
        return _componentViewByModel[ObjectIdentifier(model)]
    }
    fileprivate func viewOfSeriesModel(_ model: SeriesModel) -> ChartView? {
        return _chartViewByModel[ObjectIdentifier(model)]
    }
    fileprivate func coordinateSystems() -> [CoordinateSystemMaster] {
        return _coordSysMgr.getCoordinateSystems()
    }
}

// ============================================================================
// Concrete ExtensionAPI backed by the slim driver (upstream: the `availableMethods` forwarding to
// the `ECharts` instance). Only the members the bar path reads are implemented; the rest inherit
// the abstract `fatalError` (never reached in the bar slice).
// ============================================================================
final class SlimExtensionAPI: ExtensionAPI {
    private unowned let ec: EChartsSlim
    init(ec: EChartsSlim) {
        self.ec = ec
        super.init(ecInstance: ec)
    }
    override func getWidth() -> Double { ec.getWidth() }
    override func getHeight() -> Double { ec.getHeight() }
    override func getModel() -> GlobalModel { ec.getModel()! }
    override func getCoordinateSystems() -> [CoordinateSystemMaster] { ec.coordinateSystems() }
    override func getViewOfComponentModel(_ componentModel: ComponentModel) -> ComponentView {
        return ec.viewOfComponentModel(componentModel)!
    }
    override func getViewOfSeriesModel(_ seriesModel: SeriesModel) -> ChartView {
        return ec.viewOfSeriesModel(seriesModel)!
    }
}
