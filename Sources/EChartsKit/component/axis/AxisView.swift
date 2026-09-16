// Ported from echarts/src/component/axis/AxisView.ts — keep in sync with upstream
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

// import * as axisPointerModelHelper from '../axisPointer/modelHelper';
//   -> modelHelper (component/axisPointer/modelHelper.swift) is ported; its two call sites here
//      (`fixValue`, `getAxisPointerModel`) are wired below as free functions. They are guarded by
//      `axisPointerClass`, which no in-scope subclass sets, so the registry (`axisPointerClazz`) is
//      never populated and these paths stay effectively dead — but faithfully wired.
// import ComponentView from '../../view/Component';        -> EChartsKit `ComponentView` (view/ComponentView.swift).
// import { AxisBaseModel } from '../../coord/AxisBaseModel'; -> EChartsKit `AxisBaseModel` (coord/AxisBaseModel.swift).
// import GlobalModel from '../../model/Global';            -> EChartsKit `GlobalModel` (model/Global.swift).
// import ExtensionAPI from '../../core/ExtensionAPI';      -> EChartsKit `ExtensionAPI` (core/ExtensionAPI.swift).
// import { Payload, Dictionary } from '../../util/types';  -> EChartsKit util/types.swift (`Payload`, `Dictionary<T>` = [String: T]).
// import type BaseAxisPointer from '../axisPointer/BaseAxisPointer';
//   -> note: BaseAxisPointer is ported (component/axisPointer/BaseAxisPointer.swift), but this
//      base-AxisView path is unused here (axisPointer is driven by AxisPointerView/globalListener instead);
//      referenced in this file only via the `Any?`
//      `_axisPointer` slot and the `AxisPointerConstructor` factory typealias below.

// upstream:
//   const axisPointerClazz: Dictionary<AxisPointerConstructor> = {};
//
//   interface AxisPointerConstructor {
//       new(): BaseAxisPointer
//   }
//
// BaseAxisPointer IS ported (component/axisPointer/BaseAxisPointer.swift). The
//   `new(): BaseAxisPointer` constructor interface is modeled as a factory closure `() -> AnyObject`
//   (the concrete registrant returns a BaseAxisPointer subclass). The registry starts empty and nothing
//   registers into it in-scope, so `getAxisPointerClass` yields nil and the dispatch below short-circuits.
public typealias AxisPointerConstructor = () -> AnyObject

/**
 * Base class of AxisView.
 */
// CONVENTIONS §2/§4: reference type, subclassed by CartesianAxisView/... — `open class`.
open class AxisView: ComponentView {

    // upstream: static type = 'axis';
    public static let type = "axis"
    // upstream: type = AxisView.type;  (ComponentView has no `type`; declared fresh here, cf. ChartView.type)
    open var type: String = AxisView.type

    // module-level `const axisPointerClazz` (module-private in TS). Hoisted onto the class as a
    //   `private static` dictionary so the two static registry methods below can reach it.
    private static var axisPointerClazz: Dictionary<AxisPointerConstructor> = [:]

    /**
     * @private
     */
    // upstream: private _axisPointer: BaseAxisPointer;
    // BaseAxisPointer is ported; typed faithfully. Assigned only when the axisPointer registry
    //   is populated (never in-scope), so this stays nil in practice.
    private var _axisPointer: BaseAxisPointer?

    /**
     * @protected
     */
    // upstream: axisPointerClass: string;  (protected — Swift has no `protected`, use `open` so
    //   subclasses can set it; see ComponentView §2 note). Defaults nil (no axisPointer in-scope).
    open var axisPointerClass: String?

    /**
     * @override
     */
    // upstream types `axisModel: AxisBaseModel`; Swift cannot narrow an override parameter
    //   (ComponentView.render takes ComponentModel), so the base type is kept and downcast where an
    //   AxisBaseModel is required. The render pipeline always passes an AxisBaseModel here.
    open override func render(_ axisModel: ComponentModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload) {
        // FIXME
        // This process should proformed after coordinate systems updated
        // (axis scale updated), and should be performed each time update.
        // So put it here temporarily, although it is not appropriate to
        // put a model-writing procedure in `view`.
        if self.axisPointerClass != nil {
            // axisPointerModelHelper.fixValue(axisModel);
            fixValue(axisModel as! AxisBaseModel)
        }

        super.render(axisModel, ecModel, api, payload)

        self._doUpdateAxisPointerClass(axisModel as! AxisBaseModel, api, true)
    }

    /**
     * Action handler.
     */
    open func updateAxisPointer(
        _ axisModel: AxisBaseModel,
        _ ecModel: GlobalModel,
        _ api: ExtensionAPI,
        _ payload: Payload
    ) {
        self._doUpdateAxisPointerClass(axisModel, api, false)
    }

    /**
     * @override
     */
    // upstream: ComponentView declares an optional `remove?`; the Swift ComponentView port does not
    //   surface it, so this is a fresh `open func` (not an `override`).
    open func remove(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        let axisPointer = self._axisPointer
        if let axisPointer = axisPointer {
            // axisPointer.remove(api);
            axisPointer.remove(api)
        }
    }

    /**
     * @override
     */
    open override func dispose(_ ecModel: GlobalModel, _ api: ExtensionAPI) {
        self._disposeAxisPointer(api)
        super.dispose(ecModel, api)
    }

    private func _doUpdateAxisPointerClass(_ axisModel: AxisBaseModel, _ api: ExtensionAPI, _ forceRender: Bool? = nil) {
        guard let Clazz = AxisView.getAxisPointerClass(self.axisPointerClass) else {
            return
        }
        // Unreachable in-scope because the registry is empty (`Clazz` is always nil), but faithfully wired.
        // const axisPointerModel = axisPointerModelHelper.getAxisPointerModel(axisModel);
        let axisPointerModel = getAxisPointerModel(axisModel)
        if let axisPointerModel = axisPointerModel {
            // (this._axisPointer || (this._axisPointer = new Clazz())).render(axisModel, axisPointerModel, api, forceRender)
            if self._axisPointer == nil {
                self._axisPointer = Clazz() as? BaseAxisPointer
            }
            self._axisPointer?.render(axisModel, axisPointerModel, api, forceRender ?? false)
        }
        else {
            // this._disposeAxisPointer(api);
            self._disposeAxisPointer(api)
        }
    }

    private func _disposeAxisPointer(_ api: ExtensionAPI) {
        // this._axisPointer && this._axisPointer.dispose(api);
        self._axisPointer?.dispose(api)
        self._axisPointer = nil
    }

    public static func registerAxisPointerClass(_ type: String, _ clazz: @escaping AxisPointerConstructor) {
        if __DEV__ {
            if axisPointerClazz[type] != nil {
                // upstream: throw new Error('axisPointer ' + type + ' exists');
                fatalError("axisPointer " + type + " exists")
            }
        }
        axisPointerClazz[type] = clazz
    }

    public static func getAxisPointerClass(_ type: String?) -> AxisPointerConstructor? {
        // upstream: return type && axisPointerClazz[type];
        guard let type = type else {
            return nil
        }
        return axisPointerClazz[type]
    }

}

// export default AxisView;  -> `open class AxisView` above.
