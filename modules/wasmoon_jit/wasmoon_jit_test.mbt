///|
test "resolve runtime helper relocations into linked code" {
  let func = @machv.Function::new("caller")
  let entry = func.new_block()
  entry.append(func.new_inst(Call("wasmoon.runtime.helper")))
  let object = try! @machv_emit.emit_function_for_target(func, X64)
  let resolver = RuntimeSymbolResolver::new()
  resolver.add_symbol("wasmoon.runtime.helper", 4096L)
  let linked = try! link_code_object(object, resolver)
  inspect(linked.code.length(), content="5")
  inspect(linked.runtime_relocations.length(), content="1")
  inspect(linked.block_fixups.length(), content="0")
}

///|
test "resolve wasm function symbols into cwasm call fixups" {
  debug_inspect(resolve_wasm_func_symbol("wasm.func.12"), content="Some(12)")
  debug_inspect(resolve_wasm_func_symbol("wasm.func.x"), content="None")
  debug_inspect(resolve_wasm_func_symbol("runtime.func.12"), content="None")
  let func = @machv.Function::new("caller")
  let entry = func.new_block()
  entry.append(func.new_inst(Call("wasm.func.3")))
  entry.append(func.new_inst(Return))
  let object = try! @machv_emit.emit_function_for_target(func, X64)
  let linked = try! link_code_object(object, RuntimeSymbolResolver::new())
  inspect(linked.runtime_relocations.length(), content="1")
  debug_inspect(linked.runtime_relocations[0].fixup_idx, content="Some(3)")
  let artifact = CwasmArtifact::from_linked_code_for_target(
    linked,
    9,
    X86_64,
    "caller",
  )
  let restored = try! @cwasm.deserialize(artifact.serialize())
  inspect(restored.functions[0].call_fixups.length(), content="1")
  inspect(restored.functions[0].call_fixups[0].offset, content="0")
  inspect(restored.functions[0].call_fixups[0].func_idx, content="3")
  inspect(restored.functions[0].call_fixups[0].veneer_offset, content="-1")
}

///|
test "resolve legacy runtime fixup ids in wasmoon_jit" {
  inspect(gc_runtime_fixup_idx(0), content="-20000")
  inspect(jit_runtime_fixup_idx(13), content="-21013")
  inspect(exception_runtime_fixup_idx(11), content="-22011")
  inspect(resolve_runtime_func_fixup_idx(-20000) is Some(_), content="true")
  inspect(resolve_runtime_func_fixup_idx(-21013) is Some(_), content="true")
  inspect(resolve_runtime_func_fixup_idx(-22011) is Some(_), content="true")
  inspect(resolve_runtime_func_fixup_idx(-1) is None, content="true")
}

///|
test "default wasmoon runtime resolver maps memory.grow fixup" {
  let func = @machv.Function::new("memory_grow_caller")
  let entry = func.new_block()
  entry.append(func.new_inst(Call("wasmoon.runtime.memory_grow")))
  entry.append(func.new_inst(Return))
  let object = try! @machv_emit.emit_function_for_target(func, X64)
  let linked = try! link_code_object(
    object,
    RuntimeSymbolResolver::with_wasmoon_runtime_symbols(),
  )
  inspect(linked.runtime_relocations.length(), content="1")
  debug_inspect(linked.runtime_relocations[0].fixup_idx, content="Some(-21000)")
  let artifact = CwasmArtifact::from_linked_code_for_target(
    linked,
    7,
    X86_64,
    "memory_grow_caller",
  )
  let restored = try! @cwasm.deserialize(artifact.serialize())
  inspect(restored.functions[0].call_fixups.length(), content="1")
  inspect(restored.functions[0].call_fixups[0].func_idx, content="-21000")
}

///|
test "default wasmoon runtime resolver maps bulk memory fixups" {
  let resolver = RuntimeSymbolResolver::with_wasmoon_runtime_symbols()
  guard resolver.resolve_symbol("wasmoon.runtime.memory_fill") is Some(fill) else {
    fail("missing memory_fill runtime symbol")
  }
  guard resolver.resolve_symbol("wasmoon.runtime.memory_copy") is Some(copy) else {
    fail("missing memory_copy runtime symbol")
  }
  debug_inspect(fill.fixup_idx, content="Some(-21002)")
  debug_inspect(copy.fixup_idx, content="Some(-21004)")
}

///|
test "default wasmoon runtime resolver maps segment and table fixups" {
  let resolver = RuntimeSymbolResolver::with_wasmoon_runtime_symbols()
  let names = [
    ("wasmoon.runtime.memory_init", -21006),
    ("wasmoon.runtime.data_drop", -21007),
    ("wasmoon.runtime.table_grow", -21008),
    ("wasmoon.runtime.table_fill", -21009),
    ("wasmoon.runtime.table_copy", -21010),
    ("wasmoon.runtime.table_init", -21011),
    ("wasmoon.runtime.elem_drop", -21012),
  ]
  for item in names {
    let (name, fixup_idx) = item
    guard resolver.resolve_symbol(name) is Some(symbol) else {
      fail("missing runtime symbol \{name}")
    }
    debug_inspect(symbol.fixup_idx, content="Some(\{fixup_idx})")
  }
}

///|
test "resolve function-address fixup targets in wasmoon_jit" {
  inspect(resolve_func_addr_fixup_target(-20000, 0L) is Some(_), content="true")
  debug_inspect(resolve_func_addr_fixup_target(3, 0L), content="None")
  debug_inspect(resolve_func_addr_fixup_target(-1, 0L), content="None")
}

///|
test "JIT trap code policy lives in wasmoon_jit" {
  inspect(jit_trap_message(1), content="out of bounds memory access")
  inspect(jit_trap_message(10), content="gc precise roots unavailable")
  inspect(jit_trap_message(99), content="unknown trap")
  inspect(is_wasi_exit_trap_code(100), content="true")
  inspect(is_wasi_exit_trap_code(1), content="false")
  inspect(format_signal_name(11), content="SIGSEGV(11)")
  inspect(format_signal_name(123), content="SIG(123)")
}

///|
test "legacy trap immediates are classified in wasmoon_jit" {
  inspect(legacy_trap_immediate_from_message("unreachable"), content="0")
  inspect(
    legacy_trap_immediate_from_message("out of bounds memory access"),
    content="1",
  )
  inspect(
    legacy_trap_immediate_from_message("indirect call type mismatch"),
    content="2",
  )
  inspect(
    legacy_trap_immediate_from_message("invalid conversion to integer"),
    content="3",
  )
  inspect(
    legacy_trap_immediate_from_message("integer divide by zero"),
    content="4",
  )
  inspect(legacy_trap_immediate_from_message("integer overflow"), content="5")
  inspect(legacy_trap_immediate_from_message("backend trap"), content="6")
}

///|
test "trap report message formatting lives in wasmoon_jit" {
  inspect(format_u64_hex(-1L), content="0xffffffffffffffff")
  inspect(sanitize_debug_filename("a/b:c"), content="a_b_c")
  inspect(sanitize_debug_filename(""), content="unknown")
  let report : TrapReport = {
    trap_kind: "integer overflow",
    message: "integer overflow",
    signal: 11,
    signal_name: "SIGSEGV(11)",
    pc: 0x12L,
    lr: 0L,
    fp: 0L,
    frame_lr: 0L,
    fault_addr: 0x34L,
    brk_imm: 5,
    wasm_func_idx: Some(7),
    wasm_func_name: Some("callee"),
    wasm_offset: Some(0x20L),
    wasm_frames: [
      { pc: 0x12L, func_idx: 7, func_name: "callee", wasm_offset: 0x20L },
      { pc: 0x40L, func_idx: 3, func_name: "caller", wasm_offset: 0x10L },
    ],
    host_frames: [],
    dump_path: Some("/tmp/jit-trap.txt"),
  }
  inspect(
    format_trap_report_message(report),
    content="integer overflow (sig=SIGSEGV(11), pc=0x0000000000000012, addr=0x0000000000000034, brk_imm=5, wasm=7 'callee'+0x20, caller=3 'caller'+0x10, dump=/tmp/jit-trap.txt)",
  )
}

///|
test "wrap linked code as cwasm artifact" {
  let func = @machv.Function::new("caller")
  let entry = func.new_block()
  func.new_stack_slot(16, 16) |> ignore
  let addr_slot = func.new_stack_slot(8, 8)
  let addr = func.new_inst(StackAddr(addr_slot.id))
  addr.add_operand(@machv.Operand::def(Physical({ index: 1, class: Int })))
  entry.append(addr)
  entry.append(func.new_inst(Return))
  let object = try! @machv_emit.emit_function_for_target(func, X64)
  let resolver = RuntimeSymbolResolver::new()
  let linked = try! link_code_object(object, resolver)
  let artifact = CwasmArtifact::from_linked_code_for_target(
    linked,
    7,
    X86_64,
    "caller",
  )
  inspect(artifact.functions.length(), content="1")
  inspect(artifact.manifest().length(), content="7")
  let restored = try! @cwasm.deserialize(artifact.serialize())
  inspect(restored.function_count(), content="1")
  inspect(restored.functions[0].name, content="caller")
  inspect(restored.functions[0].frame_size, content="32")
}

///|
test "cwasm artifact preserves reusable stack map offsets" {
  let func = @machv.Function::new("caller")
  let entry = func.new_block()
  let call = func.new_inst(Call("wasmoon.runtime.helper"))
  call.set_stack_effect(CallFrame(16))
  entry.append(call)
  entry.append(func.new_inst(Return))
  let object = try! @machv_emit.emit_function_for_target(func, X64)
  let resolver = RuntimeSymbolResolver::new()
  resolver.add_symbol("wasmoon.runtime.helper", 4096L)
  let linked = try! link_code_object(object, resolver)
  let artifact = CwasmArtifact::from_linked_code_for_target(
    linked,
    7,
    X86_64,
    "caller",
  )
  inspect(artifact.stack_maps.length(), content="1")
  let restored = try! @cwasm.deserialize(artifact.serialize())
  inspect(restored.functions[0].gc_safepoints.length(), content="1")
  inspect(restored.functions[0].gc_safepoints[0].code_offset, content="0")
  inspect(restored.functions[0].gc_safepoints[0].metadata, content="0")
  inspect(restored.functions[0].gc_stackmap_blob.length(), content="12")
}

///|
test "cwasm artifact preserves runtime call fixup metadata" {
  let func = @machv.Function::new("caller")
  let entry = func.new_block()
  entry.append(func.new_inst(Call("wasmoon.runtime.hostcall")))
  entry.append(func.new_inst(Return))
  let object = try! @machv_emit.emit_function_for_target(func, X64)
  let resolver = RuntimeSymbolResolver::new()
  resolver.add_symbol_fixup(
    "wasmoon.runtime.hostcall",
    4096L,
    jit_runtime_fixup_idx(13),
  )
  let linked = try! link_code_object(object, resolver)
  let artifact = CwasmArtifact::from_linked_code_for_target(
    linked,
    9,
    X86_64,
    "caller",
  )
  let restored = try! @cwasm.deserialize(artifact.serialize())
  inspect(restored.functions[0].call_fixups.length(), content="1")
  inspect(restored.functions[0].call_fixups[0].offset, content="0")
  inspect(restored.functions[0].call_fixups[0].func_idx, content="-21013")
  inspect(restored.functions[0].call_fixups[0].veneer_offset, content="-1")
}

