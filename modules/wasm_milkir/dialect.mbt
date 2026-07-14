///|
const WASM_DIALECT : String = "wasm"

///|
fn imm(values : Array[Int]) -> FixedArray[Int] {
  FixedArray::makei(values.length(), fn(i) { values[i] })
}

///|
fn bool_imm(value : Bool) -> Int {
  if value {
    1
  } else {
    0
  }
}

///|
fn imm_bool(value : Int) -> Bool {
  value != 0
}

///|
fn descriptor_for_spec(spec : WasmOpcodeSpec) -> @milkir.ExtOpDescriptor {
  ExtOpDescriptor(WASM_DIALECT, spec.wire_name, spec.immediate_kinds.length())
}

///|
pub fn descriptor(opcode : WasmOpcode) -> @milkir.ExtOpDescriptor {
  let (id, _) = opcode_payload(opcode)
  descriptor_for_spec(wasm_opcode_spec(id))
}

///|
pub fn descriptor_by_name(name : String) -> @milkir.ExtOpDescriptor? {
  wasm_opcode_spec_by_wire_name(name).map(descriptor_for_spec)
}

///|
pub fn encode(opcode : WasmOpcode) -> @milkir.ExtOp {
  let (id, immediates) = opcode_payload(opcode)
  let spec = wasm_opcode_spec(id)
  if validate_wasm_opcode_immediates(spec, immediates) is Some(message) {
    abort("invalid \{spec.typed_constructor} encoding: \{message}")
  }
  ExtOp(WASM_DIALECT, spec.wire_name, immediates)
}

///|
fn decode_result(ext : @milkir.ExtOp) -> Result[WasmOpcode, String] {
  if ext.dialect != WASM_DIALECT {
    return Err(
      "expected Wasm MilkIR dialect '\{WASM_DIALECT}', got '\{ext.dialect}'",
    )
  }
  let spec = match wasm_opcode_spec_by_wire_name(ext.opcode) {
    Some(spec) => spec
    None => return Err("unknown Wasm MilkIR extension opcode '\{ext.opcode}'")
  }
  match validate_wasm_opcode_immediates(spec, ext.immediates) {
    Some(message) => Err(message)
    None =>
      match opcode_from_payload(spec.id, ext.immediates) {
        Some(opcode) => Ok(opcode)
        None => Err("unsupported Wasm MilkIR extension opcode '\{ext.opcode}'")
      }
  }
}

///|
pub fn decode(ext : @milkir.ExtOp) -> WasmOpcode? {
  match decode_result(ext) {
    Ok(opcode) => Some(opcode)
    Err(_) => None
  }
}

///|
pub fn decode_error(ext : @milkir.ExtOp) -> String? {
  match decode_result(ext) {
    Ok(_) => None
    Err(message) => Some(message)
  }
}

///|
/// Verify core MilkIR invariants and every extension against the Wasm schema.
pub fn verify_function(
  func : @milkir.Function,
) -> Unit raise @milkir.VerifyError {
  func.verify_with_extension_validator(decode_error)
}

///|
fn register_wasm_validator(builder : @milkir.FunctionBuilder) -> Unit {
  builder
  .get_function()
  .register_extension_validator(WASM_DIALECT, decode_error)
}

///|
pub fn decode_opcode(opcode : @milkir.Opcode) -> WasmOpcode? {
  match opcode {
    Ext(ext, _) => decode(ext)
    _ => None
  }
}
