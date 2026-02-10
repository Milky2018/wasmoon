// ============================================================
// Recursive Group Type Parsing (WasmGC)
// ============================================================

///|
fn Parser::read_field_type(self : Parser) -> @types.FieldType raise ParserError {
  let storage_type : @types.StorageType = match self.peek_byte() {
    0x78 => {
      self.skip(1)
      @types.StorageType::Packed(@types.PackedType::I8)
    }
    0x77 => {
      self.skip(1)
      @types.StorageType::Packed(@types.PackedType::I16)
    }
    _ => @types.StorageType::Val(self.read_value_type())
  }
  let mutability = self.read_byte()
  if mutability != 0x00 && mutability != 0x01 {
    raise MalformedMutability(mutability)
  }
  { storage_type, mutable: mutability == 0x01 }
}

///|
fn Parser::read_struct_type(
  self : Parser,
) -> @types.StructType raise ParserError {
  let fields = self.read_vec(() => self.read_field_type())
  { fields, }
}

///|
fn Parser::read_array_type(self : Parser) -> @types.ArrayType raise ParserError {
  let element = self.read_field_type()
  { element, }
}

///|
fn Parser::read_composite_type(
  self : Parser,
) -> @types.CompositeType raise ParserError {
  let tag = self.read_byte()
  match tag {
    0x60 => {
      let params = self.read_vec(() => self.read_value_type())
      let results = self.read_vec(() => self.read_value_type())
      @types.CompositeType::Func({ params, results })
    }
    0x5f => @types.CompositeType::Struct(self.read_struct_type())
    0x5e => @types.CompositeType::Array(self.read_array_type())
    _ => raise ParseError("unknown composite type tag: \{tag}")
  }
}

///|
fn Parser::read_subtype(self : Parser) -> @types.SubType raise ParserError {
  // WasmGC binary subtype encoding:
  // - 0x50: subtype header with flags + optional supertype
  // - 0x4f: final subtype header with optional supertype
  // - otherwise: implicit final subtype without supertypes
  let tag = self.peek_byte()
  if tag == 0x50 {
    self.skip(1)
    let flags = self.read_byte()
    let has_supertype = (flags & 0x01) != 0
    let final_ = (flags & 0x02) != 0
    if (flags & 0xFC) != 0 {
      raise ParseError("malformed subtype flags")
    }
    let supertypes : Array[Int] = if has_supertype {
      [self.read_u32()]
    } else {
      []
    }
    let composite = self.read_composite_type()
    { final_, supertypes, composite }
  } else if tag == 0x4f {
    self.skip(1)
    let flags = self.read_byte()
    let has_supertype = (flags & 0x01) != 0
    if (flags & 0xFE) != 0 {
      raise ParseError("malformed subtype flags")
    }
    let supertypes : Array[Int] = if has_supertype {
      [self.read_u32()]
    } else {
      []
    }
    let composite = self.read_composite_type()
    { final_: true, supertypes, composite }
  } else {
    // Implicit final subtype
    let composite = self.read_composite_type()
    { final_: true, supertypes: [], composite }
  }
}

