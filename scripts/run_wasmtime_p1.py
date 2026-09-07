#!/usr/bin/env python3
"""Run pinned Wasmtime WASIp1 guests with original or explicit legacy-rights expectations."""

from __future__ import annotations

import argparse
from contextlib import contextmanager
import errno
import fnmatch
import hashlib
import json
import os
from pathlib import Path
import platform
import pty
import select
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import tomllib


ROOT = Path(__file__).resolve().parents[1]
CORPUS = ROOT / "wasi-tests/wasmtime"
BUILD = ROOT / "target/wasmtime-p1-build"
UNSUPPORTED = {
    "p1_cli_hostcall_fuel": "Requires Wasmtime-specific hostcall fuel limits, not WASIp1 semantics.",
    "p1_file_truncation_readonly": "Requires a read-only preopen capability; Wasmoon CLI only exposes read-write preopens.",
    "p1_file_hardlink_across_perms": "Requires a read-only preopen capability; Wasmoon CLI only exposes read-write preopens.",
    "p1_file_rename_across_perms": "Requires a read-only preopen capability; Wasmoon CLI only exposes read-write preopens.",
}


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def validate_snapshot(corpus: Path = CORPUS) -> tuple[dict, list[str]]:
    snapshot = json.loads((corpus / "SNAPSHOT.json").read_text())
    commit = snapshot["commit"]
    if len(commit) != 40 or any(c not in "0123456789abcdef" for c in commit):
        raise ValueError("snapshot must pin a full upstream commit")
    entries = snapshot["files"]
    paths = [entry["path"] for entry in entries]
    actual = {p.relative_to(corpus / "upstream").as_posix()
              for p in (corpus / "upstream").rglob("*") if p.is_file()}
    if len(paths) != len(set(paths)) or set(paths) != actual:
        raise ValueError("upstream file inventory differs from SNAPSHOT.json")
    for entry in entries:
        if digest(corpus / "upstream" / entry["path"]) != entry["sha256"]:
            raise ValueError(f"upstream hash mismatch: {entry['path']}")
    manifest = tomllib.loads((corpus / "Cargo.toml").read_text())
    bins = manifest["bin"]
    guests = sorted(p for p in paths if p.startswith("crates/test-programs/src/bin/p1_")
                    and p.endswith(".rs"))
    if sorted(b["path"] for b in bins) != ["upstream/" + p for p in guests]:
        raise ValueError("Cargo binary inventory differs from upstream P1 inventory")
    names = [b["name"] for b in bins]
    if len(set(names)) != len(names) or any(Path(b["path"]).stem != b["name"] for b in bins):
        raise ValueError("Cargo binary names must match upstream source names")
    if not set(UNSUPPORTED).issubset(names):
        raise ValueError("stale unsupported-test entry")
    return snapshot, sorted(names)


@contextmanager
def prepare_build(profile: str):
    if profile == "upstream":
        yield CORPUS, BUILD
        return
    parent = ROOT / "target"
    parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="wasmtime-p1-source-", dir=parent) as temporary:
        source = Path(temporary)
        shutil.copytree(CORPUS, source, dirs_exist_ok=True)
        subprocess.run(["git", "apply", str(CORPUS / "explicit-rights.patch")],
                       cwd=source, check=True)
        yield source, ROOT / "target/wasmtime-p1-explicit-rights-build"


def guest_environment() -> dict[str, str]:
    # Mirrors upstream crates/test-programs/artifacts/src/lib.rs.
    return {"ERRNO_MODE_MACOS" if sys.platform == "darwin" else "ERRNO_MODE_UNIX": "1"}


def prepare_fixture(scratch: Path, name: str) -> None:
    if name == "p1_stat_extreme_host_mtime":
        path = scratch / "extreme.dat"
        path.write_bytes(b"hello")
        # Mirrors the Unix SystemTime extreme in upstream store.rs. As upstream,
        # retain the fixture if the filesystem rejects or clamps the timestamp.
        try:
            extreme = -(2**63) * 1_000_000_000
            os.utime(path, ns=(extreme, extreme))
        except (OSError, OverflowError):
            pass


