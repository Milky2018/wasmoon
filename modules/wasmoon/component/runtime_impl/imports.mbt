///|
fn resolve_import(
  linker : ComponentLinker,
  overrides : Map[String, ComponentExtern],
  outer_stack : Array[ComponentInstance],
  name : ImportName,
  desc : ExternDesc,
  types : Array[TypeDef?],
  core_types : Array[Bytes],
  store : @runtime.Store,
) -> ComponentExtern raise ComponentRuntimeError {
  let key = decode_import_name(name)
  let ext_opt = match overrides.get(key) {
    Some(v) => Some(v)
    None => linker.imports.get(key)
  }
  let expected = match desc {
    CoreModuleType(_) => "module"
    FuncType(_) => "function"
    Value(_) => "value"
    Type(_) => "type"
    ComponentType(_) => "component"
    InstanceType(_) => "instance"
  }
  match ext_opt {
    Some(ext) =>
      match (desc, ext) {
        (CoreModuleType(_), CoreModule(_))
        | (FuncType(_), Func(_))
        | (Value(_), Value(_))
        | (Type(_), Type(_))
        | (ComponentType(_), Component(_))
        | (InstanceType(_), Instance(_)) =>
          match (desc, ext) {
            (InstanceType(tyidx), Instance(inst)) => {
              validate_instance_import_type(
                key, tyidx, inst, types, core_types, outer_stack,
              )
              ext
            }
            _ => ext
          }
        _ => {
          let actual = match ext {
            Func(_) => "func"
            Value(_) => "value"
            Type(_) => "type"
            Component(_) => "component"
            Instance(_) => "instance"
            CoreModule(_) => "module"
            CoreInstance(_) => "instance"
            CoreFunc(_) => "func"
            CoreTable(_) => "table"
            CoreMemory(_) => "memory"
            CoreGlobal(_) => "global"
            CoreTag(_) => "tag"
            CoreType(_) => "type"
          }
          raise ImportTypeMismatch("expected \{expected} found \{actual}")
        }
      }
    None =>
      match desc {
        Type(Eq(ti)) =>
          if ti >= 0 && ti < types.length() {
            Type(types[ti])
          } else {
            raise UnknownImport(key)
          }
        InstanceType(tyidx) =>
          match synthesize_trivial_instance_import(key, tyidx, types, store) {
            Some(inst) => Instance(inst)
            None => raise UnknownImport(key)
          }
        _ => raise UnknownImport(key)
      }
  }
}

///|
fn component_func_signature(
  func : ComponentFunc,
) -> (FuncType, Array[TypeDef?]) {
  match func {
    Host(func_type, types, _) => (func_type, types)
    HostAsync(func_type, types, _) => (func_type, types)
    Lifted(_, func_type, _, types, _, _, _, _) => (func_type, types)
  }
}

///|
fn component_val_types_match(
  expected : ValType,
  expected_types : Array[TypeDef?],
  actual : ValType,
  actual_types : Array[TypeDef?],
  depth : Int,
) -> Bool {
  if depth > 64 {
    return false
  }
  match (expected, actual) {
    (Prim(left), Prim(right)) => left == right
    (TypeIdx(left), TypeIdx(right)) =>
      component_type_indices_match(
        left,
        expected_types,
        right,
        actual_types,
        depth + 1,
      )
    (Prim(left), TypeIdx(right)) =>
      match type_at(actual_types, right) {
        Some(DefValType(right_prim)) => left == right_prim
        _ => false
      }
    (TypeIdx(left), Prim(right)) =>
      match type_at(expected_types, left) {
        Some(DefValType(left_prim)) => left_prim == right
        _ => false
      }
  }
}

///|
fn type_at(types : Array[TypeDef?], index : Int) -> TypeDef? {
  if index < 0 || index >= types.length() {
    None
  } else {
    types[index]
  }
}

///|
fn clone_materialized_valtype(
  ty : ValType,
  source_types : Array[TypeDef?],
  dest_types : Array[TypeDef?],
  remapped : Map[Int, Int],
) -> ValType raise ComponentRuntimeError {
  match ty {
    Prim(p) => Prim(p)
    TypeIdx(index) =>
      TypeIdx(
        clone_materialized_type_index(index, source_types, dest_types, remapped),
      )
  }
}

