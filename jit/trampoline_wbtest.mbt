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
test "get_import_trampoline: supported functions" {
  let supported = [
    "fd_write", "fd_read", "fd_close", "fd_fdstat_get", "fd_prestat_get", "proc_exit",
    "args_sizes_get", "args_get", "environ_sizes_get", "environ_get", "clock_time_get",
    "random_get",
  ]
  for name in supported {
    assert_true(
      get_import_trampoline("wasi_snapshot_preview1", name) is Some(_),
    )
  }
}

///|
test "get_import_trampoline: unsupported modules" {
  // All WASI functions are now supported (some as stubs returning ENOSYS)
  // Only unknown modules should return None
  assert_true(get_import_trampoline("unknown_module", "unknown_func") is None)
}

///|
test "get_import_trampoline: spectest module" {
  let supported = [
    "print", "print_i32", "print_i64", "print_f32", "print_f64", "print_i32_f32",
    "print_f64_f64", "print_char",
  ]
  for name in supported {
    assert_true(get_import_trampoline("spectest", name) is Some(_))
  }
  // Unsupported spectest functions
  assert_true(get_import_trampoline("spectest", "unknown_func") is None)
}

///|
test "get_import_trampoline: unknown module" {
  assert_true(get_import_trampoline("env", "memory") is None)
  assert_true(get_import_trampoline("unknown_module", "some_func") is None)
}

///|
test "JITContext: allocation (GC-managed)" {
  let ctx = JITContext::new(10)
  assert_true(ctx is Some(_))
  if ctx is Some(c) {
    assert_true(c.ptr() != 0L)
    // No need to call free() - GC handles cleanup
  }
}

///|
test "memory allocation" {
  let mem = alloc_memory(65536L)
  assert_true(mem != 0L)
  free_memory(mem)
}

// ============ Entry Trampoline Tests ============

///|
test "entry trampoline: no params, i32 result" {
  // Generate trampoline for () -> i32
  let mc = @emit.emit_entry_trampoline([], [@emit.TYPE_I32])
  let bytes = mc.get_bytes()
  // Should generate non-empty code
  assert_true(bytes.length() > 0)
  // Code should be 4-byte aligned (ARM64 instructions)
  assert_true(bytes.length() % 4 == 0)
  // Key: values_vec (X1) is now saved to X20 (callee-saved) in prologue
  // and results are stored to [X20+offset] instead of [X1+offset]
  inspect(
    mc.dump_disasm(),
    content=(
      #|  0000: fd7bbfa9  stp x29, x30, [sp, #-16]!
      #|  0004: fd031faa  mov x29, x31
      #|  0008: f353bfa9  stp x19, x20, [sp, #-16]!
      #|  000c: f30300aa  mov x19, x0
      #|  0010: f40301aa  mov x20, x1
      #|block0:
      #|  0014: f10302aa  mov x17, x2
      #|  0018: e10300aa  mov x1, x0
      #|  001c: 20023fd6  blr x17
      #|  0020: 800200b9  str w0, [x20, #0]
      #|  0024: 080080d2  movz x8, #0, lsl #0
      #|  0028: e00308aa  mov x0, x8
      #|  002c: f353c1a8  ldp x19, x20, [sp], #16
      #|  0030: fd7bc1a8  ldp x29, x30, [sp], #16
      #|  0034: c0035fd6  ret
      #|
    ),
  )
}

