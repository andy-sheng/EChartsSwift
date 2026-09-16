// Ported from echarts/src/util/log.ts — keep in sync with upstream
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

// import { Dictionary } from './types';
//   -> EChartsKit util/types.swift exposes `Dictionary<T> = [String: T]` (mirrors zrender core types).
// import { map, isString, isFunction, eqNaN, isRegExp } from 'zrender/src/core/util';
//   -> ZRenderKit `util` namespace (util.map / util.isString / util.isFunction / util.eqNaN / util.isRegExp).

// `__DEV__` is a build-time global replaced by upstream's bundler. There is no
//            shared env/config module in EChartsKit yet, so it is defined here as a module
//            constant (defaults to dev). Move to a central config module once one exists, and
//            remove this declaration to avoid a redeclaration collision.
internal let __DEV__: Bool = true

/// Free-function module `log.ts` -> caseless enum namespace `log` (CONVENTIONS §2).
/// Call sites: upstream `error(...)` / `warn(...)` -> `log.error(...)` / `log.warn(...)`.
public enum log {

    private static let ECHARTS_PREFIX = "[ECharts] "
    private static var storedLogs: Dictionary<Bool> = [:]

    // upstream feature-detects `console` (`typeof console !== 'undefined' && console.warn && console.log`).
    //            Swift has no `console`; output is routed through `print` (see outputLog), which is always available.
    private static let hasConsole = true

    private static func outputLog(_ type: String, _ str: String, _ onlyOnce: Bool? = nil) {
        if hasConsole {
            if onlyOnce == true {
                if storedLogs[str] != nil {
                    return
                }
                storedLogs[str] = true
            }
            // console[type](ECHARTS_PREFIX + str);
            // note (platform): no browser `console` in Swift — `type` ('log' | 'warn' | 'error') is
            //            collapsed onto `print`. There is no strict parity target (browser warn/error share
            //            the devtools console, not a separate stderr stream); left as a single stdout seam.
            _ = type
            print(ECHARTS_PREFIX + str)
        }
    }

    public static func log(_ str: String, _ onlyOnce: Bool? = nil) {
        outputLog("log", str, onlyOnce)
    }

    public static func warn(_ str: String, _ onlyOnce: Bool? = nil) {
        outputLog("warn", str, onlyOnce)
    }

    public static func error(_ str: String, _ onlyOnce: Bool? = nil) {
        outputLog("error", str, onlyOnce)
    }

    public static func deprecateLog(_ str: String) {
        if __DEV__ {
            // Not display duplicate message.
            outputLog("warn", "DEPRECATED: " + str, true)
        }
    }

    public static func deprecateReplaceLog(_ oldOpt: String, _ newOpt: String, _ scope: String? = nil) {
        if __DEV__ {
            deprecateLog((scope != nil ? "[\(scope!)]" : "") + "\(oldOpt) is deprecated; use \(newOpt) instead.")
        }
    }

    /**
     * If in __DEV__ environment, get console printable message for users hint.
     * Parameters are separated by ' '.
     * @usage
     * makePrintable('This is an error on', someVar, someObj);
     *
     * @param hintInfo anything about the current execution context to hint users.
     * @throws Error
     */
    public static func makePrintable(_ hintInfo: Any?...) -> String {
        var msg = ""

        if __DEV__ {
            // Fuzzy stringify for print.
            // This code only exist in dev environment.
            let makePrintableStringIfPossible: (Any?) -> String? = { val in
                if val == nil {
                    return "undefined"
                }
                if let d = val as? Double, d == Double.infinity {
                    return "Infinity"
                }
                if let d = val as? Double, d == -Double.infinity {
                    return "-Infinity"
                }
                if let d = val as? Double, util.eqNaN(d) {
                    return "NaN"
                }
                if let date = val as? Date {
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    return "Date(" + formatter.string(from: date) + ")"
                }
                if util.isFunction(val) {
                    return "function () { ... }"
                }
                if util.isRegExp(val) {
                    return "\(val!)"
                }
                return nil
            }
            // Mirrors upstream's JSON.stringify replacer: re-apply
            // makePrintableStringIfPossible to every nested value so that
            // Infinity/NaN/Date/function/RegExp values buried inside an object or
            // array are printed with the same fuzzy formatting as top-level ones.
            // The result of a special value is a plain string, which JSON then
            // serializes with quotation marks (as upstream does).
            func sanitizeForJSON(_ val: Any?) -> Any {
                if let printable = makePrintableStringIfPossible(val) {
                    return printable
                }
                if let dict = val as? [String: Any] {
                    var out: [String: Any] = [:]
                    for (key, value) in dict {
                        out[key] = sanitizeForJSON(value)
                    }
                    return out
                }
                if let arr = val as? [Any] {
                    return arr.map { sanitizeForJSON($0) }
                }
                return val as Any
            }

            msg = util.map(hintInfo, { arg, _ -> String in
                if util.isString(arg) {
                    // Print without quotation mark for some statement.
                    return arg as! String
                }
                else {
                    let printableStr = makePrintableStringIfPossible(arg)
                    if printableStr != nil {
                        return printableStr!
                    }
                    // typeof JSON !== 'undefined' && JSON.stringify
                    else {
                        let sanitized = sanitizeForJSON(arg)
                        // JSONSerialization only accepts a top-level array/dict, so bare
                        // scalars (number/bool) are wrapped and unwrapped to reuse JSON's
                        // own formatting (JS would stringify them directly).
                        if JSONSerialization.isValidJSONObject(sanitized) {
                            do {
                                let data = try JSONSerialization.data(withJSONObject: sanitized)
                                return String(data: data, encoding: .utf8) ?? "?"
                                // In most cases the info object is small, so do not line break.
                            }
                            catch {
                                return "?"
                            }
                        }
                        else if JSONSerialization.isValidJSONObject([sanitized]) {
                            do {
                                let data = try JSONSerialization.data(withJSONObject: [sanitized])
                                var str = String(data: data, encoding: .utf8) ?? "[?]"
                                if str.hasPrefix("[") && str.hasSuffix("]") {
                                    str = String(str.dropFirst().dropLast())
                                }
                                return str
                            }
                            catch {
                                return "?"
                            }
                        }
                        else {
                            return "?"
                        }
                    }
                }
            }).joined(separator: " ")
        }

        return msg
    }

    /**
     * @throws Error
     */
    public static func throwError(_ msg: String? = nil) throws {
        throw EChartsError(message: msg)
    }
}

/// `throw new Error(msg)` -> a Swift `Error` carrying the optional message.
public struct EChartsError: Error {
    public let message: String?
    public init(message: String? = nil) {
        self.message = message
    }
}
