(module
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "proc_exit" (func $proc_exit (param i32)))
  (memory (export "memory") 1)
  (data (i32.const 800) "matmul ok\n")

  (func $print_ok
    (i32.store (i32.const 0) (i32.const 800))
    (i32.store (i32.const 4) (i32.const 10))
    (drop
      (call $fd_write
        (i32.const 1)
        (i32.const 0)
        (i32.const 1)
        (i32.const 8)
      )
    )
  )

  ;; Multiply two 8x8 integer matrices. A starts at 0, B at 256, and C at
  ;; 512. The checksum is stable and checked before reporting success.
  (func (export "_start")
    (local $round i32)
    (local $i i32)
    (local $j i32)
    (local $k i32)
    (local $sum i32)
    (local $checksum i32)

    (local.set $i (i32.const 0))
    (block $init_done
      (loop $init
        (br_if $init_done (i32.ge_u (local.get $i) (i32.const 64)))
        (i32.store
          (i32.mul (local.get $i) (i32.const 4))
          (i32.add (local.get $i) (i32.const 1))
        )
        (i32.store
          (i32.add
            (i32.const 256)
            (i32.mul (local.get $i) (i32.const 4))
          )
          (i32.add (i32.rem_u (local.get $i) (i32.const 8)) (i32.const 1))
        )
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $init)
      )
    )

    (block $rounds_done
      (loop $rounds
        (br_if $rounds_done (i32.ge_u (local.get $round) (i32.const 200)))
        (local.set $i (i32.const 0))
        (block $rows_done
          (loop $rows
            (br_if $rows_done (i32.ge_u (local.get $i) (i32.const 8)))
            (local.set $j (i32.const 0))
            (block $columns_done
              (loop $columns
                (br_if $columns_done (i32.ge_u (local.get $j) (i32.const 8)))
                (local.set $sum (i32.const 0))
                (local.set $k (i32.const 0))
                (block $products_done
                  (loop $products
                    (br_if $products_done (i32.ge_u (local.get $k) (i32.const 8)))
                    (local.set
                      $sum
                      (i32.add
                        (local.get $sum)
                        (i32.mul
                          (i32.load
                            (i32.mul
                              (i32.add
                                (i32.mul (local.get $i) (i32.const 8))
                                (local.get $k)
                              )
                              (i32.const 4)
                            )
                          )
                          (i32.load
                            (i32.add
                              (i32.const 256)
                              (i32.mul
                                (i32.add
                                  (i32.mul (local.get $k) (i32.const 8))
                                  (local.get $j)
                                )
                                (i32.const 4)
                              )
                            )
                          )
                        )
                      )
                    )
                    (local.set $k (i32.add (local.get $k) (i32.const 1)))
                    (br $products)
                  )
                )
                (i32.store
                  (i32.add
                    (i32.const 512)
                    (i32.mul
                      (i32.add
                        (i32.mul (local.get $i) (i32.const 8))
                        (local.get $j)
                      )
                      (i32.const 4)
                    )
                  )
                  (local.get $sum)
                )
                (local.set $j (i32.add (local.get $j) (i32.const 1)))
                (br $columns)
              )
            )
            (local.set $i (i32.add (local.get $i) (i32.const 1)))
            (br $rows)
          )
        )
        (local.set $round (i32.add (local.get $round) (i32.const 1)))
        (br $rounds)
      )
    )

    (local.set $i (i32.const 0))
    (block $checksum_done
      (loop $checksum_values
        (br_if $checksum_done (i32.ge_u (local.get $i) (i32.const 64)))
        (local.set
          $checksum
          (i32.add
            (local.get $checksum)
            (i32.load
              (i32.add
                (i32.const 512)
                (i32.mul (local.get $i) (i32.const 4))
              )
            )
          )
        )
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $checksum_values)
      )
    )
    (if (i32.ne (local.get $checksum) (i32.const 74880))
      (then (call $proc_exit (i32.const 1)))
    )
    (call $print_ok)
  )
)
