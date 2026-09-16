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
    (@test_fs.temp_dir(), "/"),
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
    preopens=[(@test_fs.temp_dir(), "writable")],
    readonly_preopens=[(@test_fs.temp_dir(), "readonly")],
  )
  inspect(wasi_i32_from_result(result.interp_result), content="0")
  inspect(wasi_i32_from_result(result.jit_result), content="0")
}

///|
test "wasi jit: SEEK implies TELL and TELL permits only nonmoving seek" {
  let source =
    #|(module
    #|(import "wasi_snapshot_preview1" "path_open" (func $open (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
    #|(import "wasi_snapshot_preview1" "fd_seek" (func $seek (param i32 i64 i32 i32) (result i32)))
    #|(import "wasi_snapshot_preview1" "fd_tell" (func $tell (param i32 i32) (result i32)))
    #|(import "wasi_snapshot_preview1" "fd_close" (func $close (param i32) (result i32)))
    #|(import "wasi_snapshot_preview1" "path_unlink_file" (func $unlink (param i32 i32 i32) (result i32)))
    #|(memory (export "memory") 1)
    #|(data (i32.const 64) "wasmoon_seek_rights")
    #|(func $eq (param i32 i32) (if (i32.ne (local.get 0) (local.get 1)) (then unreachable)))
    #|(func $case (param $rights i64) (param $query i32) (param $move i32) (local $fd i32)
    #| (call $eq (call $open (i32.const 3) (i32.const 0) (i32.const 64) (i32.const 18) (i32.const 9) (local.get $rights) (i64.const 0) (i32.const 0) (i32.const 0)) (i32.const 0))
    #| (local.set $fd (i32.load (i32.const 0)))
    #| (call $eq (call $tell (local.get $fd) (i32.const 16)) (local.get $query))
    #| (call $eq (call $seek (local.get $fd) (i64.const 0) (i32.const 1) (i32.const 16)) (local.get $query))
    #| (call $eq (call $seek (local.get $fd) (i64.const 1) (i32.const 1) (i32.const 16)) (local.get $move))
    #| (call $eq (call $close (local.get $fd)) (i32.const 0)))
    #|(func (export "test") (result i32)
    #| (call $case (i64.const 4) (i32.const 0) (i32.const 0))
    #| (call $case (i64.const 32) (i32.const 0) (i32.const 76))
    #| (call $case (i64.const 0) (i32.const 76) (i32.const 76))
    #| (call $unlink (i32.const 3) (i32.const 64) (i32.const 18))))
  let result = compare_wasi_with_options(source, "test", preopens=[
    (@test_fs.temp_dir(), "/"),
  ])
  inspect(wasi_i32_from_result(result.interp_result), content="0")
  inspect(wasi_i32_from_result(result.jit_result), content="0")
}

