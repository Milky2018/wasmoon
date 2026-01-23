///|
fn append_bytes(dst : Array[Byte], src : Array[Byte]) -> Unit {
  for b in src {
    dst.push(b)
  }
}

///|
fn leb_u32(n : Int) -> Array[Byte] {
  let mut value = n
  let bytes : Array[Byte] = []
  while true {
    let mut byte = value & 0x7f
    value = value >> 7
    if value != 0 {
      byte = byte | 0x80
    }
    bytes.push(byte.to_byte())
    if value == 0 {
      break
    }
  }
  bytes
}

///|
fn build_component(sections : Array[(Int, Array[Byte])]) -> Bytes {
  let bytes : Array[Byte] = [
    b'\x00', b'\x61', b'\x73', b'\x6d', b'\x01', b'\x00', b'\x01', b'\x00',
  ]
  for entry in sections {
    let (id, payload) = entry
    bytes.push(id.to_byte())
    append_bytes(bytes, leb_u32(payload.length()))
    append_bytes(bytes, payload)
  }
  Bytes::from_array(bytes)
}

///|
fn encode_name(name_bytes : Array[Byte]) -> Array[Byte] {
  let out : Array[Byte] = [b'\x00']
  append_bytes(out, leb_u32(name_bytes.length()))
  append_bytes(out, name_bytes)
  out
}

///|
fn vec_payload(entries : Array[Array[Byte]]) -> Array[Byte] {
  let payload : Array[Byte] = []
  append_bytes(payload, leb_u32(entries.length()))
  for entry in entries {
    append_bytes(payload, entry)
  }
  payload
}

///|
fn import_entry_func(name_bytes : Array[Byte], type_idx : Int) -> Array[Byte] {
  let entry : Array[Byte] = []
  append_bytes(entry, encode_name(name_bytes))
  entry.push(b'\x01')
  append_bytes(entry, leb_u32(type_idx))
  entry
}

///|
fn export_entry_func(name_bytes : Array[Byte], func_idx : Int) -> Array[Byte] {
  let entry : Array[Byte] = []
  append_bytes(entry, encode_name(name_bytes))
  entry.push(b'\x01')
  append_bytes(entry, leb_u32(func_idx))
  entry.push(b'\x00')
  entry
}

///|
fn export_entry_core_func(
  name_bytes : Array[Byte],
  func_idx : Int,
) -> Array[Byte] {
  let entry : Array[Byte] = []
  append_bytes(entry, encode_name(name_bytes))
  entry.push(b'\x00')
  entry.push(b'\x00')
  append_bytes(entry, leb_u32(func_idx))
  entry.push(b'\x00')
  entry
}

///|
fn alias_core_export_func(
  core_inst_idx : Int,
  name_bytes : Array[Byte],
) -> Array[Byte] {
  let entry : Array[Byte] = []
  entry.push(b'\x00')
  entry.push(b'\x00')
  entry.push(b'\x01')
  append_bytes(entry, leb_u32(core_inst_idx))
  append_bytes(entry, leb_u32(name_bytes.length()))
  append_bytes(entry, name_bytes)
  entry
}

///|
fn core_instance_instantiate(module_idx : Int) -> Array[Byte] {
  let entry : Array[Byte] = []
  entry.push(b'\x00')
  append_bytes(entry, leb_u32(module_idx))
  entry.push(b'\x00')
  entry
}

///|
fn canon_lift_entry(core_func_idx : Int, type_idx : Int) -> Array[Byte] {
  let entry : Array[Byte] = []
  entry.push(b'\x00')
  entry.push(b'\x00')
  append_bytes(entry, leb_u32(core_func_idx))
  entry.push(b'\x00')
  append_bytes(entry, leb_u32(type_idx))
  entry
}

///|
fn canon_lower_entry(func_idx : Int) -> Array[Byte] {
  let entry : Array[Byte] = []
  entry.push(b'\x01')
  entry.push(b'\x00')
  append_bytes(entry, leb_u32(func_idx))
  entry.push(b'\x00')
  entry
}

