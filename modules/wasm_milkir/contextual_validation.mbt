///|
/// The lowered MilkIR carrier contract for a WebAssembly function type.
pub(all) struct WasmFunctionContract {
  params : Array[@milkir.Type]
  results : Array[@milkir.Type]
} derive(Eq, Debug)

///|
/// The lowered MilkIR carrier and packed representation of a WebAssembly field.
pub(all) enum WasmStorageContract {
  Value(@milkir.Type)
  Packed8
  Packed16
} derive(Eq, Debug)

///|
/// The contextual contract for one WebAssembly struct field or array element.
pub(all) struct WasmFieldContract {
  storage : WasmStorageContract
  mutable_ : Bool
  defaultable : Bool
} derive(Eq, Debug)

///|
/// The contextual contract for a WebAssembly indexed type.
pub(all) enum WasmDefinedTypeContract {
  Function(WasmFunctionContract)
  Struct(Array[WasmFieldContract])
  Array(WasmFieldContract)
} derive(Eq, Debug)

///|
/// The contextual contract for a WebAssembly table.
pub(all) struct WasmTableContract {
  index_type : @milkir.Type
  element_type : @milkir.Type
} derive(Eq, Debug)

///|
/// Module and linker metadata required to validate Wasm extension operations.
///
/// The context is supplied explicitly at the Wasm adapter seam and is never
/// stored in MilkIR. Linked direct functions use their remapped global index;
/// indexed types, tables, tags, and segments use module-local indices.
struct WasmValidationContext {
  function_contract : (Int) -> WasmFunctionContract?
  defined_type_contract : (Int) -> WasmDefinedTypeContract?
  table_contract : (Int) -> WasmTableContract?
  tag_contract : (Int) -> WasmFunctionContract?
  memory_exists : (Int) -> Bool
  data_segment_exists : (Int) -> Bool
  element_segment_type : (Int) -> @milkir.Type?
}

///|
/// Resolver interface used to construct a contextual-validation adapter.
pub(all) struct WasmValidationResolvers {
  function_contract : (Int) -> WasmFunctionContract?
  defined_type_contract : (Int) -> WasmDefinedTypeContract?
  table_contract : (Int) -> WasmTableContract?
  tag_contract : (Int) -> WasmFunctionContract?
  memory_exists : (Int) -> Bool
  data_segment_exists : (Int) -> Bool
  element_segment_type : (Int) -> @milkir.Type?
}

///|
/// Construct an explicit contextual-validation adapter.
pub fn WasmValidationContext::new(
  resolvers : WasmValidationResolvers,
) -> WasmValidationContext {
  {
    function_contract: resolvers.function_contract,
    defined_type_contract: resolvers.defined_type_contract,
    table_contract: resolvers.table_contract,
    tag_contract: resolvers.tag_contract,
    memory_exists: resolvers.memory_exists,
    data_segment_exists: resolvers.data_segment_exists,
    element_segment_type: resolvers.element_segment_type,
  }
}

///|
/// Construct a context that rejects every module-indexed operation.
///
/// This is useful for lowering functions that contain only context-free Wasm
/// operations; it is not a fallback for module-produced MilkIR.
pub fn WasmValidationContext::empty() -> WasmValidationContext {
  WasmValidationContext::new({
    function_contract: fn(_) { None },
    defined_type_contract: fn(_) { None },
    table_contract: fn(_) { None },
    tag_contract: fn(_) { None },
    memory_exists: fn(_) { false },
    data_segment_exists: fn(_) { false },
    element_segment_type: fn(_) { None },
  })
}

///|
fn WasmStorageContract::carrier(self : WasmStorageContract) -> @milkir.Type {
  match self {
    Value(ty) => ty
    Packed8 | Packed16 => I32
  }
}

///|
fn WasmStorageContract::packed_width(self : WasmStorageContract) -> Int? {
  match self {
    Value(_) => None
    Packed8 => Some(1)
    Packed16 => Some(2)
  }
}

///|
fn WasmDefinedTypeContract::reference_carrier(
  self : WasmDefinedTypeContract,
) -> @milkir.Type {
  match self {
    Function(_) => CallableRef
    Struct(_) | Array(_) => Ref
  }
}

