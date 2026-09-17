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
for name in ["echo", "proxy", "middleware"]:
    source = ROOT / "tests/http" / f"{name}.wat"
    if name == "middleware":
        source = args.output / "middleware.wat"
        source.write_text((ROOT / "tests/http/proxy.wat").read_text().replace("wasi:http/client", "wasi:http/handler").replace("[async-lower]send", "[async-lower]handle"))
    core = args.output / f"{name}.core.wasm"
    subprocess.run(["wasm-tools", "component", "embed", str(ROOT / "modules/wasmoon/wasi_http/wit"),
                    str(source), "--world", "wasi:http/middleware" if name == "middleware" else "wasi:http/service", "-o", str(core)], check=True)
    subprocess.run(["wasm-tools", "component", "new", str(core), "-o", str(args.output / f"{name}.wasm")], check=True)
    subprocess.run(["wasm-tools", "validate", "--features", "all", str(args.output / f"{name}.wasm")], check=True)
