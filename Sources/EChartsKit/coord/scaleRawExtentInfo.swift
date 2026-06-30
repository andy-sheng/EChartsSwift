// Ported from echarts/src/coord/scaleRawExtentInfo.ts — keep in sync with upstream
//
// PORT-TODO: the full ScaleRawExtentInfo (~857 lines: raw min/max resolution, dataMin/dataMax,
//   determineExtent, etc.) is translated in the coordinate-system phase. The scale layer only
//   STORES an optional reference to it today (Scale.rawExtentInfo) and never calls into it, so a
//   placeholder class unblocks the scale layer without faking behavior. Kept at its upstream path.

import Foundation

public final class ScaleRawExtentInfo {
    public init() {}
}
