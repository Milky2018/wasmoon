///|
/// Result of parsing a func definition - can be a regular function or an inline import
priv enum FuncDefResult {
  /// Regular function definition: (type_idx, code, export_name)
  FuncDef(Int, @types.FunctionCode, String?)
  /// Inline import: the import definition
  InlineImport(@types.Import, String?) // import, optional export name
}

///|
/// Result of parsing a global definition - can be a regular global or an inline import
priv enum GlobalDefResult {
  /// Regular global definition: (global, export_name)
  GlobalDef(@types.Global, String?)
  /// Inline import: the import definition
  GlobalImport(@types.Import, String?) // import, optional export name
}

///|
/// Result of parsing a memory definition - can be a regular memory or an inline import
priv enum MemoryDefResult {
  /// Regular memory definition: (memory_type, export_name)
  MemoryDef(@types.MemoryType, String?)
  /// Inline import: the import definition
  MemoryImport(@types.Import, String?) // import, optional export name
}

///|
/// WAT Parser
priv struct Parser {
  lexer : Lexer
  mut current : Token
  // Name resolution maps
  func_names : Map[String, Int]
  type_names : Map[String, Int]
  local_names : Map[String, Int]
  global_names : Map[String, Int]
  memory_names : Map[String, Int]
  table_names : Map[String, Int]
  // Label stack for block/loop/if - stores (name, depth) pairs
  // depth is the index from the innermost block (0 = current block)
  label_stack : Array[String?]
}

///|
fn Parser::new(input : String) -> Parser raise WatError {
  let lexer = Lexer::new(input)
  let first_token = lexer.next_token()
  {
    lexer,
    current: first_token,
    func_names: {},
    type_names: {},
    local_names: {},
    global_names: {},
    memory_names: {},
    table_names: {},
    label_stack: [],
  }
}

///|
/// Get the current token's source location
fn Parser::loc(self : Parser) -> SourceLoc {
  self.lexer.current_loc()
}

///|
/// Push a label onto the label stack (for block/loop/if)
fn Parser::push_label(self : Parser, name : String?) -> Unit {
  self.label_stack.push(name)
}

///|
/// Pop a label from the label stack
fn Parser::pop_label(self : Parser) -> Unit {
  self.label_stack.pop() |> ignore
}

///|
/// Resolve a named label to its depth index
/// Returns the number of blocks we need to break out of
fn Parser::resolve_label(self : Parser, name : String) -> Int? {
  // Search from the top of the stack (most recent block)
  for i = self.label_stack.length() - 1; i >= 0; i = i - 1 {
    if self.label_stack[i] is Some(label_name) && label_name == name {
      // Depth is distance from top of stack
      return Some(self.label_stack.length() - 1 - i)
    }
  }
  None
}

///|
fn Parser::advance(self : Parser) -> Unit raise WatError {
  self.current = self.lexer.next_token()
}

///|
/// Skip tokens until we find the matching closing parenthesis
/// Assumes we're currently inside a parenthesized expression
fn Parser::skip_to_matching_rparen(self : Parser) -> Unit raise WatError {
  let mut depth = 1
  while depth > 0 && self.current != Eof {
    match self.current {
      LParen => {
        depth = depth + 1
        self.advance()
      }
      RParen => {
        depth = depth - 1
        if depth > 0 {
          self.advance()
        }
      }
      _ => self.advance()
    }
  }
  if self.current == RParen {
    self.advance()
  }
}

///|
fn Parser::expect_lparen(self : Parser) -> Unit raise WatError {
  match self.current {
    LParen => self.advance()
    _ => raise UnexpectedToken("expected '(', got \{self.current}", self.loc())
  }
}

///|
fn Parser::expect_rparen(self : Parser) -> Unit raise WatError {
  match self.current {
    RParen => self.advance()
    _ => raise UnexpectedToken("expected ')', got \{self.current}", self.loc())
  }
}

///|
fn Parser::expect_keyword(self : Parser, kw : String) -> Unit raise WatError {
  match self.current {
    Keyword(k) =>
      if k == kw {
        self.advance()
      } else {
        raise UnexpectedToken("expected '\{kw}', got '\{k}'", self.loc())
      }
    _ =>
      raise UnexpectedToken("expected '\{kw}', got \{self.current}", self.loc())
  }
}

///|
fn Parser::parse_u32(self : Parser) -> Int raise WatError {
  match self.current {
    Number(s) => {
      self.advance()
      parse_int(s)
    }
    _ =>
      raise UnexpectedToken("expected number, got \{self.current}", self.loc())
  }
}

///|
fn Parser::parse_i32(self : Parser) -> Int raise WatError {
  match self.current {
    Number(s) => {
      self.advance()
      parse_int(s)
    }
    _ =>
      raise UnexpectedToken("expected number, got \{self.current}", self.loc())
  }
}

///|
fn Parser::parse_i64(self : Parser) -> Int64 raise WatError {
  match self.current {
    Number(s) => {
      self.advance()
      parse_int64(s)
    }
    _ =>
      raise UnexpectedToken("expected number, got \{self.current}", self.loc())
  }
}

///|
fn Parser::parse_f32(self : Parser) -> Float raise WatError {
  match self.current {
    Number(s) => {
      self.advance()
      parse_float32(s)
    }
    _ =>
      raise UnexpectedToken("expected number, got \{self.current}", self.loc())
  }
}

///|
fn Parser::parse_f64(self : Parser) -> Double raise WatError {
  match self.current {
    Number(s) => {
      self.advance()
      parse_float64(s)
    }
    _ =>
      raise UnexpectedToken("expected number, got \{self.current}", self.loc())
  }
}

///|
fn parse_int(s : String) -> Int raise WatError {
  let trimmed = s
  if trimmed.has_prefix("0x") || trimmed.has_prefix("0X") {
    if trimmed.length() > 2 {
      let hex_part = StringBuilder::new()
      for i in 2..<trimmed.length() {
        hex_part.write_char(trimmed.code_unit_at(i).unsafe_to_char())
      }
      parse_hex_int(hex_part.to_string())
    } else {
      raise InvalidNumber(s, default_loc())
    }
  } else if trimmed.has_prefix("-0x") || trimmed.has_prefix("-0X") {
    if trimmed.length() > 3 {
      let hex_part = StringBuilder::new()
      for i in 3..<trimmed.length() {
        hex_part.write_char(trimmed.code_unit_at(i).unsafe_to_char())
      }
      -parse_hex_int(hex_part.to_string())
    } else {
      raise InvalidNumber(s, default_loc())
    }
  } else {
    // Try signed first, then unsigned (for values like 4294967295 which is -1 in i32)
    let result = @strconv.parse_int(trimmed) catch {
      _ => {
        // Try parsing as unsigned and reinterpret
        let u64 = @strconv.parse_uint64(trimmed) catch {
          _ => raise InvalidNumber(s, default_loc())
        }
        // Check if it fits in u32 range
        if u64 > 0xFFFFFFFFUL {
          raise InvalidNumber(s, default_loc())
        }
        u64.reinterpret_as_int64().to_int()
      }
    }
    result
  }
}

///|
fn parse_hex_int(s : String) -> Int raise WatError {
  let mut result = 0
  for i in 0..<s.length() {
    let c = s.code_unit_at(i).unsafe_to_char()
    if c == '_' {
      continue // Skip underscores (WAT number separator)
    }
    match hex_digit_value(c) {
      Some(v) => result = result * 16 + v
      None => raise InvalidNumber(s, default_loc())
    }
  }
  result
}

///|
/// Parse an unsigned 32-bit integer (for offset/align values)
/// Returns Int but interprets large values as unsigned
/// Raises error if value exceeds u32 max (4294967295)
fn parse_u32(s : String) -> Int raise WatError {
  let trimmed = s
  if trimmed.has_prefix("0x") || trimmed.has_prefix("0X") {
    if trimmed.length() > 2 {
      let hex_part = StringBuilder::new()
      for i in 2..<trimmed.length() {
        hex_part.write_char(trimmed.code_unit_at(i).unsafe_to_char())
      }
      parse_hex_u32(hex_part.to_string())
    } else {
      raise InvalidNumber(s, default_loc())
    }
  } else {
    // Parse decimal as unsigned 64-bit first to check range
    let u64 = @strconv.parse_uint64(trimmed) catch {
      _ => raise InvalidNumber(s, default_loc())
    }
    // Check if value exceeds u32 max
    if u64 > 0xFFFFFFFFUL {
      raise InvalidNumber(s, default_loc())
    }
    u64.reinterpret_as_int64().to_int()
  }
}

///|
fn parse_hex_u32(s : String) -> Int raise WatError {
  let mut result : UInt64 = 0UL
  let mut overflow = false
  for i in 0..<s.length() {
    let c = s.code_unit_at(i).unsafe_to_char()
    if c == '_' {
      continue // Skip underscores (WAT number separator)
    }
    match hex_digit_value(c) {
      Some(v) => {
        let new_result = result * 16UL + v.to_int64().reinterpret_as_uint64()
        // Detect overflow
        if new_result < result {
          overflow = true
        }
        result = new_result
      }
      None => raise InvalidNumber(s, default_loc())
    }
  }
  // Check if value exceeds u32 max
  if result > 0xFFFFFFFFUL || overflow {
    raise InvalidNumber(s, default_loc())
  }
  result.reinterpret_as_int64().to_int()
}

///|
fn parse_int64(s : String) -> Int64 raise WatError {
  let trimmed = s
  if trimmed.has_prefix("0x") || trimmed.has_prefix("0X") {
    if trimmed.length() > 2 {
      let hex_part = StringBuilder::new()
      for i in 2..<trimmed.length() {
        hex_part.write_char(trimmed.code_unit_at(i).unsafe_to_char())
      }
      parse_hex_int64(hex_part.to_string())
    } else {
      raise InvalidNumber(s, default_loc())
    }
  } else if trimmed.has_prefix("-0x") || trimmed.has_prefix("-0X") {
    if trimmed.length() > 3 {
      let hex_part = StringBuilder::new()
      for i in 3..<trimmed.length() {
        hex_part.write_char(trimmed.code_unit_at(i).unsafe_to_char())
      }
      -parse_hex_int64(hex_part.to_string())
    } else {
      raise InvalidNumber(s, default_loc())
    }
  } else {
    // Try signed first, then unsigned (for values like 18446744073709551615 which is -1 in i64)
    let result = @strconv.parse_int64(trimmed) catch {
      _ => {
        // Try parsing as unsigned and reinterpret
        let u64 = @strconv.parse_uint64(trimmed) catch {
          _ => raise InvalidNumber(s, default_loc())
        }
        u64.reinterpret_as_int64()
      }
    }
    result
  }
}

///|
fn parse_hex_int64(s : String) -> Int64 raise WatError {
  let mut result = 0L
  for i in 0..<s.length() {
    let c = s.code_unit_at(i).unsafe_to_char()
    if c == '_' {
      continue // Skip underscores (WAT number separator)
    }
    match hex_digit_value(c) {
      Some(v) => result = result * 16L + v.to_int64()
      None => raise InvalidNumber(s, default_loc())
    }
  }
  result
}

///|
fn parse_float32(s : String) -> Float raise WatError {
  if s == "inf" || s == "+inf" {
    return (1.0 : Float) / (0.0 : Float) // positive infinity
  }
  if s == "-inf" {
    return (-1.0 : Float) / (0.0 : Float) // negative infinity
  }
  // Handle nan and nan:payload
  if s == "nan" || s == "+nan" {
    // Canonical positive NaN: 0x7fc00000
    return Float::reinterpret_from_int(0x7fc00000)
  }
  if s == "-nan" {
    // Canonical negative NaN: 0xffc00000 = -4194304 as signed int
    return Float::reinterpret_from_int(-4194304)
  }
  if s.has_prefix("nan:0x") || s.has_prefix("+nan:0x") {
    // Parse payload from nan:0x...
    let payload_start = if s.has_prefix("+") { 7 } else { 6 }
    let payload_str = try! s[payload_start:].to_string()
    let payload = parse_hex_int(payload_str)
    // Positive NaN: 0x7f800000 | payload
    let bits = 0x7f800000 | (payload & 0x7fffff)
    return Float::reinterpret_from_int(bits)
  }
  if s.has_prefix("-nan:0x") {
    // Parse payload from -nan:0x...
    let payload_str = try! s[7:].to_string()
    let payload = parse_hex_int(payload_str)
    // Negative NaN: 0xff800000 | payload = -8388608 | payload
    let bits = -8388608 | (payload & 0x7fffff)
    return Float::reinterpret_from_int(bits)
  }
  // Handle hex float
  if s.has_prefix("0x") ||
    s.has_prefix("-0x") ||
    s.has_prefix("+0x") ||
    s.has_prefix("0X") ||
    s.has_prefix("-0X") ||
    s.has_prefix("+0X") {
    return parse_hex_float32_precise(s)
  }
  (@strconv.parse_double(s) |> Float::from_double) catch {
    _ => raise InvalidNumber(s, default_loc())
  }
}

