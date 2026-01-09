;; WASI Path Tests
;; Tests path_open, fd_prestat_get, fd_prestat_dir_name

;; Mock WASI module that provides testable implementations
(module $wasi_snapshot_preview1
  (global $last_errno (mut i32) (i32.const 0))

  ;; Simulate preopened directory at fd 3
  (global $prestat_name_len (mut i32) (i32.const 3))  ;; "/."

  (memory (export "memory") 2)

  ;; fd_prestat_get(fd, prestat) -> errno
  (func (export "fd_prestat_get") (param i32 i32) (result i32)
    (local $fd i32)
    (local.set $fd (local.get 0))

    ;; Only fd 3 has a prestat
    (if (i32.ne (local.get $fd) (i32.const 3))
      (then
        ;; EBADF = 8 or ENOTSUP = 52
        (global.set $last_errno (i32.const 8))
        (return (i32.const 8))
      )
    )

    ;; Write prestat: tag = 0 (dir), name_len = 3
    (i32.store8 (local.get 1) (i32.const 0))  ;; tag = dir
    (i32.store (i32.add (local.get 1) (i32.const 4))
              (global.get $prestat_name_len))

    (global.set $last_errno (i32.const 0))
    (return (i32.const 0))
  )

  ;; fd_prestat_dir_name(fd, path, path_len) -> errno
  (func (export "fd_prestat_dir_name") (param i32 i32 i32) (result i32)
    (local $fd i32)
    (local.set $fd (local.get 0))

    ;; Only fd 3 has a prestat
    (if (i32.ne (local.get $fd) (i32.const 3))
      (then
        (global.set $last_errno (i32.const 8))
        (return (i32.const 8))
      )
    )

    ;; Write directory name "/."
    (i32.store16 (local.get 1) (i32.const 0x2f))  ;; "/."
    (i32.store8 (i32.add (local.get 1) (i32.const 2)) (i32.const 0))

    (global.set $last_errno (i32.const 0))
    (return (i32.const 0))
  )

  ;; path_open(fd, dirflags, path, path_len, oflags, fs_rights_base, fs_rights_inheriting, fdflags, result) -> errno
  (func (export "path_open") (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)
    (local $fd i32)
    (local.set $fd (local.get 0))

    ;; Only fd 3 is valid (preopened directory)
    (if (i32.ne (local.get $fd) (i32.const 3))
      (then
        (global.set $last_errno (i32.const 8))
        (return (i32.const 8))
      )
    )

    ;; Return success with a fake fd
    (i32.store (local.get 8) (i32.const 5))
    (global.set $last_errno (i32.const 0))
    (return (i32.const 0))
  )

  ;; path_create_directory(fd, path, path_len) -> errno
  (func (export "path_create_directory") (param i32 i32 i32) (result i32)
    (local $fd i32)
    (local.set $fd (local.get 0))

    ;; Only fd 3 is valid for directory operations in this mock
    (if (i32.ne (local.get $fd) (i32.const 3))
      (then
        (global.set $last_errno (i32.const 8))
        (return (i32.const 8))
      )
    )

    (global.set $last_errno (i32.const 0))
    (return (i32.const 0))
  )

  ;; path_unlink_file(fd, path, path_len) -> errno
  (func (export "path_unlink_file") (param i32 i32 i32) (result i32)
    (local $fd i32)
    (local.set $fd (local.get 0))

    ;; Only fd 3 is valid
    (if (i32.ne (local.get $fd) (i32.const 3))
      (then
        (global.set $last_errno (i32.const 8))
        (return (i32.const 8))
      )
    )

    (global.set $last_errno (i32.const 0))
    (return (i32.const 0))
  )

  ;; path_remove_directory(fd, path, path_len) -> errno
  (func (export "path_remove_directory") (param i32 i32 i32) (result i32)
    (local $fd i32)
    (local.set $fd (local.get 0))

    ;; Only fd 3 is valid
    (if (i32.ne (local.get $fd) (i32.const 3))
      (then
        (global.set $last_errno (i32.const 8))
        (return (i32.const 8))
      )
    )

    (global.set $last_errno (i32.const 0))
    (return (i32.const 0))
  )

  ;; path_rename(fd, old_path, old_path_len, new_fd, new_path, new_path_len) -> errno
  (func (export "path_rename") (param i32 i32 i32 i32 i32 i32) (result i32)
    (local $fd i32)
    (local.set $fd (local.get 0))

    ;; Only fd 3 is valid
    (if (i32.ne (local.get $fd) (i32.const 3))
      (then
        (global.set $last_errno (i32.const 8))
        (return (i32.const 8))
      )
    )

    (global.set $last_errno (i32.const 0))
    (return (i32.const 0))
  )

  ;; Helper to get last errno
  (func (export "get_last_errno") (result i32)
    (global.get $last_errno)
  )
)

