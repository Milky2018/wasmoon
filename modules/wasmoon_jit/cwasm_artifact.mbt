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
  func_addr_fixups : Array[@machv_emit.FuncAddrFixup]
  call_fixups : Array[@machv_emit.CallFixup]
  gc_safepoints : Array[GcSafepoint]
  gc_stackmap_blob : Bytes
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
  let call_veneers = collect_call_veneers(function_index, linked.call_fixups)
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
    func_addr_fixups: linked.func_addr_fixups,
    call_fixups: linked.call_fixups,
    gc_safepoints: linked.gc_safepoints,
    gc_stackmap_blob: linked.gc_stackmap_blob,
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
fn collect_call_veneers(
  function_index : Int,
  call_fixups : Array[@machv_emit.CallFixup],
) -> Array[CwasmCallVeneer] {
  let out : Array[CwasmCallVeneer] = []
  let seen : Map[Int, Unit] = Map([])
  for fixup in call_fixups {
    let func_idx = cwasm_func_idx_for_reloc_target(fixup.target)
    if fixup.veneer_offset >= 0 && seen.get(func_idx) is None {
      seen.set(func_idx, ())
      out.push({ function_index, func_idx, offset: fixup.veneer_offset })
    }
  }
  out
}

///|
fn cwasm_func_idx_for_reloc_target(target : @instr.RelocTarget) -> Int {
  match machv_reloc_target_to_cwasm_func_idx(target) {
    Some(func_idx) => func_idx
    None => abort("cannot encode external reloc target in cwasm: \{target}")
  }
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
  for safepoint in self.gc_safepoints {
    if safepoint.code_offset >= start && safepoint.code_offset < end {
      out.push(
        GcSafepoint(
          safepoint.code_offset - start,
          safepoint.live_refs,
          safepoint.metadata,
        ),
      )
    }
  }
  out
}

///|
fn CwasmArtifact::function_func_addr_fixups(
  self : CwasmArtifact,
  record : CwasmFunctionRecord,
) -> Array[@cwasm.FuncAddrFixup] {
  let out : Array[@cwasm.FuncAddrFixup] = []
  let start = record.code_offset
  let end = record.code_offset + record.code_size
  for fixup in self.func_addr_fixups {
    if fixup.offset >= start && fixup.offset < end {
      let func_idx = cwasm_func_idx_for_reloc_target(fixup.target)
      out.push({ offset: fixup.offset - start, func_idx, reg: fixup.reg })
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
  for fixup in self.call_fixups {
    if fixup.offset >= start && fixup.offset < end {
      let func_idx = cwasm_func_idx_for_reloc_target(fixup.target)
      let veneer_offset = match
        self.find_call_veneer(record.function_index, func_idx) {
        Some(offset) => offset - start
        None => fixup.veneer_offset
      }
      out.push({ offset: fixup.offset - start, func_idx, veneer_offset })
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
  default_root_counts : Array[Int],
) -> Bytes {
  if safepoints.length() == 0 {
    b""
  } else {
    let bytes : Array[Byte] = []
    append_u32_le(bytes, 2)
    append_u32_le(bytes, safepoints.length())
    for i, safepoint in safepoints {
      let default_root_count = if i < default_root_counts.length() {
        default_root_counts[i]
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
          default_root_count
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
    safepoints.push(GcSafepoint(offset, live_refs, metadata))
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
  CompiledEntry(
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
  let module_ = @cwasm.PrecompiledModule::PrecompiledModule(self.target)
  for record in self.functions {
    let gc_safepoints = self.function_gc_safepoints(record)
    let gc_root_counts = Array::make(gc_safepoints.length(), 0)
    module_.add_function(
      build_cwasm_entry_from_code(
        record.function_index,
        self.entry_symbol,
        self.function_code(record),
        record.frame_size,
        0,
        record.num_params,
        record.num_results,
        func_addr_fixups=self.function_func_addr_fixups(record),
        gc_safepoints~,
        gc_safepoint_root_counts=gc_root_counts,
        call_fixups=self.function_call_fixups(record),
        gc_stackmap_blob=self.gc_stackmap_blob,
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
    "cwasm.call_fixups=" + self.call_fixups.length().to_string(),
    "cwasm.serialized_size=" + self.serialize().length().to_string(),
  ]
}
