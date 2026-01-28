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
  ContextGet(@types.ValueType, Int) // valtype, context index
  ContextSet(@types.ValueType, Int) // valtype, context index
  TaskReturn(ValType?, Array[CanonOpt]) // result, opts
  TaskCancel
  ThreadIndex
  ThreadYield(Bool) // cancellable?
  ThreadYieldTo(Bool) // cancellable?
  ThreadSwitchTo(Bool) // cancellable?
  ThreadResumeLater
  ThreadSuspend(Bool) // cancellable?
  ThreadNewIndirect(Int, Int) // core functype index, core table index
  WaitableSetNew
  WaitableSetWait(Bool, Int) // cancellable?, core memidx
  WaitableSetPoll(Bool, Int) // cancellable?, core memidx
  WaitableSetDrop
  WaitableJoin
  SubtaskCancel(Bool)
  SubtaskDrop
  StreamNew(Int) // stream typeidx
  StreamRead(Int, Array[CanonOpt]) // stream typeidx, opts
  StreamWrite(Int, Array[CanonOpt]) // stream typeidx, opts
  StreamCancelRead(Int, Bool) // stream typeidx, async?
  StreamCancelWrite(Int, Bool) // stream typeidx, async?
  StreamDropReadable(Int) // stream typeidx
  StreamDropWritable(Int) // stream typeidx
  FutureNew(Int) // future typeidx
  FutureRead(Int, Array[CanonOpt]) // future typeidx, opts
  FutureWrite(Int, Array[CanonOpt]) // future typeidx, opts
  FutureCancelRead(Int, Bool) // future typeidx, async?
  FutureCancelWrite(Int, Bool) // future typeidx, async?
  FutureDropReadable(Int) // future typeidx
  FutureDropWritable(Int) // future typeidx
  ResourceNew(Int) // typeidx
  ResourceDrop(Int) // typeidx
  ResourceRep(Int) // typeidx
} derive(Show, Eq)

///|
fn parse_context_core_valtype(
  reader : Reader,
) -> @types.ValueType raise ComponentParseError {
  let b = reader.read_u8()
  match b {
    0x7f => @types.ValueType::I32
    0x7e => @types.ValueType::I64
    0x7d => @types.ValueType::F32
    0x7c => @types.ValueType::F64
    0x7b => @types.ValueType::V128
    0x70 => @types.ValueType::FuncRef
    0x6f => @types.ValueType::ExternRef
    _ => raise InvalidCanonSection
  }
}

///|
fn parse_prim_valtype_from_sleb(v : Int) -> PrimValType? {
  match v {
    -1 => Some(Bool)
    -2 => Some(S8)
    -3 => Some(U8)
    -4 => Some(S16)
    -5 => Some(U16)
    -6 => Some(S32)
    -7 => Some(U32)
    -8 => Some(S64)
    -9 => Some(U64)
    -10 => Some(F32)
    -11 => Some(F64)
    -12 => Some(Char)
    -13 => Some(String)
    -28 => Some(ErrorContext)
    _ => None
  }
}

///|
fn parse_canon_valtype(reader : Reader) -> ValType raise ComponentParseError {
  let v = reader.read_sleb_i32()
  if v >= 0 {
    TypeIdx(v)
  } else {
    match parse_prim_valtype_from_sleb(v) {
      Some(p) => Prim(p)
      None => raise InvalidCanonSection
    }
  }
}

