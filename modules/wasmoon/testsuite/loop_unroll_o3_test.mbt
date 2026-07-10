///|
fn require_o3_jit_match(
  source : String,
  function_name : String,
  expected_trap? : String? = None,
) -> Unit raise {
  match run_interp_only(source, function_name, []) {
    Ok(_) => if expected_trap is Some(_) { fail("expected interpreter trap") }
    Err(error) =>
      if expected_trap is None {
        fail("expected successful interpreter execution: \{error}")
      }
  }
  let result = compare_jit_interp_with_opt_level(source, function_name, [], 3)
  if !compare_result_is_match(result) {
    fail("O3 JIT and interpreter results differed")
  }
  if expected_trap is Some(expected) &&
    !compare_result_errors_contain(result, expected) {
    fail("O3 JIT and interpreter did not report the expected trap: \{expected}")
  }
}

///|
fn optimized_milkir(
  source : String,
  function_name : String,
) -> (String, String) raise {
  let mod_ = @wat.parse(source)
  @validator.validate_module(mod_)
  let mut exported_func_idx = None
  for exp in mod_.exports {
    if exp.name == function_name && exp.desc is Func(idx) {
      exported_func_idx = Some(idx)
      break
    }
  }
  guard exported_func_idx is Some(func_idx) else {
    fail("function not found: \{function_name}")
  }
  let local_idx = func_idx - @wast.count_func_imports(mod_.imports)
  let milk = @wasm_frontend.translate_function(
    @wasmoon.wasm_frontend_embedding_environment(),
    mod_,
    local_idx,
    name=function_name,
  )
  let before = milk.print()
  @milkir.optimize_with_level(milk, O3) |> ignore
  (before, milk.print())
}

///|
fn require_o3_duplicates_loop_effect(
  source : String,
  function_name : String,
  effect_text : String,
) -> Unit raise {
  let (before, after) = optimized_milkir(source, function_name)
  let before_count = before.split(effect_text).count() - 1
  let after_count = after.split(effect_text).count() - 1
  if before_count == 0 || after_count <= before_count {
    fail(
      "expected O3 loop unrolling to duplicate '\{effect_text}': before=\{before_count}, after=\{after_count}",
    )
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
  reverse_compare? : Bool = false,
  continue_on_true? : Bool = false,
) -> String {
  let compare_operands = if reverse_compare {
    "        __TYPE__.const __BOUND__\n        local.get $i"
  } else {
    "        local.get $i\n        __TYPE__.const __BOUND__"
  }
  let continue_block = if continue_on_true {
    "      block $continue\n"
  } else {
    ""
  }
  let branch = if continue_on_true {
    "        br_if $continue\n        br $exit\n      end\n"
  } else {
    "        br_if $exit\n"
  }
  let template =
    #|(module
    #|  (func (export "run") (result i32)
    #|    (local $i __TYPE__)
    #|    (local $count i32)
    #|    __TYPE__.const __INITIAL__
    #|    local.set $i
    #|    block $exit
    #|      loop $loop
    #|__CONTINUE_BLOCK____COMPARE_OPERANDS__
    #|        __TYPE__.__CONDITION__
    #|__BRANCH__
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
  .replace(old="__CONTINUE_BLOCK__", new=continue_block)
  .replace(old="__COMPARE_OPERANDS__", new=compare_operands)
  .replace(old="__BRANCH__", new=branch)
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
  let memory_source =
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
  require_o3_jit_match(memory_source, "memory_loop")
  require_o3_duplicates_loop_effect(
    memory_source, "memory_loop", "store_ptr.i32",
  )
  let call_source =
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
  require_o3_jit_match(call_source, "call_loop")
  require_o3_duplicates_loop_effect(call_source, "call_loop", "ext.wasm.call")
}

///|
test "O3 loop unrolling matches traps and boundary loops" {
  let trap_source =
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
  require_o3_jit_match(
    trap_source,
    "trap_loop",
    expected_trap=Some("integer divide by zero"),
  )
  require_o3_duplicates_loop_effect(trap_source, "trap_loop", "sdiv")
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
    ("i32", "0", "31", "3", "ge_s", "add", false, false),
    ("i32", "0", "30", "3", "gt_s", "add", false, false),
    ("i32", "31", "2", "3", "le_s", "sub", false, false),
    ("i32", "31", "2", "3", "lt_u", "sub", false, false),
    ("i64", "0", "31", "3", "ge_u", "add", false, false),
    ("i64", "0", "30", "3", "gt_u", "add", false, false),
    ("i64", "31", "2", "3", "le_u", "sub", false, false),
    ("i64", "31", "2", "3", "lt_s", "sub", false, false),
    ("i32", "31", "2", "-3", "le_s", "add", false, false),
    ("i64", "31", "2", "-3", "le_s", "add", false, false),
    ("i32", "0", "31", "3", "le_s", "add", true, false),
  ]
  for item in cases {
    let (
      integer_type,
      initial,
      bound,
      step,
      condition,
      update,
      reverse_compare,
      continue_on_true,
    ) = item
    let source = generated_counted_loop_wat(
      integer_type,
      initial,
      bound,
      step,
      condition,
      update,
      reverse_compare~,
      continue_on_true~,
    )
    require_o3_jit_match(source, "run")
    require_o3_duplicates_loop_effect(source, "run", "iadd")
  }
}

///|
test "O3 safely skips structured branch shapes outside the supported subset" {
  let source = generated_counted_loop_wat(
    "i32",
    "0",
    "31",
    "3",
    "lt_s",
    "add",
    continue_on_true=true,
  )
  require_o3_jit_match(source, "run")
  let (before, after) = optimized_milkir(source, "run")
  inspect(before.split("iadd").count(), content="3")
  inspect(after.split("iadd").count(), content="3")
}
