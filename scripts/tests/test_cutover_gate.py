from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[2]


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


SMITH = load_module("smith_diff_run", ROOT / "scripts/smith_diff/run.py")
PERF = load_module(
    "run_machv_cutover_perf", ROOT / "scripts/run_machv_cutover_perf.py"
)


def git(repo: Path, *args: str) -> str:
    return subprocess.check_output(
        ["git", *args],
        cwd=repo,
        text=True,
    ).strip()


def commit_file(repo: Path, path: str, content: str, message: str) -> str:
    target = repo / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding="utf-8")
    git(repo, "add", path)
    git(repo, "commit", "-m", message)
    return git(repo, "rev-parse", "HEAD")


def init_git_repo(directory: str) -> Path:
    repo = Path(directory)
    git(repo, "init")
    git(repo, "config", "user.email", "cutover-test@example.com")
    git(repo, "config", "user.name", "Cutover Test")
    return repo


class SmithGateTests(unittest.TestCase):
    def test_smith_seed_is_reproducible_and_case_specific(self) -> None:
        first = SMITH._deterministic_seed(7, 3, 65)
        self.assertEqual(first, SMITH._deterministic_seed(7, 3, 65))
        self.assertNotEqual(first, SMITH._deterministic_seed(7, 4, 65))
        self.assertEqual(len(first), 65)

    def test_interpreter_oracle_never_requires_or_runs_wasmtime(self) -> None:
        checked: list[str] = []

        def which(tool: str) -> str:
            checked.append(tool)
            return f"/tools/{tool}"

        with mock.patch.object(SMITH.shutil, "which", side_effect=which):
            SMITH._ensure_tools("interpreter")
        self.assertEqual(checked, ["wasm-tools"])
        with mock.patch.object(SMITH, "_run_wasmtime") as wasmtime:
            outcome = SMITH._run_oracle(
                Path("case.wasm"),
                authority="interpreter",
                timeout_s=1.0,
            )
        wasmtime.assert_not_called()
        self.assertEqual(outcome.kind, "not-run")

    def test_run_rejects_an_empty_generated_corpus(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            with (
                mock.patch.object(
                    sys,
                    "argv",
                    [
                        "smith-diff",
                        "run",
                        "--count",
                        "0",
                        "--oracle",
                        "interpreter",
                        "--out",
                        directory,
                    ],
                ),
                mock.patch.object(SMITH, "_ensure_tools"),
                mock.patch.object(
                    SMITH,
                    "_build_template_wasm",
                    return_value=Path(directory) / "template.wasm",
                ),
                mock.patch.object(
                    SMITH,
                    "_smith_config_for_run",
                    return_value=Path(directory) / "smith_config.json",
                ),
            ):
                self.assertEqual(SMITH.main(), 2)

    def test_run_rejects_generation_errors(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            generation_error = SMITH.Outcome(
                kind="error",
                rc=1,
                stdout="",
                stderr="failed to generate module",
            )
            with (
                mock.patch.object(
                    sys,
                    "argv",
                    [
                        "smith-diff",
                        "run",
                        "--count",
                        "1",
                        "--oracle",
                        "interpreter",
                        "--out",
                        directory,
                    ],
                ),
                mock.patch.object(SMITH, "_ensure_tools"),
                mock.patch.object(
                    SMITH,
                    "_build_template_wasm",
                    return_value=Path(directory) / "template.wasm",
                ),
                mock.patch.object(
                    SMITH,
                    "_smith_config_for_run",
                    return_value=Path(directory) / "smith_config.json",
                ),
                mock.patch.object(
                    SMITH,
                    "_generate_module",
                    return_value=generation_error,
                ),
            ):
                self.assertEqual(SMITH.main(), 2)


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

    def test_runtime_normalization_preserves_sub_nanosecond_values(self) -> None:
        self.assertEqual(PERF.normalize_runtime_ns(101, 100, 10), 0.1)

    def test_runtime_normalization_rejects_non_positive_signal(self) -> None:
        with self.assertRaisesRegex(RuntimeError, "not positive"):
            PERF.normalize_runtime_ns(100, 100, 10)

    def test_compile_only_workload_does_not_require_runtime_samples(self) -> None:
        self.assertIsNone(
            PERF.workload_runtime_stats(
                {"metrics": ["jit_compile_time", "code_size"]},
                [{"legacy": {}, "candidate": {}}],
            )
        )

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
    def test_init_records_fixed_legacy_and_workload_inputs(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            manifest = Path(directory) / "manifest.json"
            result = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "scripts/cutover_gate_manifest.py"),
                    "init",
                    "--manifest",
                    str(manifest),
                    "--baseline",
                    str(ROOT / "docs/perf/machv-migration/baseline.json"),
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
            self.assertEqual(
                payload["legacy_commit"],
                "af3fa2d99598554baab7614e0b08584ab5f8d9da",
            )
            self.assertIn("baseline_sha256", payload["inputs"])
            self.assertIn("workloads_sha256", payload["inputs"])

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
        self.assertIn("scripts/check_committed_diff.py", workflow)
        self.assertNotIn("run_gate git-diff-check 'git diff --check'", workflow)
        self.assertIn("--name paired-performance", workflow)
        self.assertIn("scripts/run_machv_cutover_perf.py", workflow)
        self.assertIn("--perf-report", workflow)
        self.assertIn("smith,paired-performance", workflow)

    def test_committed_diff_gate_rejects_committed_whitespace_damage(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            repo = init_git_repo(directory)
            base = commit_file(repo, "file.txt", "clean\n", "base")
            head = commit_file(repo, "file.txt", "trailing   \n", "damage")
            result = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "scripts/check_committed_diff.py"),
                    "--base",
                    base,
                    "--head",
                    head,
                ],
                cwd=repo,
                check=False,
            )
            self.assertNotEqual(result.returncode, 0)

    def test_closing_detector_handles_late_migration_issue_ids(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            repo = init_git_repo(directory)
            for issue_id in (203, 206, 244, 300):
                base = commit_file(
                    repo,
                    f"issues/ISS-{issue_id:03d}.md",
                    "## Metadata\n- Status: open\n",
                    f"open ISS-{issue_id:03d}",
                )
                edited = commit_file(
                    repo,
                    f"issues/ISS-{issue_id:03d}.md",
                    "## Metadata\n- Status: open\n\n## Notes\n- progress\n",
                    f"edit ISS-{issue_id:03d}",
                )
                unchanged = subprocess.run(
                    [
                        sys.executable,
                        str(ROOT / "scripts/detect_cutover_closing_change.py"),
                        "--base",
                        base,
                        "--head",
                        edited,
                    ],
                    cwd=repo,
                    check=False,
                )
                self.assertEqual(unchanged.returncode, 1)
                closed = commit_file(
                    repo,
                    f"issues/ISS-{issue_id:03d}.md",
                    "## Metadata\n- Status: closed\n",
                    f"close ISS-{issue_id:03d}",
                )
                detected = subprocess.run(
                    [
                        sys.executable,
                        str(ROOT / "scripts/detect_cutover_closing_change.py"),
                        "--base",
                        edited,
                        "--head",
                        closed,
                    ],
                    cwd=repo,
                    check=False,
                )
                self.assertEqual(detected.returncode, 0)

    def test_closing_detector_triggers_for_gate_changes_and_fails_safe(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            repo = init_git_repo(directory)
            base = commit_file(repo, "README.md", "base\n", "base")
            head = commit_file(
                repo,
                ".github/workflows/perf.yml",
                "name: performance\n",
                "change gate",
            )
            script = str(ROOT / "scripts/detect_cutover_closing_change.py")
            changed = subprocess.run(
                [sys.executable, script, "--base", base, "--head", head],
                cwd=repo,
                check=False,
            )
            self.assertEqual(changed.returncode, 0)
            missing_base = subprocess.run(
                [sys.executable, script, "--base", "missing", "--head", head],
                cwd=repo,
                check=False,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            self.assertEqual(missing_base.returncode, 0)

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
