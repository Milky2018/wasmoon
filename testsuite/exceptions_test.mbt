///|
/// Tests for WebAssembly exception handling
/// Covers: throw, try_table, catch handlers, throw_ref, locals preservation

///|
/// Basic test: throw and catch with no values
test "exception_throw_catch_simple" {
  let source =
    #|(module
    #|  (tag $e)
    #|  (func (export "test") (result i32)
    #|    (block $h
    #|      (try_table (catch $e $h)
    #|        (throw $e)
    #|      )
    #|      (return (i32.const 0))
    #|    )
    #|    (i32.const 42)
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
/// Test catch with exception values (i32)
test "exception_catch_with_i32_value" {
  let source =
    #|(module
    #|  (tag $e (param i32))
    #|  (func (export "test") (result i32)
    #|    (block $h (result i32)
    #|      (try_table (catch $e $h)
    #|        (throw $e (i32.const 42))
    #|      )
    #|      (return (i32.const 0))
    #|    )
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
/// Test catch with multiple exception values
test "exception_catch_with_multiple_values" {
  let source =
    #|(module
    #|  (tag $e (param i32 i32))
    #|  (func (export "test") (result i32)
    #|    (block $h (result i32 i32)
    #|      (try_table (catch $e $h)
    #|        (throw $e (i32.const 10) (i32.const 20))
    #|      )
    #|      (return (i32.const 0))
    #|    )
    #|    (i32.add)
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
/// Test try_table with no exception - normal path
test "exception_try_table_no_throw" {
  let source =
    #|(module
    #|  (tag $e)
    #|  (func (export "test") (result i32)
    #|    (block $h
    #|      (try_table (result i32) (catch $e $h)
    #|        (i32.const 42)
    #|      )
    #|      (return)
    #|    )
    #|    (i32.const 0)
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
/// Test catch_all handler
test "exception_catch_all" {
  let source =
    #|(module
    #|  (tag $e1)
    #|  (tag $e2)
    #|  (func (export "test") (result i32)
    #|    (block $h
    #|      (try_table (catch_all $h)
    #|        (throw $e2)
    #|      )
    #|      (return (i32.const 0))
    #|    )
    #|    (i32.const 1)
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
/// Test catch_ref handler - catches exception reference
test "exception_catch_ref" {
  let source =
    #|(module
    #|  (tag $e)
    #|  (func (export "test") (result i32)
    #|    (block $h (result exnref)
    #|      (try_table (catch_ref $e $h)
    #|        (throw $e)
    #|      )
    #|      (return (i32.const 0))
    #|    )
    #|    (drop)
    #|    (i32.const 42)
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
/// Test throw_ref - re-throw caught exception
test "exception_throw_ref_rethrow" {
  let source =
    #|(module
    #|  (tag $e)
    #|  (func (export "test") (result i32)
    #|    (block $outer
    #|      (block $h (result exnref)
    #|        (try_table (catch_ref $e $h)
    #|          (throw $e)
    #|        )
    #|        (br $outer)
    #|      )
    #|      (block $h2 (result exnref)
    #|        (try_table (catch_ref $e $h2)
    #|          (throw_ref)
    #|        )
    #|        (br $outer)
    #|      )
    #|      (drop)
    #|      (return (i32.const 23))
    #|    )
    #|    (i32.const 42)
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
/// Test locals preservation in try_table - normal path
/// Locals modified in try body should be visible after try_table
test "exception_locals_normal_path" {
  let source =
    #|(module
    #|  (tag $e)
    #|  (func (export "test") (result i32)
    #|    (local $x i32)
    #|    (local.set $x (i32.const 10))
    #|    (block $h
    #|      (try_table (catch $e $h)
    #|        (local.set $x (i32.const 42))
    #|      )
    #|    )
    #|    (local.get $x)
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
/// Test locals in exception path - locals should have pre-body values
test "exception_locals_exception_path" {
  let source =
    #|(module
    #|  (tag $e)
    #|  (func (export "test") (result i32)
    #|    (local $x i32)
    #|    (local.set $x (i32.const 10))
    #|    (block $h
    #|      (try_table (catch $e $h)
    #|        (local.set $x (i32.const 99))
    #|        (throw $e)
    #|      )
    #|    )
    #|    (local.get $x)
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
/// Test nested try_table
test "exception_nested_try" {
  let source =
    #|(module
    #|  (tag $e1)
    #|  (tag $e2)
    #|  (func (export "test") (result i32)
    #|    (block $h1
    #|      (try_table (catch $e1 $h1)
    #|        (block $h2
    #|          (try_table (catch $e2 $h2)
    #|            (throw $e1)
    #|          )
    #|          (return (i32.const 0))
    #|        )
    #|        (return (i32.const 1))
    #|      )
    #|      (return (i32.const 2))
    #|    )
    #|    (i32.const 42)
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
/// Test exception across function call
test "exception_cross_function" {
  let source =
    #|(module
    #|  (tag $e (param i32))
    #|  (func $throw-it (throw $e (i32.const 5)))
    #|  (func (export "test") (result i32)
    #|    (block $h (result i32)
    #|      (try_table (catch $e $h)
    #|        (call $throw-it)
    #|      )
    #|      (return (i32.const 0))
    #|    )
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
/// Test catch_all_ref handler
test "exception_catch_all_ref" {
  let source =
    #|(module
    #|  (tag $e)
    #|  (func (export "test") (result i32)
    #|    (block $h (result exnref)
    #|      (try_table (catch_all_ref $h)
    #|        (throw $e)
    #|      )
    #|      (unreachable)
    #|    )
    #|    (drop)
    #|    (i32.const 42)
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
/// Test conditional re-throw with throw_ref
test "exception_conditional_throw_ref" {
  let source =
    #|(module
    #|  (tag $e0)
    #|  (func (export "test") (param i32) (result i32)
    #|    (block $h (result exnref)
    #|      (try_table (catch_ref $e0 $h)
    #|        (throw $e0)
    #|      )
    #|      (return (i32.const 0))
    #|    )
    #|    (if (param exnref) (i32.eqz (local.get 0))
    #|      (then (throw_ref))
    #|      (else (drop))
    #|    )
    #|    (i32.const 23)
    #|  )
    #|)
  // Test case where we don't re-throw (arg = 1)
  let result1 = compare_jit_interp(source, "test", [@types.Value::I32(1)])
  inspect(result1, content="matched")
}

///|
/// Test f64 exception values
test "exception_f64_values" {
  let source =
    #|(module
    #|  (tag $e (param f64))
    #|  (func (export "test") (result f64)
    #|    (block $h (result f64)
    #|      (try_table (catch $e $h)
    #|        (throw $e (f64.const 3.14159))
    #|      )
    #|      (return (f64.const 0))
    #|    )
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
/// Test mixed type exception values (i32, i64)
test "exception_mixed_type_values" {
  let source =
    #|(module
    #|  (tag $e (param i32 i64))
    #|  (func (export "test") (result i32)
    #|    (block $h (result i32 i64)
    #|      (try_table (catch $e $h)
    #|        (throw $e (i32.const 1) (i64.const 2))
    #|      )
    #|      (return (i32.const 0))
    #|    )
    #|    (drop)
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
/// Test multiple catch handlers - first matching wins
test "exception_multiple_catch_handlers" {
  let source =
    #|(module
    #|  (tag $e1 (param i32))
    #|  (tag $e2 (param i32))
    #|  (func (export "test") (result i32)
    #|    (block $h1 (result i32)
    #|      (block $h2 (result i32)
    #|        (try_table
    #|          (catch $e1 $h1)
    #|          (catch $e2 $h2)
    #|          (throw $e2 (i32.const 20))
    #|        )
    #|        (return (i32.const 0))
    #|      )
    #|      (i32.const 100)
    #|      (i32.add)
    #|      (return)
    #|    )
    #|    (i32.const 1000)
    #|    (i32.add)
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}

///|
/// Test try_table with params and results
test "exception_try_table_with_params" {
  let source =
    #|(module
    #|  (tag $e)
    #|  (func (export "test") (result i32)
    #|    (block $h
    #|      (i32.const 10)
    #|      (try_table (param i32) (result i32) (catch $e $h)
    #|        (i32.const 32)
    #|        (i32.add)
    #|      )
    #|      (return)
    #|    )
    #|    (i32.const 0)
    #|  )
    #|)
  let result = compare_jit_interp(source, "test", [])
  inspect(result, content="matched")
}