///|
test "aarch64 cwasm artifact materializes runtime call veneers" {
  let func = @machv.Function::new("caller")
  let entry = func.new_block()
  entry.append(func.new_inst(Call("wasmoon.runtime.hostcall")))
  entry.append(func.new_inst(Return))
  let object = try! @machv_emit.emit_function_for_target(func, AArch64)
  let resolver = RuntimeSymbolResolver::new()
  resolver.add_symbol_fixup(
    "wasmoon.runtime.hostcall",
    4096L,
    jit_runtime_fixup_idx(13),
  )
  let linked = try! link_code_object(object, resolver)
  let artifact = CwasmArtifact::from_linked_code_for_target(
    linked,
    9,
    AArch64,
    "caller",
  )
  inspect(artifact.call_veneers.length(), content="1")
  let restored = try! @cwasm.deserialize(artifact.serialize())
  inspect(restored.functions[0].call_fixups.length(), content="1")
  inspect(restored.functions[0].call_fixups[0].offset, content="0")
  inspect(restored.functions[0].call_fixups[0].func_idx, content="-21013")
  inspect(restored.functions[0].call_fixups[0].veneer_offset, content="8")
  inspect(restored.functions[0].code.length(), content="24")
  inspect(restored.functions[0].code[8], content="80")
  inspect(restored.functions[0].code[11], content="88")
  inspect(restored.functions[0].code[12], content="0")
  inspect(restored.functions[0].code[13], content="2")
  inspect(restored.functions[0].code[14], content="31")
  inspect(restored.functions[0].code[15], content="214")
}

///|
test "build moved cwasm entry from emitted code parts" {
  let entry = build_cwasm_entry_from_code(
    9,
    "compiled",
    [1, 2, 3, 4],
    16,
    0,
    2,
    1,
    func_addr_fixups=[{ offset: 4, func_idx: 7, reg: 16 }],
    call_fixups=[{ offset: 8, func_idx: -1000, veneer_offset: 12 }],
    gc_safepoint_offsets=[20],
    gc_safepoint_root_counts=[2],
    gc_safepoint_root_indices=[[0, 3]],
  )
  inspect(entry.func_idx, content="9")
  inspect(entry.code.length(), content="4")
  inspect(entry.frame_size, content="16")
  inspect(entry.func_addr_fixups[0].func_idx, content="7")
  inspect(entry.call_fixups[0].veneer_offset, content="12")
  inspect(entry.gc_safepoints.length(), content="1")
  inspect(entry.gc_safepoints[0].code_offset, content="20")
  inspect(entry.gc_safepoints[0].metadata, content="2")
  inspect(entry.gc_stackmap_blob.length(), content="24")
}

///|
test "build AArch64 direct-call stubs in wasmoon_jit" {
  let load = build_aarch64_load_imm64_fixed_bytes(16, 0L)
  inspect(load.length(), content="16")
  let stub = build_aarch64_direct_call_stub(0x1234L)
  inspect(stub.length(), content="20")
  inspect(stub[16], content="0")
  inspect(stub[17], content="2")
  inspect(stub[18], content="31")
  inspect(stub[19], content="214")
}

///|
test "build X64 direct-call stubs in wasmoon_jit" {
  let stub = build_x64_direct_call_stub(0x112233445566778L)
  inspect(stub.length(), content="13")
  inspect(stub[0], content="73")
  inspect(stub[1], content="187")
  inspect(stub[2], content="120")
  inspect(stub[3], content="103")
  inspect(stub[4], content="86")
  inspect(stub[5], content="69")
  inspect(stub[6], content="52")
  inspect(stub[7], content="35")
  inspect(stub[8], content="18")
  inspect(stub[9], content="1")
  inspect(stub[10], content="65")
  inspect(stub[11], content="255")
  inspect(stub[12], content="227")
}

///|
test "resolve direct-call fixup targets in wasmoon_jit" {
  inspect(direct_call_idx_memory_fill_mem0(), content="-1001")
  inspect(direct_call_idx_memory_copy_mem0(), content="-1002")
  let targets : Map[Int, Int64] = {}
  targets.set(direct_call_idx_memory_fill_mem0(), 0x1234L)
  debug_inspect(
    resolve_call_fixup_target(direct_call_idx_memory_fill_mem0(), 0L, targets),
    content="Some(4660)",
  )
  debug_inspect(resolve_call_fixup_target(-9999, 0L, targets), content="None")
  debug_inspect(resolve_call_fixup_target(3, 0L, targets), content="None")
}

///|
test "install direct-call stubs in wasmoon_jit" {
  let stubs = install_direct_call_stubs_for_target(X86_64) catch {
    err => fail(to_repr(err).to_string())
  }
  inspect(stubs.exec_codes.length(), content="2")
  inspect(
    stubs.targets.contains(direct_call_idx_memory_fill_mem0()),
    content="true",
  )
  inspect(
    stubs.targets.contains(direct_call_idx_memory_copy_mem0()),
    content="true",
  )
  let unsupported = try install_direct_call_stubs_for_target(Unknown) catch {
    UnsupportedDirectCallStubTarget(pseudo_idx~, code_size~) => {
      inspect(pseudo_idx, content="-1001")
      inspect(code_size, content="0")
      true
    }
    _ => false
  } noraise {
    _ => false
  }
  inspect(unsupported, content="true")
}

///|
test "compute required JIT context function count" {
  let mod = @cwasm.PrecompiledModule::new(AArch64)
  mod.add_import("wasi_snapshot_preview1", "fd_write", 4, 1)
  mod.add_import("spectest", "print", 1, 0)
  mod.add_function(@cwasm.CompiledEntry::new(7, "f7", [0xC3], 0, 0, 0, 0))
  inspect(required_context_function_count(mod, 5), content="8")
  inspect(required_context_function_count(mod, 12), content="12")
}

///|
test "encode AArch64 BL immediate for direct-call fixups" {
  debug_inspect(
    encode_aarch64_bl_imm26(0x1000L, 0x1008L),
    content="Some(-1811939326)",
  )
  debug_inspect(encode_aarch64_bl_imm26(0x1000L, 0x1002L), content="None")
  debug_inspect(encode_aarch64_bl_imm26(0x1000L, 0x9000000L), content="None")
}

///|
test "encode X64 call rel32 displacement for direct-call fixups" {
  debug_inspect(
    encode_x64_call_rel32_disp(0x1000L, 0x1010L),
    content="Some(11)",
  )
  debug_inspect(
    encode_x64_call_rel32_disp(0x1010L, 0x1000L),
    content="Some(-21)",
  )
  debug_inspect(
    encode_x64_call_rel32_disp(0x1000L, 0x80001005L),
    content="None",
  )
}

///|
test "plan Wasmoon JIT integration without leaking into machv_emit" {
  let milk = @milkir.Function::new("entry", @milkir.Signature::new([], []))
  let mach = @machv.Function::new("entry")
  let entry = mach.new_block()
  entry.append(mach.new_inst(Return))
  let x64_plan = try! plan_integration_for_target(milk, mach, X64)
  inspect(x64_plan.entry_symbol, content="entry")
  debug_inspect(x64_plan.target, content="X64")
  inspect(x64_plan.native_glue.length(), content="9")
  inspect(jit_ffi_native_stub_sources().length(), content="17")
  inspect(
    native_glue_covers_jit_ffi_stubs(glue=x64_plan.native_glue),
    content="true",
  )
  inspect(
    native_glue_covers_source(x64_plan.native_glue, "dwarf.c"),
    content="true",
  )
  inspect(x64_plan.object.debug_entries.length(), content="1")
  inspect(x64_plan.object.code.length(), content="1")
  debug_inspect(x64_plan.object.code, content="[195]")
  let aarch64_plan = try! plan_integration_for_target(milk, mach, AArch64)
  debug_inspect(aarch64_plan.target, content="AArch64")
  debug_inspect(aarch64_plan.object.code, content="[192, 3, 95, 214]")
}

///|
test "plan MilkIR through reusable JIT pipeline" {
  let signature = @milkir.Signature::new([I64, I64], [I64])
  let milk = @milkir.Function::new("add64", signature)
  let lhs = milk.new_value(I64)
  let rhs = milk.new_value(I64)
  let sum = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Iadd, [lhs, rhs], [sum]))
  entry.set_terminator(Return([sum]))
  let plan = plan_milkir_integration_for_target(milk, X64) catch {
    err => fail(to_repr(err).to_string())
  }
  debug_inspect(plan.target, content="X64")
  inspect(plan.entry_symbol, content="add64")
  debug_inspect(
    plan.object.code,
    content=(
      #|[
      #|  72,
      #|  137,
      #|  240,
      #|  72,
      #|  137,
      #|  254,
      #|  72,
      #|  137,
      #|  199,
      #|  72,
      #|  137,
      #|  240,
      #|  72,
      #|  1,
      #|  248,
      #|  72,
      #|  137,
      #|  192,
      #|  195,
      #|]
    ),
  )
  inspect(plan.object.debug_entries.length(), content="6")
}

///|
fn return_def_preg_index(inst : @machv.Instruction) -> Int {
  if inst.operands.length() > 1 && inst.operands[1].reg is Physical(preg) {
    preg.index
  } else {
    -1
  }
}

///|
test "Wasmoon JIT can request Wasm body ABI lowering" {
  let signature = @milkir.Signature::new([Ptr, I64, I64], [I64, I64])
  let milk = @milkir.Function::new("wasm_body", signature)
  let vmctx = milk.new_value(Ptr)
  let lhs = milk.new_value(I64)
  let rhs = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.set_terminator(Return([lhs, rhs]))
  let lowered = lower_wasm_body_milkir_for_target(milk, X64)
  guard lowered.param_pregs[0] is Some(vmctx_preg) else {
    fail("missing vmctx")
  }
  guard lowered.param_pregs[1] is Some(arg0_preg) else { fail("missing arg0") }
  inspect(vmctx_preg.index, content="7")
  inspect(arg0_preg.index, content="6")
  inspect(return_def_preg_index(lowered.blocks[0].instructions[1]), content="2")
  inspect(vmctx.id < lhs.id && lhs.id < rhs.id, content="true")
}

///|
test "plan Wasm body MilkIR through reusable JIT pipeline" {
  let signature = @milkir.Signature::new([Ptr, I64, I64], [I64])
  let milk = @milkir.Function::new("wasm_body_add64", signature)
  let vmctx = milk.new_value(Ptr)
  let lhs = milk.new_value(I64)
  let rhs = milk.new_value(I64)
  let sum = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Iadd, [lhs, rhs], [sum]))
  entry.set_terminator(Return([sum]))
  let plan = plan_wasm_body_milkir_integration_for_target(milk, X64) catch {
    err => fail(to_repr(err).to_string())
  }
  debug_inspect(plan.target, content="X64")
  inspect(plan.entry_symbol, content="wasm_body_add64")
  inspect(plan.object.code.length() > 0, content="true")
  inspect(plan.object.debug_entries.length() > 0, content="true")
  let lowered = lower_wasm_body_milkir_for_target(milk, X64)
  guard lowered.param_pregs[0] is Some(vmctx_preg) else {
    fail("missing vmctx")
  }
  guard lowered.param_pregs[1] is Some(arg0_preg) else { fail("missing arg0") }
  inspect(vmctx_preg.index, content="7")
  inspect(arg0_preg.index, content="6")
  inspect(vmctx.id < lhs.id && lhs.id < rhs.id, content="true")
}

