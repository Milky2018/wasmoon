#!/usr/bin/env python3
"""Compare native HTTP startup across Windows subprocess configurations."""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--wasmoon', type=Path, required=True)
    parser.add_argument('--upstream', type=Path, required=True)
    args = parser.parse_args()
    binary = str(args.wasmoon.resolve())
    suite = args.upstream.resolve() / 'tests/rust/testsuite/wasm32-wasip3'
    for case in ['http-response', 'http-request-options', 'http-service']:
        for grouped in [False, True]:
            for pipes in [False, True]:
                service = case == 'http-service'
                command = ([binary, 'serve', '--addr', '127.0.0.1:0'] if service else
                           [binary, 'component', '--run', '--http'])
                command += ['--no-jit', str(suite / (case + '.wasm'))]
                with tempfile.TemporaryFile() as out, tempfile.TemporaryFile() as err:
                    process = subprocess.Popen(command, stdin=subprocess.PIPE,
                        stdout=subprocess.PIPE if pipes else out,
                        stderr=subprocess.PIPE if pipes else err,
                        creationflags=subprocess.CREATE_NEW_PROCESS_GROUP if grouped else 0)
                    timed_out = False
                    try:
                        process.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        timed_out = True
                        process.kill()
                    stdout, stderr = process.communicate(timeout=5)
                    if not pipes:
                        out.seek(0)
                        err.seek(0)
                        stdout, stderr = out.read(), err.read()
                    print(json.dumps(dict(case=case, grouped=grouped, pipes=pipes,
                        timed_out=timed_out, returncode=process.returncode,
                        stdout=stdout.decode('utf-8', errors='backslashreplace'),
                        stderr=stderr.decode('utf-8', errors='backslashreplace'))), flush=True)


if __name__ == '__main__':
    main()
