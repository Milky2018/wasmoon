///|
fn aarch64_cwasm_target_index(
  target : @code_object.RelocationTarget,
) -> Int raise JitPipelineError {
  match target {
    Code(symbol) =>
      match resolve_wasm_func_symbol(symbol.name) {
        Some(index) => index
        None =>
          raise PipelineFailure(
            message="unresolved AArch64 function symbol '\{symbol.name}'",
          )
      }
    External(symbol) => {
      let resolver = RuntimeSymbolResolver::with_wasmoon_runtime_symbols()
      match resolver.resolve_symbol(symbol.name) {
        Some(runtime) =>
          match runtime.fixup_idx {
            Some(index) => index
            None =>
              raise PipelineFailure(
                message="AArch64 runtime symbol '\{symbol.name}' has no persistent fixup identity",
              )
          }
        None =>
          raise PipelineFailure(
            message="unresolved AArch64 runtime symbol '\{symbol.name}'",
          )
      }
    }
    Data(symbol) =>
      raise PipelineFailure(
        message="AArch64 data relocation '\{symbol.name}' is not representable in cwasm v8",
      )
  }
}

///|
fn aarch64_cwasm_call_fixups(
  object : @code_object.UnlinkedCodeObject,
  veneer_offsets : Array[Int],
) -> Array[@cwasm.CallFixup] raise JitPipelineError {
  let fixups : Array[@cwasm.CallFixup] = []
  for index, relocation in object.relocations() {
    if relocation.addend != 0L {
      raise PipelineFailure(
        message="AArch64 cwasm v8 call relocation \{index} has a non-zero addend",
      )
    }
    match relocation.kind {
      AArch64Call26 | AArch64Jump26 =>
        fixups.push({
          offset: relocation.offset,
          func_idx: aarch64_cwasm_target_index(relocation.target),
          veneer_offset: veneer_offsets[index],
        })
      AArch64Page21 | AArch64PageOffset12 | Absolute64 | X64PcRelative32 =>
        raise PipelineFailure(
          message="AArch64 relocation \{index} is not representable in cwasm v8",
        )
    }
  }
  fixups
}

///|
fn aarch64_cwasm_gc_metadata(
  object : @code_object.UnlinkedCodeObject,
) -> (Array[@cwasm.GcSafepoint], Array[Int]) {
  let safepoints : Array[@cwasm.GcSafepoint] = []
  let root_counts : Array[Int] = []
  for site in object.safepoints() {
    let root_count = match site.stack_map {
      Some(stack_map) => stack_map.argument_root_count
      None => 0
    }
    let root_indices = Array::makei(root_count, index => index)
    safepoints.push(
      GcSafepoint(site.offset, root_indices, root_count.to_int64()),
    )
    root_counts.push(root_count)
  }
  (safepoints, root_counts)
}

///|
fn aarch64_cwasm_stackmap_blob(
  safepoints : Array[@cwasm.GcSafepoint],
  root_counts : Array[Int],
) -> Bytes {
  build_gc_stackmap_blob_v2(safepoints, root_counts)
}

///|
pub fn compile_wasm_body_aarch64_cwasm_entry(
  function : @milkir.Function,
  validation_context : @wasm_milkir.WasmValidationContext,
  func_idx : Int,
  name : String,
  num_params : Int,
  num_results : Int,
  use_subtype_indirect_check? : Bool = true,
  canonical_type_indices? : Array[Int] = [],
) -> @cwasm.CompiledEntry raise JitPipelineError {
  let compiled = compile_wasm_body_aarch64_target(
    function, validation_context, use_subtype_indirect_check, canonical_type_indices,
  )
  let link_plan = @aarch64_target.prepare_aarch64_link(compiled.object) catch {
    error =>
      raise PipelineFailure(
        message="\{function.name}: AArch64 link preparation failed: \{error.to_string()}",
      )
  }
  let call_fixups = aarch64_cwasm_call_fixups(
    compiled.object,
    link_plan.veneer_offsets(),
  )
  let (gc_safepoints, gc_root_counts) = aarch64_cwasm_gc_metadata(
    compiled.object,
  )
  build_cwasm_entry_from_code(
    func_idx,
    name,
    link_plan.code().map(byte => byte.to_int()),
    compiled.frame_size,
    0,
    num_params,
    num_results,
    call_fixups~,
    gc_safepoints~,
    gc_safepoint_root_counts=gc_root_counts,
    gc_stackmap_blob=aarch64_cwasm_stackmap_blob(gc_safepoints, gc_root_counts),
  )
}
