$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../../Windows/Quota.ps1')
. (Join-Path $PSScriptRoot '../../Windows/Copilot.ps1')
$result = Get-CopilotBilling
if ($result.Summary -ne '이번 달 보고된 사용 19.75 크레딧') { throw 'Copilot fake CLI result missing' }
$env:USAGEEDGE_FAKE_GH_ERROR='1'
if ((Get-CopilotBilling).Error -ne 'login') { throw 'Copilot login failure not detected' }
Write-Output 'Windows Copilot fake CLI checks passed'
