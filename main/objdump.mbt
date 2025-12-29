///|
/// Inspect a precompiled .cwasm file
fn run_objdump(cwasm_path : String) -> Unit {
  @logger.info("Inspecting: \{cwasm_path}")
  println("=".repeat(60))

  // Read the file
  let bytes_raw = @fs.read_file_to_bytes(cwasm_path) catch {
    e => {
      @logger.error("reading file: \{e}")
      return
    }
  }

  // Convert Bytes to Array[Int]
  let bytes : Array[Int] = []
  for i in 0..<bytes_raw.length() {
    bytes.push(bytes_raw[i].to_int())
  }

  // Deserialize the precompiled module
  let precompiled = @cwasm.deserialize(bytes) catch {
    e => {
      @logger.error("parsing cwasm: \{e}")
      return
    }
  }

  // Display metadata
  println("")
  println("== Metadata ==")
  println("  Format:       cwasm")
  println("  Version:      \{precompiled.version}")
  println("  Target:       \{precompiled.target}")
  println("  Functions:    \{precompiled.functions.length()}")
  println("")

  // Calculate total code size
  let mut total_code_size = 0
  for func in precompiled.functions {
    total_code_size = total_code_size + func.code.length()
  }
  println("  Total code:   \{total_code_size} bytes")
  println("")

  // Display section info
  println("== Functions ==")
  if precompiled.functions.length() == 0 {
    println("  (no compiled functions)")
  } else {
    for func in precompiled.functions {
      println("")
      println("  Function \{func.func_idx}:")
      println("    Name:         \{func.name}")
      println("    Code size:    \{func.code.length()} bytes")
      println("    Frame size:   \{func.frame_size} bytes")
      println("    Entry offset: \{func.entry_offset}")

      // Show first few bytes of code as hex
      if func.code.length() > 0 {
        let hex_preview = StringBuilder::new()
        let preview_len = if func.code.length() > 16 {
          16
        } else {
          func.code.length()
        }
        for i in 0..<preview_len {
          if i > 0 {
            hex_preview.write_string(" ")
          }
          let b = func.code[i]
          hex_preview.write_string(to_hex_byte(b))
        }
        if func.code.length() > 16 {
          hex_preview.write_string(" ...")
        }
        println("    Code preview: \{hex_preview.to_string()}")
      }
    }
  }
  println("")
  println("=".repeat(60))
}

///|
fn to_hex_byte(b : Int) -> String {
  let hex_chars = "0123456789abcdef"
  let high = (b >> 4) & 0xF
  let low = b & 0xF
  String::make(1, hex_chars.code_unit_at(high).unsafe_to_char()) +
  String::make(1, hex_chars.code_unit_at(low).unsafe_to_char())
}
