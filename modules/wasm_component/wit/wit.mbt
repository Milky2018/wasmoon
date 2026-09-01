///|
/// Minimal WIT (WebAssembly Interface Types) text parser/printer used by wasmoon-tools.
///
/// This package was originally implemented in a single file (wit/wit.mbt).
/// It has been split into multiple files for maintainability:
/// - error.mbt: WitError
/// - ast.mbt: AST definitions
/// - parser.mbt: lexer/parser + parse_package
/// - format.mbt: format_package
/// - json.mbt: package_to_json
/// - resolve.mbt: desugar/merge/resolve/importize helpers
