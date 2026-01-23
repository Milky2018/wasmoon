///|
/// Minimal WIT -> Component encoder for `wasmoon-tools wit --wasm/--wat`.
///
/// This intentionally supports only a small subset for now:
/// - interface items: `func` only
/// - function signatures: built-in scalar types only (u32, string, ...)
/// - world items: `import` / `export` of interfaces only
///
/// Richer WIT type lowering (records/variants/resources/etc) will be added once
/// the component type system and canonical ABI support grows.

///|
priv struct ByteBuf {
  data : Array[Byte]
}

///|
fn ByteBuf::new() -> ByteBuf {
  { data: [] }
}

///|
fn ByteBuf::push_u8(self : ByteBuf, b : Int) -> Unit {
  self.data.push(b.to_byte())
}

///|
fn ByteBuf::push_bytes(self : ByteBuf, bs : Bytes) -> Unit {
  for i in 0..<bs.length() {
    self.data.push(bs[i])
  }
}

///|
fn ByteBuf::push_uleb_u32(self : ByteBuf, n : Int) -> Unit {
  // Standard unsigned LEB128 encoding.
  let mut x = n
  let mut more = true
  while more {
    let mut b = x & 0x7f
    x = x >> 7
    more = x != 0
    if more {
      b = b | 0x80
    }
    self.push_u8(b)
  }
}

///|
fn ByteBuf::push_ascii(self : ByteBuf, s : String) -> Unit {
  // Component names are UTF-8 in general; for now we assume ASCII since we're
  // generating names from WIT identifiers/packages.
  for i in 0..<s.length() {
    self.data.push(s.code_unit_at(i).to_int().to_byte())
  }
}

///|
fn ByteBuf::push_name(self : ByteBuf, s : String) -> Unit {
  // name = u32-len + utf8 bytes. We currently assume ASCII input.
  self.push_uleb_u32(s.length())
  self.push_ascii(s)
}

///|
fn ByteBuf::to_bytes(self : ByteBuf) -> Bytes {
  Bytes::from_array(self.data)
}

///|
fn wit_type_to_prim_opcode(t : TypeExpr) -> Int raise WitError {
  match t {
    Id(n) =>
      match n {
        "bool" => 0x7f
        "s8" => 0x7e
        "u8" => 0x7d
        "s16" => 0x7c
        "u16" => 0x7b
        "s32" => 0x7a
        "u32" => 0x79
        "s64" => 0x78
        "u64" => 0x77
        "f32" => 0x76
        "f64" => 0x75
        "char" => 0x74
        "string" => 0x73
        _ =>
          raise WitError::Error(
            "unsupported WIT type for component encoding: `" + n + "`",
          )
      }
    _ => raise WitError::Error("unsupported WIT type expression in signature")
  }
}

///|
fn encode_valtype(buf : ByteBuf, t : TypeExpr) -> Unit raise WitError {
  buf.push_u8(wit_type_to_prim_opcode(t))
}

///|
fn encode_functype(buf : ByteBuf, f : FuncDecl) -> Unit raise WitError {
  // functype ::= 0x40|0x43 paramlist resultlist
  buf.push_u8(if f.is_async { 0x43 } else { 0x40 })
  // paramlist
  buf.push_uleb_u32(f.params.length())
  for p in f.params {
    buf.push_name(p.0)
    encode_valtype(buf, p.1)
  }
  // resultlist: either 0x01 0x00 (empty) or 0x00 valtype (single)
  if f.results.length() == 0 {
    buf.push_u8(0x01)
    buf.push_u8(0x00)
  } else if f.results.length() == 1 {
    buf.push_u8(0x00)
    encode_valtype(buf, f.results[0].1)
  } else {
    raise WitError::Error(
      "unsupported WIT function results for component encoding (expected 0 or 1 result)",
    )
  }
}

///|
fn encode_exportname_string_plain(buf : ByteBuf, name : String) -> Unit {
  // exportname-string: 0x00 + name
  buf.push_u8(0x00)
  buf.push_name(name)
}

