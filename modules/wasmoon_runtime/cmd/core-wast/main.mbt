///|
fn main {
  let args = @env.args()
  if args.length() != 2 {
    println("usage: core-wast FILE")
    @sys.exit(2)
  }
  try {
    let result = @wast.run_script(@fs.read_file_to_string(args[1]))
    for failure in result.failures {
      println(failure)
    }
    for unsupported in result.unsupported {
      println("Unsupported: " + unsupported)
    }
    println("Passed: \{result.passed}")
    println("Failed: \{result.failed}")
    println("Unsupported: \{result.unsupported.length()}")
    if result.failed != 0 {
      @sys.exit(1)
    }
    if !result.unsupported.is_empty() {
      @sys.exit(3)
    }
  } catch {
    error => {
      println(error.to_string())
      @sys.exit(2)
    }
  }
}