///|
test "plan MilkIR branch block params through reusable JIT pipeline" {
  let signature = @milkir.Signature::new([], [I64])
  let milk = @milkir.Function::new("branch_block_params", signature)
  let cond = milk.new_value(I64)
  let true_value = milk.new_value(I64)
  let false_value = milk.new_value(I64)
  let true_param = milk.new_value(I64)
  let false_param = milk.new_value(I64)
  let entry = milk.new_block([])
  let then_block = milk.new_block([true_param])
  let else_block = milk.new_block([false_param])
  entry.append_inst(milk.new_inst(Iconst(1L), [], [cond]))
  entry.append_inst(milk.new_inst(Iconst(42L), [], [true_value]))
  entry.append_inst(milk.new_inst(Iconst(7L), [], [false_value]))
  entry.set_terminator(
    Branch(cond, then_block.id, [true_value], else_block.id, [false_value]),
  )
  then_block.set_terminator(Return([true_param]))
  else_block.set_terminator(Return([false_param]))
  let plan = try! plan_milkir_integration_for_target(milk, X64)
  inspect(plan.object.fixups.length() >= 4, content="true")
  inspect(plan.object.debug_entries.length() >= 7, content="true")
  let mut has_ret = false
  for byte in plan.object.code {
    if byte == 195 {
      has_ret = true
    }
  }
  inspect(has_ret, content="true")
}

///|
test "plan MilkIR CallPtr through reusable JIT pipeline" {
  let signature = @milkir.Signature::new([Ptr, Ptr, I64], [I64])
  let milk = @milkir.Function::new("callptr64", signature)
  let callee = milk.new_value(Ptr)
  let vmctx = milk.new_value(Ptr)
  let arg = milk.new_value(I64)
  let result = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(
    milk.new_inst(CallPtr(1, 1), [callee, vmctx, arg], [result]),
  )
  entry.set_terminator(Return([result]))
  let plan = plan_milkir_integration_for_target(milk, X64) catch {
    err => fail(to_repr(err).to_string())
  }
  debug_inspect(plan.target, content="X64")
  inspect(plan.entry_symbol, content="callptr64")
  debug_inspect(
    plan.object.code,
    content=(
      #|[
      #|  73,
      #|  137,
      #|  251,
      #|  72,
      #|  137,
      #|  247,
      #|  72,
      #|  137,
      #|  214,
      #|  73,
      #|  255,
      #|  211,
      #|  72,
      #|  137,
      #|  198,
      #|  72,
      #|  137,
      #|  240,
      #|  195,
      #|]
    ),
  )
  inspect(plan.object.debug_entries.length(), content="7")
}

///|
test "plan scalar entry trampoline through reusable JIT pipeline" {
  let params : Array[@types.ValueType] = [I64, I64]
  let results : Array[@types.ValueType] = [I64]
  let plan = plan_entry_trampoline_for_target(params, results, X64) catch {
    err => fail(to_repr(err).to_string())
  }
  debug_inspect(plan.target, content="X64")
  inspect(plan.entry_symbol, content="entry_trampoline")
  inspect(plan.object.code.length() > 0, content="true")
  let artifact = try! CwasmArtifact::from_jit_plan(
    plan,
    RuntimeSymbolResolver::new(),
    11,
  )
  let restored = try! @cwasm.deserialize(artifact.serialize())
  inspect(restored.functions[0].func_idx, content="11")
  inspect(restored.functions[0].name, content="entry_trampoline")
  inspect(restored.functions[0].code.length() > 0, content="true")
  let aarch64_plan = plan_entry_trampoline_for_target(params, results, AArch64) catch {
    err => fail(to_repr(err).to_string())
  }
  inspect(aarch64_plan.object.code.length() > 0, content="true")
  inspect(
    aarch64_plan.object.code[aarch64_plan.object.code.length() - 4],
    content="192",
  )
  inspect(
    aarch64_plan.object.code[aarch64_plan.object.code.length() - 1],
    content="214",
  )
}

///|
test "entry trampoline reports TODO for V128 lane packing" {
  let params : Array[@types.ValueType] = [V128]
  let results : Array[@types.ValueType] = []
  try plan_entry_trampoline_for_target(params, results, X64) catch {
    PipelineFailure(message=msg) =>
      inspect(msg.contains("TODO(ISS-026)"), content="true")
  } noraise {
    _ => fail("expected V128 trampoline planning to report TODO")
  }
}

///|
test "entry trampoline production gate is conservative" {
  inspect(can_use_reusable_entry_trampoline([I64, I64], [I64]), content="true")
  inspect(
    can_use_reusable_entry_trampoline([I64, I64, I64], [I64]),
    content="false",
  )
  inspect(can_use_reusable_entry_trampoline([F64], [F64]), content="false")
  inspect(can_use_reusable_entry_trampoline([V128], []), content="false")
  inspect(can_use_reusable_entry_trampoline([I64], [I64, I64]), content="false")
}

///|
test "entry trampoline signature planning lives in wasmoon_jit" {
  debug_inspect(
    entry_trampoline_type_codes([I32, I64, F32, F64, V128, ExternRef]),
    content="[0, 1, 2, 3, 4, 1]",
  )
  inspect(count_entry_trampoline_slots([I64, V128, ExternRef]), content="4")
  inspect(
    entry_trampoline_signature_hash([I64, I64], [I64]) ==
    entry_trampoline_signature_hash([I64, I64], [I64]),
    content="true",
  )
  inspect(
    entry_trampoline_signature_hash([I64, I64], [I64]) ==
    entry_trampoline_signature_hash([I64], [I64, I64]),
    content="false",
  )
}

///|
test "plan hostcall import trampoline values_vec layout" {
  let params : Array[@types.ValueType] = [
    I32,
    I64,
    F32,
    F64,
    V128,
    ExternRef,
    I64,
  ]
  let results : Array[@types.ValueType] = [I64, V128, F32]
  let layout = plan_hostcall_import_trampoline_layout(params, results, 2, 2)
  inspect(layout.arg_slots, content="8")
  inspect(layout.result_slots, content="4")
  inspect(layout.values_vec_bytes, content="96")
  inspect(layout.int_overflow_count, content="2")
  debug_inspect(layout.float_overflow_types, content="[V128]")
  inspect(hostcall_value_slot_count(V128), content="2")
  inspect(hostcall_value_byte_count(V128), content="16")
  inspect(hostcall_value_slot_count(ExternRef), content="1")
}

