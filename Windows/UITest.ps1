$ErrorActionPreference = 'Stop'
$source = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'UsageEdge.ps1'))
$quotaFile = (Join-Path $PSScriptRoot 'Quota.ps1').Replace("'", "''")
$source = $source.Replace(". (Join-Path `$PSScriptRoot 'Quota.ps1')", ". '$quotaFile'")
$rootEscaped = $PSScriptRoot.Replace("'", "''")
$source = $source.Replace('$script:appRoot = $PSScriptRoot', "`$script:appRoot = '$rootEscaped'")
$testKey = 'HKCU:\Software\UsageEdgeTest-' + [Guid]::NewGuid().ToString('N')
$source = $source.Replace("`$script:kimiKey='HKCU:\Software\UsageEdge'", "`$script:kimiKey='$testKey'")
if ($env:USAGEEDGE_TEST_KIMI_PORT) {
 $source = [regex]::Replace($source, '(?m)^ \$chosen=\[Microsoft\.VisualBasic\.Interaction\]::InputBox.*$', ' $chosen=$env:USAGEEDGE_TEST_KIMI_PORT')
}
if ($env:USAGEEDGE_TEST_KIMI_TOKEN) {
 $source = $source.Replace("`$tokenPath=Join-Path ([Environment]::GetFolderPath('UserProfile')) '.kimi-code\server.token'", '$tokenPath=$env:USAGEEDGE_TEST_KIMI_TOKEN')
}
$source = $source.Replace('$script:job=Start-Job -ArgumentList $PSScriptRoot -ScriptBlock {', "`$script:job=Start-Job -ArgumentList '$rootEscaped' -ScriptBlock {")
$source = $source.Replace('$form.Add_Shown({Update-KimiLayout; Start-Refresh; Start-KimiRefresh; $timer.Start()})', '')
$entry = '[System.Windows.Forms.Application]::Run($form)'
if (-not $source.Contains($entry)) { throw 'App entry point not found' }
$checks = @'
$oldPath = $env:PATH
$fakeDir = Join-Path ([IO.Path]::GetTempPath()) ('usageedge-fake-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fakeDir | Out-Null
$fake = @('@echo off', 'echo {"id":2,"result":{"rateLimits":{"primary":{"usedPercent":25,"windowDurationMins":300},"secondary":{"usedPercent":80,"windowDurationMins":10080}}}}', 'ping 127.0.0.1 -n 3 >nul') -join "`r`n"
[IO.File]::WriteAllText((Join-Path $fakeDir 'codex.cmd'), $fake, [Text.Encoding]::ASCII)
$env:PATH = $fakeDir + [IO.Path]::PathSeparator + $oldPath
try {
 $form.Show(); [System.Windows.Forms.Application]::DoEvents()
 if ($form.Width -ne 240 -or $form.Height -ne 320) { throw 'Expanded dimensions incorrect' }
 $collapse.PerformClick(); [System.Windows.Forms.Application]::DoEvents()
 if ($form.Width -ne 140 -or $form.Height -ne 66 -or -not $compactInfo.Visible) { throw 'Collapse failed' }
 $collapse.PerformClick(); [System.Windows.Forms.Application]::DoEvents()
 if ($form.Width -ne 240 -or $form.Height -ne 320 -or $compactInfo.Visible) { throw 'Expand failed' }
 $timer.Interval = 50; $timer.Start(); Start-Refresh
 $deadline = [DateTime]::UtcNow.AddSeconds(30)
 while ([DateTime]::UtcNow -lt $deadline -and ($script:job -or $script:windows.Count -eq 0)) {
  [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 50
 }
 if ($script:windows.Count -ne 2 -or $script:windows[0].Remaining -ne 75 -or $script:windows[1].Remaining -ne 20) { throw "Fake Codex refresh failed: $($status.Text)" }
 if ($compactInfo.Text -ne (Get-CompactSummary $script:windows)) { throw 'Compact values did not update' }
 if ($env:USAGEEDGE_TEST_KIMI_PORT) {
  $kimiConnect.PerformClick()
  if ($script:kimiPort -ne [int]$env:USAGEEDGE_TEST_KIMI_PORT -or (Get-ItemProperty -LiteralPath $script:kimiKey -Name KimiPort).KimiPort -ne $script:kimiPort) { throw 'Kimi connection settings not persisted' }
  $deadline=[DateTime]::UtcNow.AddSeconds(30)
  while ([DateTime]::UtcNow -lt $deadline -and ($script:kimiJob -or $script:kimiWindows.Count -eq 0)) {
   [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 50
  }
  if ($script:kimiWindows.Count -ne 2 -or $script:kimiWindows[0].Remaining -ne 75 -or $script:kimiWindows[1].Remaining -ne 20) { throw "Fake Kimi refresh failed: $($kimiLabel.Text)" }
  $collapse.PerformClick(); [System.Windows.Forms.Application]::DoEvents()
  if (-not $compactKimi.Visible -or $compactKimi.Text -notmatch '75%') { throw 'Compact Kimi values missing' }
  $kimiDisconnect.PerformClick(); [System.Windows.Forms.Application]::DoEvents()
  if ($script:kimiPort -ne 0 -or $script:kimiWindows.Count -ne 0 -or $compactKimi.Visible) { throw 'Kimi disconnect failed' }
  if ($null -ne (Get-ItemProperty -LiteralPath $script:kimiKey -Name KimiPort -ErrorAction SilentlyContinue)) { throw 'Kimi port remained after disconnect' }
  Write-Output 'Windows Kimi widget checks passed'
 }
 Write-Output 'Windows form and fake Codex refresh checks passed'
} finally { $form.Close(); $form.Dispose(); $env:PATH = $oldPath; Remove-Item -LiteralPath $testKey -Recurse -Force -ErrorAction SilentlyContinue; Remove-Item -LiteralPath $fakeDir -Recurse -Force -ErrorAction SilentlyContinue }
'@
$source = $source.Replace($entry, $checks)
& ([scriptblock]::Create($source))
