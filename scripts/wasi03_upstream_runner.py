"""Run the pinned upstream suite with numeric loopback fixture names."""
from pathlib import Path
from socketserver import TCPServer
import sys


def bind_endpoint(server):
    # HTTPServer resolves server_name even for 127.0.0.1. The pinned fixture
    # only needs its numeric loopback address and ephemeral port.
    TCPServer.server_bind(server)
    server.server_name, server.server_port = server.server_address[:2]


def main():
    upstream = Path(sys.argv.pop(1)).resolve()
    sys.path.insert(0, str(upstream / "test-runner"))
    from wasi_test_runner import test_suite_runner
    from wasi_test_runner.__main__ import main as upstream_main

    test_suite_runner._EndpointServer.server_bind = bind_endpoint
    return upstream_main()


if __name__ == "__main__":
    sys.exit(main())
