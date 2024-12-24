# Import all component scripts
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$dnsValidatorPath = Join-Path $scriptPath "dnsvalidator"

# Load components in order
. (Join-Path $dnsValidatorPath "DNS-Config.ps1")
. (Join-Path $dnsValidatorPath "Get-DomainDnsServers.ps1")
. (Join-Path $dnsValidatorPath "Initialize-DNSRunspacePool.ps1")
. (Join-Path $dnsValidatorPath "Get-TargetDomain.ps1")
. (Join-Path $dnsValidatorPath "Invoke-DNSResolutionWorker.ps1")
. (Join-Path $dnsValidatorPath "Invoke-DNSBatchProcessor.ps1")
. (Join-Path $dnsValidatorPath "Test-DNSValidationFunctions.ps1")
. (Join-Path $dnsValidatorPath "Invoke-DNSValidationProcessor.ps1")

function Invoke-DNSValidator {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Targets,
        [switch]$ForceRefresh,
        [switch]$Detailed,
        [switch]$Report
    )

    Write-Verbose "Starting DNS validation for $($Targets.Count) targets"
    
    # Initialize DNS server mapping
    $DNS = Get-DomainDNSServers
    Write-Verbose "Mapped DNS servers across domains"
    
    # Process targets in batches
    $dnsResults = Invoke-DNSBatchProcessor -Targets $Targets -ForceRefresh:$ForceRefresh
    Write-Verbose "Completed DNS resolution for all targets"
    
    # Validate results
    $validationResults = Invoke-DNSValidationProcessor -DNSResults $dnsResults
    
    if ($Report) {
        foreach ($target in $Targets) {
            $result = $validationResults | Where-Object { $_.Target -eq $target }
            
            Write-Host "`n=== DNS Validation Report for $target ===" -ForegroundColor Cyan
            
            Write-Host "`nDNS Validation Results:" -ForegroundColor Yellow
            $result.ValidationChain | ForEach-Object {
                Write-Host "- $($_.Type): $($_.Status) ($($_.Confidence)% confidence)"
                if ($_.Details) {
                    foreach ($detail in $_.Details.GetEnumerator()) {
                        Write-Host "  > $($detail.Key): $($detail.Value)"
                    }
                }
            }
            
            Write-Host "`nNetwork Connectivity:" -ForegroundColor Yellow
            $netStatus = $global:syncHash.AsyncResult | Where-Object { $_.ComputerName -eq $target }
            Write-Host "- Ping Status: $($netStatus.Status)"
            Write-Host "- Response Time: $($netStatus.ResponseTime)ms"
            Write-Host "- FQDN: $($netStatus.FQDN)"
            
            Write-Host "`nSystem State:" -ForegroundColor Yellow
            Write-Host "- Domain: $($result.Domain)"
            Write-Host "- Overall Status: $($result.Status)"
            Write-Host "- Final Confidence: $($result.Confidence)%"
            Write-Host "- Classification: $($result.Category)"
            
            Write-Host "`n" + "="*50 + "`n"
        }
    }

    if ($Detailed) {
        return $validationResults
    }
    else {
        return @{
            Summary = @{
                Total = $Targets.Count
                Verified = $validationResults.Verified.Count
                Mismatched = $validationResults.Mismatched.Count
                Stale = $validationResults.Stale.Count
                Orphaned = $validationResults.Orphaned.Count
            }
            Results = $validationResults
        }
    }
}

# Example usage:
# $results = Invoke-DNSValidator -Targets "MYPC01","MYPC02" -Verbose -Detailed -Report
