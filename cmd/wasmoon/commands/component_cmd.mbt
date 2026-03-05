///|
pub(all) enum ComponentErrorFormat {
  Text
  Json
} derive(Show, Eq)

///|
pub(all) enum ComponentErrorCode {
  CompFileNotFound
  CompParseError
  CompValidateError
  CompUnsupported
} derive(Show, Eq)

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
    @component_model.UnsupportedCoreSort(_)
    | @component_model.UnsupportedComponentImport
    | @component_model.UnsupportedComponentExport => CompUnsupported
    @component_model.SectionParseError(_, msg) =>
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
  let buf = StringBuilder::new()
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
      @component_model.ComponentValidationConfig::new(wit_names),
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
