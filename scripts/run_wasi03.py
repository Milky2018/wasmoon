#!/usr/bin/env python3
"""Run pinned upstream Preview 3 cases in isolated, bounded subprocesses.

Install the upstream runner's requirements in the Python environment first.
The caller supplies a checkout so no network access happens during execution.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import fnmatch
import json
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys

from native_process import kill_process_tree

PIN = "609c446139956ff30239f87cb18af1dc6128bed2"
ROOT = Path(__file__).resolve().parents[1]

def corpus_digest(name, data):
    # Git checkouts may convert JSON line endings on Windows. Normalize only
    # that text representation; guest binaries remain byte-exact.
    if name.endswith(".json"):
        data = data.replace(b"\r\n", b"\n")
    return hashlib.sha256(data).hexdigest()


def http_contract_guests(directory):
    manifest = json.loads((directory / "manifest.json").read_text())
    if manifest["upstream"] != PIN:
        raise ValueError("HTTP contract profile does not match upstream pin")
    if hashlib.sha256((directory / "expectations.patch").read_bytes()).hexdigest() != manifest["patch_sha256"]:
        raise ValueError("HTTP contract patch checksum mismatch")
    guests = {}
    for name, digest in manifest["files"].items():
        path = directory / name
        if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            raise ValueError(f"HTTP contract guest checksum mismatch: {name}")
        guests[name] = path
    if set(guests) != {"http-fields.wasm", "http-request.wasm"}:
        raise ValueError("HTTP contract profile must replace exactly two guests")
    return guests


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--http-contract-tests", action="store_true",
                   help="use the documented, patched HTTP contract guests; every test must pass")
    p.add_argument("--upstream", type=Path, required=True)
    p.add_argument("--wasmoon", type=Path, default=ROOT / "wasmoon")
    p.add_argument("--output", type=Path, required=True)
    p.add_argument("--mode", choices=["both", "jit", "interp"], default="both")
    p.add_argument("--filter", default="*")
    p.add_argument("--timeout", type=float, default=30)
    p.add_argument("--jobs", type=int, default=2)
    args = p.parse_args()
    if args.timeout <= 0 or args.jobs < 1:
        p.error("timeout and jobs must be positive")
    upstream = args.upstream.resolve()
    sha = subprocess.check_output(["git", "-C", str(upstream), "rev-parse", "HEAD"], text=True).strip()
    if sha != PIN:
        p.error(f"expected upstream {PIN}, got {sha}")
    manifest = json.loads((ROOT / "scripts/wasi03-corpus.json").read_text())
    if manifest["revision"] != PIN:
        p.error("corpus manifest revision does not match runner pin")
    suite = upstream / "tests/rust/testsuite/wasm32-wasip3"
    for name, digest in manifest["files"].items():
        # Mutable filesystem fixtures are reconstructed from the pinned commit.
        if name.startswith("fs-tests.dir/"):
            data = subprocess.check_output(["git", "-C", str(upstream), "show", f"{PIN}:tests/rust/testsuite/wasm32-wasip3/{name}"])
        else:
            data = (suite / name).read_bytes()
        if corpus_digest(name, data) != digest:
            p.error(f"upstream checksum mismatch: {name}")
    overrides = http_contract_guests(ROOT / "tests/wasi03/http-contract") if args.http_contract_tests else {}
    binary_digest = hashlib.sha256(args.wasmoon.read_bytes()).hexdigest()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    suite = upstream / "tests/rust/testsuite/wasm32-wasip3"
    cases = sorted(suite / name for name in manifest["files"] if name.endswith(".wasm") and fnmatch.fnmatch(Path(name).stem, args.filter))
    if not cases:
        p.error("no matching tests")
    engines = ["jit", "interp"] if args.mode == "both" else [args.mode]

    def run(item):
        case, engine = item
        directory = output / engine / case.stem
        directory.mkdir(parents=True)
        # Guest fixtures can contain inaccessible paths and symlinks. Keep them
        # outside the report tree consumed by artifact uploaders.
        work = output.parent / (output.name + "-work") / engine / case.stem
        work.mkdir(parents=True)
        shutil.copy(suite / "manifest.json", work)
        shutil.copy(overrides.get(case.name, case), work / case.name)
        config = case.with_suffix(".json")
        if config.exists():
            shutil.copy(config, work)
        # Preserve fixture inputs, never outputs from a prior local suite run.
        fixtures = work / "fs-tests.dir"
        fixtures.mkdir()
        for name in ["a.txt", "b.txt"]:
            content = subprocess.check_output(["git", "-C", str(upstream), "show", f"{PIN}:tests/rust/testsuite/wasm32-wasip3/fs-tests.dir/{name}"])
            (fixtures / name).write_bytes(content)
        result = directory / "upstream.json"
        cmd = [sys.executable, str(upstream / "test-runner/wasi_test_runner.py"),
               "-t", str(work), "-r", str(ROOT / "scripts/wasi03_testsuite_adapter.py"),
               "--json-output-location", str(result), "--disable-colors"]
        env = os.environ | {"WASMOON": str(args.wasmoon.resolve()), "WASI03_ENGINE": engine, "WASI03_TIMEOUT": str(args.timeout)}
        with (directory / "log.txt").open("w") as log:
            proc = subprocess.Popen(cmd, stdout=log, stderr=log, env=env, start_new_session=True)
            try:
                proc.wait(timeout=args.timeout)
            except subprocess.TimeoutExpired:
                kill_process_tree(proc)
                proc.wait()
                return {"name": case.stem, "engine": engine, "status": "timeout"}
        if not result.exists():
            return {"name": case.stem, "engine": engine, "status": "harness_error"}
        tests = json.loads(result.read_text())["results"][0]["tests"]
        if len(tests) != 1:
            return {"name": case.stem, "engine": engine, "status": "harness_error"}
        test = tests[0]
        return {"name": case.stem, "engine": engine, "status": test["outcome"], "failures": test["failures"]}

    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        results = list(pool.map(run, [(case, engine) for case in cases for engine in engines]))
    if hashlib.sha256(args.wasmoon.read_bytes()).hexdigest() != binary_digest:
        p.error("runtime binary changed during acceptance run")
    for result in results:
        result["guest_source"] = "http-contract" if result["name"] + ".wasm" in overrides else "upstream"
    counts = {status: sum(r["status"] == status for r in results) for status in sorted({r["status"] for r in results})}
    (output / "summary.json").write_text(json.dumps({"upstream": sha, "binary_sha256": binary_digest, "profile": "http-contract" if args.http_contract_tests else "upstream", "guest_overrides": {name: hashlib.sha256(path.read_bytes()).hexdigest() for name, path in overrides.items()}, "counts": counts, "results": results}, indent=2) + "\n")
    for r in results:
        print(r["engine"], r["status"], r["name"])
        if r["status"] != "pass":
            for failure in r.get("failures", []):
                print(failure)
    print(json.dumps(counts))
    return int(any(r["status"] != "pass" for r in results))


if __name__ == "__main__":
    sys.exit(main())
