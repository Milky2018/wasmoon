#!/usr/bin/env python3
"""Build HTTP guests using official WIT and wasm-tools component encoding."""
import argparse
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(__doc__)
parser.add_argument("--output", type=Path, default=ROOT / "target/http-fixtures")
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
for name in ["echo", "trap", "proxy", "inspect", "middleware", "outer", "inner"]:
    source = ROOT / "tests/http" / f"{name}.wat"
    if name == "trap":
        source = args.output / "trap.wat"
        source.write_text((ROOT / "tests/http/echo.wat").read_text().replace('(local $pair i64)', '(local $pair i64)\n    unreachable'))
    if name == "middleware":
        source = args.output / f"{name}.wat"
        source.write_text((ROOT / "tests/http/proxy.wat").read_text().replace("wasi:http/client", "wasi:http/handler").replace("[async-lower]send", "[async-lower]handle"))
    if name in ["outer", "inner"]:
        source = args.output / f"{name}.wat"
        source.write_text((ROOT / "tests/http/marker.wat").read_text().replace('"/layer"', f'"/{name}"'))
    core = args.output / f"{name}.core.wasm"
    subprocess.run(["wasm-tools", "component", "embed", str(ROOT / "modules/wasmoon/wasi_http/wit"),
                    str(source), "--world", "wasi:http/middleware" if name in ["middleware", "outer", "inner"] else "wasi:http/service", "-o", str(core)], check=True)
    subprocess.run(["wasm-tools", "component", "new", str(core), "-o", str(args.output / f"{name}.wasm")], check=True)
    subprocess.run(["wasm-tools", "validate", "--features", "all", str(args.output / f"{name}.wasm")], check=True)
subprocess.run(["wasm-tools", "parse", "-o", str(args.output / "empty.wasm")], input=b"(component)", check=True)
