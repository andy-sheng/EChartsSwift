// Ported (SVG TAG SETS) from echarts/src/component/helper/MapDraw.ts — keep in sync with upstream.
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

// The MapDraw._buildSVG tag classifiers (shared by GeoView._buildSVG and MapView._buildSVG). Upstream keeps
//   them as module-level `HashMap<number, SVGNodeTagLower>`; a `Set` of tag names is the same lookup.
//
// upstream: OPTION_STYLE_ENABLED_TAGS — only these tags apply `itemStyle` if named in SVG. Other tags like
//   <text>/<tspan>/<image> are not suitable for `itemStyle` (they are not styled until a requirement comes).
let OPTION_STYLE_ENABLED_SVG_TAGS: Set<SVGNodeTagLower> = [
    "rect", "circle", "line", "ellipse", "polygon", "polyline", "path"
]

// upstream: STATE_TRIGGER_TAG_MAP — OPTION_STYLE_ENABLED_TAGS.concat(['g']). Named elements of these tags
//   become highDown dispatchers (hover-to-highlight / highlight-by-name).
let STATE_TRIGGER_SVG_TAGS: Set<SVGNodeTagLower> = OPTION_STYLE_ENABLED_SVG_TAGS.union(["g"])

// upstream: LABEL_HOST_MAP — OPTION_STYLE_ENABLED_TAGS.concat(['g']). Named elements of these tags host the
//   region-name label (for <g>, at the group's bounding-rect center).
let LABEL_HOST_SVG_TAGS: Set<SVGNodeTagLower> = OPTION_STYLE_ENABLED_SVG_TAGS.union(["g"])
