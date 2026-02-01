///|
/// Compute a conservative nesting depth for defined types.
///
/// The component-spec suite expects a rejection for overly deep nesting even
/// when effective size is small (e.g. 101 nested `list` types).
fn valtype_nesting_depth(
  ty : @component.ValType,
  type_depths : Array[Int],
) -> Int {
  match ty {
    @component.ValType::Prim(_) => 0
    @component.ValType::TypeIdx(idx) =>
      if idx < 0 || idx >= type_depths.length() {
        0
      } else {
        type_depths[idx]
      }
  }
}

///|
fn effective_typedef_depth(
  td : @component.TypeDef,
  type_depths : Array[Int],
) -> Int {
  match td {
    // Base types contribute depth=1 so that chains like 101 nested `list`
    // typedefs trip the component-spec limit.
    @component.TypeDef::DefValType(_) => 1
    @component.TypeDef::FuncType(_) => 1
    @component.TypeDef::List(v) => 1 + valtype_nesting_depth(v, type_depths)
    @component.TypeDef::Option(v) => 1 + valtype_nesting_depth(v, type_depths)
    @component.TypeDef::Result(ok, err) => {
      let mut max_child = 0
      match ok {
        Some(v) => max_child = valtype_nesting_depth(v, type_depths)
        None => ()
      }
      match err {
        Some(v) => {
          let d = valtype_nesting_depth(v, type_depths)
          if d > max_child {
            max_child = d
          }
        }
        None => ()
      }
      1 + max_child
    }
    @component.TypeDef::Tuple(tys) => {
      let mut max_child = 0
      for v in tys {
        let d = valtype_nesting_depth(v, type_depths)
        if d > max_child {
          max_child = d
        }
      }
      1 + max_child
    }
    @component.TypeDef::Record(fields) => {
      let mut max_child = 0
      for f in fields {
        let d = valtype_nesting_depth(f.ty, type_depths)
        if d > max_child {
          max_child = d
        }
      }
      1 + max_child
    }
    @component.TypeDef::Variant(cases) => {
      let mut max_child = 0
      for c in cases {
        match c.ty {
          Some(v) => {
            let d = valtype_nesting_depth(v, type_depths)
            if d > max_child {
              max_child = d
            }
          }
          None => ()
        }
      }
      1 + max_child
    }
    // Types that are represented scalarly or don't contribute additional depth
    // beyond the base `1`.
    _ => 1
  }
}

///|
priv struct ValidatedComponentInfo {
  size : Int
  import_sorts : Map[String, @component.Sort]
  import_instance_sigs : Map[String, InstanceSig]
  import_func_sigs : Map[String, FuncSigShape]
  import_instance_resource_exports : Map[String, Map[String, Int]]
  import_type_bounds : Map[String, @component.TypeBound]
  import_type_sigs : Map[String, TypeSig]
  import_core_module_exports : Map[String, Map[String, Int]]
  import_core_module_import_sigs : Map[String, Map[String, CoreExternType]]
  export_sorts : Map[String, @component.Sort]
  export_instance_sigs : Map[String, InstanceSig]
  export_instance_type_sigs : Map[String, Map[String, TypeSig]]
  export_instance_func_sigs : Map[String, Map[String, FuncSigShape]]
  export_type_sigs : Map[String, TypeSig]
  export_func_sigs : Map[String, FuncSigShape]
}

