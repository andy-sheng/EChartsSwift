// Ported from echarts/src/component/dataset/install.ts — keep in sync with upstream
// NOTE: file named datasetInstall.swift (not install.swift) to avoid SwiftPM object-file basename
//   collisions with the other per-component install files (cf. installTitle/installGraphic).
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

/**
 * This module is imported by echarts directly.
 *
 * Notice:
 * Always keep this file exists for backward compatibility.
 * Because before 4.1.0, dataset is an optional component,
 * some users may import this module manually.
 */

import Foundation
import ZRenderKit

// upstream imports (mapped to this port; `→` marks the Swift symbol used):
//   import ComponentModel from '../../model/Component';              -> `ComponentModel` (model/Component.swift).
//   import ComponentView from '../../view/Component';                -> `ComponentView` (view/ComponentView.swift).
//   import {
//       SERIES_LAYOUT_BY_COLUMN, ComponentOption, SeriesEncodeOptionMixin,
//       OptionSourceData, SeriesLayoutBy, OptionSourceHeader
//   } from '../../util/types';
//     -> `SERIES_LAYOUT_BY_COLUMN` (util/types.swift). The `DatasetOption` field interfaces are
//        collapsed into the dynamic `[String: Any]` option bag (CONVENTIONS §2); the interface is
//        preserved as commented source below.
//   import { DataTransformOption, PipedDataTransformOption } from '../../data/helper/transform';
//     -> PORT-NOTE: `data/helper/transform.swift` is ported; here these types are only referenced by the
//        collapsed option shape (the dynamic bag), so there is no direct use of them in this file.
//   import GlobalModel from '../../model/Global';                    -> `GlobalModel` (model/Global.swift).
//   import Model from '../../model/Model';                           -> `Model` (model/Model.swift).
//   import { disableTransformOptionMerge, SourceManager } from '../../data/helper/sourceManager';
//     -> `disableTransformOptionMerge` / `SourceManager` (data/helper/sourceManager.swift).
//   import { EChartsExtensionInstallRegisters } from '../../extension';
//     -> `EChartsExtensionInstallRegisters` (registrar stub in coord/axisStatistics.swift, Phase 6b).

// ================================================================================================
// CLASS / PROTOCOL DECISION (documented per the port task):
//
// A forward-reference `protocol DatasetModel` already lives in data/helper/sourceHelper.swift — the
// data layer (sourceManager/sourceHelper) references `DatasetModel` as the dataset host type without
// importing this component-layer file (mirroring upstream's `DatasetModel | SeriesModel` host union,
// where `SeriesModel` reaches the data layer via the `SourceManagerHost` marker).
//
// A Swift CONCRETE class named `DatasetModel` would clash with that `protocol DatasetModel` (same
// module, same name). The clash is unavoidable, so — exactly as the task's fallback prescribes — the
// concrete class is named `DatasetModelImpl` and CONFORMS to the retained `protocol DatasetModel`.
// The protocol was expanded (in sourceHelper.swift) to the surface the data layer calls on a dataset
// host: `uid`, `ecModel`, `componentIndex`, `option`, `get(path, ignoreParent)`, `getSourceManager()`.
// All but `getSourceManager()` are witnessed by `ComponentModel`/`Model` inheritance; `getSourceManager()`
// is implemented here.
//
// `DatasetModelImpl` additionally conforms to `SourceManagerHost` (sourceManager.swift) so it can be
// passed to `SourceManager(self)` — the conformance is added via an extension below (`uid` inherited).
// ================================================================================================

// export interface DatasetOption extends
//         Pick<ComponentOption, 'type' | 'id' | 'name'>,
//         Pick<SeriesEncodeOptionMixin, 'dimensions'> {
//     mainType?: 'dataset';
//     seriesLayoutBy?: SeriesLayoutBy;
//     sourceHeader?: OptionSourceHeader;
//     source?: OptionSourceData;
//     fromDatasetIndex?: number;
//     fromDatasetId?: string;
//     transform?: DataTransformOption | PipedDataTransformOption;
//     // When a transform result more than on results, the results can be referenced only by:
//     // Using `fromDatasetIndex`/`fromDatasetId` and `transfromResultIndex` to retrieve
//     // the results from other dataset.
//     fromTransformResult?: number;
// }
//   -> collapsed into the dynamic `[String: Any]` option bag (CONVENTIONS §2).

// upstream: export class DatasetModel<Opts extends DatasetOption = DatasetOption> extends ComponentModel<Opts>
//   (renamed `DatasetModelImpl`; see the CLASS / PROTOCOL DECISION above. The generic `Opts` is dropped
//    per CONVENTIONS §2 — the option tree is the `Any` bag.)
public final class DatasetModelImpl: ComponentModel, DatasetModel {

