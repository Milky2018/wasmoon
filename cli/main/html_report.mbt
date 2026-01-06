///|
/// Generate HTML report for explore command with multiple functions
fn generate_html_report(funcs : Array[CompiledFunc]) -> String {
  let sb = StringBuilder::new()
  // HTML header with 3-column layout
  sb.write_string(
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
      #|      --nav-bg: #1a1a1a;
      #|    }
      #|    * { box-sizing: border-box; margin: 0; padding: 0; }
      #|    body {
      #|      font-family: 'Fira Code', 'Consolas', 'Monaco', 'SF Mono', monospace;
      #|      background: var(--bg);
      #|      color: var(--fg);
      #|      line-height: 1.5;
      #|    }
      #|    .layout { display: flex; min-height: 100vh; }
      #|    .sidebar {
      #|      width: 220px;
      #|      background: var(--nav-bg);
      #|      border-left: 1px solid var(--border);
      #|      padding: 15px;
      #|      position: fixed;
      #|      right: 0;
      #|      height: 100vh;
      #|      overflow-y: auto;
      #|    }
      #|    .sidebar h2 {
      #|      color: var(--accent);
      #|      font-size: 12px;
      #|      text-transform: uppercase;
      #|      letter-spacing: 1px;
      #|      margin-bottom: 10px;
      #|    }
      #|    .sidebar ul { list-style: none; }
      #|    .sidebar li { margin: 2px 0; }
      #|    .sidebar a {
      #|      color: var(--fg);
      #|      text-decoration: none;
      #|      display: block;
      #|      padding: 6px 10px;
      #|      border-radius: 4px;
      #|      font-size: 12px;
      #|      white-space: nowrap;
      #|      overflow: hidden;
      #|      text-overflow: ellipsis;
      #|    }
      #|    .sidebar a:hover { background: var(--header-bg); }
      #|    .sidebar a.active { background: var(--accent); color: #fff; }
      #|    .sidebar .func-sig { font-size: 10px; color: #888; display: block; }
      #|    .stage-toggles {
      #|      margin-bottom: 20px;
      #|      padding-bottom: 15px;
      #|      border-bottom: 1px solid var(--border);
      #|    }
      #|    .stage-toggles label {
      #|      display: flex;
      #|      align-items: center;
      #|      padding: 4px 0;
      #|      font-size: 12px;
      #|      cursor: pointer;
      #|    }
      #|    .stage-toggles input {
      #|      margin-right: 8px;
      #|      accent-color: var(--accent);
      #|    }
      #|    .main {
      #|      flex: 1;
      #|      margin-right: 220px;
      #|      padding: 15px;
      #|    }
      #|    .func-section {
      #|      margin-bottom: 30px;
      #|      scroll-margin-top: 15px;
      #|    }
      #|    .func-header {
      #|      color: var(--accent);
      #|      font-size: 14px;
      #|      font-weight: 600;
      #|      padding: 8px 0;
      #|      border-bottom: 1px solid var(--accent);
      #|      margin-bottom: 10px;
      #|    }
      #|    .func-header .func-sig {
      #|      font-weight: 400;
      #|      font-size: 12px;
      #|      color: var(--fg);
      #|    }
      #|    .columns {
      #|      display: flex;
      #|      gap: 10px;
      #|    }
      #|    .column {
      #|      flex: 1;
      #|      min-width: 0;
      #|      background: var(--code-bg);
      #|      border: 1px solid var(--border);
      #|      border-radius: 6px;
      #|    }
      #|    .column.hidden { display: none; }
      #|    .column-header {
      #|      background: var(--header-bg);
      #|      padding: 6px 10px;
      #|      font-size: 11px;
      #|      font-weight: 600;
      #|      color: var(--success);
      #|      text-transform: uppercase;
      #|      letter-spacing: 0.5px;
      #|      border-bottom: 1px solid var(--border);
      #|    }
      #|    .column-content {
      #|      padding: 10px;
      #|    }
      #|    pre {
      #|      font-size: 11px;
      #|      line-height: 1.4;
      #|      white-space: pre-wrap;
      #|      word-break: break-all;
      #|      margin: 0;
      #|    }
      #|  </style>
      #|</head>
      #|<body>
      #|  <div class="layout">
      #|    <main class="main">
      #|
    ),
  )
  // Generate function sections with columns
  for i, func in funcs {
    let id = "func-\{i}"
    sb.write_string("      <section class=\"func-section\" id=\"\{id}\">\n")
    sb.write_string("        <div class=\"func-header\">")
    sb.write_string(html_escape(func.name))
    sb.write_string(" <span class=\"func-sig\">")
    sb.write_string(html_escape(func.type_str))
    sb.write_string("</span></div>\n")
    sb.write_string("        <div class=\"columns\">\n")
    // WAT Source column
    sb.write_string(
      "          <div class=\"column stage-source\"><div class=\"column-header\">WAT Source</div><div class=\"column-content\"><pre>",
    )
    sb.write_string(html_escape(func.source))
    sb.write_string("</pre></div></div>\n")
    // IR column (hidden by default)
    sb.write_string(
      "          <div class=\"column stage-ir hidden\"><div class=\"column-header\">IR (SSA)</div><div class=\"column-content\"><pre>",
    )
    sb.write_string(html_escape(func.ir))
    sb.write_string("</pre></div></div>\n")
    // Optimized IR column (hidden by default)
    sb.write_string(
      "          <div class=\"column stage-opt hidden\"><div class=\"column-header\">Optimized IR</div><div class=\"column-content\"><pre>",
    )
    sb.write_string(html_escape(func.ir_opt))
    sb.write_string("</pre></div></div>\n")
    // VCode column
    sb.write_string(
      "          <div class=\"column stage-vcode\"><div class=\"column-header\">VCode</div><div class=\"column-content\"><pre>",
    )
    sb.write_string(html_escape(func.vcode))
    sb.write_string("</pre></div></div>\n")
    // Register Allocation column (hidden by default)
    sb.write_string(
      "          <div class=\"column stage-reg hidden\"><div class=\"column-header\">Reg Alloc</div><div class=\"column-content\"><pre>",
    )
    sb.write_string(html_escape(func.regalloc))
    sb.write_string("</pre></div></div>\n")
    // Machine Code column
    sb.write_string(
      "          <div class=\"column stage-mc\"><div class=\"column-header\">Machine Code</div><div class=\"column-content\"><pre>",
    )
    sb.write_string(html_escape(func.mc))
    sb.write_string("</pre></div></div>\n")
    sb.write_string("        </div>\n")
    sb.write_string("      </section>\n\n")
  }
  // Close main, add sidebar
  sb.write_string(
    (
      #|    </main>
      #|    <nav class="sidebar">
      #|      <h2>Stages</h2>
      #|      <div class="stage-toggles">
      #|        <label><input type="checkbox" id="toggle-source" checked onchange="toggleStage('source')"> WAT Source</label>
      #|        <label><input type="checkbox" id="toggle-ir" onchange="toggleStage('ir')"> IR (SSA)</label>
      #|        <label><input type="checkbox" id="toggle-opt" onchange="toggleStage('opt')"> Optimized IR</label>
      #|        <label><input type="checkbox" id="toggle-vcode" checked onchange="toggleStage('vcode')"> VCode</label>
      #|        <label><input type="checkbox" id="toggle-reg" onchange="toggleStage('reg')"> Reg Alloc</label>
      #|        <label><input type="checkbox" id="toggle-mc" checked onchange="toggleStage('mc')"> Machine Code</label>
      #|      </div>
      #|      <h2>Functions</h2>
      #|      <ul>
      #|
    ),
  )
  // Generate sidebar links
  for i, func in funcs {
    sb.write_string("        <li><a href=\"#func-\{i}\">")
    sb.write_string(html_escape(func.name))
    sb.write_string("<span class=\"func-sig\">")
    sb.write_string(html_escape(func.type_str))
    sb.write_string("</span></a></li>\n")
  }
  // Footer with JavaScript
  sb.write_string(
    (
      #|      </ul>
      #|    </nav>
      #|  </div>
      #|  <script>
      #|    function toggleStage(stage) {
      #|      const checked = document.getElementById('toggle-' + stage).checked;
      #|      document.querySelectorAll('.stage-' + stage).forEach(el => {
      #|        el.classList.toggle('hidden', !checked);
      #|      });
      #|    }
      #|    // Highlight active function in sidebar on scroll
      #|    const sections = document.querySelectorAll('.func-section');
      #|    const navLinks = document.querySelectorAll('.sidebar a');
      #|    window.addEventListener('scroll', () => {
      #|      let current = '';
      #|      sections.forEach(section => {
      #|        if (scrollY >= section.offsetTop - 100) current = section.id;
      #|      });
      #|      navLinks.forEach(link => {
      #|        link.classList.toggle('active', link.getAttribute('href') === '#' + current);
      #|      });
      #|    });
      #|  </script>
      #|</body>
      #|</html>
    ),
  )
  sb.to_string()
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
