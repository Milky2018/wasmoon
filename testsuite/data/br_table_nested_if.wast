;; Minimal crash test for br_table with nested if statements
;; This crashes when both case 0 and case 1 have if statements
(module
  (memory 1)

  (func (export "test") (param i32 i32) (result i32)
    (local i32 i32)
    (local.set 2 (i32.const 10))
    (block $5
      (block $4
        (block $3
          (block $2
            (block $1
              (block $0
                (br_table $0 $1 $2 $3 $4 $5 (local.get 0))
              )
              ;; case 0 - with if
              (if (i32.eq (local.get 1) (i32.const 0))
                (then
                  (local.set 3 (i32.const 100))
                )
              )
              (br $5)
            )
            ;; case 1 - with if (having both ifs causes crash)
            (if (i32.eq (local.get 1) (i32.const 0))
              (then
                (local.set 3 (i32.const 101))
              )
            )
            (br $5)
          )
          ;; case 2
          (br $5)
        )
        ;; case 3
        (br $5)
      )
      ;; case 4
      (br $5)
    )
    ;; case 5 / default
    (local.get 3)
  )
)
(assert_return (invoke "test" (i32.const 0) (i32.const 0)) (i32.const 100))
(assert_return (invoke "test" (i32.const 1) (i32.const 0)) (i32.const 101))
