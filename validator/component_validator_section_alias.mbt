///|
/// Handle component alias section (id 6).
fn validate_component_section_alias(
  payload : Bytes,
  counts : Counts,
  type_table : Array[@component.TypeDef?],
  local_resource_types : Array[Bool],
  resource_ids : Array[Int?],
  type_sizes : Array[Int],
  type_depths : Array[Int],
  component_sizes : Array[Int],
  instance_sizes : Array[Int],
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
  type_outers : Array[Array[@component.TypeDef?]],
  component_size_outers : Array[Array[Int]],
) -> Unit raise ComponentValidationError {
  let aliases = @component.parse_alias_section(payload) catch {
    e => raise SectionParseError(6, "\{e}")
  }
  for a in aliases {
    let mut new_core_func_ty : @types.FuncType? = None
    let mut new_core_memory_ty : @types.MemoryType? = None
    let mut new_instance_sig : InstanceSig? = None
    let mut new_instance_export_type_sigs : Map[String, TypeSig]? = None
    let mut new_instance_export_func_sigs : Map[String, FuncSigShape]? = None
    let new_instance_nested_type_sigs : Map[String, Map[String, TypeSig]]? = None
    let new_instance_nested_func_sigs : Map[String, Map[String, FuncSigShape]]? = None
    let mut new_component_size = 1
    match a.target {
      Export(instance_idx, _name) =>
        if instance_idx < 0 || instance_idx >= counts.instance {
          raise InvalidInstanceIndex(instance_idx)
        }
      CoreExport(core_instance_idx, _name) =>
        if core_instance_idx < 0 || core_instance_idx >= counts.core_instance {
          raise InvalidCoreInstanceIndex(core_instance_idx)
        }
      Outer(ct, idx) => {
        // `ct` is an outer depth: 0 = current component, 1 = parent, ...
        if ct < 0 || ct > type_outers.length() {
          raise SectionParseError(6, "invalid outer alias count of \{ct}")
        }
        // For aliases that target the current component, validate bounds
        // against the current in-progress index spaces.
        if ct == 0 {
          check_sortidx({ sort: a.sort, idx }, counts, type_table.length())
        }
      }
    }
    if a.sort is Component {
      match a.target {
        Outer(ct, idx) =>
          if ct == 0 {
            if idx >= 0 && idx < component_sizes.length() {
              new_component_size = component_sizes[idx]
            }
          } else {
            let depth = ct - 1
            if depth >= 0 && depth < component_size_outers.length() {
              let tbl = component_size_outers[depth]
              if idx >= 0 && idx < tbl.length() {
                new_component_size = tbl[idx]
              }
            }
          }
        _ => ()
      }
    }
    // If we are aliasing an instance export that has a known ascribed
    // instance type, propagate its export signature into the new
    // instance index-space entry.
    match (a.sort, a.target) {
      (@component.Sort::Instance, Export(instance_idx, name)) => {
        let parent = if instance_idx >= 0 &&
          instance_idx < instance_sigs.length() {
          instance_sigs[instance_idx]
        } else {
          None
        }
        match parent {
          Some(sig) =>
            match sig.nested.get(name) {
              Some(child) => new_instance_sig = Some(child)
              None => ()
            }
          None => ()
        }
        if instance_idx >= 0 &&
          instance_idx < instance_nested_instance_type_sigs.length() {
          match instance_nested_instance_type_sigs[instance_idx] {
            Some(map) =>
              match map.get(name) {
                Some(m) => new_instance_export_type_sigs = Some(m)
                None => ()
              }
            None => ()
          }
        }
        if instance_idx >= 0 &&
          instance_idx < instance_nested_instance_func_sigs.length() {
          match instance_nested_instance_func_sigs[instance_idx] {
            Some(map) =>
              match map.get(name) {
                Some(m) => new_instance_export_func_sigs = Some(m)
                None => ()
              }
            None => ()
          }
        }
      }
      _ => ()
    }
    match a.target {
      Export(instance_idx, name) => {
        // Keep validation robust even if our auxiliary tables lag behind
        // counts (e.g. for inline/aliased instances).
        let sig = if instance_idx >= 0 && instance_idx < instance_sigs.length() {
          instance_sigs[instance_idx]
        } else {
          None
        }
        match sig {
          Some(s) =>
            match s.exports.get(name) {
              Some(sort) =>
                if sort != a.sort {
                  raise AliasTargetMismatch("instance export \{name}")
                }
              None => raise MissingInstanceExport(instance_idx, name)
            }
          None => ()
        }
      }
      CoreExport(core_instance_idx, name) => {
        let export_kinds = if core_instance_idx >= 0 &&
          core_instance_idx < core_instance_exports.length() {
          core_instance_exports[core_instance_idx]
        } else {
          None
        }
        match export_kinds {
          Some(map) =>
            match map.get(name) {
              Some(kind) =>
                match a.sort {
                  @component.Sort::Core(core_sort) =>
                    if core_sort != kind {
                      raise AliasTargetMismatch("core export \{name}")
                    }
                  _ => raise AliasTargetMismatch("core export \{name}")
                }
              None => raise MissingCoreInstanceExport(core_instance_idx, name)
            }
          None => ()
        }
      }
      Outer(_ct, _idx) => ()
    }
    // Capture core memory types for later canonical ABI checks.
    match (a.sort, a.target) {
      (@component.Sort::Core(0x00), CoreExport(core_instance_idx, name)) => {
        let export_types = if core_instance_idx >= 0 &&
          core_instance_idx < core_instance_export_types.length() {
          core_instance_export_types[core_instance_idx]
        } else {
          None
        }
        match export_types {
          Some(map) =>
            match map.get(name) {
              Some(CoreExternType::Func(ft)) => new_core_func_ty = Some(ft)
              _ => ()
            }
          None => ()
        }
      }
      (@component.Sort::Core(0x02), CoreExport(core_instance_idx, name)) => {
        let export_types = if core_instance_idx >= 0 &&
          core_instance_idx < core_instance_export_types.length() {
          core_instance_export_types[core_instance_idx]
        } else {
          None
        }
        match export_types {
          Some(map) =>
            match map.get(name) {
              Some(CoreExternType::Memory(mt)) => new_core_memory_ty = Some(mt)
              _ => ()
            }
          None => ()
        }
      }
      _ => ()
    }
    if a.sort is Type {
      let mut new_td : @component.TypeDef? = None
      let mut new_local_resource = false
      let mut new_rid : Int? = None
      let mut new_size = 1
      let mut new_depth = 1
      match a.target {
        Outer(ct, idx) =>
          if ct == 0 {
            if idx >= 0 && idx < type_table.length() {
              new_td = type_table[idx]
            }
            if idx >= 0 && idx < local_resource_types.length() {
              new_local_resource = local_resource_types[idx]
            }
            if idx >= 0 && idx < resource_ids.length() {
              new_rid = resource_ids[idx]
            }
            if idx >= 0 && idx < type_sizes.length() {
              new_size = type_sizes[idx]
            }
            if idx >= 0 && idx < type_depths.length() {
              new_depth = type_depths[idx]
            }
          } else {
            let outer_td = outer_type_of_alias(type_outers, ct, idx)
            match outer_td {
              Some(td) => {
                let tbl = type_outers[ct - 1]
                if typedef_refers_to_resource(td, tbl, {}) {
                  raise SectionParseError(
                    6, "refers to resources not defined in the current component",
                  )
                }
              }
              None => ()
            }
            new_td = outer_td
          }
        Export(instance_idx, name) => {
          let tmap = if instance_idx >= 0 &&
            instance_idx < instance_export_type_map.length() {
            instance_export_type_map[instance_idx]
          } else {
            None
          }
          match tmap {
            Some(map) =>
              match map.get(name) {
                Some(ExportedTypeInfo::Existing(idx)) => {
                  if idx >= 0 && idx < type_table.length() {
                    new_td = type_table[idx]
                  }
                  if idx >= 0 && idx < local_resource_types.length() {
                    new_local_resource = local_resource_types[idx]
                  }
                  if idx >= 0 && idx < resource_ids.length() {
                    new_rid = resource_ids[idx]
                  }
                  if idx >= 0 && idx < type_sizes.length() {
                    new_size = type_sizes[idx]
                  }
                  if idx >= 0 && idx < type_depths.length() {
                    new_depth = type_depths[idx]
                  }
                }
                Some(ExportedTypeInfo::Resource(rid)) => {
                  new_td = Some(
                    @component.TypeDef::ResourceType(
                      -1,
                      0x7f,
                      None,
                      @component.ResourceKind::HostDefined,
                    ),
                  )
                  new_rid = Some(rid)
                }
                Some(ExportedTypeInfo::Opaque) => {
                  let sigmap = if instance_idx >= 0 &&
                    instance_idx < instance_export_type_sigs.length() {
                    instance_export_type_sigs[instance_idx]
                  } else {
                    None
                  }
                  match sigmap {
                    Some(sm) =>
                      match sm.get(name) {
                        Some(sig) =>
                          match
                            typedef_of_typesig(sig, type_table, resource_ids) {
                            Some(td) => new_td = Some(td)
                            None => ()
                          }
                        None => ()
                      }
                    None => ()
                  }
                }
                None => ()
              }
            None => ()
          }
        }
        _ => ()
      }
      type_table.push(new_td)
      local_resource_types.push(new_local_resource)
      resource_ids.push(new_rid)
      type_sizes.push(new_size)
      type_depths.push(new_depth)
      match a.target {
        Export(instance_idx, _name) =>
          if interface_instance_idxs.get(instance_idx) is Some(_) {
            named_types.set(type_table.length() - 1, 1)
          }
        _ => ()
      }
    } else {
      count_alias(a.sort, counts)
      match a.sort {
        @component.Sort::Func => {
          let mut new_ft : @component.FuncType? = None
          let mut new_sig : FuncSigShape? = None
          match a.target {
            Outer(ct, idx) =>
              if ct == 0 {
                if idx >= 0 && idx < func_types.length() {
                  new_ft = func_types[idx]
                }
                if idx >= 0 && idx < func_sig_shapes.length() {
                  new_sig = func_sig_shapes[idx]
                }
              }
            Export(instance_idx, name) => {
              let fmap = if instance_idx >= 0 &&
                instance_idx < instance_export_func_sigs.length() {
                instance_export_func_sigs[instance_idx]
              } else {
                None
              }
              match fmap {
                Some(map) =>
                  match map.get(name) {
                    Some(sig) => new_sig = Some(sig)
                    None => ()
                  }
                None => ()
              }
            }
            _ => ()
          }
          func_types.push(new_ft)
          func_sig_shapes.push(new_sig)
        }
        @component.Sort::Instance => {
          instance_sigs.push(new_instance_sig)
          instance_export_type_idxs.push(None)
          instance_export_func_idxs.push(None)
          instance_export_type_map.push(None)
          instance_export_type_sigs.push(new_instance_export_type_sigs)
          instance_export_func_sigs.push(new_instance_export_func_sigs)
          instance_nested_instance_type_sigs.push(new_instance_nested_type_sigs)
          instance_nested_instance_func_sigs.push(new_instance_nested_func_sigs)
          instance_sizes.push(1)
        }
        @component.Sort::Component => {
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
          component_sizes.push(new_component_size)
        }
        @component.Sort::Core(core_sort) =>
          if core_sort == 0x11 {
            core_module_exports.push(None)
            core_module_export_types.push(None)
            core_module_type_imports.push(None)
            core_module_defs.push(None)
          } else if core_sort == 0x12 {
            core_instance_exports.push(None)
          } else if core_sort == 0x00 {
            core_func_types.push(new_core_func_ty)
          } else if core_sort == 0x02 {
            core_memory_types.push(new_core_memory_ty)
          } else {
            ()
          }
        _ => ()
      }
    }
  }
}
