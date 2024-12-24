
function Invoke-DNSValidator {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Targets,
        [switch]$ForceRefresh,
        [switch]$Detailed,
        [switch]$Report
    )

    # ... existing validation logic ...

    if ($Report) {
        foreach ($target in $validationResults.Keys) {
            $result = $validationResults[$target]
            
            Write-Host "`n=== DNS Validation Report for $($result.Target) ===" -ForegroundColor Cyan
            
            Write-Host "`nDNS Validation Results:" -ForegroundColor Yellow
            $result.ValidationChain | ForEach-Object {
                Write-Host "- $($_.Type): $($_.Status) ($($_.Confidence)% confidence)"
            }
            
            Write-Host "`nNetwork Connectivity:" -ForegroundColor Yellow
            $netStatus = $global:syncHash.AsyncResult | Where-Object { $_.ComputerName -eq $result.Target }
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
    
    return $validationResults
}
