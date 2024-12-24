function Get-TargetDomain {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Target
    )
    
    # Quick cache check
    if ($DNSValidatorConfig.Cache.DomainMapping.ContainsKey($Target)) {
        return $DNSValidatorConfig.Cache.DomainMapping[$Target]
    }
    
    # Domain detection logic
    $domain = switch -Regex ($Target) {
        # FQDN matching
        '\.IM1\.MFG\.HPICORP\.NET$' { 'IM1' }
        '\.CVS\.RD\.ADAPPS\.HP\.COM$' { 'CVS' }
        '\.AUTH\.HPICORP\.NET$' { 'AUTH' }
        
        # IP address handling
        '^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$' {
            # Default to AUTH for IP lookups
            'AUTH'
        }
        
        # SCCM correlation
        default {
            if ($global:syncHash.allSystems.ContainsKey($Target)) {
                $global:syncHash.allSystems[$Target].Domain
            }
            else {
                'IM1' # Default domain if no match
            }
        }
    }
    
    # Cache the result
    $DNSValidatorConfig.Cache.DomainMapping[$Target] = $domain
    
    return $domain
}
