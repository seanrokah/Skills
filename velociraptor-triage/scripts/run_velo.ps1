[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$Velo,        # e.g. ".\velociraptor.exe"
  [Parameter(Mandatory=$true)][string]$Out,          # collection dir
  [Parameter(Mandatory=$true)][string[]]$Artifacts,  # items: "Name" or "Name:--args K=V"
  [string]$Format = "json"
)
$ErrorActionPreference = "Continue"
New-Item -ItemType Directory -Force -Path $Out | Out-Null
$log = Join-Path $Out "_collection_log.txt"
"=== Collection started $(Get-Date -Format o) ===" | Out-File -FilePath $log -Encoding utf8
$veloParts = $Velo -split ' '
$veloExe = $veloParts[0]
$veloLead = @(); if ($veloParts.Length -gt 1) { $veloLead = $veloParts[1..($veloParts.Length-1)] }
foreach ($item in $Artifacts) {
  $name, $extra = $item -split ':', 2
  $extraArgs = @(); if ($extra) { $extraArgs = $extra -split ' ' }
  $target = Join-Path $Out ("{0}.{1}" -f $name, $Format)
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  & $veloExe (@($veloLead) + @("--nobanner","artifacts","collect",$name) + $extraArgs + @("--format",$Format)) 2>$null |
    Out-File -FilePath $target -Encoding utf8
  $sw.Stop()
  $rows = (Select-String -Path $target -Pattern '"_Source"' -ErrorAction SilentlyContinue | Measure-Object).Count
  ("[DONE] {0,-40} {1,7:N1}s  {2} rows" -f $name, $sw.Elapsed.TotalSeconds, $rows) |
    Out-File -FilePath $log -Encoding utf8 -Append
}
"=== Collection finished $(Get-Date -Format o) ===" | Out-File -FilePath $log -Encoding utf8 -Append
Get-Content $log
