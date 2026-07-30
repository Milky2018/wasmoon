///|
/// Stable component runtime facade.
///
/// Normal embedders should use the types in this package instead of importing
/// `Milky2018/wasmoon/component/runtime_impl`. The facade owns its public value,
/// type, error, instance, and function vocabulary. Canonical ABI encodings and
/// scheduler state remain private implementation details.

///|
struct ComponentResourceType {
  identity : String
} derive(Debug, Eq)

///|
pub fn ComponentResourceType::named(name : String) -> ComponentResourceType {
  { identity: name }
}

///|
pub fn ComponentResourceType::name(self : ComponentResourceType) -> String {
  self.identity
}

///|
pub(all) enum ComponentValueType {
  Bool
  S8
  U8
  S16
  U16
  S32
  U32
  S64
  U64
  F32
  F64
  Char
  String
  ErrorContext
  List(ComponentValueType)
  FixedList(ComponentValueType, Int)
  MapType(ComponentValueType, ComponentValueType)
  Tuple(Array[ComponentValueType])
  Record(Array[ComponentField])
  Variant(Array[ComponentCase])
  Enum(Array[String])
  Flags(Array[String])
  Option(ComponentValueType)
  Result(ComponentValueType?, ComponentValueType?)
  Own(ComponentResourceType)
  Borrow(ComponentResourceType)
  Stream(ComponentValueType?)
  Future(ComponentValueType?)
} derive(Debug, Eq)

///|
pub impl Show for ComponentValueType with fn output(self, logger) {
  logger.write_string(to_repr(self).to_string())
}

///|
pub struct ComponentField {
  name : String
  ty : ComponentValueType
} derive(Debug, Eq)

///|
pub impl Show for ComponentField with fn output(self, logger) {
  logger.write_string(to_repr(self).to_string())
}

///|
pub fn ComponentField::ComponentField(
  name : String,
  ty : ComponentValueType,
) -> ComponentField {
  { name, ty }
}

///|
pub struct ComponentCase {
  name : String
  ty : ComponentValueType?
} derive(Debug, Eq)

///|
pub impl Show for ComponentCase with fn output(self, logger) {
  logger.write_string(to_repr(self).to_string())
}

///|
pub fn ComponentCase::ComponentCase(
  name : String,
  ty : ComponentValueType?,
) -> ComponentCase {
  { name, ty }
}

///|
pub struct ComponentParam {
  name : String
  ty : ComponentValueType
} derive(Debug, Eq)

///|
pub impl Show for ComponentParam with fn output(self, logger) {
  logger.write_string(to_repr(self).to_string())
}

///|
pub fn ComponentParam::ComponentParam(
  name : String,
  ty : ComponentValueType,
) -> ComponentParam {
  { name, ty }
}

///|
pub struct ComponentFuncType {
  is_async : Bool
  params : Array[ComponentParam]
  result : ComponentValueType?
} derive(Debug, Eq)

///|
pub impl Show for ComponentFuncType with fn output(self, logger) {
  logger.write_string(to_repr(self).to_string())
}

///|
pub fn ComponentFuncType::ComponentFuncType(
  params : Array[ComponentParam],
  result : ComponentValueType?,
  is_async? : Bool = false,
) -> ComponentFuncType {
  { is_async, params, result }
}

///|
struct ComponentResource {
  handle : Int
  type_ : ComponentResourceType
} derive(Debug, Eq)

///|
pub fn ComponentResource::type_(
  self : ComponentResource,
) -> ComponentResourceType {
  self.type_
}

///|
pub(all) enum ComponentValue {
  Bool(Bool)
  S8(Int)
  U8(Int)
  S16(Int)
  U16(Int)
  S32(Int)
  U32(UInt)
  S64(Int64)
  U64(UInt64)
  F32(Float)
  F64(Double)
  Char(Char)
  String(String)
  ErrorContext(String)
  List(Array[ComponentValue])
  Tuple(Array[ComponentValue])
  Record(Array[(String, ComponentValue)])
  Variant(String, ComponentValue?)
  Enum(String)
  Flags(Array[String])
  OptionNone
  OptionSome(ComponentValue)
  ResultOk(ComponentValue?)
  ResultErr(ComponentValue?)
  Resource(ComponentResource)
} derive(Debug, Eq)

///|
pub impl Show for ComponentValue with fn output(self, logger) {
  logger.write_string(to_repr(self).to_string())
}

///|
pub(all) suberror ComponentRuntimeError {
  ParseFailed(String)
  ValidationFailed(String)
  InstantiationFailed(String)
  InvalidExportPath(String)
  UnknownExport(String)
  ExportNotFunction(String)
  InvalidContract(String)
  BindingTypeMismatch(
    path~ : String,
    expected~ : ComponentFuncType,
    actual~ : ComponentFuncType
  )
  ArgumentCountMismatch(expected~ : Int, actual~ : Int)
  TypeMismatch(path~ : String, expected~ : ComponentValueType, actual~ : String)
  InvocationFailed(String)
  NativeEngineUnavailable(String)
  NativeCompilationFailed(String)
  HostInstallerAlreadyConsumed
  HostContextAlreadyOwned
  HostReadinessAlreadyInstalled
  CallAlreadyActive
  RuntimeClosed
  Cancelled
  HostExit(Int)
  JsonValueError(String)
} derive(Debug, Eq)

///|
pub impl Show for ComponentRuntimeError with fn output(self, logger) {
  logger.write_string(to_repr(self).to_string())
}

///|
priv struct ComponentRuntimeState {
  linker : @runtime_impl.ComponentLinker
  wit_names : Bool
  closed : Ref[Bool]
  execution_depth : Ref[Int]
  teardown_complete : Ref[Bool]
  next_call_id : Ref[Int]
  active_calls : Map[Int, @runtime_impl.ComponentInvocation]
  host_installers : Array[ComponentHostInstaller]
}

///|
struct ComponentRuntime {
  state : ComponentRuntimeState
}

///|
struct ComponentInstance {
  inner : @runtime_impl.ComponentInstance
  runtime : ComponentRuntimeState
}

///|
struct ComponentFunction {
  instance : @runtime_impl.ComponentInstance
  runtime : ComponentRuntimeState
  name : String
  public_type : ComponentFuncType
}

