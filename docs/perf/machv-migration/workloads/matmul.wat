(module
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "proc_exit" (func $proc_exit (param i32)))
  (memory (export "memory") 1)
  (data (i32.const 0)
    "\01\00\00\00\02\00\00\00\03\00\00\00\04\00\00\00"
    "\05\00\00\00\06\00\00\00\07\00\00\00\08\00\00\00"
    "\09\00\00\00\0a\00\00\00\0b\00\00\00\0c\00\00\00"
    "\0d\00\00\00\0e\00\00\00\0f\00\00\00\10\00\00\00")
  (data (i32.const 128) "\01\02\03\04\01\02\03\04\01\02\03\04\01\02\03\04")
  (data (i32.const 800) "matmul ok\n")

  (func $print_ok
    (i32.store (i32.const 0) (i32.const 800))
    (i32.store (i32.const 4) (i32.const 10))
    (drop
      (call $fd_write
        (i32.const 1)
        (i32.const 0)
        (i32.const 1)
        (i32.const 8))))

  ;; Multiply two 4x4 integer matrices. A starts at 0, B at 128, and C at
  ;; 256. Static input segments keep setup outside the measured hot loop.
  (func $matmul_once
    (local $i i32)
    (local $j i32)
    (local $k i32)
    (local $sum i32)
    (local $left i32)
    (local $right i32)
    (block $rows_done
      (loop $rows
        (br_if $rows_done (i32.ge_u (local.get $i) (i32.const 4)))
        (local.set $j (i32.const 0))
        (block $columns_done
          (loop $columns
            (br_if $columns_done (i32.ge_u (local.get $j) (i32.const 4)))
            (local.set $sum (i32.const 0))
            (local.set $k (i32.const 0))
            (local.set $right
              (i32.load8_u
                (i32.add (i32.const 128) (local.get $j))))
            (block $products_done
              (loop $products
                (br_if $products_done (i32.ge_u (local.get $k) (i32.const 4)))
                (local.set $left
                  (i32.load
                    (i32.mul
                      (i32.add
                        (i32.mul (local.get $i) (i32.const 4))
                        (local.get $k))
                      (i32.const 4))))
                (local.set $sum
                  (i32.add
                    (local.get $sum)
                    (i32.mul (local.get $left) (local.get $right))))
                (local.set $k (i32.add (local.get $k) (i32.const 1)))
                (br $products)))
            (i32.store
              (i32.add
                (i32.const 256)
                (i32.mul
                  (i32.add
                    (i32.mul (local.get $i) (i32.const 4))
                    (local.get $j))
                  (i32.const 4)))
              (local.get $sum))
            (local.set $j (i32.add (local.get $j) (i32.const 1)))
            (br $columns)))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $rows))))

  (func $checksum (result i32)
    (local $i i32)
    (local $sum i32)
    (block $done
      (loop $items
        (br_if $done (i32.ge_u (local.get $i) (i32.const 16)))
        (local.set $sum
          (i32.add
            (local.get $sum)
            (i32.load
              (i32.add
                (i32.const 256)
                (i32.mul (local.get $i) (i32.const 4))))))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $items)))
    (local.get $sum))

  (func (export "_start")
    (local $round i32)
    (block $done
      (loop $rounds
        (br_if $done (i32.ge_u (local.get $round) (i32.const 2000)))
        (call $matmul_once)
        (local.set $round (i32.add (local.get $round) (i32.const 1)))
        (br $rounds)))
    (if (i32.ne (call $checksum) (i32.const 1360))
      (then (call $proc_exit (i32.const 1))))
    (call $print_ok))
)
