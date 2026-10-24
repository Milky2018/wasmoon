#!/usr/bin/env python3
"""Compare asserted GC workloads across Wasmoon, Wasmtime and optimized V8.

Fresh processes and independent cold caches; compilation is serial in every
engine. Wasmoon and V8 additionally report their own compilation/invocation
boundaries. Whole-process CPU/RSS includes compilation and teardown. Generated
Wasm, samples and caches are automatically removed, including on failure.
"""
from __future__ import annotations

from benchmark_execution import main


def array_workload(count: int, *, vector: bool, nonzero: bool, size: int | None = None) -> str:
    # Exported mutable state prevents treating every array as a local aggregate.
    element = 'v128' if vector else 'i32'
    if size is None:
        size = 1024 if vector else 4096
    init = ('v128.const i64x2 0 42' if nonzero else 'v128.const i64x2 0 0') if vector else ('i32.const 42' if nonzero else 'i32.const 0')
    check = ('i64x2.extract_lane 1 i64.const ' + ('42' if nonzero else '0') + ' i64.eq') if vector else ('i32.const ' + ('42' if nonzero else '0') + ' i32.eq')
    return f"""(module
      (type $a (array (mut {element})))
      (global $last (export "last") (mut (ref null $a)) (ref.null $a))
      (func (export "probe") (result i32) (local $i i32)
        (loop $again
          {init} i32.const {size} array.new $a global.set $last
          global.get $last i32.const {size - 1} array.get $a
          {check} i32.eqz (if (then unreachable))
          local.get $i i32.const 1 i32.add local.tee $i
          i32.const {count} i32.lt_u br_if $again)
        i32.const 1))"""


def graph_workload(count: int) -> str:
    # A long-lived chain survives several full collections while a reference
    # ring mutates and short-lived arrays provide allocation pressure. The chain
    # is checked after churn, rather than merely checking that allocation works.
    nodes = 32768
    return f"""(module
      (type $node (struct (field (ref null $node)) (field i32)))
      (type $bytes (array (mut i32)))
      (type $ring (array (mut (ref null $node))))
      (global $head (export "head") (mut (ref null $node)) (ref.null $node))
      (global $ring (mut (ref null $ring)) (ref.null $ring))
      (global $last (mut (ref null $bytes)) (ref.null $bytes))
      (func (export "probe") (result i32)
        (local $i i32) (local $cursor (ref null $node)) (local $sum i32)
        ref.null $node global.set $head
        (loop $build
          global.get $head local.get $i struct.new $node global.set $head
          local.get $i i32.const 1 i32.add local.tee $i
          i32.const {nodes} i32.lt_u br_if $build)
        i32.const 256 array.new_default $ring global.set $ring
        i32.const 0 local.set $i
        (loop $churn
          global.get $ring local.get $i i32.const 255 i32.and
          ref.null $node local.get $i struct.new $node array.set $ring
          i32.const 4096 array.new_default $bytes global.set $last
          global.get $last i32.const 4095 array.get $bytes
          (if (then unreachable))
          local.get $i i32.const 1 i32.add local.tee $i
          i32.const {count} i32.lt_u br_if $churn)
        global.get $head local.set $cursor
        (block $done (loop $walk
          local.get $cursor ref.is_null br_if $done
          local.get $sum local.get $cursor struct.get $node 1 i32.add local.set $sum
          local.get $cursor struct.get $node 0 local.set $cursor br $walk))
        local.get $sum i32.const {nodes * (nodes - 1) // 2} i32.eq
        global.get $ring i32.const {(count - 1) & 255} array.get $ring
        struct.get $node 1 i32.const {count - 1} i32.eq i32.and))"""


def workloads(scale: int) -> dict[str, str]:
    count = 10000 * scale
    return {
        'i32-zero': array_workload(count, vector=False, nonzero=False),
        'i32-nonzero': array_workload(count, vector=False, nonzero=True),
        'i32-small-nonzero': array_workload(count * 10, vector=False, nonzero=True, size=4),
        'i32-single-nonzero': array_workload(count * 10, vector=False, nonzero=True, size=1),
        'i32-tail-nonzero': array_workload(count * 10, vector=False, nonzero=True, size=17),
        'v128-high-word': array_workload(count, vector=True, nonzero=True),
        'survivors-and-mutation': graph_workload(count),
    }


if __name__ == '__main__':
    main(workloads, __doc__)
