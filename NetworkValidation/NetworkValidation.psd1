@{
    ModuleVersion     = '1.0'
    GUID              = 'bf84c454-e90f-45d5-9c49-2985a2ee94a1'
    Author            = 'Network Validation Team'
    Description       = 'Network Validation Tools for Multi-Domain Environments'
    PowerShellVersion = '5.1'
    RequiredModules   = @()
    FunctionsToExport = @(
        'Get-SCCMInventory',
        'Test-DomainResolution',
        'Test-NetworkConnection',
        'Test-IPv4Range',
        'Invoke-NetworkValidation',
        'Test-NetworkValidationSuite',
        'Get-InfoBloxIPInfo',
        'Get-MACVendor',
        'Start-FullNetworkAnalysis'
    )
    PrivateData       = @{
        PSData = @{
            Tags = @('Network', 'Validation', 'DNS', 'SCCM')
        }
    }
}
