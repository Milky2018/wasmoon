#!/usr/bin/env python3
"""Execute Core WAST using the same interpreter hosted on native and wasm."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = "modules/wasmoon_runtime/cmd/core-wast"


def run(command, **kwargs):
    return subprocess.run(command, cwd=ROOT, text=True, capture_output=True, **kwargs)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target", choices=["native", "wasm", "both"], default="both")
    parser.add_argument("--output", type=Path, default=ROOT / "target/portable-core-wast.json")
    parser.add_argument("--timeout", type=int, default=60)
    parser.add_argument("files", nargs="*", type=Path)
    args = parser.parse_args()
    files = [ROOT / p for p in args.files] if args.files else sorted((ROOT / "tests/upstream/core-spec").rglob("*.wast"))
    if not files:
        parser.error("no WAST files selected")
    targets = ["native", "wasm"] if args.target == "both" else [args.target]
    report = {
        "source_revision": run(["git", "rev-parse", "HEAD"]).stdout.strip(),
        "source_dirty": bool(run(["git", "status", "--porcelain"]).stdout.strip()),
        "moon": run(["moon", "version", "--all"]).stdout.strip(),
        "moonrun": run(["moonrun", "--version"]).stdout.strip(),
        "targets": {},
    }
    failed = False
    for target in targets:
        build = ROOT / "target/portable-interpreter"
        result = run(["moon", "build", PACKAGE, "--release", "--target", target,
                      "--target-dir", str(build), "--warn-list", "+73", "--deny-warn"])
        if result.returncode:
            sys.stderr.write(result.stdout + result.stderr)
            return result.returncode
        extension = ".wasm" if target == "wasm" else ".exe"
        artifact = build / target / "release/build/Milky2018/wasmoon_runtime/cmd/core-wast" / ("core-wast" + extension)
        prefix = ["moonrun", str(artifact), "--"] if target == "wasm" else [str(artifact)]
        entries = []
        for path in files:
            start = time.monotonic()
            entry = {"file": str(path.relative_to(ROOT)), "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}
            try:
                result = run([*prefix, str(path)], timeout=args.timeout)
                text = result.stdout + result.stderr
                counts = {key.lower(): int(value) for key, value in re.findall(r"^(Passed|Failed|Unsupported): (\d+)$", text, re.M)}
                entry.update(counts, exit_code=result.returncode)
                accepted = counts.keys() == {"passed", "failed", "unsupported"} and counts["failed"] == 0 and counts["unsupported"] == 0 and result.returncode == 0
                entry["accepted"] = accepted
                if not accepted:
                    entry["diagnostic"] = text
                    print(f"{target} {entry['file']}: {text}", file=sys.stderr, flush=True)
            except subprocess.TimeoutExpired:
                entry.update(accepted=False, diagnostic=f"timeout after {args.timeout}s")
                print(f"{target} {entry['file']}: timeout", file=sys.stderr, flush=True)
            entry["seconds"] = round(time.monotonic() - start, 6)
            entries.append(entry)
        summary = {
            "artifact_sha256": hashlib.sha256(artifact.read_bytes()).hexdigest(),
            "files": len(entries), "accepted_files": sum(e["accepted"] for e in entries),
            "passed": sum(e.get("passed", 0) for e in entries),
            "failed": sum(e.get("failed", 0) for e in entries),
            "unsupported": sum(e.get("unsupported", 0) for e in entries),
            "entries": entries,
        }
        report["targets"][target] = summary
        failed |= summary["accepted_files"] != len(entries)
        print(f"{target}: {summary['accepted_files']}/{len(entries)} files, {summary['passed']} passed, {summary['failed']} failed, {summary['unsupported']} unsupported", flush=True)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2) + "\n")
    return int(failed)


if __name__ == "__main__":
    raise SystemExit(main())
