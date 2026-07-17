///|
pub suberror CodeObjectVerifyError {
  EmptyCode
  MisalignedCodeSize(size~ : Int)
  InvalidRelocation(index~ : Int, message~ : String)
  DuplicateRelocationOffset(offset~ : Int)
  InvalidSourceSite(index~ : Int, offset~ : Int)
  InvalidTrapSite(index~ : Int, offset~ : Int)
  InvalidSafepointSite(index~ : Int, offset~ : Int)
  InvalidRootLocation(safepoint~ : Int, root~ : Int)
  InvalidStackMap(safepoint~ : Int)
} derive(Eq, Debug)

///|
pub impl Show for CodeObjectVerifyError with fn output(self, logger) {
  logger.write_string(to_repr(self).to_string())
}

///|
fn instruction_alignment(architecture : Architecture) -> Int {
  match architecture {
    AArch64 => 4
    X64 => 1
  }
}

///|
fn relocation_width(kind : RelocationKind) -> Int {
  match kind {
    AArch64Call26
    | AArch64Jump26
    | AArch64Page21
    | AArch64PageOffset12
    | X64PcRelative32 => 4
    Absolute64 => 8
  }
}

///|
fn relocation_matches_architecture(
  architecture : Architecture,
  kind : RelocationKind,
) -> Bool {
  match (architecture, kind) {
    (
      AArch64,
      AArch64Call26
      | AArch64Jump26
      | AArch64Page21
      | AArch64PageOffset12
      | Absolute64,
    ) => true
    (X64, X64PcRelative32 | Absolute64) => true
    _ => false
  }
}

///|
fn valid_code_offset(
  architecture : Architecture,
  code_size : Int,
  offset : Int,
) -> Bool {
  offset >= 0 &&
  offset < code_size &&
  offset % instruction_alignment(architecture) == 0
}

///|
fn read_u32_le(code : Array[Byte], offset : Int) -> UInt {
  code[offset].to_uint() |
  (code[offset + 1].to_uint() << 8) |
  (code[offset + 2].to_uint() << 16) |
  (code[offset + 3].to_uint() << 24)
}

///|
fn relocation_matches_encoding(
  code : Array[Byte],
  relocation : Relocation,
) -> Bool {
  match relocation.kind {
    AArch64Call26 =>
      (read_u32_le(code, relocation.offset) & 0xFC000000U) == 0x94000000U
    AArch64Jump26 =>
      (read_u32_le(code, relocation.offset) & 0xFC000000U) == 0x14000000U
    _ => true
  }
}

///|
pub fn UnlinkedCodeObject::verify(
  self : UnlinkedCodeObject,
) -> Unit raise CodeObjectVerifyError {
  let code_size = self.code.length()
  if code_size == 0 {
    raise EmptyCode
  }
  if self.architecture == AArch64 && code_size % 4 != 0 {
    raise MisalignedCodeSize(size=code_size)
  }
  let relocation_offsets : Array[Int] = []
  for index, relocation in self.relocations {
    let width = relocation_width(relocation.kind)
    if !relocation_matches_architecture(self.architecture, relocation.kind) ||
      relocation.offset < 0 ||
      relocation.offset + width > code_size ||
      (self.architecture == AArch64 && relocation.offset % 4 != 0) ||
      !relocation_matches_encoding(self.code, relocation) {
      raise InvalidRelocation(
        index~,
        message="kind, alignment, or range does not match the code object",
      )
    }
    if relocation_offsets.contains(relocation.offset) {
      raise DuplicateRelocationOffset(offset=relocation.offset)
    }
    relocation_offsets.push(relocation.offset)
  }
  for index, source in self.sources {
    if !valid_code_offset(self.architecture, code_size, source.offset) {
      raise InvalidSourceSite(index~, offset=source.offset)
    }
  }
  for index, trap in self.traps {
    if !valid_code_offset(self.architecture, code_size, trap.offset) {
      raise InvalidTrapSite(index~, offset=trap.offset)
    }
  }
  for index, safepoint in self.safepoints {
    if !valid_code_offset(self.architecture, code_size, safepoint.offset) {
      raise InvalidSafepointSite(index~, offset=safepoint.offset)
    }
    for root_index, root in safepoint.roots {
      let valid = match root {
        Register(Int, id) => id >= 0 && id < 31
        Register(FpVector, id) => id >= 0 && id < 32
        Stack(offset~, ty~) =>
          offset >= 0 && offset % (if ty == V128 { 16 } else { 8 }) == 0
      }
      if !valid {
        raise InvalidRootLocation(safepoint=index, root=root_index)
      }
    }
    if safepoint.stack_map is Some(stack_map) &&
      (stack_map.id < 0 || stack_map.argument_root_count < 0) {
      raise InvalidStackMap(safepoint=index)
    }
  }
  let stack_map_ids : Array[Int] = []
  for index, safepoint in self.safepoints {
    if safepoint.stack_map is Some(stack_map) {
      if stack_map_ids.contains(stack_map.id) {
        raise InvalidStackMap(safepoint=index)
      }
      stack_map_ids.push(stack_map.id)
    }
  }
  for id in 0..<stack_map_ids.length() {
    if !stack_map_ids.contains(id) {
      raise InvalidStackMap(safepoint=0)
    }
  }
}

///|
pub fn build(
  architecture : Architecture,
  code : Array[Byte],
  relocations? : Array[Relocation] = [],
  sources? : Array[SourceSite] = [],
  traps? : Array[TrapSite] = [],
  safepoints? : Array[SafepointSite] = [],
  unwind? : Array[Byte] = [],
) -> UnlinkedCodeObject raise CodeObjectVerifyError {
  let object = {
    architecture,
    code: code.copy(),
    relocations: relocations.copy(),
    sources: sources.copy(),
    traps: traps.copy(),
    safepoints: safepoints.map(site => {
      SafepointSite::new(
        site.offset,
        site.kind,
        site.roots,
        source?=site.source,
        stack_map?=site.stack_map,
      )
    }),
    unwind: unwind.copy(),
  }
  object.verify()
  object
}