///|
test "component runtime: host import export" {
  let type_payload : Array[Byte] = [0x01, 0x40, 0x01, 0x00, 0x7a, 0x00, 0x7a]
  let import_payload = vec_payload([import_entry_func([], 0)])
  let export_payload = vec_payload([export_entry_func([], 0)])
  let bytes = build_component([
    (7, type_payload),
    (10, import_payload),
    (11, export_payload),
  ])
  let component = @component.parse_component(bytes) catch {
    e => return fail("parse component failed: \{e}")
  }
  let linker = @component.ComponentLinker::new()
  let func_type : @component.FuncType = {
    is_async: false,
    params: [
      { label: "", ty: @component.ValType::Prim(@component.PrimValType::S32) },
    ],
    result: Some(@component.ValType::Prim(@component.PrimValType::S32)),
  }
  let host = fn(
    args : Array[@component.ComponentValue],
  ) -> Array[@component.ComponentValue] raise @component.ComponentRuntimeError {
    match args {
      [@component.ComponentValue::S32(n)] =>
        [@component.ComponentValue::S32(n + 1)]
      _ =>
        raise @component.ComponentRuntimeError::HostCallError("unexpected args")
    }
  }
  linker.add_func("", func_type, host)
  let instance = linker.instantiate("host_import", component)
  let results = instance.call_exported_func("", [
    @component.ComponentValue::S32(41),
  ])
  inspect(results, content="[S32(42)]")
}

///|
test "component runtime: canon lift core func" {
  let wat = "(module (func (export \"inc\") (param i32) (result i32) local.get 0 i32.const 1 i32.add))"
  let mod_ = @wat.parse(wat) catch {
    e => return fail("parse wat failed: \{e}")
  }
  let wasm_bytes : Array[Byte] = @cwasm.encode(mod_).map(v => v.to_byte())
  let core_instance_payload = vec_payload([core_instance_instantiate(0)])
  let name_inc : Array[Byte] = [b'i', b'n', b'c']
  let alias_payload = vec_payload([alias_core_export_func(0, name_inc)])
  let type_payload : Array[Byte] = [0x01, 0x40, 0x01, 0x00, 0x7a, 0x00, 0x7a]
  let canon_payload = vec_payload([canon_lift_entry(0, 0)])
  let export_payload = vec_payload([export_entry_func(name_inc, 0)])
  let bytes = build_component([
    (1, wasm_bytes),
    (2, core_instance_payload),
    (6, alias_payload),
    (7, type_payload),
    (8, canon_payload),
    (11, export_payload),
  ])
  let component = @component.parse_component(bytes) catch {
    e => return fail("parse component failed: \{e}")
  }
  let linker = @component.ComponentLinker::new()
  let instance = linker.instantiate("canon_lift", component)
  let results = instance.call_exported_func("inc", [
    @component.ComponentValue::S32(41),
  ])
  inspect(results, content="[S32(42)]")
}

///|
test "component runtime: canon lower to core func" {
  let name_inc : Array[Byte] = [b'i', b'n', b'c']
  let name_core : Array[Byte] = [b'c', b'o', b'r', b'e']
  let type_payload : Array[Byte] = [0x01, 0x40, 0x01, 0x00, 0x7a, 0x00, 0x7a]
  let import_payload = vec_payload([import_entry_func(name_inc, 0)])
  let canon_payload = vec_payload([canon_lower_entry(0)])
  let export_payload = vec_payload([export_entry_core_func(name_core, 0)])
  let bytes = build_component([
    (7, type_payload),
    (10, import_payload),
    (8, canon_payload),
    (11, export_payload),
  ])
  let component = @component.parse_component(bytes) catch {
    e => return fail("parse component failed: \{e}")
  }
  let linker = @component.ComponentLinker::new()
  let func_type : @component.FuncType = {
    is_async: false,
    params: [
      { label: "", ty: @component.ValType::Prim(@component.PrimValType::S32) },
    ],
    result: Some(@component.ValType::Prim(@component.PrimValType::S32)),
  }
  let host = fn(
    args : Array[@component.ComponentValue],
  ) -> Array[@component.ComponentValue] raise @component.ComponentRuntimeError {
    match args {
      [@component.ComponentValue::S32(n)] =>
        [@component.ComponentValue::S32(n + 1)]
      _ =>
        raise @component.ComponentRuntimeError::HostCallError("unexpected args")
    }
  }
  linker.add_func("inc", func_type, host)
  let instance = linker.instantiate("canon_lower", component)
  let exported = instance.get_export("core")
  let core_func = match exported {
    Some(@component.ComponentExtern::CoreFunc(f)) => f
    _ => return fail("missing core func export")
  }
  let store = linker.get_store()
  let results = @executor.call_func_by_index(
    store,
    core_func.instance,
    core_func.func_idx,
    [@types.Value::I32(41)],
  ) catch {
    e => return fail("call core func failed: \{e}")
  }
  inspect(results, content="[I32(42)]")
}
