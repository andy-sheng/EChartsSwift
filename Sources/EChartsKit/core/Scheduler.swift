// Ported from echarts/src/core/Scheduler.ts — keep in sync with upstream
/*
* Licensed to the Apache Software Foundation (ASF) under one
* or more contributor license agreements.  See the NOTICE file
* distributed with this work for additional information
* regarding copyright ownership.  The ASF licenses this file
* to you under the Apache License, Version 2.0 (the
* "License"); you may not use this file except in compliance
* with the License.  You may obtain a copy of the License at
*
*   http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing,
* software distributed under the License is distributed on an
* "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
* KIND, either express or implied.  See the License for the
* specific language governing permissions and limitations
* under the License.
*/

import Foundation
import ZRenderKit

// upstream imports:
//   import {each, map, isFunction, createHashMap, noop, HashMap, assert} from 'zrender/src/core/util';
//       -> `util.each` / `util.map` / `util.isFunction` / `util.assert` / `util.noop` (ZRenderKit).
//          `HashMap` / `createHashMap` -> the shim in util/model.swift (same module).
//   import { createTask, Task, TaskContext, TaskProgressCallback, TaskProgressParams,
//            TaskPlanCallbackReturn, PerformArgs } from './task';   -> sibling core/task.swift.
//   import {getUID} from '../util/component';                       -> `component.getUID` (util/component.swift).
//   import GlobalModel from '../model/Global';                      -> GlobalModel (model/Global.swift).
//   import ExtensionAPI from './ExtensionAPI';                      -> ExtensionAPI (core/ExtensionAPI.swift).
//   import {normalizeToArray, preparePipelineContext} from '../util/model';
//       -> `model.normalizeToArray` / `model.preparePipelineContext` (util/model.swift).
//   import { StageHandlerInternal, StageHandlerOverallReset, StageHandler, Payload, StageHandlerReset,
//            StageHandlerPlan, StageHandlerProgressExecutor, SeriesLargeOptionMixin, SeriesOption }
//       from '../util/types';                                       -> util/types.swift.
//   import { EChartsType } from './echarts';                        -> EChartsType (stub in core/ExtensionAPI.swift; Phase 6b).
//   import SeriesModel from '../model/Series';                      -> SeriesModel (model/Series.swift).
//   import ChartView from '../view/Chart';                          -> ChartView (stub in util/types.swift; Phase 6b).
//   import SeriesData from '../data/SeriesData';                    -> SeriesData (data/SeriesData.swift).
//   import { ZRenderType } from 'zrender/src/zrender';              -> ZRenderType (ZRenderKit).

// upstream:
//   export type GeneralTask = Task<TaskContext>;
//   export type SeriesTask = Task<SeriesTaskContext>;
//   export type OverallTask = Task<OverallTaskContext> & { agentStubMap?: HashMap<StubTask> };
//   export type StubTask = Task<StubTaskContext> & { agent?: OverallTask };
//
// `GeneralTask` (= `Task<TaskContext>`) is not expressible in Swift (invariant generics; a protocol
//   does not conform to itself), so it is the erased `any AnyTask` (see core/task.swift). The
//   intersection props `agentStubMap` / `agent` are stored on the base `Task` (see core/task.swift).
public typealias GeneralTask = any AnyTask
public typealias SeriesTask = Task<SeriesTaskContext>
public typealias OverallTask = Task<OverallTaskContext>   // + agentStubMap (on base Task)
public typealias StubTask = Task<StubTaskContext>         // + agent (on base Task)

// upstream: export type Pipeline = { ... }
//   A mutable record stored in `_pipelineMap` and mutated across the scheduler by reference
//   (`pipeline.head = ...`, `pipeline.tail = ...`, `pipeline.count++`, `pipeline.context = ...`),
//   so it is a `final class` (reference semantics, CONVENTIONS §4).
public final class Pipeline {
    var id: String
    var head: (any AnyTask)?
    var tail: (any AnyTask)?
    var threshold: Double
    // It is only a setting - progressive rendering may not be performed even if
    // it is `true`. See also `PipelineContext['progressiveRender']`.
    // FIXME: remove it? Only use `PipelineContext['progressiveRender']`.
    var progressiveEnabled: Bool
    var blockIndex: Double
    var step: Double
    var count: Double
    var currentTask: (any AnyTask)?
    var context: PipelineContext?

    init(
        id: String,
        head: (any AnyTask)?,
        tail: (any AnyTask)?,
        threshold: Double,
        progressiveEnabled: Bool,
        blockIndex: Double,
        step: Double,
        count: Double,
        currentTask: (any AnyTask)? = nil,
        context: PipelineContext? = nil
    ) {
        self.id = id
        self.head = head
        self.tail = tail
        self.threshold = threshold
        self.progressiveEnabled = progressiveEnabled
        self.blockIndex = blockIndex
        self.step = step
        self.count = count
        self.currentTask = currentTask
        self.context = context
    }
}

