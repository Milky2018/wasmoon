///|
fn validation_function_contract(
  func_type : @types.FuncType,
) -> @wasm_milkir.WasmFunctionContract {
  {
    params: func_type.params[:].map(type_from_wasm),
    results: func_type.results[:].map(type_from_wasm),
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
    Cont(index) => Continuation(index)
    Struct(struct_type) =>
      Struct(struct_type.fields[:].map(validation_field_contract))
    Array(array_type) => Array(validation_field_contract(array_type.element))
  }
}

///|
fn indexed_function_contract(
  defined_types : Array[@wasm_milkir.WasmDefinedTypeContract],
  index : Int32,
) -> @wasm_milkir.WasmFunctionContract? {
  match defined_types.get(index) {
    Some(Function(contract)) => Some(contract)
    _ => None
  }
}

///|
fn TranslationContext::linked_function_contracts(
  self : TranslationContext,
  defined_types : Array[@wasm_milkir.WasmDefinedTypeContract],
) -> Map[Int32, @wasm_milkir.WasmFunctionContract] {
  let contracts : Map[Int32, @wasm_milkir.WasmFunctionContract] = Map([])
  for import_index, type_index in self.import_func_type_indices {
    let linked_index = if import_index < self.import_remap.length() {
      self.import_remap[import_index]
    } else {
      import_index
    }
    if indexed_function_contract(defined_types, type_index) is Some(contract) {
      contracts[linked_index] = contract
    }
  }
  for local_index, type_index in self.func_type_indices {
    let module_function_index = self.num_imports + local_index
    let linked_index = self.func_base + module_function_index
    if indexed_function_contract(defined_types, type_index) is Some(contract) {
      contracts[linked_index] = contract
    }
  }
  contracts
}

///|
/// Snapshot module and linker facts once. All function, type and tag queries
/// share these owned contracts for the lifetime of this compilation.
pub fn TranslationContext::wasm_validation_context(
  self : TranslationContext,
) -> @wasm_milkir.WasmValidationContext {
  let defined_types = self.module_types.map(validation_defined_type_contract)
  let function_contracts = self.linked_function_contracts(defined_types)
  let table_contracts : Array[@wasm_milkir.WasmTableContract] = self.tables.map(table => {
      index_type: if table.type_.is_table64 {
        I64
      } else {
        I32
      },
      element_type: type_from_wasm(table.type_.elem_type),
    },
  )
  let tag_contracts = self.tags.map(tag => {
    indexed_function_contract(defined_types, tag.type_idx)
  })
  let element_types = self.element_types.map(type_from_wasm)
  let memory_count = self.memory_count
  let data_count = self.data_count
  let final_types : Array[Int32] = []
  for index, subtype in self.module_types {
    if subtype.final_ {
      final_types.push(index)
    }
  }
  @wasm_milkir.WasmValidationContext::new(
    {
      function_contract: fn(index) { function_contracts.get(index) },
      defined_type_contract: fn(index) { defined_types.get(index) },
      table_contract: fn(index) { table_contracts.get(index) },
      tag_contract: fn(index) { tag_contracts.get(index).unwrap_or(None) },
      memory_exists: fn(index) { index >= 0 && index < memory_count },
      data_segment_exists: fn(index) { index >= 0 && index < data_count },
      element_segment_type: fn(index) { element_types.get(index) },
    },
    final_types~,
  )
}
