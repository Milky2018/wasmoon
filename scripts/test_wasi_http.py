#!/usr/bin/env python3
"""Exercise real HTTP components through the Wasmoon CLI on both engines."""
import argparse
import concurrent.futures
import contextlib
import sys
import http.client
from pathlib import Path
import socket
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


@contextlib.contextmanager
def serving(binary: Path, guest: Path, jit: bool, *options: str):
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
    command = [str(binary), "serve", str(guest), "--addr", f"127.0.0.1:{port}"]
    command += list(options)
    if not jit:
        command += ["--no-jit"]
    with tempfile.TemporaryFile() as log:
        process = subprocess.Popen(command, stdout=log, stderr=log)
        try:
            deadline = time.monotonic() + 30
            while True:
                if process.poll() is not None:
                    raise AssertionError("HTTP server exited before listening")
                try:
                    with socket.create_connection(("127.0.0.1", port), timeout=.2):
                        break
                except OSError:
                    if time.monotonic() >= deadline:
                        raise AssertionError("HTTP server did not listen")
                    time.sleep(.05)

            yield port
        except BaseException:
            log.seek(0)
            print(log.read().decode(errors="replace"))
            raise
        finally:
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=10)


def run_engine(binary: Path, fixtures: Path, jit: bool) -> None:
    for layers in [[], ["--middleware", str(fixtures / "middleware.wasm"), "--middleware", str(fixtures / "middleware.wasm")]]:
        with serving(binary, fixtures / "echo.wasm", jit, *layers) as port:
            def echo(data: bytes) -> None:
                connection = http.client.HTTPConnection("127.0.0.1", port, timeout=15)
                try:
                    connection.request("POST", "/echo?test=1", data)
                    response = connection.getresponse()
                    assert response.status == 200, response.status
                    assert response.read() == data
                finally:
                    connection.close()

            for data in [b"", b"hello HTTP", bytes(range(256)) * 8192]:
                echo(data)
            with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
                list(pool.map(echo, [f"request-{n}".encode() * 1024 for n in range(16)]))
            with socket.create_connection(("127.0.0.1", port), timeout=15) as connection:
                connection.sendall(b"POST /trailers HTTP/1.1\r\nHost: localhost\r\nTransfer-Encoding: chunked\r\n\r\n3\r\nabc\r\n0\r\nX-Trailer: first\r\nx-trailer: second\r\n\r\n")
                received = bytearray()
                while chunk := connection.recv(65536):
                    received.extend(chunk)
                assert received.startswith(b"HTTP/1.1 200 "), received
                assert b"abc\r\n0\r\nX-Trailer: first\r\nx-trailer: second\r\n\r\n" in received, received
            for invalid in [
                b"POST / HTTP/1.1\r\nHost: localhost\r\nContent-Length: 1\r\nContent-Length: 2\r\n\r\n",
                b"POST / HTTP/1.1\r\nHost: localhost\r\nTransfer-Encoding: chunked\r\nContent-Length: 0\r\n\r\n",
                b"GET / HTTP/1.1\r\nHost: localhost\r\nHost: other\r\n\r\n",
            ]:
                with socket.create_connection(("127.0.0.1", port), timeout=15) as connection:
                    connection.sendall(invalid)
                    assert connection.recv(4096).startswith(b"HTTP/1.1 400 ")
            # An abandoned upload must not poison subsequent requests or retain
            # a connection slot indefinitely.
            for _ in range(8):
                with socket.create_connection(("127.0.0.1", port), timeout=15) as connection:
                    connection.sendall(b"POST / HTTP/1.1\r\nHost: localhost\r\nContent-Length: 999999\r\n\r\npartial")
            echo(b"after disconnects")
            print(f"WASI HTTP {'JIT' if jit else 'interpreter'}: streaming, trailers, concurrency passed")
    with serving(binary, fixtures / "echo.wasm", jit) as upstream:
        for policy, expected in [("deny", 502), ("loopback", 200)]:
            with serving(binary, fixtures / "proxy.wasm", jit, "--network", policy) as port:
                connection = http.client.HTTPConnection("127.0.0.1", port, timeout=15)
                try:
                    connection.request("POST", "/proxy", b"forwarded body", {"Host": f"127.0.0.1:{upstream}"})
                    response = connection.getresponse()
                    assert response.status == expected, response.status
                    assert response.read() == (b"forwarded body" if expected == 200 else b"")
                finally:
                    connection.close()
    print(f"WASI HTTP {'JIT' if jit else 'interpreter'}: middleware chain, proxy, capability denial passed")


def main() -> None:
    parser = argparse.ArgumentParser(__doc__)
    parser.add_argument("--wasmoon", type=Path, required=True)
    parser.add_argument("--fixtures", type=Path, default=ROOT / "target/http-fixtures")
    args = parser.parse_args()
    subprocess.run([sys.executable, str(ROOT / "tests/http/build_fixtures.py"), "--output", str(args.fixtures)], check=True)
    for jit in [False, True]:
        run_engine(args.wasmoon.resolve(), args.fixtures.resolve(), jit)


if __name__ == "__main__":
    main()