// upstream: export type PipelineContext = { progressiveRender, modDataCount, large }
//   `PipelineContext` is hosted in util/model.swift (it is the return type of
//   `model.preparePipelineContext`, ported before this file); referenced here to avoid a
//   redeclaration. PORT-NOTE: relocate `PipelineContext` here once util/model.swift no longer needs
//   the forward reference.

// upstream: type TaskRecord = { seriesTaskMap?: HashMap<SeriesTask>, overallTask?: OverallTask }
//   Mutated in place inside `_pipelineMap`/`_stageTaskMap` values, so it is a `final class`.
final class TaskRecord {
    // key: seriesUID
    var seriesTaskMap: HashMap<SeriesTask>?
    var overallTask: OverallTask?
    init() {}
}

// upstream: type PerformStageTaskOpt = { block?, setDirty?, visualType?, dirtyMap? }
public struct PerformStageTaskOpt {
    // `block` means running from the beginning to the final end within
    // an individual "progress".
    var block: Bool?
    var setDirty: Bool?
    var visualType: String?   // upstream: StageHandlerInternal['visualType']
    var dirtyMap: HashMap<Any>?
    init(block: Bool? = nil, setDirty: Bool? = nil, visualType: String? = nil, dirtyMap: HashMap<Any>? = nil) {
        self.block = block
        self.setDirty = setDirty
        self.visualType = visualType
        self.dirtyMap = dirtyMap
    }
}

// upstream: export interface SeriesTaskContext extends TaskContext { ... }
public final class SeriesTaskContext: TaskContext {
    public var outputData: SeriesData?
    public var data: SeriesData?
    public var payload: Payload?
    public var model: SeriesModel?
    public var view: ChartView?
    public var ecModel: GlobalModel?
    public var api: ExtensionAPI?
    public var useClearVisual: Bool?
    public var plan: StageHandlerPlan?
    public var reset: StageHandlerReset?
    public var scheduler: Scheduler?
    public var resetDefines: [StageHandlerProgressExecutor]?
    public init() {}
}

// upstream: interface OverallTaskContext extends TaskContext { ... }
public final class OverallTaskContext: TaskContext {
    public var outputData: SeriesData?
    public var data: SeriesData?
    public var payload: Payload?
    public var model: SeriesModel?
    public var ecModel: GlobalModel!
    public var api: ExtensionAPI!
    public var overallReset: StageHandlerOverallReset!
    public var scheduler: Scheduler!
    public init() {}
}

// upstream: interface StubTaskContext extends TaskContext { ... }
public final class StubTaskContext: TaskContext {
    public var outputData: SeriesData?
    public var data: SeriesData?
    public var payload: Payload?
    public var model: SeriesModel?                     // upstream: model: SeriesModel (non-optional)
    public var dirtyOnOverallProgress: Bool?           // upstream: StageHandler['dirtyOnOverallProgress']
    public init() {}
}

public final class Scheduler {

    public let ecInstance: EChartsType
    public let api: ExtensionAPI

    // Shared with echarts.js, should only be modified by
    // this file and echarts.js
    public var unfinished: Bool = false

    private var _dataProcessorHandlers: [StageHandlerInternal]
    private var _visualHandlers: [StageHandlerInternal]
    private var _allHandlers: [StageHandlerInternal]

    // key: handlerUID
    private var _stageTaskMap: HashMap<TaskRecord> = createHashMap()
    // key: pipelineId
    private var _pipelineMap: HashMap<Pipeline>!


    public init(
        _ ecInstance: EChartsType,
        _ api: ExtensionAPI,
        _ dataProcessorHandlers: [StageHandlerInternal],
        _ visualHandlers: [StageHandlerInternal]
    ) {
        self.ecInstance = ecInstance
        self.api = api

        // Fix current processors in case that in some rear cases that
        // processors might be registered after echarts instance created.
        // Register processors incrementally for a echarts instance is
        // not supported by this stream architecture.
        // (Swift arrays are value types, so assignment is `.slice()`.)
        self._dataProcessorHandlers = dataProcessorHandlers
        self._visualHandlers = visualHandlers
        self._allHandlers = self._dataProcessorHandlers + self._visualHandlers
    }

    /// Test-only: number of per-series pipelines built by `restorePipelines` (one per series).
    var testPipelineCount: Int { return _pipelineMap?.keys().count ?? 0 }

