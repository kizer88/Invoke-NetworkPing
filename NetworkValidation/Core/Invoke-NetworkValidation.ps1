function Invoke-NetworkValidation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string[]]$ComputerNames,

        [Parameter()]
        [ValidateSet('Basic', 'Advanced', 'Subnet')]
        [string]$ScanMode = 'Basic',

        [Parameter()]
        [IPAddress]$SubnetStart,

        [Parameter()]
        [IPAddress]$SubnetEnd,

        [Parameter()]
        [switch]$CorrelateResults,

        [Parameter()]
        [switch]$ExportToExcel
    )

    begin {
        # Load all three scripts
        . "$PSScriptRoot\Invoke-NetworkPing.ps1"
        . "$PSScriptRoot\Test-DomainResolution.ps1"
        . "$PSScriptRoot\IPv4NetworkScan.ps1"

        # Initialize result tracking
        $results = @{
            HostResults   = @{}
            DnsValidation = @{}
            Summary       = @{
                TotalProcessed  = 0
                FullyVerified   = 0
                ForwardVerified = 0
                Failed          = 0
                LocalDNSIssues  = 0
                AuthDNSIssues   = 0
                Mismatched      = 0
                NotInSCCM       = 0
                Errors          = 0
            }
            NetworkStatus = @{
                Total          = 0
                Online         = 0
                Offline        = 0
                OnlinePercent  = 0
                OfflinePercent = 0
            }
        }

        # Validation strategy based on scan mode
        $strategy = @{
            'Basic'    = @{
                UseDNS    = $true
                UsePing   = $true
                UseSubnet = $false
            }
            'Advanced' = @{
                UseDNS            = $true
                UsePing           = $true
                UseSubnet         = $true
                ValidateResponses = $true
            }
            'Subnet'   = @{
                UseDNS     = $false
                UsePing    = $false
                UseSubnet  = $true
                MapNetwork = $true
            }
        }

        function Show-ValidationMenu {
            $menuOptions = @{
                1 = "Quick Ping Test"
                2 = "Advanced Network Validation"
                3 = "Subnet Scanner"
                4 = "DNS Resolution Check"
                5 = "IPAM Query"
                6 = "Full Network Analysis"
                Q = "Quit"
            }

            do {
                Clear-Host
                Write-Host "=== HP Network Validation Tool ===" -ForegroundColor Cyan
                Write-Host "Select an operation:"
                foreach ($key in $menuOptions.Keys | Sort-Object) {
                    Write-Host "$key. $($menuOptions[$key])"
                }

                $choice = Read-Host "`nEnter selection"

                switch ($choice) {
                    1 { Invoke-NetworkPing }
                    2 { Invoke-NetworkValidation -Advanced }
                    3 { Invoke-IPv4NetworkScan }
                    4 { Test-DomainResolution }
                    5 { Get-InfoBloxIPInfo }
                    6 { Start-FullNetworkAnalysis }
                    'Q' { return }
                }

                if ($choice -ne 'Q') {
                    Read-Host "`nPress Enter to continue"
                }
            } while ($choice -ne 'Q')
        }
    }

    process {
        foreach ($computer in $ComputerNames) {
            $results.HostResults[$computer] = @{
                DnsStatus        = 'Unknown'
                PingStatus       = 'Unknown'
                SubnetValidation = 'NotChecked'
                Confidence       = 'Low'
                IpAddresses      = @()
                Warnings         = @()
            }

            # Step 1: DNS Validation (if enabled)
            if ($strategy[$ScanMode].UseDNS) {
                $dnsCheck = Test-DomainResolution -ComputerName $computer
                $results.DnsValidation[$computer] = $dnsCheck
                $results.HostResults[$computer].DnsStatus = $dnsCheck.ValidationStatus
                $results.HostResults[$computer].IpAddresses += $dnsCheck.ExpectedIPs
            }

            # Step 2: Ping Validation (if enabled)
            if ($strategy[$ScanMode].UsePing) {
                $pingCheck = Invoke-NetworkPing -ComputerNames $computer
                $results.HostResults[$computer].PingStatus = $pingCheck.Status

                # Cross-reference ping results with DNS
                if ($strategy[$ScanMode].UseDNS) {
                    if ($pingCheck.Status -eq 'Online' -and
                        $dnsCheck.ValidationStatus -ne 'Verified') {
                        $results.HostResults[$computer].Warnings += "Online but DNS suspicious"
                        $results.Correlation.Suspicious += $computer
                    }
                }
            }

            # Step 3: Subnet Validation (if enabled)
            if ($strategy[$ScanMode].UseSubnet -and $SubnetStart -and $SubnetEnd) {
                $subnetScan = Invoke-IPv4NetworkScan -StartIPv4Address $SubnetStart `
                    -EndIPv4Address $SubnetEnd `
                    -DisableMACResolving

                # Correlate subnet findings with DNS/Ping results
                $matchingIPs = $subnetScan | Where-Object {
                    $_.Status -eq 'Up' -and
                    $_.IPv4Address -in $results.HostResults[$computer].IpAddresses
                }

                if ($matchingIPs) {
                    $results.HostResults[$computer].SubnetValidation = 'Confirmed'
                    $results.HostResults[$computer].Confidence = 'High'
                }
            }

            # Calculate result confidence
            $results.HostResults[$computer].Confidence = switch ($true) {
                # High confidence cases
                { $_.DnsStatus -eq 'Verified' -and
                    $_.PingStatus -eq 'Online' -and
                    $_.SubnetValidation -eq 'Confirmed' } { 'VeryHigh' }

                # Medium confidence cases
                { $_.DnsStatus -eq 'Verified' -and
                    $_.PingStatus -eq 'Online' } { 'High' }

                # Low confidence cases
                { $_.DnsStatus -ne 'Verified' -or
                    $_.Warnings.Count -gt 0 } { 'Low' }

                # Default
                default { 'Unknown' }
            }
        }
    }

    end {
        # Generate summary
        $summary = @{
            TotalHosts     = $ComputerNames.Count
            HighConfidence = ($results.HostResults.Values | Where-Object { $_.Confidence -in 'High', 'VeryHigh' }).Count
            Suspicious     = $results.Correlation.Suspicious.Count
            Conflicts      = $results.Correlation.Conflicts.Count
            ScanMode       = $ScanMode
            TimeStamp      = Get-Date
        }

        if ($ExportToExcel) {
            $results | Export-Excel -Path "NetworkValidation-$(Get-Date -Format 'yyyyMMdd-HHmm').xlsx" -AutoSize
        }

        # Return results object
        [PSCustomObject]@{
            Summary         = $summary
            DetailedResults = $results.HostResults
            DnsValidation   = $results.DnsValidation
            Correlation     = $results.Correlation
        }
    }
}
