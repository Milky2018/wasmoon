///|
test "f32_min_basic" {
  let source =
    #|(module
    #|  (func (export "min") (param f32 f32) (result f32)
    #|    (f32.min (local.get 0) (local.get 1))
    #|  )
    #|)
  // min(1.0, 2.0) should return 1.0
  let result = compare_jit_interp(source, "min", [F32(1.0), F32(2.0)])
  inspect(result, content="matched")
}

///|
test "f32_max_basic" {
  let source =
    #|(module
    #|  (func (export "max") (param f32 f32) (result f32)
    #|    (f32.max (local.get 0) (local.get 1))
    #|  )
    #|)
  // max(1.0, 2.0) should return 2.0
  let result = compare_jit_interp(source, "max", [F32(1.0), F32(2.0)])
  inspect(result, content="matched")
}

///|
test "f32_min_negative" {
  let source =
    #|(module
    #|  (func (export "min") (param f32 f32) (result f32)
    #|    (f32.min (local.get 0) (local.get 1))
    #|  )
    #|)
  // min(-1.0, 1.0) should return -1.0
  let result = compare_jit_interp(source, "min", [F32(-1.0), F32(1.0)])
  inspect(result, content="matched")
}

///|
test "f32_max_negative" {
  let source =
    #|(module
    #|  (func (export "max") (param f32 f32) (result f32)
    #|    (f32.max (local.get 0) (local.get 1))
    #|  )
    #|)
  // max(-1.0, 1.0) should return 1.0
  let result = compare_jit_interp(source, "max", [F32(-1.0), F32(1.0)])
  inspect(result, content="matched")
}

///|
test "f64_min_basic" {
  let source =
    #|(module
    #|  (func (export "min") (param f64 f64) (result f64)
    #|    (f64.min (local.get 0) (local.get 1))
    #|  )
    #|)
  // min(1.0, 2.0) should return 1.0
  let result = compare_jit_interp(source, "min", [F64(1.0), F64(2.0)])
  inspect(result, content="matched")
}

///|
test "f64_max_basic" {
  let source =
    #|(module
    #|  (func (export "max") (param f64 f64) (result f64)
    #|    (f64.max (local.get 0) (local.get 1))
    #|  )
    #|)
  // max(1.0, 2.0) should return 2.0
  let result = compare_jit_interp(source, "max", [F64(1.0), F64(2.0)])
  inspect(result, content="matched")
}
