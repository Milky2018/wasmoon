#!/usr/bin/env python3
"""Install the pinned official Wasmtime component differential oracle."""

from __future__ import annotations

import argparse
import hashlib
import platform
import shutil
import tarfile
import tempfile
import urllib.request
from pathlib import Path

from component_hardening_lib import WASMTIME_VERSION, require_tool_version


ASSETS = {
    ("Linux", "x86_64"): (
        "wasmtime-v49.0.1-x86_64-linux.tar.xz",
        "c71f7e0d30a92e418f0d17db7c6d8f6664c1ad764340a1278678f4209deab534",
    ),
    ("Darwin", "arm64"): (
        "wasmtime-v49.0.1-aarch64-macos.tar.xz",
        "93dde14d4efb20046e5af75517ac6a7f2246f6c2370fecff8f68839d4a9028f7",
    ),
    ("Darwin", "x86_64"): (
        "wasmtime-v49.0.1-x86_64-macos.tar.xz",
        "56355136c4eaba17ef50b0e35e9774e25950333ba007c2a29c45d0906600e827",
    ),
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def safe_extract(archive: Path, destination: Path) -> None:
    destination_root = destination.resolve()
    with tarfile.open(archive, mode="r:xz") as tar:
        for member in tar.getmembers():
            member_path = (destination / member.name).resolve()
            if destination_root not in member_path.parents and member_path != destination_root:
                raise RuntimeError(f"unsafe archive member {member.name!r}")
        tar.extractall(destination, filter="data")


def install(output: Path, system: str, machine: str) -> Path:
    try:
        asset, expected_digest = ASSETS[(system, machine)]
    except KeyError:
        raise RuntimeError(f"unsupported Wasmtime oracle platform {system}/{machine}")
    url = (
        "https://github.com/bytecodealliance/wasmtime/releases/download/"
        f"v{WASMTIME_VERSION}/{asset}"
    )
    output.mkdir(parents=True, exist_ok=True)
    binary = output / "wasmtime"
    with tempfile.TemporaryDirectory(prefix="wasmtime-oracle-") as directory:
        temporary = Path(directory)
        archive = temporary / asset
        urllib.request.urlretrieve(url, archive)
        actual_digest = sha256(archive)
        if actual_digest != expected_digest:
            raise RuntimeError(
                f"Wasmtime archive checksum mismatch: expected {expected_digest}, "
                f"found {actual_digest}"
            )
        extracted = temporary / "extracted"
        extracted.mkdir()
        safe_extract(archive, extracted)
        candidates = list(extracted.glob("*/wasmtime"))
        if len(candidates) != 1:
            raise RuntimeError("official Wasmtime archive did not contain one binary")
        shutil.copy2(candidates[0], binary)
        binary.chmod(0o755)
    require_tool_version(str(binary), "wasmtime", WASMTIME_VERSION)
    return binary


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("target/component-hardening/wasmtime-oracle"),
    )
    args = parser.parse_args()
    binary = install(args.output, platform.system(), platform.machine())
    print(binary)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
