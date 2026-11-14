#requires -Version 5.1
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
. (Join-Path $PSScriptRoot 'Quota.ps1')
$script:appRoot = $PSScriptRoot
[System.Windows.Forms.Application]::EnableVisualStyles()
$bg = [System.Drawing.Color]::FromArgb(19,21,26)
$card = [System.Drawing.Color]::FromArgb(30,32,38)
$white = [System.Drawing.Color]::FromArgb(235,237,240)
$muted = [System.Drawing.Color]::FromArgb(155,160,168)
$mint = [System.Drawing.Color]::FromArgb(110,210,176)
$form = New-Object System.Windows.Forms.Form
$form.Text='UsageEdge'; $form.FormBorderStyle='None'; $form.BackColor=$bg; $form.ForeColor=$white; $form.TopMost=$true
$form.ShowInTaskbar=$false; $form.StartPosition='Manual'; $form.Width=240; $form.Height=320
$working=[System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$form.Location=New-Object System.Drawing.Point(($working.Right-$form.Width-5),($working.Top+[int](($working.Height-$form.Height)/2)))
function Label($parent,$text,$x,$y,$w,$h,$size,$color) {
 $l=New-Object System.Windows.Forms.Label; $l.Text=$text; $l.SetBounds($x,$y,$w,$h); $l.ForeColor=$color
 $l.Font=New-Object System.Drawing.Font('Segoe UI',$size); $l.BackColor=[System.Drawing.Color]::Transparent; $parent.Controls.Add($l); return $l
}
function Button($parent,$text,$x,$y,$w,$h) {
 $b=New-Object System.Windows.Forms.Button; $b.Text=$text; $b.SetBounds($x,$y,$w,$h); $b.FlatStyle='Flat'; $b.FlatAppearance.BorderSize=0
 $b.BackColor=$card; $b.ForeColor=$white; $parent.Controls.Add($b); return $b
}
$heading=Label $form 'USAGE  /  사용량' 16 15 180 26 11 $white
$refresh=Button $form '↻' 175 12 26 28
$collapse=Button $form '›' 206 12 24 28
$compactInfo=Label $form '5H —  |  주 —' 7 22 105 22 8 $white; $compactInfo.Visible=$false
$compactKimi=Label $form '' 7 42 105 20 8 $white; $compactKimi.Visible=$false
$kimiLabel=Label $form '' 16 280 210 24 9 $muted; $kimiLabel.Visible=$false
$kimiTip=New-Object System.Windows.Forms.ToolTip
$claude=Label $form 'Claude   ·   공식 사용량 화면 열기' 16 55 210 28 9 $muted
$claude.Cursor=[System.Windows.Forms.Cursors]::Hand
$claude.Add_Click({Start-Process 'https://claude.ai/settings/usage'})
$provider=Label $form 'Codex' 16 92 170 26 12 $mint
$status=Label $form '확인 중' 16 120 205 25 9 $muted
$rows=@()
foreach ($i in 0..1) {
 $y=150+$i*67
 $title=Label $form '' 16 $y 80 22 10 $muted
 $value=Label $form '' 100 ($y-3) 120 27 13 $white
 $bar=New-Object System.Windows.Forms.ProgressBar; $bar.SetBounds(16,($y+25),205,5); $bar.Maximum=100; $form.Controls.Add($bar)
 $date=Label $form '' 16 ($y+35) 210 23 8 $muted
 $rows+=@([pscustomobject]@{Title=$title;Value=$value;Bar=$bar;Date=$date})
}
$settings=Button $form '설정' 155 290 65 24
$menu=New-Object System.Windows.Forms.ContextMenuStrip
$startup=New-Object System.Windows.Forms.ToolStripMenuItem('로그인 시 실행'); $startup.CheckOnClick=$true
$shortcut=Join-Path ([Environment]::GetFolderPath('Startup')) 'UsageEdge.lnk'
$startup.Checked=Test-Path $shortcut
$startup.Add_Click({
 try {
  if ($startup.Checked) {
   $shell=New-Object -ComObject WScript.Shell; $link=$shell.CreateShortcut($shortcut)
   $link.TargetPath=(Join-Path $PSScriptRoot '실행.cmd'); $link.WorkingDirectory=$PSScriptRoot; $link.Save()
  } else { if (Test-Path $shortcut) { Remove-Item -LiteralPath $shortcut -ErrorAction Stop } }
 } catch { $startup.Checked=Test-Path $shortcut; [System.Windows.Forms.MessageBox]::Show('시작 항목 설정을 변경하지 못했습니다.') | Out-Null }
})
[void]$menu.Items.Add($startup)
$connect=New-Object System.Windows.Forms.ToolStripMenuItem('Codex 브라우저 연결'); [void]$menu.Items.Add($connect)
$script:loginProcess=$null; $script:loginRefreshPending=$false
$connect.Add_Click({
 if ($script:loginProcess) { return }
 if (-not (Get-Command codex.cmd,codex.exe -ErrorAction SilentlyContinue | Select-Object -First 1)) { $status.Text='Codex CLI를 찾을 수 없음'; return }
 try {
  $script:loginProcess=Start-Process -FilePath $env:ComSpec -ArgumentList '/d','/c','codex login' -PassThru -ErrorAction Stop
  $status.Text='브라우저에서 로그인 중'
 } catch { $status.Text='Codex 로그인 실행 실패' }
})
$script:kimiKey='HKCU:\Software\UsageEdge'
$script:kimiPort=0; $script:kimiWindows=@(); $script:kimiJob=$null; $script:kimiNotified=@{}; $script:kimiLast=[DateTime]::MinValue
try { $saved=(Get-ItemProperty -LiteralPath $script:kimiKey -Name KimiPort -ErrorAction Stop).KimiPort; if ([int]$saved -ge 1 -and [int]$saved -le 65535) { $script:kimiPort=[int]$saved } } catch {}
$kimiConnect=New-Object System.Windows.Forms.ToolStripMenuItem('Kimi Code 연결…'); [void]$menu.Items.Add($kimiConnect)
$kimiDisconnect=New-Object System.Windows.Forms.ToolStripMenuItem('Kimi Code 연결 해제'); [void]$menu.Items.Add($kimiDisconnect)
$kimiConnect.Add_Click({
 Add-Type -AssemblyName Microsoft.VisualBasic
 $chosen=[Microsoft.VisualBasic.Interaction]::InputBox('실행 중인 Kimi Code 서버의 로컬 포트를 입력하세요. 서버 토큰 파일을 읽어 해당 포트로 전송합니다.','Kimi Code 연결','58627')
 if ([string]::IsNullOrWhiteSpace($chosen)) { return }
 $number=0
 if (-not [int]::TryParse($chosen,[ref]$number) -or $number -lt 1 -or $number -gt 65535) { [System.Windows.Forms.MessageBox]::Show('포트를 확인하세요.') | Out-Null; return }
 try { New-Item -Path $script:kimiKey -Force | Out-Null; Set-ItemProperty -LiteralPath $script:kimiKey -Name KimiPort -Value $number -Type DWord -ErrorAction Stop }
 catch { [System.Windows.Forms.MessageBox]::Show('설정을 저장하지 못했습니다.') | Out-Null; return }
 if ($script:kimiJob) { Stop-Job $script:kimiJob -ErrorAction SilentlyContinue; Remove-Job $script:kimiJob -Force -ErrorAction SilentlyContinue; $script:kimiJob=$null }
 $script:kimiPort=$number; $script:kimiWindows=@(); $script:kimiNotified=@{}; $kimiLabel.Text='Kimi Code 확인 중'; Update-KimiLayout; Start-KimiRefresh -Force
})
$kimiDisconnect.Add_Click({
 try {
  $existing=Get-ItemProperty -LiteralPath $script:kimiKey -Name KimiPort -ErrorAction SilentlyContinue
  if ($null -ne $existing) { Remove-ItemProperty -LiteralPath $script:kimiKey -Name KimiPort -ErrorAction Stop }
 } catch { [System.Windows.Forms.MessageBox]::Show('연결 해제 설정을 저장하지 못했습니다.') | Out-Null; return }
 $script:kimiPort=0; $script:kimiWindows=@()
 if ($script:kimiJob) { Stop-Job $script:kimiJob -ErrorAction SilentlyContinue; Remove-Job $script:kimiJob -Force -ErrorAction SilentlyContinue; $script:kimiJob=$null }
 Update-KimiLayout
})
function Update-KimiLayout {
 $hasKimi=$script:kimiPort -gt 0
 $kimiLabel.Visible=$hasKimi -and -not $script:collapsed
 $compactKimi.Visible=$hasKimi -and $script:collapsed
 if ($script:collapsed) { $form.Height=if($hasKimi){84}else{66}; $collapse.SetBounds(112,19,24,28) }
 else { $form.Height=if($hasKimi){345}else{320}; $settings.Top=if($hasKimi){315}else{290} }
 $area=[System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
 $form.Location=New-Object System.Drawing.Point(($area.Right-$form.Width-5),($area.Top+[int](($area.Height-$form.Height)/2)))
}
function Start-KimiRefresh {
 param([switch]$Force)
 if ($script:kimiPort -le 0 -or $script:kimiJob) { return }
 if (-not $Force -and ((Get-Date)-$script:kimiLast).TotalSeconds -lt 300) { return }
 $script:kimiLast=Get-Date
 $tokenPath=Join-Path ([Environment]::GetFolderPath('UserProfile')) '.kimi-code\server.token'
 $script:kimiJob=Start-Job -ArgumentList $script:appRoot,$script:kimiPort,$tokenPath -ScriptBlock {
  param($root,$port,$tokenPath)
  . (Join-Path $root 'Quota.ps1'); . (Join-Path $root 'Kimi.ps1')
  Get-KimiUsageFromFile $port $tokenPath
 }
}
$test=New-Object System.Windows.Forms.ToolStripMenuItem('알림 테스트'); [void]$menu.Items.Add($test)
$quit=New-Object System.Windows.Forms.ToolStripMenuItem('종료'); [void]$menu.Items.Add($quit)
$settings.Add_Click({$menu.Show($settings,0,$settings.Height)})
$tray=New-Object System.Windows.Forms.NotifyIcon; $tray.Icon=[System.Drawing.SystemIcons]::Application; $tray.Text='UsageEdge'; $tray.Visible=$true
$tray.ContextMenuStrip=$menu; $tray.Add_DoubleClick({if($form.Visible){$form.Hide()}else{$form.Show()}})
$quit.Add_Click({$form.Close()}); $form.Add_FormClosed({$timer.Stop();if($script:job){$script:job | Stop-Job -ErrorAction SilentlyContinue; $script:job | Remove-Job -Force -ErrorAction SilentlyContinue};if($script:kimiJob){$script:kimiJob | Stop-Job -ErrorAction SilentlyContinue; $script:kimiJob | Remove-Job -Force -ErrorAction SilentlyContinue};$tray.Visible=$false;$tray.Dispose();$kimiTip.Dispose()})
$test.Add_Click({$tray.ShowBalloonTip(5000,'UsageEdge 알림 테스트','초기화 알림이 이 방식으로 표시됩니다.',[System.Windows.Forms.ToolTipIcon]::Info)})
$script:collapsed=$false
$collapse.Add_Click({
 $script:collapsed=-not $script:collapsed
 foreach($c in $form.Controls){if($c -ne $collapse -and $c -ne $compactInfo -and $c -ne $compactKimi -and $c -ne $kimiLabel){$c.Visible=-not $script:collapsed}}
 $compactInfo.Visible=$script:collapsed
 if($script:collapsed){$form.Width=140;$form.Height=66;$collapse.SetBounds(112,19,24,28);$collapse.Text='‹'}else{$form.Width=240;$form.Height=320;$collapse.SetBounds(206,12,24,28);$collapse.Text='›'}
 Update-KimiLayout
})
$script:job=$null; $script:lastRefresh=[DateTime]::MinValue; $script:windows=@(); $script:notified=@{}
function Start-Refresh {
 if ($null -ne $script:job) {return}
 $status.Text='확인 중'; $script:lastRefresh=Get-Date
 $script:job=Start-Job -ArgumentList $PSScriptRoot -ScriptBlock {
  param($root)
  . (Join-Path $root 'Quota.ps1')
  $command=Get-Command codex.cmd,codex.exe -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $command) {return @{error='Codex CLI를 찾을 수 없음'}}
  $info=New-Object System.Diagnostics.ProcessStartInfo
  if ($command.Source -like '*.cmd') { $info.FileName=$env:ComSpec; $info.Arguments='/d /s /c ""'+$command.Source+'" app-server --stdio"' }
  else { $info.FileName=$command.Source; $info.Arguments='app-server --stdio' }
  $info.UseShellExecute=$false; $info.RedirectStandardInput=$true; $info.RedirectStandardOutput=$true; $info.RedirectStandardError=$true; $info.CreateNoWindow=$true
  $p=New-Object System.Diagnostics.Process; $p.StartInfo=$info
  try {
   [void]$p.Start(); $stderrTask=$p.StandardError.ReadToEndAsync()
   $p.StandardInput.WriteLine('{"id":1,"method":"initialize","params":{"clientInfo":{"name":"usage_edge_windows","version":"1.0"}}}')
   $p.StandardInput.WriteLine('{"method":"initialized"}'); $p.StandardInput.WriteLine('{"id":2,"method":"account/rateLimits/read"}'); $p.StandardInput.Flush()
   $deadline=[DateTime]::UtcNow.AddSeconds(18)
   while([DateTime]::UtcNow -lt $deadline) {
    $task=$p.StandardOutput.ReadLineAsync()
    if(-not $task.Wait([TimeSpan]::FromSeconds(18))){break}
    $line=$task.Result; if($null -eq $line){break}
    try { $o=$line | ConvertFrom-Json } catch { continue }
    if($o.id -eq 2) { $windows=@(Convert-CodexLimits $o); if($windows.Count){return @{windows=$windows}}; break }
   }
   return @{error='확인 불가 · 로그인과 연결 확인'}
  } catch { return @{error='Codex 실행 실패'} }
  finally { if($p -and !$p.HasExited){$p.Kill()}; if($p){$p.Dispose()} }
 }
}
$refresh.Add_Click({Start-Refresh; Start-KimiRefresh -Force})
$timer=New-Object System.Windows.Forms.Timer; $timer.Interval=1000
$timer.Add_Tick({
 if($script:loginProcess -and $script:loginProcess.HasExited){
  $code=$script:loginProcess.ExitCode; $script:loginProcess.Dispose(); $script:loginProcess=$null
  if($code -eq 0){$script:loginRefreshPending=$true} else {$status.Text='로그인 미완료 · 다시 시도'}
 }
 if($script:job -and $script:job.State -in @('Completed','Failed','Stopped')){
  $result=Receive-Job $script:job -ErrorAction SilentlyContinue; Remove-Job $script:job -Force -ErrorAction SilentlyContinue; $script:job=$null
  if($result -and $result.windows){
   $script:windows=@($result.windows); $status.Text='연결됨 · '+(Get-Date -Format 'HH:mm')
   for($i=0;$i -lt 2;$i++){
    $row=$rows[$i]; if($i -lt $script:windows.Count){$w=$script:windows[$i]; $row.Title.Text=$w.Label; $row.Value.Text="$($w.Remaining)% 남음"; $row.Bar.Value=[int]$w.Remaining; $row.Date.Text=if($w.Reset){'초기화 '+$w.Reset.ToString('M월 d일 HH:mm')}else{'초기화 시간 확인 불가'}}
    else{$row.Title.Text='';$row.Value.Text='';$row.Bar.Value=0;$row.Date.Text=''}
   }
  } else {
   $state=Resolve-RefreshState $script:windows $result
   $script:windows=@($state.Windows)
   $reason=if($result.error){$result.error}else{'확인 불가'}
   $status.Text=if($state.Stale){'오래된 값 · '+$reason}else{$reason}
  }
  $compactInfo.Text=if($result -and $result.windows){Get-CompactSummary $script:windows}else{Get-CompactSummary @()}
 }
 if($script:kimiJob -and $script:kimiJob.State -in @('Completed','Failed','Stopped')) {
  $kr=Receive-Job $script:kimiJob -ErrorAction SilentlyContinue; Remove-Job $script:kimiJob -Force -ErrorAction SilentlyContinue; $script:kimiJob=$null
  if ($kr -and $kr.Windows) {
   $script:kimiWindows=@($kr.Windows); $summary=Get-CompactSummary $script:kimiWindows
   $kimiLabel.Text='Kimi  '+$summary; $compactKimi.Text='K  '+$summary
   $resetText=($script:kimiWindows | Where-Object { $_.Reset } | ForEach-Object { $_.Label+' '+$_.Reset.ToString('M/d HH:mm') }) -join ' · '
   $kimiTip.SetToolTip($kimiLabel, $(if($resetText){'초기화 예정: '+$resetText}else{'초기화 시간 확인 불가'}))
  } else { $kimiLabel.Text=if($script:kimiWindows.Count){'Kimi 오래된 값 · 연결 확인'}else{'Kimi 연결 확인 필요'}; $compactKimi.Text='K  5H — | 주 —' }
 }
 foreach($kw in $script:kimiWindows) {
  if($kw.Reset){$delta=((Get-Date)-$kw.Reset).TotalSeconds; $key="$($kw.Minutes):$($kw.Reset.Ticks)"; if($delta -ge 0 -and $delta -lt 600 -and !$script:kimiNotified.ContainsKey($key)){$script:kimiNotified[$key]=$true;$tray.ShowBalloonTip(5000,'Kimi Code 사용량 초기화',"$($kw.Label) 한도의 초기화 예정 시각입니다. 새로고침해 확인하세요.",[System.Windows.Forms.ToolTipIcon]::Info);Start-KimiRefresh -Force}}
 }
 if($script:loginRefreshPending -and -not $script:job){$script:loginRefreshPending=$false; Start-Refresh}
 if(((Get-Date)-$script:lastRefresh).TotalSeconds -ge 300){Start-Refresh; Start-KimiRefresh}
 foreach($w in $script:windows){
  if($w.Reset){$delta=((Get-Date)-$w.Reset).TotalSeconds; $key="$($w.Minutes):$($w.Reset.Ticks)"; if($delta -ge 0 -and $delta -lt 600 -and !$script:notified.ContainsKey($key)){$script:notified[$key]=$true;$tray.ShowBalloonTip(5000,'Codex 사용량 초기화',"$($w.Label) 한도의 초기화 예정 시각입니다. 새로고침해 확인하세요.",[System.Windows.Forms.ToolTipIcon]::Info);Start-Refresh}}
 }
})
$form.Add_Shown({Update-KimiLayout; Start-Refresh; Start-KimiRefresh; $timer.Start()})
[System.Windows.Forms.Application]::Run($form)
