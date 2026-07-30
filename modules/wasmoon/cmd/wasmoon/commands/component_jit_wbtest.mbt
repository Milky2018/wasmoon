///|
priv struct ComponentJITExecutionEvidence {
  native_run_to_return : Ref[Int]
  native_resumable : Ref[Int]
  explicit_interpreter : Ref[Int]
}

///|
fn component_jit_evidence_for_test() -> ComponentJITExecutionEvidence {
  {
    native_run_to_return: Ref(0),
    native_resumable: Ref(0),
    explicit_interpreter: Ref(0),
  }
}

///|
fn ComponentJITExecutionEvidence::record(
  self : ComponentJITExecutionEvidence,
  event : @component.NativeComponentExecutionEvent,
) -> Unit {
  match event {
    RunToReturn =>
      self.native_run_to_return.val = self.native_run_to_return.val + 1
    Resumable => self.native_resumable.val = self.native_resumable.val + 1
    ExplicitInterpreter =>
      self.explicit_interpreter.val = self.explicit_interpreter.val + 1
  }
}

///|
test "component JIT records typed execution evidence" {
  let evidence = component_jit_evidence_for_test()
  evidence.record(RunToReturn)
  evidence.record(Resumable)
  evidence.record(ExplicitInterpreter)
  debug_inspect(
    (
      evidence.native_run_to_return.val,
      evidence.native_resumable.val,
      evidence.explicit_interpreter.val,
    ),
    content="(1, 1, 1)",
  )
}