///|
fn contextual_error(opcode : String, message : String) -> String? {
  Some("malformed contextual Wasm MilkIR extension '\{opcode}': \{message}")
}

///|
fn types_equal(
  actual : ReadOnlyArray[@milkir.Type],
  offset : Int,
  expected : Array[@milkir.Type],
) -> Bool {
  if actual.length() - offset != expected.length() {
    return false
  }
  for i, ty in expected {
    if actual[offset + i] != ty {
      return false
    }
  }
  true
}

///|
fn type_arrays_equal(
  left : Array[@milkir.Type],
  right : Array[@milkir.Type],
) -> Bool {
  if left.length() != right.length() {
    return false
  }
  for i, ty in left {
    if right[i] != ty {
      return false
    }
  }
  true
}

///|
fn type_array_text(types : Array[@milkir.Type]) -> String {
  "[\{types.map(fn(ty) { ty.to_string() }).join(", ")}]"
}

///|
fn actual_type_suffix_text(
  types : ReadOnlyArray[@milkir.Type],
  offset : Int,
) -> String {
  let names : Array[String] = []
  for i in offset..<types.length() {
    names.push(types[i].to_string())
  }
  "[\{names.join(", ")}]"
}

///|
fn validate_signature(
  wire_name : String,
  view : @milkir.ExtensionInstView,
  operand_offset : Int,
  contract : WasmFunctionContract,
  expected_results : Array[@milkir.Type],
) -> String? {
  if !types_equal(view.operand_types, operand_offset, contract.params) {
    return contextual_error(
      wire_name,
      "expected call parameters \{type_array_text(contract.params)}, got \{actual_type_suffix_text(view.operand_types, operand_offset)}",
    )
  }
  if !types_equal(view.result_types, 0, expected_results) {
    return contextual_error(
      wire_name,
      "expected call results \{type_array_text(expected_results)}, got \{actual_type_suffix_text(view.result_types, 0)}",
    )
  }
  None
}

///|
fn validate_direct_call(
  wire_name : String,
  view : @milkir.ExtensionInstView,
  context : WasmValidationContext,
  function_index : Int,
  tail_results : Array[@milkir.Type]?,
) -> String? {
  let contract = match (context.function_contract)(function_index) {
    Some(contract) => contract
    None =>
      return contextual_error(
        wire_name,
        "unknown linked function index \{function_index}",
      )
  }
  let instruction_results = if tail_results is Some(_) {
    []
  } else {
    contract.results
  }
  if validate_signature(wire_name, view, 0, contract, instruction_results)
    is Some(message) {
    return Some(message)
  }
  if tail_results is Some(results) &&
    !type_arrays_equal(contract.results, results) {
    return contextual_error(
      wire_name,
      "target results \{type_array_text(contract.results)} do not match enclosing function results \{type_array_text(results)}",
    )
  }
  None
}

///|
fn function_type_contract(
  wire_name : String,
  context : WasmValidationContext,
  type_index : Int,
) -> Result[WasmFunctionContract, String] {
  match (context.defined_type_contract)(type_index) {
    Some(Function(contract)) => Ok(contract)
    Some(_) =>
      Err(
        "malformed contextual Wasm MilkIR extension '\{wire_name}': type index \{type_index} is not a function type",
      )
    None =>
      Err(
        "malformed contextual Wasm MilkIR extension '\{wire_name}': unknown type index \{type_index}",
      )
  }
}

///|
fn validate_indirect_call(
  wire_name : String,
  view : @milkir.ExtensionInstView,
  context : WasmValidationContext,
  type_index : Int,
  table_index : Int?,
  tail_results : Array[@milkir.Type]?,
) -> String? {
  let contract = match function_type_contract(wire_name, context, type_index) {
    Ok(contract) => contract
    Err(message) => return Some(message)
  }
  if table_index is Some(index) {
    let table = match (context.table_contract)(index) {
      Some(table) => table
      None => return contextual_error(wire_name, "unknown table index \{index}")
    }
    if table.element_type != CallableRef {
      return contextual_error(
        wire_name,
        "table index \{index} has non-callable element carrier \{table.element_type}",
      )
    }
    if view.operand_types[0] != table.index_type {
      return contextual_error(
        wire_name,
        "table index \{index} expects element index \{table.index_type}, got \{view.operand_types[0]}",
      )
    }
  }
  let instruction_results = if tail_results is Some(_) {
    []
  } else {
    contract.results
  }
  if validate_signature(wire_name, view, 1, contract, instruction_results)
    is Some(message) {
    return Some(message)
  }
  if tail_results is Some(results) &&
    !type_arrays_equal(contract.results, results) {
    return contextual_error(
      wire_name,
      "target results \{type_array_text(contract.results)} do not match enclosing function results \{type_array_text(results)}",
    )
  }
  None
}

