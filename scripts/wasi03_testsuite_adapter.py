"""Command-world adapter for the upstream WASI Preview 3 acceptance audit.

Load this module with WebAssembly/wasi-testsuite's Python test runner.
HTTP service operations need a separate adapter; they must not be counted as
passes. Also inspect runtime diagnostics: upstream exit-code-only negative tests
can mistake an instantiation error for the expected guest exit.
"""

import os
from pathlib import Path
import subprocess

BINARY = os.environ.get("WASMOON", str(Path(__file__).resolve().parents[1] / "wasmoon"))
ENGINE = os.environ.get("WASI03_ENGINE", "jit")


def get_name():
    return f"wasmoon-{ENGINE}"


def get_version():
    return subprocess.check_output([BINARY, "--version"], text=True).strip().split()[-1]


def get_wasi_versions():
    return ["wasm32-wasip3"]


def get_wasi_worlds():
    return ["wasi:cli/command"]


def compute_argv(test_path, args_env_root, proposals, wasi_world, wasi_version):
    if ENGINE not in {"jit", "interp"}:
        raise ValueError("WASI03_ENGINE must be jit or interp")
    args, env, root = args_env_root
    argv = [BINARY, "component", "--run", "--network", "all"]
    if ENGINE == "interp":
        argv.append("--no-jit")
    for name, value in env.items():
        argv.extend(["--env", f"{name}={value}"])
    if root:
        argv.extend(["--dir", f"{root}::/"])
    for arg in args:
        argv.extend(["--arg", arg])
    return argv + [test_path]
