(module
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "proc_exit" (func $proc_exit (param i32)))
  (memory (export "memory") 1)
  (data (i32.const 128) "gcd ok\n")

  (func $print_ok
    (i32.store (i32.const 0) (i32.const 128))
    (i32.store (i32.const 4) (i32.const 7))
    (drop
      (call $fd_write
        (i32.const 1)
        (i32.const 0)
        (i32.const 1)
        (i32.const 8)
      )
    )
  )

  (func $gcd (param $a i32) (param $b i32) (result i32)
    (block $done
      (loop $euclid
        (br_if $done (i32.eq (local.get $a) (local.get $b)))
        (if (i32.gt_u (local.get $a) (local.get $b))
          (then
            (local.set $a (i32.sub (local.get $a) (local.get $b))))
          (else
            (local.set $b (i32.sub (local.get $b) (local.get $a)))))
        (br $euclid)
      )
    )
    (local.get $a)
  )

  ;; Repeat Euclid's algorithm inside the module and validate every result.
  (func (export "_start")
    (local $round i32)
    (block $done
      (loop $rounds
        (br_if $done (i32.ge_u (local.get $round) (i32.const 500000)))
        (if (i32.ne (call $gcd (i32.const 1071) (i32.const 462)) (i32.const 21))
          (then (call $proc_exit (i32.const 1)))
        )
        (local.set $round (i32.add (local.get $round) (i32.const 1)))
        (br $rounds)
      )
    )
    (call $print_ok)
  )
)