///|
/// Parse hexadecimal floating-point literal to Float with precise rounding.
/// Uses integer bit manipulation to ensure correct IEEE 754 rounding.
fn parse_hex_float32_precise(s : String) -> Float raise WatError {
  let mut neg = false
  let mut idx = 0

  // Handle sign
  if s.code_unit_at(0).unsafe_to_char() == '-' {
    neg = true
    idx = 1
  } else if s.code_unit_at(0).unsafe_to_char() == '+' {
    idx = 1
  }

  // Skip 0x
  idx += 2

  // Parse significand as a 64-bit integer, tracking the binary exponent
  let mut significand : UInt64 = 0UL
  let mut frac_bits = 0
  let mut seen_dot = false
  let mut seen_digit = false
  let mut extra_bits = false
  let mut sig_bits = 0

  while idx < s.length() {
    let c = s.code_unit_at(idx).unsafe_to_char()
    if c == '.' {
      seen_dot = true
      idx += 1
      continue
    }
    if c == 'p' || c == 'P' {
      break
    }
    if c == '_' {
      idx += 1
      continue
    }
    match hex_digit_value(c) {
      Some(v) => {
        seen_digit = true
        let v_u64 = v.to_int64().reinterpret_as_uint64()
        if sig_bits < 64 {
          significand = significand * 16UL + v_u64
          sig_bits += 4
          // Only count fractional bits for digits that fit in significand
          if seen_dot {
            frac_bits += 4
          }
        } else {
          if v != 0 {
            extra_bits = true
          }
        }
        idx += 1
      }
      None => raise InvalidNumber(s, default_loc())
    }
  }

  if !seen_digit {
    significand = 0UL
  }

  // Parse exponent
  let mut exp = 0
  let mut exp_neg = false
  if idx < s.length() && (s.code_unit_at(idx).unsafe_to_char() == 'p' || s.code_unit_at(idx).unsafe_to_char() == 'P') {
    idx += 1
    if idx < s.length() && s.code_unit_at(idx).unsafe_to_char() == '-' {
      exp_neg = true
      idx += 1
    } else if idx < s.length() && s.code_unit_at(idx).unsafe_to_char() == '+' {
      idx += 1
    }
    while idx < s.length() {
      let c = s.code_unit_at(idx).unsafe_to_char()
      if c >= '0' && c <= '9' {
        exp = exp * 10 + (c.to_int() - '0'.to_int())
        idx += 1
      } else {
        break
      }
    }
  }

  // Handle zero
  if significand == 0UL {
    return if neg {
      Float::reinterpret_from_uint(0x80000000U) // -0.0
    } else {
      (0.0 : Float)
    }
  }

  // Calculate the binary exponent
  let total_exp = if exp_neg { -exp - frac_bits } else { exp - frac_bits }

  // Normalize: shift significand so leading 1 is at bit 63
  let mut norm_sig = significand
  let mut bit_count = 0
  let mut temp = significand
  while temp != 0UL {
    bit_count += 1
    temp = temp >> 1
  }

  let shift_amount = 64 - bit_count
  if shift_amount > 0 {
    norm_sig = norm_sig << shift_amount
  }

  // norm_exp is the actual binary exponent when norm_sig is in [1, 2) form
  let norm_exp = total_exp + bit_count - 1

  // IEEE 754 float: value = 2^(ieee_exp - 127) * (1 + mantissa/2^23)
  let ieee_exp = norm_exp + 127

  // Check for overflow (infinity)
  if ieee_exp >= 255 {
    return if neg {
      Float::reinterpret_from_uint(0xff800000U) // -infinity
    } else {
      Float::reinterpret_from_uint(0x7f800000U) // +infinity
    }
  }

  // Check for underflow (subnormal or zero)
  if ieee_exp <= 0 {
    let shift = 1 - ieee_exp
    if shift >= 64 {
      return if neg {
        Float::reinterpret_from_uint(0x80000000U) // -0.0
      } else {
        (0.0 : Float)
      }
    }

    let shifted_sig = norm_sig >> shift
    // For float subnormal: mantissa is bits 62-40 of shifted_sig (23 bits)
    // Round bit is bit 39, sticky bits are bits 38-0 plus extra_bits
    let mantissa = ((shifted_sig >> 40) & 0x7FFFFFUL).reinterpret_as_int64().to_int()
    let round_bit = (shifted_sig >> 39) & 1UL
    let sticky_bits = (shifted_sig & 0x7FFFFFFFFFUL) != 0UL || extra_bits || (shift > 0 && (norm_sig & ((1UL << shift) - 1UL)) != 0UL)

    let mantissa_rounded = if round_bit != 0UL && (sticky_bits || (mantissa & 1) != 0) {
      mantissa + 1
    } else {
      mantissa
    }

    // Check if rounding promoted to normal
    if mantissa_rounded >= 0x800000 {
      let final_mantissa = (mantissa_rounded & 0x7FFFFF).reinterpret_as_uint()
      let bits = if neg { 0x80800000U | final_mantissa } else { 0x00800000U | final_mantissa }
      return Float::reinterpret_from_uint(bits)
    }

    let sign_bit : UInt = if neg { 0x80000000U } else { 0U }
    let bits = sign_bit | mantissa_rounded.reinterpret_as_uint()
    return Float::reinterpret_from_uint(bits)
  }

  // Normal number
  // Extract 23-bit mantissa from norm_sig (bits 62-40, since bit 63 is the implicit 1)
  // Round bit is bit 39, sticky bits are bits 38-0 plus extra_bits
  let mantissa_raw = ((norm_sig >> 40) & 0x7FFFFFUL).reinterpret_as_int64().to_int()
  let round_bit = (norm_sig >> 39) & 1UL
  let sticky_bits = (norm_sig & 0x7FFFFFFFFFUL) != 0UL || extra_bits

  // Round to nearest, ties to even
  let mantissa_rounded = if round_bit != 0UL && (sticky_bits || (mantissa_raw & 1) != 0) {
    mantissa_raw + 1
  } else {
    mantissa_raw
  }

  // Check if rounding overflowed the mantissa
  let (final_exp, final_mantissa) = if mantissa_rounded >= 0x800000 {
    (ieee_exp + 1, 0)
  } else {
    (ieee_exp, mantissa_rounded & 0x7FFFFF)
  }

  // Check for overflow after rounding
  if final_exp >= 255 {
    return if neg {
      Float::reinterpret_from_uint(0xff800000U) // -infinity
    } else {
      Float::reinterpret_from_uint(0x7f800000U) // +infinity
    }
  }

  // Construct IEEE 754 bit pattern
  let sign_bit : UInt = if neg { 0x80000000U } else { 0U }
  let exp_bits = ((final_exp & 0xFF) << 23).reinterpret_as_uint()
  let bits = sign_bit | exp_bits | final_mantissa.reinterpret_as_uint()
  Float::reinterpret_from_uint(bits)
}

///|
fn parse_float64(s : String) -> Double raise WatError {
  if s == "inf" || s == "+inf" {
    return 1.0 / 0.0 // positive infinity
  }
  if s == "-inf" {
    return -1.0 / 0.0 // negative infinity
  }
  // Handle nan and nan:payload
  if s == "nan" || s == "+nan" {
    // Canonical positive NaN: 0x7ff8000000000000
    return 0x7ff8000000000000L.reinterpret_as_double()
  }
  if s == "-nan" {
    // Canonical negative NaN: 0xfff8000000000000
    return 0xfff8000000000000L.reinterpret_as_double()
  }
  if s.has_prefix("nan:0x") || s.has_prefix("+nan:0x") {
    // Parse payload from nan:0x...
    let payload_start = if s.has_prefix("+") { 7 } else { 6 }
    let payload_str = try! s[payload_start:].to_string()
    let payload = parse_hex_int64(payload_str)
    // Positive NaN: 0x7ff0000000000000 | payload
    let bits = 0x7ff0000000000000L | (payload & 0xfffffffffffffL)
    return bits.reinterpret_as_double()
  }
  if s.has_prefix("-nan:0x") {
    // Parse payload from -nan:0x...
    let payload_str = try! s[7:].to_string()
    let payload = parse_hex_int64(payload_str)
    // Negative NaN: 0xfff0000000000000 | payload
    let bits = 0xfff0000000000000L | (payload & 0xfffffffffffffL)
    return bits.reinterpret_as_double()
  }
  // Handle hex float
  if s.has_prefix("0x") ||
    s.has_prefix("-0x") ||
    s.has_prefix("+0x") ||
    s.has_prefix("0X") ||
    s.has_prefix("-0X") ||
    s.has_prefix("+0X") {
    return parse_hex_float64(s)
  }
  @strconv.parse_double(s) catch {
    _ => raise InvalidNumber(s, default_loc())
  }
}

///|
fn parse_hex_float64(s : String) -> Double raise WatError {
  let mut neg = false
  let mut idx = 0
  // Handle sign
  if s.code_unit_at(0).unsafe_to_char() == '-' {
    neg = true
    idx = 1
  } else if s.code_unit_at(0).unsafe_to_char() == '+' {
    idx = 1
  }
  // Skip 0x
  idx += 2
  // Parse integer part
  let mut int_part = 0.0
  while idx < s.length() {
    let c = s.code_unit_at(idx).unsafe_to_char()
    if c == '.' || c == 'p' || c == 'P' {
      break
    }
    match hex_digit_value(c) {
      Some(v) => {
        int_part = int_part * 16.0 + v.to_double()
        idx += 1
      }
      None => raise InvalidNumber(s, default_loc())
    }
  }
  // Parse fractional part
  let mut frac_part = 0.0
  let mut frac_scale = 1.0
  if idx < s.length() && s.code_unit_at(idx).unsafe_to_char() == '.' {
    idx += 1
    while idx < s.length() {
      let c = s.code_unit_at(idx).unsafe_to_char()
      if c == 'p' || c == 'P' {
        break
      }
      match hex_digit_value(c) {
        Some(v) => {
          frac_scale = frac_scale / 16.0
          frac_part = frac_part + v.to_double() * frac_scale
          idx += 1
        }
        None => raise InvalidNumber(s, default_loc())
      }
    }
  }
  // Parse exponent
  let mut exp = 0
  let mut exp_neg = false
  if idx < s.length() &&
    (
      s.code_unit_at(idx).unsafe_to_char() == 'p' ||
      s.code_unit_at(idx).unsafe_to_char() == 'P'
    ) {
    idx += 1
    if idx < s.length() && s.code_unit_at(idx).unsafe_to_char() == '-' {
      exp_neg = true
      idx += 1
    } else if idx < s.length() && s.code_unit_at(idx).unsafe_to_char() == '+' {
      idx += 1
    }
    while idx < s.length() {
      let c = s.code_unit_at(idx).unsafe_to_char()
      if c >= '0' && c <= '9' {
        exp = exp * 10 + (c.to_int() - '0'.to_int())
        idx += 1
      } else {
        break
      }
    }
  }
  let mut result = int_part + frac_part
  // Apply exponent (binary)
  if exp_neg {
    for _ in 0..<exp {
      result = result / 2.0
    }
  } else {
    for _ in 0..<exp {
      result = result * 2.0
    }
  }
  if neg {
    -result
  } else {
    result
  }
}

///|
fn Parser::parse_value_type(self : Parser) -> @types.ValueType raise WatError {
  match self.current {
    LParen => {
      // Handle (ref ...) types
      self.advance()
      self.expect_keyword("ref")
      // Check for nullable: (ref null ...)
      let mut is_extern = false
      if self.current == Keyword("null") {
        self.advance()
      }
      // Parse heap type: func, extern, or $typeidx
      match self.current {
        Keyword("func") => {
          self.advance()
          self.expect_rparen()
          @types.ValueType::FuncRef
        }
        Keyword("extern") => {
          is_extern = true
          self.advance()
          self.expect_rparen()
          @types.ValueType::ExternRef
        }
        Id(_) => {
          // Typed function reference like (ref $t) - treat as FuncRef for now
          self.advance()
          self.expect_rparen()
          @types.ValueType::FuncRef
        }
        _ => {
          self.expect_rparen()
          if is_extern {
            @types.ValueType::ExternRef
          } else {
            @types.ValueType::FuncRef
          }
        }
      }
    }
    Keyword(kw) => {
      self.advance()
      match kw {
        "i32" => I32
        "i64" => I64
        "f32" => F32
        "f64" => F64
        "v128" => V128
        "funcref" => FuncRef
        "externref" => ExternRef
        _ =>
          raise UnexpectedToken("expected value type, got '\{kw}'", self.loc())
      }
    }
    _ =>
      raise UnexpectedToken(
        "expected value type, got \{self.current}",
        self.loc(),
      )
  }
}

