(module
  (memory 1)
  (func (export "test") (param i32) (result i32)
    (local i32 i32)
    (block $2
      (block $1
        (block $0
          (br_table $0 $1 $2 (local.get 0))
        )
        ;; case 0
        (local.set 1 (i32.const 2))
        (br $2)
      )
      ;; case 1
      (local.set 1 (i32.const 3))
      (br $2)
    )
    ;; case 2 / default
    (local.get 1)
  )
)
(assert_return (invoke "test" (i32.const 0)) (i32.const 2))
(assert_return (invoke "test" (i32.const 1)) (i32.const 3))
(assert_return (invoke "test" (i32.const 2)) (i32.const 0))
