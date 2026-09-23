"""Production resolver ownership under deterministic schedules and allocation failures."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipIf(os.name == 'nt', 'POSIX standalone allocation-failure probe')
class ResolverLifecycleTests(unittest.TestCase):
    def test_failure_close_finalizer_and_completion_schedules(self):
        with tempfile.TemporaryDirectory() as temporary:
            binary = Path(temporary) / 'resolver'
            subprocess.run([
                'cc', '-pthread', '-Wall', '-Wextra', '-Werror',
                '-I', str(Path(os.environ.get('MOON_HOME', Path.home() / '.moon')) / 'include'),
                '-I', str(ROOT / 'modules/wasmoon_jit/host_io/wasi'),
                str(ROOT / 'scripts/tests/native/resolver_lifecycle.c'),
                '-o', str(binary),
            ], check=True)
            subprocess.run([str(binary)], check=True)
