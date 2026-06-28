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
// PORT-TODO: storage mechanism deviates from upstream (NSMapTable instead of hidden
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
        return _table.object(forKey: _guard(key)) != nil
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