///|
struct ComponentCall {
  inner : @runtime_impl.ComponentInvocation
  runtime : ComponentRuntimeState
  call_id : Int
  result_type : ComponentValueType?
  active : Ref[Bool]
}

///|
pub(all) enum ComponentCallPoll {
  Pending
  Ready(Array[ComponentValue])
} derive(Debug, Eq)

///|
pub fn ComponentRuntime::ComponentRuntime(
  engine? : ComponentEngine = native_component_engine(),
  wit_names? : Bool = true,
) -> ComponentRuntime {
  {
    state: {
      linker: @runtime_impl.ComponentLinker::with_core_execution_engine(
        engine.open_session(),
      ),
      wit_names,
      closed: Ref(false),
      execution_depth: Ref(0),
      teardown_complete: Ref(false),
      next_call_id: Ref(0),
      active_calls: Map([]),
      host_installers: [],
    },
  }
}

///|
fn ComponentRuntimeState::ensure_open(
  self : ComponentRuntimeState,
) -> Unit raise ComponentRuntimeError {
  if self.closed.val {
    raise RuntimeClosed
  }
}

///|
fn ComponentRuntimeState::register_call(
  self : ComponentRuntimeState,
  call : @runtime_impl.ComponentInvocation,
) -> Int raise ComponentRuntimeError {
  self.ensure_open()
  let call_id = self.next_call_id.val
  self.next_call_id.val = call_id + 1
  self.active_calls.set(call_id, call)
  call_id
}

///|
fn ComponentRuntimeState::retire_call(
  self : ComponentRuntimeState,
  call_id : Int,
) -> Unit {
  self.active_calls.remove(call_id)
}

///|
fn ComponentRuntimeState::begin_execution(self : ComponentRuntimeState) -> Unit {
  self.execution_depth.val = self.execution_depth.val + 1
}

///|
fn ComponentRuntimeState::finish_close(self : ComponentRuntimeState) -> Unit {
  if self.teardown_complete.val {
    return
  }
  self.teardown_complete.val = true
  for entry in self.active_calls.to_array() {
    let (_, invocation) = entry
    invocation.cancel() catch {
      _ => ()
    }
  }
  self.active_calls.clear()
  for installer in self.host_installers {
    installer.close()
  }
  self.host_installers.clear()
  self.linker.close()
}

///|
fn ComponentRuntimeState::end_execution(self : ComponentRuntimeState) -> Unit {
  if self.execution_depth.val > 0 {
    self.execution_depth.val = self.execution_depth.val - 1
  }
  if self.execution_depth.val == 0 && self.closed.val {
    self.finish_close()
  }
}

///|
pub fn ComponentRuntime::install(
  self : ComponentRuntime,
  installer : ComponentHostInstaller,
) -> Unit raise ComponentRuntimeError {
  self.state.ensure_open()
  installer.claim()
  installer.populate(self.state.linker) catch {
    HostEventLoopAlreadyInstalled => {
      installer.close()
      raise HostReadinessAlreadyInstalled
    }
    error => {
      installer.close()
      raise InstantiationFailed(error.to_string())
    }
  }
  self.state.host_installers.push(installer)
}

///|
pub fn ComponentRuntime::close(self : ComponentRuntime) -> Unit {
  if !self.state.closed.val {
    self.state.closed.val = true
    for entry in self.state.active_calls.to_array() {
      let (_, invocation) = entry
      invocation.cancel() catch {
        _ => ()
      }
    }
  }
  if self.state.execution_depth.val == 0 {
    self.state.finish_close()
  }
}

///|
pub fn ComponentRuntime::instantiate(
  self : ComponentRuntime,
  name : String,
  bytes : Bytes,
) -> ComponentInstance raise ComponentRuntimeError {
  self.state.ensure_open()
  let component = @model.parse_component(bytes) catch {
    error => raise ParseFailed(error.to_string())
  }
  self.instantiate_component(name, component)
}

///|
pub fn ComponentRuntime::instantiate_component(
  self : ComponentRuntime,
  name : String,
  component : Component,
) -> ComponentInstance raise ComponentRuntimeError {
  self.state.ensure_open()
  let validated = @component_model.validate_component_for_instantiation_with_config(
    component,
    ComponentValidationConfig(self.state.wit_names),
  ) catch {
    error => raise ValidationFailed(error.to_string())
  }
  self.state.begin_execution()
  let inner = self.state.linker.instantiate(name, validated) catch {
    error => {
      self.state.end_execution()
      match error {
        NativeEngineUnavailable(message) =>
          raise NativeEngineUnavailable(message)
        NativeCompilationFailed(message) =>
          raise NativeCompilationFailed(message)
        error => raise InstantiationFailed(error.to_string())
      }
    }
  }
  self.state.end_execution()
  if self.state.closed.val {
    raise RuntimeClosed
  }
  { inner, runtime: self.state }
}

///|
fn component_primitive_type(ty : @model.PrimValType) -> ComponentValueType {
  match ty {
    Bool => Bool
    S8 => S8
    U8 => U8
    S16 => S16
    U16 => U16
    S32 => S32
    U32 => U32
    S64 => S64
    U64 => U64
    F32 => F32
    F64 => F64
    Char => Char
    String => String
    ErrorContext => ErrorContext
  }
}

///|
fn component_resource_identity(index : Int) -> ComponentResourceType {
  { identity: "type[\{index}]" }
}

