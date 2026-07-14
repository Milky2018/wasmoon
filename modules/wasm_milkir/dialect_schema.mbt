///|
priv enum WasmImmediateKind {
  IntegerImmediate
  BooleanImmediate
}

///|
priv struct WasmOpcodeSpec {
  id : Int
  typed_constructor : String
  wire_name : String
  immediate_kinds : Array[WasmImmediateKind]
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
