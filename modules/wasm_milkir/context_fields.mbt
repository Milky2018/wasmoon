///|
const MEMORY_BASE_CONTEXT_FIELD : Int = 0

///|
pub fn memory_base_context_field(memory_index : Int) -> @milkir.ContextField {
  @milkir.ContextField::new(
    WASM_DIALECT,
    MEMORY_BASE_CONTEXT_FIELD,
    [memory_index],
    Ptr,
  )
}

///|
pub fn decode_memory_base_context_field(field : @milkir.ContextField) -> Int? {
  if field.dialect != WASM_DIALECT ||
    field.key != MEMORY_BASE_CONTEXT_FIELD ||
    field.parameters.length() != 1 ||
    field.parameters[0] < 0 ||
    field.ty != Ptr {
    return None
  }
  Some(field.parameters[0])
}

///|
pub fn validate_global_value(data : @milkir.GlobalValueData) -> String? {
  match data {
    ContextField(field, _, region) =>
      match decode_memory_base_context_field(field) {
        Some(memory_index) =>
          if region == Heap(memory_index) {
            None
          } else {
            Some(
              "malformed Wasm memory-base global: memory \{memory_index} must produce heap[\{memory_index}] provenance",
            )
          }
        None =>
          Some(
            "unknown or malformed Wasm context field \{field.dialect}:\{field.key}",
          )
      }
  }
}