    public func restoreData(_ ecModel: GlobalModel, _ payload: Payload) {
        // TODO: Only restore needed series and components, but not all components.
        // Currently `restoreData` of all of the series and component will be called.
        // But some independent components like `title`, `legend`, `graphic`, `toolbox`,
        // `tooltip`, `axisPointer`, etc, do not need series refresh when `setOption`,
        // and some components like coordinate system, axes, dataZoom, visualMap only
        // need their target series refresh.
        // (1) If we are implementing this feature some day, we should consider these cases:
        // if a data processor depends on a component (e.g., dataZoomProcessor depends
        // on the settings of `dataZoom`), it should be re-performed if the component
        // is modified by `setOption`.
        // (2) If a processor depends on several series, specified by its `getTargetSeries`,
        // it should be re-performed when the result array of `getTargetSeries` changed.
        // We use `dependencies` to cover these issues.
        // (3) How to update target series when coordinate system related components modified.

        // TODO: simply the dirty mechanism? Check whether only the case here can set tasks dirty,
        // and this case all of the tasks will be set as dirty.

        ecModel.restoreData(payload)

        // Theoretically an overall task not only depends on each of its target series, but also
        // depends on all of the series.
        // The overall task is not in pipeline, and `ecModel.restoreData` only set pipeline tasks
        // dirty. If `getTargetSeries` of an overall task returns nothing, we should also ensure
        // that the overall task is set as dirty and to be performed, otherwise it probably cause
        // state chaos. So we have to set dirty of all of the overall tasks manually, otherwise it
        // probably cause state chaos (consider `dataZoomProcessor`).
        self._stageTaskMap.each { taskRecord, _ in
            let overallTask = taskRecord.overallTask
            overallTask?.dirty()
        }
    }

    // If seriesModel provided, incremental threshold is check by series data.
    public func getPerformArgs(_ task: any AnyTask, _ isBlock: Bool? = nil) -> PerformArgs? {
        // For overall task
        if task.__pipeline == nil {
            return nil
        }

        let pipeline = self._pipelineMap.get(task.__pipeline!.id)!
        let pCtx = pipeline.context
        let incremental = !(isBlock ?? false)
            && pipeline.progressiveEnabled
            && (pCtx == nil || pCtx!.progressiveRender)
            && task.__idxInPipeline! > pipeline.blockIndex

        let step: Double? = incremental ? pipeline.step : nil
        let modDataCount = pCtx?.modDataCount
        // upstream: modDataCount != null ? Math.ceil(modDataCount / step) : null
        //   (JS coerces a `null` step to 0 -> Infinity; replicated with `step ?? 0`).
        let modBy: Double? = modDataCount != nil ? ceil(modDataCount! / (step ?? 0)) : nil

        return PerformArgs(step: step, modBy: modBy, modDataCount: modDataCount)
    }

    public func getPipeline(_ pipelineId: String) -> Pipeline? {
        return self._pipelineMap.get(pipelineId)
    }

    /**
     * Current, progressive rendering starts from visual and layout.
     * Always detect render mode in the same stage, avoiding that incorrect
     * detection caused by data filtering.
     * Caution:
     * `updateStreamModes` use `seriesModel.getData()`.
     */
    // upstream: updateStreamModes(seriesModel: SeriesModel<SeriesOption & SeriesLargeOptionMixin>, view)
    //   The generic `Opt` is dropped (CONVENTIONS §2).
    public func updateStreamModes(_ seriesModel: SeriesModel, _ view: ChartView) {
        // PORT-NOTE: upstream never reaches updateStreamModes without a pipeline — `_pipe` creates one
        //   for every series during `prepareStageTasks`, run on EVERY update. This port instead drives
        //   updateStreamModes from a separate pass keyed on chartView existence (ECharts.update), and
        //   `restorePipelines` is NOT re-run after a toolbox magic-type swap (line↔bar) mints a new
        //   series uid — so `_pipelineMap.get(uid)` is nil for the swapped series and the old force-unwrap
        //   crashed (testMagicTypeSwapsLineToBar). A series with no restored pipeline has no
        //   progressive/large context to compute, so the faithful behavior is to leave it in normal mode.
        //   The deeper fix (re-run restorePipelines after a series-list mutation, matching upstream's
        //   `_prepare`) is a Scheduler-lifecycle change tracked separately.
        guard let pipeline = self._pipelineMap.get(seriesModel.uid) else { return }

        // `progressiveRender` means that can render progressively in each
        // animation frame. Note that some types of series do not provide
        // `view.incrementalPrepareRender` but support `chart.appendData`. We
        // use the term `incremental` but not `progressive` to describe the
        // case `chart.appendData`.
        // Regarding zrender, both echarts "progressive" and "incremental" use `el.incremental: true`.
        // upstream: const context = seriesModel.__preparePipelineContext
        //     ? seriesModel.__preparePipelineContext(view, pipeline)
        //     : preparePipelineContext(seriesModel, view, pipeline);
        // POTENTIAL-BUG: `__preparePipelineContext` is now overridden by concrete series (e.g.
        //   BarSeries, which sets `large = true` under progressiveRender), but the base `SeriesModel`
        //   declares no such slot, so this always calls the free `model.preparePipelineContext` and
        //   the override is bypassed. Dormant while progressive is disabled (native painter →
        //   progressiveRender false); to fix, declare the optional method on base SeriesModel (out of
        //   this file's scope) and dispatch to it when present.
        let context = model.preparePipelineContext(
            seriesModel, view,
            PipelinePick(progressiveEnabled: pipeline.progressiveEnabled, threshold: pipeline.threshold)
        )

        pipeline.context = context
        seriesModel.pipelineContext = context
    }

