"""Pinned upstream corpus bytes survive Windows Git checkout filters."""
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]


class CorpusCheckoutTests(unittest.TestCase):
    def test_autocrlf_preserves_pinned_text(self):
        files = subprocess.check_output(
            ["git", "ls-files", "wasm-tests/wasmtime/upstream"], cwd=ROOT,
            text=True, encoding="utf-8").splitlines()
        misc = next(path for path in files if path.endswith(".wast"))
        for path in ["component-spec/upstream/README.md",
                     "wasi-tests/wasmtime/upstream/LICENSE", misc,
                     "modules/wasmoon/wasi_component/wit/preview2/deps/filesystem/types.wit",
                     "modules/wasmoon/wasi_component/wit/preview3/deps/cli/stdio.wit",
                     *subprocess.check_output(
                         ["git", "ls-files", "component-spec/corrections"], cwd=ROOT,
                         text=True, encoding="utf-8").splitlines()]:
            with self.subTest(path=path):
                original = subprocess.check_output(["git", "show", f"HEAD:{path}"], cwd=ROOT)
                self.assertIn(b"\n", original)
                checkout = subprocess.check_output(
                    ["git", "-c", "core.autocrlf=true", "cat-file", "--filters", f"HEAD:{path}"],
                    cwd=ROOT)
                self.assertEqual(checkout, original)
