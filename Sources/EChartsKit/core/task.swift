// Ported from echarts/src/core/task.ts — keep in sync with upstream
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
//   import {assert, isArray} from 'zrender/src/core/util';  -> ZRenderKit `util` (`util.assert`;
//       `isArray` is not called directly — the `Cb | Cb[]` unions are modeled with enums below).
//   import SeriesModel from '../model/Series';               -> sibling model/Series.swift (`SeriesModel`).
//   import { Pipeline } from './Scheduler';                  -> real `Pipeline` class in core/Scheduler.swift (see note below).
//   import { Payload } from '../util/types';                 -> sibling util/types.swift (`Payload`).
//   import SeriesData from '../data/SeriesData';             -> sibling data/SeriesData.swift (`SeriesData`).

// '../core/Scheduler' — Pipeline is now the real `final class Pipeline` in core/Scheduler.swift
//   (same module); `Task.__pipeline` references it directly.
//
// AnyTask: a non-generic, type-erased view of `Task<Ctx>`. Upstream models `GeneralTask =
//   Task<TaskContext>` and pipes tasks of *different* context types into one pipeline (the union is
//   expressible in TS via structural covariance). Swift generics are invariant and
//   `Task<TaskContext>` is not expressible (a protocol does not conform to itself), so the
//   cross-context pipeline wiring (`_upstream`/`_downstream`/`pipe`/`getUpstream`/`getDownstream`)
//   is erased through this protocol. `core/Scheduler.swift` aliases `GeneralTask = any AnyTask`.
//   PORT-NOTE: `_upstream`/`_downstream`/`_disposed`/`_outputDueEnd` are `private` upstream; they are
//   exposed here (public / public-private(set)) only to satisfy the erased protocol witnesses.
public protocol AnyTask: AnyObject {
    var __pipeline: Pipeline? { get set }
    var __idxInPipeline: Double? { get set }
    var __block: Bool? { get set }
    var _upstream: (any AnyTask)? { get set }
    var _downstream: (any AnyTask)? { get set }
    var _disposed: Bool { get }
    var _outputDueEnd: Double { get }
    var _contextOutputData: SeriesData? { get }
    func dirty()
    @discardableResult func perform(_ performArgs: PerformArgs?) -> Bool
    func pipe(_ downTask: any AnyTask)
    @discardableResult func getUpstream() -> (any AnyTask)?
    @discardableResult func getDownstream() -> (any AnyTask)?
    func setOutputEnd(_ end: Double)
}

// upstream: interface TaskContext { outputData?, data?, payload?, model? }
//   Modeled as a class-bound protocol because `context` is shared and mutated by reference
//   (`context.data = context.outputData = upTask.context.outputData`).
public protocol TaskContext: AnyObject {
    var outputData: SeriesData? { get set }
    var data: SeriesData? { get set }
    var payload: Payload? { get set }
    var model: SeriesModel? { get set }
}

// upstream: (this: Task<Ctx>, context: Ctx) => TaskResetCallbackReturn<Ctx>
//   The `this: Task<Ctx>` binding is passed as an explicit leading parameter (Swift closures have no `this`).
//   `void` in the return union is represented by returning `nil`.
public typealias TaskResetCallback<Ctx: TaskContext> = (Task<Ctx>, Ctx) -> TaskResetCallbackReturn<Ctx>?

// upstream: TaskProgressCallback<Ctx> | TaskProgressCallback<Ctx>[]
//   (the type of `_progress` and of the reset-return `progress`). Named here to model the union.
public enum TaskProgressLike<Ctx: TaskContext> {
    case single(TaskProgressCallback<Ctx>)
    case array([TaskProgressCallback<Ctx>])
}

// upstream:
//   void
//   | (TaskProgressCallback<Ctx> | TaskProgressCallback<Ctx>[])
//   | { forceFirstProgress?: boolean, progress: TaskProgressCallback<Ctx> | TaskProgressCallback<Ctx>[] }
//   ( `void` -> represented as an Optional `nil` at the callback return. )
public enum TaskResetCallbackReturn<Ctx: TaskContext> {
    case progress(TaskProgressLike<Ctx>)
    case object(forceFirstProgress: Bool?, progress: TaskProgressLike<Ctx>)
}