///|
fn clone_materialized_optional_valtype(
  ty : ValType?,
  source_types : Array[TypeDef?],
  dest_types : Array[TypeDef?],
  remapped : Map[Int, Int],
) -> ValType? raise ComponentRuntimeError {
  match ty {
    Some(value) =>
      Some(
        clone_materialized_valtype(value, source_types, dest_types, remapped),
      )
    None => None
  }
}

///|
fn clone_materialized_type_def(
  type_def : TypeDef,
  source_types : Array[TypeDef?],
  dest_types : Array[TypeDef?],
  remapped : Map[Int, Int],
) -> TypeDef raise ComponentRuntimeError {
  match type_def {
    DefValType(p) => DefValType(p)
    FuncType(func) => {
      let params : Array[@component.Param] = []
      for param in func.params {
        params.push({
          label: param.label,
          ty: clone_materialized_valtype(
            param.ty,
            source_types,
            dest_types,
            remapped,
          ),
        })
      }
      FuncType({
        is_async: func.is_async,
        params,
        result: clone_materialized_optional_valtype(
          func.result,
          source_types,
          dest_types,
          remapped,
        ),
      })
    }
    List(ty) =>
      List(clone_materialized_valtype(ty, source_types, dest_types, remapped))
    FixedList(ty, len) =>
      FixedList(
        clone_materialized_valtype(ty, source_types, dest_types, remapped),
        len,
      )
    MapType(key, value) =>
      MapType(
        clone_materialized_valtype(key, source_types, dest_types, remapped),
        clone_materialized_valtype(value, source_types, dest_types, remapped),
      )
    Record(fields) => {
      let cloned : Array[@component.RecordField] = []
      for field in fields {
        cloned.push({
          label: field.label,
          ty: clone_materialized_valtype(
            field.ty,
            source_types,
            dest_types,
            remapped,
          ),
        })
      }
      Record(cloned)
    }
    Variant(cases) => {
      let cloned : Array[@component.VariantCase] = []
      for case in cases {
        cloned.push({
          label: case.label,
          ty: clone_materialized_optional_valtype(
            case.ty,
            source_types,
            dest_types,
            remapped,
          ),
          refines: case.refines,
        })
      }
      Variant(cloned)
    }
    Tuple(types) => {
      let cloned : Array[ValType] = []
      for ty in types {
        cloned.push(
          clone_materialized_valtype(ty, source_types, dest_types, remapped),
        )
      }
      Tuple(cloned)
    }
    Flags(labels) => Flags(labels)
    Enum(labels) => Enum(labels)
    Option(ty) =>
      Option(clone_materialized_valtype(ty, source_types, dest_types, remapped))
    Result(ok, err) =>
      Result(
        clone_materialized_optional_valtype(
          ok, source_types, dest_types, remapped,
        ),
        clone_materialized_optional_valtype(
          err, source_types, dest_types, remapped,
        ),
      )
    Own(index) =>
      Own(
        clone_materialized_type_index(index, source_types, dest_types, remapped),
      )
    Borrow(index) =>
      Borrow(
        clone_materialized_type_index(index, source_types, dest_types, remapped),
      )
    Stream(ty) =>
      Stream(
        clone_materialized_optional_valtype(
          ty, source_types, dest_types, remapped,
        ),
      )
    Future(ty) =>
      Future(
        clone_materialized_optional_valtype(
          ty, source_types, dest_types, remapped,
        ),
      )
    ResourceType(id, rep, dtor, kind) => ResourceType(id, rep, dtor, kind)
    ComponentType(decls) => ComponentType(decls)
    InstanceTypeEmpty => InstanceTypeEmpty
    InstanceType(decls) => InstanceType(decls)
  }
}

