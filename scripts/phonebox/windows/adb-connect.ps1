[CmdletBinding()]
param(
    [string]$Adb = "adb.exe",
    [string]$HostAddress = "127.0.0.1",
    [int]$Port = 5555
)
$ErrorActionPreference = "Stop"
if ($Port -lt 1 -or $Port -gt 65535) { throw "Invalid ADB port: $Port" }
& $Adb connect "$HostAddress`:$Port"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& $Adb devices
exit $LASTEXITCODE
