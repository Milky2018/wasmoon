///|
fn core_valtypes_for_component_valtype(
  ty : @component.ValType,
  type_table : Array[@component.TypeDef?],
) -> Array[@types.ValueType]? {
  // For now, we only model the "flat" ABI for scalar/composite values that can
  // be represented without linear memory. Types that require memory (strings,
  // lists, etc) return `None` and skip signature checks; those are still
  // validated structurally by canonical option checks.
  let visiting : Map[Int, Unit] = {}
  fn scalar_prim(p : @component.PrimValType) -> Array[@types.ValueType]? {
    match p {
      @component.PrimValType::Bool
      | @component.PrimValType::S8
      | @component.PrimValType::U8
      | @component.PrimValType::S16
      | @component.PrimValType::U16
      | @component.PrimValType::S32
      | @component.PrimValType::U32
      | @component.PrimValType::Char => Some([@types.ValueType::I32])
      @component.PrimValType::S64 | @component.PrimValType::U64 =>
        Some([@types.ValueType::I64])
      @component.PrimValType::F32 => Some([@types.ValueType::F32])
      @component.PrimValType::F64 => Some([@types.ValueType::F64])
      // Strings/results need canonical ABI memory rules.
      @component.PrimValType::String | @component.PrimValType::ErrorContext =>
        None
    }
  }

  fn join_flat(a : @types.ValueType, b : @types.ValueType) -> @types.ValueType {
    if a == b {
      return a
    }
    // The canonical ABI uses "join" to unify variant payloads with differing
    // shapes. Mixed integer/float representations fall back to integer bit
    // patterns (I32/I64) to preserve bits and allow masking.
    match (a, b) {
      (@types.ValueType::I64, _)
      | (_, @types.ValueType::I64)
      | (@types.ValueType::F64, _)
      | (_, @types.ValueType::F64) => @types.ValueType::I64
      (@types.ValueType::F32, @types.ValueType::I32)
      | (@types.ValueType::I32, @types.ValueType::F32) => @types.ValueType::I32
      (@types.ValueType::I32, _) | (_, @types.ValueType::I32) =>
        @types.ValueType::I32
      // Default to I64 for any other mixed case (conservative).
      _ => @types.ValueType::I64
    }
  }

  fn scalar_flat_valtype(vt : @component.ValType) -> Array[@types.ValueType]? {
    match vt {
      @component.ValType::Prim(p) => scalar_prim(p)
      @component.ValType::TypeIdx(idx) => {
        if idx < 0 || idx >= type_table.length() {
          return None
        }
        match visiting.get(idx) {
          Some(_) => None
          None => {
            visiting.set(idx, ())
            let res = match type_table[idx] {
              None => None
              Some(td) =>
                match td {
                  @component.TypeDef::DefValType(p) => scalar_prim(p)
                  @component.TypeDef::Tuple(tys) => {
                    let out : Array[@types.ValueType] = []
                    for t in tys {
                      match scalar_flat_valtype(t) {
                        Some(ts) =>
                          for x in ts {
                            out.push(x)
                            if out.length() > 16 {
                              return None
                            }
                          }
                        None => return None
                      }
                    }
                    Some(out)
                  }
                  @component.TypeDef::Record(fields) => {
                    let out : Array[@types.ValueType] = []
                    for f in fields {
                      match scalar_flat_valtype(f.ty) {
                        Some(ts) =>
                          for x in ts {
                            out.push(x)
                            if out.length() > 16 {
                              return None
                            }
                          }
                        None => return None
                      }
                    }
                    Some(out)
                  }
                  @component.TypeDef::Variant(cases) => {
                    let payloads : Array[Array[@types.ValueType]] = []
                    let mut max_len = 0
                    for c in cases {
                      let flat = match c.ty {
                        None => []
                        Some(t) =>
                          match scalar_flat_valtype(t) {
                            Some(ts) => ts
                            None => return None
                          }
                      }
                      if flat.length() > max_len {
                        max_len = flat.length()
                      }
                      payloads.push(flat)
                    }
                    let joined : Array[@types.ValueType] = []
                    for i in 0..<max_len {
                      let mut cur : @types.ValueType? = None
                      for p in payloads {
                        if i < p.length() {
                          cur = match cur {
                            None => Some(p[i])
                            Some(prev) => Some(join_flat(prev, p[i]))
                          }
                        }
                      }
                      match cur {
                        None => ()
                        Some(t) => joined.push(t)
                      }
                    }
                    if 1 + joined.length() > 16 {
                      None
                    } else {
                      Some([@types.ValueType::I32] + joined)
                    }
                  }
                  @component.TypeDef::Option(v) =>
                    match scalar_flat_valtype(v) {
                      Some(payload) =>
                        if 1 + payload.length() > 16 {
                          None
                        } else {
                          Some([@types.ValueType::I32] + payload)
                        }
                      None => None
                    }
                  @component.TypeDef::Result(ok, err) => {
                    let ok_flat = match ok {
                      None => []
                      Some(v) =>
                        match scalar_flat_valtype(v) {
                          Some(ts) => ts
                          None => return None
                        }
                    }
                    let err_flat = match err {
                      None => []
                      Some(v) =>
                        match scalar_flat_valtype(v) {
                          Some(ts) => ts
                          None => return None
                        }
                    }
                    let mut max_len = ok_flat.length()
                    if err_flat.length() > max_len {
                      max_len = err_flat.length()
                    }
                    let joined : Array[@types.ValueType] = []
                    for i in 0..<max_len {
                      let mut cur : @types.ValueType? = None
                      if i < ok_flat.length() {
                        cur = Some(ok_flat[i])
                      }
                      if i < err_flat.length() {
                        cur = match cur {
                          None => Some(err_flat[i])
                          Some(prev) => Some(join_flat(prev, err_flat[i]))
                        }
                      }
                      match cur {
                        None => ()
                        Some(t) => joined.push(t)
                      }
                    }
                    if 1 + joined.length() > 16 {
                      None
                    } else {
                      Some([@types.ValueType::I32] + joined)
                    }
                  }
                  @component.TypeDef::Flags(labels) =>
                    if labels.length() <= 32 {
                      Some([@types.ValueType::I32])
                    } else if labels.length() <= 64 {
                      Some([@types.ValueType::I64])
                    } else {
                      None
                    }
                  @component.TypeDef::Enum(_labels) =>
                    Some([@types.ValueType::I32])
                  @component.TypeDef::Own(_) | @component.TypeDef::Borrow(_) =>
                    Some([@types.ValueType::I32])
                  @component.TypeDef::ResourceType(_, _, _, _) =>
                    Some([@types.ValueType::I32])
                  @component.TypeDef::Future(_)
                  | @component.TypeDef::Stream(_) =>
                    Some([@types.ValueType::I32])
                  // Lists/strings/resources with non-scalar reps require memory.
                  _ => None
                }
            }
            visiting.remove(idx) |> ignore
            res
          }
        }
      }
    }
  }

  scalar_flat_valtype(ty)
}

