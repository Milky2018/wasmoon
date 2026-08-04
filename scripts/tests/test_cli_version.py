"""Pin the CLI's reported version to the module manifest.

MoonBit gives a program no way to read its own `moon.mod`, so the version
`wasmoon --version` prints is a constant in the source. The manifest stays
the single source of truth; this is what keeps the copy from drifting away
from it.
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

    def test_version_flag_is_declared(self) -> None:
        # A constant nothing reads would pass the check above while
        # `--version` stayed missing, which is the state this replaced.
        self.assertRegex(
            MAIN.read_text(),
            r'"version":\s*@clap\.Arg::flag\(',
            "main.mbt no longer declares a top-level --version flag",
        )


if __name__ == "__main__":
    unittest.main()