///|
test "machine-code entry trampolines support V128 registers" {
  let params : Array[@types.ValueType] = [V128]
  let results : Array[@types.ValueType] = [V128]
  let x64_code = build_entry_trampoline_for_target(params, results, X86_64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut x64_has_load = false
  let mut x64_has_store = false
  for i in 0..<(x64_code.length() - 3) {
    if x64_code[i] == 0xf3 && x64_code[i + 2] == 0x0f && x64_code[i + 3] == 0x6f {
      x64_has_load = true
    }
    if x64_code[i] == 0xf3 && x64_code[i + 2] == 0x0f && x64_code[i + 3] == 0x7f {
      x64_has_store = true
    }
  }
  inspect(x64_has_load, content="true")
  inspect(x64_has_store, content="true")
  let a64_code = build_entry_trampoline_for_target(params, results, AArch64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut a64_has_load = false
  let mut a64_has_store = false
  for i in 0..<(a64_code.length() - 3) {
    if a64_code[i + 3] == 0x3d {
      if (a64_code[i + 2] & 0xc0) == 0xc0 {
        a64_has_load = true
      } else if (a64_code[i + 2] & 0x80) == 0x80 {
        a64_has_store = true
      }
    }
  }
  inspect(a64_has_load, content="true")
  inspect(a64_has_store, content="true")
}

///|
test "hostcall and interpcall trampolines support V128 registers" {
  let params : Array[@types.ValueType] = [V128]
  let results : Array[@types.ValueType] = [V128]
  let x64_host = build_hostcall_import_trampoline_for_target(
    params,
    results,
    0,
    X86_64,
  ) catch {
    err => fail(to_repr(err).to_string())
  }
  let x64_interp = build_interpreter_fallback_trampoline_for_target(
    params,
    results,
    7,
    X86_64,
  ) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut x64_has_store = false
  let mut x64_has_load = false
  for code in [x64_host.code, x64_interp.code] {
    for i in 0..<(code.length() - 3) {
      if code[i] == 0xf3 && code[i + 2] == 0x0f && code[i + 3] == 0x7f {
        x64_has_store = true
      }
      if code[i] == 0xf3 && code[i + 2] == 0x0f && code[i + 3] == 0x6f {
        x64_has_load = true
      }
    }
  }
  inspect(x64_has_store, content="true")
  inspect(x64_has_load, content="true")
  let a64_host = build_hostcall_import_trampoline_for_target(
    params,
    results,
    0,
    AArch64,
  ) catch {
    err => fail(to_repr(err).to_string())
  }
  let a64_interp = build_interpreter_fallback_trampoline_for_target(
    params,
    results,
    7,
    AArch64,
  ) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut a64_has_store = false
  let mut a64_has_load = false
  for code in [a64_host.code, a64_interp.code] {
    for i in 0..<(code.length() - 3) {
      if code[i + 3] == 0x3d {
        if (code[i + 2] & 0xc0) == 0xc0 {
          a64_has_load = true
        } else if (code[i + 2] & 0x80) == 0x80 {
          a64_has_store = true
        }
      }
    }
  }
  inspect(a64_has_store, content="true")
  inspect(a64_has_load, content="true")
}

///|
fn code_contains_x64_rsp_int_load(code : Array[Int]) -> Bool {
  if code.length() < 4 {
    return false
  }
  for i in 0..<(code.length() - 3) {
    if code[i] == 0x4c &&
      code[i + 1] == 0x8b &&
      code[i + 2] == 0x94 &&
      code[i + 3] == 0x24 {
      return true
    }
  }
  false
}

///|
fn code_contains_x64_rsp_int_store(code : Array[Int]) -> Bool {
  if code.length() < 4 {
    return false
  }
  for i in 0..<(code.length() - 3) {
    if code[i] == 0x4c &&
      code[i + 1] == 0x89 &&
      code[i + 2] == 0x94 &&
      code[i + 3] == 0x24 {
      return true
    }
  }
  false
}

///|
fn code_contains_x64_r12_int_store(code : Array[Int]) -> Bool {
  if code.length() < 4 {
    return false
  }
  for i in 0..<(code.length() - 3) {
    if code[i] == 0x4d &&
      code[i + 1] == 0x89 &&
      code[i + 2] == 0x94 &&
      code[i + 3] == 0x24 {
      return true
    }
  }
  false
}

///|
fn code_contains_x64_r14_int_load(code : Array[Int]) -> Bool {
  if code.length() < 3 {
    return false
  }
  for i in 0..<(code.length() - 2) {
    if code[i] == 0x4d && code[i + 1] == 0x8b && code[i + 2] == 0x96 {
      return true
    }
  }
  false
}

///|
fn code_contains_x64_r14_int_store(code : Array[Int]) -> Bool {
  if code.length() < 3 {
    return false
  }
  for i in 0..<(code.length() - 2) {
    if code[i] == 0x4d && code[i + 1] == 0x89 && code[i + 2] == 0x96 {
      return true
    }
  }
  false
}

///|
fn code_contains_a64_x16_load_from_base(code : Array[Int], base : Int) -> Bool {
  if code.length() < 4 {
    return false
  }
  let expected = 0xf9400000 | ((base & 31) << 5) | 16
  let mask = 0xffc003ff
  for i in 0..<(code.length() - 3) {
    let word = code[i] |
      (code[i + 1] << 8) |
      (code[i + 2] << 16) |
      (code[i + 3] << 24)
    if (word & mask) == expected {
      return true
    }
  }
  false
}

///|
fn code_contains_a64_x16_store_to_base(code : Array[Int], base : Int) -> Bool {
  if code.length() < 4 {
    return false
  }
  let expected = 0xf9000000 | ((base & 31) << 5) | 16
  let mask = 0xffc003ff
  for i in 0..<(code.length() - 3) {
    let word = code[i] |
      (code[i + 1] << 8) |
      (code[i + 2] << 16) |
      (code[i + 3] << 24)
    if (word & mask) == expected {
      return true
    }
  }
  false
}

///|
test "hostcall and interpcall trampolines support stack-passed arguments" {
  let x64_params : Array[@types.ValueType] = [I64, I64, I64, I64, I64, I64]
  let a64_params : Array[@types.ValueType] = [
    I64,
    I64,
    I64,
    I64,
    I64,
    I64,
    I64,
    I64,
  ]
  let results : Array[@types.ValueType] = []
  let x64_host = build_hostcall_import_trampoline_for_target(
    x64_params,
    results,
    0,
    X86_64,
  ) catch {
    err => fail(to_repr(err).to_string())
  }
  let x64_interp = build_interpreter_fallback_trampoline_for_target(
    x64_params,
    results,
    7,
    X86_64,
  ) catch {
    err => fail(to_repr(err).to_string())
  }
  inspect(code_contains_x64_rsp_int_load(x64_host.code), content="true")
  inspect(code_contains_x64_rsp_int_store(x64_host.code), content="true")
  inspect(code_contains_x64_rsp_int_load(x64_interp.code), content="true")
  inspect(code_contains_x64_rsp_int_store(x64_interp.code), content="true")
  let a64_host = build_hostcall_import_trampoline_for_target(
    a64_params,
    results,
    0,
    AArch64,
  ) catch {
    err => fail(to_repr(err).to_string())
  }
  let a64_interp = build_interpreter_fallback_trampoline_for_target(
    a64_params,
    results,
    7,
    AArch64,
  ) catch {
    err => fail(to_repr(err).to_string())
  }
  inspect(
    code_contains_a64_x16_load_from_base(a64_host.code, 31),
    content="true",
  )
  inspect(
    code_contains_a64_x16_store_to_base(a64_host.code, 31),
    content="true",
  )
  inspect(
    code_contains_a64_x16_load_from_base(a64_interp.code, 31),
    content="true",
  )
  inspect(
    code_contains_a64_x16_store_to_base(a64_interp.code, 31),
    content="true",
  )
}

///|
test "entry trampolines support stack-passed arguments" {
  let x64_params : Array[@types.ValueType] = [I64, I64, I64, I64, I64, I64]
  let a64_params : Array[@types.ValueType] = [
    I64,
    I64,
    I64,
    I64,
    I64,
    I64,
    I64,
    I64,
  ]
  let results : Array[@types.ValueType] = []
  let x64_code = build_entry_trampoline_for_target(x64_params, results, X86_64) catch {
    err => fail(to_repr(err).to_string())
  }
  inspect(code_contains_x64_r14_int_load(x64_code), content="true")
  inspect(code_contains_x64_rsp_int_store(x64_code), content="true")
  let a64_code = build_entry_trampoline_for_target(a64_params, results, AArch64) catch {
    err => fail(to_repr(err).to_string())
  }
  inspect(code_contains_a64_x16_load_from_base(a64_code, 19), content="true")
  inspect(code_contains_a64_x16_store_to_base(a64_code, 31), content="true")
}

///|
test "hostcall and interpcall trampolines support overflow result areas" {
  let params : Array[@types.ValueType] = []
  let results : Array[@types.ValueType] = [
    I64,
    I64,
    I64,
    I64,
    I64,
    I64,
    I64,
    I64,
    I64,
  ]
  let x64_host = build_hostcall_import_trampoline_for_target(
    params,
    results,
    0,
    X86_64,
  ) catch {
    err => fail(to_repr(err).to_string())
  }
  let x64_interp = build_interpreter_fallback_trampoline_for_target(
    params,
    results,
    7,
    X86_64,
  ) catch {
    err => fail(to_repr(err).to_string())
  }
  inspect(code_contains_x64_rsp_int_load(x64_host.code), content="true")
  inspect(code_contains_x64_r12_int_store(x64_host.code), content="true")
  inspect(code_contains_x64_rsp_int_load(x64_interp.code), content="true")
  inspect(code_contains_x64_r12_int_store(x64_interp.code), content="true")
  let a64_host = build_hostcall_import_trampoline_for_target(
    params,
    results,
    0,
    AArch64,
  ) catch {
    err => fail(to_repr(err).to_string())
  }
  let a64_interp = build_interpreter_fallback_trampoline_for_target(
    params,
    results,
    7,
    AArch64,
  ) catch {
    err => fail(to_repr(err).to_string())
  }
  inspect(
    code_contains_a64_x16_load_from_base(a64_host.code, 31),
    content="true",
  )
  inspect(
    code_contains_a64_x16_store_to_base(a64_host.code, 23),
    content="true",
  )
  inspect(
    code_contains_a64_x16_load_from_base(a64_interp.code, 31),
    content="true",
  )
  inspect(
    code_contains_a64_x16_store_to_base(a64_interp.code, 23),
    content="true",
  )
}

///|
test "entry trampolines support overflow result areas" {
  let params : Array[@types.ValueType] = []
  let results : Array[@types.ValueType] = [
    I64,
    I64,
    I64,
    I64,
    I64,
    I64,
    I64,
    I64,
    I64,
  ]
  let x64_code = build_entry_trampoline_for_target(params, results, X86_64) catch {
    err => fail(to_repr(err).to_string())
  }
  inspect(code_contains_x64_rsp_int_load(x64_code), content="true")
  inspect(code_contains_x64_r14_int_store(x64_code), content="true")
  let a64_code = build_entry_trampoline_for_target(params, results, AArch64) catch {
    err => fail(to_repr(err).to_string())
  }
  inspect(code_contains_a64_x16_load_from_base(a64_code, 31), content="true")
  inspect(code_contains_a64_x16_store_to_base(a64_code, 19), content="true")
}

///|
test "plan MilkIR floating point through reusable JIT pipeline" {
  let signature = @milkir.Signature::new([F64, F64], [F64])
  let milk = @milkir.Function::new("fadd64", signature)
  let lhs = milk.new_value(F64)
  let rhs = milk.new_value(F64)
  let sum = milk.new_value(F64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Fadd, [lhs, rhs], [sum]))
  entry.set_terminator(Return([sum]))
  let plan = try! plan_milkir_integration_for_target(milk, X64)
  debug_inspect(plan.target, content="X64")
  inspect(plan.entry_symbol, content="fadd64")
  debug_inspect(
    plan.object.code,
    content="[242, 15, 16, 208, 242, 15, 88, 209, 242, 15, 16, 194, 195]",
  )
  inspect(plan.object.debug_entries.length(), content="3")
}

///|
test "plan MilkIR floating abs and neg through reusable JIT pipeline" {
  let signature = @milkir.Signature::new([F64], [F64])
  let milk = @milkir.Function::new("fabs_fneg64", signature)
  let input = milk.new_value(F64)
  let neg = milk.new_value(F64)
  let abs = milk.new_value(F64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Fneg, [input], [neg]))
  entry.append_inst(milk.new_inst(Fabs, [neg], [abs]))
  entry.set_terminator(Return([abs]))
  let plan = try! plan_milkir_integration_for_target(milk, X64)
  let mut has_abs_mask = false
  let mut has_neg_mask = false
  for byte in plan.object.code {
    if byte == 0x54 {
      has_abs_mask = true
    }
    if byte == 0x57 {
      has_neg_mask = true
    }
  }
  inspect(has_abs_mask, content="true")
  inspect(has_neg_mask, content="true")
  inspect(plan.object.code[plan.object.code.length() - 1], content="195")
}

///|
test "plan MilkIR f64 const through reusable x64 JIT pipeline" {
  let signature = @milkir.Signature::new([], [F64])
  let milk = @milkir.Function::new("fconst64_x64", signature)
  let output = milk.new_value(F64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Fconst(1.5), [], [output]))
  entry.set_terminator(Return([output]))
  let plan = plan_milkir_integration_for_target(milk, X64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_movq_to_xmm = false
  for i in 0..<(plan.object.code.length() - 1) {
    if plan.object.code[i] == 0x0f && plan.object.code[i + 1] == 0x6e {
      has_movq_to_xmm = true
    }
  }
  inspect(has_movq_to_xmm, content="true")
  inspect(plan.object.code[plan.object.code.length() - 1], content="195")
}

