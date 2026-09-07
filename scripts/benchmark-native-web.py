#!/usr/bin/env python3
"""Run serialized fixed-input Native/Web CPU probes, preserving raw evidence and semantic gates.

Build: swift build -c release --product ChartPerformanceProbe
Run: python3 scripts/benchmark-native-web.py --binary .build/release/ChartPerformanceProbe --output build/perf-run
Optional --baseline-binary compares an earlier Release binary on the same machine.
This measures submitted CPU work, not displayed frames, GPU completion or input-to-present latency.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import statistics
import subprocess

ROOT = Path(__file__).resolve().parent.parent
DEMOS = ["official-scatter-large", "official-bar-large", "official-candlestick-sh-2015"]


def percentile(values, fraction):
    values = sorted(values)
    index = (len(values) - 1) * fraction
    lo, hi = math.floor(index), math.ceil(index)
    return values[lo] + (values[hi] - values[lo]) * (index - lo)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--binary", type=Path, required=True)
    parser.add_argument("--baseline-binary", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--repeats", type=int, default=2)
    args = parser.parse_args()
    if args.repeats < 1:
        parser.error("--repeats must be positive")
    args.output.mkdir(parents=True, exist_ok=False)
    variants = {"native": args.binary.resolve(), "web": args.binary.resolve()}
    if args.baseline_binary:
        variants = {"before": args.baseline_binary.resolve(), **variants}
    results = {}
    reference = {}
    for demo in DEMOS:
        results[demo] = {}
        for repeat in range(args.repeats):
            for variant, binary in variants.items():
                stem = args.output / f"{demo}-{variant}-{repeat + 1}"
                with stem.with_suffix(".jsonl").open("w") as stdout, stem.with_suffix(".stderr").open("w") as stderr:
                    subprocess.run([str(binary), demo, "web" if variant == "web" else "native"],
                                   cwd=ROOT, stdout=stdout, stderr=stderr, check=True, timeout=240)
                records = [json.loads(line) for line in stem.with_suffix(".jsonl").read_text().splitlines() if line.startswith("{")]
                wheel = [r for r in records if r.get("phase") == "wheel"]
                if [r.get("i") for r in wheel] != list(range(5)):
                    raise RuntimeError(f"Incomplete wheel run: {stem}")
                for r in wheel:
                    key = (demo, r["i"])
                    # Native currently appends toolbox dataZoom models. Compare the two authored
                    # inside/slider controls, and ALL series counts; do not claim whole-option parity.
                    state = (r["dataCounts"], r["ranges"][:2])
                    expected = reference.setdefault(key, state)
                    if state[0] != expected[0] or len(state[1]) != len(expected[1]) or any(
                        not math.isclose(a, b, rel_tol=0, abs_tol=1e-8)
                        for actual, wanted in zip(state[1], expected[1]) for a, b in zip(actual, wanted)
                    ):
                        raise RuntimeError(f"Semantic mismatch: {stem}, wheel {r['i']}")
                results[demo].setdefault(variant, []).extend(records)
                print(f"{demo} {variant} run {repeat + 1}: {statistics.median(r['eventMs'] + r['flushMs'] for r in wheel):.2f} ms", flush=True)
    summary = {"metric": "submitted-cpu-ms", "semanticGate": "all-series-counts-and-two-authored-zoom-ranges",
               "repeats": args.repeats, "samplesPerRun": 5, "presentationLatencyMeasured": False,
               "head": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(), "cases": {}}
    summary["binaries"] = {name: {"path": str(path), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
                           for name, path in variants.items()}
    summary["upstream"] = {name: subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT / "upstream" / name, text=True).strip()
                           for name in ["echarts", "zrender"]}
    for demo, variants in results.items():
        summary["cases"][demo] = {}
        for variant, records in variants.items():
            wheel = [r for r in records if r.get("phase") == "wheel"]
            total = [r["eventMs"] + r["flushMs"] for r in wheel]
            summary["cases"][demo][variant] = {
                "wheelP50": statistics.median(total), "wheelP95": percentile(total, 0.95),
                "eventP50": statistics.median(r["eventMs"] for r in wheel),
                "paintP50": statistics.median(sum(r["paintMs"]) for r in wheel),
                "repaintP50": statistics.median(r["ms"] for r in records if r.get("phase") == "repaint")}
    (args.output / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")


if __name__ == "__main__":
    main()