///|
/// Count the number of function imports
fn count_func_imports(imports : Array[@types.Import]) -> Int {
  let mut count = 0
  for imp in imports {
    if imp.desc is @types.ImportDesc::Func(_) {
      count = count + 1
    }
  }
  count
}

///|
fn count_table_imports(imports : Array[@types.Import]) -> Int {
  let mut count = 0
  for imp in imports {
    if imp.desc is @types.ImportDesc::Table(_) {
      count = count + 1
    }
  }
  count
}

///|
/// Parse a WAT module from string
pub fn parse(input : String) -> @types.Module raise WatError {
  let parser = Parser::new(input)
  parser.parse_module()
}

///|
fn Parser::parse_module(self : Parser) -> @types.Module raise WatError {
  self.expect_lparen()
  self.expect_keyword("module")

  // Optional module name
  if self.current is Id(_) {
    self.advance()
  }
  let mod_ = @types.Module::new()

  // First pass: collect function and type names (to support forward references)
  // Save lexer state
  let saved_pos = self.lexer.pos
  let saved_line = self.lexer.line
  let saved_column = self.lexer.column
  let saved_token_start_line = self.lexer.token_start_line
  let saved_token_start_column = self.lexer.token_start_column
  let saved_current = self.current

  // Scan for function and type definitions to collect names
  let mut func_idx = 0
  let mut type_idx = 0
  while self.current != RParen && self.current != Eof {
    match self.current {
      LParen => {
        self.advance()
        match self.current {
          Keyword("type") => {
            self.advance()
            // Check for type name
            if self.current is Id(name) {
              self.type_names.set(name, type_idx)
              self.advance()
            }
            type_idx = type_idx + 1
            // Skip to end of type
            self.skip_to_matching_rparen()
          }
          Keyword("import") => {
            self.advance()
            // Skip module name and import name
            match self.current {
              String_(_) => self.advance()
              _ => ()
            }
            match self.current {
              String_(_) => self.advance()
              _ => ()
            }
            // Check if it's a function import
            if self.current == LParen {
              self.advance()
              if self.current == Keyword("func") {
                self.advance()
                // Check for function name
                if self.current is Id(name) {
                  self.func_names.set(name, func_idx)
                  self.advance()
                }
                func_idx = func_idx + 1
                // Skip rest of func definition (depth starts at 1 for this inner paren)
                self.skip_to_matching_rparen()
              } else {
                // Not a func import, skip this inner expression
                self.skip_to_matching_rparen()
              }
            }
            // Skip to end of import (the outer rparen)
            self.skip_to_matching_rparen()
          }
          Keyword("func") => {
            self.advance()
            // Check for function name
            if self.current is Id(name) {
              self.func_names.set(name, func_idx)
            }
            func_idx = func_idx + 1
            // Skip to end of func
            self.skip_to_matching_rparen()
          }
          _ => self.skip_to_matching_rparen()
        }
      }
      _ => self.advance()
    }
  }

  // Restore lexer state for second pass
  self.lexer.pos = saved_pos
  self.lexer.line = saved_line
  self.lexer.column = saved_column
  self.lexer.token_start_line = saved_token_start_line
  self.lexer.token_start_column = saved_token_start_column
  self.current = saved_current

  // Second pass: actual parsing
  while self.current != RParen && self.current != Eof {
    match self.current {
      LParen => {
        self.advance()
        match self.current {
          Keyword("type") => {
            let type_idx = mod_.types.length()
            let ft = self.parse_type_def(type_idx)
            self.type_names.set("\{type_idx}", type_idx)
            mod_.types.push(ft)
          }
          Keyword("func") =>
            match self.parse_func_def(mod_) {
              FuncDef(type_idx, code, export_name) => {
                // func_idx must account for imported functions
                let func_idx = count_func_imports(mod_.imports) +
                  mod_.funcs.length()
                mod_.funcs.push(type_idx)
                mod_.codes.push(code)
                if export_name is Some(name) {
                  mod_.exports.push({
                    name,
                    desc: @types.ExportDesc::Func(func_idx),
                  })
                }
              }
              InlineImport(imp, export_name) => {
                // Add the import and optionally export it
                let func_idx = count_func_imports(mod_.imports)
                mod_.imports.push(imp)
                if export_name is Some(name) {
                  mod_.exports.push({
                    name,
                    desc: @types.ExportDesc::Func(func_idx),
                  })
                }
              }
            }
          Keyword("memory") =>
            match self.parse_memory_def() {
              MemoryDef(mem, export_name) => {
                let mem_idx = mod_.memories.length()
                mod_.memories.push(mem)
                if export_name is Some(name) {
                  mod_.exports.push({
                    name,
                    desc: @types.ExportDesc::Memory(mem_idx),
                  })
                }
              }
              MemoryImport(imp, export_name) => {
                // Count existing memory imports
                let mut memory_import_count = 0
                for existing in mod_.imports {
                  if existing.desc is @types.ImportDesc::Memory(_) {
                    memory_import_count += 1
                  }
                }
                mod_.imports.push(imp)
                if export_name is Some(name) {
                  mod_.exports.push({
                    name,
                    desc: @types.ExportDesc::Memory(memory_import_count),
                  })
                }
              }
            }
          Keyword("global") =>
            match self.parse_global_def() {
              GlobalDef(global, export_name) => {
                let global_idx = mod_.globals.length()
                mod_.globals.push(global)
                if export_name is Some(name) {
                  mod_.exports.push({
                    name,
                    desc: @types.ExportDesc::Global(global_idx),
                  })
                }
              }
              GlobalImport(imp, export_name) => {
                // Count existing global imports
                let mut global_import_count = 0
                for existing in mod_.imports {
                  if existing.desc is @types.ImportDesc::Global(_) {
                    global_import_count += 1
                  }
                }
                mod_.imports.push(imp)
                if export_name is Some(name) {
                  mod_.exports.push({
                    name,
                    desc: @types.ExportDesc::Global(global_import_count),
                  })
                }
              }
            }
          Keyword("export") => {
            let exp = self.parse_export_def(mod_)
            mod_.exports.push(exp)
          }
          Keyword("import") => {
            let imp = self.parse_import_def(mod_)
            mod_.imports.push(imp)
          }
          Keyword("table") => {
            let (table, export_name, inline_elem, tbl_name) = self.parse_table_def(
              mod_,
            )
            let table_idx = mod_.tables.length()
            mod_.tables.push(table)
            // Register table name with correct index
            if tbl_name is Some(name) {
              self.table_names.set(name, table_idx)
            }
            if export_name is Some(name) {
              mod_.exports.push({
                name,
                desc: @types.ExportDesc::Table(table_idx),
              })
            }
            if inline_elem is Some(elem) {
              mod_.elems.push(elem)
            }
          }
          Keyword("start") => {
            self.advance() // skip "start"
            let func_idx = self.parse_func_idx()
            mod_.start = Some(func_idx)
            self.expect_rparen()
          }
          Keyword("data") => {
            let data = self.parse_data_def()
            mod_.datas.push(data)
          }
          Keyword("elem") => {
            let elem = self.parse_elem_def()
            mod_.elems.push(elem)
          }
          Keyword(kw) =>
            raise UnexpectedToken("unexpected module field: \{kw}", self.loc())
          _ => raise UnexpectedToken("expected module field", self.loc())
        }
      }
      _ => raise UnexpectedToken("expected '(' in module", self.loc())
    }
  }
  self.expect_rparen()
  mod_
}

///|
fn Parser::parse_type_def(
  self : Parser,
  type_idx : Int,
) -> @types.FuncType raise WatError {
  self.advance() // skip "type"
  // Optional type name
  match self.current {
    Id(name) => {
      self.advance()
      self.type_names.set(name, type_idx)
    }
    _ => ()
  }
  self.expect_lparen()
  self.expect_keyword("func")
  let ft = self.parse_func_type()
  self.expect_rparen() // close func
  self.expect_rparen() // close type
  ft
}

///|
fn Parser::parse_func_type(self : Parser) -> @types.FuncType raise WatError {
  let params : Array[@types.ValueType] = []
  let results : Array[@types.ValueType] = []

  // Parse params
  while self.current == LParen {
    let saved_pos = self.lexer.pos
    self.advance()
    match self.current {
      Keyword("param") => {
        self.advance()
        // Optional name
        match self.current {
          Id(_) => self.advance()
          _ => ()
        }
        // Parse types until )
        while self.current != RParen {
          params.push(self.parse_value_type())
        }
        self.expect_rparen()
      }
      Keyword("result") => {
        self.advance()
        while self.current != RParen {
          results.push(self.parse_value_type())
        }
        self.expect_rparen()
      }
      _ => {
        // Not param/result, restore and break
        self.lexer.pos = saved_pos
        self.current = LParen
        break
      }
    }
  }
  { params, results }
}

///|
fn Parser::parse_func_def(
  self : Parser,
  mod_ : @types.Module,
) -> FuncDefResult raise WatError {
  self.advance() // skip "func"
  let mut export_name : String? = None
  let mut func_name : String? = None

  // Optional function name
  match self.current {
    Id(name) => {
      func_name = Some(name)
      self.advance()
    }
    _ => ()
  }

  // Clear local names for this function
  self.local_names.clear()

  // Check for inline import: (func $f (import "mod" "name") ...)
  // This must be checked before export because import comes first
  if self.current == LParen {
    let saved = self.lexer.pos
    let saved_line = self.lexer.line
    let saved_column = self.lexer.column
    let saved_token_start_line = self.lexer.token_start_line
    let saved_token_start_column = self.lexer.token_start_column
    self.advance()
    match self.current {
      Keyword("import") => {
        self.advance()
        // Parse module name and import name
        let mod_name = match self.current {
          String_(s) => {
            self.advance()
            s
          }
          _ => raise UnexpectedToken("expected module name", self.loc())
        }
        let import_name = match self.current {
          String_(s) => {
            self.advance()
            s
          }
          _ => raise UnexpectedToken("expected import name", self.loc())
        }
        self.expect_rparen() // close import

        // Check for inline export after import
        if self.current == LParen {
          let saved2 = self.lexer.pos
          self.advance()
          match self.current {
            Keyword("export") => {
              self.advance()
              match self.current {
                String_(s) => {
                  export_name = Some(s)
                  self.advance()
                }
                _ => raise UnexpectedToken("expected export name", self.loc())
              }
              self.expect_rparen()
            }
            _ => {
              self.lexer.pos = saved2
              self.current = LParen
            }
          }
        }

        // Parse type reference or inline type for the import
        let mut type_idx = -1
        let inline_params : Array[@types.ValueType] = []
        let inline_results : Array[@types.ValueType] = []
        while self.current == LParen {
          let saved2 = self.lexer.pos
          self.advance()
          match self.current {
            Keyword("type") => {
              self.advance()
              type_idx = self.parse_type_idx()
              self.expect_rparen()
            }
            Keyword("param") => {
              self.advance()
              // Optional name
              match self.current {
                Id(name) => {
                  self.local_names.set(name, inline_params.length())
                  self.advance()
                }
                _ => ()
              }
              while self.current != RParen {
                inline_params.push(self.parse_value_type())
              }
              self.expect_rparen()
            }
            Keyword("result") => {
              self.advance()
              while self.current != RParen {
                inline_results.push(self.parse_value_type())
              }
              self.expect_rparen()
            }
            _ => {
              self.lexer.pos = saved2
              self.current = LParen
              break
            }
          }
        }

        // Create type if needed
        if type_idx < 0 {
          let ft : @types.FuncType = {
            params: inline_params,
            results: inline_results,
          }
          // Check if this type already exists
          let mut found = -1
          for i, t in mod_.types {
            if t.params.length() == ft.params.length() &&
              t.results.length() == ft.results.length() {
              let mut match_ = true
              for j, p in t.params {
                if p != ft.params[j] {
                  match_ = false
                  break
                }
              }
              if match_ {
                for j, r in t.results {
                  if r != ft.results[j] {
                    match_ = false
                    break
                  }
                }
              }
              if match_ {
                found = i
                break
              }
            }
          }
          if found >= 0 {
            type_idx = found
          } else {
            type_idx = mod_.types.length()
            mod_.types.push(ft)
          }
        }
        self.expect_rparen() // close func

        // Register function name with index (will be assigned when import is added)
        // The func_idx for imports needs to be the count of existing function imports
        let import_func_idx = count_func_imports(mod_.imports)
        if func_name is Some(name) {
          self.func_names.set(name, import_func_idx)
        }
        let imp : @types.Import = {
          mod_name,
          name: import_name,
          desc: @types.ImportDesc::Func(type_idx),
        }
        return FuncDefResult::InlineImport(imp, export_name)
      }
      _ => {
        // Not an inline import, restore state
        self.lexer.pos = saved
        self.lexer.line = saved_line
        self.lexer.column = saved_column
        self.lexer.token_start_line = saved_token_start_line
        self.lexer.token_start_column = saved_token_start_column
        self.current = LParen
      }
    }
  }

  // Regular function definition - register the name now
  // func_idx must account for imported functions
  let func_idx = count_func_imports(mod_.imports) + mod_.funcs.length()
  if func_name is Some(name) {
    self.func_names.set(name, func_idx)
  }

  // Check for inline export
  if self.current == LParen {
    let saved = self.lexer.pos
    self.advance()
    match self.current {
      Keyword("export") => {
        self.advance()
        match self.current {
          String_(s) => {
            export_name = Some(s)
            self.advance()
          }
          _ => raise UnexpectedToken("expected export name", self.loc())
        }
        self.expect_rparen()
      }
      _ => {
        self.lexer.pos = saved
        self.current = LParen
      }
    }
  }

  // Parse type reference or inline type
  let mut type_idx = -1
  let inline_params : Array[@types.ValueType] = []
  let inline_results : Array[@types.ValueType] = []

  // Parse (type $idx) or inline params/results
  while self.current == LParen {
    let saved = self.lexer.pos
    self.advance()
    match self.current {
      Keyword("type") => {
        self.advance()
        type_idx = self.parse_type_idx()
        self.expect_rparen()
      }
      Keyword("param") => {
        self.advance()
        // Optional name
        match self.current {
          Id(name) => {
            self.local_names.set(name, inline_params.length())
            self.advance()
          }
          _ => ()
        }
        while self.current != RParen {
          inline_params.push(self.parse_value_type())
        }
        self.expect_rparen()
      }
      Keyword("result") => {
        self.advance()
        while self.current != RParen {
          inline_results.push(self.parse_value_type())
        }
        self.expect_rparen()
      }
      _ => {
        self.lexer.pos = saved
        self.current = LParen
        break
      }
    }
  }

  // If no type reference, create inline type
  if type_idx < 0 {
    let ft : @types.FuncType = {
      params: inline_params,
      results: inline_results,
    }
    // Check if this type already exists
    let mut found = -1
    for i, t in mod_.types {
      if t.params.length() == ft.params.length() &&
        t.results.length() == ft.results.length() {
        let mut match_ = true
        for j, p in t.params {
          if p != ft.params[j] {
            match_ = false
            break
          }
        }
        if match_ {
          for j, r in t.results {
            if r != ft.results[j] {
              match_ = false
              break
            }
          }
        }
        if match_ {
          found = i
          break
        }
      }
    }
    if found >= 0 {
      type_idx = found
    } else {
      type_idx = mod_.types.length()
      mod_.types.push(ft)
    }
  }

  // Parse locals
  let locals : Array[@types.ValueType] = []
  while self.current == LParen {
    let saved = self.lexer.pos
    self.advance()
    match self.current {
      Keyword("local") => {
        self.advance()
        // Optional name
        match self.current {
          Id(name) => {
            let local_idx = inline_params.length() + locals.length()
            self.local_names.set(name, local_idx)
            self.advance()
          }
          _ => ()
        }
        while self.current != RParen {
          locals.push(self.parse_value_type())
        }
        self.expect_rparen()
      }
      _ => {
        self.lexer.pos = saved
        self.current = LParen
        break
      }
    }
  }

  // Parse body instructions
  let body = self.parse_instructions()
  self.expect_rparen() // close func
  FuncDefResult::FuncDef(type_idx, { locals, body }, export_name)
}

