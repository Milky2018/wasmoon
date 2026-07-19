(module
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "proc_exit" (func $proc_exit (param i32)))
  (memory (export "memory") 1)
  (data (i32.const 128) "abcdefghijklmnopqrstuvwxyz0123456789")
  (data (i32.const 256) "fnv1a ok\n")

  (func $print_ok
    (i32.store (i32.const 0) (i32.const 256))
    (i32.store (i32.const 4) (i32.const 9))
    (drop
      (call $fd_write
        (i32.const 1)
        (i32.const 0)
        (i32.const 1)
        (i32.const 8)
      )
    )
  )

  ;; Compute FNV-1a over a fixed input. The expected hash is checked inside
  ;; the module so the workload cannot silently benchmark a wrong result.
  (func (export "_start")
    (local $round i32)
    (local $index i32)
    (local $hash i32)
    (block $rounds_done
      (loop $rounds
        (br_if $rounds_done (i32.ge_u (local.get $round) (i32.const 20000)))
        (local.set $index (i32.const 0))
        (local.set $hash (i32.const 0x811c9dc5))
        (block $hash_done
          (loop $hash_bytes
            (br_if $hash_done (i32.ge_u (local.get $index) (i32.const 36)))
            (local.set
              $hash
              (i32.mul
                (i32.xor
                  (local.get $hash)
                  (i32.load8_u (i32.add (i32.const 128) (local.get $index)))
                )
                (i32.const 0x01000193)
              )
            )
            (local.set $index (i32.add (local.get $index) (i32.const 1)))
            (br $hash_bytes)
          )
        )
        (if (i32.ne (local.get $hash) (i32.const 0x762088cd))
          (then (call $proc_exit (i32.const 1)))
        )
        (local.set $round (i32.add (local.get $round) (i32.const 1)))
        (br $rounds)
      )
    )
    (call $print_ok)
  )
)
