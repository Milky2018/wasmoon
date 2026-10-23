import json, pathlib, subprocess, sys, tempfile
root=pathlib.Path.cwd()
with tempfile.TemporaryDirectory(prefix="pr577-control-") as work:
    for index,jobs in enumerate([2,1,2,1]):
        output=pathlib.Path(work)/str(index)
        cmd=[sys.executable,"scripts/run_wasi03.py","--upstream","upstream", "--wasmoon",str(root/"wasmoon.exe"),"--output",str(output),"--timeout","120","--http-contract-tests","--filter","http-client-*","--jobs",str(jobs)]
        result=subprocess.run(cmd,timeout=240)
        summary=json.loads((output/"summary.json").read_text())
        print(json.dumps({"round":index,"jobs":jobs,"returncode":result.returncode,"counts":summary["counts"]}),flush=True)
        for engine in ["jit","interp"]:
            case=output/engine/"http-client-send-errors"
            print("[DIAG-pr577 CONTROL]",index,jobs,engine,(case/"upstream.json").read_text(),flush=True)
            print((case/"log.txt").read_text(),flush=True)
