function Get-IPHostInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string[]]$IPAddress,

        [Parameter(Mandatory = $false)]
        [string[]]$DNSServers = @(
            # CVS DNS Servers
            '15.97.197.92', # corsi-cvsdc02
            '15.97.196.29', # corsi-cvsdc03
            # IM1 DNS Servers
            '15.97.196.26', # im1dc01
            '15.97.196.27', # im1dc02
            '15.97.196.28', # im1dc03
            # Auth DNS Servers
            '15.97.196.30', # auth-dns01
            '15.97.196.31', # auth-dns02
            '15.97.196.32', # auth-dns03
            # Additional HP DNS
            '16.110.135.51', # hp.com
            '16.110.135.52'  # hp.com
        ),

        [Parameter(Mandatory = $false)]
        [int]$TimeoutSeconds = 2
    )

    process {
        $total = $IPAddress.Count
        $current = 0

        foreach ($ip in $IPAddress) {
            $current++
            $percentComplete = ($current / $total) * 100
            Write-Progress -Activity "Resolving IP Addresses" -Status "Processing $ip" -PercentComplete $percentComplete

            $result = [PSCustomObject]@{
                IPAddress  = $ip
                Hostname   = $null
                ReversePTR = $null
                DNSServer  = $null
                Status     = "Unknown"
            }

            # Try direct Windows DNS API first
            try {
                $winDNS = [System.Net.Dns]::GetHostEntry($ip)
                if ($winDNS.HostName) {
                    $result.Hostname = $winDNS.HostName
                    $result.Status = "Found"
                    $result.DNSServer = "Windows DNS"
                    $result | Write-Output
                    continue
                }
            } catch {
                Write-Verbose "Windows DNS lookup failed for $ip"
            }

            # Try each DNS server
            foreach ($dnsServer in $DNSServers) {
                try {
                    Write-Verbose "Querying $dnsServer for $ip"
                    $ptrRecord = Resolve-DnsName -Name $ip -Server $dnsServer -Type PTR -ErrorAction Stop -Timeout $TimeoutSeconds

                    if ($ptrRecord) {
                        $result.ReversePTR = $ptrRecord.NameHost
                        $result.DNSServer = $dnsServer
                        $result.Status = "Found"

                        # Try forward lookup to verify
                        try {
                            $forward = Resolve-DnsName -Name $ptrRecord.NameHost -Server $dnsServer -Type A -ErrorAction Stop -Timeout $TimeoutSeconds
                            if ($forward.IPAddress -contains $ip) {
                                $result.Hostname = $ptrRecord.NameHost
                                $result.Status = "Verified"
                                break # Found a valid record, stop checking other DNS servers
                            }
                        } catch {
                            Write-Verbose "Forward lookup failed for $($ptrRecord.NameHost)"
                        }
                    }
                } catch {
                    Write-Verbose "Query to $dnsServer failed: $_"
                }
            }

            # If still no results, try nslookup as last resort
            if ($result.Status -eq "Unknown") {
                try {
                    $nsLookup = nslookup $ip 2>$null
                    if ($nsLookup -match "name = (.+)") {
                        $result.Hostname = $matches[1].Trim()
                        $result.Status = "NSLookup"
                    }
                } catch {
                    Write-Verbose "NSLookup failed for $ip"
                }
            }

            $result
        }
        Write-Progress -Activity "Resolving IP Addresses" -Completed
    }
}