///|
fn core_functype_for_component_functype(
  ft : @component.FuncType,
  type_table : Array[@component.TypeDef?],
) -> @types.FuncType? {
  let params : Array[@types.ValueType] = []
  for p in ft.params {
    match core_valtypes_for_component_valtype(p.ty, type_table) {
      Some(ts) =>
        for t in ts {
          params.push(t)
          if params.length() > 16 {
            // Indirect parameters: canonical ABI requires memory.
            return None
          }
        }
      None => return None
    }
  }
  let results : Array[@types.ValueType] = []
  match ft.result {
    None => ()
    Some(r) =>
      match core_valtypes_for_component_valtype(r, type_table) {
        Some(ts) =>
          for t in ts {
            results.push(t)
          }
        None => return None
      }
  }
  // Indirect/multi-value results go through memory (retptr), not direct core results.
  if results.length() > 1 {
    return None
  }
  Some({ params, results })
}

///|
fn validate_canon(
  c : @component.Canon,
  type_table : Array[@component.TypeDef?],
  local_resource_types : Array[Bool],
  type_bound : Int,
  core_memory_types : Array[@types.MemoryType?],
  core_func_types : Array[@types.FuncType?],
  func_types : Array[@component.FuncType?],
) -> Unit raise ComponentValidationError {
  match c {
    Lift(core_func_idx, opts, tyidx) => {
      validate_canon_opts(opts)
      match canon_memory_idx(opts) {
        Some(mem_idx) =>
          if mem_idx < 0 || mem_idx >= core_memory_types.length() {
            raise InvalidCoreMemoryIndex(mem_idx)
          } else {
            match core_memory_types[mem_idx] {
              Some(mt) =>
                if mt.is_memory64 {
                  raise CanonMemoryNot32Bit(mem_idx)
                }
              None => ()
            }
          }
        None => ()
      }
      match canon_realloc_idx(opts) {
        Some(idx) =>
          if idx < 0 || idx >= core_func_types.length() {
            raise InvalidCoreFuncIndex(idx)
          }
        None => ()
      }
      match canon_post_return_idx(opts) {
        Some(idx) =>
          if idx < 0 || idx >= core_func_types.length() {
            raise InvalidCoreFuncIndex(idx)
          }
        None => ()
      }
      if core_func_idx < 0 || core_func_idx >= core_func_types.length() {
        raise InvalidCoreFuncIndex(core_func_idx)
      }
      check_typeidx(tyidx, type_bound)
      let td = type_table[tyidx]
      match td {
        Some(@component.TypeDef::FuncType(ft)) => {
          match canon_realloc_idx(opts) {
            Some(idx) =>
              match core_func_types[idx] {
                Some(core_ft) => {
                  let expected : @types.FuncType = {
                    params: [
                      @types.ValueType::I32,
                      @types.ValueType::I32,
                      @types.ValueType::I32,
                      @types.ValueType::I32,
                    ],
                    results: [@types.ValueType::I32],
                  }
                  if core_ft != expected {
                    raise CanonCoreFuncTypeMismatch(
                      "canonical option `realloc` uses a core function with an incorrect signature",
                    )
                  }
                }
                None => ()
              }
            None => ()
          }
          match canon_post_return_idx(opts) {
            Some(idx) =>
              match (core_func_types[core_func_idx], core_func_types[idx]) {
                (Some(lifted_ft), Some(post_ft)) => {
                  let expected : @types.FuncType = {
                    params: lifted_ft.results,
                    results: [],
                  }
                  if post_ft != expected {
                    raise CanonCoreFuncTypeMismatch(
                      "canonical option `post-return` uses a core function with an incorrect signature",
                    )
                  }
                }
                _ => ()
              }
            None => ()
          }
          if functype_needs_memory(ft, type_table) {
            if !canon_has_memory(opts) {
              raise MissingCanonOption("memory")
            }
          }
          if functype_needs_realloc_for_lift(ft, type_table) {
            if !canon_has_realloc(opts) {
              raise MissingCanonOption("realloc")
            }
          }
          // Async-lifted functions use a callback/event-code ABI and do not
          // match the direct lowering signature.
          if !canon_has_async(opts) {
            match
              (
                core_func_types[core_func_idx],
                core_functype_for_component_functype(ft, type_table),
              ) {
              (Some(core_ft), Some(expected_core_ft)) =>
                if core_ft != expected_core_ft {
                  raise CanonCoreFuncTypeMismatch(
                    "canon lift core signature mismatch",
                  )
                }
              _ => ()
            }
          }
        }
        None => ()
        _ => raise CanonExpectedFuncType(tyidx)
      }
    }
    Lower(func_idx, opts) => {
      validate_canon_opts(opts)
      if canon_has_post_return(opts) {
        raise CanonOptionNotAllowed("post-return")
      }
      match canon_memory_idx(opts) {
        Some(mem_idx) =>
          if mem_idx < 0 || mem_idx >= core_memory_types.length() {
            raise InvalidCoreMemoryIndex(mem_idx)
          } else {
            match core_memory_types[mem_idx] {
              Some(mt) =>
                if mt.is_memory64 {
                  raise CanonMemoryNot32Bit(mem_idx)
                }
              None => ()
            }
          }
        None => ()
      }
      match canon_realloc_idx(opts) {
        Some(idx) =>
          if idx < 0 || idx >= core_func_types.length() {
            raise InvalidCoreFuncIndex(idx)
          }
        None => ()
      }
      if func_idx < 0 || func_idx >= func_types.length() {
        raise InvalidFuncIndex(func_idx)
      }
      match func_types[func_idx] {
        Some(ft) => {
          match canon_realloc_idx(opts) {
            Some(idx) =>
              match core_func_types[idx] {
                Some(core_ft) => {
                  let expected : @types.FuncType = {
                    params: [
                      @types.ValueType::I32,
                      @types.ValueType::I32,
                      @types.ValueType::I32,
                      @types.ValueType::I32,
                    ],
                    results: [@types.ValueType::I32],
                  }
                  if core_ft != expected {
                    raise CanonCoreFuncTypeMismatch(
                      "canonical option `realloc` uses a core function with an incorrect signature",
                    )
                  }
                }
                None => ()
              }
            None => ()
          }
          if functype_needs_memory(ft, type_table) && !canon_has_memory(opts) {
            raise MissingCanonOption("memory")
          }
          if functype_needs_realloc_for_lower(ft, type_table) &&
            !canon_has_realloc(opts) {
            raise MissingCanonOption("realloc")
          }
        }
        None => ()
      }
    }
    ResourceNew(tyidx) => {
      if tyidx < 0 || tyidx >= type_bound {
        raise SectionParseError(8, "type index out of bounds")
      }
      // `resource.new` requires a resource type defined in this concrete component.
      if tyidx < 0 || tyidx >= type_table.length() {
        raise SectionParseError(8, "type index out of bounds")
      }
      if tyidx < 0 ||
        tyidx >= local_resource_types.length() ||
        !local_resource_types[tyidx] {
        raise SectionParseError(8, "not a local resource")
      }
      match type_table[tyidx] {
        Some(@component.TypeDef::ResourceType(_, _, _, _)) => ()
        _ => raise SectionParseError(8, "not a resource type")
      }
    }
    ResourceRep(tyidx) => {
      if tyidx < 0 || tyidx >= type_bound {
        raise SectionParseError(8, "type index out of bounds")
      }
      if tyidx < 0 || tyidx >= type_table.length() {
        raise SectionParseError(8, "type index out of bounds")
      }
      if tyidx < 0 ||
        tyidx >= local_resource_types.length() ||
        !local_resource_types[tyidx] {
        raise SectionParseError(8, "not a local resource")
      }
      match type_table[tyidx] {
        Some(@component.TypeDef::ResourceType(_, _, _, _)) => ()
        _ => raise SectionParseError(8, "not a resource type")
      }
    }
    ResourceDrop(tyidx) => {
      if tyidx < 0 || tyidx >= type_bound {
        raise SectionParseError(8, "type index out of bounds")
      }
      if tyidx < 0 || tyidx >= type_table.length() {
        raise SectionParseError(8, "type index out of bounds")
      }
      // `resource.drop` is allowed for both local resource types and imported
      // `(sub resource)` types (which we currently model as None).
      match type_table[tyidx] {
        Some(@component.TypeDef::ResourceType(_, _, _, _)) => ()
        None => ()
        Some(_) => raise SectionParseError(8, "not a resource type")
      }
    }
    _ => ()
  }
}

