from pathlib import Path
import hashlib,subprocess,statistics,json,platform
root=Path.cwd();bins={n:root/f'target/iss641-bench-build-{n}/native/release/build/Milky2018/portable_bench/portable_bench.exe' for n in ['baseline','candidate']}
report={'base_revision':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'candidate_dirty':True,'host':platform.platform(),'toolchain':subprocess.check_output(['moon','version','--all'],text=True),'method':'1000000 guest iterations plus final Store collection, parse/validation/instantiation outside timer; one warmup pair, seven serial alternating pairs; native interpreter only','binaries':{n:hashlib.sha256(p.read_bytes()).hexdigest() for n,p in bins.items()},'measurements':[]}
for kind in ['memory','gc','exceptions']:
 times={n:[] for n in bins}
 for pair in range(8):
  for n in (['baseline','candidate'] if pair%2==0 else ['candidate','baseline']):
   r=subprocess.run([str(bins[n]),kind],capture_output=True,text=True,check=True)
   value=float(r.stdout.strip())
   if pair:times[n].append(value)
 entry={'workload':kind,'seconds':times,'median_seconds':{n:statistics.median(v) for n,v in times.items()}}
 entry['candidate_over_baseline']=entry['median_seconds']['candidate']/entry['median_seconds']['baseline'];report['measurements'].append(entry);print(kind,entry['median_seconds'],entry['candidate_over_baseline'],flush=True)
(root/'target/iss641-native-performance.json').write_text(json.dumps(report,indent=2)+'\n')
