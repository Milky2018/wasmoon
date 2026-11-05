///|
/// A buffer for WebAssembly Core and Component binary formats.
#valtype
pub struct Writer {
  priv buffer : @buffer.Buffer
}

///|
pub fn Writer::Writer() -> Writer {
  { buffer: Buffer(), }
}

///|
pub fn Writer::write_byte(self : Writer, value : Int32) -> Unit {
  self.buffer.write_byte(value.to_byte())
}

///|
pub fn Writer::write_bytes(self : Writer, bytes : BytesView) -> Unit {
  self.buffer.write_bytes(bytes)
}

///|
pub fn Writer::write_buffer(self : Writer, payload : Writer) -> Unit {
  for byte in payload.buffer.view() {
    self.buffer.write_byte(byte)
  }
}

///|
pub fn Writer::write_u32(self : Writer, value : Int32) -> Unit {
  self.buffer.write_leb128(value.reinterpret_as_uint())
}

///|
pub fn Writer::write_u64(self : Writer, value : Int64) -> Unit {
  self.buffer.write_leb128(value.reinterpret_as_uint64())
}

///|
pub fn Writer::write_s32(self : Writer, value : Int32) -> Unit {
  self.buffer.write_leb128(value)
}

///|
pub fn Writer::write_s64(self : Writer, value : Int64) -> Unit {
  self.buffer.write_leb128(value)
}

///|
pub fn Writer::write_f32(self : Writer, value : Float) -> Unit {
  self.buffer.write_float_le(value)
}

///|
pub fn Writer::write_f64(self : Writer, value : Double) -> Unit {
  self.buffer.write_double_le(value)
}

///|
/// Write the byte length followed by the UTF-8 name.
pub fn Writer::write_name(self : Writer, name : String) -> Unit {
  let payload = @buffer.Buffer(size_hint=name.length())
  for char in name {
    let code = char.to_int()
    payload.write_char_utf8(
      if 0xD800 <= code && code <= 0xDFFF {
        '\u{fffd}'
      } else {
        char
      },
    )
  }
  self.write_u32(payload.length())
  for byte in payload.view() {
    self.buffer.write_byte(byte)
  }
}

///|
pub fn Writer::length(self : Writer) -> Int32 {
  self.buffer.length()
}

///|
pub fn Writer::to_bytes(self : Writer) -> Bytes {
  self.buffer.to_bytes()
}
