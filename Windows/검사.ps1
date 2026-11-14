. (Join-Path $PSScriptRoot 'Quota.ps1')
$o = '{"result":{"rateLimits":{"primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":2000000000},"secondary":{"usedPercent":80,"windowDurationMins":10080,"resetsAt":2000001000}}}}' | ConvertFrom-Json
$r = @(Convert-CodexLimits $o)
if ($r.Count -ne 2 -or $r[0].Remaining -ne 75 -or $r[1].Remaining -ne 20) { throw '사용량 변환 실패' }
if ((Get-CompactSummary $r) -ne '5H 75%  |  주 20%') { throw '접힌 상태 사용량 표시 실패' }
if ((Get-CompactSummary @()) -ne '5H —  |  주 —') { throw '접힌 상태 빈값 표시 실패' }
$o = '{"result":{"rateLimits":{"primary":{"usedPercent":true,"windowDurationMins":300},"secondary":{"usedPercent":120,"windowDurationMins":10080}}}}' | ConvertFrom-Json
if (@(Convert-CodexLimits $o).Count -ne 0) { throw '잘못된 수치가 표시됨' }
$failed = Resolve-RefreshState $r @{error='offline'}
if (-not $failed.Stale -or $failed.Windows.Count -ne 2 -or $failed.Windows[0].Remaining -ne 75) { throw '조회 실패 시 이전 관측값이 사라짐' }
$initial = Resolve-RefreshState @() @{error='offline'}
if ($initial.Stale -or $initial.Windows.Count -ne 0) { throw '첫 실패 상태가 잘못됨' }
$recovered = Resolve-RefreshState $r @{windows=@($r[1])}
if ($recovered.Stale -or $recovered.Windows.Count -ne 1 -or $recovered.Windows[0].Remaining -ne 20) { throw '새 관측값 복구 실패' }
Write-Output '사용량 계산 검사 통과' 