///|
fn resolve_component_value_type(
  ty : @model.ValType,
  types : Array[@model.TypeDef?],
) -> ComponentValueType raise ComponentRuntimeError {
  match ty {
    Prim(primitive) => component_primitive_type(primitive)
    TypeIdx(index) => {
      guard index >= 0 && types.get(index) is Some(Some(type_def)) else {
        raise InvalidContract("unknown component value type \{index}")
      }
      match type_def {
        DefValType(primitive) => component_primitive_type(primitive)
        List(element) => List(resolve_component_value_type(element, types))
        FixedList(element, len) =>
          FixedList(resolve_component_value_type(element, types), len)
        MapType(key, value) =>
          MapType(
            resolve_component_value_type(key, types),
            resolve_component_value_type(value, types),
          )
        Tuple(elements) => {
          let resolved = []
          for element in elements {
            resolved.push(resolve_component_value_type(element, types))
          }
          Tuple(resolved)
        }
        Record(fields) => {
          let resolved = []
          for field in fields {
            resolved.push(
              ComponentField(
                field.label,
                resolve_component_value_type(field.ty, types),
              ),
            )
          }
          Record(resolved)
        }
        Variant(cases) => {
          let resolved = []
          for case in cases {
            resolved.push(
              ComponentCase(
                case.label,
                match case.ty {
                  Some(payload) =>
                    Some(resolve_component_value_type(payload, types))
                  None => None
                },
              ),
            )
          }
          Variant(resolved)
        }
        Enum(labels) => Enum(labels.copy())
        Flags(labels) => Flags(labels.copy())
        Option(payload) => Option(resolve_component_value_type(payload, types))
        Result(ok, err) =>
          Result(
            match ok {
              Some(payload) =>
                Some(resolve_component_value_type(payload, types))
              None => None
            },
            match err {
              Some(payload) =>
                Some(resolve_component_value_type(payload, types))
              None => None
            },
          )
        Own(resource_index) => Own(component_resource_identity(resource_index))
        Borrow(resource_index) =>
          Borrow(component_resource_identity(resource_index))
        Stream(payload) =>
          Stream(
            match payload {
              Some(payload) =>
                Some(resolve_component_value_type(payload, types))
              None => None
            },
          )
        Future(payload) =>
          Future(
            match payload {
              Some(payload) =>
                Some(resolve_component_value_type(payload, types))
              None => None
            },
          )
        ResourceType(_, _, _, _) => Own(component_resource_identity(index))
        FuncType(_) | ComponentType(_) | InstanceTypeEmpty | InstanceType(_) =>
          raise InvalidContract("type[\{index}] is not a component value type")
      }
    }
  }
}

///|
fn resolve_component_func_type(
  func_type : @model.FuncType,
  types : Array[@model.TypeDef?],
) -> ComponentFuncType raise ComponentRuntimeError {
  let params = []
  for param in func_type.params {
    params.push(
      ComponentParam(param.label, resolve_component_value_type(param.ty, types)),
    )
  }
  let result = match func_type.result {
    Some(result) => Some(resolve_component_value_type(result, types))
    None => None
  }
  { is_async: func_type.is_async, params, result }
}

///|
fn component_function_parts(
  func : @runtime_impl.ComponentFunc,
) -> (@model.FuncType, Array[@model.TypeDef?]) {
  match func {
    Host(func_type, types, _) | HostAsync(func_type, types, _) =>
      (func_type, types)
    Lifted(_, func_type, _, types, _, _, _, _) => (func_type, types)
  }
}

///|
pub fn ComponentInstance::bind(
  self : ComponentInstance,
  path : String,
) -> ComponentFunction raise ComponentRuntimeError {
  self.runtime.ensure_open()
  let segments = []
  for segment in path.split("#") {
    let segment = segment.to_owned()
    if segment == "" {
      raise InvalidExportPath(path)
    }
    segments.push(segment)
  }
  if segments.length() == 0 {
    raise InvalidExportPath(path)
  }
  let mut current = self.inner
  for i in 0..<(segments.length() - 1) {
    match current.get_export(segments[i]) {
      Some(Instance(instance)) => current = instance
      Some(_) => raise ExportNotFunction(segments[i])
      None => raise UnknownExport(segments[i])
    }
  }
  let name = segments[segments.length() - 1]
  match current.get_export(name) {
    Some(Func(func)) => {
      let (raw_type, raw_types) = component_function_parts(func)
      let public_type = resolve_component_func_type(raw_type, raw_types)
      { instance: current, runtime: self.runtime, name, public_type }
    }
    Some(_) => raise ExportNotFunction(path)
    None => raise UnknownExport(path)
  }
}

///|
fn component_resource_types_compatible(
  expected : ComponentResourceType,
  actual : ComponentResourceType,
  expected_to_actual : Map[String, String],
  actual_to_expected : Map[String, String],
) -> Bool {
  match
    (
      expected_to_actual.get(expected.identity),
      actual_to_expected.get(actual.identity),
    ) {
    (Some(bound_actual), Some(bound_expected)) =>
      bound_actual == actual.identity && bound_expected == expected.identity
    (Some(bound_actual), None) =>
      if bound_actual == actual.identity {
        actual_to_expected.set(actual.identity, expected.identity)
        true
      } else {
        false
      }
    (None, Some(bound_expected)) =>
      if bound_expected == expected.identity {
        expected_to_actual.set(expected.identity, actual.identity)
        true
      } else {
        false
      }
    (None, None) => {
      expected_to_actual.set(expected.identity, actual.identity)
      actual_to_expected.set(actual.identity, expected.identity)
      true
    }
  }
}

///|
fn component_value_types_compatible(
  expected : ComponentValueType,
  actual : ComponentValueType,
  expected_to_actual : Map[String, String],
  actual_to_expected : Map[String, String],
) -> Bool {
  match (expected, actual) {
    (Bool, Bool)
    | (S8, S8)
    | (U8, U8)
    | (S16, S16)
    | (U16, U16)
    | (S32, S32)
    | (U32, U32)
    | (S64, S64)
    | (U64, U64)
    | (F32, F32)
    | (F64, F64)
    | (Char, Char)
    | (String, String)
    | (ErrorContext, ErrorContext) => true
    (List(expected), List(actual)) | (Option(expected), Option(actual)) =>
      component_value_types_compatible(
        expected, actual, expected_to_actual, actual_to_expected,
      )
    (Tuple(expected), Tuple(actual)) => {
      if expected.length() != actual.length() {
        return false
      }
      for index in 0..<expected.length() {
        if !component_value_types_compatible(
            expected[index],
            actual[index],
            expected_to_actual,
            actual_to_expected,
          ) {
          return false
        }
      }
      true
    }
    (Record(expected), Record(actual)) => {
      if expected.length() != actual.length() {
        return false
      }
      for index in 0..<expected.length() {
        if expected[index].name != actual[index].name ||
          !component_value_types_compatible(
            expected[index].ty,
            actual[index].ty,
            expected_to_actual,
            actual_to_expected,
          ) {
          return false
        }
      }
      true
    }
    (Variant(expected), Variant(actual)) => {
      if expected.length() != actual.length() {
        return false
      }
      for index in 0..<expected.length() {
        if expected[index].name != actual[index].name {
          return false
        }
        match (expected[index].ty, actual[index].ty) {
          (None, None) => ()
          (Some(expected), Some(actual)) =>
            if !component_value_types_compatible(
                expected, actual, expected_to_actual, actual_to_expected,
              ) {
              return false
            }
          _ => return false
        }
      }
      true
    }
    (Enum(expected), Enum(actual)) | (Flags(expected), Flags(actual)) =>
      expected == actual
    (Result(expected_ok, expected_err), Result(actual_ok, actual_err)) => {
      let compatible_optional = fn(
        expected : ComponentValueType?,
        actual : ComponentValueType?,
      ) -> Bool {
        match (expected, actual) {
          (None, None) => true
          (Some(expected), Some(actual)) =>
            component_value_types_compatible(
              expected, actual, expected_to_actual, actual_to_expected,
            )
          _ => false
        }
      }
      compatible_optional(expected_ok, actual_ok) &&
      compatible_optional(expected_err, actual_err)
    }
    (Own(expected), Own(actual)) | (Borrow(expected), Borrow(actual)) =>
      component_resource_types_compatible(
        expected, actual, expected_to_actual, actual_to_expected,
      )
    (Stream(expected), Stream(actual)) | (Future(expected), Future(actual)) =>
      match (expected, actual) {
        (None, None) => true
        (Some(expected), Some(actual)) =>
          component_value_types_compatible(
            expected, actual, expected_to_actual, actual_to_expected,
          )
        _ => false
      }
    _ => false
  }
}