///|
fn parse_canon_resultlist(
  reader : Reader,
) -> ValType? raise ComponentParseError {
  let tag = reader.read_u8()
  if tag == 0x00 {
    Some(parse_canon_valtype(reader))
  } else if tag == 0x01 {
    let must_be_zero = reader.read_u8()
    if must_be_zero != 0x00 {
      raise InvalidCanonSection
    }
    None
  } else {
    raise InvalidCanonSection
  }
}

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
    0x05 => Canon::TaskCancel
    0x06 => {
      let async_flag = reader.read_u8()
      if async_flag != 0x00 && async_flag != 0x01 {
        raise InvalidCanonSection
      }
      Canon::SubtaskCancel(async_flag == 0x01)
    }
    0x02 => Canon::ResourceNew(reader.read_typeidx())
    0x03 => Canon::ResourceDrop(reader.read_typeidx())
    0x04 => Canon::ResourceRep(reader.read_typeidx())
    0x0a => {
      let vt = parse_context_core_valtype(reader)
      let idx = reader.read_leb_u32()
      Canon::ContextGet(vt, idx)
    }
    0x0b => {
      let vt = parse_context_core_valtype(reader)
      let idx = reader.read_leb_u32()
      Canon::ContextSet(vt, idx)
    }
    0x09 => {
      let result = parse_canon_resultlist(reader)
      let opts = parse_opts(reader)
      Canon::TaskReturn(result, opts)
    }
    0x0c => {
      let flag = reader.read_u8()
      if flag != 0x00 && flag != 0x01 {
        raise InvalidCanonSection
      }
      Canon::ThreadYield(flag == 0x01)
    }
    0x26 => Canon::ThreadIndex
    0x27 => {
      let ty = reader.read_leb_u32()
      let table = reader.read_leb_u32()
      Canon::ThreadNewIndirect(ty, table)
    }
    0x28 => {
      let flag = reader.read_u8()
      if flag != 0x00 && flag != 0x01 {
        raise InvalidCanonSection
      }
      Canon::ThreadSwitchTo(flag == 0x01)
    }
    0x29 => {
      let flag = reader.read_u8()
      if flag != 0x00 && flag != 0x01 {
        raise InvalidCanonSection
      }
      Canon::ThreadSuspend(flag == 0x01)
    }
    0x2a => Canon::ThreadResumeLater
    0x2b => {
      let flag = reader.read_u8()
      if flag != 0x00 && flag != 0x01 {
        raise InvalidCanonSection
      }
      Canon::ThreadYieldTo(flag == 0x01)
    }
    0x0d => Canon::SubtaskDrop
    0x0e => Canon::StreamNew(reader.read_typeidx())
    0x0f => {
      let ty = reader.read_typeidx()
      let opts = parse_opts(reader)
      Canon::StreamRead(ty, opts)
    }
    0x10 => {
      let ty = reader.read_typeidx()
      let opts = parse_opts(reader)
      Canon::StreamWrite(ty, opts)
    }
    0x11 => {
      let ty = reader.read_typeidx()
      let async_flag = reader.read_u8()
      if async_flag != 0x00 && async_flag != 0x01 {
        raise InvalidCanonSection
      }
      Canon::StreamCancelRead(ty, async_flag == 0x01)
    }
    0x12 => {
      let ty = reader.read_typeidx()
      let async_flag = reader.read_u8()
      if async_flag != 0x00 && async_flag != 0x01 {
        raise InvalidCanonSection
      }
      Canon::StreamCancelWrite(ty, async_flag == 0x01)
    }
    0x13 => Canon::StreamDropReadable(reader.read_typeidx())
    0x14 => Canon::StreamDropWritable(reader.read_typeidx())
    0x15 => Canon::FutureNew(reader.read_typeidx())
    0x16 => {
      let ty = reader.read_typeidx()
      let opts = parse_opts(reader)
      Canon::FutureRead(ty, opts)
    }
    0x17 => {
      let ty = reader.read_typeidx()
      let opts = parse_opts(reader)
      Canon::FutureWrite(ty, opts)
    }
    0x18 => {
      let ty = reader.read_typeidx()
      let async_flag = reader.read_u8()
      if async_flag != 0x00 && async_flag != 0x01 {
        raise InvalidCanonSection
      }
      Canon::FutureCancelRead(ty, async_flag == 0x01)
    }
    0x19 => {
      let ty = reader.read_typeidx()
      let async_flag = reader.read_u8()
      if async_flag != 0x00 && async_flag != 0x01 {
        raise InvalidCanonSection
      }
      Canon::FutureCancelWrite(ty, async_flag == 0x01)
    }
    0x1a => Canon::FutureDropReadable(reader.read_typeidx())
    0x1b => Canon::FutureDropWritable(reader.read_typeidx())
    0x1f => Canon::WaitableSetNew
    0x20 => {
      let flag = reader.read_u8()
      if flag != 0x00 && flag != 0x01 {
        raise InvalidCanonSection
      }
      Canon::WaitableSetWait(flag == 0x01, reader.read_leb_u32())
    }
    0x21 => {
      let flag = reader.read_u8()
      if flag != 0x00 && flag != 0x01 {
        raise InvalidCanonSection
      }
      Canon::WaitableSetPoll(flag == 0x01, reader.read_leb_u32())
    }
    0x22 => Canon::WaitableSetDrop
    0x23 => Canon::WaitableJoin
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