///|
fn struct_fields(
  wire_name : String,
  context : WasmValidationContext,
  type_index : Int,
) -> Result[Array[WasmFieldContract], String] {
  match (context.defined_type_contract)(type_index) {
    Some(Struct(fields)) => Ok(fields)
    Some(_) =>
      Err(
        "malformed contextual Wasm MilkIR extension '\{wire_name}': type index \{type_index} is not a struct type",
      )
    None =>
      Err(
        "malformed contextual Wasm MilkIR extension '\{wire_name}': unknown type index \{type_index}",
      )
  }
}

///|
fn struct_field(
  wire_name : String,
  context : WasmValidationContext,
  type_index : Int,
  field_index : Int,
) -> Result[WasmFieldContract, String] {
  let fields = match struct_fields(wire_name, context, type_index) {
    Ok(fields) => fields
    Err(message) => return Err(message)
  }
  match fields.get(field_index) {
    Some(field) => Ok(field)
    None =>
      Err(
        "malformed contextual Wasm MilkIR extension '\{wire_name}': unknown field index \{field_index} for struct type \{type_index}",
      )
  }
}

///|
fn array_element(
  wire_name : String,
  context : WasmValidationContext,
  type_index : Int,
) -> Result[WasmFieldContract, String] {
  match (context.defined_type_contract)(type_index) {
    Some(Array(element)) => Ok(element)
    Some(_) =>
      Err(
        "malformed contextual Wasm MilkIR extension '\{wire_name}': type index \{type_index} is not an array type",
      )
    None =>
      Err(
        "malformed contextual Wasm MilkIR extension '\{wire_name}': unknown type index \{type_index}",
      )
  }
}

///|
fn validate_struct_new(
  wire_name : String,
  view : @milkir.ExtensionInstView,
  context : WasmValidationContext,
  type_index : Int,
  use_default : Bool,
) -> String? {
  let fields = match struct_fields(wire_name, context, type_index) {
    Ok(fields) => fields
    Err(message) => return Some(message)
  }
  if use_default {
    for field in fields {
      if !field.defaultable {
        return contextual_error(
          wire_name,
          "struct type \{type_index} contains a non-defaultable field",
        )
      }
    }
    return None
  }
  let expected = fields.map(fn(field) { field.storage.carrier() })
  if !types_equal(view.operand_types, 0, expected) {
    return contextual_error(
      wire_name,
      "expected fields \{type_array_text(expected)}, got \{actual_type_suffix_text(view.operand_types, 0)}",
    )
  }
  None
}

///|
fn validate_struct_get(
  wire_name : String,
  view : @milkir.ExtensionInstView,
  context : WasmValidationContext,
  type_index : Int,
  field_index : Int,
  packed_width : Int?,
) -> String? {
  let field = match struct_field(wire_name, context, type_index, field_index) {
    Ok(field) => field
    Err(message) => return Some(message)
  }
  if field.storage.packed_width() != packed_width {
    return contextual_error(
      wire_name,
      "field \{field_index} of struct type \{type_index} has packed width \{Repr(field.storage.packed_width())}, got \{Repr(packed_width)}",
    )
  }
  let expected = field.storage.carrier()
  if view.result_types[0] != expected {
    return contextual_error(
      wire_name,
      "field \{field_index} of struct type \{type_index} has carrier \{expected}, got \{view.result_types[0]}",
    )
  }
  None
}

