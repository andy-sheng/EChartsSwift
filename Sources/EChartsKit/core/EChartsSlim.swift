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

        // View factories (upstream: registerComponentView / registerChartView; see header deviation).
        // (component views keyed by mainType; chart views keyed by subType.)
        // These are file-scope closures, assigned lazily on first `install`.
    }

    // Upstream stores the view CLASS; we store factories (see header). Keyed as upstream `getClass`
    // resolves: component views by mainType (grid/xAxis/yAxis), chart views by series subType (bar).
    private let _componentViewFactories: [String: () -> ComponentView] = [
        "grid": { GridView() },
        "xAxis": { CartesianXAxisView() },
        "yAxis": { CartesianYAxisView() }
    ]
    private let _chartViewFactories: [String: () -> ChartView] = [
        "bar": { BarView() },
        "line": { LineView() }
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
        // Order mirrors visual/style.ts install: color-palette (overallReset) then per-series style,
        //   then per-data style. Each is a `StageHandler` from visual/style.swift.
        runOverallStageHandler(dataColorPaletteTask, ecModel, api)
        runSeriesStageHandler(seriesStyleTask, ecModel, api)
        runSeriesStageHandler(dataStyleTask, ecModel, api)
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
