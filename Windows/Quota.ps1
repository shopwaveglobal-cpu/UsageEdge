function Test-QuotaNumber($value) {
    if ($null -eq $value) { return $false }
    return $value.GetType() -in @([byte], [sbyte], [int16], [uint16], [int32], [uint32], [int64], [uint64], [single], [double], [decimal])
}

function Convert-CodexLimits($obj) {
    $result = @()
    foreach ($name in @('primary','secondary')) {
        $w = $obj.result.rateLimits.$name
        if ($null -eq $w -or -not (Test-QuotaNumber $w.usedPercent)) { continue }
        $used = [double]$w.usedPercent
        $minutes = $w.windowDurationMins
        if ([double]::IsNaN($used) -or [double]::IsInfinity($used) -or $used -lt 0 -or $used -gt 100 -or -not (Test-QuotaNumber $minutes)) { continue }
        $minutes = [double]$minutes
        if ([double]::IsNaN($minutes) -or [double]::IsInfinity($minutes) -or $minutes -le 0 -or $minutes -gt [int]::MaxValue -or [Math]::Truncate($minutes) -ne $minutes) { continue }
        $reset = $null
        if ((Test-QuotaNumber $w.resetsAt)) {
            try { $reset = [DateTimeOffset]::FromUnixTimeSeconds([long]$w.resetsAt).LocalDateTime } catch {}
        }
        $label = switch ($minutes) { 300 {'5시간'} 10080 {'주간'} default {"$minutes 분"} }
        $result += [pscustomobject]@{ Minutes=[int]$minutes; Label=$label; Remaining=[math]::Round(100-$used); Reset=$reset }
    }
    return $result
}

function Get-VisibleRemaining($window, [DateTime]$now = (Get-Date)) {
    if ($null -eq $window) { return $null }
    if ($window.Reset -and $window.Reset -le $now) { return $null }
    return $window.Remaining
}

function Get-CompactSummary($windows, [DateTime]$now = (Get-Date)) {
    $five = @($windows | Where-Object { $_.Minutes -eq 300 } | Select-Object -First 1)
    $week = @($windows | Where-Object { $_.Minutes -eq 10080 } | Select-Object -First 1)
    $fiveValue = if ($five.Count) { Get-VisibleRemaining $five[0] $now } else { $null }
    $weekValue = if ($week.Count) { Get-VisibleRemaining $week[0] $now } else { $null }
    $fiveText = if ($null -ne $fiveValue) { "$fiveValue%" } else { '—' }
    $weekText = if ($null -ne $weekValue) { "$weekValue%" } else { '—' }
    return "5H $fiveText  |  주 $weekText"
}

function Resolve-RefreshState($previous, $result) {
    if ($result -and $result.windows -and @($result.windows).Count -gt 0) {
        return @{ Windows = @($result.windows); Stale = $false }
    }
    return @{ Windows = @($previous); Stale = (@($previous).Count -gt 0) }
}

function Convert-KimiLimits($obj) {
    if ($null -eq $obj -or -not (Test-QuotaNumber $obj.code) -or $obj.code -ne 0 -or $obj.data.kind -ne 'ok') { return @() }
    $usages = $obj.data.quota.usages
    $result = @()
    foreach ($entry in @(@{Name='limit5h'; Minutes=300; Label='5시간'}, @{Name='limit7d'; Minutes=10080; Label='주간'})) {
        $item = $usages.($entry.Name)
        if ($null -eq $item -or -not (Test-QuotaNumber $item.usedRatio)) { continue }
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

function Convert-CopilotBilling($obj) {
    if ($null -eq $obj -or $null -eq $obj.usageItems -or $obj.usageItems -isnot [array]) { return $null }
    if ($obj.usageItems.Count -eq 0) { return '이번 달 청구 기록 없음' }
    $sum = 0.0
    foreach ($item in $obj.usageItems) {
        if ($item.product -ne 'Copilot AI Credits' -or $item.unitType -ne 'ai-credits' -or -not (Test-QuotaNumber $item.grossQuantity)) { return $null }
        $value = [double]$item.grossQuantity
        if ([double]::IsNaN($value) -or [double]::IsInfinity($value) -or $value -lt 0) { return $null }
        $sum += $value
        if ([double]::IsInfinity($sum) -or $sum -gt 1000000000000) { return $null }
    }
    return '이번 달 보고된 사용 {0:F2} 크레딧' -f $sum
}

function Convert-ClaudeLimits($obj) {
    $result = @()
    foreach ($entry in @(@{Name='five_hour'; Minutes=300; Label='5시간'}, @{Name='seven_day'; Minutes=10080; Label='주간'})) {
        $item = $obj.rate_limits.($entry.Name)
        if ($null -eq $item -or -not (Test-QuotaNumber $item.used_percentage)) { continue }
        $used = [double]$item.used_percentage
        if ([double]::IsNaN($used) -or [double]::IsInfinity($used) -or $used -lt 0 -or $used -gt 100) { continue }
        $reset = $null
        if ((Test-QuotaNumber $item.resets_at)) {
            try { $reset = [DateTimeOffset]::FromUnixTimeSeconds([long]$item.resets_at).LocalDateTime } catch {}
        }
        $result += [pscustomobject]@{Minutes=$entry.Minutes; Label=$entry.Label; Remaining=[int][Math]::Round(100-$used, [MidpointRounding]::AwayFromZero); Reset=$reset}
    }
    return $result
}

function Convert-ClaudeSnapshot($snapshot, [double]$nowEpoch) {
    if ($null -eq $snapshot -or -not (Test-QuotaNumber $snapshot.captured_at)) { return @{State='invalid'; Windows=@()} }
    $captured = [double]$snapshot.captured_at
    if ([double]::IsNaN($captured) -or [double]::IsInfinity($captured) -or $captured -le 0 -or $captured -gt ($nowEpoch + 300)) { return @{State='invalid'; Windows=@()} }
    $age = $nowEpoch - $captured
    if ($age -gt 86400) { return @{State='expired'; Windows=@()} }
    $windows = @(Convert-ClaudeLimits $snapshot)
    if ($windows.Count -eq 0) { return @{State='invalid'; Windows=@()} }
    $state = if ($age -gt 900) { 'stale' } else { 'fresh' }
    return @{State=$state; Windows=$windows}
}
