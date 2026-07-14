///|
priv enum WasmImmediateKind {
  IntegerImmediate
  BooleanImmediate
}

///|
priv enum WasmTypePattern {
  ExactType(@milkir.Type)
  ReferenceLike
  PointerLike
  ContextualType
}

///|
priv struct WasmOpcodeSpec {
  id : Int
  typed_constructor : String
  wire_name : String
  immediate_kinds : Array[WasmImmediateKind]
  operand_types : Array[WasmTypePattern]
  result_types : Array[WasmTypePattern]
  variadic_operands : Bool
  variadic_results : Bool
}

///|
let wasm_opcode_ids_by_wire_name : Map[String, Int] = {
  let ids : Map[String, Int] = Map([])
  for spec in wasm_opcode_specs {
    ids[spec.wire_name] = spec.id
  }
  ids
}

///|
fn wasm_opcode_spec(id : Int) -> WasmOpcodeSpec {
  if id < 0 || id >= wasm_opcode_specs.length() {
    abort("Wasm opcode id \{id} is absent from the generated opcode table")
  }
  wasm_opcode_specs[id]
}

///|
fn wasm_opcode_spec_by_wire_name(name : String) -> WasmOpcodeSpec? {
  match wasm_opcode_ids_by_wire_name.get(name) {
    Some(id) => Some(wasm_opcode_specs[id])
    None => None
  }
}

///|
fn validate_wasm_opcode_immediates(
  spec : WasmOpcodeSpec,
  immediates : FixedArray[Int],
) -> String? {
  if immediates.length() != spec.immediate_kinds.length() {
    return Some(
      "malformed Wasm MilkIR extension '\{spec.wire_name}': expected \{spec.immediate_kinds.length()} immediates, got \{immediates.length()}",
    )
  }
  for i, kind in spec.immediate_kinds {
    match kind {
      IntegerImmediate => ()
      BooleanImmediate => {
        let value = immediates[i]
        if value != 0 && value != 1 {
          return Some(
            "malformed Wasm MilkIR extension '\{spec.wire_name}': immediate \{i} is a bool flag encoded as 0 or 1, got \{value}",
          )
        }
      }
    }
  }
  None
}

///|
fn type_pattern_matches(pattern : WasmTypePattern, ty : @milkir.Type) -> Bool {
  match pattern {
    ExactType(expected) => ty == expected
    ReferenceLike =>
      match ty {
        Ref | CallableRef | OpaqueRef => true
        _ => false
      }
    PointerLike => ty == Ptr || ty == I64
    ContextualType => true
  }
}

///|
fn type_pattern_name(pattern : WasmTypePattern) -> String {
  match pattern {
    ExactType(ty) => ty.to_string()
    ReferenceLike => "ref_like"
    PointerLike => "pointer"
    ContextualType => "contextual"
  }
}

///|
fn expected_type_list(
  patterns : Array[WasmTypePattern],
  variadic : Bool,
) -> String {
  let names = patterns.map(type_pattern_name)
  if variadic {
    names.push("...")
  }
  "[\{names.join(", ")}]"
}

///|
fn actual_type_list(types : ReadOnlyArray[@milkir.Type]) -> String {
  "[\{types.map(ty => ty.to_string()).join(", ")}]"
}

///|
fn validate_type_list(
  wire_name : String,
  label : String,
  actual : ReadOnlyArray[@milkir.Type],
  expected : Array[WasmTypePattern],
  variadic : Bool,
) -> String? {
  if actual.length() < expected.length() ||
    (!variadic && actual.length() != expected.length()) {
    return Some(
      "malformed Wasm MilkIR extension '\{wire_name}': expected \{label} \{expected_type_list(expected, variadic)}, got \{actual_type_list(actual)}",
    )
  }
  for i, pattern in expected {
    if !type_pattern_matches(pattern, actual[i]) {
      return Some(
        "malformed Wasm MilkIR extension '\{wire_name}': expected \{label} \{expected_type_list(expected, variadic)}, got \{actual_type_list(actual)}",
      )
    }
  }
  None
}

///|
fn validate_wasm_instruction_shape(
  spec : WasmOpcodeSpec,
  view : @milkir.ExtensionInstView,
) -> String? {
  if validate_type_list(
      spec.wire_name,
      "operands",
      view.operand_types,
      spec.operand_types,
      spec.variadic_operands,
    )
    is Some(message) {
    return Some(message)
  }
  validate_type_list(
    spec.wire_name,
    "results",
    view.result_types,
    spec.result_types,
    spec.variadic_results,
  )
}
