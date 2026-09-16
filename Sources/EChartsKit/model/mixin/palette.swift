// Ported from echarts/src/model/mixin/palette.ts — keep in sync with upstream

import ZRenderKit
// import {Dictionary} from 'zrender/src/core/types';                                 -> [String: T]                       (= zrender Dictionary)
// import {makeInner, normalizeToArray} from '../../util/model';                       -> model.makeInner / model.normalizeToArray (util/model.swift)
// import Model from '../Model';                                                       -> Model                             (sibling model/Model.swift: ref type with `get`)
// import {ZRColor, PaletteOptionMixin, DecalObject, AriaOptionMixin} from '../../util/types'; -> ZRColor / PaletteOptionMixin / DecalObject / AriaOptionMixin (util/types.swift)
// import GlobalModel from '../Global';                                                -> GlobalModel                       (util/types.swift stub; sibling model/Global.swift)

// upstream: type Inner<T> = (hostObj: PaletteMixin<PaletteOptionMixin>) => { paletteIdx: number; paletteNameMap: Dictionary<T>; };
//   The host (`scope`) is only used as a `makeInner`/WeakMap identity key (an arbitrary
//   object), so it is typed `AnyObject` here rather than `PaletteMixin`. The returned
//   per-host store is the reference-type `PaletteInner<T>` (see below).
typealias Inner<T> = (AnyObject) -> PaletteInner<T>

// upstream: the `{ paletteIdx: number; paletteNameMap: Dictionary<T> }` object stored per host.
//   `makeInner` requires a reference type (CONVENTIONS §2 / util/model.makeInner), so the
//   inline object literal becomes a `final class`. Both fields start `undefined` (upstream
//   creates an empty `{}`), modeled as Optionals so `paletteIdx || 0` / `paletteNameMap || {}`
//   port verbatim.
final class PaletteInner<T> {
    var paletteIdx: Double?
    var paletteNameMap: [String: T]?
}

private let innerColor: Inner<ZRColor> = model.makeInner { PaletteInner<ZRColor>() }

// NOTE (decal modeling): a runtime `DecalObject` is the dynamic option bag `[String: Any]` — the aria
//   decal palette in globalDefault.swift and `itemStyle.decal` are both plain dicts, and `util/decal`'s
//   `createOrUpdatePatternFromDecal` reads keys off that bag. So the palette stores/returns `[String: Any]`
//   (the typed `DecalObject` struct in util/types.swift is kept for provenance only). Modeling this as
//   `DecalObject` would make `normalizeToArray<DecalObject>([[String:Any]])` yield `[]` (a dict is not a
//   `DecalObject` struct) → every `getDecalFromPalette` would return nil.
private let innerDecal: Inner<[String: Any]> = model.makeInner { PaletteInner<[String: Any]>() }



// upstream:
//   interface PaletteMixin<T extends PaletteOptionMixin = PaletteOptionMixin> extends Pick<Model<T>, 'get'> {}
//   class PaletteMixin<T extends PaletteOptionMixin = PaletteOptionMixin> { ... }
//   ... applied via `mixin(GlobalModel, PaletteMixin)` and `mixin(SeriesModel, PaletteMixin)`.
// Per CONVENTIONS §2 a TS mixin is ported as a Swift protocol + protocol-extension. The
// `Pick<Model<T>, 'get'>` constraint becomes the `get` protocol requirement; the class
// methods (`getColorFromPalette`, `clearColorPalette`) become extension default methods.
// GlobalModel and SeriesModel declare conformance (`: PaletteMixin`) where they are ported,
// mirroring upstream's two `mixin(...)` call sites. The `T extends PaletteOptionMixin`
// generic only narrows `get`'s option type and has no Swift analogue, so it is dropped.
public protocol PaletteMixin: AnyObject {
    // upstream: Pick<Model<T>, 'get'>  (path can be `string | readonly string[]`, hence `Any?`)
    func get(_ path: Any?, _ ignoreParent: Bool) -> Any?
}

extension PaletteMixin {

    public func getColorFromPalette(
        _ name: String,
        _ scope: AnyObject? = nil,
        _ requestNum: Double? = nil
    ) -> ZRColor? {
        // The dynamic option tree stores `color`/`colorLayer` as raw `Any` (e.g. the default theme
        //   palette is `[String]`; see globalDefault.swift `themeColorTheme`). A plain color string IS a
        //   valid `ZRColor` upstream (`ZRColor = ColorString | GradientObject | PatternObject`), but
        //   `normalizeToArray<ZRColor>` cannot cast `[String]`→`[ZRColor]`, so it would yield `[]` and no
        //   series would ever get a palette color. Coerce raw strings → `.color` (and pass through any
        //   already-typed `ZRColor`) so the palette is populated. Faithful bridge until the option ingest
        //   stores typed `ZRColor` values directly.
        let defaultPalette: [ZRColor] = coerceZRColorArray(self.get("color", true))
        let layeredPalette = self.get("colorLayer", true) as? [[ZRColor]]
        return getFromPalette(self, innerColor, defaultPalette, layeredPalette, name, scope, requestNum)
    }

