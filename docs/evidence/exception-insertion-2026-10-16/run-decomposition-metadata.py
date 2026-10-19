from pathlib import Path
import subprocess,os,re,json,random,statistics,hashlib
root=Path.cwd();rng=random.Random(637)
bins={'diagnostic':root/'target/exception-insert/decomposition-build/native/release/test/Milky2018/wasmoon_jit/jit_ffi/jit_ffi.whitebox_test.exe'}
modes=[0,1,2,3,8,9,10,11,16,17,18,19,32,33,34,35,64,65,66,67,128,129,130,131]
r={'method':'300000 native insertions; bit0 real heap, bit1 i64 payload; bit3 direct native append with synthetic IDs and physical verification, no MB policy; bit4 MB policy with native append returning success without allocating (diagnostic only, no snapshot verification); bit5 minimal managed callback; bit6 minimal C callback with identical signature and result; callback controls still construct/validate the request; bit7 skips logical Array.push only, retains monotonic ID advancement and physical append (diagnostic only, no lookup verification); 2 warmups,21 shuffled serial rounds. Old external wrapper unwrapped before timing. Snapshot verified after timing. Failed preliminary old-C harness run discarded: wrapper pointer treated as raw arena.','sha256':{k:hashlib.sha256(v.read_bytes()).hexdigest() for k,v in bins.items()},'samples':{str(m):{k:[] for k in bins} for m in modes}}
for i in range(23):
 order=[(m,k) for m in modes for k in bins];rng.shuffle(order)
 for m,k in order:
  p=subprocess.run([str(bins[k]),'insert_profile_wbtest.mbt:0-1'],env={**os.environ,'WASMOON_INSERT_PROBE_MODE':str(m)},capture_output=True,text=True,check=True,timeout=30)
  v=re.search(r'\[DEBUG-insert-probe\] (\d+) (\d+)',p.stderr);assert v and int(v[1])==m,(p.stdout,p.stderr)
  if i>=2:r['samples'][str(m)][k].append(int(v[2]))
for m,s in r['samples'].items(): print(m,{k:statistics.median(v) for k,v in s.items()},flush=True)
(root/'target/exception-insert/decomposition-metadata.json').write_text(json.dumps(r,indent=2)+'\n')
