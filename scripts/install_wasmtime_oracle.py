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
        "wasmtime-v45.0.0-x86_64-linux.tar.xz",
        "9d92e6dc04630f617e0e5d532327a5a917ac4898587e07f4fb7a5fc7fffef760",
    ),
    ("Darwin", "arm64"): (
        "wasmtime-v45.0.0-aarch64-macos.tar.xz",
        "8c589a1feb6578ddfd76d4ee07bac551d7f3069d6cef9b2ae5e87e630b5198db",
    ),
    ("Darwin", "x86_64"): (
        "wasmtime-v45.0.0-x86_64-macos.tar.xz",
        "b01b421613d9e067103efb701cd66f436020b32f6e955125fac9eaf34fa5bce7",
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
