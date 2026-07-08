// Ported from echarts/src/component/timeline/preprocessor.ts — keep in sync with upstream.
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
//   import * as zrUtil from 'zrender/src/core/util';  -> `util.*`.

// PORT-DEVIATION: upstream `registerPreprocessor(timelinePreprocessor)` runs against the shared
//   (mutable, by-reference) option object. The Swift slim driver calls the preprocessors directly in
//   `EChartsSlim.setOption` with `inout` write-back (same pattern as graphicOptionPreprocessor /
//   markPointPreprocessor / …), because the OptionManager preprocessor seam is value-typed and inert
//   (see OptionManager.swift parseRawOption §29). So this variant takes `inout` and rebuilds the
//   normalized `timeline` back into the option bag.
//
// upstream: export default function timelinePreprocessor(option) { ... }
public func timelinePreprocessor(_ option: inout [String: Any]) {
    // let timelineOpt = option && option.timeline;
    let timelineOptRaw = option["timeline"]

    // if (!zrUtil.isArray(timelineOpt)) { timelineOpt = timelineOpt ? [timelineOpt] : []; }
    var timelineOpt: [Any]
    var wasArray = false
    if let arr = timelineOptRaw as? [Any] {
        timelineOpt = arr
        wasArray = true
    }
    else if timelineOptRaw != nil && !(timelineOptRaw is NSNull) {
        timelineOpt = [timelineOptRaw!]
    }
    else {
        timelineOpt = []
    }

    // zrUtil.each(timelineOpt, function (opt) { if (!opt) { return; } compatibleEC2(opt); });
    for i in 0..<timelineOpt.count {
        guard var opt = timelineOpt[i] as? [String: Any] else { continue }
        compatibleEC2(&opt)
        timelineOpt[i] = opt
    }

    // Write the normalized timeline back (single object stays a single object, mirroring upstream's
    //   by-reference mutation of the original entries; the array-wrap above is transient).
    if wasArray {
        option["timeline"] = timelineOpt
    }
    else if !timelineOpt.isEmpty {
        option["timeline"] = timelineOpt[0]
    }
}

// function compatibleEC2(opt)
private func compatibleEC2(_ opt: inout [String: Any]) {
    // const type = opt.type;
    let type = opt["type"] as? String

    // const ec2Types = {'number': 'value', 'time': 'time'};
    let ec2Types: [String: String] = ["number": "value", "time": "time"]

    // Compatible with ec2
    // if (ec2Types[type]) { opt.axisType = ec2Types[type]; delete opt.type; }
    if let t = type, let mapped = ec2Types[t] {
        opt["axisType"] = mapped
        opt.removeValue(forKey: "type")
    }

    // transferItem(opt);
    transferItem(&opt)

    // if (has(opt, 'controlPosition')) { ... }
    if has(opt, "controlPosition") {
        // const controlStyle = opt.controlStyle || (opt.controlStyle = {});
        var controlStyle = (opt["controlStyle"] as? [String: Any]) ?? [:]
        // if (!has(controlStyle, 'position')) { controlStyle.position = opt.controlPosition; }
        if !has(controlStyle, "position") {
            controlStyle["position"] = opt["controlPosition"]
        }
        // if (controlStyle.position === 'none' && !has(controlStyle, 'show')) {
        //     controlStyle.show = false; delete controlStyle.position; }
        if (controlStyle["position"] as? String) == "none" && !has(controlStyle, "show") {
            controlStyle["show"] = false
            controlStyle.removeValue(forKey: "position")
        }
        opt["controlStyle"] = controlStyle
        // delete opt.controlPosition;
        opt.removeValue(forKey: "controlPosition")
    }

    // zrUtil.each(opt.data || [], function (dataItem) { ... });
    if var dataArr = opt["data"] as? [Any] {
        for i in 0..<dataArr.count {
            // if (zrUtil.isObject(dataItem) && !zrUtil.isArray(dataItem)) { ... }
            guard var dataItem = dataArr[i] as? [String: Any] else { continue }
            // if (!has(dataItem, 'value') && has(dataItem, 'name')) { dataItem.value = dataItem.name; }
            if !has(dataItem, "value") && has(dataItem, "name") {
                dataItem["value"] = dataItem["name"]
            }
            transferItem(&dataItem)
            dataArr[i] = dataItem
        }
        opt["data"] = dataArr
    }
}

// function transferItem(opt)
private func transferItem(_ opt: inout [String: Any]) {
    // const itemStyle = opt.itemStyle || (opt.itemStyle = {});
    var itemStyle = (opt["itemStyle"] as? [String: Any]) ?? [:]

    // const itemStyleEmphasis = itemStyle.emphasis || (itemStyle.emphasis = {});
    var itemStyleEmphasis = (itemStyle["emphasis"] as? [String: Any]) ?? [:]

    // Transfer label out
    // const label = opt.label || (opt.label || {});
    var label = (opt["label"] as? [String: Any]) ?? [:]
    // const labelNormal = label.normal || (label.normal = {});
    var labelNormal = (label["normal"] as? [String: Any]) ?? [:]
    // const excludeLabelAttr = {normal: 1, emphasis: 1};
    let excludeLabelAttr: Set<String> = ["normal", "emphasis"]

    // zrUtil.each(label, function (value, name) {
    //     if (!excludeLabelAttr[name] && !has(labelNormal, name)) { labelNormal[name] = value; }
    // });
    for (name, value) in label {
        if !excludeLabelAttr.contains(name) && !has(labelNormal, name) {
            labelNormal[name] = value
        }
    }
    label["normal"] = labelNormal

    // if (itemStyleEmphasis.label && !has(label, 'emphasis')) {
    //     label.emphasis = itemStyleEmphasis.label; delete itemStyleEmphasis.label; }
    if tlTruthy(itemStyleEmphasis["label"]) && !has(label, "emphasis") {
        label["emphasis"] = itemStyleEmphasis["label"]
        itemStyleEmphasis.removeValue(forKey: "label")
    }

    itemStyle["emphasis"] = itemStyleEmphasis
    opt["itemStyle"] = itemStyle
    opt["label"] = label
}

// function has(obj, attr) { return obj.hasOwnProperty(attr); }
private func has(_ obj: [String: Any], _ attr: String) -> Bool {
    return obj[attr] != nil
}
