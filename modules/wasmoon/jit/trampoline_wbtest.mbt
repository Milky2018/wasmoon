// Whitebox tests for JIT WASI trampolines

///|
test "trampoline pointers are valid" {
  if @isa.ISA::current() is AMD64 {
    return
  }
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
  if @isa.ISA::current() is AMD64 {
    return
  }
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
  if @isa.ISA::current() is AMD64 {
    return
  }
  // All WASI functions are now supported (some as stubs returning ENOSYS)
  // Only unknown modules should return None
  assert_true(get_import_trampoline("unknown_module", "unknown_func") is None)
}

///|
test "get_import_trampoline: spectest module" {
  if @isa.ISA::current() is AMD64 {
    return
  }
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
  if @isa.ISA::current() is AMD64 {
    return
  }
  assert_true(get_import_trampoline("env", "memory") is None)
  assert_true(get_import_trampoline("unknown_module", "some_func") is None)
}

///|
test "JITContext: allocation (GC-managed)" {
  if @isa.ISA::current() is AMD64 {
    return
  }
  let ctx = JITContext::new(10)
  assert_true(ctx is Some(_))
  if ctx is Some(c) {
    assert_true(c.ptr() != 0L)
    // No need to call free() - GC handles cleanup
  }
}

///|
test "memory allocation" {
  if @isa.ISA::current() is AMD64 {
    return
  }
  let mem = alloc_memory(65536L)
  assert_true(mem != 0L)
  free_memory(mem)
}

// ============ Entry Trampoline Tests ============

///|
test "entry trampoline: no params, i32 result" {
  if @isa.ISA::current() is AMD64 {
    return
  }
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
      #|  0008: f30f1ff8  str x19, [sp, #-16]!
      #|  000c: f50300aa  mov x21, x0
      #|  0010: f30301aa  mov x19, x1
      #|block0:
      #|  0014: f10302aa  mov x17, x2
      #|  0018: 20023fd6  blr x17
      #|  001c: e30300aa  mov x3, x0
      #|  0020: 630200b9  str w3, [x19, #0]
      #|  0024: 040080d2  movz x4, #0, lsl #0
      #|  0028: e00304aa  mov x0, x4
      #|  002c: f30741f8  ldr x19, [sp], #16
      #|  0030: fd7bc1a8  ldp x29, x30, [sp], #16
      #|  0034: c0035fd6  ret
      #|
    ),
  )
}

///|
test "entry trampoline: i32 param, i32 result" {
  if @isa.ISA::current() is AMD64 {
    return
  }
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
      #|  0008: f30f1ff8  str x19, [sp, #-16]!
      #|  000c: f50300aa  mov x21, x0
      #|  0010: f30301aa  mov x19, x1
      #|block0:
      #|  0014: 630240b9  ldr w3, [x19, #0]
      #|  0018: f10302aa  mov x17, x2
      #|  001c: e10303aa  mov x1, x3
      #|  0020: 20023fd6  blr x17
      #|  0024: e40300aa  mov x4, x0
      #|  0028: 640a00b9  str w4, [x19, #8]
      #|  002c: 050080d2  movz x5, #0, lsl #0
      #|  0030: e00305aa  mov x0, x5
      #|  0034: f30741f8  ldr x19, [sp], #16
      #|  0038: fd7bc1a8  ldp x29, x30, [sp], #16
      #|  003c: c0035fd6  ret
      #|
    ),
  )
}

///|
test "entry trampoline: no params, no result" {
  if @isa.ISA::current() is AMD64 {
    return
  }
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
      #|  0008: f50300aa  mov x21, x0
      #|block0:
      #|  000c: f10302aa  mov x17, x2
      #|  0010: 20023fd6  blr x17
      #|  0014: 030080d2  movz x3, #0, lsl #0
      #|  0018: e00303aa  mov x0, x3
      #|  001c: fd7bc1a8  ldp x29, x30, [sp], #16
      #|  0020: c0035fd6  ret
      #|
    ),
  )
}

///|
test "entry trampoline: f64 param, f64 result" {
  if @isa.ISA::current() is AMD64 {
    return
  }
  // Generate trampoline for (f64) -> f64
  let mc = @emit.emit_entry_trampoline([@emit.TYPE_F64], [@emit.TYPE_F64])
  let bytes = mc.get_bytes()
  assert_true(bytes.length() > 0)
  inspect(
    mc.dump_disasm(),
    content=(
      #|  0000: fd7bbfa9  stp x29, x30, [sp, #-16]!
      #|  0004: fd030091  add x29, sp, #0
      #|  0008: f30f1ff8  str x19, [sp, #-16]!
      #|  000c: f50300aa  mov x21, x0
      #|  0010: f30301aa  mov x19, x1
      #|block0:
      #|  0014: 630240fd  ldr d3, [x19, #0]
      #|  0018: f10302aa  mov x17, x2
      #|  001c: 6040601e  fmov d0, d3
      #|  0020: 20023fd6  blr x17
      #|  0024: 0440601e  fmov d4, d0
      #|  0028: 640600fd  str d4, [x19, #8]
      #|  002c: 050080d2  movz x5, #0, lsl #0
      #|  0030: e00305aa  mov x0, x5
      #|  0034: f30741f8  ldr x19, [sp], #16
      #|  0038: fd7bc1a8  ldp x29, x30, [sp], #16
      #|  003c: c0035fd6  ret
      #|
    ),
  )
}

