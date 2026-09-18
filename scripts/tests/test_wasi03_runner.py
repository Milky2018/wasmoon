"""The regression gate never turns startup errors or new failures into passes."""
import importlib.util
from pathlib import Path
import sys
import unittest

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
spec = importlib.util.spec_from_file_location("run_wasi03", SCRIPTS / "run_wasi03.py")
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class GateTests(unittest.TestCase):
    def test_only_exact_reviewed_failure_is_acknowledged(self):
        for name, markers in runner.KNOWN_DIFFERENCES.items():
            result = {"name": name, "status": "fail", "failures": [
                "Wait(exit_code=0) failed: expected 0, got 125\n" + "\n".join(markers)]}
            self.assertFalse(runner.gate_failure(result, True))
            self.assertTrue(runner.gate_failure(result, False))
            self.assertEqual(result["status"], "fail")
            result["failures"][0] = "UnknownImport"
            self.assertTrue(runner.gate_failure(result, True))

    def test_timeouts_harness_errors_and_unexpected_passes_fail(self):
        for status in ["timeout", "harness_error", "pass"]:
            self.assertTrue(runner.gate_failure({"name": "http-fields", "status": status}, True))
        self.assertFalse(runner.gate_failure({"name": "random", "status": "pass"}, True))
        self.assertTrue(runner.gate_failure({"name": "random", "status": "fail"}, True))
