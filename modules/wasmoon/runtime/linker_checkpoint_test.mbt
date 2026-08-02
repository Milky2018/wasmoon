///|
test "a Linker rejects another Linker's checkpoint" {
  let linker_a = @runtime.Linker::Linker()
  let checkpoint = linker_a.checkpoint()
  let linker_b = @runtime.Linker::Linker()
  linker_b.register("kept", @runtime.ModuleInstance::ModuleInstance())
  linker_b.rollback_to(checkpoint) |> ignore
  debug_inspect(linker_b.get_module("kept") is Some(_), content="true")
  linker_a.close()
  linker_b.close()
}
