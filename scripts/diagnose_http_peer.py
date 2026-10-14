#!/usr/bin/env python3
"""Compare the previous HTTP peer close with complete request consumption.

This records diagnostic observations; test_wasi_http.py owns the acceptance gate.
"""
import argparse
import json
from pathlib import Path
import subprocess

import test_wasi_http as suite


def read_headers_only(connection, received):
    while b"\r\n\r\n" not in received:
        chunk = connection.recv(4096)
        assert chunk, "guest closed before sending HTTP headers"
        received.extend(chunk)
    assert received.startswith(b"GET / HTTP/1.1\r\n"), received


def main():
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument("--wasmoon", required=True, type=Path)
    parser.add_argument("--output", type=Path, default=suite.ROOT / "target/http-peer-diagnostic")
    args = parser.parse_args()
    complete_request = suite.read_mixed_request
    observations = []
    for name, reader in [("headers-only", read_headers_only), ("complete-request", complete_request)]:
        suite.read_mixed_request = reader
        for debug in [False, True]:
            for attempt in range(3):
                output = args.output / name / ("debug" if debug else "quiet") / str(attempt)
                try:
                    suite.mixed_command_case(args.wasmoon.resolve(), False, output, debug=debug)
                except (AssertionError, subprocess.TimeoutExpired, OSError) as error:
                    outcome = repr(error)
                else:
                    outcome = "success"
                request = (output / "mixed-interpreter/request.bin").read_bytes()
                body_complete = request.partition(b"\r\n\r\n")[2] == b"0\r\n\r\n"
                observations.append(dict(peer=name, debug=debug, attempt=attempt,
                                         body_complete=body_complete, outcome=outcome))
                print(json.dumps(observations[-1]), flush=True)
    (args.output / "observations.json").write_text(json.dumps(observations, indent=2) + "\n")


if __name__ == "__main__":
    main()