///|
fn encode_externdesc_functype(buf : ByteBuf, idx : Int) -> Unit {
  buf.push_u8(0x01)
  buf.push_uleb_u32(idx)
}

///|
fn encode_externdesc_instancetype(buf : ByteBuf, idx : Int) -> Unit {
  buf.push_u8(0x05)
  buf.push_uleb_u32(idx)
}

///|
fn encode_externdesc_componenttype(buf : ByteBuf, idx : Int) -> Unit {
  buf.push_u8(0x04)
  buf.push_uleb_u32(idx)
}

///|
fn encode_instancetype_from_interface(
  buf : ByteBuf,
  iface : Interface,
) -> Unit raise WitError {
  // instancetype ::= 0x42 id*:vec(<instancedecl>)
  buf.push_u8(0x42)
  // Each function becomes:
  // - instancedecl::Type(functype)
  // - instancedecl::Export(name, FuncType(local_typeidx))
  let funcs : Array[FuncDecl] = []
  for it in iface.items {
    match it {
      Func(f) => funcs.push(f)
      _ =>
        raise WitError::Error(
          "unsupported interface item for component encoding (only `func` is supported): `" +
          iface.name +
          "`",
        )
    }
  }
  buf.push_uleb_u32(funcs.length() * 2)
  let mut local_typeidx = 0
  for f in funcs {
    // type
    buf.push_u8(0x01)
    encode_functype(buf, f)
    // export
    buf.push_u8(0x04)
    encode_exportname_string_plain(buf, f.name)
    encode_externdesc_functype(buf, local_typeidx)
    local_typeidx = local_typeidx + 1
  }
}

///|
fn encode_componenttype_wrapper_for_interface(
  buf : ByteBuf,
  iface : Interface,
  pkg_name : String,
  pkg_version : String?,
) -> Unit raise WitError {
  // componenttype ::= 0x41 cd*:vec(<componentdecl>)
  buf.push_u8(0x41)
  // decls:
  // - type instancetype
  // - export "pkg/iface[@ver]" (instance (type 0))
  buf.push_uleb_u32(2)
  // componentdecl::Type
  buf.push_u8(0x01)
  encode_instancetype_from_interface(buf, iface)
  // componentdecl::Export
  buf.push_u8(0x04)
  let full = iface_full_name(pkg_name, iface.name, pkg_version)
  encode_exportname_string_plain(buf, full)
  encode_externdesc_instancetype(buf, 0)
}

///|
fn encode_componenttype_inner_for_world(
  buf : ByteBuf,
  world : World,
  cur_pkg_key : String,
  iface_map : Map[String, Interface],
) -> Unit raise WitError {
  buf.push_u8(0x41)

  // Each interface import/export becomes:
  // - componentdecl::Type(instancetype)
  // - componentdecl::Import/Export(full_iface_name, instancetype(local_idx))
  let pairs : Array[(Bool, UsePath, Interface, String)] = []
  for wi in world.items {
    match wi {
      Import(p) | Export(p) => {
        let is_import = wi is Import(_)
        let rkey = iface_ref_key(cur_pkg_key, p)
        let iface = iface_map
          .get(rkey)
          .unwrap_or_else(fn() {
            raise WitError::Error(
              "unknown interface `" + p.raw + "` in world `" + world.name + "`",
            )
          })
        let (pkg_key_opt, name, _) = split_use_path(p)
        let pkg_key = match pkg_key_opt {
          Some(k) => k
          None => cur_pkg_key
        }
        let (pkg_name, pkg_ver) = split_pkg_key(pkg_key)
        let full = iface_full_name(pkg_name, name, pkg_ver)
        pairs.push((is_import, p, iface, full))
      }
      _ =>
        raise WitError::Error(
          "unsupported world item for component encoding (only `import`/`export` of interfaces is supported): `" +
          world.name +
          "`",
        )
    }
  }
  buf.push_uleb_u32(pairs.length() * 2)
  let mut local_typeidx = 0
  for pair in pairs {
    let (is_import, _, iface, full) = pair
    // type instancetype
    buf.push_u8(0x01)
    encode_instancetype_from_interface(buf, iface)
    // import/export instance
    buf.push_u8(if is_import { 0x02 } else { 0x04 })
    encode_exportname_string_plain(buf, full)
    encode_externdesc_instancetype(buf, local_typeidx)
    local_typeidx = local_typeidx + 1
  }
}