    // `zr` is optional in this port: the host-independent `ECharts` driver owns no ZRender instance
    //   (the live `zr` lives on the host, e.g. EChartsView). Its only use here is `zr.painter.type ==
    //   "canvas"` to gate progressive rendering; the native painter reports `"native"`, so progressive
    //   is disabled either way in C1. C2 (when the live host drives the pipeline) can pass a real zr.
    public func restorePipelines(_ zr: ZRenderType?, _ ecModel: GlobalModel) {
        let scheduler = self
        let pipelineMap: HashMap<Pipeline> = createHashMap()
        scheduler._pipelineMap = pipelineMap

        ecModel.eachSeries { seriesModel, _ in
            // upstream: const progressive = zr.painter.type === 'canvas' && seriesModel.getProgressive();
            let progressive: Any? = (zr?.painter.type == "canvas") ? seriesModel.getProgressive() : false
            let pipelineId = seriesModel.uid

            pipelineMap.set(pipelineId, Pipeline(
                id: pipelineId,
                head: nil,
                tail: nil,
                threshold: seriesModel.getProgressiveThreshold(),
                // upstream: progressive && !(seriesModel.preventIncremental && seriesModel.preventIncremental())
                // POTENTIAL-BUG: `preventIncremental` is now overridden by concrete series (e.g.
                //   LinesSeries returns true when effect.show), but the base SeriesModel declares no
                //   such slot, so it is not consulted here (treated as absent/false). Dormant while
                //   progressive is disabled (native painter → `progressive` false → progressiveEnabled
                //   false regardless); to fix, declare the optional method on base SeriesModel (out of
                //   this file's scope) and gate on it.
                progressiveEnabled: jsTruthy(progressive) && true,
                blockIndex: -1,
                // upstream: Math.round(progressive || 700)
                step: floor((jsTruthy(progressive) ? ((progressive as? Double) ?? 700) : 700) + 0.5),
                count: 0
            ))

            scheduler._pipe(seriesModel, seriesModel.dataTask)
        }
    }

    public func prepareStageTasks() {
        let stageTaskMap = self._stageTaskMap
        let ecModel = self.api.getModel()
        let api = self.api

        util.each(self._allHandlers) { handler, _ in
            let record = stageTaskMap.get(handler.uid) ?? stageTaskMap.set(handler.uid, TaskRecord())

            var errMsg = ""
            if __DEV__ {
                // Currently do not need to support to specify them both.
                errMsg = "\"reset\" and \"overallReset\" must not be both specified."
            }
            util.assert(!(handler.handler.reset != nil && handler.handler.overallReset != nil), errMsg)

            if handler.handler.reset != nil { self._createSeriesStageTask(handler, record, ecModel, api) }
            if handler.handler.overallReset != nil { self._createOverallStageTask(handler, record, ecModel, api) }
        }
    }

    public func prepareView(_ view: ChartView, _ model: SeriesModel, _ ecModel: GlobalModel, _ api: ExtensionAPI) {
        // upstream:
        //   const renderTask = view.renderTask;
        //   const context = renderTask.context;
        //   context.model = model;
        //   context.ecModel = ecModel;
        //   context.api = api;
        //   renderTask.__block = !view.incrementalPrepareRender;
        //   this._pipe(model, renderTask);
        // PORT-NOTE (deferred): ChartView now has `renderTask` and `incrementalPrepareRender`
        //   (view/Chart.swift), so the faithful body above is portable, but nothing performs the piped
        //   render task yet — the render/progressive pipeline consumer (sub-project C2) is not wired.
        //   Piping the render task here would have no effect and could perturb pipeline iteration, so
        //   this stays a no-op until C2 lands. (Also `!view.incrementalPrepareRender` is not
        //   feature-detectable in Swift; see the ChartView PORT-NOTE.)
        _ = (view, model, ecModel, api)
    }

