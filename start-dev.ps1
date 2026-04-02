param(
  [string]$SignalUrl = 'ws://127.0.0.1:8080/api/v1/ws',
  [switch]$SkipBackend
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$backendDockerDir = Join-Path $repoRoot 'backend\signaling-go\deploy\docker'
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
  if (Get-Command docker -ErrorAction SilentlyContinue) {
    Write-Host 'Starting backend stack with Docker Compose...'
    Push-Location $backendDockerDir
    try {
      docker compose up -d --build | Out-Host
    } finally {
      Pop-Location
    }
  } else {
    Write-Warning 'Docker is not installed or not on PATH. Skipping backend stack startup.'
    Write-Warning 'If you already have Postgres/Redis running locally, start the Go server manually from backend/signaling-go.'
  }

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
Set-Location $repoRoot
flutter run -d windows --dart-define=BIM_SIGNAL_URL=$SignalUrl