///|
fn clone_materialized_type_index(
  index : Int,
  source_types : Array[TypeDef?],
  dest_types : Array[TypeDef?],
  remapped : Map[Int, Int],
) -> Int raise ComponentRuntimeError {
  if remapped.get(index) is Some(existing) {
    return existing
  }
  if index < 0 || index >= source_types.length() {
    raise InvalidTypeIndex(index)
  }
  let dest_index = dest_types.length()
  remapped.set(index, dest_index)
  dest_types.push(None)
  if source_types[index] is Some(type_def) {
    dest_types[dest_index] = Some(
      clone_materialized_type_def(type_def, source_types, dest_types, remapped),
    )
  }
  dest_index
}

///|
fn materialize_outer_type(
  source_index : Int,
  source_types : Array[TypeDef?],
  dest_types : Array[TypeDef?],
) -> Unit raise ComponentRuntimeError {
  let remapped : Map[Int, Int] = Map([])
  clone_materialized_type_index(
    source_index, source_types, dest_types, remapped,
  )
  |> ignore
}

///|
fn optional_val_types_match(
  expected : ValType?,
  expected_types : Array[TypeDef?],
  actual : ValType?,
  actual_types : Array[TypeDef?],
  depth : Int,
) -> Bool {
  match (expected, actual) {
    (None, None) => true
    (Some(left), Some(right)) =>
      component_val_types_match(
        left,
        expected_types,
        right,
        actual_types,
        depth + 1,
      )
    _ => false
  }
}

///|
fn component_type_indices_match(
  expected_index : Int,
  expected_types : Array[TypeDef?],
  actual_index : Int,
  actual_types : Array[TypeDef?],
  depth : Int,
) -> Bool {
  match
    (
      type_at(expected_types, expected_index),
      type_at(actual_types, actual_index),
    ) {
    (Some(expected), Some(actual)) =>
      component_type_defs_match(
        expected,
        expected_types,
        actual,
        actual_types,
        depth + 1,
      )
    _ => false
  }
}

///|
fn component_type_defs_match(
  expected : TypeDef,
  expected_types : Array[TypeDef?],
  actual : TypeDef,
  actual_types : Array[TypeDef?],
  depth : Int,
) -> Bool {
  if depth > 64 {
    return false
  }
  match (expected, actual) {
    (DefValType(left), DefValType(right)) => left == right
    (List(left), List(right)) | (Option(left), Option(right)) =>
      component_val_types_match(
        left,
        expected_types,
        right,
        actual_types,
        depth + 1,
      )
    (FixedList(left, left_len), FixedList(right, right_len)) =>
      left_len == right_len &&
      component_val_types_match(
        left,
        expected_types,
        right,
        actual_types,
        depth + 1,
      )
    (MapType(left_key, left_value), MapType(right_key, right_value)) =>
      component_val_types_match(
        left_key,
        expected_types,
        right_key,
        actual_types,
        depth + 1,
      ) &&
      component_val_types_match(
        left_value,
        expected_types,
        right_value,
        actual_types,
        depth + 1,
      )
    (Record(left), Record(right)) => {
      if left.length() != right.length() {
        return false
      }
      for i in 0..<left.length() {
        if left[i].label != right[i].label ||
          !component_val_types_match(
            left[i].ty,
            expected_types,
            right[i].ty,
            actual_types,
            depth + 1,
          ) {
          return false
        }
      }
      true
    }
    (Variant(left), Variant(right)) => {
      if left.length() != right.length() {
        return false
      }
      for i in 0..<left.length() {
        if left[i].label != right[i].label ||
          left[i].refines != right[i].refines ||
          !optional_val_types_match(
            left[i].ty,
            expected_types,
            right[i].ty,
            actual_types,
            depth + 1,
          ) {
          return false
        }
      }
      true
    }
    (Tuple(left), Tuple(right)) => {
      if left.length() != right.length() {
        return false
      }
      for i in 0..<left.length() {
        if !component_val_types_match(
            left[i],
            expected_types,
            right[i],
            actual_types,
            depth + 1,
          ) {
          return false
        }
      }
      true
    }
    (Flags(left), Flags(right)) | (Enum(left), Enum(right)) => left == right
    (Result(left_ok, left_err), Result(right_ok, right_err)) =>
      optional_val_types_match(
        left_ok,
        expected_types,
        right_ok,
        actual_types,
        depth + 1,
      ) &&
      optional_val_types_match(
        left_err,
        expected_types,
        right_err,
        actual_types,
        depth + 1,
      )
    (Own(left), Own(right)) | (Borrow(left), Borrow(right)) =>
      component_type_indices_match(
        left,
        expected_types,
        right,
        actual_types,
        depth + 1,
      )
    (Stream(left), Stream(right)) | (Future(left), Future(right)) =>
      optional_val_types_match(
        left,
        expected_types,
        right,
        actual_types,
        depth + 1,
      )
    (
      ResourceType(left_id, left_rep, _, left_kind),
      ResourceType(right_id, right_rep, _, right_kind),
    ) =>
      (left_id < 0 || right_id < 0 || left_id == right_id) &&
      left_rep == right_rep &&
      left_kind == right_kind
    (FuncType(left), FuncType(right)) =>
      component_func_types_match(
        left,
        expected_types,
        right,
        actual_types,
        depth + 1,
      )
    (InstanceTypeEmpty, InstanceTypeEmpty) => true
    (ComponentType(left), ComponentType(right)) => left == right
    (InstanceType(left), InstanceType(right)) => left == right
    _ => false
  }
}

