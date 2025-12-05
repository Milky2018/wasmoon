///|
/// Parse and display a WAT file
fn run_wat(wat_path : String) -> Unit {
  let content = @fs.read_file_to_string(wat_path) catch {
    e => {
      println("Error reading file: \{e}")
      return
    }
  }
  let mod_ = @wat.parse(content) catch {
    e => {
      println("Error parsing WAT: \{e}")
      return
    }
  }
  // Display parsed module using the disassembler
  let output = @disasm.disassemble(mod_)
  println("Parsed WAT module:")
  println(output)
}

///|
/// Run testsuite with a JSON spec file
fn run_testsuite(json_path : String) -> Unit {
  println("Running testsuite: \{json_path}")
  println("=".repeat(50))
  // Read JSON file
  let json_content = @fs.read_file_to_string(json_path) catch {
    e => {
      println("Error reading JSON file: \{e}")
      return
    }
  }
  // Determine base directory
  let base_dir = find_base_dir(json_path)
  // Run tests - use a wrapper that calls async
  let result = run_tests_internal(json_content, base_dir) catch {
    _ => {
      println("Error running tests")
      return
    }
  }
  // Print results
  println("")
  println("Results:")
  println("  Passed:  \{result.passed}")
  println("  Failed:  \{result.failed}")
  println("  Skipped: \{result.skipped}")
  if result.failures.length() > 0 {
    println("")
    println("Failures:")
    for failure in result.failures {
      println("  - \{failure}")
    }
  }
  if result.skip_reasons.length() > 0 {
    println("")
    println("Skipped:")
    for reason in result.skip_reasons {
      println("  - \{reason}")
    }
  }
  println("=".repeat(50))
}

///|
/// Internal test runner that handles file reading
fn run_tests_internal(
  json_content : String,
  base_dir : String,
) -> @testsuite.TestResult raise CliError {
  let parsed = @testsuite.parse_json_test_file(json_content) catch {
    e => raise TestError(e.to_string())
  }
  let result = @testsuite.TestResult::new()
  result.source_filename = parsed.source_filename
  let ctx = @testsuite.TestContext::new()
  for cmd in parsed.commands {
    run_test_command(ctx, cmd.command, cmd.line, result, base_dir)
  }
  result
}

///|
/// Wrapper for running a test command - handles file I/O inline
fn run_test_command(
  ctx : @testsuite.TestContext,
  cmd : @testsuite.TestCommand,
  line : Int?,
  result : @testsuite.TestResult,
  base_dir : String,
) -> Unit {
  let line_prefix = match line {
    Some(n) => "[line \{n}] "
    None => ""
  }
  match cmd {
    Module(filename) => {
      let bytes = read_wasm_file(base_dir, filename)
      match bytes {
        Some(b) =>
          if (try? {
              let instance = ctx.load_module(b, None)
              ctx.set_current_module(instance)
            })
            is Err(e) {
            result.add_failed(
              "\{line_prefix}Failed to load module \{filename}: \{e}",
            )
          }
        None => result.add_skipped("module file not found: \{filename}")
      }
    }
    AssertReturn(action, expected) =>
      match action {
        Invoke(module_name, func_name, args) => {
          let success = @testsuite.run_assert_return(
            ctx, module_name, func_name, args, expected,
          )
          if success {
            result.add_passed()
          } else {
            result.add_failed(
              "\{line_prefix}assert_return failed: \{func_name}",
            )
          }
        }
        Get(_module_name, field) =>
          result.add_skipped("assert_return (get) not implemented: \{field}")
      }
    AssertTrap(action, expected_msg) =>
      match action {
        Invoke(module_name, func_name, args) => {
          let success = @testsuite.run_assert_trap(
            ctx, module_name, func_name, args, expected_msg,
          )
          if success {
            result.add_passed()
          } else {
            result.add_failed("\{line_prefix}assert_trap failed: \{func_name}")
          }
        }
        Get(_, field) =>
          result.add_skipped("assert_trap (get) not implemented: \{field}")
      }
    AssertInvalid(filename, _msg) => {
      let bytes = read_wasm_file(base_dir, filename)
      match bytes {
        Some(b) =>
          if (try? {
              let mod = @parser.parse_module(b)
              @validator.validate_module(mod)
            })
            is Ok(_) {
            result.add_failed(
              "\{line_prefix}assert_invalid should have failed: \{filename}",
            )
          } else {
            result.add_passed()
          }
        None =>
          result.add_skipped("assert_invalid: file not found: \{filename}")
      }
    }
    AssertMalformed(filename, _msg) => {
      // Check if it's a WAT file (text format)
      if filename.has_suffix(".wat") {
        let content = read_text_file(base_dir, filename)
        match content {
          Some(text) =>
            if (try? @wat.parse(text)) is Ok(_) {
              result.add_failed(
                "\{line_prefix}assert_malformed should have failed: \{filename}",
              )
            } else {
              result.add_passed()
            }
          None =>
            // WAT files with module_type="text" are not generated by wast2json
            result.add_skipped(
              "assert_malformed: WAT file not generated by wast2json: \{filename}",
            )
        }
      } else {
        let bytes = read_wasm_file(base_dir, filename)
        match bytes {
          Some(b) =>
            if (try? @parser.parse_module(b)) is Ok(_) {
              result.add_failed(
                "\{line_prefix}assert_malformed should have failed: \{filename}",
              )
            } else {
              result.add_passed()
            }
          None =>
            result.add_skipped("assert_malformed: file not found: \{filename}")
        }
      }
    }
    AssertUninstantiable(filename, _msg) => {
      let bytes = read_wasm_file(base_dir, filename)
      match bytes {
        Some(b) =>
          if (try? ctx.load_module(b, None)) is Ok(_) {
            result.add_failed(
              "\{line_prefix}assert_uninstantiable should have failed: \{filename}",
            )
          } else {
            result.add_passed()
          }
        None =>
          result.add_skipped(
            "assert_uninstantiable: file not found: \{filename}",
          )
      }
    }
    Register(as_, name) =>
      match ctx.get_current_module() {
        Some(inst) => {
          ctx.named_modules.set(as_, inst)
          match name {
            Some(n) => ctx.named_modules.set(n, inst)
            None => ()
          }
        }
        None =>
          println("\{line_prefix}Warning: Register without current module")
      }
    Action(action) =>
      match action {
        Invoke(module_name, func_name, args) => {
          let runtime_args = args.map(@testsuite.parse_test_value)
          try ctx.invoke(module_name, func_name, runtime_args) |> ignore catch {
            e => println("\{line_prefix}Action invoke error: \{e}")
          }
        }
        Get(_, _) => ()
      }
  }
}
