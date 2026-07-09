// Ported from echarts/src/component/marker/installMarkLine.ts — keep in sync with upstream.
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

// upstream install.ts:
//   registers.registerComponentModel(MarkLineModel);
//   registers.registerComponentView(MarkLineView);
//   registers.registerPreprocessor(function (opt) {
//       if (checkMarkerInSeries(opt.series, 'markLine')) { opt.markLine = opt.markLine || {}; }
//   });
// The registration + view-factory wiring lives in the driver (ECharts.installOnce); the
// preprocessor (auto-enable the master markLine component when any series declares markLine) is here.
public func markLinePreprocessor(_ opt: inout [String: Any]) {
    // if (checkMarkerInSeries(opt.series, 'markLine')) { opt.markLine = opt.markLine || {}; }
    if checkMarkerInSeries(opt["series"], "markLine") {
        if opt["markLine"] == nil {
            opt["markLine"] = [String: Any]()
        }
    }
}