;; Register the WASI module so subsequent modules can import from it
(register "wasi_snapshot_preview1" $wasi_snapshot_preview1)

;; Test 1: fd_prestat_get with valid fd
(module
  (import "wasi_snapshot_preview1" "fd_prestat_get" (func $fd_prestat_get (param i32 i32) (result i32)))
  (memory 1)

  (func (export "test") (result i32)
    (call $fd_prestat_get (i32.const 3) (i32.const 100))
  )
)
(assert_return (invoke "test") (i32.const 0))

;; Test 2: fd_prestat_get with invalid fd (should return EBADF=8)
(module
  (import "wasi_snapshot_preview1" "fd_prestat_get" (func $fd_prestat_get (param i32 i32) (result i32)))
  (memory 1)

  (func (export "test") (result i32)
    (call $fd_prestat_get (i32.const 1) (i32.const 100))
  )
)
(assert_return (invoke "test") (i32.const 8))

;; Test 3: fd_prestat_dir_name with valid fd
(module
  (import "wasi_snapshot_preview1" "fd_prestat_dir_name" (func $fd_prestat_dir_name (param i32 i32 i32) (result i32)))
  (memory 1)

  (func (export "test") (result i32)
    (call $fd_prestat_dir_name (i32.const 3) (i32.const 100) (i32.const 3))
  )
)
(assert_return (invoke "test") (i32.const 0))

;; Test 4: fd_prestat_dir_name with invalid fd (should return EBADF=8)
(module
  (import "wasi_snapshot_preview1" "fd_prestat_dir_name" (func $fd_prestat_dir_name (param i32 i32 i32) (result i32)))
  (memory 1)

  (func (export "test") (result i32)
    (call $fd_prestat_dir_name (i32.const 1) (i32.const 100) (i32.const 3))
  )
)
(assert_return (invoke "test") (i32.const 8))

