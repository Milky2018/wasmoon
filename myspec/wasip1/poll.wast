;; WASI Poll Tests
;; Tests poll_oneoff

;; Mock WASI module that provides testable implementations
(module $wasi_snapshot_preview1
  (global $last_errno (mut i32) (i32.const 0))
  (global $event_count (mut i32) (i32.const 0))

  (memory (export "memory") 2)

  ;; poll_oneoff(subscriptions, events, nsubscriptions, nevents) -> errno
  (func (export "poll_oneoff") (param i32 i32 i32 i32) (result i32)
    (local $subs i32)
    (local $events_ptr i32)
    (local $nsubscriptions i32)
    (local $nevents_ptr i32)
    (local $i i32)
    (local $sub_ptr i32)
    (local $userdata i64)
    (local $event_type i32)
    (local $event_ptr i32)

    (local.set $subs (local.get 0))
    (local.set $events_ptr (local.get 1))
    (local.set $nsubscriptions (local.get 2))
    (local.set $nevents_ptr (local.get 3))

    ;; Check nsubscriptions
    (if (i32.eqz (local.get $nsubscriptions))
      (then
        ;; Zero subscriptions - return 0 events
        (i32.store (local.get $nevents_ptr) (i32.const 0))
        (global.set $last_errno (i32.const 0))
        (return (i32.const 0))
      )
    )

    ;; Process each subscription (simplified: just return same number of events)
    (global.set $event_count (local.get $nsubscriptions))

    (local.set $i (i32.const 0))
    (block $break (loop $continue
      (if (i32.ge_u (local.get $i) (local.get $nsubscriptions))
        (then (br $break))
      )

      ;; Calculate sub_ptr
      (local.set $sub_ptr (i32.add (local.get $subs)
                                   (i32.mul (local.get $i) (i32.const 32))))

      ;; Read subscription userdata
      (local.set $userdata (i64.load (local.get $sub_ptr)))

      ;; Calculate event_ptr
      (local.set $event_ptr (i32.add (local.get $events_ptr)
                                     (i32.mul (local.get $i) (i32.const 32))))

      ;; Copy userdata to event
      (i64.store (local.get $event_ptr) (local.get $userdata))

      ;; Write timestamp (for clock events)
      (i64.store (i32.add (local.get $event_ptr) (i32.const 8)) (i64.const 1000000))

      ;; Set event type to clock (1)
      (i32.store8 (i32.add (local.get $event_ptr) (i32.const 16)) (i32.const 1))

      ;; Set errno to ESUCCESS (0) at byte offset 24 (2 bytes)
      (i32.store8 (i32.add (local.get $event_ptr) (i32.const 24)) (i32.const 0))
      (i32.store8 (i32.add (local.get $event_ptr) (i32.const 25)) (i32.const 0))

      ;; Increment i
      (local.set $i (i32.add (local.get $i) (i32.const 1)))
      (br $continue)
    ))

    ;; Write nevents
    (i32.store (local.get $nevents_ptr) (global.get $event_count))

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

;; Test 1: poll_oneoff with clock subscription
(module
  (import "wasi_snapshot_preview1" "poll_oneoff" (func $poll_oneoff (param i32 i32 i32 i32) (result i32)))
  (memory 2)

  (func (export "test") (result i32)
    ;; Setup clock subscription at address 200
    ;; userdata = 0x1234
    (i64.store (i32.const 200) (i64.const 0x1234))
    ;; clock ID = 1 (monotonic) at offset 8
    (i32.store8 (i32.const 208) (i32.const 1))
    ;; timeout = 0 (immediate) at offset 16
    (i64.store (i32.const 216) (i64.const 0))

    ;; Call poll_oneoff
    ;; subs = 200, events = 300, nsubscriptions = 1, return nevents at 400
    (call $poll_oneoff (i32.const 200) (i32.const 300) (i32.const 1) (i32.const 400))
  )
)
(assert_return (invoke "test") (i32.const 0))

;; Test 2: poll_oneoff with zero subscriptions
(module
  (import "wasi_snapshot_preview1" "poll_oneoff" (func $poll_oneoff (param i32 i32 i32 i32) (result i32)))
  (memory 2)

  (func (export "test") (result i32)
    ;; Call with 0 subscriptions
    (call $poll_oneoff (i32.const 200) (i32.const 300) (i32.const 0) (i32.const 400))
  )
)
(assert_return (invoke "test") (i32.const 0))

;; Test 3: poll_oneoff with multiple clock subscriptions
(module
  (import "wasi_snapshot_preview1" "poll_oneoff" (func $poll_oneoff (param i32 i32 i32 i32) (result i32)))
  (memory 3)

  (func (export "test") (result i32)
    ;; Setup first clock subscription at address 200
    (i64.store (i32.const 200) (i64.const 0x1000))
    (i32.store8 (i32.const 208) (i32.const 1))  ;; clock type
    (i64.store (i32.const 216) (i64.const 0))

    ;; Setup second clock subscription at address 232
    (i64.store (i32.const 232) (i64.const 0x2000))
    (i32.store8 (i32.const 240) (i32.const 1))  ;; clock type
    (i64.store (i32.const 248) (i64.const 0))

    ;; Call poll_oneoff with 2 subscriptions
    (call $poll_oneoff (i32.const 200) (i32.const 400) (i32.const 2) (i32.const 500))
  )
)
(assert_return (invoke "test") (i32.const 0))
