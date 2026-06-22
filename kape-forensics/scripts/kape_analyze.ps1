[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$Kape,
  [Parameter(Mandatory=$true)][string]$MSource,
  [Parameter(Mandatory=$true)][string]$MDest,
  [string]$Module = "!EZParser",
  [switch]$DryRun
)
$ErrorActionPreference = "Continue"
$argList = @("--msource", $MSource, "--mdest", $MDest, "--module", $Module)
$cmd = '"{0}" {1}' -f $Kape, ($argList -join ' ')
Write-Output "COMMAND: $cmd"
if ($DryRun) { Write-Output "(DryRun) Not executing."; return }
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
if (-not $isAdmin) {
  Write-Output "NOTE: kape.exe requires Administrator even for the --module (analysis) pass."
  Write-Output "      Relaunch elevated to use this broad pass, OR run the EZ Tools directly"
  Write-Output "      (see references/analyze.md) -- the direct tools do NOT need admin."
  return
}
New-Item -ItemType Directory -Force -Path $MDest | Out-Null
& $Kape @argList
Write-Output "`n=== Parsed CSVs produced ==="
Get-ChildItem -Path $MDest -Recurse -Filter *.csv -ErrorAction SilentlyContinue |
  Select-Object @{n='KB';e={[math]::Round($_.Length/1KB,1)}}, FullName | Format-Table -AutoSize
