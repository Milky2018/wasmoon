///|
/// Minimal WIT -> Component encoder for `wasmoon-tools wit --wasm/--wat`.
///
/// This supports a useful subset of the WIT->component-type encoding used by
/// `wasm-tools component wit`, focusing on type signatures rather than
/// executable components.
///
/// Supported:
/// - Interface items: `func`, `type` alias, `record`, `variant`, `flags`, `enum`,
///   `resource` (type export + methods)
/// - Function signatures: prim types + type constructors (`list`, `tuple`,
///   `option`, `result`, `borrow`, `own`, `future`, `stream`) and named types
/// - World items: `import`/`export` of interfaces
///
/// Not supported (yet):
/// - Component execution/canonical ABI sections (this only emits component *types*)
/// - World inline interfaces / import/export funcs / include / use (world-level)

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
fn ByteBuf::push_sleb_i32(self : ByteBuf, n : Int) -> Unit {
  // Standard signed LEB128 encoding for 32-bit-ish ints.
  let mut x = n
  let mut more = true
  while more {
    let mut b = x & 0x7f
    x = x >> 7
    let sign_bit_set = (b & 0x40) != 0
    // Stop when the remaining bits are all sign-extension.
    if (x == 0 && !sign_bit_set) || (x == -1 && sign_bit_set) {
      more = false
    } else {
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
priv enum EncValType {
  Prim(Int)
  TypeIdx(Int)
}

///|
fn encode_valtype(buf : ByteBuf, vt : EncValType) -> Unit {
  match vt {
    Prim(op) => buf.push_u8(op)
    TypeIdx(idx) => buf.push_sleb_i32(idx)
  }
}

///|
priv struct EncFuncType {
  is_async : Bool
  params : Array[(String, EncValType)]
  result : EncValType?
}

///|
fn encode_functype(buf : ByteBuf, f : EncFuncType) -> Unit {
  // functype ::= 0x40|0x43 paramlist resultlist
  buf.push_u8(if f.is_async { 0x43 } else { 0x40 })
  // paramlist
  buf.push_uleb_u32(f.params.length())
  for p in f.params {
    buf.push_name(p.0)
    encode_valtype(buf, p.1)
  }
  // resultlist: either 0x01 0x00 (empty) or 0x00 valtype (single)
  match f.result {
    None => {
      buf.push_u8(0x01)
      buf.push_u8(0x00)
    }
    Some(r) => {
      buf.push_u8(0x00)
      encode_valtype(buf, r)
    }
  }
}

///|
fn typedef_prim(op : Int) -> Bytes {
  let b = ByteBuf::new()
  b.push_u8(op)
  b.to_bytes()
}

///|
fn typedef_list(elem : EncValType) -> Bytes {
  let b = ByteBuf::new()
  b.push_u8(0x70)
  encode_valtype(b, elem)
  b.to_bytes()
}

///|
fn typedef_tuple(elems : Array[EncValType]) -> Bytes {
  let b = ByteBuf::new()
  b.push_u8(0x6f)
  b.push_uleb_u32(elems.length())
  for e in elems {
    encode_valtype(b, e)
  }
  b.to_bytes()
}

///|
fn typedef_option(t : EncValType) -> Bytes {
  let b = ByteBuf::new()
  b.push_u8(0x6b)
  encode_valtype(b, t)
  b.to_bytes()
}

///|
fn typedef_result(ok : EncValType?, err : EncValType?) -> Bytes {
  let b = ByteBuf::new()
  b.push_u8(0x6a)
  match ok {
    None => b.push_u8(0x00)
    Some(v) => {
      b.push_u8(0x01)
      encode_valtype(b, v)
    }
  }
  match err {
    None => b.push_u8(0x00)
    Some(v) => {
      b.push_u8(0x01)
      encode_valtype(b, v)
    }
  }
  b.to_bytes()
}

///|
fn typedef_record(fields : Array[(String, EncValType)]) -> Bytes {
  let b = ByteBuf::new()
  b.push_u8(0x72)
  b.push_uleb_u32(fields.length())
  for f in fields {
    b.push_name(f.0)
    encode_valtype(b, f.1)
  }
  b.to_bytes()
}

///|
fn typedef_variant(cases : Array[(String, EncValType?)]) -> Bytes {
  let b = ByteBuf::new()
  b.push_u8(0x71)
  b.push_uleb_u32(cases.length())
  for c in cases {
    b.push_name(c.0)
    match c.1 {
      None => b.push_u8(0x00)
      Some(v) => {
        b.push_u8(0x01)
        encode_valtype(b, v)
      }
    }
    // No `refines` support here.
    b.push_u8(0x00)
  }
  b.to_bytes()
}

///|
fn typedef_flags(names : Array[String]) -> Bytes {
  let b = ByteBuf::new()
  b.push_u8(0x6e)
  b.push_uleb_u32(names.length())
  for n in names {
    b.push_name(n)
  }
  b.to_bytes()
}

///|
fn typedef_enum(names : Array[String]) -> Bytes {
  let b = ByteBuf::new()
  b.push_u8(0x6d)
  b.push_uleb_u32(names.length())
  for n in names {
    b.push_name(n)
  }
  b.to_bytes()
}

///|
fn typedef_own(resource_typeidx : Int) -> Bytes {
  let b = ByteBuf::new()
  b.push_u8(0x69)
  b.push_uleb_u32(resource_typeidx)
  b.to_bytes()
}

///|
fn typedef_borrow(resource_typeidx : Int) -> Bytes {
  let b = ByteBuf::new()
  b.push_u8(0x68)
  b.push_uleb_u32(resource_typeidx)
  b.to_bytes()
}

///|
fn typedef_future(payload : EncValType?) -> Bytes {
  let b = ByteBuf::new()
  b.push_u8(0x65)
  match payload {
    None => b.push_u8(0x00)
    Some(v) => {
      b.push_u8(0x01)
      encode_valtype(b, v)
    }
  }
  b.to_bytes()
}

///|
fn typedef_stream(payload : EncValType?) -> Bytes {
  let b = ByteBuf::new()
  b.push_u8(0x66)
  match payload {
    None => b.push_u8(0x00)
    Some(v) => {
      b.push_u8(0x01)
      encode_valtype(b, v)
    }
  }
  b.to_bytes()
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
priv enum EncTypeBound {
  Eq(Int)
  SubResource
}

///|
fn instancedecl_type(typedef : Bytes) -> Bytes {
  let b = ByteBuf::new()
  b.push_u8(0x01)
  b.push_bytes(typedef)
  b.to_bytes()
}

///|
fn instancedecl_alias_outer_type(count : Int, idx : Int) -> Bytes {
  let b = ByteBuf::new()
  b.push_u8(0x02)
  // kind = Type
  b.push_u8(0x03)
  // target = Outer (0x02)
  b.push_u8(0x02)
  b.push_uleb_u32(count)
  b.push_uleb_u32(idx)
  b.to_bytes()
}

///|
fn instancedecl_export_type(name : String, bound : EncTypeBound) -> Bytes {
  let b = ByteBuf::new()
  b.push_u8(0x04)
  encode_exportname_string_plain(b, name)
  // externdesc::Type
  b.push_u8(0x03)
  match bound {
    Eq(ti) => {
      b.push_u8(0x00)
      b.push_uleb_u32(ti)
    }
    SubResource => b.push_u8(0x01)
  }
  b.to_bytes()
}

///|
fn instancedecl_export_func(name : String, functype_idx : Int) -> Bytes {
  let b = ByteBuf::new()
  b.push_u8(0x04)
  encode_exportname_string_plain(b, name)
  encode_externdesc_functype(b, functype_idx)
  b.to_bytes()
}

///|
fn encode_instancetype(decls : Array[Bytes]) -> Bytes {
  let b = ByteBuf::new()
  b.push_u8(0x42)
  b.push_uleb_u32(decls.length())
  for d in decls {
    b.push_bytes(d)
  }
  b.to_bytes()
}

///|
fn componentdecl_type(typedef : Bytes) -> Bytes {
  let b = ByteBuf::new()
  b.push_u8(0x01)
  b.push_bytes(typedef)
  b.to_bytes()
}

///|
fn componentdecl_import_instance(
  name : String,
  instancetype_typeidx : Int,
) -> Bytes {
  let b = ByteBuf::new()
  b.push_u8(0x03)
  encode_exportname_string_plain(b, name)
  encode_externdesc_instancetype(b, instancetype_typeidx)
  b.to_bytes()
}

///|
fn componentdecl_export_instance(
  name : String,
  instancetype_typeidx : Int,
) -> Bytes {
  let b = ByteBuf::new()
  b.push_u8(0x04)
  encode_exportname_string_plain(b, name)
  encode_externdesc_instancetype(b, instancetype_typeidx)
  b.to_bytes()
}

///|

///|
fn componentdecl_alias_instance_export_type(
  instance_idx : Int,
  name : String,
) -> Bytes {
  let b = ByteBuf::new()
  b.push_u8(0x02)
  // kind = Type
  b.push_u8(0x03)
  // target = InstanceExport (0x00)
  b.push_u8(0x00)
  b.push_uleb_u32(instance_idx)
  // Alias targets use plain `name` encoding (len + bytes).
  b.push_name(name)
  b.to_bytes()
}

///|
fn encode_componenttype(decls : Array[Bytes]) -> Bytes {
  let b = ByteBuf::new()
  b.push_u8(0x41)
  b.push_uleb_u32(decls.length())
  for d in decls {
    b.push_bytes(d)
  }
  b.to_bytes()
}

///|
fn is_prim_id(name : String) -> Bool {
  match name {
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
    | "string" => true
    _ => false
  }
}

///|
fn prim_opcode_of_id(name : String) -> Int raise WitError {
  wit_type_to_prim_opcode(Id(name))
}

///|
priv struct TypeEnv {
  next_typeidx : Array[Int]
  // Exported type/resource name -> nominal type index (the one created by type export decl).
  named_typeidx : Map[String, Int]
  // local-name -> true iff it's a resource type.
  resources : Map[String, Bool]
  // cache key -> type index (for anonymous/compound types).
  cache : Map[String, Int]
  decls : Array[Bytes]
}

///|
fn TypeEnv::new() -> TypeEnv {
  { next_typeidx: [0], named_typeidx: {}, resources: {}, cache: {}, decls: [] }
}

///|
fn TypeEnv::alloc_type(self : TypeEnv, typedef : Bytes) -> Int {
  let idx = self.next_typeidx[0]
  self.next_typeidx[0] = self.next_typeidx[0] + 1
  self.decls.push(instancedecl_type(typedef))
  idx
}

///|
fn TypeEnv::alloc_alias_outer(self : TypeEnv, outer_typeidx : Int) -> Int {
  let idx = self.next_typeidx[0]
  self.next_typeidx[0] = self.next_typeidx[0] + 1
  self.decls.push(instancedecl_alias_outer_type(1, outer_typeidx))
  idx
}

///|
fn TypeEnv::export_type_eq(
  self : TypeEnv,
  name : String,
  target_idx : Int,
) -> Int {
  // Exporting a type introduces a fresh nominal type index.
  self.decls.push(instancedecl_export_type(name, Eq(target_idx)))
  let idx = self.next_typeidx[0]
  self.next_typeidx[0] = self.next_typeidx[0] + 1
  self.named_typeidx.set(name, idx)
  idx
}

///|
fn TypeEnv::export_resource(self : TypeEnv, name : String) -> Int {
  self.decls.push(instancedecl_export_type(name, SubResource))
  let idx = self.next_typeidx[0]
  self.next_typeidx[0] = self.next_typeidx[0] + 1
  self.named_typeidx.set(name, idx)
  self.resources.set(name, true)
  idx
}

///|
fn typeexpr_key_of_valtype(vt : EncValType) -> String {
  match vt {
    Prim(op) => "p:" + op.to_string()
    TypeIdx(i) => "t:" + i.to_string()
  }
}

///|
fn ensure_compound_type(env : TypeEnv, key : String, typedef : Bytes) -> Int {
  match env.cache.get(key) {
    Some(i) => i
    None => {
      let idx = env.alloc_type(typedef)
      env.cache.set(key, idx)
      idx
    }
  }
}

///|
fn lower_valtype_in_typedef(
  env : TypeEnv,
  t : TypeExpr,
) -> EncValType raise WitError {
  match t {
    Id(n) =>
      if is_prim_id(n) {
        Prim(prim_opcode_of_id(n))
      } else {
        match env.named_typeidx.get(n) {
          Some(i) => TypeIdx(i)
          None =>
            raise WitError::Error("unknown type `" + n + "` in type definition")
        }
      }
    Record(fields) => {
      // Anonymous inline record type.
      let lowered : Array[(String, EncValType)] = []
      for f in fields {
        lowered.push((f.0, lower_valtype_in_typedef(env, f.1)))
      }
      let key = "record:" +
        lowered
        .map(fn(p) { p.0 + "=" + typeexpr_key_of_valtype(p.1) })
        .join(",")
      let idx = ensure_compound_type(env, key, typedef_record(lowered))
      TypeIdx(idx)
    }
    Apply(name, args) =>
      // Anonymous compound type inside a definition.
      // Note: `borrow`/`own` are type constructors over a resource *typeidx*.
      match name {
        "list" => {
          if args.length() < 1 {
            raise WitError::Error("list<T> requires an element type")
          }
          let elem = lower_valtype_in_typedef(env, args[0])
          let key = "list:" + typeexpr_key_of_valtype(elem)
          let idx = ensure_compound_type(env, key, typedef_list(elem))
          TypeIdx(idx)
        }
        "tuple" => {
          let elems : Array[EncValType] = []
          for a in args {
            elems.push(lower_valtype_in_typedef(env, a))
          }
          let key = "tuple:" + elems.map(typeexpr_key_of_valtype).join(",")
          let idx = ensure_compound_type(env, key, typedef_tuple(elems))
          TypeIdx(idx)
        }
        "option" => {
          if args.length() != 1 {
            raise WitError::Error(
              "option<T> requires exactly one type argument",
            )
          }
          let inner = lower_valtype_in_typedef(env, args[0])
          let key = "option:" + typeexpr_key_of_valtype(inner)
          let idx = ensure_compound_type(env, key, typedef_option(inner))
          TypeIdx(idx)
        }
        "result" => {
          let ok = if args.length() >= 1 {
            Some(lower_valtype_in_typedef(env, args[0]))
          } else {
            None
          }
          let err = if args.length() >= 2 {
            Some(lower_valtype_in_typedef(env, args[1]))
          } else {
            None
          }
          let key = "result:" +
            ok.map_or("".to_string(), typeexpr_key_of_valtype) +
            "|" +
            err.map_or("".to_string(), typeexpr_key_of_valtype)
          let idx = ensure_compound_type(env, key, typedef_result(ok, err))
          TypeIdx(idx)
        }
        "future" => {
          let payload = if args.length() >= 1 {
            Some(lower_valtype_in_typedef(env, args[0]))
          } else {
            None
          }
          let key = "future:" +
            payload.map_or("".to_string(), typeexpr_key_of_valtype)
          let idx = ensure_compound_type(env, key, typedef_future(payload))
          TypeIdx(idx)
        }
        "stream" => {
          let payload = if args.length() >= 1 {
            Some(lower_valtype_in_typedef(env, args[0]))
          } else {
            None
          }
          let key = "stream:" +
            payload.map_or("".to_string(), typeexpr_key_of_valtype)
          let idx = ensure_compound_type(env, key, typedef_stream(payload))
          TypeIdx(idx)
        }
        "borrow" => {
          if args.length() != 1 {
            raise WitError::Error(
              "borrow<T> requires exactly one type argument",
            )
          }
          match args[0] {
            Id(n) =>
              match env.named_typeidx.get(n) {
                Some(ridx) => {
                  let key = "borrow:" + ridx.to_string()
                  let idx = ensure_compound_type(env, key, typedef_borrow(ridx))
                  TypeIdx(idx)
                }
                None =>
                  raise WitError::Error("unknown type `" + n + "` in borrow<>")
              }
            _ => raise WitError::Error("borrow<> expects a type identifier")
          }
        }
        "own" => {
          if args.length() != 1 {
            raise WitError::Error("own<T> requires exactly one type argument")
          }
          match args[0] {
            Id(n) =>
              match env.named_typeidx.get(n) {
                Some(ridx) => {
                  let key = "own:" + ridx.to_string()
                  let idx = ensure_compound_type(env, key, typedef_own(ridx))
                  TypeIdx(idx)
                }
                None =>
                  raise WitError::Error("unknown type `" + n + "` in own<>")
              }
            _ => raise WitError::Error("own<> expects a type identifier")
          }
        }
        _ =>
          raise WitError::Error(
            "unsupported type constructor `" + name + "` in type definition",
          )
      }
  }
}

///|
fn lower_valtype_in_value(
  env : TypeEnv,
  t : TypeExpr,
) -> EncValType raise WitError {
  match t {
    Id(n) =>
      if is_prim_id(n) {
        Prim(prim_opcode_of_id(n))
      } else if env.resources.get(n) is Some(true) {
        // Plain resource type in WIT value position is owned.
        let ridx = env.named_typeidx
          .get(n)
          .unwrap_or_else(fn() {
            raise WitError::Error("unknown resource `" + n + "`")
          })
        let key = "own:" + ridx.to_string()
        let idx = ensure_compound_type(env, key, typedef_own(ridx))
        TypeIdx(idx)
      } else {
        match env.named_typeidx.get(n) {
          Some(i) => TypeIdx(i)
          None =>
            raise WitError::Error(
              "unknown type `" + n + "` in function signature",
            )
        }
      }
    _ => lower_valtype_in_typedef(env, t)
  }
}

///|
fn encode_interface_instancetype_full(
  iface : Interface,
  imported_types : Array[(String, Int, Bool)],
) -> Bytes raise WitError {
  // imported_types: (local_name, outer_typeidx, is_resource)
  let env = TypeEnv::new()

  // Re-export imported types/resources via alias outer + type export.
  for it in imported_types {
    let (local_name, outer_ti, is_res) = it
    let alias_idx = env.alloc_alias_outer(outer_ti)
    env.export_type_eq(local_name, alias_idx) |> ignore
    if is_res {
      env.resources.set(local_name, true)
    }
  }

  // Collect local type items.
  let local_type_names : Map[String, Bool] = {}
  for it in iface.items {
    match it {
      TypeAlias(t) => local_type_names.set(t.name, true)
      Record(r) => local_type_names.set(r.name, true)
      Variant(v) => local_type_names.set(v.name, true)
      Flags(f) => local_type_names.set(f.name, true)
      Enum(e) => local_type_names.set(e.name, true)
      _ => ()
    }
  }

  // Helper to collect dependencies from a TypeExpr.
  fn collect_deps_from_typeexpr(t : TypeExpr, out : Map[String, Bool]) -> Unit {
    match t {
      Id(n) => if !is_prim_id(n) { out.set(n, true) }
      Apply(_n, args) =>
        for a in args {
          collect_deps_from_typeexpr(a, out)
        }
      Record(fields) =>
        for f in fields {
          collect_deps_from_typeexpr(f.1, out)
        }
    }
  }

  // Toposort local type defs (excluding pure aliases-to-Id which become exports only).
  let deps_map : Map[String, Array[String]] = {}
  for it in iface.items {
    match it {
      TypeAlias(t) =>
        match t.ty {
          Id(_) => ()
          _ => {
            let deps0 : Map[String, Bool] = {}
            collect_deps_from_typeexpr(t.ty, deps0)
            let deps : Array[String] = []
            for kv in deps0.iter() {
              let (k, _) = kv
              if local_type_names.get(k) is Some(true) {
                deps.push(k)
              }
            }
            deps_map.set(t.name, deps)
          }
        }
      Record(r) => {
        let deps0 : Map[String, Bool] = {}
        for f in r.fields {
          collect_deps_from_typeexpr(f.1, deps0)
        }
        let deps : Array[String] = []
        for kv in deps0.iter() {
          let (k, _) = kv
          if local_type_names.get(k) is Some(true) {
            deps.push(k)
          }
        }
        deps_map.set(r.name, deps)
      }
      Variant(v) => {
        let deps0 : Map[String, Bool] = {}
        for c in v.cases {
          if c.payload is Some(t) {
            collect_deps_from_typeexpr(t, deps0)
          }
        }
        let deps : Array[String] = []
        for kv in deps0.iter() {
          let (k, _) = kv
          if local_type_names.get(k) is Some(true) {
            deps.push(k)
          }
        }
        deps_map.set(v.name, deps)
      }
      Flags(f) => deps_map.set(f.name, [])
      Enum(e) => deps_map.set(e.name, [])
      _ => ()
    }
  }

  // DFS topo sort.
  let state : Map[String, Int] = {}
  let order : Array[String] = []
  fn dfs(n : String) -> Unit raise WitError {
    let st = state.get(n).unwrap_or(0)
    if st == 2 {
      return
    }
    if st == 1 {
      raise WitError::Error("cycle in interface types at `" + n + "`")
    }
    state.set(n, 1)
    for d in deps_map.get(n).unwrap_or([]) {
      dfs(d)
    }
    state.set(n, 2)
    order.push(n)
  }

  for kv in deps_map.iter() {
    let (k, _) = kv
    if state.get(k).unwrap_or(0) == 0 {
      dfs(k)
    }
  }

  // Emit local type defs in topo order.
  for name in order {
    // Find the declaration in the original item list.
    for it in iface.items {
      match it {
        TypeAlias(t) =>
          if t.name == name {
            match t.ty {
              Id(rhs) =>
                if is_prim_id(rhs) {
                  let base = env.alloc_type(
                    typedef_prim(prim_opcode_of_id(rhs)),
                  )
                  env.export_type_eq(t.name, base) |> ignore
                } else {
                  let target = env.named_typeidx
                    .get(rhs)
                    .unwrap_or_else(fn() {
                      raise WitError::Error("unknown type `" + rhs + "`")
                    })
                  env.export_type_eq(t.name, target) |> ignore
                }
              _ => {
                let base = match t.ty {
                  Record(fields) => {
                    let lowered : Array[(String, EncValType)] = []
                    for f in fields {
                      lowered.push((f.0, lower_valtype_in_typedef(env, f.1)))
                    }
                    env.alloc_type(typedef_record(lowered))
                  }
                  Apply(nm, args) =>
                    match nm {
                      "list" =>
                        if args.length() < 1 {
                          raise WitError::Error(
                            "list<T> requires an element type",
                          )
                        } else {
                          let elem = lower_valtype_in_typedef(env, args[0])
                          env.alloc_type(typedef_list(elem))
                        }
                      "tuple" => {
                        let elems : Array[EncValType] = []
                        for a in args {
                          elems.push(lower_valtype_in_typedef(env, a))
                        }
                        env.alloc_type(typedef_tuple(elems))
                      }
                      "option" =>
                        if args.length() != 1 {
                          raise WitError::Error(
                            "option<T> requires exactly one type argument",
                          )
                        } else {
                          let inner = lower_valtype_in_typedef(env, args[0])
                          env.alloc_type(typedef_option(inner))
                        }
                      "result" => {
                        let ok = if args.length() >= 1 {
                          Some(lower_valtype_in_typedef(env, args[0]))
                        } else {
                          None
                        }
                        let err = if args.length() >= 2 {
                          Some(lower_valtype_in_typedef(env, args[1]))
                        } else {
                          None
                        }
                        env.alloc_type(typedef_result(ok, err))
                      }
                      "future" => {
                        let payload = if args.length() >= 1 {
                          Some(lower_valtype_in_typedef(env, args[0]))
                        } else {
                          None
                        }
                        env.alloc_type(typedef_future(payload))
                      }
                      "stream" => {
                        let payload = if args.length() >= 1 {
                          Some(lower_valtype_in_typedef(env, args[0]))
                        } else {
                          None
                        }
                        env.alloc_type(typedef_stream(payload))
                      }
                      _ =>
                        raise WitError::Error(
                          "unsupported type alias RHS for `" + t.name + "`",
                        )
                    }
                  Id(_) =>
                    // Handled above.
                    env.alloc_type(typedef_prim(0x7f))
                }
                env.export_type_eq(t.name, base) |> ignore
              }
            }
          }
        Record(r) =>
          if r.name == name {
            let fields : Array[(String, EncValType)] = []
            for f in r.fields {
              fields.push((f.0, lower_valtype_in_typedef(env, f.1)))
            }
            let base = env.alloc_type(typedef_record(fields))
            env.export_type_eq(r.name, base) |> ignore
          }
        Variant(v) =>
          if v.name == name {
            let cases : Array[(String, EncValType?)] = []
            for c in v.cases {
              let payload = match c.payload {
                None => None
                Some(t) => Some(lower_valtype_in_typedef(env, t))
              }
              cases.push((c.name, payload))
            }
            let base = env.alloc_type(typedef_variant(cases))
            env.export_type_eq(v.name, base) |> ignore
          }
        Flags(f) =>
          if f.name == name {
            let base = env.alloc_type(typedef_flags(f.flags))
            env.export_type_eq(f.name, base) |> ignore
          }
        Enum(e) =>
          if e.name == name {
            let base = env.alloc_type(typedef_enum(e.cases))
            env.export_type_eq(e.name, base) |> ignore
          }
        _ => ()
      }
    }
  }

  // Export local resources.
  for it in iface.items {
    match it {
      Resource(r) => env.export_resource(r.name) |> ignore
      _ => ()
    }
  }

  // Export interface funcs + resource methods.
  for it in iface.items {
    match it {
      Func(f) => {
        let params : Array[(String, EncValType)] = []
        for p in f.params {
          params.push((p.0, lower_valtype_in_value(env, p.1)))
        }
        let result = if f.results.length() == 0 {
          None
        } else if f.results.length() == 1 {
          Some(lower_valtype_in_value(env, f.results[0].1))
        } else {
          raise WitError::Error(
            "unsupported WIT function results (expected 0 or 1 result): `" +
            f.name +
            "`",
          )
        }
        let ft = { is_async: f.is_async, params, result }
        let ft_idx = env.alloc_type(
          {
            let bb = ByteBuf::new()
            encode_functype(bb, ft)
            bb.to_bytes()
          },
        )
        env.decls.push(instancedecl_export_func(f.name, ft_idx))
      }
      Resource(r) =>
        for m in r.methods {
          let params : Array[(String, EncValType)] = []
          // Methods take an implicit borrowed `self`.
          let self_ty = lower_valtype_in_value(
            env,
            Apply("borrow", [Id(r.name)]),
          )
          params.push(("self", self_ty))
          for p in m.params {
            params.push((p.0, lower_valtype_in_value(env, p.1)))
          }
          let result = if m.results.length() == 0 {
            None
          } else if m.results.length() == 1 {
            Some(lower_valtype_in_value(env, m.results[0].1))
          } else {
            raise WitError::Error(
              "unsupported WIT method results (expected 0 or 1 result): `" +
              m.name +
              "`",
            )
          }
          let ft = { is_async: m.is_async, params, result }
          let ft_idx = env.alloc_type(
            {
              let bb = ByteBuf::new()
              encode_functype(bb, ft)
              bb.to_bytes()
            },
          )
          env.decls.push(
            instancedecl_export_func("[method]" + r.name + "." + m.name, ft_idx),
          )
        }
      _ => ()
    }
  }
  encode_instancetype(env.decls)
}

///|
fn encode_interface_instancetype_types_only(
  iface : Interface,
) -> Bytes raise WitError {
  // Only local type defs + resources; ignore `use` for now.
  let imported : Array[(String, Int, Bool)] = []
  // We can reuse the full encoder but omit functions by passing an interface copy?
  // Keep it simple: build a synthetic interface containing only type items.
  let items : Array[InterfaceItem] = []
  for it in iface.items {
    match it {
      TypeAlias(_)
      | Record(_)
      | Variant(_)
      | Flags(_)
      | Enum(_)
      | Resource(_) => items.push(it)
      _ => ()
    }
  }
  let iface2 : Interface = { name: iface.name, items }
  // The full encoder will still export resource methods; avoid by stripping methods.
  // Strip methods from resources.
  let items2 : Array[InterfaceItem] = []
  for it in iface2.items {
    match it {
      Resource(r) => items2.push(Resource({ name: r.name, methods: [] }))
      _ => items2.push(it)
    }
  }
  let iface3 : Interface = { name: iface.name, items: items2 }
  encode_interface_instancetype_full(iface3, imported)
}

///|
fn encode_componenttype_wrapper_for_interface(
  iface : Interface,
  pkg_key : String,
  pkg_name : String,
  pkg_version : String?,
  iface_map : Map[String, Interface],
) -> Bytes raise WitError {
  // Collect interface-level `use` dependencies.
  let deps : Map[String, Array[(String, String?)]] = {} // iface_key -> [(remote, local?)]
  for it in iface.items {
    match it {
      Use(u) => {
        let (pkg_key_opt, name, _) = split_use_path(u.path)
        let dep_key = match pkg_key_opt {
          Some(k) => k
          None => pkg_key
        }
        let iface_key = dep_key + "#" + name
        let list = deps.get(iface_key).unwrap_or([])
        for pair in u.names {
          list.push(pair)
        }
        deps.set(iface_key, list)
      }
      _ => ()
    }
  }
  let decls : Array[Bytes] = []
  let mut next_typeidx = 0
  let mut next_instanceidx = 0
  let imported_types : Array[(String, Int, Bool)] = []

  // Encode dependencies as imported instances and alias their type exports.
  for kv in deps.iter() {
    let (iface_key, names) = kv
    let dep_iface = iface_map
      .get(iface_key)
      .unwrap_or_else(fn() {
        raise WitError::Error("unknown interface `" + iface_key + "`")
      })
    let hash = find_last_code_unit(iface_key, 35) // '#'
    let dep_pkg_key = match hash {
      Some(i) => slice_ascii(iface_key, 0, i)
      None => iface_key
    }
    let dep_iface_name = match hash {
      Some(i) => slice_ascii(iface_key, i + 1, iface_key.length())
      None => dep_iface.name
    }
    let (dep_pkg_name, dep_ver) = split_pkg_key(dep_pkg_key)
    let dep_full = iface_full_name(dep_pkg_name, dep_iface_name, dep_ver)
    // type: instancetype signature (types only)
    let dep_inst_t = encode_interface_instancetype_types_only(dep_iface)
    decls.push(componentdecl_type(dep_inst_t))
    let dep_inst_typeidx = next_typeidx
    next_typeidx = next_typeidx + 1
    // import instance
    decls.push(componentdecl_import_instance(dep_full, dep_inst_typeidx))
    let dep_inst_idx = next_instanceidx
    next_instanceidx = next_instanceidx + 1
    // alias requested names
    for pair in names {
      let remote = pair.0
      let local_name = match pair.1 {
        Some(asn) => asn
        None => remote
      }
      decls.push(componentdecl_alias_instance_export_type(dep_inst_idx, remote))
      let outer_ti = next_typeidx
      next_typeidx = next_typeidx + 1
      // Determine if this is a resource in the dependency interface.
      let mut is_res = false
      for it2 in dep_iface.items {
        match it2 {
          Resource(r) => if r.name == remote { is_res = true }
          _ => ()
        }
      }
      imported_types.push((local_name, outer_ti, is_res))
    }
  }

  // type: this interface instancetype
  let inst = encode_interface_instancetype_full(iface, imported_types)
  decls.push(componentdecl_type(inst))
  let my_inst_typeidx = next_typeidx
  next_typeidx = next_typeidx + 1
  // export full iface name
  let full = iface_full_name(pkg_name, iface.name, pkg_version)
  decls.push(componentdecl_export_instance(full, my_inst_typeidx))
  encode_componenttype(decls)
}

///|
fn encode_componenttype_inner_for_world(
  buf : ByteBuf,
  world : World,
  cur_pkg_key : String,
  iface_map : Map[String, Interface],
) -> Unit raise WitError {
  // Keep the world encoding minimal for now (interfaces only). This is
  // sufficient for `wasm-tools component wit` to roundtrip WIT packages.
  let decls : Array[Bytes] = []

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
  let mut local_typeidx = 0
  for pair in pairs {
    let (is_import, _, iface, full) = pair
    // type instancetype
    let inst = encode_interface_instancetype_types_only(iface)
    decls.push(componentdecl_type(inst))
    // import/export instance
    decls.push(
      if is_import {
        componentdecl_import_instance(full, local_typeidx)
      } else {
        componentdecl_export_instance(full, local_typeidx)
      },
    )
    local_typeidx = local_typeidx + 1
  }
  buf.push_bytes(encode_componenttype(decls))
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
    let typedef = encode_componenttype_wrapper_for_interface(
      iface, root_key, root_pkg_name, root_pkg_ver, iface_map,
    )
    out.push_bytes(encode_section(7, encode_type_section_one(typedef)))
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
fn bytes_to_ascii(b : Bytes) -> String {
  let sb = StringBuilder::new()
  for i in 0..<b.length() {
    sb.write_char(b[i].to_int().unsafe_to_char())
  }
  sb.to_string()
}

///|
fn export_name_to_string(n : @component.ExportName) -> String {
  match n {
    Plain(b) => bytes_to_ascii(b)
    WithVersion(b, _vs) => bytes_to_ascii(b)
  }
}

///|
fn pp_primvaltype(p : @component.PrimValType) -> String {
  match p {
    Bool => "bool"
    S8 => "s8"
    U8 => "u8"
    S16 => "s16"
    U16 => "u16"
    S32 => "s32"
    U32 => "u32"
    S64 => "s64"
    U64 => "u64"
    F32 => "f32"
    F64 => "f64"
    Char => "char"
    String => "string"
    ErrorContext => "error-context"
  }
}

///|
fn pp_valtype(v : @component.ValType) -> String {
  match v {
    Prim(p) => pp_primvaltype(p)
    TypeIdx(i) => i.to_string()
  }
}

///|
fn pp_functype(sb : StringBuilder, ft : @component.FuncType) -> Unit {
  sb.write_string("(func")
  for p in ft.params {
    sb.write_string(" (param \"" + p.label + "\" " + pp_valtype(p.ty) + ")")
  }
  match ft.result {
    None => ()
    Some(r) => sb.write_string(" (result " + pp_valtype(r) + ")")
  }
  sb.write_string(")")
}

///|
fn pp_typedef(sb : StringBuilder, td : @component.TypeDef) -> Unit {
  match td {
    DefValType(p) => sb.write_string(pp_primvaltype(p))
    FuncType(ft) => pp_functype(sb, ft)
    List(t) => sb.write_string("(list " + pp_valtype(t) + ")")
    Tuple(ts) => {
      sb.write_string("(tuple")
      for t in ts {
        sb.write_string(" " + pp_valtype(t))
      }
      sb.write_string(")")
    }
    Option(t) => sb.write_string("(option " + pp_valtype(t) + ")")
    Result(ok, err) => {
      sb.write_string("(result")
      match ok {
        None => ()
        Some(v) => sb.write_string(" " + pp_valtype(v))
      }
      match err {
        None => ()
        Some(v) => sb.write_string(" (error " + pp_valtype(v) + ")")
      }
      sb.write_string(")")
    }
    Record(fields) => {
      sb.write_string("(record")
      for f in fields {
        sb.write_string(" (field \"" + f.label + "\" " + pp_valtype(f.ty) + ")")
      }
      sb.write_string(")")
    }
    Variant(cases) => {
      sb.write_string("(variant")
      for c in cases {
        match c.ty {
          None => sb.write_string(" (case \"" + c.label + "\")")
          Some(v) =>
            sb.write_string(" (case \"" + c.label + "\" " + pp_valtype(v) + ")")
        }
      }
      sb.write_string(")")
    }
    Flags(xs) => {
      sb.write_string("(flags")
      for x in xs {
        sb.write_string(" \"" + x + "\"")
      }
      sb.write_string(")")
    }
    Enum(xs) => {
      sb.write_string("(enum")
      for x in xs {
        sb.write_string(" \"" + x + "\"")
      }
      sb.write_string(")")
    }
    Own(ti) => sb.write_string("(own " + ti.to_string() + ")")
    Borrow(ti) => sb.write_string("(borrow " + ti.to_string() + ")")
    Future(t) =>
      match t {
        None => sb.write_string("(future)")
        Some(v) => sb.write_string("(future " + pp_valtype(v) + ")")
      }
    Stream(t) =>
      match t {
        None => sb.write_string("(stream)")
        Some(v) => sb.write_string("(stream " + pp_valtype(v) + ")")
      }
    ResourceType(_id, rep, _dtor, _kind) =>
      sb.write_string("(resource (rep 0x" + rep.to_string() + "))")
    InstanceTypeEmpty => sb.write_string("(instance)")
    InstanceType(decls) => {
      sb.write_string("(instance\n")
      for d in decls {
        pp_instancedecl(sb, "  ", d)
      }
      sb.write_string(")")
    }
    ComponentType(decls) => {
      sb.write_string("(component\n")
      for d in decls {
        pp_componentdecl(sb, "  ", d)
      }
      sb.write_string(")")
    }
  }
}

///|
fn pp_externdesc(sb : StringBuilder, desc : @component.ExternDesc) -> Unit {
  match desc {
    FuncType(ti) => sb.write_string("(func (type " + ti.to_string() + "))")
    Type(bound) =>
      match bound {
        @component.TypeBound::Eq(ti) =>
          sb.write_string("(type (eq " + ti.to_string() + "))")
        @component.TypeBound::SubResource =>
          sb.write_string("(type (sub resource))")
      }
    InstanceType(ti) =>
      sb.write_string("(instance (type " + ti.to_string() + "))")
    ComponentType(ti) =>
      sb.write_string("(component (type " + ti.to_string() + "))")
    Value(_vb) => sb.write_string("(value)")
    CoreModuleType(_ti) => sb.write_string("(core module)")
  }
}

///|
fn pp_componentdecl(
  sb : StringBuilder,
  indent : String,
  d : @component.ComponentDecl,
) -> Unit {
  sb.write_string(indent)
  match d {
    Type(td) => {
      sb.write_string("(type ")
      pp_typedef(sb, td)
      sb.write_string(")\n")
    }
    Import(name, desc) => {
      sb.write_string("(import \"" + name + "\" ")
      pp_externdesc(sb, desc)
      sb.write_string(")\n")
    }
    Export(name, desc) => {
      sb.write_string("(export \"" + name + "\" ")
      pp_externdesc(sb, desc)
      sb.write_string(")\n")
    }
    AliasInstanceExport(kind, inst, name) =>
      if kind == 0x03 {
        sb.write_string(
          "(alias export " + inst.to_string() + " \"" + name + "\" (type))\n",
        )
      } else {
        sb.write_string(
          "(; unsupported alias-export kind=" + kind.to_string() + " ;)\n",
        )
      }
    AliasOuter(kind, count, idx) =>
      if kind == 0x03 {
        sb.write_string(
          "(alias outer " +
          count.to_string() +
          " " +
          idx.to_string() +
          " (type))\n",
        )
      } else {
        sb.write_string(
          "(; unsupported alias-outer kind=" + kind.to_string() + " ;)\n",
        )
      }
    CoreType(_bytes) => sb.write_string("(; core type omitted ;)\n")
  }
}

///|
fn pp_instancedecl(
  sb : StringBuilder,
  indent : String,
  d : @component.InstanceDecl,
) -> Unit {
  sb.write_string(indent)
  match d {
    Type(td) => {
      sb.write_string("(type ")
      pp_typedef(sb, td)
      sb.write_string(")\n")
    }
    Export(name, desc) => {
      sb.write_string("(export \"" + name + "\" ")
      pp_externdesc(sb, desc)
      sb.write_string(")\n")
    }
    AliasOuter(kind, count, idx) =>
      if kind == 0x03 {
        sb.write_string(
          "(alias outer " +
          count.to_string() +
          " " +
          idx.to_string() +
          " (type))\n",
        )
      } else {
        sb.write_string(
          "(; unsupported alias-outer kind=" + kind.to_string() + " ;)\n",
        )
      }
    AliasInstanceExport(kind, inst, name) =>
      if kind == 0x03 {
        sb.write_string(
          "(alias export " + inst.to_string() + " \"" + name + "\" (type))\n",
        )
      } else {
        sb.write_string(
          "(; unsupported alias-export kind=" + kind.to_string() + " ;)\n",
        )
      }
    CoreType(_bytes) => sb.write_string("(; core type omitted ;)\n")
  }
}

///|
pub fn format_wit_component_wat(res : ResolveResult) -> String raise WitError {
  let bytes = encode_wit_component_wasm(res)
  let c = @component.parse_component(bytes) catch {
    e => raise WitError::Error("parsing encoded component: " + e.to_string())
  }
  let sb = StringBuilder::new()
  sb.write_string("(component\n")
  // Type section.
  let mut i = 0
  while i < c.types.length() {
    sb.write_string("  (type (;")
    sb.write_string(i.to_string())
    sb.write_string(";) ")
    pp_typedef(sb, c.types[i])
    sb.write_string(")\n")
    i = i + 1
  }
  // Export section (type exports for WIT package encoding).
  for e in c.exports {
    let name = export_name_to_string(e.name)
    match e.sortidx.sort {
      Type =>
        sb.write_string(
          "  (export \"" +
          name +
          "\" (type " +
          e.sortidx.idx.to_string() +
          "))\n",
        )
      _ =>
        sb.write_string(
          "  (; export \"" + name + "\" of non-type sort omitted ;)\n",
        )
    }
  }
  sb.write_string(")\n")
  sb.to_string()
}
