param(
  [string]$ReleaseDir,
  [string]$DistDir,
  [string]$AppExeName = "flowpilot.exe"
)

$ErrorActionPreference = "Stop"

$ProjectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$Config = Get-Content -LiteralPath (Join-Path $ProjectRoot "src-tauri\tauri.conf.json") -Raw | ConvertFrom-Json
$ProductName = $Config.productName
$Version = $Config.version

if (-not $ReleaseDir) {
  $ReleaseDir = Join-Path $ProjectRoot "src-tauri\target\x86_64-pc-windows-gnu\release"
}

if (-not $DistDir) {
  $DistDir = Join-Path $ProjectRoot "dist-windows"
}

$InstallerName = "${ProductName}_${Version}_x64-setup.exe"
$MsiName = "${ProductName}_${Version}_x64_en-US.msi"
$InstallerSource = Join-Path $ReleaseDir "bundle\nsis\$InstallerName"
$MsiSource = Join-Path $ReleaseDir "bundle\msi\$MsiName"
$ExeSource = Join-Path $ReleaseDir $AppExeName
$WebViewLoaderSource = Join-Path $ReleaseDir "WebView2Loader.dll"

$RequiredFiles = @($InstallerSource, $MsiSource, $ExeSource, $WebViewLoaderSource)
foreach ($File in $RequiredFiles) {
  if (-not (Test-Path -LiteralPath $File)) {
    throw "Required runtime file was not found: $File"
  }
}

New-Item -ItemType Directory -Path $DistDir -Force | Out-Null

$InstallerDest = Join-Path $DistDir $InstallerName
$MsiDest = Join-Path $DistDir $MsiName
$ExeDest = Join-Path $DistDir $AppExeName
$WebViewLoaderDest = Join-Path $DistDir "WebView2Loader.dll"
$PortableDir = Join-Path $DistDir "${ProductName}-${Version}-portable"
$PortableZip = Join-Path $DistDir "${ProductName}-${Version}-portable.zip"

Copy-Item -LiteralPath $InstallerSource -Destination $InstallerDest -Force
Copy-Item -LiteralPath $MsiSource -Destination $MsiDest -Force
Copy-Item -LiteralPath $ExeSource -Destination $ExeDest -Force
Copy-Item -LiteralPath $WebViewLoaderSource -Destination $WebViewLoaderDest -Force

if (Test-Path -LiteralPath $PortableDir) {
  Remove-Item -LiteralPath $PortableDir -Recurse -Force
}

New-Item -ItemType Directory -Path $PortableDir -Force | Out-Null
Copy-Item -LiteralPath $ExeSource -Destination (Join-Path $PortableDir "$ProductName.exe") -Force
Copy-Item -LiteralPath $WebViewLoaderSource -Destination (Join-Path $PortableDir "WebView2Loader.dll") -Force

$ReadmeTemplateBase64 = "e3tQUk9EVUNUX05BTUV9fSB7e1ZFUlNJT059fSBQb3J0YWJsZQoK7Iuk7ZaJIOuwqeuylToKMS4g7J20IO2PtOuNlOulvCDsm5DtlZjripQg7JyE7LmY7JeQIOyVley2lSDtlbTsoJztlanri4jri6QuCjIuIHt7UFJPRFVDVF9OQU1FfX0uZXhl66W8IOyLpO2Wie2VqeuLiOuLpC4KCu2PrO2VqCDtjIzsnbw6Ci0ge3tQUk9EVUNUX05BTUV9fS5leGUKLSBXZWJWaWV3MkxvYWRlci5kbGwKCu2VhOyalCDsobDqsbQ6Ci0gV2luZG93cyAxMC8xMQotIE1pY3Jvc29mdCBFZGdlIFdlYlZpZXcyIFJ1bnRpbWUKICDrs7TthrUgV2luZG93cyAxMeqzvCDstZzsi6AgV2luZG93cyAxMOyXkOuKlCDsnbTrr7gg7ISk7LmY65CY7Ja0IOyeiOyKteuLiOuLpC4K"
$ReadmeTemplate = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($ReadmeTemplateBase64))
$Readme = $ReadmeTemplate.Replace("{{PRODUCT_NAME}}", $ProductName).Replace("{{VERSION}}", $Version)
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Join-Path $PortableDir "README.txt"), $Readme, $Utf8NoBom)

if (Test-Path -LiteralPath $PortableZip) {
  Remove-Item -LiteralPath $PortableZip -Force
}

Compress-Archive -LiteralPath $PortableDir -DestinationPath $PortableZip -Force

Get-ChildItem -LiteralPath $InstallerDest, $MsiDest, $ExeDest, $WebViewLoaderDest, $PortableZip |
  Select-Object FullName, Length, LastWriteTime
