$ErrorActionPreference = "Continue"

function Load-EnvFile {
  param([string]$Path)
  if (!(Test-Path $Path)) { return }
  Get-Content $Path | ForEach-Object {
    $line = $_.Trim()
    if (!$line -or $line.StartsWith("#")) { return }
    $idx = $line.IndexOf("=")
    if ($idx -lt 1) { return }
    $k = $line.Substring(0,$idx).Trim()
    $v = $line.Substring($idx+1).Trim()
    if (($v.StartsWith('"') -and $v.EndsWith('"')) -or ($v.StartsWith("'") -and $v.EndsWith("'"))) { $v = $v.Substring(1,$v.Length-2) }
    [Environment]::SetEnvironmentVariable($k,$v,"Process")
  }
}

function Invoke-JsonRequest {
  param([string]$Method,[string]$Url,$Body=$null,[hashtable]$Headers=@{})
  try {
    $p = @{ Method=$Method; Uri=$Url; Headers=$Headers; SkipHttpErrorCheck=$true }
    if ($null -ne $Body) { $p.Body = ($Body | ConvertTo-Json -Depth 20); $p.ContentType = "application/json" }
    $r = Invoke-WebRequest @p
    $d = $null
    if ($r.Content) { try { $d = $r.Content | ConvertFrom-Json -Depth 20 } catch { $d = $r.Content } }
    [pscustomobject]@{ Status=[int]$r.StatusCode; Data=$d; Raw=$r.Content }
  } catch {
    $s = 0
    if ($_.Exception.Response -and $_.Exception.Response.StatusCode) { $s = [int]$_.Exception.Response.StatusCode }
    [pscustomobject]@{ Status=$s; Data=$null; Raw=$_.Exception.Message }
  }
}

$result = [ordered]@{ register_status=$null; verify_status=$null; login_status=$null; me_status=$null; my_status_status=$null; forgot_status=$null; failed_login_statuses=@(); observed_email_types=@(); missing_required_types=@(); email_failures=@() }
$base = "http://localhost:8080"
$log = "server_email_test.log"
$required = @("verify_email","welcome","reset_password","login_alert","account_locked")
$serverProc = $null
$tokenGo = "gettokenmain.go"
$resetGo = "resetflagsmain.go"