///|
fn validate_struct_set(
  wire_name : String,
  view : @milkir.ExtensionInstView,
  context : WasmValidationContext,
  type_index : Int,
  field_index : Int,
) -> String? {
  let field = match struct_field(wire_name, context, type_index, field_index) {
    Ok(field) => field
    Err(message) => return Some(message)
  }
  if !field.mutable_ {
    return contextual_error(
      wire_name,
      "field \{field_index} of struct type \{type_index} is immutable",
    )
  }
  let expected = field.storage.carrier()
  if view.operand_types[1] != expected {
    return contextual_error(
      wire_name,
      "field \{field_index} of struct type \{type_index} has carrier \{expected}, got \{view.operand_types[1]}",
    )
  }
  None
}

///|
fn validate_array_new(
  wire_name : String,
  view : @milkir.ExtensionInstView,
  context : WasmValidationContext,
  type_index : Int,
  use_default : Bool,
  fixed_count : Int?,
) -> String? {
  let element = match array_element(wire_name, context, type_index) {
    Ok(element) => element
    Err(message) => return Some(message)
  }
  if use_default {
    if !element.defaultable {
      return contextual_error(
        wire_name,
        "array type \{type_index} has a non-defaultable element",
      )
    }
    return None
  }
  let value_count = fixed_count.unwrap_or(1)
  let value_offset = 0
  for i in 0..<value_count {
    if view.operand_types[value_offset + i] != element.storage.carrier() {
      return contextual_error(
        wire_name,
        "array type \{type_index} expects element carrier \{element.storage.carrier()}, got \{view.operand_types[value_offset + i]}",
      )
    }
  }
  None
}

///|
fn validate_array_get(
  wire_name : String,
  view : @milkir.ExtensionInstView,
  context : WasmValidationContext,
  type_index : Int,
  packed_width : Int?,
) -> String? {
  let element = match array_element(wire_name, context, type_index) {
    Ok(element) => element
    Err(message) => return Some(message)
  }
  if element.storage.packed_width() != packed_width {
    return contextual_error(
      wire_name,
      "array type \{type_index} has packed width \{Repr(element.storage.packed_width())}, got \{Repr(packed_width)}",
    )
  }
  let expected = element.storage.carrier()
  if view.result_types[0] != expected {
    return contextual_error(
      wire_name,
      "array type \{type_index} has element carrier \{expected}, got \{view.result_types[0]}",
    )
  }
  None
}

///|
fn validate_mutable_array_value(
  wire_name : String,
  view : @milkir.ExtensionInstView,
  context : WasmValidationContext,
  type_index : Int,
  value_index : Int,
) -> String? {
  let element = match array_element(wire_name, context, type_index) {
    Ok(element) => element
    Err(message) => return Some(message)
  }
  if !element.mutable_ {
    return contextual_error(wire_name, "array type \{type_index} is immutable")
  }
  let expected = element.storage.carrier()
  if view.operand_types[value_index] != expected {
    return contextual_error(
      wire_name,
      "array type \{type_index} has element carrier \{expected}, got \{view.operand_types[value_index]}",
    )
  }
  None
}

///|
fn validate_array_copy(
  wire_name : String,
  context : WasmValidationContext,
  destination_type : Int,
  source_type : Int,
) -> String? {
  let destination = match array_element(wire_name, context, destination_type) {
    Ok(element) => element
    Err(message) => return Some(message)
  }
  let source = match array_element(wire_name, context, source_type) {
    Ok(element) => element
    Err(message) => return Some(message)
  }
  if !destination.mutable_ {
    return contextual_error(
      wire_name,
      "destination array type \{destination_type} is immutable",
    )
  }
  if destination.storage != source.storage {
    return contextual_error(
      wire_name,
      "array element storage mismatch between destination type \{destination_type} and source type \{source_type}",
    )
  }
  None
}

///|
fn data_compatible(storage : WasmStorageContract) -> Bool {
  match storage {
    Packed8 | Packed16 | Value(I32 | I64 | F32 | F64 | V128) => true
    _ => false
  }
}

