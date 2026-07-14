// PortStub.swift — the inventory of knowingly-unimplemented behaviour, and the thing that makes it
// impossible to forget.
//
// WHY THIS EXISTS
//
// This port's most expensive bugs were not missing files. They were empty function BODIES inside
// files marked ported:
//
//   - `registerSubTypeDefaulter` was a no-op, so echarts' "an axis carrying `data` IS a category
//     axis" rule never ran. Every type-less axis silently became a value axis: a plausible chart,
//     not a broken one. Nothing crashed, no test went red, and it survived until an official example
//     that omits `xAxis.type` was rendered next to real echarts.
//   - `saveOldStyle` was a no-op, so cross-series transitions animated from the wrong style.
//   - `lifecycle` was skipped because "nothing listens to it" — and nothing listened to it because
//     `universalTransition`, the listener, was skipped too. Each gap justified the other.
//
// A stub that CRASHES is harmless: it announces itself on day one and gets fixed. A stub that
// silently degrades can live for a year, because everything downstream looks fine. This file exists
// to convert the second kind into the first — not by crashing (these stubs are on hot paths that run
// on every chart), but by making every hit LOUD and, above all, ENUMERABLE:
//
//   - DEBUG builds log each stub the first time it is hit.
//   - `PortStub.hits` is the machine-readable answer to "which unimplemented behaviour did this chart
//     actually depend on?" — `EChartsDemoGallery --port-stubs` renders every demo and reports exactly
//     which demos are silently degraded, and by what.
//
// The rule that follows: a knowingly-empty body MUST call `PortStub.hit`. A comment saying "no-op
// stub" is not an inventory — three such comments were stale (the behaviour had since been
// implemented) and one was simply wrong (`Element.traverse` is empty UPSTREAM TOO — faithful, not a
// gap). `scripts/check-port-stubs.sh` enforces the rule so the inventory cannot rot again.

import Foundation

public enum PortStub {

    /// One knowingly-unimplemented behaviour, and what a caller silently gets instead.
    public struct Gap: Hashable, Sendable {
        /// Stable id, `<file>.<symbol>` — what a report and an allowlist key on.
        public let id: String
        /// What upstream does here, and what we do instead. Written for whoever hits it in a report,
        /// not for whoever wrote the stub.
        public let consequence: String
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _hits: [Gap: Int] = [:]
    nonisolated(unsafe) private static var _logged: Set<String> = []

    /// Call from the empty body. Records the hit; in DEBUG, logs it once per id.
    public static func hit(_ id: String, _ consequence: String) {
        let gap = Gap(id: id, consequence: consequence)
        lock.lock()
        _hits[gap, default: 0] += 1
        let firstTime = _logged.insert(id).inserted
        lock.unlock()
        #if DEBUG
        if firstTime {
            FileHandle.standardError.write(Data("[PORT-STUB] \(id) — \(consequence)\n".utf8))
        }
        #endif
    }

    /// Every stub hit since the last `reset()`, with hit counts. The sweep reports this per demo.
    public static var hits: [Gap: Int] {
        lock.lock(); defer { lock.unlock() }
        return _hits
    }

    /// Start a fresh measurement (the sweep resets between demos to attribute hits to one demo).
    public static func reset() {
        lock.lock(); defer { lock.unlock() }
        _hits = [:]
        _logged = []
    }
}
