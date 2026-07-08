// Ported from echarts/src/component/aria/preprocessor.ts — keep in sync with upstream.
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

// upstream:
//   import * as zrUtil from 'zrender/src/core/util';
//   import { ECUnitOption, AriaOptionMixin } from '../../util/types';
//
//   export default function ariaPreprocessor(option: ECUnitOption & AriaOptionMixin) { ... }
//
// The default-export free function maps to a top-level free function (CONVENTIONS). Mutates the
// option bag in place (inout ECUnitOption == [String: Any]), mirroring the sibling preprocessors
// wired into `EChartsSlim.setOption` (visualMapPreprocessor / timelinePreprocessor).
public func ariaPreprocessor(_ option: inout [String: Any]) {
    // upstream: if (!option || !option.aria) { return; }
    guard var aria = option["aria"] as? [String: Any] else {
        return
    }

    // upstream:
    //   // aria.show is deprecated and should use aria.enabled instead
    //   if ((aria as any).show != null) { aria.enabled = (aria as any).show; }
    if aria["show"] != nil {
        aria["enabled"] = aria["show"]
    }

    // upstream: aria.label = aria.label || {};
    var label = (aria["label"] as? [String: Any]) ?? [:]

    // upstream:
    //   // move description, general, series, data to be under aria.label
    //   zrUtil.each(['description', 'general', 'series', 'data'], name => {
    //       if ((aria as any)[name] != null) { (aria.label as any)[name] = (aria as any)[name]; }
    //   });
    for name in ["description", "general", "series", "data"] {
        if let value = aria[name] {
            label[name] = value
        }
    }

    aria["label"] = label
    option["aria"] = aria
}
