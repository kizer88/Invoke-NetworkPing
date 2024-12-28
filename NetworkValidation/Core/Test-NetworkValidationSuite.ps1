<#
.SYNOPSIS
    Comprehensive test suite for Network Validation toolkit.

.DESCRIPTION
    Runs all network validation components against specified targets and generates detailed reports.
    Uses MyTargets.txt as input and produces both JSON and HTML reports.

.PARAMETER TargetsPath
    Path to targets file. Defaults to MyTargets.txt in root directory.

.PARAMETER GenerateReport
    Switch to generate HTML report. Default is True.

.EXAMPLE
    Test-NetworkValidationSuite -TargetsPath "D:\Pingz\Network-Ping\MyTargets.txt"
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$TargetsPath = "D:\Pingz\Network-Ping\MyTargets.txt",

    [Parameter()]
    [switch]$GenerateReport = $true
)

# Load required functions
$modulePath = "D:\Pingz\Network-Ping\NetworkValidation"
Write-Verbose "Loading Core functions..."
. "$modulePath\Validators\Test-DomainResolution.ps1"
. "$modulePath\Scanners\Test-NetworkConnection.ps1"

# Verify targets file exists
if (-not (Test-Path $TargetsPath)) {
    throw "Targets file not found at: $TargetsPath"
}

# Get test targets
$testTargets = Get-Content $TargetsPath | Where-Object { $_ -match '\S' }

Write-Verbose "Starting validation suite..."

# 1. Initialize SCCM cache (this builds $Global:CachedSystems)
# Write-Verbose "Building SCCM cache..."
# Get-SCCMInventory
# 3. Run network connectivity tests
Write-Verbose "Testing network connectivity..."
$pingResults = Test-NetworkConnection -ComputerNames $testTargets
# 2. Run DNS validation
Write-Verbose "Running DNS validation..."
$dnsResults = Test-DomainResolution -ComputerName $testTarget

# Return results
$results = @{
    DNS       = $dnsResults
    Network   = $pingResults
    Timestamp = Get-Date
}

return $results
