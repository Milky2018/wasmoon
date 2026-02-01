///|
/// Handle component instance section (id 5).
fn validate_component_section_instance(
  payload : Bytes,
  cfg : ComponentValidationConfig,
  counts : Counts,
  type_table : Array[@component.TypeDef?],
  resource_ids : Array[Int?],
  component_sizes : Array[Int],
  instance_sizes : Array[Int],
  core_module_exports : Array[Map[String, Int]?],
  core_module_defs : Array[@types.Module?],
  core_module_type_imports : Array[Array[CoreModuleTypeImport]?],
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
  next_resource_id : Int,
) -> Int raise ComponentValidationError {
  let mut next_resource_id = next_resource_id
  let instances = @component.parse_instance_section(payload) catch {
    e => raise SectionParseError(5, "\{e}")
  }
  for inst in instances {
    let mut inst_sig : InstanceSig? = None
    let mut inst_size = 1
    let mut inst_type_idxs : Array[Int]? = None
    let mut inst_func_idxs : Array[Int]? = None
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
        if component_idx >= 0 && component_idx < component_sizes.length() {
          inst_size = component_sizes[component_idx]
        } else {
          inst_size = 1
        }
        // Validate instantiation args against the component's import
        // signature when available.
        let expected_imports = if component_idx >= 0 &&
          component_idx < component_import_sorts.length() {
          component_import_sorts[component_idx]
        } else {
          None
        }
        let expected_import_instance_sigs = if component_idx >= 0 &&
          component_idx < component_import_instance_sigs.length() {
          component_import_instance_sigs[component_idx]
        } else {
          None
        }
        let expected_import_func_sigs = if component_idx >= 0 &&
          component_idx < component_import_func_sigs.length() {
          component_import_func_sigs[component_idx]
        } else {
          None
        }
        let expected_import_core_modules = if component_idx >= 0 &&
          component_idx < component_import_core_module_exports.length() {
          component_import_core_module_exports[component_idx]
        } else {
          None
        }
        let expected_import_core_module_import_sigs = if component_idx >= 0 &&
          component_idx < component_import_core_module_import_sigs.length() {
          component_import_core_module_import_sigs[component_idx]
        } else {
          None
        }
        let expected_import_type_sigs = if component_idx >= 0 &&
          component_idx < component_import_type_sigs.length() {
          component_import_type_sigs[component_idx]
        } else {
          None
        }
        let expected_import_type_bounds = if component_idx >= 0 &&
          component_idx < component_import_type_bounds.length() {
          component_import_type_bounds[component_idx]
        } else {
          None
        }
        let expected_import_instance_resource_exports = if component_idx >= 0 &&
          component_idx < component_import_instance_resource_exports.length() {
          component_import_instance_resource_exports[component_idx]
        } else {
          None
        }
        let pending_type_args : Array[(String, Int)] = []
        let pending_func_args : Array[(String, Int)] = []
        let pending_instance_args : Array[(String, Int)] = []
        let seen_args : Map[String, Int] = {}
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
                    if sort is @component.Sort::Func {
                      pending_func_args.push((a.name, a.sortidx.idx))
                    }
                    if sort is @component.Sort::Instance {
                      pending_instance_args.push((a.name, a.sortidx.idx))
                    }
                    match (sort, expected_import_instance_sigs) {
                      (@component.Sort::Instance, Some(sig_map)) =>
                        match sig_map.get(a.name) {
                          Some(req) => {
                            let actual = if a.sortidx.idx >= 0 &&
                              a.sortidx.idx < instance_sigs.length() {
                              instance_sigs[a.sortidx.idx]
                            } else {
                              None
                            }
                            check_instance_subtype(actual, req)
                          }
                          None => ()
                        }
                      _ => ()
                    }
                    match (sort, expected_import_core_modules) {
                      (@component.Sort::Core(0x11), Some(core_map)) =>
                        match core_map.get(a.name) {
                          Some(req) =>
                            if a.sortidx.idx >= 0 &&
                              a.sortidx.idx < core_module_exports.length() {
                              check_core_module_subtype(
                                core_module_exports[a.sortidx.idx],
                                req,
                              )
                            } else {
                              ()
                            }
                          None => ()
                        }
                      _ => ()
                    }
                    match (sort, expected_import_core_module_import_sigs) {
                      (@component.Sort::Core(0x11), Some(sig_map)) =>
                        match sig_map.get(a.name) {
                          Some(req) => {
                            let actual_sig = core_module_import_sig_of_idx(
                              a.sortidx.idx,
                              core_module_defs,
                              core_module_type_imports,
                            )
                            check_core_module_import_subtype(actual_sig, req)
                          }
                          None => ()
                        }
                      _ => ()
                    }
                    if sort is @component.Sort::Type {
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
        let rid_subst : Map[Int, Int] = {}
        match expected_import_instance_resource_exports {
          Some(inst_map) =>
            for kv in pending_instance_args {
              let (name, inst_idx) = kv
              match inst_map.get(name) {
                Some(exports) =>
                  for kv2 in exports.iter() {
                    let (tname, expected_rid) = kv2
                    let tmap = if inst_idx >= 0 &&
                      inst_idx < instance_export_type_map.length() {
                      instance_export_type_map[inst_idx]
                    } else {
                      None
                    }
                    match tmap {
                      Some(map) =>
                        match map.get(tname) {
                          Some(ExportedTypeInfo::Resource(actual_rid)) =>
                            rid_subst.set(expected_rid, actual_rid)
                          Some(ExportedTypeInfo::Existing(tidx)) =>
                            match
                              type_sig_of_typeidx(
                                tidx, type_table, resource_ids,
                              ) {
                              TypeSig::Resource(actual_rid) =>
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
                Some(@component.TypeBound::SubResource) =>
                  match sigs.get(name) {
                    Some(TypeSig::Resource(expected_rid)) => {
                      let actual_sig = type_sig_of_typeidx(
                        idx, type_table, resource_ids,
                      )
                      match actual_sig {
                        TypeSig::Resource(actual_rid) =>
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
                Some(@component.TypeBound::Eq(_)) =>
                  match sigs.get(name) {
                    Some(req0) => {
                      let req = type_sig_subst_resources(req0, rid_subst)
                      let actual = type_sig_of_typeidx(
                        idx, type_table, resource_ids,
                      )
                      if actual != req {
                        match (req, actual) {
                          (TypeSig::Resource(_), TypeSig::Resource(_)) =>
                            raise SectionParseError(
                              5, "resource types are not the same",
                            )
                          (TypeSig::Resource(_), _) =>
                            raise SectionParseError(
                              5, "expected resource, found defined type",
                            )
                          (_, TypeSig::Resource(_)) =>
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
                                actual, type_table, resource_ids,
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
        if component_idx >= 0 && component_idx < component_export_sorts.length() {
          match component_export_sorts[component_idx] {
            Some(exports) => {
              let nested = if component_idx >= 0 &&
                component_idx < component_export_instance_sigs.length() {
                match component_export_instance_sigs[component_idx] {
                  Some(m) => m
                  None => {}
                }
              } else {
                {}
              }
              inst_sig = Some({ exports, nested })
            }
            None => ()
          }
        }

        // Track exported types so `(alias export $inst "t" (type $x))` can
        // resolve resource identities (wasm-tools/resources.wast).
        if component_idx >= 0 &&
          component_idx < component_export_type_sigs.length() {
          match component_export_type_sigs[component_idx] {
            Some(sig_map) => {
              let out : Map[String, ExportedTypeInfo] = {}
              let sig_out : Map[String, TypeSig] = {}
              for kv in sig_map.iter() {
                let (name, sig0) = kv
                sig_out.set(name, type_sig_subst_resources(sig0, rid_subst))
                match sig0 {
                  TypeSig::Resource(rid0) =>
                    match rid_subst.get(rid0) {
                      Some(actual_rid) => {
                        let mut found : Int? = None
                        for i in 0..<type_table.length() {
                          if type_sig_of_typeidx(i, type_table, resource_ids) ==
                            TypeSig::Resource(actual_rid) {
                            found = Some(i)
                            break
                          }
                        }
                        match found {
                          Some(idx) =>
                            out.set(name, ExportedTypeInfo::Existing(idx))
                          None =>
                            out.set(
                              name,
                              ExportedTypeInfo::Resource(actual_rid),
                            )
                        }
                      }
                      None => {
                        let rid = next_resource_id
                        next_resource_id += 1
                        rid_subst.set(rid0, rid)
                        out.set(name, ExportedTypeInfo::Resource(rid))
                      }
                    }
                  _ => {
                    let sig = type_sig_subst_resources(sig0, rid_subst)
                    let mut found : Int? = None
                    for i in 0..<type_table.length() {
                      if type_sig_of_typeidx(i, type_table, resource_ids) == sig {
                        found = Some(i)
                        break
                      }
                    }
                    match found {
                      Some(idx) =>
                        out.set(name, ExportedTypeInfo::Existing(idx))
                      None => out.set(name, ExportedTypeInfo::Opaque)
                    }
                  }
                }
              }
              inst_type_map = Some(out)
              inst_type_sig_map = Some(sig_out)
            }
            None => ()
          }
        }
        if component_idx >= 0 &&
          component_idx < component_export_func_sigs.length() {
          match component_export_func_sigs[component_idx] {
            Some(sig_map) => {
              let out : Map[String, FuncSigShape] = {}
              for kv in sig_map.iter() {
                let (name, sig0) = kv
                out.set(name, funcsig_subst_resources(sig0, rid_subst))
              }
              inst_func_sig_map = Some(out)
            }
            None => ()
          }
        }
        if component_idx >= 0 &&
          component_idx < component_export_instance_type_sigs.length() {
          match component_export_instance_type_sigs[component_idx] {
            Some(inst_map0) => {
              let out : Map[String, Map[String, TypeSig]] = {}
              for kv in inst_map0.iter() {
                let (inst_name, types0) = kv
                let types : Map[String, TypeSig] = {}
                for kv2 in types0.iter() {
                  let (name, sig0) = kv2
                  types.set(name, type_sig_subst_resources(sig0, rid_subst))
                }
                out.set(inst_name, types)
              }
              inst_nested_type_sigs = Some(out)
            }
            None => ()
          }
        }
        if component_idx >= 0 &&
          component_idx < component_export_instance_func_sigs.length() {
          match component_export_instance_func_sigs[component_idx] {
            Some(inst_map0) => {
              let out : Map[String, Map[String, FuncSigShape]] = {}
              for kv in inst_map0.iter() {
                let (inst_name, funcs0) = kv
                let funcs : Map[String, FuncSigShape] = {}
                for kv2 in funcs0.iter() {
                  let (name, sig0) = kv2
                  funcs.set(name, funcsig_subst_resources(sig0, rid_subst))
                }
                out.set(inst_name, funcs)
              }
              inst_nested_func_sigs = Some(out)
            }
            None => ()
          }
        }
      }
      InlineExports(inline_exports) => {
        let map : Map[String, @component.Sort] = {}
        let mut size = 1
        let t_idxs : Array[Int] = []
        let f_idxs : Array[Int] = []
        let type_map : Map[String, ExportedTypeInfo] = {}
        let type_sig_map : Map[String, TypeSig] = {}
        let func_map : Map[String, FuncSigShape] = {}
        for ex in inline_exports {
          check_sortidx(ex.sortidx, counts, type_table.length())
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
            @component.Sort::Type => {
              t_idxs.push(ex.sortidx.idx)
              type_map.set(ex.name, ExportedTypeInfo::Existing(ex.sortidx.idx))
              type_sig_map.set(
                ex.name,
                type_sig_of_typeidx(ex.sortidx.idx, type_table, resource_ids),
              )
            }
            @component.Sort::Func => {
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
                          funcsig_of_functype(ft, type_table, resource_ids),
                        )
                      None => ()
                    }
                  }
              }
            }
            _ => ()
          }
          match ex.sortidx.sort {
            @component.Sort::Instance => {
              let delta = if ex.sortidx.idx >= 0 &&
                ex.sortidx.idx < instance_sizes.length() {
                instance_sizes[ex.sortidx.idx]
              } else {
                1
              }
              size = add_type_size(size, delta)
            }
            _ => size = add_type_size(size, 1)
          }
        }
        inst_sig = Some({ exports: map, nested: {} })
        inst_size = size
        inst_type_idxs = Some(t_idxs)
        inst_func_idxs = Some(f_idxs)
        inst_type_map = Some(type_map)
        inst_type_sig_map = Some(type_sig_map)
        inst_func_sig_map = Some(func_map)
      }
    }
    instance_sigs.push(inst_sig)
    instance_sizes.push(inst_size)
    instance_export_type_idxs.push(inst_type_idxs)
    instance_export_func_idxs.push(inst_func_idxs)
    instance_export_type_map.push(inst_type_map)
    instance_export_type_sigs.push(inst_type_sig_map)
    instance_export_func_sigs.push(inst_func_sig_map)
    instance_nested_instance_type_sigs.push(inst_nested_type_sigs)
    instance_nested_instance_func_sigs.push(inst_nested_func_sigs)
    counts.instance += 1
  }
  next_resource_id
}
