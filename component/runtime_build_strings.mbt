///|
priv struct BuildState {
  types : Array[TypeDef?]
  funcs : Array[ComponentFunc]
  values : Array[ComponentValue]
  components : Array[ComponentClosure]
  instances : Array[ComponentInstance]
  resource_table : ResourceTable
  stream_table : StreamTable
  async_state : AsyncState
  core_modules : Array[@types.Module]
  core_instances : Array[CoreInstance]
  core_funcs : Array[CoreFuncRef]
  core_types : Array[Bytes]
  core_tables : Array[Int]
  core_mems : Array[Int]
  core_globals : Array[Int]
  core_tags : Array[Int]
  exports : Map[String, ComponentExtern]
}

///|
fn BuildState::new(
  stream_table : StreamTable,
  async_state : AsyncState,
) -> BuildState {
  {
    types: [],
    funcs: [],
    values: [],
    components: [],
    instances: [],
    resource_table: ResourceTable::new(),
    stream_table,
    async_state,
    core_modules: [],
    core_instances: [],
    core_funcs: [],
    core_types: [],
    core_tables: [],
    core_mems: [],
    core_globals: [],
    core_tags: [],
    exports: {},
  }
}

///|
fn decode_utf8_runtime(bytes : Bytes) -> String raise ComponentRuntimeError {
  let buf = StringBuilder::new()
  let mut i = 0
  while i < bytes.length() {
    let b = bytes[i].to_int()
    if b < 0x80 {
      buf.write_char(b.unsafe_to_char())
      i = i + 1
    } else if b < 0xC0 {
      raise InvalidUtf8
    } else if b < 0xE0 {
      if i + 1 >= bytes.length() {
        raise InvalidUtf8
      }
      let b2 = bytes[i + 1].to_int()
      if (b2 & 0xC0) != 0x80 {
        raise InvalidUtf8
      }
      let cp = ((b & 0x1F) << 6) | (b2 & 0x3F)
      if cp < 0x80 {
        raise InvalidUtf8
      }
      buf.write_char(cp.unsafe_to_char())
      i = i + 2
    } else if b < 0xF0 {
      if i + 2 >= bytes.length() {
        raise InvalidUtf8
      }
      let b2 = bytes[i + 1].to_int()
      let b3 = bytes[i + 2].to_int()
      if (b2 & 0xC0) != 0x80 || (b3 & 0xC0) != 0x80 {
        raise InvalidUtf8
      }
      let cp = ((b & 0x0F) << 12) | ((b2 & 0x3F) << 6) | (b3 & 0x3F)
      if cp < 0x800 || (cp >= 0xD800 && cp <= 0xDFFF) {
        raise InvalidUtf8
      }
      buf.write_char(cp.unsafe_to_char())
      i = i + 3
    } else if b < 0xF8 {
      if i + 3 >= bytes.length() {
        raise InvalidUtf8
      }
      let b2 = bytes[i + 1].to_int()
      let b3 = bytes[i + 2].to_int()
      let b4 = bytes[i + 3].to_int()
      if (b2 & 0xC0) != 0x80 || (b3 & 0xC0) != 0x80 || (b4 & 0xC0) != 0x80 {
        raise InvalidUtf8
      }
      let cp = ((b & 0x07) << 18) |
        ((b2 & 0x3F) << 12) |
        ((b3 & 0x3F) << 6) |
        (b4 & 0x3F)
      if cp < 0x10000 || cp > 0x10FFFF {
        raise InvalidUtf8
      }
      buf.write_char(cp.unsafe_to_char())
      i = i + 4
    } else {
      raise InvalidUtf8
    }
  }
  buf.to_string()
}

///|
fn encode_utf8_string(s : String) -> Bytes {
  let bytes : Array[Byte] = []
  for c in s {
    let cp = c.to_int()
    if cp < 0x80 {
      bytes.push(cp.to_byte())
    } else if cp < 0x800 {
      bytes.push((0xC0 | (cp >> 6)).to_byte())
      bytes.push((0x80 | (cp & 0x3F)).to_byte())
    } else if cp < 0x10000 {
      bytes.push((0xE0 | (cp >> 12)).to_byte())
      bytes.push((0x80 | ((cp >> 6) & 0x3F)).to_byte())
      bytes.push((0x80 | (cp & 0x3F)).to_byte())
    } else {
      bytes.push((0xF0 | (cp >> 18)).to_byte())
      bytes.push((0x80 | ((cp >> 12) & 0x3F)).to_byte())
      bytes.push((0x80 | ((cp >> 6) & 0x3F)).to_byte())
      bytes.push((0x80 | (cp & 0x3F)).to_byte())
    }
  }
  Bytes::from_array(bytes)
}