///|
fn component_func_types_compatible(
  expected : ComponentFuncType,
  actual : ComponentFuncType,
) -> Bool {
  if expected.is_async != actual.is_async ||
    expected.params.length() != actual.params.length() {
    return false
  }
  let expected_to_actual : Map[String, String] = Map([])
  let actual_to_expected : Map[String, String] = Map([])
  for index in 0..<expected.params.length() {
    if expected.params[index].name != actual.params[index].name ||
      !component_value_types_compatible(
        expected.params[index].ty,
        actual.params[index].ty,
        expected_to_actual,
        actual_to_expected,
      ) {
      return false
    }
  }
  match (expected.result, actual.result) {
    (None, None) => true
    (Some(expected), Some(actual)) =>
      component_value_types_compatible(
        expected, actual, expected_to_actual, actual_to_expected,
      )
    _ => false
  }
}

///|
pub fn ComponentInstance::bind_typed(
  self : ComponentInstance,
  path : String,
  expected : ComponentFuncType,
) -> ComponentFunction raise ComponentRuntimeError {
  let function = self.bind(path)
  if !component_func_types_compatible(expected, function.public_type) {
    raise BindingTypeMismatch(path~, expected~, actual=function.public_type)
  }
  function
}

///|
pub fn ComponentFunction::type_(self : ComponentFunction) -> ComponentFuncType {
  self.public_type
}

///|
fn component_value_kind(value : ComponentValue) -> String {
  match value {
    Bool(_) => "bool"
    S8(_) => "s8"
    U8(_) => "u8"
    S16(_) => "s16"
    U16(_) => "u16"
    S32(_) => "s32"
    U32(_) => "u32"
    S64(_) => "s64"
    U64(_) => "u64"
    F32(_) => "f32"
    F64(_) => "f64"
    Char(_) => "char"
    String(_) => "string"
    ErrorContext(_) => "error-context"
    List(_) => "list"
    Tuple(_) => "tuple"
    Record(_) => "record"
    Variant(_, _) => "variant"
    Enum(_) => "enum"
    Flags(_) => "flags"
    OptionNone => "option.none"
    OptionSome(_) => "option.some"
    ResultOk(_) => "result.ok"
    ResultErr(_) => "result.err"
    Resource(_) => "resource"
  }
}

///|
fn component_type_mismatch(
  path : String,
  expected : ComponentValueType,
  value : ComponentValue,
) -> ComponentRuntimeError {
  TypeMismatch(path~, expected~, actual=component_value_kind(value))
}

///|
fn find_component_field(
  fields : Array[(String, ComponentValue)],
  name : String,
) -> ComponentValue? {
  for field in fields {
    if field.0 == name {
      return Some(field.1)
    }
  }
  None
}

///|
fn component_case_index(cases : Array[ComponentCase], name : String) -> Int? {
  for index, case in cases {
    if case.name == name {
      return Some(index)
    }
  }
  None
}

///|
fn component_label_index(labels : Array[String], name : String) -> Int? {
  for index, label in labels {
    if label == name {
      return Some(index)
    }
  }
  None
}

