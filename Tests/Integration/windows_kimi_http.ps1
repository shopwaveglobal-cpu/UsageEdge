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
$file = Join-Path ([IO.Path]::GetTempPath()) ('usageedge-kimi-' + [Guid]::NewGuid().ToString('N'))
try {
    [IO.File]::WriteAllText($file, "good`n")
    $fromFile = Get-KimiUsageFromFile $Port $file
    if ($fromFile.Windows.Count -ne 2 -or $fromFile.Windows[0].Remaining -ne 75) { throw 'Token file request failed' }
    [IO.File]::WriteAllText($file, ('x' * 4097))
    if ((Get-KimiUsageFromFile $Port $file).Error -ne 'tokenfile') { throw 'Oversized token file accepted' }
    [IO.File]::WriteAllText($file, "bad token")
    if ((Get-KimiUsageFromFile $Port $file).Error -ne 'tokenfile') { throw 'Invalid token file accepted' }
} finally { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue }
Write-Output 'Windows Kimi local HTTP tests passed'
