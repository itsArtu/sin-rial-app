param(
    [Parameter(Mandatory = $true)][string]$Apk,
    [Parameter(Mandatory = $true)][string]$Device,
    [Parameter(Mandatory = $true)][string]$Flutter,
    [Parameter(Mandatory = $true)][string]$Aapt
)

$ErrorActionPreference = 'Stop'
$apkPath = (Resolve-Path -LiteralPath $Apk).Path
$metadata = & $Aapt dump badging $apkPath
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect APK.' }
$packageLine = $metadata | Where-Object { $_.StartsWith('package:') } | Select-Object -First 1
if ($packageLine -notmatch "^package: name='com\.lacaprichosa\.benchmark'") {
    throw 'Refusing to profile a non-benchmark package.'
}

# Use the inspected APK identity, never the source namespace. Do not uninstall.
& $Flutter drive --no-pub --no-dds --keep-app-running --profile `
    "--use-application-binary=$apkPath" `
    --driver=test_driver/performance_driver.dart `
    --target=integration_test/performance_test.dart -d $Device
exit $LASTEXITCODE
