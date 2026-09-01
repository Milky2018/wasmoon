///|
fn validation_function_contract(
  func_type : @types.FuncType,
) -> @wasm_milkir.WasmFunctionContract {
  {
    params: func_type.params.map(type_from_wasm),
    results: func_type.results.map(type_from_wasm),
  }
}

///|
fn validation_value_defaultable(value_type : @types.ValueType) -> Bool {
  match value_type {
    I32 | I64 | F32 | F64 | V128 => true
    _ => value_type.is_nullable()
  }
}

///|
fn validation_field_contract(
  field : @types.FieldType,
) -> @wasm_milkir.WasmFieldContract {
  match field.storage_type {
    Val(value_type) =>
      {
        storage: Value(type_from_wasm(value_type)),
        mutable_: field.mutable,
        defaultable: validation_value_defaultable(value_type),
      }
    Packed(I8) =>
      { storage: Packed8, mutable_: field.mutable, defaultable: true, }
    Packed(I16) =>
      { storage: Packed16, mutable_: field.mutable, defaultable: true, }
  }
}

///|
fn validation_defined_type_contract(
  subtype : @types.SubType,
) -> @wasm_milkir.WasmDefinedTypeContract {
  match subtype.composite {
    Func(func_type) => Function(validation_function_contract(func_type))
    Struct(struct_type) =>
      Struct(struct_type.fields.map(validation_field_contract))
    Array(array_type) => Array(validation_field_contract(array_type.element))
  }
}

///|
fn TranslationContext::linked_function_contracts(
  self : TranslationContext,
) -> Map[Int, @wasm_milkir.WasmFunctionContract] {
  let contracts : Map[Int, @wasm_milkir.WasmFunctionContract] = Map([])
  for import_index, type_index in self.import_func_type_indices {
    let linked_index = if import_index < self.import_remap.length() {
      self.import_remap[import_index]
    } else {
      import_index
    }
    if self.module_types.get(type_index) is Some(subtype) &&
      subtype.composite is Func(func_type) {
      contracts[linked_index] = validation_function_contract(func_type)
    }
  }
  for local_index, type_index in self.func_type_indices {
    let module_function_index = self.num_imports + local_index
    let linked_index = self.func_base + module_function_index
    if self.module_types.get(type_index) is Some(subtype) &&
      subtype.composite is Func(func_type) {
      contracts[linked_index] = validation_function_contract(func_type)
    }
  }
  contracts
}

///|
/// Build the module/linker context required by contextual Wasm MilkIR checks.
pub fn TranslationContext::wasm_validation_context(
  self : TranslationContext,
) -> @wasm_milkir.WasmValidationContext {
  let function_contracts = self.linked_function_contracts()
  @wasm_milkir.WasmValidationContext::new({
    function_contract: fn(index) { function_contracts.get(index) },
    defined_type_contract: fn(index) {
      self.module_types.get(index).map(validation_defined_type_contract)
    },
    table_contract: fn(index) {
      self.tables
      .get(index)
      .map(fn(table) {
        {
          index_type: if table.type_.is_table64 {
            I64
          } else {
            I32
          },
          element_type: type_from_wasm(table.type_.elem_type),
        }
      })
    },
    tag_contract: fn(index) {
      guard self.tags.get(index) is Some(tag) else { None }
      guard self.module_types.get(tag.type_idx) is Some(subtype) else { None }
      match subtype.composite {
        Func(func_type) => Some(validation_function_contract(func_type))
        _ => None
      }
    },
    memory_exists: fn(index) { index >= 0 && index < self.memory_count },
    data_segment_exists: fn(index) { index >= 0 && index < self.data_count },
    element_segment_type: fn(index) {
      self.element_types.get(index).map(type_from_wasm)
    },
  })
}
