///|
/// Parsing for canonical section (8) and start section (9).

///|
pub(all) enum StringEncoding {
  Utf8
  Utf16
  Latin1Utf16
} derive(Show, Eq)

///|
pub(all) enum CanonOpt {
  StringEncoding(StringEncoding)
  Memory(Int)
  Realloc(Int)
  PostReturn(Int)
  Async
  Callback(Int)
} derive(Show, Eq)

///|
pub(all) enum Canon {
  Lift(Int, Array[CanonOpt], Int) // core funcidx, opts, typeidx
  Lower(Int, Array[CanonOpt]) // funcidx, opts
  ResourceNew(Int) // typeidx
  ResourceDrop(Int) // typeidx
  ResourceRep(Int) // typeidx
} derive(Show, Eq)

///|
fn parse_opts(reader : Reader) -> Array[CanonOpt] raise ComponentParseError {
  let n = reader.read_leb_u32()
  let opts = loop ([], 0) {
    (acc, i) =>
      if i >= n {
        acc
      } else {
        let tag = reader.read_u8()
        let opt = match tag {
          0x00 => CanonOpt::StringEncoding(Utf8)
          0x01 => CanonOpt::StringEncoding(Utf16)
          0x02 => CanonOpt::StringEncoding(Latin1Utf16)
          0x03 => CanonOpt::Memory(reader.read_leb_u32())
          0x04 => CanonOpt::Realloc(reader.read_leb_u32())
          0x05 => CanonOpt::PostReturn(reader.read_leb_u32())
          0x06 => CanonOpt::Async
          0x07 => CanonOpt::Callback(reader.read_leb_u32())
          _ => raise InvalidCanonSection
        }
        acc.push(opt)
        continue (acc, i + 1)
      }
  }
  opts
}

///|
fn parse_canon(reader : Reader) -> Canon raise ComponentParseError {
  let tag = reader.read_u8()
  match tag {
    0x00 => {
      // 0x00 0x00 f:<core:funcidx> opts:<opts> ft:<typeidx>
      let must_be_func = reader.read_u8()
      if must_be_func != 0x00 {
        raise InvalidCanonSection
      }
      let core_func = reader.read_leb_u32()
      let opts = parse_opts(reader)
      let ft = reader.read_typeidx()
      Canon::Lift(core_func, opts, ft)
    }
    0x01 => {
      // 0x01 0x00 f:<funcidx> opts:<opts>
      let must_be_func = reader.read_u8()
      if must_be_func != 0x00 {
        raise InvalidCanonSection
      }
      let func = reader.read_leb_u32()
      let opts = parse_opts(reader)
      Canon::Lower(func, opts)
    }
    0x02 => Canon::ResourceNew(reader.read_typeidx())
    0x03 => Canon::ResourceDrop(reader.read_typeidx())
    0x04 => Canon::ResourceRep(reader.read_typeidx())
    _ => raise UnsupportedCanonOpcode(tag)
  }
}

///|
pub fn parse_canon_section(
  payload : Bytes,
) -> Array[Canon] raise ComponentParseError {
  let reader = Reader::new(payload)
  let n = reader.read_leb_u32()
  let canons = loop ([], 0) {
    (acc, i) =>
      if i >= n {
        acc
      } else {
        acc.push(parse_canon(reader))
        continue (acc, i + 1)
      }
  }
  if !reader.is_eof() {
    raise InvalidCanonSection
  }
  canons
}

///|
pub(all) struct Start {
  func_idx : Int
  args : Array[Int]
  results : Int
} derive(Show, Eq)

///|
pub fn parse_start_section(payload : Bytes) -> Start raise ComponentParseError {
  let reader = Reader::new(payload)
  let func_idx = reader.read_leb_u32()
  let n = reader.read_leb_u32()
  let args = loop ([], 0) {
    (acc, i) =>
      if i >= n {
        acc
      } else {
        acc.push(reader.read_leb_u32())
        continue (acc, i + 1)
      }
  }
  let results = reader.read_leb_u32()
  if !reader.is_eof() {
    raise InvalidStartSection
  }
  { func_idx, args, results }
}
