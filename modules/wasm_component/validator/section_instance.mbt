///|
/// Handle component instance section (id 5).
fn validate_component_section_instance(
  payload : Bytes,
  cfg : ComponentValidationConfig,
  counts : Counts,
  type_table : Array[@component.TypeDef?],
  known_type_sigs : Map[Int32, TypeSig],
  resource_ids : Array[Int32?],
  components : Array[ComponentIndexEntry],
  instances : Array[InstanceIndexEntry],
  core_modules : Array[CoreModuleIndexEntry],
  func_types : Array[@component.FuncType?],
  func_sig_shapes : Array[FuncSigShape?],
  next_resource_id : Int32,
) -> Int32 raise ComponentValidationError {
  let mut next_resource_id = next_resource_id
  let declarations = @component.parse_instance_section(payload) catch {
    e => raise SectionParseError(5, "\{e}")
  }
  for inst in declarations {
    let mut inst_sig : InstanceSig? = None
    let mut inst_size = 1
    let mut inst_type_idxs : Array[Int32]? = None
    let mut inst_func_idxs : Array[Int32]? = None
    let mut inst_type_map : Map[String, ExportedTypeInfo]? = None
    let mut inst_type_sig_map : Map[String, TypeSig]? = None
    let mut inst_func_sig_map : Map[String, FuncSigShape]? = None
    let mut inst_nested_type_sigs : Map[String, Map[String, TypeSig]]? = None
    let mut inst_nested_func_sigs : Map[String, Map[String, FuncSigShape]]? = None
    match inst.expr {
      Instantiate(component_idx, args) => {
        if component_idx < 0 || component_idx >= counts.component {
          raise InvalidComponentIndex(component_idx)
        }
        let entry = components
          .get(component_idx)
          .unwrap_or_else(() => ComponentIndexEntry::unknown(1))
        inst_size = entry.size
        // The component declaration may have no known signature.
        let expected_imports = entry.import_sorts
        let expected_import_instance_sigs = entry.import_instance_sigs
        let expected_import_func_sigs = entry.import_func_sigs
        let expected_import_core_modules = entry.import_core_modules
        let expected_import_type_sigs = entry.import_type_sigs
        let expected_import_type_bounds = entry.import_type_bounds
        let expected_import_instance_resource_exports = entry.import_instance_resource_exports
        let pending_type_args : Array[(String, Int32)] = []
        let pending_func_args : Array[(String, Int32)] = []
        let pending_instance_args : Array[(String, Int32)] = []
        let seen_args : Map[String, Int32] = Map([])
        for a in args {
          check_sortidx(a.sortidx, counts, type_table.length())
          if seen_args.get(a.name) is Some(_) {
            raise DuplicateInstantiationArg(a.name)
          }
          seen_args.set(a.name, 1)
          match expected_imports {
            Some(map) =>
              match map.get(a.name) {
                None => () // extra args are allowed (wasm-tools behavior)
                Some(sort) =>
                  if sort != a.sortidx.sort {
                    raise ComponentImportTypeMismatch(a.name)
                  } else {
                    if sort is Func {
                      pending_func_args.push((a.name, a.sortidx.idx))
                    }
                    if sort is Instance {
                      pending_instance_args.push((a.name, a.sortidx.idx))
                    }
                    match (sort, expected_import_instance_sigs) {
                      (Instance, Some(sig_map)) =>
                        match sig_map.get(a.name) {
                          Some(req) => {
                            let actual = instances
                              .get(a.sortidx.idx)
                              .bind(entry => entry.signature)
                            check_instance_subtype(actual, req)
                          }
                          None => ()
                        }
                      _ => ()
                    }
                    if sort is Core(0x11) &&
                      expected_import_core_modules is Some(requirements) &&
                      requirements.get(a.name) is Some(required) &&
                      core_modules.get(a.sortidx.idx) is Some(actual) {
                      check_core_module_subtype(
                        actual.export_kinds,
                        required.exports,
                      )
                      check_core_module_import_subtype(
                        actual.import_signature(),
                        required.imports,
                      )
                    }
                    if sort is Type {
                      pending_type_args.push((a.name, a.sortidx.idx))
                    }
                  }
              }
            None => ()
          }
        }
        match expected_imports {
          Some(map) =>
            for kv in map.iter() {
              let (name, _sort) = kv
              if seen_args.get(name) is None {
                raise MissingComponentImport(name)
              }
            }
          None => ()
        }

        // Validate type/function arguments that may depend on type-argument
        // substitution (notably for nominal resource types).
        let rid_subst : Map[Int32, Int32] = Map([])
        match expected_import_instance_resource_exports {
          Some(inst_map) =>
            for kv in pending_instance_args {
              let (name, inst_idx) = kv
              match inst_map.get(name) {
                Some(exports) =>
                  for kv2 in exports.iter() {
                    let (tname, expected_rid) = kv2
                    let tmap = instances
                      .get(inst_idx)
                      .bind(entry => entry.exported_types)
                    match tmap {
                      Some(map) =>
                        match map.get(tname) {
                          Some(Resource(actual_rid)) =>
                            rid_subst.set(expected_rid, actual_rid)
                          Some(Existing(tidx)) =>
                            match
                              type_sig_of_typeidx(
                                tidx,
                                type_table,
                                resource_ids,
                                known_sigs=known_type_sigs,
                              ) {
                              Resource(actual_rid) =>
                                rid_subst.set(expected_rid, actual_rid)
                              _ =>
                                raise SectionParseError(
                                  5, "expected resource, found defined type",
                                )
                            }
                          _ =>
                            raise SectionParseError(
                              5, "expected resource, found defined type",
                            )
                        }
                      None =>
                        raise SectionParseError(
                          5, "expected resource, found defined type",
                        )
                    }
                  }
                None => ()
              }
            }
          None => ()
        }
        match (expected_import_type_bounds, expected_import_type_sigs) {
          (Some(bounds), Some(sigs)) => {
            // First, map `sub resource` imports to the actual provided resource ids.
            for kv in pending_type_args {
              let (name, idx) = kv
              match bounds.get(name) {
                Some(SubResource) =>
                  match sigs.get(name) {
                    Some(Resource(expected_rid)) => {
                      let actual_sig = type_sig_of_typeidx(
                        idx,
                        type_table,
                        resource_ids,
                        known_sigs=known_type_sigs,
                      )
                      match actual_sig {
                        Resource(actual_rid) =>
                          rid_subst.set(expected_rid, actual_rid)
                        _ =>
                          raise SectionParseError(
                            5, "expected resource, found defined type",
                          )
                      }
                    }
                    _ => ()
                  }
                _ => ()
              }
            }
            // Then validate `eq` type imports with resource substitution applied.
            for kv in pending_type_args {
              let (name, idx) = kv
              match bounds.get(name) {
                Some(Eq(_)) =>
                  match sigs.get(name) {
                    Some(req0) => {
                      let req = type_sig_subst_resources(req0, rid_subst)
                      let actual = type_sig_of_typeidx(
                        idx,
                        type_table,
                        resource_ids,
                        known_sigs=known_type_sigs,
                      )
                      if actual != req {
                        match (req, actual) {
                          (Resource(_), Resource(_)) =>
                            raise SectionParseError(
                              5, "resource types are not the same",
                            )
                          (Resource(_), _) =>
                            raise SectionParseError(
                              5, "expected resource, found defined type",
                            )
                          (_, Resource(_)) =>
                            raise SectionParseError(
                              5, "expected defined type, found resource",
                            )
                          _ =>
                            if type_sig_has_resource_mismatch(req, actual) {
                              raise SectionParseError(
                                5, "resource types are not the same",
                              )
                            } else {
                              raise ComponentImportTypeMismatch("type \{name}")
                            }
                        }
                      }
                    }
                    None => ()
                  }
                _ => ()
              }
            }
          }
          _ => ()
        }
        // Finally validate function imports with the same resource substitution.
        match expected_import_func_sigs {
          Some(func_map) =>
            for kv in pending_func_args {
              let (name, idx) = kv
              match func_map.get(name) {
                Some(expected0) => {
                  let expected = funcsig_subst_resources(expected0, rid_subst)
                  let sig_from_map = if idx >= 0 &&
                    idx < func_sig_shapes.length() {
                    func_sig_shapes[idx]
                  } else {
                    None
                  }
                  let actual_sig = match sig_from_map {
                    Some(sig) => Some(sig)
                    None =>
                      if idx >= 0 && idx < func_types.length() {
                        match func_types[idx] {
                          Some(actual) =>
                            Some(
                              funcsig_of_functype(
                                actual,
                                type_table,
                                resource_ids,
                                known_sigs=known_type_sigs,
                              ),
                            )
                          None => None
                        }
                      } else {
                        None
                      }
                  }
                  match actual_sig {
                    Some(actual_sig) =>
                      if actual_sig != expected {
                        if funcsig_has_resource_mismatch(expected, actual_sig) {
                          raise SectionParseError(
                            5, "resource types are not the same",
                          )
                        } else {
                          raise ComponentImportTypeMismatch("function")
                        }
                      }
                    None => ()
                  }
                }
                None => ()
              }
            }
          None => ()
        }

        // Propagate the component's export signature to the instantiated
        // instance so later aliasing/instantiations can validate exports.
        if entry.export_sorts is Some(exports) {
          let nested = entry.export_instance_sigs.unwrap_or_else(() => Map([]))
          inst_sig = Some({ exports, nested, })
        }

        // Track exported types so `(alias export $inst "t" (type $x))` can
        // resolve resource identities (wasm-tools/resources.wast).
        if entry.export_type_sigs is Some(sig_map) {
          let out : Map[String, ExportedTypeInfo] = Map([])
          let sig_out : Map[String, TypeSig] = Map([])
          // Allocate every fresh resource before translating signatures.
          // Dependent types and aliases must see the same instance-local
          // identity regardless of export iteration order.
          for (_, sig) in sig_map.iter() {
            if sig is Resource(rid) && rid_subst.get(rid) is None {
              rid_subst.set(rid, next_resource_id)
              next_resource_id += 1
            }
          }
          for kv in sig_map.iter() {
            let (name, sig0) = kv
            sig_out.set(name, type_sig_subst_resources(sig0, rid_subst))
            match sig0 {
              Resource(rid0) => {
                let actual_rid = rid_subst.get(rid0).unwrap()
                let mut found : Int32? = None
                for i in 0..<type_table.length() {
                  if type_sig_of_typeidx(
                      i,
                      type_table,
                      resource_ids,
                      known_sigs=known_type_sigs,
                    ) ==
                    Resource(actual_rid) {
                    found = Some(i)
                    break
                  }
                }
                match found {
                  Some(idx) => out.set(name, Existing(idx))
                  None => out.set(name, Resource(actual_rid))
                }
              }
              _ => {
                let sig = type_sig_subst_resources(sig0, rid_subst)
                let mut found : Int32? = None
                for i in 0..<type_table.length() {
                  if type_sig_of_typeidx(
                      i,
                      type_table,
                      resource_ids,
                      known_sigs=known_type_sigs,
                    ) ==
                    sig {
                    found = Some(i)
                    break
                  }
                }
                match found {
                  Some(idx) => out.set(name, Existing(idx))
                  None => out.set(name, Opaque)
                }
              }
            }
          }
          inst_type_map = Some(out)
          inst_type_sig_map = Some(sig_out)
        }
        if entry.export_func_sigs is Some(sig_map) {
          let out : Map[String, FuncSigShape] = Map([])
          for kv in sig_map.iter() {
            let (name, sig0) = kv
            out.set(name, funcsig_subst_resources(sig0, rid_subst))
          }
          inst_func_sig_map = Some(out)
        }
        if entry.export_instance_type_sigs is Some(inst_map0) {
          let out : Map[String, Map[String, TypeSig]] = Map([])
          for kv in inst_map0.iter() {
            let (inst_name, types0) = kv
            let types : Map[String, TypeSig] = Map([])
            for kv2 in types0.iter() {
              let (name, sig0) = kv2
              types.set(name, type_sig_subst_resources(sig0, rid_subst))
            }
            out.set(inst_name, types)
          }
          inst_nested_type_sigs = Some(out)
        }
        if entry.export_instance_func_sigs is Some(inst_map0) {
          let out : Map[String, Map[String, FuncSigShape]] = Map([])
          for kv in inst_map0.iter() {
            let (inst_name, funcs0) = kv
            let funcs : Map[String, FuncSigShape] = Map([])
            for kv2 in funcs0.iter() {
              let (name, sig0) = kv2
              funcs.set(name, funcsig_subst_resources(sig0, rid_subst))
            }
            out.set(inst_name, funcs)
          }
          inst_nested_func_sigs = Some(out)
        }
      }
      InlineExports(inline_exports) => {
        let map : Map[String, @component.Sort] = Map([])
        let mut size = 1
        let t_idxs : Array[Int32] = []
        let f_idxs : Array[Int32] = []
        let type_map : Map[String, ExportedTypeInfo] = Map([])
        let type_sig_map : Map[String, TypeSig] = Map([])
        let func_map : Map[String, FuncSigShape] = Map([])
        for ex in inline_exports {
          check_sortidx(ex.sortidx, counts, type_table.length())
          validate_name_attributes_string(
            5,
            ex.name,
            ex.attributes,
            ex.sortidx.sort,
            cfg,
          )
          if cfg.wit_names && parse_bracket_resource_name(ex.name) is Some(_) {
            raise SectionParseError(
              5, "resource used in function does not have a name in this context",
            )
          }
          validate_extern_name_string(ex.name, cfg)
          if map.get(ex.name) is Some(_) {
            raise DuplicateExportName(ex.name)
          }
          map.set(ex.name, ex.sortidx.sort)
          match ex.sortidx.sort {
            Type => {
              t_idxs.push(ex.sortidx.idx)
              type_map.set(ex.name, Existing(ex.sortidx.idx))
              type_sig_map.set(
                ex.name,
                type_sig_of_typeidx(
                  ex.sortidx.idx,
                  type_table,
                  resource_ids,
                  known_sigs=known_type_sigs,
                ),
              )
            }
            Func => {
              f_idxs.push(ex.sortidx.idx)
              let sig = if ex.sortidx.idx >= 0 &&
                ex.sortidx.idx < func_sig_shapes.length() {
                func_sig_shapes[ex.sortidx.idx]
              } else {
                None
              }
              match sig {
                Some(s) => func_map.set(ex.name, s)
                None =>
                  if ex.sortidx.idx >= 0 && ex.sortidx.idx < func_types.length() {
                    match func_types[ex.sortidx.idx] {
                      Some(ft) =>
                        func_map.set(
                          ex.name,
                          funcsig_of_functype(
                            ft,
                            type_table,
                            resource_ids,
                            known_sigs=known_type_sigs,
                          ),
                        )
                      None => ()
                    }
                  }
              }
            }
            _ => ()
          }
          match ex.sortidx.sort {
            Instance => {
              let delta = instances
                .get(ex.sortidx.idx)
                .map(entry => entry.size)
                .unwrap_or(1)
              size = add_type_size(size, delta)
            }
            _ => size = add_type_size(size, 1)
          }
        }
        inst_sig = Some({ exports: map, nested: Map([]), })
        inst_size = size
        inst_type_idxs = Some(t_idxs)
        inst_func_idxs = Some(f_idxs)
        inst_type_map = Some(type_map)
        inst_type_sig_map = Some(type_sig_map)
        inst_func_sig_map = Some(func_map)
      }
    }
    instances.push({
      signature: inst_sig,
      size: inst_size,
      type_indices: inst_type_idxs,
      function_indices: inst_func_idxs,
      exported_types: inst_type_map,
      type_signatures: inst_type_sig_map,
      function_signatures: inst_func_sig_map,
      nested_type_signatures: inst_nested_type_sigs,
      nested_function_signatures: inst_nested_func_sigs,
      in_interface: false,
    })
    counts.instance += 1
  }
  next_resource_id
}
