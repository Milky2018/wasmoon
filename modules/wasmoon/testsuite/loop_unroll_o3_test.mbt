///|
fn require_o3_jit_match(
  source : String,
  function_name : String,
  expect_trap? : Bool = false,
) -> Unit raise {
  match run_interp_only(source, function_name, []) {
    Ok(_) => if expect_trap { fail("expected interpreter trap") }
    Err(error) =>
      if !expect_trap {
        fail("expected successful interpreter execution: \{error}")
      }
  }
  let result = compare_jit_interp_with_opt_level(source, function_name, [], 3)
  if !compare_result_is_match(result) {
    fail("O3 JIT and interpreter results differed")
  }
}

///|
fn generated_counted_loop_wat(
  integer_type : String,
  initial : String,
  bound : String,
  step : String,
  condition : String,
  update : String,
) -> String {
  let template =
    #|(module
    #|  (func (export "run") (result i32)
    #|    (local $i __TYPE__)
    #|    (local $count i32)
    #|    __TYPE__.const __INITIAL__
    #|    local.set $i
    #|    block $exit
    #|      loop $loop
    #|        local.get $i
    #|        __TYPE__.const __BOUND__
    #|        __TYPE__.__CONDITION__
    #|        i32.eqz
    #|        br_if $exit
    #|        local.get $count
    #|        i32.const 1
    #|        i32.add
    #|        local.set $count
    #|        local.get $i
    #|        __TYPE__.const __STEP__
    #|        __TYPE__.__UPDATE__
    #|        local.set $i
    #|        br $loop
    #|      end
    #|    end
    #|    local.get $count)
    #|)
  template
  .replace(old="__TYPE__", new=integer_type)
  .replace(old="__TYPE__", new=integer_type)
  .replace(old="__TYPE__", new=integer_type)
  .replace(old="__TYPE__", new=integer_type)
  .replace(old="__TYPE__", new=integer_type)
  .replace(old="__TYPE__", new=integer_type)
  .replace(old="__INITIAL__", new=initial)
  .replace(old="__BOUND__", new=bound)
  .replace(old="__STEP__", new=step)
  .replace(old="__CONDITION__", new=condition)
  .replace(old="__UPDATE__", new=update)
}

///|
test "O3 loop unrolling matches reductions for odd and even trip counts" {
  require_o3_jit_match(
    (
      #|(module
      #|  (func (export "sum10") (result i32)
      #|    (local $i i32) (local $sum i32)
      #|    block $exit
      #|      loop $loop
      #|        local.get $i
      #|        i32.const 10
      #|        i32.ge_s
      #|        br_if $exit
      #|        local.get $sum
      #|        local.get $i
      #|        i32.add
      #|        local.set $sum
      #|        local.get $i
      #|        i32.const 1
      #|        i32.add
      #|        local.set $i
      #|        br $loop
      #|      end
      #|    end
      #|    local.get $sum)
      #|)
    ),
    "sum10",
  )
  require_o3_jit_match(
    (
      #|(module
      #|  (func (export "sum11") (result i32)
      #|    (local $i i32) (local $sum i32)
      #|    block $exit
      #|      loop $loop
      #|        local.get $i
      #|        i32.const 11
      #|        i32.ge_s
      #|        br_if $exit
      #|        local.get $sum
      #|        local.get $i
      #|        i32.add
      #|        local.set $sum
      #|        local.get $i
      #|        i32.const 1
      #|        i32.add
      #|        local.set $i
      #|        br $loop
      #|      end
      #|    end
      #|    local.get $sum)
      #|)
    ),
    "sum11",
  )
}

///|
test "O3 loop unrolling matches memory effects and calls" {
  require_o3_jit_match(
    (
      #|(module
      #|  (memory 1)
      #|  (func (export "memory_loop") (result i32)
      #|    (local $i i32)
      #|    block $exit
      #|      loop $loop
      #|        local.get $i
      #|        i32.const 5
      #|        i32.ge_s
      #|        br_if $exit
      #|        i32.const 0
      #|        local.get $i
      #|        i32.store
      #|        local.get $i
      #|        i32.const 1
      #|        i32.add
      #|        local.set $i
      #|        br $loop
      #|      end
      #|    end
      #|    i32.const 0
      #|    i32.load)
      #|)
    ),
    "memory_loop",
  )
  require_o3_jit_match(
    (
      #|(module
      #|  (func $bump (param i32) (result i32)
      #|    local.get 0
      #|    i32.const 3
      #|    i32.add)
      #|  (func (export "call_loop") (result i32)
      #|    (local $i i32) (local $sum i32)
      #|    block $exit
      #|      loop $loop
      #|        local.get $i
      #|        i32.const 9
      #|        i32.ge_s
      #|        br_if $exit
      #|        local.get $sum
      #|        local.get $i
      #|        call $bump
      #|        i32.add
      #|        local.set $sum
      #|        local.get $i
      #|        i32.const 1
      #|        i32.add
      #|        local.set $i
      #|        br $loop
      #|      end
      #|    end
      #|    local.get $sum)
      #|)
    ),
    "call_loop",
  )
}

///|
test "O3 loop unrolling matches traps and boundary loops" {
  require_o3_jit_match(
    (
      #|(module
      #|  (func (export "trap_loop")
      #|    (local $i i32)
      #|    block $exit
      #|      loop $loop
      #|        local.get $i
      #|        i32.const 3
      #|        i32.ge_s
      #|        br_if $exit
      #|        i32.const 1
      #|        i32.const 0
      #|        i32.div_s
      #|        drop
      #|        local.get $i
      #|        i32.const 1
      #|        i32.add
      #|        local.set $i
      #|        br $loop
      #|      end
      #|    end)
      #|)
    ),
    "trap_loop",
    expect_trap=true,
  )
  require_o3_jit_match(
    generated_counted_loop_wat(
      "i64", "9223372036854775806", "9223372036854775807", "1", "lt_s", "add",
    ),
    "run",
  )
}

///|
test "O3 generated counted loops cover predicate and step combinations" {
  let cases = [
    ("i32", "0", "10", "3", "lt_s", "add"),
    ("i32", "0", "10", "3", "le_s", "add"),
    ("i32", "10", "2", "3", "gt_s", "sub"),
    ("i32", "10", "2", "3", "ge_u", "sub"),
    ("i64", "0", "10", "3", "lt_u", "add"),
    ("i64", "0", "10", "3", "le_u", "add"),
    ("i64", "10", "2", "3", "gt_u", "sub"),
    ("i64", "10", "2", "3", "ge_s", "sub"),
  ]
  for item in cases {
    let (integer_type, initial, bound, step, condition, update) = item
    require_o3_jit_match(
      generated_counted_loop_wat(
        integer_type, initial, bound, step, condition, update,
      ),
      "run",
    )
  }
}
