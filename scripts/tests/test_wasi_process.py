"""Native signal delivery is tested only in disposable child processes."""
from __future__ import annotations
import ctypes
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]

class ProcessTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.build = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.build.cleanup)
        root = Path(cls.build.name)
        export = '__declspec(dllexport)' if os.name == 'nt' else ''
        (root / 'moonbit.h').write_text(f'#define MOONBIT_FFI_EXPORT {export}\n')
        source = ROOT / 'modules/wasmoon/wasi/process_native.c'
        cls.library = root / ('process.dll' if os.name == 'nt' else 'process.so')
        if os.name == 'nt':
            backend = ROOT / 'modules/wasmoon_jit/host_io'
            command = [os.environ.get('WASMOON_MSVC_CL', 'clang-cl'), '/std:c11',
                       '/D_CRT_SECURE_NO_WARNINGS', '/LD', '/MD', '/I' + str(root), str(source),
                       *[str(backend / name) for name in ('windows_io.c', 'windows_input.c', 'windows_fs.c')],
                       '/link', '/OUT:' + str(cls.library)]
        else:
            command = ['cc', '-shared', '-fPIC', '-I' + str(root), str(source), '-o', str(cls.library)]
        subprocess.run(command, check=True, cwd=root, capture_output=True)

    def child(self, source):
        return subprocess.run([sys.executable, '-c', source, str(self.library)],
                              capture_output=True, timeout=15)

    def test_zero_and_invalid_signals_preserve_process(self):
        result = self.child('''import ctypes,sys
lib=ctypes.CDLL(sys.argv[1])
assert lib.wasmoon_wasi_raise_signal(0)==0
assert lib.wasmoon_wasi_raise_signal(31)==-1
assert lib.wasmoon_wasi_raise_signal(-1)==-1
''')
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_allowed_signal_reaches_native_handler(self):
        # A ctypes C callback executes synchronously, including under the Windows
        # CRT; Python's deferred signal handlers need not observe CRT raise().
        result = self.child('''import ctypes,os,signal,sys
lib=ctypes.CDLL(sys.argv[1])
crt=ctypes.CDLL("ucrtbase" if os.name=="nt" else None)
callback=ctypes.CFUNCTYPE(None,ctypes.c_int)(lambda _: os._exit(23))
crt.signal.argtypes=[ctypes.c_int,ctypes.c_void_p]
crt.signal(signal.SIGTERM,ctypes.cast(callback,ctypes.c_void_p))
lib.wasmoon_wasi_raise_signal(15)
os._exit(24)
''')
        self.assertEqual(result.returncode, 23, result.stderr)

if __name__ == '__main__':
    unittest.main()
