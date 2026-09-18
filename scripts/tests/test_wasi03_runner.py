"""The regression gate never turns startup errors or new failures into passes."""
import importlib.util
import os
import subprocess
import tempfile
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
spec = importlib.util.spec_from_file_location("run_wasi03", SCRIPTS / "run_wasi03.py")
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class GateTests(unittest.TestCase):
    @unittest.skipUnless(os.name == "nt", "Windows native exit status")
    def test_process_wrapper_preserves_native_exception_status(self):
        with tempfile.TemporaryDirectory() as directory:
            guest = Path(directory) / "exit.py"
            guest.write_text("import ctypes; ctypes.windll.kernel32.ExitProcess(0xc00000fd)\n")
            result = subprocess.run([sys.executable, str(SCRIPTS / "wasi03_process.py"),
                                     "command", sys.executable, str(guest)],
                                    capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 0xc00000fd, result.stderr)

    def test_guest_wait_uses_configured_watchdog_timeout(self):
        import wasi03_testsuite_adapter as adapter
        with patch.dict("os.environ", {"WASI03_TIMEOUT": "120"}):
            self.assertEqual(adapter.get_timeout_seconds(), 120)

    def test_checkout_line_endings_do_not_change_json_identity(self):
        lf = b'{\n  "exit": 0\n}\n'
        crlf = lf.replace(b"\n", b"\r\n")
        self.assertEqual(runner.corpus_digest("case.json", lf), runner.corpus_digest("case.json", crlf))
        self.assertNotEqual(runner.corpus_digest("case.wasm", lf), runner.corpus_digest("case.wasm", crlf))
        self.assertNotEqual(runner.corpus_digest("case.json", lf), runner.corpus_digest("case.json", lf.replace(b"0", b"1")))

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
