(module
  (memory (export "memory") 1)

  ;; Sum an array of i32 values
  ;; A classic SIMD candidate: can process 4 i32s at once with v128
  (func $array_sum (export "array_sum") (param $ptr i32) (param $len i32) (result i32)
    (local $sum i32)
    (local $i i32)
    (local.set $sum (i32.const 0))
    (local.set $i (i32.const 0))
    (block $done
      (loop $loop
        (br_if $done (i32.ge_u (local.get $i) (local.get $len)))
        (local.set $sum
          (i32.add
            (local.get $sum)
            (i32.load (i32.add (local.get $ptr) (i32.shl (local.get $i) (i32.const 2))))
          )
        )
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $loop)
      )
    )
    (local.get $sum)
  )

  ;; Dot product of two f32 vectors
  ;; SIMD: multiply 4 f32s, then horizontal add
  (func $dot_product (export "dot_product") (param $a i32) (param $b i32) (param $len i32) (result f32)
    (local $sum f32)
    (local $i i32)
    (local.set $sum (f32.const 0))
    (local.set $i (i32.const 0))
    (block $done
      (loop $loop
        (br_if $done (i32.ge_u (local.get $i) (local.get $len)))
        (local.set $sum
          (f32.add
            (local.get $sum)
            (f32.mul
              (f32.load (i32.add (local.get $a) (i32.shl (local.get $i) (i32.const 2))))
              (f32.load (i32.add (local.get $b) (i32.shl (local.get $i) (i32.const 2))))
            )
          )
        )
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $loop)
      )
    )
    (local.get $sum)
  )

  ;; Vector add: c[i] = a[i] + b[i]
  ;; SIMD: v128.add on 4 i32s at once
  (func $vec_add (export "vec_add") (param $a i32) (param $b i32) (param $c i32) (param $len i32)
    (local $i i32)
    (local.set $i (i32.const 0))
    (block $done
      (loop $loop
        (br_if $done (i32.ge_u (local.get $i) (local.get $len)))
        (i32.store
          (i32.add (local.get $c) (i32.shl (local.get $i) (i32.const 2)))
          (i32.add
            (i32.load (i32.add (local.get $a) (i32.shl (local.get $i) (i32.const 2))))
            (i32.load (i32.add (local.get $b) (i32.shl (local.get $i) (i32.const 2))))
          )
        )
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $loop)
      )
    )
  )

  ;; Find max in i32 array
  ;; SIMD: compare 4 elements at once, then reduce
  (func $array_max (export "array_max") (param $ptr i32) (param $len i32) (result i32)
    (local $max i32)
    (local $val i32)
    (local $i i32)
    (if (i32.eqz (local.get $len))
      (then (return (i32.const 0x80000000))) ;; INT_MIN
    )
    (local.set $max (i32.load (local.get $ptr)))
    (local.set $i (i32.const 1))
    (block $done
      (loop $loop
        (br_if $done (i32.ge_u (local.get $i) (local.get $len)))
        (local.set $val
          (i32.load (i32.add (local.get $ptr) (i32.shl (local.get $i) (i32.const 2))))
        )
        (if (i32.gt_s (local.get $val) (local.get $max))
          (then (local.set $max (local.get $val)))
        )
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $loop)
      )
    )
    (local.get $max)
  )

  ;; Saxpy: y[i] = a * x[i] + y[i]
  ;; Classic BLAS operation, perfect for SIMD
  (func $saxpy (export "saxpy") (param $a f32) (param $x i32) (param $y i32) (param $len i32)
    (local $i i32)
    (local.set $i (i32.const 0))
    (block $done
      (loop $loop
        (br_if $done (i32.ge_u (local.get $i) (local.get $len)))
        (f32.store
          (i32.add (local.get $y) (i32.shl (local.get $i) (i32.const 2)))
          (f32.add
            (f32.mul
              (local.get $a)
              (f32.load (i32.add (local.get $x) (i32.shl (local.get $i) (i32.const 2))))
            )
            (f32.load (i32.add (local.get $y) (i32.shl (local.get $i) (i32.const 2))))
          )
        )
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $loop)
      )
    )
  )

  ;; Byte copy (memcpy-like)
  ;; SIMD: copy 16 bytes at once
  (func $memcpy (export "memcpy") (param $dst i32) (param $src i32) (param $len i32)
    (local $i i32)
    (local.set $i (i32.const 0))
    (block $done
      (loop $loop
        (br_if $done (i32.ge_u (local.get $i) (local.get $len)))
        (i32.store8
          (i32.add (local.get $dst) (local.get $i))
          (i32.load8_u (i32.add (local.get $src) (local.get $i)))
        )
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $loop)
      )
    )
  )
)
