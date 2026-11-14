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

function Convert-KimiLimits($obj) {
    if ($null -eq $obj -or $obj.code -is [bool] -or $obj.code -isnot [ValueType] -or $obj.code -ne 0 -or $obj.data.kind -ne 'ok') { return @() }
    $usages = $obj.data.quota.usages
    $result = @()
    foreach ($entry in @(@{Name='limit5h'; Minutes=300; Label='5시간'}, @{Name='limit7d'; Minutes=10080; Label='주간'})) {
        $item = $usages.($entry.Name)
        if ($null -eq $item -or $item.usedRatio -is [bool] -or $item.usedRatio -isnot [ValueType]) { continue }
        $ratio = [double]$item.usedRatio
        if ([double]::IsNaN($ratio) -or [double]::IsInfinity($ratio) -or $ratio -lt 0 -or $ratio -gt 1) { continue }
        $reset = $null
        if ($item.resetAt -is [DateTime]) { $reset = $item.resetAt.ToLocalTime() }
        elseif ($item.resetAt -is [string]) {
            $parsed = [DateTimeOffset]::MinValue
            if ([DateTimeOffset]::TryParse($item.resetAt, [ref]$parsed)) { $reset = $parsed.LocalDateTime }
        }
        $result += [pscustomobject]@{Minutes=$entry.Minutes; Label=$entry.Label; Remaining=[int][Math]::Round((1-$ratio)*100, [MidpointRounding]::AwayFromZero); Reset=$reset}
    }
    return $result
}