///|
/// Encode a component-model string for the given canonical encoding, returning:
/// - raw bytes to write into memory
/// - the `len` value to pass alongside the pointer
/// - required alignment for the allocation
fn encode_string_for_canon(
  s : String,
  encoding : StringEncoding,
) -> (Bytes, Int, Int) {
  match encoding {
    Utf8 => {
      let bytes = encode_utf8_string(s)
      (bytes, bytes.length(), 1)
    }
    Utf16 => {
      let out : Array[Byte] = []
      let mut units = 0
      for c in s {
        let cp = c.to_int()
        if cp < 0x10000 {
          out.push((cp & 0xFF).to_byte())
          out.push(((cp >> 8) & 0xFF).to_byte())
          units += 1
        } else {
          let v = cp - 0x10000
          let high = 0xD800 | ((v >> 10) & 0x3FF)
          let low = 0xDC00 | (v & 0x3FF)
          out.push((high & 0xFF).to_byte())
          out.push(((high >> 8) & 0xFF).to_byte())
          out.push((low & 0xFF).to_byte())
          out.push(((low >> 8) & 0xFF).to_byte())
          units += 2
        }
      }
      (Bytes::from_array(out), units, 2)
    }
    Latin1Utf16 => {
      // Encode as latin1 if possible, otherwise utf16. We use the high bit of
      // the length to indicate latin1.
      let mut latin1_ok = true
      for c in s {
        if c.to_int() > 0xFF {
          latin1_ok = false
          break
        }
      }
      if latin1_ok {
        let bytes : Array[Byte] = []
        for c in s {
          bytes.push(c.to_int().to_byte())
        }
        let len = (bytes.length().reinterpret_as_uint() | 0x8000_0000U).reinterpret_as_int()
        (Bytes::from_array(bytes), len, 2)
      } else {
        let (bytes, units, _align) = encode_string_for_canon(
          s,
          StringEncoding::Utf16,
        )
        (bytes, units, 2)
      }
    }
  }
}

///|
fn decode_import_name(name : ImportName) -> String raise ComponentRuntimeError {
  match name {
    Plain(bytes) => decode_utf8_runtime(bytes)
    WithVersion(bytes, ver) =>
      decode_utf8_runtime(bytes) + "@" + decode_utf8_runtime(ver)
  }
}

///|
fn decode_export_name(name : ExportName) -> String raise ComponentRuntimeError {
  match name {
    Plain(bytes) => decode_utf8_runtime(bytes)
    WithVersion(bytes, ver) =>
      decode_utf8_runtime(bytes) + "@" + decode_utf8_runtime(ver)
  }
}

///|
fn synthesize_trivial_instance_import(
  key : String,
  tyidx : Int,
  types : Array[TypeDef?],
  store : @runtime.Store,
) -> ComponentInstance? raise ComponentRuntimeError {
  if tyidx < 0 || tyidx >= types.length() {
    return None
  }
  fn resolve_inst_typedef(
    local_types : Array[TypeDef?],
    idx : Int,
  ) -> TypeDef? {
    if idx >= 0 && idx < local_types.length() {
      return local_types[idx]
    }
    if idx >= 0 && idx < types.length() {
      return types[idx]
    }
    None
  }

  fn make_instance(
    name : String,
    exports : Map[String, ComponentExtern],
  ) -> ComponentInstance {
    let stream_table = StreamTable::new()
    let async_state = AsyncState::new(stream_table)
    {
      name,
      types: [],
      funcs: [],
      values: [],
      components: [],
      instances: [],
      resource_table: ResourceTable::new(),
      stream_table,
      async_state,
      core_modules: [],
      core_instances: [],
      core_funcs: [],
      core_types: [],
      core_tables: [],
      core_mems: [],
      core_globals: [],
      core_tags: [],
      exports,
      store,
    }
  }

  fn synthesize_from_typedef(
    inst_key : String,
    td : TypeDef,
  ) -> ComponentInstance? raise ComponentRuntimeError {
    match td {
      TypeDef::InstanceTypeEmpty =>
        Some(make_instance("\{inst_key}::empty", {}))
      TypeDef::InstanceType(decls) => {
        let local_types : Array[TypeDef?] = []
        let exports : Map[String, ComponentExtern] = {}
        for d in decls {
          match d {
            InstanceDecl::Type(t) => local_types.push(Some(t))
            InstanceDecl::AliasOuter(kind, _count, _idx) =>
              if kind == 0x03 {
                local_types.push(None)
              }
            InstanceDecl::AliasInstanceExport(kind, _instance_idx, _name) =>
              if kind == 0x03 {
                local_types.push(None)
              }
            InstanceDecl::Export(name, ExternDesc::Type(bound)) =>
              match bound {
                TypeBound::Eq(ti) => {
                  let aliased = if ti >= 0 && ti < local_types.length() {
                    local_types[ti]
                  } else if ti >= 0 && ti < types.length() {
                    types[ti]
                  } else {
                    None
                  }
                  exports.set(name, ComponentExtern::Type(aliased))
                  // Type exports also occupy a slot in the local type space.
                  local_types.push(aliased)
                }
                // Cannot synthesize abstract resources without a host-supplied identity.
                TypeBound::SubResource => return None
              }
            InstanceDecl::Export(name, ExternDesc::InstanceType(inner)) =>
              match resolve_inst_typedef(local_types, inner) {
                Some(inner_td) =>
                  match
                    synthesize_from_typedef("\{inst_key}::\{name}", inner_td) {
                    Some(inner_inst) =>
                      exports.set(name, ComponentExtern::Instance(inner_inst))
                    None => return None
                  }
                None => return None
              }
            InstanceDecl::Export(_, _) => return None
            _ => return None
          }
        }
        Some(make_instance("\{inst_key}::empty", exports))
      }
      _ => None
    }
  }

  match types[tyidx] {
    Some(td) => synthesize_from_typedef(key, td)
    _ => None
  }
}

///|
