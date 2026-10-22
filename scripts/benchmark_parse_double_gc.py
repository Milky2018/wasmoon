#!/usr/bin/env python3
"""Compare the pinned Core parse_double property without host or moonrun imports.

Build Core 7547b846d38de3efa5509cb1b74ffb7ed9a4a3d1's internal/strconv
wasm-gc tests first, then pass strconv.blackbox_test.wasm via --artifact.
Every timed invocation uses the same self-checking guest and a cold cache.
Scratch fixtures and caches are removed even when an engine fails.
"""
import argparse
import hashlib
import json
import os
import platform
from pathlib import Path
import re
import statistics
import subprocess
import tempfile
import time

try:
    import resource
except ImportError:
    resource = None

CORE_REVISION = "7547b846d38de3efa5509cb1b74ffb7ed9a4a3d1"
TEST_SYMBOL = "____test__646f75626c655f717569636b636865636b5f746573742e6d6274__0"


def isolate_property(wat, count):
    match = re.search(r"^  \(func (\$\S*" + TEST_SYMBOL + r") \(;", wat, re.M)
    if not match:
        raise ValueError("pinned parse_double property was not found")
    symbol = match[1]
    start = match.start()
    end = wat.index("\n  )", start) + 4
    body = wat[start:end]
    if body.count("i32.const 20000") != 1:
        raise ValueError("unexpected property iteration count")
    wat = wat[:start] + body.replace("i32.const 20000", f"i32.const {count}") + wat[end:]

    def stub(match):
        form = match[1]
        if form.startswith("(func "):
            return "  " + form[:-1] + " unreachable)"
        if form.startswith("(tag "):
            return "  " + form
        raise ValueError("unexpected import: " + form)

    wat = re.sub(r'^  \(import "[^"]*" "[^"]*" (\(.*\))\)$', stub, wat, flags=re.M)
    if "(import " in wat:
        raise ValueError("the property still has imports")
    # Retain start, indices and assertions; return true only for the Ok variant.
    wrapper = (f'\n  (func (export "probe") (result i32) call {symbol}'
               ' struct.get $moonbit.enum 0 i32.const 1 i32.eq)\n')
    return wat.rstrip()[:-1] + wrapper + ")\n"


def cpu_time():
    if resource is None:
        return None
    return resource.getrusage(resource.RUSAGE_CHILDREN).ru_utime


def measure(command, env, timeout):
    cpu_before = cpu_time()
    start = time.perf_counter()
    result = subprocess.run(command, env=env, capture_output=True, text=True,
                            timeout=timeout, check=True)
    wall = time.perf_counter() - start
    cpu_after = cpu_time()
    if result.stdout.strip() != "1":
        raise RuntimeError(f"property failed: {result.stdout!r} {result.stderr!r}")
    return {"wall_seconds": wall,
            "user_cpu_seconds": None if cpu_before is None else cpu_after - cpu_before,
            "result": 1}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--artifact", required=True, type=Path)
    parser.add_argument("--wasmoon", required=True, type=Path)
    parser.add_argument("--baseline", type=Path)
    parser.add_argument("--wasmtime", default="wasmtime")
    parser.add_argument("--count", type=int, choices=[1000, 20000], default=20000)
    parser.add_argument("--samples", type=int, default=3)
    parser.add_argument("--timeout", type=float, default=300)
    args = parser.parse_args()
    if args.samples < 1 or args.timeout <= 0:
        parser.error("samples and timeout must be positive")
    source = args.artifact.read_bytes()
    wat = subprocess.check_output(["wasm-tools", "print", str(args.artifact)], text=True)
    binaries = {"wasmoon": args.wasmoon.resolve()}
    if args.baseline:
        binaries["baseline"] = args.baseline.resolve()
    report = {"expected_core_revision": CORE_REVISION,
              "platform": platform.platform(), "machine": platform.machine(),
              "wasmtime_version": subprocess.check_output([args.wasmtime, "--version"], text=True).strip(),
              "wasm_tools_version": subprocess.check_output(["wasm-tools", "--version"], text=True).strip(),
              "artifact_sha256": hashlib.sha256(source).hexdigest(),
              "count": args.count, "samples": [],
              "wasmoon_binary_sha256": {key: hashlib.sha256(path.read_bytes()).hexdigest()
                                         for key, path in binaries.items()}}
    env = os.environ.copy()
    # These diagnostic checks materially change throughput. Never compare a
    # verification build with an ordinary reference run by accident.
    for name in ("WASMOON_GC_VERIFY", "WASMOON_GC_ASSERT_BARRIER",
                 "VCODE_REGALLOC_VALIDATION", "WASMOON_PERF",
                 "WASMOON_RUN_METRICS_FILE"):
        env.pop(name, None)
    with tempfile.TemporaryDirectory(prefix="wasmoon-parse-double-") as directory:
        scratch = Path(directory)
        text = scratch / "probe.wat"
        text.write_text(isolate_property(wat, args.count))
        fixture = scratch / "probe.wasm"
        subprocess.run(["wasm-tools", "parse", str(text), "-o", str(fixture)], check=True)
        subprocess.run(["wasm-tools", "validate", str(fixture)], check=True)
        report["probe_sha256"] = hashlib.sha256(fixture.read_bytes()).hexdigest()
        for index in range(args.samples):
            engines = ["wasmtime", *binaries]
            if index % 2:
                engines.reverse()
            for engine in engines:
                with tempfile.TemporaryDirectory(dir=scratch, prefix="cache-") as cache:
                    env["WASMOON_JIT_CACHE_DIR"] = cache
                    command = ([args.wasmtime, "run", "-C", "parallel-compilation=n",
                                "-C", "cache=n", "--invoke", "probe", str(fixture)]
                               if engine == "wasmtime" else
                               [str(binaries[engine]), "run", "--invoke", "probe", str(fixture)])
                    report["samples"].append({"engine": engine, "sample": index,
                                              **measure(command, env, args.timeout)})
    report["median"] = {}
    for engine in ["wasmtime", *binaries]:
        rows = [row for row in report["samples"] if row["engine"] == engine]
        report["median"][engine] = {
            "wall_seconds": statistics.median(row["wall_seconds"] for row in rows),
            "user_cpu_seconds": None if resource is None else statistics.median(
                row["user_cpu_seconds"] for row in rows),
        }
    reference = report["median"]["wasmtime"]
    for row in report["median"].values():
        row["wall_ratio"] = row["wall_seconds"] / reference["wall_seconds"]
        row["user_cpu_ratio"] = (None if resource is None else
                                 row["user_cpu_seconds"] / reference["user_cpu_seconds"])
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
