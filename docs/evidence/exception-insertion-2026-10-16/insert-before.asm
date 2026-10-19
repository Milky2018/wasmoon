
wasmoon:	file format mach-o arm64

Disassembly of section __TEXT,__text:

000000010040d6b0 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert>:
10040d6b0: a9bc5ff8    	stp	x24, x23, [sp, #-0x40]!
10040d6b4: a90157f6    	stp	x22, x21, [sp, #0x10]
10040d6b8: a9024ff4    	stp	x20, x19, [sp, #0x20]
10040d6bc: a9037bfd    	stp	x29, x30, [sp, #0x30]
10040d6c0: 9100c3fd    	add	x29, sp, #0x30
10040d6c4: aa0003f3    	mov	x19, x0
10040d6c8: b900501f    	str	wzr, [x0, #0x50]
10040d6cc: 92800100    	mov	x0, #-0x9               ; =-9
10040d6d0: 37f81c03    	tbnz	w3, #0x1f, 0x10040da50 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x3a0>
10040d6d4: b9403668    	ldr	w8, [x19, #0x34]
10040d6d8: 35001bc8    	cbnz	w8, 0x10040da50 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x3a0>
10040d6dc: b9403268    	ldr	w8, [x19, #0x30]
10040d6e0: 12b00009    	mov	w9, #0x7fffffff         ; =2147483647
10040d6e4: 6b09011f    	cmp	w8, w9
10040d6e8: 54001b40    	b.eq	0x10040da50 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x3a0>
10040d6ec: aa0303f4    	mov	x20, x3
10040d6f0: b9402268    	ldr	w8, [x19, #0x20]
10040d6f4: 6b02011f    	cmp	w8, w2
10040d6f8: 540000c0    	b.eq	0x10040d710 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x60>
10040d6fc: aa1303e0    	mov	x0, x19
10040d700: aa0103f5    	mov	x21, x1
10040d704: aa0203e1    	mov	x1, x2
10040d708: 94000294    	bl	0x10040e158 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState13cache__layout>
10040d70c: aa1503e1    	mov	x1, x21
10040d710: f9401675    	ldr	x21, [x19, #0x28]
10040d714: b4000155    	cbz	x21, 0x10040d73c <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x8c>
10040d718: b85fc2a8    	ldur	w8, [x21, #-0x4]
10040d71c: 6b14011f    	cmp	w8, w20
10040d720: 54001961    	b.ne	0x10040da4c <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x39c>
10040d724: b85f82a8    	ldur	w8, [x21, #-0x8]
10040d728: 7100811f    	cmp	w8, #0x20
10040d72c: 540000eb    	b.lt	0x10040d748 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x98>
10040d730: 11008108    	add	w8, w8, #0x20
10040d734: b81f82a8    	stur	w8, [x21, #-0x8]
10040d738: 14000004    	b	0x10040d748 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x98>
10040d73c: f00023a8    	adrp	x8, 0x100884000 <__M0MP59Milky201812wasm__milkir8frontend2ir10translator10Translator22translate__instructionC227705l90$closure+0x988>
10040d740: 912ea108    	add	x8, x8, #0xba8
10040d744: f9400115    	ldr	x21, [x8]
10040d748: d37c7e88    	ubfiz	x8, x20, #4, #32
10040d74c: 91004114    	add	x20, x8, #0x10
10040d750: b9403e68    	ldr	w8, [x19, #0x3c]
10040d754: 34000728    	cbz	w8, 0x10040d838 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x188>
10040d758: f9402276    	ldr	x22, [x19, #0x40]
10040d75c: b4000216    	cbz	x22, 0x10040d79c <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0xec>
10040d760: aa0103f7    	mov	x23, x1
10040d764: b85f82c8    	ldur	w8, [x22, #-0x8]
10040d768: 7100811f    	cmp	w8, #0x20
10040d76c: 5400006b    	b.lt	0x10040d778 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0xc8>
10040d770: 11008108    	add	w8, w8, #0x20
10040d774: b81f82c8    	stur	w8, [x22, #-0x8]
10040d778: aa1603e0    	mov	x0, x22
10040d77c: aa1403e1    	mov	x1, x20
10040d780: 940eea4a    	bl	0x1007c80a8 <_wasmoon_quota_acquire>
10040d784: b85f82c8    	ldur	w8, [x22, #-0x8]
10040d788: 7101011f    	cmp	w8, #0x40
10040d78c: 5400020b    	b.lt	0x10040d7cc <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x11c>
10040d790: 51008108    	sub	w8, w8, #0x20
10040d794: b81f82c8    	stur	w8, [x22, #-0x8]
10040d798: 14000013    	b	0x10040d7e4 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x134>
10040d79c: d2800000    	mov	x0, #0x0                ; =0
10040d7a0: aa0103f6    	mov	x22, x1
10040d7a4: aa1403e1    	mov	x1, x20
10040d7a8: 940eea40    	bl	0x1007c80a8 <_wasmoon_quota_acquire>
10040d7ac: aa1603e1    	mov	x1, x22
10040d7b0: 350001e0    	cbnz	w0, 0x10040d7ec <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x13c>
10040d7b4: b85f82a8    	ldur	w8, [x21, #-0x8]
10040d7b8: 7101011f    	cmp	w8, #0x40
10040d7bc: 5400044b    	b.lt	0x10040d844 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x194>
10040d7c0: 51008108    	sub	w8, w8, #0x20
10040d7c4: b81f82a8    	stur	w8, [x21, #-0x8]
10040d7c8: 14000023    	b	0x10040d854 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x1a4>
10040d7cc: 7100811f    	cmp	w8, #0x20
10040d7d0: 540000ab    	b.lt	0x10040d7e4 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x134>
10040d7d4: aa0003f8    	mov	x24, x0
10040d7d8: aa1603e0    	mov	x0, x22
10040d7dc: 940f4b68    	bl	0x1007e057c <_moonbit_drop_object>
10040d7e0: aa1803e0    	mov	x0, x24
10040d7e4: aa1703e1    	mov	x1, x23
10040d7e8: 34fffe60    	cbz	w0, 0x10040d7b4 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x104>
10040d7ec: b9403e68    	ldr	w8, [x19, #0x3c]
10040d7f0: 34000248    	cbz	w8, 0x10040d838 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x188>
10040d7f4: f9402676    	ldr	x22, [x19, #0x48]
10040d7f8: b4000376    	cbz	x22, 0x10040d864 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x1b4>
10040d7fc: aa0103f7    	mov	x23, x1
10040d800: b85f82c8    	ldur	w8, [x22, #-0x8]
10040d804: 7100811f    	cmp	w8, #0x20
10040d808: 5400006b    	b.lt	0x10040d814 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x164>
10040d80c: 11008108    	add	w8, w8, #0x20
10040d810: b81f82c8    	stur	w8, [x22, #-0x8]
10040d814: aa1603e0    	mov	x0, x22
10040d818: 52800021    	mov	w1, #0x1                ; =1
10040d81c: 940eea23    	bl	0x1007c80a8 <_wasmoon_quota_acquire>
10040d820: b85f82c8    	ldur	w8, [x22, #-0x8]
10040d824: 7101011f    	cmp	w8, #0x40
10040d828: 540002ab    	b.lt	0x10040d87c <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x1cc>
10040d82c: 51008108    	sub	w8, w8, #0x20
10040d830: b81f82c8    	stur	w8, [x22, #-0x8]
10040d834: 14000018    	b	0x10040d894 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x1e4>
10040d838: d2800005    	mov	x5, #0x0                ; =0
10040d83c: d2800004    	mov	x4, #0x0                ; =0
10040d840: 1400001b    	b	0x10040d8ac <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x1fc>
10040d844: 7100811f    	cmp	w8, #0x20
10040d848: 5400006b    	b.lt	0x10040d854 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x1a4>
10040d84c: aa1503e0    	mov	x0, x21
10040d850: 940f4b4b    	bl	0x1007e057c <_moonbit_drop_object>
10040d854: 52800328    	mov	w8, #0x19               ; =25
10040d858: b9005268    	str	w8, [x19, #0x50]
10040d85c: 92800300    	mov	x0, #-0x19              ; =-25
10040d860: 1400007c    	b	0x10040da50 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x3a0>
10040d864: d2800000    	mov	x0, #0x0                ; =0
10040d868: aa0103f6    	mov	x22, x1
10040d86c: 52800021    	mov	w1, #0x1                ; =1
10040d870: 940eea0e    	bl	0x1007c80a8 <_wasmoon_quota_acquire>
10040d874: aa1603e1    	mov	x1, x22
10040d878: 14000008    	b	0x10040d898 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x1e8>
10040d87c: 7100811f    	cmp	w8, #0x20
10040d880: 540000ab    	b.lt	0x10040d894 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x1e4>
10040d884: aa0003f8    	mov	x24, x0
10040d888: aa1603e0    	mov	x0, x22
10040d88c: 940f4b3c    	bl	0x1007e057c <_moonbit_drop_object>
10040d890: aa1803e0    	mov	x0, x24
10040d894: aa1703e1    	mov	x1, x23
10040d898: 34000860    	cbz	w0, 0x10040d9a4 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x2f4>
10040d89c: b9403e68    	ldr	w8, [x19, #0x3c]
10040d8a0: 7100011f    	cmp	w8, #0x0
10040d8a4: 1a9f07e5    	cset	w5, ne
10040d8a8: 9a9f1284    	csel	x4, x20, xzr, ne
10040d8ac: b9803268    	ldrsw	x8, [x19, #0x30]
10040d8b0: d2800029    	mov	x9, #0x1                ; =1
10040d8b4: f2e20009    	movk	x9, #0x1000, lsl #48
10040d8b8: aa080528    	orr	x8, x9, x8, lsl #1
10040d8bc: b9403a63    	ldr	w3, [x19, #0x38]
10040d8c0: aa0103e0    	mov	x0, x1
10040d8c4: aa0803f6    	mov	x22, x8
10040d8c8: aa0803e1    	mov	x1, x8
10040d8cc: aa1503e2    	mov	x2, x21
10040d8d0: 940f12a3    	bl	0x1007d235c <_wasmoon_exception_storage_append>
10040d8d4: b85f82a8    	ldur	w8, [x21, #-0x8]
10040d8d8: 7101011f    	cmp	w8, #0x40
10040d8dc: 5400008b    	b.lt	0x10040d8ec <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x23c>
10040d8e0: 51008108    	sub	w8, w8, #0x20
10040d8e4: b81f82a8    	stur	w8, [x21, #-0x8]
10040d8e8: 14000007    	b	0x10040d904 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x254>
10040d8ec: 7100811f    	cmp	w8, #0x20
10040d8f0: 540000ab    	b.lt	0x10040d904 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x254>
10040d8f4: aa0003f7    	mov	x23, x0
10040d8f8: aa1503e0    	mov	x0, x21
10040d8fc: 940f4b20    	bl	0x1007e057c <_moonbit_drop_object>
10040d900: aa1703e0    	mov	x0, x23
10040d904: 340002c0    	cbz	w0, 0x10040d95c <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x2ac>
10040d908: f9400274    	ldr	x20, [x19]
10040d90c: b9400a88    	ldr	w8, [x20, #0x8]
10040d910: f9400289    	ldr	x9, [x20]
10040d914: b85fc12a    	ldur	w10, [x9, #-0x4]
10040d918: 6b0a011f    	cmp	w8, w10
10040d91c: 540000c1    	b.ne	0x10040d934 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x284>
10040d920: 11000501    	add	w1, w8, #0x1
10040d924: aa1403e0    	mov	x0, x20
10040d928: 940c9891    	bl	0x100733b6c <__M0MPC15array5Array7reallocGRP39Milky201812wasmoon__jit8jit__ffi14ExceptionEntryE>
10040d92c: b9400a88    	ldr	w8, [x20, #0x8]
10040d930: f9400289    	ldr	x9, [x20]
10040d934: aa1603e0    	mov	x0, x22
10040d938: 8b28d129    	add	x9, x9, w8, sxtw #4
10040d93c: 5280002a    	mov	w10, #0x1               ; =1
10040d940: a9002936    	stp	x22, x10, [x9]
10040d944: 11000508    	add	w8, w8, #0x1
10040d948: b9000a88    	str	w8, [x20, #0x8]
10040d94c: b9403268    	ldr	w8, [x19, #0x30]
10040d950: 11000508    	add	w8, w8, #0x1
10040d954: b9003268    	str	w8, [x19, #0x30]
10040d958: 1400003e    	b	0x10040da50 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x3a0>
10040d95c: b9403e68    	ldr	w8, [x19, #0x3c]
10040d960: 34000768    	cbz	w8, 0x10040da4c <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x39c>
10040d964: f9402275    	ldr	x21, [x19, #0x40]
10040d968: b40002b5    	cbz	x21, 0x10040d9bc <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x30c>
10040d96c: b85f82a8    	ldur	w8, [x21, #-0x8]
10040d970: 7100811f    	cmp	w8, #0x20
10040d974: 5400006b    	b.lt	0x10040d980 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x2d0>
10040d978: 11008108    	add	w8, w8, #0x20
10040d97c: b81f82a8    	stur	w8, [x21, #-0x8]
10040d980: aa1503e0    	mov	x0, x21
10040d984: aa1403e1    	mov	x1, x20
10040d988: 940ee9dd    	bl	0x1007c80fc <_wasmoon_quota_release>
10040d98c: b85f82a8    	ldur	w8, [x21, #-0x8]
10040d990: 7101011f    	cmp	w8, #0x40
10040d994: 540001cb    	b.lt	0x10040d9cc <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x31c>
10040d998: 51008108    	sub	w8, w8, #0x20
10040d99c: b81f82a8    	stur	w8, [x21, #-0x8]
10040d9a0: 1400000f    	b	0x10040d9dc <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x32c>
10040d9a4: b85f82a8    	ldur	w8, [x21, #-0x8]
10040d9a8: 7101011f    	cmp	w8, #0x40
10040d9ac: 540005cb    	b.lt	0x10040da64 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x3b4>
10040d9b0: 51008108    	sub	w8, w8, #0x20
10040d9b4: b81f82a8    	stur	w8, [x21, #-0x8]
10040d9b8: 1400002f    	b	0x10040da74 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x3c4>
10040d9bc: d2800000    	mov	x0, #0x0                ; =0
10040d9c0: aa1403e1    	mov	x1, x20
10040d9c4: 940ee9ce    	bl	0x1007c80fc <_wasmoon_quota_release>
10040d9c8: 14000005    	b	0x10040d9dc <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x32c>
10040d9cc: 7100811f    	cmp	w8, #0x20
10040d9d0: 5400006b    	b.lt	0x10040d9dc <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x32c>
10040d9d4: aa1503e0    	mov	x0, x21
10040d9d8: 940f4ae9    	bl	0x1007e057c <_moonbit_drop_object>
10040d9dc: f9402673    	ldr	x19, [x19, #0x48]
10040d9e0: b4000213    	cbz	x19, 0x10040da20 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x370>
10040d9e4: b85f8268    	ldur	w8, [x19, #-0x8]
10040d9e8: 7100811f    	cmp	w8, #0x20
10040d9ec: 5400006b    	b.lt	0x10040d9f8 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x348>
10040d9f0: 11008108    	add	w8, w8, #0x20
10040d9f4: b81f8268    	stur	w8, [x19, #-0x8]
10040d9f8: aa1303e0    	mov	x0, x19
10040d9fc: 52800021    	mov	w1, #0x1                ; =1
10040da00: 940ee9bf    	bl	0x1007c80fc <_wasmoon_quota_release>
10040da04: b85f8268    	ldur	w8, [x19, #-0x8]
10040da08: 7101011f    	cmp	w8, #0x40
10040da0c: 5400014b    	b.lt	0x10040da34 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x384>
10040da10: 51008108    	sub	w8, w8, #0x20
10040da14: b81f8268    	stur	w8, [x19, #-0x8]
10040da18: 92800100    	mov	x0, #-0x9               ; =-9
10040da1c: 1400000d    	b	0x10040da50 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x3a0>
10040da20: d2800000    	mov	x0, #0x0                ; =0
10040da24: 52800021    	mov	w1, #0x1                ; =1
10040da28: 940ee9b5    	bl	0x1007c80fc <_wasmoon_quota_release>
10040da2c: 92800100    	mov	x0, #-0x9               ; =-9
10040da30: 14000008    	b	0x10040da50 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x3a0>
10040da34: 7100811f    	cmp	w8, #0x20
10040da38: 540000ab    	b.lt	0x10040da4c <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x39c>
10040da3c: aa1303e0    	mov	x0, x19
10040da40: 940f4acf    	bl	0x1007e057c <_moonbit_drop_object>
10040da44: 92800100    	mov	x0, #-0x9               ; =-9
10040da48: 14000002    	b	0x10040da50 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x3a0>
10040da4c: 92800100    	mov	x0, #-0x9               ; =-9
10040da50: a9437bfd    	ldp	x29, x30, [sp, #0x30]
10040da54: a9424ff4    	ldp	x20, x19, [sp, #0x20]
10040da58: a94157f6    	ldp	x22, x21, [sp, #0x10]
10040da5c: a8c45ff8    	ldp	x24, x23, [sp], #0x40
10040da60: d65f03c0    	ret
10040da64: 7100811f    	cmp	w8, #0x20
10040da68: 5400006b    	b.lt	0x10040da74 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x3c4>
10040da6c: aa1503e0    	mov	x0, x21
10040da70: 940f4ac3    	bl	0x1007e057c <_moonbit_drop_object>
10040da74: f9402275    	ldr	x21, [x19, #0x40]
10040da78: b40001f5    	cbz	x21, 0x10040dab4 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x404>
10040da7c: b85f82a8    	ldur	w8, [x21, #-0x8]
10040da80: 7100811f    	cmp	w8, #0x20
10040da84: 5400006b    	b.lt	0x10040da90 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x3e0>
10040da88: 11008108    	add	w8, w8, #0x20
10040da8c: b81f82a8    	stur	w8, [x21, #-0x8]
10040da90: aa1503e0    	mov	x0, x21
10040da94: aa1403e1    	mov	x1, x20
10040da98: 940ee999    	bl	0x1007c80fc <_wasmoon_quota_release>
10040da9c: b85f82a8    	ldur	w8, [x21, #-0x8]
10040daa0: 7101011f    	cmp	w8, #0x40
10040daa4: 5400010b    	b.lt	0x10040dac4 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x414>
10040daa8: 51008108    	sub	w8, w8, #0x20
10040daac: b81f82a8    	stur	w8, [x21, #-0x8]
10040dab0: 14000009    	b	0x10040dad4 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x424>
10040dab4: d2800000    	mov	x0, #0x0                ; =0
10040dab8: aa1403e1    	mov	x1, x20
10040dabc: 940ee990    	bl	0x1007c80fc <_wasmoon_quota_release>
10040dac0: 14000005    	b	0x10040dad4 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x424>
10040dac4: 7100811f    	cmp	w8, #0x20
10040dac8: 5400006b    	b.lt	0x10040dad4 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x424>
10040dacc: aa1503e0    	mov	x0, x21
10040dad0: 940f4aab    	bl	0x1007e057c <_moonbit_drop_object>
10040dad4: 52800348    	mov	w8, #0x1a               ; =26
10040dad8: b9005268    	str	w8, [x19, #0x50]
10040dadc: 92800320    	mov	x0, #-0x1a              ; =-26
10040dae0: 17ffffdc    	b	0x10040da50 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x3a0>
