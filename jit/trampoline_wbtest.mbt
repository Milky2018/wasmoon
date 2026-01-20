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
      #|  0004: fd030091  add x29, sp, #0
      #|  0008: f357bfa9  stp x19, x21, [sp, #-16]!
      #|  000c: f50300aa  mov x21, x0
      #|  0010: f30301aa  mov x19, x1
      #|block0:
      #|  0014: f10302aa  mov x17, x2
      #|  0018: 20023fd6  blr x17
      #|  001c: e80300aa  mov x8, x0
      #|  0020: 680200b9  str w8, [x19, #0]
      #|  0024: 080080d2  movz x8, #0, lsl #0
      #|  0028: e00308aa  mov x0, x8
      #|  002c: f357c1a8  ldp x19, x21, [sp], #16
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
      #|  0004: fd030091  add x29, sp, #0
      #|  0008: f357bfa9  stp x19, x21, [sp, #-16]!
      #|  000c: f50300aa  mov x21, x0
      #|  0010: f30301aa  mov x19, x1
      #|block0:
      #|  0014: 680240b9  ldr w8, [x19, #0]
      #|  0018: f10302aa  mov x17, x2
      #|  001c: e10308aa  mov x1, x8
      #|  0020: 20023fd6  blr x17
      #|  0024: e80300aa  mov x8, x0
      #|  0028: 680a00b9  str w8, [x19, #8]
      #|  002c: 080080d2  movz x8, #0, lsl #0
      #|  0030: e00308aa  mov x0, x8
      #|  0034: f357c1a8  ldp x19, x21, [sp], #16
      #|  0038: fd7bc1a8  ldp x29, x30, [sp], #16
      #|  003c: c0035fd6  ret
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
      #|  0004: fd030091  add x29, sp, #0
      #|  0008: f50f1ff8  str x21, [sp, #-16]!
      #|  000c: f50300aa  mov x21, x0
      #|block0:
      #|  0010: f10302aa  mov x17, x2
      #|  0014: 20023fd6  blr x17
      #|  0018: 080080d2  movz x8, #0, lsl #0
      #|  001c: e00308aa  mov x0, x8
      #|  0020: f50741f8  ldr x21, [sp], #16
      #|  0024: fd7bc1a8  ldp x29, x30, [sp], #16
      #|  0028: c0035fd6  ret
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
      #|  0004: fd030091  add x29, sp, #0
      #|  0008: f357bfa9  stp x19, x21, [sp, #-16]!
      #|  000c: f50300aa  mov x21, x0
      #|  0010: f30301aa  mov x19, x1
      #|block0:
      #|  0014: 600240fd  ldr d0, [x19, #0]
      #|  0018: f10302aa  mov x17, x2
      #|  001c: 20023fd6  blr x17
      #|  0020: 600600fd  str d0, [x19, #8]
      #|  0024: 080080d2  movz x8, #0, lsl #0
      #|  0028: e00308aa  mov x0, x8
      #|  002c: f357c1a8  ldp x19, x21, [sp], #16
      #|  0030: fd7bc1a8  ldp x29, x30, [sp], #16
      #|  0034: c0035fd6  ret
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
      #|  0004: fd030091  add x29, sp, #0
      #|  0008: f357bfa9  stp x19, x21, [sp, #-16]!
      #|  000c: f50300aa  mov x21, x0
      #|  0010: f30301aa  mov x19, x1
      #|block0:
      #|  0014: 690240b9  ldr w9, [x19, #0]
      #|  0018: 680640f9  ldr x8, [x19, #8]
      #|  001c: 601240bd  ldr s0, [x19, #16]
      #|  0020: f10302aa  mov x17, x2
      #|  0024: e10309aa  mov x1, x9
      #|  0028: e20308aa  mov x2, x8
      #|  002c: 20023fd6  blr x17
      #|  0030: e80300aa  mov x8, x0
      #|  0034: 680e00f9  str x8, [x19, #24]
      #|  0038: 080080d2  movz x8, #0, lsl #0
      #|  003c: e00308aa  mov x0, x8
      #|  0040: f357c1a8  ldp x19, x21, [sp], #16
      #|  0044: fd7bc1a8  ldp x29, x30, [sp], #16
      #|  0048: c0035fd6  ret
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
      #|  0004: fd030091  add x29, sp, #0
      #|  0008: f357bfa9  stp x19, x21, [sp, #-16]!
      #|  000c: f50300aa  mov x21, x0
      #|  0010: f30301aa  mov x19, x1
      #|block0:
      #|  0014: 600240fd  ldr d0, [x19, #0]
      #|  0018: 610640fd  ldr d1, [x19, #8]
      #|  001c: 620a40fd  ldr d2, [x19, #16]
      #|  0020: 630e40fd  ldr d3, [x19, #24]
      #|  0024: 641240fd  ldr d4, [x19, #32]
      #|  0028: 651640fd  ldr d5, [x19, #40]
      #|  002c: 661a40fd  ldr d6, [x19, #48]
      #|  0030: 671e40fd  ldr d7, [x19, #56]
      #|  0034: f10302aa  mov x17, x2
      #|  0038: 20023fd6  blr x17
      #|  003c: 602200fd  str d0, [x19, #64]
      #|  0040: 080080d2  movz x8, #0, lsl #0
      #|  0044: e00308aa  mov x0, x8
      #|  0048: f357c1a8  ldp x19, x21, [sp], #16
      #|  004c: fd7bc1a8  ldp x29, x30, [sp], #16
      #|  0050: c0035fd6  ret
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
      #|  0004: fd030091  add x29, sp, #0
      #|  0008: fb73bfa9  stp x27, x28, [sp, #-16]!
      #|  000c: f96bbfa9  stp x25, x26, [sp, #-16]!
      #|  0010: f763bfa9  stp x23, x24, [sp, #-16]!
      #|  0014: f55bbfa9  stp x21, x22, [sp, #-16]!
      #|  0018: f353bfa9  stp x19, x20, [sp, #-16]!
      #|  001c: ff4302d1  sub sp, sp, #144
      #|  0020: ff0300f9  str x31, [x31, #0]
      #|  0024: f50300aa  mov x21, x0
      #|  0028: f30301aa  mov x19, x1
      #|block0:
      #|  002c: 6e0240f9  ldr x14, [x19, #0]
      #|  0030: 6d0640f9  ldr x13, [x19, #8]
      #|  0034: 6c0a40f9  ldr x12, [x19, #16]
      #|  0038: 6b0e40f9  ldr x11, [x19, #24]
      #|  003c: 6a1240f9  ldr x10, [x19, #32]
      #|  0040: 691640f9  ldr x9, [x19, #40]
      #|  0044: 681a40f9  ldr x8, [x19, #48]
      #|  0048: 701e40f9  ldr x16, [x19, #56]
      #|  004c: f04700f9  str x16, [x31, #136]
      #|  0050: 6f2240f9  ldr x15, [x19, #64]
      #|  0054: 742640f9  ldr x20, [x19, #72]
      #|  0058: 762a40f9  ldr x22, [x19, #80]
      #|  005c: 772e40f9  ldr x23, [x19, #88]
      #|  0060: 783240f9  ldr x24, [x19, #96]
      #|  0064: 793640f9  ldr x25, [x19, #104]
      #|  0068: 7a3a40f9  ldr x26, [x19, #112]
      #|  006c: 7b3e40f9  ldr x27, [x19, #120]
      #|  0070: 7c4240f9  ldr x28, [x19, #128]
      #|  0074: 714640f9  ldr x17, [x19, #136]
      #|  0078: f13b00f9  str x17, [x31, #112]
      #|  007c: 704a40f9  ldr x16, [x19, #144]
      #|  0080: f03f00f9  str x16, [x31, #120]
      #|  0084: 714e40f9  ldr x17, [x19, #152]
      #|  0088: f14300f9  str x17, [x31, #128]
      #|  008c: f04740f9  ldr x16, [x31, #136]
      #|  0090: f00300f9  str x16, [x31, #0]
      #|  0094: ef0700f9  str x15, [x31, #8]
      #|  0098: f40b00f9  str x20, [x31, #16]
      #|  009c: f60f00f9  str x22, [x31, #24]
      #|  00a0: f71300f9  str x23, [x31, #32]
      #|  00a4: f81700f9  str x24, [x31, #40]
      #|  00a8: f91b00f9  str x25, [x31, #48]
      #|  00ac: fa1f00f9  str x26, [x31, #56]
      #|  00b0: fb2300f9  str x27, [x31, #64]
      #|  00b4: fc2700f9  str x28, [x31, #72]
      #|  00b8: f03b40f9  ldr x16, [x31, #112]
      #|  00bc: f02b00f9  str x16, [x31, #80]
      #|  00c0: f03f40f9  ldr x16, [x31, #120]
      #|  00c4: f02f00f9  str x16, [x31, #88]
      #|  00c8: f04340f9  ldr x16, [x31, #128]
      #|  00cc: f03300f9  str x16, [x31, #96]
      #|  00d0: f10302aa  mov x17, x2
      #|  00d4: e1030eaa  mov x1, x14
      #|  00d8: e2030daa  mov x2, x13
      #|  00dc: e3030caa  mov x3, x12
      #|  00e0: e4030baa  mov x4, x11
      #|  00e4: e5030aaa  mov x5, x10
      #|  00e8: e60309aa  mov x6, x9
      #|  00ec: e70308aa  mov x7, x8
      #|  00f0: 20023fd6  blr x17
      #|  00f4: e80300aa  mov x8, x0
      #|  00f8: 685200f9  str x8, [x19, #160]
      #|  00fc: 080080d2  movz x8, #0, lsl #0
      #|  0100: e00308aa  mov x0, x8
      #|  0104: ff430291  add sp, sp, #144
      #|  0108: f353c1a8  ldp x19, x20, [sp], #16
      #|  010c: f55bc1a8  ldp x21, x22, [sp], #16
      #|  0110: f763c1a8  ldp x23, x24, [sp], #16
      #|  0114: f96bc1a8  ldp x25, x26, [sp], #16
      #|  0118: fb73c1a8  ldp x27, x28, [sp], #16
      #|  011c: fd7bc1a8  ldp x29, x30, [sp], #16
      #|  0120: c0035fd6  ret
      #|
    ),
  )
}
