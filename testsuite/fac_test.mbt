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

///|
test "fac_ssa" {
  let source =
    #|(module
    #|  ;; Iterative factorial without locals.
    #|  (func $pick0 (param i64) (result i64 i64)
    #|    (local.get 0) (local.get 0)
    #|  )
    #|  (func $pick1 (param i64 i64) (result i64 i64 i64)
    #|    (local.get 0) (local.get 1) (local.get 0)
    #|  )
    #|  (func (export "fac-ssa") (param i64) (result i64)
    #|    (i64.const 1) (local.get 0)
    #|    (loop $l (param i64 i64) (result i64)
    #|      (call $pick1) (call $pick1) (i64.mul)
    #|      (call $pick1) (i64.const 1) (i64.sub)
    #|      (call $pick0) (i64.const 0) (i64.gt_u)
    #|      (br_if $l)
    #|      (drop) (return)
    #|    )
    #|  )
    #|)
  let result = compare_jit_interp(source, "fac-ssa", [I64(5)])
  inspect(result.matched(), content="true")
}