// upstream: (this: Task<Ctx>, params: TaskProgressParams, context: Ctx) => void
//   `this: Task<Ctx>` binding passed as an explicit leading parameter.
public typealias TaskProgressCallback<Ctx: TaskContext> = (Task<Ctx>, TaskProgressParams, Ctx) -> Void

public struct TaskProgressParams {
    public var start: Double
    public var end: Double
    public var count: Double
    public var next: TaskDataIteratorNext?
    public init(start: Double, end: Double, count: Double, next: TaskDataIteratorNext? = nil) {
        self.start = start
        self.end = end
        self.count = count
        self.next = next
    }
}

// upstream: (this: Task<Ctx>, context: Ctx) => TaskPlanCallbackReturn
public typealias TaskPlanCallback<Ctx: TaskContext> = (Task<Ctx>, Ctx) -> TaskPlanCallbackReturn?

// upstream: 'reset' | false | null | undefined
//   `.reset` == 'reset'; the falsy variants (false | null | undefined) all collapse to `nil`.
public enum TaskPlanCallbackReturn {
    case reset
}

// upstream: (this: Task<Ctx>, context: Ctx) => number
public typealias TaskCountCallback<Ctx: TaskContext> = (Task<Ctx>, Ctx) -> Double

// upstream: (this: Task<Ctx>, context: Ctx) => void
public typealias TaskOnDirtyCallback<Ctx: TaskContext> = (Task<Ctx>, Ctx) -> Void

public typealias TaskDataIteratorNext = () -> Double?   // upstream: () => number ( returns null when exhausted )

// upstream: type TaskDataIterator = { reset(...): void, next?: TaskDataIteratorNext }
//   Ported as a final class (shared mutable singleton `iterator` below; see the module-level IIFE).

public struct TaskDefineParam<Ctx: TaskContext> {
    public var reset: TaskResetCallback<Ctx>?
    // Returns 'reset' indicate reset immediately
    public var plan: TaskPlanCallback<Ctx>?
    // count is used to determine data task.
    public var count: TaskCountCallback<Ctx>?
    public var onDirty: TaskOnDirtyCallback<Ctx>?
    public init(
        reset: TaskResetCallback<Ctx>? = nil,
        plan: TaskPlanCallback<Ctx>? = nil,
        count: TaskCountCallback<Ctx>? = nil,
        onDirty: TaskOnDirtyCallback<Ctx>? = nil
    ) {
        self.reset = reset
        self.plan = plan
        self.count = count
        self.onDirty = onDirty
    }
}

public struct PerformArgs {
    public var step: Double?
    public var skip: Bool?
    public var modBy: Double?
    public var modDataCount: Double?
    public init(step: Double? = nil, skip: Bool? = nil, modBy: Double? = nil, modDataCount: Double? = nil) {
        self.step = step
        self.skip = skip
        self.modBy = modBy
        self.modDataCount = modDataCount
    }
}

/**
 * @param {Object} define
 * @return See the return of `createTask`.
 */
public func createTask<Ctx: TaskContext>(
    _ define: TaskDefineParam<Ctx>
) -> Task<Ctx> {
    return Task<Ctx>(define)
}

public final class Task<Ctx: TaskContext>: AnyTask {

    private var _reset: TaskResetCallback<Ctx>?
    private var _plan: TaskPlanCallback<Ctx>?
    private var _count: TaskCountCallback<Ctx>?
    private var _onDirty: TaskOnDirtyCallback<Ctx>?
    private var _progress: TaskProgressLike<Ctx>?
    private var _callingProgress: TaskProgressCallback<Ctx>?

    private var _dirty: Bool
    private var _modBy: Double?
    private var _modDataCount: Double?
    // PORT-TODO: `_upstream`/`_downstream` form a strong reference cycle (upstream JS relies on GC;
    //   `dispose()` breaks the chain). Kept strong to preserve upstream lifetime semantics.
    //   Erased to `(any AnyTask)?` (upstream `Task<Ctx>`) to allow cross-context piping (see AnyTask).
    public var _upstream: (any AnyTask)?
    public var _downstream: (any AnyTask)?
    private var _dueEnd: Double = 0
    public private(set) var _outputDueEnd: Double = 0   // upstream: private
    private var _settedOutputEnd: Double?
    private var _dueIndex: Double = 0
    public private(set) var _disposed: Bool = false      // upstream: private

    // Injected in schedular
    public var __pipeline: Pipeline?
    public var __idxInPipeline: Double?
    public var __block: Bool? // FIXME: simplify it - merge with PerformStageTaskOpt['block']?

