# Race animation validation

Race examples cannot be validated with the normal one-frame PNG oracle. A final frame can be correct
even when the native implementation snaps, restarts its enter animation, uses different random input, or
temporarily mounts two copies of the same element. Validate the transition as a time series instead.

## Workflow

1. **Make the stimulus deterministic.** Native and HTML must start from the same data and consume the
   same update sequence. Preserve the official cadence and value distribution, but replace independent
   random calls with one pinned sequence. A value or rank mismatch is otherwise not animation evidence.
2. **Capture matching timeline offsets.** Use a frame before the update, multiple in-flight frames, the
   nominal end frame, and at least one frame in the next cycle. Capture Native and the live HTML page in
   separate fresh processes at identical wall-clock offsets.
3. **Check structural invariants.** Across an update, datum element identity must survive, active animator
   counts must be non-zero during the transition, and custom `extra` values must move between their start
   and target values. A rank-only update must not add a second set of bars or labels.
4. **Compare by phase, not raw pixel score.** At each offset compare geometry, rank order, label value,
   easing direction, and completion. Small wall-clock skew is acceptable; a snap, restart, duplicate,
   missing tween, different trajectory, or wrong final order is not. Global pixel diff is not a reliable
   pass/fail metric because WebKit and the native display link do not start on the same millisecond.
5. **Lock the bug with unit tests.** Exercise start/middle/end values with a synthetic clock. Assert object
   identity and scene element count around action-driven updates, not only final coordinates.

Run all four race cases with:

```sh
scripts/validate-race-animation.sh
```

The command writes paired `*.native.png` / `*.web.png` frames and `invariants.txt` under
`build/race-animation-validation/<case>/`.

## Current acceptance checks

| Case | Required signal |
| --- | --- |
| `official-line-race` | line reveal follows the same path and reaches the same endpoint |
| `official-bar-race` | bar width, row movement, rolling value, and top-three membership transition together |
| `official-bar-race-country` | country/flag, bar, value, and year remain one moving datum during rank swaps |
| `official-custom-spiral-race` | polygon geometry and text are derived from the same interpolated `extra.endRadian` |

For bar races, the `changeAxisOrder` action must preserve the bar object for every category. For the
custom spiral, both the polygon and text elements must have live animators during an update and the
reported `extra.endRadian` samples must be intermediate rather than immediately equal to the target.
