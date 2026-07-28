///|
test "Preview 3 inherited stdin source reads fd zero through the reactor" {
  let path = "/tmp/wasmoon-preview3-inherited-stdin"
  guard @wasi.native_open(path, [WriteOnly, Create, Truncate], 0o600)
    is Some(output_fd) else {
    return fail("could not create inherited stdin fixture")
  }
  let input = b"hello"
  let buffer = FixedArray::makei(input.length(), i => input[i])
  guard @wasi.native_write(output_fd, buffer, buffer.length()) is Some(written) &&
    written == buffer.length() else {
    @wasi.native_close(output_fd) |> ignore
    return fail("could not write inherited stdin fixture")
  }
  @wasi.native_close(output_fd) |> ignore
  guard @wasi.native_open(path, [ReadOnly], 0) is Some(input_fd) else {
    return fail("could not open inherited stdin fixture")
  }
  defer @wasi.native_close(input_fd) |> ignore
  guard @wasi.native_dup(0) is Some(saved_stdin) else {
    return fail("could not preserve stdin")
  }
  defer @wasi.native_close(saved_stdin) |> ignore
  guard @wasi.native_dup2(input_fd, 0) else {
    return fail("could not redirect stdin")
  }
  defer @wasi.native_dup2(saved_stdin, 0) |> ignore
  let ctx = WasiComponentCtxBuilder().inherit_stdin().build()
  defer ctx.close()
  guard ctx.get_resource(ctx.stdin_rep) is Some(InputStream(state)) &&
    state.native_fd is Some(fd) else {
    return fail("inherited stdin is not backed by fd zero")
  }
  let source = Preview3StdinSource::new(ctx, state, fd)
  debug_inspect(
    [source.pull(5), source.pull(5)],
    content="[Values([U8(104), U8(101), U8(108), U8(108), U8(111)]), Closed]",
  )
}
