///|
fn x64_cwasm_target_index(
  target : @code_object.RelocationTarget,
) -> Int raise JitPipelineError {
  match target {
    Code(symbol) =>
      match resolve_wasm_func_symbol(symbol.name) {
        Some(index) => index
        None =>
          raise PipelineFailure(
            message="unresolved x64 function symbol '\{symbol.name}'",
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
                message="x64 runtime symbol '\{symbol.name}' has no persistent fixup identity",
              )
          }
        None =>
          raise PipelineFailure(
            message="unresolved x64 runtime symbol '\{symbol.name}'",
          )
      }
    }
    Data(symbol) =>
      raise PipelineFailure(
        message="x64 data relocation '\{symbol.name}' is not representable in cwasm v8",
      )
  }
}

///|
fn x64_cwasm_fixups(
  object : @code_object.UnlinkedCodeObject,
  veneer_offsets : Array[Int],
) -> (Array[@cwasm.FuncAddrFixup], Array[@cwasm.CallFixup]) raise JitPipelineError {
  if veneer_offsets.length() != object.relocations().length() {
    raise PipelineFailure(message="x64 veneer table length mismatch")
  }
  let addresses : Array[@cwasm.FuncAddrFixup] = []
  let calls : Array[@cwasm.CallFixup] = []
  for index, relocation in object.relocations() {
    if relocation.addend != 0L {
      raise PipelineFailure(
        message="x64 cwasm v8 relocation \{index} has a non-zero addend",
      )
    }
    match relocation.kind {
      X64PcRelative32 => {
        if relocation.offset < 1 {
          raise PipelineFailure(
            message="x64 rel32 relocation has invalid offset",
          )
        }
        calls.push({
          offset: relocation.offset - 1,
          func_idx: x64_cwasm_target_index(relocation.target),
          veneer_offset: veneer_offsets[index],
        })
      }
      Absolute64 => {
        if relocation.offset < 2 {
          raise PipelineFailure(
            message="x64 absolute relocation has invalid offset",
          )
        }
        addresses.push({
          offset: relocation.offset - 2,
          func_idx: x64_cwasm_target_index(relocation.target),
          reg: 0,
        })
      }
      AArch64Call26 | AArch64Jump26 | AArch64Page21 | AArch64PageOffset12 =>
        raise PipelineFailure(
          message="x64 code object contains AArch64 relocation \{index}",
        )
    }
  }
  (addresses, calls)
}

///|
fn x64_cwasm_gc_metadata(
  object : @code_object.UnlinkedCodeObject,
) -> (Array[@cwasm.GcSafepoint], Array[Int]) {
  let safepoints : Array[@cwasm.GcSafepoint] = []
  let root_counts : Array[Int] = []
  for site in object.safepoints() {
    let root_count = match site.stack_map {
      Some(stack_map) => stack_map.argument_root_count
      None => 0
    }
    safepoints.push(
      GcSafepoint(
        site.offset,
        Array::makei(root_count, index => index),
        root_count.to_int64(),
      ),
    )
    root_counts.push(root_count)
  }
  (safepoints, root_counts)
}

///|
pub fn compile_wasm_body_x64_cwasm_entry(
  function : @milkir.Function,
  validation_context : @wasm_milkir.WasmValidationContext,
  func_idx : Int,
  name : String,
  num_params : Int,
  num_results : Int,
  use_subtype_indirect_check? : Bool = true,
  canonical_type_indices? : Array[Int] = [],
) -> @cwasm.CompiledEntry raise JitPipelineError {
  let compiled = compile_wasm_body_x64_target(
    function, validation_context, use_subtype_indirect_check, canonical_type_indices,
  )
  let link_plan = @x64_target.prepare_x64_link(compiled.object) catch {
    error =>
      raise PipelineFailure(
        message="\{function.name}: x64 link preparation failed: \{error.to_string()}",
      )
  }
  let (func_addr_fixups, call_fixups) = x64_cwasm_fixups(
    compiled.object,
    link_plan.veneer_offsets(),
  )
  let (gc_safepoints, gc_root_counts) = x64_cwasm_gc_metadata(compiled.object)
  build_cwasm_entry_from_code(
    func_idx,
    name,
    link_plan.code().map(byte => byte.to_int()),
    compiled.frame_size,
    0,
    num_params,
    num_results,
    func_addr_fixups~,
    call_fixups~,
    gc_safepoints~,
    gc_safepoint_root_counts=gc_root_counts,
    gc_stackmap_blob=build_gc_stackmap_blob_v2(gc_safepoints, gc_root_counts),
  )
}
