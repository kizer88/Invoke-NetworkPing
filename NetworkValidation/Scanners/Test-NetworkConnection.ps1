



function Test-NetworkConnection {
    <#
    .SYNOPSIS
    Pings things. Sometimes they ping back. Life is full of disappointments.

    .DESCRIPTION
    Like a corporate email thread that never ends, this function pings computers 
    across domains until something responds or your patience runs out.

    .PARAMETER ComputerNames
    The victims... err, targets of our ping requests.

    .PARAMETER ExportToExcel
    Because management needs pretty spreadsheets to understand failure.

    .PARAMETER EmailReport
    Automatically disappoints your inbox.

    .PARAMETER AdvancedPing
    When regular ping just isn't painful enough.
    #>

    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [ValidateNotNullOrEmpty()]
        [string[]]$ComputerNames,

        [switch]$ExportToExcel,
        [switch]$EmailReport,
        [switch]$AdvancedPing
    )

    [string[]]$ComputerNames = @($ComputerNames)
    
    
    $ComputerNames = @($ComputerNames | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    
    if ($ComputerNames.Count -eq 0) {
        throw "No valid computer names provided after filtering empty values."
    }

    Write-Verbose "Processing $($ComputerNames.Count) computer names"

    
    if (-not (Test-Path variable:\global:syncHash)) {
        $global:syncHash = [hashtable]::Synchronized(@{
                AsyncResult        = [System.Collections.ArrayList]::new()
                OnlineCount        = 0
                OfflineCount       = 0
                TotalCount         = 0
                OnlineDevices      = @()
                OfflineDevices     = @()
                CVS_OnlineDevices  = @()
                IM1_OnlineDevices  = @()
                CVS_OfflineDevices = @()
                IM1_OfflineDevices = @()
                PingErrors         = @{}
                PingErrorCount     = 0
                finalResult        = @()
                allSystems         = @{}
                DNSCache           = @{}
                SystemCache        = @{}
                summary            = @{}
            })
    }

    
    $config = @{
        Domains       = @{
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
        MaxRunspaces  = [Math]::Min(32, [Math]::Max(1, [Environment]::ProcessorCount * 2))
        BatchSize     = 50
        Timeouts      = @{
            Ping = 1000  
            WMI  = 30000  
            DNS  = 1000   
        }
        ExportPath    = "C:\Reports\PingResults.xlsx"
        LogPath       = "C:\Logs\operation.log"
        EmailSettings = @{
            SmtpServer = 'smtp.hpicorp.net'
            From       = 'no-reply@hpicorp.net'
            To         = 'networkteam@hpicorp.net'
            Subject    = 'Network Ping Report'
            Body       = 'Please find the attached network ping report.'
        }
    }

    function Add-SyncHashError {
        [CmdletBinding()]
        param (
            [Parameter(Mandatory)]
            [string]$Target,
        
            [Parameter(Mandatory)]
            [System.Management.Automation.ErrorRecord]$ErrorRecord,
        
            [string]$Operation = "Unknown",
        
            [ValidateSet('Error', 'Warning', 'Critical')]
            [string]$Severity = 'Error',

            [string]$Component = (Get-Variable -Name Component -ValueOnly -ErrorAction SilentlyContinue)
        )

        
        if (-not $global:syncHash.ContainsKey('ErrorLog')) {
            $global:syncHash.ErrorLog = [System.Collections.ArrayList]@()
        }
        if (-not $global:syncHash.ContainsKey('ErrorCount')) {
            $global:syncHash.ErrorCount = 0
        }

        
        $global:syncHash.ErrorCount++

        
        $errorObject = [PSCustomObject]@{
            ID         = $global:syncHash.ErrorCount
            Timestamp  = Get-Date
            Component  = $Component
            Line       = $MyInvocation.ScriptLineNumber
            Target     = $Target
            Operation  = $Operation
            Message    = $ErrorRecord.Exception.Message
            FullError  = $ErrorRecord.Exception.ToString()
            Severity   = $Severity
            ScriptName = $MyInvocation.ScriptName
            CallStack  = Get-PSCallStack | Select-Object -First 3 | ConvertTo-Json
        }

        
        [void]$global:syncHash.ErrorLog.Add($errorObject)

        Write-Verbose "Error #$($global:syncHash.ErrorCount) in $Component at line $($MyInvocation.ScriptLineNumber): $($ErrorRecord.Exception.Message)"

        return $errorObject
    }
    
    try {
        Import-Module -Name ImportExcel -ErrorAction Stop
        Write-Verbose "Imported ImportExcel module successfully."
    }
    catch {
        Add-SyncHashError -Target "ImportExcel" -ErrorRecord $_ -Operation "Module Import" -Severity "Critical"
        return
    }


    
    function Log-Operation {
        param (
            [string]$Operation,
            [string]$Target,
            [string]$Result,
            [int]$Duration,
            [string]$ErrorCode
        )
        $logEntry = @{
            Timestamp = Get-Date
            Operation = $Operation
            Target    = $Target
            Result    = $Result
            Duration  = $Duration
            ErrorCode = $ErrorCode
        }
        
        $logDir = Split-Path -Path $config.LogPath
        if (-not (Test-Path -Path $logDir)) {
            try {
                New-Item -ItemType Directory -Path $logDir -Force | Out-Null
                Write-Verbose "Created log directory at $logDir"
            }
            catch {
                Write-Error "Failed to create log directory at $logDir. Error: $_"
                return
            }
        }
        
        try {
            $logEntry | ConvertTo-Json | Out-File -FilePath $config.LogPath -Append -Encoding UTF8
            Write-Verbose "Logged operation: $Operation on Target: $Target with Result: $Result"
        }
        catch {
            Write-Error "Failed to write to log file at $config.LogPath. Error: $_"
        }

        
        if ($Result -ne "Success") {
            $global:syncHash.PingErrors[$Target] = @{
                Operation = $Operation
                Result    = $Result
                Duration  = $Duration
                ErrorCode = $ErrorCode
            }
        }
    }

    
    function Initialize-Cache {
        Write-Verbose "Initializing cache..."
        
        
        Remove-Variable -Name syncHash -Scope Global -ErrorAction SilentlyContinue
        
        $global:syncHash = [hashtable]::Synchronized(@{
                
                AsyncResult        = [System.Collections.ArrayList]::new()
                OnlineDevices      = [System.Collections.ArrayList]::new()
                OfflineDevices     = [System.Collections.ArrayList]::new()
                CVS_OnlineDevices  = [System.Collections.ArrayList]::new()
                CVS_OfflineDevices = [System.Collections.ArrayList]::new()
                IM1_OnlineDevices  = [System.Collections.ArrayList]::new()
                IM1_OfflineDevices = [System.Collections.ArrayList]::new()
                
                
                OnlineCount        = 0
                OfflineCount       = 0
                TotalCount         = 0
                ErrorCount         = 0
                
                
                allSystems         = @{}
                
                
                PingErrors         = @{}
                
                
                summary            = @{}
            })
    }

    
    if ($null -eq $Global:CachedSystems) {
        $Global:CachedSystems = $null
    }

    function Get-SCCMInventory {
        Write-Verbose "Checking for cached SCCM data..."
        
        
        if ($null -ne $Global:CachedSystems) {
            Write-Progress -Activity "SCCM Systems" -Status "Using cached data" -PercentComplete 100
            Write-Verbose "Using cached SCCM data with $($Global:CachedSystems.Count) systems"
            $global:syncHash.allSystems = $Global:CachedSystems.Clone()
            return
        }
        Write-Progress -Activity "SCCM Systems" -Status "Querying SCCM Servers" -PercentComplete 0
        Write-Verbose "No cached data found, querying SCCM servers..."
        $Global:CachedSystems = @{}
    
        
        try {
            $domain = $config.Domains['IM1']
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
            Add-SyncHashError -Target $domain.CMServer -ErrorRecord $_ -Operation "IM1 SCCM Query"
        }
    
        
        try {
            $domain = $config.Domains['CVS']
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
            Add-SyncHashError -Target $domain.CMServer -ErrorRecord $_ -Operation "CVS SCCM Query"
        }
    
        Write-Progress -Activity "SCCM Systems" -Status "Cache Complete" -PercentComplete 100
        Write-Verbose "Total systems in cache: $($Global:CachedSystems.Count)"
        $global:syncHash.allSystems = $Global:CachedSystems.Clone()
        Write-Progress -Activity "SCCM Systems" -Completed
    }
    
    function Get-ProperFQDN {
        param(
            [string]$ComputerName
        )

        
        if ($ComputerName -match "^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$") {
            Write-Verbose "ComputerName '$ComputerName' is an IP address. Returning as-is."
            return $ComputerName 
        }

        if ($ComputerName -match "\.") {
            Write-Verbose "ComputerName '$ComputerName' is already a FQDN. Returning as-is."
            return $ComputerName 
        }

        
        if ($global:syncHash.allSystems.ContainsKey($ComputerName)) {
            $sccmData = $global:syncHash.allSystems[$ComputerName]
            if (![string]::IsNullOrEmpty($sccmData.FullDomainName)) {
                Write-Verbose "Resolved FQDN for '$ComputerName' from SCCM: $($sccmData.FullDomainName)"
                return $sccmData.FullDomainName
            }
            
            Write-Verbose "Constructing FQDN for '$ComputerName' using DNS suffix: $($sccmData.DNSSuffix)"
            return "$ComputerName.$($sccmData.DNSSuffix)"
        }

        
        Write-Verbose "Constructing FQDN for '$ComputerName' using primary domain suffix: $($config.Domains['IM1'].DNSSuffix)"
        return "$ComputerName.$($config.Domains['IM1'].DNSSuffix)"
    }

    
    function Execute-Pings {
        param([switch]$UseAdvancedPing)

        Write-Verbose "Executing pings..."
        foreach ($computer in $ComputerNames) {
            Write-Verbose "Processing computer: $computer"
            $fqdn = Get-ProperFQDN -ComputerName $computer
            
            try {
                $ping = New-Object System.Net.NetworkInformation.Ping
                Write-Verbose "Pinging computer: ${computer} with FQDN: $fqdn"
                $result = $ping.Send($fqdn, $config.Timeouts.Ping)
                
                
                $pingResult = [PSCustomObject]@{
                    ComputerName = $computer
                    FQDN         = $fqdn
                    Status       = $result.Status.ToString()
                    ResponseTime = if ($result.Status -eq 'Success') { $result.RoundtripTime } else { $null }
                    TimeStamp    = Get-Date
                }
                
                Write-Verbose "Ping result for ${computer}: StatusCode = $($result.Status), ResponseTime = $($result.RoundtripTime)"
                
                
                Log-Operation -Operation "Ping" -Target $fqdn -Result $result.Status.ToString() -Duration $result.RoundtripTime
                
                
                [void]$global:syncHash.AsyncResult.Add($pingResult)
            }
            catch {
                Write-Verbose "Error pinging $computer : $_"
                
                $errorResult = [PSCustomObject]@{
                    ComputerName = $computer
                    FQDN         = $fqdn
                    Status       = "Error"
                    ResponseTime = $null
                    TimeStamp    = Get-Date
                }
                [void]$global:syncHash.AsyncResult.Add($errorResult)
                Log-Operation -Operation "Ping" -Target $fqdn -Result "Error" -ErrorCode "PING_ERROR"
            }
        }
    }
    
    function Process-Results {
        Write-Verbose "Processing results..."
        
        
        $global:syncHash.OnlineCount = 0
        $global:syncHash.OfflineCount = 0
        $global:syncHash.TotalCount = $global:syncHash.AsyncResult.Count

        
        $global:syncHash.OnlineDevices.Clear()
        $global:syncHash.OfflineDevices.Clear()
        $global:syncHash.CVS_OnlineDevices.Clear()
        $global:syncHash.CVS_OfflineDevices.Clear()
        $global:syncHash.IM1_OnlineDevices.Clear()
        $global:syncHash.IM1_OfflineDevices.Clear()

        
        foreach ($result in $global:syncHash.AsyncResult) {
            $domain = if ($result.FQDN -match 'IM1\.MFG\.HPICORP\.NET$') { 'IM1' } else { 'CVS' }
            
            if ($result.Status -eq 'Success') {
                $global:syncHash.OnlineCount++
                [void]$global:syncHash.OnlineDevices.Add($result.ComputerName)
                
                if ($domain -eq 'IM1') {
                    [void]$global:syncHash.IM1_OnlineDevices.Add($result.ComputerName)
                }
                else {
                    [void]$global:syncHash.CVS_OnlineDevices.Add($result.ComputerName)
                }
            }
            else {
                $global:syncHash.OfflineCount++
                [void]$global:syncHash.OfflineDevices.Add($result.ComputerName)
                
                if ($domain -eq 'IM1') {
                    [void]$global:syncHash.IM1_OfflineDevices.Add($result.ComputerName)
                }
                else {
                    [void]$global:syncHash.CVS_OfflineDevices.Add($result.ComputerName)
                }
            }
        }

        $global:AsyncResult = $global:syncHash.AsyncResult 
        
        
        $global:syncHash.summary = [ordered]@{
            Total_Targets       = $global:syncHash.TotalCount
            Online_Percent      = if ($global:syncHash.TotalCount -gt 0) { "{0:P2}" -f ($global:syncHash.OnlineCount / $global:syncHash.TotalCount) } else { "0.00%" }
            Online_Targets      = $global:syncHash.OnlineCount
            Offline_Percent     = if ($global:syncHash.TotalCount -gt 0) { "{0:P2}" -f ($global:syncHash.OfflineCount / $global:syncHash.TotalCount) } else { "0.00%" }
            Offline_Targets     = $global:syncHash.OfflineCount
            CVS_Targets         = ($global:syncHash.CVS_OnlineDevices.Count + $global:syncHash.CVS_OfflineDevices.Count)
            IM1_Targets         = ($global:syncHash.IM1_OnlineDevices.Count + $global:syncHash.IM1_OfflineDevices.Count)
            CVS_Targets_Online  = $global:syncHash.CVS_OnlineDevices.Count
            IM1_Targets_Online  = $global:syncHash.IM1_OnlineDevices.Count
            CVS_Targets_Offline = $global:syncHash.CVS_OfflineDevices.Count
            IM1_Targets_Offline = $global:syncHash.IM1_OfflineDevices.Count
            Execution_Time      = (Get-Date) - $script:StartTime
        }
        
        Write-Verbose "Result Processing Completed."
    }

    
    function Export-ToExcel {
        Write-Verbose "Exporting results to Excel..."
        $excelPath = $config.ExportPath
        
        $exportDir = Split-Path -Path $excelPath
        if (-not (Test-Path -Path $exportDir)) {
            try {
                New-Item -ItemType Directory -Path $exportDir -Force | Out-Null
                Write-Verbose "Created export directory at $exportDir"
            }
            catch {
                Add-SyncHashError -Target $excelPath -ErrorRecord $_ -Operation "Excel Export" -Severity "Critical"
            }
        }

        
        $global:syncHash.detailedResults = $global:syncHash.AsyncResult | Where-Object { $_.FQDN -ne $null -and $_.FQDN -ne "" -and $_.Result -ne $null }

        try {
            $global:syncHash.detailedResults | Export-Excel -Path $excelPath -AutoSize -Title "Network Ping Results" -WorksheetName "Results" -ClearSheet
            Write-Output "Results exported to Excel at $excelPath"
            Write-Verbose "Export to Excel completed."
        }
        catch {
            Add-SyncHashError -Target $excelPath -ErrorRecord $_ -Operation "Excel Export" -Severity "Critical"
        }
    }

    
    function Send-EmailReport {
        param (
            [string]$AttachmentPath
        )

        $emailSettings = $config.EmailSettings

        try {
            Send-MailMessage -SmtpServer $emailSettings.SmtpServer `
                -From $emailSettings.From `
                -To $emailSettings.To `
                -Subject $emailSettings.Subject `
                -Body $emailSettings.Body `
                -Attachments $AttachmentPath -ErrorAction Stop
            Write-Output "Email report sent successfully to $($emailSettings.To)."
            Write-Verbose "Email sent."
        }
        catch {
            Add-SyncHashError -Target $emailSettings.To -ErrorRecord $_ -Operation "Email Report" -Severity "Warning"
        }
    }

    
    try {
        $script:StartTime = Get-Date
        Write-Verbose "Starting Network Ping Operations..."

        Initialize-Cache
        Get-SCCMInventory
        Execute-Pings -UseAdvancedPing:$AdvancedPing.IsPresent
        Process-Results

        if ($ExportToExcel) {
            Export-ToExcel
        }

        if ($EmailReport -and $ExportToExcel) {
            Send-EmailReport -AttachmentPath $config.ExportPath
        }

        
        if ($ComputerNames.Count -eq 1) {
            
            Write-Host "Network ping operations completed successfully." -ForegroundColor Green
            return $global:syncHash.AsyncResult[0]  
        }
        else {
            
            Write-Host "Network ping operations completed successfully." -ForegroundColor Green
            return $global:syncHash.summary
        }

        
        if ($global:syncHash.PingErrors.Count -gt 0) {
            Write-Host "`n----- Failed Pings -----" -ForegroundColor Yellow
            $global:syncHash.PingErrors.GetEnumerator() | ForEach-Object {
                Write-Host "Target: $($_.Key)"
                Write-Host "Operation: $($_.Value.Operation)"
                Write-Host "Result: $($_.Value.Result)"
                Write-Host "Duration: $($_.Value.Duration)"
                Write-Host "Error Code: $($_.Value.ErrorCode)"
                Write-Host "------------------------"
            }
        }
    }
    catch {
        Add-SyncHashError -Target "Main Execution" -ErrorRecord $_ -Operation "Script Execution" -Severity "Critical"
    }
}





