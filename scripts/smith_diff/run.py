#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
SMITH_DIR = Path(__file__).resolve().parent
DEFAULT_CONFIG = SMITH_DIR / "wasm_smith_all.json"
TEMPLATE_WAT = SMITH_DIR / "template_run.wat"


@dataclass(frozen=True)
class Outcome:
    kind: str  # ok|trap|error|timeout
    rc: int
    stdout: str
    stderr: str


def _run(
    argv: list[str],
    *,
    timeout_s: float,
    cwd: Path | None = None,
) -> Outcome:
    try:
        p = subprocess.run(
            argv,
            cwd=str(cwd) if cwd is not None else None,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout_s,
        )
    except subprocess.TimeoutExpired as e:
        stdout = (e.stdout or "") if isinstance(e.stdout, str) else ""
        stderr = (e.stderr or "") if isinstance(e.stderr, str) else ""
        return Outcome(kind="timeout", rc=124, stdout=stdout, stderr=stderr)

    stdout = p.stdout or ""
    stderr = p.stderr or ""

    if p.returncode == 0:
        return Outcome(kind="ok", rc=0, stdout=stdout, stderr=stderr)

    lowered = (stderr + "\n" + stdout).lower()

    # Classify traps heuristically across runtimes.
    # Wasmoon often formats traps as `Error: <trap reason>`.
    trap_markers = [
        "wasm trap",
        "trap:",
        "unreachable",
        "stack overflow",
        "out of bounds",
        "memory fault",
        "division by zero",
        "integer divide by zero",
        "integer overflow",
        "invalid conversion to integer",
        "undefined element",
        "uninitialized element",
        "indirect call type mismatch",
        "null reference",
    ]

    parse_markers = [
        "parse wasm module error",
        "parse wat file error",
        "parsing wasm",
        "parsing wat",
    ]

    if any(m in lowered for m in parse_markers):
        kind = "error"
    elif any(m in lowered for m in trap_markers):
        kind = "trap"
    else:
        kind = "error"
    return Outcome(kind=kind, rc=p.returncode, stdout=stdout, stderr=stderr)


def _ensure_tools() -> None:
    required = ["wasm-tools", "wasmtime"]
    missing = [t for t in required if shutil.which(t) is None]
    if missing:
        raise SystemExit(f"missing required tools in PATH: {', '.join(missing)}")

    wasmoon = REPO_ROOT / "wasmoon"
    wasmoon_tools = REPO_ROOT / "wasmoon-tools"
    if not wasmoon.exists() or not wasmoon_tools.exists():
        raise SystemExit(
            "missing ./wasmoon or ./wasmoon-tools; run `./install.sh` first"
        )


def _build_template_wasm(work_dir: Path) -> Path:
    template_wasm = work_dir / "template_run.wasm"
    argv = [
        "wasm-tools",
        "parse",
        str(TEMPLATE_WAT),
        "-o",
        str(template_wasm),
    ]
    out = _run(argv, timeout_s=10.0)
    if out.kind != "ok":
        raise SystemExit(
            "failed to build template wasm:\n"
            f"stdout:\n{out.stdout}\n\n"
            f"stderr:\n{out.stderr}"
        )
    return template_wasm


def _build_wat_to_wasm(work_dir: Path, *, name: str, wat: str) -> Path:
    wat_path = work_dir / f"{name}.wat"
    wasm_path = work_dir / f"{name}.wasm"
    wat_path.write_text(wat, encoding="utf-8")
    out = _run(["wasm-tools", "parse", str(wat_path), "-o", str(wasm_path)], timeout_s=10.0)
    if out.kind != "ok":
        raise SystemExit(
            f"failed to build {name} wasm:\n"
            f"stdout:\n{out.stdout}\n\n"
            f"stderr:\n{out.stderr}"
        )
    return wasm_path