    public func performDataProcessorTasks(_ ecModel: GlobalModel, _ payload: Payload? = nil) {
        // If we do not use `block` here, it should be considered when to update modes.
        self._performStageTasks(self._dataProcessorHandlers, ecModel, payload, PerformStageTaskOpt(block: true))
    }

    public func performVisualTasks(
        _ ecModel: GlobalModel,
        _ payload: Payload? = nil,
        _ opt: PerformStageTaskOpt? = nil
    ) {
        self._performStageTasks(self._visualHandlers, ecModel, payload, opt)
    }

    private func _performStageTasks(
        _ stageHandlers: [StageHandlerInternal],
        _ ecModel: GlobalModel,
        _ payload: Payload?,
        _ opt: PerformStageTaskOpt? = nil
    ) {
        let opt = opt ?? PerformStageTaskOpt()
        var unfinished: Bool = false
        let scheduler = self

        util.each(stageHandlers) { stageHandler, idx in
            if let visualType = opt.visualType, visualType != stageHandler.visualType {
                return
            }

            let stageHandlerRecord = scheduler._stageTaskMap.get(stageHandler.uid)!
            let seriesTaskMap = stageHandlerRecord.seriesTaskMap
            let overallTask = stageHandlerRecord.overallTask

            if let overallTask = overallTask {
                var overallNeedDirty = false
                let agentStubMap = overallTask.agentStubMap!
                agentStubMap.each { stub, _ in
                    if needSetDirty(opt, stub) {
                        stub.dirty()
                        overallNeedDirty = true
                    }
                }
                if overallNeedDirty { overallTask.dirty() }
                scheduler.updatePayload(overallTask, payload)
                let performArgs = scheduler.getPerformArgs(overallTask, opt.block)
                // Execute stubs firstly, which may set the overall task dirty,
                // then execute the overall task. And stub will call seriesModel.setData,
                // which ensures that in the overallTask seriesModel.getData() will not
                // return incorrect data.
                agentStubMap.each { stub, _ in
                    stub.perform(performArgs)
                }
                if overallTask.perform(performArgs) {
                    unfinished = true
                }
            }
            else if let seriesTaskMap = seriesTaskMap {
                seriesTaskMap.each { task, pipelineId in
                    if needSetDirty(opt, task) {
                        task.dirty()
                    }
                    var performArgs: PerformArgs = scheduler.getPerformArgs(task, opt.block)!
                    // FIXME
                    // if intending to declare `performRawSeries` in handlers, only
                    // stream-independent (specifically, data item independent) operations can be
                    // performed. Because if a series is filtered, most of the tasks will not
                    // be performed. A stream-dependent operation probably cause wrong biz logic.
                    // Perhaps we should not provide a separate callback for this case instead
                    // of providing the config `performRawSeries`. The stream-dependent operations
                    // and stream-independent operations should better not be mixed.
                    performArgs.skip = !(stageHandler.handler.performRawSeries ?? false)
                        && ecModel.isSeriesFiltered(task.context.model!)
                    scheduler.updatePayload(task, payload)

                    if task.perform(performArgs) {
                        unfinished = true
                    }
                }
            }
        }

        func needSetDirty(_ opt: PerformStageTaskOpt, _ task: any AnyTask) -> Bool {
            return (opt.setDirty ?? false) && (opt.dirtyMap == nil || jsTruthy(opt.dirtyMap!.get(task.__pipeline!.id)))
        }
        self.unfinished = unfinished || self.unfinished
    }

    public func performSeriesTasks(_ ecModel: GlobalModel) {
        var unfinished: Bool = false

        ecModel.eachSeries { seriesModel, _ in
            // Progress to the end for dataInit and dataRestore.
            unfinished = seriesModel.dataTask.perform() || unfinished
        }
        self.unfinished = unfinished || self.unfinished
    }

    public func plan() {
        // Travel pipelines, check block.
        self._pipelineMap.each { pipeline, _ in
            // upstream: do { ... } while (task); (`pipeline.tail` is always set after `_pipe`).
            var task = pipeline.tail
            while let t = task {
                if (t.__block ?? false) {
                    pipeline.blockIndex = t.__idxInPipeline!
                    break
                }
                task = t.getUpstream()
            }
        }
    }

    // upstream: updatePayload(task: Task<SeriesTaskContext | OverallTaskContext>, payload: Payload | 'remain')
    public func updatePayload<Ctx: TaskContext>(
        _ task: Task<Ctx>,
        _ payload: Payload?
    ) {
        // upstream: payload !== 'remain' && (task.context.payload = payload)
        // PORT-NOTE: the `'remain'` sentinel (a string union member) lets core/echarts.ts keep the
        //   previous payload. In this port `payload` is a strongly-typed `Payload?`, so the sentinel is
        //   not representable; the "keep previous" case is not exercised and the branch is dropped.
        task.context.payload = payload
    }

