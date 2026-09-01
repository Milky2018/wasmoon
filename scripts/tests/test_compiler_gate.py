from __future__ import annotations

import importlib.util
import subprocess
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


SMITH = load_module("smith_diff_run", ROOT / "scripts/smith_diff/run.py")


def git(repo: Path, *args: str) -> str:
    return subprocess.check_output(
        ["git", *args],
        cwd=repo,
        text=True,
    ).strip()


def commit_file(repo: Path, path: str, content: str, message: str) -> str:
    target = repo / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding="utf-8")
    git(repo, "add", path)
    git(repo, "commit", "-m", message)
    return git(repo, "rev-parse", "HEAD")


def init_git_repo(directory: str) -> Path:
    repo = Path(directory)
    git(repo, "init")
    git(repo, "config", "user.email", "cutover-test@example.com")
    git(repo, "config", "user.name", "Cutover Test")
    return repo


class SmithGateTests(unittest.TestCase):
    def test_smith_seed_is_reproducible_and_case_specific(self) -> None:
        first = SMITH._deterministic_seed(7, 3, 65)
        self.assertEqual(first, SMITH._deterministic_seed(7, 3, 65))
        self.assertNotEqual(first, SMITH._deterministic_seed(7, 4, 65))
        self.assertEqual(len(first), 65)

    def test_interpreter_oracle_never_requires_or_runs_wasmtime(self) -> None:
        checked: list[str] = []

        def which(tool: str) -> str:
            checked.append(tool)
            return f"/tools/{tool}"

        with tempfile.TemporaryDirectory() as directory:
            (Path(directory) / "wasmoon").touch()
            with (
                mock.patch.object(SMITH, "REPO_ROOT", Path(directory)),
                mock.patch.object(SMITH.shutil, "which", side_effect=which),
            ):
                SMITH._ensure_tools("interpreter")
        self.assertEqual(checked, ["wasm-tools"])
        with mock.patch.object(SMITH, "_run_wasmtime") as wasmtime:
            outcome = SMITH._run_oracle(
                Path("case.wasm"),
                authority="interpreter",
                timeout_s=1.0,
            )
        wasmtime.assert_not_called()
        self.assertEqual(outcome.kind, "not-run")

    def test_run_rejects_an_empty_generated_corpus(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            with (
                mock.patch.object(
                    sys,
                    "argv",
                    [
                        "smith-diff",
                        "run",
                        "--count",
                        "0",
                        "--oracle",
                        "interpreter",
                        "--out",
                        directory,
                    ],
                ),
                mock.patch.object(SMITH, "_ensure_tools"),
                mock.patch.object(
                    SMITH,
                    "_build_template_wasm",
                    return_value=Path(directory) / "template.wasm",
                ),
                mock.patch.object(
                    SMITH,
                    "_smith_config_for_run",
                    return_value=Path(directory) / "smith_config.json",
                ),
            ):
                self.assertEqual(SMITH.main(), 2)

    def test_run_rejects_generation_errors(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            generation_error = SMITH.Outcome(
                kind="error",
                rc=1,
                stdout="",
                stderr="failed to generate module",
            )
            with (
                mock.patch.object(
                    sys,
                    "argv",
                    [
                        "smith-diff",
                        "run",
                        "--count",
                        "1",
                        "--oracle",
                        "interpreter",
                        "--out",
                        directory,
                    ],
                ),
                mock.patch.object(SMITH, "_ensure_tools"),
                mock.patch.object(
                    SMITH,
                    "_build_template_wasm",
                    return_value=Path(directory) / "template.wasm",
                ),
                mock.patch.object(
                    SMITH,
                    "_smith_config_for_run",
                    return_value=Path(directory) / "smith_config.json",
                ),
                mock.patch.object(
                    SMITH,
                    "_generate_module",
                    return_value=generation_error,
                ),
            ):
                self.assertEqual(SMITH.main(), 2)

    def test_interpreter_oracle_distinguishes_trap_reasons(self) -> None:
        interpreter = SMITH._signature(
            SMITH.Outcome(
                kind="trap",
                rc=1,
                stdout="",
                stderr="Error: out of bounds memory access",
            )
        )
        jit = SMITH._signature(
            SMITH.Outcome(
                kind="trap",
                rc=1,
                stdout="",
                stderr="Error: integer divide by zero",
            )
        )
        self.assertNotEqual(interpreter, jit)
        self.assertTrue(
            SMITH._is_mismatch(("not-run",), interpreter, jit, "interpreter")
        )

    def test_interpreter_oracle_accepts_equivalent_trap_wording(self) -> None:
        interpreter = SMITH._signature(
            SMITH.Outcome(
                kind="trap",
                rc=1,
                stdout="",
                stderr="Error: division by zero",
            )
        )
        jit = SMITH._signature(
            SMITH.Outcome(
                kind="trap",
                rc=1,
                stdout="",
                stderr="wasm trap: integer divide by zero",
            )
        )
        self.assertEqual(interpreter, jit)
        self.assertFalse(
            SMITH._is_mismatch(("not-run",), interpreter, jit, "interpreter")
        )

    def test_interpreter_oracle_distinguishes_runtime_errors(self) -> None:
        interpreter = SMITH._signature(
            SMITH.Outcome(
                kind="error",
                rc=1,
                stdout="",
                stderr="InternalError: interpreter invariant failed",
            )
        )
        jit = SMITH._signature(
            SMITH.Outcome(
                kind="error",
                rc=2,
                stdout="",
                stderr="EmissionFailed: unsupported relocation",
            )
        )
        self.assertNotEqual(interpreter, jit)
        self.assertTrue(
            SMITH._is_mismatch(("not-run",), interpreter, jit, "interpreter")
        )

    def test_interpreter_oracle_accepts_matching_runtime_errors(self) -> None:
        error = SMITH._signature(
            SMITH.Outcome(
                kind="error",
                rc=1,
                stdout="",
                stderr="Error: unsupported shared reference type",
            )
        )
        self.assertFalse(
            SMITH._is_mismatch(("not-run",), error, error, "interpreter")
        )

    def test_interpreter_oracle_rejects_matching_timeouts(self) -> None:
        timeout = SMITH._signature(
            SMITH.Outcome(kind="timeout", rc=124, stdout="", stderr="")
        )
        self.assertTrue(
            SMITH._is_mismatch(("not-run",), timeout, timeout, "interpreter")
        )


class WorkflowGateTests(unittest.TestCase):
    def test_check_workflow_has_only_platform_jobs(self) -> None:
        workflow = (ROOT / ".github/workflows/check.yml").read_text(
            encoding="utf-8"
        )
        self.assertIn("  native-platform:", workflow)
        self.assertIn("name: ${{ matrix.name }}", workflow)
        self.assertIn("name: Linux AMD64", workflow)
        self.assertIn("name: macOS ARM64", workflow)
        self.assertIn("runs-on: ${{ matrix.os }}", workflow)
        self.assertIn("if: runner.os == 'Linux'", workflow)
        self.assertIn("native_test_args: --no-parallelize", workflow)
        self.assertIn("native_test_args: \"\"", workflow)
        self.assertNotIn("  linux-amd64:", workflow)
        self.assertNotIn("  macos-arm64:", workflow)
        self.assertIn("scripts/check_committed_diff.py", workflow)
        self.assertNotIn("  component-model:", workflow)
        self.assertNotIn("  component-hardening:", workflow)
        self.assertNotIn("  build-ubuntu-sanitizer:", workflow)
        self.assertNotIn("paired-performance", workflow)
        self.assertNotIn("--perf-report", workflow)

    def test_committed_diff_gate_rejects_committed_whitespace_damage(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            repo = init_git_repo(directory)
            base = commit_file(repo, "file.txt", "clean\n", "base")
            head = commit_file(repo, "file.txt", "trailing   \n", "damage")
            result = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "scripts/check_committed_diff.py"),
                    "--base",
                    base,
                    "--head",
                    head,
                ],
                cwd=repo,
                check=False,
            )
            self.assertNotEqual(result.returncode, 0)
    def test_platform_jobs_own_component_checks(self) -> None:
        workflow = (ROOT / ".github/workflows/check.yml").read_text(
            encoding="utf-8"
        )
        self.assertEqual(
            workflow.count(
                "python3 -m unittest discover -s scripts/tests "
                "-p 'test_*.py'"
            ),
            1,
        )
        self.assertEqual(
            workflow.count("python3 scripts/audit_component_security.py"),
            1,
        )
        self.assertEqual(
            workflow.count("python3 scripts/audit_jit_context_lifetimes.py"),
            1,
        )
        self.assertEqual(workflow.count("run stable Component Model 0.2"), 1)
        self.assertEqual(workflow.count("run Component Model 0.3 async"), 1)
        self.assertEqual(
            workflow.count("run future-gated Component Model features"),
            1,
        )
        self.assertEqual(
            workflow.count(
                "python3 scripts/find_gc_bugs.py --dir spec/gc --timeout 30"
            ),
            1,
        )

    def test_sanitizer_gate_is_gone(self) -> None:
        # The gate was removed by maintainer decision: it worked by pointing
        # MOON_CC at a wrapper that appended -fsanitize to every compile and
        # link, which is compiler interception. Removing the wrapper removes
        # the gate -- a version without sanitizers would only duplicate the
        # `run native tests` and `build Wasmoon` steps.
        #
        # Interception was never the only supported route, and ISS-390 records
        # the declarative one: `link.native.cc-flags` / `cc-link-flags` in a
        # package's own config. ISS-323's finding was narrower than it read --
        # the CFLAGS/CXXFLAGS/LDFLAGS *environment variables* are ignored, but
        # those config fields are not.
        #
        # This asserts the removal stayed complete rather than half-undone.
        workflow = (ROOT / ".github/workflows/check.yml").read_text(
            encoding="utf-8"
        )
        for token in (
            "run native sanitizer checks",
            "MOON_CC",
            "MOON_AR",
            "ASAN_OPTIONS",
            "UBSAN_OPTIONS",
            "asan_options",
            "sanitizer_build",
            "scripts/native_sanitizer_cc.sh",
            "scripts/verify_native_sanitizers.py",
        ):
            self.assertNotIn(token, workflow)
        for path in (
            "scripts/native_sanitizer_cc.sh",
            "scripts/verify_native_sanitizers.py",
            "scripts/tests/test_verify_native_sanitizers.py",
        ):
            self.assertFalse((ROOT / path).exists(), f"{path} still exists")


if __name__ == "__main__":
    unittest.main()
