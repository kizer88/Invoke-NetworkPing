# Set working directory and repo URL
$repoPath = "D:\Pingz\Network-Ping"
$repoUrl = "https://github.com/kizer88/Invoke-NetworkPing"

# Initialize git if needed
Set-Location $repoPath
if (-not (Test-Path ".git")) {
    git init
    git remote add origin $repoUrl
}

# Stage all changes
git add .

# Commit with meaningful message
$commitMessage = "feat: Add DNS validation engine with multi-domain support
- Add DNS validation framework
- Implement parallel resolution
- Add trust-aware validation
- Include SCCM correlation
- Add detailed validation reporting"

git commit -m $commitMessage

# Push to main branch
git push origin main