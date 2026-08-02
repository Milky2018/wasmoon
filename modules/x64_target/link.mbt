///|
pub suberror X64LinkError {
  InvalidCodeObject(message~ : String)
  InvalidCodeBase(address~ : Int64)
  UnresolvedRelocation(index~ : Int)
  RelocationOutOfRange(index~ : Int)
  UnsupportedRelocation(index~ : Int)
} derive(Eq, Debug)

///|
pub impl Show for X64LinkError with fn output(self, logger) {
  logger.write_string(Repr(self).to_string())
}

///|
pub struct X64LinkPlan {
  priv code : Array[Byte]
  priv relocations : Array[@code_object.Relocation]
  priv veneer_offsets : Array[Int]
} derive(Debug)

///|
pub fn X64LinkPlan::code(self : X64LinkPlan) -> Array[Byte] {
  self.code.copy()
}

///|
pub fn X64LinkPlan::veneer_offsets(self : X64LinkPlan) -> Array[Int] {
  self.veneer_offsets.copy()
}

///|
fn append_call_veneer(code : Array[Byte]) -> Int {
  let offset = code.length()
  // jmp qword ptr [rip + 0], followed by the absolute target address.
  code.append([
    b'\xff', b'\x25', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00',
    b'\x00', b'\x00', b'\x00', b'\x00', b'\x00',
  ])
  offset
}

///|
pub fn prepare_x64_link(
  object : @code_object.UnlinkedCodeObject,
) -> X64LinkPlan raise X64LinkError {
  object.verify() catch {
    error => raise InvalidCodeObject(message=error.to_string())
  }
  if object.architecture() != X64 {
    raise InvalidCodeObject(message="expected an x64 code object")
  }
  let code = object.code()
  let relocations = object.relocations()
  let veneer_offsets = Array::make(relocations.length(), -1)
  let veneer_targets : Array[@code_object.RelocationTarget] = []
  let veneer_addends : Array[Int64] = []
  let veneers : Array[Int] = []
  for index, relocation in relocations {
    if relocation.kind is X64PcRelative32 {
      let mut veneer = -1
      for target_index, target in veneer_targets {
        if target == relocation.target &&
          veneer_addends[target_index] == relocation.addend {
          veneer = veneers[target_index]
          break
        }
      }
      if veneer < 0 {
        veneer = append_call_veneer(code)
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
fn write_u32(code : Array[Byte], offset : Int, value : UInt) -> Unit {
  for byte in 0..<4 {
    code[offset + byte] = ((value >> (byte * 8)) & 0xFFU).to_byte()
  }
}

///|
fn write_address(code : Array[Byte], offset : Int, address : Int64) -> Unit {
  let bits = address.reinterpret_as_uint64()
  for byte in 0..<8 {
    code[offset + byte] = ((bits >> (byte * 8)) & 0xFFUL).to_byte()
  }
}

///|
pub fn X64LinkPlan::link(
  self : X64LinkPlan,
  code_address : Int64,
  resolve : (@code_object.RelocationTarget) -> Int64?,
) -> Array[Byte] raise X64LinkError {
  if code_address < 0L {
    raise InvalidCodeBase(address=code_address)
  }
  let code = self.code.copy()
  for index, relocation in self.relocations {
    guard resolve(relocation.target) is Some(resolved) else {
      raise UnresolvedRelocation(index~)
    }
    let target = resolved + relocation.addend
    match relocation.kind {
      Absolute64 => write_address(code, relocation.offset, target)
      X64PcRelative32 => {
        let next_instruction = code_address + relocation.offset.to_int64() + 4L
        let displacement = target - next_instruction
        if displacement >= -0x80000000L && displacement <= 0x7FFFFFFFL {
          write_u32(
            code,
            relocation.offset,
            displacement.to_int().reinterpret_as_uint(),
          )
        } else {
          let veneer = self.veneer_offsets[index]
          if veneer < 0 {
            raise RelocationOutOfRange(index~)
          }
          let veneer_displacement = veneer.to_int64() -
            relocation.offset.to_int64() -
            4L
          if veneer_displacement < -0x80000000L ||
            veneer_displacement > 0x7FFFFFFFL {
            raise RelocationOutOfRange(index~)
          }
          write_u32(
            code,
            relocation.offset,
            veneer_displacement.to_int().reinterpret_as_uint(),
          )
          write_address(code, veneer + 6, target)
        }
      }
      AArch64Call26 | AArch64Jump26 | AArch64Page21 | AArch64PageOffset12 =>
        raise UnsupportedRelocation(index~)
    }
  }
  code
}
