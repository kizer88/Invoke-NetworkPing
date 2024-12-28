function Get-InfoBloxIPInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [string[]]$IPAddress,

        [Parameter(Mandatory = $false)]
        [string]$PythonScript = "D:\Pingz\Network-Ping\NetworkValidation\Validators\infobox.py",

        [Parameter(Mandatory = $false)]
        [int]$ThrottleLimit = 10, # Adjust based on testing

        [Parameter(Mandatory = $false)]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential
    )

    begin {
        # Initialize progress tracking
        $script:totalIPs = 0
        $script:processedIPs = 0
        $script:progressId = Get-Random

        # Credential handling:
        # 1. Uses $Credential if explicitly passed
        # 2. Uses $mycr3Dz if available (encrypted credential store)
        # 3. Attempts to load $mycr3Dz from .WwanSvc if not loaded
        # 4. Prompts user for credentials if none of the above work
        if ((-not $mycr3Dz) -and (-not $Credential)) {
            $mycr3Dz = Read-Credential -Environment Development -Path "$env:USERPROFILE\.WwanSvc" -ErrorAction SilentlyContinue
            if (-not $mycr3Dz) {
                # If no credentials available, prompt for them
                if (-not $mycr3Dz) {
                    $Mycr3dz = Get-Credential -Message "Enter credentials for InfoBlox"
                }
            }
        } else {
            if ($mycr3Dz) {
                Write-Host "Using credentials from `$mycr3Dz" -ForegroundColor Cyan
            } elseif ($Credential) {
                Write-Host "Using credentials from `$Credential" -ForegroundColor Cyan
                $mycr3Dz = $Credential
            }
        }
    }

    process {
        $script:totalIPs += $IPAddress.Count
        Write-Progress -Id $progressId -Activity "InfoBlox IP Validation" -Status "Starting..." -PercentComplete 0

        $username = $mycr3Dz.UserName
        $password = $mycr3Dz.GetNetworkCredential().Password

        # Create runspace pool for parallel processing
        $runspacePool = [runspacefactory]::CreateRunspacePool(1, $ThrottleLimit)
        $runspacePool.Open()
        $runspaces = @()
        $results = [System.Collections.Concurrent.ConcurrentBag[PSObject]]::new()

        foreach ($ip in $IPAddress) {
            Write-Progress -Id $progressId -Activity "InfoBlox IP Validation" `
                -Status "Queuing $ip" `
                -PercentComplete (($script:processedIPs / $script:totalIPs) * 100)

            $powershell = [powershell]::Create().AddScript({
                    param($ip, $username, $password, $PythonScript)
                    try {
                        # Debug info
                        Write-Verbose "Starting InfoBlox query for IP: $ip"
                        Write-Verbose "Using Python script: $PythonScript"
                        Write-Verbose "Username: $username"

                        # Verify Python script exists
                        if (-not (Test-Path $PythonScript)) {
                            throw "Python script not found at: $PythonScript"
                        }

                        Write-Verbose "Executing Python command: python $PythonScript $ip $username [password]"
                        $result = python $PythonScript $ip $username $password | ConvertFrom-Json
                        Write-Verbose "Python execution complete"

                        if ($result) {
                            Write-Verbose "Got result from Python"
                            [PSCustomObject]@{
                                IPAddress      = $result.ip_address
                                Network        = $result.network
                                NetworkComment = $result.network_comment
                                Hostname       = $result.hostname
                                FQDN           = $result.fqdn
                                MACAddress     = $result.mac_address
                                Status         = $result.status
                                LeaseState     = $result.lease_state
                                Usage          = $result.usage -join ", "
                                Types          = $result.types -join ", "
                            }
                        } else {
                            Write-Warning "No result returned from Python script for IP: $ip"
                        }
                    } catch {
                        Write-Error "Error processing IP $ip : $_"
                        throw
                    }
                }).AddArgument($ip).AddArgument($username).AddArgument($password).AddArgument($PythonScript)

            $powershell.RunspacePool = $runspacePool

            $runspaces += @{
                PowerShell = $powershell
                Handle     = $powershell.BeginInvoke()
                IP         = $ip
                StartTime  = Get-Date
            }
        }
    }

    end {
        while ($runspaces) {
            $completed = $runspaces | Where-Object { $_.Handle.IsCompleted }

            foreach ($runspace in $completed) {
                $script:processedIPs++

                # Calculate completion percentage and elapsed time
                $percentComplete = ($script:processedIPs / $script:totalIPs) * 100
                $elapsedTime = New-TimeSpan -Start $runspace.StartTime -End (Get-Date)

                Write-Progress -Id $progressId -Activity "InfoBlox IP Validation" `
                    -Status "Processing $($runspace.IP) | Elapsed: $($elapsedTime.ToString('hh\:mm\:ss'))" `
                    -PercentComplete $percentComplete `
                    -CurrentOperation "$script:processedIPs of $script:totalIPs IPs processed"

                try {
                    Write-Verbose "Getting results for IP: $($runspace.IP)"
                    $result = $runspace.PowerShell.EndInvoke($runspace.Handle)

                    # Check for errors after completion
                    if ($runspace.PowerShell.Streams.Error.Count -gt 0) {
                        Write-Warning "Errors occurred processing $($runspace.IP):"
                        $runspace.PowerShell.Streams.Error | ForEach-Object {
                            Write-Warning $_.ToString()
                        }
                    }

                    if ($result) {
                        $results.Add($result)
                        Write-Verbose "Added result for IP: $($runspace.IP)"
                    }
                } catch {
                    Write-Warning "Error processing results for $($runspace.IP): $_"
                } finally {
                    $runspace.PowerShell.Dispose()
                }
            }

            $runspaces = $runspaces | Where-Object { -not $_.Handle.IsCompleted }
            Start-Sleep -Milliseconds 100
        }

        Write-Progress -Id $progressId -Activity "InfoBlox IP Validation" -Status "Complete" -PercentComplete 100 -Completed

        $runspacePool.Close()
        $runspacePool.Dispose()

        return $results
    }
}
