///|
test "AArch64 candidate executes production Wasm frontend output like legacy" {
  match @wasmoon_jit.host_target_arch() {
    AArch64 => ()
    _ => return
  }
  let source =
    #|(module
    #|  (func (export "add") (param i64 i64) (result i64)
    #|    local.get 0
    #|    local.get 1
    #|    i64.add)
    #|)
  let mod_ = @wat.parse(source)
  @validator.validate_module(mod_)
  let milk = @wasm_frontend.translate_function(
    @wasmoon.wasm_frontend_embedding_environment(),
    mod_,
    0,
    name="candidate_wasm_add",
  )
  let candidate_object = @wasmoon_jit.plan_wasm_body_aarch64_code_object(milk)
  debug_inspect(candidate_object.relocations(), content="[]")
  guard @wasmoon_jit.ExecCode::try_alloc(
      candidate_object.code().map(byte => byte.to_int()),
    )
    is Some(candidate) else {
    fail("failed to allocate executable candidate Wasm code")
  }
  let legacy_plan = @wasmoon_jit.plan_wasm_body_milkir_integration_for_target(
    milk,
    AArch64,
  )
  guard @wasmoon_jit.ExecCode::try_alloc(legacy_plan.object.get_bytes())
    is Some(legacy) else {
    fail("failed to allocate executable legacy Wasm code")
  }
  let trampoline_bytes = @wasmoon_jit.build_entry_trampoline_for_target(
    [I64, I64],
    [I64],
    AArch64,
  ) catch {
    error => fail("failed to build Wasm entry trampoline: \{error}")
  }
  guard @wasmoon_jit.ExecCode::try_alloc(trampoline_bytes) is Some(trampoline) else {
    fail("failed to allocate executable Wasm entry trampoline")
  }
  guard @wasmoon_jit.NativeJITContext::try_alloc(1) is Some(context) else {
    fail("failed to allocate native Wasm JIT context")
  }
  let candidate_values = FixedArray::from_array([20L, 22L, 0L])
  let candidate_trap = context.call_trampoline(
    trampoline.ptr(),
    candidate.ptr(),
    candidate_values,
    candidate_values.length(),
    false,
  )
  let legacy_values = FixedArray::from_array([20L, 22L, 0L])
  let legacy_trap = context.call_trampoline(
    trampoline.ptr(),
    legacy.ptr(),
    legacy_values,
    legacy_values.length(),
    false,
  )
  debug_inspect(
    (candidate_trap, candidate_values[2], legacy_trap, legacy_values[2]),
    content="(0, 42, 0, 42)",
  )
}