///|
fn valtype_refers_to_resource(
  ty : @component.ValType,
  type_table : Array[@component.TypeDef?],
  visiting : Map[Int, Int],
) -> Bool {
  match ty {
    @component.ValType::Prim(_) => false
    @component.ValType::TypeIdx(idx) =>
      if idx < 0 || idx >= type_table.length() {
        false
      } else if visiting.get(idx) is Some(_) {
        false
      } else {
        visiting.set(idx, 1)
        let any = match type_table[idx] {
          None => false
          Some(td) => typedef_refers_to_resource(td, type_table, visiting)
        }
        visiting.remove(idx) |> ignore
        any
      }
  }
}

///|
fn externdesc_refers_to_resource(
  desc : @component.ExternDesc,
  type_table : Array[@component.TypeDef?],
  visiting : Map[Int, Int],
) -> Bool {
  match desc {
    @component.ExternDesc::Type(b) =>
      match b {
        @component.TypeBound::Eq(idx) =>
          valtype_refers_to_resource(
            @component.ValType::TypeIdx(idx),
            type_table,
            visiting,
          )
        @component.TypeBound::SubResource => true
      }
    @component.ExternDesc::FuncType(tyidx) =>
      if tyidx < 0 || tyidx >= type_table.length() {
        false
      } else {
        match type_table[tyidx] {
          Some(@component.TypeDef::FuncType(ft)) => {
            let mut any = false
            for p in ft.params {
              if valtype_refers_to_resource(p.ty, type_table, visiting) {
                any = true
                break
              }
            }
            if !any {
              match ft.result {
                None => ()
                Some(r) =>
                  if valtype_refers_to_resource(r, type_table, visiting) {
                    any = true
                  }
              }
            }
            any
          }
          _ => false
        }
      }
    @component.ExternDesc::InstanceType(tyidx) =>
      if tyidx < 0 || tyidx >= type_table.length() {
        false
      } else {
        match type_table[tyidx] {
          Some(@component.TypeDef::InstanceType(decls)) => {
            let mut any = false
            for d in decls {
              match d {
                @component.InstanceDecl::Type(td) =>
                  if typedef_refers_to_resource(td, type_table, visiting) {
                    any = true
                    break
                  }
                @component.InstanceDecl::Export(_name, desc) =>
                  if externdesc_refers_to_resource(desc, type_table, visiting) {
                    any = true
                    break
                  }
                _ => ()
              }
            }
            any
          }
          _ => false
        }
      }
    @component.ExternDesc::ComponentType(tyidx) =>
      if tyidx < 0 || tyidx >= type_table.length() {
        false
      } else {
        match type_table[tyidx] {
          Some(@component.TypeDef::ComponentType(decls)) => {
            let mut any = false
            for d in decls {
              match d {
                @component.ComponentDecl::Type(td) =>
                  if typedef_refers_to_resource(td, type_table, visiting) {
                    any = true
                    break
                  }
                @component.ComponentDecl::Import(_name, desc) =>
                  if externdesc_refers_to_resource(desc, type_table, visiting) {
                    any = true
                    break
                  }
                @component.ComponentDecl::Export(_name, desc) =>
                  if externdesc_refers_to_resource(desc, type_table, visiting) {
                    any = true
                    break
                  }
                _ => ()
              }
            }
            any
          }
          _ => false
        }
      }
    _ => false
  }
}

