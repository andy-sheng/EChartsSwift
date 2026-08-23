#!/usr/bin/env python3
"""Build a visual-agent review request for captured interaction frames."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("scenario", type=Path)
    parser.add_argument("case_root", type=Path)
    args = parser.parse_args()

    scenario = json.loads(args.scenario.read_text())
    captures = [step["capture"] for step in scenario["steps"] if step.get("capture")]
    frames = args.case_root / "frames"
    image_paths: dict[str, list[str]] = {"native": [], "web": []}

    for index, label in enumerate(captures):
        for side in ("native", "web"):
            matches = sorted((frames / side).glob(f"{index:02d}-*.{side}.png"))
            if len(matches) != 1:
                raise SystemExit(f"expected one {side} capture for {index:02d}-{label}, got {len(matches)}")
            image_paths[side].append(str(matches[0].resolve()))

    contact_path = args.case_root / "contact.png"
    if not contact_path.exists():
        raise SystemExit(f"contact sheet not found: {contact_path}")
    request = {
        "case": scenario["id"],
        "demo": scenario["demo"],
        "task": "Review the rendered chart pixels after the declared interaction sequence.",
        "rules": [
            "Judge visible chart semantics; do not require pixel-perfect Native/Web identity.",
            "Use the original per-side PNGs to confirm any detail that is unclear in the contact sheet.",
            "Return uncertain instead of guessing when a label or marker cannot be read reliably.",
        ],
        "checks": scenario.get("checks", []),
        "images": {
            "contact": str(contact_path.resolve()),
            **image_paths,
        },
        "expectedOutput": {
            "case": scenario["id"],
            "status": "pass | fail | uncertain",
            "missingLabels": ["string"],
            "nativeVsWeb": "short visual comparison",
            "notes": ["short observation"],
            "evidenceImages": ["absolute path"],
        },
    }
    request_path = args.case_root / "review-request.json"
    request_path.write_text(json.dumps(request, indent=2, ensure_ascii=False) + "\n")
    print(contact_path)
    print(request_path)


if __name__ == "__main__":
    main()
