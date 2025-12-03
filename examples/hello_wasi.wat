(module
  ;; Import WASI functions
  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "proc_exit"
    (func $proc_exit (param i32)))

  ;; Memory (1 page = 64KB)
  (memory (export "memory") 1)

  ;; Data: "Hello, WASI!\n" at offset 8
  (data (i32.const 8) "Hello, WASI!\n")

  ;; _start is the entry point for WASI programs
  (func (export "_start")
    ;; Set up iovec at address 0:
    ;;   iovec.buf = 8 (pointer to string)
    ;;   iovec.buf_len = 13 (length of "Hello, WASI!\n")
    (i32.store (i32.const 0) (i32.const 8))   ;; buf pointer
    (i32.store (i32.const 4) (i32.const 13))  ;; buf length

    ;; Call fd_write(fd=1, iovs=0, iovs_len=1, nwritten=100)
    ;; fd=1 is stdout
    (call $fd_write
      (i32.const 1)   ;; fd: stdout
      (i32.const 0)   ;; iovs: pointer to iovec array
      (i32.const 1)   ;; iovs_len: number of iovecs
      (i32.const 100) ;; nwritten: where to store bytes written
    )
    drop ;; ignore return value

    ;; Exit with code 0
    (call $proc_exit (i32.const 0))
  )
)
