function Get-CopilotBilling {
    $gh = Get-Command gh.exe,gh.cmd -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $gh) { return @{Error='cli'} }
    $env:GH_HOST='github.com'; $env:GH_PROMPT_DISABLED='1'; $env:GH_PAGER='cat'
    try {
        $login = (& $gh.Source api --hostname github.com user --jq '.login' 2>$null | Out-String).Trim()
        if ($LASTEXITCODE -ne 0 -or $login -cnotmatch '^[A-Za-z0-9-]{1,39}$') { return @{Error='login'} }
        $endpoint = 'users/' + $login + '/settings/billing/ai_credit/usage'
        $json = (& $gh.Source api --hostname github.com -H 'Accept: application/vnd.github+json' -H 'X-GitHub-Api-Version: 2026-03-10' $endpoint 2>$null | Out-String)
        if ($LASTEXITCODE -ne 0) { return @{Error='permission'} }
        if ($json.Length -gt 1000000) { return @{Error='data'} }
        $summary = Convert-CopilotBilling ($json | ConvertFrom-Json -ErrorAction Stop)
        if ($null -eq $summary) { return @{Error='data'} }
        return @{Summary=$summary}
    } catch { return @{Error='network'} }
}
