# F32 Decimal Literal Double Rounding Fix

## Problem

The `const.wast` test suite had 4 failing test cases (551, 553, 555, 557) related to F32 decimal literal parsing:

```
case 551: +8.8817847263968443574e-16 → expected 0x26800001, got 0x26800000
case 553: -8.8817847263968443574e-16 → expected 0xa6800001, got 0xa6800000
case 555: +8.8817857851880284252e-16 → expected 0x26800001, got 0x26800002
case 557: -8.8817857851880284252e-16 → expected 0xa6800001, got 0xa6800002
```

All errors were off by 1 in the least significant bit of the mantissa.

## Root Cause: Double Rounding

The original implementation used `@strconv.parse_double(s)` to parse the decimal string, then converted the Double to Float using `Float::from_double(d)`. This caused **double rounding**:

1. **First rounding**: Decimal string → Double (53-bit mantissa)
2. **Second rounding**: Double → Float (24-bit mantissa)

When the decimal value falls very close to the midpoint between two adjacent Float values, the first rounding to Double loses critical precision needed to determine the correct Float rounding direction.

### Example Analysis

For `8.8817847263968443574e-16`:
- True midpoint between `0x26800000` and `0x26800001` is `8.8817847263968443573267652624...e-16`
- Input string `8.8817847263968443574e-16` is **slightly above** the midpoint (digit 19: `4` > `3`)
- Should round **up** to `0x26800001`

But when parsed as Double first:
- Double can't distinguish between the input and the true midpoint
- Double rounds to some value, losing the "slightly above" information
- Float conversion then rounds incorrectly

## Solution: Big Integer Arithmetic

Implemented a pure string-to-Float parser using arbitrary precision integer arithmetic, completely bypassing Double:

### Key Components

1. **BigUInt struct**: Arbitrary precision unsigned integer using `Array[UInt64]` limbs in little-endian order

2. **BigUInt operations**:
   - `mul_small(n: UInt64)`: Multiply by small integer with carry propagation
   - `add(other)`: Addition with carry
   - `compare(other)`: Three-way comparison
   - `shl(n)` / `op_shl`: Left shift by n bits
   - `bit_length()`: Count of significant bits
   - `extract_bits(start, count)`: Extract bit range as UInt64
   - `has_bits_below(n)`: Check if any bit below position n is set (for sticky bit)

3. **bigint_div(a, b)**: Binary long division for arbitrary precision integers

4. **bigint_sub(a, b)**: Subtraction (assumes a >= b)

### Algorithm

```
parse_decimal_float32_precise(s: String) -> Float:
  1. Parse decimal string into:
     - neg: sign
     - digits: Array[Int] of significant digits
     - decimal_exp: power of 10

  2. Convert digits to BigUInt mantissa

  3. Compute binary representation:
     if decimal_exp >= 0:
       sig = mantissa * 5^decimal_exp
       binary_exp = decimal_exp
     else:
       # mantissa * 10^(-abs_exp) = mantissa / (2^abs_exp * 5^abs_exp)
       sig = (mantissa << 128) / 5^abs_exp
       binary_exp = -abs_exp - 128

  4. Normalize and extract IEEE 754 components:
     bit_len = sig.bit_length()
     ieee_exp = binary_exp + bit_len - 1 + 127

  5. Extract 23-bit mantissa with round-to-nearest-ties-to-even:
     mantissa_start = bit_len - 24
     raw_mantissa = sig.extract_bits(mantissa_start, 23)
     round_bit = sig.extract_bits(mantissa_start - 1, 1)
     sticky = sig.has_bits_below(mantissa_start - 1)

     if round_bit && (sticky || (raw_mantissa & 1)):
       final_mantissa = raw_mantissa + 1

  6. Handle overflow/underflow and construct IEEE 754 bit pattern
```

### Key Insight: Exponent Calculation

The trickiest part was getting the binary exponent correct:

```
Value = mantissa * 10^decimal_exp
      = mantissa * 2^decimal_exp * 5^decimal_exp

For negative decimal_exp (-abs_exp):
  We compute: quotient = (mantissa << extra_bits) / 5^abs_exp
  This equals: mantissa * 2^extra_bits / 5^abs_exp

  We want: mantissa / (2^abs_exp * 5^abs_exp)

  So: quotient * 2^binary_exp = mantissa / (2^abs_exp * 5^abs_exp)
  => binary_exp = -abs_exp - extra_bits
```

Initial bug: Used `binary_exp = extra_bits - abs_exp` (wrong sign!)

Another bug: Used `ieee_exp_unbiased = binary_exp + bit_len - 24` instead of `binary_exp + bit_len - 1`

The correct formula: For a BigUInt with `bit_len` bits, the leading 1 is at position `bit_len - 1`, so:
```
value = sig * 2^binary_exp = (1.xxx) * 2^(bit_len-1) * 2^binary_exp
      = (1.xxx) * 2^(bit_len-1+binary_exp)

ieee_exp_unbiased = bit_len - 1 + binary_exp
ieee_exp = ieee_exp_unbiased + 127
```

## Files Changed

- `wat/parser.mbt`: Added BigUInt implementation and `parse_decimal_float32_precise`
- `wat/wat_test.mbt`: Added 4 test cases for the failing decimal literals

## Verification

```bash
$ moon test -p wat
Total tests: 348, passed: 348, failed: 0.

$ ./wasmoon test testsuite/data/const.wast
Results:
  Passed:  376
  Failed:  0
```

## Lessons Learned

1. **Double rounding is subtle**: When converting decimal → Float, going through Double can cause incorrect rounding for values near Float midpoints.

2. **Arbitrary precision is necessary**: For correct decimal-to-binary conversion, we need more precision than either Float (24 bits) or Double (53 bits) provides.

3. **Test edge cases systematically**: The WebAssembly test suite specifically tests these boundary cases where double rounding fails.

4. **Verify formulas carefully**: Both the binary exponent calculation and IEEE exponent formula had sign/offset errors that took debugging to identify.
