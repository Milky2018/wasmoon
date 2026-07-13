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
fn parse_immediate_kinds(
  wire_name : String,
  encoded : StringView,
) -> Array[WasmImmediateKind] {
  if encoded == "-" {
    return []
  }
  encoded
  .split(",")
  .map(kind => {
    match kind {
      "int" => IntegerImmediate
      "bool" => BooleanImmediate
      _ =>
        abort("invalid immediate kind '\{kind}' for Wasm opcode '\{wire_name}'")
    }
  })
  .to_array()
}

///|
fn parse_wasm_opcode_schema(encoded : String) -> Array[WasmOpcodeSpec] {
  let specs : Array[WasmOpcodeSpec] = []
  let typed_constructors : Map[String, Unit] = Map([])
  let wire_names : Map[String, Unit] = Map([])
  for raw_line in encoded.split("\n") {
    let line = raw_line.trim()
    if line.is_empty() || line.has_prefix("#") {
      continue
    }
    let fields = line.split("|").to_array()
    if fields.length() != 4 {
      abort("invalid Wasm opcode schema row '\{line}': expected 4 fields")
    }
    let expected_id = specs.length()
    if fields[0] != "\{expected_id}" {
      abort(
        "invalid Wasm opcode schema id '\{fields[0]}': expected \{expected_id}",
      )
    }
    let typed_constructor = fields[1].to_owned()
    if typed_constructor == "" {
      abort("Wasm opcode schema contains an empty typed constructor")
    }
    if typed_constructors.contains(typed_constructor) {
      abort("duplicate Wasm opcode typed constructor '\{typed_constructor}'")
    }
    typed_constructors[typed_constructor] = ()
    let wire_name = fields[2].to_owned()
    if wire_name == "" {
      abort("Wasm opcode schema contains an empty wire name")
    }
    if wire_names.contains(wire_name) {
      abort("duplicate Wasm opcode wire name '\{wire_name}'")
    }
    wire_names[wire_name] = ()
    specs.push({
      id: expected_id,
      typed_constructor,
      wire_name,
      immediate_kinds: parse_immediate_kinds(wire_name, fields[3]),
    })
  }
  specs
}

///|
let wasm_opcode_specs : Array[WasmOpcodeSpec] = parse_wasm_opcode_schema(
  @opcode_schema.wasm_opcodes_schema,
)

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
    abort("Wasm opcode id \{id} is absent from the embedded schema")
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
