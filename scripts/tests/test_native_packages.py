"""Exercise the native runner CLI with a deterministic toolchain fixture."""
from pathlib import Path
import json
import os
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class NativeRunnerTests(unittest.TestCase):
    @unittest.skipIf(os.name == "nt", "fixture uses a POSIX executable script")
    def test_unicode_build_log_does_not_prevent_inventory_execution(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            moon = root / "moon"
            moon.write_text("#!" + sys.executable + "\n" +
                            "import sys\n" +
                            "if '--build-only' in sys.argv: sys.stdout.buffer.write('编译完成\\n'.encode('utf-8'))\n" +
                            "elif '--outline' in sys.argv: print('1. fixture/package test')\n" +
                            "else: print('Total tests: 1, passed: 1, failed: 0.')\n", encoding="utf-8")
            moon.chmod(0o755)
            output = root / "results"
            environment = os.environ | {"PATH": str(root) + os.pathsep + os.environ["PATH"],
                                         "PYTHONIOENCODING": "cp1252"}
            result = subprocess.run([sys.executable, str(ROOT / "scripts/run_native_packages.py"),
                                     "--output", str(output)], env=environment,
                                    capture_output=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr.decode("utf-8", errors="replace"))
            self.assertIn("编译完成", result.stdout.decode("utf-8"))
            evidence = json.loads((output / "results.json").read_text())
            self.assertEqual(evidence["inventory_count"], 1)
            self.assertEqual(evidence["packages"][0]["executed_tests"], 1)
            self.assertFalse(evidence["build"]["timed_out"])
