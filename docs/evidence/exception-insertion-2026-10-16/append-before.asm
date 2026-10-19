
wasmoon:	file format mach-o arm64

Disassembly of section __TEXT,__text:

00000001007d235c <_wasmoon_exception_storage_append>:
1007d235c: d10283ff    	sub	sp, sp, #0xa0
1007d2360: a9046ffc    	stp	x28, x27, [sp, #0x40]
1007d2364: a90567fa    	stp	x26, x25, [sp, #0x50]
1007d2368: a9065ff8    	stp	x24, x23, [sp, #0x60]
1007d236c: a90757f6    	stp	x22, x21, [sp, #0x70]
1007d2370: a9084ff4    	stp	x20, x19, [sp, #0x80]
1007d2374: a9097bfd    	stp	x29, x30, [sp, #0x90]
1007d2378: 910243fd    	add	x29, sp, #0x90
1007d237c: b940141b    	ldr	w27, [x0, #0x14]
1007d2380: 37f80cbb    	tbnz	w27, #0x1f, 0x1007d2514 <_wasmoon_exception_storage_append+0x1b8>
1007d2384: aa0503f3    	mov	x19, x5
1007d2388: aa0403f4    	mov	x20, x4
1007d238c: aa0303f7    	mov	x23, x3
1007d2390: aa0203f8    	mov	x24, x2
1007d2394: aa0103f5    	mov	x21, x1
1007d2398: aa0003f6    	mov	x22, x0
1007d239c: f9400008    	ldr	x8, [x0]
1007d23a0: f940051a    	ldr	x26, [x8, #0x8]
1007d23a4: 29412748    	ldp	w8, w9, [x26, #0x8]
1007d23a8: 93407d08    	sxtw	x8, w8
1007d23ac: 6b09011f    	cmp	w8, w9
1007d23b0: 540001c1    	b.ne	0x1007d23e8 <_wasmoon_exception_storage_append+0x8c>
1007d23b4: d37ff909    	lsl	x9, x8, #1
1007d23b8: 7100011f    	cmp	w8, #0x0
1007d23bc: 52800208    	mov	w8, #0x10               ; =16
1007d23c0: 9a890119    	csel	x25, x8, x9, eq
1007d23c4: d35fff28    	lsr	x8, x25, #31
1007d23c8: b5000a68    	cbnz	x8, 0x1007d2514 <_wasmoon_exception_storage_append+0x1b8>
1007d23cc: f9400340    	ldr	x0, [x26]
1007d23d0: 8b190b28    	add	x8, x25, x25, lsl #2
1007d23d4: d37df101    	lsl	x1, x8, #3
1007d23d8: 97ffd713    	bl	0x1007c8024 <_wasmoon_native_realloc>
1007d23dc: b40009e0    	cbz	x0, 0x1007d2518 <_wasmoon_exception_storage_append+0x1bc>
1007d23e0: f9000340    	str	x0, [x26]
1007d23e4: b9000f59    	str	w25, [x26, #0xc]
1007d23e8: 6f00e400    	movi.2d	v0, #0000000000000000
1007d23ec: ad0083e0    	stp	q0, q0, [sp, #0x10]
1007d23f0: 3400013b    	cbz	w27, 0x1007d2414 <_wasmoon_exception_storage_append+0xb8>
1007d23f4: d37df379    	lsl	x25, x27, #3
1007d23f8: aa1903e0    	mov	x0, x25
1007d23fc: 97ffd6e6    	bl	0x1007c7f94 <_wasmoon_native_malloc>
1007d2400: f9000be0    	str	x0, [sp, #0x10]
1007d2404: b40008a0    	cbz	x0, 0x1007d2518 <_wasmoon_exception_storage_append+0x1bc>
1007d2408: f9400ec1    	ldr	x1, [x22, #0x18]
1007d240c: aa1903e2    	mov	x2, x25
1007d2410: 940070b6    	bl	0x1007ee6e8 <_write+0x1007ee6e8>
1007d2414: b94012c8    	ldr	w8, [x22, #0x10]
1007d2418: 29066fe8    	stp	w8, w27, [sp, #0x30]
1007d241c: f94006c0    	ldr	x0, [x22, #0x8]
1007d2420: b4000460    	cbz	x0, 0x1007d24ac <_wasmoon_exception_storage_append+0x150>
1007d2424: 2a170368    	orr	w8, w27, w23
1007d2428: 34000428    	cbz	w8, 0x1007d24ac <_wasmoon_exception_storage_append+0x150>
1007d242c: f90007ff    	str	xzr, [sp, #0x8]
1007d2430: 7100077f    	cmp	w27, #0x1
1007d2434: 1a9f8779    	csinc	w25, w27, wzr, hi
1007d2438: 910043e8    	add	x8, sp, #0x10
1007d243c: b27d0102    	orr	x2, x8, #0x8
1007d2440: 910023e3    	add	x3, sp, #0x8
1007d2444: aa1903e1    	mov	x1, x25
1007d2448: 97ffef30    	bl	0x1007ce108 <_gc_heap_register_parked_roots>
1007d244c: 340004a0    	cbz	w0, 0x1007d24e0 <_wasmoon_exception_storage_append+0x184>
1007d2450: d2800008    	mov	x8, #0x0                ; =0
1007d2454: b85fc309    	ldur	w9, [x24, #-0x4]
1007d2458: 14000007    	b	0x1007d2474 <_wasmoon_exception_storage_append+0x118>
1007d245c: d280000a    	mov	x10, #0x0               ; =0
1007d2460: f94007eb    	ldr	x11, [sp, #0x8]
1007d2464: f828796a    	str	x10, [x11, x8, lsl #3]
1007d2468: 91000508    	add	x8, x8, #0x1
1007d246c: eb08033f    	cmp	x25, x8
1007d2470: 54000120    	b.eq	0x1007d2494 <_wasmoon_exception_storage_append+0x138>
1007d2474: eb1b011f    	cmp	x8, x27
1007d2478: 54ffff22    	b.hs	0x1007d245c <_wasmoon_exception_storage_append+0x100>
1007d247c: 34000069    	cbz	w9, 0x1007d2488 <_wasmoon_exception_storage_append+0x12c>
1007d2480: b8687b0a    	ldr	w10, [x24, x8, lsl #2]
1007d2484: 34fffeca    	cbz	w10, 0x1007d245c <_wasmoon_exception_storage_append+0x100>
1007d2488: f9400bea    	ldr	x10, [sp, #0x10]
1007d248c: f868794a    	ldr	x10, [x10, x8, lsl #3]
1007d2490: 17fffff4    	b	0x1007d2460 <_wasmoon_exception_storage_append+0x104>
1007d2494: 340000d7    	cbz	w23, 0x1007d24ac <_wasmoon_exception_storage_append+0x150>
1007d2498: f9400fe0    	ldr	x0, [sp, #0x18]
1007d249c: f94002c1    	ldr	x1, [x22]
1007d24a0: aa1503e2    	mov	x2, x21
1007d24a4: 97ffef70    	bl	0x1007ce264 <_gc_heap_bind_exception_roots>
1007d24a8: 340001c0    	cbz	w0, 0x1007d24e0 <_wasmoon_exception_storage_append+0x184>
1007d24ac: a9024ff4    	stp	x20, x19, [sp, #0x20]
1007d24b0: f9400348    	ldr	x8, [x26]
1007d24b4: b9800b49    	ldrsw	x9, [x26, #0x8]
1007d24b8: 1100052a    	add	w10, w9, #0x1
1007d24bc: b9000b4a    	str	w10, [x26, #0x8]
1007d24c0: 5280050a    	mov	w10, #0x28              ; =40
1007d24c4: 9b2a2128    	smaddl	x8, w9, w10, x8
1007d24c8: ad4087e0    	ldp	q0, q1, [sp, #0x10]
1007d24cc: f9401be9    	ldr	x9, [sp, #0x30]
1007d24d0: f9001109    	str	x9, [x8, #0x20]
1007d24d4: ad000500    	stp	q0, q1, [x8]
1007d24d8: 52800020    	mov	w0, #0x1                ; =1
1007d24dc: 1400000f    	b	0x1007d2518 <_wasmoon_exception_storage_append+0x1bc>
1007d24e0: b94037e8    	ldr	w8, [sp, #0x34]
1007d24e4: 37f80188    	tbnz	w8, #0x1f, 0x1007d2514 <_wasmoon_exception_storage_append+0x1b8>
1007d24e8: f9400fe0    	ldr	x0, [sp, #0x18]
1007d24ec: b4000040    	cbz	x0, 0x1007d24f4 <_wasmoon_exception_storage_append+0x198>
1007d24f0: 97ffef36    	bl	0x1007ce1c8 <_gc_heap_unregister_parked_roots>
1007d24f4: f9400be0    	ldr	x0, [sp, #0x10]
1007d24f8: 94006ffe    	bl	0x1007ee4f0 <_write+0x1007ee4f0>
1007d24fc: f9400b40    	ldr	x0, [x26, #0x10]
1007d2500: f94013e1    	ldr	x1, [sp, #0x20]
1007d2504: 97ffd6fe    	bl	0x1007c80fc <_wasmoon_quota_release>
1007d2508: f9400f40    	ldr	x0, [x26, #0x18]
1007d250c: f94017e1    	ldr	x1, [sp, #0x28]
1007d2510: 97ffd6fb    	bl	0x1007c80fc <_wasmoon_quota_release>
1007d2514: 52800000    	mov	w0, #0x0                ; =0
1007d2518: a9497bfd    	ldp	x29, x30, [sp, #0x90]
1007d251c: a9484ff4    	ldp	x20, x19, [sp, #0x80]
1007d2520: a94757f6    	ldp	x22, x21, [sp, #0x70]
1007d2524: a9465ff8    	ldp	x24, x23, [sp, #0x60]
1007d2528: a94567fa    	ldp	x26, x25, [sp, #0x50]
1007d252c: a9446ffc    	ldp	x28, x27, [sp, #0x40]
1007d2530: 910283ff    	add	sp, sp, #0xa0
1007d2534: d65f03c0    	ret
