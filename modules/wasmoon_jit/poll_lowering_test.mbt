///|
test "native poll checks branch directly without boolean temporaries" {
  let b = @milkir.FunctionBuilder("direct_poll_checks")
  b.add_param(Ptr) |> ignore
  b.emit_void_ext_inst(@wasm_milkir.encode(SafepointPoll(-8, 0, 16, 24)), [])
  b.return_([])
  for target in [@wasmoon_jit.NativeTarget::AArch64, X64] {
    let diagnostics = @wasmoon_jit.compile_wasm_body_diagnostics_for_target(
      b.get_function(),
      @wasm_milkir.WasmValidationContext::empty(),
      target,
    )
    assert_true(diagnostics.code_object.contains("cancel_poll"))
    if target == AArch64 {
      assert_false(diagnostics.target_vcode.contains("CompareSet"))
      assert_true(diagnostics.target_vcode.contains("BranchCompareImmediate"))
    }
  }
}
