function Invoke-DNSBatchProcessor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Targets,
        
        [switch]$ForceRefresh
    )
    
    $runspacePool = Initialize-DNSRunspacePool
    $jobs = [System.Collections.ArrayList]::new()
    $results = [System.Collections.ArrayList]::new()
    
    Write-Verbose "Processing $($Targets.Count) targets in batches of $($DNSValidatorConfig.Performance.BatchSize)"
    
    for ($i = 0; $i -lt $Targets.Count; $i += $DNSValidatorConfig.Performance.BatchSize) {
        $batch = $Targets[$i..([Math]::Min($i + $DNSValidatorConfig.Performance.BatchSize - 1, $Targets.Count - 1))]
        
        foreach ($target in $batch) {
            $domain = Get-TargetDomain -Target $target
            $job = Invoke-DNSResolutionWorker -Target $target -Domain $domain -RunspacePool $runspacePool -ForceRefresh:$ForceRefresh
            [void]$jobs.Add($job)
        }
        
        while ($jobs.Count -gt 0) {
            for ($j = $jobs.Count - 1; $j -ge 0; $j--) {
                if ($jobs[$j].Job.IsCompleted) {
                    $result = $jobs[$j].PowerShell.EndInvoke($jobs[$j].Job)
                    [void]$results.Add($result)
                    $jobs[$j].PowerShell.Dispose()
                    [void]$jobs.RemoveAt($j)
                }
            }
            if ($jobs.Count -gt 0) { Start-Sleep -Milliseconds 100 }
        }
        
        Write-Progress -Activity "DNS Resolution" -Status "Processed $($results.Count) of $($Targets.Count)" `
                      -PercentComplete (($results.Count / $Targets.Count) * 100)
    }
    
    $runspacePool.Close()
    $runspacePool.Dispose()
    
    return $results
}