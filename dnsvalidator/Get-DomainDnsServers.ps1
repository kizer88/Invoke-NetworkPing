function Get-DomainDNSServers {
    [CmdletBinding()]
    param()
    
    $config = @{
        Domains = @{
            'IM1' = @{
                'DNSSuffix' = 'IM1.MFG.HPICORP.NET'
                'CMServer' = 'MTO-SCCM.im1.mfg.hpicorp.net'
                'CMSiteCode' = 'USM'
                'Namespace' = 'root\sms\site_USM'
            }
            'CVS' = @{
                'DNSSuffix' = 'CVS.RD.ADAPPS.HP.COM'
                'CMServer' = 'AM1-SCCM01-COR.rd.hpicorp.net'
                'CMSiteCode' = 'AM1'
                'Namespace' = 'root\sms\site_AM1'
            }
            'AUTH' = @{
                'DNSSuffix' = 'AUTH.HPICORP.NET'
            }
        }
    }

    $dnsMap = @{}
    
    foreach ($domain in $config.Domains.Keys) {
        $dnsServers = @()
        
        try {
            $servers = Get-WmiObject -Class Win32_NetworkAdapterConfiguration -Filter "IPEnabled='True'" |
                Select-Object -ExpandProperty DNSServerSearchOrder
            
            $nslookupResult = nslookup -type=ns "$($config.Domains[$domain].DNSSuffix)" 2>$null
            $nsServers = $nslookupResult | Where-Object { $_ -match 'nameserver = (.+)' } | 
                ForEach-Object { $matches[1].Trim() }
            
            $dnsServers = @($servers + $nsServers | Select-Object -Unique)
            
            $role = switch($domain) {
                'AUTH' { 'Enterprise' }
                default { 'Child' }
            }
            
            $dnsMap[$domain] = @{
                'Servers' = $dnsServers
                'Role' = $role
                'DNSSuffix' = $config.Domains[$domain].DNSSuffix
                'LastUpdated' = Get-Date
            }
            
            Write-Verbose "Successfully mapped DNS servers for $domain"
        }
        catch {
            Write-Warning "Failed to get DNS servers for $domain : $_"
        }
    }
    
    return $dnsMap
}

$queryOptimization = @{
    'BatchSize' = 50
    'MaxRunspaces' = 32
    'TimeoutMS' = 1000
    'CacheExpiration' = '1.00:00:00'  # 1 day
    'RetryAttempts' = 2
}

$validationPriority = @{
    'LocalDNS' = 1    # Fastest, most relevant
    'SCCM' = 2        # Cached data
    'CrossDomain' = 3 # Only if needed
    'Historical' = 4  # Background task
}
