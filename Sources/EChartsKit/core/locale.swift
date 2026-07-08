// Ported from echarts/src/core/locale.ts — keep in sync with upstream.
//
// The i18n locale registry. Upstream exposes free functions (`registerLocale`,
// `createLocaleObject`, `getLocaleModel`, `getDefaultLocaleModel`) plus the `SYSTEM_LANG`
// constant, backed by two module-private maps. Following the port convention
// (free-function module → caseless enum namespace), these live under `enum locale`.
//
// upstream:
//   import Model from '../model/Model';
//   import env from 'zrender/src/core/env';
//   import langEN from '../i18n/langEN';
//   import langZH from '../i18n/langZH';
//   import { isString, clone, merge } from 'zrender/src/core/util';

import ZRenderKit

// upstream: export type LocaleOption = typeof langEN;
//   -> the port models a LocaleOption as the same nested `[String: Any]` option tree.
public typealias LocaleOption = [String: Any]

public enum locale {

    // upstream: const LOCALE_ZH = 'ZH'; const LOCALE_EN = 'EN'; const DEFAULT_LOCALE = LOCALE_EN;
    public static let LOCALE_ZH = "ZH"
    public static let LOCALE_EN = "EN"
    static let DEFAULT_LOCALE = LOCALE_EN

    // upstream: const localeStorage: Dictionary<LocaleOption> = {};
    //           const localeModels: Dictionary<Model> = {};
    private static var localeStorage: [String: LocaleOption] = [:]
    private static var localeModels: [String: Model] = [:]

    // upstream:
    //   export const SYSTEM_LANG = !env.domSupported ? DEFAULT_LOCALE : (function () {
    //       const langStr = (document.documentElement.lang || navigator.language || ...).toUpperCase();
    //       return langStr.indexOf(LOCALE_ZH) > -1 ? LOCALE_ZH : DEFAULT_LOCALE;
    //   })();
    //   In this native port `env.domSupported` is ALWAYS false (zrender/core/env.swift: no DOM on
    //   iOS), so the browser-language detection branch is statically unreachable and SYSTEM_LANG is
    //   fixed to DEFAULT_LOCALE (EN). `env` is internal to ZRenderKit, so the invariant is inlined.
    public static let SYSTEM_LANG: String = DEFAULT_LOCALE

    // upstream: export function registerLocale(locale: string, localeObj: LocaleOption)
    public static func registerLocale(_ localeName: String, _ localeObj: LocaleOption) {
        let key = localeName.uppercased()
        localeModels[key] = Model(localeObj)
        localeStorage[key] = localeObj
    }

    // upstream: export function createLocaleObject(locale: string | LocaleOption): LocaleOption
    public static func createLocaleObject(_ localeArg: Any) -> LocaleOption {
        if util.isString(localeArg) {
            let localeName = (localeArg as! String)
            let localeObj = localeStorage[localeName.uppercased()] ?? [:]
            if localeName == LOCALE_ZH || localeName == LOCALE_EN {
                return util.clone(localeObj)
            }
            else {
                var base = util.clone(localeObj)
                _ = util.merge(&base, util.clone(localeStorage[DEFAULT_LOCALE] ?? [:]), false)
                return base
            }
        }
        else {
            var base = util.clone((localeArg as? LocaleOption) ?? [:])
            _ = util.merge(&base, util.clone(localeStorage[DEFAULT_LOCALE] ?? [:]), false)
            return base
        }
    }

    // upstream: export function getLocaleModel(lang: string): Model<LocaleOption>
    public static func getLocaleModel(_ lang: String) -> Model? {
        return localeModels[lang]
    }

    // upstream: export function getDefaultLocaleModel(): Model<LocaleOption>
    public static func getDefaultLocaleModel() -> Model {
        return localeModels[DEFAULT_LOCALE]!
    }

    // upstream (module bottom):
    //   registerLocale(LOCALE_EN, langEN);
    //   registerLocale(LOCALE_ZH, langZH);
    // A caseless enum has no module side-effect slot, so the default registration runs on
    // first access via this idempotent installer (invoked from EChartsSlim.installOnce()).
    //
    // Upstream only side-effect-registers EN + ZH from core/locale.ts; the other i18n/langXX
    // bundles are opt-in in the browser build (the user imports the bundle, which calls
    // `registerLocale`). In this native port there is no per-file import step, so the built-in
    // spread is registered here too (still opt-in at USE time: a chart only picks a locale up by
    // name via `init(locale:)`). Keyed by the standard locale code; `registerLocale` upper-cases
    // the key so lookups are case-insensitive (e.g. "PT-br" -> "PT-BR").
    private static var _defaultsRegistered = false
    public static func registerDefaultLocales() {
        if _defaultsRegistered { return }
        _defaultsRegistered = true
        registerLocale(LOCALE_EN, langEN.option)
        registerLocale(LOCALE_ZH, langZH.option)
        // Broadened built-in locale spread (ported from upstream/echarts/src/i18n/lang*.ts).
        registerLocale("FR", langFR.option)
        registerLocale("DE", langDE.option)
        registerLocale("ES", langES.option)
        registerLocale("JA", langJA.option)
        registerLocale("RU", langRU.option)
        registerLocale("PT-br", langPTbr.option)
    }
}
