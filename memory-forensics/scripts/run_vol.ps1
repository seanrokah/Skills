[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$Vol,      # e.g. ".\vol.exe" or "python -m volatility3"
  [Parameter(Mandatory=$true)][string]$Image,
  [Parameter(Mandatory=$true)][string]$Out,       # artifacts dir
  [Parameter(Mandatory=$true)][string[]]$Plugins, # items: "name" or "name:--extra args"
  [string]$Symbols
)
$ErrorActionPreference = "Continue"
New-Item -ItemType Directory -Force -Path $Out | Out-Null
$log = Join-Path $Out "_collection_log.txt"
"=== Collection started $(Get-Date -Format o) ===" | Out-File -FilePath $log -Encoding utf8
$volParts = $Vol -split ' '
$volExe = $volParts[0]
$volLead = @(); if ($volParts.Length -gt 1) { $volLead = $volParts[1..($volParts.Length-1)] }
$symArgs = @(); if ($Symbols) { $symArgs = @("-s", $Symbols) }
foreach ($item in $Plugins) {
  $name, $extra = $item -split ':', 2
  $extraArgs = @(); if ($extra) { $extraArgs = $extra -split ' ' }
  $target = Join-Path $Out ("{0}.txt" -f $name)
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  & $volExe (@($volLead) + @("-f", $Image) + $symArgs + @($name) + $extraArgs) 2>$null |
    Out-File -FilePath $target -Encoding utf8
  $sw.Stop()
  $lines = (Get-Content $target -ErrorAction SilentlyContinue | Measure-Object -Line).Lines
  ("[DONE] {0,-34} {1,7:N1}s  {2} lines" -f $name, $sw.Elapsed.TotalSeconds, $lines) |
    Out-File -FilePath $log -Encoding utf8 -Append
}
"=== Collection finished $(Get-Date -Format o) ===" | Out-File -FilePath $log -Encoding utf8 -Append
Get-Content $log