///|
fn component_func_types_match(
  expected : FuncType,
  expected_types : Array[TypeDef?],
  actual : FuncType,
  actual_types : Array[TypeDef?],
  depth : Int,
) -> Bool {
  if expected.is_async != actual.is_async ||
    expected.params.length() != actual.params.length() {
    return false
  }
  for i in 0..<expected.params.length() {
    if !component_val_types_match(
        expected.params[i].ty,
        expected_types,
        actual.params[i].ty,
        actual_types,
        depth + 1,
      ) {
      return false
    }
  }
  optional_val_types_match(
    expected.result,
    expected_types,
    actual.result,
    actual_types,
    depth + 1,
  )
}

///|
fn require_component_func_type(
  name : String,
  expected_index : Int,
  expected_types : Array[TypeDef?],
  actual_func : ComponentFunc,
) -> Unit raise ComponentRuntimeError {
  guard type_at(expected_types, expected_index) is Some(FuncType(expected)) else {
    raise ImportTypeMismatch(
      "invalid function type for instance export \{name}",
    )
  }
  let (actual, actual_types) = component_func_signature(actual_func)
  if !component_func_types_match(
      expected, expected_types, actual, actual_types, 0,
    ) {
    raise ImportTypeMismatch(
      "instance function export signature mismatch: \{name}",
    )
  }
}

