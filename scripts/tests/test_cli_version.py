"""Pin the CLI's reported version constant to the module manifest.

MoonBit gives a program no way to read its own `moon.mod`, so the version
`wasmoon --version` prints is a constant in the source. The manifest stays
the single source of truth; this keeps the copy from drifting away from it.

This reads source, so it can only see that the two strings agree -- never
that `--version` runs, or prints, or exits 0. `scripts/cli_behavior_test.py`
executes the built binary and checks all of that, and is the authority on
what the CLI does. What this adds is timing: it runs in the pre-commit hook
before anything is built, so drift is caught at the commit that causes it
rather than one CI build later.
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / "modules/wasmoon/moon.mod"
MAIN = ROOT / "modules/wasmoon/cmd/wasmoon/main.mbt"


def manifest_version() -> str:
    match = re.search(
        r'^\s*version\s*=\s*"([^"]+)"', MANIFEST.read_text(), re.MULTILINE
    )
    assert match is not None, f"no version field in {MANIFEST}"
    return match.group(1)


def cli_version() -> str:
    match = re.search(
        r'^const WASMOON_VERSION\s*:\s*String\s*=\s*"([^"]+)"',
        MAIN.read_text(),
        re.MULTILINE,
    )
    assert match is not None, f"no WASMOON_VERSION constant in {MAIN}"
    return match.group(1)


class CliVersionTest(unittest.TestCase):
    def test_cli_version_matches_manifest(self) -> None:
        self.assertEqual(
            cli_version(),
            manifest_version(),
            "wasmoon --version disagrees with modules/wasmoon/moon.mod; "
            "update WASMOON_VERSION in main.mbt to match the manifest",
        )

    def test_behaviour_test_covers_the_flag(self) -> None:
        # This file used to also grep for the flag's declaration, on the
        # grounds that a constant nothing reads would satisfy the check
        # above while `--version` stayed missing. Running the binary settles
        # that properly, so what is left to pin here is that the check which
        # runs the binary still exists and is wired into CI -- otherwise the
        # coverage silently reverts to grepping source.
        behaviour = ROOT / "scripts/cli_behavior_test.py"
        self.assertTrue(behaviour.exists(), f"{behaviour} is missing")
        workflow = (ROOT / ".github/workflows/check.yml").read_text()
        self.assertIn("python3 scripts/cli_behavior_test.py", workflow)


if __name__ == "__main__":
    unittest.main()
