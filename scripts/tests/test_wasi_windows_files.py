"""Windows file handles, UTF-8 paths and capability primitives."""
from __future__ import annotations

import ctypes
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
DIRECTORY = 0x10000000
NOFOLLOW = 0x20000000


@unittest.skipUnless(os.name == "nt", "requires native Windows filesystem")
class WindowsFileTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import _ctypes
        cls.directory = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.directory.cleanup)
        directory = Path(cls.directory.name)
        (directory / "moonbit.h").write_text('#define MOONBIT_FFI_EXPORT __declspec(dllexport)\n')
        library = directory / "files.dll"
        names = ["open", "openat", "close", "path_within_base", "is_symlink_at", "readlinkat"]
        subprocess.run([
            "clang-cl", "/LD", "/MD", "/I" + str(directory),
            str(ROOT / "modules/wasmoon_jit/host_io/windows_io.c"),
            str(ROOT / "modules/wasmoon_jit/host_io/windows_fs.c"),
            "/link", "/OUT:" + str(library),
            *["/EXPORT:wasmoon_windows_" + name for name in names],
        ], check=True, cwd=directory)
        cls.library = ctypes.CDLL(str(library), use_errno=True)
        cls.addClassCleanup(_ctypes.FreeLibrary, cls.library._handle)
        cls.open = cls.library.wasmoon_windows_open
        cls.open.argtypes = [ctypes.c_char_p, ctypes.c_int, ctypes.c_int]
        cls.openat = cls.library.wasmoon_windows_openat
        cls.openat.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_int]
        cls.close = cls.library.wasmoon_windows_close
        cls.close.argtypes = [ctypes.c_int]
        cls.within = cls.library.wasmoon_windows_path_within_base
        cls.within.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
        cls.is_link = cls.library.wasmoon_windows_is_symlink_at
        cls.is_link.argtypes = [ctypes.c_int, ctypes.c_char_p]
        cls.readlink = cls.library.wasmoon_windows_readlinkat
        cls.readlink.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_void_p, ctypes.c_size_t]
        cls.readlink.restype = ctypes.c_int64

    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory()
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name) / "root"
        self.root.mkdir()
        self.fd = self.open(os.fsencode(self.root), DIRECTORY, 0)
        self.assertGreaterEqual(self.fd, 0)
        self.addCleanup(self.close, self.fd)

    def test_unicode_open_and_binary_contents(self):
        fd = self.openat(self.fd, "中文😀.txt".encode(), os.O_RDWR | os.O_CREAT | NOFOLLOW, 0o600)
        self.assertGreaterEqual(fd, 0)
        try:
            self.assertEqual(os.write(fd, b"a\r\nb\x1ac"), 6)
            os.lseek(fd, 0, os.SEEK_SET)
            self.assertEqual(os.read(fd, 20), b"a\r\nb\x1ac")
        finally:
            self.close(fd)

    def test_held_directory_survives_rename(self):
        (self.root / "file").write_bytes(b"original")
        renamed = self.root.with_name("renamed")
        self.root.rename(renamed)
        self.root.mkdir()
        (self.root / "file").write_bytes(b"replacement")
        fd = self.openat(self.fd, b"file", NOFOLLOW, 0)
        self.assertGreaterEqual(fd, 0)
        try:
            self.assertEqual(os.read(fd, 20), b"original")
        finally:
            self.close(fd)

    def test_relative_primitive_rejects_traversal_and_stream_names(self):
        for name in [b"..", b"../outside", b"sub/file", b"sub\\file", b"file:stream"]:
            self.assertEqual(self.openat(self.fd, name, os.O_CREAT | os.O_WRONLY, 0o600), -1)

    def test_directory_constraint_precedes_truncation(self):
        path = self.root / "file"
        path.write_bytes(b"keep")
        self.assertEqual(self.openat(self.fd, b"file", DIRECTORY | os.O_WRONLY | os.O_TRUNC, 0), -1)
        self.assertEqual(path.read_bytes(), b"keep")

    def test_symlink_cannot_be_truncated_through_no_follow(self):
        outside = self.root.parent / "outside"
        outside.write_bytes(b"keep")
        os.symlink("../outside", self.root / "link")
        self.assertEqual(self.is_link(self.fd, b"link"), 1)
        self.assertEqual(self.openat(self.fd, b"link", NOFOLLOW | os.O_WRONLY | os.O_TRUNC, 0), -1)
        self.assertEqual(outside.read_bytes(), b"keep")
        buffer = ctypes.create_string_buffer(256)
        length = self.readlink(self.fd, b"link", buffer, 256)
        self.assertEqual(buffer.raw[:length], b"../outside")
        self.assertEqual(self.within(os.fsencode(self.root), os.fsencode(self.root / "link")), 0)

    def test_nonexistent_target_checks_existing_parent(self):
        self.assertEqual(self.within(os.fsencode(self.root), os.fsencode(self.root / "new")), 1)
        self.assertEqual(self.within(os.fsencode(self.root), os.fsencode(self.root.parent / "outside")), 0)

    def test_containment_respects_case_sensitive_directories(self):
        parent = self.root / "sensitive"
        parent.mkdir()
        subprocess.run(["fsutil.exe", "file", "setCaseSensitiveInfo", str(parent), "enable"],
                       check=True, capture_output=True, text=True)
        base = parent / "base"
        outside = parent / "BASE"
        base.mkdir()
        outside.mkdir()
        self.assertEqual(self.within(os.fsencode(base), os.fsencode(outside / "new")), 0)
        self.assertEqual(self.within(os.fsencode(base), os.fsencode(base / "new")), 1)

    def test_normalized_path_accepts_case_insensitive_spelling(self):
        self.assertEqual(self.within(os.fsencode(self.root),
                                     os.fsencode(self.root.with_name("ROOT") / "new")), 1)