    private func _createSeriesStageTask(
        _ stageHandler: StageHandlerInternal,
        _ stageHandlerRecord: TaskRecord,
        _ ecModel: GlobalModel,
        _ api: ExtensionAPI
    ) {
        let scheduler = self
        let oldSeriesTaskMap = stageHandlerRecord.seriesTaskMap
        // The count of stages are totally about only several dozen, so
        // do not need to reuse the map.
        let newSeriesTaskMap: HashMap<SeriesTask> = createHashMap()
        stageHandlerRecord.seriesTaskMap = newSeriesTaskMap
        let seriesType = stageHandler.handler.seriesType
        let getTargetSeries = stageHandler.handler.getTargetSeries

        // If a stageHandler should cover all series, `createOnAllSeries` should be declared mandatorily,
        // to avoid some typo or abuse. Otherwise if an extension do not specify a `seriesType`,
        // it works but it may cause other irrelevant charts blocked.
        func create(_ seriesModel: SeriesModel) {
            let pipelineId = seriesModel.uid

            // Init tasks for each seriesModel only once.
            // Reuse original task instance.
            let task = oldSeriesTaskMap?.get(pipelineId)
                ?? createTask(TaskDefineParam<SeriesTaskContext>(
                    reset: seriesTaskReset,
                    plan: seriesTaskPlan,
                    count: seriesTaskCount
                ))
            newSeriesTaskMap.set(pipelineId, task)
            let context = SeriesTaskContext()
            context.model = seriesModel
            context.ecModel = ecModel
            context.api = api
            // PENDING: `useClearVisual` not used?
            context.useClearVisual = (stageHandler.isVisual ?? false) && !(stageHandler.isLayout ?? false)
            context.plan = stageHandler.handler.plan
            context.reset = stageHandler.handler.reset
            context.scheduler = scheduler
            task.context = context
            scheduler._pipe(seriesModel, task)
        }

        if (stageHandler.handler.createOnAllSeries ?? false) {
            ecModel.eachRawSeries { seriesModel, _ in create(seriesModel) }
        }
        else if let seriesType = seriesType {
            ecModel.eachRawSeriesByType(seriesType) { seriesModel, _ in create(seriesModel) }
        }
        else if let getTargetSeries = getTargetSeries {
            // POTENTIAL-BUG: upstream `getTargetSeries(...).each(create)` iterates a `HashMap<SeriesModel>`
            //   in insertion order; the ported return type is `[String: SeriesModel]`, and Swift
            //   Dictionary iteration order is unspecified (varies across runs), so the series-task
            //   creation order here is non-deterministic. Change `getTargetSeries` to return an ordered
            //   collection (e.g. HashMap/[SeriesModel]) to make pipeline order deterministic.
            for (_, seriesModel) in getTargetSeries(ecModel, api) { create(seriesModel) }
        }
    }

    private func _createOverallStageTask(
        _ stageHandler: StageHandlerInternal,
        _ stageHandlerRecord: TaskRecord,
        _ ecModel: GlobalModel,
        _ api: ExtensionAPI
    ) {
        let scheduler = self
        // For overall task, the function only be called on reset stage.
        let overallTask: OverallTask = stageHandlerRecord.overallTask
            ?? createTask(TaskDefineParam<OverallTaskContext>(reset: overallTaskReset))
        stageHandlerRecord.overallTask = overallTask

        let context = OverallTaskContext()
        context.ecModel = ecModel
        context.api = api
        context.overallReset = stageHandler.handler.overallReset
        context.scheduler = scheduler
        overallTask.context = context

        let oldAgentStubMap = overallTask.agentStubMap
        // The count of stages are totally about only several dozen, so
        // do not need to reuse the map.
        let newAgentStubMap: HashMap<StubTask> = createHashMap()
        overallTask.agentStubMap = newAgentStubMap

        let seriesType = stageHandler.handler.seriesType
        let getTargetSeries = stageHandler.handler.getTargetSeries
        let dirtyOnOverallProgress = stageHandler.handler.dirtyOnOverallProgress
        var shouldOverallTaskDirty = false
        // FIXME:TS never used, so comment it
        // let modifyOutputEnd = stageHandler.modifyOutputEnd;

        // An overall task with seriesType detected or has `getTargetSeries`, we add
        // stub in each pipelines to receive dirty info from upstream.
        var errMsg = ""
        if __DEV__ {
            errMsg = "\"createOnAllSeries\" is not supported for \"overallReset\", "
                + "because it will block all streams."
        }
        util.assert(!(stageHandler.handler.createOnAllSeries ?? false), errMsg)

        func createStub(_ seriesModel: SeriesModel) {
            let pipelineId = seriesModel.uid
            var stub = oldAgentStubMap?.get(pipelineId)
            if stub == nil {
                // When the result of `getTargetSeries` changed, the overallTask
                // should be set as dirty and re-performed.
                shouldOverallTaskDirty = true
                stub = createTask(TaskDefineParam<StubTaskContext>(reset: stubReset, onDirty: stubOnDirty))
            }
            newAgentStubMap.set(pipelineId, stub!)
            let context = StubTaskContext()
            context.model = seriesModel
            context.dirtyOnOverallProgress = dirtyOnOverallProgress
            // FIXME:TS never used, so comment it
            // modifyOutputEnd: modifyOutputEnd
            stub!.context = context
            stub!.agent = overallTask
            stub!.__block = dirtyOnOverallProgress

            scheduler._pipe(seriesModel, stub!)
        }

        if let seriesType = seriesType {
            ecModel.eachRawSeriesByType(seriesType) { seriesModel, _ in createStub(seriesModel) }
        }
        else if let getTargetSeries = getTargetSeries {
            // POTENTIAL-BUG: see note in `_createSeriesStageTask` — Swift `[String: SeriesModel]`
            //   iteration order is unspecified vs upstream's insertion-ordered HashMap, making the
            //   stub-creation (and thus pipeline) order non-deterministic.
            for (_, seriesModel) in getTargetSeries(ecModel, api) { createStub(seriesModel) }
        }
        else {
            util.each(ecModel.getSeries()) { seriesModel, _ in createStub(seriesModel) }
        }

        if shouldOverallTaskDirty {
            overallTask.dirty()
        }
    }

