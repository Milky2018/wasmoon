
target/exception-rootcause/candidate-aligned:	file format mach-o arm64

Disassembly of section __TEXT,__text:

0000000100000778 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6lookup>:
100000778: a9bf7bfd    	stp	x29, x30, [sp, #-0x10]!
10000077c: 910003fd    	mov	x29, sp
100000780: f9400008    	ldr	x8, [x0]
100000784: b9400909    	ldr	w9, [x8, #0x8]
100000788: 7100053f    	cmp	w9, #0x1
10000078c: 540005ab    	b.lt	0x100000840 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6lookup+0xc8>
100000790: f940010b    	ldr	x11, [x8]
100000794: f940016a    	ldr	x10, [x11]
100000798: cb0a002c    	sub	x12, x1, x10
10000079c: 9341fd8a    	asr	x10, x12, #1
1000007a0: b7f8020a    	tbnz	x10, #0x3f, 0x1000007e0 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6lookup+0x68>
1000007a4: eb09015f    	cmp	x10, x9
1000007a8: 540001ca    	b.ge	0x1000007e0 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6lookup+0x68>
1000007ac: d341fd8c    	lsr	x12, x12, #1
1000007b0: 6b0c013f    	cmp	w9, w12
1000007b4: 540004c9    	b.ls	0x10000084c <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6lookup+0xd4>
1000007b8: d37c794c    	ubfiz	x12, x10, #4, #31
1000007bc: 8b0c016b    	add	x11, x11, x12
1000007c0: f940016c    	ldr	x12, [x11]
1000007c4: eb01019f    	cmp	x12, x1
1000007c8: 540000c1    	b.ne	0x1000007e0 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6lookup+0x68>
1000007cc: b940096b    	ldr	w11, [x11, #0x8]
1000007d0: 3400008b    	cbz	w11, 0x1000007e0 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6lookup+0x68>
1000007d4: 91000540    	add	x0, x10, #0x1
1000007d8: a8c17bfd    	ldp	x29, x30, [sp], #0x10
1000007dc: d65f03c0    	ret
1000007e0: 5280000a    	mov	w10, #0x0               ; =0
1000007e4: aa0903eb    	mov	x11, x9
1000007e8: 14000004    	b	0x1000007f8 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6lookup+0x80>
1000007ec: 1100058a    	add	w10, w12, #0x1
1000007f0: 6b0b015f    	cmp	w10, w11
1000007f4: 5400026a    	b.ge	0x100000840 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6lookup+0xc8>
1000007f8: 4b0a016c    	sub	w12, w11, w10
1000007fc: 0b4c7d8c    	add	w12, w12, w12, lsr #31
100000800: 0b8c054c    	add	w12, w10, w12, asr #1
100000804: 6b09019f    	cmp	w12, w9
100000808: 54000222    	b.hs	0x10000084c <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6lookup+0xd4>
10000080c: f940010d    	ldr	x13, [x8]
100000810: d37c7d8e    	ubfiz	x14, x12, #4, #32
100000814: f86e69ae    	ldr	x14, [x13, x14]
100000818: eb0101df    	cmp	x14, x1
10000081c: 54fffe8b    	b.lt	0x1000007ec <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6lookup+0x74>
100000820: aa0c03eb    	mov	x11, x12
100000824: 54fffe6c    	b.gt	0x1000007f0 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6lookup+0x78>
100000828: 8b0c11a8    	add	x8, x13, x12, lsl #4
10000082c: b9400908    	ldr	w8, [x8, #0x8]
100000830: 7100011f    	cmp	w8, #0x0
100000834: 9a8c07e0    	csinc	x0, xzr, x12, eq
100000838: a8c17bfd    	ldp	x29, x30, [sp], #0x10
10000083c: d65f03c0    	ret
100000840: d2800000    	mov	x0, #0x0                ; =0
100000844: a8c17bfd    	ldp	x29, x30, [sp], #0x10
100000848: d65f03c0    	ret
10000084c: 941fb5ed    	bl	0x1007ee000 <_moonbit_panic>

0000000100000850 <_ctx_execution_fallback>:
100000850: a9be4ff4    	stp	x20, x19, [sp, #-0x20]!
100000854: a9017bfd    	stp	x29, x30, [sp, #0x10]
100000858: 910043fd    	add	x29, sp, #0x10
10000085c: aa0003f3    	mov	x19, x0
100000860: 52800020    	mov	w0, #0x1                ; =1
100000864: 52800d01    	mov	w1, #0x68               ; =104
100000868: 941f2566    	bl	0x1007c9e00 <_wasmoon_native_calloc>
10000086c: b4000040    	cbz	x0, 0x100000874 <_ctx_execution_fallback+0x24>
100000870: f8128260    	stur	x0, [x19, #-0xd8]
100000874: a9417bfd    	ldp	x29, x30, [sp, #0x10]
100000878: a8c24ff4    	ldp	x20, x19, [sp], #0x20
10000087c: d65f03c0    	ret

0000000100000880 <_ctx_gc_restore_root_scopes_internal>:
100000880: b40005e0    	cbz	x0, 0x10000093c <_ctx_gc_restore_root_scopes_internal+0xbc>
100000884: a9bd57f6    	stp	x22, x21, [sp, #-0x30]!
100000888: a9014ff4    	stp	x20, x19, [sp, #0x10]
10000088c: a9027bfd    	stp	x29, x30, [sp, #0x20]
100000890: 910083fd    	add	x29, sp, #0x20
100000894: aa0003f3    	mov	x19, x0
100000898: f8528016    	ldur	x22, [x0, #-0xd8]
10000089c: b40004b6    	cbz	x22, 0x100000930 <_ctx_gc_restore_root_scopes_internal+0xb0>
1000008a0: aa0103f4    	mov	x20, x1
1000008a4: f94032c8    	ldr	x8, [x22, #0x60]
1000008a8: eb01011f    	cmp	x8, x1
1000008ac: 1a9f17e9    	cset	w9, eq
1000008b0: f100011f    	cmp	x8, #0x0
1000008b4: fa411104    	ccmp	x8, x1, #0x4, ne
1000008b8: 54000200    	b.eq	0x1000008f8 <_ctx_gc_restore_root_scopes_internal+0x78>
1000008bc: f8528269    	ldur	x9, [x19, #-0xd8]
1000008c0: b4000149    	cbz	x9, 0x1000008e8 <_ctx_gc_restore_root_scopes_internal+0x68>
1000008c4: f9403135    	ldr	x21, [x9, #0x60]
1000008c8: b4000115    	cbz	x21, 0x1000008e8 <_ctx_gc_restore_root_scopes_internal+0x68>
1000008cc: f94002a8    	ldr	x8, [x21]
1000008d0: f9003128    	str	x8, [x9, #0x60]
1000008d4: f94006a0    	ldr	x0, [x21, #0x8]
1000008d8: 941fba3c    	bl	0x1007ef1c8 <_write+0x1007ef1c8>
1000008dc: aa1503e0    	mov	x0, x21
1000008e0: 941fba3a    	bl	0x1007ef1c8 <_write+0x1007ef1c8>
1000008e4: f94032c8    	ldr	x8, [x22, #0x60]
1000008e8: eb14011f    	cmp	x8, x20
1000008ec: 1a9f17e9    	cset	w9, eq
1000008f0: b4000048    	cbz	x8, 0x1000008f8 <_ctx_gc_restore_root_scopes_internal+0x78>
1000008f4: 54fffe41    	b.ne	0x1000008bc <_ctx_gc_restore_root_scopes_internal+0x3c>
1000008f8: b40001d4    	cbz	x20, 0x100000930 <_ctx_gc_restore_root_scopes_internal+0xb0>
1000008fc: 370001a9    	tbnz	w9, #0x0, 0x100000930 <_ctx_gc_restore_root_scopes_internal+0xb0>
100000900: f8528274    	ldur	x20, [x19, #-0xd8]
100000904: b4000174    	cbz	x20, 0x100000930 <_ctx_gc_restore_root_scopes_internal+0xb0>
100000908: f9403293    	ldr	x19, [x20, #0x60]
10000090c: b4000133    	cbz	x19, 0x100000930 <_ctx_gc_restore_root_scopes_internal+0xb0>
100000910: f9400268    	ldr	x8, [x19]
100000914: f9003288    	str	x8, [x20, #0x60]
100000918: f9400660    	ldr	x0, [x19, #0x8]
10000091c: 941fba2b    	bl	0x1007ef1c8 <_write+0x1007ef1c8>
100000920: aa1303e0    	mov	x0, x19
100000924: 941fba29    	bl	0x1007ef1c8 <_write+0x1007ef1c8>
100000928: f9403293    	ldr	x19, [x20, #0x60]
10000092c: b5ffff33    	cbnz	x19, 0x100000910 <_ctx_gc_restore_root_scopes_internal+0x90>
100000930: a9427bfd    	ldp	x29, x30, [sp, #0x20]
100000934: a9414ff4    	ldp	x20, x19, [sp, #0x10]
100000938: a8c357f6    	ldp	x22, x21, [sp], #0x30
10000093c: d65f03c0    	ret

0000000100000940 <_exception_activation_context>:
100000940: a9be4ff4    	stp	x20, x19, [sp, #-0x20]!
100000944: a9017bfd    	stp	x29, x30, [sp, #0x10]
100000948: 910043fd    	add	x29, sp, #0x10
10000094c: aa0003f3    	mov	x19, x0
100000950: 9400038d    	bl	0x100001784 <_get_current_jit_context>
100000954: b40000b3    	cbz	x19, 0x100000968 <_exception_activation_context+0x28>
100000958: f85b0268    	ldur	x8, [x19, #-0x50]
10000095c: f100011f    	cmp	x8, #0x0
100000960: fa401804    	ccmp	x0, #0x0, #0x4, ne
100000964: 54000041    	b.ne	0x10000096c <_exception_activation_context+0x2c>
100000968: aa1303e0    	mov	x0, x19
10000096c: a9417bfd    	ldp	x29, x30, [sp, #0x10]
100000970: a8c24ff4    	ldp	x20, x19, [sp], #0x20
100000974: d65f03c0    	ret

0000000100000978 <_exception_arena_copy_marked>:
100000978: b40000a0    	cbz	x0, 0x10000098c <_exception_arena_copy_marked+0x14>
10000097c: f9400808    	ldr	x8, [x0, #0x10]
100000980: f9401502    	ldr	x2, [x8, #0x28]
100000984: f9400000    	ldr	x0, [x0]
100000988: d61f0040    	br	x2
10000098c: d65f03c0    	ret

0000000100000990 <_exception_arena_mark>:
100000990: b40000a0    	cbz	x0, 0x1000009a4 <_exception_arena_mark+0x14>
100000994: f9400808    	ldr	x8, [x0, #0x10]
100000998: f9400d02    	ldr	x2, [x8, #0x18]
10000099c: f9400000    	ldr	x0, [x0]
1000009a0: d61f0040    	br	x2
1000009a4: d65f03c0    	ret

00000001000009a8 <_exception_arena_marked_count>:
1000009a8: b40000a0    	cbz	x0, 0x1000009bc <_exception_arena_marked_count+0x14>
1000009ac: f9400808    	ldr	x8, [x0, #0x10]
1000009b0: f9401101    	ldr	x1, [x8, #0x20]
1000009b4: f9400000    	ldr	x0, [x0]
1000009b8: d61f0020    	br	x1
1000009bc: d65f03c0    	ret

00000001000009c0 <_exception_arena_release>:
1000009c0: b4000040    	cbz	x0, 0x1000009c8 <_exception_arena_release+0x8>
1000009c4: 141f7fdc    	b	0x1007e0934 <_moonbit_decref>
1000009c8: d65f03c0    	ret

00000001000009cc <_exception_arena_reset_marks>:
1000009cc: b40000a0    	cbz	x0, 0x1000009e0 <_exception_arena_reset_marks+0x14>
1000009d0: f9400808    	ldr	x8, [x0, #0x10]
1000009d4: f9401901    	ldr	x1, [x8, #0x30]
1000009d8: f9400000    	ldr	x0, [x0]
1000009dc: d61f0020    	br	x1
1000009e0: d65f03c0    	ret

00000001000009e4 <_exception_arena_sweep>:
1000009e4: b40000a0    	cbz	x0, 0x1000009f8 <_exception_arena_sweep+0x14>
1000009e8: f9400808    	ldr	x8, [x0, #0x10]
1000009ec: f9401d02    	ldr	x2, [x8, #0x38]
1000009f0: f9400000    	ldr	x0, [x0]
1000009f4: d61f0040    	br	x2
1000009f8: d65f03c0    	ret

00000001000009fc <_exception_capture_current>:
1000009fc: 140000b6    	b	0x100000cd4 <_exception_get_ref_impl>

0000000100000a00 <_exception_capture_payload>:
100000a00: d10143ff    	sub	sp, sp, #0x50
100000a04: a90257f6    	stp	x22, x21, [sp, #0x20]
100000a08: a9034ff4    	stp	x20, x19, [sp, #0x30]
100000a0c: a9047bfd    	stp	x29, x30, [sp, #0x40]
100000a10: 910103fd    	add	x29, sp, #0x40
100000a14: aa0303f3    	mov	x19, x3
100000a18: aa0203f5    	mov	x21, x2
100000a1c: aa0103f4    	mov	x20, x1
100000a20: aa0003f6    	mov	x22, x0
100000a24: 37f80101    	tbnz	w1, #0x1f, 0x100000a44 <_exception_capture_payload+0x44>
100000a28: b85f82c8    	ldur	w8, [x22, #-0x8]
100000a2c: 6b08029f    	cmp	w20, w8
100000a30: 5400006a    	b.ge	0x100000a3c <_exception_capture_payload+0x3c>
100000a34: f85c02c8    	ldur	x8, [x22, #-0x40]
100000a38: b8745914    	ldr	w20, [x8, w20, uxtw #2]
100000a3c: 94000352    	bl	0x100001784 <_get_current_jit_context>
100000a40: 14000003    	b	0x100000a4c <_exception_capture_payload+0x4c>
100000a44: 94000350    	bl	0x100001784 <_get_current_jit_context>
100000a48: b40000b6    	cbz	x22, 0x100000a5c <_exception_capture_payload+0x5c>
100000a4c: f85b02c8    	ldur	x8, [x22, #-0x50]
100000a50: f100001f    	cmp	x0, #0x0
100000a54: fa401904    	ccmp	x8, #0x0, #0x4, ne
100000a58: 9a961016    	csel	x22, x0, x22, ne
100000a5c: f85602c8    	ldur	x8, [x22, #-0xa0]
100000a60: b4000108    	cbz	x8, 0x100000a80 <_exception_capture_payload+0x80>
100000a64: f85202c8    	ldur	x8, [x22, #-0xe0]
100000a68: b40001c8    	cbz	x8, 0x100000aa0 <_exception_capture_payload+0xa0>
100000a6c: 39404508    	ldrb	w8, [x8, #0x11]
100000a70: f103fd1f    	cmp	x8, #0xff
100000a74: 54000181    	b.ne	0x100000aa4 <_exception_capture_payload+0xa4>
100000a78: d2800009    	mov	x9, #0x0                ; =0
100000a7c: 1400000b    	b	0x100000aa8 <_exception_capture_payload+0xa8>
100000a80: f85682c8    	ldur	x8, [x22, #-0x98]
100000a84: b4ffff08    	cbz	x8, 0x100000a64 <_exception_capture_payload+0x64>
100000a88: d63f0100    	blr	x8
100000a8c: b4fffec0    	cbz	x0, 0x100000a64 <_exception_capture_payload+0x64>
100000a90: f9400808    	ldr	x8, [x0, #0x10]
100000a94: b4000428    	cbz	x8, 0x100000b18 <_exception_capture_payload+0x118>
100000a98: f81602c0    	stur	x0, [x22, #-0xa0]
100000a9c: 17fffff2    	b	0x100000a64 <_exception_capture_payload+0x64>
100000aa0: 52800f08    	mov	w8, #0x78               ; =120
100000aa4: f8686ac9    	ldr	x9, [x22, x8]
100000aa8: 92800100    	mov	x0, #-0x9               ; =-9
100000aac: 37f803b3    	tbnz	w19, #0x1f, 0x100000b20 <_exception_capture_payload+0x120>
100000ab0: f85602c8    	ldur	x8, [x22, #-0xa0]
100000ab4: b4000368    	cbz	x8, 0x100000b20 <_exception_capture_payload+0x120>
100000ab8: b5000055    	cbnz	x21, 0x100000ac0 <_exception_capture_payload+0xc0>
100000abc: 35000333    	cbnz	w19, 0x100000b20 <_exception_capture_payload+0x120>
100000ac0: f90003e8    	str	x8, [sp]
100000ac4: b4000089    	cbz	x9, 0x100000ad4 <_exception_capture_payload+0xd4>
100000ac8: f940012a    	ldr	x10, [x9]
100000acc: f100015f    	cmp	x10, #0x0
100000ad0: 9a8903e9    	csel	x9, xzr, x9, eq
100000ad4: f90007e9    	str	x9, [sp, #0x8]
100000ad8: 29024ff4    	stp	w20, w19, [sp, #0x10]
100000adc: f9000ff5    	str	x21, [sp, #0x18]
100000ae0: f9400909    	ldr	x9, [x8, #0x10]
100000ae4: f9400129    	ldr	x9, [x9]
100000ae8: f9400100    	ldr	x0, [x8]
100000aec: 910003e1    	mov	x1, sp
100000af0: aa1403e2    	mov	x2, x20
100000af4: aa1303e3    	mov	x3, x19
100000af8: d63f0120    	blr	x9
100000afc: f100001f    	cmp	x0, #0x0
100000b00: 5400010d    	b.le	0x100000b20 <_exception_capture_payload+0x120>
100000b04: a9447bfd    	ldp	x29, x30, [sp, #0x40]
100000b08: a9434ff4    	ldp	x20, x19, [sp, #0x30]
100000b0c: a94257f6    	ldp	x22, x21, [sp, #0x20]
100000b10: 910143ff    	add	sp, sp, #0x50
100000b14: d65f03c0    	ret
100000b18: 941f7f87    	bl	0x1007e0934 <_moonbit_decref>
100000b1c: 17ffffd2    	b	0x100000a64 <_exception_capture_payload+0x64>
100000b20: 4b0003f3    	neg	w19, w0
100000b24: 94000323    	bl	0x1000017b0 <_jit_current_trap_activation>
100000b28: b900d413    	str	w19, [x0, #0xd4]
100000b2c: 94000321    	bl	0x1000017b0 <_jit_current_trap_activation>
100000b30: 52800021    	mov	w1, #0x1                ; =1
100000b34: 941fbb16    	bl	0x1007ef78c <_write+0x1007ef78c>

0000000100000b38 <_exception_copy_activation_roots>:
100000b38: f9400828    	ldr	x8, [x1, #0x10]
100000b3c: b40000a8    	cbz	x8, 0x100000b50 <_exception_copy_activation_roots+0x18>
100000b40: b4000042    	cbz	x2, 0x100000b48 <_exception_copy_activation_roots+0x10>
100000b44: f9000048    	str	x8, [x2]
100000b48: 52800020    	mov	w0, #0x1                ; =1
100000b4c: d65f03c0    	ret
100000b50: a9be4ff4    	stp	x20, x19, [sp, #-0x20]!
100000b54: a9017bfd    	stp	x29, x30, [sp, #0x10]
100000b58: 910043fd    	add	x29, sp, #0x10
100000b5c: aa0203f3    	mov	x19, x2
100000b60: f8560009    	ldur	x9, [x0, #-0xa0]
100000b64: b4000149    	cbz	x9, 0x100000b8c <_exception_copy_activation_roots+0x54>
100000b68: b9401828    	ldr	w8, [x1, #0x18]
100000b6c: f940092a    	ldr	x10, [x9, #0x10]
100000b70: f940094a    	ldr	x10, [x10, #0x10]
100000b74: f9400120    	ldr	x0, [x9]
100000b78: aa0103f4    	mov	x20, x1
100000b7c: aa0803e1    	mov	x1, x8
100000b80: d63f0140    	blr	x10
100000b84: aa1403e1    	mov	x1, x20
100000b88: 14000002    	b	0x100000b90 <_exception_copy_activation_roots+0x58>
100000b8c: d2800000    	mov	x0, #0x0                ; =0
100000b90: b9402829    	ldr	w9, [x1, #0x28]
100000b94: 7100053f    	cmp	w9, #0x1
100000b98: 540002cb    	b.lt	0x100000bf0 <_exception_copy_activation_roots+0xb8>
100000b9c: d280000a    	mov	x10, #0x0               ; =0
100000ba0: 52800008    	mov	w8, #0x0                ; =0
100000ba4: aa1303eb    	mov	x11, x19
100000ba8: 14000005    	b	0x100000bbc <_exception_copy_activation_roots+0x84>
100000bac: 11000508    	add	w8, w8, #0x1
100000bb0: 9100054a    	add	x10, x10, #0x1
100000bb4: eb29c15f    	cmp	x10, w9, sxtw
100000bb8: 540001ea    	b.ge	0x100000bf4 <_exception_copy_activation_roots+0xbc>
100000bbc: f940102c    	ldr	x12, [x1, #0x20]
100000bc0: b4ffff8c    	cbz	x12, 0x100000bb0 <_exception_copy_activation_roots+0x78>
100000bc4: b40000c0    	cbz	x0, 0x100000bdc <_exception_copy_activation_roots+0xa4>
100000bc8: b89fc00d    	ldursw	x13, [x0, #-0x4]
100000bcc: eb0d015f    	cmp	x10, x13
100000bd0: 54ffff0a    	b.ge	0x100000bb0 <_exception_copy_activation_roots+0x78>
100000bd4: b86a780d    	ldr	w13, [x0, x10, lsl #2]
100000bd8: 34fffecd    	cbz	w13, 0x100000bb0 <_exception_copy_activation_roots+0x78>
100000bdc: b4fffe8b    	cbz	x11, 0x100000bac <_exception_copy_activation_roots+0x74>
100000be0: f86a7989    	ldr	x9, [x12, x10, lsl #3]
100000be4: f828d969    	str	x9, [x11, w8, sxtw #3]
100000be8: b9402829    	ldr	w9, [x1, #0x28]
100000bec: 17fffff0    	b	0x100000bac <_exception_copy_activation_roots+0x74>
100000bf0: 52800008    	mov	w8, #0x0                ; =0
100000bf4: a9417bfd    	ldp	x29, x30, [sp, #0x10]
100000bf8: a8c24ff4    	ldp	x20, x19, [sp], #0x20
100000bfc: aa0803e0    	mov	x0, x8
100000c00: d65f03c0    	ret

0000000100000c04 <_exception_delegate_impl>:
100000c04: a9bc5ff8    	stp	x24, x23, [sp, #-0x40]!
100000c08: a90157f6    	stp	x22, x21, [sp, #0x10]
100000c0c: a9024ff4    	stp	x20, x19, [sp, #0x20]
100000c10: a9037bfd    	stp	x29, x30, [sp, #0x30]
100000c14: 9100c3fd    	add	x29, sp, #0x30
100000c18: aa0103f4    	mov	x20, x1
100000c1c: aa0003f5    	mov	x21, x0
100000c20: 940002d9    	bl	0x100001784 <_get_current_jit_context>
100000c24: b40000d5    	cbz	x21, 0x100000c3c <_exception_delegate_impl+0x38>
100000c28: aa0003f3    	mov	x19, x0
100000c2c: f85b02a8    	ldur	x8, [x21, #-0x50]
100000c30: f100011f    	cmp	x8, #0x0
100000c34: fa401804    	ccmp	x0, #0x0, #0x4, ne
100000c38: 54000041    	b.ne	0x100000c40 <_exception_delegate_impl+0x3c>
100000c3c: aa1503f3    	mov	x19, x21
100000c40: f8528276    	ldur	x22, [x19, #-0xd8]
100000c44: b5000096    	cbnz	x22, 0x100000c54 <_exception_delegate_impl+0x50>
100000c48: aa1303e0    	mov	x0, x19
100000c4c: 97ffff01    	bl	0x100000850 <_ctx_execution_fallback>
100000c50: aa0003f6    	mov	x22, x0
100000c54: f94002d5    	ldr	x21, [x22]
100000c58: f10002bf    	cmp	x21, #0x0
100000c5c: 1a9f07e8    	cset	w8, ne
100000c60: 7100069f    	cmp	w20, #0x1
100000c64: 540001ab    	b.lt	0x100000c98 <_exception_delegate_impl+0x94>
100000c68: b4000195    	cbz	x21, 0x100000c98 <_exception_delegate_impl+0x94>
100000c6c: 52800037    	mov	w23, #0x1               ; =1
100000c70: aa1503e0    	mov	x0, x21
100000c74: f94066b5    	ldr	x21, [x21, #0xc8]
100000c78: f90002d5    	str	x21, [x22]
100000c7c: 941fb953    	bl	0x1007ef1c8 <_write+0x1007ef1c8>
100000c80: f10002bf    	cmp	x21, #0x0
100000c84: 1a9f07e8    	cset	w8, ne
100000c88: 6b1402ff    	cmp	w23, w20
100000c8c: 5400006a    	b.ge	0x100000c98 <_exception_delegate_impl+0x94>
100000c90: 110006f7    	add	w23, w23, #0x1
100000c94: b5fffef5    	cbnz	x21, 0x100000c70 <_exception_delegate_impl+0x6c>
100000c98: 360000e8    	tbz	w8, #0x0, 0x100000cb4 <_exception_delegate_impl+0xb0>
100000c9c: f9406ea1    	ldr	x1, [x21, #0xd8]
100000ca0: aa1303e0    	mov	x0, x19
100000ca4: 97fffef7    	bl	0x100000880 <_ctx_gc_restore_root_scopes_internal>
100000ca8: b940d2a1    	ldr	w1, [x21, #0xd0]
100000cac: aa1503e0    	mov	x0, x21
100000cb0: 941fbab7    	bl	0x1007ef78c <_write+0x1007ef78c>
100000cb4: 940002bf    	bl	0x1000017b0 <_jit_current_trap_activation>
100000cb8: 52800188    	mov	w8, #0xc                ; =12
100000cbc: b900d408    	str	w8, [x0, #0xd4]
100000cc0: aa1303e0    	mov	x0, x19
100000cc4: 941f1fb8    	bl	0x1007c8ba4 <_ctx_gc_clear_root_scopes_internal>
100000cc8: 940002ba    	bl	0x1000017b0 <_jit_current_trap_activation>
100000ccc: 52800021    	mov	w1, #0x1                ; =1
100000cd0: 941fbaaf    	bl	0x1007ef78c <_write+0x1007ef78c>

0000000100000cd4 <_exception_get_ref_impl>:
100000cd4: d10103ff    	sub	sp, sp, #0x40
100000cd8: a9024ff4    	stp	x20, x19, [sp, #0x20]
100000cdc: a9037bfd    	stp	x29, x30, [sp, #0x30]
100000ce0: 9100c3fd    	add	x29, sp, #0x30
100000ce4: aa0003f3    	mov	x19, x0
100000ce8: 940002a7    	bl	0x100001784 <_get_current_jit_context>
100000cec: b4000173    	cbz	x19, 0x100000d18 <_exception_get_ref_impl+0x44>
100000cf0: aa0003f4    	mov	x20, x0
100000cf4: f85b0268    	ldur	x8, [x19, #-0x50]
100000cf8: f100011f    	cmp	x8, #0x0
100000cfc: fa401804    	ccmp	x0, #0x0, #0x4, ne
100000d00: 540000c0    	b.eq	0x100000d18 <_exception_get_ref_impl+0x44>
100000d04: f8528293    	ldur	x19, [x20, #-0xd8]
100000d08: b40000f3    	cbz	x19, 0x100000d24 <_exception_get_ref_impl+0x50>
100000d0c: f9400a60    	ldr	x0, [x19, #0x10]
100000d10: b50006c0    	cbnz	x0, 0x100000de8 <_exception_get_ref_impl+0x114>
100000d14: 14000009    	b	0x100000d38 <_exception_get_ref_impl+0x64>
100000d18: aa1303f4    	mov	x20, x19
100000d1c: f8528293    	ldur	x19, [x20, #-0xd8]
100000d20: b5ffff73    	cbnz	x19, 0x100000d0c <_exception_get_ref_impl+0x38>
100000d24: aa1403e0    	mov	x0, x20
100000d28: 97fffeca    	bl	0x100000850 <_ctx_execution_fallback>
100000d2c: aa0003f3    	mov	x19, x0
100000d30: f9400a60    	ldr	x0, [x19, #0x10]
100000d34: b50005a0    	cbnz	x0, 0x100000de8 <_exception_get_ref_impl+0x114>
100000d38: f8560288    	ldur	x8, [x20, #-0xa0]
100000d3c: b4000128    	cbz	x8, 0x100000d60 <_exception_get_ref_impl+0x8c>
100000d40: f8560288    	ldur	x8, [x20, #-0xa0]
100000d44: f8520289    	ldur	x9, [x20, #-0xe0]
100000d48: b40001c9    	cbz	x9, 0x100000d80 <_exception_get_ref_impl+0xac>
100000d4c: 39404529    	ldrb	w9, [x9, #0x11]
100000d50: f103fd3f    	cmp	x9, #0xff
100000d54: 54000181    	b.ne	0x100000d84 <_exception_get_ref_impl+0xb0>
100000d58: d2800009    	mov	x9, #0x0                ; =0
100000d5c: 1400000b    	b	0x100000d88 <_exception_get_ref_impl+0xb4>
100000d60: f8568288    	ldur	x8, [x20, #-0x98]
100000d64: b4fffee8    	cbz	x8, 0x100000d40 <_exception_get_ref_impl+0x6c>
100000d68: d63f0100    	blr	x8
100000d6c: b4fffea0    	cbz	x0, 0x100000d40 <_exception_get_ref_impl+0x6c>
100000d70: f9400808    	ldr	x8, [x0, #0x10]
100000d74: b4000428    	cbz	x8, 0x100000df8 <_exception_get_ref_impl+0x124>
100000d78: f8160280    	stur	x0, [x20, #-0xa0]
100000d7c: 17fffff1    	b	0x100000d40 <_exception_get_ref_impl+0x6c>
100000d80: 52800f09    	mov	w9, #0x78               ; =120
100000d84: f8696a89    	ldr	x9, [x20, x9]
100000d88: 92800100    	mov	x0, #-0x9               ; =-9
100000d8c: b40003a8    	cbz	x8, 0x100000e00 <_exception_get_ref_impl+0x12c>
100000d90: b9402a63    	ldr	w3, [x19, #0x28]
100000d94: 37f80363    	tbnz	w3, #0x1f, 0x100000e00 <_exception_get_ref_impl+0x12c>
100000d98: b9401a62    	ldr	w2, [x19, #0x18]
100000d9c: f940126a    	ldr	x10, [x19, #0x20]
100000da0: b500004a    	cbnz	x10, 0x100000da8 <_exception_get_ref_impl+0xd4>
100000da4: 350002e3    	cbnz	w3, 0x100000e00 <_exception_get_ref_impl+0x12c>
100000da8: f90003e8    	str	x8, [sp]
100000dac: b4000089    	cbz	x9, 0x100000dbc <_exception_get_ref_impl+0xe8>
100000db0: f940012b    	ldr	x11, [x9]
100000db4: f100017f    	cmp	x11, #0x0
100000db8: 9a8903e9    	csel	x9, xzr, x9, eq
100000dbc: f90007e9    	str	x9, [sp, #0x8]
100000dc0: 29020fe2    	stp	w2, w3, [sp, #0x10]
100000dc4: f9000fea    	str	x10, [sp, #0x18]
100000dc8: f9400909    	ldr	x9, [x8, #0x10]
100000dcc: f9400129    	ldr	x9, [x9]
100000dd0: f9400100    	ldr	x0, [x8]
100000dd4: 910003e1    	mov	x1, sp
100000dd8: d63f0120    	blr	x9
100000ddc: f100001f    	cmp	x0, #0x0
100000de0: 5400010d    	b.le	0x100000e00 <_exception_get_ref_impl+0x12c>
100000de4: f9000a60    	str	x0, [x19, #0x10]
100000de8: a9437bfd    	ldp	x29, x30, [sp, #0x30]
100000dec: a9424ff4    	ldp	x20, x19, [sp, #0x20]
100000df0: 910103ff    	add	sp, sp, #0x40
100000df4: d65f03c0    	ret
100000df8: 941f7ecf    	bl	0x1007e0934 <_moonbit_decref>
100000dfc: 17ffffd1    	b	0x100000d40 <_exception_get_ref_impl+0x6c>
100000e00: 4b0003f3    	neg	w19, w0
100000e04: 9400026b    	bl	0x1000017b0 <_jit_current_trap_activation>
100000e08: b900d413    	str	w19, [x0, #0xd4]
100000e0c: 94000269    	bl	0x1000017b0 <_jit_current_trap_activation>
100000e10: 52800021    	mov	w1, #0x1                ; =1
100000e14: 941fba5e    	bl	0x1007ef78c <_write+0x1007ef78c>

0000000100000e18 <_exception_get_spilled_local_impl>:
100000e18: a9be4ff4    	stp	x20, x19, [sp, #-0x20]!
100000e1c: a9017bfd    	stp	x29, x30, [sp, #0x10]
100000e20: 910043fd    	add	x29, sp, #0x10
100000e24: aa0103f3    	mov	x19, x1
100000e28: aa0003f4    	mov	x20, x0
100000e2c: 94000256    	bl	0x100001784 <_get_current_jit_context>
100000e30: b40000b4    	cbz	x20, 0x100000e44 <_exception_get_spilled_local_impl+0x2c>
100000e34: f85b0288    	ldur	x8, [x20, #-0x50]
100000e38: f100011f    	cmp	x8, #0x0
100000e3c: fa401804    	ccmp	x0, #0x0, #0x4, ne
100000e40: 54000101    	b.ne	0x100000e60 <_exception_get_spilled_local_impl+0x48>
100000e44: aa1403e0    	mov	x0, x20
100000e48: f8528008    	ldur	x8, [x0, #-0xd8]
100000e4c: b50000e8    	cbnz	x8, 0x100000e68 <_exception_get_spilled_local_impl+0x50>
100000e50: 97fffe80    	bl	0x100000850 <_ctx_execution_fallback>
100000e54: aa0003e8    	mov	x8, x0
100000e58: 36f800b3    	tbz	w19, #0x1f, 0x100000e6c <_exception_get_spilled_local_impl+0x54>
100000e5c: 1400000b    	b	0x100000e88 <_exception_get_spilled_local_impl+0x70>
100000e60: f8528008    	ldur	x8, [x0, #-0xd8]
100000e64: b4ffff68    	cbz	x8, 0x100000e50 <_exception_get_spilled_local_impl+0x38>
100000e68: 37f80113    	tbnz	w19, #0x1f, 0x100000e88 <_exception_get_spilled_local_impl+0x70>
100000e6c: b9403909    	ldr	w9, [x8, #0x38]
100000e70: 6b09027f    	cmp	w19, w9
100000e74: 540000aa    	b.ge	0x100000e88 <_exception_get_spilled_local_impl+0x70>
100000e78: f9401908    	ldr	x8, [x8, #0x30]
100000e7c: b4000068    	cbz	x8, 0x100000e88 <_exception_get_spilled_local_impl+0x70>
100000e80: f8735900    	ldr	x0, [x8, w19, uxtw #3]
100000e84: 14000002    	b	0x100000e8c <_exception_get_spilled_local_impl+0x74>
100000e88: d2800000    	mov	x0, #0x0                ; =0
100000e8c: a9417bfd    	ldp	x29, x30, [sp, #0x10]
100000e90: a8c24ff4    	ldp	x20, x19, [sp], #0x20
100000e94: d65f03c0    	ret

0000000100000e98 <_exception_get_tag_impl>:
100000e98: a9be4ff4    	stp	x20, x19, [sp, #-0x20]!
100000e9c: a9017bfd    	stp	x29, x30, [sp, #0x10]
100000ea0: 910043fd    	add	x29, sp, #0x10
100000ea4: aa0003f3    	mov	x19, x0
100000ea8: 94000237    	bl	0x100001784 <_get_current_jit_context>
100000eac: b40000b3    	cbz	x19, 0x100000ec0 <_exception_get_tag_impl+0x28>
100000eb0: f85b0268    	ldur	x8, [x19, #-0x50]
100000eb4: f100011f    	cmp	x8, #0x0
100000eb8: fa401804    	ccmp	x0, #0x0, #0x4, ne
100000ebc: 54000041    	b.ne	0x100000ec4 <_exception_get_tag_impl+0x2c>
100000ec0: aa1303e0    	mov	x0, x19
100000ec4: f8528008    	ldur	x8, [x0, #-0xd8]
100000ec8: b5000068    	cbnz	x8, 0x100000ed4 <_exception_get_tag_impl+0x3c>
100000ecc: 97fffe61    	bl	0x100000850 <_ctx_execution_fallback>
100000ed0: aa0003e8    	mov	x8, x0
100000ed4: b9401900    	ldr	w0, [x8, #0x18]
100000ed8: f85b0268    	ldur	x8, [x19, #-0x50]
100000edc: b40001e8    	cbz	x8, 0x100000f18 <_exception_get_tag_impl+0x80>
100000ee0: b85f8268    	ldur	w8, [x19, #-0x8]
100000ee4: 7100051f    	cmp	w8, #0x1
100000ee8: 5400012b    	b.lt	0x100000f0c <_exception_get_tag_impl+0x74>
100000eec: d2800009    	mov	x9, #0x0                ; =0
100000ef0: f85c026a    	ldur	x10, [x19, #-0x40]
100000ef4: b869794b    	ldr	w11, [x10, x9, lsl #2]
100000ef8: 6b00017f    	cmp	w11, w0
100000efc: 540000c0    	b.eq	0x100000f14 <_exception_get_tag_impl+0x7c>
100000f00: 91000529    	add	x9, x9, #0x1
100000f04: 6b09011f    	cmp	w8, w9
100000f08: 54ffff61    	b.ne	0x100000ef4 <_exception_get_tag_impl+0x5c>
100000f0c: 12800000    	mov	w0, #-0x1               ; =-1
100000f10: 14000002    	b	0x100000f18 <_exception_get_tag_impl+0x80>
100000f14: aa0903e0    	mov	x0, x9
100000f18: a9417bfd    	ldp	x29, x30, [sp, #0x10]
100000f1c: a8c24ff4    	ldp	x20, x19, [sp], #0x20
100000f20: d65f03c0    	ret

0000000100000f24 <_exception_get_value_count_impl>:
100000f24: a9be4ff4    	stp	x20, x19, [sp, #-0x20]!
100000f28: a9017bfd    	stp	x29, x30, [sp, #0x10]
100000f2c: 910043fd    	add	x29, sp, #0x10
100000f30: aa0003f3    	mov	x19, x0
100000f34: 94000214    	bl	0x100001784 <_get_current_jit_context>
100000f38: b40000b3    	cbz	x19, 0x100000f4c <_exception_get_value_count_impl+0x28>
100000f3c: f85b0268    	ldur	x8, [x19, #-0x50]
100000f40: f100011f    	cmp	x8, #0x0
100000f44: fa401804    	ccmp	x0, #0x0, #0x4, ne
100000f48: 54000041    	b.ne	0x100000f50 <_exception_get_value_count_impl+0x2c>
100000f4c: aa1303e0    	mov	x0, x19
100000f50: f8528008    	ldur	x8, [x0, #-0xd8]
100000f54: b5000068    	cbnz	x8, 0x100000f60 <_exception_get_value_count_impl+0x3c>
100000f58: 97fffe3e    	bl	0x100000850 <_ctx_execution_fallback>
100000f5c: aa0003e8    	mov	x8, x0
100000f60: b9402900    	ldr	w0, [x8, #0x28]
100000f64: a9417bfd    	ldp	x29, x30, [sp, #0x10]
100000f68: a8c24ff4    	ldp	x20, x19, [sp], #0x20
100000f6c: d65f03c0    	ret

0000000100000f70 <_exception_get_value_impl>:
100000f70: a9be4ff4    	stp	x20, x19, [sp, #-0x20]!
100000f74: a9017bfd    	stp	x29, x30, [sp, #0x10]
100000f78: 910043fd    	add	x29, sp, #0x10
100000f7c: aa0103f3    	mov	x19, x1
100000f80: aa0003f4    	mov	x20, x0
100000f84: 94000200    	bl	0x100001784 <_get_current_jit_context>
100000f88: b40000b4    	cbz	x20, 0x100000f9c <_exception_get_value_impl+0x2c>
100000f8c: f85b0288    	ldur	x8, [x20, #-0x50]
100000f90: f100011f    	cmp	x8, #0x0
100000f94: fa401804    	ccmp	x0, #0x0, #0x4, ne
100000f98: 54000101    	b.ne	0x100000fb8 <_exception_get_value_impl+0x48>
100000f9c: aa1403e0    	mov	x0, x20
100000fa0: f8528008    	ldur	x8, [x0, #-0xd8]
100000fa4: b50000e8    	cbnz	x8, 0x100000fc0 <_exception_get_value_impl+0x50>
100000fa8: 97fffe2a    	bl	0x100000850 <_ctx_execution_fallback>
100000fac: aa0003e8    	mov	x8, x0
100000fb0: 36f800b3    	tbz	w19, #0x1f, 0x100000fc4 <_exception_get_value_impl+0x54>
100000fb4: 1400000b    	b	0x100000fe0 <_exception_get_value_impl+0x70>
100000fb8: f8528008    	ldur	x8, [x0, #-0xd8]
100000fbc: b4ffff68    	cbz	x8, 0x100000fa8 <_exception_get_value_impl+0x38>
100000fc0: 37f80113    	tbnz	w19, #0x1f, 0x100000fe0 <_exception_get_value_impl+0x70>
100000fc4: b9402909    	ldr	w9, [x8, #0x28]
100000fc8: 6b09027f    	cmp	w19, w9
100000fcc: 540000aa    	b.ge	0x100000fe0 <_exception_get_value_impl+0x70>
100000fd0: f9401108    	ldr	x8, [x8, #0x20]
100000fd4: b4000068    	cbz	x8, 0x100000fe0 <_exception_get_value_impl+0x70>
100000fd8: f8735900    	ldr	x0, [x8, w19, uxtw #3]
100000fdc: 14000002    	b	0x100000fe4 <_exception_get_value_impl+0x74>
100000fe0: d2800000    	mov	x0, #0x0                ; =0
100000fe4: a9417bfd    	ldp	x29, x30, [sp, #0x10]
100000fe8: a8c24ff4    	ldp	x20, x19, [sp], #0x20
100000fec: d65f03c0    	ret

0000000100000ff0 <_exception_has_pending_hostcall>:
100000ff0: a9be4ff4    	stp	x20, x19, [sp, #-0x20]!
100000ff4: a9017bfd    	stp	x29, x30, [sp, #0x10]
100000ff8: 910043fd    	add	x29, sp, #0x10
100000ffc: aa0003f3    	mov	x19, x0
100001000: 940001e1    	bl	0x100001784 <_get_current_jit_context>
100001004: b4000173    	cbz	x19, 0x100001030 <_exception_has_pending_hostcall+0x40>
100001008: f85b0268    	ldur	x8, [x19, #-0x50]
10000100c: f100001f    	cmp	x0, #0x0
100001010: fa401904    	ccmp	x8, #0x0, #0x4, ne
100001014: 9a931008    	csel	x8, x0, x19, ne
100001018: f8528108    	ldur	x8, [x8, #-0xd8]
10000101c: b40000a8    	cbz	x8, 0x100001030 <_exception_has_pending_hostcall+0x40>
100001020: b9400908    	ldr	w8, [x8, #0x8]
100001024: 7100011f    	cmp	w8, #0x0
100001028: 1a9f07e0    	cset	w0, ne
10000102c: 14000002    	b	0x100001034 <_exception_has_pending_hostcall+0x44>
100001030: 52800000    	mov	w0, #0x0                ; =0
100001034: a9417bfd    	ldp	x29, x30, [sp, #0x10]
100001038: a8c24ff4    	ldp	x20, x19, [sp], #0x20
10000103c: d65f03c0    	ret

0000000100001040 <_exception_mark_activation_roots>:
100001040: a9bc5ff8    	stp	x24, x23, [sp, #-0x40]!
100001044: a90157f6    	stp	x22, x21, [sp, #0x10]
100001048: a9024ff4    	stp	x20, x19, [sp, #0x20]
10000104c: a9037bfd    	stp	x29, x30, [sp, #0x30]
100001050: 9100c3fd    	add	x29, sp, #0x30
100001054: aa0003f3    	mov	x19, x0
100001058: aa0203e8    	mov	x8, x2
10000105c: f8410d09    	ldr	x9, [x8, #0x10]!
100001060: b4000129    	cbz	x9, 0x100001084 <_exception_mark_activation_roots+0x44>
100001064: aa1303e0    	mov	x0, x19
100001068: aa0803e1    	mov	x1, x8
10000106c: 52800022    	mov	w2, #0x1                ; =1
100001070: a9437bfd    	ldp	x29, x30, [sp, #0x30]
100001074: a9424ff4    	ldp	x20, x19, [sp, #0x20]
100001078: a94157f6    	ldp	x22, x21, [sp, #0x10]
10000107c: a8c45ff8    	ldp	x24, x23, [sp], #0x40
100001080: 141f4174    	b	0x1007d1650 <_gc_heap_mark_roots>
100001084: aa0203f4    	mov	x20, x2
100001088: f8560028    	ldur	x8, [x1, #-0xa0]
10000108c: b4000108    	cbz	x8, 0x1000010ac <_exception_mark_activation_roots+0x6c>
100001090: b9401a81    	ldr	w1, [x20, #0x18]
100001094: f9400909    	ldr	x9, [x8, #0x10]
100001098: f9400929    	ldr	x9, [x9, #0x10]
10000109c: f9400100    	ldr	x0, [x8]
1000010a0: d63f0120    	blr	x9
1000010a4: aa0003f5    	mov	x21, x0
1000010a8: 14000002    	b	0x1000010b0 <_exception_mark_activation_roots+0x70>
1000010ac: d2800015    	mov	x21, #0x0               ; =0
1000010b0: b9402a88    	ldr	w8, [x20, #0x28]
1000010b4: 7100051f    	cmp	w8, #0x1
1000010b8: 540002cb    	b.lt	0x100001110 <_exception_mark_activation_roots+0xd0>
1000010bc: d2800016    	mov	x22, #0x0               ; =0
1000010c0: d2800017    	mov	x23, #0x0               ; =0
1000010c4: 1400000a    	b	0x1000010ec <_exception_mark_activation_roots+0xac>
1000010c8: 8b160121    	add	x1, x9, x22
1000010cc: aa1303e0    	mov	x0, x19
1000010d0: 52800022    	mov	w2, #0x1                ; =1
1000010d4: 941f415f    	bl	0x1007d1650 <_gc_heap_mark_roots>
1000010d8: b9402a88    	ldr	w8, [x20, #0x28]
1000010dc: 910006f7    	add	x23, x23, #0x1
1000010e0: 910022d6    	add	x22, x22, #0x8
1000010e4: eb28c2ff    	cmp	x23, w8, sxtw
1000010e8: 5400014a    	b.ge	0x100001110 <_exception_mark_activation_roots+0xd0>
1000010ec: f9401289    	ldr	x9, [x20, #0x20]
1000010f0: b4ffff69    	cbz	x9, 0x1000010dc <_exception_mark_activation_roots+0x9c>
1000010f4: b4fffeb5    	cbz	x21, 0x1000010c8 <_exception_mark_activation_roots+0x88>
1000010f8: b89fc2aa    	ldursw	x10, [x21, #-0x4]
1000010fc: eb0a02ff    	cmp	x23, x10
100001100: 54fffeea    	b.ge	0x1000010dc <_exception_mark_activation_roots+0x9c>
100001104: b8777aaa    	ldr	w10, [x21, x23, lsl #2]
100001108: 35fffe0a    	cbnz	w10, 0x1000010c8 <_exception_mark_activation_roots+0x88>
10000110c: 17fffff4    	b	0x1000010dc <_exception_mark_activation_roots+0x9c>
100001110: a9437bfd    	ldp	x29, x30, [sp, #0x30]
100001114: a9424ff4    	ldp	x20, x19, [sp, #0x20]
100001118: a94157f6    	ldp	x22, x21, [sp, #0x10]
10000111c: a8c45ff8    	ldp	x24, x23, [sp], #0x40
100001120: d65f03c0    	ret

0000000100001124 <_exception_raise_current>:
100001124: a9be4ff4    	stp	x20, x19, [sp, #-0x20]!
100001128: a9017bfd    	stp	x29, x30, [sp, #0x10]
10000112c: 910043fd    	add	x29, sp, #0x10
100001130: aa0003f3    	mov	x19, x0
100001134: f8528000    	ldur	x0, [x0, #-0xd8]
100001138: b5000060    	cbnz	x0, 0x100001144 <_exception_raise_current+0x20>
10000113c: aa1303e0    	mov	x0, x19
100001140: 97fffdc4    	bl	0x100000850 <_ctx_execution_fallback>
100001144: f9400014    	ldr	x20, [x0]
100001148: b5000134    	cbnz	x20, 0x10000116c <_exception_raise_current+0x48>
10000114c: 94000199    	bl	0x1000017b0 <_jit_current_trap_activation>
100001150: 52800188    	mov	w8, #0xc                ; =12
100001154: b900d408    	str	w8, [x0, #0xd4]
100001158: aa1303e0    	mov	x0, x19
10000115c: 941f1e92    	bl	0x1007c8ba4 <_ctx_gc_clear_root_scopes_internal>
100001160: 94000194    	bl	0x1000017b0 <_jit_current_trap_activation>
100001164: 52800021    	mov	w1, #0x1                ; =1
100001168: 941fb989    	bl	0x1007ef78c <_write+0x1007ef78c>
10000116c: f9406e81    	ldr	x1, [x20, #0xd8]
100001170: aa1303e0    	mov	x0, x19
100001174: 97fffdc3    	bl	0x100000880 <_ctx_gc_restore_root_scopes_internal>
100001178: b940d281    	ldr	w1, [x20, #0xd0]
10000117c: aa1403e0    	mov	x0, x20
100001180: 941fb983    	bl	0x1007ef78c <_write+0x1007ef78c>

0000000100001184 <_exception_raise_pending_hostcall>:
100001184: a9be4ff4    	stp	x20, x19, [sp, #-0x20]!
100001188: a9017bfd    	stp	x29, x30, [sp, #0x10]
10000118c: 910043fd    	add	x29, sp, #0x10
100001190: aa0003f3    	mov	x19, x0
100001194: 9400017c    	bl	0x100001784 <_get_current_jit_context>
100001198: b4000133    	cbz	x19, 0x1000011bc <_exception_raise_pending_hostcall+0x38>
10000119c: f85b0268    	ldur	x8, [x19, #-0x50]
1000011a0: f100001f    	cmp	x0, #0x0
1000011a4: fa401904    	ccmp	x8, #0x0, #0x4, ne
1000011a8: 9a931008    	csel	x8, x0, x19, ne
1000011ac: f8528108    	ldur	x8, [x8, #-0xd8]
1000011b0: b4000068    	cbz	x8, 0x1000011bc <_exception_raise_pending_hostcall+0x38>
1000011b4: b9400908    	ldr	w8, [x8, #0x8]
1000011b8: 35000088    	cbnz	w8, 0x1000011c8 <_exception_raise_pending_hostcall+0x44>
1000011bc: a9417bfd    	ldp	x29, x30, [sp, #0x10]
1000011c0: a8c24ff4    	ldp	x20, x19, [sp], #0x20
1000011c4: d65f03c0    	ret
1000011c8: aa1303e0    	mov	x0, x19
1000011cc: 97fffddd    	bl	0x100000940 <_exception_activation_context>
1000011d0: f8528008    	ldur	x8, [x0, #-0xd8]
1000011d4: b900091f    	str	wzr, [x8, #0x8]
1000011d8: 97ffffd3    	bl	0x100001124 <_exception_raise_current>

00000001000011dc <_exception_reset_execution_state>:
1000011dc: b40003a0    	cbz	x0, 0x100001250 <_exception_reset_execution_state+0x74>
1000011e0: a9be4ff4    	stp	x20, x19, [sp, #-0x20]!
1000011e4: a9017bfd    	stp	x29, x30, [sp, #0x10]
1000011e8: 910043fd    	add	x29, sp, #0x10
1000011ec: aa0003f3    	mov	x19, x0
1000011f0: f9400000    	ldr	x0, [x0]
1000011f4: b40000a0    	cbz	x0, 0x100001208 <_exception_reset_execution_state+0x2c>
1000011f8: f9406414    	ldr	x20, [x0, #0xc8]
1000011fc: 941fb7f3    	bl	0x1007ef1c8 <_write+0x1007ef1c8>
100001200: aa1403e0    	mov	x0, x20
100001204: b5ffffb4    	cbnz	x20, 0x1000011f8 <_exception_reset_execution_state+0x1c>
100001208: f900027f    	str	xzr, [x19]
10000120c: aa1303e0    	mov	x0, x19
100001210: 941f1e77    	bl	0x1007c8bec <_jit_execution_clear_root_scopes>
100001214: f9401260    	ldr	x0, [x19, #0x20]
100001218: b4000060    	cbz	x0, 0x100001224 <_exception_reset_execution_state+0x48>
10000121c: 941fb7eb    	bl	0x1007ef1c8 <_write+0x1007ef1c8>
100001220: f900127f    	str	xzr, [x19, #0x20]
100001224: f9000a7f    	str	xzr, [x19, #0x10]
100001228: b9002a7f    	str	wzr, [x19, #0x28]
10000122c: b9001a7f    	str	wzr, [x19, #0x18]
100001230: b9000a7f    	str	wzr, [x19, #0x8]
100001234: f9401a60    	ldr	x0, [x19, #0x30]
100001238: b4000060    	cbz	x0, 0x100001244 <_exception_reset_execution_state+0x68>
10000123c: 941fb7e3    	bl	0x1007ef1c8 <_write+0x1007ef1c8>
100001240: f9001a7f    	str	xzr, [x19, #0x30]
100001244: b9003a7f    	str	wzr, [x19, #0x38]
100001248: a9417bfd    	ldp	x29, x30, [sp, #0x10]
10000124c: a8c24ff4    	ldp	x20, x19, [sp], #0x20
100001250: d65f03c0    	ret

0000000100001254 <_exception_set_payload>:
100001254: a9bb67fa    	stp	x26, x25, [sp, #-0x50]!
100001258: a9015ff8    	stp	x24, x23, [sp, #0x10]
10000125c: a90257f6    	stp	x22, x21, [sp, #0x20]
100001260: a9034ff4    	stp	x20, x19, [sp, #0x30]
100001264: a9047bfd    	stp	x29, x30, [sp, #0x40]
100001268: 910103fd    	add	x29, sp, #0x40
10000126c: aa0403f3    	mov	x19, x4
100001270: aa0303f4    	mov	x20, x3
100001274: aa0203f7    	mov	x23, x2
100001278: aa0103f5    	mov	x21, x1
10000127c: f8528016    	ldur	x22, [x0, #-0xd8]
100001280: b5000076    	cbnz	x22, 0x10000128c <_exception_set_payload+0x38>
100001284: 97fffd73    	bl	0x100000850 <_ctx_execution_fallback>
100001288: aa0003f6    	mov	x22, x0
10000128c: 37f80394    	tbnz	w20, #0x1f, 0x1000012fc <_exception_set_payload+0xa8>
100001290: b4000376    	cbz	x22, 0x1000012fc <_exception_set_payload+0xa8>
100001294: b5000057    	cbnz	x23, 0x10000129c <_exception_set_payload+0x48>
100001298: 35000334    	cbnz	w20, 0x1000012fc <_exception_set_payload+0xa8>
10000129c: 34000174    	cbz	w20, 0x1000012c8 <_exception_set_payload+0x74>
1000012a0: 2a1403e8    	mov	w8, w20
1000012a4: d37df119    	lsl	x25, x8, #3
1000012a8: aa1903e0    	mov	x0, x25
1000012ac: 94000224    	bl	0x100001b3c <_wasmoon_native_malloc>
1000012b0: b4000260    	cbz	x0, 0x1000012fc <_exception_set_payload+0xa8>
1000012b4: aa0003f8    	mov	x24, x0
1000012b8: aa1703e1    	mov	x1, x23
1000012bc: aa1903e2    	mov	x2, x25
1000012c0: 941fb840    	bl	0x1007ef3c0 <_write+0x1007ef3c0>
1000012c4: 14000002    	b	0x1000012cc <_exception_set_payload+0x78>
1000012c8: d2800018    	mov	x24, #0x0               ; =0
1000012cc: f94012c0    	ldr	x0, [x22, #0x20]
1000012d0: 941fb7be    	bl	0x1007ef1c8 <_write+0x1007ef1c8>
1000012d4: f90012d8    	str	x24, [x22, #0x20]
1000012d8: b9002ad4    	str	w20, [x22, #0x28]
1000012dc: b9001ad5    	str	w21, [x22, #0x18]
1000012e0: f9000ad3    	str	x19, [x22, #0x10]
1000012e4: a9447bfd    	ldp	x29, x30, [sp, #0x40]
1000012e8: a9434ff4    	ldp	x20, x19, [sp, #0x30]
1000012ec: a94257f6    	ldp	x22, x21, [sp, #0x20]
1000012f0: a9415ff8    	ldp	x24, x23, [sp, #0x10]
1000012f4: a8c567fa    	ldp	x26, x25, [sp], #0x50
1000012f8: d65f03c0    	ret
1000012fc: 9400012d    	bl	0x1000017b0 <_jit_current_trap_activation>
100001300: 52800128    	mov	w8, #0x9                ; =9
100001304: b900d408    	str	w8, [x0, #0xd4]
100001308: 9400012a    	bl	0x1000017b0 <_jit_current_trap_activation>
10000130c: 52800021    	mov	w1, #0x1                ; =1
100001310: 941fb91f    	bl	0x1007ef78c <_write+0x1007ef78c>

0000000100001314 <_exception_spill_locals_impl>:
100001314: a9bc5ff8    	stp	x24, x23, [sp, #-0x40]!
100001318: a90157f6    	stp	x22, x21, [sp, #0x10]
10000131c: a9024ff4    	stp	x20, x19, [sp, #0x20]
100001320: a9037bfd    	stp	x29, x30, [sp, #0x30]
100001324: 9100c3fd    	add	x29, sp, #0x30
100001328: aa0203f3    	mov	x19, x2
10000132c: aa0103f4    	mov	x20, x1
100001330: aa0003f5    	mov	x21, x0
100001334: 94000114    	bl	0x100001784 <_get_current_jit_context>
100001338: b4000155    	cbz	x21, 0x100001360 <_exception_spill_locals_impl+0x4c>
10000133c: f85b02a8    	ldur	x8, [x21, #-0x50]
100001340: f100011f    	cmp	x8, #0x0
100001344: fa401804    	ccmp	x0, #0x0, #0x4, ne
100001348: 540000c0    	b.eq	0x100001360 <_exception_spill_locals_impl+0x4c>
10000134c: f8528015    	ldur	x21, [x0, #-0xd8]
100001350: b40000f5    	cbz	x21, 0x10000136c <_exception_spill_locals_impl+0x58>
100001354: d2800016    	mov	x22, #0x0               ; =0
100001358: b5000134    	cbnz	x20, 0x10000137c <_exception_spill_locals_impl+0x68>
10000135c: 14000013    	b	0x1000013a8 <_exception_spill_locals_impl+0x94>
100001360: aa1503e0    	mov	x0, x21
100001364: f8528015    	ldur	x21, [x0, #-0xd8]
100001368: b5ffff75    	cbnz	x21, 0x100001354 <_exception_spill_locals_impl+0x40>
10000136c: 97fffd39    	bl	0x100000850 <_ctx_execution_fallback>
100001370: aa0003f5    	mov	x21, x0
100001374: d2800016    	mov	x22, #0x0               ; =0
100001378: b4000194    	cbz	x20, 0x1000013a8 <_exception_spill_locals_impl+0x94>
10000137c: 7100067f    	cmp	w19, #0x1
100001380: 5400014b    	b.lt	0x1000013a8 <_exception_spill_locals_impl+0x94>
100001384: 531f7a68    	lsl	w8, w19, #1
100001388: d37d7d17    	ubfiz	x23, x8, #3, #32
10000138c: aa1703e0    	mov	x0, x23
100001390: 940001eb    	bl	0x100001b3c <_wasmoon_native_malloc>
100001394: b4000200    	cbz	x0, 0x1000013d4 <_exception_spill_locals_impl+0xc0>
100001398: aa0003f6    	mov	x22, x0
10000139c: aa1403e1    	mov	x1, x20
1000013a0: aa1703e2    	mov	x2, x23
1000013a4: 941fb807    	bl	0x1007ef3c0 <_write+0x1007ef3c0>
1000013a8: f9401aa0    	ldr	x0, [x21, #0x30]
1000013ac: 941fb787    	bl	0x1007ef1c8 <_write+0x1007ef1c8>
1000013b0: f9001ab6    	str	x22, [x21, #0x30]
1000013b4: f10002df    	cmp	x22, #0x0
1000013b8: 1a9303e8    	csel	w8, wzr, w19, eq
1000013bc: b9003aa8    	str	w8, [x21, #0x38]
1000013c0: a9437bfd    	ldp	x29, x30, [sp, #0x30]
1000013c4: a9424ff4    	ldp	x20, x19, [sp, #0x20]
1000013c8: a94157f6    	ldp	x22, x21, [sp, #0x10]
1000013cc: a8c45ff8    	ldp	x24, x23, [sp], #0x40
1000013d0: d65f03c0    	ret
1000013d4: 940000f7    	bl	0x1000017b0 <_jit_current_trap_activation>
1000013d8: 52800128    	mov	w8, #0x9                ; =9
1000013dc: b900d408    	str	w8, [x0, #0xd4]
1000013e0: 940000f4    	bl	0x1000017b0 <_jit_current_trap_activation>
1000013e4: 52800021    	mov	w1, #0x1                ; =1
1000013e8: 941fb8e9    	bl	0x1007ef78c <_write+0x1007ef78c>

00000001000013ec <_exception_stage_hostcall>:
1000013ec: b40003a0    	cbz	x0, 0x100001460 <_exception_stage_hostcall+0x74>
1000013f0: a9bb67fa    	stp	x26, x25, [sp, #-0x50]!
1000013f4: a9015ff8    	stp	x24, x23, [sp, #0x10]
1000013f8: a90257f6    	stp	x22, x21, [sp, #0x20]
1000013fc: a9034ff4    	stp	x20, x19, [sp, #0x30]
100001400: a9047bfd    	stp	x29, x30, [sp, #0x40]
100001404: 910103fd    	add	x29, sp, #0x40
100001408: aa0303f3    	mov	x19, x3
10000140c: aa0203f5    	mov	x21, x2
100001410: aa0103f4    	mov	x20, x1
100001414: aa0403f7    	mov	x23, x4
100001418: aa0003f6    	mov	x22, x0
10000141c: 941f0218    	bl	0x1007c1c7c <_jit_hostcall_is_active>
100001420: 340003c0    	cbz	w0, 0x100001498 <_exception_stage_hostcall+0xac>
100001424: 940000e3    	bl	0x1000017b0 <_jit_current_trap_activation>
100001428: b940d008    	ldr	w8, [x0, #0xd0]
10000142c: 12800000    	mov	w0, #-0x1               ; =-1
100001430: 37f80373    	tbnz	w19, #0x1f, 0x10000149c <_exception_stage_hostcall+0xb0>
100001434: 34000348    	cbz	w8, 0x10000149c <_exception_stage_hostcall+0xb0>
100001438: b5000055    	cbnz	x21, 0x100001440 <_exception_stage_hostcall+0x54>
10000143c: 35000313    	cbnz	w19, 0x10000149c <_exception_stage_hostcall+0xb0>
100001440: 34000157    	cbz	w23, 0x100001468 <_exception_stage_hostcall+0x7c>
100001444: 37f802d4    	tbnz	w20, #0x1f, 0x10000149c <_exception_stage_hostcall+0xb0>
100001448: b85f82c9    	ldur	w9, [x22, #-0x8]
10000144c: 6b09029f    	cmp	w20, w9
100001450: 5400026a    	b.ge	0x10000149c <_exception_stage_hostcall+0xb0>
100001454: f85c02c8    	ldur	x8, [x22, #-0x40]
100001458: b8745914    	ldr	w20, [x8, w20, uxtw #2]
10000145c: 14000004    	b	0x10000146c <_exception_stage_hostcall+0x80>
100001460: 12800000    	mov	w0, #-0x1               ; =-1
100001464: d65f03c0    	ret
100001468: 37f801b4    	tbnz	w20, #0x1f, 0x10000149c <_exception_stage_hostcall+0xb0>
10000146c: 940000c6    	bl	0x100001784 <_get_current_jit_context>
100001470: f85b02c8    	ldur	x8, [x22, #-0x50]
100001474: f100001f    	cmp	x0, #0x0
100001478: fa401904    	ccmp	x8, #0x0, #0x4, ne
10000147c: 9a961018    	csel	x24, x0, x22, ne
100001480: f8528319    	ldur	x25, [x24, #-0xd8]
100001484: b40000b9    	cbz	x25, 0x100001498 <_exception_stage_hostcall+0xac>
100001488: b5000175    	cbnz	x21, 0x1000014b4 <_exception_stage_hostcall+0xc8>
10000148c: 34000153    	cbz	w19, 0x1000014b4 <_exception_stage_hostcall+0xc8>
100001490: 52800000    	mov	w0, #0x0                ; =0
100001494: 14000002    	b	0x10000149c <_exception_stage_hostcall+0xb0>
100001498: 12800000    	mov	w0, #-0x1               ; =-1
10000149c: a9447bfd    	ldp	x29, x30, [sp, #0x40]
1000014a0: a9434ff4    	ldp	x20, x19, [sp, #0x30]
1000014a4: a94257f6    	ldp	x22, x21, [sp, #0x20]
1000014a8: a9415ff8    	ldp	x24, x23, [sp, #0x10]
1000014ac: a8c567fa    	ldp	x26, x25, [sp], #0x50
1000014b0: d65f03c0    	ret
1000014b4: 34000173    	cbz	w19, 0x1000014e0 <_exception_stage_hostcall+0xf4>
1000014b8: 2a1303e8    	mov	w8, w19
1000014bc: d37df117    	lsl	x23, x8, #3
1000014c0: aa1703e0    	mov	x0, x23
1000014c4: 9400019e    	bl	0x100001b3c <_wasmoon_native_malloc>
1000014c8: b4fffea0    	cbz	x0, 0x10000149c <_exception_stage_hostcall+0xb0>
1000014cc: aa0003f6    	mov	x22, x0
1000014d0: aa1503e1    	mov	x1, x21
1000014d4: aa1703e2    	mov	x2, x23
1000014d8: 941fb7ba    	bl	0x1007ef3c0 <_write+0x1007ef3c0>
1000014dc: 14000002    	b	0x1000014e4 <_exception_stage_hostcall+0xf8>
1000014e0: d2800016    	mov	x22, #0x0               ; =0
1000014e4: f9401320    	ldr	x0, [x25, #0x20]
1000014e8: 941fb738    	bl	0x1007ef1c8 <_write+0x1007ef1c8>
1000014ec: f9001336    	str	x22, [x25, #0x20]
1000014f0: b9002b33    	str	w19, [x25, #0x28]
1000014f4: b9001b34    	str	w20, [x25, #0x18]
1000014f8: f9000b3f    	str	xzr, [x25, #0x10]
1000014fc: f8528308    	ldur	x8, [x24, #-0xd8]
100001500: 52800020    	mov	w0, #0x1                ; =1
100001504: b9000900    	str	w0, [x8, #0x8]
100001508: 17ffffe5    	b	0x10000149c <_exception_stage_hostcall+0xb0>

000000010000150c <_exception_throw_impl>:
10000150c: a9bd57f6    	stp	x22, x21, [sp, #-0x30]!
100001510: a9014ff4    	stp	x20, x19, [sp, #0x10]
100001514: a9027bfd    	stp	x29, x30, [sp, #0x20]
100001518: 910083fd    	add	x29, sp, #0x20
10000151c: aa0303f3    	mov	x19, x3
100001520: aa0203f4    	mov	x20, x2
100001524: aa0103f5    	mov	x21, x1
100001528: b40000e0    	cbz	x0, 0x100001544 <_exception_throw_impl+0x38>
10000152c: 37f800d5    	tbnz	w21, #0x1f, 0x100001544 <_exception_throw_impl+0x38>
100001530: b85f8008    	ldur	w8, [x0, #-0x8]
100001534: 6b0802bf    	cmp	w21, w8
100001538: 5400006a    	b.ge	0x100001544 <_exception_throw_impl+0x38>
10000153c: f85c0008    	ldur	x8, [x0, #-0x40]
100001540: b8755915    	ldr	w21, [x8, w21, uxtw #2]
100001544: 97fffcff    	bl	0x100000940 <_exception_activation_context>
100001548: aa0003f6    	mov	x22, x0
10000154c: aa1503e1    	mov	x1, x21
100001550: aa1403e2    	mov	x2, x20
100001554: aa1303e3    	mov	x3, x19
100001558: d2800004    	mov	x4, #0x0                ; =0
10000155c: 97ffff3e    	bl	0x100001254 <_exception_set_payload>
100001560: aa1603e0    	mov	x0, x22
100001564: 97fffef0    	bl	0x100001124 <_exception_raise_current>

0000000100001568 <_exception_throw_ref_impl>:
100001568: a9bd57f6    	stp	x22, x21, [sp, #-0x30]!
10000156c: a9014ff4    	stp	x20, x19, [sp, #0x10]
100001570: a9027bfd    	stp	x29, x30, [sp, #0x20]
100001574: 910083fd    	add	x29, sp, #0x20
100001578: aa0103f3    	mov	x19, x1
10000157c: aa0003f5    	mov	x21, x0
100001580: 94000081    	bl	0x100001784 <_get_current_jit_context>
100001584: b40000d5    	cbz	x21, 0x10000159c <_exception_throw_ref_impl+0x34>
100001588: aa0003f4    	mov	x20, x0
10000158c: f85b02a8    	ldur	x8, [x21, #-0x50]
100001590: f100011f    	cmp	x8, #0x0
100001594: fa401804    	ccmp	x0, #0x0, #0x4, ne
100001598: 54000041    	b.ne	0x1000015a0 <_exception_throw_ref_impl+0x38>
10000159c: aa1503f4    	mov	x20, x21
1000015a0: f8560295    	ldur	x21, [x20, #-0xa0]
1000015a4: b4000395    	cbz	x21, 0x100001614 <_exception_throw_ref_impl+0xac>
1000015a8: f9400aa8    	ldr	x8, [x21, #0x10]
1000015ac: f9400508    	ldr	x8, [x8, #0x8]
1000015b0: f94002a0    	ldr	x0, [x21]
1000015b4: aa1303e1    	mov	x1, x19
1000015b8: d63f0100    	blr	x8
1000015bc: d1000408    	sub	x8, x0, #0x1
1000015c0: 321f77e9    	mov	w9, #0x7ffffffe         ; =2147483646
1000015c4: eb09011f    	cmp	x8, x9
1000015c8: 54000268    	b.hi	0x100001614 <_exception_throw_ref_impl+0xac>
1000015cc: f94006a8    	ldr	x8, [x21, #0x8]
1000015d0: b9400909    	ldr	w9, [x8, #0x8]
1000015d4: 6b00013f    	cmp	w9, w0
1000015d8: 540001eb    	b.lt	0x100001614 <_exception_throw_ref_impl+0xac>
1000015dc: f9400108    	ldr	x8, [x8]
1000015e0: b40001a8    	cbz	x8, 0x100001614 <_exception_throw_ref_impl+0xac>
1000015e4: 51000409    	sub	w9, w0, #0x1
1000015e8: 5280050a    	mov	w10, #0x28              ; =40
1000015ec: 9baa2128    	umaddl	x8, w9, w10, x8
1000015f0: b9402503    	ldr	w3, [x8, #0x24]
1000015f4: 37f80103    	tbnz	w3, #0x1f, 0x100001614 <_exception_throw_ref_impl+0xac>
1000015f8: b9402101    	ldr	w1, [x8, #0x20]
1000015fc: f9400102    	ldr	x2, [x8]
100001600: aa1403e0    	mov	x0, x20
100001604: aa1303e4    	mov	x4, x19
100001608: 97ffff13    	bl	0x100001254 <_exception_set_payload>
10000160c: aa1403e0    	mov	x0, x20
100001610: 97fffec5    	bl	0x100001124 <_exception_raise_current>
100001614: f100027f    	cmp	x19, #0x0
100001618: 52800108    	mov	w8, #0x8                ; =8
10000161c: 528001c9    	mov	w9, #0xe                ; =14
100001620: 1a880133    	csel	w19, w9, w8, eq
100001624: 94000063    	bl	0x1000017b0 <_jit_current_trap_activation>
100001628: b900d413    	str	w19, [x0, #0xd4]
10000162c: 94000061    	bl	0x1000017b0 <_jit_current_trap_activation>
100001630: 52800021    	mov	w1, #0x1                ; =1
100001634: 941fb856    	bl	0x1007ef78c <_write+0x1007ef78c>

0000000100001638 <_exception_try_begin_impl>:
100001638: a9be4ff4    	stp	x20, x19, [sp, #-0x20]!
10000163c: a9017bfd    	stp	x29, x30, [sp, #0x10]
100001640: 910043fd    	add	x29, sp, #0x10
100001644: aa0103f3    	mov	x19, x1
100001648: aa0003f4    	mov	x20, x0
10000164c: 9400004e    	bl	0x100001784 <_get_current_jit_context>
100001650: b40000b4    	cbz	x20, 0x100001664 <_exception_try_begin_impl+0x2c>
100001654: f85b0288    	ldur	x8, [x20, #-0x50]
100001658: f100011f    	cmp	x8, #0x0
10000165c: fa401804    	ccmp	x0, #0x0, #0x4, ne
100001660: 54000041    	b.ne	0x100001668 <_exception_try_begin_impl+0x30>
100001664: aa1403e0    	mov	x0, x20
100001668: f8528014    	ldur	x20, [x0, #-0xd8]
10000166c: b5000074    	cbnz	x20, 0x100001678 <_exception_try_begin_impl+0x40>
100001670: 97fffc78    	bl	0x100000850 <_ctx_execution_fallback>
100001674: aa0003f4    	mov	x20, x0
100001678: 52801c00    	mov	w0, #0xe0               ; =224
10000167c: 94000130    	bl	0x100001b3c <_wasmoon_native_malloc>
100001680: b4000140    	cbz	x0, 0x1000016a8 <_exception_try_begin_impl+0x70>
100001684: f9400288    	ldr	x8, [x20]
100001688: f9006408    	str	x8, [x0, #0xc8]
10000168c: b900d013    	str	w19, [x0, #0xd0]
100001690: f9403288    	ldr	x8, [x20, #0x60]
100001694: f9006c08    	str	x8, [x0, #0xd8]
100001698: f9000280    	str	x0, [x20]
10000169c: a9417bfd    	ldp	x29, x30, [sp, #0x10]
1000016a0: a8c24ff4    	ldp	x20, x19, [sp], #0x20
1000016a4: d65f03c0    	ret
1000016a8: 94000042    	bl	0x1000017b0 <_jit_current_trap_activation>
1000016ac: 52800128    	mov	w8, #0x9                ; =9
1000016b0: b900d408    	str	w8, [x0, #0xd4]
1000016b4: 9400003f    	bl	0x1000017b0 <_jit_current_trap_activation>
1000016b8: 52800021    	mov	w1, #0x1                ; =1
1000016bc: 941fb834    	bl	0x1007ef78c <_write+0x1007ef78c>

00000001000016c0 <_exception_try_end_impl>:
1000016c0: a9be4ff4    	stp	x20, x19, [sp, #-0x20]!
1000016c4: a9017bfd    	stp	x29, x30, [sp, #0x10]
1000016c8: 910043fd    	add	x29, sp, #0x10
1000016cc: aa0103f4    	mov	x20, x1
1000016d0: aa0003f3    	mov	x19, x0
1000016d4: 9400002c    	bl	0x100001784 <_get_current_jit_context>
1000016d8: b4000153    	cbz	x19, 0x100001700 <_exception_try_end_impl+0x40>
1000016dc: f85b0268    	ldur	x8, [x19, #-0x50]
1000016e0: f100011f    	cmp	x8, #0x0
1000016e4: fa401804    	ccmp	x0, #0x0, #0x4, ne
1000016e8: 540000c0    	b.eq	0x100001700 <_exception_try_end_impl+0x40>
1000016ec: f8528013    	ldur	x19, [x0, #-0xd8]
1000016f0: b40000f3    	cbz	x19, 0x10000170c <_exception_try_end_impl+0x4c>
1000016f4: f9400260    	ldr	x0, [x19]
1000016f8: b5000120    	cbnz	x0, 0x10000171c <_exception_try_end_impl+0x5c>
1000016fc: 1400001c    	b	0x10000176c <_exception_try_end_impl+0xac>
100001700: aa1303e0    	mov	x0, x19
100001704: f8528013    	ldur	x19, [x0, #-0xd8]
100001708: b5ffff73    	cbnz	x19, 0x1000016f4 <_exception_try_end_impl+0x34>
10000170c: 97fffc51    	bl	0x100000850 <_ctx_execution_fallback>
100001710: aa0003f3    	mov	x19, x0
100001714: f9400260    	ldr	x0, [x19]
100001718: b40002a0    	cbz	x0, 0x10000176c <_exception_try_end_impl+0xac>
10000171c: b940d008    	ldr	w8, [x0, #0xd0]
100001720: 6b14011f    	cmp	w8, w20
100001724: 54000241    	b.ne	0x10000176c <_exception_try_end_impl+0xac>
100001728: f9406408    	ldr	x8, [x0, #0xc8]
10000172c: f9000268    	str	x8, [x19]
100001730: 941fb6a6    	bl	0x1007ef1c8 <_write+0x1007ef1c8>
100001734: f9401260    	ldr	x0, [x19, #0x20]
100001738: b4000060    	cbz	x0, 0x100001744 <_exception_try_end_impl+0x84>
10000173c: 941fb6a3    	bl	0x1007ef1c8 <_write+0x1007ef1c8>
100001740: f900127f    	str	xzr, [x19, #0x20]
100001744: f9000a7f    	str	xzr, [x19, #0x10]
100001748: b9002a7f    	str	wzr, [x19, #0x28]
10000174c: f9401a60    	ldr	x0, [x19, #0x30]
100001750: b4000060    	cbz	x0, 0x10000175c <_exception_try_end_impl+0x9c>
100001754: 941fb69d    	bl	0x1007ef1c8 <_write+0x1007ef1c8>
100001758: f9001a7f    	str	xzr, [x19, #0x30]
10000175c: b9003a7f    	str	wzr, [x19, #0x38]
100001760: a9417bfd    	ldp	x29, x30, [sp, #0x10]
100001764: a8c24ff4    	ldp	x20, x19, [sp], #0x20
100001768: d65f03c0    	ret
10000176c: 94000011    	bl	0x1000017b0 <_jit_current_trap_activation>
100001770: 52800108    	mov	w8, #0x8                ; =8
100001774: b900d408    	str	w8, [x0, #0xd4]
100001778: 9400000e    	bl	0x1000017b0 <_jit_current_trap_activation>
10000177c: 52800021    	mov	w1, #0x1                ; =1
100001780: 941fb803    	bl	0x1007ef78c <_write+0x1007ef78c>

0000000100001784 <_get_current_jit_context>:
100001784: a9bf7bfd    	stp	x29, x30, [sp, #-0x10]!
100001788: 910003fd    	mov	x29, sp
10000178c: 94000009    	bl	0x1000017b0 <_jit_current_trap_activation>
100001790: b940d008    	ldr	w8, [x0, #0xd0]
100001794: 34000088    	cbz	w8, 0x1000017a4 <_get_current_jit_context+0x20>
100001798: f941c800    	ldr	x0, [x0, #0x390]
10000179c: a8c17bfd    	ldp	x29, x30, [sp], #0x10
1000017a0: d65f03c0    	ret
1000017a4: d2800000    	mov	x0, #0x0                ; =0
1000017a8: a8c17bfd    	ldp	x29, x30, [sp], #0x10
1000017ac: d65f03c0    	ret

00000001000017b0 <_jit_current_trap_activation>:
1000017b0: a9bf7bfd    	stp	x29, x30, [sp, #-0x10]!
1000017b4: 910003fd    	mov	x29, sp
1000017b8: b0004540    	adrp	x0, 0x1008aa000 <__M0IP29Milky201815aarch64__target16InternalAbiErrorPC15debug5Debug8to__reprN6constrS77258GRP29Milky201815aarch64__target16InternalAbiErrorE>
1000017bc: 911a6000    	add	x0, x0, #0x698
1000017c0: f9400008    	ldr	x8, [x0]
1000017c4: d63f0100    	blr	x8
1000017c8: f9400008    	ldr	x8, [x0]
1000017cc: b0004540    	adrp	x0, 0x1008aa000 <__M0IP29Milky201815aarch64__target16InternalAbiErrorPC15debug5Debug8to__reprN6constrS77258GRP29Milky201815aarch64__target16InternalAbiErrorE>
1000017d0: 911ac000    	add	x0, x0, #0x6b0
1000017d4: f9400009    	ldr	x9, [x0]
1000017d8: d63f0120    	blr	x9
1000017dc: f100011f    	cmp	x8, #0x0
1000017e0: 9a880000    	csel	x0, x0, x8, eq
1000017e4: a8c17bfd    	ldp	x29, x30, [sp], #0x10
1000017e8: d65f03c0    	ret

00000001000017ec <_wasmoon_jit_exception_delegate>:
1000017ec: a9bf7bfd    	stp	x29, x30, [sp, #-0x10]!
1000017f0: 910003fd    	mov	x29, sp
1000017f4: 97fffd04    	bl	0x100000c04 <_exception_delegate_impl>

00000001000017f8 <_wasmoon_jit_exception_get_spilled_local>:
1000017f8: a9be4ff4    	stp	x20, x19, [sp, #-0x20]!
1000017fc: a9017bfd    	stp	x29, x30, [sp, #0x10]
100001800: 910043fd    	add	x29, sp, #0x10
100001804: aa0103f3    	mov	x19, x1
100001808: aa0003f4    	mov	x20, x0
10000180c: 97ffffde    	bl	0x100001784 <_get_current_jit_context>
100001810: b40000b4    	cbz	x20, 0x100001824 <_wasmoon_jit_exception_get_spilled_local+0x2c>
100001814: f85b0288    	ldur	x8, [x20, #-0x50]
100001818: f100011f    	cmp	x8, #0x0
10000181c: fa401804    	ccmp	x0, #0x0, #0x4, ne
100001820: 54000101    	b.ne	0x100001840 <_wasmoon_jit_exception_get_spilled_local+0x48>
100001824: aa1403e0    	mov	x0, x20
100001828: f8528008    	ldur	x8, [x0, #-0xd8]
10000182c: b50000e8    	cbnz	x8, 0x100001848 <_wasmoon_jit_exception_get_spilled_local+0x50>
100001830: 97fffc08    	bl	0x100000850 <_ctx_execution_fallback>
100001834: aa0003e8    	mov	x8, x0
100001838: 36f800b3    	tbz	w19, #0x1f, 0x10000184c <_wasmoon_jit_exception_get_spilled_local+0x54>
10000183c: 1400000b    	b	0x100001868 <_wasmoon_jit_exception_get_spilled_local+0x70>
100001840: f8528008    	ldur	x8, [x0, #-0xd8]
100001844: b4ffff68    	cbz	x8, 0x100001830 <_wasmoon_jit_exception_get_spilled_local+0x38>
100001848: 37f80113    	tbnz	w19, #0x1f, 0x100001868 <_wasmoon_jit_exception_get_spilled_local+0x70>
10000184c: b9403909    	ldr	w9, [x8, #0x38]
100001850: 6b09027f    	cmp	w19, w9
100001854: 540000aa    	b.ge	0x100001868 <_wasmoon_jit_exception_get_spilled_local+0x70>
100001858: f9401908    	ldr	x8, [x8, #0x30]
10000185c: b4000068    	cbz	x8, 0x100001868 <_wasmoon_jit_exception_get_spilled_local+0x70>
100001860: f8735900    	ldr	x0, [x8, w19, uxtw #3]
100001864: 14000002    	b	0x10000186c <_wasmoon_jit_exception_get_spilled_local+0x74>
100001868: d2800000    	mov	x0, #0x0                ; =0
10000186c: a9417bfd    	ldp	x29, x30, [sp, #0x10]
100001870: a8c24ff4    	ldp	x20, x19, [sp], #0x20
100001874: d65f03c0    	ret

0000000100001878 <_wasmoon_jit_exception_get_tag>:
100001878: a9be4ff4    	stp	x20, x19, [sp, #-0x20]!
10000187c: a9017bfd    	stp	x29, x30, [sp, #0x10]
100001880: 910043fd    	add	x29, sp, #0x10
100001884: aa0003f3    	mov	x19, x0
100001888: 97ffffbf    	bl	0x100001784 <_get_current_jit_context>
10000188c: b40000b3    	cbz	x19, 0x1000018a0 <_wasmoon_jit_exception_get_tag+0x28>
100001890: f85b0268    	ldur	x8, [x19, #-0x50]
100001894: f100011f    	cmp	x8, #0x0
100001898: fa401804    	ccmp	x0, #0x0, #0x4, ne
10000189c: 54000041    	b.ne	0x1000018a4 <_wasmoon_jit_exception_get_tag+0x2c>
1000018a0: aa1303e0    	mov	x0, x19
1000018a4: f8528008    	ldur	x8, [x0, #-0xd8]
1000018a8: b5000068    	cbnz	x8, 0x1000018b4 <_wasmoon_jit_exception_get_tag+0x3c>
1000018ac: 97fffbe9    	bl	0x100000850 <_ctx_execution_fallback>
1000018b0: aa0003e8    	mov	x8, x0
1000018b4: b9401900    	ldr	w0, [x8, #0x18]
1000018b8: f85b0268    	ldur	x8, [x19, #-0x50]
1000018bc: b40001e8    	cbz	x8, 0x1000018f8 <_wasmoon_jit_exception_get_tag+0x80>
1000018c0: b85f8268    	ldur	w8, [x19, #-0x8]
1000018c4: 7100051f    	cmp	w8, #0x1
1000018c8: 5400012b    	b.lt	0x1000018ec <_wasmoon_jit_exception_get_tag+0x74>
1000018cc: d2800009    	mov	x9, #0x0                ; =0
1000018d0: f85c026a    	ldur	x10, [x19, #-0x40]
1000018d4: b869794b    	ldr	w11, [x10, x9, lsl #2]
1000018d8: 6b00017f    	cmp	w11, w0
1000018dc: 540000c0    	b.eq	0x1000018f4 <_wasmoon_jit_exception_get_tag+0x7c>
1000018e0: 91000529    	add	x9, x9, #0x1
1000018e4: eb09011f    	cmp	x8, x9
1000018e8: 54ffff61    	b.ne	0x1000018d4 <_wasmoon_jit_exception_get_tag+0x5c>
1000018ec: 12800000    	mov	w0, #-0x1               ; =-1
1000018f0: 14000002    	b	0x1000018f8 <_wasmoon_jit_exception_get_tag+0x80>
1000018f4: aa0903e0    	mov	x0, x9
1000018f8: a9417bfd    	ldp	x29, x30, [sp, #0x10]
1000018fc: a8c24ff4    	ldp	x20, x19, [sp], #0x20
100001900: d65f03c0    	ret

0000000100001904 <_wasmoon_jit_exception_get_value>:
100001904: a9be4ff4    	stp	x20, x19, [sp, #-0x20]!
100001908: a9017bfd    	stp	x29, x30, [sp, #0x10]
10000190c: 910043fd    	add	x29, sp, #0x10
100001910: aa0103f3    	mov	x19, x1
100001914: aa0003f4    	mov	x20, x0
100001918: 97ffff9b    	bl	0x100001784 <_get_current_jit_context>
10000191c: b40000b4    	cbz	x20, 0x100001930 <_wasmoon_jit_exception_get_value+0x2c>
100001920: f85b0288    	ldur	x8, [x20, #-0x50]
100001924: f100011f    	cmp	x8, #0x0
100001928: fa401804    	ccmp	x0, #0x0, #0x4, ne
10000192c: 54000101    	b.ne	0x10000194c <_wasmoon_jit_exception_get_value+0x48>
100001930: aa1403e0    	mov	x0, x20
100001934: f8528008    	ldur	x8, [x0, #-0xd8]
100001938: b50000e8    	cbnz	x8, 0x100001954 <_wasmoon_jit_exception_get_value+0x50>
10000193c: 97fffbc5    	bl	0x100000850 <_ctx_execution_fallback>
100001940: aa0003e8    	mov	x8, x0
100001944: 36f800b3    	tbz	w19, #0x1f, 0x100001958 <_wasmoon_jit_exception_get_value+0x54>
100001948: 1400000b    	b	0x100001974 <_wasmoon_jit_exception_get_value+0x70>
10000194c: f8528008    	ldur	x8, [x0, #-0xd8]
100001950: b4ffff68    	cbz	x8, 0x10000193c <_wasmoon_jit_exception_get_value+0x38>
100001954: 37f80113    	tbnz	w19, #0x1f, 0x100001974 <_wasmoon_jit_exception_get_value+0x70>
100001958: b9402909    	ldr	w9, [x8, #0x28]
10000195c: 6b09027f    	cmp	w19, w9
100001960: 540000aa    	b.ge	0x100001974 <_wasmoon_jit_exception_get_value+0x70>
100001964: f9401108    	ldr	x8, [x8, #0x20]
100001968: b4000068    	cbz	x8, 0x100001974 <_wasmoon_jit_exception_get_value+0x70>
10000196c: f8735900    	ldr	x0, [x8, w19, uxtw #3]
100001970: 14000002    	b	0x100001978 <_wasmoon_jit_exception_get_value+0x74>
100001974: d2800000    	mov	x0, #0x0                ; =0
100001978: a9417bfd    	ldp	x29, x30, [sp, #0x10]
10000197c: a8c24ff4    	ldp	x20, x19, [sp], #0x20
100001980: d65f03c0    	ret

0000000100001984 <_wasmoon_jit_exception_get_value_count>:
100001984: a9be4ff4    	stp	x20, x19, [sp, #-0x20]!
100001988: a9017bfd    	stp	x29, x30, [sp, #0x10]
10000198c: 910043fd    	add	x29, sp, #0x10
100001990: aa0003f3    	mov	x19, x0
100001994: 97ffff7c    	bl	0x100001784 <_get_current_jit_context>
100001998: b40000b3    	cbz	x19, 0x1000019ac <_wasmoon_jit_exception_get_value_count+0x28>
10000199c: f85b0268    	ldur	x8, [x19, #-0x50]
1000019a0: f100011f    	cmp	x8, #0x0
1000019a4: fa401804    	ccmp	x0, #0x0, #0x4, ne
1000019a8: 54000041    	b.ne	0x1000019b0 <_wasmoon_jit_exception_get_value_count+0x2c>
1000019ac: aa1303e0    	mov	x0, x19
1000019b0: f8528008    	ldur	x8, [x0, #-0xd8]
1000019b4: b5000068    	cbnz	x8, 0x1000019c0 <_wasmoon_jit_exception_get_value_count+0x3c>
1000019b8: 97fffba6    	bl	0x100000850 <_ctx_execution_fallback>
1000019bc: aa0003e8    	mov	x8, x0
1000019c0: b9402900    	ldr	w0, [x8, #0x28]
1000019c4: a9417bfd    	ldp	x29, x30, [sp, #0x10]
1000019c8: a8c24ff4    	ldp	x20, x19, [sp], #0x20
1000019cc: d65f03c0    	ret

00000001000019d0 <_wasmoon_jit_exception_spill_locals>:
1000019d0: 17fffe51    	b	0x100001314 <_exception_spill_locals_impl>

00000001000019d4 <_wasmoon_jit_exception_throw>:
1000019d4: a9bf7bfd    	stp	x29, x30, [sp, #-0x10]!
1000019d8: 910003fd    	mov	x29, sp
1000019dc: 97fffecc    	bl	0x10000150c <_exception_throw_impl>

00000001000019e0 <_wasmoon_jit_exception_throw_ref>:
1000019e0: a9bf7bfd    	stp	x29, x30, [sp, #-0x10]!
1000019e4: 910003fd    	mov	x29, sp
1000019e8: 97fffee0    	bl	0x100001568 <_exception_throw_ref_impl>

00000001000019ec <_wasmoon_jit_exception_throw_store_values_managed>:
1000019ec: a9bd57f6    	stp	x22, x21, [sp, #-0x30]!
1000019f0: a9014ff4    	stp	x20, x19, [sp, #0x10]
1000019f4: a9027bfd    	stp	x29, x30, [sp, #0x20]
1000019f8: 910083fd    	add	x29, sp, #0x20
1000019fc: aa0303f3    	mov	x19, x3
100001a00: aa0203f4    	mov	x20, x2
100001a04: aa0103f5    	mov	x21, x1
100001a08: 941f0548    	bl	0x1007c2f28 <_wasmoon_jit_context_ptr>
100001a0c: aa1503e1    	mov	x1, x21
100001a10: aa1403e2    	mov	x2, x20
100001a14: aa1303e3    	mov	x3, x19
100001a18: 52800004    	mov	w4, #0x0                ; =0
100001a1c: a9427bfd    	ldp	x29, x30, [sp, #0x20]
100001a20: a9414ff4    	ldp	x20, x19, [sp, #0x10]
100001a24: a8c357f6    	ldp	x22, x21, [sp], #0x30
100001a28: 17fffe71    	b	0x1000013ec <_exception_stage_hostcall>

0000000100001a2c <_wasmoon_jit_exception_throw_tag>:
100001a2c: a9bf7bfd    	stp	x29, x30, [sp, #-0x10]!
100001a30: 910003fd    	mov	x29, sp
100001a34: d2800002    	mov	x2, #0x0                ; =0
100001a38: 52800003    	mov	w3, #0x0                ; =0
100001a3c: 97fffeb4    	bl	0x10000150c <_exception_throw_impl>

0000000100001a40 <_wasmoon_jit_exception_throw_tag_managed>:
100001a40: a9bd57f6    	stp	x22, x21, [sp, #-0x30]!
100001a44: a9014ff4    	stp	x20, x19, [sp, #0x10]
100001a48: a9027bfd    	stp	x29, x30, [sp, #0x20]
100001a4c: 910083fd    	add	x29, sp, #0x20
100001a50: aa0103f4    	mov	x20, x1
100001a54: 941f0535    	bl	0x1007c2f28 <_wasmoon_jit_context_ptr>
100001a58: b40003e0    	cbz	x0, 0x100001ad4 <_wasmoon_jit_exception_throw_tag_managed+0x94>
100001a5c: aa0003f3    	mov	x19, x0
100001a60: 941f0087    	bl	0x1007c1c7c <_jit_hostcall_is_active>
100001a64: 34000380    	cbz	w0, 0x100001ad4 <_wasmoon_jit_exception_throw_tag_managed+0x94>
100001a68: 97ffff52    	bl	0x1000017b0 <_jit_current_trap_activation>
100001a6c: b940d008    	ldr	w8, [x0, #0xd0]
100001a70: 12800000    	mov	w0, #-0x1               ; =-1
100001a74: 37f80334    	tbnz	w20, #0x1f, 0x100001ad8 <_wasmoon_jit_exception_throw_tag_managed+0x98>
100001a78: 34000308    	cbz	w8, 0x100001ad8 <_wasmoon_jit_exception_throw_tag_managed+0x98>
100001a7c: b85f8268    	ldur	w8, [x19, #-0x8]
100001a80: 6b08029f    	cmp	w20, w8
100001a84: 540002aa    	b.ge	0x100001ad8 <_wasmoon_jit_exception_throw_tag_managed+0x98>
100001a88: f85c0268    	ldur	x8, [x19, #-0x40]
100001a8c: b8745914    	ldr	w20, [x8, w20, uxtw #2]
100001a90: 97ffff3d    	bl	0x100001784 <_get_current_jit_context>
100001a94: f85b0268    	ldur	x8, [x19, #-0x50]
100001a98: f100001f    	cmp	x0, #0x0
100001a9c: fa401904    	ccmp	x8, #0x0, #0x4, ne
100001aa0: 9a931013    	csel	x19, x0, x19, ne
100001aa4: f8528275    	ldur	x21, [x19, #-0xd8]
100001aa8: b4000175    	cbz	x21, 0x100001ad4 <_wasmoon_jit_exception_throw_tag_managed+0x94>
100001aac: f94012a0    	ldr	x0, [x21, #0x20]
100001ab0: 941fb5c6    	bl	0x1007ef1c8 <_write+0x1007ef1c8>
100001ab4: f90012bf    	str	xzr, [x21, #0x20]
100001ab8: b9002abf    	str	wzr, [x21, #0x28]
100001abc: b9001ab4    	str	w20, [x21, #0x18]
100001ac0: f9000abf    	str	xzr, [x21, #0x10]
100001ac4: f8528268    	ldur	x8, [x19, #-0xd8]
100001ac8: 52800020    	mov	w0, #0x1                ; =1
100001acc: b9000900    	str	w0, [x8, #0x8]
100001ad0: 14000002    	b	0x100001ad8 <_wasmoon_jit_exception_throw_tag_managed+0x98>
100001ad4: 12800000    	mov	w0, #-0x1               ; =-1
100001ad8: a9427bfd    	ldp	x29, x30, [sp, #0x20]
100001adc: a9414ff4    	ldp	x20, x19, [sp, #0x10]
100001ae0: a8c357f6    	ldp	x22, x21, [sp], #0x30
100001ae4: d65f03c0    	ret

0000000100001ae8 <_wasmoon_jit_exception_throw_values>:
100001ae8: a9bf7bfd    	stp	x29, x30, [sp, #-0x10]!
100001aec: 910003fd    	mov	x29, sp
100001af0: 97fffe87    	bl	0x10000150c <_exception_throw_impl>

0000000100001af4 <_wasmoon_jit_exception_throw_values_managed>:
100001af4: a9bd57f6    	stp	x22, x21, [sp, #-0x30]!
100001af8: a9014ff4    	stp	x20, x19, [sp, #0x10]
100001afc: a9027bfd    	stp	x29, x30, [sp, #0x20]
100001b00: 910083fd    	add	x29, sp, #0x20
100001b04: aa0303f3    	mov	x19, x3
100001b08: aa0203f4    	mov	x20, x2
100001b0c: aa0103f5    	mov	x21, x1
100001b10: 941f0506    	bl	0x1007c2f28 <_wasmoon_jit_context_ptr>
100001b14: aa1503e1    	mov	x1, x21
100001b18: aa1403e2    	mov	x2, x20
100001b1c: aa1303e3    	mov	x3, x19
100001b20: 52800024    	mov	w4, #0x1                ; =1
100001b24: a9427bfd    	ldp	x29, x30, [sp, #0x20]
100001b28: a9414ff4    	ldp	x20, x19, [sp, #0x10]
100001b2c: a8c357f6    	ldp	x22, x21, [sp], #0x30
100001b30: 17fffe2f    	b	0x1000013ec <_exception_stage_hostcall>

0000000100001b34 <_wasmoon_jit_exception_try_begin>:
100001b34: 17fffec1    	b	0x100001638 <_exception_try_begin_impl>

0000000100001b38 <_wasmoon_jit_exception_try_end>:
100001b38: 17fffee2    	b	0x1000016c0 <_exception_try_end_impl>

0000000100001b3c <_wasmoon_native_malloc>:
100001b3c: a9bf7bfd    	stp	x29, x30, [sp, #-0x10]!
100001b40: 910003fd    	mov	x29, sp
100001b44: aa0003e8    	mov	x8, x0
100001b48: b0004540    	adrp	x0, 0x1008aa000 <__M0IP29Milky201815aarch64__target16InternalAbiErrorPC15debug5Debug8to__reprN6constrS77258GRP29Milky201815aarch64__target16InternalAbiErrorE>
100001b4c: 911d6000    	add	x0, x0, #0x758
100001b50: f9400009    	ldr	x9, [x0]
100001b54: d63f0120    	blr	x9
100001b58: b9400009    	ldr	w9, [x0]
100001b5c: 71000529    	subs	w9, w9, #0x1
100001b60: 5400006b    	b.lt	0x100001b6c <_wasmoon_native_malloc+0x30>
100001b64: b9000009    	str	w9, [x0]
100001b68: 54000080    	b.eq	0x100001b78 <_wasmoon_native_malloc+0x3c>
100001b6c: aa0803e0    	mov	x0, x8
100001b70: a8c17bfd    	ldp	x29, x30, [sp], #0x10
100001b74: 141fb607    	b	0x1007ef390 <_write+0x1007ef390>
100001b78: d2800000    	mov	x0, #0x0                ; =0
100001b7c: a8c17bfd    	ldp	x29, x30, [sp], #0x10
100001b80: d65f03c0    	ret

0000000100001b84 <_wasmoon_native_realloc>:
100001b84: a9bf7bfd    	stp	x29, x30, [sp, #-0x10]!
100001b88: 910003fd    	mov	x29, sp
100001b8c: aa0003e8    	mov	x8, x0
100001b90: b0004540    	adrp	x0, 0x1008aa000 <__M0IP29Milky201815aarch64__target16InternalAbiErrorPC15debug5Debug8to__reprN6constrS77258GRP29Milky201815aarch64__target16InternalAbiErrorE>
100001b94: 911d6000    	add	x0, x0, #0x758
100001b98: f9400009    	ldr	x9, [x0]
100001b9c: d63f0120    	blr	x9
100001ba0: b9400009    	ldr	w9, [x0]
100001ba4: 71000529    	subs	w9, w9, #0x1
100001ba8: 5400006b    	b.lt	0x100001bb4 <_wasmoon_native_realloc+0x30>
100001bac: b9000009    	str	w9, [x0]
100001bb0: 54000080    	b.eq	0x100001bc0 <_wasmoon_native_realloc+0x3c>
100001bb4: aa0803e0    	mov	x0, x8
100001bb8: a8c17bfd    	ldp	x29, x30, [sp], #0x10
100001bbc: 141fb6bb    	b	0x1007ef6a8 <_write+0x1007ef6a8>
100001bc0: d2800000    	mov	x0, #0x0                ; =0
100001bc4: a8c17bfd    	ldp	x29, x30, [sp], #0x10
100001bc8: d65f03c0    	ret
