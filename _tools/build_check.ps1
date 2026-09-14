# build_check.ps1 -- OTTO EA strict compilation gate
#
# Stages a temporary MQL5 build tree that mirrors the MetaTrader terminal
# layout so that `#include "../Include/Otto/*.mqh"` resolves, compiles via the
# MetaEditor CLI, and reports the exact error/warning counts.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File build_check.ps1

param(
    [string]$Source = "C:\Users\vivek\Downloads\cline local work",
    [string]$MetaEditor = "C:\Program Files\Five Percent Online MetaTrader 5\MetaEditor64.exe",
    [string]$Entry = "otto.mq5"
)

$ErrorActionPreference = "Stop"

$buildRoot = Join-Path $env:TEMP "otto_build"
$experts   = Join-Path $buildRoot "MQL5\Experts"
$includes  = Join-Path $buildRoot "MQL5\Include\Otto"
$logPath   = Join-Path $buildRoot "compile.log"

Write-Host "=================================================================="
Write-Host "OTTO EA COMPILATION GATE"
Write-Host "=================================================================="
Write-Host "source    : $Source"
Write-Host "metaeditor: $MetaEditor"
Write-Host "entry     : $Entry"
Write-Host "buildRoot : $buildRoot"
Write-Host ""

if (-not (Test-Path $MetaEditor)) {
    Write-Host "FATAL: MetaEditor not found at $MetaEditor"
    exit 2
}

# --- Stage a clean build tree -------------------------------------------
if (Test-Path $buildRoot) { Remove-Item $buildRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path $experts, $includes | Out-Null

Copy-Item (Join-Path $Source "*.mqh") $includes -Force
Copy-Item (Join-Path $Source "*.mq5") $experts  -Force

# --- Keep the live terminal's Include\Otto in sync ------------------------
# Angle-bracket includes (<Otto\*.mqh>) resolve against the terminal's real
# MQL5\Include folder, NOT this staging tree. If the deployed headers drift
# out of date the compile silently links stale modules, so mirror them here.
$mt5Include = Join-Path $env:APPDATA "MetaQuotes\Terminal\10CE948A1DFC9A8C27E56E827008EBD4\MQL5\Include\Otto"
if (Test-Path (Split-Path $mt5Include -Parent)) {
    if (-not (Test-Path $mt5Include)) { New-Item -ItemType Directory -Force -Path $mt5Include | Out-Null }
    Copy-Item (Join-Path $Source "*.mqh") $mt5Include -Force
    Write-Host "synced headers -> $mt5Include"
    Write-Host ""
}

# Remove stale build artifacts so we never compile a cached binary
Get-ChildItem $buildRoot -Recurse -Include *.ex5, *.log -File -ErrorAction SilentlyContinue |
    Remove-Item -Force -ErrorAction SilentlyContinue

$entryPath = Join-Path $experts $Entry
if (-not (Test-Path $entryPath)) {
    Write-Host "FATAL: entry file not found: $entryPath"
    exit 2
}

Write-Host "staged files:"
Get-ChildItem $buildRoot -Recurse -File |
    ForEach-Object { Write-Host ("  {0} ({1} bytes)" -f $_.FullName, $_.Length) }
Write-Host ""

# --- Compile -------------------------------------------------------------
$sw = [System.Diagnostics.Stopwatch]::StartNew()
& $MetaEditor /compile:"$entryPath" /log:"$logPath" | Out-Null
$sw.Stop()
Write-Host ("compile wall time: {0:N0} ms" -f $sw.Elapsed.TotalMilliseconds)
Write-Host ""

if (-not (Test-Path $logPath)) {
    Write-Host "FATAL: compiler produced no log at $logPath"
    exit 2
}

# --- Parse the log -------------------------------------------------------
# MetaEditor writes the log as UTF-16LE on some builds; detect and decode.
$bytes = [System.IO.File]::ReadAllBytes($logPath)
if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
    $text = [System.Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2)
} else {
    $text = [System.Text.Encoding]::UTF8.GetString($bytes)
}

$lines = $text -split "`r?`n"

$errors   = @()
$warnings = @()
$ignored  = @()
$summary  = ""

foreach ($line in $lines) {
    $t = $line.Trim()
    # MetaEditor prefixes diagnostics with "<path>(line,col) : " on some builds
    # and with a bare ": " on others -- match both forms.
    if ($t -match "(^|:\s)error\s+\d+:")   { $errors   += $t; continue }
    if ($t -match "(^|:\s)warning\s+\d+:") { $warnings += $t; continue }
    if ($t -match "(^|:\s)information:\s*ignoring") { $ignored += $t; continue }
    if ($t -match "^\d+\s+error\(s\)")   { $summary = ($summary + $t + " ") }
    if ($t -match "^Result:")            { $summary = ($summary + $t) }
    if ($t -match "^\d+\s+warning\(s\)") { $summary = ($summary + $t + " ") }
}

Write-Host "=================================================================="
Write-Host "COMPILER LOG (full)"
Write-Host "=================================================================="
foreach ($line in $lines) {
    if ($line.Trim() -ne "") { Write-Host $line }
}
Write-Host ""

# --- Verdict -------------------------------------------------------------
Write-Host "=================================================================="
Write-Host "VERDICT"
Write-Host "=================================================================="

$nErr = $errors.Count
$nWarn = $warnings.Count
$ex5 = Get-ChildItem $experts -Filter "*.ex5" -File -ErrorAction SilentlyContinue

if ($ignored.Count -gt 0) {
    Write-Host ("ignored pragma/informational lines: {0}" -f $ignored.Count)
}
Write-Host ("errors  : {0}" -f $nErr)
Write-Host ("warnings: {0}" -f $nWarn)
if ($ex5) {
    Write-Host ("binary  : {0} ({1} bytes)" -f $ex5.FullName, $ex5.Length)
} else {
    Write-Host "binary  : NOT PRODUCED"
}
Write-Host ""
if ($summary) { Write-Host ("summary : {0}" -f $summary.Trim()) }

if ($nErr -gt 0) {
    Write-Host ""
    Write-Host "ERRORS:"
    $errors | ForEach-Object { Write-Host "  $_" }
}
if ($nWarn -gt 0) {
    Write-Host ""
    Write-Host "WARNINGS:"
    $warnings | ForEach-Object { Write-Host "  $_" }
}

Write-Host ""
if ($nErr -eq 0 -and $nWarn -eq 0 -and $ex5) {
    Write-Host "*** GATE PASSED: 0 errors, 0 warnings ***"
    exit 0
} else {
    Write-Host "*** GATE FAILED ***"
    exit 1
}