///|
fn Parser::parse_instructions(
  self : Parser,
) -> Array[@types.Instruction] raise WatError {
  let instrs : Array[@types.Instruction] = []
  while self.current != RParen && self.current != Eof {
    match self.current {
      LParen => {
        // Folded instruction - may produce multiple instructions
        self.advance()
        for instr in self.parse_folded_instructions() {
          instrs.push(instr)
        }
      }
      Keyword(kw) => {
        // Stop on control flow terminators (they are handled by the caller)
        if kw == "end" || kw == "else" {
          break
        }
        let instr = self.parse_plain_instruction(kw)
        instrs.push(instr)
      }
      _ => break
    }
  }
  instrs
}

///|
/// Parse a folded instruction and return all resulting instructions.
/// For most instructions, returns a single instruction.
/// For folded `if`, returns condition instructions followed by the if instruction.
fn Parser::parse_folded_instructions(
  self : Parser,
) -> Array[@types.Instruction] raise WatError {
  match self.current {
    Keyword(kw) => {
      // Special handling for "block" in folded form
      if kw == "block" {
        self.advance() // skip "block"
        // Optional label name
        let label : String? = match self.current {
          Id(name) => {
            self.advance()
            Some(name)
          }
          _ => None
        }
        let bt = self.parse_block_type()
        self.push_label(label)
        let body = self.parse_instructions()
        self.pop_label()
        self.expect_rparen() // close block in folded form (no 'end' keyword)
        return [@types.Instruction::Block(bt, body)]
      }
      // Special handling for "loop" in folded form
      if kw == "loop" {
        self.advance() // skip "loop"
        // Optional label name
        let label : String? = match self.current {
          Id(name) => {
            self.advance()
            Some(name)
          }
          _ => None
        }
        let bt = self.parse_block_type()
        self.push_label(label)
        let body = self.parse_instructions()
        self.pop_label()
        self.expect_rparen() // close loop in folded form (no 'end' keyword)
        return [@types.Instruction::Loop(bt, body)]
      }
      // Special handling for "if" in folded form
      if kw == "if" {
        self.advance() // skip "if"
        // Optional label name
        let label : String? = match self.current {
          Id(name) => {
            self.advance()
            Some(name)
          }
          _ => None
        }
        let bt = self.parse_block_type()
        let result : Array[@types.Instruction] = []
        // In folded form, condition operands come first as nested S-expressions
        while self.current == LParen {
          // Peek ahead to see if this is (then ...) or (else ...)
          let saved = self.lexer.pos
          self.advance()
          match self.current {
            Keyword("then") | Keyword("else") => {
              // Restore and break to handle then/else
              self.lexer.pos = saved
              self.current = LParen
              break
            }
            _ => {
              // Restore to parse as folded operand (condition)
              self.lexer.pos = saved
              self.current = LParen
              self.advance()
              for instr in self.parse_folded_instructions() {
                result.push(instr)
              }
            }
          }
        }
        // Now parse (then ...) and optionally (else ...)
        let mut then_body : Array[@types.Instruction] = []
        let mut else_body : Array[@types.Instruction] = []
        self.push_label(label)
        if self.current == LParen {
          self.advance()
          match self.current {
            Keyword("then") => {
              self.advance()
              then_body = self.parse_instructions()
              self.expect_rparen()
            }
            _ =>
              raise UnexpectedToken("expected 'then' in folded if", self.loc())
          }
        }
        if self.current == LParen {
          let saved = self.lexer.pos
          self.advance()
          match self.current {
            Keyword("else") => {
              self.advance()
              else_body = self.parse_instructions()
              self.expect_rparen()
            }
            _ => {
              self.lexer.pos = saved
              self.current = LParen
            }
          }
        }
        self.pop_label()
        self.expect_rparen() // close if
        result.push(@types.Instruction::If(bt, then_body, else_body))
        return result
      }
      let instr = self.parse_plain_instruction(kw)
      // For control instructions, we've already handled them
      // For other instructions, parse folded operands
      match instr {
        Block(_, _) | Loop(_, _) | If(_, _, _) => [instr]
        _ => {
          // Parse nested folded instructions (operands)
          let result : Array[@types.Instruction] = []
          while self.current == LParen {
            self.advance()
            for i in self.parse_folded_instructions() {
              result.push(i)
            }
          }
          self.expect_rparen()
          result.push(instr)
          result
        }
      }
    }
    _ => raise UnexpectedToken("expected instruction", self.loc())
  }
}

