from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

from audit_component_security import audit_repo


class ComponentSecurityAuditTests(unittest.TestCase):
    def create_fixture(self, root: Path) -> None:
        manifest = {
            "schema_version": 1,
            "oracle": {"name": "wasmtime", "version": "45.0.0"},
            "source_checks": {
                "stable_interface": "interface.mbti",
                "facade": "facade.mbt",
                "validator": "validator.mbt",
                "forbidden_termination_roots": ["untrusted"],
                "forbidden_termination_patterns": ["abort(", "try!"],
                "termination_allowlist": [],
                "unsafe_conversion_allowlist": [],
            },
            "evidence": [
                {"name": name}
                for name in [
                    "fuzz",
                    "wasmtime-differential",
                    "logical-resource-lifecycle",
                    "native-sanitizers",
                    "large-component-stress",
                ]
            ],
        }
        (root / "docs").mkdir()
        (root / "docs/component-hardening.json").write_text(
            json.dumps(manifest),
            encoding="utf-8",
        )
        (root / "interface.mbti").write_text("pub type Component\n", encoding="utf-8")
        (root / "facade.mbt").write_text(
            "@component_model.validate_component_with_config(component)\n"
            "self.linker.instantiate(name, component)\n",
            encoding="utf-8",
        )
        (root / "validator.mbt").write_text(
            '"effective type size exceeds the limit"\n'
            '"type nesting is too deep"\n',
            encoding="utf-8",
        )
        (root / "untrusted").mkdir()
        (root / "untrusted/input.mbt").write_text("raise InvalidInput\n")
        runtime = root / "modules/wasmoon/component/runtime_impl"
        runtime.mkdir(parents=True)
        for name in [
            "async_types.mbt",
            "canon_stream.mbt",
            "canon_future.mbt",
            "host_stream.mbt",
        ]:
            (runtime / name).write_text(
                "cleanup_closed_stream()\ncleanup_closed_future()\n",
                encoding="utf-8",
            )
        scripts = root / "scripts"
        scripts.mkdir()
        script_names = [
            "component_fuzz.py",
            "component_differential.py",
            "component_stress.py",
            "install_wasmtime_oracle.py",
        ]
        for name in script_names:
            (scripts / name).write_text("# fixture\n", encoding="utf-8")
        workflows = root / ".github/workflows"
        workflows.mkdir(parents=True)
        ci = (
            "\n".join(script_names)
            + "\nruntime_cleanup_wbtest.mbt\n"
            + "actions/upload-artifact@v4\n"
            + "if: always()\n"
            + "target/component-hardening\n"
        )
        (workflows / "check.yml").write_text(ci, encoding="utf-8")
        (workflows / "component-hardening.yml").write_text(ci, encoding="utf-8")

    def assert_failed(self, root: Path, name: str) -> None:
        checks = {check.name: check for check in audit_repo(root)}
        self.assertFalse(checks[name].passed, checks[name].detail)

    def test_complete_fixture_passes(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.create_fixture(root)
            self.assertTrue(all(check.passed for check in audit_repo(root)))

    def test_missing_evidence_fails(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.create_fixture(root)
            manifest_path = root / "docs/component-hardening.json"
            manifest = json.loads(manifest_path.read_text())
            manifest["evidence"].pop()
            manifest_path.write_text(json.dumps(manifest))
            self.assert_failed(root, "manifest-evidence")

    def test_stable_interface_leak_fails(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.create_fixture(root)
            (root / "interface.mbti").write_text("pub type runtime_impl.State\n")
            self.assert_failed(root, "stable-interface-isolation")

    def test_instantiate_before_validation_fails(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.create_fixture(root)
            (root / "facade.mbt").write_text(
                "self.linker.instantiate(name, component)\n"
                "@component_model.validate_component_with_config(component)\n"
            )
            self.assert_failed(root, "validate-before-instantiate")

    def test_missing_validator_limit_fails(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.create_fixture(root)
            (root / "validator.mbt").write_text(
                '"effective type size exceeds the limit"\n'
            )
            self.assert_failed(root, "validator-limits")

    def test_unstructured_termination_fails(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.create_fixture(root)
            (root / "untrusted/input.mbt").write_text('abort("bad input")\n')
            self.assert_failed(root, "structured-termination")

    def test_unreviewed_unsafe_conversion_fails(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.create_fixture(root)
            (root / "untrusted/input.mbt").write_text(
                "value.unsafe_to_char()\n"
            )
            self.assert_failed(root, "unsafe-conversion-budget")

    def test_missing_cleanup_boundary_fails(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.create_fixture(root)
            runtime = root / "modules/wasmoon/component/runtime_impl"
            for path in runtime.iterdir():
                path.write_text("fn unrelated() -> Unit { () }\n")
            self.assert_failed(root, "resource-cleanup-boundary")

    def test_missing_hardening_tool_fails(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.create_fixture(root)
            (root / "scripts/component_fuzz.py").unlink()
            self.assert_failed(root, "hardening-tools")

    def test_missing_ci_reference_fails(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.create_fixture(root)
            for path in (root / ".github/workflows").iterdir():
                path.write_text("target/component-hardening\n")
            self.assert_failed(root, "hardening-ci")


if __name__ == "__main__":
    unittest.main()
