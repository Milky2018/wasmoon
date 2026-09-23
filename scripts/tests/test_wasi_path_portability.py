"""The private POSIX path helpers must link from either native consumer."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipIf(os.name == 'nt', 'POSIX path helpers')
class PathPortabilityTests(unittest.TestCase):
    def test_standalone_consumer_links_and_preserves_empty_readlink(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            source = directory / 'consumer.c'
            source.write_text(r'''
#include "path_inline.h"
int main(int argc, char **argv) {
    if (argc != 2) return 1;
    if (wasmoon_wasi_symlinkat_portable("missing", AT_FDCWD, argv[1]) != 0) return 2;
    if (wasmoon_wasi_readlinkat_portable(AT_FDCWD, argv[1], NULL, 0) != 0) return 3;
    char data[16];
    if (wasmoon_wasi_readlinkat_portable(AT_FDCWD, argv[1], data, sizeof(data)) != 7) return 4;
    if (memcmp(data, "missing", 7) != 0) return 5;
    if (unlink(argv[1]) != 0) return 6;
    if (wasmoon_wasi_readlinkat_portable(AT_FDCWD, argv[1], NULL, 0) != -1) return 7;
    return errno == ENOENT ? 0 : 8;
}
''')
            executable = directory / 'consumer'
            subprocess.run(['cc', '-Wall', '-Wextra', '-Werror',
                            '-I', str(ROOT / 'modules/wasmoon_jit/host_io'),
                            str(source), '-o', str(executable)], check=True)
            subprocess.run([str(executable), str(directory / 'link')], check=True)
