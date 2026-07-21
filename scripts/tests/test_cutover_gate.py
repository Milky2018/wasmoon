from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


PERF = load_module("run_machv_cutover_perf", ROOT / "scripts/run_machv_cutover_perf.py")


class CutoverPerfTests(unittest.TestCase):
    def test_checked_in_workload_manifest_satisfies_coverage_contract(self) -> None:
        manifest = json.loads(
            (ROOT / "docs/perf/machv-migration/workloads.json").read_text(
                encoding="utf-8"
            )
        )
        workloads = PERF.validate_workload_manifest(manifest)
        PERF.validate_workload_files(ROOT, workloads)
        self.assertGreaterEqual(
            sum(workload["tier"] == "real_module" for workload in workloads), 3
        )
        self.assertGreaterEqual(
            sum(
                workload["tier"] == "large_compile_stress"
                for workload in workloads
            ),
            2,
        )

    def test_workload_manifest_rejects_missing_required_feature(self) -> None:
        manifest = json.loads(
            (ROOT / "docs/perf/machv-migration/workloads.json").read_text(
                encoding="utf-8"
            )
        )
        for workload in manifest["workloads"]:
            workload["features"] = [
                feature
                for feature in workload["features"]
                if feature != "tail_call"
            ]
        with self.assertRaisesRegex(RuntimeError, "tail_call"):
            PERF.validate_workload_manifest(manifest)

    def test_ratio_stats_are_geometric_and_report_noise(self) -> None:
        stats = PERF.ratio_stats([1.0, 1.21])
        self.assertAlmostEqual(stats["geometric_mean_ratio"], 1.1)
        self.assertGreater(stats["upper_95_ratio"], 1.1)
        self.assertGreater(stats["coefficient_of_variation"], 0.0)

    def test_threshold_crossing_confidence_bound_is_inconclusive(self) -> None:
        failures: list[str] = []
        PERF.record_failure(
            failures,
            "runtime fixture",
            {
                "geometric_mean_ratio": 1.01,
                "upper_95_ratio": 1.06,
                "coefficient_of_variation": 0.02,
            },
            1.05,
        )
        self.assertEqual(
            failures,
            ["runtime fixture: inconclusive upper 95% ratio 1.060000 exceeds 1.050000"],
        )

    def test_corpus_confidence_bound_preserves_equal_workload_weighting(self) -> None:
        stats = PERF.corpus_ratio_stats(
            [
                [1.00, 1.00],
                [1.21, 1.21, 1.21, 1.21],
            ]
        )
        self.assertAlmostEqual(stats["geometric_mean_ratio"], 1.10)
        self.assertAlmostEqual(stats["upper_95_ratio"], 1.10)

    def test_corpus_threshold_uses_confidence_bound(self) -> None:
        stats = PERF.corpus_ratio_stats(
            [
                [1.00, 1.02],
                [1.00, 1.02, 1.00, 1.02],
            ]
        )
        self.assertLess(stats["geometric_mean_ratio"], 1.03)
        self.assertGreater(stats["upper_95_ratio"], 1.03)

        failures: list[str] = []
        PERF.record_failure(failures, "runtime corpus", stats, 1.03)
        self.assertEqual(len(failures), 1)
        self.assertIn("inconclusive upper 95% ratio", failures[0])


class GateManifestTests(unittest.TestCase):
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


if __name__ == "__main__":
    unittest.main()