///|
fn lower_component_value(
  value : ComponentValue,
  expected : ComponentValueType,
  path : String,
) -> @runtime_impl.ComponentValue raise ComponentRuntimeError {
  match (expected, value) {
    (Bool, Bool(value)) => Bool(value)
    (S8, S8(value)) =>
      if value >= -128 && value <= 127 {
        S8(value)
      } else {
        raise TypeMismatch(path~, expected~, actual="out-of-range s8")
      }
    (U8, U8(value)) =>
      if value >= 0 && value <= 255 {
        U8(value)
      } else {
        raise TypeMismatch(path~, expected~, actual="out-of-range u8")
      }
    (S16, S16(value)) =>
      if value >= -32768 && value <= 32767 {
        S16(value)
      } else {
        raise TypeMismatch(path~, expected~, actual="out-of-range s16")
      }
    (U16, U16(value)) =>
      if value >= 0 && value <= 65535 {
        U16(value)
      } else {
        raise TypeMismatch(path~, expected~, actual="out-of-range u16")
      }
    (S32, S32(value)) => S32(value)
    (U32, U32(value)) => U32(value.reinterpret_as_int())
    (S64, S64(value)) => S64(value)
    (U64, U64(value)) => U64(value.reinterpret_as_int64())
    (F32, F32(value)) => F32(value)
    (F64, F64(value)) => F64(value)
    (Char, Char(value)) => Char(value)
    (String, String(value)) => String(value)
    (ErrorContext, ErrorContext(value)) => ErrorContext(value)
    (List(element_type), List(values)) => {
      let lowered = []
      for index, element in values {
        lowered.push(
          lower_component_value(element, element_type, "\{path}[\{index}]"),
        )
      }
      List(lowered)
    }
    (Tuple(element_types), Tuple(values)) => {
      if element_types.length() != values.length() {
        raise component_type_mismatch(path, expected, value)
      }
      let lowered = []
      for index in 0..<values.length() {
        lowered.push(
          lower_component_value(
            values[index],
            element_types[index],
            "\{path}[\{index}]",
          ),
        )
      }
      Tuple(lowered)
    }
    (Record(field_types), Record(fields)) => {
      if field_types.length() != fields.length() {
        raise component_type_mismatch(path, expected, value)
      }
      let lowered = []
      for field in field_types {
        guard find_component_field(fields, field.name) is Some(field_value) else {
          raise TypeMismatch(
            path="\{path}.\{field.name}",
            expected=field.ty,
            actual="missing",
          )
        }
        lowered.push(
          lower_component_value(field_value, field.ty, "\{path}.\{field.name}"),
        )
      }
      Tuple(lowered)
    }
    (Variant(cases), Variant(case_name, payload)) => {
      guard component_case_index(cases, case_name) is Some(index) else {
        raise component_type_mismatch(path, expected, value)
      }
      let expected_payload = cases[index].ty
      let lowered_payload = match (expected_payload, payload) {
        (None, None) => None
        (Some(payload_type), Some(payload)) =>
          Some(
            lower_component_value(payload, payload_type, "\{path}.\{case_name}"),
          )
        _ => raise component_type_mismatch(path, expected, value)
      }
      Variant(index, lowered_payload)
    }
    (Enum(labels), Enum(label)) => {
      guard component_label_index(labels, label) is Some(index) else {
        raise component_type_mismatch(path, expected, value)
      }
      U32(index)
    }
    (Flags(labels), Flags(selected)) => {
      if labels.length() > 64 {
        raise InvalidContract("flags with more than 64 labels are unsupported")
      }
      let mut bits = 0UL
      for label in selected {
        guard component_label_index(labels, label) is Some(index) else {
          raise component_type_mismatch(path, expected, value)
        }
        bits = bits | (1UL << index)
      }
      if labels.length() <= 32 {
        U32(bits.to_uint().reinterpret_as_int())
      } else {
        U64(bits.reinterpret_as_int64())
      }
    }
    (Option(_), OptionNone) => Variant(0, None)
    (Option(payload_type), OptionSome(payload)) =>
      Variant(
        1,
        Some(lower_component_value(payload, payload_type, "\{path}.some")),
      )
    (Result(ok_type, _), ResultOk(payload)) => {
      let lowered = match (ok_type, payload) {
        (None, None) => None
        (Some(payload_type), Some(payload)) =>
          Some(lower_component_value(payload, payload_type, "\{path}.ok"))
        _ => raise component_type_mismatch(path, expected, value)
      }
      Variant(0, lowered)
    }
    (Result(_, error_type), ResultErr(payload)) => {
      let lowered = match (error_type, payload) {
        (None, None) => None
        (Some(payload_type), Some(payload)) =>
          Some(lower_component_value(payload, payload_type, "\{path}.err"))
        _ => raise component_type_mismatch(path, expected, value)
      }
      Variant(1, lowered)
    }
    (Own(identity), Resource(resource))
    | (Borrow(identity), Resource(resource)) =>
      if resource.type_ == identity {
        ResourceValue(resource.handle)
      } else {
        raise component_type_mismatch(path, expected, value)
      }
    (Stream(_), Resource(resource)) =>
      if resource.type_.identity == "stream" {
        ResourceValue(resource.handle)
      } else {
        raise component_type_mismatch(path, expected, value)
      }
    (Future(_), Resource(resource)) =>
      if resource.type_.identity == "future" {
        ResourceValue(resource.handle)
      } else {
        raise component_type_mismatch(path, expected, value)
      }
    _ => raise component_type_mismatch(path, expected, value)
  }
}

///|
fn lift_component_value(
  value : @runtime_impl.ComponentValue,
  expected : ComponentValueType,
  path : String,
) -> ComponentValue raise ComponentRuntimeError {
  match (expected, value) {
    (Bool, Bool(value)) => Bool(value)
    (S8, S8(value)) => S8(value)
    (U8, U8(value)) => U8(value)
    (S16, S16(value)) => S16(value)
    (U16, U16(value)) => U16(value)
    (S32, S32(value)) => S32(value)
    (U32, U32(value)) => U32(value.reinterpret_as_uint())
    (S64, S64(value)) => S64(value)
    (U64, U64(value)) => U64(value.reinterpret_as_uint64())
    (F32, F32(value)) => F32(value)
    (F64, F64(value)) => F64(value)
    (Char, Char(value)) => Char(value)
    (String, String(value)) => String(value)
    (ErrorContext, ErrorContext(value)) => ErrorContext(value)
    (List(element_type), List(values)) => {
      let lifted = []
      for index, element in values {
        lifted.push(
          lift_component_value(element, element_type, "\{path}[\{index}]"),
        )
      }
      List(lifted)
    }
    (Tuple(element_types), Tuple(values)) => {
      if element_types.length() != values.length() {
        raise InvocationFailed(
          "component returned a malformed tuple at \{path}",
        )
      }
      let lifted = []
      for index in 0..<values.length() {
        lifted.push(
          lift_component_value(
            values[index],
            element_types[index],
            "\{path}[\{index}]",
          ),
        )
      }
      Tuple(lifted)
    }
    (Record(field_types), Tuple(values)) => {
      if field_types.length() != values.length() {
        raise InvocationFailed(
          "component returned a malformed record at \{path}",
        )
      }
      let lifted = []
      for index in 0..<values.length() {
        lifted.push(
          (
            field_types[index].name,
            lift_component_value(
              values[index],
              field_types[index].ty,
              "\{path}.\{field_types[index].name}",
            ),
          ),
        )
      }
      Record(lifted)
    }
    (Variant(cases), Variant(index, payload)) => {
      guard index >= 0 && cases.get(index) is Some(case) else {
        raise InvocationFailed(
          "component returned an unknown variant tag at \{path}",
        )
      }
      let lifted_payload = match (case.ty, payload) {
        (None, None) => None
        (Some(payload_type), Some(payload)) =>
          Some(
            lift_component_value(payload, payload_type, "\{path}.\{case.name}"),
          )
        _ =>
          raise InvocationFailed(
            "component returned a malformed variant payload at \{path}",
          )
      }
      Variant(case.name, lifted_payload)
    }
    (Enum(labels), U32(index)) => {
      guard index >= 0 && labels.get(index) is Some(label) else {
        raise InvocationFailed(
          "component returned an unknown enum tag at \{path}",
        )
      }
      Enum(label)
    }
    (Flags(labels), U32(raw)) => {
      let bits = raw.reinterpret_as_uint().to_uint64()
      let selected = []
      for index, label in labels {
        if (bits & (1UL << index)) != 0UL {
          selected.push(label)
        }
      }
      Flags(selected)
    }
    (Flags(labels), U64(raw)) => {
      let bits = raw.reinterpret_as_uint64()
      let selected = []
      for index, label in labels {
        if (bits & (1UL << index)) != 0UL {
          selected.push(label)
        }
      }
      Flags(selected)
    }
    (Option(_), Variant(0, None)) => OptionNone
    (Option(payload_type), Variant(1, Some(payload))) =>
      OptionSome(lift_component_value(payload, payload_type, "\{path}.some"))
    (Result(ok_type, _), Variant(0, payload)) =>
      ResultOk(
        match (ok_type, payload) {
          (None, None) => None
          (Some(payload_type), Some(payload)) =>
            Some(lift_component_value(payload, payload_type, "\{path}.ok"))
          _ =>
            raise InvocationFailed(
              "component returned a malformed result.ok at \{path}",
            )
        },
      )
    (Result(_, error_type), Variant(1, payload)) =>
      ResultErr(
        match (error_type, payload) {
          (None, None) => None
          (Some(payload_type), Some(payload)) =>
            Some(lift_component_value(payload, payload_type, "\{path}.err"))
          _ =>
            raise InvocationFailed(
              "component returned a malformed result.err at \{path}",
            )
        },
      )
    (Own(identity), ResourceValue(handle))
    | (Borrow(identity), ResourceValue(handle)) =>
      Resource({ handle, type_: identity })
    (Stream(_), ResourceValue(handle)) =>
      Resource({ handle, type_: { identity: "stream" } })
    (Future(_), ResourceValue(handle)) =>
      Resource({ handle, type_: { identity: "future" } })
    _ =>
      raise InvocationFailed(
        "component returned a value incompatible with \{to_repr(expected)} at \{path}",
      )
  }
}