///|
/// Validate a parsed component (partial).
fn validate_component_inner(
  component : @component.Component,
  is_root : Bool,
  cfg : ComponentValidationConfig,
  depth : Int,
  type_outers : Array[Array[@component.TypeDef?]],
  core_type_bound_outers : Array[Int],
  component_size_outers : Array[Array[Int]],
) -> ValidatedComponentInfo raise ComponentValidationError {
  let counts = Counts::new()
  let type_table : Array[@component.TypeDef?] = []
  // Track which type indices correspond to resource types defined in the
  // current concrete component (as opposed to imported/aliased resource types).
  let local_resource_types : Array[Bool] = []
  // Nominal identity ids for resource types (both defined and imported via `sub resource`).
  // These are local to this validation run, but used to detect mismatches across instantiation.
  let resource_ids : Array[Int?] = []
  let mut next_resource_id = 0
  let type_sizes : Array[Int] = []
  let type_depths : Array[Int] = []
  // Approximate export-signature size (used for wasm-tools' very-nested.wast).
  let component_sizes : Array[Int] = []
  let instance_sizes : Array[Int] = []
  let mut export_size = 1
  // Type indices that have names in the current interface namespace (type imports/exports).
  let named_types : Map[Int, Int] = {}
  // Type indices named by imports only (used to validate imports even if the
  // component's sections are reordered).
  let import_named_types : Map[Int, Int] = {}
  let core_type_exports : Array[Map[String, Int]?] = []
  let core_type_module_imports : Array[Array[CoreModuleTypeImport]?] = []
  let core_type_module_export_types : Array[Map[String, CoreExternType]?] = []
  let core_module_exports : Array[Map[String, Int]?] = []
  // Align core module definitions to the core-module index space (imports get None).
  let core_module_defs : Array[@types.Module?] = []
  let core_func_types : Array[@types.FuncType?] = []
  let core_module_export_types : Array[Map[String, CoreExternType]?] = []
  let core_module_type_imports : Array[Array[CoreModuleTypeImport]?] = []
  let core_instance_exports : Array[Map[String, Int]?] = []
  let core_instance_export_types : Array[Map[String, CoreExternType]?] = []
  let core_memory_types : Array[@types.MemoryType?] = []
  let component_import_sorts : Array[Map[String, @component.Sort]?] = []
  let component_import_instance_sigs : Array[Map[String, InstanceSig]?] = []
  let component_import_func_sigs : Array[Map[String, FuncSigShape]?] = []
  let component_import_instance_resource_exports : Array[
    Map[String, Map[String, Int]]?,
  ] = []
  let component_import_core_module_exports : Array[
    Map[String, Map[String, Int]]?,
  ] = []
  let component_import_core_module_import_sigs : Array[
    Map[String, Map[String, CoreExternType]]?,
  ] = []
  let component_import_type_bounds : Array[Map[String, @component.TypeBound]?] = []
  let component_import_type_sigs : Array[Map[String, TypeSig]?] = []
  let component_export_sorts : Array[Map[String, @component.Sort]?] = []
  let component_export_instance_sigs : Array[Map[String, InstanceSig]?] = []
  let component_export_instance_type_sigs : Array[
    Map[String, Map[String, TypeSig]]?,
  ] = []
  let component_export_instance_func_sigs : Array[
    Map[String, Map[String, FuncSigShape]]?,
  ] = []
  let component_export_type_sigs : Array[Map[String, TypeSig]?] = []
  let component_export_func_sigs : Array[Map[String, FuncSigShape]?] = []
  let instance_sigs : Array[InstanceSig?] = []
  // Instances that are part of this component's interface namespace (imports
  // plus export-introduced instance aliases).
  let interface_instance_idxs : Map[Int, Int] = {}
  let instance_export_type_idxs : Array[Array[Int]?] = []
  let instance_export_func_idxs : Array[Array[Int]?] = []
  let instance_export_type_map : Array[Map[String, ExportedTypeInfo]?] = []
  let instance_export_type_sigs : Array[Map[String, TypeSig]?] = []
  let instance_export_func_sigs : Array[Map[String, FuncSigShape]?] = []
  let instance_nested_instance_type_sigs : Array[
    Map[String, Map[String, TypeSig]]?,
  ] = []
  let instance_nested_instance_func_sigs : Array[
    Map[String, Map[String, FuncSigShape]]?,
  ] = []
  let func_types : Array[@component.FuncType?] = []
  let func_sig_shapes : Array[FuncSigShape?] = []
  let mut imported_funcs = 0
  let seen_import_names : Map[String, String] = {}
  let seen_export_names : Map[String, String] = {}
  // Resource-type names in the WIT interface namespace.
  let import_resource_names : Map[String, Int] = {}
  let export_resource_names : Map[String, Int] = {}

  // Signature tables for this component (returned to parent for instantiation validation).
  let my_import_sorts : Map[String, @component.Sort] = {}
  let my_import_instance_sigs : Map[String, InstanceSig] = {}
  let my_import_func_sigs : Map[String, FuncSigShape] = {}
  let my_import_instance_resource_exports : Map[String, Map[String, Int]] = {}
  let my_import_type_bounds : Map[String, @component.TypeBound] = {}
  let my_import_type_sigs : Map[String, TypeSig] = {}
  let my_export_sorts : Map[String, @component.Sort] = {}
  let my_export_instance_sigs : Map[String, InstanceSig] = {}
  let my_export_instance_type_sigs : Map[String, Map[String, TypeSig]] = {}
  let my_export_instance_func_sigs : Map[String, Map[String, FuncSigShape]] = {}
  let my_export_type_sigs : Map[String, TypeSig] = {}
  let my_export_func_sigs : Map[String, FuncSigShape] = {}
  for s in component.binary.sections {
    match s.id {
      // Core module/instance/type sections each declare a single core item.
      1 => {
        // Validate embedded core modules using the existing core validator.
        let core_mod = @parser.parse_module(s.payload) catch {
          e => raise CoreModuleError("parse core module: \{e}")
        }
        // wasm-tools expects duplicate import names in core modules to be invalid.
        let seen_imports : Map[String, Int] = {}
        for imp in core_mod.imports {
          let key = "\{imp.mod_name}:\{imp.name}"
          if seen_imports.get(key) is Some(_) {
            raise CoreModuleError("duplicate import name `\{key}`")
          }
          seen_imports.set(key, 1)
        }
        validate_module(core_mod) catch {
          e => raise CoreModuleError("validate core module: \{e}")
        }
        let exports : Map[String, Int] = {}
        let export_types : Map[String, CoreExternType] = {}
        for ex in core_mod.exports {
          match ex.desc {
            @types.ExportDesc::Func(_) => exports.set(ex.name, 0x00)
            @types.ExportDesc::Table(_) => exports.set(ex.name, 0x01)
            @types.ExportDesc::Memory(_) => exports.set(ex.name, 0x02)
            @types.ExportDesc::Global(_) => exports.set(ex.name, 0x03)
            @types.ExportDesc::Tag(_) => exports.set(ex.name, 0x04)
          }
          match core_export_type_of_module(core_mod, ex) {
            Some(t) => export_types.set(ex.name, t)
            None => ()
          }
        }
        core_module_exports.push(Some(exports))
        core_module_export_types.push(Some(export_types))
        core_module_type_imports.push(None)
        core_module_defs.push(Some(core_mod))
        counts.core_module += 1
      }
      2 => {
        let core_instances = @component.parse_core_instance_section(s.payload) catch {
          e => raise SectionParseError(2, "\{e}")
        }
        for inst in core_instances {
          let mut export_map : Map[String, Int]? = None
          let mut export_types : Map[String, CoreExternType]? = None
          match inst.expr {
            @component.CoreInstanceExpr::Instantiate(module_idx, args) => {
              if module_idx < 0 || module_idx >= counts.core_module {
                raise InvalidCoreModuleIndex(module_idx)
              }
              if module_idx >= 0 && module_idx < core_module_exports.length() {
                export_map = core_module_exports[module_idx]
              }
              if module_idx >= 0 &&
                module_idx < core_module_export_types.length() {
                export_types = core_module_export_types[module_idx]
              }
              // Validate that instantiation args satisfy the core module's
              // imports when we have enough type information (either a full
              // core module body, or a core module type signature).
              let providers : Map[String, Int] = {}
              let seen_arg_names : Map[String, Int] = {}
              for a in args {
                check_sortidx(a.sortidx, counts, type_table.length())
                if seen_arg_names.get(a.name) is Some(_) {
                  raise CoreModuleError(
                    "duplicate module instantiation argument named `\{a.name}`",
                  )
                }
                seen_arg_names.set(a.name, 1)
                match a.sortidx.sort {
                  @component.Sort::Core(0x12) =>
                    providers.set(a.name, a.sortidx.idx)
                  _ => ()
                }
              }
              let mod_def = if module_idx >= 0 &&
                module_idx < core_module_defs.length() {
                core_module_defs[module_idx]
              } else {
                None
              }
              match mod_def {
                Some(mod_) =>
                  for imp in mod_.imports {
                    match providers.get(imp.mod_name) {
                      None =>
                        raise CoreModuleError(
                          "module import `\{imp.mod_name}::\{imp.name}` not defined",
                        )
                      Some(provider_idx) => {
                        if provider_idx < 0 ||
                          provider_idx >= core_instance_export_types.length() {
                          raise InvalidCoreInstanceIndex(provider_idx)
                        }
                        let expected = core_import_type_of_module(
                          mod_,
                          imp.desc,
                        )
                        match expected {
                          None => ()
                          Some(exp_ty) => {
                            let expected_kind = core_kind_of_extern_type(exp_ty)
                            // Check presence/kind first (even if we don't have full type info).
                            if provider_idx < 0 ||
                              provider_idx >= core_instance_exports.length() {
                              raise InvalidCoreInstanceIndex(provider_idx)
                            }
                            match core_instance_exports[provider_idx] {
                              Some(kinds) =>
                                match kinds.get(imp.name) {
                                  None =>
                                    raise CoreModuleError(
                                      "module import `\{imp.mod_name}::\{imp.name}` not defined",
                                    )
                                  Some(actual_kind) =>
                                    if actual_kind != expected_kind {
                                      raise CoreModuleError(
                                        "module import `\{imp.mod_name}::\{imp.name}` has the wrong type",
                                      )
                                    }
                                }
                              None => ()
                            }
                            // If we also know full types, enforce type compatibility.
                            match core_instance_export_types[provider_idx] {
                              Some(map) =>
                                match map.get(imp.name) {
                                  Some(prov_ty) =>
                                    if !core_import_compatible(exp_ty, prov_ty) {
                                      raise CoreModuleError(
                                        "module import `\{imp.mod_name}::\{imp.name}` has the wrong type",
                                      )
                                    }
                                  None => ()
                                }
                              None => ()
                            }
                          }
                        }
                      }
                    }
                  }
                None =>
                  match
                    (if module_idx >= 0 &&
                      module_idx < core_module_type_imports.length() {
                      core_module_type_imports[module_idx]
                    } else {
                      None
                    }) {
                    Some(sigs) =>
                      for imp in sigs {
                        match providers.get(imp.mod_name) {
                          None =>
                            raise CoreModuleError(
                              "module import `\{imp.mod_name}::\{imp.name}` not defined",
                            )
                          Some(provider_idx) => {
                            if provider_idx < 0 ||
                              provider_idx >=
                              core_instance_export_types.length() {
                              raise InvalidCoreInstanceIndex(provider_idx)
                            }
                            let expected_kind = core_kind_of_extern_type(imp.ty)
                            if provider_idx < 0 ||
                              provider_idx >= core_instance_exports.length() {
                              raise InvalidCoreInstanceIndex(provider_idx)
                            }
                            match core_instance_exports[provider_idx] {
                              Some(kinds) =>
                                match kinds.get(imp.name) {
                                  None =>
                                    raise CoreModuleError(
                                      "module import `\{imp.mod_name}::\{imp.name}` not defined",
                                    )
                                  Some(actual_kind) =>
                                    if actual_kind != expected_kind {
                                      raise CoreModuleError(
                                        "module import `\{imp.mod_name}::\{imp.name}` has the wrong type",
                                      )
                                    }
                                }
                              None => ()
                            }
                            match core_instance_export_types[provider_idx] {
                              Some(map) =>
                                match map.get(imp.name) {
                                  Some(prov_ty) =>
                                    if !core_import_compatible(imp.ty, prov_ty) {
                                      raise CoreModuleError(
                                        "module import `\{imp.mod_name}::\{imp.name}` has the wrong type",
                                      )
                                    }
                                  None => ()
                                }
                              None => ()
                            }
                          }
                        }
                      }
                    None => ()
                  }
              }
            }
            @component.CoreInstanceExpr::InlineExports(inline_exports) => {
              let map : Map[String, Int] = {}
              for ex in inline_exports {
                check_sortidx(ex.sortidx, counts, type_table.length())
                if map.get(ex.name) is Some(_) {
                  raise DuplicateExportName(ex.name)
                }
                match ex.sortidx.sort {
                  @component.Sort::Core(core_sort) =>
                    map.set(ex.name, core_sort)
                  _ => ()
                }
              }
              export_map = Some(map)
            }
          }
          core_instance_exports.push(export_map)
          core_instance_export_types.push(export_types)
          counts.core_instance += 1
        }
      }
      3 => {
        // Validate core module type signatures, including `alias outer` bounds.
        // The `outer` depth counts enclosing component scopes.
        let max_outer_depth = depth + 1
        let base_core_type_bound = counts.core_type
        let exports = parse_core_type_section(
          s.payload,
          max_outer_depth,
          base_core_type_bound,
          core_type_bound_outers,
        )
        let (module_imports, module_export_types) = parse_core_type_section_module_sigs(
          s.payload,
          max_outer_depth,
          base_core_type_bound,
          core_type_bound_outers,
        )
        for e in exports {
          core_type_exports.push(e)
        }
        for m in module_imports {
          core_type_module_imports.push(m)
        }
        for t in module_export_types {
          core_type_module_export_types.push(t)
        }
        counts.core_type += exports.length()
      }
      4 => {
        // Nested component payloads are also component binaries.
        let nested = @component.parse_component(s.payload) catch {
          e => raise SectionParseError(4, "parse nested component: \{e}")
        }
        let nested_info = validate_component_inner(
          nested,
          false,
          cfg,
          depth + 1,
          [type_table] + type_outers,
          [counts.core_type] + core_type_bound_outers,
          [component_sizes] + component_size_outers,
        )
        component_import_sorts.push(Some(nested_info.import_sorts))
        component_import_instance_sigs.push(
          Some(nested_info.import_instance_sigs),
        )
        component_import_func_sigs.push(Some(nested_info.import_func_sigs))
        component_import_instance_resource_exports.push(
          Some(nested_info.import_instance_resource_exports),
        )
        component_import_core_module_exports.push(
          Some(nested_info.import_core_module_exports),
        )
        component_import_core_module_import_sigs.push(
          Some(nested_info.import_core_module_import_sigs),
        )
        component_import_type_bounds.push(Some(nested_info.import_type_bounds))
        component_import_type_sigs.push(Some(nested_info.import_type_sigs))
        component_export_sorts.push(Some(nested_info.export_sorts))
        component_export_instance_sigs.push(
          Some(nested_info.export_instance_sigs),
        )
        component_export_instance_type_sigs.push(
          Some(nested_info.export_instance_type_sigs),
        )
        component_export_instance_func_sigs.push(
          Some(nested_info.export_instance_func_sigs),
        )
        component_export_type_sigs.push(Some(nested_info.export_type_sigs))
        component_export_func_sigs.push(Some(nested_info.export_func_sigs))
        component_sizes.push(nested_info.size)
        // Nested component definitions contribute to the overall effective
        // size of the component graph (wasm-tools/very-nested.wast).
        export_size = add_type_size(export_size, nested_info.size)
        counts.component += 1
      }
      7 => {
        // Definitions extend the type index space.
        let defs = @component.parse_type_section(s.payload) catch {
          e => raise SectionParseError(7, "\{e}")
        }
        for d in defs {
          // This is still a subset: we only allow referencing earlier types.
          validate_typedef(
            d,
            cfg,
            [type_table] + type_outers,
            [core_type_exports],
            true,
          )
          // Resource types refer to the core-func index space for their dtor.
          // Validate bounds/signature here where we have access to the current
          // core-func types.
          match d {
            @component.TypeDef::ResourceType(_, _rep, dtor_idx, _kind) =>
              match dtor_idx {
                Some(idx) =>
                  if idx < 0 || idx >= counts.core_func {
                    raise SectionParseError(7, "function index out of bounds")
                  } else {
                    match core_func_types.get(idx) {
                      Some(Some(ft)) => {
                        let expected : @types.FuncType = {
                          params: [@types.ValueType::I32],
                          results: [],
                        }
                        if ft != expected {
                          raise SectionParseError(
                            7, "wrong signature for a destructor",
                          )
                        }
                      }
                      _ => ()
                    }
                  }
                None => ()
              }
            _ => ()
          }
          let size = effective_typedef_size(d, type_sizes)
          if size > 100000 {
            raise SectionParseError(7, "effective type size exceeds the limit")
          }
          let depth = effective_typedef_depth(d, type_depths)
          if depth > 100 {
            raise SectionParseError(7, "type nesting is too deep")
          }
          type_table.push(Some(d))
          local_resource_types.push(
            d is @component.TypeDef::ResourceType(_, _, _, _),
          )
          match d {
            @component.TypeDef::ResourceType(_, _, _, _) => {
              resource_ids.push(Some(next_resource_id))
              next_resource_id += 1
            }
            _ => resource_ids.push(None)
          }
          type_sizes.push(size)
          type_depths.push(depth)
        }
      }
      10 => {
        let (new_next_resource_id, new_imported_funcs) = validate_component_section_import(
          s.payload,
          cfg,
          is_root,
          counts,
          type_table,
          local_resource_types,
          resource_ids,
          type_sizes,
          type_depths,
          component_sizes,
          instance_sizes,
          named_types,
          import_named_types,
          core_type_exports,
          core_type_module_imports,
          core_type_module_export_types,
          core_module_exports,
          core_module_defs,
          core_module_export_types,
          core_module_type_imports,
          component_import_sorts,
          component_import_instance_sigs,
          component_import_func_sigs,
          component_import_instance_resource_exports,
          component_import_core_module_exports,
          component_import_core_module_import_sigs,
          component_import_type_bounds,
          component_import_type_sigs,
          component_export_sorts,
          component_export_instance_sigs,
          component_export_instance_type_sigs,
          component_export_instance_func_sigs,
          component_export_type_sigs,
          component_export_func_sigs,
          instance_sigs,
          interface_instance_idxs,
          instance_export_type_idxs,
          instance_export_func_idxs,
          instance_export_type_map,
          instance_export_type_sigs,
          instance_export_func_sigs,
          instance_nested_instance_type_sigs,
          instance_nested_instance_func_sigs,
          func_types,
          func_sig_shapes,
          seen_import_names,
          import_resource_names,
          my_import_sorts,
          my_import_instance_sigs,
          my_import_func_sigs,
          my_import_instance_resource_exports,
          my_import_type_bounds,
          my_import_type_sigs,
          type_outers,
          next_resource_id,
          imported_funcs,
        )
        next_resource_id = new_next_resource_id
        imported_funcs = new_imported_funcs
      }
      11 =>
        export_size = validate_component_section_export(
          s.payload,
          cfg,
          is_root,
          counts,
          type_table,
          local_resource_types,
          resource_ids,
          type_sizes,
          type_depths,
          component_sizes,
          instance_sizes,
          export_size,
          named_types,
          core_module_exports,
          core_module_defs,
          core_func_types,
          core_module_export_types,
          core_module_type_imports,
          core_instance_exports,
          core_instance_export_types,
          core_memory_types,
          component_import_sorts,
          component_import_instance_sigs,
          component_import_func_sigs,
          component_import_instance_resource_exports,
          component_import_core_module_exports,
          component_import_core_module_import_sigs,
          component_import_type_bounds,
          component_import_type_sigs,
          component_export_sorts,
          component_export_instance_sigs,
          component_export_instance_type_sigs,
          component_export_instance_func_sigs,
          component_export_type_sigs,
          component_export_func_sigs,
          instance_sigs,
          interface_instance_idxs,
          instance_export_type_idxs,
          instance_export_func_idxs,
          instance_export_type_map,
          instance_export_type_sigs,
          instance_export_func_sigs,
          instance_nested_instance_type_sigs,
          instance_nested_instance_func_sigs,
          func_types,
          func_sig_shapes,
          imported_funcs,
          seen_export_names,
          export_resource_names,
          my_export_sorts,
          my_export_instance_sigs,
          my_export_instance_type_sigs,
          my_export_instance_func_sigs,
          my_export_type_sigs,
          my_export_func_sigs,
          type_outers,
        )
      5 =>
        next_resource_id = validate_component_section_instance(
          s.payload,
          cfg,
          counts,
          type_table,
          resource_ids,
          component_sizes,
          instance_sizes,
          core_module_exports,
          core_module_defs,
          core_module_type_imports,
          component_import_sorts,
          component_import_instance_sigs,
          component_import_func_sigs,
          component_import_instance_resource_exports,
          component_import_core_module_exports,
          component_import_core_module_import_sigs,
          component_import_type_bounds,
          component_import_type_sigs,
          component_export_sorts,
          component_export_instance_sigs,
          component_export_instance_type_sigs,
          component_export_instance_func_sigs,
          component_export_type_sigs,
          component_export_func_sigs,
          instance_sigs,
          instance_export_type_idxs,
          instance_export_func_idxs,
          instance_export_type_map,
          instance_export_type_sigs,
          instance_export_func_sigs,
          instance_nested_instance_type_sigs,
          instance_nested_instance_func_sigs,
          func_types,
          func_sig_shapes,
          next_resource_id,
        )
      6 =>
        validate_component_section_alias(
          s.payload,
          counts,
          type_table,
          local_resource_types,
          resource_ids,
          type_sizes,
          type_depths,
          component_sizes,
          instance_sizes,
          named_types,
          core_module_exports,
          core_module_defs,
          core_func_types,
          core_module_export_types,
          core_module_type_imports,
          core_instance_exports,
          core_instance_export_types,
          core_memory_types,
          component_import_sorts,
          component_import_instance_sigs,
          component_import_func_sigs,
          component_import_instance_resource_exports,
          component_import_core_module_exports,
          component_import_core_module_import_sigs,
          component_import_type_bounds,
          component_import_type_sigs,
          component_export_sorts,
          component_export_instance_sigs,
          component_export_instance_type_sigs,
          component_export_instance_func_sigs,
          component_export_type_sigs,
          component_export_func_sigs,
          instance_sigs,
          interface_instance_idxs,
          instance_export_type_idxs,
          instance_export_func_idxs,
          instance_export_type_map,
          instance_export_type_sigs,
          instance_export_func_sigs,
          instance_nested_instance_type_sigs,
          instance_nested_instance_func_sigs,
          func_types,
          func_sig_shapes,
          type_outers,
          component_size_outers,
        )
      8 => {
        let canons = @component.parse_canon_section(s.payload) catch {
          e => raise SectionParseError(8, "\{e}")
        }
        for c in canons {
          validate_canon(
            c,
            type_table,
            local_resource_types,
            type_table.length(),
            core_memory_types,
            core_func_types,
            func_types,
          )
          count_canon(c, counts)
          match c {
            @component.Canon::Lift(_, _, tyidx) =>
              match type_table[tyidx] {
                Some(@component.TypeDef::FuncType(ft)) => {
                  func_types.push(Some(ft))
                  func_sig_shapes.push(
                    Some(funcsig_of_functype(ft, type_table, resource_ids)),
                  )
                }
                _ => {
                  func_types.push(None)
                  func_sig_shapes.push(None)
                }
              }
            // All non-lift canonical items append a core function to the core-func
            // index space, but we don't (yet) model their signatures here.
            _ => core_func_types.push(None)
          }
        }
      }
      9 => {
        let start = @component.parse_start_section(s.payload) catch {
          e => raise SectionParseError(9, "\{e}")
        }
        if start.func_idx < 0 || start.func_idx >= counts.func {
          raise InvalidFuncIndex(start.func_idx)
        }
      }
      _ => ()
    }
  }
  if export_size > 100000 {
    raise SectionParseError(11, "effective type size exceeds the limit")
  }
  {
    size: export_size,
    import_sorts: my_import_sorts,
    import_instance_sigs: my_import_instance_sigs,
    import_func_sigs: my_import_func_sigs,
    import_instance_resource_exports: my_import_instance_resource_exports,
    import_type_bounds: my_import_type_bounds,
    import_type_sigs: my_import_type_sigs,
    import_core_module_exports: component_import_core_module_exports_of(
      component,
    ),
    import_core_module_import_sigs: component_import_core_module_import_sigs_of(
      component,
    ),
    export_sorts: my_export_sorts,
    export_instance_sigs: my_export_instance_sigs,
    export_instance_type_sigs: my_export_instance_type_sigs,
    export_instance_func_sigs: my_export_instance_func_sigs,
    export_type_sigs: my_export_type_sigs,
    export_func_sigs: my_export_func_sigs,
  }
}

///|
pub fn validate_component(
  component : @component.Component,
) -> Unit raise ComponentValidationError {
  validate_component_with_config(
    component,
    ComponentValidationConfig::default(),
  )
}

///|
pub fn validate_component_with_config(
  component : @component.Component,
  cfg : ComponentValidationConfig,
) -> Unit raise ComponentValidationError {
  validate_component_inner(component, true, cfg, 0, [], [], []) |> ignore
}
