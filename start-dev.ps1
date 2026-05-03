param(
  [string]$SignalUrl = 'ws://127.0.0.1:8080/api/v1/ws',
  [string]$ApiUrl = '',
  [string]$ServerAddr = ':8080',
  [switch]$SkipBackend,
  [switch]$LowMemory,
  [ValidateSet('debug', 'profile', 'release')]
  [string]$Mode = 'debug'
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$serverDir = Join-Path $repoRoot 'server'
$clientDir = Join-Path $repoRoot 'client'
$healthUrl = 'http://127.0.0.1:8080/healthz'

function Resolve-ApiUrlFromSignal {
  param([string]$Signal)

  if ([string]::IsNullOrWhiteSpace($Signal)) {
    return ''
  }

  $api = $Signal.Trim()
  if ($api.StartsWith('ws://')) {
    $api = 'http://' + $api.Substring(5)
  } elseif ($api.StartsWith('wss://')) {
    $api = 'https://' + $api.Substring(6)
  }

  $api = $api -replace '/api/v1/ws/?$', '/api/v1'
  return $api
}

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
$resolvedApiUrl = $ApiUrl
if ([string]::IsNullOrWhiteSpace($resolvedApiUrl)) {
  $resolvedApiUrl = Resolve-ApiUrlFromSignal -Signal $SignalUrl
}

$flutterArgs = @('run', '-d', 'windows')

switch ($Mode) {
  'profile' { $flutterArgs += '--profile' }
  'release' { $flutterArgs += '--release' }
  default { }
}

if ($LowMemory) {
  Write-Host 'Low-memory mode enabled (disables track-widget-creation).'
  $flutterArgs += '--no-track-widget-creation'
}

$flutterArgs += "--dart-define=BIM_SIGNAL_URL=$SignalUrl"
if (-not [string]::IsNullOrWhiteSpace($resolvedApiUrl)) {
  $flutterArgs += "--dart-define=BIM_API_URL=$resolvedApiUrl"
}

& flutter @flutterArgs
$exitCode = $LASTEXITCODE

if ($exitCode -ne 0 -and -not $LowMemory -and $Mode -eq 'debug') {
  Write-Host 'Default debug run failed; retrying with low-memory profile mode...'
  $retryArgs = @(
    'run',
    '-d',
    'windows',
    '--profile',
    '--no-track-widget-creation',
    "--dart-define=BIM_SIGNAL_URL=$SignalUrl"
  )
  if (-not [string]::IsNullOrWhiteSpace($resolvedApiUrl)) {
    $retryArgs += "--dart-define=BIM_API_URL=$resolvedApiUrl"
  }
  & flutter @retryArgs
  exit $LASTEXITCODE
}

exit $exitCode
