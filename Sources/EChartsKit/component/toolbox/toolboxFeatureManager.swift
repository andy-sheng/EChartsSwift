// Ported from echarts/src/component/toolbox/featureManager.ts — keep in sync with upstream
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

// upstream imports (mapped to this port):
//   import Displayable from 'zrender/src/graphic/Displayable'; -> ZRenderKit `Displayable` (icon paths).
//   import Model from '../../model/Model';                     -> `Model`.
//   import GlobalModel from '../../model/Global';              -> `GlobalModel`.
//   import ExtensionAPI from '../../core/ExtensionAPI';        -> `ExtensionAPI`.
//   The `IconStyle` / `ToolboxFeatureOption` / `ToolboxFeatureModel` INTERFACES collapse to the
//   dynamic `[String: Any]` option bag + a `Model` (CONVENTIONS §2). `ToolboxFeatureModel` therefore
//   aliases `Model`; its `iconPaths` collection + `setIconStatus` live in the side-table / free
//   function below (Element/Model are not dynamically extensible in Swift).

// upstream: `export interface ToolboxFeatureModel extends Model<Opts> { iconPaths; setIconStatus(...) }`.
//   The port keeps it a plain `Model`; the injected `iconPaths` map is held in a `makeInner` side table
//   (`toolboxIconPathsInner`) and `setIconStatus` is the free function `toolboxSetIconStatus` below.
public typealias ToolboxFeatureModel = Model

// upstream: `abstract class ToolboxFeature<Opts>` (declaration-merged with an interface of optional
//   hooks). CONVENTIONS §2: reference type + subclassed by each concrete feature -> `open class`.
//   The `Opts` generic (a phantom type param) is dropped; the option is read off `self.model`.
open class ToolboxFeature {

    // uid: string;  (assigned by the view via getUID('toolbox-feature'))
    public var uid: String = ""

    // model: ToolboxFeatureModel<Opts>;  ecModel: GlobalModel;  api: ExtensionAPI;  (injected by the view)
    public var model: ToolboxFeatureModel!
    public var ecModel: GlobalModel!
    public var api: ExtensionAPI!

    public init() {}

    // upstream (optional): getIcons?(): Dictionary<string>
    //   Default nil -> the view falls back to `featureModel.get('icon')`. MagicType/DataZoom override.
    open func getIcons() -> [String: String]? { return nil }

    // upstream: onclick(ecModel, api, type, event): void  — `type` is the clicked icon name.
    //   PORT: the `event: ZRElementEvent` arg is deferred (interaction detail); the two features that
    //   need only the icon name (restore/magicType) are wired end-to-end.
    open func onclick(_ ecModel: GlobalModel, _ api: ExtensionAPI, _ type: String) {}

    // upstream (optional): dispose?(ecModel, api): void
    open func dispose(_ ecModel: GlobalModel, _ api: ExtensionAPI) {}

    // upstream (optional): render?(featureModel, model, api, payload): void  (DataZoom mounts its BrushController)
    open func render(
        _ featureModel: ToolboxFeatureModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {}

    // upstream (optional): updateView?(featureModel, model, api, payload): void
    open func updateView(
        _ featureModel: ToolboxFeatureModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload
    ) {}
}

// upstream: `export interface UserDefinedToolboxFeature { uid; model; ecModel; api; featureName?; onclick() }`.
//   A user-defined (`my*`) toolbox feature is NOT a subclass of `ToolboxFeature`; it is a plain object that
//   carries the injected view context (uid/model/ecModel/api) plus an optional `featureName` and a zero-arg
//   `onclick`. Modeled as a protocol (CONVENTIONS §2 — interface -> protocol) so the toolbox view can adopt it
//   for `my*` features. No concrete conformer is registered via `registerFeature` (these come from the option).
public protocol UserDefinedToolboxFeature: AnyObject {
    var uid: String { get set }

    var model: ToolboxFeatureModel { get set }
    var ecModel: GlobalModel { get set }
    var api: ExtensionAPI { get set }

    var featureName: String? { get set }

    func onclick()
}

// upstream: `type ToolboxFeatureCtor = { new(): ToolboxFeature; defaultOption?; getDefaultOption?; }`.
//   Swift has no static-on-the-constructor `getDefaultOption`, so a registration bundles a factory
//   closure with the (optional) `getDefaultOption(ecModel)` — read by `ToolboxModel.optionUpdated`.
public struct ToolboxFeatureRegistration {
    public let create: () -> ToolboxFeature
    // upstream `Feature.getDefaultOption?(ecModel)` — the per-feature default icon/title/show bag.
    public let getDefaultOption: ((GlobalModel) -> [String: Any])?
    public init(
        create: @escaping () -> ToolboxFeature,
        getDefaultOption: ((GlobalModel) -> [String: Any])? = nil
    ) {
        self.create = create
        self.getDefaultOption = getDefaultOption
    }
}

// const features: Dictionary<ToolboxFeatureCtor> = {};
private var _toolboxFeatures: [String: ToolboxFeatureRegistration] = [:]

// export function registerFeature(name, ctor) { features[name] = ctor; }
public func registerFeature(_ name: String, _ registration: ToolboxFeatureRegistration) {
    _toolboxFeatures[name] = registration
}

// export function getFeature(name) { return features[name]; }
public func getFeature(_ name: String) -> ToolboxFeatureRegistration? {
    return _toolboxFeatures[name]
}

// ─────────────────────────── iconPaths side table + setIconStatus ───────────────────────────
// upstream stores the created icon Displayables on `featureModel.iconPaths` (injected by the view)
//   and `featureModel.setIconStatus(iconName, status)` flips the icon's emphasis state. Model is not
//   dynamically extensible in Swift, so `iconPaths` lives in a `makeInner` side table.

final class ToolboxIconPaths {
    var paths: [String: Displayable] = [:]
}
let toolboxIconPathsInner: (Model) -> ToolboxIconPaths = model.makeInner { ToolboxIconPaths() }

// upstream: featureModel.setIconStatus = function (iconName, status) {
//     option.iconStatus = option.iconStatus || {};
//     option.iconStatus[iconName] = status;
//     if (iconPaths[iconName]) (status === 'emphasis' ? enterEmphasis : leaveEmphasis)(iconPaths[iconName]);
// };
public func toolboxSetIconStatus(_ featureModel: Model, _ iconName: String, _ status: String) {
    var option = (featureModel.option as? [String: Any]) ?? [:]
    var iconStatus = (option["iconStatus"] as? [String: Any]) ?? [:]
    iconStatus[iconName] = status
    option["iconStatus"] = iconStatus
    featureModel.option = option
    // (status === 'emphasis' ? enterEmphasis : leaveEmphasis)(iconPaths[iconName]);  — flip the live icon.
    if let path = toolboxIconPathsInner(featureModel).paths[iconName] {
        if status == "emphasis" { states.enterEmphasis(path) }
        else { states.leaveEmphasis(path) }
    }
}
