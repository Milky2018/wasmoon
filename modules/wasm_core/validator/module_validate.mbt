///|
/// Validate a complete module
pub fn validate_module(
  mod : @types.Module,
  bulk_memory~ : Bool = true,
  stack_switching~ : Bool = false,
) -> Unit raise ValidationError {
  validate_module_core(mod, bulk_memory, stack_switching, with_context=false)
}

///|
/// Run the complete module validation with instruction-level diagnostics.
pub fn validate_module_with_context(
  mod : @types.Module,
  bulk_memory~ : Bool = true,
  stack_switching~ : Bool = false,
) -> Unit raise ValidationError {
  validate_module_core(mod, bulk_memory, stack_switching, with_context=true)
}

///|
fn validate_module_core(
  mod : @types.Module,
  bulk_memory : Bool,
  stack_switching : Bool,
  with_context~ : Bool,
) -> Unit raise ValidationError {
  let ctx = ValidationContext::ValidationContext(
    mod,
    bulk_memory~,
    stack_switching~,
  )
  validate_segment_features(mod, bulk_memory)
  validate_continuation_types(mod, stack_switching)
  validate_module_declarations(mod, ctx, stack_switching) catch {
    error => raise decorate_validation_error(error, with_context)
  }
  // Validate all function bodies
  let num_imports = count_func_imports(mod.imports)
  for i, code in mod.codes {
    let func_idx = num_imports + i
    let type_idx = ctx.funcs[func_idx]
    if type_idx < 0 || type_idx >= ctx.types.length() {
      raise decorate_validation_error(
        InvalidTypeIndex(type_idx),
        with_context,
        func_idx~,
      )
    }
    let func_type = ctx.get_func_type(type_idx)
    validate_function(
      ctx,
      func_type,
      code,
      func_idx?=if with_context { Some(func_idx) } else { None },
    )
  }
}

