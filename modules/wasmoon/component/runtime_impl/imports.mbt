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
              local_types.push(outer.types[idx])
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
          Export(name, desc) => {
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
                  (FuncType(_), Func(_))
                  | (Value(_), Value(_))
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
