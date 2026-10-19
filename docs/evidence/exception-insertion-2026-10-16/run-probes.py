from pathlib import Path
import subprocess,os,re,json,random,statistics,hashlib
root=Path.cwd();rng=random.Random(637)
bins={k:root/f'target/exception-insert/{v}/native/release/test/Milky2018/wasmoon_jit/jit_ffi/jit_ffi.whitebox_test.exe' for k,v in [('current','probe-build'),('matched_c','c-probe-build')]}
r={'method':'300000 native insertions; bit0 real heap, bit1 i64 payload; 2 warmups,21 shuffled serial rounds. Old external wrapper unwrapped before timing. Snapshot verified after timing. Failed preliminary old-C harness run discarded: wrapper pointer treated as raw arena.','sha256':{k:hashlib.sha256(v.read_bytes()).hexdigest() for k,v in bins.items()},'samples':{str(m):{k:[] for k in bins} for m in range(4)}}
for i in range(23):
 order=[(m,k) for m in range(4) for k in bins];rng.shuffle(order)
 for m,k in order:
  p=subprocess.run([str(bins[k]),'insert_profile_wbtest.mbt:0-1'],env={**os.environ,'WASMOON_INSERT_PROBE_MODE':str(m)},capture_output=True,text=True,check=True,timeout=30)
  v=re.search(r'\[DEBUG-insert-probe\] (\d+) (\d+)',p.stderr);assert v and int(v[1])==m,(p.stdout,p.stderr)
  if i>=2:r['samples'][str(m)][k].append(int(v[2]))
for m,s in r['samples'].items(): print(m,{k:statistics.median(v) for k,v in s.items()},flush=True)
(root/'target/exception-insert/probes.json').write_text(json.dumps(r,indent=2)+'\n')
