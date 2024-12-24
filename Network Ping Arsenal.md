# 🚀 Network Ping Arsenal

> "Because sometimes you need to know if it's dead or just ignoring you"

A battle-tested network ping utility that handles multi-domain warfare across CVS and IM1 territories. Built for speed, resilience, and those moments when you need to know what's really going on in your network.

## 💥 Features That Actually Matter

- **Parallel Ping Operations** - Because life's too short for sequential pings
- **SCCM Integration** - Knows where the bodies are buried
- **Cross-Domain Support** - Plays nice with CVS and IM1 (most of the time)
- **Excel Reporting** - Makes management happy
- **Error Handling** - Catches chaos before it catches you

## 🎯 Quick Start

```powershell:D:\Pingz\Network-Ping\Invoke-NetworkPing.ps1
# Basic ping of a single computer
Invoke-NetworkPing -ComputerName "MYPC01"

# Multiple computers with Excel export
Invoke-NetworkPing -ComputerNames "MYPC01","MYPC02","MYPC03" -ExportToExcel

# Full arsenal deployment
Invoke-NetworkPing -ComputerNames (Get-Content .\computers.txt) -ExportToExcel -EmailReport -AdvancedPing


## ⚡ Performance

- Handles 1000+ targets without breaking a sweat
- Parallel execution with smart throttling
- Caches SCCM data because nobody likes waiting

## 🔧 Requirements

- PowerShell 5.1+
- ImportExcel module
- SCCM access rights (for system cache)
- A sense of humor

## 🛡️ Error Handling

When things go wrong (and they will), we've got you covered:

- Detailed error logging
- Smart retry logic
- Domain-aware error handling
- Actual useful error messages

## 📊 Output Example


# Sample Output Structure
{
    "Total_Targets": 150,
    "Online_Percent": "87.33%",
    "Online_Targets": 131,
    "Offline_Percent": "12.67%",
    "Offline_Targets": 19,
    "CVS_Targets": 75,
    "IM1_Targets": 75,
    "CVS_Targets_Online": 65,
    "IM1_Targets_Online": 66,
    "CVS_Targets_Offline": 10,
    "IM1_Targets_Offline": 9,
    "Execution_Time": "00:01:23"
}


## 🎭 Known Quirks

- Sometimes servers play dead
- DNS can be... creative
- The void occasionally stares back

## 🔥 Author

Created by someone who's pinged one too many dead servers

## 📜 License

MIT - Because sharing is caring
