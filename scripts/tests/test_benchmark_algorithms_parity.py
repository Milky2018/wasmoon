from __future__ import annotations

import importlib.util
import json
import math
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
    def test_pair_order_alternates_deterministically(self) -> None:
        self.assertEqual(PARITY.pair_engine_order(0), ["wasmoon", "wasmtime"])
        self.assertEqual(PARITY.pair_engine_order(1), ["wasmtime", "wasmoon"])
        self.assertEqual(PARITY.pair_engine_order(2), ["wasmoon", "wasmtime"])
        self.assertEqual(PARITY.pair_engine_order(3), ["wasmtime", "wasmoon"])

    def test_paired_ratio_summary_keeps_median_and_geometric_mean(self) -> None:
        summary = PARITY.paired_ratio_summary([1.0, 2.0, 8.0])
        self.assertEqual(summary["count"], 3)
        self.assertEqual(summary["median"], 2.0)
        self.assertTrue(
            math.isclose(summary["geometric_mean"], 2.5198420997897464)
        )

    def test_cache_is_rooted_in_output_area_and_cleared_per_workload(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "summary-output" / "jit-cache"
            workload = Path("examples/algorithms/aead strange.wasm")
            cache = PARITY.prepare_isolated_cache(root, workload)
            stale = cache / "stale.cwasm"
            stale.write_bytes(b"old")
            recreated = PARITY.prepare_isolated_cache(root, workload)
            self.assertEqual(recreated, root / "aead_strange")
            self.assertFalse(stale.exists())
            self.assertEqual(list(recreated.iterdir()), [])

    def test_wasmoon_run_records_fresh_cache_creation_without_wasmtime(self) -> None:
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
                result = PARITY.run_wasmoon(
                    ["wasmoon", "run", "case.wasm"],
                    5,
                    cache,
                )
            self.assertTrue(result.freshly_compiled)
            self.assertEqual(result.cache_files_before, [])
            self.assertEqual(result.cache_files_after, ["current.cwasm"])

    def test_main_writes_raw_pairs_and_cache_provenance_without_wasmtime(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            workloads = root / "workloads"
            workloads.mkdir()
            (workloads / "case.wasm").write_bytes(b"wasm")
            summary = root / "out" / "summary.json"

            def fake_run(command, timeout_sec, *, extra_env=None):
                del timeout_sec
                is_wasmoon = command[0] == "wasmoon"
                if is_wasmoon:
                    cache = Path(extra_env["WASMOON_JIT_CACHE_DIR"])
                    artifact = cache / "current.cwasm"
                    if not artifact.exists():
                        artifact.write_bytes(b"artifact")
                return PARITY.RunResult(
                    command=command,
                    exit_code=0,
                    duration_sec=2.0 if is_wasmoon else 1.0,
                    stdout="2" if is_wasmoon else "1",
                    stderr="",
                    parsed_value=2.0 if is_wasmoon else 1.0,
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
                        "--iterations",
                        "2",
                        "--warmup",
                        "0",
                    ],
                ),
            ):
                self.assertEqual(PARITY.main(), 0)

            payload = json.loads(summary.read_text(encoding="utf-8"))
            row = payload["rows"][0]
            self.assertEqual(
                [pair["order"] for pair in row["pairs"]],
                [
                    ["wasmoon", "wasmtime"],
                    ["wasmtime", "wasmoon"],
                ],
            )
            self.assertEqual(
                row["paired_ratios"],
                {
                    "value": {
                        "count": 2,
                        "median": 2.0,
                        "geometric_mean": 2.0,
                    },
                    "wall": {
                        "count": 2,
                        "median": 2.0,
                        "geometric_mean": 2.0,
                    },
                },
            )
            self.assertEqual(row["cache"]["measured_fresh_compilations"], 1)
            self.assertEqual(row["cache"]["final_files"], ["current.cwasm"])


if __name__ == "__main__":
    unittest.main()
