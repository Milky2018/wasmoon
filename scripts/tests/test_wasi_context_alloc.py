"""Production native context cleanup under deterministic allocation failures."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipIf(os.name == 'nt', 'POSIX standalone allocation-failure probe')
class ContextAllocationTests(unittest.TestCase):
    def test_every_partial_allocation_and_reinitialization(self):
        with tempfile.TemporaryDirectory() as temporary:
            binary = Path(temporary) / 'context'
            subprocess.run([
                'cc', '-Wall', '-Wextra', '-Werror',
                '-I', str(Path(os.environ.get('MOON_HOME', Path.home() / '.moon')) / 'include'),
                '-I', str(ROOT / 'modules/wasmoon_jit/jit_ffi'),
                str(ROOT / 'scripts/tests/native/wasi_context_alloc.c'),
                '-o', str(binary),
            ], check=True)
            subprocess.run([str(binary)], check=True)
