"""Native Windows readiness using real CRT handles and Winsock sockets."""
from __future__ import annotations

import ctypes
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import threading
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(os.name == "nt", "requires native Windows handles")
class WindowsPollTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.directory.cleanup)
        directory = Path(cls.directory.name)
        (directory / "moonbit.h").write_text('#define MOONBIT_FFI_EXPORT __declspec(dllexport)\n')
        library = directory / "poll.dll"
        subprocess.run([
            "clang", "-shared", "-fms-runtime-lib=dll", "-I", str(directory),
            str(ROOT / "modules/wasmoon/wasi/poll_native.c"),
            str(ROOT / "modules/wasmoon_jit/jit_ffi/windows_io.c"),
            "-Wl,/export:wasmoon_windows_socket_adopt",
            "-Wl,/export:wasmoon_windows_close",
            "-Wl,/export:wasmoon_windows_bytes_available",
            "-o", str(library),
        ], check=True)
        cls.library = ctypes.CDLL(str(library), use_errno=True)
        # Unload before TemporaryDirectory cleanup: Windows locks loaded DLLs.
        import _ctypes
        cls.addClassCleanup(_ctypes.FreeLibrary, cls.library._handle)
        cls.poll = cls.library.wasmoon_wasi_poll
        pointer = ctypes.POINTER(ctypes.c_int)
        cls.poll.argtypes = [pointer, pointer, pointer, ctypes.c_int, ctypes.c_int]
        cls.poll.restype = ctypes.c_int
        cls.adopt = cls.library.wasmoon_windows_socket_adopt
        cls.adopt.argtypes = [ctypes.c_size_t]
        cls.adopt.restype = ctypes.c_int
        cls.close = cls.library.wasmoon_windows_close
        cls.close.argtypes = [ctypes.c_int]
        cls.available = cls.library.wasmoon_windows_bytes_available
        cls.available.argtypes = [ctypes.c_int]
        cls.available.restype = ctypes.c_int64

    def readiness(self, fds, events, timeout=0):
        array = ctypes.c_int * len(fds)
        output = array()
        count = self.poll(array(*fds), array(*events), output, len(fds), timeout)
        self.assertGreaterEqual(count, 0, os.strerror(ctypes.get_errno()))
        return count, list(output)

    def pipe(self):
        reader, writer = os.pipe()
        self.addCleanup(os.close, reader)
        self.addCleanup(os.close, writer)
        return reader, writer

    def test_pending_pipe_and_null_device(self):
        reader, writer = self.pipe()
        with open(os.devnull, "rb") as null:
            self.assertEqual(self.readiness([null.fileno(), reader], [1, 1]), (1, [1, 0]))
            os.write(writer, b"abc")
            self.assertEqual(self.readiness([reader], [1]), (1, [1]))
            self.assertEqual(self.available(reader), 3)
            self.assertEqual(os.read(reader, 3), b"abc")

    def test_pipe_timeout_and_delayed_input(self):
        reader, writer = self.pipe()
        start = time.monotonic()
        self.assertEqual(self.readiness([reader], [1], 40), (0, [0]))
        self.assertGreaterEqual(time.monotonic() - start, 0.025)
        timer = threading.Timer(0.05, os.write, args=(writer, b"x"))
        timer.start()
        try:
            self.assertEqual(self.readiness([reader], [1], 1000), (1, [1]))
            self.assertEqual(os.read(reader, 1), b"x")
        finally:
            timer.join()

    def test_pipe_hangup_retains_unread_data(self):
        reader, writer = os.pipe()
        self.addCleanup(os.close, reader)
        os.write(writer, b"x")
        os.close(writer)
        count, flags = self.readiness([reader], [1], 100)
        self.assertEqual(count, 1)
        self.assertTrue(flags[0] & 16)
        self.assertTrue(flags[0] & 1)
        self.assertEqual(os.read(reader, 1), b"x")
        self.assertTrue(self.readiness([reader], [1])[1][0] & 16)

    def test_pipe_write_readiness_and_backpressure(self):
        reader, writer = self.pipe()
        self.assertEqual(self.readiness([writer], [4]), (1, [4]))
        # Write only a byte at a time while quota is available: this cannot
        # block on an unexpectedly small host pipe buffer.
        for _ in range(1024 * 1024):
            if self.readiness([writer], [4]) == (0, [0]):
                break
            os.write(writer, b"x")
        else:
            self.fail("pipe never applied backpressure")
        os.read(reader, 1)
        self.assertEqual(self.readiness([writer], [4]), (1, [4]))

    def test_regular_file_duplicate_and_invalid_descriptors(self):
        with tempfile.TemporaryFile() as file:
            self.assertEqual(self.readiness([file.fileno(), file.fileno(), -1, 1234567],
                                            [1, 4, 1, 1]), (3, [1, 4, 0, 32]))

    def test_socket_data_hangup_and_duplicate_subscriptions(self):
        reader, writer = socket.socketpair()
        self.addCleanup(writer.close)
        fd = self.adopt(reader.detach())
        self.assertGreaterEqual(fd, 0)
        self.addCleanup(self.close, fd)
        self.assertEqual(self.readiness([fd], [1], 20), (0, [0]))
        writer.sendall(b"abc")
        self.assertEqual(self.readiness([fd, fd], [1, 1], 1000), (2, [1, 1]))
        self.assertEqual(self.available(fd), 3)
        writer.shutdown(socket.SHUT_WR)
        self.assertEqual(self.readiness([fd], [1], 1000)[0], 1)

    def test_socket_and_pending_pipe(self):
        pipe_reader, _ = self.pipe()
        reader, writer = socket.socketpair()
        self.addCleanup(writer.close)
        fd = self.adopt(reader.detach())
        self.addCleanup(self.close, fd)
        writer.sendall(b"x")
        self.assertEqual(self.readiness([pipe_reader, fd], [1, 1], 1000), (1, [0, 1]))

    def test_closed_socket_is_invalid(self):
        reader, writer = socket.socketpair()
        self.addCleanup(writer.close)
        fd = self.adopt(reader.detach())
        self.assertEqual(self.close(fd), 0)
        self.assertEqual(self.readiness([fd], [1]), (1, [32]))
