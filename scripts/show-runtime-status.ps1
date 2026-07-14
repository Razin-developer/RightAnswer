param(
  [switch]$IncludeLogs
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

function Write-Section($title) {
  Write-Host ""
  Write-Host "=== $title ==="
}

Write-Section "Embedding Environment"
$envFile = Join-Path $root ".env"
if (Test-Path $envFile) {
  $envLines = Get-Content $envFile | Where-Object {
    $_ -match '^RIGHT_ANSWER_EMBEDDING_' -or $_ -match '^DATABASE_URL='
  }
  if ($envLines) {
    $envLines | ForEach-Object { Write-Host $_ }
  } else {
    Write-Host "No embedding-related settings found in .env"
  }
} else {
  Write-Host ".env not present"
}

Write-Section "Running Processes"
$processes = Get-CimInstance Win32_Process |
  Where-Object { $_.Name -in @("node.exe", "python.exe", "postgres.exe") } |
  Select-Object Name, ProcessId, ParentProcessId, CommandLine

if ($processes) {
  $processes | Format-Table -Wrap -AutoSize
} else {
  Write-Host "No node/python/postgres processes are currently running."
}

Write-Section "Storage"
$storageRoot = Join-Path $root "storage"
if (Test-Path $storageRoot) {
  Get-ChildItem $storageRoot -Directory |
    Select-Object Name, LastWriteTime |
    Sort-Object Name |
    Format-Table -AutoSize
} else {
  Write-Host "storage/ does not exist yet."
}

Write-Section "Database Check"
try {
  node (Join-Path $root "scripts/check-db.mjs")
} catch {
  Write-Host "Database check failed: $($_.Exception.Message)"
}

if ($IncludeLogs) {
  Write-Section "Latest Ingestion Logs"
  $logRoot = Join-Path $root "storage/logs/ingestion"
  if (Test-Path $logRoot) {
    Get-ChildItem $logRoot -File |
      Sort-Object LastWriteTime -Descending |
      Select-Object -First 10 Name, LastWriteTime, Length |
      Format-Table -AutoSize
  } else {
    Write-Host "No ingestion log directory yet."
  }
}
