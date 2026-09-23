"""Independent host-level checks for P1 allocation, contents and descriptor position."""
from __future__ import annotations

import ctypes
import errno
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class AllocationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.build = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.build.cleanup)
        root = Path(cls.build.name)
        export = '__declspec(dllexport)' if os.name == 'nt' else ''
        (root / 'moonbit.h').write_text(f'#define MOONBIT_FFI_EXPORT {export}\n')
        source = ROOT / 'modules/wasmoon_jit/host_io/wasi/file_semantics_native.c'
        library = root / ('allocate.dll' if os.name == 'nt' else 'allocate.so')
        if os.name == 'nt':
            backend = ROOT / 'modules/wasmoon_jit/host_io'
            command = [os.environ.get('WASMOON_MSVC_CL', 'clang-cl'), '/std:c11',
                       '/D_CRT_SECURE_NO_WARNINGS', '/LD', '/MD', '/I' + str(root), str(source),
                       *[str(backend / name) for name in ('windows_io.c', 'windows_input.c', 'windows_fs.c')],
                       '/link', '/OUT:' + str(library)]
        else:
            command = ['cc', '-shared', '-fPIC', '-I' + str(root), str(source), '-o', str(library)]
        subprocess.run(command, check=True, cwd=root, capture_output=True)
        cls.library = ctypes.CDLL(str(library))
        if os.name == 'nt':
            import _ctypes
            cls.addClassCleanup(_ctypes.FreeLibrary, cls.library._handle)
        cls.allocate = cls.library.wasmoon_wasi_allocate
        cls.allocate.argtypes = [ctypes.c_int, ctypes.c_int64, ctypes.c_int64]
        cls.allocate.restype = ctypes.c_int

    def test_allocation_preserves_contents_size_and_cursor(self):
        with tempfile.TemporaryFile() as file:
            file.write(b'keep')
            file.flush()
            position = file.tell()
            self.assertEqual(self.allocate(file.fileno(), 4096, 4096), 0)
            self.assertEqual(os.fstat(file.fileno()).st_size, 8192)
            self.assertEqual(file.tell(), position)
            file.seek(0)
            self.assertEqual(file.read(4), b'keep')
            file.seek(4096)
            self.assertEqual(file.read(4096), bytes(4096))
            self.assertEqual(self.allocate(file.fileno(), 0, 1), 0)
            self.assertEqual(os.fstat(file.fileno()).st_size, 8192)
            self.assertEqual(file.tell(), 8192)

    def test_allocation_rejects_invalid_ranges_without_mutation(self):
        with tempfile.TemporaryFile() as file:
            for offset, length, expected in ((0, 0, errno.EINVAL), (-1, 1, errno.EOVERFLOW),
                                              (0, -1, errno.EOVERFLOW), ((1 << 63) - 1, 1, errno.EOVERFLOW)):
                self.assertEqual(self.allocate(file.fileno(), offset, length), expected)
                self.assertEqual(os.fstat(file.fileno()).st_size, 0)

    def test_readonly_file_does_not_gain_write_authority(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / 'file'
            path.write_bytes(b'keep')
            with path.open('rb') as file:
                self.assertEqual(self.allocate(file.fileno(), 0, 8192), errno.EBADF)
            self.assertEqual(path.read_bytes(), b'keep')


if __name__ == '__main__':
    unittest.main()
