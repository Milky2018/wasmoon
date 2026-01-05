// GC Compiler Trait for JIT Code Generation
//
// This trait defines how the JIT compiler generates GC-aware code.
// Different GC implementations may require different code generation strategies.

// ============================================================
// GcCompiler - JIT Compiler GC Support
// ============================================================
//
// Responsible for:
// - Generating allocation code (fast path + slow path)
// - Emitting write barriers in generated code
// - Generating safepoint checks for preemptive GC
// - Recording stack maps for root scanning
//
// Implementations:
// - NoBarrierCompiler: No barriers, for stop-the-world GC
// - WriteBarrierCompiler: Insert write barriers for incremental GC
// - FullBarrierCompiler: Insert read+write barriers for concurrent GC

///|
/// Information about a GC safepoint in generated code
pub struct GcSafepoint {
  /// Offset in generated machine code where this safepoint is
  code_offset : Int
  /// Which virtual registers contain live GC references at this point
  live_refs : Array[Int]
  /// Additional metadata (e.g., return address for stack unwinding)
  metadata : Int64
} derive(Show)

///|
/// GC compiler capabilities - what features does this GC need?
pub struct GcCompilerConfig {
  /// Does this GC need write barriers?
  needs_write_barriers : Bool
  /// Does this GC need read barriers?
  needs_read_barriers : Bool
  /// Does this GC need safepoint checks?
  needs_safepoints : Bool
  /// Can allocation be inlined (bump pointer)?
  can_inline_alloc : Bool
  /// Size of object header in bytes
  object_header_size : Int
} derive(Show)

///|
/// GC compiler interface for JIT code generation
pub(open) trait GcCompiler {
  // === Configuration ===

  /// Get the GC compiler configuration
  config(Self) -> GcCompilerConfig

  // === Allocation Code Generation ===

  /// Generate code to allocate a struct
  /// func: the VCode function being compiled
  /// block: the block to emit instructions into
  /// type_idx: the struct type index
  /// field_vregs: virtual registers containing field values
  /// Returns: virtual register containing the new struct reference
  gen_alloc_struct(
    Self,
    @regalloc.VCodeFunction,
    @block.VCodeBlock,
    Int,
    Array[@abi.VReg],
  ) -> @abi.VReg

  /// Generate code to allocate an array
  /// func: the VCode function being compiled
  /// block: the block to emit instructions into
  /// type_idx: the array type index
  /// len_vreg: virtual register containing array length
  /// init_vreg: virtual register containing initial element value (optional)
  /// Returns: virtual register containing the new array reference
  gen_alloc_array(
    Self,
    @regalloc.VCodeFunction,
    @block.VCodeBlock,
    Int,
    @abi.VReg,
    @abi.VReg?,
  ) -> @abi.VReg

  // === Barrier Code Generation ===

  /// Generate write barrier code BEFORE a reference store
  /// obj_vreg: object being written to
  /// field_idx: field/element index
  /// old_vreg: current value being overwritten
  /// new_vreg: new reference value being stored
  gen_write_barrier_pre(
    Self,
    @regalloc.VCodeFunction,
    @abi.VReg,
    Int,
    @abi.VReg,
    @abi.VReg,
  ) -> Unit

  /// Generate write barrier code AFTER a reference store
  gen_write_barrier_post(Self, @regalloc.VCodeFunction, @abi.VReg, @abi.VReg) -> Unit

  /// Generate read barrier code before a reference load
  /// Returns: possibly updated reference after barrier
  gen_read_barrier(Self, @regalloc.VCodeFunction, @abi.VReg) -> @abi.VReg

  // === Safepoint Generation ===

  /// Generate a safepoint poll
  /// This checks if GC wants to run and yields if needed
  /// Returns: label to continue after safepoint
  gen_safepoint_poll(Self, @regalloc.VCodeFunction) -> Unit

  /// Record safepoint information for stack map
  /// code_offset: where in the code this safepoint is
  /// live_refs: which vregs hold live GC references
  record_safepoint(Self, Int, Array[@abi.VReg]) -> Unit

  // === Stack Map Query ===

  /// Get all recorded safepoints for this function
  get_safepoints(Self) -> Array[GcSafepoint]

  /// Clear safepoint records (call between functions)
  clear_safepoints(Self) -> Unit
}

// ============================================================
// No-Op GC Compiler (for stop-the-world GC)
// ============================================================

///|
/// A no-op GC compiler that generates no barriers or safepoints.
/// Suitable for simple stop-the-world garbage collectors.
pub struct NoBarrierGcCompiler {
  safepoints : Array[GcSafepoint]
}

///|
pub fn NoBarrierGcCompiler::new() -> NoBarrierGcCompiler {
  { safepoints: [] }
}

///|
pub impl GcCompiler for NoBarrierGcCompiler with config(_self) -> GcCompilerConfig {
  {
    needs_write_barriers: false,
    needs_read_barriers: false,
    needs_safepoints: false,
    can_inline_alloc: false, // Use runtime calls for now
    object_header_size: 8, // type_idx (4) + padding (4)
  }
}

///|
pub impl GcCompiler for NoBarrierGcCompiler with gen_alloc_struct(
  _self,
  _func,
  _block,
  _type_idx,
  _field_vregs,
) -> @abi.VReg {
  // Not used - lower_struct_new uses ctx-passing libcalls directly
  // TODO: Future work - implement inline bump pointer allocation
  abort("gen_alloc_struct not implemented - use libcalls")
}

///|
pub impl GcCompiler for NoBarrierGcCompiler with gen_alloc_array(
  _self,
  _func,
  _block,
  _type_idx,
  _len_vreg,
  _init_vreg,
) -> @abi.VReg {
  // Not used - lower_array_new uses ctx-passing libcalls directly
  // TODO: Future work - implement inline bump pointer allocation
  abort("gen_alloc_array not implemented - use libcalls")
}

///|
pub impl GcCompiler for NoBarrierGcCompiler with gen_write_barrier_pre(
  _self,
  _func,
  _obj_vreg,
  _field_idx,
  _old_vreg,
  _new_vreg,
) -> Unit {
  // No-op: stop-the-world GC doesn't need write barriers
}

///|
pub impl GcCompiler for NoBarrierGcCompiler with gen_write_barrier_post(
  _self,
  _func,
  _obj_vreg,
  _new_vreg,
) -> Unit {
  // No-op
}

///|
pub impl GcCompiler for NoBarrierGcCompiler with gen_read_barrier(
  _self,
  _func,
  ref_vreg,
) -> @abi.VReg {
  // No-op: just return the reference unchanged
  ref_vreg
}

///|
pub impl GcCompiler for NoBarrierGcCompiler with gen_safepoint_poll(
  _self,
  _func,
) -> Unit {
  // No-op: stop-the-world GC doesn't need safepoint polls
}

///|
pub impl GcCompiler for NoBarrierGcCompiler with record_safepoint(
  self,
  code_offset,
  live_refs,
) -> Unit {
  let refs : Array[Int] = []
  for vreg in live_refs {
    refs.push(vreg.id)
  }
  self.safepoints.push({ code_offset, live_refs: refs, metadata: 0L })
}

///|
pub impl GcCompiler for NoBarrierGcCompiler with get_safepoints(self) -> Array[
  GcSafepoint,
] {
  self.safepoints
}

///|
pub impl GcCompiler for NoBarrierGcCompiler with clear_safepoints(self) -> Unit {
  self.safepoints.clear()
}
