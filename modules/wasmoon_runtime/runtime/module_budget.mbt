///|
/// Iterative admission of host-built ASTs before validation/canonicalization.
/// Units count declarations, instructions, locals, type members and payload
/// bytes. They bound accepted shape, not the optimizer's exact instruction count.
fn ResourceBudget::admit_module(
  self : ResourceBudget,
  module_ : @types.Module,
) -> ResourceLease raise RuntimeError {
  let lease = self.reserve(CompilationUnits, 0L)
  errdefer lease.release()
  let used = Ref(0L)
  fn charge(amount : Int32) -> Unit raise RuntimeError {
    let next = used.val + amount.to_int64()
    guard lease.reservation.resize(next) else {
      raise ResourceLimitExceeded(CompilationUnits)
    }
    used.val = next
  }
  fn expression(
    body : ReadOnlyArray[@types.Instruction],
  ) -> Unit raise RuntimeError {
    let stack : Array[(ReadOnlyArray[@types.Instruction], Int32, Int32)] = [
      (body, 0, 0),
    ]
    while stack.pop() is Some((body, index, depth)) {
      if index >= body.length() {
        continue
      }
      charge(1)
      stack.push((body, index + 1, depth))
      fn child(
        body : ReadOnlyArray[@types.Instruction],
      ) -> Unit raise RuntimeError {
        guard depth < self.compilation_depth else {
          raise ResourceLimitExceeded(CompilationUnits)
        }
        stack.push((body, 0, depth + 1))
      }
      match body[index] {
        Block(_, body) | Loop(_, body) => child(body)
        If(_, yes, no) => {
          child(no)
          child(yes)
        }
        TryTable(_, handlers, body) => {
          charge(handlers.length())
          child(body)
        }
        BrTable(labels, _) => charge(labels.length())
        SelectTyped(types) => charge(types.length())
        Resume(_, handlers)
        | ResumeThrow(_, _, handlers)
        | ResumeThrowRef(_, handlers) => charge(handlers.length())
        _ => ()
      }
    }
  }
  charge(module_.types.length())
  charge(module_.type_rec_groups.length())
  charge(module_.imports.length())
  charge(module_.funcs.length())
  charge(module_.tables.length())
  charge(module_.memories.length())
  charge(module_.globals.length())
  charge(module_.exports.length())
  charge(module_.elems.length())
  charge(module_.codes.length())
  charge(module_.datas.length())
  charge(module_.tags.length())
  charge(module_.func_names.length())
  for type_ in module_.types {
    charge(type_.supertypes.length())
    match type_.composite {
      Func(type_) => {
        charge(type_.params.length())
        charge(type_.results.length())
      }
      Struct(type_) => charge(type_.fields.length())
      Array(_) | Cont(_) => charge(1)
    }
  }
  for import_ in module_.imports {
    charge(import_.mod_name.length())
    charge(import_.name.length())
  }
  for export_ in module_.exports {
    charge(export_.name.length())
  }
  for _, name in module_.func_names {
    charge(name.length())
  }
  for table in module_.tables {
    if table.init is Some(body) {
      expression(body)
    }
  }
  for global in module_.globals {
    expression(global.init)
  }
  for element in module_.elems {
    if element.mode is Active(_, offset) {
      expression(offset)
    }
    charge(element.init.length())
    for body in element.init {
      expression(body)
    }
  }
  for data in module_.datas {
    charge(data.init.length())
    expression(data.offset)
  }
  for code in module_.codes {
    charge(code.locals.length())
    expression(code.body)
  }
  lease
}

///|
pub fn Store::check_instance_admission(
  self : Store,
  admission : InstanceAdmission,
  validated? : @validator.ValidatedModule,
) -> Unit raise RuntimeError {
  self.ensure_open()
  guard physical_equal(admission.owner, self.closed) else { raise ForeignStore }
  guard !admission.consumed.val else { raise InvalidHandle }
  if validated is Some(validated) && self.resource_budget is Some(budget) {
    if admission.validated is Some(accepted) &&
      physical_equal(accepted, validated) {
      return
    }
    // A token for a smaller module cannot authorize a different validated AST.
    // Return this token's provisional work charge before replacing it.
    if admission.compilation is Some(previous) {
      previous.release()
    }
    admission.compilation = None
    admission.compilation = Some(budget.admit_module(validated.snapshot()))
    admission.validated = Some(validated)
  }
}

///|
/// Bound binary decoding before expanded locals/type vectors are allocated.
/// The returned AST belongs to the caller; its lifetime is not charged to the
/// Store. Instantiation separately admits and retains its compilation units.
pub fn Store::decode_module(self : Store, bytes : Bytes) -> @types.Module raise {
  self.ensure_open()
  guard self.resource_budget is Some(budget) else {
    return @parser.parse_module(bytes)
  }
  let input = budget.reserve(InputBytes, bytes.length().to_int64())
  defer input.release()
  let work = budget.reserve(CompilationUnits, 0L)
  defer work.release()
  let used = Ref(0L)
  @parser.parse_module(
    bytes,
    limits={
      max_input_bytes: bytes.length().to_int64(),
      max_work: 0x7FFF_FFFF_FFFF_FFFFL,
      max_depth: budget.compilation_depth,
    },
    admit_work=Some(fn(amount) {
      let next = used.val + amount
      if !work.reservation.resize(next) {
        return false
      }
      used.val = next
      true
    }),
  ) catch {
    error if error.is_resource_exhaustion() =>
      raise ResourceLimitExceeded(CompilationUnits)
    error => raise error
  }
}

///|
/// Temporarily admit validation or compilation of a caller-owned AST.
pub fn Store::admit_module_work(
  self : Store,
  module_ : @types.Module,
) -> ResourceLease? raise RuntimeError {
  self.ensure_open()
  self.resource_budget.map(budget => budget.admit_module(module_))
}