    private func _pipe(_ seriesModel: SeriesModel, _ task: any AnyTask) {
        let pipelineId = seriesModel.uid
        let pipeline = self._pipelineMap.get(pipelineId)!
        if pipeline.head == nil { pipeline.head = task }
        pipeline.tail?.pipe(task)
        pipeline.tail = task
        task.__idxInPipeline = pipeline.count
        pipeline.count += 1
        task.__pipeline = pipeline
    }

    public static func wrapStageHandler(
        _ stageHandler: Any,   // upstream: StageHandler | StageHandlerOverallReset
        _ visualType: String?  // upstream: StageHandlerInternal['visualType']
    ) -> StageHandlerInternal {
        var handler: StageHandler
        if util.isFunction(stageHandler) {
            // upstream: stageHandler = { overallReset: stageHandler, seriesType: detectSeriseType(stageHandler) }
            let overallReset = stageHandler as! StageHandlerOverallReset
            var h = StageHandler()
            h.overallReset = overallReset
            h.seriesType = detectSeriseType(overallReset)
            handler = h
        }
        else {
            handler = stageHandler as! StageHandler
        }

        // upstream: (stageHandler as StageHandlerInternal).uid = getUID('stageHandler');
        //           visualType && ((stageHandler as StageHandlerInternal).visualType = visualType);
        // PORT-NOTE: `__prio` is assigned by the registry (echarts.ts registerVisual/registerLayout);
        //   defaulted to 0 here. Harmless: the ported `_performStageTasks` iterates registration/array
        //   order, not `__prio`, so the value is currently unused by execution ordering.
        var internalHandler = StageHandlerInternal(
            uid: component.getUID("stageHandler"),
            visualType: nil,
            __prio: 0,
            __raw: stageHandler,
            isVisual: nil,
            isLayout: nil,
            handler: handler
        )
        if let visualType = visualType { internalHandler.visualType = visualType }

        return internalHandler
    }

}


func overallTaskReset(_ this: OverallTask, _ context: OverallTaskContext) -> TaskResetCallbackReturn<OverallTaskContext>? {
    context.overallReset(
        context.ecModel, context.api, context.payload
    )
    return nil
}

func stubReset(_ this: StubTask, _ context: StubTaskContext) -> TaskResetCallbackReturn<StubTaskContext>? {
    return (context.dirtyOnOverallProgress ?? false) ? .progress(.single(stubProgress)) : nil
}

// upstream: function stubProgress(this: StubTask): void
func stubProgress(_ this: StubTask, _ params: TaskProgressParams, _ context: StubTaskContext) {
    this.agent?.dirty()
    this.getDownstream()?.dirty()
}

// upstream: function stubOnDirty(this: StubTask): void
func stubOnDirty(_ this: StubTask, _ context: StubTaskContext) {
    this.agent?.dirty()
}

func seriesTaskPlan(_ this: SeriesTask, _ context: SeriesTaskContext) -> TaskPlanCallbackReturn? {
    return context.plan != nil ? context.plan!(
        context.model!, context.ecModel!, context.api!, context.payload
    ) : nil
}

