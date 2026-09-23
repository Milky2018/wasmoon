#!/usr/bin/env python3
"""Compile declared native C stubs with warnings treated as errors."""
import os
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    include = Path(os.environ.get('MOON_HOME', Path.home() / '.moon')) / 'include'
    if os.name == 'nt':
        command = [os.environ.get('WASMOON_MSVC_CL', 'clang-cl'), '/nologo',
                   '/std:c11', '/D_CRT_SECURE_NO_WARNINGS', '/W3', '/WX', '/Zs',
                   '/I' + str(include)]
        if 'WASMOON_MSVC_CL' in os.environ:
            command.append('/experimental:c11atomics')
    else:
        command = ['clang', '-fsyntax-only', '-Wall', '-Wextra', '-Werror',
                   '-I', str(include)]
    count = 0
    failed = []
    for config in sorted((ROOT / 'modules').rglob('moon.pkg')):
        declaration = re.search(r'"native-stub"\s*:\s*\[([^]]*)\]', config.read_text())
        if declaration is None:
            continue
        for name in re.findall(r'"([^"]+\.c)"', declaration[1]):
            result = subprocess.run([*command, str(config.parent / name)])
            if result.returncode:
                failed.append(str(config.parent / name))
            count += 1
    if failed:
        raise SystemExit('Native C compilation failed: ' + ', '.join(failed))
    print(f'Compiled {count} native C stubs with warnings denied.')


if __name__ == '__main__':
    main()