try {
  Load-EnvFile ".env"
  Get-ChildItem -Filter "ztmp*.go" -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

  go test ./...
  go run . migrate

  if (Test-Path $log) { Remove-Item $log -Force }
  $serverProc = Start-Process -FilePath "cmd.exe" -ArgumentList "/c","go run . > server_email_test.log 2>&1" -PassThru

  $health = $false
  $sw = [Diagnostics.Stopwatch]::StartNew()
  while ($sw.Elapsed.TotalSeconds -lt 90 -and -not $health) {
    $h = Invoke-JsonRequest "GET" "$base/healthz"
    if ($h.Status -eq 200 -and $h.Data -and $h.Data.status -eq "ok") { $health = $true }
  }

  $ts = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  $email = "bimstreaming.autotest+$ts@gmail.com"
  $password = "Passw0rd!123!"
  $username = "autotest_$ts"

  $reg = Invoke-JsonRequest "POST" "$base/api/v1/auth/register" @{ username=$username; email=$email; password=$password }
  $result.register_status = $reg.Status

  $uid = $null
  if ($reg.Data) {
    if ($reg.Data.user_id) { $uid = [string]$reg.Data.user_id }
    elseif ($reg.Data.data -and $reg.Data.data.user_id) { $uid = [string]$reg.Data.data.user_id }
    elseif ($reg.Data.user -and $reg.Data.user.id) { $uid = [string]$reg.Data.user.id }
  }

  Set-Content $tokenGo -Encoding UTF8 -Value @(
    "package main",
    "import (",
    "  \"context\"",
    "  \"fmt\"",
    "  \"os\"",
    "  \"time\"",
    "  \"github.com/jackc/pgx/v5/pgxpool\"",
    ")",
    "func main(){",
    "  db:=os.Getenv(\"DATABASE_URL\"); if db==\"\"{fmt.Println(\"|\"); os.Exit(1)}",
    "  uid:=\"\"; if len(os.Args)>1{uid=os.Args[1]}",
    "  ctx,c:=context.WithTimeout(context.Background(),10*time.Second); defer c()",
    "  p,err:=pgxpool.New(ctx,db); if err!=nil{fmt.Println(\"|\"); os.Exit(1)}; defer p.Close()",
    "  qs:=[]string{\"SELECT user_id::text, token FROM email_verifications WHERE user_id=$1 ORDER BY created_at DESC LIMIT 1\",\"SELECT user_id::text, verification_token FROM email_verifications WHERE user_id=$1 ORDER BY created_at DESC LIMIT 1\",\"SELECT user_id::text, token FROM email_verifications ORDER BY created_at DESC LIMIT 1\",\"SELECT user_id::text, verification_token FROM email_verifications ORDER BY created_at DESC LIMIT 1\"}",
    "  for i,q:= range qs { var u,t string; if i<2 && uid!=\"\"{err=p.QueryRow(ctx,q,uid).Scan(&u,&t)} else if i>=2 {err=p.QueryRow(ctx,q).Scan(&u,&t)} else {continue}; if err==nil && u!=\"\" && t!=\"\" {fmt.Printf(\"%s|%s\",u,t); return} }",
    "  fmt.Println(\"|\"); os.Exit(1)",
    "}"
  )

  $tokOut = ""
  if ($uid) { $tokOut = (go run $tokenGo $uid 2>$null | Out-String).Trim() } else { $tokOut = (go run $tokenGo 2>$null | Out-String).Trim() }
  $vu = $null; $vt = $null
  if ($tokOut -match "\|") { $parts = $tokOut.Split("|",2); $vu = $parts[0]; $vt = $parts[1] }

  $ver = Invoke-JsonRequest "POST" "$base/api/v1/auth/verify-email" @{ user_id=$vu; token=$vt }
  $result.verify_status = $ver.Status

  $login = Invoke-JsonRequest "POST" "$base/api/v1/auth/login" @{ email=$email; password=$password; device_label="AutoTest Device" } @{ "X-Forwarded-For"="8.8.8.8" }
  $result.login_status = $login.Status

  $atk = $null
  if ($login.Data) {
    if ($login.Data.access_token) { $atk = [string]$login.Data.access_token }
    elseif ($login.Data.data -and $login.Data.data.access_token) { $atk = [string]$login.Data.data.access_token }
    elseif ($login.Data.tokens -and $login.Data.tokens.access_token) { $atk = [string]$login.Data.tokens.access_token }
  }
  if ($atk) {
    $me = Invoke-JsonRequest "GET" "$base/api/v1/users/me" $null @{ Authorization="Bearer $atk" }
    $result.me_status = $me.Status
    $my = Invoke-JsonRequest "GET" "$base/api/v1/users/me/status" $null @{ Authorization="Bearer $atk" }
    $result.my_status_status = $my.Status
  }

  $fp = Invoke-JsonRequest "POST" "$base/api/v1/auth/forgot-password" @{ email=$email }
  $result.forgot_status = $fp.Status

  Set-Content $resetGo -Encoding UTF8 -Value @(
    "package main",
    "import(\"context\";\"os\";\"time\";\"github.com/jackc/pgx/v5/pgxpool\")",
    "func main(){db:=os.Getenv(\"DATABASE_URL\");if db==\"\"{os.Exit(1)};ctx,c:=context.WithTimeout(context.Background(),10*time.Second);defer c();p,err:=pgxpool.New(ctx,db);if err!=nil{os.Exit(1)};defer p.Close();_,err=p.Exec(ctx,\"UPDATE users SET failed_login_count=0, locked_until=NULL, is_banned=false WHERE email='user@bim.com'\");if err!=nil{os.Exit(1)}}"
  )
  go run $resetGo *> $null

  for ($i=0; $i -lt 5; $i++) {
    $bad = Invoke-JsonRequest "POST" "$base/api/v1/auth/login" @{ email="user@bim.com"; password="WrongPass!123"; device_label="AutoTest Device" } @{ "X-Forwarded-For"="8.8.8.8" }
    $result.failed_login_statuses += $bad.Status
  }

  $wait = [Diagnostics.Stopwatch]::StartNew(); while ($wait.Elapsed.TotalSeconds -lt 2) { $null = 1 }

  $txt = ""
  if (Test-Path $log) { $txt = Get-Content $log -Raw }
  $obs = @()
  foreach ($t in $required) { if ($txt -match [Regex]::Escape($t)) { $obs += $t } }
  $result.observed_email_types = $obs
  $result.missing_required_types = @($required | Where-Object { $_ -notin $obs })
  if (Test-Path $log) { $result.email_failures = @(Select-String -Path $log -Pattern "(?i)email send failed|failed to send email|email.*failed" | ForEach-Object { $_.Line.Trim() }) }
}
finally {
  if (Test-Path $tokenGo) { Remove-Item $tokenGo -Force -ErrorAction SilentlyContinue }
  if (Test-Path $resetGo) { Remove-Item $resetGo -Force -ErrorAction SilentlyContinue }
  if ($serverProc -and -not $serverProc.HasExited) { cmd /c "taskkill /PID $($serverProc.Id) /T /F" *> $null }

  $non = @()
  foreach ($k in @("register_status","verify_status","login_status","me_status","my_status_status","forgot_status")) {
    $v = $result[$k]
    if ($null -ne $v -and $v -notin @(200,201)) { $non += "$k=$v" }
  }
  foreach ($s in $result.failed_login_statuses) { if ($s -notin @(200,201)) { $non += "failed_login=$s" } }

  Write-Output "NON_200_201: $($non -join ', ')"
  Write-Output "OBSERVED_EMAIL_TYPES: $($result.observed_email_types -join ',')"
  Write-Output "MISSING_REQUIRED_TYPES: $($result.missing_required_types -join ',')"
  Write-Output "EMAIL_FAILURE_LINES:"
  if ($result.email_failures.Count -gt 0) { $result.email_failures | ForEach-Object { Write-Output $_ } } else { Write-Output "(none)" }
  Write-Output "FINAL_JSON:"
  $result | ConvertTo-Json -Depth 10
}