    // Injected in Scheduler (upstream: `OverallTask` / `StubTask` intersection props tacked onto the
    //   task object). `agentStubMap` lives on the overall task; `agent` on the stub. Kept on the base
    //   `Task` so they survive `context` replacement across resets (the overall task reuses its stubs).
    public var agentStubMap: HashMap<StubTask>?   // upstream: OverallTask['agentStubMap']
    public var agent: OverallTask?                // upstream: StubTask['agent']

    // Context must be specified implicitly, to
    // avoid miss update context when model changed.
    public var context: Ctx!

    // Erased accessor for `AnyTask` (upstream reads `upTask.context.outputData` directly).
    public var _contextOutputData: SeriesData? { return self.context?.outputData }

    public init(_ define: TaskDefineParam<Ctx>?) {
        let define = define ?? TaskDefineParam<Ctx>()

        self._reset = define.reset
        self._plan = define.plan
        self._count = define.count
        self._onDirty = define.onDirty

        self._dirty = true
    }

    /**
     * @param step Specified step.
     * @param skip Skip customer perform call.
     * @param modBy Sampling window size.
     * @param modDataCount Sampling count.
     * @return whether unfinished.
     */
    @discardableResult
    public func perform(_ performArgs: PerformArgs? = nil) -> Bool {
        let upTask = self._upstream
        let skip = (performArgs?.skip) ?? false

        // TODO some refactor.
        // Pull data. Must pull data each time, because context.data
        // may be updated by Series.setData.
        if self._dirty, let upTask = upTask {
            let context = self.context!
            context.outputData = upTask._contextOutputData
            context.data = context.outputData
        }

        if self.__pipeline != nil {
            self.__pipeline!.currentTask = self
        }

        var planResult: TaskPlanCallbackReturn?
        if let _plan = self._plan, !skip {
            planResult = _plan(self, self.context)
        }

        // Support sharding by mod, which changes the render sequence and makes the rendered graphic
        // elements uniformed distributed when progress, especially when moving or zooming.
        let lastModBy = normalizeModBy(self._modBy)
        let lastModDataCount = self._modDataCount ?? 0
        let modBy = normalizeModBy(performArgs?.modBy)
        let modDataCount = (performArgs?.modDataCount) ?? 0
        if lastModBy != modBy || lastModDataCount != modDataCount {
            planResult = .reset
        }

        func normalizeModBy(_ val: Double?) -> Double {
            var val = val
            if !((val ?? Double.nan) >= 1) { val = 1 } // jshint ignore:line
            return val!
        }

        var forceFirstProgress: Bool?
        if self._dirty || planResult == .reset {
            self._dirty = false
            forceFirstProgress = self._doReset(skip)
        }

        self._modBy = modBy
        self._modDataCount = modDataCount

        let step = performArgs?.step

        if let upTask = upTask {
            if __DEV__ {
                // upstream: assert(upTask._outputDueEnd != null) — `_outputDueEnd` is a non-optional Double here,
                //   so the null-check is vacuous.
                util.assert(true)
            }
            self._dueEnd = upTask._outputDueEnd
        }
        // DataTask or overallTask
        else {
            if __DEV__ {
                util.assert(self._progress == nil || self._count != nil)
            }
            self._dueEnd = self._count != nil ? self._count!(self, self.context) : Double.infinity
        }

        // Note: Stubs, that its host overall task let it has progress, has progress.
        // If no progress, pass index from upstream to downstream each time plan called.
        if let progress = self._progress {
            let start = self._dueIndex
            let end = Swift.min(
                step != nil ? self._dueIndex + step! : Double.infinity,
                self._dueEnd
            )

            if !skip && ((forceFirstProgress ?? false) || start < end) {
                switch progress {
                case .array(let arr):
                    for i in 0..<arr.count {
                        self._doProgress(arr[i], start, end, modBy, modDataCount)
                    }
                case .single(let cb):
                    self._doProgress(cb, start, end, modBy, modDataCount)
                }
            }

            self._dueIndex = end
            // If no `outputDueEnd`, assume that output data and
            // input data is the same, so use `dueIndex` as `outputDueEnd`.
            let outputDueEnd = self._settedOutputEnd != nil
                ? self._settedOutputEnd! : end

            if __DEV__ {
                // ??? Can not rollback.
                util.assert(outputDueEnd >= self._outputDueEnd)
            }

            self._outputDueEnd = outputDueEnd
        }
        else {
            // (1) Some overall task has no progress.
            // (2) Stubs, that its host overall task do not let it has progress, has no progress.
            // This should always be performed so it can be passed to downstream.
            self._dueIndex = self._settedOutputEnd != nil
                ? self._settedOutputEnd! : self._dueEnd
            self._outputDueEnd = self._dueIndex
        }

        return self.unfinished()
    }