///|
fn validate_instance_import_type(
  import_key : String,
  tyidx : Int,
  inst : ComponentInstance,
  types : Array[TypeDef?],
  _core_types : Array[Bytes],
  outer_stack : Array[ComponentInstance],
) -> Unit raise ComponentRuntimeError {
  if tyidx < 0 || tyidx >= types.length() {
    raise UnknownImport(import_key)
  }
  match types[tyidx] {
    Some(InstanceTypeEmpty) => ()
    Some(InstanceType(decls)) => {
      // Instance type decls have their own local type space; we interpret a
      // minimal subset needed for resource type bounds and (alias outer ...).
      let local_types : Array[TypeDef?] = []
      let local_core_types : Array[Bytes] = []
      for d in decls {
        match d {
          CoreType(bytes) => local_core_types.push(bytes)
          AliasOuter(kind, count, idx) => {
            // In the binary format, `count` is 1-based: 1 = current env, 2 = one level out, ...
            let depth = count - 1
            if depth < 0 || depth >= outer_stack.length() {
              raise OuterAliasOutOfRange(count)
            }
            let outer = outer_stack[outer_stack.length() - 1 - depth]
            // Alias kinds use `parse_alias_kind` encoding:
            // - Type = 0x03
            // - Core sorts are encoded as 0x100 + <core_sort>
            if kind == 0x03 {
              if idx < 0 || idx >= outer.types.length() {
                raise InvalidTypeIndex(idx)
              }
              materialize_outer_type(idx, outer.types, local_types)
            } else if (kind & 0x100) != 0 {
              if idx < 0 || idx >= outer.core_types.length() {
                raise InvalidCoreTypeIndex(idx)
              }
              local_core_types.push(outer.core_types[idx])
            } else {
              ()
            }
          }
          AliasInstanceExport(kind, _instance_idx, _name) =>
            if kind == 0x03 {
              // Not needed for current component-spec coverage; keep the local
              // type space aligned for later indices.
              local_types.push(None)
            }
          Type(t) => local_types.push(Some(t))
          Export(name, _attributes, desc) => {
            // Instance type exports of `type` also declare a slot in the local
            // type index space, which later decls can reference (e.g. `own 0`).
            let type_slot : Int? = match desc {
              Type(_) => Some(local_types.length())
              _ => None
            }
            match desc {
              Type(bound) =>
                match bound {
                  SubResource =>
                    local_types.push(
                      Some(ResourceType(-1, 0x7f, None, HostDefined)),
                    )
                  Eq(ti) => {
                    let aliased = if ti >= 0 && ti < local_types.length() {
                      local_types[ti]
                    } else if ti >= 0 && ti < types.length() {
                      types[ti]
                    } else {
                      None
                    }
                    local_types.push(aliased)
                  }
                }
              _ => ()
            }
            match inst.get_export(name) {
              None =>
                match desc {
                  // For equality-bounded type exports, the host doesn't need to
                  // redundantly supply the alias; it can be inferred.
                  Type(Eq(_)) => ()
                  _ => raise UnknownImport(import_key)
                }
              Some(ext) =>
                match (desc, ext) {
                  (Type(SubResource), Func(_)) =>
                    raise ImportTypeMismatch("expected resource found func")
                  (CoreModuleType(tyidx), CoreModule(m)) => {
                    if tyidx < 0 || tyidx >= local_core_types.length() {
                      raise ImportTypeMismatch("invalid core module type index")
                    }
                    check_core_module_against_type(m, local_core_types[tyidx])
                  }
                  (FuncType(tyidx), Func(func)) =>
                    require_component_func_type(name, tyidx, local_types, func)
                  (Value(_), Value(_))
                  | (ComponentType(_), Component(_))
                  | (InstanceType(_), Instance(_)) => ()
                  (Type(bound), Type(actual)) =>
                    match bound {
                      SubResource =>
                        match actual {
                          Some(ResourceType(_, _, _, _)) =>
                            // Capture the host-supplied identity so later `(eq ...)` bounds
                            // compare against the real type instead of the placeholder.
                            match type_slot {
                              Some(slot) =>
                                if slot >= 0 && slot < local_types.length() {
                                  local_types[slot] = actual
                                }
                              None => ()
                            }
                          _ =>
                            raise ImportTypeMismatch(
                              "mismatched resource types",
                            )
                        }
                      Eq(ti) => {
                        let expected = if ti >= 0 && ti < local_types.length() {
                          local_types[ti]
                        } else if ti >= 0 && ti < types.length() {
                          types[ti]
                        } else {
                          raise ImportTypeMismatch("invalid type bound index")
                        }
                        match (expected, actual) {
                          (
                            Some(ResourceType(id1, _, _, kind1)),
                            Some(ResourceType(id2, _, _, kind2)),
                          ) =>
                            if id1 < 0 {
                              // Unify the abstract resource type with the
                              // concrete host-supplied identity so subsequent
                              // equality constraints work.
                              if ti >= 0 && ti < local_types.length() {
                                local_types[ti] = actual
                              }
                            } else if id1 != id2 || kind1 != kind2 {
                              raise ImportTypeMismatch(
                                "mismatched resource types",
                              )
                            }
                          _ =>
                            if expected != actual {
                              raise ImportTypeMismatch(
                                "instance export type mismatch",
                              )
                            }
                        }
                      }
                    }
                  _ => raise ImportTypeMismatch("instance export type mismatch")
                }
            }
          }
        }
      }
    }
    _ => ()
  }
}

///|
