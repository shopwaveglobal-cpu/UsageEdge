$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Quota.ps1')
$o = '{"result":{"rateLimits":{"primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":2000000000},"secondary":{"usedPercent":80,"windowDurationMins":10080,"resetsAt":2000001000}}}}' | ConvertFrom-Json
$r = @(Convert-CodexLimits $o)
if ($r.Count -ne 2 -or $r[0].Remaining -ne 75 -or $r[1].Remaining -ne 20) { throw '사용량 변환 실패' }
if ((Get-CompactSummary $r) -ne '5H 75%  |  주 20%') { throw '접힌 상태 사용량 표시 실패' }
if ((Get-CompactSummary @()) -ne '5H —  |  주 —') { throw '접힌 상태 빈값 표시 실패' }
$o = '{"result":{"rateLimits":{"primary":{"usedPercent":true,"windowDurationMins":300},"secondary":{"usedPercent":120,"windowDurationMins":10080}}}}' | ConvertFrom-Json
if (@(Convert-CodexLimits $o).Count -ne 0) { throw '잘못된 수치가 표시됨' }
$now = Get-Date
$expired = @([pscustomobject]@{Minutes=300; Remaining=75; Reset=$now.AddSeconds(-1)}, [pscustomobject]@{Minutes=10080; Remaining=20; Reset=$now.AddSeconds(60)})
if ((Get-CompactSummary $expired $now) -ne '5H —  |  주 20%') { throw '초기화 지난 사용량이 계속 표시됨' }
if ($null -ne (Get-VisibleRemaining $expired[0] $now)) { throw '초기화 지난 수치를 최신으로 표시함' }
$failed = Resolve-RefreshState $r @{error='offline'}
if (-not $failed.Stale -or $failed.Windows.Count -ne 2 -or $failed.Windows[0].Remaining -ne 75) { throw '조회 실패 시 이전 관측값이 사라짐' }
$initial = Resolve-RefreshState @() @{error='offline'}
if ($initial.Stale -or $initial.Windows.Count -ne 0) { throw '첫 실패 상태가 잘못됨' }
$recovered = Resolve-RefreshState $r @{windows=@($r[1])}
if ($recovered.Stale -or $recovered.Windows.Count -ne 1 -or $recovered.Windows[0].Remaining -ne 20) { throw '새 관측값 복구 실패' }
$kimi = '{"code":0,"data":{"kind":"ok","quota":{"usages":{"limit5h":{"usedRatio":0.25,"resetAt":"2026-11-14T12:00:00Z"},"limit7d":{"usedRatio":0.8}}}}}' | ConvertFrom-Json
$k = @(Convert-KimiLimits $kimi)
if ($k.Count -ne 2 -or $k[0].Remaining -ne 75 -or $k[1].Remaining -ne 20 -or $null -eq $k[0].Reset) { throw 'Kimi 사용량 변환 실패' }
foreach ($invalid in @(
 '{"code":1,"data":{"kind":"ok","quota":{"usages":{"limit5h":{"usedRatio":0}}}}}',
 '{"code":0,"data":{"kind":"error","quota":{"usages":{"limit5h":{"usedRatio":0}}}}}',
 '{"code":0,"data":{"kind":"ok","quota":{"usages":{"limit5h":{"usedRatio":true}}}}}',
 '{"code":0,"data":{"kind":"ok","quota":{"usages":{"limit5h":{"usedRatio":1.1}}}}}'
)) { if (@(Convert-KimiLimits ($invalid | ConvertFrom-Json)).Count -ne 0) { throw 'Kimi 잘못된 수치가 표시됨' } }
$copilot = '{"usageItems":[{"product":"Copilot AI Credits","unitType":"ai-credits","grossQuantity":12.5},{"product":"Copilot AI Credits","unitType":"ai-credits","grossQuantity":7.25}]}' | ConvertFrom-Json
if ((Convert-CopilotBilling $copilot) -ne '이번 달 보고된 사용 19.75 크레딧') { throw 'Copilot 청구 변환 실패' }
if ((Convert-CopilotBilling ('{"usageItems":[]}' | ConvertFrom-Json)) -ne '이번 달 청구 기록 없음') { throw 'Copilot 빈 청구 처리 실패' }
if ($null -ne (Convert-CopilotBilling ('{"usageItems":[{"product":"Copilot AI Credits","unitType":"ai-credits","grossQuantity":true}]}' | ConvertFrom-Json))) { throw 'Copilot 잘못된 수치가 표시됨' }
if ($null -ne (Convert-CopilotBilling ('{"usageItems":[{"product":"Other","unitType":"tokens","grossQuantity":3}]}' | ConvertFrom-Json))) { throw 'Copilot 다른 단위를 표시함' }
$claude = '{"rate_limits":{"five_hour":{"used_percentage":25,"resets_at":2000000000},"seven_day":{"used_percentage":80}}}' | ConvertFrom-Json
$c = @(Convert-ClaudeLimits $claude)
if ($c.Count -ne 2 -or $c[0].Remaining -ne 75 -or $c[1].Remaining -ne 20 -or $null -eq $c[0].Reset -or $null -ne $c[1].Reset) { throw 'Claude usage conversion failed' }
foreach ($invalid in @(
 '{"rate_limits":{"five_hour":{"used_percentage":true}}}',
 '{"rate_limits":{"five_hour":{"used_percentage":-1}}}',
 '{"rate_limits":{"five_hour":{"used_percentage":101}}}',
 '{"rate_limits":{}}'
)) { if (@(Convert-ClaudeLimits ($invalid | ConvertFrom-Json)).Count -ne 0) { throw 'Invalid Claude value displayed' } }
$dateValue = [DateTime]::UtcNow
$badClaude = @{rate_limits=@{five_hour=@{used_percentage=$dateValue}}}
$badKimi = @{code=0; data=@{kind='ok'; quota=@{usages=@{limit5h=@{usedRatio=$dateValue}}}}}
$badCodex = @{result=@{rateLimits=@{primary=@{usedPercent=$dateValue; windowDurationMins=300}}}}
if (@(Convert-ClaudeLimits $badClaude).Count -or @(Convert-KimiLimits $badKimi).Count -or @(Convert-CodexLimits $badCodex).Count) { throw 'Non-numeric value accepted' }
$currentEpoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$fresh = @{captured_at=$currentEpoch; rate_limits=@{five_hour=@{used_percentage=25; resets_at=2000000000}}}
$readFresh = Convert-ClaudeSnapshot $fresh $currentEpoch
if ($readFresh.State -ne 'fresh' -or $readFresh.Windows.Count -ne 1 -or $readFresh.Windows[0].Remaining -ne 75) { throw 'Claude fresh snapshot failed' }
$readStale = Convert-ClaudeSnapshot $fresh ($currentEpoch + 901)
if ($readStale.State -ne 'stale') { throw 'Claude stale snapshot failed' }
$readExpired = Convert-ClaudeSnapshot $fresh ($currentEpoch + 86401)
if ($readExpired.State -ne 'expired' -or $readExpired.Windows.Count -ne 0) { throw 'Claude expired snapshot failed' }
$readFuture = Convert-ClaudeSnapshot $fresh ($currentEpoch - 301)
if ($readFuture.State -ne 'invalid') { throw 'Claude future snapshot accepted' }
foreach ($minutes in @([double]::NaN, [double]::PositiveInfinity, 1e100, 300.5)) {
 $badDuration=@{result=@{rateLimits=@{primary=@{usedPercent=25; windowDurationMins=$minutes}}}}
 if (@(Convert-CodexLimits $badDuration).Count -ne 0) { throw 'Invalid Codex duration accepted' }
}
Write-Output '사용량 계산 검사 통과' 