///|
test "entry trampoline: i32 param, i32 result" {
  // Generate trampoline for (i32) -> i32
  let mc = @emit.emit_entry_trampoline([@emit.TYPE_I32], [@emit.TYPE_I32])
  let bytes = mc.get_bytes()
  assert_true(bytes.length() > 0)
  assert_true(bytes.length() % 4 == 0)
  inspect(
    mc.dump_disasm(),
    content=(
      #|  0000: fd7bbfa9  stp x29, x30, [sp, #-16]!
      #|  0004: fd031faa  mov x29, x31
      #|  0008: f353bfa9  stp x19, x20, [sp, #-16]!
      #|  000c: ff4300d1  sub sp, sp, #16
      #|  0010: f30300aa  mov x19, x0
      #|  0014: f40301aa  mov x20, x1
      #|block0:
      #|  0018: 900240b9  ldr w16, [x20, #0]
      #|  001c: f00300f9  str x16, [x31, #0]
      #|  0020: f10302aa  mov x17, x2
      #|  0024: e10300aa  mov x1, x0
      #|  0028: e20340f9  ldr x2, [x31, #0]
      #|  002c: 20023fd6  blr x17
      #|  0030: 800a00b9  str w0, [x20, #8]
      #|  0034: 080080d2  movz x8, #0, lsl #0
      #|  0038: e00308aa  mov x0, x8
      #|  003c: ff430091  add sp, sp, #16
      #|  0040: f353c1a8  ldp x19, x20, [sp], #16
      #|  0044: fd7bc1a8  ldp x29, x30, [sp], #16
      #|  0048: c0035fd6  ret
      #|
    ),
  )
}

///|
test "entry trampoline: no params, no result" {
  // Generate trampoline for () -> ()
  let mc = @emit.emit_entry_trampoline([], [])
  let bytes = mc.get_bytes()
  assert_true(bytes.length() > 0)
  assert_true(bytes.length() % 4 == 0)
  inspect(
    mc.dump_disasm(),
    content=(
      #|  0000: fd7bbfa9  stp x29, x30, [sp, #-16]!
      #|  0004: fd031faa  mov x29, x31
      #|  0008: f30f1ff8  str x19, [sp, #-16]!
      #|  000c: f30300aa  mov x19, x0
      #|block0:
      #|  0010: f10302aa  mov x17, x2
      #|  0014: e10300aa  mov x1, x0
      #|  0018: 20023fd6  blr x17
      #|  001c: 080080d2  movz x8, #0, lsl #0
      #|  0020: e00308aa  mov x0, x8
      #|  0024: f30741f8  ldr x19, [sp], #16
      #|  0028: fd7bc1a8  ldp x29, x30, [sp], #16
      #|  002c: c0035fd6  ret
      #|
    ),
  )
}

///|
test "entry trampoline: f64 param, f64 result" {
  // Generate trampoline for (f64) -> f64
  let mc = @emit.emit_entry_trampoline([@emit.TYPE_F64], [@emit.TYPE_F64])
  let bytes = mc.get_bytes()
  assert_true(bytes.length() > 0)
  inspect(
    mc.dump_disasm(),
    content=(
      #|  0000: fd7bbfa9  stp x29, x30, [sp, #-16]!
      #|  0004: fd031faa  mov x29, x31
      #|  0008: f353bfa9  stp x19, x20, [sp, #-16]!
      #|  000c: f30300aa  mov x19, x0
      #|  0010: f40301aa  mov x20, x1
      #|block0:
      #|  0014: 800240fd  ldr d0, [x20, #0]
      #|  0018: f10302aa  mov x17, x2
      #|  001c: e10300aa  mov x1, x0
      #|  0020: 20023fd6  blr x17
      #|  0024: 800600fd  str d0, [x20, #8]
      #|  0028: 080080d2  movz x8, #0, lsl #0
      #|  002c: e00308aa  mov x0, x8
      #|  0030: f353c1a8  ldp x19, x20, [sp], #16
      #|  0034: fd7bc1a8  ldp x29, x30, [sp], #16
      #|  0038: c0035fd6  ret
      #|
    ),
  )
}

