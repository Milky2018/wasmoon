from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))

from verify_native_sanitizers import collect_binaries, missing_sanitizers


class NativeSanitizerVerificationTests(unittest.TestCase):
    def test_accepts_runtime_dependencies_and_handler_symbols(self) -> None:
        self.assertEqual(
            missing_sanitizers(
                "libclang_rt.asan_osx_dynamic.dylib",
                "___ubsan_handle_type_mismatch_v1",
            ),
            [],
        )
        self.assertEqual(
            missing_sanitizers("libasan.so.8\nlibubsan.so.1", ""),
            [],
        )
        self.assertEqual(
            missing_sanitizers(
                "@rpath/libclang_rt.asan_osx_dynamic.dylib\n"
                "@rpath/libclang_rt.ubsan_osx_dynamic.dylib",
                "",
            ),
            [],
        )
        self.assertEqual(
            missing_sanitizers(
                "libclang_rt.asan-x86_64.so\n"
                "libclang_rt.ubsan_standalone-x86_64.so",
                "",
            ),
            [],
        )
        self.assertEqual(
            missing_sanitizers(
                "",
                "__asan_init\n__ubsan_handle_add_overflow",
            ),
            [],
        )

    def test_reports_each_missing_sanitizer(self) -> None:
        self.assertEqual(missing_sanitizers("libSystem", ""), ["ASan", "UBSan"])
        self.assertEqual(
            missing_sanitizers("libasan.so", ""),
            ["UBSan"],
        )
        self.assertEqual(
            missing_sanitizers("", "__ubsan_handle_add_overflow"),
            ["ASan"],
        )

    def test_rejects_adversarial_runtime_and_symbol_names(self) -> None:
        self.assertEqual(
            missing_sanitizers(
                "libnotasan.so\n"
                "libnotubsan.so\n"
                "libclang_rt.asan_fake.so\n"
                "libclang_rt.ubsan_fake.so",
                "",
            ),
            ["ASan", "UBSan"],
        )
        self.assertEqual(
            missing_sanitizers(
                "",
                "__notasan_init\n__notubsan_handle_add_overflow",
            ),
            ["ASan", "UBSan"],
        )

    def test_collects_cli_and_test_executables(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory)
            cli = (
                target
                / "native/release/build/Milky2018/wasmoon/cmd/wasmoon/wasmoon.exe"
            )
            test = (
                target
                / "native/debug/test/Milky2018/wasmoon_jit"
                / "wasmoon_jit.whitebox_test.exe"
            )
            cli.parent.mkdir(parents=True)
            test.parent.mkdir(parents=True)
            cli.touch()
            test.touch()
            cli_debug = (
                cli.parent
                / "wasmoon.exe.dSYM/Contents/Resources/DWARF/wasmoon.exe"
            )
            test_debug = (
                test.parent
                / (
                    "wasmoon_jit.whitebox_test.exe.dSYM/Contents/Resources/"
                    "DWARF/wasmoon_jit.whitebox_test.exe"
                )
            )
            cli_debug.parent.mkdir(parents=True)
            test_debug.parent.mkdir(parents=True)
            cli_debug.touch()
            test_debug.touch()
            self.assertEqual(collect_binaries(target), ([cli], [test]))


if __name__ == "__main__":
    unittest.main()
