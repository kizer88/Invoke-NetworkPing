function Invoke-DNSResolutionWorker {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Target,
        
        [Parameter(Mandatory)]
        [string]$Domain,
        
        [System.Management.Automation.Runspaces.RunspacePool]$RunspacePool,
        
        [switch]$ForceRefresh
    )
    
    $scriptBlock = {
        param($Target, $Domain, $Config, $TrustMap, $ForceRefresh)
        
        $result = @{
            Target = $Target
            Domain = $Domain
            Forward = @{}
            Reverse = @{}
            Timestamp = Get-Date
            Status = 'Processing'
        }
        
        # Check cache first unless forced refresh
        if (!$ForceRefresh -and $Config.Cache.DNSResponses.ContainsKey($Target)) {
            $cachedResult = $Config.Cache.DNSResponses[$Target]
            if ((Get-Date) -lt $cachedResult.Timestamp + $Config.Performance.CacheExpiration) {
                return $cachedResult
            }
        }
        
        try {
            # Forward Resolution
            foreach ($dnsServer in $TrustMap[$Domain].DNSServers) {
                $resolveResult = Resolve-DnsName -Name $Target -Server $dnsServer -ErrorAction Stop
                $result.Forward[$dnsServer] = $resolveResult.IPAddress
            }
            
            # Reverse Resolution for each IP found
            foreach ($ip in $result.Forward.Values | Select-Object -Unique) {
                $reverseResult = Resolve-DnsName -Name $ip -Server $TrustMap[$Domain].DNSServers[0] -ErrorAction Stop
                $result.Reverse[$ip] = $reverseResult.NameHost
            }
            
            $result.Status = 'Success'
        }
        catch {
            $result.Status = 'Error'
            $result.ErrorDetails = $_.Exception.Message
        }
        
        # Cache the result
        $Config.Cache.DNSResponses[$Target] = $result
        
        return $result
    }
    
    $powerShell = [powershell]::Create().AddScript($scriptBlock)
    $powerShell.RunspacePool = $RunspacePool
    
    $job = $powerShell.AddArgument($Target).
                       AddArgument($Domain).
                       AddArgument($DNSValidatorConfig).
                       AddArgument($trustMap).
                       AddArgument($ForceRefresh).
                       BeginInvoke()
    
    return @{
        PowerShell = $powerShell
        Job = $job
        Target = $Target
        Domain = $Domain
    }
}
