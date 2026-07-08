// Ported from echarts/src/visual/aria.ts (+ echarts/src/component/aria/install.ts) —
// keep in sync with upstream.
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

// upstream (visual/aria.ts):
//   import * as zrUtil from 'zrender/src/core/util';
//   import ExtensionAPI from '../core/ExtensionAPI';
//   import GlobalModel from '../model/Global';
//   import Model from '../model/Model';
//   import SeriesModel from '../model/Series';
//   import {createSimpleOverallStageHandler2, makeInner} from '../util/model';
//   import {Dictionary, DecalObject, InnerDecalObject, AriaOption} from '../util/types';
//   import {LocaleOption} from '../core/locale';
//   import { getDecalFromPalette } from '../model/mixin/palette';
//   import type {TitleOption} from '../component/title/install';
//
// The free-function upstream module maps to this caseless enum namespace (CONVENTIONS).
public enum aria {

    // upstream:
    //   const DEFAULT_OPTION: AriaOption = {
    //       label: { enabled: true },
    //       decal: { show: false }
    //   };
    static var DEFAULT_OPTION: [String: Any] {
        return [
            "label": ["enabled": true],
            "decal": ["show": false]
        ]
    }

    // upstream:
    //   export const ariaVisualStageHandler = createSimpleOverallStageHandler2(ariaVisual);
    //
    // The upstream `ariaVisual` writes the generated label to the DOM (`dom.setAttribute('aria-label', ...)`).
    // There is no DOM in this native port, so the label is RETURNED (see `ariaLabel(...)`) and the driver
    // (`EChartsSlim`) stores it on the ec instance + exposes it via `getAriaLabel()`. This stage handler is
    // kept for faithfulness (mirrors the upstream registration shape) and simply drives the generator; the
    // computed string is dropped here because a `StageHandler` returns Void — the driver calls
    // `aria.ariaLabel(ecModel, api)` directly so it can capture the result.
    public static let ariaVisualStageHandler: StageHandler =
        model.createSimpleOverallStageHandler2 { ecModel, api, _ in
            _ = aria.ariaLabel(ecModel, api)
        }

    // ------------------------------------------------------------------------
    // upstream: function ariaVisual(ecModel, api) { ... setDecal(); setLabel(); }
    //
    // The port splits out the LABEL generation (pure data + locale, RETURNED as a String?) from the
    // DECAL generation (PORT-TODO below). Returns `nil` when aria is disabled / has no series (upstream:
    // the early `return`s that leave `aria-label` unset).
    // ------------------------------------------------------------------------
    public static func ariaLabel(_ ecModel: GlobalModel, _ api: ExtensionAPI) -> String? {
        let ariaModel = ecModel.getModel("aria")

        // upstream: // See "area enabled" detection code in `GlobalModel.ts`.
        //   if (!ariaModel.get('enabled')) { return; }
        if !jsTruthy(ariaModel.get("enabled")) {
            return nil
        }

        // upstream:
        //   const defaultOption = zrUtil.clone(DEFAULT_OPTION);
        //   zrUtil.merge(defaultOption.label, ecModel.getLocaleModel().get('aria'), false);
        //   zrUtil.merge(ariaModel.option, defaultOption, false);
        let localeAria = (ecModel.getLocaleModel().get(["aria"]) as? [String: Any]) ?? [:]
        var defaultOption = DEFAULT_OPTION
        var defaultLabel = (defaultOption["label"] as? [String: Any]) ?? [:]
        _ = util.merge(&defaultLabel, localeAria, false)
        defaultOption["label"] = defaultLabel

        var ariaOpt = (ariaModel.option as? [String: Any]) ?? [:]
        _ = util.merge(&ariaOpt, defaultOption, false)
        ariaModel.option = ariaOpt

        // upstream splits setDecal() / setLabel(). Only setLabel() is ported (returns the string).
        // PORT-TODO (setDecal): the `aria.decal.show` branch generates decal (SVG-pattern) visuals per datum
        //   via `getDecalFromPalette` + `data.setItemVisual(idx, 'decal', ...)`. The decal palette infra
        //   (model/mixin/palette.getDecalFromPalette + the renderer's decal pattern fill) is not ported yet,
        //   so decal generation is deferred. The LABEL string below is the primary deliverable.

        return setLabel(ecModel, api, ariaModel, localeAria)
    }

