///|
priv struct ImportMismatch {
  expected : String
  actual : String?
  message : String
  runtime_error : @runtime.RuntimeError
}

///|
fn invalid_import_address(
  expected : String,
  kind : String,
  addr : Int32,
  error : @runtime.RuntimeError,
) -> ImportMismatch {
  {
    expected,
    actual: None,
    message: "refers to invalid \{kind} address \{addr}",
    runtime_error: error,
  }
}

///|
fn import_type_mismatch(
  expected : String,
  actual : String,
  message : String,
  error~ : @runtime.RuntimeError = LinkError,
) -> ImportMismatch {
  { expected, actual: Some(actual), message, runtime_error: error, }
}

///|
fn import_limits_message(
  expected : @types.Limits,
  actual : (Int64, Int64?),
) -> String? {
  match expected.import_mismatch(actual) {
    Some(MinimumTooSmall) => Some("minimum is smaller than required")
    Some(MaximumTooLarge) => Some("maximum exceeds requirement")
    Some(MissingMaximum) => Some("maximum is required but missing")
    None => None
  }
}

///|
/// Compare an import after the resolver has checked its external kind.
fn check_import_type(
  store : @runtime.Store,
  mod : @types.Module,
  imp : @types.Import,
  value : @runtime.ExternVal,
) -> ImportMismatch? {
  match (imp.desc, value) {
    (Func(index), Func(addr)) => {
      let expected = mod.validated_func_type_at(index)
      let actual = store.get_func_type(addr) catch {
        error =>
          return Some(
            invalid_import_address(
              expected.to_string(),
              "function",
              addr,
              error,
            ),
          )
      }
      if store.get_func_owner(addr) is Some(owner) {
        let context = @types.SubtypingContext::cross_module(
          owner.types,
          mod.types,
          rec_groups1=owner.type_rec_groups,
          rec_groups2=mod.type_rec_groups,
        )
        if !context.is_subtype(store.get_func_type_idx(addr), index) {
          return Some(
            import_type_mismatch(
              expected.to_string(),
              actual.to_string(),
              "function type mismatch (cross-module subtype check failed)",
              error=LinkErrorDetail(
                "import \{imp.mod_name}.\{imp.name}: exported type is not a subtype of imported type",
              ),
            ),
          )
        }
      } else {
        let rec_info = @types.get_rec_group_info(mod.type_rec_groups, index)
        if rec_info != (0, 1) {
          return Some(
            import_type_mismatch(
              expected.to_string(),
              actual.to_string(),
              "expects singleton rec group type, got \{Repr(rec_info)}",
              error=LinkErrorDetail(
                "import \{imp.mod_name}.\{imp.name}: expected singleton rec group type, got \{Repr(rec_info)}",
              ),
            ),
          )
        }
        if !@types.func_types_equal(expected, actual) {
          return Some(
            import_type_mismatch(
              expected.to_string(),
              actual.to_string(),
              "function type mismatch",
              error=LinkErrorDetail(
                "import \{imp.mod_name}.\{imp.name}: type mismatch; expected=\{expected} actual=\{actual}",
              ),
            ),
          )
        }
      }
      None
    }
    (Memory(expected), Memory(addr)) => {
      let memory = store.get_mem(addr) catch {
        error =>
          return Some(
            invalid_import_address(expected.to_string(), "memory", addr, error),
          )
      }
      let limits = memory.get_limits64()
      let mismatch = if memory.is_memory64() != expected.is_memory64 ||
        memory.is_shared() != expected.is_shared ||
        memory.page_size_bytes() != 1L << expected.page_size_log2 {
        Some("64 mismatch")
      } else {
        import_limits_message(expected.limits, limits).map(message => {
          " " + message
        })
      }
      mismatch.map(message => {
        import_type_mismatch(
          expected.to_string(),
          "memory64=\{memory.is_memory64()}, limits=\{format_limits_pair(limits)}",
          "memory" + message,
        )
      })
    }
    (Table(expected), Table(addr)) => {
      let table = store.get_table(addr) catch {
        error =>
          return Some(
            invalid_import_address(expected.to_string(), "table", addr, error),
          )
      }
      let element = table.get_elem_type()
      let limits = table.get_limits64()
      let mismatch = if !store.resource_value_type_matches(
          Table(addr),
          mod,
          element,
          expected.elem_type,
          invariant=true,
        ) {
        Some(" element type mismatch")
      } else if table.is_table64() != expected.is_table64 {
        Some("64 mismatch")
      } else {
        import_limits_message(expected.limits, limits).map(message => {
          " " + message
        })
      }
      mismatch.map(message => {
        import_type_mismatch(
          expected.to_string(),
          "elem=\{element}, table64=\{table.is_table64()}, limits=\{format_limits_pair(limits)}",
          "table" + message,
        )
      })
    }
    (Global(expected), Global(addr)) => {
      let actual = store.get_global(addr).get_type() catch {
          error =>
            return Some(
              invalid_import_address(
                expected.to_string(),
                "global",
                addr,
                error,
              ),
            )
        }
      let matches = store.resource_value_type_matches(
        Global(addr),
        mod,
        actual.value_type,
        expected.value_type,
        invariant=actual.mutable,
      )
      let mismatch = if actual.mutable {
        if !matches || !expected.mutable {
          Some("mutable global type mismatch")
        } else {
          None
        }
      } else if !matches {
        Some("immutable global type mismatch")
      } else if expected.mutable {
        Some("expected mutable global but actual is immutable")
      } else {
        None
      }
      mismatch.map(message => {
        import_type_mismatch(expected.to_string(), actual.to_string(), message)
      })
    }
    (Tag(index), Tag(addr)) => {
      let expected = mod.validated_func_type_at(index)
      let actual = store.get_tag_type(addr) catch {
        error =>
          return Some(
            invalid_import_address(expected.to_string(), "tag", addr, error),
          )
      }
      if store.tag_type_matches(addr, mod, index, actual) {
        return None
      }
      let message = if store.get_tag_owner(addr) is Some(owner) &&
        (
          @types.get_rec_group_info(mod.type_rec_groups, index).1 != 1 ||
          @types.get_rec_group_info(
            owner.type_rec_groups,
            store.get_tag_type_idx(addr),
          ).1 !=
          1
        ) {
        "tag type mismatch"
      } else {
        "tag parameter mismatch"
      }
      Some(
        import_type_mismatch(expected.to_string(), actual.to_string(), message),
      )
    }
    _ => abort("import kind was checked before comparing its type")
  }
}
