"""Verify corpus identity and explicit HTTP contract profile selection."""
import importlib.util
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
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
    def test_loopback_endpoint_binds_without_reverse_lookup(self):
        from wasi03_upstream_runner import bind_endpoint

        class Endpoint(ThreadingHTTPServer):
            server_bind = bind_endpoint

        with patch("socket.getfqdn", side_effect=AssertionError("reverse lookup")), \
             patch("socket.gethostbyaddr", side_effect=AssertionError("reverse lookup")):
            with Endpoint(("127.0.0.1", 0), BaseHTTPRequestHandler) as server:
                host, port = server.server_address
                self.assertEqual(host, "127.0.0.1")
                self.assertGreater(port, 0)
                self.assertEqual(server.server_name, host)
                self.assertEqual(server.server_port, port)

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
        guests = runner.http_contract_guests(SCRIPTS.parent / "tests/wasi/p3/http-contract")
        self.assertEqual(set(guests), {"http-fields.wasm", "http-request.wasm"})

    def test_contract_guest_and_patch_corruption_are_rejected(self):
        import shutil
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / "profile"
            shutil.copytree(SCRIPTS.parent / "tests/wasi/p3/http-contract", root)
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

    def test_case_workspaces_are_removed_and_reports_survive(self):
        import contextlib
        import io
        import json

        for outcome in ["pass", "fail", "missing", "malformed", "timeout"]:
            with self.subTest(outcome=outcome), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                upstream = root / "upstream"
                suite = upstream / "tests/rust/testsuite/wasm32-wasip3"
                suite.mkdir(parents=True)
                guest = suite / "case.wasm"
                guest.write_bytes(b"\0asm")
                (suite / "manifest.json").write_text("{}")
                (root / "scripts").mkdir()
                (root / "scripts/wasi03-corpus.json").write_text(json.dumps({
                    "revision": runner.PIN,
                    "files": {guest.name: runner.corpus_digest(guest.name, guest.read_bytes())},
                }))
                sentinel = root / "sentinel.txt"
                sentinel.write_text("keep")
                # Exercise the real subprocess lifecycle, including inaccessible
                # fixture directories and symlinks left by guest filesystem tests.
                (root / "scripts/wasi03_upstream_runner.py").write_text(f'''
import json, os, sys, time
from pathlib import Path
args = sys.argv
work = Path(args[args.index("-t") + 1])
result = Path(args[args.index("--json-output-location") + 1])
(result.parent / "work-path.txt").write_text(str(work))
assert (work / "case.wasm").read_bytes() == b"\\0asm"
assert (work / "fs-tests.dir/a.txt").read_bytes() == b"fixture"
if os.name != "nt":
    (work / "outside").symlink_to({str(sentinel)!r})
    locked = work / "locked"
    locked.mkdir()
    (locked / "file").write_text("temporary")
    locked.chmod(0)
print("fixture executed", flush=True)
outcome = {outcome!r}
if outcome == "timeout":
    time.sleep(60)
elif outcome == "malformed":
    result.write_text("invalid json")
elif outcome != "missing":
    result.write_text(json.dumps({{"results": [{{"tests": [{{
        "outcome": outcome, "failures": []
    }}]}}]}}))
''')
                binary = root / "wasmoon"
                binary.write_bytes(b"test runtime identity")
                output = root / "reports"
                argv = ["run_wasi03", "--upstream", str(upstream), "--wasmoon", str(binary),
                        "--output", str(output), "--timeout", "2"]

                def git_output(command, **kwargs):
                    return runner.PIN + "\n" if "rev-parse" in command else b"fixture"

                with patch.object(runner, "ROOT", root), patch.object(sys, "argv", argv), \
                     patch.object(runner.subprocess, "check_output", side_effect=git_output), \
                     contextlib.redirect_stdout(io.StringIO()):
                    if outcome == "malformed":
                        with self.assertRaises(json.JSONDecodeError):
                            runner.main()
                    else:
                        self.assertEqual(runner.main(), int(outcome != "pass"))
                workspaces = []
                for engine in ["jit", "interp"]:
                    report = output / engine / "case"
                    work = Path((report / "work-path.txt").read_text())
                    workspaces.append(work)
                    self.assertFalse(work.exists(), f"leaked {outcome} workspace: {work}")
                    self.assertFalse(work.is_relative_to(output.parent), str(work))
                    self.assertIn("fixture executed", (report / "log.txt").read_text())
                self.assertNotEqual(*workspaces)
                self.assertEqual(sentinel.read_text(), "keep")
                if outcome != "malformed":
                    expected = "harness_error" if outcome == "missing" else outcome
                    self.assertEqual(json.loads((output / "summary.json").read_text())["counts"],
                                     {expected: 2})