///|
fn Parser::parse_plain_instruction(
  self : Parser,
  kw : String,
) -> @types.Instruction raise WatError {
  self.advance()
  match kw {
    // Control
    "unreachable" => @types.Instruction::Unreachable
    "nop" => @types.Instruction::Nop
    "block" => {
      // Optional label name
      let label : String? = match self.current {
        Id(name) => {
          self.advance()
          Some(name)
        }
        _ => None
      }
      let bt = self.parse_block_type()
      self.push_label(label)
      let body = self.parse_instructions()
      self.pop_label()
      self.expect_keyword("end")
      @types.Instruction::Block(bt, body)
    }
    "loop" => {
      // Optional label name
      let label : String? = match self.current {
        Id(name) => {
          self.advance()
          Some(name)
        }
        _ => None
      }
      let bt = self.parse_block_type()
      self.push_label(label)
      let body = self.parse_instructions()
      self.pop_label()
      self.expect_keyword("end")
      @types.Instruction::Loop(bt, body)
    }
    "if" => {
      // Optional label name
      let label : String? = match self.current {
        Id(name) => {
          self.advance()
          Some(name)
        }
        _ => None
      }
      let bt = self.parse_block_type()
      // Flat form: if (result type) ... else ... end
      self.push_label(label)
      let then_body = self.parse_instructions()
      let else_body : Array[@types.Instruction] = if self.current ==
        Keyword("else") {
        self.advance()
        self.parse_instructions()
      } else {
        []
      }
      self.pop_label()
      self.expect_keyword("end")
      @types.Instruction::If(bt, then_body, else_body)
    }
    "br" => @types.Instruction::Br(self.parse_label_idx())
    "br_if" => @types.Instruction::BrIf(self.parse_label_idx())
    "br_table" => {
      let labels : Array[Int] = []
      while self.current != RParen && self.current != Eof {
        match self.current {
          Number(_) | Id(_) => labels.push(self.parse_label_idx())
          _ => break
        }
      }
      if labels.length() == 0 {
        raise ParseError("br_table requires at least one label", self.loc())
      }
      let default_label = labels.pop().unwrap()
      @types.Instruction::BrTable(labels, default_label)
    }
    "return" => @types.Instruction::Return
    "call" => @types.Instruction::Call(self.parse_func_idx())
    "call_indirect" => {
      // call_indirect can have various forms:
      // (call_indirect $table (type $t) ...)
      // (call_indirect (type $t) ...)
      // (call_indirect (param ...) (result ...) ...)
      // (call_indirect ...)  - empty type
      let mut table_idx = 0
      let mut type_idx = -1

      // Check for optional table index/name before the type
      match self.current {
        Id(name) =>
          match self.table_names.get(name) {
            Some(idx) => {
              table_idx = idx
              self.advance()
            }
            None => () // Not a table name, might be something else
          }
        Number(_) => table_idx = self.parse_u32()
        _ => ()
      }

      // Parse optional type/param/result annotations
      while self.current == LParen {
        let saved = self.lexer.pos
        let saved_line = self.lexer.line
        let saved_column = self.lexer.column
        let saved_token_start_line = self.lexer.token_start_line
        let saved_token_start_column = self.lexer.token_start_column
        self.advance()
        match self.current {
          Keyword("type") => {
            self.advance()
            type_idx = self.parse_type_idx()
            self.expect_rparen()
          }
          Keyword("param") | Keyword("result") => {
            // Skip inline param/result - they should match the type
            while self.current != RParen {
              self.advance()
            }
            self.expect_rparen()
          }
          _ => {
            // Not a type annotation, restore state (this is an operand)
            self.lexer.pos = saved
            self.lexer.line = saved_line
            self.lexer.column = saved_column
            self.lexer.token_start_line = saved_token_start_line
            self.lexer.token_start_column = saved_token_start_column
            self.current = LParen
            break
          }
        }
      }
      if type_idx < 0 {
        type_idx = 0 // Default to type 0 if not specified
      }
      @types.Instruction::CallIndirect(type_idx, table_idx)
    }

    // Parametric
    "drop" => @types.Instruction::Drop
    "select" => {
      // select can have optional (result type) annotations
      while self.current == LParen {
        let saved = self.lexer.pos
        let saved_line = self.lexer.line
        let saved_column = self.lexer.column
        let saved_token_start_line = self.lexer.token_start_line
        let saved_token_start_column = self.lexer.token_start_column
        self.advance()
        match self.current {
          Keyword("result") => {
            // Skip result type annotation
            while self.current != RParen {
              self.advance()
            }
            self.expect_rparen()
          }
          _ => {
            // Not a type annotation, restore state
            self.lexer.pos = saved
            self.lexer.line = saved_line
            self.lexer.column = saved_column
            self.lexer.token_start_line = saved_token_start_line
            self.lexer.token_start_column = saved_token_start_column
            self.current = LParen
            break
          }
        }
      }
      @types.Instruction::Select
    }

    // Reference types
    "ref.null" => {
      // Parse reference type (func or extern)
      let ref_type = self.parse_ref_type()
      @types.Instruction::RefNull(ref_type)
    }
    "ref.is_null" => @types.Instruction::RefIsNull
    "ref.func" => @types.Instruction::RefFunc(self.parse_func_idx())

    // Variable
    "local.get" => @types.Instruction::LocalGet(self.parse_local_idx())
    "local.set" => @types.Instruction::LocalSet(self.parse_local_idx())
    "local.tee" => @types.Instruction::LocalTee(self.parse_local_idx())
    "global.get" => @types.Instruction::GlobalGet(self.parse_global_idx())
    "global.set" => @types.Instruction::GlobalSet(self.parse_global_idx())

    // Table instructions
    "table.get" => @types.Instruction::TableGet(self.parse_table_idx())
    "table.set" => @types.Instruction::TableSet(self.parse_table_idx())
    "table.size" => @types.Instruction::TableSize(self.parse_table_idx())
    "table.grow" => @types.Instruction::TableGrow(self.parse_table_idx())
    "table.fill" => @types.Instruction::TableFill(self.parse_table_idx())
    "table.copy" => {
      let dest = self.parse_table_idx()
      let src = self.parse_table_idx()
      @types.Instruction::TableCopy(dest, src)
    }
    "table.init" => {
      // table.init can have forms: (table.init $elem) or (table.init $table $elem)
      let first = match self.current {
        Number(s) => {
          self.advance()
          parse_int(s)
        }
        Id(name) =>
          // Could be table name or elem name - try table first
          match self.table_names.get(name) {
            Some(idx) => {
              self.advance()
              idx
            }
            None => {
              // Not a table name, treat as elem index
              self.advance()
              0 // Assume it's elem 0 for named elems (we don't track elem names)
            }
          }
        _ => 0
      }
      match self.current {
        Number(_) | Id(_) => {
          // Two arguments: first was table index, second is elem index
          let elem_idx = match self.current {
            Number(s) => {
              self.advance()
              parse_int(s)
            }
            Id(_) => {
              self.advance()
              0 // Named elem, default to 0
            }
            _ => 0
          }
          @types.Instruction::TableInit(first, elem_idx)
        }
        _ =>
          // One argument: first was elem index, table defaults to 0
          @types.Instruction::TableInit(0, first)
      }
    }

    // Memory
    "i32.load" =>
      parse_mem_arg(self, fn(a, o) { @types.Instruction::I32Load(a, o) })
    "i64.load" =>
      parse_mem_arg(self, fn(a, o) { @types.Instruction::I64Load(a, o) })
    "f32.load" =>
      parse_mem_arg(self, fn(a, o) { @types.Instruction::F32Load(a, o) })
    "f64.load" =>
      parse_mem_arg(self, fn(a, o) { @types.Instruction::F64Load(a, o) })
    "i32.load8_s" =>
      parse_mem_arg(self, fn(a, o) { @types.Instruction::I32Load8S(a, o) })
    "i32.load8_u" =>
      parse_mem_arg(self, fn(a, o) { @types.Instruction::I32Load8U(a, o) })
    "i32.load16_s" =>
      parse_mem_arg(self, fn(a, o) { @types.Instruction::I32Load16S(a, o) })
    "i32.load16_u" =>
      parse_mem_arg(self, fn(a, o) { @types.Instruction::I32Load16U(a, o) })
    "i64.load8_s" =>
      parse_mem_arg(self, fn(a, o) { @types.Instruction::I64Load8S(a, o) })
    "i64.load8_u" =>
      parse_mem_arg(self, fn(a, o) { @types.Instruction::I64Load8U(a, o) })
    "i64.load16_s" =>
      parse_mem_arg(self, fn(a, o) { @types.Instruction::I64Load16S(a, o) })
    "i64.load16_u" =>
      parse_mem_arg(self, fn(a, o) { @types.Instruction::I64Load16U(a, o) })
    "i64.load32_s" =>
      parse_mem_arg(self, fn(a, o) { @types.Instruction::I64Load32S(a, o) })
    "i64.load32_u" =>
      parse_mem_arg(self, fn(a, o) { @types.Instruction::I64Load32U(a, o) })
    "i32.store" =>
      parse_mem_arg(self, fn(a, o) { @types.Instruction::I32Store(a, o) })
    "i64.store" =>
      parse_mem_arg(self, fn(a, o) { @types.Instruction::I64Store(a, o) })
    "f32.store" =>
      parse_mem_arg(self, fn(a, o) { @types.Instruction::F32Store(a, o) })
    "f64.store" =>
      parse_mem_arg(self, fn(a, o) { @types.Instruction::F64Store(a, o) })
    "i32.store8" =>
      parse_mem_arg(self, fn(a, o) { @types.Instruction::I32Store8(a, o) })
    "i32.store16" =>
      parse_mem_arg(self, fn(a, o) { @types.Instruction::I32Store16(a, o) })
    "i64.store8" =>
      parse_mem_arg(self, fn(a, o) { @types.Instruction::I64Store8(a, o) })
    "i64.store16" =>
      parse_mem_arg(self, fn(a, o) { @types.Instruction::I64Store16(a, o) })
    "i64.store32" =>
      parse_mem_arg(self, fn(a, o) { @types.Instruction::I64Store32(a, o) })
    "memory.size" => @types.Instruction::MemorySize
    "memory.grow" => @types.Instruction::MemoryGrow
    "memory.init" => @types.Instruction::MemoryInit(self.parse_data_idx())
    "memory.copy" => @types.Instruction::MemoryCopy
    "memory.fill" => @types.Instruction::MemoryFill
    "data.drop" => @types.Instruction::DataDrop(self.parse_data_idx())
    "elem.drop" => @types.Instruction::ElemDrop(self.parse_elem_idx())

    // Constants
    "i32.const" => @types.Instruction::I32Const(self.parse_i32())
    "i64.const" => @types.Instruction::I64Const(self.parse_i64())
    "f32.const" => @types.Instruction::F32Const(self.parse_f32())
    "f64.const" => @types.Instruction::F64Const(self.parse_f64())

    // i32 operations
    "i32.eqz" => @types.Instruction::I32Eqz
    "i32.eq" => @types.Instruction::I32Eq
    "i32.ne" => @types.Instruction::I32Ne
    "i32.lt_s" => @types.Instruction::I32LtS
    "i32.lt_u" => @types.Instruction::I32LtU
    "i32.gt_s" => @types.Instruction::I32GtS
    "i32.gt_u" => @types.Instruction::I32GtU
    "i32.le_s" => @types.Instruction::I32LeS
    "i32.le_u" => @types.Instruction::I32LeU
    "i32.ge_s" => @types.Instruction::I32GeS
    "i32.ge_u" => @types.Instruction::I32GeU
    "i32.clz" => @types.Instruction::I32Clz
    "i32.ctz" => @types.Instruction::I32Ctz
    "i32.popcnt" => @types.Instruction::I32Popcnt
    "i32.add" => @types.Instruction::I32Add
    "i32.sub" => @types.Instruction::I32Sub
    "i32.mul" => @types.Instruction::I32Mul
    "i32.div_s" => @types.Instruction::I32DivS
    "i32.div_u" => @types.Instruction::I32DivU
    "i32.rem_s" => @types.Instruction::I32RemS
    "i32.rem_u" => @types.Instruction::I32RemU
    "i32.and" => @types.Instruction::I32And
    "i32.or" => @types.Instruction::I32Or
    "i32.xor" => @types.Instruction::I32Xor
    "i32.shl" => @types.Instruction::I32Shl
    "i32.shr_s" => @types.Instruction::I32ShrS
    "i32.shr_u" => @types.Instruction::I32ShrU
    "i32.rotl" => @types.Instruction::I32Rotl
    "i32.rotr" => @types.Instruction::I32Rotr
    // Sign-extension operators
    "i32.extend8_s" => @types.Instruction::I32Extend8S
    "i32.extend16_s" => @types.Instruction::I32Extend16S

    // i64 operations
    "i64.eqz" => @types.Instruction::I64Eqz
    "i64.eq" => @types.Instruction::I64Eq
    "i64.ne" => @types.Instruction::I64Ne
    "i64.lt_s" => @types.Instruction::I64LtS
    "i64.lt_u" => @types.Instruction::I64LtU
    "i64.gt_s" => @types.Instruction::I64GtS
    "i64.gt_u" => @types.Instruction::I64GtU
    "i64.le_s" => @types.Instruction::I64LeS
    "i64.le_u" => @types.Instruction::I64LeU
    "i64.ge_s" => @types.Instruction::I64GeS
    "i64.ge_u" => @types.Instruction::I64GeU
    "i64.clz" => @types.Instruction::I64Clz
    "i64.ctz" => @types.Instruction::I64Ctz
    "i64.popcnt" => @types.Instruction::I64Popcnt
    "i64.add" => @types.Instruction::I64Add
    "i64.sub" => @types.Instruction::I64Sub
    "i64.mul" => @types.Instruction::I64Mul
    "i64.div_s" => @types.Instruction::I64DivS
    "i64.div_u" => @types.Instruction::I64DivU
    "i64.rem_s" => @types.Instruction::I64RemS
    "i64.rem_u" => @types.Instruction::I64RemU
    "i64.and" => @types.Instruction::I64And
    "i64.or" => @types.Instruction::I64Or
    "i64.xor" => @types.Instruction::I64Xor
    "i64.shl" => @types.Instruction::I64Shl
    "i64.shr_s" => @types.Instruction::I64ShrS
    "i64.shr_u" => @types.Instruction::I64ShrU
    "i64.rotl" => @types.Instruction::I64Rotl
    "i64.rotr" => @types.Instruction::I64Rotr
    // Sign-extension operators
    "i64.extend8_s" => @types.Instruction::I64Extend8S
    "i64.extend16_s" => @types.Instruction::I64Extend16S
    "i64.extend32_s" => @types.Instruction::I64Extend32S

    // f32 operations
    "f32.abs" => @types.Instruction::F32Abs
    "f32.neg" => @types.Instruction::F32Neg
    "f32.ceil" => @types.Instruction::F32Ceil
    "f32.floor" => @types.Instruction::F32Floor
    "f32.trunc" => @types.Instruction::F32Trunc
    "f32.nearest" => @types.Instruction::F32Nearest
    "f32.sqrt" => @types.Instruction::F32Sqrt
    "f32.add" => @types.Instruction::F32Add
    "f32.sub" => @types.Instruction::F32Sub
    "f32.mul" => @types.Instruction::F32Mul
    "f32.div" => @types.Instruction::F32Div
    "f32.min" => @types.Instruction::F32Min
    "f32.max" => @types.Instruction::F32Max
    "f32.copysign" => @types.Instruction::F32Copysign
    "f32.eq" => @types.Instruction::F32Eq
    "f32.ne" => @types.Instruction::F32Ne
    "f32.lt" => @types.Instruction::F32Lt
    "f32.gt" => @types.Instruction::F32Gt
    "f32.le" => @types.Instruction::F32Le
    "f32.ge" => @types.Instruction::F32Ge

    // f64 operations
    "f64.abs" => @types.Instruction::F64Abs
    "f64.neg" => @types.Instruction::F64Neg
    "f64.ceil" => @types.Instruction::F64Ceil
    "f64.floor" => @types.Instruction::F64Floor
    "f64.trunc" => @types.Instruction::F64Trunc
    "f64.nearest" => @types.Instruction::F64Nearest
    "f64.sqrt" => @types.Instruction::F64Sqrt
    "f64.add" => @types.Instruction::F64Add
    "f64.sub" => @types.Instruction::F64Sub
    "f64.mul" => @types.Instruction::F64Mul
    "f64.div" => @types.Instruction::F64Div
    "f64.min" => @types.Instruction::F64Min
    "f64.max" => @types.Instruction::F64Max
    "f64.copysign" => @types.Instruction::F64Copysign
    "f64.eq" => @types.Instruction::F64Eq
    "f64.ne" => @types.Instruction::F64Ne
    "f64.lt" => @types.Instruction::F64Lt
    "f64.gt" => @types.Instruction::F64Gt
    "f64.le" => @types.Instruction::F64Le
    "f64.ge" => @types.Instruction::F64Ge

    // Conversions
    "i32.wrap_i64" => @types.Instruction::I32WrapI64
    "i32.trunc_f32_s" => @types.Instruction::I32TruncF32S
    "i32.trunc_f32_u" => @types.Instruction::I32TruncF32U
    "i32.trunc_f64_s" => @types.Instruction::I32TruncF64S
    "i32.trunc_f64_u" => @types.Instruction::I32TruncF64U
    "i64.extend_i32_s" => @types.Instruction::I64ExtendI32S
    "i64.extend_i32_u" => @types.Instruction::I64ExtendI32U
    "i64.trunc_f32_s" => @types.Instruction::I64TruncF32S
    "i64.trunc_f32_u" => @types.Instruction::I64TruncF32U
    "i64.trunc_f64_s" => @types.Instruction::I64TruncF64S
    "i64.trunc_f64_u" => @types.Instruction::I64TruncF64U
    "f32.convert_i32_s" => @types.Instruction::F32ConvertI32S
    "f32.convert_i32_u" => @types.Instruction::F32ConvertI32U
    "f32.convert_i64_s" => @types.Instruction::F32ConvertI64S
    "f32.convert_i64_u" => @types.Instruction::F32ConvertI64U
    "f32.demote_f64" => @types.Instruction::F32DemoteF64
    "f64.convert_i32_s" => @types.Instruction::F64ConvertI32S
    "f64.convert_i32_u" => @types.Instruction::F64ConvertI32U
    "f64.convert_i64_s" => @types.Instruction::F64ConvertI64S
    "f64.convert_i64_u" => @types.Instruction::F64ConvertI64U
    "f64.promote_f32" => @types.Instruction::F64PromoteF32
    "i32.reinterpret_f32" => @types.Instruction::I32ReinterpretF32
    "i64.reinterpret_f64" => @types.Instruction::I64ReinterpretF64
    "f32.reinterpret_i32" => @types.Instruction::F32ReinterpretI32
    "f64.reinterpret_i64" => @types.Instruction::F64ReinterpretI64

    // Saturating truncation instructions (nontrapping float-to-int)
    "i32.trunc_sat_f32_s" => @types.Instruction::I32TruncSatF32S
    "i32.trunc_sat_f32_u" => @types.Instruction::I32TruncSatF32U
    "i32.trunc_sat_f64_s" => @types.Instruction::I32TruncSatF64S
    "i32.trunc_sat_f64_u" => @types.Instruction::I32TruncSatF64U
    "i64.trunc_sat_f32_s" => @types.Instruction::I64TruncSatF32S
    "i64.trunc_sat_f32_u" => @types.Instruction::I64TruncSatF32U
    "i64.trunc_sat_f64_s" => @types.Instruction::I64TruncSatF64S
    "i64.trunc_sat_f64_u" => @types.Instruction::I64TruncSatF64U
    _ => raise InvalidInstruction(kw, self.loc())
  }
}

