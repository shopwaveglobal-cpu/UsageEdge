$ErrorActionPreference='Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
. (Join-Path $root 'Windows/ClaudeSetup.ps1')
$homeDir=Join-Path ([IO.Path]::GetTempPath()) ('usageedge-setup-'+[Guid]::NewGuid().ToString('N'))
$source=Join-Path $root 'Windows/ClaudeStatus.ps1'
try {
 [void][IO.Directory]::CreateDirectory((Join-Path $homeDir '.claude'))
 $settings=Join-Path $homeDir '.claude/settings.json'
 [IO.File]::WriteAllText($settings,'{"theme":"dark"}')
 $result=Set-ClaudeConnection $homeDir $source 'install'
 if ($result -ne 'installed') { throw 'Installation failed' }
 if ((Get-ClaudeConnectionState $homeDir) -ne 'connected') { throw 'Connected status not detected' }
 $obj=Get-Content -Raw -LiteralPath $settings | ConvertFrom-Json
 if ($obj.theme -ne 'dark' -or $obj.statusLine.command -notmatch 'usageedge/ClaudeStatus.ps1') { throw 'Settings were not preserved' }
 if (-not (Test-Path (Join-Path $homeDir '.claude/usageedge/ClaudeStatus.ps1'))) { throw 'Collector not installed' }
 if ((Set-ClaudeConnection $homeDir $source 'install') -ne 'installed') { throw 'Idempotent installation failed' }
 if ((Set-ClaudeConnection $homeDir $source 'uninstall') -ne 'removed') { throw 'Removal failed' }
 if ((Get-ClaudeConnectionState $homeDir) -ne 'missing') { throw 'Disconnected status not detected' }
 $obj=Get-Content -Raw -LiteralPath $settings | ConvertFrom-Json
 if ($obj.theme -ne 'dark' -or $null -ne $obj.statusLine) { throw 'Removal modified unrelated settings' }
 [IO.File]::WriteAllText($settings,'{"statusLine":{"type":"command","command":"other"}}')
 $before=[IO.File]::ReadAllBytes($settings)
 if ((Set-ClaudeConnection $homeDir $source 'install') -ne 'conflict') { throw 'Existing statusline not detected' }
 if ([Convert]::ToBase64String($before) -ne [Convert]::ToBase64String([IO.File]::ReadAllBytes($settings))) { throw 'Existing statusline modified' }
 if ((Set-ClaudeConnection $homeDir $source 'uninstall') -ne 'conflict') { throw 'Other statusline removed' }
 [IO.File]::WriteAllText($settings,'not json')
 if ((Set-ClaudeConnection $homeDir $source 'install') -ne 'invalid') { throw 'Invalid settings accepted' }
 'Windows Claude setup checks passed'
} finally { Remove-Item -LiteralPath $homeDir -Recurse -Force -ErrorAction SilentlyContinue }