func seriesTaskReset(
    _ this: SeriesTask,
    _ context: SeriesTaskContext
) -> TaskResetCallbackReturn<SeriesTaskContext>? {
    if (context.useClearVisual ?? false) {
        context.data!.clearAllVisual()
    }
    let resetDefines: [StageHandlerProgressExecutor] = model.normalizeToArray(
        context.reset!(context.model!, context.ecModel!, context.api!, context.payload)
    )
    context.resetDefines = resetDefines
    return resetDefines.count > 1
        ? .progress(.array(util.map(resetDefines) { _, idx in
            return makeSeriesTaskProgress(Double(idx))
        }))
        : .progress(.single(singleSeriesTaskProgress))
}

let singleSeriesTaskProgress = makeSeriesTaskProgress(0)

func makeSeriesTaskProgress(_ resetDefineIdx: Double) -> TaskProgressCallback<SeriesTaskContext> {
    return { (this: SeriesTask, params: TaskProgressParams, context: SeriesTaskContext) in
        // upstream guards `if (resetDefine && resetDefine.dataEach)` — `resetDefines[idx]` is `undefined`
        //   when the handler's `reset` returned nothing (e.g. dataSample with no `sampling`:
        //   normalizeToArray(undefined) == [] so singleSeriesTaskProgress reads resetDefines[0] ==
        //   undefined). JS no-ops via the `resetDefine &&` truthy check; the Swift port must guard the
        //   index + optionals instead of force-unwrapping (dropping the guard trapped on every plain
        //   bar/line series once the Scheduler drives the pipeline live). Faithful to upstream.
        let idx = Int(resetDefineIdx)
        guard let resetDefines = context.resetDefines, idx < resetDefines.count else { return }
        let resetDefine = resetDefines[idx]
        let data = context.data

        if let dataEach = resetDefine.dataEach, let data = data {
            var i = params.start
            while i < params.end {
                dataEach(data, i)
                i += 1
            }
        }
        else if let progress = resetDefine.progress, let data = data {
            progress(params, data)
        }
    }
}

func seriesTaskCount(_ this: SeriesTask, _ context: SeriesTaskContext) -> Double {
    return Double(context.data!.count())
}



/**
 * Only some legacy stage handlers (usually in echarts extensions) are pure function.
 * To ensure that they can work normally, they should work in block mode, that is,
 * they should not be started util the previous tasks finished. So they cause the
 * progressive rendering disabled. We try to detect the series type, to narrow down
 * the block range to only the series type they concern, but not all series.
 */
// PORT-NOTE (unportable): upstream detects the series type by running `legacyFunc` against mock
//   `GlobalModel`/`ExtensionAPI` instances whose every prototype method is replaced by `noop`
//   (`for (let name in Clz.prototype) target[name] = noop;`) and capturing the `eachSeriesByType`/
//   `eachRawSeriesByType`/`eachComponent` argument. Swift cannot iterate a type's method table nor
//   construct empty mock instances of these non-optional-initializer classes, so detection is
//   skipped (returns nil). The block-range narrowing is a perf optimization only; correctness is
//   unaffected. Restore with a Swift-appropriate mechanism when legacy pure-function handlers land.
func detectSeriseType(_ legacyFunc: StageHandlerOverallReset) -> String? {
    return nil
}

// upstream module-level mock scaffolding (see the PORT-NOTE above):
//   const ecModelMock: GlobalModel = {} as GlobalModel;
//   const apiMock: ExtensionAPI = {} as ExtensionAPI;
//   let seriesType;
//   mockMethods(ecModelMock, GlobalModel);
//   mockMethods(apiMock, ExtensionAPI);
//   ecModelMock.eachSeriesByType = ecModelMock.eachRawSeriesByType = function (type) { seriesType = type; };
//   ecModelMock.eachComponent = function (cond) {
//       if (cond.mainType === 'series' && cond.subType) { seriesType = cond.subType; }
//   };
//   function mockMethods(target, Clz) { for (let name in Clz.prototype) { target[name] = noop; } }

// export default Scheduler;  -> `public final class Scheduler` above.

// JS truthiness shim for dynamic option values (nil/false/0/NaN/"" are falsy). Not an upstream
// symbol — replaces inline `if (x)` / `x || y` / `x && y` truthiness on `Any?` (e.g. `progressive`).
private func jsTruthy(_ v: Any?) -> Bool {
    guard let v = v else { return false }
    if v is NSNull { return false }
    if let b = v as? Bool { return b }
    if let n = v as? Double { return n != 0 && !n.isNaN }
    if let i = v as? Int { return i != 0 }
    if let s = v as? String { return !s.isEmpty }
    return true
}