///|
fn parse_mem_arg(
  parser : Parser,
  instr : (Int, Int) -> @types.Instruction,
) -> @types.Instruction raise WatError {
  let mut offset = 0
  let mut align = 0
  // Parse optional offset=N and align=N
  while true {
    match parser.current {
      Keyword(s) =>
        if s.has_prefix("offset=") {
          let offset_str = StringBuilder::new()
          for i in 7..<s.length() {
            offset_str.write_char(s.code_unit_at(i).unsafe_to_char())
          }
          // Use parse_u32 for offset (can be up to 0xFFFFFFFF)
          offset = parse_u32(offset_str.to_string())
          parser.advance()
        } else if s.has_prefix("align=") {
          let align_str = StringBuilder::new()
          for i in 6..<s.length() {
            align_str.write_char(s.code_unit_at(i).unsafe_to_char())
          }
          let a = parse_u32(align_str.to_string())
          // Convert alignment to log2
          align = log2(a)
          parser.advance()
        } else {
          break
        }
      _ => break
    }
  }
  instr(align, offset)
}

///|
fn log2(n : Int) -> Int {
  let mut v = n
  let mut r = 0
  while v > 1 {
    v = v / 2
    r += 1
  }
  r
}

///|
fn Parser::parse_block_type(self : Parser) -> @types.BlockType raise WatError {
  let params : Array[@types.ValueType] = []
  let results : Array[@types.ValueType] = []
  let mut type_idx : Int? = None

  // Parse optional (type $idx) and/or (param ...) (result ...)
  while self.current == LParen {
    let saved = self.lexer.pos
    let saved_line = self.lexer.line
    let saved_column = self.lexer.column
    let saved_token_start_line = self.lexer.token_start_line
    let saved_token_start_column = self.lexer.token_start_column
    self.advance()
    match self.current {
      Keyword("type") => {
        // (type $idx) - explicit type reference
        self.advance()
        type_idx = Some(self.parse_type_idx())
        self.expect_rparen()
        // Continue to parse any inline param/result annotations (they are optional redundant info)
      }
      Keyword("param") => {
        self.advance()
        // Skip optional name
        if self.current is Id(_) {
          self.advance()
        }
        while self.current != RParen {
          params.push(self.parse_value_type())
        }
        self.expect_rparen()
      }
      Keyword("result") => {
        self.advance()
        while self.current != RParen {
          results.push(self.parse_value_type())
        }
        self.expect_rparen()
      }
      _ => {
        // Not a block type annotation, restore state
        self.lexer.pos = saved
        self.lexer.line = saved_line
        self.lexer.column = saved_column
        self.lexer.token_start_line = saved_token_start_line
        self.lexer.token_start_column = saved_token_start_column
        self.current = LParen
        break
      }
    }
  }

  // Determine the block type variant
  // If we have explicit type index, use it (param/result are just annotations)
  if type_idx is Some(idx) {
    return @types.BlockType::TypeIndex(idx)
  }
  if params.length() > 0 {
    // Has parameters - use InlineType
    @types.BlockType::InlineType(params, results)
  } else if results.length() == 0 {
    @types.BlockType::Empty
  } else if results.length() == 1 {
    @types.BlockType::Value(results[0])
  } else {
    @types.BlockType::MultiValue(results)
  }
}

///|
fn Parser::parse_type_idx(self : Parser) -> Int raise WatError {
  match self.current {
    Number(s) => {
      self.advance()
      parse_int(s)
    }
    Id(name) =>
      match self.type_names.get(name) {
        Some(idx) => {
          self.advance()
          idx
        }
        None => raise UndefinedIdentifier("type $\{name}", self.loc())
      }
    _ => raise UnexpectedToken("expected type index", self.loc())
  }
}

///|
fn Parser::parse_func_idx(self : Parser) -> Int raise WatError {
  match self.current {
    Number(s) => {
      self.advance()
      parse_int(s)
    }
    Id(name) =>
      match self.func_names.get(name) {
        Some(idx) => {
          self.advance()
          idx
        }
        None => raise UndefinedIdentifier("func $\{name}", self.loc())
      }
    _ => raise UnexpectedToken("expected func index", self.loc())
  }
}

///|
fn Parser::parse_local_idx(self : Parser) -> Int raise WatError {
  match self.current {
    Number(s) => {
      self.advance()
      parse_int(s)
    }
    Id(name) =>
      match self.local_names.get(name) {
        Some(idx) => {
          self.advance()
          idx
        }
        None => raise UndefinedIdentifier("local $\{name}", self.loc())
      }
    _ => raise UnexpectedToken("expected local index", self.loc())
  }
}

///|
fn Parser::parse_global_idx(self : Parser) -> Int raise WatError {
  match self.current {
    Number(s) => {
      self.advance()
      parse_int(s)
    }
    Id(name) =>
      match self.global_names.get(name) {
        Some(idx) => {
          self.advance()
          idx
        }
        None => raise UndefinedIdentifier("global $\{name}", self.loc())
      }
    _ => raise UnexpectedToken("expected global index", self.loc())
  }
}

///|
fn Parser::parse_table_idx(self : Parser) -> Int raise WatError {
  match self.current {
    Number(s) => {
      self.advance()
      parse_int(s)
    }
    Id(name) =>
      match self.table_names.get(name) {
        Some(idx) => {
          self.advance()
          idx
        }
        None => raise UndefinedIdentifier("table $\{name}", self.loc())
      }
    _ =>
      // Default to table 0 if no index specified
      0
  }
}

///|
fn Parser::parse_data_idx(self : Parser) -> Int raise WatError {
  match self.current {
    Number(s) => {
      self.advance()
      parse_int(s)
    }
    _ => raise UnexpectedToken("expected data segment index", self.loc())
  }
}

///|
fn Parser::parse_elem_idx(self : Parser) -> Int raise WatError {
  match self.current {
    Number(s) => {
      self.advance()
      parse_int(s)
    }
    _ => raise UnexpectedToken("expected elem segment index", self.loc())
  }
}

///|
/// Parse a reference type for ref.null instruction
fn Parser::parse_ref_type(self : Parser) -> @types.ValueType raise WatError {
  match self.current {
    Keyword("func") | Keyword("funcref") => {
      self.advance()
      @types.ValueType::FuncRef
    }
    Keyword("extern") | Keyword("externref") => {
      self.advance()
      @types.ValueType::ExternRef
    }
    Id(_) => {
      // Type index like $t - treat as FuncRef for now
      self.advance()
      @types.ValueType::FuncRef
    }
    _ =>
      raise UnexpectedToken(
        "expected reference type (func, extern, funcref, externref)",
        self.loc(),
      )
  }
}

///|
fn Parser::parse_label_idx(self : Parser) -> Int raise WatError {
  match self.current {
    Number(s) => {
      self.advance()
      parse_int(s)
    }
    Id(name) =>
      match self.resolve_label(name) {
        Some(idx) => {
          self.advance()
          idx
        }
        None => raise UndefinedIdentifier("label $\{name}", self.loc())
      }
    _ => raise UnexpectedToken("expected label index", self.loc())
  }
}

///|
fn Parser::parse_memory_def(self : Parser) -> MemoryDefResult raise WatError {
  self.advance() // skip "memory"
  let mut export_name : String? = None

  // Optional name
  match self.current {
    Id(name) => {
      self.memory_names.set(name, 0)
      self.advance()
    }
    _ => ()
  }

  // Check for inline import: (memory (import "mod" "name") MIN [MAX])
  if self.current == LParen {
    let saved = self.lexer.pos
    let saved_line = self.lexer.line
    let saved_column = self.lexer.column
    let saved_token_start_line = self.lexer.token_start_line
    let saved_token_start_column = self.lexer.token_start_column
    self.advance()
    match self.current {
      Keyword("import") => {
        self.advance()
        // Parse module name and import name
        let mod_name = match self.current {
          String_(s) => {
            self.advance()
            s
          }
          _ => raise UnexpectedToken("expected module name", self.loc())
        }
        let import_name = match self.current {
          String_(s) => {
            self.advance()
            s
          }
          _ => raise UnexpectedToken("expected import name", self.loc())
        }
        self.expect_rparen() // close import

        // Check for inline export after import
        if self.current == LParen {
          let saved2 = self.lexer.pos
          self.advance()
          match self.current {
            Keyword("export") => {
              self.advance()
              match self.current {
                String_(s) => {
                  export_name = Some(s)
                  self.advance()
                }
                _ => raise UnexpectedToken("expected export name", self.loc())
              }
              self.expect_rparen()
            }
            _ => {
              self.lexer.pos = saved2
              self.current = LParen
            }
          }
        }

        // Parse limits
        let min = self.parse_u32()
        let max = match self.current {
          Number(_) => Some(self.parse_u32())
          _ => None
        }
        self.expect_rparen() // close memory
        let imp : @types.Import = {
          mod_name,
          name: import_name,
          desc: @types.ImportDesc::Memory({ limits: { min, max } }),
        }
        return MemoryDefResult::MemoryImport(imp, export_name)
      }
      Keyword("export") => {
        self.advance()
        match self.current {
          String_(s) => {
            export_name = Some(s)
            self.advance()
          }
          _ => raise UnexpectedToken("expected export name", self.loc())
        }
        self.expect_rparen()
      }
      _ => {
        self.lexer.pos = saved
        self.lexer.line = saved_line
        self.lexer.column = saved_column
        self.lexer.token_start_line = saved_token_start_line
        self.lexer.token_start_column = saved_token_start_column
        self.current = LParen
      }
    }
  }

  // Parse limits
  let min = self.parse_u32()
  let max = match self.current {
    Number(_) => Some(self.parse_u32())
    _ => None
  }
  self.expect_rparen()
  MemoryDefResult::MemoryDef({ limits: { min, max } }, export_name)
}

