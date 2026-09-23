#!/usr/bin/env python3
"""Build one declaratively instrumented test closure against current sources."""
from pathlib import Path
import hashlib
import json
import os
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "target" / "sanitizers"
PACKAGE = OUT / "package"


def run(command, *, log, env=None, expected_failure=False):
    with log.open("w") as output:
        result = subprocess.run(command, cwd=PACKAGE, env=env,
                                stdout=output, stderr=subprocess.STDOUT)
    if (result.returncode != 0) != expected_failure:
        raise RuntimeError(f"Unexpected exit {result.returncode}: {log}")
    return log.read_text()


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    if PACKAGE.exists():
        shutil.rmtree(PACKAGE)
    shutil.copytree(ROOT / "tools" / "sanitizer", PACKAGE)
    fixtures = ROOT / "modules" / "wasmoon" / "sanitizer_testsuite"
    for source in fixtures.glob("*_test.mbt"):
        shutil.copy2(source, PACKAGE / source.name)
    bounds = ROOT / "modules/wasmoon_jit/host_io/wasi/bounds_test.mbt"
    (PACKAGE / "native_bounds_test.mbt").write_text(
        bounds.read_text().replace("@wasi.", "@native_host."))
    resolver = ROOT / "modules/wasmoon_jit/host_io/wasi/resolver_test.mbt"
    (PACKAGE / "resolver_test.mbt").write_text(
        resolver.read_text().replace("@wasi.", "@native_host."))
    fixture_dir = PACKAGE / "testsuite" / "fixtures"
    fixture_dir.mkdir(parents=True)
    shutil.copy2(ROOT / "modules/wasmoon/testsuite/fixtures/wasi-command-async-stdin.component.wat",
                 fixture_dir)
    manifest = (ROOT / "modules/wasmoon/moon.mod").read_text()
    version = re.search(r'^version = "([^"]+)"', manifest, re.M)[1]
    manifest = manifest.replace('name = "Milky2018/wasmoon"',
                                'name = "Milky2018/wasmoon_sanitizer"')
    manifest = manifest.replace('import {',
                                f'import {{\n  "Milky2018/wasmoon@{version}",', 1)
    (PACKAGE / "moon.mod").write_text(manifest)
    members = re.findall(r'"(\./modules/[^"]+)"', (ROOT / "moon.work").read_text())
    # Instrument native stubs through supported package configuration in an
    # isolated source workspace; never intercept compiler commands.
    sources = OUT / "sources"
    if sources.exists():
        shutil.rmtree(sources)
    sources.mkdir()
    workspace = []
    for member in members:
        original = ROOT / member
        destination = sources / original.name
        shutil.copytree(original, destination, ignore=shutil.ignore_patterns(
            "_build", "target", ".mooncakes", ".git"))
        for config in destination.rglob("moon.pkg"):
            text = config.read_text()
            if '"native-stub"' not in text:
                continue
            if "link:" in text:
                raise RuntimeError(f"Merge existing native link options explicitly: {config}")
            text = text.replace("options(", 'options(\n  link: { "native": { '
                '"stub-cc": "clang", '
                '"stub-cc-flags": "-fsanitize=address,undefined -fno-sanitize-recover=all '
                '-fno-omit-frame-pointer" } },', 1)
            config.write_text(text)
        workspace.append(str(destination))
    workspace.append(str(PACKAGE))
    (PACKAGE / "moon.work").write_text("members = " + json.dumps(workspace) + "\n")
    environment = os.environ.copy()
    environment["MOON_WORK"] = str(PACKAGE / "moon.work")
    environment["MOONBIT_ALLOCATOR"] = "system"
    environment.pop("WASMOON_SANITIZER_PROBE", None)
    try:
        run(["moon", "test", ".", "--target", "native", "--no-parallelize", "--target-dir", str(OUT / "build")],
            log=OUT / "tests.log", env=environment)
    except RuntimeError:
        # Preserve the failing gate while obtaining per-test leak roots.
        for info in (OUT / "build").rglob("__blackbox_test_info.json"):
            if "wasmoon_sanitizer" not in str(info):
                continue
            binary = info.parent / "wasmoon_sanitizer.blackbox_test.exe"
            if not binary.exists():
                continue
            isolated = OUT / "isolated"
            isolated.mkdir(exist_ok=True)
            summary = []
            for filename, tests in json.loads(info.read_text())["tests"].items():
                for test in tests:
                    index = test["index"]
                    log = isolated / f"{filename}-{index}.log"
                    with log.open("w") as output:
                        result = subprocess.run([str(binary), f"{filename}:{index}-{index+1}"],
                                                cwd=PACKAGE, env=environment,
                                                stdout=output, stderr=subprocess.STDOUT, timeout=60)
                    diagnostic = re.findall(r"SUMMARY:.*", log.read_text())
                    summary.append({"file": filename, "index": index, "name": test["name"],
                                    "exit": result.returncode, "diagnostic": diagnostic})
            (isolated / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
        raise
    executables = list((OUT / "build").rglob("*.blackbox_test.exe"))
    if not executables:
        raise RuntimeError("No instrumented test executable found")
    binary = next(p for p in executables if "wasmoon_sanitizer" in str(p))
    symbols = subprocess.check_output(["nm", str(binary)], text=True)
    (OUT / "symbols.log").write_text(symbols)
    for symbol in ["__asan_init", "__ubsan_handle"]:
        if symbol not in symbols:
            raise RuntimeError(f"Missing instrumentation: {symbol}")
    # Exercise resolver failure and cancellation schedules under the same tools.
    allocation_probe = OUT / "resolver-lifecycle"
    include = Path(os.environ.get("MOON_HOME", Path.home() / ".moon")) / "include"
    run(["clang", "-pthread", "-fsanitize=address,undefined", "-fno-sanitize-recover=all",
         "-fno-omit-frame-pointer", "-I", str(include),
         "-I", str(sources / "wasmoon_jit/host_io/wasi"),
         str(ROOT / "scripts/tests/native/resolver_lifecycle.c"),
         "-o", str(allocation_probe)], log=OUT / "allocation-build.log")
    run([str(allocation_probe)], log=OUT / "allocation.log")
    environment["WASMOON_SANITIZER_PROBE"] = "asan"
    probe = run([str(binary), "instrumentation_test.mbt:0-1"],
                log=OUT / "probe.log", env=environment, expected_failure=True)
    if "ERROR: AddressSanitizer:" not in probe:
        raise RuntimeError("Positive control failed without an ASan diagnostic")
    environment["WASMOON_SANITIZER_PROBE"] = "native"
    native_probe = run([str(binary), "instrumentation_test.mbt:0-1"],
                       log=OUT / "native-probe.log", env=environment, expected_failure=True)
    if "ERROR: AddressSanitizer:" not in native_probe:
        raise RuntimeError("Native stub positive control failed without an ASan diagnostic")
    (OUT / "summary.json").write_text(json.dumps({
        "version": version, "source_revision": subprocess.check_output(
            ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "source_dirty": bool(subprocess.check_output(
            ["git", "status", "--porcelain"], cwd=ROOT, text=True).strip()),
        "binary_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
        "tests": "passed", "asan_probe": "detected", "native_asan_probe": "detected",
        "binary": str(binary), "instrumentation": ["address", "undefined"], "allocator": "system",
        "exclusions": ["MoonBit runtime objects", "JIT machine code"],
    }, indent=2) + "\n")
    print(f"Sanitizer tests and instrumentation proof passed: {OUT}")


if __name__ == "__main__":
    main()
