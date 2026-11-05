///|
fn[R, E : Error] read_unsigned(
  reader : R,
  read_byte : (R) -> Int32 raise E,
  overflow : () -> E,
  bits : Int32,
) -> Int64 raise E {
  for result = 0L, shift = 0 {
    let byte = read_byte(reader)
    let payload = (byte & 0x7F).to_int64()
    let remaining = bits - shift
    if remaining <= 7 && ((byte & 0x80) != 0 || payload >> remaining != 0L) {
      raise overflow()
    }
    let value = result | (payload << shift)
    if (byte & 0x80) == 0 {
      break value
    }
    continue value, shift + 7
  }
}

///|
fn[R, E : Error] read_signed(
  reader : R,
  read_byte : (R) -> Int32 raise E,
  overflow : () -> E,
  bits : Int32,
) -> Int64 raise E {
  for result = 0L, shift = 0 {
    let byte = read_byte(reader)
    let payload = byte & 0x7F
    let remaining = bits - shift
    if remaining <= 7 {
      let sign = 1 << (remaining - 1)
      let high = 0x7F & (-1 << remaining)
      let expected = if (payload & sign) == 0 { 0 } else { high }
      if (byte & 0x80) != 0 || (payload & high) != expected {
        raise overflow()
      }
    }
    let value = result | (payload.to_int64() << shift)
    let next = shift + 7
    if (byte & 0x80) == 0 {
      if next < 64 && (byte & 0x40) != 0 {
        break value | (-1L << next)
      }
      break value
    }
    continue value, next
  }
}

///|
pub fn[R, E : Error] read_u32(
  reader : R,
  read_byte : (R) -> Int32 raise E,
  overflow : () -> E,
) -> Int32 raise E {
  read_unsigned(reader, read_byte, overflow, 32).to_int()
}

///|
pub fn[R, E : Error] read_u64(
  reader : R,
  read_byte : (R) -> Int32 raise E,
  overflow : () -> E,
) -> Int64 raise E {
  read_unsigned(reader, read_byte, overflow, 64)
}

///|
pub fn[R, E : Error] read_s32(
  reader : R,
  read_byte : (R) -> Int32 raise E,
  overflow : () -> E,
) -> Int32 raise E {
  read_signed(reader, read_byte, overflow, 32).to_int()
}

///|
pub fn[R, E : Error] read_s33(
  reader : R,
  read_byte : (R) -> Int32 raise E,
  overflow : () -> E,
) -> Int64 raise E {
  read_signed(reader, read_byte, overflow, 33)
}

///|
pub fn[R, E : Error] read_s64(
  reader : R,
  read_byte : (R) -> Int32 raise E,
  overflow : () -> E,
) -> Int64 raise E {
  read_signed(reader, read_byte, overflow, 64)
}
