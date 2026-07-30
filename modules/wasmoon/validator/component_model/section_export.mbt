///|
/// Handle component export section (id 11).
fn validate_component_section_export(
  payload : Bytes,
  cfg : ComponentValidationConfig,
  is_root : Bool,
  counts : Counts,
  type_table : Array[@component.TypeDef?],
  local_resource_types : Array[Bool],
  resource_ids : Array[Int?],
  type_sizes : Array[Int],
  type_depths : Array[Int],
  component_sizes : Array[Int],
  instance_sizes : Array[Int],
  export_size : Int,
  named_types : Map[Int, Int],
  core_module_exports : Array[Map[String, Int]?],
  core_module_defs : Array[@types.Module?],
  core_func_types : Array[@types.FuncType?],
  core_module_export_types : Array[Map[String, CoreExternType]?],
  core_module_type_imports : Array[Array[CoreModuleTypeImport]?],
  core_instance_exports : Array[Map[String, Int]?],
  core_instance_export_types : Array[Map[String, CoreExternType]?],
  core_memory_types : Array[@types.MemoryType?],
  component_import_sorts : Array[Map[String, @component.Sort]?],
  component_import_instance_sigs : Array[Map[String, InstanceSig]?],
  component_import_func_sigs : Array[Map[String, FuncSigShape]?],
  component_import_instance_resource_exports : Array[
    Map[String, Map[String, Int]]?,
  ],
  component_import_core_module_exports : Array[Map[String, Map[String, Int]]?],
  component_import_core_module_import_sigs : Array[
    Map[String, Map[String, CoreExternType]]?,
  ],
  component_import_type_bounds : Array[Map[String, @component.TypeBound]?],
  component_import_type_sigs : Array[Map[String, TypeSig]?],
  component_export_sorts : Array[Map[String, @component.Sort]?],
  component_export_instance_sigs : Array[Map[String, InstanceSig]?],
  component_export_instance_type_sigs : Array[
    Map[String, Map[String, TypeSig]]?,
  ],
  component_export_instance_func_sigs : Array[
    Map[String, Map[String, FuncSigShape]]?,
  ],
  component_export_type_sigs : Array[Map[String, TypeSig]?],
  component_export_func_sigs : Array[Map[String, FuncSigShape]?],
  instance_sigs : Array[InstanceSig?],
  interface_instance_idxs : Map[Int, Int],
  instance_export_type_idxs : Array[Array[Int]?],
  instance_export_func_idxs : Array[Array[Int]?],
  instance_export_type_map : Array[Map[String, ExportedTypeInfo]?],
  instance_export_type_sigs : Array[Map[String, TypeSig]?],
  instance_export_func_sigs : Array[Map[String, FuncSigShape]?],
  instance_nested_instance_type_sigs : Array[Map[String, Map[String, TypeSig]]?],
  instance_nested_instance_func_sigs : Array[
    Map[String, Map[String, FuncSigShape]]?,
  ],
  func_types : Array[@component.FuncType?],
  func_sig_shapes : Array[FuncSigShape?],
  imported_funcs : Int,
  seen_export_names : Map[String, String],
  export_resource_names : Map[String, Int],
  my_export_sorts : Map[String, @component.Sort],
  my_export_instance_sigs : Map[String, InstanceSig],
  my_export_instance_type_sigs : Map[String, Map[String, TypeSig]],
  my_export_instance_func_sigs : Map[String, Map[String, FuncSigShape]],
  my_export_type_sigs : Map[String, TypeSig],
  my_export_func_sigs : Map[String, FuncSigShape],
  type_outers : Array[Array[@component.TypeDef?]],
  next_resource_id : Int,
) -> (Int, Int) raise ComponentValidationError {
  let mut export_size = export_size
  let mut next_resource_id = next_resource_id
  let exports = @component.parse_export_section(payload) catch {
    e => raise SectionParseError(11, "\{e}")
  }
  for e in exports {
    validate_export_name(e.name, cfg)
    validate_name_attributes(
      11,
      exportname_to_bytes(e.name),
      e.attributes,
      e.sortidx.sort,
    )
    if is_root && e.sortidx.sort is Component {
      raise SectionParseError(
        11, "exporting a component from the root component is not supported",
      )
    }
    if exportname_to_string(e.name) is Some(name) {
      // wasm-tools' very-nested.wast relies on long export names to
      // trigger the effective-size limiter.
      export_size = add_type_size(export_size, name.length())
      let key = if cfg.wit_names { wit_conflict_key(name) } else { name }
      match seen_export_names.get(key) {
        Some(prev) =>
          if prev == name {
            raise DuplicateExportName(name)
          } else {
            raise SectionParseError(
              11,
              "export name `\{name}` conflicts with previous name `\{prev}`",
            )
          }
        None => seen_export_names.set(key, name)
      }
    }
    if exportname_to_string(e.name) is Some(name) {
      my_export_sorts.set(name, e.sortidx.sort)
    }
    if exportname_to_string(e.name) is Some(name) &&
      parse_bracket_resource_name(name) is Some(_) &&
      !(e.sortidx.sort is Func) {
      raise SectionParseError(11, "is not a func")
    }
    if is_root && e.sortidx.sort is Func && e.sortidx.idx < imported_funcs {
      raise ExportedImportedFunc(e.sortidx.idx)
    }
    check_sortidx(e.sortidx, counts, type_table.length())
    let mut ascribed_resource_id : Int? = None
    if e.sortidx.sort is Type && e.desc is Some(Type(SubResource)) {
      if !(type_sig_of_typeidx(e.sortidx.idx, type_table, resource_ids)
        is Resource(_)) {
        raise AscribedExportTypeIncompatible
      }
      ascribed_resource_id = Some(next_resource_id)
      next_resource_id += 1
    }
    if e.sortidx.sort is Type {
      if exportname_to_string(e.name) is Some(name) {
        let sig = match ascribed_resource_id {
          Some(rid) => TypeSig::Resource(rid)
          None => type_sig_of_typeidx(e.sortidx.idx, type_table, resource_ids)
        }
        my_export_type_sigs.set(name, sig)
      }
    }
    if e.sortidx.sort is Func &&
      exportname_to_string(e.name) is Some(name) &&
      e.sortidx.idx >= 0 &&
      e.sortidx.idx < func_types.length() {
      let mut ft : @component.FuncType? = None
      if e.desc is Some(FuncType(tyidx)) &&
        tyidx >= 0 &&
        tyidx < type_table.length() &&
        type_table[tyidx] is Some(FuncType(t)) {
        ft = Some(t)
      }
      if ft is None {
        ft = func_types[e.sortidx.idx]
      }
      if ft is Some(ft) {
        validate_bracketed_func_name(
          11, name, ft, type_table, resource_ids, export_resource_names,
        )
        my_export_func_sigs.set(
          name,
          funcsig_of_functype(ft, type_table, resource_ids),
        )
      }
    }
    if e.sortidx.sort is Instance && exportname_to_string(e.name) is Some(name) {
      if e.sortidx.idx >= 0 &&
        e.sortidx.idx < instance_sigs.length() &&
        instance_sigs[e.sortidx.idx] is Some(sig) {
        my_export_instance_sigs.set(name, sig)
      }
      if e.sortidx.idx >= 0 &&
        e.sortidx.idx < instance_export_type_sigs.length() &&
        instance_export_type_sigs[e.sortidx.idx] is Some(map) {
        my_export_instance_type_sigs.set(name, map)
      }
      if e.sortidx.idx >= 0 &&
        e.sortidx.idx < instance_export_func_sigs.length() &&
        instance_export_func_sigs[e.sortidx.idx] is Some(map) {
        my_export_instance_func_sigs.set(name, map)
      }
    }

    // Enforce "exportable" rules: nominal-ish types must have names in the
    // interface namespace (provided via type imports/exports).
    match e.sortidx.sort {
      Type => {
        let idx = e.sortidx.idx
        let had = named_types.get(idx) is Some(_)
        if !had {
          named_types.set(idx, 1)
        }
        if !valtype_valid_for_type_import_export(
            TypeIdx(idx),
            type_table,
            resource_ids,
            named_types,
            Map([]),
          ) {
          raise SectionParseError(11, "type not valid to be used as export")
        }
        if !had {
          named_types.remove(idx) |> ignore
        }
        if idx >= 0 && idx < type_table.length() {
          match type_table[idx] {
            Some(InstanceType(_)) | Some(InstanceTypeEmpty) =>
              if !instancetype_valid_for_use_as_interface(
                  idx, type_table, type_outers,
                ) {
                raise SectionParseError(
                  11, "type not valid to be used as export",
                )
              }
            _ => ()
          }
        }
      }
      Func =>
        if e.sortidx.idx >= 0 && e.sortidx.idx < func_types.length() {
          let mut ft : @component.FuncType? = None
          match e.desc {
            Some(FuncType(tyidx)) =>
              if tyidx >= 0 && tyidx < type_table.length() {
                match type_table[tyidx] {
                  Some(FuncType(t)) => ft = Some(t)
                  _ => ()
                }
              }
            _ => ()
          }
          if ft is None {
            ft = func_types[e.sortidx.idx]
          }
          match ft {
            Some(ft) =>
              if !functype_valid_in_interface(
                  ft, type_table, resource_ids, named_types,
                ) {
                raise SectionParseError(
                  11, "func not valid to be used as export",
                )
              }
            None => ()
          }
        }
      Instance => {
        let inst_idx = e.sortidx.idx
        if inst_idx >= 0 && inst_idx < counts.instance {
          let exported_type_idxs : Array[Int] = []
          let seen : Map[Int, Int] = Map([])
          if inst_idx >= 0 && inst_idx < instance_export_type_idxs.length() {
            match instance_export_type_idxs[inst_idx] {
              Some(t_idxs) =>
                for t in t_idxs {
                  if seen.get(t) is None {
                    seen.set(t, 1)
                    exported_type_idxs.push(t)
                  }
                }
              None => ()
            }
          }
          if inst_idx >= 0 && inst_idx < instance_export_type_map.length() {
            match instance_export_type_map[inst_idx] {
              Some(map) =>
                for kv in map.iter() {
                  let (_name, info) = kv
                  match info {
                    Existing(t) =>
                      if seen.get(t) is None {
                        seen.set(t, 1)
                        exported_type_idxs.push(t)
                      }
                    _ => ()
                  }
                }
              None => ()
            }
          }
          if inst_idx >= 0 && inst_idx < instance_export_type_sigs.length() {
            match instance_export_type_sigs[inst_idx] {
              Some(map) =>
                for kv in map.iter() {
                  let (_name, sig) = kv
                  match typeidx_of_typesig(sig, type_table, resource_ids) {
                    Some(t) =>
                      if seen.get(t) is None {
                        seen.set(t, 1)
                        exported_type_idxs.push(t)
                      }
                    None => ()
                  }
                }
              None => ()
            }
          }
          let inst_named : Map[Int, Int] = Map([])
          for kv in named_types.iter() {
            let (k, v) = kv
            inst_named.set(k, v)
          }
          for t in exported_type_idxs {
            inst_named.set(t, 1)
          }
          for t in exported_type_idxs {
            if !valtype_valid_in_interface(
                TypeIdx(t),
                type_table,
                resource_ids,
                inst_named,
                Map([]),
              ) {
              raise SectionParseError(
                11, "instance not valid to be used as export",
              )
            }
          }

          // Make types exported through this instance available to later
          // exports in this component's interface.
          for t in exported_type_idxs {
            named_types.set(t, 1)
          }

          // Validate exported functions use only named types (either named
          // in the parent interface or exported by this instance).
          let named_sigs : Array[TypeSig] = []
          for kv in inst_named.iter() {
            let (k, _v) = kv
            let sig = type_sig_of_typeidx(k, type_table, resource_ids)
            if sig != Other && !typesig_contains(sig, named_sigs) {
              named_sigs.push(sig)
            }
          }
          if inst_idx >= 0 && inst_idx < instance_export_type_sigs.length() {
            match instance_export_type_sigs[inst_idx] {
              Some(map) =>
                for kv in map.iter() {
                  let (_name, sig) = kv
                  if sig != Other && !typesig_contains(sig, named_sigs) {
                    named_sigs.push(sig)
                  }
                }
              None => ()
            }
          }
          let mut validated_by_idx = false
          let mut validated_by_sig = false
          if inst_idx >= 0 && inst_idx < instance_export_func_idxs.length() {
            match instance_export_func_idxs[inst_idx] {
              Some(f_idxs) => {
                validated_by_idx = true
                for f in f_idxs {
                  if f >= 0 && f < func_types.length() {
                    match func_types[f] {
                      Some(ft) =>
                        if !functype_valid_in_interface(
                            ft, type_table, resource_ids, inst_named,
                          ) {
                          raise SectionParseError(
                            11, "instance not valid to be used as export",
                          )
                        }
                      None => ()
                    }
                  }
                }
              }
              None => ()
            }
          }
          if !validated_by_idx &&
            inst_idx >= 0 &&
            inst_idx < instance_export_func_sigs.length() {
            match instance_export_func_sigs[inst_idx] {
              Some(map) => {
                validated_by_sig = true
                for kv in map.iter() {
                  let (_name, sig) = kv
                  if !funcsig_valid_in_interface(sig, named_sigs) {
                    raise SectionParseError(
                      11, "instance not valid to be used as export",
                    )
                  }
                }
              }
              None => ()
            }
          }
          if !validated_by_idx && !validated_by_sig {
            let mut needs_funcs = false
            if inst_idx >= 0 && inst_idx < instance_sigs.length() {
              match instance_sigs[inst_idx] {
                Some(s) =>
                  for kv in s.exports.iter() {
                    let (_n, sort) = kv
                    if sort is Func {
                      needs_funcs = true
                      break
                    }
                  }
                None => ()
              }
            }
            if needs_funcs {
              raise SectionParseError(
                11, "instance not valid to be used as export",
              )
            }
          }
        }
      }
      _ => ()
    }
    // Track effective type size of this component's export signature.
    match e.sortidx.sort {
      Instance => {
        let delta = if e.sortidx.idx >= 0 &&
          e.sortidx.idx < instance_sizes.length() {
          instance_sizes[e.sortidx.idx]
        } else {
          1
        }
        export_size = add_type_size(export_size, delta)
      }
      Type => {
        let delta = if e.sortidx.idx >= 0 && e.sortidx.idx < type_sizes.length() {
          type_sizes[e.sortidx.idx]
        } else {
          1
        }
        export_size = add_type_size(export_size, delta)
      }
      Component => {
        let delta = if e.sortidx.idx >= 0 &&
          e.sortidx.idx < component_sizes.length() {
          component_sizes[e.sortidx.idx]
        } else {
          1
        }
        export_size = add_type_size(export_size, delta)
      }
      _ => export_size = add_type_size(export_size, 1)
    }
    if e.desc is Some(d) {
      validate_externdesc(d, type_table, counts.core_type)
    }
    // Export ascription: if a type is provided, it must be compatible with
    // the actual export (we currently model instance-type compatibility).
    match (e.sortidx.sort, e.desc) {
      (Instance, Some(InstanceType(tyidx))) =>
        if tyidx >= 0 && tyidx < type_table.length() {
          let expected = instancetype_sig_of_global_idx(
            tyidx,
            type_table,
            Map([]),
          )
          let actual = if e.sortidx.idx >= 0 &&
            e.sortidx.idx < instance_sigs.length() {
            instance_sigs[e.sortidx.idx]
          } else {
            None
          }
          check_instance_subtype(actual, expected)
          match exportname_to_string(e.name) {
            Some(name) => my_export_instance_sigs.set(name, expected)
            None => ()
          }
        } else {
          raise AscribedExportTypeIncompatible
        }
      (_sort, Some(d)) =>
        if sort_of_externdesc(d) != e.sortidx.sort {
          raise AscribedExportTypeIncompatible
        }
      _ => ()
    }

    // Component exports can introduce an alias in the corresponding index
    // space, which later sections can reference by index.
    if e.sortidx.sort is Type {
      let idx = e.sortidx.idx
      if ascribed_resource_id is Some(rid) {
        type_table.push(Some(ResourceType(-1, 0x7f, None, HostDefined)))
        local_resource_types.push(false)
        resource_ids.push(Some(rid))
        type_sizes.push(1)
        type_depths.push(1)
      } else if idx >= 0 && idx < type_table.length() {
        type_table.push(type_table[idx])
        if idx >= 0 && idx < local_resource_types.length() {
          local_resource_types.push(local_resource_types[idx])
        } else {
          local_resource_types.push(false)
        }
        if idx >= 0 && idx < resource_ids.length() {
          resource_ids.push(resource_ids[idx])
        } else {
          resource_ids.push(None)
        }
        if idx >= 0 && idx < type_sizes.length() {
          type_sizes.push(type_sizes[idx])
        } else {
          type_sizes.push(1)
        }
        if idx >= 0 && idx < type_depths.length() {
          type_depths.push(type_depths[idx])
        } else {
          type_depths.push(1)
        }
      } else {
        type_table.push(None)
        local_resource_types.push(false)
        resource_ids.push(None)
        type_sizes.push(1)
        type_depths.push(1)
      }
      // The exported type alias is now a named type in the interface.
      let alias_idx = type_table.length() - 1
      named_types.set(alias_idx, 1)
      if exportname_to_string(e.name) is Some(name) &&
        type_sig_of_typeidx(alias_idx, type_table, resource_ids) is Resource(_) {
        export_resource_names.set(name, alias_idx)
      }
    } else {
      count_alias(e.sortidx.sort, counts)
      match e.sortidx.sort {
        Func =>
          if e.sortidx.idx >= 0 && e.sortidx.idx < func_types.length() {
            func_types.push(func_types[e.sortidx.idx])
            if e.sortidx.idx >= 0 && e.sortidx.idx < func_sig_shapes.length() {
              func_sig_shapes.push(func_sig_shapes[e.sortidx.idx])
            } else {
              func_sig_shapes.push(None)
            }
          } else {
            func_types.push(None)
            func_sig_shapes.push(None)
          }
        Instance =>
          if e.sortidx.idx >= 0 && e.sortidx.idx < instance_sigs.length() {
            instance_sigs.push(instance_sigs[e.sortidx.idx])
            if e.sortidx.idx >= 0 &&
              e.sortidx.idx < instance_export_type_idxs.length() {
              instance_export_type_idxs.push(
                instance_export_type_idxs[e.sortidx.idx],
              )
            } else {
              instance_export_type_idxs.push(None)
            }
            if e.sortidx.idx >= 0 &&
              e.sortidx.idx < instance_export_func_idxs.length() {
              instance_export_func_idxs.push(
                instance_export_func_idxs[e.sortidx.idx],
              )
            } else {
              instance_export_func_idxs.push(None)
            }
            if e.sortidx.idx >= 0 &&
              e.sortidx.idx < instance_export_type_map.length() {
              instance_export_type_map.push(
                instance_export_type_map[e.sortidx.idx],
              )
            } else {
              instance_export_type_map.push(None)
            }
            if e.sortidx.idx >= 0 &&
              e.sortidx.idx < instance_export_type_sigs.length() {
              instance_export_type_sigs.push(
                instance_export_type_sigs[e.sortidx.idx],
              )
            } else {
              instance_export_type_sigs.push(None)
            }
            if e.sortidx.idx >= 0 &&
              e.sortidx.idx < instance_export_func_sigs.length() {
              instance_export_func_sigs.push(
                instance_export_func_sigs[e.sortidx.idx],
              )
            } else {
              instance_export_func_sigs.push(None)
            }
            if e.sortidx.idx >= 0 &&
              e.sortidx.idx < instance_nested_instance_type_sigs.length() {
              instance_nested_instance_type_sigs.push(
                instance_nested_instance_type_sigs[e.sortidx.idx],
              )
            } else {
              instance_nested_instance_type_sigs.push(None)
            }
            if e.sortidx.idx >= 0 &&
              e.sortidx.idx < instance_nested_instance_func_sigs.length() {
              instance_nested_instance_func_sigs.push(
                instance_nested_instance_func_sigs[e.sortidx.idx],
              )
            } else {
              instance_nested_instance_func_sigs.push(None)
            }
            if e.sortidx.idx >= 0 && e.sortidx.idx < instance_sizes.length() {
              instance_sizes.push(instance_sizes[e.sortidx.idx])
            } else {
              instance_sizes.push(1)
            }
            interface_instance_idxs.set(instance_sigs.length() - 1, 1)
          } else {
            instance_sigs.push(None)
            instance_export_type_idxs.push(None)
            instance_export_func_idxs.push(None)
            instance_export_type_map.push(None)
            instance_export_type_sigs.push(None)
            instance_export_func_sigs.push(None)
            instance_nested_instance_type_sigs.push(None)
            instance_nested_instance_func_sigs.push(None)
            instance_sizes.push(1)
            interface_instance_idxs.set(instance_sigs.length() - 1, 1)
          }
        Component => {
          let src = e.sortidx.idx
          if src >= 0 && src < component_import_sorts.length() {
            component_import_sorts.push(component_import_sorts[src])
            component_import_instance_sigs.push(
              component_import_instance_sigs[src],
            )
            component_import_func_sigs.push(component_import_func_sigs[src])
            component_import_instance_resource_exports.push(
              component_import_instance_resource_exports[src],
            )
            component_import_core_module_exports.push(
              component_import_core_module_exports[src],
            )
            component_import_core_module_import_sigs.push(
              component_import_core_module_import_sigs[src],
            )
            component_import_type_bounds.push(component_import_type_bounds[src])
            component_import_type_sigs.push(component_import_type_sigs[src])
            component_export_sorts.push(component_export_sorts[src])
            component_export_instance_sigs.push(
              component_export_instance_sigs[src],
            )
            component_export_instance_type_sigs.push(
              component_export_instance_type_sigs[src],
            )
            component_export_instance_func_sigs.push(
              component_export_instance_func_sigs[src],
            )
            component_export_type_sigs.push(component_export_type_sigs[src])
            component_export_func_sigs.push(component_export_func_sigs[src])
          } else {
            component_import_sorts.push(None)
            component_import_instance_sigs.push(None)
            component_import_func_sigs.push(None)
            component_import_instance_resource_exports.push(None)
            component_import_core_module_exports.push(None)
            component_import_core_module_import_sigs.push(None)
            component_import_type_bounds.push(None)
            component_import_type_sigs.push(None)
            component_export_sorts.push(None)
            component_export_instance_sigs.push(None)
            component_export_instance_type_sigs.push(None)
            component_export_instance_func_sigs.push(None)
            component_export_type_sigs.push(None)
            component_export_func_sigs.push(None)
          }
          if src >= 0 && src < component_sizes.length() {
            component_sizes.push(component_sizes[src])
          } else {
            component_sizes.push(1)
          }
        }
        Core(core_sort) =>
          if core_sort == 0x00 {
            if e.sortidx.idx >= 0 && e.sortidx.idx < core_func_types.length() {
              core_func_types.push(core_func_types[e.sortidx.idx])
            } else {
              core_func_types.push(None)
            }
          } else if core_sort == 0x02 {
            if e.sortidx.idx >= 0 && e.sortidx.idx < core_memory_types.length() {
              core_memory_types.push(core_memory_types[e.sortidx.idx])
            } else {
              core_memory_types.push(None)
            }
          } else if core_sort == 0x11 {
            if e.sortidx.idx >= 0 &&
              e.sortidx.idx < core_module_exports.length() {
              core_module_exports.push(core_module_exports[e.sortidx.idx])
            } else {
              core_module_exports.push(None)
            }
            if e.sortidx.idx >= 0 &&
              e.sortidx.idx < core_module_export_types.length() {
              core_module_export_types.push(
                core_module_export_types[e.sortidx.idx],
              )
            } else {
              core_module_export_types.push(None)
            }
            if e.sortidx.idx >= 0 &&
              e.sortidx.idx < core_module_type_imports.length() {
              core_module_type_imports.push(
                core_module_type_imports[e.sortidx.idx],
              )
            } else {
              core_module_type_imports.push(None)
            }
            if e.sortidx.idx >= 0 && e.sortidx.idx < core_module_defs.length() {
              core_module_defs.push(core_module_defs[e.sortidx.idx])
            } else {
              core_module_defs.push(None)
            }
          } else if core_sort == 0x12 {
            if e.sortidx.idx >= 0 &&
              e.sortidx.idx < core_instance_exports.length() {
              core_instance_exports.push(core_instance_exports[e.sortidx.idx])
            } else {
              core_instance_exports.push(None)
            }
            if e.sortidx.idx >= 0 &&
              e.sortidx.idx < core_instance_export_types.length() {
              core_instance_export_types.push(
                core_instance_export_types[e.sortidx.idx],
              )
            } else {
              core_instance_export_types.push(None)
            }
          } else {
            ()
          }
        _ => ()
      }
    }
    // These aliases can be referenced by later exports/sections, so
    // conservatively account for their contribution to the effective
    // signature size (wasm-tools' very-nested.wast).
    match e.sortidx.sort {
      Instance => {
        let delta = if instance_sizes.length() > 0 {
          instance_sizes[instance_sizes.length() - 1]
        } else {
          1
        }
        export_size = add_type_size(export_size, delta)
      }
      Type => {
        let delta = if type_sizes.length() > 0 {
          type_sizes[type_sizes.length() - 1]
        } else {
          1
        }
        export_size = add_type_size(export_size, delta)
      }
      Component => {
        let delta = if component_sizes.length() > 0 {
          component_sizes[component_sizes.length() - 1]
        } else {
          1
        }
        export_size = add_type_size(export_size, delta)
      }
      _ => export_size = add_type_size(export_size, 1)
    }
  }
  (export_size, next_resource_id)
}
