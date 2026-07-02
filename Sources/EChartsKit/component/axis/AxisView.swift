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
//   -> PORT-TODO: axisPointer machinery is OUT OF SCOPE for the bar+cartesian+axis milestone
//      (component/axisPointer/modelHelper.ts not ported). Its two call sites here
//      (`fixValue`, `getAxisPointerModel`) are guarded by `axisPointerClass` which is always
//      nil in-scope, so they are dead code and preserved only as PORT-TODO comments.
// import ComponentView from '../../view/Component';        -> EChartsKit `ComponentView` (view/ComponentView.swift).
// import { AxisBaseModel } from '../../coord/AxisBaseModel'; -> EChartsKit `AxisBaseModel` (coord/AxisBaseModel.swift).
// import GlobalModel from '../../model/Global';            -> EChartsKit `GlobalModel` (model/Global.swift).
// import ExtensionAPI from '../../core/ExtensionAPI';      -> EChartsKit `ExtensionAPI` (core/ExtensionAPI.swift).
// import { Payload, Dictionary } from '../../util/types';  -> EChartsKit util/types.swift (`Payload`, `Dictionary<T>` = [String: T]).
// import type BaseAxisPointer from '../axisPointer/BaseAxisPointer';
//   -> PORT-TODO: BaseAxisPointer not ported (out of scope). Referenced only via the `Any?`
//      `_axisPointer` slot and the `AxisPointerConstructor` factory typealias below.

// upstream:
//   const axisPointerClazz: Dictionary<AxisPointerConstructor> = {};
//
//   interface AxisPointerConstructor {
//       new(): BaseAxisPointer
//   }
//
// PORT-TODO: BaseAxisPointer is out of scope. The `new(): BaseAxisPointer` constructor interface is
//   modeled as a factory closure `() -> AnyObject`. The registry starts empty and nothing registers
//   into it in-scope (no axisPointer classes are ported), so `getAxisPointerClass` always yields nil
//   and every axisPointer code path below short-circuits.
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
    // PORT-TODO: BaseAxisPointer not ported (out of scope); typed `Any?`. Never assigned in-scope.
    private var _axisPointer: Any?

    /**
     * @protected
     */
    // upstream: axisPointerClass: string;  (protected — Swift has no `protected`, use `open` so
    //   subclasses can set it; see ComponentView §2 note). Defaults nil (no axisPointer in-scope).
    open var axisPointerClass: String?

    /**
     * @override
     */
    // PORT-TODO: upstream types `axisModel: AxisBaseModel`; Swift cannot narrow an override parameter
    //   (ComponentView.render takes ComponentModel), so the base type is kept and downcast where an
    //   AxisBaseModel is required. The render pipeline always passes an AxisBaseModel here.
    open override func render(_ axisModel: ComponentModel, _ ecModel: GlobalModel, _ api: ExtensionAPI, _ payload: Payload) {
        // FIXME
        // This process should proformed after coordinate systems updated
        // (axis scale updated), and should be performed each time update.
        // So put it here temporarily, although it is not appropriate to
        // put a model-writing procedure in `view`.
        if self.axisPointerClass != nil {
            // PORT-TODO: axisPointerModelHelper.fixValue(axisModel) — axisPointer machinery out of
            //   scope; `axisPointerClass` is always nil in-scope so this is dead code.
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
        if axisPointer != nil {
            // PORT-TODO: axisPointer.remove(api) — BaseAxisPointer out of scope; `_axisPointer` is
            //   never assigned in-scope so this is dead code.
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
        let Clazz = AxisView.getAxisPointerClass(self.axisPointerClass)
        if Clazz == nil {
            return
        }
        // PORT-TODO: axisPointer machinery out of scope (axisPointer/modelHelper + BaseAxisPointer
        //   not ported). Unreachable in-scope because `Clazz` is always nil (empty registry).
        //   Upstream:
        //     const axisPointerModel = axisPointerModelHelper.getAxisPointerModel(axisModel);
        //     axisPointerModel
        //         ? (this._axisPointer || (this._axisPointer = new Clazz()))
        //             .render(axisModel, axisPointerModel, api, forceRender)
        //         : this._disposeAxisPointer(api);
        _ = axisModel
        _ = api
        _ = forceRender
    }

    private func _disposeAxisPointer(_ api: ExtensionAPI) {
        if self._axisPointer != nil {
            // PORT-TODO: self._axisPointer.dispose(api) — BaseAxisPointer out of scope; never
            //   assigned in-scope. Upstream: this._axisPointer && this._axisPointer.dispose(api);
        }
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
