"""Exercise the mixed-command peer's request completion boundary."""
import socket
import unittest

from scripts.test_wasi_http import read_mixed_request


HEADERS = b"GET / HTTP/1.1\r\nHost: localhost\r\nTransfer-Encoding: chunked\r\n\r\n"


class MixedCommandPeerTests(unittest.TestCase):
    def test_consumes_body_received_with_headers(self):
        reader, writer = socket.socketpair()
        with reader, writer:
            writer.sendall(HEADERS + b"0\r\n\r\n")
            writer.shutdown(socket.SHUT_WR)
            received = bytearray()
            read_mixed_request(reader, received)
            self.assertEqual(received, HEADERS + b"0\r\n\r\n")

    def test_rejects_a_truncated_empty_body(self):
        reader, writer = socket.socketpair()
        with reader, writer:
            writer.sendall(HEADERS + b"0\r\n")
            writer.shutdown(socket.SHUT_WR)
            with self.assertRaises(AssertionError):
                read_mixed_request(reader, bytearray())
