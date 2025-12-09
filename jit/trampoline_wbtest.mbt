// Whitebox tests for JIT WASI trampolines

///|
test "trampoline pointers are valid" {
  // All 12 WASI trampolines should return non-zero function pointers
  assert_true(get_fd_write_ptr() != 0L)
  assert_true(get_fd_read_ptr() != 0L)
  assert_true(get_fd_close_ptr() != 0L)
  assert_true(get_fd_fdstat_get_ptr() != 0L)
  assert_true(get_fd_prestat_get_ptr() != 0L)
  assert_true(get_proc_exit_ptr() != 0L)
  assert_true(get_args_sizes_get_ptr() != 0L)
  assert_true(get_args_get_ptr() != 0L)
  assert_true(get_environ_sizes_get_ptr() != 0L)
  assert_true(get_environ_get_ptr() != 0L)
  assert_true(get_clock_time_get_ptr() != 0L)
  assert_true(get_random_get_ptr() != 0L)
}

///|
test "has_import_trampoline: supported functions" {
  let supported = [
    "fd_write", "fd_read", "fd_close", "fd_fdstat_get", "fd_prestat_get", "proc_exit",
    "args_sizes_get", "args_get", "environ_sizes_get", "environ_get", "clock_time_get",
    "random_get",
  ]
  for name in supported {
    assert_true(has_import_trampoline("wasi_snapshot_preview1", name))
  }
}

///|
test "has_import_trampoline: unsupported functions" {
  let unsupported = ["fd_seek", "path_open", "fd_readdir", "fd_pread"]
  for name in unsupported {
    assert_false(has_import_trampoline("wasi_snapshot_preview1", name))
  }
}

///|
test "has_import_trampoline: spectest module" {
  let supported = [
    "print", "print_i32", "print_i64", "print_f32", "print_f64",
    "print_i32_f32", "print_f64_f64",
  ]
  for name in supported {
    assert_true(has_import_trampoline("spectest", name))
  }
  // Unsupported spectest functions
  assert_false(has_import_trampoline("spectest", "unknown_func"))
}

///|
test "has_import_trampoline: unknown module" {
  assert_false(has_import_trampoline("env", "memory"))
  assert_false(has_import_trampoline("unknown_module", "some_func"))
}

///|
test "JITContext: allocation and free" {
  let ctx = JITContext::new(10)
  assert_true(ctx is Some(_))
  match ctx {
    Some(c) => {
      assert_true(c.ctx_ptr != 0L)
      assert_true(c.func_table_ptr != 0L)
      c.free()
    }
    None => ()
  }
}

///|
test "memory allocation" {
  let mem = alloc_memory(65536L)
  assert_true(mem != 0L)
  free_memory(mem)
}