///|
fn typedef_refers_to_resource(
  td : @component.TypeDef,
  type_table : Array[@component.TypeDef?],
  visiting : Map[Int, Int],
) -> Bool {
  match td {
    @component.TypeDef::ResourceType(_, _, _, _) => true
    @component.TypeDef::Own(_) | @component.TypeDef::Borrow(_) => true
    @component.TypeDef::DefValType(_) => false
    @component.TypeDef::Tuple(tys) => {
      let mut any = false
      for t in tys {
        if valtype_refers_to_resource(t, type_table, visiting) {
          any = true
          break
        }
      }
      any
    }
    @component.TypeDef::Record(fields) => {
      let mut any = false
      for f in fields {
        if valtype_refers_to_resource(f.ty, type_table, visiting) {
          any = true
          break
        }
      }
      any
    }
    @component.TypeDef::Variant(cases) => {
      let mut any = false
      for c in cases {
        match c.ty {
          None => ()
          Some(t) =>
            if valtype_refers_to_resource(t, type_table, visiting) {
              any = true
              break
            }
        }
      }
      any
    }
    @component.TypeDef::Option(v) =>
      valtype_refers_to_resource(v, type_table, visiting)
    @component.TypeDef::Result(ok, err) => {
      let ok_any = match ok {
        None => false
        Some(v) => valtype_refers_to_resource(v, type_table, visiting)
      }
      let err_any = match err {
        None => false
        Some(v) => valtype_refers_to_resource(v, type_table, visiting)
      }
      ok_any || err_any
    }
    @component.TypeDef::List(v) =>
      valtype_refers_to_resource(v, type_table, visiting)
    @component.TypeDef::Stream(v) | @component.TypeDef::Future(v) =>
      match v {
        None => false
        Some(inner) => valtype_refers_to_resource(inner, type_table, visiting)
      }
    @component.TypeDef::FuncType(ft) => {
      let mut any = false
      for p in ft.params {
        if valtype_refers_to_resource(p.ty, type_table, visiting) {
          any = true
          break
        }
      }
      if !any {
        match ft.result {
          None => ()
          Some(r) =>
            if valtype_refers_to_resource(r, type_table, visiting) {
              any = true
            }
        }
      }
      any
    }
    @component.TypeDef::ComponentType(decls) => {
      let mut any = false
      for d in decls {
        match d {
          @component.ComponentDecl::Type(td2) =>
            if typedef_refers_to_resource(td2, type_table, visiting) {
              any = true
              break
            }
          @component.ComponentDecl::Import(_name, desc) =>
            if externdesc_refers_to_resource(desc, type_table, visiting) {
              any = true
              break
            }
          @component.ComponentDecl::Export(_name, desc) =>
            if externdesc_refers_to_resource(desc, type_table, visiting) {
              any = true
              break
            }
          _ => ()
        }
      }
      any
    }
    @component.TypeDef::InstanceType(decls) => {
      let mut any = false
      for d in decls {
        match d {
          @component.InstanceDecl::Type(td2) =>
            if typedef_refers_to_resource(td2, type_table, visiting) {
              any = true
              break
            }
          @component.InstanceDecl::Export(_name, desc) =>
            if externdesc_refers_to_resource(desc, type_table, visiting) {
              any = true
              break
            }
          _ => ()
        }
      }
      any
    }
    _ => false
  }
}