///|
test "plan MilkIR f32 const through reusable AArch64 JIT pipeline" {
  let signature = @milkir.Signature::new([], [F32])
  let milk = @milkir.Function::new("fconst32_aarch64", signature)
  let output = milk.new_value(F32)
  let entry = milk.new_block([])
  let bits = (1.25 : Float).reinterpret_as_int().to_int64()
  entry.append_inst(
    milk.new_inst(Fconst(bits.reinterpret_as_double()), [], [output]),
  )
  entry.set_terminator(Return([output]))
  let plan = plan_milkir_integration_for_target(milk, AArch64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_fmov_w_to_s = false
  for i in 0..<(plan.object.code.length() - 3) {
    if plan.object.code[i + 2] == 0x27 && plan.object.code[i + 3] == 0x1e {
      has_fmov_w_to_s = true
    }
  }
  inspect(has_fmov_w_to_s, content="true")
  inspect(plan.object.code[plan.object.code.length() - 4], content="192")
  inspect(plan.object.code[plan.object.code.length() - 1], content="214")
}

///|
test "plan MilkIR float promote through reusable x64 JIT pipeline" {
  let signature = @milkir.Signature::new([F32], [F64])
  let milk = @milkir.Function::new("fpromote_x64", signature)
  let input = milk.new_value(F32)
  let output = milk.new_value(F64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Fpromote, [input], [output]))
  entry.set_terminator(Return([output]))
  let plan = plan_milkir_integration_for_target(milk, X64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_cvtss2sd = false
  for i in 0..<(plan.object.code.length() - 2) {
    if plan.object.code[i] == 0xf3 &&
      plan.object.code[i + 1] == 0x0f &&
      plan.object.code[i + 2] == 0x5a {
      has_cvtss2sd = true
    }
  }
  inspect(has_cvtss2sd, content="true")
  inspect(plan.object.code[plan.object.code.length() - 1], content="195")
}

///|
test "plan MilkIR float demote through reusable AArch64 JIT pipeline" {
  let signature = @milkir.Signature::new([F64], [F32])
  let milk = @milkir.Function::new("fdemote_aarch64", signature)
  let input = milk.new_value(F64)
  let output = milk.new_value(F32)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Fdemote, [input], [output]))
  entry.set_terminator(Return([output]))
  let plan = plan_milkir_integration_for_target(milk, AArch64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_fcvt_s_d = false
  for i in 0..<(plan.object.code.length() - 3) {
    if (plan.object.code[i + 1] & 0x40) == 0x40 &&
      plan.object.code[i + 2] == 0x62 &&
      plan.object.code[i + 3] == 0x1e {
      has_fcvt_s_d = true
    }
  }
  inspect(has_fcvt_s_d, content="true")
  inspect(plan.object.code[plan.object.code.length() - 4], content="192")
  inspect(plan.object.code[plan.object.code.length() - 1], content="214")
}

///|
test "plan MilkIR float ceil through reusable x64 JIT pipeline" {
  let signature = @milkir.Signature::new([F32], [F32])
  let milk = @milkir.Function::new("fceil_x64", signature)
  let input = milk.new_value(F32)
  let output = milk.new_value(F32)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Fceil, [input], [output]))
  entry.set_terminator(Return([output]))
  let plan = plan_milkir_integration_for_target(milk, X64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_roundss_ceil = false
  for i in 0..<(plan.object.code.length() - 4) {
    if plan.object.code[i] == 0x0f &&
      plan.object.code[i + 1] == 0x3a &&
      plan.object.code[i + 2] == 0x0a &&
      plan.object.code[i + 4] == 0x02 {
      has_roundss_ceil = true
    }
  }
  inspect(has_roundss_ceil, content="true")
  inspect(plan.object.code[plan.object.code.length() - 1], content="195")
}

///|
test "plan MilkIR float nearest through reusable AArch64 JIT pipeline" {
  let signature = @milkir.Signature::new([F64], [F64])
  let milk = @milkir.Function::new("fnearest_aarch64", signature)
  let input = milk.new_value(F64)
  let output = milk.new_value(F64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Fnearest, [input], [output]))
  entry.set_terminator(Return([output]))
  let plan = plan_milkir_integration_for_target(milk, AArch64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_frintn_d = false
  for i in 0..<(plan.object.code.length() - 3) {
    if (plan.object.code[i + 1] & 0x40) == 0x40 &&
      plan.object.code[i + 2] == 0x64 &&
      plan.object.code[i + 3] == 0x1e {
      has_frintn_d = true
    }
  }
  inspect(has_frintn_d, content="true")
  inspect(plan.object.code[plan.object.code.length() - 4], content="192")
  inspect(plan.object.code[plan.object.code.length() - 1], content="214")
}

///|
test "plan MilkIR float compare through reusable x64 JIT pipeline" {
  let signature = @milkir.Signature::new([F64, F64], [I32])
  let milk = @milkir.Function::new("fcmp_eq_x64", signature)
  let lhs = milk.new_value(F64)
  let rhs = milk.new_value(F64)
  let output = milk.new_value(I32)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Fcmp(Eq), [lhs, rhs], [output]))
  entry.set_terminator(Return([output]))
  let plan = plan_milkir_integration_for_target(milk, X64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_ucomisd = false
  let mut has_setnp = false
  for i in 0..<(plan.object.code.length() - 2) {
    if plan.object.code[i] == 0x66 &&
      plan.object.code[i + 1] == 0x0f &&
      plan.object.code[i + 2] == 0x2e {
      has_ucomisd = true
    }
    if plan.object.code[i] == 0x0f && plan.object.code[i + 1] == 0x9b {
      has_setnp = true
    }
  }
  inspect(has_ucomisd, content="true")
  inspect(has_setnp, content="true")
  inspect(plan.object.code[plan.object.code.length() - 1], content="195")
}

///|
test "plan MilkIR float compare through reusable AArch64 JIT pipeline" {
  let signature = @milkir.Signature::new([F32, F32], [I32])
  let milk = @milkir.Function::new("fcmp_lt_aarch64", signature)
  let lhs = milk.new_value(F32)
  let rhs = milk.new_value(F32)
  let output = milk.new_value(I32)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Fcmp(Lt), [lhs, rhs], [output]))
  entry.set_terminator(Return([output]))
  let plan = plan_milkir_integration_for_target(milk, AArch64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_fcmp_s = false
  let mut has_cset_mi = false
  for i in 0..<(plan.object.code.length() - 3) {
    if (plan.object.code[i + 2] & 0xe0) == 0x20 &&
      plan.object.code[i + 3] == 0x1e {
      has_fcmp_s = true
    }
    if (plan.object.code[i + 1] & 0xf0) == 0x50 &&
      plan.object.code[i + 2] == 0x9f &&
      plan.object.code[i + 3] == 0x9a {
      has_cset_mi = true
    }
  }
  inspect(has_fcmp_s, content="true")
  inspect(has_cset_mi, content="true")
  inspect(plan.object.code[plan.object.code.length() - 4], content="192")
  inspect(plan.object.code[plan.object.code.length() - 1], content="214")
}

///|
test "plan MilkIR generic memory through reusable x64 JIT pipeline" {
  let signature = @milkir.Signature::new([Ptr, I32], [I32])
  let milk = @milkir.Function::new("generic_mem_x64", signature)
  let ptr = milk.new_value(Ptr)
  let value = milk.new_value(I32)
  let loaded = milk.new_value(I32)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Store, [ptr, value], []))
  entry.append_inst(milk.new_inst(Load, [ptr], [loaded]))
  entry.set_terminator(Return([loaded]))
  let plan = plan_milkir_integration_for_target(milk, X64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_store = false
  let mut has_load = false
  for i in 0..<(plan.object.code.length() - 1) {
    if plan.object.code[i] == 0x89 {
      has_store = true
    }
    if plan.object.code[i] == 0x8b {
      has_load = true
    }
  }
  inspect(has_store, content="true")
  inspect(has_load, content="true")
  inspect(plan.object.code[plan.object.code.length() - 1], content="195")
}

///|
test "plan MilkIR narrow memory through reusable x64 JIT pipeline" {
  let builder = @milkir.IRBuilder::new("narrow_mem_x64")
  let ptr = builder.add_param(Ptr)
  let value = builder.add_param(I32)
  builder.add_result(I32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  builder.store_ptr_narrow(16, ptr, value, builder.iconst_i64(8L))
  let loaded = builder.load_ptr_narrow(
    I32,
    8,
    false,
    ptr,
    builder.iconst_i64(4L),
  )
  builder.return_([loaded])
  let plan = plan_milkir_integration_for_target(builder.get_function(), X64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_store16 = false
  let mut has_load8u = false
  for i in 0..<(plan.object.code.length() - 2) {
    if plan.object.code[i] == 0x66 && plan.object.code[i + 1] == 0x89 {
      has_store16 = true
    }
    if plan.object.code[i] == 0x0f && plan.object.code[i + 1] == 0xb6 {
      has_load8u = true
    }
  }
  inspect(has_store16, content="true")
  inspect(has_load8u, content="true")
  inspect(plan.object.code[plan.object.code.length() - 1], content="195")
}

///|
test "plan MilkIR generic memory through reusable AArch64 JIT pipeline" {
  let signature = @milkir.Signature::new([Ptr, I32], [I32])
  let milk = @milkir.Function::new("generic_mem_aarch64", signature)
  let ptr = milk.new_value(Ptr)
  let value = milk.new_value(I32)
  let loaded = milk.new_value(I32)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Store, [ptr, value], []))
  entry.append_inst(milk.new_inst(Load, [ptr], [loaded]))
  entry.set_terminator(Return([loaded]))
  let plan = plan_milkir_integration_for_target(milk, AArch64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_str_w = false
  let mut has_ldr_w = false
  for i in 0..<(plan.object.code.length() - 3) {
    if plan.object.code[i + 3] == 0xb9 {
      has_str_w = true
    }
    if plan.object.code[i + 3] == 0xb9 &&
      (plan.object.code[i + 2] & 0x40) == 0x40 {
      has_ldr_w = true
    }
  }
  inspect(has_str_w, content="true")
  inspect(has_ldr_w, content="true")
  inspect(plan.object.code[plan.object.code.length() - 4], content="192")
  inspect(plan.object.code[plan.object.code.length() - 1], content="214")
}

///|
test "plan MilkIR narrow memory through reusable AArch64 JIT pipeline" {
  let builder = @milkir.IRBuilder::new("narrow_mem_aarch64")
  let ptr = builder.add_param(Ptr)
  let value = builder.add_param(I32)
  builder.add_result(I32)
  let entry = builder.create_block()
  builder.switch_to_block(entry)
  builder.store_ptr_narrow(16, ptr, value, builder.iconst_i64(8L))
  let loaded = builder.load_ptr_narrow(
    I32,
    8,
    true,
    ptr,
    builder.iconst_i64(4L),
  )
  builder.return_([loaded])
  let plan = plan_milkir_integration_for_target(builder.get_function(), AArch64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_store16 = false
  let mut has_load8s = false
  for i in 0..<(plan.object.code.length() - 3) {
    if plan.object.code[i + 3] == 0x79 {
      has_store16 = true
    }
    if plan.object.code[i + 2] == 0x80 && plan.object.code[i + 3] == 0x39 {
      has_load8s = true
    }
  }
  inspect(has_store16, content="true")
  inspect(has_load8s, content="true")
  inspect(plan.object.code[plan.object.code.length() - 4], content="192")
  inspect(plan.object.code[plan.object.code.length() - 1], content="214")
}

///|
test "plan MilkIR scalar float memory through reusable x64 JIT pipeline" {
  let signature = @milkir.Signature::new([Ptr, F64], [F64])
  let milk = @milkir.Function::new("float_mem_x64", signature)
  let ptr = milk.new_value(Ptr)
  let value = milk.new_value(F64)
  let loaded = milk.new_value(F64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Store, [ptr, value], []))
  entry.append_inst(milk.new_inst(Load, [ptr], [loaded]))
  entry.set_terminator(Return([loaded]))
  let plan = plan_milkir_integration_for_target(milk, X64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_movsd_store = false
  let mut has_movsd_load = false
  for i in 0..<(plan.object.code.length() - 2) {
    if plan.object.code[i] == 0xf2 &&
      plan.object.code[i + 1] == 0x0f &&
      plan.object.code[i + 2] == 0x11 {
      has_movsd_store = true
    }
    if plan.object.code[i] == 0xf2 &&
      plan.object.code[i + 1] == 0x0f &&
      plan.object.code[i + 2] == 0x10 {
      has_movsd_load = true
    }
  }
  inspect(has_movsd_store, content="true")
  inspect(has_movsd_load, content="true")
  inspect(plan.object.code[plan.object.code.length() - 1], content="195")
}

///|
test "plan MilkIR scalar float memory through reusable AArch64 JIT pipeline" {
  let signature = @milkir.Signature::new([Ptr, F64], [F64])
  let milk = @milkir.Function::new("float_mem_aarch64", signature)
  let ptr = milk.new_value(Ptr)
  let value = milk.new_value(F64)
  let loaded = milk.new_value(F64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Store, [ptr, value], []))
  entry.append_inst(milk.new_inst(Load, [ptr], [loaded]))
  entry.set_terminator(Return([loaded]))
  let plan = plan_milkir_integration_for_target(milk, AArch64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_str_d = false
  let mut has_ldr_d = false
  for i in 0..<(plan.object.code.length() - 3) {
    if plan.object.code[i + 3] == 0xfd {
      if (plan.object.code[i + 2] & 0x40) == 0x40 {
        has_ldr_d = true
      } else {
        has_str_d = true
      }
    }
  }
  inspect(has_str_d, content="true")
  inspect(has_ldr_d, content="true")
  inspect(plan.object.code[plan.object.code.length() - 4], content="192")
  inspect(plan.object.code[plan.object.code.length() - 1], content="214")
}

///|
test "plan MilkIR vector memory through reusable x64 JIT pipeline" {
  let signature = @milkir.Signature::new([Ptr, V128], [])
  let milk = @milkir.Function::new("vector_mem_x64", signature)
  let ptr = milk.new_value(Ptr)
  let value = milk.new_value(V128)
  let loaded = milk.new_value(V128)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Store, [ptr, value], []))
  entry.append_inst(milk.new_inst(Load, [ptr], [loaded]))
  entry.set_terminator(Return([]))
  let plan = plan_milkir_integration_for_target(milk, X64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_movdqu_store = false
  let mut has_movdqu_load = false
  for i in 0..<(plan.object.code.length() - 2) {
    if plan.object.code[i] == 0xf3 &&
      plan.object.code[i + 1] == 0x0f &&
      plan.object.code[i + 2] == 0x7f {
      has_movdqu_store = true
    }
    if plan.object.code[i] == 0xf3 &&
      plan.object.code[i + 1] == 0x0f &&
      plan.object.code[i + 2] == 0x6f {
      has_movdqu_load = true
    }
  }
  inspect(has_movdqu_store, content="true")
  inspect(has_movdqu_load, content="true")
  inspect(plan.object.code[plan.object.code.length() - 1], content="195")
}

///|
test "plan MilkIR vector memory through reusable AArch64 JIT pipeline" {
  let signature = @milkir.Signature::new([Ptr, V128], [])
  let milk = @milkir.Function::new("vector_mem_aarch64", signature)
  let ptr = milk.new_value(Ptr)
  let value = milk.new_value(V128)
  let loaded = milk.new_value(V128)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Store, [ptr, value], []))
  entry.append_inst(milk.new_inst(Load, [ptr], [loaded]))
  entry.set_terminator(Return([]))
  let plan = plan_milkir_integration_for_target(milk, AArch64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_str_q = false
  let mut has_ldr_q = false
  for i in 0..<(plan.object.code.length() - 3) {
    if plan.object.code[i + 3] == 0x3d {
      if (plan.object.code[i + 2] & 0xc0) == 0xc0 {
        has_ldr_q = true
      } else if (plan.object.code[i + 2] & 0x80) == 0x80 {
        has_str_q = true
      }
    }
  }
  inspect(has_str_q, content="true")
  inspect(has_ldr_q, content="true")
  inspect(plan.object.code[plan.object.code.length() - 4], content="192")
  inspect(plan.object.code[plan.object.code.length() - 1], content="214")
}

