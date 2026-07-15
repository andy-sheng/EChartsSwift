// Ported from echarts/src/component/transform/install.ts — keep in sync with upstream
// NOTE: file named transformInstall.swift (not install.swift) to avoid SwiftPM object-file basename
//   collisions with the other per-component install files (cf. datasetInstall / installTitle).
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

// upstream imports (mapped to this port; `→` marks the Swift symbol used):
//   import { EChartsExtensionInstallRegisters } from '../../extension';
//     -> `EChartsExtensionInstallRegisters` (registrar stub in coord/axisStatistics.swift, Phase 6b).
//   import { filterTransform } from './filterTransform';   -> `filterTransform` (component/transform/filterTransform.swift).
//   import { sortTransform } from './sortTransform';       -> `sortTransform` (component/transform/sortTransform.swift).

import Foundation
import ZRenderKit

// upstream:
//   export function install(registers: EChartsExtensionInstallRegisters) {
//       registers.registerTransform(filterTransform);
//       registers.registerTransform(sortTransform);
//   }
//
// PORT: the Phase-6b `EChartsExtensionInstallRegisters` stub does not yet expose `registerTransform`.
//   In this port the transform registry lives in data/helper/transform.swift and the public registrar
//   is `registerExternalTransform(_:)` — the same function `registers.registerTransform` proxies to
//   upstream (`extension.ts` -> `registerExternalTransform`). Register the two built-ins directly
//   against it, mirroring how `datasetInstall` registers directly against the reachable registry while
//   still threading `registers` through to keep the upstream call shape. Swap the two bodies to
//   `registers.registerTransform(...)` once that registrar surface lands.
//
//   `registerExternalTransform` is `throws` (it validates the `ns:name` type on registration); both
//   built-ins carry valid namespaced types ("echarts:filter" / "echarts:sort"), so registration never
//   throws here — `try!` keeps `transformInstall` non-throwing to match the upstream `install` shape
//   and the sibling `*Install` functions.
public func transformInstall(_ registers: EChartsExtensionInstallRegisters) {
    _ = registers
    // registers.registerTransform(filterTransform);
    try! registerExternalTransform(filterTransform)
    // registers.registerTransform(sortTransform);
    try! registerExternalTransform(sortTransform)
    // NOT upstream: echarts-stat's `ecStat:regression` (ported in ecStatRegressionTransform.swift) so the
    //   scatter-*-regression official examples build natively. Harmless if a page never uses it.
    try! registerExternalTransform(ecStatRegressionTransform)
    // upstream registers this in chart/boxplot/install.ts; the port centralizes external-transform
    //   registration here. Enables `transform: { type: 'boxplot' }` (boxplot-* examples).
    try! registerExternalTransform(boxplotTransform)
}
