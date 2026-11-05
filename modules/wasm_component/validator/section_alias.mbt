///|
/// Handle component alias section (id 6).
fn validate_component_section_alias(
  payload : Bytes,
  counts : Counts,
  type_table : Array[@component.TypeDef?],
  known_type_sigs : Map[Int32, TypeSig],
  local_resource_types : Array[Bool],
  resource_ids : Array[Int32?],
  type_sizes : Array[Int32],
  type_depths : Array[Int32],
  components : Array[ComponentIndexEntry],
  instances : Array[InstanceIndexEntry],
  named_types : Map[Int32, Int32],
  core_modules : Array[CoreModuleIndexEntry],
  core_types : Array[CoreModuleTypeSignature?],
  core_type_outers : Array[Array[CoreModuleTypeSignature?]],
  core_func_types : Array[@types.FuncType?],
  core_instances : Array[CoreInstanceIndexEntry],
  core_memory_types : Array[@types.MemoryType?],
  func_types : Array[@component.FuncType?],
  func_sig_shapes : Array[FuncSigShape?],
  type_outers : Array[Array[@component.TypeDef?]],
  component_outers : Array[Array[ComponentIndexEntry]],
) -> Unit raise ComponentValidationError {
  let aliases = @component.parse_alias_section(payload) catch {
    e => raise SectionParseError(6, "\{e}")
  }
  for a in aliases {
    if a.sort is Core(0x12) {
      raise UnsupportedCoreSort(0x12)
    }
    let mut new_core_func_ty : @types.FuncType? = None
    let mut new_core_memory_ty : @types.MemoryType? = None
    let mut new_instance_sig : InstanceSig? = None
    let mut new_instance_export_type_sigs : Map[String, TypeSig]? = None
    let mut new_instance_export_func_sigs : Map[String, FuncSigShape]? = None
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
          check_sortidx({ sort: a.sort, idx, }, counts, type_table.length())
        }
      }
    }
    if a.sort is Component && a.target is Outer(ct, idx) {
      if ct == 0 {
        if idx >= 0 && idx < components.length() {
          new_component_size = components[idx].size
        }
      } else {
        let depth = ct - 1
        if depth >= 0 && depth < component_outers.length() {
          let tbl = component_outers[depth]
          if idx >= 0 && idx < tbl.length() {
            new_component_size = tbl[idx].size
          }
        }
      }
    }
    // If we are aliasing an instance export that has a known ascribed
    // instance type, propagate its export signature into the new
    // instance index-space entry.
    if (a.sort, a.target) is (Instance, Export(instance_idx, name)) &&
      instances.get(instance_idx) is Some(parent) {
      new_instance_sig = parent.signature.bind(sig => sig.nested.get(name))
      new_instance_export_type_sigs = parent.nested_type_signatures.bind(map => {
        map.get(name)
      })
      new_instance_export_func_sigs = parent.nested_function_signatures.bind(map => {
        map.get(name)
      })
    }
    match a.target {
      Export(instance_idx, name) => {
        // Keep validation robust even if our auxiliary tables lag behind
        // counts (e.g. for inline/aliased instances).
        let sig = instances.get(instance_idx).bind(entry => entry.signature)
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
        let export_kinds = core_instances
          .get(core_instance_idx)
          .bind(entry => entry.export_kinds)
        match export_kinds {
          Some(map) =>
            match map.get(name) {
              Some(kind) =>
                match a.sort {
                  Core(core_sort) =>
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
      (Core(0x00), CoreExport(core_instance_idx, name)) => {
        let export_types = core_instances
          .get(core_instance_idx)
          .bind(entry => entry.export_types)
        match export_types {
          Some(map) =>
            match map.get(name) {
              Some(Func(ft)) => new_core_func_ty = Some(ft)
              _ => ()
            }
          None => ()
        }
      }
      (Core(0x02), CoreExport(core_instance_idx, name)) => {
        let export_types = core_instances
          .get(core_instance_idx)
          .bind(entry => entry.export_types)
        match export_types {
          Some(map) =>
            match map.get(name) {
              Some(Memory(mt)) => new_core_memory_ty = Some(mt)
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
      let mut new_rid : Int32? = None
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
                if typedef_refers_to_resource(td, tbl, Map([])) {
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
          let tmap = instances
            .get(instance_idx)
            .bind(entry => entry.exported_types)
          match tmap {
            Some(map) =>
              match map.get(name) {
                Some(Existing(idx)) => {
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
                Some(Resource(rid)) => {
                  new_td = Some(ResourceType(-1, 0x7f, None, HostDefined))
                  new_rid = Some(rid)
                }
                Some(Opaque) => {
                  let sigmap = instances
                    .get(instance_idx)
                    .bind(entry => entry.type_signatures)
                  match sigmap {
                    Some(sm) =>
                      match sm.get(name) {
                        Some(sig) =>
                          match
                            typedef_of_typesig(
                              sig,
                              type_table,
                              resource_ids,
                              Some(named_types),
                            ) {
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
      // Preserve the complete signature even when nested definitions have no
      // index in this component's local type namespace.
      match a.target {
        Export(instance_idx, name) =>
          if instances.get(instance_idx) is Some(entry) &&
            entry.type_signatures is Some(signatures) &&
            signatures.get(name) is Some(signature) {
            known_type_sigs.set(type_table.length(), signature)
          }
        Outer(0, idx) =>
          if known_type_sigs.get(idx) is Some(signature) {
            known_type_sigs.set(type_table.length(), signature)
          }
        _ => ()
      }
      type_table.push(new_td)
      local_resource_types.push(new_local_resource)
      resource_ids.push(new_rid)
      type_sizes.push(new_size)
      type_depths.push(new_depth)
      if a.target is Export(instance_idx, _name) &&
        instances.get(instance_idx) is Some(entry) &&
        entry.in_interface {
        named_types.set(type_table.length() - 1, 1)
      }
    } else {
      count_alias(a.sort, counts)
      match a.sort {
        Func => {
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
              let fmap = instances
                .get(instance_idx)
                .bind(entry => entry.function_signatures)
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
        Instance =>
          instances.push({
            ..InstanceIndexEntry::unknown(),
            signature: new_instance_sig,
            type_signatures: new_instance_export_type_sigs,
            function_signatures: new_instance_export_func_sigs,
          })
        Component =>
          components.push(ComponentIndexEntry::unknown(new_component_size))
        Core(core_sort) =>
          if core_sort == 0x11 {
            core_modules.push(CoreModuleIndexEntry::unknown())
          } else if core_sort == 0x10 || core_sort == 0x05 {
            let signature = match a.target {
              Outer(0, index) => core_types[index]
              Outer(count, index) =>
                outer_core_type_of_alias(core_type_outers, count, index)
              _ => raise AliasTargetMismatch("core type")
            }
            core_types.push(signature)
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