///|
/// Compute a conservative "effective type size" for component/instance types.
///
/// This is a lightweight check used to reject pathological type graphs that
/// explode when expanded (wasm-tools' `very-nested.wast`). The component-spec
/// limit is 100_000.
fn clamp_type_size(size : Int) -> Int {
  if size > 100000 {
    100001
  } else {
    size
  }
}

///|
fn add_type_size(acc : Int, delta : Int) -> Int {
  if acc > 100000 {
    return 100001
  }
  let d = clamp_type_size(delta)
  let sum = acc + d
  clamp_type_size(sum)
}

///|
fn local_type_size_of(idx : Int, local_sizes : Array[Int]) -> Int {
  if idx < 0 || idx >= local_sizes.length() {
    return 1
  }
  local_sizes[idx]
}

///|
fn externdesc_type_size(
  desc : @component.ExternDesc,
  local_sizes : Array[Int],
) -> Int {
  match desc {
    @component.ExternDesc::ComponentType(tyidx) =>
      local_type_size_of(tyidx, local_sizes)
    @component.ExternDesc::InstanceType(tyidx) =>
      local_type_size_of(tyidx, local_sizes)
    @component.ExternDesc::FuncType(_) => 1
    @component.ExternDesc::CoreModuleType(_) => 1
    @component.ExternDesc::Type(_) => 1
    @component.ExternDesc::Value(_) => 1
  }
}

