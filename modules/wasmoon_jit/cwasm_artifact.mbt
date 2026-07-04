///|
pub(all) struct CwasmFunctionRecord {
  function_index : Int
  code_offset : Int
  code_size : Int
  frame_size : Int
  num_params : Int
  num_results : Int
} derive(Eq, Debug)

///|
pub(all) struct CwasmCallVeneer {
  function_index : Int
  func_idx : Int
  offset : Int
} derive(Eq, Debug)

///|
pub(all) struct CwasmArtifact {
  version : Int
  target : @cwasm.TargetArch
  entry_symbol : String
  code : Array[Int]
  functions : Array[CwasmFunctionRecord]
  call_veneers : Array[CwasmCallVeneer]
  runtime_relocations : Array[ResolvedRuntimeRelocation]
  block_fixups : Array[@machv_emit.Fixup]
  stack_maps : Array[@machv_emit.StackMap]
  debug_entries : Array[@machv_emit.DebugEntry]
} derive(Debug)

///|
fn emit_target_to_cwasm_target(
  target : @machv_emit.EmitTarget,
) -> @cwasm.TargetArch {
  match target {
    X64 => X86_64
    AArch64 => AArch64
  }
}

///|
fn cwasm_target_name(target : @cwasm.TargetArch) -> String {
  match target {
    Unknown => "unknown"
    X86_64 => "x86_64"
    AArch64 => "aarch64"
  }
}

///|
pub fn CwasmArtifact::from_linked_code_for_target(
  linked : LinkedCode,
  function_index : Int,
  target : @cwasm.TargetArch,
  entry_symbol : String,
) -> CwasmArtifact {
  CwasmArtifact::from_linked_code_for_target_with_signature(
    linked, function_index, target, entry_symbol, 0, 0,
  )
}

///|
pub fn CwasmArtifact::from_linked_code_for_target_with_signature(
  linked : LinkedCode,
  function_index : Int,
  target : @cwasm.TargetArch,
  entry_symbol : String,
  num_params : Int,
  num_results : Int,
) -> CwasmArtifact {
  let code = linked.code.copy()
  let call_veneers = if target is AArch64 {
    materialize_aarch64_call_veneers(
      code,
      function_index,
      linked.runtime_relocations,
    )
  } else {
    []
  }
  {
    version: 1,
    target,
    entry_symbol,
    code,
    functions: [
      {
        function_index,
        code_offset: 0,
        code_size: code.length(),
        frame_size: linked.frame_size,
        num_params,
        num_results,
      },
    ],
    call_veneers,
    runtime_relocations: linked.runtime_relocations,
    block_fixups: linked.block_fixups,
    stack_maps: linked.stack_maps,
    debug_entries: linked.debug_entries,
  }
}

///|
pub fn CwasmArtifact::from_jit_plan(
  plan : JitIntegrationPlan,
  resolver : RuntimeSymbolResolver,
  function_index : Int,
) -> CwasmArtifact raise LinkError {
  CwasmArtifact::from_jit_plan_with_signature(
    plan, resolver, function_index, 0, 0,
  )
}

///|
pub fn CwasmArtifact::from_jit_plan_with_signature(
  plan : JitIntegrationPlan,
  resolver : RuntimeSymbolResolver,
  function_index : Int,
  num_params : Int,
  num_results : Int,
) -> CwasmArtifact raise LinkError {
  CwasmArtifact::from_linked_code_for_target_with_signature(
    link_code_object(plan.object, resolver),
    function_index,
    emit_target_to_cwasm_target(plan.target),
    plan.entry_symbol,
    num_params,
    num_results,
  )
}

///|
fn CwasmArtifact::function_code(
  self : CwasmArtifact,
  record : CwasmFunctionRecord,
) -> Array[Int] {
  let out : Array[Int] = []
  let end = record.code_offset + record.code_size
  for i in record.code_offset..<end {
    out.push(self.code[i])
  }
  out
}

///|
fn append_aarch64_call_veneer(code : Array[Int]) -> Int {
  let offset = code.length()
  // Veneer layout:
  //   ldr x16, #8
  //   br x16
  //   .quad target_ptr
  code.push(0x50)
  code.push(0x00)
  code.push(0x00)
  code.push(0x58)
  code.push(0x00)
  code.push(0x02)
  code.push(0x1f)
  code.push(0xd6)
  for _ in 0..<8 {
    code.push(0)
  }
  offset
}

///|
fn materialize_aarch64_call_veneers(
  code : Array[Int],
  function_index : Int,
  runtime_relocations : Array[ResolvedRuntimeRelocation],
) -> Array[CwasmCallVeneer] {
  let out : Array[CwasmCallVeneer] = []
  let veneers_by_func : Map[Int, Int] = {}
  for relocation in runtime_relocations {
    if relocation.fixup_idx is Some(func_idx) {
      if veneers_by_func.get(func_idx) is None {
        let offset = append_aarch64_call_veneer(code)
        veneers_by_func.set(func_idx, offset)
        out.push({ function_index, func_idx, offset })
      }
    }
  }
  out
}

