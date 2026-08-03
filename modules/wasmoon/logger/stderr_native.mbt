///|
#borrow(buf)
extern "c" fn c_write_stderr(buf : FixedArray[Byte], count : Int) -> Int = "wasmoon_logger_write_stderr"

///|
/// Write a line to the process's standard error.
fn write_stderr_line(msg : String) -> Unit {
  let encoded = @utf8.encode(msg + "\n")
  let buf = FixedArray::makei(encoded.length(), fn(i) { encoded[i] })
  c_write_stderr(buf, encoded.length()) |> ignore
}
