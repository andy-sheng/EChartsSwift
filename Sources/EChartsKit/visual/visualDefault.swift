// Ported from echarts/src/visual/visualDefault.ts — keep in sync with upstream.
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

/**
 * @file Visual mapping.
 */

import Foundation
import ZRenderKit

// import * as zrUtil from 'zrender/src/core/util';   -> `util` (ZRenderKit).
// import tokens from './tokens';
//   -> PORT-NOTE: visual/tokens.swift has landed, but `tokens.color.transparent` is still inlined
//      here as its literal 'rgba(0,0,0,0)' (`tokensColorTransparent`) rather than read from `tokens`.
//      A follow-up may re-wire this to `tokens.color.transparent`.
private let tokensColorTransparent = "rgba(0,0,0,0)"

// const visualDefault = { get: function (visualType, key, isCategory?) { ... } };
//   Caseless namespace (mirrors format/number/util) — the upstream default export is an object literal
//   with a single `get` method.
public enum visualDefault {

    /**
     * @public
     */
    // get: function (visualType: string, key: 'active' | 'inactive', isCategory?: boolean)
    public static func get(_ visualType: String, _ key: String, _ isCategory: Bool? = nil) -> Any? {
        // const value = zrUtil.clone((defaultOption[visualType] || {})[key]);
        let entry = defaultOption[visualType]
        let raw: Any? = entry?[key]
        guard let raw = raw else {
            // clone(undefined) === undefined
            return nil
        }
        let value = util.clone(raw)

        // return isCategory ? (zrUtil.isArray(value) ? value[value.length - 1] : value) : value;
        if isCategory == true {
            if let arr = value as? [Any] {
                return arr.isEmpty ? value : arr[arr.count - 1]
            }
            return value
        }
        return value
    }
}

// const defaultOption: {[key: string]: { active: string[] | number[], inactive: string[] | number[] }}
//   Modeled as [visualType: [state: [Any]]] so the string- and number-valued default rows share one shape.
private let defaultOption: [String: [String: [Any]]] = [

    "color": [
        "active": ["#006edd", "#e0ffff"],
        "inactive": [tokensColorTransparent]
    ],

    "colorHue": [
        "active": [0.0, 360.0],
        "inactive": [0.0, 0.0]
    ],

    "colorSaturation": [
        "active": [0.3, 1.0],
        "inactive": [0.0, 0.0]
    ],

    "colorLightness": [
        "active": [0.9, 0.5],
        "inactive": [0.0, 0.0]
    ],

    "colorAlpha": [
        "active": [0.3, 1.0],
        "inactive": [0.0, 0.0]
    ],

    "opacity": [
        "active": [0.3, 1.0],
        "inactive": [0.0, 0.0]
    ],

    "symbol": [
        "active": ["circle", "roundRect", "diamond"],
        "inactive": ["none"]
    ],

    "symbolSize": [
        "active": [10.0, 50.0],
        "inactive": [0.0, 0.0]
    ]
]
