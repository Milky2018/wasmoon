(module
  (memory 1)
  (func (export "test") (param i32) (result f32)
    (local f32 f32)
    (block $2
      (block $1
        (block $0
          (br_table $0 $1 $2 (local.get 0))
        )
        ;; case 0
        (local.set 1 (f32.const 2.0))
        (br $2)
      )
      ;; case 1
      (local.set 1 (f32.const 3.0))
      (br $2)
    )
    ;; case 2 / default
    (local.get 1)
  )
)
(assert_return (invoke "test" (i32.const 0)) (f32.const 2.0))
(assert_return (invoke "test" (i32.const 1)) (f32.const 3.0))
(assert_return (invoke "test" (i32.const 2)) (f32.const 0.0))
