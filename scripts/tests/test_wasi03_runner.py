"""Verify corpus identity and explicit HTTP contract profile selection."""
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

    def test_contract_guests_are_pinned_and_complete(self):
        guests = runner.http_contract_guests(SCRIPTS.parent / "tests/wasi03/http-contract")
        self.assertEqual(set(guests), {"http-fields.wasm", "http-request.wasm"})

    def test_contract_guest_and_patch_corruption_are_rejected(self):
        import shutil
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "profile"
            shutil.copytree(SCRIPTS.parent / "tests/wasi03/http-contract", root)
            guest = root / "http-fields.wasm"
            original = guest.read_bytes()
            guest.write_bytes(original + b"corrupt")
            with self.assertRaisesRegex(ValueError, "guest checksum mismatch"):
                runner.http_contract_guests(root)
            guest.write_bytes(original)
            patch_file = root / "expectations.patch"
            patch_file.write_bytes(patch_file.read_bytes() + b"corrupt")
            with self.assertRaisesRegex(ValueError, "patch checksum mismatch"):
                runner.http_contract_guests(root)
