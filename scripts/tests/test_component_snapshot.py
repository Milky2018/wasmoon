from __future__ import annotations

import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

from component_snapshot import SnapshotError, validate_snapshot


class ComponentSnapshotTests(unittest.TestCase):
    def create_snapshot(self, root: Path) -> None:
        component_root = root / "component-spec"
        upstream = component_root / "upstream"
        suites = component_root / "suites"
        upstream.mkdir(parents=True)
        suites.mkdir()
        contents = {
            "README.md": b"upstream\n",
            "stable.wast": b"(component)\n",
            "async.wast": b"(component)\n",
            "future.wast": b"(component)\n",
        }
        files = []
        for name, content in contents.items():
            (upstream / name).write_bytes(content)
            files.append(
                {
                    "path": name,
                    "sha256": hashlib.sha256(content).hexdigest(),
                }
            )
        (suites / "stable-0.2.txt").write_text("stable.wast\n", encoding="utf-8")
        (suites / "async-0.3.txt").write_text("async.wast\n", encoding="utf-8")
        (suites / "future-gated.txt").write_text(
            "future.wast\n",
            encoding="utf-8",
        )
        (component_root / "SNAPSHOT.json").write_text(
            json.dumps(
                {
                    "schema_version": 1,
                    "repository": "https://example.invalid/component-model.git",
                    "commit": "1" * 40,
                    "upstream_tree": "2" * 40,
                    "upstream_path": "test",
                    "wasm_tools_version": "1.254.0",
                    "files": files,
                }
            ),
            encoding="utf-8",
        )

    def test_accepts_exact_disjoint_exhaustive_snapshot(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.create_snapshot(root)
            snapshot = validate_snapshot(root)
            self.assertEqual(snapshot.commit, "1" * 40)
            self.assertEqual(
                {name: len(files) for name, files in snapshot.suites.items()},
                {
                    "stable-0.2": 1,
                    "async-0.3": 1,
                    "future-gated": 1,
                },
            )

    def test_rejects_modified_upstream_file(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.create_snapshot(root)
            (root / "component-spec/upstream/stable.wast").write_text(
                "(component (type))\n",
                encoding="utf-8",
            )
            with self.assertRaisesRegex(SnapshotError, "hash mismatch"):
                validate_snapshot(root)

    def test_corrections_preserve_and_pin_both_sources(self) -> None:
        for mutation in (None, "source", "corrected", "unlisted", "upstream"):
            with self.subTest(mutation=mutation), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                self.create_snapshot(root)
                component = root / "component-spec"
                corrected = component / "corrections/async.wast"
                corrected.parent.mkdir()
                corrected.write_text("(component)\n(assert_return (invoke \"g\"))\n")
                entry = {
                    "path": "async.wast",
                    "upstream_sha256": hashlib.sha256(b"(component)\n").hexdigest(),
                    "sha256": hashlib.sha256(corrected.read_bytes()).hexdigest(),
                    "reason": "Replace an obsolete temporary restriction.",
                }
                if mutation == "source":
                    entry["upstream_sha256"] = "0" * 64
                elif mutation == "corrected":
                    corrected.write_text("(component)\n")
                elif mutation == "unlisted":
                    (corrected.parent / "extra.wast").write_text("(component)\n")
                elif mutation == "upstream":
                    (component / "upstream/async.wast").write_text("(component)\n;; edited\n")
                (component / "CORRECTIONS.json").write_text(
                    json.dumps({"schema_version": 1, "files": [entry]})
                )
                if mutation is None:
                    snapshot = validate_snapshot(root)
                    self.assertEqual(snapshot.corrections, {Path("async.wast"): corrected})
                    self.assertEqual(snapshot.suites["async-0.3"], (Path("async.wast"),))
                else:
                    with self.assertRaises(SnapshotError):
                        validate_snapshot(root)

    def test_rejects_file_assigned_to_two_suites(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.create_snapshot(root)
            (root / "component-spec/suites/async-0.3.txt").write_text(
                "stable.wast\n",
                encoding="utf-8",
            )
            with self.assertRaisesRegex(SnapshotError, "appears in both"):
                validate_snapshot(root)

    def test_rejects_unassigned_wast_file(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.create_snapshot(root)
            (root / "component-spec/suites/future-gated.txt").write_text(
                "# empty\n",
                encoding="utf-8",
            )
            with self.assertRaisesRegex(SnapshotError, "at least one"):
                validate_snapshot(root)

    def test_rejects_an_unexpected_fourth_suite(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.create_snapshot(root)
            (root / "component-spec/suites/other.txt").write_text(
                "stable.wast\n",
                encoding="utf-8",
            )
            with self.assertRaisesRegex(SnapshotError, "unexpected suite"):
                validate_snapshot(root)


if __name__ == "__main__":
    unittest.main()
