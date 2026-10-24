// ============================================================
// Section Parsing
// ============================================================

///|
/// Parse WebAssembly module from bytes
pub fn parse_module(
  data : Bytes,
  limits? : ParseLimits,
  admit_work~ : ((Int64) -> Bool)? = None,
) -> @types.Module raise ParserError {
  parse_module_impl(data, limits?, admit_work~, capture_sources=false).0
}

///|
/// Parse a binary and retain original instruction positions for each defined
/// function. Neither re-encoding an AST nor native code offsets can recover
/// these positions, including non-canonical LEBs and custom sections.
pub fn parse_module_with_sources(
  data : Bytes,
  limits? : ParseLimits,
  admit_work~ : ((Int64) -> Bool)? = None,
) -> (@types.Module, Array[Array[@types.InstructionSource]]) raise ParserError {
  parse_module_impl(data, limits?, admit_work~, capture_sources=true)
}

///|
fn parse_module_impl(
  data : Bytes,
  limits? : ParseLimits,
  admit_work~ : ((Int64) -> Bool)?,
  capture_sources~ : Bool,
) -> (@types.Module, Array[Array[@types.InstructionSource]]) raise ParserError {
  let function_sources : Array[Array[@types.InstructionSource]] = []
  let limits = limits.unwrap_or({
    max_input_bytes: 0x7FFF_FFFF_FFFF_FFFFL,
    max_work: 0x7FFF_FFFF_FFFF_FFFFL,
    max_depth: 0x7FFF_FFFF,
  })
  guard limits.max_input_bytes >= 0L &&
    limits.max_work >= 0L &&
    limits.max_depth >= 0 else {
    raise InvalidParseLimits
  }
  guard data.length().to_int64() <= limits.max_input_bytes else {
    raise InputLimitExceeded
  }
  let parser : Parser = {
    data,
    pos: 0,
    instruction_sources: None,
    has_data_count: false,
    types: [],
    remaining_work: Ref(limits.max_work),
    max_depth: limits.max_depth,
    admit_work,
  }

  // Check magic number
  let magic = parser.read_bytes(4)
  if magic != b"\x00asm" {
    raise InvalidMagicNumber
  }

  // Check version
  let version = parser.read_bytes(4)
  if version != b"\x01\x00\x00\x00" {
    raise UnsupportedVersion
  }
  let mod = @types.Module::Module()

  // Track last seen non-custom section id for ordering check
  let mut last_section_id = 0
  // Track data count from section 12 (if present)
  let mut data_count : Int32? = None

  // Parse sections
  while !parser.is_eof() {
    let section_id = parser.read_byte()
    let section_size = parser.read_u32()
    let section_end = parser.pos + section_size

    // Validate section_end doesn't exceed data length
    if section_end > parser.data.length() {
      raise LengthOutOfBounds
    }

    // Check section ordering (non-custom sections must be in order, no duplicates)
    // The canonical order is: 1→2→3→4→5→13→6→7→8→9→12→10→11
    // (Tag=13 is before Global=6, DataCount=12 appears between Elem=9 and Code=10)
    fn section_order(id : Int32) -> Int32 {
      match id {
        1 => 1 // Type
        2 => 2 // Import
        3 => 3 // Function
        4 => 4 // Table
        5 => 5 // Memory
        13 => 6 // Tag (exception handling, before Global)
        6 => 7 // Global
        7 => 8 // Export
        8 => 9 // Start
        9 => 10 // Elem
        12 => 11 // DataCount (before Code)
        10 => 12 // Code
        11 => 13 // Data
        _ => id // Custom (0) or unknown
      }
    }

    if section_id != 0 {
      // Custom sections (id=0) can appear anywhere
      let current_order = section_order(section_id)
      let last_order = section_order(last_section_id)
      if current_order <= last_order {
        raise DuplicateSection(section_id)
      }
      last_section_id = section_id
    }
    match section_id {
      1 => {
        // Type section
        // The binary type section is a vec of rec groups (WasmGC).
        let group_count = parser.read_u32()
        for group_id in 0..<group_count {
          let group = parser.read_rec_group()
          for subtype in group {
            mod.types.push(subtype)
            mod.type_rec_groups.push(group_id)
          }
        }
      }
      2 => {
        // Import section
        let count = parser.read_u32()
        for _ in 0..<count {
          let mod_name = parser.read_string()
          let name = parser.read_string()
          let kind = parser.read_byte()
          let desc = match kind {
            0x00 => @types.ImportDesc::Func(parser.read_u32())
            0x01 => Table(parser.read_table_type())
            0x02 => Memory(parser.read_memory_type())
            0x03 => Global(parser.read_global_type())
            0x04 => {
              // Tag import: attribute (should be 0 for exception) + type_idx
              parser.read_byte() |> ignore // attribute, always 0 for exceptions
              Tag(parser.read_u32())
            }
            _ => raise InvalidImportKind(kind)
          }
          mod.imports.push({ mod_name, name, desc, })
        }
      }
      3 => {
        // Function section
        let count = parser.read_u32()
        for _ in 0..<count {
          mod.funcs.push(parser.read_u32())
        }
      }
      4 => {
        // Table section
        let count = parser.read_u32()
        for _ in 0..<count {
          mod.tables.push(parser.read_table())
        }
      }
      5 => {
        // Memory section
        let count = parser.read_u32()
        for _ in 0..<count {
          mod.memories.push(parser.read_memory_type())
        }
      }
      6 => {
        // Global section
        let count = parser.read_u32()
        for _ in 0..<count {
          let type_ = parser.read_global_type()
          let init = parser.read_expr()
          mod.globals.push({ type_, init: ReadOnlyArray::from_array(init), })
        }
      }
      7 => {
        // Export section
        let count = parser.read_u32()
        for _ in 0..<count {
          let name = parser.read_string()
          let kind = parser.read_byte()
          let desc = match kind {
            0x00 => @types.ExportDesc::Func(parser.read_u32())
            0x01 => Table(parser.read_u32())
            0x02 => Memory(parser.read_u32())
            0x03 => Global(parser.read_u32())
            0x04 => Tag(parser.read_u32())
            _ => raise InvalidExportKind(kind)
          }
          mod.exports.push({ name, desc, })
        }
      }
      8 =>
        // Start section
        mod.start = Some(parser.read_u32())
      9 => {
        // Element section (supports WebAssembly 1.0+ formats)
        let count = parser.read_u32()
        for _ in 0..<count {
          let flags = parser.read_u32()
          let (mode, elem_type, init) = parser.read_elem_segment(flags)
          mod.elems.push({
            mode,
            type_: elem_type,
            init: ReadOnlyArray::from_array(init),
          })
        }
      }
      10 => {
        // Code section
        let count = parser.read_u32()
        for _ in 0..<count {
          let _code_size = parser.read_u32()
          let local_count = parser.read_u32()
          let locals : Array[@types.ValueType] = []
          let mut total_locals : Int64 = 0L
          for _ in 0..<local_count {
            let n = parser.read_u32()
            let vt = parser.read_value_type()
            // Check for too many locals before accumulating
            // Treat n as unsigned by reinterpreting
            let n_unsigned = n.reinterpret_as_uint().to_int64()
            total_locals = total_locals + n_unsigned
            if total_locals > 1000000L {
              raise TooManyLocals
            }
            parser.charge(n_unsigned)
            for _ in 0..<n {
              locals.push(vt)
            }
          }
          if capture_sources {
            parser.instruction_sources = Some([])
          }
          let body = parser.read_expr()
          if parser.instruction_sources is Some(sources) {
            function_sources.push(sources)
            parser.instruction_sources = None
          }
          mod.codes.push({
            locals: ReadOnlyArray::from_array(locals),
            body: ReadOnlyArray::from_array(body),
          })
        }
      }
      11 => {
        // Data section (bulk-memory encoding)
        let count = parser.read_u32()
        for _ in 0..<count {
          let flags = parser.read_u32()
          let (memory_idx, offset) : (Int32, Array[@types.Instruction]) = match
            flags {
            0 => {
              // Active segment with implicit memory 0
              let offset = parser.read_expr()
              (0, offset)
            }
            1 =>
              // Passive segment (no memory, no offset)
              (-1, [])
            2 => {
              // Active segment with explicit memory index
              let memory_idx = parser.read_u32()
              let offset = parser.read_expr()
              (memory_idx, offset)
            }
            _ => raise MalformedDataSegmentFlags(flags)
          }
          let size = parser.read_u32()
          let init = parser.read_bytes(size)
          mod.datas.push({
            memory_idx,
            offset: ReadOnlyArray::from_array(offset),
            init,
          })
        }
      }
      0 => {
        // Custom section - parse and validate name, then skip rest
        // Custom section must have at least a name (which requires at least 1 byte for length)
        if section_size == 0 {
          raise UnexpectedEnd
        }
        // Read and validate the custom section name as UTF-8
        let name = parser.read_string()
        guard parser.pos <= section_end else { raise SectionSizeMismatch }
        if name == "name" {
          let payload = parser.read_bytes(section_end - parser.pos)
          let names = parser.read_function_names(payload) catch {
            error => {
              if error.is_resource_exhaustion() {
                raise error
              }
              Map([])
            }
          }
          for index, function_name in names {
            mod.func_names.set(index, function_name)
          }
        } else {
          parser.skip(section_end - parser.pos)
        }
      }
      12 => {
        // Data count section (bulk memory)
        data_count = Some(parser.read_u32())
        parser.has_data_count = true
      }
      13 => {
        // Tag section (exception handling)
        let count = parser.read_u32()
        for _ in 0..<count {
          parser.read_byte() |> ignore // attribute, always 0 for exceptions
          let type_idx = parser.read_u32()
          mod.tags.push({ type_idx, })
        }
      }
      _ =>
        // Invalid section id (valid range is 0-13)
        raise MalformedSectionId(section_id)
    }

    // Ensure we're at the expected position
    if parser.pos != section_end {
      raise SectionSizeMismatch
    }
  }

  // Verify function and code section counts match
  if mod.funcs.length() != mod.codes.length() {
    raise FunctionCodeMismatch
  }

  // Verify data count and data section counts match (if data count section present)
  if data_count is Some(count) && count != mod.datas.length() {
    raise DataCountMismatch
  }

  // Check for unexpected content after last section
  if !parser.is_eof() {
    raise UnexpectedContent
  }
  // Debug indices have no validation authority and may precede definitions.
  let mut function_count = mod.funcs.length()
  for import_ in mod.imports {
    if import_.desc is Func(_) {
      function_count += 1
    }
  }
  let invalid = mod.func_names
    .iter()
    .filter_map(pair => {
      if pair.0 < 0 || pair.0 >= function_count {
        Some(pair.0)
      } else {
        None
      }
    })
    .to_array()
  for index in invalid {
    mod.func_names.remove(index) |> ignore
  }
  (mod, function_sources)
}
