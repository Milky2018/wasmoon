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
        (CoreModuleType(_), ComponentExtern::CoreModule(_))
        | (FuncType(_), ComponentExtern::Func(_))
        | (Value(_), ComponentExtern::Value(_))
        | (Type(_), ComponentExtern::Type(_))
        | (ComponentType(_), ComponentExtern::Component(_))
        | (InstanceType(_), ComponentExtern::Instance(_)) =>
          match (desc, ext) {
            (InstanceType(tyidx), ComponentExtern::Instance(inst)) => {
              validate_instance_import_type(
                key, tyidx, inst, types, core_types, outer_stack,
              )
              ext
            }
            _ => ext
          }
        _ => {
          let actual = match ext {
            ComponentExtern::Func(_) => "func"
            ComponentExtern::Value(_) => "value"
            ComponentExtern::Type(_) => "type"
            ComponentExtern::Component(_) => "component"
            ComponentExtern::Instance(_) => "instance"
            ComponentExtern::CoreModule(_) => "module"
            ComponentExtern::CoreInstance(_) => "instance"
            ComponentExtern::CoreFunc(_) => "func"
            ComponentExtern::CoreTable(_) => "table"
            ComponentExtern::CoreMemory(_) => "memory"
            ComponentExtern::CoreGlobal(_) => "global"
            ComponentExtern::CoreTag(_) => "tag"
            ComponentExtern::CoreType(_) => "type"
          }
          raise ImportTypeMismatch("expected \{expected} found \{actual}")
        }
      }
    None =>
      match desc {
        Type(TypeBound::Eq(ti)) =>
          if ti >= 0 && ti < types.length() {
            ComponentExtern::Type(types[ti])
          } else {
            raise UnknownImport(key)
          }
        InstanceType(tyidx) =>
          match synthesize_trivial_instance_import(key, tyidx, types, store) {
            Some(inst) => ComponentExtern::Instance(inst)
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
  core_types : Array[Bytes],
  outer_stack : Array[ComponentInstance],
) -> Unit raise ComponentRuntimeError {
  if tyidx < 0 || tyidx >= types.length() {
    raise UnknownImport(import_key)
  }
  match types[tyidx] {
    Some(TypeDef::InstanceTypeEmpty) => ()
    Some(TypeDef::InstanceType(decls)) => {
      // Instance type decls have their own local type space; we interpret a
      // minimal subset needed for resource type bounds and (alias outer ...).
      let local_types : Array[TypeDef?] = []
      let local_core_types : Array[Bytes] = []
      for d in decls {
        match d {
          InstanceDecl::CoreType(bytes) => local_core_types.push(bytes)
          InstanceDecl::AliasOuter(kind, count, idx) => {
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
          InstanceDecl::AliasInstanceExport(kind, _instance_idx, _name) =>
            if kind == 0x03 {
              // Not needed for current component-spec coverage; keep the local
              // type space aligned for later indices.
              local_types.push(None)
            }
          InstanceDecl::Type(t) => local_types.push(Some(t))
          InstanceDecl::Export(name, desc) => {
            // Instance type exports of `type` also declare a slot in the local
            // type index space, which later decls can reference (e.g. `own 0`).
            let type_slot : Int? = match desc {
              ExternDesc::Type(_) => Some(local_types.length())
              _ => None
            }
            match desc {
              ExternDesc::Type(bound) =>
                match bound {
                  TypeBound::SubResource =>
                    local_types.push(
                      Some(
                        TypeDef::ResourceType(
                          -1,
                          0x7f,
                          None,
                          ResourceKind::HostDefined,
                        ),
                      ),
                    )
                  TypeBound::Eq(ti) => {
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
                  ExternDesc::Type(TypeBound::Eq(_)) => ()
                  _ => raise UnknownImport(import_key)
                }
              Some(ext) =>
                match (desc, ext) {
                  (
                    ExternDesc::Type(TypeBound::SubResource),
                    ComponentExtern::Func(_),
                  ) => raise ImportTypeMismatch("expected resource found func")
                  (
                    ExternDesc::CoreModuleType(tyidx),
                    ComponentExtern::CoreModule(m),
                  ) => {
                    if tyidx < 0 || tyidx >= local_core_types.length() {
                      raise ImportTypeMismatch("invalid core module type index")
                    }
                    check_core_module_against_type(m, local_core_types[tyidx])
                  }
                  (ExternDesc::FuncType(_), ComponentExtern::Func(_))
                  | (ExternDesc::Value(_), ComponentExtern::Value(_))
                  | (ExternDesc::ComponentType(_), ComponentExtern::Component(_)
                  )
                  | (ExternDesc::InstanceType(_), ComponentExtern::Instance(_)) =>
                    ()
                  (ExternDesc::Type(bound), ComponentExtern::Type(actual)) =>
                    match bound {
                      TypeBound::SubResource =>
                        match actual {
                          Some(TypeDef::ResourceType(_, _, _, _)) =>
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
                      TypeBound::Eq(ti) => {
                        let expected = if ti >= 0 && ti < local_types.length() {
                          local_types[ti]
                        } else if ti >= 0 && ti < types.length() {
                          types[ti]
                        } else {
                          raise ImportTypeMismatch("invalid type bound index")
                        }
                        match (expected, actual) {
                          (
                            Some(TypeDef::ResourceType(id1, _, _, kind1)),
                            Some(TypeDef::ResourceType(id2, _, _, kind2)),
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
