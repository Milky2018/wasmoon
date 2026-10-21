;; Reject invalid URI setters through the canonical ABI, then echo the body.
(module
  (import "wasi:http/types@0.3.0" "[method]request.set-path-with-query" (func $set-path (param i32 i32 i32 i32) (result i32)))
  (import "wasi:http/types@0.3.0" "[method]request.set-authority" (func $set-authority (param i32 i32 i32 i32) (result i32)))
  (import "wasi:http/types@0.3.0" "[constructor]fields" (func $fields (result i32)))
  (import "wasi:http/types@0.3.0" "[static]request.consume-body" (func $consume (param i32 i32 i32)))
  (import "wasi:http/types@0.3.0" "[static]response.new" (func $response (param i32 i32 i32 i32 i32)))
  (import "wasi:http/types@0.3.0" "[future-new-0][static]request.consume-body" (func $future (result i64)))
  (import "wasi:http/types@0.3.0" "[async-lower][future-write-0][static]request.consume-body" (func $write (param i32 i32) (result i32)))
  (import "wasi:http/types@0.3.0" "[future-drop-writable-0][static]request.consume-body" (func $drop-writer (param i32)))
  (import "wasi:http/types@0.3.0" "[future-drop-readable-2][static]response.new" (func $drop-receipt (param i32)))
  (import "$root" "[waitable-set-new]" (func $set-new (result i32)))
  (import "$root" "[waitable-join]" (func $join (param i32 i32)))
  (import "$root" "[waitable-set-drop]" (func $set-drop (param i32)))
  (import "[export]wasi:http/handler@0.3.0" "[task-return]handle" (func $return (param i32 i32 i32 i64 i32 i32 i32 i32)))
  (memory (export "memory") 2)
  (data (i32.const 64) "/<bad>/ok")
  (data (i32.const 80) "/%GG")
  (data (i32.const 96) "<bad>")
  (global $heap (mut i32) (i32.const 4096))
  (global $writer (mut i32) (i32.const 0))
  (global $set (mut i32) (i32.const 0))
  (func (export "cabi_realloc") (param i32 i32 i32 i32) (result i32)
    (local $ptr i32)
    global.get $heap
    local.get 2 i32.const 1 i32.sub i32.add
    i32.const 0 local.get 2 i32.sub i32.and
    local.tee $ptr local.get 3 i32.add global.set $heap
    local.get $ptr)
  (func (export "[async-lift]wasi:http/handler@0.3.0#handle") (param $request i32) (result i32)
    (local $pair i64)
    local.get $request i32.const 1 i32.const 64 i32.const 9 call $set-path
    i32.const 1 i32.ne if unreachable end
    local.get $request i32.const 1 i32.const 80 i32.const 4 call $set-path
    i32.const 1 i32.ne if unreachable end
    local.get $request i32.const 1 i32.const 96 i32.const 5 call $set-authority
    i32.const 1 i32.ne if unreachable end
    call $future local.tee $pair
    i64.const 32 i64.shr_u i32.wrap_i64 global.set $writer
    call $set-new global.set $set
    global.get $writer i32.const 256 call $write drop
    global.get $writer global.get $set call $join
    local.get $request local.get $pair i32.wrap_i64 i32.const 512 call $consume
    call $fields
    i32.const 1 i32.const 512 i32.load i32.const 516 i32.load i32.const 528 call $response
    i32.const 532 i32.load call $drop-receipt
    i32.const 0 i32.const 528 i32.load i32.const 0 i64.const 0
    i32.const 0 i32.const 0 i32.const 0 i32.const 0 call $return
    global.get $set i32.const 4 i32.shl i32.const 2 i32.or)
  (func (export "[callback][async-lift]wasi:http/handler@0.3.0#handle") (param i32 i32 i32) (result i32)
    global.get $writer call $drop-writer
    global.get $set call $set-drop
    i32.const 0)
)
