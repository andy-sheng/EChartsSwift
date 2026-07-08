// Ported from echarts/src/component/helper/interactionMutex.ts — keep in sync with upstream
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
//   import { ZRenderType } from 'zrender/src/zrender';   -> ZRenderKit `ZRender`.
//   import * as echarts from '../../core/echarts';       -> registerAction (see PORT-TODO below).
//   import { noop } from 'zrender/src/core/util';         -> unused (only fed to the deferred action).
//   import { makeInner } from '../../util/model';         -> `model.makeInner` (util/modelUtil.swift).

// upstream: `type InteractionMutexResource = { globalPan: string }`. The per-zr resource bag. Upstream
//   stores a single resource key ('globalPan'); modeled here as a keyed dictionary so `take`/`release`/
//   `isTaken` stay generic over `resourceKey` exactly like upstream.
public final class InteractionMutexResource {
    public var store: [String: String] = [:]
    public init() {}
}

// upstream: `const inner = makeInner<InteractionMutexResource, ZRenderType>();` — a per-zr WeakMap.
private let mutexInner: (ZRender) -> InteractionMutexResource = model.makeInner { InteractionMutexResource() }

// upstream: free-function module `export function take/release/isTaken` → caseless enum (CONVENTIONS §2).
public enum interactionMutex {

    // upstream: export function take(zr, resourceKey, userKey) { inner(zr)[resourceKey] = userKey; }
    public static func take(_ zr: ZRender, _ resourceKey: String, _ userKey: String) {
        mutexInner(zr).store[resourceKey] = userKey
    }

    // upstream: export function release(zr, resourceKey, userKey) {
    //     const store = inner(zr); const uKey = store[resourceKey];
    //     if (uKey === userKey) { store[resourceKey] = null; }
    // }
    public static func release(_ zr: ZRender, _ resourceKey: String, _ userKey: String) {
        let store = mutexInner(zr)
        if store.store[resourceKey] == userKey {
            store.store[resourceKey] = nil
        }
    }

    // upstream: export function isTaken(zr, resourceKey) { return !!inner(zr)[resourceKey]; }
    public static func isTaken(_ zr: ZRender, _ resourceKey: String) -> Bool {
        return mutexInner(zr).store[resourceKey] != nil
    }
}

// PORT-TODO: upstream self-registers a `takeGlobalCursor` action (`echarts.registerAction(
//   {type: 'takeGlobalCursor', event: 'globalCursorTaken', update: 'update'}, noop)`) at module load.
//   The graph-roam path does not take the global cursor, so this no-op action registration is DEFERRED
//   (registering it here would run at file scope, which the slim driver has no hook for). Add it if a
//   consumer of the global-pan cursor (brush / dataZoomSelect) is ported.
