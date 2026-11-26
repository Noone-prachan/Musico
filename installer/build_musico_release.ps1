param(
  [switch]$SkipFlutterBuild,
  [string]$OutputDirectory = (Join-Path $env:USERPROFILE 'Downloads\Musico-Release')
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$projectRoot = Split-Path -Parent $PSScriptRoot
$releaseDirectory = Join-Path $projectRoot 'build\windows\x64\runner\Release'
$outputZip = Join-Path $OutputDirectory 'Musico-Windows-x64.zip'
$checksumFile = "$outputZip.sha256"
$setupExecutable = Join-Path $OutputDirectory 'Musico-Setup.exe'
$headers = @{
  Accept = 'application/vnd.github+json'
  'User-Agent' = 'Musico-release-build'
  'X-GitHub-Api-Version' = '2022-11-28'
}
$workingDirectory = Join-Path $env:TEMP ("musico-release-" + [Guid]::NewGuid().ToString('N'))
$stagingDirectory = Join-Path $workingDirectory 'package'
$dependencyDirectory = Join-Path $workingDirectory 'dependencies'

function Get-VerifiedGitHubAsset {
  param(
    [Parameter(Mandatory = $true)][string]$Repository,
    [Parameter(Mandatory = $true)][string]$AssetName,
    [Parameter(Mandatory = $true)][string]$Destination
  )

  $release = Invoke-RestMethod `
    -Uri "https://api.github.com/repos/$Repository/releases/latest" `
    -Headers $headers
  $asset = $release.assets |
    Where-Object { $_.name -eq $AssetName } |
    Select-Object -First 1
  if (-not $asset) {
    throw "The latest $Repository release has no $AssetName asset."
  }
  $digestMatch = [regex]::Match([string]$asset.digest, '^sha256:([0-9a-fA-F]{64})$')
  if (-not $digestMatch.Success) {
    throw "GitHub did not provide a SHA-256 digest for $Repository/$AssetName."
  }
  $expectedHash = $digestMatch.Groups[1].Value

  $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
  if ($curl) {
    & $curl.Source `
      --fail `
      --location `
      --show-error `
      --retry 3 `
      --connect-timeout 30 `
      --output $Destination `
      $asset.browser_download_url
    if ($LASTEXITCODE -ne 0) {
      throw "Download failed for $Repository/$AssetName with curl exit code $LASTEXITCODE."
    }
  } else {
    Invoke-WebRequest `
      -Uri $asset.browser_download_url `
      -Headers @{ 'User-Agent' = 'Musico-release-build' } `
      -OutFile $Destination `
      -UseBasicParsing
  }

  $actualHash = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash
  if ($actualHash -ne $expectedHash) {
    throw "SHA-256 verification failed for $Repository/$AssetName."
  }
}

if (-not $SkipFlutterBuild) {
  $flutterCommand = Get-Command flutter.bat -ErrorAction SilentlyContinue
  $flutterPath = if ($flutterCommand) {
    $flutterCommand.Source
  } else {
    Join-Path $env:LOCALAPPDATA 'Programs\flutter\bin\flutter.bat'
  }
  if (-not (Test-Path -LiteralPath $flutterPath -PathType Leaf)) {
    throw 'Flutter was not found. Install Flutter or add flutter.bat to PATH.'
  }
  & $flutterPath build windows --release
  if ($LASTEXITCODE -ne 0) {
    throw "Flutter Windows release build failed with exit code $LASTEXITCODE."
  }
}

if (-not (Test-Path -LiteralPath (Join-Path $releaseDirectory 'Musico.exe') -PathType Leaf)) {
  throw 'The Windows Release folder is missing Musico.exe.'
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
New-Item -ItemType Directory -Path $stagingDirectory, $dependencyDirectory -Force | Out-Null
try {
  $appDirectory = Join-Path $stagingDirectory 'Musico'
  $binDirectory = Join-Path $appDirectory 'bin'
  $denoExtractDirectory = Join-Path $dependencyDirectory 'deno'
  New-Item -ItemType Directory -Path $appDirectory, $binDirectory, $denoExtractDirectory -Force | Out-Null

  Get-ChildItem -LiteralPath $releaseDirectory -Force |
    Copy-Item -Destination $appDirectory -Recurse -Force

  Get-VerifiedGitHubAsset `
    -Repository 'yt-dlp/yt-dlp' `
    -AssetName 'yt-dlp.exe' `
    -Destination (Join-Path $binDirectory 'yt-dlp.exe')

  Get-VerifiedGitHubAsset `
    -Repository 'denoland/deno' `
    -AssetName 'deno-x86_64-pc-windows-msvc.zip' `
    -Destination (Join-Path $dependencyDirectory 'deno.zip')
  Expand-Archive `
    -LiteralPath (Join-Path $dependencyDirectory 'deno.zip') `
    -DestinationPath $denoExtractDirectory `
    -Force
  $denoExecutable = Get-ChildItem -LiteralPath $denoExtractDirectory -Filter deno.exe -Recurse |
    Select-Object -First 1
  if (-not $denoExecutable) {
    throw 'The verified Deno archive did not contain deno.exe.'
  }
  Copy-Item -LiteralPath $denoExecutable.FullName -Destination (Join-Path $binDirectory 'deno.exe')

  Add-Type -AssemblyName System.IO.Compression.FileSystem
  if (Test-Path -LiteralPath $outputZip) {
    Remove-Item -LiteralPath $outputZip -Force
  }
  [IO.Compression.ZipFile]::CreateFromDirectory(
    $stagingDirectory,
    $outputZip,
    [IO.Compression.CompressionLevel]::Optimal,
    $false
  )
  $packageHash = (Get-FileHash -LiteralPath $outputZip -Algorithm SHA256).Hash.ToLowerInvariant()
  Set-Content -LiteralPath $checksumFile -Value "$packageHash  Musico-Windows-x64.zip" -Encoding ASCII

  $compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
  if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) {
    throw 'The .NET Framework C# compiler was not found.'
  }
  & $compiler `
    /nologo `
    /target:winexe `
    "/out:$setupExecutable" `
    "/resource:$outputZip,MusicoBundle.zip" `
    /reference:System.Windows.Forms.dll `
    /reference:System.Drawing.dll `
    /reference:System.IO.Compression.dll `
    /reference:System.IO.Compression.FileSystem.dll `
    (Join-Path $PSScriptRoot 'SetupWizard.cs')
  if ($LASTEXITCODE -ne 0) {
    throw "Setup wizard compilation failed with exit code $LASTEXITCODE."
  }

  Write-Output "Setup executable: $setupExecutable"
  Write-Output "GitHub release asset: $outputZip"
  Write-Output "Release checksum: $checksumFile"
  Write-Output 'Upload the ZIP and its .sha256 file to a published GitHub Release in Noone-prachan/Musico.'
}
finally {
  if (Test-Path -LiteralPath $workingDirectory) {
    Remove-Item -LiteralPath $workingDirectory -Recurse -Force
  }
}
