///|
/// Preflight shallow section frames iteratively before the recursive component
/// decoder and validator run. Core expansion is metered before validation too.
pub fn ComponentLinker::validate_input(
  self : ComponentLinker,
  bytes : Bytes,
  wit_names~ : Bool = true,
  component_implements~ : Bool = true,
) -> @component_validator.ValidatedComponent raise {
  self.core_execution_lifecycle.ensure_open()
  let store = self.get_store()
  let leases : Array[@runtime.ResourceLease] = []
  defer (for lease in leases {
    lease.release()
  })
  if store.resource_budget is Some(budget) {
    leases.push(
      budget.reserve(InputBytes, bytes.length().to_int64()) catch {
        error => raise ComponentRuntimeError::from_core(error)
      },
    )
    let work = budget.reserve(CompilationUnits, 0L) catch {
      error => raise ComponentRuntimeError::from_core(error)
    }
    leases.push(work)
    let used = Ref(0L)
    let stack : Array[(Bytes, Int32)] = [(bytes, 0)]
    while stack.pop() is Some((input, depth)) {
      guard depth <= budget.compilation_depth else {
        raise ComponentRuntimeError::ResourceLimitExceeded(CompilationUnits)
      }
      let next = used.val + input.length().to_int64()
      guard work.resize(next) else {
        raise ComponentRuntimeError::ResourceLimitExceeded(CompilationUnits)
      }
      used.val = next
      let binary = @component.parse_component_binary(input) catch {
        error =>
          raise ComponentRuntimeError::ComponentParseError(error.to_string())
      }
      for section in binary.sections {
        match section.id {
          4 => stack.push((section.payload, depth + 1))
          1 => {
            let module_ = store.decode_module(section.payload) catch {
              error =>
                match @runtime.RuntimeError::from_error(error) {
                  Some(error) => raise ComponentRuntimeError::from_core(error)
                  None =>
                    raise ComponentRuntimeError::CoreModuleParseError(
                      error.to_string(),
                    )
                }
            }
            if (store.admit_module_work(module_) catch {
                error => raise ComponentRuntimeError::from_core(error)
              })
              is Some(lease) {
              leases.push(lease)
            }
          }
          _ => ()
        }
      }
    }
  }
  let component = @component.parse_component(bytes) catch {
    error => raise ComponentRuntimeError::ComponentParseError(error.to_string())
  }
  @component_validator.validate_component_for_instantiation_with_config(
    component,
    ComponentValidationConfig(wit_names, component_implements~),
  )
}