///|
fn raise_public_invocation_error(
  error : @runtime_impl.ComponentRuntimeError,
) -> Unit raise ComponentRuntimeError {
  match error {
    NativeEngineUnavailable(message) => raise NativeEngineUnavailable(message)
    NativeCompilationFailed(message) => raise NativeCompilationFailed(message)
    Cancelled => raise Cancelled
    HostExit(status) => raise HostExit(status)
    error => raise InvocationFailed(error.to_string())
  }
}

///|
fn lift_component_results(
  raw_results : Array[@runtime_impl.ComponentValue],
  result_type : ComponentValueType?,
) -> Array[ComponentValue] raise ComponentRuntimeError {
  match result_type {
    None =>
      if raw_results.length() == 0 {
        []
      } else {
        raise InvocationFailed(
          "component returned \{raw_results.length()} values for a function with no result",
        )
      }
    Some(result_type) =>
      if raw_results.length() == 1 {
        [lift_component_value(raw_results[0], result_type, "result")]
      } else {
        raise InvocationFailed(
          "component returned \{raw_results.length()} values for a single-result function",
        )
      }
  }
}

///|
pub fn ComponentFunction::start(
  self : ComponentFunction,
  args : Array[ComponentValue],
) -> ComponentCall raise ComponentRuntimeError {
  self.runtime.ensure_open()
  if args.length() != self.public_type.params.length() {
    raise ArgumentCountMismatch(
      expected=self.public_type.params.length(),
      actual=args.length(),
    )
  }
  let lowered = []
  for index in 0..<args.length() {
    lowered.push(
      lower_component_value(
        args[index],
        self.public_type.params[index].ty,
        "argument[\{index}]",
      ),
    )
  }
  let inner = self.instance.start_exported_func(self.name, lowered) catch {
    error => {
      raise_public_invocation_error(error)
      raise InvocationFailed("unreachable")
    }
  }
  let call_id = self.runtime.register_call(inner)
  {
    inner,
    runtime: self.runtime,
    call_id,
    result_type: self.public_type.result,
    active: Ref(false),
  }
}

///|
fn ComponentCall::begin_drive(
  self : ComponentCall,
) -> Unit raise ComponentRuntimeError {
  if self.runtime.closed.val {
    raise Cancelled
  }
  if self.active.val {
    raise CallAlreadyActive
  }
  self.active.val = true
  self.runtime.begin_execution()
}

///|
fn ComponentCall::end_drive(self : ComponentCall) -> Unit {
  self.active.val = false
  self.runtime.end_execution()
}

///|
pub fn ComponentCall::poll(
  self : ComponentCall,
) -> ComponentCallPoll raise ComponentRuntimeError {
  self.begin_drive()
  let polled = self.inner.poll() catch {
    error => {
      self.end_drive()
      self.runtime.retire_call(self.call_id)
      raise_public_invocation_error(error)
      raise InvocationFailed("unreachable")
    }
  }
  self.end_drive()
  if self.runtime.closed.val {
    self.runtime.retire_call(self.call_id)
    raise Cancelled
  }
  match polled {
    InvocationPending => Pending
    InvocationReady(results) => {
      self.runtime.retire_call(self.call_id)
      Ready(lift_component_results(results, self.result_type))
    }
  }
}

///|
pub fn ComponentCall::wait(
  self : ComponentCall,
) -> Array[ComponentValue] raise ComponentRuntimeError {
  self.begin_drive()
  let results = self.inner.wait() catch {
    error => {
      self.end_drive()
      self.runtime.retire_call(self.call_id)
      raise_public_invocation_error(error)
      raise InvocationFailed("unreachable")
    }
  }
  self.end_drive()
  if self.runtime.closed.val {
    self.runtime.retire_call(self.call_id)
    raise Cancelled
  }
  self.runtime.retire_call(self.call_id)
  lift_component_results(results, self.result_type)
}

///|
pub async fn ComponentCall::join(
  self : ComponentCall,
) -> Array[ComponentValue] raise ComponentRuntimeError {
  self.begin_drive()
  let results = self.inner.join() catch {
    error => {
      self.end_drive()
      self.runtime.retire_call(self.call_id)
      raise_public_invocation_error(error)
      raise InvocationFailed("unreachable")
    }
  }
  self.end_drive()
  if self.runtime.closed.val {
    self.runtime.retire_call(self.call_id)
    raise Cancelled
  }
  self.runtime.retire_call(self.call_id)
  lift_component_results(results, self.result_type)
}