///|
fn encode_componenttype_wrapper_for_world(
  buf : ByteBuf,
  world : World,
  cur_pkg_key : String,
  pkg_name : String,
  pkg_version : String?,
  iface_map : Map[String, Interface],
) -> Unit raise WitError {
  buf.push_u8(0x41)
  // decls:
  // - type inner componenttype
  // - export "pkg/world[@ver]" (component (type 0))
  buf.push_uleb_u32(2)
  // type inner
  buf.push_u8(0x01)
  encode_componenttype_inner_for_world(buf, world, cur_pkg_key, iface_map)
  // export wrapper
  buf.push_u8(0x04)
  let full = world_full_name(pkg_name, world.name, pkg_version)
  encode_exportname_string_plain(buf, full)
  encode_externdesc_componenttype(buf, 0)
}

///|
fn encode_type_section_one(typedef_bytes : Bytes) -> Bytes {
  let p = ByteBuf::new()
  p.push_uleb_u32(1)
  p.push_bytes(typedef_bytes)
  p.to_bytes()
}

///|
fn encode_export_section_one(name : String, typeidx : Int) -> Bytes {
  let p = ByteBuf::new()
  p.push_uleb_u32(1)
  // exportname = 0x00 + name
  p.push_u8(0x00)
  p.push_name(name)
  // sort = Type (0x03)
  p.push_u8(0x03)
  p.push_uleb_u32(typeidx)
  // opt-externdesc = none
  p.push_u8(0x00)
  p.to_bytes()
}

///|
fn encode_section(id : Int, payload : Bytes) -> Bytes {
  let b = ByteBuf::new()
  b.push_u8(id)
  b.push_uleb_u32(payload.length())
  b.push_bytes(payload)
  b.to_bytes()
}

///|
fn pkg_key_of(pkg : Package) -> String raise WitError {
  let name = match pkg.name {
    Some(n) => n
    None => raise WitError::Error("missing `package` header")
  }
  match pkg.version {
    Some(v) => name + "@" + v
    None => name
  }
}

///|
fn split_pkg_key(key : String) -> (String, String?) {
  // pkg-key = name[@version]
  match find_last_code_unit(key, 64) { // '@'
    Some(i) =>
      if i > 0 && i + 1 < key.length() {
        (slice_ascii(key, 0, i), Some(slice_ascii(key, i + 1, key.length())))
      } else {
        (key, None)
      }
    None => (key, None)
  }
}

///|
fn iface_ref_key(cur_pkg_key : String, p : UsePath) -> String {
  match split_use_path(p) {
    (None, name, _) => cur_pkg_key + "#" + name
    (Some(k), name, _) => k + "#" + name
  }
}

///|
fn iface_full_name(pkg_name : String, iface : String, ver : String?) -> String {
  match ver {
    Some(v) => pkg_name + "/" + iface + "@" + v
    None => pkg_name + "/" + iface
  }
}

///|
fn world_full_name(pkg_name : String, world : String, ver : String?) -> String {
  match ver {
    Some(v) => pkg_name + "/" + world + "@" + v
    None => pkg_name + "/" + world
  }
}

