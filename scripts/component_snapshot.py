#!/usr/bin/env python3
"""Validate the pinned upstream Component Model test snapshot."""

from __future__ import annotations

import hashlib
import json
from dataclasses import dataclass
from pathlib import Path, PurePosixPath


REQUIRED_SUITES = ("stable-0.2", "async-0.3", "future-gated")


class SnapshotError(Exception):
    """The checked-in Component Model snapshot is inconsistent."""


@dataclass(frozen=True)
class ComponentSnapshot:
    root: Path
    repository: str
    commit: str
    upstream_tree: str
    upstream_path: str
    wasm_tools_version: str
    suites: dict[str, tuple[Path, ...]]


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _require_string(data: dict[str, object], name: str) -> str:
    value = data.get(name)
    if not isinstance(value, str) or not value:
        raise SnapshotError(f"snapshot field {name!r} must be a non-empty string")
    return value


def _validate_relative_path(value: str, *, source: Path) -> Path:
    path = PurePosixPath(value)
    if path.is_absolute() or ".." in path.parts or value != path.as_posix():
        raise SnapshotError(f"{source}: invalid relative path {value!r}")
    return Path(*path.parts)


def _load_suite(path: Path) -> tuple[Path, ...]:
    entries: list[Path] = []
    seen: set[str] = set()
    for line_number, raw_line in enumerate(
        path.read_text(encoding="utf-8").splitlines(),
        start=1,
    ):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        relative = _validate_relative_path(line, source=path)
        if relative.suffix != ".wast":
            raise SnapshotError(
                f"{path}:{line_number}: suite entry must name a .wast file"
            )
        key = relative.as_posix()
        if key in seen:
            raise SnapshotError(f"{path}:{line_number}: duplicate entry {key!r}")
        seen.add(key)
        entries.append(relative)
    if not entries:
        raise SnapshotError(f"{path}: suite must contain at least one .wast file")
    return tuple(entries)


def validate_snapshot(repo_root: Path) -> ComponentSnapshot:
    component_root = repo_root / "component-spec"
    snapshot_path = component_root / "SNAPSHOT.json"
    try:
        data = json.loads(snapshot_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise SnapshotError(f"cannot read {snapshot_path}: {error}") from error
    if not isinstance(data, dict):
        raise SnapshotError(f"{snapshot_path}: root must be a JSON object")
    if data.get("schema_version") != 1:
        raise SnapshotError(f"{snapshot_path}: unsupported schema_version")

    repository = _require_string(data, "repository")
    commit = _require_string(data, "commit")
    upstream_tree = _require_string(data, "upstream_tree")
    upstream_path = _require_string(data, "upstream_path")
    wasm_tools_version = _require_string(data, "wasm_tools_version")
    if len(commit) != 40 or any(char not in "0123456789abcdef" for char in commit):
        raise SnapshotError(f"{snapshot_path}: commit must be a full lowercase SHA-1")
    if len(upstream_tree) != 40 or any(
        char not in "0123456789abcdef" for char in upstream_tree
    ):
        raise SnapshotError(
            f"{snapshot_path}: upstream_tree must be a full lowercase SHA-1"
        )

    raw_files = data.get("files")
    if not isinstance(raw_files, list) or not raw_files:
        raise SnapshotError(f"{snapshot_path}: files must be a non-empty array")
    expected_hashes: dict[str, str] = {}
    for index, entry in enumerate(raw_files):
        if not isinstance(entry, dict):
            raise SnapshotError(f"{snapshot_path}: files[{index}] must be an object")
        raw_path = _require_string(entry, "path")
        relative = _validate_relative_path(raw_path, source=snapshot_path)
        digest = _require_string(entry, "sha256")
        if len(digest) != 64 or any(
            char not in "0123456789abcdef" for char in digest
        ):
            raise SnapshotError(
                f"{snapshot_path}: invalid SHA-256 for {relative.as_posix()!r}"
            )
        key = relative.as_posix()
        if key in expected_hashes:
            raise SnapshotError(f"{snapshot_path}: duplicate file entry {key!r}")
        expected_hashes[key] = digest

    upstream_root = component_root / "upstream"
    actual_paths: dict[str, Path] = {}
    for path in upstream_root.rglob("*"):
        if path.is_symlink():
            raise SnapshotError(f"{path}: symlinks are not allowed in the snapshot")
        if path.is_file():
            key = path.relative_to(upstream_root).as_posix()
            actual_paths[key] = path
    expected_names = set(expected_hashes)
    actual_names = set(actual_paths)
    if missing := sorted(expected_names - actual_names):
        raise SnapshotError(f"snapshot files missing from disk: {', '.join(missing)}")
    if extra := sorted(actual_names - expected_names):
        raise SnapshotError(f"untracked snapshot files on disk: {', '.join(extra)}")
    for name, expected in expected_hashes.items():
        actual = sha256_file(actual_paths[name])
        if actual != expected:
            raise SnapshotError(
                f"snapshot hash mismatch for {name}: expected {expected}, got {actual}"
            )

    suites: dict[str, tuple[Path, ...]] = {}
    assigned: dict[str, str] = {}
    suite_root = component_root / "suites"
    actual_suite_names = {
        path.stem
        for path in suite_root.glob("*.txt")
        if path.is_file()
    }
    expected_suite_names = set(REQUIRED_SUITES)
    if missing := sorted(expected_suite_names - actual_suite_names):
        raise SnapshotError(f"suite manifests missing: {', '.join(missing)}")
    if extra := sorted(actual_suite_names - expected_suite_names):
        raise SnapshotError(f"unexpected suite manifests: {', '.join(extra)}")
    for suite_name in REQUIRED_SUITES:
        suite_path = suite_root / f"{suite_name}.txt"
        try:
            entries = _load_suite(suite_path)
        except OSError as error:
            raise SnapshotError(f"cannot read {suite_path}: {error}") from error
        for relative in entries:
            name = relative.as_posix()
            if name not in expected_hashes:
                raise SnapshotError(
                    f"{suite_path}: entry {name!r} is not in the pinned snapshot"
                )
            if previous := assigned.get(name):
                raise SnapshotError(
                    f"{name!r} appears in both {previous!r} and {suite_name!r}"
                )
            assigned[name] = suite_name
        suites[suite_name] = entries

    wast_files = {name for name in expected_hashes if name.endswith(".wast")}
    assigned_files = set(assigned)
    if missing := sorted(wast_files - assigned_files):
        raise SnapshotError(
            "snapshot .wast files missing from suites: " + ", ".join(missing)
        )
    if extra := sorted(assigned_files - wast_files):
        raise SnapshotError(
            "suite entries that are not snapshot .wast files: " + ", ".join(extra)
        )

    return ComponentSnapshot(
        root=upstream_root,
        repository=repository,
        commit=commit,
        upstream_tree=upstream_tree,
        upstream_path=upstream_path,
        wasm_tools_version=wasm_tools_version,
        suites=suites,
    )
