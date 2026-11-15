param([switch]$SanitizeOnly)
$ErrorActionPreference = 'Stop'
function Test-Number($value) {
    if ($null -eq $value) { return $false }
    return $value.GetType() -in @([byte], [sbyte], [int16], [uint16], [int32], [uint32], [int64], [uint64], [single], [double], [decimal])
}
try {
    $buffer = New-Object char[] 1000001
    $length = 0
    while ($length -lt $buffer.Length) {
        $read = [Console]::In.Read($buffer, $length, $buffer.Length - $length)
        if ($read -eq 0) { break }
        $length += $read
    }
    if ($length -gt 1000000) { throw 'input too large' }
    $data = (-join $buffer[0..($length-1)]) | ConvertFrom-Json
    $limits = @{}
    foreach ($name in @('five_hour', 'seven_day')) {
        $item = $data.rate_limits.$name
        if ($null -eq $item -or -not (Test-Number $item.used_percentage)) { continue }
        $value = [double]$item.used_percentage
        if ([double]::IsNaN($value) -or [double]::IsInfinity($value) -or $value -lt 0 -or $value -gt 100) { continue }
        $clean = @{ used_percentage = $value }
        if (Test-Number $item.resets_at) {
            $reset = [double]$item.resets_at
            if (-not [double]::IsNaN($reset) -and -not [double]::IsInfinity($reset) -and $reset -gt 0 -and $reset -lt 253402300800) { $clean.resets_at = $reset }
        }
        $limits[$name] = $clean
    }
    if ($SanitizeOnly) { ConvertTo-Json -InputObject $limits -Compress -Depth 5; exit 0 }
    if ($limits.Count -gt 0) {
        Add-Type -AssemblyName System.Security
        $snapshot = @{ captured_at = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds(); rate_limits = $limits } | ConvertTo-Json -Compress -Depth 5
        $bytes = [Text.Encoding]::UTF8.GetBytes($snapshot)
        $encrypted = [Security.Cryptography.ProtectedData]::Protect($bytes, $null, [Security.Cryptography.DataProtectionScope]::CurrentUser)
        $directory = Join-Path $env:LOCALAPPDATA 'UsageEdge\ClaudeStatus'
        [void][IO.Directory]::CreateDirectory($directory)
        $target = Join-Path $directory 'snapshot.dat'
        $temp = Join-Path $directory ('.snapshot-' + [Guid]::NewGuid().ToString('N'))
        try {
            [IO.File]::WriteAllBytes($temp, $encrypted)
            if ([IO.File]::Exists($target)) { [IO.File]::Replace($temp, $target, [System.Management.Automation.Language.NullString]::Value) } else { [IO.File]::Move($temp, $target) }
        } finally { if ([IO.File]::Exists($temp)) { [IO.File]::Delete($temp) } }
    }
} catch { if ($SanitizeOnly) { Write-Output '{}'; exit 0 } }
Write-Output 'Claude'
