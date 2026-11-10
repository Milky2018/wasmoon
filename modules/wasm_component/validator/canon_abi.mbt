///|
fn core_valtypes_for_component_valtype(
  ty : @component.ValType,
  type_table : Array[@component.TypeDef?],
) -> Array[@types.ValueType]? {
  match @component.canonical_abi_plan(ty, type_table, false, max_flat=17) {
    Some(plan) => if plan.contains_memory { None } else { Some(plan.flat) }
    None => None
  }
}

///|
fn core_functype_for_task_return(
  result : @component.ValType?,
  type_table : Array[@component.TypeDef?],
  pointer_type : @types.ValueType,
) -> @types.FuncType? {
  let params : Array[@types.ValueType] = []
  match result {
    None => ()
    Some(vt) =>
      match
        @component.canonical_flat_types(
          vt,
          type_table,
          pointer_type,
          max_flat=17,
        ) {
        Some(ts) =>
          if ts.length() > 16 {
            params.push(pointer_type)
          } else {
            for t in ts {
              params.push(t)
            }
          }
        None => return None
      }
  }
  Some({ params: ReadOnlyArray::from_array(params), results: [], })
}

///|
fn core_functype_for_canon(
  c : @component.Canon,
  type_table : Array[@component.TypeDef?],
  core_memory_types : Array[@types.MemoryType?],
) -> @types.FuncType? {
  match c {
    BackpressureInc | BackpressureDec | TaskCancel =>
      Some({ params: [], results: [], })
    TaskReturn(result, opts) =>
      core_functype_for_task_return(
        result,
        type_table,
        canon_address_type(opts, core_memory_types),
      )
    WaitableSetNew => Some({ params: [], results: [I32], })
    WaitableSetWait(_, _) | WaitableSetPoll(_, _) =>
      Some({ params: [I32, I32], results: [I32], })
    WaitableSetDrop => Some({ params: [I32], results: [], })
    WaitableJoin => Some({ params: [I32, I32], results: [], })
    SubtaskDrop => Some({ params: [I32], results: [], })
    SubtaskCancel(_) => Some({ params: [I32], results: [I32], })
    ThreadYield(_) => Some({ params: [], results: [I32], })
    ThreadSuspendThenResume(_)
    | ThreadYieldThenResume(_)
    | ThreadSuspendThenPromote(_)
    | ThreadYieldThenPromote(_) => Some({ params: [I32], results: [I32], })
    ContextGet(vt, _) => Some({ params: [], results: [vt], })
    ContextSet(vt, _) => Some({ params: [vt], results: [], })
    _ => None
  }
}

///|
fn canon_address_type(
  opts : Array[@component.CanonOpt],
  core_memory_types : Array[@types.MemoryType?],
) -> @types.ValueType {
  for opt in opts {
    if opt is Memory(idx) {
      return core_memory_address_type(Some(idx), core_memory_types)
    }
  }
  I32
}

///|
fn core_memory_address_type(
  memory : Int32?,
  core_memory_types : Array[@types.MemoryType?],
) -> @types.ValueType {
  if memory is Some(idx) && core_memory_types[idx] is Some(mt) && mt.is_memory64 {
    I64
  } else {
    I32
  }
}

///|
priv struct CheckedCanonOptions {
  memory : Int32?
  realloc : Int32?
  post_return : Int32?
  is_async : Bool
}

///|
fn check_canon_options(
  opts : Array[@component.CanonOpt],
) -> CheckedCanonOptions raise ComponentValidationError {
  let mut seen = 0
  let mut memory = None
  let mut realloc = None
  let mut post_return = None
  let mut is_async = false
  for opt in opts {
    let (kind, name) = match opt {
      StringEncoding(_) => (0, "string-encoding")
      Memory(idx) => {
        memory = Some(idx)
        (1, "memory")
      }
      Realloc(idx) => {
        realloc = Some(idx)
        (2, "realloc")
      }
      PostReturn(idx) => {
        post_return = Some(idx)
        (3, "post-return")
      }
      CoreType(_) => (4, "core-type")
      Gc => (5, "gc")
      Callback(_) => (6, "callback")
      Async => {
        is_async = true
        (7, "async")
      }
    }
    let bit = 1 << kind
    if (seen & bit) != 0 {
      raise DuplicateCanonOption(name)
    }
    seen = seen | bit
  }
  { memory, realloc, post_return, is_async, }
}

