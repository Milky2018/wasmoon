///|
let simd_opcode_by_instruction : Map[@types.Instruction, Int32] = {
  let table : Map[@types.Instruction, Int32] = Map([])
  for pair in @types.simd_plain_opcodes() {
    let (opcode, instruction) = pair
    table.set(instruction, opcode)
  }
  table
}

///|
fn write_simd_opcode(w : @binary.Writer, opcode : Int32) -> Unit {
  w.write_byte(0xFD)
  w.write_u32(opcode)
}

///|
fn encode_simd_memory(
  w : @binary.Writer,
  opcode : Int32,
  memidx : Int32,
  align : Int32,
  offset : Int64,
  lane? : Int32,
) -> Unit {
  write_simd_opcode(w, opcode)
  encode_memarg(w, memidx, align, offset)
  if lane is Some(lane) {
    w.write_byte(lane)
  }
}

///|
fn encode_simd_lane(w : @binary.Writer, opcode : Int32, lane : Int32) -> Unit {
  write_simd_opcode(w, opcode)
  w.write_byte(lane)
}

///|
fn encode_simd_instruction(
  w : @binary.Writer,
  instruction : @types.Instruction,
) -> Unit {
  match instruction {
    V128Const(bytes) => {
      write_simd_opcode(w, 12)
      w.write_bytes(bytes[0:16])
    }
    I8x16Shuffle(lanes) => {
      write_simd_opcode(w, 13)
      for i in 0..<16 {
        w.write_byte(lanes[i])
      }
    }
    V128Load(memidx, align, offset) =>
      encode_simd_memory(w, 0, memidx, align, offset)
    V128Load8x8S(memidx, align, offset) =>
      encode_simd_memory(w, 1, memidx, align, offset)
    V128Load8x8U(memidx, align, offset) =>
      encode_simd_memory(w, 2, memidx, align, offset)
    V128Load16x4S(memidx, align, offset) =>
      encode_simd_memory(w, 3, memidx, align, offset)
    V128Load16x4U(memidx, align, offset) =>
      encode_simd_memory(w, 4, memidx, align, offset)
    V128Load32x2S(memidx, align, offset) =>
      encode_simd_memory(w, 5, memidx, align, offset)
    V128Load32x2U(memidx, align, offset) =>
      encode_simd_memory(w, 6, memidx, align, offset)
    V128Load8Splat(memidx, align, offset) =>
      encode_simd_memory(w, 7, memidx, align, offset)
    V128Load16Splat(memidx, align, offset) =>
      encode_simd_memory(w, 8, memidx, align, offset)
    V128Load32Splat(memidx, align, offset) =>
      encode_simd_memory(w, 9, memidx, align, offset)
    V128Load64Splat(memidx, align, offset) =>
      encode_simd_memory(w, 10, memidx, align, offset)
    V128Store(memidx, align, offset) =>
      encode_simd_memory(w, 11, memidx, align, offset)
    V128Load32Zero(memidx, align, offset) =>
      encode_simd_memory(w, 92, memidx, align, offset)
    V128Load64Zero(memidx, align, offset) =>
      encode_simd_memory(w, 93, memidx, align, offset)
    V128Load8Lane(memidx, align, offset, lane) =>
      encode_simd_memory(w, 84, memidx, align, offset, lane~)
    V128Load16Lane(memidx, align, offset, lane) =>
      encode_simd_memory(w, 85, memidx, align, offset, lane~)
    V128Load32Lane(memidx, align, offset, lane) =>
      encode_simd_memory(w, 86, memidx, align, offset, lane~)
    V128Load64Lane(memidx, align, offset, lane) =>
      encode_simd_memory(w, 87, memidx, align, offset, lane~)
    V128Store8Lane(memidx, align, offset, lane) =>
      encode_simd_memory(w, 88, memidx, align, offset, lane~)
    V128Store16Lane(memidx, align, offset, lane) =>
      encode_simd_memory(w, 89, memidx, align, offset, lane~)
    V128Store32Lane(memidx, align, offset, lane) =>
      encode_simd_memory(w, 90, memidx, align, offset, lane~)
    V128Store64Lane(memidx, align, offset, lane) =>
      encode_simd_memory(w, 91, memidx, align, offset, lane~)
    I8x16ExtractLaneS(lane) => encode_simd_lane(w, 21, lane)
    I8x16ExtractLaneU(lane) => encode_simd_lane(w, 22, lane)
    I8x16ReplaceLane(lane) => encode_simd_lane(w, 23, lane)
    I16x8ExtractLaneS(lane) => encode_simd_lane(w, 24, lane)
    I16x8ExtractLaneU(lane) => encode_simd_lane(w, 25, lane)
    I16x8ReplaceLane(lane) => encode_simd_lane(w, 26, lane)
    I32x4ExtractLane(lane) => encode_simd_lane(w, 27, lane)
    I32x4ReplaceLane(lane) => encode_simd_lane(w, 28, lane)
    I64x2ExtractLane(lane) => encode_simd_lane(w, 29, lane)
    I64x2ReplaceLane(lane) => encode_simd_lane(w, 30, lane)
    F32x4ExtractLane(lane) => encode_simd_lane(w, 31, lane)
    F32x4ReplaceLane(lane) => encode_simd_lane(w, 32, lane)
    F64x2ExtractLane(lane) => encode_simd_lane(w, 33, lane)
    F64x2ReplaceLane(lane) => encode_simd_lane(w, 34, lane)
    _ => {
      guard simd_opcode_by_instruction.get(instruction) is Some(opcode) else {
        abort("no binary encoding for instruction \{instruction}")
      }
      write_simd_opcode(w, opcode)
    }
  }
}