///|
fn effective_typedef_size(
  td : @component.TypeDef,
  outer_sizes : Array[Int],
) -> Int {
  fn valtype_size(ty : @component.ValType) -> Int {
    match ty {
      @component.ValType::Prim(_) => 1
      @component.ValType::TypeIdx(idx) => local_type_size_of(idx, outer_sizes)
    }
  }

  match td {
    @component.TypeDef::ComponentType(decls) => {
      let local_sizes : Array[Int] = []
      let mut total = 1
      for d in decls {
        match d {
          @component.ComponentDecl::Type(t) =>
            local_sizes.push(effective_typedef_size(t, outer_sizes))
          @component.ComponentDecl::AliasOuter(kind, count, idx) =>
            if kind == 0x03 {
              let s = if count == 1 && idx >= 0 && idx < outer_sizes.length() {
                outer_sizes[idx]
              } else {
                1
              }
              local_sizes.push(s)
            } else {
              ()
            }
          @component.ComponentDecl::AliasInstanceExport(kind, _inst, _name) =>
            if kind == 0x03 {
              local_sizes.push(1)
            } else {
              ()
            }
          @component.ComponentDecl::Import(_name, desc)
          | @component.ComponentDecl::Export(_name, desc) => {
            total = add_type_size(
              total,
              externdesc_type_size(desc, local_sizes),
            )
            // Importing/exporting a type introduces a fresh local type index.
            if desc is @component.ExternDesc::Type(_) {
              local_sizes.push(1)
            }
          }
          @component.ComponentDecl::CoreType(_) => ()
        }
        if total > 100000 {
          return 100001
        }
      }
      total
    }
    @component.TypeDef::InstanceType(decls) => {
      let local_sizes : Array[Int] = []
      let mut total = 1
      for d in decls {
        match d {
          @component.InstanceDecl::Type(t) =>
            local_sizes.push(effective_typedef_size(t, outer_sizes))
          @component.InstanceDecl::AliasOuter(kind, count, idx) =>
            if kind == 0x03 {
              let s = if count == 1 && idx >= 0 && idx < outer_sizes.length() {
                outer_sizes[idx]
              } else {
                1
              }
              local_sizes.push(s)
            } else {
              ()
            }
          @component.InstanceDecl::AliasInstanceExport(kind, _inst, _name) =>
            if kind == 0x03 {
              local_sizes.push(1)
            } else {
              ()
            }
          @component.InstanceDecl::Export(_name, desc) => {
            total = add_type_size(
              total,
              externdesc_type_size(desc, local_sizes),
            )
            if desc is @component.ExternDesc::Type(_) {
              local_sizes.push(1)
            }
          }
          @component.InstanceDecl::CoreType(_) => ()
        }
        if total > 100000 {
          return 100001
        }
      }
      total
    }
    @component.TypeDef::DefValType(_) => 1
    @component.TypeDef::FuncType(ft) => {
      let mut total = 1
      for p in ft.params {
        total = add_type_size(total, valtype_size(p.ty))
        if total > 100000 {
          return 100001
        }
      }
      match ft.result {
        Some(r) => add_type_size(total, valtype_size(r))
        None => total
      }
    }
    @component.TypeDef::Tuple(tys) => {
      let mut total = 1
      for t in tys {
        total = add_type_size(total, valtype_size(t))
        if total > 100000 {
          return 100001
        }
      }
      total
    }
    @component.TypeDef::Record(fields) => {
      let mut total = 1
      for f in fields {
        total = add_type_size(total, valtype_size(f.ty))
        if total > 100000 {
          return 100001
        }
      }
      total
    }
    @component.TypeDef::Variant(cases) => {
      let mut total = 1
      for c in cases {
        match c.ty {
          Some(t) => total = add_type_size(total, valtype_size(t))
          None => ()
        }
        if total > 100000 {
          return 100001
        }
      }
      total
    }
    @component.TypeDef::Option(v) => add_type_size(1, valtype_size(v))
    @component.TypeDef::Result(ok, err) => {
      let mut total = 1
      match ok {
        Some(v) => total = add_type_size(total, valtype_size(v))
        None => ()
      }
      match err {
        Some(v) => total = add_type_size(total, valtype_size(v))
        None => ()
      }
      total
    }
    @component.TypeDef::List(v) => add_type_size(1, valtype_size(v))
    @component.TypeDef::Flags(labels) => add_type_size(1, labels.length())
    @component.TypeDef::Enum(labels) => add_type_size(1, labels.length())
    _ => 1
  }
}