///|
fn validate_array_segment(
  wire_name : String,
  context : WasmValidationContext,
  type_index : Int,
  segment_index : Int,
  data_segment : Bool,
  require_mutable : Bool,
) -> String? {
  let element = match array_element(wire_name, context, type_index) {
    Ok(element) => element
    Err(message) => return Some(message)
  }
  if require_mutable && !element.mutable_ {
    return contextual_error(wire_name, "array type \{type_index} is immutable")
  }
  if data_segment {
    if !(context.data_segment_exists)(segment_index) {
      return contextual_error(
        wire_name,
        "unknown data segment index \{segment_index}",
      )
    }
    if !data_compatible(element.storage) {
      return contextual_error(
        wire_name,
        "array type \{type_index} is not compatible with a data segment",
      )
    }
  } else {
    let segment_type = match (context.element_segment_type)(segment_index) {
      Some(ty) => ty
      None =>
        return contextual_error(
          wire_name,
          "unknown element segment index \{segment_index}",
        )
    }
    if segment_type != element.storage.carrier() {
      return contextual_error(
        wire_name,
        "element segment \{segment_index} has carrier \{segment_type}, expected \{element.storage.carrier()}",
      )
    }
  }
  None
}

///|
fn validate_reference_type(
  wire_name : String,
  view : @milkir.ExtensionInstView,
  context : WasmValidationContext,
  type_index : Int,
  check_result : Bool,
) -> String? {
  let carrier : @milkir.Type = if type_index < 0 {
    match type_index {
      -1 | -2 | -3 | -4 | -5 | -8 => Ref
      -6 | -9 => CallableRef
      -7 | -10 => OpaqueRef
      _ =>
        return contextual_error(wire_name, "unknown heap type id \{type_index}")
    }
  } else {
    match (context.defined_type_contract)(type_index) {
      Some(contract) => contract.reference_carrier()
      None =>
        return contextual_error(wire_name, "unknown type index \{type_index}")
    }
  }
  if check_result && view.result_types[0] != carrier {
    return contextual_error(
      wire_name,
      "type index \{type_index} has reference carrier \{carrier}, got \{view.result_types[0]}",
    )
  }
  None
}

///|
fn validate_throw(
  wire_name : String,
  view : @milkir.ExtensionInstView,
  context : WasmValidationContext,
  tag_index : Int,
) -> String? {
  let contract = match (context.tag_contract)(tag_index) {
    Some(contract) => contract
    None => return contextual_error(wire_name, "unknown tag index \{tag_index}")
  }
  if contract.results.length() != 0 {
    return contextual_error(
      wire_name,
      "tag index \{tag_index} has a non-empty result contract",
    )
  }
  if !types_equal(view.operand_types, 0, contract.params) {
    return contextual_error(
      wire_name,
      "tag index \{tag_index} expects values \{type_array_text(contract.params)}, got \{actual_type_suffix_text(view.operand_types, 0)}",
    )
  }
  None
}

