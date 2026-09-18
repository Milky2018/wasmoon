from __future__ import annotations

import importlib.util
import json
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


PARITY = load_module(
    "benchmark_algorithms_parity",
    ROOT / "scripts/benchmark_algorithms_parity.py",
)


class AlgorithmsParityTests(unittest.TestCase):
    def test_workload_pair_order_alternates_deterministically(self) -> None:
        self.assertEqual(PARITY.pair_engine_order(0), ["wasmoon", "wasmtime"])
        self.assertEqual(PARITY.pair_engine_order(1), ["wasmtime", "wasmoon"])

    def test_both_caches_are_output_local_and_cleared_per_workload(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "summary-output" / "jit-cache"
            workload = Path("examples/algorithms/aead strange.wasm")
            caches = PARITY.prepare_isolated_caches(root, workload)
            (caches.wasmoon / "stale.cwasm").write_bytes(b"old")
            (caches.wasmtime / "stale.bin").write_bytes(b"old")

            recreated = PARITY.prepare_isolated_caches(root, workload)

            self.assertEqual(recreated.root, root / "aead_strange")
            self.assertEqual(list(recreated.wasmoon.iterdir()), [])
            self.assertEqual(list(recreated.wasmtime.iterdir()), [])
            config = recreated.wasmtime_config.read_text(encoding="utf-8")
            self.assertIn("[cache]", config)
            self.assertIn(str(recreated.wasmtime.resolve()), config)

    def test_cache_run_records_fresh_artifact(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            cache = Path(directory)

            def create_artifact(command, timeout_sec, *, extra_env=None):
                self.assertEqual(command, ["wasmoon", "run", "case.wasm"])
                self.assertEqual(timeout_sec, 5)
                self.assertEqual(extra_env["WASMOON_JIT_CACHE_DIR"], str(cache))
                (cache / "current.cwasm").write_bytes(b"artifact")
                return PARITY.RunResult(
                    command=command,
                    exit_code=0,
                    duration_sec=1.0,
                    stdout="10",
                    stderr="",
                    parsed_value=10.0,
                    timeout=False,
                )

            with mock.patch.object(PARITY, "run_one", side_effect=create_artifact):
                result = PARITY.record_cache_run(
                    ["wasmoon", "run", "case.wasm"],
                    5,
                    cache,
                    extra_env={"WASMOON_JIT_CACHE_DIR": str(cache)},
                )

            self.assertIsNone(result.freshly_compiled)
            self.assertTrue(result.cache_files_changed)
            self.assertEqual(result.cache_files_before, [])
            self.assertEqual(result.cache_files_after, ["current.cwasm"])

    def test_runtime_evidence_is_independent_of_disk_changes(self) -> None:
        reports = [
            {"schema_version": 1, "freshly_compiled": True, "cache_hit": False,
             "cache_write_succeeded": False},
            {"schema_version": 1, "freshly_compiled": False, "cache_hit": True,
             "cache_write_succeeded": None},
            {"schema_version": 1, "freshly_compiled": True, "cache_hit": False,
             "cache_write_succeeded": None},
        ]
        for report in reports:
            with self.subTest(report=report), tempfile.TemporaryDirectory() as directory:
                caches = PARITY.prepare_isolated_caches(Path(directory), Path("a.wasm"))
                def fake_run(command, timeout_sec, *, extra_env=None):
                    Path(extra_env["WASMOON_JIT_CACHE_REPORT"]).write_text(json.dumps(report))
                    return PARITY.RunResult(command, 0, 1.0, "42", "", 42, False)
                with mock.patch.object(PARITY, "run_one", side_effect=fake_run):
                    result = PARITY.run_engine("wasmoon", Path("a.wasm"),
                        wasmoon_bin="wasmoon", wasmtime_bin="wasmtime", timeout_sec=5,
                        caches=caches)
                self.assertEqual(result.freshly_compiled, report["freshly_compiled"])
                self.assertEqual(result.cache_hit, report["cache_hit"])
                self.assertEqual(result.cache_write_succeeded, report["cache_write_succeeded"])
                self.assertFalse(result.cache_files_changed)
                self.assertIsNone(result.evidence_error)

    def test_missing_or_invalid_report_never_reuses_stale_evidence(self) -> None:
        for report in [None, [], {"schema_version": 9},
                       {"schema_version": 1, "freshly_compiled": True,
                        "cache_hit": True, "cache_write_succeeded": True}]:
            with self.subTest(report=report), tempfile.TemporaryDirectory() as directory:
                caches = PARITY.prepare_isolated_caches(Path(directory), Path("a.wasm"))
                (caches.root / "wasmoon-jit-report.json").write_text(json.dumps({
                    "schema_version": 1, "freshly_compiled": True,
                    "cache_hit": False, "cache_write_succeeded": True}))
                def fake_run(command, timeout_sec, *, extra_env=None):
                    if report is not None:
                        Path(extra_env["WASMOON_JIT_CACHE_REPORT"]).write_text(json.dumps(report))
                    return PARITY.RunResult(command, 0, 1.0, "42", "", 42, False)
                with mock.patch.object(PARITY, "run_one", side_effect=fake_run):
                    result = PARITY.run_engine("wasmoon", Path("a.wasm"),
                        wasmoon_bin="wasmoon", wasmtime_bin="wasmtime", timeout_sec=5,
                        caches=caches)
                self.assertIsNone(result.freshly_compiled)
                self.assertIsNone(result.cache_hit)
                self.assertIsNotNone(result.evidence_error)

    def test_main_rejects_missing_compilation_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "a.wasm").write_bytes(b"wasm")
            summary = root / "out" / "summary.json"
            def fake_run(command, timeout_sec, *, extra_env=None):
                return PARITY.RunResult(command, 0, 1.0, "42", "", 42, False)
            with mock.patch.object(PARITY, "run_one", side_effect=fake_run), mock.patch.object(
                sys, "argv", ["benchmark", "--strict", "--workloads-dir", str(root),
                              "--summary-file", str(summary)]
            ):
                self.assertEqual(PARITY.main(), 1)
            payload = json.loads(summary.read_text())
            self.assertEqual(payload["rows"][0]["status"], "measurement_error")
            self.assertIsNone(payload["rows"][0]["pair"]["wasmoon"]["freshly_compiled"])
            self.assertIn("unknown", summary.with_suffix(".md").read_text())

    def test_main_runs_each_engine_once_with_separate_cold_caches(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            workloads = root / "workloads"
            workloads.mkdir()
            (workloads / "a.wasm").write_bytes(b"wasm")
            (workloads / "b.wasm").write_bytes(b"wasm")
            summary = root / "out" / "summary.json"
            calls = []

            def fake_run(command, timeout_sec, *, extra_env=None):
                del timeout_sec
                engine = "wasmoon" if command[0] == "wasmoon" else "wasmtime"
                workload = Path(command[-1]).name
                calls.append((workload, engine))
                if engine == "wasmoon":
                    cache = Path(extra_env["WASMOON_JIT_CACHE_DIR"])
                    (cache / "current.cwasm").write_bytes(b"artifact")
                    Path(extra_env["WASMOON_JIT_CACHE_REPORT"]).write_text(json.dumps({
                        "schema_version": 1, "freshly_compiled": True,
                        "cache_hit": False, "cache_write_succeeded": True,
                    }))
                else:
                    self.assertIn("cache=y", command)
                    self.assertIn("parallel-compilation=n", command)
                    config_arg = next(
                        arg for arg in command if arg.startswith("cache-config=")
                    )
                    config_path = Path(config_arg.split("=", 1)[1])
                    directory_line = config_path.read_text(encoding="utf-8").splitlines()[1]
                    cache = Path(json.loads(directory_line.split("=", 1)[1].strip()))
                    (cache / "compiled-module").write_bytes(b"artifact")
                return PARITY.RunResult(
                    command=command,
                    exit_code=0,
                    duration_sec=2.0 if engine == "wasmoon" else 1.0,
                    stdout="2" if engine == "wasmoon" else "1",
                    stderr="",
                    parsed_value=2.0 if engine == "wasmoon" else 1.0,
                    timeout=False,
                )

            with (
                mock.patch.object(PARITY, "run_one", side_effect=fake_run),
                mock.patch.object(
                    sys,
                    "argv",
                    [
                        "benchmark-algorithms-parity",
                        "--wasmoon",
                        "wasmoon",
                        "--wasmtime",
                        "wasmtime",
                        "--workloads-dir",
                        str(workloads),
                        "--summary-file",
                        str(summary),
                    ],
                ),
            ):
                self.assertEqual(PARITY.main(), 0)

            self.assertEqual(
                calls,
                [
                    ("a.wasm", "wasmoon"),
                    ("a.wasm", "wasmtime"),
                    ("b.wasm", "wasmtime"),
                    ("b.wasm", "wasmoon"),
                ],
            )
            payload = json.loads(summary.read_text(encoding="utf-8"))
            self.assertEqual(payload["schema_version"], 4)
            self.assertEqual(payload["config"]["runs_per_engine"], 1)
            self.assertEqual(
                payload["config"]["cache_policy"],
                "cold-isolated-per-workload",
            )
            self.assertFalse(payload["config"]["wasmtime_parallel_compilation"])
            for row in payload["rows"]:
                self.assertEqual(row["pair"]["value_ratio"], 2.0)
                self.assertEqual(row["pair"]["wall_ratio"], 2.0)
                self.assertTrue(row["pair"]["wasmoon"]["freshly_compiled"])
                self.assertIsNone(row["pair"]["wasmtime"]["freshly_compiled"])
                self.assertTrue(row["pair"]["wasmtime"]["cache_files_changed"])
                self.assertNotIn("pairs", row)
                self.assertNotIn("paired_ratios", row)


if __name__ == "__main__":
    unittest.main()