;; Test 5: path_open with valid fd
(module
  (import "wasi_snapshot_preview1" "path_open" (func $path_open (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
  (memory 2)
  (data "test.txt")

  (func (export "test") (result i32)
    (call $path_open
      (i32.const 3)           ;; fd
      (i32.const 0)            ;; dirflags
      (i32.const 100)          ;; path ptr
      (i32.const 8)            ;; path len
      (i32.const 0)            ;; oflags
      (i64.const 0)            ;; fs_rights_base
      (i64.const 0)            ;; fs_rights_inheriting
      (i32.const 0)            ;; fd flags
      (i32.const 200)          ;; result
    )
  )
)
(assert_return (invoke "test") (i32.const 0))

;; Test 6: path_open with invalid fd (should return EBADF=8)
(module
  (import "wasi_snapshot_preview1" "path_open" (func $path_open (param i32 i32 i32 i32 i32 i64 i64 i32 i32) (result i32)))
  (memory 2)
  (data "test.txt")

  (func (export "test") (result i32)
    (call $path_open
      (i32.const 99)           ;; fd
      (i32.const 0)            ;; dirflags
      (i32.const 100)          ;; path ptr
      (i32.const 8)            ;; path len
      (i32.const 0)            ;; oflags
      (i64.const 0)            ;; fs_rights_base
      (i64.const 0)            ;; fs_rights_inheriting
      (i32.const 0)            ;; fd flags
      (i32.const 200)          ;; result
    )
  )
)
(assert_return (invoke "test") (i32.const 8))

;; Test 7: path_create_directory with valid fd
(module
  (import "wasi_snapshot_preview1" "path_create_directory" (func $path_create_directory (param i32 i32 i32) (result i32)))
  (memory 1)
  (data "test")

  (func (export "test") (result i32)
    (call $path_create_directory (i32.const 3) (i32.const 100) (i32.const 4))
  )
)
(assert_return (invoke "test") (i32.const 0))

;; Test 8: path_create_directory with invalid fd (should return EBADF=8)
(module
  (import "wasi_snapshot_preview1" "path_create_directory" (func $path_create_directory (param i32 i32 i32) (result i32)))
  (memory 1)

  (func (export "test") (result i32)
    (call $path_create_directory (i32.const 99) (i32.const 100) (i32.const 4))
  )
)
(assert_return (invoke "test") (i32.const 8))

;; Test 9: path_unlink_file with valid fd
(module
  (import "wasi_snapshot_preview1" "path_unlink_file" (func $path_unlink_file (param i32 i32 i32) (result i32)))
  (memory 1)

  (func (export "test") (result i32)
    (call $path_unlink_file (i32.const 3) (i32.const 100) (i32.const 4))
  )
)
(assert_return (invoke "test") (i32.const 0))

;; Test 10: path_unlink_file with invalid fd (should return EBADF=8)
(module
  (import "wasi_snapshot_preview1" "path_unlink_file" (func $path_unlink_file (param i32 i32 i32) (result i32)))
  (memory 1)

  (func (export "test") (result i32)
    (call $path_unlink_file (i32.const 99) (i32.const 100) (i32.const 4))
  )
)
(assert_return (invoke "test") (i32.const 8))

;; Test 11: path_remove_directory with valid fd
(module
  (import "wasi_snapshot_preview1" "path_remove_directory" (func $path_remove_directory (param i32 i32 i32) (result i32)))
  (memory 1)

  (func (export "test") (result i32)
    (call $path_remove_directory (i32.const 3) (i32.const 100) (i32.const 4))
  )
)
(assert_return (invoke "test") (i32.const 0))

;; Test 12: path_remove_directory with invalid fd (should return EBADF=8)
(module
  (import "wasi_snapshot_preview1" "path_remove_directory" (func $path_remove_directory (param i32 i32 i32) (result i32)))
  (memory 1)

  (func (export "test") (result i32)
    (call $path_remove_directory (i32.const 99) (i32.const 100) (i32.const 4))
  )
)
(assert_return (invoke "test") (i32.const 8))

;; Test 13: path_rename with valid fd
(module
  (import "wasi_snapshot_preview1" "path_rename" (func $path_rename (param i32 i32 i32 i32 i32 i32) (result i32)))
  (memory 1)

  (func (export "test") (result i32)
    (call $path_rename (i32.const 3) (i32.const 100) (i32.const 4) (i32.const 3) (i32.const 200) (i32.const 8))
  )
)
(assert_return (invoke "test") (i32.const 0))

;; Test 14: path_rename with invalid fd (should return EBADF=8)
(module
  (import "wasi_snapshot_preview1" "path_rename" (func $path_rename (param i32 i32 i32 i32 i32 i32) (result i32)))
  (memory 1)

  (func (export "test") (result i32)
    (call $path_rename (i32.const 99) (i32.const 100) (i32.const 4) (i32.const 3) (i32.const 200) (i32.const 8))
  )
)
(assert_return (invoke "test") (i32.const 8))
