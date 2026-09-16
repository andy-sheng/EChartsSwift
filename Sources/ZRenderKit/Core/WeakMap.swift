// Ported from zrender/src/core/WeakMap.ts — keep in sync with upstream
//
// Upstream is a browser shim for the native ES `WeakMap`: it stores the value as a
// hidden, non-enumerable property (keyed by a per-instance unique `_id`) directly on the
// key object. That mechanism (`Object.defineProperty` / dynamic property bag on the key)
// has no faithful Swift analogue. Per the file-specific porting guidance we replace the
// storage mechanism with `NSMapTable` (weak keys → strong values) while preserving the
// public API surface (`get` / `set` / `delete` / `has`). The `wmUniqueIndex` /
// `supportDefineProperty` / `_id` machinery only existed to namespace the hidden property
// on the key, so it is intentionally dropped here.
// storage mechanism deviates from upstream (NSMapTable instead of hidden
//            property on key); behavior of the public API is preserved.

import Foundation

// upstream: let wmUniqueIndex = Math.round(Math.random() * 9);
//           const supportDefineProperty = typeof Object.defineProperty === 'function';
// Both only support the hidden-property storage scheme that we replace; see header note.

// upstream: export default class WeakMap<K extends object, V>
// K extends object → Swift requires the key to be a reference type (`AnyObject`) so it can
// be held weakly, matching the native WeakMap's weak-key / object-key semantics.
public final class WeakMap<K: AnyObject, V> {

    // upstream: protected _id: string  — replaced by the NSMapTable storage below.
    // upstream: internal/protected; Swift has no `protected`.  // upstream: protected
    private let _table: NSMapTable<K, _WeakMapBox<V>>

    public init() {
        // upstream: this._id = '__ec_inner_' + wmUniqueIndex++;
        // Replaced by an NSMapTable with weak keys and strong values.
        _table = NSMapTable<K, _WeakMapBox<V>>(
            keyOptions: [.weakMemory, .objectPointerPersonality],
            valueOptions: .strongMemory
        )
    }

    public func get(_ key: K) -> V? {
        // upstream: return (this._guard(key) as any)[this._id];
        return _table.object(forKey: _guard(key))?.value
    }

    @discardableResult
    public func set(_ key: K, _ value: V) -> WeakMap<K, V> {
        // upstream: const target = this._guard(key) as any;
        //           Object.defineProperty(target, this._id, { value, enumerable: false, configurable: true });
        // (the `supportDefineProperty` fallback `target[this._id] = value` is moot here)
        _table.setObject(_WeakMapBox(value), forKey: _guard(key))
        return self
    }

    @discardableResult
    public func delete(_ key: K) -> Bool {
        // upstream:
        // if (this.has(key)) {
        //     delete (this._guard(key) as any)[this._id];
        //     return true;
        // }
        // return false;
        if has(key) {
            _table.removeObject(forKey: _guard(key))
            return true
        }
        return false
    }

    public func has(_ key: K) -> Bool {
        // upstream: return !!(this._guard(key) as any)[this._id];
        // The `!!` coerces the stored value to a JS boolean: a *falsy* stored value
        // (undefined/null, 0, NaN, '', false) yields `has() === false` even though the key
        // is present. Mirror that truthiness test here rather than a bare presence check so a
        // stored 0/''/false/nil reads has()==false exactly as upstream does.
        guard let box = _table.object(forKey: _guard(key)) else {
            return false
        }
        return WeakMap._isTruthy(box.value)
    }

    // JS `!!value` truthiness for an arbitrary stored `V`. Not a distinct upstream method —
    // it inlines the `!!` coercion in `has()` — but factored out here because Swift lacks the
    // implicit boolean coercion. Falsy: nil/Optional.none, false, 0 (any numeric zero), NaN,
    // "" (empty string). Everything else (non-empty strings, non-zero numbers, objects) is
    // truthy.
    private static func _isTruthy(_ value: V) -> Bool {
        let any: Any = value
        let mirror = Mirror(reflecting: any)
        if mirror.displayStyle == .optional {
            // Optional.none → JS undefined/null → falsy; otherwise test the wrapped value.
            guard let wrapped = mirror.children.first?.value else {
                return false
            }
            return _isTruthyAny(wrapped)
        }
        return _isTruthyAny(any)
    }

    private static func _isTruthyAny(_ any: Any) -> Bool {
        switch any {
        case let b as Bool:
            return b
        case let d as Double:
            return d != 0 && !d.isNaN
        case let f as Float:
            return f != 0 && !f.isNaN
        case let i as Int:
            return i != 0
        case let s as String:
            return !s.isEmpty
        case let ss as Substring:
            return !ss.isEmpty
        default:
            // Other numeric widths coerce to Double via NSNumber; non-numeric objects are
            // truthy in JS (only the primitives above are falsy).
            if let n = any as? NSNumber {
                let d = n.doubleValue
                return d != 0 && !d.isNaN
            }
            return true
        }
    }

    // upstream: protected _guard(key: K): K
    // upstream: protected; Swift has no `protected`.  // upstream: protected
    private func _guard(_ key: K) -> K {
        // upstream:
        // if (key !== Object(key)) {
        //     throw TypeError('Value of WeakMap is not a non-null object.');
        // }
        // return key;
        // In Swift `K: AnyObject` already guarantees a non-null object reference, so the
        // runtime type/null check is statically enforced; nothing to throw.
        return key
    }
}

// Box so that arbitrary `V` (including value types) can be stored as a strong object in the
// NSMapTable. Not present upstream; an artifact of the storage-mechanism deviation.
private final class _WeakMapBox<V> {
    let value: V
    init(_ value: V) {
        self.value = value
    }
}