def command_for(binary: Path, mode: str, wasm: Path, scratch: Path, name: str) -> list[str]:
    args = [str(binary), "run"]
    if mode == "wasmtime":
        args += ["--dir", f"{scratch}::."]
        for key, value in guest_environment().items():
            args += ["--env", f"{key}={value}"]
        args += [str(wasm)]
    else:
        args += [str(wasm), "--dir", f"{scratch}::.", "-S", "common"]
        for key, value in guest_environment().items():
            args += ["--env", f"{key}={value}"]
        if mode == "interp":
            args += ["--no-jit"]
    # The CLI output stress test has its own argument/output contract.
    # Wasmtime forwards everything after the module path, including a literal
    # '--'; Wasmoon argparse consumes the separator before guest arguments.
    if mode != "wasmtime":
        args += ["--"]
    args += ["hello, world!", "10000"] if name == "p1_cli_much_stdout" else ["."]
    return args


def execute(command: list[str], directory: Path, timeout: float,
            *, terminal: bool = False, pending_stdin: bool = False) -> dict:
    """Keep output on disk; kill and reap the process group on timeout."""
    stdout_path = directory / "stdout.txt"
    stderr_path = directory / "stderr.txt"
    started = time.monotonic()
    master = slave = None
    status = "fail"
    returncode = None
    detail = ""
    proc = None
    with stdout_path.open("wb") as stdout, stderr_path.open("wb") as stderr:
        try:
            if terminal:
                master, slave = pty.openpty()
            env = os.environ.copy()
            # A fresh per-case JIT cache avoids testing an unrelated old artifact.
            env["WASMOON_JIT_CACHE_DIR"] = str(directory / "jit-cache")
            proc = subprocess.Popen(
                command, cwd=directory, env=env, start_new_session=True,
                stdin=slave if terminal else (subprocess.PIPE if pending_stdin else subprocess.DEVNULL),
                stdout=slave if terminal else stdout,
                stderr=slave if terminal else stderr,
            )
            if slave is not None:
                os.close(slave)
                slave = None
            if master is not None:
                # Drain the PTY while the guest runs so a panic cannot fill it.
                while True:
                    remaining = timeout - (time.monotonic() - started)
                    if remaining <= 0:
                        raise subprocess.TimeoutExpired(command, timeout)
                    readable, _, _ = select.select([master], [], [], min(remaining, 0.1))
                    if readable:
                        try:
                            chunk = os.read(master, 65536)
                        except OSError as error:
                            if error.errno != errno.EIO:
                                raise
                            break
                        if not chunk:
                            break
                        stdout.write(chunk)
                    elif proc.poll() is not None:
                        break
            returncode = proc.wait(timeout=max(0.001, timeout - (time.monotonic() - started)))
            status = "pass" if returncode == 0 else "fail"
        except subprocess.TimeoutExpired:
            status = "timeout"
            detail = f"Exceeded {timeout:g} seconds"
        except OSError as error:
            status = "harness_error"
            detail = str(error)
        finally:
            if proc is not None:
                if proc.poll() is None:
                    os.killpg(proc.pid, signal.SIGKILL)
                returncode = proc.wait()
                if proc.stdin is not None:
                    proc.stdin.close()
            for fd in (master, slave):
                if fd is not None:
                    os.close(fd)
    return {"status": status, "returncode": returncode, "detail": detail,
            "seconds": round(time.monotonic() - started, 3), "command": command,
            "stdout": str(stdout_path), "stderr": str(stderr_path),
            "terminal": terminal, "pending_stdin": pending_stdin}


def run_case(binary: Path, mode: str, wasm: Path, output: Path, timeout: float,
             *, pending_stdin: bool = False) -> dict:
    name = wasm.stem
    case_id = name + ("__pending_stdin" if pending_stdin else "")
    record = {"name": name, "case": case_id, "mode": mode}
    if name in UNSUPPORTED:
        return record | {"status": "unsupported", "detail": UNSUPPORTED[name]}
    directory = output / mode / case_id
    directory.mkdir(parents=True)
    scratch = directory / "scratch"
    scratch.mkdir()
    try:
        prepare_fixture(scratch, name)
        result = execute(command_for(binary, mode, wasm, scratch, name), directory, timeout,
                         terminal=name == "p1_stdio_isatty", pending_stdin=pending_stdin)
        if result["status"] == "pass" and name == "p1_cli_much_stdout":
            if Path(result["stdout"]).read_bytes() != b"hello, world!" * 10000:
                result.update(status="fail", detail="stdout differs from the complete expected byte sequence")
        return record | result
    except OSError as error:
        return record | {"status": "harness_error", "detail": str(error)}
    finally:
        # Each case/mode gets a fresh filesystem. Logs survive cleanup.
        shutil.rmtree(scratch)