///|
pub fn encode_wit_component_wasm(res : ResolveResult) -> Bytes raise WitError {
  let root_key = pkg_key_of(res.root)
  let (root_pkg_name, root_pkg_ver) = split_pkg_key(root_key)

  // Build interface lookup across root + deps.
  let iface_map : Map[String, Interface] = {}
  let all : Array[Package] = [res.root]
  for d in res.deps {
    all.push(d)
  }
  for pkg in all {
    let pkg_key = pkg_key_of(pkg)
    for it in pkg.items {
      match it {
        Interface(i) => iface_map.set(pkg_key + "#" + i.name, i)
        _ => ()
      }
    }
  }

  // Collect and sort exported interfaces/worlds from the root package.
  let root_ifaces : Array[Interface] = []
  let root_worlds : Array[World] = []
  for it in res.root.items {
    match it {
      Interface(i) => root_ifaces.push(i)
      World(w) => root_worlds.push(w)
      _ => ()
    }
  }
  root_ifaces.sort_by(fn(a, b) { a.name.compare(b.name) })
  root_worlds.sort_by(fn(a, b) { a.name.compare(b.name) })
  let out = ByteBuf::new()
  // wasm magic + component preamble (version=13, layer=1)
  out.push_u8(0x00)
  out.push_u8(0x61)
  out.push_u8(0x73)
  out.push_u8(0x6d)
  out.push_u8(0x0d)
  out.push_u8(0x00)
  out.push_u8(0x01)
  out.push_u8(0x00)

  // wasm-tools exports each type immediately after defining it. We'll do the same.
  let mut export_typeidx = 0
  for iface in root_ifaces {
    let tb = ByteBuf::new()
    encode_componenttype_wrapper_for_interface(
      tb, iface, root_pkg_name, root_pkg_ver,
    )
    out.push_bytes(encode_section(7, encode_type_section_one(tb.to_bytes())))
    out.push_bytes(
      encode_section(11, encode_export_section_one(iface.name, export_typeidx)),
    )
    export_typeidx = export_typeidx + 2
  }
  for world in root_worlds {
    let tb = ByteBuf::new()
    encode_componenttype_wrapper_for_world(
      tb, world, root_key, root_pkg_name, root_pkg_ver, iface_map,
    )
    out.push_bytes(encode_section(7, encode_type_section_one(tb.to_bytes())))
    out.push_bytes(
      encode_section(11, encode_export_section_one(world.name, export_typeidx)),
    )
    export_typeidx = export_typeidx + 2
  }
  out.to_bytes()
}

///|
fn sanitize_wat_id(s : String) -> String {
  let sb = StringBuilder::new()
  for i in 0..<s.length() {
    let cu = s.code_unit_at(i).to_int()
    let ok = (cu >= 48 && cu <= 57) ||
      (cu >= 65 && cu <= 90) ||
      (cu >= 97 && cu <= 122) ||
      cu == 95 // '_'
    sb.write_char(if ok { cu.unsafe_to_char() } else { '_' })
  }
  sb.to_string()
}

///|
fn typeexpr_to_wat(t : TypeExpr) -> String raise WitError {
  match t {
    Id(n) =>
      match n {
        "bool"
        | "s8"
        | "u8"
        | "s16"
        | "u16"
        | "s32"
        | "u32"
        | "s64"
        | "u64"
        | "f32"
        | "f64"
        | "char"
        | "string" => n
        _ =>
          raise WitError::Error(
            "unsupported WIT type for component encoding: `" + n + "`",
          )
      }
    _ => raise WitError::Error("unsupported WIT type expression in signature")
  }
}

///|
fn write_interface_instancetype_wat(
  sb : StringBuilder,
  indent : String,
  inst_tname : String,
  iface : Interface,
) -> Unit raise WitError {
  sb.write_string(indent + "(type " + inst_tname + " (instance\n")
  for it in iface.items {
    match it {
      Func(f) => {
        let ft_name = inst_tname + "_ft_" + sanitize_wat_id(f.name)
        sb.write_string(indent + "  (type " + ft_name + " (func")
        for p in f.params {
          sb.write_string(
            " (param \"" + p.0 + "\" " + typeexpr_to_wat(p.1) + ")",
          )
        }
        if f.results.length() == 0 {
          ()
        } else if f.results.length() == 1 {
          sb.write_string(" (result " + typeexpr_to_wat(f.results[0].1) + ")")
        } else {
          raise WitError::Error(
            "unsupported WIT function results for component encoding (expected 0 or 1 result)",
          )
        }
        sb.write_string(") )\n")
        sb.write_string(
          indent +
          "  (export \"" +
          f.name +
          "\" (func (type " +
          ft_name +
          ")))\n",
        )
      }
      _ =>
        raise WitError::Error(
          "unsupported interface item for component encoding (only `func` is supported): `" +
          iface.name +
          "`",
        )
    }
  }
  sb.write_string(indent + "))\n")
}

