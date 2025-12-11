(module
  (memory 1)
  (func (export "test") (param i32) (result f32)
    (local f32 f32)
    (local.set 1 (f32.const 10.0))
    (block $3
      (block $2
        (block $1
          (block $0
            (br_table $0 $1 $2 $3 (local.get 0))
          )
          ;; case 0
          (f32.store (i32.const 0) (local.get 1))
          (local.set 2 (f32.load (i32.const 0)))
          (br $3)
        )
        ;; case 1
        (f32.store (i32.const 0) (local.get 1))
        (local.set 2 (f32.load (i32.const 0)))
        (br $3)
      )
      ;; case 2
      (f32.store (i32.const 0) (local.get 1))
      (local.set 2 (f32.load (i32.const 0)))
      (br $3)
    )
    ;; case 3 / default
    (local.get 2)
  )
)
(assert_return (invoke "test" (i32.const 0)) (f32.const 10.0))
(assert_return (invoke "test" (i32.const 1)) (f32.const 10.0))
(assert_return (invoke "test" (i32.const 2)) (f32.const 10.0))
;; case 3 jumps directly to end, local 2 is never set, returns default 0.0
(assert_return (invoke "test" (i32.const 3)) (f32.const 0.0))
