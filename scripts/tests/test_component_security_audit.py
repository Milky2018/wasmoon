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
                "validator": "validator.mbt",
                "validator_interface": "validator.mbti",
                "runtime_interface": "runtime.mbti",
                "interface_scan_root": "modules/wasmoon",
                "implementation_owner_roots": [
                    "Milky2018/wasmoon/component/runtime_impl",
                    "Milky2018/wasmoon/component_engine",
                    "Milky2018/wasmoon/component_host",
                    "Milky2018/wasmoon/component_native",
                ],
                "implementation_interface_allowlist": [
                    "modules/wasmoon/component_native/pkg.generated.mbti",
                    "modules/wasmoon/wasi_component/pkg.generated.mbti",
                ],
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
        (root / "validator.mbt").write_text(
            '"effective type size exceeds the limit"\n'
            '"type nesting is too deep"\n',
            encoding="utf-8",
        )
        (root / "validator.mbti").write_text(
            "type ValidatedComponent\n"
            "pub fn ValidatedComponent::component(Self)"
            " -> @model.Component raise @model.ComponentParseError\n"
            "pub fn validate_component_for_instantiation_with_config"
            "(@model.Component, ComponentValidationConfig)"
            " -> ValidatedComponent raise ComponentValidationError\n",
            encoding="utf-8",
        )
        (root / "runtime.mbti").write_text(
            "type ComponentClosure\n"
            "pub fn ComponentLinker::add_component"
            "(Self, String, @component_model.ValidatedComponent) -> Unit\n"
            "pub fn ComponentLinker::instantiate"
            "(Self, String, @component_model.ValidatedComponent)"
            " -> ComponentInstance raise ComponentRuntimeError\n",
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
        for name in [
            "component_fuzz.py",
            "component_differential.py",
            "component_stress.py",
            "install_wasmtime_oracle.py",
        ]:
            (scripts / name).write_text("# fixture\n", encoding="utf-8")
        workflows = root / ".github/workflows"
        workflows.mkdir(parents=True)
        (workflows / "check.yml").write_text(
            "runtime_cleanup_wbtest.mbt\n"
            "run native sanitizer checks\n"
            "stable-0.2\n"
            "async-0.3\n"
            "future-gated\n",
            encoding="utf-8",
        )

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

    def test_missing_interface_owner_config_fails(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.create_fixture(root)
            manifest_path = root / "docs/component-hardening.json"
            manifest = json.loads(manifest_path.read_text())
            del manifest["source_checks"]["implementation_owner_roots"]
            manifest_path.write_text(json.dumps(manifest))
            self.assert_failed(root, "interface-owner-config")

    def test_stable_interface_leak_fails(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.create_fixture(root)
            (root / "interface.mbti").write_text(
                "import {\n"
                '  "Milky2018/wasmoon/component/runtime_impl",\n'
                "}\n"
                "pub fn state() -> @runtime_impl.State\n",
                encoding="utf-8",
            )
            self.assert_failed(root, "stable-interface-isolation")

    def test_reexported_implementation_adapter_fails(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.create_fixture(root)
            (root / "interface.mbti").write_text(
                "import {\n"
                '  "Milky2018/wasmoon/component_engine",\n'
                "}\n"
                "pub using @component_engine {type ComponentEngine}\n",
                encoding="utf-8",
            )
            self.assert_failed(root, "stable-interface-isolation")

    def test_aliased_nested_implementation_owner_fails(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.create_fixture(root)
            (root / "interface.mbti").write_text(
                "import {\n"
                '  "Milky2018/wasmoon/component_native/internal" @engine,\n'
                "}\n"
                "pub fn engine() -> @engine.CoreExecutionEngine\n",
                encoding="utf-8",
            )
            self.assert_failed(root, "stable-interface-isolation")

    def test_similarly_prefixed_public_owner_passes(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.create_fixture(root)
            (root / "interface.mbti").write_text(
                "import {\n"
                '  "Milky2018/wasmoon/component_native_api",\n'
                "}\n"
                "pub fn engine() -> @component_native_api.Engine\n",
                encoding="utf-8",
            )
            checks = {check.name: check for check in audit_repo(root)}
            self.assertTrue(
                checks["stable-interface-isolation"].passed,
                checks["stable-interface-isolation"].detail,
            )

    def test_unused_implementation_import_passes(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.create_fixture(root)
            (root / "interface.mbti").write_text(
                "import {\n"
                '  "Milky2018/wasmoon/component_native/internal" @engine,\n'
                "}\n"
                "pub fn local_engine() -> LocalEngine\n",
                encoding="utf-8",
            )
            checks = {check.name: check for check in audit_repo(root)}
            self.assertTrue(
                checks["stable-interface-isolation"].passed,
                checks["stable-interface-isolation"].detail,
            )

    def test_generic_adapter_under_another_package_fails(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.create_fixture(root)
            path = (
                root
                / "modules"
                / "wasmoon"
                / "alternate_adapter"
                / "pkg.generated.mbti"
            )
            path.parent.mkdir(parents=True)
            path.write_text(
                "import {\n"
                '  "Milky2018/wasmoon/component/runtime_impl" @engine,\n'
                "}\n"
                "pub fn from_session_factory(\n"
                "  factory : () -> @engine.CoreExecutionEngine,\n"
                ") -> Adapter\n",
                encoding="utf-8",
            )
            self.assert_failed(root, "adapter-interface-isolation")

    def test_reviewed_low_level_interface_passes(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.create_fixture(root)
            path = (
                root
                / "modules"
                / "wasmoon"
                / "component_native"
                / "pkg.generated.mbti"
            )
            path.parent.mkdir(parents=True)
            path.write_text(
                "import {\n"
                '  "Milky2018/wasmoon/component/runtime_impl" @engine,\n'
                "}\n"
                "pub fn open_session() -> @engine.CoreExecutionEngine\n",
                encoding="utf-8",
            )
            checks = {check.name: check for check in audit_repo(root)}
            self.assertTrue(
                checks["adapter-interface-isolation"].passed,
                checks["adapter-interface-isolation"].detail,
            )

    def test_raw_component_instantiation_boundary_fails(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.create_fixture(root)
            (root / "runtime.mbti").write_text(
                "pub fn ComponentLinker::instantiate"
                "(Self, String, @model.Component)"
                " -> ComponentInstance raise ComponentRuntimeError\n",
                encoding="utf-8",
            )
            self.assert_failed(root, "validate-before-instantiate")

    def test_raw_component_import_boundary_fails(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.create_fixture(root)
            (root / "runtime.mbti").write_text(
                "type ComponentClosure\n"
                "pub fn ComponentLinker::add_component"
                "(Self, String, @model.Component) -> Unit\n"
                "pub fn ComponentLinker::instantiate"
                "(Self, String, @component_model.ValidatedComponent)"
                " -> ComponentInstance raise ComponentRuntimeError\n",
                encoding="utf-8",
            )
            self.assert_failed(root, "validate-before-instantiate")

    def test_alias_returning_evidence_accessor_fails(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.create_fixture(root)
            (root / "validator.mbti").write_text(
                "type ValidatedComponent\n"
                "pub fn ValidatedComponent::component(Self)"
                " -> @model.Component\n"
                "pub fn validate_component_for_instantiation_with_config"
                "(@model.Component, ComponentValidationConfig)"
                " -> ValidatedComponent raise ComponentValidationError\n",
                encoding="utf-8",
            )
            self.assert_failed(root, "validate-before-instantiate")

    def test_public_register_fails(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.create_fixture(root)
            (root / "runtime.mbti").write_text(
                "type ComponentClosure\n"
                "pub fn ComponentLinker::add_component"
                "(Self, String, @component_model.ValidatedComponent) -> Unit\n"
                "pub fn ComponentLinker::instantiate"
                "(Self, String, @component_model.ValidatedComponent)"
                " -> ComponentInstance raise ComponentRuntimeError\n"
                "pub fn ComponentLinker::register"
                "(Self, String, ComponentInstance) -> Unit\n",
                encoding="utf-8",
            )
            self.assert_failed(root, "validate-before-instantiate")

    def test_constructible_component_closure_fails(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.create_fixture(root)
            (root / "runtime.mbti").write_text(
                "pub(all) struct ComponentClosure {\n"
                "  component : @model.Component\n"
                "  outer_stack : Array[ComponentInstance]\n"
                "}\n"
                "pub fn ComponentLinker::add_component"
                "(Self, String, @component_model.ValidatedComponent) -> Unit\n"
                "pub fn ComponentLinker::instantiate"
                "(Self, String, @component_model.ValidatedComponent)"
                " -> ComponentInstance raise ComponentRuntimeError\n",
                encoding="utf-8",
            )
            self.assert_failed(root, "validate-before-instantiate")

    def test_missing_validation_evidence_producer_fails(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.create_fixture(root)
            (root / "validator.mbti").write_text(
                "pub struct ValidatedComponent {\n"
                "  component : @model.Component\n"
                "}\n",
                encoding="utf-8",
            )
            self.assert_failed(root, "validate-before-instantiate")

    def test_constructible_validation_evidence_fails(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.create_fixture(root)
            (root / "validator.mbti").write_text(
                "pub struct ValidatedComponent {\n"
                "  component : @model.Component\n"
                "}\n"
                "pub fn validate_component_for_instantiation_with_config"
                "(@model.Component, ComponentValidationConfig)"
                " -> ValidatedComponent raise ComponentValidationError\n",
                encoding="utf-8",
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

    def test_missing_platform_ci_reference_fails(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.create_fixture(root)
            for path in (root / ".github/workflows").iterdir():
                path.write_text("run native sanitizer checks\n")
            self.assert_failed(root, "platform-ci")


if __name__ == "__main__":
    unittest.main()
