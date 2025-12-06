(module
  ;; Simple function that adds two numbers
  (func (export "add") (param i32 i32) (result i32)
    local.get 0
    local.get 1
    i32.add
  )

  ;; Function that returns a constant
  (func (export "const42") (result i32)
    i32.const 42
  )

  ;; Function with a simple if-else
  (func (export "max") (param i32 i32) (result i32)
    local.get 0
    local.get 1
    i32.gt_s
    if (result i32)
      local.get 0
    else
      local.get 1
    end
  )

  ;; Simple loop that counts down
  (func (export "countdown") (param i32) (result i32)
    (local $i i32)
    (local.set $i (local.get 0))
    (block $done
      (loop $loop
        ;; if i <= 0, break
        (br_if $done (i32.le_s (local.get $i) (i32.const 0)))
        ;; i = i - 1
        (local.set $i (i32.sub (local.get $i) (i32.const 1)))
        ;; continue loop
        (br $loop)
      )
    )
    (local.get $i)
  )
)
