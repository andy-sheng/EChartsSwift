// Ported from zrender/src/graphic/CompoundPath.ts — keep in sync with upstream

// CompoundPath to improve performance

// upstream imports (resolved to the ported modules):
// import Path from './Path';
// import PathProxy from '../core/PathProxy';

// upstream: export interface CompoundPathShape { paths: Path[] }
//   Modeled as a struct conforming to the `PathShape` existential marker (see Path.swift's
//   GENERICS DECISION). `paths` holds the sub-`Path`s concatenated into one buildPath.
public struct CompoundPathShape: PathShape {
    public var paths: [Path] = []
    public init() {}
    public init(paths: [Path]) { self.paths = paths }
}

// upstream: export default class CompoundPath extends Path
public final class CompoundPath: Path {

    // upstream: type = 'compound'  /  shape: CompoundPathShape
    public override init(_ opts: ElementProps? = nil) {
        super.init(opts)
        self.type = "compound"
    }

    // PORT-NOTE: upstream `CompoundPath` declares `shape: CompoundPathShape` but no `getDefaultShape`,
    //   relying on `shape.paths` being supplied via constructor opts (with `|| []` fallbacks below).
    //   The typed-existential model (Path.swift) needs a concrete default so `self.shape as! …`
    //   never traps; we default to an empty `CompoundPathShape`.
    public override func getDefaultShape() -> PathShape {
        return CompoundPathShape()
    }

    private func _updatePathDirty() {
        let paths = (self.shape as! CompoundPathShape).paths
        var dirtyPath = self.shapeChanged()
        for i in 0..<paths.count {
            // Mark as dirty if any subpath is dirty
            dirtyPath = dirtyPath || paths[i].shapeChanged()
        }
        if dirtyPath {
            self.dirtyShape()
        }
    }

    // PORT-NOTE: upstream signature `beforeBrush()` takes no args; the Swift base
    //   `Displayable.beforeBrush(_ param: BeforeBrushParam)` carries the param, so we override with
    //   it and ignore `param`.
    public override func beforeBrush(_ param: BeforeBrushParam) {
        self._updatePathDirty()
        let paths = (self.shape as? CompoundPathShape)?.paths ?? []
        let scale = self.getGlobalScale()
        // Update path scale
        for i in 0..<paths.count {
            if paths[i].path == nil {
                paths[i].createPathProxy()
            }
            paths[i].path.setScale(scale[0], scale[1], paths[i].segmentIgnoreThreshold)
        }
    }

    // PORT-NOTE: upstream signature `buildPath(ctx, shape)` omits the `inBatch` arg; the Swift base
    //   `Path.buildPath(_ ctx, _ shape, _ inBatch)` carries it, so we override with the full arity.
    public override func buildPath(_ ctx: PathProxy, _ shape: PathShape, _ inBatch: Bool) {
        let shape = shape as! CompoundPathShape
        let paths = shape.paths  // upstream: shape.paths || []
        for i in 0..<paths.count {
            paths[i].buildPath(ctx, paths[i].shape, true)
        }
    }

    public override func afterBrush() {
        let paths = (self.shape as? CompoundPathShape)?.paths ?? []
        for i in 0..<paths.count {
            paths[i].pathUpdated()
        }
    }

    public override func getBoundingRect() -> BoundingRect? {
        // upstream: this._updatePathDirty.call(this)
        self._updatePathDirty()
        // upstream: return Path.prototype.getBoundingRect.call(this)
        return super.getBoundingRect()
    }
}

// upstream: export default CompoundPath;
