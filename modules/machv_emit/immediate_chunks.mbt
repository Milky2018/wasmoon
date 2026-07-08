///|
pub fn plan_signed_i8_chunks(value : Int) -> Array[Int] {
  let chunks : Array[Int] = []
  let mut remaining = value
  while remaining > 127 {
    chunks.push(127)
    remaining = remaining - 127
  }
  while remaining < -128 {
    chunks.push(-128)
    remaining = remaining + 128
  }
  if remaining != 0 {
    chunks.push(remaining)
  }
  chunks
}

///|
pub fn fits_signed_i8(value : Int) -> Bool {
  value >= -128 && value <= 127
}

///|
pub fn fits_signed_i32(value : Int) -> Bool {
  value >= -2147483648 && value <= 2147483647
}
