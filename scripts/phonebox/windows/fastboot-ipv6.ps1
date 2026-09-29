[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Address,
    [int]$Port = 5554,
    [string]$Fastboot = "fastboot.exe",
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$FastbootArguments
)
$ErrorActionPreference = "Stop"
if ($Port -lt 1 -or $Port -gt 65535) { throw "Invalid Fastboot TCP port: $Port" }
$endpoint = "tcp:$Address`:$Port"
& $Fastboot $endpoint @FastbootArguments
exit $LASTEXITCODE
