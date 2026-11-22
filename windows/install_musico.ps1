param(
  [ValidateSet('Debug', 'Profile', 'Release')]
  [string]$Configuration = 'Profile'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$buildDirectory = Join-Path $projectRoot "build\windows\x64\runner\$Configuration"
$buildExecutable = Join-Path $buildDirectory 'Musico.exe'

if (-not (Test-Path -LiteralPath $buildExecutable -PathType Leaf)) {
  throw "The $Configuration build is missing. Build Windows before installing Musico."
}

$installDirectory = Join-Path $env:LOCALAPPDATA 'Programs\Musico'
$installedExecutable = Join-Path $installDirectory 'Musico.exe'
$runningApp = Get-Process -Name Musico -ErrorAction SilentlyContinue |
  Where-Object { $_.Path -eq $installedExecutable }
if ($runningApp) {
  throw 'Close the installed Musico app before updating it.'
}

New-Item -ItemType Directory -Path $installDirectory -Force | Out-Null
Get-ChildItem -LiteralPath $buildDirectory -Force |
  Copy-Item -Destination $installDirectory -Recurse -Force

$programsDirectory = [Environment]::GetFolderPath('Programs')
$shortcutPath = Join-Path $programsDirectory 'Musico.lnk'
$shell = New-Object -ComObject WScript.Shell
try {
  $shortcut = $shell.CreateShortcut($shortcutPath)
  $shortcut.TargetPath = $installedExecutable
  $shortcut.WorkingDirectory = $installDirectory
  $shortcut.Description = 'Musico offline music player'
  $shortcut.IconLocation = "$installedExecutable,0"
  $shortcut.Save()
}
finally {
  [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
}

Write-Output "Installed Musico to $installDirectory"
Write-Output "Added Start Menu shortcut: $shortcutPath"
