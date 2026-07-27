#!/usr/bin/env python3
"""Import an exact Component Model test/ tree and refresh its hash manifest."""

from __future__ import annotations

import argparse
import io
import json
import shutil
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

from component_snapshot import SnapshotError, sha256_file, validate_snapshot


DEFAULT_REPOSITORY = "https://github.com/WebAssembly/component-model.git"


def git_output(source: Path, *args: str) -> str:
    try:
        result = subprocess.run(
            ["git", "-C", str(source), *args],
            check=True,
            capture_output=True,
            text=True,
        )
    except subprocess.CalledProcessError as error:
        detail = error.stderr.strip() or error.stdout.strip() or str(error)
        raise RuntimeError(detail) from error
    return result.stdout.strip()


def prepare_source(repository: str, commit: str, source: Path | None) -> tuple[Path, str]:
    if source is not None:
        resolved = git_output(source, "rev-parse", f"{commit}^{{commit}}")
        return source, resolved

    checkout = Path(tempfile.mkdtemp(prefix="component-model-sync-git-"))
    try:
        subprocess.run(["git", "init", "-q", str(checkout)], check=True)
        subprocess.run(
            ["git", "-C", str(checkout), "fetch", "--depth=1", repository, commit],
            check=True,
        )
        resolved = git_output(checkout, "rev-parse", "FETCH_HEAD^{commit}")
    except Exception:
        shutil.rmtree(checkout, ignore_errors=True)
        raise
    return checkout, resolved


def extract_tree(source: Path, commit: str, upstream_path: str, output: Path) -> str:
    tree = git_output(source, "rev-parse", f"{commit}:{upstream_path}")
    try:
        archive = subprocess.run(
            [
                "git",
                "-C",
                str(source),
                "archive",
                "--format=tar",
                commit,
                upstream_path,
            ],
            check=True,
            capture_output=True,
        ).stdout
    except subprocess.CalledProcessError as error:
        detail = error.stderr.decode(errors="replace").strip() or str(error)
        raise RuntimeError(detail) from error

    with tarfile.open(fileobj=io.BytesIO(archive), mode="r:") as tar:
        tar.extractall(output, filter="data")
    extracted = output / upstream_path
    if not extracted.is_dir():
        raise RuntimeError(f"archive did not contain {upstream_path!r}")
    return tree


def write_snapshot(
    repo_root: Path,
    *,
    repository: str,
    commit: str,
    tree: str,
    upstream_path: str,
    wasm_tools_version: str,
) -> None:
    upstream_root = repo_root / "component-spec" / "upstream"
    files = []
    for path in sorted(item for item in upstream_root.rglob("*") if item.is_file()):
        files.append(
            {
                "path": path.relative_to(upstream_root).as_posix(),
                "sha256": sha256_file(path),
            }
        )
    payload = {
        "schema_version": 1,
        "repository": repository,
        "commit": commit,
        "upstream_tree": tree,
        "upstream_path": upstream_path,
        "wasm_tools_version": wasm_tools_version,
        "files": files,
    }
    snapshot_path = repo_root / "component-spec" / "SNAPSHOT.json"
    snapshot_path.write_text(
        json.dumps(payload, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--commit", required=True, help="Exact upstream commit")
    parser.add_argument(
        "--repository",
        default=DEFAULT_REPOSITORY,
        help=f"Upstream repository (default: {DEFAULT_REPOSITORY})",
    )
    parser.add_argument(
        "--source",
        type=Path,
        help="Existing upstream Git checkout; avoids a network fetch",
    )
    parser.add_argument(
        "--upstream-path",
        default="test",
        help="Path to import from the upstream commit (default: test)",
    )
    parser.add_argument(
        "--wasm-tools-version",
        required=True,
        help="Exact wasm-tools version used to parse this snapshot",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parent.parent
    temporary_source = args.source is None
    source: Path | None = None
    extract_root: Path | None = None
    try:
        source, resolved_commit = prepare_source(
            args.repository,
            args.commit,
            args.source,
        )
        extract_root = Path(tempfile.mkdtemp(prefix="component-model-sync-tree-"))
        tree = extract_tree(
            source,
            resolved_commit,
            args.upstream_path,
            extract_root,
        )
        destination = repo_root / "component-spec" / "upstream"
        shutil.rmtree(destination, ignore_errors=True)
        shutil.copytree(extract_root / args.upstream_path, destination)
        write_snapshot(
            repo_root,
            repository=args.repository,
            commit=resolved_commit,
            tree=tree,
            upstream_path=args.upstream_path,
            wasm_tools_version=args.wasm_tools_version,
        )
        snapshot = validate_snapshot(repo_root)
    except (OSError, RuntimeError, SnapshotError, subprocess.CalledProcessError) as error:
        print(f"Component snapshot sync failed: {error}", file=sys.stderr)
        return 1
    finally:
        if extract_root is not None:
            shutil.rmtree(extract_root, ignore_errors=True)
        if temporary_source and source is not None:
            shutil.rmtree(source, ignore_errors=True)

    print(
        f"Synced {snapshot.repository}@{snapshot.commit}:{snapshot.upstream_path} "
        f"(tree {snapshot.upstream_tree})"
    )
    for name, files in snapshot.suites.items():
        print(f"  {name}: {len(files)} .wast files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
