# Dot-source from an x64 Visual Studio developer environment.
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path "$PSScriptRoot/../..").Path
$tools = Join-Path $repo "target/msvc-tools"
New-Item -ItemType Directory -Force $tools | Out-Null
$env:WASMOON_MSVC_CL = (Get-Command cl.exe -ErrorAction Stop).Source
$env:WASMOON_MSVC_LIB = (Get-Command lib.exe -ErrorAction Stop).Source
$env:WASMOON_MSVC_ML64 = (Get-Command ml64.exe -ErrorAction Stop).Source
& $env:WASMOON_MSVC_CL /nologo /std:c11 /MT /D_CRT_SECURE_NO_WARNINGS "$PSScriptRoot/driver.c" "/Fe$tools/wasmoon-cl.exe" "/Fo$tools/driver.obj"
if ($LASTEXITCODE -ne 0) { throw "MSVC driver build failed" }
Copy-Item "$tools/wasmoon-cl.exe" "$tools/lib.exe" -Force
$env:MOON_CC = Join-Path $tools "wasmoon-cl.exe"
Write-Host "C compiler: $env:WASMOON_MSVC_CL"
Write-Host "Assembler: $env:WASMOON_MSVC_ML64"
if ($env:GITHUB_ENV) {
    foreach ($name in @("WASMOON_MSVC_CL", "WASMOON_MSVC_LIB", "WASMOON_MSVC_ML64", "MOON_CC")) {
        "$name=$([Environment]::GetEnvironmentVariable($name))" >> $env:GITHUB_ENV
    }
}