    public func clearColorPalette() {
        clearPalette(self, innerColor)
    }

}

public func getDecalFromPalette(
    _ ecModel: GlobalModel,
    _ name: String,
    _ scope: AnyObject,
    _ requestNum: Double? = nil
) -> [String: Any]? {
    // upstream: const defaultDecals = normalizeToArray((ecModel as Model<AriaOptionMixin>).get(['aria', 'decal', 'decals']));
    // upstream casts ecModel to `Model<AriaOptionMixin>` purely for typing `get`;
    //   here GlobalModel conforms to PaletteMixin (upstream `mixin(GlobalModel, PaletteMixin)`),
    //   which exposes `get`, so the cast targets PaletteMixin. Decals are the dynamic option bag
    //   `[String: Any]` (see the innerDecal note above).
    let that = ecModel as PaletteMixin   // GlobalModel conforms to PaletteMixin (upcast)
    let defaultDecals: [[String: Any]] = model.normalizeToArray(that.get(["aria", "decal", "decals"], false))
    return getFromPalette(that, innerDecal, defaultDecals, nil, name, scope, requestNum)
}


// Coerce a raw dynamic `color` option (String / [String] / ZRColor / [ZRColor] / mixed [Any]) into a
// `[ZRColor]`. A plain color string maps to `.string`. Not an upstream symbol — bridges the dynamic
// option bag to the typed `ZRColor` enum (see `getColorFromPalette`).
private func coerceZRColorArray(_ raw: Any?) -> [ZRColor] {
    func one(_ el: Any?) -> ZRColor? {
        if let z = el as? ZRColor { return z }
        if let s = el as? ColorString { return .color(s) }
        return nil
    }
    guard let raw = raw else { return [] }
    if let arr = raw as? [ZRColor] { return arr }
    if let arr = raw as? [ColorString] { return arr.map { .color($0) } }
    if let arr = raw as? [Any] { return arr.compactMap(one) }
    if let single = one(raw) { return [single] }
    return []
}

private func getNearestPalette<T>(
    _ palettes: [[T]], _ requestColorNum: Double
) -> [T]? {
    let paletteNum = palettes.count
    // TODO palettes must be in order
    for i in 0..<paletteNum {
        if Double(palettes[i].count) > requestColorNum {
            return palettes[i]
        }
    }
    // upstream: `return palettes[paletteNum - 1];` — returns `undefined` when `palettes` is empty
    //   (then handled by `palette = palette || defaultPalette` at the call site). Return nil for the
    //   empty case so the Swift subscript never traps on an empty array (upstream's undefined).
    return paletteNum > 0 ? palettes[paletteNum - 1] : nil
}

/**
 * @param name MUST NOT be null/undefined. Otherwise call this function
 *             twise with the same parameters will get different result.
 * @param scope default this.
 * @return Can be null/undefined
 */
private func getFromPalette<T>(
    _ that: PaletteMixin,
    _ inner: Inner<T>,
    _ defaultPalette: [T],
    _ layeredPalette: [[T]]?,
    _ name: String,
    _ scope: AnyObject?,
    _ requestNum: Double?
) -> T? {
    let scope = scope ?? that   // scope = scope || that
    let scopeFields = inner(scope)
    let paletteIdx = scopeFields.paletteIdx ?? 0   // scopeFields.paletteIdx || 0
    // const paletteNameMap = scopeFields.paletteNameMap = scopeFields.paletteNameMap || {};
    // (upstream `paletteNameMap` aliases the same object; Swift dicts are value types, so we
    //  operate directly on `scopeFields.paletteNameMap`.)
    if scopeFields.paletteNameMap == nil {
        scopeFields.paletteNameMap = [:]
    }
    // Use `hasOwnProperty` to avoid conflict with Object.prototype.
    if let existing = scopeFields.paletteNameMap![name] {
        return existing
    }
    var palette: [T]?
    if requestNum == nil || layeredPalette == nil {
        palette = defaultPalette
    } else {
        palette = getNearestPalette(layeredPalette!, requestNum!)
    }

    // In case can't find in layered color palette.
    palette = palette ?? defaultPalette

    guard let palette = palette, palette.count > 0 else {
        return nil
    }

    let pickedPaletteItem = palette[Int(paletteIdx)]
    if !name.isEmpty {   // if (name)
        scopeFields.paletteNameMap![name] = pickedPaletteItem
    }
    scopeFields.paletteIdx = (paletteIdx + 1).truncatingRemainder(dividingBy: Double(palette.count))

    return pickedPaletteItem
}

private func clearPalette<T>(_ that: PaletteMixin, _ inner: Inner<T>) {
    inner(that).paletteIdx = 0
    inner(that).paletteNameMap = [:]
}
