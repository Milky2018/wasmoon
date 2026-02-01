// SIMD codegen for MachineCode::emit_instruction

///|
fn MachineCode::emit_instruction_simd(
  self : MachineCode,
  inst : @instr.VCodeInst,
  stack_frame : JITStackFrame,
  spill_base_offset : Int,
  frame_size : Int,
) -> Unit {
  ignore(stack_frame)
  ignore(spill_base_offset)
  ignore(frame_size)
  match inst.opcode {
    // ============ SIMD Instructions ============
    LoadConstV128(bytes) => {
      // Load V128 constant using GPR + INS instructions
      // Strategy: Load two 64-bit halves into X16, X17, then INS into vector register
      let rd = wreg_num(inst.defs[0])

      // Extract low and high 64-bit values (little-endian)
      let low = bytes_to_int64_le(bytes, 0)
      let high = bytes_to_int64_le(bytes, 8)

      // Optimization: all zeros -> MOVI Vd.2D, #0
      if low == 0L && high == 0L {
        MoviZero(rd).emit(self)
      } else {
        // General case: MOVI zero, then INS the two 64-bit values
        MoviZero(rd).emit(self)

        // Insert low 64-bit (D[0])
        if low != 0L {
          self.emit_load_imm64(16, low)
          InsD(rd, 0, 16).emit(self)
        }

        // Insert high 64-bit (D[1])
        if high != 0L {
          self.emit_load_imm64(16, high)
          InsD(rd, 1, 16).emit(self)
        }
      }
    }
    SIMDSplat(lane_size) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      match lane_size {
        B8 => Dup16B(rd, rn).emit(self)
        H16 => Dup8H(rd, rn).emit(self)
        S32 => Dup4S(rd, rn).emit(self)
        D64 => Dup2D(rd, rn).emit(self)
      }
    }
    SIMDSplatF(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if is_f32 {
        DupElem4S(rd, rn, 0).emit(self)
      } else {
        DupElem2D(rd, rn, 0).emit(self)
      }
    }
    SIMDExtractU(lane_size, lane) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      match lane_size {
        B8 => UmovB(rd, rn, lane).emit(self)
        H16 => UmovH(rd, rn, lane).emit(self)
        S32 => UmovS(rd, rn, lane).emit(self)
        D64 => UmovD(rd, rn, lane).emit(self)
      }
    }
    SIMDExtractS(lane_size, lane) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      match lane_size {
        B8 => SmovB(rd, rn, lane).emit(self)
        H16 => SmovH(rd, rn, lane).emit(self)
        S32 => SmovS(rd, rn, lane).emit(self)
        D64 => UmovD(rd, rn, lane).emit(self) // No SMOV for D64
      }
    }
    SIMDExtractF(is_f32, lane) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if is_f32 {
        DupScalarS(rd, rn, lane).emit(self)
      } else {
        DupScalarD(rd, rn, lane).emit(self)
      }
    }
    SIMDInsert(lane_size, lane) => {
      let rd = wreg_num(inst.defs[0])
      let rv = reg_num(inst.uses[0]) // source vector
      let rn = reg_num(inst.uses[1]) // value to insert
      // INS modifies destination in-place, so copy source vector first if different
      if rd != rv {
        OrrVec(rd, rv).emit(self)
      }
      match lane_size {
        B8 => InsB(rd, lane, rn).emit(self)
        H16 => InsH(rd, lane, rn).emit(self)
        S32 => InsS(rd, lane, rn).emit(self)
        D64 => InsD(rd, lane, rn).emit(self)
      }
    }
    SIMDInsertF(is_f32, lane) => {
      let rd = wreg_num(inst.defs[0])
      let rv = reg_num(inst.uses[0]) // source vector
      let rn = reg_num(inst.uses[1]) // value to insert
      // INS modifies destination in-place, so copy source vector first if different
      if rd != rv {
        OrrVec(rd, rv).emit(self)
      }
      if is_f32 {
        InsElemS(rd, lane, rn, 0).emit(self)
      } else {
        InsElemD(rd, lane, rn, 0).emit(self)
      }
    }
    SIMDShuffle(lanes) => {
      // i8x16.shuffle: select lanes from two source vectors using constant indices
      // Use two TBL1 calls instead of TBL2 to avoid consecutive register requirement.
      // Each TBL1 handles one source vector. TBL returns 0 for out-of-range indices.
      let rd = wreg_num(inst.defs[0])
      let temp1 = wreg_num(inst.defs[1]) // temp for TBL1 from first source
      let temp2 = wreg_num(inst.defs[2]) // temp for TBL1 from second source
      let rn = reg_num(inst.uses[0]) // first source (lanes 0-15)
      let rm = reg_num(inst.uses[1]) // second source (lanes 16-31)
      // Use V16 as a reserved scratch vector register for aliasing fixes.
      // This avoids clobbering `rd` when `rd` aliases an input.
      let scratch = 16
      // Aliasing analysis:
      // - rn == temp1: must save before indices1 build destroys temp1
      // - rn == temp2: safe (TBL1 reads rn before indices2 build touches temp2)
      // - rm == temp1: must save before indices1 build destroys temp1
      // - rm == temp2: must save before indices2 build destroys temp2
      //
      // Phase 1: Save temp1 if either input uses it
      let temp1_has_input = rn == temp1 || rm == temp1
      if temp1_has_input {
        Orr16B(scratch, temp1, temp1).emit(self) // Save input before clobbering temp1
      }
      let actual_rn = if rn == temp1 { scratch } else { rn }
      // Build two index vectors at compile time:
      // indices1: lanes < 16 keep original, lanes >= 16 use 0x80 (out of range)
      // indices2: lanes >= 16 use lane-16, lanes < 16 use 0x80 (out of range)
      let mut low1 = 0L
      let mut high1 = 0L
      let mut low2 = 0L
      let mut high2 = 0L
      for i in 0..<8 {
        let lane = lanes[i]
        if lane < 16 {
          low1 = low1 | ((lane.to_int64() & 0xFFL) << (i * 8))
          low2 = low2 | (0x80L << (i * 8))
        } else {
          low1 = low1 | (0x80L << (i * 8))
          low2 = low2 | (((lane - 16).to_int64() & 0xFFL) << (i * 8))
        }
        let lane2 = lanes[i + 8]
        if lane2 < 16 {
          high1 = high1 | ((lane2.to_int64() & 0xFFL) << (i * 8))
          high2 = high2 | (0x80L << (i * 8))
        } else {
          high1 = high1 | (0x80L << (i * 8))
          high2 = high2 | (((lane2 - 16).to_int64() & 0xFFL) << (i * 8))
        }
      }
      // Load indices1 into temp1
      MoviZero(temp1).emit(self)
      if low1 != 0L {
        self.emit_load_imm64(16, low1)
        InsD(temp1, 0, 16).emit(self)
      }
      if high1 != 0L {
        self.emit_load_imm64(16, high1)
        InsD(temp1, 1, 16).emit(self)
      }
      // TBL1 for first source
      Tbl1(temp1, actual_rn, temp1).emit(self) // temp1 = select from rn
      // Phase 2: Handle rm aliasing
      // - rm == temp1: already saved to rd in phase 1
      // - rm == temp2: save now before indices2 build destroys it
      let actual_rm = if rm == temp1 {
        scratch // Already saved before indices1 build
      } else if rm == temp2 {
        Orr16B(scratch, rm, rm).emit(self) // Save input before clobbering temp2
        scratch
      } else {
        rm
      }
      // Load indices2 into temp2
      MoviZero(temp2).emit(self)
      if low2 != 0L {
        self.emit_load_imm64(16, low2)
        InsD(temp2, 0, 16).emit(self)
      }
      if high2 != 0L {
        self.emit_load_imm64(16, high2)
        InsD(temp2, 1, 16).emit(self)
      }
      // TBL1 for second source
      Tbl1(temp2, actual_rm, temp2).emit(self) // temp2 = select from rm
      // Combine results with ORR (0 | value = value)
      Orr16B(rd, temp1, temp2).emit(self)
    }
    SIMDSwizzle => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      Tbl1(rd, rn, rm).emit(self)
    }
    SIMDNot => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      Not16B(rd, rn).emit(self)
    }
    SIMDAnd => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      And16B(rd, rn, rm).emit(self)
    }
    SIMDBic => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      Bic16B(rd, rn, rm).emit(self)
    }
    SIMDOr => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      Orr16B(rd, rn, rm).emit(self)
    }
    SIMDXor => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      Eor16B(rd, rn, rm).emit(self)
    }
    SIMDBsl => {
      // v128.bitselect(a, b, c) = (a & c) | (b & ~c)
      // uses[0] = a, uses[1] = b, uses[2] = c (mask)
      // BSL Vd, Vn, Vm: Vd = (Vn & Vd) | (Vm & ~Vd)
      // So we need: Vd = c (mask), Vn = a, Vm = b
      let rd = wreg_num(inst.defs[0])
      let a = reg_num(inst.uses[0])
      let b = reg_num(inst.uses[1])
      let c = reg_num(inst.uses[2]) // mask
      // Implement without any fixed scratch vector registers:
      // result = b ^ ((a ^ b) & c)
      //
      // Special case: if rd aliases the mask reg c and c is dead after this op,
      // BSL can compute the result in-place (Vd is both mask input and output).
      if rd == c {
        Bsl16B(rd, a, b).emit(self)
      } else if rd == b {
        // rd = a ^ b
        Eor16B(rd, a, b).emit(self)
        // rd = (a ^ b) & ~c
        Bic16B(rd, rd, c).emit(self)
        // rd = a ^ ((a ^ b) & ~c) = (a & c) | (b & ~c)
        Eor16B(rd, rd, a).emit(self)
      } else {
        // rd = a ^ b
        Eor16B(rd, a, b).emit(self)
        // rd = (a ^ b) & c
        And16B(rd, rd, c).emit(self)
        // rd = b ^ ((a ^ b) & c)
        Eor16B(rd, rd, b).emit(self)
      }
    }
    SIMDAnyTrue => {
      // v128.any_true: returns 1 if any bit is set, 0 otherwise
      // Algorithm: UMAXV Bd, Vn.16B (max byte across lanes)
      //            FMOV Xd, Dn (move to GPR - upper bits are zero)
      //            CMP Xd, #0; CSET Wd, NE
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let tmp = wreg_num(inst.defs[1])
      // Step 1: UMAXV to get max byte into tmp
      Umaxv16B(tmp, rn).emit(self)
      // Step 2: FMOV from Dtmp to X16 (result in low byte, rest is zero)
      self.emit_fmov_d_to_x(16, tmp)
      // Step 3: CMP X16, #0
      self.emit_cmp_imm(16, 0)
      // Step 4: CSET Wd, NE (rd = 1 if X16 != 0, else 0)
      self.emit_cset(rd, 1) // NE condition
    }
    SIMDAllTrue(lane_size) => {
      // i*x*.all_true: returns 1 if all lanes are non-zero, 0 otherwise
      // Algorithm: UMINV (min across lanes), compare != 0
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      match lane_size {
        B8 =>
          // i8x16.all_true: UMINV Bd, Vn.16B
          Uminv16B(wreg_num(inst.defs[1]), rn).emit(self)
        H16 =>
          // i16x8.all_true: UMINV Hd, Vn.8H
          Uminv8H(wreg_num(inst.defs[1]), rn).emit(self)
        S32 =>
          // i32x4.all_true: UMINV Sd, Vn.4S
          Uminv4S(wreg_num(inst.defs[1]), rn).emit(self)
        D64 => {
          // i64x2.all_true: (lane0 != 0) && (lane1 != 0)
          UmovD(16, rn, 0).emit(self)
          UmovD(17, rn, 1).emit(self)
          self.emit_cmp_imm(16, 0)
          // If lane0 != 0 then CMP lane1, else force Z=1 so NE is false.
          self.emit_ccmp_imm(17, 0, 4, 1, true)
          self.emit_cset(rd, 1) // NE
          return
        }
      }
      // Common: compare result != 0 and set rd to 0/1
      if lane_size is D64 {
        // Already have result in X16, just compare
        self.emit_cmp_imm(16, 0)
      } else {
        let tmp = wreg_num(inst.defs[1])
        // FMOV from Dtmp to X16
        self.emit_fmov_d_to_x(16, tmp)
        self.emit_cmp_imm(16, 0)
      }
      // CSET Wd, NE
      self.emit_cset(rd, 1)
    }
    SIMDBitmask(lane_size) => {
      // Extract MSB of each lane into an integer
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      match lane_size {
        D64 => {
          // i64x2.bitmask: 2 lanes -> 2-bit result
          // Extract lane 0 MSB using UMOV, then shift right by 63
          UmovD(16, rn, 0).emit(self) // X16 = Vn.D[0]
          self.emit_lsr_imm(16, 16, 63) // X16 = bit 0
          // Extract lane 1 MSB
          UmovD(17, rn, 1).emit(self) // X17 = Vn.D[1]
          self.emit_lsr_imm(17, 17, 63) // X17 = bit 1
          // Combine: rd = bit0 | (bit1 << 1)
          self.emit_orr_shifted(rd, 16, 17, @instr.ShiftType::Lsl, 1)
        }
        S32 => {
          // i32x4.bitmask: 4 lanes -> 4-bit result
          // Use LSR immediate, no extra register needed
          UmovS(16, rn, 0).emit(self) // W16 = Vn.S[0]
          self.emit_lsr_imm32(16, 16, 31) // bit 0
          UmovS(17, rn, 1).emit(self)
          self.emit_lsr_imm32(17, 17, 31)
          self.emit_orr_shifted(16, 16, 17, @instr.ShiftType::Lsl, 1) // bits 0-1
          UmovS(17, rn, 2).emit(self)
          self.emit_lsr_imm32(17, 17, 31)
          self.emit_orr_shifted(16, 16, 17, @instr.ShiftType::Lsl, 2) // bits 0-2
          UmovS(17, rn, 3).emit(self)
          self.emit_lsr_imm32(17, 17, 31)
          self.emit_orr_shifted(rd, 16, 17, @instr.ShiftType::Lsl, 3) // bits 0-3
        }
        H16 => {
          // i16x8.bitmask: 8 lanes -> 8-bit result
          // Use LSR immediate, no extra register needed
          UmovH(16, rn, 0).emit(self)
          self.emit_lsr_imm32(16, 16, 15) // bit 0
          UmovH(17, rn, 1).emit(self)
          self.emit_lsr_imm32(17, 17, 15)
          self.emit_orr_shifted(16, 16, 17, @instr.ShiftType::Lsl, 1)
          UmovH(17, rn, 2).emit(self)
          self.emit_lsr_imm32(17, 17, 15)
          self.emit_orr_shifted(16, 16, 17, @instr.ShiftType::Lsl, 2)
          UmovH(17, rn, 3).emit(self)
          self.emit_lsr_imm32(17, 17, 15)
          self.emit_orr_shifted(16, 16, 17, @instr.ShiftType::Lsl, 3)
          UmovH(17, rn, 4).emit(self)
          self.emit_lsr_imm32(17, 17, 15)
          self.emit_orr_shifted(16, 16, 17, @instr.ShiftType::Lsl, 4)
          UmovH(17, rn, 5).emit(self)
          self.emit_lsr_imm32(17, 17, 15)
          self.emit_orr_shifted(16, 16, 17, @instr.ShiftType::Lsl, 5)
          UmovH(17, rn, 6).emit(self)
          self.emit_lsr_imm32(17, 17, 15)
          self.emit_orr_shifted(16, 16, 17, @instr.ShiftType::Lsl, 6)
          UmovH(17, rn, 7).emit(self)
          self.emit_lsr_imm32(17, 17, 15)
          self.emit_orr_shifted(rd, 16, 17, @instr.ShiftType::Lsl, 7)
        }
        B8 => {
          // i8x16.bitmask: 16 lanes -> 16-bit result
          // Use weighted add approach for efficiency
          // Temps allocated by regalloc: defs[1]=weights, defs[2]=shift, defs[3]=work
          let v_weights = wreg_num(inst.defs[1])
          let v_shift = wreg_num(inst.defs[2])
          let v_work = wreg_num(inst.defs[3])
          // Check for aliasing: if rn aliases v_weights or v_shift, we must copy
          // rn to v_work first before those temps are overwritten.
          // (rn == v_work is safe because Sshl reads before writing)
          let actual_rn = if rn == v_weights || rn == v_shift {
            Orr16B(v_work, rn, rn).emit(self) // MOV v_work, rn
            v_work
          } else {
            rn
          }
          // Step 1: Load weights [1,2,4,8,16,32,64,128,1,2,4,8,16,32,64,128]
          // 0x8040201008040201 = weights for 8 bytes (little endian)
          // Use X16/X17 (linker scratch GPR) for loading immediate
          LoadImm64(17, 0x8040201008040201L).emit(self)
          self.emit_fmov_x_to_d(v_weights, 17) // v_weights.D[0] = weights
          DupElem2D(v_weights, v_weights, 0).emit(self) // v_weights.D[1] = v_weights.D[0]
          // Step 2: Shift each byte right by 7 to get 0/1 based on MSB
          // Load -7 into all lanes (0xF9 = -7 in signed byte)
          self.emit_movz(17, 0xF9, 0) // X17 = 0xF9 = -7 as unsigned byte
          Dup16B(v_shift, 17).emit(self) // v_shift.16B = all 0xF9 = -7
          Sshl16B(v_work, actual_rn, v_shift).emit(self) // v_work = signed shift right by 7
          // Now v_work has 0x00 or 0xFF in each lane (all 0s or all 1s)
          // Step 3: AND with weights to get weighted bits
          And16B(v_work, v_work, v_weights).emit(self) // v_work = weighted bits
          // Step 4: Pairwise add to combine
          Uaddlp8H(v_work, v_work).emit(self) // v_work.8H = pairwise sums
          Uaddlp4S(v_work, v_work).emit(self) // v_work.4S = pairwise sums
          Uaddlp2D(v_work, v_work).emit(self) // v_work.2D = pairwise sums
          // v_work.D[0] = low 8 bits, v_work.D[1] = high 8 bits
          self.emit_fmov_d_to_x(16, v_work) // X16 = low 8 bits
          self.emit_ext_16b(v_shift, v_work, v_work, 8) // rotate to get high half (reuse v_shift)
          self.emit_fmov_d_to_x(17, v_shift) // X17 = high 8 bits
          // Combine: rd = low | (high << 8)
          self.emit_orr_shifted(rd, 16, 17, @instr.ShiftType::Lsl, 8)
        }
      }
    }
    SIMDAdd(lane_size) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      match lane_size {
        B8 => Add16B(rd, rn, rm).emit(self)
        H16 => Add8H(rd, rn, rm).emit(self)
        S32 => Add4S(rd, rn, rm).emit(self)
        D64 => Add2D(rd, rn, rm).emit(self)
      }
    }
    SIMDSub(lane_size) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      match lane_size {
        B8 => Sub16B(rd, rn, rm).emit(self)
        H16 => Sub8H(rd, rn, rm).emit(self)
        S32 => Sub4S(rd, rn, rm).emit(self)
        D64 => Sub2D(rd, rn, rm).emit(self)
      }
    }
    SIMDMul(lane_size) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      match lane_size {
        B8 => abort("SIMD JIT: MUL.16B not supported, need expansion")
        H16 => Mul8H(rd, rn, rm).emit(self)
        S32 => Mul4S(rd, rn, rm).emit(self)
        D64 => {
          // i64x2.mul emulation: NEON doesn't have MUL.2D
          // a*b = (a_hi*b_lo + a_lo*b_hi) << 32 + a_lo*b_lo
          // IMPORTANT: the result register can alias an input register.
          // Use temporaries for all intermediates and only write `rd` at the end.
          //
          // Also IMPORTANT: this expands to multiple machine instructions, so we
          // must not rely on `rn` / `rm` remaining unmodified after the first
          // instruction. Regalloc may legally reuse dead input regs for temps.
          // Copy inputs into reserved scratch V16/V17 first.
          //
          // Temps allocated by regalloc: defs[1..5]
          let t0 = wreg_num(inst.defs[1]) // a_lo (2s)
          let t1 = wreg_num(inst.defs[2]) // b_lo (2s), then reused as cross2 (2d)
          let t2 = wreg_num(inst.defs[3]) // low product (2d)
          let t3 = wreg_num(inst.defs[4]) // scratch for hi halves (2s)
          let t4 = wreg_num(inst.defs[5]) // cross sum (2d)

          // Save inputs to scratch regs (V16/V17 are non-allocatable).
          let a = 16
          let b = 17
          OrrVec(a, rn).emit(self)
          OrrVec(b, rm).emit(self)

          // 1. Extract low 32-bit halves
          Xtn2S(t0, a).emit(self) // t0 = [a0_lo, a1_lo]
          Xtn2S(t1, b).emit(self) // t1 = [b0_lo, b1_lo]

          // 2. low = a_lo * b_lo
          Umull2D(t2, t0, t1).emit(self)

          // 3. a_hi = high 32-bit halves of a
          Rev64_4S(t3, a).emit(self)
          Xtn2S(t3, t3).emit(self) // t3 = [a0_hi, a1_hi]

          // 4. cross1 = a_hi * b_lo
          Umull2D(t4, t3, t1).emit(self)

          // 5. b_hi = high 32-bit halves of b
          Rev64_4S(t3, b).emit(self)
          Xtn2S(t3, t3).emit(self) // t3 = [b0_hi, b1_hi]

          // 6. cross2 = a_lo * b_hi (reuse t1 as a 2d dest)
          Umull2D(t1, t0, t3).emit(self)

          // 7. cross = cross1 + cross2
          Add2D(t4, t4, t1).emit(self)

          // 8. Shift cross products left by 32
          ShlImm2D(t4, t4, 32).emit(self)

          // 9. Add to low*low to get final result
          Add2D(rd, t2, t4).emit(self)
        }
      }
    }
    SIMDSqadd(lane_size) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      match lane_size {
        B8 => Sqadd16B(rd, rn, rm).emit(self)
        H16 => Sqadd8H(rd, rn, rm).emit(self)
        S32 => Sqadd4S(rd, rn, rm).emit(self)
        D64 => Sqadd2D(rd, rn, rm).emit(self)
      }
    }
    SIMDUqadd(lane_size) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      match lane_size {
        B8 => Uqadd16B(rd, rn, rm).emit(self)
        H16 => Uqadd8H(rd, rn, rm).emit(self)
        S32 => Uqadd4S(rd, rn, rm).emit(self)
        D64 => Uqadd2D(rd, rn, rm).emit(self)
      }
    }
    SIMDSqsub(lane_size) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      match lane_size {
        B8 => Sqsub16B(rd, rn, rm).emit(self)
        H16 => Sqsub8H(rd, rn, rm).emit(self)
        S32 => Sqsub4S(rd, rn, rm).emit(self)
        D64 => Sqsub2D(rd, rn, rm).emit(self)
      }
    }
    SIMDUqsub(lane_size) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      match lane_size {
        B8 => Uqsub16B(rd, rn, rm).emit(self)
        H16 => Uqsub8H(rd, rn, rm).emit(self)
        S32 => Uqsub4S(rd, rn, rm).emit(self)
        D64 => Uqsub2D(rd, rn, rm).emit(self)
      }
    }
    SIMDSmin(lane_size) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      match lane_size {
        B8 => Smin16B(rd, rn, rm).emit(self)
        H16 => Smin8H(rd, rn, rm).emit(self)
        S32 => Smin4S(rd, rn, rm).emit(self)
        D64 => abort("SIMD JIT: SMIN.2D not supported")
      }
    }
    SIMDUmin(lane_size) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      match lane_size {
        B8 => Umin16B(rd, rn, rm).emit(self)
        H16 => Umin8H(rd, rn, rm).emit(self)
        S32 => Umin4S(rd, rn, rm).emit(self)
        D64 => abort("SIMD JIT: UMIN.2D not supported")
      }
    }
    SIMDSmax(lane_size) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      match lane_size {
        B8 => Smax16B(rd, rn, rm).emit(self)
        H16 => Smax8H(rd, rn, rm).emit(self)
        S32 => Smax4S(rd, rn, rm).emit(self)
        D64 => abort("SIMD JIT: SMAX.2D not supported")
      }
    }
    SIMDUmax(lane_size) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      match lane_size {
        B8 => Umax16B(rd, rn, rm).emit(self)
        H16 => Umax8H(rd, rn, rm).emit(self)
        S32 => Umax4S(rd, rn, rm).emit(self)
        D64 => abort("SIMD JIT: UMAX.2D not supported")
      }
    }
    SIMDUrhadd(lane_size) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      match lane_size {
        B8 => Urhadd16B(rd, rn, rm).emit(self)
        H16 => Urhadd8H(rd, rn, rm).emit(self)
        S32 => Urhadd4S(rd, rn, rm).emit(self)
        D64 => abort("SIMD JIT: URHADD.2D not supported")
      }
    }
    SIMDAbs(lane_size) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      match lane_size {
        B8 => Abs16B(rd, rn).emit(self)
        H16 => Abs8H(rd, rn).emit(self)
        S32 => Abs4S(rd, rn).emit(self)
        D64 => Abs2D(rd, rn).emit(self)
      }
    }
    SIMDNeg(lane_size) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      match lane_size {
        B8 => Neg16B(rd, rn).emit(self)
        H16 => Neg8H(rd, rn).emit(self)
        S32 => Neg4S(rd, rn).emit(self)
        D64 => Neg2D(rd, rn).emit(self)
      }
    }
    SIMDCnt => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      Cnt16B(rd, rn).emit(self)
    }
    SIMDBroadcastShift(lane_size, negate) => {
      // Mask scalar shift amount and broadcast to vector
      // Uses: [shift_scalar], Defs: [temp_gpr, shift_vec]
      let temp_gpr = wreg_num(inst.defs[0]) // temp GPR for masked shift
      let rd = wreg_num(inst.defs[1]) // destination vector register
      let rm = reg_num(inst.uses[0]) // source scalar (GPR)
      // Mask shift amount to valid range using UBFX
      let width = match lane_size {
        B8 => 3 // mask = 7 = 0b111
        H16 => 4 // mask = 15 = 0b1111
        S32 => 5 // mask = 31 = 0b11111
        D64 => 6 // mask = 63 = 0b111111
      }
      UbfxWidth(temp_gpr, rm, width).emit(self)
      // Negate if needed (for right shifts)
      if negate {
        self.emit_sub_reg(temp_gpr, 31, temp_gpr) // temp_gpr = -temp_gpr
      }
      // Broadcast to all lanes
      match lane_size {
        B8 => Dup16B(rd, temp_gpr).emit(self)
        H16 => Dup8H(rd, temp_gpr).emit(self)
        S32 => Dup4S(rd, temp_gpr).emit(self)
        D64 => Dup2D(rd, temp_gpr).emit(self)
      }
    }
    SIMDShiftByVec(lane_size, use_ushl) => {
      // Vector shift: input_vec shifted by shift_vec (already broadcast)
      // Uses: [input_vec, shift_vec], Defs: [result]
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0]) // input vector
      let rm = reg_num(inst.uses[1]) // shift vector
      if use_ushl {
        // Unsigned shift (USHL)
        match lane_size {
          B8 => Ushl16B(rd, rn, rm).emit(self)
          H16 => Ushl8H(rd, rn, rm).emit(self)
          S32 => Ushl4S(rd, rn, rm).emit(self)
          D64 => Ushl2D(rd, rn, rm).emit(self)
        }
      } else {
        // Signed shift (SSHL) - used for left shift and signed right shift
        match lane_size {
          B8 => Sshl16B(rd, rn, rm).emit(self)
          H16 => Sshl8H(rd, rn, rm).emit(self)
          S32 => Sshl4S(rd, rn, rm).emit(self)
          D64 => Sshl2D(rd, rn, rm).emit(self)
        }
      }
    }
    SIMDCmp(lane_size, cmp_kind) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      match (lane_size, cmp_kind) {
        (B8, Eq) => Cmeq16B(rd, rn, rm).emit(self)
        (H16, Eq) => Cmeq8H(rd, rn, rm).emit(self)
        (S32, Eq) => Cmeq4S(rd, rn, rm).emit(self)
        (D64, Eq) => Cmeq2D(rd, rn, rm).emit(self)
        (B8, GtS) => Cmgt16B(rd, rn, rm).emit(self)
        (H16, GtS) => Cmgt8H(rd, rn, rm).emit(self)
        (S32, GtS) => Cmgt4S(rd, rn, rm).emit(self)
        (D64, GtS) => Cmgt2D(rd, rn, rm).emit(self)
        (B8, GeS) => Cmge16B(rd, rn, rm).emit(self)
        (H16, GeS) => Cmge8H(rd, rn, rm).emit(self)
        (S32, GeS) => Cmge4S(rd, rn, rm).emit(self)
        (D64, GeS) => Cmge2D(rd, rn, rm).emit(self)
        (B8, GtU) => Cmhi16B(rd, rn, rm).emit(self)
        (H16, GtU) => Cmhi8H(rd, rn, rm).emit(self)
        (S32, GtU) => Cmhi4S(rd, rn, rm).emit(self)
        (D64, GtU) => Cmhi2D(rd, rn, rm).emit(self)
        (B8, GeU) => Cmhs16B(rd, rn, rm).emit(self)
        (H16, GeU) => Cmhs8H(rd, rn, rm).emit(self)
        (S32, GeU) => Cmhs4S(rd, rn, rm).emit(self)
        (D64, GeU) => Cmhs2D(rd, rn, rm).emit(self)
      }
    }
    SIMDNarrow(lane_size, is_signed) => {
      // Narrow two v128 to one v128 with saturation
      // First input -> lower half, second input -> upper half
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0]) // First input
      let rm = reg_num(inst.uses[1]) // Second input
      match (lane_size, is_signed) {
        (B8, true) => {
          // i8x16.narrow_i16x8_s
          Sqxtn8B(rd, rn).emit(self) // Lower 8 bytes from first input
          Sqxtn2_16B(rd, rm).emit(self) // Upper 8 bytes from second input
        }
        (B8, false) => {
          // i8x16.narrow_i16x8_u
          Sqxtun8B(rd, rn).emit(self) // Lower 8 bytes from first input
          Sqxtun2_16B(rd, rm).emit(self) // Upper 8 bytes from second input
        }
        (H16, true) => {
          // i16x8.narrow_i32x4_s
          Sqxtn4H(rd, rn).emit(self) // Lower 4 halfwords from first input
          Sqxtn2_8H(rd, rm).emit(self) // Upper 4 halfwords from second input
        }
        (H16, false) => {
          // i16x8.narrow_i32x4_u
          Sqxtun4H(rd, rn).emit(self) // Lower 4 halfwords from first input
          Sqxtun2_8H(rd, rm).emit(self) // Upper 4 halfwords from second input
        }
        _ => abort("Unsupported narrow operation")
      }
    }
    SIMDExtendLow(lane_size, is_signed) => {
      // Extend lower half of input to full width
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      match (lane_size, is_signed) {
        (H16, true) => Sxtl8H(rd, rn).emit(self) // i8 -> i16 (low 8 bytes)
        (H16, false) => Uxtl8H(rd, rn).emit(self)
        (S32, true) => Sxtl4S(rd, rn).emit(self) // i16 -> i32 (low 4 halfwords)
        (S32, false) => Uxtl4S(rd, rn).emit(self)
        (D64, true) => Sxtl2D(rd, rn).emit(self) // i32 -> i64 (low 2 words)
        (D64, false) => Uxtl2D(rd, rn).emit(self)
        _ => abort("Unsupported extend low operation")
      }
    }
    SIMDExtendHigh(lane_size, is_signed) => {
      // Extend upper half of input to full width
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      match (lane_size, is_signed) {
        (H16, true) => Sxtl2_8H(rd, rn).emit(self) // i8 -> i16 (high 8 bytes)
        (H16, false) => Uxtl2_8H(rd, rn).emit(self)
        (S32, true) => Sxtl2_4S(rd, rn).emit(self) // i16 -> i32 (high 4 halfwords)
        (S32, false) => Uxtl2_4S(rd, rn).emit(self)
        (D64, true) => Sxtl2_2D(rd, rn).emit(self) // i32 -> i64 (high 2 words)
        (D64, false) => Uxtl2_2D(rd, rn).emit(self)
        _ => abort("Unsupported extend high operation")
      }
    }
    SIMDExtMulLow(lane_size, is_signed) => {
      // Extended multiply: multiply lower halves and produce wider result
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      match (lane_size, is_signed) {
        (H16, true) => Smull8H(rd, rn, rm).emit(self) // i8x8 -> i16x8
        (H16, false) => Umull8H(rd, rn, rm).emit(self)
        (S32, true) => Smull4S(rd, rn, rm).emit(self) // i16x4 -> i32x4
        (S32, false) => Umull4S(rd, rn, rm).emit(self)
        (D64, true) => Smull2D(rd, rn, rm).emit(self) // i32x2 -> i64x2
        (D64, false) => Umull2D(rd, rn, rm).emit(self)
        _ => abort("Unsupported extmul low operation")
      }
    }
    SIMDExtMulHigh(lane_size, is_signed) => {
      // Extended multiply: multiply upper halves and produce wider result
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      match (lane_size, is_signed) {
        (H16, true) => Smull2_8H(rd, rn, rm).emit(self) // i8x8 -> i16x8
        (H16, false) => Umull2_8H(rd, rn, rm).emit(self)
        (S32, true) => Smull2_4S(rd, rn, rm).emit(self) // i16x4 -> i32x4
        (S32, false) => Umull2_4S(rd, rn, rm).emit(self)
        (D64, true) => Smull2_2D(rd, rn, rm).emit(self) // i32x2 -> i64x2
        (D64, false) => Umull2_2D(rd, rn, rm).emit(self)
        _ => abort("Unsupported extmul high operation")
      }
    }
    SIMDExtAddPairwise(lane_size, is_signed) => {
      // Extended add pairwise: add adjacent pairs and widen result
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      match (lane_size, is_signed) {
        (H16, true) => Saddlp8H(rd, rn).emit(self) // pairs of i8 -> i16
        (H16, false) => Uaddlp8H(rd, rn).emit(self)
        (S32, true) => Saddlp4S(rd, rn).emit(self) // pairs of i16 -> i32
        (S32, false) => Uaddlp4S(rd, rn).emit(self)
        _ => abort("Unsupported ext add pairwise operation")
      }
    }
    SIMDDot => {
      // i32x4.dot_i16x8_s: multiply i16 pairs and add to get i32
      // result[i] = a[2*i]*b[2*i] + a[2*i+1]*b[2*i+1]
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      // Step 1: SMULL low halves [a0*b0, a1*b1, a2*b2, a3*b3]
      Smull4S(16, rn, rm).emit(self)
      // Step 2: SMULL2 high halves [a4*b4, a5*b5, a6*b6, a7*b7]
      Smull2_4S(17, rn, rm).emit(self)
      // Step 3: ADDP to add adjacent pairs
      // Result: [a0*b0+a1*b1, a2*b2+a3*b3, a4*b4+a5*b5, a6*b6+a7*b7]
      Addp4S(rd, 16, 17).emit(self)
    }
    SIMDQ15MulrSat => {
      // i16x8.q15mulr_sat_s: saturating Q15 rounding multiply
      // result = saturate((a * b + 0x4000) >> 15)
      // SQRDMULH does exactly this
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      Sqrdmulh8H(rd, rn, rm).emit(self)
    }
    SIMDFAdd(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if is_f32 {
        Fadd4S(rd, rn, rm).emit(self)
      } else {
        Fadd2D(rd, rn, rm).emit(self)
      }
    }
    SIMDFSub(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if is_f32 {
        Fsub4S(rd, rn, rm).emit(self)
      } else {
        Fsub2D(rd, rn, rm).emit(self)
      }
    }
    SIMDFMul(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if is_f32 {
        Fmul4S(rd, rn, rm).emit(self)
      } else {
        Fmul2D(rd, rn, rm).emit(self)
      }
    }
    SIMDFDiv(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if is_f32 {
        Fdiv4S(rd, rn, rm).emit(self)
      } else {
        Fdiv2D(rd, rn, rm).emit(self)
      }
    }
    SIMDFMin(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if is_f32 {
        Fmin4S(rd, rn, rm).emit(self)
      } else {
        Fmin2D(rd, rn, rm).emit(self)
      }
    }
    SIMDFMax(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      if is_f32 {
        Fmax4S(rd, rn, rm).emit(self)
      } else {
        Fmax2D(rd, rn, rm).emit(self)
      }
    }
    SIMDFPMin(is_f32) => {
      // pmin: returns min, but with comparison-based selection
      // pmin(a, b) = if a < b then a else b
      // Use FCMGT + BSL: FCMGT Vmask, Va, Vb; BSL Vmask, Vb, Va
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0]) // a
      let rm = reg_num(inst.uses[1]) // b
      // Step 1: FCMGT V16, Vn, Vm (mask = all 1s where a > b)
      if is_f32 {
        Fcmgt4S(16, rn, rm).emit(self)
      } else {
        Fcmgt2D(16, rn, rm).emit(self)
      }
      // Step 2: BSL V16, Vm, Vn (where a > b, use b; else use a)
      Bsl16B(16, rm, rn).emit(self)
      // Step 3: Move result to rd
      if rd != 16 {
        Orr16B(rd, 16, 16).emit(self)
      }
    }
    SIMDFPMax(is_f32) => {
      // pmax: returns max, but with comparison-based selection
      // pmax(a, b) = if b > a then b else a
      // Use FCMGT + BSL: FCMGT Vmask, Vb, Va; BSL Vmask, Vb, Va
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0]) // a
      let rm = reg_num(inst.uses[1]) // b
      // Step 1: FCMGT V16, Vm, Vn (mask = all 1s where b > a)
      if is_f32 {
        Fcmgt4S(16, rm, rn).emit(self)
      } else {
        Fcmgt2D(16, rm, rn).emit(self)
      }
      // Step 2: BSL V16, Vm, Vn (where b > a, use b; else use a)
      Bsl16B(16, rm, rn).emit(self)
      // Step 3: Move result to rd
      if rd != 16 {
        Orr16B(rd, 16, 16).emit(self)
      }
    }
    SIMDFAbs(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if is_f32 {
        Fabs4S(rd, rn).emit(self)
      } else {
        Fabs2D(rd, rn).emit(self)
      }
    }
    SIMDFNeg(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if is_f32 {
        Fneg4S(rd, rn).emit(self)
      } else {
        Fneg2D(rd, rn).emit(self)
      }
    }
    SIMDFSqrt(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if is_f32 {
        Fsqrt4S(rd, rn).emit(self)
      } else {
        Fsqrt2D(rd, rn).emit(self)
      }
    }
    SIMDFCeil(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if is_f32 {
        Frintp4S(rd, rn).emit(self)
      } else {
        Frintp2D(rd, rn).emit(self)
      }
    }
    SIMDFFloor(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if is_f32 {
        Frintm4S(rd, rn).emit(self)
      } else {
        Frintm2D(rd, rn).emit(self)
      }
    }
    SIMDFTrunc(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if is_f32 {
        Frintz4S(rd, rn).emit(self)
      } else {
        Frintz2D(rd, rn).emit(self)
      }
    }
    SIMDFNearest(is_f32) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if is_f32 {
        Frintn4S(rd, rn).emit(self)
      } else {
        Frintn2D(rd, rn).emit(self)
      }
    }
    SIMDFCmp(is_f32, kind) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      match kind {
        Eq =>
          if is_f32 {
            Fcmeq4S(rd, rn, rm).emit(self)
          } else {
            Fcmeq2D(rd, rn, rm).emit(self)
          }
        Gt =>
          if is_f32 {
            Fcmgt4S(rd, rn, rm).emit(self)
          } else {
            Fcmgt2D(rd, rn, rm).emit(self)
          }
        Ge =>
          if is_f32 {
            Fcmge4S(rd, rn, rm).emit(self)
          } else {
            Fcmge2D(rd, rn, rm).emit(self)
          }
      }
    }
    SIMDFCvtToIntS(is_f32) => {
      // FCVTZS: float -> signed int (truncating, saturating)
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if is_f32 {
        Fcvtzs4S(rd, rn).emit(self)
      } else {
        Fcvtzs2D(rd, rn).emit(self)
      }
    }
    SIMDFCvtToIntU(is_f32) => {
      // FCVTZU: float -> unsigned int (truncating, saturating)
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if is_f32 {
        Fcvtzu4S(rd, rn).emit(self)
      } else {
        Fcvtzu2D(rd, rn).emit(self)
      }
    }
    SIMDIntToFloatS(is_f32) => {
      // SCVTF: signed int -> float
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if is_f32 {
        Scvtf4S(rd, rn).emit(self)
      } else {
        Scvtf2D(rd, rn).emit(self)
      }
    }
    SIMDIntToFloatU(is_f32) => {
      // UCVTF: unsigned int -> float
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      if is_f32 {
        Ucvtf4S(rd, rn).emit(self)
      } else {
        Ucvtf2D(rd, rn).emit(self)
      }
    }
    SIMDTruncSatF64ToI32SZero => {
      // f64x2 -> i32x4 with zeros in high lanes (signed)
      // FCVTZS Vtmp.2D, Vn.2D; SQXTN Vd.2S, Vtmp.2D
      let rd = wreg_num(inst.defs[0])
      let tmp = wreg_num(inst.defs[1])
      let rn = reg_num(inst.uses[0])
      Fcvtzs2D(tmp, rn).emit(self) // Convert to i64x2 with saturation to INT64 range
      Sqxtn2S(rd, tmp).emit(self) // Saturating narrow to i32x2 (zeros in high lanes)
    }
    SIMDTruncSatF64ToI32UZero => {
      // f64x2 -> i32x4 with zeros in high lanes (unsigned)
      // FCVTZU Vtmp.2D, Vn.2D; UQXTN Vd.2S, Vtmp.2D
      let rd = wreg_num(inst.defs[0])
      let tmp = wreg_num(inst.defs[1])
      let rn = reg_num(inst.uses[0])
      Fcvtzu2D(tmp, rn).emit(self) // Convert to u64x2 with saturation to UINT64 range
      Uqxtn2S(rd, tmp).emit(self) // Saturating narrow to u32x2 (zeros in high lanes)
    }
    SIMDConvertLowI32ToF64S => {
      // Low 2 i32 lanes -> f64x2 (signed)
      // SXTL Vtmp.2D, Vn.2S; SCVTF Vd.2D, Vtmp.2D
      let rd = wreg_num(inst.defs[0])
      let tmp = wreg_num(inst.defs[1])
      let rn = reg_num(inst.uses[0])
      Sxtl2D(tmp, rn).emit(self) // Sign-extend i32x2 to i64x2
      Scvtf2D(rd, tmp).emit(self) // Convert i64x2 to f64x2
    }
    SIMDConvertLowI32ToF64U => {
      // Low 2 i32 lanes -> f64x2 (unsigned)
      // UXTL Vtmp.2D, Vn.2S; UCVTF Vd.2D, Vtmp.2D
      let rd = wreg_num(inst.defs[0])
      let tmp = wreg_num(inst.defs[1])
      let rn = reg_num(inst.uses[0])
      Uxtl2D(tmp, rn).emit(self) // Zero-extend i32x2 to i64x2
      Ucvtf2D(rd, tmp).emit(self) // Convert i64x2 to f64x2
    }
    SIMDDemoteF64ToF32Zero => {
      // f64x2 -> f32x4 with zeros in high lanes
      // FCVTN Vd.2S, Vn.2D (high 64 bits become zeros)
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      Fcvtn2S(rd, rn).emit(self)
    }
    SIMDPromoteLowF32ToF64 => {
      // Low 2 f32 lanes -> f64x2
      // FCVTL Vd.2D, Vn.2S
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      Fcvtl2D(rd, rn).emit(self)
    }
    SIMDLoad(offset) => {
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      LdrQ(rd, rn, offset).emit(self)
    }
    SIMDStore(offset) => {
      let rt = reg_num(inst.uses[0])
      let rn = reg_num(inst.uses[1])
      StrQ(rt, rn, offset).emit(self)
    }
    SIMDLoadSplat(lane_size, offset) => {
      // Load and replicate to all lanes
      // uses[0] = base address
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      // LD1R doesn't have immediate offset form, compute address if needed
      if offset == 0 {
        match lane_size {
          B8 => Ld1rB(rd, rn).emit(self)
          H16 => Ld1rH(rd, rn).emit(self)
          S32 => Ld1rS(rd, rn).emit(self)
          D64 => Ld1rD(rd, rn).emit(self)
        }
      } else {
        // Use x16 as temp for address calculation
        AddImm(16, rn, offset).emit(self)
        match lane_size {
          B8 => Ld1rB(rd, 16).emit(self)
          H16 => Ld1rH(rd, 16).emit(self)
          S32 => Ld1rS(rd, 16).emit(self)
          D64 => Ld1rD(rd, 16).emit(self)
        }
      }
    }
    SIMDLoadExtend(src_bits, signed, offset) => {
      // Load 64 bits and extend each element
      // uses[0] = base address
      // src_bits: 8 -> i8x8 to i16x8, 16 -> i16x4 to i32x4, 32 -> i32x2 to i64x2
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      // Load 64 bits into low half using LDR D
      LdrDImm(rd, rn, offset).emit(self)
      // Then extend using SXTL/UXTL
      match (src_bits, signed) {
        (8, true) => Sxtl8H(rd, rd).emit(self) // i8x8 -> i16x8 (signed)
        (8, false) => Uxtl8H(rd, rd).emit(self) // i8x8 -> i16x8 (unsigned)
        (16, true) => Sxtl4S(rd, rd).emit(self) // i16x4 -> i32x4 (signed)
        (16, false) => Uxtl4S(rd, rd).emit(self) // i16x4 -> i32x4 (unsigned)
        (32, true) => Sxtl2D(rd, rd).emit(self) // i32x2 -> i64x2 (signed)
        (32, false) => Uxtl2D(rd, rd).emit(self) // i32x2 -> i64x2 (unsigned)
        _ => abort("Invalid src_bits for SIMDLoadExtend")
      }
    }
    SIMDLoadZero(is_64, offset) => {
      // Load 32 or 64 bits to low lane, zero upper bits
      // uses[0] = base address
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      // Scalar float load zeros upper bits
      if is_64 {
        LdrDImm(rd, rn, offset).emit(self)
      } else {
        LdrSImm(rd, rn, offset).emit(self)
      }
    }
    SIMDLoadLane(lane_size, lane, offset) => {
      // Load single element to specific lane
      // uses[0] = base address (GPR)
      // uses[1] = existing vector
      let rd = wreg_num(inst.defs[0])
      let rn = reg_num(inst.uses[0])
      let vec = reg_num(inst.uses[1])
      // Copy existing vector to destination first (LD1 modifies in place)
      if rd != vec {
        Orr16B(rd, vec, vec).emit(self)
      }
      // LD1 doesn't have immediate offset form, compute address if needed
      if offset == 0 {
        match lane_size {
          B8 => Ld1B(rd, rn, lane).emit(self)
          H16 => Ld1H(rd, rn, lane).emit(self)
          S32 => Ld1S(rd, rn, lane).emit(self)
          D64 => Ld1D(rd, rn, lane).emit(self)
        }
      } else {
        // Use x16 as temp for address calculation
        AddImm(16, rn, offset).emit(self)
        match lane_size {
          B8 => Ld1B(rd, 16, lane).emit(self)
          H16 => Ld1H(rd, 16, lane).emit(self)
          S32 => Ld1S(rd, 16, lane).emit(self)
          D64 => Ld1D(rd, 16, lane).emit(self)
        }
      }
    }
    SIMDStoreLane(lane_size, lane, offset) => {
      // Store single element from specific lane
      // uses[0] = base address
      // uses[1] = vector
      let rn = reg_num(inst.uses[0])
      let vec = reg_num(inst.uses[1])
      // ST1 doesn't have immediate offset form, compute address if needed
      if offset == 0 {
        match lane_size {
          B8 => St1B(vec, rn, lane).emit(self)
          H16 => St1H(vec, rn, lane).emit(self)
          S32 => St1S(vec, rn, lane).emit(self)
          D64 => St1D(vec, rn, lane).emit(self)
        }
      } else {
        // Use x16 as temp for address calculation
        AddImm(16, rn, offset).emit(self)
        match lane_size {
          B8 => St1B(vec, 16, lane).emit(self)
          H16 => St1H(vec, 16, lane).emit(self)
          S32 => St1S(vec, 16, lane).emit(self)
          D64 => St1D(vec, 16, lane).emit(self)
        }
      }
    }
    // ============ Relaxed SIMD ============
    SIMDFMla(is_f32) => {
      // FMLA: Vd = Vd + Vn * Vm
      // defs[0] = result
      // uses[0] = accumulator, uses[1] = v1, uses[2] = v2
      let rd = wreg_num(inst.defs[0])
      let acc = reg_num(inst.uses[0])
      let rn = reg_num(inst.uses[1])
      let rm = reg_num(inst.uses[2])
      // This expands to multiple instructions. Copy multiplicands into reserved
      // scratch regs so we can freely overwrite `rd` with the accumulator.
      let a = 16
      let b = 17
      OrrVec(a, rn).emit(self)
      OrrVec(b, rm).emit(self)
      OrrVec(rd, acc).emit(self) // accumulator
      if is_f32 {
        Fmla4S(rd, a, b).emit(self)
      } else {
        Fmla2D(rd, a, b).emit(self)
      }
    }
    SIMDFMls(is_f32) => {
      // FMLS: Vd = Vd - Vn * Vm
      // defs[0] = result
      // uses[0] = accumulator, uses[1] = v1, uses[2] = v2
      let rd = wreg_num(inst.defs[0])
      let acc = reg_num(inst.uses[0])
      let rn = reg_num(inst.uses[1])
      let rm = reg_num(inst.uses[2])
      let a = 16
      let b = 17
      OrrVec(a, rn).emit(self)
      OrrVec(b, rm).emit(self)
      OrrVec(rd, acc).emit(self) // accumulator
      if is_f32 {
        Fmls4S(rd, a, b).emit(self)
      } else {
        Fmls2D(rd, a, b).emit(self)
      }
    }
    SIMDRelaxedDot8to16 => {
      // i16x8.relaxed_dot_i8x16_i7x16_s: dot product of i8x16 vectors to i16x8
      // result[i] = a[2*i]*b[2*i] + a[2*i+1]*b[2*i+1]
      // uses[0] = v1 (i8x16), uses[1] = v2 (i8x16)
      let rd = wreg_num(inst.defs[0])
      let tmp = wreg_num(inst.defs[1])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      // Multi-instruction expansion: copy inputs into reserved scratch regs so
      // `rd` may alias an input without clobbering it before the second SMULL.
      let a = 16
      let b = 17
      OrrVec(a, rn).emit(self)
      OrrVec(b, rm).emit(self)
      // Step 1: SMULL for lower 8 bytes - products for bytes 0-7
      Smull8H(rd, a, b).emit(self)
      // Step 2: SMULL2 for upper 8 bytes - products for bytes 8-15
      Smull2_8H(tmp, a, b).emit(self)
      // Step 3: ADDP pairwise add to get final dot products
      // Result: [a0*b0+a1*b1, a2*b2+a3*b3, ..., a14*b14+a15*b15]
      Addp8H(rd, rd, tmp).emit(self)
    }
    SIMDRelaxedDot8to32Add => {
      // i32x4.relaxed_dot_i8x16_i7x16_add_s: dot product + accumulator
      // result[i] = c[i] + sum(a[4*i+k]*b[4*i+k], k=0..3)
      // uses[0] = v1, uses[1] = v2, uses[2] = accumulator
      let rd = wreg_num(inst.defs[0])
      let tmp = wreg_num(inst.defs[1])
      let rn = reg_num(inst.uses[0])
      let rm = reg_num(inst.uses[1])
      let acc = reg_num(inst.uses[2])
      // Multi-instruction expansion. Protect operands that must remain available
      // after `rd`/`tmp` are overwritten by using reserved scratch regs V16/V17.
      let mut a = rn
      let mut b = rm
      let mut acc_reg = acc
      if acc_reg == rd || acc_reg == tmp {
        OrrVec(16, acc_reg).emit(self)
        acc_reg = 16
      }
      // `rn`/`rm` are used in both SMULL and SMULL2. If `rd` aliases one of them,
      // the first SMULL would clobber the input before SMULL2.
      if rd == a {
        OrrVec(17, a).emit(self)
        a = 17
      }
      if rd == b && b != a {
        OrrVec(17, b).emit(self)
        b = 17
      }
      // Step 1: SMULL for lower 8 bytes
      Smull8H(rd, a, b).emit(self)
      // Step 2: SMULL2 for upper 8 bytes
      Smull2_8H(tmp, a, b).emit(self)
      // Step 3: ADDP pairwise to get i16x8 dot products
      Addp8H(rd, rd, tmp).emit(self)
      // Step 4: SADDLP to get i32x4 from i16x8 (another pairwise add with widening)
      Saddlp4S(rd, rd).emit(self)
      // Step 5: Add accumulator
      Add4S(rd, rd, acc_reg).emit(self)
    }
    _ => abort("non-SIMD opcode routed to emit_instruction_simd")
  }
}
