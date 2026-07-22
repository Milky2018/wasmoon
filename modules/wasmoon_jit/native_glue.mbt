///|
pub(all) enum NativeGlueKind {
  ExecutableMemory
  TrapHandler
  StackSwitch
  HostCallBridge
  WasmMemoryOp
  GcRuntime
  ExceptionHandling
  WasiPreview1
  DebugInfo
} derive(Eq, Debug)

///|
pub(all) struct NativeGlueBinding {
  kind : NativeGlueKind
  symbol : String
  sources : Array[String]
} derive(Eq, Debug)

///|
pub(all) struct JitIntegrationPlan {
  entry_symbol : String
  target : NativeTarget
  native_glue : Array[NativeGlueBinding]
  object : JitCodeObject
}

///|
/// Stable, read-only renderings of the final native compilation checkpoints.
/// Concrete target instruction, allocation, and frame types remain owned by
/// their target modules and do not cross this diagnostics facade.
pub struct JitPipelineDiagnostics {
  semantic_machv : String
  target_vcode : String
  allocated_vcode : String
  code_object : String
  machine_code : String
} derive(Debug)

///|
fn code_object_diagnostic_text(
  object : @code_object.UnlinkedCodeObject,
) -> String {
  let architecture = match object.architecture() {
    AArch64 => "aarch64"
    X64 => "x64"
  }
  let code = object.code()
  let bytes = code.map(byte => @types.to_hex_byte(byte.to_int())).join(" ")
  "code-object \{architecture}\n" +
  "  code-size: \{code.length()}\n" +
  "  relocations: \{to_repr(object.relocations())}\n" +
  "  sources: \{to_repr(object.sources())}\n" +
  "  traps: \{to_repr(object.traps())}\n" +
  "  safepoints: \{to_repr(object.safepoints())}\n" +
  "  unwind: \{to_repr(object.unwind())}\n" +
  "  bytes: \{bytes}"
}

///|
pub suberror JitPipelineError {
  PipelineFailure(message~ : String)
} derive(Debug, Eq)

///|
pub impl Show for JitPipelineError with fn output(self, logger) {
  logger.write_string(to_repr(self).to_string())
}

///|
pub fn jit_ffi_native_stub_sources() -> Array[String] {
  [
    "jit.c", "trap.c", "exec_mem.c", "jit_context.c", "memory_ops.c", "segment_ops.c",
    "gc_type_cache.c", "gc_ops.c", "gc_allocator.c", "gc_heap.c", "exception.c",
    "wasi.c", "wasm_stack.c", "trampoline_call_x86_64.S", "stack_switch_aarch64.S",
    "stack_switch_x86_64.S", "dwarf.c",
  ]
}

///|
pub fn default_native_glue() -> Array[NativeGlueBinding] {
  [
    {
      kind: ExecutableMemory,
      symbol: "wasmoon_jit_exec_mem",
      sources: ["exec_mem.c"],
    },
    { kind: TrapHandler, symbol: "wasmoon_jit_trap", sources: ["trap.c"] },
    {
      kind: StackSwitch,
      symbol: "wasmoon_jit_stack_switch",
      sources: [
        "wasm_stack.c", "trampoline_call_x86_64.S", "stack_switch_aarch64.S", "stack_switch_x86_64.S",
      ],
    },
    {
      kind: HostCallBridge,
      symbol: "wasmoon_jit_hostcall",
      sources: ["jit.c", "jit_context.c"],
    },
    {
      kind: WasmMemoryOp,
      symbol: "wasmoon_jit_memory_op",
      sources: ["memory_ops.c", "segment_ops.c"],
    },
    {
      kind: GcRuntime,
      symbol: "wasmoon_jit_gc",
      sources: ["gc_type_cache.c", "gc_ops.c", "gc_allocator.c", "gc_heap.c"],
    },
    {
      kind: ExceptionHandling,
      symbol: "wasmoon_jit_exception",
      sources: ["exception.c"],
    },
    { kind: WasiPreview1, symbol: "wasmoon_jit_wasi", sources: ["wasi.c"] },
    { kind: DebugInfo, symbol: "wasmoon_jit_dwarf", sources: ["dwarf.c"] },
  ]
}

///|
pub fn native_glue_covers_source(
  glue : Array[NativeGlueBinding],
  source : String,
) -> Bool {
  for binding in glue {
    for owned in binding.sources {
      if owned == source {
        return true
      }
    }
  }
  false
}

///|
pub fn native_glue_covers_jit_ffi_stubs(
  glue? : Array[NativeGlueBinding] = default_native_glue(),
) -> Bool {
  for source in jit_ffi_native_stub_sources() {
    if !native_glue_covers_source(glue, source) {
      return false
    }
  }
  true
}

///|
pub fn plan_milkir_integration_for_target(
  func : @milkir.Function,
  target : NativeTarget,
) -> JitIntegrationPlan raise JitPipelineError {
  if target is AArch64 {
    let semantic = @milkir_machv.lower_core_function_with_protocol(
      func,
      Platform,
    ) catch {
      error =>
        raise PipelineFailure(message="\{func.name}: \{error.to_string()}")
    }
    let compiled = build_aarch64_target(semantic)
    return {
      entry_symbol: func.name,
      target,
      native_glue: default_native_glue(),
      object: jit_code_object_from_aarch64(compiled.object, compiled.frame_size),
    }
  }
  let semantic = @milkir_machv.lower_core_function_with_protocol(func, Platform) catch {
    error => raise PipelineFailure(message="\{func.name}: \{error.to_string()}")
  }
  let compiled = build_x64_target(semantic)
  return {
    entry_symbol: func.name,
    target,
    native_glue: default_native_glue(),
    object: jit_code_object_from_x64(compiled.object, compiled.frame_size),
  }
}

///|
pub fn plan_wasm_body_milkir_integration_for_target(
  func : @milkir.Function,
  validation_context : @wasm_milkir.WasmValidationContext,
  target : NativeTarget,
) -> JitIntegrationPlan raise JitPipelineError {
  if target is AArch64 {
    let compiled = compile_wasm_body_aarch64_target(
      func,
      validation_context,
      true,
      [],
    )
    return {
      entry_symbol: func.name,
      target,
      native_glue: default_native_glue(),
      object: jit_code_object_from_aarch64(compiled.object, compiled.frame_size),
    }
  }
  let compiled = compile_wasm_body_x64_target(func, validation_context, true, [])
  {
    entry_symbol: func.name,
    target,
    native_glue: default_native_glue(),
    object: jit_code_object_from_x64(compiled.object, compiled.frame_size),
  }
}
