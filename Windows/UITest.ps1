$ErrorActionPreference = 'Stop'
$source = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'UsageEdge.ps1'))
$quotaFile = (Join-Path $PSScriptRoot 'Quota.ps1').Replace("'", "''")
$source = $source.Replace(". (Join-Path `$PSScriptRoot 'Quota.ps1')", ". '$quotaFile'")
$source = $source.Replace('$form.Add_Shown({Start-Refresh; $timer.Start()})', '')
$entry = '[System.Windows.Forms.Application]::Run($form)'
if (-not $source.Contains($entry)) { throw 'App entry point not found' }
$checks = @'
try {
 $form.Show(); [System.Windows.Forms.Application]::DoEvents()
 if ($form.Width -ne 240 -or $form.Height -ne 320) { throw 'Expanded dimensions incorrect' }
 $collapse.PerformClick(); [System.Windows.Forms.Application]::DoEvents()
 if ($form.Width -ne 140 -or $form.Height -ne 66 -or -not $compactInfo.Visible) { throw 'Collapse failed' }
 $collapse.PerformClick(); [System.Windows.Forms.Application]::DoEvents()
 if ($form.Width -ne 240 -or $form.Height -ne 320 -or $compactInfo.Visible) { throw 'Expand failed' }
 Write-Output 'Windows form collapse and expand checks passed'
} finally { $form.Close(); $form.Dispose() }
'@
$source = $source.Replace($entry, $checks)
& ([scriptblock]::Create($source))
