"""Execute the actual MASM bridges against Microsoft-compiled host functions."""
from pathlib import Path
import os
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
FFI = ROOT / 'modules/wasmoon_jit/jit_ffi'


@unittest.skipUnless(os.name == 'nt', 'requires Microsoft C and MASM')
class WindowsGuestAbiTests(unittest.TestCase):
    def test_all_guest_helpers_preserve_argument_positions(self):
        signatures = {}
        for path in FFI.glob('*.c'):
            for match in re.finditer(r'\bWASMOON_GUEST_ABI\s+(\w+)\s*\(([^)]*)\)\s*\{', path.read_text()):
                signatures[match[1]] = len(match[2].split(','))
        names = re.findall(r'PUBLIC (\w+)_msvc_guest', (FFI / 'msvc_guest_bridges.asm').read_text())
        self.assertGreater(len(names), 100)
        c = ['#include <stdint.h>', '#include <stdio.h>']
        asm = ['option casemap:none', '.code']
        checks = []
        for name in names:
            count = signatures[name]
            args = ', '.join(f'uint64_t a{i}' for i in range(count))
            # Distinct values exercise both register moves and >6 argument copies.
            values = [0x1020304050607080 + i for i in range(count)]
            result = sum(value * (i + 1) for i, value in enumerate(values)) % (1 << 64)
            expression = ' + '.join(f'a{i} * {i + 1}' for i in range(count))
            c += [f'uint64_t {name}_host({args}) {{ return {expression}; }}',
                  f'void *const {name}_msvc_target = (void *){name}_host;',
                  f'extern uint64_t {name}_probe(void);']
            checks += [f'if ({name}_probe() != UINT64_C({result})) {{ puts("{name}"); return 1; }}']
            size = max(count - 6, 0) * 8
            size += 8 if size % 16 == 0 else 0
            asm += [f'EXTERN {name}_msvc_guest:PROC', f'PUBLIC {name}_probe',
                    f'{name}_probe PROC', '    push rdi', '    push rsi', f'    sub rsp, {size}']
            for i, value in enumerate(values):
                if i < 6:
                    register = ['rdi', 'rsi', 'rdx', 'rcx', 'r8', 'r9'][i]
                    asm.append(f'    mov {register}, 0{value:x}h')
                else:
                    asm += [f'    mov rax, 0{value:x}h', f'    mov QWORD PTR [rsp+{(i - 6) * 8}], rax']
            asm += [f'    call {name}_msvc_guest', f'    add rsp, {size}', '    pop rsi',
                    '    pop rdi', '    ret', f'{name}_probe ENDP']
        c += ['int main(void) {'] + checks + ['return 0; }']
        asm += ['END']
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary)
            (path / 'host.c').write_text('\n'.join(c))
            (path / 'probe.asm').write_text('\n'.join(asm))
            ml64 = os.environ.get('WASMOON_MSVC_ML64', 'ml64.exe')
            cl = os.environ.get('WASMOON_MSVC_CL', 'cl.exe')
            for source, output in [(FFI / 'msvc_guest_bridges.asm', 'bridges.obj'), (path / 'probe.asm', 'probe.obj')]:
                subprocess.run([ml64, '/nologo', '/c', '/Fo' + output, str(source)], cwd=path, check=True, timeout=60)
            subprocess.run([cl, '/nologo', '/std:c11', '/O2', '/MT', 'host.c', 'bridges.obj', 'probe.obj', '/Feprobe.exe'],
                           cwd=path, check=True, timeout=60)
            subprocess.run([str(path / 'probe.exe')], check=True, timeout=30)
