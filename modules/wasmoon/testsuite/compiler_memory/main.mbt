///|
fn main raise {
  let args = @env.args()
  guard args.length() == 3 else { abort("expected input.wasm output.artifact") }
  let bytes = @fs.read_file_to_bytes(args[1])
  let started = @perf.tick_now()
  let result = @commands.compile_module(bytes)
  let elapsed = @perf.elapsed_us(started)
  guard result is Some(artifact) else { abort("compilation failed") }
  let encoded = @artifact.encode(artifact)
  @fs.write_bytes_to_file(args[2], encoded)
  println(elapsed)
}