///|
test "emit MachV regalloc stack spills through reusable x64 pipeline" {
  let func = @machv.Function::new("spilled_x64")
  let entry = func.new_block()
  let values : Array[@machv.VReg] = []
  for i in 0..<5 {
    let value = func.new_vreg(Int)
    values.push(value)
    let inst = func.new_inst(IntConst(i.to_int64()))
    inst.add_operand(@machv.Operand::def(Virtual(value)))
    entry.append(inst)
  }
  let sum = func.new_vreg(Int)
  let add = func.new_inst(IntAdd)
  add.add_operand(@machv.Operand::use_reg(Virtual(values[0])))
  add.add_operand(@machv.Operand::use_reg(Virtual(values[4])))
  add.add_operand(@machv.Operand::def(Virtual(sum)))
  entry.append(add)
  entry.set_terminator(TermReturn([]))
  let p0 : @machv.PReg = { index: 0, class: Int }
  let p1 : @machv.PReg = { index: 1, class: Int }
  let result = @machv_regalloc.allocate_and_apply(func, [p0, p1])
  let object = try! @machv_emit.emit_function_for_target(func, X64)
  let mut has_stack_load = false
  let mut has_stack_store = false
  for i in 0..<(object.code.length() - 4) {
    if object.code[i] == 0x48 &&
      object.code[i + 1] == 0x8b &&
      object.code[i + 3] == 0x24 {
      has_stack_load = true
    }
    if object.code[i] == 0x48 &&
      object.code[i + 1] == 0x89 &&
      object.code[i + 3] == 0x24 {
      has_stack_store = true
    }
  }
  inspect(result.spill_slots.length() > 0, content="true")
  inspect(has_stack_load, content="true")
  inspect(has_stack_store, content="true")
  inspect(object.code[object.code.length() - 1], content="195")
}

///|
test "plan Wasm body return area through reusable JIT pipeline" {
  let milk = @milkir.Function::new_empty("wasm_return_area")
  let values : Array[@milkir.Value] = []
  let entry = milk.new_block([])
  for i in 0..<9 {
    let value = milk.new_value(I64)
    milk.add_result(I64)
    entry.append_inst(milk.new_inst(Iconst(i.to_int64()), [], [value]))
    values.push(value)
  }
  entry.set_terminator(Return(values))
  let x64_plan = plan_wasm_body_milkir_integration_for_target(milk, X64) catch {
    err => fail(to_repr(err).to_string())
  }
  inspect(x64_plan.object.code.length() > 0, content="true")
  let a64_plan = plan_wasm_body_milkir_integration_for_target(milk, AArch64) catch {
    err => fail(to_repr(err).to_string())
  }
  inspect(a64_plan.object.code.length() > 0, content="true")
}

///|
test "plan MilkIR StackAddr through reusable x64 JIT pipeline" {
  let signature = @milkir.Signature::new([], [Ptr])
  let milk = @milkir.Function::new("stack_addr_x64", signature)
  let slot = milk.new_stack_slot(16, 16)
  let ptr = milk.new_value(Ptr)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(StackAddr(slot), [], [ptr]))
  entry.set_terminator(Return([ptr]))
  let plan = plan_milkir_integration_for_target(milk, X64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_lea = false
  for i in 0..<(plan.object.code.length() - 1) {
    if plan.object.code[i] == 0x48 && plan.object.code[i + 1] == 0x8d {
      has_lea = true
    }
  }
  inspect(has_lea, content="true")
  inspect(plan.object.code[plan.object.code.length() - 1], content="195")
}

///|
test "plan MilkIR popcnt through reusable x64 JIT pipeline" {
  let signature = @milkir.Signature::new([I64], [I64])
  let milk = @milkir.Function::new("popcnt_x64", signature)
  let value = milk.new_value(I64)
  let count = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Popcnt, [value], [count]))
  entry.set_terminator(Return([count]))
  let plan = plan_milkir_integration_for_target(milk, X64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_imul = false
  let mut has_shift = false
  for i in 0..<(plan.object.code.length() - 1) {
    if plan.object.code[i] == 0x0f && plan.object.code[i + 1] == 0xaf {
      has_imul = true
    }
    if plan.object.code[i] == 0xd3 {
      has_shift = true
    }
  }
  inspect(has_imul, content="true")
  inspect(has_shift, content="true")
  inspect(plan.object.code[plan.object.code.length() - 1], content="195")
}

///|
test "plan MilkIR bitcast through reusable x64 JIT pipeline" {
  let signature = @milkir.Signature::new([I64], [F64])
  let milk = @milkir.Function::new("bitcast_i64_f64", signature)
  let input = milk.new_value(I64)
  let output = milk.new_value(F64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Bitcast, [input], [output]))
  entry.set_terminator(Return([output]))
  let plan = plan_milkir_integration_for_target(milk, X64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_movq_to_xmm = false
  for i in 0..<(plan.object.code.length() - 2) {
    if plan.object.code[i] == 0x0f && plan.object.code[i + 1] == 0x6e {
      has_movq_to_xmm = true
    }
  }
  inspect(has_movq_to_xmm, content="true")
  inspect(plan.object.code[plan.object.code.length() - 1], content="195")
}

///|
test "plan MilkIR bitcast through reusable AArch64 JIT pipeline" {
  let signature = @milkir.Signature::new([F64], [I64])
  let milk = @milkir.Function::new("bitcast_f64_i64", signature)
  let input = milk.new_value(F64)
  let output = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Bitcast, [input], [output]))
  entry.set_terminator(Return([output]))
  let plan = plan_milkir_integration_for_target(milk, AArch64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_fmov_to_gpr = false
  for i in 0..<(plan.object.code.length() - 3) {
    if plan.object.code[i + 2] == 0x66 && plan.object.code[i + 3] == 0x9e {
      has_fmov_to_gpr = true
    }
  }
  inspect(has_fmov_to_gpr, content="true")
  inspect(plan.object.code[plan.object.code.length() - 4], content="192")
  inspect(plan.object.code[plan.object.code.length() - 1], content="214")
}

///|
test "plan MilkIR sign-extension through reusable x64 JIT pipeline" {
  let signature = @milkir.Signature::new([I64], [I64])
  let milk = @milkir.Function::new("sext8_x64", signature)
  let input = milk.new_value(I64)
  let output = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Sextend8, [input], [output]))
  entry.set_terminator(Return([output]))
  let plan = plan_milkir_integration_for_target(milk, X64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_movsx = false
  for i in 0..<(plan.object.code.length() - 1) {
    if plan.object.code[i] == 0x0f && plan.object.code[i + 1] == 0xbe {
      has_movsx = true
    }
  }
  inspect(has_movsx, content="true")
  inspect(plan.object.code[plan.object.code.length() - 1], content="195")
}

