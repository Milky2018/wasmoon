from __future__ import annotations

import io
import json
import random
import subprocess
import sys
import tarfile
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

from component_fuzz import classify_validation, mutate
from component_hardening_lib import (
    ProcessResult,
    arithmetic_case,
    classify_wasmoon,
    classify_wasmtime,
)
from component_stress import (
    deep_type_component,
    large_function_component,
    wide_type_component,
)
from install_wasmtime_oracle import safe_extract


def process(
    *,
    returncode: int = 0,
    stdout: str = "",
    stderr: str = "",
    timed_out: bool = False,
) -> ProcessResult:
    return ProcessResult(
        command=["test"],
        returncode=returncode,
        stdout=stdout,
        stderr=stderr,
        timed_out=timed_out,
        duration_sec=0,
    )


class ComponentHardeningTests(unittest.TestCase):
    def test_mutations_are_deterministic_and_cover_every_mode(self) -> None:
        data = bytes(range(64))
        first = [mutate(data, random.Random(17), index) for index in range(5)]
        second = [mutate(data, random.Random(17), index) for index in range(5)]
        self.assertEqual(first, second)
        self.assertEqual(
            [name for name, _ in first],
            ["truncate", "bit-flip", "insert", "delete", "section-length"],
        )

    def test_validation_timeout_and_signal_are_campaign_failures(self) -> None:
        self.assertEqual(
            classify_validation(process(timed_out=True)),
            (False, "timeout"),
        )
        self.assertEqual(
            classify_validation(process(returncode=-9)),
            (False, "signal"),
        )

    def test_semantic_outcomes_do_not_merge_failure_classes(self) -> None:
        timeout = classify_wasmoon(process(timed_out=True))
        signal = classify_wasmoon(process(returncode=-11))
        trap = classify_wasmoon(
            process(
                returncode=1,
                stdout=json.dumps(
                    {"ok": False, "phase": "invoke", "detail": "guest trap"}
                ),
            )
        )
        error = classify_wasmoon(
            process(
                returncode=1,
                stdout=json.dumps(
                    {"ok": False, "phase": "parse", "detail": "bad component"}
                ),
            )
        )
        malformed = classify_wasmoon(process(returncode=1, stdout=""))
        self.assertEqual(
            [timeout.kind, signal.kind, trap.kind, error.kind, malformed.kind],
            ["timeout", "signal", "trap", "error", "malformed"],
        )

    def test_wasmtime_trap_is_distinct_from_tool_error(self) -> None:
        trap = classify_wasmtime(
            process(returncode=1, stderr="error: wasm trap: out of bounds")
        )
        error = classify_wasmtime(
            process(returncode=1, stderr="error: unknown option")
        )
        self.assertEqual((trap.kind, error.kind), ("trap", "error"))

    def test_zero_case_campaign_is_rejected_before_tool_lookup(self) -> None:
        result = subprocess.run(
            [
                sys.executable,
                str(ROOT / "scripts/component_fuzz.py"),
                "--mutations",
                "0",
                "--valid-cases",
                "0",
            ],
            cwd=ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("must execute at least one case", result.stderr)

    def test_generated_cases_are_seed_stable(self) -> None:
        self.assertEqual(arithmetic_case(19, 4), arithmetic_case(19, 4))
        self.assertNotEqual(arithmetic_case(19, 4), arithmetic_case(19, 5))

    def test_stress_generators_scale_requested_dimensions(self) -> None:
        wat, path = large_function_component(7, 4)
        self.assertEqual(wat.count('(func (export "f'), 7)
        self.assertEqual(path, "nested#next#next#next#calculate")
        self.assertEqual(wide_type_component(9).count('(field "f'), 9)
        self.assertEqual(deep_type_component(6).count("\n  (type $t"), 6)

    def test_archive_extraction_rejects_path_traversal(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive = root / "unsafe.tar.xz"
            with tarfile.open(archive, "w:xz") as tar:
                info = tarfile.TarInfo("../escape")
                payload = b"unsafe"
                info.size = len(payload)
                tar.addfile(info, io.BytesIO(payload))
            with self.assertRaisesRegex(RuntimeError, "unsafe archive member"):
                safe_extract(archive, root / "output")


if __name__ == "__main__":
    unittest.main()
