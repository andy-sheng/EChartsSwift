#!/usr/bin/env python3
"""scene-diff.py — diff two scene-graph dumps produced by
   `EChartsDemoGallery --scene-native <demo> a.json` and `--scene-web <demo> b.json`.

Reports a divergence as a NAMED PROPERTY rather than a pixel percentage, e.g.
    [7] sector    z2    2 != 4
so the finding is directly greppable in the Swift source.

WHY MATCHING, NOT ZIPPING. The display list is z-sorted, so a z/z2 divergence REORDERS it — and a
naive index-zip then compares a label against a sector and buries the one real finding under dozens
of bogus ones. So elements are matched by content first; the resulting order difference is then
reported as its own finding (PAINT-ORDER), which is what a z2 bug actually is.

Sections:
  PAINT-ORDER  matched elements that occupy different positions -> z/z2 divergence, real
  DIFF         a key both sides have with different values      -> behavioural difference
  WEB-ONLY     a key only real echarts has                      -> often an unmodelled feature,
                                                                   but ALSO plain JS bag noise
  NATIVE-ONLY  a key only the Swift dump has                    -> usually port-local materialisation

Usage: scene-diff.py <native.json> <web.json> [--tol 0.5] [--all]
"""
import json, sys

# --- Keys that are structurally guaranteed to differ and carry no behavioural meaning -------------
# zrStyleMagic : the port's stand-in for upstream's dynamic STYLE_MAGIC_KEY stamp (Displayable.swift);
#                it has no JS counterpart by construction.
IGNORE_KEYS = {'zrStyleMagic'}

# --- Type-string normalisation --------------------------------------------------------------------
# util/symbol.ts:274 declares `Path.extend({type: 'symbol'})`, but Path.extend (echarts.js:12107)
# copies ONLY function-valued keys onto the subclass prototype — the string `type` is dropped, so a
# symbol's RUNTIME type upstream is 'path'. The Swift port sets `self.type = "symbol"`
# (util/symbol.swift:359), i.e. it implemented the source's stated intent rather than its actual
# behaviour. Nothing in the port branches on it today, so normalise here and report it once.
TYPE_ALIASES = {'symbol': 'path'}

TOP_KEYS = ['z', 'z2', 'zlevel', 'ignore', 'invisible', 'silent',
            'x', 'y', 'scaleX', 'scaleY', 'rotation']


def ntype(e):
    t = e.get('type', '?')
    return TYPE_ALIASES.get(t, t)


def text_of(e):
    return e.get('text') or (e.get('style') or {}).get('text') or ''


def close(a, b, tol):
    if isinstance(a, bool) or isinstance(b, bool):
        return a == b
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        return abs(a - b) <= tol
    if isinstance(a, list) and isinstance(b, list):
        return len(a) == len(b) and all(close(x, y, tol) for x, y in zip(a, b))
    return a == b


def fmt(v):
    if isinstance(v, float):
        return f'{v:g}'
    if isinstance(v, list):
        return '[' + ','.join(fmt(x) for x in v) + ']'
    return str(v)


def cost(a, b):
    """Distance between two elements for matching. Type and text are near-hard constraints; the
    rest is geometric so that two same-type elements pair with their true counterpart."""
    if ntype(a) != ntype(b):
        return 1e9
    c = 0.0
    if text_of(a) != text_of(b):
        c += 1e6
    sa, sb = a.get('shape', {}), b.get('shape', {})
    keys = (set(sa) & set(sb)) | {'x', 'y'}
    for k in keys:
        va = sa.get(k, a.get(k)) if k not in ('x', 'y') else a.get(k)
        vb = sb.get(k, b.get(k)) if k not in ('x', 'y') else b.get(k)
        if isinstance(va, (int, float)) and isinstance(vb, (int, float)) \
                and not isinstance(va, bool) and not isinstance(vb, bool):
            c += abs(va - vb)
    return c


# Above this bucket size, fall back to pairing by order within the bucket. The greedy pass is O(k^2)
# and the corpus contains charts with tens of thousands of interchangeable elements (custom-wind: 65k),
# where an all-pairs match is both intractable and pointless — those elements are homogeneous, so
# order-pairing inside a (type, text) bucket is the same answer for far less work.
GREEDY_BUCKET_LIMIT = 60


def match(nat, web):
    """Match elements by content, not by index.

    Bucketed by (normalised type, text) first: that is what makes the match stable under the
    REORDERING a z/z2 bug causes, while keeping the cost near-linear on large charts. Inside a bucket,
    small groups get a greedy nearest-neighbour pass on geometry; large homogeneous groups are paired
    in order."""
    def key(e):
        return (ntype(e), text_of(e))

    bn, bw = {}, {}
    for i, e in enumerate(nat):
        bn.setdefault(key(e), []).append(i)
    for j, e in enumerate(web):
        bw.setdefault(key(e), []).append(j)

    out, used_n, used_w = [], set(), set()
    for k, ii in bn.items():
        jj = bw.get(k)
        if not jj:
            continue
        if len(ii) <= GREEDY_BUCKET_LIMIT and len(jj) <= GREEDY_BUCKET_LIMIT:
            cand = sorted(((cost(nat[i], web[j]), i, j) for i in ii for j in jj), key=lambda t: t[0])
            for c, i, j in cand:
                if c >= 1e9 or i in used_n or j in used_w:
                    continue
                used_n.add(i); used_w.add(j); out.append((i, j))
        else:
            for i, j in zip(ii, jj):
                used_n.add(i); used_w.add(j); out.append((i, j))
    out.sort()
    unmatched_n = [i for i in range(len(nat)) if i not in used_n]
    unmatched_w = [j for j in range(len(web)) if j not in used_w]
    return out, unmatched_n, unmatched_w


