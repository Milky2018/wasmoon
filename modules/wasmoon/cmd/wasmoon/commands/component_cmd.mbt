///|
pub(all) enum ComponentErrorFormat {
  Text
  Json
} derive(Debug, Eq)

///|
pub(all) enum ComponentErrorCode {
  CompFileNotFound
  CompParseError
  CompValidateError
  CompUnsupported
  CompRuntimeError
} derive(Debug, Eq)

///|
pub impl Show for ComponentErrorFormat with fn output(self, logger) {
  logger.write_string(to_repr(self).to_string())
}

///|
pub impl Show for ComponentErrorCode with fn output(self, logger) {
  logger.write_string(to_repr(self).to_string())
}

///|
priv struct ComponentCommandEvalResult {
  ok : Bool
  code : ComponentErrorCode?
  phase : String
  detail : String
  parsed : @component.Component?
  summary_lines : Array[String]
}

///|
fn component_error_code_string(code : ComponentErrorCode) -> String {
  match code {
    CompFileNotFound => "COMP_FILE_NOT_FOUND"
    CompParseError => "COMP_PARSE_ERROR"
    CompValidateError => "COMP_VALIDATE_ERROR"
    CompUnsupported => "COMP_UNSUPPORTED"
    CompRuntimeError => "COMP_RUNTIME_ERROR"
  }
}

///|
fn component_parse_error_code(
  e : @component.ComponentParseError,
) -> ComponentErrorCode {
  match e {
    UnsupportedComponentPreamble(_, _)
    | UnsupportedCanonOpcode(_)
    | UnsupportedTypeOpcode(_) => CompUnsupported
    _ => CompParseError
  }
}

///|
fn component_validation_error_code(
  e : @component_model.ComponentValidationError,
) -> ComponentErrorCode {
  match e {
    UnsupportedCoreSort(_)
    | UnsupportedComponentImport
    | UnsupportedComponentExport => CompUnsupported
    SectionParseError(_, msg) =>
      if msg.contains("unsupported") {
        CompUnsupported
      } else {
        CompValidateError
      }
    _ => CompValidateError
  }
}

///|
fn json_escape_string(s : String) -> String {
  let buf = StringBuilder::StringBuilder()
  for c in s {
    match c {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\r' => buf.write_string("\\r")
      '\t' => buf.write_string("\\t")
      _ => buf.write_char(c)
    }
  }
  buf.to_string()
}

///|
fn component_error_json(
  ok : Bool,
  code : ComponentErrorCode?,
  phase : String,
  detail : String,
  summary? : Array[String]? = None,
) -> String {
  let mut line = "{\"ok\":"
  line = line + (if ok { "true" } else { "false" })
  if code is Some(code) {
    line = line + ",\"code\":\"\{component_error_code_string(code)}\""
  }
  line = line + ",\"phase\":\"\{json_escape_string(phase)}\""
  line = line + ",\"detail\":\"\{json_escape_string(detail)}\""
  if summary is Some(summary) {
    line = line + ",\"summary\":["
    for i, item in summary {
      if i > 0 {
        line = line + ","
      }
      line = line + "\"\{json_escape_string(item)}\""
    }
    line = line + "]"
  }
  line + "}"
}

///|
fn build_component_summary_lines(
  parsed : @component.Component,
) -> Array[String] {
  let has_start = match parsed.start {
    Some(_) => true
    None => false
  }
  [
    "component version=\{parsed.binary.version} layer=\{parsed.binary.layer} sections=\{parsed.binary.sections.length()}",
    "core_modules=\{parsed.core_modules.length()} core_instances=\{parsed.core_instances.length()} core_types=\{parsed.core_types.length()} nested_components=\{parsed.components.length()}",
    "types=\{parsed.types.length()} imports=\{parsed.imports.length()} exports=\{parsed.exports.length()} instances=\{parsed.instances.length()} aliases=\{parsed.aliases.length()} canons=\{parsed.canons.length()} start=\{has_start}",
  ]
}

///|
fn run_component_command_eval(
  file_path : String,
  validate : Bool,
  wit_names : Bool,
) -> ComponentCommandEvalResult {
  let bytes = @fs.read_file_to_bytes(file_path) catch {
    IOError(_e) =>
      return {
        ok: false,
        code: Some(CompFileNotFound),
        phase: "read",
        detail: "file \{file_path} not found",
        parsed: None,
        summary_lines: [],
      }
  }
  let parsed = @component.parse_component(bytes) catch {
    e =>
      return {
        ok: false,
        code: Some(component_parse_error_code(e)),
        phase: "parse",
        detail: e.to_string(),
        parsed: None,
        summary_lines: [],
      }
  }
  if validate {
    @component_model.validate_component_with_config(
      parsed,
      ComponentValidationConfig(wit_names),
    ) catch {
      e =>
        return {
          ok: false,
          code: Some(component_validation_error_code(e)),
          phase: "validate",
          detail: e.to_string(),
          parsed: None,
          summary_lines: [],
        }
    }
  }
  let summary_lines = build_component_summary_lines(parsed)
  let merged_summary = if validate {
    ["component validated ok"] + summary_lines
  } else {
    summary_lines
  }
  {
    ok: true,
    code: None,
    phase: if validate {
      "validate"
    } else {
      "summary"
    },
    detail: if validate {
      "component validated ok"
    } else {
      "component parsed ok"
    },
    parsed: Some(parsed),
    summary_lines: merged_summary,
  }
}

