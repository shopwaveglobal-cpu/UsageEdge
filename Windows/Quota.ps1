function Convert-CodexLimits($obj) {
    $result = @()
    foreach ($name in @('primary','secondary')) {
        $w = $obj.result.rateLimits.$name
        if ($null -eq $w -or $w.usedPercent -is [bool] -or $w.usedPercent -isnot [ValueType]) { continue }
        $used = [double]$w.usedPercent
        $minutes = $w.windowDurationMins
        if ([double]::IsNaN($used) -or $used -lt 0 -or $used -gt 100 -or $minutes -is [bool] -or $minutes -isnot [ValueType] -or $minutes -le 0) { continue }
        $reset = $null
        if ($w.resetsAt -is [ValueType] -and $w.resetsAt -isnot [bool]) {
            try { $reset = [DateTimeOffset]::FromUnixTimeSeconds([long]$w.resetsAt).LocalDateTime } catch {}
        }
        $label = switch ($minutes) { 300 {'5시간'} 10080 {'주간'} default {"$minutes 분"} }
        $result += [pscustomobject]@{ Minutes=[int]$minutes; Label=$label; Remaining=[math]::Round(100-$used); Reset=$reset }
    }
    return $result
}

function Get-CompactSummary($windows) {
    $five = @($windows | Where-Object { $_.Minutes -eq 300 } | Select-Object -First 1)
    $week = @($windows | Where-Object { $_.Minutes -eq 10080 } | Select-Object -First 1)
    $fiveText = if ($five.Count) { "$($five[0].Remaining)%" } else { '—' }
    $weekText = if ($week.Count) { "$($week[0].Remaining)%" } else { '—' }
    return "5H $fiveText  |  주 $weekText"
}

function Resolve-RefreshState($previous, $result) {
    if ($result -and $result.windows -and @($result.windows).Count -gt 0) {
        return @{ Windows = @($result.windows); Stale = $false }
    }
    return @{ Windows = @($previous); Stale = (@($previous).Count -gt 0) }
}
