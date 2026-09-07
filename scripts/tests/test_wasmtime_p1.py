from __future__ import annotations

from pathlib import Path
import shutil
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

import run_wasmtime_p1 as p1


class P1RunnerTests(unittest.TestCase):
    def test_source_snapshot_is_complete_and_unchanged(self):
        _, names = p1.validate_snapshot()
        self.assertEqual(len(names), 58)

    def test_modified_or_unlisted_upstream_file_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            corpus = Path(tmp) / "corpus"
            shutil.copytree(p1.CORPUS, corpus)
            path = corpus / "upstream/crates/test-programs/src/bin/p1_stdio.rs"
            original = path.read_bytes()
            path.write_bytes(original + b"\n")
            with self.assertRaisesRegex(ValueError, "hash mismatch"):
                p1.validate_snapshot(corpus)
            path.write_bytes(original)
            (path.parent / "p1_new.rs").write_text("fn main() {}")
            with self.assertRaisesRegex(ValueError, "inventory"):
                p1.validate_snapshot(corpus)

    def test_process_failure_and_full_output_are_preserved(self):
        with tempfile.TemporaryDirectory() as tmp:
            result = p1.execute(
                [sys.executable, "-c", "import sys; print('guest assertion', file=sys.stderr); sys.exit(7)"],
                Path(tmp), 5,
            )
            self.assertEqual((result["status"], result["returncode"]), ("fail", 7))
            self.assertEqual(Path(result["stderr"]).read_text(), "guest assertion\n")
            self.assertEqual(p1.verdict([result]), 1)

    def test_timeout_is_not_success(self):
        with tempfile.TemporaryDirectory() as tmp:
            result = p1.execute([sys.executable, "-c", "import time; time.sleep(60)"], Path(tmp), 0.1)
            self.assertEqual(result["status"], "timeout")
            self.assertLess(result["seconds"], 5)
            self.assertEqual(p1.verdict([result]), 1)

    def test_missing_engine_is_a_harness_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            result = p1.execute([str(Path(tmp) / "missing")], Path(tmp), 1)
            self.assertEqual(result["status"], "harness_error")
            self.assertEqual(p1.verdict([result]), 2)

    def test_stdin_eof_and_pending_are_distinct(self):
        code = "import select; print(bool(select.select([0], [], [], 0.05)[0]))"
        for pending, expected in [(False, "True\n"), (True, "False\n")]:
            with self.subTest(pending=pending), tempfile.TemporaryDirectory() as tmp:
                result = p1.execute([sys.executable, "-c", code], Path(tmp), 5, pending_stdin=pending)
                self.assertEqual(result["status"], "pass")
                self.assertEqual(Path(result["stdout"]).read_text(), expected)

    def test_terminal_fixture_really_has_three_terminal_descriptors(self):
        with tempfile.TemporaryDirectory() as tmp:
            code = "import os; assert all(os.isatty(fd) for fd in (0,1,2)); print('terminal')"
            result = p1.execute([sys.executable, "-c", code], Path(tmp), 5, terminal=True)
            self.assertEqual(result["status"], "pass")
            self.assertEqual(Path(result["stdout"]).read_text(), "terminal\n")

    def test_each_case_has_fresh_scratch_and_short_output_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp)
            engine = output / "engine"
            engine.write_text(
                f"#!{sys.executable}\n"
                "from pathlib import Path\n"
                "assert not list(Path('scratch').iterdir())\n"
                "Path('scratch/artifact').write_text('guest output')\n"
                "print('hello, world!', end='')\n"
            )
            engine.chmod(0o755)
            for mode in ("interp", "jit"):
                result = p1.run_case(engine, mode, Path("p1_cli_much_stdout.wasm"), output, 5)
                self.assertEqual(result["status"], "fail")
                self.assertIn("complete expected", result["detail"])
                self.assertFalse((output / mode / "p1_cli_much_stdout/scratch").exists())

    def test_unsupported_and_empty_runs_never_count_as_passes(self):
        self.assertEqual(p1.verdict([]), 1)
        self.assertEqual(p1.verdict([{"status": "unsupported"}]), 1)
        self.assertEqual(p1.verdict([{"status": "pass"}, {"status": "unsupported"}]), 0)

    def test_oracle_does_not_pass_separator_to_guest(self):
        command = p1.command_for(Path("wasmtime"), "wasmtime", Path("guest.wasm"), Path("scratch"), "p1_stdio")
        self.assertEqual(command[command.index("guest.wasm") + 1:], ["."])


if __name__ == "__main__":
    unittest.main()
