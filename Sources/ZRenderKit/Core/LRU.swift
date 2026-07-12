// Ported from zrender/src/core/LRU.ts — keep in sync with upstream

// import { Dictionary } from './types';  → upstream Dictionary<T> == [String: T]

// Simple LRU cache use doubly linked list
// @module zrender/core/LRU

/// Upstream `key: string | number`. Swift has no untagged union, so we model the
/// key as a tagged enum. Literal conformances keep call sites close to upstream
/// (`lru.put("foo", v)` / `lru.put(1, v)`).
// PORT-NOTE: JS coerces numeric object keys to strings, so `map[1]` and `map["1"]`
// collide in the original. `.number(1)` and `.string("1")` are distinct here.
public enum LRUKey: Hashable {
    case string(String)
    case number(Double)
}

extension LRUKey: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
}

extension LRUKey: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
}

extension LRUKey: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) { self = .number(value) }
}

public final class Entry<T> {

    var value: T

    // upstream: key: string | number  (declared non-optional, but only set in LRU.put)
    var key: LRUKey!

    // upstream: next/prev typed Entry<T> but assigned null at runtime → Optional
    // PORT-NOTE: upstream relies on GC for the doubly-linked list. To avoid a retain
    //   cycle (A.next→B, B.prev→A) in ARC, the forward `next` link stays strong (the
    //   list is kept alive by head + the next-chain) and the back `prev` link is weak.
    var next: Entry<T>?

    weak var prev: Entry<T>?

    init(_ val: T) {
        self.value = val
    }
}
/**
 * Simple double linked list. Compared with array, it has O(1) remove operation.
 * @constructor
 */
public final class LinkedList<T> {

    var head: Entry<T>?
    var tail: Entry<T>?

    private var _len: Double = 0

    /**
     * Insert a new value at the tail
     */
    func insert(_ val: T) -> Entry<T> {
        let entry = Entry(val)
        self.insertEntry(entry)
        return entry
    }

    /**
     * Insert an entry at the tail
     */
    func insertEntry(_ entry: Entry<T>) {
        if self.head == nil {
            self.head = entry
            self.tail = entry
        }
        else {
            self.tail!.next = entry
            entry.prev = self.tail
            entry.next = nil
            self.tail = entry
        }
        self._len += 1
    }

    /**
     * Remove entry.
     */
    func remove(_ entry: Entry<T>) {
        let prev = entry.prev
        let next = entry.next
        if prev != nil {
            prev!.next = next
        }
        else {
            // Is head
            self.head = next
        }
        if next != nil {
            next!.prev = prev
        }
        else {
            // Is tail
            self.tail = prev
        }
        entry.next = nil
        entry.prev = nil
        self._len -= 1
    }

    /**
     * Get length
     */
    func len() -> Double {
        return self._len
    }

    /**
     * Clear list
     */
    func clear() {
        self.head = nil
        self.tail = nil
        self._len = 0
    }

}

/**
 * LRU Cache
 */
public final class LRU<T> {

    private let _list = LinkedList<T>()

    private var _maxSize: Double = 10

    private var _lastRemovedEntry: Entry<T>?

    private var _map: [LRUKey: Entry<T>] = [:]

    public init(_ maxSize: Double) {
        self._maxSize = maxSize
    }

    /**
     * @return Removed value
     */
    @discardableResult
    public func put(_ key: LRUKey, _ value: T) -> T? {
        let list = self._list
        // upstream aliases `const map = this._map`; Swift Dictionary is a value type,
        // so we mutate self._map directly to preserve the reference-semantics intent.
        var removed: T? = nil
        if self._map[key] == nil {
            let len = list.len()
            // Reuse last removed entry
            var entry = self._lastRemovedEntry

            if len >= self._maxSize && len > 0 {
                // Remove the least recently used
                let leastUsedEntry = list.head!
                list.remove(leastUsedEntry)
                self._map[leastUsedEntry.key] = nil

                removed = leastUsedEntry.value
                self._lastRemovedEntry = leastUsedEntry
            }

            if entry != nil {
                entry!.value = value
            }
            else {
                entry = Entry(value)
            }
            entry!.key = key
            list.insertEntry(entry!)
            self._map[key] = entry!
        }

        return removed
    }

    public func get(_ key: LRUKey) -> T? {
        let entry = self._map[key]
        let list = self._list
        if entry != nil {
            // Put the latest used entry in the tail
            if entry !== list.tail {
                list.remove(entry!)
                list.insertEntry(entry!)
            }

            return entry!.value
        }
        return nil
    }

    /**
     * Clear the cache
     */
    public func clear() {
        self._list.clear()
        self._map = [:]
    }

    public func len() -> Double {
        return self._list.len()
    }
}
