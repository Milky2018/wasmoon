"""Native Windows readiness using real CRT handles and Winsock sockets."""
from __future__ import annotations

import ctypes
import errno
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
            os.environ.get("WASMOON_MSVC_CL", "clang-cl"), "/std:c11", "/D_CRT_SECURE_NO_WARNINGS", "/LD", "/MD", "/DWASMOON_POLL_TESTING", "/I" + str(directory),
            str(ROOT / "modules/wasmoon/wasi/poll_native.c"),
            str(ROOT / "modules/wasmoon_jit/host_io/windows_io.c"),
            str(ROOT / "modules/wasmoon_jit/host_io/windows_input.c"),
            "/link", "/EXPORT:wasmoon_windows_socket_adopt",
            "/EXPORT:wasmoon_windows_close",
            "/EXPORT:wasmoon_windows_bytes_available",
            "/EXPORT:wasmoon_windows_setfl", "/EXPORT:wasmoon_windows_getfl",
            "/EXPORT:wasmoon_windows_read", "/EXPORT:wasmoon_windows_dup",
            "/OUT:" + str(library),
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
        cls.adopt.argtypes = [ctypes.c_size_t, ctypes.c_int]
        cls.adopt.restype = ctypes.c_int
        cls.close = cls.library.wasmoon_windows_close
        cls.close.argtypes = [ctypes.c_int]
        cls.available = cls.library.wasmoon_windows_bytes_available
        cls.available.argtypes = [ctypes.c_int]
        cls.available.restype = ctypes.c_int64
        cls.setfl = cls.library.wasmoon_windows_setfl
        cls.setfl.argtypes = [ctypes.c_int, ctypes.c_int]
        cls.getfl = cls.library.wasmoon_windows_getfl
        cls.getfl.argtypes = [ctypes.c_int]
        cls.read = cls.library.wasmoon_windows_read
        cls.read.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_int]
        cls.claim = cls.library.wasmoon_host_claim_input
        cls.claim.argtypes = [ctypes.c_int]
        cls.release = cls.library.wasmoon_host_release_input
        cls.release.argtypes = [ctypes.c_int]
        cls.release.restype = None
        cls.duplicate = cls.library.wasmoon_windows_dup
        cls.duplicate.argtypes = [ctypes.c_int]
        cls.scans = cls.library.wasmoon_windows_poll_scan_count
        cls.scans.restype = ctypes.c_int


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

    def test_socket_nonblocking_flag_controls_actual_reads(self):
        reader, writer = socket.socketpair()
        self.addCleanup(writer.close)
        fd = self.adopt(reader.detach(), os.O_RDWR)
        self.assertGreaterEqual(fd, 0)
        self.addCleanup(self.close, fd)
        nonblocking = 0x04000000
        self.assertEqual(self.setfl(fd, os.O_RDWR | nonblocking), 0)
        self.assertTrue(self.getfl(fd) & nonblocking)
        buffer = ctypes.create_string_buffer(1)
        self.assertEqual(self.read(fd, buffer, 1), -1)
        self.assertEqual(ctypes.get_errno(), errno.EAGAIN)
        writer.sendall(b"x")
        self.assertEqual(self.read(fd, buffer, 1), 1)
        self.assertEqual(buffer.raw, b"x")
        self.assertEqual(self.setfl(fd, os.O_RDWR), 0)
        self.assertFalse(self.getfl(fd) & nonblocking)

    def test_alertable_wait_reports_interruption(self):
        reader, _ = self.pipe()
        kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        callback_type = ctypes.WINFUNCTYPE(None, ctypes.c_size_t)
        called = []
        callback = callback_type(lambda value: called.append(value))
        kernel.GetCurrentThread.restype = ctypes.c_void_p
        kernel.QueueUserAPC.argtypes = [callback_type, ctypes.c_void_p, ctypes.c_size_t]
        self.assertNotEqual(kernel.QueueUserAPC(callback, kernel.GetCurrentThread(), 7), 0)
        array = ctypes.c_int * 1
        self.assertEqual(self.poll(array(reader), array(1), array(), 1, 1000), -1)
        self.assertEqual(ctypes.get_errno(), errno.EINTR)
        self.assertEqual(called, [7])

    def test_console_line_input_is_not_consumed(self):
        self.console_line_input(False)

    def test_exclusive_console_waits_for_completed_line(self):
        self.console_line_input(True)

    def console_line_input(self, exclusive):
        import msvcrt
        from ctypes import wintypes

        class KeyEvent(ctypes.Structure):
            _fields_ = [("down", wintypes.BOOL), ("repeat", wintypes.WORD),
                        ("key", wintypes.WORD), ("scan", wintypes.WORD),
                        ("char", wintypes.WCHAR), ("control", wintypes.DWORD)]

        class Event(ctypes.Union):
            _fields_ = [("key", KeyEvent), ("storage", ctypes.c_byte * 16)]

        class InputRecord(ctypes.Structure):
            _fields_ = [("kind", wintypes.WORD), ("event", Event)]

        self.assertEqual(ctypes.sizeof(InputRecord), 20)
        kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        kernel.FreeConsole()
        self.assertTrue(kernel.AllocConsole())
        self.addCleanup(kernel.FreeConsole)
        kernel.CreateFileW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD,
                                      ctypes.c_void_p, wintypes.DWORD, wintypes.DWORD,
                                      wintypes.HANDLE]
        kernel.CreateFileW.restype = wintypes.HANDLE
        kernel.SetConsoleMode.argtypes = [wintypes.HANDLE, wintypes.DWORD]
        kernel.WriteConsoleInputW.argtypes = [wintypes.HANDLE, ctypes.POINTER(InputRecord),
                                            wintypes.DWORD, ctypes.POINTER(wintypes.DWORD)]
        kernel.GetNumberOfConsoleInputEvents.argtypes = [wintypes.HANDLE,
                                                        ctypes.POINTER(wintypes.DWORD)]
        handle = kernel.CreateFileW("CONIN$", 0xC0000000, 3, None, 3, 0, None)
        self.assertNotEqual(handle, ctypes.c_void_p(-1).value)
        fd = msvcrt.open_osfhandle(handle, os.O_BINARY)
        self.addCleanup(self.close if exclusive else os.close, fd)
        if exclusive:
            self.assertEqual(self.claim(fd), 0)
        self.assertTrue(kernel.SetConsoleMode(handle, 2))  # ENABLE_LINE_INPUT

        def enqueue(char, down):
            record = InputRecord()
            record.kind = 1  # KEY_EVENT
            record.event.key = KeyEvent(down, 1, 0, 0, char, 0)
            written = wintypes.DWORD()
            self.assertTrue(kernel.WriteConsoleInputW(handle, ctypes.byref(record), 1,
                                                      ctypes.byref(written)))
            self.assertEqual(written.value, 1)

        enqueue("\r", False)
        enqueue("x", True)
        before_scans = self.scans()
        self.assertEqual(self.readiness([fd], [1], 80 if exclusive else 0), (0, [0]))
        if exclusive:
            self.assertLessEqual(self.scans() - before_scans, 3)
        enqueue("\r", True)
        if exclusive:
            self.assertEqual(self.readiness([fd], [1], 1000), (1, [1]))
            actual = self.read_bytes(fd, 32)
            self.release(fd)
            # Compare against the native console in exactly the same mode;
            # ENABLE_LINE_INPUT alone does not promise CRLF translation.
            enqueue("x", True)
            enqueue("\r", True)
            expected = ctypes.create_string_buffer(32)
            transferred = wintypes.DWORD()
            kernel.ReadFile.argtypes = [wintypes.HANDLE, ctypes.c_void_p, wintypes.DWORD,
                                        ctypes.POINTER(wintypes.DWORD), ctypes.c_void_p]
            self.assertTrue(kernel.ReadFile(handle, expected, 32, ctypes.byref(transferred), None))
            self.assertEqual(actual, expected.raw[:transferred.value])
            self.assertTrue(actual.startswith(b"x"))
            return
        before = wintypes.DWORD()
        after = wintypes.DWORD()
        self.assertTrue(kernel.GetNumberOfConsoleInputEvents(handle, ctypes.byref(before)))
        self.assertEqual(self.readiness([fd], [1]), (1, [1]))
        self.assertTrue(kernel.GetNumberOfConsoleInputEvents(handle, ctypes.byref(after)))
        self.assertEqual(after.value, before.value)

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
        fd = self.adopt(reader.detach(), 0)
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
        fd = self.adopt(reader.detach(), 0)
        self.addCleanup(self.close, fd)
        writer.sendall(b"x")
        self.assertEqual(self.readiness([pipe_reader, fd], [1, 1], 1000), (1, [0, 1]))

    def test_closed_socket_is_invalid(self):
        reader, writer = socket.socketpair()
        self.addCleanup(writer.close)
        fd = self.adopt(reader.detach(), 0)
        self.assertEqual(self.close(fd), 0)
        self.assertEqual(self.readiness([fd], [1]), (1, [32]))

    def exclusive_pipe(self):
        reader, writer = os.pipe()
        self.addCleanup(os.close, writer)
        self.addCleanup(self.close, reader)
        self.assertEqual(self.claim(reader), 0)
        return reader, writer

    def read_bytes(self, fd, count):
        buffer = ctypes.create_string_buffer(count)
        received = self.read(fd, buffer, count)
        self.assertGreaterEqual(received, 0)
        return buffer.raw[:received]

    def test_exclusive_idle_wait_does_not_rescan_periodically(self):
        reader, _ = self.exclusive_pipe()
        before = self.scans()
        self.assertEqual(self.readiness([reader], [1], 120), (0, [0]))
        self.assertLessEqual(self.scans() - before, 3)

    def test_exclusive_input_wakes_mixed_socket_wait(self):
        reader, writer = self.exclusive_pipe()
        socket_reader, socket_writer = socket.socketpair()
        self.addCleanup(socket_writer.close)
        fd = self.adopt(socket_reader.detach(), 0)
        self.addCleanup(self.close, fd)
        before = self.scans()
        timer = threading.Timer(0.08, os.write, args=(writer, b"abc"))
        timer.start()
        try:
            self.assertEqual(self.readiness([reader, fd], [1, 1], 1000), (1, [1, 0]))
            self.assertLessEqual(self.scans() - before, 3)
            self.assertEqual(self.read_bytes(reader, 3), b"abc")
        finally:
            timer.join()

    def test_exclusive_aliases_share_partial_reads_and_eof(self):
        reader, writer = os.pipe()
        self.assertEqual(self.claim(reader), 0)
        duplicate = self.duplicate(reader)
        self.assertGreaterEqual(duplicate, 0)
        self.addCleanup(self.close, duplicate)
        os.write(writer, b"abcdef")
        os.close(writer)
        self.assertEqual(self.readiness([reader, duplicate], [1, 1], 1000)[0], 2)
        self.assertEqual(self.read_bytes(reader, 2), b"ab")
        self.assertEqual(self.close(reader), 0)
        self.assertEqual(self.available(duplicate), 4)
        self.assertEqual(self.read_bytes(duplicate, 10), b"cdef")
        self.assertEqual(self.readiness([duplicate], [1], 1000), (1, [17]))
        self.assertEqual(self.read_bytes(duplicate, 10), b"")

    def test_exclusive_nonblocking_reads_preserve_pending_operation(self):
        reader, writer = self.exclusive_pipe()
        self.assertEqual(self.setfl(reader, os.O_RDONLY | 0x04000000), 0)
        buffer = ctypes.create_string_buffer(1)
        self.assertEqual(self.read(reader, buffer, 0), 0)
        self.assertEqual(self.read(reader, buffer, 1), -1)
        self.assertEqual(ctypes.get_errno(), errno.EAGAIN)
        os.write(writer, b"x")
        self.assertEqual(self.readiness([reader], [1], 1000), (1, [1]))
        self.assertEqual(self.read_bytes(reader, 1), b"x")

    def test_exclusive_release_cancels_idle_read_and_restores_shared_input(self):
        reader, writer = self.exclusive_pipe()
        for _ in range(20):
            self.assertEqual(self.readiness([reader], [1], 0), (0, [0]))
            start = time.monotonic()
            self.release(reader)
            self.assertLess(time.monotonic() - start, 1)
            os.write(writer, b"x")
            self.assertEqual(os.read(reader, 1), b"x")
            self.assertEqual(self.claim(reader), 0)

    def test_duplex_pipe_claim_preserves_shared_write_semantics(self):
        import msvcrt
        from ctypes import wintypes
        kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        kernel.CreateNamedPipeW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD,
            wintypes.DWORD, wintypes.DWORD, wintypes.DWORD, wintypes.DWORD,
            wintypes.DWORD, ctypes.c_void_p]
        kernel.CreateNamedPipeW.restype = wintypes.HANDLE
        name = rf"\\.\pipe\wasmoon-input-{os.getpid()}-{id(self)}"
        handle = kernel.CreateNamedPipeW(name, 3 | 0x80000, 0, 1, 4096, 4096, 0, None)
        self.assertNotEqual(handle, ctypes.c_void_p(-1).value)
        fd = msvcrt.open_osfhandle(handle, os.O_RDWR | os.O_BINARY)
        self.addCleanup(self.close, fd)
        self.assertEqual(self.getfl(fd) & 3, os.O_RDWR)
        self.assertEqual(self.claim(fd), errno.ENOTSUP)
        self.assertEqual(self.getfl(fd) & 3, os.O_RDWR)
