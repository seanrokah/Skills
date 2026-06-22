[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$Kape,
  [Parameter(Mandatory=$true)][string]$TSource,
  [Parameter(Mandatory=$true)][string]$TDest,
  [Parameter(Mandatory=$true)][string]$Target,
  [string]$Vhdx,
  [switch]$DryRun
)
$ErrorActionPreference = "Continue"
$argList = @("--tsource", $TSource, "--tdest", $TDest, "--target", $Target)
if ($Vhdx) { $argList += @("--vhdx", $Vhdx) }
$cmd = '"{0}" {1}' -f $Kape, ($argList -join ' ')
Write-Output "COMMAND: $cmd"
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
Write-Output ("Elevation: {0}" -f $(if($isAdmin){"Administrator"}else{"NOT elevated - live collection will fail"}))
if ($DryRun) { Write-Output "(DryRun) Not executing."; return }
New-Item -ItemType Directory -Force -Path $TDest | Out-Null
& $Kape @argList
# Build manifest from KAPE's CopyLog/SkipLog CSVs (sum ALL logs; KAPE may write one per source/target)
$copyLogs = Get-ChildItem -Path $TDest -Recurse -Filter "*_CopyLog.csv" -ErrorAction SilentlyContinue
$skipLogs = Get-ChildItem -Path $TDest -Recurse -Filter "*_SkipLog.csv" -ErrorAction SilentlyContinue
$copied = if ($copyLogs) { ($copyLogs | ForEach-Object { (Import-Csv $_.FullName | Measure-Object).Count } | Measure-Object -Sum).Sum } else { "n/a" }
$skipped = if ($skipLogs) { ($skipLogs | ForEach-Object { (Import-Csv $_.FullName | Measure-Object).Count } | Measure-Object -Sum).Sum } else { "n/a" }
# Hash the produced VHDX (chain of custody) if one was created
$vhdxLine = "VHDX: (none)"
if ($Vhdx) {
  $vhdxFile = Get-ChildItem -Path $TDest -Recurse -Filter "*.vhdx" -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($vhdxFile) {
    $sha = (Get-FileHash -Algorithm SHA256 -Path $vhdxFile.FullName).Hash
    $vhdxLine = "VHDX: $($vhdxFile.Name)  SHA256: $sha"
  } else { $vhdxLine = "VHDX: $Vhdx (file not found to hash)" }
}
$man = Join-Path $TDest "collection_manifest.md"
@(
 "# Collection Manifest",
 "Generated: $(Get-Date -Format o)",
 "KAPE: $Kape",
 "Source (--tsource): $TSource",
 "Target (--target): $Target",
 "Dest (--tdest): $TDest",
 $vhdxLine,
 "Files copied: $copied",
 "Files skipped: $skipped"
) | Out-File -FilePath $man -Encoding utf8
Write-Output "Manifest written: $man"
