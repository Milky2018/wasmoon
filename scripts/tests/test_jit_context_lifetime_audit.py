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
            'extern "c" fn c_jit_context_ptr(Context) -> Int64\n',
            encoding="utf-8",
        )
        (jit_package / "managed_owner.mbt").write_text(
            "///|\n"
            "fn[T] ManagedOwner::borrow(\n"
            "  self : ManagedOwner,\n"
            "  body : (Int64) -> T,\n"
            ") -> T {\n"
            "  let raw = c_jit_context_ptr(self.handle)\n"
            "  defer c_jit_context_keep_alive(self.handle)\n"
            "  body(raw)\n"
            "}\n"
            "\n"
            "///|\n"
            "fn[T] ManagedOwner::inspect(\n"
            "  self : ManagedOwner,\n"
            "  action : (Int64) -> T,\n"
            ") -> T {\n"
            "  let address = c_jit_context_ptr(self.handle)\n"
            "  defer c_jit_context_keep_alive(self.handle)\n"
            "  action(address)\n"
            "}\n"
            "\n"
            "///|\n"
            "fn[T] ManagedOwner::visit(\n"
            "  self : ManagedOwner,\n"
            "  visitor : (Int64) -> T,\n"
            ") -> T {\n"
            "  let pointer = c_jit_context_ptr(self.handle)\n"
            "  defer c_jit_context_keep_alive(self.handle)\n"
            "  visitor(pointer)\n"
            "}\n",
            encoding="utf-8",
        )
        (jit_package / "pkg.generated.mbti").write_text(
            "type ManagedOwner\n", encoding="utf-8"
        )
        public_jit = root / "modules/wasmoon/jit"
        public_jit.mkdir(parents=True)
        (public_jit / "pkg.generated.mbti").write_text(
            "type JITModule\n", encoding="utf-8"
        )
        return jit_package

    def test_structurally_scoped_accessors_pass_without_name_or_count_rules(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.create_fixture(root)
            self.assertEqual(audit_repo(root), [])

    def test_owner_file_extraction_without_keep_alive_fails(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            jit_package = self.create_fixture(root)
            owner = jit_package / "managed_owner.mbt"
            owner.write_text(
                owner.read_text(encoding="utf-8").replace(
                    "  defer c_jit_context_keep_alive(self.handle)\n", "", 1
                ),
                encoding="utf-8",
            )
            self.assertTrue(
                any("managed keep-alive" in failure for failure in audit_repo(root))
            )

    def test_owner_file_use_before_keep_alive_fails(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            jit_package = self.create_fixture(root)
            owner = jit_package / "managed_owner.mbt"
            owner.write_text(
                owner.read_text(encoding="utf-8").replace(
                    "  defer c_jit_context_keep_alive(self.handle)\n"
                    "  body(raw)\n",
                    "  body(raw) |> ignore\n"
                    "  defer c_jit_context_keep_alive(self.handle)\n"
                    "  body(raw)\n",
                    1,
                ),
                encoding="utf-8",
            )
            self.assertTrue(
                any("before its first use" in failure for failure in audit_repo(root))
            )

    def test_same_package_direct_extraction_fails(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            jit_package = self.create_fixture(root)
            (jit_package / "bypass.mbt").write_text(
                "///|\n"
                "fn bypass(context : Context) -> Int64 {\n"
                "  c_jit_context_ptr(context)\n"
                "}\n",
                encoding="utf-8",
            )
            self.assertTrue(
                any("scoped accessor" in failure for failure in audit_repo(root))
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
