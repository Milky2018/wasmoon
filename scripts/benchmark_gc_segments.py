#!/usr/bin/env python3
"""Compare asserted numeric segment construction and initialization across engines.

Compilation is serial, processes and caches are independent, and generated
fixtures are removed by the shared runner. Construction traffic stays below
64 MiB per invocation at the default scale: segment construction intentionally makes one allocation
attempt, so this benchmark must not silently become a collection-policy test.
"""
from __future__ import annotations

from benchmark_execution import main


PATTERNS = {
    'i8': bytes.fromhex('81'),
    'i16': bytes.fromhex('81fe'),
    'i32': bytes.fromhex('21436587'),
    'i64': bytes.fromhex('8070605040302010'),
    'f32': bytes.fromhex('4523a17f'),
    'f64': bytes.fromhex('bc9a78563412f07f'),
    'v128': bytes.fromhex('88776655443322111122334455667788'),
}


def segment_workload(element: str, size: int, iterations: int, initialize: bool) -> str:
    pattern = PATTERNS[element]
    # The extra byte deliberately makes the source unaligned for wider values.
    data = '\\ff' + ''.join(f'\\{byte:02x}' for byte in pattern) * size

    def check(index: int, *, zero: bool = False) -> str:
        packed = '_u' if element in ('i8', 'i16') else ''
        load = f'global.get $last i32.const {index} array.get{packed} $a'
        if element == 'v128':
            checks = []
            for lane in range(2):
                expected = 0 if zero else int.from_bytes(pattern[lane * 8:lane * 8 + 8], 'little')
                checks.append(f'{load} i64x2.extract_lane {lane} i64.const {expected:#x} i64.ne if unreachable end')
            return '\n'.join(checks)
        integer = 'i64' if element in ('i64', 'f64') else 'i32'
        cast = f' {integer}.reinterpret_{element}' if element in ('f32', 'f64') else ''
        expected = 0 if zero else int.from_bytes(pattern, 'little')
        return f'{load}{cast} {integer}.const {expected:#x} {integer}.ne if unreachable end'

    if initialize:
        setup = f'i32.const {size + 2} array.new_default $a global.set $last'
        body = f'global.get $last i32.const 1 i32.const 1 i32.const {size} array.init_data $a $d'
        start = 1
    else:
        setup = ''
        body = f'i32.const 1 i32.const {size} array.new_data $a $d global.set $last'
        start = 0
    checks = '\n'.join(check(index) for index in sorted({start, start + size // 2, start + size - 1}))
    if initialize:
        checks += '\n' + check(0, zero=True) + '\n' + check(size + 1, zero=True)
    return f'''(module
      (type $a (array (mut {element}))) (data $d "{data}")
      (global $last (export "last") (mut (ref null $a)) (ref.null $a))
      (func (export "probe") (result i32) (local $i i32) {setup}
        loop $repeat {body}
          local.get $i i32.const 1 i32.add local.tee $i
          i32.const {iterations} i32.lt_u br_if $repeat
        end
        {checks} i32.const 1))'''


def workloads(scale: int) -> dict[str, str]:
    cases = {}
    for element, pattern in PATTERNS.items():
        sizes = (1, 2, 3, 4, 17, 256, 65536) if element in ('i32', 'v128') else (65536,)
        for size in sizes:
            for initialize in (False, True):
                traffic = (512 if initialize else 64) * 1024 * 1024
                iterations = max(1, min(1_000_000, traffic // (size * len(pattern))))
                operation = 'init' if initialize else 'new'
                cases[f'{element}-{size}-{operation}'] = segment_workload(
                    element, size, iterations * scale, initialize)
    return cases


if __name__ == '__main__':
    main(workloads, __doc__)
