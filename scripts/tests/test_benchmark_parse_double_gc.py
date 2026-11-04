"""The performance fixture must retain the property and all index spaces."""
import importlib.util
from pathlib import Path
import unittest
import json
import statistics
import tempfile
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "parse_double_benchmark", Path(__file__).parents[1] / "benchmark_parse_double_gc.py")
BENCHMARK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BENCHMARK)


class PropertyIsolationTests(unittest.TestCase):
    def fixture(self):
        return ('(module\n'
                '  (import "host" "assert" (func $assert (;0;) (param i32)))\n'
                '  (import "host" "tag" (tag $tag (;0;) (param i32)))\n'
                '  (func $init (;1;)\n    i32.const 20000\n    drop\n  )\n'
                f'  (func $property_{BENCHMARK.TEST_SYMBOL} (;2;)\n'
                '    i32.const 20000\n    call $assert\n  )\n'
                '  (start $init)\n)\n')

    def test_only_target_count_changes_and_failures_still_trap(self):
        pure = BENCHMARK.isolate_property(self.fixture(), 1000)
        self.assertNotIn('(import ', pure)
        self.assertIn('(func $assert (;0;) (param i32) unreachable)', pure)
        self.assertIn('(tag $tag (;0;) (param i32))', pure)
        self.assertIn('(start $init)', pure)
        self.assertEqual(pure.count('i32.const 20000'), 1)
        self.assertEqual(pure.count('i32.const 1000'), 1)
        self.assertIn('call $assert', pure)
        self.assertIn('struct.get $moonbit.enum 0 i32.const 1 i32.eq', pure)

    def test_ambiguous_property_is_rejected(self):
        source = self.fixture().replace('    call $assert', '    i32.const 20000\n    call $assert')
        with self.assertRaisesRegex(ValueError, 'iteration count'):
            BENCHMARK.isolate_property(source, 1000)

    def test_unexpected_host_memory_is_rejected(self):
        source = self.fixture().replace('  (start', '  (import "host" "memory" (memory 1))\n  (start')
        with self.assertRaisesRegex(ValueError, 'unexpected import'):
            BENCHMARK.isolate_property(source, 1000)


class PhaseMeasurementTests(unittest.TestCase):
    def test_int64_phase_strings_are_numeric_before_medians(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "phases.json"
            samples = []
            for value in ("9", "10", "11"):
                path.write_text(json.dumps({"phases_us": {
                    "compile": value, "invoke_including_hostcalls": value}}))
                with patch.object(BENCHMARK.subprocess, "run") as run:
                    run.return_value.stdout = "1\n"
                    run.return_value.stderr = ""
                    samples.append(BENCHMARK.measure(
                        ["test-engine"], {"WASMOON_RUN_METRICS_FILE": str(path)},
                        1)["phases_us"]["compile"])
            self.assertEqual(statistics.median(samples), 10)

    def test_missing_cold_compile_is_a_measurement_error(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "phases.json"
            path.write_text(json.dumps({"phases_us": {"invoke_including_hostcalls": "1"}}))
            with patch.object(BENCHMARK.subprocess, "run") as run:
                run.return_value.stdout = "1\n"
                with self.assertRaisesRegex(RuntimeError, "cold Wasmoon"):
                    BENCHMARK.measure(["test-engine"],
                                      {"WASMOON_RUN_METRICS_FILE": str(path)}, 1)


if __name__ == '__main__':
    unittest.main()
