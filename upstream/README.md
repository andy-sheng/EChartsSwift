# upstream/ — read-only reference checkouts

These are the **exact upstream sources** the Swift port mirrors. They exist so every
`// Ported from <path> — keep in sync with upstream` header in `Sources/` has a real,
local file to diff against, and so the golden fixtures can be regenerated from the same
version that was translated.

**Do not edit anything under `upstream/`.** It is reference only and is not part of the
SwiftPM build (SwiftPM globs `Sources/<target>/**`).

## Pinned versions (match the port + golden fixtures)

The single source of truth for *which commit* the Swift port mirrors is
[`upstream.lock`](./upstream.lock) — exact commit SHAs, consumed by the sync script.
The checkouts under `upstream/echarts` and `upstream/zrender` are **not committed**
(see root `.gitignore`); reconstruct them from the lock with `scripts/sync-upstream.sh`.

| repo | version | commit | date |
|------|---------|--------|------|
| [apache/echarts](https://github.com/apache/echarts) | 6.1.0 | `20ecdf4cae568f31d350a1c547516d08cdcab9b0` | 2026-05-31 |
| [ecomfe/zrender](https://github.com/ecomfe/zrender) | 6.1.0 | `349111033fba0fa08cee745b72dd2ea66dc6fcaa` | 2026-05-26 |

The `Oracle/` golden fixtures were generated from echarts **6.1.0** (see
`Oracle/fixtures/*.json` → `"echartsVersion": "6.1.0"`), so these pinned commits are the
authoritative source-of-truth for the current port.

### Reconstruct / verify the checkouts

```sh
scripts/sync-upstream.sh           # clone/fetch each repo to the locked SHA + pull echarts dist
scripts/sync-upstream.sh --check   # verify working checkouts still match upstream.lock (CI-friendly)
```

> Why a lock + script instead of git submodules? The project isn't a git repo yet, and a
> submodule cannot carry echarts' prebuilt `dist/echarts.js` (echarts gitignores its own
> `dist/`), which `Oracle/dump-displaylist.js` needs. The script checks out the exact source
> SHA *and* pulls the matching prebuilt dist from the npm CDN. Once the project is `git init`-ed,
> this can be upgraded to submodules if preferred.

## Path mapping

| upstream | Swift target |
|----------|--------------|
| `upstream/zrender/src/core/*.ts` | `Sources/ZRenderKit/Core/*.swift` |
| `upstream/zrender/src/graphic/*.ts` | `Sources/ZRenderKit/Graphic/*.swift` |
| `upstream/zrender/src/graphic/shape/*.ts` | `Sources/ZRenderKit/Graphic/Shape/*.swift` |
| `upstream/zrender/src/{canvas,svg}/Painter.ts` | *not translated* → `Sources/NativePainter/` (fresh CG/CA backend) |
| `upstream/echarts/src/**` | `Sources/EChartsKit/**` (later phases) |

## Re-syncing / bumping upstream

1. Edit [`upstream.lock`](./upstream.lock): set the new commit SHA (+ version) for the repo(s).
2. `scripts/sync-upstream.sh` — checks out the new SHAs and pulls the matching echarts dist.
3. Diff to see what changed upstream, then apply the same change to the Swift mirror:
   `git -C upstream/zrender diff <old-sha>..<new-sha> -- src/<file>.ts`
4. Regenerate golden fixtures from the new version:
   `cd Oracle && ECHARTS_DIST=../upstream/echarts/dist/echarts.js node dump-displaylist.js`
5. `swift test` must stay green (rebuilt `d` byte-for-byte vs the oracle).
6. Update the pinned-versions table above (or just point readers at `upstream.lock`).
