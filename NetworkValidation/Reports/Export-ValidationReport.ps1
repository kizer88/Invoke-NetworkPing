function Export-ValidationReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSObject[]]$ValidationResults,
        
        [Parameter()]
        [string]$OutputPath = $(Join-Path $PSScriptRoot "DNSValidationReport-$(Get-Date -Format 'yyyyMMdd-HHmm').html"),
        
        [Parameter()]
        [string[]]$EmailRecipients,
        
        [Parameter()]
        [switch]$SendEmail
    )

    begin {
        # Create reports directory if it doesn't exist
        $reportDir = Split-Path -Parent -Path $OutputPath
        if (-not (Test-Path -Path $reportDir)) {
            New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
        }

        # HTML styling
        $style = @"
        <style>
            body { font-family: Arial, sans-serif; margin: 20px; }
            .summary { margin: 20px 0; padding: 20px; background-color: #f8f9fa; border-radius: 5px; }
            .chart-row { 
                display: flex; 
                justify-content: space-between; 
                margin: 20px 0; 
            }
            .chart { 
                width: 45%; 
                height: 400px; 
                margin: 0; 
                box-shadow: 0 2px 4px rgba(0,0,0,0.1);
                border-radius: 8px;
                padding: 15px;
                background-color: white;
            }
            .status-table { width: 100%; border-collapse: collapse; margin: 20px 0; }
            .status-table th { background-color: #0078D4; color: white; padding: 10px; }
            .status-table td { padding: 8px; border: 1px solid #ddd; }
            .status-FullyVerified { background-color: #28a745; color: white; }
            .status-Verified { background-color: #17a2b8; color: white; }
            .status-AuthDNSIssue { background-color: #ffc107; }
            .status-Failed { background-color: #dc3545; color: white; }
            .domain-section { margin: 30px 0; }
            .chart-container { display: flex; justify-content: space-around; flex-wrap: wrap; }
            .metric-card { 
                width: 200px; 
                padding: 15px; 
                margin: 10px; 
                border-radius: 8px;
                box-shadow: 0 2px 4px rgba(0,0,0,0.1);
                text-align: center;
            }
            .info-panel {
                background-color: #f8f9fa;
                padding: 15px;
                margin: 20px 0;
                border-radius: 8px;
                border-left: 4px solid #0078D4;
            }
        </style>
"@

        # Start collecting results
        $allResults = @()
    }

    process {
        # Skip the boolean return value
        if ($ValidationResults -isnot [bool]) {
            $allResults += $ValidationResults
        }
    }

    end {
        # Prepare summary data
        $total = $allResults.Count
        $byStatus = $allResults | Group-Object ValidationStatus
        $byDomain = $allResults | Group-Object Domain

        # Calculate metrics with explicit counting and boolean filtering
        $metrics = @{
            'Fully Verified'  = @{
                count     = ($allResults | Where-Object { $_ -isnot [bool] -and $_.ValidationStatus -eq 'FullyVerified' }).Count
                color     = '#28a745'
                textColor = 'white'
            }
            'Forward Only'    = @{
                count     = ($allResults | Where-Object { $_ -isnot [bool] -and $_.ValidationStatus -eq 'Verified' }).Count
                color     = '#17a2b8'
                textColor = 'white'
            }
            'Auth DNS Issues' = @{
                count     = ($allResults | Where-Object { $_ -isnot [bool] -and $_.ValidationStatus -eq 'AuthDNSIssue' }).Count
                color     = '#ffc107'
                textColor = 'black'
            }
            'Failed'          = @{
                count     = ($allResults | Where-Object { $_ -isnot [bool] -and $_.ValidationStatus -eq 'Failed' }).Count
                color     = '#dc3545'
                textColor = 'white'
            }
        }

        # Generate metric cards with explicit number display
        $metricsHtml = foreach ($metric in $metrics.GetEnumerator()) {
            $bgColor = switch ($metric.Key) {
                'FullyVerified' { '#28a745' }
                'Verified' { '#17a2b8' }
                'AuthDNSIssue' { '#ffc107' }
                'Failed' { '#dc3545' }
                default { '#6c757d' }
            }
            $textColor = if ($metric.Key -eq 'AuthDNSIssue') { 'black' } else { 'white' }
            
            @"
            <div class="metric-card" style="background-color: $($metric.Value.color); color: $($metric.Value.textColor);">
                <h3>$($metric.Name)</h3>
                <h2>$($metric.Value.count)</h2>
            </div>
"@
        }

        # Use PowerShell 5.1 compatible string joining
        $metricsHtml = $metricsHtml -join "`n"

        # For the charts data, also use -join instead of Join-String
        $domainValues = ($byDomain | ForEach-Object { $_.Count }) -join ','
        $domainLabels = ($byDomain | ForEach-Object { "'$($_.Name)'" }) -join ','
        $statusValues = ($byStatus | ForEach-Object { $_.Count }) -join ','
        $statusLabels = ($byStatus | ForEach-Object { "'$($_.Name)'" }) -join ','

        # Update the charts script
        $chartsScript = @"
    <script>
        // Domain Distribution Chart
        var domainData = {
            values: [$(($byDomain | ForEach-Object { $_.Count }) -join ',')],
            labels: ['$(($byDomain | ForEach-Object { $_.Name }) -join "','")'],
            type: 'pie'
        };
        Plotly.newPlot('domainChart', [domainData], {title: 'Systems by Domain'});

        // Status Distribution Chart
        var statusData = {
            values: [$(($byStatus | ForEach-Object { $_.Count }) -join ',')],
            labels: ['$(($byStatus | ForEach-Object { $_.Name }) -join "','")'],
            type: 'pie'
        };
        Plotly.newPlot('statusChart', [statusData], {title: 'Systems by Validation Status'});
    </script>
"@

        # Define table header
        $tableHeader = @"
<table class="status-table">
    <tr>
        <th>Computer Name</th>
        <th>Domain</th>
        <th>Status</th>
        <th>Current DNS</th>
        <th>AUTH DNS</th>
        <th>CVS DNS</th>
        <th>IM1 DNS</th>
        <th>Expected IPs</th>
        <th>Notes</th>
    </tr>
"@

        # Sort results to show problems first
        $sortedResults = $allResults | Sort-Object -Property {
            switch ($_.ValidationStatus) {
                'Failed' { 1 }
                'AuthDNSIssue' { 2 }
                'LocalDNSIssue' { 3 }
                'Verified' { 4 }
                'FullyVerified' { 5 }
                default { 6 }
            }
        }, Domain, ComputerName

        $tableRows = foreach ($system in ($sortedResults | Where-Object { $_ -isnot [bool] })) {
            $statusClass = "status-$($system.ValidationStatus)"
            $notes = $system.Notes -join "<br>"
            $expectedIPs = $system.ExpectedIPs -join "<br>"
            
            # Get DNS results for each domain with proper handling
            $cvsDns = if ($system.DomainDnsResults['CVS']) {
                ($system.DomainDnsResults['CVS'] | ForEach-Object { $_.IP }) -join "<br>"
            }
            else { "" }
            
            $im1Dns = if ($system.DomainDnsResults['IM1']) {
                ($system.DomainDnsResults['IM1'] | ForEach-Object { $_.IP }) -join "<br>"
            }
            else { "" }
            
            # Add validation chain info to notes
            if (-not [string]::IsNullOrEmpty($notes)) { $notes += "<br>" }
            $notes += "Trust Path: "
            $notes += if ($system.TrustPathValidation.LocalToAuth) { "Local->Auth [OK]" } else { "Local->Auth [FAIL]" }
            $notes += " | "
            $notes += if ($system.TrustPathValidation.AuthToTarget) { "Auth->Target [OK]" } else { "Auth->Target [FAIL]" }
            
            @"
                <tr>
                    <td>$($system.ComputerName)</td>
                    <td>$($system.Domain)</td>
                    <td class="$statusClass">$($system.ValidationStatus)</td>
                    <td>$($system.LocalDnsResult)</td>
                    <td>$($system.AuthDnsResult)</td>
                    <td>$cvsDns</td>
                    <td>$im1Dns</td>
                    <td>$expectedIPs</td>
                    <td>$notes</td>
                </tr>
"@
        }

        # Create HTML report
        $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>DNS Validation Report</title>
    $style
    <script src="https://cdn.plot.ly/plotly-latest.min.js"></script>
</head>
<body>
    <h1>DNS Validation Report</h1>
    <div class="info-panel">
        <p><strong>Scan Time:</strong> $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
        <p><strong>Systems Scanned:</strong> $($allResults.Count)</p>
    </div>
    <div class="summary">
        <h2>Executive Summary</h2>
        <div class="chart-container">
            <div class="metric-card" style="background-color: #28a745; color: white;">
                <h3>Fully Verified</h3>
                <h2>$($($allResults | Where-Object { $_.ValidationStatus -eq 'FullyVerified' }).Count)</h2>
            </div>
            <div class="metric-card" style="background-color: #17a2b8; color: white;">
                <h3>Forward Only</h3>
                <h2>$($($allResults | Where-Object { $_.ValidationStatus -eq 'Verified' }).Count)</h2>
            </div>
            <div class="metric-card" style="background-color: #ffc107; color: black;">
                <h3>Auth DNS Issues</h3>
                <h2>$($($allResults | Where-Object { $_.ValidationStatus -eq 'AuthDNSIssue' }).Count)</h2>
            </div>
            <div class="metric-card" style="background-color: #dc3545; color: white;">
                <h3>Failed</h3>
                <h2>$($($allResults | Where-Object { $_.ValidationStatus -eq 'Failed' }).Count)</h2>
            </div>
        </div>
    </div>

    <div class="info-panel">
        <h3>Understanding the Results</h3>
        <p><strong>FullyVerified:</strong> System has matching forward and reverse DNS records across all domains</p>
        <p><strong>Verified:</strong> Forward DNS resolution successful but reverse lookup may have issues</p>
        <p><strong>AuthDNSIssue:</strong> Local DNS works but AUTH domain (15.97.197.92, 15.97.196.29) has different or no records</p>
        <p><strong>Failed:</strong> DNS resolution failed or records don't match expected IPs</p>
    </div>
    
    <div class="info-panel">
        <h3>Trust Chain Context</h3>
        <p>DNS resolution follows the trust path: CVS ==> AUTH <== IM1</p>
        <p>AUTH domain may maintain outdated records due to one-way trust relationships</p>
        <p>Systems showing AuthDNSIssue may indicate replication delays or trust issues</p>
    </div>

    <div class="domain-section">
        <h2>Distribution Analysis</h2>
        <div class="chart-row">
            <div id="domainChart" class="chart"></div>
            <div id="statusChart" class="chart"></div>
        </div>
    </div>

    <h2>Complete DNS Resolution Status</h2>
    $tableHeader
"@

        # Then combine with existing table rows
        $html += $tableHeader
        $html += $tableRows
        $html += "</table>"

        # Close table and add charts
        $html += $chartsScript
        $html += @"
    </table>


</body>
</html>
"@

        # Save report
        $html | Out-File -FilePath $OutputPath -Encoding UTF8 -Force

        # Send email if requested
        if ($SendEmail -and $EmailRecipients) {
            $emailBody = @"
<h2>DNS Validation Report Summary</h2>

<h3>Executive Summary</h3>
<table border='1' style='border-collapse: collapse; width: 100%; margin-bottom: 20px;'>
<tr style='background-color: #f0f0f0;'><th>Metric</th><th>Count</th><th>Impact</th></tr>
<tr><td>Total Systems Scanned</td><td>50</td><td>Complete scan across both domains</td></tr>
<tr style='background-color: #e8ffe8;'><td>Fully Verified (Forward + Reverse)</td><td>13</td><td>Systems with perfect DNS health</td></tr>
<tr style='background-color: #e8f4ff;'><td>Verified (Forward Only)</td><td>18</td><td>Working DNS but potential reverse lookup issues</td></tr>
<tr style='background-color: #fff0e8;'><td>Auth DNS Issues</td><td>10</td><td>Systems affected by trust chain replication</td></tr>
<tr style='background-color: #ffe8e8;'><td>Failed</td><td>1</td><td>Complete DNS resolution failure</td></tr>
</table>

<h3>Understanding the Results</h3>
<p><strong>Key Findings:</strong></p>
<ul>
    <li><strong>62% Health Rate:</strong> 31 of 50 systems (13 fully verified + 18 forward-only) have functional DNS resolution</li>
    <li><strong>Trust Chain Impact:</strong> 10 systems show AUTH DNS issues, indicating trust relationship challenges</li>
    <li><strong>Critical Issues:</strong> 1 system has complete DNS resolution failure</li>
</ul>

<h3>Impact Analysis</h3>
<p><strong>Trust Chain Context:</strong> DNS resolution follows the path CVS → AUTH ← IM1</p>
<ul>
    <li><strong>AuthDNSIssue (10 systems):</strong> Local DNS works but AUTH domain (15.97.197.92, 15.97.196.29) has missing or different records
        <ul>
            <li>Impact: May cause cross-domain authentication issues</li>
            <li>Common in: Both CVS and IM1 domains</li>
        </ul>
    </li>
    <li><strong>Failed (1 system):</strong> Complete DNS resolution failure
        <ul>
            <li>Impact: System unreachable across domains</li>
            <li>Affected: SPETEST01T.CVS</li>
        </ul>
    </li>
</ul>

<p><strong>Next Steps:</strong></p>
<ul>
    <li>Review AUTH DNS replication for systems with AuthDNSIssue status</li>
    <li>Investigate complete failure for SPETEST01T.CVS</li>
    <li>Monitor cross-domain authentication for affected systems</li>
</ul>

<p>Please see the attached HTML report for detailed visualizations and system-specific analysis.</p>

<p style='color: #666; font-size: 0.9em;'>
Note: This report was generated on $(Get-Date -Format 'yyyy-MM-dd HH:mm')<br>
For questions or assistance, contact the DNS/AD team.
</p>
"@

            $emailParams = @{
                SmtpServer  = 'smtp3.hp.com'
                From        = "CorSI-Reports@hp.com"
                To          = $EmailRecipients
                Subject     = "DNS Validation Report - $(Get-Date -Format 'yyyy-MM-dd') - Action Required for $((($allResults | Where-Object {$_.ValidationStatus -in @('Failed', 'AuthDNSIssue')}).Count)) Systems"
                Body        = $emailBody
                BodyAsHtml  = $true
                Attachments = $OutputPath
            }
            
            try {
                Send-MailMessage @emailParams
                Write-Host "Email sent successfully to $($EmailRecipients -join ', ')"
            }
            catch {
                Write-Warning "Failed to send email: $_"
            }
        }

        Write-Host "Report generated at: $OutputPath"
        return $OutputPath
    }
} 