///|
test "entry trampoline: multiple params" {
  // Generate trampoline for (i32, i64, f32) -> i64
  let mc = @emit.emit_entry_trampoline(
    [@emit.TYPE_I32, @emit.TYPE_I64, @emit.TYPE_F32],
    [@emit.TYPE_I64],
  )
  let bytes = mc.get_bytes()
  assert_true(bytes.length() > 0)
  inspect(
    mc.dump_disasm(),
    content=(
      #|  0000: fd7bbfa9  stp x29, x30, [sp, #-16]!
      #|  0004: fd031faa  mov x29, x31
      #|  0008: f353bfa9  stp x19, x20, [sp, #-16]!
      #|  000c: ff4300d1  sub sp, sp, #16
      #|  0010: f30300aa  mov x19, x0
      #|  0014: f40301aa  mov x20, x1
      #|block0:
      #|  0018: 900240b9  ldr w16, [x20, #0]
      #|  001c: f00300f9  str x16, [x31, #0]
      #|  0020: 830640f9  ldr x3, [x20, #8]
      #|  0024: 801240bd  ldr s0, [x20, #16]
      #|  0028: f10302aa  mov x17, x2
      #|  002c: e10300aa  mov x1, x0
      #|  0030: e20340f9  ldr x2, [x31, #0]
      #|  0034: 20023fd6  blr x17
      #|  0038: 800e00f9  str x0, [x20, #24]
      #|  003c: 080080d2  movz x8, #0, lsl #0
      #|  0040: e00308aa  mov x0, x8
      #|  0044: ff430091  add sp, sp, #16
      #|  0048: f353c1a8  ldp x19, x20, [sp], #16
      #|  004c: fd7bc1a8  ldp x29, x30, [sp], #16
      #|  0050: c0035fd6  ret
      #|
    ),
  )
}

///|
test "entry trampoline: 8 f64 params" {
  // Generate trampoline for 8 f64 params -> f64 result
  let param_types : Array[Int] = []
  for _i in 0..<8 {
    param_types.push(@emit.TYPE_F64)
  }
  let mc = @emit.emit_entry_trampoline(param_types, [@emit.TYPE_F64])
  let bytes = mc.get_bytes()
  assert_true(bytes.length() > 0)
  inspect(
    mc.dump_disasm(),
    content=(
      #|  0000: fd7bbfa9  stp x29, x30, [sp, #-16]!
      #|  0004: fd031faa  mov x29, x31
      #|  0008: f353bfa9  stp x19, x20, [sp, #-16]!
      #|  000c: f30300aa  mov x19, x0
      #|  0010: f40301aa  mov x20, x1
      #|block0:
      #|  0014: 800240fd  ldr d0, [x20, #0]
      #|  0018: 810640fd  ldr d1, [x20, #8]
      #|  001c: 820a40fd  ldr d2, [x20, #16]
      #|  0020: 830e40fd  ldr d3, [x20, #24]
      #|  0024: 841240fd  ldr d4, [x20, #32]
      #|  0028: 851640fd  ldr d5, [x20, #40]
      #|  002c: 861a40fd  ldr d6, [x20, #48]
      #|  0030: 871e40fd  ldr d7, [x20, #56]
      #|  0034: f10302aa  mov x17, x2
      #|  0038: e10300aa  mov x1, x0
      #|  003c: 20023fd6  blr x17
      #|  0040: 802200fd  str d0, [x20, #64]
      #|  0044: 080080d2  movz x8, #0, lsl #0
      #|  0048: e00308aa  mov x0, x8
      #|  004c: f353c1a8  ldp x19, x20, [sp], #16
      #|  0050: fd7bc1a8  ldp x29, x30, [sp], #16
      #|  0054: c0035fd6  ret
      #|
    ),
  )
}