    // upstream: function setLabel() { ... } (nested in ariaVisual)
    private static func setLabel(
        _ ecModel: GlobalModel,
        _ api: ExtensionAPI,
        _ ariaModel: Model,
        _ labelLocale: [String: Any]
    ) -> String? {
        // upstream:
        //   const dom = api.getZr().dom;
        //   // TODO: support for SSR
        //   if (!dom) { return; }
        // PORT: no DOM in the native port — the guard is inapplicable; the label is returned instead of
        //   being written to `dom.setAttribute('aria-label', ...)`.

        // upstream:
        //   const labelLocale = ecModel.getLocaleModel().get('aria');
        //   const labelModel = ariaModel.getModel('label');
        //   labelModel.option = zrUtil.defaults(labelModel.option, labelLocale);
        let labelModel = ariaModel.getModel(["label"])
        var labelOpt = (labelModel.option as? [String: Any]) ?? [:]
        _ = util.defaults(&labelOpt, labelLocale)
        labelModel.option = labelOpt

        // upstream: if (!labelModel.get('enabled')) { return; }
        if !jsTruthy(labelModel.get("enabled")) {
            return nil
        }

        // upstream: dom.setAttribute('role', 'img'); — no DOM, skipped.

        // upstream:
        //   if (labelModel.get('description')) {
        //       dom.setAttribute('aria-label', labelModel.get('description'));
        //       return;
        //   }
        if let description = labelModel.get("description") as? String, !description.isEmpty {
            return description
        }

        // upstream:
        //   const seriesCnt = ecModel.getSeriesCount();
        //   const maxDataCnt = labelModel.get(['data', 'maxCount']) || 10;
        //   const maxSeriesCnt = labelModel.get(['series', 'maxCount']) || 10;
        //   const displaySeriesCnt = Math.min(seriesCnt, maxSeriesCnt);
        let seriesCnt = Int(ecModel.getSeriesCount())
        let maxDataCnt = intOr(labelModel.get(["data", "maxCount"]), 10)
        let maxSeriesCnt = intOr(labelModel.get(["series", "maxCount"]), 10)
        let displaySeriesCnt = min(seriesCnt, maxSeriesCnt)

        // upstream: if (seriesCnt < 1) { return; }
        if seriesCnt < 1 {
            return nil
        }

        var ariaLabel: String

        // upstream:
        //   const title = getTitle();
        //   if (title) {
        //       const withTitle = labelModel.get(['general', 'withTitle']);
        //       ariaLabel = replace(withTitle, { title: title });
        //   } else {
        //       ariaLabel = labelModel.get(['general', 'withoutTitle']);
        //   }
        if let title = getTitle(ecModel), !title.isEmpty {
            let withTitle = str(labelModel.get(["general", "withTitle"]))
            ariaLabel = replace(withTitle, ["title": title])
        }
        else {
            ariaLabel = str(labelModel.get(["general", "withoutTitle"]))
        }

        // upstream:
        //   const seriesLabels: string[] = [];
        //   const prefix = seriesCnt > 1
        //       ? labelModel.get(['series', 'multiple', 'prefix'])
        //       : labelModel.get(['series', 'single', 'prefix']);
        //   ariaLabel += replace(prefix, { seriesCount: seriesCnt });
        var seriesLabels: [String] = []
        let prefix = seriesCnt > 1
            ? str(labelModel.get(["series", "multiple", "prefix"]))
            : str(labelModel.get(["series", "single", "prefix"]))
        ariaLabel += replace(prefix, ["seriesCount": String(seriesCnt)])

        // upstream: ecModel.eachSeries(function (seriesModel, idx) { if (idx < displaySeriesCnt) { ... } });
        ecModel.eachSeries { seriesModel, idx in
            if Int(idx) < displaySeriesCnt {
                var seriesLabel: String

                // upstream:
                //   const seriesName = seriesModel.get('name');
                //   const withName = seriesName ? 'withName' : 'withoutName';
                //   seriesLabel = seriesCnt > 1
                //       ? labelModel.get(['series', 'multiple', withName])
                //       : labelModel.get(['series', 'single', withName]);
                let seriesName = seriesModel.get("name")
                let withName = jsTruthy(seriesName) ? "withName" : "withoutName"
                seriesLabel = seriesCnt > 1
                    ? str(labelModel.get(["series", "multiple", withName]))
                    : str(labelModel.get(["series", "single", withName]))

                // upstream:
                //   seriesLabel = replace(seriesLabel, {
                //       seriesId: seriesModel.seriesIndex,
                //       seriesName: seriesModel.get('name'),
                //       seriesType: getSeriesTypeName(seriesModel.subType as SeriesTypes)
                //   });
                seriesLabel = replace(seriesLabel, [
                    "seriesId": String(Int(seriesModel.seriesIndex)),
                    "seriesName": str(seriesName),
                    "seriesType": getSeriesTypeName(ecModel, seriesModel.subType)
                ])

                let data = seriesModel.getData()

                // upstream:
                //   if (data.count() > maxDataCnt) {
                //       const partialLabel = labelModel.get(['data', 'partialData']);
                //       seriesLabel += replace(partialLabel, { displayCnt: maxDataCnt });
                //   } else {
                //       seriesLabel += labelModel.get(['data', 'allData']);
                //   }
                if data.count() > maxDataCnt {
                    let partialLabel = str(labelModel.get(["data", "partialData"]))
                    seriesLabel += replace(partialLabel, ["displayCnt": String(maxDataCnt)])
                }
                else {
                    seriesLabel += str(labelModel.get(["data", "allData"]))
                }

                // upstream:
                //   const middleSeparator = labelModel.get(['data', 'separator', 'middle']);
                //   const endSeparator = labelModel.get(['data', 'separator', 'end']);
                //   const excludeDimensionId = labelModel.get(['data', 'excludeDimensionId']);
                let middleSeparator = str(labelModel.get(["data", "separator", "middle"]))
                let endSeparator = str(labelModel.get(["data", "separator", "end"]))
                let excludeDimensionId = labelModel.get(["data", "excludeDimensionId"]) as? [Any]

                var dataLabels: [String] = []
                // upstream:
                //   for (let i = 0; i < data.count(); i++) {
                //       if (i < maxDataCnt) {
                //           const name = data.getName(i);
                //           const value = !excludeDimensionId ? data.getValues(i)
                //               : zrUtil.filter(data.getValues(i), (v, j) =>
                //                   zrUtil.indexOf(excludeDimensionId, j) === -1);
                //           const dataLabel = labelModel.get(['data', name ? 'withName' : 'withoutName']);
                //           dataLabels.push(replace(dataLabel, {
                //               name: name, value: value.join(middleSeparator)
                //           }));
                //       }
                //   }
                let cnt = data.count()
                var i = 0
                while i < cnt {
                    if i < maxDataCnt {
                        let name = data.getName(i)
                        let allValues = data.getValues(i)
                        let value: [Any]
                        if let excludeDimensionId = excludeDimensionId {
                            value = util.filter(allValues) { _, j in
                                !indexOfDim(excludeDimensionId, j)
                            }
                        }
                        else {
                            value = allValues
                        }
                        let dataLabel = str(labelModel.get(["data", !name.isEmpty ? "withName" : "withoutName"]))
                        dataLabels.append(replace(dataLabel, [
                            "name": name,
                            "value": joinValues(value, middleSeparator)
                        ]))
                    }
                    i += 1
                }
                // upstream: seriesLabel += dataLabels.join(middleSeparator) + endSeparator;
                seriesLabel += dataLabels.joined(separator: middleSeparator) + endSeparator

                seriesLabels.append(seriesLabel)
            }
        }

        // upstream:
        //   const separatorModel = labelModel.getModel(['series', 'multiple', 'separator']);
        //   const middleSeparator = separatorModel.get('middle');
        //   const endSeparator = separatorModel.get('end');
        //   ariaLabel += seriesLabels.join(middleSeparator) + endSeparator;
        let separatorModel = labelModel.getModel(["series", "multiple", "separator"])
        let middleSeparator = str(separatorModel.get("middle"))
        let endSeparator = str(separatorModel.get("end"))
        ariaLabel += seriesLabels.joined(separator: middleSeparator) + endSeparator

        // upstream: dom.setAttribute('aria-label', ariaLabel);
        return ariaLabel
    }

