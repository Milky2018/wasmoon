///|
/// Decode one WAT string literal into bytes, preserving non-UTF-8 payloads.
/// The input includes its quotes; names must additionally validate UTF-8.
pub fn parse_string_literal(input : String) -> Bytes raise WatError {
  let lexer = Lexer::Lexer(input)
  let token = lexer.next_token()
  guard token.token is String_(value) else {
    raise UnexpectedToken("expected string literal", token.to_loc())
  }
  let end = lexer.next_token()
  guard end.token is Eof else {
    raise UnexpectedToken("trailing tokens after string literal", end.to_loc())
  }
  Bytes::from_array(value.iter().map(c => c.to_int().to_byte()).collect())
}
