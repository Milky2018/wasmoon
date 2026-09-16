// MSVC uses the sibling MASM file. Clang handles guest ABI crossings itself.
#if !defined(__APPLE__) && !defined(_WIN32)
.section .note.GNU-stack,"",@progbits
#endif
