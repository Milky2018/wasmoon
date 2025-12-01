///|
/// Generate HTML report for explore command
fn generate_html_report(
  wasm_path : String,
  func_idx : Int,
  func_type : @types.FuncType,
  code : @types.FunctionCode,
  ir_func : @ir.Function,
  ir_optimized : String,
  vcode_func : String,
  allocated : String,
  opt_level : Int,
) -> String {
  let params = func_type.params.map(fn(t) { t.to_string() }).join(", ")
  let results = func_type.results.map(fn(t) { t.to_string() }).join(", ")
  let type_str = "(\{params}) -> (\{results})"
  let wasm_instrs = StringBuilder::new()
  for i, instr in code.body {
    wasm_instrs.write_string("      <tr><td>\{i}</td><td>")
    wasm_instrs.write_string(html_escape(instr.to_string()))
    wasm_instrs.write_string("</td></tr>\n")
  }
  let ir_text = html_escape(ir_func.print())
  let ir_opt_text = html_escape(ir_optimized)
  let vcode_text = html_escape(vcode_func)
  let allocated_text = html_escape(allocated)
  (
    #|<!DOCTYPE html>
    #|<html lang="en">
    #|<head>
    #|  <meta charset="UTF-8">
    #|  <meta name="viewport" content="width=device-width, initial-scale=1.0">
    #|  <title>Wasmoon Compilation Report</title>
    #|  <style>
    #|    :root {
    #|      --bg: #1e1e1e;
    #|      --fg: #d4d4d4;
    #|      --header-bg: #252526;
    #|      --border: #3c3c3c;
    #|      --accent: #569cd6;
    #|      --success: #4ec9b0;
    #|      --code-bg: #2d2d2d;
    #|    }
    #|    * { box-sizing: border-box; }
    #|    body {
    #|      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
    #|      background: var(--bg);
    #|      color: var(--fg);
    #|      margin: 0;
    #|      padding: 20px;
    #|      line-height: 1.6;
    #|    }
    #|    .container { max-width: 1400px; margin: 0 auto; }
    #|    h1 {
    #|      color: var(--accent);
    #|      border-bottom: 2px solid var(--accent);
    #|      padding-bottom: 10px;
    #|    }
    #|    h2 {
    #|      color: var(--success);
    #|      margin-top: 30px;
    #|      cursor: pointer;
    #|    }
    #|    h2:hover { text-decoration: underline; }
    #|    .meta {
    #|      background: var(--header-bg);
    #|      padding: 15px;
    #|      border-radius: 8px;
    #|      margin-bottom: 20px;
    #|    }
    #|    .meta-item { margin: 5px 0; }
    #|    .meta-label { color: #888; }
    #|    .section {
    #|      background: var(--code-bg);
    #|      border: 1px solid var(--border);
    #|      border-radius: 8px;
    #|      margin: 15px 0;
    #|      overflow: hidden;
    #|    }
    #|    .section-content {
    #|      padding: 15px;
    #|      overflow-x: auto;
    #|    }
    #|    pre {
    #|      margin: 0;
    #|      font-family: 'Fira Code', 'Consolas', 'Monaco', monospace;
    #|      font-size: 13px;
    #|      white-space: pre-wrap;
    #|      word-wrap: break-word;
    #|    }
    #|    table {
    #|      width: 100%;
    #|      border-collapse: collapse;
    #|    }
    #|    th, td {
    #|      text-align: left;
    #|      padding: 8px 12px;
    #|      border-bottom: 1px solid var(--border);
    #|    }
    #|    th { background: var(--header-bg); color: var(--accent); }
    #|    tr:hover { background: var(--header-bg); }
    #|    .collapsible { display: block; }
    #|    .collapsed { display: none; }
    #|    .toggle { float: right; font-size: 14px; color: #888; }
    #|  </style>
    #|</head>
    #|<body>
    #|  <div class="container">
    #|    <h1>Wasmoon Compilation Report</h1>
    #|    <div class="meta">
    #|      <div class="meta-item"><span class="meta-label">File:</span>
  ).to_string() +
  html_escape(wasm_path) +
  (
    #|</div>
    #|      <div class="meta-item"><span class="meta-label">Function:</span>
  ).to_string() +
  "\{func_idx}" +
  (
    #|</div>
    #|      <div class="meta-item"><span class="meta-label">Type:</span> <code>
  ).to_string() +
  html_escape(type_str) +
  (
    #|</code></div>
    #|      <div class="meta-item"><span class="meta-label">Locals:</span>
  ).to_string() +
  "\{code.locals.length()}" +
  (
    #|</div>
    #|      <div class="meta-item"><span class="meta-label">Optimization Level:</span> O
  ).to_string() +
  "\{opt_level}" +
  (
    #|</div>
    #|    </div>
    #|
    #|    <h2 onclick="toggleSection('wasm')">Stage 1: WASM Instructions <span class="toggle" id="wasm-toggle">[collapse]</span></h2>
    #|    <div class="section" id="wasm">
    #|      <div class="section-content">
    #|        <table>
    #|          <tr><th>Index</th><th>Instruction</th></tr>
    #|
  ).to_string() +
  wasm_instrs.to_string() +
  (
    #|        </table>
    #|      </div>
    #|    </div>
    #|
    #|    <h2 onclick="toggleSection('ir')">Stage 2: IR (SSA Form) <span class="toggle" id="ir-toggle">[collapse]</span></h2>
    #|    <div class="section" id="ir">
    #|      <div class="section-content"><pre>
  ).to_string() +
  ir_text +
  (
    #|</pre></div>
    #|    </div>
    #|
    #|    <h2 onclick="toggleSection('ir-opt')">Stage 3: Optimized IR (O
  ).to_string() +
  "\{opt_level}" +
  (
    #|) <span class="toggle" id="ir-opt-toggle">[collapse]</span></h2>
    #|    <div class="section" id="ir-opt">
    #|      <div class="section-content"><pre>
  ).to_string() +
  ir_opt_text +
  (
    #|</pre></div>
    #|    </div>
    #|
    #|    <h2 onclick="toggleSection('vcode')">Stage 4: VCode (Low-level IR) <span class="toggle" id="vcode-toggle">[collapse]</span></h2>
    #|    <div class="section" id="vcode">
    #|      <div class="section-content"><pre>
  ).to_string() +
  vcode_text +
  (
    #|</pre></div>
    #|    </div>
    #|
    #|    <h2 onclick="toggleSection('alloc')">Stage 5: After Register Allocation <span class="toggle" id="alloc-toggle">[collapse]</span></h2>
    #|    <div class="section" id="alloc">
    #|      <div class="section-content"><pre>
  ).to_string() +
  allocated_text +
  (
    #|</pre></div>
    #|    </div>
    #|
    #|    <script>
    #|      function toggleSection(id) {
    #|        const el = document.getElementById(id);
    #|        const toggle = document.getElementById(id + '-toggle');
    #|        if (el.classList.contains('collapsed')) {
    #|          el.classList.remove('collapsed');
    #|          toggle.textContent = '[collapse]';
    #|        } else {
    #|          el.classList.add('collapsed');
    #|          toggle.textContent = '[expand]';
    #|        }
    #|      }
    #|    </script>
    #|  </div>
    #|</body>
    #|</html>
  ).to_string()
}

///|
fn html_escape(s : String) -> String {
  let result = StringBuilder::new()
  for c in s {
    match c {
      '<' => result.write_string("&lt;")
      '>' => result.write_string("&gt;")
      '&' => result.write_string("&amp;")
      '"' => result.write_string("&quot;")
      '\'' => result.write_string("&#39;")
      _ => result.write_char(c)
    }
  }
  result.to_string()
}