///|
fn CheckedCanonOptions::validate_indices(
  self : CheckedCanonOptions,
  memory_count : Int32,
  function_count : Int32,
) -> Unit raise ComponentValidationError {
  if self.memory is Some(idx) && (idx < 0 || idx >= memory_count) {
    raise InvalidCoreMemoryIndex(idx)
  }
  if self.realloc is Some(idx) && (idx < 0 || idx >= function_count) {
    raise InvalidCoreFuncIndex(idx)
  }
  if self.post_return is Some(idx) && (idx < 0 || idx >= function_count) {
    raise InvalidCoreFuncIndex(idx)
  }
}

///|
fn CheckedCanonOptions::validate_realloc(
  self : CheckedCanonOptions,
  core_memory_types : Array[@types.MemoryType?],
  core_func_types : Array[@types.FuncType?],
) -> Unit raise ComponentValidationError {
  if self.realloc is Some(idx) {
    guard self.memory is Some(_) else { raise MissingCanonOption("memory") }
    if core_func_types[idx] is Some(core_ft) {
      let addr = core_memory_address_type(self.memory, core_memory_types)
      let expected : @types.FuncType = {
        params: [addr, addr, addr, addr],
        results: [addr],
      }
      if core_ft != expected {
        raise CanonCoreFuncTypeMismatch(
          "canonical option `realloc` uses a core function with an incorrect signature",
        )
      }
    }
  }
}