///|
pub fn ComponentCall::cancel(
  self : ComponentCall,
) -> Unit raise ComponentRuntimeError {
  self.inner.cancel() catch {
    error => {
      self.runtime.retire_call(self.call_id)
      raise_public_invocation_error(error)
    }
  }
  self.runtime.retire_call(self.call_id)
}

///|
pub fn ComponentFunction::call(
  self : ComponentFunction,
  args : Array[ComponentValue],
) -> Array[ComponentValue] raise ComponentRuntimeError {
  self.start(args).wait()
}

///|
fn component_json_integer_text(json : Json) -> String? {
  match json {
    Number(number, repr~) => Some(repr.unwrap_or_else(() => number.to_string()))
    String(value) => Some(value)
    _ => None
  }
}

///|
fn component_json_signed(
  json : Json,
  min : Int64,
  max : Int64,
  expected : String,
) -> Int64 raise ComponentRuntimeError {
  guard component_json_integer_text(json) is Some(text) else {
    raise JsonValueError("expected \{expected} integer")
  }
  let value = @string.parse_int64(text) catch {
    _ => raise JsonValueError("invalid \{expected} integer '\{text}'")
  }
  if value < min || value > max {
    raise JsonValueError("\{expected} integer is out of range")
  }
  value
}

///|
fn component_json_unsigned(
  json : Json,
  max : UInt64,
  expected : String,
) -> UInt64 raise ComponentRuntimeError {
  guard component_json_integer_text(json) is Some(text) else {
    raise JsonValueError("expected \{expected} integer")
  }
  let value = @string.parse_uint64(text) catch {
    _ => raise JsonValueError("invalid \{expected} integer '\{text}'")
  }
  if value > max {
    raise JsonValueError("\{expected} integer is out of range")
  }
  value
}

///|
fn component_json_float(
  json : Json,
  expected : String,
) -> Double raise ComponentRuntimeError {
  match json {
    Number(value, ..) => value
    String(value) =>
      match value {
        "nan" => 0.0 / 0.0
        "inf" => 1.0 / 0.0
        "-inf" => -1.0 / 0.0
        _ =>
          @string.parse_double(value) catch {
            _ => raise JsonValueError("invalid \{expected} value '\{value}'")
          }
      }
    _ => raise JsonValueError("expected \{expected} number")
  }
}

///|
fn component_json_single_char(json : Json) -> Char raise ComponentRuntimeError {
  guard json is String(value) else {
    raise JsonValueError("expected char string")
  }
  let mut result : Char? = None
  for char in value {
    if result is Some(_) {
      raise JsonValueError("expected exactly one Unicode scalar value")
    }
    result = Some(char)
  }
  result.unwrap_or_else(() => {
    raise JsonValueError("expected exactly one Unicode scalar value")
  })
}

///|
fn component_json_payload(
  object : Map[String, Json],
  label : String,
  payload_type : ComponentValueType?,
) -> ComponentValue? raise ComponentRuntimeError {
  match (payload_type, object.get("value")) {
    (None, None) => None
    (None, Some(Null)) => None
    (Some(payload_type), Some(payload)) =>
      Some(component_value_from_json(payload, payload_type))
    (None, Some(_)) =>
      raise JsonValueError("\{label} does not accept a payload")
    (Some(_), None) => raise JsonValueError("\{label} requires a payload")
  }
}

