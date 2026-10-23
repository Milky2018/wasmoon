# Issue 568: generated loop evidence

Exact experiment contract and caveats: [comparison](issue568-three-engine-comparison-2026-10-22.md). Dumps are diagnostic, not timing runs. Wasmoon BL operands are unlinked relocations; a branch to its own address does not mean recursion. Resolve them with the allocated VCode call list. V8 absolute addresses are diagnostic process addresses; trap stubs are not normal hot-loop calls.

## Function 454: left_shift

### Wasmoon optimized MilkIR

```text
function _M0MPC28internal7strconv7Decimal11left__shift(v0:i64, v1:ref, v2:i32) -> i32 {
block0:
    v15:i32 = ext.wasm.call [455] v1, v2
    v16:i32 = ext.wasm.struct_get [244, 1] v1
    v17:ref = ext.wasm.struct_new [303] v16
    v18:i32 = ext.wasm.struct_get [244, 1] v1
    v19:i32 = iadd v18, v15
    v20:ref = ext.wasm.struct_new [303] v19
    v21:i64 = iconst 0
    v22:ref = ext.wasm.struct_new [462] v21
    v24:i32 = iconst 1
    v25:i32 = isub v16, v24
    v36:ref = ext.wasm.struct_get [244, 0] v1
    v187:i32 = iconst 0
    v189:i32 = iconst 0
    jump block1(v25, v19, v21, v187, v189)
block1(v136:i32, v137:i32, v138:i64, v190:i32, v191:i32):
    v31:i32 = iconst 0
    v32:i32 = icmp.sge v136, v31
    v204:i32 = iconst 0
    v205:i32 = iconst 1
    v206:ref = iconst 0
    branch v32, block3(v136, v137, v138, v190, v191), block12(v137, v138, v204, v206)
block3(v139:i32, v140:i32, v141:i64, v200:i32, v201:i32):
    v38:i32 = ext.wasm.array_get_u [2, 1] v36, v136
    v129:i64 = sextend v38
    v41:i64 = sextend v2
    v42:i64 = ishl v129, v41
    v43:i64 = iadd v141, v42
    v46:i64 = iconst 10
    v47:i64 = sdiv v43, v46
    v49:i64 = iconst 10
    v50:i64 = imul v47, v49
    v51:i64 = isub v43, v50
    v52:i32 = ireduce v51
    v54:i32 = iconst 1
    v55:i32 = isub v140, v54
    branch v200, block27(v201), block26()
block6(v142:i32, v195:i32):
    v63:i32 = iconst 255
    v64:i32 = band v52, v63
    ext.wasm.array_set [2] v36, v55, v64
    jump block8(v142, v195)
block7(v145:i32, v197:i32):
    v66:i32 = iconst 0
    v67:i32 = icmp.ne v52, v66
    branch v67, block9(v145, v197), block8(v145, v197)
block8(v148:i32, v193:i32):
    v74:i32 = iconst 1
    v75:i32 = isub v148, v74
    v225:i32 = iconst 1
    jump block1(v75, v55, v47, v225, v193)
block9(v151:i32, v199:i32):
    v68:i32 = iconst 1
    ext.wasm.struct_set [244, 4] v1, v68
    jump block8(v151, v199)
block12(v155:i32, v156:i64, v207:i32, v208:ref):
    v81:i64 = iconst 0
    v82:i32 = icmp.sgt v156, v81
    branch v82, block14(v155, v207, v208), block15()
block14(v158:i32, v215:i32, v216:ref):
    v86:i64 = iconst 10
    v87:i64 = sdiv v156, v86
    v89:i64 = iconst 10
    v90:i64 = imul v87, v89
    v91:i64 = isub v156, v90
    v92:i32 = ireduce v91
    v94:i32 = iconst 1
    v95:i32 = isub v158, v94
    branch v215, block29(v216), block28()
block15:
    v114:i32 = ext.wasm.struct_get [244, 1] v1
    v115:i32 = iadd v114, v15
    ext.wasm.struct_set [244, 1] v1, v115
    v118:ref = ext.wasm.struct_get [244, 0] v1
    v119:i32 = ext.wasm.array_len v118
    v120:i32 = icmp.sgt v115, v119
    branch v120, block23(), block25()
block17(v210:ref):
    v103:i32 = iconst 255
    v104:i32 = band v92, v103
    ext.wasm.array_set [2] v217, v95, v104
    jump block12(v95, v87, v205, v210)
block18(v212:ref):
    v106:i32 = iconst 0
    v107:i32 = icmp.ne v92, v106
    branch v107, block20(v212), block12(v95, v87, v205, v212)
block20(v214:ref):
    v108:i32 = iconst 1
    ext.wasm.struct_set [244, 4] v1, v108
    jump block12(v95, v87, v205, v214)
block23:
    ext.wasm.struct_set [244, 1] v1, v119
    jump block25
block25:
    v125:i32 = ext.wasm.struct_get [244, 2] v1
    v126:i32 = iadd v125, v15
    ext.wasm.struct_set [244, 2] v1, v126
    v128:i32 = ext.wasm.call [461] v1
    return v128
block26:
    v203:i32 = ext.wasm.array_len v36
    jump block27(v203)
block27(v202:i32):
    v60:i32 = icmp.slt v55, v202
    branch v60, block6(v139, v202), block7(v139, v202)
block28:
    v218:ref = ext.wasm.struct_get [244, 0] v1
    jump block29(v218)
block29(v217:ref):
    v99:i32 = ext.wasm.array_len v217
    v100:i32 = icmp.slt v95, v99
    branch v100, block17(v217), block18(v217)
}
```

### Wasmoon VCode call-site order

```text
i6 PlatformCall(
  { name: "wasmoon.runtime.gc.push_root_scope" }
i7 InternalCall(
  { name: "wasm.func.455" }
i10 PlatformCall(
  { name: "wasmoon.runtime.gc.pop_root_scope" }
i14 PlatformCall(
  { name: "wasmoon.runtime.gc.struct_get_heap" }
i27 PlatformCall(
  { name: "wasmoon.runtime.gc.push_root_scope" }
i28 PlatformCall(
  { name: "wasmoon.runtime.gc.alloc_struct_slow" }
i31 PlatformCall(
  { name: "wasmoon.runtime.gc.pop_root_scope" }
i36 PlatformCall(
  { name: "wasmoon.runtime.gc.struct_get_heap" }
i50 PlatformCall(
  { name: "wasmoon.runtime.gc.push_root_scope" }
i51 PlatformCall(
  { name: "wasmoon.runtime.gc.alloc_struct_slow" }
i54 PlatformCall(
  { name: "wasmoon.runtime.gc.pop_root_scope" }
i66 PlatformCall(
  { name: "wasmoon.runtime.gc.push_root_scope" }
i67 PlatformCall(
  { name: "wasmoon.runtime.gc.alloc_struct_slow" }
i70 PlatformCall(
  { name: "wasmoon.runtime.gc.pop_root_scope" }
i76 PlatformCall(
  { name: "wasmoon.runtime.gc.struct_get_heap" }
i81 PlatformCall(
  { name: "wasmoon.runtime.gc.array_data_heap" }
i100 PlatformCall(
  { name: "wasmoon.runtime.gc.struct_get_heap" }
i108 PlatformCall(
  { name: "wasmoon.runtime.gc.struct_set_heap" }
i112 PlatformCall(
  { name: "wasmoon.runtime.gc.struct_get_heap" }
i116 PlatformCall(
  { name: "wasmoon.runtime.gc.array_len_heap" }
i123 PlatformCall(
  { name: "wasmoon.runtime.gc.struct_set_heap" }
i128 PlatformCall(
  { name: "wasmoon.runtime.gc.struct_get_heap" }
i136 PlatformCall(
  { name: "wasmoon.runtime.gc.struct_set_heap" }
i140 PlatformCall(
  { name: "wasmoon.runtime.gc.push_root_scope" }
i141 InternalCall(
  { name: "wasm.func.461" }
i144 PlatformCall(
  { name: "wasmoon.runtime.gc.pop_root_scope" }
i160 PlatformCall(
  { name: "wasmoon.runtime.gc.struct_get_heap" }
i165 PlatformCall(
  { name: "wasmoon.runtime.gc.array_len_heap" }
i174 PlatformCall(
  { name: "wasmoon.runtime.gc.struct_set_heap" }
i180 PlatformCall(
  { name: "wasmoon.runtime.gc.array_set_heap" }
i186 PlatformCall(
  { name: "wasmoon.runtime.gc.array_get_heap" }
i213 PlatformCall(
  { name: "wasmoon.runtime.gc.array_len_heap" }
i223 PlatformCall(
  { name: "wasmoon.runtime.gc.struct_set_heap" }
i231 PlatformCall(
  { name: "wasmoon.runtime.gc.array_set_heap" }
```

### Wasmoon ARM64 machine code

```asm
/var/folders/n6/d4863hyd3078tg52nj9vppjr0000gn/T/wasmoon-568-comparison-rhbbmzio/wm-454.o:	file format mach-o arm64

Disassembly of section __TEXT,__text:

0000000000000000 <ltmp0>:
       0: d10043ff     	sub	sp, sp, #0x10
       4: a9007bfd     	stp	x29, x30, [sp]
       8: 910003fd     	mov	x29, sp
       c: d10343ff     	sub	sp, sp, #0xd0
      10: a907d3f3     	stp	x19, x20, [sp, #0x78]
      14: a908dbf5     	stp	x21, x22, [sp, #0x88]
      18: a909e3f7     	stp	x23, x24, [sp, #0x98]
      1c: a90aebf9     	stp	x25, x26, [sp, #0xa8]
      20: a90bf3fb     	stp	x27, x28, [sp, #0xb8]
      24: aa0003f3     	mov	x19, x0
      28: aa0103f4     	mov	x20, x1
      2c: b90053e2     	str	w2, [sp, #0x50]
      30: 910003e1     	mov	x1, sp
      34: f9000034     	str	x20, [x1]
      38: 52800022     	mov	w2, #0x1                ; =1
      3c: aa1303e0     	mov	x0, x19
      40: 94000000     	bl	0x40 <ltmp0+0x40>
      44: b94053f6     	ldr	w22, [sp, #0x50]
      48: aa1303e0     	mov	x0, x19
      4c: aa1403e1     	mov	x1, x20
      50: 2a1603e2     	mov	w2, w22
      54: 94000000     	bl	0x54 <ltmp0+0x54>
      58: b90057e0     	str	w0, [sp, #0x54]
      5c: aa1303e0     	mov	x0, x19
      60: 94000000     	bl	0x60 <ltmp0+0x60>
      64: 52801e80     	mov	w0, #0xf4               ; =244
      68: 52800022     	mov	w2, #0x1                ; =1
      6c: f9402260     	ldr	x0, [x19, #0x40]
      70: aa1403e1     	mov	x1, x20
      74: 94000000     	bl	0x74 <ltmp0+0x74>
      78: 2a0003f5     	mov	w21, w0
      7c: b9005bf5     	str	w21, [sp, #0x58]
      80: 910083f6     	add	x22, sp, #0x20
      84: 2a1503e0     	mov	w0, w21
      88: f90002c0     	str	x0, [x22]
      8c: 528025f7     	mov	w23, #0x12f             ; =303
      90: 52800038     	mov	w24, #0x1               ; =1
      94: 52a00019     	movz	w25, #0x0, lsl #16
      98: 528038da     	mov	w26, #0x1c6             ; =454
      9c: 910003e1     	mov	x1, sp
      a0: f9000034     	str	x20, [x1]
      a4: 52800022     	mov	w2, #0x1                ; =1
      a8: aa1303e0     	mov	x0, x19
      ac: 94000000     	bl	0xac <ltmp0+0xac>
      b0: aa1303e0     	mov	x0, x19
      b4: 2a1703e1     	mov	w1, w23
      b8: aa1603e2     	mov	x2, x22
      bc: 2a1803e3     	mov	w3, w24
      c0: 2a1903e4     	mov	w4, w25
      c4: 2a1a03e5     	mov	w5, w26
      c8: 94000000     	bl	0xc8 <ltmp0+0xc8>
      cc: aa0003f5     	mov	x21, x0
      d0: aa1303e0     	mov	x0, x19
      d4: 94000000     	bl	0xd4 <ltmp0+0xd4>
      d8: aa1503e0     	mov	x0, x21
      dc: 52801e80     	mov	w0, #0xf4               ; =244
      e0: 52800022     	mov	w2, #0x1                ; =1
      e4: f9402260     	ldr	x0, [x19, #0x40]
      e8: aa1403e1     	mov	x1, x20
      ec: 94000000     	bl	0xec <ltmp0+0xec>
      f0: b94057f6     	ldr	w22, [sp, #0x54]
      f4: 0b160017     	add	w23, w0, w22
      f8: 9100c3f8     	add	x24, sp, #0x30
      fc: 2a1703e0     	mov	w0, w23
     100: f9000300     	str	x0, [x24]
     104: 528025f9     	mov	w25, #0x12f             ; =303
     108: 5280003a     	mov	w26, #0x1               ; =1
     10c: 5280003b     	mov	w27, #0x1               ; =1
     110: 528038dc     	mov	w28, #0x1c6             ; =454
     114: 910003e1     	mov	x1, sp
     118: f9000034     	str	x20, [x1]
     11c: 52800022     	mov	w2, #0x1                ; =1
     120: aa1303e0     	mov	x0, x19
     124: 94000000     	bl	0x124 <ltmp0+0x124>
     128: aa1303e0     	mov	x0, x19
     12c: 2a1903e1     	mov	w1, w25
     130: aa1803e2     	mov	x2, x24
     134: 2a1a03e3     	mov	w3, w26
     138: 2a1b03e4     	mov	w4, w27
     13c: 2a1c03e5     	mov	w5, w28
     140: 94000000     	bl	0x140 <ltmp0+0x140>
     144: aa0003f5     	mov	x21, x0
     148: aa1303e0     	mov	x0, x19
     14c: 94000000     	bl	0x14c <ltmp0+0x14c>
     150: aa1503e0     	mov	x0, x21
     154: 52a00018     	movz	w24, #0x0, lsl #16
     158: 910103f9     	add	x25, sp, #0x40
     15c: f9000338     	str	x24, [x25]
     160: 528039da     	mov	w26, #0x1ce             ; =462
     164: 5280003b     	mov	w27, #0x1               ; =1
     168: 5280005c     	mov	w28, #0x2               ; =2
     16c: 528038d5     	mov	w21, #0x1c6             ; =454
     170: 910003e1     	mov	x1, sp
     174: f9000034     	str	x20, [x1]
     178: 52800022     	mov	w2, #0x1                ; =1
     17c: aa1303e0     	mov	x0, x19
     180: 94000000     	bl	0x180 <ltmp0+0x180>
     184: aa1303e0     	mov	x0, x19
     188: 2a1a03e1     	mov	w1, w26
     18c: aa1903e2     	mov	x2, x25
     190: 2a1b03e3     	mov	w3, w27
     194: 2a1c03e4     	mov	w4, w28
     198: 2a1503e5     	mov	w5, w21
     19c: 94000000     	bl	0x19c <ltmp0+0x19c>
     1a0: aa0003f5     	mov	x21, x0
     1a4: aa1303e0     	mov	x0, x19
     1a8: 94000000     	bl	0x1a8 <ltmp0+0x1a8>
     1ac: aa1503e0     	mov	x0, x21
     1b0: b9405bf5     	ldr	w21, [sp, #0x58]
     1b4: 510006b9     	sub	w25, w21, #0x1
     1b8: 52801e80     	mov	w0, #0xf4               ; =244
     1bc: 52a00002     	movz	w2, #0x0, lsl #16
     1c0: f9402260     	ldr	x0, [x19, #0x40]
     1c4: aa1403e1     	mov	x1, x20
     1c8: 94000000     	bl	0x1c8 <ltmp0+0x1c8>
     1cc: aa0003e1     	mov	x1, x0
     1d0: f90033e1     	str	x1, [sp, #0x60]
     1d4: f9402260     	ldr	x0, [x19, #0x40]
     1d8: 52800022     	mov	w2, #0x1                ; =1
     1dc: f94033e1     	ldr	x1, [sp, #0x60]
     1e0: 94000000     	bl	0x1e0 <ltmp0+0x1e0>
     1e4: f90037e0     	str	x0, [sp, #0x68]
     1e8: f94037fa     	ldr	x26, [sp, #0x68]
     1ec: f100035f     	cmp	x26, #0x0
     1f0: 9a9f07e0     	cset	x0, ne
     1f4: 34000080     	cbz	w0, 0x204 <ltmp0+0x204>
     1f8: f94037fa     	ldr	x26, [sp, #0x68]
     1fc: b940035b     	ldr	w27, [x26]
     200: 14000002     	b	0x208 <ltmp0+0x208>
     204: 52a0001b     	movz	w27, #0x0, lsl #16
     208: 52a00015     	movz	w21, #0x0, lsl #16
     20c: 52a0001c     	movz	w28, #0x0, lsl #16
     210: 52a00000     	movz	w0, #0x0, lsl #16
     214: 52800021     	mov	w1, #0x1                ; =1
     218: b90073e1     	str	w1, [sp, #0x70]
     21c: 52a0001a     	movz	w26, #0x0, lsl #16
     220: 7100033f     	cmp	w25, #0x0
     224: 5400006b     	b.lt	0x230 <ltmp0+0x230>
     228: 2a1903f6     	mov	w22, w25
     22c: 14000076     	b	0x404 <ltmp0+0x404>
     230: f100031f     	cmp	x24, #0x0
     234: 5400080c     	b.gt	0x334 <ltmp0+0x334>
     238: 52801e80     	mov	w0, #0xf4               ; =244
     23c: 52800022     	mov	w2, #0x1                ; =1
     240: f9402260     	ldr	x0, [x19, #0x40]
     244: aa1403e1     	mov	x1, x20
     248: 94000000     	bl	0x248 <ltmp0+0x248>
     24c: b94057f6     	ldr	w22, [sp, #0x54]
     250: 0b160015     	add	w21, w0, w22
     254: 2a1503e3     	mov	w3, w21
     258: 52801e80     	mov	w0, #0xf4               ; =244
     25c: 52800022     	mov	w2, #0x1                ; =1
     260: f9402260     	ldr	x0, [x19, #0x40]
     264: aa1403e1     	mov	x1, x20
     268: 94000000     	bl	0x268 <ltmp0+0x268>
     26c: 52801e80     	mov	w0, #0xf4               ; =244
     270: 52a00002     	movz	w2, #0x0, lsl #16
     274: f9402260     	ldr	x0, [x19, #0x40]
     278: aa1403e1     	mov	x1, x20
     27c: 94000000     	bl	0x27c <ltmp0+0x27c>
     280: aa0003e1     	mov	x1, x0
     284: f9402260     	ldr	x0, [x19, #0x40]
     288: 94000000     	bl	0x288 <ltmp0+0x288>
     28c: 6b0002bf     	cmp	w21, w0
     290: 540000ed     	b.le	0x2ac <ltmp0+0x2ac>
     294: 2a0003e3     	mov	w3, w0
     298: 52801e80     	mov	w0, #0xf4               ; =244
     29c: 52800022     	mov	w2, #0x1                ; =1
     2a0: f9402260     	ldr	x0, [x19, #0x40]
     2a4: aa1403e1     	mov	x1, x20
     2a8: 94000000     	bl	0x2a8 <ltmp0+0x2a8>
     2ac: 52801e80     	mov	w0, #0xf4               ; =244
     2b0: 52800042     	mov	w2, #0x2                ; =2
     2b4: f9402260     	ldr	x0, [x19, #0x40]
     2b8: aa1403e1     	mov	x1, x20
     2bc: 94000000     	bl	0x2bc <ltmp0+0x2bc>
     2c0: b94057f6     	ldr	w22, [sp, #0x54]
     2c4: 0b160000     	add	w0, w0, w22
     2c8: 2a0003e3     	mov	w3, w0
     2cc: 52801e80     	mov	w0, #0xf4               ; =244
     2d0: 52800042     	mov	w2, #0x2                ; =2
     2d4: f9402260     	ldr	x0, [x19, #0x40]
     2d8: aa1403e1     	mov	x1, x20
     2dc: 94000000     	bl	0x2dc <ltmp0+0x2dc>
     2e0: 910003e1     	mov	x1, sp
     2e4: f9000034     	str	x20, [x1]
     2e8: 52800022     	mov	w2, #0x1                ; =1
     2ec: aa1303e0     	mov	x0, x19
     2f0: 94000000     	bl	0x2f0 <ltmp0+0x2f0>
     2f4: aa1303e0     	mov	x0, x19
     2f8: aa1403e1     	mov	x1, x20
     2fc: 94000000     	bl	0x2fc <ltmp0+0x2fc>
     300: 2a0003f5     	mov	w21, w0
     304: aa1303e0     	mov	x0, x19
     308: 94000000     	bl	0x308 <ltmp0+0x308>
     30c: 2a1503e0     	mov	w0, w21
     310: a94bf3fb     	ldp	x27, x28, [sp, #0xb8]
     314: a94aebf9     	ldp	x25, x26, [sp, #0xa8]
     318: a949e3f7     	ldp	x23, x24, [sp, #0x98]
     31c: a948dbf5     	ldp	x21, x22, [sp, #0x88]
     320: a947d3f3     	ldp	x19, x20, [sp, #0x78]
     324: 910343ff     	add	sp, sp, #0xd0
     328: a9407bfd     	ldp	x29, x30, [sp]
     32c: 910043ff     	add	sp, sp, #0x10
     330: d65f03c0     	ret
     334: 52800141     	mov	w1, #0xa                ; =10
     338: b5000041     	cbnz	x1, 0x340 <ltmp0+0x340>
     33c: d4200080     	brk	#0x4
     340: b100043f     	cmn	x1, #0x1
     344: fa410b00     	ccmp	x24, #0x1, #0x0, eq
     348: 54000047     	b.vc	0x350 <ltmp0+0x350>
     34c: d42000a0     	brk	#0x5
     350: 9ac10f15     	sdiv	x21, x24, x1
     354: 52800141     	mov	w1, #0xa                ; =10
     358: 9b017ea1     	mul	x1, x21, x1
     35c: cb010301     	sub	x1, x24, x1
     360: 2a0103f6     	mov	w22, w1
     364: 510006f7     	sub	w23, w23, #0x1
     368: 350000e0     	cbnz	w0, 0x384 <ltmp0+0x384>
     36c: 52801e80     	mov	w0, #0xf4               ; =244
     370: 52a00002     	movz	w2, #0x0, lsl #16
     374: f9402260     	ldr	x0, [x19, #0x40]
     378: aa1403e1     	mov	x1, x20
     37c: 94000000     	bl	0x37c <ltmp0+0x37c>
     380: aa0003fa     	mov	x26, x0
     384: f9402260     	ldr	x0, [x19, #0x40]
     388: aa1a03e1     	mov	x1, x26
     38c: 94000000     	bl	0x38c <ltmp0+0x38c>
     390: 6b0002ff     	cmp	w23, w0
     394: 5400006a     	b.ge	0x3a0 <ltmp0+0x3a0>
     398: aa1a03f8     	mov	x24, x26
     39c: 1400000f     	b	0x3d8 <ltmp0+0x3d8>
     3a0: 35000096     	cbnz	w22, 0x3b0 <ltmp0+0x3b0>
     3a4: aa1503f8     	mov	x24, x21
     3a8: b94073e0     	ldr	w0, [sp, #0x70]
     3ac: 17ffffa1     	b	0x230 <ltmp0+0x230>
     3b0: 52800020     	mov	w0, #0x1                ; =1
     3b4: 2a0003e3     	mov	w3, w0
     3b8: 52801e80     	mov	w0, #0xf4               ; =244
     3bc: 52800082     	mov	w2, #0x4                ; =4
     3c0: f9402260     	ldr	x0, [x19, #0x40]
     3c4: aa1403e1     	mov	x1, x20
     3c8: 94000000     	bl	0x3c8 <ltmp0+0x3c8>
     3cc: aa1503f8     	mov	x24, x21
     3d0: b94073e0     	ldr	w0, [sp, #0x70]
     3d4: 17ffff97     	b	0x230 <ltmp0+0x230>
     3d8: 12001ec0     	and	w0, w22, #0xff
     3dc: 2a0003e3     	mov	w3, w0
     3e0: 52800040     	mov	w0, #0x2                ; =2
     3e4: f9402260     	ldr	x0, [x19, #0x40]
     3e8: aa1a03e1     	mov	x1, x26
     3ec: 2a1703e2     	mov	w2, w23
     3f0: 94000000     	bl	0x3f0 <ltmp0+0x3f0>
     3f4: b94073e0     	ldr	w0, [sp, #0x70]
     3f8: aa1803fa     	mov	x26, x24
     3fc: aa1503f8     	mov	x24, x21
     400: 17ffff8c     	b	0x230 <ltmp0+0x230>
     404: 6b1b033f     	cmp	w25, w27
     408: 9a9f27e0     	cset	x0, lo
     40c: 35000120     	cbnz	w0, 0x430 <ltmp0+0x430>
     410: 52800040     	mov	w0, #0x2                ; =2
     414: f9402260     	ldr	x0, [x19, #0x40]
     418: f94033e1     	ldr	x1, [sp, #0x60]
     41c: 2a1903e2     	mov	w2, w25
     420: 94000000     	bl	0x420 <ltmp0+0x420>
     424: 52801fe1     	mov	w1, #0xff               ; =255
     428: 0a010000     	and	w0, w0, w1
     42c: 14000007     	b	0x448 <ltmp0+0x448>
     430: 2a1903e0     	mov	w0, w25
     434: 52800021     	mov	w1, #0x1                ; =1
     438: 9b017c00     	mul	x0, x0, x1
     43c: f94037fa     	ldr	x26, [sp, #0x68]
     440: 8b000340     	add	x0, x26, x0
     444: 39404000     	ldrb	w0, [x0, #0x10]
     448: 93407c00     	sxtw	x0, w0
     44c: b94053e2     	ldr	w2, [sp, #0x50]
     450: 93407c41     	sxtw	x1, w2
     454: 9ac12000     	lsl	x0, x0, x1
     458: 8b000300     	add	x0, x24, x0
     45c: 52800141     	mov	w1, #0xa                ; =10
     460: b5000041     	cbnz	x1, 0x468 <ltmp0+0x468>
     464: d4200080     	brk	#0x4
     468: b100043f     	cmn	x1, #0x1
     46c: fa410800     	ccmp	x0, #0x1, #0x0, eq
     470: 54000047     	b.vc	0x478 <ltmp0+0x478>
     474: d42000a0     	brk	#0x5
     478: 9ac10c18     	sdiv	x24, x0, x1
     47c: 52800141     	mov	w1, #0xa                ; =10
     480: 9b017f01     	mul	x1, x24, x1
     484: cb010000     	sub	x0, x0, x1
     488: 2a0003f9     	mov	w25, w0
     48c: 510006f7     	sub	w23, w23, #0x1
     490: 350000b5     	cbnz	w21, 0x4a4 <ltmp0+0x4a4>
     494: f9402260     	ldr	x0, [x19, #0x40]
     498: f94033e1     	ldr	x1, [sp, #0x60]
     49c: 94000000     	bl	0x49c <ltmp0+0x49c>
     4a0: 2a0003fc     	mov	w28, w0
     4a4: 6b1c02ff     	cmp	w23, w28
     4a8: 5400014b     	b.lt	0x4d0 <ltmp0+0x4d0>
     4ac: 34000379     	cbz	w25, 0x518 <ltmp0+0x518>
     4b0: 52800020     	mov	w0, #0x1                ; =1
     4b4: 2a0003e3     	mov	w3, w0
     4b8: 52801e80     	mov	w0, #0xf4               ; =244
     4bc: 52800082     	mov	w2, #0x4                ; =4
     4c0: f9402260     	ldr	x0, [x19, #0x40]
     4c4: aa1403e1     	mov	x1, x20
     4c8: 94000000     	bl	0x4c8 <ltmp0+0x4c8>
     4cc: 14000013     	b	0x518 <ltmp0+0x518>
     4d0: 12001f20     	and	w0, w25, #0xff
     4d4: 6b1b02ff     	cmp	w23, w27
     4d8: 9a9f27e1     	cset	x1, lo
     4dc: 35000101     	cbnz	w1, 0x4fc <ltmp0+0x4fc>
     4e0: 52800041     	mov	w1, #0x2                ; =2
     4e4: 2a0003e3     	mov	w3, w0
     4e8: f9402260     	ldr	x0, [x19, #0x40]
     4ec: f94033e1     	ldr	x1, [sp, #0x60]
     4f0: 2a1703e2     	mov	w2, w23
     4f4: 94000000     	bl	0x4f4 <ltmp0+0x4f4>
     4f8: 14000008     	b	0x518 <ltmp0+0x518>
     4fc: 2a1703e1     	mov	w1, w23
     500: 52800022     	mov	w2, #0x1                ; =1
     504: 9b027c21     	mul	x1, x1, x2
     508: f94037fa     	ldr	x26, [sp, #0x68]
     50c: 8b010341     	add	x1, x26, x1
     510: 39004020     	strb	w0, [x1, #0x10]
     514: 14000001     	b	0x518 <ltmp0+0x518>
     518: 510006d9     	sub	w25, w22, #0x1
     51c: 52800035     	mov	w21, #0x1               ; =1
     520: 17ffff3c     	b	0x210 <ltmp0+0x210>
```

### Wasmtime optimized CLIF

Dumped after compile_maybe_cached, not before optimization.

```text
;; Intermediate Representation of function <wasm[0]::function[454]::_M0MPC28internal7strconv7Decimal11left__shift>:
function u0:454(i64 vmctx, i64, i32, i32) -> i32 tail {
    ss0 = explicit_slot 4, align = 4
    ss1 = explicit_slot 4, align = 4
    ss2 = explicit_slot 4, align = 4
    ss3 = explicit_slot 4, align = 4
    region0 = 123 ""
    region1 = 160 ""
    region2 = 196 ""
    region3 = 206 ""
    region4 = 108 ""
    region5 = 65 ""
    region6 = 177 ""
    region7 = 98 ""
    region8 = 130 ""
    region9 = 178 ""
    region10 = 200 ""
    region11 = 240 ""
    region12 = 0 ""
    region13 = 208 ""
    region14 = 232 ""
    gv0 = vmctx
    gv1 = load.i64 notrap aligned readonly can_move region0 gv0+8
    gv2 = load.i64 notrap aligned region1 gv1+24
    sig0 = (i64 vmctx, i64, i32, i32) -> i32 tail
    sig1 = (i64 vmctx, i32, i32, i32, i32) -> i32 tail
    sig2 = (i64 vmctx, i64, i32) -> i64 tail
    sig3 = (i64 vmctx, i64, i32) -> i32 tail
    fn0 = colocated u0:455 sig0
    fn1 = colocated u805306368:24 sig1
    fn2 = colocated u0:688 sig2
    fn3 = colocated u0:461 sig3
    stack_limit = gv2

                                block0(v0: i64, v1: i64, v2: i32, v3: i32):
                                    v780 = stack_addr.i64 ss0
                                    store notrap aligned region14 v2, v780
@15b19                              v9 = call fn0(v0, v0, v2, v3), stack_map=[i32 @ ss0+0]
                                    v777 = load.i32 notrap aligned region14 v780
@15b20                              trapz v777, user16
@15b20                              v11 = load.i64 notrap aligned readonly can_move region0 v0+8
@15b20                              v12 = load.i64 notrap aligned readonly can_move region2 v11+32
@15b20                              v10 = uextend.i64 v777
@15b20                              v13 = iadd v12, v10
@15b20                              v14 = iconst.i64 20
@15b20                              v15 = iadd v13, v14  ; v14 = 20
@15b20                              v16 = load.i32 user2 little region4 v15
@15b25                              v18 = load.i64 notrap aligned readonly can_move region5 v0+32
@15b25                              v19 = load.i32 notrap aligned region6 v18
@15b25                              v20 = load.i32 notrap aligned region7 v18+4
@15b25                              v26 = uextend.i64 v19
                                    v781 = iconst.i64 32
@15b25                              v27 = iadd v26, v781  ; v781 = 32
@15b25                              v28 = uextend.i64 v20
@15b25                              v29 = icmp ule v27, v28
@15b25                              brif v29, block2, block3

                                block2:
                                    v867 = iconst.i32 32
                                    v795 = iadd.i32 v19, v867  ; v867 = 32
@15b25                              store notrap aligned region6 v795, v18
                                    v868 = iconst.i32 -1342177278
@15b25                              v43 = iadd.i64 v12, v26
@15b25                              store user2 region4 v868, v43  ; v868 = -1342177278
                                    v869 = load.i64 notrap aligned readonly can_move region8 v0+40
                                    v870 = load.i32 notrap aligned readonly can_move region9 v869+160
@15b25                              store user2 region4 v870, v43+4
                                    v871 = iconst.i64 32
@15b25                              istore32 user2 region4 v871, v43+8  ; v871 = 32
@15b25                              jump block4(v19, v43)

                                block3 cold:
@15b25                              v30 = iconst.i32 -1342177278
@15b25                              v31 = load.i64 notrap aligned readonly can_move region8 v0+40
@15b25                              v32 = load.i32 notrap aligned readonly can_move region9 v31+160
@15b25                              v17 = iconst.i32 32
@15b25                              v33 = iconst.i32 16
@15b25                              v34 = call fn1(v0, v30, v32, v17, v33), stack_map=[i32 @ ss0+0]  ; v30 = -1342177278, v17 = 32, v33 = 16
@15b25                              v37 = uextend.i64 v34
@15b25                              v38 = iadd.i64 v12, v37
@15b25                              jump block4(v34, v38)

                                block4(v47: i32, v48: i64):
                                    v773 = stack_addr.i64 ss1
                                    store notrap aligned region11 v47, v773
@15b25                              v49 = iconst.i64 16
@15b25                              v50 = iadd v48, v49  ; v49 = 16
@15b25                              store.i32 user2 little region4 v16, v50
                                    v772 = load.i32 notrap aligned region14 v780
@15b2d                              trapz v772, user16
@15b2d                              v52 = uextend.i64 v772
@15b2d                              v55 = iadd.i64 v12, v52
                                    v872 = iconst.i64 20
                                    v873 = iadd v55, v872  ; v872 = 20
@15b2d                              v58 = load.i32 user2 little region4 v873
@15b35                              v63 = load.i32 notrap aligned region6 v18
@15b35                              v64 = load.i32 notrap aligned region7 v18+4
@15b35                              v70 = uextend.i64 v63
                                    v874 = iconst.i64 32
                                    v875 = iadd v70, v874  ; v874 = 32
@15b35                              v72 = uextend.i64 v64
@15b35                              v73 = icmp ule v875, v72
@15b35                              brif v73, block5, block6

                                block5:
                                    v881 = iconst.i32 32
                                    v798 = iadd.i32 v63, v881  ; v881 = 32
@15b35                              store notrap aligned region6 v798, v18
                                    v882 = iconst.i32 -1342177278
@15b35                              v87 = iadd.i64 v12, v70
@15b35                              store user2 region4 v882, v87  ; v882 = -1342177278
                                    v883 = load.i64 notrap aligned readonly can_move region8 v0+40
                                    v884 = load.i32 notrap aligned readonly can_move region9 v883+160
@15b35                              store user2 region4 v884, v87+4
                                    v885 = iconst.i64 32
@15b35                              istore32 user2 region4 v885, v87+8  ; v885 = 32
@15b35                              jump block7(v63, v87)

                                block6 cold:
                                    v876 = iconst.i32 -1342177278
                                    v877 = load.i64 notrap aligned readonly can_move region8 v0+40
                                    v878 = load.i32 notrap aligned readonly can_move region9 v877+160
                                    v879 = iconst.i32 32
                                    v880 = iconst.i32 16
@15b35                              v78 = call fn1(v0, v876, v878, v879, v880), stack_map=[i32 @ ss0+0, i32 @ ss1+0]  ; v876 = -1342177278, v879 = 32, v880 = 16
@15b35                              v81 = uextend.i64 v78
@15b35                              v82 = iadd.i64 v12, v81
@15b35                              jump block7(v78, v82)

                                block7(v91: i32, v92: i64):
                                    v768 = stack_addr.i64 ss2
                                    store notrap aligned region13 v91, v768
@15b34                              v60 = iadd.i32 v58, v9
                                    v886 = iconst.i64 16
                                    v887 = iadd v92, v886  ; v886 = 16
@15b35                              store user2 little region4 v60, v887
@15b3d                              v98 = load.i32 notrap aligned region6 v18
@15b3d                              v99 = load.i32 notrap aligned region7 v18+4
@15b3d                              v105 = uextend.i64 v98
                                    v888 = iconst.i64 32
                                    v889 = iadd v105, v888  ; v888 = 32
@15b3d                              v107 = uextend.i64 v99
@15b3d                              v108 = icmp ule v889, v107
@15b3d                              brif v108, block8, block9

                                block8:
                                    v894 = iconst.i32 32
                                    v801 = iadd.i32 v98, v894  ; v894 = 32
@15b3d                              store notrap aligned region6 v801, v18
                                    v895 = iconst.i32 -1342177278
@15b3d                              v122 = iadd.i64 v12, v105
@15b3d                              store user2 region4 v895, v122  ; v895 = -1342177278
                                    v896 = load.i64 notrap aligned readonly can_move region8 v0+40
                                    v897 = load.i32 notrap aligned readonly can_move region10 v896+1604
@15b3d                              store user2 region4 v897, v122+4
                                    v898 = iconst.i64 32
@15b3d                              istore32 user2 region4 v898, v122+8  ; v898 = 32
@15b3d                              jump block10(v98, v122)

                                block9 cold:
                                    v890 = iconst.i32 -1342177278
                                    v891 = load.i64 notrap aligned readonly can_move region8 v0+40
@15b3d                              v111 = load.i32 notrap aligned readonly can_move region10 v891+1604
                                    v892 = iconst.i32 32
                                    v893 = iconst.i32 16
@15b3d                              v113 = call fn1(v0, v890, v111, v892, v893), stack_map=[i32 @ ss0+0, i32 @ ss1+0, i32 @ ss2+0]  ; v890 = -1342177278, v892 = 32, v893 = 16
@15b3d                              v116 = uextend.i64 v113
@15b3d                              v117 = iadd.i64 v12, v116
@15b3d                              jump block10(v113, v117)

                                block10(v126: i32, v127: i64):
                                    v767 = stack_addr.i64 ss3
                                    store notrap aligned region12 v126, v767
@15b0d                              v5 = iconst.i64 0
                                    v899 = iconst.i64 16
                                    v900 = iadd v127, v899  ; v899 = 16
@15b3d                              store user2 little region4 v5, v900  ; v5 = 0
                                    v766 = load.i32 notrap aligned region11 v773
@15b47                              trapz v766, user16
@15b47                              v132 = uextend.i64 v766
@15b47                              v135 = iadd.i64 v12, v132
                                    v901 = iadd v135, v899  ; v899 = 16
@15b47                              v138 = load.i32 user2 little region4 v901
@15b4c                              v139 = iconst.i32 1
@15b4e                              v140 = isub v138, v139  ; v139 = 1
@15b4f                              store user2 little region4 v140, v901
@15b03                              v4 = iconst.i32 0
@15b57                              jump block11

                                block11:
                                    v758 = load.i32 notrap aligned region11 v773
@15b5b                              trapz v758, user16
@15b5b                              v149 = uextend.i64 v758
@15b5b                              v152 = iadd.i64 v12, v149
                                    v902 = iconst.i64 16
                                    v903 = iadd v152, v902  ; v902 = 16
@15b5b                              v155 = load.i32 user2 little region4 v903
                                    v904 = iconst.i32 0
                                    v905 = icmp sge v155, v904  ; v904 = 0
@15b63                              brif v905, block13, block14

                                block13:
                                    v676 = load.i32 notrap aligned region14 v780
@15b67                              trapz v676, user16
@15b67                              v160 = uextend.i64 v676
@15b67                              v163 = iadd.i64 v12, v160
                                    v946 = iconst.i64 16
                                    v947 = iadd v163, v946  ; v946 = 16
@15b67                              v166 = load.i32 user2 little region4 v947
@15b73                              trapz v166, user16
@15b73                              v174 = uextend.i64 v166
@15b73                              v177 = iadd.i64 v12, v174
                                    v948 = iadd v177, v946  ; v946 = 16
@15b73                              v180 = load.i32 user2 readonly region4 v948
@15b73                              v181 = icmp.i32 ult v155, v180
@15b73                              trapz v181, user17
@15b73                              v183 = uextend.i64 v180
                                    v949 = iconst.i64 32
                                    v950 = ushr v183, v949  ; v949 = 32
@15b73                              trapnz v950, user2
                                    v951 = iconst.i32 20
@15b73                              v189 = uadd_overflow_trap v180, v951, user2  ; v951 = 20
@15b73                              v193 = uadd_overflow_trap v166, v189, user2
@15b73                              v194 = uextend.i64 v193
@15b73                              v197 = iadd.i64 v12, v194
@15b73                              v192 = iadd.i32 v155, v951  ; v951 = 20
@15b73                              v198 = isub v189, v192
@15b73                              v199 = uextend.i64 v198
@15b73                              v200 = isub v197, v199
@15b73                              v201 = load.i8 user2 little region4 v200
@15b73                              v202 = uextend.i32 v201
@15b76                              v203 = call fn2(v0, v0, v202), stack_map=[i32 @ ss0+0, i32 @ ss1+0, i32 @ ss2+0, i32 @ ss3+0]
                                    v668 = load.i32 notrap aligned region12 v767
@15b7f                              trapz v668, user16
@15b7f                              v205 = uextend.i64 v668
@15b7f                              v208 = iadd.i64 v12, v205
                                    v952 = iadd v208, v946  ; v946 = 16
@15b7f                              v211 = load.i64 user2 little region4 v952
                                    v839 = ishl v203, v3
@15b8a                              v215 = iadd v211, v839
@15b8b                              store user2 little region4 v215, v952
                                    v652 = load.i32 notrap aligned region13 v768
@15bb3                              trapz v652, user16
@15bb3                              v244 = uextend.i64 v652
@15bb3                              v247 = iadd.i64 v12, v244
                                    v953 = iadd v247, v946  ; v946 = 16
@15bb3                              v250 = load.i32 user2 little region4 v953
                                    v954 = iconst.i32 1
                                    v955 = isub v250, v954  ; v954 = 1
@15bbb                              store user2 little region4 v955, v953
                                    v640 = load.i32 notrap aligned region14 v780
@15bcc                              trapz v640, user16
@15bcc                              v267 = uextend.i64 v640
@15bcc                              v270 = iadd.i64 v12, v267
                                    v956 = iadd v270, v946  ; v946 = 16
@15bcc                              v273 = load.i32 user2 little region4 v956
@15bd1                              trapz v273, user16
@15bd1                              v274 = uextend.i64 v273
@15bd1                              v277 = iadd.i64 v12, v274
                                    v957 = iadd v277, v946  ; v946 = 16
@15bd1                              v280 = load.i32 user2 readonly region4 v957
@15bd3                              v281 = icmp slt v955, v280
@15bd4                              brif v281, block15, block17

                                block15:
@15bea                              v306 = icmp.i32 ult v955, v280
@15bea                              trapz v306, user17
@15bea                              v308 = uextend.i64 v280
                                    v965 = iconst.i64 32
                                    v966 = ushr v308, v965  ; v965 = 32
@15bea                              trapnz v966, user2
@15bea                              v314 = uadd_overflow_trap.i32 v280, v951, user2  ; v951 = 20
@15bea                              v318 = uadd_overflow_trap.i32 v273, v314, user2
                                    v967 = iconst.i64 0x6666_6666_6666_6667
                                    v968 = smulhi.i64 v215, v967  ; v967 = 0x6666_6666_6666_6667
                                    v969 = iconst.i64 2
                                    v970 = sshr v968, v969  ; v969 = 2
                                    v971 = iconst.i64 63
                                    v972 = ushr v970, v971  ; v971 = 63
                                    v973 = iadd v970, v972
                                    v974 = iconst.i64 10
                                    v975 = imul v973, v974  ; v974 = 10
                                    v976 = isub.i64 v215, v975
                                    v977 = ireduce.i32 v976
                                    v978 = iconst.i32 255
@15be9                              v298 = band v977, v978  ; v978 = 255
@15bea                              v319 = uextend.i64 v318
@15bea                              v322 = iadd.i64 v12, v319
                                    v979 = iconst.i32 19
                                    v865 = iadd.i32 v250, v979  ; v979 = 19
@15bea                              v323 = isub v314, v865
@15bea                              v324 = uextend.i64 v323
@15bea                              v325 = isub v322, v324
@15bea                              istore8 user2 little region4 v298, v325
@15bf0                              jump block16

                                block17:
                                    v958 = iconst.i64 0x6666_6666_6666_6667
                                    v841 = smulhi.i64 v215, v958  ; v958 = 0x6666_6666_6666_6667
                                    v959 = iconst.i64 2
                                    v842 = sshr v841, v959  ; v959 = 2
                                    v960 = iconst.i64 63
                                    v843 = ushr v842, v960  ; v960 = 63
                                    v844 = iadd v842, v843
                                    v231 -> v844
                                    v961 = iconst.i64 10
@15baa                              v240 = imul v844, v961  ; v961 = 10
@15bab                              v241 = isub.i64 v215, v240
@15bac                              v242 = ireduce.i32 v241
@15bf6                              brif v242, block18, block19

                                block18:
                                    v962 = iconst.i32 1
                                    v963 = iconst.i64 32
                                    v964 = iadd.i64 v270, v963  ; v963 = 32
@15bfc                              store user2 little region4 v962, v964  ; v962 = 1
@15c04                              jump block19

                                block19:
@15c08                              jump block16

                                block16:
                                    v980 = iconst.i64 0x6666_6666_6666_6667
                                    v981 = smulhi.i64 v215, v980  ; v980 = 0x6666_6666_6666_6667
                                    v982 = iconst.i64 2
                                    v983 = sshr v981, v982  ; v982 = 2
                                    v984 = iconst.i64 63
                                    v985 = ushr v983, v984  ; v984 = 63
                                    v986 = iadd v983, v985
@15c10                              store user2 little region4 v986, v952
                                    v620 = load.i32 notrap aligned region11 v773
@15c1c                              trapz v620, user16
@15c1c                              v353 = uextend.i64 v620
@15c1c                              v356 = iadd.i64 v12, v353
                                    v987 = iconst.i64 16
                                    v988 = iadd v356, v987  ; v987 = 16
@15c1c                              v359 = load.i32 user2 little region4 v988
                                    v989 = iconst.i32 1
                                    v990 = isub v359, v989  ; v989 = 1
@15c24                              store user2 little region4 v990, v988
@15c2c                              jump block11

                                block14:
@15c2f                              jump block12

                                block12:
@15c33                              jump block20

                                block20:
                                    v754 = load.i32 notrap aligned region12 v767
@15c37                              trapz v754, user16
@15c37                              v383 = uextend.i64 v754
@15c37                              v386 = iadd.i64 v12, v383
                                    v906 = iconst.i64 16
                                    v907 = iadd v386, v906  ; v906 = 16
@15c37                              v389 = load.i64 user2 little region4 v907
                                    v908 = iconst.i64 0
                                    v909 = icmp sgt v389, v908  ; v908 = 0
@15c3f                              brif v909, block22, block23

                                block22:
                                    v708 = load.i32 notrap aligned region13 v768
@15c61                              trapz v708, user16
@15c61                              v414 = uextend.i64 v708
@15c61                              v417 = iadd.i64 v12, v414
                                    v915 = iconst.i64 16
                                    v916 = iadd v417, v915  ; v915 = 16
@15c61                              v420 = load.i32 user2 little region4 v916
                                    v917 = iconst.i32 1
                                    v918 = isub v420, v917  ; v917 = 1
@15c69                              store user2 little region4 v918, v916
                                    v696 = load.i32 notrap aligned region14 v780
@15c7a                              trapz v696, user16
@15c7a                              v438 = uextend.i64 v696
@15c7a                              v441 = iadd.i64 v12, v438
                                    v919 = iadd v441, v915  ; v915 = 16
@15c7a                              v444 = load.i32 user2 little region4 v919
@15c7f                              trapz v444, user16
@15c7f                              v445 = uextend.i64 v444
@15c7f                              v448 = iadd.i64 v12, v445
                                    v920 = iadd v448, v915  ; v915 = 16
@15c7f                              v451 = load.i32 user2 readonly region4 v920
@15c81                              v452 = icmp slt v918, v451
@15c82                              brif v452, block24, block26

                                block24:
@15c98                              v477 = icmp.i32 ult v918, v451
@15c98                              trapz v477, user17
@15c98                              v479 = uextend.i64 v451
                                    v924 = iconst.i64 32
                                    v925 = ushr v479, v924  ; v924 = 32
@15c98                              trapnz v925, user2
@15c98                              v484 = iconst.i32 20
@15c98                              v485 = uadd_overflow_trap.i32 v451, v484, user2  ; v484 = 20
@15c98                              v489 = uadd_overflow_trap.i32 v444, v485, user2
                                    v926 = iconst.i64 0x6666_6666_6666_6667
                                    v927 = smulhi.i64 v389, v926  ; v926 = 0x6666_6666_6666_6667
                                    v928 = iconst.i64 2
                                    v929 = sshr v927, v928  ; v928 = 2
                                    v930 = iconst.i64 63
                                    v931 = ushr v929, v930  ; v930 = 63
                                    v932 = iadd v929, v931
                                    v933 = iconst.i64 10
                                    v934 = imul v932, v933  ; v933 = 10
                                    v935 = isub.i64 v389, v934
                                    v936 = ireduce.i32 v935
@15c94                              v468 = iconst.i32 255
@15c97                              v469 = band v936, v468  ; v468 = 255
@15c98                              v490 = uextend.i64 v489
@15c98                              v493 = iadd.i64 v12, v490
                                    v833 = iconst.i32 19
                                    v834 = iadd.i32 v420, v833  ; v833 = 19
@15c98                              v494 = isub v485, v834
@15c98                              v495 = uextend.i64 v494
@15c98                              v496 = isub v493, v495
@15c98                              istore8 user2 little region4 v469, v496
@15c9e                              jump block25

                                block26:
                                    v803 = iconst.i64 0x6666_6666_6666_6667
                                    v804 = smulhi.i64 v389, v803  ; v803 = 0x6666_6666_6666_6667
                                    v805 = iconst.i64 2
                                    v806 = sshr v804, v805  ; v805 = 2
                                    v807 = iconst.i64 63
                                    v808 = ushr v806, v807  ; v807 = 63
                                    v809 = iadd v806, v808
                                    v401 -> v809
@15c48                              v400 = iconst.i64 10
                                    v810 = imul v809, v400  ; v400 = 10
@15c59                              v411 = isub.i64 v389, v810
@15c5a                              v412 = ireduce.i32 v411
@15ca4                              brif v412, block27, block28

                                block27:
                                    v921 = iconst.i32 1
                                    v922 = iconst.i64 32
                                    v923 = iadd.i64 v441, v922  ; v922 = 32
@15caa                              store user2 little region4 v921, v923  ; v921 = 1
@15cb2                              jump block28

                                block28:
@15cb6                              jump block25

                                block25:
                                    v680 = load.i32 notrap aligned region12 v767
@15cbe                              trapz v680, user16
                                    v937 = iconst.i64 0x6666_6666_6666_6667
                                    v938 = smulhi.i64 v389, v937  ; v937 = 0x6666_6666_6666_6667
                                    v939 = iconst.i64 2
                                    v940 = sshr v938, v939  ; v939 = 2
                                    v941 = iconst.i64 63
                                    v942 = ushr v940, v941  ; v941 = 63
                                    v943 = iadd v940, v942
@15cbe                              v515 = uextend.i64 v680
@15cbe                              v518 = iadd.i64 v12, v515
                                    v944 = iconst.i64 16
                                    v945 = iadd v518, v944  ; v944 = 16
@15cbe                              store user2 little region4 v943, v945
@15cc6                              jump block20

                                block23:
@15cc9                              jump block21

                                block21:
                                    v750 = load.i32 notrap aligned region14 v780
@15cd1                              trapz v750, user16
@15cd1                              v527 = uextend.i64 v750
@15cd1                              v530 = iadd.i64 v12, v527
                                    v910 = iconst.i64 20
                                    v911 = iadd v530, v910  ; v910 = 20
@15cd1                              v533 = load.i32 user2 little region4 v911
@15cd8                              v542 = iadd v533, v9
@15cd9                              store user2 little region4 v542, v911
                                    v912 = iconst.i64 16
                                    v913 = iadd v530, v912  ; v912 = 16
@15cea                              v563 = load.i32 user2 little region4 v913
@15cef                              trapz v563, user16
@15cef                              v564 = uextend.i64 v563
@15cef                              v567 = iadd.i64 v12, v564
                                    v914 = iadd v567, v912  ; v912 = 16
@15cef                              v570 = load.i32 user2 readonly region4 v914
@15cf1                              v571 = icmp sgt v542, v570
@15cf2                              brif v571, block29, block30

                                block29:
@15cff                              store.i32 user2 little region4 v570, v911
@15d07                              jump block30

                                block30:
                                    v726 = load.i32 notrap aligned region14 v780
@15d0f                              trapz v726, user16
@15d0f                              v596 = uextend.i64 v726
@15d0f                              v599 = iadd.i64 v12, v596
@15d0f                              v600 = iconst.i64 24
@15d0f                              v601 = iadd v599, v600  ; v600 = 24
@15d0f                              v602 = load.i32 user2 little region4 v601
@15d16                              v604 = iadd v602, v9
@15d17                              store user2 little region4 v604, v601
@15d21                              v612 = call fn3(v0, v0, v726)
@15d24                              jump block1

                                block1:
@15d24                              return v612
}
```

### Wasmtime ARM64 machine code and stack maps

```asm
wasm[0]::function[454]::_M0MPC28internal7strconv7Decimal11left__shift:
            5f 23 03 d5                  pacibz
            fd 7b bf a9                  stp     x29, x30, [sp, #-0x10]!
            fd 03 00 91                  mov     x29, sp
            50 80 40 f8                  ldur    x16, [x2, #8]
            10 82 41 f8                  ldur    x16, [x16, #0x18]
            10 c2 01 91                  add     x16, x16, #0x70
            ff 63 30 eb                  cmp     sp, x16
            03 2a 00 54                  b.lo    #0x4e47c
            f9 0f 1f f8                  str     x25, [sp, #-0x10]!
            f7 63 bf a9                  stp     x23, x24, [sp, #-0x10]!
            f5 5b bf a9                  stp     x21, x22, [sp, #-0x10]!
            f3 53 bf a9                  stp     x19, x20, [sp, #-0x10]!
            ff 83 00 d1                  sub     sp, sp, #0x20
            f8 03 02 aa                  mov     x24, x2
            e4 03 00 b8                  stur    w4, [sp]
            f5 03 05 aa                  mov     x21, x5
            e3 03 18 aa                  mov     x3, x24
            67 01 00 94                  bl      #0x4e500
            f9 03 02 aa                  mov     x25, x2
                                          ╰─╼ stack_map: frame_size=96, frame_offsets=[0]
            e0 03 40 b8                  ldur    w0, [sp]
            80 28 00 34                  cbz     w0, #0x4e480
            e2 03 18 aa                  mov     x2, x24
            41 04 40 f9                  ldr     x1, [x2, #8]
            33 10 40 f9                  ldr     x19, [x1, #0x20]
            60 42 20 8b                  add     x0, x19, w0, uxtw
            14 14 40 b9                  ldr     w20, [x0, #0x14]
                                          ╰─╼ trap: GcHeapCorrupt
            56 10 40 f9                  ldr     x22, [x2, #0x20]
            c2 02 40 b9                  ldr     w2, [x22]
            e0 03 02 2a                  mov     w0, w2
            00 80 00 91                  add     x0, x0, #0x20
            c1 06 40 b9                  ldr     w1, [x22, #4]
            1f 00 01 eb                  cmp     x0, x1
            28 23 00 54                  b.hi    #0x4e404
            40 80 00 11                  add     w0, w2, #0x20
            c0 02 00 b9                  str     w0, [x22]
            41 00 80 52                  mov     w1, #2
            01 00 b6 72                  movk    w1, #0xb000, lsl #16
            60 42 22 8b                  add     x0, x19, w2, uxtw
            61 4a 22 b8                  str     w1, [x19, w2, uxtw]
                                          ╰─╼ trap: GcHeapCorrupt
            ed 03 18 aa                  mov     x13, x24
            a1 15 40 f9                  ldr     x1, [x13, #0x28]
            21 a0 40 b9                  ldr     w1, [x1, #0xa0]
            01 04 00 b9                  str     w1, [x0, #4]
                                          ╰─╼ trap: GcHeapCorrupt
            01 04 80 d2                  mov     x1, #0x20
            01 08 00 b9                  str     w1, [x0, #8]
                                          ╰─╼ trap: GcHeapCorrupt
            e2 83 00 b8                  stur    w2, [sp, #8]
            14 10 00 b9                  str     w20, [x0, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            e0 03 40 b8                  ldur    w0, [sp]
            20 25 00 34                  cbz     w0, #0x4e484
            60 42 20 8b                  add     x0, x19, w0, uxtw
            17 14 40 b9                  ldr     w23, [x0, #0x14]
                                          ╰─╼ trap: GcHeapCorrupt
            c2 02 40 b9                  ldr     w2, [x22]
            e0 03 02 2a                  mov     w0, w2
            00 80 00 91                  add     x0, x0, #0x20
            c1 06 40 b9                  ldr     w1, [x22, #4]
            1f 00 01 eb                  cmp     x0, x1
            68 21 00 54                  b.hi    #0x4e42c
            40 80 00 11                  add     w0, w2, #0x20
            c0 02 00 b9                  str     w0, [x22]
            41 00 80 52                  mov     w1, #2
            01 00 b6 72                  movk    w1, #0xb000, lsl #16
            60 42 22 8b                  add     x0, x19, w2, uxtw
            61 4a 22 b8                  str     w1, [x19, w2, uxtw]
                                          ╰─╼ trap: GcHeapCorrupt
            e1 03 18 aa                  mov     x1, x24
            21 14 40 f9                  ldr     x1, [x1, #0x28]
            21 a0 40 b9                  ldr     w1, [x1, #0xa0]
            01 04 00 b9                  str     w1, [x0, #4]
                                          ╰─╼ trap: GcHeapCorrupt
            01 04 80 d2                  mov     x1, #0x20
            01 08 00 b9                  str     w1, [x0, #8]
                                          ╰─╼ trap: GcHeapCorrupt
            e2 03 01 b8                  stur    w2, [sp, #0x10]
            f4 03 19 aa                  mov     x20, x25
            e1 02 14 0b                  add     w1, w23, w20
            01 10 00 b9                  str     w1, [x0, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            c2 02 40 b9                  ldr     w2, [x22]
            e0 03 02 2a                  mov     w0, w2
            00 80 00 91                  add     x0, x0, #0x20
            c1 06 40 b9                  ldr     w1, [x22, #4]
            1f 00 01 eb                  cmp     x0, x1
            e8 1f 00 54                  b.hi    #0x4e454
            40 80 00 11                  add     w0, w2, #0x20
            c0 02 00 b9                  str     w0, [x22]
            41 00 80 52                  mov     w1, #2
            01 00 b6 72                  movk    w1, #0xb000, lsl #16
            60 42 22 8b                  add     x0, x19, w2, uxtw
            61 4a 22 b8                  str     w1, [x19, w2, uxtw]
                                          ╰─╼ trap: GcHeapCorrupt
            e1 03 18 aa                  mov     x1, x24
            21 14 40 f9                  ldr     x1, [x1, #0x28]
            21 44 46 b9                  ldr     w1, [x1, #0x644]
            01 04 00 b9                  str     w1, [x0, #4]
                                          ╰─╼ trap: GcHeapCorrupt
            01 04 80 d2                  mov     x1, #0x20
            01 08 00 b9                  str     w1, [x0, #8]
                                          ╰─╼ trap: GcHeapCorrupt
            e2 83 01 b8                  stur    w2, [sp, #0x18]
            03 00 80 d2                  mov     x3, #0
            03 08 00 f9                  str     x3, [x0, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            e4 83 40 b8                  ldur    w4, [sp, #8]
            64 1f 00 34                  cbz     w4, #0x4e488
            65 42 24 8b                  add     x5, x19, w4, uxtw
            a6 10 40 b9                  ldr     w6, [x5, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            c6 04 00 51                  sub     w6, w6, #1
            a6 10 00 b9                  str     w6, [x5, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            e7 83 40 b8                  ldur    w7, [sp, #8]
            c7 1e 00 34                  cbz     w7, #0x4e48c
            68 42 27 8b                  add     x8, x19, w7, uxtw
            08 11 40 b9                  ldr     w8, [x8, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            1f 01 00 71                  cmp     w8, #0
            2a 0d 00 54                  b.ge    #0x4e268
            ec 83 41 b8                  ldur    w12, [sp, #0x18]
            2c 1e 00 34                  cbz     w12, #0x4e490
            6d 42 2c 8b                  add     x13, x19, w12, uxtw
            ad 09 40 f9                  ldr     x13, [x13, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            bf 01 00 f1                  cmp     x13, #0
            ec 03 00 54                  b.gt    #0x4e158
            e0 03 40 b8                  ldur    w0, [sp]
            80 1d 00 34                  cbz     w0, #0x4e494
            60 42 20 8b                  add     x0, x19, w0, uxtw
            01 14 40 b9                  ldr     w1, [x0, #0x14]
                                          ╰─╼ trap: GcHeapCorrupt
            21 00 14 0b                  add     w1, w1, w20
            01 14 00 b9                  str     w1, [x0, #0x14]
                                          ╰─╼ trap: GcHeapCorrupt
            02 10 40 b9                  ldr     w2, [x0, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            e2 1c 00 34                  cbz     w2, #0x4e498
            62 42 22 8b                  add     x2, x19, w2, uxtw
            42 10 40 b9                  ldr     w2, [x2, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            3f 00 02 6b                  cmp     w1, w2
            4d 00 00 54                  b.le    #0x4e114
            02 14 00 b9                  str     w2, [x0, #0x14]
                                          ╰─╼ trap: GcHeapCorrupt
            e4 03 40 b8                  ldur    w4, [sp]
            24 1c 00 34                  cbz     w4, #0x4e49c
            60 42 24 8b                  add     x0, x19, w4, uxtw
            01 18 40 b9                  ldr     w1, [x0, #0x18]
                                          ╰─╼ trap: GcHeapCorrupt
            21 00 14 0b                  add     w1, w1, w20
            01 18 00 b9                  str     w1, [x0, #0x18]
                                          ╰─╼ trap: GcHeapCorrupt
            e3 03 18 aa                  mov     x3, x24
            e2 03 03 aa                  mov     x2, x3
            1b 07 00 94                  bl      #0x4fda0
            ff 83 00 91                  add     sp, sp, #0x20
            f3 53 c1 a8                  ldp     x19, x20, [sp], #0x10
            f5 5b c1 a8                  ldp     x21, x22, [sp], #0x10
            f7 63 c1 a8                  ldp     x23, x24, [sp], #0x10
            f9 07 41 f8                  ldr     x25, [sp], #0x10
            fd 7b c1 a8                  ldp     x29, x30, [sp], #0x10
            df 23 03 d5                  autibz
            c0 03 5f d6                  ret
            e0 03 41 b8                  ldur    w0, [sp, #0x10]
            20 1a 00 34                  cbz     w0, #0x4e4a0
            61 42 20 8b                  add     x1, x19, w0, uxtw
            20 10 40 b9                  ldr     w0, [x1, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            03 04 00 51                  sub     w3, w0, #1
            23 10 00 b9                  str     w3, [x1, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            e1 03 40 b8                  ldur    w1, [sp]
            81 19 00 34                  cbz     w1, #0x4e4a4
            61 42 21 8b                  add     x1, x19, w1, uxtw
            22 10 40 b9                  ldr     w2, [x1, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            42 19 00 34                  cbz     w2, #0x4e4a8
            64 42 22 8b                  add     x4, x19, w2, uxtw
            84 10 40 b9                  ldr     w4, [x4, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            7f 00 04 6b                  cmp     w3, w4
            eb 01 00 54                  b.lt    #0x4e1cc
            e0 cc 8c d2                  mov     x0, #0x6667
            c0 cc ac f2                  movk    x0, #0x6666, lsl #16
            c0 cc cc f2                  movk    x0, #0x6666, lsl #32
            c0 cc ec f2                  movk    x0, #0x6666, lsl #48
            a0 7d 40 9b                  smulh   x0, x13, x0
            00 fc 42 93                  asr     x0, x0, #2
            02 fc 7f d3                  lsr     x2, x0, #0x3f
            00 00 02 8b                  add     x0, x0, x2
            42 01 80 d2                  mov     x2, #0xa
            00 b4 02 9b                  msub    x0, x0, x2, x13
            c0 03 00 34                  cbz     w0, #0x4e234
            20 00 80 52                  mov     w0, #1
            20 20 00 b9                  str     w0, [x1, #0x20]
                                          ╰─╼ trap: GcHeapCorrupt
            1b 00 00 14                  b       #0x4e234
            7f 00 04 6b                  cmp     w3, w4
            e2 16 00 54                  b.hs    #0x4e4ac
            e1 03 04 2a                  mov     w1, w4
            21 fc 60 d3                  lsr     x1, x1, #0x20
            a1 16 00 b5                  cbnz    x1, #0x4e4b0
            81 02 80 52                  mov     w1, #0x14
            81 00 01 2b                  adds    w1, w4, w1
            62 16 00 54                  b.hs    #0x4e4b4
            42 00 01 2b                  adds    w2, w2, w1
            42 16 00 54                  b.hs    #0x4e4b8
            e3 cc 8c d2                  mov     x3, #0x6667
            c3 cc ac f2                  movk    x3, #0x6666, lsl #16
            c3 cc cc f2                  movk    x3, #0x6666, lsl #32
            c3 cc ec f2                  movk    x3, #0x6666, lsl #48
            a3 7d 43 9b                  smulh   x3, x13, x3
            63 fc 42 93                  asr     x3, x3, #2
            64 fc 7f d3                  lsr     x4, x3, #0x3f
            63 00 04 8b                  add     x3, x3, x4
            44 01 80 d2                  mov     x4, #0xa
            63 b4 04 9b                  msub    x3, x3, x4, x13
            63 1c 00 12                  and     w3, w3, #0xff
            62 42 22 8b                  add     x2, x19, w2, uxtw
            00 4c 00 11                  add     w0, w0, #0x13
            20 00 00 4b                  sub     w0, w1, w0
            40 40 20 cb                  sub     x0, x2, w0, uxtw
            03 00 00 39                  strb    w3, [x0]
                                          ╰─╼ trap: GcHeapCorrupt
            e0 83 41 b8                  ldur    w0, [sp, #0x18]
            20 14 00 34                  cbz     w0, #0x4e4bc
            e1 cc 8c d2                  mov     x1, #0x6667
            c1 cc ac f2                  movk    x1, #0x6666, lsl #16
            c1 cc cc f2                  movk    x1, #0x6666, lsl #32
            c1 cc ec f2                  movk    x1, #0x6666, lsl #48
            a1 7d 41 9b                  smulh   x1, x13, x1
            21 fc 42 93                  asr     x1, x1, #2
            22 fc 7f d3                  lsr     x2, x1, #0x3f
            21 00 02 8b                  add     x1, x1, x2
            60 42 20 8b                  add     x0, x19, w0, uxtw
            01 08 00 f9                  str     x1, [x0, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            99 ff ff 17                  b       #0x4e0c8
            e0 03 40 b8                  ldur    w0, [sp]
            a0 12 00 34                  cbz     w0, #0x4e4c0
            60 42 20 8b                  add     x0, x19, w0, uxtw
            00 10 40 b9                  ldr     w0, [x0, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            60 12 00 34                  cbz     w0, #0x4e4c4
            61 42 20 8b                  add     x1, x19, w0, uxtw
            21 10 40 b9                  ldr     w1, [x1, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            1f 01 01 6b                  cmp     w8, w1
            02 12 00 54                  b.hs    #0x4e4c8
            e2 03 01 2a                  mov     w2, w1
            42 fc 60 d3                  lsr     x2, x2, #0x20
            c2 11 00 b5                  cbnz    x2, #0x4e4cc
            96 02 80 52                  mov     w22, #0x14
            21 00 16 2b                  adds    w1, w1, w22
            82 11 00 54                  b.hs    #0x4e4d0
            00 00 01 2b                  adds    w0, w0, w1
            62 11 00 54                  b.hs    #0x4e4d4
            60 42 20 8b                  add     x0, x19, w0, uxtw
            02 51 00 11                  add     w2, w8, #0x14
            21 00 02 4b                  sub     w1, w1, w2
            00 40 21 cb                  sub     x0, x0, w1, uxtw
            00 00 40 39                  ldrb    w0, [x0]
                                          ╰─╼ trap: GcHeapCorrupt
            04 1c 00 53                  uxtb    w4, w0
            e2 03 18 aa                  mov     x2, x24
            e3 03 18 aa                  mov     x3, x24
            65 8d 00 94                  bl      #0x71860
            e0 83 41 b8                  ldur    w0, [sp, #0x18]
                                          ╰─╼ stack_map: frame_size=96, frame_offsets=[0, 8, 16, 24]
            20 10 00 34                  cbz     w0, #0x4e4d8
            60 42 20 8b                  add     x0, x19, w0, uxtw
            01 08 40 f9                  ldr     x1, [x0, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            42 20 d5 9a                  lsl     x2, x2, x21
            21 00 02 8b                  add     x1, x1, x2
            01 08 00 f9                  str     x1, [x0, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            e2 03 41 b8                  ldur    w2, [sp, #0x10]
            62 0f 00 34                  cbz     w2, #0x4e4dc
            63 42 22 8b                  add     x3, x19, w2, uxtw
            62 10 40 b9                  ldr     w2, [x3, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            45 04 00 51                  sub     w5, w2, #1
            65 10 00 b9                  str     w5, [x3, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            e3 03 40 b8                  ldur    w3, [sp]
            c3 0e 00 34                  cbz     w3, #0x4e4e0
            63 42 23 8b                  add     x3, x19, w3, uxtw
            64 10 40 b9                  ldr     w4, [x3, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            84 0e 00 34                  cbz     w4, #0x4e4e4
            66 42 24 8b                  add     x6, x19, w4, uxtw
            c6 10 40 b9                  ldr     w6, [x6, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            bf 00 06 6b                  cmp     w5, w6
            eb 01 00 54                  b.lt    #0x4e360
            e2 cc 8c d2                  mov     x2, #0x6667
            c2 cc ac f2                  movk    x2, #0x6666, lsl #16
            c2 cc cc f2                  movk    x2, #0x6666, lsl #32
            c2 cc ec f2                  movk    x2, #0x6666, lsl #48
            22 7c 42 9b                  smulh   x2, x1, x2
            42 fc 42 93                  asr     x2, x2, #2
            44 fc 7f d3                  lsr     x4, x2, #0x3f
            42 00 04 8b                  add     x2, x2, x4
            44 01 80 d2                  mov     x4, #0xa
            42 84 04 9b                  msub    x2, x2, x4, x1
            a2 03 00 34                  cbz     w2, #0x4e3c4
            24 00 80 52                  mov     w4, #1
            64 20 00 b9                  str     w4, [x3, #0x20]
                                          ╰─╼ trap: GcHeapCorrupt
            1a 00 00 14                  b       #0x4e3c4
            bf 00 06 6b                  cmp     w5, w6
            22 0c 00 54                  b.hs    #0x4e4e8
            e8 03 06 2a                  mov     w8, w6
            08 fd 60 d3                  lsr     x8, x8, #0x20
            e8 0b 00 b5                  cbnz    x8, #0x4e4ec
            c9 00 16 2b                  adds    w9, w6, w22
            c2 0b 00 54                  b.hs    #0x4e4f0
            8a 00 09 2b                  adds    w10, w4, w9
            a2 0b 00 54                  b.hs    #0x4e4f4
            eb cc 8c d2                  mov     x11, #0x6667
            cb cc ac f2                  movk    x11, #0x6666, lsl #16
            cb cc cc f2                  movk    x11, #0x6666, lsl #32
            cb cc ec f2                  movk    x11, #0x6666, lsl #48
            2b 7c 4b 9b                  smulh   x11, x1, x11
            6b fd 42 93                  asr     x11, x11, #2
            6c fd 7f d3                  lsr     x12, x11, #0x3f
            6b 01 0c 8b                  add     x11, x11, x12
            4c 01 80 d2                  mov     x12, #0xa
            6b 85 0c 9b                  msub    x11, x11, x12, x1
            6b 1d 00 12                  and     w11, w11, #0xff
            6c 42 2a 8b                  add     x12, x19, w10, uxtw
            4d 4c 00 11                  add     w13, w2, #0x13
            2d 01 0d 4b                  sub     w13, w9, w13
            8c 41 2d cb                  sub     x12, x12, w13, uxtw
            8b 01 00 39                  strb    w11, [x12]
                                          ╰─╼ trap: GcHeapCorrupt
            ed cc 8c d2                  mov     x13, #0x6667
            cd cc ac f2                  movk    x13, #0x6666, lsl #16
            cd cc cc f2                  movk    x13, #0x6666, lsl #32
            cd cc ec f2                  movk    x13, #0x6666, lsl #48
            2d 7c 4d 9b                  smulh   x13, x1, x13
            ad fd 42 93                  asr     x13, x13, #2
            ae fd 7f d3                  lsr     x14, x13, #0x3f
            ad 01 0e 8b                  add     x13, x13, x14
            0d 08 00 f9                  str     x13, [x0, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            ee 83 40 b8                  ldur    w14, [sp, #8]
            6e 08 00 34                  cbz     w14, #0x4e4f8
            6f 42 2e 8b                  add     x15, x19, w14, uxtw
            e0 11 40 b9                  ldr     w0, [x15, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            00 04 00 51                  sub     w0, w0, #1
            e0 11 00 b9                  str     w0, [x15, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            2c ff ff 17                  b       #0x4e0b0
            43 00 80 52                  mov     w3, #2
            03 00 b6 72                  movk    w3, #0xb000, lsl #16
            e2 03 18 aa                  mov     x2, x24
            40 14 40 f9                  ldr     x0, [x2, #0x28]
            04 a0 40 b9                  ldr     w4, [x0, #0xa0]
            05 04 80 52                  mov     w5, #0x20
            06 02 80 52                  mov     w6, #0x10
            78 7d 02 94                  bl      #0xeda00
            60 42 22 8b                  add     x0, x19, w2, uxtw
                                          ╰─╼ stack_map: frame_size=96, frame_offsets=[0]
            eb fe ff 17                  b       #0x4dfd4
            43 00 80 52                  mov     w3, #2
            03 00 b6 72                  movk    w3, #0xb000, lsl #16
            e2 03 18 aa                  mov     x2, x24
            40 14 40 f9                  ldr     x0, [x2, #0x28]
            04 a0 40 b9                  ldr     w4, [x0, #0xa0]
            05 04 80 52                  mov     w5, #0x20
            06 02 80 52                  mov     w6, #0x10
            6e 7d 02 94                  bl      #0xeda00
            60 42 22 8b                  add     x0, x19, w2, uxtw
                                          ╰─╼ stack_map: frame_size=96, frame_offsets=[0, 8]
            f9 fe ff 17                  b       #0x4e034
            43 00 80 52                  mov     w3, #2
            03 00 b6 72                  movk    w3, #0xb000, lsl #16
            e2 03 18 aa                  mov     x2, x24
            40 14 40 f9                  ldr     x0, [x2, #0x28]
            04 44 46 b9                  ldr     w4, [x0, #0x644]
            05 04 80 52                  mov     w5, #0x20
            06 02 80 52                  mov     w6, #0x10
            64 7d 02 94                  bl      #0xeda00
            60 42 22 8b                  add     x0, x19, w2, uxtw
                                          ╰─╼ stack_map: frame_size=96, frame_offsets=[0, 8, 16]
            05 ff ff 17                  b       #0x4e08c
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: Normal(StackOverflow)
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: Normal(NullReference)
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: Normal(NullReference)
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: Normal(NullReference)
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: Normal(NullReference)
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: Normal(NullReference)
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: Normal(NullReference)
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: Normal(NullReference)
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: Normal(NullReference)
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: Normal(NullReference)
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: Normal(NullReference)
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: Normal(NullReference)
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: Normal(ArrayOutOfBounds)
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: GcHeapCorrupt
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: GcHeapCorrupt
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: GcHeapCorrupt
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: Normal(NullReference)
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: Normal(NullReference)
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: Normal(NullReference)
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: Normal(ArrayOutOfBounds)
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: GcHeapCorrupt
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: GcHeapCorrupt
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: GcHeapCorrupt
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: Normal(NullReference)
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: Normal(NullReference)
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: Normal(NullReference)
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: Normal(NullReference)
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: Normal(ArrayOutOfBounds)
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: GcHeapCorrupt
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: GcHeapCorrupt
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: GcHeapCorrupt
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: Normal(NullReference)
```

### V8 final optimized Turboshaft IR

Node IDs, dependencies, properties and representations come from the emitted graph; not reconstructed from source.

```text
B0 #0 Parameter() [0] [Tagged]
B0 #1 Parameter() [1] [Tagged]
B0 #3 Parameter() [2] [Word32]
B0 #4 Load(#0) [tagged base, TaggedPointer, Tagged, offset: 240] [Tagged]
B0 #5 Constant() [word64: 0] [Word64]
B0 #6 Constant() [word32: 0] [Word32]
B0 #7 WasmStackCheck() [function-entry] []
B0 #8 Load(#0) [tagged base, TaggedPointer, Tagged, offset: 192] [Tagged]
B0 #9 Load(#8) [tagged base, AnyTagged, Tagged, offset: 104] [Tagged]
B0 #10 LoadRootRegister()  [Word64]
B0 #11 Load(#10) [raw, TaggedPointer, Tagged, offset: 1848] [Tagged]
B0 #12 Comparison(#9, #11) [Equal, Tagged] [Word32]
B0 #13 TrapIf(#12) [0, TrapNullDereference] []
B0 #14 Load(#9) [tagged base, Int32, Word32, offset: 16] [Word32]
B0 #15 Comparison(#3, #14) [UnsignedLessThan, Word32] [Word32]
B0 #16 TrapIf(#15) [1, TrapArrayOutOfBounds] []
B0 #17 Change(#3) [SignExtend, NoAssumption, Word32, Word64] [Word64]
B0 #18 Load(#9, #17) [tagged base, AnyTagged, Tagged, element size: 2^3, offset: 24] [Tagged]
B0 #20 Comparison(#18, #11) [Equal, Tagged] [Word32]
B0 #21 TrapIf(#20) [0, TrapNullDereference] []
B0 #22 Load(#18) [tagged base, Int32, Word32, offset: 16] [Word32]
B0 #23 Load(#18) [tagged base, AnyTagged, Tagged, offset: 24] [Tagged]
B0 #24 Load(#23) [tagged base, Int32, Word32, offset: 16] [Word32]
B0 #25 Comparison(#6, #24) [SignedLessThan, Word32] [Word32]
B0 #26 Branch(#25) [B1, B39, None] []
B1 #28 Comparison(#6, #24) [UnsignedLessThan, Word32] [Word32]
B1 #29 TrapIf(#28) [1, TrapArrayOutOfBounds] []
B1 #30 Load(#23) [tagged base, Uint16, Word32, offset: 24] [Word32]
B1 #31 Load(#1) [tagged base, Int32, Word32, offset: 24] [Word32]
B1 #32 Comparison(#31, #6) [SignedLessThanOrEqual, Word32] [Word32]
B1 #33 Branch(#32) [B35, B2, None] []
B2 #35 Constant() [word32: -48] [Word32]
B2 #36 WordBinop(#30, #35) [Add, Word32] [Word32]
B2 #37 Load(#1) [tagged base, AnyTagged, Tagged, offset: 16] [Tagged]
B2 #38 Load(#37) [tagged base, Int32, Word32, offset: 16] [Word32]
B2 #39 Comparison(#6, #38) [UnsignedLessThan, Word32] [Word32]
B2 #40 TrapIf(#39) [1, TrapArrayOutOfBounds] []
B2 #41 Load(#37) [tagged base, Uint8, Word32, offset: 24] [Word32]
B2 #42 Comparison(#41, #36) [Equal, Word32] [Word32]
B2 #43 Branch(#42) [B3, B32, None] []
B3 #45 Constant() [word32: 1] [Word32]
B3 #46 Goto() [B4, 0] []
B4 #47 Phi(#45, #133) [Word32] [Word32]
B4 #48 Comparison(#47, #24) [SignedLessThan, Word32] [Word32]
B4 #49 Branch(#48) [B5, B30, None] []
B5 #51 Comparison(#47, #24) [UnsignedLessThan, Word32] [Word32]
B5 #52 TrapIf(#51) [1, TrapArrayOutOfBounds] []
B5 #53 Change(#47) [SignExtend, NoAssumption, Word32, Word64] [Word64]
B5 #54 Load(#23, #53) [tagged base, Uint16, Word32, element size: 2^1, offset: 24] [Word32]
B5 #55 Comparison(#31, #47) [SignedLessThanOrEqual, Word32] [Word32]
B5 #56 Branch(#55) [B28, B6, None] []
B6 #58 WordBinop(#54, #35) [Add, Word32] [Word32]
B6 #59 Comparison(#47, #38) [UnsignedLessThan, Word32] [Word32]
B6 #60 TrapIf(#59) [1, TrapArrayOutOfBounds] []
B6 #61 Load(#37, #53) [tagged base, Uint8, Word32, offset: 24] [Word32]
B6 #63 Comparison(#61, #58) [Equal, Word32] [Word32]
B6 #64 Branch(#63) [B7, B26, None] []
B7 #66 WordBinop(#47, #45) [Add, Word32] [Word32]
B7 #67 Comparison(#66, #24) [SignedLessThan, Word32] [Word32]
B7 #68 Branch(#67) [B9, B8, None] []
B8 #70 Goto() [B31, 0] []
B9 #71 Comparison(#66, #24) [UnsignedLessThan, Word32] [Word32]
B9 #72 TrapIf(#71) [1, TrapArrayOutOfBounds] []
B9 #73 Change(#66) [SignExtend, NoAssumption, Word32, Word64] [Word64]
B9 #74 Load(#23, #73) [tagged base, Uint16, Word32, element size: 2^1, offset: 24] [Word32]
B9 #75 Comparison(#31, #66) [SignedLessThanOrEqual, Word32] [Word32]
B9 #76 Branch(#75) [B10, B11, None] []
B10 #78 Goto() [B29, 0] []
B11 #79 WordBinop(#74, #35) [Add, Word32] [Word32]
B11 #80 Comparison(#66, #38) [UnsignedLessThan, Word32] [Word32]
B11 #81 TrapIf(#80) [1, TrapArrayOutOfBounds] []
B11 #82 Load(#37, #73) [tagged base, Uint8, Word32, offset: 24] [Word32]
B11 #84 Comparison(#82, #79) [Equal, Word32] [Word32]
B11 #85 Branch(#84) [B13, B12, None] []
B12 #87 Goto() [B27, 0] []
B13 #88 WordBinop(#66, #45) [Add, Word32] [Word32]
B13 #89 Comparison(#88, #24) [SignedLessThan, Word32] [Word32]
B13 #90 Branch(#89) [B15, B14, None] []
B14 #92 Goto() [B31, 0] []
B15 #93 Comparison(#88, #24) [UnsignedLessThan, Word32] [Word32]
B15 #94 TrapIf(#93) [1, TrapArrayOutOfBounds] []
B15 #95 Change(#88) [SignExtend, NoAssumption, Word32, Word64] [Word64]
B15 #96 Load(#23, #95) [tagged base, Uint16, Word32, element size: 2^1, offset: 24] [Word32]
B15 #97 Comparison(#31, #88) [SignedLessThanOrEqual, Word32] [Word32]
B15 #98 Branch(#97) [B16, B17, None] []
B16 #100 Goto() [B29, 0] []
B17 #101 WordBinop(#96, #35) [Add, Word32] [Word32]
B17 #102 Comparison(#88, #38) [UnsignedLessThan, Word32] [Word32]
B17 #103 TrapIf(#102) [1, TrapArrayOutOfBounds] []
B17 #104 Load(#37, #95) [tagged base, Uint8, Word32, offset: 24] [Word32]
B17 #106 Comparison(#104, #101) [Equal, Word32] [Word32]
B17 #107 Branch(#106) [B19, B18, None] []
B18 #109 Goto() [B27, 0] []
B19 #110 WordBinop(#88, #45) [Add, Word32] [Word32]
B19 #111 WasmStackCheck() [loop] []
B19 #112 Comparison(#110, #24) [SignedLessThan, Word32] [Word32]
B19 #113 Branch(#112) [B21, B20, None] []
B20 #115 Goto() [B31, 0] []
B21 #116 Comparison(#110, #24) [UnsignedLessThan, Word32] [Word32]
B21 #117 TrapIf(#116) [1, TrapArrayOutOfBounds] []
B21 #118 Change(#110) [SignExtend, NoAssumption, Word32, Word64] [Word64]
B21 #119 Load(#23, #118) [tagged base, Uint16, Word32, element size: 2^1, offset: 24] [Word32]
B21 #120 Comparison(#31, #110) [SignedLessThanOrEqual, Word32] [Word32]
B21 #121 Branch(#120) [B22, B23, None] []
B22 #123 Goto() [B29, 0] []
B23 #124 WordBinop(#119, #35) [Add, Word32] [Word32]
B23 #125 Comparison(#110, #38) [UnsignedLessThan, Word32] [Word32]
B23 #126 TrapIf(#125) [1, TrapArrayOutOfBounds] []
B23 #127 Load(#37, #118) [tagged base, Uint8, Word32, offset: 24] [Word32]
B23 #129 Comparison(#127, #124) [Equal, Word32] [Word32]
B23 #130 Branch(#129) [B25, B24, None] []
B24 #132 Goto() [B27, 0] []
B25 #133 WordBinop(#110, #45) [Add, Word32] [Word32]
B25 #134 Goto() [B4, 1] []
B26 #135 Goto() [B27, 0] []
B27 #136 Phi(#79, #101, #124, #58) [Word32] [Word32]
B27 #137 Phi(#66, #88, #110, #47) [Word32] [Word32]
B27 #139 Goto() [B33, 0] []
B28 #140 Goto() [B29, 0] []
B29 #141 Goto() [B36, 0] []
B30 #142 Goto() [B31, 0] []
B31 #143 Goto() [B40, 0] []
B32 #144 Goto() [B33, 0] []
B33 #145 Phi(#136, #36) [Word32] [Word32]
B33 #146 Phi(#137, #6) [Word32] [Word32]
B33 #147 Comparison(#146, #38) [UnsignedLessThan, Word32] [Word32]
B33 #148 TrapIf(#147) [1, TrapArrayOutOfBounds] []
B33 #149 Change(#146) [SignExtend, NoAssumption, Word32, Word64] [Word64]
B33 #150 Load(#37, #149) [tagged base, Uint8, Word32, offset: 24] [Word32]
B33 #151 Comparison(#150, #145) [SignedLessThan, Word32] [Word32]
B33 #152 Goto() [B34, 0] []
B34 #153 Branch(#151) [B38, B42, None] []
B35 #155 Goto() [B36, 0] []
B36 #156 Constant() [word32: 1] [Word32]
B36 #157 Goto() [B37, 0] []
B37 #158 Goto() [B43, 0] []
B38 #159 Goto() [B43, 0] []
B39 #160 Goto() [B40, 0] []
B40 #161 Goto() [B41, 0] []
B41 #162 Goto() [B44, 0] []
B42 #163 Goto() [B44, 0] []
B43 #164 Phi(#151, #156) [Word32] [Word32]
B43 #165 Constant() [word32: -1] [Word32]
B43 #166 WordBinop(#22, #165) [Add, Word32] [Word32]
B43 #167 Goto() [B45, 0] []
B44 #168 Phi(#151, #6) [Word32] [Word32]
B44 #169 Goto() [B45, 0] []
B45 #170 Phi(#164, #168) [Word32] [Word32]
B45 #171 Phi(#166, #22) [Word32] [Word32]
B45 #172 Load(#1) [tagged base, Int32, Word32, offset: 24] [Word32]
B45 #173 Load(#4) [tagged base, AnyTagged, Tagged, offset: 2440] [Tagged]
B45 #174 Constant() [word64: 24] [Word64]
B45 #175 Load(#0) [tagged base, Uint64, Word64, offset: 72] [Word64]
B45 #176 Load(#175) [raw, Uint64, Word64] [Word64]
B45 #177 Constant() [number: 128] [Tagged]
B45 #178 Load(#0) [tagged base, Uint64, Word64, offset: 64] [Word64]
B45 #179 Constant() [word64: 131072] [Word64]
B45 #180 Constant() [word32: 1] [Word32]
B45 #181 Goto() [B46, 0] []
B46 #182 Load(#178) [raw, Uint64, Word64] [Word64]
B46 #183 WordBinop(#176, #174) [Add, Word64] [Word64]
B46 #184 Comparison(#183, #182) [UnsignedLessThan, Word64] [Word32]
B46 #185 Branch(#184) [B48, B47, True] []
B47 #187 Call(#177, #174) [BuiltinPointer:Allocate Descriptor:r1s0i2f0] []
B47 #189 DidntThrow(#187) [🁫🁫 🁫🁫 🁤🁪 🁫 i a, 0] [Tagged]
B47 #191 TaggedBitcast(#189) [Tagged, Word64, HeapObject] [Word64]
B47 #192 Constant() [word64: 1] [Word64]
B47 #193 Constant() [word64: -1] [Word64]
B47 #194 WordBinop(#191, #193) [Add, Word64] [Word64]
B47 #195 Goto() [B49, 0] []
B48 #196 Goto() [B49, 0] []
B49 #197 Phi(#176, #194) [Word64] [Word64]
B49 #198 WordBinop(#197, #174) [Add, Word64] [Word64]
B49 #199 Store(#175, #198) [raw, Uint64, NoWriteBarrier] []
B49 #201 Constant() [word64: 1] [Word64]
B49 #202 WordBinop(#197, #201) [Add, Word64] [Word64]
B49 #203 TaggedBitcast(#202) [Word64, Tagged, HeapObject] [Tagged]
B49 #204 Store(#203, #173) [tagged base, TaggedPointer, NoWriteBarrier, initializing] []
B49 #205 Load(#10) [raw, Uint64, Word64, offset: 608] [Word64]
B49 #206 Store(#203, #205) [tagged base, AnyTagged, NoWriteBarrier, offset: 8, initializing] []
B49 #208 Store(#203, #172) [tagged base, Int32, NoWriteBarrier, offset: 16] []
B49 #209 WordBinop(#172, #171) [Add, Word32] [Word32]
B49 #210 Load(#0) [tagged base, Uint64, Word64, offset: 72] [Word64]
B49 #211 Load(#210) [raw, Uint64, Word64] [Word64]
B49 #212 Load(#0) [tagged base, Uint64, Word64, offset: 64] [Word64]
B49 #213 Goto() [B50, 0] []
B50 #214 Load(#212) [raw, Uint64, Word64] [Word64]
B50 #215 WordBinop(#211, #174) [Add, Word64] [Word64]
B50 #216 Comparison(#215, #214) [UnsignedLessThan, Word64] [Word32]
B50 #217 Branch(#216) [B52, B51, True] []
B51 #219 Call(#177, #174) [BuiltinPointer:Allocate Descriptor:r1s0i2f0] []
B51 #221 DidntThrow(#219) [🁫🁫 🁫🁫 🁤🁪 🁫 i a, 0] [Tagged]
B51 #223 TaggedBitcast(#221) [Tagged, Word64, HeapObject] [Word64]
B51 #224 Constant() [word64: -1] [Word64]
B51 #225 WordBinop(#223, #224) [Add, Word64] [Word64]
B51 #226 Goto() [B53, 0] []
B52 #227 Goto() [B53, 0] []
B53 #228 Phi(#211, #225) [Word64] [Word64]
B53 #229 WordBinop(#228, #174) [Add, Word64] [Word64]
B53 #230 Store(#210, #229) [raw, Uint64, NoWriteBarrier] []
B53 #232 WordBinop(#228, #201) [Add, Word64] [Word64]
B53 #233 TaggedBitcast(#232) [Word64, Tagged, HeapObject] [Tagged]
B53 #234 Store(#233, #173) [tagged base, TaggedPointer, NoWriteBarrier, initializing] []
B53 #235 Load(#10) [raw, Uint64, Word64, offset: 608] [Word64]
B53 #236 Store(#233, #235) [tagged base, AnyTagged, NoWriteBarrier, offset: 8, initializing] []
B53 #238 Store(#233, #209) [tagged base, Int32, NoWriteBarrier, offset: 16] []
B53 #239 Load(#4) [tagged base, AnyTagged, Tagged, offset: 3712] [Tagged]
B53 #240 Load(#0) [tagged base, Uint64, Word64, offset: 72] [Word64]
B53 #241 Load(#240) [raw, Uint64, Word64] [Word64]
B53 #242 Load(#0) [tagged base, Uint64, Word64, offset: 64] [Word64]
B53 #243 Goto() [B54, 0] []
B54 #244 Load(#242) [raw, Uint64, Word64] [Word64]
B54 #245 WordBinop(#241, #174) [Add, Word64] [Word64]
B54 #246 Comparison(#245, #244) [UnsignedLessThan, Word64] [Word32]
B54 #247 Branch(#246) [B56, B55, True] []
B55 #249 Call(#177, #174) [BuiltinPointer:Allocate Descriptor:r1s0i2f0] []
B55 #251 DidntThrow(#249) [🁫🁫 🁫🁫 🁤🁪 🁫 i a, 0] [Tagged]
B55 #253 TaggedBitcast(#251) [Tagged, Word64, HeapObject] [Word64]
B55 #254 Constant() [word64: -1] [Word64]
B55 #255 WordBinop(#253, #254) [Add, Word64] [Word64]
B55 #256 Goto() [B57, 0] []
B56 #257 Goto() [B57, 0] []
B57 #258 Phi(#241, #255) [Word64] [Word64]
B57 #259 WordBinop(#258, #174) [Add, Word64] [Word64]
B57 #260 Store(#240, #259) [raw, Uint64, NoWriteBarrier] []
B57 #262 WordBinop(#258, #201) [Add, Word64] [Word64]
B57 #263 TaggedBitcast(#262) [Word64, Tagged, HeapObject] [Tagged]
B57 #264 Store(#263, #239) [tagged base, TaggedPointer, NoWriteBarrier, initializing] []
B57 #265 Load(#10) [raw, Uint64, Word64, offset: 608] [Word64]
B57 #266 Store(#263, #265) [tagged base, AnyTagged, NoWriteBarrier, offset: 8, initializing] []
B57 #268 Store(#263, #5) [tagged base, Int64, NoWriteBarrier, offset: 16] []
B57 #269 Constant() [word32: -1] [Word32]
B57 #270 WordBinop(#172, #269) [Add, Word32] [Word32]
B57 #271 Store(#203, #270) [tagged base, Int32, NoWriteBarrier, offset: 16] []
B57 #273 Comparison(#6, #270) [SignedLessThanOrEqual, Word32] [Word32]
B57 #274 Branch(#273) [B58, B74, None] []
B58 #276 Load(#1) [tagged base, AnyTagged, Tagged, offset: 16] [Tagged]
B58 #277 Load(#276) [tagged base, Int32, Word32, offset: 16] [Word32]
B58 #278 Comparison(#270, #277) [UnsignedLessThan, Word32] [Word32]
B58 #279 TrapIf(#278) [1, TrapArrayOutOfBounds] []
B58 #280 Change(#270) [SignExtend, NoAssumption, Word32, Word64] [Word64]
B58 #281 Load(#276, #280) [tagged base, Uint8, Word32, offset: 24] [Word32]
B58 #282 Change(#281) [SignExtend, NoAssumption, Word32, Word64] [Word64]
B58 #283 Constant() [word32: 63] [Word32]
B58 #284 WordBinop(#3, #283) [BitwiseAnd, Word32] [Word32]
B58 #285 Shift(#282, #284) [ShiftLeft, Word64] [Word64]
B58 #286 Store(#263, #285) [tagged base, Int64, NoWriteBarrier, offset: 16] []
B58 #288 Constant() [word64: 10] [Word64]
B58 #289 Constant() [word64: 7378697629483820647] [Word64]
B58 #290 WordBinop(#285, #289) [SignedMulOverflownBits, Word64] [Word64]
B58 #291 Shift(#285, #283) [ShiftRightLogical, Word64] [Word64]
B58 #292 Constant() [word32: 2] [Word32]
B58 #293 Shift(#290, #292) [ShiftRightArithmetic, Word64] [Word64]
B58 #294 WordBinop(#293, #291) [Add, Word64] [Word64]
B58 #295 WordBinop(#294, #288) [Mul, Word64] [Word64]
B58 #296 WordBinop(#285, #295) [Sub, Word64] [Word64]
B58 #297 Change(#296) [Truncate, NoAssumption, Word64, Word32] [Word32]
B58 #298 WordBinop(#209, #269) [Add, Word32] [Word32]
B58 #299 Store(#233, #298) [tagged base, Int32, NoWriteBarrier, offset: 16] []
B58 #300 Comparison(#298, #277) [SignedLessThan, Word32] [Word32]
B58 #301 Branch(#300) [B59, B60, None] []
B59 #303 Constant() [word32: 255] [Word32]
B59 #304 Comparison(#298, #277) [UnsignedLessThan, Word32] [Word32]
B59 #305 TrapIf(#304) [1, TrapArrayOutOfBounds] []
B59 #306 Change(#298) [SignExtend, NoAssumption, Word32, Word64] [Word64]
B59 #307 Store(#276, #306, #297) [tagged base, Int8, NoWriteBarrier, offset: 24] []
B59 #309 Goto() [B64, 0] []
B60 #310 Branch(#297) [B61, B62, None] []
B61 #312 Store(#1, #180) [tagged base, Int32, NoWriteBarrier, offset: 36] []
B61 #314 Goto() [B63, 0] []
B62 #315 Goto() [B63, 0] []
B63 #316 Goto() [B64, 0] []
B64 #317 Store(#263, #294) [tagged base, Int64, NoWriteBarrier, offset: 16] []
B64 #318 WordBinop(#270, #269) [Add, Word32] [Word32]
B64 #319 Store(#203, #318) [tagged base, Int32, NoWriteBarrier, offset: 16] []
B64 #321 Goto() [B65, 0] []
B65 #322 WasmStackCheck() [loop] []
B65 #323 Load(#203) [tagged base, Int32, Word32, offset: 16] [Word32]
B65 #324 Comparison(#6, #323) [SignedLessThanOrEqual, Word32] [Word32]
B65 #325 Branch(#324) [B67, B66, None] []
B66 #327 Goto() [B75, 0] []
B67 #328 Comparison(#323, #277) [UnsignedLessThan, Word32] [Word32]
B67 #329 TrapIf(#328) [1, TrapArrayOutOfBounds] []
B67 #330 Change(#323) [SignExtend, NoAssumption, Word32, Word64] [Word64]
B67 #331 Load(#276, #330) [tagged base, Uint8, Word32, offset: 24] [Word32]
B67 #332 Change(#331) [SignExtend, NoAssumption, Word32, Word64] [Word64]
B67 #333 Load(#263) [tagged base, Int64, Word64, offset: 16] [Word64]
B67 #334 Shift(#332, #284) [ShiftLeft, Word64] [Word64]
B67 #335 WordBinop(#333, #334) [Add, Word64] [Word64]
B67 #336 Store(#263, #335) [tagged base, Int64, NoWriteBarrier, offset: 16] []
B67 #338 WordBinop(#335, #289) [SignedMulOverflownBits, Word64] [Word64]
B67 #339 Shift(#335, #283) [ShiftRightLogical, Word64] [Word64]
B67 #340 Shift(#338, #292) [ShiftRightArithmetic, Word64] [Word64]
B67 #341 WordBinop(#340, #339) [Add, Word64] [Word64]
B67 #342 WordBinop(#341, #288) [Mul, Word64] [Word64]
B67 #343 WordBinop(#335, #342) [Sub, Word64] [Word64]
B67 #344 Change(#343) [Truncate, NoAssumption, Word64, Word32] [Word32]
B67 #345 Load(#233) [tagged base, Int32, Word32, offset: 16] [Word32]
B67 #346 WordBinop(#345, #269) [Add, Word32] [Word32]
B67 #347 Store(#233, #346) [tagged base, Int32, NoWriteBarrier, offset: 16] []
B67 #348 Comparison(#346, #277) [SignedLessThan, Word32] [Word32]
B67 #349 Branch(#348) [B68, B69, None] []
B68 #351 Constant() [word32: 255] [Word32]
B68 #352 Comparison(#346, #277) [UnsignedLessThan, Word32] [Word32]
B68 #353 TrapIf(#352) [1, TrapArrayOutOfBounds] []
B68 #354 Change(#346) [SignExtend, NoAssumption, Word32, Word64] [Word64]
B68 #355 Store(#276, #354, #344) [tagged base, Int8, NoWriteBarrier, offset: 24] []
B68 #357 Goto() [B73, 0] []
B69 #358 Branch(#344) [B70, B71, None] []
B70 #360 Store(#1, #180) [tagged base, Int32, NoWriteBarrier, offset: 36] []
B70 #362 Goto() [B72, 0] []
B71 #363 Goto() [B72, 0] []
B72 #364 Goto() [B73, 0] []
B73 #365 Store(#263, #341) [tagged base, Int64, NoWriteBarrier, offset: 16] []
B73 #366 WordBinop(#323, #269) [Add, Word32] [Word32]
B73 #367 Store(#203, #366) [tagged base, Int32, NoWriteBarrier, offset: 16] []
B73 #369 Goto() [B65, 1] []
B74 #370 Goto() [B75, 0] []
B75 #371 Load(#263) [tagged base, Int64, Word64, offset: 16] [Word64]
B75 #372 Comparison(#5, #371) [SignedLessThan, Word64] [Word32]
B75 #373 Branch(#372) [B76, B117, None] []
B76 #375 Constant() [word64: 10] [Word64]
B76 #376 Constant() [word64: 7378697629483820647] [Word64]
B76 #377 WordBinop(#371, #376) [SignedMulOverflownBits, Word64] [Word64]
B76 #378 Constant() [word32: 63] [Word32]
B76 #379 Shift(#371, #378) [ShiftRightLogical, Word64] [Word64]
B76 #380 Constant() [word32: 2] [Word32]
B76 #381 Shift(#377, #380) [ShiftRightArithmetic, Word64] [Word64]
B76 #382 WordBinop(#381, #379) [Add, Word64] [Word64]
B76 #383 WordBinop(#382, #375) [Mul, Word64] [Word64]
B76 #384 WordBinop(#371, #383) [Sub, Word64] [Word64]
B76 #385 Change(#384) [Truncate, NoAssumption, Word64, Word32] [Word32]
B76 #386 Load(#233) [tagged base, Int32, Word32, offset: 16] [Word32]
B76 #387 WordBinop(#386, #269) [Add, Word32] [Word32]
B76 #388 Store(#233, #387) [tagged base, Int32, NoWriteBarrier, offset: 16] []
B76 #389 Load(#1) [tagged base, AnyTagged, Tagged, offset: 16] [Tagged]
B76 #390 Load(#389) [tagged base, Int32, Word32, offset: 16] [Word32]
B76 #391 Comparison(#387, #390) [SignedLessThan, Word32] [Word32]
B76 #392 Branch(#391) [B77, B78, None] []
B77 #394 Constant() [word32: 255] [Word32]
B77 #395 Comparison(#387, #390) [UnsignedLessThan, Word32] [Word32]
B77 #396 TrapIf(#395) [1, TrapArrayOutOfBounds] []
B77 #397 Change(#387) [SignExtend, NoAssumption, Word32, Word64] [Word64]
B77 #398 Store(#389, #397, #385) [tagged base, Int8, NoWriteBarrier, offset: 24] []
B77 #400 Goto() [B82, 0] []
B78 #401 Branch(#385) [B79, B80, None] []
B79 #403 Store(#1, #180) [tagged base, Int32, NoWriteBarrier, offset: 36] []
B79 #405 Goto() [B81, 0] []
B80 #406 Goto() [B81, 0] []
B81 #407 Goto() [B82, 0] []
B82 #408 Store(#263, #382) [tagged base, Int64, NoWriteBarrier, offset: 16] []
B82 #409 Goto() [B83, 0] []
B83 #410 Load(#263) [tagged base, Int64, Word64, offset: 16] [Word64]
B83 #411 Comparison(#5, #410) [SignedLessThan, Word64] [Word32]
B83 #412 Branch(#411) [B84, B115, None] []
B84 #414 WordBinop(#410, #376) [SignedMulOverflownBits, Word64] [Word64]
B84 #415 Shift(#410, #378) [ShiftRightLogical, Word64] [Word64]
B84 #416 Shift(#414, #380) [ShiftRightArithmetic, Word64] [Word64]
B84 #417 WordBinop(#416, #415) [Add, Word64] [Word64]
B84 #418 WordBinop(#417, #375) [Mul, Word64] [Word64]
B84 #419 WordBinop(#410, #418) [Sub, Word64] [Word64]
B84 #420 Change(#419) [Truncate, NoAssumption, Word64, Word32] [Word32]
B84 #421 Load(#233) [tagged base, Int32, Word32, offset: 16] [Word32]
B84 #422 WordBinop(#421, #269) [Add, Word32] [Word32]
B84 #423 Store(#233, #422) [tagged base, Int32, NoWriteBarrier, offset: 16] []
B84 #425 Comparison(#422, #390) [SignedLessThan, Word32] [Word32]
B84 #426 Branch(#425) [B85, B86, None] []
B85 #428 Constant() [word32: 255] [Word32]
B85 #429 Comparison(#422, #390) [UnsignedLessThan, Word32] [Word32]
B85 #430 TrapIf(#429) [1, TrapArrayOutOfBounds] []
B85 #431 Change(#422) [SignExtend, NoAssumption, Word32, Word64] [Word64]
B85 #432 Store(#389, #431, #420) [tagged base, Int8, NoWriteBarrier, offset: 24] []
B85 #434 Goto() [B90, 0] []
B86 #435 Branch(#420) [B87, B88, None] []
B87 #437 Store(#1, #180) [tagged base, Int32, NoWriteBarrier, offset: 36] []
B87 #438 Goto() [B89, 0] []
B88 #439 Goto() [B89, 0] []
B89 #440 Goto() [B90, 0] []
B90 #441 Store(#263, #417) [tagged base, Int64, NoWriteBarrier, offset: 16] []
B90 #443 Comparison(#5, #417) [SignedLessThan, Word64] [Word32]
B90 #444 Branch(#443) [B92, B91, None] []
B91 #446 Goto() [B116, 0] []
B92 #447 WordBinop(#417, #376) [SignedMulOverflownBits, Word64] [Word64]
B92 #448 Shift(#417, #378) [ShiftRightLogical, Word64] [Word64]
B92 #449 Shift(#447, #380) [ShiftRightArithmetic, Word64] [Word64]
B92 #450 WordBinop(#449, #448) [Add, Word64] [Word64]
B92 #451 WordBinop(#450, #375) [Mul, Word64] [Word64]
B92 #452 WordBinop(#417, #451) [Sub, Word64] [Word64]
B92 #453 Change(#452) [Truncate, NoAssumption, Word64, Word32] [Word32]
B92 #454 WordBinop(#422, #269) [Add, Word32] [Word32]
B92 #455 Store(#233, #454) [tagged base, Int32, NoWriteBarrier, offset: 16] []
B92 #456 Comparison(#454, #390) [SignedLessThan, Word32] [Word32]
B92 #457 Branch(#456) [B93, B94, None] []
B93 #459 Constant() [word32: 255] [Word32]
B93 #460 Comparison(#454, #390) [UnsignedLessThan, Word32] [Word32]
B93 #461 TrapIf(#460) [1, TrapArrayOutOfBounds] []
B93 #462 Change(#454) [SignExtend, NoAssumption, Word32, Word64] [Word64]
B93 #463 Store(#389, #462, #453) [tagged base, Int8, NoWriteBarrier, offset: 24] []
B93 #465 Goto() [B98, 0] []
B94 #466 Branch(#453) [B95, B96, None] []
B95 #468 Store(#1, #180) [tagged base, Int32, NoWriteBarrier, offset: 36] []
B95 #470 Goto() [B97, 0] []
B96 #471 Goto() [B97, 0] []
B97 #472 Goto() [B98, 0] []
B98 #473 Store(#263, #450) [tagged base, Int64, NoWriteBarrier, offset: 16] []
B98 #474 Comparison(#5, #450) [SignedLessThan, Word64] [Word32]
B98 #475 Branch(#474) [B100, B99, None] []
B99 #477 Goto() [B116, 0] []
B100 #478 WordBinop(#450, #376) [SignedMulOverflownBits, Word64] [Word64]
B100 #479 Shift(#450, #378) [ShiftRightLogical, Word64] [Word64]
B100 #480 Shift(#478, #380) [ShiftRightArithmetic, Word64] [Word64]
B100 #481 WordBinop(#480, #479) [Add, Word64] [Word64]
B100 #482 WordBinop(#481, #375) [Mul, Word64] [Word64]
B100 #483 WordBinop(#450, #482) [Sub, Word64] [Word64]
B100 #484 Change(#483) [Truncate, NoAssumption, Word64, Word32] [Word32]
B100 #485 WordBinop(#454, #269) [Add, Word32] [Word32]
B100 #486 Store(#233, #485) [tagged base, Int32, NoWriteBarrier, offset: 16] []
B100 #488 Comparison(#485, #390) [SignedLessThan, Word32] [Word32]
B100 #489 Branch(#488) [B101, B102, None] []
B101 #491 Constant() [word32: 255] [Word32]
B101 #492 Comparison(#485, #390) [UnsignedLessThan, Word32] [Word32]
B101 #493 TrapIf(#492) [1, TrapArrayOutOfBounds] []
B101 #494 Change(#485) [SignExtend, NoAssumption, Word32, Word64] [Word64]
B101 #495 Store(#389, #494, #484) [tagged base, Int8, NoWriteBarrier, offset: 24] []
B101 #497 Goto() [B106, 0] []
B102 #498 Branch(#484) [B103, B104, None] []
B103 #500 Store(#1, #180) [tagged base, Int32, NoWriteBarrier, offset: 36] []
B103 #501 Goto() [B105, 0] []
B104 #502 Goto() [B105, 0] []
B105 #503 Goto() [B106, 0] []
B106 #504 Store(#263, #481) [tagged base, Int64, NoWriteBarrier, offset: 16] []
B106 #506 WasmStackCheck() [loop] []
B106 #507 Comparison(#5, #481) [SignedLessThan, Word64] [Word32]
B106 #508 Branch(#507) [B108, B107, None] []
B107 #510 Goto() [B116, 0] []
B108 #511 WordBinop(#481, #376) [SignedMulOverflownBits, Word64] [Word64]
B108 #512 Shift(#481, #378) [ShiftRightLogical, Word64] [Word64]
B108 #513 Shift(#511, #380) [ShiftRightArithmetic, Word64] [Word64]
B108 #514 WordBinop(#513, #512) [Add, Word64] [Word64]
B108 #515 WordBinop(#514, #375) [Mul, Word64] [Word64]
B108 #516 WordBinop(#481, #515) [Sub, Word64] [Word64]
B108 #517 Change(#516) [Truncate, NoAssumption, Word64, Word32] [Word32]
B108 #518 WordBinop(#485, #269) [Add, Word32] [Word32]
B108 #519 Store(#233, #518) [tagged base, Int32, NoWriteBarrier, offset: 16] []
B108 #520 Comparison(#518, #390) [SignedLessThan, Word32] [Word32]
B108 #521 Branch(#520) [B109, B110, None] []
B109 #523 Constant() [word32: 255] [Word32]
B109 #524 Comparison(#518, #390) [UnsignedLessThan, Word32] [Word32]
B109 #525 TrapIf(#524) [1, TrapArrayOutOfBounds] []
B109 #526 Change(#518) [SignExtend, NoAssumption, Word32, Word64] [Word64]
B109 #527 Store(#389, #526, #517) [tagged base, Int8, NoWriteBarrier, offset: 24] []
B109 #529 Goto() [B114, 0] []
B110 #530 Branch(#517) [B111, B112, None] []
B111 #532 Store(#1, #180) [tagged base, Int32, NoWriteBarrier, offset: 36] []
B111 #534 Goto() [B113, 0] []
B112 #535 Goto() [B113, 0] []
B113 #536 Goto() [B114, 0] []
B114 #537 Store(#263, #514) [tagged base, Int64, NoWriteBarrier, offset: 16] []
B114 #538 Goto() [B83, 1] []
B115 #539 Goto() [B116, 0] []
B116 #540 Goto() [B118, 0] []
B117 #541 Goto() [B118, 0] []
B118 #542 Store(#1, #209) [tagged base, Int32, NoWriteBarrier, offset: 24] []
B118 #544 Load(#1) [tagged base, AnyTagged, Tagged, offset: 16] [Tagged]
B118 #545 Load(#544) [tagged base, Int32, Word32, offset: 16] [Word32]
B118 #546 Comparison(#545, #209) [SignedLessThan, Word32] [Word32]
B118 #547 Branch(#546) [B119, B120, None] []
B119 #549 Store(#1, #545) [tagged base, Int32, NoWriteBarrier, offset: 24] []
B119 #550 Goto() [B121, 0] []
B120 #551 Goto() [B121, 0] []
B121 #552 Load(#1) [tagged base, Int32, Word32, offset: 28] [Word32]
B121 #553 WordBinop(#552, #171) [Add, Word32] [Word32]
B121 #554 Store(#1, #553) [tagged base, Int32, NoWriteBarrier, offset: 28] []
B121 #556 Load(#1) [tagged base, Int32, Word32, offset: 24] [Word32]
B121 #557 Comparison(#6, #556) [SignedLessThan, Word32] [Word32]
B121 #558 Branch(#557) [B122, B124, None] []
B122 #560 WordBinop(#556, #269) [Add, Word32] [Word32]
B122 #561 Comparison(#560, #545) [UnsignedLessThan, Word32] [Word32]
B122 #562 TrapIf(#561) [1, TrapArrayOutOfBounds] []
B122 #563 Change(#560) [SignExtend, NoAssumption, Word32, Word64] [Word64]
B122 #564 Load(#544, #563) [tagged base, Uint8, Word32, offset: 24] [Word32]
B122 #565 Comparison(#564, #6) [Equal, Word32] [Word32]
B122 #566 Goto() [B123, 0] []
B123 #567 Branch(#564) [B126, B127, None] []
B124 #569 Goto() [B125, 0] []
B125 #570 Goto() [B158, 0] []
B126 #571 Goto() [B158, 0] []
B127 #572 WordBinop(#556, #269) [Add, Word32] [Word32]
B127 #573 Store(#1, #572) [tagged base, Int32, NoWriteBarrier, offset: 24] []
B127 #575 Goto() [B128, 0] []
B128 #576 Load(#1) [tagged base, Int32, Word32, offset: 24] [Word32]
B128 #577 Comparison(#6, #576) [SignedLessThan, Word32] [Word32]
B128 #578 Branch(#577) [B129, B131, None] []
B129 #580 WordBinop(#576, #269) [Add, Word32] [Word32]
B129 #581 Comparison(#580, #545) [UnsignedLessThan, Word32] [Word32]
B129 #582 TrapIf(#581) [1, TrapArrayOutOfBounds] []
B129 #583 Change(#580) [SignExtend, NoAssumption, Word32, Word64] [Word64]
B129 #584 Load(#544, #583) [tagged base, Uint8, Word32, offset: 24] [Word32]
B129 #585 Comparison(#584, #6) [Equal, Word32] [Word32]
B129 #586 Goto() [B130, 0] []
B130 #587 Branch(#584) [B133, B134, None] []
B131 #589 Goto() [B132, 0] []
B132 #590 Goto() [B156, 0] []
B133 #591 Goto() [B156, 0] []
B134 #592 WordBinop(#576, #269) [Add, Word32] [Word32]
B134 #593 Store(#1, #592) [tagged base, Int32, NoWriteBarrier, offset: 24] []
B134 #595 Comparison(#6, #592) [SignedLessThan, Word32] [Word32]
B134 #596 Branch(#595) [B135, B137, None] []
B135 #598 WordBinop(#592, #269) [Add, Word32] [Word32]
B135 #599 Comparison(#598, #545) [UnsignedLessThan, Word32] [Word32]
B135 #600 TrapIf(#599) [1, TrapArrayOutOfBounds] []
B135 #601 Change(#598) [SignExtend, NoAssumption, Word32, Word64] [Word64]
B135 #602 Load(#544, #601) [tagged base, Uint8, Word32, offset: 24] [Word32]
B135 #603 Comparison(#602, #6) [Equal, Word32] [Word32]
B135 #604 Goto() [B136, 0] []
B136 #605 Branch(#602) [B139, B141, None] []
B137 #607 Goto() [B138, 0] []
B138 #608 Goto() [B140, 0] []
B139 #609 Goto() [B140, 0] []
B140 #610 Phi(#603, #6) [Word32] [Word32]
B140 #611 Goto() [B157, 0] []
B141 #612 WordBinop(#592, #269) [Add, Word32] [Word32]
B141 #613 Store(#1, #612) [tagged base, Int32, NoWriteBarrier, offset: 24] []
B141 #615 Comparison(#6, #612) [SignedLessThan, Word32] [Word32]
B141 #616 Branch(#615) [B142, B144, None] []
B142 #618 WordBinop(#612, #269) [Add, Word32] [Word32]
B142 #619 Comparison(#618, #545) [UnsignedLessThan, Word32] [Word32]
B142 #620 TrapIf(#619) [1, TrapArrayOutOfBounds] []
B142 #621 Change(#618) [SignExtend, NoAssumption, Word32, Word64] [Word64]
B142 #622 Load(#544, #621) [tagged base, Uint8, Word32, offset: 24] [Word32]
B142 #623 Comparison(#622, #6) [Equal, Word32] [Word32]
B142 #624 Goto() [B143, 0] []
B143 #625 Branch(#622) [B146, B148, None] []
B144 #627 Goto() [B145, 0] []
B145 #628 Goto() [B147, 0] []
B146 #629 Goto() [B147, 0] []
B147 #630 Phi(#623, #6) [Word32] [Word32]
B147 #631 Goto() [B157, 0] []
B148 #632 WordBinop(#612, #269) [Add, Word32] [Word32]
B148 #633 Store(#1, #632) [tagged base, Int32, NoWriteBarrier, offset: 24] []
B148 #635 WasmStackCheck() [loop] []
B148 #636 Comparison(#6, #632) [SignedLessThan, Word32] [Word32]
B148 #637 Branch(#636) [B149, B151, None] []
B149 #639 WordBinop(#632, #269) [Add, Word32] [Word32]
B149 #640 Comparison(#639, #545) [UnsignedLessThan, Word32] [Word32]
B149 #641 TrapIf(#640) [1, TrapArrayOutOfBounds] []
B149 #642 Change(#639) [SignExtend, NoAssumption, Word32, Word64] [Word64]
B149 #643 Load(#544, #642) [tagged base, Uint8, Word32, offset: 24] [Word32]
B149 #644 Comparison(#643, #6) [Equal, Word32] [Word32]
B149 #645 Goto() [B150, 0] []
B150 #646 Branch(#643) [B153, B155, None] []
B151 #648 Goto() [B152, 0] []
B152 #649 Goto() [B154, 0] []
B153 #650 Goto() [B154, 0] []
B154 #651 Phi(#644, #6) [Word32] [Word32]
B154 #652 Goto() [B157, 0] []
B155 #653 WordBinop(#632, #269) [Add, Word32] [Word32]
B155 #654 Store(#1, #653) [tagged base, Int32, NoWriteBarrier, offset: 24] []
B155 #656 Goto() [B128, 1] []
B156 #657 Phi(#585, #6) [Word32] [Word32]
B156 #658 Goto() [B157, 0] []
B157 #659 Phi(#585, #585, #585, #657) [Word32] [Word32]
B157 #660 Goto() [B159, 0] []
B158 #661 Phi(#565, #6) [Word32] [Word32]
B158 #662 Goto() [B159, 0] []
B159 #663 Phi(#565, #661) [Word32] [Word32]
B159 #664 Load(#1) [tagged base, Int32, Word32, offset: 24] [Word32]
B159 #665 Branch(#664) [B161, B160, None] []
B160 #667 Store(#1, #6) [tagged base, Int32, NoWriteBarrier, offset: 28] []
B160 #669 Return(#6, #6) [0] []
B161 #670 Return(#6, #6) [0] []
```

### V8 inlined guest functions

455, 461, 688, 755, 883

### V8 ARM64 machine code

```asm
0x8f1e9f000     0  d2800110       movz x16, #0x8
0x8f1e9f004     4  a9be43e7       stp x7, x16, [sp, #-32]!
0x8f1e9f008     8  a9017bfd       stp fp, lr, [sp, #16]
0x8f1e9f00c     c  910043fd       add fp, sp, #0x10 (16)
0x8f1e9f010    10  d10143ff       sub sp, sp, #0x50 (80)
0x8f1e9f014    14  f84ef0e3       ldur x3, [x7, #239]
0x8f1e9f018    18  f8520344       ldur x4, [x26, #-224]
0x8f1e9f01c    1c  eb2463ff       cmp sp, x4
0x8f1e9f020    20  540036a9       b.ls #+0x6d4 (addr 0x8f1e9f6f4)
0x8f1e9f024    24  f84bf0e4       ldur x4, [x7, #191]
0x8f1e9f028    28  f8467084       ldur x4, [x4, #103]
0x8f1e9f02c    2c  f9439f45       ldr x5, [x26, #1848]
0x8f1e9f030    30  eb05009f       cmp x4, x5
0x8f1e9f034    34  54004ee0       b.eq #+0x9dc (addr 0x8f1e9fa10)
0x8f1e9f038    38  b840f086       ldur w6, [x4, #15]
0x8f1e9f03c    3c  6b06001f       cmp w0, w6
0x8f1e9f040    40  54004e62       b.hs #+0x9cc (addr 0x8f1e9fa0c)
0x8f1e9f044    44  93407c06       sxtw x6, w0
0x8f1e9f048    48  d37df0c6       lsl x6, x6, #3
0x8f1e9f04c    4c  91005cc6       add x6, x6, #0x17 (23)
0x8f1e9f050    50  f8666884       ldr x4, [x4, x6]
0x8f1e9f054    54  eb05009f       cmp x4, x5
0x8f1e9f058    58  54004d80       b.eq #+0x9b0 (addr 0x8f1e9fa08)
0x8f1e9f05c    5c  b840f085       ldur w5, [x4, #15]
0x8f1e9f060    60  f8417084       ldur x4, [x4, #23]
0x8f1e9f064    64  b840f086       ldur w6, [x4, #15]
0x8f1e9f068    68  710000df       cmp w6, #0x0 (0)
0x8f1e9f06c    6c  54000d2d       b.le #+0x1a4 (addr 0x8f1e9f210)
0x8f1e9f070    70  710000df       cmp w6, #0x0 (0)
0x8f1e9f074    74  54004c89       b.ls #+0x990 (addr 0x8f1e9fa04)
0x8f1e9f078    78  78417088       ldurh w8, [x4, #23]
0x8f1e9f07c    7c  b8417049       ldur w9, [x2, #23]
0x8f1e9f080    80  7100013f       cmp w9, #0x0 (0)
0x8f1e9f084    84  54000c4d       b.le #+0x188 (addr 0x8f1e9f20c)
0x8f1e9f088    88  5100c108       sub w8, w8, #0x30 (48)
0x8f1e9f08c    8c  f840f04a       ldur x10, [x2, #15]
0x8f1e9f090    90  b840f14b       ldur w11, [x10, #15]
0x8f1e9f094    94  7100017f       cmp w11, #0x0 (0)
0x8f1e9f098    98  54004b49       b.ls #+0x968 (addr 0x8f1e9fa00)
0x8f1e9f09c    9c  39405d4c       ldrb w12, [x10, #23]
0x8f1e9f0a0    a0  6b08019f       cmp w12, w8
0x8f1e9f0a4    a4  54000080       b.eq #+0x10 (addr 0x8f1e9f0b4)
0x8f1e9f0a8    a8  aa0803ed       mov x13, x8
0x8f1e9f0ac    ac  d2800008       movz x8, #0x0
0x8f1e9f0b0    b0  1400004e       b #+0x138 (addr 0x8f1e9f1e8)
0x8f1e9f0b4    b4  d2800028       movz x8, #0x1
0x8f1e9f0b8    b8  14000002       b #+0x8 (addr 0x8f1e9f0c0)
0x8f1e9f0bc    bc  11000508       add w8, w8, #0x1 (1)
0x8f1e9f0c0    c0  6b06011f       cmp w8, w6
0x8f1e9f0c4    c4  54000a6a       b.ge #+0x14c (addr 0x8f1e9f210)
0x8f1e9f0c8    c8  6b06011f       cmp w8, w6
0x8f1e9f0cc    cc  54004982       b.hs #+0x930 (addr 0x8f1e9f9fc)
0x8f1e9f0d0    d0  93407d0c       sxtw x12, w8
0x8f1e9f0d4    d4  d37ff98d       lsl x13, x12, #1
0x8f1e9f0d8    d8  91005dad       add x13, x13, #0x17 (23)
0x8f1e9f0dc    dc  786d688d       ldrh w13, [x4, x13]
0x8f1e9f0e0    e0  6b08013f       cmp w9, w8
0x8f1e9f0e4    e4  5400094d       b.le #+0x128 (addr 0x8f1e9f20c)
0x8f1e9f0e8    e8  5100c1ad       sub w13, w13, #0x30 (48)
0x8f1e9f0ec    ec  6b0b011f       cmp w8, w11
0x8f1e9f0f0    f0  54004842       b.hs #+0x908 (addr 0x8f1e9f9f8)
0x8f1e9f0f4    f4  91005d8c       add x12, x12, #0x17 (23)
0x8f1e9f0f8    f8  386c694c       ldrb w12, [x10, x12]
0x8f1e9f0fc    fc  6b0d019f       cmp w12, w13
0x8f1e9f100   100  54000741       b.ne #+0xe8 (addr 0x8f1e9f1e8)
0x8f1e9f104   104  11000508       add w8, w8, #0x1 (1)
0x8f1e9f108   108  6b06011f       cmp w8, w6
0x8f1e9f10c   10c  5400082a       b.ge #+0x104 (addr 0x8f1e9f210)
0x8f1e9f110   110  6b06011f       cmp w8, w6
0x8f1e9f114   114  54004702       b.hs #+0x8e0 (addr 0x8f1e9f9f4)
0x8f1e9f118   118  93407d0c       sxtw x12, w8
0x8f1e9f11c   11c  d37ff98d       lsl x13, x12, #1
0x8f1e9f120   120  91005dad       add x13, x13, #0x17 (23)
0x8f1e9f124   124  786d688d       ldrh w13, [x4, x13]
0x8f1e9f128   128  6b08013f       cmp w9, w8
0x8f1e9f12c   12c  5400070d       b.le #+0xe0 (addr 0x8f1e9f20c)
0x8f1e9f130   130  5100c1ad       sub w13, w13, #0x30 (48)
0x8f1e9f134   134  6b0b011f       cmp w8, w11
0x8f1e9f138   138  540045c2       b.hs #+0x8b8 (addr 0x8f1e9f9f0)
0x8f1e9f13c   13c  91005d8c       add x12, x12, #0x17 (23)
0x8f1e9f140   140  386c694c       ldrb w12, [x10, x12]
0x8f1e9f144   144  6b0d019f       cmp w12, w13
0x8f1e9f148   148  54000501       b.ne #+0xa0 (addr 0x8f1e9f1e8)
0x8f1e9f14c   14c  11000508       add w8, w8, #0x1 (1)
0x8f1e9f150   150  6b06011f       cmp w8, w6
0x8f1e9f154   154  540005ea       b.ge #+0xbc (addr 0x8f1e9f210)
0x8f1e9f158   158  6b06011f       cmp w8, w6
0x8f1e9f15c   15c  54004482       b.hs #+0x890 (addr 0x8f1e9f9ec)
0x8f1e9f160   160  93407d0c       sxtw x12, w8
0x8f1e9f164   164  d37ff98d       lsl x13, x12, #1
0x8f1e9f168   168  91005dad       add x13, x13, #0x17 (23)
0x8f1e9f16c   16c  786d688d       ldrh w13, [x4, x13]
0x8f1e9f170   170  6b08013f       cmp w9, w8
0x8f1e9f174   174  540004cd       b.le #+0x98 (addr 0x8f1e9f20c)
0x8f1e9f178   178  5100c1ad       sub w13, w13, #0x30 (48)
0x8f1e9f17c   17c  6b0b011f       cmp w8, w11
0x8f1e9f180   180  54004342       b.hs #+0x868 (addr 0x8f1e9f9e8)
0x8f1e9f184   184  91005d8c       add x12, x12, #0x17 (23)
0x8f1e9f188   188  386c694c       ldrb w12, [x10, x12]
0x8f1e9f18c   18c  6b0d019f       cmp w12, w13
0x8f1e9f190   190  540002c1       b.ne #+0x58 (addr 0x8f1e9f1e8)
0x8f1e9f194   194  11000508       add w8, w8, #0x1 (1)
0x8f1e9f198   198  f852034c       ldur x12, [x26, #-224]
0x8f1e9f19c   19c  eb2c63ff       cmp sp, x12
0x8f1e9f1a0   1a0  54002bc9       b.ls #+0x578 (addr 0x8f1e9f718)
0x8f1e9f1a4   1a4  6b06011f       cmp w8, w6
0x8f1e9f1a8   1a8  5400034a       b.ge #+0x68 (addr 0x8f1e9f210)
0x8f1e9f1ac   1ac  6b06011f       cmp w8, w6
0x8f1e9f1b0   1b0  540041a2       b.hs #+0x834 (addr 0x8f1e9f9e4)
0x8f1e9f1b4   1b4  93407d0c       sxtw x12, w8
0x8f1e9f1b8   1b8  d37ff98d       lsl x13, x12, #1
0x8f1e9f1bc   1bc  91005dad       add x13, x13, #0x17 (23)
0x8f1e9f1c0   1c0  786d688d       ldrh w13, [x4, x13]
0x8f1e9f1c4   1c4  6b08013f       cmp w9, w8
0x8f1e9f1c8   1c8  5400022d       b.le #+0x44 (addr 0x8f1e9f20c)
0x8f1e9f1cc   1cc  5100c1ad       sub w13, w13, #0x30 (48)
0x8f1e9f1d0   1d0  6b0b011f       cmp w8, w11
0x8f1e9f1d4   1d4  54004062       b.hs #+0x80c (addr 0x8f1e9f9e0)
0x8f1e9f1d8   1d8  91005d8c       add x12, x12, #0x17 (23)
0x8f1e9f1dc   1dc  386c694c       ldrb w12, [x10, x12]
0x8f1e9f1e0   1e0  6b0d019f       cmp w12, w13
0x8f1e9f1e4   1e4  54fff6c0       b.eq #-0x128 (addr 0x8f1e9f0bc)
0x8f1e9f1e8   1e8  6b0b011f       cmp w8, w11
0x8f1e9f1ec   1ec  54003f82       b.hs #+0x7f0 (addr 0x8f1e9f9dc)
0x8f1e9f1f0   1f0  93407d04       sxtw x4, w8
0x8f1e9f1f4   1f4  91005c84       add x4, x4, #0x17 (23)
0x8f1e9f1f8   1f8  38646944       ldrb w4, [x10, x4]
0x8f1e9f1fc   1fc  6b0d009f       cmp w4, w13
0x8f1e9f200   200  9a9fa7e4       cset x4, lt
0x8f1e9f204   204  d280000c       movz x12, #0x0
0x8f1e9f208   208  34000044       cbz w4, #+0x8 (addr 0x8f1e9f210)
0x8f1e9f20c   20c  510004a5       sub w5, w5, #0x1 (1)
0x8f1e9f210   210  b8417044       ldur w4, [x2, #23]
0x8f1e9f214   214  d28130e6       movz x6, #0x987
0x8f1e9f218   218  f8666866       ldr x6, [x3, x6]
0x8f1e9f21c   21c  f84470e8       ldur x8, [x7, #71]
0x8f1e9f220   220  f9400109       ldr x9, [x8]
0x8f1e9f224   224  f843f0ea       ldur x10, [x7, #63]
0x8f1e9f228   228  f940014a       ldr x10, [x10]
0x8f1e9f22c   22c  9100612b       add x11, x9, #0x18 (24)
0x8f1e9f230   230  eb0a017f       cmp x11, x10
0x8f1e9f234   234  54002a02       b.hs #+0x540 (addr 0x8f1e9f774)
0x8f1e9f238   238  9100612a       add x10, x9, #0x18 (24)
0x8f1e9f23c   23c  f900010a       str x10, [x8]
0x8f1e9f240   240  91000528       add x8, x9, #0x1 (1)
0x8f1e9f244   244  f81ff106       stur x6, [x8, #-1]
0x8f1e9f248   248  f9413349       ldr x9, [x26, #608]
0x8f1e9f24c   24c  f8007109       stur x9, [x8, #7]
0x8f1e9f250   250  b800f104       stur w4, [x8, #15]
0x8f1e9f254   254  0b050089       add w9, w4, w5
0x8f1e9f258   258  f84470ea       ldur x10, [x7, #71]
0x8f1e9f25c   25c  f940014b       ldr x11, [x10]
0x8f1e9f260   260  f843f0ec       ldur x12, [x7, #63]
0x8f1e9f264   264  f940018c       ldr x12, [x12]
0x8f1e9f268   268  9100616d       add x13, x11, #0x18 (24)
0x8f1e9f26c   26c  eb0c01bf       cmp x13, x12
0x8f1e9f270   270  54002b42       b.hs #+0x568 (addr 0x8f1e9f7d8)
0x8f1e9f274   274  9100616c       add x12, x11, #0x18 (24)
0x8f1e9f278   278  f900014c       str x12, [x10]
0x8f1e9f27c   27c  9100056a       add x10, x11, #0x1 (1)
0x8f1e9f280   280  f81ff146       stur x6, [x10, #-1]
0x8f1e9f284   284  f9413346       ldr x6, [x26, #608]
0x8f1e9f288   288  f8007146       stur x6, [x10, #7]
0x8f1e9f28c   28c  b800f149       stur w9, [x10, #15]
0x8f1e9f290   290  d281cfe6       movz x6, #0xe7f
0x8f1e9f294   294  f8666863       ldr x3, [x3, x6]
0x8f1e9f298   298  f84470e6       ldur x6, [x7, #71]
0x8f1e9f29c   29c  f94000cb       ldr x11, [x6]
0x8f1e9f2a0   2a0  f843f0e7       ldur x7, [x7, #63]
0x8f1e9f2a4   2a4  f94000e7       ldr x7, [x7]
0x8f1e9f2a8   2a8  9100616c       add x12, x11, #0x18 (24)
0x8f1e9f2ac   2ac  eb07019f       cmp x12, x7
0x8f1e9f2b0   2b0  54002cc2       b.hs #+0x598 (addr 0x8f1e9f848)
0x8f1e9f2b4   2b4  91006167       add x7, x11, #0x18 (24)
0x8f1e9f2b8   2b8  f90000c7       str x7, [x6]
0x8f1e9f2bc   2bc  91000566       add x6, x11, #0x1 (1)
0x8f1e9f2c0   2c0  f81ff0c3       stur x3, [x6, #-1]
0x8f1e9f2c4   2c4  f9413343       ldr x3, [x26, #608]
0x8f1e9f2c8   2c8  f80070c3       stur x3, [x6, #7]
0x8f1e9f2cc   2cc  f800f0df       stur xzr, [x6, #15]
0x8f1e9f2d0   2d0  51000483       sub w3, w4, #0x1 (1)
0x8f1e9f2d4   2d4  b800f103       stur w3, [x8, #15]
0x8f1e9f2d8   2d8  37f80923       tbnz w3, #31, #+0x124 (addr 0x8f1e9f3fc)
0x8f1e9f2dc   2dc  f840f044       ldur x4, [x2, #15]
0x8f1e9f2e0   2e0  b840f087       ldur w7, [x4, #15]
0x8f1e9f2e4   2e4  6b07007f       cmp w3, w7
0x8f1e9f2e8   2e8  54003782       b.hs #+0x6f0 (addr 0x8f1e9f9d8)
0x8f1e9f2ec   2ec  93407c6b       sxtw x11, w3
0x8f1e9f2f0   2f0  91005d6b       add x11, x11, #0x17 (23)
0x8f1e9f2f4   2f4  386b688b       ldrb w11, [x4, x11]
0x8f1e9f2f8   2f8  1200140c       and w12, w0, #0x3f
0x8f1e9f2fc   2fc  9acc216b       lsl x11, x11, x12
0x8f1e9f300   300  f800f0cb       stur x11, [x6, #15]
0x8f1e9f304   304  d28ccced       movz x13, #0x6667
0x8f1e9f308   308  f2accccd       movk x13, #0x6666, lsl #16
0x8f1e9f30c   30c  f2cccccd       movk x13, #0x6666, lsl #32
0x8f1e9f310   310  f2eccccd       movk x13, #0x6666, lsl #48
0x8f1e9f314   314  9b4d7d6e       smulh x14, x11, x13
0x8f1e9f318   318  9342fdce       asr x14, x14, #2
0x8f1e9f31c   31c  8b4bfdce       add x14, x14, x11, lsr #63
0x8f1e9f320   320  d280014f       movz x15, #0xa
0x8f1e9f324   324  9b0fadcb       msub x11, x14, x15, x11
0x8f1e9f328   328  51000533       sub w19, w9, #0x1 (1)
0x8f1e9f32c   32c  b800f153       stur w19, [x10, #15]
0x8f1e9f330   330  6b07027f       cmp w19, w7
0x8f1e9f334   334  540000ab       b.lt #+0x14 (addr 0x8f1e9f348)
0x8f1e9f338   338  3400012b       cbz w11, #+0x24 (addr 0x8f1e9f35c)
0x8f1e9f33c   33c  d2800034       movz x20, #0x1
0x8f1e9f340   340  b8023054       stur w20, [x2, #35]
0x8f1e9f344   344  14000006       b #+0x18 (addr 0x8f1e9f35c)
0x8f1e9f348   348  6b07027f       cmp w19, w7
0x8f1e9f34c   34c  54003442       b.hs #+0x688 (addr 0x8f1e9f9d4)
0x8f1e9f350   350  93407e73       sxtw x19, w19
0x8f1e9f354   354  91005e73       add x19, x19, #0x17 (23)
0x8f1e9f358   358  3833688b       strb w11, [x4, x19]
0x8f1e9f35c   35c  f800f0ce       stur x14, [x6, #15]
0x8f1e9f360   360  51000463       sub w3, w3, #0x1 (1)
0x8f1e9f364   364  b800f103       stur w3, [x8, #15]
0x8f1e9f368   368  14000004       b #+0x10 (addr 0x8f1e9f378)
0x8f1e9f36c   36c  f800f0ce       stur x14, [x6, #15]
0x8f1e9f370   370  51000463       sub w3, w3, #0x1 (1)
0x8f1e9f374   374  b800f103       stur w3, [x8, #15]
0x8f1e9f378   378  f8520343       ldur x3, [x26, #-224]
0x8f1e9f37c   37c  eb2363ff       cmp sp, x3
0x8f1e9f380   380  540029a9       b.ls #+0x534 (addr 0x8f1e9f8b4)
0x8f1e9f384   384  b840f103       ldur w3, [x8, #15]
0x8f1e9f388   388  37f803a3       tbnz w3, #31, #+0x74 (addr 0x8f1e9f3fc)
0x8f1e9f38c   38c  6b07007f       cmp w3, w7
0x8f1e9f390   390  54003202       b.hs #+0x640 (addr 0x8f1e9f9d0)
0x8f1e9f394   394  93407c6b       sxtw x11, w3
0x8f1e9f398   398  91005d6b       add x11, x11, #0x17 (23)
0x8f1e9f39c   39c  386b688b       ldrb w11, [x4, x11]
0x8f1e9f3a0   3a0  f840f0ce       ldur x14, [x6, #15]
0x8f1e9f3a4   3a4  9acc216b       lsl x11, x11, x12
0x8f1e9f3a8   3a8  8b0b01cb       add x11, x14, x11
0x8f1e9f3ac   3ac  f800f0cb       stur x11, [x6, #15]
0x8f1e9f3b0   3b0  9b4d7d6e       smulh x14, x11, x13
0x8f1e9f3b4   3b4  9342fdce       asr x14, x14, #2
0x8f1e9f3b8   3b8  8b4bfdce       add x14, x14, x11, lsr #63
0x8f1e9f3bc   3bc  9b0fadcb       msub x11, x14, x15, x11
0x8f1e9f3c0   3c0  b840f153       ldur w19, [x10, #15]
0x8f1e9f3c4   3c4  51000673       sub w19, w19, #0x1 (1)
0x8f1e9f3c8   3c8  b800f153       stur w19, [x10, #15]
0x8f1e9f3cc   3cc  6b07027f       cmp w19, w7
0x8f1e9f3d0   3d0  540000ab       b.lt #+0x14 (addr 0x8f1e9f3e4)
0x8f1e9f3d4   3d4  34fffccb       cbz w11, #-0x68 (addr 0x8f1e9f36c)
0x8f1e9f3d8   3d8  d2800034       movz x20, #0x1
0x8f1e9f3dc   3dc  b8023054       stur w20, [x2, #35]
0x8f1e9f3e0   3e0  17ffffe3       b #-0x74 (addr 0x8f1e9f36c)
0x8f1e9f3e4   3e4  6b07027f       cmp w19, w7
0x8f1e9f3e8   3e8  54002f22       b.hs #+0x5e4 (addr 0x8f1e9f9cc)
0x8f1e9f3ec   3ec  93407e73       sxtw x19, w19
0x8f1e9f3f0   3f0  91005e73       add x19, x19, #0x17 (23)
0x8f1e9f3f4   3f4  3833688b       strb w11, [x4, x19]
0x8f1e9f3f8   3f8  17ffffdd       b #-0x8c (addr 0x8f1e9f36c)
0x8f1e9f3fc   3fc  f840f0c3       ldur x3, [x6, #15]
0x8f1e9f400   400  f100007f       cmp x3, #0x0 (0)
0x8f1e9f404   404  54000e4d       b.le #+0x1c8 (addr 0x8f1e9f5cc)
0x8f1e9f408   408  d28ccce4       movz x4, #0x6667
0x8f1e9f40c   40c  f2acccc4       movk x4, #0x6666, lsl #16
0x8f1e9f410   410  f2ccccc4       movk x4, #0x6666, lsl #32
0x8f1e9f414   414  f2ecccc4       movk x4, #0x6666, lsl #48
0x8f1e9f418   418  9b447c67       smulh x7, x3, x4
0x8f1e9f41c   41c  9342fce7       asr x7, x7, #2
0x8f1e9f420   420  8b43fce7       add x7, x7, x3, lsr #63
0x8f1e9f424   424  d2800148       movz x8, #0xa
0x8f1e9f428   428  9b088ce3       msub x3, x7, x8, x3
0x8f1e9f42c   42c  b840f14b       ldur w11, [x10, #15]
0x8f1e9f430   430  5100056b       sub w11, w11, #0x1 (1)
0x8f1e9f434   434  b800f14b       stur w11, [x10, #15]
0x8f1e9f438   438  f840f04c       ldur x12, [x2, #15]
0x8f1e9f43c   43c  b840f18d       ldur w13, [x12, #15]
0x8f1e9f440   440  6b0d017f       cmp w11, w13
0x8f1e9f444   444  540000ab       b.lt #+0x14 (addr 0x8f1e9f458)
0x8f1e9f448   448  34000123       cbz w3, #+0x24 (addr 0x8f1e9f46c)
0x8f1e9f44c   44c  d280002e       movz x14, #0x1
0x8f1e9f450   450  b802304e       stur w14, [x2, #35]
0x8f1e9f454   454  14000006       b #+0x18 (addr 0x8f1e9f46c)
0x8f1e9f458   458  6b0d017f       cmp w11, w13
0x8f1e9f45c   45c  54002b62       b.hs #+0x56c (addr 0x8f1e9f9c8)
0x8f1e9f460   460  93407d6b       sxtw x11, w11
0x8f1e9f464   464  91005d6b       add x11, x11, #0x17 (23)
0x8f1e9f468   468  382b6983       strb w3, [x12, x11]
0x8f1e9f46c   46c  f800f0c7       stur x7, [x6, #15]
0x8f1e9f470   470  14000002       b #+0x8 (addr 0x8f1e9f478)
0x8f1e9f474   474  f800f0c3       stur x3, [x6, #15]
0x8f1e9f478   478  f840f0c3       ldur x3, [x6, #15]
0x8f1e9f47c   47c  f100007f       cmp x3, #0x0 (0)
0x8f1e9f480   480  54000a6d       b.le #+0x14c (addr 0x8f1e9f5cc)
0x8f1e9f484   484  9b447c67       smulh x7, x3, x4
0x8f1e9f488   488  9342fce7       asr x7, x7, #2
0x8f1e9f48c   48c  8b43fce7       add x7, x7, x3, lsr #63
0x8f1e9f490   490  9b088ce3       msub x3, x7, x8, x3
0x8f1e9f494   494  b840f14b       ldur w11, [x10, #15]
0x8f1e9f498   498  5100056b       sub w11, w11, #0x1 (1)
0x8f1e9f49c   49c  b800f14b       stur w11, [x10, #15]
0x8f1e9f4a0   4a0  6b0d017f       cmp w11, w13
0x8f1e9f4a4   4a4  540000ab       b.lt #+0x14 (addr 0x8f1e9f4b8)
0x8f1e9f4a8   4a8  34000123       cbz w3, #+0x24 (addr 0x8f1e9f4cc)
0x8f1e9f4ac   4ac  d280002e       movz x14, #0x1
0x8f1e9f4b0   4b0  b802304e       stur w14, [x2, #35]
0x8f1e9f4b4   4b4  14000006       b #+0x18 (addr 0x8f1e9f4cc)
0x8f1e9f4b8   4b8  6b0d017f       cmp w11, w13
0x8f1e9f4bc   4bc  54002842       b.hs #+0x508 (addr 0x8f1e9f9c4)
0x8f1e9f4c0   4c0  93407d6e       sxtw x14, w11
0x8f1e9f4c4   4c4  91005dce       add x14, x14, #0x17 (23)
0x8f1e9f4c8   4c8  382e6983       strb w3, [x12, x14]
0x8f1e9f4cc   4cc  f800f0c7       stur x7, [x6, #15]
0x8f1e9f4d0   4d0  f10000ff       cmp x7, #0x0 (0)
0x8f1e9f4d4   4d4  540007cd       b.le #+0xf8 (addr 0x8f1e9f5cc)
0x8f1e9f4d8   4d8  9b447ce3       smulh x3, x7, x4
0x8f1e9f4dc   4dc  9342fc63       asr x3, x3, #2
0x8f1e9f4e0   4e0  8b47fc63       add x3, x3, x7, lsr #63
0x8f1e9f4e4   4e4  9b089c67       msub x7, x3, x8, x7
0x8f1e9f4e8   4e8  5100056b       sub w11, w11, #0x1 (1)
0x8f1e9f4ec   4ec  b800f14b       stur w11, [x10, #15]
0x8f1e9f4f0   4f0  6b0d017f       cmp w11, w13
0x8f1e9f4f4   4f4  540000ab       b.lt #+0x14 (addr 0x8f1e9f508)
0x8f1e9f4f8   4f8  34000127       cbz w7, #+0x24 (addr 0x8f1e9f51c)
0x8f1e9f4fc   4fc  d280002e       movz x14, #0x1
0x8f1e9f500   500  b802304e       stur w14, [x2, #35]
0x8f1e9f504   504  14000006       b #+0x18 (addr 0x8f1e9f51c)
0x8f1e9f508   508  6b0d017f       cmp w11, w13
0x8f1e9f50c   50c  540025a2       b.hs #+0x4b4 (addr 0x8f1e9f9c0)
0x8f1e9f510   510  93407d6e       sxtw x14, w11
0x8f1e9f514   514  91005dce       add x14, x14, #0x17 (23)
0x8f1e9f518   518  382e6987       strb w7, [x12, x14]
0x8f1e9f51c   51c  f800f0c3       stur x3, [x6, #15]
0x8f1e9f520   520  f100007f       cmp x3, #0x0 (0)
0x8f1e9f524   524  5400054d       b.le #+0xa8 (addr 0x8f1e9f5cc)
0x8f1e9f528   528  9b447c67       smulh x7, x3, x4
0x8f1e9f52c   52c  9342fce7       asr x7, x7, #2
0x8f1e9f530   530  8b43fce7       add x7, x7, x3, lsr #63
0x8f1e9f534   534  9b088ce3       msub x3, x7, x8, x3
0x8f1e9f538   538  5100056b       sub w11, w11, #0x1 (1)
0x8f1e9f53c   53c  b800f14b       stur w11, [x10, #15]
0x8f1e9f540   540  6b0d017f       cmp w11, w13
0x8f1e9f544   544  540000ab       b.lt #+0x14 (addr 0x8f1e9f558)
0x8f1e9f548   548  34000123       cbz w3, #+0x24 (addr 0x8f1e9f56c)
0x8f1e9f54c   54c  d280002e       movz x14, #0x1
0x8f1e9f550   550  b802304e       stur w14, [x2, #35]
0x8f1e9f554   554  14000006       b #+0x18 (addr 0x8f1e9f56c)
0x8f1e9f558   558  6b0d017f       cmp w11, w13
0x8f1e9f55c   55c  54002302       b.hs #+0x460 (addr 0x8f1e9f9bc)
0x8f1e9f560   560  93407d6e       sxtw x14, w11
0x8f1e9f564   564  91005dce       add x14, x14, #0x17 (23)
0x8f1e9f568   568  382e6983       strb w3, [x12, x14]
0x8f1e9f56c   56c  f800f0c7       stur x7, [x6, #15]
0x8f1e9f570   570  f8520343       ldur x3, [x26, #-224]
0x8f1e9f574   574  eb2363ff       cmp sp, x3
0x8f1e9f578   578  54001d09       b.ls #+0x3a0 (addr 0x8f1e9f918)
0x8f1e9f57c   57c  f10000ff       cmp x7, #0x0 (0)
0x8f1e9f580   580  5400026d       b.le #+0x4c (addr 0x8f1e9f5cc)
0x8f1e9f584   584  9b447ce3       smulh x3, x7, x4
0x8f1e9f588   588  9342fc63       asr x3, x3, #2
0x8f1e9f58c   58c  8b47fc63       add x3, x3, x7, lsr #63
0x8f1e9f590   590  9b089c67       msub x7, x3, x8, x7
0x8f1e9f594   594  5100056b       sub w11, w11, #0x1 (1)
0x8f1e9f598   598  b800f14b       stur w11, [x10, #15]
0x8f1e9f59c   59c  6b0d017f       cmp w11, w13
0x8f1e9f5a0   5a0  540000ab       b.lt #+0x14 (addr 0x8f1e9f5b4)
0x8f1e9f5a4   5a4  34fff687       cbz w7, #-0x130 (addr 0x8f1e9f474)
0x8f1e9f5a8   5a8  d280002e       movz x14, #0x1
0x8f1e9f5ac   5ac  b802304e       stur w14, [x2, #35]
0x8f1e9f5b0   5b0  17ffffb1       b #-0x13c (addr 0x8f1e9f474)
0x8f1e9f5b4   5b4  6b0d017f       cmp w11, w13
0x8f1e9f5b8   5b8  54002002       b.hs #+0x400 (addr 0x8f1e9f9b8)
0x8f1e9f5bc   5bc  93407d6b       sxtw x11, w11
0x8f1e9f5c0   5c0  91005d6b       add x11, x11, #0x17 (23)
0x8f1e9f5c4   5c4  382b6987       strb w7, [x12, x11]
0x8f1e9f5c8   5c8  17ffffab       b #-0x154 (addr 0x8f1e9f474)
0x8f1e9f5cc   5cc  b8017049       stur w9, [x2, #23]
0x8f1e9f5d0   5d0  f840f043       ldur x3, [x2, #15]
0x8f1e9f5d4   5d4  b840f064       ldur w4, [x3, #15]
0x8f1e9f5d8   5d8  6b09009f       cmp w4, w9
0x8f1e9f5dc   5dc  5400004a       b.ge #+0x8 (addr 0x8f1e9f5e4)
0x8f1e9f5e0   5e0  b8017044       stur w4, [x2, #23]
0x8f1e9f5e4   5e4  b841b046       ldur w6, [x2, #27]
0x8f1e9f5e8   5e8  0b0500c5       add w5, w6, w5
0x8f1e9f5ec   5ec  b801b045       stur w5, [x2, #27]
0x8f1e9f5f0   5f0  b8417045       ldur w5, [x2, #23]
0x8f1e9f5f4   5f4  710000bf       cmp w5, #0x0 (0)
0x8f1e9f5f8   5f8  540006cd       b.le #+0xd8 (addr 0x8f1e9f6d0)
0x8f1e9f5fc   5fc  510004a5       sub w5, w5, #0x1 (1)
0x8f1e9f600   600  6b0400bf       cmp w5, w4
0x8f1e9f604   604  54001d82       b.hs #+0x3b0 (addr 0x8f1e9f9b4)
0x8f1e9f608   608  93407ca6       sxtw x6, w5
0x8f1e9f60c   60c  91005cc6       add x6, x6, #0x17 (23)
0x8f1e9f610   610  38666866       ldrb w6, [x3, x6]
0x8f1e9f614   614  350005e6       cbnz w6, #+0xbc (addr 0x8f1e9f6d0)
0x8f1e9f618   618  b8017045       stur w5, [x2, #23]
0x8f1e9f61c   61c  14000002       b #+0x8 (addr 0x8f1e9f624)
0x8f1e9f620   620  b8017045       stur w5, [x2, #23]
0x8f1e9f624   624  b8417045       ldur w5, [x2, #23]
0x8f1e9f628   628  710000bf       cmp w5, #0x0 (0)
0x8f1e9f62c   62c  5400052d       b.le #+0xa4 (addr 0x8f1e9f6d0)
0x8f1e9f630   630  510004a5       sub w5, w5, #0x1 (1)
0x8f1e9f634   634  6b0400bf       cmp w5, w4
0x8f1e9f638   638  54001bc2       b.hs #+0x378 (addr 0x8f1e9f9b0)
0x8f1e9f63c   63c  93407ca6       sxtw x6, w5
0x8f1e9f640   640  91005cc6       add x6, x6, #0x17 (23)
0x8f1e9f644   644  38666866       ldrb w6, [x3, x6]
0x8f1e9f648   648  35000446       cbnz w6, #+0x88 (addr 0x8f1e9f6d0)
0x8f1e9f64c   64c  b8017045       stur w5, [x2, #23]
0x8f1e9f650   650  710000bf       cmp w5, #0x0 (0)
0x8f1e9f654   654  540003ed       b.le #+0x7c (addr 0x8f1e9f6d0)
0x8f1e9f658   658  510004a5       sub w5, w5, #0x1 (1)
0x8f1e9f65c   65c  6b0400bf       cmp w5, w4
0x8f1e9f660   660  54001a62       b.hs #+0x34c (addr 0x8f1e9f9ac)
0x8f1e9f664   664  93407ca6       sxtw x6, w5
0x8f1e9f668   668  91005cc6       add x6, x6, #0x17 (23)
0x8f1e9f66c   66c  38666866       ldrb w6, [x3, x6]
0x8f1e9f670   670  35000306       cbnz w6, #+0x60 (addr 0x8f1e9f6d0)
0x8f1e9f674   674  b8017045       stur w5, [x2, #23]
0x8f1e9f678   678  710000bf       cmp w5, #0x0 (0)
0x8f1e9f67c   67c  540002ad       b.le #+0x54 (addr 0x8f1e9f6d0)
0x8f1e9f680   680  510004a5       sub w5, w5, #0x1 (1)
0x8f1e9f684   684  6b0400bf       cmp w5, w4
0x8f1e9f688   688  54001902       b.hs #+0x320 (addr 0x8f1e9f9a8)
0x8f1e9f68c   68c  93407ca6       sxtw x6, w5
0x8f1e9f690   690  91005cc6       add x6, x6, #0x17 (23)
0x8f1e9f694   694  38666866       ldrb w6, [x3, x6]
0x8f1e9f698   698  350001c6       cbnz w6, #+0x38 (addr 0x8f1e9f6d0)
0x8f1e9f69c   69c  b8017045       stur w5, [x2, #23]
0x8f1e9f6a0   6a0  f8520346       ldur x6, [x26, #-224]
0x8f1e9f6a4   6a4  eb2663ff       cmp sp, x6
0x8f1e9f6a8   6a8  540016a9       b.ls #+0x2d4 (addr 0x8f1e9f97c)
0x8f1e9f6ac   6ac  710000bf       cmp w5, #0x0 (0)
0x8f1e9f6b0   6b0  5400010d       b.le #+0x20 (addr 0x8f1e9f6d0)
0x8f1e9f6b4   6b4  510004a5       sub w5, w5, #0x1 (1)
0x8f1e9f6b8   6b8  6b0400bf       cmp w5, w4
0x8f1e9f6bc   6bc  54001742       b.hs #+0x2e8 (addr 0x8f1e9f9a4)
0x8f1e9f6c0   6c0  93407ca6       sxtw x6, w5
0x8f1e9f6c4   6c4  91005cc6       add x6, x6, #0x17 (23)
0x8f1e9f6c8   6c8  38666866       ldrb w6, [x3, x6]
0x8f1e9f6cc   6cc  34fffaa6       cbz w6, #-0xac (addr 0x8f1e9f620)
0x8f1e9f6d0   6d0  b8417043       ldur w3, [x2, #23]
0x8f1e9f6d4   6d4  350000c3       cbnz w3, #+0x18 (addr 0x8f1e9f6ec)
0x8f1e9f6d8   6d8  b801b05f       stur wzr, [x2, #27]
0x8f1e9f6dc   6dc  d2800000       movz x0, #0x0
0x8f1e9f6e0   6e0  910003bf       mov sp, fp
0x8f1e9f6e4   6e4  a8c17bfd       ldp fp, lr, [sp], #16
0x8f1e9f6e8   6e8  d65f03c0       ret
0x8f1e9f6ec   6ec  d2800000       movz x0, #0x0
0x8f1e9f6f0   6f0  17fffffc       b #-0x10 (addr 0x8f1e9f6e0)
0x8f1e9f6f4   6f4  f90027e2       str x2, [sp, #72]
0x8f1e9f6f8   6f8  f90003e0       str x0, [sp]
0x8f1e9f6fc   6fc  f90023e3       str x3, [sp, #64]
0x8f1e9f700   700  94000540       bl #+0x1500 (addr 0x8f1ea0c00)
0x8f1e9f704   704  f94027e2       ldr x2, [sp, #72]
0x8f1e9f708   708  f94003e0       ldr x0, [sp]
0x8f1e9f70c   70c  f9402be7       ldr x7, [sp, #80]
0x8f1e9f710   710  f94023e3       ldr x3, [sp, #64]
0x8f1e9f714   714  17fffe44       b #-0x6f0 (addr 0x8f1e9f024)
0x8f1e9f718   718  f90027e2       str x2, [sp, #72]
0x8f1e9f71c   71c  f90003e0       str x0, [sp]
0x8f1e9f720   720  f90023e3       str x3, [sp, #64]
0x8f1e9f724   724  f90017e5       str x5, [sp, #40]
0x8f1e9f728   728  f90007ea       str x10, [sp, #8]
0x8f1e9f72c   72c  f90013eb       str x11, [sp, #32]
0x8f1e9f730   730  f9001be8       str x8, [sp, #48]
0x8f1e9f734   734  f9000fe9       str x9, [sp, #24]
0x8f1e9f738   738  f9000be4       str x4, [sp, #16]
0x8f1e9f73c   73c  f9001fe6       str x6, [sp, #56]
0x8f1e9f740   740  94000540       bl #+0x1500 (addr 0x8f1ea0c40)
0x8f1e9f744   744  f94027e2       ldr x2, [sp, #72]
0x8f1e9f748   748  f94003e0       ldr x0, [sp]
0x8f1e9f74c   74c  f9402be7       ldr x7, [sp, #80]
0x8f1e9f750   750  f94023e3       ldr x3, [sp, #64]
0x8f1e9f754   754  f94017e5       ldr x5, [sp, #40]
0x8f1e9f758   758  f94007ea       ldr x10, [sp, #8]
0x8f1e9f75c   75c  f94013eb       ldr x11, [sp, #32]
0x8f1e9f760   760  f9401be8       ldr x8, [sp, #48]
0x8f1e9f764   764  f9400fe9       ldr x9, [sp, #24]
0x8f1e9f768   768  f9400be4       ldr x4, [sp, #16]
0x8f1e9f76c   76c  f9401fe6       ldr x6, [sp, #56]
0x8f1e9f770   770  17fffe8d       b #-0x5cc (addr 0x8f1e9f1a4)
0x8f1e9f774   774  f90027e2       str x2, [sp, #72]
0x8f1e9f778   778  d2c01002       movz x2, #0x8000000000
0x8f1e9f77c   77c  d2800301       movz x1, #0x18
0x8f1e9f780   780  f90017e5       str x5, [sp, #40]
0x8f1e9f784   784  f90003e0       str x0, [sp]
0x8f1e9f788   788  f90007e4       str x4, [sp, #8]
0x8f1e9f78c   78c  f90023e3       str x3, [sp, #64]
0x8f1e9f790   790  f9000fe6       str x6, [sp, #24]
0x8f1e9f794   794  f9001fe8       str x8, [sp, #56]
0x8f1e9f798   798  aa0203e9       mov x9, x2
0x8f1e9f79c   79c  935dfc42       asr x2, x2, #29
0x8f1e9f7a0   7a0  d28a2610       movz x16, #0x5130
0x8f1e9f7a4   7a4  8b100042       add x2, x2, x16
0x8f1e9f7a8   7a8  f8626b42       ldr x2, [x26, x2]
0x8f1e9f7ac   7ac  d63f0040       blr x2
0x8f1e9f7b0   7b0  d1000409       sub x9, x0, #0x1 (1)
0x8f1e9f7b4   7b4  f9401fe8       ldr x8, [sp, #56]
0x8f1e9f7b8   7b8  f94027e2       ldr x2, [sp, #72]
0x8f1e9f7bc   7bc  f94017e5       ldr x5, [sp, #40]
0x8f1e9f7c0   7c0  f94003e0       ldr x0, [sp]
0x8f1e9f7c4   7c4  f94007e4       ldr x4, [sp, #8]
0x8f1e9f7c8   7c8  f9402be7       ldr x7, [sp, #80]
0x8f1e9f7cc   7cc  f94023e3       ldr x3, [sp, #64]
0x8f1e9f7d0   7d0  f9400fe6       ldr x6, [sp, #24]
0x8f1e9f7d4   7d4  17fffe99       b #-0x59c (addr 0x8f1e9f238)
0x8f1e9f7d8   7d8  f90027e2       str x2, [sp, #72]
0x8f1e9f7dc   7dc  f90017e5       str x5, [sp, #40]
0x8f1e9f7e0   7e0  f9001be9       str x9, [sp, #48]
0x8f1e9f7e4   7e4  f9001fe8       str x8, [sp, #56]
0x8f1e9f7e8   7e8  f90003e0       str x0, [sp]
0x8f1e9f7ec   7ec  f90007e4       str x4, [sp, #8]
0x8f1e9f7f0   7f0  f90023e3       str x3, [sp, #64]
0x8f1e9f7f4   7f4  f9000fe6       str x6, [sp, #24]
0x8f1e9f7f8   7f8  f90013ea       str x10, [sp, #32]
0x8f1e9f7fc   7fc  d2800301       movz x1, #0x18
0x8f1e9f800   800  d2c01002       movz x2, #0x8000000000
0x8f1e9f804   804  935dfc42       asr x2, x2, #29
0x8f1e9f808   808  d28a2610       movz x16, #0x5130
0x8f1e9f80c   80c  8b100042       add x2, x2, x16
0x8f1e9f810   810  f8626b42       ldr x2, [x26, x2]
0x8f1e9f814   814  d63f0040       blr x2
0x8f1e9f818   818  d100040b       sub x11, x0, #0x1 (1)
0x8f1e9f81c   81c  f94013ea       ldr x10, [sp, #32]
0x8f1e9f820   820  f94027e2       ldr x2, [sp, #72]
0x8f1e9f824   824  f94017e5       ldr x5, [sp, #40]
0x8f1e9f828   828  f9401be9       ldr x9, [sp, #48]
0x8f1e9f82c   82c  f9401fe8       ldr x8, [sp, #56]
0x8f1e9f830   830  f94003e0       ldr x0, [sp]
0x8f1e9f834   834  f94007e4       ldr x4, [sp, #8]
0x8f1e9f838   838  f9402be7       ldr x7, [sp, #80]
0x8f1e9f83c   83c  f94023e3       ldr x3, [sp, #64]
0x8f1e9f840   840  f9400fe6       ldr x6, [sp, #24]
0x8f1e9f844   844  17fffe8c       b #-0x5d0 (addr 0x8f1e9f274)
0x8f1e9f848   848  f90027e2       str x2, [sp, #72]
0x8f1e9f84c   84c  f90017e5       str x5, [sp, #40]
0x8f1e9f850   850  f9001be9       str x9, [sp, #48]
0x8f1e9f854   854  f9000bea       str x10, [sp, #16]
0x8f1e9f858   858  f9001fe8       str x8, [sp, #56]
0x8f1e9f85c   85c  f90003e0       str x0, [sp]
0x8f1e9f860   860  f90007e4       str x4, [sp, #8]
0x8f1e9f864   864  f90013e3       str x3, [sp, #32]
0x8f1e9f868   868  f90023e6       str x6, [sp, #64]
0x8f1e9f86c   86c  d2800301       movz x1, #0x18
0x8f1e9f870   870  d2c01007       movz x7, #0x8000000000
0x8f1e9f874   874  935dfce7       asr x7, x7, #29
0x8f1e9f878   878  d28a2610       movz x16, #0x5130
0x8f1e9f87c   87c  8b1000e7       add x7, x7, x16
0x8f1e9f880   880  f8676b47       ldr x7, [x26, x7]
0x8f1e9f884   884  d63f00e0       blr x7
0x8f1e9f888   888  d100040b       sub x11, x0, #0x1 (1)
0x8f1e9f88c   88c  f94023e6       ldr x6, [sp, #64]
0x8f1e9f890   890  f94027e2       ldr x2, [sp, #72]
0x8f1e9f894   894  f94017e5       ldr x5, [sp, #40]
0x8f1e9f898   898  f9401be9       ldr x9, [sp, #48]
0x8f1e9f89c   89c  f9400bea       ldr x10, [sp, #16]
0x8f1e9f8a0   8a0  f9401fe8       ldr x8, [sp, #56]
0x8f1e9f8a4   8a4  f94003e0       ldr x0, [sp]
0x8f1e9f8a8   8a8  f94007e4       ldr x4, [sp, #8]
0x8f1e9f8ac   8ac  f94013e3       ldr x3, [sp, #32]
0x8f1e9f8b0   8b0  17fffe81       b #-0x5fc (addr 0x8f1e9f2b4)
0x8f1e9f8b4   8b4  f90027e2       str x2, [sp, #72]
0x8f1e9f8b8   8b8  f90017e5       str x5, [sp, #40]
0x8f1e9f8bc   8bc  f9001be9       str x9, [sp, #48]
0x8f1e9f8c0   8c0  f90023e6       str x6, [sp, #64]
0x8f1e9f8c4   8c4  f9000bea       str x10, [sp, #16]
0x8f1e9f8c8   8c8  f9001fe8       str x8, [sp, #56]
0x8f1e9f8cc   8cc  f90013e4       str x4, [sp, #32]
0x8f1e9f8d0   8d0  f9000fe7       str x7, [sp, #24]
0x8f1e9f8d4   8d4  f90007ec       str x12, [sp, #8]
0x8f1e9f8d8   8d8  94000540       bl #+0x1500 (addr 0x8f1ea0dd8)
0x8f1e9f8dc   8dc  f94027e2       ldr x2, [sp, #72]
0x8f1e9f8e0   8e0  f94017e5       ldr x5, [sp, #40]
0x8f1e9f8e4   8e4  f9401be9       ldr x9, [sp, #48]
0x8f1e9f8e8   8e8  f94023e6       ldr x6, [sp, #64]
0x8f1e9f8ec   8ec  f9400bea       ldr x10, [sp, #16]
0x8f1e9f8f0   8f0  f9401fe8       ldr x8, [sp, #56]
0x8f1e9f8f4   8f4  f94013e4       ldr x4, [sp, #32]
0x8f1e9f8f8   8f8  f9400fe7       ldr x7, [sp, #24]
0x8f1e9f8fc   8fc  d280014f       movz x15, #0xa
0x8f1e9f900   900  d28ccced       movz x13, #0x6667
0x8f1e9f904   904  f2accccd       movk x13, #0x6666, lsl #16
0x8f1e9f908   908  f2cccccd       movk x13, #0x6666, lsl #32
0x8f1e9f90c   90c  f2eccccd       movk x13, #0x6666, lsl #48
0x8f1e9f910   910  f94007ec       ldr x12, [sp, #8]
0x8f1e9f914   914  17fffe9c       b #-0x590 (addr 0x8f1e9f384)
0x8f1e9f918   918  f90027e2       str x2, [sp, #72]
0x8f1e9f91c   91c  f90017e5       str x5, [sp, #40]
0x8f1e9f920   920  f9001be9       str x9, [sp, #48]
0x8f1e9f924   924  f90023e6       str x6, [sp, #64]
0x8f1e9f928   928  f9001fec       str x12, [sp, #56]
0x8f1e9f92c   92c  f90013ed       str x13, [sp, #32]
0x8f1e9f930   930  f9000bea       str x10, [sp, #16]
0x8f1e9f934   934  f9000feb       str x11, [sp, #24]
0x8f1e9f938   938  f90007e7       str x7, [sp, #8]
0x8f1e9f93c   93c  94000540       bl #+0x1500 (addr 0x8f1ea0e3c)
0x8f1e9f940   940  f94027e2       ldr x2, [sp, #72]
0x8f1e9f944   944  f94017e5       ldr x5, [sp, #40]
0x8f1e9f948   948  f9401be9       ldr x9, [sp, #48]
0x8f1e9f94c   94c  f94023e6       ldr x6, [sp, #64]
0x8f1e9f950   950  f9401fec       ldr x12, [sp, #56]
0x8f1e9f954   954  f94013ed       ldr x13, [sp, #32]
0x8f1e9f958   958  f9400bea       ldr x10, [sp, #16]
0x8f1e9f95c   95c  f9400feb       ldr x11, [sp, #24]
0x8f1e9f960   960  d2800148       movz x8, #0xa
0x8f1e9f964   964  f94007e7       ldr x7, [sp, #8]
0x8f1e9f968   968  d28ccce4       movz x4, #0x6667
0x8f1e9f96c   96c  f2acccc4       movk x4, #0x6666, lsl #16
0x8f1e9f970   970  f2ccccc4       movk x4, #0x6666, lsl #32
0x8f1e9f974   974  f2ecccc4       movk x4, #0x6666, lsl #48
0x8f1e9f978   978  17ffff01       b #-0x3fc (addr 0x8f1e9f57c)
0x8f1e9f97c   97c  f90027e2       str x2, [sp, #72]
0x8f1e9f980   980  f90023e3       str x3, [sp, #64]
0x8f1e9f984   984  f9001fe4       str x4, [sp, #56]
0x8f1e9f988   988  f9001be5       str x5, [sp, #48]
0x8f1e9f98c   98c  94000540       bl #+0x1500 (addr 0x8f1ea0e8c)
0x8f1e9f990   990  f94027e2       ldr x2, [sp, #72]
0x8f1e9f994   994  f94023e3       ldr x3, [sp, #64]
0x8f1e9f998   998  f9401fe4       ldr x4, [sp, #56]
0x8f1e9f99c   99c  f9401be5       ldr x5, [sp, #48]
0x8f1e9f9a0   9a0  17ffff43       b #-0x2f4 (addr 0x8f1e9f6ac)
0x8f1e9f9a4   9a4  94000568       bl #+0x15a0 (addr 0x8f1ea0f44)
0x8f1e9f9a8   9a8  94000568       bl #+0x15a0 (addr 0x8f1ea0f48)
0x8f1e9f9ac   9ac  94000568       bl #+0x15a0 (addr 0x8f1ea0f4c)
0x8f1e9f9b0   9b0  94000568       bl #+0x15a0 (addr 0x8f1ea0f50)
0x8f1e9f9b4   9b4  94000568       bl #+0x15a0 (addr 0x8f1ea0f54)
0x8f1e9f9b8   9b8  94000568       bl #+0x15a0 (addr 0x8f1ea0f58)
0x8f1e9f9bc   9bc  94000568       bl #+0x15a0 (addr 0x8f1ea0f5c)
0x8f1e9f9c0   9c0  94000568       bl #+0x15a0 (addr 0x8f1ea0f60)
0x8f1e9f9c4   9c4  94000568       bl #+0x15a0 (addr 0x8f1ea0f64)
0x8f1e9f9c8   9c8  94000568       bl #+0x15a0 (addr 0x8f1ea0f68)
0x8f1e9f9cc   9cc  94000568       bl #+0x15a0 (addr 0x8f1ea0f6c)
0x8f1e9f9d0   9d0  94000568       bl #+0x15a0 (addr 0x8f1ea0f70)
0x8f1e9f9d4   9d4  94000568       bl #+0x15a0 (addr 0x8f1ea0f74)
0x8f1e9f9d8   9d8  94000568       bl #+0x15a0 (addr 0x8f1ea0f78)
0x8f1e9f9dc   9dc  94000568       bl #+0x15a0 (addr 0x8f1ea0f7c)
0x8f1e9f9e0   9e0  94000568       bl #+0x15a0 (addr 0x8f1ea0f80)
0x8f1e9f9e4   9e4  94000568       bl #+0x15a0 (addr 0x8f1ea0f84)
0x8f1e9f9e8   9e8  94000568       bl #+0x15a0 (addr 0x8f1ea0f88)
0x8f1e9f9ec   9ec  94000568       bl #+0x15a0 (addr 0x8f1ea0f8c)
0x8f1e9f9f0   9f0  94000568       bl #+0x15a0 (addr 0x8f1ea0f90)
0x8f1e9f9f4   9f4  94000568       bl #+0x15a0 (addr 0x8f1ea0f94)
0x8f1e9f9f8   9f8  94000568       bl #+0x15a0 (addr 0x8f1ea0f98)
0x8f1e9f9fc   9fc  94000568       bl #+0x15a0 (addr 0x8f1ea0f9c)
0x8f1e9fa00   a00  94000568       bl #+0x15a0 (addr 0x8f1ea0fa0)
0x8f1e9fa04   a04  94000568       bl #+0x15a0 (addr 0x8f1ea0fa4)
0x8f1e9fa08   a08  94000566       bl #+0x1598 (addr 0x8f1ea0fa0)
0x8f1e9fa0c   a0c  94000568       bl #+0x15a0 (addr 0x8f1ea0fac)
0x8f1e9fa10   a10  94000566       bl #+0x1598 (addr 0x8f1ea0fa8)
0x8f1e9fa14   a14  d503201f       nop
```

## Function 453: right_shift

### Wasmoon optimized MilkIR

```text
function _M0MPC28internal7strconv7Decimal12right__shift(v0:i64, v1:ref, v2:i32) -> i32 {
block0:
    v14:i32 = iconst 0
    v15:ref = ext.wasm.struct_new [303] v14
    v16:i32 = iconst 0
    v17:ref = ext.wasm.struct_new [303] v16
    v18:i64 = iconst 0
    v19:ref = ext.wasm.struct_new [681] v18
    v196:i32 = iconst 0
    v198:ref = iconst 0
    v233:i32 = iconst 0
    v235:i32 = iconst 0
    jump block2(v14, v18, v196, v198, v233, v235)
block1(v151:i32, v153:i64):
    v60:i32 = ext.wasm.struct_get [244, 2] v1
    v62:i32 = iconst 1
    v63:i32 = isub v151, v62
    v64:i32 = isub v60, v63
    ext.wasm.struct_set [244, 2] v1, v64
    v66:i64 = iconst 1
    v68:i64 = ishl v66, v23
    v69:i64 = iconst 1
    v70:i64 = isub v68, v69
    v74:i32 = ext.wasm.struct_get [244, 1] v1
    v81:ref = ext.wasm.struct_get [244, 0] v1
    v207:i32 = iconst 0
    jump block15(v151, v16, v153, v207, v198)
block2(v154:i32, v156:i64, v199:i32, v200:ref, v236:i32, v237:i32):
    v23:i64 = sextend v2
    v24:i64 = ushr v156, v23
    v25:i64 = iconst 0
    v26:i32 = icmp.eq v24, v25
    branch v26, block4(v154, v156, v199, v200, v236, v237), block1(v154, v156)
block4(v157:i32, v159:i64, v203:i32, v204:ref, v244:i32, v245:i32):
    branch v244, block38(v245), block37()
block8(v160:i32, v201:i32, v202:ref, v241:i32):
    branch v201, block32(v202, v241), block31(v241)
block10(v163:i32, v165:i64):
    v33:i64 = ushr v165, v23
    v34:i64 = iconst 0
    v35:i32 = icmp.eq v33, v34
    branch v35, block12(v163), block1(v163, v165)
block12(v166:i32):
    v37:i64 = iconst 10
    v38:i64 = imul v165, v37
    v41:i32 = iconst 1
    v42:i32 = iadd v166, v41
    jump block10(v42, v38)
block15(v169:i32, v170:i32, v171:i64, v210:i32, v211:ref):
    v75:i32 = icmp.slt v169, v74
    branch v210, block34(v211), block33()
block17(v172:i32, v173:i32, v174:i64, v213:ref):
    v80:i64 = ushr v174, v23
    v144:i32 = ireduce v80
    v145:i32 = iconst 255
    v146:i32 = band v144, v145
    ext.wasm.array_set [2] v81, v173, v146
    v86:i32 = iconst 1
    v87:i32 = iadd v173, v86
    v90:i64 = band v174, v70
    v94:i32 = ext.wasm.array_get_u [2, 1] v81, v172
    v96:i64 = iconst 10
    v97:i64 = imul v90, v96
    v147:i64 = sextend v94
    v99:i64 = iadd v97, v147
    v102:i32 = iconst 1
    v103:i32 = iadd v172, v102
    v248:i32 = iconst 1
    jump block15(v103, v87, v99, v248, v213)
block20(v176:i32, v177:i64, v219:i32, v220:i32):
    v108:i64 = iconst 0
    v109:i32 = icmp.ne v177, v108
    branch v109, block22(v176, v177, v219, v220), block23(v176)
block22(v179:i32, v180:i64, v229:i32, v230:i32):
    v113:i64 = ushr v177, v23
    branch v229, block36(v230), block35()
block23(v182:i32):
    ext.wasm.struct_set [244, 1] v1, v182
    v142:i32 = ext.wasm.call [461] v1
    return v142
block25(v186:i64, v224:i32):
    v148:i32 = ireduce v113
    v149:i32 = iconst 255
    v150:i32 = band v148, v149
    ext.wasm.array_set [2] v214, v179, v150
    v123:i32 = iconst 1
    v124:i32 = iadd v179, v123
    jump block27(v124, v186, v224)
block26(v188:i32, v189:i64, v226:i32):
    v126:i64 = iconst 0
    v127:i32 = icmp.ne v113, v126
    branch v127, block28(v188, v189, v226), block27(v188, v189, v226)
block27(v191:i32, v192:i64, v222:i32):
    v133:i64 = band v192, v70
    v136:i64 = iconst 10
    v137:i64 = imul v133, v136
    v249:i32 = iconst 1
    jump block20(v191, v137, v249, v222)
block28(v194:i32, v195:i64, v228:i32):
    v128:i32 = iconst 1
    ext.wasm.struct_set [244, 4] v1, v128
    jump block27(v194, v195, v228)
block31(v243:i32):
    v206:ref = ext.wasm.struct_get [244, 0] v1
    jump block32(v206, v243)
block32(v205:ref, v239:i32):
    v48:i32 = ext.wasm.array_get_u [2, 1] v205, v157
    v50:i64 = iconst 10
    v51:i64 = imul v156, v50
    v143:i64 = sextend v48
    v53:i64 = iadd v51, v143
    v56:i32 = iconst 1
    v57:i32 = iadd v160, v56
    v250:i32 = iconst 1
    v251:i32 = iconst 1
    jump block2(v57, v53, v250, v205, v251, v239)
block33:
    v215:ref = ext.wasm.struct_get [244, 0] v1
    jump block34(v215)
block34(v214:ref):
    v216:i32 = iconst 0
    v218:i32 = iconst 0
    branch v75, block17(v169, v170, v171, v214), block20(v170, v171, v216, v218)
block35:
    v232:i32 = ext.wasm.array_len v214
    jump block36(v232)
block36(v231:i32):
    v117:i32 = icmp.slt v179, v231
    branch v117, block25(v180, v231), block26(v179, v180, v231)
block37:
    v247:i32 = ext.wasm.struct_get [244, 1] v1
    jump block38(v247)
block38(v246:i32):
    v30:i32 = icmp.sge v157, v246
    branch v30, block10(v157, v159), block8(v157, v203, v204, v246)
}
```

### Wasmoon VCode call-site order

```text
i14 PlatformCall(
  { name: "wasmoon.runtime.gc.push_root_scope" }
i15 PlatformCall(
  { name: "wasmoon.runtime.gc.alloc_struct_slow" }
i18 PlatformCall(
  { name: "wasmoon.runtime.gc.pop_root_scope" }
i31 PlatformCall(
  { name: "wasmoon.runtime.gc.push_root_scope" }
i32 PlatformCall(
  { name: "wasmoon.runtime.gc.alloc_struct_slow" }
i35 PlatformCall(
  { name: "wasmoon.runtime.gc.pop_root_scope" }
i47 PlatformCall(
  { name: "wasmoon.runtime.gc.push_root_scope" }
i48 PlatformCall(
  { name: "wasmoon.runtime.gc.alloc_struct_slow" }
i51 PlatformCall(
  { name: "wasmoon.runtime.gc.pop_root_scope" }
i65 PlatformCall(
  { name: "wasmoon.runtime.gc.struct_get_heap" }
i74 PlatformCall(
  { name: "wasmoon.runtime.gc.struct_get_heap" }
i80 PlatformCall(
  { name: "wasmoon.runtime.gc.array_get_heap" }
i97 PlatformCall(
  { name: "wasmoon.runtime.gc.struct_get_heap" }
i106 PlatformCall(
  { name: "wasmoon.runtime.gc.struct_set_heap" }
i113 PlatformCall(
  { name: "wasmoon.runtime.gc.struct_get_heap" }
i119 PlatformCall(
  { name: "wasmoon.runtime.gc.struct_get_heap" }
i124 PlatformCall(
  { name: "wasmoon.runtime.gc.array_data_heap" }
i138 PlatformCall(
  { name: "wasmoon.runtime.gc.struct_get_heap" }
i150 PlatformCall(
  { name: "wasmoon.runtime.gc.struct_set_heap" }
i154 PlatformCall(
  { name: "wasmoon.runtime.gc.push_root_scope" }
i155 InternalCall(
  { name: "wasm.func.461" }
i158 PlatformCall(
  { name: "wasmoon.runtime.gc.pop_root_scope" }
i164 PlatformCall(
  { name: "wasmoon.runtime.gc.array_len_heap" }
i174 PlatformCall(
  { name: "wasmoon.runtime.gc.struct_set_heap" }
i181 PlatformCall(
  { name: "wasmoon.runtime.gc.array_set_heap" }
i197 PlatformCall(
  { name: "wasmoon.runtime.gc.array_set_heap" }
i211 PlatformCall(
  { name: "wasmoon.runtime.gc.array_get_heap" }
```

### Wasmoon ARM64 machine code

```asm
/var/folders/n6/d4863hyd3078tg52nj9vppjr0000gn/T/wasmoon-568-comparison-rhbbmzio/wm-453.o:	file format mach-o arm64

Disassembly of section __TEXT,__text:

0000000000000000 <ltmp0>:
       0: d10043ff     	sub	sp, sp, #0x10
       4: a9007bfd     	stp	x29, x30, [sp]
       8: 910003fd     	mov	x29, sp
       c: d10303ff     	sub	sp, sp, #0xc0
      10: a90753f3     	stp	x19, x20, [sp, #0x70]
      14: a9085bf5     	stp	x21, x22, [sp, #0x80]
      18: a90963f7     	stp	x23, x24, [sp, #0x90]
      1c: a90a6bf9     	stp	x25, x26, [sp, #0xa0]
      20: a90b73fb     	stp	x27, x28, [sp, #0xb0]
      24: aa0003f3     	mov	x19, x0
      28: aa0103f4     	mov	x20, x1
      2c: b90053e2     	str	w2, [sp, #0x50]
      30: 52a00016     	movz	w22, #0x0, lsl #16
      34: 910003f5     	mov	x21, sp
      38: 2a1603e0     	mov	w0, w22
      3c: f90002a0     	str	x0, [x21]
      40: 528025f7     	mov	w23, #0x12f             ; =303
      44: 52800038     	mov	w24, #0x1               ; =1
      48: 52a00019     	movz	w25, #0x0, lsl #16
      4c: 528038ba     	mov	w26, #0x1c5             ; =453
      50: 910043e1     	add	x1, sp, #0x10
      54: f9000034     	str	x20, [x1]
      58: 52800022     	mov	w2, #0x1                ; =1
      5c: aa1303e0     	mov	x0, x19
      60: 94000000     	bl	0x60 <ltmp0+0x60>
      64: aa1303e0     	mov	x0, x19
      68: 2a1703e1     	mov	w1, w23
      6c: aa1503e2     	mov	x2, x21
      70: 2a1803e3     	mov	w3, w24
      74: 2a1903e4     	mov	w4, w25
      78: 2a1a03e5     	mov	w5, w26
      7c: 94000000     	bl	0x7c <ltmp0+0x7c>
      80: aa0003f5     	mov	x21, x0
      84: aa1303e0     	mov	x0, x19
      88: 94000000     	bl	0x88 <ltmp0+0x88>
      8c: aa1503e0     	mov	x0, x21
      90: 52a00015     	movz	w21, #0x0, lsl #16
      94: 9100c3f7     	add	x23, sp, #0x30
      98: 2a1503e0     	mov	w0, w21
      9c: f90002e0     	str	x0, [x23]
      a0: 528025f8     	mov	w24, #0x12f             ; =303
      a4: 52800039     	mov	w25, #0x1               ; =1
      a8: 5280003a     	mov	w26, #0x1               ; =1
      ac: 528038bb     	mov	w27, #0x1c5             ; =453
      b0: 910043e1     	add	x1, sp, #0x10
      b4: f9000034     	str	x20, [x1]
      b8: 52800022     	mov	w2, #0x1                ; =1
      bc: aa1303e0     	mov	x0, x19
      c0: 94000000     	bl	0xc0 <ltmp0+0xc0>
      c4: aa1303e0     	mov	x0, x19
      c8: 2a1803e1     	mov	w1, w24
      cc: aa1703e2     	mov	x2, x23
      d0: 2a1903e3     	mov	w3, w25
      d4: 2a1a03e4     	mov	w4, w26
      d8: 2a1b03e5     	mov	w5, w27
      dc: 94000000     	bl	0xdc <ltmp0+0xdc>
      e0: aa0003f7     	mov	x23, x0
      e4: aa1303e0     	mov	x0, x19
      e8: 94000000     	bl	0xe8 <ltmp0+0xe8>
      ec: aa1703e0     	mov	x0, x23
      f0: 52a00019     	movz	w25, #0x0, lsl #16
      f4: 910103f7     	add	x23, sp, #0x40
      f8: f90002f9     	str	x25, [x23]
      fc: 52805538     	mov	w24, #0x2a9             ; =681
     100: 5280003a     	mov	w26, #0x1               ; =1
     104: 5280005b     	mov	w27, #0x2               ; =2
     108: 528038bc     	mov	w28, #0x1c5             ; =453
     10c: 910043e1     	add	x1, sp, #0x10
     110: f9000034     	str	x20, [x1]
     114: 52800022     	mov	w2, #0x1                ; =1
     118: aa1303e0     	mov	x0, x19
     11c: 94000000     	bl	0x11c <ltmp0+0x11c>
     120: aa1303e0     	mov	x0, x19
     124: 2a1803e1     	mov	w1, w24
     128: aa1703e2     	mov	x2, x23
     12c: 2a1a03e3     	mov	w3, w26
     130: 2a1b03e4     	mov	w4, w27
     134: 2a1c03e5     	mov	w5, w28
     138: 94000000     	bl	0x138 <ltmp0+0x138>
     13c: aa0003f7     	mov	x23, x0
     140: aa1303e0     	mov	x0, x19
     144: 94000000     	bl	0x144 <ltmp0+0x144>
     148: aa1703e0     	mov	x0, x23
     14c: 52a00018     	movz	w24, #0x0, lsl #16
     150: 52a00017     	movz	w23, #0x0, lsl #16
     154: 52a00000     	movz	w0, #0x0, lsl #16
     158: 52a0001c     	movz	w28, #0x0, lsl #16
     15c: aa1703fb     	mov	x27, x23
     160: b94053e2     	ldr	w2, [sp, #0x50]
     164: 93407c41     	sxtw	x1, w2
     168: f9002fe1     	str	x1, [sp, #0x58]
     16c: 9ac12722     	lsr	x2, x25, x1
     170: b50004a2     	cbnz	x2, 0x204 <ltmp0+0x204>
     174: aa1903fa     	mov	x26, x25
     178: 350000e0     	cbnz	w0, 0x194 <ltmp0+0x194>
     17c: 52801e80     	mov	w0, #0xf4               ; =244
     180: 52800022     	mov	w2, #0x1                ; =1
     184: f9402260     	ldr	x0, [x19, #0x40]
     188: aa1403e1     	mov	x1, x20
     18c: 94000000     	bl	0x18c <ltmp0+0x18c>
     190: 2a0003fc     	mov	w28, w0
     194: 6b1c02df     	cmp	w22, w28
     198: 540002ea     	b.ge	0x1f4 <ltmp0+0x1f4>
     19c: 2a1603fa     	mov	w26, w22
     1a0: 350000f8     	cbnz	w24, 0x1bc <ltmp0+0x1bc>
     1a4: 52801e80     	mov	w0, #0xf4               ; =244
     1a8: 52a00002     	movz	w2, #0x0, lsl #16
     1ac: f9402260     	ldr	x0, [x19, #0x40]
     1b0: aa1403e1     	mov	x1, x20
     1b4: 94000000     	bl	0x1b4 <ltmp0+0x1b4>
     1b8: aa0003fb     	mov	x27, x0
     1bc: 52800040     	mov	w0, #0x2                ; =2
     1c0: f9402260     	ldr	x0, [x19, #0x40]
     1c4: aa1b03e1     	mov	x1, x27
     1c8: 2a1603e2     	mov	w2, w22
     1cc: 94000000     	bl	0x1cc <ltmp0+0x1cc>
     1d0: 52801fe1     	mov	w1, #0xff               ; =255
     1d4: 0a010000     	and	w0, w0, w1
     1d8: 93407c00     	sxtw	x0, w0
     1dc: 52800141     	mov	w1, #0xa                ; =10
     1e0: 9b010339     	madd	x25, x25, x1, x0
     1e4: 11000756     	add	w22, w26, #0x1
     1e8: 52800038     	mov	w24, #0x1               ; =1
     1ec: 52800020     	mov	w0, #0x1                ; =1
     1f0: 17ffffdc     	b	0x160 <ltmp0+0x160>
     1f4: f9402fe1     	ldr	x1, [sp, #0x58]
     1f8: 9ac12740     	lsr	x0, x26, x1
     1fc: b4001420     	cbz	x0, 0x480 <ltmp0+0x480>
     200: aa1a03f9     	mov	x25, x26
     204: 52801e80     	mov	w0, #0xf4               ; =244
     208: 52800042     	mov	w2, #0x2                ; =2
     20c: f9402260     	ldr	x0, [x19, #0x40]
     210: aa1403e1     	mov	x1, x20
     214: 94000000     	bl	0x214 <ltmp0+0x214>
     218: 510006c1     	sub	w1, w22, #0x1
     21c: 4b010000     	sub	w0, w0, w1
     220: 2a0003e3     	mov	w3, w0
     224: 52801e80     	mov	w0, #0xf4               ; =244
     228: 52800042     	mov	w2, #0x2                ; =2
     22c: f9402260     	ldr	x0, [x19, #0x40]
     230: aa1403e1     	mov	x1, x20
     234: 94000000     	bl	0x234 <ltmp0+0x234>
     238: 52800020     	mov	w0, #0x1                ; =1
     23c: f9402fe1     	ldr	x1, [sp, #0x58]
     240: 9ac12000     	lsl	x0, x0, x1
     244: d100041a     	sub	x26, x0, #0x1
     248: 52801e80     	mov	w0, #0xf4               ; =244
     24c: 52800022     	mov	w2, #0x1                ; =1
     250: f9402260     	ldr	x0, [x19, #0x40]
     254: aa1403e1     	mov	x1, x20
     258: 94000000     	bl	0x258 <ltmp0+0x258>
     25c: 2a0003fb     	mov	w27, w0
     260: b90063fb     	str	w27, [sp, #0x60]
     264: 52801e80     	mov	w0, #0xf4               ; =244
     268: 52a00002     	movz	w2, #0x0, lsl #16
     26c: f9402260     	ldr	x0, [x19, #0x40]
     270: aa1403e1     	mov	x1, x20
     274: 94000000     	bl	0x274 <ltmp0+0x274>
     278: aa0003e1     	mov	x1, x0
     27c: f90037e1     	str	x1, [sp, #0x68]
     280: f9402260     	ldr	x0, [x19, #0x40]
     284: 52800022     	mov	w2, #0x1                ; =1
     288: f94037e1     	ldr	x1, [sp, #0x68]
     28c: 94000000     	bl	0x28c <ltmp0+0x28c>
     290: aa0003fb     	mov	x27, x0
     294: f100037f     	cmp	x27, #0x0
     298: 9a9f07e0     	cset	x0, ne
     29c: 34000060     	cbz	w0, 0x2a8 <ltmp0+0x2a8>
     2a0: b940037c     	ldr	w28, [x27]
     2a4: 14000002     	b	0x2ac <ltmp0+0x2ac>
     2a8: 52a0001c     	movz	w28, #0x0, lsl #16
     2ac: 52a00000     	movz	w0, #0x0, lsl #16
     2b0: 350000e0     	cbnz	w0, 0x2cc <ltmp0+0x2cc>
     2b4: 52801e80     	mov	w0, #0xf4               ; =244
     2b8: 52a00002     	movz	w2, #0x0, lsl #16
     2bc: f9402260     	ldr	x0, [x19, #0x40]
     2c0: aa1403e1     	mov	x1, x20
     2c4: 94000000     	bl	0x2c4 <ltmp0+0x2c4>
     2c8: aa0003f7     	mov	x23, x0
     2cc: 52a00000     	movz	w0, #0x0, lsl #16
     2d0: 52a00018     	movz	w24, #0x0, lsl #16
     2d4: b94063e1     	ldr	w1, [sp, #0x60]
     2d8: 6b0102df     	cmp	w22, w1
     2dc: 540007eb     	b.lt	0x3d8 <ltmp0+0x3d8>
     2e0: b4000079     	cbz	x25, 0x2ec <ltmp0+0x2ec>
     2e4: aa1903f6     	mov	x22, x25
     2e8: 1400001c     	b	0x358 <ltmp0+0x358>
     2ec: 2a1503e3     	mov	w3, w21
     2f0: 52801e80     	mov	w0, #0xf4               ; =244
     2f4: 52800022     	mov	w2, #0x1                ; =1
     2f8: f9402260     	ldr	x0, [x19, #0x40]
     2fc: aa1403e1     	mov	x1, x20
     300: 94000000     	bl	0x300 <ltmp0+0x300>
     304: 910043e1     	add	x1, sp, #0x10
     308: f9000034     	str	x20, [x1]
     30c: 52800022     	mov	w2, #0x1                ; =1
     310: aa1303e0     	mov	x0, x19
     314: 94000000     	bl	0x314 <ltmp0+0x314>
     318: aa1303e0     	mov	x0, x19
     31c: aa1403e1     	mov	x1, x20
     320: 94000000     	bl	0x320 <ltmp0+0x320>
     324: 2a0003f5     	mov	w21, w0
     328: aa1303e0     	mov	x0, x19
     32c: 94000000     	bl	0x32c <ltmp0+0x32c>
     330: 2a1503e0     	mov	w0, w21
     334: a94b73fb     	ldp	x27, x28, [sp, #0xb0]
     338: a94a6bf9     	ldp	x25, x26, [sp, #0xa0]
     33c: a94963f7     	ldp	x23, x24, [sp, #0x90]
     340: a9485bf5     	ldp	x21, x22, [sp, #0x80]
     344: a94753f3     	ldp	x19, x20, [sp, #0x70]
     348: 910303ff     	add	sp, sp, #0xc0
     34c: a9407bfd     	ldp	x29, x30, [sp]
     350: 910043ff     	add	sp, sp, #0x10
     354: d65f03c0     	ret
     358: f9402fe1     	ldr	x1, [sp, #0x58]
     35c: 9ac12739     	lsr	x25, x25, x1
     360: 350000a0     	cbnz	w0, 0x374 <ltmp0+0x374>
     364: f9402260     	ldr	x0, [x19, #0x40]
     368: aa1703e1     	mov	x1, x23
     36c: 94000000     	bl	0x36c <ltmp0+0x36c>
     370: 2a0003f8     	mov	w24, w0
     374: 6b1802bf     	cmp	w21, w24
     378: 5400014b     	b.lt	0x3a0 <ltmp0+0x3a0>
     37c: b4000259     	cbz	x25, 0x3c4 <ltmp0+0x3c4>
     380: 52800020     	mov	w0, #0x1                ; =1
     384: 2a0003e3     	mov	w3, w0
     388: 52801e80     	mov	w0, #0xf4               ; =244
     38c: 52800082     	mov	w2, #0x4                ; =4
     390: f9402260     	ldr	x0, [x19, #0x40]
     394: aa1403e1     	mov	x1, x20
     398: 94000000     	bl	0x398 <ltmp0+0x398>
     39c: 1400000a     	b	0x3c4 <ltmp0+0x3c4>
     3a0: 2a1903e0     	mov	w0, w25
     3a4: 12001c00     	and	w0, w0, #0xff
     3a8: 2a0003e3     	mov	w3, w0
     3ac: 52800040     	mov	w0, #0x2                ; =2
     3b0: f9402260     	ldr	x0, [x19, #0x40]
     3b4: aa1703e1     	mov	x1, x23
     3b8: 2a1503e2     	mov	w2, w21
     3bc: 94000000     	bl	0x3bc <ltmp0+0x3bc>
     3c0: 110006b5     	add	w21, w21, #0x1
     3c4: 8a1a02c0     	and	x0, x22, x26
     3c8: 52800141     	mov	w1, #0xa                ; =10
     3cc: 9b017c19     	mul	x25, x0, x1
     3d0: 52800020     	mov	w0, #0x1                ; =1
     3d4: 17ffffc3     	b	0x2e0 <ltmp0+0x2e0>
     3d8: f9402fe1     	ldr	x1, [sp, #0x58]
     3dc: 9ac12720     	lsr	x0, x25, x1
     3e0: 12001c00     	and	w0, w0, #0xff
     3e4: 6b1c02bf     	cmp	w21, w28
     3e8: 9a9f27e1     	cset	x1, lo
     3ec: 35000101     	cbnz	w1, 0x40c <ltmp0+0x40c>
     3f0: 52800041     	mov	w1, #0x2                ; =2
     3f4: 2a0003e3     	mov	w3, w0
     3f8: f9402260     	ldr	x0, [x19, #0x40]
     3fc: f94037e1     	ldr	x1, [sp, #0x68]
     400: 2a1503e2     	mov	w2, w21
     404: 94000000     	bl	0x404 <ltmp0+0x404>
     408: 14000006     	b	0x420 <ltmp0+0x420>
     40c: 2a1503e1     	mov	w1, w21
     410: 52800022     	mov	w2, #0x1                ; =1
     414: 9b027c21     	mul	x1, x1, x2
     418: 8b010361     	add	x1, x27, x1
     41c: 39004020     	strb	w0, [x1, #0x10]
     420: 110006b5     	add	w21, w21, #0x1
     424: 8a1a0338     	and	x24, x25, x26
     428: 6b1c02df     	cmp	w22, w28
     42c: 9a9f27e0     	cset	x0, lo
     430: 35000120     	cbnz	w0, 0x454 <ltmp0+0x454>
     434: 52800040     	mov	w0, #0x2                ; =2
     438: f9402260     	ldr	x0, [x19, #0x40]
     43c: f94037e1     	ldr	x1, [sp, #0x68]
     440: 2a1603e2     	mov	w2, w22
     444: 94000000     	bl	0x444 <ltmp0+0x444>
     448: 52801fe1     	mov	w1, #0xff               ; =255
     44c: 0a010000     	and	w0, w0, w1
     450: 14000006     	b	0x468 <ltmp0+0x468>
     454: 2a1603e0     	mov	w0, w22
     458: 52800021     	mov	w1, #0x1                ; =1
     45c: 9b017c00     	mul	x0, x0, x1
     460: 8b000360     	add	x0, x27, x0
     464: 39404000     	ldrb	w0, [x0, #0x10]
     468: 93407c00     	sxtw	x0, w0
     46c: 52800141     	mov	w1, #0xa                ; =10
     470: 9b010319     	madd	x25, x24, x1, x0
     474: 110006d6     	add	w22, w22, #0x1
     478: 52800020     	mov	w0, #0x1                ; =1
     47c: 17ffff8d     	b	0x2b0 <ltmp0+0x2b0>
     480: 52800140     	mov	w0, #0xa                ; =10
     484: 9b007f5a     	mul	x26, x26, x0
     488: 110006d6     	add	w22, w22, #0x1
     48c: 17ffff5a     	b	0x1f4 <ltmp0+0x1f4>
```

### Wasmtime optimized CLIF

Dumped after compile_maybe_cached, not before optimization.

```text
;; Intermediate Representation of function <wasm[0]::function[453]::_M0MPC28internal7strconv7Decimal12right__shift>:
function u0:453(i64 vmctx, i64, i32, i32) -> i32 tail {
    ss0 = explicit_slot 4, align = 4
    ss1 = explicit_slot 4, align = 4
    ss2 = explicit_slot 4, align = 4
    ss3 = explicit_slot 4, align = 4
    ss4 = explicit_slot 4, align = 4
    region0 = 123 ""
    region1 = 160 ""
    region2 = 65 ""
    region3 = 177 ""
    region4 = 98 ""
    region5 = 130 ""
    region6 = 178 ""
    region7 = 196 ""
    region8 = 108 ""
    region9 = 200 ""
    region10 = 206 ""
    region11 = 240 ""
    region12 = 0 ""
    region13 = 232 ""
    region14 = 208 ""
    region15 = 80 ""
    gv0 = vmctx
    gv1 = load.i64 notrap aligned readonly can_move region0 gv0+8
    gv2 = load.i64 notrap aligned region1 gv1+24
    sig0 = (i64 vmctx, i32, i32, i32, i32) -> i32 tail
    sig1 = (i64 vmctx, i64, i32) -> i64 tail
    sig2 = (i64 vmctx, i64, i64) -> i32 tail
    sig3 = (i64 vmctx, i64, i32) -> i32 tail
    fn0 = colocated u805306368:24 sig0
    fn1 = colocated u0:688 sig1
    fn2 = colocated u0:1255 sig2
    fn3 = colocated u0:461 sig3
    stack_limit = gv2

                                block0(v0: i64, v1: i64, v2: i32, v3: i32):
                                    v884 = stack_addr.i64 ss0
                                    store notrap aligned region13 v2, v884
@158a8                              v10 = load.i64 notrap aligned readonly can_move region2 v0+32
@158a8                              v11 = load.i32 notrap aligned region3 v10
@158a8                              v12 = load.i32 notrap aligned region4 v10+4
@158a8                              v18 = uextend.i64 v11
                                    v885 = iconst.i64 32
@158a8                              v19 = iadd v18, v885  ; v885 = 32
@158a8                              v20 = uextend.i64 v12
@158a8                              v21 = icmp ule v19, v20
@158a8                              brif v21, block2, block3

                                block2:
                                    v934 = iconst.i32 32
                                    v899 = iadd.i32 v11, v934  ; v934 = 32
@158a8                              store notrap aligned region3 v899, v10
                                    v935 = iconst.i32 -1342177278
                                    v936 = load.i64 notrap aligned readonly can_move region0 v0+8
                                    v937 = load.i64 notrap aligned readonly can_move region7 v936+32
@158a8                              v35 = iadd v937, v18
@158a8                              store user2 region8 v935, v35  ; v935 = -1342177278
                                    v938 = load.i64 notrap aligned readonly can_move region5 v0+40
                                    v939 = load.i32 notrap aligned readonly can_move region6 v938+160
@158a8                              store user2 region8 v939, v35+4
                                    v940 = iconst.i64 32
@158a8                              istore32 user2 region8 v940, v35+8  ; v940 = 32
@158a8                              jump block4(v11, v35)

                                block3 cold:
@158a8                              v22 = iconst.i32 -1342177278
@158a8                              v23 = load.i64 notrap aligned readonly can_move region5 v0+40
@158a8                              v24 = load.i32 notrap aligned readonly can_move region6 v23+160
@158a8                              v9 = iconst.i32 32
@158a8                              v25 = iconst.i32 16
@158a8                              v26 = call fn0(v0, v22, v24, v9, v25), stack_map=[i32 @ ss0+0]  ; v22 = -1342177278, v9 = 32, v25 = 16
@158a8                              v27 = load.i64 notrap aligned readonly can_move region0 v0+8
@158a8                              v28 = load.i64 notrap aligned readonly can_move region7 v27+32
@158a8                              v29 = uextend.i64 v26
@158a8                              v30 = iadd v28, v29
@158a8                              jump block4(v26, v30)

                                block4(v39: i32, v40: i64):
                                    v883 = stack_addr.i64 ss1
                                    store notrap aligned region11 v39, v883
@1589e                              v4 = iconst.i32 0
@158a8                              v41 = iconst.i64 16
@158a8                              v42 = iadd v40, v41  ; v41 = 16
@158a8                              store user2 little region8 v4, v42  ; v4 = 0
@158b0                              v46 = load.i32 notrap aligned region3 v10
@158b0                              v47 = load.i32 notrap aligned region4 v10+4
@158b0                              v53 = uextend.i64 v46
                                    v941 = iconst.i64 32
                                    v942 = iadd v53, v941  ; v941 = 32
@158b0                              v55 = uextend.i64 v47
@158b0                              v56 = icmp ule v942, v55
@158b0                              brif v56, block5, block6

                                block5:
                                    v950 = iconst.i32 32
                                    v902 = iadd.i32 v46, v950  ; v950 = 32
@158b0                              store notrap aligned region3 v902, v10
                                    v951 = iconst.i32 -1342177278
                                    v952 = load.i64 notrap aligned readonly can_move region0 v0+8
                                    v953 = load.i64 notrap aligned readonly can_move region7 v952+32
@158b0                              v70 = iadd v953, v53
@158b0                              store user2 region8 v951, v70  ; v951 = -1342177278
                                    v954 = load.i64 notrap aligned readonly can_move region5 v0+40
                                    v955 = load.i32 notrap aligned readonly can_move region6 v954+160
@158b0                              store user2 region8 v955, v70+4
                                    v956 = iconst.i64 32
@158b0                              istore32 user2 region8 v956, v70+8  ; v956 = 32
@158b0                              jump block7(v46, v70)

                                block6 cold:
                                    v943 = iconst.i32 -1342177278
                                    v944 = load.i64 notrap aligned readonly can_move region5 v0+40
                                    v945 = load.i32 notrap aligned readonly can_move region6 v944+160
                                    v946 = iconst.i32 32
                                    v947 = iconst.i32 16
@158b0                              v61 = call fn0(v0, v943, v945, v946, v947), stack_map=[i32 @ ss0+0, i32 @ ss1+0]  ; v943 = -1342177278, v946 = 32, v947 = 16
                                    v948 = load.i64 notrap aligned readonly can_move region0 v0+8
                                    v949 = load.i64 notrap aligned readonly can_move region7 v948+32
@158b0                              v64 = uextend.i64 v61
@158b0                              v65 = iadd v949, v64
@158b0                              jump block7(v61, v65)

                                block7(v74: i32, v75: i64):
                                    v882 = stack_addr.i64 ss2
                                    store notrap aligned region14 v74, v882
                                    v957 = iconst.i32 0
                                    v958 = iconst.i64 16
                                    v959 = iadd v75, v958  ; v958 = 16
@158b0                              store user2 little region8 v957, v959  ; v957 = 0
@158b8                              v81 = load.i32 notrap aligned region3 v10
@158b8                              v82 = load.i32 notrap aligned region4 v10+4
@158b8                              v88 = uextend.i64 v81
                                    v960 = iconst.i64 32
                                    v961 = iadd v88, v960  ; v960 = 32
@158b8                              v90 = uextend.i64 v82
@158b8                              v91 = icmp ule v961, v90
@158b8                              brif v91, block8, block9

                                block8:
                                    v968 = iconst.i32 32
                                    v905 = iadd.i32 v81, v968  ; v968 = 32
@158b8                              store notrap aligned region3 v905, v10
                                    v969 = iconst.i32 -1342177278
                                    v970 = load.i64 notrap aligned readonly can_move region0 v0+8
                                    v971 = load.i64 notrap aligned readonly can_move region7 v970+32
@158b8                              v105 = iadd v971, v88
@158b8                              store user2 region8 v969, v105  ; v969 = -1342177278
                                    v972 = load.i64 notrap aligned readonly can_move region5 v0+40
                                    v973 = load.i32 notrap aligned readonly can_move region9 v972+1604
@158b8                              store user2 region8 v973, v105+4
                                    v974 = iconst.i64 32
@158b8                              istore32 user2 region8 v974, v105+8  ; v974 = 32
@158b8                              jump block10(v81, v105)

                                block9 cold:
                                    v962 = iconst.i32 -1342177278
                                    v963 = load.i64 notrap aligned readonly can_move region5 v0+40
@158b8                              v94 = load.i32 notrap aligned readonly can_move region9 v963+1604
                                    v964 = iconst.i32 32
                                    v965 = iconst.i32 16
@158b8                              v96 = call fn0(v0, v962, v94, v964, v965), stack_map=[i32 @ ss0+0, i32 @ ss1+0, i32 @ ss2+0]  ; v962 = -1342177278, v964 = 32, v965 = 16
                                    v966 = load.i64 notrap aligned readonly can_move region0 v0+8
                                    v967 = load.i64 notrap aligned readonly can_move region7 v966+32
@158b8                              v99 = uextend.i64 v96
@158b8                              v100 = iadd v967, v99
@158b8                              jump block10(v96, v100)

                                block10(v109: i32, v110: i64):
                                    v881 = stack_addr.i64 ss3
                                    store notrap aligned region12 v109, v881
@158a0                              v5 = iconst.i64 0
                                    v975 = iconst.i64 16
                                    v976 = iadd v110, v975  ; v975 = 16
@158b8                              store user2 little region8 v5, v976  ; v5 = 0
                                    v977 = load.i64 notrap aligned readonly can_move region0 v0+8
                                    v978 = load.i64 notrap aligned readonly can_move region7 v977+32
@158c0                              jump block12

                                block12:
                                    v880 = load.i32 notrap aligned region12 v881
@158c4                              trapz v880, user16
@158c4                              v114 = uextend.i64 v880
@158c4                              v117 = iadd.i64 v978, v114
                                    v979 = iconst.i64 16
                                    v980 = iadd v117, v979  ; v979 = 16
@158c4                              v120 = load.i64 user2 little region8 v980
                                    v907 = ushr v120, v3
                                    v981 = iconst.i64 0
                                    v982 = icmp eq v907, v981  ; v981 = 0
@158d0                              brif v982, block14, block15

                                block14:
                                    v876 = load.i32 notrap aligned region11 v883
@158d4                              trapz v876, user16
@158d4                              v128 = uextend.i64 v876
@158d4                              v131 = iadd.i64 v978, v128
                                    v983 = iconst.i64 16
                                    v984 = iadd v131, v983  ; v983 = 16
@158d4                              v134 = load.i32 user2 little region8 v984
                                    v872 = load.i32 notrap aligned region13 v884
@158db                              trapz v872, user16
@158db                              v136 = uextend.i64 v872
@158db                              v139 = iadd.i64 v978, v136
@158db                              v140 = iconst.i64 20
@158db                              v141 = iadd v139, v140  ; v140 = 20
@158db                              v142 = load.i32 user2 little region8 v141
@158e0                              v143 = icmp sge v134, v142
@158e1                              brif v143, block16, block17

                                block16:
@158e3                              jump block18

                                block18:
                                    v844 = load.i32 notrap aligned region12 v881
@158e7                              trapz v844, user16
@158e7                              v146 = uextend.i64 v844
@158e7                              v149 = iadd.i64 v978, v146
                                    v992 = iconst.i64 16
                                    v993 = iadd v149, v992  ; v992 = 16
@158e7                              v152 = load.i64 user2 little region8 v993
                                    v913 = ushr v152, v3
                                    v994 = iconst.i64 0
                                    v995 = icmp eq v913, v994  ; v994 = 0
@158f3                              brif v995, block20, block21

                                block20:
                                    v996 = iconst.i64 10
@15900                              v167 = imul.i64 v152, v996  ; v996 = 10
@15901                              store user2 little region8 v167, v993
                                    v684 = load.i32 notrap aligned region11 v883
@1590d                              trapz v684, user16
@1590d                              v176 = uextend.i64 v684
@1590d                              v179 = iadd.i64 v978, v176
                                    v997 = iconst.i64 16
                                    v998 = iadd v179, v997  ; v997 = 16
@1590d                              v182 = load.i32 user2 little region8 v998
                                    v999 = iconst.i32 1
@15914                              v184 = iadd v182, v999  ; v999 = 1
@15915                              store user2 little region8 v184, v998
@1591d                              jump block18

                                block21:
@15920                              jump block19

                                block19:
@15924                              jump block11

                                block17:
                                    v985 = iconst.i64 16
                                    v986 = iadd.i64 v139, v985  ; v985 = 16
@1592c                              v200 = load.i32 user2 little region8 v986
@15938                              trapz v200, user16
@15938                              v208 = uextend.i64 v200
@15938                              v211 = iadd.i64 v978, v208
                                    v987 = iadd v211, v985  ; v985 = 16
@15938                              v214 = load.i32 user2 readonly region8 v987
@15938                              v215 = icmp.i32 ult v134, v214
@15938                              trapz v215, user17
@15938                              v217 = uextend.i64 v214
                                    v988 = iconst.i64 32
                                    v989 = ushr v217, v988  ; v988 = 32
@15938                              trapnz v989, user2
@15938                              v222 = iconst.i32 20
@15938                              v223 = uadd_overflow_trap v214, v222, user2  ; v222 = 20
@15938                              v227 = uadd_overflow_trap v200, v223, user2
@15938                              v228 = uextend.i64 v227
@15938                              v231 = iadd.i64 v978, v228
@15938                              v226 = iadd.i32 v134, v222  ; v222 = 20
@15938                              v232 = isub v223, v226
@15938                              v233 = uextend.i64 v232
@15938                              v234 = isub v231, v233
@15938                              v235 = load.i8 user2 little region8 v234
@15938                              v236 = uextend.i32 v235
@1594b                              v246 = call fn1(v0, v0, v236), stack_map=[i32 @ ss0+0, i32 @ ss1+0, i32 @ ss2+0, i32 @ ss3+0]
                                    v856 = load.i32 notrap aligned region12 v881
@1594f                              trapz v856, user16
@15946                              v244 = iconst.i64 10
@15948                              v245 = imul.i64 v120, v244  ; v244 = 10
@1594e                              v247 = iadd v245, v246
@1594f                              v248 = uextend.i64 v856
@1594f                              v251 = iadd.i64 v978, v248
                                    v990 = iadd v251, v985  ; v985 = 16
@1594f                              store user2 little region8 v247, v990
                                    v852 = load.i32 notrap aligned region11 v883
@1595b                              trapz v852, user16
@1595b                              v255 = uextend.i64 v852
@1595b                              v258 = iadd.i64 v978, v255
                                    v991 = iadd v258, v985  ; v985 = 16
@1595b                              v261 = load.i32 user2 little region8 v991
                                    v911 = iconst.i32 1
@15962                              v263 = iadd v261, v911  ; v911 = 1
@15963                              store user2 little region8 v263, v991
@1596b                              jump block12

                                block15:
@1596e                              jump block13

                                block13:
@1596f                              jump block11

                                block11:
                                    v840 = load.i32 notrap aligned region13 v884
@15977                              trapz v840, user16
@15977                              v282 = uextend.i64 v840
@15977                              v285 = iadd.i64 v978, v282
@15977                              v286 = iconst.i64 24
@15977                              v287 = iadd v285, v286  ; v286 = 24
@15977                              v288 = load.i32 user2 little region8 v287
                                    v836 = load.i32 notrap aligned region11 v883
@1597e                              trapz v836, user16
@1597e                              v290 = uextend.i64 v836
@1597e                              v293 = iadd.i64 v978, v290
                                    v1000 = iconst.i64 16
                                    v1001 = iadd v293, v1000  ; v1000 = 16
@1597e                              v296 = load.i32 user2 little region8 v1001
                                    v1002 = iconst.i32 1
@15985                              v298 = isub v296, v1002  ; v1002 = 1
@15986                              v299 = isub v288, v298
@15987                              store user2 little region8 v299, v287
                                    v1005 = iconst.i64 20
@1599a                              jump block22

                                block22:
                                    v828 = load.i32 notrap aligned region11 v883
@1599e                              trapz v828, user16
@1599e                              v314 = uextend.i64 v828
@1599e                              v317 = iadd.i64 v978, v314
                                    v1003 = iconst.i64 16
                                    v1004 = iadd v317, v1003  ; v1003 = 16
@1599e                              v320 = load.i32 user2 little region8 v1004
                                    v824 = load.i32 notrap aligned region13 v884
@159a5                              trapz v824, user16
@159a5                              v322 = uextend.i64 v824
@159a5                              v325 = iadd.i64 v978, v322
@159a5                              v327 = iadd v325, v1005  ; v1005 = 20
@159a5                              v328 = load.i32 user2 little region8 v327
@159aa                              v329 = icmp slt v320, v328
@159ab                              brif v329, block24, block25

                                block24:
                                    v751 = load.i32 notrap aligned region12 v881
@159af                              trapz v751, user16
@159af                              v332 = uextend.i64 v751
@159af                              v335 = iadd.i64 v978, v332
                                    v1026 = iconst.i64 16
                                    v1027 = iadd v335, v1026  ; v1026 = 16
@159af                              v338 = load.i64 user2 little region8 v1027
                                    v1028 = iadd.i64 v325, v1026  ; v1026 = 16
@159bc                              v348 = load.i32 user2 little region8 v1028
                                    v1029 = stack_addr.i64 ss4
                                    store notrap aligned region15 v348, v1029
                                    v742 = load.i32 notrap aligned region14 v882
@159c3                              trapz v742, user16
@159c3                              v350 = uextend.i64 v742
@159c3                              v353 = iadd.i64 v978, v350
                                    v1030 = iadd v353, v1026  ; v1026 = 16
@159c3                              v356 = load.i32 user2 little region8 v1030
                                    v926 = ushr v338, v3
@159ca                              v357 = call fn2(v0, v0, v926), stack_map=[i32 @ ss0+0, i32 @ ss1+0, i32 @ ss2+0, i32 @ ss3+0, i32 @ ss4+0]
                                    v738 = load.i32 notrap aligned region15 v1029
@159cd                              trapz v738, user16
@159cd                              v358 = uextend.i64 v738
@159cd                              v361 = iadd.i64 v978, v358
                                    v1031 = iadd v361, v1026  ; v1026 = 16
@159cd                              v364 = load.i32 user2 readonly region8 v1031
@159cd                              v365 = icmp ult v356, v364
@159cd                              trapz v365, user17
@159cd                              v367 = uextend.i64 v364
                                    v1032 = iconst.i64 32
                                    v1033 = ushr v367, v1032  ; v1032 = 32
@159cd                              trapnz v1033, user2
                                    v1034 = iconst.i32 20
@159cd                              v373 = uadd_overflow_trap v364, v1034, user2  ; v1034 = 20
@159cd                              v377 = uadd_overflow_trap v738, v373, user2
@159cd                              v378 = uextend.i64 v377
@159cd                              v381 = iadd.i64 v978, v378
@159cd                              v376 = iadd v356, v1034  ; v1034 = 20
@159cd                              v382 = isub v373, v376
@159cd                              v383 = uextend.i64 v382
@159cd                              v384 = isub v381, v383
@159cd                              istore8 user2 little region8 v357, v384
                                    v732 = load.i32 notrap aligned region14 v882
@159d7                              trapz v732, user16
@159d7                              v386 = uextend.i64 v732
@159d7                              v389 = iadd.i64 v978, v386
                                    v1035 = iadd v389, v1026  ; v1026 = 16
@159d7                              v392 = load.i32 user2 little region8 v1035
@159de                              v394 = iadd v392, v1002  ; v1002 = 1
@159df                              store user2 little region8 v394, v1035
                                    v724 = load.i32 notrap aligned region12 v881
@159eb                              trapz v724, user16
@159eb                              v402 = uextend.i64 v724
@159eb                              v405 = iadd.i64 v978, v402
                                    v1036 = iadd v405, v1026  ; v1026 = 16
@159eb                              v408 = load.i64 user2 little region8 v1036
                                    v1037 = iconst.i64 1
                                    v1038 = ishl v1037, v3  ; v1037 = 1
                                    v1039 = isub v1038, v1037  ; v1037 = 1
@159f2                              v410 = band v408, v1039
@159f3                              store user2 little region8 v410, v1036
                                    v716 = load.i32 notrap aligned region13 v884
@159fd                              trapz v716, user16
@159fd                              v418 = uextend.i64 v716
@159fd                              v421 = iadd.i64 v978, v418
                                    v1040 = iadd v421, v1026  ; v1026 = 16
@159fd                              v424 = load.i32 user2 little region8 v1040
                                    v712 = load.i32 notrap aligned region11 v883
@15a04                              trapz v712, user16
@15a04                              v425 = uextend.i64 v712
@15a04                              v428 = iadd.i64 v978, v425
                                    v1041 = iadd v428, v1026  ; v1026 = 16
@15a04                              v431 = load.i32 user2 little region8 v1041
@15a09                              trapz v424, user16
@15a09                              v432 = uextend.i64 v424
@15a09                              v435 = iadd.i64 v978, v432
                                    v1042 = iadd v435, v1026  ; v1026 = 16
@15a09                              v438 = load.i32 user2 readonly region8 v1042
@15a09                              v439 = icmp ult v431, v438
@15a09                              trapz v439, user17
@15a09                              v441 = uextend.i64 v438
                                    v1043 = ushr v441, v1032  ; v1032 = 32
@15a09                              trapnz v1043, user2
@15a09                              v447 = uadd_overflow_trap v438, v1034, user2  ; v1034 = 20
@15a09                              v451 = uadd_overflow_trap v424, v447, user2
@15a09                              v452 = uextend.i64 v451
@15a09                              v455 = iadd.i64 v978, v452
@15a09                              v450 = iadd v431, v1034  ; v1034 = 20
@15a09                              v456 = isub v447, v450
@15a09                              v457 = uextend.i64 v456
@15a09                              v458 = isub v455, v457
@15a09                              v459 = load.i8 user2 little region8 v458
@15a09                              v460 = uextend.i32 v459
@15a1c                              v470 = call fn1(v0, v0, v460), stack_map=[i32 @ ss0+0, i32 @ ss1+0, i32 @ ss2+0, i32 @ ss3+0]
                                    v704 = load.i32 notrap aligned region12 v881
@15a20                              trapz v704, user16
                                    v1044 = iconst.i64 10
@15a19                              v469 = imul v410, v1044  ; v1044 = 10
@15a1f                              v471 = iadd v469, v470
@15a20                              v472 = uextend.i64 v704
@15a20                              v475 = iadd.i64 v978, v472
                                    v1045 = iadd v475, v1026  ; v1026 = 16
@15a20                              store user2 little region8 v471, v1045
                                    v700 = load.i32 notrap aligned region11 v883
@15a2c                              trapz v700, user16
@15a2c                              v479 = uextend.i64 v700
@15a2c                              v482 = iadd.i64 v978, v479
                                    v1046 = iadd v482, v1026  ; v1026 = 16
@15a2c                              v485 = load.i32 user2 little region8 v1046
@15a33                              v487 = iadd v485, v1002  ; v1002 = 1
@15a34                              store user2 little region8 v487, v1046
@15a3c                              jump block22

                                block25:
@15a3f                              jump block23

                                block23:
@15a43                              jump block26

                                block26:
                                    v820 = load.i32 notrap aligned region12 v881
@15a47                              trapz v820, user16
@15a47                              v502 = uextend.i64 v820
@15a47                              v505 = iadd.i64 v978, v502
                                    v1006 = iconst.i64 16
                                    v1007 = iadd v505, v1006  ; v1006 = 16
@15a47                              v508 = load.i64 user2 little region8 v1007
@15a4f                              brif v508, block28, block29

                                block28:
                                    v802 = load.i32 notrap aligned region14 v882
@15a60                              trapz v802, user16
@15a60                              v523 = uextend.i64 v802
@15a60                              v526 = iadd.i64 v978, v523
                                    v1010 = iconst.i64 16
                                    v1011 = iadd v526, v1010  ; v1010 = 16
@15a60                              v529 = load.i32 user2 little region8 v1011
                                    v798 = load.i32 notrap aligned region13 v884
@15a67                              trapz v798, user16
@15a67                              v531 = uextend.i64 v798
@15a67                              v534 = iadd.i64 v978, v531
                                    v1012 = iadd v534, v1010  ; v1010 = 16
@15a67                              v537 = load.i32 user2 little region8 v1012
@15a6c                              trapz v537, user16
@15a6c                              v538 = uextend.i64 v537
@15a6c                              v541 = iadd.i64 v978, v538
                                    v1013 = iadd v541, v1010  ; v1010 = 16
@15a6c                              v544 = load.i32 user2 readonly region8 v1013
@15a6e                              v545 = icmp slt v529, v544
@15a6f                              brif v545, block30, block32

                                block30:
                                    v786 = stack_addr.i64 ss4
                                    store.i32 notrap aligned region15 v537, v786
                                    v1016 = ushr.i64 v508, v3
@15a81                              v561 = call fn2(v0, v0, v1016), stack_map=[i32 @ ss0+0, i32 @ ss2+0, i32 @ ss3+0, i32 @ ss4+0]
                                    v781 = load.i32 notrap aligned region15 v786
@15a84                              trapz v781, user16
@15a84                              v562 = uextend.i64 v781
@15a84                              v565 = iadd.i64 v978, v562
                                    v1017 = iconst.i64 16
                                    v1018 = iadd v565, v1017  ; v1017 = 16
@15a84                              v568 = load.i32 user2 readonly region8 v1018
@15a84                              v569 = icmp.i32 ult v529, v568
@15a84                              trapz v569, user17
@15a84                              v571 = uextend.i64 v568
                                    v1019 = iconst.i64 32
                                    v1020 = ushr v571, v1019  ; v1019 = 32
@15a84                              trapnz v1020, user2
                                    v1021 = iconst.i32 20
@15a84                              v577 = uadd_overflow_trap v568, v1021, user2  ; v1021 = 20
@15a84                              v581 = uadd_overflow_trap v781, v577, user2
@15a84                              v582 = uextend.i64 v581
@15a84                              v585 = iadd.i64 v978, v582
@15a84                              v580 = iadd.i32 v529, v1021  ; v1021 = 20
@15a84                              v586 = isub v577, v580
@15a84                              v587 = uextend.i64 v586
@15a84                              v588 = isub v585, v587
@15a84                              istore8 user2 little region8 v561, v588
                                    v775 = load.i32 notrap aligned region14 v882
@15a8e                              trapz v775, user16
@15a8e                              v590 = uextend.i64 v775
@15a8e                              v593 = iadd.i64 v978, v590
                                    v1022 = iadd v593, v1017  ; v1017 = 16
@15a8e                              v596 = load.i32 user2 little region8 v1022
@15a95                              v598 = iadd v596, v1002  ; v1002 = 1
@15a96                              store user2 little region8 v598, v1022
@15a9e                              jump block31

                                block32:
                                    v919 = ushr.i64 v508, v3
@15aa4                              brif v919, block33, block34

                                block33:
                                    v1014 = iconst.i64 32
                                    v1015 = iadd.i64 v534, v1014  ; v1014 = 32
@15aaa                              store.i32 user2 little region8 v1002, v1015  ; v1002 = 1
@15ab2                              jump block34

                                block34:
@15ab6                              jump block31

                                block31:
                                    v767 = load.i32 notrap aligned region12 v881
@15abe                              trapz v767, user16
@15abe                              v621 = uextend.i64 v767
@15abe                              v624 = iadd.i64 v978, v621
                                    v1023 = iconst.i64 16
                                    v1024 = iadd v624, v1023  ; v1023 = 16
@15abe                              v627 = load.i64 user2 little region8 v1024
@15938                              v216 = iconst.i64 1
                                    v915 = ishl v216, v3  ; v216 = 1
@15997                              v312 = isub v915, v216  ; v216 = 1
@15ac5                              v631 = band v627, v312
@15ac6                              store user2 little region8 v631, v1024
                                    v1025 = iconst.i64 10
@15ad9                              v647 = imul v631, v1025  ; v1025 = 10
@15ada                              store user2 little region8 v647, v1024
@15ae2                              jump block26

                                block29:
@15ae5                              jump block27

                                block27:
                                    v816 = load.i32 notrap aligned region14 v882
@15aed                              trapz v816, user16
@15aed                              v662 = uextend.i64 v816
@15aed                              v665 = iadd.i64 v978, v662
                                    v1008 = iconst.i64 16
                                    v1009 = iadd v665, v1008  ; v1008 = 16
@15aed                              v668 = load.i32 user2 little region8 v1009
                                    v812 = load.i32 notrap aligned region13 v884
@15af2                              trapz v812, user16
@15af2                              v669 = uextend.i64 v812
@15af2                              v672 = iadd.i64 v978, v669
@15af2                              v674 = iadd v672, v1005  ; v1005 = 20
@15af2                              store user2 little region8 v668, v674
@15afc                              v676 = call fn3(v0, v0, v812)
@15aff                              jump block1

                                block1:
@15aff                              return v676
}
```

### Wasmtime ARM64 machine code and stack maps

```asm
wasm[0]::function[453]::_M0MPC28internal7strconv7Decimal12right__shift:
            5f 23 03 d5                  pacibz
            fd 7b bf a9                  stp     x29, x30, [sp, #-0x10]!
            fd 03 00 91                  mov     x29, sp
            50 80 40 f8                  ldur    x16, [x2, #8]
            10 82 41 f8                  ldur    x16, [x16, #0x18]
            10 c2 01 91                  add     x16, x16, #0x70
            ff 63 30 eb                  cmp     sp, x16
            43 30 00 54                  b.lo    #0x4de44
            f7 67 bf a9                  stp     x23, x25, [sp, #-0x10]!
            f5 5b bf a9                  stp     x21, x22, [sp, #-0x10]!
            f3 53 bf a9                  stp     x19, x20, [sp, #-0x10]!
            ff c3 00 d1                  sub     sp, sp, #0x30
            f4 03 05 aa                  mov     x20, x5
            f6 03 02 aa                  mov     x22, x2
            e4 03 00 b8                  stur    w4, [sp]
            53 10 40 f9                  ldr     x19, [x2, #0x20]
            62 02 40 b9                  ldr     w2, [x19]
            e0 03 02 2a                  mov     w0, w2
            00 80 00 91                  add     x0, x0, #0x20
            61 06 40 b9                  ldr     w1, [x19, #4]
            1f 00 01 eb                  cmp     x0, x1
            a8 29 00 54                  b.hi    #0x4dda8
            40 80 00 11                  add     w0, w2, #0x20
            60 02 00 b9                  str     w0, [x19]
            41 00 80 52                  mov     w1, #2
            01 00 b6 72                  movk    w1, #0xb000, lsl #16
            e0 03 16 aa                  mov     x0, x22
            00 04 40 f9                  ldr     x0, [x0, #8]
            03 10 40 f9                  ldr     x3, [x0, #0x20]
            60 40 22 8b                  add     x0, x3, w2, uxtw
            61 48 22 b8                  str     w1, [x3, w2, uxtw]
                                          ╰─╼ trap: GcHeapCorrupt
            e1 03 16 aa                  mov     x1, x22
            21 14 40 f9                  ldr     x1, [x1, #0x28]
            21 a0 40 b9                  ldr     w1, [x1, #0xa0]
            01 04 00 b9                  str     w1, [x0, #4]
                                          ╰─╼ trap: GcHeapCorrupt
            01 04 80 d2                  mov     x1, #0x20
            01 08 00 b9                  str     w1, [x0, #8]
                                          ╰─╼ trap: GcHeapCorrupt
            e2 83 00 b8                  stur    w2, [sp, #8]
            02 00 80 52                  mov     w2, #0
            02 10 00 b9                  str     w2, [x0, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            62 02 40 b9                  ldr     w2, [x19]
            e3 03 02 2a                  mov     w3, w2
            63 80 00 91                  add     x3, x3, #0x20
            64 06 40 b9                  ldr     w4, [x19, #4]
            7f 00 04 eb                  cmp     x3, x4
            48 28 00 54                  b.hi    #0x4dddc
            46 80 00 11                  add     w6, w2, #0x20
            66 02 00 b9                  str     w6, [x19]
            47 00 80 52                  mov     w7, #2
            07 00 b6 72                  movk    w7, #0xb000, lsl #16
            e0 03 16 aa                  mov     x0, x22
            08 04 40 f9                  ldr     x8, [x0, #8]
            08 11 40 f9                  ldr     x8, [x8, #0x20]
            00 41 22 8b                  add     x0, x8, w2, uxtw
            07 49 22 b8                  str     w7, [x8, w2, uxtw]
                                          ╰─╼ trap: GcHeapCorrupt
            e5 03 16 aa                  mov     x5, x22
            a8 14 40 f9                  ldr     x8, [x5, #0x28]
            08 a1 40 b9                  ldr     w8, [x8, #0xa0]
            08 04 00 b9                  str     w8, [x0, #4]
                                          ╰─╼ trap: GcHeapCorrupt
            09 04 80 d2                  mov     x9, #0x20
            09 08 00 b9                  str     w9, [x0, #8]
                                          ╰─╼ trap: GcHeapCorrupt
            e2 03 01 b8                  stur    w2, [sp, #0x10]
            0c 00 80 52                  mov     w12, #0
            0c 10 00 b9                  str     w12, [x0, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            62 02 40 b9                  ldr     w2, [x19]
            ed 03 02 2a                  mov     w13, w2
            ad 81 00 91                  add     x13, x13, #0x20
            6e 06 40 b9                  ldr     w14, [x19, #4]
            bf 01 0e eb                  cmp     x13, x14
            e8 26 00 54                  b.hi    #0x4de10
            40 80 00 11                  add     w0, w2, #0x20
            60 02 00 b9                  str     w0, [x19]
            41 00 80 52                  mov     w1, #2
            01 00 b6 72                  movk    w1, #0xb000, lsl #16
            e0 03 16 aa                  mov     x0, x22
            00 04 40 f9                  ldr     x0, [x0, #8]
            03 10 40 f9                  ldr     x3, [x0, #0x20]
            60 40 22 8b                  add     x0, x3, w2, uxtw
            61 48 22 b8                  str     w1, [x3, w2, uxtw]
                                          ╰─╼ trap: GcHeapCorrupt
            e1 03 16 aa                  mov     x1, x22
            21 14 40 f9                  ldr     x1, [x1, #0x28]
            21 44 46 b9                  ldr     w1, [x1, #0x644]
            01 04 00 b9                  str     w1, [x0, #4]
                                          ╰─╼ trap: GcHeapCorrupt
            01 04 80 d2                  mov     x1, #0x20
            01 08 00 b9                  str     w1, [x0, #8]
                                          ╰─╼ trap: GcHeapCorrupt
            e2 83 01 b8                  stur    w2, [sp, #0x18]
            01 00 80 d2                  mov     x1, #0
            01 08 00 f9                  str     x1, [x0, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            e2 03 16 aa                  mov     x2, x22
            40 04 40 f9                  ldr     x0, [x2, #8]
            17 10 40 f9                  ldr     x23, [x0, #0x20]
            e0 83 41 b8                  ldur    w0, [sp, #0x18]
            c0 25 00 34                  cbz     w0, #0x4de48
            e0 42 20 8b                  add     x0, x23, w0, uxtw
            19 08 40 f9                  ldr     x25, [x0, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            f3 03 14 aa                  mov     x19, x20
            20 27 d3 9a                  lsr     x0, x25, x19
            a0 06 00 b5                  cbnz    x0, #0x4da78
            e0 83 40 b8                  ldur    w0, [sp, #8]
            00 25 00 34                  cbz     w0, #0x4de4c
            e0 42 20 8b                  add     x0, x23, w0, uxtw
            00 10 40 b9                  ldr     w0, [x0, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            e1 03 40 b8                  ldur    w1, [sp]
            a1 24 00 34                  cbz     w1, #0x4de50
            e1 42 21 8b                  add     x1, x23, w1, uxtw
            22 14 40 b9                  ldr     w2, [x1, #0x14]
                                          ╰─╼ trap: GcHeapCorrupt
            1f 00 02 6b                  cmp     w0, w2
            aa 04 00 54                  b.ge    #0x4da60
            21 10 40 b9                  ldr     w1, [x1, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            01 24 00 34                  cbz     w1, #0x4de54
            e2 42 21 8b                  add     x2, x23, w1, uxtw
            42 10 40 b9                  ldr     w2, [x2, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            1f 00 02 6b                  cmp     w0, w2
            a2 23 00 54                  b.hs    #0x4de58
            e3 03 02 2a                  mov     w3, w2
            63 fc 60 d3                  lsr     x3, x3, #0x20
            63 23 00 b5                  cbnz    x3, #0x4de5c
            83 02 80 52                  mov     w3, #0x14
            42 00 03 2b                  adds    w2, w2, w3
            22 23 00 54                  b.hs    #0x4de60
            21 00 02 2b                  adds    w1, w1, w2
            02 23 00 54                  b.hs    #0x4de64
            e1 42 21 8b                  add     x1, x23, w1, uxtw
            00 50 00 11                  add     w0, w0, #0x14
            40 00 00 4b                  sub     w0, w2, w0
            20 40 20 cb                  sub     x0, x1, w0, uxtw
            04 00 40 39                  ldrb    w4, [x0]
                                          ╰─╼ trap: GcHeapCorrupt
            e2 03 16 aa                  mov     x2, x22
            e3 03 16 aa                  mov     x3, x22
            8f 8f 00 94                  bl      #0x71860
            e0 83 41 b8                  ldur    w0, [sp, #0x18]
                                          ╰─╼ stack_map: frame_size=96, frame_offsets=[0, 8, 16, 24]
            e0 21 00 34                  cbz     w0, #0x4de68
            41 01 80 d2                  mov     x1, #0xa
            21 0b 01 9b                  madd    x1, x25, x1, x2
            e0 42 20 8b                  add     x0, x23, w0, uxtw
            01 08 00 f9                  str     x1, [x0, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            e0 83 40 b8                  ldur    w0, [sp, #8]
            40 21 00 34                  cbz     w0, #0x4de6c
            e0 42 20 8b                  add     x0, x23, w0, uxtw
            01 10 40 b9                  ldr     w1, [x0, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            21 04 00 11                  add     w1, w1, #1
            01 10 00 b9                  str     w1, [x0, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            f4 03 13 aa                  mov     x20, x19
            cc ff ff 17                  b       #0x4d98c
            e0 83 41 b8                  ldur    w0, [sp, #0x18]
            60 20 00 34                  cbz     w0, #0x4de70
            e0 42 20 8b                  add     x0, x23, w0, uxtw
            01 08 40 f9                  ldr     x1, [x0, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            22 24 d3 9a                  lsr     x2, x1, x19
            62 18 00 b4                  cbz     x2, #0x4dd80
            e0 03 40 b8                  ldur    w0, [sp]
            c0 1f 00 34                  cbz     w0, #0x4de74
            e0 42 20 8b                  add     x0, x23, w0, uxtw
            01 18 40 b9                  ldr     w1, [x0, #0x18]
                                          ╰─╼ trap: GcHeapCorrupt
            e2 83 40 b8                  ldur    w2, [sp, #8]
            62 1f 00 34                  cbz     w2, #0x4de78
            e2 42 22 8b                  add     x2, x23, w2, uxtw
            42 10 40 b9                  ldr     w2, [x2, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            34 00 80 52                  mov     w20, #1
            42 04 00 51                  sub     w2, w2, #1
            21 00 02 4b                  sub     w1, w1, w2
            01 18 00 b9                  str     w1, [x0, #0x18]
                                          ╰─╼ trap: GcHeapCorrupt
            e0 83 40 b8                  ldur    w0, [sp, #8]
            80 1e 00 34                  cbz     w0, #0x4de7c
            e0 42 20 8b                  add     x0, x23, w0, uxtw
            01 10 40 b9                  ldr     w1, [x0, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            e0 03 40 b8                  ldur    w0, [sp]
            20 1e 00 34                  cbz     w0, #0x4de80
            e0 42 20 8b                  add     x0, x23, w0, uxtw
            02 14 40 b9                  ldr     w2, [x0, #0x14]
                                          ╰─╼ trap: GcHeapCorrupt
            3f 00 02 6b                  cmp     w1, w2
            8b 0a 00 54                  b.lt    #0x4dc1c
            e0 83 41 b8                  ldur    w0, [sp, #0x18]
            80 1d 00 34                  cbz     w0, #0x4de84
            e0 42 20 8b                  add     x0, x23, w0, uxtw
            00 08 40 f9                  ldr     x0, [x0, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            60 02 00 b5                  cbnz    x0, #0x4db2c
            e0 03 41 b8                  ldur    w0, [sp, #0x10]
            00 1d 00 34                  cbz     w0, #0x4de88
            e0 42 20 8b                  add     x0, x23, w0, uxtw
            00 10 40 b9                  ldr     w0, [x0, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            e4 03 40 b8                  ldur    w4, [sp]
            a4 1c 00 34                  cbz     w4, #0x4de8c
            e1 42 24 8b                  add     x1, x23, w4, uxtw
            20 14 00 b9                  str     w0, [x1, #0x14]
                                          ╰─╼ trap: GcHeapCorrupt
            e3 03 16 aa                  mov     x3, x22
            e2 03 03 aa                  mov     x2, x3
            a5 08 00 94                  bl      #0x4fda0
            ff c3 00 91                  add     sp, sp, #0x30
            f3 53 c1 a8                  ldp     x19, x20, [sp], #0x10
            f5 5b c1 a8                  ldp     x21, x22, [sp], #0x10
            f7 67 c1 a8                  ldp     x23, x25, [sp], #0x10
            fd 7b c1 a8                  ldp     x29, x30, [sp], #0x10
            df 23 03 d5                  autibz
            c0 03 5f d6                  ret
            e3 03 41 b8                  ldur    w3, [sp, #0x10]
            03 1b 00 34                  cbz     w3, #0x4de90
            e4 42 23 8b                  add     x4, x23, w3, uxtw
            95 10 40 b9                  ldr     w21, [x4, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            e4 03 40 b8                  ldur    w4, [sp]
            a4 1a 00 34                  cbz     w4, #0x4de94
            e5 42 24 8b                  add     x5, x23, w4, uxtw
            a6 10 40 b9                  ldr     w6, [x5, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            66 1a 00 34                  cbz     w6, #0x4de98
            e7 42 26 8b                  add     x7, x23, w6, uxtw
            e7 10 40 b9                  ldr     w7, [x7, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            bf 02 07 6b                  cmp     w21, w7
            ab 00 00 54                  b.lt    #0x4db70
            08 24 d3 9a                  lsr     x8, x0, x19
            28 04 00 b4                  cbz     x8, #0x4dbe8
            b4 20 00 b9                  str     w20, [x5, #0x20]
                                          ╰─╼ trap: GcHeapCorrupt
            1f 00 00 14                  b       #0x4dbe8
            e6 03 02 b8                  stur    w6, [sp, #0x20]
            04 24 d3 9a                  lsr     x4, x0, x19
            e2 03 16 aa                  mov     x2, x22
            e3 03 16 aa                  mov     x3, x22
            68 44 01 94                  bl      #0x9ed20
            ee 03 42 b8                  ldur    w14, [sp, #0x20]
                                          ╰─╼ stack_map: frame_size=96, frame_offsets=[0, 16, 24, 32]
            ae 18 00 34                  cbz     w14, #0x4de9c
            ef 42 2e 8b                  add     x15, x23, w14, uxtw
            ef 11 40 b9                  ldr     w15, [x15, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            bf 02 0f 6b                  cmp     w21, w15
            42 18 00 54                  b.hs    #0x4dea0
            e0 03 0f 2a                  mov     w0, w15
            00 fc 60 d3                  lsr     x0, x0, #0x20
            00 18 00 b5                  cbnz    x0, #0x4dea4
            80 02 80 52                  mov     w0, #0x14
            e0 01 00 2b                  adds    w0, w15, w0
            c2 17 00 54                  b.hs    #0x4dea8
            c1 01 00 2b                  adds    w1, w14, w0
            a2 17 00 54                  b.hs    #0x4deac
            e1 42 21 8b                  add     x1, x23, w1, uxtw
            a3 52 00 11                  add     w3, w21, #0x14
            00 00 03 4b                  sub     w0, w0, w3
            20 40 20 cb                  sub     x0, x1, w0, uxtw
            02 00 00 39                  strb    w2, [x0]
                                          ╰─╼ trap: GcHeapCorrupt
            e0 03 41 b8                  ldur    w0, [sp, #0x10]
            e0 16 00 34                  cbz     w0, #0x4deb0
            e0 42 20 8b                  add     x0, x23, w0, uxtw
            01 10 40 b9                  ldr     w1, [x0, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            21 04 00 11                  add     w1, w1, #1
            01 10 00 b9                  str     w1, [x0, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            e0 83 41 b8                  ldur    w0, [sp, #0x18]
            40 16 00 34                  cbz     w0, #0x4deb4
            e0 42 20 8b                  add     x0, x23, w0, uxtw
            01 08 40 f9                  ldr     x1, [x0, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            22 00 80 d2                  mov     x2, #1
            42 20 d3 9a                  lsl     x2, x2, x19
            42 04 00 d1                  sub     x2, x2, #1
            21 00 02 8a                  and     x1, x1, x2
            01 08 00 f9                  str     x1, [x0, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            42 01 80 d2                  mov     x2, #0xa
            21 7c 02 9b                  mul     x1, x1, x2
            01 08 00 f9                  str     x1, [x0, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            ae ff ff 17                  b       #0x4dad0
            e1 83 41 b8                  ldur    w1, [sp, #0x18]
            c1 14 00 34                  cbz     w1, #0x4deb8
            e1 42 21 8b                  add     x1, x23, w1, uxtw
            21 08 40 f9                  ldr     x1, [x1, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            00 10 40 b9                  ldr     w0, [x0, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            e0 03 02 b8                  stur    w0, [sp, #0x20]
            e0 03 41 b8                  ldur    w0, [sp, #0x10]
            20 14 00 34                  cbz     w0, #0x4debc
            e0 42 20 8b                  add     x0, x23, w0, uxtw
            15 10 40 b9                  ldr     w21, [x0, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            24 24 d3 9a                  lsr     x4, x1, x19
            e2 03 16 aa                  mov     x2, x22
            e3 03 16 aa                  mov     x3, x22
            34 44 01 94                  bl      #0x9ed20
            e1 03 42 b8                  ldur    w1, [sp, #0x20]
                                          ╰─╼ stack_map: frame_size=96, frame_offsets=[0, 8, 16, 24, 32]
            41 13 00 34                  cbz     w1, #0x4dec0
            e0 42 21 8b                  add     x0, x23, w1, uxtw
            03 10 40 b9                  ldr     w3, [x0, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            bf 02 03 6b                  cmp     w21, w3
            e2 12 00 54                  b.hs    #0x4dec4
            e0 03 03 2a                  mov     w0, w3
            00 fc 60 d3                  lsr     x0, x0, #0x20
            a0 12 00 b5                  cbnz    x0, #0x4dec8
            80 02 80 52                  mov     w0, #0x14
            63 00 00 2b                  adds    w3, w3, w0
            62 12 00 54                  b.hs    #0x4decc
            21 00 03 2b                  adds    w1, w1, w3
            42 12 00 54                  b.hs    #0x4ded0
            e1 42 21 8b                  add     x1, x23, w1, uxtw
            a4 52 00 11                  add     w4, w21, #0x14
            63 00 04 4b                  sub     w3, w3, w4
            21 40 23 cb                  sub     x1, x1, w3, uxtw
            22 00 00 39                  strb    w2, [x1]
                                          ╰─╼ trap: GcHeapCorrupt
            e1 03 41 b8                  ldur    w1, [sp, #0x10]
            81 11 00 34                  cbz     w1, #0x4ded4
            e1 42 21 8b                  add     x1, x23, w1, uxtw
            22 10 40 b9                  ldr     w2, [x1, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            42 04 00 11                  add     w2, w2, #1
            22 10 00 b9                  str     w2, [x1, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            e1 83 41 b8                  ldur    w1, [sp, #0x18]
            e1 10 00 34                  cbz     w1, #0x4ded8
            e1 42 21 8b                  add     x1, x23, w1, uxtw
            22 08 40 f9                  ldr     x2, [x1, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            23 00 80 d2                  mov     x3, #1
            63 20 d3 9a                  lsl     x3, x3, x19
            63 04 00 d1                  sub     x3, x3, #1
            55 00 03 8a                  and     x21, x2, x3
            35 08 00 f9                  str     x21, [x1, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            e1 03 40 b8                  ldur    w1, [sp]
            e1 0f 00 34                  cbz     w1, #0x4dedc
            e1 42 21 8b                  add     x1, x23, w1, uxtw
            21 10 40 b9                  ldr     w1, [x1, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            e2 83 40 b8                  ldur    w2, [sp, #8]
            82 0f 00 34                  cbz     w2, #0x4dee0
            e2 42 22 8b                  add     x2, x23, w2, uxtw
            42 10 40 b9                  ldr     w2, [x2, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            41 0f 00 34                  cbz     w1, #0x4dee4
            e3 42 21 8b                  add     x3, x23, w1, uxtw
            63 10 40 b9                  ldr     w3, [x3, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            5f 00 03 6b                  cmp     w2, w3
            e2 0e 00 54                  b.hs    #0x4dee8
            e4 03 03 2a                  mov     w4, w3
            84 fc 60 d3                  lsr     x4, x4, #0x20
            a4 0e 00 b5                  cbnz    x4, #0x4deec
            60 00 00 2b                  adds    w0, w3, w0
            82 0e 00 54                  b.hs    #0x4def0
            21 00 00 2b                  adds    w1, w1, w0
            62 0e 00 54                  b.hs    #0x4def4
            e1 42 21 8b                  add     x1, x23, w1, uxtw
            42 50 00 11                  add     w2, w2, #0x14
            00 00 02 4b                  sub     w0, w0, w2
            20 40 20 cb                  sub     x0, x1, w0, uxtw
            04 00 40 39                  ldrb    w4, [x0]
                                          ╰─╼ trap: GcHeapCorrupt
            e2 03 16 aa                  mov     x2, x22
            e3 03 16 aa                  mov     x3, x22
            c6 8e 00 94                  bl      #0x71860
            e0 83 41 b8                  ldur    w0, [sp, #0x18]
                                          ╰─╼ stack_map: frame_size=96, frame_offsets=[0, 8, 16, 24]
            40 0d 00 34                  cbz     w0, #0x4def8
            41 01 80 d2                  mov     x1, #0xa
            a1 0a 01 9b                  madd    x1, x21, x1, x2
            e0 42 20 8b                  add     x0, x23, w0, uxtw
            01 08 00 f9                  str     x1, [x0, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            e0 83 40 b8                  ldur    w0, [sp, #8]
            a0 0c 00 34                  cbz     w0, #0x4defc
            e0 42 20 8b                  add     x0, x23, w0, uxtw
            01 10 40 b9                  ldr     w1, [x0, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            21 04 00 11                  add     w1, w1, #1
            01 10 00 b9                  str     w1, [x0, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            4b ff ff 17                  b       #0x4daa8
            42 01 80 d2                  mov     x2, #0xa
            21 7c 02 9b                  mul     x1, x1, x2
            01 08 00 f9                  str     x1, [x0, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            e0 83 40 b8                  ldur    w0, [sp, #8]
            80 0b 00 34                  cbz     w0, #0x4df00
            e0 42 20 8b                  add     x0, x23, w0, uxtw
            01 10 40 b9                  ldr     w1, [x0, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            21 04 00 11                  add     w1, w1, #1
            01 10 00 b9                  str     w1, [x0, #0x10]
                                          ╰─╼ trap: GcHeapCorrupt
            2f ff ff 17                  b       #0x4da60
            43 00 80 52                  mov     w3, #2
            03 00 b6 72                  movk    w3, #0xb000, lsl #16
            e2 03 16 aa                  mov     x2, x22
            40 14 40 f9                  ldr     x0, [x2, #0x28]
            04 a0 40 b9                  ldr     w4, [x0, #0xa0]
            05 04 80 52                  mov     w5, #0x20
            06 02 80 52                  mov     w6, #0x10
            0f 7f 02 94                  bl      #0xeda00
            e0 03 16 aa                  mov     x0, x22
                                          ╰─╼ stack_map: frame_size=96, frame_offsets=[0]
            00 04 40 f9                  ldr     x0, [x0, #8]
            00 10 40 f9                  ldr     x0, [x0, #0x20]
            00 40 22 8b                  add     x0, x0, w2, uxtw
            b7 fe ff 17                  b       #0x4d8b4
            43 00 80 52                  mov     w3, #2
            03 00 b6 72                  movk    w3, #0xb000, lsl #16
            e2 03 16 aa                  mov     x2, x22
            45 14 40 f9                  ldr     x5, [x2, #0x28]
            a4 a0 40 b9                  ldr     w4, [x5, #0xa0]
            05 04 80 52                  mov     w5, #0x20
            06 02 80 52                  mov     w6, #0x10
            02 7f 02 94                  bl      #0xeda00
            e0 03 16 aa                  mov     x0, x22
                                          ╰─╼ stack_map: frame_size=96, frame_offsets=[0, 8]
            05 04 40 f9                  ldr     x5, [x0, #8]
            a5 10 40 f9                  ldr     x5, [x5, #0x20]
            a0 40 22 8b                  add     x0, x5, w2, uxtw
            c2 fe ff 17                  b       #0x4d914
            43 00 80 52                  mov     w3, #2
            03 00 b6 72                  movk    w3, #0xb000, lsl #16
            e2 03 16 aa                  mov     x2, x22
            4f 14 40 f9                  ldr     x15, [x2, #0x28]
            e4 45 46 b9                  ldr     w4, [x15, #0x644]
            05 04 80 52                  mov     w5, #0x20
            06 02 80 52                  mov     w6, #0x10
            f5 7e 02 94                  bl      #0xeda00
            e0 03 16 aa                  mov     x0, x22
                                          ╰─╼ stack_map: frame_size=96, frame_offsets=[0, 8, 16]
            0f 04 40 f9                  ldr     x15, [x0, #8]
            ef 11 40 f9                  ldr     x15, [x15, #0x20]
            e0 41 22 8b                  add     x0, x15, w2, uxtw
            cd fe ff 17                  b       #0x4d974
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: Normal(StackOverflow)
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: Normal(NullReference)
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: Normal(NullReference)
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: Normal(NullReference)
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: Normal(NullReference)
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: Normal(ArrayOutOfBounds)
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: GcHeapCorrupt
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: GcHeapCorrupt
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: GcHeapCorrupt
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: Normal(NullReference)
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: Normal(NullReference)
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: Normal(NullReference)
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: Normal(NullReference)
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: Normal(NullReference)
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: Normal(NullReference)
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: Normal(NullReference)
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: Normal(NullReference)
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: Normal(NullReference)
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: Normal(NullReference)
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: Normal(NullReference)
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: Normal(NullReference)
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: Normal(NullReference)
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: Normal(NullReference)
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: Normal(ArrayOutOfBounds)
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: GcHeapCorrupt
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: GcHeapCorrupt
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: GcHeapCorrupt
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: Normal(NullReference)
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: Normal(NullReference)
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: Normal(NullReference)
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: Normal(NullReference)
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: Normal(NullReference)
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: Normal(ArrayOutOfBounds)
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: GcHeapCorrupt
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: GcHeapCorrupt
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: GcHeapCorrupt
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: Normal(NullReference)
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: Normal(NullReference)
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: Normal(NullReference)
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: Normal(NullReference)
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: Normal(NullReference)
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: Normal(ArrayOutOfBounds)
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: GcHeapCorrupt
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: GcHeapCorrupt
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: GcHeapCorrupt
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: Normal(NullReference)
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: Normal(NullReference)
            1f c1 00 00                  udf     #0xc11f
                                          ╰─╼ trap: Normal(NullReference)
```

### V8 final optimized Turboshaft IR

Node IDs, dependencies, properties and representations come from the emitted graph; not reconstructed from source.

```text
B0 #0 Parameter() [0] [Tagged]
B0 #1 Parameter() [1] [Tagged]
B0 #3 Parameter() [2] [Word32]
B0 #4 Load(#0) [tagged base, TaggedPointer, Tagged, offset: 240] [Tagged]
B0 #5 Constant() [word32: 0] [Word32]
B0 #6 Constant() [word64: 0] [Word64]
B0 #7 WasmStackCheck() [function-entry] []
B0 #8 Load(#4) [tagged base, AnyTagged, Tagged, offset: 2440] [Tagged]
B0 #9 Constant() [word64: 24] [Word64]
B0 #10 Load(#0) [tagged base, Uint64, Word64, offset: 72] [Word64]
B0 #11 Load(#10) [raw, Uint64, Word64] [Word64]
B0 #12 Constant() [number: 128] [Tagged]
B0 #13 Load(#0) [tagged base, Uint64, Word64, offset: 64] [Word64]
B0 #14 Constant() [word64: 131072] [Word64]
B0 #15 Constant() [word32: 1] [Word32]
B0 #16 Goto() [B1, 0] []
B1 #17 Load(#13) [raw, Uint64, Word64] [Word64]
B1 #18 WordBinop(#11, #9) [Add, Word64] [Word64]
B1 #19 Comparison(#18, #17) [UnsignedLessThan, Word64] [Word32]
B1 #20 Branch(#19) [B3, B2, True] []
B2 #22 Call(#12, #9) [BuiltinPointer:Allocate Descriptor:r1s0i2f0] []
B2 #24 DidntThrow(#22) [🁫🁫 🁫🁫 🁤🁪 🁫 i a, 0] [Tagged]
B2 #26 TaggedBitcast(#24) [Tagged, Word64, HeapObject] [Word64]
B2 #27 Constant() [word64: 1] [Word64]
B2 #28 Constant() [word64: -1] [Word64]
B2 #29 WordBinop(#26, #28) [Add, Word64] [Word64]
B2 #30 Goto() [B4, 0] []
B3 #31 Goto() [B4, 0] []
B4 #32 Phi(#11, #29) [Word64] [Word64]
B4 #33 WordBinop(#32, #9) [Add, Word64] [Word64]
B4 #34 Store(#10, #33) [raw, Uint64, NoWriteBarrier] []
B4 #36 Constant() [word64: 1] [Word64]
B4 #37 WordBinop(#32, #36) [Add, Word64] [Word64]
B4 #38 TaggedBitcast(#37) [Word64, Tagged, HeapObject] [Tagged]
B4 #39 Store(#38, #8) [tagged base, TaggedPointer, NoWriteBarrier, initializing] []
B4 #40 LoadRootRegister()  [Word64]
B4 #41 Load(#40) [raw, Uint64, Word64, offset: 608] [Word64]
B4 #42 Store(#38, #41) [tagged base, AnyTagged, NoWriteBarrier, offset: 8, initializing] []
B4 #44 Store(#38, #5) [tagged base, Int32, NoWriteBarrier, offset: 16] []
B4 #45 Load(#0) [tagged base, Uint64, Word64, offset: 72] [Word64]
B4 #46 Load(#45) [raw, Uint64, Word64] [Word64]
B4 #47 Load(#0) [tagged base, Uint64, Word64, offset: 64] [Word64]
B4 #48 Goto() [B5, 0] []
B5 #49 Load(#47) [raw, Uint64, Word64] [Word64]
B5 #50 WordBinop(#46, #9) [Add, Word64] [Word64]
B5 #51 Comparison(#50, #49) [UnsignedLessThan, Word64] [Word32]
B5 #52 Branch(#51) [B7, B6, True] []
B6 #54 Call(#12, #9) [BuiltinPointer:Allocate Descriptor:r1s0i2f0] []
B6 #56 DidntThrow(#54) [🁫🁫 🁫🁫 🁤🁪 🁫 i a, 0] [Tagged]
B6 #58 TaggedBitcast(#56) [Tagged, Word64, HeapObject] [Word64]
B6 #59 Constant() [word64: -1] [Word64]
B6 #60 WordBinop(#58, #59) [Add, Word64] [Word64]
B6 #61 Goto() [B8, 0] []
B7 #62 Goto() [B8, 0] []
B8 #63 Phi(#46, #60) [Word64] [Word64]
B8 #64 WordBinop(#63, #9) [Add, Word64] [Word64]
B8 #65 Store(#45, #64) [raw, Uint64, NoWriteBarrier] []
B8 #67 WordBinop(#63, #36) [Add, Word64] [Word64]
B8 #68 TaggedBitcast(#67) [Word64, Tagged, HeapObject] [Tagged]
B8 #69 Store(#68, #8) [tagged base, TaggedPointer, NoWriteBarrier, initializing] []
B8 #70 Load(#40) [raw, Uint64, Word64, offset: 608] [Word64]
B8 #71 Store(#68, #70) [tagged base, AnyTagged, NoWriteBarrier, offset: 8, initializing] []
B8 #73 Store(#68, #5) [tagged base, Int32, NoWriteBarrier, offset: 16] []
B8 #74 Load(#4) [tagged base, AnyTagged, Tagged, offset: 5464] [Tagged]
B8 #75 Load(#0) [tagged base, Uint64, Word64, offset: 72] [Word64]
B8 #76 Load(#75) [raw, Uint64, Word64] [Word64]
B8 #77 Load(#0) [tagged base, Uint64, Word64, offset: 64] [Word64]
B8 #78 Goto() [B9, 0] []
B9 #79 Load(#77) [raw, Uint64, Word64] [Word64]
B9 #80 WordBinop(#76, #9) [Add, Word64] [Word64]
B9 #81 Comparison(#80, #79) [UnsignedLessThan, Word64] [Word32]
B9 #82 Branch(#81) [B11, B10, True] []
B10 #84 Call(#12, #9) [BuiltinPointer:Allocate Descriptor:r1s0i2f0] []
B10 #86 DidntThrow(#84) [🁫🁫 🁫🁫 🁤🁪 🁫 i a, 0] [Tagged]
B10 #88 TaggedBitcast(#86) [Tagged, Word64, HeapObject] [Word64]
B10 #89 Constant() [word64: -1] [Word64]
B10 #90 WordBinop(#88, #89) [Add, Word64] [Word64]
B10 #91 Goto() [B12, 0] []
B11 #92 Goto() [B12, 0] []
B12 #93 Phi(#76, #90) [Word64] [Word64]
B12 #94 WordBinop(#93, #9) [Add, Word64] [Word64]
B12 #95 Store(#75, #94) [raw, Uint64, NoWriteBarrier] []
B12 #97 WordBinop(#93, #36) [Add, Word64] [Word64]
B12 #98 TaggedBitcast(#97) [Word64, Tagged, HeapObject] [Tagged]
B12 #99 Store(#98, #74) [tagged base, TaggedPointer, NoWriteBarrier, initializing] []
B12 #100 Load(#40) [raw, Uint64, Word64, offset: 608] [Word64]
B12 #101 Store(#98, #100) [tagged base, AnyTagged, NoWriteBarrier, offset: 8, initializing] []
B12 #103 Store(#98, #6) [tagged base, Int64, NoWriteBarrier, offset: 16] []
B12 #104 Constant() [word32: 63] [Word32]
B12 #105 WordBinop(#3, #104) [BitwiseAnd, Word32] [Word32]
B12 #106 Shift(#6, #105) [ShiftRightLogical, Word64] [Word64]
B12 #107 Comparison(#106, #6) [Equal, Word64] [Word32]
B12 #108 Branch(#107) [B13, B49, None] []
B13 #110 Load(#1) [tagged base, Int32, Word32, offset: 24] [Word32]
B13 #111 Comparison(#110, #5) [SignedLessThanOrEqual, Word32] [Word32]
B13 #112 Branch(#111) [B34, B14, None] []
B14 #114 Load(#1) [tagged base, AnyTagged, Tagged, offset: 16] [Tagged]
B14 #115 Load(#114) [tagged base, Int32, Word32, offset: 16] [Word32]
B14 #116 Comparison(#5, #115) [UnsignedLessThan, Word32] [Word32]
B14 #117 TrapIf(#116) [1, TrapArrayOutOfBounds] []
B14 #118 Load(#114) [tagged base, Uint8, Word32, offset: 24] [Word32]
B14 #119 Constant() [word64: 10] [Word64]
B14 #120 Change(#118) [SignExtend, NoAssumption, Word32, Word64] [Word64]
B14 #121 Store(#98, #120) [tagged base, Int64, NoWriteBarrier, offset: 16] []
B14 #123 Store(#38, #15) [tagged base, Int32, NoWriteBarrier, offset: 16] []
B14 #124 Goto() [B15, 0] []
B15 #125 Load(#98) [tagged base, Int64, Word64, offset: 16] [Word64]
B15 #126 Shift(#125, #105) [ShiftRightLogical, Word64] [Word64]
B15 #127 Comparison(#126, #6) [Equal, Word64] [Word32]
B15 #128 Branch(#127) [B16, B32, None] []
B16 #130 Load(#38) [tagged base, Int32, Word32, offset: 16] [Word32]
B16 #131 Comparison(#110, #130) [SignedLessThanOrEqual, Word32] [Word32]
B16 #132 Branch(#131) [B30, B17, None] []
B17 #134 Comparison(#130, #115) [UnsignedLessThan, Word32] [Word32]
B17 #135 TrapIf(#134) [1, TrapArrayOutOfBounds] []
B17 #136 Change(#130) [SignExtend, NoAssumption, Word32, Word64] [Word64]
B17 #137 Load(#114, #136) [tagged base, Uint8, Word32, offset: 24] [Word32]
B17 #139 WordBinop(#125, #119) [Mul, Word64] [Word64]
B17 #140 Change(#137) [SignExtend, NoAssumption, Word32, Word64] [Word64]
B17 #141 WordBinop(#139, #140) [Add, Word64] [Word64]
B17 #142 Store(#98, #141) [tagged base, Int64, NoWriteBarrier, offset: 16] []
B17 #143 WordBinop(#130, #15) [Add, Word32] [Word32]
B17 #144 Store(#38, #143) [tagged base, Int32, NoWriteBarrier, offset: 16] []
B17 #146 Shift(#141, #105) [ShiftRightLogical, Word64] [Word64]
B17 #147 Comparison(#146, #6) [Equal, Word64] [Word32]
B17 #148 Branch(#147) [B19, B18, None] []
B18 #150 Goto() [B33, 0] []
B19 #151 Comparison(#110, #143) [SignedLessThanOrEqual, Word32] [Word32]
B19 #152 Branch(#151) [B20, B21, None] []
B20 #154 Goto() [B31, 0] []
B21 #155 Comparison(#143, #115) [UnsignedLessThan, Word32] [Word32]
B21 #156 TrapIf(#155) [1, TrapArrayOutOfBounds] []
B21 #157 Change(#143) [SignExtend, NoAssumption, Word32, Word64] [Word64]
B21 #158 Load(#114, #157) [tagged base, Uint8, Word32, offset: 24] [Word32]
B21 #159 WordBinop(#141, #119) [Mul, Word64] [Word64]
B21 #160 Change(#158) [SignExtend, NoAssumption, Word32, Word64] [Word64]
B21 #161 WordBinop(#159, #160) [Add, Word64] [Word64]
B21 #162 Store(#98, #161) [tagged base, Int64, NoWriteBarrier, offset: 16] []
B21 #164 WordBinop(#143, #15) [Add, Word32] [Word32]
B21 #165 Store(#38, #164) [tagged base, Int32, NoWriteBarrier, offset: 16] []
B21 #166 Shift(#161, #105) [ShiftRightLogical, Word64] [Word64]
B21 #167 Comparison(#166, #6) [Equal, Word64] [Word32]
B21 #168 Branch(#167) [B23, B22, None] []
B22 #170 Goto() [B33, 0] []
B23 #171 Comparison(#110, #164) [SignedLessThanOrEqual, Word32] [Word32]
B23 #172 Branch(#171) [B24, B25, None] []
B24 #174 Goto() [B31, 0] []
B25 #175 Comparison(#164, #115) [UnsignedLessThan, Word32] [Word32]
B25 #176 TrapIf(#175) [1, TrapArrayOutOfBounds] []
B25 #177 Change(#164) [SignExtend, NoAssumption, Word32, Word64] [Word64]
B25 #178 Load(#114, #177) [tagged base, Uint8, Word32, offset: 24] [Word32]
B25 #180 WordBinop(#161, #119) [Mul, Word64] [Word64]
B25 #181 Change(#178) [SignExtend, NoAssumption, Word32, Word64] [Word64]
B25 #182 WordBinop(#180, #181) [Add, Word64] [Word64]
B25 #183 Store(#98, #182) [tagged base, Int64, NoWriteBarrier, offset: 16] []
B25 #184 WordBinop(#164, #15) [Add, Word32] [Word32]
B25 #185 Store(#38, #184) [tagged base, Int32, NoWriteBarrier, offset: 16] []
B25 #187 WasmStackCheck() [loop] []
B25 #188 Shift(#182, #105) [ShiftRightLogical, Word64] [Word64]
B25 #189 Comparison(#188, #6) [Equal, Word64] [Word32]
B25 #190 Branch(#189) [B27, B26, None] []
B26 #192 Goto() [B33, 0] []
B27 #193 Comparison(#110, #184) [SignedLessThanOrEqual, Word32] [Word32]
B27 #194 Branch(#193) [B28, B29, None] []
B28 #196 Goto() [B31, 0] []
B29 #197 Comparison(#184, #115) [UnsignedLessThan, Word32] [Word32]
B29 #198 TrapIf(#197) [1, TrapArrayOutOfBounds] []
B29 #199 Change(#184) [SignExtend, NoAssumption, Word32, Word64] [Word64]
B29 #200 Load(#114, #199) [tagged base, Uint8, Word32, offset: 24] [Word32]
B29 #201 WordBinop(#182, #119) [Mul, Word64] [Word64]
B29 #202 Change(#200) [SignExtend, NoAssumption, Word32, Word64] [Word64]
B29 #203 WordBinop(#201, #202) [Add, Word64] [Word64]
B29 #204 Store(#98, #203) [tagged base, Int64, NoWriteBarrier, offset: 16] []
B29 #206 WordBinop(#184, #15) [Add, Word32] [Word32]
B29 #207 Store(#38, #206) [tagged base, Int32, NoWriteBarrier, offset: 16] []
B29 #208 Goto() [B15, 1] []
B30 #209 Goto() [B31, 0] []
B31 #210 Goto() [B35, 0] []
B32 #211 Goto() [B33, 0] []
B33 #212 Goto() [B50, 0] []
B34 #213 Goto() [B35, 0] []
B35 #214 Load(#98) [tagged base, Int64, Word64, offset: 16] [Word64]
B35 #215 Shift(#214, #105) [ShiftRightLogical, Word64] [Word64]
B35 #216 Comparison(#215, #6) [Equal, Word64] [Word32]
B35 #217 Branch(#216) [B36, B47, None] []
B36 #219 Constant() [word64: 10] [Word64]
B36 #220 WordBinop(#214, #219) [Mul, Word64] [Word64]
B36 #221 Store(#98, #220) [tagged base, Int64, NoWriteBarrier, offset: 16] []
B36 #223 Load(#38) [tagged base, Int32, Word32, offset: 16] [Word32]
B36 #224 WordBinop(#223, #15) [Add, Word32] [Word32]
B36 #225 Store(#38, #224) [tagged base, Int32, NoWriteBarrier, offset: 16] []
B36 #226 Goto() [B37, 0] []
B37 #227 Load(#98) [tagged base, Int64, Word64, offset: 16] [Word64]
B37 #228 Shift(#227, #105) [ShiftRightLogical, Word64] [Word64]
B37 #229 Comparison(#228, #6) [Equal, Word64] [Word32]
B37 #230 Branch(#229) [B38, B45, None] []
B38 #232 WordBinop(#227, #219) [Mul, Word64] [Word64]
B38 #233 Store(#98, #232) [tagged base, Int64, NoWriteBarrier, offset: 16] []
B38 #235 Load(#38) [tagged base, Int32, Word32, offset: 16] [Word32]
B38 #236 WordBinop(#235, #15) [Add, Word32] [Word32]
B38 #237 Store(#38, #236) [tagged base, Int32, NoWriteBarrier, offset: 16] []
B38 #238 Shift(#232, #105) [ShiftRightLogical, Word64] [Word64]
B38 #239 Comparison(#238, #6) [Equal, Word64] [Word32]
B38 #240 Branch(#239) [B40, B39, None] []
B39 #242 Goto() [B46, 0] []
B40 #243 WordBinop(#232, #219) [Mul, Word64] [Word64]
B40 #244 Store(#98, #243) [tagged base, Int64, NoWriteBarrier, offset: 16] []
B40 #246 WordBinop(#236, #15) [Add, Word32] [Word32]
B40 #247 Store(#38, #246) [tagged base, Int32, NoWriteBarrier, offset: 16] []
B40 #248 Shift(#243, #105) [ShiftRightLogical, Word64] [Word64]
B40 #249 Comparison(#248, #6) [Equal, Word64] [Word32]
B40 #250 Branch(#249) [B42, B41, None] []
B41 #252 Goto() [B46, 0] []
B42 #253 WordBinop(#243, #219) [Mul, Word64] [Word64]
B42 #254 Store(#98, #253) [tagged base, Int64, NoWriteBarrier, offset: 16] []
B42 #256 WordBinop(#246, #15) [Add, Word32] [Word32]
B42 #257 Store(#38, #256) [tagged base, Int32, NoWriteBarrier, offset: 16] []
B42 #258 WasmStackCheck() [loop] []
B42 #259 Shift(#253, #105) [ShiftRightLogical, Word64] [Word64]
B42 #260 Comparison(#259, #6) [Equal, Word64] [Word32]
B42 #261 Branch(#260) [B44, B43, None] []
B43 #263 Goto() [B46, 0] []
B44 #264 WordBinop(#253, #219) [Mul, Word64] [Word64]
B44 #265 Store(#98, #264) [tagged base, Int64, NoWriteBarrier, offset: 16] []
B44 #267 WordBinop(#256, #15) [Add, Word32] [Word32]
B44 #268 Store(#38, #267) [tagged base, Int32, NoWriteBarrier, offset: 16] []
B44 #269 Goto() [B37, 1] []
B45 #270 Goto() [B46, 0] []
B46 #271 Goto() [B48, 0] []
B47 #272 Goto() [B48, 0] []
B48 #273 Goto() [B51, 0] []
B49 #274 Goto() [B50, 0] []
B50 #275 Goto() [B51, 0] []
B51 #276 Load(#1) [tagged base, Int32, Word32, offset: 28] [Word32]
B51 #277 Load(#38) [tagged base, Int32, Word32, offset: 16] [Word32]
B51 #278 Constant() [word32: -1] [Word32]
B51 #279 WordBinop(#277, #278) [Add, Word32] [Word32]
B51 #280 WordBinop(#276, #279) [Sub, Word32] [Word32]
B51 #281 Store(#1, #280) [tagged base, Int32, NoWriteBarrier, offset: 28] []
B51 #283 Shift(#36, #105) [ShiftLeft, Word64] [Word64]
B51 #284 Constant() [word64: -1] [Word64]
B51 #285 WordBinop(#283, #284) [Add, Word64] [Word64]
B51 #286 Load(#1) [tagged base, Int32, Word32, offset: 24] [Word32]
B51 #287 Comparison(#277, #286) [SignedLessThan, Word32] [Word32]
B51 #288 Branch(#287) [B52, B61, None] []
B52 #290 Load(#98) [tagged base, Int64, Word64, offset: 16] [Word64]
B52 #291 Shift(#290, #105) [ShiftRightLogical, Word64] [Word64]
B52 #292 Load(#1) [tagged base, AnyTagged, Tagged, offset: 16] [Tagged]
B52 #293 Change(#291) [Truncate, NoAssumption, Word64, Word32] [Word32]
B52 #294 Constant() [word32: 255] [Word32]
B52 #295 Load(#292) [tagged base, Int32, Word32, offset: 16] [Word32]
B52 #296 Comparison(#5, #295) [UnsignedLessThan, Word32] [Word32]
B52 #297 TrapIf(#296) [1, TrapArrayOutOfBounds] []
B52 #298 Store(#292, #293) [tagged base, Int8, NoWriteBarrier, offset: 24] []
B52 #299 Store(#68, #15) [tagged base, Int32, NoWriteBarrier, offset: 16] []
B52 #301 WordBinop(#290, #285) [BitwiseAnd, Word64] [Word64]
B52 #302 Store(#98, #301) [tagged base, Int64, NoWriteBarrier, offset: 16] []
B52 #303 Comparison(#277, #295) [UnsignedLessThan, Word32] [Word32]
B52 #304 TrapIf(#303) [1, TrapArrayOutOfBounds] []
B52 #305 Change(#277) [SignExtend, NoAssumption, Word32, Word64] [Word64]
B52 #306 Load(#292, #305) [tagged base, Uint8, Word32, offset: 24] [Word32]
B52 #308 Constant() [word64: 10] [Word64]
B52 #309 WordBinop(#301, #308) [Mul, Word64] [Word64]
B52 #310 Change(#306) [SignExtend, NoAssumption, Word32, Word64] [Word64]
B52 #311 WordBinop(#309, #310) [Add, Word64] [Word64]
B52 #312 Store(#98, #311) [tagged base, Int64, NoWriteBarrier, offset: 16] []
B52 #313 WordBinop(#277, #15) [Add, Word32] [Word32]
B52 #314 Store(#38, #313) [tagged base, Int32, NoWriteBarrier, offset: 16] []
B52 #316 Goto() [B53, 0] []
B53 #317 Load(#38) [tagged base, Int32, Word32, offset: 16] [Word32]
B53 #318 Comparison(#317, #286) [SignedLessThan, Word32] [Word32]
B53 #319 Branch(#318) [B54, B59, None] []
B54 #321 Load(#98) [tagged base, Int64, Word64, offset: 16] [Word64]
B54 #322 Shift(#321, #105) [ShiftRightLogical, Word64] [Word64]
B54 #323 Load(#68) [tagged base, Int32, Word32, offset: 16] [Word32]
B54 #324 Change(#322) [Truncate, NoAssumption, Word64, Word32] [Word32]
B54 #325 Comparison(#323, #295) [UnsignedLessThan, Word32] [Word32]
B54 #326 TrapIf(#325) [1, TrapArrayOutOfBounds] []
B54 #327 Change(#323) [SignExtend, NoAssumption, Word32, Word64] [Word64]
B54 #328 Store(#292, #327, #324) [tagged base, Int8, NoWriteBarrier, offset: 24] []
B54 #330 WordBinop(#323, #15) [Add, Word32] [Word32]
B54 #331 Store(#68, #330) [tagged base, Int32, NoWriteBarrier, offset: 16] []
B54 #332 WordBinop(#321, #285) [BitwiseAnd, Word64] [Word64]
B54 #333 Store(#98, #332) [tagged base, Int64, NoWriteBarrier, offset: 16] []
B54 #335 Comparison(#317, #295) [UnsignedLessThan, Word32] [Word32]
B54 #336 TrapIf(#335) [1, TrapArrayOutOfBounds] []
B54 #337 Change(#317) [SignExtend, NoAssumption, Word32, Word64] [Word64]
B54 #338 Load(#292, #337) [tagged base, Uint8, Word32, offset: 24] [Word32]
B54 #339 WordBinop(#332, #308) [Mul, Word64] [Word64]
B54 #340 Change(#338) [SignExtend, NoAssumption, Word32, Word64] [Word64]
B54 #341 WordBinop(#339, #340) [Add, Word64] [Word64]
B54 #342 Store(#98, #341) [tagged base, Int64, NoWriteBarrier, offset: 16] []
B54 #344 WordBinop(#317, #15) [Add, Word32] [Word32]
B54 #345 Store(#38, #344) [tagged base, Int32, NoWriteBarrier, offset: 16] []
B54 #346 Comparison(#344, #286) [SignedLessThan, Word32] [Word32]
B54 #347 Branch(#346) [B56, B55, None] []
B55 #349 Goto() [B60, 0] []
B56 #350 Shift(#341, #105) [ShiftRightLogical, Word64] [Word64]
B56 #351 Change(#350) [Truncate, NoAssumption, Word64, Word32] [Word32]
B56 #352 Comparison(#330, #295) [UnsignedLessThan, Word32] [Word32]
B56 #353 TrapIf(#352) [1, TrapArrayOutOfBounds] []
B56 #354 Change(#330) [SignExtend, NoAssumption, Word32, Word64] [Word64]
B56 #355 Store(#292, #354, #351) [tagged base, Int8, NoWriteBarrier, offset: 24] []
B56 #357 WordBinop(#330, #15) [Add, Word32] [Word32]
B56 #358 Store(#68, #357) [tagged base, Int32, NoWriteBarrier, offset: 16] []
B56 #360 WordBinop(#341, #285) [BitwiseAnd, Word64] [Word64]
B56 #361 Store(#98, #360) [tagged base, Int64, NoWriteBarrier, offset: 16] []
B56 #362 Comparison(#344, #295) [UnsignedLessThan, Word32] [Word32]
B56 #363 TrapIf(#362) [1, TrapArrayOutOfBounds] []
B56 #364 Change(#344) [SignExtend, NoAssumption, Word32, Word64] [Word64]
B56 #365 Load(#292, #364) [tagged base, Uint8, Word32, offset: 24] [Word32]
B56 #367 WordBinop(#360, #308) [Mul, Word64] [Word64]
B56 #368 Change(#365) [SignExtend, NoAssumption, Word32, Word64] [Word64]
B56 #369 WordBinop(#367, #368) [Add, Word64] [Word64]
B56 #370 Store(#98, #369) [tagged base, Int64, NoWriteBarrier, offset: 16] []
B56 #371 WordBinop(#344, #15) [Add, Word32] [Word32]
B56 #372 Store(#38, #371) [tagged base, Int32, NoWriteBarrier, offset: 16] []
B56 #374 WasmStackCheck() [loop] []
B56 #375 Comparison(#371, #286) [SignedLessThan, Word32] [Word32]
B56 #376 Branch(#375) [B58, B57, None] []
B57 #378 Goto() [B60, 0] []
B58 #379 Shift(#369, #105) [ShiftRightLogical, Word64] [Word64]
B58 #380 Change(#379) [Truncate, NoAssumption, Word64, Word32] [Word32]
B58 #381 Comparison(#357, #295) [UnsignedLessThan, Word32] [Word32]
B58 #382 TrapIf(#381) [1, TrapArrayOutOfBounds] []
B58 #383 Change(#357) [SignExtend, NoAssumption, Word32, Word64] [Word64]
B58 #384 Store(#292, #383, #380) [tagged base, Int8, NoWriteBarrier, offset: 24] []
B58 #386 WordBinop(#357, #15) [Add, Word32] [Word32]
B58 #387 Store(#68, #386) [tagged base, Int32, NoWriteBarrier, offset: 16] []
B58 #388 WordBinop(#369, #285) [BitwiseAnd, Word64] [Word64]
B58 #389 Store(#98, #388) [tagged base, Int64, NoWriteBarrier, offset: 16] []
B58 #391 Comparison(#371, #295) [UnsignedLessThan, Word32] [Word32]
B58 #392 TrapIf(#391) [1, TrapArrayOutOfBounds] []
B58 #393 Change(#371) [SignExtend, NoAssumption, Word32, Word64] [Word64]
B58 #394 Load(#292, #393) [tagged base, Uint8, Word32, offset: 24] [Word32]
B58 #395 WordBinop(#388, #308) [Mul, Word64] [Word64]
B58 #396 Change(#394) [SignExtend, NoAssumption, Word32, Word64] [Word64]
B58 #397 WordBinop(#395, #396) [Add, Word64] [Word64]
B58 #398 Store(#98, #397) [tagged base, Int64, NoWriteBarrier, offset: 16] []
B58 #400 WordBinop(#371, #15) [Add, Word32] [Word32]
B58 #401 Store(#38, #400) [tagged base, Int32, NoWriteBarrier, offset: 16] []
B58 #402 Goto() [B53, 1] []
B59 #403 Goto() [B60, 0] []
B60 #404 Goto() [B62, 0] []
B61 #405 Goto() [B62, 0] []
B62 #406 Load(#98) [tagged base, Int64, Word64, offset: 16] [Word64]
B62 #407 Comparison(#6, #406) [UnsignedLessThan, Word64] [Word32]
B62 #408 Branch(#407) [B63, B104, None] []
B63 #410 Shift(#406, #105) [ShiftRightLogical, Word64] [Word64]
B63 #411 Load(#68) [tagged base, Int32, Word32, offset: 16] [Word32]
B63 #412 Load(#1) [tagged base, AnyTagged, Tagged, offset: 16] [Tagged]
B63 #413 Load(#412) [tagged base, Int32, Word32, offset: 16] [Word32]
B63 #414 Comparison(#411, #413) [SignedLessThan, Word32] [Word32]
B63 #415 Branch(#414) [B64, B65, None] []
B64 #417 Change(#410) [Truncate, NoAssumption, Word64, Word32] [Word32]
B64 #418 Constant() [word32: 255] [Word32]
B64 #419 Comparison(#411, #413) [UnsignedLessThan, Word32] [Word32]
B64 #420 TrapIf(#419) [1, TrapArrayOutOfBounds] []
B64 #421 Change(#411) [SignExtend, NoAssumption, Word32, Word64] [Word64]
B64 #422 Store(#412, #421, #417) [tagged base, Int8, NoWriteBarrier, offset: 24] []
B64 #424 WordBinop(#411, #15) [Add, Word32] [Word32]
B64 #425 Store(#68, #424) [tagged base, Int32, NoWriteBarrier, offset: 16] []
B64 #427 Goto() [B69, 0] []
B65 #428 Comparison(#6, #410) [UnsignedLessThan, Word64] [Word32]
B65 #429 Branch(#428) [B66, B67, None] []
B66 #431 Store(#1, #15) [tagged base, Int32, NoWriteBarrier, offset: 36] []
B66 #432 Goto() [B68, 0] []
B67 #433 Goto() [B68, 0] []
B68 #434 Goto() [B69, 0] []
B69 #435 WordBinop(#406, #285) [BitwiseAnd, Word64] [Word64]
B69 #436 Store(#98, #435) [tagged base, Int64, NoWriteBarrier, offset: 16] []
B69 #438 Constant() [word64: 10] [Word64]
B69 #439 WordBinop(#435, #438) [Mul, Word64] [Word64]
B69 #440 Store(#98, #439) [tagged base, Int64, NoWriteBarrier, offset: 16] []
B69 #441 Goto() [B70, 0] []
B70 #442 Load(#98) [tagged base, Int64, Word64, offset: 16] [Word64]
B70 #443 Comparison(#6, #442) [UnsignedLessThan, Word64] [Word32]
B70 #444 Branch(#443) [B71, B102, None] []
B71 #446 Shift(#442, #105) [ShiftRightLogical, Word64] [Word64]
B71 #447 Load(#68) [tagged base, Int32, Word32, offset: 16] [Word32]
B71 #448 Comparison(#447, #413) [SignedLessThan, Word32] [Word32]
B71 #449 Branch(#448) [B72, B73, None] []
B72 #451 Change(#446) [Truncate, NoAssumption, Word64, Word32] [Word32]
B72 #452 Constant() [word32: 255] [Word32]
B72 #453 Comparison(#447, #413) [UnsignedLessThan, Word32] [Word32]
B72 #454 TrapIf(#453) [1, TrapArrayOutOfBounds] []
B72 #455 Change(#447) [SignExtend, NoAssumption, Word32, Word64] [Word64]
B72 #456 Store(#412, #455, #451) [tagged base, Int8, NoWriteBarrier, offset: 24] []
B72 #458 WordBinop(#447, #15) [Add, Word32] [Word32]
B72 #459 Store(#68, #458) [tagged base, Int32, NoWriteBarrier, offset: 16] []
B72 #461 Goto() [B77, 0] []
B73 #462 Comparison(#6, #446) [UnsignedLessThan, Word64] [Word32]
B73 #463 Branch(#462) [B74, B75, None] []
B74 #465 Store(#1, #15) [tagged base, Int32, NoWriteBarrier, offset: 36] []
B74 #466 Goto() [B76, 0] []
B75 #467 Goto() [B76, 0] []
B76 #468 Goto() [B77, 0] []
B77 #469 WordBinop(#442, #285) [BitwiseAnd, Word64] [Word64]
B77 #470 Store(#98, #469) [tagged base, Int64, NoWriteBarrier, offset: 16] []
B77 #472 WordBinop(#469, #438) [Mul, Word64] [Word64]
B77 #473 Store(#98, #472) [tagged base, Int64, NoWriteBarrier, offset: 16] []
B77 #474 Comparison(#6, #472) [UnsignedLessThan, Word64] [Word32]
B77 #475 Branch(#474) [B79, B78, None] []
B78 #477 Goto() [B103, 0] []
B79 #478 Shift(#472, #105) [ShiftRightLogical, Word64] [Word64]
B79 #479 Load(#68) [tagged base, Int32, Word32, offset: 16] [Word32]
B79 #480 Comparison(#479, #413) [SignedLessThan, Word32] [Word32]
B79 #481 Branch(#480) [B80, B81, None] []
B80 #483 Change(#478) [Truncate, NoAssumption, Word64, Word32] [Word32]
B80 #484 Constant() [word32: 255] [Word32]
B80 #485 Comparison(#479, #413) [UnsignedLessThan, Word32] [Word32]
B80 #486 TrapIf(#485) [1, TrapArrayOutOfBounds] []
B80 #487 Change(#479) [SignExtend, NoAssumption, Word32, Word64] [Word64]
B80 #488 Store(#412, #487, #483) [tagged base, Int8, NoWriteBarrier, offset: 24] []
B80 #490 WordBinop(#479, #15) [Add, Word32] [Word32]
B80 #491 Store(#68, #490) [tagged base, Int32, NoWriteBarrier, offset: 16] []
B80 #493 Goto() [B85, 0] []
B81 #494 Comparison(#6, #478) [UnsignedLessThan, Word64] [Word32]
B81 #495 Branch(#494) [B82, B83, None] []
B82 #497 Store(#1, #15) [tagged base, Int32, NoWriteBarrier, offset: 36] []
B82 #498 Goto() [B84, 0] []
B83 #499 Goto() [B84, 0] []
B84 #500 Goto() [B85, 0] []
B85 #501 WordBinop(#472, #285) [BitwiseAnd, Word64] [Word64]
B85 #502 Store(#98, #501) [tagged base, Int64, NoWriteBarrier, offset: 16] []
B85 #504 WordBinop(#501, #438) [Mul, Word64] [Word64]
B85 #505 Store(#98, #504) [tagged base, Int64, NoWriteBarrier, offset: 16] []
B85 #506 Comparison(#6, #504) [UnsignedLessThan, Word64] [Word32]
B85 #507 Branch(#506) [B87, B86, None] []
B86 #509 Goto() [B103, 0] []
B87 #510 Shift(#504, #105) [ShiftRightLogical, Word64] [Word64]
B87 #511 Load(#68) [tagged base, Int32, Word32, offset: 16] [Word32]
B87 #512 Comparison(#511, #413) [SignedLessThan, Word32] [Word32]
B87 #513 Branch(#512) [B88, B89, None] []
B88 #515 Change(#510) [Truncate, NoAssumption, Word64, Word32] [Word32]
B88 #516 Constant() [word32: 255] [Word32]
B88 #517 Comparison(#511, #413) [UnsignedLessThan, Word32] [Word32]
B88 #518 TrapIf(#517) [1, TrapArrayOutOfBounds] []
B88 #519 Change(#511) [SignExtend, NoAssumption, Word32, Word64] [Word64]
B88 #520 Store(#412, #519, #515) [tagged base, Int8, NoWriteBarrier, offset: 24] []
B88 #522 WordBinop(#511, #15) [Add, Word32] [Word32]
B88 #523 Store(#68, #522) [tagged base, Int32, NoWriteBarrier, offset: 16] []
B88 #525 Goto() [B93, 0] []
B89 #526 Comparison(#6, #510) [UnsignedLessThan, Word64] [Word32]
B89 #527 Branch(#526) [B90, B91, None] []
B90 #529 Store(#1, #15) [tagged base, Int32, NoWriteBarrier, offset: 36] []
B90 #530 Goto() [B92, 0] []
B91 #531 Goto() [B92, 0] []
B92 #532 Goto() [B93, 0] []
B93 #533 WordBinop(#504, #285) [BitwiseAnd, Word64] [Word64]
B93 #534 Store(#98, #533) [tagged base, Int64, NoWriteBarrier, offset: 16] []
B93 #536 WordBinop(#533, #438) [Mul, Word64] [Word64]
B93 #537 Store(#98, #536) [tagged base, Int64, NoWriteBarrier, offset: 16] []
B93 #538 WasmStackCheck() [loop] []
B93 #539 Comparison(#6, #536) [UnsignedLessThan, Word64] [Word32]
B93 #540 Branch(#539) [B95, B94, None] []
B94 #542 Goto() [B103, 0] []
B95 #543 Shift(#536, #105) [ShiftRightLogical, Word64] [Word64]
B95 #544 Load(#68) [tagged base, Int32, Word32, offset: 16] [Word32]
B95 #545 Comparison(#544, #413) [SignedLessThan, Word32] [Word32]
B95 #546 Branch(#545) [B96, B97, None] []
B96 #548 Change(#543) [Truncate, NoAssumption, Word64, Word32] [Word32]
B96 #549 Constant() [word32: 255] [Word32]
B96 #550 Comparison(#544, #413) [UnsignedLessThan, Word32] [Word32]
B96 #551 TrapIf(#550) [1, TrapArrayOutOfBounds] []
B96 #552 Change(#544) [SignExtend, NoAssumption, Word32, Word64] [Word64]
B96 #553 Store(#412, #552, #548) [tagged base, Int8, NoWriteBarrier, offset: 24] []
B96 #555 WordBinop(#544, #15) [Add, Word32] [Word32]
B96 #556 Store(#68, #555) [tagged base, Int32, NoWriteBarrier, offset: 16] []
B96 #558 Goto() [B101, 0] []
B97 #559 Comparison(#6, #543) [UnsignedLessThan, Word64] [Word32]
B97 #560 Branch(#559) [B98, B99, None] []
B98 #562 Store(#1, #15) [tagged base, Int32, NoWriteBarrier, offset: 36] []
B98 #563 Goto() [B100, 0] []
B99 #564 Goto() [B100, 0] []
B100 #565 Goto() [B101, 0] []
B101 #566 WordBinop(#536, #285) [BitwiseAnd, Word64] [Word64]
B101 #567 Store(#98, #566) [tagged base, Int64, NoWriteBarrier, offset: 16] []
B101 #569 WordBinop(#566, #438) [Mul, Word64] [Word64]
B101 #570 Store(#98, #569) [tagged base, Int64, NoWriteBarrier, offset: 16] []
B101 #571 Goto() [B70, 1] []
B102 #572 Goto() [B103, 0] []
B103 #573 Goto() [B105, 0] []
B104 #574 Goto() [B105, 0] []
B105 #575 Load(#68) [tagged base, Int32, Word32, offset: 16] [Word32]
B105 #576 Store(#1, #575) [tagged base, Int32, NoWriteBarrier, offset: 24] []
B105 #578 Comparison(#5, #575) [SignedLessThan, Word32] [Word32]
B105 #579 Branch(#578) [B106, B108, None] []
B106 #581 Load(#1) [tagged base, AnyTagged, Tagged, offset: 16] [Tagged]
B106 #582 WordBinop(#575, #278) [Add, Word32] [Word32]
B106 #583 Load(#581) [tagged base, Int32, Word32, offset: 16] [Word32]
B106 #584 Comparison(#582, #583) [UnsignedLessThan, Word32] [Word32]
B106 #585 TrapIf(#584) [1, TrapArrayOutOfBounds] []
B106 #586 Change(#582) [SignExtend, NoAssumption, Word32, Word64] [Word64]
B106 #587 Load(#581, #586) [tagged base, Uint8, Word32, offset: 24] [Word32]
B106 #588 Comparison(#587, #5) [Equal, Word32] [Word32]
B106 #589 Goto() [B107, 0] []
B107 #590 Branch(#587) [B110, B111, None] []
B108 #592 Goto() [B109, 0] []
B109 #593 Goto() [B142, 0] []
B110 #594 Goto() [B142, 0] []
B111 #595 WordBinop(#575, #278) [Add, Word32] [Word32]
B111 #596 Store(#1, #595) [tagged base, Int32, NoWriteBarrier, offset: 24] []
B111 #598 Goto() [B112, 0] []
B112 #599 Load(#1) [tagged base, Int32, Word32, offset: 24] [Word32]
B112 #600 Comparison(#5, #599) [SignedLessThan, Word32] [Word32]
B112 #601 Branch(#600) [B113, B115, None] []
B113 #603 Load(#1) [tagged base, AnyTagged, Tagged, offset: 16] [Tagged]
B113 #604 WordBinop(#599, #278) [Add, Word32] [Word32]
B113 #605 Load(#603) [tagged base, Int32, Word32, offset: 16] [Word32]
B113 #606 Comparison(#604, #605) [UnsignedLessThan, Word32] [Word32]
B113 #607 TrapIf(#606) [1, TrapArrayOutOfBounds] []
B113 #608 Change(#604) [SignExtend, NoAssumption, Word32, Word64] [Word64]
B113 #609 Load(#603, #608) [tagged base, Uint8, Word32, offset: 24] [Word32]
B113 #610 Comparison(#609, #5) [Equal, Word32] [Word32]
B113 #611 Goto() [B114, 0] []
B114 #612 Branch(#609) [B117, B118, None] []
B115 #614 Goto() [B116, 0] []
B116 #615 Goto() [B140, 0] []
B117 #616 Goto() [B140, 0] []
B118 #617 WordBinop(#599, #278) [Add, Word32] [Word32]
B118 #618 Store(#1, #617) [tagged base, Int32, NoWriteBarrier, offset: 24] []
B118 #620 Comparison(#5, #617) [SignedLessThan, Word32] [Word32]
B118 #621 Branch(#620) [B119, B121, None] []
B119 #623 Load(#1) [tagged base, AnyTagged, Tagged, offset: 16] [Tagged]
B119 #624 WordBinop(#617, #278) [Add, Word32] [Word32]
B119 #625 Load(#623) [tagged base, Int32, Word32, offset: 16] [Word32]
B119 #626 Comparison(#624, #625) [UnsignedLessThan, Word32] [Word32]
B119 #627 TrapIf(#626) [1, TrapArrayOutOfBounds] []
B119 #628 Change(#624) [SignExtend, NoAssumption, Word32, Word64] [Word64]
B119 #629 Load(#623, #628) [tagged base, Uint8, Word32, offset: 24] [Word32]
B119 #630 Comparison(#629, #5) [Equal, Word32] [Word32]
B119 #631 Goto() [B120, 0] []
B120 #632 Branch(#629) [B123, B125, None] []
B121 #634 Goto() [B122, 0] []
B122 #635 Goto() [B124, 0] []
B123 #636 Goto() [B124, 0] []
B124 #637 Phi(#630, #5) [Word32] [Word32]
B124 #638 Goto() [B141, 0] []
B125 #639 WordBinop(#617, #278) [Add, Word32] [Word32]
B125 #640 Store(#1, #639) [tagged base, Int32, NoWriteBarrier, offset: 24] []
B125 #642 Comparison(#5, #639) [SignedLessThan, Word32] [Word32]
B125 #643 Branch(#642) [B126, B128, None] []
B126 #645 Load(#1) [tagged base, AnyTagged, Tagged, offset: 16] [Tagged]
B126 #646 WordBinop(#639, #278) [Add, Word32] [Word32]
B126 #647 Load(#645) [tagged base, Int32, Word32, offset: 16] [Word32]
B126 #648 Comparison(#646, #647) [UnsignedLessThan, Word32] [Word32]
B126 #649 TrapIf(#648) [1, TrapArrayOutOfBounds] []
B126 #650 Change(#646) [SignExtend, NoAssumption, Word32, Word64] [Word64]
B126 #651 Load(#645, #650) [tagged base, Uint8, Word32, offset: 24] [Word32]
B126 #652 Comparison(#651, #5) [Equal, Word32] [Word32]
B126 #653 Goto() [B127, 0] []
B127 #654 Branch(#651) [B130, B132, None] []
B128 #656 Goto() [B129, 0] []
B129 #657 Goto() [B131, 0] []
B130 #658 Goto() [B131, 0] []
B131 #659 Phi(#652, #5) [Word32] [Word32]
B131 #660 Goto() [B141, 0] []
B132 #661 WordBinop(#639, #278) [Add, Word32] [Word32]
B132 #662 Store(#1, #661) [tagged base, Int32, NoWriteBarrier, offset: 24] []
B132 #664 WasmStackCheck() [loop] []
B132 #665 Comparison(#5, #661) [SignedLessThan, Word32] [Word32]
B132 #666 Branch(#665) [B133, B135, None] []
B133 #668 Load(#1) [tagged base, AnyTagged, Tagged, offset: 16] [Tagged]
B133 #669 WordBinop(#661, #278) [Add, Word32] [Word32]
B133 #670 Load(#668) [tagged base, Int32, Word32, offset: 16] [Word32]
B133 #671 Comparison(#669, #670) [UnsignedLessThan, Word32] [Word32]
B133 #672 TrapIf(#671) [1, TrapArrayOutOfBounds] []
B133 #673 Change(#669) [SignExtend, NoAssumption, Word32, Word64] [Word64]
B133 #674 Load(#668, #673) [tagged base, Uint8, Word32, offset: 24] [Word32]
B133 #675 Comparison(#674, #5) [Equal, Word32] [Word32]
B133 #676 Goto() [B134, 0] []
B134 #677 Branch(#674) [B137, B139, None] []
B135 #679 Goto() [B136, 0] []
B136 #680 Goto() [B138, 0] []
B137 #681 Goto() [B138, 0] []
B138 #682 Phi(#675, #5) [Word32] [Word32]
B138 #683 Goto() [B141, 0] []
B139 #684 WordBinop(#661, #278) [Add, Word32] [Word32]
B139 #685 Store(#1, #684) [tagged base, Int32, NoWriteBarrier, offset: 24] []
B139 #687 Goto() [B112, 1] []
B140 #688 Phi(#610, #5) [Word32] [Word32]
B140 #689 Goto() [B141, 0] []
B141 #690 Phi(#610, #610, #610, #688) [Word32] [Word32]
B141 #691 Goto() [B143, 0] []
B142 #692 Phi(#588, #5) [Word32] [Word32]
B142 #693 Goto() [B143, 0] []
B143 #694 Phi(#588, #692) [Word32] [Word32]
B143 #695 Load(#1) [tagged base, Int32, Word32, offset: 24] [Word32]
B143 #696 Branch(#695) [B145, B144, None] []
B144 #698 Store(#1, #5) [tagged base, Int32, NoWriteBarrier, offset: 28] []
B144 #700 Return(#5, #5) [0] []
B145 #701 Return(#5, #5) [0] []
```

### V8 inlined guest functions

1255, 461, 688, 755

### V8 ARM64 machine code

```asm
0x8f1eec000     0  d2800110       movz x16, #0x8
0x8f1eec004     4  a9be43e7       stp x7, x16, [sp, #-32]!
0x8f1eec008     8  a9017bfd       stp fp, lr, [sp, #16]
0x8f1eec00c     c  910043fd       add fp, sp, #0x10 (16)
0x8f1eec010    10  d10183ff       sub sp, sp, #0x60 (96)
0x8f1eec014    14  f84ef0e3       ldur x3, [x7, #239]
0x8f1eec018    18  f8520344       ldur x4, [x26, #-224]
0x8f1eec01c    1c  eb2463ff       cmp sp, x4
0x8f1eec020    20  540037c9       b.ls #+0x6f8 (addr 0x8f1eec718)
0x8f1eec024    24  d28130e4       movz x4, #0x987
0x8f1eec028    28  f8646864       ldr x4, [x3, x4]
0x8f1eec02c    2c  f84470e5       ldur x5, [x7, #71]
0x8f1eec030    30  f94000a6       ldr x6, [x5]
0x8f1eec034    34  f843f0e8       ldur x8, [x7, #63]
0x8f1eec038    38  f9400108       ldr x8, [x8]
0x8f1eec03c    3c  910060c9       add x9, x6, #0x18 (24)
0x8f1eec040    40  eb08013f       cmp x9, x8
0x8f1eec044    44  540037c2       b.hs #+0x6f8 (addr 0x8f1eec73c)
0x8f1eec048    48  910060c8       add x8, x6, #0x18 (24)
0x8f1eec04c    4c  f90000a8       str x8, [x5]
0x8f1eec050    50  910004c5       add x5, x6, #0x1 (1)
0x8f1eec054    54  f81ff0a4       stur x4, [x5, #-1]
0x8f1eec058    58  f9413346       ldr x6, [x26, #608]
0x8f1eec05c    5c  f80070a6       stur x6, [x5, #7]
0x8f1eec060    60  b800f0bf       stur wzr, [x5, #15]
0x8f1eec064    64  f84470e6       ldur x6, [x7, #71]
0x8f1eec068    68  f94000c8       ldr x8, [x6]
0x8f1eec06c    6c  f843f0e9       ldur x9, [x7, #63]
0x8f1eec070    70  f9400129       ldr x9, [x9]
0x8f1eec074    74  9100610a       add x10, x8, #0x18 (24)
0x8f1eec078    78  eb09015f       cmp x10, x9
0x8f1eec07c    7c  540038a2       b.hs #+0x714 (addr 0x8f1eec790)
0x8f1eec080    80  91006109       add x9, x8, #0x18 (24)
0x8f1eec084    84  f90000c9       str x9, [x6]
0x8f1eec088    88  91000506       add x6, x8, #0x1 (1)
0x8f1eec08c    8c  f81ff0c4       stur x4, [x6, #-1]
0x8f1eec090    90  f9413344       ldr x4, [x26, #608]
0x8f1eec094    94  f80070c4       stur x4, [x6, #7]
0x8f1eec098    98  b800f0df       stur wzr, [x6, #15]
0x8f1eec09c    9c  d282aae4       movz x4, #0x1557
0x8f1eec0a0    a0  f8646863       ldr x3, [x3, x4]
0x8f1eec0a4    a4  f84470e4       ldur x4, [x7, #71]
0x8f1eec0a8    a8  f9400088       ldr x8, [x4]
0x8f1eec0ac    ac  f843f0e7       ldur x7, [x7, #63]
0x8f1eec0b0    b0  f94000e7       ldr x7, [x7]
0x8f1eec0b4    b4  91006109       add x9, x8, #0x18 (24)
0x8f1eec0b8    b8  eb07013f       cmp x9, x7
0x8f1eec0bc    bc  54003962       b.hs #+0x72c (addr 0x8f1eec7e8)
0x8f1eec0c0    c0  91006107       add x7, x8, #0x18 (24)
0x8f1eec0c4    c4  f9000087       str x7, [x4]
0x8f1eec0c8    c8  91000504       add x4, x8, #0x1 (1)
0x8f1eec0cc    cc  f81ff083       stur x3, [x4, #-1]
0x8f1eec0d0    d0  f9413343       ldr x3, [x26, #608]
0x8f1eec0d4    d4  f8007083       stur x3, [x4, #7]
0x8f1eec0d8    d8  f800f09f       stur xzr, [x4, #15]
0x8f1eec0dc    dc  12001403       and w3, w0, #0x3f
0x8f1eec0e0    e0  d2800007       movz x7, #0x0
0x8f1eec0e4    e4  9ac324e7       lsr x7, x7, x3
0x8f1eec0e8    e8  b4000067       cbz x7, #+0xc (addr 0x8f1eec0f4)
0x8f1eec0ec    ec  d280002a       movz x10, #0x1
0x8f1eec0f0    f0  14000070       b #+0x1c0 (addr 0x8f1eec2b0)
0x8f1eec0f4    f4  b8417047       ldur w7, [x2, #23]
0x8f1eec0f8    f8  710000ff       cmp w7, #0x0 (0)
0x8f1eec0fc    fc  540008ad       b.le #+0x114 (addr 0x8f1eec210)
0x8f1eec100   100  f840f048       ldur x8, [x2, #15]
0x8f1eec104   104  b840f109       ldur w9, [x8, #15]
0x8f1eec108   108  7100013f       cmp w9, #0x0 (0)
0x8f1eec10c   10c  54004849       b.ls #+0x908 (addr 0x8f1eeca14)
0x8f1eec110   110  39405d0a       ldrb w10, [x8, #23]
0x8f1eec114   114  f800f08a       stur x10, [x4, #15]
0x8f1eec118   118  d280002a       movz x10, #0x1
0x8f1eec11c   11c  b800f0aa       stur w10, [x5, #15]
0x8f1eec120   120  d280014b       movz x11, #0xa
0x8f1eec124   124  1400000a       b #+0x28 (addr 0x8f1eec14c)
0x8f1eec128   128  6b0901bf       cmp w13, w9
0x8f1eec12c   12c  54004722       b.hs #+0x8e4 (addr 0x8f1eeca10)
0x8f1eec130   130  93407dae       sxtw x14, w13
0x8f1eec134   134  91005dce       add x14, x14, #0x17 (23)
0x8f1eec138   138  386e690e       ldrb w14, [x8, x14]
0x8f1eec13c   13c  9b0b398c       madd x12, x12, x11, x14
0x8f1eec140   140  f800f08c       stur x12, [x4, #15]
0x8f1eec144   144  110005ac       add w12, w13, #0x1 (1)
0x8f1eec148   148  b800f0ac       stur w12, [x5, #15]
0x8f1eec14c   14c  f840f08c       ldur x12, [x4, #15]
0x8f1eec150   150  9ac3258d       lsr x13, x12, x3
0x8f1eec154   154  b5000aed       cbnz x13, #+0x15c (addr 0x8f1eec2b0)
0x8f1eec158   158  b840f0ad       ldur w13, [x5, #15]
0x8f1eec15c   15c  6b0d00ff       cmp w7, w13
0x8f1eec160   160  540005ad       b.le #+0xb4 (addr 0x8f1eec214)
0x8f1eec164   164  6b0901bf       cmp w13, w9
0x8f1eec168   168  54004522       b.hs #+0x8a4 (addr 0x8f1eeca0c)
0x8f1eec16c   16c  93407dae       sxtw x14, w13
0x8f1eec170   170  91005dce       add x14, x14, #0x17 (23)
0x8f1eec174   174  386e690e       ldrb w14, [x8, x14]
0x8f1eec178   178  9b0b398c       madd x12, x12, x11, x14
0x8f1eec17c   17c  f800f08c       stur x12, [x4, #15]
0x8f1eec180   180  110005ad       add w13, w13, #0x1 (1)
0x8f1eec184   184  b800f0ad       stur w13, [x5, #15]
0x8f1eec188   188  9ac3258e       lsr x14, x12, x3
0x8f1eec18c   18c  b500092e       cbnz x14, #+0x124 (addr 0x8f1eec2b0)
0x8f1eec190   190  6b0d00ff       cmp w7, w13
0x8f1eec194   194  5400040d       b.le #+0x80 (addr 0x8f1eec214)
0x8f1eec198   198  6b0901bf       cmp w13, w9
0x8f1eec19c   19c  54004362       b.hs #+0x86c (addr 0x8f1eeca08)
0x8f1eec1a0   1a0  93407dae       sxtw x14, w13
0x8f1eec1a4   1a4  91005dce       add x14, x14, #0x17 (23)
0x8f1eec1a8   1a8  386e690e       ldrb w14, [x8, x14]
0x8f1eec1ac   1ac  9b0b398c       madd x12, x12, x11, x14
0x8f1eec1b0   1b0  f800f08c       stur x12, [x4, #15]
0x8f1eec1b4   1b4  110005ad       add w13, w13, #0x1 (1)
0x8f1eec1b8   1b8  b800f0ad       stur w13, [x5, #15]
0x8f1eec1bc   1bc  9ac3258e       lsr x14, x12, x3
0x8f1eec1c0   1c0  b500078e       cbnz x14, #+0xf0 (addr 0x8f1eec2b0)
0x8f1eec1c4   1c4  6b0d00ff       cmp w7, w13
0x8f1eec1c8   1c8  5400026d       b.le #+0x4c (addr 0x8f1eec214)
0x8f1eec1cc   1cc  6b0901bf       cmp w13, w9
0x8f1eec1d0   1d0  540041a2       b.hs #+0x834 (addr 0x8f1eeca04)
0x8f1eec1d4   1d4  93407dae       sxtw x14, w13
0x8f1eec1d8   1d8  91005dce       add x14, x14, #0x17 (23)
0x8f1eec1dc   1dc  386e690e       ldrb w14, [x8, x14]
0x8f1eec1e0   1e0  9b0b398c       madd x12, x12, x11, x14
0x8f1eec1e4   1e4  f800f08c       stur x12, [x4, #15]
0x8f1eec1e8   1e8  110005ad       add w13, w13, #0x1 (1)
0x8f1eec1ec   1ec  b800f0ad       stur w13, [x5, #15]
0x8f1eec1f0   1f0  f852034e       ldur x14, [x26, #-224]
0x8f1eec1f4   1f4  eb2e63ff       cmp sp, x14
0x8f1eec1f8   1f8  54003229       b.ls #+0x644 (addr 0x8f1eec83c)
0x8f1eec1fc   1fc  9ac3258e       lsr x14, x12, x3
0x8f1eec200   200  b500058e       cbnz x14, #+0xb0 (addr 0x8f1eec2b0)
0x8f1eec204   204  6b0d00ff       cmp w7, w13
0x8f1eec208   208  54fff90c       b.gt #-0xe0 (addr 0x8f1eec128)
0x8f1eec20c   20c  14000002       b #+0x8 (addr 0x8f1eec214)
0x8f1eec210   210  d280002a       movz x10, #0x1
0x8f1eec214   214  f840f087       ldur x7, [x4, #15]
0x8f1eec218   218  9ac324e8       lsr x8, x7, x3
0x8f1eec21c   21c  b50004a8       cbnz x8, #+0x94 (addr 0x8f1eec2b0)
0x8f1eec220   220  d2800148       movz x8, #0xa
0x8f1eec224   224  9b087ce7       mul x7, x7, x8
0x8f1eec228   228  f800f087       stur x7, [x4, #15]
0x8f1eec22c   22c  b840f0a7       ldur w7, [x5, #15]
0x8f1eec230   230  110004e7       add w7, w7, #0x1 (1)
0x8f1eec234   234  b800f0a7       stur w7, [x5, #15]
0x8f1eec238   238  14000005       b #+0x14 (addr 0x8f1eec24c)
0x8f1eec23c   23c  9b087ce7       mul x7, x7, x8
0x8f1eec240   240  f800f087       stur x7, [x4, #15]
0x8f1eec244   244  11000527       add w7, w9, #0x1 (1)
0x8f1eec248   248  b800f0a7       stur w7, [x5, #15]
0x8f1eec24c   24c  f840f087       ldur x7, [x4, #15]
0x8f1eec250   250  9ac324e9       lsr x9, x7, x3
0x8f1eec254   254  b50002e9       cbnz x9, #+0x5c (addr 0x8f1eec2b0)
0x8f1eec258   258  9b087ce7       mul x7, x7, x8
0x8f1eec25c   25c  f800f087       stur x7, [x4, #15]
0x8f1eec260   260  b840f0a9       ldur w9, [x5, #15]
0x8f1eec264   264  11000529       add w9, w9, #0x1 (1)
0x8f1eec268   268  b800f0a9       stur w9, [x5, #15]
0x8f1eec26c   26c  9ac324eb       lsr x11, x7, x3
0x8f1eec270   270  b500020b       cbnz x11, #+0x40 (addr 0x8f1eec2b0)
0x8f1eec274   274  9b087ce7       mul x7, x7, x8
0x8f1eec278   278  f800f087       stur x7, [x4, #15]
0x8f1eec27c   27c  11000529       add w9, w9, #0x1 (1)
0x8f1eec280   280  b800f0a9       stur w9, [x5, #15]
0x8f1eec284   284  9ac324eb       lsr x11, x7, x3
0x8f1eec288   288  b500014b       cbnz x11, #+0x28 (addr 0x8f1eec2b0)
0x8f1eec28c   28c  9b087ce7       mul x7, x7, x8
0x8f1eec290   290  f800f087       stur x7, [x4, #15]
0x8f1eec294   294  11000529       add w9, w9, #0x1 (1)
0x8f1eec298   298  b800f0a9       stur w9, [x5, #15]
0x8f1eec29c   29c  f852034b       ldur x11, [x26, #-224]
0x8f1eec2a0   2a0  eb2b63ff       cmp sp, x11
0x8f1eec2a4   2a4  54002fc9       b.ls #+0x5f8 (addr 0x8f1eec89c)
0x8f1eec2a8   2a8  9ac324eb       lsr x11, x7, x3
0x8f1eec2ac   2ac  b4fffc8b       cbz x11, #-0x70 (addr 0x8f1eec23c)
0x8f1eec2b0   2b0  b841b047       ldur w7, [x2, #27]
0x8f1eec2b4   2b4  b840f0a8       ldur w8, [x5, #15]
0x8f1eec2b8   2b8  51000509       sub w9, w8, #0x1 (1)
0x8f1eec2bc   2bc  4b0900e7       sub w7, w7, w9
0x8f1eec2c0   2c0  b801b047       stur w7, [x2, #27]
0x8f1eec2c4   2c4  d2800027       movz x7, #0x1
0x8f1eec2c8   2c8  9ac320e7       lsl x7, x7, x3
0x8f1eec2cc   2cc  d10004e7       sub x7, x7, #0x1 (1)
0x8f1eec2d0   2d0  b8417049       ldur w9, [x2, #23]
0x8f1eec2d4   2d4  6b09011f       cmp w8, w9
0x8f1eec2d8   2d8  54000b6a       b.ge #+0x16c (addr 0x8f1eec444)
0x8f1eec2dc   2dc  f840f08b       ldur x11, [x4, #15]
0x8f1eec2e0   2e0  9ac3256c       lsr x12, x11, x3
0x8f1eec2e4   2e4  f840f04d       ldur x13, [x2, #15]
0x8f1eec2e8   2e8  b840f1ae       ldur w14, [x13, #15]
0x8f1eec2ec   2ec  710001df       cmp w14, #0x0 (0)
0x8f1eec2f0   2f0  54003889       b.ls #+0x710 (addr 0x8f1eeca00)
0x8f1eec2f4   2f4  39005dac       strb w12, [x13, #23]
0x8f1eec2f8   2f8  b800f0ca       stur w10, [x6, #15]
0x8f1eec2fc   2fc  8a07016b       and x11, x11, x7
0x8f1eec300   300  f800f08b       stur x11, [x4, #15]
0x8f1eec304   304  6b0e011f       cmp w8, w14
0x8f1eec308   308  540037a2       b.hs #+0x6f4 (addr 0x8f1eec9fc)
0x8f1eec30c   30c  93407d0c       sxtw x12, w8
0x8f1eec310   310  91005d8c       add x12, x12, #0x17 (23)
0x8f1eec314   314  386c69ac       ldrb w12, [x13, x12]
0x8f1eec318   318  d280014f       movz x15, #0xa
0x8f1eec31c   31c  9b0f316b       madd x11, x11, x15, x12
0x8f1eec320   320  f800f08b       stur x11, [x4, #15]
0x8f1eec324   324  11000508       add w8, w8, #0x1 (1)
0x8f1eec328   328  b800f0a8       stur w8, [x5, #15]
0x8f1eec32c   32c  14000014       b #+0x50 (addr 0x8f1eec37c)
0x8f1eec330   330  9ac32573       lsr x19, x11, x3
0x8f1eec334   334  6b0e019f       cmp w12, w14
0x8f1eec338   338  54003602       b.hs #+0x6c0 (addr 0x8f1eec9f8)
0x8f1eec33c   33c  93407d94       sxtw x20, w12
0x8f1eec340   340  91005e94       add x20, x20, #0x17 (23)
0x8f1eec344   344  383469b3       strb w19, [x13, x20]
0x8f1eec348   348  1100058c       add w12, w12, #0x1 (1)
0x8f1eec34c   34c  b800f0cc       stur w12, [x6, #15]
0x8f1eec350   350  8a07016b       and x11, x11, x7
0x8f1eec354   354  f800f08b       stur x11, [x4, #15]
0x8f1eec358   358  6b0e011f       cmp w8, w14
0x8f1eec35c   35c  540034c2       b.hs #+0x698 (addr 0x8f1eec9f4)
0x8f1eec360   360  93407d0c       sxtw x12, w8
0x8f1eec364   364  91005d8c       add x12, x12, #0x17 (23)
0x8f1eec368   368  386c69ac       ldrb w12, [x13, x12]
0x8f1eec36c   36c  9b0f316b       madd x11, x11, x15, x12
0x8f1eec370   370  f800f08b       stur x11, [x4, #15]
0x8f1eec374   374  11000508       add w8, w8, #0x1 (1)
0x8f1eec378   378  b800f0a8       stur w8, [x5, #15]
0x8f1eec37c   37c  b840f0a8       ldur w8, [x5, #15]
0x8f1eec380   380  6b09011f       cmp w8, w9
0x8f1eec384   384  5400060a       b.ge #+0xc0 (addr 0x8f1eec444)
0x8f1eec388   388  f840f08b       ldur x11, [x4, #15]
0x8f1eec38c   38c  9ac3256c       lsr x12, x11, x3
0x8f1eec390   390  b840f0d3       ldur w19, [x6, #15]
0x8f1eec394   394  6b0e027f       cmp w19, w14
0x8f1eec398   398  540032c2       b.hs #+0x658 (addr 0x8f1eec9f0)
0x8f1eec39c   39c  93407e74       sxtw x20, w19
0x8f1eec3a0   3a0  91005e94       add x20, x20, #0x17 (23)
0x8f1eec3a4   3a4  383469ac       strb w12, [x13, x20]
0x8f1eec3a8   3a8  1100066c       add w12, w19, #0x1 (1)
0x8f1eec3ac   3ac  b800f0cc       stur w12, [x6, #15]
0x8f1eec3b0   3b0  8a07016b       and x11, x11, x7
0x8f1eec3b4   3b4  f800f08b       stur x11, [x4, #15]
0x8f1eec3b8   3b8  6b0e011f       cmp w8, w14
0x8f1eec3bc   3bc  54003182       b.hs #+0x630 (addr 0x8f1eec9ec)
0x8f1eec3c0   3c0  93407d13       sxtw x19, w8
0x8f1eec3c4   3c4  91005e73       add x19, x19, #0x17 (23)
0x8f1eec3c8   3c8  387369b3       ldrb w19, [x13, x19]
0x8f1eec3cc   3cc  9b0f4d6b       madd x11, x11, x15, x19
0x8f1eec3d0   3d0  f800f08b       stur x11, [x4, #15]
0x8f1eec3d4   3d4  11000508       add w8, w8, #0x1 (1)
0x8f1eec3d8   3d8  b800f0a8       stur w8, [x5, #15]
0x8f1eec3dc   3dc  6b09011f       cmp w8, w9
0x8f1eec3e0   3e0  5400032a       b.ge #+0x64 (addr 0x8f1eec444)
0x8f1eec3e4   3e4  9ac32573       lsr x19, x11, x3
0x8f1eec3e8   3e8  6b0e019f       cmp w12, w14
0x8f1eec3ec   3ec  54002fe2       b.hs #+0x5fc (addr 0x8f1eec9e8)
0x8f1eec3f0   3f0  93407d94       sxtw x20, w12
0x8f1eec3f4   3f4  91005e94       add x20, x20, #0x17 (23)
0x8f1eec3f8   3f8  383469b3       strb w19, [x13, x20]
0x8f1eec3fc   3fc  1100058c       add w12, w12, #0x1 (1)
0x8f1eec400   400  b800f0cc       stur w12, [x6, #15]
0x8f1eec404   404  8a07016b       and x11, x11, x7
0x8f1eec408   408  f800f08b       stur x11, [x4, #15]
0x8f1eec40c   40c  6b0e011f       cmp w8, w14
0x8f1eec410   410  54002ea2       b.hs #+0x5d4 (addr 0x8f1eec9e4)
0x8f1eec414   414  93407d13       sxtw x19, w8
0x8f1eec418   418  91005e73       add x19, x19, #0x17 (23)
0x8f1eec41c   41c  387369b3       ldrb w19, [x13, x19]
0x8f1eec420   420  9b0f4d6b       madd x11, x11, x15, x19
0x8f1eec424   424  f800f08b       stur x11, [x4, #15]
0x8f1eec428   428  11000508       add w8, w8, #0x1 (1)
0x8f1eec42c   42c  b800f0a8       stur w8, [x5, #15]
0x8f1eec430   430  f8520353       ldur x19, [x26, #-224]
0x8f1eec434   434  eb3363ff       cmp sp, x19
0x8f1eec438   438  54002569       b.ls #+0x4ac (addr 0x8f1eec8e4)
0x8f1eec43c   43c  6b09011f       cmp w8, w9
0x8f1eec440   440  54fff78b       b.lt #-0x110 (addr 0x8f1eec330)
0x8f1eec444   444  f840f085       ldur x5, [x4, #15]
0x8f1eec448   448  b4000d05       cbz x5, #+0x1a0 (addr 0x8f1eec5e8)
0x8f1eec44c   44c  9ac324a8       lsr x8, x5, x3
0x8f1eec450   450  b840f0c9       ldur w9, [x6, #15]
0x8f1eec454   454  f840f04b       ldur x11, [x2, #15]
0x8f1eec458   458  b840f16c       ldur w12, [x11, #15]
0x8f1eec45c   45c  6b0c013f       cmp w9, w12
0x8f1eec460   460  5400008b       b.lt #+0x10 (addr 0x8f1eec470)
0x8f1eec464   464  b4000148       cbz x8, #+0x28 (addr 0x8f1eec48c)
0x8f1eec468   468  b802304a       stur w10, [x2, #35]
0x8f1eec46c   46c  14000008       b #+0x20 (addr 0x8f1eec48c)
0x8f1eec470   470  6b0c013f       cmp w9, w12
0x8f1eec474   474  54002b62       b.hs #+0x56c (addr 0x8f1eec9e0)
0x8f1eec478   478  93407d2d       sxtw x13, w9
0x8f1eec47c   47c  91005dad       add x13, x13, #0x17 (23)
0x8f1eec480   480  382d6968       strb w8, [x11, x13]
0x8f1eec484   484  11000528       add w8, w9, #0x1 (1)
0x8f1eec488   488  b800f0c8       stur w8, [x6, #15]
0x8f1eec48c   48c  8a0700a5       and x5, x5, x7
0x8f1eec490   490  f800f085       stur x5, [x4, #15]
0x8f1eec494   494  d2800148       movz x8, #0xa
0x8f1eec498   498  9b087ca5       mul x5, x5, x8
0x8f1eec49c   49c  f800f085       stur x5, [x4, #15]
0x8f1eec4a0   4a0  14000005       b #+0x14 (addr 0x8f1eec4b4)
0x8f1eec4a4   4a4  8a0700a5       and x5, x5, x7
0x8f1eec4a8   4a8  f800f085       stur x5, [x4, #15]
0x8f1eec4ac   4ac  9b087ca5       mul x5, x5, x8
0x8f1eec4b0   4b0  f800f085       stur x5, [x4, #15]
0x8f1eec4b4   4b4  f840f085       ldur x5, [x4, #15]
0x8f1eec4b8   4b8  b4000985       cbz x5, #+0x130 (addr 0x8f1eec5e8)
0x8f1eec4bc   4bc  9ac324a9       lsr x9, x5, x3
0x8f1eec4c0   4c0  b840f0cd       ldur w13, [x6, #15]
0x8f1eec4c4   4c4  6b0c01bf       cmp w13, w12
0x8f1eec4c8   4c8  5400008b       b.lt #+0x10 (addr 0x8f1eec4d8)
0x8f1eec4cc   4cc  b4000149       cbz x9, #+0x28 (addr 0x8f1eec4f4)
0x8f1eec4d0   4d0  b802304a       stur w10, [x2, #35]
0x8f1eec4d4   4d4  14000008       b #+0x20 (addr 0x8f1eec4f4)
0x8f1eec4d8   4d8  6b0c01bf       cmp w13, w12
0x8f1eec4dc   4dc  54002802       b.hs #+0x500 (addr 0x8f1eec9dc)
0x8f1eec4e0   4e0  93407dae       sxtw x14, w13
0x8f1eec4e4   4e4  91005dce       add x14, x14, #0x17 (23)
0x8f1eec4e8   4e8  382e6969       strb w9, [x11, x14]
0x8f1eec4ec   4ec  110005a9       add w9, w13, #0x1 (1)
0x8f1eec4f0   4f0  b800f0c9       stur w9, [x6, #15]
0x8f1eec4f4   4f4  8a0700a5       and x5, x5, x7
0x8f1eec4f8   4f8  f800f085       stur x5, [x4, #15]
0x8f1eec4fc   4fc  9b087ca5       mul x5, x5, x8
0x8f1eec500   500  f800f085       stur x5, [x4, #15]
0x8f1eec504   504  b4000725       cbz x5, #+0xe4 (addr 0x8f1eec5e8)
0x8f1eec508   508  9ac324a9       lsr x9, x5, x3
0x8f1eec50c   50c  b840f0cd       ldur w13, [x6, #15]
0x8f1eec510   510  6b0c01bf       cmp w13, w12
0x8f1eec514   514  5400008b       b.lt #+0x10 (addr 0x8f1eec524)
0x8f1eec518   518  b4000149       cbz x9, #+0x28 (addr 0x8f1eec540)
0x8f1eec51c   51c  b802304a       stur w10, [x2, #35]
0x8f1eec520   520  14000008       b #+0x20 (addr 0x8f1eec540)
0x8f1eec524   524  6b0c01bf       cmp w13, w12
0x8f1eec528   528  54002582       b.hs #+0x4b0 (addr 0x8f1eec9d8)
0x8f1eec52c   52c  93407dae       sxtw x14, w13
0x8f1eec530   530  91005dce       add x14, x14, #0x17 (23)
0x8f1eec534   534  382e6969       strb w9, [x11, x14]
0x8f1eec538   538  110005a9       add w9, w13, #0x1 (1)
0x8f1eec53c   53c  b800f0c9       stur w9, [x6, #15]
0x8f1eec540   540  8a0700a5       and x5, x5, x7
0x8f1eec544   544  f800f085       stur x5, [x4, #15]
0x8f1eec548   548  9b087ca5       mul x5, x5, x8
0x8f1eec54c   54c  f800f085       stur x5, [x4, #15]
0x8f1eec550   550  b40004c5       cbz x5, #+0x98 (addr 0x8f1eec5e8)
0x8f1eec554   554  9ac324a9       lsr x9, x5, x3
0x8f1eec558   558  b840f0cd       ldur w13, [x6, #15]
0x8f1eec55c   55c  6b0c01bf       cmp w13, w12
0x8f1eec560   560  5400008b       b.lt #+0x10 (addr 0x8f1eec570)
0x8f1eec564   564  b4000149       cbz x9, #+0x28 (addr 0x8f1eec58c)
0x8f1eec568   568  b802304a       stur w10, [x2, #35]
0x8f1eec56c   56c  14000008       b #+0x20 (addr 0x8f1eec58c)
0x8f1eec570   570  6b0c01bf       cmp w13, w12
0x8f1eec574   574  54002302       b.hs #+0x460 (addr 0x8f1eec9d4)
0x8f1eec578   578  93407dae       sxtw x14, w13
0x8f1eec57c   57c  91005dce       add x14, x14, #0x17 (23)
0x8f1eec580   580  382e6969       strb w9, [x11, x14]
0x8f1eec584   584  110005a9       add w9, w13, #0x1 (1)
0x8f1eec588   588  b800f0c9       stur w9, [x6, #15]
0x8f1eec58c   58c  8a0700a5       and x5, x5, x7
0x8f1eec590   590  f800f085       stur x5, [x4, #15]
0x8f1eec594   594  9b087ca5       mul x5, x5, x8
0x8f1eec598   598  f800f085       stur x5, [x4, #15]
0x8f1eec59c   59c  f8520349       ldur x9, [x26, #-224]
0x8f1eec5a0   5a0  eb2963ff       cmp sp, x9
0x8f1eec5a4   5a4  54001d89       b.ls #+0x3b0 (addr 0x8f1eec954)
0x8f1eec5a8   5a8  b4000205       cbz x5, #+0x40 (addr 0x8f1eec5e8)
0x8f1eec5ac   5ac  9ac324a9       lsr x9, x5, x3
0x8f1eec5b0   5b0  b840f0cd       ldur w13, [x6, #15]
0x8f1eec5b4   5b4  6b0c01bf       cmp w13, w12
0x8f1eec5b8   5b8  5400008b       b.lt #+0x10 (addr 0x8f1eec5c8)
0x8f1eec5bc   5bc  b4fff749       cbz x9, #-0x118 (addr 0x8f1eec4a4)
0x8f1eec5c0   5c0  b802304a       stur w10, [x2, #35]
0x8f1eec5c4   5c4  17ffffb8       b #-0x120 (addr 0x8f1eec4a4)
0x8f1eec5c8   5c8  6b0c01bf       cmp w13, w12
0x8f1eec5cc   5cc  54002022       b.hs #+0x404 (addr 0x8f1eec9d0)
0x8f1eec5d0   5d0  93407dae       sxtw x14, w13
0x8f1eec5d4   5d4  91005dce       add x14, x14, #0x17 (23)
0x8f1eec5d8   5d8  382e6969       strb w9, [x11, x14]
0x8f1eec5dc   5dc  110005a9       add w9, w13, #0x1 (1)
0x8f1eec5e0   5e0  b800f0c9       stur w9, [x6, #15]
0x8f1eec5e4   5e4  17ffffb0       b #-0x140 (addr 0x8f1eec4a4)
0x8f1eec5e8   5e8  b840f0c3       ldur w3, [x6, #15]
0x8f1eec5ec   5ec  b8017043       stur w3, [x2, #23]
0x8f1eec5f0   5f0  7100007f       cmp w3, #0x0 (0)
0x8f1eec5f4   5f4  5400080d       b.le #+0x100 (addr 0x8f1eec6f4)
0x8f1eec5f8   5f8  f840f044       ldur x4, [x2, #15]
0x8f1eec5fc   5fc  51000463       sub w3, w3, #0x1 (1)
0x8f1eec600   600  b840f085       ldur w5, [x4, #15]
0x8f1eec604   604  6b05007f       cmp w3, w5
0x8f1eec608   608  54001e22       b.hs #+0x3c4 (addr 0x8f1eec9cc)
0x8f1eec60c   60c  93407c65       sxtw x5, w3
0x8f1eec610   610  91005ca5       add x5, x5, #0x17 (23)
0x8f1eec614   614  38656884       ldrb w4, [x4, x5]
0x8f1eec618   618  350006e4       cbnz w4, #+0xdc (addr 0x8f1eec6f4)
0x8f1eec61c   61c  b8017043       stur w3, [x2, #23]
0x8f1eec620   620  14000002       b #+0x8 (addr 0x8f1eec628)
0x8f1eec624   624  b8017043       stur w3, [x2, #23]
0x8f1eec628   628  b8417043       ldur w3, [x2, #23]
0x8f1eec62c   62c  7100007f       cmp w3, #0x0 (0)
0x8f1eec630   630  5400062d       b.le #+0xc4 (addr 0x8f1eec6f4)
0x8f1eec634   634  f840f044       ldur x4, [x2, #15]
0x8f1eec638   638  51000463       sub w3, w3, #0x1 (1)
0x8f1eec63c   63c  b840f085       ldur w5, [x4, #15]
0x8f1eec640   640  6b05007f       cmp w3, w5
0x8f1eec644   644  54001c22       b.hs #+0x384 (addr 0x8f1eec9c8)
0x8f1eec648   648  93407c65       sxtw x5, w3
0x8f1eec64c   64c  91005ca5       add x5, x5, #0x17 (23)
0x8f1eec650   650  38656884       ldrb w4, [x4, x5]
0x8f1eec654   654  35000504       cbnz w4, #+0xa0 (addr 0x8f1eec6f4)
0x8f1eec658   658  b8017043       stur w3, [x2, #23]
0x8f1eec65c   65c  7100007f       cmp w3, #0x0 (0)
0x8f1eec660   660  540004ad       b.le #+0x94 (addr 0x8f1eec6f4)
0x8f1eec664   664  f840f044       ldur x4, [x2, #15]
0x8f1eec668   668  51000463       sub w3, w3, #0x1 (1)
0x8f1eec66c   66c  b840f085       ldur w5, [x4, #15]
0x8f1eec670   670  6b05007f       cmp w3, w5
0x8f1eec674   674  54001a82       b.hs #+0x350 (addr 0x8f1eec9c4)
0x8f1eec678   678  93407c65       sxtw x5, w3
0x8f1eec67c   67c  91005ca5       add x5, x5, #0x17 (23)
0x8f1eec680   680  38656884       ldrb w4, [x4, x5]
0x8f1eec684   684  35000384       cbnz w4, #+0x70 (addr 0x8f1eec6f4)
0x8f1eec688   688  b8017043       stur w3, [x2, #23]
0x8f1eec68c   68c  7100007f       cmp w3, #0x0 (0)
0x8f1eec690   690  5400032d       b.le #+0x64 (addr 0x8f1eec6f4)
0x8f1eec694   694  f840f044       ldur x4, [x2, #15]
0x8f1eec698   698  51000463       sub w3, w3, #0x1 (1)
0x8f1eec69c   69c  b840f085       ldur w5, [x4, #15]
0x8f1eec6a0   6a0  6b05007f       cmp w3, w5
0x8f1eec6a4   6a4  540018e2       b.hs #+0x31c (addr 0x8f1eec9c0)
0x8f1eec6a8   6a8  93407c65       sxtw x5, w3
0x8f1eec6ac   6ac  91005ca5       add x5, x5, #0x17 (23)
0x8f1eec6b0   6b0  38656884       ldrb w4, [x4, x5]
0x8f1eec6b4   6b4  35000204       cbnz w4, #+0x40 (addr 0x8f1eec6f4)
0x8f1eec6b8   6b8  b8017043       stur w3, [x2, #23]
0x8f1eec6bc   6bc  f8520344       ldur x4, [x26, #-224]
0x8f1eec6c0   6c0  eb2463ff       cmp sp, x4
0x8f1eec6c4   6c4  54001709       b.ls #+0x2e0 (addr 0x8f1eec9a4)
0x8f1eec6c8   6c8  7100007f       cmp w3, #0x0 (0)
0x8f1eec6cc   6cc  5400014d       b.le #+0x28 (addr 0x8f1eec6f4)
0x8f1eec6d0   6d0  f840f044       ldur x4, [x2, #15]
0x8f1eec6d4   6d4  51000463       sub w3, w3, #0x1 (1)
0x8f1eec6d8   6d8  b840f085       ldur w5, [x4, #15]
0x8f1eec6dc   6dc  6b05007f       cmp w3, w5
0x8f1eec6e0   6e0  540016e2       b.hs #+0x2dc (addr 0x8f1eec9bc)
0x8f1eec6e4   6e4  93407c65       sxtw x5, w3
0x8f1eec6e8   6e8  91005ca5       add x5, x5, #0x17 (23)
0x8f1eec6ec   6ec  38656884       ldrb w4, [x4, x5]
0x8f1eec6f0   6f0  34fff9a4       cbz w4, #-0xcc (addr 0x8f1eec624)
0x8f1eec6f4   6f4  b8417043       ldur w3, [x2, #23]
0x8f1eec6f8   6f8  350000c3       cbnz w3, #+0x18 (addr 0x8f1eec710)
0x8f1eec6fc   6fc  b801b05f       stur wzr, [x2, #27]
0x8f1eec700   700  d2800000       movz x0, #0x0
0x8f1eec704   704  910003bf       mov sp, fp
0x8f1eec708   708  a8c17bfd       ldp fp, lr, [sp], #16
0x8f1eec70c   70c  d65f03c0       ret
0x8f1eec710   710  d2800000       movz x0, #0x0
0x8f1eec714   714  17fffffc       b #-0x10 (addr 0x8f1eec704)
0x8f1eec718   718  f9002fe2       str x2, [sp, #88]
0x8f1eec71c   71c  f90017e0       str x0, [sp, #40]
0x8f1eec720   720  f9001fe3       str x3, [sp, #56]
0x8f1eec724   724  94000540       bl #+0x1500 (addr 0x8f1eedc24)
0x8f1eec728   728  f9402fe2       ldr x2, [sp, #88]
0x8f1eec72c   72c  f94017e0       ldr x0, [sp, #40]
0x8f1eec730   730  f94033e7       ldr x7, [sp, #96]
0x8f1eec734   734  f9401fe3       ldr x3, [sp, #56]
0x8f1eec738   738  17fffe3b       b #-0x714 (addr 0x8f1eec024)
0x8f1eec73c   73c  f9002fe2       str x2, [sp, #88]
0x8f1eec740   740  d2c01002       movz x2, #0x8000000000
0x8f1eec744   744  d2800301       movz x1, #0x18
0x8f1eec748   748  f90017e0       str x0, [sp, #40]
0x8f1eec74c   74c  f9001fe3       str x3, [sp, #56]
0x8f1eec750   750  f90023e4       str x4, [sp, #64]
0x8f1eec754   754  f90027e5       str x5, [sp, #72]
0x8f1eec758   758  aa0203e6       mov x6, x2
0x8f1eec75c   75c  935dfc42       asr x2, x2, #29
0x8f1eec760   760  d28a2610       movz x16, #0x5130
0x8f1eec764   764  8b100042       add x2, x2, x16
0x8f1eec768   768  f8626b42       ldr x2, [x26, x2]
0x8f1eec76c   76c  d63f0040       blr x2
0x8f1eec770   770  d1000406       sub x6, x0, #0x1 (1)
0x8f1eec774   774  f94027e5       ldr x5, [sp, #72]
0x8f1eec778   778  f9402fe2       ldr x2, [sp, #88]
0x8f1eec77c   77c  f94017e0       ldr x0, [sp, #40]
0x8f1eec780   780  f94033e7       ldr x7, [sp, #96]
0x8f1eec784   784  f9401fe3       ldr x3, [sp, #56]
0x8f1eec788   788  f94023e4       ldr x4, [sp, #64]
0x8f1eec78c   78c  17fffe2f       b #-0x744 (addr 0x8f1eec048)
0x8f1eec790   790  f9002fe2       str x2, [sp, #88]
0x8f1eec794   794  f9001be5       str x5, [sp, #48]
0x8f1eec798   798  f90017e0       str x0, [sp, #40]
0x8f1eec79c   79c  f9001fe3       str x3, [sp, #56]
0x8f1eec7a0   7a0  f90023e4       str x4, [sp, #64]
0x8f1eec7a4   7a4  f9002be6       str x6, [sp, #80]
0x8f1eec7a8   7a8  d2800301       movz x1, #0x18
0x8f1eec7ac   7ac  d2c01002       movz x2, #0x8000000000
0x8f1eec7b0   7b0  935dfc42       asr x2, x2, #29
0x8f1eec7b4   7b4  d28a2610       movz x16, #0x5130
0x8f1eec7b8   7b8  8b100042       add x2, x2, x16
0x8f1eec7bc   7bc  f8626b42       ldr x2, [x26, x2]
0x8f1eec7c0   7c0  d63f0040       blr x2
0x8f1eec7c4   7c4  d1000408       sub x8, x0, #0x1 (1)
0x8f1eec7c8   7c8  f9402be6       ldr x6, [sp, #80]
0x8f1eec7cc   7cc  f9402fe2       ldr x2, [sp, #88]
0x8f1eec7d0   7d0  f9401be5       ldr x5, [sp, #48]
0x8f1eec7d4   7d4  f94017e0       ldr x0, [sp, #40]
0x8f1eec7d8   7d8  f94033e7       ldr x7, [sp, #96]
0x8f1eec7dc   7dc  f9401fe3       ldr x3, [sp, #56]
0x8f1eec7e0   7e0  f94023e4       ldr x4, [sp, #64]
0x8f1eec7e4   7e4  17fffe27       b #-0x764 (addr 0x8f1eec080)
0x8f1eec7e8   7e8  f9002fe2       str x2, [sp, #88]
0x8f1eec7ec   7ec  f9002be6       str x6, [sp, #80]
0x8f1eec7f0   7f0  f9001be5       str x5, [sp, #48]
0x8f1eec7f4   7f4  f90017e0       str x0, [sp, #40]
0x8f1eec7f8   7f8  f9001fe3       str x3, [sp, #56]
0x8f1eec7fc   7fc  f90027e4       str x4, [sp, #72]
0x8f1eec800   800  d2800301       movz x1, #0x18
0x8f1eec804   804  d2c01007       movz x7, #0x8000000000
0x8f1eec808   808  935dfce7       asr x7, x7, #29
0x8f1eec80c   80c  d28a2610       movz x16, #0x5130
0x8f1eec810   810  8b1000e7       add x7, x7, x16
0x8f1eec814   814  f8676b47       ldr x7, [x26, x7]
0x8f1eec818   818  d63f00e0       blr x7
0x8f1eec81c   81c  d1000408       sub x8, x0, #0x1 (1)
0x8f1eec820   820  f94027e4       ldr x4, [sp, #72]
0x8f1eec824   824  f9402fe2       ldr x2, [sp, #88]
0x8f1eec828   828  f9402be6       ldr x6, [sp, #80]
0x8f1eec82c   82c  f9401be5       ldr x5, [sp, #48]
0x8f1eec830   830  f94017e0       ldr x0, [sp, #40]
0x8f1eec834   834  f9401fe3       ldr x3, [sp, #56]
0x8f1eec838   838  17fffe22       b #-0x778 (addr 0x8f1eec0c0)
0x8f1eec83c   83c  f9002fe2       str x2, [sp, #88]
0x8f1eec840   840  f9002be6       str x6, [sp, #80]
0x8f1eec844   844  f90027e4       str x4, [sp, #72]
0x8f1eec848   848  f90013e3       str x3, [sp, #32]
0x8f1eec84c   84c  f9001be5       str x5, [sp, #48]
0x8f1eec850   850  f90023ed       str x13, [sp, #64]
0x8f1eec854   854  f9001fec       str x12, [sp, #56]
0x8f1eec858   858  f9000fe8       str x8, [sp, #24]
0x8f1eec85c   85c  f9000be9       str x9, [sp, #16]
0x8f1eec860   860  f90017e7       str x7, [sp, #40]
0x8f1eec864   864  94000540       bl #+0x1500 (addr 0x8f1eedd64)
0x8f1eec868   868  f9402fe2       ldr x2, [sp, #88]
0x8f1eec86c   86c  f9402be6       ldr x6, [sp, #80]
0x8f1eec870   870  f94027e4       ldr x4, [sp, #72]
0x8f1eec874   874  d280002a       movz x10, #0x1
0x8f1eec878   878  f94013e3       ldr x3, [sp, #32]
0x8f1eec87c   87c  f9401be5       ldr x5, [sp, #48]
0x8f1eec880   880  f94023ed       ldr x13, [sp, #64]
0x8f1eec884   884  f9401fec       ldr x12, [sp, #56]
0x8f1eec888   888  d280014b       movz x11, #0xa
0x8f1eec88c   88c  f9400fe8       ldr x8, [sp, #24]
0x8f1eec890   890  f9400be9       ldr x9, [sp, #16]
0x8f1eec894   894  f94017e7       ldr x7, [sp, #40]
0x8f1eec898   898  17fffe59       b #-0x69c (addr 0x8f1eec1fc)
0x8f1eec89c   89c  f9002fe2       str x2, [sp, #88]
0x8f1eec8a0   8a0  f9002be6       str x6, [sp, #80]
0x8f1eec8a4   8a4  f90027e4       str x4, [sp, #72]
0x8f1eec8a8   8a8  f90013e3       str x3, [sp, #32]
0x8f1eec8ac   8ac  f9001be5       str x5, [sp, #48]
0x8f1eec8b0   8b0  f90023e9       str x9, [sp, #64]
0x8f1eec8b4   8b4  f9001fe7       str x7, [sp, #56]
0x8f1eec8b8   8b8  94000540       bl #+0x1500 (addr 0x8f1eeddb8)
0x8f1eec8bc   8bc  f9402fe2       ldr x2, [sp, #88]
0x8f1eec8c0   8c0  f9402be6       ldr x6, [sp, #80]
0x8f1eec8c4   8c4  f94027e4       ldr x4, [sp, #72]
0x8f1eec8c8   8c8  d280002a       movz x10, #0x1
0x8f1eec8cc   8cc  f94013e3       ldr x3, [sp, #32]
0x8f1eec8d0   8d0  f9401be5       ldr x5, [sp, #48]
0x8f1eec8d4   8d4  f94023e9       ldr x9, [sp, #64]
0x8f1eec8d8   8d8  f9401fe7       ldr x7, [sp, #56]
0x8f1eec8dc   8dc  d2800148       movz x8, #0xa
0x8f1eec8e0   8e0  17fffe72       b #-0x638 (addr 0x8f1eec2a8)
0x8f1eec8e4   8e4  f9002fe2       str x2, [sp, #88]
0x8f1eec8e8   8e8  f9002be6       str x6, [sp, #80]
0x8f1eec8ec   8ec  f90027e4       str x4, [sp, #72]
0x8f1eec8f0   8f0  f9001fe7       str x7, [sp, #56]
0x8f1eec8f4   8f4  f90013e3       str x3, [sp, #32]
0x8f1eec8f8   8f8  f9001be5       str x5, [sp, #48]
0x8f1eec8fc   8fc  f90023e8       str x8, [sp, #64]
0x8f1eec900   900  f90017ed       str x13, [sp, #40]
0x8f1eec904   904  f90003ee       str x14, [sp]
0x8f1eec908   908  f90007eb       str x11, [sp, #8]
0x8f1eec90c   90c  f9000bec       str x12, [sp, #16]
0x8f1eec910   910  f9000fe9       str x9, [sp, #24]
0x8f1eec914   914  94000540       bl #+0x1500 (addr 0x8f1eede14)
0x8f1eec918   918  f9402fe2       ldr x2, [sp, #88]
0x8f1eec91c   91c  f9402be6       ldr x6, [sp, #80]
0x8f1eec920   920  f94027e4       ldr x4, [sp, #72]
0x8f1eec924   924  f9401fe7       ldr x7, [sp, #56]
0x8f1eec928   928  d280002a       movz x10, #0x1
0x8f1eec92c   92c  f94013e3       ldr x3, [sp, #32]
0x8f1eec930   930  f9401be5       ldr x5, [sp, #48]
0x8f1eec934   934  f94023e8       ldr x8, [sp, #64]
0x8f1eec938   938  d280014f       movz x15, #0xa
0x8f1eec93c   93c  f94017ed       ldr x13, [sp, #40]
0x8f1eec940   940  f94003ee       ldr x14, [sp]
0x8f1eec944   944  f94007eb       ldr x11, [sp, #8]
0x8f1eec948   948  f9400bec       ldr x12, [sp, #16]
0x8f1eec94c   94c  f9400fe9       ldr x9, [sp, #24]
0x8f1eec950   950  17fffebb       b #-0x514 (addr 0x8f1eec43c)
0x8f1eec954   954  f9002fe2       str x2, [sp, #88]
0x8f1eec958   958  f9002be6       str x6, [sp, #80]
0x8f1eec95c   95c  f90027e4       str x4, [sp, #72]
0x8f1eec960   960  f90023e5       str x5, [sp, #64]
0x8f1eec964   964  f9001fe7       str x7, [sp, #56]
0x8f1eec968   968  f9001beb       str x11, [sp, #48]
0x8f1eec96c   96c  f90017ec       str x12, [sp, #40]
0x8f1eec970   970  f90013e3       str x3, [sp, #32]
0x8f1eec974   974  94000540       bl #+0x1500 (addr 0x8f1eede74)
0x8f1eec978   978  f9402fe2       ldr x2, [sp, #88]
0x8f1eec97c   97c  f9402be6       ldr x6, [sp, #80]
0x8f1eec980   980  f94027e4       ldr x4, [sp, #72]
0x8f1eec984   984  d2800148       movz x8, #0xa
0x8f1eec988   988  f94023e5       ldr x5, [sp, #64]
0x8f1eec98c   98c  f9401fe7       ldr x7, [sp, #56]
0x8f1eec990   990  f9401beb       ldr x11, [sp, #48]
0x8f1eec994   994  f94017ec       ldr x12, [sp, #40]
0x8f1eec998   998  d280002a       movz x10, #0x1
0x8f1eec99c   99c  f94013e3       ldr x3, [sp, #32]
0x8f1eec9a0   9a0  17ffff02       b #-0x3f8 (addr 0x8f1eec5a8)
0x8f1eec9a4   9a4  f9002fe2       str x2, [sp, #88]
0x8f1eec9a8   9a8  f9002be3       str x3, [sp, #80]
0x8f1eec9ac   9ac  94000540       bl #+0x1500 (addr 0x8f1eedeac)
0x8f1eec9b0   9b0  f9402fe2       ldr x2, [sp, #88]
0x8f1eec9b4   9b4  f9402be3       ldr x3, [sp, #80]
0x8f1eec9b8   9b8  17ffff44       b #-0x2f0 (addr 0x8f1eec6c8)
0x8f1eec9bc   9bc  94000568       bl #+0x15a0 (addr 0x8f1eedf5c)
0x8f1eec9c0   9c0  94000568       bl #+0x15a0 (addr 0x8f1eedf60)
0x8f1eec9c4   9c4  94000568       bl #+0x15a0 (addr 0x8f1eedf64)
0x8f1eec9c8   9c8  94000568       bl #+0x15a0 (addr 0x8f1eedf68)
0x8f1eec9cc   9cc  94000568       bl #+0x15a0 (addr 0x8f1eedf6c)
0x8f1eec9d0   9d0  94000568       bl #+0x15a0 (addr 0x8f1eedf70)
0x8f1eec9d4   9d4  94000568       bl #+0x15a0 (addr 0x8f1eedf74)
0x8f1eec9d8   9d8  94000568       bl #+0x15a0 (addr 0x8f1eedf78)
0x8f1eec9dc   9dc  94000568       bl #+0x15a0 (addr 0x8f1eedf7c)
0x8f1eec9e0   9e0  94000568       bl #+0x15a0 (addr 0x8f1eedf80)
0x8f1eec9e4   9e4  94000568       bl #+0x15a0 (addr 0x8f1eedf84)
0x8f1eec9e8   9e8  94000568       bl #+0x15a0 (addr 0x8f1eedf88)
0x8f1eec9ec   9ec  94000568       bl #+0x15a0 (addr 0x8f1eedf8c)
0x8f1eec9f0   9f0  94000568       bl #+0x15a0 (addr 0x8f1eedf90)
0x8f1eec9f4   9f4  94000568       bl #+0x15a0 (addr 0x8f1eedf94)
0x8f1eec9f8   9f8  94000568       bl #+0x15a0 (addr 0x8f1eedf98)
0x8f1eec9fc   9fc  94000568       bl #+0x15a0 (addr 0x8f1eedf9c)
0x8f1eeca00   a00  94000568       bl #+0x15a0 (addr 0x8f1eedfa0)
0x8f1eeca04   a04  94000568       bl #+0x15a0 (addr 0x8f1eedfa4)
0x8f1eeca08   a08  94000568       bl #+0x15a0 (addr 0x8f1eedfa8)
0x8f1eeca0c   a0c  94000568       bl #+0x15a0 (addr 0x8f1eedfac)
0x8f1eeca10   a10  94000568       bl #+0x15a0 (addr 0x8f1eedfb0)
0x8f1eeca14   a14  94000568       bl #+0x15a0 (addr 0x8f1eedfb4)
0x8f1eeca18   a18  d503201f       nop
```
