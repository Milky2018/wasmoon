///|
test "fac_iter" {
  let source =
    #|(module
    #|  ;; Iterative factorial
    #|  (func (export "fac-iter") (param i64) (result i64)
    #|    (local i64 i64)
    #|    (local.set 1 (local.get 0))
    #|    (local.set 2 (i64.const 1))
    #|    (block
    #|      (loop
    #|        (if
    #|          (i64.eq (local.get 1) (i64.const 0))
    #|          (then (br 2))
    #|          (else
    #|            (local.set 2 (i64.mul (local.get 1) (local.get 2)))
    #|            (local.set 1 (i64.sub (local.get 1) (i64.const 1)))
    #|          )
    #|        )
    #|        (br 0)
    #|      )
    #|    )
    #|    (local.get 2)
    #|  )
    #|)
  let result = compare_jit_interp(source, "fac-iter", [I64(5)])
  inspect(result.matched(), content="true")
}

///|
// BUG: fac-rec returns wrong result (0 instead of 120 for n=5)
// Root cause: Register allocator doesn't spill caller-saved registers across calls
// After call_indirect, x3 still contains the call argument (n-1), not the original n
// So `mul x3, x8` computes (n-1)*fac(n-1) instead of n*fac(n-1)
test "fac_rec" {
  let source =
    #|(module
    #|  ;; Recursive factorial
    #|  (func (export "fac-rec") (param i64) (result i64)
    #|    (if (result i64) (i64.eq (local.get 0) (i64.const 0))
    #|      (then (i64.const 1))
    #|      (else
    #|        (i64.mul (local.get 0) (call 0 (i64.sub (local.get 0) (i64.const 1))))
    #|      )
    #|    )
    #|  )
    #|)
  let result = compare_jit_interp(source, "fac-rec", [I64(5)])
  inspect(result.matched(), content="true")
}
