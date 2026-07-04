///|
fn hex_digit(n : Int) -> String {
  let d = n & 0xF
  if d < 10 {
    (48 + d).unsafe_to_char().to_string()
  } else {
    (87 + d).unsafe_to_char().to_string()
  }
}

///|
fn hex_byte(n : Int) -> String {
  hex_digit((n >> 4) & 0xF) + hex_digit(n & 0xF)
}

///|
fn int_to_hex(n : Int) -> String {
  if n == 0 {
    "0"
  } else {
    let digits : Array[String] = []
    let mut value = n
    while value > 0 {
      digits.push(hex_digit(value & 0xF))
      value = value >> 4
    }
    digits.rev_in_place()
    digits.join("")
  }
}

///|
fn hex_offset(n : Int, width : Int) -> String {
  let hex = int_to_hex(n)
  if hex.length() >= width {
    hex
  } else {
    "0".repeat(width - hex.length()) + hex
  }
}

///|
fn disasm_width(code_size : Int) -> Int {
  let max_offset = if code_size > 0 { code_size - 1 } else { 0 }
  if max_offset <= 0xFFFF {
    4
  } else if max_offset <= 0xFFFFFF {
    6
  } else {
    8
  }
}

///|
pub fn format_disassembly(
  code : Array[Int],
  label_offsets : Array[(Int, Int)],
  annotations : Array[(Int, String)],
) -> String {
  let label_map : Map[Int, Array[Int]] = {}
  for entry in label_offsets {
    let (block_id, offset) = entry
    match label_map.get(offset) {
      Some(ids) => ids.push(block_id)
      None => label_map.set(offset, [block_id])
    }
  }
  let width = disasm_width(code.length())
  let sorted = annotations.copy()
  sorted.sort_by(fn(a, b) { a.0.compare(b.0) })
  let mut result = ""
  for entry in sorted {
    let (offset, text) = entry
    if label_map.get(offset) is Some(block_ids) {
      for block_id in block_ids {
        result = result + "block\{block_id}:\n"
      }
    }
    let b0 = if offset < code.length() { code[offset] } else { 0 }
    let b1 = if offset + 1 < code.length() { code[offset + 1] } else { 0 }
    let b2 = if offset + 2 < code.length() { code[offset + 2] } else { 0 }
    let b3 = if offset + 3 < code.length() { code[offset + 3] } else { 0 }
    let hex = hex_byte(b0) + hex_byte(b1) + hex_byte(b2) + hex_byte(b3)
    result = result + "  \{hex_offset(offset, width)}: \{hex}  \{text}\n"
  }
  result
}
