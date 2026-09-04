[CmdletBinding()]
param(
    [string]$InstallDir = "$env:ProgramData\WallpaperScheduler",
    [switch]$EnableWatchdog
)

$ErrorActionPreference = 'Stop'
$taskName = "WallpaperScheduler-$($env:USERNAME)"
$sourceDir = $PSScriptRoot

$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$windowsPrincipal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
$isAdmin = $windowsPrincipal.IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    throw 'Execute este instalador como administrador. A tarefa continuará rodando como o usuário atual.'
}

New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $InstallDir 'images') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $sourceDir 'Set-Wallpaper.ps1') -Destination $InstallDir -Force
Copy-Item -LiteralPath (Join-Path $sourceDir 'Run-Wallpaper.bat') -Destination $InstallDir -Force
Copy-Item -LiteralPath (Join-Path $sourceDir 'config.json') -Destination $InstallDir -Force
if (Test-Path -LiteralPath (Join-Path $sourceDir 'images')) {
    Copy-Item -Path (Join-Path $sourceDir 'images\*') -Destination (Join-Path $InstallDir 'images') -Force
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$userId = $identity.Name
$action = New-ScheduledTaskAction `
    -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
    -Argument "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$InstallDir\Set-Wallpaper.ps1`"" `
    -WorkingDirectory $InstallDir

$triggers = @(
    New-ScheduledTaskTrigger -AtLogOn -User $userId
    New-ScheduledTaskTrigger -Weekly -WeeksInterval 1 -DaysOfWeek Sunday,Monday,Tuesday,Wednesday,Thursday,Friday,Saturday -At '00:00'
    New-ScheduledTaskTrigger -Weekly -WeeksInterval 1 -DaysOfWeek Sunday,Saturday -At '08:00'
    New-ScheduledTaskTrigger -Weekly -WeeksInterval 1 -DaysOfWeek Sunday,Saturday -At '16:30'
    New-ScheduledTaskTrigger -Weekly -WeeksInterval 1 -DaysOfWeek Saturday -At '18:00'
    New-ScheduledTaskTrigger -Weekly -WeeksInterval 1 -DaysOfWeek Monday -At '10:00'
    New-ScheduledTaskTrigger -Weekly -WeeksInterval 1 -DaysOfWeek Tuesday,Thursday,Friday -At '07:00'
    New-ScheduledTaskTrigger -Weekly -WeeksInterval 1 -DaysOfWeek Tuesday,Thursday,Friday -At '18:00'
    New-ScheduledTaskTrigger -Weekly -WeeksInterval 1 -DaysOfWeek Wednesday -At '19:00'
)

if ($EnableWatchdog) {
    # O módulo ScheduledTasks só aceita repetição no gatilho "Once".
    # Dez anos dão comportamento contínuo e são renovados ao reinstalar/atualizar.
    $triggers += New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
        -RepetitionInterval (New-TimeSpan -Minutes 30) `
        -RepetitionDuration (New-TimeSpan -Days 3650)
}

$principal = New-ScheduledTaskPrincipal -UserId $userId -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -MultipleInstances IgnoreNew `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

$task = New-ScheduledTask -Action $action -Trigger $triggers -Principal $principal `
    -Settings $settings -Description 'Recalcula e aplica o wallpaper correto no logon e em cada transição.'
Register-ScheduledTask -TaskName $taskName -InputObject $task -Force | Out-Null
Start-ScheduledTask -TaskName $taskName

Write-Host "Tarefa registrada: $taskName"
Write-Host "Instalação: $InstallDir"
Write-Host 'Repita a instalação em cada conta Windows que deverá receber wallpapers.'