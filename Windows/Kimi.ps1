function Get-KimiUsage([int]$Port, [string]$Token) {
    if ($Port -lt 1 -or $Port -gt 65535 -or [string]::IsNullOrEmpty($Token) -or $Token -cmatch '[^!-~]') { return @{Error='input'} }
    Add-Type -AssemblyName System.Net.Http
    $handler = New-Object System.Net.Http.HttpClientHandler
    $handler.AllowAutoRedirect = $false
    $handler.UseProxy = $false
    $client = New-Object System.Net.Http.HttpClient($handler)
    $client.Timeout = [TimeSpan]::FromSeconds(15)
    $client.MaxResponseContentBufferSize = 1048576
    $request = New-Object System.Net.Http.HttpRequestMessage([System.Net.Http.HttpMethod]::Get, "http://127.0.0.1:$Port/api/v1/oauth/usage")
    $request.Headers.Authorization = New-Object System.Net.Http.Headers.AuthenticationHeaderValue('Bearer', $Token)
    try {
        $response = $client.SendAsync($request).GetAwaiter().GetResult()
        try {
            if ([int]$response.StatusCode -eq 401) { return @{Error='auth'} }
            if ([int]$response.StatusCode -ne 200) { return @{Error='http'} }
            $json = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            $windows = @(Convert-KimiLimits ($json | ConvertFrom-Json -ErrorAction Stop))
            if ($windows.Count -eq 0) { return @{Error='data'} }
            return @{Windows=$windows}
        } finally { $response.Dispose() }
    } catch { return @{Error='network'} }
    finally { $request.Dispose(); $client.Dispose(); $handler.Dispose() }
}
