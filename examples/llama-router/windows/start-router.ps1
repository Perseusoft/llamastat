# Starts the llama.cpp router on Windows. To run it at login, put a shortcut to this script
# in shell:startup, or register it with Task Scheduler.
# Usage: .\start-router.ps1 [-Models "$env:USERPROFILE\models"]
param([string]$Models = "$env:USERPROFILE\models")

$server = (Get-Command llama-server -ErrorAction SilentlyContinue).Source
if (-not $server) { Write-Error "llama-server not found. Install it: winget install llama.cpp"; exit 1 }

New-Item -ItemType Directory -Force -Path $Models | Out-Null
$presets = Join-Path $Models "presets.ini"
if (-not (Test-Path $presets)) {
    $template = Get-Content (Join-Path $PSScriptRoot "..\presets.example.ini")
    $template -replace "__MODELS__", ($Models -replace "\\", "/") | Set-Content $presets
    Write-Host "==> Created $presets (edit it to list your .gguf models)"
}

& $server --models-preset $presets --models-max 1 --jinja --host 127.0.0.1 --port 8080 -ngl 999 -c 32768 --sleep-idle-seconds 900
