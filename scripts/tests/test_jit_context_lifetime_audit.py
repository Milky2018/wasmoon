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
            'extern "c" fn c_jit_context_ptr(Context) -> Int64\n'
        )
        (jit_package / "native_context.mbt").write_text(
            "fn allocate() { c_jit_context_ptr(context) |> ignore }\n"
            "fn borrow() { c_jit_context_ptr(context) |> ignore }\n"
            "fn inspect() { c_jit_context_ptr(context) |> ignore }\n"
        )
        (jit_package / "pkg.generated.mbti").write_text("type NativeJITContext\n")
        public_jit = root / "modules/wasmoon/jit"
        public_jit.mkdir(parents=True)
        (public_jit / "pkg.generated.mbti").write_text("type JITModule\n")
        return jit_package

    def test_scoped_file_can_be_refactored_without_call_count_budget(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.create_fixture(root)
            self.assertEqual(audit_repo(root), [])

    def test_scoped_file_can_be_renamed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            jit_package = self.create_fixture(root)
            (jit_package / "native_context.mbt").rename(
                jit_package / "managed_context_owner.mbt"
            )
            self.assertEqual(audit_repo(root), [])

    def test_raw_extractor_outside_scoped_file_fails(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            jit_package = self.create_fixture(root)
            (jit_package / "bypass.mbt").write_text(
                "fn bypass() { c_jit_context_ptr(context) |> ignore }\n"
            )
            self.assertTrue(
                any(
                    "confined to one implementation file" in failure
                    for failure in audit_repo(root)
                )
            )

    def test_public_raw_pointer_escape_fails(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            jit_package = self.create_fixture(root)
            (jit_package / "pkg.generated.mbti").write_text(
                "pub fn NativeJITContext::ptr(Self) -> Int64\n"
            )
            self.assertTrue(
                any(
                    "forbidden raw-pointer API" in failure
                    for failure in audit_repo(root)
                )
            )


if __name__ == "__main__":
    unittest.main()
