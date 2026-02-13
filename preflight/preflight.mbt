///|
/// Preflight stage markers for module and JIT validation.
pub(all) enum PreflightStage {
  Parse
  Validate
  Translate
  Lower
  Regalloc
}

///|
fn PreflightStage::to_string(self : PreflightStage) -> String {
  match self {
    Parse => "parse"
    Validate => "validate"
    Translate => "translate"
    Lower => "lower"
    Regalloc => "regalloc"
  }
}

///|
pub impl Show for PreflightStage with output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// Severity level for a preflight diagnostic.
pub(all) enum PreflightSeverity {
  Error
  Warning
}

///|
fn PreflightSeverity::to_string(self : PreflightSeverity) -> String {
  match self {
    Error => "error"
    Warning => "warning"
  }
}

///|
pub impl Show for PreflightSeverity with output(self, logger) {
  logger.write_string(self.to_string())
}

///|
/// A structured diagnostic emitted during preflight checks.
pub struct PreflightDiagnostic {
  severity : PreflightSeverity
  stage : PreflightStage
  message : String
  func_idx : Int?
  func_name : String?
}

///|
pub fn PreflightDiagnostic::new(
  severity : PreflightSeverity,
  stage : PreflightStage,
  message : String,
  func_idx? : Int? = None,
  func_name? : String? = None,
) -> PreflightDiagnostic {
  { severity, stage, message, func_idx, func_name }
}

///|
/// Structured preflight report for integration callers.
pub struct PreflightResult {
  mut ok : Bool
  diagnostics : Array[PreflightDiagnostic]
  mut total_funcs : Int
  mut checked_funcs : Int
}

///|
pub fn PreflightResult::new() -> PreflightResult {
  { ok: true, diagnostics: [], total_funcs: 0, checked_funcs: 0 }
}

///|
pub fn PreflightResult::add_error(
  self : PreflightResult,
  stage : PreflightStage,
  message : String,
  func_idx? : Int? = None,
  func_name? : String? = None,
) -> Unit {
  self.ok = false
  self.diagnostics.push(
    PreflightDiagnostic::new(Error, stage, message, func_idx~, func_name~),
  )
}

///|
pub fn PreflightResult::add_warning(
  self : PreflightResult,
  stage : PreflightStage,
  message : String,
  func_idx? : Int? = None,
  func_name? : String? = None,
) -> Unit {
  self.diagnostics.push(
    PreflightDiagnostic::new(Warning, stage, message, func_idx~, func_name~),
  )
}

///|
fn count_func_imports(imports : Array[@types.Import]) -> Int {
  let mut count = 0
  for imp in imports {
    if imp.desc is Func(_) {
      count = count + 1
    }
  }
  count
}

///|
fn get_func_name(mod_ : @types.Module, func_idx : Int) -> String {
  for exp in mod_.exports {
    if exp.desc is Func(idx) && idx == func_idx {
      return exp.name
    }
  }
  "func_\{func_idx}"
}

///|
fn normalize_opt_level(opt_level : Int) -> Int {
  if opt_level < 0 {
    0
  } else if opt_level > 3 {
    3
  } else {
    opt_level
  }
}

///|
fn parse_and_validate_module(
  module_bytes : Bytes,
  report : PreflightResult,
) -> @types.Module? {
  let mod_ = @parser.parse_module(module_bytes) catch {
    e => {
      report.add_error(Parse, e.to_string())
      return None
    }
  }
  report.total_funcs = mod_.codes.length()
  @validator.validate_module(mod_) catch {
    e => {
      let (message, func_idx) = match e {
        @validator.WithContext(ctx) => (ctx.format(), ctx.func_idx)
        _ => (@validator.format_validation_error(e), None)
      }
      report.add_error(Validate, message, func_idx~)
      return None
    }
  }
  Some(mod_)
}

///|
/// Validate module bytes (parse + wasm validation) and return structured diagnostics.
pub fn validate_module(module_bytes : Bytes) -> PreflightResult {
  let report = PreflightResult::new()
  ignore(parse_and_validate_module(module_bytes, report))
  report
}

///|
/// Validate JIT preconditions for module bytes.
///
/// This API performs:
/// - Parse and wasm validation.
/// - IR translation, lowering, and regalloc checks per local function.
///
/// It intentionally does not execute machine-code emission to avoid hard runtime
/// failures from backend aborts during preflight.
pub fn validate_jit(
  module_bytes : Bytes,
  opt_level? : Int = 2,
) -> PreflightResult {
  let report = PreflightResult::new()
  let mod_ = parse_and_validate_module(module_bytes, report)
  guard mod_ is Some(wasm_module) else { return report }
  let normalized_opt_level = normalize_opt_level(opt_level)
  let num_imports = count_func_imports(wasm_module.imports)
  for i, _ in wasm_module.codes {
    let func_idx = num_imports + i
    let func_name = get_func_name(wasm_module, func_idx)
    let ir_func = @ir.translate_function(wasm_module, i, name=func_name)
    @ir.optimize_with_level(
      ir_func,
      @ir.OptLevel::from_int(normalized_opt_level),
    )
    |> ignore
    let vcode_func = @lower.lower_function(
      ir_func,
      num_imports=wasm_module.imports.length(),
      run_ir_opt=false,
    )
    ignore(@regalloc.allocate_registers_backtracking(vcode_func))
    report.checked_funcs = report.checked_funcs + 1
  }
  report
}