def count_inversions(seq):
    """Number of out-of-order pairs in `seq`, via a Fenwick tree. The naive double loop is O(m^2) and
    the corpus has charts with tens of thousands of matched elements."""
    if not seq:
        return 0
    rank = {v: r for r, v in enumerate(sorted(set(seq)), 1)}
    n = len(rank)
    tree = [0] * (n + 1)
    inv = 0
    seen = 0
    for v in seq:
        r = rank[v]
        # count already-seen values strictly greater than r
        i, acc = r, 0
        while i > 0:
            acc += tree[i]; i -= i & -i
        inv += seen - acc
        seen += 1
        i = r
        while i <= n:
            tree[i] += 1; i += i & -i
    return inv


def diff_bag(name, a, b, tol, out, idx, et):
    ka, kb = set(a) - IGNORE_KEYS, set(b) - IGNORE_KEYS
    for k in sorted(ka & kb):
        if not close(a[k], b[k], tol):
            out['DIFF'].append((idx, et, f'{name}.{k}', fmt(a[k]), fmt(b[k])))
    for k in sorted(ka - kb):
        out['NATIVE-ONLY'].append((idx, et, f'{name}.{k}', fmt(a[k]), '-'))
    for k in sorted(kb - ka):
        out['WEB-ONLY'].append((idx, et, f'{name}.{k}', '-', fmt(b[k])))


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    tol = float(sys.argv[sys.argv.index('--tol') + 1]) if '--tol' in sys.argv else 0.5
    show_all = '--all' in sys.argv
    nat, web = json.load(open(args[0])), json.load(open(args[1]))

    print(f'native elements: {len(nat)}    web elements: {len(web)}')
    pairs, un, uw = match(nat, web)
    print(f'matched: {len(pairs)}    unmatched native: {len(un)}    unmatched web: {len(uw)}')
    for i in un:
        print(f'  NATIVE-ONLY ELEMENT [{i}] {nat[i].get("type")} «{text_of(nat[i])}»')
    for j in uw:
        print(f'  WEB-ONLY ELEMENT    [{j}] {web[j].get("type")} «{text_of(web[j])}»')

    # PAINT-ORDER: a matched pair whose relative position differs. Reported as inversions against
    # the web order, since the display list IS the paint order.
    order = [j for _, j in pairs]
    total_inv = count_inversions(order)
    # Only the first few need naming, so enumerate lazily instead of materialising every pair.
    inversions = []
    for k in range(len(order)):
        for k2 in range(k + 1, len(order)):
            if order[k] > order[k2]:
                inversions.append((pairs[k][0], pairs[k][1], pairs[k2][0], pairs[k2][1]))
                if len(inversions) >= 12:
                    break
        if len(inversions) >= 12:
            break
    print(f'\n=== PAINT-ORDER inversions: {total_inv} ===')
    for i1, j1, i2, j2 in inversions[:12]:
        print(f'  native paints [{i1}] {ntype(nat[i1])} «{text_of(nat[i1])}» BEFORE [{i2}] '
              f'{ntype(nat[i2])} «{text_of(nat[i2])}»; real echarts paints them the other way '
              f'(web [{j1}] after [{j2}])')
    if total_inv > len(inversions):
        print(f'  … {total_inv - len(inversions)} more')

    out = {'DIFF': [], 'NATIVE-ONLY': [], 'WEB-ONLY': []}
    for i, j in pairs:
        a, b = nat[i], web[j]
        et = ntype(a)
        if a.get('type') != b.get('type'):
            out['DIFF'].append((i, et, 'type', a.get('type'), b.get('type')))
        for k in TOP_KEYS:
            if k in a and k in b and not close(a[k], b[k], tol):
                out['DIFF'].append((i, et, k, fmt(a[k]), fmt(b[k])))
        diff_bag('style', a.get('style', {}), b.get('style', {}), tol, out, i, et)
        diff_bag('shape', a.get('shape', {}), b.get('shape', {}), tol, out, i, et)

    for sev in ('DIFF', 'WEB-ONLY', 'NATIVE-ONLY'):
        rows = out[sev]
        print(f'\n=== {sev}: {len(rows)} ===')
        byprop = {}
        for i, et, p, x, y in rows:
            byprop.setdefault(p, []).append((i, et, x, y))
        for p, hits in sorted(byprop.items(), key=lambda kv: -len(kv[1])):
            i, et, x, y = hits[0]
            n = len(hits)
            where = f'[{i}] {et}' + (f' (+{n-1})' if n > 1 else '')
            print(f'  {where:22} {p:26} {x:>18} != {y}')
            if show_all and n > 1:
                for i2, et2, x2, y2 in hits[1:]:
                    print(f'      [{i2}] {et2:10} {"":26} {x2:>18} != {y2}')


if __name__ == '__main__':
    main()
