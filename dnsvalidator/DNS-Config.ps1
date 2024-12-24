# DNS Validator Configuration
$DNSValidatorConfig = @{
    Performance = @{
        BatchSize = 50
        MaxRunspaces = [Math]::Min(32, [Environment]::ProcessorCount * 2)
        TimeoutMS = 1000
        CacheExpiration = New-TimeSpan -Days 1
        RetryAttempts = 2
    }
    
    ValidationPriority = @{
        LocalDNS = 1     # Primary domain DNS
        SCCM = 2         # Configuration Manager data
        CrossDomain = 3  # Other domain validation
        Historical = 4   # Record history check
    }
    
    Cache = @{
        DNSResponses = [hashtable]::Synchronized(@{})
        SCCMData = [hashtable]::Synchronized(@{})
        ValidationResults = [hashtable]::Synchronized(@{})
    }
}

$DNSValidatorConfig.Cache.DomainMapping = [hashtable]::Synchronized(@{})

$trustMap = @{
    'AUTH' = @{
        'TrustsDown' = @('CVS', 'IM1')
        'TrustedBy' = @()
        'TrustsUp' = @()
    }
    'CVS' = @{
        'TrustsUp' = @('AUTH')
        'TrustedBy' = @('AUTH')
    }
    'IM1' = @{
        'TrustsUp' = @('AUTH')
        'TrustedBy' = @('AUTH')
    }
}
