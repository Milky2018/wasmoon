///|
pub suberror AArch64LinkError {
  InvalidCodeObject(message~ : String)
  InvalidCodeBase(address~ : Int64)
  UnresolvedRelocation(index~ : Int)
  RelocationOutOfRange(index~ : Int)
  UnsupportedRelocation(index~ : Int)
} derive(Eq, Debug)

///|
pub impl Show for AArch64LinkError with fn output(self, logger) {
  logger.write_string(to_repr(self).to_string())
}

///|
pub struct AArch64LinkPlan {
  priv code : Array[Byte]
  priv relocations : Array[@code_object.Relocation]
  priv veneer_offsets : Array[Int]
} derive(Debug)

///|
pub fn AArch64LinkPlan::code(self : AArch64LinkPlan) -> Array[Byte] {
  self.code.copy()
}

///|
pub fn AArch64LinkPlan::veneer_offsets(self : AArch64LinkPlan) -> Array[Int] {
  self.veneer_offsets.copy()
}

///|
fn append_branch_veneer(code : Array[Byte]) -> Int {
  let offset = code.length()
  code.append([
    b'\x50', b'\x00', b'\x00', b'\x58', b'\x00', b'\x02', b'\x1f', b'\xd6', b'\x00',
    b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00',
  ])
  offset
}

///|
pub fn prepare_aarch64_link(
  object : @code_object.UnlinkedCodeObject,
) -> AArch64LinkPlan raise AArch64LinkError {
  object.verify() catch {
    error => raise InvalidCodeObject(message=error.to_string())
  }
  if object.architecture() != AArch64 {
    raise InvalidCodeObject(message="expected an AArch64 code object")
  }
  let code = object.code()
  let relocations = object.relocations()
  let veneer_offsets = Array::make(relocations.length(), -1)
  let veneer_targets : Array[@code_object.RelocationTarget] = []
  let veneer_addends : Array[Int64] = []
  let veneers : Array[Int] = []
  for index, relocation in relocations {
    if relocation.kind is AArch64Call26 || relocation.kind is AArch64Jump26 {
      let mut veneer = -1
      for target_index, target in veneer_targets {
        if target == relocation.target &&
          veneer_addends[target_index] == relocation.addend {
          veneer = veneers[target_index]
          break
        }
      }
      if veneer < 0 {
        veneer = append_branch_veneer(code)
        veneer_targets.push(relocation.target)
        veneer_addends.push(relocation.addend)
        veneers.push(veneer)
      }
      veneer_offsets[index] = veneer
    }
  }
  { code, relocations, veneer_offsets }
}

///|
fn read_word(code : Array[Byte], offset : Int) -> UInt {
  code[offset].to_uint() |
  (code[offset + 1].to_uint() << 8) |
  (code[offset + 2].to_uint() << 16) |
  (code[offset + 3].to_uint() << 24)
}

///|
fn write_word(code : Array[Byte], offset : Int, word : UInt) -> Unit {
  code[offset] = (word & 0xFFU).to_byte()
  code[offset + 1] = ((word >> 8) & 0xFFU).to_byte()
  code[offset + 2] = ((word >> 16) & 0xFFU).to_byte()
  code[offset + 3] = ((word >> 24) & 0xFFU).to_byte()
}

///|
fn write_address(code : Array[Byte], offset : Int, address : Int64) -> Unit {
  let bits = address.reinterpret_as_uint64()
  for byte in 0..<8 {
    code[offset + byte] = ((bits >> (byte * 8)) & 0xFFUL).to_byte()
  }
}

///|
fn patch_branch(
  code : Array[Byte],
  offset : Int,
  delta : Int64,
  relocation_index : Int,
) -> Unit raise AArch64LinkError {
  if delta % 4L != 0L {
    raise RelocationOutOfRange(index=relocation_index)
  }
  let words = delta / 4L
  if words < -0x2000000L || words > 0x1FFFFFFL {
    raise RelocationOutOfRange(index=relocation_index)
  }
  let immediate = words.to_int() & 0x3FFFFFF
  let word = (read_word(code, offset) & 0xFC000000U) |
    immediate.reinterpret_as_uint()
  write_word(code, offset, word)
}

///|
fn patch_page21(
  code : Array[Byte],
  offset : Int,
  pc : Int64,
  target : Int64,
  relocation_index : Int,
) -> Unit raise AArch64LinkError {
  let delta = (target >> 12) - (pc >> 12)
  if delta < -0x100000L || delta > 0xFFFFFL {
    raise RelocationOutOfRange(index=relocation_index)
  }
  let bits = delta.to_int() & 0x1FFFFF
  let immlo = bits & 0x3
  let immhi = (bits >> 2) & 0x7FFFF
  let word = (read_word(code, offset) & 0x9F00001FU) |
    (immlo << 29).reinterpret_as_uint() |
    (immhi << 5).reinterpret_as_uint()
  write_word(code, offset, word)
}

///|
fn patch_page_offset12(
  code : Array[Byte],
  offset : Int,
  target : Int64,
) -> Unit {
  let immediate = (target.reinterpret_as_uint64() & 0xFFFUL).to_int()
  let word = (read_word(code, offset) & 0xFFC003FFU) |
    (immediate << 10).reinterpret_as_uint()
  write_word(code, offset, word)
}

///|
pub fn AArch64LinkPlan::link(
  self : AArch64LinkPlan,
  code_address : Int64,
  resolve : (@code_object.RelocationTarget) -> Int64?,
) -> Array[Byte] raise AArch64LinkError {
  if code_address < 0L || code_address % 4L != 0L {
    raise InvalidCodeBase(address=code_address)
  }
  let code = self.code.copy()
  for index, relocation in self.relocations {
    guard resolve(relocation.target) is Some(resolved) else {
      raise UnresolvedRelocation(index~)
    }
    let target = resolved + relocation.addend
    match relocation.kind {
      AArch64Call26 | AArch64Jump26 => {
        let pc = code_address + relocation.offset.to_int64()
        let direct_delta = target - pc
        if direct_delta % 4L == 0L &&
          direct_delta / 4L >= -0x2000000L &&
          direct_delta / 4L <= 0x1FFFFFFL {
          patch_branch(code, relocation.offset, direct_delta, index)
        } else {
          let veneer = self.veneer_offsets[index]
          if veneer < 0 {
            raise RelocationOutOfRange(index~)
          }
          patch_branch(
            code,
            relocation.offset,
            veneer.to_int64() - relocation.offset.to_int64(),
            index,
          )
          write_address(code, veneer + 8, target)
        }
      }
      AArch64Page21 =>
        patch_page21(
          code,
          relocation.offset,
          code_address + relocation.offset.to_int64(),
          target,
          index,
        )
      AArch64PageOffset12 =>
        patch_page_offset12(code, relocation.offset, target)
      Absolute64 => write_address(code, relocation.offset, target)
      X64PcRelative32 => raise UnsupportedRelocation(index~)
    }
  }
  code
}
