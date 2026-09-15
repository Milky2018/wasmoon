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
        names = ["open", "openat", "close", "path_within_base", "is_symlink_at", "readlinkat", "linkat",
                 "pread", "pwrite", "write", "getfl", "setfl", "dup", "dup2", "symlinkat", "ftruncate", "renameat"]
        subprocess.run([
            os.environ.get("WASMOON_MSVC_CL", "clang-cl"), "/std:c11", "/D_CRT_SECURE_NO_WARNINGS", "/LD", "/MD", "/DWASMOON_SYMLINK_TESTING", "/I" + str(directory),
            str(ROOT / "modules/wasmoon_jit/host_io/windows_io.c"),
            str(ROOT / "modules/wasmoon_jit/host_io/windows_input.c"),
            str(ROOT / "modules/wasmoon_jit/host_io/windows_fs.c"),
            str(ROOT / "scripts/tests/native/windows_symlink.c"),
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
        cls.link = cls.library.wasmoon_windows_linkat
        cls.link.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p, ctypes.c_int]
        cls.pread = cls.library.wasmoon_windows_pread
        cls.pwrite = cls.library.wasmoon_windows_pwrite
        for function in [cls.pread, cls.pwrite]:
            function.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_int, ctypes.c_int64]
        cls.write = cls.library.wasmoon_windows_write
        cls.write.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_int]
        cls.getfl = cls.library.wasmoon_windows_getfl
        cls.getfl.argtypes = [ctypes.c_int]
        cls.setfl = cls.library.wasmoon_windows_setfl
        cls.setfl.argtypes = [ctypes.c_int, ctypes.c_int]
        cls.dup = cls.library.wasmoon_windows_dup
        cls.dup.argtypes = [ctypes.c_int]
        cls.dup2 = cls.library.wasmoon_windows_dup2
        cls.dup2.argtypes = [ctypes.c_int, ctypes.c_int]
        cls.symlink = cls.library.wasmoon_windows_symlinkat
        cls.symlink.argtypes = [ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p]
        cls.rename = cls.library.wasmoon_windows_renameat
        cls.rename.argtypes = [ctypes.c_int, ctypes.c_char_p, ctypes.c_int, ctypes.c_char_p]
        cls.truncate = cls.library.wasmoon_windows_ftruncate
        cls.truncate.argtypes = [ctypes.c_int, ctypes.c_int64]

    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory()
        self.addCleanup(self.scratch.cleanup)
        self.root = Path(self.scratch.name) / "root"
        self.root.mkdir()
        self.fd = self.open(os.fsencode(self.root), DIRECTORY, 0)
        self.assertGreaterEqual(self.fd, 0)
        self.addCleanup(self.close, self.fd)

    def test_unprivileged_symlink(self):
        mode = os.environ.get("WASMOON_TEST_DEVELOPER_MODE")
        if mode not in ("0", "1"):
            self.skipTest("requires explicit Developer Mode CI configuration")
        self.assertEqual(self.library.wasmoon_test_remove_symlink_privilege(), 1)
        try:
            target = self.root / "target"
            target.write_bytes(b"target")
            result = self.symlink(b"target", self.fd, b"link")
            if mode == "1":
                self.assertEqual(result, 0, os.strerror(ctypes.get_errno()))
                self.assertEqual((self.root / "link").read_bytes(), b"target")
                self.assertEqual(self.symlink(b"missing", self.fd, b"dangling"), 0)
                self.assertTrue((self.root / "dangling").is_symlink())
                self.assertEqual(self.symlink(b"target", self.fd, b"link"), -1)
            else:
                self.assertEqual(result, -1)
                self.assertEqual(ctypes.get_errno(), 1)  # EPERM
                self.assertFalse(os.path.lexists(self.root / "link"))
            # Success and failure must preserve the caller's restricted token.
            control = self.root / "control"
            try:
                os.symlink("target", control)
                self.assertEqual(mode, "1")
            except OSError as error:
                self.assertEqual(mode, "0")
                self.assertEqual(error.winerror, 1314)
        finally:
            self.assertEqual(self.library.wasmoon_test_restore_token(), 1)

    def test_unprivileged_symlink_locks_ancestors(self):
        if os.environ.get("WASMOON_TEST_DEVELOPER_MODE") != "1":
            self.skipTest("requires Developer Mode CI configuration")
        observations = []
        callback_type = ctypes.CFUNCTYPE(None)

        @callback_type
        def locked():
            # This callback runs at the mutation boundary, while all locks are held.
            for path in (self.root, self.root.parent):
                try:
                    path.rename(path.with_name(path.name + "-moved"))
                    observations.append("renamed")
                except OSError as error:
                    observations.append(error.winerror)

        register = self.library.wasmoon_test_symlink_hook
        register.argtypes = [ctypes.c_void_p]
        register(ctypes.cast(locked, ctypes.c_void_p))
        self.assertEqual(self.library.wasmoon_test_remove_symlink_privilege(), 1)
        try:
            self.assertEqual(self.symlink(b"missing", self.fd, b"link"), 0,
                             os.strerror(ctypes.get_errno()))
            self.assertEqual(observations, [32, 32])  # ERROR_SHARING_VIOLATION
        finally:
            register(None)
            self.assertEqual(self.library.wasmoon_test_restore_token(), 1)
        # Locks are operation-scoped; the ordinary descriptor still permits rename.
        renamed = self.root.with_name("renamed")
        self.root.rename(renamed)
        self.root.mkdir()
        self.assertEqual(self.library.wasmoon_test_remove_symlink_privilege(), 1)
        try:
            self.assertEqual(self.symlink(b"missing", self.fd, b"after-rename"), 0)
        finally:
            self.assertEqual(self.library.wasmoon_test_restore_token(), 1)
        self.assertTrue((renamed / "after-rename").is_symlink())
        self.assertFalse(os.path.lexists(self.root / "after-rename"))

    def test_unicode_open_and_binary_contents(self):
        fd = self.openat(self.fd, "中文😀.txt".encode(), os.O_RDWR | os.O_CREAT | NOFOLLOW, 0o600)
        self.assertGreaterEqual(fd, 0)
        try:
            self.assertEqual(os.write(fd, b"a\r\nb\x1ac"), 6)
            os.lseek(fd, 0, os.SEEK_SET)
            self.assertEqual(os.read(fd, 20), b"a\r\nb\x1ac")
        finally:
            self.close(fd)

    def test_positioned_io_keeps_shared_cursor_after_rename(self):
        path = self.root / "file"
        path.write_bytes(b"0123456789")
        fd = self.openat(self.fd, b"file", os.O_RDWR, 0)
        self.assertGreaterEqual(fd, 0)
        self.addCleanup(self.close, fd)
        os.lseek(fd, 5, os.SEEK_SET)
        path.rename(path.with_name("renamed"))
        path.write_bytes(b"replacement")
        buffer = ctypes.create_string_buffer(4)
        self.assertEqual(self.pread(fd, buffer, 3, 1), 3)
        self.assertEqual(buffer.raw[:3], b"123")
        self.assertEqual(self.pwrite(fd, b"\r\n\x1a", 3, 2), 3)
        self.assertEqual(os.lseek(fd, 0, os.SEEK_CUR), 5)
        self.assertEqual(self.pread(fd, buffer, 4, 100), 0)
        self.assertEqual(path.with_name("renamed").read_bytes(), b"01\r\n\x1a56789")
        self.assertEqual(path.read_bytes(), b"replacement")

    def test_positioned_write_does_not_upgrade_read_only_handle(self):
        path = self.root / "file"
        path.write_bytes(b"keep")
        fd = self.openat(self.fd, b"file", os.O_RDONLY, 0)
        self.assertGreaterEqual(fd, 0)
        self.addCleanup(self.close, fd)
        self.assertEqual(self.pwrite(fd, b"bad", 3, 0), -1)
        self.assertEqual(path.read_bytes(), b"keep")

    def test_truncate_preserves_cursor_and_rejects_negative_size(self):
        path = self.root / "file"
        path.write_bytes(b"0123456789")
        fd = self.openat(self.fd, b"file", os.O_RDWR, 0)
        self.assertGreaterEqual(fd, 0)
        self.addCleanup(self.close, fd)
        os.lseek(fd, 7, os.SEEK_SET)
        self.assertEqual(self.truncate(fd, -1), -1)
        self.assertEqual(path.read_bytes(), b"0123456789")
        self.assertEqual(self.truncate(fd, 3), 0)
        self.assertEqual(os.lseek(fd, 0, os.SEEK_CUR), 7)
        self.assertEqual(path.read_bytes(), b"012")
        self.assertEqual(self.truncate(1234567, 0), -1)

    def test_append_flags_are_shared_by_duplicates_and_can_be_cleared(self):
        path = self.root / "file"
        path.write_bytes(b"start")
        fd = self.openat(self.fd, b"file", os.O_RDWR, 0)
        self.assertGreaterEqual(fd, 0)
        duplicate = self.dup(fd)
        self.assertGreaterEqual(duplicate, 0)
        self.addCleanup(self.close, duplicate)
        try:
            self.assertEqual(self.setfl(duplicate, os.O_RDWR | os.O_APPEND), 0)
            self.assertTrue(self.getfl(fd) & os.O_APPEND)
            self.assertEqual(self.write(fd, b"\r\n\x1a", 3), 3)
            self.assertEqual(path.read_bytes(), b"start\r\n\x1a")
            self.assertEqual(self.setfl(fd, os.O_RDWR), 0)
            self.assertFalse(self.getfl(duplicate) & os.O_APPEND)
            os.lseek(duplicate, 0, os.SEEK_SET)
            self.assertEqual(self.write(duplicate, b"X", 1), 1)
        finally:
            self.close(fd)
        self.assertEqual(self.getfl(duplicate) & (os.O_WRONLY | os.O_RDWR), os.O_RDWR)
        self.assertEqual(path.read_bytes(), b"Xtart\r\n\x1a")

    def test_close_invalid_descriptor_returns_error_without_crt_abort(self):
        self.assertEqual(self.close(1234567), -1)

    def test_dup2_replaces_destination_flags_and_retains_source(self):
        first = self.openat(self.fd, b"first", os.O_RDWR | os.O_CREAT | os.O_APPEND, 0o600)
        second = self.openat(self.fd, b"second", os.O_RDWR | os.O_CREAT, 0o600)
        self.assertGreaterEqual(first, 0)
        self.assertGreaterEqual(second, 0)
        self.addCleanup(self.close, first)
        self.addCleanup(self.close, second)
        self.assertEqual(self.dup2(first, second), second)
        self.assertTrue(self.getfl(second) & os.O_APPEND)
        self.assertEqual(self.setfl(second, os.O_RDWR), 0)
        self.assertFalse(self.getfl(first) & os.O_APPEND)
        self.assertEqual(self.write(second, b"same", 4), 4)
        self.assertEqual((self.root / "first").read_bytes(), b"same")
        self.assertEqual((self.root / "second").read_bytes(), b"")

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

    def test_hard_link_uses_held_parent_and_does_not_replace(self):
        source = self.root / "source"
        source.write_bytes(b"shared")
        self.assertEqual(self.link(self.fd, b"source", self.fd, b"link", 0), 0)
        self.assertTrue(os.path.samefile(source, self.root / "link"))
        self.assertEqual(self.link(self.fd, b"source", self.fd, b"link", 0), -1)
        renamed = self.root.with_name("renamed")
        self.root.rename(renamed)
        self.assertEqual(self.link(self.fd, b"source", self.fd, b"after-rename", 0), 0)
        self.assertTrue(os.path.samefile(renamed / "source", renamed / "after-rename"))

    def test_hard_link_absolute_host_path(self):
        source = self.root / "source"
        source.write_bytes(b"shared")
        target = self.root / "target"
        self.assertEqual(self.link(0, os.fsencode(source), 0, os.fsencode(target), 0), 0)
        self.assertTrue(os.path.samefile(source, target))

    def test_absolute_rename_normalizes_guest_separators(self):
        source = self.root / "source"
        source.mkdir()
        target = self.root / "target"
        self.assertEqual(self.rename(0, (self.root.as_posix() + "/./source").encode(), 0, (self.root.as_posix() + "/./target").encode()), 0)
        self.assertFalse(source.exists())
        self.assertTrue(target.is_dir())

    def test_rename_in_workspace_after_missing_source_probe(self):
        parent = ROOT / "target"
        parent.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=parent) as directory:
            base = Path(directory) / "scratch"
            base.mkdir()
            (base / "source").mkdir()
            source = (base.as_posix() + "/./source").encode()
            target = (base.as_posix() + "/./target").encode()
            previous = Path.cwd()
            try:
                os.chdir(directory)
                self.assertEqual(self.rename(0, source, 0, target), 0)
                self.assertEqual(self.open(source, DIRECTORY | NOFOLLOW, 0), -1)
                opened = self.open(target, DIRECTORY | NOFOLLOW, 0)
                self.assertGreaterEqual(opened, 0)
                self.close(opened)
                self.assertTrue((base / "target").is_dir())
            finally:
                os.chdir(previous)

    def test_rename_replaces_empty_directory_and_preserves_nonempty_target(self):
        source = self.root / "source"
        target = self.root / "target"
        source.mkdir()
        target.mkdir()
        self.assertEqual(self.rename(self.fd, b"source", self.fd, b"target"), 0)
        self.assertFalse(source.exists())
        self.assertTrue(target.is_dir())
        source.mkdir()
        (target / "keep").write_bytes(b"retained")
        self.assertEqual(self.rename(self.fd, b"source", self.fd, b"target"), -1)
        self.assertTrue(source.is_dir())
        self.assertEqual((target / "keep").read_bytes(), b"retained")

    def test_rename_relative_target_uses_held_parent(self):
        (self.root / "source").write_bytes(b"retained")
        moved = self.root.with_name("moved")
        self.root.rename(moved)
        self.assertEqual(self.rename(self.fd, b"source", self.fd, b"target"), 0)
        self.assertFalse((moved / "source").exists())
        self.assertEqual((moved / "target").read_bytes(), b"retained")

    def test_rename_directory_over_file_matches_windows_contract(self):
        (self.root / "source").mkdir()
        (self.root / "target").write_bytes(b"replace")
        self.assertEqual(self.rename(self.fd, b"source", self.fd, b"target"), 0)
        self.assertTrue((self.root / "target").is_dir())
        (self.root / "source").write_bytes(b"retain")
        self.assertEqual(self.rename(self.fd, b"source", self.fd, b"target"), -1)
        self.assertTrue((self.root / "target").is_dir())
        self.assertEqual((self.root / "source").read_bytes(), b"retain")

    def test_absolute_symlink_normalizes_nested_target(self):
        nested = self.root / "nested"
        nested.mkdir()
        (nested / "file").write_bytes(b"target")
        link = self.root / "link"
        self.assertEqual(self.symlink(b"nested/file", 0, link.as_posix().encode()), 0)
        self.assertEqual(link.read_bytes(), b"target")
        self.assertEqual(self.within(os.fsencode(self.root), os.fsencode(link)), 1)

    def test_directory_write_open_and_trailing_link_fail(self):
        self.assertEqual(self.open(os.fsencode(self.root), DIRECTORY | os.O_RDWR, 0), -1)
        source = self.root / "source"
        source.write_bytes(b"keep")
        self.assertEqual(self.link(0, os.fsencode(source), 0, (self.root.as_posix() + "/link/").encode(), 0), -1)
        self.assertFalse((self.root / "link").exists())

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

    def test_create_symlink_through_held_parent_after_rename(self):
        nested = self.root / "inside" / "deep"
        nested.mkdir(parents=True)
        (nested / "file").write_bytes(b"target")
        renamed = self.root.with_name("renamed")
        self.root.rename(renamed)
        self.root.mkdir()
        self.assertEqual(self.symlink(b"inside/deep", self.fd, b"link"), 0,
                         os.strerror(ctypes.get_errno()))
        self.assertEqual((renamed / "link" / "file").read_bytes(), b"target")
        self.assertFalse((self.root / "link").exists())
        self.assertEqual(self.symlink(b"other", self.fd, b"link"), -1)
        buffer = ctypes.create_string_buffer(256)
        length = self.readlink(self.fd, b"link", buffer, 256)
        self.assertEqual(buffer.raw[:length], b"inside/deep")

    def test_absolute_symlink_is_readable_but_cannot_escape(self):
        target = self.root.parent / "outside"
        target.write_bytes(b"outside")
        self.assertEqual(self.symlink(os.fsencode(target), self.fd, b"link"), 0)
        buffer = ctypes.create_string_buffer(2048)
        length = self.readlink(self.fd, b"link", buffer, 2048)
        self.assertEqual(buffer.raw[:length], str(target).replace("\\", "/").encode())
        self.assertEqual(self.within(os.fsencode(self.root), os.fsencode(self.root / "link")), 0)

    def test_host_absolute_symlink_creation(self):
        target = self.root / "target"
        target.write_bytes(b"target")
        link = self.root / "link"
        self.assertEqual(self.symlink(b"target", 0, os.fsencode(link)), 0)
        self.assertEqual(link.read_bytes(), b"target")

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
