import http.client, http.server, json, queue, re, socket, subprocess, threading, time
from pathlib import Path
from socketserver import TCPServer

class Endpoint(http.server.BaseHTTPRequestHandler):
    protocol_version="HTTP/1.1"
    def do_GET(self):
        if self.headers.get("Transfer-Encoding","").lower()=="chunked":
            while True:
                size=int(self.rfile.readline().split(b";")[0],16)
                if size==0:
                    while self.rfile.readline() not in (b"\r\n",b"\n",b""): pass
                    break
                self.rfile.read(size)
                self.rfile.read(2)
        self.send_response(200)
        self.send_header("Content-Length","0")
        self.send_header("Connection","close")
        self.end_headers()
        self.close_connection=True
    def log_message(self,*args): pass

class Server(http.server.ThreadingHTTPServer):
    def server_bind(self):
        TCPServer.server_bind(self)
        self.server_name,self.server_port=self.server_address

def run(engine,index):
    server=Server(("127.0.0.1",0),Endpoint)
    threading.Thread(target=server.serve_forever,daemon=True).start()
    with socket.socket() as dead:
        dead.bind(("127.0.0.1",0))
        closed=dead.getsockname()[1]
    guest=Path("upstream/tests/rust/testsuite/wasm32-wasip3/http-client-send-errors.wasm").resolve()
    cmd=[str(Path("wasmoon.exe").resolve()),"serve","--addr","127.0.0.1:0","--network","all",
         "--env",f"HTTP_SERVER_MAIN=127.0.0.1:{server.server_port}",
         "--env",f"HTTP_SERVER_DEAD=127.0.0.1:{closed}"]
    if engine=="interp": cmd+=["--no-jit"]
    cmd+=[str(guest)]
    t=time.perf_counter()
    proc=subprocess.Popen(cmd,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,text=True)
    ready=queue.Queue()
    def consume():
        for line in proc.stderr:
            print(json.dumps({"engine":engine,"round":index,"seconds":time.perf_counter()-t,"stderr":line.strip()}),flush=True)
            if "Serving " in line:
                ready.put(re.search(r"http://([^\s]+)",line)[1])
    reader=threading.Thread(target=consume,daemon=True)
    reader.start()
    try:
        addr=ready.get(timeout=30)
        host,port=addr.rsplit(":",1)
        c=http.client.HTTPConnection(host,int(port),timeout=5)
        start=time.perf_counter()
        try:
            c.request("GET","/")
            r=c.getresponse()
            body=r.read()
            print(json.dumps({"engine":engine,"round":index,"response":r.status,"body":body.decode(),"request_s":time.perf_counter()-start}),flush=True)
        except Exception as e:
            print(json.dumps({"engine":engine,"round":index,"request_error":repr(e),"request_s":time.perf_counter()-start}),flush=True)
            time.sleep(8)
        finally:
            c.close()
    finally:
        proc.terminate()
        proc.wait(timeout=10)
        reader.join(timeout=2)
        server.shutdown()
        server.server_close()
    print(json.dumps({"engine":engine,"round":index,"total_s":time.perf_counter()-t}),flush=True)

for engine,index in [("jit",0),("interp",0),("jit",1),("jit",2)]:
    run(engine,index)
