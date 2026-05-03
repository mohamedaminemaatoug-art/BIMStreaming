param(
  [string]$SignalUrl = 'ws://127.0.0.1:8080/api/v1/ws',
  [string]$ApiUrl = '',
  [string]$ServerAddr = ':8080',
  [switch]$SkipBackend,
  [switch]$LowMemory,
  [ValidateSet('debug', 'profile', 'release')]
  [string]$Mode = 'debug'
)

$rootScript = Join-Path $PSScriptRoot '..\start-dev.ps1'
& $rootScript @PSBoundParameters