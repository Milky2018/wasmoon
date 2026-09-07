///|
test "wasi jit: path_open preserves zero rights and irreversible inheritance bounds" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "path_open"
    #|    (func $path_open (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_fdstat_get"
    #|    (func $stat (param i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_fdstat_set_rights"
    #|    (func $reduce (param i32 i64 i64) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (data (i32.const 0) ".")
    #|  (func $open (param $fd i32) (param $base i64) (param $inherit i64) (result i32)
    #|    (call $path_open (local.get $fd) (i32.const 1) (i32.const 0) (i32.const 1)
    #|      (i32.const 2) (local.get $base) (local.get $inherit) (i32.const 0) (i32.const 64)))
    #|  (func (export "test") (result i32)
    #|    (local $fd i32)
    #|    (if (call $open (i32.const 3) (i64.const 0) (i64.const 0))
    #|      (then (return (i32.const 1))))
    #|    (local.set $fd (i32.load (i32.const 64)))
    #|    (if (call $stat (local.get $fd) (i32.const 80))
    #|      (then (return (i32.const 2))))
    #|    (if (i64.ne (i64.or (i64.load (i32.const 88)) (i64.load (i32.const 96))) (i64.const 0))
    #|      (then (return (i32.const 3))))
    #|    (if (i32.ne (call $open (local.get $fd) (i64.const 0) (i64.const 0)) (i32.const 76))
    #|      (then (return (i32.const 4))))
    #|    ;; PATH_OPEN is the only capability needed to open another directory.
    #|    (if (call $open (i32.const 3) (i64.const 8192) (i64.const 8192))
    #|      (then (return (i32.const 5))))
    #|    (local.set $fd (i32.load (i32.const 64)))
    #|    (if (call $open (local.get $fd) (i64.const 8192) (i64.const 0))
    #|      (then (return (i32.const 6))))
    #|    (if (call $reduce (local.get $fd) (i64.const 8192) (i64.const 0))
    #|      (then (return (i32.const 7))))
    #|    (if (i32.ne (call $open (local.get $fd) (i64.const 8192) (i64.const 0)) (i32.const 76))
    #|      (then (return (i32.const 8))))
    #|    (if (call $reduce (local.get $fd) (i64.const 0) (i64.const 0))
    #|      (then (return (i32.const 9))))
    #|    (if (i32.ne (call $reduce (local.get $fd) (i64.const 8192) (i64.const 0)) (i32.const 76))
    #|      (then (return (i32.const 10))))
    #|    (i32.const 0)))
  let result = compare_wasi_with_options(source, "test", preopens=[
    ("/tmp", "/"),
  ])
  inspect(wasi_i32_from_result(result.interp_result), content="0")
  inspect(wasi_i32_from_result(result.jit_result), content="0")
}

