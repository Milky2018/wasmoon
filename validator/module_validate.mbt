///|
/// Validate a complete module
pub fn validate_module(mod : @types.Module) -> Unit raise ValidationError {
  let ctx = ValidationContext::new(mod)
  let num_types = ctx.types.length()

  // Validate that all function type indices are valid
  for i, type_idx in ctx.funcs {
    if type_idx < 0 || type_idx >= num_types {
      raise InvalidTypeIndex(type_idx)
    }
    ignore(i)
  }

  // Validate type indices in function types (parameters and results)
  for subtype in mod.types {
    for vt in collect_value_types_from_subtype(subtype) {
      validate_value_type(vt, num_types)
    }
  }

  // Validate forward type references are only within rec groups
  for type_idx, subtype in mod.types {
    for vt in collect_value_types_from_subtype(subtype) {
      validate_type_forward_refs(vt, type_idx, mod.type_rec_groups)
    }
  }

  // Validate subtype declarations: supertypes must not be final, must have matching kind,
  // and must satisfy structural subtyping rules
  let subtyping_ctx = @types.SubtypingContext::same_module(mod.types)
  for type_idx, subtype in mod.types {
    for super_idx in subtype.supertypes {
      if super_idx < 0 || super_idx >= num_types {
        raise InvalidTypeIndex(super_idx)
      }
      let supertype = mod.types[super_idx]
      if supertype.final_ {
        raise TypeMismatch(
          "sub type: type \{type_idx} cannot extend final type \{super_idx}",
        )
      }
      // Validate composite type kinds match
      let valid_kind = match (subtype.composite, supertype.composite) {
        (Func(_), Func(_)) => true
        (Struct(_), Struct(_)) => true
        (Array(_), Array(_)) => true
        _ => false
      }
      if not(valid_kind) {
        raise TypeMismatch(
          "sub type: type \{type_idx} has incompatible kind with supertype \{super_idx}",
        )
      }
      // Validate structural subtyping: subtype's structure must be compatible with supertype
      if not(subtyping_ctx.validate_declared_subtype(type_idx, super_idx)) {
        raise TypeMismatch(
          "sub type: type \{type_idx} is not a valid structural subtype of \{super_idx}",
        )
      }
    }
    ignore(type_idx)
  }

  // Validate type indices in global types
  for global in mod.globals {
    validate_value_type(global.type_.value_type, num_types)
  }

  // Validate type indices in table element types
  for table in mod.tables {
    validate_value_type(table.type_.elem_type, num_types)
  }

  // Validate type indices in elem segment types
  for elem in mod.elems {
    validate_value_type(elem.type_, num_types)
  }

  // Multi-memory support is now enabled
  // The restriction has been removed to support WebAssembly multi-memory proposal

  // Multi-table support is now enabled
  // The restriction has been removed to support WebAssembly reference types proposal

  // Validate memory limits
  for mem in ctx.mems {
    validate_memory_limits(mem)
  }

  // Validate table types and limits
  for table in mod.tables {
    validate_table_type(table, ctx, ctx.funcs)
  }

  // Validate global initialization expressions
  // For each global, its init expression can only reference previously defined globals
  // (imported globals are already in ctx.globals from imports)
  let num_imported_globals = count_global_imports(mod.imports)
  for i, global in mod.globals {
    // Available globals for this init: imports + module globals before index i
    let available_globals : Array[@types.GlobalType] = []
    // Add all imported globals
    for j in 0..<num_imported_globals {
      available_globals.push(ctx.globals[j])
    }
    // Add module globals defined before this one
    for j in 0..<i {
      available_globals.push(mod.globals[j].type_)
    }
    // Validate init expression (pass funcs to allow ref.func in global init)
    validate_const_expr(
      available_globals,
      global.init,
      global.type_.value_type,
      funcs=ctx.funcs,
    )
  }

  // Validate data segments reference valid memory and have valid offset expressions
  for data in mod.datas {
    if data.memory_idx >= ctx.mems.length() {
      raise InvalidMemoryIndex(data.memory_idx)
    }
    // Validate offset expression is a constant expression producing i32
    validate_const_expr(ctx.globals, data.offset, @types.ValueType::I32)
  }

  // Validate elem segments
  for elem in mod.elems {
    // Validate offset expression for active elem segments
    if elem.mode is Active(table_idx, offset_expr) {
      // Check table index is valid
      if table_idx >= ctx.tables.length() {
        raise InvalidTableIndex(table_idx)
      }
      // Check element type matches table element type
      let table_elem_type = ctx.tables[table_idx].elem_type
      if elem.type_ != table_elem_type {
        raise TypeMismatch(
          "element segment type \{elem.type_} does not match table element type \{table_elem_type}",
        )
      }
      // Validate offset expression - i32 for table32, i64 for table64
      let offset_type = if ctx.tables[table_idx].is_table64 {
        @types.ValueType::I64
      } else {
        @types.ValueType::I32
      }
      validate_const_expr(ctx.globals, offset_expr, offset_type)
    }
    // Validate each init expression is a constant expression producing the element type
    for init in elem.init {
      validate_const_expr(ctx.globals, init, elem.type_, funcs=ctx.funcs)
    }
  }

  // Validate exports
  let export_names : Map[String, Unit] = {}
  for exp in mod.exports {
    // Check for duplicate export names
    if export_names.contains(exp.name) {
      raise DuplicateExportName(exp.name)
    }
    export_names.set(exp.name, ())
    // Check that export references a valid entity
    match exp.desc {
      Func(idx) =>
        if idx >= ctx.funcs.length() {
          raise UnknownExport("unknown function \{idx}")
        }
      Global(idx) =>
        if idx >= ctx.globals.length() {
          raise UnknownExport("unknown global \{idx}")
        }
      Table(idx) =>
        if idx >= ctx.tables.length() {
          raise UnknownExport("unknown table \{idx}")
        }
      Memory(idx) =>
        if idx >= ctx.mems.length() {
          raise UnknownExport("unknown memory \{idx}")
        }
      Tag(idx) => {
        // Validate tag index - count imported tags plus defined tags
        let num_imported_tags = count_tag_imports(mod.imports)
        let total_tags = num_imported_tags + mod.tags.length()
        if idx >= total_tags {
          raise UnknownExport("unknown tag \{idx}")
        }
      }
    }
  }

  // Validate start function if present
  if mod.start is Some(start_idx) {
    // Check that the function index is valid
    if start_idx >= ctx.funcs.length() {
      raise InvalidFunctionIndex(start_idx)
    }
    // Get the function type
    let type_idx = ctx.funcs[start_idx]
    let func_type = ctx.get_func_type(type_idx)
    // Start function must have type [] -> [] (no params, no results)
    if func_type.params.length() != 0 || func_type.results.length() != 0 {
      raise InvalidStartFunction("start function")
    }
  }

  // Validate all function bodies
  let num_imports = count_func_imports(mod.imports)
  for i, code in mod.codes {
    let func_idx = num_imports + i
    let type_idx = ctx.funcs[func_idx]
    if type_idx < 0 || type_idx >= ctx.types.length() {
      raise InvalidTypeIndex(type_idx)
    }
    let func_type = ctx.get_func_type(type_idx)
    validate_function(ctx, func_type, code)
  }
}