///|
test "wasi jit: synchronous opens require inherited rights before create or truncate" {
  let path = @test_fs.temp_dir() + "/wasmoon_sync_rights"
  @wasi.native_unlinkat(0, path, 0) |> ignore
  defer @wasi.native_unlinkat(0, path, 0) |> ignore
  let source =
    #|(module
    #|(import "wasi_snapshot_preview1" "path_open" (func $open (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
    #|(import "wasi_snapshot_preview1" "fd_close" (func $close (param i32) (result i32)))
    #|(import "wasi_snapshot_preview1" "path_unlink_file" (func $unlink (param i32 i32 i32) (result i32)))
    #|(import "wasi_snapshot_preview1" "fd_write" (func $write (param i32 i32 i32 i32) (result i32)))
    #|(import "wasi_snapshot_preview1" "fd_filestat_get" (func $stat (param i32 i32) (result i32)))
    #|(memory (export "memory") 1)
    #|(data (i32.const 64) "wasmoon_sync_rights") (data (i32.const 90) ".") (data (i32.const 91) "x")
    #|(func $eq (param i32 i32) (if (i32.ne (local.get 0) (local.get 1)) (then unreachable)))
    #|(func $file (param $dir i32) (param $oflags i32) (param $flags i32) (result i32)
    #| (call $open (local.get $dir) (i32.const 0) (i32.const 64) (i32.const 18) (local.get $oflags) (i64.const 64) (i64.const 0) (local.get $flags) (i32.const 0)))
    #|(func $dir (param $rights i64) (result i32)
    #| (call $eq (call $open (i32.const 3) (i32.const 0) (i32.const 90) (i32.const 1) (i32.const 2) (i64.const 533504) (local.get $rights) (i32.const 0) (i32.const 0)) (i32.const 0))
    #| (i32.load (i32.const 0)))
    #|(func $case (param $flags i32) (param $sync i64) (local $d i32) (local $f i32)
    #| (local.set $d (call $dir (i64.const 64)))
    #| (call $eq (call $file (local.get $d) (i32.const 1) (local.get $flags)) (i32.const 76))
    #| (call $eq (call $unlink (i32.const 3) (i32.const 64) (i32.const 18)) (i32.const 44))
    #| ;; Create data with a descriptor that can observe whether denied truncation mutated it.
    #| (call $eq (call $open (i32.const 3) (i32.const 0) (i32.const 64) (i32.const 18) (i32.const 9) (i64.const 2097216) (i64.const 0) (i32.const 0) (i32.const 0)) (i32.const 0))
    #| (local.set $f (i32.load (i32.const 0)))
    #| (i32.store (i32.const 16) (i32.const 91)) (i32.store (i32.const 20) (i32.const 1))
    #| (call $eq (call $write (local.get $f) (i32.const 16) (i32.const 1) (i32.const 24)) (i32.const 0))
    #| (call $eq (call $file (local.get $d) (i32.const 8) (local.get $flags)) (i32.const 76))
    #| (call $eq (call $stat (local.get $f) (i32.const 128)) (i32.const 0))
    #| (if (i64.ne (i64.load (i32.const 160)) (i64.const 1)) (then unreachable))
    #| (call $eq (call $close (local.get $f)) (i32.const 0))
    #| (call $eq (call $close (local.get $d)) (i32.const 0))
    #| (local.set $d (call $dir (i64.or (i64.const 64) (local.get $sync))))
    #| (call $eq (call $file (local.get $d) (i32.const 0) (local.get $flags)) (i32.const 0))
    #| (call $eq (call $close (i32.load (i32.const 0))) (i32.const 0))
    #| (call $eq (call $close (local.get $d)) (i32.const 0))
    #| (call $eq (call $unlink (i32.const 3) (i32.const 64) (i32.const 18)) (i32.const 0)))
    #|(func (export "test") (result i32)
    #| (call $case (i32.const 2) (i64.const 1))
    #| (call $case (i32.const 8) (i64.const 16))
    #| (call $case (i32.const 16) (i64.const 16))
    #| (call $case (i32.const 26) (i64.const 17)) (i32.const 0)))
  let result = compare_wasi_with_options(source, "test", preopens=[
    (@test_fs.temp_dir(), "/"),
  ])
  if result.interp_result is Err(_) || result.jit_result is Err(_) {
    fail(result.to_string())
  }
  inspect(wasi_i32_from_result(result.interp_result), content="0")
  inspect(wasi_i32_from_result(result.jit_result), content="0")
}

