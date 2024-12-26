# First load Query-SCCMServers
. $PSScriptRoot\Query-SCCMServers.ps1

function Validate-DnsResolution {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string[]]$ComputerName,
        
        [Parameter(Mandatory = $false)]
        [int]$ThrottleLimit = 32,
        
        [Parameter(Mandatory = $false)]
        [switch]$IncludeSccmData
    )

    begin {
        # Initialize domain-specific settings
        $authDnsServers = @('15.97.197.92', '15.97.196.29')
        $results = [System.Collections.Concurrent.ConcurrentBag[PSObject]]::new()
        
        # Create runspace pool for parallel processing
        $runspacePool = [runspacefactory]::CreateRunspacePool(1, $ThrottleLimit)
        $runspacePool.Open()
        $runspaces = @()

        # Initialize progress tracking
        $script:totalComputers = 0
        $script:processedComputers = 0
        $script:progressId = Get-Random

        # Initialize SCCM cache if needed
        if ($null -eq $Global:CachedSystems) {
            $Global:CachedSystems = @{}
        }

        # Ensure SCCM cache is populated
        Write-Progress -Id $progressId -Activity "DNS Validation" -Status "Loading SCCM data..." -PercentComplete 0
        Query-SCCMServers
        Write-Progress -Id $progressId -Activity "DNS Validation" -Status "SCCM data loaded" -PercentComplete 5
    }

    process {
        $script:totalComputers += $ComputerName.Count
        
        foreach ($computer in $ComputerName) {
            Write-Progress -Id $progressId -Activity "DNS Validation" `
                -Status "Processing $computer" `
                -PercentComplete (($script:processedComputers / $script:totalComputers) * 100)

            # Get system info from cache
            $systemInfo = $Global:CachedSystems[$computer]
            
            if (-not $systemInfo) {
                Write-Warning "Cannot find $computer in SCCM cache"
                $results.Add([PSCustomObject]@{
                        ComputerName     = $computer
                        Domain           = $null
                        ValidationStatus = "NotFound"
                        Errors           = @("System not found in SCCM")
                    })
                continue
            }

            $powershell = [powershell]::Create().AddScript({
                    param($Computer, $SystemInfo, $AuthDnsServers)
                
                    $result = [PSCustomObject]@{
                        ComputerName            = $Computer
                        Domain                  = $SystemInfo.Domain
                        FQDN                    = "$Computer.$($SystemInfo.DNSSuffix)"
                        ExpectedIPs             = $SystemInfo.IPAddresses
                        LocalDnsResult          = $null
                        AuthDnsResult           = $null
                        CrossDomainResult       = $null
                        ForwardMatch            = $false
                        ReverseMatch            = $false
                        SccmPresent             = $true
                        ValidationStatus        = 'Unknown'
                        ValidationSteps         = @()
                        Errors                  = @()
                        DomainControllerResults = @()
                        TrustPathValidation     = @{
                            LocalToAuth   = $false
                            AuthToTarget  = $false
                            ResponseTimes = @{}
                        }
                        ReplicationStatus       = @{
                            LastUpdate  = $null
                            Consistency = $false
                            DcAgreement = $false
                        }
                        DnsClientServers        = (Get-DnsClientServerAddress -AddressFamily IPv4 | 
                                Select-Object -ExpandProperty ServerAddresses)
                        ValidationChain         = @{
                            LocalDns    = $false
                            AuthDns     = $false
                            CrossDomain = $false
                        }
                        NetworkConfiguration    = @{
                            PrivateAddressesFound = $false
                            MisconfiguredNICs     = @()
                            NonStandardSubnets    = @()
                        }
                    }

                    try {
                        $result.ValidationSteps += "Starting validation for $($result.FQDN)"

                        # Local DNS check using configured DNS servers
                        foreach ($dnsServer in $result.DnsClientServers) {
                            try {
                                $dnsResult = Resolve-DnsName -Name $result.FQDN -Server $dnsServer -ErrorAction Stop
                                $ipv4Results = $dnsResult | Where-Object { $_.Type -eq 'A' } | Select-Object -ExpandProperty IPAddress
                                if ($ipv4Results) {
                                    $result.LocalDnsResult = $ipv4Results
                                    $result.ValidationSteps += "DNS Server $dnsServer resolution: $($ipv4Results -join ', ')"
                                    $result.ValidationChain.LocalDns = $true
                                    break  # Successfully resolved
                                }
                            }
                            catch {
                                $result.ValidationSteps += "DNS Server $dnsServer failed: $_"
                            }
                        }

                        # AUTH DNS check (using known AUTH DNS servers)
                        foreach ($authServer in @('15.97.197.92', '15.97.196.29')) {
                            try {
                                $authResult = Resolve-DnsName -Name $result.FQDN -Server $authServer -ErrorAction Stop
                                $ipv4Results = $authResult | Where-Object { $_.Type -eq 'A' } | Select-Object -ExpandProperty IPAddress
                                if ($ipv4Results) {
                                    $result.AuthDnsResult = $ipv4Results
                                    $result.ValidationSteps += "AUTH DNS ($authServer) resolution: $($ipv4Results -join ', ')"
                                    $result.ValidationChain.AuthDns = $true
                                    break
                                }
                            }
                            catch {
                                $result.ValidationSteps += "AUTH DNS $authServer failed: $_"
                            }
                        }

                        # Check primary and secondary DCs
                        $domainControllers = Get-DnsClientServerAddress -AddressFamily IPv4 | 
                            Select-Object -ExpandProperty ServerAddresses | Select-Object -First 2

                        $result.DomainControllerResults = @()
                        foreach ($dc in $domainControllers) {
                            try {
                                $dcResult = Resolve-DnsName -Name $result.FQDN -Server $dc -ErrorAction Stop
                                $result.ValidationSteps += "DC $dc resolution: $($dcResult.IPAddress -join ', ')"
                                $result.DomainControllerResults += @{
                                    Server = $dc
                                    IPs    = $dcResult.IPAddress
                                    Time   = (Get-Date)
                                }
                            }
                            catch {
                                $result.ValidationSteps += "DC $dc resolution failed: $_"
                            }
                        }

                        # Compare results with SCCM data
                        if ($SystemInfo.IPAddresses) {
                            # Filter for IPv4 addresses only from SCCM data
                            $expectedIPv4 = $SystemInfo.IPAddresses | Where-Object { $_ -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$' }
                            
                            if ($result.LocalDnsResult) {
                                $result.ForwardMatch = @(Compare-Object $expectedIPv4 @($result.LocalDnsResult) -IncludeEqual -ExcludeDifferent).Count -gt 0
                                $result.ValidationSteps += "IP comparison with Local DNS: $($result.ForwardMatch) (Expected: $($expectedIPv4 -join ', '))"
                            }
                            elseif ($result.AuthDnsResult) {
                                $result.ForwardMatch = @(Compare-Object $expectedIPv4 @($result.AuthDnsResult) -IncludeEqual -ExcludeDifferent).Count -gt 0
                                $result.ValidationSteps += "IP comparison with AUTH DNS: $($result.ForwardMatch) (Expected: $($expectedIPv4 -join ', '))"
                            }
                        }

                        # Reverse DNS lookup
                        if ($result.LocalDnsResult) {
                            try {
                                foreach ($ip in $result.LocalDnsResult) {
                                    $result.ValidationSteps += "Attempting reverse DNS lookup for $ip"
                                    $reverse = Resolve-DnsName -Name $ip -Type PTR -ErrorAction Stop
                                    
                                    # Check if reverse points back to our FQDN
                                    if ($reverse.NameHost -eq $result.FQDN) {
                                        $result.ReverseMatch = $true
                                        $result.ValidationSteps += "Reverse DNS lookup successful: $($reverse.NameHost) matches FQDN"
                                        break  # Found a matching reverse record
                                    }
                                    else {
                                        $result.ValidationSteps += "Reverse DNS mismatch: Got $($reverse.NameHost), expected $($result.FQDN)"
                                    }
                                }
                            }
                            catch {
                                $result.ValidationSteps += "Reverse DNS lookup failed: $_"
                            }
                        }

                        # Trust path validation
                        if ($result.Domain -eq 'CVS') {
                            try {
                                if ($result.LocalDnsResult) {
                                    $result.TrustPathValidation.LocalToAuth = $true
                                    $result.ValidationSteps += "CVS local DNS resolution successful"
                                    
                                    if ($result.AuthDnsResult) {
                                        $result.ValidationSteps += "CVS->AUTH path validated"
                                        
                                        # Only check IM1 path if target is in IM1
                                        if ($targetDomain -eq 'IM1' -and $result.AuthDnsResult) {
                                            $result.TrustPathValidation.AuthToTarget = $true
                                            $result.ValidationSteps += "AUTH->IM1 path validated"
                                        }
                                    }
                                }
                            }
                            catch {
                                $result.ValidationSteps += "Trust path validation error: $_"
                            }
                        }

                        # Check DC replication consistency
                        if ($result.DomainControllerResults.Count -gt 1) {
                            $firstDC = $result.DomainControllerResults[0].IPs | Where-Object { $_ -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$' }
                            $secondDC = $result.DomainControllerResults[1].IPs | Where-Object { $_ -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$' }
                            
                            if ($firstDC -and $secondDC) {
                                try {
                                    # Only compare IPv4 addresses
                                    $result.ReplicationStatus.DcAgreement = 
                                    @(Compare-Object $firstDC $secondDC -SyncWindow 0 -ErrorAction Stop).Count -eq 0
                                    
                                    $result.ValidationSteps += "DC replication check: $($firstDC -join ', ') vs $($secondDC -join ', ')"
                                    $result.ValidationSteps += "DC agreement: $($result.ReplicationStatus.DcAgreement)"
                                }
                                catch {
                                    $result.ValidationSteps += "DC comparison failed: $_"
                                    $result.ReplicationStatus.DcAgreement = $false
                                }
                            }
                            else {
                                $result.ValidationSteps += "Insufficient IPv4 data for DC comparison"
                                $result.ReplicationStatus.DcAgreement = $false
                            }
                        }

                        # Check for non-standard subnets (anything not 15.x.x.x)
                        if ($result.LocalDnsResult) {
                            $nonStandardIPs = $result.LocalDnsResult | Where-Object { $_ -notmatch '^15\.' }
                            if ($nonStandardIPs) {
                                $result.NetworkConfiguration.PrivateAddressesFound = $true
                                $result.NetworkConfiguration.MisconfiguredNICs = $nonStandardIPs
                                $result.ValidationSteps += "WARNING: Non-standard IP addresses found: $($nonStandardIPs -join ', ')"
                                $result.ValidationSteps += "System may have misconfigured secondary NICs (expected 15.x.x.x range only)"
                            }
                        }

                        # Determine validation status
                        $result.ValidationStatus = if ($result.LocalDnsResult) {
                            if ($result.AuthDnsResult) {
                                # Both DNS resolutions worked
                                if ($result.ForwardMatch) {
                                    if ($result.ReverseMatch) {
                                        "FullyVerified"
                                    }
                                    else {
                                        "Verified"
                                    }
                                }
                                else {
                                    "Mismatched"
                                }
                            }
                            else {
                                # Only Local DNS worked
                                if ($result.ForwardMatch) {
                                    "AuthDNSIssue"
                                }
                                else {
                                    "Failed"
                                }
                            }
                        }
                        elseif ($result.AuthDnsResult) {
                            # Only AUTH DNS worked
                            if ($result.ForwardMatch) {
                                "LocalDNSIssue"
                            }
                            else {
                                "Failed"
                            }
                        }
                        else {
                            "Failed"
                        }
                    }
                    catch {
                        $result.Errors += $_.Exception.Message
                        $result.ValidationStatus = "Error"
                    }

                    return $result
                }).AddArgument($computer).AddArgument($systemInfo).AddArgument($authDnsServers)

            $powershell.RunspacePool = $runspacePool

            $runspaces += @{
                PowerShell = $powershell
                Handle     = $powershell.BeginInvoke()
                Computer   = $computer
                StartTime  = Get-Date
            }
        }
    }

    end {
        # Collect results with progress
        while ($runspaces) {
            $completed = $runspaces | Where-Object { $_.Handle.IsCompleted }
            
            foreach ($runspace in $completed) {
                $script:processedComputers++
                
                # Calculate completion percentage and elapsed time
                $percentComplete = ($script:processedComputers / $script:totalComputers) * 100
                $elapsedTime = New-TimeSpan -Start $runspace.StartTime -End (Get-Date)
                
                Write-Progress -Id $progressId -Activity "DNS Validation" `
                    -Status "Processing $($runspace.Computer) | Elapsed: $($elapsedTime.ToString('hh\:mm\:ss'))" `
                    -PercentComplete $percentComplete `
                    -CurrentOperation "$script:processedComputers of $script:totalComputers computers processed"

                $results.Add($runspace.PowerShell.EndInvoke($runspace.Handle))
                $runspace.PowerShell.Dispose()
            }
            
            $runspaces = $runspaces | Where-Object { -not $_.Handle.IsCompleted }
            Start-Sleep -Milliseconds 100  # Prevent CPU spinning
        }

        Write-Progress -Id $progressId -Activity "DNS Validation" -Status "Complete" -PercentComplete 100 -Completed
        
        $runspacePool.Close()
        $runspacePool.Dispose()

        # Calculate summary statistics
        $summary = @{
            Total         = $script:totalComputers
            FullyVerified = ($results | Where-Object { $_.ValidationStatus -eq 'FullyVerified' }).Count
            Verified      = ($results | Where-Object { $_.ValidationStatus -eq 'Verified' }).Count
            Failed        = ($results | Where-Object { $_.ValidationStatus -eq 'Failed' }).Count
            Mismatched    = ($results | Where-Object { $_.ValidationStatus -eq 'Mismatched' }).Count
            LocalDNSIssue = ($results | Where-Object { $_.ValidationStatus -eq 'LocalDNSIssue' }).Count
            AuthDNSIssue  = ($results | Where-Object { $_.ValidationStatus -eq 'AuthDNSIssue' }).Count
            NotFound      = ($results | Where-Object { $_.ValidationStatus -eq 'NotFound' }).Count
            Errors        = ($results | Where-Object { $_.Errors.Count -gt 0 }).Count
        }

        # Display summary with colors
        Write-Host "`nValidation Summary:" -ForegroundColor Cyan
        Write-Host "Total computers processed: $($summary.Total)" -ForegroundColor White
        Write-Host "Fully Verified (Forward + Reverse): $($summary.FullyVerified)" -ForegroundColor Green
        Write-Host "Verified (Forward Only): $($summary.Verified)" -ForegroundColor Yellow
        Write-Host "Failed: $($summary.Failed)" -ForegroundColor Red
        Write-Host "Local DNS Issues: $($summary.LocalDNSIssue)" -ForegroundColor Yellow
        Write-Host "Auth DNS Issues: $($summary.AuthDNSIssue)" -ForegroundColor Yellow
        Write-Host "Mismatched: $($summary.Mismatched)" -ForegroundColor Red
        Write-Host "Not Found in SCCM: $($summary.NotFound)" -ForegroundColor Red
        Write-Host "Errors encountered: $($summary.Errors)" -ForegroundColor Red

        # Return results sorted by status (most critical first)
        return $results | Sort-Object -Property @{
            Expression = {
                switch ($_.ValidationStatus) {
                    'Error' { 0 }
                    'Failed' { 1 }
                    'Mismatched' { 2 }
                    'LocalDNSIssue' { 3 }
                    'AuthDNSIssue' { 4 }
                    'NotFound' { 5 }
                    'Verified' { 6 }
                    'FullyVerified' { 7 }
                    default { 8 }
                }
            }
        }
    }
}

# Define domain configuration at script scope
$script:serversdomains = @{
    'IM1' = @{
        'DNSSuffix'  = 'IM1.MFG.HPICORP.NET'
        'CMServer'   = 'MTO-SCCM.im1.mfg.hpicorp.net'
        'CMSiteCode' = 'USM'
        'Namespace'  = 'root\sms\site_USM'
    }
    'CVS' = @{
        'DNSSuffix'  = 'CVS.RD.ADAPPS.HP.COM'
        'CMServer'   = 'AM1-SCCM01-COR.rd.hpicorp.net'
        'CMSiteCode' = 'AM1'
        'Namespace'  = 'root\sms\site_AM1'
    }
}

function Get-SystemLocation {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ComputerName,
        
        [Parameter(Mandatory = $false)]
        [hashtable]$DomainConfig = $script:serversdomains
    )
    
    foreach ($domain in $DomainConfig.Keys) {
        $sccmServer = $DomainConfig[$domain].CMServer
        $namespace = $DomainConfig[$domain].Namespace
        
        Write-Verbose "Checking $domain SCCM ($sccmServer) for $ComputerName"
        
        try {
            if ($domain -eq 'CVS') {
                # CVS domain uses direct WMI
                $system = Get-WmiObject -ComputerName $sccmServer `
                    -Namespace $namespace `
                    -Class SMS_R_System `
                    -Filter "Name='$ComputerName'" `
                    -ErrorAction Stop
            }
            else {
                # IM1 domain uses WinRM
                $system = Invoke-Command -ComputerName $sccmServer -ScriptBlock {
                    param($ns, $comp)
                    Get-WmiObject -Namespace $ns -Class SMS_R_System -Filter "Name='$comp'"
                } -ArgumentList $namespace, $ComputerName -ErrorAction Stop
            }
            
            if ($system) {
                Write-Verbose "Found $ComputerName in $domain SCCM"
                return @{
                    Domain   = $domain
                    FQDN     = "$ComputerName.$($DomainConfig[$domain].DNSSuffix)"
                    SccmData = $system
                }
            }
        }
        catch {
            Write-Verbose "Error querying $domain SCCM: $_"
        }
    }
    return $null
} 