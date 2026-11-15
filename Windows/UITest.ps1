$ErrorActionPreference = 'Stop'
$source = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'UsageEdge.ps1'))
$quotaFile = (Join-Path $PSScriptRoot 'Quota.ps1').Replace("'", "''")
$source = $source.Replace(". (Join-Path `$PSScriptRoot 'Quota.ps1')", ". '$quotaFile'")
foreach ($name in @('ClaudeSetup.ps1','ClaudeSnapshot.ps1')) {
 $path=(Join-Path $PSScriptRoot $name).Replace("'", "''")
 $source=$source.Replace(". (Join-Path `$PSScriptRoot '$name')", ". '$path'")
}
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
$source = $source.Replace('$form.Add_Shown({Update-KimiLayout; Update-ClaudeView; Start-Refresh; Start-KimiRefresh; Start-CopilotRefresh; $timer.Start()})', '')
$source = $source.Replace('$script:claudeState=Get-ClaudeConnectionState $script:claudeHome', "`$script:claudeState='missing'")
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
 function Get-ClaudeSnapshot { return @{State='fresh'; Windows=@([pscustomobject]@{Minutes=300; Remaining=80; Reset=$null}, [pscustomobject]@{Minutes=10080; Remaining=45; Reset=$null})} }
 $script:claudeState='connected'; Update-ClaudeView; Update-KimiLayout
 if ($claude.Text -notmatch '80%' -or $claude.Text -notmatch '45%') { throw 'Claude expanded values missing' }
 $collapse.PerformClick(); [System.Windows.Forms.Application]::DoEvents()
 if (-not $compactClaude.Visible -or $compactClaude.Text -notmatch '80%' -or $form.Height -ne 84) { throw 'Claude compact values missing' }
 $script:claudeState='missing'; $claude.Text='Claude'; $collapse.PerformClick(); [System.Windows.Forms.Application]::DoEvents()

 $timer.Interval = 50; $timer.Start(); Start-Refresh
 $deadline = [DateTime]::UtcNow.AddSeconds(30)
 while ([DateTime]::UtcNow -lt $deadline -and ($script:job -or $script:windows.Count -eq 0)) {
  [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 50
 }
 if ($script:windows.Count -ne 2 -or $script:windows[0].Remaining -ne 75 -or $script:windows[1].Remaining -ne 20) { throw "Fake Codex refresh failed: $($status.Text)" }
 if ($compactInfo.Text -ne (Get-CompactSummary $script:windows)) { throw 'Compact values did not update' }
 if ($env:USAGEEDGE_TEST_KIMI_PORT) {
  $compactKimi.Text='K  5H 99% | 주 99%'
  $kimiConnect.PerformClick()
  if ($compactKimi.Text -match '99%') { throw 'Old Kimi values remain visible during reconnect' }
  if ($script:kimiPort -ne [int]$env:USAGEEDGE_TEST_KIMI_PORT -or (Get-ItemProperty -LiteralPath $script:kimiKey -Name KimiPort).KimiPort -ne $script:kimiPort) { throw 'Kimi connection settings not persisted' }
  $deadline=[DateTime]::UtcNow.AddSeconds(30)
  while ([DateTime]::UtcNow -lt $deadline -and ($script:kimiJob -or $script:kimiWindows.Count -eq 0)) {
   [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 50
  }
  if ($script:kimiWindows.Count -ne 2 -or $script:kimiWindows[0].Remaining -ne 75 -or $script:kimiWindows[1].Remaining -ne 20) { throw "Fake Kimi refresh failed: $($kimiLabel.Text)" }
  $collapse.PerformClick(); [System.Windows.Forms.Application]::DoEvents()
  if (-not $compactKimi.Visible -or $compactKimi.Text -notmatch '75%') { throw 'Compact Kimi values missing' }
  $deadline=[DateTime]::UtcNow.AddSeconds(8)
  while ([DateTime]::UtcNow -lt $deadline -and $script:kimiNotified.Count -eq 0) {
   [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 50
  }
  if ($script:kimiNotified.Count -ne 1) { throw 'Kimi reset notification was not triggered' }
  $kimiDisconnect.PerformClick(); [System.Windows.Forms.Application]::DoEvents()
  if ($script:kimiPort -ne 0 -or $script:kimiWindows.Count -ne 0 -or $compactKimi.Visible) { throw 'Kimi disconnect failed' }
  if ($null -ne (Get-ItemProperty -LiteralPath $script:kimiKey -Name KimiPort -ErrorAction SilentlyContinue)) { throw 'Kimi port remained after disconnect' }
  Write-Output 'Windows Kimi widget checks passed'
 }
 if ($env:USAGEEDGE_TEST_COPILOT -eq '1') {
  $copilotToggle.PerformClick(); [System.Windows.Forms.Application]::DoEvents()
  if (-not $script:copilotEnabled -or (Get-ItemProperty -LiteralPath $script:kimiKey -Name CopilotEnabled).CopilotEnabled -ne 1) { throw 'Copilot toggle did not persist' }
  $deadline=[DateTime]::UtcNow.AddSeconds(30)
  while ([DateTime]::UtcNow -lt $deadline -and ($script:copilotJob -or $copilotLabel.Text -notmatch '19.75')) {
   [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 50
  }
  if ($copilotLabel.Text -notmatch '19.75') { throw "Fake Copilot refresh failed: $($copilotLabel.Text)" }
  if (-not $script:collapsed) { $collapse.PerformClick(); [System.Windows.Forms.Application]::DoEvents() }
  if (-not $compactCopilot.Visible -or $compactCopilot.Text -notmatch '19.75') { throw 'Compact Copilot value missing' }
  $copilotToggle.PerformClick(); [System.Windows.Forms.Application]::DoEvents()
  if ($script:copilotEnabled -or $compactCopilot.Visible -or (Get-ItemProperty -LiteralPath $script:kimiKey -Name CopilotEnabled).CopilotEnabled -ne 0) { throw 'Copilot disconnect failed' }
  Write-Output 'Windows Copilot widget checks passed'
 }
 Write-Output 'Windows form and fake Codex refresh checks passed'
} finally { $form.Close(); $form.Dispose(); $env:PATH = $oldPath; Remove-Item -LiteralPath $testKey -Recurse -Force -ErrorAction SilentlyContinue; Remove-Item -LiteralPath $fakeDir -Recurse -Force -ErrorAction SilentlyContinue }
'@
$source = $source.Replace($entry, $checks)
& ([scriptblock]::Create($source))
