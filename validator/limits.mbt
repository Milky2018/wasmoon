///|
/// Validate memory limits according to WASM spec
fn validate_memory_limits(
  mem : @types.MemoryType,
) -> Unit raise ValidationError {
  let limits = mem.limits
  // memory32: max 65536 pages (2^16) = 4GB
  // memory64: max 2^48 pages = 16EB (theoretical, but limit to 2^48 pages)
  // Note: 2^48 = 281474976710656, but we use the representation that fits in Int64
  let max_pages : Int64 = if mem.is_memory64 {
    281474976710656L // 2^48 pages
  } else {
    65536L
  }
  let error_msg = if mem.is_memory64 {
    "memory size must be at most 2^48 pages"
  } else {
    "memory size must be at most 65536 pages"
  }

  // Check min doesn't exceed max allowed
  if limits.min.reinterpret_as_uint64() > max_pages.reinterpret_as_uint64() {
    raise InvalidLimits(error_msg)
  }

  // Check max if specified
  if limits.max is Some(max_val) {
    // max must not exceed allowed maximum
    if max_val.reinterpret_as_uint64() > max_pages.reinterpret_as_uint64() {
      raise InvalidLimits(error_msg)
    }
    // min must not be greater than max (unsigned comparison)
    if limits.min.reinterpret_as_uint64() > max_val.reinterpret_as_uint64() {
      raise InvalidLimits("size minimum must not be greater than maximum")
    }
  }
}

///|
/// Validate table limits according to WASM spec
fn validate_table_limits(
  limits : @types.Limits,
  is_table64? : Bool = false,
) -> Unit raise ValidationError {
  // For table32, min and max must fit in 32 bits (< 2^32)
  let max_table32_size = 0x100000000L // 2^32
  if not(is_table64) {
    if limits.min >= max_table32_size {
      raise InvalidLimits("table size")
    }
    if limits.max is Some(max_val) && max_val >= max_table32_size {
      raise InvalidLimits("table size")
    }
  }
  // Check max if specified
  if limits.max is Some(max_val) {
    // min must not be greater than max (unsigned comparison)
    if limits.min.reinterpret_as_uint64() > max_val.reinterpret_as_uint64() {
      raise InvalidLimits("size minimum must not be greater than maximum")
    }
  }
}

///|
/// Validate memory offset for load/store instructions
/// For memory32, offset must be < 2^32
fn validate_mem_offset(
  mem : @types.MemoryType,
  offset : Int64,
) -> Unit raise ValidationError {
  // For memory32, offset must fit in 32 bits (< 2^32)
  // Use unsigned comparison to handle large values like 0xFFFF_FFFF_FFFF_FFFF
  let max_offset = 0x100000000L.reinterpret_as_uint64() // 2^32
  if not(mem.is_memory64) && offset.reinterpret_as_uint64() >= max_offset {
    raise InvalidLimits("offset out of range")
  }
}

///|
/// Check if a reference type is non-nullable
fn is_non_nullable_ref_type(ty : @types.ValueType) -> Bool {
  match ty {
    RefFunc | RefExtern | RefFuncTyped(_) => true
    _ => false
  }
}

///|
/// Validate table type with init expression
fn validate_table_type(
  table : @types.Table,
  ctx : ValidationContext,
  func_addrs : Array[Int],
) -> Unit raise ValidationError {
  // Validate table limits
  validate_table_limits(table.type_.limits, is_table64=table.type_.is_table64)
  // Validate table init expression if present
  if table.init is Some(init_expr) {
    // Validate the init expression produces the correct type
    validate_const_expr(
      ctx.globals,
      init_expr,
      table.type_.elem_type,
      funcs=func_addrs,
    )
  } else if is_non_nullable_ref_type(table.type_.elem_type) {
    // If no init expression and element type is non-nullable, this is always an error
    // per WebAssembly spec, regardless of table size
    raise TypeMismatch(
      "table with non-nullable element type requires an initializer",
    )
  }
}

///|
fn count_func_imports(imports : Array[@types.Import]) -> Int {
  let mut count = 0
  for imp in imports {
    if imp.desc is Func(_) {
      count = count + 1
    }
  }
  count
}

///|
fn count_global_imports(imports : Array[@types.Import]) -> Int {
  let mut count = 0
  for imp in imports {
    if imp.desc is Global(_) {
      count = count + 1
    }
  }
  count
}

///|
fn count_tag_imports(imports : Array[@types.Import]) -> Int {
  let mut count = 0
  for imp in imports {
    if imp.desc is Tag(_) {
      count = count + 1
    }
  }
  count
}
