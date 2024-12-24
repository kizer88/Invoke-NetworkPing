function Test-PrimaryDomainResolution {
    [CmdletBinding()]
    param([hashtable]$Result)
    
    $validation = @{
        Type = 'PrimaryDomain'
        Status = 'Processing'
        Confidence = 0
        Details = @{}
    }
    
    # Check forward/reverse match in primary domain
    $forwardIPs = $Result.Forward.Values | Select-Object -Unique
    $reverseHosts = $Result.Reverse.Values | Select-Object -Unique
    
    $validation.Details = @{
        ForwardIPs = $forwardIPs
        ReverseHosts = $reverseHosts
        MatchStatus = if ($reverseHosts -contains $Result.Target) { 'Match' } else { 'Mismatch' }
    }
    
    $validation.Confidence = switch($validation.Details.MatchStatus) {
        'Match' { 80 }
        'Mismatch' { 20 }
        default { 0 }
    }
    
    $validation.Status = if ($validation.Confidence -ge 80) { 'Success' } else { 'Failed' }
    
    return $validation
}

function Test-CrossDomainResolution {
    [CmdletBinding()]
    param([hashtable]$Result)
    
    $validation = @{
        Type = 'CrossDomain'
        Status = 'Processing'
        Confidence = 0
        Details = @{}
    }
    
    # Check resolution across trusted domains
    $crossDomainResults = @{}
    foreach ($trustedDomain in $trustMap[$Result.Domain].TrustsUp) {
        $crossDomainResults[$trustedDomain] = Test-TrustedDomainResolution -Target $Result.Target -Domain $trustedDomain
    }
    
    $validation.Details = @{
        CrossDomainMatches = $crossDomainResults
        MatchCount = ($crossDomainResults.Values | Where-Object { $_.Status -eq 'Success' }).Count
        TotalChecks = $crossDomainResults.Count
    }
    
    $validation.Confidence = [math]::Min(100, ($validation.Details.MatchCount / $validation.Details.TotalChecks * 100))
    $validation.Status = if ($validation.Confidence -ge 50) { 'Success' } else { 'Failed' }
    
    return $validation
}

function Test-SCCMCorrelation {
    [CmdletBinding()]
    param([hashtable]$Result)
    
    $validation = @{
        Type = 'SCCM'
        Status = 'Processing'
        Confidence = 0
        Details = @{}
    }
    
    # Check SCCM data correlation
    if ($global:syncHash.allSystems.ContainsKey($Result.Target)) {
        $sccmData = $global:syncHash.allSystems[$Result.Target]
        $validation.Details = @{
            SCCMDomain = $sccmData.Domain
            SCCMIPs = $sccmData.IPAddresses
            IPMatch = $false
            DomainMatch = ($sccmData.Domain -eq $Result.Domain)
        }
        
        # Check if any resolved IPs match SCCM data
        $validation.Details.IPMatch = @(Compare-Object $Result.Forward.Values $sccmData.IPAddresses -IncludeEqual -ExcludeDifferent).Count -gt 0
        
        $validation.Confidence = switch ($true) {
            { $validation.Details.IPMatch -and $validation.Details.DomainMatch } { 100 }
            { $validation.Details.IPMatch -or $validation.Details.DomainMatch } { 50 }
            default { 0 }
        }
    }
    
    $validation.Status = if ($validation.Confidence -ge 50) { 'Success' } else { 'Failed' }
    
    return $validation
}

function Get-ValidationClassification {
    [CmdletBinding()]
    param([array]$ValidationChain)
    
    Write-Verbose "Validation Chain Contents:"
    $ValidationChain | ForEach-Object {
        Write-Verbose "Type: $($_.Type), Status: $($_.Status), Confidence: $($_.Confidence)"
    }
    
    # Calculate confidence with explicit type checking
    $validResults = $ValidationChain | Where-Object { 
        $_.Confidence -is [int] -or $_.Confidence -is [double] 
    }
    
    $totalConfidence = if ($validResults -and $validResults.Count -gt 0) {
        ($validResults.Confidence | Measure-Object -Average).Average
    } else {
        0
    }
    
    $category = switch($totalConfidence) {
        {$_ -ge 80} { 'Verified' }
        {$_ -ge 50} { 'Mismatched' }
        {$_ -ge 20} { 'Stale' }
        default { 'Orphaned' }
    }
    
    Write-Verbose "Final Confidence: $totalConfidence, Category: $category"
    
    return @{
        Status = if ($totalConfidence -ge 50) { 'Success' } else { 'Failed' }
        Confidence = $totalConfidence
        Category = $category
    }
}function Test-TrustedDomainResolution {
    [CmdletBinding()]
    param(
        [string]$Target,
        [string]$Domain
    )
    
    $validation = @{
        Status = 'Processing'
        Confidence = 0
        Details = @{}
    }
    
    try {
        # Use domain's DNS servers for resolution
        $dnsServers = $trustMap[$Domain].DNSServers
        $resolution = Resolve-DnsName -Name $Target -Server $dnsServers[0] -ErrorAction Stop
        
        $validation.Status = 'Success'
        $validation.Confidence = 100
        $validation.Details = @{
            IPAddress = $resolution.IPAddress
            Domain = $Domain
            Server = $dnsServers[0]
        }
    }
    catch {
        $validation.Status = 'Failed'
        $validation.Details.Error = $_.Exception.Message
    }
    
    return $validation
}
