// ============================================================
// Section Parsing
// ============================================================

///|
/// Parse WebAssembly module from bytes
pub fn parse_module(data : Bytes) -> @types.Module raise ParserError {
  let parser = Parser::new(data)

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
  let mod = @types.Module::new()

  // Track last seen non-custom section id for ordering check
  let mut last_section_id = 0
  // Track data count from section 12 (if present)
  let mut data_count : Int? = None

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
    // The canonical order is: 1→2→3→4→5→6→13→7→8→9→12→10→11
    // (DataCount=12 appears between Elem=9 and Code=10, Tag=13 after Global=6)
    fn section_order(id : Int) -> Int {
      match id {
        1 => 1 // Type
        2 => 2 // Import
        3 => 3 // Function
        4 => 4 // Table
        5 => 5 // Memory
        6 => 6 // Global
        13 => 7 // Tag (exception handling, after Global)
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
            0x01 => @types.ImportDesc::Table(parser.read_table_type())
            0x02 => @types.ImportDesc::Memory(parser.read_memory_type())
            0x03 => @types.ImportDesc::Global(parser.read_global_type())
            0x04 => {
              // Tag import: attribute (should be 0 for exception) + type_idx
              let _ = parser.read_byte() // attribute, always 0 for exceptions
              @types.ImportDesc::Tag(parser.read_u32())
            }
            _ => raise InvalidImportKind(kind)
          }
          mod.imports.push({ mod_name, name, desc })
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
          mod.globals.push({ type_, init })
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
            0x01 => @types.ExportDesc::Table(parser.read_u32())
            0x02 => @types.ExportDesc::Memory(parser.read_u32())
            0x03 => @types.ExportDesc::Global(parser.read_u32())
            0x04 => @types.ExportDesc::Tag(parser.read_u32())
            _ => raise InvalidExportKind(kind)
          }
          mod.exports.push({ name, desc })
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
          mod.elems.push({ mode, type_: elem_type, init })
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
            for _ in 0..<n {
              locals.push(vt)
            }
          }
          let body = parser.read_expr()
          mod.codes.push({ locals, body })
        }
      }
      11 => {
        // Data section (bulk-memory encoding)
        let count = parser.read_u32()
        for _ in 0..<count {
          let flags = parser.read_u32()
          let (memory_idx, offset) : (Int, Array[@types.Instruction]) = match
            flags {
            0 => {
              // Active segment with implicit memory 0
              let offset = parser.read_expr()
              (0, offset)
            }
            1 =>
              // Passive segment (no memory, no offset)
              (0, [])
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
          mod.datas.push({ memory_idx, offset, init })
        }
      }
      0 => {
        // Custom section - parse and validate name, then skip rest
        // Custom section must have at least a name (which requires at least 1 byte for length)
        if section_size == 0 {
          raise UnexpectedEnd
        }
        // Read and validate the custom section name as UTF-8
        let _ = parser.read_string()
        // Skip any remaining custom section content
        parser.pos = section_end
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
          let _ = parser.read_byte() // attribute, always 0 for exceptions
          let type_idx = parser.read_u32()
          mod.tags.push(@types.TagType::{ type_idx, })
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
  mod
}