    /**
     * @tutorial [EC_TASK_DIRTY]
     *  Task `dirty()` calls typically originate from a trigger of EC_FULL_UPDATE_CYCLE and
     *  EC_PARTIAL_UPDATE_CYCLE) (See comments in EC_CYCLE. Generally, task dirty propagates
     *  to downstream tasks.
     *  Task dirty leads to the `StageHandler['reset']` or `StageHandler['overallReset']` call,
     *  which discards the previous result and starts over the processing.
     */
    public func dirty() {
        self._dirty = true
        self._onDirty?(self, self.context)
    }

    private func _doProgress(
        _ progress: @escaping (Task<Ctx>, TaskProgressParams, Ctx) -> Void,   // upstream: TaskProgressCallback<Ctx>
        _ start: Double,
        _ end: Double,
        _ modBy: Double,
        _ modDataCount: Double
    ) {
        iterator.reset(start, end, modBy, modDataCount)
        self._callingProgress = progress
        self._callingProgress!(
            self,
            TaskProgressParams(start: start, end: end, count: end - start, next: iterator.next),
            self.context
        )
    }

    private func _doReset(_ skip: Bool) -> Bool? {
        self._dueEnd = 0
        self._outputDueEnd = 0
        self._dueIndex = 0
        self._settedOutputEnd = nil

        var progress: TaskProgressLike<Ctx>?
        var forceFirstProgress: Bool?

        if !skip, let _reset = self._reset {
            let ret = _reset(self, self.context)
            if case .object(let ffp, let prog)? = ret {
                forceFirstProgress = ffp
                progress = prog
            }
            else if case .progress(let prog)? = ret {
                progress = prog
            }
            // To simplify no progress checking, array must has item.
            if case .array(let arr)? = progress, arr.isEmpty {
                progress = nil
            }
        }

        self._progress = progress
        self._modBy = nil
        self._modDataCount = nil

        let downstream = self._downstream
        downstream?.dirty()

        return forceFirstProgress
    }

    public func unfinished() -> Bool {
        return self._progress != nil && self._dueIndex < self._dueEnd
    }

    /**
     * @param downTask The downstream task.
     * @return The downstream task.
     */
    public func pipe(_ downTask: any AnyTask) {
        if __DEV__ {
            // upstream: assert(downTask && !downTask._disposed && downTask !== this)
            util.assert(!downTask._disposed && !(downTask === self))
        }

        // If already downstream, do not dirty downTask.
        if self._downstream !== downTask || self._dirty {
            self._downstream = downTask
            downTask._upstream = self
            downTask.dirty()
        }
    }

    public func dispose() {
        if self._disposed {
            return
        }

        self._upstream?._downstream = nil
        self._downstream?._upstream = nil

        self._dirty = false
        self._disposed = true
    }

    public func getUpstream() -> (any AnyTask)? {
        return self._upstream
    }

    public func getDownstream() -> (any AnyTask)? {
        return self._downstream
    }

    public func setOutputEnd(_ end: Double) {
        // This only happens in dataTask, dataZoom, map, currently.
        // where dataZoom do not set end each time, but only set
        // when reset. So we should record the set end, in case
        // that the stub of dataZoom perform again and earse the
        // set end by upstream.
        self._outputDueEnd = end
        self._settedOutputEnd = end
    }

}

// upstream: const iterator: TaskDataIterator = (function () { ... })();
//   A module-level singleton with closure-captured mutable state. Ported as a final class whose
//   single instance is shared across all `Task<Ctx>` (matching the single upstream module singleton).
final class TaskDataIterator {

    private var end: Double = 0
    private var current: Double = 0
    private var modBy: Double = 0
    private var modDataCount: Double = 0
    private var winCount: Double = 0

    var next: TaskDataIteratorNext?