///|
test "entry trampoline: 20 i64 params (debug)" {
  // Generate trampoline for 20 i64 params -> i64 result
  let param_types : Array[Int] = []
  for _i in 0..<20 {
    param_types.push(@emit.TYPE_I64)
  }
  let mc = @emit.emit_entry_trampoline(param_types, [@emit.TYPE_I64])
  let bytes = mc.get_bytes()
  assert_true(bytes.length() > 0)
  inspect(
    mc.dump_disasm(),
    content=(
      #|  0000: fd7bbfa9  stp x29, x30, [sp, #-16]!
      #|  0004: fd031faa  mov x29, x31
      #|  0008: f96bbfa9  stp x25, x26, [sp, #-16]!
      #|  000c: f763bfa9  stp x23, x24, [sp, #-16]!
      #|  0010: f55bbfa9  stp x21, x22, [sp, #-16]!
      #|  0014: f353bfa9  stp x19, x20, [sp, #-16]!
      #|  0018: ff0302d1  sub sp, sp, #128
      #|  001c: f30300aa  mov x19, x0
      #|  0020: f40301aa  mov x20, x1
      #|block0:
      #|  0024: 900240f9  ldr x16, [x20, #0]
      #|  0028: f03b00f9  str x16, [x31, #112]
      #|  002c: 830640f9  ldr x3, [x20, #8]
      #|  0030: 840a40f9  ldr x4, [x20, #16]
      #|  0034: 850e40f9  ldr x5, [x20, #24]
      #|  0038: 861240f9  ldr x6, [x20, #32]
      #|  003c: 871640f9  ldr x7, [x20, #40]
      #|  0040: 9a1a40f9  ldr x26, [x20, #48]
      #|  0044: 881e40f9  ldr x8, [x20, #56]
      #|  0048: 8a2240f9  ldr x10, [x20, #64]
      #|  004c: 8b2640f9  ldr x11, [x20, #72]
      #|  0050: 8c2a40f9  ldr x12, [x20, #80]
      #|  0054: 8d2e40f9  ldr x13, [x20, #88]
      #|  0058: 8e3240f9  ldr x14, [x20, #96]
      #|  005c: 8f3640f9  ldr x15, [x20, #104]
      #|  0060: 953a40f9  ldr x21, [x20, #112]
      #|  0064: 963e40f9  ldr x22, [x20, #120]
      #|  0068: 974240f9  ldr x23, [x20, #128]
      #|  006c: 984640f9  ldr x24, [x20, #136]
      #|  0070: 994a40f9  ldr x25, [x20, #144]
      #|  0074: 894e40f9  ldr x9, [x20, #152]
      #|  0078: fa0300f9  str x26, [x31, #0]
      #|  007c: e80700f9  str x8, [x31, #8]
      #|  0080: ea0b00f9  str x10, [x31, #16]
      #|  0084: eb0f00f9  str x11, [x31, #24]
      #|  0088: ec1300f9  str x12, [x31, #32]
      #|  008c: ed1700f9  str x13, [x31, #40]
      #|  0090: ee1b00f9  str x14, [x31, #48]
      #|  0094: ef1f00f9  str x15, [x31, #56]
      #|  0098: f52300f9  str x21, [x31, #64]
      #|  009c: f62700f9  str x22, [x31, #72]
      #|  00a0: f72b00f9  str x23, [x31, #80]
      #|  00a4: f82f00f9  str x24, [x31, #88]
      #|  00a8: f93300f9  str x25, [x31, #96]
      #|  00ac: e93700f9  str x9, [x31, #104]
      #|  00b0: f10302aa  mov x17, x2
      #|  00b4: e10300aa  mov x1, x0
      #|  00b8: e23b40f9  ldr x2, [x31, #112]
      #|  00bc: 20023fd6  blr x17
      #|  00c0: 805200f9  str x0, [x20, #160]
      #|  00c4: 080080d2  movz x8, #0, lsl #0
      #|  00c8: e00308aa  mov x0, x8
      #|  00cc: ff030291  add sp, sp, #128
      #|  00d0: f353c1a8  ldp x19, x20, [sp], #16
      #|  00d4: f55bc1a8  ldp x21, x22, [sp], #16
      #|  00d8: f763c1a8  ldp x23, x24, [sp], #16
      #|  00dc: f96bc1a8  ldp x25, x26, [sp], #16
      #|  00e0: fd7bc1a8  ldp x29, x30, [sp], #16
      #|  00e4: c0035fd6  ret
      #|
    ),
  )
}
