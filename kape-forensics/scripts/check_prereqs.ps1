[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$KapePath)
$ErrorActionPreference = "Continue"
$kape = Join-Path $KapePath "kape.exe"
Write-Output "=== KAPE prerequisite check ==="
if (Test-Path $kape) {
  $v = (Get-Item $kape).VersionInfo.FileVersion
  Write-Output ("kape.exe        : FOUND  ({0})  {1}" -f ($(if($v){$v}else{"version n/a"}), $kape))
} else {
  Write-Output "kape.exe        : MISSING at $kape"
  Write-Output "  -> KAPE is registration-gated; obtain it from Kroll and re-run with the correct -KapePath."
}
$bin = Join-Path $KapePath "Modules\bin"
$want = @("MFTECmd.exe","EvtxECmd.exe","AmcacheParser.exe","AppCompatCacheParser.exe","PECmd.exe",
          "SBECmd.exe","LECmd.exe","JLECmd.exe","SrumECmd.exe","RBCmd.exe")
Write-Output "`n=== EZ Tools in Modules\bin ==="
$missing = @()
foreach ($t in $want) {
  # Some EZ Tools (e.g. EvtxECmd) ship in a subfolder under bin, so search recursively.
  $hit = if (Test-Path $bin) { Get-ChildItem -Path $bin -Recurse -Filter $t -ErrorAction SilentlyContinue | Select-Object -First 1 } else { $null }
  if ($hit) { Write-Output ("  [OK]      {0}" -f $t) }
  else { Write-Output ("  [MISSING] {0}" -f $t); $missing += $t }
}
if ($missing.Count -gt 0) {
  Write-Output "`nMissing EZ Tools. Fetch the free tools by running (from the KAPE folder):"
  Write-Output "  .\Get-KAPEUpdate.ps1"
  Write-Output "  (or download EZ Tools and place the .exe files in Modules\bin)"
}
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
           ).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
Write-Output ("`nElevation       : {0}" -f $(if($isAdmin){"Administrator (OK for live collection)"}else{"NOT elevated (required for live collection)"}))
