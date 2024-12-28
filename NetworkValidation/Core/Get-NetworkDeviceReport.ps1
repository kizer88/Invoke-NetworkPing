function Get-NetworkDeviceReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ComputerNames,

        [Parameter()]
        [switch]$IncludeIPAM,

        [Parameter()]
        [ValidateSet('None', 'Console', 'HTML', 'CSV', 'All')]
        [string]$ReportFormat = 'None',

        [Parameter()]
        [string]$ReportPath,

        [Parameter()]
        [switch]$PassThru
    )

    # Initialize results collection
    $results = @{
        Ping      = Invoke-NetworkPing -ComputerNames $ComputerNames
        DNS       = Test-DomainResolution -ComputerName $ComputerNames
        Network   = $null
        IPAM      = $null
        Timestamp = Get-Date
        Summary   = @{
            TotalDevices = $ComputerNames.Count
            Responding   = 0
            DNSValid     = 0
            IPAMFound    = 0
        }
    }

    if ($IncludeIPAM) {
        $results.IPAM = Get-InfoBloxIPInfo -IPAddress $results.Ping.IPAddress
    }

    # Correlate results
    $consolidated = foreach ($computer in $ComputerNames) {
        $deviceReport = [PSCustomObject]@{
            ComputerName = $computer
            PingStatus   = $results.Ping[$computer].Status
            DNSStatus    = $results.DNS[$computer].ValidationStatus
            IPAddress    = $results.Ping[$computer].IPAddress
            MACAddress   = $results.IPAM[$results.Ping[$computer].IPAddress].MACAddress
            MACVendor    = if ($results.IPAM[$results.Ping[$computer].IPAddress].MACAddress) {
                Get-MACVendor -MACAddress $results.IPAM[$results.Ping[$computer].IPAddress].MACAddress
            } else { "Unknown" }
            IPAMStatus   = $results.IPAM[$results.Ping[$computer].IPAddress].Status
        }

        # Update summary counts
        if ($deviceReport.PingStatus -eq 'Success') { $results.Summary.Responding++ }
        if ($deviceReport.DNSStatus -eq 'Valid') { $results.Summary.DNSValid++ }
        if ($deviceReport.IPAMStatus -eq 'USED') { $results.Summary.IPAMFound++ }

        $deviceReport
    }

    # Handle reporting based on format
    switch ($ReportFormat) {
        'Console' {
            Write-Host "`nNetwork Device Report - $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -ForegroundColor Cyan
            Write-Host "Summary:"
            Write-Host "  Total Devices: $($results.Summary.TotalDevices)"
            Write-Host "  Responding: $($results.Summary.Responding)"
            Write-Host "  DNS Valid: $($results.Summary.DNSValid)"
            if ($IncludeIPAM) {
                Write-Host "  IPAM Found: $($results.Summary.IPAMFound)"
            }
            Write-Host "`nDetailed Results:"
            $consolidated | Format-Table -AutoSize
        }
        'HTML' {
            $reportPath = $ReportPath ?? "NetworkReport-$(Get-Date -Format 'yyyyMMdd-HHmm').html"
            $consolidated | ConvertTo-Html -Title "Network Device Report" | Out-File $reportPath
            Write-Verbose "HTML report saved to: $reportPath"
        }
        'CSV' {
            $reportPath = $ReportPath ?? "NetworkReport-$(Get-Date -Format 'yyyyMMdd-HHmm').csv"
            $consolidated | Export-Csv -Path $reportPath -NoTypeInformation
            Write-Verbose "CSV report saved to: $reportPath"
        }
        'All' {
            Get-NetworkDeviceReport @PSBoundParameters -ReportFormat 'Console'
            Get-NetworkDeviceReport @PSBoundParameters -ReportFormat 'HTML'
            Get-NetworkDeviceReport @PSBoundParameters -ReportFormat 'CSV'
        }
    }

    # Return results if PassThru is specified or no report format
    if ($PassThru -or $ReportFormat -eq 'None') {
        return $consolidated
    }
}
