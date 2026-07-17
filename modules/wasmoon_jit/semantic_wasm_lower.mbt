///|
priv struct WasmoonSemanticEnvironment {
  wasm : @wasm_machv.Environment
  field_paths : Map[String, Array[Int]]
  code_symbols : Map[String, @instr.CodeSymbol]
  runtime_symbols : @wasm_milkir.RuntimeSymbols
}

///|
fn semantic_runtime_symbol(
  symbols : @wasm_milkir.RuntimeSymbols,
  capability : String,
) -> String {
  match capability {
    "memory.grow" => symbols.memory_grow
    "memory.size" => symbols.memory_size
    "memory.fill" => symbols.memory_fill
    "memory.copy" => symbols.memory_copy
    "memory.init" => symbols.memory_init
    "data.drop" => symbols.data_drop
    "table.grow" => symbols.table_grow
    "table.fill" => symbols.table_fill
    "table.copy" => symbols.table_copy
    "table.init" => symbols.table_init
    "elem.drop" => symbols.elem_drop
    "gc.ref_test" => symbols.gc_ref_test
    "gc.ref_cast" => symbols.gc_ref_cast
    "gc.struct_get" => symbols.gc_struct_get
    "gc.struct_set" => symbols.gc_struct_set
    "gc.array_get" => symbols.gc_array_get
    "gc.array_set" => symbols.gc_array_set
    "gc.array_len" => symbols.gc_array_len
    "gc.array_fill" => symbols.gc_array_fill
    "gc.array_copy" => symbols.gc_array_copy
    "gc.array_new_data" => symbols.gc_array_new_data
    "gc.array_new_elem" => symbols.gc_array_new_elem
    "gc.array_init_data" => symbols.gc_array_init_data
    "gc.array_init_elem" => symbols.gc_array_init_elem
    "gc.type_check_subtype" => symbols.gc_type_check_subtype
    "gc.register_struct_inline" => symbols.gc_register_struct_inline
    "gc.register_array_inline" => symbols.gc_register_array_inline
    "gc.alloc_struct_slow" => symbols.gc_alloc_struct_slow
    "gc.alloc_array_from_values_slow" => symbols.gc_alloc_array_from_values_slow
    "gc.alloc_array_slow" => symbols.gc_alloc_array_slow
    "exception.try_begin" => symbols.exception_try_begin
    "exception.try_end" => symbols.exception_try_end
    "exception.throw" => symbols.exception_throw
    "exception.throw_tag" => symbols.exception_throw_tag
    "exception.throw_ref" => symbols.exception_throw_ref
    "exception.delegate" => symbols.exception_delegate
    "exception.get_tag" => symbols.exception_get_tag
    "exception.get_value" => symbols.exception_get_value
    "exception.get_value_count" => symbols.exception_get_value_count
    "exception.sigsetjmp" => symbols.exception_sigsetjmp
    "exception.spill_locals" => symbols.exception_spill_locals
    "exception.get_spilled_local" => symbols.exception_get_spilled_local
    _ => abort("missing Wasmoon runtime capability '\{capability}'")
  }
}

///|
fn wasmoon_semantic_environment(
  use_subtype_indirect_check : Bool,
  canonical_type_indices : Array[Int],
) -> WasmoonSemanticEnvironment {
  let layout = vmcontext_layout()
  let field_paths : Map[String, Array[Int]] = Map([])
  let code_symbols : Map[String, @instr.CodeSymbol] = Map([])
  let runtime_symbols = wasm_runtime_symbols()
  let function_table_field = @semantic_machv.EnvironmentField::new(
    "wasmoon.vmctx.function_table",
    Ptr64,
  )
  field_paths.set(function_table_field.name, [layout.func_table_offset])
  let canonical_type_indices = canonical_type_indices.copy()
  let wasm = @wasm_machv.Environment::new(
    fn(index) {
      let name = "wasm.func.\{index}"
      code_symbols.set(name, CodeSymbol("wasm.func", index))
      @semantic_machv.CodeSymbol::new(name)
    },
    fn(index) {
      let field = @semantic_machv.EnvironmentField::new(
        "wasmoon.vmctx.memory.\{index}.base",
        Ptr64,
      )
      let path = if index == 0 {
        [layout.memory0_base_offset]
      } else {
        [layout.memories_offset, index * layout.pointer_stride, 0]
      }
      field_paths.set(field.name, path)
      field
    },
    function_table_field,
    fn(index) {
      let field = @semantic_machv.EnvironmentField::new(
        "wasmoon.vmctx.table.\{index}.base",
        Ptr64,
      )
      let path = if index == 0 {
        [layout.table0_base_offset]
      } else {
        [layout.tables_offset, index * layout.pointer_stride]
      }
      field_paths.set(field.name, path)
      field
    },
    fn(raw_type_index) {
      if use_subtype_indirect_check {
        return raw_type_index
      }
      if raw_type_index >= 0 && raw_type_index < canonical_type_indices.length() {
        canonical_type_indices[raw_type_index]
      } else {
        raw_type_index
      }
    },
    fn(capability) {
      @semantic_machv.ExternalSymbol::new(
        semantic_runtime_symbol(runtime_symbols, capability),
      )
    },
  )
  { wasm, field_paths, code_symbols, runtime_symbols }
}

