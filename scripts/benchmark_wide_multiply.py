#!/usr/bin/env python3
"""Compare an asserted unsigned 64x64-to-128 product on independent engines.

Each checksum covers 1024 pseudorandom operand pairs. Its expected result was
computed independently using arbitrary-precision integer arithmetic. Scale 1
repeats that checked export 10000 times; --scale 100 gives 1.024 billion pairs.
Fresh caches, serial compilation and timer boundaries match the GC controls.
"""
from benchmark_execution import main


def workloads(scale: int) -> dict[str, str]:
    return {'wide-unsigned-product': f"""(module (memory 1)
      (func $multiply (param $out i32) (param $a i64) (param $b i64)
        (local $al i64) (local $bl i64) (local $ah i64) (local $bh i64)
        (local $low i64) (local $carry i64) (local $middle i64)
        local.get $a i64.const 4294967295 i64.and local.set $al
        local.get $b i64.const 4294967295 i64.and local.set $bl
        local.get $a i64.const 32 i64.shr_u local.set $ah
        local.get $b i64.const 32 i64.shr_u local.set $bh
        local.get $al local.get $bl i64.mul local.set $low
        local.get $bl local.get $ah i64.mul
        local.get $low i64.const 32 i64.shr_u i64.add local.set $carry
        local.get $bh local.get $al i64.mul
        local.get $carry i64.const 4294967295 i64.and i64.add local.set $middle
        local.get $out local.get $bh local.get $ah i64.mul
        local.get $carry i64.const 32 i64.shr_u i64.add
        local.get $middle i64.const 32 i64.shr_u i64.add i64.store offset=8
        local.get $out local.get $low i64.const 4294967295 i64.and
        local.get $middle i64.const 32 i64.shl i64.or i64.store)
      (func $checksum (result i64)
        (local $a i64) (local $b i64) (local $sum i64) (local $i i32)
        i64.const 0x123456789abcdef0 local.set $a
        i64.const 0xfedcba9876543210 local.set $b
        loop $again
          local.get $a local.get $a i64.const 13 i64.shl i64.xor local.set $a
          local.get $a local.get $a i64.const 7 i64.shr_u i64.xor local.set $a
          local.get $a local.get $a i64.const 17 i64.shl i64.xor local.set $a
          local.get $b i64.const 6364136223846793005 i64.mul
          i64.const 1442695040888963407 i64.add local.set $b
          i32.const 0 local.get $a local.get $b call $multiply
          local.get $sum i32.const 0 i64.load i32.const 8 i64.load i64.xor
          i64.add local.set $sum
          local.get $i i32.const 1 i32.add local.tee $i
          i32.const 1024 i32.lt_u br_if $again
        end local.get $sum)
      (func (export "probe") (result i32) (local $i i32)
        loop $repeat
          call $checksum i64.const -3416368657776049373 i64.ne
          if unreachable end
          local.get $i i32.const 1 i32.add local.tee $i
          i32.const {10000 * scale} i32.lt_u br_if $repeat
        end i32.const 1))"""}


if __name__ == '__main__':
    main(workloads, __doc__)
