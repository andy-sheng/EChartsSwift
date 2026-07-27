#!/usr/bin/env python3
"""scene-sweep-report.py — rank a whole structural sweep produced by
   `--scene-sweep-native` + `--scene-sweep-web`.

The point of the report is the DELTA, not the absolute score: slot 0 is the untouched initial render
and slot N is the state after the Nth derived action. A demo whose slot 0 matches but whose slot N
diverges is an INTERACTION REGRESSION — the class that a frame-0 structural diff and a pixel oracle
both score as clean, because the bug does not exist until the user touches the chart.

Usage: scene-sweep-report.py <sweepdir> <manifest.json> [--top 30]
"""
import json, os, sys, importlib.util

HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location('scenediff', os.path.join(HERE, 'scene-diff.py'))
sd = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(sd)

TOL = 0.5


def score(nat, web):
    """Structural badness of one (native, web) pair, decomposed so the report can say WHY."""
    pairs, un, uw = sd.match(nat, web)
    inversions = sd.count_inversions([j for _, j in pairs])
    props = {}
    for i, j in pairs:
        a, b = nat[i], web[j]
        for k in sd.TOP_KEYS:
            if k in a and k in b and not sd.close(a[k], b[k], TOL):
                props[k] = props.get(k, 0) + 1
        for bagname in ('style', 'shape'):
            ba, bb = a.get(bagname, {}), b.get(bagname, {})
            for k in (set(ba) & set(bb)) - sd.IGNORE_KEYS:
                if not sd.close(ba[k], bb[k], TOL):
                    key = f'{bagname}.{k}'
                    props[key] = props.get(key, 0) + 1
    return {
        'n_native': len(nat), 'n_web': len(web),
        'unmatched': len(un) + len(uw),
        'inversions': inversions,
        'diff_props': props,
        # Element-count mismatch is weighted hardest: it means one side is drawing things the other
        # is not (a phantom ribbon, a missing arc), which is a data-level error, not a styling one.
        'bad': 6 * abs(len(nat) - len(web)) + 3 * (len(un) + len(uw)) + min(inversions, 20) + len(props),
    }


def load(path):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return None


def main():
    sweep, manifest_path = sys.argv[1], sys.argv[2]
    top = int(sys.argv[sys.argv.index('--top') + 1]) if '--top' in sys.argv else 30
    manifest = json.load(open(manifest_path))

    rows, missing, crashed = [], [], []
    for demo, actions in sorted(manifest.items()):
        for slot in range(len(actions) + 1):
            n = load(os.path.join(sweep, f'{demo}##{slot}.native.json'))
            w = load(os.path.join(sweep, f'{demo}##{slot}.web.json'))
            if n is None and os.path.exists(os.path.join(sweep, f'{demo}##{slot}.native.json.skip')):
                crashed.append((demo, slot, actions[slot - 1] if slot else None)); continue
            if n is None or w is None:
                missing.append(f'{demo}##{slot}'); continue
            s = score(n, w)
            s['demo'], s['slot'] = demo, slot
            s['action'] = actions[slot - 1] if slot else None
            rows.append(s)

    by = {}
    for r in rows:
        by.setdefault(r['demo'], {})[r['slot']] = r

    print(f'slots compared: {len(rows)}   crashed(native): {len(crashed)}   missing: {len(missing)}\n')

    if crashed:
        print('=== NATIVE HARD CRASH on the action (no dump produced) ===')
        for demo, slot, act in crashed:
            print(f'  {demo}##{slot}   {json.dumps(act, ensure_ascii=False) if act else "(base render)"}')
        print()

    # THE headline: slot 0 clean, slot N not.
    regressions = []
    for demo, slots in by.items():
        base = slots.get(0)
        if base is None:
            continue
        for slot, r in slots.items():
            if slot == 0:
                continue
            delta = r['bad'] - base['bad']
            if delta > 0:
                regressions.append((delta, base, r))
    regressions.sort(key=lambda t: -t[0])

    print(f'=== INTERACTION REGRESSIONS (slot 0 fine, action makes it worse): '
          f'{len(regressions)} of {sum(len(s) - 1 for s in by.values())} action slots ===')
    for delta, base, r in regressions[:top]:
        act = json.dumps(r['action'], ensure_ascii=False)
        print(f'  +{delta:<4} {r["demo"]}##{r["slot"]}  {act}')
        print(f'          base: els {base["n_native"]}/{base["n_web"]} unmatched={base["unmatched"]} '
              f'inv={base["inversions"]} props={len(base["diff_props"])}')
        print(f'          after: els {r["n_native"]}/{r["n_web"]} unmatched={r["unmatched"]} '
              f'inv={r["inversions"]} props={len(r["diff_props"])}'
              + (f'  top-props={sorted(r["diff_props"], key=r["diff_props"].get, reverse=True)[:4]}'
                 if r['diff_props'] else ''))
    if len(regressions) > top:
        print(f'  … {len(regressions) - top} more')

    # Element-count mismatch after an action is the sharpest single signal: one side draws elements
    # the other does not.
    print(f'\n=== ACTION SLOTS WITH ELEMENT-COUNT MISMATCH ===')
    cnt = [r for r in rows if r['slot'] > 0 and r['n_native'] != r['n_web']]
    cnt.sort(key=lambda r: -abs(r['n_native'] - r['n_web']))
    for r in cnt[:top]:
        base = by[r['demo']].get(0)
        bs = f'{base["n_native"]}/{base["n_web"]}' if base else '?'
        print(f'  {r["demo"]}##{r["slot"]}  native {r["n_native"]} vs web {r["n_web"]}   (base {bs})'
              f'   {json.dumps(r["action"], ensure_ascii=False)}')
    print(f'  total: {len(cnt)}')

    # Baseline health, for reference — this is what the frame-0 diff alone would have reported.
    base_bad = sorted([r for r in rows if r['slot'] == 0], key=lambda r: -r['bad'])
    clean0 = sum(1 for r in rows if r['slot'] == 0 and r['bad'] == 0)
    print(f'\n=== BASELINE (slot 0) for reference: {clean0}/{sum(1 for r in rows if r["slot"] == 0)} '
          f'structurally identical ===')
    for r in base_bad[:10]:
        print(f'  bad={r["bad"]:<5} {r["demo"]}  els {r["n_native"]}/{r["n_web"]} '
              f'unmatched={r["unmatched"]} inv={r["inversions"]} props={len(r["diff_props"])}')


if __name__ == '__main__':
    main()