    // upstream:
    //   function replace(str: string, keyValues: object) {
    //       if (!zrUtil.isString(str)) { return str; }
    //       let result = str;
    //       zrUtil.each(keyValues, function (value, key) {
    //           result = result.replace(new RegExp('\\{\\s*' + key + '\\s*\\}', 'g'), value);
    //       });
    //       return result;
    //   }
    private static func replace(_ template: String, _ keyValues: [String: String]) -> String {
        var result = template
        for (key, value) in keyValues {
            // new RegExp('\\{\\s*' + key + '\\s*\\}', 'g')
            let pattern = "\\{\\s*" + NSRegularExpression.escapedPattern(for: key) + "\\s*\\}"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            // String.replace replaces the raw match text with `value` verbatim (no `$` templating).
            let escapedValue = NSRegularExpression.escapedTemplate(for: value)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: escapedValue)
        }
        return result
    }

    // upstream:
    //   function getTitle() {
    //       let title = ecModel.get('title') as TitleOption | TitleOption[];
    //       if (title && (title as TitleOption[]).length) { title = (title as TitleOption[])[0]; }
    //       return title && (title as TitleOption).text;
    //   }
    private static func getTitle(_ ecModel: GlobalModel) -> String? {
        var title = ecModel.get("title", false)
        // if (title && title.length) — an array of title options: take the first.
        if let arr = title as? [Any], !arr.isEmpty {
            title = arr[0]
        }
        if let titleObj = title as? [String: Any] {
            return str(titleObj["text"])
        }
        return nil
    }

    // upstream:
    //   function getSeriesTypeName(type: SeriesTypes) {
    //       const typeNames = ecModel.getLocaleModel().get(['series', 'typeNames']);
    //       return typeNames[type] || typeNames.chart;
    //   }
    private static func getSeriesTypeName(_ ecModel: GlobalModel, _ type: String) -> String {
        let typeNames = (ecModel.getLocaleModel().get(["series", "typeNames"]) as? [String: Any]) ?? [:]
        if let name = typeNames[type] as? String, !name.isEmpty {
            return name
        }
        return (typeNames["chart"] as? String) ?? ""
    }

    // ---- port-local helpers -------------------------------------------------

    // JS truthiness for an option value (mirrors Series.swift's private `jsTruthy`).
    private static func jsTruthy(_ v: Any?) -> Bool {
        guard let v = v else { return false }
        if let b = v as? Bool { return b }
        if let d = v as? Double { return d != 0 && !d.isNaN }
        if let i = v as? Int { return i != 0 }
        if let n = v as? NSNumber { return n.doubleValue != 0 }
        if let s = v as? String { return !s.isEmpty }
        return true
    }

    // Coerce an option value to a String (locale templates are strings; upstream `replace` returns the
    // raw value unchanged when it is not a string, but every template read here is a string key).
    private static func str(_ v: Any?) -> String {
        guard let v = v else { return "" }
        if let s = v as? String { return s }
        return numStr(v)
    }

    // Int coercion with a fallback (upstream `labelModel.get(...) || 10`). Handles the Int-vs-Double
    // option-boxing trap (numbers box as Int OR Double).
    private static func intOr(_ v: Any?, _ fallback: Int) -> Int {
        guard let v = v else { return fallback }
        if let i = v as? Int { return i != 0 ? i : fallback }
        if let d = v as? Double { return d != 0 ? Int(d) : fallback }
        if let n = v as? NSNumber { return n.intValue != 0 ? n.intValue : fallback }
        return fallback
    }

    // `value.join(middleSeparator)` — stringify each ParsedValue (JS Number/String → toString) and join.
    private static func joinValues(_ values: [Any], _ separator: String) -> String {
        return values.map { numStr($0) }.joined(separator: separator)
    }

    // JS `Number.prototype.toString` style: integral doubles print without a trailing ".0" ("120", not
    // "120.0"); strings pass through.
    private static func numStr(_ v: Any) -> String {
        if let s = v as? String { return s }
        if let i = v as? Int { return String(i) }
        if let d = v as? Double {
            if d.isNaN { return "NaN" }
            if d == d.rounded() && abs(d) < 1e15 { return String(Int(d)) }
            return String(d)
        }
        if let n = v as? NSNumber {
            let d = n.doubleValue
            if d == d.rounded() && abs(d) < 1e15 { return String(Int(d)) }
            return String(d)
        }
        return "\(v)"
    }

    // zrUtil.indexOf(excludeDimensionId, j) === -1  →  is dimension index `j` present in the exclude list?
    private static func indexOfDim(_ list: [Any], _ j: Int) -> Bool {
        for e in list {
            if let i = e as? Int, i == j { return true }
            if let d = e as? Double, Int(d) == j { return true }
            if let n = e as? NSNumber, n.intValue == j { return true }
        }
        return false
    }
}
