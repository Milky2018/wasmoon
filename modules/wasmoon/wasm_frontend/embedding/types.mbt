///|
pub(all) struct RuntimeLayout {
  memory0_base_offset : Int
  memory0_size_offset : Int
  func_table_offset : Int
  table0_base_offset : Int
  table0_elements_offset : Int
  globals_offset : Int
  tables_offset : Int
  table_sizes_offset : Int
  memories_offset : Int
  pointer_stride : Int
  global_value_stride : Int
  table_entry_value_offset : Int
  table_entry_stride : Int
  func_table_entry_stride : Int
} derive(Debug, Eq)

///|
pub(all) struct MemoryDescriptorLayout {
  base_offset : Int
  current_length_offset : Int
} derive(Debug, Eq)

///|
pub(all) struct EmbeddingEnvironment {
  runtime_symbol_prefix : String
  hidden_context_type : @milkir.Type?
  runtime_layout : RuntimeLayout?
  memory_descriptor_layout : MemoryDescriptorLayout?
  wasm_runtime_symbols : @wasm_milkir.RuntimeSymbols
  cancellation_safepoints : Bool
} derive(Debug)

///|
pub fn EmbeddingEnvironment::EmbeddingEnvironment(
  runtime_symbol_prefix? : String = "wasmoon",
  hidden_context_type? : @milkir.Type? = Some(Ptr),
  runtime_layout? : RuntimeLayout? = None,
  memory_descriptor_layout? : MemoryDescriptorLayout? = None,
  wasm_runtime_symbols? : @wasm_milkir.RuntimeSymbols? = None,
  cancellation_safepoints? : Bool = false,
) -> EmbeddingEnvironment {
  let wasm_runtime_symbols = wasm_runtime_symbols.unwrap_or(
    @wasm_milkir.RuntimeSymbols::with_runtime_prefix(
      runtime_symbol_prefix + ".runtime",
    ),
  )
  {
    runtime_symbol_prefix,
    hidden_context_type,
    runtime_layout,
    memory_descriptor_layout,
    wasm_runtime_symbols,
    cancellation_safepoints,
  }
}

///|
pub fn EmbeddingEnvironment::cancellation_safepoints(
  self : EmbeddingEnvironment,
) -> Bool {
  self.cancellation_safepoints
}

///|
pub fn EmbeddingEnvironment::runtime_symbol(
  self : EmbeddingEnvironment,
  name : String,
) -> @milkir.ExternalSymbol {
  ExternalSymbol(self.runtime_symbol_prefix + "." + name)
}

///|
pub fn EmbeddingEnvironment::wasm_runtime_symbols(
  self : EmbeddingEnvironment,
) -> @wasm_milkir.RuntimeSymbols {
  self.wasm_runtime_symbols
}

///|
pub fn EmbeddingEnvironment::hidden_context_param(
  self : EmbeddingEnvironment,
) -> @milkir.Type? {
  self.hidden_context_type
}

///|
pub fn EmbeddingEnvironment::runtime_layout(
  self : EmbeddingEnvironment,
) -> RuntimeLayout? {
  self.runtime_layout
}

///|
pub fn EmbeddingEnvironment::memory_descriptor_layout(
  self : EmbeddingEnvironment,
) -> MemoryDescriptorLayout? {
  self.memory_descriptor_layout
}
