function Query-SCCMServers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [hashtable]$DomainConfig = $script:serversdomains
    )
    
    Write-Verbose "Initializing SCCM system cache..."
    
    # Define cache file path
    $cachePath = Join-Path $PSScriptRoot "SCCMCache.xml"
    
    # Try to load existing cache if it exists and is less than 24 hours old
    if (Test-Path $cachePath) {
        $cacheAge = (Get-Date) - (Get-Item $cachePath).LastWriteTime
        if ($cacheAge.TotalHours -lt 24) {
            Write-Verbose "Loading SCCM cache from file (Age: $($cacheAge.TotalHours) hours)"
            $Global:CachedSystems = Import-Clixml -Path $cachePath
            $global:DNSValidatorHash = @{}
            $global:DNSValidatorHash.allSystems = $Global:CachedSystems.Clone()
            Write-Verbose "Loaded $(($Global:CachedSystems.Keys).Count) systems from cache"
            return $true
        }
        else {
            Write-Verbose "Cache file exists but is older than 24 hours. Refreshing..."
        }
    }

    # Initialize new cache if needed
    if ($null -eq $Global:CachedSystems) {
        $Global:CachedSystems = @{}
    }

    if ($null -eq $global:DNSValidatorHash) {
        $global:DNSValidatorHash = @{}
    }

    Write-Progress -Activity "SCCM Systems" -Status "Querying SCCM Servers" -PercentComplete 0
    
    # Query IM1 Domain (Primary)
    try {
        $domain = $DomainConfig['IM1']
        Write-Progress -Activity "SCCM Systems" -Status "Querying IM1 Domain" -PercentComplete 25
        Write-Verbose "Querying IM1 SCCM Server: $($domain.CMServer)"
        
        $query = "Select Name, IPAddresses, ResourceID, FullDomainName from SMS_R_System"
        $devices = Get-WmiObject -Query $query -Namespace $domain.Namespace -ComputerName $domain.CMServer -ErrorAction Stop

        Write-Progress -Activity "SCCM Systems" -Status "Processing IM1 Results" -PercentComplete 50
        $deviceCount = 0
        $totalDevices = $devices.Count

        foreach ($device in $devices) {
            $deviceCount++
            if ($deviceCount % 100 -eq 0) {
                $percentComplete = [math]::Min(75, 50 + ($deviceCount / $totalDevices * 25))
                Write-Progress -Activity "SCCM Systems" -Status "Processing IM1 Device $deviceCount of $totalDevices" -PercentComplete $percentComplete
            }

            $Global:CachedSystems[$device.Name] = @{
                DNSSuffix      = $domain.DNSSuffix
                IPAddresses    = $device.IPAddresses
                ResourceID     = $device.ResourceID
                FullDomainName = $device.FullDomainName
                Domain         = 'IM1'
            }
        }
        Write-Verbose "Cached $($devices.Count) devices from IM1"
    }
    catch {
        Write-Warning "IM1 SCCM Query failed: $($_.Exception.Message)"
    }

    # Query CVS Domain (Secondary)
    try {
        $domain = $DomainConfig['CVS']
        Write-Progress -Activity "SCCM Systems" -Status "Querying CVS Domain" -PercentComplete 75
        Write-Verbose "Querying CVS SCCM Server: $($domain.CMServer)"
        
        $query = "Select Name, IPAddresses, ResourceID, FullDomainName from SMS_R_System"
        $devices = Get-WmiObject -Query $query -Namespace $domain.Namespace -ComputerName $domain.CMServer -ErrorAction Stop

        Write-Progress -Activity "SCCM Systems" -Status "Processing CVS Results" -PercentComplete 85
        $deviceCount = 0
        $totalDevices = $devices.Count
        $addedDevices = 0

        foreach ($device in $devices) {
            $deviceCount++
            if ($deviceCount % 100 -eq 0) {
                $percentComplete = [math]::Min(99, 85 + ($deviceCount / $totalDevices * 14))
                Write-Progress -Activity "SCCM Systems" -Status "Processing CVS Device $deviceCount of $totalDevices (Added: $addedDevices)" -PercentComplete $percentComplete
            }

            if (-not $Global:CachedSystems.ContainsKey($device.Name)) {
                $Global:CachedSystems[$device.Name] = @{
                    DNSSuffix      = $domain.DNSSuffix
                    IPAddresses    = $device.IPAddresses
                    ResourceID     = $device.ResourceID
                    FullDomainName = $device.FullDomainName
                    Domain         = 'CVS'
                }
                $addedDevices++
            }
        }
        Write-Verbose "Added $addedDevices unique devices from CVS"
    }
    catch {
        Write-Warning "CVS SCCM Query failed: $($_.Exception.Message)"
    }

    # Save cache to file after queries complete
    Write-Progress -Activity "SCCM Systems" -Status "Cache Complete" -PercentComplete 100
    Write-Verbose "Total systems in cache: $($Global:CachedSystems.Count)"
    $global:DNSValidatorHash.allSystems = $Global:CachedSystems.Clone()
    
    # Export cache to file
    $Global:CachedSystems | Export-Clixml -Path $cachePath
    Write-Verbose "Saved cache to $cachePath"
    
    Write-Progress -Activity "SCCM Systems" -Completed

    return $Global:CachedSystems.Count -gt 0
} 