///|
test "plan MilkIR sign-extension through reusable AArch64 JIT pipeline" {
  let signature = @milkir.Signature::new([I64], [I64])
  let milk = @milkir.Function::new("sext32_aarch64", signature)
  let input = milk.new_value(I64)
  let output = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Sextend32, [input], [output]))
  entry.set_terminator(Return([output]))
  let plan = plan_milkir_integration_for_target(milk, AArch64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_sxtw = false
  for i in 0..<(plan.object.code.length() - 3) {
    if (plan.object.code[i + 1] & 0x7c) == 0x7c &&
      plan.object.code[i + 2] == 0x40 &&
      plan.object.code[i + 3] == 0x93 {
      has_sxtw = true
    }
  }
  inspect(has_sxtw, content="true")
  inspect(plan.object.code[plan.object.code.length() - 4], content="192")
  inspect(plan.object.code[plan.object.code.length() - 1], content="214")
}

///|
test "plan MilkIR unsigned extend through reusable x64 JIT pipeline" {
  let signature = @milkir.Signature::new([I32], [I64])
  let milk = @milkir.Function::new("uextend_x64", signature)
  let input = milk.new_value(I32)
  let output = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Uextend, [input], [output]))
  entry.set_terminator(Return([output]))
  let plan = plan_milkir_integration_for_target(milk, X64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_mov32 = false
  for i in 0..<(plan.object.code.length() - 1) {
    if plan.object.code[i] == 0x89 {
      has_mov32 = true
    }
  }
  inspect(has_mov32, content="true")
  inspect(plan.object.code[plan.object.code.length() - 1], content="195")
}

///|
test "plan MilkIR integer reduce through reusable AArch64 JIT pipeline" {
  let signature = @milkir.Signature::new([I64], [I32])
  let milk = @milkir.Function::new("ireduce_aarch64", signature)
  let input = milk.new_value(I64)
  let output = milk.new_value(I32)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Ireduce, [input], [output]))
  entry.set_terminator(Return([output]))
  let plan = plan_milkir_integration_for_target(milk, AArch64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_mov_w = false
  for i in 0..<(plan.object.code.length() - 3) {
    if plan.object.code[i + 3] == 0x2a {
      has_mov_w = true
    }
  }
  inspect(has_mov_w, content="true")
  inspect(plan.object.code[plan.object.code.length() - 4], content="192")
  inspect(plan.object.code[plan.object.code.length() - 1], content="214")
}

///|
test "plan MilkIR integer select through reusable x64 JIT pipeline" {
  let signature = @milkir.Signature::new([I32, I64, I64], [I64])
  let milk = @milkir.Function::new("select_x64", signature)
  let cond = milk.new_value(I32)
  let true_value = milk.new_value(I64)
  let false_value = milk.new_value(I64)
  let output = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(
    milk.new_inst(Select, [cond, true_value, false_value], [output]),
  )
  entry.set_terminator(Return([output]))
  let plan = plan_milkir_integration_for_target(milk, X64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_cmovne = false
  for i in 0..<(plan.object.code.length() - 2) {
    if plan.object.code[i] == 0x0f && plan.object.code[i + 1] == 0x45 {
      has_cmovne = true
    }
  }
  inspect(has_cmovne, content="true")
  inspect(plan.object.code[plan.object.code.length() - 1], content="195")
}

///|
test "plan MilkIR floating point select through reusable x64 JIT pipeline" {
  let signature = @milkir.Signature::new([I32, F64, F64], [F64])
  let milk = @milkir.Function::new("select_f64_x64", signature)
  let cond = milk.new_value(I32)
  let true_value = milk.new_value(F64)
  let false_value = milk.new_value(F64)
  let output = milk.new_value(F64)
  let entry = milk.new_block([])
  entry.append_inst(
    milk.new_inst(Select, [cond, true_value, false_value], [output]),
  )
  entry.set_terminator(Return([output]))
  let plan = plan_milkir_integration_for_target(milk, X64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_cmovne = false
  for i in 0..<(plan.object.code.length() - 2) {
    if plan.object.code[i] == 0x0f && plan.object.code[i + 1] == 0x45 {
      has_cmovne = true
    }
  }
  inspect(has_cmovne, content="true")
  inspect(plan.object.code[plan.object.code.length() - 1], content="195")
}

///|
test "plan MilkIR integer select through reusable AArch64 JIT pipeline" {
  let signature = @milkir.Signature::new([I32, I64, I64], [I64])
  let milk = @milkir.Function::new("select_aarch64", signature)
  let cond = milk.new_value(I32)
  let true_value = milk.new_value(I64)
  let false_value = milk.new_value(I64)
  let output = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(
    milk.new_inst(Select, [cond, true_value, false_value], [output]),
  )
  entry.set_terminator(Return([output]))
  let plan = plan_milkir_integration_for_target(milk, AArch64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_csel = false
  for i in 0..<(plan.object.code.length() - 3) {
    if plan.object.code[i + 3] == 0x9a &&
      (plan.object.code[i + 2] & 0x80) == 0x80 {
      has_csel = true
    }
  }
  inspect(has_csel, content="true")
  inspect(plan.object.code[plan.object.code.length() - 4], content="192")
  inspect(plan.object.code[plan.object.code.length() - 1], content="214")
}

///|
test "plan MilkIR floating point select through reusable AArch64 JIT pipeline" {
  let signature = @milkir.Signature::new([I32, F64, F64], [F64])
  let milk = @milkir.Function::new("select_f64_aarch64", signature)
  let cond = milk.new_value(I32)
  let true_value = milk.new_value(F64)
  let false_value = milk.new_value(F64)
  let output = milk.new_value(F64)
  let entry = milk.new_block([])
  entry.append_inst(
    milk.new_inst(Select, [cond, true_value, false_value], [output]),
  )
  entry.set_terminator(Return([output]))
  let plan = plan_milkir_integration_for_target(milk, AArch64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_csel = false
  for i in 0..<(plan.object.code.length() - 3) {
    if plan.object.code[i + 3] == 0x9a &&
      (plan.object.code[i + 2] & 0x80) == 0x80 {
      has_csel = true
    }
  }
  inspect(has_csel, content="true")
  inspect(plan.object.code[plan.object.code.length() - 4], content="192")
  inspect(plan.object.code[plan.object.code.length() - 1], content="214")
}

///|
test "plan MilkIR signed integer division through reusable JIT pipeline" {
  let signature = @milkir.Signature::new([I64, I64], [I64])
  let milk = @milkir.Function::new("sdiv64", signature)
  let lhs = milk.new_value(I64)
  let rhs = milk.new_value(I64)
  let quotient = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Sdiv, [lhs, rhs], [quotient]))
  entry.set_terminator(Return([quotient]))
  let plan = plan_milkir_integration_for_target(milk, X64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_cqo = false
  let mut has_div_opcode = false
  for i in 0..<(plan.object.code.length() - 1) {
    if plan.object.code[i] == 0x48 && plan.object.code[i + 1] == 0x99 {
      has_cqo = true
    }
  }
  for byte in plan.object.code {
    if byte == 0xf7 {
      has_div_opcode = true
    }
  }
  inspect(has_cqo, content="true")
  inspect(has_div_opcode, content="true")
  inspect(plan.object.code[plan.object.code.length() - 1], content="195")
}

///|
test "plan MilkIR signed integer remainder through reusable JIT pipeline" {
  let signature = @milkir.Signature::new([I64, I64], [I64])
  let milk = @milkir.Function::new("srem64", signature)
  let lhs = milk.new_value(I64)
  let rhs = milk.new_value(I64)
  let rem = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Srem, [lhs, rhs], [rem]))
  entry.set_terminator(Return([rem]))
  let plan = plan_milkir_integration_for_target(milk, X64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_cqo = false
  let mut has_div_opcode = false
  for i in 0..<(plan.object.code.length() - 1) {
    if plan.object.code[i] == 0x48 && plan.object.code[i + 1] == 0x99 {
      has_cqo = true
    }
  }
  for byte in plan.object.code {
    if byte == 0xf7 {
      has_div_opcode = true
    }
  }
  inspect(has_cqo, content="true")
  inspect(has_div_opcode, content="true")
  inspect(plan.object.code[plan.object.code.length() - 1], content="195")
}

///|
test "plan MilkIR signed multiply-high through reusable JIT pipeline" {
  let signature = @milkir.Signature::new([I64, I64], [I64])
  let milk = @milkir.Function::new("smulh64", signature)
  let lhs = milk.new_value(I64)
  let rhs = milk.new_value(I64)
  let high = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Smulh, [lhs, rhs], [high]))
  entry.set_terminator(Return([high]))
  let plan = plan_milkir_integration_for_target(milk, X64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_mul_opcode = false
  for i in 0..<(plan.object.code.length() - 1) {
    if plan.object.code[i] == 0xf7 && (plan.object.code[i + 1] & 0x38) == 0x28 {
      has_mul_opcode = true
    }
  }
  inspect(has_mul_opcode, content="true")
  inspect(plan.object.code[plan.object.code.length() - 1], content="195")
}

///|
test "plan MilkIR integer not through reusable JIT pipeline" {
  let signature = @milkir.Signature::new([I64], [I64])
  let milk = @milkir.Function::new("bnot64", signature)
  let input = milk.new_value(I64)
  let inverted = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Bnot, [input], [inverted]))
  entry.set_terminator(Return([inverted]))
  let plan = plan_milkir_integration_for_target(milk, X64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_not_opcode = false
  for byte in plan.object.code {
    if byte == 0xf7 {
      has_not_opcode = true
    }
  }
  inspect(has_not_opcode, content="true")
  inspect(plan.object.code[plan.object.code.length() - 1], content="195")
}

///|
test "plan MilkIR integer compare through reusable JIT pipeline" {
  let signature = @milkir.Signature::new([I64, I64], [I32])
  let milk = @milkir.Function::new("icmp_slt64", signature)
  let lhs = milk.new_value(I64)
  let rhs = milk.new_value(I64)
  let is_less = milk.new_value(I32)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Icmp(Slt), [lhs, rhs], [is_less]))
  entry.set_terminator(Return([is_less]))
  let plan = plan_milkir_integration_for_target(milk, X64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_setcc = false
  let mut has_movzx = false
  for i in 0..<(plan.object.code.length() - 1) {
    if plan.object.code[i] == 0x0f && plan.object.code[i + 1] == 0x9c {
      has_setcc = true
    }
    if plan.object.code[i] == 0x0f && plan.object.code[i + 1] == 0xb6 {
      has_movzx = true
    }
  }
  inspect(has_setcc, content="true")
  inspect(has_movzx, content="true")
  inspect(plan.object.code[plan.object.code.length() - 1], content="195")
}

///|
test "plan MilkIR integer shift through reusable JIT pipeline" {
  let signature = @milkir.Signature::new([I64, I64], [I64])
  let milk = @milkir.Function::new("shl64", signature)
  let value = milk.new_value(I64)
  let count = milk.new_value(I64)
  let shifted = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Ishl, [value, count], [shifted]))
  entry.set_terminator(Return([shifted]))
  let plan = plan_milkir_integration_for_target(milk, X64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_shift_cl = false
  for byte in plan.object.code {
    if byte == 0xd3 {
      has_shift_cl = true
    }
  }
  inspect(has_shift_cl, content="true")
  inspect(plan.object.code[plan.object.code.length() - 1], content="195")
}

