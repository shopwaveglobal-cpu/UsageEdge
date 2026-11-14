param([int]$Port)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../../Windows/Quota.ps1')
. (Join-Path $PSScriptRoot '../../Windows/Kimi.ps1')
$ok = Get-KimiUsage $Port 'good'
if ($ok.Windows.Count -ne 2 -or $ok.Windows[0].Remaining -ne 75 -or $ok.Windows[1].Remaining -ne 20) { throw 'Quota response failed' }
if ((Get-KimiUsage $Port 'bad').Error -ne 'auth') { throw 'Authentication failure not reported' }
if ((Get-KimiUsage $Port 'redirect').Error -ne 'http') { throw 'Redirect not rejected' }
if ((Get-KimiUsage 0 'good').Error -ne 'input') { throw 'Invalid port accepted' }
if ((Get-KimiUsage $Port "bad`ntoken").Error -ne 'input') { throw 'Invalid token accepted' }
Write-Output 'Windows Kimi local HTTP tests passed'
