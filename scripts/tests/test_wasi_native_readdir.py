"""Run the production directory serializer under AddressSanitizer."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class NativeReaddirTests(unittest.TestCase):
    def test_repeated_reads_after_directory_changes(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            (directory / "moonbit.h").write_text(
                '#include <stdint.h>\n#define MOONBIT_FFI_EXPORT\n'
                'typedef unsigned char *moonbit_bytes_t;\n'
                'moonbit_bytes_t moonbit_make_bytes(int32_t size, int value);\n')
            binary = directory / "readdir"
            subprocess.run(['cc', '-fsanitize=address', '-g', '-Wall', '-Wextra', '-Werror',
                            '-I', str(directory), str(ROOT / 'modules/wasmoon/wasi/directory_native.c'),
                            str(ROOT / 'scripts/tests/native/readdir.c'), '-o', str(binary)],
                           check=True, capture_output=True)
            scratch = directory / "scratch"
            scratch.mkdir()
            result = subprocess.run([str(binary), str(scratch)], capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr.decode(errors='replace'))
