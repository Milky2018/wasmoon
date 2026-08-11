from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

from audit_jit_context_lifetimes import audit_repo


class JITContextLifetimeAuditTests(unittest.TestCase):
    def create_fixture(self, root: Path) -> Path:
        jit_package = root / "modules/wasmoon_jit"
        jit_package.mkdir(parents=True)
        (jit_package / "native_ffi.mbt").write_text(
            'priv type JITContext\n'
            '#borrow(context)\n'
            'extern "c" fn context_is_valid(context : JITContext) -> Int = '
            '"wasmoon_jit_context_is_valid"\n',
            encoding="utf-8",
        )
        (jit_package / "pkg.generated.mbti").write_text(
            "type NativeJITContext\n", encoding="utf-8"
        )
        public_jit = root / "modules/wasmoon/jit"
        public_jit.mkdir(parents=True)
        (public_jit / "pkg.generated.mbti").write_text(
            "type JITModule\n", encoding="utf-8"
        )
        return jit_package

    def test_opaque_managed_context_operations_pass(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.create_fixture(root)
            self.assertEqual(audit_repo(root), [])

    def test_raw_extractor_declaration_fails(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            jit_package = self.create_fixture(root)
            (jit_package / "native_ffi.mbt").write_text(
                'extern "c" fn raw(context : JITContext) -> Int64 = '
                '"wasmoon_jit_context_ptr"\n',
                encoding="utf-8",
            )
            self.assertTrue(
                any("raw JIT context seam" in failure for failure in audit_repo(root))
            )

    def test_reported_return_escape_fails(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            jit_package = self.create_fixture(root)
            (jit_package / "bypass.mbt").write_text(
                "fn bypass(context, body) -> Int64 {\n"
                "  let raw = c_jit_context_ptr(context)\n"
                "  defer c_jit_context_keep_alive(context)\n"
                "  body(raw)\n"
                "  raw\n"
                "}\n",
                encoding="utf-8",
            )
            self.assertTrue(
                any("raw JIT context seam" in failure for failure in audit_repo(root))
            )

    def test_scoped_callback_seam_fails(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            jit_package = self.create_fixture(root)
            (jit_package / "owner.mbt").write_text(
                "fn[T] NativeJITContext::with_ptr(self, body) -> T {\n"
                "  body(c_jit_context_ptr(self.handle))\n"
                "}\n",
                encoding="utf-8",
            )
            self.assertTrue(
                any("raw JIT context seam" in failure for failure in audit_repo(root))
            )

    def test_public_raw_pointer_escape_fails(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            jit_package = self.create_fixture(root)
            (jit_package / "pkg.generated.mbti").write_text(
                "pub fn NativeJITContext::ptr(Self) -> Int64\n",
                encoding="utf-8",
            )
            self.assertTrue(
                any(
                    "forbidden raw-pointer API" in failure
                    for failure in audit_repo(root)
                )
            )


if __name__ == "__main__":
    unittest.main()