///|
pub fn component_value_from_json(
  json : Json,
  expected : ComponentValueType,
) -> ComponentValue raise ComponentRuntimeError {
  match expected {
    Bool =>
      match json {
        True => Bool(true)
        False => Bool(false)
        _ => raise JsonValueError("expected bool")
      }
    S8 => S8(component_json_signed(json, -128L, 127L, "s8").to_int())
    U8 => U8(component_json_unsigned(json, 255UL, "u8").to_int())
    S16 => S16(component_json_signed(json, -32768L, 32767L, "s16").to_int())
    U16 => U16(component_json_unsigned(json, 65535UL, "u16").to_int())
    S32 =>
      S32(
        component_json_signed(json, -2147483648L, 2147483647L, "s32").to_int(),
      )
    U32 => U32(component_json_unsigned(json, 4294967295UL, "u32").to_uint())
    S64 =>
      S64(
        component_json_signed(
          json,
          -9223372036854775807L - 1L,
          9223372036854775807L,
          "s64",
        ),
      )
    U64 => U64(component_json_unsigned(json, 18446744073709551615UL, "u64"))
    F32 => F32(Float::from_double(component_json_float(json, "f32")))
    F64 => F64(component_json_float(json, "f64"))
    Char => Char(component_json_single_char(json))
    String =>
      match json {
        String(value) => String(value)
        _ => raise JsonValueError("expected string")
      }
    ErrorContext =>
      match json {
        String(value) => ErrorContext(value)
        _ => raise JsonValueError("expected error-context string")
      }
    List(element_type) =>
      match json {
        Array(items) => {
          let values = []
          for item in items {
            values.push(component_value_from_json(item, element_type))
          }
          List(values)
        }
        _ => raise JsonValueError("expected list array")
      }
    FixedList(element_type, len) =>
      match json {
        Array(items) => {
          if items.length() != len {
            raise JsonValueError("fixed-length list length mismatch")
          }
          let values = []
          for item in items {
            values.push(component_value_from_json(item, element_type))
          }
          List(values)
        }
        _ => raise JsonValueError("expected fixed-length list array")
      }
    MapType(key_type, value_type) =>
      match json {
        Array(entries) => {
          let values = []
          for entry in entries {
            guard entry is Array([key, value]) else {
              raise JsonValueError("expected map entry pair")
            }
            values.push(
              ComponentValue::Tuple([
                component_value_from_json(key, key_type),
                component_value_from_json(value, value_type),
              ]),
            )
          }
          List(values)
        }
        _ => raise JsonValueError("expected map entry array")
      }
    Tuple(element_types) =>
      match json {
        Array(items) => {
          if items.length() != element_types.length() {
            raise JsonValueError("tuple length mismatch")
          }
          let values = []
          for index in 0..<items.length() {
            values.push(
              component_value_from_json(items[index], element_types[index]),
            )
          }
          Tuple(values)
        }
        _ => raise JsonValueError("expected tuple array")
      }
    Record(field_types) =>
      match json {
        Object(object) => {
          if object.length() != field_types.length() {
            raise JsonValueError("record field count mismatch")
          }
          let fields = []
          for field in field_types {
            guard object.get(field.name) is Some(value) else {
              raise JsonValueError("missing record field '\{field.name}'")
            }
            fields.push(
              (field.name, component_value_from_json(value, field.ty)),
            )
          }
          Record(fields)
        }
        _ => raise JsonValueError("expected record object")
      }
    Variant(cases) =>
      match json {
        Object(object) => {
          guard object.get("case") is Some(String(case_name)) else {
            raise JsonValueError("variant requires a string 'case'")
          }
          guard component_case_index(cases, case_name) is Some(index) else {
            raise JsonValueError("unknown variant case '\{case_name}'")
          }
          Variant(
            case_name,
            component_json_payload(object, "variant case", cases[index].ty),
          )
        }
        _ => raise JsonValueError("expected variant object")
      }
    Enum(labels) =>
      match json {
        String(label) =>
          if component_label_index(labels, label) is Some(_) {
            Enum(label)
          } else {
            raise JsonValueError("unknown enum case '\{label}'")
          }
        _ => raise JsonValueError("expected enum case string")
      }
    Flags(labels) =>
      match json {
        Array(items) => {
          let selected = []
          for item in items {
            guard item is String(label) else {
              raise JsonValueError("expected flag name string")
            }
            if component_label_index(labels, label) is None {
              raise JsonValueError("unknown flag '\{label}'")
            }
            selected.push(label)
          }
          Flags(selected)
        }
        _ => raise JsonValueError("expected flags array")
      }
    Option(payload_type) =>
      match json {
        Null => OptionNone
        Object(object) =>
          match object.get("some") {
            Some(payload) =>
              OptionSome(component_value_from_json(payload, payload_type))
            None => raise JsonValueError("option object requires 'some'")
          }
        _ => OptionSome(component_value_from_json(json, payload_type))
      }
    Result(ok_type, error_type) =>
      match json {
        Object(object) =>
          match (object.get("ok"), object.get("err")) {
            (Some(payload), None) =>
              ResultOk(
                match ok_type {
                  None =>
                    if payload is Null {
                      None
                    } else {
                      raise JsonValueError("result.ok has no payload")
                    }
                  Some(payload_type) =>
                    Some(component_value_from_json(payload, payload_type))
                },
              )
            (None, Some(payload)) =>
              ResultErr(
                match error_type {
                  None =>
                    if payload is Null {
                      None
                    } else {
                      raise JsonValueError("result.err has no payload")
                    }
                  Some(payload_type) =>
                    Some(component_value_from_json(payload, payload_type))
                },
              )
            _ =>
              raise JsonValueError(
                "result object requires exactly one of 'ok' or 'err'",
              )
          }
        _ => raise JsonValueError("expected result object")
      }
    Own(_) | Borrow(_) | Stream(_) | Future(_) =>
      raise JsonValueError("resource values cannot be created from JSON")
  }
}

///|
pub fn parse_component_value_json(
  text : String,
  expected : ComponentValueType,
) -> ComponentValue raise ComponentRuntimeError {
  let json = @json.parse(text) catch {
    error => raise JsonValueError(error.to_string())
  }
  component_value_from_json(json, expected)
}

///|
fn component_optional_json(value : ComponentValue?) -> Json {
  match value {
    Some(value) => component_value_to_json(value)
    None => Json::null()
  }
}

///|
fn component_float_to_json(value : Double) -> Json {
  if value.is_nan() {
    Json::string("nan")
  } else if value == 1.0 / 0.0 {
    Json::string("inf")
  } else if value == -1.0 / 0.0 {
    Json::string("-inf")
  } else {
    Json::number(value)
  }
}

///|
pub fn component_value_to_json(value : ComponentValue) -> Json {
  match value {
    Bool(value) => Json::boolean(value)
    S8(value) | U8(value) | S16(value) | U16(value) | S32(value) =>
      Json::number(value.to_double(), repr=value.to_string())
    U32(value) => Json::number(value.to_double(), repr=value.to_string())
    S64(value) => Json::number(value.to_double(), repr=value.to_string())
    U64(value) => Json::number(value.to_double(), repr=value.to_string())
    F32(value) => component_float_to_json(value.to_double())
    F64(value) => component_float_to_json(value)
    Char(value) => Json::string(value.to_string())
    String(value) | ErrorContext(value) => Json::string(value)
    List(values) | Tuple(values) => {
      let items = []
      for value in values {
        items.push(component_value_to_json(value))
      }
      Json::array(items)
    }
    Record(fields) => {
      let object : Map[String, Json] = Map([])
      for field in fields {
        object.set(field.0, component_value_to_json(field.1))
      }
      Json::object(object)
    }
    Variant(case_name, payload) => {
      let object : Map[String, Json] = Map([])
      object.set("case", Json::string(case_name))
      if payload is Some(payload) {
        object.set("value", component_value_to_json(payload))
      }
      Json::object(object)
    }
    Enum(label) => Json::string(label)
    Flags(labels) => {
      let items = []
      for label in labels {
        items.push(Json::string(label))
      }
      Json::array(items)
    }
    OptionNone => Json::null()
    OptionSome(payload) => {
      let object : Map[String, Json] = Map([])
      object.set("some", component_value_to_json(payload))
      Json::object(object)
    }
    ResultOk(payload) => {
      let object : Map[String, Json] = Map([])
      object.set("ok", component_optional_json(payload))
      Json::object(object)
    }
    ResultErr(payload) => {
      let object : Map[String, Json] = Map([])
      object.set("err", component_optional_json(payload))
      Json::object(object)
    }
    Resource(resource) => {
      let object : Map[String, Json] = Map([])
      object.set("resource-type", Json::string(resource.type_.identity))
      object.set(
        "handle",
        Json::number(
          resource.handle.to_double(),
          repr=resource.handle.to_string(),
        ),
      )
      Json::object(object)
    }
  }
}

///|
pub fn component_values_to_json(values : Array[ComponentValue]) -> Json {
  let items = []
  for value in values {
    items.push(component_value_to_json(value))
  }
  Json::array(items)
}