///|
test "wasi jit: readonly preopens reject mutation and inherited escalation" {
  let source =
    #|(module
    #|  (import "wasi_snapshot_preview1" "path_open"
    #|    (func $open (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_close"
    #|    (func $close (param i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_read"
    #|    (func $read (param i32 i32 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_write"
    #|    (func $write (param i32 i32 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_fdstat_get"
    #|    (func $stat (param i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_fdstat_set_rights"
    #|    (func $rights (param i32 i64 i64) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_filestat_set_size"
    #|    (func $size (param i32 i64) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_filestat_set_times"
    #|    (func $times (param i32 i64 i64 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "path_unlink_file"
    #|    (func $unlink (param i32 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "path_create_directory"
    #|    (func $mkdir (param i32 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "path_link"
    #|    (func $link (param i32 i32 i32 i32 i32 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "path_rename"
    #|    (func $rename (param i32 i32 i32 i32 i32 i32) (result i32)))
    #|  (import "wasi_snapshot_preview1" "fd_readdir"
    #|    (func $readdir (param i32 i32 i32 i64 i32) (result i32)))
    #|  (memory (export "memory") 1)
    #|  (data (i32.const 0) "wasmoon_readonly_rights_probe")
    #|  (data (i32.const 64) "wasmoon_readonly_forbidden")
    #|  (data (i32.const 96) ".")
    #|  (data (i32.const 100) "RO")
    #|  (func (export "test") (result i32)
    #|    (local $file i32) (local $child i32)
    #|    (local $base i64) (local $inherit i64)
    #|    ;; Prepare a fixture using the writable descriptor, then access the same host directory through a read-only descriptor.
    #|    (if (i32.ne (call $open (i32.const 3) (i32.const 0) (i32.const 0) (i32.const 29) (i32.const 9) (i64.const 64) (i64.const 0) (i32.const 0) (i32.const 128)) (i32.const 0))
    #|      (then (return (i32.const 1))))
    #|    (local.set $file (i32.load (i32.const 128)))
    #|    (i32.store (i32.const 144) (i32.const 100))
    #|    (i32.store (i32.const 148) (i32.const 2))
    #|    (if (i32.ne (call $write (local.get $file) (i32.const 144) (i32.const 1) (i32.const 152)) (i32.const 0))
    #|      (then (return (i32.const 2))))
    #|    (if (i32.ne (call $close (local.get $file)) (i32.const 0))
    #|      (then (return (i32.const 3))))
    #|    (if (i32.ne (call $stat (i32.const 4) (i32.const 160)) (i32.const 0))
    #|      (then (return (i32.const 4))))
    #|    (local.set $base (i64.load (i32.const 168)))
    #|    (local.set $inherit (i64.load (i32.const 176)))
    #|    ;; Read-only preopens cannot gain creation rights.
    #|    (if (i32.ne (call $rights (i32.const 4) (i64.or (local.get $base) (i64.const 1024)) (local.get $inherit)) (i32.const 76))
    #|      (then (return (i32.const 5))))
    #|    (if (i32.ne (call $rights (i32.const 4) (local.get $base) (i64.or (local.get $inherit) (i64.const 64))) (i32.const 76))
    #|      (then (return (i32.const 6))))
    #|    ;; Directory listing remains available.
    #|    (if (i32.ne (call $readdir (i32.const 4) (i32.const 512) (i32.const 1024) (i64.const 0) (i32.const 156)) (i32.const 0))
    #|      (then (return (i32.const 7))))
    #|    ;; A child directory inherits the same capability boundary.
    #|    (if (i32.ne (call $open (i32.const 4) (i32.const 1) (i32.const 96) (i32.const 1) (i32.const 2) (local.get $base) (local.get $inherit) (i32.const 0) (i32.const 128)) (i32.const 0))
    #|      (then (return (i32.const 8))))
    #|    (local.set $child (i32.load (i32.const 128)))
    #|    (if (i32.ne (call $open (local.get $child) (i32.const 0) (i32.const 0) (i32.const 29) (i32.const 0) (i64.const 64) (i64.const 0) (i32.const 0) (i32.const 128)) (i32.const 76))
    #|      (then (return (i32.const 9))))
    #|    (if (i32.ne (call $open (i32.const 4) (i32.const 0) (i32.const 0) (i32.const 29) (i32.const 0) (i64.const 64) (i64.const 0) (i32.const 0) (i32.const 128)) (i32.const 76))
    #|      (then (return (i32.const 10))))
    #|    (if (i32.ne (call $open (i32.const 4) (i32.const 0) (i32.const 0) (i32.const 29) (i32.const 8) (i64.const 2) (i64.const 0) (i32.const 0) (i32.const 128)) (i32.const 76))
    #|      (then (return (i32.const 11))))
    #|    (if (i32.ne (call $open (i32.const 4) (i32.const 0) (i32.const 64) (i32.const 25) (i32.const 1) (i64.const 2) (i64.const 0) (i32.const 0) (i32.const 128)) (i32.const 76))
    #|      (then (return (i32.const 12))))
    #|    (if (i32.ne (call $unlink (i32.const 4) (i32.const 0) (i32.const 29)) (i32.const 76))
    #|      (then (return (i32.const 13))))
    #|    (if (i32.ne (call $mkdir (i32.const 4) (i32.const 64) (i32.const 25)) (i32.const 76))
    #|      (then (return (i32.const 14))))
    #|    ;; Neither source nor target may use read-only filesystem mutation rights.
    #|    (if (i32.ne (call $link (i32.const 4) (i32.const 0) (i32.const 0) (i32.const 29) (i32.const 3) (i32.const 64) (i32.const 25)) (i32.const 76))
    #|      (then (return (i32.const 15))))
    #|    (if (i32.ne (call $rename (i32.const 4) (i32.const 0) (i32.const 29) (i32.const 3) (i32.const 64) (i32.const 25)) (i32.const 76))
    #|      (then (return (i32.const 16))))
    #|    ;; Neither source nor target may use read-only filesystem mutation rights.
    #|    (if (i32.ne (call $link (i32.const 3) (i32.const 0) (i32.const 0) (i32.const 29) (i32.const 4) (i32.const 64) (i32.const 25)) (i32.const 76))
    #|      (then (return (i32.const 17))))
    #|    (if (i32.ne (call $rename (i32.const 3) (i32.const 0) (i32.const 29) (i32.const 4) (i32.const 64) (i32.const 25)) (i32.const 76))
    #|      (then (return (i32.const 18))))
    #|    ;; Reads remain available after denied mutations.
    #|    (if (i32.ne (call $open (local.get $child) (i32.const 0) (i32.const 0) (i32.const 29) (i32.const 0) (i64.const 2) (i64.const 0) (i32.const 0) (i32.const 128)) (i32.const 0))
    #|      (then (return (i32.const 19))))
    #|    (local.set $file (i32.load (i32.const 128)))
    #|    (if (i32.ne (call $size (local.get $file) (i64.const 0)) (i32.const 76))
    #|      (then (return (i32.const 20))))
    #|    (if (i32.ne (call $times (local.get $file) (i64.const 0) (i64.const 0) (i32.const 10)) (i32.const 76))
    #|      (then (return (i32.const 21))))
    #|    (if (i32.ne (call $write (local.get $file) (i32.const 144) (i32.const 1) (i32.const 152)) (i32.const 76))
    #|      (then (return (i32.const 22))))
    #|    (i32.store (i32.const 144) (i32.const 200))
    #|    (if (i32.ne (call $read (local.get $file) (i32.const 144) (i32.const 1) (i32.const 152)) (i32.const 0))
    #|      (then (return (i32.const 23))))
    #|    (if (i32.ne (i32.load (i32.const 152)) (i32.const 2))
    #|      (then (return (i32.const 24))))
    #|    (if (i32.ne (i32.load16_u (i32.const 200)) (i32.const 20306))
    #|      (then (return (i32.const 25))))
    #|    (if (i32.ne (call $read (local.get $file) (i32.const 144) (i32.const 1) (i32.const 152)) (i32.const 0))
    #|      (then (return (i32.const 26))))
    #|    (if (i32.ne (i32.load (i32.const 152)) (i32.const 0))
    #|      (then (return (i32.const 27))))
    #|    (if (i32.ne (call $close (local.get $file)) (i32.const 0))
    #|      (then (return (i32.const 28))))
    #|    (if (i32.ne (call $close (local.get $child)) (i32.const 0))
    #|      (then (return (i32.const 29))))
    #|    ;; Clean up through the original writable descriptor.
    #|    (if (i32.ne (call $unlink (i32.const 3) (i32.const 0) (i32.const 29)) (i32.const 0))
    #|      (then (return (i32.const 30))))
    #|    (i32.const 0)))
  let result = compare_wasi_with_options(
    source,
    "test",
    preopens=[("/tmp", "writable")],
    readonly_preopens=[("/tmp", "readonly")],
  )
  inspect(wasi_i32_from_result(result.interp_result), content="0")
  inspect(wasi_i32_from_result(result.jit_result), content="0")
}
