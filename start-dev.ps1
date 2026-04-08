param(
  [string]$SignalUrl = 'ws://127.0.0.1:8080/api/v1/ws',
  [string]$ServerAddr = ':8080',
  [switch]$SkipBackend
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$serverDir = Join-Path $repoRoot 'server'
$clientDir = Join-Path $repoRoot 'client'
$healthUrl = 'http://127.0.0.1:8080/healthz'

function Test-BackendReady {
  try {
    $response = Invoke-WebRequest -Uri $healthUrl -UseBasicParsing -TimeoutSec 2
    return $response.StatusCode -ge 200 -and $response.StatusCode -lt 300
  } catch {
    return $false
  }
}

if (-not $SkipBackend) {
  if (-not (Test-Path $serverDir)) {
    throw "Server directory not found: $serverDir"
  }

  Write-Host "Starting relay server from $serverDir"
  $backendCommand = "`$env:SERVER_ADDR='$ServerAddr'; Set-Location '$serverDir'; go run ."
  Start-Process -FilePath 'powershell' -ArgumentList @('-NoExit', '-Command', $backendCommand) | Out-Null

  Write-Host 'Waiting for signaling backend to become ready...'
  $deadline = (Get-Date).AddSeconds(90)
  while ((Get-Date) -lt $deadline) {
    if (Test-BackendReady) {
      Write-Host 'Backend is ready.'
      break
    }
    Start-Sleep -Seconds 2
  }

  if (-not (Test-BackendReady)) {
    throw "Backend did not become ready at $healthUrl. Start it first, or check Docker/Postgres/Redis logs."
  }
}

Write-Host "Launching Flutter with BIM_SIGNAL_URL=$SignalUrl"
if (-not (Test-Path $clientDir)) {
  throw "Client directory not found: $clientDir"
}

Set-Location $clientDir
flutter run -d windows --dart-define=BIM_SIGNAL_URL=$SignalUrl
