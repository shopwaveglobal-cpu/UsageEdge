. (Join-Path $PSScriptRoot 'Quota.ps1')
$o = '{"result":{"rateLimits":{"primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":2000000000},"secondary":{"usedPercent":80,"windowDurationMins":10080,"resetsAt":2000001000}}}}' | ConvertFrom-Json
$r = @(Convert-CodexLimits $o)
if ($r.Count -ne 2 -or $r[0].Remaining -ne 75 -or $r[1].Remaining -ne 20) { throw '사용량 변환 실패' }
if ((Get-CompactSummary $r) -ne '5H 75%  |  주 20%') { throw '접힌 상태 사용량 표시 실패' }
if ((Get-CompactSummary @()) -ne '5H —  |  주 —') { throw '접힌 상태 빈값 표시 실패' }
$o = '{"result":{"rateLimits":{"primary":{"usedPercent":true,"windowDurationMins":300},"secondary":{"usedPercent":120,"windowDurationMins":10080}}}}' | ConvertFrom-Json
if (@(Convert-CodexLimits $o).Count -ne 0) { throw '잘못된 수치가 표시됨' }
Write-Output '사용량 계산 검사 통과'
