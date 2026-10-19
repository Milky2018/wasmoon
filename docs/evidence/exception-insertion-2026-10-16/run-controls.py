from pathlib import Path
import hashlib,json,os,random,statistics,subprocess
root=Path.cwd();binary=root/'target/exception-insert/controls';out=root/'target/exception-insert/controls.json';rng=random.Random(637)
report={'method':'Same binary; RC/view bit1, direct physical construction bit2, direct storage pointer bit4. 21 shuffled serial measured rounds after2 warmups; guest thread CPU and monotonic times checked. No parallel builds/tests. No semantic checks bypassed.','binary_sha256':hashlib.sha256(binary.read_bytes()).hexdigest(),'results':[]}
for workload,count in [('snapshots',300000),('snapshots-word',300000),('rethrow',2000000)]:
 row={'workload':workload,'count':count,'samples':{str(mode):[] for mode in range(8)}}
 for i in range(23):
  order=list(range(8));rng.shuffle(order)
  for mode in order:
   r=subprocess.run([str(binary),'run',str(root/f'docs/evidence/exception-performance-2026-10-16/{workload}.wat'),'--invoke','run','--arg',str(count)],env={**os.environ,'WASMOON_EXCEPTION_INSERT_CONTROL':str(mode)},capture_output=True,text=True,check=True,timeout=60)
   elapsed,cpu=map(int,r.stdout.split());assert cpu>0 and elapsed>0
   if i>=2:row['samples'][str(mode)].append({'cpu_ns':cpu,'guest_ns':elapsed})
 row['median']={mode:statistics.median(s['cpu_ns'] for s in samples) for mode,samples in row['samples'].items()}
 report['results'].append(row);out.write_text(json.dumps(report,indent=2)+'\n');print(workload,row['median'],flush=True)
