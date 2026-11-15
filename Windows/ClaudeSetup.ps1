function Set-ClaudeConnection([string]$HomePath, [string]$Source, [string]$Action) {
    $base = Join-Path $HomePath '.claude'
    $settingsPath = Join-Path $base 'settings.json'
    $helperDir = Join-Path $base 'usageedge'
    $helper = Join-Path $helperDir 'ClaudeStatus.ps1'
    $command = 'powershell -NoProfile -ExecutionPolicy Bypass -File ~/.claude/usageedge/ClaudeStatus.ps1'
    if ($Action -notin @('install', 'uninstall')) { return 'invalid' }
    try {
        foreach ($path in @($base, $settingsPath, $helperDir, $helper)) {
            if (Test-Path -LiteralPath $path) {
                $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
                if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { return 'invalid' }
            }
        }
        $original = if ([IO.File]::Exists($settingsPath)) { [IO.File]::ReadAllBytes($settingsPath) } else { $null }
        if ($null -ne $original -and $original.Length -gt 1048576) { return 'invalid' }
        if ($null -ne $original) {
            try { $settings = [Text.Encoding]::UTF8.GetString($original).TrimStart([char]0xFEFF) | ConvertFrom-Json -ErrorAction Stop }
            catch { return 'invalid' }
            if ($null -eq $settings -or $settings -isnot [pscustomobject]) { return 'invalid' }
        } else { $settings = [pscustomobject]@{} }
        $existing = $settings.PSObject.Properties['statusLine']
        $ours = $null -ne $existing -and $existing.Value.type -ceq 'command' -and $existing.Value.command -ceq $command -and @($existing.Value.PSObject.Properties).Count -eq 2
        if ($existing -and -not $ours) { return 'conflict' }
        if ($Action -eq 'uninstall' -and -not $ours) { return 'removed' }
        if ($Action -eq 'install') {
            if (-not [IO.File]::Exists($Source)) { return 'invalid' }
            if ([IO.File]::Exists($helper) -and -not $ours) { return 'conflict' }
            [void][IO.Directory]::CreateDirectory($helperDir)
            $helperTemp = Join-Path $helperDir ('.helper-' + [Guid]::NewGuid().ToString('N'))
            try {
                [IO.File]::WriteAllBytes($helperTemp, [IO.File]::ReadAllBytes($Source))
                if ([IO.File]::Exists($helper)) { [IO.File]::Replace($helperTemp, $helper, [System.Management.Automation.Language.NullString]::Value) } else { [IO.File]::Move($helperTemp, $helper) }
            } finally { if ([IO.File]::Exists($helperTemp)) { [IO.File]::Delete($helperTemp) } }
            if ($ours) { return 'installed' }
            $settings | Add-Member -MemberType NoteProperty -Name statusLine -Value ([pscustomobject]@{type='command'; command=$command})
        } else { $settings.PSObject.Properties.Remove('statusLine') }
        $temp = Join-Path $base ('.settings-' + [Guid]::NewGuid().ToString('N'))
        try {
            $json = $settings | ConvertTo-Json -Depth 100
            [IO.File]::WriteAllText($temp, $json + "`n", (New-Object Text.UTF8Encoding($false)))
            $current = if ([IO.File]::Exists($settingsPath)) { [IO.File]::ReadAllBytes($settingsPath) } else { $null }
            if (($null -eq $original) -ne ($null -eq $current)) { return 'changed' }
            if ($null -ne $original -and [Convert]::ToBase64String($original) -cne [Convert]::ToBase64String($current)) { return 'changed' }
            if ($null -ne $current) { [IO.File]::Replace($temp, $settingsPath, [System.Management.Automation.Language.NullString]::Value) } else { [IO.File]::Move($temp, $settingsPath) }
        } finally { if ([IO.File]::Exists($temp)) { [IO.File]::Delete($temp) } }
        if ($Action -eq 'install') { return 'installed' }
        return 'removed'
    } catch { return 'error' }
}

function Get-ClaudeConnectionState([string]$HomePath) {
    $base = Join-Path $HomePath '.claude'
    $path = Join-Path $base 'settings.json'
    $helper = Join-Path $base 'usageedge/ClaudeStatus.ps1'
    $command = 'powershell -NoProfile -ExecutionPolicy Bypass -File ~/.claude/usageedge/ClaudeStatus.ps1'
    try {
        if (-not [IO.File]::Exists($path)) { return 'missing' }
        foreach ($entry in @($base, $path, (Split-Path $helper), $helper)) {
            if ((Test-Path -LiteralPath $entry) -and ((Get-Item -LiteralPath $entry -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { return 'invalid' }
        }
        $file = Get-Item -LiteralPath $path -ErrorAction Stop
        if ($file.Length -gt 1048576) { return 'invalid' }
        $obj = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($path)).TrimStart([char]0xFEFF) | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $obj -or $obj -isnot [pscustomobject]) { return 'invalid' }
        $entry = $obj.PSObject.Properties['statusLine']
        if (-not $entry) { return 'missing' }
        if ($entry.Value.type -cne 'command' -or $entry.Value.command -cne $command -or @($entry.Value.PSObject.Properties).Count -ne 2) { return 'conflict' }
        if (-not [IO.File]::Exists($helper)) { return 'invalid' }
        return 'connected'
    } catch { return 'invalid' }
}
