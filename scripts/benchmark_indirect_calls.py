#!/usr/bin/env python3
"""Compare asserted indirect calls through mutable tables.

Each target adds a different constant to a dependency chain. The table index
cycles through every target; the final sum checks every call's contribution.
An exported mutable global can replace an entry between invocations; the table
itself stays private, matching CLI-supported exports. Execution and cold-process
boundaries use the same serial protocol as the other controls.
"""
from benchmark_execution import main


def workloads(scale: int) -> dict[str, str]:
    count = 10_000_000 * scale  # A multiple of every table size below.
    cases = {}
    for targets in (1, 2, 64):
        functions = '\n'.join(
            f'(func $f{i} (type $operation) local.get 0 i64.const {i + 1} i64.add)'
            for i in range(targets))
        elements = ' '.join(f'$f{i}' for i in range(targets))
        expected = count * (targets + 1) // 2
        cases[f'indirect-{targets}-targets'] = f"""(module
          (type $operation (func (param i64) (result i64)))
          {functions}
          (func $alternate (type $operation) local.get 0 i64.const -1 i64.add)
          (global $replace (export "replace") (mut i32) (i32.const 0))
          (table {targets} funcref)
          (elem (i32.const 0) func {elements})
          (elem declare func $alternate)
          (func (export "probe") (result i32)
            (local $i i32) (local $sum i64)
            global.get $replace
            if i32.const 0 ref.func $alternate table.set 0 end
            loop $again
              local.get $sum
              local.get $i i32.const {targets - 1} i32.and
              call_indirect (type $operation) local.set $sum
              local.get $i i32.const 1 i32.add local.tee $i
              i32.const {count} i32.lt_u br_if $again
            end
            local.get $sum i64.const {expected} i64.ne
            if unreachable end i32.const 1))"""
    return cases


if __name__ == '__main__':
    main(workloads, __doc__)