///|
test "plan MilkIR integer rotate through reusable JIT pipeline" {
  let signature = @milkir.Signature::new([I64, I64], [I64])
  let milk = @milkir.Function::new("rotr64", signature)
  let value = milk.new_value(I64)
  let count = milk.new_value(I64)
  let rotated = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Rotr, [value, count], [rotated]))
  entry.set_terminator(Return([rotated]))
  let plan = plan_milkir_integration_for_target(milk, X64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_rotate_cl = false
  for i in 0..<(plan.object.code.length() - 1) {
    if plan.object.code[i] == 0xd3 && (plan.object.code[i + 1] & 0x38) == 0x08 {
      has_rotate_cl = true
    }
  }
  inspect(has_rotate_cl, content="true")
  inspect(plan.object.code[plan.object.code.length() - 1], content="195")
}

///|
test "plan MilkIR integer ctz through reusable AArch64 JIT pipeline" {
  let signature = @milkir.Signature::new([I64], [I64])
  let milk = @milkir.Function::new("ctz64", signature)
  let value = milk.new_value(I64)
  let trailing = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Ctz, [value], [trailing]))
  entry.set_terminator(Return([trailing]))
  let plan = plan_milkir_integration_for_target(milk, AArch64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_rbit = false
  let mut has_clz = false
  for i in 0..<(plan.object.code.length() - 3) {
    if plan.object.code[i + 2] == 0xc0 && plan.object.code[i + 3] == 0xda {
      if (plan.object.code[i + 1] & 0x10) == 0 {
        has_rbit = true
      } else {
        has_clz = true
      }
    }
  }
  inspect(has_rbit, content="true")
  inspect(has_clz, content="true")
  inspect(plan.object.code[plan.object.code.length() - 4], content="192")
  inspect(plan.object.code[plan.object.code.length() - 1], content="214")
}

///|
test "plan MilkIR integer clz through reusable x64 JIT pipeline" {
  let signature = @milkir.Signature::new([I64], [I64])
  let milk = @milkir.Function::new("clz64_x64", signature)
  let value = milk.new_value(I64)
  let leading = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Clz, [value], [leading]))
  entry.set_terminator(Return([leading]))
  let plan = plan_milkir_integration_for_target(milk, X64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_imul = false
  for i in 0..<(plan.object.code.length() - 2) {
    if plan.object.code[i] == 0x0f && plan.object.code[i + 1] == 0xaf {
      has_imul = true
    }
  }
  inspect(has_imul, content="true")
  inspect(plan.object.code[plan.object.code.length() - 1], content="195")
}

///|
test "plan MilkIR integer ctz through reusable x64 JIT pipeline" {
  let signature = @milkir.Signature::new([I64], [I64])
  let milk = @milkir.Function::new("ctz64_x64", signature)
  let value = milk.new_value(I64)
  let trailing = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Ctz, [value], [trailing]))
  entry.set_terminator(Return([trailing]))
  let plan = plan_milkir_integration_for_target(milk, X64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_imul = false
  for i in 0..<(plan.object.code.length() - 2) {
    if plan.object.code[i] == 0x0f && plan.object.code[i + 1] == 0xaf {
      has_imul = true
    }
  }
  inspect(has_imul, content="true")
  inspect(plan.object.code[plan.object.code.length() - 1], content="195")
}

///|
test "plan MilkIR unsigned multiply-high through reusable AArch64 JIT pipeline" {
  let signature = @milkir.Signature::new([I64, I64], [I64])
  let milk = @milkir.Function::new("umulh64", signature)
  let lhs = milk.new_value(I64)
  let rhs = milk.new_value(I64)
  let high = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Umulh, [lhs, rhs], [high]))
  entry.set_terminator(Return([high]))
  let plan = plan_milkir_integration_for_target(milk, AArch64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_umulh = false
  for i in 0..<(plan.object.code.length() - 3) {
    if (plan.object.code[i + 1] & 0x7c) == 0x7c &&
      (plan.object.code[i + 2] & 0xc0) == 0xc0 &&
      plan.object.code[i + 3] == 0x9b {
      has_umulh = true
    }
  }
  inspect(has_umulh, content="true")
  inspect(plan.object.code[plan.object.code.length() - 4], content="192")
  inspect(plan.object.code[plan.object.code.length() - 1], content="214")
}

///|
test "plan MilkIR rotate-right through reusable AArch64 JIT pipeline" {
  let signature = @milkir.Signature::new([I64, I64], [I64])
  let milk = @milkir.Function::new("rotr64_aarch64", signature)
  let value = milk.new_value(I64)
  let count = milk.new_value(I64)
  let rotated = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Rotr, [value, count], [rotated]))
  entry.set_terminator(Return([rotated]))
  let plan = plan_milkir_integration_for_target(milk, AArch64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_rorv = false
  for i in 0..<(plan.object.code.length() - 3) {
    if (plan.object.code[i + 1] & 0x2c) == 0x2c &&
      (plan.object.code[i + 2] & 0xc0) == 0xc0 &&
      plan.object.code[i + 3] == 0x9a {
      has_rorv = true
    }
  }
  inspect(has_rorv, content="true")
  inspect(plan.object.code[plan.object.code.length() - 4], content="192")
  inspect(plan.object.code[plan.object.code.length() - 1], content="214")
}

///|
test "plan MilkIR rotate-left through reusable AArch64 JIT pipeline" {
  let signature = @milkir.Signature::new([I64, I64], [I64])
  let milk = @milkir.Function::new("rotl64_aarch64", signature)
  let value = milk.new_value(I64)
  let count = milk.new_value(I64)
  let rotated = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Rotl, [value, count], [rotated]))
  entry.set_terminator(Return([rotated]))
  let plan = plan_milkir_integration_for_target(milk, AArch64) catch {
    err => fail(to_repr(err).to_string())
  }
  let mut has_rorv = false
  for i in 0..<(plan.object.code.length() - 3) {
    if (plan.object.code[i + 1] & 0x2c) == 0x2c &&
      (plan.object.code[i + 2] & 0xc0) == 0xc0 &&
      plan.object.code[i + 3] == 0x9a {
      has_rorv = true
    }
  }
  inspect(has_rorv, content="true")
  inspect(plan.object.code[plan.object.code.length() - 4], content="192")
  inspect(plan.object.code[plan.object.code.length() - 1], content="214")
}

///|
test "wrap reusable JIT plan as cwasm artifact" {
  let signature = @milkir.Signature::new([I64, I64], [I64])
  let milk = @milkir.Function::new("add64_artifact", signature)
  let lhs = milk.new_value(I64)
  let rhs = milk.new_value(I64)
  let sum = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Iadd, [lhs, rhs], [sum]))
  entry.set_terminator(Return([sum]))
  let plan = try! plan_milkir_integration_for_target(milk, X64)
  let artifact = try! CwasmArtifact::from_jit_plan(
    plan,
    RuntimeSymbolResolver::new(),
    3,
  )
  inspect(artifact.functions.length(), content="1")
  inspect(artifact.functions[0].function_index, content="3")
  inspect(artifact.code.length() > 0, content="true")
  inspect(artifact.debug_entries.length(), content="6")
  let restored = try! @cwasm.deserialize(artifact.serialize())
  inspect(restored.function_count(), content="1")
  inspect(restored.functions[0].func_idx, content="3")
  inspect(restored.functions[0].name, content="add64_artifact")
  inspect(restored.functions[0].frame_size, content="0")
  inspect(
    restored.functions[0].code.length(),
    content=artifact.code.length().to_string(),
  )
}

///|
test "wrap reusable JIT plan preserves cwasm signature metadata" {
  let signature = @milkir.Signature::new([I64, I64], [I64])
  let milk = @milkir.Function::new("add64_artifact_sig", signature)
  let lhs = milk.new_value(I64)
  let rhs = milk.new_value(I64)
  let sum = milk.new_value(I64)
  let entry = milk.new_block([])
  entry.append_inst(milk.new_inst(Iadd, [lhs, rhs], [sum]))
  entry.set_terminator(Return([sum]))
  let plan = try! plan_milkir_integration_for_target(milk, X64)
  let artifact = try! CwasmArtifact::from_jit_plan_with_signature(
    plan,
    RuntimeSymbolResolver::new(),
    4,
    2,
    1,
  )
  inspect(artifact.functions[0].num_params, content="2")
  inspect(artifact.functions[0].num_results, content="1")
  let restored = try! @cwasm.deserialize(artifact.serialize())
  inspect(restored.functions[0].func_idx, content="4")
  inspect(restored.functions[0].num_params, content="2")
  inspect(restored.functions[0].num_results, content="1")
}

///|
test "native runtime cstring encoding lives in wasmoon_jit" {
  let encoded = make_cstring("wasi")
  inspect(encoded.length(), content="5")
  inspect(encoded[0].to_int(), content="119")
  inspect(encoded[1].to_int(), content="97")
  inspect(encoded[2].to_int(), content="115")
  inspect(encoded[3].to_int(), content="105")
  inspect(encoded[4].to_int(), content="0")
}

///|
test "reference encoding helpers roundtrip JIT values" {
  inspect(is_null_ref(encode_null_ref()), content="true")
  debug_inspect(decode_funcref_idx(encode_funcref_idx(7)), content="Some(7)")
  let tagged = tag_funcref_ptr(0x1000L)
  inspect(is_funcref_ptr(tagged), content="true")
  inspect(untag_funcref_ptr(tagged), content="4096")
  debug_inspect(decode_externref(encode_externref(11)), content="Some(11)")
  debug_inspect(decode_gc_heap_ref(encode_gc_heap_ref(3)), content="Some(3)")
  debug_inspect(decode_gc_heap_ref(encode_null_ref()), content="None")
}

///|
test "VMContext reusable ABI layout matches JIT fixed prefix" {
  let layout = vmcontext_layout()
  inspect(layout.memory0_offset, content="0")
  inspect(layout.memory0_base_offset, content="8")
  inspect(layout.memory0_size_offset, content="16")
  inspect(layout.func_table_offset, content="24")
  inspect(layout.table0_base_offset, content="32")
  inspect(layout.table0_elements_offset, content="40")
  inspect(layout.globals_offset, content="48")
  inspect(layout.tables_offset, content="56")
  inspect(layout.table_count_offset, content="64")
  inspect(layout.func_count_offset, content="68")
  inspect(layout.table_sizes_offset, content="72")
  inspect(layout.table_max_sizes_offset, content="80")
  inspect(layout.memories_offset, content="88")
  inspect(layout.memory_count_offset, content="96")
  inspect(layout.debug_current_func_idx_offset, content="100")
  inspect(layout.gc_heap_ptr_offset, content="104")
  inspect(layout.gc_heap_limit_offset, content="112")
  inspect(layout.gc_heap_offset, content="120")
  inspect(layout.pointer_stride, content="8")
  inspect(layout.global_value_stride, content="16")
  inspect(layout.table_entry_value_offset, content="0")
  inspect(layout.table_entry_stride, content="16")
  inspect(layout.func_table_entry_stride, content="8")
  let memory = memory_descriptor_layout()
  inspect(memory.base_offset, content="0")
  inspect(memory.current_length_offset, content="8")
}
