"""Exercise the production C readiness backend with real host descriptors."""
from __future__ import annotations

import ctypes
import fcntl
import os
from pathlib import Path
import resource
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class NativePollTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.directory.cleanup)
        directory = Path(cls.directory.name)
        # The backend uses no MoonBit runtime APIs, only the export annotation.
        (directory / "moonbit.h").write_text("#define MOONBIT_FFI_EXPORT\n")
        library = directory / "poll.so"
        subprocess.run(["cc", "-shared", "-fPIC", "-Wall", "-Wextra", "-Werror",
                        "-I", str(directory), str(ROOT / "modules/wasmoon/wasi/poll_native.c"),
                        "-o", str(library)], check=True)
        cls.library = ctypes.CDLL(str(library), use_errno=True)
        cls.poll = cls.library.wasmoon_wasi_poll
        pointer = ctypes.POINTER(ctypes.c_int)
        cls.poll.argtypes = [pointer, pointer, pointer, ctypes.c_int, ctypes.c_int]
        cls.poll.restype = ctypes.c_int

    def readiness(self, fds, events, timeout=0):
        array = ctypes.c_int * len(fds)
        output = array()
        count = self.poll(array(*fds), array(*events), output, len(fds), timeout)
        self.assertGreaterEqual(count, 0, os.strerror(ctypes.get_errno()))
        return count, list(output)

    def test_null_device_does_not_make_pending_pipe_ready(self):
        reader, writer = os.pipe()
        self.addCleanup(os.close, reader)
        self.addCleanup(os.close, writer)
        with open(os.devnull, 'rb') as null:
            self.assertEqual(self.readiness([null.fileno(), reader], [1, 1]), (1, [1, 0]))
            os.write(writer, b'x')
            self.assertEqual(self.readiness([null.fileno(), reader], [1, 1]), (2, [1, 1]))

    def test_high_descriptor_and_duplicate_subscriptions(self):
        if resource.getrlimit(resource.RLIMIT_NOFILE)[0] <= 2048:
            self.skipTest('host descriptor limit does not allow fd > FD_SETSIZE')
        with open(os.devnull, 'rb') as null:
            fd = fcntl.fcntl(null, fcntl.F_DUPFD, 2048)
        self.addCleanup(os.close, fd)
        self.assertEqual(self.readiness([fd, fd, 2147483647], [1, 1, 1]), (3, [1, 1, 32]))

    def test_pending_pipe_timeout_and_hangup(self):
        reader, writer = os.pipe()
        self.addCleanup(os.close, reader)
        try:
            self.assertEqual(self.readiness([reader], [1], 20), (0, [0]))
        finally:
            os.close(writer)
        count, flags = self.readiness([reader], [1])
        self.assertEqual(count, 1)
        self.assertTrue(flags[0] & 16)

    def test_regular_file_and_null_device(self):
        with tempfile.TemporaryFile() as file, open(os.devnull, 'rb') as null:
            self.assertEqual(self.readiness([file.fileno(), null.fileno(), -1], [4, 1, 1]),
                             (2, [4, 1, 0]))
