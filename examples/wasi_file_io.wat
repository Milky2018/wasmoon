(module
  ;; Test real file I/O operations with WASI
  ;; Usage: wasmoon run examples/wasi_file_io.wat --dir .

  (import "wasi_snapshot_preview1" "fd_write"
    (func $fd_write (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_read"
    (func $fd_read (param i32 i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "path_open"
    (func $path_open (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_close"
    (func $fd_close (param i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_prestat_get"
    (func $fd_prestat_get (param i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "fd_prestat_dir_name"
    (func $fd_prestat_dir_name (param i32 i32 i32) (result i32)))
  (import "wasi_snapshot_preview1" "proc_exit"
    (func $proc_exit (param i32)))

  (memory (export "memory") 1)

  ;; Memory layout:
  ;; 0-7: iovec (buf_ptr, buf_len)
  ;; 8-11: nwritten/nread result
  ;; 16-19: opened_fd result
  ;; 32-63: prestat buffer
  ;; 64-127: dir name buffer
  ;; 128-255: messages
  ;; 256-511: file content buffer
  ;; 512+: filename

  ;; Messages
  (data (i32.const 128) "=== WASI File I/O Test ===\n")
  (data (i32.const 160) "Checking preopen fd 3... ")
  (data (i32.const 192) "OK\n")
  (data (i32.const 196) "FAIL (errno=")
  (data (i32.const 212) ")\n")
  (data (i32.const 216) "Creating test file... ")
  (data (i32.const 240) "Writing to file... ")
  (data (i32.const 264) "Closing file... ")
  (data (i32.const 284) "Reopening for read... ")
  (data (i32.const 308) "Reading from file... ")
  (data (i32.const 332) "Content: \"")
  (data (i32.const 344) "\"\n")
  (data (i32.const 348) "Test completed!\n")

  ;; Test filename and content
  (data (i32.const 512) "test_output.txt")
  (data (i32.const 544) "Hello from WebAssembly!")

  ;; Print helper (ptr, len)
  (func $print (param $ptr i32) (param $len i32)
    (i32.store (i32.const 0) (local.get $ptr))
    (i32.store (i32.const 4) (local.get $len))
    (call $fd_write (i32.const 1) (i32.const 0) (i32.const 1) (i32.const 8))
    drop
  )

  ;; Print a number (0-99)
  (func $print_num (param $n i32)
    (local $tens i32)
    (local $ones i32)
    (local.set $tens (i32.div_u (local.get $n) (i32.const 10)))
    (local.set $ones (i32.rem_u (local.get $n) (i32.const 10)))
    (if (i32.gt_u (local.get $tens) (i32.const 0))
      (then
        (i32.store8 (i32.const 256) (i32.add (i32.const 48) (local.get $tens)))
        (call $print (i32.const 256) (i32.const 1))
      )
    )
    (i32.store8 (i32.const 256) (i32.add (i32.const 48) (local.get $ones)))
    (call $print (i32.const 256) (i32.const 1))
  )

  (func (export "_start")
    (local $errno i32)
    (local $fd i32)
    (local $nread i32)

    ;; Print header
    (call $print (i32.const 128) (i32.const 27))

    ;; Check preopen fd 3
    (call $print (i32.const 160) (i32.const 25))
    (local.set $errno (call $fd_prestat_get (i32.const 3) (i32.const 32)))
    (if (i32.eqz (local.get $errno))
      (then
        (call $print (i32.const 192) (i32.const 3))
      )
      (else
        (call $print (i32.const 196) (i32.const 12))
        (call $print_num (local.get $errno))
        (call $print (i32.const 212) (i32.const 2))
        (call $proc_exit (i32.const 1))
      )
    )

    ;; Create test file for writing
    ;; path_open(dir_fd=3, dirflags=0, path, path_len, oflags=CREATE|TRUNC,
    ;;           rights_base, rights_inheriting, fdflags, opened_fd)
    (call $print (i32.const 216) (i32.const 22))
    (local.set $errno
      (call $path_open
        (i32.const 3)         ;; dir_fd (preopen)
        (i32.const 0)         ;; dirflags
        (i32.const 512)       ;; path ptr "test_output.txt"
        (i32.const 15)        ;; path_len
        (i32.const 9)         ;; oflags: CREATE(1) | TRUNC(8)
        (i64.const 0x1FFFFFFF) ;; rights_base (all valid rights)
        (i64.const 0x1FFFFFFF) ;; rights_inheriting
        (i32.const 0)         ;; fdflags
        (i32.const 16)        ;; opened_fd ptr
      )
    )
    (if (i32.eqz (local.get $errno))
      (then
        (call $print (i32.const 192) (i32.const 3))
      )
      (else
        (call $print (i32.const 196) (i32.const 12))
        (call $print_num (local.get $errno))
        (call $print (i32.const 212) (i32.const 2))
        (call $proc_exit (i32.const 1))
      )
    )
    (local.set $fd (i32.load (i32.const 16)))

    ;; Write to file
    (call $print (i32.const 240) (i32.const 19))
    (i32.store (i32.const 0) (i32.const 544))  ;; buf ptr
    (i32.store (i32.const 4) (i32.const 23))   ;; buf len "Hello from WebAssembly!"
    (local.set $errno
      (call $fd_write
        (local.get $fd)       ;; fd
        (i32.const 0)         ;; iovs
        (i32.const 1)         ;; iovs_len
        (i32.const 8)         ;; nwritten
      )
    )
    (if (i32.eqz (local.get $errno))
      (then
        (call $print (i32.const 192) (i32.const 3))
      )
      (else
        (call $print (i32.const 196) (i32.const 12))
        (call $print_num (local.get $errno))
        (call $print (i32.const 212) (i32.const 2))
        (call $proc_exit (i32.const 1))
      )
    )

    ;; Close file
    (call $print (i32.const 264) (i32.const 16))
    (local.set $errno (call $fd_close (local.get $fd)))
    (if (i32.eqz (local.get $errno))
      (then
        (call $print (i32.const 192) (i32.const 3))
      )
      (else
        (call $print (i32.const 196) (i32.const 12))
        (call $print_num (local.get $errno))
        (call $print (i32.const 212) (i32.const 2))
        (call $proc_exit (i32.const 1))
      )
    )

    ;; Reopen for reading
    (call $print (i32.const 284) (i32.const 22))
    (local.set $errno
      (call $path_open
        (i32.const 3)         ;; dir_fd
        (i32.const 0)         ;; dirflags
        (i32.const 512)       ;; path ptr
        (i32.const 15)        ;; path_len
        (i32.const 0)         ;; oflags: none (just open)
        (i64.const 0x1FFFFFFF) ;; rights_base
        (i64.const 0x1FFFFFFF) ;; rights_inheriting
        (i32.const 0)         ;; fdflags
        (i32.const 16)        ;; opened_fd ptr
      )
    )
    (if (i32.eqz (local.get $errno))
      (then
        (call $print (i32.const 192) (i32.const 3))
      )
      (else
        (call $print (i32.const 196) (i32.const 12))
        (call $print_num (local.get $errno))
        (call $print (i32.const 212) (i32.const 2))
        (call $proc_exit (i32.const 1))
      )
    )
    (local.set $fd (i32.load (i32.const 16)))

    ;; Read from file
    (call $print (i32.const 308) (i32.const 21))
    ;; Clear buffer first
    (memory.fill (i32.const 256) (i32.const 0) (i32.const 64))
    (i32.store (i32.const 0) (i32.const 256))  ;; buf ptr
    (i32.store (i32.const 4) (i32.const 64))   ;; buf len
    (local.set $errno
      (call $fd_read
        (local.get $fd)       ;; fd
        (i32.const 0)         ;; iovs
        (i32.const 1)         ;; iovs_len
        (i32.const 8)         ;; nread
      )
    )
    (if (i32.eqz (local.get $errno))
      (then
        ;; Read nread BEFORE printing OK (print overwrites address 8)
        (local.set $nread (i32.load (i32.const 8)))
        (call $print (i32.const 192) (i32.const 3))
        ;; Print content
        (call $print (i32.const 332) (i32.const 10))
        (call $print (i32.const 256) (local.get $nread))
        (call $print (i32.const 344) (i32.const 2))
      )
      (else
        (call $print (i32.const 196) (i32.const 12))
        (call $print_num (local.get $errno))
        (call $print (i32.const 212) (i32.const 2))
        (call $proc_exit (i32.const 1))
      )
    )

    ;; Close file
    (call $fd_close (local.get $fd))
    drop

    ;; Done
    (call $print (i32.const 348) (i32.const 16))
    (call $proc_exit (i32.const 0))
  )
)
