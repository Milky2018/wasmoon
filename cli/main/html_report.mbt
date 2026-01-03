///|
/// Generate HTML report for explore command with multiple functions
fn generate_html_report(funcs : Array[CompiledFunc]) -> String {
  let sb = StringBuilder::new()
  // HTML header
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
      #|    * { box-sizing: border-box; }
      #|    body {
      #|      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      #|      background: var(--bg);
      #|      color: var(--fg);
      #|      margin: 0;
      #|      padding: 0;
      #|      line-height: 1.6;
      #|    }
      #|    .layout {
      #|      display: flex;
      #|      min-height: 100vh;
      #|    }
      #|    .sidebar {
      #|      width: 250px;
      #|      background: var(--nav-bg);
      #|      border-right: 1px solid var(--border);
      #|      padding: 20px;
      #|      position: fixed;
      #|      height: 100vh;
      #|      overflow-y: auto;
      #|    }
      #|    .sidebar h2 {
      #|      color: var(--accent);
      #|      margin: 0 0 15px 0;
      #|      font-size: 14px;
      #|      text-transform: uppercase;
      #|      letter-spacing: 1px;
      #|    }
      #|    .sidebar ul {
      #|      list-style: none;
      #|      padding: 0;
      #|      margin: 0;
      #|    }
      #|    .sidebar li {
      #|      margin: 4px 0;
      #|    }
      #|    .sidebar a {
      #|      color: var(--fg);
      #|      text-decoration: none;
      #|      display: block;
      #|      padding: 8px 12px;
      #|      border-radius: 4px;
      #|      font-size: 13px;
      #|      white-space: nowrap;
      #|      overflow: hidden;
      #|      text-overflow: ellipsis;
      #|    }
      #|    .sidebar a:hover {
      #|      background: var(--header-bg);
      #|    }
      #|    .sidebar a.active {
      #|      background: var(--accent);
      #|      color: #fff;
      #|    }
      #|    .sidebar code {
      #|      font-size: 11px;
      #|      color: #888;
      #|      display: block;
      #|      margin-top: 2px;
      #|    }
      #|    .main {
      #|      flex: 1;
      #|      margin-left: 250px;
      #|      padding: 30px;
      #|    }
      #|    .func-section {
      #|      margin-bottom: 60px;
      #|      scroll-margin-top: 20px;
      #|    }
      #|    h1 {
      #|      color: var(--accent);
      #|      border-bottom: 2px solid var(--accent);
      #|      padding-bottom: 10px;
      #|      margin-top: 0;
      #|    }
      #|    h1 code {
      #|      background: var(--code-bg);
      #|      padding: 4px 8px;
      #|      border-radius: 4px;
      #|      font-size: 0.85em;
      #|    }
      #|    h2 {
      #|      color: var(--success);
      #|      margin-top: 25px;
      #|      cursor: pointer;
      #|      font-size: 16px;
      #|    }
      #|    h2:hover { text-decoration: underline; }
      #|    .section {
      #|      background: var(--code-bg);
      #|      border: 1px solid var(--border);
      #|      border-radius: 8px;
      #|      margin: 10px 0;
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
      #|    .collapsed { display: none; }
      #|    .toggle { float: right; font-size: 13px; color: #888; }
      #|  </style>
      #|</head>
      #|<body>
      #|  <div class="layout">
      #|    <nav class="sidebar">
      #|      <h2>Functions</h2>
      #|      <ul>
      #|
    ),
  )
  // Generate sidebar links
  for i, func in funcs {
    sb.write_string("        <li><a href=\"#func-\{i}\">")
    sb.write_string(html_escape(func.name))
    sb.write_string("<code>")
    sb.write_string(html_escape(func.type_str))
    sb.write_string("</code></a></li>\n")
  }
  sb.write_string(
    (
      #|      </ul>
      #|    </nav>
      #|    <main class="main">
      #|
    ),
  )
  // Generate function sections
  for i, func in funcs {
    let id = "func-\{i}"
    sb.write_string("      <section class=\"func-section\" id=\"\{id}\">\n")
    sb.write_string("        <h1>")
    sb.write_string(html_escape(func.name))
    sb.write_string(" <code>")
    sb.write_string(html_escape(func.type_str))
    sb.write_string("</code></h1>\n\n")
    // WAT Source
    sb.write_string(
      "        <h2 onclick=\"toggleSection('\{id}-source')\">WAT Source <span class=\"toggle\" id=\"\{id}-source-toggle\">[collapse]</span></h2>\n",
    )
    sb.write_string("        <div class=\"section\" id=\"\{id}-source\">\n")
    sb.write_string("          <div class=\"section-content\"><pre>")
    sb.write_string(html_escape(func.source))
    sb.write_string("</pre></div>\n        </div>\n\n")
    // IR
    sb.write_string(
      "        <h2 onclick=\"toggleSection('\{id}-ir')\">IR (SSA Form) <span class=\"toggle\" id=\"\{id}-ir-toggle\">[collapse]</span></h2>\n",
    )
    sb.write_string("        <div class=\"section\" id=\"\{id}-ir\">\n")
    sb.write_string("          <div class=\"section-content\"><pre>")
    sb.write_string(html_escape(func.ir))
    sb.write_string("</pre></div>\n        </div>\n\n")
    // Optimized IR
    sb.write_string(
      "        <h2 onclick=\"toggleSection('\{id}-opt')\">Optimized IR <span class=\"toggle\" id=\"\{id}-opt-toggle\">[collapse]</span></h2>\n",
    )
    sb.write_string("        <div class=\"section\" id=\"\{id}-opt\">\n")
    sb.write_string("          <div class=\"section-content\"><pre>")
    sb.write_string(html_escape(func.ir_opt))
    sb.write_string("</pre></div>\n        </div>\n\n")
    // VCode
    sb.write_string(
      "        <h2 onclick=\"toggleSection('\{id}-vcode')\">VCode <span class=\"toggle\" id=\"\{id}-vcode-toggle\">[collapse]</span></h2>\n",
    )
    sb.write_string("        <div class=\"section\" id=\"\{id}-vcode\">\n")
    sb.write_string("          <div class=\"section-content\"><pre>")
    sb.write_string(html_escape(func.vcode))
    sb.write_string("</pre></div>\n        </div>\n\n")
    // Register Allocation
    sb.write_string(
      "        <h2 onclick=\"toggleSection('\{id}-reg')\">Register Allocation <span class=\"toggle\" id=\"\{id}-reg-toggle\">[collapse]</span></h2>\n",
    )
    sb.write_string("        <div class=\"section\" id=\"\{id}-reg\">\n")
    sb.write_string("          <div class=\"section-content\"><pre>")
    sb.write_string(html_escape(func.regalloc))
    sb.write_string("</pre></div>\n        </div>\n\n")
    // Machine Code
    sb.write_string(
      "        <h2 onclick=\"toggleSection('\{id}-mc')\">Machine Code <span class=\"toggle\" id=\"\{id}-mc-toggle\">[collapse]</span></h2>\n",
    )
    sb.write_string("        <div class=\"section\" id=\"\{id}-mc\">\n")
    sb.write_string("          <div class=\"section-content\"><pre>")
    sb.write_string(html_escape(func.mc))
    sb.write_string("</pre></div>\n        </div>\n")
    sb.write_string("      </section>\n\n")
  }
  // Footer
  sb.write_string(
    (
      #|    </main>
      #|  </div>
      #|  <script>
      #|    function toggleSection(id) {
      #|      const el = document.getElementById(id);
      #|      const toggle = document.getElementById(id + '-toggle');
      #|      if (el.classList.contains('collapsed')) {
      #|        el.classList.remove('collapsed');
      #|        toggle.textContent = '[collapse]';
      #|      } else {
      #|        el.classList.add('collapsed');
      #|        toggle.textContent = '[expand]';
      #|      }
      #|    }
      #|    // Highlight active function in sidebar on scroll
      #|    const sections = document.querySelectorAll('.func-section');
      #|    const navLinks = document.querySelectorAll('.sidebar a');
      #|    window.addEventListener('scroll', () => {
      #|      let current = '';
      #|      sections.forEach(section => {
      #|        const top = section.offsetTop;
      #|        if (scrollY >= top - 100) current = section.id;
      #|      });
      #|      navLinks.forEach(link => {
      #|        link.classList.remove('active');
      #|        if (link.getAttribute('href') === '#' + current) {
      #|          link.classList.add('active');
      #|        }
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
