
target/exception-rootcause/same-site-control:	file format mach-o arm64

Disassembly of section __TEXT,__text:

00000001007bc0c4 <_wasmoon_exception_storage_append>:
1007bc0c4: d10283ff    	sub	sp, sp, #0xa0
1007bc0c8: a9046ffc    	stp	x28, x27, [sp, #0x40]
1007bc0cc: a90567fa    	stp	x26, x25, [sp, #0x50]
1007bc0d0: a9065ff8    	stp	x24, x23, [sp, #0x60]
1007bc0d4: a90757f6    	stp	x22, x21, [sp, #0x70]
1007bc0d8: a9084ff4    	stp	x20, x19, [sp, #0x80]
1007bc0dc: a9097bfd    	stp	x29, x30, [sp, #0x90]
1007bc0e0: 910243fd    	add	x29, sp, #0x90
1007bc0e4: b940141b    	ldr	w27, [x0, #0x14]
1007bc0e8: 37f80d5b    	tbnz	w27, #0x1f, 0x1007bc290 <_wasmoon_exception_storage_append+0x1cc>
1007bc0ec: aa0503f3    	mov	x19, x5
1007bc0f0: aa0403f4    	mov	x20, x4
1007bc0f4: aa0303f7    	mov	x23, x3
1007bc0f8: aa0203f8    	mov	x24, x2
1007bc0fc: aa0103f6    	mov	x22, x1
1007bc100: aa0003f5    	mov	x21, x0
1007bc104: f9400008    	ldr	x8, [x0]
1007bc108: f940051a    	ldr	x26, [x8, #0x8]
1007bc10c: 29412748    	ldp	w8, w9, [x26, #0x8]
1007bc110: 93407d08    	sxtw	x8, w8
1007bc114: 6b09011f    	cmp	w8, w9
1007bc118: 540001c1    	b.ne	0x1007bc150 <_wasmoon_exception_storage_append+0x8c>
1007bc11c: d37ff909    	lsl	x9, x8, #1
1007bc120: 7100011f    	cmp	w8, #0x0
1007bc124: 52800208    	mov	w8, #0x10               ; =16
1007bc128: 9a890119    	csel	x25, x8, x9, eq
1007bc12c: d35fff28    	lsr	x8, x25, #31
1007bc130: b5000b08    	cbnz	x8, 0x1007bc290 <_wasmoon_exception_storage_append+0x1cc>
1007bc134: f9400340    	ldr	x0, [x26]
1007bc138: 8b190b28    	add	x8, x25, x25, lsl #2
1007bc13c: d37df101    	lsl	x1, x8, #3
1007bc140: 9400370e    	bl	0x1007c9d78 <_wasmoon_native_realloc>
1007bc144: b4000a80    	cbz	x0, 0x1007bc294 <_wasmoon_exception_storage_append+0x1d0>
1007bc148: f9000340    	str	x0, [x26]
1007bc14c: b9000f59    	str	w25, [x26, #0xc]
1007bc150: 6f00e400    	movi.2d	v0, #0000000000000000
1007bc154: ad0083e0    	stp	q0, q0, [sp, #0x10]
1007bc158: 3400013b    	cbz	w27, 0x1007bc17c <_wasmoon_exception_storage_append+0xb8>
1007bc15c: d37df379    	lsl	x25, x27, #3
1007bc160: aa1903e0    	mov	x0, x25
1007bc164: 940036e1    	bl	0x1007c9ce8 <_wasmoon_native_malloc>
1007bc168: f9000be0    	str	x0, [sp, #0x10]
1007bc16c: b4000940    	cbz	x0, 0x1007bc294 <_wasmoon_exception_storage_append+0x1d0>
1007bc170: f9400ea1    	ldr	x1, [x21, #0x18]
1007bc174: aa1903e2    	mov	x2, x25
1007bc178: 9400c99b    	bl	0x1007ee7e4 <_write+0x1007ee7e4>
1007bc17c: b94012a8    	ldr	w8, [x21, #0x10]
1007bc180: 29066fe8    	stp	w8, w27, [sp, #0x30]
1007bc184: f94006a0    	ldr	x0, [x21, #0x8]
1007bc188: b4000460    	cbz	x0, 0x1007bc214 <_wasmoon_exception_storage_append+0x150>
1007bc18c: 2a170368    	orr	w8, w27, w23
1007bc190: 34000428    	cbz	w8, 0x1007bc214 <_wasmoon_exception_storage_append+0x150>
1007bc194: f90007ff    	str	xzr, [sp, #0x8]
1007bc198: 7100077f    	cmp	w27, #0x1
1007bc19c: 1a9f8779    	csinc	w25, w27, wzr, hi
1007bc1a0: 910043e8    	add	x8, sp, #0x10
1007bc1a4: b27d0102    	orr	x2, x8, #0x8
1007bc1a8: 910023e3    	add	x3, sp, #0x8
1007bc1ac: aa1903e1    	mov	x1, x25
1007bc1b0: 94004f2b    	bl	0x1007cfe5c <_gc_heap_register_parked_roots>
1007bc1b4: 34000540    	cbz	w0, 0x1007bc25c <_wasmoon_exception_storage_append+0x198>
1007bc1b8: d2800008    	mov	x8, #0x0                ; =0
1007bc1bc: b85fc309    	ldur	w9, [x24, #-0x4]
1007bc1c0: 14000007    	b	0x1007bc1dc <_wasmoon_exception_storage_append+0x118>
1007bc1c4: d280000a    	mov	x10, #0x0               ; =0
1007bc1c8: f94007eb    	ldr	x11, [sp, #0x8]
1007bc1cc: f828796a    	str	x10, [x11, x8, lsl #3]
1007bc1d0: 91000508    	add	x8, x8, #0x1
1007bc1d4: eb08033f    	cmp	x25, x8
1007bc1d8: 54000120    	b.eq	0x1007bc1fc <_wasmoon_exception_storage_append+0x138>
1007bc1dc: eb1b011f    	cmp	x8, x27
1007bc1e0: 54ffff22    	b.hs	0x1007bc1c4 <_wasmoon_exception_storage_append+0x100>
1007bc1e4: 34000069    	cbz	w9, 0x1007bc1f0 <_wasmoon_exception_storage_append+0x12c>
1007bc1e8: b8687b0a    	ldr	w10, [x24, x8, lsl #2]
1007bc1ec: 34fffeca    	cbz	w10, 0x1007bc1c4 <_wasmoon_exception_storage_append+0x100>
1007bc1f0: f9400bea    	ldr	x10, [sp, #0x10]
1007bc1f4: f868794a    	ldr	x10, [x10, x8, lsl #3]
1007bc1f8: 17fffff4    	b	0x1007bc1c8 <_wasmoon_exception_storage_append+0x104>
1007bc1fc: 340000d7    	cbz	w23, 0x1007bc214 <_wasmoon_exception_storage_append+0x150>
1007bc200: f9400fe0    	ldr	x0, [sp, #0x18]
1007bc204: f94002a1    	ldr	x1, [x21]
1007bc208: aa1603e2    	mov	x2, x22
1007bc20c: 94004f6b    	bl	0x1007cffb8 <_gc_heap_bind_exception_roots>
1007bc210: 34000260    	cbz	w0, 0x1007bc25c <_wasmoon_exception_storage_append+0x198>
1007bc214: aa140268    	orr	x8, x19, x20
1007bc218: b5000088    	cbnz	x8, 0x1007bc228 <_wasmoon_exception_storage_append+0x164>
1007bc21c: f94002a8    	ldr	x8, [x21]
1007bc220: b9401908    	ldr	w8, [x8, #0x18]
1007bc224: 35000048    	cbnz	w8, 0x1007bc22c <_wasmoon_exception_storage_append+0x168>
1007bc228: a9024ff4    	stp	x20, x19, [sp, #0x20]
1007bc22c: f9400348    	ldr	x8, [x26]
1007bc230: b9800b49    	ldrsw	x9, [x26, #0x8]
1007bc234: 1100052a    	add	w10, w9, #0x1
1007bc238: b9000b4a    	str	w10, [x26, #0x8]
1007bc23c: 5280050a    	mov	w10, #0x28              ; =40
1007bc240: 9b2a2128    	smaddl	x8, w9, w10, x8
1007bc244: ad4087e0    	ldp	q0, q1, [sp, #0x10]
1007bc248: f9401be9    	ldr	x9, [sp, #0x30]
1007bc24c: f9001109    	str	x9, [x8, #0x20]
1007bc250: ad000500    	stp	q0, q1, [x8]
1007bc254: 52800020    	mov	w0, #0x1                ; =1
1007bc258: 1400000f    	b	0x1007bc294 <_wasmoon_exception_storage_append+0x1d0>
1007bc25c: b94037e8    	ldr	w8, [sp, #0x34]
1007bc260: 37f80188    	tbnz	w8, #0x1f, 0x1007bc290 <_wasmoon_exception_storage_append+0x1cc>
1007bc264: f9400fe0    	ldr	x0, [sp, #0x18]
1007bc268: b4000040    	cbz	x0, 0x1007bc270 <_wasmoon_exception_storage_append+0x1ac>
1007bc26c: 94004f2c    	bl	0x1007cff1c <_gc_heap_unregister_parked_roots>
1007bc270: f9400be0    	ldr	x0, [sp, #0x10]
1007bc274: 9400c8de    	bl	0x1007ee5ec <_write+0x1007ee5ec>
1007bc278: f9400b40    	ldr	x0, [x26, #0x10]
1007bc27c: f94013e1    	ldr	x1, [sp, #0x20]
1007bc280: 940036f4    	bl	0x1007c9e50 <_wasmoon_quota_release>
1007bc284: f9400f40    	ldr	x0, [x26, #0x18]
1007bc288: f94017e1    	ldr	x1, [sp, #0x28]
1007bc28c: 940036f1    	bl	0x1007c9e50 <_wasmoon_quota_release>
1007bc290: 52800000    	mov	w0, #0x0                ; =0
1007bc294: a9497bfd    	ldp	x29, x30, [sp, #0x90]
1007bc298: a9484ff4    	ldp	x20, x19, [sp, #0x80]
1007bc29c: a94757f6    	ldp	x22, x21, [sp, #0x70]
1007bc2a0: a9465ff8    	ldp	x24, x23, [sp, #0x60]
1007bc2a4: a94567fa    	ldp	x26, x25, [sp, #0x50]
1007bc2a8: a9446ffc    	ldp	x28, x27, [sp, #0x40]
1007bc2ac: 910283ff    	add	sp, sp, #0xa0
1007bc2b0: d65f03c0    	ret
