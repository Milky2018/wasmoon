"""Adapter for the pinned upstream WASI Preview 3 command and HTTP tests.

Runtime failures use exit status 125, independently of guest result/exit status.
"""

import os
from pathlib import Path
import subprocess
import sys

BINARY = os.environ.get("WASMOON", str(Path(__file__).resolve().parents[1] / "wasmoon"))
ENGINE = os.environ.get("WASI03_ENGINE", "jit")


def get_name():
    return f"wasmoon-{ENGINE}"


def get_version():
    return subprocess.check_output([BINARY, "--version"], text=True).strip().split()[-1]


def get_wasi_versions():
    return ["wasm32-wasip3"]


def get_wasi_worlds():
    return ["wasi:cli/command", "wasi:http/service"]


def compute_argv(test_path, args_env_root, proposals, wasi_world, wasi_version):
    if ENGINE not in {"jit", "interp"}:
        raise ValueError("WASI03_ENGINE must be jit or interp")
    args, env, root = args_env_root
    network = "all" if wasi_world == "wasi:http/service" or "http" in proposals or Path(test_path).stem.startswith("sockets-") else "deny"
    argv = [BINARY, "serve", "--addr", "127.0.0.1:0", "--network", network] if wasi_world == "wasi:http/service" else [BINARY, "component", "--run", "--network", network]
    if wasi_world == "wasi:cli/command" and "http" in proposals:
        argv.append("--http")
    if ENGINE == "interp":
        argv.append("--no-jit")
    for name, value in env.items():
        argv.extend(["--env", f"{name}={value}"])
    if root:
        argv.extend(["--dir", f"{root}::/"])
    for arg in args:
        argv.extend(["--arg", arg])
    # Windows upstream terminates the direct service process with TerminateProcess.
    # Do not interpose a wrapper whose child would outlive that termination.
    if os.name == "nt" and wasi_world == "wasi:http/service":
        return argv + [test_path]
    return [sys.executable, str(Path(__file__).with_name("wasi03_process.py")),
            "service" if wasi_world == "wasi:http/service" else "command"] + argv + [test_path]
