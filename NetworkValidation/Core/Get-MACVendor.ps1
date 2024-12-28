function Get-MACVendor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$MACAddress,

        [Parameter()]
        [string]$OUIPath = "$PSScriptRoot\..\Data\OUI\oui.txt"
    )

    # Cache the OUI data in script scope if not already loaded
    if (-not $script:OUIHashTable) {
        $script:OUIHashTable = @{}
        if (Test-Path $OUIPath) {
            Get-Content $OUIPath | ForEach-Object {
                $parts = $_ -split '\|'
                if ($parts.Count -eq 2) {
                    $script:OUIHashTable[$parts[0]] = $parts[1]
                }
            }
        }
    }

    # Extract OUI from MAC
    $oui = ($MACAddress -replace '[-:]', '').Substring(0, 6).ToUpper()

    # Return vendor or unknown using standard PowerShell syntax
    if ($script:OUIHashTable.ContainsKey($oui)) {
        return $script:OUIHashTable[$oui]
    }
    return "Unknown"
}