///|
test "wasi jit: standard stream rights stay reduced across renumbering" {
  let source =
    #|(module
    #|(import "wasi_snapshot_preview1" "fd_fdstat_get" (func $stat (param i32 i32) (result i32)))
    #|(import "wasi_snapshot_preview1" "fd_filestat_get" (func $filestat (param i32 i32) (result i32)))
    #|(import "wasi_snapshot_preview1" "fd_fdstat_set_rights" (func $rights (param i32 i64 i64) (result i32)))
    #|(import "wasi_snapshot_preview1" "fd_read" (func $read (param i32 i32 i32 i32) (result i32)))
    #|(import "wasi_snapshot_preview1" "fd_write" (func $write (param i32 i32 i32 i32) (result i32)))
    #|(import "wasi_snapshot_preview1" "fd_renumber" (func $move (param i32 i32) (result i32)))
    #|(import "wasi_snapshot_preview1" "fd_close" (func $close (param i32) (result i32)))
    #|(import "wasi_snapshot_preview1" "poll_oneoff" (func $poll (param i32 i32 i32 i32) (result i32)))
    #|(memory (export "memory") 1) (global $target (mut i32) (i32.const 0))
    #|(func $eq (param i32 i32) (if (i32.ne (local.get 0) (local.get 1)) (then unreachable)))
    #|(func $denied (param $fd i32) (param $kind i32)
    #| (i32.store (i32.const 16) (i32.const 48)) (i32.store (i32.const 20) (i32.const 1))
    #| (i32.store8 (i32.const 48) (i32.const 165)) (i32.store (i32.const 24) (i32.const 123))
    #| (if (i32.eq (local.get $kind) (i32.const 1))
    #|  (then (call $eq (call $read (local.get $fd) (i32.const 16) (i32.const 1) (i32.const 24)) (i32.const 76)))
    #|  (else (call $eq (call $write (local.get $fd) (i32.const 16) (i32.const 1) (i32.const 24)) (i32.const 76))))
    #| (call $eq (i32.load8_u (i32.const 48)) (i32.const 165))
    #| (call $eq (i32.load (i32.const 24)) (i32.const 123))
    #| (call $eq (call $filestat (local.get $fd) (i32.const 320)) (i32.const 76))
    #| (i32.store8 (i32.const 136) (local.get $kind)) (i32.store (i32.const 144) (local.get $fd))
    #| (call $eq (call $poll (i32.const 128) (i32.const 192) (i32.const 1) (i32.const 240)) (i32.const 76)))
    #|(func $case (param $fd i32) (param $kind i32) (local $base i64) (local $inherit i64)
    #| (global.set $target (if (result i32) (i32.eqz (local.get $fd)) (then (i32.const 1)) (else (i32.const 0))))
    #| (call $eq (call $stat (local.get $fd) (i32.const 64)) (i32.const 0))
    #| (local.set $base (i64.load (i32.const 72))) (local.set $inherit (i64.load (i32.const 80)))
    #| (call $eq (call $rights (local.get $fd) (local.get $base) (local.get $inherit)) (i32.const 0))
    #| (call $eq (call $rights (local.get $fd) (i64.const 0) (i64.const 0)) (i32.const 0))
    #| (call $eq (call $stat (local.get $fd) (i32.const 64)) (i32.const 0))
    #| (if (i64.ne (i64.or (i64.load (i32.const 72)) (i64.load (i32.const 80))) (i64.const 0)) (then unreachable))
    #| (call $eq (call $rights (local.get $fd) (local.get $base) (local.get $inherit)) (i32.const 76))
    #| (call $denied (local.get $fd) (local.get $kind))
    #| (call $eq (call $move (local.get $fd) (global.get $target)) (i32.const 0))
    #| (call $eq (call $stat (local.get $fd) (i32.const 64)) (i32.const 8))
    #| (call $denied (global.get $target) (local.get $kind))
    #| (call $eq (call $rights (global.get $target) (local.get $base) (local.get $inherit)) (i32.const 76))
    #| (call $eq (call $close (global.get $target)) (i32.const 0))
    #| (call $eq (call $rights (global.get $target) (i64.const 0) (i64.const 0)) (i32.const 8)))
    #|(func (export "stdin") (result i32) (call $case (i32.const 0) (i32.const 1)) (i32.const 0))
    #|(func (export "stdout") (result i32) (call $case (i32.const 1) (i32.const 2)) (i32.const 0))
    #|(func (export "stderr") (result i32) (call $case (i32.const 2) (i32.const 2)) (i32.const 0)))
  for name in ["stdin", "stdout", "stderr"] {
    let result = compare_wasi_with_options(source, name, stdin_data=b"secret")
    if result.interp_result is Err(_) || result.jit_result is Err(_) {
      fail(result.to_string())
    }
    inspect(wasi_i32_from_result(result.interp_result), content="0")
    inspect(wasi_i32_from_result(result.jit_result), content="0")
    inspect(result.interp_stdout, content="b\"\"")
    inspect(result.jit_stdout, content="b\"\"")
  }
}
