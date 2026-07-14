// Ported from echarts/src/util/event.ts — keep in sync with upstream
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

import ZRenderKit
// upstream: import Element from 'zrender/src/Element';   → ZRenderKit.Element

// export function findEventDispatcher(
//     target: Element,
//     det: (target: Element) => boolean,
//     returnFirstMatch?: boolean
// )
//
// `target` is `Element?` here (the upstream `while (target)` loop walks until the parent chain runs
// out, so the parameter is nullable in practice; `e.target` on a `globalout` is null as well).
public func findEventDispatcher(
    _ target: Element?,
    _ det: (Element) -> Bool,
    _ returnFirstMatch: Bool? = nil
) -> Element? {
    var target = target
    var found: Element?
    while let t = target {
        if det(t) {
            found = t
            if returnFirstMatch == true {
                break
            }
        }

        // target = target.__hostTarget || target.parent;
        target = t.__hostTarget ?? (t.parent as? Element)
    }
    return found
}
