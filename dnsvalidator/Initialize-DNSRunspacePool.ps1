function Initialize-DNSRunspacePool {
    [CmdletBinding()]
    param()
    
    $initialSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
    
    # Import required functions and variables
    $initialSessionState.Variables.Add((New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList 'DNSValidatorConfig', $DNSValidatorConfig, ''))
    $initialSessionState.Variables.Add((New-Object System.Management.Automation.Runspaces.SessionStateVariableEntry -ArgumentList 'trustMap', $trustMap, ''))
    
    $runspacePool = [runspacefactory]::CreateRunspacePool(1, $DNSValidatorConfig.Performance.MaxRunspaces, $initialSessionState, $Host)
    $runspacePool.Open()
    
    Write-Verbose "DNS Validation runspace pool initialized with max capacity: $($DNSValidatorConfig.Performance.MaxRunspaces)"
    
    return $runspacePool
}