def _load_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def _write_json(path: Path, obj: dict) -> None:
    with path.open("w", encoding="utf-8") as f:
        json.dump(obj, f, indent=2, sort_keys=True)
        f.write("\n")


def _smith_config_for_run(config_path: Path, work_dir: Path, *, allow_imports: bool) -> Path:
    cfg = _load_json(config_path)

    # For differential execution, imports are almost always noise unless we also
    # generate matching stub modules.
    cfg["min-imports"] = 0
    if not allow_imports:
        # Keep this at zero so we can actually execute most generated modules.
        cfg["max-imports"] = 0

    # Keep size bounded for 1000-case runs.
    cfg.setdefault("max-funcs", 50)
    cfg.setdefault("max-instructions", 200)

    out_path = work_dir / "smith_config.json"
    _write_json(out_path, cfg)
    return out_path


def _generate_module(
    *,
    seed_path: Path,
    out_wasm: Path,
    template_wasm: Path,
    module_type_wasm: Path | None,
    config_path: Path,
    ensure_termination: bool,
) -> Outcome:
    argv = [
        "wasm-tools",
        "smith",
        str(seed_path),
        "-c",
        str(config_path),
        "-o",
        str(out_wasm),
    ]

    if module_type_wasm is not None:
        argv += ["--module-type", str(module_type_wasm)]
    else:
        argv += ["--exports", str(template_wasm)]

    if ensure_termination:
        argv.append("--ensure-termination")

    return _run(argv, timeout_s=10.0)


def _run_wasmtime(wasm: Path, timeout_s: float, *, preloads: list[str] | None = None) -> Outcome:
    # Enable a broad set of proposals, but explicitly keep stack-switching off.
    # Some wasmtime builds error out when stack-switching is requested.
    wasm_flags = [
        "bulk-memory=y",
        "multi-memory=y",
        "multi-value=y",
        "reference-types=y",
        "function-references=y",
        "simd=y",
        "relaxed-simd=y",
        "tail-call=y",
        "threads=y",
        "shared-everything-threads=y",
        "memory64=y",
        "gc=y",
        "custom-page-sizes=y",
        "wide-arithmetic=y",
        "extended-const=y",
        "exceptions=y",
        "stack-switching=n",
        "component-model=n",
        f"timeout={int(timeout_s)}s",
        "gc-support=y",
    ]

    argv: list[str] = ["wasmtime", "run"]
    if preloads:
        for p in preloads:
            argv += ["--preload", p]
    for flag in wasm_flags:
        argv += ["-W", flag]
    argv += ["--invoke", "run", str(wasm)]
    return _run(argv, timeout_s=timeout_s + 1.0)


def _run_wasmoon(
    wasm: Path,
    *,
    jit: bool,
    timeout_s: float,
    preloads: list[str] | None = None,
) -> Outcome:
    argv = [str(REPO_ROOT / "wasmoon"), "run", str(wasm), "--invoke", "run"]
    if preloads:
        for p in preloads:
            argv += ["--preload", p]
    if not jit:
        argv.append("--no-jit")
    return _run(argv, timeout_s=timeout_s)


def _signature(out: Outcome) -> tuple:
    if out.kind == "ok":
        return ("ok", out.stdout.strip())
    return (out.kind,)


def check_one(wasm: Path, *, timeout_s: float) -> int:
    """Exit 0 if mismatch exists, 1 otherwise.

    This is designed for `wasm-tools shrink` property checking.
    """
    oracle = _signature(_run_wasmtime(wasm, timeout_s=timeout_s))
    interp = _signature(_run_wasmoon(wasm, jit=False, timeout_s=timeout_s))
    jit = _signature(_run_wasmoon(wasm, jit=True, timeout_s=timeout_s))

    mismatch = (interp != oracle) or (jit != oracle)
    return 0 if mismatch else 1