///|
/// Validate one Wasm extension against module and linker metadata.
pub fn WasmValidationContext::validate_extension(
  self : WasmValidationContext,
  view : @milkir.ExtensionInstView,
  enclosing_results : Array[@milkir.Type],
) -> String? {
  if validate_extension(view) is Some(message) {
    return Some(message)
  }
  let opcode = match decode(view.op) {
    Some(opcode) => opcode
    None => return Some("invalid Wasm extension after local validation")
  }
  match opcode {
    WasmCall(function_index) =>
      validate_direct_call("call", view, self, function_index, None)
    ReturnCall(function_index) =>
      validate_direct_call(
        "return_call",
        view,
        self,
        function_index,
        Some(enclosing_results),
      )
    WasmCallIndirect(type_index, table_index) =>
      validate_indirect_call(
        "call_indirect",
        view,
        self,
        type_index,
        Some(table_index),
        None,
      )
    ReturnCallIndirect(type_index, table_index) =>
      validate_indirect_call(
        "return_call_indirect",
        view,
        self,
        type_index,
        Some(table_index),
        Some(enclosing_results),
      )
    CallRef(type_index) =>
      validate_indirect_call("call_ref", view, self, type_index, None, None)
    ReturnCallRef(type_index) =>
      validate_indirect_call(
        "return_call_ref",
        view,
        self,
        type_index,
        None,
        Some(enclosing_results),
      )
    GetFuncRef(function_index) =>
      if (self.function_contract)(function_index) is Some(_) {
        None
      } else {
        contextual_error(
          "get_func_ref",
          "unknown linked function index \{function_index}",
        )
      }
    StructNew(type_index) =>
      validate_struct_new("struct_new", view, self, type_index, false)
    StructNewDefault(type_index) =>
      validate_struct_new("struct_new_default", view, self, type_index, true)
    StructGet(type_index, field_index) =>
      validate_struct_get(
        "struct_get",
        view,
        self,
        type_index,
        field_index,
        None,
      )
    StructGetS(type_index, field_index, width) =>
      validate_struct_get(
        "struct_get_s",
        view,
        self,
        type_index,
        field_index,
        Some(width),
      )
    StructGetU(type_index, field_index, width) =>
      validate_struct_get(
        "struct_get_u",
        view,
        self,
        type_index,
        field_index,
        Some(width),
      )
    StructSet(type_index, field_index) =>
      validate_struct_set("struct_set", view, self, type_index, field_index)
    ArrayNew(type_index) =>
      validate_array_new("array_new", view, self, type_index, false, None)
    ArrayNewDefault(type_index) =>
      validate_array_new(
        "array_new_default",
        view,
        self,
        type_index,
        true,
        None,
      )
    ArrayNewFixed(type_index, count) =>
      validate_array_new(
        "array_new_fixed",
        view,
        self,
        type_index,
        false,
        Some(count),
      )
    ArrayGet(type_index) =>
      validate_array_get("array_get", view, self, type_index, None)
    ArrayGetS(type_index, width) =>
      validate_array_get("array_get_s", view, self, type_index, Some(width))
    ArrayGetU(type_index, width) =>
      validate_array_get("array_get_u", view, self, type_index, Some(width))
    ArraySet(type_index) =>
      validate_mutable_array_value("array_set", view, self, type_index, 2)
    ArrayFill(type_index) =>
      validate_mutable_array_value("array_fill", view, self, type_index, 2)
    ArrayCopy(destination_type, source_type) =>
      validate_array_copy("array_copy", self, destination_type, source_type)
    ArrayNewData(type_index, data_index) =>
      validate_array_segment(
        "array_new_data", self, type_index, data_index, true, false,
      )
    ArrayNewElem(type_index, element_index) =>
      validate_array_segment(
        "array_new_elem", self, type_index, element_index, false, false,
      )
    ArrayInitData(type_index, data_index) =>
      validate_array_segment(
        "array_init_data", self, type_index, data_index, true, true,
      )
    ArrayInitElem(type_index, element_index) =>
      validate_array_segment(
        "array_init_elem", self, type_index, element_index, false, true,
      )
    RefTest(type_index, _) =>
      validate_reference_type("ref_test", view, self, type_index, false)
    RefCast(type_index, _) =>
      validate_reference_type("ref_cast", view, self, type_index, true)
    Throw(tag_index) => validate_throw("throw", view, self, tag_index)
    _ => None
  }
}

///|
pub fn WasmValidationContext::validate_global_value(
  self : WasmValidationContext,
  data : @milkir.GlobalValueData,
) -> String? {
  if validate_global_value(data) is Some(message) {
    return Some(message)
  }
  match data {
    ContextField(field, _, _) =>
      match decode_memory_base_context_field(field) {
        Some(memory_index) =>
          if (self.memory_exists)(memory_index) {
            None
          } else {
            contextual_error(
              "memory_base",
              "unknown memory index \{memory_index}",
            )
          }
        None => Some("invalid Wasm context field after local validation")
      }
  }
}

///|
/// Verify core MilkIR, local Wasm schema, and module-contextual contracts.
pub fn verify_function_with_context(
  func : @milkir.Function,
  context : WasmValidationContext,
) -> Unit raise @milkir.VerifyError {
  fn validate(view : @milkir.ExtensionInstView) -> String? {
    context.validate_extension(view, func.results)
  }
  fn validate_global(data : @milkir.GlobalValueData) -> String? {
    context.validate_global_value(data)
  }
  func.verify_with_dialect_validator(WASM_DIALECT, validate, validate_global)
}
