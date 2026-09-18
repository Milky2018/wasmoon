#!/usr/bin/env python3
"""Exercise actual CLI cache writes, hits, corruption, and write failures."""

import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--wasmoon", default="./wasmoon.exe" if os.name == "nt" else "./wasmoon")
    args = parser.parse_args()
    binary = str(Path(args.wasmoon).resolve())
    with tempfile.TemporaryDirectory(prefix="wasmoon-cache-") as directory:
        root = Path(directory)
        cache = root / "cache"
        cache.mkdir()
        # (module (func (export "_start") (result i32) i32.const 42))
        wasm = root / "answer.wasm"
        wasm.write_bytes(bytes.fromhex(
            "0061736d010000000105016000017f03020100070a01065f73746172740000"
            "0a06010400412a0b"
        ))
        report = root / "report.json"
        env = {**os.environ, "WASMOON_JIT_CACHE_DIR": str(cache),
               "WASMOON_JIT_CACHE_REPORT": str(report)}

        def run(label, fresh, hit, written):
            report.unlink(missing_ok=True)
            result = subprocess.run([binary, "run", str(wasm)], env=env,
                                    capture_output=True, text=True, timeout=60)
            assert result.returncode == 0, (label, result.stderr)
            assert result.stdout.strip() == "42", (label, result.stdout)
            actual = json.loads(report.read_text())
            expected = {"schema_version": 1, "freshly_compiled": fresh,
                        "cache_hit": hit, "cache_write_succeeded": written}
            assert actual == expected, (label, actual, expected)
            if written is False:
                assert "Failed to write JIT cache" in result.stderr, result.stderr
            print(f"{label}: {json.dumps(actual)}")

        run("cold", True, False, True)
        entries = list(cache.iterdir())
        assert len(entries) == 1, entries
        entry = entries[0]
        assert len(entry.name.encode()) <= 255, entry.name
        original = entry.read_bytes()
        original_mtime = entry.stat().st_mtime_ns
        run("warm", False, True, None)
        assert entry.read_bytes() == original
        assert entry.stat().st_mtime_ns == original_mtime
        entry.write_bytes(b"corrupt artifact")
        run("corrupt", True, False, True)
        assert entry.read_bytes() == original
        entry.unlink()
        # A directory at the artifact path deterministically blocks writes on
        # all supported platforms, even when the test runs as an administrator.
        entry.mkdir()
        run("write-failed", True, False, False)
        entry.rmdir()
        cache.rmdir()
        cache.write_bytes(b"not a cache directory")
        run("cache-unavailable", True, False, None)


if __name__ == "__main__":
    main()