def main() -> int:
    # `wasm-tools shrink` expects a predicate script which is invoked as:
    #
    #   predicate <candidate.wasm>
    #
    # To make this script usable directly as a predicate, accept a bare wasm path
    # as the first argument and treat it as `check`.
    if len(sys.argv) >= 2 and sys.argv[1] not in {"run", "check", "-h", "--help"}:
        wasm = Path(sys.argv[1])
        timeout_s = 3.0
        if "--timeout" in sys.argv[2:]:
            idx = sys.argv.index("--timeout")
            if idx + 1 < len(sys.argv):
                try:
                    timeout_s = float(sys.argv[idx + 1])
                except ValueError:
                    pass
        _ensure_tools()
        return check_one(wasm, timeout_s=timeout_s)

    parser = argparse.ArgumentParser(
        prog="smith-diff",
        description="Generate wasm-smith cases and diff wasmoon vs wasmtime",
    )
    sub = parser.add_subparsers(dest="cmd", required=True)

    run_p = sub.add_parser("run", help="generate N cases and run diffs")
    run_p.add_argument("--count", type=int, default=1000)
    run_p.add_argument("--seed-size", type=int, default=256)
    run_p.add_argument("--timeout", type=float, default=3.0)
    run_p.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    run_p.add_argument("--out", type=Path, default=SMITH_DIR / "out")
    run_p.add_argument("--keep-passing", action="store_true")
    run_p.add_argument("--no-shrink", action="store_true")
    run_p.add_argument("--no-ensure-termination", action="store_true")
    run_p.add_argument(
        "--multi-module",
        action="store_true",
        help="run generated modules with a preloaded provider module",
    )

    check_p = sub.add_parser("check", help="property check for shrink")
    check_p.add_argument("wasm", type=Path)
    check_p.add_argument("--timeout", type=float, default=3.0)

    args = parser.parse_args()

    if args.cmd == "check":
        _ensure_tools()
        return check_one(args.wasm, timeout_s=args.timeout)

    _ensure_tools()

    out_root = args.out
    out_root.mkdir(parents=True, exist_ok=True)
    run_id = time.strftime("%Y%m%d-%H%M%S")
    work_dir = out_root / f"run-{run_id}"
    work_dir.mkdir(parents=True, exist_ok=True)

    template_wasm = _build_template_wasm(work_dir)

    preloads: list[str] = []
    module_type_wasm: Path | None = None
    if args.multi_module:
        # Preload a provider module under the name "preload".
        # Generated modules can import "preload"."memory" to exercise module linking.
        preload_wasm = _build_wat_to_wasm(
            work_dir,
            name="preload_memory",
            wat='''(module
  (memory (export "memory") 1 2)
)\n''',
        )
        preloads = [f"preload={preload_wasm}"]
        module_type_wasm = _build_wat_to_wasm(
            work_dir,
            name="module_type_preload_memory",
            wat='''(module
  (import "preload" "memory" (memory 1 2))
  (func (export "run") (result i32)
    (i32.const 0))
)\n''',
        )

    smith_cfg = _smith_config_for_run(args.config, work_dir, allow_imports=args.multi_module)

    seeds_dir = work_dir / "seeds"
    seeds_dir.mkdir(parents=True, exist_ok=True)

    failures_dir = work_dir / "failures"
    failures_dir.mkdir(parents=True, exist_ok=True)

    summary_path = work_dir / "summary.json"

    ensure_termination = not args.no_ensure_termination
    do_shrink = not args.no_shrink

    stats = {
        "count": args.count,
        "seed_size": args.seed_size,
        "timeout": args.timeout,
        "ensure_termination": ensure_termination,
        "failures": 0,
        "generated_errors": 0,
        "passes": 0,
    }

    for i in range(args.count):
        seed = os.urandom(args.seed_size)
        seed_path = seeds_dir / f"seed-{i:04d}.bin"
        seed_path.write_bytes(seed)

        wasm_path = work_dir / f"case-{i:04d}.wasm"

        gen = _generate_module(
            seed_path=seed_path,
            out_wasm=wasm_path,
            template_wasm=template_wasm,
            module_type_wasm=module_type_wasm,
            config_path=smith_cfg,
            ensure_termination=ensure_termination,
        )
        if gen.kind != "ok":
            stats["generated_errors"] += 1
            if wasm_path.exists() and not args.keep_passing:
                wasm_path.unlink(missing_ok=True)
            continue

        oracle = _run_wasmtime(wasm_path, timeout_s=args.timeout, preloads=preloads)
        interp = _run_wasmoon(wasm_path, jit=False, timeout_s=args.timeout, preloads=preloads)
        jit = _run_wasmoon(wasm_path, jit=True, timeout_s=args.timeout, preloads=preloads)

        oracle_sig = _signature(oracle)
        interp_sig = _signature(interp)
        jit_sig = _signature(jit)

        mismatch = (interp_sig != oracle_sig) or (jit_sig != oracle_sig)

        if mismatch:
            stats["failures"] += 1
            case_dir = failures_dir / f"case-{i:04d}"
            case_dir.mkdir(parents=True, exist_ok=True)

            shutil.copy2(seed_path, case_dir / "seed.bin")
            shutil.copy2(wasm_path, case_dir / "case.wasm")

            (case_dir / "wasmtime.stdout").write_text(oracle.stdout, encoding="utf-8")
            (case_dir / "wasmtime.stderr").write_text(oracle.stderr, encoding="utf-8")
            (case_dir / "wasmtime.meta.json").write_text(
                json.dumps({"kind": oracle.kind, "rc": oracle.rc}, indent=2) + "\n",
                encoding="utf-8",
            )

            (case_dir / "wasmoon_interp.stdout").write_text(
                interp.stdout, encoding="utf-8"
            )
            (case_dir / "wasmoon_interp.stderr").write_text(
                interp.stderr, encoding="utf-8"
            )
            (case_dir / "wasmoon_interp.meta.json").write_text(
                json.dumps({"kind": interp.kind, "rc": interp.rc}, indent=2) + "\n",
                encoding="utf-8",
            )

            (case_dir / "wasmoon_jit.stdout").write_text(jit.stdout, encoding="utf-8")
            (case_dir / "wasmoon_jit.stderr").write_text(jit.stderr, encoding="utf-8")
            (case_dir / "wasmoon_jit.meta.json").write_text(
                json.dumps({"kind": jit.kind, "rc": jit.rc}, indent=2) + "\n",
                encoding="utf-8",
            )

            if do_shrink:
                shrunk = case_dir / "case.min.wasm"
                shrink_cmd = [
                    "wasm-tools",
                    "shrink",
                    str(Path(__file__).resolve()),
                    str(wasm_path),
                    "--attempts",
                    "200",
                    "-o",
                    str(shrunk),
                ]
                shrink_out = _run(shrink_cmd, timeout_s=120.0)
                (case_dir / "shrink.stdout").write_text(
                    shrink_out.stdout, encoding="utf-8"
                )
                (case_dir / "shrink.stderr").write_text(
                    shrink_out.stderr, encoding="utf-8"
                )
                (case_dir / "shrink.meta.json").write_text(
                    json.dumps(
                        {"kind": shrink_out.kind, "rc": shrink_out.rc}, indent=2
                    )
                    + "\n",
                    encoding="utf-8",
                )

        else:
            stats["passes"] += 1

        if not args.keep_passing and wasm_path.exists():
            wasm_path.unlink(missing_ok=True)

        if (i + 1) % 50 == 0:
            summary_path.write_text(json.dumps({"stats": stats}, indent=2) + "\n")

    summary_path.write_text(json.dumps({"stats": stats}, indent=2) + "\n")
    print(json.dumps({"work_dir": str(work_dir), "stats": stats}, indent=2))
    return 0 if stats["failures"] == 0 else 2


if __name__ == "__main__":
    raise SystemExit(main())