///|
test "entry trampoline: multiple params" {
  if @isa.ISA::current() is AMD64 {
    return
  }
  // Generate trampoline for (i32, i64, f32) -> i64
  let mc = @emit.emit_entry_trampoline(
    [@emit.TYPE_I32, @emit.TYPE_I64, @emit.TYPE_F32],
    [@emit.TYPE_I64],
  )
  let bytes = mc.get_bytes()
  assert_true(bytes.length() > 0)
  let disasm = mc.dump_disasm()
  assert_true(disasm.contains("stp x29, x30, [sp, #-16]!"))
  assert_true(disasm.contains("mov x21, x0"))
  assert_true(disasm.contains("ldr w"))
  assert_true(disasm.contains("ldr s"))
  assert_true(disasm.contains("blr x17"))
  assert_true(disasm.contains("str x"))
  assert_true(disasm.contains("ret"))
}

///|
test "entry trampoline: 8 f64 params" {
  if @isa.ISA::current() is AMD64 {
    return
  }
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
      #|  0008: f30f1ff8  str x19, [sp, #-16]!
      #|  000c: f50300aa  mov x21, x0
      #|  0010: f30301aa  mov x19, x1
      #|block0:
      #|  0014: 630240fd  ldr d3, [x19, #0]
      #|  0018: 640640fd  ldr d4, [x19, #8]
      #|  001c: 650a40fd  ldr d5, [x19, #16]
      #|  0020: 660e40fd  ldr d6, [x19, #24]
      #|  0024: 671240fd  ldr d7, [x19, #32]
      #|  0028: 721640fd  ldr d18, [x19, #40]
      #|  002c: 731a40fd  ldr d19, [x19, #48]
      #|  0030: 741e40fd  ldr d20, [x19, #56]
      #|  0034: f10302aa  mov x17, x2
      #|  0038: 6040601e  fmov d0, d3
      #|  003c: 8140601e  fmov d1, d4
      #|  0040: a240601e  fmov d2, d5
      #|  0044: c340601e  fmov d3, d6
      #|  0048: e440601e  fmov d4, d7
      #|  004c: 4542601e  fmov d5, d18
      #|  0050: 6642601e  fmov d6, d19
      #|  0054: 8742601e  fmov d7, d20
      #|  0058: 20023fd6  blr x17
      #|  005c: 1540601e  fmov d21, d0
      #|  0060: 752200fd  str d21, [x19, #64]
      #|  0064: 0c0080d2  movz x12, #0, lsl #0
      #|  0068: e0030caa  mov x0, x12
      #|  006c: f30741f8  ldr x19, [sp], #16
      #|  0070: fd7bc1a8  ldp x29, x30, [sp], #16
      #|  0074: c0035fd6  ret
      #|
    ),
  )
}

///|
test "entry trampoline: 20 i64 params (debug)" {
  if @isa.ISA::current() is AMD64 {
    return
  }
  // Generate trampoline for 20 i64 params -> i64 result
  let param_types : Array[Int] = []
  for _i in 0..<20 {
    param_types.push(@emit.TYPE_I64)
  }
  let mc = @emit.emit_entry_trampoline(param_types, [@emit.TYPE_I64])
  let bytes = mc.get_bytes()
  assert_true(bytes.length() > 0)
  let disasm = mc.dump_disasm()
  assert_true(disasm.contains("stp x29, x30, [sp, #-16]!"))
  assert_true(disasm.contains("blr x17"))
  assert_true(disasm.contains("#160]"))
  assert_true(disasm.contains("ldr x1, ["))
  assert_true(disasm.contains("[x31, #0]"))
  assert_true(disasm.contains("[x31, #96]"))
  assert_true(disasm.contains("ret"))
  let mut gpr_loads = 0
  let mut overflow_stores = 0
  for line in disasm.split("\n") {
    if line.contains(" ldr x") && line.contains("[x") && line.contains(", #") {
      gpr_loads = gpr_loads + 1
    }
    if line.contains(" str x") && line.contains("[x31, #") {
      overflow_stores = overflow_stores + 1
    }
  }
  // 20 i64 params: 20 loads from argv base (x19), with overflow args spilled.
  assert_true(gpr_loads >= 20)
  assert_true(overflow_stores >= 13)
}