///|
fn CwasmArtifact::find_call_veneer(
  self : CwasmArtifact,
  function_index : Int,
  func_idx : Int,
) -> Int? {
  for veneer in self.call_veneers {
    if veneer.function_index == function_index && veneer.func_idx == func_idx {
      return Some(veneer.offset)
    }
  }
  None
}

///|
fn CwasmArtifact::function_gc_safepoints(
  self : CwasmArtifact,
  record : CwasmFunctionRecord,
) -> Array[@cwasm.GcSafepoint] {
  let out : Array[@cwasm.GcSafepoint] = []
  let start = record.code_offset
  let end = record.code_offset + record.code_size
  for stack_map in self.stack_maps {
    if stack_map.offset >= start && stack_map.offset < end {
      out.push(@cwasm.GcSafepoint::new(stack_map.offset - start, [], 0L))
    }
  }
  out
}

///|
fn CwasmArtifact::function_call_fixups(
  self : CwasmArtifact,
  record : CwasmFunctionRecord,
) -> Array[@cwasm.CallFixup] {
  let out : Array[@cwasm.CallFixup] = []
  let start = record.code_offset
  let end = record.code_offset + record.code_size
  for relocation in self.runtime_relocations {
    if relocation.offset >= start && relocation.offset < end {
      if relocation.fixup_idx is Some(func_idx) {
        let veneer_offset = match
          self.find_call_veneer(record.function_index, func_idx) {
          Some(offset) => offset - start
          None => -1
        }
        out.push({ offset: relocation.offset - start, func_idx, veneer_offset })
      }
    }
  }
  out
}

///|
fn append_u32_le(buf : Array[Byte], value : Int) -> Unit {
  buf.push((value & 0xFF).to_byte())
  buf.push(((value >> 8) & 0xFF).to_byte())
  buf.push(((value >> 16) & 0xFF).to_byte())
  buf.push(((value >> 24) & 0xFF).to_byte())
}

///|
pub fn build_gc_stackmap_blob(root_counts : Array[Int]) -> Bytes {
  if root_counts.length() == 0 {
    b""
  } else {
    let bytes : Array[Byte] = []
    append_u32_le(bytes, 1)
    append_u32_le(bytes, root_counts.length())
    for count in root_counts {
      append_u32_le(bytes, count)
    }
    Bytes::from_array(bytes)
  }
}

///|
pub fn gc_safepoint_metadata_to_root_count(metadata : Int64) -> Int {
  if metadata <= 0L {
    0
  } else if metadata > @types.I32_MAX.to_int64() {
    @types.I32_MAX
  } else {
    metadata.to_int()
  }
}

///|
fn encode_stackmap_root_count(root_count : Int) -> Int {
  if root_count <= 0 {
    0
  } else if root_count > @types.I32_MAX {
    @types.I32_MAX
  } else {
    root_count
  }
}

///|
fn has_stackmap_live_ref_indices(
  safepoints : Array[@cwasm.GcSafepoint],
) -> Bool {
  let mut found = false
  for safepoint in safepoints {
    if safepoint.live_refs.length() > 0 {
      found = true
    }
  }
  found
}

///|
pub fn build_gc_stackmap_blob_v2(
  safepoints : Array[@cwasm.GcSafepoint],
  fallback_root_counts : Array[Int],
) -> Bytes {
  if safepoints.length() == 0 {
    b""
  } else {
    let bytes : Array[Byte] = []
    append_u32_le(bytes, 2)
    append_u32_le(bytes, safepoints.length())
    for i, safepoint in safepoints {
      let fallback_root_count = if i < fallback_root_counts.length() {
        fallback_root_counts[i]
      } else {
        safepoint.live_refs.length()
      }
      let metadata_root_count = gc_safepoint_metadata_to_root_count(
        safepoint.metadata,
      )
      let mut root_count = encode_stackmap_root_count(
        if metadata_root_count > 0 {
          metadata_root_count
        } else {
          fallback_root_count
        },
      )
      let valid_indices : Array[Int] = []
      for live_ref in safepoint.live_refs {
        if live_ref >= 0 && live_ref <= @types.I32_MAX {
          valid_indices.push(live_ref)
        }
      }
      if valid_indices.length() > 0 {
        if root_count <= 0 || root_count > valid_indices.length() {
          root_count = valid_indices.length()
        }
        append_u32_le(bytes, root_count)
        append_u32_le(bytes, root_count)
        for idx in 0..<root_count {
          append_u32_le(bytes, valid_indices[idx])
        }
      } else {
        append_u32_le(bytes, root_count)
        append_u32_le(bytes, 0)
      }
    }
    Bytes::from_array(bytes)
  }
}

