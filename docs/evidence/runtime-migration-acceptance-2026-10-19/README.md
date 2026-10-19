# Runtime migration acceptance

ISS-636, ISS-638 and ISS-639 are closed against PR #542, merged as `aac8ce10`.
Its source tree equals accepted head `c6c92283`. Run 39200929903 passes all five
jobs. `ci.json` records exact head/base/artifact ancestry, sanitizer controls and
both Windows compiler results. The normal Linux sanitizer run passes 181 tests
without a leak report; a separate expected-failure control detects 17 leaked
bytes. ASan/native-ASan/LSan positive controls are all active.

A fresh macOS ARM64 release build independently verifies archive membership and
absence of `wasmoon_test_` symbols in the linked CLI (`archive.txt`). Actual
MASM bridge behavior, strict C and native execution pass on both Windows CI
lanes. This does not claim a Windows release symbol audit. Historical local
measurement receipts retain their original dirty-source state. ISS-634's
incremental-header toolchain defect and ISS-640's builtin routing are separate.