///|
/// Read a rec group entry in the type section.
/// The type section is a vec of rec groups; each entry is either:
/// - 0x4e <vec subtype>  (explicit rec group)
/// - subtype             (implicit singleton group)
fn Parser::read_rec_group(
  self : Parser,
) -> Array[@types.SubType] raise ParserError {
  fn placeholder_subtype_by_composite_tag(
    composite_tag : Int,
  ) -> @types.SubType raise ParserError {
    let composite : @types.CompositeType = match composite_tag {
      0x60 => @types.CompositeType::Func({ params: [], results: [] })
      0x5f => @types.CompositeType::Struct({ fields: [] })
      0x5e => {
        let element : @types.FieldType = {
          storage_type: @types.StorageType::Val(@types.ValueType::I32),
          mutable: false,
        }
        @types.CompositeType::Array({ element, })
      }
      _ => raise ParseError("unknown composite type tag: \{composite_tag}")
    }
    { final_: true, supertypes: [], composite }
  }

  fn skip_value_type_no_resolve(self : Parser) -> Unit raise ParserError {
    let byte = self.read_byte()
    match byte {
      0x7F | 0x7E | 0x7D | 0x7C | 0x7B => ()

      // Reference shorthands
      0x70
      | 0x6F
      | 0x6E
      | 0x6D
      | 0x6C
      | 0x6B
      | 0x6A
      | 0x69
      | 0x71
      | 0x72
      | 0x73
      | 0x74 => ()

      // ref heaptype / ref null heaptype
      0x64 | 0x63 => self.read_heap_type() |> ignore

      // shared reference types proposal
      0x65 | 0x62 => {
        self.read_heap_type() |> ignore
        raise ParseError("shared reference types not supported")
      }
      _ => raise InvalidValueType(byte)
    }
  }

  fn skip_field_type_no_resolve(self : Parser) -> Unit raise ParserError {
    match self.peek_byte() {
      0x78 | 0x77 => self.skip(1)
      _ => skip_value_type_no_resolve(self)
    }
    let mutability = self.read_byte()
    if mutability != 0x00 && mutability != 0x01 {
      raise MalformedMutability(mutability)
    }
  }

  fn skip_composite_type_no_resolve(self : Parser) -> Int raise ParserError {
    let tag = self.read_byte()
    match tag {
      0x60 => {
        // func: vec(valtype) vec(valtype)
        let nparams = self.read_u32()
        for _ in 0..<nparams {
          skip_value_type_no_resolve(self)
        }
        let nresults = self.read_u32()
        for _ in 0..<nresults {
          skip_value_type_no_resolve(self)
        }
        tag
      }
      0x5f => {
        // struct: vec(fieldtype)
        let nfields = self.read_u32()
        for _ in 0..<nfields {
          skip_field_type_no_resolve(self)
        }
        tag
      }
      0x5e => {
        // array: fieldtype
        skip_field_type_no_resolve(self)
        tag
      }
      _ => raise ParseError("unknown composite type tag: \{tag}")
    }
  }

  fn skip_subtype_and_get_composite_tag(
    self : Parser,
  ) -> Int raise ParserError {
    let tag = self.peek_byte()
    if tag == 0x50 {
      self.skip(1)
      let flags = self.read_byte()
      let has_supertype = (flags & 0x01) != 0
      if (flags & 0xFC) != 0 {
        raise ParseError("malformed subtype flags")
      }
      if has_supertype {
        self.read_u32() |> ignore
      }
      skip_composite_type_no_resolve(self)
    } else if tag == 0x4f {
      self.skip(1)
      let flags = self.read_byte()
      let has_supertype = (flags & 0x01) != 0
      if (flags & 0xFE) != 0 {
        raise ParseError("malformed subtype flags")
      }
      if has_supertype {
        self.read_u32() |> ignore
      }
      skip_composite_type_no_resolve(self)
    } else {
      skip_composite_type_no_resolve(self)
    }
  }

  let tag = self.peek_byte()
  if tag == 0x4e {
    self.skip(1)
    let n = self.read_u32()
    let base_idx = self.types.length()

    // WasmGC allows forward references within a `rec` group. Pre-scan the group
    // to learn each entry's composite kind, then pre-allocate placeholders so
    // typed refs can be resolved during the real parse.
    let scan : Parser = {
      data: self.data,
      pos: self.pos,
      has_data_count: self.has_data_count,
      types: [],
    }
    let composite_tags : Array[Int] = []
    for _ in 0..<n {
      composite_tags.push(skip_subtype_and_get_composite_tag(scan))
    }
    for i in 0..<n {
      self.types.push(placeholder_subtype_by_composite_tag(composite_tags[i]))
    }
    let defs : Array[@types.SubType] = []
    for i in 0..<n {
      let subtype = self.read_subtype()
      defs.push(subtype)
      self.types[base_idx + i] = subtype
    }
    defs
  } else {
    let subtype = self.read_subtype()
    self.types.push(subtype)
    [subtype]
  }
}
