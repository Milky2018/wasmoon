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


def raw_exchange(port: int, request: bytes) -> bytes:
    with socket.create_connection(("127.0.0.1", port), timeout=10) as connection:
        connection.sendall(request)
        received = bytearray()
        while chunk := connection.recv(65536):
            received.extend(chunk)
        return bytes(received)


def protocol_cases(port: int) -> None:
    head = raw_exchange(port, b"HEAD / HTTP/1.1\r\nHost: localhost\r\n\r\n")
    headers, body = head.split(b"\r\n\r\n", 1)
    assert head.startswith(b"HTTP/1.1 200 ") and body == b"", head
    assert b"transfer-encoding:" not in headers.lower(), head
    for verb, target in [(b"OPTIONS", b"*"), (b"CUSTOM", b"/custom")]:
        response = raw_exchange(port, verb + b" " + target + b" HTTP/1.1\r\nHost: localhost\r\n\r\n")
        assert response.startswith(b"HTTP/1.1 200 "), response
    for expectation in [b"100-continue", b"100-Continue", b"100-CONTINUE", b"100-continue, 100-Continue"]:
        with socket.create_connection(("127.0.0.1", port), timeout=10) as connection:
            connection.sendall(b"POST / HTTP/1.1\r\nHost: localhost\r\nExpect: " + expectation + b"\r\nContent-Length: 1\r\n\r\n")
            reader = connection.makefile("rb")
            assert reader.readline() == b"HTTP/1.1 100 Continue\r\n", expectation
            assert reader.readline() == b"\r\n"
            connection.sendall(b"x")
            response = reader.read()
            assert response.startswith(b"HTTP/1.1 200 "), response
            assert response.endswith(b"1\r\nx\r\n0\r\n\r\n"), response
    absolute = raw_exchange(port, b"POST http://localhost/echo?q=1 HTTP/1.1\r\nHost: ignored.example\r\nContent-Length: 1\r\n\r\nx")
    assert absolute.startswith(b"HTTP/1.1 200 "), absolute
    for extension in [b';foo=bar', b' ; foo = "quoted;value"', b';foo="escaped\\\"quote"', b';foo="\xff"']:
        response = raw_exchange(port, b"POST / HTTP/1.1\r\nHost: localhost\r\nTransfer-Encoding: chunked\r\n\r\n1" + extension + b"\r\nx\r\n0\r\n\r\n")
        assert response.startswith(b"HTTP/1.1 200 "), response
        assert response.endswith(b"1\r\nx\r\n0\r\n\r\n"), (extension, response)
    for extension in [b';=', b';foo=', b';foo="unterminated', b';foo="bad"junk']:
        response = raw_exchange(port, b"POST / HTTP/1.1\r\nHost: localhost\r\nTransfer-Encoding: chunked\r\n\r\n1" + extension + b"\r\nx\r\n0\r\n\r\n")
        # Once the response is published, a body error must terminate it without
        # a successful last chunk; the server cannot replace its status line.
        assert not response.endswith(b"0\r\n\r\n"), (extension, response)
    with socket.create_connection(("127.0.0.1", port), timeout=10) as connection:
        connection.sendall(b"POST / HTTP/1.1\r\nHost: localhost\r\nTransfer-Encoding: chunked\r\n\r\n3\r\none\r\n")
        response = bytearray()
        while b"one" not in response:
            chunk = connection.recv(4096)
            assert chunk, response
            response.extend(chunk)
        # Do not finish the upload until response data has arrived. Buffering
        # the whole request would deadlock here and fail the socket timeout.
        connection.sendall(b"3\r\ntwo\r\n0\r\n\r\n")
        while chunk := connection.recv(4096):
            response.extend(chunk)
        assert response.endswith(b"3\r\none\r\n3\r\ntwo\r\n0\r\n\r\n"), response


def startup_cases(binary: Path, fixtures: Path, jit: bool) -> None:
    for guest, options in [("empty.wasm", []), ("echo.wasm", ["--middleware", str(fixtures / "empty.wasm")])]:
        command = [str(binary), "serve", str(fixtures / guest), "--addr", "127.0.0.1:0", *options]
        if not jit:
            command += ["--no-jit"]
        result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15)
        assert result.returncode != 0, result
        assert b"must export wasi:http/handler@0.3.0" in result.stderr, result.stderr
    with socket.socket() as listener:
        if hasattr(socket, "SO_EXCLUSIVEADDRUSE"):
            listener.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
        listener.bind(("127.0.0.1", 0))
        listener.listen()
        port = listener.getsockname()[1]
        result = subprocess.run([str(binary), "serve", str(fixtures / "echo.wasm"), "--addr", f"127.0.0.1:{port}"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15)
        assert result.returncode != 0, result


def run_engine(binary: Path, fixtures: Path, jit: bool) -> None:
    startup_cases(binary, fixtures, jit)
    with serving(binary, fixtures / "trap.wasm", jit) as port:
        for _ in range(3):
            response = raw_exchange(port, b"GET / HTTP/1.1\r\nHost: localhost\r\n\r\n")
            assert response.startswith(b"HTTP/1.1 500 "), response
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

            protocol_cases(port)
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
            for index in range(300):
                with socket.create_connection(("127.0.0.1", port), timeout=15) as connection:
                    connection.sendall(b"POST / HTTP/1.1\r\nHost: localhost\r\nContent-Length: 999999\r\n\r\npartial")
                    if index % 2:
                        assert connection.recv(4096).startswith(b"HTTP/1.1 200 ")
            echo(b"after disconnects")
            print(f"WASI HTTP {'JIT' if jit else 'interpreter'}: Expect, URI, chunk framing, incremental streaming, trailers, concurrency and 300 disconnects passed")
    for layers, expected_path in [([], "/original?q=1"), (["--middleware", str(fixtures / "outer.wasm"), "--middleware", str(fixtures / "inner.wasm")], "/inner/outer/original?q=1")]:
        with serving(binary, fixtures / "inspect.wasm", jit, *layers) as port:
            response = raw_exchange(port, b"POST http://target.example:8081/original?q=1 HTTP/1.1\r\nHost: ignored.example\r\nContent-Length: 4\r\n\r\ndata")
            assert b"x-path: " + expected_path.encode() + b"\r\n" in response, response
            assert b"x-authority: target.example:8081\r\n" in response, response
            assert response.endswith(b"4\r\ndata\r\n0\r\n\r\n"), response
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
    print(f"WASI HTTP {'JIT' if jit else 'interpreter'}: startup rejection, guest traps, middleware order, metadata, proxy and capability denial passed")


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
