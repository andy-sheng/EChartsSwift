// Ported from echarts/src/coord/radar/IndicatorAxis.ts — keep in sync with upstream
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
//   import Axis from '../Axis';                                        -> Axis (coord/Axis.swift).
//   import Scale from '../../scale/Scale';                             -> Scale (scale/Scale.swift).
//   import { OptionAxisType } from '../axisCommonTypes';               -> OptionAxisType (String alias).
//   import { AxisBaseModel } from '../AxisBaseModel';                  -> AxisBaseModel (base `Axis.model` type).
//   import { InnerIndicatorAxisOption } from './RadarModel';           -> dynamic option bag (dropped, CONVENTIONS §2).

// upstream: class IndicatorAxis extends Axis { ... }
//   Not further subclassed → `final class` (CONVENTIONS §2).
public final class IndicatorAxis: Axis {

    // upstream: angle = 0;
    public var angle: Double = 0

    // upstream: name = '';
    public var name: String = ""

    // upstream (property narrowing): model: AxisBaseModel<InnerIndicatorAxisOption>;
    //   The inherited `Axis.model: AxisBaseModel!` already provides this (Swift can not narrow the
    //   generic slot; the dynamic option bag is accessed identically) — no re-declaration needed.

    // upstream: constructor(dim: string, scale: Scale, radiusExtent?: [number, number]) { super(dim, scale, radiusExtent); }
    public override init(_ dim: DimensionName, _ scale: Scale, _ radiusExtent: [Double]? = nil) {
        super.init(dim, scale, radiusExtent)
        // upstream: type: OptionAxisType = 'value';  (instance field default → set after super.init)
        self.type = "value"
    }
}

// export default IndicatorAxis;  -> `public final class IndicatorAxis` above.
