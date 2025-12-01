///|
/// Generate shell completion script
fn run_completion(shell : String) -> Unit {
  match shell {
    "bash" => print_bash_completion()
    "zsh" => print_zsh_completion()
    "fish" => print_fish_completion()
    _ =>
      println("Error: unsupported shell '\{shell}'. Supported: bash, zsh, fish")
  }
}

///|
fn print_bash_completion() -> Unit {
  println(
    (
      #|_wasmoon() {
      #|    local cur prev opts commands
      #|    COMPREPLY=()
      #|    cur="${COMP_WORDS[COMP_CWORD]}"
      #|    prev="${COMP_WORDS[COMP_CWORD-1]}"
      #|    commands="run compile demo test disasm wat wast explore objdump settings completion"
      #|
      #|    case "${prev}" in
      #|        wasmoon)
      #|            COMPREPLY=( $(compgen -W "${commands}" -- ${cur}) )
      #|            return 0
      #|            ;;
      #|        run|compile|disasm|wat|wast|explore|objdump)
      #|            COMPREPLY=( $(compgen -f -X '!*.wasm' -- ${cur}) $(compgen -f -X '!*.wat' -- ${cur}) $(compgen -f -X '!*.cwasm' -- ${cur}) $(compgen -d -- ${cur}) )
      #|            return 0
      #|            ;;
      #|        test)
      #|            COMPREPLY=( $(compgen -f -X '!*.json' -- ${cur}) $(compgen -d -- ${cur}) )
      #|            return 0
      #|            ;;
      #|        completion)
      #|            COMPREPLY=( $(compgen -W "bash zsh fish" -- ${cur}) )
      #|            return 0
      #|            ;;
      #|        --invoke|--func)
      #|            return 0
      #|            ;;
      #|        --O)
      #|            COMPREPLY=( $(compgen -W "0 1 2 3" -- ${cur}) )
      #|            return 0
      #|            ;;
      #|        *)
      #|            ;;
      #|    esac
      #|
      #|    if [[ ${cur} == -* ]] ; then
      #|        case "${COMP_WORDS[1]}" in
      #|            run)
      #|                COMPREPLY=( $(compgen -W "--invoke --arg --preload" -- ${cur}) )
      #|                ;;
      #|            compile)
      #|                COMPREPLY=( $(compgen -W "--output --emit-ir" -- ${cur}) )
      #|                ;;
      #|            explore)
      #|                COMPREPLY=( $(compgen -W "--func --O --html" -- ${cur}) )
      #|                ;;
      #|        esac
      #|        return 0
      #|    fi
      #|}
      #|complete -F _wasmoon wasmoon
    ),
  )
}

///|
fn print_zsh_completion() -> Unit {
  println(
    (
      #|#compdef wasmoon
      #|
      #|_wasmoon() {
      #|    local -a commands
      #|    commands=(
      #|        'run:Run a WebAssembly module'
      #|        'compile:Compile WASM to precompiled format'
      #|        'demo:Run built-in demo programs'
      #|        'test:Run wasm-testsuite JSON spec file'
      #|        'disasm:Disassemble WASM file to text format'
      #|        'wat:Parse WAT file and display as text'
      #|        'wast:Run WebAssembly test script'
      #|        'explore:Explore WASM compilation process'
      #|        'objdump:Inspect precompiled .cwasm file'
      #|        'settings:Display available compiler settings'
      #|        'completion:Generate shell completion script'
      #|    )
      #|
      #|    _arguments -C \
      #|        '1: :->command' \
      #|        '*: :->args'
      #|
      #|    case $state in
      #|        command)
      #|            _describe 'command' commands
      #|            ;;
      #|        args)
      #|            case $words[2] in
      #|                run|compile|disasm|wat|wast|explore|objdump)
      #|                    _files -g '*.wasm' -g '*.wat' -g '*.cwasm'
      #|                    ;;
      #|                test)
      #|                    _files -g '*.json'
      #|                    ;;
      #|                completion)
      #|                    _values 'shell' bash zsh fish
      #|                    ;;
      #|            esac
      #|            ;;
      #|    esac
      #|}
      #|
      #|_wasmoon "$@"
    ),
  )
}

///|
fn print_fish_completion() -> Unit {
  println(
    (
      #|# Fish completion for wasmoon
      #|
      #|# Disable file completion by default
      #|complete -c wasmoon -f
      #|
      #|# Commands
      #|complete -c wasmoon -n "__fish_use_subcommand" -a "run" -d "Run a WebAssembly module"
      #|complete -c wasmoon -n "__fish_use_subcommand" -a "compile" -d "Compile WASM to precompiled format"
      #|complete -c wasmoon -n "__fish_use_subcommand" -a "demo" -d "Run built-in demo programs"
      #|complete -c wasmoon -n "__fish_use_subcommand" -a "test" -d "Run wasm-testsuite JSON spec file"
      #|complete -c wasmoon -n "__fish_use_subcommand" -a "disasm" -d "Disassemble WASM file to text format"
      #|complete -c wasmoon -n "__fish_use_subcommand" -a "wat" -d "Parse WAT file and display as text"
      #|complete -c wasmoon -n "__fish_use_subcommand" -a "wast" -d "Run WebAssembly test script"
      #|complete -c wasmoon -n "__fish_use_subcommand" -a "explore" -d "Explore WASM compilation process"
      #|complete -c wasmoon -n "__fish_use_subcommand" -a "objdump" -d "Inspect precompiled .cwasm file"
      #|complete -c wasmoon -n "__fish_use_subcommand" -a "settings" -d "Display available compiler settings"
      #|complete -c wasmoon -n "__fish_use_subcommand" -a "completion" -d "Generate shell completion script"
      #|
      #|# File completions for commands that need them
      #|complete -c wasmoon -n "__fish_seen_subcommand_from run compile disasm wat wast explore objdump" -F -a "*.wasm *.wat *.cwasm"
      #|complete -c wasmoon -n "__fish_seen_subcommand_from test" -F -a "*.json"
      #|
      #|# Completion command arguments
      #|complete -c wasmoon -n "__fish_seen_subcommand_from completion" -a "bash zsh fish"
      #|
      #|# Options for run command
      #|complete -c wasmoon -n "__fish_seen_subcommand_from run" -l invoke -d "Function to invoke"
      #|complete -c wasmoon -n "__fish_seen_subcommand_from run" -l arg -d "Arguments to pass to the function"
      #|complete -c wasmoon -n "__fish_seen_subcommand_from run" -l preload -d "Preload module as NAME=PATH"
      #|
      #|# Options for compile command
      #|complete -c wasmoon -n "__fish_seen_subcommand_from compile" -l output -d "Output path"
      #|complete -c wasmoon -n "__fish_seen_subcommand_from compile" -l emit-ir -d "Emit IR to specified path"
      #|
      #|# Options for explore command
      #|complete -c wasmoon -n "__fish_seen_subcommand_from explore" -l func -d "Function index to explore"
      #|complete -c wasmoon -n "__fish_seen_subcommand_from explore" -l O -d "Optimization level (0-3)"
      #|complete -c wasmoon -n "__fish_seen_subcommand_from explore" -l html -d "Output HTML report to path"
    ),
  )
}
