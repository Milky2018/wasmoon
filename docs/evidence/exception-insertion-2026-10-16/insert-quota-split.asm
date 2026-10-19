
target/exception-insert/quota-split:	file format mach-o arm64

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
10040d6d0: 37f80dc3    	tbnz	w3, #0x1f, 0x10040d888 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x1d8>
10040d6d4: b9403668    	ldr	w8, [x19, #0x34]
10040d6d8: 35000d88    	cbnz	w8, 0x10040d888 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x1d8>
10040d6dc: b9403268    	ldr	w8, [x19, #0x30]
10040d6e0: 12b00009    	mov	w9, #0x7fffffff         ; =2147483647
10040d6e4: 6b09011f    	cmp	w8, w9
10040d6e8: 54000d00    	b.eq	0x10040d888 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x1d8>
10040d6ec: aa0303f5    	mov	x21, x3
10040d6f0: b9402268    	ldr	w8, [x19, #0x20]
10040d6f4: 6b02011f    	cmp	w8, w2
10040d6f8: 540000c0    	b.eq	0x10040d710 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x60>
10040d6fc: aa1303e0    	mov	x0, x19
10040d700: aa0103f4    	mov	x20, x1
10040d704: aa0203e1    	mov	x1, x2
10040d708: 94000202    	bl	0x10040df10 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState13cache__layout>
10040d70c: aa1403e1    	mov	x1, x20
10040d710: f9401674    	ldr	x20, [x19, #0x28]
10040d714: b4000154    	cbz	x20, 0x10040d73c <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x8c>
10040d718: b85fc288    	ldur	w8, [x20, #-0x4]
10040d71c: 6b15011f    	cmp	w8, w21
10040d720: 54000981    	b.ne	0x10040d850 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x1a0>
10040d724: b85f8288    	ldur	w8, [x20, #-0x8]
10040d728: 7100811f    	cmp	w8, #0x20
10040d72c: 540000eb    	b.lt	0x10040d748 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x98>
10040d730: 11008108    	add	w8, w8, #0x20
10040d734: b81f8288    	stur	w8, [x20, #-0x8]
10040d738: 14000004    	b	0x10040d748 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x98>
10040d73c: f00023a8    	adrp	x8, 0x100884000 <__M0MP59Milky201812wasm__milkir8frontend2ir10translator10Translator22translate__instructionC227646l169$closure+0x988>
10040d740: 912ea108    	add	x8, x8, #0xba8
10040d744: f9400114    	ldr	x20, [x8]
10040d748: d37c7ea8    	ubfiz	x8, x21, #4, #32
10040d74c: 91004115    	add	x21, x8, #0x10
10040d750: b9403e68    	ldr	w8, [x19, #0x3c]
10040d754: 34000188    	cbz	w8, 0x10040d784 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0xd4>
10040d758: aa0103f6    	mov	x22, x1
10040d75c: aa1303e0    	mov	x0, x19
10040d760: aa1503e1    	mov	x1, x21
10040d764: 94000242    	bl	0x10040e06c <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState16acquire__payload>
10040d768: 34000780    	cbz	w0, 0x10040d858 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x1a8>
10040d76c: b9403e68    	ldr	w8, [x19, #0x3c]
10040d770: 7100011f    	cmp	w8, #0x0
10040d774: 1a9f07e5    	cset	w5, ne
10040d778: 9a9f12a4    	csel	x4, x21, xzr, ne
10040d77c: aa1603e1    	mov	x1, x22
10040d780: 14000003    	b	0x10040d78c <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0xdc>
10040d784: d2800005    	mov	x5, #0x0                ; =0
10040d788: d2800004    	mov	x4, #0x0                ; =0
10040d78c: b9803268    	ldrsw	x8, [x19, #0x30]
10040d790: d2800029    	mov	x9, #0x1                ; =1
10040d794: f2e20009    	movk	x9, #0x1000, lsl #48
10040d798: aa080528    	orr	x8, x9, x8, lsl #1
10040d79c: b9403a63    	ldr	w3, [x19, #0x38]
10040d7a0: aa0103e0    	mov	x0, x1
10040d7a4: aa0803f6    	mov	x22, x8
10040d7a8: aa0803e1    	mov	x1, x8
10040d7ac: aa1403e2    	mov	x2, x20
10040d7b0: 940f12ee    	bl	0x1007d2368 <_wasmoon_exception_storage_append>
10040d7b4: b85f8288    	ldur	w8, [x20, #-0x8]
10040d7b8: 7101011f    	cmp	w8, #0x40
10040d7bc: 5400008b    	b.lt	0x10040d7cc <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x11c>
10040d7c0: 51008108    	sub	w8, w8, #0x20
10040d7c4: b81f8288    	stur	w8, [x20, #-0x8]
10040d7c8: 14000007    	b	0x10040d7e4 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x134>
10040d7cc: 7100811f    	cmp	w8, #0x20
10040d7d0: 540000ab    	b.lt	0x10040d7e4 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x134>
10040d7d4: aa0003f7    	mov	x23, x0
10040d7d8: aa1403e0    	mov	x0, x20
10040d7dc: 940f4b6b    	bl	0x1007e0588 <_moonbit_drop_object>
10040d7e0: aa1703e0    	mov	x0, x23
10040d7e4: 340002c0    	cbz	w0, 0x10040d83c <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x18c>
10040d7e8: f9400274    	ldr	x20, [x19]
10040d7ec: b9400a88    	ldr	w8, [x20, #0x8]
10040d7f0: f9400289    	ldr	x9, [x20]
10040d7f4: b85fc12a    	ldur	w10, [x9, #-0x4]
10040d7f8: 6b0a011f    	cmp	w8, w10
10040d7fc: 540000c1    	b.ne	0x10040d814 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x164>
10040d800: 11000501    	add	w1, w8, #0x1
10040d804: aa1403e0    	mov	x0, x20
10040d808: 940c98dc    	bl	0x100733b78 <__M0MPC15array5Array7reallocGRP39Milky201812wasmoon__jit8jit__ffi14ExceptionEntryE>
10040d80c: b9400a88    	ldr	w8, [x20, #0x8]
10040d810: f9400289    	ldr	x9, [x20]
10040d814: aa1603e0    	mov	x0, x22
10040d818: 8b28d129    	add	x9, x9, w8, sxtw #4
10040d81c: 5280002a    	mov	w10, #0x1               ; =1
10040d820: a9002936    	stp	x22, x10, [x9]
10040d824: 11000508    	add	w8, w8, #0x1
10040d828: b9000a88    	str	w8, [x20, #0x8]
10040d82c: b9403268    	ldr	w8, [x19, #0x30]
10040d830: 11000508    	add	w8, w8, #0x1
10040d834: b9003268    	str	w8, [x19, #0x30]
10040d838: 14000014    	b	0x10040d888 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x1d8>
10040d83c: b9403e68    	ldr	w8, [x19, #0x3c]
10040d840: 34000088    	cbz	w8, 0x10040d850 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x1a0>
10040d844: aa1303e0    	mov	x0, x19
10040d848: aa1503e1    	mov	x1, x21
10040d84c: 94000281    	bl	0x10040e250 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState16release__payload>
10040d850: 92800100    	mov	x0, #-0x9               ; =-9
10040d854: 1400000d    	b	0x10040d888 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x1d8>
10040d858: b85f8288    	ldur	w8, [x20, #-0x8]
10040d85c: 7101011f    	cmp	w8, #0x40
10040d860: 5400008b    	b.lt	0x10040d870 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x1c0>
10040d864: 51008108    	sub	w8, w8, #0x20
10040d868: b81f8288    	stur	w8, [x20, #-0x8]
10040d86c: 14000005    	b	0x10040d880 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x1d0>
10040d870: 7100811f    	cmp	w8, #0x20
10040d874: 5400006b    	b.lt	0x10040d880 <__M0MP39Milky201812wasmoon__jit8jit__ffi14ExceptionState6insert+0x1d0>
10040d878: aa1403e0    	mov	x0, x20
10040d87c: 940f4b43    	bl	0x1007e0588 <_moonbit_drop_object>
10040d880: b9805268    	ldrsw	x8, [x19, #0x50]
10040d884: cb0803e0    	neg	x0, x8
10040d888: a9437bfd    	ldp	x29, x30, [sp, #0x30]
10040d88c: a9424ff4    	ldp	x20, x19, [sp, #0x20]
10040d890: a94157f6    	ldp	x22, x21, [sp, #0x10]
10040d894: a8c45ff8    	ldp	x24, x23, [sp], #0x40
10040d898: d65f03c0    	ret
