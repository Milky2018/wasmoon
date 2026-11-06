///|
/// Compute a conservative nesting depth for defined types.
///
/// The component-spec suite expects a rejection for overly deep nesting even
/// when effective size is small (e.g. 101 nested `list` types).
fn valtype_nesting_depth(
  ty : @component.ValType,
  type_depths : Array[Int32],
) -> Int32 {
  match ty {
    Prim(_) => 0
    TypeIdx(idx) =>
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
  type_depths : Array[Int32],
) -> Int32 {
  match td {
    // Base types contribute depth=1 so that chains like 101 nested `list`
    // typedefs trip the component-spec limit.
    DefValType(_) => 1
    FuncType(_) => 1
    List(v) => 1 + valtype_nesting_depth(v, type_depths)
    Option(v) => 1 + valtype_nesting_depth(v, type_depths)
    Result(ok, err) => {
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
    Tuple(tys) => {
      let mut max_child = 0
      for v in tys {
        let d = valtype_nesting_depth(v, type_depths)
        if d > max_child {
          max_child = d
        }
      }
      1 + max_child
    }
    Record(fields) => {
      let mut max_child = 0
      for f in fields {
        let d = valtype_nesting_depth(f.ty, type_depths)
        if d > max_child {
          max_child = d
        }
      }
      1 + max_child
    }
    Variant(cases) => {
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
priv struct CoreInstanceIndexEntry {
  export_kinds : Map[String, Int32]?
  export_types : Map[String, CoreExternType]?
}

///|
fn CoreInstanceIndexEntry::unknown() -> CoreInstanceIndexEntry {
  { export_kinds: None, export_types: None, }
}

///|
priv struct CoreModuleIndexEntry {
  definition : @types.Module?
  export_kinds : Map[String, Int32]?
  export_types : Map[String, CoreExternType]?
  import_types : Array[CoreModuleTypeImport]?
}

///|
fn CoreModuleIndexEntry::unknown() -> CoreModuleIndexEntry {
  {
    definition: None,
    export_kinds: None,
    export_types: None,
    import_types: None,
  }
}

///|
priv struct InstanceIndexEntry {
  signature : InstanceSig?
  size : Int32
  type_indices : Array[Int32]?
  function_indices : Array[Int32]?
  exported_types : Map[String, ExportedTypeInfo]?
  type_signatures : Map[String, TypeSig]?
  function_signatures : Map[String, FuncSigShape]?
  nested_type_signatures : Map[String, Map[String, TypeSig]]?
  nested_function_signatures : Map[String, Map[String, FuncSigShape]]?
  in_interface : Bool
}

///|
// Imports and exports add interface instances. Other entries only contribute
// to the instance index space and do not name types in the interface.
fn InstanceIndexEntry::unknown() -> InstanceIndexEntry {
  {
    signature: None,
    size: 1,
    type_indices: None,
    function_indices: None,
    exported_types: None,
    type_signatures: None,
    function_signatures: None,
    nested_type_signatures: None,
    nested_function_signatures: None,
    in_interface: false,
  }
}

///|
priv struct ComponentIndexEntry {
  size : Int32
  import_sorts : Map[String, @component.Sort]?
  import_instance_sigs : Map[String, InstanceSig]?
  import_func_sigs : Map[String, FuncSigShape]?
  import_instance_resource_exports : Map[String, Map[String, Int32]]?
  import_type_bounds : Map[String, @component.TypeBound]?
  import_type_sigs : Map[String, TypeSig]?
  import_core_modules : Map[String, CoreModuleRequirement]?
  export_sorts : Map[String, @component.Sort]?
  export_instance_sigs : Map[String, InstanceSig]?
  export_instance_type_sigs : Map[String, Map[String, TypeSig]]?
  export_instance_func_sigs : Map[String, Map[String, FuncSigShape]]?
  export_type_sigs : Map[String, TypeSig]?
  export_func_sigs : Map[String, FuncSigShape]?
}

///|
fn ComponentIndexEntry::unknown(size : Int32) -> ComponentIndexEntry {
  {
    size,
    import_sorts: None,
    import_instance_sigs: None,
    import_func_sigs: None,
    import_instance_resource_exports: None,
    import_core_modules: None,
    import_type_bounds: None,
    import_type_sigs: None,
    export_sorts: None,
    export_instance_sigs: None,
    export_instance_type_sigs: None,
    export_instance_func_sigs: None,
    export_type_sigs: None,
    export_func_sigs: None,
  }
}

///|
/// Validate a parsed component (partial).
fn validate_component_inner(
  component : @component.Component,
  is_root : Bool,
  cfg : ComponentValidationConfig,
  depth : Int32,
  type_outers : Array[Array[@component.TypeDef?]],
  type_outer_depths : Array[Int32],
  core_type_outers : Array[Array[CoreModuleTypeSignature?]],
  component_outers : Array[Array[ComponentIndexEntry]],
) -> ComponentIndexEntry raise ComponentValidationError {
  let counts = Counts::Counts()
  let type_table : Array[@component.TypeDef?] = []
  let known_type_sigs : Map[Int32, TypeSig] = Map([])
  // Track which type indices correspond to resource types defined in the
  // current concrete component (as opposed to imported/aliased resource types).
  let local_resource_types : Array[Bool] = []
  // Nominal identity ids for resource types (both defined and imported via `sub resource`).
  // These are local to this validation run, but used to detect mismatches across instantiation.
  let resource_ids : Array[Int32?] = []
  let mut next_resource_id = 0
  let type_sizes : Array[Int32] = []
  let type_depths : Array[Int32] = []
  // Approximate export-signature size (used for wasm-tools' very-nested.wast).
  let components : Array[ComponentIndexEntry] = []
  let mut export_size = 1
  // Type indices that have names in the current interface namespace (type imports/exports).
  let named_types : Map[Int32, Int32] = Map([])
  // Type indices named by imports only (used to validate imports even if the
  // component's sections are reordered).
  let import_named_types : Map[Int32, Int32] = Map([])
  let core_types : Array[CoreModuleTypeSignature?] = []
  let core_type_bounds = core_type_outers.map(scope => scope.length())
  let core_modules : Array[CoreModuleIndexEntry] = []
  let core_func_types : Array[@types.FuncType?] = []
  let core_instances : Array[CoreInstanceIndexEntry] = []
  let core_memory_types : Array[@types.MemoryType?] = []
  let instances : Array[InstanceIndexEntry] = []
  let func_types : Array[@component.FuncType?] = []
  let func_sig_shapes : Array[FuncSigShape?] = []
  let mut imported_funcs = 0
  let seen_import_names : Map[String, String] = Map([])
  let seen_export_names : Map[String, String] = Map([])
  // Resource-type names in the WIT interface namespace.
  let import_resource_names : Map[String, Int32] = Map([])
  let export_resource_names : Map[String, Int32] = Map([])

  // Signature tables for this component (returned to parent for instantiation validation).
  let my_import_sorts : Map[String, @component.Sort] = Map([])
  let my_import_core_modules : Map[String, CoreModuleRequirement] = Map([])
  let my_import_instance_sigs : Map[String, InstanceSig] = Map([])
  let my_import_func_sigs : Map[String, FuncSigShape] = Map([])
  let my_import_instance_resource_exports : Map[String, Map[String, Int32]] = Map([],
  )
  let my_import_type_bounds : Map[String, @component.TypeBound] = Map([])
  let my_import_type_sigs : Map[String, TypeSig] = Map([])
  let my_export_sorts : Map[String, @component.Sort] = Map([])
  let my_export_instance_sigs : Map[String, InstanceSig] = Map([])
  let my_export_instance_type_sigs : Map[String, Map[String, TypeSig]] = Map([])
  let my_export_instance_func_sigs : Map[String, Map[String, FuncSigShape]] = Map([],
  )
  let my_export_type_sigs : Map[String, TypeSig] = Map([])
  let my_export_func_sigs : Map[String, FuncSigShape] = Map([])
  for s in component.binary.sections {
    match s.id {
      // Core module/instance/type sections each declare a single core item.
      1 => {
        // Validate embedded core modules using the existing core validator.
        if @component.sniff_binary_kind(s.payload) != Some(CoreModule) {
          raise CoreModuleError("unknown binary version")
        }
        let core_mod = @parser.parse_module(s.payload) catch {
          e => raise CoreModuleError("parse core module: \{e}")
        }
        // wasm-tools expects duplicate import names in core modules to be invalid.
        let seen_imports : Map[String, Int32] = Map([])
        for imp in core_mod.imports {
          let key = "\{imp.mod_name}:\{imp.name}"
          if seen_imports.get(key) is Some(_) {
            raise CoreModuleError("duplicate import name `\{key}`")
          }
          seen_imports.set(key, 1)
        }
        @core_validator.validate_module(core_mod) catch {
          e => raise CoreModuleError("validate core module: \{e}")
        }
        let exports : Map[String, Int32] = Map([])
        let export_types : Map[String, CoreExternType] = Map([])
        for ex in core_mod.exports {
          match ex.desc {
            Func(_) => exports.set(ex.name, 0x00)
            Table(_) => exports.set(ex.name, 0x01)
            Memory(_) => exports.set(ex.name, 0x02)
            Global(_) => exports.set(ex.name, 0x03)
            Tag(_) => exports.set(ex.name, 0x04)
          }
          match core_export_type_of_module(core_mod, ex) {
            Some(t) => export_types.set(ex.name, t)
            None => ()
          }
        }
        core_modules.push({
          definition: Some(core_mod),
          export_kinds: Some(exports),
          export_types: Some(export_types),
          import_types: None,
        })
        counts.core_module += 1
      }
      2 => {
        let declarations = @component.parse_core_instance_section(s.payload) catch {
          e => raise SectionParseError(2, "\{e}")
        }
        for inst in declarations {
          let mut export_map : Map[String, Int32]? = None
          let mut export_types : Map[String, CoreExternType]? = None
          match inst.expr {
            Instantiate(module_idx, args) => {
              if module_idx < 0 || module_idx >= counts.core_module {
                raise InvalidCoreModuleIndex(module_idx)
              }
              let entry = core_modules
                .get(module_idx)
                .unwrap_or_else(CoreModuleIndexEntry::unknown)
              export_map = entry.export_kinds
              export_types = entry.export_types
              // Validate that instantiation args satisfy the core module's
              // imports when we have enough type information (either a full
              // core module body, or a core module type signature).
              let providers : Map[String, Int32] = Map([])
              let seen_arg_names : Map[String, Int32] = Map([])
              for a in args {
                check_sortidx(a.sortidx, counts, type_table.length())
                if seen_arg_names.get(a.name) is Some(_) {
                  raise CoreModuleError(
                    "duplicate module instantiation argument named `\{a.name}`",
                  )
                }
                seen_arg_names.set(a.name, 1)
                match a.sortidx.sort {
                  Core(0x12) => providers.set(a.name, a.sortidx.idx)
                  _ => ()
                }
              }
              match entry.definition {
                Some(module_) =>
                  for imp in module_.imports {
                    check_core_module_provider(
                      imp.mod_name,
                      imp.name,
                      core_import_type_of_module(module_, imp.desc),
                      providers,
                      core_instances,
                    )
                  }
                None =>
                  if entry.import_types is Some(imports) {
                    for imp in imports {
                      check_core_module_provider(
                        imp.mod_name,
                        imp.name,
                        Some(imp.ty),
                        providers,
                        core_instances,
                      )
                    }
                  }
              }
            }
            InlineExports(inline_exports) => {
              let map : Map[String, Int32] = Map([])
              let type_map : Map[String, CoreExternType] = Map([])
              for ex in inline_exports {
                check_sortidx(ex.sortidx, counts, type_table.length())
                if map.get(ex.name) is Some(_) {
                  raise DuplicateExportName(ex.name)
                }
                match ex.sortidx.sort {
                  Core(core_sort) => {
                    map.set(ex.name, core_sort)
                    match core_sort {
                      0x00 =>
                        if ex.sortidx.idx >= 0 &&
                          ex.sortidx.idx < core_func_types.length() {
                          match core_func_types[ex.sortidx.idx] {
                            Some(ft) => type_map.set(ex.name, Func(ft))
                            None => ()
                          }
                        }
                      0x02 =>
                        if ex.sortidx.idx >= 0 &&
                          ex.sortidx.idx < core_memory_types.length() {
                          match core_memory_types[ex.sortidx.idx] {
                            Some(mt) => type_map.set(ex.name, Memory(mt))
                            None => ()
                          }
                        }
                      _ => ()
                    }
                  }
                  _ => ()
                }
              }
              export_map = Some(map)
              export_types = Some(type_map)
            }
          }
          core_instances.push({ export_kinds: export_map, export_types, })
          counts.core_instance += 1
        }
      }
      3 => {
        // Validate core module type signatures, including `alias outer` bounds.
        // The `outer` depth counts enclosing component scopes.
        let max_outer_depth = depth + 1
        let base_core_type_bound = counts.core_type
        let signatures = parse_core_type_section(
          s.payload,
          max_outer_depth,
          base_core_type_bound,
          core_type_bounds,
        )
        core_types.append(signatures)
        counts.core_type += signatures.length()
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
          [depth] + type_outer_depths,
          [core_types] + core_type_outers,
          [components] + component_outers,
        )
        components.push(nested_info)
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
        let scope : TypeValidationScope = {
          cfg,
          type_outers: [type_table] + type_outers,
          type_outer_depths: [depth] + type_outer_depths,
          component_depth: depth,
          core_type_outers: [core_types],
        }
        for d in defs {
          scope.validate_typedef(d, allow_resource_defs=true)
          // Resource types refer to the core-func index space for their dtor.
          // Validate bounds/signature here where we have access to the current
          // core-func types.
          match d {
            ResourceType(_, _rep, dtor_idx, _kind) =>
              match dtor_idx {
                Some(idx) =>
                  if idx < 0 || idx >= counts.core_func {
                    raise SectionParseError(7, "function index out of bounds")
                  } else {
                    match core_func_types.get(idx) {
                      Some(Some(ft)) => {
                        let expected : @types.FuncType = {
                          params: [I32],
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
          local_resource_types.push(d is ResourceType(_, _, _, _))
          match d {
            ResourceType(_, _, _, _) => {
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
          components,
          instances,
          named_types,
          import_named_types,
          core_types,
          core_modules,
          func_types,
          func_sig_shapes,
          seen_import_names,
          import_resource_names,
          my_import_sorts,
          my_import_core_modules,
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
      11 => {
        let (new_export_size, new_next_resource_id) = validate_component_section_export(
          s.payload,
          cfg,
          is_root,
          counts,
          type_table,
          known_type_sigs,
          local_resource_types,
          resource_ids,
          type_sizes,
          type_depths,
          components,
          instances,
          export_size,
          named_types,
          core_modules,
          core_func_types,
          core_instances,
          core_memory_types,
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
          next_resource_id,
        )
        export_size = new_export_size
        next_resource_id = new_next_resource_id
      }
      5 =>
        next_resource_id = validate_component_section_instance(
          s.payload,
          cfg,
          counts,
          type_table,
          known_type_sigs,
          resource_ids,
          components,
          instances,
          core_modules,
          func_types,
          func_sig_shapes,
          next_resource_id,
        )
      6 =>
        validate_component_section_alias(
          s.payload,
          counts,
          type_table,
          known_type_sigs,
          local_resource_types,
          resource_ids,
          type_sizes,
          type_depths,
          components,
          instances,
          named_types,
          core_modules,
          core_types,
          core_type_outers,
          core_func_types,
          core_instances,
          core_memory_types,
          func_types,
          func_sig_shapes,
          type_outers,
          component_outers,
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
            Lift(_, _, tyidx) =>
              match type_table[tyidx] {
                Some(FuncType(ft)) => {
                  func_types.push(Some(ft))
                  func_sig_shapes.push(
                    Some(
                      funcsig_of_functype(
                        ft,
                        type_table,
                        resource_ids,
                        known_sigs=known_type_sigs,
                      ),
                    ),
                  )
                }
                _ => {
                  func_types.push(None)
                  func_sig_shapes.push(None)
                }
              }
            // All non-lift canonical items append a core function to the core-func
            // index space. Model known intrinsic signatures so core module
            // instantiation validates imports against canonical builtins.
            _ =>
              core_func_types.push(
                core_functype_for_canon(c, type_table, core_memory_types),
              )
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
    import_sorts: Some(my_import_sorts),
    import_instance_sigs: Some(my_import_instance_sigs),
    import_func_sigs: Some(my_import_func_sigs),
    import_instance_resource_exports: Some(my_import_instance_resource_exports),
    import_type_bounds: Some(my_import_type_bounds),
    import_type_sigs: Some(my_import_type_sigs),
    import_core_modules: Some(my_import_core_modules),
    export_sorts: Some(my_export_sorts),
    export_instance_sigs: Some(my_export_instance_sigs),
    export_instance_type_sigs: Some(my_export_instance_type_sigs),
    export_instance_func_sigs: Some(my_export_instance_func_sigs),
    export_type_sigs: Some(my_export_type_sigs),
    export_func_sigs: Some(my_export_func_sigs),
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
  validate_component_inner(component, true, cfg, 0, [], [], [], []) |> ignore
}

///|
/// Validate a component and return evidence accepted by runtime instantiation.
pub fn validate_component_for_instantiation(
  component : @component.Component,
) -> ValidatedComponent raise ComponentValidationError {
  validate_component_for_instantiation_with_config(
    component,
    ComponentValidationConfig::default(),
  )
}

///|
/// Validate a component with the requested name policy and return evidence
/// accepted by runtime instantiation.
///
/// The evidence holds an immutable binary snapshot rebuilt from the
/// component's sections. The parsed snapshot is what gets validated, and the
/// runtime reparses exactly those bytes. Mutating the argument after this call
/// cannot invalidate the evidence.
pub fn validate_component_for_instantiation_with_config(
  component : @component.Component,
  cfg : ComponentValidationConfig,
) -> ValidatedComponent raise ComponentValidationError {
  let component_bytes = component.snapshot_bytes()
  let snapshot = @component.parse_component(component_bytes) catch {
    e => raise SectionParseError(0, "component snapshot: \{e}")
  }
  validate_component_with_config(snapshot, cfg)
  { component_bytes, }
}
