(module
  ;; A CPU-intensive benchmark that takes ~10 seconds
  ;; Computes Fibonacci numbers iteratively in a loop

  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "proc_exit"
    (func $proc_exit (param i32)))

  (memory (export "memory") 1)

  ;; Messages
  (data (i32.const 128) "Running benchmark...\n")
  (data (i32.const 152) "Iteration ")
  (data (i32.const 164) "/10\n")
  (data (i32.const 176) "Benchmark complete!\n")

  ;; Print helper
  (func $print (param $ptr i32) (param $len i32)
    (i32.store (i32.const 0) (local.get $ptr))
    (i32.store (i32.const 4) (local.get $len))
    (call $fd_write (i32.const 1) (i32.const 0) (i32.const 1) (i32.const 8))
    drop
  )

  ;; Print a number 1-10 (two characters: space+digit or "10")
  (func $print_num (param $n i32)
    (if (i32.eq (local.get $n) (i32.const 10))
      (then
        (i32.store8 (i32.const 200) (i32.const 49))  ;; '1'
        (i32.store8 (i32.const 201) (i32.const 48))  ;; '0'
      )
      (else
        (i32.store8 (i32.const 200) (i32.const 32))  ;; ' '
        (i32.store8 (i32.const 201) (i32.add (i32.const 48) (local.get $n)))
      )
    )
    (call $print (i32.const 200) (i32.const 2))
  )

  ;; Compute fibonacci(n) iteratively
  (func $fib (param $n i32) (result i64)
    (local $a i64)
    (local $b i64)
    (local $tmp i64)
    (local $i i32)

    (local.set $a (i64.const 0))
    (local.set $b (i64.const 1))
    (local.set $i (i32.const 0))

    (block $done
      (loop $loop
        (br_if $done (i32.ge_u (local.get $i) (local.get $n)))
        (local.set $tmp (local.get $b))
        (local.set $b (i64.add (local.get $a) (local.get $b)))
        (local.set $a (local.get $tmp))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $loop)
      )
    )
    (local.get $a)
  )

  ;; Main: run fibonacci many times to consume ~10 seconds
  (func (export "_start")
    (local $outer i32)
    (local $inner i32)
    (local $result i64)

    ;; Print starting message
    (call $print (i32.const 128) (i32.const 21))

    ;; Outer loop: 10 iterations with progress
    (local.set $outer (i32.const 0))
    (block $outer_done
      (loop $outer_loop
        (br_if $outer_done (i32.ge_u (local.get $outer) (i32.const 10)))

        ;; Print progress
        (call $print (i32.const 152) (i32.const 10))
        (call $print_num (i32.add (local.get $outer) (i32.const 1)))
        (call $print (i32.const 164) (i32.const 4))

        ;; Inner loop: compute fib(80) many times
        (local.set $inner (i32.const 0))
        (block $inner_done
          (loop $inner_loop
            (br_if $inner_done (i32.ge_u (local.get $inner) (i32.const 1000000)))
            (local.set $result (call $fib (i32.const 80)))
            (local.set $inner (i32.add (local.get $inner) (i32.const 1)))
            (br $inner_loop)
          )
        )

        (local.set $outer (i32.add (local.get $outer) (i32.const 1)))
        (br $outer_loop)
      )
    )

    ;; Print done message
    (call $print (i32.const 176) (i32.const 20))
    (call $proc_exit (i32.const 0))
  )
)
