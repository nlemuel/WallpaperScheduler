[CmdletBinding()]
param(
    [datetime]$At = (Get-Date),
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$baseDir = $PSScriptRoot
$configPath = Join-Path $baseDir 'config.json'
$imageDir = Join-Path $baseDir 'images'
$logDir = Join-Path $env:LOCALAPPDATA 'WallpaperScheduler\Logs'
$logPath = Join-Path $logDir 'wallpaper.log'

function Write-Log([string]$Level, [string]$Message) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    if ((Test-Path -LiteralPath $logPath) -and
        (Get-Item -LiteralPath $logPath).Length -gt 2MB) {
        Move-Item -LiteralPath $logPath -Destination "$logPath.old" -Force
    }
    '{0:o} [{1}] {2}' -f (Get-Date), $Level, $Message |
        Add-Content -LiteralPath $logPath -Encoding UTF8
}

try {
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        throw "Configuração não encontrada: $configPath"
    }

    $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 |
        ConvertFrom-Json
    $dayName = $At.DayOfWeek.ToString()
    $periods = @($config.Schedule.$dayName)
    if ($periods.Count -eq 0) {
        throw "Não há períodos configurados para $dayName."
    }

    $nowMinutes = ($At.Hour * 60) + $At.Minute
    $selected = $periods |
        ForEach-Object {
            $parts = $_.Start -split ':'
            if ($parts.Count -ne 2) { throw "Horário inválido: $($_.Start)" }
            [pscustomobject]@{
                StartMinutes = ([int]$parts[0] * 60) + [int]$parts[1]
                File = [string]$_.File
                Start = [string]$_.Start
            }
        } |
        Where-Object { $_.StartMinutes -le $nowMinutes } |
        Sort-Object StartMinutes -Descending |
        Select-Object -First 1

    if ($null -eq $selected) {
        throw "A configuração de $dayName deve começar em 00:00."
    }

    $imageRoot = [IO.Path]::GetFullPath($imageDir).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $wallpaperPath = [IO.Path]::GetFullPath((Join-Path $imageDir $selected.File))
    if (-not $wallpaperPath.StartsWith($imageRoot,
            [StringComparison]::OrdinalIgnoreCase)) {
        throw "Caminho fora da pasta images: $($selected.File)"
    }
    if (-not (Test-Path -LiteralPath $wallpaperPath -PathType Leaf)) {
        throw "Imagem não encontrada: $wallpaperPath"
    }

    $styles = @{
        Fill    = @{ WallpaperStyle = '10'; TileWallpaper = '0' }
        Fit     = @{ WallpaperStyle = '6';  TileWallpaper = '0' }
        Stretch = @{ WallpaperStyle = '2';  TileWallpaper = '0' }
        Center  = @{ WallpaperStyle = '0';  TileWallpaper = '0' }
        Tile    = @{ WallpaperStyle = '0';  TileWallpaper = '1' }
        Span    = @{ WallpaperStyle = '22'; TileWallpaper = '0' }
    }
    $styleName = [string]$config.Style
    if (-not $styles.ContainsKey($styleName)) { throw "Estilo inválido: $styleName" }

    if ($DryRun) {
        Write-Output "DRY RUN: $dayName $($At.ToString('HH:mm')) -> $wallpaperPath"
        exit 0
    }

    $desktopKey = 'HKCU:\Control Panel\Desktop'
    Set-ItemProperty -Path $desktopKey -Name WallpaperStyle -Value $styles[$styleName].WallpaperStyle
    Set-ItemProperty -Path $desktopKey -Name TileWallpaper -Value $styles[$styleName].TileWallpaper

    if (-not ('Wallpaper.NativeMethods' -as [type])) {
        Add-Type @'
using System;
using System.Runtime.InteropServices;
namespace Wallpaper {
    public static class NativeMethods {
        [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
        public static extern bool SystemParametersInfo(
            int uiAction, int uiParam, string pvParam, int fWinIni);
    }
}
'@
    }

    # SPI_SETDESKWALLPAPER=20; SPIF_UPDATEINIFILE|SPIF_SENDCHANGE=3
    $ok = [Wallpaper.NativeMethods]::SystemParametersInfo(20, 0, $wallpaperPath, 3)
    if (-not $ok) {
        $code = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        throw "SystemParametersInfo falhou. Win32=$code"
    }

    Write-Log 'INFO' "$dayName $($At.ToString('HH:mm')); período=$($selected.Start); arquivo=$wallpaperPath; resultado=OK"
}
catch {
    try { Write-Log 'ERROR' $_.Exception.Message } catch {}
    Write-Error $_
    exit 1
}
