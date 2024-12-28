NetworkValidation/
├── Core/
│ ├── Invoke-NetworkValidation.ps1 # Main menu & orchestration
│ ├── Get-SCCMInventory.ps1
│ └── Get-NetworkStatus.ps1
├── Data/
│ ├── OUI/ # MAC vendor database
│ │ ├── oui.txt
│ │ └── Create-OUIListFromWeb.ps1
│ └── Config/ # Configuration files
├── Validators/
│ ├── Invoke-NetworkPing.ps1
│ ├── Test-DomainResolution.ps1
│ ├── Get-InfoBloxIPInfo.ps1
│ └── IPv4NetworkScan.ps1
├── Reports/
│ ├── Export-ValidationReport.ps1
│ └── Templates/
└── README.md
