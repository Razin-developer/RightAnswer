param(
  [Parameter(Mandatory = $true, Position = 0)]
  [ValidateSet("extract-pages", "detect-chapters", "ingest-local", "run-all", "batch-csv")]
  [string]$Command,

  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$Args
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$tsxCli = Join-Path $root "node_modules\tsx\dist\cli.mjs"

if (-not (Test-Path $tsxCli)) {
  throw "tsx CLI was not found at $tsxCli. Run dependency install first."
}

$scriptMap = @{
  "extract-pages"   = "apps/api/scripts/textbook-extract-pages.ts"
  "detect-chapters" = "apps/api/scripts/textbook-detect-chapters.ts"
  "ingest-local"    = "apps/api/scripts/textbook-ingest-local.ts"
  "run-all"         = "apps/api/scripts/textbook-run-all.ts"
  "batch-csv"       = "apps/api/scripts/textbook-batch-from-csv.ts"
}

$target = Join-Path $root $scriptMap[$Command]
if (-not (Test-Path $target)) {
  throw "Target script not found: $target"
}

& node $tsxCli $target @Args
exit $LASTEXITCODE