    func reset(_ s: Double, _ e: Double, _ sStep: Double, _ sCount: Double) {
        current = s
        end = e

        modBy = sStep
        modDataCount = sCount
        winCount = ceil(modDataCount / modBy)

        next = (modBy > 1 && modDataCount > 0) ? { [unowned self] in self.modNext() }
                                               : { [unowned self] in self.sequentialNext() }
    }

    private func sequentialNext() -> Double? {
        if current < end {
            let result = current
            current += 1
            return result
        }
        return nil
    }

    private func modNext() -> Double? {
        let dataIndex = (current.truncatingRemainder(dividingBy: winCount)) * modBy + ceil(current / winCount)
        let result: Double? = current >= end
            ? nil
            : dataIndex < modDataCount
            ? dataIndex
            // If modDataCount is smaller than data.count() (consider `appendData` case),
            // Use normal linear rendering mode.
            : current
        current += 1
        return result
    }
}

let iterator = TaskDataIterator()



// -----------------------------------------------------------------------------
// For stream debug (Should be commented out after used!)
// @usage: printTask(this, 'begin');
// @usage: printTask(this, null, {someExtraProp});
// @usage: Use `__idxInPipeline` as conditional breakpiont.
//
// window.printTask = function (task: any, prefix: string, extra: { [key: string]: unknown }): void {
//     window.ecTaskUID == null && (window.ecTaskUID = 0);
//     task.uidDebug == null && (task.uidDebug = `task_${window.ecTaskUID++}`);
//     task.agent && task.agent.uidDebug == null && (task.agent.uidDebug = `task_${window.ecTaskUID++}`);
//     let props = [];
//     if (task.__pipeline) {
//         let val = `${task.__idxInPipeline}/${task.__pipeline.tail.__idxInPipeline} ${task.agent ? '(stub)' : ''}`;
//         props.push({text: '__idxInPipeline/total', value: val});
//     } else {
//         let stubCount = 0;
//         task.agentStubMap.each(() => stubCount++);
//         props.push({text: 'idx', value: `overall (stubs: ${stubCount})`});
//     }
//     props.push({text: 'uid', value: task.uidDebug});
//     if (task.__pipeline) {
//         props.push({text: 'pipelineId', value: task.__pipeline.id});
//         task.agent && props.push(
//             {text: 'stubFor', value: task.agent.uidDebug}
//         );
//     }
//     props.push(
//         {text: 'dirty', value: task._dirty},
//         {text: 'dueIndex', value: task._dueIndex},
//         {text: 'dueEnd', value: task._dueEnd},
//         {text: 'outputDueEnd', value: task._outputDueEnd}
//     );
//     if (extra) {
//         Object.keys(extra).forEach(key => {
//             props.push({text: key, value: extra[key]});
//         });
//     }
//     let args = ['color: blue'];
//     let msg = `%c[${prefix || 'T'}] %c` + props.map(item => (
//         args.push('color: green', 'color: red'),
//         `${item.text}: %c${item.value}`
//     )).join('%c, ');
//     console.log.apply(console, [msg].concat(args));
//     // console.log(this);
// };
// window.printPipeline = function (task: any, prefix: string) {
//     const pipeline = task.__pipeline;
//     let currTask = pipeline.head;
//     while (currTask) {
//         window.printTask(currTask, prefix);
//         currTask = currTask._downstream;
//     }
// };
// window.showChain = function (chainHeadTask) {
//     var chain = [];
//     var task = chainHeadTask;
//     while (task) {
//         chain.push({
//             task: task,
//             up: task._upstream,
//             down: task._downstream,
//             idxInPipeline: task.__idxInPipeline
//         });
//         task = task._downstream;
//     }
//     return chain;
// };
// window.findTaskInChain = function (task, chainHeadTask) {
//     let chain = window.showChain(chainHeadTask);
//     let result = [];
//     for (let i = 0; i < chain.length; i++) {
//         let chainItem = chain[i];
//         if (chainItem.task === task) {
//             result.push(i);
//         }
//     }
//     return result;
// };
// window.printChainAEachInChainB = function (chainHeadTaskA, chainHeadTaskB) {
//     let chainA = window.showChain(chainHeadTaskA);
//     for (let i = 0; i < chainA.length; i++) {
//         console.log('chainAIdx:', i, 'inChainB:', window.findTaskInChain(chainA[i].task, chainHeadTaskB));
//     }
// };
