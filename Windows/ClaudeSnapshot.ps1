function Get-ClaudeSnapshot {
    try {
        $path = Join-Path $env:LOCALAPPDATA 'UsageEdge\ClaudeStatus\snapshot.dat'
        if (-not (Test-Path -LiteralPath $path)) { return @{State='waiting'; Windows=@()} }
        $file = Get-Item -LiteralPath $path -Force -ErrorAction Stop
        if ($file.PSIsContainer -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $file.Length -lt 1 -or $file.Length -gt 1048576) { return @{State='invalid'; Windows=@()} }
        Add-Type -AssemblyName System.Security
        $bytes = [IO.File]::ReadAllBytes($file.FullName)
        $plain = [Security.Cryptography.ProtectedData]::Unprotect($bytes, $null, [Security.Cryptography.DataProtectionScope]::CurrentUser)
        $snapshot = [Text.Encoding]::UTF8.GetString($plain) | ConvertFrom-Json -ErrorAction Stop
        return Convert-ClaudeSnapshot $snapshot ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
    } catch { return @{State='invalid'; Windows=@()} }
}
