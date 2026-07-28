///|
/// Local reader and core-type skipping helpers used by runtime instantiation.

///|
priv struct Reader {
  data : Bytes
  mut pos : Int
}

///|
fn Reader::Reader(data : Bytes) -> Reader {
  { data, pos: 0 }
}

///|
fn Reader::is_eof(self : Reader) -> Bool {
  self.pos >= self.data.length()
}

///|
fn Reader::read_u8(self : Reader) -> Int raise ComponentRuntimeError {
  if self.pos >= self.data.length() {
    raise ComponentParseError("unexpected end of input")
  }
  let b = self.data[self.pos].to_int()
  self.pos += 1
  b
}

///|
fn Reader::read_bytes(
  self : Reader,
  n : Int,
) -> Bytes raise ComponentRuntimeError {
  if self.pos + n > self.data.length() {
    raise ComponentParseError("unexpected end of input")
  }
  let bytes : Array[Byte] = []
  for i in 0..<n {
    bytes.push(self.data[self.pos + i])
  }
  self.pos += n
  Bytes::from_array(bytes)
}

///|
fn decode_utf8_validated(bytes : Bytes) -> String raise ComponentRuntimeError {
  let buf = StringBuilder::StringBuilder()
  let mut i = 0
  while i < bytes.length() {
    let b = bytes[i].to_int()
    if b < 0x80 {
      buf.write_char(b.unsafe_to_char())
      i = i + 1
    } else if b < 0xC0 {
      raise ComponentParseError("invalid utf-8")
    } else if b < 0xE0 {
      if i + 1 >= bytes.length() {
        raise ComponentParseError("invalid utf-8")
      }
      let b2 = bytes[i + 1].to_int()
      if (b2 & 0xC0) != 0x80 {
        raise ComponentParseError("invalid utf-8")
      }
      let cp = ((b & 0x1F) << 6) | (b2 & 0x3F)
      if cp < 0x80 {
        raise ComponentParseError("invalid utf-8")
      }
      buf.write_char(cp.unsafe_to_char())
      i = i + 2
    } else if b < 0xF0 {
      if i + 2 >= bytes.length() {
        raise ComponentParseError("invalid utf-8")
      }
      let b2 = bytes[i + 1].to_int()
      let b3 = bytes[i + 2].to_int()
      if (b2 & 0xC0) != 0x80 || (b3 & 0xC0) != 0x80 {
        raise ComponentParseError("invalid utf-8")
      }
      let cp = ((b & 0x0F) << 12) | ((b2 & 0x3F) << 6) | (b3 & 0x3F)
      if cp < 0x800 || (cp >= 0xD800 && cp <= 0xDFFF) {
        raise ComponentParseError("invalid utf-8")
      }
      buf.write_char(cp.unsafe_to_char())
      i = i + 3
    } else if b < 0xF8 {
      if i + 3 >= bytes.length() {
        raise ComponentParseError("invalid utf-8")
      }
      let b2 = bytes[i + 1].to_int()
      let b3 = bytes[i + 2].to_int()
      let b4 = bytes[i + 3].to_int()
      if (b2 & 0xC0) != 0x80 || (b3 & 0xC0) != 0x80 || (b4 & 0xC0) != 0x80 {
        raise ComponentParseError("invalid utf-8")
      }
      let cp = ((b & 0x07) << 18) |
        ((b2 & 0x3F) << 12) |
        ((b3 & 0x3F) << 6) |
        (b4 & 0x3F)
      if cp < 0x10000 || cp > 0x10FFFF {
        raise ComponentParseError("invalid utf-8")
      }
      buf.write_char(cp.unsafe_to_char())
      i = i + 4
    } else {
      raise ComponentParseError("invalid utf-8")
    }
  }
  buf.to_string()
}

///|
fn Reader::read_name(self : Reader) -> String raise ComponentRuntimeError {
  let len = self.read_leb_u32()
  let bytes = self.read_bytes(len)
  decode_utf8_validated(bytes)
}

