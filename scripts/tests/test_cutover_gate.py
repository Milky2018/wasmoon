from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]

class GateManifestTests(unittest.TestCase):
    def test_init_records_only_current_tree_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            manifest = Path(directory) / "manifest.json"
            result = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "scripts/cutover_gate_manifest.py"),
                    "init",
                    "--manifest",
                    str(manifest),
                    "--kind",
                    "target-cutover",
                    "--target",
                    "linux-amd64",
                ],
                cwd=ROOT,
                check=False,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            self.assertEqual(result.returncode, 0)
            payload = json.loads(manifest.read_text(encoding="utf-8"))
            self.assertNotIn("legacy_commit", payload)
            self.assertNotIn("performance", payload)
            self.assertNotIn("inputs", payload)

    def test_finalize_rejects_a_missing_required_command(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            manifest = Path(directory) / "manifest.json"
            manifest.write_text(
                json.dumps(
                    {
                        "commands": [],
                        "artifacts": [],
                        "failures": [],
                        "decision": "incomplete",
                    }
                ),
                encoding="utf-8",
            )
            result = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "scripts/cutover_gate_manifest.py"),
                    "finalize",
                    "--manifest",
                    str(manifest),
                    "--required",
                    "target-identity",
                ],
                check=False,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            self.assertEqual(result.returncode, 2)
            payload = json.loads(manifest.read_text(encoding="utf-8"))
            self.assertEqual(payload["decision"], "fail")
            self.assertEqual(
                payload["failures"],
                ["missing required commands: target-identity"],
            )

    def test_combine_rejects_a_failed_required_job(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "source.json"
            combined = root / "combined.json"
            source.write_text(
                json.dumps(
                    {
                        "candidate_commit": "abc123",
                        "kind": "target-cutover",
                        "target": "linux-amd64",
                        "decision": "pass",
                    }
                ),
                encoding="utf-8",
            )
            result = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "scripts/cutover_gate_manifest.py"),
                    "combine",
                    "--out",
                    str(combined),
                    "--required-job",
                    "build-macos=failure",
                    str(source),
                ],
                check=False,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            self.assertEqual(result.returncode, 2)
            payload = json.loads(combined.read_text(encoding="utf-8"))
            self.assertEqual(payload["decision"], "fail")
            self.assertEqual(payload["required_jobs"], {"build-macos": "failure"})
            self.assertEqual(
                payload["failures"],
                ["required job 'build-macos' result is 'failure'"],
            )

    def test_closing_workflow_records_common_quality_commands(self) -> None:
        workflow = (ROOT / ".github/workflows/check.yml").read_text(
            encoding="utf-8"
        )
        for command in ("moon-fmt", "moon-info", "git-diff-check"):
            self.assertIn(f"run_gate {command}", workflow)
        self.assertIn(
            "--required target-identity,moon-fmt,moon-info,git-diff-check,",
            workflow,
        )

    def test_closing_workflow_requires_common_build_jobs(self) -> None:
        workflow = (ROOT / ".github/workflows/check.yml").read_text(
            encoding="utf-8"
        )
        self.assertIn(
            "needs: [detect-machv-cutover, machv-cutover, "
            "build-ubuntu-sanitizer, build-macos, build-ubuntu-amd64]",
            workflow,
        )
        self.assertIn(
            "--required-job build-macos=${{ needs.build-macos.result }}",
            workflow,
        )
        self.assertIn(
            "--required-job build-ubuntu-amd64=${{ "
            "needs.build-ubuntu-amd64.result }}",
            workflow,
        )

    def test_closing_workflow_has_no_legacy_performance_gate(self) -> None:
        workflow = (ROOT / ".github/workflows/check.yml").read_text(
            encoding="utf-8"
        )
        self.assertNotIn("paired-performance", workflow)
        self.assertNotIn("run_machv_cutover_perf", workflow)
        self.assertNotIn("perf-report", workflow)


if __name__ == "__main__":
    unittest.main()