def verdict(results: list[dict]) -> int:
    if any(r["status"] == "harness_error" for r in results):
        return 2
    return int(any(r["status"] in {"fail", "timeout"} for r in results)
               or not any(r["status"] == "pass" for r in results))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", choices=["upstream", "explicit-rights"], default="upstream")
    parser.add_argument("--mode", choices=["both", "jit", "interp", "wasmtime"], default="both")
    parser.add_argument("--wasmoon", type=Path, default=ROOT / "wasmoon")
    parser.add_argument("--wasmtime", default="wasmtime")
    parser.add_argument("--filter", default="*", help="Shell glob over guest program names")
    parser.add_argument("--timeout", type=float, default=30.0, help="Seconds per invocation")
    parser.add_argument("--output", type=Path, help="New or empty result directory")
    parser.add_argument("--check", action="store_true", help="Only verify the source snapshot")
    parser.add_argument("--list", action="store_true", help="List selected programs without building")
    args = parser.parse_args()
    if sys.platform not in {"darwin", "linux"}:
        parser.error("this runner currently supports macOS and Linux")
    if args.timeout <= 0:
        parser.error("--timeout must be positive")
    try:
        snapshot, names = validate_snapshot()
        if args.check:
            print(f"Verified {len(names)} P1 programs at {snapshot['commit']}")
            return 0
        names = [name for name in names if fnmatch.fnmatchcase(name, args.filter)]
        if not names:
            parser.error("--filter matched no programs")
        if args.list:
            for name in names:
                print(name + (f" [unsupported: {UNSUPPORTED[name]}]" if name in UNSUPPORTED else ""))
            return 0
        binary = Path(shutil.which(args.wasmtime) or args.wasmtime) if args.mode == "wasmtime" else args.wasmoon
        binary = binary.resolve()
        if not binary.is_file() or not os.access(binary, os.X_OK):
            parser.error(f"missing executable: {binary}; build Wasmoon with ./install.sh")
        with prepare_build(args.profile) as (source, build):
            build_command = ["cargo", "build", "--locked", "--manifest-path", str(source / "Cargo.toml"),
                             "--target", "wasm32-wasip1", "--release", "--target-dir", str(build)]
            subprocess.run(build_command, check=True, cwd=ROOT)
        if args.output:
            output = args.output.resolve()
            output.mkdir(parents=True, exist_ok=True)
            if any(output.iterdir()):
                parser.error("--output must be empty (previous evidence is never overwritten)")
        else:
            parent = ROOT / "target/wasmtime-p1-results"
            parent.mkdir(parents=True, exist_ok=True)
            output = Path(tempfile.mkdtemp(prefix="run-", dir=parent)).resolve()
        results = []
        report = {
            "profile": args.profile,
            "adaptation_sha256": digest(CORPUS / "explicit-rights.patch") if args.profile != "upstream" else None,
            "upstream_commit": snapshot["commit"], "host": platform.platform(),
            "engine": str(binary), "engine_sha256": digest(binary),
            "engine_version": subprocess.check_output([str(binary), "--version"], text=True).strip(),
            "rustc": subprocess.check_output(["rustc", "--version", "--verbose"], text=True).strip(),
            "cargo_lock_sha256": digest(CORPUS / "Cargo.lock"),
            "build_command": build_command, "guest_environment": guest_environment(),
            "filter": args.filter, "timeout": args.timeout, "results": results,
        }
        modes = ["interp", "jit"] if args.mode == "both" else [args.mode]
        print(f"Results: {output}", flush=True)
        for name in names:
            wasm = (build / "wasm32-wasip1/release" / f"{name}.wasm").resolve()
            for mode in modes:
                # Test polling with both EOF and an open, unreadable stdin pipe.
                for pending in ([False, True] if name == "p1_poll_oneoff_stdio" else [False]):
                    result = run_case(binary, mode, wasm, output, args.timeout, pending_stdin=pending)
                    result["wasm_sha256"] = digest(wasm)
                    results.append(result)
                    print(f"{mode:8} {result['status']:13} {result['case']} {result.get('detail', '')}", flush=True)
                    (output / "summary.json").write_text(json.dumps(report, indent=2) + "\n")
        counts = {s: sum(r["status"] == s for r in results)
                  for s in ["pass", "fail", "timeout", "unsupported", "harness_error"]}
        report["counts"] = counts
        (output / "summary.json").write_text(json.dumps(report, indent=2) + "\n")
        print(json.dumps(counts), flush=True)
        return verdict(results)
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as error:
        print(f"P1 harness error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