///|
pub fn run_component_command(
  file_path : String,
  dump : Bool,
  validate : Bool,
  wit_names : Bool,
  error_format : ComponentErrorFormat,
) -> Int {
  let result = run_component_command_eval(file_path, validate, wit_names)
  if result.ok {
    if error_format is Json {
      println(
        component_error_json(
          true,
          None,
          if dump {
            "dump"
          } else {
            result.phase
          },
          if dump {
            "component dump requested"
          } else {
            result.detail
          },
          summary=Some(result.summary_lines),
        ),
      )
      return 0
    }
    if dump {
      match result.parsed {
        Some(parsed) => println(parsed)
        None => println("parse component error: missing parsed component")
      }
      return 0
    }
    for line in result.summary_lines {
      println(line)
    }
    return 0
  }

  if error_format is Json {
    println(
      component_error_json(
        false,
        result.code,
        result.phase,
        result.detail,
        summary=None,
      ),
    )
    return 1
  }
  match result.phase {
    "read" => println(result.detail)
    "parse" => println("parse component error: \{result.detail}")
    "validate" => println("validate component error: \{result.detail}")
    _ => println(result.detail)
  }
  1
}

///|
fn component_command_run_instance(
  instance : @runtime_impl.ComponentInstance,
) -> @runtime_impl.ComponentInstance? {
  for name in ["wasi:cli/run@0.2.11", "wasi:cli/run@0.3.0-rc-2025-09-16"] {
    match instance.get_export(name) {
      Some(Instance(run)) => return Some(run)
      _ => ()
    }
  }
  None
}

///|
fn component_command_status(
  values : Array[@runtime_impl.ComponentValue],
  requested_exit : Int?,
) -> Int raise @runtime_impl.ComponentRuntimeError {
  match requested_exit {
    Some(status) => status
    None =>
      match values {
        [Variant(0, None)] => 0
        [Variant(1, None)] => 1
        _ =>
          raise HostCallError(
            "wasi:cli/run returned a value outside result<(), ()>",
          )
      }
  }
}

///|
fn report_component_run_error(
  format : ComponentErrorFormat,
  phase : String,
  detail : String,
) -> Int {
  if format is Json {
    println(
      component_error_json(
        false,
        Some(CompRuntimeError),
        phase,
        detail,
        summary=None,
      ),
    )
  } else {
    println("component \{phase} error: \{detail}")
  }
  1
}

///|
fn component_command_context(
  file_path : String,
  args : Array[String],
  envs : Array[String],
  dirs : Array[String],
  network : String,
) -> @wasi_component.WasiComponentCtx raise @runtime_impl.ComponentRuntimeError {
  let parsed_envs = []
  let parsed_dirs = []
  for entry in envs {
    match parse_env_var(entry) {
      Some(pair) => parsed_envs.push(pair)
      None => raise HostCallError("invalid environment entry '\{entry}'")
    }
  }
  for mapping in dirs {
    match parse_dir_mapping(mapping) {
      Some(pair) => parsed_dirs.push(pair)
      None => raise HostCallError("invalid preopen mapping '\{mapping}'")
    }
  }
  let network_policy : @wasi_component.WasiNetworkPolicy = match network {
    "deny" => DenyAll
    "loopback" => LoopbackOnly
    "all" => AllowAll
    _ => raise HostCallError("unknown network policy '\{network}'")
  }
  let mut builder = @wasi_component.WasiComponentCtxBuilder()
    .args([file_path] + args)
    .inherit_stdio()
    .network_policy(network_policy)
  for pair in parsed_envs {
    let (name, value) = pair
    builder = builder.env(name, value)
  }
  for pair in parsed_dirs {
    let (host_path, guest_path) = pair
    builder = builder.preopened_directory(host_path, guest_path, false) catch {
      e => {
        builder.build().close()
        raise e
      }
    }
  }
  builder.build()
}

///|
pub fn run_wasi_component_command(
  file_path : String,
  args : Array[String],
  envs : Array[String],
  dirs : Array[String],
  network : String,
  wit_names : Bool,
  error_format : ComponentErrorFormat,
  use_jit? : Bool = true,
) -> Int {
  let parsed = run_component_command_eval(file_path, true, wit_names)
  guard parsed.parsed is Some(component) else {
    return report_component_run_error(error_format, parsed.phase, parsed.detail)
  }
  let ctx = component_command_context(file_path, args, envs, dirs, network) catch {
    e =>
      return report_component_run_error(
        error_format,
        "configure",
        e.to_string(),
      )
  }
  defer ctx.close()
  let linker = if use_jit {
    @runtime_impl.ComponentLinker::with_core_execution_engine(
      component_jit_execution_engine(),
    )
  } else {
    ComponentLinker()
  }
  let host = @wasi_component.WasiComponentHost(linker, ctx)
  (try {
    host.add_preview2_cli_clocks_random()
    host.add_preview2_io()
    host.add_preview2_filesystem()
    host.add_preview2_sockets()
    host.add_preview3_cli_clocks_random()
    host.add_preview3_filesystem()
    host.add_preview3_sockets()
  } catch {
    e =>
      return report_component_run_error(
        error_format,
        "configure",
        e.to_string(),
      )
  })
  |> ignore
  let instance = linker.instantiate("command", component) catch {
    e =>
      return report_component_run_error(
        error_format,
        "instantiate",
        e.to_string(),
      )
  }
  guard component_command_run_instance(instance) is Some(run) else {
    return report_component_run_error(
      error_format, "instantiate", "component does not export a pinned wasi:cli/run instance",
    )
  }
  let result = try run.call_exported_func("run", []) catch {
    HostExit(status) => return status
    e => return report_component_run_error(error_format, "run", e.to_string())
  } noraise {
    values => values
  }
  component_command_status(result, ctx.exit_status()) catch {
    e => report_component_run_error(error_format, "run", e.to_string())
  }
}
