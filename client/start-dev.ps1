param(
  [string]$SignalUrl = 'ws://127.0.0.1:8080/api/v1/ws',
  [string]$ServerAddr = ':8080',
  [switch]$SkipBackend
)

$rootScript = Join-Path $PSScriptRoot '..\start-dev.ps1'
& $rootScript @PSBoundParameters