///|
fn Parser::parse_global_def(self : Parser) -> GlobalDefResult raise WatError {
  self.advance() // skip "global"
  let mut export_name : String? = None
  let mut global_name : String? = None

  // Optional name
  match self.current {
    Id(name) => {
      global_name = Some(name)
      self.advance()
    }
    _ => ()
  }

  // Check for inline import: (global $x (import "mod" "name") i32)
  if self.current == LParen {
    let saved = self.lexer.pos
    let saved_line = self.lexer.line
    let saved_column = self.lexer.column
    let saved_token_start_line = self.lexer.token_start_line
    let saved_token_start_column = self.lexer.token_start_column
    self.advance()
    match self.current {
      Keyword("import") => {
        self.advance()
        // Parse module name and import name
        let mod_name = match self.current {
          String_(s) => {
            self.advance()
            s
          }
          _ => raise UnexpectedToken("expected module name", self.loc())
        }
        let import_name = match self.current {
          String_(s) => {
            self.advance()
            s
          }
          _ => raise UnexpectedToken("expected import name", self.loc())
        }
        self.expect_rparen() // close import

        // Check for inline export after import
        if self.current == LParen {
          let saved2 = self.lexer.pos
          self.advance()
          match self.current {
            Keyword("export") => {
              self.advance()
              match self.current {
                String_(s) => {
                  export_name = Some(s)
                  self.advance()
                }
                _ => raise UnexpectedToken("expected export name", self.loc())
              }
              self.expect_rparen()
            }
            _ => {
              self.lexer.pos = saved2
              self.current = LParen
            }
          }
        }

        // Parse global type (mut i32) or i32 or (ref ...)
        let (value_type, mutable) = if self.current == LParen {
          let saved3 = self.lexer.pos
          let saved3_line = self.lexer.line
          let saved3_column = self.lexer.column
          let saved3_token_start_line = self.lexer.token_start_line
          let saved3_token_start_column = self.lexer.token_start_column
          self.advance()
          if self.current == Keyword("mut") {
            self.advance()
            let vt = self.parse_value_type()
            self.expect_rparen()
            (vt, true)
          } else {
            // Not (mut ...), restore and parse as ref type
            self.lexer.pos = saved3
            self.lexer.line = saved3_line
            self.lexer.column = saved3_column
            self.lexer.token_start_line = saved3_token_start_line
            self.lexer.token_start_column = saved3_token_start_column
            self.current = LParen
            (self.parse_value_type(), false)
          }
        } else {
          (self.parse_value_type(), false)
        }
        self.expect_rparen() // close global

        // Register global name
        if global_name is Some(name) {
          self.global_names.set(name, self.global_names.length())
        }
        let imp : @types.Import = {
          mod_name,
          name: import_name,
          desc: @types.ImportDesc::Global({ value_type, mutable }),
        }
        return GlobalDefResult::GlobalImport(imp, export_name)
      }
      _ => {
        // Not an inline import, restore state
        self.lexer.pos = saved
        self.lexer.line = saved_line
        self.lexer.column = saved_column
        self.lexer.token_start_line = saved_token_start_line
        self.lexer.token_start_column = saved_token_start_column
        self.current = LParen
      }
    }
  }

  // Register global name for regular global
  if global_name is Some(name) {
    self.global_names.set(name, self.global_names.length())
  }

  // Check for inline export
  if self.current == LParen {
    let saved = self.lexer.pos
    self.advance()
    match self.current {
      Keyword("export") => {
        self.advance()
        match self.current {
          String_(s) => {
            export_name = Some(s)
            self.advance()
          }
          _ => raise UnexpectedToken("expected export name", self.loc())
        }
        self.expect_rparen()
      }
      _ => {
        self.lexer.pos = saved
        self.current = LParen
      }
    }
  }

  // Parse global type (mut i32) or i32 or (ref ...)
  let (value_type, mutable) = if self.current == LParen {
    let saved = self.lexer.pos
    let saved_line = self.lexer.line
    let saved_column = self.lexer.column
    let saved_token_start_line = self.lexer.token_start_line
    let saved_token_start_column = self.lexer.token_start_column
    self.advance()
    if self.current == Keyword("mut") {
      self.advance()
      let vt = self.parse_value_type()
      self.expect_rparen()
      (vt, true)
    } else {
      // Not (mut ...), restore and parse as ref type
      self.lexer.pos = saved
      self.lexer.line = saved_line
      self.lexer.column = saved_column
      self.lexer.token_start_line = saved_token_start_line
      self.lexer.token_start_column = saved_token_start_column
      self.current = LParen
      (self.parse_value_type(), false)
    }
  } else {
    (self.parse_value_type(), false)
  }

  // Parse init expression
  let init = self.parse_instructions()
  self.expect_rparen()
  GlobalDefResult::GlobalDef(
    { type_: { value_type, mutable }, init },
    export_name,
  )
}

///|
fn Parser::parse_table_def(
  self : Parser,
  mod_ : @types.Module,
) -> (@types.TableType, String?, @types.Element?, String?) raise WatError {
  // Returns (table_type, export_name, inline_elem, table_name)
  self.advance() // skip "table"
  let mut export_name : String? = None
  let mut table_name : String? = None

  // Optional name
  match self.current {
    Id(name) => {
      table_name = Some(name)
      // Don't set table_names here; caller will set with correct index
      self.advance()
    }
    _ => ()
  }

  // Check for inline export
  if self.current == LParen {
    let saved = self.lexer.pos
    self.advance()
    match self.current {
      Keyword("export") => {
        self.advance()
        match self.current {
          String_(s) => {
            export_name = Some(s)
            self.advance()
          }
          _ => raise UnexpectedToken("expected export name", self.loc())
        }
        self.expect_rparen()
      }
      _ => {
        self.lexer.pos = saved
        self.current = LParen
      }
    }
  }

  // Check for inline import: (table (import "mod" "name") MIN [MAX] elemtype)
  if self.current == LParen {
    let saved = self.lexer.pos
    let saved_line = self.lexer.line
    let saved_column = self.lexer.column
    let saved_token_start_line = self.lexer.token_start_line
    let saved_token_start_column = self.lexer.token_start_column
    self.advance()
    match self.current {
      Keyword("import") => {
        self.advance()
        // Parse module name and import name
        let mod_name = match self.current {
          String_(s) => {
            self.advance()
            s
          }
          _ => raise UnexpectedToken("expected module name", self.loc())
        }
        let import_name = match self.current {
          String_(s) => {
            self.advance()
            s
          }
          _ => raise UnexpectedToken("expected import name", self.loc())
        }
        self.expect_rparen() // close import

        // Parse limits
        let min = self.parse_u32()
        let max = match self.current {
          Number(_) => Some(self.parse_u32())
          _ => None
        }
        // Parse element type
        let elem_type = self.parse_value_type()
        self.expect_rparen() // close table

        // Add the import to the module
        let imp : @types.Import = {
          mod_name,
          name: import_name,
          desc: @types.ImportDesc::Table({ elem_type, limits: { min, max } }),
        }
        mod_.imports.push(imp)
        // Return a placeholder table type (the import is what matters)
        return (
          { elem_type, limits: { min, max } },
          export_name,
          None,
          table_name,
        )
      }
      _ => {
        // Not an inline import, restore state
        self.lexer.pos = saved
        self.lexer.line = saved_line
        self.lexer.column = saved_column
        self.lexer.token_start_line = saved_token_start_line
        self.lexer.token_start_column = saved_token_start_column
        self.current = LParen
      }
    }
  }

  // Check for inline elem syntax: (table elemtype (elem ...))
  // In this syntax, the element type comes first, followed by inline elem
  // Element type can be a keyword (funcref, externref) or a reference type (ref null $t)
  match self.current {
    Keyword("funcref")
    | Keyword("func")
    | Keyword("externref")
    | Keyword("extern")
    | LParen => {
      // Could be inline elem syntax or reference type followed by inline elem
      let elem_type = self.parse_value_type()
      // Check if followed by inline elem
      if self.current == LParen {
        let saved = self.lexer.pos
        let saved_line = self.lexer.line
        let saved_column = self.lexer.column
        let saved_token_start_line = self.lexer.token_start_line
        let saved_token_start_column = self.lexer.token_start_column
        self.advance()
        match self.current {
          Keyword("elem") => {
            self.advance()
            // Parse element init expressions (can be indices or expressions)
            let init : Array[Array[@types.Instruction]] = []
            while self.current != RParen {
              match self.current {
                Id(name) =>
                  // Named function reference like $f
                  match self.func_names.get(name) {
                    Some(idx) => {
                      init.push([@types.Instruction::RefFunc(idx)])
                      self.advance()
                    }
                    None =>
                      // Function might be declared later, use placeholder
                      // For now, just skip - this is for assert_invalid tests
                      self.advance()
                  }
                Number(_) => {
                  let idx = self.parse_u32()
                  init.push([@types.Instruction::RefFunc(idx)])
                }
                LParen => {
                  // Expression like (ref.func $f) or (ref.null func)
                  self.advance()
                  match self.current {
                    Keyword("ref.func") => {
                      self.advance()
                      let idx = self.parse_func_idx()
                      self.expect_rparen()
                      init.push([@types.Instruction::RefFunc(idx)])
                    }
                    Keyword("ref.null") => {
                      self.advance()
                      let ref_type = self.parse_ref_type()
                      self.expect_rparen()
                      init.push([@types.Instruction::RefNull(ref_type)])
                    }
                    Keyword("item") => {
                      self.advance()
                      let expr = self.parse_instructions()
                      self.expect_rparen()
                      init.push(expr)
                    }
                    _ => {
                      // General expression
                      let expr = self.parse_instructions()
                      self.expect_rparen()
                      init.push(expr)
                    }
                  }
                }
                _ => break
              }
            }
            self.expect_rparen() // close elem
            self.expect_rparen() // close table
            let table_idx = mod_.tables.length()
            let elem : @types.Element = {
              mode: @types.ElemMode::Active(table_idx, [
                @types.Instruction::I32Const(0),
              ]),
              type_: elem_type,
              init,
            }
            let table_type : @types.TableType = {
              elem_type,
              limits: { min: init.length(), max: Some(init.length()) },
            }
            return (table_type, export_name, Some(elem), table_name)
          }
          _ => {
            // Not an inline elem, restore state and fall through to standard syntax
            // But we already parsed elem_type, so we need a different approach
            // This case shouldn't happen for valid WAT - (ref null $t) followed by something other than (elem ...)
            self.lexer.pos = saved
            self.lexer.line = saved_line
            self.lexer.column = saved_column
            self.lexer.token_start_line = saved_token_start_line
            self.lexer.token_start_column = saved_token_start_column
            self.current = LParen
            raise UnexpectedToken("expected elem in inline table", self.loc())
          }
        }
      } else {
        // Just element type followed by closing paren (no inline elem, no limits)
        self.expect_rparen()
        // This is a table with implicit size 0, no elements
        return (
          { elem_type, limits: { min: 0, max: None } },
          export_name,
          None,
          table_name,
        )
      }
    }
    _ => {
      // Standard syntax: (table MIN [MAX] elemtype [init_expr])
      let min = self.parse_u32()
      let max = match self.current {
        Number(_) => Some(self.parse_u32())
        _ => None
      }
      let elem_type = self.parse_value_type()
      // Check for optional default init expression (ref.func $f) or (ref.null func)
      if self.current == LParen {
        // Skip the init expression - it's for table default value
        // This is a WebAssembly 2.0 feature, we'll just parse and ignore for now
        self.advance()
        match self.current {
          Keyword("ref.func") | Keyword("ref.null") => {
            self.advance()
            // Skip the argument
            while self.current != RParen {
              self.advance()
            }
            self.expect_rparen()
          }
          _ => {
            // General expression, skip until closing paren
            let mut depth = 1
            while depth > 0 && self.current != Eof {
              match self.current {
                LParen => {
                  depth += 1
                  self.advance()
                }
                RParen => {
                  depth -= 1
                  if depth > 0 {
                    self.advance()
                  }
                }
                _ => self.advance()
              }
            }
            self.expect_rparen()
          }
        }
      }
      self.expect_rparen()
      ({ elem_type, limits: { min, max } }, export_name, None, table_name)
    }
  }
}

///|
fn Parser::parse_export_def(
  self : Parser,
  mod_ : @types.Module,
) -> @types.Export raise WatError {
  self.advance() // skip "export"
  let name = match self.current {
    String_(s) => {
      self.advance()
      s
    }
    _ => raise UnexpectedToken("expected export name", self.loc())
  }
  self.expect_lparen()
  let desc = match self.current {
    Keyword("func") => {
      self.advance()
      let idx = self.parse_func_idx()
      @types.ExportDesc::Func(idx)
    }
    Keyword("memory") => {
      self.advance()
      let idx = match self.current {
        Number(_) => self.parse_u32()
        _ => 0
      }
      @types.ExportDesc::Memory(idx)
    }
    Keyword("table") => {
      self.advance()
      let idx = match self.current {
        Number(_) => self.parse_u32()
        _ => 0
      }
      @types.ExportDesc::Table(idx)
    }
    Keyword("global") => {
      self.advance()
      let idx = self.parse_global_idx()
      @types.ExportDesc::Global(idx)
    }
    _ => raise UnexpectedToken("expected export kind", self.loc())
  }
  ignore(mod_)
  self.expect_rparen()
  self.expect_rparen()
  { name, desc }
}