///|
/// Validate a complete module and return detailed error context on failure
pub fn validate_module_with_context(
  mod : @types.Module,
) -> Unit raise ValidationError {
  let ctx = ValidationContext::new(mod)

  // Validate that all function type indices are valid
  for i, type_idx in ctx.funcs {
    if type_idx < 0 || type_idx >= ctx.types.length() {
      raise WithContext(
        ValidationErrorContext::from_error(InvalidTypeIndex(type_idx)),
      )
    }
    ignore(i)
  }

  // Validate subtype declarations: supertypes must not be final, must have matching kind,
  // and must satisfy structural subtyping rules
  let num_types = ctx.types.length()
  let subtyping_ctx = @types.SubtypingContext::same_module(mod.types)
  for type_idx, subtype in mod.types {
    for super_idx in subtype.supertypes {
      if super_idx < 0 || super_idx >= num_types {
        raise WithContext(
          ValidationErrorContext::from_error(InvalidTypeIndex(super_idx)),
        )
      }
      let supertype = mod.types[super_idx]
      if supertype.final_ {
        raise WithContext(
          ValidationErrorContext::from_error(
            TypeMismatch(
              "sub type: type \{type_idx} cannot extend final type \{super_idx}",
            ),
          ),
        )
      }
      // Validate composite type kinds match
      let valid_kind = match (subtype.composite, supertype.composite) {
        (Func(_), Func(_)) => true
        (Struct(_), Struct(_)) => true
        (Array(_), Array(_)) => true
        _ => false
      }
      if not(valid_kind) {
        raise WithContext(
          ValidationErrorContext::from_error(
            TypeMismatch(
              "sub type: type \{type_idx} has incompatible kind with supertype \{super_idx}",
            ),
          ),
        )
      }
      // Validate structural subtyping: subtype's structure must be compatible with supertype
      if not(subtyping_ctx.validate_declared_subtype(type_idx, super_idx)) {
        raise WithContext(
          ValidationErrorContext::from_error(
            TypeMismatch(
              "sub type: type \{type_idx} is not a valid structural subtype of \{super_idx}",
            ),
          ),
        )
      }
    }
    ignore(type_idx)
  }

  // Multi-memory support is now enabled (WebAssembly multi-memory proposal)

  // Multi-table support is now enabled (WebAssembly reference types proposal)

  // Validate memory limits
  for mem in ctx.mems {
    validate_memory_limits(mem) catch {
      e => raise WithContext(ValidationErrorContext::from_error(e))
    }
  }

  // Validate table types and limits
  for table in mod.tables {
    validate_table_type(table, ctx, ctx.funcs) catch {
      e => raise WithContext(ValidationErrorContext::from_error(e))
    }
  }

  // Validate data segments reference valid memory and have valid offset expressions
  for data in mod.datas {
    if data.memory_idx >= ctx.mems.length() {
      raise WithContext(
        ValidationErrorContext::from_error(InvalidMemoryIndex(data.memory_idx)),
      )
    }
    // Validate offset expression is a constant expression producing i32
    validate_const_expr(ctx.globals, data.offset, @types.ValueType::I32) catch {
      e => raise WithContext(ValidationErrorContext::from_error(e))
    }
  }

  // Validate elem segments
  for elem in mod.elems {
    // Validate offset expression for active elem segments
    if elem.mode is Active(table_idx, offset_expr) {
      // Check table index is valid
      if table_idx >= ctx.tables.length() {
        raise WithContext(
          ValidationErrorContext::from_error(InvalidTableIndex(table_idx)),
        )
      }
      // Check element type matches table element type
      let table_elem_type = ctx.tables[table_idx].elem_type
      if elem.type_ != table_elem_type {
        raise WithContext(
          ValidationErrorContext::from_error(
            TypeMismatch(
              "element segment type \{elem.type_} does not match table element type \{table_elem_type}",
            ),
          ),
        )
      }
      // Validate offset expression - i32 for table32, i64 for table64
      let offset_type = if ctx.tables[table_idx].is_table64 {
        @types.ValueType::I64
      } else {
        @types.ValueType::I32
      }
      validate_const_expr(ctx.globals, offset_expr, offset_type) catch {
        e => raise WithContext(ValidationErrorContext::from_error(e))
      }
    }
    // Validate each init expression is a constant expression producing the element type
    for init in elem.init {
      validate_const_expr(ctx.globals, init, elem.type_, funcs=ctx.funcs) catch {
        e => raise WithContext(ValidationErrorContext::from_error(e))
      }
    }
  }

  // Validate start function if present
  if mod.start is Some(start_idx) {
    // Check that the function index is valid
    if start_idx >= ctx.funcs.length() {
      raise WithContext(
        ValidationErrorContext::from_error(InvalidFunctionIndex(start_idx)),
      )
    }
    // Get the function type
    let type_idx = ctx.funcs[start_idx]
    let func_type = ctx.get_func_type(type_idx)
    // Start function must have type [] -> [] (no params, no results)
    if func_type.params.length() != 0 || func_type.results.length() != 0 {
      raise WithContext(
        ValidationErrorContext::from_error(
          InvalidStartFunction("start function"),
        ),
      )
    }
  }

  // Validate all function bodies with location tracking
  let num_imports = count_func_imports(mod.imports)
  for i, code in mod.codes {
    let func_idx = num_imports + i
    let type_idx = ctx.funcs[func_idx]
    if type_idx < 0 || type_idx >= ctx.types.length() {
      raise WithContext(
        ValidationErrorContext::from_error(InvalidTypeIndex(type_idx)).with_func_idx(
          func_idx,
        ),
      )
    }
    let func_type = ctx.get_func_type(type_idx)
    validate_function_with_offset(ctx, func_type, code, func_idx)
  }
}