///|
fn Reader::read_label(self : Reader) -> String raise ComponentRuntimeError {
  self.read_name()
}

///|
fn Reader::read_leb_u32(self : Reader) -> Int raise ComponentRuntimeError {
  for result = 0, shift = 0 {
    if shift > 28 {
      raise ComponentParseError("invalid leb128")
    }
    let byte = self.read_u8()
    if shift == 28 && (byte & 0x7F) > 0x0F {
      raise ComponentParseError("invalid leb128")
    }
    let new_result = result | ((byte & 0x7F) << shift)
    if (byte & 0x80) == 0 {
      break new_result
    } else {
      continue new_result, shift + 7
    }
  }
}

///|
fn skip_limits(reader : Reader) -> Unit raise ComponentRuntimeError {
  let flags = reader.read_u8()
  reader.read_leb_u32() |> ignore
  if (flags & 0x01) != 0 {
    reader.read_leb_u32() |> ignore
  }
}

///|
fn skip_core_functype_inline(
  reader : Reader,
) -> Unit raise ComponentRuntimeError {
  let form = reader.read_u8()
  if form != 0x60 {
    raise ComponentParseError("invalid core type section")
  }
  skip_core_functype_body(reader)
}

///|
fn skip_core_functype_body(reader : Reader) -> Unit raise ComponentRuntimeError {
  let nparams = reader.read_leb_u32()
  for _i in 0..<nparams {
    reader.read_u8() |> ignore
  }
  let nresults = reader.read_leb_u32()
  for _i in 0..<nresults {
    reader.read_u8() |> ignore
  }
}

///|
fn skip_core_extern_type(
  reader : Reader,
  kind : Int,
) -> Unit raise ComponentRuntimeError {
  match kind {
    0x00 => reader.read_leb_u32() |> ignore
    0x01 => {
      reader.read_u8() |> ignore
      skip_limits(reader)
    }
    0x02 => skip_limits(reader)
    0x03 => {
      reader.read_u8() |> ignore
      reader.read_u8() |> ignore
    }
    0x04 => reader.read_leb_u32() |> ignore
    _ => raise ComponentParseError("invalid core type section")
  }
}

///|
fn skip_core_moduletype(reader : Reader) -> Unit raise ComponentRuntimeError {
  let ndecls = reader.read_leb_u32()
  for _i in 0..<ndecls {
    let tag = reader.read_u8()
    match tag {
      0x00 => {
        reader.read_label() |> ignore
        reader.read_label() |> ignore
        let kind = reader.read_u8()
        skip_core_extern_type(reader, kind)
      }
      0x01 => skip_core_functype_inline(reader)
      0x02 => {
        reader.read_u8() |> ignore
        let target = reader.read_u8()
        if target == 0x01 {
          reader.read_leb_u32() |> ignore
          reader.read_leb_u32() |> ignore
        } else {
          raise ComponentParseError("invalid core type section")
        }
      }
      0x03 => {
        reader.read_label() |> ignore
        let kind = reader.read_u8()
        skip_core_extern_type(reader, kind)
      }
      _ => raise ComponentParseError("invalid core type section")
    }
  }
}

///|
fn skip_core_typedef(reader : Reader) -> Unit raise ComponentRuntimeError {
  let op = reader.read_u8()
  if op == 0x50 {
    skip_core_moduletype(reader)
  } else if op == 0x60 {
    skip_core_functype_body(reader)
  } else if op == 0x00 {
    if reader.read_u8() != 0x50 {
      raise ComponentParseError("invalid core type section")
    }
    let supertype_count = reader.read_leb_u32()
    for _ in 0..<supertype_count {
      reader.read_leb_u32() |> ignore
    }
    if reader.read_u8() != 0x60 {
      raise ComponentParseError("invalid core type section")
    }
    skip_core_functype_body(reader)
  } else {
    raise ComponentParseError("invalid core type section")
  }
}