///|
pub fn derive_gc_safepoints(
  offsets : Array[Int],
  root_counts : Array[Int],
  root_indices : Array[Array[Int]],
) -> Array[@cwasm.GcSafepoint] {
  let safepoints : Array[@cwasm.GcSafepoint] = []
  for i, offset in offsets {
    let metadata = if i < root_counts.length() {
      root_counts[i].to_int64()
    } else {
      0L
    }
    let live_refs = if i < root_indices.length() { root_indices[i] } else { [] }
    safepoints.push(@cwasm.GcSafepoint::new(offset, live_refs, metadata))
  }
  safepoints
}

///|
pub fn build_gc_stackmap_blob_for_safepoints(
  safepoints : Array[@cwasm.GcSafepoint],
  root_counts : Array[Int],
  explicit_blob? : Bytes = b"",
) -> Bytes {
  if explicit_blob.length() > 0 {
    explicit_blob
  } else if has_stackmap_live_ref_indices(safepoints) {
    build_gc_stackmap_blob_v2(safepoints, root_counts)
  } else if root_counts.length() > 0 {
    build_gc_stackmap_blob(root_counts)
  } else if safepoints.length() > 0 {
    let counts : Array[Int] = []
    for safepoint in safepoints {
      counts.push(gc_safepoint_metadata_to_root_count(safepoint.metadata))
    }
    build_gc_stackmap_blob(counts)
  } else {
    b""
  }
}

///|
pub fn build_cwasm_entry_from_code(
  func_idx : Int,
  name : String,
  code : Array[Int],
  frame_size : Int,
  entry_offset : Int,
  num_params : Int,
  num_results : Int,
  func_addr_fixups? : Array[@cwasm.FuncAddrFixup] = [],
  call_fixups? : Array[@cwasm.CallFixup] = [],
  gc_safepoint_offsets? : Array[Int] = [],
  gc_safepoint_root_counts? : Array[Int] = [],
  gc_safepoint_root_indices? : Array[Array[Int]] = [],
  gc_safepoints? : Array[@cwasm.GcSafepoint] = [],
  gc_stackmap_blob? : Bytes = b"",
) -> @cwasm.CompiledEntry {
  let resolved_gc_safepoints = if gc_safepoints.length() > 0 {
    gc_safepoints
  } else {
    derive_gc_safepoints(
      gc_safepoint_offsets, gc_safepoint_root_counts, gc_safepoint_root_indices,
    )
  }
  @cwasm.CompiledEntry::new(
    func_idx,
    name,
    code,
    frame_size,
    entry_offset,
    num_params,
    num_results,
    func_addr_fixups~,
    call_fixups~,
    gc_safepoints=resolved_gc_safepoints,
    gc_stackmap_blob=build_gc_stackmap_blob_for_safepoints(
      resolved_gc_safepoints,
      gc_safepoint_root_counts,
      explicit_blob=gc_stackmap_blob,
    ),
  )
}

///|
pub fn CwasmArtifact::to_precompiled_module(
  self : CwasmArtifact,
) -> @cwasm.PrecompiledModule {
  let module_ = @cwasm.PrecompiledModule::new(self.target)
  for record in self.functions {
    let gc_safepoints = self.function_gc_safepoints(record)
    let gc_root_counts = Array::make(gc_safepoints.length(), 0)
    // TODO(ISS-022): carry real live-root indices/root counts and per-function
    // function-address fixups from the production JIT pipeline.
    module_.add_function(
      build_cwasm_entry_from_code(
        record.function_index,
        self.entry_symbol,
        self.function_code(record),
        record.frame_size,
        0,
        record.num_params,
        record.num_results,
        gc_safepoints~,
        gc_safepoint_root_counts=gc_root_counts,
        call_fixups=self.function_call_fixups(record),
      ),
    )
  }
  module_
}

///|
pub fn CwasmArtifact::serialize(self : CwasmArtifact) -> Array[Int] {
  self.to_precompiled_module().serialize()
}

///|
pub fn CwasmArtifact::manifest(self : CwasmArtifact) -> Array[String] {
  [
    "cwasm.version=" + self.version.to_string(),
    "cwasm.target=" + cwasm_target_name(self.target),
    "cwasm.code_size=" + self.code.length().to_string(),
    "cwasm.functions=" + self.functions.length().to_string(),
    "cwasm.runtime_relocations=" + self.runtime_relocations.length().to_string(),
    "cwasm.block_fixups=" + self.block_fixups.length().to_string(),
    "cwasm.serialized_size=" + self.serialize().length().to_string(),
  ]
}
