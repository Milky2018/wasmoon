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
} derive(Debug)

///|
pub fn EmbeddingEnvironment::new(
  runtime_symbol_prefix? : String = "wasmoon",
  hidden_context_type? : @milkir.Type? = Some(Ptr),
  runtime_layout? : RuntimeLayout? = None,
  memory_descriptor_layout? : MemoryDescriptorLayout? = None,
) -> EmbeddingEnvironment {
  {
    runtime_symbol_prefix,
    hidden_context_type,
    runtime_layout,
    memory_descriptor_layout,
  }
}

///|
pub fn EmbeddingEnvironment::runtime_symbol(
  self : EmbeddingEnvironment,
  name : String,
) -> @milkir.ExternalSymbol {
  @milkir.ExternalSymbol::new(self.runtime_symbol_prefix + "." + name)
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

///|
pub suberror LowerError {
  FunctionIndexOutOfRange(index~ : Int)
  TypeIndexOutOfRange(index~ : Int)
  NonFunctionType(index~ : Int)
  MissingCode(index~ : Int)
  UnsupportedNativeLowering(index~ : Int, reason~ : String)
} derive(Debug, Eq)

///|
pub impl Show for LowerError with fn output(self, logger) {
  logger.write_string(to_repr(self).to_string())
}
