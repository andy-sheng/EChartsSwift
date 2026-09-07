// Native-only compiled geometry cache. No CGContext or scene state is retained.
import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
import ZRenderKit

/// Owned by one painter, used on its rendering thread. Geometry is element-local: transforms,
/// clipping, colors and compositing still apply on every draw. Bounded by entries AND commands.
public final class CGGeometryCache {
    private struct Entry {
        let generation: Int
        weak var proxy: PathProxy?
        let version: Double
        let length: Double
        let percent: Double
        let threshold: VectorArray
        let commands: ContiguousArray<Double>
        let path: CGPath
    }

    private let maxEntries: Int
    private let maxCommands: Int
    private var entries: [ObjectIdentifier: Entry] = [:]
    private var order: [(key: ObjectIdentifier, generation: Int)] = []
    private var head = 0
    private var generation = 0
    private var commandCount = 0

    public init(maxEntries: Int = 2048, maxCommands: Int = 1_000_000) {
        self.maxEntries = max(0, maxEntries)
        self.maxCommands = max(0, maxCommands)
    }

    public func path(for proxy: PathProxy, percent: Double = 1) -> CGPath {
        let key = ObjectIdentifier(proxy)
        let version = proxy.getVersion()
        let length = proxy.len()
        let threshold = proxy.getRebuildPathThreshold()
        if let entry = entries[key], entry.proxy === proxy,
           entry.version == version, entry.length == length,
           entry.percent == percent, entry.threshold == threshold,
           entry.commands == proxy.data {
            return entry.path
        }

        let rebuilder = CGPathRebuilder()
        proxy.rebuildPath(rebuilder, percent)
        let path = rebuilder.path.copy()!
        // Retain the COW command buffer, not the scene object. Equality is O(1) for the unchanged
        // buffer; a direct setData/data mutation is still detected even without increaseVersion().
        let cost = proxy.data.count
        if let old = entries.removeValue(forKey: key) { commandCount -= old.commands.count }
        guard maxEntries > 0, cost <= maxCommands else { return path }
        while entries.count >= maxEntries || commandCount + cost > maxCommands {
            let oldest = order[head]
            head += 1
            if let old = entries[oldest.key], old.generation == oldest.generation {
                entries.removeValue(forKey: oldest.key)
                commandCount -= old.commands.count
            }
        }
        // Discard stale FIFO records in amortized O(1), rather than scanning on every insertion.
        if order.count > maxEntries * 2 {
            order = order[head...].filter { entries[$0.key]?.generation == $0.generation }
            head = 0
        }
        generation += 1
        entries[key] = Entry(generation: generation, proxy: proxy, version: version, length: length, percent: percent,
                             threshold: threshold, commands: proxy.data, path: path)
        order.append((key, generation))
        commandCount += cost
        return path
    }

    public func removeAll() {
        entries.removeAll()
        order.removeAll()
        head = 0
        commandCount = 0
    }
}
#endif
