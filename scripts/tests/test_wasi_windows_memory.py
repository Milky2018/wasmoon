"""Instrument the real Windows host I/O implementation with AddressSanitizer."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(os.name == "nt", "requires native Windows AddressSanitizer")
class WindowsMemoryTests(unittest.TestCase):
    def test_native_ownership_and_buffers_under_asan(self):
        compiler = Path(shutil.which("clang-cl") or "clang-cl")
        clang = compiler.with_name("clang.exe")
        resources = Path(subprocess.check_output(
            [str(clang), "--print-resource-dir"], text=True).strip())
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "moonbit.h").write_text('#define MOONBIT_FFI_EXPORT\n')
            source = ROOT / "modules/wasmoon_jit/host_io"
            program = root / "memory.exe"
            subprocess.run([
                str(compiler), "/MD", "/Zi", "/fsanitize=address",
                "/I" + str(root), "/I" + str(source),
                str(ROOT / "scripts/tests/native/windows_memory.c"),
                str(source / "windows_io.c"), str(source / "windows_fs.c"),
                "/Fe:" + str(program),
            ], check=True, cwd=root, timeout=120)
            fixture = root / "fixture"
            fixture.mkdir()
            environment = os.environ | {
                "ASAN_OPTIONS": "detect_leaks=0:halt_on_error=1:abort_on_error=1",
                "PATH": str(resources / "lib/windows") + os.pathsep + os.environ["PATH"],
            }
            subprocess.run([str(program), str(fixture)], check=True, env=environment, timeout=60)