///|
pub fn format_wit_component_wat(res : ResolveResult) -> String raise WitError {
  let root_key = pkg_key_of(res.root)
  let (root_pkg_name, root_pkg_ver) = split_pkg_key(root_key)

  // Build interface lookup across root + deps.
  let iface_map : Map[String, Interface] = {}
  let all : Array[Package] = [res.root]
  for d in res.deps {
    all.push(d)
  }
  for pkg in all {
    let pkg_key = pkg_key_of(pkg)
    for it in pkg.items {
      match it {
        Interface(i) => iface_map.set(pkg_key + "#" + i.name, i)
        _ => ()
      }
    }
  }

  // Collect and sort exported interfaces/worlds from the root package.
  let root_ifaces : Array[Interface] = []
  let root_worlds : Array[World] = []
  for it in res.root.items {
    match it {
      Interface(i) => root_ifaces.push(i)
      World(w) => root_worlds.push(w)
      _ => ()
    }
  }
  root_ifaces.sort_by(fn(a, b) { a.name.compare(b.name) })
  root_worlds.sort_by(fn(a, b) { a.name.compare(b.name) })
  let sb = StringBuilder::new()
  sb.write_string("(component\n")
  for iface in root_ifaces {
    let base = sanitize_wat_id("iface_" + iface.name)
    let tname = "$" + base
    let inst_tname = "$" + base + "_inst"
    sb.write_string("  (type " + tname + " (component\n")
    write_interface_instancetype_wat(sb, "    ", inst_tname, iface)
    let full = iface_full_name(root_pkg_name, iface.name, root_pkg_ver)
    sb.write_string(
      "    (export \"" + full + "\" (instance (type " + inst_tname + ")))\n",
    )
    sb.write_string("  ))\n")
    sb.write_string("  (export \"" + iface.name + "\" (type " + tname + "))\n")
  }
  for world in root_worlds {
    let base = sanitize_wat_id("world_" + world.name)
    let tname = "$" + base
    let inner_tname = "$" + base + "_inner"
    sb.write_string("  (type " + tname + " (component\n")
    sb.write_string("    (type " + inner_tname + " (component\n")
    for wi in world.items {
      match wi {
        Import(p) | Export(p) => {
          let is_import = wi is Import(_)
          let rkey = iface_ref_key(root_key, p)
          let iface = iface_map
            .get(rkey)
            .unwrap_or_else(fn() {
              raise WitError::Error(
                "unknown interface `" +
                p.raw +
                "` in world `" +
                world.name +
                "`",
              )
            })
          let (pkg_key_opt, name, _) = split_use_path(p)
          let pkg_key = match pkg_key_opt {
            Some(k) => k
            None => root_key
          }
          let (pkg_name, pkg_ver) = split_pkg_key(pkg_key)
          let full = iface_full_name(pkg_name, name, pkg_ver)
          let inst_tname = inner_tname + "_inst_" + sanitize_wat_id(name)
          write_interface_instancetype_wat(sb, "      ", inst_tname, iface)
          sb.write_string(
            "      (" +
            (if is_import { "import" } else { "export" }) +
            " \"" +
            full +
            "\" (instance (type " +
            inst_tname +
            ")))\n",
          )
        }
        _ =>
          raise WitError::Error(
            "unsupported world item for component encoding (only `import`/`export` of interfaces is supported): `" +
            world.name +
            "`",
          )
      }
    }
    sb.write_string("    ))\n")
    let full = world_full_name(root_pkg_name, world.name, root_pkg_ver)
    sb.write_string(
      "    (export \"" + full + "\" (component (type " + inner_tname + ")))\n",
    )
    sb.write_string("  ))\n")
    sb.write_string("  (export \"" + world.name + "\" (type " + tname + "))\n")
  }
  sb.write_string(")\n")
  sb.to_string()
}