///|
fn semantic_trap_payload(reason : @semantic_machv.TrapReason) -> Int {
  match reason {
    Unreachable => 0
    MemoryOutOfBounds | TableOutOfBounds => 1
    IndirectCallTypeMismatch => 2
    InvalidConversionToInteger => 3
    IntegerDivisionByZero => 4
    IntegerOverflow => 5
    User(payload) => payload
    NullReference | UnalignedAtomic | UnsupportedOperation | StackOverflow => 6
  }
}

///|
fn has_wasm_extension(function : @milkir.Function) -> Bool {
  for block in function.blocks {
    for instruction in block.instructions {
      if instruction.opcode is Ext(_, _) {
        return true
      }
    }
  }
  false
}

///|
fn wasmoon_allocation_symbols(
  environment : WasmoonSemanticEnvironment,
) -> Array[@semantic_machv.ExternalSymbol] {
  [
    @semantic_machv.ExternalSymbol::new(
      environment.runtime_symbols.gc_alloc_struct_slow,
    ),
    @semantic_machv.ExternalSymbol::new(
      environment.runtime_symbols.gc_alloc_array_from_values_slow,
    ),
    @semantic_machv.ExternalSymbol::new(
      environment.runtime_symbols.gc_alloc_array_slow,
    ),
  ]
}

///|
fn build_wasmoon_aarch64_code_object(
  semantic : @semantic_machv.Function,
  environment : WasmoonSemanticEnvironment,
) -> @code_object.UnlinkedCodeObject raise JitPipelineError {
  build_aarch64_shadow(
    semantic,
    environment_field_path=fn(field : @semantic_machv.EnvironmentField) {
      environment.field_paths.get(field.name)
    },
    allocation_symbols=wasmoon_allocation_symbols(environment),
    root_scope_symbols=(
      @semantic_machv.ExternalSymbol::new(gc_push_root_scope_symbol()),
      @semantic_machv.ExternalSymbol::new(gc_pop_root_scope_symbol()),
    ),
  )
}

///|
pub fn plan_wasm_body_aarch64_code_object(
  function : @milkir.Function,
  use_subtype_indirect_check? : Bool = true,
  canonical_type_indices? : Array[Int] = [],
) -> @code_object.UnlinkedCodeObject raise JitPipelineError {
  let environment = wasmoon_semantic_environment(
    use_subtype_indirect_check, canonical_type_indices,
  )
  let semantic = @wasm_machv.lower_function(function, environment.wasm) catch {
    error =>
      raise PipelineFailure(message="\{function.name}: \{error.to_string()}")
  }
  build_wasmoon_aarch64_code_object(semantic, environment)
}

///|
fn lower_semantic_wasm_with_isa(
  function : @milkir.Function,
  isa : @isa.ISA,
  embedding_abi : @abi.EmbeddingABI,
  use_subtype_indirect_check : Bool,
  canonical_type_indices : Array[Int],
) -> @machv.Function raise JitPipelineError {
  if function.params.is_empty() && !has_wasm_extension(function) {
    return lower_semantic_core_with_isa(function, isa, embedding_abi)
  }
  let environment = wasmoon_semantic_environment(
    use_subtype_indirect_check, canonical_type_indices,
  )
  let semantic = @wasm_machv.lower_function(function, environment.wasm) catch {
    error =>
      raise PipelineFailure(message="\{function.name}: \{error.to_string()}")
  }
  match isa {
    AArch64 if aarch64_shadow_enabled() =>
      build_wasmoon_aarch64_code_object(semantic, environment) |> ignore
    _ => ()
  }
  let legacy = adapt_semantic_to_legacy(
    semantic,
    isa,
    embedding_abi=Some(embedding_abi),
    trap_payload=semantic_trap_payload,
    requires_hidden_safepoint_id=Some(fn(symbol) {
      symbol.name == environment.runtime_symbols.gc_alloc_struct_slow ||
      symbol.name == environment.runtime_symbols.gc_alloc_array_from_values_slow ||
      symbol.name == environment.runtime_symbols.gc_alloc_array_slow
    }),
    caller_root_scope_symbols=Some(
      (
        @semantic_machv.ExternalSymbol::new(gc_push_root_scope_symbol()),
        @semantic_machv.ExternalSymbol::new(gc_pop_root_scope_symbol()),
      ),
    ),
    environment_field_path=Some(fn(field) {
      environment.field_paths.get(field.name)
    }),
    code_symbol_resolver=Some(fn(symbol) {
      match environment.code_symbols.get(symbol.name) {
        Some(resolved) => resolved
        None => abort("unresolved Wasmoon code symbol '\{symbol.name}'")
      }
    }),
  ) catch {
    error =>
      raise PipelineFailure(message="\{function.name}: \{error.to_string()}")
  }
  legacy
}

///|
fn lower_semantic_core_with_isa(
  function : @milkir.Function,
  isa : @isa.ISA,
  embedding_abi : @abi.EmbeddingABI,
) -> @machv.Function raise JitPipelineError {
  let semantic = @milkir_machv.lower_core_function(function) catch {
    error =>
      raise PipelineFailure(message="\{function.name}: \{error.to_string()}")
  }
  adapt_semantic_to_legacy(
    semantic,
    isa,
    embedding_abi=Some(embedding_abi),
    trap_payload=semantic_trap_payload,
  ) catch {
    error =>
      raise PipelineFailure(message="\{function.name}: \{error.to_string()}")
  }
}
