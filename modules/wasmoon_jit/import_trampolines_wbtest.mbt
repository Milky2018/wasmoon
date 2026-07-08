///|
test "import trampolines: known wasi functions" {
  let names = [
    "fd_write", "fd_read", "args_get", "environ_get", "clock_time_get", "random_get",
    "proc_exit",
  ]
  for name in names {
    assert_true(
      get_import_trampoline("wasi_snapshot_preview1", name) is Some(_),
    )
  }
}

///|
test "import trampolines: known spectest functions" {
  let names = [
    "print", "print_i32", "print_i64", "print_f32", "print_f64", "print_i32_f32",
    "print_f64_f64", "print_char",
  ]
  for name in names {
    assert_true(get_import_trampoline("spectest", name) is Some(_))
  }
}

///|
test "import trampolines: unsupported imports" {
  assert_true(get_import_trampoline("unknown_module", "unknown_func") is None)
  assert_true(get_import_trampoline("spectest", "unknown_func") is None)
  assert_true(get_import_trampoline("env", "memory") is None)
  assert_true(!is_jit_supported_module("env"))
}

///|
test "import trampolines: external imports override builtin fallback" {
  let external : Map[String, Map[String, Int64]] = {}
  external.set("spectest", { "print": 1234L })
  debug_inspect(
    resolve_import_function_ptr(external, "spectest", "print"),
    content="Some(1234)",
  )
  assert_true(
    resolve_import_function_ptr(external, "wasi_snapshot_preview1", "fd_write")
    is Some(_),
  )
  debug_inspect(
    resolve_import_function_ptr(external, "env", "memory"),
    content="None",
  )
}

///|
test "import trampolines: classify direct and hostcall pointers" {
  let external : Map[String, Map[String, Int64]] = {}
  external.set("env", { "host": -124L, "direct": 4096L })
  debug_inspect(
    resolve_import_function(external, "env", "host"),
    content="HostImportFunctionAddr(123)",
  )
  debug_inspect(
    resolve_import_function(external, "env", "direct"),
    content="DirectImportFunction(4096)",
  )
  debug_inspect(
    resolve_import_function(external, "env", "missing"),
    content="UnsupportedImportFunction",
  )
}
