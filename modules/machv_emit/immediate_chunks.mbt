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