    // type = 'dataset';
    // static type = 'dataset';
    //   (the class registry / `ComponentModel.type` read the static; the instance `type` computed
    //    property on the base mirrors it — faithful to `prototype.type = static type`.)
    public override class var type: ComponentFullType { return "dataset" }

    // static defaultOption: DatasetOption = { seriesLayoutBy: SERIES_LAYOUT_BY_COLUMN };
    public override class var defaultOption: ModelOption? {
        return ["seriesLayoutBy": SERIES_LAYOUT_BY_COLUMN] as [String: Any]
    }

    // private _sourceManager: SourceManager;
    //   PORT (SwiftPM trap): an implicitly-unwrapped optional bound to an inferred `let`/`var` would
    //   infer plain Optional — annotate the concrete IUO type. Bound in `init(...)` after `super.init`.
    private var _sourceManager: SourceManager!

    // upstream: init(option: Opts, parentModel: Model, ecModel: GlobalModel): void { ... }
    //   This is the ECharts model LIFECYCLE `init` hook (NOT the Swift designated constructor) — the
    //   base `ComponentModel` exposes it as `open override func \`init\`(...)` (which runs
    //   `mergeDefaultAndTheme`). We override it to mirror upstream `super.init(...)` + wire the
    //   source manager, exactly as the TS body does.
    public override func `init`(
        _ option: ModelOption?, _ parentModel: Model? = nil, _ ecModel: GlobalModel? = nil, _ rest: Any...
    ) {
        // super.init(option, parentModel, ecModel);
        super.`init`(option, parentModel, ecModel)
        // this._sourceManager = new SourceManager(this);
        self._sourceManager = SourceManager(self)
        // disableTransformOptionMerge(this);
        disableTransformOptionMerge(self)
    }

    // upstream: mergeOption(newOption: Opts, ecModel: GlobalModel): void { ... }
    public override func mergeOption(_ newOption: ModelOption?, _ ecModel: GlobalModel?) {
        // super.mergeOption(newOption, ecModel);
        super.mergeOption(newOption, ecModel)
        // disableTransformOptionMerge(this);
        disableTransformOptionMerge(self)
    }

    // upstream: optionUpdated() { this._sourceManager.dirty(); }
    //   (base signature is `optionUpdated(_ newCptOption:, _ isInit:)`; the extra params are ignored,
    //    matching the upstream zero-arg body.)
    public override func optionUpdated(_ newCptOption: ModelOption?, _ isInit: Bool) {
        self._sourceManager.dirty()
    }

    // upstream: getSourceManager() { return this._sourceManager; }
    //   (satisfies the `DatasetModel` protocol requirement — the dataset-specific member the data
    //    layer calls on an upstream dataset host.)
    public func getSourceManager() -> SourceManager {
        return self._sourceManager
    }
}

// `DatasetModelImpl` is a valid `SourceManager` host (upstream host union `DatasetModel | SeriesModel`).
// `SourceManagerHost` only requires `uid`, inherited from `ComponentModel`. Declared as an extension so
// the class body stays a clean mirror of upstream (cf. `extension SeriesModel: SourceManagerHost {}`).
extension DatasetModelImpl: SourceManagerHost {}

// upstream: class DatasetView extends ComponentView { static type = 'dataset'; type = 'dataset'; }
//   Static shell — no behavior (matches upstream: DatasetView has no render/lifecycle overrides).
public final class DatasetView: ComponentView {
    // static type = 'dataset';
    public static let type = "dataset"
    // type = 'dataset';
    public let type = "dataset"
}

// `ComponentView.registerClass` keys the view registry by its static `type`; conform `DatasetView` to
// `ClassManageable` so `DatasetView.self` is a valid `Constructor` for that call (mirrors how
// `ComponentModel` subclasses are `ClassManageable`). The `static let type` above witnesses the
// requirement.
extension DatasetView: ClassManageable {}

// upstream:
//   export function install(registers: EChartsExtensionInstallRegisters) {
//       registers.registerComponentModel(DatasetModel);
//       registers.registerComponentView(DatasetView);
//   }
//
// PORT: the Phase-6b `EChartsExtensionInstallRegisters` stub does not yet expose
//   `registerComponentModel` / `registerComponentView`; register directly against the class
//   registries the ported GlobalModel/echarts driver actually reads — the same reachable path
//   `ECharts` uses for models (`ComponentModel.registerClass(...)`). Swap the two bodies to
//   `registers.registerComponentModel(...)` / `registers.registerComponentView(...)` once the
//   registrar surface lands. `registers` is threaded through now to keep the upstream call shape.
public func datasetInstall(_ registers: EChartsExtensionInstallRegisters) {
    _ = registers
    // registers.registerComponentModel(DatasetModel);
    ComponentModel.registerClass(DatasetModelImpl.self)
    // registers.registerComponentView(DatasetView);
    ComponentView.registerClass(DatasetView.self)
}
