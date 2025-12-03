(module
  ;; Import WASI functions
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "args_sizes_get"
    (func $args_sizes_get (param i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "args_get"
    (func $args_get (param i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "proc_exit"
    (func $proc_exit (param i32)))

  ;; Memory layout:
  ;;   0-3: argc (from args_sizes_get)
  ;;   4-7: argv_buf_size (from args_sizes_get)
  ;;   8-11: iovec.buf
  ;;   12-15: iovec.buf_len
  ;;   16-19: nwritten
  ;;   100+: argv array (pointers)
  ;;   500+: argv_buf (actual strings)
  (memory (export "memory") 1)

  ;; Newline character
  (data (i32.const 20) "\n")

  (func (export "_start")
    (local $i i32)
    (local $argc i32)
    (local $arg_ptr i32)

    ;; Get argument sizes
    (call $args_sizes_get
      (i32.const 0)   ;; argc pointer
      (i32.const 4)   ;; argv_buf_size pointer
    )
    drop

    ;; Load argc
    (local.set $argc (i32.load (i32.const 0)))

    ;; Get arguments
    (call $args_get
      (i32.const 100) ;; argv pointer array
      (i32.const 500) ;; argv_buf
    )
    drop

    ;; Print each argument followed by newline
    (local.set $i (i32.const 0))
    (block $break
      (loop $loop
        ;; Check if i >= argc
        (br_if $break (i32.ge_u (local.get $i) (local.get $argc)))

        ;; Get pointer to current argument
        (local.set $arg_ptr
          (i32.load
            (i32.add
              (i32.const 100)
              (i32.mul (local.get $i) (i32.const 4))
            )
          )
        )

        ;; Find string length by looking for null terminator
        ;; Set up iovec for the argument
        (i32.store (i32.const 8) (local.get $arg_ptr))

        ;; Calculate length (simple: assume max 100 chars, find null)
        (i32.store (i32.const 12)
          (call $strlen (local.get $arg_ptr))
        )

        ;; Print argument
        (call $fd_write
          (i32.const 1)   ;; stdout
          (i32.const 8)   ;; iovec
          (i32.const 1)   ;; iovs_len
          (i32.const 16)  ;; nwritten
        )
        drop

        ;; Print newline
        (i32.store (i32.const 8) (i32.const 20))  ;; buf = newline
        (i32.store (i32.const 12) (i32.const 1))  ;; len = 1
        (call $fd_write
          (i32.const 1)
          (i32.const 8)
          (i32.const 1)
          (i32.const 16)
        )
        drop

        ;; i++
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $loop)
      )
    )

    ;; Exit with code 0
    (call $proc_exit (i32.const 0))
  )

  ;; Helper: calculate string length (find null terminator)
  (func $strlen (param $ptr i32) (result i32)
    (local $len i32)
    (local.set $len (i32.const 0))
    (block $break
      (loop $loop
        ;; If current byte is 0, break
        (br_if $break
          (i32.eqz
            (i32.load8_u (i32.add (local.get $ptr) (local.get $len)))
          )
        )
        ;; len++
        (local.set $len (i32.add (local.get $len) (i32.const 1)))
        ;; Safety: max 1000 chars
        (br_if $break (i32.ge_u (local.get $len) (i32.const 1000)))
        (br $loop)
      )
    )
    (local.get $len)
  )
)