///|
fn validate_canon(
  c : @component.Canon,
  type_table : Array[@component.TypeDef?],
  local_resource_types : Array[Bool],
  type_bound : Int32,
  core_memory_types : Array[@types.MemoryType?],
  core_func_types : Array[@types.FuncType?],
  func_types : Array[@component.FuncType?],
) -> Unit raise ComponentValidationError {
  match c {
    Lift(core_func_idx, opts, tyidx) => {
      let options = check_canon_options(opts)
      options.validate_indices(
        core_memory_types.length(),
        core_func_types.length(),
      )
      if core_func_idx < 0 || core_func_idx >= core_func_types.length() {
        raise InvalidCoreFuncIndex(core_func_idx)
      }
      check_typeidx(tyidx, type_bound)
      let td = type_table[tyidx]
      match td {
        Some(FuncType(ft)) => {
          if options.is_async && !ft.is_async {
            raise CanonAsyncTypeMismatch(tyidx)
          }
          options.validate_realloc(core_memory_types, core_func_types)
          match options.post_return {
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
          let needs_memory = if options.is_async {
            functype_async_lift_needs_memory(ft, type_table)
          } else {
            functype_needs_memory(ft, type_table)
          }
          if needs_memory && options.memory is None {
            raise MissingCanonOption("memory")
          }
          if functype_needs_realloc_for_lift(ft, type_table) &&
            options.realloc is None {
            raise MissingCanonOption("realloc")
          }
          // Async-lifted functions use a callback/event-code ABI and do not
          // match the direct lowering signature.
          if !options.is_async {
            match
              (
                core_func_types[core_func_idx],
                @component.canonical_lift_core_func_type(
                  ft,
                  type_table,
                  core_memory_address_type(options.memory, core_memory_types),
                ),
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
      let options = check_canon_options(opts)
      if options.post_return is Some(_) {
        raise CanonOptionNotAllowed("post-return")
      }
      options.validate_indices(
        core_memory_types.length(),
        core_func_types.length(),
      )
      if func_idx < 0 || func_idx >= func_types.length() {
        raise InvalidFuncIndex(func_idx)
      }
      match func_types[func_idx] {
        Some(ft) => {
          if options.is_async && !ft.is_async {
            raise CanonAsyncTypeMismatch(func_idx)
          }
          options.validate_realloc(core_memory_types, core_func_types)
          if functype_needs_memory(ft, type_table) && options.memory is None {
            raise MissingCanonOption("memory")
          }
          if functype_needs_realloc_for_lower(ft, type_table) &&
            options.realloc is None {
            raise MissingCanonOption("realloc")
          }
        }
        None => ()
      }
    }
    ResourceNew(tyidx) | ResourceRep(tyidx) => {
      if tyidx < 0 || tyidx >= type_bound {
        raise SectionParseError(8, "type index out of bounds")
      }
      // These operations require a resource defined in this concrete component.
      if tyidx < 0 || tyidx >= type_table.length() {
        raise SectionParseError(8, "type index out of bounds")
      }
      if tyidx < 0 ||
        tyidx >= local_resource_types.length() ||
        !local_resource_types[tyidx] {
        raise SectionParseError(8, "not a local resource")
      }
      match type_table[tyidx] {
        Some(ResourceType(_, _, _, _)) => ()
        _ => raise SectionParseError(8, "not a resource type")
      }
    }
    ResourceDrop(tyidx) => {
      if tyidx < 0 || tyidx >= type_bound || tyidx >= type_table.length() {
        raise SectionParseError(8, "type index out of bounds")
      }
      // `resource.drop` is allowed for both local resource types and imported
      // `(sub resource)` types (which we currently model as None).
      match type_table[tyidx] {
        Some(ResourceType(_, _, _, _)) => ()
        None => ()
        Some(_) => raise SectionParseError(8, "not a resource type")
      }
    }
    TaskReturn(result, opts) => {
      let options = check_canon_options(opts)
      if result is Some(ty) {
        validate_valtype(ty, type_table)
      }
      if options.memory is Some(memory) {
        if memory < 0 || memory >= core_memory_types.length() {
          raise InvalidCoreMemoryIndex(memory)
        }
      } else if functype_async_lift_needs_memory(
          { is_async: true, params: [], result, },
          type_table,
        ) {
        raise MissingCanonOption("memory")
      }
      for opt in opts {
        match opt {
          Async => raise CanonOptionNotAllowed("async")
          Callback(_) => raise CanonOptionNotAllowed("callback")
          PostReturn(_) => raise CanonOptionNotAllowed("post-return")
          Realloc(_) => raise CanonOptionNotAllowed("realloc")
          _ => ()
        }
      }
    }
    _ => ()
  }
}

///|
fn valtype_refers_to_resource(
  ty : @component.ValType,
  type_table : Array[@component.TypeDef?],
  visiting : Map[Int32, Int32],
) -> Bool {
  match ty {
    Prim(_) => false
    TypeIdx(idx) =>
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
  visiting : Map[Int32, Int32],
) -> Bool {
  match desc {
    Type(b) =>
      match b {
        Eq(idx) =>
          valtype_refers_to_resource(TypeIdx(idx), type_table, visiting)
        SubResource => true
      }
    FuncType(tyidx) =>
      if tyidx < 0 || tyidx >= type_table.length() {
        false
      } else {
        match type_table[tyidx] {
          Some(FuncType(ft)) => {
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
    InstanceType(tyidx) =>
      if tyidx < 0 || tyidx >= type_table.length() {
        false
      } else {
        match type_table[tyidx] {
          Some(InstanceType(decls)) => {
            let mut any = false
            for d in decls {
              match d {
                Type(td) =>
                  if typedef_refers_to_resource(td, type_table, visiting) {
                    any = true
                    break
                  }
                Export(_name, _attributes, desc) =>
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
    ComponentType(tyidx) =>
      if tyidx < 0 || tyidx >= type_table.length() {
        false
      } else {
        match type_table[tyidx] {
          Some(ComponentType(decls)) => {
            let mut any = false
            for d in decls {
              match d {
                Type(td) =>
                  if typedef_refers_to_resource(td, type_table, visiting) {
                    any = true
                    break
                  }
                Import(_name, _attributes, desc) =>
                  if externdesc_refers_to_resource(desc, type_table, visiting) {
                    any = true
                    break
                  }
                Export(_name, _attributes, desc) =>
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
  visiting : Map[Int32, Int32],
) -> Bool {
  match td {
    ResourceType(_, _, _, _) => true
    Own(_) | Borrow(_) => true
    DefValType(_) => false
    Tuple(tys) => {
      let mut any = false
      for t in tys {
        if valtype_refers_to_resource(t, type_table, visiting) {
          any = true
          break
        }
      }
      any
    }
    Record(fields) => {
      let mut any = false
      for f in fields {
        if valtype_refers_to_resource(f.ty, type_table, visiting) {
          any = true
          break
        }
      }
      any
    }
    Variant(cases) => {
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
    Option(v) => valtype_refers_to_resource(v, type_table, visiting)
    Result(ok, err) => {
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
    List(v) | FixedList(v, _) =>
      valtype_refers_to_resource(v, type_table, visiting)
    Stream(v) | Future(v) =>
      match v {
        None => false
        Some(inner) => valtype_refers_to_resource(inner, type_table, visiting)
      }
    FuncType(ft) => {
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
    ComponentType(decls) => {
      let mut any = false
      for d in decls {
        match d {
          Type(td2) =>
            if typedef_refers_to_resource(td2, type_table, visiting) {
              any = true
              break
            }
          Import(_name, _attributes, desc) =>
            if externdesc_refers_to_resource(desc, type_table, visiting) {
              any = true
              break
            }
          Export(_name, _attributes, desc) =>
            if externdesc_refers_to_resource(desc, type_table, visiting) {
              any = true
              break
            }
          _ => ()
        }
      }
      any
    }
    InstanceType(decls) => {
      let mut any = false
      for d in decls {
        match d {
          Type(td2) =>
            if typedef_refers_to_resource(td2, type_table, visiting) {
              any = true
              break
            }
          Export(_name, _attributes, desc) =>
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
fn clamp_type_size(size : Int32) -> Int32 {
  if size > 100000 {
    100001
  } else {
    size
  }
}

///|
fn add_type_size(acc : Int32, delta : Int32) -> Int32 {
  if acc > 100000 {
    return 100001
  }
  let d = clamp_type_size(delta)
  let sum = acc + d
  clamp_type_size(sum)
}

///|
fn local_type_size_of(idx : Int32, local_sizes : Array[Int32]) -> Int32 {
  if idx < 0 || idx >= local_sizes.length() {
    return 1
  }
  local_sizes[idx]
}

///|
fn externdesc_type_size(
  desc : @component.ExternDesc,
  local_sizes : Array[Int32],
) -> Int32 {
  match desc {
    ComponentType(tyidx) => local_type_size_of(tyidx, local_sizes)
    InstanceType(tyidx) => local_type_size_of(tyidx, local_sizes)
    FuncType(_) => 1
    CoreModuleType(_) => 1
    Type(_) => 1
    Value(_) => 1
  }
}

///|
fn effective_typedef_size(
  td : @component.TypeDef,
  outer_sizes : Array[Int32],
) -> Int32 {
  fn valtype_size(ty : @component.ValType) -> Int32 {
    match ty {
      Prim(_) => 1
      TypeIdx(idx) => local_type_size_of(idx, outer_sizes)
    }
  }

  match td {
    ComponentType(decls) => {
      let local_sizes : Array[Int32] = []
      let mut total = 1
      for d in decls {
        match d {
          Type(t) => local_sizes.push(effective_typedef_size(t, outer_sizes))
          AliasOuter(kind, count, idx) =>
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
          AliasInstanceExport(kind, _inst, _name) =>
            if kind == 0x03 {
              local_sizes.push(1)
            } else {
              ()
            }
          Import(_name, _attributes, desc) | Export(_name, _attributes, desc) => {
            total = add_type_size(
              total,
              externdesc_type_size(desc, local_sizes),
            )
            // Importing/exporting a type introduces a fresh local type index.
            if desc is Type(_) {
              local_sizes.push(1)
            }
          }
          CoreType(_) => ()
        }
        if total > 100000 {
          return 100001
        }
      }
      total
    }
    InstanceType(decls) => {
      let local_sizes : Array[Int32] = []
      let mut total = 1
      for d in decls {
        match d {
          Type(t) => local_sizes.push(effective_typedef_size(t, outer_sizes))
          AliasOuter(kind, count, idx) =>
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
          AliasInstanceExport(kind, _inst, _name) =>
            if kind == 0x03 {
              local_sizes.push(1)
            } else {
              ()
            }
          Export(_name, _attributes, desc) => {
            total = add_type_size(
              total,
              externdesc_type_size(desc, local_sizes),
            )
            if desc is Type(_) {
              local_sizes.push(1)
            }
          }
          CoreType(_) => ()
        }
        if total > 100000 {
          return 100001
        }
      }
      total
    }
    DefValType(_) => 1
    FuncType(ft) => {
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
    Tuple(tys) => {
      let mut total = 1
      for t in tys {
        total = add_type_size(total, valtype_size(t))
        if total > 100000 {
          return 100001
        }
      }
      total
    }
    Record(fields) => {
      let mut total = 1
      for f in fields {
        total = add_type_size(total, valtype_size(f.ty))
        if total > 100000 {
          return 100001
        }
      }
      total
    }
    Variant(cases) => {
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
    Option(v) => add_type_size(1, valtype_size(v))
    Result(ok, err) => {
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
    List(v) => add_type_size(1, valtype_size(v))
    Flags(labels) => add_type_size(1, labels.length())
    Enum(labels) => add_type_size(1, labels.length())
    _ => 1
  }
}
