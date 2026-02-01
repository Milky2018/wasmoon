// ============================================================
// LEB128 Decoding
// ============================================================

///|
/// Decode unsigned LEB128
fn Parser::read_leb128_u32(self : Parser) -> Int raise ParserError {
  loop (0, 0) {
    (result, shift) => {
      if shift > 28 {
        raise LEB128TooLarge
      }
      let byte = self.read_byte()
      // For the 5th byte (shift=28), only lower 4 bits can be used for u32
      // If the value is >= 16 (0x10), it would overflow u32
      if shift == 28 && (byte & 0x7F) > 0x0F {
        raise LEB128TooLarge
      }
      let new_result = result | ((byte & 0x7F) << shift)
      if (byte & 0x80) == 0 {
        new_result
      } else {
        continue (new_result, shift + 7)
      }
    }
  }
}

///|
/// Decode signed LEB128
fn Parser::read_leb128_i32(self : Parser) -> Int raise ParserError {
  loop (0, 0) {
    (result, shift) => {
      if shift > 28 {
        raise LEB128TooLarge
      }
      let byte = self.read_byte()
      // For the 5th byte (shift=28), validate sign extension
      // Bits 4-6 must be sign-extended from bit 3
      if shift == 28 {
        let sign_bit = (byte & 0x08) != 0 // bit 3 is sign
        let upper_bits = byte & 0x70 // bits 4-6 must be sign-extended
        if sign_bit {
          // Negative: bits 4-6 must all be 1 (0x70)
          if upper_bits != 0x70 {
            raise LEB128TooLarge
          }
          // Non-negative: bits 4-6 must all be 0 (0x00)
        } else if upper_bits != 0x00 {
          raise LEB128TooLarge
        }
        // Also, 5th byte cannot have continuation bit
        if (byte & 0x80) != 0 {
          raise LEB128TooLarge
        }
      }
      let new_result = result | ((byte & 0x7F) << shift)
      let new_shift = shift + 7
      if (byte & 0x80) == 0 {
        // Sign extend if needed
        if new_shift < 32 && (byte & 0x40) != 0 {
          new_result | (-1 << new_shift)
        } else {
          new_result
        }
      } else {
        continue (new_result, new_shift)
      }
    }
  }
}

///|
/// Decode signed LEB128 i64
fn Parser::read_leb128_i64(self : Parser) -> Int64 raise ParserError {
  loop (0L, 0) {
    (result, shift) => {
      if shift > 63 {
        raise LEB128TooLarge
      }
      let byte = self.read_byte()
      // For the 10th byte (shift=63), validate sign extension
      // Only bit 0 is used for value (bit 63), bits 1-6 must be sign-extended from bit 0
      if shift == 63 {
        let sign_bit = (byte & 0x01) != 0 // bit 0 is sign (bit 63 of i64)
        let upper_bits = byte & 0x7E // bits 1-6 must be sign-extended
        if sign_bit {
          // Negative: bits 1-6 must all be 1 (0x7E)
          if upper_bits != 0x7E {
            raise LEB128TooLarge
          }
          // Non-negative: bits 1-6 must all be 0 (0x00)
        } else if upper_bits != 0x00 {
          raise LEB128TooLarge
        }
        // Also, 10th byte cannot have continuation bit
        if (byte & 0x80) != 0 {
          raise LEB128TooLarge
        }
      }
      let new_result = result | (byte.land(0x7F).to_int64() << shift)
      let new_shift = shift + 7
      if (byte & 0x80) == 0 {
        // Sign extend if needed
        if new_shift < 64 && (byte & 0x40) != 0 {
          new_result | (-1L << new_shift)
        } else {
          new_result
        }
      } else {
        continue (new_result, new_shift)
      }
    }
  }
}

///|
/// Decode unsigned LEB128 u64
fn Parser::read_leb128_u64(self : Parser) -> Int64 raise ParserError {
  loop (0L, 0) {
    (result, shift) => {
      if shift > 63 {
        raise LEB128TooLarge
      }
      let byte = self.read_byte()
      // For the 10th byte (shift=63), only bit 0 can be used for u64
      // If any other bit is set, it would overflow u64
      if shift == 63 && (byte & 0x7E) != 0 {
        raise LEB128TooLarge
      }
      let new_result = result | (byte.land(0x7F).to_int64() << shift)
      if (byte & 0x80) == 0 {
        new_result
      } else {
        continue (new_result, shift + 7)
      }
    }
  }
}
