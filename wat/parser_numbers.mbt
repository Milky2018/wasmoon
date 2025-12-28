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
      raise WatError::InvalidNumber(s, default_loc())
    }
  } else if trimmed.has_prefix("-0x") || trimmed.has_prefix("-0X") {
    if trimmed.length() > 3 {
      let hex_part = StringBuilder::new()
      for i in 3..<trimmed.length() {
        hex_part.write_char(trimmed.code_unit_at(i).unsafe_to_char())
      }
      -parse_hex_int(hex_part.to_string())
    } else {
      raise WatError::InvalidNumber(s, default_loc())
    }
  } else {
    // Try signed first, then unsigned (for values like 4294967295 which is -1 in i32)
    let result = @strconv.parse_int(trimmed) catch {
      _ => {
        // Try parsing as unsigned and reinterpret
        let u64 = @strconv.parse_uint64(trimmed) catch {
          _ => raise WatError::InvalidNumber(s, default_loc())
        }
        // Check if it fits in u32 range
        if u64 > 0xFFFFFFFFUL {
          raise WatError::InvalidNumber(s, default_loc())
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
      None => raise WatError::InvalidNumber(s, default_loc())
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
      raise WatError::InvalidNumber(s, default_loc())
    }
  } else {
    // Parse decimal as unsigned 64-bit first to check range
    let u64 = @strconv.parse_uint64(trimmed) catch {
      _ => raise WatError::InvalidNumber(s, default_loc())
    }
    // Check if value exceeds u32 max
    if u64 > 0xFFFFFFFFUL {
      raise WatError::InvalidNumber(s, default_loc())
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
      None => raise WatError::InvalidNumber(s, default_loc())
    }
  }
  // Check if value exceeds u32 max
  if result > 0xFFFFFFFFUL || overflow {
    raise WatError::InvalidNumber(s, default_loc())
  }
  result.reinterpret_as_int64().to_int()
}

///|
/// Parse an unsigned 64-bit integer (for memory64 limits)
/// Returns Int64 to support memory64 proposal limits
fn parse_u64(s : String) -> Int64 raise WatError {
  let trimmed = s
  if trimmed.has_prefix("0x") || trimmed.has_prefix("0X") {
    if trimmed.length() > 2 {
      let hex_part = StringBuilder::new()
      for i in 2..<trimmed.length() {
        hex_part.write_char(trimmed.code_unit_at(i).unsafe_to_char())
      }
      parse_hex_u64(hex_part.to_string())
    } else {
      raise WatError::InvalidNumber(s, default_loc())
    }
  } else {
    // Parse decimal as unsigned 64-bit
    let u64 = @strconv.parse_uint64(trimmed) catch {
      _ => raise WatError::InvalidNumber(s, default_loc())
    }
    u64.reinterpret_as_int64()
  }
}

///|
fn parse_hex_u64(s : String) -> Int64 raise WatError {
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
      None => raise WatError::InvalidNumber(s, default_loc())
    }
  }
  if overflow {
    raise WatError::InvalidNumber(s, default_loc())
  }
  result.reinterpret_as_int64()
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
      raise WatError::InvalidNumber(s, default_loc())
    }
  } else if trimmed.has_prefix("-0x") || trimmed.has_prefix("-0X") {
    if trimmed.length() > 3 {
      let hex_part = StringBuilder::new()
      for i in 3..<trimmed.length() {
        hex_part.write_char(trimmed.code_unit_at(i).unsafe_to_char())
      }
      -parse_hex_int64(hex_part.to_string())
    } else {
      raise WatError::InvalidNumber(s, default_loc())
    }
  } else {
    // Try signed first, then unsigned (for values like 18446744073709551615 which is -1 in i64)
    let result = @strconv.parse_int64(trimmed) catch {
      _ => {
        // Try parsing as unsigned and reinterpret
        let u64 = @strconv.parse_uint64(trimmed) catch {
          _ => raise WatError::InvalidNumber(s, default_loc())
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
      None => raise WatError::InvalidNumber(s, default_loc())
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
  // Use precise decimal to float conversion to avoid double rounding
  parse_decimal_float32_precise(s)
}

///|
/// Big integer representation using Array[UInt64] in little-endian order
/// Each element holds a 64-bit limb
priv struct BigUInt {
  limbs : Array[UInt64]
}

///|
fn BigUInt::from_int(n : Int) -> BigUInt {
  if n == 0 {
    { limbs: [0UL] }
  } else {
    { limbs: [n.to_int64().reinterpret_as_uint64()] }
  }
}

///|
fn BigUInt::is_zero(self : BigUInt) -> Bool {
  for limb in self.limbs {
    if limb != 0UL {
      return false
    }
  }
  true
}

///|
/// Multiply BigUInt by a small integer
fn BigUInt::mul_small(self : BigUInt, n : UInt64) -> BigUInt {
  let result : Array[UInt64] = []
  let mut carry : UInt64 = 0UL
  for limb in self.limbs {
    // We need to handle overflow carefully
    // Split limb into high and low 32 bits
    let limb_lo = limb & 0xFFFFFFFFUL
    let limb_hi = limb >> 32
    let n_lo = n & 0xFFFFFFFFUL
    let n_hi = n >> 32
    // limb * n = (limb_hi * 2^32 + limb_lo) * (n_hi * 2^32 + n_lo)
    //          = limb_hi * n_hi * 2^64 + (limb_hi * n_lo + limb_lo * n_hi) * 2^32 + limb_lo * n_lo
    let lo_lo = limb_lo * n_lo
    let lo_hi = limb_lo * n_hi
    let hi_lo = limb_hi * n_lo
    let hi_hi = limb_hi * n_hi
    // Combine: result = lo_lo + (lo_hi + hi_lo) << 32 + hi_hi << 64
    let mid = lo_hi + hi_lo
    let mid_overflow = if mid < lo_hi { 1UL } else { 0UL }
    let result_lo = lo_lo + (mid << 32)
    let carry_from_lo = if result_lo < lo_lo { 1UL } else { 0UL }
    let result_with_carry = result_lo + carry
    let carry_from_add = if result_with_carry < result_lo { 1UL } else { 0UL }
    result.push(result_with_carry)
    carry = hi_hi +
      (mid >> 32) +
      (mid_overflow << 32) +
      carry_from_lo +
      carry_from_add
  }
  if carry != 0UL {
    result.push(carry)
  }
  { limbs: result }
}

///|
/// Add another BigUInt
fn BigUInt::add(self : BigUInt, other : BigUInt) -> BigUInt {
  let result : Array[UInt64] = []
  let mut carry : UInt64 = 0UL
  let len = if self.limbs.length() > other.limbs.length() {
    self.limbs.length()
  } else {
    other.limbs.length()
  }
  for i in 0..<len {
    let a = if i < self.limbs.length() { self.limbs[i] } else { 0UL }
    let b = if i < other.limbs.length() { other.limbs[i] } else { 0UL }
    let sum = a + b
    let c1 = if sum < a { 1UL } else { 0UL }
    let sum2 = sum + carry
    let c2 = if sum2 < sum { 1UL } else { 0UL }
    result.push(sum2)
    carry = c1 + c2
  }
  if carry != 0UL {
    result.push(carry)
  }
  { limbs: result }
}

///|
/// Compare two BigUInts: returns -1 if self < other, 0 if equal, 1 if self > other
fn BigUInt::compare(self : BigUInt, other : BigUInt) -> Int {
  // Remove leading zeros for comparison
  let mut self_len = self.limbs.length()
  while self_len > 1 && self.limbs[self_len - 1] == 0UL {
    self_len -= 1
  }
  let mut other_len = other.limbs.length()
  while other_len > 1 && other.limbs[other_len - 1] == 0UL {
    other_len -= 1
  }
  if self_len != other_len {
    return if self_len < other_len { -1 } else { 1 }
  }
  for i = self_len - 1; i >= 0; i = i - 1 {
    if self.limbs[i] < other.limbs[i] {
      return -1
    }
    if self.limbs[i] > other.limbs[i] {
      return 1
    }
  }
  0
}

///|
/// Left shift by n bits
impl Shl for BigUInt with shl(self, n) {
  if n == 0 {
    return { limbs: self.limbs.copy() }
  }
  let limb_shift = n / 64
  let bit_shift = n % 64
  let result : Array[UInt64] = []
  // Add zero limbs for limb shift
  for _ in 0..<limb_shift {
    result.push(0UL)
  }
  if bit_shift == 0 {
    for limb in self.limbs {
      result.push(limb)
    }
  } else {
    let mut carry : UInt64 = 0UL
    for limb in self.limbs {
      result.push((limb << bit_shift) | carry)
      carry = limb >> (64 - bit_shift)
    }
    if carry != 0UL {
      result.push(carry)
    }
  }
  { limbs: result }
}

///|
/// Right shift by n bits
impl Shr for BigUInt with shr(self, n) {
  if n == 0 {
    return { limbs: self.limbs.copy() }
  }
  let limb_shift = n / 64
  let bit_shift = n % 64
  if limb_shift >= self.limbs.length() {
    return { limbs: [0UL] }
  }
  let result : Array[UInt64] = []
  if bit_shift == 0 {
    for i in limb_shift..<self.limbs.length() {
      result.push(self.limbs[i])
    }
  } else {
    for i in limb_shift..<self.limbs.length() {
      let lo = self.limbs[i] >> bit_shift
      let hi = if i + 1 < self.limbs.length() {
        self.limbs[i + 1] << (64 - bit_shift)
      } else {
        0UL
      }
      result.push(lo | hi)
    }
  }
  // Remove leading zeros
  while result.length() > 1 && result[result.length() - 1] == 0UL {
    result.pop() |> ignore
  }
  { limbs: result }
}

///|
/// Get the highest set bit position (0-indexed from LSB), -1 if zero
fn BigUInt::bit_length(self : BigUInt) -> Int {
  let mut idx = self.limbs.length() - 1
  while idx >= 0 && self.limbs[idx] == 0UL {
    idx -= 1
  }
  if idx < 0 {
    return 0
  }
  let mut bits = idx * 64
  let mut val = self.limbs[idx]
  while val != 0UL {
    bits += 1
    val = val >> 1
  }
  bits
}

///|
/// Extract bits [start, start+count) as UInt64, where bit 0 is LSB
fn BigUInt::extract_bits(self : BigUInt, start : Int, count : Int) -> UInt64 {
  if count == 0 || count > 64 {
    return 0UL
  }
  let limb_idx = start / 64
  let bit_idx = start % 64
  if limb_idx >= self.limbs.length() {
    return 0UL
  }
  let lo = self.limbs[limb_idx] >> bit_idx
  if bit_idx + count <= 64 {
    // All bits from one limb
    lo & ((1UL << count) - 1UL)
  } else {
    // Need bits from next limb too
    let hi = if limb_idx + 1 < self.limbs.length() {
      self.limbs[limb_idx + 1]
    } else {
      0UL
    }
    let combined = lo | (hi << (64 - bit_idx))
    combined & ((1UL << count) - 1UL)
  }
}

///|
/// Check if any bit below position n is set (for sticky bit calculation)
fn BigUInt::has_bits_below(self : BigUInt, n : Int) -> Bool {
  if n <= 0 {
    return false
  }
  let full_limbs = n / 64
  let remaining_bits = n % 64
  for i in 0..<full_limbs {
    if i < self.limbs.length() && self.limbs[i] != 0UL {
      return true
    }
  }
  if remaining_bits > 0 && full_limbs < self.limbs.length() {
    let mask = (1UL << remaining_bits) - 1UL
    if (self.limbs[full_limbs] & mask) != 0UL {
      return true
    }
  }
  false
}

///|
/// Parse decimal floating-point literal to Float with precise rounding.
/// Parses directly from string using big integer arithmetic to avoid double rounding.
fn parse_decimal_float32_precise(s : String) -> Float raise WatError {
  // Parse the decimal string into components
  let mut idx = 0
  let mut neg = false

  // Handle sign
  if idx < s.length() && s.code_unit_at(idx).unsafe_to_char() == '-' {
    neg = true
    idx += 1
  } else if idx < s.length() && s.code_unit_at(idx).unsafe_to_char() == '+' {
    idx += 1
  }

  // Collect all significant digits and track decimal point position
  let digits : Array[Int] = []
  let mut decimal_pos = -1
  let mut seen_digit = false
  let mut leading_zeros_after_dot = 0
  while idx < s.length() {
    let c = s.code_unit_at(idx).unsafe_to_char()
    if c >= '0' && c <= '9' {
      if digits.length() == 0 && c == '0' {
        if decimal_pos >= 0 {
          // Leading zero after decimal point - count for exponent adjustment
          leading_zeros_after_dot += 1
        }
        // Leading zeros before decimal point - just skip
        seen_digit = true
        idx += 1
        continue
      }
      digits.push(c.to_int() - '0'.to_int())
      seen_digit = true
      idx += 1
    } else if c == '.' {
      if decimal_pos >= 0 {
        raise WatError::InvalidNumber(s, default_loc())
      }
      decimal_pos = digits.length()
      idx += 1
    } else if c == 'e' || c == 'E' {
      idx += 1
      break
    } else if c == '_' {
      idx += 1
      continue
    } else {
      break
    }
  }
  if !seen_digit {
    raise WatError::InvalidNumber(s, default_loc())
  }
  if decimal_pos < 0 {
    decimal_pos = digits.length()
  }

  // Parse exponent
  let mut exp = 0
  let mut exp_neg = false
  if idx < s.length() {
    let c = s.code_unit_at(idx).unsafe_to_char()
    if c == '-' {
      exp_neg = true
      idx += 1
    } else if c == '+' {
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
  if exp_neg {
    exp = -exp
  }

  // Handle zero
  if digits.length() == 0 {
    if neg {
      return Float::reinterpret_from_uint(0x80000000U)
    }
    return (0.0 : Float)
  }

  // Calculate the decimal exponent
  // value = (digits as integer) * 10^decimal_exp
  // decimal_exp = exp - (number of digits after decimal point) - leading_zeros_after_dot
  let decimal_exp = exp -
    (digits.length() - decimal_pos) -
    leading_zeros_after_dot

  // Convert digits to BigUInt
  let mut mantissa = BigUInt::from_int(0)
  for d in digits {
    mantissa = mantissa.mul_small(10UL)
    mantissa = mantissa.add(BigUInt::from_int(d))
  }
  if mantissa.is_zero() {
    if neg {
      return Float::reinterpret_from_uint(0x80000000U)
    }
    return (0.0 : Float)
  }

  // Now we need to compute: mantissa * 10^decimal_exp as a binary float
  // 10^n = 2^n * 5^n
  // So mantissa * 10^decimal_exp = mantissa * 2^decimal_exp * 5^decimal_exp
  //
  // For decimal_exp >= 0: multiply mantissa by 5^decimal_exp, then shift left by decimal_exp
  // For decimal_exp < 0: we need to divide by 5^|decimal_exp| and shift right by |decimal_exp|
  //
  // For division, we use: mantissa * 2^extra_bits / 5^|decimal_exp| to get enough precision

  let mut binary_exp = 0
  let mut sig : BigUInt = { limbs: mantissa.limbs.copy() }
  if decimal_exp >= 0 {
    // Multiply by 5^decimal_exp
    for _ in 0..<decimal_exp {
      sig = sig.mul_small(5UL)
    }
    binary_exp = decimal_exp
  } else {
    // We need to compute mantissa / 5^|decimal_exp| with enough precision
    // Strategy: multiply mantissa by 2^extra_bits, then divide by 5^|decimal_exp|
    // We need at least 24 + 2 (guard, round) + some extra bits for precision
    // For subnormal numbers, we need up to 149 extra bits (f32 subnormal range)
    // Use 256 extra bits to be safe for all cases
    let extra_bits = 256
    let abs_exp = -decimal_exp

    // Compute 5^abs_exp
    let mut power_of_5 = BigUInt::from_int(1)
    for _ in 0..<abs_exp {
      power_of_5 = power_of_5.mul_small(5UL)
    }

    // Shift sig left by extra_bits
    sig = sig << extra_bits

    // Divide sig by power_of_5 using repeated subtraction (slow but correct)
    // For efficiency, we use a simple long division approach
    let quotient = bigint_div(sig, power_of_5)
    sig = quotient

    // Adjust binary exponent:
    // We want: mantissa * 10^(-abs_exp) = mantissa / (2^abs_exp * 5^abs_exp)
    // We computed: quotient = mantissa * 2^extra_bits / 5^abs_exp
    // So: quotient * 2^binary_exp = mantissa / (2^abs_exp * 5^abs_exp)
    // => binary_exp = -abs_exp - extra_bits
    binary_exp = -abs_exp - extra_bits
  }

  // Now sig contains the significand, and the value is sig * 2^binary_exp
  // Normalize: find the position of the highest bit
  let bit_len = sig.bit_length()
  if bit_len == 0 {
    if neg {
      return Float::reinterpret_from_uint(0x80000000U)
    }
    return (0.0 : Float)
  }

  // IEEE 754 float has 23 explicit mantissa bits (24 total with implicit 1)
  // We want the leading 1 at position 23 (0-indexed)
  // So we need to extract bits [bit_len-24, bit_len) for mantissa
  // Round bit is at position bit_len-25, sticky bits are below that

  // Adjust binary_exp: the value is sig * 2^binary_exp
  // sig has bit_len bits, so sig = (1.xxx) * 2^(bit_len-1) in binary
  // Therefore: value = (1.xxx) * 2^(bit_len-1+binary_exp)
  // The IEEE exponent (unbiased) is: bit_len - 1 + binary_exp

  let ieee_exp_unbiased = binary_exp + bit_len - 1
  let ieee_exp = ieee_exp_unbiased + 127

  // Check for overflow
  if ieee_exp >= 255 {
    // Infinity
    if neg {
      return Float::reinterpret_from_uint(0xFF800000U)
    }
    return Float::reinterpret_from_uint(0x7F800000U)
  }

  // Check for underflow (subnormal or zero)
  if ieee_exp <= 0 {
    // Subnormal: the value is sig * 2^binary_exp
    // For subnormal f32, we need to represent as mantissa * 2^(-149)
    // where mantissa is at most 23 bits (no implicit leading 1)
    //
    // The effective exponent for subnormal is fixed at -149 (unbiased: -126 - 23)
    // We need to shift sig right so that its value becomes mantissa * 2^(-149)
    //
    // Currently: value = sig * 2^binary_exp
    // Target:    value = mantissa * 2^(-149)
    // So: mantissa = sig * 2^(binary_exp + 149)
    //
    // If binary_exp + 149 < 0, we need to shift sig right by -(binary_exp + 149)
    // If binary_exp + 149 >= 0, we need to shift sig left

    let target_exp = -149
    let shift_amount = binary_exp - target_exp // = binary_exp + 149
    let (shifted_sig, extra_round, extra_sticky) = if shift_amount >= 0 {
      // Shift left - no precision loss
      (sig << shift_amount, false, false)
    } else {
      // Shift right - may lose precision
      // Round bit is at position (right_shift - 1) in original sig
      // Sticky bits are below that
      let right_shift = -shift_amount
      let round = if right_shift > 0 {
        sig.extract_bits(right_shift - 1, 1) != 0UL
      } else {
        false
      }
      let sticky = if right_shift > 1 {
        sig.has_bits_below(right_shift - 1)
      } else {
        false
      }
      (sig >> right_shift, round, sticky)
    }
    let shifted_bit_len = shifted_sig.bit_length()
    if shifted_bit_len == 0 {
      // Underflow to zero, but check if we should round up to 1
      if extra_round && (extra_sticky || true) {
        // Round up from 0 to 1
        let sign_bit : UInt = if neg { 0x80000000U } else { 0U }
        let result_bits = sign_bit | 1U
        return Float::reinterpret_from_uint(result_bits)
      }
      if neg {
        return Float::reinterpret_from_uint(0x80000000U)
      }
      return (0.0 : Float)
    }

    // For subnormal, mantissa is at most 23 bits
    // If shifted_sig has more than 23 bits, we need to truncate and round
    if shifted_bit_len <= 23 {
      // All bits fit in mantissa
      // Round bit and sticky come from the earlier shift
      let raw_mantissa = shifted_sig.extract_bits(0, shifted_bit_len)
      let mut final_mantissa = raw_mantissa.reinterpret_as_int64().to_int()
      if extra_round && (extra_sticky || (final_mantissa & 1) != 0) {
        final_mantissa += 1
      }
      // Check if rounding promoted to normal
      if final_mantissa >= 0x800000 {
        let result_bits = if neg { 0x80800000U } else { 0x00800000U }
        return Float::reinterpret_from_uint(result_bits)
      }
      let sign_bit : UInt = if neg { 0x80000000U } else { 0U }
      let result_bits = sign_bit | final_mantissa.reinterpret_as_uint()
      return Float::reinterpret_from_uint(result_bits)
    }

    // shifted_bit_len > 23: need to extract top 23 bits and round
    let mantissa_start = shifted_bit_len - 23
    let raw_mantissa = shifted_sig.extract_bits(mantissa_start, 23)

    // Round bit is at position mantissa_start - 1 in shifted_sig
    let round_pos = mantissa_start - 1
    let round_bit = shifted_sig.extract_bits(round_pos, 1) != 0UL

    // Sticky bits are all bits below round_pos in shifted_sig, plus extra from earlier shift
    let sticky = extra_round ||
      extra_sticky ||
      (round_pos > 0 && shifted_sig.has_bits_below(round_pos))

    // Round to nearest, ties to even
    let mut final_mantissa = raw_mantissa.reinterpret_as_int64().to_int()
    if round_bit && (sticky || (final_mantissa & 1) != 0) {
      final_mantissa += 1
    }

    // Check if rounding promoted to normal (mantissa >= 2^23)
    if final_mantissa >= 0x800000 {
      // Became normal with exp = 1
      let result_bits = if neg { 0x80800000U } else { 0x00800000U }
      return Float::reinterpret_from_uint(result_bits)
    }
    let sign_bit : UInt = if neg { 0x80000000U } else { 0U }
    let result_bits = sign_bit | final_mantissa.reinterpret_as_uint()
    return Float::reinterpret_from_uint(result_bits)
  }

  // Normal number: extract 23-bit mantissa (the leading 1 is implicit)
  // The top bit is at position bit_len - 1
  // We want bits [bit_len - 24, bit_len - 1) for the 23-bit mantissa
  let mantissa_start = bit_len - 24

  // Handle small numbers where bit_len < 24
  // In this case, we need to shift sig left to align the bits properly
  let (raw_mantissa, round_bit, sticky) = if mantissa_start < 0 {
    // Shift sig left to align the leading bit at position 23
    let shift = -mantissa_start
    let shifted_sig = sig << shift
    // Extract mantissa (bits 0-22, removing the implicit leading 1 at bit 23)
    let mantissa = shifted_sig.extract_bits(0, 23)
    // No round bit or sticky bits since we're shifting left (adding zeros)
    (mantissa, 0UL, false)
  } else {
    // Normal case: extract bits from the correct position
    let mantissa = sig.extract_bits(mantissa_start, 23)
    let round = sig.extract_bits(mantissa_start - 1, 1)
    let sticky_bits = sig.has_bits_below(mantissa_start - 1)
    (mantissa, round, sticky_bits)
  }

  // Round to nearest, ties to even
  let mut final_mantissa = raw_mantissa.reinterpret_as_int64().to_int()
  if round_bit != 0UL && (sticky || (final_mantissa & 1) != 0) {
    final_mantissa += 1
  }

  // Check if rounding overflowed the mantissa
  let mut final_exp = ieee_exp
  if final_mantissa >= 0x800000 {
    final_mantissa = 0
    final_exp += 1
  }

  // Check for overflow after rounding
  if final_exp >= 255 {
    if neg {
      return Float::reinterpret_from_uint(0xFF800000U)
    }
    return Float::reinterpret_from_uint(0x7F800000U)
  }

  // Construct IEEE 754 bit pattern
  let sign_bit : UInt = if neg { 0x80000000U } else { 0U }
  let exp_bits = ((final_exp & 0xFF) << 23).reinterpret_as_uint()
  let mantissa_bits_u = (final_mantissa & 0x7FFFFF).reinterpret_as_uint()
  Float::reinterpret_from_uint(sign_bit | exp_bits | mantissa_bits_u)
}

///|
/// Simple big integer division: returns quotient of a / b
fn bigint_div(a : BigUInt, b : BigUInt) -> BigUInt {
  // Handle simple cases
  if b.is_zero() {
    // Division by zero - shouldn't happen in our use case
    return BigUInt::from_int(0)
  }
  let cmp = a.compare(b)
  if cmp < 0 {
    return BigUInt::from_int(0)
  }
  if cmp == 0 {
    return BigUInt::from_int(1)
  }

  // Binary long division
  let a_bits = a.bit_length()
  let mut quotient = BigUInt::from_int(0)
  let mut remainder = BigUInt::from_int(0)

  // Process bits from high to low
  for i = a_bits - 1; i >= 0; i = i - 1 {
    // Shift remainder left by 1 and add next bit of a
    remainder = remainder << 1
    let bit = a.extract_bits(i, 1)
    if bit != 0UL {
      remainder = remainder.add(BigUInt::from_int(1))
    }
    // If remainder >= b, subtract b and set quotient bit
    if remainder.compare(b) >= 0 {
      remainder = bigint_sub(remainder, b)
      // Set bit i in quotient
      let bit_to_set = BigUInt::from_int(1) << i
      quotient = quotient.add(bit_to_set)
    }
  }
  quotient
}

///|
/// Subtract b from a (assumes a >= b)
fn bigint_sub(a : BigUInt, b : BigUInt) -> BigUInt {
  let result : Array[UInt64] = []
  let mut borrow : UInt64 = 0UL
  for i in 0..<a.limbs.length() {
    let av = a.limbs[i]
    let bv = if i < b.limbs.length() { b.limbs[i] } else { 0UL }
    let diff = av - bv - borrow
    // Check for borrow
    borrow = if av < bv + borrow { 1UL } else { 0UL }
    result.push(diff)
  }
  // Remove leading zeros
  while result.length() > 1 && result[result.length() - 1] == 0UL {
    result.pop() |> ignore
  }
  { limbs: result }
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
  let mut int_bits_overflow = 0 // Extra integer bits that didn't fit
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
          // Beyond 64 bits
          if !seen_dot {
            // Integer part overflow - these bits add to the exponent
            int_bits_overflow += 4
          }
          if v != 0 {
            extra_bits = true
          }
        }
        idx += 1
      }
      None => raise WatError::InvalidNumber(s, default_loc())
    }
  }
  if !seen_digit {
    significand = 0UL
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

  // Handle zero
  if significand == 0UL {
    return if neg { (-0.0 : Float) } else { (0.0 : Float) }
  }

  // Calculate the binary exponent
  // int_bits_overflow accounts for integer bits that didn't fit in significand
  let total_exp = if exp_neg {
    -exp - frac_bits + int_bits_overflow
  } else {
    exp - frac_bits + int_bits_overflow
  }

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
    let mantissa = ((shifted_sig >> 40) & 0x7FFFFFUL)
      .reinterpret_as_int64()
      .to_int()
    let round_bit = (shifted_sig >> 39) & 1UL
    let sticky_bits = (shifted_sig & 0x7FFFFFFFFFUL) != 0UL ||
      extra_bits ||
      (shift > 0 && (norm_sig & ((1UL << shift) - 1UL)) != 0UL)
    let mantissa_rounded = if round_bit != 0UL &&
      (sticky_bits || (mantissa & 1) != 0) {
      mantissa + 1
    } else {
      mantissa
    }

    // Check if rounding promoted to normal
    if mantissa_rounded >= 0x800000 {
      let final_mantissa = (mantissa_rounded & 0x7FFFFF).reinterpret_as_uint()
      let bits = if neg {
        0x80800000U | final_mantissa
      } else {
        0x00800000U | final_mantissa
      }
      return Float::reinterpret_from_uint(bits)
    }
    let sign_bit : UInt = if neg { 0x80000000U } else { 0U }
    let bits = sign_bit | mantissa_rounded.reinterpret_as_uint()
    return Float::reinterpret_from_uint(bits)
  }

  // Normal number
  // Extract 23-bit mantissa from norm_sig (bits 62-40, since bit 63 is the implicit 1)
  // Round bit is bit 39, sticky bits are bits 38-0 plus extra_bits
  let mantissa_raw = ((norm_sig >> 40) & 0x7FFFFFUL)
    .reinterpret_as_int64()
    .to_int()
  let round_bit = (norm_sig >> 39) & 1UL
  let sticky_bits = (norm_sig & 0x7FFFFFFFFFUL) != 0UL || extra_bits

  // Round to nearest, ties to even
  let mantissa_rounded = if round_bit != 0UL &&
    (sticky_bits || (mantissa_raw & 1) != 0) {
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
    _ => raise WatError::InvalidNumber(s, default_loc())
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

  // Parse significand as a 64-bit integer, tracking the binary exponent
  let mut significand : UInt64 = 0UL
  let mut frac_bits = 0
  let mut int_bits_overflow = 0 // Extra integer bits that didn't fit
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
          if seen_dot {
            frac_bits += 4
          }
        } else {
          // Beyond 64 bits
          if !seen_dot {
            // Integer part overflow - these bits add to the exponent
            int_bits_overflow += 4
          }
          if v != 0 {
            extra_bits = true
          }
        }
        idx += 1
      }
      None => raise WatError::InvalidNumber(s, default_loc())
    }
  }
  if !seen_digit {
    significand = 0UL
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

  // Handle zero
  if significand == 0UL {
    return if neg { -0.0 } else { 0.0 }
  }

  // Calculate the binary exponent
  // int_bits_overflow accounts for integer bits that didn't fit in significand
  let total_exp = if exp_neg {
    -exp - frac_bits + int_bits_overflow
  } else {
    exp - frac_bits + int_bits_overflow
  }

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

  // IEEE 754 double: value = 2^(ieee_exp - 1023) * (1 + mantissa/2^52)
  let ieee_exp = norm_exp + 1023

  // Check for overflow (infinity)
  if ieee_exp >= 2047 {
    return if neg {
      -1.0 / 0.0 // -infinity
    } else {
      1.0 / 0.0 // +infinity
    }
  }

  // Check for underflow (subnormal or zero)
  if ieee_exp <= 0 {
    let shift = 1 - ieee_exp
    if shift >= 64 {
      // NOTE: Work around MoonBit compiler bug with conditional float literals
      let sign_bit : Int64 = if neg { 0x8000000000000000L } else { 0L }
      return sign_bit.reinterpret_as_double()
    }
    let shifted_sig = norm_sig >> shift
    // For double subnormal: mantissa is bits 62-11 of shifted_sig (52 bits)
    // Round bit is bit 10, sticky bits are bits 9-0 plus extra_bits
    let mantissa = ((shifted_sig >> 11) & 0xFFFFFFFFFFFFFUL).reinterpret_as_int64()
    let round_bit = (shifted_sig >> 10) & 1UL
    let sticky_bits = (shifted_sig & 0x3FFUL) != 0UL ||
      extra_bits ||
      (shift > 0 && (norm_sig & ((1UL << shift) - 1UL)) != 0UL)
    let mantissa_rounded = if round_bit != 0UL &&
      (sticky_bits || (mantissa & 1L) != 0L) {
      mantissa + 1L
    } else {
      mantissa
    }

    // Check if rounding promoted to normal
    if mantissa_rounded >= 0x10000000000000L {
      let final_mantissa = mantissa_rounded & 0xFFFFFFFFFFFFFL
      let bits = if neg {
        0x8010000000000000L | final_mantissa
      } else {
        0x0010000000000000L | final_mantissa
      }
      return bits.reinterpret_as_double()
    }
    let sign_bit : Int64 = if neg { 0x8000000000000000L } else { 0L }
    let bits = sign_bit | mantissa_rounded
    return bits.reinterpret_as_double()
  }

  // Normal number
  // Extract 52-bit mantissa from norm_sig (bits 62-11, since bit 63 is the implicit 1)
  // Round bit is bit 10, sticky bits are bits 9-0 plus extra_bits
  let mantissa_raw = ((norm_sig >> 11) & 0xFFFFFFFFFFFFFUL).reinterpret_as_int64()
  let round_bit = (norm_sig >> 10) & 1UL
  let sticky_bits = (norm_sig & 0x3FFUL) != 0UL || extra_bits

  // Round to nearest, ties to even
  let mantissa_rounded = if round_bit != 0UL &&
    (sticky_bits || (mantissa_raw & 1L) != 0L) {
    mantissa_raw + 1L
  } else {
    mantissa_raw
  }

  // Check if rounding overflowed the mantissa
  let (final_exp, final_mantissa) = if mantissa_rounded >= 0x10000000000000L {
    (ieee_exp + 1, 0L)
  } else {
    (ieee_exp, mantissa_rounded & 0xFFFFFFFFFFFFFL)
  }

  // Check for overflow after rounding
  if final_exp >= 2047 {
    return if neg { -1.0 / 0.0 } else { 1.0 / 0.0 }
  }

  // Construct IEEE 754 bit pattern
  let sign_bit : Int64 = if neg { 0x8000000000000000L } else { 0L }
  let exp_bits = (final_exp.to_int64() & 0x7FFL) << 52
  let bits = sign_bit | exp_bits | final_mantissa
  bits.reinterpret_as_double()
}
