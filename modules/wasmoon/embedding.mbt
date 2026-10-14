///|
pub fn wasm_frontend_embedding_environment(
  runtime_symbol_prefix~ : String = "wasmoon",
  hidden_context_type~ : @milkir.Type? = Some(Ptr),
  cancellation_safepoints~ : Bool = false,
  context_shape~ : @wasmoon_jit.ContextShape = Legacy,
) -> @wasm_frontend.EmbeddingEnvironment {
  let vm = @wasmoon_jit.shaped_vmcontext_layout(context_shape)
  let memory = @wasmoon_jit.memory_descriptor_layout()
  EmbeddingEnvironment(
    runtime_symbol_prefix~,
    hidden_context_type~,
    runtime_layout=Some({
      memory0_base_offset: vm.memory0_base_offset,
      memory0_size_offset: vm.memory0_size_offset,
      func_table_offset: vm.func_table_offset,
      table0_base_offset: vm.table0_base_offset,
      table0_elements_offset: vm.table0_elements_offset,
      globals_offset: vm.globals_offset,
      tables_offset: vm.tables_offset,
      table_sizes_offset: vm.table_sizes_offset,
      memories_offset: vm.memories_offset,
      pointer_stride: vm.pointer_stride,
      global_value_stride: vm.global_value_stride,
      table_entry_value_offset: vm.table_entry_value_offset,
      table_entry_stride: vm.table_entry_stride,
      func_table_entry_stride: vm.func_table_entry_stride,
    }),
    memory_descriptor_layout=Some({
      base_offset: memory.base_offset,
      current_length_offset: memory.current_length_offset,
    }),
    cancellation_safepoints~,
  )
}