///|
fn validate_module_declarations(
  mod : @types.Module,
  ctx : ValidationContext,
  stack_switching : Bool,
) -> Unit raise ValidationError {
  let num_types = ctx.types.length()

  // Validate that all function type indices are valid
  for type_idx in ctx.funcs {
    if type_idx < 0 || type_idx >= num_types {
      raise InvalidTypeIndex(type_idx)
    }
  }

  // Validate subtype declarations: supertypes must not be final, must have matching kind,
  // and must satisfy structural subtyping rules
  let canonical = @types.compute_canonical_type_indices(
    mod.types,
    type_rec_groups=mod.type_rec_groups,
  )
  let subtyping_ctx = @types.SubtypingContext::same_module(
    mod.types,
    rec_groups=mod.type_rec_groups,
    canonical~,
  )
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
        (Cont(_), Cont(_)) => true
        _ => false
      }
      if !valid_kind {
        raise TypeMismatch(
          "sub type: type \{type_idx} has incompatible kind with supertype \{super_idx}",
        )
      }
      // Validate structural subtyping: subtype's structure must be compatible with supertype
      if !subtyping_ctx.validate_declared_subtype(type_idx, super_idx) {
        raise TypeMismatch(
          "sub type: type \{type_idx} is not a valid structural subtype of \{super_idx}",
        )
      }
    }
  }

  // Validate type indices in global types
  for global in mod.globals {
    validate_value_type(global.type_.value_type, ctx.types, stack_switching~)
  }

  // Validate type indices in table element types
  for table in mod.tables {
    validate_value_type(table.type_.elem_type, ctx.types, stack_switching~)
  }

  // Validate type indices in elem segment types
  for elem in mod.elems {
    validate_value_type(elem.type_, ctx.types, stack_switching~)
  }

  // Validate memory limits
  for mem in ctx.mems {
    validate_memory_limits(mem)
  }

  // Table initializers can only see imported globals.
  let num_imported_globals = count_global_imports(mod.imports)
  // Validate table types and limits
  for table in mod.tables {
    validate_table_type(table, ctx, ctx.globals[:num_imported_globals])
  }

  // Validate global initialization expressions
  // For each global, its init expression can only reference previously defined globals
  // (imported globals are already in ctx.globals from imports)
  for i, global in mod.globals {
    // Validate init expression (pass funcs to allow ref.func in global init)
    validate_const_expr(
      ctx.globals[:num_imported_globals + i],
      global.init,
      global.type_.value_type,
      funcs=ctx.funcs,
      types=ctx.types,
      subtyping_ctx=Some(ctx.subtyping_ctx),
      stack_switching=ctx.stack_switching,
    )
  }

  // Validate data segments reference valid memory and have valid offset expressions
  for data in mod.datas {
    // Passive data segments have no offset expression to validate.
    if data.memory_idx < 0 {
      continue
    }
    if data.memory_idx >= ctx.mems.length() {
      raise InvalidMemoryIndex(data.memory_idx)
    }
    // Validate offset expression with the target memory's address type.
    let offset_type = ctx.mems[data.memory_idx].addr_type()
    validate_const_expr(
      ctx.globals,
      data.offset,
      offset_type,
      types=ctx.types,
      subtyping_ctx=Some(ctx.subtyping_ctx),
      stack_switching=ctx.stack_switching,
    )
  }

  // Validate elem segments
  for elem in mod.elems {
    // Validate offset expression for active elem segments
    if elem.mode is Active(table_idx, offset_expr) {
      // Check table index is valid
      if table_idx < 0 || table_idx >= ctx.tables.length() {
        raise InvalidTableIndex(table_idx)
      }
      // Check element type matches table element type
      let table_elem_type = ctx.tables[table_idx].elem_type
      if !is_type_subtype(elem.type_, table_elem_type) {
        raise TypeMismatch(
          "element segment type \{elem.type_} is not subtype of table element type \{table_elem_type}",
        )
      }
      // Validate offset expression - i32 for table32, i64 for table64
      let offset_type = if ctx.tables[table_idx].is_table64 {
        @types.ValueType::I64
      } else {
        I32
      }
      validate_const_expr(
        ctx.globals,
        offset_expr,
        offset_type,
        types=ctx.types,
        subtyping_ctx=Some(ctx.subtyping_ctx),
        stack_switching=ctx.stack_switching,
      )
    }
    // Validate each init expression is a constant expression producing the element type
    for init in elem.init {
      validate_const_expr(
        ctx.globals,
        init,
        elem.type_,
        funcs=ctx.funcs,
        types=ctx.types,
        subtyping_ctx=Some(ctx.subtyping_ctx),
        stack_switching=ctx.stack_switching,
      )
    }
  }

  validate_exports(mod, ctx)

  // Validate start function if present
  if mod.start is Some(start_idx) {
    // Check that the function index is valid
    if start_idx < 0 || start_idx >= ctx.funcs.length() {
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
}

///|
fn decorate_validation_error(
  error : ValidationError,
  with_context : Bool,
  func_idx? : Int32,
) -> ValidationError {
  if !with_context {
    return error
  }
  let details = ValidationErrorContext::from_error(error)
  WithContext(
    match func_idx {
      Some(index) => details.with_func_idx(index)
      None => details
    },
  )
}

///|
fn validate_segment_features(
  mod : @types.Module,
  bulk_memory : Bool,
) -> Unit raise ValidationError {
  if bulk_memory {
    return
  }
  for data in mod.datas {
    if data.memory_idx < 0 {
      raise TypeMismatch("bulk memory support is not enabled")
    }
  }
  for elem in mod.elems {
    match elem.mode {
      Active(_, _) => ()
      _ => raise TypeMismatch("bulk memory support is not enabled")
    }
  }
}

///|
fn validate_exports(
  mod : @types.Module,
  ctx : ValidationContext,
) -> Unit raise ValidationError {
  // Validate exports
  let export_names : Map[String, Unit] = Map([])
  for exp in mod.exports {
    // Check for duplicate export names
    if export_names.contains(exp.name) {
      raise DuplicateExportName(exp.name)
    }
    export_names.set(exp.name, ())
    // Check that export references a valid entity
    match exp.desc {
      Func(idx) =>
        if idx < 0 || idx >= ctx.funcs.length() {
          raise UnknownExport("unknown function \{idx}")
        }
      Global(idx) =>
        if idx < 0 || idx >= ctx.globals.length() {
          raise UnknownExport("unknown global \{idx}")
        }
      Table(idx) =>
        if idx < 0 || idx >= ctx.tables.length() {
          raise UnknownExport("unknown table \{idx}")
        }
      Memory(idx) =>
        if idx < 0 || idx >= ctx.mems.length() {
          raise UnknownExport("unknown memory \{idx}")
        }
      Tag(idx) => {
        // Validate tag index - count imported tags plus defined tags
        let num_imported_tags = count_tag_imports(mod.imports)
        let total_tags = num_imported_tags + mod.tags.length()
        if idx < 0 || idx >= total_tags {
          raise UnknownExport("unknown tag \{idx}")
        }
      }
    }
  }
}
