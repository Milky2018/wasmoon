///|
pub(all) enum NativeTarget {
  X64
  AArch64
} derive(Eq, Debug)

///|
pub(all) struct JitFuncAddrFixup {
  offset : Int
  target : @code_object.RelocationTarget
  reg : Int
} derive(Eq, Debug)

///|
pub(all) struct JitCallFixup {
  offset : Int
  target : @code_object.RelocationTarget
  veneer_offset : Int
} derive(Eq, Debug)

///|
pub struct JitCodeObject {
  priv code : Array[Int]
  priv frame_size : Int
  priv func_addr_fixups : Array[JitFuncAddrFixup]
  priv call_fixups : Array[JitCallFixup]
  priv gc_safepoints : Array[GcSafepoint]
} derive(Debug)

///|
pub fn JitCodeObject::new(
  code : Array[Int],
  frame_size : Int,
  func_addr_fixups? : Array[JitFuncAddrFixup] = [],
  call_fixups? : Array[JitCallFixup] = [],
  gc_safepoints? : Array[GcSafepoint] = [],
) -> JitCodeObject {
  {
    code: code.copy(),
    frame_size,
    func_addr_fixups: func_addr_fixups.copy(),
    call_fixups: call_fixups.copy(),
    gc_safepoints: gc_safepoints.copy(),
  }
}

///|
pub fn JitCodeObject::get_bytes(self : JitCodeObject) -> Array[Int] {
  self.code.copy()
}

///|
pub fn JitCodeObject::size(self : JitCodeObject) -> Int {
  self.code.length()
}

///|
pub fn JitCodeObject::frame_size(self : JitCodeObject) -> Int {
  self.frame_size
}

///|
pub fn JitCodeObject::get_func_addr_fixups(
  self : JitCodeObject,
) -> Array[JitFuncAddrFixup] {
  self.func_addr_fixups.copy()
}

///|
pub fn JitCodeObject::get_call_fixups(
  self : JitCodeObject,
) -> Array[JitCallFixup] {
  self.call_fixups.copy()
}

///|
pub fn JitCodeObject::get_gc_safepoints(
  self : JitCodeObject,
) -> Array[GcSafepoint] {
  self.gc_safepoints.copy()
}

///|
fn code_object_gc_safepoints(
  object : @code_object.UnlinkedCodeObject,
) -> Array[GcSafepoint] {
  object
  .safepoints()
  .map(site => {
    let root_count = match site.stack_map {
      Some(stack_map) => stack_map.argument_root_count
      None => 0
    }
    GcSafepoint(
      site.offset,
      Array::makei(root_count, index => index),
      root_count.to_int64(),
    )
  })
}

///|
fn jit_code_object_from_x64(
  object : @code_object.UnlinkedCodeObject,
  frame_size : Int,
) -> JitCodeObject raise JitPipelineError {
  let plan = @x64_target.prepare_x64_link(object) catch {
    error =>
      raise PipelineFailure(
        message="x64 link preparation failed: \{error.to_string()}",
      )
  }
  let addresses : Array[JitFuncAddrFixup] = []
  let calls : Array[JitCallFixup] = []
  for index, relocation in object.relocations() {
    if relocation.addend != 0L {
      raise PipelineFailure(
        message="x64 JIT relocation \{index} has a non-zero addend",
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
          target: relocation.target,
          veneer_offset: -1,
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
          target: relocation.target,
          reg: 0,
        })
      }
      AArch64Call26 | AArch64Jump26 | AArch64Page21 | AArch64PageOffset12 =>
        raise PipelineFailure(
          message="x64 code object contains AArch64 relocation \{index}",
        )
    }
  }
  JitCodeObject::new(
    plan.code().map(byte => byte.to_int()),
    frame_size,
    func_addr_fixups=addresses,
    call_fixups=calls,
    gc_safepoints=code_object_gc_safepoints(object),
  )
}

///|
fn jit_code_object_from_aarch64(
  object : @code_object.UnlinkedCodeObject,
  frame_size : Int,
) -> JitCodeObject raise JitPipelineError {
  let plan = @aarch64_target.prepare_aarch64_link(object) catch {
    error =>
      raise PipelineFailure(
        message="AArch64 link preparation failed: \{error.to_string()}",
      )
  }
  let calls : Array[JitCallFixup] = []
  for index, relocation in object.relocations() {
    if relocation.addend != 0L {
      raise PipelineFailure(
        message="AArch64 JIT relocation \{index} has a non-zero addend",
      )
    }
    match relocation.kind {
      AArch64Call26 | AArch64Jump26 =>
        calls.push({
          offset: relocation.offset,
          target: relocation.target,
          veneer_offset: plan.veneer_offsets()[index],
        })
      AArch64Page21 | AArch64PageOffset12 | Absolute64 | X64PcRelative32 =>
        raise PipelineFailure(
          message="unsupported AArch64 JIT relocation \{index}",
        )
    }
  }
  JitCodeObject::new(
    plan.code().map(byte => byte.to_int()),
    frame_size,
    call_fixups=calls,
    gc_safepoints=code_object_gc_safepoints(object),
  )
}
