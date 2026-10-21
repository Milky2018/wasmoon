;; Keep a native timer pending while HTTP needs the same host scheduler.
;; A completed HTTP exchange cancels the timer; waiting synchronously deadlocks.
(module
  (import "wasi:clocks/monotonic-clock@0.3.0" "[async-lower]wait-for" (func $timer (param i64) (result i32)))
  (import "wasi:http/types@0.3.0" "[constructor]fields" (func $fields (result i32)))
  (import "wasi:http/types@0.3.0" "[static]request.new" (func $request (param i32 i32 i32 i32 i32 i32 i32)))
  (import "wasi:http/types@0.3.0" "[method]request.set-authority" (func $authority (param i32 i32 i32 i32) (result i32)))
  (import "wasi:http/types@0.3.0" "[future-new-1][static]request.new" (func $future (result i64)))
  (import "wasi:http/types@0.3.0" "[async-lower][future-write-1][static]request.new" (func $write (param i32 i32) (result i32)))
  (import "wasi:http/types@0.3.0" "[future-drop-writable-1][static]request.new" (func $drop-writer (param i32)))
  (import "wasi:http/types@0.3.0" "[future-drop-readable-2][static]request.new" (func $drop-receipt (param i32)))
  (import "wasi:http/types@0.3.0" "[resource-drop]response" (func $drop-response (param i32)))
  (import "wasi:http/client@0.3.0" "[async-lower]send" (func $send (param i32 i32) (result i32)))
  (import "$root" "[waitable-set-new]" (func $set-new (result i32)))
  (import "$root" "[waitable-join]" (func $join (param i32 i32)))
  (import "$root" "[waitable-set-drop]" (func $set-drop (param i32)))
  (import "$root" "[subtask-drop]" (func $subtask-drop (param i32)))
  (import "$root" "[subtask-cancel]" (func $cancel (param i32) (result i32)))
  (import "[export]wasi:cli/run@0.3.0" "[task-return]run" (func $return (param i32)))
  (memory (export "memory") 2)
  (data (i32.const 64) "127.0.0.1:PORT")
  (global $heap (mut i32) (i32.const 4096))
  (global $set (mut i32) (i32.const 0))
  (global $timer (mut i32) (i32.const 0))
  (global $send (mut i32) (i32.const 0))
  (global $writer (mut i32) (i32.const 0))
  (global $written (mut i32) (i32.const 0))
  (global $received (mut i32) (i32.const 0))
  (func (export "cabi_realloc") (param i32 i32 i32 i32) (result i32)
    (local $ptr i32)
    global.get $heap local.get 2 i32.const 1 i32.sub i32.add
    i32.const 0 local.get 2 i32.sub i32.and
    local.tee $ptr local.get 3 i32.add global.set $heap local.get $ptr)
  (func (export "[async-lift]wasi:cli/run@0.3.0#run") (result i32)
    (local $pair i64)
    call $set-new global.set $set
    i64.const 60000000000 call $timer i32.const 4 i32.shr_u global.set $timer
    global.get $timer global.get $set call $join
    call $future local.tee $pair i64.const 32 i64.shr_u i32.wrap_i64 global.set $writer
    global.get $writer i32.const 256 call $write drop
    global.get $writer global.get $set call $join
    call $fields i32.const 0 i32.const 0 local.get $pair i32.wrap_i64
    i32.const 0 i32.const 0 i32.const 512 call $request
    i32.const 516 i32.load call $drop-receipt
    i32.const 512 i32.load i32.const 1 i32.const 64 i32.const AUTHORITY_LENGTH call $authority
    if unreachable end
    i32.const 512 i32.load i32.const 1024 call $send i32.const 4 i32.shr_u global.set $send
    global.get $send global.get $set call $join
    global.get $set i32.const 4 i32.shl i32.const 2 i32.or)
  (func (export "[callback][async-lift]wasi:cli/run@0.3.0#run") (param $event i32) (param $handle i32) (param $status i32) (result i32)
    local.get $handle global.get $writer i32.eq
    if
      global.get $writer call $drop-writer
      i32.const 1 global.set $written
    end
    local.get $handle global.get $send i32.eq local.get $status i32.const 2 i32.eq i32.and
    if
      i32.const 1024 i32.load8_u if unreachable end
      i32.const 1032 i32.load call $drop-response
      global.get $send call $subtask-drop
      i32.const 1 global.set $received
    end
    global.get $written global.get $received i32.and
    if
      global.get $timer i32.const 0 call $join
      global.get $timer call $cancel drop
      global.get $timer call $subtask-drop
      global.get $set call $set-drop
      i32.const 0 call $return
      i32.const 0 return
    end
    global.get $set i32.const 4 i32.shl i32.const 2 i32.or)
)
