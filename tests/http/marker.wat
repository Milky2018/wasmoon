;; Prefix the request path before calling downstream; build_fixtures.py selects each layer name.
(module
  (import "wasi:http/handler@0.3.0" "[async-lower]handle" (func $send (param i32 i32) (result i32)))
  (import "$root" "[waitable-set-new]" (func $set-new (result i32)))
  (import "$root" "[waitable-join]" (func $join (param i32 i32)))
  (import "$root" "[waitable-set-drop]" (func $set-drop (param i32)))
  (import "$root" "[subtask-drop]" (func $subtask-drop (param i32)))
  (import "[export]wasi:http/handler@0.3.0" "[task-return]handle" (func $return (param i32 i32 i32 i64 i32 i32 i32 i32)))
  (import "wasi:http/types@0.3.0" "[method]request.get-path-with-query" (func $get-path (param i32 i32)))
  (import "wasi:http/types@0.3.0" "[method]request.set-path-with-query" (func $set-path (param i32 i32 i32 i32) (result i32)))
  (memory (export "memory") 2)
  (data (i32.const 64) "/layer")
  (global $heap (mut i32) (i32.const 4096))
  (global $set (mut i32) (i32.const 0))
  (global $subtask (mut i32) (i32.const 0))
  (func (export "cabi_realloc") (param i32 i32 i32 i32) (result i32)
    (local $ptr i32)
    global.get $heap local.get 2 i32.const 1 i32.sub i32.add
    i32.const 0 local.get 2 i32.sub i32.and
    local.tee $ptr local.get 3 i32.add global.set $heap local.get $ptr)
  (func $publish
    i32.const 512 i32.load8_u i32.const 520 i32.load i32.const 0 i64.const 0
    i32.const 0 i32.const 0 i32.const 0 i32.const 0 call $return)
  (func (export "[async-lift]wasi:http/handler@0.3.0#handle") (param i32) (result i32)
    (local $status i32)
    local.get 0 i32.const 320 call $get-path
    global.get $heap i32.const 64 i32.const 6 memory.copy
    global.get $heap i32.const 6 i32.add
    i32.const 324 i32.load i32.const 328 i32.load memory.copy
    local.get 0 i32.const 1 global.get $heap
    i32.const 328 i32.load i32.const 6 i32.add call $set-path if unreachable end
    global.get $heap i32.const 328 i32.load i32.add i32.const 6 i32.add global.set $heap
    local.get 0 i32.const 512 call $send local.tee $status
    i32.const 15 i32.and i32.const 2 i32.eq
    if call $publish i32.const 0 return end
    local.get $status i32.const 4 i32.shr_u global.set $subtask
    call $set-new global.set $set
    global.get $subtask global.get $set call $join
    global.get $set i32.const 4 i32.shl i32.const 2 i32.or)
  (func (export "[callback][async-lift]wasi:http/handler@0.3.0#handle") (param i32 i32 i32) (result i32)
    local.get 2 i32.const 2 i32.eq
    if
      global.get $subtask call $subtask-drop
      global.get $set call $set-drop
      call $publish i32.const 0 return
    end
    global.get $set i32.const 4 i32.shl i32.const 2 i32.or)
)
