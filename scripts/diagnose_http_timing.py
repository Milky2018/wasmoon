#!/usr/bin/env python3
"""Temporary Windows HTTP timing experiment; results are not acceptance gates."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]


def instrument_tls(source: str) -> str:
    wrappers = []
    for name, signature, arguments in [
        ("init_server", "struct Context *ctx, unsigned char *pfx_content", "ctx, pfx_content"),
        ("init_client", "struct Context *ctx, int32_t verify", "ctx, verify"),
        ("verify_peer_certificate", "struct Context *ctx, LPWSTR host_name", "ctx, host_name"),
    ]:
        symbol = "moonbitlang_async_schannel_" + name
        needle = "int32_t " + symbol + "("
        assert source.count(needle) == 1, symbol
        source = source.replace(needle, "int32_t " + symbol + "_untraced(")
        wrappers.append(f'''
MOONBIT_FFI_EXPORT int32_t {symbol}({signature}) {{
  double start = wasmoon_http_diag_ms();
  fprintf(stderr, "[HTTP-TIMING] {name} begin %.3f\\n", start);
  const char *delay = getenv("WASMOON_HTTP_TLS_DELAY_MS");
  if (delay && strcmp("{name}", "init_server") == 0) Sleep((DWORD)atoi(delay));
  int32_t result = {symbol}_untraced({arguments});
  fprintf(stderr, "[HTTP-TIMING] {name} end %.3f elapsed=%.3f result=%ld\\n",
    wasmoon_http_diag_ms(), wasmoon_http_diag_ms() - start, (long)result);
  return result;
}}
''')
    helpers = '''
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static double wasmoon_http_diag_ms(void) {
  LARGE_INTEGER now, frequency;
  QueryPerformanceCounter(&now);
  QueryPerformanceFrequency(&frequency);
  return (double)now.QuadPart * 1000.0 / (double)frequency.QuadPart;
}
MOONBIT_FFI_EXPORT void wasmoon_http_timing_trace(int32_t event) {
  fprintf(stderr, "[HTTP-TIMING] event=%ld qpc_ms=%.3f tid=%lu\\n",
    (long)event, wasmoon_http_diag_ms(), (unsigned long)GetCurrentThreadId());
}
'''
    end = source.rfind("#endif")
    assert end > 0
    return source[:end] + helpers + "\n".join(wrappers) + source[end:]


def instrument_wire(source: str) -> str:
    source = source.replace(
        "  if self.offset == self.buffer.length() {\n",
        "  if self.offset == self.buffer.length() {\n"
        "    http_timing_trace(9000 + self.body_deadline.map(t => t.duration).unwrap_or(0))\n",
        1,
    )
    source = source.replace("    consume(bytes)\n", "    http_timing_trace(4000)\n    consume(bytes)\n    http_timing_trace(4001)\n")
    source = source.replace(
        "      self.body_deadline = self.timeout.map(millis => Timer(millis))\n",
        "      self.body_deadline = self.timeout.map(millis => Timer(millis))\n"
        "      http_timing_trace(3000 + self.timeout.unwrap_or(0))\n",
    )
    return source + '\n///|\nextern "c" fn http_timing_trace(event : Int32) -> Unit = "wasmoon_http_timing_trace"\n'


def instrument_tests(source: str) -> str:
    substitutions = [
        ('async test "first body byte keeps its budget through headers and chunk framing" {\n',
         'async test "first body byte keeps its budget through headers and chunk framing" {\n  http_timing_trace(100)\n'),
        ('      @async.sleep(100)\n      socket.write(b"hi',
         '      http_timing_trace(101)\n      @async.sleep(100)\n      http_timing_trace(102)\n      socket.write(b"hi'),
        ('async test "consumer backpressure does not consume the next body read budget" {\n',
         'async test "consumer backpressure does not consume the next body read budget" {\n  http_timing_trace(800)\n'),
        ('        writer.write(b"h")\n', '        http_timing_trace(801)\n        writer.write(b"h")\n        http_timing_trace(802)\n'),
        ('          wake.wait()\n        }\n        writer.write(b"i")',
         '          wake.wait()\n        }\n        http_timing_trace(806)\n        writer.write(b"i")\n        http_timing_trace(807)'),
        ('          @async.sleep(150)\n', '          http_timing_trace(803)\n          @async.sleep(150)\n          http_timing_trace(804)\n'),
        ('          ready.val = true\n          wake.broadcast()\n', '          ready.val = true\n          wake.broadcast()\n          http_timing_trace(805)\n'),
    ]
    for before, after in substitutions:
        assert source.count(before) == 1, before
        source = source.replace(before, after)
    return source


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--repeats", type=int, default=12)
    args = parser.parse_args()
    if os.name != "nt":
        raise SystemExit("This diagnostic requires the real Windows native runtime")
    args.output.mkdir(parents=True, exist_ok=True)
    paths = [ROOT / ".mooncakes/moonbitlang/async/src/tls/schannel.c",
             ROOT / "modules/wasmoon/wasi_http/wire.mbt",
             ROOT / "modules/wasmoon/wasi_http/timeout_wbtest.mbt"]
    originals = {p: p.read_bytes() for p in paths}
    report = {"diagnostic_only": True, "source_revision": subprocess.check_output(
        ["git", "rev-parse", "HEAD"], text=True).strip(), "original_sha256": {
            str(p.relative_to(ROOT)): hashlib.sha256(v).hexdigest() for p, v in originals.items()},
        "event_ids": {"100": "first-positive start", "101": "TCP headers sent / sleep100 begin",
                      "102": "sleep100 end / body write begin", "800": "backpressure start",
                      "801": "pipe h write begin", "802": "pipe h write returned",
                      "803": "consumer sleep150 begin", "804": "consumer sleep150 end",
                      "805": "consumer ready broadcast", "806": "producer ready observed",
                      "807": "pipe i write returned", "4000": "consume begin", "4001": "consume end",
                      "3000+ms": "next body Timer created", "9000+ms": "buffer empty / read with active Timer"},
        "runs": []}
    summary = args.output / "summary.json"
    def save(): summary.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    try:
        paths[0].write_text(instrument_tls(originals[paths[0]].decode()), encoding="utf-8")
        paths[1].write_text(instrument_wire(originals[paths[1]].decode()), encoding="utf-8")
        paths[2].write_text(instrument_tests(originals[paths[2]].decode()), encoding="utf-8")
        build_dir = args.output / "build"
        build = ["moon", "test", "--target", "native", "--package", "Milky2018/wasmoon/wasi_http",
                 "--build-only", "--strip", "--jobs", "2", "--target-dir", str(build_dir)]
        with (args.output / "build.log").open("w", encoding="utf-8") as log:
            subprocess.run(build, cwd=ROOT, stdout=log, stderr=log, check=True, timeout=1200)
        binary = (build_dir / "native/debug/test/Milky2018/wasmoon/wasi_http/wasi_http.whitebox_test.exe").resolve()
        metadata = json.loads(binary.with_name("__whitebox_test_info.json").read_text())
        whole_package = [f"{name}:0-{max(v['index'] for v in tests)+1}"
                         for name, tests in metadata["tests"].items() if tests]
        cohorts = [
            ("whole-package", whole_package),
            ("positive-only", ["timeout_wbtest.mbt:0-1", "timeout_wbtest.mbt:8-9"]),
            ("positive-with-tls", ["timeout_wbtest.mbt:0-1", "timeout_wbtest.mbt:8-9", "tls_wbtest.mbt:0-1"]),
            ("timeout-only", ["timeout_wbtest.mbt:0-9"]),
        ]
        for repeat in range(args.repeats):
            for name, tests in cohorts:
                start = time.monotonic()
                result = subprocess.run([str(binary), "/".join(tests)], cwd=ROOT, capture_output=True,
                                        text=True, encoding="utf-8", errors="replace", timeout=45)
                logfile = f"{repeat:02d}-{name}.log"
                (args.output / logfile).write_text(result.stdout + result.stderr, encoding="utf-8")
                verdicts = [json.loads(line) for line in result.stdout.splitlines()
                            if line.startswith('{"type":"result"')]
                expected = sum(int(t.split(":")[1].split("-")[1]) - int(t.split(":")[1].split("-")[0]) for t in tests)
                assert len(verdicts) == expected, (name, len(verdicts), expected, result.stdout)
                report["runs"].append({"repeat": repeat, "cohort": name, "code": result.returncode,
                                       "test_count": len(verdicts),
                                       "failures": [v for v in verdicts if v["message"]],
                                       "seconds": time.monotonic()-start, "log": logfile})
                save()
        # Positive control: prove a synchronous TLS stall can be observed, without
        # changing any HTTP deadline or treating this deliberately failing run as acceptance.
        name, tests = cohorts[2]
        env = os.environ.copy(); env["WASMOON_HTTP_TLS_DELAY_MS"] = "3500"
        result = subprocess.run([str(binary), "/".join(tests)], cwd=ROOT, env=env, capture_output=True,
                                text=True, encoding="utf-8", errors="replace", timeout=45)
        (args.output / "injected-tls-stall.log").write_text(result.stdout+result.stderr, encoding="utf-8")
        report["injected_tls_stall"] = {"milliseconds_per_server": 3500, "code": result.returncode,
                                        "log": "injected-tls-stall.log",
                                        "verdicts": [json.loads(line) for line in result.stdout.splitlines()
                                                     if line.startswith('{"type":"result"')]}
        save()
    finally:
        for p, original in originals.items(): p.write_bytes(original)
        report["sources_restored"] = all(p.read_bytes()==v for p,v in originals.items())
        save()
    print(json.dumps({"diagnostic": str(summary), "runs": len(report["runs"]),
                      "observed_failures": sum(bool(v["failures"]) or v["code"]!=0 for v in report["runs"]),
                      "sources_restored": report["sources_restored"]}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
