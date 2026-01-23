///|
test "wit: parse single file and format" {
  let src = "package docs:calculator@0.1.0;\n\n" +
    "interface add {\n" +
    "  add: func(x: u32, y: u32) -> u32;\n" +
    "}\n\n" +
    "world adder {\n" +
    "  export add;\n" +
    "}\n"
  let pkg = @wit.parse_package(src) catch { _ => panic() }
  inspect(
    @wit.format_package(pkg),
    content="package docs:calculator@0.1.0;\n\n" +
      "interface add {\n" +
      "  add: func(x: u32, y: u32) -> u32;\n" +
      "}\n\n" +
      "world adder {\n" +
      "  export add;\n" +
      "}\n",
  )
}

///|
test "wit: json output is stable" {
  let src = "package a:b@1.2.3;\n\n" +
    "interface i {\n" +
    "  type t = list<u8>;\n" +
    "  f: func(x: t) -> u32;\n" +
    "}\n"
  let pkg = @wit.parse_package(src) catch { _ => panic() }
  inspect(
    @wit.package_to_json(pkg),
    content="{\"name\":\"a:b\",\"version\":\"1.2.3\",\"nested\":[],\"items\":[{\"kind\":\"interface\",\"name\":\"i\",\"items\":[{\"kind\":\"type\",\"name\":\"t\"},{\"kind\":\"func\",\"name\":\"f\"}]}]}",
  )
}
