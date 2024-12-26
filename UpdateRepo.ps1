# Set working directory and repo URL
$repoPath = "D:\Pingz\Network-Ping"
$repoUrl = "https://github.com/kizer88/Invoke-NetworkPing"

# Initialize git if needed
Set-Location $repoPath
if (-not (Test-Path ".git")) {
    git init
    git remote add origin $repoUrl
}

# Sync with remote first
git pull origin master

# Stage modified files
git add UpdateRepo.ps1
git add Validate-DnsResolution.ps1

# Get changes for commit message
$dnsChanges = git diff --cached Validate-DnsResolution.ps1
$commitMessage = "feat: DNS validation updates`n"

if ($dnsChanges -match "parallel") {
    $commitMessage += "- Enhanced parallel processing`n"
}
if ($dnsChanges -match "SCCM") {
    $commitMessage += "- Updated SCCM integration`n"
}
if ($dnsChanges -match "domain") {
    $commitMessage += "- Improved multi-domain handling`n"
}

# Commit and push
git commit -m $commitMessage
git push origin master
