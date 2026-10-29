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


def struct_view_workload(count: int, *, same_object: bool) -> str:
    # Allocate before the measured invocation. Mutable exported globals and
    # fields preserve real projections for both repeated hits and alternating
    # misses; the final sum checks every load.
    second = 'global.get $a' if same_object else 'i32.const 42 struct.new $s'
    expected = (46 if same_object else 65) * count
    return f"""(module
      (type $s (struct (field (mut i32))))
      (global $a (export "a") (mut (ref null $s)) (ref.null $s))
      (global $b (export "b") (mut (ref null $s)) (ref.null $s))
      (func $init
        i32.const 23 struct.new $s global.set $a
        {second} global.set $b)
      (start $init)
      (func (export "probe") (result i32) (local $i i32) (local $sum i64)
        (loop $again
          local.get $sum
          global.get $a struct.get $s 0 i64.extend_i32_u i64.add
          global.get $b struct.get $s 0 i64.extend_i32_u i64.add local.set $sum
          local.get $i i32.const 1 i32.add local.tee $i
          i32.const {count} i32.lt_u br_if $again)
        local.get $sum i64.const {expected} i64.eq))"""


def graph_workload(count: int, *, nodes: int = 32768) -> str:
    # A long-lived chain survives several full collections while a reference
    # ring mutates and short-lived arrays provide allocation pressure. The chain
    # is checked after churn, rather than merely checking that allocation works.
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
        local.get $sum i32.const {(nodes * (nodes - 1) // 2) & 0xffffffff} i32.eq
        global.get $ring i32.const {(count - 1) & 255} array.get $ring
        struct.get $node 1 i32.const {count - 1} i32.eq i32.and))"""


def reference_array_workload(count: int, *, length: int, mutate: bool) -> str:
    # Keep a large reference container alive while a small working set mutates.
    # Independent short-lived arrays supply pressure; final values and the
    # distant null tail are asserted.
    updates = (
        'global.get $roots local.get $i i32.const 1023 i32.and '
        'local.get $i struct.new $node array.set $refs' if mutate else ''
    )
    expected = sum(range(count - 1024, count)) if mutate else sum(range(1024))
    return f"""(module
 (type $node (struct (field i32))) (type $refs (array (mut (ref null $node))))
 (type $bytes (array (mut i32)))
 (global $roots (mut (ref null $refs)) (ref.null $refs))
 (global $last (mut (ref null $bytes)) (ref.null $bytes))
 (func (export "probe") (result i32) (local $i i32) (local $sum i32)
 i32.const {length} array.new_default $refs global.set $roots
 loop $init
 global.get $roots local.get $i local.get $i struct.new $node array.set $refs
 local.get $i i32.const 1 i32.add local.tee $i i32.const 1024 i32.lt_u br_if $init end
 i32.const 0 local.set $i
 loop $churn {updates}
 i32.const 4096 array.new_default $bytes global.set $last
 global.get $last i32.const 4095 array.get $bytes if unreachable end
 local.get $i i32.const 1 i32.add local.tee $i i32.const {count} i32.lt_u br_if $churn end
 i32.const 0 local.set $i
 loop $check local.get $sum global.get $roots local.get $i array.get $refs
 struct.get $node 0 i32.add local.set $sum
 local.get $i i32.const 1 i32.add local.tee $i i32.const 1024 i32.lt_u br_if $check end
 local.get $sum i32.const {expected} i32.ne if unreachable end
 global.get $roots i32.const {length-1} array.get $refs ref.is_null i32.eqz if unreachable end
 i32.const 1))"""


def live_initializer_workload(count: int) -> str:
    # Keep all references live through one large initializer. Publishing the
    # array prevents treating its elements as nonescaping local aggregates.
    members = ' '.join(f'i32.const {i} struct.new $node' for i in range(count))
    expected = count * (count - 1) // 2 & 0xffffffff
    return f"""(module
      (type $node (struct (field i32)))
      (type $refs (array (ref $node)))
      (global $last (export "last") (mut (ref null $refs)) (ref.null $refs))
      (func (export "probe") (result i32) (local $i i32) (local $sum i32)
        {members} array.new_fixed $refs {count} global.set $last
        loop $check
          local.get $sum global.get $last local.get $i array.get $refs
          struct.get $node 0 i32.add local.set $sum
          local.get $i i32.const 1 i32.add local.tee $i
          i32.const {count} i32.lt_u br_if $check
        end
        local.get $sum i32.const {expected} i32.eq))"""


def workloads(scale: int) -> dict[str, str]:
    count = 10000 * scale
    return {
        'reused-struct-view': struct_view_workload(count * 2000, same_object=True),
        'alternating-struct-views': struct_view_workload(count * 2000, same_object=False),
        'live-initializer-128': live_initializer_workload(128 * scale),
        'live-initializer-512': live_initializer_workload(512 * scale),
        'live-initializer-2048': live_initializer_workload(2048 * scale),
        'i32-zero': array_workload(count, vector=False, nonzero=False),
        'i32-nonzero': array_workload(count, vector=False, nonzero=True),
        'i32-small-nonzero': array_workload(count * 10, vector=False, nonzero=True, size=4),
        'i32-single-nonzero': array_workload(count * 10, vector=False, nonzero=True, size=1),
        'i32-tail-nonzero': array_workload(count * 10, vector=False, nonzero=True, size=17),
        'v128-high-word': array_workload(count, vector=True, nonzero=True),
        'survivors-and-mutation': graph_workload(count),
        'large-survivors-and-mutation': graph_workload(100000 * scale, nodes=2097152),
        'static-large-reference-array': reference_array_workload(
            65536 * scale, length=16777212, mutate=False),
        'mutated-large-reference-array': reference_array_workload(
            65536 * scale, length=16777212, mutate=True),
    }


if __name__ == '__main__':
    main(workloads, __doc__)