///|
fn Parser::parse_import_def(
  self : Parser,
  mod_ : @types.Module,
) -> @types.Import raise WatError {
  self.advance() // skip "import"
  let mod_name = match self.current {
    String_(s) => {
      self.advance()
      s
    }
    _ => raise UnexpectedToken("expected module name", self.loc())
  }
  let name = match self.current {
    String_(s) => {
      self.advance()
      s
    }
    _ => raise UnexpectedToken("expected import name", self.loc())
  }
  self.expect_lparen()
  let desc = match self.current {
    Keyword("func") => {
      self.advance()
      // Optional func name - imported function index is count of function imports so far
      match self.current {
        Id(fname) => {
          self.func_names.set(fname, count_func_imports(mod_.imports))
          self.advance()
        }
        _ => ()
      }
      // Parse type - either (type $idx) or inline (param ...) (result ...)
      let type_idx = if self.current == LParen {
        let saved_pos = self.lexer.pos
        self.advance()
        if self.current == Keyword("type") {
          // (type $idx) syntax
          self.advance()
          let idx = self.parse_type_idx()
          self.expect_rparen()
          idx
        } else {
          // Inline signature - restore position and parse func type
          self.lexer.pos = saved_pos
          self.current = LParen
          let func_type = self.parse_func_type()
          // Add this type to the module and get its index
          let idx = mod_.types.length()
          mod_.types.push(func_type)
          idx
        }
      } else {
        // No type specified, use empty signature
        let func_type : @types.FuncType = { params: [], results: [] }
        let idx = mod_.types.length()
        mod_.types.push(func_type)
        idx
      }
      @types.ImportDesc::Func(type_idx)
    }
    Keyword("memory") => {
      self.advance()
      let min = self.parse_u32()
      let max = match self.current {
        Number(_) => Some(self.parse_u32())
        _ => None
      }
      @types.ImportDesc::Memory({ limits: { min, max } })
    }
    Keyword("table") => {
      self.advance()
      // Optional table name
      if self.current is Id(tname) {
        // Register table name - table index is count of table imports so far
        self.table_names.set(tname, count_table_imports(mod_.imports))
        self.advance()
      }
      let min = self.parse_u32()
      let max = match self.current {
        Number(_) => Some(self.parse_u32())
        _ => None
      }
      let elem_type = self.parse_value_type()
      @types.ImportDesc::Table({ elem_type, limits: { min, max } })
    }
    Keyword("global") => {
      self.advance()
      let (value_type, mutable) = if self.current == LParen {
        let saved_pos = self.lexer.pos
        let saved_line = self.lexer.line
        let saved_column = self.lexer.column
        let saved_token_start_line = self.lexer.token_start_line
        let saved_token_start_column = self.lexer.token_start_column
        self.advance()
        if self.current == Keyword("mut") {
          self.advance()
          let vt = self.parse_value_type()
          self.expect_rparen()
          (vt, true)
        } else {
          // Not (mut ...), restore and parse as ref type
          self.lexer.pos = saved_pos
          self.lexer.line = saved_line
          self.lexer.column = saved_column
          self.lexer.token_start_line = saved_token_start_line
          self.lexer.token_start_column = saved_token_start_column
          self.current = LParen
          (self.parse_value_type(), false)
        }
      } else {
        (self.parse_value_type(), false)
      }
      @types.ImportDesc::Global({ value_type, mutable })
    }
    _ => raise UnexpectedToken("expected import kind", self.loc())
  }
  self.expect_rparen()
  self.expect_rparen()
  { mod_name, name, desc }
}

///|
/// Parse a data segment definition
/// Supports various syntaxes:
/// - (data (i32.const <offset>) "<string>"...)  - active with offset
/// - (data (memory <idx>) (offset ...) "<string>"...)  - active with memory
/// - (data)  - passive, empty
/// - (data "<string>"...)  - passive with init
fn Parser::parse_data_def(self : Parser) -> @types.Data raise WatError {
  self.advance() // skip "data"

  // Check for optional data id
  if self.current is Id(_) {
    self.advance()
  }

  // Default memory index is 0
  let mut memory_idx = 0
  let mut offset : Array[@types.Instruction] = []
  let mut is_passive = true

  // Check what comes next
  if self.current == LParen {
    let saved = self.lexer.pos
    let saved_line = self.lexer.line
    let saved_column = self.lexer.column
    let saved_token_start_line = self.lexer.token_start_line
    let saved_token_start_column = self.lexer.token_start_column
    self.advance()
    match self.current {
      Keyword("memory") => {
        is_passive = false
        self.advance()
        memory_idx = match self.current {
          Number(_) => self.parse_u32()
          Id(name) =>
            match self.memory_names.get(name) {
              Some(idx) => {
                self.advance()
                idx
              }
              None => 0
            }
          _ => 0
        }
        self.expect_rparen()
        // Now expect offset - can be (offset ...) or direct (i32.const ...)
        self.expect_lparen()
        if self.current == Keyword("offset") {
          self.advance()
          offset = self.parse_instructions()
          self.expect_rparen()
        } else {
          // Direct offset expression like (i32.const 0)
          offset = self.parse_instructions()
          self.expect_rparen()
        }
      }
      Keyword("offset") => {
        is_passive = false
        self.advance()
        offset = self.parse_instructions()
        self.expect_rparen()
      }
      Keyword(_) => {
        // Any keyword instruction can be an offset expression (i32.const, i32.add, global.get, etc.)
        is_passive = false
        offset = self.parse_instructions()
        self.expect_rparen()
      }
      _ => {
        // Restore - this might be something else or passive data
        self.lexer.pos = saved
        self.lexer.line = saved_line
        self.lexer.column = saved_column
        self.lexer.token_start_line = saved_token_start_line
        self.lexer.token_start_column = saved_token_start_column
        self.current = LParen
      }
    }
  }

  // Parse string literals for init data (can have multiple or none)
  let init_bytes : Array[Byte] = []
  while self.current is String_(_) {
    if self.current is String_(s) {
      for i in 0..<s.length() {
        init_bytes.push(s.code_unit_at(i).to_byte())
      }
      self.advance()
    }
  }
  self.expect_rparen() // close data
  ignore(is_passive)
  { memory_idx, offset, init: Bytes::from_array(init_bytes) }
}

///|
/// Parse an element segment definition
/// Supports various syntaxes:
/// - Passive: (elem funcref ...) or (elem func $f $g)
/// - Active: (elem (table $t) (offset ...) ...) or (elem (i32.const 0) $f $g)
/// - Declarative: (elem declare func $f $g)
fn Parser::parse_elem_def(self : Parser) -> @types.Element raise WatError {
  self.advance() // skip "elem"

  // Check for optional elem id
  if self.current is Id(_) {
    self.advance()
  }

  // Check for declarative element segment: (elem declare ...)
  if self.current == Keyword("declare") {
    self.advance() // skip "declare"
    return self.parse_elem_items_and_finish(@types.ElemMode::Declarative)
  }

  // Check what comes next to determine if this is passive or active
  // Passive: starts with reftype (funcref, externref, func, (ref ...))
  // Active: starts with ( for table/offset/i32.const
  match self.current {
    Keyword("funcref")
    | Keyword("externref")
    | Keyword("func")
    | Keyword("extern") =>
      // Passive element segment
      self.parse_elem_items_and_finish(@types.ElemMode::Passive)
    LParen => {
      // Could be active segment with (table ...), (offset ...), (i32.const ...), or (ref ...)
      let saved = self.lexer.pos
      let saved_line = self.lexer.line
      let saved_column = self.lexer.column
      let saved_token_start_line = self.lexer.token_start_line
      let saved_token_start_column = self.lexer.token_start_column
      self.advance()
      match self.current {
        Keyword("ref") => {
          // Passive segment with (ref null func) type
          self.lexer.pos = saved
          self.lexer.line = saved_line
          self.lexer.column = saved_column
          self.lexer.token_start_line = saved_token_start_line
          self.lexer.token_start_column = saved_token_start_column
          self.current = LParen
          self.parse_elem_items_and_finish(@types.ElemMode::Passive)
        }
        Keyword("table") => {
          // Active with explicit table
          self.advance()
          let table_idx = match self.current {
            Number(_) => self.parse_u32()
            Id(name) =>
              match self.table_names.get(name) {
                Some(idx) => {
                  self.advance()
                  idx
                }
                None => raise UndefinedIdentifier("table $\{name}", self.loc())
              }
            _ => 0
          }
          self.expect_rparen()
          // Now expect offset expression
          self.expect_lparen()
          let offset = if self.current is Keyword("offset") {
            self.advance()
            let o = self.parse_instructions()
            self.expect_rparen()
            o
          } else {
            // Direct offset expression like (i32.const 0)
            let o = self.parse_instructions()
            self.expect_rparen()
            o
          }
          self.parse_elem_items_and_finish(
            @types.ElemMode::Active(table_idx, offset),
          )
        }
        Keyword("offset") => {
          // Active with explicit offset, implicit table 0
          self.advance()
          let offset = self.parse_instructions()
          self.expect_rparen()
          self.parse_elem_items_and_finish(@types.ElemMode::Active(0, offset))
        }
        _ => {
          // Active with direct offset expression like (i32.const 0), implicit table 0
          let offset = self.parse_instructions()
          self.expect_rparen()
          self.parse_elem_items_and_finish(@types.ElemMode::Active(0, offset))
        }
      }
    }
    // Empty passive segment
    RParen => {
      self.expect_rparen()
      {
        mode: @types.ElemMode::Passive,
        type_: @types.ValueType::FuncRef,
        init: [],
      }
    }
    _ => raise UnexpectedToken("expected elem segment content", self.loc())
  }
}

///|
/// Parse element items (type and init expressions) and finish the element segment
fn Parser::parse_elem_items_and_finish(
  self : Parser,
  mode : @types.ElemMode,
) -> @types.Element raise WatError {
  // Parse element type: funcref, externref, func, (ref ...)
  let (elem_type, use_func_indices) = self.parse_elem_type()

  // Parse init expressions
  let init : Array[Array[@types.Instruction]] = []
  if use_func_indices {
    // Parse function indices directly: $f $g or 0 1 2
    while self.current != RParen && self.current != Eof {
      match self.current {
        Number(_) | Id(_) => {
          let idx = self.parse_func_idx()
          init.push([@types.Instruction::RefFunc(idx)])
        }
        _ => break
      }
    }
  } else {
    // Parse init expressions: (ref.func $f), (ref.null func), (item ...), or general expressions
    while self.current == LParen {
      self.advance()
      match self.current {
        Keyword("item") => {
          // (item <expr>)
          self.advance()
          let expr = self.parse_instructions()
          self.expect_rparen()
          init.push(expr)
        }
        Keyword("ref.func") => {
          // (ref.func $f)
          self.advance()
          let idx = self.parse_func_idx()
          self.expect_rparen()
          init.push([@types.Instruction::RefFunc(idx)])
        }
        Keyword("ref.null") => {
          // (ref.null func)
          self.advance()
          let ref_type = self.parse_ref_type()
          self.expect_rparen()
          init.push([@types.Instruction::RefNull(ref_type)])
        }
        _ => {
          // General expression like (global.get 0)
          let expr = self.parse_instructions()
          self.expect_rparen()
          init.push(expr)
        }
      }
    }
  }
  self.expect_rparen() // close elem
  { mode, type_: elem_type, init }
}

///|
/// Parse element type and return (type, use_func_indices)
/// use_func_indices is true when using "func" abbreviation (indices instead of expressions)
fn Parser::parse_elem_type(
  self : Parser,
) -> (@types.ValueType, Bool) raise WatError {
  match self.current {
    Keyword("funcref") => {
      self.advance()
      (@types.ValueType::FuncRef, false)
    }
    Keyword("externref") => {
      self.advance()
      (@types.ValueType::ExternRef, false)
    }
    Keyword("func") => {
      self.advance()
      (@types.ValueType::FuncRef, true) // use indices
    }
    Keyword("extern") => {
      self.advance()
      (@types.ValueType::ExternRef, true) // use indices
    }
    LParen => {
      // (ref null func) or similar
      let vt = self.parse_value_type()
      (vt, false)
    }
    Id(_) | Number(_) =>
      // Legacy syntax: direct function indices without type keyword
      (@types.ValueType::FuncRef, true)
    _ =>
      // Default to funcref with expressions (empty elem)
      (@types.ValueType::FuncRef, false)
  }
}
