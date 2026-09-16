// Ported from echarts/src/component/axisPointer/AxisPointer.ts — keep in sync with upstream
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

// upstream imports (resolved to the ported modules):
// import { AxisBaseModel } from '../../coord/AxisBaseModel';   -> coord/AxisBaseModel.swift (same module)
// import ExtensionAPI from '../../core/ExtensionAPI';          -> core/ExtensionAPI.swift (same module)
// import { CommonAxisPointerOption } from '../../util/types';  -> the option surface is the dynamic
//     `[String: Any]` bag read through `Model.get(...)` (CONVENTIONS §2); the TS interface is documentary.
// import Model from '../../model/Model';                       -> model/Model.swift (same module)

// upstream: export interface AxisPointer { render(...); remove(api); dispose(api); }
//
//   note (CONVENTIONS §2): upstream `AxisPointer` is a pure TS interface implemented by the
//   `BaseAxisPointer` class (and, through it, the concrete `CartesianAxisPointer` / `PolarAxisPointer`
//   / `SingleAxisPointer`). Modeled as a Swift `protocol` (class-bound — the implementors are the
//   reference-type pointer managers). `axisPointerModel: Model<CommonAxisPointerOption>` collapses to
//   the untyped `Model`; the option surface is read via `Model.get(...)` (the dynamic bag).
public protocol AxisPointer: AnyObject {

    /// If `show` called, axisPointer must be displayed or remain its original status.
    // upstream: render(axisModel, axisPointerModel, /* coordSys, */ api, forceRender?)
    func render(
        _ axisModel: AxisBaseModel,
        _ axisPointerModel: Model,
        _ api: ExtensionAPI,
        _ forceRender: Bool
    )

    /// If `hide` called, axisPointer must be hidden.
    func remove(_ api: ExtensionAPI)

    func dispose(_ api: ExtensionAPI)
}
